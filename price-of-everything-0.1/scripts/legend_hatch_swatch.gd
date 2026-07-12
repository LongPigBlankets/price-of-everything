extends Control
## A tiny legend swatch overlay: the parent ColorRect paints the base colour; this
## child draws 45° diagonal bars in `hatch_color`, clipped to the swatch by
## clip_contents. Mirrors power_hex_overlay._draw_hatch at legend scale (a 20px
## swatch, so the bar/stride are much smaller than the tile's world-unit values).

var hatch_color: Color = Color(0.8, 0.2, 0.2)
var bar_width: float = 3.0
var stride: float = 6.0

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _draw() -> void:
	var h := size.y
	var off := -h
	while off < size.x:
		draw_line(Vector2(off, h), Vector2(off + h, 0.0), hatch_color, bar_width)
		off += stride
