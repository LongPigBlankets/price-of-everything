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
	print("[3D] menu -> New Game -> Begin succeeded")
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
	var board: Control = view.find_child("Board", true, false)
	await get_tree().physics_frame
	board.call("fit_view")
	var home: Dictionary = board.call("capture_camera")
	if not await _exercise_pointer(board): return
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
	await _click(board.call("screen_point", builder.point(tiles[first].center)))
	if str(board.get("_selected_tile")) != first:
		push_error("GUI Shift-click must select the projected tile")
		get_tree().quit(1)
		return
	await _shot("tile_selected")
	var panel: Control = main.get("info_panel")
	print("[3D] tile panel visible: ", panel.visible)
	if not panel.visible:
		get_tree().quit(1)
		return
	panel.hide()
	var close := home.duplicate()
	close.span *= 0.48
	board.call("restore_camera", close)
	await _shot("close")
	print("[3D] drawcalls ", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), " triangles ", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	if "--detail-review" in OS.get_cmdline_user_args(): await _detail_review(board, home)
	get_tree().quit()
func _shot(label: String) -> void:
	for i in 5: await get_tree().process_frame
	Harness.capture(self, "/private/tmp/supply3d_%s.png" % label, Vector2i(1920, 1080))

func _exercise_pointer(board: Control) -> bool:
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
	if is_equal_approx(before.yaw, after.yaw) or is_equal_approx(before.pitch, after.pitch):
		push_error("GUI drag must orbit the 3D camera")
		get_tree().quit(1)
		return false
	print("[3D] GUI right drag changed yaw and pitch")
	var pinch := InputEventMagnifyGesture.new()
	pinch.position = board.size * 0.5
	pinch.factor = 1.15
	get_viewport().push_input(pinch, true)
	await get_tree().process_frame
	if not is_equal_approx(board.call("capture_camera").span, after.span / 1.15):
		push_error("GUI pinch must zoom the 3D camera")
		get_tree().quit(1)
		return false
	print("[3D] GUI trackpad pinch changed zoom")
	return true

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

func _detail_review(board: Control, home: Dictionary) -> void:
	var focus: Vector3 = home.target
	for tile in board.get("_model").tiles.values():
		if "Snare Harbour Coast" in str(tile.label):
			focus = board.get("_builder").point(tile.center)
			break
	board.call("_select_tile", "")
	var texture_bytes := 0.0
	for item in board.get("_builder").terrain_lods:
		for texture in item.data.textures: texture_bytes += texture.get_width() * texture.get_height() * 4.0 * 4.0 / 3.0
	print("[LOD] retained terrain texture MiB=", texture_bytes / 1048576.0)
	for tier in 3:
		var state := home.duplicate()
		state.target = focus if tier > 0 else home.target
		state.span = [2200.0, 1100.0, 560.0][tier]
		board.call("restore_camera", state)
		await _shot("detail_%s" % ["far", "medium", "near"][tier])
		for warm in 60:
			RenderingServer.force_draw(false)
			await get_tree().process_frame
		var samples: Array[float] = []
		for frame in 45:
			var start := Time.get_ticks_usec()
			RenderingServer.force_draw(false)
			await get_tree().process_frame
			samples.append((Time.get_ticks_usec() - start) / 1000.0)
		samples.sort()
		print("[LOD] tier=", board.get("_detail"), " median_ms=", samples[22], " p95_ms=", samples[42],
			" draws=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			" triangles=", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			" texture_MiB=", Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0)
	# Rotation must retain the print pattern and directional volume at near detail.
	var close: Dictionary = board.call("capture_camera")
	close.yaw += PI * 0.65
	board.call("restore_camera", close)
	await _shot("detail_near_rotated")
	board.get_parent().set_process(false)
	board.hide()
	var wrapper := Control.new()
	board.get_parent().add_child(wrapper)
	wrapper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color("2b3757")
	wrapper.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var original := preload("res://scripts/empire_board.gd").new()
	wrapper.add_child(original)
	original.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.hide()
	await original.build_async(board.get("_last_graph"), board.get("_last_terrain"))
	for tier in [0, 1]:
		var span: float = [2200.0, 1100.0][tier]
		var target: Vector3 = home.target if tier == 0 else focus
		original.set("_zoom", original.size.y / span)
		original.set("_offset", original.size * 0.5 - original.iso(Vector2(target.x, target.z), target.y) * original.size.y / span)
		original.call("_view_changed")
		await Harness.await_board_baked(self, original, 20.0)
		original.modulate = Color.WHITE
		await _shot("reference_%s" % ["far", "medium"][tier])
	original.queue_free()
