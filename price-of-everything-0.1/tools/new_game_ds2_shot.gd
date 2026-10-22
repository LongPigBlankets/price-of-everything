extends Node
## Captures of the New Game settings screen as the company registry (scripts/new_game_ds2/new_game_ds2.gd), the panel
## alone at its width of 1396 on a dark backdrop, in a SubViewport at two pixels a logical pixel so every capture has
## the same pixels whatever the display. States: the full game with the recommended start, the full game with the
## Troubled Carmaker open (a building pointed at, Hard stamped, a 200 turn charter), three moments of the seal coming
## down when Start New Game is pressed (the die over the circle, the die down, the impression left), and the demo with
## its lockboxes.
## Needs a window:
##   AGENT_GODOT_WINDOW=1 godot --path . res://tools/new_game_ds2_shot.tscn --quit-after 20000 -- --no-telemetry
## Writes <state>.png into $NEW_GAME_SHOT_DIR (default artifacts/new_game_ds2/ds2_v2). NEW_GAME_SHOT_EVERY=1 also
## captures every start, start_<id>.png. 07_many_buildings is a made-up company of nine buildings.

const ShotHarness := preload("res://tools/shot_harness.gd")
const DebugTerminal := preload("res://scripts/debug_terminal.gd")
const PANEL_SCRIPT := "res://scripts/new_game_ds2/new_game_ds2.gd"
const PANEL := Vector2(1396, 966)
const MARGIN := 20.0

var _vp: SubViewport
var _dir := ""


func _ready() -> void:
	_dir = OS.get_environment("NEW_GAME_SHOT_DIR")
	if _dir == "":
		_dir = ProjectSettings.globalize_path("res://artifacts/new_game_ds2/ds2_v2")
	DirAccess.make_dir_recursive_absolute(_dir)
	ShotHarness.arm_watchdog(self, 240.0)
	ShotHarness.prepare_window(get_window(), Vector2i(1600, 1000))
	TelemetryState.enabled = false
	var logical := Vector2i(PANEL + Vector2(MARGIN, MARGIN) * 2.0)
	_vp = SubViewport.new()
	_vp.size = logical * 2
	_vp.size_2d_override = logical
	_vp.size_2d_override_stretch = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.gui_embed_subwindows = true
	_vp.transparent_bg = false
	add_child(_vp)
	var back := ColorRect.new()
	back.color = Color("#121820")
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vp.add_child(back)
	UiPrefs.set_use_new_game_ds2(true)

	DebugTerminal._demo_unlocked = true
	var panel: Control = await _open()
	await _shot("01_full_default")
	var files: Array = panel.get("_card_buttons")
	if OS.get_environment("NEW_GAME_SHOT_EVERY") != "":
		# Every start in turn, to compare the leaves across stories of different lengths.
		for i in files.size():
			(files[i] as Button).button_pressed = true
			await _settle(90)
			await _shot("start_" + str((panel.get("_starts")[i] as Dictionary).get("id", i)))
	for i in files.size():
		if str((panel.get("_starts")[i] as Dictionary).get("id", "")) == "troubled_carmaker":
			(files[i] as Button).button_pressed = true
	await _settle(4)
	panel.call("_hover", 1)
	panel.call("_choose_grade", "hard")
	panel.call("_step_speed", -1)
	await _settle(90)
	await _shot("02_full_carmaker")
	panel.call("_hover", -1)
	await _shot_many(panel)
	for moment in [["04_stamp_over", 1.2], ["05_stamp_down", 1.5], ["06_stamp_after", 2.5]]:
		panel.call("_set_stamp_time", float(moment[1]))
		await _settle(6)
		await _shot(String(moment[0]))
	panel.queue_free()
	await _settle(2)

	DebugTerminal._demo_unlocked = false
	panel = await _open()
	await _shot("03_demo_lockboxes")
	panel.queue_free()
	await _settle(2)
	print("[NEW_GAME_SHOT] done, %s" % _dir)
	get_tree().quit(0)


## No start owns this many buildings yet: a made-up company of nine, alike ones together, three rows of the grid,
## with a grouped cell pointed at.
func _shot_many(panel: Control) -> void:
	var path := "user://new_game_shot_many.json"
	var buildings: Array = []
	for e in [["b_002", "r_003", "tile_9_9"], ["b_002", "r_003", "tile_9_10"], ["b_002", "r_003", "tile_7_11"],
			["b_001", "r_001", "tile_9_9"], ["b_001", "r_001", "tile_9_10"], ["b_001", "r_002", "tile_9_9"],
			["b_003", "r_004", "tile_9_9"], ["b_001", "r_018", "tile_19_15"], ["b_002", "r_053", "tile_18_16"]]:
		buildings.append({"building_id": e[0], "recipe_id": e[1], "tile_id": e[2]})
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"money": 1500, "steady_profit_per_turn": 120, "loans": [{"principal": 800}], "buildings": buildings}))
	f.close()
	var longest := ""
	for st in panel.get("_starts"):
		var words := String((st as Dictionary).get("description", ""))
		if words.length() > longest.length(): longest = words
	panel.call("_select_start", {"id": "_many", "title": "Many Buildings", "file": path, "description": longest})
	await _settle(30)
	panel.call("_hover", 0)
	await _settle(10)
	await _shot("07_many_buildings")
	panel.call("_hover", -1)


func _open() -> Control:
	var panel: Control = (load(PANEL_SCRIPT) as GDScript).new()
	panel.position = Vector2(MARGIN, MARGIN)
	panel.size = PANEL
	_vp.add_child(panel)
	await _settle(12)
	return panel


func _settle(frames: int) -> void:
	for _i in frames:
		RenderingServer.force_draw(false)
		await get_tree().process_frame


func _shot(state: String) -> void:
	RenderingServer.force_draw(false)
	var img := _vp.get_texture().get_image()
	img.save_png(_dir.path_join(state + ".png"))
	print("[NEW_GAME_SHOT] %s %s" % [state, img.get_size()])
