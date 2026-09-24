extends Control
## Building Detail v3: a section heading in raised white letters, lettered exactly as INPUTS and OUTPUTS
## on the control plate: IBM Plex Sans Bold, the same white letters raised on the same softened flank,
## the same swept shadow and contact line, faces graded from white at the top-left to warm grey at the
## bottom-right. The letters come from an atlas rendered by tools/button_mockup/cluster.html?export
## (res://assets/ui/bdp_v3/heading_glyphs.png, and heading_glyph_shadows.png for their shadows); each
## cell in layout.json carries the letter's advance, and the letters are set along one line by them.
## The shadows are all drawn before the faces. A heading with a character the atlas lacks can't be
## shown (can_show), and the panel keeps its plain label for it.

const CAPTURE_SCALE := 1.875
const TEXELS_PER_PIXEL := 2.0
const FACES: Texture2D = preload("res://assets/ui/bdp_v3/heading_glyphs.png")
const SHADOWS: Texture2D = preload("res://assets/ui/bdp_v3/heading_glyph_shadows.png")
## The face at the heading's bottom-right; white at its top-left (as the title's).
const FACE_GRADE := Color("#b8b0a0")
const LAYOUT_PATH := "res://assets/ui/bdp_v3/layout.json"
## The room round each letter in its cell (cluster.html HEADING.pad), in layout pixels.
const PAD := 8.0

## layout.json's heading_glyphs: {glyphs: {char: [x, y, w, h, pen x, advance]}, baseline, space, ...},
## in layout pixels.
static var _atlas := {}

var text := "": set = set_text
## [face region, drawn rect, face shade] per letter, left to right.
var _letters: Array = []


static func atlas() -> Dictionary:
	if _atlas.is_empty():
		var f := FileAccess.open(LAYOUT_PATH, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_atlas = (parsed as Dictionary).get("heading_glyphs", {})
	return _atlas


## True when every character of `heading` (in capitals) has a letter in the atlas.
static func can_show(heading: String) -> bool:
	var glyphs: Dictionary = atlas().get("glyphs", {})
	if glyphs.is_empty():
		return false
	for ch in heading.to_upper():
		if ch != " " and not glyphs.has(ch):
			return false
	return true


func _init() -> void:
	name = "BdpV3Heading"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func set_text(value: String) -> void:
	text = value.to_upper()
	_lay_out()


func letter_count() -> int:
	return _letters.size()


## Places each letter's cell on its pen position and grades the faces across the heading.
func _lay_out() -> void:
	_letters.clear()
	var at := atlas()
	var glyphs: Dictionary = at.get("glyphs", {})
	var k := TEXELS_PER_PIXEL / CAPTURE_SCALE
	var placed: Array = []
	var x := 0.0
	var cell_h := 0.0
	for ch in text:
		if not glyphs.has(ch):
			x += float(at.get("space", 7.0)) / CAPTURE_SCALE
			continue
		var c: Array = glyphs[ch]
		cell_h = float(c[3]) / CAPTURE_SCALE
		var src := Rect2(float(c[0]) * k, float(c[1]) * k, float(c[2]) * k, float(c[3]) * k)
		var dst := Rect2(x - float(c[4]) / CAPTURE_SCALE, -PAD / CAPTURE_SCALE, float(c[2]) / CAPTURE_SCALE, cell_h)
		placed.append([src, dst, x + float(c[5]) / CAPTURE_SCALE * 0.5])
		x += float(c[5]) / CAPTURE_SCALE
	for p: Array in placed:
		var t := clampf((float(p[2]) / maxf(x, 1.0) + 0.5) * 0.5, 0.0, 1.0)
		_letters.append([p[0], p[1], Color.WHITE.lerp(FACE_GRADE, t)])
	# The cells carry room for the shadow round each letter; the control is the letters' own size.
	custom_minimum_size = Vector2(ceilf(x), ceilf(maxf(cell_h - 2.0 * PAD / CAPTURE_SCALE, 0.0)))
	queue_redraw()


func _draw() -> void:
	for l: Array in _letters:
		draw_texture_rect_region(SHADOWS, l[1], l[0])
	for l: Array in _letters:
		draw_texture_rect_region(FACES, l[1], l[0], l[2])
