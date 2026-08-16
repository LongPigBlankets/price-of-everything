extends Node
## Regression check for the editor's INPUT behaviour — the three things that were broken
## when the panel landed, each of which is invisible to a screenshot:
##
##   1. Escape returns to the menu. It did not, because the world is a CHILD of the editor
##      and `camera_controller` / `hex_map` / `world_map` all consume input before it.
##   2. Dragging in Navigate pans the view and authors NOTHING.
##   3. The pen still draws when it is the selected tool.
##
## Events go through `Input.parse_input_event`, i.e. the real pipeline, because the bug was
## in routing rather than in the handlers. Calling the handlers directly would have passed
## while the editor stayed broken.
##
##   <godot> --path . res://tools/map_editor/editor_input_check.tscn --quit-after 9000
## WINDOWED.

var _editor: Node
var _failures: PackedStringArray = []


func _ready() -> void:
	_editor = (load("res://tools/map_editor/map_editor.tscn") as PackedScene).instantiate()
	add_child(_editor)
	var waited := 0
	while waited < 1200 and not bool(_editor.call("is_ready_to_edit")):
		await get_tree().process_frame
		waited += 1
	if not bool(_editor.call("is_ready_to_edit")):
		push_error("[INPUT] editor never became ready")
		get_tree().quit(1)
		return

	_check("the game's input handlers are silenced",
		not _any_world_input_alive(_editor.get_node("WorldMap") if _editor.has_node("WorldMap") else _world_of()))
	_check("the default tool is Navigate", str(_editor.call("current_tool")) == "pan")

	# 2. Drag in Navigate: the camera must move and no road may appear.
	var camera: Camera2D = _editor.call("camera")
	var before_pos := camera.position
	var roads_before := _road_count()
	await _drag(Vector2(700, 400), Vector2(760, 460))
	_check("dragging in Navigate pans the view", camera.position != before_pos)
	_check("dragging in Navigate authors nothing", _road_count() == roads_before)

	# WASD pans, and keeps panning while the pen is the active tool — navigating mid-stroke
	# is normal when a road runs off the edge of the view.
	for entry in [["W", KEY_W, Vector2(0, -1)], ["S", KEY_S, Vector2(0, 1)],
			["A", KEY_A, Vector2(-1, 0)], ["D", KEY_D, Vector2(1, 0)]]:
		var from := camera.position
		await _hold_key(entry[1] as Key, 6)
		var moved: Vector2 = camera.position - from
		var want: Vector2 = entry[2]
		_check("%s pans the view the right way" % entry[0],
			moved.length() > 0.5 and moved.normalized().dot(want) > 0.99)

	# Zoom: the wheel must move it both ways and stop at the editor's own limits.
	var zoom_start := camera.zoom.x
	await _wheel(MOUSE_BUTTON_WHEEL_UP, Vector2(700, 400), 1)
	var zoomed_in := camera.zoom.x
	_check("wheel up zooms in", zoomed_in > zoom_start)
	await _wheel(MOUSE_BUTTON_WHEEL_DOWN, Vector2(700, 400), 2)
	_check("wheel down zooms out", camera.zoom.x < zoomed_in)
	await _wheel(MOUSE_BUTTON_WHEEL_UP, Vector2(700, 400), 60)
	_check("zoom stops at the near limit", camera.zoom.x <= 2.5 + 0.001)
	await _wheel(MOUSE_BUTTON_WHEEL_DOWN, Vector2(700, 400), 120)
	_check("zoom stops at the far limit", camera.zoom.x >= 0.12 - 0.001)
	_check("the whole map fits at the far limit",
		1920.0 / camera.zoom.x >= 13905.0)

	# Cursor anchoring: the world point under the pointer must stay under it, so zooming in
	# on a junction gets you closer to that junction instead of sliding it off screen.
	await _wheel(MOUSE_BUTTON_WHEEL_UP, Vector2(700, 400), 20)
	var probe := Vector2(1100, 620)
	var world_before: Vector2 = _editor.call("_world_at", probe)
	await _wheel(MOUSE_BUTTON_WHEEL_UP, probe, 3)
	var world_after: Vector2 = _editor.call("_world_at", probe)
	_check("zoom stays anchored on the cursor (%.1f u drift)" % world_before.distance_to(world_after),
		world_before.distance_to(world_after) < 1.0)

	# Q/E complete keyboard-only navigation alongside WASD.
	var key_zoom_from := camera.zoom.x
	_send_key(KEY_E)
	await get_tree().process_frame
	_check("E zooms in", camera.zoom.x > key_zoom_from)
	_send_key(KEY_Q)
	await get_tree().process_frame
	_send_key(KEY_Q)
	await get_tree().process_frame
	_check("Q zooms out", camera.zoom.x < key_zoom_from)

	# 3. The pen draws when selected.
	_editor.call("set_tool", "road")
	_check("the pen can be selected", str(_editor.call("current_tool")) == "road")
	var pen_from := camera.position
	await _hold_key(KEY_D, 6)
	_check("WASD still pans while the pen is active", camera.position != pen_from)
	await _click(Vector2(600, 400))
	await _click(Vector2(800, 500))
	_send_key(KEY_ENTER)
	await get_tree().process_frame
	_check("the pen commits a stroke", _road_count() == roads_before + 1)

	# 1. Escape reaches the editor. Observed by ARMING rather than by the scene actually
	# changing: leaving frees the current scene, which is this harness (the editor is its
	# child), so the run would die mid-await and report nothing. The document is dirty from
	# the stroke above, so the first press arms the discard — and arming at all is precisely
	# what was impossible while the game was eating the key.
	var document: RefCounted = _editor.call("document")
	_check("Escape is not armed before the key", not bool(document.call("discard_armed")))
	_send_key(KEY_ESCAPE)
	await get_tree().process_frame
	_check("Escape reaches the editor (arms the unsaved-work guard)",
		bool(document.call("discard_armed")))

	# ── The three added draw modes ──────────────────────────────────────────────
	var doc: RefCounted = _editor.call("document")

	# FREEHAND: press, drag along a path, release -> one simplified stroke.
	_editor.call("set_tool", "trace")
	var before_trace := _road_count()
	await _trace_path([Vector2(400, 300), Vector2(500, 330), Vector2(600, 300),
		Vector2(700, 340), Vector2(820, 300)])
	_check("freehand commits a stroke", _road_count() == before_trace + 1)
	var traced := _last_stroke(doc)
	var traced_points: int = (traced.get("points", []) as Array).size()
	# The gesture above sent 5 waypoints plus interpolated motion; a stroke that kept every
	# sample would be unusable as an object. It must also keep more than a bare line.
	_check("freehand simplifies the path (%d points)" % traced_points,
		traced_points >= 2 and traced_points <= 8)

	# CONNECT THE DOTS: two dots, then a link between them.
	_editor.call("set_tool", "dots")
	var before_dots := _road_count()
	await _click(Vector2(500, 600))
	await _click(Vector2(760, 660))
	_check("dots are not roads until joined", _road_count() == before_dots)
	_check("two dots exist", (_editor.call("trace_tool").call("dots") as PackedVector2Array).size() == 2)
	await _click(Vector2(500, 600))
	await _click(Vector2(760, 660))
	_check("joining two dots makes a stroke", _road_count() == before_dots + 1)
	var joined := _last_stroke(doc)
	_check("a joined stroke is a straight run",
		(joined.get("points", []) as Array).size() == 2)

	# ADD ANCHOR: click that straight run, drag, and both segments should bow.
	_editor.call("set_tool", "anchor")
	var mid := Vector2(630, 630)
	var before_points: int = (joined.get("points", []) as Array).size()
	await _drag(mid, mid + Vector2(0, 70))
	var shaped := _last_stroke(doc)
	var shaped_points: Array = shaped.get("points", []) as Array
	_check("the anchor tool inserts a point (%d -> %d)" % [before_points, shaped_points.size()],
		shaped_points.size() == before_points + 1)
	var middle: Array = shaped_points[1] if shaped_points.size() > 2 else []
	_check("the inserted point carries curve handles",
		middle.size() >= 6 and (Vector2(float(middle[4]), float(middle[5]))).length() > 0.5)
	_check("dragging the anchor moved it off the straight line",
		middle.size() >= 2 and absf(float(middle[1]) - 630.0) > 1.0)

	if _failures.is_empty():
		print("[INPUT] ALL CHECKS PASSED")
		get_tree().quit(0)
	else:
		for failure in _failures:
			print("[INPUT] FAILED: %s" % failure)
		get_tree().quit(1)


func _world_of() -> Node:
	for child in _editor.get_children():
		if child.name == "WorldMap":
			return child
	return null


## True if any node under the world still processes input — the condition that let the game
## swallow Escape and fight the drag.
func _any_world_input_alive(node: Node) -> bool:
	if node == null:
		return false
	if node.is_processing_input() or node.is_processing_unhandled_input():
		return true
	for child in node.get_children():
		if _any_world_input_alive(child):
			return true
	return false


func _road_count() -> int:
	var counts: Dictionary = _editor.call("document").call("counts")
	return int(counts.get("roads", 0))


func _click(at: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = at
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = at
	Input.parse_input_event(up)
	await get_tree().process_frame


func _drag(from: Vector2, to: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = from
	Input.parse_input_event(down)
	await get_tree().process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = to
	motion.relative = to - from
	Input.parse_input_event(motion)
	await get_tree().process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = to
	Input.parse_input_event(up)
	await get_tree().process_frame


## The most recently added stroke of the first settlement — the one a tool just committed.
func _last_stroke(document: RefCounted) -> Dictionary:
	var data: Dictionary = document.call("data")
	var settlements: Dictionary = data.get("settlements", {})
	for key in settlements.keys():
		var roads: Array = (settlements[key] as Dictionary).get("roads", []) as Array
		if not roads.is_empty():
			return roads[roads.size() - 1]
	return {}


## Press, move through every waypoint, release — a freehand gesture.
func _trace_path(waypoints: Array) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = waypoints[0]
	Input.parse_input_event(down)
	await get_tree().process_frame
	for i in range(1, waypoints.size()):
		var motion := InputEventMouseMotion.new()
		motion.position = waypoints[i]
		motion.relative = (waypoints[i] as Vector2) - (waypoints[i - 1] as Vector2)
		Input.parse_input_event(motion)
		await get_tree().process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = waypoints[waypoints.size() - 1]
	Input.parse_input_event(up)
	await get_tree().process_frame


func _wheel(button: MouseButton, at: Vector2, times: int) -> void:
	for _i in times:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = true
		event.position = at
		Input.parse_input_event(event)
		await get_tree().process_frame


## Hold a key down for a few frames, then release. Panning is polled in `_process`, not
## driven by key events, so a single parsed event would move the camera by nothing.
func _hold_key(code: Key, frames: int) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = code
	down.keycode = code
	down.pressed = true
	Input.parse_input_event(down)
	for _i in frames:
		await get_tree().process_frame
	var up := InputEventKey.new()
	up.physical_keycode = code
	up.keycode = code
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


func _send_key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)


func _check(what: String, ok: bool) -> void:
	print("[INPUT] %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures.append(what)
