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

func _ready() -> void:
	title_label.text = "Market"
	close_button.pressed.connect(hide)
	_build_content()
	_build_tabs()
	MarketState.prices_updated.connect(_on_prices_updated)

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

	main_vbox.add_child(tabs)

func _build_bulk_sell_section(parent: VBoxContainer) -> void:
	# Stories 4 & 5: sell across many/all tiles to market, with good / finished / threshold filters.
	var header := Label.new()
	header.text = "Sell to market (bulk)"
	header.add_theme_font_size_override("font_size", 16)
	parent.add_child(header)

	_good_option = OptionButton.new()
	_good_option.add_item("All goods")
	_good_option.set_item_metadata(0, "")
	for g in Catalog.all_goods():
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
