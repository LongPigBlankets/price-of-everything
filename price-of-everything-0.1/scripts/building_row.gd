extends HBoxContainer

signal build_requested(building_id: String)
signal expand_toggled(building_id: String, is_expanded: bool)

@onready var icon_label: Label = $IconLabel
@onready var name_label: Label = $NameLabel
@onready var cost_label: Label = $CostLabel
@onready var materials_container: HBoxContainer = $MaterialsContainer
@onready var build_button: Button = $BuildButton
@onready var expand_button: Button = $ExpandButton

var building_id: String = ""
var is_expanded: bool = false

func setup(data: Dictionary) -> void:
	building_id = data.get("id", "")
	icon_label.text = data.get("icon", "•")  # placeholder character; swap for icon later
	name_label.text = data.get("name", "")
	cost_label.text = "£%s" % data.get("cost", "0")
	
	# Clear and populate material costs (up to 5 materials)
	for child in materials_container.get_children():
		child.queue_free()
	
	var materials: Array = data.get("materials", [])
	for mat in materials:
		var mat_label := Label.new()
		# First 3 chars of material name + quantity, e.g., "STE +5"
		var mat_name: String = mat.get("name", "")
		var mat_qty: int = mat.get("qty", 0)
		mat_label.text = "%s +%d" % [mat_name.substr(0, 3).to_upper(), mat_qty]
		materials_container.add_child(mat_label)
	
	build_button.text = "+"
	expand_button.text = "^"
	
	build_button.pressed.connect(_on_build_pressed)
	expand_button.pressed.connect(_on_expand_pressed)

func _on_build_pressed() -> void:
	build_requested.emit(building_id)

func _on_expand_pressed() -> void:
	is_expanded = not is_expanded
	expand_button.text = "v" if is_expanded else "^"
	expand_toggled.emit(building_id, is_expanded)
