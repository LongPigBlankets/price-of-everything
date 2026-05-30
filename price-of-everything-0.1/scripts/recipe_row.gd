extends HBoxContainer

signal recipe_selected(building_id: String, recipe_id: String)

const SELECTED_COLOR := Color(0.18, 0.52, 0.8, 0.65)
const UNAFFORDABLE_COLOR := Color(0.12, 0.12, 0.12, 0.25)
const UNAFFORDABLE_FLASH_COLOR := Color(0.7, 0.12, 0.08, 0.48)
const GoodIcons := preload("res://scripts/good_icons.gd")

@onready var icon_texture: TextureRect = $OutputIcon/IconTexture
@onready var name_label: Label = $TextColumn/NameLabel
@onready var detail_label: Label = $TextColumn/DetailLabel

var building_id: String = ""
var recipe_id: String = ""
var is_selected: bool = false
var is_affordable: bool = true
var _unaffordable_flash := false

func setup(recipe_data: Dictionary, parent_building_id: String) -> void:
	building_id = parent_building_id
	recipe_id = recipe_data.get("recipe_id", "")
	name_label.text = recipe_data.get("display_name", "")
	mouse_filter = Control.MOUSE_FILTER_STOP
	if not gui_input.is_connected(_on_row_gui_input):
		gui_input.connect(_on_row_gui_input)

	# Output good icon (placeholder panel shows when a good has no art yet).
	var out_good_id: String = recipe_data.get("output_good_id", "")
	var out_internal: String = recipe_data.get("output_name", "")
	icon_texture.texture = GoodIcons.texture_for(out_good_id, out_internal)

	# Detail line: inputs -> output xqty   energy.
	var parts: Array = []
	for inp in recipe_data.get("inputs", []):
		parts.append("%d %s" % [int(inp.get("qty", 0)), _good_label(inp.get("good_id", ""), inp.get("internal_name", ""))])
	var inputs_str: String = ", ".join(parts) if parts.size() > 0 else "raw extraction"
	var detail: String = "%s  →  %d %s" % [
		inputs_str, int(recipe_data.get("output_qty", 0)), _good_label(out_good_id, out_internal)]
	var energy: int = int(recipe_data.get("energy_req", 0))
	if energy != 0:
		detail += "    ⚡%d" % energy
	detail_label.text = detail
	_update_visual_state()

func _good_label(good_id: String, internal_name: String) -> String:
	if good_id != "":
		return Catalog.get_display_name(good_id)
	return internal_name.capitalize()

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
	icon_texture.modulate = Color(1, 1, 1, dim)
	name_label.modulate = Color(1, 1, 1, dim)
	detail_label.modulate = Color(1, 1, 1, dim)
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
