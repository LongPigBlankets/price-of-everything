extends TextureButton
## Building Detail v3: a small cream keycap with a navy glyph (Close ✕, Back ‹), with the shadow it
## casts on the panel baked around it (layers from tools/button_mockup/cluster.html?export).
## The texture is 96 layout pixels square with the key in its middle 64; it draws at logical size.

const CAPTURE_SCALE := 1.875
const TEXTURE_SIDE := 96.0


static func make(glyph: String) -> TextureButton:
	var b: TextureButton = load("res://scripts/bdp_v3_key.gd").new()
	b.name = "BdpV3" + glyph.capitalize() + "Key"
	b.texture_normal = load("res://assets/ui/bdp_v3/key_%s.png" % glyph)
	b.texture_pressed = load("res://assets/ui/bdp_v3/key_%s_pressed.png" % glyph)
	b.ignore_texture_size = true
	b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var side := roundf(TEXTURE_SIDE / CAPTURE_SCALE)
	b.custom_minimum_size = Vector2(side, side)
	# Square at its own size: never stretched by a taller row (the header grows with a two-line title).
	b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = "Close" if glyph == "close" else "Back"
	return b
