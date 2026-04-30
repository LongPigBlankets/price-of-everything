extends Node2D

@export var color: Color = Color.WHITE
@export var radius: float = 18.0

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, color)
