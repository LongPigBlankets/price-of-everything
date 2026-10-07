extends Control
## The Research panel in DS2: one research as a patent drawing pinned to the board. Presentation only: the shell
## (research_ds2.gd) hands it the research's row and what state it is in, read from the research panel and
## ResearchState.
##
## The sheet, top to bottom: a drawing pin; the research's icon on a beige sticky note stuck to the drawing (a
## good in its own colours, a building or a glyph printed navy); its title in technical capitals; its condition
## as a spec line ("PRODUCE 500 COAL"); what it grants on a white label strip ("+15% coal mining output"); and a
## white scale filling toward the target with the count over it ("212/500"). By state:
##   open      a blueprint, its scale filling;
##   locked    the blueprint faded, a padlock in its corner, and the research it needs under the scale;
##   granted   the cream copy kept on file, a red rubber GRANTED stamp across its foot;
##   licensed  the same, the stamp in blue: LICENSED (taken free from a knowledge sharing offer).
## While licences are being chosen an open sheet glows; the board (board_view.gd) turns a click on it into
## `picked`. The sheet passes the pointer on, so a drag that starts on it still pans the board.

signal hover_changed(card: Control, on: bool)
signal picked(card: Control)

const Ink := preload("res://scripts/research_ds2/ink.gd")
const GoodIcons := preload("res://scripts/good_icons.gd")
const EffectEmblem := preload("res://scripts/effect_emblem.gd")

const SIZE := Vector2(236, 228)
const PAD := 14.0
const NOTE_SIDE := 52.0
const TITLE_PX := 16
const TITLE_MIN_PX := 12
const SPEC_PX := 14
const SPEC_MIN_PX := 12
const REWARD_PX := 13
const REWARD_MIN_PX := 11
const FIGURE_PX := 15
const NOTE_PX := 14
## The pin stands this far down the sheet's top edge.
const PIN_DROP := 4.0
## The stamp: its box, and its turn off square (a few degrees), varied a little per sheet.
const STAMP_SIZE := Vector2(150, 42)
const STAMP_ANGLE := -0.12
## The label strip's tab, printed GRANTS.
const TAB_W := 50.0
const STRIP_INK := Color("#f4f0e2")

var title := ""
var node_id := ""
## "open", "locked", "granted" or "licensed".
var state := "open"
## The condition in a line or two, and how far it has come (Vector2i.ZERO when it has no count).
var spec := ""
var progress := Vector2i.ZERO
## What the research grants, in a few words (Ink.short_reward), and in full (the CSV description).
var reward := ""
var reward_full := ""
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

var _icon_tex: Texture2D


func _init() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_PASS
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
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
	reward_full = str(unlock.get("description", ""))
	reward = Ink.short_reward(reward_full)
	icon_kind = str(presentation.get("kind", "system"))
	icon_base = str(presentation.get("base", ""))
	icon_glyph = str(presentation.get("glyph", "gears"))
	_icon_tex = icon_texture_for(icon_kind, icon_base, icon_glyph)
	refresh_look()


func refresh_look() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if (choosing and eligible) else Control.CURSOR_ARROW
	queue_redraw()


func is_granted() -> bool:
	return state == "granted" or state == "licensed"


## The icon on the sticky note, and the tint it is drawn in (white keeps a good's colours; navy prints a mask).
func icon_texture() -> Texture2D:
	return _icon_tex


func icon_tint() -> Color:
	return icon_tint_for(icon_kind)


## A good's own colour art; a building's art keyed to a mask; a glyph.
static func icon_texture_for(kind: String, base: String, glyph: String) -> Texture2D:
	match kind:
		"good":
			var good: Dictionary = Catalog.get_good(base)
			return GoodIcons.texture_for_size(base, str(good.get("internal_name", "")), 160.0)
		"building":
			return Ink.building_mask(Catalog.get_building(base))
	return EffectEmblem.texture(glyph)


static func icon_tint_for(kind: String) -> Color:
	return Color.WHITE if kind == "good" else Ink.ICON_NAVY


## The sticky note's slight turn, the same for every draw of this research.
func note_angle() -> float:
	return deg_to_rad(float(absi(hash(node_id)) % 5 - 2) * 0.8)


## The point of the sheet's pin, in the sheet's own frame.
func pin_point() -> Vector2:
	return Vector2(size.x * 0.5, PIN_DROP + 4.0)


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
	Ink.sticky_note(self, Rect2(Vector2(PAD + 1.0, PAD + 6.0), Vector2(NOTE_SIDE, NOTE_SIDE)), note_angle(), _icon_tex, icon_tint())
	if state == "locked":
		draw_rect(Rect2(Vector2(PAD - 2.0, PAD + 2.0), Vector2(NOTE_SIDE + 6.0, NOTE_SIDE + 8.0)), Color(Ink.FADED, 0.35))
	_draw_title()
	var w := size.x - PAD * 2.0
	# The spec line, then what it grants on its strip.
	var y := PAD + 6.0 + NOTE_SIDE + 8.0
	var spec_text := spec.to_upper()
	var spec_px := Ink.fit(Ink.spec_font(), spec_text, w, SPEC_PX, SPEC_MIN_PX, 2)
	var lines := Ink.wrap(Ink.spec_font(), spec_text, w, spec_px, 2)
	var pitch := float(spec_px) + 1.0
	Ink.print_lines(self, Ink.spec_font(), lines, PAD, y, w, spec_px, pitch, Color(_print_ink(), 0.95))
	y += pitch * float(maxi(lines.size(), 1)) + 6.0
	var reward_bottom := _draw_reward(Rect2(PAD - 2.0, y, w + 4.0, 0.0))
	# The foot: a note line (what a locked sheet needs, or its category on a search) under the scale.
	var foot := size.y - PAD - 2.0
	if note != "":
		var note_text := note.to_upper()
		var npx := Ink.fit(Ink.spec_font(), note_text, w, NOTE_PX, 11, 1)
		var nl := Ink.wrap(Ink.spec_font(), note_text, w, npx, 1)
		var colour := Color("#ffd27a") if state == "locked" else _print_ink()
		Ink.print_lines(self, Ink.spec_font(), nl, PAD, foot - float(npx) - 2.0, w, npx, 0.0, colour)
		foot -= float(npx) + 6.0
	if not is_granted() and progress != Vector2i.ZERO:
		_draw_scale(Rect2(PAD, maxf(foot - 28.0, reward_bottom + 2.0), w, 28.0))
	if state == "locked":
		Ink.padlock(self, Vector2(size.x - PAD - 6.0, PAD + 9.0), 15.0, Color(1, 1, 1, 0.9))
	if is_granted():
		var licensed := state == "licensed"
		var turn := STAMP_ANGLE + float(absi(hash(title)) % 7 - 3) * 0.012
		var cy := clampf(foot - STAMP_SIZE.y * 0.5 - 2.0, reward_bottom + STAMP_SIZE.y * 0.5 - 4.0, size.y - STAMP_SIZE.y * 0.5 - 6.0)
		Ink.stamp(self, Vector2(size.x * 0.5, cy), STAMP_SIZE, "LICENSED" if licensed else "GRANTED",
			Ink.STAMP_BLUE if licensed else Ink.STAMP_RED, turn, hash(title))
	if hot and not (choosing and not eligible):
		draw_rect(r.grow(1.0), Color(1, 1, 1, 0.55), false, 1.5)
	if choosing and not eligible:
		draw_rect(r, Color(0.02, 0.04, 0.08, 0.45))
	Ink.pin(self, Vector2(size.x * 0.5, PIN_DROP + 4.0), "people_pin_blue" if state == "licensed" else "people_pin_red", 1.5)


## What the research grants on a white label strip stuck across the sheet: a navy GRANTS tab, then the reward in
## two lines at most (the readout and the detail sheet carry the full text). Returns the strip's foot.
func _draw_reward(at: Rect2) -> float:
	if reward == "":
		return at.position.y
	var text_w := at.size.x - TAB_W - 12.0
	var font := Ink.body_semi()
	var px := Ink.fit(font, reward, text_w, REWARD_PX, REWARD_MIN_PX, 2)
	var lines := Ink.wrap(font, reward, text_w, px, 2)
	var pitch := float(px) + 3.0
	var h := pitch * float(lines.size()) + 9.0
	var strip := Rect2(at.position, Vector2(at.size.x, h))
	draw_rect(Rect2(strip.position + Ink.shadow_offset(1.5), strip.size), Color(0, 0, 0, 0.28))
	draw_rect(strip, STRIP_INK if state != "locked" else Color(STRIP_INK, 0.82))
	draw_rect(Rect2(strip.position, Vector2(TAB_W, strip.size.y)), Ink.NAVY)
	var lf := Ink.label_font()
	var tw := lf.get_string_size("GRANTS", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(lf, Vector2(strip.position.x + (TAB_W - tw) * 0.5, strip.get_center().y + 4.5), "GRANTS",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	Ink.print_lines(self, font, lines, strip.position.x + TAB_W + 7.0, strip.position.y + 4.0, text_w, px, pitch, Ink.NAVY)
	return strip.end.y


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
	var left := PAD + NOTE_SIDE + 12.0
	var w := size.x - left - PAD - (16.0 if state == "locked" else 0.0)
	var text := title.to_upper()
	var font := Ink.title_font()
	var px := Ink.fit(font, text, w, TITLE_PX, TITLE_MIN_PX, 3)
	var lines := Ink.wrap(font, text, w, px, 3)
	var pitch := float(px) + 2.0
	var top := PAD + 6.0 + (NOTE_SIDE - pitch * float(lines.size())) * 0.5 - 1.0
	Ink.print_lines(self, font, lines, left, top, w, px, pitch, _print_ink())


## The scale: a white rule with ticks every tenth, the run so far hatched along it to a marker, the count over
## its right end.
func _draw_scale(r: Rect2) -> void:
	draw_scale(self, r, progress, _print_ink(), FIGURE_PX)


static func draw_scale(ci: CanvasItem, r: Rect2, have_need: Vector2i, ink: Color, figure_px: int) -> void:
	var share := clampf(float(have_need.x) / float(maxi(have_need.y, 1)), 0.0, 1.0)
	var base_y := r.end.y - 4.0
	var x0 := r.position.x
	var x1 := r.end.x
	var figure := "%d/%d" % [have_need.x, have_need.y]
	var font: Font = Ink.mono_font()
	var fw := font.get_string_size(figure, HORIZONTAL_ALIGNMENT_LEFT, -1, figure_px).x
	ci.draw_string(font, Vector2(x1 - fw, r.position.y + font.get_ascent(figure_px) - 6.0), figure,
		HORIZONTAL_ALIGNMENT_LEFT, -1, figure_px, ink)
	var bar := Rect2(x0, base_y - 7.0, (x1 - x0) * share, 6.0)
	if bar.size.x > 0.5:
		ci.draw_rect(bar, Color(ink, 0.32))
		var hx := bar.position.x - 6.0
		while hx < bar.end.x:
			var a := Vector2(maxf(hx, bar.position.x), bar.end.y - maxf(0.0, bar.position.x - hx))
			var b := Vector2(minf(hx + 6.0, bar.end.x), bar.position.y + maxf(0.0, hx + 6.0 - bar.end.x))
			ci.draw_line(a, b, Color(ink, 0.85), 1.2, true)
			hx += 4.0
	ci.draw_line(Vector2(x0, base_y), Vector2(x1, base_y), ink, 1.6)
	for i in 11:
		var tx := x0 + (x1 - x0) * float(i) / 10.0
		var tall := 7.0 if i % 5 == 0 else 4.0
		ci.draw_line(Vector2(tx, base_y), Vector2(tx, base_y + tall * 0.5 + 1.0), ink, 1.2)
		ci.draw_line(Vector2(tx, base_y), Vector2(tx, base_y - tall), Color(ink, 0.6), 1.0)
	var mx := x0 + (x1 - x0) * share
	ci.draw_colored_polygon(PackedVector2Array([Vector2(mx, base_y - 8.0), Vector2(mx - 4.0, base_y - 14.0), Vector2(mx + 4.0, base_y - 14.0)]), ink)
