extends VBoxContainer
## DS2 market, Prices: the quote board as one row per good (owner, decision 4), a module each in the ledger's
## language, under sortable headings (click one to sort by it, again to turn the order round):
##   the good in its well and its name, the trend arrow and a word under the name (the way the price is heading,
##     red when it goes against the player's own trade, green when with it: MParts.trend_tone);
##   Buy and Sell on LED screens after a printed £, the raw market prices (decision 6), Sell being what a sale
##     is paid this turn (MarketRules.sale_price);
##   Sold, the units sold to the market last turn;
##   Your cost and Profit on LED screens lit green, amber or red (decision 5, MarketRules.cost_tone and
##     profit_tone), blank for a good you don't make;
##   Impact, the price's current impact, underlined, its hover card the good's impact ladder (decision 7).
## A row opens its slip under it (decision 10, slip.gd): the chart recorder, the impact ladder and the good's
## keys (Buy, Sell, Move, Build more). Over the board, the search on a screen and three filter keys (You
## produce, Profitable, Unprofitable). Every figure is MarketRules.board_row's.

signal sell_requested(good_id: String)

const MarketRules := preload("res://scripts/market_rules.gd")
const MParts := preload("res://scripts/market_ds2/parts.gd")
const Parts := preload("res://scripts/tvp_v3/buildings_parts.gd")
const LedgerV3 := preload("res://scripts/ledger_v3/ledger_v3.gd")
const Metrics := preload("res://scripts/ds2/metrics.gd")
const LatchKey := preload("res://scripts/ds2/latch_key.gd")
const DotCard := preload("res://scripts/ds2/dot_card.gd")
const Nine := preload("res://scripts/bdp_v3_nine.gd")
const Slip := preload("res://scripts/market_ds2/slip.gd")

## The gap between a good's well and its name, and between every other column (the Resources panel's spacing).
const COL_GAP := 4
const VALUE_GAP := 20
const NAME_W := 122.0
const SOLD_W := 56.0
const IMPACT_W := 64.0
## The well and the name sit together at COL_GAP; the columns after them are VALUE_GAP apart.
const LEAD_COLUMNS := 2
## The columns, left to right: key, heading, width (0: a money screen's), sortable.
const COLUMNS := [
	["well", "", float(Metrics.GOOD_ICON), false],
	["name", "Good", NAME_W, true],
	["buy", "Buy", 0.0, true],
	["sell", "Sell", 0.0, true],
	["sold", "Sold", SOLD_W, true],
	["cost", "Your cost", 0.0, true],
	["profit", "Profit", 0.0, true],
	["impact", "Impact", IMPACT_W, true],
]
const FILTERS := [["produce", "You produce"], ["profitable", "Profitable"], ["unprofitable", "Unprofitable"]]
const WORDS := {1: "Rising", -1: "Falling", 0: "Steady"}

var _search := ""
var _filters := {"produce": false, "profitable": false, "unprofitable": false}
var _filter_keys: Dictionary = {}
var _sort_key := "name"
var _ascending := true
var _cells: Dictionary = {}
var _marks: Dictionary = {}
var _scroll: ScrollContainer
var _rows: VBoxContainer
var _open := ""
var _slip: Control = null
var _row_models: Array = []


func _init() -> void:
	add_theme_constant_override("separation", 10)
	var bar := HBoxContainer.new()
	bar.name = "PricesToolbar"
	bar.add_theme_constant_override("separation", 12)
	var screen: Control = LedgerV3._search_screen(func(t: String) -> void:
		_search = t.strip_edges().to_lower()
		render())
	(screen.get_meta("edit") as LineEdit).placeholder_text = "Search goods"
	bar.add_child(screen)
	bar.add_child(_filter_bed())
	add_child(bar)
	var heads := _heading_row()
	add_child(heads)
	var t := LedgerV3.table()
	_scroll = t.scroll
	_scroll.name = "PricesScroll"
	_rows = t.rows
	add_child(_scroll)


static func money_w() -> float:
	return MParts.money_width(MParts.MONEY_CELLS)


static func column_width(col: Array) -> float:
	return float(col[2]) if float(col[2]) > 0.0 else money_w()


func _filter_bed() -> PanelContainer:
	var bed := PanelContainer.new()
	bed.name = "FilterBed"
	var pad := StyleBoxEmpty.new()
	pad.set_content_margin_all(8)
	bed.add_theme_stylebox_override("panel", pad)
	bed.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	bed.draw.connect(func() -> void:
		Nine.paint(bed, LedgerV3.KEYBED, Rect2(Vector2.ZERO, bed.size).grow(LedgerV3.KEYBED_MARGIN / LedgerV3.LAYOUT),
			(LedgerV3.KEYBED_MARGIN + LedgerV3.KEYBED_CORNER) * LedgerV3.TEXELS))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	bed.add_child(line)
	for spec: Array in FILTERS:
		var id := str(spec[0])
		var key: Control = LatchKey.new()
		key.name = "Filter_%s" % id
		key.set("text", str(spec[1]))
		key.custom_minimum_size.x = 118.0
		key.connect("pressed", func() -> void: set_filter(id, not bool(_filters[id])))
		line.add_child(key)
		_filter_keys[id] = key
	return bed


## A filter on or off. Profitable and Unprofitable exclude each other.
func set_filter(id: String, on: bool) -> void:
	_filters[id] = on
	if on and id == "profitable":
		_filters["unprofitable"] = false
	elif on and id == "unprofitable":
		_filters["profitable"] = false
	for k in _filter_keys:
		_filter_keys[k].set("latched", bool(_filters[k]))
	render()


func set_search(text: String) -> void:
	_search = text.strip_edges().to_lower()
	render()


func _heading_row() -> MarginContainer:
	var wrap := MarginContainer.new()
	wrap.name = "PricesHeadings"
	var left := roundi(Parts.case_margin() + Parts.PAD.x)
	wrap.add_theme_constant_override("margin_left", left)
	wrap.add_theme_constant_override("margin_right", left)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", VALUE_GAP)
	wrap.add_child(row)
	var lead := _lead_box(row)
	for i in COLUMNS.size():
		var col: Array = COLUMNS[i]
		var key := str(col[0])
		var cell := HBoxContainer.new()
		cell.name = "Head_%s" % key
		cell.custom_minimum_size.x = column_width(col)
		cell.alignment = BoxContainer.ALIGNMENT_CENTER
		cell.add_theme_constant_override("separation", 4)
		var l := Parts.caption(str(col[1]), Parts.CAPTION_PX, HORIZONTAL_ALIGNMENT_CENTER)
		cell.add_child(l)
		var mark: Control = LedgerV3.SortMark.new()
		mark.visible = false
		cell.add_child(mark)
		_cells[key] = l
		_marks[key] = mark
		if bool(col[3]):
			cell.mouse_filter = Control.MOUSE_FILTER_STOP
			cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			cell.gui_input.connect(func(e: InputEvent) -> void:
				var mb := e as InputEventMouseButton
				if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
					sort_by(key))
		(lead if i < LEAD_COLUMNS else row).add_child(cell)
	return wrap


## The box that keeps the well and the name together at COL_GAP inside a line spaced at VALUE_GAP.
static func _lead_box(line: HBoxContainer) -> HBoxContainer:
	var lead := HBoxContainer.new()
	lead.name = "Lead"
	lead.add_theme_constant_override("separation", COL_GAP)
	lead.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(lead)
	return lead


## Sorts by a column; the same column again turns the order round.
func sort_by(key: String) -> void:
	if key == _sort_key:
		_ascending = not _ascending
	else:
		_sort_key = key
		_ascending = key == "name"
	render()


## Re-reads every row from MarketRules and redraws the board.
func refresh() -> void:
	_row_models = []
	for g: Dictionary in MatchState.visible_goods():
		_row_models.append(MarketRules.board_row(str(g.get("id", ""))))
	render()


func shown_rows() -> Array:
	var out: Array = _row_models.filter(_passes)
	out.sort_custom(_compare)
	return out


func _passes(r: Dictionary) -> bool:
	if _search != "" and not str(r.name).to_lower().contains(_search):
		return false
	if bool(_filters.produce) and not bool(r.made):
		return false
	if bool(_filters.profitable) and not (bool(r.made) and float(r.profit) > 0.0):
		return false
	if bool(_filters.unprofitable) and not (bool(r.made) and float(r.profit) < 0.0):
		return false
	return true


func _sort_value(r: Dictionary) -> Variant:
	match _sort_key:
		"name":
			return str(r.name).to_lower()
		"cost":
			return float(r.cost) if bool(r.made) else INF
		"profit":
			return float(r.profit) if bool(r.made) else -INF
		"impact":
			return float(r.impact)
	return float(r.get(_sort_key, 0.0))


func _compare(a: Dictionary, b: Dictionary) -> bool:
	var va: Variant = _sort_value(a)
	var vb: Variant = _sort_value(b)
	if va == vb:
		return str(a.name) < str(b.name)
	return va < vb if _ascending else va > vb


func render() -> void:
	if _rows == null:
		return
	LedgerV3.show_sort(_cells, _marks, _sort_key, _ascending)
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	_slip = null
	for r: Dictionary in shown_rows():
		_rows.add_child(_row(r))
		if str(r.good_id) == _open:
			_slip = Slip.new(str(r.good_id))
			_slip.connect("sell_requested", func(gid: String) -> void: sell_requested.emit(gid))
			_rows.add_child(_slip)


## Opens (or closes) a good's slip under its row.
func toggle_slip(gid: String) -> void:
	_open = "" if _open == gid else gid
	render()


func open_slip() -> Control:
	return _slip


func row_for(gid: String) -> Control:
	return _rows.get_node_or_null("MarketRow_%s" % gid) if _rows != null else null


func _row(r: Dictionary) -> PanelContainer:
	var gid := str(r.good_id)
	var m := Parts.module("MarketRow_%s" % gid)
	m.custom_minimum_size.y = Metrics.CARD_H
	m.mouse_filter = Control.MOUSE_FILTER_STOP
	Parts.on_click(m, func() -> void: toggle_slip(gid))
	m.set_meta("good_id", gid)
	var line := Parts.row_of(m)
	line.add_theme_constant_override("separation", VALUE_GAP)
	var lead := _lead_box(line)
	for i in COLUMNS.size():
		var col: Array = COLUMNS[i]
		(lead if i < LEAD_COLUMNS else line).add_child(_cell(str(col[0]), column_width(col), r))
	return m


func _cell(key: String, w: float, r: Dictionary) -> Control:
	match key:
		"well":
			return LedgerV3._boxed(Parts.good_in_well(str(r.good_id), -1, str(r.name), true, Metrics.GOOD_ICON), w)
		"name":
			return _name_cell(r, w)
		"buy":
			return _money_cell("Buy", float(r.buy), DS.PALETTE["TEXT"], w)
		"sell":
			return _money_cell("Sell", float(r.sell), DS.PALETTE["TEXT"], w)
		"sold":
			var l := Parts.body(str(int(r.sold)))
			l.name = "Sold"
			l.custom_minimum_size.x = w
			l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			l.autowrap_mode = TextServer.AUTOWRAP_OFF
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			l.tooltip_text = "Sold to the market last turn: %d. Bought: %d." % [int(r.sold), int(r.bought)]
			l.mouse_filter = Control.MOUSE_FILTER_PASS
			return l
		"cost":
			if not bool(r.made):
				return Parts.spacer(w, 0)
			return _money_cell("Cost", float(r.cost), MParts.tone_colour(str(r.cost_tone)), w)
		"profit":
			if not bool(r.made):
				return Parts.spacer(w, 0)
			return _money_cell("Profit", float(r.profit), MParts.tone_colour(str(r.profit_tone)), w)
		"impact":
			return impact_cell(r, w)
	return Parts.spacer(w, 0)


func _money_cell(cell_name: String, value: float, colour: Color, w: float) -> Control:
	var box := LedgerV3._boxed(MParts.money(value, colour), w)
	box.name = cell_name
	return box


## The name (semibold) over the trend arrow and a word for the way the price is heading.
func _name_cell(r: Dictionary, w: float) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.name = "NameCell"
	col.custom_minimum_size.x = w
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name := Parts.body(str(r.name))
	name.name = "Name"
	name.add_theme_font_override("font", Parts.FONT_TITLE)
	name.custom_minimum_size.x = w
	col.add_child(name)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", Parts.LAMP_GAP)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var arrow: Control = MParts.TrendArrow.new()
	var tone := MParts.trend_tone(int(r.dir), float((r.trend as Dictionary).get("avg", 0.0)))
	arrow.call("set_trend", int(r.dir), MParts.tone_colour(tone))
	arrow.set_meta("tone", tone)
	line.add_child(arrow)
	var word := Parts.body(str(WORDS.get(int(r.dir), "")))
	word.name = "Heading"
	word.autowrap_mode = TextServer.AUTOWRAP_OFF
	word.custom_minimum_size.x = 0
	line.add_child(word)
	col.add_child(line)
	return col


## The current impact, underlined; its hover card is the good's impact ladder.
func impact_cell(r: Dictionary, w: float) -> Control:
	var host: PanelContainer = DotCard.TipPanel.new()
	host.name = "Impact"
	host.custom_minimum_size.x = w
	host.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	host.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	host.mouse_filter = Control.MOUSE_FILTER_PASS
	var l := Parts.body(MParts.impact_text(float(r.impact)))
	l.name = "Figure"
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.custom_minimum_size.x = w
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.draw.connect(func() -> void:
		var font := l.get_theme_font("font")
		var fs := l.get_theme_font_size("font_size")
		var tw := font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var x0 := (l.size.x - tw) * 0.5
		var y := (l.size.y + font.get_ascent(fs) - font.get_descent(fs)) * 0.5 + 2.0
		l.draw_line(Vector2(x0, y), Vector2(x0 + tw, y), Color(DS.PALETTE["TEXT"], 0.85), 1.0))
	host.add_child(l)
	DotCard.attach(host, MParts.ladder_card(str(r.good_id)))
	return host


## The hovers the capture tool shows: the impact card of the first row, and the open slip's chart hovered.
func capture_views() -> Array:
	var views: Array = []
	views.append({"name": "prices_impact_card", "show": func() -> void:
		var shown := shown_rows()
		if shown.is_empty():
			return
		var row := row_for(str(shown[0].good_id))
		var host := row.find_child("Impact", true, false) as Control if row != null else null
		if host == null:
			return
		var card: Control = DotCard.make(host.get("tip"), host)
		card.name = "CaptureCard"
		add_child(card)
		card.top_level = true
		card.global_position = host.global_position + Vector2(-260, host.size.y + 4)
		card.size = card.get_combined_minimum_size(),
		"hide": func() -> void:
			var c := find_child("CaptureCard", false, false)
			if c != null:
				c.queue_free()})
	views.append({"name": "prices_slip_chart_hover", "show": func() -> void:
		var gid := "g_001"
		if _open != gid:
			toggle_slip(gid)
		await get_tree().process_frame
		await get_tree().process_frame
		if _slip != null:
			_scroll.ensure_control_visible(_slip)
			_slip.call("hover_sample", -3),
		"hide": func() -> void:
			if _open != "":
				toggle_slip(_open)})
	return views
