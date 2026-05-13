extends PanelContainer

@onready var title_label: Label = $MarginContainer/VBoxContainer/HeaderRow/TitleLabel
@onready var close_button: Button = $MarginContainer/VBoxContainer/HeaderRow/CloseButton
@onready var location_label: Label = $MarginContainer/VBoxContainer/LocationLabel
@onready var flow_summary: PanelContainer = $MarginContainer/VBoxContainer/FlowSummary
@onready var flow_frame: PanelContainer = $MarginContainer/VBoxContainer/FlowSummary/FlowInset/FlowFrame
@onready var flow_row: HBoxContainer = $MarginContainer/VBoxContainer/FlowSummary/FlowInset/FlowFrame/FlowRow
@onready var input_preview: VBoxContainer = $MarginContainer/VBoxContainer/FlowSummary/FlowInset/FlowFrame/FlowRow/InputPreview
@onready var input_grid: GridContainer = $MarginContainer/VBoxContainer/FlowSummary/FlowInset/FlowFrame/FlowRow/InputPreview/InputGrid
@onready var output_preview: VBoxContainer = $MarginContainer/VBoxContainer/FlowSummary/FlowInset/FlowFrame/FlowRow/OutputPreview
@onready var output_grid: GridContainer = $MarginContainer/VBoxContainer/FlowSummary/FlowInset/FlowFrame/FlowRow/OutputPreview/OutputGrid
@onready var flow_arrow: TextureRect = $MarginContainer/VBoxContainer/FlowSummary/FlowInset/FlowFrame/FlowRow/FlowArrow
@onready var status_icon_column: VBoxContainer = $MarginContainer/VBoxContainer/ContentRow/StatusIconColumn
@onready var fields_vbox: VBoxContainer = $MarginContainer/VBoxContainer/ContentRow/ScrollContainer/FieldsVBox

const HEADER_HEIGHT := 40.0
const PANEL_EDGE_MARGIN := 20.0
const STATUS_ICON_SIZE := Vector2(24, 24)
const STATUS_DOT_SIZE := Vector2(10, 10)
const FLOW_COMPACT_HEIGHT := 130.0
const FLOW_LARGE_HEIGHT := 130.0
const FLOW_SINGLE_CELL_SIZE := Vector2(110, 110)
const FLOW_GRID_CELL_SIZE := Vector2(55, 55)
const GOODS_ICON_DIR := "res://assets/icons/goods/small"
const RECIPE_ARROW_PATH := "res://assets/icons/ui_icons/recipe_arrow.png"
const RECIPE_POWER_ICON_PATH := "res://assets/icons/ui_icons/recipe_power_icon.png"
const FLOW_ARROW_COMPACT_SIZE := Vector2(130, 60)
const FLOW_ARROW_LARGE_SIZE := Vector2(130, 60)
const FLOW_BADGE_DIAMETER := 24
const FLOW_BADGE_TEXT_SIZE := 14
const STATUS_GREEN := Color(0.2, 0.75, 0.25)
const STATUS_RED := Color(0.85, 0.15, 0.12)
const STATUS_GREY := Color(0.45, 0.48, 0.52)
const STATUS_YELLOW := Color(0.95, 0.78, 0.18)
const ICON_TINT := Color(0.92, 0.90, 0.82)
const TOOLTIP_NAVY := Color(0.03, 0.07, 0.13)
const DIAGRAM_NAVY := Color(0.0, 0.119856, 0.243095, 1.0)
const DIAGRAM_PAPER := Color(0.9725, 0.9333, 0.8431, 1.0)
const FLOW_SQUARE_COLOR := Color(1.0, 1.0, 1.0)

const STATUS_ICON_CONFIG := [
	{
		"key": "power",
		"path": "res://assets/icons/ui_icons/power_status_icon.png",
		"tooltip": "Power status",
	},
	{
		"key": "input",
		"path": "res://assets/icons/ui_icons/input_status_icon.png",
		"tooltip": "Input status",
	},
	{
		"key": "duration",
		"path": "res://assets/icons/ui_icons/input_transport_duration_icon.png",
		"tooltip": "Input transport duration",
	},
	{
		"key": "cost",
		"path": "res://assets/icons/ui_icons/cost_of_transport_icon.png",
		"tooltip": "Cost of transport",
	},
]

var _dragging := false
var _drag_offset := Vector2.ZERO
var _status_dots: Dictionary = {}
var _tooltip_theme: Theme = null

func _ready() -> void:
	close_button.pressed.connect(hide)
	_tooltip_theme = _make_tooltip_theme()
	_style_flow_summary()
	_build_status_icon_column()

func show_building(building: Dictionary) -> void:
	_rebuild_fields(building)
	visible = true
	_position_for_visible_panels()

func _rebuild_fields(building: Dictionary) -> void:
	for child in fields_vbox.get_children():
		child.queue_free()
	
	var building_data: Dictionary = Catalog.get_building(building.get("building_id", ""))
	var recipe: Dictionary = Catalog.get_recipe(building.get("recipe_id", ""))
	var category: String = building_data.get("category", "")
	var is_infrastructure: bool = category == "infrastructure"
	
	title_label.text = _building_display_name(building, building_data, recipe)
	location_label.text = _format_location(building)
	_update_flow_summary(recipe)
	_update_status_icons(building, recipe, is_infrastructure)
	_add_field("Value", _money_text(building_data.get("base_price", 0.0)))
	
	if not is_infrastructure and recipe.get("output_name", "") == "power":
		_add_field("Power production", str(recipe.get("output_qty", 0)))
	
	
	_add_field("Maintenance cost", _money_text(_maintenance_cost(building_data)))
	_add_field("Labour cost", _money_text(_labour_cost(building_data)))
	
	if not is_infrastructure and recipe.get("output_name", "") != "power":
		_add_field("Output destination", _output_destination())

func _add_text(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fields_vbox.add_child(label)

func _add_field(field_name: String, value: String) -> void:
	_add_text("%s: %s" % [field_name, value])

func _style_flow_summary() -> void:
	var summary_style := StyleBoxFlat.new()
	summary_style.bg_color = DIAGRAM_PAPER
	flow_summary.add_theme_stylebox_override("panel", summary_style)
	
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(1.0, 1.0, 1.0, 0.0)
	frame_style.border_width_left = 1
	frame_style.border_width_top = 1
	frame_style.border_width_right = 1
	frame_style.border_width_bottom = 1
	frame_style.border_color = DIAGRAM_NAVY
	frame_style.content_margin_left = 8
	frame_style.content_margin_top = 0
	frame_style.content_margin_right = 8
	frame_style.content_margin_bottom = 0
	flow_frame.add_theme_stylebox_override("panel", frame_style)
	
	flow_arrow.texture = load(RECIPE_ARROW_PATH)
	flow_arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	flow_arrow.stretch_mode = TextureRect.STRETCH_SCALE
	flow_arrow.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _update_flow_summary(recipe: Dictionary) -> void:
	var inputs: Array = recipe.get("inputs", [])
	var outputs: Array = _flow_output_items(recipe)
	var large_layout: bool = inputs.size() >= 2 or outputs.size() >= 2
	_resize_flow_summary(large_layout)
	_populate_flow_grid(input_grid, inputs)
	_populate_flow_grid(output_grid, outputs)
	_update_flow_power(recipe)

func _resize_flow_summary(large_layout: bool) -> void:
	var height := FLOW_LARGE_HEIGHT if large_layout else FLOW_COMPACT_HEIGHT
	flow_summary.custom_minimum_size = Vector2(0, height)
	input_preview.custom_minimum_size = Vector2(0, height)
	output_preview.custom_minimum_size = Vector2(0, height)
	flow_arrow.custom_minimum_size = FLOW_ARROW_LARGE_SIZE if large_layout else FLOW_ARROW_COMPACT_SIZE
	flow_arrow.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _populate_flow_grid(grid: GridContainer, goods: Array) -> void:
	for child in grid.get_children():
		child.queue_free()
	
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("v_separation", 0)
	var count: int = max(goods.size(), 1)
	grid.columns = 2 if count > 2 else 1
	var cell_size := _flow_cell_size(goods.size())
	
	if goods.is_empty():
		grid.add_child(_make_flow_cell({}, cell_size))
		return
	
	for good_item in goods:
		grid.add_child(_make_flow_cell(good_item, cell_size))

func _flow_cell_size(good_count: int) -> Vector2:
	if good_count <= 1:
		return FLOW_SINGLE_CELL_SIZE
	return FLOW_GRID_CELL_SIZE

func _make_flow_cell(good_item: Dictionary, cell_size: Vector2) -> Panel:
	var cell := Panel.new()
	cell.custom_minimum_size = cell_size
	var texture: Texture2D = _load_good_texture(good_item)
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 1.0, 0.0) if texture != null else FLOW_SQUARE_COLOR
	cell.add_theme_stylebox_override("panel", style)
	
	if texture != null:
		var texture_rect := TextureRect.new()
		texture_rect.texture = texture
		texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(texture_rect)
	
	_add_flow_quantity_badge(cell, good_item, cell_size)
	
	return cell

func _add_flow_quantity_badge(cell: Panel, good_item: Dictionary, cell_size: Vector2) -> void:
	if not _should_show_quantity_badge(good_item):
		return
	
	var qty := _badge_quantity(good_item)
	if qty <= 0:
		return
	
	var qty_text := str(qty)
	var badge_height: int = FLOW_BADGE_DIAMETER
	var badge_width: int = badge_height
	if qty_text.length() > 1:
		badge_width = max(badge_height, (qty_text.length() * 9) + 14)
	
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(badge_width, badge_height)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	var overlap: int = max(4, roundi(min(cell_size.x, cell_size.y) * 0.10))
	badge.offset_left = -badge_width + overlap
	badge.offset_top = -badge_height + overlap
	badge.offset_right = overlap
	badge.offset_bottom = overlap
	
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = DIAGRAM_NAVY
	badge_style.border_color = DIAGRAM_PAPER
	badge_style.border_width_left = 2
	badge_style.border_width_top = 2
	badge_style.border_width_right = 2
	badge_style.border_width_bottom = 2
	var radius: int = int(badge_height / 2.0)
	badge_style.corner_radius_top_left = radius
	badge_style.corner_radius_top_right = radius
	badge_style.corner_radius_bottom_left = radius
	badge_style.corner_radius_bottom_right = radius
	badge_style.content_margin_left = 0
	badge_style.content_margin_top = 0
	badge_style.content_margin_right = 0
	badge_style.content_margin_bottom = 0
	badge.add_theme_stylebox_override("panel", badge_style)
	
	var label_settings := LabelSettings.new()
	label_settings.font_color = DIAGRAM_PAPER
	label_settings.font_size = FLOW_BADGE_TEXT_SIZE
	
	var label := Label.new()
	label.text = qty_text
	label.custom_minimum_size = Vector2(badge_width, badge_height)
	label.label_settings = label_settings
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(label)
	cell.add_child(badge)

func _update_flow_power(recipe: Dictionary) -> void:
	for child in flow_arrow.get_children():
		child.queue_free()
	
	var energy_req: int = recipe.get("energy_req", 0)
	if energy_req <= 0:
		return
	
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(50, 30)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.anchor_left = 0.5
	badge.anchor_top = 0.5
	badge.anchor_right = 0.5
	badge.anchor_bottom = 0.5
	badge.offset_left = -25
	badge.offset_top = -15
	badge.offset_right = 25
	badge.offset_bottom = 15
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = DIAGRAM_NAVY
	badge_style.content_margin_left = 4
	badge_style.content_margin_top = 0
	badge_style.content_margin_right = 4
	badge_style.content_margin_bottom = 0
	badge.add_theme_stylebox_override("panel", badge_style)
	flow_arrow.add_child(badge)
	
	var overlay := HBoxContainer.new()
	overlay.alignment = BoxContainer.ALIGNMENT_CENTER
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_theme_constant_override("separation", 2)
	badge.add_child(overlay)
	
	var label_settings := LabelSettings.new()
	label_settings.font_color = DIAGRAM_PAPER
	label_settings.font_size = 20
	
	var label := Label.new()
	label.text = str(energy_req)
	label.label_settings = label_settings
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(label)
	
	var icon := TextureRect.new()
	icon.texture = load(RECIPE_POWER_ICON_PATH)
	icon.custom_minimum_size = Vector2(20, 20)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(icon)

func _should_show_quantity_badge(good_item: Dictionary) -> bool:
	if good_item.is_empty():
		return false
	var item_type: String = str(good_item.get("type", "")).to_lower()
	if item_type == "deposit":
		return false
	var internal_name: String = str(good_item.get("internal_name", "")).to_lower()
	if internal_name.contains("deposit"):
		return false
	return not ["solar", "wind", "solar_potential", "wind_potential"].has(internal_name)

func _badge_quantity(good_item: Dictionary) -> int:
	if good_item.has("qty"):
		return roundi(float(good_item.get("qty", 0)))
	if good_item.has("quantity"):
		return roundi(float(good_item.get("quantity", 0)))
	if good_item.has("output_qty"):
		return roundi(float(good_item.get("output_qty", 0)))
	return 0

func _load_good_texture(good_item: Dictionary) -> Texture2D:
	var good_id: String = good_item.get("good_id", "")
	var internal_name: String = good_item.get("internal_name", "")
	if good_id == "" or internal_name == "":
		return null
	
	var paths: Array = [
		"%s/%s_%s.svg" % [GOODS_ICON_DIR, good_id, internal_name],
		"%s/%s_%s.SVG" % [GOODS_ICON_DIR, good_id, internal_name],
		"%s/%s_%s.PNG" % [GOODS_ICON_DIR, good_id, internal_name],
		"%s/%s_%s.png" % [GOODS_ICON_DIR, good_id, internal_name],
		"%s/%s.svg" % [GOODS_ICON_DIR, good_id],
		"%s/%s.SVG" % [GOODS_ICON_DIR, good_id],
		"%s/%s.PNG" % [GOODS_ICON_DIR, good_id],
		"%s/%s.png" % [GOODS_ICON_DIR, good_id],
	]
	for path in paths:
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null

func _flow_output_items(recipe: Dictionary) -> Array:
	if recipe.has("outputs"):
		var outputs: Array = recipe.get("outputs", [])
		return outputs
	
	var output_name: String = recipe.get("output_name", "")
	var output_qty: int = recipe.get("output_qty", 0)
	if output_name == "" or output_qty <= 0:
		return []
	return [{
		"good_id": recipe.get("output_good_id", ""),
		"internal_name": output_name,
		"qty": output_qty,
	}]

func _build_status_icon_column() -> void:
	for child in status_icon_column.get_children():
		child.queue_free()
	_status_dots.clear()
	
	for config in STATUS_ICON_CONFIG:
		var key: String = config.get("key", "")
		var icon_path: String = config.get("path", "")
		var tooltip: String = config.get("tooltip", "")
		var wrapper := HBoxContainer.new()
		wrapper.alignment = BoxContainer.ALIGNMENT_END
		wrapper.theme = _tooltip_theme
		wrapper.tooltip_text = tooltip
		wrapper.mouse_filter = Control.MOUSE_FILTER_STOP
		wrapper.add_theme_constant_override("separation", 4)
		
		var icon := TextureRect.new()
		icon.custom_minimum_size = STATUS_ICON_SIZE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = load(icon_path)
		icon.modulate = ICON_TINT
		icon.tooltip_text = tooltip
		icon.theme = _tooltip_theme
		wrapper.add_child(icon)
		
		var dot := Panel.new()
		dot.custom_minimum_size = STATUS_DOT_SIZE
		dot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.tooltip_text = tooltip
		dot.theme = _tooltip_theme
		wrapper.add_child(dot)
		_status_dots[key] = dot
		
		status_icon_column.add_child(wrapper)

func _update_status_icons(building: Dictionary, recipe: Dictionary, is_infrastructure: bool) -> void:
	_set_status_dot("power", _power_status_color(building, recipe, is_infrastructure))
	_set_status_dot("input", _input_status_color(building, recipe, is_infrastructure))
	_set_status_dot("duration", STATUS_GREEN)
	_set_status_dot("cost", STATUS_GREEN)

func _set_status_dot(key: String, color: Color) -> void:
	if not _status_dots.has(key):
		return
	var dot: Panel = _status_dots[key]
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	dot.add_theme_stylebox_override("panel", style)

func _make_tooltip_theme() -> Theme:
	var theme := Theme.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = TOOLTIP_NAVY
	panel_style.set_content_margin_all(6)
	theme.set_stylebox("panel", "TooltipPanel", panel_style)
	theme.set_color("font_color", "TooltipLabel", ICON_TINT)
	return theme

func _power_status_color(building: Dictionary, recipe: Dictionary, is_infrastructure: bool) -> Color:
	if is_infrastructure:
		return STATUS_GREY
	var energy_req: int = recipe.get("energy_req", 0)
	var produces_power: bool = recipe.get("output_name", "") == "power"
	if energy_req <= 0 and not produces_power:
		return STATUS_GREY
	if not Power.is_supplied(building.get("tile_id", ""), energy_req):
		return STATUS_RED
	return STATUS_GREEN if _power_supply(building) == "Owned Supply" else STATUS_YELLOW

func _input_status_color(building: Dictionary, recipe: Dictionary, is_infrastructure: bool) -> Color:
	if is_infrastructure:
		return STATUS_GREY
	var instance_id: String = building.get("instance_id", "")
	if instance_id != "" and Production.missing_by_building.has(instance_id):
		return STATUS_RED
	var inputs: Array = recipe.get("inputs", [])
	if inputs.is_empty():
		return STATUS_GREEN
	for input in inputs:
		if Stockpile.get_total(input.get("good_id", "")) < input.get("qty", 0):
			return STATUS_RED
	return STATUS_YELLOW

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

func _maintenance_cost(building_data: Dictionary) -> float:
	var value = building_data.get("maintenance_cost", 0.0)
	if value == null:
		return 0.0
	return float(value)

func _labour_cost(building_data: Dictionary) -> float:
	var base_cost: float = (
		building_data.get("labour_unskilled_required", 0) * EconomyConfig.LABOUR_UNSKILLED_RATE
		+ building_data.get("labour_skilled_required", 0) * EconomyConfig.LABOUR_SKILLED_RATE
		+ building_data.get("labour_h_skilled_required", 0) * EconomyConfig.LABOUR_HIGH_SKILLED_RATE
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

func _money_text(value: float) -> String:
	return "£%s" % _format_money(value)

func _position_for_visible_panels() -> void:
	if custom_minimum_size.x > 0.0 and custom_minimum_size.y > 0.0:
		size = custom_minimum_size
	var panel_size := size
	if panel_size.x <= 0.0:
		panel_size.x = custom_minimum_size.x
	if panel_size.y <= 0.0:
		panel_size.y = custom_minimum_size.y
	
	var viewport_size := get_viewport().get_visible_rect().size
	var right_edge := viewport_size.x - PANEL_EDGE_MARGIN
	var top_edge := PANEL_EDGE_MARGIN
	
	var hud := get_parent().get_parent()
	if hud != null:
		var top_bar := hud.get_node_or_null("TopBar") as Control
		if top_bar != null and top_bar.visible:
			top_edge = top_bar.global_position.y + top_bar.size.y + PANEL_EDGE_MARGIN
	
	var tile_panel := get_parent().get_node_or_null("TileInfoPanel") as Control
	if tile_panel != null and tile_panel.visible:
		right_edge = tile_panel.global_position.x - PANEL_EDGE_MARGIN
	
	var x := clampf(right_edge - panel_size.x, PANEL_EDGE_MARGIN, viewport_size.x - panel_size.x - PANEL_EDGE_MARGIN)
	var y := clampf(top_edge, PANEL_EDGE_MARGIN, viewport_size.y - panel_size.y - PANEL_EDGE_MARGIN)
	global_position = Vector2(x, y)

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
