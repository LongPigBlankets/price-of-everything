extends Node2D

var fill_color: Color = Color(0, 0, 0, 0)
var hatch_color: Color = Color(1, 1, 1, 0.2)
var tile_size := Vector2(64, 56)
var hatch_gap := 6.0

func _draw() -> void:
	var half_w := tile_size.x * 0.5
	var half_h := tile_size.y * 0.5
	var shoulder_x := tile_size.x * 0.25
	var points := PackedVector2Array([
		Vector2(-shoulder_x, -half_h),
		Vector2(shoulder_x, -half_h),
		Vector2(half_w, 0),
		Vector2(shoulder_x, half_h),
		Vector2(-shoulder_x, half_h),
		Vector2(-half_w, 0),
	])
	draw_colored_polygon(points, fill_color)
	_draw_hatching(half_w, half_h, shoulder_x)
	var outline := PackedVector2Array()
	for point in points:
		outline.append(point)
	outline.append(points[0])
	draw_polyline(outline, hatch_color.darkened(0.2), 1.0)

func _draw_hatching(half_w: float, half_h: float, shoulder_x: float) -> void:
	var y := -half_h + hatch_gap
	while y < half_h:
		var x_bound := lerpf(half_w, shoulder_x, absf(y) / half_h)
		draw_line(Vector2(-x_bound, y), Vector2(x_bound, y), hatch_color, 1.0)
		y += hatch_gap
