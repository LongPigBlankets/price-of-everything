extends Control
## The Research panel in DS2: the drawing office's plan chest, a tall steel cabinet of shallow drawers, one per
## research category, down the panel's left side. Presentation only: the shell (research_ds2.gd) sets each
## drawer's figures and listens for `drawer_pressed`.
##
## A drawer front is blackened steel (the kit's dark plate, cropped), with a brass label holder carrying a cream
## card printed with the category, a brass bar pull, and on its right a small dot matrix screen of the
## category's count granted over three rank lamps (green: the rank all granted; amber: open; off: closed).
## The open drawer stands slid out to the right, lit, its shadow cast back onto the cabinet. While the board
## shows a search, the drawers holding matches light up with their count of matches and the rest dim.
## The drawers are Buttons: click one, or move between them with the arrow keys and press Enter.

signal drawer_pressed(category: String)

const Ink := preload("res://scripts/research_ds2/ink.gd")

## The carcass's sides and top, the gap between drawers, and how far the open drawer stands out.
const SIDE := 10.0
const CAP := 12.0
const PLINTH := 16.0
const GAP := 4.0
const SLIDE := 16.0
const MIN_DRAWER_H := 28.0
const MAX_DRAWER_H := 62.0

var _drawers: Array = []


func _init() -> void:
	name = "PlanChest"
	mouse_filter = Control.MOUSE_FILTER_PASS
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	resized.connect(_lay_out)


## One drawer per category, top to bottom.
func build(categories: Array) -> void:
	for d in _drawers:
		remove_child(d)
		d.queue_free()
	_drawers.clear()
	for i in categories.size():
		var d := Drawer.new()
		d.category = str(categories[i])
		d.name = "Drawer_%d" % i
		d.set_meta("category", d.category)
		d.index = i
		d.pressed.connect(func() -> void: drawer_pressed.emit(d.category))
		add_child(d)
		_drawers.append(d)
	_lay_out()


func drawers() -> Array:
	return _drawers


func drawer_for(category: String) -> Control:
	for d in _drawers:
		if d.category == category:
			return d
	return null


## Sets every drawer from `figures`: category -> {granted, total, ranks: [state x3], open, matches (-1 none), lit, dim}.
func set_figures(figures: Dictionary) -> void:
	for d: Drawer in _drawers:
		var f: Dictionary = figures.get(d.category, {})
		d.granted = int(f.get("granted", 0))
		d.total = int(f.get("total", 0))
		d.ranks = f.get("ranks", ["off", "off", "off"])
		d.open = bool(f.get("open", false))
		d.matches = int(f.get("matches", -1))
		d.lit = bool(f.get("lit", false))
		d.dim = bool(f.get("dim", false))
		d.refresh()
	_lay_out()


func _lay_out() -> void:
	if _drawers.is_empty():
		return
	var n := float(_drawers.size())
	var room := size.y - CAP - PLINTH
	var h := clampf((room - GAP * (n - 1.0)) / n, MIN_DRAWER_H, MAX_DRAWER_H)
	var used := h * n + GAP * (n - 1.0)
	var top := CAP + maxf(0.0, (room - used) * 0.5)
	var w := size.x - SIDE * 2.0 - SLIDE
	for i in _drawers.size():
		var d: Drawer = _drawers[i]
		d.position = Vector2(SIDE + (SLIDE if d.open else 0.0), top + float(i) * (h + GAP))
		d.size = Vector2(w, h)
	queue_redraw()


## The carcass: a cabinet of the same blackened steel, a lip at its top, a plinth at its foot, and the dark
## openings the drawers sit in.
func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size - Vector2(SLIDE, 0))
	Ink.cast_shadow(self, r, 5.0, 0.5, 4)
	var plate := Ink.tex("dark_plate")
	if plate != null:
		var src := Rect2(Vector2(40, 40), r.size * 2.0)
		src.size = src.size.min(plate.get_size() - Vector2(80, 80))
		draw_texture_rect_region(plate, r, src, Color(0.86, 0.88, 0.92))
	else:
		draw_rect(r, Color("#24282e"))
	Ink.bevel(self, r, 2.0, Color(1, 1, 1, 0.22), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(0, 0, r.size.x, CAP - 3.0), Color(0.62, 0.66, 0.72, 0.30))
	Ink.bevel(self, Rect2(0, 0, r.size.x, CAP - 3.0), 1.0, Color(1, 1, 1, 0.3), Color(0, 0, 0, 0.45))
	var plinth := Rect2(0, r.size.y - PLINTH + 3.0, r.size.x, PLINTH - 3.0)
	draw_rect(plinth, Color(0.05, 0.05, 0.06, 0.55))
	Ink.bevel(self, plinth, 1.0, Color(1, 1, 1, 0.16), Color(0, 0, 0, 0.5))
	for d: Drawer in _drawers:
		var slot := Rect2(Vector2(SIDE - 2.0, d.position.y - 2.0), Vector2(d.size.x + 4.0, d.size.y + 4.0))
		draw_rect(slot, Color(0.01, 0.012, 0.015, 0.92))
		if d.open:
			# The drawer's sides seen in its open mouth, and its shadow thrown back onto the cabinet face.
			draw_rect(Rect2(slot.position + Vector2(2, 2), Vector2(SLIDE + 2.0, slot.size.y - 4.0)), Color("#3a3f46"))
			draw_rect(Rect2(slot.position + Vector2(2, slot.size.y * 0.5), Vector2(SLIDE + 2.0, 1.0)), Color(0, 0, 0, 0.5))


## A drawer: its front, label holder, pull and readout, drawn; a real Button underneath.
class Drawer extends Button:
	const InkRef := preload("res://scripts/research_ds2/ink.gd")
	const DotRef := preload("res://scripts/ds2/dot_matrix.gd")

	var category := ""
	var index := 0
	var granted := 0
	var total := 0
	var ranks: Array = ["off", "off", "off"]
	var open := false
	var matches := -1
	var lit := false
	var dim := false
	var _count: Control

	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		for s in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			add_theme_stylebox_override(s, StyleBoxEmpty.new())
		_count = DotRef.new()
		_count.name = "Count"
		_count.set("pitch", 1.4)
		_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_count)
		resized.connect(_place)
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)

	func refresh() -> void:
		var text := "%d/%d" % [granted, total]
		var colour := Color.WHITE
		if matches >= 0:
			text = "%d FOUND" % matches if matches > 0 else "NONE"
			colour = Color("#ffd27a") if matches > 0 else Color(1, 1, 1, 0.8)
		_count.set("colour", colour)
		_count.set("text", text)
		var words := {"done": "all granted", "open": "open", "off": "closed"}
		var rank_words: Array = []
		for k in mini(3, ranks.size()):
			rank_words.append("Rank %s %s" % [["I", "II", "III"][k], str(words.get(str(ranks[k]), "closed"))])
		tooltip_text = "%s: %d of %d granted\n%s" % [category, granted, total, ". ".join(rank_words)]
		_place()
		queue_redraw()

	func _compact() -> bool:
		return size.y < 46.0

	func _readout_w() -> float:
		return 76.0

	func _place() -> void:
		if _count == null:
			return
		var w := _readout_w()
		var h := 20.0 if not _compact() else minf(20.0, size.y - 8.0)
		_count.size = Vector2(w, h)
		_count.position = Vector2(size.x - w - 8.0, 6.0 if not _compact() else (size.y - h) * 0.5)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if open:
			InkRef.cast_shadow(self, r, 6.0, 0.6, 2)
		var plate := InkRef.tex("dark_metal_plate")
		var tint := Color(0.9, 0.92, 0.96)
		if open:
			tint = Color(1.25, 1.2, 1.1)
		elif dim:
			tint = Color(0.5, 0.52, 0.56)
		elif lit or is_hovered():
			tint = Color(1.08, 1.08, 1.1)
		if plate != null:
			var ps := plate.get_size()
			var src := Rect2(Vector2(30, 30 + fmod(float(index) * 41.0, maxf(1.0, ps.y - 60.0 - size.y * 2.0))), size * 2.0)
			src.size = src.size.min(ps - Vector2(60, 60))
			draw_texture_rect_region(plate, r, src, tint)
		else:
			draw_rect(r, Color("#2b3037") * tint)
		InkRef.bevel(self, r, 2.0, Color(1, 1, 1, 0.24), Color(0, 0, 0, 0.55))
		var compact := _compact()
		# The label holder: a brass frame round a cream card, the category printed navy.
		var label_w := size.x - _readout_w() - 26.0
		var lh := clampf(size.y * 0.42, 18.0, 26.0)
		var holder := Rect2(10, 6.0 if not compact else (size.y - lh) * 0.5, label_w, lh)
		var brass := Color("#b48c3c") if not dim else Color("#6e5a33")
		draw_rect(holder.grow(2.0), brass)
		InkRef.bevel(self, holder.grow(2.0), 1.0, Color(1, 0.94, 0.7, 0.55), Color(0.2, 0.13, 0.03, 0.6))
		var card_col := Color("#f1e7cc") if not dim else Color("#8f8a7c")
		if open or (lit and matches > 0):
			card_col = Color("#fff4d6")
		draw_rect(holder, card_col)
		draw_rect(Rect2(holder.position, Vector2(holder.size.x, 1.5)), Color(0, 0, 0, 0.18))
		var font: Font = InkRef.LABEL_FONT
		var text := category.to_upper()
		var px := InkRef.fit(font, text, holder.size.x - 10.0, 16, 11, 1)
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var base := holder.position.y + (holder.size.y + font.get_ascent(px) - font.get_descent(px)) * 0.5
		draw_string(font, Vector2(holder.position.x + (holder.size.x - minf(tw, holder.size.x - 10.0)) * 0.5, base), text,
			HORIZONTAL_ALIGNMENT_LEFT, holder.size.x - 10.0, px, InkRef.NAVY)
		# The pull: a brass bar on two posts, under the label (or beside it on a shallow drawer).
		var pull_w := minf(64.0, label_w * 0.45)
		var pull := Rect2(Vector2(holder.get_center().x - pull_w * 0.5, holder.end.y + 7.0), Vector2(pull_w, 5.0))
		if not compact:
			draw_rect(Rect2(pull.position + InkRef.shadow_offset(2.5), pull.size), Color(0, 0, 0, 0.45))
			for px_post in [pull.position.x + 3.0, pull.end.x - 7.0]:
				draw_rect(Rect2(px_post, pull.position.y - 3.0, 4.0, 3.0), Color("#7a5d22"))
			draw_rect(pull, brass)
			draw_rect(Rect2(pull.position.x, pull.end.y - 1.5, pull.size.x, 1.5), Color(1, 0.94, 0.7, 0.6))
		# Three rank lamps under the count.
		if not compact:
			var lx := size.x - _readout_w() - 8.0 + 14.0
			for k in 3:
				_rank_lamp(Vector2(lx + float(k) * 24.0, size.y - 12.0), str(ranks[k]) if k < ranks.size() else "off")
		if has_focus():
			draw_rect(r.grow(-1.0), Color(InkRef.PICK_GLOW, 0.8), false, 1.5)
		if dim:
			draw_rect(r, Color(0, 0, 0, 0.25))

	## A small lamp: green when its rank is all granted, amber when open, dark when closed.
	func _rank_lamp(c: Vector2, state: String) -> void:
		var col := Color("#20252b")
		match state:
			"done":
				col = Color("#4fdc86")
			"open":
				col = Color("#ffa412")
		draw_circle(c + InkRef.shadow_offset(1.5), 5.0, Color(0, 0, 0, 0.5))
		draw_circle(c, 5.0, Color("#9aa1a8"))
		draw_circle(c, 3.6, col)
		if state != "off":
			draw_circle(c, 7.0, Color(col, 0.18))
			draw_circle(c + InkRef.LIGHT_FROM * 1.2, 1.2, Color(1, 1, 1, 0.7))
