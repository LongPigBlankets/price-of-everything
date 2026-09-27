extends PanelContainer
## The market's sell panel: sell one good from the tiles that hold or make it. Opened by a good's Sell key
## on the board (today's look and the DS2 look alike). It replaces the Sales tab's bulk sell form: bulk
## sell is this panel for one good.
##   a table of every tile that holds the good or makes it (MarketRules.sell_sources), a tick box each and
##     Select all over them;
##   the quantity: everything on each tile, everything but X on each tile, or only X from each tile;
##   One off (the default) or Recurring;
##   the preview, per tile and in total (MarketRules.sell_quote, the figures the sale pays);
##   a guarded Confirm sale key (scripts/ds2/guard_key.gd): the first click lifts its cover, the second
##     sells. One off sells now (MatchState.sell_all_to_market, the queue_sell path); Recurring sets up
##     the same sale every turn from the chosen tiles (MatchState.add_recurring_bulk_sell).
## The panel covers its host (the market panel) until closed. Its state (the good, the ticks, the mode, the
## quantity and One off or Recurring) is plain data, so tests drive it without clicking: open(),
## set_tile_selected(), set_all_selected(), set_mode(), set_qty(), set_recurring(), quote(), confirm().
## `ds2` switches its look to the DS2 skin (scripts/market_ds2/sell_skin.gd); its behaviour is one.

signal closed
signal sold(result: Dictionary)

const MarketRules := preload("res://scripts/market_rules.gd")
const GuardKey := preload("res://scripts/ds2/guard_key.gd")
const MODES := [
	[MarketRules.MODE_ALL, "All"],
	[MarketRules.MODE_ALL_BUT, "All but X"],
	[MarketRules.MODE_ONLY, "Only X"],
]
const COLUMNS := [
	["Place", 190.0], ["Held", 64.0], ["Made/turn", 84.0], ["Units", 64.0], ["Revenue", 92.0], ["Charges", 84.0], ["Net", 92.0],
]
const GUARD_PX := 44.0

var good_id := ""
var mode := MarketRules.MODE_ALL
var qty := 0
var recurring := false
var ds2 := false
## tile -> ticked
var selected: Dictionary = {}
var sources: Array = []
var _quote: Dictionary = {}

var _title: Label
var _mode_keys: Dictionary = {}
var _qty_edit: SpinBox
var _once_key: Button
var _recurring_key: Button
var _table: GridContainer
var _select_all: CheckBox
var _total: Label
var _note: Label
var _guard: Control
var _guard_label: Label
var _empty: Label
var _body: VBoxContainer
var _skin: RefCounted = null


func _init() -> void:
	name = "MarketSellPanel"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL


func _ready() -> void:
	if get_child_count() == 0:
		_build()


## Opens the panel on `gid`: every source ticked, everything from each, one off.
func open(gid: String) -> void:
	good_id = gid
	mode = MarketRules.MODE_ALL
	qty = 0
	recurring = false
	selected.clear()
	sources = MarketRules.sell_sources(good_id)
	for s: Dictionary in sources:
		selected[str(s.tile)] = true
	if get_child_count() == 0:
		_build()
	visible = true
	_sync_controls()
	refresh()


func close() -> void:
	if _guard != null:
		_guard.call("drop")
	visible = false
	closed.emit()


func selected_tiles() -> Array:
	var out: Array = []
	for s: Dictionary in sources:
		if bool(selected.get(str(s.tile), false)):
			out.append(str(s.tile))
	return out


func set_tile_selected(tile: String, on: bool) -> void:
	selected[tile] = on
	refresh()


func set_all_selected(on: bool) -> void:
	for s: Dictionary in sources:
		selected[str(s.tile)] = on
	refresh()


func set_mode(m: String) -> void:
	mode = m
	_sync_controls()
	refresh()


func set_qty(n: int) -> void:
	qty = maxi(0, n)
	if _qty_edit != null and int(_qty_edit.value) != qty:
		_qty_edit.set_value_no_signal(qty)
	refresh()


func set_recurring(on: bool) -> void:
	recurring = on
	_sync_controls()
	refresh()


## The preview for the panel's state, as the sale will pay it.
func quote() -> Dictionary:
	return MarketRules.sell_quote(good_id, selected_tiles(), mode, qty)


## Whether Confirm sale would do anything: a one off needs units to sell; a recurring sale needs a tile
## and, for Only X, an X.
func can_confirm() -> bool:
	if selected_tiles().is_empty():
		return false
	if recurring:
		return mode != MarketRules.MODE_ONLY or qty > 0
	return int((_quote.get("total", {}) as Dictionary).get("units", 0)) > 0


## Sells (one off) or sets up the recurring sale, as the preview said. Returns the sale's result
## ({total_qty, revenue, tiles}), or {recurring: true, params} for a recurring sale; {} when nothing to do.
func confirm() -> Dictionary:
	_quote = quote()
	if not can_confirm():
		return {}
	var params: Dictionary = _quote.params
	var result: Dictionary = {}
	var name_text := Catalog.get_display_name(good_id)
	if recurring:
		MatchState.add_recurring_bulk_sell(params)
		result = {"recurring": true, "params": params}
		MatchState.request_toast("Selling %s every turn from %d place%s" % [name_text, selected_tiles().size(),
			"" if selected_tiles().size() == 1 else "s"], "success")
	else:
		result = MatchState.sell_all_to_market(params)
		var units := int(result.get("total_qty", 0))
		var places := int(result.get("tiles", 0))
		if units > 0:
			MatchState.request_toast("Selling %d %s from %d place%s" % [units, name_text, places, "" if places == 1 else "s"], "success")
		else:
			MatchState.request_toast("Nothing to sell", "warning")
	sold.emit(result)
	sources = MarketRules.sell_sources(good_id)
	refresh()
	return result


## Re-reads the preview and redraws the table and the figures.
func refresh() -> void:
	if good_id == "":
		return
	_quote = quote()
	if _skin != null:
		_skin.call("refresh", self)
	else:
		_refresh_v2()


func figure(amount: float) -> String:
	return "£%.2f" % amount


# --- the look ----------------------------------------------------------------------------------

func _build() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_mode_keys.clear()
	if ds2:
		_skin = load("res://scripts/market_ds2/sell_skin.gd").new()
		_skin.call("build", self)
	else:
		_skin = null
		_build_v2()


## Switches the look (the market panel's switch); the state stays.
func set_ds2(on: bool) -> void:
	if on == ds2 and get_child_count() > 0:
		return
	ds2 = on
	_build()
	if visible:
		_sync_controls()
		refresh()


func _build_v2() -> void:
	add_theme_stylebox_override("panel", preload("res://scripts/pipe_frame.gd").dark_brown_stylebox(8.0))
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	add_child(margin)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	margin.add_child(_body)

	var head := HBoxContainer.new()
	_title = Label.new()
	_title.theme_type_variation = "Title"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close_btn := Button.new()
	close_btn.name = "CloseSell"
	close_btn.text = "Back"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(close)
	head.add_child(close_btn)
	_body.add_child(head)

	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 8)
	for spec: Array in MODES:
		var key := Button.new()
		key.name = "Mode_%s" % str(spec[0])
		key.text = str(spec[1])
		key.toggle_mode = true
		key.focus_mode = Control.FOCUS_NONE
		_latch_look(key)
		var m := str(spec[0])
		key.pressed.connect(func() -> void: set_mode(m))
		_mode_keys[m] = key
		modes.add_child(key)
	var x_label := Label.new()
	x_label.text = "X"
	modes.add_child(x_label)
	_qty_edit = SpinBox.new()
	_qty_edit.name = "SellQty"
	_qty_edit.min_value = 0
	_qty_edit.max_value = 1000000
	_qty_edit.step = 1
	_qty_edit.custom_minimum_size.x = 110
	_qty_edit.value_changed.connect(func(v: float) -> void:
		qty = int(v)
		refresh())
	modes.add_child(_qty_edit)
	var spring := Control.new()
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modes.add_child(spring)
	_once_key = _toggle_button("OneOff", "One off", func() -> void: set_recurring(false))
	_recurring_key = _toggle_button("Recurring", "Recurring", func() -> void: set_recurring(true))
	modes.add_child(_once_key)
	modes.add_child(_recurring_key)
	_body.add_child(modes)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_table = GridContainer.new()
	_table.name = "SellTable"
	_table.columns = COLUMNS.size() + 1
	_table.add_theme_constant_override("h_separation", 10)
	_table.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_table)
	_body.add_child(scroll)
	_empty = Label.new()
	_empty.theme_type_variation = "Body"
	_body.add_child(_empty)

	_total = Label.new()
	_total.name = "SellTotal"
	_total.theme_type_variation = "Body"
	_total.add_theme_font_size_override("font_size", 17)
	_body.add_child(_total)
	_note = Label.new()
	_note.theme_type_variation = "Body"
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_note)

	var confirm_row := HBoxContainer.new()
	confirm_row.add_theme_constant_override("separation", 12)
	confirm_row.alignment = BoxContainer.ALIGNMENT_END
	_guard_label = Label.new()
	_guard_label.theme_type_variation = "Body"
	_guard_label.add_theme_font_size_override("font_size", 17)
	confirm_row.add_child(_guard_label)
	_guard = GuardKey.new(GUARD_PX)
	_guard.name = "ConfirmSale"
	_guard.connect("pressed", func() -> void: confirm())
	var guard_box := MarginContainer.new()
	guard_box.add_theme_constant_override("margin_top", ceili(GuardKey.overhang(GUARD_PX)))
	guard_box.add_child(_guard)
	confirm_row.add_child(guard_box)
	_body.add_child(confirm_row)


func _toggle_button(node_name: String, text: String, fn: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	_latch_look(b)
	b.pressed.connect(fn)
	return b


## A chosen key reads as chosen: the cream accent with navy print, as the Good prices filters do.
func _latch_look(b: Button) -> void:
	var on := StyleBoxFlat.new()
	on.bg_color = DS.PALETTE["ACCENT"]
	on.set_corner_radius_all(6)
	on.set_content_margin_all(8)
	on.content_margin_left = 14
	on.content_margin_right = 14
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_color_override("font_pressed_color", Color("#0b2340"))
	b.add_theme_color_override("font_hover_pressed_color", Color("#0b2340"))


func _sync_controls() -> void:
	if _skin != null:
		_skin.call("sync", self)
		return
	for m in _mode_keys:
		(_mode_keys[m] as Button).set_pressed_no_signal(m == mode)
	if _qty_edit != null:
		_qty_edit.editable = mode != MarketRules.MODE_ALL
		_qty_edit.set_value_no_signal(qty)
	if _once_key != null:
		_once_key.set_pressed_no_signal(not recurring)
		_recurring_key.set_pressed_no_signal(recurring)


func _refresh_v2() -> void:
	if _table == null:
		return
	_title.text = "Sell %s" % Catalog.get_display_name(good_id)
	for c in _table.get_children():
		_table.remove_child(c)
		c.queue_free()
	_select_all = CheckBox.new()
	_select_all.name = "SelectAll"
	_select_all.text = "All"
	_select_all.focus_mode = Control.FOCUS_NONE
	_select_all.set_pressed_no_signal(not sources.is_empty() and selected_tiles().size() == sources.size())
	_select_all.toggled.connect(func(on: bool) -> void: set_all_selected(on))
	_table.add_child(_select_all)
	for col: Array in COLUMNS:
		_table.add_child(_cell(str(col[0]), float(col[1]), true))
	var by_tile: Dictionary = _quote.get("by_tile", {})
	for s: Dictionary in sources:
		var tile := str(s.tile)
		var tick := CheckBox.new()
		tick.name = "Tick_%s" % tile
		tick.focus_mode = Control.FOCUS_NONE
		tick.set_pressed_no_signal(bool(selected.get(tile, false)))
		tick.toggled.connect(func(on: bool) -> void: set_tile_selected(tile, on))
		_table.add_child(tick)
		var line: Dictionary = by_tile.get(tile, {})
		var units := int(line.get("units", 0))
		_table.add_child(_cell(str(s.name), float(COLUMNS[0][1]), false))
		_table.add_child(_cell(str(int(s.held)), float(COLUMNS[1][1]), false))
		_table.add_child(_cell(str(int(s.made)) if int(s.made) > 0 else "", float(COLUMNS[2][1]), false))
		var ticked := bool(selected.get(tile, false))
		_table.add_child(_cell(str(units) if ticked else "", float(COLUMNS[3][1]), false))
		_table.add_child(_cell(figure(float(line.revenue)) if ticked and units > 0 else "", float(COLUMNS[4][1]), false))
		var charges := _cell(figure(float(line.charges)) if ticked and units > 0 else "", float(COLUMNS[5][1]), false)
		if ticked and units > 0:
			charges.tooltip_text = "Port charge %s. The buyer pays the freight." % figure(float(line.port))
			charges.mouse_filter = Control.MOUSE_FILTER_PASS
		_table.add_child(charges)
		_table.add_child(_cell(figure(float(line.net)) if ticked and units > 0 else "", float(COLUMNS[6][1]), false))
	_empty.visible = sources.is_empty()
	_empty.text = "You hold no %s and make none." % Catalog.get_display_name(good_id)
	var total: Dictionary = _quote.get("total", {})
	_total.text = "Total: %d units, revenue %s, charges %s, net %s" % [int(total.get("units", 0)),
		figure(float(total.get("revenue", 0.0))), figure(float(total.get("charges", 0.0))), figure(float(total.get("net", 0.0)))]
	_note.text = note_text()
	_guard_label.text = "Confirm recurring sale" if recurring else "Confirm sale"
	_guard.set("disabled", not can_confirm())


## One line on when the money comes and what repeats.
func note_text() -> String:
	var total: Dictionary = _quote.get("total", {})
	var unit := float(_quote.get("unit_price", 0.0))
	if recurring:
		return "Sells every turn from the ticked places at that turn's price. The figures are this turn's, at %s a unit." % figure(unit)
	var turns := int(total.get("turns", 0))
	if int(total.get("units", 0)) <= 0:
		return "Nothing to sell from the ticked places."
	if turns <= 0:
		return "Sold at %s a unit and paid now." % figure(unit)
	if LoanState.transit_credit_available() and LoanState.transit_credit_enabled:
		return "Sold at %s a unit. The transit credit line pays now, the goods reach the port in %d turn%s." % [
			figure(unit), turns, "" if turns == 1 else "s"]
	return "Sold at %s a unit. Paid when the goods reach the port, in up to %d turn%s." % [figure(unit), turns, "" if turns == 1 else "s"]


func _cell(text: String, w: float, heading: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = w
	l.theme_type_variation = "Caption" if heading else "Body"
	l.add_theme_color_override("font_color", DS.PALETTE["TEXT"])
	l.clip_text = true
	return l
