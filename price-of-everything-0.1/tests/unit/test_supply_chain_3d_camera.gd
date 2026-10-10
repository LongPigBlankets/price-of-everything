extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Board := preload("res://scripts/supply_chain_3d/board.gd")

func _test_camera_pan_keeps_sprite_angle() -> void:
	var camera := Camera3D.new()
	add_child(camera)
	var rig := Board.Rig.new()
	var stable := true
	# Exact atlas boundaries are where tiny look_at() rounding switched views.
	for yaw in [PI / 16.0, PI * 3.0 / 16.0, Board.Rig.HOME_YAW]:
		for pitch in [Board.Rig.HOME_PITCH, 0.43125, 0.69375]:
			rig.yaw = yaw
			rig.pitch = pitch
			rig.target = Vector3(10395, 34, 4320)
			rig.apply(camera)
			var basis := camera.basis
			for i in 300:
				rig.pan(Vector2(3, 1), 1080)
				rig.apply(camera)
				stable = stable and camera.basis == basis
	_check(stable, "3D camera: panning across the map keeps an identical view basis at sprite-angle boundaries")
	camera.queue_free()
	await get_tree().process_frame

func _test_camera_continent_starts_medium() -> void:
	var board := Board.new()
	board.size = Vector2(1280, 720)
	add_child(board)
	board.set_process(false)
	var state := {"yaw": 0.72, "pitch": 0.68, "span": 1700.0, "target": Vector3(9000, 34, 4000)}
	board.restore_camera(state)
	board._medium_view()
	var medium: Dictionary = board.capture_camera()
	_check(medium.target == state.target and is_equal_approx(medium.yaw, state.yaw) and medium.pitch == state.pitch,
		"3D camera: medium entry preserves the current location and viewing angle")
	_check(Board.Detail.choose(board.size.y / medium.span) == 1,
		"3D camera: initial continent span selects medium detail at the actual UI resolution")
	board.queue_free()
	await get_tree().process_frame

func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _test_camera_pointer_controls() -> void:
	var board := Board.new()
	board.size = Vector2(1280, 720)
	add_child(board)
	board.set_process(false)
	var selected: Array = []
	board.tile_picked.connect(func(id: String) -> void: selected.append(id))
	board.building_picked.connect(func(id: String) -> void: selected.append(id))
	var initial: Dictionary = board.capture_camera()
	var button := InputEventMouseButton.new()
	button.position = board.size * 0.5
	button.button_index = MOUSE_BUTTON_MIDDLE
	button.pressed = true
	board._gui_input(button)
	var motion := InputEventMouseMotion.new()
	motion.position = button.position + Vector2(80, -30)
	motion.relative = Vector2(80, -30)
	motion.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	board._gui_input(motion)
	button.position = motion.position
	button.pressed = false
	board._gui_input(button)
	var orbit: Dictionary = board.capture_camera()
	_check(not is_equal_approx(orbit.yaw, initial.yaw) and not is_equal_approx(orbit.pitch, initial.pitch)
		and orbit.target == initial.target and orbit.span == initial.span,
		"3D camera: middle drag changes yaw and tilt without translating or zooming")
	motion.position += motion.relative
	board._gui_input(motion)
	_check(board.capture_camera() == orbit and selected.is_empty(),
		"3D camera: releasing middle drag stops rotation without selecting terrain or buildings")
	var pan := InputEventPanGesture.new()
	pan.position = board.size * 0.5
	pan.delta = Vector2(2, 1)
	for key in [KEY_0, KEY_KP_0]:
		board.restore_camera(initial)
		_key(key, true)
		board._gui_input(pan)
		orbit = board.capture_camera()
		_check(not is_equal_approx(orbit.yaw, initial.yaw) and not is_equal_approx(orbit.pitch, initial.pitch)
			and orbit.target == initial.target and orbit.span == initial.span,
			"3D camera: holding %s turns a two-finger pan into yaw and tilt" % OS.get_keycode_string(key))
		_key(key, false)
		board._gui_input(pan)
		var moved: Dictionary = board.capture_camera()
		_check(moved.target != orbit.target and moved.yaw == orbit.yaw and moved.pitch == orbit.pitch,
			"3D camera: releasing %s immediately restores ordinary trackpad pan" % OS.get_keycode_string(key))
	_key(KEY_0, true)
	var before_zoom: Dictionary = board.capture_camera()
	var pinch := InputEventMagnifyGesture.new()
	pinch.position = pan.position
	pinch.factor = 1.2
	board._gui_input(pinch)
	_key(KEY_0, false)
	var zoomed: Dictionary = board.capture_camera()
	_check(is_equal_approx(zoomed.span, before_zoom.span / 1.2)
		and zoomed.yaw == before_zoom.yaw and zoomed.pitch == before_zoom.pitch,
		"3D camera: holding 0 still allows pinch zoom without changing the angle")
	_check(selected.is_empty(), "3D camera: trackpad gestures do not activate a tile or building")
	board.queue_free()
	await get_tree().process_frame
