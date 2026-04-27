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

var buildings_by_category: Dictionary = {}  # category -> Array of building data dicts

func _ready() -> void:
	close_button.pressed.connect(hide)
	title_label.text = "Construct Building"
	_load_buildings()
	_build_panel_content()

func _load_buildings() -> void:
	var path := "res://data/Buildings - buildingsMVP.csv"  # rename your CSV to remove the spaces
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

func _parse_building_row(headers: PackedStringArray, line: PackedStringArray) -> Dictionary:
	# Map columns by header name. Adjust to match your CSV's actual headers.
	var result := {}
	for i in headers.size():
		var key := headers[i].strip_edges().to_lower().replace(" ", "_")
		var val: String = line[i].strip_edges() if i < line.size() else ""
		result[key] = val
	
	# Build the materials array. Assumes columns named like
	# build_material_1, build_qty_1, build_material_2, build_qty_2, etc.
	var materials: Array = []
	for n in range(1, 6):  # support up to 5 materials
		var mat_name: String = result.get("build_material_%d" % n, "")
		var mat_qty_str: String = result.get("build_qty_%d" % n, "")
		if mat_name != "" and mat_qty_str != "":
			materials.append({"name": mat_name, "qty": int(mat_qty_str)})
	
	return {
		"id": result.get("id", ""),
		"name": result.get("display_name", result.get("name", "")),
		"cost": result.get("build_cost_money", "0"),
		"category": result.get("building_category", "production").to_lower(),
		"materials": materials,
		"icon": result.get("icon", "•"),
	}

func _build_panel_content() -> void:
	# Clear any existing children
	for child in content_vbox.get_children():
		child.queue_free()
	
	for category in SECTION_ORDER:
		if not buildings_by_category.has(category):
			continue
		
		# Section header
		var header := Label.new()
		header.text = SECTION_DISPLAY_NAMES.get(category, category.to_upper())
		header.add_theme_font_size_override("font_size", 14)
		header.modulate = Color(0.7, 0.85, 1.0)  # subtle blue tint
		content_vbox.add_child(header)
		
		# Rows for this section
		for building_data in buildings_by_category[category]:
			var row := BuildingRowScene.instantiate()
			content_vbox.add_child(row)
			row.setup(building_data)
			row.build_requested.connect(_on_build_requested)
			row.expand_toggled.connect(_on_expand_toggled)

func _on_build_requested(building_id: String) -> void:
	print("Build requested: ", building_id)
	BuildMode.enter_build_mode(building_id)

func _on_expand_toggled(building_id: String, is_expanded: bool) -> void:
	print("Expand toggled: ", building_id, " expanded=", is_expanded)
	# TODO: show/hide expanded detail content
