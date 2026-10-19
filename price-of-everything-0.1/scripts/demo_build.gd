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

## Buildings every build hides until a cheat brings them back. The demo ships without them:
## their rows, their recipes and their art are left out of the export
## (addons/demo_export/demo_data_filter.gd), and a demo run skips them at load.
const HIDDEN_BUILDING_IDS: Dictionary = {"b_029": true, "b_030": true, "b_031": true, "b_035": true}
## The recycling chain: Water Recycling Plant, Recycling Plant, Landfill.
const RECYCLING_BUILDING_IDS: Dictionary = {"b_022": true, "b_036": true, "b_023": true}
## Waste Water, Scrap Metal, Bio Waste, Electronic Waste. Their goods rows stay in the demo
## because the market prices every good, but recipes that consume or make them are left out.
const RECYCLING_GOOD_IDS: Dictionary = {"g_063": true, "g_067": true, "g_073": true, "g_074": true}
## The research branch that only feeds the recycling chain.
const GATED_RESEARCH_CATEGORY := "Recycling"
## Research actions with no meaning in the demo: every tile starts surveyed.
const GATED_RESEARCH_ACTIONS: Array = ["Survey"]


## Whether a research_unlocks.csv row is left out of the demo.
static func is_gated_research(category: String, action: String) -> bool:
	return category.strip_edges() == GATED_RESEARCH_CATEGORY or GATED_RESEARCH_ACTIONS.has(action.strip_edges())

## Command-line switch that runs an editor or headless session as the demo, so the test
## suite and probes can exercise it. Honoured only where the `editor` feature exists, so an
## exported build cannot be switched.
const AS_DEMO_ARG := "--as-demo"

## Tests set this to run demo behaviour inside the editor.
static var forced := false


static func active() -> bool:
	return forced or OS.has_feature(FEATURE) \
		or (OS.has_feature("editor") and OS.get_cmdline_user_args().has(AS_DEMO_ARG))


static func is_gated_building(building_id: String) -> bool:
	return HIDDEN_BUILDING_IDS.has(building_id) or RECYCLING_BUILDING_IDS.has(building_id)


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
