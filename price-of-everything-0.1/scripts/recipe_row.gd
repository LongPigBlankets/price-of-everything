extends HBoxContainer

signal recipe_selected(building_id: String, recipe_id: String)

@onready var name_label: Label = $NameLabel
@onready var details_label: Label = $DetailsLabel
@onready var power_label: Label = $PowerLabel
@onready var build_button: Button = $BuildButton

var building_id: String = ""
var recipe_id: String = ""

func setup(recipe_data: Dictionary, parent_building_id: String) -> void:
	building_id = parent_building_id
	recipe_id = recipe_data.recipe_id
	name_label.text = recipe_data.display_name
	
	var input_strs: Array = []
	for inp in recipe_data.inputs:
		input_strs.append("%s+%d" % [inp.name.substr(0, 3).to_upper(), inp.qty])
	var inputs_str: String = ", ".join(input_strs) if input_strs.size() > 0 else "none"
	var output_str := "→%s+%d" % [recipe_data.output_name.substr(0, 3).to_upper(), recipe_data.output_qty]
	details_label.text = "%s  %s" % [inputs_str, output_str]
	
	power_label.text = "pwr:%d" % recipe_data.energy_req
	
	build_button.text = "+"
	build_button.pressed.connect(_on_build_pressed)

func _on_build_pressed() -> void:
	recipe_selected.emit(building_id, recipe_id)
