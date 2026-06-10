extends Node2D

var fill_color: Color = Color(0, 0, 0, 0)
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
	draw_colored_polygon(points, fill_color)
