extends Node2D
## World-space drawing for the Infrastructure mapmode. Every tile holding the
## selected infrastructure is a filled circle in that type's colour (80 world
## px across — full size at the most zoomed-in level, shrinking naturally as
## the camera zooms out), joined to adjacent same-infrastructure tiles by
## straight centre-to-centre lines (circles draw on top, so lines read as
## rim-to-rim). Links touching under-construction infrastructure are dashed;
## a stranded under-construction tile (no adjacent tile with the infra) gets
## a transparent cross cut out of its circle plus dashed stubs reaching
## halfway to each hex edge midpoint.

const CIRCLE_DIAMETER := 80.0
const LINE_WIDTH := 10.0
const DASH_LEN := 24.0
# Infrastructure level styling: level 2 adds a thin "rail" running parallel to
# the main line (RAIL_GAP clear of its edge); level 3 adds one on each side.
const RAIL_WIDTH := 3.0
const RAIL_GAP := 2.0
const CROSS_HALF_WIDTH := 9.0    # half-thickness of the cut-out cross arms
const STUB_EDGE_FRACTION := 0.5  # stubs stop halfway to the edge midpoint
const ARC_SEGMENTS := 24

var color := Color.WHITE
var circles: Array = []        # Vector2 tile centres — built infrastructure
var uc_circles: Array = []     # Vector2 — under construction with a neighbour
var stranded: Array = []       # {pos: Vector2, edge_mids: Array} — isolated UC
var solid_links: Array = []    # {a, b, level} — built <-> built
var dashed_links: Array = []   # {a, b, level} with an under-construction endpoint

func _draw() -> void:
	for link in solid_links:
		_draw_link(link.a, link.b, int(link.level), false)
	for link in dashed_links:
		_draw_link(link.a, link.b, int(link.level), true)
	var radius := CIRCLE_DIAMETER * 0.5
	for entry in stranded:
		_draw_stranded(entry.pos, entry.edge_mids, radius)
	for pos in circles:
		draw_circle(pos, radius, color)
	for pos in uc_circles:
		draw_circle(pos, radius, color)

func _draw_link(a: Vector2, b: Vector2, level: int, dashed: bool) -> void:
	_draw_link_line(a, b, LINE_WIDTH, dashed)
	if level < 2:
		return
	var offset: Vector2 = (b - a).normalized().orthogonal() \
			* (LINE_WIDTH * 0.5 + RAIL_GAP + RAIL_WIDTH * 0.5)
	_draw_link_line(a + offset, b + offset, RAIL_WIDTH, dashed)
	if level >= 3:
		_draw_link_line(a - offset, b - offset, RAIL_WIDTH, dashed)

func _draw_link_line(from: Vector2, to: Vector2, width: float, dashed: bool) -> void:
	if dashed:
		draw_dashed_line(from, to, color, width, DASH_LEN)
	else:
		draw_line(from, to, color, width)

func _draw_stranded(pos: Vector2, edge_mids: Array, radius: float) -> void:
	# Dashed stubs start at the circle rim (the cross hole is see-through, so
	# they can't pass under the disc) and stop halfway to each edge midpoint.
	for mid in edge_mids:
		var to: Vector2 = pos + (mid - pos) * STUB_EDGE_FRACTION
		var from: Vector2 = pos + (mid - pos).normalized() * radius
		draw_dashed_line(from, to, color, LINE_WIDTH, DASH_LEN)
	# Circle with a transparent cross cut out of the middle: four quadrant
	# pieces, each the part of the disc beyond the cross arms.
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			draw_colored_polygon(_quadrant_points(pos, radius, sx, sy), color)

func _quadrant_points(center: Vector2, radius: float, sx: float, sy: float) -> PackedVector2Array:
	var w := CROSS_HALF_WIDTH
	var reach := sqrt(radius * radius - w * w)
	var points := PackedVector2Array()
	points.append(center + Vector2(w * sx, w * sy))
	var angle_from := atan2(reach, w)  # on the vertical arm's edge
	var angle_to := atan2(w, reach)    # on the horizontal arm's edge
	for i in ARC_SEGMENTS + 1:
		var angle := lerpf(angle_from, angle_to, float(i) / float(ARC_SEGMENTS))
		points.append(center + Vector2(cos(angle) * radius * sx, sin(angle) * radius * sy))
	return points
