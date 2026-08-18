extends RefCounted
## Finding and reshaping strokes that are already in the document — the half of road
## authoring that is not "draw a new one".
##
## EDITOR-ONLY (see the header of `map_editor.gd`).
##
## Kept apart from the pen because the questions are different: the pen only ever appends to
## a stroke it owns, while these operate on any stroke in any settlement and have to answer
## "what did the designer just click on". Both mutate through the document's snapshot undo,
## so neither needs to describe its own inverse.

const AuthoredRoadGeometry := preload("res://scripts/authored_road_geometry.gd")
const AuthoredRoadStyle := preload("res://scripts/authored_road_style.gd")

## How close a click must land to a stroke's centreline to count as hitting it, as a
## multiple of that stroke's own bed half-width. Wider than the carriageway because the
## target is a line on screen, not a shape: a major road is easy to hit, a minor one at low
## zoom would be nearly impossible at 1.0.
const HIT_TOLERANCE := 1.8
## Floor for the above in world units, so a minor road stays clickable when zoomed out.
const HIT_MIN := 9.0

## The class ladder, narrowest first. Matches the ordering of `AuthoredMap.ROAD_WIDTHS`;
## declared explicitly rather than derived from the widths so that re-tuning a width during
## the curation pass cannot silently reorder what "upgrade" means.
const CLASS_LADDER := ["minor", "mid", "major"]


## Step a stroke's class one rung. Upgrading stops at `major` and downgrading at `minor`
## rather than wrapping: a wrap turns a mis-click on the top rung into the biggest possible
## change, from the widest road to the narrowest. Returns the new class, or "" if it could
## not move.
static func step_class(stroke: Dictionary, up: bool) -> String:
	var current := CLASS_LADDER.find(str(stroke.get("class", "mid")))
	if current < 0:
		current = 1
	var next := current + (1 if up else -1)
	if next < 0 or next >= CLASS_LADDER.size():
		return ""
	stroke["class"] = CLASS_LADDER[next]
	return str(stroke["class"])


## The stroke under `world`, as `{settlement, stroke, index}` — or an empty dictionary.
## Searches every settlement; ties go to the NARROWEST stroke, because a minor road drawn
## across a major is the one the designer means when they click on the crossing.
static func stroke_at(document: Dictionary, world: Vector2) -> Dictionary:
	var best := {}
	var best_width := INF
	var settlements_value: Variant = document.get("settlements", {})
	if typeof(settlements_value) != TYPE_DICTIONARY:
		return best
	var settlements: Dictionary = settlements_value
	var keys := settlements.keys()
	keys.sort()
	for key in keys:
		var settlement_value: Variant = settlements[key]
		if typeof(settlement_value) != TYPE_DICTIONARY:
			continue
		var roads: Array = (settlement_value as Dictionary).get("roads", []) as Array
		for index in roads.size():
			var stroke_value: Variant = roads[index]
			if typeof(stroke_value) != TYPE_DICTIONARY:
				continue
			var stroke: Dictionary = stroke_value
			var stroke_class := str(stroke.get("class", "mid"))
			var width := AuthoredRoadStyle.bed_width(stroke_class)
			var tolerance := maxf(width * 0.5 * HIT_TOLERANCE, HIT_MIN)
			var points := AuthoredRoadGeometry.sample(stroke)
			if _distance_to_polyline(points, world) > tolerance:
				continue
			if width < best_width:
				best_width = width
				best = {"settlement": str(key), "stroke": stroke, "index": index}
	return best


## Where along a stroke's POINT LIST a new anchor belongs for a click at `world`, and the
## position it should take. Returns `{index, position}` — `index` is the insertion slot, so
## the new point lands between `points[index - 1]` and the old `points[index]`.
##
## Measured against the authored control points rather than the sampled curve: a curve is
## only a rendering of them, and inserting "after sample 43" says nothing about which
## authored segment was clicked.
static func anchor_slot(stroke: Dictionary, world: Vector2) -> Dictionary:
	var points: Array = stroke.get("points", []) as Array
	if points.size() < 2:
		return {}
	var best_index := -1
	var best_distance := INF
	var best_position := world
	for i in range(1, points.size()):
		var a := _point_of(points[i - 1])
		var b := _point_of(points[i])
		var closest := Geometry2D.get_closest_point_to_segment(world, a, b)
		var distance := world.distance_to(closest)
		if distance < best_distance:
			best_distance = distance
			best_index = i
			best_position = closest
	if best_index < 0:
		return {}
	return {"index": best_index, "position": best_position}


## Insert a plain corner point. It starts with no handles: the segments stay exactly as they
## were until the point is dragged, so inserting an anchor never changes the road's shape by
## itself. The curve appears from the drag, which is what makes the gesture predictable.
static func insert_anchor(stroke: Dictionary, slot: Dictionary) -> int:
	if slot.is_empty():
		return -1
	var points: Array = stroke.get("points", []) as Array
	var position: Vector2 = slot["position"]
	points.insert(int(slot["index"]), [position.x, position.y])
	stroke["points"] = points
	return int(slot["index"])


## Move an existing point and give it symmetric handles derived from the drag, curving BOTH
## segments that meet there. The handle length is a fraction of the distance to the
## neighbouring points, so a bend on a short segment does not overshoot into its neighbours.
static func shape_anchor(stroke: Dictionary, index: int, world: Vector2) -> void:
	var points: Array = stroke.get("points", []) as Array
	if index < 0 or index >= points.size():
		return
	var previous := _point_of(points[maxi(index - 1, 0)])
	var next := _point_of(points[mini(index + 1, points.size() - 1)])
	# The tangent through the point is the direction from its neighbours: pulling the point
	# sideways then bows both segments smoothly through it, rather than kinking one.
	var tangent := (next - previous)
	if tangent.length() < 0.001:
		tangent = Vector2.RIGHT
	tangent = tangent.normalized()
	var reach := minf(previous.distance_to(world), next.distance_to(world)) * 0.4
	var handle := tangent * reach
	var entry: Array = [world.x, world.y]
	if index > 0 and index < points.size() - 1 and reach > 0.5:
		entry = [world.x, world.y, -handle.x, -handle.y, handle.x, handle.y]
	points[index] = entry
	stroke["points"] = points


## The index of the authored point nearest `world`, or -1 when none is within `tolerance`.
static func point_at(stroke: Dictionary, world: Vector2, tolerance: float) -> int:
	var points: Array = stroke.get("points", []) as Array
	var best := -1
	var best_distance := tolerance
	for i in points.size():
		var distance := _point_of(points[i]).distance_to(world)
		if distance <= best_distance:
			best_distance = distance
			best = i
	return best


static func _point_of(entry: Variant) -> Vector2:
	var values: Array = entry as Array
	if values == null or values.size() < 2:
		return Vector2.ZERO
	return Vector2(float(values[0]), float(values[1]))


static func _distance_to_polyline(points: PackedVector2Array, world: Vector2) -> float:
	if points.size() < 2:
		return INF
	var best := INF
	for i in range(1, points.size()):
		var closest := Geometry2D.get_closest_point_to_segment(world, points[i - 1], points[i])
		best = minf(best, world.distance_to(closest))
	return best
