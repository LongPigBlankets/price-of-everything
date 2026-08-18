extends Node

const AuthoredSpecialShapesScript := preload("res://scripts/authored_special_shapes.gd")
const AuthoredRoadGeometryScript := preload("res://scripts/authored_road_geometry.gd")
const AuthoredRoadStyleScript := preload("res://scripts/authored_road_style.gd")
const MapEditorSlotBoxes := preload("res://scripts/map_editor/map_editor_slot_boxes.gd")
const AuthoredMapRef := preload("res://scripts/authored_map.gd")
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
	var stuck := PackedStringArray()
	for entry in [["W", KEY_W], ["A", KEY_A], ["S", KEY_S], ["D", KEY_D],
			["Q", KEY_Q], ["E", KEY_E]]:
		if Input.is_physical_key_pressed(entry[1] as Key):
			stuck.append(str(entry[0]))
	_check("no pan key is still held before the anchor probe (%s)"
		% ("none" if stuck.is_empty() else ", ".join(stuck)), stuck.is_empty())
	var probe := Vector2(1100, 620)
	var drift_from: Vector2 = camera.position
	var world_before: Vector2 = _editor.call("_world_at", probe)
	await _wheel(MOUSE_BUTTON_WHEEL_UP, probe, 3)
	var world_after: Vector2 = _editor.call("_world_at", probe)
	_check("the camera only moved as much as the zoom compensation needed (%.1f u)"
		% camera.position.distance_to(drift_from),
		camera.position.distance_to(drift_from) < 400.0)
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
	_send_key(KEY_ESCAPE)
	await get_tree().process_frame
	_check("Escape asks before leaving, rather than leaving",
		bool(_editor.call("confirm_open")))
	_send_key(KEY_ESCAPE)
	await get_tree().process_frame
	_check("a second Escape dismisses the question", not bool(_editor.call("confirm_open")))

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
	_send_key(KEY_BACKSPACE)
	await get_tree().process_frame
	_check("Backspace asks for confirmation", _road_count() == total_before)
	_send_key(KEY_ESCAPE)
	await get_tree().process_frame
	_check("cancelling the prompt keeps everything", _road_count() == total_before)
	_check("cancelling keeps the selection", int(_editor.call("selection_size")) == picked)

	_send_key(KEY_BACKSPACE)
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
	await _drag_stamp_at(Vector2(1020, 620), Vector2(1080, 660))
	var block := _last_of(doc, "decor")
	_check("a mass was stamped to move", not block.is_empty())
	_editor.call("set_tool", "select")

	# Drag it toward the road; it should seat itself at a kerb rather than where the pointer
	# stopped. Measured against the NEAREST road, since the document has many.
	var from := _mass_centre(block)
	# A PLAIN drag is literal — snapping is opt-in (owner, 2026-08-16).
	await _drag(_screen_of(from, camera), Vector2(1020, 520))
	var dropped := _mass_centre(_last_of(doc, "decor"))
	var literal := _world_at(Vector2(1020, 520))
	_check("a plain drag drops it exactly where the pointer stopped (%.0f u off)"
		% dropped.distance_to(literal), dropped.distance_to(literal) < 8.0)

	# Holding Ctrl asks for the kerb.
	await _drag_modified(_screen_of(dropped, camera), Vector2(1020, 470), true)
	var free_at := _mass_centre(_last_of(doc, "decor"))
	var gap := _nearest_road_distance(doc, free_at)
	_check("holding Ctrl seats it at a kerb (%.0f u from the nearest road)" % gap,
		gap > 4.0 and gap < 80.0)
	# Deliberately NOT asserting that the snap moved the shape: whether it does depends on
	# where the pointer happened to stop relative to the kerb, so a drop that already lands
	# on the kerb would fail a check the feature passed. Sitting at a kerb is the contract.
	_check("the snapped gap matches a kerb offset rather than a coincidence",
		gap > AuthoredRoadStyleScript.bed_width("mid") * 0.5)

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
	_send_key(KEY_BRACKETRIGHT)
	await get_tree().process_frame
	var after_z := float(_last_of(doc, "decor").get("rot", 0.0))
	_check("] turns it 5 degrees clockwise (%.1f deg)" % rad_to_deg(after_z - before_angle),
		absf(rad_to_deg(after_z - before_angle) - 5.0) < 0.01)
	_send_key(KEY_BRACKETLEFT)
	await get_tree().process_frame
	_check("[ turns it back", absf(float(_last_of(doc, "decor").get("rot", 0.0))
		- before_angle) < 0.001)

	# Z is undo again. It was shadowed by a duplicate match arm, so Ctrl+Z did nothing at all
	# — the kind of thing that only shows up when someone reaches for it.
	# Undo must actually change something. The rotation just applied is the thing to undo,
	# so this asserts the angle returns — the earlier version compared road counts with an
	# `or n >= 0` fallback, which is true whatever happens and tested nothing.
	_send_key(KEY_BRACKETRIGHT)
	await get_tree().process_frame
	var turned := float(_last_of(doc, "decor").get("rot", 0.0))
	_send_key_mod(KEY_Z, true, false)
	await get_tree().process_frame
	var undone := float(_last_of(doc, "decor").get("rot", 0.0))
	_check("Ctrl+Z undoes the rotation (%.1f -> %.1f deg)"
		% [rad_to_deg(turned), rad_to_deg(undone)], absf(undone - turned) > 0.01)
	_send_key_mod(KEY_Z, true, true)
	await get_tree().process_frame
	_check("Ctrl+Shift+Z redoes it",
		absf(float(_last_of(doc, "decor").get("rot", 0.0)) - turned) < 0.01)

	# Arrows move the selected SHAPE too, not only slots — same polled nudge, so a shape that
	# did not move would mean the selection never reached it.
	var nudge_from := _mass_centre(_last_of(doc, "decor"))
	await _hold_key(KEY_DOWN, 14)
	var nudge_to := _mass_centre(_last_of(doc, "decor"))
	_check("holding Down nudges the selected mass south (%.1f u)" % (nudge_to.y - nudge_from.y),
		nudge_to.y - nudge_from.y > 0.5 and absf(nudge_to.x - nudge_from.x) < 0.01)

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

	# The free polygon: up to six corners, then Enter.
	_editor.call("pick_special", "poly")
	for at in [Vector2(400, 300), Vector2(520, 280), Vector2(560, 380), Vector2(430, 400)]:
		await _click(at)
	_check("corners accumulate (%d)" % (_editor.call("poly_points") as Array).size(),
		(_editor.call("poly_points") as Array).size() == 4)
	var poly_doc: RefCounted = _editor.call("document")
	var specials_before := str((_last_of(poly_doc, "specials") as Dictionary).get("id", ""))
	_send_key(KEY_ENTER)
	await get_tree().process_frame
	var shape := _last_of(poly_doc, "specials")
	_check("Enter closes the free polygon", str(shape.get("id", "")) != str(specials_before))
	_check("it keeps every corner (%d)" % (shape.get("outline", []) as Array).size(),
		(shape.get("outline", []) as Array).size() == 4)
	_check("it has no side parameters", (shape.get("sides", []) as Array).is_empty())

	# ── Gameplay slots ──────────────────────────────────────────────────────────
	# A slot is reserved ground, not a drawn thing, so everything about handling it has to be
	# proven rather than seen: that a click finds it at all, that it carries the class the
	# panel asked for, and that arrows and brackets move the record and not just a highlight.
	# Class names come from the shipped ladder — they have been renamed twice, and a literal
	# here fails as a broken editor rather than as an out-of-date check.
	var first_slot_class := str(AuthoredMapRef.SLOT_BOX_CLASSES[0])
	_editor.call("pick_slot_class", first_slot_class)
	await _click(Vector2(660, 420))
	var slot := _first_slot(doc)
	_check("a %s slot lands on the tile" % first_slot_class, not slot.is_empty()
		and str(slot.get("size", "")) == first_slot_class)
	if not slot.is_empty():
		var boxes: Array = _editor.call("document_slot_boxes")
		var slot_box: Dictionary = {}
		for candidate in boxes:
			if str((candidate as Dictionary).get("class", "")) == first_slot_class:
				slot_box = candidate
				break
		_check("the overlay gets a box for it (%d box(es))" % boxes.size(), not slot_box.is_empty())
		if not slot_box.is_empty():
			# Read the shipped table, never a literal. The boxes are DERIVED from the art
			# constants now, and a hardcoded 62 here is the same drift this whole area has
			# already produced twice.
			var sizes: Dictionary = MapEditorSlotBoxes.sizes()
			var biggest := str(AuthoredMapRef.SLOT_BOX_CLASSES[
				AuthoredMapRef.SLOT_BOX_CLASSES.size() - 1])
			_check("the box is the %s size, not the %s one (%.0f)"
				% [first_slot_class, biggest, (slot_box["size"] as Vector2).x],
				(slot_box["size"] as Vector2).is_equal_approx(sizes[first_slot_class])
				and sizes[first_slot_class] != sizes[biggest])
			# Picking it: the click has to land on the slot even though there is drawn fabric
			# under it — a slot sits ON the ground it reserves, so it is tested first.
			_editor.call("set_tool", "select")
			await _click(_screen_of(slot_box["centre"] as Vector2, camera))
			_check("clicking it picks it up",
				not (_editor.call("picked_slot") as Dictionary).is_empty())

			var slot_from: Array = (_first_slot(doc).get("pos", [0, 0]) as Array).duplicate()
			await _hold_key(KEY_RIGHT, 14)
			var slot_to: Array = _first_slot(doc).get("pos", [0, 0]) as Array
			var slot_dx := float(slot_to[0]) - float(slot_from[0])
			_check("holding Right nudges it east (%.1f u)" % slot_dx, slot_dx > 0.5)
			_check("and leaves its northing alone (%.2f u)"
				% (float(slot_to[1]) - float(slot_from[1])),
				absf(float(slot_to[1]) - float(slot_from[1])) < 0.01)
			# Continuous, not one step per repeat: a longer press must travel further.
			var press_from: Array = (_first_slot(doc).get("pos", [0, 0]) as Array).duplicate()
			await _hold_key(KEY_RIGHT, 42)
			var press_dx := float((_first_slot(doc).get("pos", [0, 0]) as Array)[0]) \
				- float(press_from[0])
			_check("a longer press travels further (%.1f u vs %.1f u)" % [press_dx, slot_dx],
				press_dx > slot_dx * 1.5)
			# One snapshot per press, so undo returns the slot to where the press started
			# rather than unwinding it one frame at a time.
			_send_key_mod(KEY_Z, true, false)
			await get_tree().process_frame
			_check("Ctrl+Z undoes the whole press",
				absf(float((_first_slot(doc).get("pos", [0, 0]) as Array)[0])
					- float(press_from[0])) < 0.01)

			var before_slot_angle := float(_first_slot(doc).get("angle", 0.0))
			_send_key(KEY_BRACKETRIGHT)
			await get_tree().process_frame
			_check("] turns the slot 5 degrees",
				absf(rad_to_deg(float(_first_slot(doc).get("angle", 0.0))
					- before_slot_angle) - 5.0) < 0.01)

			_send_key(KEY_BACKSPACE)
			await get_tree().process_frame
			_check("Backspace removes it", _first_slot(doc).is_empty())

	# Every class on the ladder must be placeable and must reserve a bigger box than the one
	# below it. Driven off the shipped list so a new class cannot be added without the editor
	# being able to lay it.
	var ladder: Array = AuthoredMapRef.SLOT_BOX_CLASSES
	_check("there is more than one slot class (%d)" % ladder.size(), ladder.size() >= 2)
	# Clear anything the block above left, so `_first_slot` describes the slot just placed.
	while not _first_slot(doc).is_empty():
		_editor.call("set_tool", "select")
		await _click(_screen_of(_slot_centre(doc), camera))
		_send_key(KEY_BACKSPACE)
		await get_tree().process_frame
	var last_box := 0.0
	var spot := Vector2(620, 470)
	for slot_class_value in ladder:
		var slot_class := str(slot_class_value)
		_editor.call("pick_slot_class", slot_class)
		await _click(spot)
		var laid := _first_slot(doc)
		_check("a %s slot can be placed" % slot_class,
			not laid.is_empty() and str(laid.get("size", "")) == slot_class)
		var reserved: float = (MapEditorSlotBoxes.size_for(slot_class) as Vector2).x
		_check("the %s box (%.0fu) is bigger than the class below it" % [slot_class, reserved],
			reserved > last_box)
		last_box = reserved
		if not laid.is_empty():
			_editor.call("set_tool", "select")
			await _click(_screen_of(_slot_centre(doc), camera))
			_send_key(KEY_BACKSPACE)
			await get_tree().process_frame
		spot.x += 8.0

	# K picks the tool, then cycles the class, so a row of mixed sizes needs no pointer trip.
	_editor.call("set_tool", "select")
	_send_key(KEY_K)
	await get_tree().process_frame
	_check("K selects the slot tool", str(_editor.call("current_tool")) == "slot")
	var first_class := str(_editor.call("current_slot_class"))
	_send_key(KEY_K)
	await get_tree().process_frame
	var next_class := str(_editor.call("current_slot_class"))
	_check("K again cycles the class (%s -> %s)" % [first_class, next_class],
		next_class != first_class and ladder.has(next_class))
	for _i in ladder.size():
		_send_key(KEY_K)
		await get_tree().process_frame
	_check("cycling wraps back around (%s)" % str(_editor.call("current_slot_class")),
		str(_editor.call("current_slot_class")) == next_class)

	# ── Industrial zones ────────────────────────────────────────────────────────
	# Three kinds, each drawable to ten corners. The corner cap is what separates a zone from
	# a farm field, so it is checked by actually clicking an eleventh rather than by reading
	# the constant back.
	var zone_kinds: Array = AuthoredMapRef.ZONE_KINDS
	_check("there are three zone kinds (%d)" % zone_kinds.size(), zone_kinds.size() == 3)
	var zone_doc: RefCounted = _editor.call("document")
	for kind_value in zone_kinds:
		var zone_kind := str(kind_value)
		_editor.call("set_area_kind", "zone:%s" % zone_kind)
		_check("picking %s selects the area tool" % zone_kind,
			str(_editor.call("current_tool")) == "area")
		_check("the corner cap is the zone cap, not the field cap (%d)"
			% int(_editor.call("shape_tool").call("max_corners")),
			int(_editor.call("shape_tool").call("max_corners"))
				== AuthoredMapRef.ZONE_MAX_VERTICES)
		var before_zones := (_zones_of(zone_doc)).size()
		# Eleven clicks for a ten-corner cap: the last must be refused, not accepted.
		for i in 11:
			var t := TAU * float(i) / 11.0
			await _click(Vector2(660, 420) + Vector2(cos(t), sin(t)) * 150.0)
		_send_key(KEY_ENTER)
		await get_tree().process_frame
		var zones := _zones_of(zone_doc)
		_check("a %s zone is committed (%d -> %d)" % [zone_kind, before_zones, zones.size()],
			zones.size() == before_zones + 1)
		if zones.size() > before_zones:
			var zone: Dictionary = zones[zones.size() - 1]
			_check("it carries its kind (%s)" % str(zone.get("kind", "")),
				str(zone.get("kind", "")) == zone_kind)
			_check("it stopped at the cap (%d corners)"
				% (zone.get("outline", []) as Array).size(),
				(zone.get("outline", []) as Array).size() == AuthoredMapRef.ZONE_MAX_VERTICES)
			_check("it declares the tiles it covers (%s)" % str(zone.get("tiles", [])),
				not (zone.get("tiles", []) as Array).is_empty())

	# The extraction-resources overlay is a toggle like the water mask.
	_check("extraction resources start hidden", not bool(_editor.call("deposit_marks_shown")))
	_editor.call("toggle_deposit_marks")
	await get_tree().process_frame
	_check("toggling shows them", bool(_editor.call("deposit_marks_shown")))
	var marked: Array = _editor.call("deposit_tiles")
	_check("it marks the tiles with a non-water deposit (%d)" % marked.size(),
		marked.size() > 0)
	var water_marked := 0
	for mark_value in marked:
		if str((mark_value as Dictionary).get("what", "")).contains("water"):
			water_marked += 1
	_check("and never labels water (%d water labels)" % water_marked, water_marked == 0)
	_editor.call("toggle_deposit_marks")

	# ── P3: the tile report and slot conversion ────────────────────────────────
	# The report exists to show the designer which of two independent limits binds. Both are
	# checked, because reporting only the one you thought of is how a lint becomes decoration.
	var report_tile := "tile_9_10"
	var report: Dictionary = _editor.call("tile_report", report_tile)
	_check("the tile report resolves a tile (%s, %s, cap %d)"
		% [str(report.get("tile", "")), str(report.get("terrain", "")), int(report.get("cap", 0))],
		str(report.get("tile", "")) == report_tile and int(report.get("cap", 0)) > 0)
	var fits: Array = report.get("fits", [])
	_check("it reports what the land allows (%d sizes)" % fits.size(), fits.size() >= 3)
	var descending := true
	for i in range(1, fits.size()):
		if int((fits[i] as Dictionary)["count"]) > int((fits[i - 1] as Dictionary)["count"]):
			descending = false
	_check("bigger buildings come out fewer per tile", descending)
	_check("a tile with no zones says so", (report.get("zones", []) as Array).is_empty())
	# Sea falls through the terrain cap table to the 200 default, which means nothing there.
	# The report must say so rather than quote a factory capacity for open water.
	var sea: Dictionary = _editor.call("tile_report", "tile_22_17")
	_check("a water tile is reported as offshore, not as 200 land (%s)"
		% str(sea.get("terrain", "")),
		bool(sea.get("offshore", false)) and (sea.get("fits", []) as Array).is_empty())

	# Draw a SMALL zone and the zone must become the binding limit, not the land cap.
	_editor.call("set_area_kind", "zone:industrial")
	var centre_screen := _screen_of(_editor.call("_world_at", Vector2(640, 400)), camera)
	for at in [centre_screen + Vector2(-40, -40), centre_screen + Vector2(40, -40),
			centre_screen + Vector2(40, 40), centre_screen + Vector2(-40, 40)]:
		await _click(at)
	_send_key(KEY_ENTER)
	await get_tree().process_frame
	# Report on the tile the zone actually LANDED on, from its own coverage list — not on
	# whatever the synthetic pointer is over, which is how this check ended up interrogating
	# open water.
	var drawn_zones := _zones_of(_editor.call("document"))
	var zoned_tile := ""
	if not drawn_zones.is_empty():
		var covered: Array = (drawn_zones[drawn_zones.size() - 1] as Dictionary).get("tiles", [])
		if not covered.is_empty():
			zoned_tile = str(covered[0])
	_check("the drawn zone recorded a tile (%s)" % zoned_tile, zoned_tile != "")
	var small: Dictionary = _editor.call("tile_report", zoned_tile)
	var zones: Array = small.get("zones", [])
	_check("a drawn zone appears in the report (%d)" % zones.size(), zones.size() >= 1)
	if not zones.is_empty():
		_check("it measures an area (%.0f u2)" % float((zones[0] as Dictionary)["area"]),
			float((zones[0] as Dictionary)["area"]) > 0.0)
		var land_count := 0
		for entry_value in (small.get("fits", []) as Array):
			if str((entry_value as Dictionary)["what"]) == "standard plant":
				land_count = int((entry_value as Dictionary)["count"])
		_check("a SMALL zone binds tighter than the land cap (%d boxes vs %d by land)"
			% [int((zones[0] as Dictionary)["max_boxes"]), land_count],
			int((zones[0] as Dictionary)["max_boxes"]) < land_count)

	# Slots -> zone. The slots must GO: leaving them would keep _claim_slot seating buildings
	# in boxes the zone was drawn to replace.
	_editor.call("pick_slot_class", "standard")
	for at in [Vector2(560, 300), Vector2(680, 320), Vector2(620, 420)]:
		await _click(at)
	var before_slots := (_editor.call("document_slot_boxes") as Array).size()
	_check("slots were laid to convert (%d)" % before_slots, before_slots >= 3)
	var slot_tile := str((_editor.call("document_slot_boxes") as Array)[0]["tile_id"])
	var before_zones := _zones_of(_editor.call("document")).size()
	var said: String = _editor.call("convert_slots_to_zone", slot_tile)
	await get_tree().process_frame
	_check("conversion reports what it did (%s)" % said, said.contains("industrial zone"))
	var after_zones := _zones_of(_editor.call("document"))
	_check("a zone was created (%d -> %d)" % [before_zones, after_zones.size()],
		after_zones.size() == before_zones + 1)
	var made: Dictionary = after_zones[after_zones.size() - 1]
	_check("it is within the corner cap (%d)" % (made.get("outline", []) as Array).size(),
		(made.get("outline", []) as Array).size() <= AuthoredMapRef.ZONE_MAX_VERTICES
			and (made.get("outline", []) as Array).size() >= 3)
	var left := 0
	for box_value in (_editor.call("document_slot_boxes") as Array):
		if str((box_value as Dictionary)["tile_id"]) == slot_tile:
			left += 1
	_check("the slots it replaced are gone (%d left on the tile)" % left, left == 0)

	# ── Zones are editable like any other shape ────────────────────────────────
	# Somewhere the harness has NOT already drawn: roads test before zones (a zone is the
	# ground everything else stands on), so a zone drawn over the earlier roads would be
	# correctly passed over and the check would be measuring precedence, not selection.
	_editor.call("focus_tile", "tile_18_14", 0.9)
	await get_tree().process_frame
	_editor.call("set_area_kind", "zone:extraction")
	var zone_at := Vector2(760, 500)
	for offset in [Vector2(-70, -60), Vector2(70, -60), Vector2(70, 60), Vector2(-70, 60)]:
		await _click(zone_at + offset)
	_send_key(KEY_ENTER)
	await get_tree().process_frame
	var all_zones := _zones_of(_editor.call("document"))
	_check("a zone to edit exists (%d)" % all_zones.size(), not all_zones.is_empty())
	if not all_zones.is_empty():
		var edit_zone: Dictionary = all_zones[all_zones.size() - 1]
		var zone_id := str(edit_zone.get("id", ""))
		# Is the click's WORLD point actually inside the polygon that was drawn? If the
		# geometry is wrong the selection failure means nothing.
		var zone_poly := PackedVector2Array()
		for entry in (edit_zone.get("outline", []) as Array):
			var values: Array = entry as Array
			if values != null and values.size() >= 2:
				zone_poly.append(Vector2(float(values[0]), float(values[1])))
		var click_world: Vector2 = _editor.call("_world_at", zone_at)
		_check("the click lands inside the drawn polygon (%s in %d corners)"
			% [str(click_world.round()), zone_poly.size()],
			zone_poly.size() >= 3 and Geometry2D.is_point_in_polygon(click_world, zone_poly))
		_editor.call("set_tool", "select")
		await _click(zone_at)
		var got: Dictionary = _editor.call("selected_ids")
		_check("clicking inside a zone selects it (wanted %s, got %s)"
			% [zone_id, "nothing" if got.is_empty() else ", ".join(PackedStringArray(got.keys()))],
			got.has(zone_id))
		var zone_handles: PackedVector2Array = _editor.call("editable_corners")
		_check("it offers its corners for dragging (%d)" % zone_handles.size(),
			zone_handles.size() == 4)

		if zone_handles.size() == 4:
			var zone_corner := zone_handles[0]
			await _drag(_screen_of(zone_corner, camera),
				_screen_of(zone_corner + Vector2(-45.0, -38.0), camera))
			var zone_moved: PackedVector2Array = _editor.call("editable_corners")
			_check("dragging a corner reshapes the zone (%.0f u)"
				% zone_corner.distance_to(zone_moved[0]),
				zone_moved.size() == 4 and zone_corner.distance_to(zone_moved[0]) > 20.0)
			var zone_others := 0
			for i in range(1, 4):
				if zone_handles[i].distance_to(zone_moved[i]) > 0.01:
					zone_others += 1
			_check("the other corners stayed put (%d moved)" % zone_others, zone_others == 0)

		# Drag the body to move the whole zone.
		var zone_from := Vector2.ZERO
		for entry in (_editor.call("editable_corners") as PackedVector2Array):
			zone_from += entry
		zone_from /= 4.0
		await _drag(_screen_of(zone_from, camera),
			_screen_of(zone_from + Vector2(60.0, 40.0), camera))
		var zone_to := Vector2.ZERO
		for entry in (_editor.call("editable_corners") as PackedVector2Array):
			zone_to += entry
		zone_to /= 4.0
		_check("dragging the body moves the whole zone (%.0f u)"
			% zone_from.distance_to(zone_to),
			zone_from.distance_to(zone_to) > 30.0)

		# A marquee must NOT sweep a zone up: `_meets_rect` counts an outline as met when
		# the rect's centre is inside it, so every bulk delete in a town would take the zone.
		var zone_swept: Array = _editor.call("marquee_kinds_for_test", zone_to)
		_check("a marquee inside a zone does not select the zone (%s)"
			% ("none" if zone_swept.is_empty() else ", ".join(PackedStringArray(zone_swept))),
			not zone_swept.has("zones"))

	# ── Placing an area leaves the tool armed for another of the same kind ─────
	for kind in ["parks", "plazas", "farms", "forests",
			"zone:industrial", "zone:extraction"]:
		_editor.call("set_area_kind", kind)
		var here := Vector2(430, 560)
		for offset in [Vector2(-50, -45), Vector2(50, -45), Vector2(50, 45), Vector2(-50, 45)]:
			await _click(here + offset)
		_send_key(KEY_ENTER)
		await get_tree().process_frame
		_check("after placing a %s the tool is still the area tool (%s)"
			% [kind, str(_editor.call("current_tool"))],
			str(_editor.call("current_tool")) == "area")
		_check("and still armed on %s (%s)" % [kind, str(_editor.call("current_area_kind"))],
			str(_editor.call("current_area_kind")) == kind)
		# And it must be READY — a leftover corner would make the next click continue the
		# last shape instead of starting a new one.
		_check("with no corners carried over from the last %s (%d)"
			% [kind, (_editor.call("shape_tool").call("polygon_points") as Array).size()],
			(_editor.call("shape_tool").call("polygon_points") as Array).is_empty())

	# ── Layering: sibling order IS the layering in this world ──────────────────
	# Asserted structurally rather than by screenshot, because the visual case only appears on
	# a tile where the PROCEDURAL fabric still draws — and an authored tile suppresses it, so
	# the very tiles you author on cannot show the bug. The order below is the guarantee.
	var world := _world_of()
	_check("the world was found for the layer check", world != null)
	if world != null:
		var order: Dictionary = {}
		for want in ["MapEditorFabricGround", "UrbanFabricVisuals", "AuthoredFabricVisuals",
				"MapEditorFabric", "BuildingVisuals", "RoadNetworkVisuals"]:
			var node := world.get_node_or_null(want)
			order[want] = node.get_index() if node != null else -1
		for want in order.keys():
			_check("%s is mounted (%d)" % [want, int(order[want])], int(order[want]) >= 0)
		# Ground BELOW the procedural fabric: parks and plazas must sit under the decorative
		# buildings the generator draws, which was the reported bug.
		_check("edited GROUND draws below the procedural fabric (%d < %d)"
			% [int(order["MapEditorFabricGround"]), int(order["UrbanFabricVisuals"])],
			int(order["MapEditorFabricGround"]) < int(order["UrbanFabricVisuals"]))
		# Standing fabric with the shipped authored node, and both below the buildings.
		_check("edited STANDING fabric sits with the authored node (%d > %d)"
			% [int(order["MapEditorFabric"]), int(order["AuthoredFabricVisuals"])],
			int(order["MapEditorFabric"]) > int(order["AuthoredFabricVisuals"]))
		_check("all edited fabric draws below the buildings (%d < %d)"
			% [int(order["MapEditorFabric"]), int(order["BuildingVisuals"])],
			int(order["MapEditorFabric"]) < int(order["BuildingVisuals"]))

	# The in-progress polygon must show its corners. It went missing when the fabric moved out
	# of the overlay, and a polygon tool with no visible corners is one you use blind.
	_editor.call("set_area_kind", "parks")
	for at in [Vector2(500, 300), Vector2(600, 290), Vector2(590, 380)]:
		await _click(at)
	_check("the half-drawn polygon keeps its corners (%d)"
		% (_editor.call("shape_tool").call("polygon_points") as Array).size(),
		(_editor.call("shape_tool").call("polygon_points") as Array).size() == 3)
	_check("and the tool is still mid-draw, so the overlay has something to paint",
		bool(_editor.call("shape_tool").call("is_drawing")))
	_send_key(KEY_ENTER)
	await get_tree().process_frame

	if _failures.is_empty():
		print("[INPUT] ALL CHECKS PASSED")
		get_tree().quit(0)
	else:
		for failure in _failures:
			print("[INPUT] FAILED: %s" % failure)
		get_tree().quit(1)


## Where the first slot sits in world units, for clicking it back.
func _slot_centre(document: RefCounted) -> Vector2:
	var boxes: Array = _editor.call("document_slot_boxes")
	return (boxes[0] as Dictionary)["centre"] if not boxes.is_empty() else Vector2.ZERO


## The first slot pin in the document, whichever tile it landed on. The checks place one at
## a time, so "first" and "the one just placed" are the same record.
## Every zone in the document, in order.
func _zones_of(document: RefCounted) -> Array:
	var out: Array = []
	for settlement_value in (document.call("data").get("settlements", {}) as Dictionary).values():
		for zone in ((settlement_value as Dictionary).get("zones", []) as Array):
			out.append(zone)
	return out


func _first_slot(document: RefCounted) -> Dictionary:
	var settlements: Dictionary = document.call("data").get("settlements", {})
	for key in settlements.keys():
		var slots: Dictionary = (settlements[key] as Dictionary).get("slots", {})
		for tile_id in slots.keys():
			var pins: Array = (slots[tile_id] as Dictionary).get("pins", []) as Array
			if not pins.is_empty():
				return pins[0] as Dictionary
	return {}


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


func _send_key_mod(code: Key, ctrl: bool, shift: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	event.ctrl_pressed = ctrl
	event.shift_pressed = shift
	Input.parse_input_event(event)


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
