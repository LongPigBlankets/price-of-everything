extends Node2D

var bounds := Rect2(Vector2.ZERO, Vector2.ZERO)
# 10% transparent black: terrain stays barely visible under mapmode masks.
var color := Color(0, 0, 0, 0.90)

func _draw() -> void:
	draw_rect(bounds, color, true)
