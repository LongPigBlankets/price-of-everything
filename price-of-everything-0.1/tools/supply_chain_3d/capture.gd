extends Node
## Windowed visual smoke test. Uses a disposable game, never a saved game.
## AGENT_GODOT_WINDOW=1 godot --path . res://tools/supply_chain_3d/capture.tscn
const Harness := preload("res://tools/shot_harness.gd")
func _ready() -> void:
	Harness.prepare_window(get_window(), Vector2i(1920, 1080))
	Harness.arm_watchdog(self, 240.0)
	TelemetryState.enabled = false
	SaveLoad.autosave_enabled = false
	AudioServer.set_bus_mute(0, true)
	SaveLoad.prepare_new_game("res://data/starts/metal_magnate.json")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	get_tree().current_scene = main
	while not bool(main.get("build_complete")): await get_tree().process_frame
	MatchState.ruleset["opener_done"] = true
	Tutorial._on_overlay_skipped()
	DecisionState.enabled = false
	for layer in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var script := layer.get_script() as Script
		if script != null and script.resource_path.ends_with("_intro.gd"): layer.queue_free()
	var view: Control = main.find_child("EmpireView", true, false)
	await view.call("prepare")
	Harness.prepare_window(get_window(), Vector2i(1920, 1080))
	for i in 5: await get_tree().process_frame
	view.call("toggle")
	var board: Control = view.find_child("Board", true, false)
	await get_tree().physics_frame
	board.call("fit_view")
	var home: Dictionary = board.call("capture_camera")
	await _exercise_pointer(board)
	board.call("restore_camera", home)
	print("[3D] camera ", home, " tiles ", board.get("_model").tiles.size(), " objects ", board.get("_builder").pickables.size())
	for i in 4:
		var state := home.duplicate()
		state.yaw += PI * 0.5 * i
		board.call("restore_camera", state)
		await _shot("orbit_%d" % i)
	board.call("restore_camera", home)
	var tiles: Dictionary = board.get("_model").tiles
	var first := str(tiles.keys()[0])
	var builder: RefCounted = board.get("_builder")
	var camera: Camera3D = board.get("_camera")
	await _click(camera.unproject_position(builder.point(tiles[first].center)))
	board.call("_select_tile", first)
	await _shot("tile_selected")
	var panel: Control = main.get("info_panel")
	print("[3D] tile panel visible: ", panel.visible)
	panel.hide()
	var close := home.duplicate()
	close.span *= 0.48
	board.call("restore_camera", close)
	await _shot("close")
	print("[3D] drawcalls ", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), " triangles ", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	get_tree().quit()
func _shot(label: String) -> void:
	for i in 5: await get_tree().process_frame
	Harness.capture(self, "/private/tmp/supply3d_%s.png" % label, Vector2i(1920, 1080))

func _exercise_pointer(board: Control) -> void:
	var before: Dictionary = board.call("capture_camera")
	var event := InputEventMouseButton.new()
	event.position = board.size * 0.5
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	get_viewport().push_input(event, true)
	var motion := InputEventMouseMotion.new()
	motion.position = event.position + Vector2(100, -40)
	motion.relative = Vector2(100, -40)
	motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
	get_viewport().push_input(motion, true)
	event.pressed = false
	event.position = motion.position
	get_viewport().push_input(event, true)
	await get_tree().process_frame
	var after: Dictionary = board.call("capture_camera")
	assert(not is_equal_approx(before.yaw, after.yaw) and not is_equal_approx(before.pitch, after.pitch), "GUI drag must orbit the 3D camera")
	print("[3D] GUI right drag changed yaw and pitch")

func _click(position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.shift_pressed = true
	event.pressed = true
	get_viewport().push_input(event, true)
	event.pressed = false
	get_viewport().push_input(event, true)
	await get_tree().process_frame
