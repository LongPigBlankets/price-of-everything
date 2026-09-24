#!/usr/bin/env python3
"""Compare Building Detail v3 screenshots against the saved standard.

tools/bdp_v3_shot.tscn writes the panel's views as poe_bdp_v3_<view>.png (into /tmp, or
$BDP_SHOT_DIR). The standard is a saved set of those views in artifacts/bdp_v3_standard/, with
the measurements taken from them in metrics.json. Every visual change to v3 is checked against it:

    python3 tools/bdp_v3_compare.py                 # compare /tmp's captures with the standard
    python3 tools/bdp_v3_compare.py --save          # make /tmp's captures the new standard

For each view the comparison reports how much of the panel changed and by how much, and writes
standard | current | difference images (the difference amplified four times, in red) and a
contact sheet into --out. It also compares the measurements:

    lamp       the light of the lamp over the panel in a 3 x 4 grid (the "top" view against
               "top_unlit": 1.0 is unlit)
    steel      the median brightness of the steel down the panel's left and right edges (the
               backing and the frames on it), every 100 px, in "top"
"""
import argparse
import json
import shutil
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
STANDARD = HERE.parent / "artifacts" / "bdp_v3_standard"
PREFIX = "poe_bdp_v3_"
CHANGED = 8.0   # a pixel counts as changed when its luminance moves by more than this (0-255)


def lum(img):
    a = np.asarray(img.convert("RGB")).astype(float)
    return 0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]


def views(folder):
    return {p.name[len(PREFIX):-4]: p for p in sorted(Path(folder).glob(PREFIX + "*.png"))}


def measure(folder):
    """The lamp grid and the steel profiles, from a folder's top and top_unlit views."""
    v = views(folder)
    out = {}
    if "top" in v and "top_unlit" in v:
        lit, unlit = lum(Image.open(v["top"])), lum(Image.open(v["top_unlit"]))
        ratio = (lit + 1.0) / (unlit + 1.0)
        h, w = ratio.shape
        out["lamp"] = [[round(float(np.median(ratio[int(h * (r + 0.3) / 4):int(h * (r + 0.7) / 4),
                                                        int(w * (c + 0.3) / 3):int(w * (c + 0.7) / 3)])), 3)
                        for c in range(3)] for r in range(4)]
    if "top" in v:
        top = lum(Image.open(v["top"]))
        h, w = top.shape
        cols = {"left": (int(w * 0.03), int(w * 0.06)), "right": (int(w * 0.93), int(w * 0.965))}
        out["steel"] = {name: [round(float(np.median(top[y - 5:y + 5, x0:x1])), 1) for y in range(60, h - 20, 100)]
                        for name, (x0, x1) in cols.items()}
    return out


def triptych(std, cur):
    a, b = std.convert("RGB"), cur.convert("RGB")
    if b.size != a.size:
        b = b.resize(a.size, Image.LANCZOS)
    d = np.abs(lum(a) - lum(b))
    heat = np.zeros((a.height, a.width, 3), np.uint8)
    heat[..., 0] = np.clip(d * 4.0, 0, 255).astype(np.uint8)
    heat[..., 1] = (lum(a) * 0.25).astype(np.uint8)
    heat[..., 2] = heat[..., 1]
    out = Image.new("RGB", (a.width * 3 + 40, a.height), (12, 14, 18))
    out.paste(a, (0, 0))
    out.paste(b, (a.width + 20, 0))
    out.paste(Image.fromarray(heat), (a.width * 2 + 40, 0))
    return out, float((d > CHANGED).mean() * 100.0), float((lum(b) - lum(a)).mean())


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--current", default="/tmp", help="folder with the new poe_bdp_v3_*.png captures")
    ap.add_argument("--standard", default=str(STANDARD))
    ap.add_argument("--out", default="/tmp/bdp_v3_compare", help="where the difference images go")
    ap.add_argument("--save", action="store_true", help="make the current captures the standard")
    args = ap.parse_args()

    cur = views(args.current)
    if not cur:
        raise SystemExit(f"no {PREFIX}*.png captures in {args.current}")
    std_dir = Path(args.standard)
    if args.save:
        std_dir.mkdir(parents=True, exist_ok=True)
        for old in std_dir.glob(PREFIX + "*.png"):
            old.unlink()
        for path in cur.values():
            shutil.copy2(path, std_dir / path.name)
        (std_dir / "metrics.json").write_text(json.dumps(measure(std_dir), indent=1) + "\n")
        print(f"saved {len(cur)} views as the standard in {std_dir}")
        return

    std = views(std_dir)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    sheets = []
    print(f"{'view':<22}{'changed %':>10}{'mean dL':>9}")
    for name, path in std.items():
        if name not in cur:
            print(f"{name:<22}{'missing':>10}")
            continue
        img, changed, dl = triptych(Image.open(path), Image.open(cur[name]))
        img.save(out / f"{name}.png")
        sheets.append(img)
        print(f"{name:<22}{changed:>10.1f}{dl:>+9.1f}")
    for name in sorted(set(cur) - set(std)):
        print(f"{name:<22}{'new view':>10}")

    before = json.loads((std_dir / "metrics.json").read_text()) if (std_dir / "metrics.json").exists() else {}
    after = measure(args.current)
    if "lamp" in before and "lamp" in after:
        print("\nlamp (3 x 4 grid, standard -> current)")
        for rb, ra in zip(before["lamp"], after["lamp"]):
            print("   " + "   ".join(f"{b:.3f}->{a:.3f}" for b, a in zip(rb, ra)))
    if "steel" in before and "steel" in after:
        print("\nsteel brightness down the edges (standard -> current)")
        for side in ("left", "right"):
            pairs = zip(before["steel"][side], after["steel"][side])
            print(f"   {side:<6}" + " ".join(f"{b:.0f}->{a:.0f}" for b, a in pairs))
    if sheets:
        w = max(s.width for s in sheets)
        thumbs = [s.resize((w // 3, int(s.height * (w // 3) / s.width))) for s in sheets]
        sheet = Image.new("RGB", (w // 3, sum(t.height + 10 for t in thumbs)), (12, 14, 18))
        y = 0
        for t in thumbs:
            sheet.paste(t, (0, y))
            y += t.height + 10
        sheet.save(out / "contact_sheet.png")
        print(f"\ndifference images in {out}")


if __name__ == "__main__":
    main()
