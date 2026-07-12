extends Node2D
## A transparent flat-top hex mask sized to a terrain tile. Set `color` (alpha controls
## transparency) and `tile_size` before adding to the tree. Set `hatch = true` plus a
## `hatch_color` to overlay 45° diagonal bars on the base `color`, clipped to the hex — e.g.
## the "partly grid" power tile (amber base + red bars) or the intermittency tile (amber base +
## green barber-pole). `hatch_bar_width` / `hatch_stride` (world units, perpendicular) tune the
## bar thickness and pitch per instance.

var color: Color = Color(0, 0, 0, 0)
var tile_size := Vector2(64, 56)
var hatch: bool = false
var hatch_color: Color = Color(0.8, 0.2, 0.2, 0.5)
var hatch_bar_width: float = 10.0   # bar thickness (default: legacy 10px red "partly grid" bar)
var hatch_stride: float = 20.0      # x-step between bars (10px bar + 10px gap by default)

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
	if hatch:
		_draw_hatch(points, hatch_color)

# 45° diagonal bars clipped to the hex polygon (reuses the money_chart hatch approach).
func _draw_hatch(poly: PackedVector2Array, col: Color) -> void:
	var min_x := poly[5].x   # left vertex
	var max_x := poly[2].x   # right vertex
	var span_y := tile_size.y
	var off := -span_y
	while off < (max_x - min_x):
		var p1 := Vector2(min_x + off, -span_y * 0.5)
		var p2 := Vector2(min_x + off + span_y, span_y * 0.5)
		var line := PackedVector2Array([p1, p2])
		for seg in Geometry2D.intersect_polyline_with_polygon(line, poly):
			if seg.size() >= 2:
				draw_polyline(seg, col, hatch_bar_width)
		off += hatch_stride
