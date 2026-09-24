extends TextureButton
## Building Detail v3: a small cream keycap with a navy glyph (Close ✕, Back ‹, Location's map pin),
## with the shadow it casts on the panel baked around it (layers from
## tools/button_mockup/cluster.html?export).
## The texture is TEXTURE_SIDE layout pixels square with the key (and its bezel) in its middle KEY_SIDE.
## `key_px` is the key's drawn size in logical pixels; by default the size the small keys have always had.

const CAPTURE_SCALE := 1.875
const TEXTURE_SIDE := 108.0
const KEY_SIDE := 76.0
const DEFAULT_KEY_PX := 64.0 / CAPTURE_SCALE


static func make(glyph: String, key_px: float = DEFAULT_KEY_PX) -> TextureButton:
	var b: TextureButton = load("res://scripts/bdp_v3_key.gd").new()
	b.name = "BdpV3" + glyph.capitalize() + "Key"
	b.texture_normal = load("res://assets/ui/bdp_v3/key_%s.png" % glyph)
	b.texture_pressed = load("res://assets/ui/bdp_v3/key_%s_pressed.png" % glyph)
	b.ignore_texture_size = true
	b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var side := roundf(control_side(key_px))
	b.custom_minimum_size = Vector2(side, side)
	# Square at its own size: never stretched by a taller row (the header grows with a two-line title).
	b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = str({"close": "Close", "back": "Back", "pin": "Location"}.get(glyph, ""))
	return b


## The control's side for a key drawn `key_px` across: the texture's room for its shadow scales with it.
static func control_side(key_px: float) -> float:
	return key_px * TEXTURE_SIDE / KEY_SIDE
