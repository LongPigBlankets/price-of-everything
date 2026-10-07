extends Control
## The Research panel in DS2: one research as a patent drawing pinned to the board. Presentation only: the shell
## (research_ds2.gd) hands it the research's row and what state it is in, read from the research panel and
## ResearchState.
##
## The sheet, top to bottom: a drawing pin; the research's icon drawn as white lines; its title in technical
## capitals; its condition as a spec line ("PRODUCE 500 COAL"); and a white scale filling toward the target with
## the count over it ("212/500"). By state:
##   open      a blueprint, its scale filling;
##   locked    the blueprint faded, a padlock in its corner, and the research it needs under the scale;
##   granted   the cream copy kept on file, a red rubber GRANTED stamp across it;
##   licensed  the same, the stamp in blue: LICENSED (taken free from a knowledge sharing offer).
## While licences are being chosen an open sheet glows and takes a click; the rest dim.

signal hover_changed(card: Control, on: bool)
signal picked(card: Control)

const Ink := preload("res://scripts/research_ds2/ink.gd")
const GoodIcons := preload("res://scripts/good_icons.gd")
const KeyedBuildingIcon := preload("res://scripts/keyed_building_icon.gd")
const EffectEmblem := preload("res://scripts/effect_emblem.gd")

const SIZE := Vector2(228, 188)
const PAD := 14.0
const ICON := 50.0
const TITLE_PX := 16
const TITLE_MIN_PX := 12
const SPEC_PX := 15
const SPEC_MIN_PX := 12
const FIGURE_PX := 15
const NOTE_PX := 14
## The pin stands this far down the sheet's top edge.
const PIN_DROP := 4.0
## The stamp: its box, and its turn off square (a few degrees), varied a little per sheet.
const STAMP_SIZE := Vector2(156, 46)
const STAMP_ANGLE := -0.13

var title := ""
var node_id := ""
## "open", "locked", "granted" or "licensed".
var state := "open"
## The condition in a line or two, and how far it has come (Vector2i.ZERO when it has no count).
var spec := ""
var progress := Vector2i.ZERO
## What a locked sheet waits for ("NEEDS COAL WASHING"), or the category when the board shows a search.
var note := ""
var icon_kind := "system"
var icon_base := ""
var icon_glyph := "gears"
var choosing := false
var eligible := false
var hot := false:
	set(v):
		if hot != v:
			hot = v
			queue_redraw()
## Lit by a search on the board: the sheet's border picked out.
var matched := false

var _icon: Control


func _init() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_icon = IconLines.new()
	_icon.name = "Icon"
	_icon.position = Vector2(PAD, PAD + 6.0)
	_icon.size = Vector2(ICON, ICON)
	add_child(_icon)
	mouse_entered.connect(func() -> void:
		hot = true
		hover_changed.emit(self, true))
	mouse_exited.connect(func() -> void:
		hot = false
		hover_changed.emit(self, false))


## Sets the sheet from `unlock` (a research panel row) and its presentation spec.
func configure(unlock: Dictionary, presentation: Dictionary) -> void:
	title = str(unlock.get("title", ""))
	node_id = str(unlock.get("research_node_id", ""))
	name = "Card_%s" % node_id
	icon_kind = str(presentation.get("kind", "system"))
	icon_base = str(presentation.get("base", ""))
	icon_glyph = str(presentation.get("glyph", "gears"))
	_icon.set("texture", _icon_texture())
	refresh_look()


func refresh_look() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if (choosing and eligible) else Control.CURSOR_ARROW
	_icon.set("ink", Color(_line_ink(), 0.72) if state == "locked" else _line_ink())
	_icon.queue_redraw()
	queue_redraw()


func is_granted() -> bool:
	return state == "granted" or state == "licensed"


## The point of the sheet's pin, in the sheet's own frame.
func pin_point() -> Vector2:
	return Vector2(size.x * 0.5, PIN_DROP + 4.0)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and choosing and eligible:
		picked.emit(self)
		accept_event()


func _icon_texture() -> Texture2D:
	match icon_kind:
		"good":
			var good: Dictionary = Catalog.get_good(icon_base)
			return GoodIcons.texture_for_size(icon_base, str(good.get("internal_name", "")), 80.0)
		"building":
			return KeyedBuildingIcon.keyed(Catalog.get_building(icon_base))
	return EffectEmblem.texture(icon_glyph)


func _paper() -> Color:
	match state:
		"granted", "licensed":
			return Ink.PAPER
		"locked":
			return Ink.FADED
	return Ink.BLUEPRINT


func _edge() -> Color:
	match state:
		"granted", "licensed":
			return Ink.PAPER_EDGE
		"locked":
			return Ink.FADED_EDGE
	return Ink.BLUEPRINT_EDGE


## The drawing's line colour: white on the blueprint, navy on the cream copy.
func _line_ink() -> Color:
	return Ink.NAVY_LINE if is_granted() else Ink.WHITE_LINE


func _print_ink() -> Color:
	return Ink.NAVY if is_granted() else Color.WHITE


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	Ink.cast_shadow(self, r, 6.0 if hot else Ink.SHADOW_REACH, 0.55 if hot else 0.42)
	if choosing and eligible:
		for i in 4:
			var g := StyleBoxFlat.new()
			g.bg_color = Color(Ink.PICK_GLOW, 0.42 - float(i) * 0.09)
			g.set_corner_radius_all(5 + i * 2)
			draw_style_box(g, r.grow(2.0 + float(i) * 3.0))
	var sheet := StyleBoxFlat.new()
	sheet.bg_color = _paper()
	sheet.border_color = _edge()
	sheet.set_border_width_all(1)
	sheet.set_corner_radius_all(2)
	draw_style_box(sheet, r)
	_draw_grid(r)
	_draw_border(r)
	_draw_title()
	var spec_top := PAD + 6.0 + ICON + 8.0
	var spec_lines := 3 if progress == Vector2i.ZERO else 2
	var spec_text := spec.to_upper()
	var spec_px := Ink.fit(Ink.SPEC_FONT, spec_text, size.x - PAD * 2.0, SPEC_PX, SPEC_MIN_PX, spec_lines)
	var lines := Ink.wrap(Ink.SPEC_FONT, spec_text, size.x - PAD * 2.0, spec_px, spec_lines)
	Ink.print_lines(self, Ink.SPEC_FONT, lines, PAD, spec_top, size.x - PAD * 2.0, spec_px, float(spec_px) + 1.0,
		Color(_print_ink(), 0.95))
	# The foot: a note line (what a locked sheet needs, or its category on a search) under the scale.
	var foot := size.y - PAD - 2.0
	if note != "":
		var note_text := note.to_upper()
		var npx := Ink.fit(Ink.SPEC_FONT, note_text, size.x - PAD * 2.0, NOTE_PX, 11, 1)
		var nl := Ink.wrap(Ink.SPEC_FONT, note_text, size.x - PAD * 2.0, npx, 1)
		var colour := Color("#ffd27a") if state == "locked" else _print_ink()
		Ink.print_lines(self, Ink.SPEC_FONT, nl, PAD, foot - float(npx) - 2.0, size.x - PAD * 2.0, npx, 0.0, colour)
		foot -= float(npx) + 6.0
	if not is_granted() and progress != Vector2i.ZERO:
		_draw_scale(Rect2(PAD, foot - 28.0, size.x - PAD * 2.0, 28.0))
	if state == "locked":
		Ink.padlock(self, Vector2(size.x - PAD - 6.0, PAD + 9.0), 15.0, Color(1, 1, 1, 0.9))
	if is_granted():
		var licensed := state == "licensed"
		var turn := STAMP_ANGLE + float(absi(hash(title)) % 7 - 3) * 0.012
		Ink.stamp(self, Vector2(size.x * 0.5, minf(foot - 22.0, size.y - 48.0)), STAMP_SIZE, "LICENSED" if licensed else "GRANTED",
			Ink.STAMP_BLUE if licensed else Ink.STAMP_RED, turn, hash(title))
	if hot and not (choosing and not eligible):
		draw_rect(r.grow(1.0), Color(1, 1, 1, 0.55), false, 1.5)
	if choosing and not eligible:
		draw_rect(r, Color(0.02, 0.04, 0.08, 0.45))
	Ink.pin(self, Vector2(size.x * 0.5, PIN_DROP + 4.0), "people_pin_blue" if state == "licensed" else "people_pin_red", 1.5)


## The drafting grid: a fine ruling every 8 px, a heavier one every 40.
func _draw_grid(r: Rect2) -> void:
	var ink := _line_ink()
	var fine := Color(ink, 0.07)
	var heavy := Color(ink, 0.13)
	var x := 8.0
	while x < r.size.x:
		draw_line(Vector2(x, 1), Vector2(x, r.size.y - 1), heavy if int(x) % 40 == 0 else fine, 1.0)
		x += 8.0
	var y := 8.0
	while y < r.size.y:
		draw_line(Vector2(1, y), Vector2(r.size.x - 1, y), heavy if int(y) % 40 == 0 else fine, 1.0)
		y += 8.0


## The drawing's border, a heavy rule inside a fine one.
func _draw_border(r: Rect2) -> void:
	var ink := _line_ink()
	draw_rect(r.grow(-5.0), Color(ink, 0.55), false, 1.0)
	draw_rect(r.grow(-8.0), Color(ink, 0.9), false, 1.6)


func _draw_title() -> void:
	var left := PAD + ICON + 10.0
	var w := size.x - left - PAD - (16.0 if state == "locked" else 0.0)
	var text := title.to_upper()
	var px := Ink.fit(Ink.TITLE_FONT, text, w, TITLE_PX, TITLE_MIN_PX, 3)
	var lines := Ink.wrap(Ink.TITLE_FONT, text, w, px, 3)
	var pitch := float(px) + 2.0
	var top := PAD + 6.0 + (ICON - pitch * float(lines.size())) * 0.5 - 1.0
	Ink.print_lines(self, Ink.TITLE_FONT, lines, left, top, w, px, pitch, _print_ink())


## The scale: a white rule with ticks every tenth, the run so far hatched along it to a marker, the count over
## its right end.
func _draw_scale(r: Rect2) -> void:
	var ink := _print_ink()
	var share := clampf(float(progress.x) / float(maxi(progress.y, 1)), 0.0, 1.0)
	var base_y := r.end.y - 4.0
	var x0 := r.position.x
	var x1 := r.end.x
	var figure := "%d/%d" % [progress.x, progress.y]
	var font: Font = Ink.UIFonts.mono()
	var fw := font.get_string_size(figure, HORIZONTAL_ALIGNMENT_LEFT, -1, FIGURE_PX).x
	draw_string(font, Vector2(x1 - fw, r.position.y + font.get_ascent(FIGURE_PX) - 6.0), figure,
		HORIZONTAL_ALIGNMENT_LEFT, -1, FIGURE_PX, ink)
	var bar := Rect2(x0, base_y - 7.0, (x1 - x0) * share, 6.0)
	if bar.size.x > 0.5:
		draw_rect(bar, Color(ink, 0.32))
		var hx := bar.position.x - 6.0
		while hx < bar.end.x:
			var a := Vector2(maxf(hx, bar.position.x), bar.end.y - maxf(0.0, bar.position.x - hx))
			var b := Vector2(minf(hx + 6.0, bar.end.x), bar.position.y + maxf(0.0, hx + 6.0 - bar.end.x))
			draw_line(a, b, Color(ink, 0.85), 1.2, true)
			hx += 4.0
	draw_line(Vector2(x0, base_y), Vector2(x1, base_y), ink, 1.6)
	for i in 11:
		var tx := x0 + (x1 - x0) * float(i) / 10.0
		var tall := 7.0 if i % 5 == 0 else 4.0
		draw_line(Vector2(tx, base_y), Vector2(tx, base_y + tall * 0.5 + 1.0), ink, 1.2)
		draw_line(Vector2(tx, base_y), Vector2(tx, base_y - tall), Color(ink, 0.6), 1.0)
	var mx := x0 + (x1 - x0) * share
	draw_colored_polygon(PackedVector2Array([Vector2(mx, base_y - 8.0), Vector2(mx - 4.0, base_y - 14.0), Vector2(mx + 4.0, base_y - 14.0)]), ink)


## The research's icon drawn as lines in the drawing's ink: its outline and the edges inside it, over a faint
## fill, by a small canvas shader, so goods, buildings and glyphs all read as parts of one drawing.
class IconLines extends Control:
	static var _line_shader: Shader
	var texture: Texture2D:
		set(v):
			texture = v
			queue_redraw()
	var ink := Color.WHITE:
		set(v):
			ink = v
			if material != null:
				(material as ShaderMaterial).set_shader_parameter("ink", ink)

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var m := ShaderMaterial.new()
		m.shader = IconLines.line_shader()
		m.set_shader_parameter("ink", ink)
		material = m

	func _draw() -> void:
		if texture == null:
			return
		var ts := texture.get_size()
		var k := minf(size.x / ts.x, size.y / ts.y)
		var d := ts * k
		var r := Rect2((size - d) * 0.5, d)
		(material as ShaderMaterial).set_shader_parameter("step_uv", Vector2(1.4 / maxf(d.x, 1.0), 1.4 / maxf(d.y, 1.0)))
		draw_texture_rect(texture, r, false)

	static func line_shader() -> Shader:
		if _line_shader != null:
			return _line_shader
		_line_shader = Shader.new()
		_line_shader.code = """
shader_type canvas_item;
uniform vec4 ink : source_color = vec4(1.0);
uniform vec2 step_uv = vec2(0.02);
uniform float fill = 0.16;

float lum(vec4 c) { return dot(c.rgb, vec3(0.299, 0.587, 0.114)); }

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float l = lum(c);
	float lowest = 1.0;
	float edge = 0.0;
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.785398;
		vec2 o = vec2(cos(a), sin(a)) * step_uv;
		vec4 s = texture(TEXTURE, UV + o);
		lowest = min(lowest, s.a);
		edge = max(edge, abs(lum(s) - l) * min(s.a, c.a));
	}
	float outline = clamp((c.a - lowest) * 2.2, 0.0, 1.0);
	float inner = smoothstep(0.07, 0.2, edge);
	float v = max(outline, inner * 0.9) + c.a * fill;
	COLOR = vec4(ink.rgb, clamp(v, 0.0, 1.0) * ink.a);
}
"""
		return _line_shader
