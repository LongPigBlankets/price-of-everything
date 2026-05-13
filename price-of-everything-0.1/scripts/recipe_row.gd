extends HBoxContainer

signal recipe_selected(building_id: String, recipe_id: String)

const SELECTED_COLOR := Color(0.18, 0.52, 0.8, 0.65)
const UNAFFORDABLE_COLOR := Color(0.12, 0.12, 0.12, 0.25)
const UNAFFORDABLE_FLASH_COLOR := Color(0.7, 0.12, 0.08, 0.48)

@onready var name_label: Label = $NameLabel
@onready var details_label: Label = $DetailsLabel
@onready var power_label: Label = $PowerLabel
@onready var build_button: Button = $BuildButton

var building_id: String = ""
var recipe_id: String = ""
var is_selected: bool = false
var is_affordable: bool = true
var _unaffordable_flash := false

func setup(recipe_data: Dictionary, parent_building_id: String) -> void:
	building_id = parent_building_id
	recipe_id = recipe_data.recipe_id
	name_label.text = recipe_data.display_name
	mouse_filter = Control.MOUSE_FILTER_STOP
	if not gui_input.is_connected(_on_row_gui_input):
		gui_input.connect(_on_row_gui_input)

	var input_strs: Array = []
	for inp in recipe_data.inputs:
		input_strs.append("%s+%d" % [inp.name.substr(0, 3).to_upper(), inp.qty])
	var inputs_str: String = ", ".join(input_strs) if input_strs.size() > 0 else "none"
	var output_str := "->%s+%d" % [recipe_data.output_name.substr(0, 3).to_upper(), recipe_data.output_qty]
	details_label.text = "%s  %s" % [inputs_str, output_str]

	power_label.text = "pwr:%d" % recipe_data.energy_req
	build_button.visible = false
	if not build_button.pressed.is_connected(_on_build_pressed):
		build_button.pressed.connect(_on_build_pressed)
	_update_visual_state()

func _on_build_pressed() -> void:
	_on_row_pressed()

func _on_row_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_on_row_pressed()
		accept_event()

func _on_row_pressed() -> void:
	if not is_affordable:
		_flash_unaffordable()
		return
	recipe_selected.emit(building_id, recipe_id)

func set_selected(value: bool) -> void:
	is_selected = value
	_update_visual_state()

func set_affordable(value: bool) -> void:
	is_affordable = value
	_update_visual_state()

func _update_visual_state() -> void:
	var dim := 0.45 if not is_affordable else 1.0
	name_label.modulate = Color(1, 1, 1, dim)
	details_label.modulate = Color(1, 1, 1, dim)
	power_label.modulate = Color(1, 1, 1, dim)
	queue_redraw()

func _draw() -> void:
	if _unaffordable_flash:
		draw_rect(Rect2(Vector2.ZERO, size), UNAFFORDABLE_FLASH_COLOR, true)
	elif is_selected:
		draw_rect(Rect2(Vector2.ZERO, size), SELECTED_COLOR, true)
	elif not is_affordable:
		draw_rect(Rect2(Vector2.ZERO, size), UNAFFORDABLE_COLOR, true)

func _flash_unaffordable() -> void:
	_unaffordable_flash = true
	queue_redraw()
	await get_tree().create_timer(0.14).timeout
	_unaffordable_flash = false
	queue_redraw()
