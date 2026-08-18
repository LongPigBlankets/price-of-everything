extends RefCounted
## Seating a dragged building against a road.
##
## EDITOR-ONLY (see the header of `map_editor.gd`).
##
## A building beside a street should touch its kerb and face it. Doing that by eye at every
## zoom is fiddly and never quite consistent, so a drag that ends near a road snaps: the
## shape turns to the road's tangent and sits one kerb-gap from its centreline. Hold Ctrl
## (Cmd on macOS) while dragging to place it exactly where the pointer is instead.
##
## THE SAME CONTRACT THE GAME USES. Gameplay buildings are placed with their footprint's
## first edge along the road tangent and offset by the carriageway half-width plus a pad;
## an authored building that sat by a different rule would look wrong next to a built one.

const AuthoredRoadGeometry := preload("res://scripts/authored_road_geometry.gd")
const AuthoredRoadStyle := preload("res://scripts/authored_road_style.gd")
const MapEditorSelection := preload("res://scripts/map_editor/map_editor_selection.gd")

## How near the seated position a drag must finish for the snap to take, in world units.
## Generous on purpose: the owner's 2 u figure was for fine shape alignment, and 2 u is about
## two pixels even at full zoom — a target you cannot hit while dragging.
const SNAP_BAND := 26.0

## Gap between the carriageway edge and the building, world units. Matches the kerb clearance
## the placement pipeline uses for art buildings.
const KERB_PAD := 5.5


## Where a record should sit if it snaps to a road, as
## `{position, angle, road}` — or {} when nothing is near enough.
##
## `angle` is the turn to apply about the record's centre, not an absolute heading, because
## an outline has no stored rotation to overwrite.
static func seat_for(document: Dictionary, item: Dictionary) -> Dictionary:
	var centre := MapEditorSelection.centre_of(item)
	var best := {}
	var best_gap := INF
	for stroke in _strokes(document):
		var points := AuthoredRoadGeometry.sample(stroke)
		if points.size() < 2:
			continue
		for i in range(1, points.size()):
			var a := points[i - 1]
			var b := points[i]
			var closest := Geometry2D.get_closest_point_to_segment(centre, a, b)
			var gap := centre.distance_to(closest)
			if gap >= best_gap:
				continue
			var tangent := (b - a)
			if tangent.length() < 0.001:
				continue
			best_gap = gap
			best = {"closest": closest, "tangent": tangent.normalized(),
				"class": str(stroke.get("class", "mid"))}
	if best.is_empty():
		return {}

	var tangent: Vector2 = best["tangent"]
	var normal := Vector2(-tangent.y, tangent.x)
	var closest: Vector2 = best["closest"]
	# Keep the building on the side of the road it was dragged to.
	if (centre - closest).dot(normal) < 0.0:
		normal = -normal
	# Turn the shape so its long axis runs along the road, then measure how deep it is
	# ACROSS the road to work out where its edge falls.
	var angle := _turn_to(item, tangent)
	var depth := MapEditorSelection.half_extent_along(item, normal)
	var offset := AuthoredRoadStyle.bed_width(str(best["class"])) * 0.5 + KERB_PAD + depth
	var seated := closest + normal * offset
	if centre.distance_to(seated) > SNAP_BAND:
		return {}
	return {"position": seated, "angle": angle, "road": best}


## The turn that brings the record's long axis onto `tangent`. A mass already carries a
## rotation; an outline's axis is measured from its own extent, so an L or a terrace lies
## along the street rather than across it.
static func _turn_to(item: Dictionary, tangent: Vector2) -> float:
	var target := tangent.angle()
	if item.has("form"):
		return wrapf(target - float(item.get("rot", 0.0)), -PI, PI)
	var axis := _long_axis(item)
	if axis == Vector2.ZERO:
		return 0.0
	# Either direction along the street is equally correct; take the shorter turn.
	var turn := wrapf(target - axis.angle(), -PI, PI)
	if turn > PI * 0.5:
		turn -= PI
	elif turn < -PI * 0.5:
		turn += PI
	return turn


static func _long_axis(item: Dictionary) -> Vector2:
	var outline := PackedVector2Array()
	for entry in (item.get("outline", []) as Array):
		var values: Array = entry as Array
		if values != null and values.size() >= 2:
			outline.append(Vector2(float(values[0]), float(values[1])))
	if outline.size() < 2:
		return Vector2.ZERO
	# The longest chord between vertices is a good enough principal axis for shapes of this
	# size, and it is stable under the corner dragging these outlines allow.
	var best := Vector2.ZERO
	var best_length := 0.0
	for i in outline.size():
		for j in range(i + 1, outline.size()):
			var span := outline[j] - outline[i]
			if span.length() > best_length:
				best_length = span.length()
				best = span
	return best.normalized() if best_length > 0.0 else Vector2.ZERO


static func _strokes(document: Dictionary) -> Array:
	var out: Array = []
	var settlements_value: Variant = document.get("settlements", {})
	if typeof(settlements_value) != TYPE_DICTIONARY:
		return out
	for key in (settlements_value as Dictionary).keys():
		var settlement_value: Variant = (settlements_value as Dictionary)[key]
		if typeof(settlement_value) != TYPE_DICTIONARY:
			continue
		for stroke_value in ((settlement_value as Dictionary).get("roads", []) as Array):
			if typeof(stroke_value) == TYPE_DICTIONARY:
				out.append(stroke_value)
	return out
