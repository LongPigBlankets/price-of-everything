extends Control
## Building Detail v3: the panel's title in raised white letters, with the effects of the INPUTS /
## OUTPUTS lettering on the control plate: the same white letters raised on a softened flank, the same
## swept shadow and contact line, and faces graded from white at the top-left to warm grey at the
## bottom-right. The letters come from an atlas rendered by tools/button_mockup/cluster.html?export
## (res://assets/ui/bdp_v3/title_glyphs.png, and title_glyph_shadows.png for their shadows), whose cells
## are listed in layout.json.
##
## The title is set in its own font at its own size (Bebas Neue, 32 px), shaped and wrapped by Godot
## as the plain label would be, and each letter's render is placed on its pen position. The shadows
## are all drawn before the faces. The plate's lettering is graded across its whole word, so here the
## faces are graded across the whole title, one shade per letter. A title with a character the atlas
## lacks can't be shown (can_show), and the panel keeps its plain label for it.

const CAPTURE_SCALE := 1.875
const TEXELS_PER_PIXEL := 2.0
const FACES: Texture2D = preload("res://assets/ui/bdp_v3/title_glyphs.png")
const SHADOWS: Texture2D = preload("res://assets/ui/bdp_v3/title_glyph_shadows.png")
const FONT: FontFile = preload("res://assets/fonts/BebasNeue-Regular.ttf")
const FONT_SIZE := 32
const LINE_SPACING := 3.0
## The face at the title's bottom-right; white at its top-left (cluster.html FACE_GRADE).
const FACE_GRADE := Color("#b8b0a0")
const LAYOUT_PATH := "res://assets/ui/bdp_v3/layout.json"

## layout.json's title_glyphs: {glyphs: {char: [x, y, w, h, pen x]}, baseline, ...}, in layout pixels.
static var _atlas := {}

var text := "": set = set_text
var _para := TextParagraph.new()
## [face region, drawn rect, face shade] per letter, top to bottom, left to right.
var _letters: Array = []


static func atlas() -> Dictionary:
	if _atlas.is_empty():
		var f := FileAccess.open(LAYOUT_PATH, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_atlas = (parsed as Dictionary).get("title_glyphs", {})
	return _atlas


## True when every character of `title` (in capitals) has a letter in the atlas.
static func can_show(title: String) -> bool:
	var glyphs: Dictionary = atlas().get("glyphs", {})
	if glyphs.is_empty():
		return false
	for ch in title.to_upper():
		if ch != " " and not glyphs.has(ch):
			return false
	return true


func _init() -> void:
	name = "BdpV3Title"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_para.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE


func set_text(value: String) -> void:
	text = value.to_upper()
	_lay_out()


func letter_count() -> int:
	return _letters.size()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and not is_equal_approx(_para.width, size.x):
		_lay_out()


## Shapes and wraps the title at this control's width, places each letter's render on its pen
## position, and grades the faces across the block the lines fill.
func _lay_out() -> void:
	_letters.clear()
	_para.clear()
	_para.width = size.x if size.x > 0.0 else custom_minimum_size.x
	_para.add_string(text, FONT, FONT_SIZE)
	var at := atlas()
	var glyphs: Dictionary = at.get("glyphs", {})
	var cell_baseline := float(at.get("baseline", 0.0)) / CAPTURE_SCALE
	var k := TEXELS_PER_PIXEL / CAPTURE_SCALE
	var ts := TextServerManager.get_primary_interface()
	var placed: Array = []
	var y := 0.0
	var block := Vector2.ZERO
	for i in _para.get_line_count():
		var baseline := y + _para.get_line_ascent(i)
		var x := 0.0
		for gl: Dictionary in ts.shaped_text_get_glyphs(_para.get_line_rid(i)):
			var ch := text.substr(int(gl.get("start", 0)), 1)
			var offset: Vector2 = gl.get("offset", Vector2.ZERO)
			if glyphs.has(ch):
				var c: Array = glyphs[ch]
				var src := Rect2(float(c[0]) * k, float(c[1]) * k, float(c[2]) * k, float(c[3]) * k)
				var dst := Rect2(x + offset.x - float(c[4]) / CAPTURE_SCALE, baseline + offset.y - cell_baseline,
					float(c[2]) / CAPTURE_SCALE, float(c[3]) / CAPTURE_SCALE)
				placed.append([src, dst, Vector2(x + float(gl.get("advance", 0.0)) * 0.5, baseline - FONT_SIZE * 0.35)])
			x += float(gl.get("advance", 0.0))
		block = Vector2(maxf(block.x, x), y + _para.get_line_size(i).y)
		y += _para.get_line_size(i).y + LINE_SPACING
	for p: Array in placed:
		var mid: Vector2 = p[2]
		var t := clampf((mid.x / maxf(block.x, 1.0) + mid.y / maxf(block.y, 1.0)) * 0.5, 0.0, 1.0)
		_letters.append([p[0], p[1], Color.WHITE.lerp(FACE_GRADE, t)])
	custom_minimum_size.y = ceilf(block.y)
	queue_redraw()


func _draw() -> void:
	for l: Array in _letters:
		draw_texture_rect_region(SHADOWS, l[1], l[0])
	for l: Array in _letters:
		draw_texture_rect_region(FACES, l[1], l[0], l[2])
