#!/usr/bin/env python3
"""Freeze, render and compare an editable complex-goods workspace. See README.md.

Requires Pillow/numpy and Blender. This tool never installs or approves assets.
Builder ABI: source/<entry> -- OUTPUT GOOD; writes GOOD_raw.png, its _mask,
GOOD.blend and metrics.json. The workspace contains project.json and source/.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

from PIL import Image, ImageChops, ImageDraw


def read(path):
    return json.loads(path.read_text())


def write(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def local(root, relative):
    path = (root / relative).resolve()
    if not path.is_relative_to(root.resolve()):
        raise ValueError(f"Path must stay inside workspace: {relative}")
    return path


def config(root):
    cfg = read(root / "project.json")
    if cfg.get("schema_version") != 1 or not re.fullmatch(r"[a-z][a-z0-9_]*", cfg["good"]):
        raise ValueError("Expected schema_version 1 and a snake_case good name")
    for key in ("entry", "exporter"):
        if not local(root / "source", cfg[key]).is_file():
            raise ValueError(f"Missing source {key}: {cfg[key]}")
    declared_references = [cfg["reference"]] + [item["path"] for item in cfg.get("real_references", [])]
    for relative in declared_references:
        path = local(root, relative)
        if not path.is_file() or not path.is_relative_to((root / "references").resolve()):
            raise ValueError(f"Save every reference under references/ so it is frozen: {relative}")
    if len(cfg.get("regions", [])) < 4:
        raise ValueError("Define at least four anatomical reference/candidate crop pairs")
    names = [item["name"] for item in cfg["regions"]]
    if len(names) != len(set(names)) or any(not re.fullmatch(r"[a-z0-9_]+", name) for name in names):
        raise ValueError("Each crop needs a unique lowercase name using letters, digits or underscores")
    return cfg


def hashes(root):
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(root.rglob("*")) if p.is_file() and "__pycache__" not in p.parts}


def input_hashes(root):
    result = {"project.json": hashlib.sha256((root / "project.json").read_bytes()).hexdigest()}
    for directory in ("source", "references"):
        result.update({f"{directory}/{name}": digest for name, digest in hashes(root / directory).items()})
    return result


def run(command, log):
    with log.open("w") as stream:
        subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, check=True)


def render(root, cfg, out, blender):
    out.mkdir()
    run([blender, "--background", "--factory-startup", "--python-exit-code", "1",
         "--python", str(local(root / "source", cfg["entry"])), "--", str(out), cfg["good"]],
        out / "blender.log")
    good = cfg["good"]
    for name in (f"{good}_raw.png", f"{good}_raw_mask.png", f"{good}.blend", "metrics.json"):
        if not (out / name).is_file():
            raise ValueError(f"Builder did not produce {name}; inspect {out / 'blender.log'}")
    metrics = read(out / "metrics.json")
    angles = metrics.get("camera_degrees", [])
    if len(angles) != 3 or any(abs(a - b) > .01 for a, b in zip(angles, (54.7356, 0, 45))):
        raise ValueError("Fixed isometric camera check failed")
    with Image.open(out / f"{good}_raw.png") as raw, Image.open(out / f"{good}_raw_mask.png") as mask:
        if raw.size != mask.size or raw.mode != "RGBA" or not raw.getbbox():
            raise ValueError("Invalid color/mask pair")
        # Ignore the transparent background: a white object on black is still a broken mask.
        values = [v for v, a in zip(mask.convert("L").getdata(), raw.getchannel("A").getdata()) if a > 250]
        if not values or max(values) - min(values) < 8:
            raise ValueError("Shading mask is uniform on the subject")
    return metrics


def export(root, cfg, out):
    good = cfg["good"]
    run([sys.executable, str(local(root / "source", cfg["exporter"])),
         str(out / f"{good}_raw.png"), str(out / f"{good}_800.png"),
         "--contour", str(cfg["contour"]), "--vib", str(cfg["vibrance"])], out / "export.log")
    with Image.open(out / f"{good}_800.png") as master:
        if master.size != (800, 800) or master.mode != "RGBA":
            raise ValueError("Exporter must produce transparent 800x800 RGBA")
        for size in (450, 400, 256, 60):
            master.resize((size, size), Image.Resampling.LANCZOS).save(out / f"{good}_{size}.png")


def tile(path, size):
    with Image.open(path) as raw:
        im = raw.convert("RGBA")
    im.thumbnail((size, size), Image.Resampling.LANCZOS)
    bg = Image.new("RGB", (size, size), (244, 241, 234))
    bg.paste(im, ((size - im.width) // 2, (size - im.height) // 2), im)
    return bg


def proof(root, cfg, out, previous):
    good = cfg["good"]
    columns = [("Original goods icon", local(root, cfg["reference"]))]
    if previous:
        columns.append(("Previous", previous / "render" / f"{good}_800.png"))
    columns.append(("Candidate", out / f"{good}_800.png"))
    board = Image.new("RGB", (400 * len(columns), 500), (244, 241, 234))
    draw = ImageDraw.Draw(board)
    for i, (label, path) in enumerate(columns):
        draw.text((i * 400 + 12, 10), label, fill=(20, 28, 60))
        board.paste(tile(path, 400), (i * 400, 32))
        board.paste(tile(path, 60), (i * 400 + 170, 432))
    board.save(out / "comparison.png")
    crops = out / "crops"
    crops.mkdir()
    for item in cfg["regions"]:
        if not re.fullmatch(r"[a-z0-9_]+", item["name"]):
            raise ValueError("Crop names must use lowercase letters, digits or underscores")
        row = []
        for label, path in columns:
            with Image.open(path) as raw:
                box = item["reference"] if label == "Original goods icon" else item["candidate"]
                if len(box) != 4 or not (0 <= box[0] < box[2] <= raw.width and 0 <= box[1] < box[3] <= raw.height):
                    raise ValueError(f"Invalid crop for {item['name']}: {box}")
                crop = raw.convert("RGBA").crop(box)
            crop = crop.resize((crop.width * 3, crop.height * 3), Image.Resampling.NEAREST)
            row.append((label, crop))
        sheet = Image.new("RGB", (sum(im.width for _, im in row), max(im.height for _, im in row) + 30), (244, 241, 234))
        d = ImageDraw.Draw(sheet)
        x = 0
        for label, im in row:
            d.text((x + 8, 8), label, fill=(20, 28, 60))
            sheet.paste(im, (x, 30), im)
            x += im.width
        sheet.save(crops / f"{item['name']}_3x.png")
    if previous:
        with Image.open(previous / "render" / f"{good}_800.png") as old, Image.open(out / f"{good}_800.png") as new:
            diff = ImageChops.difference(old.convert("RGBA"), new.convert("RGBA"))
            combined = Image.new("L", diff.size)
            for channel in diff.split():
                combined = ImageChops.lighter(combined, channel)
            combined.save(out / "changed_pixels.png")
            write(out / "delta.json", {"changed_bbox": combined.getbbox(),
                  "changed_pixel_count": sum(v > 0 for v in combined.getdata()),
                  "note": "Pixel change is evidence of a change, not evidence that the owner's request is met."})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    init = sub.add_parser("init", help="Copy a seed into a new editable workspace")
    init.add_argument("seed", type=Path)
    init.add_argument("workspace", type=Path)
    bake = sub.add_parser("round", help="Freeze sources and make a review candidate")
    bake.add_argument("workspace", type=Path)
    bake.add_argument("name")
    bake.add_argument("--brief", required=True, help="Owner request and observable acceptance criterion")
    bake.add_argument("--previous", help="Earlier round name for before/after proof")
    bake.add_argument("--blender", default=os.environ.get("BLENDER_BIN", "/Applications/Blender.app/Contents/MacOS/Blender"))
    verify = sub.add_parser("verify", help="Rebuild only from a frozen round and compare pixels")
    verify.add_argument("round", type=Path)
    verify.add_argument("--blender", default=os.environ.get("BLENDER_BIN", "/Applications/Blender.app/Contents/MacOS/Blender"))
    args = parser.parse_args()
    if args.action == "init":
        seed = args.seed.resolve()
        config(seed)
        if args.workspace.exists():
            raise ValueError("Workspace already exists; refusing to replace edits")
        args.workspace.mkdir(parents=True)
        shutil.copy2(seed / "project.json", args.workspace / "project.json")
        for name in ("source", "references"):
            shutil.copytree(seed / name, args.workspace / name, ignore=shutil.ignore_patterns("__pycache__"))
        (args.workspace / ".gdignore").touch()
        print(f"Editable workspace: {args.workspace.resolve()}")
        return
    if args.action == "round":
        workspace = args.workspace.resolve()
        cfg = config(workspace)
        if not re.fullmatch(r"[a-zA-Z0-9_-]+", args.name):
            raise ValueError("Use a simple round name")
        previous = local(workspace / "rounds", args.previous) if args.previous else None
        if previous and not (previous / "render" / f"{cfg['good']}_800.png").is_file():
            raise ValueError("Previous round is missing its master")
        root = workspace / "rounds" / args.name
        root.mkdir(parents=True, exist_ok=False)
        for name in ("source", "references"):
            shutil.copytree(workspace / name, root / name, ignore=shutil.ignore_patterns("__pycache__"))
        shutil.copy2(workspace / "project.json", root / "project.json")
        write(root / "revision.json", {"brief": args.brief, "previous": args.previous,
              "status": "candidate", "inputs": input_hashes(root)})
        out = root / "render"
        render(root, cfg, out, args.blender)
        export(root, cfg, out)
        proof(root, cfg, out, previous)
        (root / "review.md").write_text("Owner request: " + args.brief + "\n\nCandidate awaiting visual review. Record MET / PARTLY / NOT for the request, measured evidence, regressions and the next action. Tool checks do not confer visual approval.\n")
        print(f"Review candidate: {out / 'comparison.png'}")
        return
    root = args.round.resolve()
    cfg = config(root)
    revision = read(root / "revision.json")
    if input_hashes(root) != revision["inputs"]:
        raise ValueError("Frozen inputs changed (modified, missing or added files)")
    out = root / "repeat"
    render(root, cfg, out, args.blender)
    export(root, cfg, out)
    checks = {}
    for suffix in ("raw", "raw_mask", "800", "450", "400", "256", "60"):
        name = f"{cfg['good']}_{suffix}.png"
        with Image.open(root / "render" / name) as first, Image.open(out / name) as second:
            same = first.mode == second.mode and first.size == second.size and first.tobytes() == second.tobytes()
        checks[name] = same
    write(root / "verification.json", {"identical_pixels": checks, "passed": all(checks.values())})
    if not all(checks.values()):
        raise ValueError("Rebuild differs; inspect verification.json")
    print("PASS: frozen source reproduces color, mask and all five export sizes")


if __name__ == "__main__":
    main()
