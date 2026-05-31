extends Node2D

var bounds := Rect2(Vector2.ZERO, Vector2.ZERO)
var color := Color(0, 0, 0, 0.32)

func _draw() -> void:
	draw_rect(bounds, color, true)
