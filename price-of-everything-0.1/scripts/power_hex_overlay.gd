extends Node2D
## A transparent flat-top hex mask sized to a terrain tile. Set `color` (alpha controls
## transparency) and `tile_size` before adding to the tree. For a "partial" power tile (some
## consumption self-supplied, some bought from the national grid), set `hatch = true` plus
## `hatch_color`: the base `color` (amber) fills the hex and `hatch_color` (red) is overlaid as
## 10px-thick diagonal bars separated by 10px gaps.

var color: Color = Color(0, 0, 0, 0)
var tile_size := Vector2(64, 56)
var hatch: bool = false
var hatch_color: Color = Color(0.8, 0.2, 0.2, 0.5)

const HATCH_BAR_WIDTH := 10.0   # red bar thickness
const HATCH_STRIDE := 20.0      # 10px red bar + 10px amber gap

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
				draw_polyline(seg, col, HATCH_BAR_WIDTH)
		off += HATCH_STRIDE
