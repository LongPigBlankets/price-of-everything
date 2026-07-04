extends PanelContainer
const BuildingLevels := preload("res://scripts/building_levels.gd")
# Shared status/cost helpers (one source of truth with the Building Ledger).
const BuildingStatus := preload("res://scripts/building_status.gd")

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
@onready var fields_host: Control = $MarginContainer/VBoxContainer/ContentRow/FieldsHost
@onready var fields_vbox: VBoxContainer = $MarginContainer/VBoxContainer/ContentRow/FieldsHost/ScrollContainer/FieldsVBox
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
const UPGRADE_NUMERAL_BLUE := Color("#A7C8D3")  # light steel-blue (DS Primary-button face)
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
const MOD_WHITE := Color(0.93, 0.94, 0.96)  # neutral band for the net-modifier %
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
var _mod_label: Label = null
var _mod_wrapper: HBoxContainer = null
var _tooltip_theme: Theme = null
var _upgrade_button: Button = null
var _upgrade_numeral: Label = null         # target-level digit embossed inside the arrow
var _max_lvl_badge: PanelContainer = null  # replaces the button once the building is maxed
var _upgrade_panel: PanelContainer = null  # legacy inline panel — superseded by the upgrade dialog (kept null)
var _upgrade_dialog: Control = null        # lazily-built expanded upgrade dialog (see upgrade_dialog.gd)
var _upgrade_dialog_layer: CanvasLayer = null  # the top CanvasLayer the dialog lives on (built once, reused)
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
var _run_warning_button: Button = null
var _run_warning_details: PanelContainer = null
var _run_warning_details_label: Label = null
var _run_warning_tween: Tween = null
var _run_warning_expanded := false
var _current_run_warning_message := ""
var _action_button_row: HBoxContainer = null
var _npc_panel: PanelContainer = null
var _npc_label: Label = null
var _construction_overlay: Control = null  # blur + "Under Construction" pill over the diagram
var _npc_blur_rect: ColorRect = null  # frost over an NPC building's info fields (top_level, rect-synced)
var _showing_construction_instance: String = ""  # instance_id while rendering construction mode
var _storage_diagram: HBoxContainer = null  # battery "In use for storage" diagram (replaces FlowRow)
var _sd_produced: Label = null
var _sd_consumed: Label = null
var _sd_maxcap: Label = null
var _sd_icon_row: HBoxContainer = null  # loaded battery-type icon(s) inside the storage box
const DASHED_BOX := preload("res://scripts/dashed_box.gd")
var _fill_expanded: bool = false       # battery "Fill Storage" section open?
var _fill_type: String = ""            # selected battery good internal_name

func _ready() -> void:
	_is_secondary_panel = bool(get_meta("is_secondary_building_panel", false))
	if DS and DS.theme:
		theme = DS.theme  # inherit the design-system theme (fonts, buttons, palette)
	if not _is_secondary_panel:
		_prepare_building_panel_template()
	close_button.pressed.connect(_hide_panel)
	if not change_recipe_button.pressed.is_connected(_on_change_recipe_pressed):
		change_recipe_button.pressed.connect(_on_change_recipe_pressed)
	if not MatchState.building_retrofitted.is_connected(_on_retrofit_changed):
		MatchState.building_retrofitted.connect(_on_retrofit_changed)
		MatchState.building_retrofit_started.connect(_on_retrofit_changed)
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
	# A research unlock (or any modifier change) can flip the net-modifier indicator.
	if not Modifiers.modifiers_changed.is_connected(_on_modifiers_changed):
		Modifiers.modifiers_changed.connect(_on_modifiers_changed)
	if not MatchState.workforce_policies_changed.is_connected(_on_workforce_policies_changed):
		MatchState.workforce_policies_changed.connect(_on_workforce_policies_changed)
	# A deposit running out must refresh the shown building's RAG dots, production
	# status and recipe diagram (it stops being able to produce).
	if not MatchState.deposits_changed.is_connected(_on_deposit_changed):
		MatchState.deposits_changed.connect(_on_deposit_changed)
	# Battery cells loading/unloading/installing on the shown tile must refresh the storage
	# diagram (so the loaded-type icon appears the turn the cells arrive in the building).
	if not MatchState.battery_cells_changed.is_connected(_on_battery_cells_changed):
		MatchState.battery_cells_changed.connect(_on_battery_cells_changed)
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
	# Keep this panel live as an upgrade is queued, advances, and completes.
	if not MatchState.building_upgraded.is_connected(_on_building_upgrade_changed):
		MatchState.building_upgraded.connect(_on_building_upgrade_changed)
	if not MatchState.building_upgrade_started.is_connected(_on_building_upgrade_changed):
		MatchState.building_upgrade_started.connect(_on_building_upgrade_changed)
	if not MatchState.building_upgrade_cancelled.is_connected(_on_building_upgrade_changed):
		MatchState.building_upgrade_cancelled.connect(_on_building_upgrade_changed)
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
		_stop_run_warning_blink()
		PanelStack.remove(self)
		if not _is_secondary_panel:
			building_connections_changed.emit("", [], [], false)

func _hide_panel() -> void:
	_stop_run_warning_blink()
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
	_clear_npc_field_blur()
	_showing_construction_instance = ""

	_current_building = building
	_refresh_upgrade_button()  # next-level digit / MAX LVL badge for the selected building
	var building_data: Dictionary = Catalog.get_building(building.get("building_id", ""))
	_update_building_banner(building_data)
	var recipe: Dictionary = Catalog.get_recipe(building.get("recipe_id", ""))
	_current_recipe = recipe
	_set_run_warning_message("")
	var category: String = building_data.get("category", "")
	var is_infrastructure: bool = category == "infrastructure"

	var owner_id := _resolve_owner_id(building)
	if owner_id != MatchState.LOCAL_PLAYER and owner_id != "tile_data":
		_apply_npc_mode(true)
		if _npc_label != null:
			var is_ruins := str(building.get("building_id", "")) == "b_031"
			_npc_label.text = ("Disused — operated by %s" % owner_id) if is_ruins else ("Building operated by %s" % owner_id)
		title_label.text = _building_display_name(building, building_data, recipe) + _tile_title_suffix(building)
		title_label.tooltip_text = _tile_title_tooltip(building)
		location_label.visible = false
		# Banner + recipe diagram stay readable; the detail fields render but sit
		# behind a frost blur — a future specialist advisor can reveal them.
		_update_flow_summary(recipe)
		_add_field("Value", _money_text(building_data.get("base_price", 0.0)))
		_add_field("Maintenance cost", _money_text(_maintenance_cost(building_data)))
		_add_separator()
		_add_labour_table(building_data)
		_add_separator()
		_add_operation_table(building, recipe)
		_apply_npc_field_blur()
		return
	_apply_npc_mode(false)

	# Construction sites (awaiting materials / under construction) show none of the usual
	# building info — just a frosted diagram and the materials/ETA breakdown.
	var project: Dictionary = Construction.construction_projects.get(str(building.get("instance_id", "")), {})
	if not project.is_empty():
		_render_construction_mode(building, building_data, recipe, project)
		return

	# Battery storage: no recipe processing — show the bespoke "In use for storage" diagram
	# (not a recipe flow), no power/route/operation rows. Just value, maintenance, labour.
	if category == "battery":
		_apply_npc_mode(false)
		change_recipe_button.visible = false
		if _route_row != null:
			_route_row.visible = false  # no Inputs/Outputs routing for storage
		title_label.text = _building_display_name(building, building_data, recipe) + _tile_title_suffix(building)
		title_label.tooltip_text = _tile_title_tooltip(building)
		location_label.visible = false
		_show_storage_diagram(building)
		_add_fill_storage_section(building)
		var blvl := int(building.get("level", 1))
		_add_field("Value", _money_text(building_data.get("base_price", 0.0)))
		_add_field("Maintenance cost", _money_text(_maintenance_cost(building_data) * BuildingLevels.mult("maint", blvl)))
		_add_separator()
		_add_labour_table(building_data)
		_update_run_warning(building, recipe, false)
		return

	_update_change_recipe_button(building, is_infrastructure)
	title_label.text = _building_display_name(building, building_data, recipe) + _tile_title_suffix(building)
	title_label.tooltip_text = _tile_title_tooltip(building)
	location_label.visible = false
	_update_flow_summary(recipe)
	_refresh_route_controls(building, recipe)
	_update_status_icons(building, recipe, is_infrastructure)
	_add_field("Value", _money_text(building_data.get("base_price", 0.0)))

	# Levelling raises the base, so these track the building's level (matching the engine).
	var lvl := int(building.get("level", 1))
	if not is_infrastructure and recipe.get("output_name", "") == "power":
		var power_out := int(round(float(recipe.get("output_qty", 0)) * BuildingLevels.mult("output", lvl)))
		_add_field("Power production", str(power_out))


	_add_field("Maintenance cost", _money_text(_maintenance_cost(building_data) * BuildingLevels.mult("maint", lvl)))
	_add_power_sources_section(building)

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

# Authoritative ownership: re-read the live owner from MatchState by instance_id rather than
# trusting a possibly stale/cross-wired `owner` on the passed-in dict, so this panel can never
# disagree with the tile view (MatchState.is_player_owned). Missing owner defaults to the local
# player (matching is_player_owned), so a not-yet-promoted construction stub — which isn't in
# MatchState.buildings and carries no owner — resolves to the player and falls through to
# construction mode rather than NPC-frosting.
func _resolve_owner_id(building: Dictionary) -> String:
	var iid := str(building.get("instance_id", ""))
	var live: Dictionary = MatchState.get_building(iid) if iid != "" else {}
	return str(live.get("owner", building.get("owner", MatchState.LOCAL_PLAYER)))

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
	buy.tooltip_text = "NPC buildings rotate onto the purchase market in phases (coming soon)"
	buy.mouse_filter = Control.MOUSE_FILTER_STOP
	buy.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	vbox.add_child(buy)

	panel_vbox.add_child(_npc_panel)
	panel_vbox.move_child(_npc_panel, flow_summary.get_index() + 1)

func _apply_npc_mode(on: bool) -> void:
	# NPC-owned buildings keep the banner + recipe diagram readable and show the
	# grey "operated by…" card + a disabled Buy; the info fields below are frosted
	# (_apply_npc_field_blur). No status lights, routes, or upgrade/recipe controls.
	flow_summary.visible = true
	change_recipe_button.visible = change_recipe_button.visible and not on
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

# --- NPC field frosting -------------------------------------------------------
# The info fields under an NPC building render normally but sit behind a strong
# screen-space blur. FieldsHost is a plain full-rect Control wrapping the
# ScrollContainer, so the overlay anchors over the fields without disturbing
# the HBox layout (same pattern as the construction overlay on FlowSummary).

func _apply_npc_field_blur() -> void:
	_clear_npc_field_blur()
	var blur := ColorRect.new()
	blur.name = "NPCFieldBlur"
	blur.set_anchors_preset(Control.PRESET_FULL_RECT)
	blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = CONSTRUCTION_BLUR_SHADER
	mat.set_shader_parameter("blur_px", 9.0)
	blur.material = mat
	fields_host.add_child(blur)
	_npc_blur_rect = blur

func _clear_npc_field_blur() -> void:
	if _npc_blur_rect != null and is_instance_valid(_npc_blur_rect):
		_npc_blur_rect.queue_free()
	_npc_blur_rect = null
	if fields_host == null:
		return
	# Remove EVERY frost overlay, not just one matched by exact name: a same-frame re-render can
	# rename a second blur to "@NPCFieldBlur@2", which a name lookup misses — leaving it frosting
	# the next building. The frost is the only ColorRect parented to fields_host, so sweep them.
	for child in fields_host.get_children():
		if child is ColorRect:
			child.queue_free()

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

func _on_battery_cells_changed(tile_id: String) -> void:
	# Re-render a shown battery building when its tile's cells change (load/unload/install).
	if not visible or _current_building.is_empty() or _showing_construction_instance != "":
		return
	if str(_current_building.get("tile_id", "")) == tile_id \
			and str(Catalog.get_building(str(_current_building.get("building_id", ""))).get("category", "")) == "battery":
		_rebuild_fields(_current_building)

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

# "Power Source(s): x Green from A, B; y Grey from C; z Grey from Grid" — where this
# building's power came from (on-demand attribution to the nearest source buildings).
func _add_power_sources_section(building: Dictionary) -> void:
	var src: Dictionary = Production.get_power_sources(str(building.get("instance_id", "")))
	if src.is_empty():
		return
	var clauses: Array = []
	var green_clause := _power_source_clause(src.get("green_from", {}), "Green")
	if green_clause != "":
		clauses.append(green_clause)
	var grey_clause := _power_source_clause(src.get("grey_from", {}), "Grey")
	if grey_clause != "":
		clauses.append(grey_clause)
	var grid: int = int(round(float(src.get("grid", 0.0))))
	if grid > 0:
		clauses.append("%d Grey from Grid" % grid)
	if clauses.is_empty():
		return
	_add_field("Power Source(s)", "; ".join(clauses))

func _power_source_clause(from: Dictionary, quality_label: String) -> String:
	var qty := 0
	var names: Array = []
	for iid in from.keys():
		qty += int(round(float(from[iid])))
		names.append(_source_building_name(str(iid)))
	if qty <= 0:
		return ""
	return "%d %s from %s" % [qty, quality_label, ", ".join(names)]

func _source_building_name(instance_id: String) -> String:
	var b: Dictionary = MatchState.get_building(instance_id)
	if b.is_empty():
		return instance_id
	return BuildingNaming.label_for_tile(
		str(b.get("tile_id", "")), instance_id,
		str(b.get("building_id", "")), str(b.get("recipe_id", "")))

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
	# Labour slider + workforce policies apply additively to the 100% base (no compounding).
	var cost := float(count) * rate * MatchState.labour_policy_factor()
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

# Coalesced (notification_bell pattern): stockpile_changed fires per add/consume
# during PROCESS — with the panel open, a busy turn used to trigger hundreds of
# complete _rebuild_fields passes. One deferred rebuild per frame instead.
var _logistics_refresh_queued := false

func _on_logistics_changed() -> void:
	if not visible or _current_building.is_empty() or _logistics_refresh_queued:
		return
	_logistics_refresh_queued = true
	call_deferred("_apply_logistics_refresh")

func _apply_logistics_refresh() -> void:
	_logistics_refresh_queued = false
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

	var active_order: Dictionary = SpecialOrderState.get_active_order_for_good(good_id)
	var special_order_id := str(active_order.get("id", ""))
	var routed_order_id := MatchState.get_output_special_order_id(instance_id, good_id)
	var is_special_order := special_order_id != "" and routed_order_id == special_order_id
	var is_market := MatchState.is_output_market(instance_id, good_id) and not is_special_order
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

	if not active_order.is_empty():
		var special_btn := _make_route_choice_button("Special Order", is_special_order)
		special_btn.tooltip_text = "%d required, %d committed, %d delivered" % [
			int(active_order.get("qty_required", 0)),
			int(active_order.get("qty_committed", 0)),
			int(active_order.get("qty_delivered", 0)),
		]
		special_btn.pressed.connect(func() -> void:
			MatchState.route_output_to_special_order(instance_id, good_id, special_order_id)
			_refresh_route_controls(_current_building, _current_recipe)
			_output_route_detail.visible = true
		)
		btns.add_child(special_btn)

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
	# The target-level digit, embossed inside the arrow: light-blue (button colour) with a
	# dark drop to the lower-right, as if lit from the upper-left.
	_upgrade_numeral = Label.new()
	_upgrade_numeral.theme_type_variation = "Numeric"
	_upgrade_numeral.add_theme_font_size_override("font_size", 19)
	_upgrade_numeral.add_theme_color_override("font_color", UPGRADE_NUMERAL_BLUE)
	_upgrade_numeral.add_theme_color_override("font_shadow_color", Color(0.0, 0.04, 0.09, 0.9))
	_upgrade_numeral.add_theme_constant_override("shadow_offset_x", 2)
	_upgrade_numeral.add_theme_constant_override("shadow_offset_y", 2)
	_upgrade_numeral.add_theme_color_override("font_outline_color", Color(0.0, 0.04, 0.09, 0.85))
	_upgrade_numeral.add_theme_constant_override("outline_size", 3)
	_upgrade_numeral.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_upgrade_numeral.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_upgrade_numeral.set_anchors_preset(Control.PRESET_FULL_RECT)
	_upgrade_numeral.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_upgrade_button.add_child(_upgrade_numeral)
	button_row.add_child(_upgrade_button)

	# Terminal state: a non-clickable rounded square reading MAX / LVL (off-white on transparent),
	# shown in place of the button once the building reaches the maximum level.
	_max_lvl_badge = PanelContainer.new()
	_max_lvl_badge.custom_minimum_size = UPGRADE_BUTTON_SIZE
	_max_lvl_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_max_lvl_badge.visible = false
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = Color(0, 0, 0, 0)  # transparent
	badge_style.border_color = DS.PALETTE.BORDER_SOFT
	badge_style.set_border_width_all(2)
	badge_style.set_corner_radius_all(10)
	_max_lvl_badge.add_theme_stylebox_override("panel", badge_style)
	var max_lbl := Label.new()
	max_lbl.text = "MAX\nLVL"
	max_lbl.add_theme_font_size_override("font_size", 12)
	max_lbl.add_theme_color_override("font_color", DS.PALETTE.ACCENT)
	max_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	max_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	max_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_max_lvl_badge.add_child(max_lbl)
	button_row.add_child(_max_lvl_badge)

	panel_vbox.add_child(button_row)
	panel_vbox.move_child(button_row, row_index)

	panel_vbox.remove_child(change_recipe_button)
	change_recipe_button.custom_minimum_size = Vector2(0, 30)
	change_recipe_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button_row.add_child(change_recipe_button)
	# The upgrade flow now opens the expanded upgrade_dialog (built lazily); no inline panel.

# Open the expanded upgrade dialog for the selected building. The dialog shows the material
# kit (with market/stockpile sourcing), the cur→new benefit/cost deltas, and the 3-turn build
# time, and commits via MatchState.start_upgrade(). Built lazily on a top CanvasLayer so it
# floats above the HUD regardless of where this panel sits.
func _on_upgrade_button_pressed() -> void:
	var instance_id: String = str(_current_building.get("instance_id", ""))
	if instance_id == "":
		return
	_ensure_upgrade_dialog()
	_upgrade_dialog.open(instance_id)

# Sync the upgrade control to the selected building: show the next-level digit in the arrow,
# or swap to the non-clickable MAX LVL badge once the building can't be upgraded further.
func _refresh_upgrade_button() -> void:
	if _upgrade_button == null:
		return
	var level := int(_current_building.get("level", 1))
	var maxed := level >= BuildingLevels.MAX_LEVEL
	_upgrade_button.visible = not maxed
	if _max_lvl_badge != null:
		_max_lvl_badge.visible = maxed
	if not maxed and _upgrade_numeral != null:
		_upgrade_numeral.text = str(level + 1)
		_upgrade_button.tooltip_text = "Upgrade to Level %d" % (level + 1)

func _ensure_upgrade_dialog() -> void:
	if _upgrade_dialog != null and is_instance_valid(_upgrade_dialog):
		return
	# One reusable dialog on a high CanvasLayer (built once, hidden on close — never re-created).
	if _upgrade_dialog_layer == null or not is_instance_valid(_upgrade_dialog_layer):
		_upgrade_dialog_layer = CanvasLayer.new()
		_upgrade_dialog_layer.layer = 128
		get_tree().root.add_child(_upgrade_dialog_layer)
	_upgrade_dialog = (load("res://scripts/upgrade_dialog.gd") as Script).new()
	_upgrade_dialog_layer.add_child(_upgrade_dialog)
	_upgrade_dialog.committed.connect(_on_upgrade_committed)

func _on_upgrade_committed(instance_id: String) -> void:
	# The level changes a few turns later (building_upgraded); refresh now so the in-progress
	# state shows immediately.
	if str(_current_building.get("instance_id", "")) == instance_id:
		_current_building = MatchState.get_building(instance_id)
		_rebuild_fields(_current_building)

# An upgrade for some building was queued, advanced, or completed — refresh if it's the one on screen.
func _on_building_upgrade_changed(instance_id: String, _level_or_target: int = 0) -> void:
	if str(_current_building.get("instance_id", "")) == instance_id and MatchState.buildings.has(instance_id):
		_current_building = MatchState.get_building(instance_id)
		_rebuild_fields(_current_building)

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
	var instance_id: String = str(building.get("instance_id", ""))
	# Retooling in progress: show the countdown, disabled.
	if MatchState.is_retooling(instance_id):
		var turns: int = MatchState.retrofit_turns_remaining(instance_id)
		change_recipe_button.text = "Retooling — %d turn%s left" % [turns, "" if turns == 1 else "s"]
		change_recipe_button.disabled = true
		return
	if is_infrastructure:
		change_recipe_button.text = "Change Recipe (0 recipes)"
		change_recipe_button.disabled = true
		return
	var building_id: String = building.get("building_id", "")
	var alternate_count: int = maxi(0, Catalog.get_recipes_for_building(building_id).size() - 1)
	change_recipe_button.text = "Change Recipe (%d)" % alternate_count
	change_recipe_button.disabled = alternate_count == 0 or not MatchState.is_player_owned(building)

# Open a picker of the building's other recipes; selecting one confirms the retrofit.
func _on_change_recipe_pressed() -> void:
	if _current_building.is_empty():
		return
	var instance_id: String = str(_current_building.get("instance_id", ""))
	if MatchState.is_retooling(instance_id):
		return
	var current: String = str(_current_building.get("recipe_id", ""))
	var alts: Array = []
	for r in Catalog.get_recipes_for_building(str(_current_building.get("building_id", ""))):
		if str(r.get("recipe_id", "")) != current:
			alts.append(r)
	if alts.is_empty():
		return
	var menu := PopupMenu.new()
	if DS and DS.theme:
		menu.theme = DS.theme
	add_child(menu)
	for i in alts.size():
		menu.add_item(_recipe_menu_label(alts[i]), i)
	menu.id_pressed.connect(func(idx: int) -> void: _confirm_retrofit(instance_id, alts[idx]))
	menu.popup_hide.connect(func() -> void: menu.queue_free(), CONNECT_DEFERRED)
	menu.position = Vector2i(change_recipe_button.get_screen_position())
	menu.popup()

func _recipe_menu_label(recipe: Dictionary) -> String:
	var out_internal: String = str(recipe.get("output_name", ""))
	var disp: String = Catalog.get_display_name(str(Catalog.get_good_by_internal_name(out_internal).get("id", "")))
	if disp == "":
		disp = str(recipe.get("recipe_id", "recipe"))
	return "Make %s" % disp

func _confirm_retrofit(instance_id: String, recipe: Dictionary) -> void:
	var tier: Dictionary = MatchState.retrofit_cost_tier()
	var dlg := ConfirmationDialog.new()
	if DS and DS.theme:
		dlg.theme = DS.theme
	dlg.title = "Retool building"
	dlg.dialog_text = "%s?\nOne-off fee £%d · %d turn%s retooling at %d%% labour.\nThe building produces nothing until it completes." % [
		_recipe_menu_label(recipe), int(tier.get("fee", 0.0)), int(tier.get("turns", 2)),
		"" if int(tier.get("turns", 2)) == 1 else "s", int(round(float(tier.get("labour", 0.5)) * 100.0))]
	dlg.ok_button_text = "Retool"
	add_child(dlg)
	dlg.confirmed.connect(func() -> void:
		var res: Dictionary = MatchState.start_retrofit(instance_id, str(recipe.get("recipe_id", "")))
		if not bool(res.get("ok", false)):
			MatchState.request_toast(str(res.get("reason", "Could not retool.")), "warning")
		dlg.queue_free())
	dlg.canceled.connect(func() -> void: dlg.queue_free())
	dlg.popup_centered()

func _on_retrofit_changed(instance_id: String, _recipe_id: String) -> void:
	if visible and not _current_building.is_empty() and str(_current_building.get("instance_id", "")) == instance_id:
		_rebuild_fields(_current_building)

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

# Battery storage diagram (in place of the recipe flow): a navy dashed "In use for storage" box,
# a vertical line, then three rows — produced steadied, consumed steadied, and max capacity.
func _show_storage_diagram(building: Dictionary) -> void:
	input_preview.visible = false
	flow_arrow.visible = false
	output_preview.visible = false
	if _storage_diagram == null or not is_instance_valid(_storage_diagram):
		_storage_diagram = _build_storage_diagram()
		flow_row.add_child(_storage_diagram)
	_storage_diagram.visible = true
	flow_summary.custom_minimum_size = Vector2(0, 168)  # room for the full-size battery icon
	var tile_id := str(building.get("tile_id", ""))
	var im: Dictionary = Production.get_tile_intermittency(tile_id)
	_sd_produced.text = "%d ⚡ steadied (produced)" % int(im.get("green_produced", 0))
	_sd_consumed.text = "%d ⚡ steadied (consumed)" % int(round(float(im.get("green_consumed", 0.0))))
	_sd_maxcap.text = "Max capacity: %d ⚡" % MatchState.tile_battery_slots(tile_id)
	# Show the icon of each battery type actually IN the building (not in-flight fills — those
	# aren't in tile_battery_cells until they install, so the icon appears the turn they arrive).
	for c in _sd_icon_row.get_children():
		c.queue_free()
	var cells: Dictionary = MatchState.get_tile_battery_cells(tile_id)
	for gid in cells:
		var holder := Control.new()
		holder.custom_minimum_size = FLOW_SINGLE_CELL_SIZE  # regular recipe-cell size (~110px)
		var icon := TextureRect.new()
		icon.texture = GoodIcons.texture_for(str(gid), str(Catalog.get_good(str(gid)).get("internal_name", "")), true)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		holder.add_child(icon)
		holder.add_child(_make_cell_qty_pill(int(cells[gid])))  # qty of cells in use
		_sd_icon_row.add_child(holder)

func _build_storage_diagram() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Left: dashed navy box — the loaded battery-type icon(s) up top, "In use for storage" lower.
	var box := DASHED_BOX.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box_vb := VBoxContainer.new()
	box_vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	box_vb.add_theme_constant_override("separation", 4)
	box_vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Icon(s) of the battery type(s) actually loaded (populated in _show_storage_diagram).
	_sd_icon_row = HBoxContainer.new()
	_sd_icon_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_sd_icon_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sd_icon_row.add_theme_constant_override("separation", 6)
	box_vb.add_child(_sd_icon_row)
	var gap := Control.new()  # pushes the label toward the bottom of the box
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box_vb.add_child(gap)
	var box_lbl := Label.new()
	box_lbl.text = "In use for storage"
	box_lbl.add_theme_color_override("font_color", DIAGRAM_NAVY)
	box_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box_vb.add_child(box_lbl)
	var bot := Control.new()
	bot.custom_minimum_size = Vector2(0, 10)
	box_vb.add_child(bot)
	box.add_child(box_vb)
	row.add_child(box)
	# Middle: a thin navy vertical line, inset so it doesn't touch the top/bottom of the card.
	var mid := VBoxContainer.new()
	var mtop := Control.new()
	mtop.custom_minimum_size = Vector2(2, 14)
	var line := ColorRect.new()
	line.color = DIAGRAM_NAVY
	line.custom_minimum_size = Vector2(2, 0)
	line.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var mbot := Control.new()
	mbot.custom_minimum_size = Vector2(2, 14)
	mid.add_child(mtop)
	mid.add_child(line)
	mid.add_child(mbot)
	row.add_child(mid)
	# Right: three rows — produced steadied, consumed steadied, and max capacity at the bottom.
	var right := HBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(12, 0)
	right.add_child(pad)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sd_produced = _storage_diagram_label()
	_sd_consumed = _storage_diagram_label()
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sd_maxcap = _storage_diagram_label()
	rows.add_child(_sd_produced)
	rows.add_child(_sd_consumed)
	rows.add_child(spacer)
	rows.add_child(_sd_maxcap)
	right.add_child(rows)
	row.add_child(right)
	return row

# A small qty pill anchored to the bottom-right of a cell (cells in use).
func _make_cell_qty_pill(qty: int) -> PanelContainer:
	var pill := PanelContainer.new()
	pill.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	pill.offset_left = -4
	pill.offset_top = -4
	pill.offset_right = -4
	pill.offset_bottom = -4
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.04, 0.09, 0.92)
	style.set_corner_radius_all(10)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	pill.add_theme_stylebox_override("panel", style)
	var lbl := Label.new()
	lbl.text = str(qty)
	lbl.theme_type_variation = &"Numeric"
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_font_size_override("font_size", 13)
	pill.add_child(lbl)
	return pill

func _storage_diagram_label() -> Label:
	var l := Label.new()
	l.theme_type_variation = &"Body"
	l.add_theme_color_override("font_color", DIAGRAM_NAVY)
	return l

# --- Battery "Fill Storage" flow ----------------------------------------------------------
# Replaces the Inputs/Outputs route controls. A wide button opens: choose a battery type (3
# cards; locked types greyed "NOT AVAILABLE", quantity pill hidden), then a source — Buy from
# Market (cost confirm + order), This tile's stockpile (instant load), or Other tile (routing,
# next update).
func _add_fill_storage_section(building: Dictionary) -> void:
	var tile_id := str(building.get("tile_id", ""))
	_add_separator()
	var fill_btn := Button.new()
	fill_btn.text = ("▴  " if _fill_expanded else "▾  ") + "Fill Storage"
	fill_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill_btn.custom_minimum_size = Vector2(0, 40)
	fill_btn.pressed.connect(func() -> void:
		_fill_expanded = not _fill_expanded
		_rebuild_fields(_current_building))
	fields_vbox.add_child(fill_btn)
	if not _fill_expanded:
		return
	# A fill is in flight — show the countdown instead of the source picker.
	var remaining := MatchState.battery_fill_turns_remaining(tile_id)
	if remaining > 0:
		_add_text("⏳ Battery operational in %d turn%s." % [remaining, "" if remaining == 1 else "s"])
		return
	var type_row := HBoxContainer.new()
	type_row.add_theme_constant_override("separation", 8)
	for internal in ["lithium_battery", "sodium_battery", "iron_battery"]:
		type_row.add_child(_make_battery_type_card(tile_id, internal))
	fields_vbox.add_child(type_row)
	if _fill_type == "" or not MatchState.is_unlocked(str(EconomyConfig.BATTERY_TYPE_UNLOCK.get(_fill_type, ""))):
		return
	var gid := str(Catalog.get_good_by_internal_name(_fill_type).get("id", ""))
	var need := MatchState.battery_cells_to_fill(tile_id, gid)
	var gname := str(Catalog.get_good(gid).get("display_name", _fill_type))
	if need <= 0:
		_add_text("Storage is full for %s." % gname)
		return
	_add_text("Needs %d %s cells to fill." % [need, gname])
	var stock := Stockpile.get_at_tile(tile_id, gid)
	var src_row := HBoxContainer.new()
	src_row.add_theme_constant_override("separation", 8)
	var mkt := _make_source_button("Buy from Market", true)
	mkt.pressed.connect(func() -> void: _confirm_battery_market_buy(tile_id, gid, need, gname))
	src_row.add_child(mkt)
	var this_btn := _make_source_button("This tile's stockpile", stock >= need)
	if stock >= need:
		this_btn.pressed.connect(func() -> void:
			MatchState.load_battery_cells(tile_id, gid, need)
			_rebuild_fields(_current_building))
	src_row.add_child(this_btn)
	var other := _make_source_button("Other tile", true)
	other.pressed.connect(func() -> void:
		MatchState.request_toast("Routing cells from another tile is coming in the next update.", "caution"))
	src_row.add_child(other)
	fields_vbox.add_child(src_row)

func _make_source_button(text: String, enabled: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 34)
	b.disabled = not enabled
	return b

func _make_battery_type_card(tile_id: String, internal: String) -> PanelContainer:
	var gid := str(Catalog.get_good_by_internal_name(internal).get("id", ""))
	var unlocked := MatchState.is_unlocked(str(EconomyConfig.BATTERY_TYPE_UNLOCK.get(internal, "")))
	var selected := _fill_type == internal and unlocked
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 88)
	var style := StyleBoxFlat.new()
	style.bg_color = DIAGRAM_PAPER  # off-white
	style.set_corner_radius_all(6)
	style.set_content_margin_all(6)
	style.set_border_width_all(2)
	style.border_color = DS.PALETTE.ACCENT if selected else Color(0, 0, 0, 0)
	card.add_theme_stylebox_override("panel", style)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 2)
	var icon := TextureRect.new()
	icon.texture = GoodIcons.texture_for(gid, internal, true)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(0, 44)
	if not unlocked:
		icon.modulate = Color(0.5, 0.5, 0.5, 0.5)
	vb.add_child(icon)
	if unlocked:
		var pill := Label.new()
		pill.text = "%d" % Stockpile.get_at_tile(tile_id, gid)
		pill.theme_type_variation = &"Numeric"
		pill.add_theme_color_override("font_color", DIAGRAM_NAVY)
		pill.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(pill)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				_fill_type = internal
				_rebuild_fields(_current_building))
	else:
		var na := Label.new()
		na.text = "NOT AVAILABLE"
		na.add_theme_color_override("font_color", STATUS_RED)
		na.add_theme_font_size_override("font_size", 10)
		na.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(na)
	card.add_child(vb)
	return card

func _confirm_battery_market_buy(tile_id: String, gid: String, need: int, gname: String) -> void:
	var cost := float(need) * MarketState.get_price(gid)
	var dlg := ConfirmationDialog.new()
	dlg.title = "Buy battery cells"
	dlg.dialog_text = "Buy %d %s from the market and ship them to this tile for about £%.0f?" % [need, gname, cost]
	dlg.confirmed.connect(func() -> void:
		var res := MatchState.order_battery_fill_market(tile_id, gid, need)
		if bool(res.get("ok", false)):
			var t := int(res.get("turns", 1))
			MatchState.request_toast("Ordered %d %s cells — operational in %d turn%s." % [need, gname, t, "" if t == 1 else "s"], "info")
			_rebuild_fields(_current_building)
		else:
			MatchState.request_toast("Couldn't order — not enough money or no route.", "caution")
		dlg.queue_free())
	dlg.canceled.connect(func() -> void: dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered()

func _update_flow_summary(recipe: Dictionary) -> void:
	# Restore the normal recipe flow content if the previous render was a battery storage diagram.
	if _storage_diagram != null and is_instance_valid(_storage_diagram):
		_storage_diagram.visible = false
	input_preview.visible = true
	flow_arrow.visible = true
	output_preview.visible = true
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
		_add_flow_quantity_badge(cell, good_item, cell_size, is_input)

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
	return BuildingStatus.recipe_deposit_exhausted(building, recipe)

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

func _add_flow_quantity_badge(cell: Panel, good_item: Dictionary, cell_size: Vector2, is_input: bool = false) -> void:
	if not _should_show_quantity_badge(good_item):
		return

	# Levelling raises the BASE recipe quantity (it is NOT a modifier): a Level-2 building
	# consumes ×input_mult inputs and produces ×output_mult outputs. The card shows that
	# levelled base; recipe_output modifiers then apply on top of it.
	var lvl := int(_current_building.get("level", 1))
	var qty := int(round(_badge_quantity(good_item) * BuildingLevels.mult("input" if is_input else "output", lvl)))
	if qty <= 0:
		return

	# Only OUTPUTS whose modifier-adjusted quantity rounds to a DIFFERENT integer get
	# the widened dual pill; inputs and unchanged outputs keep the normal narrow pill.
	var modified := qty
	if not is_input:
		modified = _modified_output_qty(good_item, qty)

	var height := FLOW_BADGE_DIAMETER
	var overlap: int = max(4, roundi(min(cell_size.x, cell_size.y) * 0.10))

	if modified == qty:
		var badge := UIHelpers.make_quantity_pill(str(qty), height, FLOW_BADGE_TEXT_SIZE)
		var bs := badge.custom_minimum_size
		badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		badge.offset_left = -bs.x + overlap
		badge.offset_top = -bs.y + overlap
		badge.offset_right = overlap
		badge.offset_bottom = overlap
		cell.add_child(badge)
		return

	# Changed output: struck default + actual, sized to content (snug padding), centred
	# on the same point the original single pill sat at.
	var base_w: int = height if str(qty).length() <= 1 else maxi(height, str(qty).length() * 9 + 14)
	var pill := _make_recipe_quantity_pill(qty, modified, height)
	var w: float = pill.custom_minimum_size.x
	var center_x: float = overlap - base_w / 2.0
	pill.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	pill.offset_left = center_x - w / 2.0
	pill.offset_right = center_x + w / 2.0
	pill.offset_top = -height + overlap
	pill.offset_bottom = overlap
	cell.add_child(pill)

# The output a recipe's good would actually produce after recipe_output modifiers
# and workforce output policies — the production result shown in the diagram.
func _modified_output_qty(good_item: Dictionary, default_qty: int) -> int:
	if _current_recipe.is_empty():
		return default_qty
	var recipe_id := str(_current_recipe.get("recipe_id", ""))
	var good_id := str(good_item.get("good_id", ""))
	var good_internal := str(good_item.get("internal_name", ""))
	if good_internal == "" and good_id != "":
		good_internal = str(Catalog.get_good(good_id).get("internal_name", ""))
	var ctx := {
		"recipe_id": recipe_id,
		"recipe_type": str(_current_recipe.get("recipe_type", "")).to_lower(),
		"building_id": str(_current_building.get("building_id", "")),
		"good_id": good_id,
		"good_internal": good_internal,
	}
	var modified := Modifiers.apply("recipe_output", recipe_id, float(default_qty), ctx)
	modified *= MatchState.workforce_output_multiplier()
	return int(round(modified))

# The dual recipe-diagram quantity pill: struck default on the LEFT and the actual
# on the RIGHT (red if the output dropped, green if it rose, each 1px white-outlined),
# a small gap between, sized to content with snug padding.
const _DUAL_PILL_PAD := 8   # horizontal padding inside the pill
const _DUAL_PILL_GAP := 8   # space between the struck default and the actual
func _make_recipe_quantity_pill(default_qty: int, modified_qty: int, height: int) -> Control:
	var struck_w: int = str(default_qty).length() * 9 + 6
	var actual_w: int = str(modified_qty).length() * 9 + 6
	var width: int = _DUAL_PILL_PAD * 2 + struck_w + _DUAL_PILL_GAP + actual_w

	var pill := Panel.new()
	pill.custom_minimum_size = Vector2(width, height)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.clip_contents = false
	var style := StyleBoxFlat.new()
	style.bg_color = DIAGRAM_NAVY
	style.border_color = DIAGRAM_PAPER
	style.set_border_width_all(2)
	style.set_corner_radius_all(int(height / 2.0))
	pill.add_theme_stylebox_override("panel", style)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(center)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _DUAL_PILL_GAP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(row)

	row.add_child(_make_struck_number(default_qty, height))

	var actual := Label.new()
	actual.text = str(modified_qty)
	var als := LabelSettings.new()
	als.font_size = FLOW_BADGE_TEXT_SIZE
	als.font_color = STATUS_GREEN if modified_qty > default_qty else STATUS_RED
	als.outline_size = 1
	als.outline_color = Color.WHITE
	actual.label_settings = als
	actual.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	actual.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	actual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(actual)
	return pill

# A number with a 1px line drawn through it (Label + centred ColorRect), paper-coloured.
func _make_struck_number(value: int, height: int) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(str(value).length() * 9 + 4, height)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lbl := Label.new()
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.text = str(value)
	var lset := LabelSettings.new()
	lset.font_color = DIAGRAM_PAPER
	lset.font_size = FLOW_BADGE_TEXT_SIZE
	lbl.label_settings = lset
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(lbl)
	var line := ColorRect.new()
	line.color = DIAGRAM_PAPER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.anchor_left = 0.0
	line.anchor_right = 1.0
	line.anchor_top = 0.5
	line.anchor_bottom = 0.5
	line.offset_left = 1.0
	line.offset_right = -1.0
	line.offset_top = -1.0
	line.offset_bottom = 0.0
	box.add_child(line)
	return box

func _update_flow_power(recipe: Dictionary) -> void:
	for child in flow_arrow.get_children():
		child.queue_free()

	# Energy draw scales with the building's level (the base grows on upgrade, same as the
	# grid draw in _effective_energy_req).
	var lvl := int(_current_building.get("level", 1))
	var energy_req: int = int(round(float(recipe.get("energy_req", 0)) * BuildingLevels.mult("energy", lvl)))
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
	return BuildingStatus.flow_output_items(recipe)

func _build_status_icon_column() -> void:
	for child in status_icon_column.get_children():
		if child != close_button:
			child.queue_free()
	_status_dots.clear()

	# Group the RAG indicators in a rounded highlight tray (DS BG_HIGHLIGHT).
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

	# En-route inputs badge: flashes red while input shipments for this
	# building's recipe are still on the road to its tile. Click = how many
	# turns away the first one is.
	_enroute_badge = Button.new()
	_enroute_badge.text = "!"
	_enroute_badge.visible = false
	_enroute_badge.custom_minimum_size = Vector2(22, 22)
	_enroute_badge.add_theme_font_size_override("font_size", 15)
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = STATUS_RED
	badge_style.set_corner_radius_all(11)
	for st in ["normal", "hover", "pressed", "focus"]:
		_enroute_badge.add_theme_stylebox_override(st, badge_style)
	for cn in ["font_color", "font_pressed_color", "font_hover_color", "font_focus_color"]:
		_enroute_badge.add_theme_color_override(cn, Color.WHITE)
	_enroute_badge.tooltip_text = "Inputs are on their way — click for arrival time"
	_enroute_badge.pressed.connect(_on_enroute_badge_pressed)
	rag_box.add_child(_enroute_badge)

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

	# 6th indicator: net production modifier — a signed %, coloured by band
	# (white −1..1%, red <−1%, green >1%). All active output multipliers add
	# together (−10% and +15% → +5%) before applying; hover lists each one.
	_mod_wrapper = HBoxContainer.new()
	_mod_wrapper.alignment = BoxContainer.ALIGNMENT_CENTER
	_mod_wrapper.theme = _tooltip_theme
	_mod_wrapper.mouse_filter = Control.MOUSE_FILTER_STOP
	_mod_wrapper.add_theme_constant_override("separation", 2)
	_mod_wrapper.custom_minimum_size = Vector2(STATUS_RAIL_WIDTH + 14.0, 0)

	var mod_icon := Label.new()
	mod_icon.text = "Δ"
	mod_icon.custom_minimum_size = STATUS_ICON_SIZE
	mod_icon.add_theme_font_size_override("font_size", 14)
	mod_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mod_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mod_icon.modulate = ICON_TINT
	mod_icon.mouse_filter = Control.MOUSE_FILTER_STOP
	mod_icon.theme = _tooltip_theme
	_mod_wrapper.add_child(mod_icon)

	_mod_label = Label.new()
	_mod_label.add_theme_font_size_override("font_size", 12)
	_mod_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mod_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mod_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_mod_label.theme = _tooltip_theme
	_mod_wrapper.add_child(_mod_label)

	rag_box.add_child(_mod_wrapper)

	# 7th indicator: only visible after a failed run, with a click-to-expand reason.
	_run_warning_button = Button.new()
	_run_warning_button.text = "!"
	_run_warning_button.visible = false
	_run_warning_button.flat = false
	_run_warning_button.focus_mode = Control.FOCUS_NONE
	_run_warning_button.theme = _tooltip_theme
	_run_warning_button.tooltip_text = "Production warning"
	_run_warning_button.custom_minimum_size = Vector2(24, 24)
	_run_warning_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_run_warning_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_run_warning_button.add_theme_font_size_override("font_size", 16)
	_run_warning_button.add_theme_color_override("font_color", STATUS_RED)
	_run_warning_button.add_theme_color_override("font_hover_color", STATUS_RED)
	_run_warning_button.add_theme_color_override("font_pressed_color", STATUS_RED)
	var warning_button_style := _make_run_warning_button_style()
	_run_warning_button.add_theme_stylebox_override("normal", warning_button_style)
	_run_warning_button.add_theme_stylebox_override("hover", warning_button_style)
	_run_warning_button.add_theme_stylebox_override("pressed", warning_button_style)
	_run_warning_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if not _run_warning_button.pressed.is_connected(_toggle_run_warning_details):
		_run_warning_button.pressed.connect(_toggle_run_warning_details)
	rag_box.add_child(_run_warning_button)

	_run_warning_details = PanelContainer.new()
	_run_warning_details.visible = false
	_run_warning_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_run_warning_details.custom_minimum_size = Vector2(0, 28)
	var warning_style := StyleBoxFlat.new()
	warning_style.bg_color = STATUS_RED
	warning_style.set_corner_radius_all(7)
	warning_style.set_content_margin(SIDE_LEFT, 10)
	warning_style.set_content_margin(SIDE_RIGHT, 10)
	warning_style.set_content_margin(SIDE_TOP, 4)
	warning_style.set_content_margin(SIDE_BOTTOM, 4)
	_run_warning_details.add_theme_stylebox_override("panel", warning_style)
	_run_warning_details_label = Label.new()
	_run_warning_details_label.add_theme_font_size_override("font_size", 12)
	_run_warning_details_label.add_theme_color_override("font_color", Color.WHITE)
	_run_warning_details_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_run_warning_details_label.clip_text = true
	_run_warning_details.add_child(_run_warning_details_label)
	_rag_panel = rag_panel

	# Place the strip in the main column, directly BELOW the recipe (inputs/outputs)
	# flow summary. Remove the vertical split: hide the old rail and let the fields
	# scroll fill the full width.
	panel_vbox.add_child(rag_panel)
	panel_vbox.move_child(rag_panel, flow_summary.get_index() + 1)
	panel_vbox.add_child(_run_warning_details)
	panel_vbox.move_child(_run_warning_details, rag_panel.get_index() + 1)
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
	_update_mod_label(building, recipe)
	_update_run_warning(building, recipe, is_infrastructure)
	_update_enroute_badge(building, recipe)

# ── en-route inputs badge ────────────────────────────────────────────────────
var _enroute_badge: Button
var _enroute_flash: Tween
var _enroute_min_turns: int = 0
var _enroute_count: int = 0

## Inbound (non-sale) shipments headed to this building's tile carrying one of
## its recipe's input goods. Market buys and tile moves both carry good_id/qty.
func _inbound_input_shipments(building: Dictionary, recipe: Dictionary) -> Array:
	var tile_id := str(building.get("tile_id", ""))
	if tile_id == "":
		return []
	var input_ids: Dictionary = {}
	for input in recipe.get("inputs", []):
		input_ids[str(input.get("good_id", ""))] = true
	if input_ids.is_empty():
		return []
	var out: Array = []
	for s in MatchState.pending_transport_shipments:
		var sd: Dictionary = s
		if bool(sd.get("is_sale", false)):
			continue
		if str(sd.get("destination_tile", "")) != tile_id:
			continue
		if input_ids.has(str(sd.get("good_id", ""))):
			out.append(sd)
	return out

func _update_enroute_badge(building: Dictionary, recipe: Dictionary) -> void:
	if _enroute_badge == null:
		return
	var shipments := _inbound_input_shipments(building, recipe)
	if shipments.is_empty():
		_enroute_badge.visible = false
		if _enroute_flash != null and _enroute_flash.is_valid():
			_enroute_flash.kill()
			_enroute_badge.modulate.a = 1.0
		return
	var min_turns := 999
	for s in shipments:
		min_turns = mini(min_turns, int((s as Dictionary).get("turns_remaining", 0)))
	var was_visible := _enroute_badge.visible
	_enroute_min_turns = maxi(min_turns, 0)
	_enroute_count = shipments.size()
	_enroute_badge.visible = true
	_enroute_badge.tooltip_text = ("%d input shipment%s en route — click for arrival time"
		% [_enroute_count, "" if _enroute_count == 1 else "s"])
	if not was_visible or _enroute_flash == null or not _enroute_flash.is_valid():
		if _enroute_flash != null and _enroute_flash.is_valid():
			_enroute_flash.kill()
		_enroute_flash = create_tween().set_loops()
		_enroute_flash.tween_property(_enroute_badge, "modulate:a", 0.35, 0.45)
		_enroute_flash.tween_property(_enroute_badge, "modulate:a", 1.0, 0.45)

func _on_enroute_badge_pressed() -> void:
	if _enroute_min_turns <= 0:
		MatchState.request_toast("Inputs arrive when this turn resolves.", "info")
	else:
		MatchState.request_toast("First input shipment arrives in %d turn%s (%d en route)."
			% [_enroute_min_turns, "" if _enroute_min_turns == 1 else "s", _enroute_count], "info")

func _make_run_warning_button_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = STATUS_RED
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(0)
	return style

func _update_run_warning(building: Dictionary, recipe: Dictionary, is_infrastructure: bool) -> void:
	if is_infrastructure or building.is_empty() or not MatchState.is_player_owned(building):
		_set_run_warning_message("")
		return
	var warning: Dictionary = Production.run_warning_for_building(building, recipe)
	_set_run_warning_message(str(warning.get("message", "")))

func _set_run_warning_message(message: String) -> void:
	if _run_warning_button == null:
		return
	if message == "":
		_current_run_warning_message = ""
		_run_warning_expanded = false
		_run_warning_button.visible = false
		if _run_warning_details != null:
			_run_warning_details.visible = false
		_stop_run_warning_blink()
		return
	if message != _current_run_warning_message:
		_run_warning_expanded = false
	_current_run_warning_message = message
	_run_warning_button.visible = true
	_run_warning_button.tooltip_text = message
	if _run_warning_details_label != null:
		_run_warning_details_label.text = message
	if _run_warning_details != null:
		_run_warning_details.visible = _run_warning_expanded
	_start_run_warning_blink()

func _toggle_run_warning_details() -> void:
	if _current_run_warning_message == "":
		return
	_run_warning_expanded = not _run_warning_expanded
	if _run_warning_details != null:
		_run_warning_details.visible = _run_warning_expanded

func _start_run_warning_blink() -> void:
	if _run_warning_button == null:
		return
	if _run_warning_tween != null and _run_warning_tween.is_running():
		return
	_run_warning_button.modulate = Color.WHITE
	_run_warning_tween = create_tween()
	_run_warning_tween.set_loops()
	_run_warning_tween.tween_property(_run_warning_button, "modulate:a", 0.35, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_run_warning_tween.tween_property(_run_warning_button, "modulate:a", 1.0, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _stop_run_warning_blink() -> void:
	if _run_warning_tween != null:
		_run_warning_tween.kill()
	_run_warning_tween = null
	if _run_warning_button != null:
		_run_warning_button.modulate = Color.WHITE

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
		color = BuildingStatus.cost_rag_color(uc, base_price)
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
	# costs_updated fires after grid_settlement + cost_solve each turn, so this is where the
	# RAG dots should refresh: the power/input dots reflect the just-settled power + run state
	# and would otherwise stay stale across turns while the panel is open. (A construction site
	# has its own refresh and no live dots, so only update its cost label.)
	if _showing_construction_instance != "" or _current_recipe.is_empty():
		_update_cost_label(_current_building)
		return
	var is_infra := str(Catalog.get_building(str(_current_building.get("building_id", ""))).get("category", "")) == "infrastructure"
	_update_status_icons(_current_building, _current_recipe, is_infra)

const _MOD_RAG_LEGEND := "White means no net effect (−1% to +1%), green a net production boost above +1%, red a net penalty below −1%."

# Net production-modifier indicator: every active recipe_output multiplier for this
# building/recipe summed (−10% and +15% → +5%), coloured by band, with the
# contributing multipliers listed on hover.
func _update_mod_label(building: Dictionary, recipe: Dictionary) -> void:
	if _mod_label == null:
		return
	# Single source of truth for the net-modifier %, its colour band, the component parts and the
	# intermittency derate — shared with the Empire view (scripts/building_status.gd).
	var mod := BuildingStatus.net_output_modifier(building, recipe)
	var parts: Array = mod.get("parts", [])
	var workforce_parts: Array = mod.get("workforce_parts", [])
	var derate: float = float(mod.derate)
	var eff_i: int = int(mod.pct)
	_mod_label.text = str(mod.text)
	_mod_label.add_theme_color_override("font_color", mod.color as Color)

	var tip: String
	if parts.is_empty() and workforce_parts.is_empty() and derate <= 0.0:
		tip = "Production modifier: none active.\n%s" % _MOD_RAG_LEGEND
	else:
		var lines: PackedStringArray = ["Production modifiers:"]
		if not parts.is_empty():
			lines.append("Recipe modifiers (added together):")
			for p in parts:
				var pv: float = float(p.get("pct", 0.0))
				lines.append("  %s%d%%  %s" % ["+" if pv > 0.0 else "", int(round(pv)), str(p.get("label", ""))])
		if not workforce_parts.is_empty():
			lines.append("Workforce policies (multiplicative):")
			for p in workforce_parts:
				var pv: float = float(p.get("pct", 0.0))
				lines.append("  %s%d%%  %s" % ["+" if pv > 0.0 else "", int(round(pv)), str(p.get("label", ""))])
		if derate > 0.0:
			lines.append("  -%d%%  Intermittency impact (multiplicative, applied after)" % int(round(derate * 100.0)))
		lines.append("Net: %s%d%%" % ["+" if eff_i > 0 else "", eff_i])
		lines.append(_MOD_RAG_LEGEND)
		tip = "\n".join(lines)
	_mod_label.tooltip_text = tip
	if _mod_wrapper != null:
		_mod_wrapper.tooltip_text = tip
		var glyph := _mod_wrapper.get_child(0) as Label
		if glyph != null:
			glyph.tooltip_text = tip

func _on_modifiers_changed() -> void:
	if _current_building.is_empty() or _current_recipe.is_empty():
		return
	_update_mod_label(_current_building, _current_recipe)
	_update_flow_summary(_current_recipe)

func _on_workforce_policies_changed() -> void:
	if _current_building.is_empty() or _current_recipe.is_empty():
		return
	_update_mod_label(_current_building, _current_recipe)
	_update_flow_summary(_current_recipe)

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
	return BuildingStatus.power_status_color(building, recipe, is_infrastructure)

func _input_status_color(building: Dictionary, recipe: Dictionary, is_infrastructure: bool) -> Color:
	return BuildingStatus.input_status_color(building, recipe, is_infrastructure)

func _transport_duration_status_color(building: Dictionary, recipe: Dictionary, is_infrastructure: bool) -> Color:
	return BuildingStatus.transport_duration_status_color(building, recipe, is_infrastructure)

func _transport_cost_status_color(building: Dictionary, recipe: Dictionary, is_infrastructure: bool) -> Color:
	return BuildingStatus.transport_cost_status_color(building, recipe, is_infrastructure)

func _selected_output_route(building: Dictionary, recipe: Dictionary) -> Dictionary:
	return BuildingStatus.selected_output_route(building, recipe)

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
	return BuildingStatus.power_supply(building)

func _tile_power_state(tile_id: String) -> Dictionary:
	return BuildingStatus.tile_power_state(tile_id)

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
	return BuildingStatus.produced_since_construction(building, recipe)

func _produced_good_display_name(good_key: String, recipe: Dictionary) -> String:
	return BuildingStatus.produced_good_display_name(good_key, recipe)

func _full_output_streak(building: Dictionary) -> int:
	return BuildingStatus.full_output_streak(building)

func _primary_output_display_name(recipe: Dictionary) -> String:
	return BuildingStatus.primary_output_display_name(recipe)

func _good_display_from_internal(internal_name: String) -> String:
	return BuildingStatus.good_display_from_internal(internal_name)

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
	return BuildingStatus.maintenance_cost(building_data)

func _labour_cost(building_data: Dictionary) -> float:
	var base_cost: float = (
		building_data.get("labour_unskilled_required", 0) * EconomyConfig.LABOUR_UNSKILLED_RATE
		+ building_data.get("labour_skilled_required", 0) * EconomyConfig.LABOUR_SKILLED_RATE
		+ building_data.get("labour_h_skilled_required", 0) * EconomyConfig.LABOUR_HIGH_SKILLED_RATE
	)
	return base_cost * MatchState.labour_policy_factor()

func _output_destination() -> String:
	var instance_id: String = _current_building.get("instance_id", "")
	var good_id := _primary_output_good_id(_current_recipe)
	var special_order_id := MatchState.get_output_special_order_id(instance_id, good_id)
	if special_order_id != "":
		var order := SpecialOrderState.get_order(special_order_id)
		if not order.is_empty():
			return "Special Order: %s" % str(order.get("display_name", Catalog.get_display_name(good_id)))
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
	if MatchState.is_output_market(instance_id, good_id):
		target = TransportService.nearest_port_tile(source_tile)
		var special_order_id := MatchState.get_output_special_order_id(instance_id, good_id)
		if special_order_id != "" and not SpecialOrderState.get_order(special_order_id).is_empty():
			destination = ("Special Order (via %s)" % Catalog.tile_label(target)) if target != "" else "Special Order"
		else:
			destination = ("Market (via %s)" % Catalog.tile_label(target)) if target != "" else "Market"
	elif dest_tile != "":
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
	return BuildingStatus.primary_output_good_id(recipe)

# Primary output's internal_name — the key the deposit-penalty / mining-yield
# modifiers match on (Modifiers target_match {good_internal: …}).
func _primary_output_internal(recipe: Dictionary) -> String:
	return BuildingStatus.primary_output_internal(recipe)

func _primary_output_qty(recipe: Dictionary) -> int:
	return BuildingStatus.primary_output_qty(recipe)

func _route_summary_for_good(source_tile: String, destination_tile: String, good_id: String, qty: int) -> Dictionary:
	return BuildingStatus.route_summary(source_tile, destination_tile, good_id, qty)

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
