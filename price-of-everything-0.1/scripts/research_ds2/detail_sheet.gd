extends Control
## The Research panel in DS2: the research pointed at, drawn large. It covers the whole panel: the panel dimmed
## round the drawing under the pointer (left clear, so the pointer stays on it), and a large patent drawing on
## the side away from it, about a third of the panel wide. It takes no clicks: a click goes through to the board,
## and the shell (research_ds2.gd) hides it on any click, wheel turn or gesture.
##
## The sheet: two pins; the icon on a larger sticky note; the title, its rank and category, and its state; what
## it grants in full on the label strip; the condition in full with its count on a large scale, and each part's
## count for a condition of several parts; its prerequisites, granted or not; what it leads to; and a title block in
## the corner as on an engineering drawing (its drawing number, the research id, and its rank).

const Ink := preload("res://scripts/research_ds2/ink.gd")
const Card := preload("res://scripts/research_ds2/blueprint_card.gd")

const SCRIM := Color(0.01, 0.02, 0.04, 0.62)
const MARGIN := 24.0
const WIDTH_SHARE := 0.34
const MIN_W := 460.0
const MAX_W := 700.0
const PAD := 28.0
const NOTE_SIDE := 104.0
const HEAD_PX := 13
const MIN_H := 420.0

## {title, rank, category, node_id, description, condition, progress, parts: [{text, progress}],
##  needs: [{title, granted}], leads: [titles], state, state_text, icon_kind, icon_base, icon_glyph}
var data: Dictionary = {}
## The hovered drawing's rect and the sheet's, in this control's frame.
var hole := Rect2()
var sheet := Rect2()
var _icon: Texture2D


func _init() -> void:
	name = "DetailSheet"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Shows `d` for the drawing at `card_rect` (this control's frame), the sheet on the side away from it.
func show_for(d: Dictionary, card_rect: Rect2, top: float) -> void:
	data = d
	hole = card_rect
	_icon = Card.icon_texture_for(str(d.get("icon_kind", "system")), str(d.get("icon_base", "")), str(d.get("icon_glyph", "gears")))
	var w := clampf(size.x * WIDTH_SHARE, MIN_W, MAX_W)
	var h := clampf(_content_height(w), MIN_H, size.y - top - MARGIN)
	var right := Rect2(Vector2(size.x - MARGIN - w, top), Vector2(w, h))
	var left := Rect2(Vector2(MARGIN, top), Vector2(w, h))
	var overlap_right := right.intersection(card_rect).get_area()
	var overlap_left := left.intersection(card_rect).get_area()
	if card_rect.get_center().x < size.x * 0.5:
		sheet = right if overlap_right <= overlap_left else left
	else:
		sheet = left if overlap_left <= overlap_right else right
	visible = true
	queue_redraw()


## The sheet's height for its content at width `w`: the same steps as _draw_sheet, measured, and the title block.
func _content_height(w: float) -> float:
	var inner := w - PAD * 2.0
	var tw := w - PAD * 2.0 - NOTE_SIDE - 20.0
	var title := str(data.get("title", "")).to_upper()
	var tpx := Ink.fit(Ink.title_font(), title, tw, 28, 18, 3)
	var tl := Ink.wrap(Ink.title_font(), title, tw, tpx, 3).size()
	var sl := Ink.wrap(Ink.spec_font(), str(data.get("state_text", "")).to_upper(), tw, 16, 2).size()
	var y := PAD + maxf(NOTE_SIDE + 4.0, 2.0 + (float(tpx) + 3.0) * float(tl) + 30.0 + 18.0 * float(sl)) + 22.0
	y += 30.0 + 22.0 * float(maxi(Ink.wrap(Ink.body_semi(), str(data.get("description", "")), inner - 24.0, 17, 5).size(), 1)) + 16.0 + 22.0
	y += 30.0 + 21.0 * float(Ink.wrap(Ink.body_font(), str(data.get("condition", "")), inner, 16, 3).size()) + 6.0
	var prog: Vector2i = data.get("progress", Vector2i.ZERO)
	if prog != Vector2i.ZERO and not is_granted():
		y += 48.0
	for part: Dictionary in data.get("parts", []):
		var pt := Ink.wrap(Ink.spec_font(), str(part.get("text", "")).to_upper(), inner * 0.55, 14, 2).size()
		y += maxf(30.0, 15.0 * float(pt) + 10.0)
	y += 14.0 + 30.0 + 22.0 * float(maxi((data.get("needs", []) as Array).size(), 1)) + 14.0
	var leads: Array = data.get("leads", [])
	if not leads.is_empty():
		y += 30.0 + 20.0 * float(Ink.wrap(Ink.body_font(), ", ".join(PackedStringArray(leads)), inner, 15, 3).size())
	return y + 18.0 + 58.0 + 26.0


func hide_sheet() -> void:
	visible = false
	data = {}


func is_granted() -> bool:
	return str(data.get("state", "")) in ["granted", "licensed"]


func _print() -> Color:
	return Ink.NAVY if is_granted() else Color.WHITE


func _draw() -> void:
	if data.is_empty():
		return
	# The panel dimmed round the drawing under the pointer.
	var full := Rect2(Vector2.ZERO, size)
	var h := hole.grow(6.0).intersection(full)
	draw_rect(Rect2(0, 0, size.x, h.position.y), SCRIM)
	draw_rect(Rect2(0, h.end.y, size.x, size.y - h.end.y), SCRIM)
	draw_rect(Rect2(0, h.position.y, h.position.x, h.size.y), SCRIM)
	draw_rect(Rect2(h.end.x, h.position.y, size.x - h.end.x, h.size.y), SCRIM)
	draw_rect(h, Color(1, 1, 1, 0.6), false, 2.0)
	_draw_sheet(sheet)


func _draw_sheet(r: Rect2) -> void:
	Ink.cast_shadow(self, r, 10.0, 0.6, 4)
	var granted := is_granted()
	var paper := Ink.PAPER if granted else (Ink.FADED if str(data.get("state", "")) == "locked" else Ink.BLUEPRINT)
	draw_rect(r, paper)
	var ink := Ink.NAVY_LINE if granted else Ink.WHITE_LINE
	var x := 10.0
	while x < r.size.x:
		draw_line(r.position + Vector2(x, 1), r.position + Vector2(x, r.size.y - 1), Color(ink, 0.13 if int(x) % 50 == 0 else 0.06), 1.0)
		x += 10.0
	var yy := 10.0
	while yy < r.size.y:
		draw_line(r.position + Vector2(1, yy), r.position + Vector2(r.size.x - 1, yy), Color(ink, 0.13 if int(yy) % 50 == 0 else 0.06), 1.0)
		yy += 10.0
	draw_rect(r.grow(-7.0), Color(ink, 0.55), false, 1.0)
	draw_rect(r.grow(-11.0), Color(ink, 0.9), false, 2.0)
	var pr := _print()
	var left := r.position.x + PAD
	var w := r.size.x - PAD * 2.0
	# Head: the note, the title, rank and category, state.
	var note_rect := Rect2(Vector2(left, r.position.y + PAD + 4.0), Vector2(NOTE_SIDE, NOTE_SIDE))
	Ink.sticky_note(self, note_rect, deg_to_rad(-1.5), _icon, Card.icon_tint_for(str(data.get("icon_kind", ""))))
	var tx := note_rect.end.x + 20.0
	var tw := r.end.x - PAD - tx
	var title := str(data.get("title", "")).to_upper()
	var tf := Ink.title_font()
	var tpx := Ink.fit(tf, title, tw, 28, 18, 3)
	var tl := Ink.wrap(tf, title, tw, tpx, 3)
	Ink.print_lines(self, tf, tl, tx, r.position.y + PAD + 2.0, tw, tpx, float(tpx) + 3.0, pr)
	var ty := r.position.y + PAD + 2.0 + (float(tpx) + 3.0) * float(tl.size()) + 6.0
	var sub := "RANK %s   %s" % [str(data.get("rank", "")), str(data.get("category", "")).to_upper()]
	Ink.print_lines(self, Ink.spec_font(), PackedStringArray([sub]), tx, ty, tw, 17, 0.0, pr)
	ty += 24.0
	var state_text := str(data.get("state_text", "")).to_upper()
	var state_col := Color("#ffd27a") if str(data.get("state", "")) == "locked" else pr
	var sl := Ink.wrap(Ink.spec_font(), state_text, tw, 16, 2)
	Ink.print_lines(self, Ink.spec_font(), sl, tx, ty, tw, 16, 18.0, state_col)
	var y := maxf(note_rect.end.y, ty + 18.0 * float(sl.size())) + 22.0
	# Grants: the full reward on the label strip.
	y = _heading("Grants", left, y, w, pr)
	var bf := Ink.body_semi()
	var desc := str(data.get("description", ""))
	var dl := Ink.wrap(bf, desc, w - 24.0, 17, 5)
	var strip := Rect2(Vector2(left, y), Vector2(w, 22.0 * float(maxi(dl.size(), 1)) + 16.0))
	draw_rect(Rect2(strip.position + Ink.shadow_offset(2.0), strip.size), Color(0, 0, 0, 0.3))
	draw_rect(strip, Card.STRIP_INK)
	draw_rect(Rect2(strip.position, Vector2(8.0, strip.size.y)), Ink.NAVY)
	Ink.print_lines(self, bf, dl, left + 18.0, y + 7.0, w - 24.0, 17, 22.0, Ink.NAVY)
	y = strip.end.y + 22.0
	# The condition: in full, its count on a large scale, its parts each counted.
	y = _heading("Condition", left, y, w, pr)
	var cf := Ink.body_font()
	var cl := Ink.wrap(cf, str(data.get("condition", "")), w, 16, 3)
	Ink.print_lines(self, cf, cl, left, y, w, 16, 21.0, pr)
	y += 21.0 * float(cl.size()) + 6.0
	var prog: Vector2i = data.get("progress", Vector2i.ZERO)
	if prog != Vector2i.ZERO and not granted:
		Card.draw_scale(self, Rect2(left, y, w, 40.0), prog, pr, 20)
		y += 48.0
	for part: Dictionary in data.get("parts", []):
		var pp: Vector2i = part.get("progress", Vector2i.ZERO)
		var pt := Ink.wrap(Ink.spec_font(), str(part.get("text", "")).to_upper(), w * 0.55, 14, 2)
		Ink.print_lines(self, Ink.spec_font(), pt, left + 10.0, y + 4.0, w * 0.55, 14, 15.0, pr)
		if pp != Vector2i.ZERO:
			Card.draw_scale(self, Rect2(left + w * 0.6, y, w * 0.4, 26.0), pp, pr, 13)
		y += maxf(30.0, 15.0 * float(pt.size()) + 10.0)
	y += 14.0
	# Its prerequisites, and what it leads to.
	var needs: Array = data.get("needs", [])
	y = _heading("Prerequisites", left, y, w, pr)
	if needs.is_empty():
		Ink.print_lines(self, cf, PackedStringArray(["Nothing"]), left, y, w, 15, 0.0, pr)
		y += 22.0
	for n: Dictionary in needs:
		var got := bool(n.get("granted", false))
		var box := Rect2(Vector2(left + 2.0, y + 3.0), Vector2(13, 13))
		draw_rect(box, pr, false, 1.5)
		if got:
			draw_rect(box.grow(-3.0), pr)
		Ink.print_lines(self, cf, PackedStringArray([str(n.get("title", ""))]), left + 24.0, y, w * 0.7, 15, 0.0, pr)
		var tag := "GRANTED" if got else "NOT YET"
		var tfw := Ink.label_font().get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string(Ink.label_font(), Vector2(r.end.x - PAD - tfw, y + 15.0), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
			pr if got else Color("#ffd27a") if not granted else Ink.STAMP_RED)
		y += 22.0
	y += 14.0
	var leads: Array = data.get("leads", [])
	if not leads.is_empty():
		y = _heading("Leads to", left, y, w, pr)
		var ll := Ink.wrap(cf, ", ".join(PackedStringArray(leads)), w, 15, 3)
		Ink.print_lines(self, cf, ll, left, y, w, 15, 20.0, pr)
	_draw_title_block(r, pr)
	if granted:
		var licensed := str(data.get("state", "")) == "licensed"
		Ink.stamp(self, Vector2(r.end.x - PAD - 120.0, r.position.y + PAD + NOTE_SIDE + 4.0), Vector2(230, 62),
			"LICENSED" if licensed else "GRANTED", Ink.STAMP_BLUE if licensed else Ink.STAMP_RED, -0.1, hash(str(data.get("title", ""))))
	Ink.pin(self, r.position + Vector2(PAD, 12.0), "people_pin_red", 1.7)
	Ink.pin(self, Vector2(r.end.x - PAD, r.position.y + 12.0), "people_pin_red", 1.7)


## A section heading: small capitals over a rule. Returns where its content starts.
func _heading(text: String, x: float, y: float, w: float, ink: Color) -> float:
	var f := Ink.label_font()
	draw_string(f, Vector2(x, y + f.get_ascent(HEAD_PX + 2)), text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, HEAD_PX + 2, ink)
	draw_line(Vector2(x, y + 21.0), Vector2(x + w, y + 21.0), Color(ink, 0.6), 1.0)
	return y + 30.0


## The title block in the lower right corner: drawing number, research id, rank and sheet, ruled in cells.
func _draw_title_block(r: Rect2, ink: Color) -> void:
	var b := Rect2(Vector2(r.end.x - 18.0 - 280.0, r.end.y - 18.0 - 58.0), Vector2(280, 58))
	draw_rect(b, Color(ink, 0.9), false, 1.5)
	draw_line(Vector2(b.position.x, b.position.y + 29.0), Vector2(b.end.x, b.position.y + 29.0), Color(ink, 0.7), 1.0)
	draw_line(Vector2(b.position.x + 190.0, b.position.y), Vector2(b.position.x + 190.0, b.end.y), Color(ink, 0.7), 1.0)
	var lf := Ink.label_font()
	var sf := Ink.spec_font()
	draw_string(lf, b.position + Vector2(6, 11), "DRG. No.", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(ink, 0.85))
	var id_text := str(data.get("node_id", "")).to_upper()
	draw_string(sf, b.position + Vector2(6, 25), id_text, HORIZONTAL_ALIGNMENT_LEFT, -1, Ink.fit(sf, id_text, 178, 13, 8, 1), ink)
	draw_string(lf, b.position + Vector2(196, 11), "RANK", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(ink, 0.85))
	draw_string(sf, b.position + Vector2(196, 25), str(data.get("rank", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ink)
	draw_string(lf, b.position + Vector2(6, 40), "TITLE", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(ink, 0.85))
	var t_text := str(data.get("title", "")).to_upper()
	draw_string(sf, b.position + Vector2(6, 54), t_text, HORIZONTAL_ALIGNMENT_LEFT, -1, Ink.fit(sf, t_text, 178, 13, 8, 1), ink)
	draw_string(lf, b.position + Vector2(196, 40), "SHEET", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(ink, 0.85))
	draw_string(sf, b.position + Vector2(196, 54), "1 OF 1", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ink)
