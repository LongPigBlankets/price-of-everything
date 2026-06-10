extends PanelContainer

@onready var title_label: Label = $MarginContainer/VBoxContainer/HeaderRow/TitleLabel
@onready var close_button: Button = $MarginContainer/VBoxContainer/HeaderRow/CloseButton
@onready var location_label: Label = $MarginContainer/VBoxContainer/LocationLabel
@onready var building_image_banner: PanelContainer = $MarginContainer/VBoxContainer/BuildingImageBanner
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
@onready var panel_margin: MarginContainer = $MarginContainer
@onready var panel_vbox: VBoxContainer = $MarginContainer/VBoxContainer
@onready var content_row: HBoxContainer = $MarginContainer/VBoxContainer/ContentRow
@onready var change_recipe_button: Button = $MarginContainer/VBoxContainer/ChangeRecipeButton

const HEADER_HEIGHT := 40.0
const PANEL_EDGE_MARGIN := 20.0
# The top bar is 36px tall; keep the panel 20px clear of it so it never overlaps.
const TOP_BAR_CLEARANCE := 56.0
const UIHelpers := preload("res://scripts/ui_helpers.gd")
static var _suppress_tile_only_warning := false  # session-wide "Don't show again"
const UPGRADE_BUTTON_SIZE := Vector2(40, 40)
const STATUS_ICON_SIZE := Vector2(20, 20)
const STATUS_DOT_SIZE := Vector2(8, 8)
const STATUS_RAIL_WIDTH := 30.0
const NORMAL_BUILDING_PANEL_LIMIT := 3
const EXTENDED_BUILDING_PANEL_LIMIT := 4
const FLOW_COMPACT_HEIGHT := 130.0
const FLOW_LARGE_HEIGHT := 130.0
const FLOW_SINGLE_CELL_SIZE := Vector2(110, 110)
const FLOW_GRID_CELL_SIZE := Vector2(62, 62)
const GoodIcons := preload("res://scripts/good_icons.gd")
const BuildingNaming := preload("res://scripts/building_naming.gd")
const GOODS_FRAME := preload("res://assets/ui/goods_frame.tres")  # 9-slice panel frame
const SILVER_FRAME := preload("res://assets/ui/silver_frame.tres")  # beige chroma-keyed out
const CONSTRUCTION_BLUR_SHADER := preload("res://assets/shaders/ui_blur.gdshader")
# Per-building banner art shown in the BuildingImageBanner header, keyed by the
# building's internal_name.
const BUILDING_BANNERS := {
	"mine": "res://assets/building_banners/mine.jpg",
	"furnace": "res://assets/building_banners/furnace.jpg",
	"eaf": "res://assets/building_banners/furnace.jpg",
	"chem_plant": "res://assets/building_banners/chem_plant.jpg",
	"petro_refinery": "res://assets/building_banners/petro_refinery.jpg",
	"poly_plant": "res://assets/building_banners/poly_plant.jpg",
}
var _building_banner_rect: TextureRect = null
var _building_banner_cache: Dictionary = {}
const RECIPE_ARROW_PATH := "res://assets/icons/ui_icons/recipe_arrow.png"
const RECIPE_POWER_ICON_PATH := "res://assets/icons/ui_icons/recipe_power_icon.png"
const UPGRADE_ICON_PATH := "res://assets/icons/ui_icons/upgrade_icon_off_white.png"
const FLOW_ARROW_COMPACT_SIZE := Vector2(96, 58)
const FLOW_ARROW_LARGE_SIZE := Vector2(96, 58)
const FLOW_BADGE_DIAMETER := 24
const FLOW_BADGE_TEXT_SIZE := 14
const STATUS_GREEN := Color("#5BD180")   # DS PALETTE OK
const STATUS_RED := Color("#E66060")     # DS PALETTE DANGER
const STATUS_GREY := Color(0.45, 0.48, 0.52)
const STATUS_YELLOW := Color("#E6B85C")  # DS PALETTE WARN
const ICON_TINT := Color(0.995234, 0.930806, 0.763265)   # off-white (recipe-card bg)
const TOOLTIP_NAVY := Color(0.03, 0.07, 0.13)
const DIAGRAM_NAVY := Color(0.0, 0.119856, 0.243095, 1.0)
const DIAGRAM_PAPER := Color(0.995234, 0.930806, 0.763265, 1.0)
const FLOW_SQUARE_COLOR := Color(1.0, 1.0, 1.0)
const UPGRADE_GREEN := Color(0.25, 0.82, 0.36)
const UPGRADE_RED := Color(0.95, 0.28, 0.24)
const ROUTE_BUTTON_HEIGHT := 45.0
const ROUTE_TO_ACTION_GAP := 5.0
const ROUTE_LINK_FONT_SIZE := 14
const UPGRADE_TILE_SIZE_MULTIPLIER := 0.8
const DENSITY_SOFT_CAPACITY := 100.0

const STATUS_ICON_CONFIG := [
	{
		"key": "power",
		"path": "res://assets/icons/ui_icons/power_status_icon.png",
		"tooltip": "Power status\nGreen: powered by your own supply · Amber: powered via the grid · Red: not powered · Grey: no power needed",
	},
	{
		"key": "input",
		"path": "res://assets/icons/ui_icons/input_status_icon.png",
		"tooltip": "Input status\nGreen: ran with inputs available · Amber: inputs present but idle · Red: missing inputs · Grey: not applicable",
	},
	{
		"key": "duration",
		"path": "res://assets/icons/ui_icons/input_transport_duration_icon.png",
		"tooltip": "Output transport duration\nGreen: arrives same turn · Amber: multi-turn shipment · Grey: building didn't run this turn",
	},
	{
		"key": "cost",
		"path": "res://assets/icons/ui_icons/cost_of_transport_icon.png",
		"tooltip": "Cost of transport\nGreen: no shipping cost · Amber: paying to ship output · Grey: building didn't run this turn",
	},
]

## Emitted whenever the displayed building's connection data changes (or clears on hide).
## origin_tile_id: the building's own tile
## input_tile_ids: tile IDs of buildings supplying this building's inputs
## output_tile_ids: tile IDs where this building's outputs are stockpiled
## has_market_output: true if any output goes to market (no stockpile destination)
signal building_connections_changed(origin_tile_id: String, input_tile_ids: Array, output_tile_ids: Array, has_market_output: bool)

var _dragging := false
var _drag_offset := Vector2.ZERO
var _status_dots: Dictionary = {}
var _cost_label: Panel = null
var _cost_wrapper: HBoxContainer = null
var _tooltip_theme: Theme = null
var _upgrade_button: Button = null
var _upgrade_panel: PanelContainer = null
var _current_building: Dictionary = {}
var _current_recipe: Dictionary = {}
var _route_row: HBoxContainer = null
var _input_route_button: Button = null
var _output_route_button: Button = null
var _input_route_detail: VBoxContainer = null
var _output_route_detail: VBoxContainer = null
var _input_source_rows: Array = []
var _building_panel_template: PanelContainer = null
var _building_panel_instances: Array[PanelContainer] = []
var _pending_dialog_building: Dictionary = {}
var _route_action_spacer: Control = null
var _is_secondary_panel := false
var _allow_extended_building_panels := false
var _busy_screen_dialog: ConfirmationDialog = null
var _too_many_dialog: AcceptDialog = null
var _tile_only_dialog: AcceptDialog = null
var _rag_panel: PanelContainer = null
var _action_button_row: HBoxContainer = null
var _npc_panel: PanelContainer = null
var _npc_label: Label = null
var _construction_overlay: Control = null  # blur + "Under Construction" pill over the diagram
var _showing_construction_instance: String = ""  # instance_id while rendering construction mode

func _ready() -> void:
	_is_secondary_panel = bool(get_meta("is_secondary_building_panel", false))
	if DS and DS.theme:
		theme = DS.theme  # inherit the design-system theme (fonts, buttons, palette)
	if not _is_secondary_panel:
		_prepare_building_panel_template()
	close_button.pressed.connect(_hide_panel)
	_setup_building_banner()
	_apply_goods_frame_border()
	_tooltip_theme = _make_tooltip_theme()
	_style_flow_summary()
	# The status indicators now live in a horizontal strip inside the main column
	# (built by _build_status_icon_column); the old vertical right rail is gone.
	_build_status_icon_column()
	_build_route_controls()
	_build_upgrade_controls()
	_build_npc_panel()
	if not MatchState.output_stockpile_destination_changed.is_connected(_on_output_stockpile_destination_changed):
		MatchState.output_stockpile_destination_changed.connect(_on_output_stockpile_destination_changed)
	if not MatchState.transport_shipments_changed.is_connected(_on_logistics_changed):
		MatchState.transport_shipments_changed.connect(_on_logistics_changed)
	if not Stockpile.stockpile_changed.is_connected(_on_logistics_changed):
		Stockpile.stockpile_changed.connect(_on_logistics_changed)
	if not CostSolver.costs_updated.is_connected(_on_costs_updated):
		CostSolver.costs_updated.connect(_on_costs_updated)
	# A deposit running out must refresh the shown building's RAG dots, production
	# status and recipe diagram (it stops being able to produce).
	if not MatchState.deposits_changed.is_connected(_on_deposit_changed):
		MatchState.deposits_changed.connect(_on_deposit_changed)
	# Keep a shown construction site's countdowns/ETAs live, and cross-fade to the running
	# building when it completes.
	if not Production.turn_processed.is_connected(_on_turn_processed_construction):
		Production.turn_processed.connect(_on_turn_processed_construction)
	if not Construction.construction_materials_updated.is_connected(_on_construction_progress):
		Construction.construction_materials_updated.connect(_on_construction_progress)
	if not Construction.construction_started.is_connected(_on_construction_progress):
		Construction.construction_started.connect(_on_construction_progress)
	if not Construction.construction_completed.is_connected(_on_construction_finished):
		Construction.construction_completed.connect(_on_construction_finished)
	if not Construction.construction_cancelled.is_connected(_on_construction_cancelled_detail):
		Construction.construction_cancelled.connect(_on_construction_cancelled_detail)
	set_meta("panel_ready", true)

func show_building(building: Dictionary) -> void:
	_rebuild_fields(building)
	visible = true
	PanelStack.push(self)
	if _is_secondary_panel:
		_position_as_secondary_panel()
	else:
		_position_for_visible_panels()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
		PanelStack.remove(self)
		if not _is_secondary_panel:
			building_connections_changed.emit("", [], [], false)

func _hide_panel() -> void:
	hide()
	if not _is_secondary_panel:
		for panel in _building_panel_instances:
			if panel != null:
				panel.hide()

# Ornate goods-frame as a 9-slice BORDER around the panel — the navy background is
# kept (the frame's centre is transparent), and the content is padded so it sits
# inside the frame. Added after the template is duplicated so secondaries don't
# inherit a duplicate overlay (each adds its own).
func _apply_goods_frame_border() -> void:
	# Navy background with no content margin so the overlay can reach the panel edge.
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.015686275, 0.058823529, 0.105882353, 1.0)
	bg.set_corner_radius_all(8)
	bg.set_content_margin_all(0)
	add_theme_stylebox_override("panel", bg)
	# Pad the inner content so it clears the ornate frame border.
	if panel_margin != null:
		for side in ["left", "right", "top", "bottom"]:
			panel_margin.add_theme_constant_override("margin_" + side, 26)
	# The frame border itself (transparent centre → navy shows through).
	var frame := NinePatchRect.new()
	frame.name = "GoodsFrameBorder"
	frame.texture = SILVER_FRAME.texture  # beige chroma-keyed out → silver border only
	frame.draw_center = false
	# Cropped plate (transparent margin removed) → smaller 9-slice corners so the
	# silver band sits flush with the panel edge.
	frame.patch_margin_left = 18
	frame.patch_margin_right = 18
	frame.patch_margin_top = 18
	frame.patch_margin_bottom = 18
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)

func _setup_building_banner() -> void:
	if building_image_banner == null:
		return
	_building_banner_rect = TextureRect.new()
	_building_banner_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_building_banner_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_building_banner_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_building_banner_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	building_image_banner.add_child(_building_banner_rect)

func _update_building_banner(building_data: Dictionary) -> void:
	if _building_banner_rect == null:
		return
	var internal := str(building_data.get("internal_name", "")).strip_edges().to_lower()
	var path := str(BUILDING_BANNERS.get(internal, ""))
	if path == "":
		_building_banner_rect.texture = null
		return
	if not _building_banner_cache.has(path):
		_building_banner_cache[path] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_building_banner_rect.texture = _building_banner_cache.get(path)

func _rebuild_fields(building: Dictionary) -> void:
	for child in fields_vbox.get_children():
		child.queue_free()
	_clear_construction_overlay()  # drop any frosted-diagram overlay from a previous render
	_showing_construction_instance = ""

	_current_building = building
	var building_data: Dictionary = Catalog.get_building(building.get("building_id", ""))
	_update_building_banner(building_data)
	var recipe: Dictionary = Catalog.get_recipe(building.get("recipe_id", ""))
	_current_recipe = recipe
	var category: String = building_data.get("category", "")
	var is_infrastructure: bool = category == "infrastructure"

	var owner_id := str(building.get("owner", ""))
	if owner_id == "" and str(building.get("instance_id", "")) != "":
		owner_id = str(MatchState.get_building(str(building.get("instance_id", ""))).get("owner", ""))
	if owner_id != "" and owner_id != "player_1" and owner_id != "tile_data":
		_apply_npc_mode(true)
		if _npc_label != null:
			var is_ruins := str(building.get("building_id", "")) == "b_031"
			_npc_label.text = ("Disused — operated by %s" % owner_id) if is_ruins else ("Building operated by %s" % owner_id)
		title_label.text = _building_display_name(building, building_data, recipe) + _tile_title_suffix(building)
		title_label.tooltip_text = _tile_title_tooltip(building)
		location_label.visible = false
		return
	_apply_npc_mode(false)

	# Construction sites (awaiting materials / under construction) show none of the usual
	# building info — just a frosted diagram and the materials/ETA breakdown.
	var project: Dictionary = Construction.construction_projects.get(str(building.get("instance_id", "")), {})
	if not project.is_empty():
		_render_construction_mode(building, building_data, recipe, project)
		return

	_update_change_recipe_button(building, is_infrastructure)
	title_label.text = _building_display_name(building, building_data, recipe) + _tile_title_suffix(building)
	title_label.tooltip_text = _tile_title_tooltip(building)
	location_label.visible = false
	_update_flow_summary(recipe)
	_refresh_route_controls(building, recipe)
	_update_status_icons(building, recipe, is_infrastructure)
	_add_field("Value", _money_text(building_data.get("base_price", 0.0)))

	if not is_infrastructure and recipe.get("output_name", "") == "power":
		_add_field("Power production", str(recipe.get("output_qty", 0)))


	_add_field("Maintenance cost", _money_text(_maintenance_cost(building_data)))

	if not is_infrastructure and recipe.get("output_name", "") != "power":
		var route_info := _output_route_summary()
		_add_field("Output destination", route_info.destination)
		_add_field("Output transport cost", _format_money(route_info.cost))
		_add_field("Duration to destination", "%d turn%s" % [
			int(route_info.turns), "" if int(route_info.turns) == 1 else "s"
		])

	_add_separator()
	_add_inbound_inputs_section(building, recipe)
	_add_separator()
	_add_labour_table(building_data)
	_add_separator()
	_add_operation_table(building, recipe)

func _build_npc_panel() -> void:
	if _npc_panel != null:
		return
	_npc_panel = PanelContainer.new()
	_npc_panel.visible = false
	_npc_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.45, 0.48, 0.52)  # grey
	style.set_corner_radius_all(6)
	style.set_content_margin_all(16)
	_npc_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	_npc_panel.add_child(vbox)

	_npc_label = Label.new()
	_npc_label.text = "Building operated by another party"
	_npc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_npc_label.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(_npc_label)

	var buy := Button.new()
	buy.text = "Buy"
	buy.disabled = true
	buy.tooltip_text = "Ports cannot be purchased (yet)"
	buy.mouse_filter = Control.MOUSE_FILTER_STOP
	buy.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	vbox.add_child(buy)

	panel_vbox.add_child(_npc_panel)
	panel_vbox.move_child(_npc_panel, flow_summary.get_index() + 1)

func _apply_npc_mode(on: bool) -> void:
	# NPC-owned buildings show only the grey "operated by…" card + a disabled Buy —
	# no recipe diagram, status lights, routes, or upgrade/recipe controls.
	flow_summary.visible = not on
	if _route_row != null:
		_route_row.visible = not on
	if _input_route_detail != null:
		_input_route_detail.visible = false
	if _output_route_detail != null:
		_output_route_detail.visible = false
	if _route_action_spacer != null:
		_route_action_spacer.visible = not on
	if _action_button_row != null:
		_action_button_row.visible = not on
	if _upgrade_panel != null and on:
		_upgrade_panel.visible = false
	if _rag_panel != null:
		_rag_panel.visible = not on
	if _npc_panel != null:
		_npc_panel.visible = on

func _render_construction_mode(building: Dictionary, building_data: Dictionary, recipe: Dictionary, project: Dictionary) -> void:
	var b_name: String = str(building_data.get("display_name", building.get("building_id", "")))
	var recipe_name: String = str(recipe.get("display_name", ""))
	title_label.text = b_name if recipe_name == "" else "%s — %s" % [b_name, recipe_name]
	title_label.tooltip_text = ""
	location_label.visible = false
	_showing_construction_instance = str(building.get("instance_id", ""))
	_update_flow_summary(recipe)  # populate the diagram so there's something to frost
	_hide_operational_controls()
	_apply_construction_overlay()
	_build_construction_materials_section(project)
	_add_cancel_construction_button(str(building.get("instance_id", "")))

func _hide_operational_controls() -> void:
	# Suppress every interactive/info control; the diagram stays (it gets frosted over).
	# NOTE: the close (X) button is reparented INTO status_icon_column, so that column must
	# stay visible — we hide the RAG tray (_rag_panel) instead to drop the status dots.
	change_recipe_button.visible = false
	for node in [_route_row, _input_route_detail, _output_route_detail, _route_action_spacer,
			_action_button_row, _rag_panel, _upgrade_panel, _npc_panel]:
		if node != null:
			node.visible = false

func _apply_construction_overlay() -> void:
	_clear_construction_overlay()
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var blur := ColorRect.new()
	blur.set_anchors_preset(Control.PRESET_FULL_RECT)
	blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = CONSTRUCTION_BLUR_SHADER
	blur.material = mat
	overlay.add_child(blur)

	# Single-row "Under Construction" pill anchored to the diagram's centre.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pill := PanelContainer.new()
	var pill_style := StyleBoxFlat.new()
	pill_style.bg_color = DIAGRAM_NAVY
	pill_style.set_corner_radius_all(4)
	pill_style.set_content_margin_all(8)
	pill.add_theme_stylebox_override("panel", pill_style)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pill_label := Label.new()
	pill_label.text = "Under Construction"
	pill_label.add_theme_color_override("font_color", DIAGRAM_PAPER)
	pill.add_child(pill_label)
	center.add_child(pill)
	overlay.add_child(center)

	flow_summary.add_child(overlay)
	_construction_overlay = overlay

func _clear_construction_overlay() -> void:
	if _construction_overlay != null and is_instance_valid(_construction_overlay):
		_construction_overlay.queue_free()
	_construction_overlay = null

func _add_cancel_construction_button(instance_id: String) -> void:
	var btn := Button.new()
	btn.text = "Cancel construction"
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(func() -> void: _on_cancel_construction_pressed(instance_id))
	fields_vbox.add_child(btn)

func _on_cancel_construction_pressed(instance_id: String) -> void:
	Construction.cancel(instance_id)  # refunds + returns secured materials + frees the site
	_hide_panel()

func _on_turn_processed_construction(_summary: Dictionary) -> void:
	_refresh_if_showing_construction()

func _on_deposit_changed(tile_id: String) -> void:
	# Recompute the whole panel when this building's own deposit changes.
	if not visible or _current_building.is_empty():
		return
	if _showing_construction_instance != "":
		return  # construction view refreshes on its own
	if str(_current_building.get("tile_id", "")) == tile_id:
		_rebuild_fields(_current_building)

func _on_construction_progress(instance_id: String, _tile_id: String) -> void:
	if instance_id == _showing_construction_instance:
		_refresh_if_showing_construction()

func _refresh_if_showing_construction() -> void:
	# Re-render the construction view so material ETAs and the build countdown stay current.
	if not visible or _showing_construction_instance == "":
		return
	if Construction.construction_projects.has(_showing_construction_instance):
		_rebuild_fields(_current_building)

func _on_construction_finished(instance_id: String, _tile_id: String) -> void:
	if not visible or instance_id != _showing_construction_instance:
		return
	_crossfade_to_running(instance_id)

func _on_construction_cancelled_detail(instance_id: String, _tile_id: String) -> void:
	# Whether cancelled from this panel or elsewhere, the site is gone — close the panel.
	if visible and instance_id == _showing_construction_instance:
		_hide_panel()

func _crossfade_to_running(instance_id: String) -> void:
	# 2s cross-dissolve from the frosted construction view to the live, running building.
	var building: Dictionary = MatchState.get_building(instance_id)
	if building.is_empty():
		return
	_showing_construction_instance = ""  # stop per-turn construction refreshes during the swap
	var tween := create_tween()
	tween.tween_property(panel_vbox, "modulate:a", 0.0, 1.0)
	tween.tween_callback(func() -> void: show_building(building))
	tween.tween_property(panel_vbox, "modulate:a", 1.0, 1.0)

func _build_construction_materials_section(project: Dictionary) -> void:
	# Navy card under the diagram: off-white rows, one per material with qty + arrival ETA.
	var status: String = str(project.get("status", Construction.STATUS_UNDER_CONSTRUCTION))
	var tile_id: String = str(project.get("tile_id", ""))
	var navy := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = DIAGRAM_NAVY
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	navy.add_theme_stylebox_override("panel", style)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	navy.add_child(vb)

	var header := Label.new()
	header.text = "Awaiting building materials" if status == Construction.STATUS_AWAITING_MATERIALS else "Under construction"
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", DIAGRAM_PAPER)
	vb.add_child(header)

	var required: Dictionary = project.get("required_materials", {})
	var missing: Dictionary = project.get("missing_materials", {})
	for gid in required:
		var line: String = "%d %s — " % [int(required[gid]), Catalog.get_display_name(str(gid))]
		if missing.has(gid):
			var eta: int = Construction.material_arrival_eta(tile_id, str(gid))
			line += ("arrives in %d turn%s" % [eta, "" if eta == 1 else "s"]) if eta >= 0 else "pending delivery"
		else:
			line += "secured"
		var row := Label.new()
		row.text = line
		row.add_theme_color_override("font_color", DIAGRAM_PAPER)
		vb.add_child(row)

	var duration: int = int(project.get("construction_duration", 0))
	var foot := Label.new()
	if status == Construction.STATUS_UNDER_CONSTRUCTION:
		var rem: int = int(project.get("turns_remaining", 0))
		foot.text = "Construction: %d turn%s remaining" % [rem, "" if rem == 1 else "s"]
	else:
		foot.text = "Construction completes %d turn%s after materials arrive" % [duration, "" if duration == 1 else "s"]
	foot.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	vb.add_child(foot)
	fields_vbox.add_child(navy)

func _add_text(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fields_vbox.add_child(label)

func _add_field(field_name: String, value: String) -> void:
	_add_text("%s: %s" % [field_name, value])

func _add_separator() -> void:
	var separator := HSeparator.new()
	fields_vbox.add_child(separator)

func _add_section_label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.modulate = Color(0.7, 0.85, 1.0)
	fields_vbox.add_child(label)

func _add_inbound_inputs_section(building: Dictionary, recipe: Dictionary) -> void:
	var inputs: Array = recipe.get("inputs", [])
	if inputs.is_empty():
		return
	_add_section_label("Receiving inputs")
	var tile_id: String = building.get("tile_id", "")
	for input in inputs:
		var good_id: String = input.get("good_id", "")
		var needed := int(input.get("qty", 0))
		var stored := Stockpile.get_at_tile(tile_id, good_id)
		var line := "%s: %d/%d stored" % [
			_good_display_from_internal(input.get("internal_name", "")),
			stored,
			needed,
		]
		var inbound_summary := _inbound_input_summary(tile_id, good_id)
		if inbound_summary != "":
			line += " · " + inbound_summary
		else:
			line += " · no inbound shipment scheduled"
		_add_text(line)

func _show_tile_only_warning() -> void:
	if _tile_only_dialog == null:
		_tile_only_dialog = AcceptDialog.new()
		_tile_only_dialog.title = "Tile stockpile only"
		_tile_only_dialog.dialog_text = "This may make your buildings stop producing when the stockpile is insufficient."
		var checkbox := UIHelpers.make_custom_checkbox()
		checkbox.toggled.connect(func(pressed: bool) -> void: _suppress_tile_only_warning = pressed)
		var row := UIHelpers.make_setting_row("Don't show again", checkbox)
		_tile_only_dialog.add_child(row)
		get_parent().add_child(_tile_only_dialog)
	_tile_only_dialog.popup_centered()

func _inbound_input_summary(tile_id: String, good_id: String) -> String:
	var shipments := MatchState.get_inbound_transport_shipments(tile_id, good_id)
	if shipments.is_empty():
		return ""
	shipments.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("turns_remaining", 0)) < int(b.get("turns_remaining", 0))
	)
	var next_turns := int(shipments[0].get("turns_remaining", 0))
	var source_tiles: Array = []
	var total_qty := 0
	for shipment in shipments:
		total_qty += int(shipment.get("qty", 0))
		var source_tile: String = shipment.get("source_tile", "")
		if source_tile != "" and not source_tiles.has(source_tile):
			source_tiles.append(source_tile)
	var source_labels: Array = []
	for st in source_tiles:
		source_labels.append(Catalog.tile_label(st))
	var source_text := ", ".join(source_labels) if not source_labels.is_empty() else "unknown tile"
	return "%d inbound from %s, next %s" % [
		total_qty,
		source_text,
		_arrival_text(next_turns),
	]

func _arrival_text(turns_remaining: int) -> String:
	if turns_remaining <= 1:
		return "next turn"
	return "in %d turns" % turns_remaining

func _add_labour_table(building_data: Dictionary) -> void:
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 6)
	fields_vbox.add_child(header_row)

	var hardhat_icon := Label.new()
	hardhat_icon.text = "[H]"
	hardhat_icon.tooltip_text = "Hardhat"
	hardhat_icon.custom_minimum_size = Vector2(28, 0)
	header_row.add_child(hardhat_icon)

	var title := Label.new()
	title.text = "Labour"
	title.modulate = Color(0.7, 0.85, 1.0)
	header_row.add_child(title)

	var table := GridContainer.new()
	table.columns = 3
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.add_theme_constant_override("h_separation", 12)
	table.add_theme_constant_override("v_separation", 4)
	fields_vbox.add_child(table)

	table.add_child(_make_table_cell("Type", true, 120.0))
	table.add_child(_make_table_cell("Count", true, 52.0))
	table.add_child(_make_table_cell("Cost", true, 70.0))

	_add_labour_row(table, "Unskilled", building_data.get("labour_unskilled_required", 0), EconomyConfig.LABOUR_UNSKILLED_RATE)
	_add_labour_row(table, "Skilled", building_data.get("labour_skilled_required", 0), EconomyConfig.LABOUR_SKILLED_RATE)
	_add_labour_row(table, "Highly Skilled", building_data.get("labour_h_skilled_required", 0), EconomyConfig.LABOUR_HIGH_SKILLED_RATE)

func _add_labour_row(table: GridContainer, label: String, count_value: Variant, rate: float) -> void:
	var count := int(count_value)
	var cost := float(count) * rate * MatchState.labour_multiplier
	table.add_child(_make_table_cell(label, false, 120.0))
	table.add_child(_make_table_cell(str(count), false, 52.0))
	table.add_child(_make_table_cell("%.2f" % cost, false, 70.0))

func _add_operation_table(building: Dictionary, recipe: Dictionary) -> void:
	_add_section_label("Operation")

	var table := GridContainer.new()
	table.columns = 2
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.add_theme_constant_override("h_separation", 12)
	table.add_theme_constant_override("v_separation", 4)
	fields_vbox.add_child(table)

	table.add_child(_make_table_cell("Metric", true, 175.0))
	table.add_child(_make_table_cell("Value", true, 100.0))
	table.add_child(_make_table_cell("Produced since construction", false, 175.0))
	table.add_child(_make_table_cell(_produced_since_construction(building, recipe), false, 100.0))
	table.add_child(_make_table_cell("Turns at full output", false, 175.0))
	table.add_child(_make_table_cell(str(_full_output_streak(building)), false, 100.0))

func _make_table_cell(text: String, is_header: bool, min_width: float = 0.0) -> Label:
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if min_width > 0.0:
		label.custom_minimum_size = Vector2(min_width, 0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if is_header:
		label.modulate = Color(0.7, 0.85, 1.0)
	return label

func _build_status_right_rail() -> void:
	if panel_margin.get_node_or_null("BuildingDetailLayout") != null:
		return
	var current_parent := panel_vbox.get_parent()
	if current_parent != panel_margin:
		return
	panel_margin.remove_child(panel_vbox)
	var layout := HBoxContainer.new()
	layout.name = "BuildingDetailLayout"
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 8)
	panel_margin.add_child(layout)
	panel_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(panel_vbox)
	if status_icon_column.get_parent() != null:
		status_icon_column.get_parent().remove_child(status_icon_column)
	status_icon_column.custom_minimum_size = Vector2(STATUS_RAIL_WIDTH, 0)
	status_icon_column.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	status_icon_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	status_icon_column.alignment = BoxContainer.ALIGNMENT_BEGIN
	status_icon_column.add_theme_constant_override("separation", 6)
	layout.add_child(status_icon_column)
	if close_button.get_parent() != status_icon_column:
		close_button.get_parent().remove_child(close_button)
		close_button.custom_minimum_size = Vector2(STATUS_RAIL_WIDTH, 28)
		close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		status_icon_column.add_child(close_button)

func _build_route_controls() -> void:
	_route_row = HBoxContainer.new()
	_route_row.custom_minimum_size = Vector2(0, ROUTE_BUTTON_HEIGHT)
	_route_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_route_row.add_theme_constant_override("separation", 8)

	_input_route_button = _make_route_button("Inputs", "", _on_input_route_pressed)
	_output_route_button = _make_route_button("Outputs", "", _on_output_route_pressed)
	_route_row.add_child(_input_route_button)
	_route_row.add_child(_output_route_button)

	panel_vbox.add_child(_route_row)
	panel_vbox.move_child(_route_row, flow_summary.get_index() + 1)

	_input_route_detail = VBoxContainer.new()
	_input_route_detail.visible = false
	_input_route_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input_route_detail.add_theme_constant_override("separation", 6)
	panel_vbox.add_child(_input_route_detail)
	panel_vbox.move_child(_input_route_detail, _route_row.get_index() + 1)

	_output_route_detail = VBoxContainer.new()
	_output_route_detail.visible = false
	_output_route_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_output_route_detail.add_theme_constant_override("separation", 6)
	panel_vbox.add_child(_output_route_detail)
	panel_vbox.move_child(_output_route_detail, _input_route_detail.get_index() + 1)

	_route_action_spacer = Control.new()
	_route_action_spacer.custom_minimum_size = Vector2(0, ROUTE_TO_ACTION_GAP)
	panel_vbox.add_child(_route_action_spacer)
	panel_vbox.move_child(_route_action_spacer, _output_route_detail.get_index() + 1)

func _make_route_button(title: String, subtitle: String, pressed_method: Callable) -> Button:
	var button := Button.new()
	button.text = ""
	button.custom_minimum_size = Vector2(0, ROUTE_BUTTON_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.clip_contents = true
	button.pressed.connect(pressed_method)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.add_child(content)

	var title_label := Label.new()
	title_label.name = "Title"
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 12)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(title_label)

	var subtitle_label := Label.new()
	subtitle_label.name = "Subtitle"
	subtitle_label.text = subtitle
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.add_theme_font_size_override("font_size", 10)
	subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(subtitle_label)

	return button

func _set_route_button_text(button: Button, title: String, subtitle: String) -> void:
	if button == null:
		return
	var title_label := button.get_node_or_null("Content/Title") as Label
	var subtitle_label := button.get_node_or_null("Content/Subtitle") as Label
	if title_label != null:
		title_label.text = title
	if subtitle_label != null:
		subtitle_label.text = subtitle

func _refresh_route_controls(building: Dictionary, recipe: Dictionary) -> void:
	_input_source_rows = _find_input_source_rows(building, recipe)
	var recipe_inputs: Array = recipe.get("inputs", [])
	var input_subtitle: String = "No inputs" if recipe_inputs.is_empty() else "No linked inputs"
	if _input_source_rows.size() == 1:
		input_subtitle = _input_source_rows[0].get("building_name", "")
	elif _input_source_rows.size() > 1:
		input_subtitle = "See all buildings"
	_set_route_button_text(_input_route_button, "Inputs", input_subtitle)
	_input_route_button.disabled = recipe_inputs.is_empty()  # enabled when there are inputs to source

	_set_route_button_text(_output_route_button, "Outputs", _output_destination())
	_output_route_button.disabled = _flow_output_items(recipe).is_empty()

	_input_route_detail.visible = false
	_output_route_detail.visible = false
	_rebuild_input_route_detail()
	_rebuild_output_route_detail()
	_emit_building_connections(building, recipe)

func _emit_building_connections(building: Dictionary, recipe: Dictionary) -> void:
	var origin_tile_id: String = building.get("tile_id", "")
	var instance_id: String = building.get("instance_id", "")

	# Collect input source tile IDs (deduplicated)
	var input_tile_ids: Array = []
	for row in _input_source_rows:
		var src_tile_id: String = row.get("building", {}).get("tile_id", "")
		if src_tile_id != "" and src_tile_id != origin_tile_id and not input_tile_ids.has(src_tile_id):
			input_tile_ids.append(src_tile_id)

	# Collect output destination tile IDs and detect market outputs
	var output_tile_ids: Array = []
	var has_market_output := false
	for output in _flow_output_items(recipe):
		var good_id: String = output.get("good_id", "")
		if good_id == "":
			var good: Dictionary = Catalog.get_good_by_internal_name(output.get("internal_name", ""))
			good_id = good.get("id", "")
		if good_id == "":
			continue
		var dest: String = MatchState.get_output_stockpile_destination(instance_id, good_id)
		if dest != "" and dest != origin_tile_id and not output_tile_ids.has(dest):
			output_tile_ids.append(dest)
		elif dest == "":
			has_market_output = true

	building_connections_changed.emit(origin_tile_id, input_tile_ids, output_tile_ids, has_market_output)

func _find_input_source_rows(building: Dictionary, recipe: Dictionary) -> Array:
	var rows: Array = []
	var inputs: Array = recipe.get("inputs", [])
	var current_instance_id: String = building.get("instance_id", "")
	var current_tile_id: String = building.get("tile_id", "")
	for input in inputs:
		var producers: Array = _producers_for_input(input, current_instance_id, current_tile_id)
		for producer in producers:
			var producer_recipe: Dictionary = Catalog.get_recipe(producer.get("recipe_id", ""))
			var producer_data: Dictionary = Catalog.get_building(producer.get("building_id", ""))
			rows.append({
				"input_name": _good_display_from_internal(input.get("internal_name", "")),
				"building": producer,
				"building_name": _building_display_name(producer, producer_data, producer_recipe),
			})
	return rows

func _producers_for_input(input: Dictionary, current_instance_id: String, current_tile_id: String) -> Array:
	var producers: Array = []
	var input_good_id: String = input.get("good_id", "")
	var input_internal_name: String = input.get("internal_name", "")
	for building in MatchState.buildings.values():
		if building.get("instance_id", "") == current_instance_id:
			continue
		var recipe: Dictionary = Catalog.get_recipe(building.get("recipe_id", ""))
		for output in _flow_output_items(recipe):
			if _good_matches_input(output, input_good_id, input_internal_name) and _producer_routes_output_to_tile(building, output, current_tile_id):
				producers.append(building)
				break
	return producers

func _good_matches_input(output: Dictionary, input_good_id: String, input_internal_name: String) -> bool:
	var output_good_id: String = output.get("good_id", "")
	if input_good_id != "" and output_good_id != "":
		return input_good_id == output_good_id
	return output.get("internal_name", "") == input_internal_name

func _producer_routes_output_to_tile(producer: Dictionary, output: Dictionary, tile_id: String) -> bool:
	if tile_id == "":
		return false
	var good_id: String = output.get("good_id", "")
	if good_id == "":
		var internal_name: String = output.get("internal_name", "")
		var good: Dictionary = Catalog.get_good_by_internal_name(internal_name)
		good_id = good.get("id", "")
	if good_id == "":
		return false
	return MatchState.get_output_stockpile_destination(producer.get("instance_id", ""), good_id) == tile_id

func _on_input_route_pressed() -> void:
	_input_route_detail.visible = not _input_route_detail.visible
	_output_route_detail.visible = false

func _on_output_route_pressed() -> void:
	_output_route_detail.visible = not _output_route_detail.visible
	_input_route_detail.visible = false

func _on_output_stockpile_destination_changed(instance_id: String, _tile_id: String, _good_id: String) -> void:
	if not visible:
		return
	if _current_building.get("instance_id", "") != instance_id:
		return
	_refresh_route_controls(_current_building, _current_recipe)

func _on_logistics_changed() -> void:
	if not visible or _current_building.is_empty():
		return
	_rebuild_fields(_current_building)

func _rebuild_input_route_detail() -> void:
	for child in _input_route_detail.get_children():
		child.queue_free()

	# Per-input source selector: Tile stockpile or Market (buy from nearest port).
	var instance_id := str(_current_building.get("instance_id", ""))
	for input in _current_recipe.get("inputs", []):
		var good_id := str(input.get("good_id", ""))
		if good_id == "":
			continue
		var sel_row := HBoxContainer.new()
		sel_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sel_row.add_theme_constant_override("separation", 8)
		var name_lbl := Label.new()
		name_lbl.text = _good_display_from_internal(input.get("internal_name", ""))
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", ROUTE_LINK_FONT_SIZE)
		sel_row.add_child(name_lbl)
		var opt := OptionButton.new()
		opt.add_item("Stockpile then market")  # index 0 (default)
		opt.add_item("Tile stockpile only")    # index 1
		opt.select(1 if MatchState.is_input_tile_only(instance_id, good_id) else 0)
		opt.item_selected.connect(func(idx: int) -> void:
			var tile_only := idx == 1
			MatchState.set_input_tile_only(instance_id, good_id, tile_only)
			if tile_only and not _suppress_tile_only_warning:
				_show_tile_only_warning()
		)
		sel_row.add_child(opt)
		_input_route_detail.add_child(sel_row)

	for row in _input_source_rows:
		var line := HBoxContainer.new()
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_theme_constant_override("separation", 8)
		_input_route_detail.add_child(line)

		var label := Label.new()
		label.text = "%s: %s" % [row.get("input_name", "Input"), row.get("building_name", "Building")]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", ROUTE_LINK_FONT_SIZE)
		line.add_child(label)

		var go_to := LinkButton.new()
		go_to.text = "Go to"
		go_to.add_theme_font_size_override("font_size", ROUTE_LINK_FONT_SIZE)
		var source_building: Dictionary = row.get("building", {})
		go_to.pressed.connect(func() -> void:
			_open_secondary_building(source_building)
		)
		line.add_child(go_to)

func _rebuild_output_route_detail() -> void:
	for child in _output_route_detail.get_children():
		child.queue_free()

	var instance_id: String = _current_building.get("instance_id", "")
	var source_tile: String = str(_current_building.get("tile_id", ""))
	# One routing row PER output good, so every output of a multi-output recipe can be
	# directed independently (the old single control only routed the primary output).
	for good_id in _output_good_ids(_current_recipe):
		_output_route_detail.add_child(_make_output_route_row(instance_id, source_tile, good_id))

# All distinct output good ids of a recipe (resolving internal names).
func _output_good_ids(recipe: Dictionary) -> Array:
	var ids: Array = []
	for o in _flow_output_items(recipe):
		var gid := str(o.get("good_id", ""))
		if gid == "":
			var internal := str(o.get("internal_name", ""))
			if internal != "":
				gid = str(Catalog.get_good_by_internal_name(internal).get("id", ""))
		if gid != "" and not ids.has(gid):
			ids.append(gid)
	return ids

func _make_output_route_row(instance_id: String, source_tile: String, good_id: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var name_lbl := Label.new()
	name_lbl.text = Catalog.get_display_name(good_id)
	name_lbl.add_theme_font_size_override("font_size", ROUTE_LINK_FONT_SIZE)
	box.add_child(name_lbl)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 6)
	btns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(btns)

	var is_market := MatchState.is_output_market(instance_id, good_id)
	var dest := MatchState.get_output_stockpile_destination(instance_id, good_id)
	var on_tile := dest != "" and dest == source_tile
	var other_tile := dest != "" and dest != source_tile

	var market_btn := _make_route_choice_button("Market", is_market)
	market_btn.pressed.connect(func() -> void:
		# Route THIS output good to market — does not flip the global sell mode.
		MatchState.route_output_to_market(instance_id, good_id)
		_refresh_route_controls(_current_building, _current_recipe)
		_output_route_detail.visible = true
	)
	btns.add_child(market_btn)

	# "Store on tile" records this tile as the destination directly (no map mode).
	var store_btn := _make_route_choice_button("Store on tile", on_tile)
	store_btn.disabled = source_tile == ""
	store_btn.pressed.connect(func() -> void:
		MatchState.set_output_stockpile_destination(instance_id, source_tile, good_id)
		_refresh_route_controls(_current_building, _current_recipe)
		_output_route_detail.visible = true
	)
	btns.add_child(store_btn)

	# "Send to other tile" opens the logistics map mode to pick a destination tile.
	var other_btn := _make_route_choice_button("Send to other tile", other_tile)
	other_btn.pressed.connect(func() -> void:
		MatchState.begin_output_stockpile_selection(instance_id, good_id)
		_output_route_detail.visible = false
	)
	btns.add_child(other_btn)
	return box

func _make_route_choice_button(text: String, active: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, ROUTE_BUTTON_HEIGHT)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.toggle_mode = true                 # pressed state shows the active destination
	b.button_pressed = active
	b.focus_mode = Control.FOCUS_NONE
	return b

func _open_secondary_building(building: Dictionary) -> void:
	if building.is_empty():
		return
	if _is_secondary_panel:
		var manager: Node = _building_panel_manager()
		if manager != null:
			manager.call("_request_open_building_panel", building)
		return
	_request_open_building_panel(building)

func _request_open_building_panel(building: Dictionary) -> void:
	if _is_secondary_panel:
		var manager: Node = _building_panel_manager()
		if manager != null:
			manager.call("_request_open_building_panel", building)
		return
	var visible_count: int = _visible_building_panels().size()
	if visible_count >= EXTENDED_BUILDING_PANEL_LIMIT:
		_show_too_many_building_panels_dialog()
		return
	if visible_count >= NORMAL_BUILDING_PANEL_LIMIT and not _allow_extended_building_panels:
		_pending_dialog_building = building
		_show_busy_screen_dialog()
		return
	var target_panel: PanelContainer = _next_available_building_panel()
	if target_panel == null:
		_show_too_many_building_panels_dialog()
		return
	target_panel.call("show_building", building)
	_position_visible_building_panels()

func _prepare_building_panel_template() -> void:
	if _building_panel_template != null:
		return
	var duplicate_panel: Node = duplicate()
	_building_panel_template = duplicate_panel as PanelContainer
	if _building_panel_template != null:
		_building_panel_template.set_meta("is_building_panel_template", true)
		_building_panel_template.hide()

func _next_available_building_panel() -> PanelContainer:
	for panel in _building_panel_instances:
		if panel != null and not panel.visible:
			return panel
	if _building_panel_instances.size() >= EXTENDED_BUILDING_PANEL_LIMIT - 1:
		return null
	return _create_building_panel_instance()

func _create_building_panel_instance() -> PanelContainer:
	if _building_panel_template == null:
		_prepare_building_panel_template()
	if _building_panel_template == null:
		return null
	var duplicate_panel: Node = _building_panel_template.duplicate()
	duplicate_panel.name = "BuildingDetailPanel%d" % (_building_panel_instances.size() + 2)
	duplicate_panel.unique_name_in_owner = false
	duplicate_panel.set_meta("is_secondary_building_panel", true)
	get_parent().add_child(duplicate_panel)
	var panel: PanelContainer = duplicate_panel as PanelContainer
	if panel == null:
		return null
	panel.hide()
	_building_panel_instances.append(panel)
	return panel

func _visible_building_panels() -> Array[PanelContainer]:
	var panels: Array[PanelContainer] = []
	if visible:
		panels.append(self)
	for panel in _building_panel_instances:
		if panel != null and panel.visible:
			panels.append(panel)
	return panels

func _building_panel_manager() -> Node:
	if not _is_secondary_panel:
		return self
	if get_parent() == null:
		return null
	return get_parent().get_node_or_null("BuildingDetailPanel")

func _show_busy_screen_dialog() -> void:
	if _busy_screen_dialog == null:
		_busy_screen_dialog = ConfirmationDialog.new()
		_busy_screen_dialog.title = "Screen is getting busy"
		_busy_screen_dialog.dialog_text = "Screen is getting busy, do you want to close all non-building panels?"
		_busy_screen_dialog.confirmed.connect(_on_busy_screen_confirmed)
		get_parent().add_child(_busy_screen_dialog)
		_busy_screen_dialog.get_ok_button().text = "Yes, close them"
		_busy_screen_dialog.get_cancel_button().text = "Cancel"
	_busy_screen_dialog.popup_centered()

func _on_busy_screen_confirmed() -> void:
	_allow_extended_building_panels = true
	_close_non_building_panels()
	var building: Dictionary = _pending_dialog_building
	_pending_dialog_building = {}
	if not building.is_empty():
		_request_open_building_panel(building)
	_position_visible_building_panels()

func _show_too_many_building_panels_dialog() -> void:
	if _too_many_dialog == null:
		_too_many_dialog = AcceptDialog.new()
		_too_many_dialog.title = "Too many building panels"
		_too_many_dialog.dialog_text = "There are too many building panels open at the same time. Close some before opening another."
		get_parent().add_child(_too_many_dialog)
	_too_many_dialog.popup_centered()

func _close_non_building_panels() -> void:
	var panel_names: Array = [
		"TileInfoPanel",
		"ConstructPanel",
		"MapModesPanel",
		"ResourcePanel",
		"MarketPanel",
	]
	for panel_name in panel_names:
		var panel: CanvasItem = get_parent().get_node_or_null(panel_name) as CanvasItem
		if panel != null:
			panel.hide()

func _position_visible_building_panels() -> void:
	if _is_secondary_panel:
		return
	var panels: Array[PanelContainer] = _visible_building_panels()
	if panels.is_empty():
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var right_edge := viewport_size.x - PANEL_EDGE_MARGIN
	var top_edge := TOP_BAR_CLEARANCE
	var tile_panel := get_parent().get_node_or_null("TileInfoPanel") as Control
	if tile_panel != null and tile_panel.visible:
		right_edge = tile_panel.global_position.x - PANEL_EDGE_MARGIN
		top_edge = maxf(tile_panel.global_position.y, TOP_BAR_CLEARANCE)
	for i in range(panels.size()):
		var panel: PanelContainer = panels[i]
		if panel.custom_minimum_size.x > 0.0 and panel.custom_minimum_size.y > 0.0:
			panel.size = panel.custom_minimum_size
		var panel_size := panel.size
		if panel_size.x <= 0.0:
			panel_size.x = panel.custom_minimum_size.x
		if panel_size.y <= 0.0:
			panel_size.y = panel.custom_minimum_size.y
		var x := right_edge - panel_size.x - (float(i) * (panel_size.x + PANEL_EDGE_MARGIN))
		x = clampf(x, PANEL_EDGE_MARGIN, viewport_size.x - panel_size.x - PANEL_EDGE_MARGIN)
		var y := clampf(top_edge, PANEL_EDGE_MARGIN, viewport_size.y - panel_size.y - PANEL_EDGE_MARGIN)
		panel.global_position = Vector2(x, y)

func _position_as_secondary_panel() -> void:
	if custom_minimum_size.x > 0.0 and custom_minimum_size.y > 0.0:
		size = custom_minimum_size
	var panel_size := size
	if panel_size.x <= 0.0:
		panel_size.x = custom_minimum_size.x
	if panel_size.y <= 0.0:
		panel_size.y = custom_minimum_size.y
	var primary_panel := get_parent().get_node_or_null("BuildingDetailPanel") as Control
	if primary_panel == null:
		_position_for_visible_panels()
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var target_x := primary_panel.global_position.x - panel_size.x - PANEL_EDGE_MARGIN
	target_x = clampf(target_x, PANEL_EDGE_MARGIN, viewport_size.x - panel_size.x - PANEL_EDGE_MARGIN)
	var target_y := clampf(primary_panel.global_position.y, PANEL_EDGE_MARGIN, viewport_size.y - panel_size.y - PANEL_EDGE_MARGIN)
	global_position = Vector2(target_x, target_y)

func _build_upgrade_controls() -> void:
	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 8)
	button_row.custom_minimum_size = Vector2(0, 30)
	button_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action_button_row = button_row
	var row_index := change_recipe_button.get_index()

	_upgrade_button = Button.new()
	_upgrade_button.custom_minimum_size = UPGRADE_BUTTON_SIZE
	_upgrade_button.tooltip_text = "Upgrade"
	_upgrade_button.icon = load(UPGRADE_ICON_PATH) as Texture2D
	_upgrade_button.expand_icon = true
	_upgrade_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_upgrade_button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	_upgrade_button.theme_type_variation = "BuildIcon"  # DS light-blue square icon button
	_upgrade_button.pressed.connect(_on_upgrade_button_pressed)
	button_row.add_child(_upgrade_button)

	panel_vbox.add_child(button_row)
	panel_vbox.move_child(button_row, row_index)

	panel_vbox.remove_child(change_recipe_button)
	change_recipe_button.custom_minimum_size = Vector2(0, 30)
	change_recipe_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button_row.add_child(change_recipe_button)

	_upgrade_panel = _make_upgrade_panel()
	panel_vbox.add_child(_upgrade_panel)
	panel_vbox.move_child(_upgrade_panel, button_row.get_index() + 1)

func _make_upgrade_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.visible = false
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.03, 0.08, 0.14, 0.98)
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.42, 0.68, 0.88, 0.75)
	panel_style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", panel_style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var title := _make_upgrade_label("Upgrade to level 2.", Color.WHITE, 15)
	vbox.add_child(title)
	vbox.add_child(_make_upgrade_label("Cost: X, Materials required: A, B, C", Color.WHITE, 13))
	vbox.add_child(HSeparator.new())
	vbox.add_child(_make_upgrade_label("Output modifier: +150%", UPGRADE_GREEN, 13))
	vbox.add_child(_make_upgrade_label("Power req: +100%", UPGRADE_RED, 13))
	vbox.add_child(_make_upgrade_label("Tile size required: +80%", UPGRADE_RED, 13))
	vbox.add_child(_make_upgrade_label("Maintenance required: +80%", UPGRADE_RED, 13))
	vbox.add_child(_make_upgrade_label("Labour costs: +80%", UPGRADE_RED, 13))
	var note := _make_upgrade_label("Note - output rounds to the nearest integer", Color(0.78, 0.84, 0.9), 11)
	note.add_theme_font_override("font", get_theme_default_font())
	vbox.add_child(note)

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 8)
	vbox.add_child(button_row)

	var upgrade_button := Button.new()
	upgrade_button.text = "Upgrade"
	upgrade_button.pressed.connect(_on_upgrade_confirm_pressed)
	button_row.add_child(upgrade_button)

	var cancel_button := Button.new()
	cancel_button.text = "Cancel"
	cancel_button.pressed.connect(_hide_upgrade_panel)
	button_row.add_child(cancel_button)

	return panel

func _make_upgrade_label(text: String, color: Color, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _on_upgrade_button_pressed() -> void:
	if _upgrade_panel == null:
		return
	_upgrade_panel.visible = not _upgrade_panel.visible

func _hide_upgrade_panel() -> void:
	if _upgrade_panel != null:
		_upgrade_panel.visible = false

func _on_upgrade_confirm_pressed() -> void:
	var tile_id: String = _current_building.get("tile_id", "")
	var building_id: String = _current_building.get("building_id", "")
	if tile_id == "" or building_id == "":
		return
	var building_data := Catalog.get_building(building_id)
	var added_space := float(building_data.get("tile_size_used", 1.0)) * UPGRADE_TILE_SIZE_MULTIPLIER
	var projected_space := MatchState.get_tile_space_used(tile_id) + added_space
	if projected_space > float(MatchState.MAX_TILE_LAND):
		_show_tile_space_toast("There is no more room on that tile. Demolish buildings to make room.", "show_error")
		return
	if projected_space > float(MatchState.get_tile_land_owned(tile_id)):
		_show_tile_space_toast("You cannot build that. You do not own sufficient land on tile %s" % tile_id, "show_error")
		return
	if projected_space > DENSITY_SOFT_CAPACITY:
		_show_tile_space_toast("Local opposition to density on tile %s will increase material and money costs for new buildings by 50%%" % tile_id, "show_caution")

func _show_tile_space_toast(message: String, method_name: String) -> void:
	var toast := get_tree().root.find_child("ToastLayer", true, false)
	if toast != null and toast.has_method(method_name):
		toast.call(method_name, message)
	else:
		push_warning(message)

func _update_change_recipe_button(building: Dictionary, is_infrastructure: bool) -> void:
	if change_recipe_button == null:
		return
	change_recipe_button.visible = true  # restore it after a construction-mode render hid it
	if is_infrastructure:
		change_recipe_button.text = "Change Recipe (0 recipes)"
		return
	var building_id: String = building.get("building_id", "")
	var recipe_count: int = Catalog.get_recipes_for_building(building_id).size()
	var alternate_count: int = maxi(0, recipe_count - 1)
	change_recipe_button.text = "Change Recipe (%d recipes)" % alternate_count

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
	var inputs: Array = (recipe.get("inputs", []) as Array).duplicate()
	# Deposit requirements (mines etc.) show as an input cell — greyed "EXHAUSTED"
	# once the tile's deposit runs out.
	inputs.append_array(_recipe_deposit_items(recipe))
	# Solar/wind have no good inputs — show their tile potential as a text cell.
	var potential := _recipe_potential(recipe)
	if potential != "":
		inputs.append({"_potential": potential})
	var outputs: Array = _flow_output_items(recipe)
	var large_layout: bool = inputs.size() >= 2 or outputs.size() >= 2
	_resize_flow_summary(large_layout)
	_populate_flow_grid(input_grid, inputs, true)
	_populate_flow_grid(output_grid, outputs, false)
	_update_flow_power(recipe)

func _resize_flow_summary(large_layout: bool) -> void:
	var height := FLOW_LARGE_HEIGHT if large_layout else FLOW_COMPACT_HEIGHT
	flow_summary.custom_minimum_size = Vector2(0, height)
	input_preview.custom_minimum_size = Vector2(0, height)
	output_preview.custom_minimum_size = Vector2(0, height)
	flow_arrow.custom_minimum_size = FLOW_ARROW_LARGE_SIZE if large_layout else FLOW_ARROW_COMPACT_SIZE
	flow_arrow.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _populate_flow_grid(grid: GridContainer, goods: Array, is_input: bool = false) -> void:
	for child in grid.get_children():
		child.queue_free()

	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("v_separation", 0)
	var count: int = max(goods.size(), 1)
	grid.columns = 2 if count > 2 else 1
	var cell_size := _flow_cell_size(goods.size())
	# A single input/output is shown large (one 92px cell) so it uses the medium
	# master; a 2x2 grid crams several into 52px cells, so those use the small
	# variant to keep VRAM down.
	var prefer_small := goods.size() > 1

	if goods.is_empty():
		grid.add_child(_make_flow_cell({}, cell_size, prefer_small, is_input))
		return

	for good_item in goods:
		grid.add_child(_make_flow_cell(good_item, cell_size, prefer_small, is_input))

func _flow_cell_size(good_count: int) -> Vector2:
	if good_count <= 1:
		return FLOW_SINGLE_CELL_SIZE
	return FLOW_GRID_CELL_SIZE

func _make_flow_cell(good_item: Dictionary, cell_size: Vector2, prefer_small: bool, is_input: bool = false) -> Panel:
	# Tile potential (wind/solar) inputs render as text inside the icon cell.
	if good_item.has("_potential"):
		return _make_potential_flow_cell(str(good_item["_potential"]), cell_size)
	var cell := Panel.new()
	cell.custom_minimum_size = cell_size
	var texture: Texture2D = GoodIcons.texture_for(
		good_item.get("good_id", ""), good_item.get("internal_name", ""), prefer_small)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 1.0, 0.0) if texture != null else FLOW_SQUARE_COLOR
	# Supply source (your supply vs market) is kept as a hover tooltip only — the
	# coloured border read as a stray dark-yellow square, so it's been removed.
	if is_input:
		var src_good_id := _flow_cell_good_id(good_item)
		var instance_id := str(_current_building.get("instance_id", ""))
		if src_good_id != "" and instance_id != "":
			var from_player := MatchState.is_input_tile_only(instance_id, src_good_id)
			cell.tooltip_text = "Supplied by you" if from_player else "Supplied by the market"
	cell.add_theme_stylebox_override("panel", style)

	var exhausted := _flow_item_exhausted(good_item)
	if texture != null:
		var texture_rect := TextureRect.new()
		texture_rect.texture = texture
		texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if exhausted:
			texture_rect.modulate = Color(0.5, 0.5, 0.5, 0.85)  # greyed out
		cell.add_child(texture_rect)

	if exhausted:
		_add_exhausted_overlay(cell)
	else:
		_add_flow_quantity_badge(cell, good_item, cell_size)

	return cell

# "EXHAUSTED" ribbon over a mined-out deposit cell in the recipe diagram.
func _add_exhausted_overlay(cell: Panel) -> void:
	var label := Label.new()
	label.text = "EXHAUSTED"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ls := LabelSettings.new()
	ls.font_color = STATUS_RED
	ls.font_size = 11
	ls.outline_color = Color(0, 0, 0, 0.85)
	ls.outline_size = 4
	label.label_settings = ls
	cell.add_child(label)
	cell.tooltip_text = "This deposit is exhausted — the building can no longer produce."

# Deposit requirements as flow-input items (one per "deposit" requirement).
# The CSV deposit token "water" maps to the pure_water good.
func _recipe_deposit_items(recipe: Dictionary) -> Array:
	var items: Array = []
	for req in recipe.get("requirements", []):
		if str(req.get("type", "")) != "deposit":
			continue
		var token := str(req.get("value", ""))
		if token == "":
			continue
		var internal := "pure_water" if token == "water" else token
		var good: Dictionary = Catalog.get_good_by_internal_name(internal)
		items.append({
			"good_id": str(good.get("id", internal)),
			"internal_name": internal,
			"type": "deposit",
			"deposit_token": token,
		})
	return items

# True when the building's tile has mined out a deposit the recipe needs.
# Pure water never depletes, so it never counts as exhausted.
func _recipe_deposit_exhausted(building: Dictionary, recipe: Dictionary) -> bool:
	var tile_id := str(building.get("tile_id", ""))
	if tile_id == "":
		return false
	for req in recipe.get("requirements", []):
		if str(req.get("type", "")) != "deposit":
			continue
		var token := str(req.get("value", ""))
		if token == "" or token == "water":
			continue
		if MatchState.deposit_remaining_for(tile_id, token) == 0:
			return true
	return false

# Whether a flow good_item is a deposit cell whose deposit is mined out.
func _flow_item_exhausted(good_item: Dictionary) -> bool:
	if str(good_item.get("type", "")) != "deposit":
		return false
	var token := str(good_item.get("deposit_token", ""))
	if token == "" or token == "water":
		return false
	var tile_id := str(_current_building.get("tile_id", ""))
	if tile_id == "":
		return false
	return MatchState.deposit_remaining_for(tile_id, token) == 0

func _recipe_potential(recipe: Dictionary) -> String:
	for req in recipe.get("requirements", []):
		if str(req.get("type", "")).to_lower() == "potential":
			var v := str(req.get("value", "")).to_lower()
			if v.contains("solar"):
				return "solar"
			if v.contains("wind"):
				return "wind"
	var internal := str(Catalog.get_building(str(recipe.get("building_id", ""))).get("internal_name", "")).to_lower()
	if internal.contains("solar_farm"):
		return "solar"
	if internal.contains("wind_farm"):
		return "wind"
	return ""

func _make_potential_flow_cell(value: String, cell_size: Vector2) -> Panel:
	var cell := Panel.new()
	cell.custom_minimum_size = cell_size
	var style := StyleBoxFlat.new()
	style.bg_color = FLOW_SQUARE_COLOR
	style.set_corner_radius_all(6)
	cell.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = "%s\npotential" % value.capitalize()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 11 if cell_size.x > 70 else 9)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(label)
	cell.tooltip_text = "Requires %s potential on this tile" % value.capitalize()
	return cell

func _flow_cell_good_id(good_item: Dictionary) -> String:
	var gid := str(good_item.get("good_id", ""))
	if gid != "":
		return gid
	var internal := str(good_item.get("internal_name", ""))
	if internal == "":
		return ""
	return str(Catalog.get_good_by_internal_name(internal).get("id", ""))

func _add_flow_quantity_badge(cell: Panel, good_item: Dictionary, cell_size: Vector2) -> void:
	if not _should_show_quantity_badge(good_item):
		return

	var qty := _badge_quantity(good_item)
	if qty <= 0:
		return

	var qty_text := str(qty)
	# The shared quantity pill (also used by the deposits mapmode overlay).
	var badge := UIHelpers.make_quantity_pill(qty_text, FLOW_BADGE_DIAMETER, FLOW_BADGE_TEXT_SIZE)
	var badge_size := badge.custom_minimum_size
	badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	var overlap: int = max(4, roundi(min(cell_size.x, cell_size.y) * 0.10))
	badge.offset_left = -badge_size.x + overlap
	badge.offset_top = -badge_size.y + overlap
	badge.offset_right = overlap
	badge.offset_bottom = overlap
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
		if child != close_button:
			child.queue_free()
	_status_dots.clear()

	# Group the five RAG indicators in a rounded highlight tray (DS BG_HIGHLIGHT).
	var rag_panel := PanelContainer.new()
	var rag_style := StyleBoxFlat.new()
	rag_style.bg_color = DS.PALETTE["BG_HIGHLIGHT"]
	rag_style.border_color = DS.PALETTE["BORDER_SOFT"]
	rag_style.set_border_width_all(1)
	rag_style.set_corner_radius_all(8)
	rag_style.set_content_margin_all(5)
	rag_panel.add_theme_stylebox_override("panel", rag_style)
	rag_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# Horizontal strip (was a vertical rail).
	var rag_box := HBoxContainer.new()
	rag_box.add_theme_constant_override("separation", 10)
	rag_panel.add_child(rag_box)

	for config in STATUS_ICON_CONFIG:
		var key: String = config.get("key", "")
		var icon_path: String = config.get("path", "")
		var tooltip: String = config.get("tooltip", "")
		var wrapper := HBoxContainer.new()
		wrapper.alignment = BoxContainer.ALIGNMENT_CENTER
		wrapper.theme = _tooltip_theme
		wrapper.tooltip_text = tooltip
		wrapper.mouse_filter = Control.MOUSE_FILTER_STOP
		wrapper.add_theme_constant_override("separation", 1)
		wrapper.custom_minimum_size = Vector2(STATUS_RAIL_WIDTH, 0)

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

		rag_box.add_child(wrapper)

	# 5th indicator: production cost per unit — RAG dot, cost + legend in tooltip
	_cost_wrapper = HBoxContainer.new()
	_cost_wrapper.alignment = BoxContainer.ALIGNMENT_CENTER
	_cost_wrapper.theme = _tooltip_theme
	_cost_wrapper.mouse_filter = Control.MOUSE_FILTER_STOP
	_cost_wrapper.add_theme_constant_override("separation", 1)
	_cost_wrapper.custom_minimum_size = Vector2(STATUS_RAIL_WIDTH, 0)

	var pound_icon := Label.new()
	pound_icon.text = "£"
	pound_icon.custom_minimum_size = STATUS_ICON_SIZE
	pound_icon.add_theme_font_size_override("font_size", 14)
	pound_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pound_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pound_icon.modulate = ICON_TINT
	pound_icon.mouse_filter = Control.MOUSE_FILTER_STOP
	pound_icon.theme = _tooltip_theme
	_cost_wrapper.add_child(pound_icon)

	_cost_label = Panel.new()
	_cost_label.custom_minimum_size = STATUS_DOT_SIZE
	_cost_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_cost_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_cost_label.theme = _tooltip_theme
	_cost_wrapper.add_child(_cost_label)

	rag_box.add_child(_cost_wrapper)
	_rag_panel = rag_panel

	# Place the strip in the main column, directly BELOW the recipe (inputs/outputs)
	# flow summary. Remove the vertical split: hide the old rail and let the fields
	# scroll fill the full width.
	panel_vbox.add_child(rag_panel)
	panel_vbox.move_child(rag_panel, flow_summary.get_index() + 1)
	status_icon_column.visible = false
	# The close (X) was reparented to the top of the rail; with the rail hidden it
	# vanished with it. Return it to the header row so the panel keeps its X.
	var header_row := panel_vbox.get_node_or_null("HeaderRow")
	if header_row != null and close_button.get_parent() != header_row:
		close_button.get_parent().remove_child(close_button)
		close_button.custom_minimum_size = Vector2(28, 28)
		close_button.size_flags_horizontal = Control.SIZE_SHRINK_END
		header_row.add_child(close_button)
	var scroll := fields_vbox.get_parent()
	if scroll is Control:
		(scroll as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _update_status_icons(building: Dictionary, recipe: Dictionary, is_infrastructure: bool) -> void:
	_set_status_dot("power", _power_status_color(building, recipe, is_infrastructure))
	_set_status_dot("input", _input_status_color(building, recipe, is_infrastructure))
	_set_status_dot("duration", _transport_duration_status_color(building, recipe, is_infrastructure))
	_set_status_dot("cost", _transport_cost_status_color(building, recipe, is_infrastructure))
	_update_cost_label(building)

const _COST_RAG_LEGEND := "Green if cheaper than buying from the market, amber if even with market and red if more expensive than purchasing from the market"

func _update_cost_label(building: Dictionary) -> void:
	if _cost_label == null:
		return
	var instance_id: String = building.get("instance_id", "")
	var uc: float = CostSolver.get_building_unit_cost(instance_id)
	# A mined-out deposit means the building produces nothing — no unit cost.
	if _recipe_deposit_exhausted(building, Catalog.get_recipe(str(building.get("recipe_id", "")))):
		uc = -1.0
	var color: Color
	var tooltip: String
	if uc < 0.0:
		color = STATUS_GREY
		tooltip = "Production cost per unit: --\n" + _COST_RAG_LEGEND
	else:
		var bd: Dictionary = CostSolver.last_result.get("per_building", {}).get(instance_id, {})
		var output_good_id: String = bd.get("output_good_id", "")
		var base_price: float = Catalog.get_base_price(output_good_id) if output_good_id != "" else 0.0
		var pct: float = (uc / base_price * 100.0) if base_price > 0.0 else 0.0
		if pct < 90.0:
			color = STATUS_GREEN
		elif pct <= 110.0:
			color = STATUS_YELLOW
		else:
			color = STATUS_RED
		var output_costs: Dictionary = bd.get("output_costs", {})
		if output_costs.size() > 1:
			# Multi-output: list the allocated cost basis for each product
			var lines: PackedStringArray = ["Production cost per unit (market-value allocation):"]
			for gid in output_costs:
				lines.append("  %s: £%.2f" % [Catalog.get_display_name(gid), output_costs[gid]])
			lines.append(_COST_RAG_LEGEND)
			tooltip = "\n".join(lines)
		else:
			tooltip = "Production cost per unit: £%.2f\n%s" % [uc, _COST_RAG_LEGEND]
	var style := StyleBoxFlat.new()
	style.bg_color = color
	var radius := roundi(STATUS_DOT_SIZE.x * 0.5)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	_cost_label.add_theme_stylebox_override("panel", style)
	_cost_label.tooltip_text = tooltip
	if _cost_wrapper != null:
		_cost_wrapper.tooltip_text = tooltip
		var pound := _cost_wrapper.get_child(0) as Label
		if pound != null:
			pound.tooltip_text = tooltip

func _on_costs_updated() -> void:
	if _current_building.is_empty():
		return
	_update_cost_label(_current_building)

func _set_status_dot(key: String, color: Color) -> void:
	if not _status_dots.has(key):
		return
	var dot: Panel = _status_dots[key]
	var style := StyleBoxFlat.new()
	style.bg_color = color
	var radius := roundi(STATUS_DOT_SIZE.x * 0.5)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
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
	# An extraction building whose deposit is mined out can no longer produce.
	if _recipe_deposit_exhausted(building, recipe):
		return STATUS_RED
	var instance_id: String = building.get("instance_id", "")
	if instance_id != "" and Production.last_turn_run.has(instance_id):
		return STATUS_GREEN
	if instance_id != "" and Production.missing_by_building.has(instance_id):
		return STATUS_RED
	var inputs: Array = recipe.get("inputs", [])
	if inputs.is_empty():
		return STATUS_GREEN
	var tile_id: String = building.get("tile_id", "")
	for input in inputs:
		if Stockpile.get_at_tile(tile_id, input.get("good_id", "")) < input.get("qty", 0):
			return STATUS_RED
	return STATUS_YELLOW

func _transport_duration_status_color(building: Dictionary, recipe: Dictionary, is_infrastructure: bool) -> Color:
	if is_infrastructure:
		return STATUS_GREY
	# No output to transport when the building isn't running (or its deposit ran out).
	if not Production.last_turn_run.has(str(building.get("instance_id", ""))) or _recipe_deposit_exhausted(building, recipe):
		return STATUS_GREY
	var route := _selected_output_route(building, recipe)
	if route.is_empty():
		return STATUS_GREEN
	return STATUS_YELLOW if int(route.turns) > 1 else STATUS_GREEN

func _transport_cost_status_color(building: Dictionary, recipe: Dictionary, is_infrastructure: bool) -> Color:
	if is_infrastructure:
		return STATUS_GREY
	if not Production.last_turn_run.has(str(building.get("instance_id", ""))) or _recipe_deposit_exhausted(building, recipe):
		return STATUS_GREY
	var route := _selected_output_route(building, recipe)
	if route.is_empty():
		return STATUS_GREEN
	return STATUS_YELLOW if float(route.cost) > 0.0 else STATUS_GREEN

func _selected_output_route(building: Dictionary, recipe: Dictionary) -> Dictionary:
	var instance_id: String = building.get("instance_id", "")
	var good_id := _primary_output_good_id(recipe)
	var destination_tile := MatchState.get_output_stockpile_destination(instance_id, good_id)
	if destination_tile == "":
		return {}
	return _route_summary_for_good(
		building.get("tile_id", ""),
		destination_tile,
		good_id,
		_primary_output_qty(recipe)
	)

func _building_display_name(building: Dictionary, building_data: Dictionary, recipe: Dictionary) -> String:
	# Codified naming: "<Type> - <Output> - <Letter>" (see building_naming.gd).
	return BuildingNaming.label_for_tile(
		str(building.get("tile_id", "")), str(building.get("instance_id", "")),
		str(building.get("building_id", "")), str(building.get("recipe_id", "")))

func _format_location(building: Dictionary) -> String:
	var tile_id: String = building.get("tile_id", "")
	if tile_id.begins_with("tile_"):
		return "Tile %s" % tile_id.trim_prefix("tile_")
	return tile_id

func _tile_title_suffix(building: Dictionary) -> String:
	var tile_id: String = building.get("tile_id", "")
	if tile_id == "":
		return ""
	return " (%s)" % tile_id

func _tile_title_tooltip(building: Dictionary) -> String:
	var tile_coord := _tile_column_row(building)
	if tile_coord == Vector2i(-1, -1):
		return ""
	return "column %d, row %d" % [tile_coord.x, tile_coord.y]

func _tile_column_row(building: Dictionary) -> Vector2i:
	var tile_id: String = building.get("tile_id", "")
	if not tile_id.begins_with("tile_"):
		return Vector2i(-1, -1)
	var parts := tile_id.split("_")
	if parts.size() != 3 or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return Vector2i(-1, -1)
	return Vector2i(int(parts[1]), int(parts[2]))

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

func _produced_since_construction(building: Dictionary, recipe: Dictionary) -> String:
	var instance_id: String = building.get("instance_id", "")
	var totals: Dictionary = Production.produced_by_building.get(instance_id, {}) as Dictionary
	if totals.is_empty():
		return "0"

	var parts: Array = []
	for good_key in totals.keys():
		parts.append("%d %s" % [int(totals[good_key]), _produced_good_display_name(str(good_key), recipe)])
	return ", ".join(parts)

func _produced_good_display_name(good_key: String, recipe: Dictionary) -> String:
	if good_key == "power":
		return "Power"
	var good: Dictionary = Catalog.get_good(good_key)
	if not good.is_empty():
		return good.get("display_name", good_key)
	for output in _flow_output_items(recipe):
		if output.get("internal_name", "") == good_key:
			return _good_display_from_internal(good_key)
	return good_key

func _full_output_streak(building: Dictionary) -> int:
	var instance_id: String = building.get("instance_id", "")
	return int(Production.full_output_streak_by_building.get(instance_id, 0))

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
	var instance_id: String = _current_building.get("instance_id", "")
	var good_id := _primary_output_good_id(_current_recipe)
	if MatchState.is_output_market(instance_id, good_id):
		return "Market"
	var destination_tile := MatchState.get_output_stockpile_destination(instance_id, good_id)
	if destination_tile != "":
		var route := _route_summary_for_good(
			_current_building.get("tile_id", ""),
			destination_tile,
			good_id,
			_primary_output_qty(_current_recipe)
		)
		return "%s · %d turn%s · £%s" % [
			Catalog.tile_label(destination_tile),
			route.turns,
			"" if int(route.turns) == 1 else "s",
			_format_money(route.cost),
		]
	match MatchState.sell_mode:
		MatchState.SellMode.STOCKPILE_ALL:
			return "Tile stockpile"
		MatchState.SellMode.BUILDING_BY_BUILDING:
			return "Building-by-building"
		_:
			return "Market"

func _output_route_summary() -> Dictionary:
	# Resolve where this building's output goes + the route cost/turns to get there.
	var source_tile := str(_current_building.get("tile_id", ""))
	var good_id := _primary_output_good_id(_current_recipe)
	var qty := _primary_output_qty(_current_recipe)
	var instance_id: String = _current_building.get("instance_id", "")
	var dest_tile := MatchState.get_output_stockpile_destination(instance_id, good_id)
	var target := ""
	var destination := ""
	if dest_tile != "":
		target = dest_tile
		destination = Catalog.tile_label(dest_tile)
	elif MatchState.sell_mode == MatchState.SellMode.STOCKPILE_ALL:
		target = source_tile
		destination = "Tile stockpile (same tile)"
	else:
		target = TransportService.nearest_port_tile(source_tile)
		destination = ("Market (via %s)" % Catalog.tile_label(target)) if target != "" else "Market"
	var route := _route_summary_for_good(source_tile, target, good_id, qty)
	return {"destination": destination, "cost": route.cost, "turns": route.turns, "target": target}

func _primary_output_good_id(recipe: Dictionary) -> String:
	for output in _flow_output_items(recipe):
		var output_good_id: String = output.get("good_id", "")
		if output_good_id != "":
			return output_good_id
		var internal_name: String = output.get("internal_name", "")
		if internal_name != "":
			var good: Dictionary = Catalog.get_good_by_internal_name(internal_name)
			return good.get("id", "")
	return ""

func _primary_output_qty(recipe: Dictionary) -> int:
	for output in _flow_output_items(recipe):
		return int(output.get("qty", 0))
	return 0

func _route_summary_for_good(source_tile: String, destination_tile: String, good_id: String, qty: int) -> Dictionary:
	var r := TransportService.route(source_tile, destination_tile, good_id)
	var turns: int = int(r.get("turns", 0))
	var cost := TransportService.transport_cost_for_route(good_id, qty, r)
	return {
		"distance": int(r.get("tile_distance", 0)),
		"turns": turns,
		"cost": cost,
	}

func _format_money(value: float) -> String:
	var text := "%.2f" % value
	while text.ends_with("0"):
		text = text.trim_suffix("0")
	if text.ends_with("."):
		text = text.trim_suffix(".")
	return text

func _money_text(value: float) -> String:
	return "Â£%s" % _format_money(value)

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
	var top_edge := TOP_BAR_CLEARANCE

	var tile_panel := get_parent().get_node_or_null("TileInfoPanel") as Control
	if tile_panel != null and tile_panel.visible:
		right_edge = tile_panel.global_position.x - PANEL_EDGE_MARGIN
		top_edge = maxf(tile_panel.global_position.y, TOP_BAR_CLEARANCE)

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
