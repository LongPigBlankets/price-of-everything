extends Control
## Tile view v3, the Stock tab: the warehouse's fill as a level bar on an LED screen's glass, drawn as
## Building Detail's value bars are (scripts/bdp_v3_value_bar.gd). Each stored good is a lit slice in one
## tone's shades (green, amber from 90%, red when full); the dark glass beyond is the room left.
## Over the bar the biggest goods each have their icon on a small cream tile, the rest share one "+N" tile.
## A tile that sits over its own slice drops a short line to it, as the value bar's do. Tiles that had to
## spread along the row to fit (the usual case while the fill is low and its slices narrow) stand side by
## side on one shelf instead, and the shelf's two legs come down on the ends of the stretch of fill they
## name, so no line fans out across the bar. A dashed mark stands at last turn's peak when it was above
## what is stored now, PEAK printed on the glass beside it (or, with no room left there, a tag right over
## it). Under the bar a scale of brackets says what the capacity is made of: the warehouse's level, the
## storage a building adds (the port's 600) and any modifier. Pointing at a good in the bay, or at its tile
## or slice here, lights its slice and its tile and names it under the bar, in the scale's place; picking
## a tile or a slice asks for that good's Move or sell sheet (`picked`), and picking the "+N" tile asks for
## every good in the bay (`more_picked`).

signal picked(good_id: String)
## The "+N" tile was picked: the goods it stands for are in the bay, behind its wide key.
signal more_picked
## The good under the pointer here, "" when it leaves one, so the bay can light that good's cell.
signal pointed(good_id: String)

const Nine := preload("res://scripts/bdp_v3_nine.gd")
const Light := preload("res://scripts/bdp_v3_light.gd")
const Plate := preload("res://scripts/bdp_v3_plate.gd")
const GoodIcons := preload("res://scripts/good_icons.gd")
const UIHelpers := preload("res://scripts/ui_helpers.gd")
const SCREEN: Texture2D = preload("res://assets/ui/bdp_v3/mini_screen.png")
const GLASS: Texture2D = preload("res://assets/ui/bdp_v3/mini_screen_glass.png")
const CAPTURE_SCALE := 1.875
## From layout.json (mini_screen), in layout pixels: the screen's shadow room, bezel and pane radius.
const SCREEN_MARGIN := 8.0
const SCREEN_RIM := 7.0
const SCREEN_RADIUS := 5.0
## In logical pixels: the fill's height inside the bezel; a tag's tile (the value bar's ICON_PX), the room
## between the tags and the bar that their lines run through, and the least room between two tags; the
## sliver over the bar when nothing is tagged, the room under it for the scale (or the good pointed at),
## and the print (the owner's caption size).
const BAR_H := 20.0
const ICON_PX := 32.0
const ICON_GAP := 12.0
const ICON_SPACING := 4.0
const NO_TAG_ROOM := 3.0
const SCALE_ROOM := 28.0
const LABEL_PX := 15
const TAG_PX := 15
## At most this many tags over the bar: the biggest goods, the last one standing for the rest when more
## goods are stored than that.
const MAX_TAGS := 6
## Tags moved further than this from their slices to fit stand on a shelf rather than each drop a line.
const DIRECT_SLACK := 8.0
## The shelf's drop below the tiles, and PEAK's room from its mark on the glass.
const SHELF_DROP := 4.0
const PEAK_PAD := 5.0
## The peak is marked only when it stood this far (a share of the capacity) above what is stored now;
## nearer, the fill's own end is the peak.
const PEAK_APART := 0.02
const NAVY := Color("#0b2340")
const INK := Color(1, 1, 1, 0.42)
const SHADES := {
	"ok": [Color("#3fb265"), Color("#2e8f4f"), Color("#5fcf85"), Color("#23713d")],
	"warn": [Color("#e0a030"), Color("#c4861c"), Color("#f0bd58"), Color("#a86e10")],
	"bad": [Color("#d64a3a"), Color("#b03026"), Color("#e46a5a"), Color("#8e231b")],
}

## [{good_id, name, qty, from, to, colour}], most first, from and to as shares of the capacity.
var slices: Array = []
## [{label, short, from, to, tip}]
var parts: Array = []
var used := 0
var capacity := 0
var peak := 0
## The good whose slice is lit and named, "" for none.
var hot := ""
var _layer: Control
var _glass: Control
var _tile := StyleBoxFlat.new()
var _ring := StyleBoxFlat.new()
var _icons := {}
var _pointed := ""


func _init() -> void:
	name = "StockGauge"
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = Vector2(0.0, NO_TAG_ROOM + _frame_h() + SCALE_ROOM)
	# A good's tile, as the value bar draws it; and the ring round the one pointed at.
	_tile.bg_color = UIHelpers.PILL_PAPER
	_tile.set_corner_radius_all(6)
	_tile.shadow_color = Color(0, 0, 0, 0.45)
	_tile.shadow_size = 3
	_tile.shadow_offset = Vector2(1.5, 1.5)
	_ring.draw_center = false
	_ring.set_corner_radius_all(8)
	_ring.set_border_width_all(2)
	_ring.border_color = DS.PALETTE.TEXT
	_layer = Control.new()
	_layer.name = "Fill"
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.material = Light.emissive_material()
	_layer.draw.connect(_draw_fill)
	add_child(_layer)
	_glass = Control.new()
	_glass.name = "Glass"
	_glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glass.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glass.draw.connect(func() -> void:
		Nine.paint(_glass, GLASS, _bar().grow(SCREEN_MARGIN / CAPTURE_SCALE), _corner()))
	add_child(_glass)


## `goods` as TileViewData.stockpile_summary gives them (most first), what is stored and the capacity,
## last turn's peak, the capacity's parts ([{label, short, units, tip}] in order) and the fill's tone.
func set_fill(goods: Array, used_units: int, cap: int, peak_units: int, cap_parts: Array, tone: String) -> void:
	used = used_units
	capacity = maxi(cap, 1)
	peak = peak_units
	var shades: Array = SHADES.get(tone, SHADES.ok)
	slices.clear()
	var at := 0.0
	for i in goods.size():
		var g: Dictionary = goods[i]
		var share := float(g.qty) / float(capacity)
		if share <= 0.0:
			continue
		slices.append({"good_id": str(g.good_id), "name": str(g.display_name), "qty": int(g.qty), "from": at,
			"to": minf(1.0, at + share), "colour": shades[slices.size() % shades.size()]})
		at = minf(1.0, at + share)
	parts.clear()
	at = 0.0
	for p: Dictionary in cap_parts:
		var share := float(p.units) / float(capacity)
		if share <= 0.0:
			continue
		parts.append({"label": str(p.label), "short": str(p.short), "from": at, "to": minf(1.0, at + share), "tip": str(p.tip)})
		at += share
	_fit_height()
	_redraw()
	_glass.queue_redraw()


## The height the bar needs: whether a tag row stands over it can hang on its width (PEAK goes on the glass
## only when there is room there), so this runs again whenever the width changes.
func _fit_height() -> void:
	var h := _top() + _frame_h() + SCALE_ROOM
	if not is_equal_approx(custom_minimum_size.y, h):
		custom_minimum_size.y = h


## Lights one good's slice and tile and names it under the bar ("" puts it back).
func set_hot(good_id: String) -> void:
	if hot == good_id:
		return
	hot = good_id
	_redraw()


## Whether last turn's peak gets its own mark (it stood clear of what is stored now).
func peak_marked() -> bool:
	return peak > 0 and capacity > 0 and float(peak - used) / float(capacity) >= PEAK_APART


## Whether PEAK is printed on the glass beside its mark (there is room right of it); else it is a tag over
## the mark.
func peak_on_glass() -> bool:
	return peak_marked() and _pane_right() - _x(_peak_share()) >= _peak_w() + PEAK_PAD * 2.0


## The tags over the bar, left to right: {kind ("good", "more" or "peak"), at (its centre), w, target (the
## x on the bar it names), shelf (the shelf it stands on in `shelves()`, -1 when it drops its own line),
## and for a good its good_id, name and qty; for "more" the goods it stands for}.
func tags() -> Array:
	return _layout().tags


## The shelves tags stand on, each {x0, x1 (the ends of the stretch of fill its tags name, where its legs
## come down), row0, row1 (the ends of its row of tiles), first, last (its tags' indexes)}.
func shelves() -> Array:
	return _layout().shelves


func _layout() -> Dictionary:
	var lo := _pane_left()
	var hi := _pane_right()
	var out: Array = []
	var peak_tag := {}
	if peak_marked() and not peak_on_glass():
		# No room on the glass: PEAK is a tag right over its mark, and the goods keep to its left.
		var pw := _peak_w() + 6.0
		var mx := _x(_peak_share())
		var at := clampf(mx, lo + pw * 0.5, hi - pw * 0.5)
		peak_tag = {"kind": "peak", "w": pw, "target": mx, "at": at, "shelf": -1}
		hi = at - pw * 0.5 - ICON_SPACING
	var fit := maxi(1, floori((hi - lo + ICON_SPACING) / (ICON_PX + ICON_SPACING)))
	var most := mini(MAX_TAGS, fit)
	var named := slices.size() if slices.size() <= most else most - 1
	for i in named:
		var s: Dictionary = slices[i]
		out.append({"kind": "good", "good_id": s.good_id, "name": s.name, "qty": s.qty, "w": ICON_PX, "shelf": -1,
			"from": float(s.from), "to": float(s.to), "target": _x((float(s.from) + float(s.to)) * 0.5)})
	if named < slices.size():
		var rest: Array = slices.slice(named)
		var a := float(rest[0].from)
		var b := float(rest[rest.size() - 1].to)
		out.append({"kind": "more", "goods": rest, "w": ICON_PX, "shelf": -1, "from": a, "to": b, "target": _x((a + b) * 0.5)})
	# Spread them so no two overlap, kept over the bar (the value bar's icon_centres, for mixed widths).
	var xs: Array = []
	for t: Dictionary in out:
		xs.append(float(t.target))
	for _pass in 8:
		for i in range(1, xs.size()):
			var gap := (float(out[i - 1].w) + float(out[i].w)) * 0.5 + ICON_SPACING
			xs[i] = maxf(float(xs[i]), float(xs[i - 1]) + gap)
		if not xs.is_empty():
			xs[-1] = minf(float(xs[-1]), hi - float(out[-1].w) * 0.5)
		for i in range(xs.size() - 2, -1, -1):
			var gap := (float(out[i].w) + float(out[i + 1].w)) * 0.5 + ICON_SPACING
			xs[i] = minf(float(xs[i]), float(xs[i + 1]) - gap)
		if not xs.is_empty():
			xs[0] = maxf(float(xs[0]), lo + float(out[0].w) * 0.5)
	for i in out.size():
		out[i].at = xs[i]
	# A run of tiles pushed shoulder to shoulder, any of them well off its slice, stands on one shelf.
	var shelf_list: Array = []
	var first := 0
	while first < out.size():
		var last := first
		while last + 1 < out.size() and float(out[last + 1].at) - float(out[last].at) \
				<= (float(out[last].w) + float(out[last + 1].w)) * 0.5 + ICON_SPACING + 0.5:
			last += 1
		var worst := 0.0
		for k in range(first, last + 1):
			worst = maxf(worst, absf(float(out[k].at) - float(out[k].target)))
		if last > first and worst > DIRECT_SLACK:
			shelf_list.append({"x0": _x(float(out[first].from)), "x1": _x(float(out[last].to)),
				"row0": float(out[first].at) - float(out[first].w) * 0.5, "row1": float(out[last].at) + float(out[last].w) * 0.5,
				"first": first, "last": last})
			for k in range(first, last + 1):
				out[k].shelf = shelf_list.size() - 1
		first = last + 1
	if not peak_tag.is_empty():
		out.append(peak_tag)
	return {"tags": out, "shelves": shelf_list}


func _redraw() -> void:
	queue_redraw()
	_layer.queue_redraw()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_RESIZED:
			_fit_height()
			_redraw()
			_glass.queue_redraw()
		NOTIFICATION_MOUSE_EXIT:
			_point("")


func _gui_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null:
		var gid := _good_at(motion.position)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if gid != "" or _on_more(motion.position) else Control.CURSOR_ARROW
		_point(gid)
		return
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		var gid := _good_at(click.position)
		if gid != "":
			accept_event()
			picked.emit(gid)
		elif _on_more(click.position):
			accept_event()
			more_picked.emit()


func _point(gid: String) -> void:
	if gid == _pointed:
		return
	_pointed = gid
	set_hot(gid)
	pointed.emit(gid)


## The good whose tile or slice is at `at`, "" for none.
func _good_at(at: Vector2) -> String:
	for t: Dictionary in tags():
		if str(t.kind) == "good" and _tag_rect(t).grow(2.0).has_point(at):
			return str(t.good_id)
	if _pane().grow(2.0).has_point(at):
		for s: Dictionary in slices:
			if at.x >= _x(float(s.from)) - 0.5 and at.x <= _x(float(s.to)) + 0.5:
				return str(s.good_id)
	return ""


## Whether `at` is on the "+N" tile.
func _on_more(at: Vector2) -> bool:
	for t: Dictionary in tags():
		if str(t.kind) == "more" and _tag_rect(t).grow(2.0).has_point(at):
			return true
	return false


func _frame_h() -> float:
	return BAR_H + 2.0 * _inset()


## The bezel's width round the pane.
func _inset() -> float:
	return SCREEN_RIM / CAPTURE_SCALE + 2.0


## The room over the bar: the tags' row when anything is stored or PEAK needs a tag, else a sliver.
func _top() -> float:
	return ICON_PX + ICON_GAP if (not slices.is_empty() or (peak_marked() and not peak_on_glass())) else NO_TAG_ROOM


func _bar() -> Rect2:
	return Rect2(0.0, _top(), size.x, _frame_h())


## The pane the fill runs in, inside the bezel.
func _pane() -> Rect2:
	return _bar().grow(-_inset())


func _pane_left() -> float:
	return _inset()


func _pane_right() -> float:
	return size.x - _inset()


func _corner() -> float:
	return (SCREEN_MARGIN + SCREEN_RIM + SCREEN_RADIUS + 2.0) * 2.0 / CAPTURE_SCALE


func _x(share: float) -> float:
	return _pane_left() + (_pane_right() - _pane_left()) * clampf(share, 0.0, 1.0)


func _peak_share() -> float:
	return float(peak) / float(capacity)


func _peak_w() -> float:
	return Plate.FONT_SEMI.get_string_size("PEAK", HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_PX).x


## Where PEAK is printed on the glass, right of its mark.
func _peak_label_rect() -> Rect2:
	var pane := _pane()
	return Rect2(_x(_peak_share()) + PEAK_PAD, pane.position.y, _peak_w(), pane.size.y)


func _hot_slice() -> Dictionary:
	if hot == "":
		return {}
	for s: Dictionary in slices:
		if str(s.good_id) == hot:
			return s
	return {}


func _icon(good_id: String) -> Texture2D:
	if not _icons.has(good_id):
		_icons[good_id] = GoodIcons.texture_for_size(good_id, Catalog.get_internal_name(good_id), ICON_PX)
	return _icons[good_id]


func _print(text: String, at: Vector2, px: int) -> void:
	var font: Font = Plate.FONT_SEMI
	draw_string(font, at + Vector2(1.0, 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(0, 0, 0, 0.8))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, DS.PALETTE.TEXT)


func _tag_rect(t: Dictionary) -> Rect2:
	return Rect2(float(t.at) - float(t.w) * 0.5, 0.0, float(t.w), ICON_PX)


func _draw() -> void:
	var bar := _bar()
	Nine.paint(self, SCREEN, bar.grow(SCREEN_MARGIN / CAPTURE_SCALE), _corner())
	var font: Font = Plate.FONT_SEMI
	var pane := _pane()
	var lay := _layout()
	var glass_y := pane.position.y - 2.0
	# The shelves: a rail under their tiles, reaching over the stretch of fill they name, and a leg down to
	# each end of that stretch.
	var rail_y := ICON_PX + SHELF_DROP
	for sh: Dictionary in lay.shelves:
		var a := minf(float(sh.row0) + 4.0, float(sh.x0))
		var b := maxf(float(sh.row1) - 4.0, float(sh.x1))
		draw_line(Vector2(a, rail_y), Vector2(b, rail_y), INK, 1.5, true)
		draw_line(Vector2(float(sh.x0), rail_y), Vector2(float(sh.x0), glass_y), INK, 1.0, true)
		if float(sh.x1) - float(sh.x0) >= 2.0:
			draw_line(Vector2(float(sh.x1), rail_y), Vector2(float(sh.x1), glass_y), INK, 1.0, true)
	# The tags, each on its shelf or joined to what it names by a short line.
	for t: Dictionary in lay.tags:
		var rect := _tag_rect(t)
		if str(t.kind) == "peak":
			var w := _peak_w()
			var base := ICON_PX * 0.5 + TAG_PX * 0.36
			_print("PEAK", Vector2(float(t.at) - w * 0.5, base), TAG_PX)
			draw_line(Vector2(float(t.target), base + 5.0), Vector2(float(t.target), glass_y), INK, 1.0, true)
			continue
		if int(t.shelf) < 0:
			draw_line(Vector2(float(t.at), ICON_PX + 1.0), Vector2(float(t.target), glass_y), INK, 1.0, true)
		_tile.draw(get_canvas_item(), rect.grow(-1.0))
		var lit := false
		if str(t.kind) == "good":
			var tex := _icon(str(t.good_id))
			if tex != null:
				draw_texture_rect(tex, rect.grow(-4.0), false)
			lit = str(t.good_id) == hot
		else:
			var more := "+%d" % (t.goods as Array).size()
			var mw := Plate.FONT_BOLD.get_string_size(more, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
			draw_string(Plate.FONT_BOLD, Vector2(rect.get_center().x - mw * 0.5, rect.get_center().y + Plate.FONT_BOLD.get_ascent(17) * 0.36),
				more, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, NAVY)
			for g: Dictionary in t.goods:
				lit = lit or str(g.good_id) == hot
		if lit:
			_ring.draw(get_canvas_item(), rect.grow(2.0))
	# Under it, the good pointed at, in the scale's place while it is lit: its name (its quantity is on its
	# pill in the bay, lit with it).
	var lit_slice := _hot_slice()
	if not lit_slice.is_empty():
		var text := str(lit_slice.name).to_upper()
		var x := (_x(float(lit_slice.from)) + _x(float(lit_slice.to))) * 0.5
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_PX).x
		var y := bar.end.y + 1.0
		draw_colored_polygon(PackedVector2Array([Vector2(x - 4.0, y + 5.0), Vector2(x + 4.0, y + 5.0), Vector2(x, y)]), DS.PALETTE.TEXT)
		_print(text, Vector2(clampf(x - w * 0.5, 0.0, size.x - w), y + 6.0 + font.get_ascent(TAG_PX)), TAG_PX)
		return
	# The scale: a bracket under each part of the capacity, its figure and name centred under it.
	var ink := Color(DS.PALETTE.TEXT, 0.75)
	var y0 := bar.end.y + 3.0
	for p: Dictionary in parts:
		var x0 := _x(float(p.from))
		var x1 := _x(float(p.to))
		draw_line(Vector2(x0, y0), Vector2(x0, y0 + 7.0), ink, 1.5, true)
		draw_line(Vector2(x1, y0), Vector2(x1, y0 + 7.0), ink, 1.5, true)
		draw_line(Vector2(x0, y0 + 4.0), Vector2(x1, y0 + 4.0), ink, 1.0, true)
		var room := x1 - x0 - 6.0
		var label := str(p.label)
		if font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_PX).x > room:
			label = str(p.short)
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_PX).x
		if w <= room + 6.0:
			_print(label, Vector2((x0 + x1 - w) * 0.5, y0 + 8.0 + font.get_ascent(LABEL_PX)), LABEL_PX)


func _draw_fill() -> void:
	var pane := _pane()
	for s: Dictionary in slices:
		var x0 := _x(float(s.from))
		var x1 := _x(float(s.to))
		var rect := Rect2(x0, pane.position.y, maxf(x1 - x0, 1.0), pane.size.y)
		var colour: Color = s.colour
		if hot != "":
			# The good pointed at stays lit; the rest sink towards the glass.
			colour = colour.lightened(0.18) if str(s.good_id) == hot else colour.darkened(0.55)
		_layer.draw_rect(rect, colour)
		# A little light along the top of each slice and shade along its foot, so it reads as lit.
		_layer.draw_rect(Rect2(rect.position, Vector2(rect.size.x, rect.size.y * 0.35)), Color(1, 1, 1, 0.12))
		_layer.draw_rect(Rect2(rect.position + Vector2(0.0, rect.size.y * 0.75), Vector2(rect.size.x, rect.size.y * 0.25)), Color(0, 0, 0, 0.18))
		if x0 > pane.position.x + 0.5:
			_layer.draw_line(Vector2(x0, rect.position.y), Vector2(x0, rect.end.y), Color(0, 0, 0, 0.55), 1.0)
	# Where each part of the capacity ends, a faint line up the glass.
	for p: Dictionary in parts:
		var x := _x(float(p.to))
		if x < pane.end.x - 1.0:
			_layer.draw_line(Vector2(x, pane.position.y), Vector2(x, pane.end.y), Color(1, 1, 1, 0.14), 1.0)
	if peak_marked():
		var mx := _x(_peak_share())
		var y := pane.position.y - 3.0
		while y < pane.end.y + 3.0:
			_layer.draw_line(Vector2(mx, y), Vector2(mx, minf(y + 2.5, pane.end.y + 3.0)), Color(1, 1, 1, 0.8), 1.5)
			y += 4.5
		if peak_on_glass():
			# PEAK lit on the glass beside its mark, as a gauge's printed limit.
			var at := _peak_label_rect()
			_layer.draw_string(Plate.FONT_SEMI, Vector2(at.position.x, at.get_center().y + TAG_PX * 0.36), "PEAK",
				HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_PX, DS.PALETTE.TEXT)


func _get_tooltip(at_position: Vector2) -> String:
	var pane := _pane()
	for t: Dictionary in tags():
		if not _tag_rect(t).grow(2.0).has_point(at_position):
			continue
		match str(t.kind):
			"good":
				return "%s: %d stored\nClick to move or sell" % [str(t.name), int(t.qty)]
			"more":
				var names := PackedStringArray()
				for g: Dictionary in t.goods:
					names.append("%s %d" % [str(g.name), int(g.qty)])
				return "%d more goods: %s\nClick to see them all in the bay" % [(t.goods as Array).size(), ", ".join(names)]
			"peak":
				return "Last turn's peak: %d of %d" % [peak, capacity]
	if peak_marked():
		var near_mark := absf(at_position.x - _x(_peak_share())) <= 4.0 and at_position.y <= pane.end.y + 3.0 \
			and at_position.y >= pane.position.y - 4.0
		if near_mark or (peak_on_glass() and _peak_label_rect().grow(2.0).has_point(at_position)):
			return "Last turn's peak: %d of %d" % [peak, capacity]
	if pane.grow(2.0).has_point(at_position):
		for s: Dictionary in slices:
			if at_position.x >= _x(float(s.from)) - 0.5 and at_position.x <= _x(float(s.to)) + 0.5:
				return "%s: %d stored\nClick to move or sell" % [str(s.name), int(s.qty)]
		return "Room for %d more" % maxi(0, capacity - used)
	if at_position.y > pane.end.y:
		for p: Dictionary in parts:
			if at_position.x >= _x(float(p.from)) and at_position.x <= _x(float(p.to)):
				return str(p.tip)
	return ""
