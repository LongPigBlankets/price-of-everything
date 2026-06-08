extends Control
## Draws the metal-plate material over the navy tray (alt menu only): a diagonal
## sheen (lighter top-left), faint cast-iron noise, and an inner bevel (bright
## top/left edge, dark bottom/right). Sits under the silver frame.
##
## The plate texture is opaque to its edges with corners rounded to the same
## radius as the navy panel fill, so the near-black panel fill no longer peeks
## through a transparent margin as a competing rounded-rect outline. A matching
## grey rounded-rect is still painted underneath as a backstop, so any sub-pixel
## anti-aliasing seam at the rounded corners stays grey rather than navy.

const PLATE_TEX := preload("res://assets/icons/ui_icons/alt/_plate.png")
const LABEL_FONT := preload("res://assets/fonts/BebasNeue-Regular.ttf")
const LABEL := "MK-IV / OPS"
const FILL_COLOR := Color(0.45, 0.48, 0.52)  # mid plate grey, hides any navy seam
const FILL_RADIUS := 12  # same rounding as the navy panel fill it covers

var _fill_sb: StyleBoxFlat

func _ready() -> void:
	resized.connect(queue_redraw)
	MatchState.alt_bottom_menu_changed.connect(func(_e): queue_redraw())
	_fill_sb = StyleBoxFlat.new()
	_fill_sb.bg_color = FILL_COLOR
	_fill_sb.corner_radius_top_left = FILL_RADIUS
	_fill_sb.corner_radius_top_right = FILL_RADIUS
	_fill_sb.corner_radius_bottom_right = FILL_RADIUS
	_fill_sb.corner_radius_bottom_left = FILL_RADIUS

func _draw() -> void:
	if not MatchState.use_alt_bottom_menu:
		return  # the metal-plate material is part of the alt look only
	draw_style_box(_fill_sb, Rect2(Vector2.ZERO, size))  # hide the navy behind the plate's rounded corners
	draw_texture_rect(PLATE_TEX, Rect2(Vector2.ZERO, size), false)
	# Faint worn stencilled part-number along the bottom of the plate, in the
	# narrow strip just below the buttons.
	draw_string(LABEL_FONT, Vector2(24.0, 53.0), LABEL, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 9,
		Color(0.88, 0.84, 0.72, 0.26))
