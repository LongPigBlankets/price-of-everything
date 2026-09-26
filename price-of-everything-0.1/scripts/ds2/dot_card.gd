extends RefCounted
## DS2: a hover card on a dot-matrix screen (the tile view's Transport keys, Building Detail's Upgrade key). What building or raising a link
## costs and what it brings, lit on a dot-matrix screen in the gunmetal bezel and glass of Building Detail's
## readouts, so it reads as a part of the cabinet and not a tooltip box:
##   ● UPGRADE TO LEVEL 2
##
##   COST      £150
##   CAPACITY  300 → 600 A TURN
##   REACH     2 → 3 TILES
##   TIME      3 TURNS
## Every line is the shared DotMatrix part (scripts/ds2/dot_matrix.gd), unframed, at a whole-pixel pitch so
## the lines stack without a fraction of a pixel between them, and every line is as many characters long
## as the longest, blanks lit faint, so the unlit cells run from edge to edge of the glass and the whole
## screen reads as one display, as the key bed's strip does. A line per fact, a word for its caption and
## a figure for its value, the captions in one column (the matrix is monospaced). The mark before the title
## is the lamp: amber while the job runs, red when the key would be refused or can't be paid for; a
## warning's own line lights in its colour, under the facts. The goods a build takes sit on the lines after
## the facts, each in its well with its quantity in a pill (the one shape a good's quantity takes), laid
## over the same cells.
##
## The card opens under the pointer, inside the tile view's body: it never reaches over the navy sheet's
## rim or past the panel (Drop places it once the tooltip is up).
##
## A card is a Dictionary: {title, tone ("", warn or bad: the mark; none when ""), rows: [{caption, value,
## tone}], notes: [{text, tone}], goods: {good id: qty}, goods_caption, goods_note}. The hosts keep theirs
## in `tip` and its words in plain text in tooltip_text, which the tooltip needs to show at all and which
## tests read.

const DotMatrix := preload("res://scripts/ds2/dot_matrix.gd")
const Nine := preload("res://scripts/bdp_v3_nine.gd")
const Well := preload("res://scripts/ds2/good_well.gd")
## The dots' pitch: a character seven dots tall is 14 px, the body text's size, and each line and cell is a
## whole number of pixels.
const PITCH := 2.0
## The room between the glass's edge and the dot cells (DotMatrix's own padding adds to it).
const PAD := Vector2(3.0, 4.0)
## The goods' icons, and the room kept round a well's frame inside its run of cells.
const GOOD_PX := preload("res://scripts/ds2/metrics.gd").GOOD_ICON
const WELL_ROOM := 4.0
## The lines a row of goods takes, and the one its words are on, the wells centred on it.
## (goods_lines(), goods_words_line(): as many as a well and its room take, the words on the middle one.)
const MARK := "●"
## Where the card opens: this far right of the pointer and below it, or this far above it when there is no
## room below; the room left round it in the tooltip's window for the bezel's shadow.
const NUDGE := 10.0
const DROP := 24.0
const ABOVE := 12.0
const SHADOW := 6
## The room kept between the card and the body's scrollbar rail.
const RAIL_GAP := 4.0


## The card for `tip`, placed inside the body of the panel `anchor` sits in.
static func make(tip: Dictionary, anchor: Control = null) -> Control:
	var host := Drop.new()
	host.anchor = anchor
	host.add_child(Card.new(tip))
	return host


## The same card in plain words, for tooltip_text: the title, then a line a fact.
static func plain(tip: Dictionary) -> String:
	var lines: Array[String] = [str(tip.get("title", ""))]
	for r: Dictionary in tip.get("rows", []):
		lines.append(("%s %s" % [str(r.get("caption", "")), str(r.get("value", ""))]).strip_edges())
	for n: Dictionary in tip.get("notes", []):
		lines.append(str(n.get("text", "")))
	var goods: Dictionary = tip.get("goods", {})
	if not goods.is_empty():
		var parts: Array[String] = []
		for gid in goods:
			parts.append("%s %s" % [Well.count(int(goods[gid])), Catalog.get_display_name(str(gid))])
		var note := str(tip.get("goods_note", ""))
		lines.append(("%s %s%s" % [str(tip.get("goods_caption", "Needs")), ", ".join(parts),
			(", " + note.to_lower()) if note != "" else ""]).strip_edges())
	return "\n".join(lines.filter(func(l: String) -> bool: return l != ""))


## Gives `host` (TipPanel, or a transport key) its card.
static func attach(host: Control, tip: Dictionary) -> void:
	host.set("tip", tip)
	host.tooltip_text = plain(tip)


## The screen's lines of words for `tip`, each a list of runs ({text, colour}): the title, then the facts and
## the notes. The goods' lines are laid out with the wells, between the facts and the notes (Board).
static func board_lines(tip: Dictionary) -> Array:
	var col := caption_chars(tip)
	var lines: Array = []
	var tone := str(tip.get("tone", ""))
	var title: Array = []
	if tone != "":
		title.append({"text": MARK + " ", "colour": tone_colour(tone)})
	title.append({"text": str(tip.get("title", "")), "colour": Color.WHITE})
	lines.append(title)
	for r: Dictionary in tip.get("rows", []):
		lines.append([{"text": str(r.get("caption", "")).rpad(col), "colour": Color.WHITE},
			{"text": str(r.get("value", "")), "colour": tone_colour(str(r.get("tone", "")))}])
	for n: Dictionary in tip.get("notes", []):
		lines.append([{"text": str(n.get("text", "")), "colour": tone_colour(str(n.get("tone", "")))}])
	return lines


## The caption column's width in characters: the longest caption and two spaces.
static func caption_chars(tip: Dictionary) -> int:
	var col := 0
	if not (tip.get("goods", {}) as Dictionary).is_empty():
		col = str(tip.get("goods_caption", "Needs")).length()
	for r: Dictionary in tip.get("rows", []):
		col = maxi(col, str(r.get("caption", "")).length())
	return col + 2


static func tone_colour(tone: String) -> Color:
	match tone:
		"bad": return DS.PALETTE["DANGER"]
		"warn": return DS.PALETTE["WARN"]
		"ok": return DS.PALETTE["OK"]
	return Color.WHITE


## The lines a row of goods takes: enough for a well, its frame and its room, at a line's height (seven dots
## and the unframed display's padding above and below).
static func goods_lines() -> int:
	var line_h := DotMatrix.ROWS * PITCH + 6.0
	return maxi(3, ceili((GOOD_PX + 2.0 * Well.reach() + 2.0 * WELL_ROOM) / line_h))


## The goods' line their words are on: the middle one.
static func goods_words_line() -> int:
	return goods_lines() / 2


## One character cell's width, a dot column of spacing included.
static func cell_width() -> float:
	return (DotMatrix.COLUMNS + 1) * PITCH


## The cells a well takes in a row of goods: its icon, its frame and a little room each side.
static func well_cells() -> int:
	return ceili((GOOD_PX + 2.0 * Well.reach() + 2.0 * WELL_ROOM) / cell_width())


## A line of the screen: `runs` then blank cells up to `chars` characters, left aligned, unframed.
static func dot_line(runs: Array, chars: int) -> Control:
	var d: Control = DotMatrix.new()
	d.set("pitch", PITCH)
	d.set("framed", false)
	d.set("align", HORIZONTAL_ALIGNMENT_LEFT)
	var n := 0
	for r: Dictionary in runs:
		n += str(r.text).length()
	var padded := runs.duplicate()
	if chars > n:
		padded.append({"text": " ".repeat(chars - n), "colour": Color.WHITE})
	d.call("set_runs", padded)
	return d


## Holds the card in the tooltip's window, clears the window's panel so only the bezel is drawn, and once
## the engine has put the tooltip up at the pointer, moves it inside the body the anchor sits in: under the
## pointer when there is room, above it when not, never past the body's edges.
class Drop extends MarginContainer:
	var anchor: Control = null

	func _init() -> void:
		name = "TransportTip"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		# The bezel's shadow reaches past the screen: room for it inside the window.
		for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
			add_theme_constant_override(side, SHADOW)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PARENTED:
			var win := get_parent() as Window
			if win != null:
				win.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		elif what == NOTIFICATION_READY:
			# The engine sets the window's place after adding it: move it once that is done.
			_place.call_deferred()

	## The card's place inside the body, as a rect in the viewport; empty when there is nothing to fit.
	func placed_rect() -> Rect2:
		var card := get_child(0) as Control if get_child_count() > 0 else null
		var win := get_parent() as Window
		if card == null or win == null:
			return Rect2()
		return Rect2(Vector2(win.position) + Vector2(SHADOW, SHADOW), card.get_combined_minimum_size())

	## The body's rect in the viewport (the tile view's BodyScroll, short of its scrollbar's rail while that
	## shows), or the viewport's own.
	func bounds() -> Rect2:
		var n: Node = anchor
		while n != null:
			if n is ScrollContainer and n.name == &"BodyScroll":
				var c := n as ScrollContainer
				var xf := c.get_global_transform_with_canvas()
				var r := Rect2(xf.origin, c.size * xf.get_scale())
				var bar := c.get_v_scroll_bar()
				if bar != null and bar.visible:
					r.size.x -= (bar.size.x + RAIL_GAP) * xf.get_scale().x
				return r
			n = n.get_parent()
		return anchor.get_viewport().get_visible_rect()

	func _place() -> void:
		var win := get_parent() as Window
		if win == null or anchor == null or not is_instance_valid(anchor) or not anchor.is_inside_tree():
			return
		# An embedded tooltip is placed in the viewport's own coordinates, as the pointer and the body are
		# (the project embeds its subwindows); a native one is left where the engine put it.
		if not win.is_embedded():
			return
		var card := get_child(0) as Control
		var s := card.get_combined_minimum_size()
		# The bezel's render reaches this far past the card: that stays inside too.
		var box := bounds().grow(-DotMatrix.MARGIN / DotMatrix.CAPTURE_SCALE)
		var mouse := anchor.get_viewport().get_mouse_position()
		var at := Vector2(mouse.x + NUDGE, mouse.y + DROP)
		if at.y + s.y > box.end.y:
			at.y = mouse.y - ABOVE - s.y
		at.x = clampf(at.x, box.position.x, maxf(box.position.x, box.end.x - s.x))
		at.y = clampf(at.y, box.position.y, maxf(box.position.y, box.end.y - s.y))
		win.position = Vector2i((at - Vector2(SHADOW, SHADOW)).round())


## The screen: the bezel and its dark pane, the board of dot lines, the glass over them.
class Card extends MarginContainer:
	var _glass: Control

	func _init(tip: Dictionary) -> void:
		name = "TransportCard"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var inset := DotMatrix.RIM / DotMatrix.CAPTURE_SCALE
		add_theme_constant_override("margin_left", roundi(inset + PAD.x))
		add_theme_constant_override("margin_right", roundi(inset + PAD.x))
		add_theme_constant_override("margin_top", roundi(inset + PAD.y))
		add_theme_constant_override("margin_bottom", roundi(inset + PAD.y))
		var board := Board.new()
		board.fill(tip)
		add_child(board)
		# The glass over everything, painted over the whole screen from the board's rect.
		_glass = Control.new()
		_glass.name = "Glass"
		_glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_glass.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_glass.draw.connect(func() -> void:
			Nine.paint(_glass, DotMatrix.GLASS, Rect2(-_glass.position, size).grow(DotMatrix.MARGIN / DotMatrix.CAPTURE_SCALE), _corner()))
		add_child(_glass)
		resized.connect(func() -> void:
			queue_redraw()
			_glass.queue_redraw())

	func _corner() -> float:
		return (DotMatrix.MARGIN + DotMatrix.RIM + DotMatrix.RADIUS + 2.0) * 2.0 / DotMatrix.CAPTURE_SCALE

	func _draw() -> void:
		var box := Rect2(Vector2.ZERO, size)
		Nine.paint(self, DotMatrix.SCREEN, box.grow(DotMatrix.MARGIN / DotMatrix.CAPTURE_SCALE), _corner())
		draw_rect(box.grow(-DotMatrix.RIM / DotMatrix.CAPTURE_SCALE), DotMatrix.PANE)


## The screen's lines, one under the next, every one as many characters long: the title, a blank line, the
## facts, the goods' lines with the wells on them, then the notes.
class Board extends VBoxContainer:
	var _texts: Array[String] = []

	func _init() -> void:
		name = "DotBoard"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_theme_constant_override("separation", 0)

	func fill(tip: Dictionary) -> void:
		var T: GDScript = load("res://scripts/ds2/dot_card.gd")
		var lines: Array = T.board_lines(tip)
		var goods: Dictionary = tip.get("goods", {})
		var col: int = T.caption_chars(tip)
		var span: int = T.well_cells()
		var note := str(tip.get("goods_note", ""))
		var goods_runs: Array = []
		if not goods.is_empty():
			goods_runs = [{"text": str(tip.get("goods_caption", "Needs")).rpad(col) + " ".repeat(goods.size() * span),
				"colour": Color.WHITE}]
			if note != "":
				goods_runs.append({"text": " " + note, "colour": Color.WHITE})
		var chars := _length(goods_runs)
		for runs: Array in lines:
			chars = maxi(chars, _length(runs))
		# The title, a blank line, the facts, the goods, then the notes (why it can't, what to mind).
		var facts := 1 + (tip.get("rows", []) as Array).size()
		for i in lines.size():
			if i == facts and not goods.is_empty():
				_add_goods(T, goods, goods_runs, chars, col, span)
			add_child(T.dot_line(lines[i], chars))
			_texts.append(_joined(lines[i]))
			if i == 0 and lines.size() > 1:
				add_child(T.dot_line([], chars))
		if facts >= lines.size() and not goods.is_empty():
			_add_goods(T, goods, goods_runs, chars, col, span)

	func _add_goods(T: GDScript, goods: Dictionary, runs: Array, chars: int, col: int, span: int) -> void:
		add_child(_goods(T, goods, runs, chars, col, span))
		_texts.append(_joined(runs))

	## The goods' lines: blank cells above and below, the caption and the note on the middle line, and the
	## wells laid over the cells from the values' column on, each centred in its run of cells.
	func _goods(T: GDScript, goods: Dictionary, runs: Array, chars: int, col: int, span: int) -> Control:
		var block := Control.new()
		block.name = "Goods"
		block.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var stack := VBoxContainer.new()
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_theme_constant_override("separation", 0)
		var line_size := Vector2.ZERO
		var pad := Vector2.ZERO
		var lines: int = T.goods_lines()
		var words_line: int = T.goods_words_line()
		for i in lines:
			var line: Control = T.dot_line(runs if i == words_line else [], chars)
			stack.add_child(line)
			line_size = line.custom_minimum_size
			pad = line.call("_padding")
		var line_h := line_size.y
		block.custom_minimum_size = Vector2(line_size.x, line_h * lines)
		stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		block.add_child(stack)
		var p := PITCH
		var cell: float = T.cell_width()
		var cy := line_h * (words_line + 0.5)
		var i := 0
		for gid in goods:
			var first := col + i * span
			var cx := pad.x + first * cell + (span * cell - p) * 0.5
			var icon := Well.make(str(gid), int(goods[gid]), "", GOOD_PX)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon.position = Vector2(cx, cy) - Vector2(GOOD_PX, GOOD_PX) * 0.5
			icon.size = Vector2(GOOD_PX, GOOD_PX)
			block.add_child(icon)
			i += 1
		return block

	static func _length(runs: Array) -> int:
		var n := 0
		for r: Dictionary in runs:
			n += str(r.text).length()
		return n

	static func _joined(runs: Array) -> String:
		var s := ""
		for r: Dictionary in runs:
			s += str(r.text)
		return s.strip_edges()

	## The text of line `i` (the blank ones left out), for tests and probes.
	func line_text(i: int) -> String:
		return _texts[i]

	func line_count() -> int:
		return _texts.size()


## A module that keeps a card in `tip` and shows it as its tooltip.
class TipPanel extends PanelContainer:
	var tip: Dictionary = {}

	func _make_custom_tooltip(_for_text: String) -> Object:
		return load("res://scripts/ds2/dot_card.gd").make(tip, self) if not tip.is_empty() else null
