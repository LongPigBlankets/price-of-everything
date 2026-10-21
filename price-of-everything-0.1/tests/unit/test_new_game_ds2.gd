extends "res://tests/test_base.gd"
## The New Game settings screen as the company registry (scripts/new_game_ds2/new_game_ds2.gd): what shows when, the
## signals, the demo lock, and the old panel standing untouched with the flag off. Behaviour, not looks.

const FEATURE := "new_game"
const TAGS := {
	"_test_flag_off_keeps_the_old_panel": ["new_game", "ui"],
	"_test_registry_files_and_the_open_file": ["new_game", "ui"],
	"_test_registry_form_and_stamps": ["new_game", "ui"],
	"_test_registry_signals": ["new_game", "ui"],
	"_test_registry_demo_lockboxes": ["new_game", "ui", "demo_build"],
	"_test_era_spans": ["new_game", "ui"],
	"_test_place_for_unnamed_tiles": ["new_game", "map"],
	"_test_registry_seal_sequence": ["new_game", "ui"],
	"_test_grade_words_without_the_survey_sentence": ["new_game", "ui"],
	"_test_story_wraps_to_the_leaf": ["new_game", "ui"],
}
const DS2_SCRIPT := "res://scripts/new_game_ds2/new_game_ds2.gd"
const DebugTerminalScript := preload("res://scripts/debug_terminal.gd")
const PlayerColours := preload("res://scripts/player_colours.gd")
const PANEL_SIZE := Vector2(1396, 966)


func _registry(unlocked: bool) -> Control:
	DebugTerminalScript._demo_unlocked = unlocked
	var p: Control = (load(DS2_SCRIPT) as GDScript).new()
	p.size = PANEL_SIZE
	add_child(p)
	return p


func _file_index(p: Control, start_id: String) -> int:
	var starts: Array = p.get("_starts")
	for i in starts.size():
		if str((starts[i] as Dictionary).get("id", "")) == start_id:
			return i
	return -1


## The registry is the default; the cheat's flag brings the old panel back live, untouched, and on again returns
## the registry.
func _test_flag_off_keeps_the_old_panel() -> void:
	var was: bool = UiPrefs.use_new_game_ds2
	var fresh: Node = load("res://scripts/ui_prefs.gd").new()
	_check(bool(fresh.get("use_new_game_ds2")), "new game: the registry is the default")
	fresh.free()
	UiPrefs.set_use_new_game_ds2(false)
	var menu: Control = load("res://scripts/main_menu.gd").new()
	add_child(menu)
	await get_tree().process_frame
	var old_script: GDScript = load("res://scripts/new_game_panel.gd")
	var panel: Control = menu.get("_new_game_panel")
	_check(panel != null and panel.get_script() == old_script and not bool(menu.call("new_game_is_ds2")),
		"new game flag off: the old panel stands")
	_check(_tree_has_label_text(panel, "New Game") and _tree_has_label_text(panel, "Advanced Settings"),
		"new game flag off: the old panel's title and accordion are as before")
	_check((panel.get("_card_buttons") as Array).size() == 7, "new game flag off: seven start cards")
	UiPrefs.set_use_new_game_ds2(true)
	await get_tree().process_frame
	panel = menu.get("_new_game_panel")
	_check(bool(menu.call("new_game_is_ds2")) and panel.name == "NewGameDs2", "new game flag on: the registry stands in its place")
	UiPrefs.set_use_new_game_ds2(false)
	await get_tree().process_frame
	panel = menu.get("_new_game_panel")
	_check(panel.get_script() == old_script and _tree_has_label_text(panel, "Advanced Settings"),
		"new game flag off again: the old panel is back")
	menu.queue_free()
	UiPrefs.set_use_new_game_ds2(was)
	await get_tree().process_frame


## Seven files in the rack, the recommended one pulled out; the open file prints the start's buildings and the ledger.
func _test_registry_files_and_the_open_file() -> void:
	var saved: bool = DebugTerminalScript._demo_unlocked
	var p := _registry(true)
	await get_tree().process_frame
	var files: Array = p.get("_card_buttons")
	_check(files.size() == 7, "registry: seven company files")
	var open_field := _file_index(p, "open_field")
	_check(int(p.get("_chosen_index")) == open_field and str(p.get("_start_id")) == "open_field",
		"registry: the recommended start's file is the one pulled out")
	_check(not (p.get("_rack_lid") as Control).visible, "registry: no lockbox in the full game")
	var carmaker := _file_index(p, "troubled_carmaker")
	(files[carmaker] as Button).button_pressed = true
	await get_tree().process_frame
	_check(str(p.get("_start_id")) == "troubled_carmaker" and str(p.get("_start_path")).ends_with("troubled_carmaker.json"),
		"registry: pressing a file opens that start")
	var rows: Array = p.call("building_rows")
	_check(rows.size() == 4 and str((rows[0] as Dictionary).get("gid", "")) != "" and str((rows[0] as Dictionary).get("place", "")) != "",
		"registry: the carmaker's four buildings, each with the good it makes and its place")
	var ledger: Array = p.call("ledger_lines")
	_check(ledger.size() == 3 and str(ledger[0][0]) == "Cash" and str(ledger[0][1]) == "£200" and str(ledger[1][1]) == "£500"
		and str(ledger[2][0]) == "Net" and str(ledger[2][1]) == "-£300" and (ledger[2][2] as Color) == Color("#8f1f19"),
		"registry ledger: Cash £200, Debt £500, Net -£300 in red ink (%s)" % str(ledger))
	(files[_file_index(p, "metal_magnate")] as Button).button_pressed = true
	await get_tree().process_frame
	ledger = p.call("ledger_lines")
	_check(ledger.size() == 3 and str(ledger[1][1]) == "none" and str(ledger[2][0]) == "Profit each turn" and not str(ledger[2][1]).begins_with("-"),
		"registry ledger: no debt prints none and Profit each turn (%s)" % str(ledger))
	p.call("_hover", 1)
	_check(int(p.call("hovered_cell")) == 1 and (p.get("_slip") as Control).visible, "registry: pointing at a building shows the slip")
	p.call("_hover", -1)
	_check(not (p.get("_slip") as Control).visible, "registry: the slip goes when the pointer leaves")
	var paints: Array = p.get("_paint_buttons")
	_check(paints.size() == PlayerColours.all().size(), "registry: a paint square for every livery")
	(paints[2] as Button).pressed.emit()
	_check(str(p.call("colour_key")) == str((PlayerColours.all()[2] as Dictionary)["key"]), "registry: pressing a square repaints")
	_check((p.get("_r_press") as Rect2).end.x <= p.size.x + 0.5 and (p.get("_r_form") as Rect2).end.x < (p.get("_r_stamps") as Rect2).position.x,
		"registry: the form, the stamps and the press fit the width")
	p.queue_free()
	DebugTerminalScript._demo_unlocked = saved
	await get_tree().process_frame


## The grade stamps set the difficulty, the two hard grades stay padlocked until a game is finished, the charter's
## keys step the drum through the lengths.
func _test_registry_form_and_stamps() -> void:
	var saved: bool = DebugTerminalScript._demo_unlocked
	var p := _registry(true)
	await get_tree().process_frame
	var keys: Array = p.get("_grade_keys")
	_check(keys.size() == 5 and str(p.get("_difficulty_id")) == "normal", "registry stamps: five grades, Normal latched")
	var finished := PlayerProfile.has_completed_game()
	var locked_ok := true
	for k in keys:
		var grade := str((k as Button).get_meta("grade"))
		var spent := bool((k as Button).get("spent"))
		if grade in ["very_hard", "god"]:
			locked_ok = locked_ok and spent == (not finished)
		else:
			locked_ok = locked_ok and not spent
	_check(locked_ok, "registry stamps: Very Hard and God of Industry padlocked until a game is finished (finished: %s)" % finished)
	p.call("_choose_grade", "hard")
	var hard_chosen := false
	for k in keys:
		if str((k as Button).get_meta("grade")) == "hard":
			hard_chosen = bool((k as Button).get("chosen"))
	_check(str(p.get("_difficulty_id")) == "hard" and hard_chosen, "registry stamps: pressing Hard stamps the form")
	_check(int(p.call("charter_turns")) == 300 and p.get("_drum") != null, "registry charter: 300 turns on the drum")
	p.call("_step_speed", 1)
	_check(int(p.call("charter_turns")) == 400, "registry charter: the right key steps to 400")
	p.call("_step_speed", 1)
	_check(int(p.call("charter_turns")) == 100 and str(p.get("_policy_timeline")) == "demo_itch",
		"registry charter: then the demo's 100 turns with its timeline")
	p.call("_step_speed", -1)
	p.call("_step_speed", -1)
	p.call("_step_speed", -1)
	_check(int(p.call("charter_turns")) == 200 and str(p.get("_policy_timeline")) == "", "registry charter: the left key steps back to 200")
	p.queue_free()
	DebugTerminalScript._demo_unlocked = saved
	await get_tree().process_frame


## Start New Game carries the choices in the same overrides as the old panel; Back asks the menu to close.
func _test_registry_signals() -> void:
	var saved: bool = DebugTerminalScript._demo_unlocked
	var p := _registry(true)
	await get_tree().process_frame
	var got := {}
	p.start_requested.connect(func(path: String, overrides: Dictionary) -> void:
		got["path"] = path
		got["overrides"] = overrides)
	var backs := [0]
	p.back_requested.connect(func() -> void: backs[0] += 1)
	(p.get("_card_buttons")[_file_index(p, "glass_merchant")] as Button).button_pressed = true
	p.call("_choose_grade", "easy")
	p.call("_step_speed", -1)
	(p.get("_start_key") as Button).pressed.emit()
	var rs: Dictionary = (got.get("overrides", {}) as Dictionary).get("ruleset", {})
	_check(str(got.get("path", "")).ends_with("glass_merchant.json") and str(rs.get("start_id", "")) == "glass_merchant"
		and str(rs.get("difficulty", "")) == "easy" and int(rs.get("speed_turns", 0)) == 200
		and str(rs.get("company_colour", "")) == str(p.call("colour_key")) and bool(rs.get("survey_all_tiles", false)),
		"registry start: the press emits start_requested with the choices (%s)" % str(rs))
	_check((got.get("overrides", {}) as Dictionary).has("telemetry_opt_in"), "registry start: telemetry consent rides the overrides")
	(p.get_node("Header/BackKey") as BaseButton).pressed.emit()
	_check(backs[0] == 1, "registry back: the Back key emits back_requested")
	p.queue_free()
	DebugTerminalScript._demo_unlocked = saved
	await get_tree().process_frame


## A demo build: the five full game starts and the stamps under lockbox lids, the form fixed, Start still there.
func _test_registry_demo_lockboxes() -> void:
	var saved: bool = DebugTerminalScript._demo_unlocked
	var p := _registry(false)
	await get_tree().process_frame
	var files: Array = p.get("_card_buttons")
	var starts: Array = p.get("_starts")
	var locks_ok := true
	for i in files.size():
		var demo_start: bool = NewGamePanel.DEMO_START_IDS.has(str((starts[i] as Dictionary).get("id", "")))
		locks_ok = locks_ok and (files[i] as Button).disabled == (not demo_start)
		if not demo_start:
			locks_ok = locks_ok and (files[i] as Button).tooltip_text == NewGamePanel.DEMO_LOCK_TIP
	_check(locks_ok, "registry demo: only the demo's starts open, the rest say Locked in the Demo")
	_check((p.get("_rack_lid") as Control).visible and (p.get("_r_lid_rack") as Rect2).size.x > 0.0, "registry demo: the lockbox lid over the shut pigeonholes")
	_check(str(p.get("_start_id")) == "metal_magnate", "registry demo: Metal Magnate's file is open")
	var only_normal := true
	for k in p.get("_grade_keys"):
		only_normal = only_normal and bool((k as Button).get("spent")) == (str((k as Button).get_meta("grade")) != "normal")
	_check(only_normal and str(p.get("_difficulty_id")) == "normal", "registry demo: the grades but Normal are shut")
	_check(p.get("_drum") == null and int(p.call("charter_turns")) == 100 and str(p.get("_policy_timeline")) == "demo_itch",
		"registry demo: the charter is fixed at the demo's 100 turns, no drum")
	p.call("_step_speed", 1)
	_check(int(p.call("charter_turns")) == 100, "registry demo: the charter cannot be stepped")
	_check(p.get("_start_key") != null and not (p.get("_start_key") as Button).disabled, "registry demo: Start New Game stands")
	p.queue_free()
	DebugTerminalScript._demo_unlocked = saved
	await get_tree().process_frame


## The era rule cuts a charter into three eras: 90, 90 and 110 turns of 300, the same shares of any other length.
func _test_era_spans() -> void:
	var script: GDScript = load(DS2_SCRIPT)
	_check(script.call("era_spans", 300) == [[0, 90], [90, 180], [180, 300]], "eras: 300 turns are 90, 90 and 110")
	_check(script.call("era_spans", 200) == [[0, 60], [60, 120], [120, 200]], "eras: 200 turns keep the shares")
	_check(script.call("era_spans", 400) == [[0, 120], [120, 240], [240, 400]], "eras: 400 turns keep the shares")
	_check(int(script.DEMO_ERA_SPAN) == 300, "eras: the demo's rule spans the campaign's 300 turns")


## A tile with no name prints Near the nearest named tile.
func _test_place_for_unnamed_tiles() -> void:
	var script: GDScript = load(DS2_SCRIPT)
	_check(str(script.call("place_for", "tile_24_8")) == Catalog.tile_name("tile_24_8") and Catalog.tile_name("tile_24_8") != "",
		"place for: a named tile prints its name")
	var unnamed := ""
	for tid in Catalog.all_tile_ids():
		if Catalog.tile_name(str(tid)) == "":
			unnamed = str(tid)
			break
	var near := str(script.call("place_for", unnamed))
	_check(unnamed != "" and near.begins_with("Near ") and near.length() > 5, "place for: an unnamed tile prints Near the nearest named one (%s -> %s)" % [unnamed, near])


## The seal: headless the Start key emits at once (the signals test); the sequence itself is a pure function of time,
## the die on the press before the lift, over the circle after the slide, down on it from the drop, the impression
## staying from then on.
func _test_registry_seal_sequence() -> void:
	var saved: bool = DebugTerminalScript._demo_unlocked
	var p := _registry(true)
	await get_tree().process_frame
	var script: GDScript = p.get_script()
	var home: Vector2 = p.call("die_centre_at", 0.0)
	var over: Vector2 = p.call("die_centre_at", script.STAMP_SLIDE)
	var seal: Vector2 = (p.get("_r_form") as Rect2).position + (p.call("_seal_centre") as Vector2)
	var press: Rect2 = p.get("_r_press")
	_check(press.has_point(home) and home.distance_to(seal) > 100.0, "seal: the die rests on the press before Start")
	_check(over.is_equal_approx(seal) and (p.call("die_centre_at", script.STAMP_HOLD) as Vector2).is_equal_approx(seal),
		"seal: the die is over the circle from the end of the slide while it stamps")
	_check((p.call("die_centre_at", script.STAMP_SECONDS) as Vector2).is_equal_approx(home)
		and is_equal_approx(float(script.DIE_SCALE_AT(script.STAMP_SECONDS)), 1.0),
		"seal: the die is back on the press at the end, so the impression is in view")
	var mid: Vector2 = p.call("die_centre_at", (script.STAMP_LIFT + script.STAMP_SLIDE) * 0.5)
	_check(mid.distance_to(home) > 10.0 and mid.distance_to(seal) > 10.0, "seal: the die is on its way between the two")
	_check(float(script.DIE_SCALE_AT(script.STAMP_LIFT)) > 1.0 and is_equal_approx(float(script.DIE_SCALE_AT(script.STAMP_DOWN)), 1.0)
		and is_equal_approx(float(script.DIE_SCALE_AT(-1.0)), 1.0), "seal: the die is larger while lifted, its own size when down")
	_check(not bool(p.call("is_sealed")), "seal: no impression before Start")
	p.call("_set_stamp_time", script.STAMP_DOWN - 0.01)
	_check(not bool(p.call("is_sealed")), "seal: no impression while the die is still coming down")
	p.call("_set_stamp_time", script.STAMP_DOWN)
	_check(bool(p.call("is_sealed")) and (p.get("_die") as Control).get_rect().has_point(seal), "seal: the impression is there once the die is down, the die over the circle")
	p.call("_set_stamp_time", script.STAMP_SECONDS)
	_check(bool(p.call("is_sealed")) and not (p.get("_die") as Control).get_rect().has_point(seal),
		"seal: the impression stays once the die has gone back")
	_check(not bool(p.call("is_starting")), "seal: a headless press never holds the panel (the signal went at once)")
	p.queue_free()
	DebugTerminalScript._demo_unlocked = saved
	await get_tree().process_frame


## The grade's words leave out the survey sentence while every tile is surveyed, keeping the deposits.
func _test_grade_words_without_the_survey_sentence() -> void:
	var saved: bool = DebugTerminalScript._demo_unlocked
	var p := _registry(true)
	await get_tree().process_frame
	var all_clean := true
	var kept_deposits := true
	for opt in NewGamePanel.DIFFICULTIES:
		var words: String = p.call("grade_words", String(opt["desc"]))
		all_clean = all_clean and not ("surveyed" in words)
		kept_deposits = kept_deposits and "deposit" in words and words.ends_with(".")
	_check(all_clean, "grade words: no sentence about what is surveyed")
	_check(kept_deposits, "grade words: the deposits part of every grade stays, ending in a full stop")
	_check(p.call("grade_words", "Some tiles are surveyed.") == "", "grade words: a grade with only the survey sentence prints nothing")
	p.queue_free()
	DebugTerminalScript._demo_unlocked = saved
	await get_tree().process_frame


## The company's story wraps to the open file's left leaf, even when the file is chosen before the panel has a size
## (the main menu chooses one as it builds the panel) and after the panel is resized.
func _test_story_wraps_to_the_leaf() -> void:
	DebugTerminalScript._demo_unlocked = true
	var p: Control = (load(DS2_SCRIPT) as GDScript).new()
	add_child(p)
	for panel_size in [PANEL_SIZE, PANEL_SIZE * 0.8]:
		p.size = panel_size
		p.call("_layout")
		var leaf: Rect2 = p.get("_r_leaf_l")
		var inner: float = leaf.size.x - 2.0 * float(p.LEAF["m"]) * p.L
		var story := String((p.get("_chosen") as Dictionary).get("description", (p.get("_chosen") as Dictionary).get("blurb", "")))
		var lines: Array = p.get("_story_lines")
		var widest := 0.0
		for rng in lines:
			var line := story.substr(int((rng as Vector2i).x), int((rng as Vector2i).y - (rng as Vector2i).x)).strip_edges()
			widest = maxf(widest, p.FONT_PLEX.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, p.call("_story_font_px")).x)
		_check(lines.size() > 1 and widest <= inner + 0.5, "New Game: the company story wraps inside its leaf at %d wide (%d lines, widest %d of %d)" % [panel_size.x, lines.size(), widest, inner])
	p.queue_free()
