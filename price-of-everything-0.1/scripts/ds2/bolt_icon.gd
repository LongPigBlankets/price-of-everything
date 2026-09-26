extends Control
## DS2: a plain lightning bolt, for power as a quantity (a building's draw or output), in the good tiles'
## cream so it sits with the other icons in a cream outline. The yellow bolt is the recipe diagram's and the
## power good's; the bolt with a plug (bar_icon_power) is the grid.

const UIHelpers := preload("res://scripts/ui_helpers.gd")
## The bolt's outline in a unit box, top to bottom.
const SHAPE := [Vector2(0.60, 0.04), Vector2(0.22, 0.56), Vector2(0.47, 0.56), Vector2(0.36, 0.96),
	Vector2(0.78, 0.40), Vector2(0.53, 0.40), Vector2(0.66, 0.04)]

var ink: Color = UIHelpers.PILL_PAPER


func _init(side: float = 40.0) -> void:
	name = "BoltIcon"
	custom_minimum_size = Vector2(side, side)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	var pts := PackedVector2Array()
	for p: Vector2 in SHAPE:
		pts.append(o + p * s)
	draw_colored_polygon(pts, ink)
