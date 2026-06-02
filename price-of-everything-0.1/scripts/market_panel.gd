extends PanelContainer

@onready var title_label: Label = $MarginContainer/VBoxContainer/HeaderRow/TitleLabel
@onready var close_button: Button = $MarginContainer/VBoxContainer/HeaderRow/CloseButton
@onready var content_vbox: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/ContentVBox
@onready var main_vbox: VBoxContainer = $MarginContainer/VBoxContainer
@onready var header_static: HBoxContainer = $MarginContainer/VBoxContainer/HeaderRowStatic
@onready var scroll: ScrollContainer = $MarginContainer/VBoxContainer/ScrollContainer

const MarketRowScene: PackedScene = preload("res://scenes/market_row.tscn")
const UIHelpers := preload("res://scripts/ui_helpers.gd")
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

func _rebuild_header() -> void:
	for c in header_static.get_children():
		header_static.remove_child(c)
		c.queue_free()
	header_static.add_theme_constant_override("separation", 10)
	header_static.add_child(_header_spacer(60.0))             # icon column
	header_static.add_child(_header_label("Product", 160.0))
	header_static.add_child(_header_label("Sale now", 80.0, SALE_TINT))
	header_static.add_child(_header_label("Sale +10t", 90.0, SALE_TINT))
	header_static.add_child(_header_label("Buy now", 80.0, BUY_TINT))
	header_static.add_child(_header_label("Buy +10t", 90.0, BUY_TINT))
	header_static.add_child(_header_label("Sold", 80.0))
	header_static.add_child(_header_label("Bought", 90.0))
	header_static.add_child(_header_label("Cost/unit", 100.0))
	header_static.add_child(_header_label("Profit/unit", 110.0))

const SALE_TINT := Color(0.82, 0.85, 0.90, 0.10)
const BUY_TINT := Color(0.50, 0.53, 0.58, 0.22)

func _header_label(text: String, width: float, tint: Color = Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(width, 0)
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
	# Double-width, centred on screen.
	var vp := get_viewport_rect().size
	var w := 800.0
	var h := minf(640.0, vp.y - 80.0)
	offset_left = maxf(0.0, (vp.x - w) / 2.0)
	offset_top = maxf(40.0, (vp.y - h) / 2.0)
	offset_right = offset_left + w
	offset_bottom = offset_top + h

func _on_panel_visibility_changed() -> void:
	if not visible:
		return
	_centre_and_resize()
	_refresh_ledgers()
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
	main_vbox.remove_child(header_static)
	main_vbox.remove_child(scroll)
	prices_tab.add_child(header_static)  # table header sits above the rows
	prices_tab.add_child(scroll)
	tabs.add_child(prices_tab)

	var sales_tab := VBoxContainer.new()
	sales_tab.name = "Sales"
	sales_tab.add_theme_constant_override("separation", 6)
	_build_bulk_sell_section(sales_tab)
	tabs.add_child(sales_tab)

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
