extends Control
## Draws the metal-plate material over the navy tray (alt menu only): a diagonal
## sheen (lighter top-left), faint cast-iron noise, and an inner bevel (bright
## top/left edge, dark bottom/right). Sits under the silver frame.

const PLATE_TEX := preload("res://assets/icons/ui_icons/alt/_plate.png")

func _ready() -> void:
	resized.connect(queue_redraw)
	MatchState.alt_bottom_menu_changed.connect(func(_e): queue_redraw())

func _draw() -> void:
	if not MatchState.use_alt_bottom_menu:
		return  # the metal-plate material is part of the alt look only
	draw_texture_rect(PLATE_TEX, Rect2(Vector2.ZERO, size), false)
