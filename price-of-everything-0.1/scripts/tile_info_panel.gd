extends PanelContainer

@onready var title_label: Label = $MarginContainer/VBoxContainer/HeaderRow/TitleLabel
@onready var close_button: Button = $MarginContainer/VBoxContainer/HeaderRow/CloseButton
@onready var property_table: GridContainer = $MarginContainer/VBoxContainer/PropertyTable
@onready var buildings_header: Label = $MarginContainer/VBoxContainer/BuildingsHeader
@onready var buildings_list: VBoxContainer = $MarginContainer/VBoxContainer/BuildingsList

signal building_clicked(building_name: String)

const DISPLAY_FIELDS := [
	"id", "nickname", "type", "deposits",
	"solar_potential", "wind_potential",
	"build_capacity", "tile_price", "infrastructure_present",
]

const FIELD_LABELS := {
	"id": "ID",
	"nickname": "Nickname",
	"type": "Type",
	"deposits": "Deposits",
	"solar_potential": "Solar Potential",
	"wind_potential": "Wind Potential",
	"build_capacity": "Build Capacity",
	"tile_price": "Tile Price",
	"infrastructure_present": "Infrastructure",
}

func _ready() -> void:
	close_button.pressed.connect(hide)

func show_tile(tile_data: Dictionary) -> void:
	title_label.text = tile_data.nickname if tile_data.nickname != "" else tile_data.id
	_rebuild_table(tile_data)
	_rebuild_buildings(tile_data)
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
	for child in buildings_list.get_children():
		child.queue_free()

	var buildings: Array = tile_data.get("buildings_present", [])

	if buildings.is_empty():
		buildings_header.visible = false
		buildings_list.visible = false
		return

	buildings_header.visible = true
	buildings_list.visible = true

	for building_name in buildings:
		buildings_list.add_child(_make_building_button(building_name))

func _make_building_button(building_name: String) -> Button:
	var btn := Button.new()
	btn.text = building_name
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	# 10px padding on every side, achieved via theme constant overrides
	btn.add_theme_constant_override("h_separation", 10)
	# Stylebox padding gives the actual clickable inset
	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = Color(0.18, 0.22, 0.28)
	style_normal.set_content_margin_all(10)
	style_normal.corner_radius_top_left = 3
	style_normal.corner_radius_top_right = 3
	style_normal.corner_radius_bottom_left = 3
	style_normal.corner_radius_bottom_right = 3
	btn.add_theme_stylebox_override("normal", style_normal)

	var style_hover := style_normal.duplicate()
	style_hover.bg_color = Color(0.25, 0.30, 0.38)
	btn.add_theme_stylebox_override("hover", style_hover)

	var style_pressed := style_normal.duplicate()
	style_pressed.bg_color = Color(0.30, 0.36, 0.45)
	btn.add_theme_stylebox_override("pressed", style_pressed)

	btn.pressed.connect(func(): building_clicked.emit(building_name))
	return btn

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

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		print(">>> TileInfoPanel received click at ", event.position)
		accept_event()
