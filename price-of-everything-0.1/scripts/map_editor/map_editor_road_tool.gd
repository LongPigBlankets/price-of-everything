extends RefCounted
## The road pen — P1 of `docs/map-editor-plan.md`.
##
## EDITOR-ONLY (see the header of `map_editor.gd`).
##
## DRAWING. Click to drop a corner; click-and-drag to drop a curve point, the drag setting
## its handles (symmetric, so a curve through the point stays smooth). Enter or double-click
## ends the stroke, Escape abandons it, Backspace removes the last point. Straights and
## curves are therefore the same gesture at different lengths, which is what makes a mixed
## stroke — a straight run into a bend into another straight — one object rather than three.
##
## SNAPPING. A new point within `SNAP_DISTANCE` of an existing stroke's endpoint takes that
## endpoint exactly, so junctions meet cleanly instead of leaving a hairline gap that reads
## as a break at full zoom. Hold Alt to place a raw point.
##
## UNLOCKABLE. Every finished stroke records the tiles it crosses. It is marked unlockable
## automatically when ANY of those tiles starts without the road flag: the alternative —
## defaulting to always-visible — draws roads across land the player has not connected yet,
## which is precisely the state the connection rule exists to prevent. The designer can
## override either way.

const AuthoredMap := preload("res://scripts/authored_map.gd")
const AuthoredRoadGeometry := preload("res://scripts/authored_road_geometry.gd")

## World units. Deliberately larger than the 2 u the owner specified for SHAPE snapping:
## at full zoom 2 u is about two pixels, which is a hard target for a junction. The shape
## tools (P2) use the ruled 2 u; a road endpoint is a coarser thing to hit.
const SNAP_DISTANCE := 14.0

## A drag shorter than this is a click, not a curve: without it every click would leave
## tiny handles and turn straight runs into faint wobbles.
const DRAG_THRESHOLD := 4.0

var _points: Array = []          ## points of the stroke being drawn, in the authored format
var _drag_origin := Vector2.ZERO
var _dragging := false
var _stroke_class := "mid"


func stroke_class() -> String:
	return _stroke_class


func set_stroke_class(value: String) -> void:
	if AuthoredMap.ROAD_WIDTHS.has(value):
		_stroke_class = value


func is_drawing() -> bool:
	return not _points.is_empty()


## The in-progress points, for the overlay's preview.
func preview_points() -> Array:
	return _points


## Begin a point at `world`. Returns the position actually used (snapped or raw).
func press(world: Vector2, snap_targets: Array, allow_snap: bool) -> Vector2:
	var position := _snapped(world, snap_targets) if allow_snap else world
	_drag_origin = position
	_dragging = true
	_points.append([position.x, position.y])
	return position


## Finish the point begun by [method press]. A drag past the threshold converts it into a
## curve point whose handles mirror the drag — the standard pen-tool gesture.
func release(world: Vector2) -> void:
	if not _dragging or _points.is_empty():
		_dragging = false
		return
	_dragging = false
	var pull := world - _drag_origin
	if pull.length() < DRAG_THRESHOLD:
		return
	_points[_points.size() - 1] = [
		_drag_origin.x, _drag_origin.y,
		-pull.x, -pull.y,
		pull.x, pull.y,
	]


func undo_point() -> void:
	if not _points.is_empty():
		_points.remove_at(_points.size() - 1)


func abandon() -> void:
	_points = []
	_dragging = false


## Close the stroke and return it as a document record, or an empty dictionary when there is
## not enough to keep. `next_id` supplies the stable id — ids are never renumbered, so an
## edit to one stroke cannot change how any other is seeded or drawn.
func finish(settlement_key: String, next_id: int, terrain: Node) -> Dictionary:
	if _points.size() < 2:
		abandon()
		return {}
	var stroke := {
		"id": "r:%s:%d" % [settlement_key, next_id],
		"class": _stroke_class,
		"points": _points.duplicate(true),
	}
	var centreline := AuthoredRoadGeometry.sample(stroke)
	if AuthoredRoadGeometry.length_of(centreline) < AuthoredRoadGeometry.MIN_STROKE_LENGTH:
		abandon()
		return {}
	var tiles := AuthoredRoadGeometry.touched_tiles(centreline, terrain)
	stroke["tiles"] = _to_array(tiles)
	# Unlockable by default when any touched tile starts roadless — see the header.
	stroke["unlockable"] = _any_tile_roadless(tiles, terrain)
	var crossings := AuthoredRoadGeometry.river_crossings(centreline, NavGrid.instance())
	if not crossings.is_empty():
		var bridges: Array = []
		for crossing in crossings:
			var centre: Vector2 = crossing[0]
			var tangent: Vector2 = crossing[1]
			bridges.append([centre.x, centre.y, tangent.x, tangent.y])
		stroke["bridges"] = bridges
	abandon()
	return stroke


## Endpoints of every existing stroke in the document — the snap targets.
static func snap_targets(document: Dictionary) -> Array:
	var out: Array = []
	var settlements_value: Variant = document.get("settlements", {})
	if typeof(settlements_value) != TYPE_DICTIONARY:
		return out
	for key in (settlements_value as Dictionary).keys():
		var settlement_value: Variant = (settlements_value as Dictionary)[key]
		if typeof(settlement_value) != TYPE_DICTIONARY:
			continue
		for stroke_value in ((settlement_value as Dictionary).get("roads", []) as Array):
			if typeof(stroke_value) != TYPE_DICTIONARY:
				continue
			var points: Array = (stroke_value as Dictionary).get("points", []) as Array
			for index in [0, points.size() - 1]:
				if index < 0 or index >= points.size():
					continue
				var entry: Array = points[index] as Array
				if entry != null and entry.size() >= 2:
					out.append(Vector2(float(entry[0]), float(entry[1])))
	return out


func _snapped(world: Vector2, targets: Array) -> Vector2:
	var best := world
	var best_distance := SNAP_DISTANCE
	for target_value in targets:
		var target: Vector2 = target_value
		var distance := world.distance_to(target)
		if distance < best_distance:
			best_distance = distance
			best = target
	return best


func _any_tile_roadless(tiles: PackedStringArray, terrain: Node) -> bool:
	if terrain == null:
		return false
	var all_tiles: Dictionary = terrain.get("tiles")
	for tile_id in tiles:
		var coord: Vector2i = terrain.call("id_to_coord", tile_id)
		if not all_tiles.has(coord):
			continue
		var tile: Dictionary = all_tiles[coord]
		if not (tile.get("infrastructure_present", []) as Array).has("roads"):
			return true
	return false


func _to_array(values: PackedStringArray) -> Array:
	var out: Array = []
	for value in values:
		out.append(value)
	return out
