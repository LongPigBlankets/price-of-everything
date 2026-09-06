extends Control
## Shared cream-on-navy cost/effect emblem, also used by Research.
const CREAM := Color("#f6e8c6")
static var _cache := {}
var glyph := "gears"

static func make(symbol: String, side: float = 28.0, tip: String = "") -> Control:
	var icon = load("res://scripts/effect_emblem.gd").new()
	icon.glyph = symbol
	icon.name = "EffectEmblem_" + symbol
	icon.custom_minimum_size = Vector2(side, side)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.tooltip_text = tip
	return icon

func _draw() -> void:
	draw_on(self, Rect2(Vector2.ZERO, size).grow(-1.0), glyph)

static func draw_on(canvas: CanvasItem, rect: Rect2, symbol: String, direction: String = "") -> void:
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color("#051a2e")
	plate.border_color = CREAM
	plate.set_border_width_all(1)
	plate.set_corner_radius_all(4)
	canvas.draw_style_box(plate, rect)
	var art := texture(symbol)
	if art != null:
		canvas.draw_texture_rect(art, rect.grow(-3.0), false, CREAM)
	if direction != "" and symbol != "merge":
		var pill := Rect2(Vector2(rect.position.x - 4.0, rect.end.y - 10.0), Vector2(16.0, 16.0))
		canvas.draw_style_box(plate, pill)
		canvas.draw_texture_rect(texture(direction), pill.grow(-2.0), false, CREAM)

static func texture(name: String) -> Texture2D:
	if _cache.has(name):
		return _cache[name]
	var path := "res://assets/icons/ui_icons/standalone/open-book.png" if name == "encyclopedia" else "res://assets/icons/research/glyph/%s.png" % name
	if not ResourceLoader.exists(path):
		return null
	# Existing glyphs are navy alpha masks. Cache a neutral mask so the theme can
	# tint the same art ivory, mint or brass without changing the source files.
	var source: Texture2D = load(path)
	var mask := source.get_image()
	mask.convert(Image.FORMAT_RGBA8)
	for y in mask.get_height():
		for x in mask.get_width():
			mask.set_pixel(x, y, Color(1, 1, 1, mask.get_pixel(x, y).a))
	if name == "merge":
		mask.rotate_90(CLOCKWISE)
	mask.generate_mipmaps() # Rebuild the imported navy mip levels after recolouring.
	var texture := ImageTexture.create_from_image(mask)
	_cache[name] = texture
	return texture
