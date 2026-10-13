extends Node
## Colour review of the 3D supply chain view: Greyroad (polluted, the player's works) and
## Silkstown (clean, scenery only) on the Metal Magnate start, in daylight and evening,
## at far, medium and near zoom. Writes the 3D viewport only, without the board's UI.
## AGENT_GODOT_WINDOW=1 godot --path . res://tools/supply_chain_3d/review_colour.tscn -- --no-telemetry --out=<dir>
const Harness := preload("res://tools/shot_harness.gd")
const Board := preload("res://scripts/supply_chain_3d/board.gd")
## [tag, tile, span, offset]: offsets keep the hill south of Greyroad out of the way.
const FRAMES := [["greyroad", "tile_9_9", 900.0, Vector2(0, -110)], ["greyroad", "tile_9_9", 560.0, Vector2(0, -110)],
	["greyroad", "tile_9_9", 320.0, Vector2(-120, -110)], ["silkstown", "tile_9_8", 420.0, Vector2.ZERO],
	["continent", "tile_9_9", 2200.0, Vector2.ZERO]]
var out := "/private/tmp/sc3d_colour"
## --quick: daylight, all tiles, Greyroad at medium zoom only.
var quick := false

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
		if arg == "--quick": quick = true
	DirAccess.make_dir_recursive_absolute(out)
	Harness.prepare_window(get_window(), Vector2i(1920, 1080))
	Harness.arm_watchdog(self, 1200.0)
	TelemetryState.enabled = false
	SaveLoad.autosave_enabled = false
	AudioServer.set_bus_mute(0, true)
	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	get_tree().root.add_child.call_deferred(menu)
	await get_tree().process_frame
	get_tree().current_scene = menu
	menu.call("_on_new_game_pressed")
	SaveLoad.prepare_new_game("res://data/starts/metal_magnate.json")
	var loading := LoadingScreen.show_global(get_tree())
	loading.begin_load(SaveLoad.MAIN_SCENE)
	var main: Node
	while true:
		main = get_tree().current_scene
		if main != menu and main != null and bool(main.get("build_complete")): break
		await get_tree().process_frame
	while not bool(loading.call("_ready_to_begin")): await get_tree().process_frame
	loading.call("_on_begin_pressed")
	while is_instance_valid(loading): await get_tree().process_frame
	for i in 3: await get_tree().process_frame
	MatchState.ruleset["opener_done"] = true
	Tutorial._on_overlay_skipped()
	DecisionState.enabled = false
	for layer in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var script := layer.get_script() as Script
		if script != null and script.resource_path.ends_with("_intro.gd"):
			if layer.has_method("_on_begin"): layer.call("_on_begin")
			else: layer.queue_free()
	for i in 3: await get_tree().process_frame
	var view: Control = main.find_child("EmpireView", true, false)
	await view.call("prepare")
	Harness.prepare_window(get_window(), Vector2i(1920, 1080))
	for i in 5: await get_tree().process_frame
	view.call("toggle")
	await get_tree().physics_frame
	var board: Control = view.find_child("Board", true, false)
	board.call("fit_view")
	var original_all: bool = board.get("show_all_tiles")
	if quick:
		await board.call("set_all_tiles", true, false)
		await _settle(board)
		await _frame(board, "quick", FRAMES[1])
		await _frame(board, "quick", FRAMES[0])
		await _finish(main, board)
		return
	for light in ["day", "evening"]:
		await board.call("set_evening", light == "evening")
		await board.call("set_all_tiles", false, false)
		await _settle(board)
		await _frame(board, "owned_%s" % light, FRAMES[1])
		await board.call("set_all_tiles", true, false)
		await _settle(board)
		for frame in FRAMES: await _frame(board, "all_%s" % light, frame)
	await board.call("set_evening", false)
	if not original_all: await board.call("set_all_tiles", false, false)
	await _finish(main, board)

func _frame(board: Control, tag: String, frame: Array) -> void:
	var tile: Dictionary = board.get("_model").tiles.get(frame[1], {})
	if tile.is_empty(): return
	var state: Dictionary = board.call("capture_camera")
	state.target = board.get("_builder").point(tile.center + frame[3])
	state.span = frame[2]
	board.call("restore_camera", state)
	await _settle(board)
	RenderingServer.force_draw(false)
	var image: Image = board.get("_viewport").get_texture().get_image()
	var name := "%s_%s_%d.png" % [tag, frame[0], int(frame[2])]
	image.save_png(out.path_join(name))
	print("[COLOUR] ", name, " detail=", board.get("_detail"))

func _settle(board: Control) -> void:
	var frames := 0
	while not board.call("detail_ready") and frames < 1200:
		RenderingServer.force_draw(false)
		await get_tree().process_frame
		frames += 1
	for i in 30:
		RenderingServer.force_draw(false)
		await get_tree().process_frame

func _finish(main: Node, board: Control) -> void:
	board.set_process(false)
	for i in 8:
		RenderingServer.force_draw(false)
		await get_tree().process_frame
	if is_instance_valid(main) and main != self: main.queue_free()
	for i in 8:
		RenderingServer.force_draw(false)
		await get_tree().process_frame
	get_tree().quit()
