#!/usr/bin/env python3
"""Make, check and export the demo build.

The demo is the regular game exported through a "<platform> Demo" preset: a copy of the
regular preset with the `demo` feature tag and the files in excludes.txt left out.

  build_demo.py sync      rewrite the Demo presets in export_presets.cfg from the regular ones
  build_demo.py check     exit 1 when the Demo presets are out of date (no writes)
  build_demo.py export    sync, stage, export every Demo preset, verify, and zip each platform
  build_demo.py verify    re-run the checks on an existing export folder
  build_demo.py stage     only make the staged demo source (see below), and parse-check it;
                          --keep-excluded leaves tools/ and tests/ in it for probes

The demo is exported from a staged copy of the project: an APFS clone (a plain copy
elsewhere) in which every `# demo:strip` ... `# demo:end` region of a .gd file is removed.
Lines between `# demo:keep` and `# demo:end` are the demo's replacement: each is written
`#| <code>` and appears uncommented in the stage. Regions do not nest.

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
FORBIDDEN = HERE / "forbidden.txt"
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
STAGE_MARKER = "demo_stage.txt"
STRIP_BEGIN = re.compile(r"^\s*# demo:strip\b")
STRIP_KEEP = re.compile(r"^\s*# demo:keep\b")
STRIP_END = re.compile(r"^\s*# demo:end\b")
KEEP_LINE = re.compile(r"^(\s*)#\| ?")
STRIPPED_DIRS = ("scripts", "scenes", "addons")


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
    icons = PROJECT / "assets/icons/research/nodes"
    globs += sorted(f"assets/icons/research/nodes/{i}.png" for i in gated_research_ids() if (icons / f"{i}.png").exists())
    return globs


def gated_research_ids() -> set[str]:
    """Research nodes the demo leaves out (demo_data_filter.gd gated_research_ids)."""
    import csv
    text = DEMO_SCRIPT.read_text()
    category = re.search(r'^const GATED_RESEARCH_CATEGORY := "([^"]+)"', text, re.MULTILINE)[1]
    actions = re.findall(r'"([^"]+)"', re.search(r"^const GATED_RESEARCH_ACTIONS: Array = \[([^\]]*)\]",
                                                  text, re.MULTILINE)[1])
    hidden = re.search(r"^const HIDDEN_RESEARCH_IDS := \{(.*?)^\}", (PROJECT / "scripts/research_state.gd").read_text(),
                       re.MULTILINE | re.DOTALL)[1]
    out = set(re.findall(r'"(research_[a-z0-9_]+)"', hidden))
    with open(PROJECT / "data/research_unlocks.csv", newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if row["category"].strip() == category or row["Action"].strip() in actions:
                out.add(row["research_node_id"].strip())
    return out


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


# ── Staged source ────────────────────────────────────────────────────────────────────

def strip_source(text: str, name: str) -> str:
    """The demo's version of a script: strip regions removed, keep regions uncommented."""
    out, state, opened = [], None, 0
    for number, line in enumerate(text.splitlines(keepends=True), 1):
        if STRIP_BEGIN.match(line):
            if state:
                raise SystemExit(f"{name}:{number}: demo:strip inside the region opened at line {opened}")
            state, opened = "strip", number
        elif STRIP_KEEP.match(line):
            if state != "strip":
                raise SystemExit(f"{name}:{number}: demo:keep outside a demo:strip region")
            state = "keep"
        elif STRIP_END.match(line):
            if not state:
                raise SystemExit(f"{name}:{number}: demo:end without demo:strip")
            state = None
        elif state == "keep":
            match = KEEP_LINE.match(line)
            if match:
                out.append(match[1] + line[match.end():])
            elif line.strip():
                raise SystemExit(f"{name}:{number}: a demo:keep line must start with '#|'")
            else:
                out.append(line)
        elif state is None:
            out.append(line)
    if state:
        raise SystemExit(f"{name}:{opened}: demo:strip is never closed")
    return "".join(out)


SECTION = re.compile(r"^\[(\w+)([^\]]*)\]\s*$")
ATTR = re.compile(r'(\w+)="([^"]*)"')


def strip_scene(text: str, name: str, excluded) -> str:
    """Drop ext_resources whose file the demo leaves out, the nodes using one as their
    script (with their children) and those nodes' connections. Any other use of a dropped
    resource stops the build: the scene would not load."""
    sections, current = [], []
    for line in text.splitlines(keepends=True):
        if SECTION.match(line) and current:
            sections.append(current)
            current = []
        current.append(line)
    if current:
        sections.append(current)
    dropped_ids, dropped_nodes, kept = set(), [], []
    for sec in sections:
        head = SECTION.match(sec[0])
        attrs = dict(ATTR.findall(head[2])) if head else {}
        if head and head[1] == "ext_resource" and excluded(attrs.get("path", "").removeprefix("res://")):
            dropped_ids.add(attrs.get("id", ""))
            continue
        kept.append((head, attrs, sec))
    if not dropped_ids:
        return text
    out = []
    for head, attrs, sec in kept:
        body = "".join(sec[1:])
        if head and head[1] == "node":
            parent = attrs.get("parent")
            path = attrs.get("name", "") if parent in (None, ".") else f"{parent}/{attrs.get('name', '')}"
            if parent is not None and any(parent == d or parent.startswith(d + "/") for d in dropped_nodes):
                dropped_nodes.append(path)
                continue
            if any(f'script = ExtResource("{i}")' in body for i in dropped_ids):
                dropped_nodes.append(path)
                continue
        if head and head[1] == "connection":
            ends = (attrs.get("from", ""), attrs.get("to", ""))
            if any(e == d or e.startswith(d + "/") for e in ends for d in dropped_nodes):
                continue
        for i in dropped_ids:
            if f'ExtResource("{i}")' in "".join(sec):
                raise SystemExit(f"{name}: {sec[0].strip()} uses a resource the demo leaves out")
        out.append("".join(sec))
    print(f"  {name}: dropped nodes {', '.join(dropped_nodes) or 'none'}", flush=True)
    return "".join(out)


def marked_scripts(root: Path) -> list[Path]:
    found = []
    for folder in STRIPPED_DIRS:
        for path in sorted((root / folder).rglob("*.gd")):
            if "# demo:" in path.read_text(encoding="utf-8", errors="replace"):
                found.append(path)
    return found


def stage(stage_dir: Path, keep_excluded: bool = False) -> Path:
    """Clone the project to stage_dir, strip the marked regions, parse-check, return its path."""
    staged = stage_dir / PROJECT.name
    if stage_dir.exists():
        shutil.rmtree(stage_dir)
    stage_dir.mkdir(parents=True)
    clone = ["cp", "-cRp"] if sys.platform == "darwin" else ["cp", "-a", "--reflink=auto"]
    subprocess.run(clone + [str(PROJECT), str(staged)], check=True)
    changed = 0
    for path in marked_scripts(staged):
        rel = path.relative_to(staged)
        text = path.read_text(encoding="utf-8")
        demo = strip_source(text, str(rel))
        if demo != text:
            path.write_text(demo, encoding="utf-8")
            changed += 1
    globs = demo_excludes()
    excluded = lambda rel: any(fnmatch.fnmatch(rel, g) for g in globs)
    for folder in ("scenes", "scripts"):
        for scene in sorted((staged / folder).rglob("*.tscn")):
            text = scene.read_text(encoding="utf-8")
            demo = strip_scene(text, str(scene.relative_to(staged)), excluded)
            if demo != text:
                scene.write_text(demo, encoding="utf-8")
    (staged / STAGE_MARKER).write_text("Staged demo source. Made by tools/demo_build/build_demo.py.\n")
    print(f"staged {staged} ({changed} scripts stripped)", flush=True)
    result = subprocess.run([godot(), "--headless", "--path", str(staged), "res://tools/parse_check.tscn",
                             "--quit-after", "600"], capture_output=True, text=True)
    summary = [l for l in result.stdout.splitlines() if l.startswith("[parse_check]")]
    failed = [m[1] for l in summary if (m := re.search(r"FAILED\s+res://(\S+)", l))]
    shipped = [f for f in failed if not excluded(f)]
    totals = [l for l in summary if "scripts," in l]
    print("\n".join(totals[-1:]) + f" ({len(failed) - len(shipped)} of them in files the demo leaves out)", flush=True)
    if shipped or not totals:
        print("\n".join(f"FAILED {f}" for f in shipped))
        raise SystemExit("the staged demo source does not parse")
    # parse_check skips autoloads; a broken one shows as a parse error at boot.
    boot = subprocess.run([godot(), "--headless", "--path", str(staged), "--quit-after", "5", "--", "--as-demo"],
                          capture_output=True, text=True)
    errors = [l for l in (boot.stdout + boot.stderr).splitlines()
              if re.search(r"Parse Error|SCRIPT ERROR|Failed to load script|Compile Error", l)]
    if errors:
        print("\n".join(errors[:20]))
        raise SystemExit("the staged demo source has autoload errors at boot")
    print("staged autoloads boot without errors", flush=True)
    if keep_excluded:
        return staged
    # Delete what the demo leaves out, so the caches the export rebuilds (the UID and class
    # caches, which are packed) list only shipped files. The export plugin and the marker stay.
    keep = ("addons/demo_export/*", STAGE_MARKER)
    demo_globs = [g for g in field(next(p for p in read_presets(PRESETS.read_text())
                                         if field(p["main"], "name") == "Linux" + SUFFIX)["main"],
                                   "exclude_filter").split(",") if g]
    removed = 0
    for path in sorted(staged.rglob("*"), reverse=True):
        rel = str(path.relative_to(staged))
        if rel.startswith(".godot") or not path.is_file() or any(fnmatch.fnmatch(rel, k) for k in keep):
            continue
        source = rel.removesuffix(".import").removesuffix(".uid")
        if any(fnmatch.fnmatch(source, g) for g in demo_globs):
            path.unlink()
            removed += 1
    # CSVs imported as translations are never read by the game (it reads its CSVs raw), and
    # their importer is the one that crashes on odd files: drop them before the export scan.
    for imp in sorted(staged.rglob("*.csv.import")):
        if 'importer="csv_translation"' in imp.read_text(encoding="utf-8", errors="replace"):
            imp.with_suffix("").unlink(missing_ok=True)
            imp.unlink()
            removed += 1
    for cache in ("uid_cache.bin", "global_script_class_cache.cfg"):
        (staged / ".godot" / cache).unlink(missing_ok=True)
    print(f"deleted {removed} excluded files from the stage; caches rebuild on export", flush=True)
    return staged


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


def forbidden_strings() -> list[str]:
    import csv
    out = [l.strip() for l in FORBIDDEN.read_text().splitlines() if l.strip() and not l.strip().startswith("#")]
    gated = re.findall(r'"(g_\d+)": true', DEMO_SCRIPT.read_text())
    with open(PROJECT / "data/Goods - goodsMVP.csv", newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if row["ID"] in gated:
                # A plain-word internal name ("scrap") also lives inside kept names such as
                # Scrap Preheating Towers; its display name covers it.
                out += [row["display_name"]] + ([row["internal_name"]] if "_" in row["internal_name"] else [])
    return out


def read_pack(path: Path) -> tuple[bytes, list[tuple[str, int, int]]]:
    """A Godot 4 pack's bytes and its (name, offset, size) directory; standalone or embedded."""
    import struct
    data = path.read_bytes()
    start = 0
    if not data.startswith(b"GDPC"):
        size = struct.unpack_from("<Q", data, len(data) - 12)[0]
        start = len(data) - 12 - size
    if data[start:start + 4] != b"GDPC":
        raise SystemExit(f"{path}: no Godot pack found")
    version = struct.unpack_from("<I", data, start + 4)[0]
    off = start + 20
    file_base = 0
    if version >= 2:
        file_base = struct.unpack_from("<Q", data, off + 4)[0]
        off += 12
    if version >= 3:
        off = start + struct.unpack_from("<Q", data, off)[0]
    else:
        off += 64
    files = []
    count = struct.unpack_from("<I", data, off)[0]
    off += 4
    for _ in range(count):
        n = struct.unpack_from("<I", data, off)[0]
        name = data[off + 4:off + 4 + n].rstrip(b"\0").decode("utf-8", "replace")
        off += 4 + n
        foff, fsize = struct.unpack_from("<QQ", data, off)
        off += 16 + 16 + (4 if version >= 2 else 0)
        files.append((name, start + file_base + foff, fsize))
    return data, files


SCRIPT_SCAN = """extends SceneTree
func _walk(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for sub in d.get_directories():
		_walk(dir.path_join(sub), out)
	for f in d.get_files():
		if f.ends_with(".gdc"):
			out.append(dir.path_join(f))
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if not ProjectSettings.load_resource_pack(args[0], false):
		print("SCRIPTSCAN cannot mount"); quit(2); return
	var needles: Array = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	var files: Array = []
	_walk("res://", files)
	var bad := 0
	for path in files:
		var b := FileAccess.get_file_as_bytes(path)
		if b.size() < 12 or b.slice(0, 4).get_string_from_ascii() != "GDSC":
			print("SCRIPTSCAN unreadable ", path); bad += 1; continue
		var size := b.decode_u32(8)
		var body := b.slice(12)
		if size > 0:
			body = body.decompress(size, FileAccess.COMPRESSION_ZSTD)
		var hex := body.hex_encode()
		for n in needles:
			var u32 := String(n).to_utf32_buffer()
			var x32 := u32.duplicate()
			for i in range(0, x32.size(), 4):
				x32[i] = x32[i] ^ 0xb6
			for enc in [String(n).to_utf8_buffer(), u32, x32]:
				if hex.find((enc as PackedByteArray).hex_encode()) >= 0:
					print("SCRIPTSCAN ", path, " contains ", n); bad += 1; break
	print("SCRIPTSCAN %d scripts, %d problems" % [files.size(), bad])
	quit(1 if bad else 0)
"""


def scan_pack(pack: Path) -> None:
    """No forbidden string in any packed file: raw bytes for data, decompressed for scripts."""
    needles = forbidden_strings()
    data, files = read_pack(pack)
    hits = []
    for name, off, size in files:
        if name.endswith(".gdc"):
            continue
        blob = data[off:off + size]
        for n in needles:
            if n.encode() in blob or n.encode("utf-32-le") in blob:
                hits.append(f"{name}: {n}")
    for h in hits[:30]:
        print("PACKSCAN", h)
    print(f"PACKSCAN {len(files)} files, {len(needles)} forbidden strings, {len(hits)} hits", flush=True)
    with tempfile.TemporaryDirectory(prefix="cnc-scan-") as tmp:
        tmp_path = Path(tmp)
        (tmp_path / "project.godot").write_text('config_version=5\n\n[application]\nconfig/name="scan"\n')
        (tmp_path / "scan.gd").write_text(SCRIPT_SCAN)
        (tmp_path / "needles.json").write_text(json.dumps(needles))
        result = subprocess.run([godot(), "--headless", "--path", str(tmp_path), "--script", "scan.gd",
                                 "--", str(pack), str(tmp_path / "needles.json")], capture_output=True, text=True)
        lines = [l for l in result.stdout.splitlines() if l.startswith("SCRIPTSCAN")]
        print("\n".join(lines[-30:]), flush=True)
    if hits or result.returncode != 0:
        raise SystemExit(f"forbidden text in {pack}")


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
    for path in marked_scripts(PROJECT):
        strip_source(path.read_text(encoding="utf-8"), str(path.relative_to(PROJECT)))
    print("Demo presets are up to date; demo:strip regions are well formed")
    return 0


def cmd_stage(args: argparse.Namespace) -> int:
    cmd_sync(args)
    stage(args.stage.expanduser().resolve(), args.keep_excluded)
    return 0


def folder_for(out: Path, label: str) -> Path:
    return out / f"Carbon and Capital V{project_version()} Demo {label}"


def cmd_export(args: argparse.Namespace) -> int:
    cmd_sync(args)
    staged = stage(args.stage.expanduser().resolve())
    out = args.out.expanduser().resolve()
    for preset, (label, exe) in PLATFORMS.items():
        if args.platforms and label.lower() not in args.platforms:
            continue
        folder = folder_for(out, label)
        if folder.exists():
            shutil.rmtree(folder)
        folder.mkdir(parents=True)
        print(f"exporting {preset}{SUFFIX} -> {folder / exe}", flush=True)
        result = subprocess.run([godot(), "--headless", "--path", str(staged), "--export-release",
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
        scan_pack(pack)
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
    default_stage = Path(tempfile.gettempdir()) / "carbon-and-capital-demo-stage"
    p = sub.add_parser("stage")
    p.add_argument("--stage", type=Path, default=default_stage)
    p.add_argument("--keep-excluded", action="store_true",
                   help="leave tools/ and tests/ in the stage so probes and tests can run in it")
    p.set_defaults(func=cmd_stage)
    for name, func in (("export", cmd_export), ("verify", cmd_verify)):
        p = sub.add_parser(name)
        p.add_argument("--stage", type=Path, default=default_stage)
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
