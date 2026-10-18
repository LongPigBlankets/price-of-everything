extends RefCounted
## The demo build: this same project exported through a "<platform> Demo" preset, which adds
## the `demo` feature tag. Nothing forks. A feature reaches the demo by default and is kept
## out in one of two places:
##   - at runtime, behind `DemoBuild.active()` (this file holds the allow-lists), and
##   - at export, in tools/demo_build/excludes.txt (files the demo presets leave out).
## `python3 tools/demo_build/build_demo.py sync` regenerates the demo presets from the
## regular ones, so a change to a regular preset reaches the demo on the next sync.
## tests/unit/test_demo_build.gd fails when the presets are out of sync or when shipped code
## preloads a file the demo leaves out.
##
## Reference it as `const DemoBuild := preload("res://scripts/demo_build.gd")`.

const FEATURE := "demo"

## The starts the demo ships. Every other start file in data/starts/ is left out of the
## export; their New Game cards stay as locked teasers drawn from index.json alone.
const START_IDS: Array = ["metal_magnate", "glass_merchant"]

## Terminal commands a demo build keeps once `debug CandC` is entered. Matched against the
## lower-cased command line: a bare word allows any arguments, two words allow that exact
## sub-command only.
const CHEATS: Array = ["cash", "unlock all", "help"]

## Command-line user arguments (after `--`) a demo build honours. Review and trace switches
## are dropped so a demo binary always runs the shipped game.
const USER_ARGS: Array = ["--no-telemetry"]

## Tests set this to run demo behaviour inside the editor.
static var forced := false


static func active() -> bool:
	return forced or OS.has_feature(FEATURE)


## Whether a terminal command line is allowed. Always true outside a demo build.
static func allows_cheat(command_line: String) -> bool:
	if not active():
		return true
	var parts := command_line.strip_edges().to_lower().split(" ", false)
	if parts.is_empty():
		return false
	for entry in CHEATS:
		var want := String(entry).split(" ", false)
		if want.size() == 1 and parts[0] == want[0]:
			return true
		if want.size() == parts.size() and want == parts:
			return true
	return false


## `OS.get_cmdline_user_args()`, filtered to USER_ARGS in a demo build.
static func user_args() -> PackedStringArray:
	var args := OS.get_cmdline_user_args()
	if not active():
		return args
	var kept := PackedStringArray()
	for arg in args:
		if USER_ARGS.has(arg):
			kept.append(arg)
	return kept


static func has_user_arg(arg: String) -> bool:
	return user_args().has(arg)


## The version string reported to telemetry, tagged so demo and full runs stay apart.
static func version_label() -> String:
	var version := str(ProjectSettings.get_setting("application/config/version", "dev"))
	return version + "-demo" if active() else version
