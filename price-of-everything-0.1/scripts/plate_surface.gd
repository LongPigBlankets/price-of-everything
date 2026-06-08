extends Control
## Draws the metal-plate material over the navy tray (alt menu only): a diagonal
## sheen (lighter top-left), faint cast-iron noise, and an inner bevel (bright
## top/left edge, dark bottom/right). Sits under the silver frame.

const PLATE_TEX := preload("res://assets/icons/ui_icons/alt/_plate.png")
const LABEL_FONT := preload("res://assets/fonts/BebasNeue-Regular.ttf")
const LABEL := "MK-IV / OPS"

func _ready() -> void:
	resized.connect(queue_redraw)
	MatchState.alt_bottom_menu_changed.connect(func(_e): queue_redraw())

func _draw() -> void:
	if not MatchState.use_alt_bottom_menu:
		return  # the metal-plate material is part of the alt look only
	draw_texture_rect(PLATE_TEX, Rect2(Vector2.ZERO, size), false)
	# Faint worn stencilled part-number along the bottom of the plate, in the
	# narrow strip just below the buttons.
	draw_string(LABEL_FONT, Vector2(24.0, 53.0), LABEL, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 9,
		Color(0.88, 0.84, 0.72, 0.26))
