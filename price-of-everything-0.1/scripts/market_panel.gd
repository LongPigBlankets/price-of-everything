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
# Purchases tab
var _buy_search_field: LineEdit = null
var _buy_search_list: ItemList = null
var _buy_qty_field: LineEdit = null
var _buy_dest_button: Button = null
var _buy_recurring_check: CheckBox = null
var _buy_cta: Button = null
var _buy_good_id: String = ""
var _buy_dest_tile: String = ""
var _buy_search_results: Array = []  # good_ids for the current filter
var _pick_in_progress := false  # true while the panel is hidden for a map tile-pick

func _ready() -> void:
	title_label.text = "Market"
	close_button.pressed.connect(hide)
	_build_content()
	_build_tabs()
	MarketState.prices_updated.connect(_on_prices_updated)
	MatchState.buy_tile_picked.connect(_on_buy_tile_picked)
	visibility_changed.connect(_on_panel_visibility_changed)
	Production.turn_processed.connect(_refresh_ledgers)

func _on_panel_visibility_changed() -> void:
	if not visible:
		return
	_refresh_ledgers()
	if not _pick_in_progress:
		# Fresh open (not a reopen after a map pick): clear stale "recurring" choices.
		if _buy_recurring_check != null:
			_buy_recurring_check.set_pressed_no_signal(false)
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

	tabs.add_child(_build_purchases_tab())
	tabs.add_child(_build_ledger_tab("Transactions",
		MatchState.get_recurring_transaction_rows, MatchState.get_oneoff_transaction_rows))
	tabs.add_child(_build_ledger_tab("Movements",
		MatchState.get_recurring_move_rows, MatchState.get_oneoff_move_rows))

	main_vbox.add_child(tabs)

func _build_purchases_tab() -> VBoxContainer:
	var tab := VBoxContainer.new()
	tab.name = "Purchases"
	tab.add_theme_constant_override("separation", 6)

	var header := Label.new()
	header.text = "Buy from market"
	header.add_theme_font_size_override("font_size", 16)
	tab.add_child(header)

	# Good — search with live string-matched results (buyable goods only).
	tab.add_child(_make_caption("Good"))
	_buy_search_field = LineEdit.new()
	_buy_search_field.placeholder_text = "Search goods…"
	_buy_search_field.text_changed.connect(_on_buy_search_changed)
	tab.add_child(_buy_search_field)
	_buy_search_list = ItemList.new()
	_buy_search_list.visible = false
	_buy_search_list.custom_minimum_size = Vector2(0, 110)
	_buy_search_list.item_selected.connect(_on_buy_good_selected)
	tab.add_child(_buy_search_list)

	# Quantity (editable box + arrows, like the Sell steppers)
	tab.add_child(_make_buy_qty_row())

	# Destination — picked on the map
	_buy_dest_button = Button.new()
	_buy_dest_button.text = "Choose tile on map"
	_buy_dest_button.pressed.connect(_on_choose_dest_pressed)
	tab.add_child(_make_labeled_row("Deliver to", _buy_dest_button))

	_buy_recurring_check = UIHelpers.make_custom_checkbox()
	tab.add_child(UIHelpers.make_setting_row("Make recurring every turn", _buy_recurring_check))

	_buy_cta = Button.new()
	_buy_cta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_buy_cta.pressed.connect(_on_buy_pressed)
	tab.add_child(_buy_cta)
	_update_buy_cta()
	return tab

func _make_caption(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	return lbl

func _make_buy_qty_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = "Quantity"
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	_buy_qty_field = LineEdit.new()
	_buy_qty_field.text = "10"
	_buy_qty_field.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_buy_qty_field.custom_minimum_size = Vector2(64, 0)
	_buy_qty_field.text_changed.connect(func(_t: String) -> void: _update_buy_cta())
	row.add_child(_buy_qty_field)
	var arrows := VBoxContainer.new()
	arrows.add_theme_constant_override("separation", 2)
	var up := _make_tiny_arrow("▲")
	up.pressed.connect(_on_buy_qty_arrow.bind(1))
	var down := _make_tiny_arrow("▼")
	down.pressed.connect(_on_buy_qty_arrow.bind(-1))
	arrows.add_child(up)
	arrows.add_child(down)
	row.add_child(arrows)
	return row

func _make_tiny_arrow(glyph: String) -> Button:
	var b := Button.new()
	b.text = glyph
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(16, 14)
	b.add_theme_font_size_override("font_size", 10)
	return b

func _on_buy_qty_arrow(delta: int) -> void:
	var v: int = (int(_buy_qty_field.text) if _buy_qty_field.text.is_valid_int() else 0) + delta
	_buy_qty_field.text = str(maxi(1, v))
	_update_buy_cta()

func _on_buy_search_changed(text: String) -> void:
	_buy_search_list.clear()
	_buy_search_results.clear()
	var needle := text.strip_edges().to_lower()
	for g in Catalog.buyable_goods():
		var name := str(g.get("display_name", ""))
		if needle == "" or name.to_lower().contains(needle):
			_buy_search_list.add_item(name)
			_buy_search_results.append(str(g.get("id", "")))
	_buy_search_list.visible = not _buy_search_results.is_empty()

func _on_buy_good_selected(index: int) -> void:
	if index < 0 or index >= _buy_search_results.size():
		return
	_buy_good_id = str(_buy_search_results[index])
	_buy_search_field.text = Catalog.get_display_name(_buy_good_id)
	_buy_search_list.visible = false
	_update_buy_cta()

func _on_choose_dest_pressed() -> void:
	# Hide the panel for the map pick, then reopen it once a tile is chosen.
	_pick_in_progress = true
	hide()
	MatchState.buy_tile_pick_requested.emit()

func _on_buy_tile_picked(tile_id: String) -> void:
	_buy_dest_tile = tile_id
	_buy_dest_button.text = "Choose tile on map" if tile_id == "" else Catalog.tile_label(tile_id)
	_update_buy_cta()
	if _pick_in_progress:
		show()  # reopen on the Purchases tab; recurring is preserved (guarded in visibility handler)
		_pick_in_progress = false

func _update_buy_cta() -> void:
	if _buy_cta == null:
		return
	var qty: int = int(_buy_qty_field.text) if _buy_qty_field != null and _buy_qty_field.text.is_valid_int() else 0
	var good_label := Catalog.get_display_name(_buy_good_id) if _buy_good_id != "" else "—"
	_buy_cta.text = "Buy %d %s" % [qty, good_label]
	_buy_cta.disabled = _buy_good_id == "" or qty <= 0 or _buy_dest_tile == ""

func _on_buy_pressed() -> void:
	var qty: int = int(_buy_qty_field.text) if _buy_qty_field.text.is_valid_int() else 0
	if _buy_good_id == "" or qty <= 0 or _buy_dest_tile == "":
		return
	var result: Dictionary = MatchState.queue_buy(_buy_dest_tile, _buy_good_id, qty)
	if not result.is_empty():
		var turns := int(result.get("turns", 0))
		MatchState.request_toast("Buying %d %s to %s — arrives in %d turn%s" % [
			int(result.get("qty", qty)), Catalog.get_display_name(_buy_good_id),
			Catalog.tile_label(_buy_dest_tile), turns, "" if turns == 1 else "s"], "success")
	else:
		MatchState.request_toast("Couldn't buy %s — not enough cash" % Catalog.get_display_name(_buy_good_id), "warning")
	if _buy_recurring_check != null and _buy_recurring_check.button_pressed:
		MatchState.add_recurring_buy(_buy_dest_tile, _buy_good_id, qty)

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

func _refresh_ledgers() -> void:
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
	# Pass 2 will use this to refresh visible prices when decay ticks
	for row in rows:
		row._update_price()

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
