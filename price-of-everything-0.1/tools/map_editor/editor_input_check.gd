extends Node

const AuthoredSpecialShapesScript := preload("res://scripts/authored_special_shapes.gd")
const AuthoredRoadGeometryScript := preload("res://scripts/authored_road_geometry.gd")
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
	# The editor drives itself from synthetic input here, and a computed click can land on
	# the tool panel and press a button. Scratch mode makes that harmless: the editor opens
	# an empty document and cannot write to a real one.
	OS.set_environment("POE_EDITOR_SCRATCH", "1")
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

	# ── Upgrade ─────────────────────────────────────────────────────────────────
	# The click point is derived from the stroke's OWN geometry. Guessing screen coordinates
	# made two of these checks pass while the clicks were missing the road entirely and the
	# class never changed — a test that passes when the feature does nothing is worse than no
	# test at all.
	_editor.call("set_tool", "upgrade")
	var target := _last_stroke(doc)
	var on_road := _screen_of(_midpoint(target), camera)
	_check("the upgrade target starts below major",
		str(target.get("class", "")) != "major")
	# Walk the whole ladder down to minor first, so the climb exercises every rung —
	# the owner's requirement is one click each from minor to mid to major.
	for _i in 3:
		await _shift_click(on_road)
	_check("Shift-click narrows down to minor and stops there (%s)"
		% str(_last_stroke(doc).get("class", "")),
		str(_last_stroke(doc).get("class", "")) == "minor")
	var seen: Array = [str(_last_stroke(doc).get("class", ""))]
	for _i in 3:
		await _click(on_road)
		# The stroke does not move when its class changes, but re-reading keeps this honest
		# if that ever stops being true.
		seen.append(str(_last_stroke(doc).get("class", "")))
	_check("one click per rung: minor to mid to major, then it stops (%s)" % ", ".join(seen),
		seen == ["minor", "mid", "major", "major"])

	# ── Select and delete ───────────────────────────────────────────────────────
	_editor.call("set_tool", "select")
	var total_before := _road_count()
	await _drag(Vector2(300, 560), Vector2(1050, 780))
	var picked := int(_editor.call("selection_size"))
	_check("a marquee selects the roads it covers (%d)" % picked, picked > 0)
	_check("the marquee does not delete on its own", _road_count() == total_before)

	# Deletion must ask first — it is the only action here that destroys authored work.
	_send_key(KEY_DELETE)
	await get_tree().process_frame
	_check("Delete asks for confirmation", _road_count() == total_before)
	_send_key(KEY_ESCAPE)
	await get_tree().process_frame
	_check("cancelling the prompt keeps everything", _road_count() == total_before)
	_check("cancelling keeps the selection", int(_editor.call("selection_size")) == picked)

	_send_key(KEY_DELETE)
	await get_tree().process_frame
	_send_key(KEY_ENTER)
	await get_tree().process_frame
	_check("confirming removes the selected roads",
		_road_count() == total_before - picked)

	# The tile list is the suppression key: a tile left listed with nothing drawn on it is a
	# hole in the map — procedural content stood down, authored content deleted.
	var data: Dictionary = doc.call("data")
	var settlements: Dictionary = data.get("settlements", {})
	var stale := false
	for key in settlements.keys():
		var settlement: Dictionary = settlements[key]
		var covered: Dictionary = {}
		for road_value in (settlement.get("roads", []) as Array):
			for tile_id in ((road_value as Dictionary).get("tiles", []) as Array):
				covered[str(tile_id)] = true
		for tile_id in (settlement.get("tiles", []) as Array):
			if not covered.has(str(tile_id)):
				stale = true
	_check("deletion rebuilds the settlement's tile coverage", not stale)

	# ── Parametric primitives, and dragging their corners ───────────────────────
	_editor.call("pick_special", "ring")
	_check("picking a primitive selects its tool", str(_editor.call("current_tool")) == "special")
	await _click(Vector2(520, 300))
	var ring := _last_of(doc, "specials")
	_check("clicking lays the primitive", not ring.is_empty())
	_check("it carries its side lengths (%d)" % (ring.get("sides", []) as Array).size(),
		(ring.get("sides", []) as Array).size() == 4)
	# The ring stores its FOUR outer corners; the courtyard band is derived at draw time. The
	# band carries a seam, and its duplicate points made corner dragging grab the wrong
	# vertex — which is why the editable shape and the drawn shape are deliberately not the
	# same polygon.
	var corners_before: int = (ring.get("outline", []) as Array).size()
	_check("a ring is stored as four editable corners (%d)" % corners_before,
		corners_before == 4)
	var drawn: PackedVector2Array = AuthoredSpecialShapesScript.render_polygon(ring)
	_check("a ring DRAWS as a band with a courtyard (%d points)" % drawn.size(),
		drawn.size() >= 8)

	# Parameters rebuild the outline. Grow one side and the shape must get wider.
	var width_before := _outline_width(ring)
	_editor.call("adjust_special_side", 0, 40.0)
	var width_after := _outline_width(_last_of(doc, "specials"))
	_check("a side length rebuilds the shape (%.0f -> %.0f)" % [width_before, width_after],
		width_after > width_before + 10.0)

	# Selecting it shows its corners; dragging one moves that corner and nothing else.
	_editor.call("set_tool", "select")
	var centre := _outline_centre(_last_of(doc, "specials"))
	await _drag(_screen_of(centre - Vector2(160, 130), camera),
		_screen_of(centre + Vector2(160, 130), camera))
	var handles: PackedVector2Array = _editor.call("editable_corners")
	_check("selecting one shape shows its corners (%d)" % handles.size(), handles.size() == 4)
	if handles.size() == 4:
		var moved_from := handles[0]
		var others_before := _outline_points(_last_of(doc, "specials"))
		await _drag(_screen_of(moved_from, camera),
			_screen_of(moved_from + Vector2(-45.0, -38.0), camera))
		var after := _outline_points(_last_of(doc, "specials"))
		_check("dragging a corner moves it (%.0f u)" % moved_from.distance_to(after[0]),
			moved_from.distance_to(after[0]) > 20.0)
		var others_moved := 0
		for i in range(1, mini(others_before.size(), after.size())):
			if others_before[i].distance_to(after[i]) > 0.01:
				others_moved += 1
		_check("dragging a corner leaves the others alone (%d moved)" % others_moved,
			others_moved == 0)

	# ── Select: drag moves, click selects ───────────────────────────────────────
	# The same button does three things depending on what is under it, so each is checked
	# against the other two: a move must not select, a click must not move.
	_editor.call("set_tool", "select")
	var special := _last_of(doc, "specials")
	var before_centre := _outline_centre(special)

	# 1. Drag ON the shape: it moves, and nothing is left selected by the gesture.
	await _drag(_screen_of(before_centre, camera),
		_screen_of(before_centre + Vector2(90.0, 60.0), camera))
	var after_centre := _outline_centre(_last_of(doc, "specials"))
	var shift := after_centre - before_centre
	_check("dragging a shape moves it (%.0f, %.0f)" % [shift.x, shift.y],
		shift.distance_to(Vector2(90.0, 60.0)) < 12.0)
	_check("the shape keeps its size while moving",
		absf(_outline_width(_last_of(doc, "specials")) - _outline_width(special)) < 0.01)

	# 2. Click ON the shape (press and release, no travel): it selects, and does not move.
	var settled := _outline_centre(_last_of(doc, "specials"))
	await _click(_screen_of(settled, camera))
	_check("clicking a shape selects it", int(_editor.call("selection_size")) == 1)
	_check("clicking does not move it",
		_outline_centre(_last_of(doc, "specials")).distance_to(settled) < 0.01)
	_check("clicking a primitive opens its corners",
		(_editor.call("editable_corners") as PackedVector2Array).size() == 4)
	_check("clicking a primitive opens its side lengths",
		(_editor.call("special_sides") as Array).size() == 4)

	# 3. Drag on EMPTY ground still box-selects rather than moving anything.
	var empty := settled + Vector2(900.0, 900.0)
	await _drag(_screen_of(empty, camera), _screen_of(empty + Vector2(120.0, 90.0), camera))
	_check("dragging empty ground box-selects instead of moving",
		int(_editor.call("selection_size")) == 0
			and _outline_centre(_last_of(doc, "specials")).distance_to(settled) < 0.01)

	# ── Snapping, the Ctrl override, and +/- resize ─────────────────────────────
	# Draw a straight road, then drop a primitive near it and drag it closer.
	_editor.call("set_road_class", "mid")
	_editor.call("set_tool", "road")
	var road_a := Vector2(400, 250)
	var road_b := Vector2(1000, 250)
	await _click(road_a)
	await _click(road_b)
	_send_key(KEY_ENTER)
	await get_tree().process_frame

	# A stamped square, not a primitive: an L's centre sits in its notch — outside the shape
	# and near its inner corner — so a grab there picks up a corner handle instead, which is
	# correct behaviour and a terrible thing to test a move with.
	_editor.call("pick_form", "square")
	await _drag_stamp_at(Vector2(700, 430), Vector2(760, 470))
	var block := _last_of(doc, "decor")
	_check("a mass was stamped to move", not block.is_empty())
	_editor.call("set_tool", "select")

	# Drag it toward the road; it should seat itself at a kerb rather than where the pointer
	# stopped. Measured against the NEAREST road, since the document has many.
	var from := _mass_centre(block)
	await _drag(_screen_of(from, camera), Vector2(700, 330))
	var seated := _mass_centre(_last_of(doc, "decor"))
	var gap := _nearest_road_distance(doc, seated)
	_check("a dragged building seats itself at a kerb (%.0f u from the nearest road)" % gap,
		gap > 4.0 and gap < 80.0)
	var released_at := _world_at(Vector2(700, 330))
	_check("snapping overrides where the pointer stopped",
		seated.distance_to(released_at) > 1.0)

	# Ctrl suppresses it: the shape stays where it was let go.
	var free_from := _mass_centre(_last_of(doc, "decor"))
	await _drag_modified(_screen_of(free_from, camera), Vector2(660, 560), true)
	var free_at := _mass_centre(_last_of(doc, "decor"))
	var wanted := _world_at(Vector2(660, 560))
	_check("holding Ctrl places it exactly where dropped (%.0f u off)"
		% free_at.distance_to(wanted), free_at.distance_to(wanted) < 8.0)

	# +/- resize the selection in 10% steps.
	await _click(_screen_of(free_at, camera))
	_check("clicking the mass selects it", int(_editor.call("selection_size")) == 1)
	var pre_resize := _mass_width(_last_of(doc, "decor"))
	_send_key(KEY_EQUAL)
	await get_tree().process_frame
	var grown := _mass_width(_last_of(doc, "decor"))
	_check("+ grows the selection 10%% (%.0f -> %.0f)" % [pre_resize, grown],
		absf(grown - pre_resize * 1.1) < 0.5)
	_send_key(KEY_MINUS)
	await get_tree().process_frame
	_check("- shrinks it back (%.0f)" % _mass_width(_last_of(doc, "decor")),
		absf(_mass_width(_last_of(doc, "decor")) - pre_resize) < 0.5)

	# ── Rotation, and corners on a rectangular mass ─────────────────────────────
	var turn_target := _last_of(doc, "decor")
	var corner_before: PackedVector2Array = _editor.call("editable_corners")
	_check("a stamped mass offers its box corners (%d)" % corner_before.size(),
		corner_before.size() == 4)
	var before_angle := float(turn_target.get("rot", 0.0))
	_send_key(KEY_Z)
	await get_tree().process_frame
	var after_z := float(_last_of(doc, "decor").get("rot", 0.0))
	_check("Z turns it 5 degrees clockwise (%.1f deg)" % rad_to_deg(after_z - before_angle),
		absf(rad_to_deg(after_z - before_angle) - 5.0) < 0.01)
	_send_key(KEY_Y)
	await get_tree().process_frame
	_check("Y turns it back", absf(float(_last_of(doc, "decor").get("rot", 0.0))
		- before_angle) < 0.001)

	# Dragging a corner of a rectangular mass makes it an irregular quad, and the form is
	# re-fitted into it rather than staying a rectangle.
	var box: PackedVector2Array = _editor.call("editable_corners")
	if box.size() == 4:
		var grabbed := box[0]
		await _drag(_screen_of(grabbed, camera), _screen_of(grabbed + Vector2(-40.0, -34.0), camera))
		var reshaped := _last_of(doc, "decor")
		_check("a mass keeps an explicit parcel once a corner is dragged",
			reshaped.has("parcel"))
		var moved: PackedVector2Array = _editor.call("editable_corners")
		_check("the dragged corner moved (%.0f u)" % grabbed.distance_to(moved[0]),
			moved.size() == 4 and grabbed.distance_to(moved[0]) > 20.0)
		var others := 0
		for i in range(1, 4):
			if box[i].distance_to(moved[i]) > 0.01:
				others += 1
		_check("the other three corners stayed put (%d moved)" % others, others == 0)

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


## The midpoint of a stroke's first segment — a point guaranteed to lie on the line.
func _midpoint(stroke: Dictionary) -> Vector2:
	var points: Array = stroke.get("points", []) as Array
	if points.size() < 2:
		return Vector2.ZERO
	var a: Array = points[0]
	var b: Array = points[1]
	return Vector2(float(a[0]), float(a[1])).lerp(Vector2(float(b[0]), float(b[1])), 0.5)


## World to screen — the inverse of the editor's own `_world_at`.
func _mass_centre(record: Dictionary) -> Vector2:
	var pos: Array = record.get("pos", [0, 0]) as Array
	return Vector2(float(pos[0]), float(pos[1])) if pos.size() >= 2 else Vector2.ZERO


func _mass_width(record: Dictionary) -> float:
	var size: Array = record.get("size", [0, 0]) as Array
	return float(size[0]) if size.size() >= 1 else 0.0


## Distance from a point to the nearest authored road, so a snap can be asserted without
## assuming which road it chose — the loaded document has plenty.
func _nearest_road_distance(document: RefCounted, world: Vector2) -> float:
	var best := INF
	var data: Dictionary = document.call("data")
	for key in (data.get("settlements", {}) as Dictionary).keys():
		var settlement: Dictionary = (data["settlements"] as Dictionary)[key]
		for stroke_value in (settlement.get("roads", []) as Array):
			var points := AuthoredRoadGeometryScript.sample(stroke_value as Dictionary)
			for i in range(1, points.size()):
				best = minf(best, world.distance_to(Geometry2D.get_closest_point_to_segment(
					world, points[i - 1], points[i])))
	return best


func _drag_stamp_at(from: Vector2, to: Vector2) -> void:
	await _drag(from, to)


func _world_at(screen: Vector2) -> Vector2:
	return _editor.call("_world_at", screen)


func _screen_of(world: Vector2, camera: Camera2D) -> Vector2:
	var viewport_size := get_viewport().get_visible_rect().size
	return (world - camera.get_screen_center_position()) * camera.zoom.x + viewport_size * 0.5


func _shift_click(at: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = at
	down.shift_pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = at
	up.shift_pressed = true
	Input.parse_input_event(up)
	await get_tree().process_frame


## A drag with Ctrl held, for the snap override.
func _drag_modified(from: Vector2, to: Vector2, ctrl: bool) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = from
	down.ctrl_pressed = ctrl
	Input.parse_input_event(down)
	await get_tree().process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = to
	motion.relative = to - from
	motion.ctrl_pressed = ctrl
	Input.parse_input_event(motion)
	await get_tree().process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = to
	up.ctrl_pressed = ctrl
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
## The most recently added record of a kind, in the first settlement that has one.
func _last_of(document: RefCounted, kind: String) -> Dictionary:
	var data: Dictionary = document.call("data")
	var settlements: Dictionary = data.get("settlements", {})
	for key in settlements.keys():
		var items: Array = (settlements[key] as Dictionary).get(kind, []) as Array
		if not items.is_empty():
			return items[items.size() - 1]
	return {}


func _outline_points(record: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	for entry in (record.get("outline", []) as Array):
		var values: Array = entry as Array
		if values != null and values.size() >= 2:
			out.append(Vector2(float(values[0]), float(values[1])))
	return out


func _outline_width(record: Dictionary) -> float:
	var points := _outline_points(record)
	if points.is_empty():
		return 0.0
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	return bounds.size.x


func _outline_centre(record: Dictionary) -> Vector2:
	var points := _outline_points(record)
	if points.is_empty():
		return Vector2.ZERO
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	return bounds.get_center()


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
