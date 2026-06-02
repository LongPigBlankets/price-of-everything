extends Node2D
## A transparent flat-top hex sized to a terrain tile — the power mapmode marker
## (replaces the old small circle). Set `color` (alpha controls transparency) and
## `tile_size` before adding to the tree.

var color: Color = Color(0, 0, 0, 0)
var tile_size := Vector2(64, 56)

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
	draw_colored_polygon(points, color)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, Color(color.r, color.g, color.b, minf(1.0, color.a + 0.35)), 2.0, true)
