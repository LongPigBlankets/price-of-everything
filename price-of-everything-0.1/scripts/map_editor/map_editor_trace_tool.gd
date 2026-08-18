extends RefCounted
## Two ways of laying down a road that are not the pen: FREEHAND tracing, and CONNECT THE
## DOTS.
##
## EDITOR-ONLY (see the header of `map_editor.gd`).
##
## FREEHAND — press, drag along the line you want, release. The traced path is sampled at a
## minimum spacing and then simplified, because a mouse produces hundreds of points a second
## and a road with 400 control points is unusable: it cannot be re-shaped, it bloats the
## document, and the wobble on top of hand tremor reads as noise rather than ink. Simplifying
## to a handful of corners is what makes the result an editable object rather than a
## recording of a gesture.
##
## CONNECT THE DOTS — click to drop dots, then click one and another to join them with a
## straight run. Dots persist between strokes, so a junction laid down once can anchor
## several roads. This is the tool for a planned grid, where the pen's freehand feel is
## exactly wrong.

const AuthoredRoadGeometry := preload("res://scripts/authored_road_geometry.gd")

## Minimum world-unit spacing between recorded trace samples. Anything closer is tremor.
const TRACE_MIN_SPACING := 6.0
## Douglas-Peucker tolerance for the traced path, in world units. Large enough to erase the
## shake in a hand-drawn line, small enough to keep a deliberate bend.
const TRACE_SIMPLIFY := 7.0
## Click radius for picking up an existing dot, in world units.
const DOT_PICK := 14.0

var _trace: PackedVector2Array = PackedVector2Array()
var _tracing := false
## Free-standing dots, in world units. Not part of any stroke until two are joined.
var _dots: PackedVector2Array = PackedVector2Array()
## Index of the dot awaiting its partner, or -1.
var _pending := -1


# ── Freehand ────────────────────────────────────────────────────────────────────

func begin_trace(world: Vector2) -> void:
	_tracing = true
	_trace = PackedVector2Array([world])


func extend_trace(world: Vector2) -> void:
	if not _tracing:
		return
	if _trace.is_empty() or _trace[_trace.size() - 1].distance_to(world) >= TRACE_MIN_SPACING:
		_trace.append(world)


func is_tracing() -> bool:
	return _tracing


func trace_points() -> PackedVector2Array:
	return _trace


## Close the trace and return its simplified points in the authored format, or an empty
## array when the gesture was too short to be a road.
func end_trace() -> Array:
	_tracing = false
	var raw := _trace
	_trace = PackedVector2Array()
	if raw.size() < 2:
		return []
	var simplified := _simplify(raw, TRACE_SIMPLIFY)
	if simplified.size() < 2:
		return []
	if AuthoredRoadGeometry.length_of(simplified) < AuthoredRoadGeometry.MIN_STROKE_LENGTH:
		return []
	var out: Array = []
	for point in simplified:
		out.append([point.x, point.y])
	return out


func cancel_trace() -> void:
	_tracing = false
	_trace = PackedVector2Array()


# ── Connect the dots ────────────────────────────────────────────────────────────

func dots() -> PackedVector2Array:
	return _dots


func pending_dot() -> int:
	return _pending


## A click in dot mode: on an existing dot it starts (or completes) a link; on empty ground
## it drops a new dot. Returns the two endpoints when a link was completed, else an empty
## array.
func click_dot(world: Vector2) -> Array:
	var hit := _dot_at(world)
	if hit < 0:
		_dots.append(world)
		# Dropping a dot clears a half-made link: the designer went to place geometry rather
		# than finish the join, and a link left half-armed would fire on an unrelated click
		# minutes later.
		_pending = -1
		return []
	if _pending < 0:
		_pending = hit
		return []
	if _pending == hit:
		_pending = -1   # clicking the armed dot again cancels
		return []
	var from := _dots[_pending]
	var to := _dots[hit]
	_pending = -1
	return [[from.x, from.y], [to.x, to.y]]


func clear_dots() -> void:
	_dots = PackedVector2Array()
	_pending = -1


## Remove the last dot placed. Undo covers committed strokes; dots are not in the document
## until they are joined, so they need their own step back.
func undo_dot() -> void:
	if _dots.is_empty():
		return
	_dots.remove_at(_dots.size() - 1)
	_pending = -1


func _dot_at(world: Vector2) -> int:
	var best := -1
	var best_distance := DOT_PICK
	for i in _dots.size():
		var distance := _dots[i].distance_to(world)
		if distance <= best_distance:
			best_distance = distance
			best = i
	return best


## Iterative Douglas-Peucker. Iterative rather than recursive because a traced path can be
## hundreds of points long and GDScript's recursion is not free; this mirrors the road
## renderer's own `_rdp`.
func _simplify(points: PackedVector2Array, tolerance: float) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var keep := {}
	keep[0] = true
	keep[points.size() - 1] = true
	var stack: Array = [[0, points.size() - 1]]
	while not stack.is_empty():
		var span: Array = stack.pop_back()
		var first: int = span[0]
		var last: int = span[1]
		var worst := -1
		var worst_distance := tolerance
		for i in range(first + 1, last):
			var closest := Geometry2D.get_closest_point_to_segment(points[i], points[first], points[last])
			var distance := points[i].distance_to(closest)
			if distance > worst_distance:
				worst_distance = distance
				worst = i
		if worst > 0:
			keep[worst] = true
			stack.append([first, worst])
			stack.append([worst, last])
	var indices := keep.keys()
	indices.sort()
	var out := PackedVector2Array()
	for index in indices:
		out.append(points[int(index)])
	return out
