extends "res://tests/test_base.gd"
## The opening steps every new game plays (Tutorial.start_opener): their content and their detectors. Also the
## diagnostics LED rule and the profile's display and audio settings, which lived here before.

const FEATURE := "tutorial"
## Tests that also belong to other features (run under any of their tags).
const TAGS := {
	"_test_profile_display_and_audio": ["settings", "tutorial"],
	"_test_diagnostic_led_tone": ["ui", "tutorial"],
}


func _copy_has_dash(value: Variant) -> bool:
	if value is String:
		for mark: String in ["-", "–", "—", "‑", "‐"]:
			if value.contains(mark):
				return true
	elif value is Array:
		for item: Variant in value:
			if _copy_has_dash(item):
				return true
	elif value is Dictionary:
		for item: Variant in value.values():
			if _copy_has_dash(item):
				return true
	return false


## The opener's steps, in order, in plain copy: the welcome, the screen tour, tiles and the recipe diagram, then
## the business steps, with End Turn handed over after the costs.
func _test_opener_steps() -> void:
	var steps: Array = TutorialSteps.opener_steps()
	var ids: Array = steps.map(func(st: Dictionary) -> String: return str(st.get("id", "")))
	_check(ids == ["welcome", "ui_primer", "tile_basics_select", "tile_basics_land", "tile_basics_features",
		"recipe_inputs_intro", "recipe_outputs_intro", "opener_movement", "opener_your_buildings", "opener_costs",
		TutorialSteps.OPENER_END_TURN_STEP, "opener_next_opportunity", "opener_own_pace"],
		"opener: the steps run in order (%s)" % ", ".join(PackedStringArray(ids)))
	for step: Dictionary in steps:
		_check(not _copy_has_dash(step.get("title", "")) and not _copy_has_dash(step.get("body", ""))
			and not _copy_has_dash(step.get("paragraphs", [])), "opener copy has no hyphens or dashes: " + str(step.id))
	var first: Dictionary = steps[0]
	_check(str(first.get("mode", "")) == "welcome" and str((first.get("paragraphs", []) as Array)[1]).contains("interface"),
		"opener: the welcome card says the interface comes first")
	var primer: Dictionary = steps[1]
	_check(str(primer.get("mode", "")) == "annotate" and bool(primer.get("map_only", false)),
		"opener: the screen tour shades only the map")
	for step: Dictionary in steps:
		for action: Dictionary in step.get("setup", []):
			_check(str(action.get("action", "")) == "close_tile_panel",
				"opener: %s only uses setup actions the engine runs" % str(step.id))
		var kind := str((step.get("spotlight", {}) as Dictionary).get("kind", "none"))
		_check(kind in ["none", "node_name"], "opener: %s spotlights by node name or not at all" % str(step.id))
	_check(not Tutorial.active and not Tutorial.end_turn_locked(), "opener: End Turn is free while no opener runs")


## The opener's detectors read live state; unknown predicates never advance a step.
func _test_opener_detectors() -> void:
	_check(TutorialDetectors.poll({"kind": "node_visible", "ref": "NoSuchNode_xyz"}) == false,
		"detector: node_visible is false for a node that does not exist")
	_check(TutorialDetectors.poll({"kind": "unknown_predicate"}) == false, "detector: an unknown predicate never advances")
	_check(TutorialDetectors.poll({"kind": "building_detail_open"}) == false,
		"detector: building_detail_open is false with no detail panel up")
	_check(TutorialDetectors.poll({"kind": "own_buildings_shown"}) == false,
		"detector: own_buildings_shown is false with neither the tile panel nor the ledger open")


## The tile LED's tone over a building's diagnostics.
func _test_diagnostic_led_tone() -> void:
	var readout = load("res://scripts/building_readout.gd")
	_check(readout.diagnostic_led_tone([{"tone": "ok"}, {"tone": "warn"}]) == "ok", "tile LED: green tolerates one amber alongside green")
	_check(readout.diagnostic_led_tone([{"tone": "ok"}, {"tone": "warn"}, {"tone": "warn"}]) == "warn", "tile LED: multiple amber diagnostics need attention")
	_check(readout.diagnostic_led_tone([{"tone": "warn"}]) == "warn", "tile LED: all amber stays amber")
	_check(readout.diagnostic_led_tone([{"tone": "ok"}, {"tone": "warn"}, {"tone": "bad"}]) == "bad", "tile LED: any red diagnostic wins")


## Resolution, fullscreen, the target monitor and audio volumes persist through PlayerProfile (apply is a
## headless no-op), and survive the profile's JSON encode and decode.
func _test_profile_display_and_audio() -> void:
	var ws_saved: Vector2i = PlayerProfile.window_size
	PlayerProfile.set_window_size(Vector2i(3440, 1440))
	_check(PlayerProfile.window_size == Vector2i(3440, 1440), "profile: set_window_size stores the chosen resolution")
	var fs_saved: bool = PlayerProfile.fullscreen
	var sc_saved: int = PlayerProfile.screen_index
	var al_saved: Dictionary = PlayerProfile.audio_levels.duplicate()
	PlayerProfile.set_display(false, Vector2i(1920, 1080), 0)
	_check(PlayerProfile.fullscreen == false and PlayerProfile.window_size == Vector2i(1920, 1080) and PlayerProfile.screen_index == 0, "profile: set_display stores mode + windowed size + monitor")
	PlayerProfile.set_audio_levels({"Master": 100.0, "Music": 55.0, "SFX": 30.0})
	_check(int(PlayerProfile.audio_levels.get("Music", 0)) == 55, "profile: set_audio_levels stores volumes")
	var round_trip: Variant = JSON.parse_string(JSON.stringify({"fullscreen": PlayerProfile.fullscreen, "screen_index": PlayerProfile.screen_index, "audio_levels": PlayerProfile.audio_levels}))
	_check(round_trip is Dictionary and (round_trip as Dictionary).get("fullscreen") == false \
		and int((round_trip as Dictionary).get("screen_index", -99)) == 0 \
		and int(((round_trip as Dictionary).get("audio_levels", {}) as Dictionary).get("Music", 0)) == 55, \
		"profile: display + audio prefs survive a JSON round-trip")
	PlayerProfile.fullscreen = fs_saved
	PlayerProfile.set_audio_levels(al_saved)              # restore + re-persist the originals
	PlayerProfile.set_display(fs_saved, ws_saved, sc_saved)
	_check(PlayerProfile.window_size == ws_saved and PlayerProfile.screen_index == sc_saved, "profile: window_size + monitor restored after test")
