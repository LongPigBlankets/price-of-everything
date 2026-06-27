extends PanelContainer

@onready var title_label: Label = $MarginContainer/VBoxContainer/HeaderRow/TitleLabel
@onready var close_button: Button = $MarginContainer/VBoxContainer/HeaderRow/CloseButton
@onready var content_vbox: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/ContentVBox
@onready var main_vbox: VBoxContainer = $MarginContainer/VBoxContainer
@onready var header_static: HBoxContainer = $MarginContainer/VBoxContainer/HeaderRowStatic
@onready var scroll: ScrollContainer = $MarginContainer/VBoxContainer/ScrollContainer

const MarketRowScene: PackedScene = preload("res://scenes/market_row.tscn")
const UIHelpers := preload("res://scripts/ui_helpers.gd")
const BuildingMarketTab := preload("res://scripts/building_market_panel.gd")  # NPC buildings-for-sale tab
const HEADER_HEIGHT := 40.0

var rows: Array = []
var _dragging := false
var _drag_offset := Vector2.ZERO
var _good_option: OptionButton = null
var _finished_check: CheckBox = null
var _recurring_check: CheckBox = null
var _keep_spin: SpinBox = null
var _ledger_refreshers: Array = []  # Callables that rebuild the Transactions/Movements tabs
# Buying now lives in the per-good "Purchase" flow on the world map (world_map.gd).

# Filter bar (Good prices tab): search + three exclusive-ish toggle filters.
var _search: LineEdit = null
var _filter_produce_btn: Button = null
var _filter_profit_btn: Button = null
var _filter_unprofit_btn: Button = null
var _filter_produce := false
var _filter_profitable := false
var _filter_unprofitable := false

func _ready() -> void:
	title_label.text = "Market"
	close_button.pressed.connect(hide)
	_build_content()
	_rebuild_header()
	_build_tabs()
	MarketState.prices_updated.connect(_on_prices_updated)
	MatchState.show_construct_for_good.connect(_on_show_construct_for_good)
	MatchState.transfer_for_good_requested.connect(func(_g: String) -> void: hide())
	MatchState.purchase_for_good_requested.connect(func(_g: String) -> void: hide())
	visibility_changed.connect(_on_panel_visibility_changed)
	Production.turn_processed.connect(_refresh_ledgers)
	Production.turn_processed.connect(func(_s: Dictionary = {}) -> void: _update_filter_availability())

func _rebuild_header() -> void:
	for c in header_static.get_children():
		header_static.remove_child(c)
		c.queue_free()
	header_static.add_theme_constant_override("separation", 10)
	header_static.add_child(_header_spacer(98.0))             # framed icon column
	header_static.add_child(_header_label("Product", 240.0, Color(0, 0, 0, 0), false))
	header_static.add_child(_header_label("Sale now", 70.0, SALE_TINT))
	header_static.add_child(_header_label("Sale +10t", 80.0, SALE_TINT))
	header_static.add_child(_header_label("Buy now", 70.0, BUY_TINT))
	header_static.add_child(_header_label("Buy +10t", 80.0, BUY_TINT))
	header_static.add_child(_header_label("Sold", 60.0))
	header_static.add_child(_header_label("Bought", 64.0))
	header_static.add_child(_header_label("Cost/unit", 100.0))
	header_static.add_child(_header_label("Profit/unit", 110.0))

const SALE_TINT := Color(0.82, 0.85, 0.90, 0.10)
const BUY_TINT := Color(0.50, 0.53, 0.58, 0.22)

func _header_label(text: String, width: float, tint: Color = Color(0, 0, 0, 0), center: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(width, 0)
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if tint.a > 0.0:
		var box := StyleBoxFlat.new()
		box.bg_color = tint
		box.content_margin_left = 6
		box.content_margin_right = 6
		l.add_theme_stylebox_override("normal", box)
	return l

func _header_spacer(width: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(width, 0)
	return c

func _on_show_construct_for_good(_good_id: String) -> void:
	hide()  # close the market panel; the construct panel opens itself filtered

func _centre_and_resize() -> void:
	# Wide enough to show every column without sideways scrolling, centred on
	# screen (capped to the viewport on narrow displays).
	var vp := get_viewport_rect().size
	var w := minf(1220.0, vp.x - 60.0)
	var base_h := minf(640.0, vp.y - 80.0)
	# 30% taller than the old (base_h + 40) panel, with ALL the extra height added
	# upward — the bottom edge stays put and the top grows up — so the rows get more room.
	var h := (base_h + 40.0) * 1.30
	var centred_top := maxf(40.0, (vp.y - base_h) / 2.0)
	var bottom := centred_top + base_h  # where the old panel's bottom sat — keep it fixed
	offset_left = maxf(0.0, (vp.x - w) / 2.0)
	offset_top = maxf(8.0, bottom - h)  # grow upward; clamp to the top of the screen
	offset_right = offset_left + w
	offset_bottom = bottom

func _on_panel_visibility_changed() -> void:
	if not visible:
		return
	_centre_and_resize()
	_refresh_ledgers()
	_update_filter_availability()
	# Fresh open: clear the stale "recurring" choice on the Sales tab.
	if _recurring_check != null:
		_recurring_check.set_pressed_no_signal(false)

func _build_tabs() -> void:
	# Two tabs: the price table ("Good prices", default) and bulk selling ("Sales").
	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var prices_tab := VBoxContainer.new()
	prices_tab.name = "Good prices"
	prices_tab.add_theme_constant_override("separation", 6)
	main_vbox.remove_child(header_static)
	main_vbox.remove_child(scroll)
	prices_tab.add_child(_build_filter_row())  # search + filters, above the headers
	prices_tab.add_child(header_static)  # table header sits above the rows
	prices_tab.add_child(scroll)
	tabs.add_child(prices_tab)

	var sales_tab := VBoxContainer.new()
	sales_tab.name = "Sales"
	sales_tab.add_theme_constant_override("separation", 6)
	_build_bulk_sell_section(sales_tab)
	tabs.add_child(sales_tab)

	# NPC buildings for sale — one long, searchable list (built lazily on first show).
	var buildings_tab := BuildingMarketTab.new()
	buildings_tab.name = "Buildings"
	tabs.add_child(buildings_tab)

	tabs.add_child(_build_ledger_tab("Transactions",
		MatchState.get_recurring_transaction_rows, MatchState.get_oneoff_transaction_rows))
	tabs.add_child(_build_ledger_tab("Movements",
		MatchState.get_recurring_move_rows, MatchState.get_oneoff_move_rows))

	main_vbox.add_child(tabs)

func _build_ledger_tab(title: String, recurring_getter: Callable, oneoff_getter: Callable) -> VBoxContainer:
	# View-only ledger: a "Recurring" accordion + a "One-off" accordion, each a small table.
	var tab := VBoxContainer.new()
	tab.name = title
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)
	tab.add_child(scroll)

	var recurring := _make_accordion()
	var oneoff := _make_accordion()
	body.add_child(recurring.root)
	body.add_child(oneoff.root)

	var refresh := func() -> void:
		_populate_accordion(recurring, "Recurring", recurring_getter.call())
		_populate_accordion(oneoff, "One-off", oneoff_getter.call())
	_ledger_refreshers.append(refresh)
	refresh.call()
	return tab

func _make_accordion() -> Dictionary:
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var header := Button.new()
	header.toggle_mode = true
	header.button_pressed = true
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(header)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(content)
	var acc := {"root": root, "header": header, "content": content, "title": ""}
	header.toggled.connect(func(pressed: bool) -> void:
		content.visible = pressed
		header.text = ("▾ " if pressed else "▸ ") + str(acc.get("title", ""))
	)
	return acc

func _populate_accordion(acc: Dictionary, label: String, rows: Array) -> void:
	var content: VBoxContainer = acc.content
	for c in content.get_children():
		c.queue_free()
	acc["title"] = "%s (%d)" % [label, rows.size()]
	var expanded: bool = acc.header.button_pressed
	acc.header.text = ("▾ " if expanded else "▸ ") + str(acc.title)
	if rows.is_empty():
		var empty := Label.new()
		empty.text = "  None"
		empty.add_theme_font_size_override("font_size", 12)
		empty.modulate = Color(0.7, 0.7, 0.7)
		content.add_child(empty)
		return
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 2)
	content.add_child(grid)
	for h in ["Type", "From", "To", "Good", "Qty", "Started", "Ended"]:
		grid.add_child(_ledger_cell(h, true))
	for r in rows:
		grid.add_child(_ledger_cell(str(r.get("type", "")), false))
		grid.add_child(_ledger_cell(str(r.get("from", "")), false))
		grid.add_child(_ledger_cell(str(r.get("to", "")), false))
		grid.add_child(_ledger_cell(str(r.get("good", "")), false))
		grid.add_child(_ledger_cell("—" if int(r.get("qty", 0)) < 0 else str(int(r.get("qty", 0))), false))
		grid.add_child(_ledger_cell("T%d" % int(r.get("turn_started", 0)), false))
		grid.add_child(_ledger_cell(_format_turn_ended(int(r.get("turn_ended", -1))), false))

func _ledger_cell(text: String, is_header: bool) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	if is_header:
		lbl.modulate = Color(0.7, 0.85, 1.0)
	return lbl

func _format_turn_ended(ended: int) -> String:
	if ended < 0 or ended > int(TurnManager.current_turn):
		return "Ongoing"
	return "T%d" % ended

func _refresh_ledgers(_summary: Dictionary = {}) -> void:
	# Accept the optional summary arg so the turn_processed signal (which emits one)
	# can connect directly without an arg-count error.
	if not visible:
		return
	for refresh in _ledger_refreshers:
		refresh.call()

func _build_bulk_sell_section(parent: VBoxContainer) -> void:
	# Stories 4 & 5: sell across many/all tiles to market, with good / finished / threshold filters.
	var header := Label.new()
	header.text = "Sell to market (bulk)"
	header.add_theme_font_size_override("font_size", 16)
	parent.add_child(header)

	_good_option = OptionButton.new()
	_good_option.add_item("All goods")
	_good_option.set_item_metadata(0, "")
	for g in Catalog.sellable_goods():
		_good_option.add_item(str(g.display_name))
		_good_option.set_item_metadata(_good_option.item_count - 1, str(g.id))
	parent.add_child(_make_labeled_row("Good", _good_option))

	_finished_check = UIHelpers.make_custom_checkbox()
	parent.add_child(UIHelpers.make_setting_row("Finished goods only (non-raw)", _finished_check))

	_keep_spin = SpinBox.new()
	_keep_spin.min_value = 0
	_keep_spin.max_value = 100000
	_keep_spin.step = 1
	_keep_spin.value = 0
	parent.add_child(_make_labeled_row("Keep per tile", _keep_spin))

	_recurring_check = UIHelpers.make_custom_checkbox()
	parent.add_child(UIHelpers.make_setting_row("Make recurring every turn", _recurring_check))

	var sell_btn := Button.new()
	sell_btn.text = "Sell from all tiles"
	sell_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell_btn.pressed.connect(_on_bulk_sell_pressed)
	parent.add_child(sell_btn)

func _make_labeled_row(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row

func _on_bulk_sell_pressed() -> void:
	var params := {
		"good_id": str(_good_option.get_item_metadata(_good_option.selected)),
		"finished_only": _finished_check.button_pressed,
		"per_tile_keep": int(_keep_spin.value),
	}
	var result: Dictionary = MatchState.sell_all_to_market(params)
	var qty := int(result.get("total_qty", 0))
	var tiles := int(result.get("tiles", 0))
	if qty > 0:
		MatchState.request_toast("Selling %d units from %d tile%s to market" % [
			qty, tiles, "" if tiles == 1 else "s"], "success")
	else:
		MatchState.request_toast("Nothing to sell with those filters", "warning")
	if _recurring_check != null and _recurring_check.button_pressed:
		MatchState.add_recurring_bulk_sell(params)

# ── Filter bar ───────────────────────────────────────────────────────────────
func _build_filter_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	_search = LineEdit.new()
	_search.placeholder_text = "Search products…"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # pushes filters to the right
	_search.custom_minimum_size = Vector2(180, 0)
	_search.text_changed.connect(func(_t: String) -> void: _apply_filters())
	row.add_child(_search)

	_filter_produce_btn = _make_filter_button("Goods you produce")
	_filter_profit_btn = _make_filter_button("Profitable Goods")
	_filter_unprofit_btn = _make_filter_button("Unprofitable Goods")
	_filter_produce_btn.toggled.connect(func(p: bool) -> void: _on_filter_toggled("produce", p))
	_filter_profit_btn.toggled.connect(func(p: bool) -> void: _on_filter_toggled("profit", p))
	_filter_unprofit_btn.toggled.connect(func(p: bool) -> void: _on_filter_toggled("unprofit", p))
	row.add_child(_filter_produce_btn)
	row.add_child(_filter_profit_btn)
	row.add_child(_filter_unprofit_btn)

	_update_filter_availability()
	return row

func _make_filter_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.add_theme_stylebox_override("normal", _filter_box(DS.PALETTE.BG_INSET, DS.PALETTE.BORDER_SOFT))
	b.add_theme_stylebox_override("hover", _filter_box(DS.PALETTE.BG_HIGHLIGHT, DS.PALETTE.ACCENT))
	b.add_theme_stylebox_override("pressed", _filter_box(DS.PALETTE.ACCENT, DS.PALETTE.ACCENT))
	b.add_theme_stylebox_override("hover_pressed", _filter_box(DS.PALETTE.ACCENT, DS.PALETTE.ACCENT))
	b.add_theme_stylebox_override("disabled", _filter_box(DS.PALETTE.BG_PANEL, DS.PALETTE.BORDER_SOFT))
	b.add_theme_color_override("font_color", DS.PALETTE.TEXT_MUTED)
	b.add_theme_color_override("font_hover_color", DS.PALETTE.TEXT)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)        # selected
	b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", DS.PALETTE.TEXT_DIM)
	return b

func _filter_box(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(6)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s

func _on_filter_toggled(which: String, pressed: bool) -> void:
	match which:
		"produce":
			_filter_produce = pressed
		"profit":
			_filter_profitable = pressed
			# Profitable and Unprofitable are mutually exclusive.
			if pressed and _filter_unprofit_btn.button_pressed:
				_filter_unprofit_btn.set_pressed_no_signal(false)
				_filter_unprofitable = false
		"unprofit":
			_filter_unprofitable = pressed
			if pressed and _filter_profit_btn.button_pressed:
				_filter_profit_btn.set_pressed_no_signal(false)
				_filter_profitable = false
	_apply_filters()

func _apply_filters() -> void:
	var q := _search.text.strip_edges().to_lower() if _search != null else ""
	for row in rows:
		if not is_instance_valid(row):
			continue
		var show := true
		if q != "" and not Catalog.get_display_name(row.good_id).to_lower().contains(q):
			show = false
		if show and _filter_produce and not row.is_produced():
			show = false
		if show and _filter_profitable:
			var p: float = row.profit_per_unit()
			if is_nan(p) or p <= 0.0:
				show = false
		if show and _filter_unprofitable:
			var p2: float = row.profit_per_unit()
			if is_nan(p2) or p2 >= 0.0:
				show = false
		row.visible = show

func _update_filter_availability() -> void:
	if _filter_produce_btn == null:
		return
	var any_produce := false
	var any_profit := false
	var any_unprofit := false
	for row in rows:
		if not is_instance_valid(row):
			continue
		if row.is_produced():
			any_produce = true
		var p: float = row.profit_per_unit()
		if not is_nan(p):
			if p > 0.0:
				any_profit = true
			elif p < 0.0:
				any_unprofit = true
	_set_filter_enabled(_filter_produce_btn, any_produce, "You don't produce any goods yet.")
	_set_filter_enabled(_filter_profit_btn, any_profit, "No goods were sold at a profit last turn.")
	_set_filter_enabled(_filter_unprofit_btn, any_unprofit, "No goods were sold at a loss last turn.")
	_apply_filters()

func _set_filter_enabled(btn: Button, enabled: bool, reason: String) -> void:
	btn.disabled = not enabled
	btn.tooltip_text = "" if enabled else reason
	if not enabled and btn.button_pressed:
		btn.set_pressed_no_signal(false)
		if btn == _filter_produce_btn:
			_filter_produce = false
		elif btn == _filter_profit_btn:
			_filter_profitable = false
		elif btn == _filter_unprofit_btn:
			_filter_unprofitable = false

func _build_content() -> void:
	for child in content_vbox.get_children():
		child.queue_free()
	rows.clear()
	
	var all_goods = Catalog.all_goods()
	print("MarketPanel building rows for %d goods" % all_goods.size())
	
	for good_data in all_goods:
		print("  Adding row: ", good_data.id, " / ", good_data.display_name)
		var row := MarketRowScene.instantiate()
		content_vbox.add_child(row)
		row.setup(good_data)
		rows.append(row)

func _on_prices_updated() -> void:
	# Refresh visible prices/cols when decay ticks.
	for row in rows:
		if is_instance_valid(row) and row.has_method("_refresh"):
			row._refresh()
	_update_filter_availability()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Only start drag if click is in the top strip
			if event.position.y > HEADER_HEIGHT:
				return
			_dragging = true
			_drag_offset = global_position - get_global_mouse_position()
			accept_event()
		else:
			_dragging = false
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		global_position = get_global_mouse_position() + _drag_offset
		accept_event()
