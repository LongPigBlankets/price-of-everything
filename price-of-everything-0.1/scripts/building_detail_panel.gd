extends PanelContainer

@onready var title_label: Label = $MarginContainer/VBoxContainer/HeaderRow/TitleLabel
@onready var close_button: Button = $MarginContainer/VBoxContainer/HeaderRow/CloseButton
@onready var fields_vbox: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/FieldsVBox

const HEADER_HEIGHT := 40.0

var _dragging := false
var _drag_offset := Vector2.ZERO

func _ready() -> void:
	close_button.pressed.connect(hide)

func show_building(building: Dictionary) -> void:
	_rebuild_fields(building)
	visible = true

func _rebuild_fields(building: Dictionary) -> void:
	for child in fields_vbox.get_children():
		child.queue_free()
	
	var building_data: Dictionary = Catalog.get_building(building.get("building_id", ""))
	var recipe: Dictionary = Catalog.get_recipe(building.get("recipe_id", ""))
	var category: String = building_data.get("category", "")
	var is_infrastructure: bool = category == "infrastructure"
	
	title_label.text = _building_display_name(building, building_data, recipe)
	_add_text(_format_location(building))
	_add_field("Value", "£%s" % _format_money(building_data.get("base_price", 0.0)))
	
	if not is_infrastructure:
		_add_field("Power Status", _power_status(building, recipe))
		_add_field("Power Supply", _power_supply(building))
		
		var energy_req: int = recipe.get("energy_req", 0)
		if energy_req > 0:
			_add_field("Power Consumption", str(energy_req))
		
		if recipe.get("output_name", "") == "power":
			_add_field("Power production", str(recipe.get("output_qty", 0)))
	
	if not is_infrastructure:
		for input_line in _input_lines(building_data, recipe):
			_add_field("Input", input_line)
		for output_line in _output_lines(recipe):
			_add_field("Output", output_line)
	
	_add_field("Maintenance cost", "£%s (stub: no per-building maintenance field)" % _format_money(EconomyConfig.MAINTENANCE_PER_BUILDING))
	_add_field("Labour cost", "£%s (stub: %d/%d/%d workers)" % [
		_format_money(_labour_cost()),
		EconomyConfig.STUB_UNSKILLED_PER_BUILDING,
		EconomyConfig.STUB_SKILLED_PER_BUILDING,
		EconomyConfig.STUB_HIGH_SKILLED_PER_BUILDING,
	])
	
	if not is_infrastructure and recipe.get("output_name", "") != "power":
		_add_field("Output destination", _output_destination())

func _add_text(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fields_vbox.add_child(label)

func _add_field(field_name: String, value: String) -> void:
	_add_text("%s: %s" % [field_name, value])

func _building_display_name(building: Dictionary, building_data: Dictionary, recipe: Dictionary) -> String:
	var building_name: String = building_data.get("display_name", building.get("building_id", ""))
	var output_name := _primary_output_display_name(recipe)
	var letter := _building_letter_for_tile(building)
	if output_name == "":
		return "%s - %s" % [building_name, letter]
	return "%s - %s - %s" % [building_name, output_name, letter]

func _format_location(building: Dictionary) -> String:
	var tile_id: String = building.get("tile_id", "")
	if tile_id.begins_with("tile_"):
		return "Tile %s" % tile_id.trim_prefix("tile_")
	return tile_id

func _power_status(building: Dictionary, recipe: Dictionary) -> String:
	var energy_req: int = recipe.get("energy_req", 0)
	if energy_req <= 0 and recipe.get("output_name", "") != "power":
		return "Not connected"
	return "Connected" if Power.is_supplied(building.get("tile_id", ""), energy_req) else "Not connected"

func _power_supply(building: Dictionary) -> String:
	var power_state := _tile_power_state(building.get("tile_id", ""))
	if not power_state.get("connected", false):
		return "Not connected"
	if not power_state.get("has_power_plant", false) or power_state.get("supply", 0) < power_state.get("demand", 0):
		return "Grid"
	return "Owned Supply"

func _tile_power_state(tile_id: String) -> Dictionary:
	var connected := Power.is_supplied(tile_id, 1)
	var supply := 0
	var demand := 0
	var has_power_plant := false
	for building in MatchState.get_buildings_on_tile(tile_id):
		var recipe: Dictionary = Catalog.get_recipe(building.get("recipe_id", ""))
		if recipe.get("output_name", "") == "power":
			has_power_plant = true
			supply += recipe.get("output_qty", 0)
		demand += recipe.get("energy_req", 0)
	return {
		"connected": connected,
		"supply": supply,
		"demand": demand,
		"has_power_plant": has_power_plant,
	}

func _input_lines(building_data: Dictionary, recipe: Dictionary) -> Array:
	var inputs: Array = recipe.get("inputs", [])
	if not inputs.is_empty():
		var lines: Array = []
		for input in inputs:
			lines.append("%d %s" % [input.get("qty", 0), _good_display_from_internal(input.get("internal_name", ""))])
		return lines
	
	var internal_name: String = building_data.get("internal_name", "")
	var output_name: String = recipe.get("output_name", "")
	if internal_name == "mine" and output_name != "":
		return ["%s deposit" % _good_display_from_internal(output_name)]
	if internal_name == "water_pump":
		return ["Water source"]
	return []

func _output_lines(recipe: Dictionary) -> Array:
	var output_name: String = recipe.get("output_name", "")
	var output_qty: int = recipe.get("output_qty", 0)
	if output_name == "" or output_qty <= 0:
		return []
	return ["%d %s" % [output_qty, _good_display_from_internal(output_name)]]

func _primary_output_display_name(recipe: Dictionary) -> String:
	var output_name: String = recipe.get("output_name", "")
	if output_name == "":
		return ""
	return _good_display_from_internal(output_name)

func _good_display_from_internal(internal_name: String) -> String:
	var good: Dictionary = Catalog.get_good_by_internal_name(internal_name)
	return good.get("display_name", internal_name)

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

func _labour_cost() -> float:
	var base_cost: float = (
		EconomyConfig.STUB_UNSKILLED_PER_BUILDING * EconomyConfig.LABOUR_UNSKILLED_RATE
		+ EconomyConfig.STUB_SKILLED_PER_BUILDING * EconomyConfig.LABOUR_SKILLED_RATE
		+ EconomyConfig.STUB_HIGH_SKILLED_PER_BUILDING * EconomyConfig.LABOUR_HIGH_SKILLED_RATE
	)
	return base_cost * MatchState.labour_multiplier

func _output_destination() -> String:
	return "Market" if MatchState.sell_mode == MatchState.SellMode.SELL_ALL else "Stockpile"

func _format_money(value: float) -> String:
	var text := "%.2f" % value
	while text.ends_with("0"):
		text = text.trim_suffix("0")
	if text.ends_with("."):
		text = text.trim_suffix(".")
	return text

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
