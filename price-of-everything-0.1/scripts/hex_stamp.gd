extends RefCounted
## The research panel's rounded-corner hexagonal metal stamp, as shared geometry.
##
## Extracted from research_panel.gd so the end screen's victory crests are the SAME
## object as the tier stamps rather than a second drawing of them. The panel's own
## helpers are now one-line delegates to these; two implementations of one piece of
## chrome drift apart the first time either is touched.
##
## The shape is a flat-topped hexagon inscribed in a rect (points at left and right
## middle), with every corner filleted by a short quadratic sweep. The metal is three
## passes: a dropped shadow, a diagonal gradient body, and per-edge lighting that runs
## light on the edges facing the top-left and shadow on the ones facing away.


## Hexagon inscribed in `rect`: flat top and bottom runs, a point at each side's middle.
static func hex_points(rect: Rect2) -> PackedVector2Array:
	var left := rect.position.x
	var right := rect.end.x
	var top := rect.position.y
	var bottom := rect.end.y
	var middle_y := rect.get_center().y
	var bevel := rect.size.x * 0.22
	return PackedVector2Array([
		Vector2(left + bevel, top),
		Vector2(right - bevel, top),
		Vector2(right, middle_y),
		Vector2(right - bevel, bottom),
		Vector2(left + bevel, bottom),
		Vector2(left, middle_y),
	])


static func rounded_hex_points(rect: Rect2, corner_radius: float) -> PackedVector2Array:
	return rounded_polygon_points(hex_points(rect), corner_radius)


## Every corner replaced by a 5-step quadratic fillet, capped at 42% of the shorter
## adjacent run so a small stamp never folds its corners through each other.
static func rounded_polygon_points(vertices: PackedVector2Array, corner_radius: float) -> PackedVector2Array:
	if vertices.size() < 3:
		return vertices
	var points := PackedVector2Array()
	for index in vertices.size():
		var current := vertices[index]
		var previous := vertices[(index - 1 + vertices.size()) % vertices.size()]
		var next := vertices[(index + 1) % vertices.size()]
		var radius := minf(corner_radius, minf(current.distance_to(previous), current.distance_to(next)) * 0.42)
		var from_point := current + (previous - current).normalized() * radius
		var to_point := current + (next - current).normalized() * radius
		for step in 5:
			var t := float(step) / 4.0
			var a := from_point.lerp(current, t)
			var b := current.lerp(to_point, t)
			points.append(a.lerp(b, t))
	return points


## Per-edge lighting: light where the edge faces the top-left, shadow where it faces away.
static func draw_rounded_edge_lighting(ci: CanvasItem, points: PackedVector2Array, rect: Rect2,
		width: float, light_color: Color, shadow_color: Color) -> void:
	if points.size() < 2:
		return
	var center_sum := rect.get_center().x + rect.get_center().y
	for index in points.size():
		var start := points[index]
		var end := points[(index + 1) % points.size()]
		var mid := (start + end) * 0.5
		var color := light_color if mid.x + mid.y <= center_sum else shadow_color
		ci.draw_line(start, end, color, width, true)


static func solid_colors(count: int, color: Color) -> PackedColorArray:
	var colors := PackedColorArray()
	for index in count:
		colors.append(color)
	return colors


## Diagonal light→dark ramp across the polygon's own bounds (light from the top-left).
static func hex_gradient_colors(points: PackedVector2Array, light_color: Color, dark_color: Color) -> PackedColorArray:
	var bounds := Rect2()
	var has_bounds := false
	for point in points:
		if has_bounds:
			bounds = bounds.expand(point)
		else:
			bounds = Rect2(point, Vector2.ZERO)
			has_bounds = true
	var colors := PackedColorArray()
	var denominator := maxf(bounds.size.x + bounds.size.y, 1.0)
	for point in points:
		var ratio := clampf(((point.x - bounds.position.x) + (point.y - bounds.position.y)) / denominator, 0.0, 1.0)
		colors.append(light_color.lerp(dark_color, ratio))
	return colors


## The whole stamp in one call: shadow, outline shell, gradient face, edge lighting on
## both rims. Returns the inner rect the caller may put an icon or a glyph inside.
static func draw_stamp(ci: CanvasItem, rect: Rect2, fill: Color, outline_light: Color,
		outline_dark: Color, outline: float, corner_radius: float) -> Rect2:
	var outer := rounded_hex_points(rect, corner_radius)
	var inner_rect := rect.grow(-outline)
	var inner := rounded_hex_points(inner_rect, maxf(2.0, corner_radius - outline * 0.35))
	var shadow_points := PackedVector2Array()
	for point in outer:
		shadow_points.append(point + Vector2(0.0, 2.0))
	ci.draw_polygon(shadow_points, solid_colors(shadow_points.size(), Color(0, 0, 0, 0.22)))
	ci.draw_polygon(outer, hex_gradient_colors(outer, outline_light, outline_dark))
	ci.draw_polygon(inner, hex_gradient_colors(inner, fill.lightened(0.10), fill.darkened(0.18)))
	draw_rounded_edge_lighting(ci, outer, rect, 1.8, Color(1.0, 1.0, 1.0, 0.20), Color(0.0, 0.0, 0.0, 0.24))
	draw_rounded_edge_lighting(ci, inner, inner_rect, 1.8, Color(1.0, 1.0, 1.0, 0.14), Color(0.0, 0.0, 0.0, 0.18))
	return inner_rect
