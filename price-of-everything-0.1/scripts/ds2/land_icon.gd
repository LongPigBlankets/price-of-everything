extends Control
## DS2: the land icon, a hex half filled (the construct panel's land requirement draws the same shape), in
## the good tiles' cream so it sits with the other icons in a cream outline.

const UIHelpers := preload("res://scripts/ui_helpers.gd")
## The hex's radius against the box, and its outline.
const RADIUS := 0.42
const LINE := 2.5

var ink: Color = UIHelpers.PILL_PAPER


func _init(side: float = 40.0) -> void:
	name = "LandIcon"
	custom_minimum_size = Vector2(side, side)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * RADIUS
	var hex := PackedVector2Array()
	for i in 6:
		hex.append(c + Vector2(cos(i * TAU / 6.0), sin(i * TAU / 6.0)) * r)
	draw_colored_polygon(PackedVector2Array([hex[0], hex[1], hex[2], hex[3]]), ink)
	hex.append(hex[0])
	draw_polyline(hex, ink, LINE, true)
