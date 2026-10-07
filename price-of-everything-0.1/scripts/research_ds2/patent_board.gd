extends Control
## The Research panel in DS2: the patent board, a cork board the open drawer's research is pinned to, scrolled
## up and down inside its metal frame (research_ds2.gd holds the frame and the scroll).
##
## The board is ruled into the three ranks, I at the top, each a row of patent drawings (blueprint_card.gd) that
## wraps onto as many lines as it needs, a brass rank plate at its left with the rank's count granted. Between
## the ranks runs an aluminium straightedge. A rank not yet open sits behind a steel grille with a notice pinned
## to it saying what opens it. Pointing at a drawing runs red threads from its pin to the pins of the research
## it needs and the research that needs it, where those are on the board.

signal card_hover(card: Control, on: bool)
signal card_picked(card: Control)

const Ink := preload("res://scripts/research_ds2/ink.gd")
const Card := preload("res://scripts/research_ds2/blueprint_card.gd")
const Nine := preload("res://scripts/bdp_v3_nine.gd")

## The rank plates' column, the room above the first line (a pin's head), the gaps between drawings, a row's
## padding above and below its drawings and the straightedge between rows.
const GUTTER := 92.0
const TOP := 20.0
const GAP := Vector2(18, 24)
const ROW_PAD := 18.0
const RULE_H := 12.0
const RIGHT := 14.0
const PLATE := Vector2(60, 78)
## The cork's inside in its render (people_cork: 14 layout px of margin and a 16 px frame), in texels, tiled
## across the board at 2 texels a px and darkened a little with age.
const CORK_INSIDE := Rect2(40, 40, 430, 889)
const CORK_TINT := Color(0.74, 0.66, 0.58)
## The notice card (people_card_white, a 9-slice: 10 layout px of margin, 76 corner).
const NOTICE_MARGIN := 10.0
const NOTICE_CORNER := 76.0
const NOTICE_SIZE := Vector2(300, 92)

## [{rank, open, granted, total, notice: {heading, line, count}, cards: [Card]}] as last laid out.
var _rows: Array = []
var _cards := {}
var _row_rects: Array = []
var _grilles: Array = []
var _threads: Control
var _hover := ""
## title -> [titles it needs] and title -> [titles that need it], over the whole research table.
var _needs := {}
var _needed_by := {}
var _empty_text := ""


func _init() -> void:
	name = "PatentBoard"
	mouse_filter = Control.MOUSE_FILTER_PASS
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	clip_contents = false
	resized.connect(_lay_out)


## Pins up `rows` (see _rows; each card entry a dictionary the shell built: {unlock, presentation, state, spec,
## progress, note, eligible}). `needs` maps a title to the titles it needs. `choosing` is licence choosing.
func populate(rows: Array, needs: Dictionary, choosing: bool, empty_text: String = "") -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_cards.clear()
	_grilles.clear()
	_rows.clear()
	_needs = needs
	_needed_by.clear()
	for t: String in needs:
		for p: String in needs[t]:
			if not _needed_by.has(p):
				_needed_by[p] = []
			(_needed_by[p] as Array).append(t)
	_empty_text = empty_text
	for row: Dictionary in rows:
		var built := row.duplicate()
		var cards: Array = []
		for entry: Dictionary in row.get("cards", []):
			var card: Control = Card.new()
			card.set("state", str(entry.get("state", "open")))
			card.set("spec", str(entry.get("spec", "")))
			card.set("progress", entry.get("progress", Vector2i.ZERO))
			card.set("note", str(entry.get("note", "")))
			card.set("choosing", choosing)
			card.set("eligible", bool(entry.get("eligible", false)))
			card.call("configure", entry.get("unlock", {}), entry.get("presentation", {}))
			card.connect("hover_changed", _on_card_hover)
			card.connect("picked", func(c: Control) -> void: card_picked.emit(c))
			add_child(card)
			cards.append(card)
			_cards[str(card.get("title"))] = card
		built["cards"] = cards
		if not bool(row.get("open", true)):
			var grille := Grille.new()
			grille.notice = row.get("notice", {})
			add_child(grille)
			_grilles.append(grille)
			built["grille"] = grille
		_rows.append(built)
	_threads = Threads.new()
	_threads.board = self
	add_child(_threads)
	_hover = ""
	_lay_out()


func card_for(title: String) -> Control:
	return _cards.get(title, null)


func cards() -> Array:
	return _cards.values()


func grilles() -> Array:
	return _grilles


## The rank rows as laid out: [{rank, rect, open}].
func row_rects() -> Array:
	return _row_rects


func hovered_title() -> String:
	return _hover


func columns_for(width: float) -> int:
	return maxi(1, int(floor((width - GUTTER - RIGHT + GAP.x) / (Card.SIZE.x + GAP.x))))


## A drawing's width at `width`: the columns widened to fill the row, up to a third wider than drawn.
func card_width_for(width: float) -> float:
	var cols := columns_for(width)
	var w := (width - GUTTER - RIGHT - GAP.x * float(cols - 1)) / float(cols)
	return clampf(w, Card.SIZE.x, Card.SIZE.x * 1.33)


func _lay_out() -> void:
	var cols := columns_for(size.x)
	var cw := card_width_for(size.x)
	var y := TOP
	_row_rects.clear()
	for i in _rows.size():
		var row: Dictionary = _rows[i]
		var cards: Array = row.cards
		var lines := maxi(1, ceili(float(cards.size()) / float(cols)))
		var top := y
		for j in cards.size():
			var c: Control = cards[j]
			c.size = Vector2(cw, Card.SIZE.y)
			c.position = Vector2(GUTTER + float(j % cols) * (cw + GAP.x), top + ROW_PAD + float(j / cols) * (Card.SIZE.y + GAP.y))
		var h := ROW_PAD * 2.0 + float(lines) * Card.SIZE.y + float(lines - 1) * GAP.y
		h = maxf(h, PLATE.y + 20.0)
		var rect := Rect2(0, top, size.x, h)
		_row_rects.append({"rank": str(row.get("rank", "")), "rect": rect, "open": bool(row.get("open", true))})
		if row.has("grille"):
			var g: Control = row.grille
			g.position = Vector2(GUTTER - 10.0, top + 6.0)
			var used := mini(cards.size(), cols)
			g.size = Vector2(float(used) * (cw + GAP.x) - GAP.x + 20.0, h - 12.0)
		y += h + RULE_H
	var total := y + 10.0
	if _rows.is_empty():
		total = NOTICE_SIZE.y + 80.0
	# The cork reaches the frame's foot however few drawings are pinned.
	var view := get_parent() as Control
	if view != null:
		total = maxf(total, view.size.y)
	if absf(custom_minimum_size.y - total) > 0.5:
		custom_minimum_size.y = total
	if _threads != null:
		_threads.position = Vector2.ZERO
		_threads.size = size
		_threads.queue_redraw()
	queue_redraw()


func _on_card_hover(card: Control, on: bool) -> void:
	var t := str(card.get("title"))
	if on:
		_hover = t
	elif _hover == t:
		_hover = ""
	if _threads != null:
		_threads.queue_redraw()
	card_hover.emit(card, on)


## The titles a hovered drawing is tied to on the board: what it needs and what needs it.
func ties(title: String) -> Array:
	var out: Array = []
	for t in _needs.get(title, []):
		if _cards.has(t) and not out.has(t):
			out.append(t)
	for t in _needed_by.get(title, []):
		if _cards.has(t) and not out.has(t):
			out.append(t)
	return out


func _draw() -> void:
	_draw_cork(Rect2(Vector2.ZERO, size))
	for i in _row_rects.size():
		var rr: Dictionary = _row_rects[i]
		var rect: Rect2 = rr.rect
		var row: Dictionary = _rows[i]
		_draw_rank_plate(Vector2(14, rect.position.y + ROW_PAD - 2.0), str(rr.rank), int(row.get("granted", 0)), int(row.get("total", 0)))
		if i < _row_rects.size() - 1:
			_draw_straightedge(rect.end.y + 1.0)
	if _rows.is_empty() and _empty_text != "":
		var r := Rect2(Vector2(GUTTER, TOP + 20.0), NOTICE_SIZE)
		Grille.notice_card(self, r, {"heading": _empty_text, "line": "", "count": ""})


func _draw_cork(r: Rect2) -> void:
	var t := Ink.tex("people_cork")
	if t == null:
		draw_rect(r, Color("#8a6a45"))
		return
	var tile := CORK_INSIDE.size / 2.0
	var y := 0.0
	while y < r.size.y:
		var x := 0.0
		var th := minf(tile.y, r.size.y - y)
		while x < r.size.x:
			var tw := minf(tile.x, r.size.x - x)
			draw_texture_rect_region(t, Rect2(x, y, tw, th), Rect2(CORK_INSIDE.position, Vector2(tw, th) * 2.0), CORK_TINT)
			x += tile.x
		y += tile.y


## A brass plate screwed to the cork: RANK, the numeral engraved, and the rank's count granted under it.
func _draw_rank_plate(at: Vector2, rank: String, granted: int, total: int) -> void:
	var r := Rect2(at, PLATE)
	Ink.cast_shadow(self, r, 3.0, 0.5, 4)
	var brass := StyleBoxFlat.new()
	brass.bg_color = Color("#b08a3e")
	brass.set_corner_radius_all(4)
	brass.border_color = Color("#6f5320")
	brass.set_border_width_all(1)
	draw_style_box(brass, r)
	# Brushed: a few fine streaks across the face.
	for k in 9:
		var yy := r.position.y + 6.0 + float(k) * 7.4
		draw_line(Vector2(r.position.x + 3, yy), Vector2(r.end.x - 3, yy + 0.6), Color(1, 0.95, 0.75, 0.10 if k % 2 == 0 else 0.05), 1.0)
	Ink.bevel(self, r.grow(-1.0), 2.0, Color(1, 0.93, 0.7, 0.45), Color(0.25, 0.17, 0.05, 0.45))
	var screw := Ink.tex("screw_silver")
	if screw != null:
		for p in [Vector2(r.get_center().x, r.position.y + 7.0), Vector2(r.get_center().x, r.end.y - 7.0)]:
			draw_texture_rect(screw, Rect2(p - Vector2(5.5, 5.5), Vector2(11, 11)), false)
	var navy := Ink.NAVY
	var small := Ink.LABEL_FONT
	var w := small.get_string_size("RANK", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(small, Vector2(r.get_center().x - w * 0.5, r.position.y + 25.0), "RANK", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, navy)
	var big := Ink.STAMP_FONT
	var nw := big.get_string_size(rank, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	draw_string(big, Vector2(r.get_center().x - nw * 0.5 + 0.8, r.position.y + 52.8), rank, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1, 0.92, 0.7, 0.45))
	draw_string(big, Vector2(r.get_center().x - nw * 0.5, r.position.y + 52.0), rank, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, navy)
	var count := "%d/%d" % [granted, total]
	var cw := small.get_string_size(count, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string(small, Vector2(r.get_center().x - cw * 0.5, r.position.y + 67.0), count, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, navy)


## The aluminium straightedge between two ranks: a bar across the board, lit along the edge facing the light.
func _draw_straightedge(y: float) -> void:
	var r := Rect2(8, y + 2.0, size.x - 16.0, RULE_H - 4.0)
	Ink.cast_shadow(self, r, 3.0, 0.45, 2)
	draw_rect(r, Color("#9aa3ab"))
	draw_rect(Rect2(r.position.x, r.position.y + 1.0, r.size.x, 2.0), Color(1, 1, 1, 0.18))
	Ink.bevel(self, r, 1.0, Color(1, 1, 1, 0.5), Color(0.15, 0.17, 0.2, 0.55))
	var x := r.position.x + 24.0
	while x < r.end.x - 10.0:
		draw_line(Vector2(x, r.position.y + 1.0), Vector2(x, r.position.y + (4.0 if int(x) % 120 == 0 else 2.5)), Color(0.15, 0.17, 0.2, 0.7), 1.0)
		x += 12.0


## A rank not yet open: a steel grille over its drawings, a notice pinned to it.
class Grille extends Control:
	const InkRef := preload("res://scripts/research_ds2/ink.gd")
	const NineRef := preload("res://scripts/bdp_v3_nine.gd")
	## {heading, line, count}: "RANK II CLOSED", what opens it, how far that has come.
	var notice: Dictionary = {}

	func _init() -> void:
		name = "RankGrille"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		resized.connect(queue_redraw)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.05, 0.06, 0.08, 0.35))
		var x := 10.0
		while x < r.size.x - 4.0:
			var bar := Rect2(x, 0, 6, r.size.y)
			draw_rect(Rect2(bar.position + InkRef.shadow_offset(3.0), bar.size), Color(0, 0, 0, 0.3))
			draw_rect(bar, Color("#5d656e"))
			draw_rect(Rect2(bar.position.x + bar.size.x - 2.0, 0, 2.0, r.size.y), Color(1, 1, 1, 0.28))
			draw_rect(Rect2(bar.position.x, 0, 1.0, r.size.y), Color(0, 0, 0, 0.4))
			x += 44.0
		for yy in [0.0, r.size.y - 10.0]:
			var rail := Rect2(0, yy, r.size.x, 10.0)
			draw_rect(Rect2(rail.position + InkRef.shadow_offset(3.0), rail.size), Color(0, 0, 0, 0.3))
			draw_rect(rail, Color("#4f565e"))
			InkRef.bevel(self, rail, 1.5, Color(1, 1, 1, 0.3), Color(0, 0, 0, 0.45))
			var screw := InkRef.tex("screw_silver")
			if screw != null:
				for sx in [8.0, r.size.x * 0.5, r.size.x - 8.0]:
					draw_texture_rect(screw, Rect2(Vector2(sx - 4.0, yy + 1.0), Vector2(8, 8)), false)
		var card := Rect2(Vector2(28, maxf(14.0, (r.size.y - 92.0) * 0.5)), Vector2(300, 92))
		notice_card(self, card, notice)

	## A white index card pinned at its head: a heading, a line under it and a count, printed navy.
	static func notice_card(ci: CanvasItem, card: Rect2, n: Dictionary) -> void:
		InkRef.cast_shadow(ci, card, 4.0, 0.5, 3)
		NineRef.paint(ci, InkRef.tex("people_card_white"), card.grow(10.0 / 1.875), (76.0 + 10.0) * 2.0 / 1.875)
		var navy := InkRef.NAVY
		var heading := str(n.get("heading", ""))
		var f: Font = InkRef.STAMP_FONT
		ci.draw_string(f, Vector2(card.position.x + 16, card.position.y + 34), heading, HORIZONTAL_ALIGNMENT_LEFT, card.size.x - 32, 26, navy)
		var line := str(n.get("line", ""))
		if line != "":
			var lf: Font = InkRef.BODY_SEMI
			var lines := InkRef.wrap(lf, line, card.size.x - 32, 14, 2)
			InkRef.print_lines(ci, lf, lines, card.position.x + 16, card.position.y + 42, card.size.x - 32, 14, 17.0, navy)
		var count := str(n.get("count", ""))
		if count != "":
			var cf: Font = InkRef.LABEL_FONT
			var cw := cf.get_string_size(count, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			ci.draw_string(cf, Vector2(card.end.x - 16 - cw, card.position.y + 32), count, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, navy)
		InkRef.pin(ci, Vector2(card.get_center().x, card.position.y + 6.0), "people_pin_yellow")


## The red threads of the drawing pointed at, drawn over every drawing, with a pin at each end.
class Threads extends Control:
	const InkRef := preload("res://scripts/research_ds2/ink.gd")
	var board: Control

	func _init() -> void:
		name = "Threads"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	func _draw() -> void:
		if board == null:
			return
		var title: String = board.call("hovered_title")
		if title == "":
			return
		var from: Control = board.call("card_for", title)
		if from == null:
			return
		var a: Vector2 = from.position + from.call("pin_point")
		var tied: Array = board.call("ties", title)
		for t: String in tied:
			var to: Control = board.call("card_for", t)
			if to == null:
				continue
			InkRef.thread(self, a, to.position + to.call("pin_point"))
		if not tied.is_empty():
			for t: String in tied:
				var to: Control = board.call("card_for", t)
				if to != null:
					InkRef.pin(self, to.position + to.call("pin_point"), "people_pin_red", 1.5)
			InkRef.pin(self, a, "people_pin_red", 1.5)
