extends PanelContainer

@onready var title_label: Label = $MarginContainer/VBoxContainer/HeaderRow/TitleLabel
@onready var close_button: Button = $MarginContainer/VBoxContainer/HeaderRow/CloseButton
@onready var content_vbox: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/ContentVBox

const BuildingRowScene: PackedScene = preload("res://scenes/building_row.tscn")

const SECTION_ORDER: Array = ["production", "power", "infrastructure", "battery"]
const SECTION_DISPLAY_NAMES: Dictionary = {
	"production": "PRODUCTION",
	"power": "POWER",
	"infrastructure": "INFRASTRUCTURE",
	"battery": "BATTERY",
}
const HEADER_HEIGHT := 40.0
const SECTION_HEADER_COLOR := Color(0.05, 0.18, 0.32, 0.92)
const SECTION_HEADER_TEXT_COLOR := Color(0.78, 0.9, 1.0)

var buildings_by_category: Dictionary = {}  # category -> Array of building data
var recipes_by_building: Dictionary = {}    # building_id -> Array of recipe data
var take_loan_dialog: PanelContainer = null
var overlay_rows: Array = []
var _dragging := false
var _drag_offset := Vector2.ZERO
var _section_containers: Dictionary = {}
var _section_toggle_buttons: Dictionary = {}
var _section_labels: Dictionary = {}
var _section_expanded: Dictionary = {}
var _building_rows: Array = []

func _ready() -> void:
	close_button.pressed.connect(hide)
	if not BuildMode.mode_entered.is_connected(_on_build_mode_entered):
		BuildMode.mode_entered.connect(_on_build_mode_entered)
	if not BuildMode.mode_exited.is_connected(_on_build_mode_exited):
		BuildMode.mode_exited.connect(_on_build_mode_exited)
	if not MatchState.money_changed.is_connected(_on_money_changed):
		MatchState.money_changed.connect(_on_money_changed)
	title_label.text = "Construct Building"
	_load_buildings()
	_load_recipes()
	print(">>> recipes_by_building keys: ", recipes_by_building.keys())
	print(">>> sample: ", recipes_by_building.get("b_001", []))
	_build_panel_content()

func _load_buildings() -> void:
	var path := "res://data/Buildings - buildingsMVP.csv"
	if not FileAccess.file_exists(path):
		push_error("Buildings CSV not found at %s" % path)
		return

	var file := FileAccess.open(path, FileAccess.READ)
	var headers := file.get_csv_line()

	while not file.eof_reached():
		var line := file.get_csv_line()
		if line.size() < 7 or line[0] == "":
			continue

		var building := _parse_building_row(headers, line)
		if building.is_empty():
			continue

		var category: String = building.get("category", "production")
		if not buildings_by_category.has(category):
			buildings_by_category[category] = []
		buildings_by_category[category].append(building)

	file.close()

func _load_recipes() -> void:
	var path := "res://data/recipesMVP.csv"  # adjust to your actual CSV filename
	if not FileAccess.file_exists(path):
		push_error("Recipes CSV not found at %s" % path)
		return

	var file := FileAccess.open(path, FileAccess.READ)
	var headers := file.get_csv_line()

	while not file.eof_reached():
		var line := file.get_csv_line()
		if line.size() < 3 or line[0] == "":
			continue

		var recipe := _parse_recipe_row(headers, line)
		if recipe.is_empty():
			continue

		var building_id: String = recipe.building_id
		if building_id == "":
			continue
		if not recipes_by_building.has(building_id):
			recipes_by_building[building_id] = []
		recipes_by_building[building_id].append(recipe)

	file.close()

func _parse_building_row(headers: PackedStringArray, line: PackedStringArray) -> Dictionary:
	var result := {}
	for i in headers.size():
		var key := headers[i].strip_edges().to_lower().replace(" ", "_")
		var val: String = line[i].strip_edges() if i < line.size() else ""
		result[key] = val

	var materials: Array = []
	for n in range(1, 6):
		var mat_name: String = result.get("build_material_%d" % n, "")
		var mat_qty_str: String = result.get("build_qty_%d" % n, "")
		if mat_name != "" and mat_qty_str != "":
			materials.append({"name": mat_name, "qty": int(mat_qty_str)})

	return {
		"id": result.get("id", ""),
		"internal_name": result.get("internal_name", ""),
		"name": result.get("display_name", result.get("name", "")),
		"cost": result.get("build_cost_money", "0"),
		"category": result.get("building_category", "production").to_lower(),
		"materials": materials,
		"icon": result.get("icon", "*"),
	}

func _parse_recipe_row(headers: PackedStringArray, line: PackedStringArray) -> Dictionary:
	var result := {}
	for i in headers.size():
		var key := headers[i].strip_edges().to_lower().replace(" ", "_")
		var val: String = line[i].strip_edges() if i < line.size() else ""
		result[key] = val

	# Parse output (first output is the primary)
	var output_name: String = result.get("output_1", "")
	var output_qty_str: String = result.get("output_qty_1", "0")
	var output_qty: int = 0 if output_qty_str == "" else int(output_qty_str)

	# Parse inputs (up to 5)
	var inputs: Array = []
	for n in range(1, 6):
		var inp_name: String = result.get("input_%d" % n, "")
		var inp_qty_str: String = result.get("qty_%d" % n, "")
		if inp_name != "" and inp_qty_str != "":
			inputs.append({"name": inp_name, "qty": int(inp_qty_str)})

	var energy_str: String = result.get("energy_req", "0")
	var energy_req: int = 0 if energy_str == "" else int(energy_str)

	return {
		"recipe_id": result.get("recipe_id", ""),
		"display_name": result.get("display_name", ""),
		"building_id": result.get("building_id", ""),
		"energy_req": energy_req,
		"output_name": output_name,
		"output_qty": output_qty,
		"inputs": inputs,
	}

func _on_infrastructure_build_pressed(building_id: String) -> void:
	var building_data: Dictionary = _find_building_data(building_id)
	var infra_key: String = building_data.get("internal_name", "")
	if infra_key == "":
		push_warning("Infrastructure %s has no internal_name" % building_id)
		return
	BuildMode.enter_infrastructure_mode(infra_key)
	_refresh_build_mode_selection()

func _find_building_data(building_id: String) -> Dictionary:
	for category in buildings_by_category.keys():
		for b in buildings_by_category[category]:
			if b.id == building_id:
				return b
	return {}

func _build_panel_content() -> void:
	for child in content_vbox.get_children():
		child.queue_free()
	_section_containers.clear()
	_section_toggle_buttons.clear()
	_section_labels.clear()
	_section_expanded.clear()
	_building_rows.clear()

	for category in SECTION_ORDER:
		if not buildings_by_category.has(category):
			continue

		_add_section(category)
		var section_container: VBoxContainer = _section_containers[category]

		for building_data in buildings_by_category[category]:
			var row := BuildingRowScene.instantiate()
			section_container.add_child(row)

			var building_id: String = building_data.id
			var recipes_for_this: Array = recipes_by_building.get(building_id, [])
			row.setup(building_data, recipes_for_this)
			row.set_affordable(_is_building_affordable(building_data), MatchState.money)
			row.recipe_selected.connect(_on_recipe_selected)
			row.expand_toggled.connect(_on_expand_toggled)
			row.infrastructure_build_pressed.connect(_on_infrastructure_build_pressed)  # NEW
			_building_rows.append(row)

	_refresh_build_mode_selection()

func _add_section(category: String) -> void:
	var header_panel := PanelContainer.new()
	header_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var header_style := StyleBoxFlat.new()
	header_style.bg_color = SECTION_HEADER_COLOR
	header_style.corner_radius_top_left = 4
	header_style.corner_radius_top_right = 4
	header_style.corner_radius_bottom_left = 4
	header_style.corner_radius_bottom_right = 4
	header_style.content_margin_left = 8
	header_style.content_margin_top = 4
	header_style.content_margin_right = 6
	header_style.content_margin_bottom = 4
	header_panel.add_theme_stylebox_override("panel", header_style)
	content_vbox.add_child(header_panel)

	var header_row := HBoxContainer.new()
	header_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_theme_constant_override("separation", 8)
	header_panel.add_child(header_row)

	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", SECTION_HEADER_TEXT_COLOR)
	header_row.add_child(label)

	var toggle_button := Button.new()
	toggle_button.custom_minimum_size = Vector2(28, 28)
	toggle_button.add_theme_font_size_override("font_size", 16)
	header_row.add_child(toggle_button)

	var section_container := VBoxContainer.new()
	content_vbox.add_child(section_container)

	_section_containers[category] = section_container
	_section_labels[category] = label
	_section_toggle_buttons[category] = toggle_button
	_section_expanded[category] = true
	_update_section_header(category)
	toggle_button.pressed.connect(_on_section_header_pressed.bind(category))

func _on_section_header_pressed(category: String) -> void:
	var expanded: bool = _section_expanded.get(category, true)
	_section_expanded[category] = not expanded
	_section_containers[category].visible = not expanded
	_update_section_header(category)

func _update_section_header(category: String) -> void:
	var expanded: bool = _section_expanded.get(category, true)
	var marker := "v" if expanded else ">"
	var label: String = SECTION_DISPLAY_NAMES.get(category, category.to_upper())
	_section_labels[category].text = label
	_section_toggle_buttons[category].text = marker

func _on_recipe_selected(building_id: String, recipe_id: String) -> void:
	print("Recipe selected: %s for %s" % [recipe_id, building_id])
	BuildMode.enter_build_mode(building_id, recipe_id)
	_refresh_build_mode_selection()

func _on_expand_toggled(building_id: String, is_expanded: bool) -> void:
	print("Expand toggled: ", building_id, " expanded=", is_expanded)

func _on_build_mode_entered(_building_id: String, _recipe_id: String) -> void:
	_refresh_build_mode_selection()

func _on_build_mode_exited() -> void:
	_refresh_build_mode_selection()

func _on_money_changed(_new_amount: float) -> void:
	_refresh_affordability()

func _refresh_affordability() -> void:
	for row in _building_rows:
		if row == null:
			continue
		var building_data: Dictionary = _find_building_data(row.building_id)
		row.set_affordable(_is_building_affordable(building_data), MatchState.money)

func _refresh_build_mode_selection() -> void:
	for row in _building_rows:
		if row == null:
			continue
		var active_building_id := ""
		var active_recipe_id := ""
		var active_infrastructure_key := ""
		if BuildMode.is_active and BuildMode.kind == BuildMode.Kind.BUILDING:
			active_building_id = BuildMode.current_building_id
			active_recipe_id = BuildMode.current_recipe_id
		elif BuildMode.is_active and BuildMode.kind == BuildMode.Kind.INFRASTRUCTURE:
			active_infrastructure_key = BuildMode.current_infrastructure_type
		row.set_build_mode_selection(active_building_id, active_recipe_id, active_infrastructure_key)

func _is_building_affordable(building_data: Dictionary) -> bool:
	return float(building_data.get("cost", 0.0)) <= MatchState.money




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
