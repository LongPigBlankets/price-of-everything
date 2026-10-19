#!/usr/bin/env python3
"""Make, check and export the demo build.

The demo is the regular game exported through a "<platform> Demo" preset: a copy of the
regular preset with the `demo` feature tag and the files in excludes.txt left out.

  build_demo.py sync      rewrite the Demo presets in export_presets.cfg from the regular ones
  build_demo.py check     exit 1 when the Demo presets are out of date (no writes)
  build_demo.py export    sync, export every Demo preset, verify, and zip each platform
  build_demo.py verify    re-run the checks on an existing export folder

Run it from anywhere; paths resolve from this file. Godot is found as $GODOT, then `godot`
on PATH, then the macOS app bundle.
"""
import argparse
import fnmatch
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
PRESETS = PROJECT / "export_presets.cfg"
EXCLUDES = HERE / "excludes.txt"
DEMO_SCRIPT = PROJECT / "scripts/demo_build.gd"
SMOKE = PROJECT.parent / "tools/ci/run_startup_smoke.py"
FEATURE = "demo"
SUFFIX = " Demo"
ALWAYS_STARTS = {"index.json", "default.json", "tutorial.json"}
# Regular preset name -> (folder label, executable file name).
PLATFORMS = {
    "macOS": ("MacOS", "Carbon and Capital.app"),
    "Windows Desktop": ("Windows", "Carbon and Capital.exe"),
    "Linux": ("Linux", "Carbon and Capital.x86_64"),
}
HEADER = re.compile(r"^\[preset\.(\d+)(\.options)?\]$", re.MULTILINE)


# ── Preset file ──────────────────────────────────────────────────────────────────────

def read_presets(text: str) -> list[dict]:
    """Split export_presets.cfg into presets, each {index, main, options} (raw bodies)."""
    marks = list(HEADER.finditer(text))
    presets: dict[int, dict] = {}
    for i, mark in enumerate(marks):
        end = marks[i + 1].start() if i + 1 < len(marks) else len(text)
        body = text[mark.end():end]
        entry = presets.setdefault(int(mark[1]), {"index": int(mark[1]), "main": "", "options": ""})
        entry["options" if mark[2] else "main"] = body
    return [presets[k] for k in sorted(presets)]


def write_presets(presets: list[dict]) -> str:
    """Sections separated by one blank line, as the Godot editor writes them."""
    out = []
    for p in presets:
        out.append(f"[preset.{p['index']}]\n\n{p['main'].strip(chr(10))}\n")
        out.append(f"[preset.{p['index']}.options]\n\n{p['options'].strip(chr(10))}\n")
    return "\n".join(out)


def field(body: str, key: str) -> str:
    match = re.search(rf'^{re.escape(key)}="(.*)"$', body, re.MULTILINE)
    if match is None:
        raise SystemExit(f"export_presets.cfg: preset is missing {key}")
    return match[1]


def set_field(body: str, key: str, value: str) -> str:
    return re.sub(rf'^{re.escape(key)}=".*"$', lambda _: f'{key}="{value}"', body,
                  count=1, flags=re.MULTILINE)


# ── What the demo leaves out ─────────────────────────────────────────────────────────

def demo_start_ids() -> list[str]:
    match = re.search(r"^const START_IDS: Array = \[([^\]]*)\]", DEMO_SCRIPT.read_text(), re.MULTILINE)
    if match is None:
        raise SystemExit("scripts/demo_build.gd: START_IDS not found")
    return re.findall(r'"([^"]+)"', match[1])


def demo_excludes() -> list[str]:
    globs = [line.strip() for line in EXCLUDES.read_text().splitlines()
             if line.strip() and not line.strip().startswith("#")]
    index = json.loads((PROJECT / "data/starts/index.json").read_text())
    keep = set(ALWAYS_STARTS)
    for start in index["starts"]:
        if start["id"] in demo_start_ids():
            keep.add(Path(start["file"].removeprefix("res://")).name)
    globs += sorted(f"data/starts/{p.name}" for p in (PROJECT / "data/starts").glob("*.json")
                    if p.name not in keep)
    active = (PROJECT / "data/map_authored/active.txt").read_text().strip()
    globs += sorted(f"data/map_authored/{p.name}" for p in (PROJECT / "data/map_authored").glob("*.json")
                    if p.stem != active)
    return globs


def demo_preset(base: dict, index: int) -> dict:
    main = set_field(base["main"], "name", field(base["main"], "name") + SUFFIX)
    main = set_field(main, "custom_features", FEATURE)
    regular = [g for g in field(base["main"], "exclude_filter").split(",") if g]
    merged = regular + [g for g in demo_excludes() if g not in regular]
    main = set_field(main, "exclude_filter", ",".join(merged))
    main = set_field(main, "export_path", "")
    return {"index": index, "main": main, "options": base["options"]}


def synced_text() -> str:
    presets = read_presets(PRESETS.read_text())
    regular = [p for p in presets if not field(p["main"], "name").endswith(SUFFIX)]
    for i, p in enumerate(regular):
        p["index"] = i
    demos = [demo_preset(p, len(regular) + i) for i, p in enumerate(regular)
             if field(p["main"], "name") in PLATFORMS]
    return write_presets(regular + demos)


# ── Godot ────────────────────────────────────────────────────────────────────────────

def godot() -> str:
    for candidate in (os.environ.get("GODOT"), shutil.which("godot"),
                      "/Users/crisu/Desktop/Godot.app/Contents/MacOS/Godot"):
        if candidate and Path(candidate).exists():
            return candidate
    raise SystemExit("Godot not found: set $GODOT")


def project_version() -> str:
    match = re.search(r'^config/version="([^"]+)"', (PROJECT / "project.godot").read_text(), re.MULTILINE)
    return match[1] if match else "dev"


def project_files() -> list[str]:
    out = []
    for root, dirs, files in os.walk(PROJECT):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        rel = Path(root).relative_to(PROJECT)
        for name in files:
            if not name.endswith((".import", ".uid")):
                out.append(str(rel / name) if str(rel) != "." else name)
    return out


def pck_expectations() -> dict:
    """Concrete res:// paths that must be absent from / present in a demo pack."""
    files = project_files()
    absent = sorted({f for g in demo_excludes() for f in files if fnmatch.fnmatch(f, g)})
    index = json.loads((PROJECT / "data/starts/index.json").read_text())
    present = [s["file"].removeprefix("res://") for s in index["starts"] if s["id"] in demo_start_ids()]
    present += [f"data/starts/{n}" for n in sorted(ALWAYS_STARTS)]
    active = (PROJECT / "data/map_authored/active.txt").read_text().strip()
    present += [f"data/map_authored/{active}.json", "data/Goods - goodsMVP.csv",
                "data/recipes_all.csv", "scripts/demo_build.gd", "scripts/debug_terminal.gd",
                "scenes/main_menu.tscn", "scenes/main.tscn"]
    # Rows addons/demo_export/demo_data_filter.gd must have taken out of the shipped files.
    gated = [m for m in re.findall(r'"(b_\d+)": true', DEMO_SCRIPT.read_text())]
    absent_text = [["res://data/Buildings - buildingsMVP.csv", f"\n{b},"] for b in gated]
    absent_text += [["res://data/recipes_all.csv", ",recycling_plant,"],
                    ["res://data/recipes_all.csv", ",consumer_goods_factory,"],
                    ["res://data/recipes_all.csv", ",water_treatment_plant,"],
                    ["res://data/research_unlocks.csv", "research_recyc_"],
                    ["res://data/research_presentation.json", "research_recyc_"]]
    return {"absent": ["res://" + p for p in absent], "present": ["res://" + p for p in present],
            "absent_text": absent_text}


def demo_building_count() -> int:
    """Buildings a demo run loads: every buildings CSV row minus the gated ids."""
    gated = set(re.findall(r'"(b_\d+)": true', DEMO_SCRIPT.read_text()))
    rows = (PROJECT / "data/Buildings - buildingsMVP.csv").read_text().splitlines()[1:]
    return sum(1 for r in rows if r.strip() and r.split(",")[0] not in gated)


PCK_CHECK = """extends SceneTree
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	if not ProjectSettings.load_resource_pack(args[0], false):
		print("PCKCHECK cannot mount ", args[0]); quit(2); return
	var bad := 0
	for p in spec.absent:
		if FileAccess.file_exists(p) or ResourceLoader.exists(p):
			print("PCKCHECK shipped but excluded: ", p); bad += 1
	for p in spec.present:
		if not (FileAccess.file_exists(p) or ResourceLoader.exists(p)):
			print("PCKCHECK missing: ", p); bad += 1
	for pair in spec.absent_text:
		if FileAccess.get_file_as_string(pair[0]).contains(pair[1]):
			print("PCKCHECK gated row shipped: ", pair[0], " contains ", pair[1].strip_edges()); bad += 1
	print("PCKCHECK %d absent, %d present, %d gated rows checked, %d problems" % [spec.absent.size(), spec.present.size(), spec.absent_text.size(), bad])
	quit(1 if bad else 0)
"""


def check_pack(pack: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="cnc-pck-") as tmp:
        tmp_path = Path(tmp)
        (tmp_path / "project.godot").write_text('config_version=5\n\n[application]\nconfig/name="pckcheck"\n')
        (tmp_path / "check.gd").write_text(PCK_CHECK)
        spec = tmp_path / "spec.json"
        spec.write_text(json.dumps(pck_expectations()))
        result = subprocess.run([godot(), "--headless", "--path", str(tmp_path), "--script", "check.gd",
                                 "--", str(pack), str(spec)], capture_output=True, text=True)
        lines = [l for l in result.stdout.splitlines() if l.startswith("PCKCHECK")]
        print("\n".join(lines[-40:]))
        if result.returncode != 0:
            raise SystemExit(f"pack check failed: {pack}")


def smoke_macos(app: Path, logs: Path) -> None:
    """Boot a copy of the .app twice (EULA, then main menu) and require the demo flavour."""
    spec = importlib.util.spec_from_file_location("run_startup_smoke", SMOKE)
    smoke = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(smoke)
    import hashlib
    logs.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="cnc-demo-") as tmp:
        isolated = Path(tmp)
        copy = isolated / app.name
        shutil.copytree(app, copy, symlinks=True)
        exe = next((copy / "Contents/MacOS").iterdir())
        smoke.run_game([str(exe)], isolated, logs, "fresh", 180)
        agreement = (PROJECT / "data/legal/demo_eula.txt").read_text(encoding="utf-8").strip()
        version = re.search(r'^const VERSION := "([^"]+)"', (PROJECT / "scripts/demo_eula.gd").read_text(),
                            re.MULTILINE)[1]
        record = isolated / "savegames/demo_eula.cfg"
        record.parent.mkdir(parents=True, exist_ok=True)
        record.write_text(f'[agreement]\nversion="{version}"\n'
                          f'sha256="{hashlib.sha256(agreement.encode()).hexdigest()}"\n', encoding="utf-8")
        smoke.run_game([str(exe)], isolated, logs, "accepted", 180)
        console = (logs / "accepted-console.log").read_text(errors="replace")
        if "[STARTUP] build demo" not in console.splitlines():
            raise SystemExit("the exported macOS build did not start as the demo")
        want = f"Catalog: loaded {demo_building_count()} buildings"
        if want not in console.splitlines():
            raise SystemExit(f"the exported macOS demo did not report '{want}'")
    print(f"macOS demo boots to the EULA and the main menu as the demo (logs: {logs})")


# ── Commands ─────────────────────────────────────────────────────────────────────────

def cmd_sync(_: argparse.Namespace) -> int:
    text = synced_text()
    if text != PRESETS.read_text():
        PRESETS.write_text(text)
        print("export_presets.cfg: Demo presets updated")
    else:
        print("export_presets.cfg: Demo presets already up to date")
    return 0


def cmd_check(_: argparse.Namespace) -> int:
    if synced_text() != PRESETS.read_text():
        print("Demo presets are out of date: run python3 tools/demo_build/build_demo.py sync")
        return 1
    print("Demo presets are up to date")
    return 0


def folder_for(out: Path, label: str) -> Path:
    return out / f"Carbon and Capital V{project_version()} Demo {label}"


def cmd_export(args: argparse.Namespace) -> int:
    cmd_sync(args)
    out = args.out.expanduser().resolve()
    for preset, (label, exe) in PLATFORMS.items():
        if args.platforms and label.lower() not in args.platforms:
            continue
        folder = folder_for(out, label)
        if folder.exists():
            shutil.rmtree(folder)
        folder.mkdir(parents=True)
        print(f"exporting {preset}{SUFFIX} -> {folder / exe}", flush=True)
        result = subprocess.run([godot(), "--headless", "--path", str(PROJECT), "--export-release",
                                 preset + SUFFIX, str(folder / exe)])
        if result.returncode != 0 or not (folder / exe).exists():
            raise SystemExit(f"export failed: {preset}{SUFFIX}")
    return cmd_verify(args)


def cmd_verify(args: argparse.Namespace) -> int:
    out = args.out.expanduser().resolve()
    for preset, (label, exe) in PLATFORMS.items():
        if args.platforms and label.lower() not in args.platforms:
            continue
        folder = folder_for(out, label)
        if label == "MacOS":
            app = folder / exe
            pack = next((app / "Contents/Resources").glob("*.pck"))
        elif label == "Windows":
            pack = next(folder.glob("*.pck"))
        else:
            pack = folder / exe
        print(f"checking {label} pack {pack.name}", flush=True)
        check_pack(pack)
        if label == "MacOS" and sys.platform == "darwin" and not args.no_smoke:
            smoke_macos(folder / exe, out / "logs" / label)
        if args.zip:
            archive = out / f"Carbon and Capital V{project_version()} Demo - {label}.zip"
            archive.unlink(missing_ok=True)
            if label == "MacOS":
                subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(folder),
                                str(archive)], check=True)
            else:
                subprocess.run(["zip", "-q", "-r", "-X", str(archive), folder.name], cwd=out, check=True)
            print(f"zipped {archive}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("sync").set_defaults(func=cmd_sync)
    sub.add_parser("check").set_defaults(func=cmd_check)
    for name, func in (("export", cmd_export), ("verify", cmd_verify)):
        p = sub.add_parser(name)
        p.add_argument("--out", type=Path, default=Path("~/Desktop/Carbon and Capital Demo builds"))
        p.add_argument("--platforms", type=lambda s: [x.strip().lower() for x in s.split(",")],
                       help="comma list of macos, windows, linux (default: all)")
        p.add_argument("--zip", action="store_true", help="zip each platform folder for upload")
        p.add_argument("--no-smoke", action="store_true", help="skip booting the macOS build")
        p.set_defaults(func=func)
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
