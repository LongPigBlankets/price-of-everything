extends PanelContainer

@onready var title_label: Label = $MarginContainer/VBoxContainer/HeaderRow/TitleLabel
@onready var close_button: Button = $MarginContainer/VBoxContainer/HeaderRow/CloseButton
@onready var content_vbox: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/ContentVBox

const BuildingRowScene: PackedScene = preload("res://scenes/building_row.tscn")

const SECTION_ORDER: Array = ["production", "power", "infrastructure"]
const SECTION_DISPLAY_NAMES: Dictionary = {
	"production": "PRODUCTION",
	"power": "POWER",
	"infrastructure": "INFRASTRUCTURE",
}
const HEADER_HEIGHT := 40.0

var buildings_by_category: Dictionary = {}  # category -> Array of building data
var recipes_by_building: Dictionary = {}    # building_id -> Array of recipe data
var take_loan_dialog: PanelContainer = null
var overlay_rows: Array = []
var _dragging := false
var _drag_offset := Vector2.ZERO

func _ready() -> void:
	close_button.pressed.connect(hide)
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
		"icon": result.get("icon", "•"),
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

func _find_building_data(building_id: String) -> Dictionary:
	for category in buildings_by_category.keys():
		for b in buildings_by_category[category]:
			if b.id == building_id:
				return b
	return {}
	
func _build_panel_content() -> void:
	for child in content_vbox.get_children():
		child.queue_free()
	
	for category in SECTION_ORDER:
		if not buildings_by_category.has(category):
			continue
		
		var header := Label.new()
		header.text = SECTION_DISPLAY_NAMES.get(category, category.to_upper())
		header.add_theme_font_size_override("font_size", 14)
		header.modulate = Color(0.7, 0.85, 1.0)
		content_vbox.add_child(header)
		
		for building_data in buildings_by_category[category]:
			var row := BuildingRowScene.instantiate()
			content_vbox.add_child(row)
			
			var building_id: String = building_data.id
			var recipes_for_this: Array = recipes_by_building.get(building_id, [])
			row.setup(building_data, recipes_for_this)
			row.recipe_selected.connect(_on_recipe_selected)
			row.expand_toggled.connect(_on_expand_toggled)
			row.infrastructure_build_pressed.connect(_on_infrastructure_build_pressed)  # NEW

func _on_recipe_selected(building_id: String, recipe_id: String) -> void:
	print("Recipe selected: %s for %s" % [recipe_id, building_id])
	BuildMode.enter_build_mode(building_id, recipe_id)

func _on_expand_toggled(building_id: String, is_expanded: bool) -> void:
	print("Expand toggled: ", building_id, " expanded=", is_expanded)




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
