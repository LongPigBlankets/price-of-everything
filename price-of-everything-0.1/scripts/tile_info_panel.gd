extends PanelContainer

@onready var title_label: Label = $MarginContainer/ContentRow/VBoxContainer/HeaderRow/TitleLabel
@onready var close_button: Button = $MarginContainer/ContentRow/VBoxContainer/HeaderRow/CloseButton
@onready var infrastructure_separator: HSeparator = $MarginContainer/ContentRow/ChartColumn/InfrastructureSeparator
@onready var infrastructure_table: GridContainer = $MarginContainer/ContentRow/ChartColumn/InfrastructureTable
@onready var content_vbox: VBoxContainer = $MarginContainer/ContentRow/VBoxContainer
@onready var tile_size_chart = $MarginContainer/ContentRow/ChartColumn/TileSizeChart
@onready var tile_image_banner: PanelContainer = $MarginContainer/ContentRow/VBoxContainer/TileImageBanner
@onready var _content_row: HBoxContainer = $MarginContainer/ContentRow
@onready var _margin_container: MarginContainer = $MarginContainer

signal building_clicked(building: Dictionary)

const STOCKPILE_VIEW_SCRIPT := preload("res://scripts/stockpile_view.gd")
const INFRA_GRID_SCRIPT := preload("res://scripts/infra_grid.gd")

const HEADER_HEIGHT := 40.0
var OFF_WHITE: Color = DS.PALETTE.ACCENT
const CONTROL_ROW_HEIGHT := 34.0
const CONTROL_ROW_TALL_HEIGHT := 48.0
const CONTROL_LABEL_FONT_SIZE := 13
const CONTROL_LABEL_RATIO := 6.0
const CONTROL_CONTROL_RATIO := 3.0
const CONTROL_SPACER_RATIO := 1.0
const CHECKBOX_ICON_SIZE := 16
const CHART_CONTROL_SIZE := Vector2(336, 360)
const RURAL_TILE_BANNER_PATH := "res://assets/tile_banners/rural_banner.jpg"
const PLUS_ICON_PATH := "res://assets/icons/ui_icons/plus_off_white.png"
const TILE_MODAL_FRAME_PATH := "res://assets/ui/tile_modal_pipe_frame.png"
const TILE_MODAL_FRAME_SLICE := 32.0
const TILE_MODAL_FRAME_OUTSET := 11.0
const TILE_MODAL_CONTENT_MARGIN := 20
const INFRA_GRID_WIDTH := 283.0
const INFRA_CELL_DEFAULT_SIZE := Vector2(87, 86)
const INFRA_CELL_WIDTHS := {
	"roads": 72.0,
	"rails": 62.0,
	"pipes": 98.0,
	"reinf_pipes": 108.0,
}
const INFRA_LABEL_FONT_SIZE := 14
const INFRA_LABEL_MAX_CHARS := 15
# Colours sourced from the DS design system (see ds.gd). These are `var` (not
# `const`) because DS.PALETTE is an autoload value resolved at runtime.
var SUMMARY_PANEL_BG: Color = Color(DS.PALETTE.BG_PANEL, 0.78)
var SUMMARY_PANEL_BORDER: Color = DS.PALETTE.BORDER_SOFT
var SUMMARY_SUBTLE_TEXT: Color = DS.PALETTE.TEXT_MUTED
var SUMMARY_GREEN: Color = DS.PALETTE.OK
var SUMMARY_AMBER: Color = DS.PALETTE.WARN
var SUMMARY_RED: Color = DS.PALETTE.DANGER
var SUMMARY_MUTED: Color = DS.PALETTE.TEXT_DIM
const PRODUCTION_ROW_HEIGHT := 24.0
const TILE_TYPE_SUMMARY_HEIGHT := 20.0
const TILE_TYPE_SUMMARY_FONT_SIZE := 10
const BASE_TILE_SIZE_CAPACITY := 200
const UI_ABBREVIATION_SETTING_THRESHOLD := 30
const UI_ABBREVIATION_RULES := [
	["High Voltage Cables", "HVDC", "HVDC", "HVDC"],
	["Reinforced", "Reinf.", "reinf.", "REINF."],
	["Construction", "Constr.", "constr.", "CONSTR."],
	["Partially", "Part.", "part.", "PART."],
	["Maintenance", "Maint.", "maint.", "MAINT."],
	["Destination", "Dest.", "dest.", "DEST."],
	["Production", "Prod.", "prod.", "PROD."],
	["Industrial", "Ind.", "ind.", "IND."],
]

var _current_tile_data: Dictionary = {}
var _current_tile_id: String = ""
var _dragging := false
var _drag_offset := Vector2.ZERO
var _stockpile_view: VBoxContainer = null
var _infra_grid = null
var _stockpile_sell_button: Button = null
var _sell_surplus_button: CheckBox = null
var _production_destination_option: OptionButton = null
@onready var _chart_column: VBoxContainer = $MarginContainer/ContentRow/ChartColumn
var _land_left_label: Label = null
var _land_purchase_buttons_row: HBoxContainer = null
var _land_buy_one_button: Button = null
var _land_buy_all_button: Button = null
var _land_buildings_for_sale_button: Button = null
var _plus_icon_texture: Texture2D = null
var _checkbox_checked_icon_texture: Texture2D = null
var _checkbox_unchecked_icon_texture: Texture2D = null
var _tile_modal_frame_texture: Texture2D = null
var _rural_tile_banner_texture: Texture2D = null
var _tile_banner_texture_rect: TextureRect = null
var _banner_summary_wrapper: PanelContainer = null
var _banner_summary_content: VBoxContainer = null
var _tile_type_summary_row: HBoxContainer = null
var _tile_type_summary_label: Label = null
var _tile_deposits_summary_label: Label = null
var _survey_status_button: Button = null
var _right_scroll: ScrollContainer = null
var _right_scroll_content: VBoxContainer = null
var _power_section_content: VBoxContainer = null
var _production_section_content: VBoxContainer = null
var _building_icon_cache: Dictionary = {}

func _ready() -> void:
	close_button.pressed.connect(hide)
	tile_size_chart.segment_clicked.connect(_on_chart_segment_clicked)
	MatchState.building_added.connect(_on_building_added)
	MatchState.building_removed.connect(_on_building_removed)
	MatchState.stockpile_market_sale_queue_changed.connect(_on_stockpile_market_sale_queue_changed)
	MatchState.sell_surplus_changed.connect(_on_sell_surplus_changed)
	MatchState.sell_mode_changed.connect(_on_sell_mode_changed)
	MatchState.tile_land_owned_changed.connect(_on_tile_land_owned_changed)
	Production.turn_processed.connect(_on_turn_processed)
	CostSolver.costs_updated.connect(_on_costs_updated)
	Stockpile.stockpile_changed.connect(_on_stockpile_changed)
	_apply_tile_modal_frame_style()
	_apply_tile_modal_content_margins()
	_restructure_layout()
	_setup_tile_banner()
	_build_power_section()
	_build_production_section()
	_build_stockpile_section()
	_build_land_purchase_section()

func _restructure_layout() -> void:
	infrastructure_table.visible = false
	if _infra_grid == null:
		_infra_grid = INFRA_GRID_SCRIPT.new()
		_infra_grid.custom_minimum_size = Vector2(INFRA_GRID_WIDTH, 0)
		_infra_grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_infra_grid.size_flags_vertical = Control.SIZE_SHRINK_END
		_infra_grid.slot_activated.connect(func(inst: Dictionary) -> void: building_clicked.emit(inst))
		_infra_grid.add_requested.connect(_on_add_infrastructure_pressed)
		_chart_column.add_child(_infra_grid)

	if _banner_summary_wrapper == null:
		_banner_summary_wrapper = PanelContainer.new()
		_banner_summary_wrapper.name = "BannerSummary"
		_banner_summary_wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_banner_summary_wrapper.add_theme_stylebox_override("panel", _make_panel_style(Color.TRANSPARENT, SUMMARY_PANEL_BORDER, 8))
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 8)
		margin.add_theme_constant_override("margin_top", 8)
		margin.add_theme_constant_override("margin_right", 8)
		margin.add_theme_constant_override("margin_bottom", 8)
		_banner_summary_wrapper.add_child(margin)
		_banner_summary_content = VBoxContainer.new()
		_banner_summary_content.add_theme_constant_override("separation", 8)
		margin.add_child(_banner_summary_content)
		content_vbox.add_child(_banner_summary_wrapper)
		content_vbox.move_child(_banner_summary_wrapper, 1)

	if tile_image_banner.get_parent() != _banner_summary_content:
		var current_parent := tile_image_banner.get_parent()
		if current_parent != null:
			current_parent.remove_child(tile_image_banner)
		_banner_summary_content.add_child(tile_image_banner)
		_banner_summary_content.move_child(tile_image_banner, 0)
	tile_image_banner.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	if _tile_type_summary_row == null:
		_tile_type_summary_row = HBoxContainer.new()
		_tile_type_summary_row.name = "TileTypeSummary"
		_tile_type_summary_row.custom_minimum_size = Vector2(0, TILE_TYPE_SUMMARY_HEIGHT)
		_tile_type_summary_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tile_type_summary_row.add_theme_constant_override("separation", 4)
		_banner_summary_content.add_child(_tile_type_summary_row)

		_tile_type_summary_label = _make_summary_chip_label()
		_tile_type_summary_label.size_flags_stretch_ratio = 1.0
		_tile_type_summary_row.add_child(_tile_type_summary_label)

		_tile_deposits_summary_label = _make_summary_chip_label()
		_tile_deposits_summary_label.size_flags_stretch_ratio = 1.45
		_tile_type_summary_row.add_child(_tile_deposits_summary_label)

		_survey_status_button = Button.new()
		_survey_status_button.focus_mode = Control.FOCUS_NONE
		_survey_status_button.custom_minimum_size = Vector2(0, TILE_TYPE_SUMMARY_HEIGHT)
		_survey_status_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_survey_status_button.size_flags_stretch_ratio = 1.25
		_survey_status_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_survey_status_button.add_theme_font_size_override("font_size", TILE_TYPE_SUMMARY_FONT_SIZE)
		_survey_status_button.add_theme_stylebox_override("normal", _make_summary_chip_style(Color.TRANSPARENT, SUMMARY_PANEL_BORDER))
		_survey_status_button.add_theme_stylebox_override("hover", _make_summary_chip_style(Color(0.7, 0.85, 1.0, 0.10), Color(0.7, 0.85, 1.0, 0.78)))
		_survey_status_button.add_theme_stylebox_override("pressed", _make_summary_chip_style(Color(0.7, 0.85, 1.0, 0.14), Color(0.7, 0.85, 1.0, 0.9)))
		_survey_status_button.add_theme_color_override("font_color", OFF_WHITE)
		_survey_status_button.add_theme_color_override("font_hover_color", OFF_WHITE)
		_tile_type_summary_row.add_child(_survey_status_button)

	if _right_scroll == null:
		_right_scroll = ScrollContainer.new()
		_right_scroll.name = "TileInfoScroll"
		_right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_right_scroll_content = VBoxContainer.new()
		_right_scroll_content.name = "TileInfoScrollContent"
		_right_scroll_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_right_scroll_content.add_theme_constant_override("separation", 8)
		_right_scroll.add_child(_right_scroll_content)
		content_vbox.add_child(_right_scroll)
		content_vbox.move_child(_right_scroll, 2)

func _setup_tile_banner() -> void:
	if _tile_banner_texture_rect != null:
		return
	_tile_banner_texture_rect = TextureRect.new()
	_tile_banner_texture_rect.name = "BannerTexture"
	_tile_banner_texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tile_banner_texture_rect.offset_left = 0
	_tile_banner_texture_rect.offset_top = 0
	_tile_banner_texture_rect.offset_right = 0
	_tile_banner_texture_rect.offset_bottom = 0
	_tile_banner_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tile_banner_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_tile_banner_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile_image_banner.add_child(_tile_banner_texture_rect)

func show_tile(tile_data: Dictionary) -> void:
	_current_tile_data = tile_data
	_current_tile_id = tile_data.id
	var nick: String = tile_data.get("nickname", "")
	var tid: String = tile_data.get("id", "")
	title_label.text = ("%s (%s)" % [nick, tid]) if nick != "" else tid
	_rebuild_buildings(tile_data)
	_rebuild_infrastructure_table(tile_data)
	_refresh_tile_banner(tile_data)
	_refresh_tile_type_summary(tile_data)
	_refresh_power_section()
	_refresh_production_section()
	_refresh_land_purchase_section()
	_refresh_stockpile_section()
	visible = true
	PanelStack.push(self)

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
		PanelStack.remove(self)

func _rebuild_buildings(tile_data: Dictionary) -> void:
	var tile_id: String = tile_data.id
	var buildings: Array = MatchState.get_buildings_on_tile(tile_id)
	var chart_buildings: Array = []
	var seen_infrastructure := {}
	for building in buildings:
		var chart_building: Dictionary = building.duplicate()
		chart_building["display_label"] = _format_building_label(building)
		chart_buildings.append(chart_building)
		var building_data: Dictionary = Catalog.get_building(building.get("building_id", ""))
		if building_data.get("category", "") == "infrastructure":
			seen_infrastructure[_normalise_infrastructure_name(str(building_data.get("internal_name", "")))] = true

	for infra_name in tile_data.get("infrastructure_present", []):
		var normalized_name := _normalise_infrastructure_name(str(infra_name))
		if normalized_name == "" or seen_infrastructure.has(normalized_name):
			continue
		var building_data: Dictionary = Catalog.get_building_by_internal_name(normalized_name)
		if building_data.is_empty():
			continue
		chart_buildings.append({
			"instance_id": "tile_%s_%s" % [tile_id, normalized_name],
			"building_id": building_data.get("id", ""),
			"recipe_id": "",
			"tile_id": tile_id,
			"owner": "tile_data",
			"display_label": building_data.get("display_name", normalized_name),
		})
		seen_infrastructure[normalized_name] = true

	tile_size_chart.set_buildings(chart_buildings, _tile_size_capacity_for_tile(tile_data), MatchState.get_tile_land_owned(tile_id))

func _refresh_tile_banner(tile_data: Dictionary) -> void:
	if _tile_banner_texture_rect == null:
		return
	var tile_type := str(tile_data.get("type", "")).strip_edges().to_lower()
	if tile_type == "rural" or tile_type == "grass":
		if _rural_tile_banner_texture == null:
			_rural_tile_banner_texture = _load_texture(RURAL_TILE_BANNER_PATH)
		_tile_banner_texture_rect.texture = _rural_tile_banner_texture
	else:
		_tile_banner_texture_rect.texture = null

func _rebuild_infrastructure_table(tile_data: Dictionary) -> void:
	if _infra_grid == null:
		return
	_infra_grid.set_slots(_build_infra_slot_data(tile_data))

func _build_infra_slot_data(tile_data: Dictionary) -> Array:
	var slots_data: Array = []
	for slot in _infrastructure_slots():
		var key := str(slot.get("key", ""))
		var label_text := str(slot.get("label", key.capitalize()))
		var building_data := _infrastructure_building_data_for_key(key)
		var instance := _infrastructure_instance_for_tile(tile_data, key, building_data)
		var cell_size := _infrastructure_cell_size(key)
		var display_label := _abbreviate_if_needed(label_text, cell_size.x, INFRA_LABEL_FONT_SIZE)
		var max_label_lines := 2
		if key == "reinf_pipes":
			display_label = _abbreviate_if_long(label_text, INFRA_LABEL_MAX_CHARS)
			max_label_lines = 1
		var data := {
			"cell_size": cell_size,
			"display_label": display_label,
			"label_tooltip": label_text if display_label != label_text else "",
			"max_label_lines": max_label_lines,
		}
		if not instance.is_empty():
			data["state"] = "exists"
			data["icon"] = _building_icon_for_data(building_data)
			data["button_tooltip"] = _infrastructure_tooltip(tile_data, slot, instance)
			data["instance"] = instance
		elif building_data.is_empty():
			data["state"] = "unavailable"
			data["icon"] = _get_plus_icon()
			data["button_tooltip"] = "%s is not available yet" % label_text
		else:
			data["state"] = "add"
			data["icon"] = _get_plus_icon()
			data["button_tooltip"] = "Add %s" % label_text
			data["internal_name"] = str(building_data.get("internal_name", key))
		slots_data.append(data)
	return slots_data

func _right_detail_parent() -> VBoxContainer:
	return _right_scroll_content if _right_scroll_content != null else content_vbox

func _apply_tile_modal_frame_style() -> void:
	if _tile_modal_frame_texture == null:
		_tile_modal_frame_texture = _load_texture(TILE_MODAL_FRAME_PATH)
	if _tile_modal_frame_texture == null:
		return
	var style := StyleBoxTexture.new()
	style.texture = _tile_modal_frame_texture
	style.draw_center = true
	style.texture_margin_left = TILE_MODAL_FRAME_SLICE
	style.texture_margin_top = TILE_MODAL_FRAME_SLICE
	style.texture_margin_right = TILE_MODAL_FRAME_SLICE
	style.texture_margin_bottom = TILE_MODAL_FRAME_SLICE
	style.expand_margin_left = TILE_MODAL_FRAME_OUTSET
	style.expand_margin_top = TILE_MODAL_FRAME_OUTSET
	style.expand_margin_right = TILE_MODAL_FRAME_OUTSET
	style.expand_margin_bottom = TILE_MODAL_FRAME_OUTSET
	style.content_margin_left = 0.0
	style.content_margin_top = 0.0
	style.content_margin_right = 0.0
	style.content_margin_bottom = 0.0
	add_theme_stylebox_override("panel", style)

func _apply_tile_modal_content_margins() -> void:
	_margin_container.add_theme_constant_override("margin_left", TILE_MODAL_CONTENT_MARGIN)
	_margin_container.add_theme_constant_override("margin_top", TILE_MODAL_CONTENT_MARGIN)
	_margin_container.add_theme_constant_override("margin_right", TILE_MODAL_CONTENT_MARGIN)
	_margin_container.add_theme_constant_override("margin_bottom", TILE_MODAL_CONTENT_MARGIN)

func _make_panel_style(bg_color: Color, border_color: Color, radius: int = 6) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 8
	style.content_margin_top = 8
	style.content_margin_right = 8
	style.content_margin_bottom = 8
	return style

func _make_summary_chip_style(bg_color: Color, border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	style.content_margin_left = 4
	style.content_margin_top = 1
	style.content_margin_right = 4
	style.content_margin_bottom = 1
	return style

func _make_summary_chip_label() -> Label:
	var label := Label.new()
	label.custom_minimum_size = Vector2(0, TILE_TYPE_SUMMARY_HEIGHT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", TILE_TYPE_SUMMARY_FONT_SIZE)
	label.add_theme_color_override("font_color", OFF_WHITE)
	return label

func _make_summary_section(title_text: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(SUMMARY_PANEL_BG, SUMMARY_PANEL_BORDER, 7))
	_right_detail_parent().add_child(panel)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	panel.add_child(content)

	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", SUMMARY_SUBTLE_TEXT)
	content.add_child(title)
	return content

func _build_power_section() -> void:
	_power_section_content = _make_summary_section("⚡ POWER")

func _build_production_section() -> void:
	_production_section_content = _make_summary_section("📦 PRODUCTION (top 3 by value/turn)")

func _refresh_tile_type_summary(tile_data: Dictionary) -> void:
	if _tile_type_summary_label == null or _tile_deposits_summary_label == null or _survey_status_button == null:
		return
	var raw_tile_type := str(tile_data.get("type", "")).strip_edges().to_lower()
	var tile_type := _title_or_dash(raw_tile_type)
	var deposits: Array[String] = _tile_deposits(tile_data)
	_tile_type_summary_label.text = tile_type
	_tile_type_summary_label.tooltip_text = _tile_type_tooltip_text(raw_tile_type)
	_tile_deposits_summary_label.text = _deposit_summary_text(deposits)
	_tile_deposits_summary_label.tooltip_text = _deposit_tooltip_text(deposits)
	_survey_status_button.text = _survey_status_for_tile(tile_data)
	_survey_status_button.tooltip_text = "Survey status"

func _build_power_flow_rows() -> Dictionary:
	var produced := 0
	var consumed := 0
	var producers: Array[String] = []
	var consumers: Array[String] = []
	for building in MatchState.get_buildings_on_tile(_current_tile_id):
		var instance_id := str(building.get("instance_id", ""))
		if not Production.last_turn_run.get(instance_id, false):
			continue
		var recipe: Dictionary = Catalog.get_recipe(building.get("recipe_id", ""))
		if recipe.is_empty():
			continue
		var output_name := str(recipe.get("output_name", ""))
		if output_name == "power":
			produced += int(recipe.get("output_qty", 0))
			_add_unique_string(producers, _building_summary_name(building))
		var energy_req := int(recipe.get("energy_req", 0))
		if energy_req > 0:
			consumed += energy_req
			_add_unique_string(consumers, _building_summary_name(building))
	return {
		"produced": produced,
		"consumed": consumed,
		"net": produced - consumed,
		"producers": producers,
		"consumers": consumers,
	}

func _refresh_power_section() -> void:
	if _power_section_content == null:
		return
	_clear_summary_section(_power_section_content)
	var flow := _build_power_flow_rows()
	var net := int(flow.get("net", 0))
	var status := "surplus" if net > 0 else ("deficit" if net < 0 else "balanced")
	var status_color := SUMMARY_GREEN if net > 0 else (SUMMARY_RED if net < 0 else SUMMARY_AMBER)
	_power_section_content.add_child(_make_summary_title_row("⚡ POWER", "●  %s" % status, status_color))
	_power_section_content.add_child(_make_power_metric_row("Produced", int(flow.get("produced", 0)), _names_for_summary(flow.get("producers", []), "No producer this turn")))
	_power_section_content.add_child(_make_power_metric_row("Consumed", int(flow.get("consumed", 0)), _names_for_summary(flow.get("consumers", []), "No consumers this turn")))
	_power_section_content.add_child(_make_power_net_row(net))

func _refresh_production_section() -> void:
	if _production_section_content == null:
		return
	_clear_summary_section(_production_section_content)
	_production_section_content.add_child(_make_summary_title_row("📦 PRODUCTION", "top 3 by value/turn", SUMMARY_SUBTLE_TEXT))

	var rows := _production_rows_for_tile()
	if rows.is_empty():
		var empty := _make_summary_label("No production on this tile last turn", 12, SUMMARY_MUTED)
		_production_section_content.add_child(empty)
		return

	var limit := mini(3, rows.size())
	for i in range(limit):
		_production_section_content.add_child(_make_production_row(rows[i]))

	var more_count := maxi(0, rows.size() - limit)
	var footer := _make_summary_label("[+%d more ▼]  [see breakdown →]" % more_count, 12, SUMMARY_SUBTLE_TEXT)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_production_section_content.add_child(footer)

func _clear_summary_section(section: VBoxContainer) -> void:
	for child in section.get_children():
		child.queue_free()

func _make_summary_title_row(left_text: String, right_text: String, right_color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var left := _make_summary_label(left_text, 13, SUMMARY_SUBTLE_TEXT)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var right := _make_summary_label(right_text, 12, right_color)
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(right)
	return row

func _make_power_metric_row(label_text: String, amount: int, source_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 22)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	row.add_child(_make_fixed_summary_label(label_text, 88.0, 12, OFF_WHITE))
	row.add_child(_make_fixed_summary_label("%d/turn" % amount, 74.0, 12, OFF_WHITE))
	var source := _make_summary_label("(%s)" % source_text, 12, SUMMARY_SUBTLE_TEXT)
	source.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	source.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(source)
	return row

func _make_power_net_row(net: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 22)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	row.add_child(_make_fixed_summary_label("Net", 88.0, 12, OFF_WHITE))
	var sign := "+" if net > 0 else ""
	row.add_child(_make_fixed_summary_label("%s%d" % [sign, net], 74.0, 12, OFF_WHITE))
	var destination := "→ grid" if net > 0 else ("← grid" if net < 0 else "balanced")
	var dest_label := _make_summary_label(destination, 12, SUMMARY_SUBTLE_TEXT)
	dest_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(dest_label)
	return row

func _make_production_row(row_data: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, PRODUCTION_ROW_HEIGHT)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	row.add_child(_make_fixed_summary_label(str(row_data.get("display_name", "")), 94.0, 12, OFF_WHITE))
	row.add_child(_make_fixed_summary_label("%d/turn" % int(row_data.get("qty", 0)), 62.0, 12, OFF_WHITE))
	var cost_label := _make_fixed_summary_label(_format_unit_cost(float(row_data.get("unit_cost", -1.0))), 60.0, 12, _cost_color_for_row(row_data))
	row.add_child(cost_label)
	var dest := _make_summary_label(str(row_data.get("destination", "")), 12, SUMMARY_SUBTLE_TEXT)
	dest.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	dest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(dest)
	return row

func _make_summary_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label

func _make_fixed_summary_label(text: String, width: float, font_size: int, color: Color) -> Label:
	var display_text := _abbreviate_if_needed(text, width, font_size)
	var label := _make_summary_label(display_text, font_size, color)
	label.custom_minimum_size = Vector2(width, 0)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if display_text != text:
		label.tooltip_text = text
	return label

func _abbreviate_if_needed(text: String, width: float, font_size: int) -> String:
	if width <= 0.0 or _text_fits_width(text, width, font_size):
		return text
	var abbreviated := _abbreviate_ui_text(text)
	return abbreviated

func _text_fits_width(text: String, width: float, font_size: int) -> bool:
	var font := get_theme_default_font()
	if font == null:
		return true
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x <= width

func _abbreviate_ui_text(text: String) -> String:
	var output := text
	for rule in UI_ABBREVIATION_RULES:
		var source := str(rule[0])
		output = output.replace(source, str(rule[1]))
		output = output.replace(source.to_lower(), str(rule[2]))
		output = output.replace(source.to_upper(), str(rule[3]))
	return output

func _abbreviate_if_long(text: String, max_chars: int) -> String:
	var display_text := _abbreviate_ui_text(text)
	if display_text.length() <= max_chars:
		return display_text
	return "%s..." % display_text.substr(0, maxi(1, max_chars - 3))

func _production_rows_for_tile() -> Array:
	var rows_by_good: Dictionary = {}
	var power_flow := _build_power_flow_rows()
	for building in MatchState.get_buildings_on_tile(_current_tile_id):
		var instance_id := str(building.get("instance_id", ""))
		if not Production.last_turn_run.get(instance_id, false):
			continue
		var recipe: Dictionary = Catalog.get_recipe(building.get("recipe_id", ""))
		if recipe.is_empty():
			continue
		for output in _recipe_output_items(recipe):
			var good_id := _output_good_id(output)
			var qty := int(output.get("qty", 0))
			if good_id == "" or qty <= 0:
				continue
			var rec: Dictionary = rows_by_good.get(good_id, {
				"good_id": good_id,
				"display_name": Catalog.get_display_name(good_id),
				"qty": 0,
				"cost_weight": 0.0,
				"cost_qty": 0.0,
				"value": 0.0,
				"destinations": {},
			})
			var unit_cost := _building_output_unit_cost(building, recipe, good_id, qty)
			rec.qty = int(rec.get("qty", 0)) + qty
			rec.value = float(rec.get("value", 0.0)) + (float(qty) * MarketState.get_price(good_id))
			if unit_cost >= 0.0:
				rec.cost_weight = float(rec.get("cost_weight", 0.0)) + (unit_cost * float(qty))
				rec.cost_qty = float(rec.get("cost_qty", 0.0)) + float(qty)
			var destinations: Dictionary = rec.get("destinations", {})
			destinations[_production_destination_text(building, good_id, power_flow)] = true
			rec.destinations = destinations
			rows_by_good[good_id] = rec

	var rows: Array = []
	for good_id in rows_by_good:
		var rec: Dictionary = rows_by_good[good_id]
		var cost_qty := float(rec.get("cost_qty", 0.0))
		rec.unit_cost = (float(rec.get("cost_weight", 0.0)) / cost_qty) if cost_qty > 0.0 else -1.0
		var destinations := (rec.get("destinations", {}) as Dictionary).keys()
		rec.destination = _join_limited(destinations, "mixed")
		rows.append(rec)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if is_equal_approx(float(a.get("value", 0.0)), float(b.get("value", 0.0))):
			return str(a.get("display_name", "")) < str(b.get("display_name", ""))
		return float(a.get("value", 0.0)) > float(b.get("value", 0.0))
	)
	return rows

func _recipe_output_items(recipe: Dictionary) -> Array:
	if recipe.has("outputs"):
		return recipe.get("outputs", [])
	var output_name := str(recipe.get("output_name", ""))
	var output_qty := int(recipe.get("output_qty", 0))
	if output_name == "" or output_qty <= 0:
		return []
	return [{"internal_name": output_name, "qty": output_qty}]

func _output_good_id(output: Dictionary) -> String:
	var good_id := str(output.get("good_id", ""))
	if good_id != "":
		return good_id
	var internal_name := str(output.get("internal_name", ""))
	if internal_name == "":
		return ""
	var good: Dictionary = Catalog.get_good_by_internal_name(internal_name)
	return str(good.get("id", ""))

func _building_output_unit_cost(building: Dictionary, recipe: Dictionary, good_id: String, qty: int) -> float:
	var instance_id := str(building.get("instance_id", ""))
	var cost := CostSolver.get_building_output_cost(instance_id, good_id)
	if cost >= 0.0:
		return cost
	cost = CostSolver.get_building_unit_cost(instance_id)
	if cost >= 0.0:
		return cost
	return _fallback_building_unit_cost(building, recipe, qty)

func _fallback_building_unit_cost(building: Dictionary, recipe: Dictionary, output_qty: int) -> float:
	if output_qty <= 0:
		return -1.0
	var input_cost := 0.0
	for input in recipe.get("inputs", []):
		var good_id := str(input.get("good_id", ""))
		if good_id == "":
			var good: Dictionary = Catalog.get_good_by_internal_name(str(input.get("internal_name", "")))
			good_id = str(good.get("id", ""))
		var unit := CostSolver.get_good_unit_cost(good_id)
		if unit < 0.0:
			unit = MarketState.get_price(good_id)
		input_cost += unit * float(input.get("qty", 0))
	var building_data: Dictionary = Catalog.get_building(building.get("building_id", ""))
	var labour_cost: float = (
		int(building_data.get("labour_unskilled_required", EconomyConfig.STUB_UNSKILLED_PER_BUILDING)) * EconomyConfig.LABOUR_UNSKILLED_RATE
		+ int(building_data.get("labour_skilled_required", EconomyConfig.STUB_SKILLED_PER_BUILDING)) * EconomyConfig.LABOUR_SKILLED_RATE
		+ int(building_data.get("labour_h_skilled_required", EconomyConfig.STUB_HIGH_SKILLED_PER_BUILDING)) * EconomyConfig.LABOUR_HIGH_SKILLED_RATE
	) * MatchState.labour_multiplier
	var maintenance: Variant = building_data.get("maintenance_cost", null)
	var maintenance_cost: float = EconomyConfig.MAINTENANCE_PER_BUILDING if maintenance == null else float(maintenance)
	var power_cost: float = float(recipe.get("energy_req", 0)) * EconomyConfig.GRID_BUY_PRICE
	return (input_cost + labour_cost + maintenance_cost + power_cost) / float(output_qty)

func _production_destination_text(building: Dictionary, good_id: String, power_flow: Dictionary) -> String:
	if Catalog.get_internal_name(good_id) == "power":
		var net := int(power_flow.get("net", 0))
		var consumed := int(power_flow.get("consumed", 0))
		if consumed > 0 and net > 0:
			return "self-consumed (%d to grid)" % net
		if consumed > 0:
			return "self-consumed"
		return "to grid" if net > 0 else "balanced"
	if _tile_good_is_locally_consumed(good_id):
		return "self-consumed"
	var explicit_destination := MatchState.get_output_stockpile_destination(str(building.get("instance_id", "")), good_id)
	if explicit_destination != "":
		return "to %s" % explicit_destination
	match MatchState.sell_mode:
		MatchState.SellMode.STOCKPILE_ALL:
			return "to this tile"
		MatchState.SellMode.BUILDING_BY_BUILDING:
			return "building-by-building"
		_:
			return "to market"

func _tile_good_is_locally_consumed(good_id: String) -> bool:
	for building in MatchState.get_buildings_on_tile(_current_tile_id):
		var recipe: Dictionary = Catalog.get_recipe(building.get("recipe_id", ""))
		for input in recipe.get("inputs", []):
			if str(input.get("good_id", "")) == good_id:
				return true
	return false

func _cost_color_for_row(row_data: Dictionary) -> Color:
	var unit_cost := float(row_data.get("unit_cost", -1.0))
	if unit_cost < 0.0:
		return SUMMARY_MUTED
	var market_price := MarketState.get_price(str(row_data.get("good_id", "")))
	if market_price <= 0.0:
		return SUMMARY_MUTED
	var ratio := unit_cost / market_price
	if ratio >= 1.1:
		return SUMMARY_RED
	if ratio >= 0.9:
		return SUMMARY_AMBER
	return SUMMARY_GREEN

func _format_unit_cost(unit_cost: float) -> String:
	return "—" if unit_cost < 0.0 else "£%.2f" % unit_cost

func _tile_deposits(tile_data: Dictionary) -> Array[String]:
	var deposits: Array[String] = []
	for deposit in tile_data.get("deposits", []):
		var value := str(deposit).strip_edges()
		if value != "":
			deposits.append(value)
	return deposits

func _deposit_summary_text(deposits: Array[String]) -> String:
	if deposits.is_empty():
		return "No deposits"
	if deposits.size() == 1:
		return "%s Deposit" % _good_display_from_internal(deposits[0])
	return "%d Deposits" % deposits.size()

func _deposit_tooltip_text(deposits: Array[String]) -> String:
	if deposits.is_empty():
		return "No known deposits"
	var lines: Array[String] = ["Deposits on this tile"]
	for deposit in deposits:
		lines.append("- %s" % _good_display_from_internal(deposit))
	return "\n".join(lines)

func _survey_status_for_tile(tile_data: Dictionary) -> String:
	var explicit := str(tile_data.get("survey_status", "")).strip_edges()
	if explicit != "":
		return _compact_survey_status(explicit)
	match str(tile_data.get("type", "")).strip_edges().to_lower():
		"rural", "grass":
			return "Surveyed"
		"urban":
			return "P Surveyed"
		"mountain":
			return "Unsurveyed"
		_:
			return "Unsurveyed"

func _compact_survey_status(status: String) -> String:
	match status.strip_edges().to_lower():
		"partially surveyed", "partial", "p surveyed":
			return "P Surveyed"
		"surveyed":
			return "Surveyed"
		"unsurveyed":
			return "Unsurveyed"
		_:
			return status

func _tile_type_tooltip_text(tile_type: String) -> String:
	var impact := _tile_type_impact(tile_type)
	return "Impact on transport cost: %s\nImpact on Tile Size Cap: %s" % [
		impact.get("transport", "0"),
		_format_capacity_modifier(int(impact.get("capacity", 0))),
	]

func _tile_size_capacity_for_tile(tile_data: Dictionary) -> int:
	var impact := _tile_type_impact(str(tile_data.get("type", "")))
	return max(1, BASE_TILE_SIZE_CAPACITY + int(impact.get("capacity", 0)))

func _tile_type_impact(tile_type: String) -> Dictionary:
	match tile_type.strip_edges().to_lower():
		"rural", "grass":
			return {"transport": "0", "capacity": 50}
		"hill":
			return {"transport": "+20%", "capacity": 25}
		"mountain":
			return {"transport": "+100%", "capacity": -25}
		"urban":
			return {"transport": "+10%", "capacity": 0}
		_:
			return {"transport": "0", "capacity": 0}

func _format_capacity_modifier(value: int) -> String:
	if value >= 0:
		return "+%d" % value
	return str(value)

func _good_display_from_internal(internal_name: String) -> String:
	var good: Dictionary = Catalog.get_good_by_internal_name(internal_name)
	if good.is_empty():
		good = Catalog.get_good(internal_name)
	var display := str(good.get("display_name", internal_name))
	return _title_or_dash(display)

func _building_summary_name(building: Dictionary) -> String:
	var building_data: Dictionary = Catalog.get_building(building.get("building_id", ""))
	return str(building_data.get("display_name", building.get("building_id", "")))

func _names_for_summary(names: Array, empty_text: String) -> String:
	if names.is_empty():
		return empty_text
	return "%s, this tile" % _join_limited(names, empty_text)

func _join_limited(items: Array, empty_text: String, max_items: int = 2) -> String:
	if items.is_empty():
		return empty_text
	var strings: Array[String] = []
	for i in range(mini(max_items, items.size())):
		strings.append(str(items[i]))
	if items.size() > max_items:
		strings.append("+%d more" % (items.size() - max_items))
	return ", ".join(strings)

func _add_unique_string(items: Array[String], value: String) -> void:
	if value != "" and not items.has(value):
		items.append(value)

func _title_or_dash(value: String) -> String:
	var stripped := value.strip_edges()
	if stripped == "":
		return "—"
	return stripped.replace("_", " ").capitalize()

func _build_land_purchase_section() -> void:
	var separator := HSeparator.new()
	_right_detail_parent().add_child(separator)

	var header_row := HBoxContainer.new()
	header_row.custom_minimum_size = Vector2(0, 24)
	header_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_theme_constant_override("separation", 8)
	_right_detail_parent().add_child(header_row)

	var title := Label.new()
	title.text = "Buy land/buildings"
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", SUMMARY_SUBTLE_TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(title)

	_land_left_label = Label.new()
	_land_left_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_land_left_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_land_left_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_land_left_label.add_theme_font_size_override("font_size", 12)
	_land_left_label.add_theme_color_override("font_color", OFF_WHITE)
	_land_left_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(_land_left_label)

	_land_purchase_buttons_row = HBoxContainer.new()
	_land_purchase_buttons_row.custom_minimum_size = Vector2(0, 30)
	_land_purchase_buttons_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_land_purchase_buttons_row.add_theme_constant_override("separation", 8)
	_right_detail_parent().add_child(_land_purchase_buttons_row)

	_land_buy_one_button = _make_land_purchase_button("Buy 10 land", "Buy 10 more land on this tile")
	_land_buy_one_button.pressed.connect(_on_buy_land_patch_pressed.bind(1))
	_land_purchase_buttons_row.add_child(_land_buy_one_button)

	_land_buy_all_button = _make_land_purchase_button("Buy all land", "Buy every remaining land patch on this tile")
	_land_buy_all_button.pressed.connect(_on_buy_all_land_pressed)
	_land_purchase_buttons_row.add_child(_land_buy_all_button)

	_land_buildings_for_sale_button = _make_land_purchase_button("See buildings for sale", "Coming soon")
	_land_purchase_buttons_row.add_child(_land_buildings_for_sale_button)

func _refresh_land_purchase_section() -> void:
	if _land_left_label == null:
		return

	var owned := MatchState.get_tile_land_owned(_current_tile_id)
	var land_left := maxi(0, MatchState.MAX_TILE_LAND - owned)
	var available := MatchState.get_tile_land_patches_available(_current_tile_id)
	_land_left_label.text = "Land left for purchase: %d" % land_left
	if _land_buy_one_button != null:
		_land_buy_one_button.disabled = available <= 0
	if _land_buy_all_button != null:
		_land_buy_all_button.disabled = available <= 0

func _make_land_purchase_button(text: String, tooltip: String) -> Button:
	var buy_button := Button.new()
	buy_button.text = text
	buy_button.custom_minimum_size = Vector2(0, 30)
	buy_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buy_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	buy_button.tooltip_text = tooltip
	_apply_button_text_style(buy_button)
	return buy_button

func _on_buy_land_patch_pressed(patches: int = 1) -> void:
	if _current_tile_id == "":
		return
	if not MatchState.purchase_tile_land(_current_tile_id, patches):
		var toast := get_tree().root.find_child("ToastLayer", true, false)
		if toast != null and toast.has_method("show_error"):
			toast.call("show_error", "You cannot purchase more land on tile %s" % _current_tile_id)
		else:
			push_warning("You cannot purchase more land on tile %s" % _current_tile_id)

func _on_buy_all_land_pressed() -> void:
	if _current_tile_id == "":
		return
	_on_buy_land_patch_pressed(MatchState.get_tile_land_patches_available(_current_tile_id))

func _infrastructure_slots() -> Array:
	return [
		{"key": "cables", "label": "Cables"},
		{"key": "roads", "label": "Roads"},
		{"key": "pipes", "label": "Pipework"},
		{"key": "hvdc", "label": "HVDC"},
		{"key": "rails", "label": "Rail"},
		{"key": "reinf_pipes", "label": "Reinforced pipework"},
	]

func _infrastructure_cell_size(key: String) -> Vector2:
	return Vector2(float(INFRA_CELL_WIDTHS.get(key, INFRA_CELL_DEFAULT_SIZE.x)), INFRA_CELL_DEFAULT_SIZE.y)

func _on_add_infrastructure_pressed(infra_type: String) -> void:
	if _current_tile_id == "" or infra_type == "":
		return
	BuildMode.infrastructure_attempted.emit(infra_type, _current_tile_id)

func _infrastructure_tooltip(tile_data: Dictionary, slot: Dictionary, instance: Dictionary) -> String:
	var key := str(slot.get("key", ""))
	var display_name := str(slot.get("label", key.capitalize()))
	var level := clampi(int(instance.get("level", 1)), 1, 3)
	var lines: Array[String] = ["%s (Level %d)" % [display_name, level]]
	match key:
		"cables", "hvdc":
			lines.append("Grid: %s" % _tile_grid_name(tile_data))
		"pipes":
			lines.append("Liquids and Gas Capacity: %s" % _pipe_capacity_text(tile_data))
			lines.append("In use: Pure Water, Waste Water, Crude Oil, Processed Oil, Fuels")
		"reinf_pipes":
			lines.append("Liquids and Gas Capacity: %s" % _pipe_capacity_text(tile_data, 200))
			lines.append("In use: Chlorine, Hydrogen, Oxygen, Nitrogen, Ethylene, Ammonia, Sodium Hydroxide")
		"roads", "rails":
			lines.append("Transit capacity A/B")
	return "\n".join(lines)

func _tile_grid_name(tile_data: Dictionary) -> String:
	for key in ["grid_name", "power_grid", "grid", "electric_grid"]:
		var value := str(tile_data.get(key, "")).strip_edges()
		if value != "":
			return value
	return "National Grid"

func _pipe_capacity_text(tile_data: Dictionary, default_capacity: int = 100) -> String:
	var used := int(tile_data.get("liquid_capacity_used", tile_data.get("pipe_capacity_used", 0)))
	var capacity := int(tile_data.get("liquid_capacity", tile_data.get("pipe_capacity", default_capacity)))
	return "%d/%d" % [used, capacity]

func _infrastructure_building_data_for_key(key: String) -> Dictionary:
	var building_data := Catalog.get_building_by_internal_name(key)
	if not building_data.is_empty():
		return building_data
	for candidate in Catalog.all_buildings():
		if candidate.get("category", "") != "infrastructure":
			continue
		if _normalise_infrastructure_name(str(candidate.get("internal_name", ""))) == key:
			return candidate
	return {}

func _infrastructure_instance_for_tile(tile_data: Dictionary, key: String, building_data: Dictionary) -> Dictionary:
	var tile_id := str(tile_data.get("id", ""))
	for building in MatchState.get_buildings_on_tile(tile_id):
		var candidate_data: Dictionary = Catalog.get_building(building.get("building_id", ""))
		if candidate_data.get("category", "") != "infrastructure":
			continue
		if _normalise_infrastructure_name(str(candidate_data.get("internal_name", ""))) == key:
			return building

	for infra_name in tile_data.get("infrastructure_present", []):
		if _normalise_infrastructure_name(str(infra_name)) != key:
			continue
		return {
			"instance_id": "tile_%s_%s" % [tile_id, key],
			"building_id": building_data.get("id", ""),
			"recipe_id": "",
			"tile_id": tile_id,
			"owner": "tile_data",
			"display_label": building_data.get("display_name", key.capitalize()),
		}
	return {}

func _get_plus_icon() -> Texture2D:
	if _plus_icon_texture == null:
		_plus_icon_texture = _load_texture(PLUS_ICON_PATH)
	return _plus_icon_texture

func _building_icon_for_data(building_data: Dictionary) -> Texture2D:
	var building_id := str(building_data.get("id", ""))
	if building_id == "":
		return null
	if _building_icon_cache.has(building_id):
		return _building_icon_cache[building_id] as Texture2D

	var internal_name := str(building_data.get("internal_name", ""))
	var icon_paths: Array[String] = []
	if internal_name != "":
		icon_paths.append("res://assets/icons/buildings/%s_%s.png" % [building_id, internal_name])
		icon_paths.append("res://assets/icons/buildings/%s_%s.PNG" % [building_id, internal_name])
	icon_paths.append("res://assets/icons/buildings/%s.png" % building_id)
	icon_paths.append("res://assets/icons/buildings/%s.PNG" % building_id)
	if internal_name != "":
		icon_paths.append("res://assets/icons/buildings/%s.png" % internal_name)
		icon_paths.append("res://assets/icons/buildings/%s.PNG" % internal_name)
	for icon_path in icon_paths:
		var texture := _load_texture(icon_path)
		if texture != null:
			_building_icon_cache[building_id] = texture
			return texture
	_building_icon_cache[building_id] = null
	return null

func _load_texture(texture_path: String) -> Texture2D:
	if ResourceLoader.exists(texture_path):
		return load(texture_path) as Texture2D
	var image := Image.new()
	if image.load(ProjectSettings.globalize_path(texture_path)) == OK:
		return ImageTexture.create_from_image(image)
	return null

func _make_setting_row(label_text: String, control: Control, row_height: float = CONTROL_ROW_HEIGHT) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, row_height)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)

	var label := Label.new()
	label.text = _abbreviate_if_long(label_text, UI_ABBREVIATION_SETTING_THRESHOLD)
	if label.text != label_text:
		label.tooltip_text = label_text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.max_lines_visible = 2
	label.clip_text = true
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", CONTROL_LABEL_FONT_SIZE)
	label.add_theme_color_override("font_color", OFF_WHITE)
	label.custom_minimum_size = Vector2(0, row_height)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_stretch_ratio = CONTROL_LABEL_RATIO
	row.add_child(label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.size_flags_stretch_ratio = CONTROL_SPACER_RATIO
	row.add_child(spacer)

	if control is CheckBox:
		control.custom_minimum_size = Vector2(CHECKBOX_ICON_SIZE, 30)
		control.size_flags_horizontal = Control.SIZE_SHRINK_END
	else:
		control.custom_minimum_size = Vector2(0, 30)
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		control.size_flags_stretch_ratio = CONTROL_CONTROL_RATIO
	row.add_child(control)
	return row

func _apply_button_text_style(button: Button) -> void:
	button.add_theme_color_override("font_color", OFF_WHITE)
	button.add_theme_color_override("font_hover_color", OFF_WHITE)
	button.add_theme_color_override("font_pressed_color", Color(OFF_WHITE.r, OFF_WHITE.g, OFF_WHITE.b, 0.82))
	button.add_theme_color_override("font_disabled_color", Color(OFF_WHITE.r, OFF_WHITE.g, OFF_WHITE.b, 0.45))

func _get_checkbox_icon(checked: bool) -> Texture2D:
	if checked and _checkbox_checked_icon_texture != null:
		return _checkbox_checked_icon_texture
	if not checked and _checkbox_unchecked_icon_texture != null:
		return _checkbox_unchecked_icon_texture
	var image := Image.create(CHECKBOX_ICON_SIZE, CHECKBOX_ICON_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	if checked:
		image.fill(Color.WHITE)
	else:
		for i in CHECKBOX_ICON_SIZE:
			image.set_pixel(i, 0, Color.WHITE)
			image.set_pixel(i, CHECKBOX_ICON_SIZE - 1, Color.WHITE)
			image.set_pixel(0, i, Color.WHITE)
			image.set_pixel(CHECKBOX_ICON_SIZE - 1, i, Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	if checked:
		_checkbox_checked_icon_texture = texture
	else:
		_checkbox_unchecked_icon_texture = texture
	return texture

func _build_stockpile_section() -> void:
	var separator := HSeparator.new()
	_right_detail_parent().add_child(separator)

	var title := Label.new()
	title.text = "Stockpile"
	title.add_theme_font_size_override("font_size", 13)
	title.modulate = Color(0.7, 0.85, 1.0)
	_right_detail_parent().add_child(title)

	_stockpile_view = STOCKPILE_VIEW_SCRIPT.new()
	_stockpile_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right_detail_parent().add_child(_stockpile_view)

	_sell_surplus_button = CheckBox.new()
	_sell_surplus_button.text = ""
	_sell_surplus_button.tooltip_text = "Automatically sell surplus stockpile that buildings on this tile do not require"
	_sell_surplus_button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_sell_surplus_button.add_theme_icon_override("unchecked", _get_checkbox_icon(false))
	_sell_surplus_button.add_theme_icon_override("checked", _get_checkbox_icon(true))
	_sell_surplus_button.add_theme_icon_override("unchecked_disabled", _get_checkbox_icon(false))
	_sell_surplus_button.add_theme_icon_override("checked_disabled", _get_checkbox_icon(true))
	_sell_surplus_button.toggled.connect(_on_sell_surplus_toggled)
	_right_detail_parent().add_child(_make_setting_row("Sell surplus every turn", _sell_surplus_button))

	_production_destination_option = OptionButton.new()
	_production_destination_option.add_item("this tile")
	_production_destination_option.add_item("market")
	_production_destination_option.add_item("building-by-building")
	_apply_button_text_style(_production_destination_option)
	_production_destination_option.item_selected.connect(_on_production_destination_selected)
	_right_detail_parent().add_child(_make_setting_row("Production destination for all buildings", _production_destination_option, CONTROL_ROW_TALL_HEIGHT))
	_sync_production_destination_option()

	_stockpile_sell_button = Button.new()
	_stockpile_sell_button.text = "Sell All to Market"
	_stockpile_sell_button.custom_minimum_size = Vector2(0, 30)
	_stockpile_sell_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_button_text_style(_stockpile_sell_button)
	_stockpile_sell_button.pressed.connect(_on_sell_stockpile_pressed)
	_right_detail_parent().add_child(_stockpile_sell_button)

func _refresh_stockpile_section() -> void:
	if _stockpile_view == null:
		return
	_stockpile_view.set_tile(_current_tile_id)

	var used: int = Stockpile.get_used_capacity(_current_tile_id)
	if _sell_surplus_button != null:
		_sell_surplus_button.set_pressed_no_signal(MatchState.is_sell_surplus_enabled(_current_tile_id))

	if _stockpile_sell_button != null:
		var sale_queued := MatchState.is_stockpile_market_sale_queued(_current_tile_id)
		_stockpile_sell_button.text = "Sale Queued for End Turn" if sale_queued else "Sell All to Market"
		_stockpile_sell_button.disabled = used <= 0 or sale_queued

func _on_stockpile_changed() -> void:
	if visible and _current_tile_id != "":
		_refresh_stockpile_section()

func _on_stockpile_market_sale_queue_changed(tile_id: String) -> void:
	if visible and tile_id == _current_tile_id:
		_refresh_stockpile_section()

func _on_sell_stockpile_pressed() -> void:
	if _current_tile_id == "":
		return
	if Stockpile.get_used_capacity(_current_tile_id) <= 0:
		return
	MatchState.queue_stockpile_market_sale(_current_tile_id)
	_refresh_stockpile_section()

func _infrastructure_rows_for_tile(tile_data: Dictionary) -> Array:
	var rows: Array = []
	var seen_ids := {}
	for building in MatchState.get_buildings_on_tile(tile_data.id):
		var building_data: Dictionary = Catalog.get_building(building.get("building_id", ""))
		if building_data.get("category", "") == "infrastructure":
			rows.append(building_data)
			seen_ids[building_data.get("id", "")] = true
	
	var infrastructure_present: Array = tile_data.get("infrastructure_present", [])
	for infra_name in infrastructure_present:
		var building_data: Dictionary = Catalog.get_building_by_internal_name(_normalise_infrastructure_name(str(infra_name)))
		if building_data.is_empty():
			continue
		var building_id: String = building_data.get("id", "")
		if seen_ids.has(building_id):
			continue
		rows.append(building_data)
		seen_ids[building_id] = true
	return rows

func _normalise_infrastructure_name(infra_name: String) -> String:
	match infra_name.strip_edges().to_lower():
		"railways", "railway":
			return "rails"
		"pipework", "pipeworks", "pipes":
			return "pipes"
		"reinforced_pipes", "reinforced_pipework", "reinforced_pipeworks":
			return "reinf_pipes"
		"hvdc":
			return "hvdc"
		_:
			return infra_name.strip_edges().to_lower()

func _all_infrastructure_buildings() -> Array:
	var buildings: Array = []
	for building_data in Catalog.all_buildings():
		if building_data.get("category", "") == "infrastructure":
			buildings.append(building_data)
	return buildings

func _format_building_label(building: Dictionary) -> String:
	var building_data: Dictionary = Catalog.get_building(building.get("building_id", ""))
	var building_name: String = building_data.get("display_name", building.get("building_id", ""))
	var recipe: Dictionary = Catalog.get_recipe(building.get("recipe_id", ""))
	var output_name := _primary_output_display_name(recipe)
	var letter := _building_letter_for_tile(building)
	if output_name == "":
		return "%s - %s" % [building_name, letter]
	return "%s - %s - %s" % [building_name, output_name, letter]

func _on_chart_segment_clicked(building: Dictionary) -> void:
	building_clicked.emit(building)

func _primary_output_display_name(recipe: Dictionary) -> String:
	var output_name: String = recipe.get("output_name", "")
	if output_name == "":
		return ""
	var good: Dictionary = Catalog.get_good_by_internal_name(output_name)
	return good.get("display_name", output_name)

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

func _on_building_added(instance: Dictionary) -> void:
	if not visible:
		return
	if instance.get("tile_id", "") == _current_tile_id:
		_rebuild_buildings(_current_tile_data)
		_rebuild_infrastructure_table(_current_tile_data)
		_refresh_power_section()
		_refresh_production_section()

func _on_building_removed(_instance_id: String) -> void:
	if visible and _current_tile_id != "":
		_rebuild_buildings(_current_tile_data)
		_rebuild_infrastructure_table(_current_tile_data)
		_refresh_power_section()
		_refresh_production_section()

func _on_tile_land_owned_changed(tile_id: String) -> void:
	if visible and tile_id == _current_tile_id:
		_rebuild_buildings(_current_tile_data)
		_refresh_land_purchase_section()

func _format_nullable_money(value: Variant) -> String:
	if value == null:
		return "null"
	return "£%.2f" % float(value)

func _on_sell_surplus_toggled(pressed: bool) -> void:
	if _current_tile_id == "":
		return
	if pressed:
		MatchState.enable_sell_surplus(_current_tile_id)
	else:
		MatchState.disable_sell_surplus(_current_tile_id)

func _on_sell_surplus_changed(tile_id: String) -> void:
	if visible and tile_id == _current_tile_id:
		_refresh_stockpile_section()

func _on_production_destination_selected(index: int) -> void:
	match index:
		0:
			MatchState.set_sell_mode(MatchState.SellMode.STOCKPILE_ALL)
		1:
			MatchState.set_sell_mode(MatchState.SellMode.SELL_ALL)
		2:
			# Building-by-building routing uses per-building destinations where
			# they exist, with market as the fallback for unassigned buildings.
			MatchState.set_sell_mode(MatchState.SellMode.BUILDING_BY_BUILDING)

func _on_sell_mode_changed(_new_mode: int) -> void:
	_sync_production_destination_option()
	if visible:
		_refresh_production_section()

func _on_turn_processed(_summary: Dictionary) -> void:
	if visible and _current_tile_id != "":
		_refresh_power_section()
		_refresh_production_section()
		_refresh_stockpile_section()

func _on_costs_updated() -> void:
	if visible and _current_tile_id != "":
		_refresh_production_section()

func _sync_production_destination_option() -> void:
	if _production_destination_option == null:
		return
	var selected_index := 0
	match MatchState.sell_mode:
		MatchState.SellMode.STOCKPILE_ALL:
			selected_index = 0
		MatchState.SellMode.BUILDING_BY_BUILDING:
			selected_index = 2
		_:
			selected_index = 1
	_production_destination_option.select(selected_index)

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
