extends PanelContainer

@onready var title_label: Label = $MarginContainer/ContentRow/VBoxContainer/HeaderRow/TitleLabel
@onready var close_button: Button = $MarginContainer/ContentRow/VBoxContainer/HeaderRow/CloseButton
@onready var property_table: GridContainer = $MarginContainer/ContentRow/VBoxContainer/PropertyTable
@onready var deposits_table: GridContainer = $MarginContainer/ContentRow/VBoxContainer/DepositsTable
@onready var infrastructure_table: GridContainer = $MarginContainer/ContentRow/VBoxContainer/InfrastructureTable
@onready var content_vbox: VBoxContainer = $MarginContainer/ContentRow/VBoxContainer
@onready var tile_size_chart = $MarginContainer/ContentRow/TileSizeChart

signal building_clicked(building: Dictionary)

const HEADER_HEIGHT := 40.0
const STOCKPILE_VISUAL_SIZE := Vector2(250, 100)
const STOCKPILE_UNIT_SIZE := Vector2(10, 5)
const STOCKPILE_VISUAL_COLUMNS := 25

const DISPLAY_FIELDS := [
	"id", "type",
	"tile_price",
]

const FIELD_LABELS := {
	"id": "ID",
	"type": "Type",
	"tile_price": "Tile Price",
}

var _current_tile_data: Dictionary = {}
var _current_tile_id: String = ""
var _dragging := false
var _drag_offset := Vector2.ZERO
var _stockpile_capacity_label: Label = null
var _stockpile_goods_list: VBoxContainer = null
var _stockpile_visual: Panel = null
var _stockpile_sell_button: Button = null
var _sell_surplus_button: CheckButton = null

func _ready() -> void:
	close_button.pressed.connect(hide)
	tile_size_chart.segment_clicked.connect(_on_chart_segment_clicked)
	MatchState.building_added.connect(_on_building_added)
	MatchState.building_removed.connect(_on_building_removed)
	MatchState.stockpile_market_sale_queue_changed.connect(_on_stockpile_market_sale_queue_changed)
	MatchState.sell_surplus_changed.connect(_on_sell_surplus_changed)
	Stockpile.stockpile_changed.connect(_on_stockpile_changed)
	_build_stockpile_section()

func show_tile(tile_data: Dictionary) -> void:
	_current_tile_data = tile_data
	_current_tile_id = tile_data.id
	title_label.text = tile_data.nickname if tile_data.nickname != "" else tile_data.id
	_rebuild_table(tile_data)
	_rebuild_buildings(tile_data)
	_rebuild_deposits_table(tile_data)
	_rebuild_infrastructure_table(tile_data)
	_refresh_stockpile_section()
	visible = true
	PanelStack.push(self)

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
		PanelStack.remove(self)

func _rebuild_table(tile_data: Dictionary) -> void:
	for child in property_table.get_children():
		child.queue_free()

	property_table.add_child(_make_cell("Property", true))
	property_table.add_child(_make_cell("Value", true))

	for field in DISPLAY_FIELDS:
		if not tile_data.has(field):
			continue
		var label_text: String = FIELD_LABELS.get(field, field)
		var value_text := _format_value(tile_data[field])
		property_table.add_child(_make_cell(label_text, false))
		property_table.add_child(_make_cell(value_text, false))

func _rebuild_buildings(tile_data: Dictionary) -> void:
	var tile_id: String = tile_data.id
	var buildings: Array = MatchState.get_buildings_on_tile(tile_id)
	var chart_buildings: Array = []
	for building in buildings:
		var chart_building: Dictionary = building.duplicate()
		chart_building["display_label"] = _format_building_label(building)
		chart_buildings.append(chart_building)
	tile_size_chart.set_buildings(chart_buildings, int(tile_data.get("build_capacity", 10)))

func _rebuild_deposits_table(_tile_data: Dictionary) -> void:
	for child in deposits_table.get_children():
		child.queue_free()

	for header in ["Resource", "Quantity", "Action"]:
		deposits_table.add_child(_make_cell(header, true))

	deposits_table.add_child(_make_cell("Coal", false))
	deposits_table.add_child(_make_cell("Infinite", false))

	var add_button := Button.new()
	add_button.text = "Add Building"
	deposits_table.add_child(add_button)

func _rebuild_infrastructure_table(tile_data: Dictionary) -> void:
	for child in infrastructure_table.get_children():
		child.queue_free()
	
	for header in ["Inf", "lvl", "mnt", "cap"]:
		infrastructure_table.add_child(_make_cell(header, true))
	
	var infrastructure_rows := _infrastructure_rows_for_tile(tile_data)
	for building_data in infrastructure_rows:
		infrastructure_table.add_child(_make_cell(building_data.get("display_name", ""), false))
		infrastructure_table.add_child(_make_cell("1", false))
		infrastructure_table.add_child(_make_cell(_format_nullable_money(building_data.get("maintenance_cost", null)), false))
		infrastructure_table.add_child(_make_cell("1", false))
	
	if infrastructure_rows.size() < _all_infrastructure_buildings().size():
		var add_button := Button.new()
		add_button.text = "ADD"
		infrastructure_table.add_child(add_button)
		infrastructure_table.add_child(_make_cell("", false))
		infrastructure_table.add_child(_make_cell("", false))
		infrastructure_table.add_child(_make_cell("", false))

func _build_stockpile_section() -> void:
	var separator := HSeparator.new()
	content_vbox.add_child(separator)

	var title := Label.new()
	title.text = "Stockpile"
	title.add_theme_font_size_override("font_size", 13)
	title.modulate = Color(0.7, 0.85, 1.0)
	content_vbox.add_child(title)

	_stockpile_capacity_label = Label.new()
	_stockpile_capacity_label.text = "Stored 0 / %d" % Stockpile.get_capacity("")
	content_vbox.add_child(_stockpile_capacity_label)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	content_vbox.add_child(row)

	_stockpile_goods_list = VBoxContainer.new()
	_stockpile_goods_list.custom_minimum_size = Vector2(120, STOCKPILE_VISUAL_SIZE.y)
	_stockpile_goods_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stockpile_goods_list.add_theme_constant_override("separation", 3)
	row.add_child(_stockpile_goods_list)

	_stockpile_visual = Panel.new()
	_stockpile_visual.custom_minimum_size = STOCKPILE_VISUAL_SIZE
	_stockpile_visual.size_flags_horizontal = Control.SIZE_SHRINK_END
	_stockpile_visual.clip_contents = true
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.05, 0.09, 0.82)
	style.border_color = Color(0.7, 0.85, 1.0, 0.35)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	_stockpile_visual.add_theme_stylebox_override("panel", style)
	row.add_child(_stockpile_visual)

	_sell_surplus_button = CheckButton.new()
	_sell_surplus_button.text = "Sell surplus every turn"
	_sell_surplus_button.tooltip_text = "Automatically sell surplus stockpile that buildings on this tile do not require"
	_sell_surplus_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sell_surplus_button.toggled.connect(_on_sell_surplus_toggled)
	content_vbox.add_child(_sell_surplus_button)

	_stockpile_sell_button = Button.new()
	_stockpile_sell_button.text = "Sell All to Market"
	_stockpile_sell_button.custom_minimum_size = Vector2(0, 30)
	_stockpile_sell_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stockpile_sell_button.pressed.connect(_on_sell_stockpile_pressed)
	content_vbox.add_child(_stockpile_sell_button)

func _refresh_stockpile_section() -> void:
	if _stockpile_capacity_label == null or _stockpile_goods_list == null or _stockpile_visual == null:
		return
	var used: int = Stockpile.get_used_capacity(_current_tile_id)
	var capacity: int = Stockpile.get_capacity(_current_tile_id)
	_stockpile_capacity_label.text = "Stored %d / %d" % [used, capacity]
	if _sell_surplus_button != null:
		_sell_surplus_button.set_pressed_no_signal(MatchState.is_sell_surplus_enabled(_current_tile_id))

	if _stockpile_sell_button != null:
		var sale_queued := MatchState.is_stockpile_market_sale_queued(_current_tile_id)
		_stockpile_sell_button.text = "Sale Queued for End Turn" if sale_queued else "Sell All to Market"
		_stockpile_sell_button.disabled = used <= 0 or sale_queued

	for child in _stockpile_goods_list.get_children():
		child.queue_free()

	var committed: Dictionary = Production.compute_committed_for_tile(_current_tile_id)
	var top_goods: Array = Stockpile.get_top_goods(_current_tile_id, 3)
	if top_goods.is_empty():
		_stockpile_goods_list.add_child(_make_stockpile_row("No goods stored"))
	else:
		for row in top_goods:
			var good_id: String = row.get("good_id", "")
			var qty: int = int(row.get("qty", 0))
			var need: int = int(committed.get(good_id, 0))
			var text: String
			if need > 0:
				text = "%s: %d (need %d)" % [Catalog.get_display_name(good_id), qty, need]
			else:
				text = "%s: %d" % [Catalog.get_display_name(good_id), qty]
			_stockpile_goods_list.add_child(_make_stockpile_row(text))

	_rebuild_stockpile_visual()

func _rebuild_stockpile_visual() -> void:
	for child in _stockpile_visual.get_children():
		child.queue_free()

	var block_index := 0
	for row in _sorted_stockpile_visual_rows():
		var good_id: String = row.get("good_id", "")
		var qty: int = int(row.get("qty", 0))
		var color := _stockpile_color_for_good(good_id)
		for _i in range(qty):
			if block_index >= Stockpile.get_capacity(_current_tile_id):
				return
			var block := ColorRect.new()
			block.color = color
			block.size = STOCKPILE_UNIT_SIZE
			block.position = Vector2(
				float(block_index % STOCKPILE_VISUAL_COLUMNS) * STOCKPILE_UNIT_SIZE.x,
				floorf(float(block_index) / float(STOCKPILE_VISUAL_COLUMNS)) * STOCKPILE_UNIT_SIZE.y
			)
			_stockpile_visual.add_child(block)
			block_index += 1

func _sorted_stockpile_visual_rows() -> Array:
	var rows: Array = []
	var totals: Dictionary = Stockpile.get_tile_totals(_current_tile_id)
	for good_id in totals.keys():
		var qty: int = int(totals[good_id])
		if qty > 0:
			rows.append({"good_id": good_id, "qty": qty})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.qty) == int(b.qty):
			return str(a.good_id) < str(b.good_id)
		return int(a.qty) > int(b.qty)
	)
	return rows

func _make_stockpile_row(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 12)
	return label

func _stockpile_color_for_good(good_id: String) -> Color:
	var seed := 0
	for i in good_id.length():
		seed += good_id.unicode_at(i) * (i + 1)
	var hue := float(seed % 360) / 360.0
	return Color.from_hsv(hue, 0.55, 0.95, 0.9)

func _on_stockpile_changed() -> void:
	if visible and _current_tile_id != "":
		_refresh_stockpile_section()

func _on_stockpile_market_sale_queue_changed(tile_id: String) -> void:
	if visible and tile_id == _current_tile_id:
		_refresh_stockpile_section()

func _on_sell_stockpile_pressed() -> void:
	if _current_tile_id == "":
		return
	if Stockpile.get_used_capacity(_current_tile_id) <= 0:
		return
	MatchState.queue_stockpile_market_sale(_current_tile_id)
	_refresh_stockpile_section()

func _infrastructure_rows_for_tile(tile_data: Dictionary) -> Array:
	var rows: Array = []
	var seen_ids := {}
	for building in MatchState.get_buildings_on_tile(tile_data.id):
		var building_data: Dictionary = Catalog.get_building(building.get("building_id", ""))
		if building_data.get("category", "") == "infrastructure":
			rows.append(building_data)
			seen_ids[building_data.get("id", "")] = true
	
	var infrastructure_present: Array = tile_data.get("infrastructure_present", [])
	for infra_name in infrastructure_present:
		var building_data: Dictionary = Catalog.get_building_by_internal_name(str(infra_name))
		if building_data.is_empty():
			continue
		var building_id: String = building_data.get("id", "")
		if seen_ids.has(building_id):
			continue
		rows.append(building_data)
		seen_ids[building_id] = true
	return rows

func _all_infrastructure_buildings() -> Array:
	var buildings: Array = []
	for building_data in Catalog.all_buildings():
		if building_data.get("category", "") == "infrastructure":
			buildings.append(building_data)
	return buildings

func _format_building_label(building: Dictionary) -> String:
	var building_data: Dictionary = Catalog.get_building(building.get("building_id", ""))
	var building_name: String = building_data.get("display_name", building.get("building_id", ""))
	var recipe: Dictionary = Catalog.get_recipe(building.get("recipe_id", ""))
	var output_name := _primary_output_display_name(recipe)
	var letter := _building_letter_for_tile(building)
	if output_name == "":
		return "%s - %s" % [building_name, letter]
	return "%s - %s - %s" % [building_name, output_name, letter]

func _on_chart_segment_clicked(building: Dictionary) -> void:
	building_clicked.emit(building)

func _primary_output_display_name(recipe: Dictionary) -> String:
	var output_name: String = recipe.get("output_name", "")
	if output_name == "":
		return ""
	var good: Dictionary = Catalog.get_good_by_internal_name(output_name)
	return good.get("display_name", output_name)

func _building_letter_for_tile(building: Dictionary) -> String:
	var tile_id: String = building.get("tile_id", "")
	var instance_id: String = building.get("instance_id", "")
	var buildings: Array = MatchState.get_buildings_on_tile(tile_id)
	for i in buildings.size():
		if buildings[i].get("instance_id", "") == instance_id:
			return _letter_from_index(i)
	return "?"

func _letter_from_index(index: int) -> String:
	var alphabet := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	if index < alphabet.length():
		return alphabet.substr(index, 1)
	var first_index := floori(float(index) / float(alphabet.length())) - 1
	return alphabet.substr(first_index, 1) + alphabet.substr(index % alphabet.length(), 1)

func _on_building_added(instance: Dictionary) -> void:
	if not visible:
		return
	if instance.get("tile_id", "") == _current_tile_id:
		_rebuild_buildings(_current_tile_data)
		_rebuild_infrastructure_table(_current_tile_data)

func _on_building_removed(_instance_id: String) -> void:
	if visible and _current_tile_id != "":
		_rebuild_buildings(_current_tile_data)
		_rebuild_infrastructure_table(_current_tile_data)

func _make_cell(text: String, is_header: bool) -> Label:
	var label := Label.new()
	label.text = text
	if is_header:
		label.add_theme_font_size_override("font_size", 13)
		label.modulate = Color(0.7, 0.85, 1.0)
	return label

func _format_value(value: Variant) -> String:
	if value is Array:
		return "—" if value.is_empty() else ", ".join(value)
	return str(value)

func _format_nullable_money(value: Variant) -> String:
	if value == null:
		return "null"
	return "£%.2f" % float(value)

func _on_sell_surplus_toggled(pressed: bool) -> void:
	if _current_tile_id == "":
		return
	if pressed:
		MatchState.enable_sell_surplus(_current_tile_id)
	else:
		MatchState.disable_sell_surplus(_current_tile_id)

func _on_sell_surplus_changed(tile_id: String) -> void:
	if visible and tile_id == _current_tile_id:
		_refresh_stockpile_section()

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
