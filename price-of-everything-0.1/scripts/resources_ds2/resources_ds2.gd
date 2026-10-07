extends VBoxContainer
## The Resources panel in DS2 (docs/resources-ds2-plan.md), the Building Ledger's sibling: built into the
## Resources panel (scripts/resource_panel.gd). Every figure comes from scripts/goods_figures.gd; nothing here
## adds up.
##
## The shell is the ledger's: Building Detail's backing, the raised title with the Goods Graph and Close
## keys, the count on a dot display beside the search screen, latching filter keys on the key bed, the
## rubber seam, metal headings that sort, and one plastic case of raised modules, a good a module:
##   the good in its well with what is stored on the pill; its name; what was produced, used and sold last
##   turn, what is stored and what is in transit (blank when none); what a unit costs to make and what the
##   market pays, on LED screens; and, once the levy is in force, the carbon tax a unit pays.
## Pressing a module opens the good's costs under it: what last turn charged to move it, to store it and
## in intermediary fees, each as a total and a unit, then the freight a unit pays a tile by mode and level
## and the port's charge.

const Figures := preload("res://scripts/goods_figures.gd")
const LedgerV3 := preload("res://scripts/ledger_v3/ledger_v3.gd")
const Parts := preload("res://scripts/ds2/parts.gd")
const Metrics := preload("res://scripts/ds2/metrics.gd")
const MoneyFigure := preload("res://scripts/ds2/money_figure.gd")
const DotMatrix := preload("res://scripts/ds2/dot_matrix.gd")
const LatchKey := preload("res://scripts/ds2/latch_key.gd")
const Nine := preload("res://scripts/bdp_v3_nine.gd")
const Title := preload("res://scripts/bdp_v3_title.gd")
const Key := preload("res://scripts/bdp_v3_key.gd")
const BuildingStatus := preload("res://scripts/building_status.gd")
const Middleman := preload("res://scripts/middleman_service.gd")

## The panel's width for every state, a row open or not (owner: start at 1080 and work down).
const WIDTH := 1080.0
const HEIGHT := 760.0
const COL_GAP := 8
## A money screen's cells (the owner's five cell rule), and the widths of the columns round it.
const MONEY_DIGITS := 5
const WELL_W := 76.0
const MONEY_W := 104.0
## The count columns: wider until the Carbon tax column joins the table.
const COUNT_W := 84.0
const COUNT_W_TAXED := 72.0
const COUNT_KEYS := ["produced", "used", "sold", "stored", "transit"]
const LABELS := {"name": "Good", "produced": "Produced", "used": "Used", "sold": "Sold", "stored": "Stored",
	"transit": "In transit", "cost": "Cost/unit", "market": "Market", "carbon": "Carbon tax"}
## The filter keys: a good shows when it passes every key that is down. None down shows every good.
const FILTERS := [["stored", "In stock"], ["produced", "Produced"], ["used", "Used"], ["sold", "Sold"], ["transit", "In transit"]]
const COST_LABELS := {"transport": "Transport", "storage": "Storage", "intermediary": "Intermediary fee"}
const COST_UNITS := {"transport": "%s moved", "storage": "%s held", "intermediary": "%s bought or sold"}

var on_close := Callable()
var on_drag := Callable()

var _rows: Array = []
var _filters := {}
var _search_text := ""
var _sort_key := "name"
var _sort_asc := true
var _open := {}
var _taxed := false
var _count: Control = null
var _body: VBoxContainer = null
var _scroll: ScrollContainer = null
var _keys := {}
var _head_holder: Control = null
var _head_cells := {}
var _head_marks := {}


func _ready() -> void:
	name = "ResourcesDs2"
	add_theme_constant_override("separation", 12)
	for spec: Array in FILTERS:
		_filters[str(spec[0])] = false
	add_child(_title_row())
	add_child(_toolbar())
	add_child(_filter_bed())
	add_child(LedgerV3.seam())
	_head_holder = MarginContainer.new()
	_head_holder.name = "ResourceHeadings"
	add_child(_head_holder)
	var t := LedgerV3.table()
	(t.scroll as Control).name = "ResourceScroll"
	add_child(t.scroll)
	_scroll = t.scroll
	_body = t.rows
	_scroll.get_v_scroll_bar().visibility_changed.connect(_align_headings)
	_scroll.get_v_scroll_bar().resized.connect(_align_headings)
	refresh()


# --- the shell ---------------------------------------------------------------------------------

func _title_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "ResourceTitleRow"
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_MOVE
	row.gui_input.connect(func(e: InputEvent) -> void:
		if on_drag.is_valid():
			on_drag.call(e))
	var title: Control = Title.new()
	title.call("set_text", "Resources")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(title)
	var graph := Parts.key_button("Goods Graph", "GoodsGraphKey", 0.8)
	graph.size_flags_horizontal = Control.SIZE_SHRINK_END
	graph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	graph.custom_minimum_size.x = 150.0
	graph.tooltip_text = "Open the goods production web (G)"
	graph.pressed.connect(func() -> void: MatchState.goods_graph_requested.emit())
	row.add_child(graph)
	var close: TextureButton = Key.make("close", Title.line_height())
	close.name = "CloseKey"
	close.pressed.connect(func() -> void:
		if on_close.is_valid():
			on_close.call())
	row.add_child(close)
	return row


func _toolbar() -> HBoxContainer:
	var bar := LedgerV3.toolbar(func(t: String) -> void:
		_search_text = t.strip_edges().to_lower()
		_render())
	(bar.row as Control).name = "ResourceToolbar"
	(bar.search as LineEdit).placeholder_text = "Search a good"
	_count = bar.count
	return bar.row


func _filter_bed() -> Control:
	var bed := PanelContainer.new()
	bed.name = "FilterBed"
	var pad := StyleBoxEmpty.new()
	pad.content_margin_left = 10
	pad.content_margin_right = 10
	pad.content_margin_top = 10
	pad.content_margin_bottom = 12
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
		key.connect("pressed", func() -> void: set_filter(id, not bool(_filters[id])))
		_keys[id] = key
		line.add_child(key)
	return bed


## The columns for the table as it stands: the Carbon tax column only once the levy is in force.
func columns() -> Array:
	var count_w := COUNT_W_TAXED if _taxed else COUNT_W
	var cols: Array = [{"key": "well", "w": WELL_W, "sort": false}, {"key": "name", "w": 0.0, "sort": true}]
	for key: String in COUNT_KEYS:
		cols.append({"key": key, "w": count_w, "sort": true})
	cols.append({"key": "cost", "w": MONEY_W, "sort": true})
	cols.append({"key": "market", "w": MONEY_W, "sort": true})
	if _taxed:
		cols.append({"key": "carbon", "w": MONEY_W, "sort": true})
	return cols


func _build_headings() -> void:
	for c in _head_holder.get_children():
		_head_holder.remove_child(c)
		c.queue_free()
	_head_cells.clear()
	_head_marks.clear()
	_align_headings()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", COL_GAP)
	_head_holder.add_child(row)
	for col: Dictionary in columns():
		var key := str(col.key)
		var cell := HBoxContainer.new()
		cell.name = "Head_%s" % key
		cell.custom_minimum_size.x = float(col.w)
		cell.alignment = BoxContainer.ALIGNMENT_BEGIN if key == "name" else BoxContainer.ALIGNMENT_CENTER
		if key == "name":
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 5)
		var l := Parts.caption(str(LABELS.get(key, "")), Parts.CAPTION_PX, HORIZONTAL_ALIGNMENT_CENTER)
		cell.add_child(l)
		var mark := LedgerV3.SortMark.new()
		mark.visible = false
		cell.add_child(mark)
		_head_cells[key] = l
		_head_marks[key] = mark
		if bool(col.sort):
			cell.mouse_filter = Control.MOUSE_FILTER_STOP
			cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			cell.gui_input.connect(func(e: InputEvent) -> void:
				var mb := e as InputEventMouseButton
				if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
					sort_by(key))
		row.add_child(cell)


## The headings stand over the modules' columns: inset as the case and a module are, and clear of the
## scroll rail while it shows.
func _align_headings() -> void:
	if _head_holder == null or _scroll == null:
		return
	var inset := roundi(Parts.case_margin() + Parts.PAD.x)
	var bar := _scroll.get_v_scroll_bar()
	_head_holder.add_theme_constant_override("margin_left", inset)
	_head_holder.add_theme_constant_override("margin_right", inset + (roundi(bar.size.x) if bar.visible else 0))


# --- state -------------------------------------------------------------------------------------

## Read the figures again and draw the table.
func refresh() -> void:
	_rows = Figures.rows()
	var taxed := Figures.carbon_in_force()
	if taxed != _taxed or _head_cells.is_empty():
		_taxed = taxed
		if _sort_key == "carbon" and not _taxed:
			_sort_key = "name"
			_sort_asc = true
		_build_headings()
	_render()


func set_filter(id: String, on: bool) -> void:
	if not _filters.has(id):
		return
	_filters[id] = on
	(_keys[id] as Control).set("latched", on)
	_render()


## Sort by a column: a second press turns the order round. Names run A to Z first, figures largest first.
func sort_by(key: String) -> void:
	if key == _sort_key:
		_sort_asc = not _sort_asc
	else:
		_sort_key = key
		_sort_asc = key == "name"
	_render()


func toggle_good(good_id: String) -> void:
	_open[good_id] = not bool(_open.get(good_id, false))
	_render()


## The goods the filters and the search leave, in the sorted order.
func shown_rows() -> Array:
	var shown: Array = _rows.filter(func(r: Dictionary) -> bool:
		for id in _filters:
			if bool(_filters[id]) and int(r.get(id, 0)) <= 0:
				return false
		return _search_text == "" or str(r.name).to_lower().contains(_search_text))
	shown.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if _sort_key != "name":
			var av := float(a.get(_sort_key, 0.0))
			var bv := float(b.get(_sort_key, 0.0))
			if not is_equal_approx(av, bv):
				return av < bv if _sort_asc else av > bv
			return str(a.name).naturalnocasecmp_to(str(b.name)) < 0
		var c := str(a.name).naturalnocasecmp_to(str(b.name))
		return c < 0 if _sort_asc else c > 0)
	return shown


func _render() -> void:
	if _body == null:
		return
	# Detached before freed, so the old rows never show beside the new for a frame.
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	var shown := shown_rows()
	for r: Dictionary in shown:
		_body.add_child(_row(r))
		if bool(_open.get(str(r.good_id), false)):
			_body.add_child(_detail(r))
	if _count != null:
		_count.set("text", count_text(shown.size(), _rows.size()))
	LedgerV3.show_sort(_head_cells, _head_marks, _sort_key, _sort_asc)


static func count_text(shown: int, total: int) -> String:
	if shown == total:
		return "%d GOOD%s" % [total, "" if total == 1 else "S"]
	return "%d/%d SHOWN" % [shown, total]


# --- a good's module ---------------------------------------------------------------------------

func _row(r: Dictionary) -> PanelContainer:
	var gid := str(r.good_id)
	var m := Parts.module("ResourceRow_%s" % gid)
	m.custom_minimum_size.y = Metrics.CARD_H
	m.mouse_filter = Control.MOUSE_FILTER_STOP
	m.tooltip_text = "Show what %s costs to move and store" % str(r.name).to_lower()
	Parts.on_click(m, func() -> void: toggle_good(gid))
	var line := Parts.row_of(m)
	line.add_theme_constant_override("separation", COL_GAP)
	for col: Dictionary in columns():
		line.add_child(_cell(str(col.key), float(col.w), r))
	return m


func _cell(key: String, w: float, r: Dictionary) -> Control:
	match key:
		"well":
			var box := CenterContainer.new()
			box.custom_minimum_size.x = w
			box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(Parts.good_in_well(str(r.good_id), int(r.stored), ""))
			return box
		"name":
			var l := Parts.body(str(r.name))
			l.name = "Name"
			l.add_theme_font_override("font", Parts.FONT_TITLE)
			l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			return l
		"cost":
			if float(r.cost) < 0.0:
				return Parts.spacer(w, 0)
			return _money_cell("Cost", float(r.cost), BuildingStatus.cost_rag_color(float(r.cost), float(r.market)), w)
		"market":
			return _money_cell("Market", float(r.market), DS.PALETTE["TEXT"], w)
		"carbon":
			if float(r.carbon) <= 0.0:
				return Parts.spacer(w, 0)
			return _money_cell("Carbon", float(r.carbon), BuildingStatus.STATUS_RED, w)
	var units := int(r.get(key, 0))
	var figure := Parts.body(thousands(units) if units > 0 else "")
	figure.name = "Count_%s" % key
	figure.autowrap_mode = TextServer.AUTOWRAP_OFF
	figure.custom_minimum_size.x = w
	figure.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	figure.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	figure.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return figure


## A money figure on its screen, by the owner's display rule, centred in a column `w` wide.
static func _money_cell(cell_name: String, value: float, colour: Color, w: float, max_decimals := 2) -> Control:
	var box := CenterContainer.new()
	box.name = cell_name
	box.custom_minimum_size.x = w
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fig: Dictionary = MoneyFigure.screen(value, max_decimals)
	box.add_child(Parts.money(str(fig.figure), colour, MONEY_DIGITS, str(fig.suffix)))
	return box


# --- a good opened: its costs ------------------------------------------------------------------

func _detail(r: Dictionary) -> PanelContainer:
	var gid := str(r.good_id)
	var m := Parts.module("ResourceDetail_%s" % gid)
	var line := Parts.row_of(m)
	line.add_child(Parts.spacer(WELL_W, 0))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(col)
	col.add_child(_costs_grid(gid))
	col.add_child(_freight_block(gid))
	return m


## What last turn charged on the good: a line a kind, its total and what a unit paid.
func _costs_grid(good_id: String) -> GridContainer:
	var costs: Dictionary = Figures.costs(good_id)
	var grid := GridContainer.new()
	grid.name = "Costs"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 6)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for head: String in ["", "Last turn", "Per unit", ""]:
		grid.add_child(Parts.caption(head, Parts.CAPTION_PX, HORIZONTAL_ALIGNMENT_CENTER))
	for kind: String in Figures.COST_KINDS:
		if kind == "intermediary" and not Middleman.active():
			continue
		var c: Dictionary = costs[kind]
		var label := Parts.caption(str(COST_LABELS[kind]))
		label.custom_minimum_size.x = 150.0
		grid.add_child(label)
		grid.add_child(_money_cell("Total_%s" % kind, float(c.total), BuildingStatus.STATUS_RED, MONEY_W))
		grid.add_child(_money_cell("Unit_%s" % kind, float(c.per_unit), BuildingStatus.STATUS_RED, MONEY_W, 3))
		var words := Parts.body(str(COST_UNITS[kind]) % units_text(int(c.units)) if int(c.units) > 0 else "None last turn.")
		words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(words)
	return grid


## What a unit pays to travel a tile, by mode and level, and what a port takes.
func _freight_block(good_id: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "Freight"
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(Parts.caption("Freight a unit a tile"))
	var rates: Array = Figures.freight_rates(good_id)
	if rates.is_empty():
		box.add_child(Parts.body("No built infrastructure carries this good."))
	else:
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 18)
		grid.add_theme_constant_override("v_separation", 4)
		grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for head: String in ["", "Level 1", "Level 2", "Level 3"]:
			grid.add_child(Parts.caption(head, Parts.CAPTION_PX, HORIZONTAL_ALIGNMENT_CENTER))
		for rate: Dictionary in rates:
			var label := Parts.caption(str(rate.label))
			label.custom_minimum_size.x = 150.0
			grid.add_child(label)
			for v: float in rate.levels:
				grid.add_child(_money_cell("Rate", v, DS.PALETTE["TEXT"], MONEY_W, 3))
		box.add_child(grid)
	var port: Dictionary = Figures.port_charge(good_id)
	var port_line := Parts.body("A port takes %s a unit shipped, %s%% of its market price." % [
"£" + str(MoneyFigure.screen(float(port.get("cost", 0.0)), 3).figure), ("%.1f" % (float(port.get("rate", 0.0)) * 100.0)).trim_suffix(".0")])
	port_line.name = "PortLine"
	box.add_child(port_line)
	return box


static func units_text(units: int) -> String:
	return "%s unit%s" % [thousands(units), "" if units == 1 else "s"]


static func thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return ("-" if n < 0 else "") + out
