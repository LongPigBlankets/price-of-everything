extends PanelContainer

@onready var title_label: Label = $MarginContainer/ContentRow/VBoxContainer/HeaderRow/TitleLabel
@onready var close_button: Button = $MarginContainer/ContentRow/VBoxContainer/HeaderRow/CloseButton
@onready var property_table: GridContainer = $MarginContainer/ContentRow/VBoxContainer/PropertyTable
@onready var deposits_table: GridContainer = $MarginContainer/ContentRow/VBoxContainer/DepositsTable
@onready var infrastructure_table: GridContainer = $MarginContainer/ContentRow/VBoxContainer/InfrastructureTable
@onready var tile_size_chart = $MarginContainer/ContentRow/TileSizeChart

signal building_clicked(building: Dictionary)

const HEADER_HEIGHT := 40.0

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

func _ready() -> void:
	close_button.pressed.connect(hide)
	tile_size_chart.segment_clicked.connect(_on_chart_segment_clicked)
	MatchState.building_added.connect(_on_building_added)
	MatchState.building_removed.connect(_on_building_removed)

func show_tile(tile_data: Dictionary) -> void:
	_current_tile_data = tile_data
	_current_tile_id = tile_data.id
	title_label.text = tile_data.nickname if tile_data.nickname != "" else tile_data.id
	_rebuild_table(tile_data)
	_rebuild_buildings(tile_data)
	_rebuild_deposits_table(tile_data)
	_rebuild_infrastructure_table(tile_data)
	visible = true

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
