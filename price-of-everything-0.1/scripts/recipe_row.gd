extends MarginContainer

signal recipe_selected(building_id: String, recipe_id: String)

const OFF_WHITE := Color(0.995234, 0.930806, 0.763265)
const NAVY := Color(0.015686275, 0.058823529, 0.105882353)
const UNAFFORDABLE_FLASH_COLOR := Color(0.7, 0.12, 0.08, 0.5)
const GoodIcons := preload("res://scripts/good_icons.gd")
# Power output uses the same lightning the tile-panel recipe diagram shows.
const RECIPE_POWER_ICON := "res://assets/icons/ui_icons/recipe_power_icon.png"

@onready var output_icon: TextureRect = $Row/OutputIcon
@onready var name_label: Label = $Row/TextColumn/NameLabel
@onready var detail_label: Label = $Row/TextColumn/DetailLabel
@onready var power_box: PanelContainer = $Row/PowerBox
@onready var power_label: Label = $Row/PowerBox/PowerMargin/PowerLabel

var building_id: String = ""
var recipe_id: String = ""
var is_selected: bool = false
var is_affordable: bool = true
var _unaffordable_flash := false
var _card_style: StyleBoxFlat
var _selected_border: StyleBoxFlat
var _glow: GradientTexture2D

func _ready() -> void:
	_card_style = StyleBoxFlat.new()
	_card_style.bg_color = OFF_WHITE
	_card_style.set_corner_radius_all(0)
	_selected_border = StyleBoxFlat.new()
	_selected_border.bg_color = Color(0, 0, 0, 0)
	_selected_border.set_border_width_all(2)
	_selected_border.border_color = NAVY
	_selected_border.set_corner_radius_all(0)
	# Soft white glow that feathers outward from the goods icon.
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0.45), Color(1, 1, 1, 0.0)])
	_glow = GradientTexture2D.new()
	_glow.gradient = g
	_glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5, 0.5)
	_glow.fill_to = Vector2(1.0, 0.5)
	_glow.width = 96
	_glow.height = 96
	queue_redraw()

func setup(recipe_data: Dictionary, parent_building_id: String) -> void:
	building_id = parent_building_id
	recipe_id = recipe_data.get("recipe_id", "")
	name = "RecipeRow_%s" % str(recipe_id)   # tutorial spotlight target (e.g. RecipeRow_r_053)
	name_label.text = recipe_data.get("display_name", "")
	mouse_filter = Control.MOUSE_FILTER_STOP
	if not gui_input.is_connected(_on_row_gui_input):
		gui_input.connect(_on_row_gui_input)

	var output_gid: String = recipe_data.get("output_good_id", "")
	if Catalog.get_internal_name(output_gid) == "power":
		output_icon.texture = load(RECIPE_POWER_ICON)
	else:
		output_icon.texture = GoodIcons.texture_for(output_gid, recipe_data.get("output_name", ""), true)

	var parts: Array = []
	for inp in recipe_data.get("inputs", []):
		parts.append("%d %s" % [int(inp.get("qty", 0)), _good_label(inp.get("good_id", ""), inp.get("internal_name", ""))])
	var inputs_str: String = ", ".join(parts) if parts.size() > 0 else "raw extraction"
	detail_label.text = "%s  →  %d %s" % [
		inputs_str, int(recipe_data.get("output_qty", 0)),
		_good_label(recipe_data.get("output_good_id", ""), recipe_data.get("output_name", ""))]

	var energy: int = int(recipe_data.get("energy_req", 0))
	power_box.visible = energy != 0
	power_label.text = "⚡%d" % energy
	_update_visual_state()
	queue_redraw()

func _good_label(good_id: String, internal_name: String) -> String:
	if good_id != "":
		return Catalog.get_display_name(good_id)
	return String(internal_name).capitalize()

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
	queue_redraw()

func set_affordable(value: bool) -> void:
	is_affordable = value
	_update_visual_state()

func _update_visual_state() -> void:
	modulate = Color(1, 1, 1, 0.5) if not is_affordable else Color(1, 1, 1, 1)
	queue_redraw()

func _draw() -> void:
	if _card_style == null:
		return
	# Off-white card.
	draw_style_box(_card_style, Rect2(Vector2.ZERO, size))
	# Feather glow radiating from the goods icon.
	var icon_c := Vector2(39.0, size.y * 0.5)
	var r := size.y * 1.5
	draw_texture_rect(_glow, Rect2(icon_c - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), false)
	# States.
	if _unaffordable_flash:
		draw_rect(Rect2(Vector2.ZERO, size), UNAFFORDABLE_FLASH_COLOR, true)
	elif is_selected:
		# Confident navy border, inset from the white edge.
		draw_style_box(_selected_border, Rect2(Vector2(4, 4), size - Vector2(8, 8)))

func _flash_unaffordable() -> void:
	_unaffordable_flash = true
	queue_redraw()
	await get_tree().create_timer(0.14).timeout
	_unaffordable_flash = false
	queue_redraw()
