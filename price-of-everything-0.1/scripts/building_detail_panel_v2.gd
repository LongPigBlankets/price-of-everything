extends PanelContainer
const Metrics := preload("res://scripts/ds2/metrics.gd")
const EffectEmblem := preload("res://scripts/effect_emblem.gd")
## Building Detail — the scenario-adaptive detail panel.
## Code-instantiated by world_map. THE building detail panel.
## Renders a shared, UI-agnostic readout (building_readout.gd): header + status badge → adaptive
## recipe/flow strip (frameless good icons in independent input/output grids) → always-open
## diagnostics checklist → emphasised per-output cost-to-produce → economics → inbound shipments →
## routing (with the map-highlight signal) → labour. Live via coalesced refresh. Upgrade/recipe/
## sell/demolish sheets, banners and battery/infra/port variants land in later phases.
## See docs/building-detail-v2-plan.md.

const BuildingReadout := preload("res://scripts/building_readout.gd")
const BuildingStatus := preload("res://scripts/building_status.gd")
const GoodIcons := preload("res://scripts/good_icons.gd")
const UIHelpers := preload("res://scripts/ui_helpers.gd")
const BuyDialog := preload("res://scripts/buy_building_dialog.gd")
const BuildingLevels := preload("res://scripts/building_levels.gd")
const InfrastructureInfo := preload("res://scripts/infrastructure_info.gd")
const BdpV3Block := preload("res://scripts/bdp_v3_block.gd")
const BdpV3Footer := preload("res://scripts/bdp_v3_footer.gd")
const BdpV3Key := preload("res://scripts/bdp_v3_key.gd")
const BdpV3Lamp := preload("res://scripts/bdp_v3_lamp.gd")
const BdpV3Plate := preload("res://scripts/bdp_v3_plate.gd")
const BdpV3Scroll := preload("res://scripts/bdp_v3_scroll.gd")
const BdpV3Seam := preload("res://scripts/bdp_v3_seam.gd")
const BdpV3Title := preload("res://scripts/bdp_v3_title.gd")
const BdpV3Enamel := preload("res://scripts/bdp_v3_enamel.gd")
const BdpV3Light := preload("res://scripts/bdp_v3_light.gd")
const BdpV3Cable := preload("res://scripts/bdp_v3_cable.gd")
const BdpV3Counter := preload("res://scripts/bdp_v3_counter.gd")
const PanelGauge := preload("res://scripts/panel_gauge.gd")
const BdpV3Nine := preload("res://scripts/bdp_v3_nine.gd")
const BdpV3Section := preload("res://scripts/bdp_v3_section.gd")
const BdpV3Heading := preload("res://scripts/bdp_v3_heading.gd")
const BdpV3Toggle := preload("res://scripts/bdp_v3_toggle.gd")
const BdpV3Door := preload("res://scripts/bdp_v3_door.gd")
const BdpV3LabourDoor := preload("res://scripts/bdp_v3_labour_door.gd")
const BdpV3ModKey := preload("res://scripts/bdp_v3_mod_key.gd")
const BdpV3Led := preload("res://scripts/bdp_v3_led.gd")
const BdpV3Indicator := preload("res://scripts/bdp_v3_indicator.gd")
const BdpV3Readout := preload("res://scripts/bdp_v3_readout.gd")
const BdpV3Emblem := preload("res://scripts/bdp_v3_emblem.gd")
const BuildingEconomics := preload("res://scripts/building_economics.gd")
const BuildingPrice := preload("res://scripts/building_price.gd")
const BdpV3ValueBar := preload("res://scripts/bdp_v3_value_bar.gd")
## v3 frames these sections (heading and content together); the value names the frame, so sections
## sharing a name share one frame (Modifiers and Economics).
const V3_FRAMED_SECTIONS := {
	"Diagnostics": "diagnostics", "Cost to produce": "cost", "Modifiers": "money", "Economics · per turn": "money",
	"Infrastructure": "infrastructure", "Breakdown": "breakdown", "Inbound shipments": "shipments",
	"Labour on this building": "labour", "Labour and Wages": "labour",
}
const ROUTE_STOCKPILE_ICON: Texture2D = preload("res://assets/icons/ui_icons/route_stockpile.png")
const ROUTE_MARKET_ICON: Texture2D = preload("res://assets/icons/ui_icons/route_port.png")
const ROUTE_MIDDLEMAN_ICON: Texture2D = preload("res://assets/icons/ui_icons/route_lorry.png")
const INPUT_ICON: Texture2D = preload("res://assets/icons/ui_icons/construction_materials.png")
const OUTPUT_ICON: Texture2D = preload("res://assets/icons/research/glyph/output.png")



const HEADER_HEIGHT := 44.0
const PANEL_EDGE_MARGIN := 20.0
const TOP_BAR_CLEARANCE := 72.0   # clears the top bar and its shadow
const BOTTOM_CLEARANCE := 110.0  # fallback: keep clear of the bottom menu when no tile panel to match
const PANEL_WIDTH := 460.0
const CONTENT_MARGIN := 26
## The width v3's header keeps for its keys.
const V3_KEY_COLUMN := 96.0 / 1.875
## The backing's rounded corner, in pixels (panel_backing: 4 + 16 layout pixels), and its brass trim's
## width in layout pixels (layout.json panel_backing).
const BACKING_CORNER := 10.5
const BACKING_TRIM := 14.0

# Empire-view click (world_map sets this before show_building): dock at the tile view
# panel's spot instead of the default edge position — in that view there IS no tile panel,
# and the detail panel takes its place.
var empire_dock := false
# Set by _open_sheet's optional extra_width — widens the WHOLE panel (right-anchored,
# so it grows further left, never off-screen) while a sheet that needs more than
# PANEL_WIDTH is open, e.g. the "Change recipe" sheet's mini diagram bars. Reset to
# 0 on _close_sheet so every other view keeps the normal width.
var _sheet_extra_width := 0.0
const MARKET_ICON := 98  # framed good-icon size, matching the market panel's goods rows
const CREAM := Color(0.995234, 0.930806, 0.763265)  # recipe-strip parchment (matches v1 diagram paper)
const CREAM_INK := Color(0.0, 0.119856, 0.243095)   # navy ink on the parchment
const CREAM_INK_BAD := Color(0.6, 0.28, 0.16)
const RECIPE_ARROW_PATH := "res://assets/icons/ui_icons/recipe_arrow.png"
const RECIPE_POWER_ICON_PATH := "res://assets/icons/ui_icons/recipe_power_icon.png"

## Mirrors the v1 signal so world_map's building-connection map highlight wires identically.
signal building_connections_changed(origin_tile_id: String, input_tile_ids: Array, output_tile_ids: Array, has_market_output: bool)

var _current_building: Dictionary = {}
var _title_label: Label = null
# v3 shows the title in raised white letters instead of the label (which keeps the text).
var _title_v3: BdpV3Title = null
## v3: the building's icon in polished metal, top left, two title lines tall.
var _emblem_v3: Control = null
var _subtitle_label: Label = null
var _badge: PanelContainer = null
var _badge_label: Label = null
# v3 shows the status as a lamp and its label instead of the badge.
var _status_v3: HBoxContainer = null
var _status_lamp: BdpV3Lamp = null
var _status_v3_label: Label = null
var _body: VBoxContainer = null
var _scroll: ScrollContainer = null
# The header and body (everything under v3's lamp but the backing).
var _margin: MarginContainer = null
# v3's non-slip edge over the seam between the header and the scrolling body.
var _seam: Control = null
var _dragging := false
var _drag_offset := Vector2.ZERO
# coalesced-refresh state (house doctrine — one rebuild per frame max)
var _refresh_queued := false
var _dirty := false
# NPC buy-confirm dialog (lazily built on its own CanvasLayer, mirrors the market panel)
var _buy_dialog: Node = null
var _buy_layer: CanvasLayer = null
var _pending_buy: Dictionary = {}
# Action sheets (in-panel overlay) + the reused upgrade dialog
var _upgrade_dialog: Control = null
var _upgrade_dialog_layer: CanvasLayer = null
var _sheet: Control = null
# Header close control: the v2 button, and the v3 keycap shown instead while `toggle bdp v3` is on.
var _close_button: Button = null
var _close_key: TextureButton = null
# v3's Location keycap under the close key: pans the map to the building.
var _pin_key: TextureButton = null
# v3's lamp over the whole panel (a multiply overlay; see bdp_v3_light.gd).
var _shade: Control = null
# v2's brass pipe border, and v3's backing plate (dark navy-grey steel in a brass trim) drawn behind
# everything instead.
var _pipe_frame: Control = null
var _backing: Control = null

func _ready() -> void:
	if DS and DS.theme:
		theme = DS.theme
	custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_build_shell()
	_wire_live_refresh()
	visibility_changed.connect(_on_visibility_changed)
	UiPrefs.bdp_v3_changed.connect(_on_bdp_v3_changed)

# --- shell ---------------------------------------------------------------------------------

func _build_shell() -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = DS.PALETTE["BG_PANEL"]
	bg.set_border_width_all(0)   # the brass pipe overlay replaces the coloured outline
	bg.border_color = DS.PALETTE["BORDER_SOFT"]
	bg.set_corner_radius_all(10)
	bg.set_content_margin_all(0)
	add_theme_stylebox_override("panel", bg)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, CONTENT_MARGIN)   # clear the brass frame
	add_child(margin)
	_margin = margin
	_pipe_frame = preload("res://scripts/brass_pipe_frame.gd").new()
	add_child(_pipe_frame)   # brass frame, drawn on top
	_backing = BdpV3Nine.make("panel_backing", 64.0)
	add_child(_backing)
	move_child(_backing, 0)   # behind the content
	# Over the backing and content, under the action sheets (added later).
	_shade = Control.new()
	_shade.name = "BdpV3Shade"
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.material = BdpV3Light.shade_material()
	_shade.draw.connect(func() -> void: _shade.draw_rect(Rect2(Vector2.ZERO, _shade.size), Color.WHITE))
	_shade.resized.connect(func() -> void: (_shade.material as ShaderMaterial).set_shader_parameter("rect_size", _shade.size))
	(_shade.material as ShaderMaterial).set_shader_parameter("corner", BACKING_CORNER)
	add_child(_shade)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", DS.SP["SM"])
	margin.add_child(outer)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", DS.SP["SM"])
	outer.add_child(header)
	_emblem_v3 = BdpV3Emblem.new()
	header.add_child(_emblem_v3)
	_title_label = Label.new()
	_title_label.theme_type_variation = "Title"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_label.custom_minimum_size = Vector2(PANEL_WIDTH - 2.0 * DS.SP["MD"] - 44.0, 0)
	header.add_child(_title_label)
	_title_v3 = BdpV3Title.new()
	# The emblem takes its side and a gap from the title's width.
	_title_v3.custom_minimum_size = Vector2(_title_label.custom_minimum_size.x - BdpV3Emblem.side() - DS.SP["SM"], 0)
	header.add_child(_title_v3)
	_close_button = Button.new()
	_close_button.text = "X"
	_close_button.custom_minimum_size = Vector2(32, 32)
	_close_button.pressed.connect(_hide_panel)
	header.add_child(_close_button)
	# v3's keys: Close beside the title's first line and Location beside its second, each a line tall.
	# The keys' renders carry room round them for their shadows, so the controls overlap and sit a little
	# above the title's top.
	var line := BdpV3Title.line_height()
	var key_side := roundf(BdpV3Key.control_side(line))
	var key_lift := MarginContainer.new()
	key_lift.name = "HeaderKeys"
	key_lift.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	key_lift.add_theme_constant_override("margin_top", roundi((line - key_side) * 0.5))
	# The header keeps the width it always had for the keys; the rest of a key's render is shadow room.
	key_lift.add_theme_constant_override("margin_right", mini(0, roundi(V3_KEY_COLUMN - key_side)))
	header.add_child(key_lift)
	var keys := VBoxContainer.new()
	keys.add_theme_constant_override("separation", roundi(BdpV3Title.line_pitch() - key_side))
	key_lift.add_child(keys)
	_close_key = BdpV3Key.make("close", line)
	_close_key.pressed.connect(_hide_panel)
	keys.add_child(_close_key)
	_pin_key = BdpV3Key.make("pin", line)
	_pin_key.pressed.connect(_on_pin_pressed)
	keys.add_child(_pin_key)

	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", DS.SP["SM"])
	outer.add_child(meta)
	_badge = PanelContainer.new()
	_badge_label = Label.new()
	_badge_label.theme_type_variation = "Caption"
	_badge.add_child(_badge_label)
	meta.add_child(_badge)
	_status_v3 = HBoxContainer.new()
	_status_v3.name = "BdpV3Status"
	_status_v3.add_theme_constant_override("separation", 6)
	_status_lamp = BdpV3Lamp.new()
	_status_v3.add_child(_status_lamp)
	_status_v3_label = Label.new()
	_status_v3_label.uppercase = true
	_status_v3_label.add_theme_font_override("font", BdpV3Plate.FONT_SEMI)
	_status_v3_label.add_theme_font_size_override("font_size", 18)
	_status_v3_label.add_theme_color_override("font_color", DS.PALETTE["TEXT"])
	_status_v3_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status_v3.add_child(_status_v3_label)
	meta.add_child(_status_v3)
	_subtitle_label = Label.new()
	_subtitle_label.theme_type_variation = "Caption"
	_subtitle_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.add_child(_subtitle_label)

	# The scroll area sits in a plain Control so that v3's seam edge, added after it, draws over the
	# top of the body; with v3 on, the body starts at the edge's lip.
	var well := Control.new()
	well.name = "BodyWell"
	well.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(well)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	well.add_child(_scroll)
	_seam = BdpV3Seam.new()
	_seam.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_seam.offset_bottom = BdpV3Seam.strip_height()
	# Out to the backing's trim (4 layout pixels and the trim in from the panel's edge), less a hair.
	_seam.outset = CONTENT_MARGIN - (4.0 + BACKING_TRIM) / BdpV3Seam.CAPTURE_SCALE - 0.5
	well.add_child(_seam)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", DS.SP["SM"])
	_scroll.add_child(_body)
	# The diagnostics' readout keeps in sight as the body scrolls or the panel changes height.
	_body.item_rect_changed.connect(_v3_place_readout)
	_scroll.resized.connect(_v3_place_readout)
	_apply_v3_chrome()

# --- live refresh (coalesced) --------------------------------------------------------------

func _wire_live_refresh() -> void:
	# Any sim change that can move a number the readout shows → one deferred rebuild per frame.
	var conns: Array = [
		[CostSolver, "costs_updated"],
		[Modifiers, "modifiers_changed"],
		[MatchState, "workforce_policies_changed"],
		[Stockpile, "stockpile_changed"],
		[MatchState, "transport_shipments_changed"],
		[MatchState, "output_stockpile_destination_changed"],
		[MatchState, "deposits_changed"],
		[Production, "turn_processed"],
		[MatchState, "building_upgraded"],
		[MatchState, "building_upgrade_started"],
		[MatchState, "building_upgrade_cancelled"],
		[MatchState, "building_upgrade_progress"],
		[MatchState, "building_retrofit_started"],
		[MatchState, "building_retrofitted"],
		[MatchState, "building_demolish_started"],
		[MatchState, "building_demolished"],
		[MatchState, "building_owner_changed"],
	]
	for c in conns:
		var obj: Object = c[0]
		var sig: String = c[1]
		if obj.has_signal(sig) and not obj.is_connected(sig, _queue_refresh):
			obj.connect(sig, _queue_refresh)

func _queue_refresh(_a: Variant = null, _b: Variant = null, _c: Variant = null, _d: Variant = null) -> void:
	_dirty = true
	if _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_apply_refresh")

func _apply_refresh() -> void:
	_refresh_queued = false
	if not _dirty or not visible or _current_building.is_empty():
		return  # hidden: stay dirty, catch up on show
	_dirty = false
	var iid := str(_current_building.get("instance_id", ""))
	var live: Dictionary = BuildingState.get_building(iid) if iid != "" else {}
	if not live.is_empty():
		_current_building = live
	_rebuild(_current_building)
	_apply_v3_text_light()
	_resize_body()  # content height may have changed; keep the current (possibly dragged) position

func _on_visibility_changed() -> void:
	if visible and _dirty:
		_queue_refresh()

# --- entry point ---------------------------------------------------------------------------

func show_building(building: Dictionary) -> void:
	_close_sheet()
	_current_building = building
	_dirty = false
	_rebuild(building)
	_apply_v3_text_light()
	visible = true
	PanelStack.push(self)
	_size_and_position()

func _rebuild(building: Dictionary) -> void:
	for child in _body.get_children():
		# A purchase emits building_owner_changed and the tutorial immediately focuses the
		# newly-owned building. Both paths can rebuild in the same frame. queue_free() alone
		# leaves the old controls participating in the VBox minimum-size calculation until
		# frame end, which briefly stretched the detail panel across most of the viewport.
		_body.remove_child(child)
		child.queue_free()

	var building_data: Dictionary = Catalog.get_building(str(building.get("building_id", "")))
	var recipe: Dictionary = Catalog.get_recipe(str(building.get("recipe_id", "")))
	var is_infra := str(building_data.get("category", "")).to_lower() == "infrastructure"
	var kind := BuildingReadout.classify(building_data, recipe, str(building.get("building_id", "")))

	var display_name := str(building_data.get("display_name", building.get("building_id", "Building")))
	var recipe_name := str(recipe.get("display_name", ""))
	_title_label.text = display_name if recipe_name == "" else "%s — %s" % [display_name, recipe_name]
	_title_v3.text = _title_label.text
	_emblem_v3.visible = UiPrefs.use_bdp_v3 and _emblem_v3.set_building(str(building.get("building_id", "")))
	_apply_v3_title()
	# Catalog.tile_label, not the raw id: this was the one surface still printing
	# "tile_5_9" at the player instead of "Stoneshore Fields - (5, 9)".
	var _tile := str(building.get("tile_id", ""))
	var display_level := int(building.get("level", 1))
	if BuildingWorks.INFRA_UPGRADABLE.has(str(building_data.get("internal_name", ""))):
		display_level = BuildingWorks.infra_tile_level(building)
	_subtitle_label.text = "Level %d · %s" % [
		display_level, Catalog.tile_label(_tile) if _tile != "" else "—"]
	_pin_key.tooltip_text = "Show on the map · %s" % (Catalog.tile_label(_tile) if _tile != "" else "—")

	# construction site → materials checklist + countdown only
	var constr := BuildingReadout.construction(building)
	if bool(constr.get("active", false)):
		_render_construction(building, recipe, constr)
		building_connections_changed.emit(str(building.get("tile_id", "")), [], [], false)
		return

	# NPC-owned → recipe + big "Owned by [company]" + Buy (no other info, no frost)
	var own := BuildingReadout.owner_info(building)
	if bool(own.get("is_npc", false)):
		_render_npc(building, building_data, recipe, own)
		building_connections_changed.emit(str(building.get("tile_id", "")), [], [], false)
		return

	_set_badge(BuildingReadout.status(building, recipe, is_infra))

	# adaptive strip: storage meter / port / infrastructure note / recipe flow
	var fl := BuildingReadout.flow(building, recipe)
	if kind == "battery":
		_body.add_child(_build_storage_card(building))
		if BuildingReadout.owner_info(building).get("is_npc", false) == false:
			_body.add_child(_build_battery_actions(building, recipe))
	elif kind == "port":
		_body.add_child(_build_port_card(building))
	elif is_infra:
		_body.add_child(_build_infra_card())
		# Levellable infra (roads/rails/pipes/reinf_pipes/cables) gets the same Upgrade
		# button as production buildings — it opens the cash-only upgrade sheet.
		if BuildingWorks.INFRA_UPGRADABLE.has(str(building_data.get("internal_name", ""))):
			_body.add_child(_build_primary_actions(building, building_data))
	elif BuildingReadout.is_recipe_kind(kind) and (not (fl.get("output", {}) as Dictionary).is_empty() or not (fl.get("inputs", []) as Array).is_empty()):
		_body.add_child(_build_recipe_strip(fl))

	# primary actions (upgrade · change recipe) + routing (input sources · output destination),
	# both right under the recipe strip; routing opens action sheets.
	if BuildingReadout.is_recipe_kind(kind) and not is_infra:
		if UiPrefs.use_bdp_v3:
			_body.add_child(_build_v3_block(building, recipe))
		else:
			_body.add_child(_build_routing_buttons(building, recipe))
			_body.add_child(_build_primary_actions(building, building_data))

	if UiPrefs.use_bdp_v3:
		var diag_head := _make_section("Diagnostics")
		diag_head.add_child(_v3_view_switch())
		_body.add_child(diag_head)
	else:
		_body.add_child(_make_section("Diagnostics", "always shown"))
	var diag_card := _build_diagnostics(BuildingReadout.diagnostics(building, recipe, building_data, is_infra))
	_body.add_child(diag_card)
	# v3's economics, quoted once: the visual diagnostics' carbon check reads it as well as the section.
	var v3_econ: Dictionary = BuildingEconomics.per_turn(building) if UiPrefs.use_bdp_v3 else {}
	if UiPrefs.use_bdp_v3:
		# Both views are built; the switch shows one.
		var diag_visual := _build_v3_diag_visual(building, recipe, is_infra, v3_econ)
		_body.add_child(diag_visual)
		_v3_diag_text_card = diag_card
		_v3_diag_visual_view = diag_visual
		_v3_show_diag_view()

	# emphasised cost-to-produce (per output good, vs its market price)
	if not is_infra and kind != "battery":
		var cost_rows := BuildingReadout.cost_to_produce(building)
		if not cost_rows.is_empty():
			_body.add_child(_make_section("Cost to produce"))
			_body.add_child(_build_cost_to_produce(cost_rows))

	# Modifiers: everything currently bending this building's
	# numbers, in an accordion whose chevroned section header expands on click.
	if not is_infra and kind != "battery":
		_add_modifiers_accordion(building, recipe)

	if UiPrefs.use_bdp_v3:
		# v3: value added in production, transport, and what is left; nothing for a building with
		# neither inputs nor outputs (a battery), whose running costs are no measure beside a producer's.
		if bool(v3_econ.get("shown", false)):
			_body.add_child(_make_section("Economics · per turn"))
			_body.add_child(_build_economics_v3(v3_econ))
	else:
		_body.add_child(_make_section("Economics · per turn"))
		_body.add_child(_build_economics(BuildingReadout.economics(building, recipe, building_data)))
	if is_infra:
		_body.add_child(_make_section("Infrastructure"))
		_body.add_child(_build_infrastructure_details(building_data))
		var breakdown := _build_infra_breakdown(building, building_data)
		if breakdown != null:
			_body.add_child(_make_section("Breakdown"))
			_body.add_child(breakdown)

	# v3 leaves the power line out: the diagnostics say the same.
	var pw := BuildingReadout.power(building, recipe)
	if bool(pw.get("needs", false)) and not UiPrefs.use_bdp_v3:
		_body.add_child(_build_power_line(pw))

	# inbound shipments
	var ships := BuildingReadout.shipments(building, recipe)
	if not ships.is_empty():
		_body.add_child(_make_section("Inbound shipments"))
		_body.add_child(_build_shipments(ships))

	_body.add_child(_make_section("Labour and Wages" if UiPrefs.use_bdp_v3 else "Labour on this building"))
	# Headcounts from the recipe/building; cost is the engine's actual grown-wage charge (level +
	# labour modifiers included), the same figure the Economics card shows — not the base rate.
	var lab_readout: Dictionary = BuildingReadout.labour(building_data, recipe)
	lab_readout["cost"] = Production._calculate_labour_cost(building, recipe)
	_body.add_child(_build_labour(lab_readout))

	# sell / demolish (player-owned; the early NPC/construction returns skip this)
	var sell_row: Control
	if UiPrefs.use_bdp_v3 and not BuildingWorks.is_demolishing(str(building.get("instance_id", ""))):
		sell_row = _build_v3_footer(building)
	else:
		sell_row = _build_sell_demolish_row(building, building_data)
	sell_row.set_meta("v3_section_end", true)
	_body.add_child(sell_row)
	if UiPrefs.use_bdp_v3:
		_v3_frame_sections()

	# map highlight: light up supplier/consumer tiles for this building
	var conn := BuildingReadout.connections(building, recipe)
	building_connections_changed.emit(str(conn.get("origin", "")), conn.get("input_tiles", []), conn.get("output_tiles", []), bool(conn.get("has_market", false)))

# --- badge ---------------------------------------------------------------------------------

func _set_badge(st: Dictionary) -> void:
	var c := _tone_color(str(st.get("tone", "idle")))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(c.r, c.g, c.b, 0.14)
	style.border_color = Color(c.r, c.g, c.b, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	_badge.add_theme_stylebox_override("panel", style)
	_badge_label.text = str(st.get("label", ""))
	_badge_label.add_theme_color_override("font_color", c)
	_status_lamp.set_tone(str(st.get("tone", "idle")))
	_status_v3_label.text = str(st.get("label", ""))

# --- NPC-owned body (recipe + big "Owned by [company]" + Buy; nothing else, no frost) ------

func _render_npc(building: Dictionary, building_data: Dictionary, recipe: Dictionary, own: Dictionary) -> void:
	_set_badge({"label": "NPC-owned", "tone": "info"})
	var kind := BuildingReadout.classify(building_data, recipe, str(building.get("building_id", "")))
	if kind == "port":
		_body.add_child(_build_port_card(building))
	else:
		var fl := BuildingReadout.flow(building, recipe)
		if not (fl.get("output", {}) as Dictionary).is_empty() or not (fl.get("inputs", []) as Array).is_empty():
			_body.add_child(_build_recipe_strip(fl))

	var card := _make_card()
	var vb := card.get_child(0) as VBoxContainer
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 2)
	var kicker := Label.new()
	kicker.theme_type_variation = "Caption"
	kicker.text = "DISUSED — FORMERLY" if bool(own.get("is_ruins", false)) else "OWNED BY"
	kicker.add_theme_color_override("font_color", DS.PALETTE["TEXT_DIM"])
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(kicker)
	var company := Label.new()
	company.theme_type_variation = "Title"
	company.text = str(own.get("company", "Unknown"))
	company.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	company.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(company)
	_body.add_child(card)

	if not bool(own.get("is_ruins", false)):
		var display_name := str(building_data.get("display_name", building.get("building_id", "Building")))
		var price := BuildingReadout.buy_price(building)
		var buy := Button.new()
		buy.name = "NPCBuildingBuyButton"
		buy.theme_type_variation = "Primary"
		buy.text = "Buy — £%s" % _fmt_int(price)
		buy.custom_minimum_size = Vector2(0, 46)
		buy.disabled = Tutorial.port_purchase_disabled(str(building.get("building_id", "")))
		if buy.disabled:
			buy.tooltip_text = Tutorial.PORT_PURCHASE_DISABLED_TOOLTIP
		buy.pressed.connect(func() -> void: _open_buy_dialog(str(building.get("instance_id", "")), display_name, price))
		_body.add_child(buy)

func _fmt_int(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out

func _open_buy_dialog(iid: String, building_name: String, price: int) -> void:
	var building: Dictionary = BuildingState.get_building(iid)
	if Tutorial.port_purchase_disabled(str(building.get("building_id", ""))):
		return
	if _buy_layer == null or not is_instance_valid(_buy_layer):
		_buy_layer = CanvasLayer.new()
		_buy_layer.layer = 130
		get_tree().root.add_child(_buy_layer)
	if _buy_dialog == null or not is_instance_valid(_buy_dialog):
		_buy_dialog = BuyDialog.new()
		_buy_layer.add_child(_buy_dialog)
		_buy_dialog.connect("confirmed", _on_buy_confirmed)
	_pending_buy = {"iid": iid, "name": building_name, "price": price}
	_buy_dialog.call("open", building_name, price)

func _on_buy_confirmed(_dont_ask: bool) -> void:
	var iid := str(_pending_buy.get("iid", ""))
	var building_name := str(_pending_buy.get("name", ""))
	var price := int(_pending_buy.get("price", 0))
	var building: Dictionary = BuildingState.get_building(iid)
	if Tutorial.port_purchase_disabled(str(building.get("building_id", ""))):
		return
	if iid == "" or not BuildingState.buildings.has(iid):
		return
	if not MatchState.deduct_money(float(price)):
		MatchState.build_rejected_no_funds.emit("Not enough money to buy %s — need £%d, you have £%.0f" % [building_name, price, MatchState.money])
		return
	BuildingState.set_building_owner(iid, MatchState.LOCAL_PLAYER)
	MatchState.request_toast("Purchased %s for £%d" % [building_name, price], "success")
	Audio.transaction()
	# building_owner_changed → coalesced refresh re-reads the now-owned building → full panel.

# --- construction body (materials checklist + countdown + cancel) --------------------------

func _render_construction(building: Dictionary, recipe: Dictionary, constr: Dictionary) -> void:
	_set_badge({"label": "Under construction", "tone": "warn"})
	var fl := BuildingReadout.flow(building, recipe)
	if not (fl.get("output", {}) as Dictionary).is_empty() or not (fl.get("inputs", []) as Array).is_empty():
		_body.add_child(_build_recipe_strip(fl))

	var building_phase := bool(constr.get("building_phase", false))
	var card := _make_card()
	var vb := card.get_child(0) as VBoxContainer
	var title := Label.new()
	title.theme_type_variation = "Body"
	title.add_theme_color_override("font_color", DS.PALETTE["WARN"])
	title.text = "Construction under way" if building_phase else "Awaiting building materials"
	vb.add_child(title)
	var sub := Label.new()
	sub.theme_type_variation = "Caption"
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var after := int(constr.get("turns_after", 0))
	if building_phase:
		var left := int(constr.get("turns_left", 0))
		sub.text = "%d of %d turn%s remaining" % [left, after, "" if after == 1 else "s"]
	else:
		sub.text = "Construction begins once all materials arrive · then a %d-turn build" % after
	vb.add_child(sub)
	_body.add_child(card)

	var mats: Array = constr.get("materials", [])
	if not mats.is_empty():
		var secured := 0
		for m in mats:
			if bool(m.get("secured", false)):
				secured += 1
		_body.add_child(_make_section("Building materials", "%d/%d secured" % [secured, mats.size()]))
		var mc := _make_card()
		var mvb := mc.get_child(0) as VBoxContainer
		mvb.add_theme_constant_override("separation", DS.SP["SM"])
		for i in mats.size():
			var m: Dictionary = mats[i]
			if i > 0:
				mvb.add_child(HSeparator.new())
			var hb := HBoxContainer.new()
			hb.add_theme_constant_override("separation", DS.SP["SM"])
			mvb.add_child(hb)
			hb.add_child(_flat_good_cell(str(m.get("good_id", "")), str(m.get("internal", "")), int(m.get("qty", 0)), 26))
			var nm := Label.new()
			nm.theme_type_variation = "Body"
			nm.text = str(m.get("name", ""))
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hb.add_child(nm)
			var st := Label.new()
			st.theme_type_variation = "Caption"
			if bool(m.get("secured", false)):
				st.text = "secured"
				st.add_theme_color_override("font_color", DS.PALETTE["OK"])
			else:
				var eta := int(m.get("eta", -1))
				st.text = ("arrives in %d turn%s" % [eta, "" if eta == 1 else "s"]) if eta >= 0 else "pending delivery"
				st.add_theme_color_override("font_color", DS.PALETTE["WARN"])
			hb.add_child(st)
		_body.add_child(mc)

	# Delivery blockers: a build material that needs a pipeline the site doesn't have will
	# never arrive and the build stalls forever. Surface it as a diagnostics card (same
	# DiagnosticsCard node the run-time view uses, so the tutorial coach can spotlight it).
	var cdiag: Array = BuildingReadout.construction_diagnostics(constr)
	if not cdiag.is_empty():
		_body.add_child(_make_section("Diagnostics", "delivery blocked"))
		_body.add_child(_build_diagnostics(cdiag))

	var cancel := Button.new()
	cancel.text = "Cancel construction"
	cancel.tooltip_text = "Before End Turn, also refunds and cancels reserved material orders. Dispatched materials remain yours."
	cancel.custom_minimum_size = Vector2(0, 44)
	var iid := str(building.get("instance_id", ""))
	cancel.pressed.connect(func() -> void:
		Construction.cancel(iid)
		hide())
	_body.add_child(cancel)

# --- battery / infrastructure strips (non-recipe) ------------------------------------------

func _build_storage_card(building: Dictionary) -> PanelContainer:
	var b := BuildingReadout.battery(building)
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = CREAM
	style.set_corner_radius_all(10)
	style.set_content_margin_all(14)
	card.add_theme_stylebox_override("panel", style)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	card.add_child(vb)
	var head := Label.new()
	head.add_theme_color_override("font_color", CREAM_INK)
	# The pair that shares a unit is power stabilised vs the tile's firming capacity — never
	# cells over MEGAWATTS, a count divided by a capacity.
	head.text = "Power stabilised — %d / %d MW" % [int(b.get("firming_cap", 0)), int(b.get("slots", 0))]
	vb.add_child(head)
	var note := Label.new()
	note.add_theme_color_override("font_color", CREAM_INK)
	note.text = "%d cell%s loaded — stores energy, runs no recipe" % [
		int(b.get("loaded", 0)), "" if int(b.get("loaded", 0)) == 1 else "s"]
	vb.add_child(note)
	return card

# Battery cell management: source cells from the tile stockpile, or order them from the market.
func _build_battery_actions(building: Dictionary, recipe: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DS.SP["SM"])
	var src := Button.new()
	src.text = "Load from stockpile"
	src.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	src.custom_minimum_size = Vector2(0, 40)
	src.pressed.connect(func() -> void: _open_battery_source_sheet(building, recipe))
	row.add_child(src)
	var ord := Button.new()
	ord.theme_type_variation = "Primary"
	ord.text = "Order from market"
	ord.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ord.custom_minimum_size = Vector2(0, 40)
	ord.pressed.connect(func() -> void: _open_battery_order_sheet(building, recipe))
	row.add_child(ord)
	return row

func _open_battery_source_sheet(building: Dictionary, recipe: Dictionary) -> void:
	var tile := str(building.get("tile_id", ""))
	_open_sheet("Load battery cells", func(vb: VBoxContainer) -> void:
		var b := BuildingReadout.battery(building)
		var head := Label.new()
		head.theme_type_variation = "Caption"
		head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		head.text = "%d / %d cells fitted. Load cells from this tile's stockpile into the housing — locked capital, refundable by unloading." % [int(b.get("loaded", 0)), int(b.get("slots", 0))]
		vb.add_child(head)
		for catalyst in recipe.get("catalysts", []) as Array:
			var internal := str(catalyst.get("internal_name", ""))
			var gid := str(Catalog.get_good_by_internal_name(str(internal)).get("id", ""))
			if gid == "":
				continue
			var unlocked := Power.battery_type_loadable(gid)
			var fill := Power.battery_cells_to_fill(tile, gid, str(building.get("instance_id", "")))
			var stock := Stockpile.get_at_tile(tile, gid)
			var loadable := mini(fill, stock)
			var subtitle := ""
			var btn_text := ""
			var enabled := false
			if not unlocked:
				subtitle = "Requires research: %s" % str(EconomyConfig.BATTERY_TYPE_UNLOCK[internal])
				btn_text = "Locked"
			elif fill <= 0:
				subtitle = "Housing full"
				btn_text = "Full"
			else:
				subtitle = "%d in stock · fits %d more" % [stock, fill]
				btn_text = "Load %d" % loadable
				enabled = loadable > 0
			vb.add_child(_battery_type_row(gid, str(internal), subtitle, btn_text, enabled, func() -> void:
				var n := Power.load_battery_cells(tile, gid, loadable)
				MatchState.request_toast(("Loaded %d %s cells" % [n, Catalog.get_display_name(gid)]) if n > 0 else "Nothing available to load", "success" if n > 0 else "warning")
				_queue_refresh()
				_open_battery_source_sheet(building, recipe))))

func _open_battery_order_sheet(building: Dictionary, recipe: Dictionary) -> void:
	var tile := str(building.get("tile_id", ""))
	_open_sheet("Order battery cells", func(vb: VBoxContainer) -> void:
		var head := Label.new()
		head.theme_type_variation = "Caption"
		head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		head.text = "Order cells from the market to fill the housing — paid now, installed after delivery."
		vb.add_child(head)
		for catalyst in recipe.get("catalysts", []) as Array:
			var internal := str(catalyst.get("internal_name", ""))
			var gid := str(Catalog.get_good_by_internal_name(str(internal)).get("id", ""))
			if gid == "":
				continue
			var unlocked := Power.battery_type_loadable(gid)
			var fill := Power.battery_cells_to_fill(tile, gid, str(building.get("instance_id", "")))
			var subtitle := ""
			var btn_text := ""
			var enabled := false
			if not unlocked:
				subtitle = "Requires research: %s" % str(EconomyConfig.BATTERY_TYPE_UNLOCK[internal])
				btn_text = "Locked"
			elif fill <= 0:
				subtitle = "Housing full"
				btn_text = "Full"
			else:
				var quote := TransportService.quote_market_buy(tile, gid, fill, TransportState.seaport_would_cover(gid))
				var cost := float(quote.get("cost", 0.0))
				subtitle = ("fills %d cells · £%.2f" % [fill, cost]) if not quote.is_empty() else "no market route to this tile"
				btn_text = "Order %d" % fill
				enabled = not quote.is_empty()
			vb.add_child(_battery_type_row(gid, str(internal), subtitle, btn_text, enabled, func() -> void:
				var r := Power.order_battery_fill_market(tile, gid, fill)
				if bool(r.get("ok", false)):
					var t := int(r.get("turns", 1))
					MatchState.request_toast("Ordered %d cells — £%.2f, arriving in %d turn%s" % [fill, float(r.get("cost", 0.0)), t, "" if t == 1 else "s"], "success")
					_close_sheet()
					_queue_refresh()
				else:
					MatchState.request_toast("Can't order — %s" % ("not enough funds" if str(r.get("reason", "")) == "funds" else "no market route"), "warning"))))

# A battery-chemistry row for the source/order sheets: framed icon · name · detail · action button.
func _battery_type_row(gid: String, internal: String, subtitle: String, btn_text: String, enabled: bool, on_press: Callable) -> Control:
	var card := _make_card()
	var cvb := card.get_child(0) as VBoxContainer
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", DS.SP["SM"])
	cvb.add_child(hb)
	var icon := UIHelpers.make_framed_good_icon(gid, internal, MARKET_ICON)
	icon.custom_minimum_size = Vector2(MARKET_ICON, MARKET_ICON)
	UIHelpers.link_good_icon_to_encyclopedia(icon, gid)
	hb.add_child(icon)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 0)
	hb.add_child(col)
	var nm := Label.new()
	nm.theme_type_variation = "Body"
	nm.text = Catalog.get_display_name(gid)
	col.add_child(nm)
	var sub := Label.new()
	sub.theme_type_variation = "Caption"
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.text = subtitle
	sub.add_theme_color_override("font_color", DS.PALETTE["TEXT_MUTED"])
	col.add_child(sub)
	var btn := Button.new()
	btn.text = btn_text
	btn.custom_minimum_size = Vector2(92, 36)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.disabled = not enabled
	if enabled:
		btn.pressed.connect(on_press)
	hb.add_child(btn)
	return card

func _build_infra_card() -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = CREAM
	style.set_corner_radius_all(10)
	style.set_content_margin_all(14)
	card.add_theme_stylebox_override("panel", style)
	var lbl := Label.new()
	lbl.add_theme_color_override("font_color", CREAM_INK)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.text = InfrastructureInfo.purpose(InfrastructureInfo.key_for(Catalog.get_building(str(_current_building.get("building_id", "")))))
	card.add_child(lbl)
	return card

func _build_infrastructure_details(building_data: Dictionary) -> PanelContainer:
	var card := _make_card()
	var vb := card.get_child(0) as VBoxContainer
	var key := InfrastructureInfo.key_for(building_data)
	if not InfrastructureInfo.has_level_stats(key):
		var none := Label.new()
		none.theme_type_variation = "Body"
		none.text = "Nothing yet."
		vb.add_child(none)
		return card
	var heading := Label.new()
	heading.theme_type_variation = "Caption"
	heading.text = "STATS"
	heading.add_theme_color_override("font_color", DS.PALETTE["TEXT_DIM"])
	vb.add_child(heading)
	for level in range(1, 4):
		vb.add_child(_infrastructure_level_accordion(key, level))
	return card

func _infrastructure_level_accordion(key: String, level: int) -> VBoxContainer:
	var box := VBoxContainer.new()
	var stats := InfrastructureInfo.level_stats(key, level)
	var header := Button.new()
	header.text = "Level %d   %s" % [level, "▾" if level == 1 else "▸"]
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.custom_minimum_size = Vector2(0, 30)
	box.add_child(header)
	var details := VBoxContainer.new()
	details.visible = level == 1
	details.add_theme_constant_override("separation", 3)
	box.add_child(details)
	for item in [[str(stats.get("capacity_label", "Transport soft cap")), str(stats.get("capacity", "—"))], ["Tiles covered in 1 turn", str(stats.get("tiles", "—"))], ["Cost per unit", str(stats.get("cost", "—"))]]:
		details.add_child(_metric(str(item[0]), str(item[1]), DS.PALETTE["TEXT"], false))
	header.pressed.connect(func() -> void:
		details.visible = not details.visible
		header.text = "Level %d   %s" % [level, "▾" if details.visible else "▸"])
	return box

## "Breakdown" table: goods that transited this tile's infra last turn, one row each —
## icon+qty cell (the same cream plain-icon-with-navy-pill every other good row on this
## panel uses), total transport cost, and the congestion-penalty share of that cost.
## Cables/hvdc carry power, not goods, and a quiet tile carries nothing at all — both
## just come back empty from MatchState.tile_good_breakdown(), so there's a single
## empty check here rather than a separate mode allow-list to keep in sync with it.
func _build_infra_breakdown(building: Dictionary, building_data: Dictionary) -> Control:
	var mode := InfrastructureInfo.key_for(building_data)
	var rows := TransportState.tile_good_breakdown(str(building.get("tile_id", "")), mode)
	if rows.is_empty():
		return null
	var card := _make_card()
	card.name = "InfraBreakdownCard"   # stable target for the dev screenshot harness
	var vb := card.get_child(0) as VBoxContainer
	vb.add_theme_constant_override("separation", DS.SP["SM"])
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", DS.SP["LG"])
	grid.add_theme_constant_override("v_separation", DS.SP["SM"])
	vb.add_child(grid)
	grid.add_child(Control.new())   # spacer over the icon column — it names itself
	grid.add_child(_breakdown_col_header("COST"))
	grid.add_child(_breakdown_col_header("PENALTIES"))
	for row_value in rows:
		var row: Dictionary = row_value
		var good_id := str(row.get("good_id", ""))
		var qty := int(row.get("qty", 0))
		var cost := float(row.get("cost", 0.0))
		var penalty := float(row.get("penalty", 0.0))
		grid.add_child(_good_icon_pill(good_id, Catalog.get_internal_name(good_id), qty, Metrics.GOOD_ICON))
		grid.add_child(_breakdown_value_label("£%.2f" % cost, DS.PALETTE["TEXT"]))
		var has_penalty := penalty > 0.01
		grid.add_child(_breakdown_value_label(("£%.2f" % penalty) if has_penalty else "—",
			DS.PALETTE["WARN"] if has_penalty else DS.PALETTE["TEXT_DIM"]))
	return card

func _breakdown_col_header(text: String) -> Label:
	var l := Label.new()
	l.theme_type_variation = "Caption"
	l.text = text
	l.add_theme_color_override("font_color", DS.PALETTE["TEXT_DIM"])
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l

func _breakdown_value_label(text: String, color: Color) -> Label:
	var l := Label.new()
	l.theme_type_variation = "Numeric"
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l

func _build_port_card(building: Dictionary) -> PanelContainer:
	var card := _make_card()
	card.name = "PortTermsCard"
	var vb := card.get_child(0) as VBoxContainer
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	vb.add_child(title_row)
	var gold_hex := Label.new()
	gold_hex.text = "⬡"
	gold_hex.add_theme_font_size_override("font_size", 34)
	gold_hex.add_theme_color_override("font_color", Color("c99832"))
	title_row.add_child(gold_hex)
	var head := Label.new()
	head.theme_type_variation = "BuildingName"
	head.add_theme_color_override("font_color", Color.WHITE)
	head.text = "Sea freight terminal"
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(head)
	var sub := Label.new()
	sub.add_theme_color_override("font_color", Color.WHITE)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.text = "Inputs arrive from, and outputs ship to, the world market through this port. Sea freight is booked under Transport."
	vb.add_child(sub)
	var tile := str(building.get("tile_id", ""))
	var sea := TransportState.seaport_shipping_summary(tile)
	var owned := bool(sea.get("owned", false))
	var growth := float(sea.get("growth", 1.0))
	var rate_pct := float(sea.get("insurance_rate", 0.0)) * 100.0 * growth
	# Three sections, ordered by what each is WORTH to the player rather than by what is
	# easiest to explain. What you are paying right now comes first, the goods
	# that actually moved this turn second, and the rate card — reference you read once — last.
	# Eleven metrics one separation apart read as a single undifferentiated wall; the air
	# between the sections is what does the separating, so the rows inside one stay tight.
	vb.add_theme_constant_override("separation", 5)

	_port_section(vb, "WHAT YOU PAY NOW", true)
	vb.add_child(_port_metric("Flat fee", "£%.2f per active good" % (float(sea.get("base_fee", 0.0)) * growth)))
	vb.add_child(_port_metric("Ad valorem", "%s%% of market buy value" % String.num(rate_pct, 4)))
	_add_port_throughput_rows(vb, true)
	if owned:
		vb.add_child(_port_metric("Owned-port upkeep", "£20.00 maintenance · about £15 labour / turn"))

	var rows: Array = sea.get("rows", [])
	_port_section(vb, "THIS TURN'S SEA FREIGHT" if bool(sea.get("is_current_turn", true)) else "MOST RECENT SEA FREIGHT", false)
	if rows.is_empty():
		var none := Label.new()
		none.add_theme_color_override("font_color", Color.WHITE)
		none.text = "No goods have shipped through this port yet."
		vb.add_child(none)
	else:
		var used_by_class: Dictionary = sea.get("usage", {})
		for row_value in rows:
			var row: Dictionary = row_value
			vb.add_child(_port_activity_row(row, used_by_class))

	_port_section(vb, "THE RATE CARD", false)
	if TransportState.keeps_introductory_port_rate():
		vb.add_child(_port_metric("Ad valorem · all turns", "0.5% of market buy value"))
	else:
		vb.add_child(_port_metric("Ad valorem · turns 1–30", "0.5% of market buy value"))
		vb.add_child(_port_metric("Ad valorem · turn 31 onward", "3% of market buy value"))
	vb.add_child(_port_metric("Annual drift", "+0.1% to the fee each turn"))
	_add_port_throughput_rows(vb, false)
	vb.add_child(_port_metric("At the throughput cap", "Sea fees double for that shipment"))
	vb.add_child(_port_metric("Owned port", "Ad valorem rate is halved; upkeep and labour apply"))
	return card


## A section heading with air above it — less for the one that opens the card, since the
## intro paragraph above it is already a break. The air IS the structure here: the rows
## inside a section sit five pixels apart, so without it eleven metrics read as one wall.
func _port_section(vb: VBoxContainer, title: String, first: bool) -> void:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, DS.SP["MD"] if first else DS.SP["LG"])
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(gap)
	var head := Label.new()
	head.theme_type_variation = "Caption"
	head.text = title
	head.add_theme_color_override("font_color", Color.WHITE)
	vb.add_child(head)

func _port_activity_row(row_data: Dictionary, used_by_class: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 62)
	row.add_theme_constant_override("separation", 10)
	var gid := str(row_data.get("good_id", ""))
	# 50px on the cream plate, the size a good icon is everywhere else in the UI.
	var icon := _flat_good_cell(gid, Catalog.get_internal_name(gid), int(row_data.get("total_qty", 0)), 50)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 0)
	var name := Label.new()
	name.text = Catalog.get_display_name(gid)
	name.add_theme_color_override("font_color", Color.WHITE)
	detail.add_child(name)
	var buy_qty := int(row_data.get("buy_qty", 0))
	var sell_qty := int(row_data.get("sell_qty", 0))
	var direction := Label.new()
	direction.add_theme_color_override("font_color", Color.WHITE)
	direction.add_theme_font_size_override("font_size", 12)
	direction.text = "Bought %d | Sold %d" % [buy_qty, sell_qty]
	detail.add_child(direction)
	row.add_child(detail)
	var cost := Label.new()
	cost.size_flags_horizontal = Control.SIZE_SHRINK_END
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cost.add_theme_color_override("font_color", Color.WHITE)
	cost.add_theme_font_size_override("font_size", 12)
	cost.tooltip_text = "Per-turn fee | ad valorem"
	cost.text = "£%.2f | £%.2f" % [float(row_data.get("base_fee", 0.0)), float(row_data.get("insurance_fee", 0.0))]
	var fees := VBoxContainer.new()
	fees.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fee_label := Label.new()
	fee_label.text = "Fee paid"
	fee_label.theme_type_variation = &"Caption"
	fee_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fees.add_child(fee_label)
	fees.add_child(cost)
	row.add_child(fees)
	var transport_class := str(row_data.get("transport_class", ""))
	var capacity := int(row_data.get("capacity", 0))
	var used := int(used_by_class.get(transport_class, 0))
	row.tooltip_text = "%d / %d %s" % [used, capacity, transport_class.replace("_", " ")]
	return row

func _port_metric(key: String, value: String) -> HBoxContainer:
	var row := _metric(key, value, Color.WHITE, false)
	var key_label := row.get_child(0) as Label
	if key_label != null:
		key_label.add_theme_color_override("font_color", Color.WHITE)
	var value_label := row.get_child(1) as Label
	if value_label != null:
		value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value_label.size_flags_stretch_ratio = 1.4
	return row

func _add_port_throughput_rows(vb: VBoxContainer, live: bool) -> void:
	for spec in [["solid_light", "Light solids"], ["solid_heavy", "Heavy solids"],
		["ultra_heavy", "Ultra-heavy solids"], ["safe_liquid", "Safe liquids"],
		["hazard_liquid", "Hazardous liquids"], ["gas", "Gases"]]:
		var kind: String = spec[0]
		var base: int = EconomyConfig.SEAPORT_THROUGHPUT_RESTRICTED if kind in EconomyConfig.SEAPORT_RESTRICTED_TRANSPORT_CLASSES else EconomyConfig.SEAPORT_THROUGHPUT_STANDARD
		var capacity: int = maxi(1, int(round(Modifiers.apply("port_throughput", "port", float(base), {"transport_class": kind})))) if live else base
		vb.add_child(_port_metric("Throughput: " + str(spec[1]), _fmt_int(capacity) + " units / turn"))

func sea_port_cap(good_id: String) -> int:
	return TransportState.seaport_throughput_cap(good_id)

# --- primary actions (upgrade · change recipe) ---------------------------------------------

func _build_primary_actions(building: Dictionary, _building_data: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DS.SP["SM"])
	var iid := str(building.get("instance_id", ""))
	var lvl := int(building.get("level", 1))
	# Infra levels live on the TILE (the instance copy can lag) — label from the truth.
	var b_internal := str(Catalog.get_building(str(building.get("building_id", ""))).get("internal_name", ""))
	if BuildingWorks.INFRA_UPGRADABLE.has(b_internal):
		lvl = BuildingWorks.infra_tile_level(building)

	var up := Button.new()
	up.name = "UpgradeButton"
	up.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	up.custom_minimum_size = Vector2(0, 40)
	var upgrade_progress := BuildingWorks.upgrade_progress_snapshot(iid)
	if not upgrade_progress.is_empty():
		up.text = "Upgrading…"
		up.disabled = true
		up.tooltip_text = str(upgrade_progress.get("tooltip", "Upgrade in progress."))
	elif lvl >= BuildingLevels.MAX_LEVEL:
		up.text = "Max level (L%d)" % lvl
		up.disabled = true
	else:
		up.theme_type_variation = "Primary"
		up.text = "Upgrade to Lv %d" % (lvl + 1)
	up.pressed.connect(func() -> void: _open_upgrade_sheet(building))
	row.add_child(up)

	var alt_count := maxi(0, Catalog.get_recipes_for_building(str(building.get("building_id", ""))).size() - 1)
	if alt_count > 0:
		var rc := Button.new()
		rc.name = "ChangeRecipeButton"   # stable target for the tutorial coach spotlight
		rc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rc.custom_minimum_size = Vector2(0, 40)
		if BuildingWorks.is_retooling(iid):
			var t := BuildingWorks.retrofit_turns_remaining(iid)
			rc.text = "Retooling — %d turn%s" % [t, "" if t == 1 else "s"]
		else:
			rc.text = "Change recipe (%d)" % alt_count
		rc.pressed.connect(func() -> void: _open_recipe_sheet(building))
		row.add_child(rc)
	return row

# In-panel upgrade action sheet — the upgrade_dialog.gd content (level stat deltas, material
# sourcing modes) rendered as one of the BDP's own sheets. Driven by MatchState.preview_upgrade /
# start_upgrade / cancel_upgrade.
## The material upgrade opens THE SHARED DIALOG (scripts/upgrade_dialog.gd). An in-sheet
## copy of the same screen drifts from the dialog as soon as either is improved. One screen,
## one implementation.
##
## The full-height action sheet stays for the CASH-ONLY INFRASTRUCTURE upgrade and for the
## already-upgrading countdown, which the dialog does not model; those are genuinely different
## screens rather than a second copy of this one. It is also why the upgrade "kept going" past
## its buttons: a sheet fills the panel by design, and a card sizes to its content.
func _open_upgrade_sheet(building: Dictionary) -> void:
	var iid := str(building.get("instance_id", ""))
	var preview: Dictionary = BuildingWorks.preview_upgrade(iid)
	# The DS2 panel also shows the top level and an upgrade under way, so only infrastructure's cash upgrade
	# keeps the sheet.
	var ds2 := UiPrefs.use_upgrade_ds2 and not bool(preview.get("infra", false))
	if bool(preview.get("ok", false)) and (ds2 or (not bool(preview.get("at_max", false)) \
			and not bool(preview.get("infra", false)) \
			and not bool(preview.get("already_upgrading", false)))):
		_ensure_upgrade_dialog()
		_upgrade_dialog.call("open", iid)
		return
	_open_sheet("Upgrade", func(vb: VBoxContainer) -> void:
		var pv := BuildingWorks.preview_upgrade(iid)
		if pv.is_empty() or not bool(pv.get("ok", false)):
			var msg := Label.new()
			msg.theme_type_variation = "Body"
			msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			msg.text = str(pv.get("reason", "This building can't be upgraded."))
			vb.add_child(msg)
			return
		var from_level := int(pv.get("from_level", 1))
		if bool(pv.get("at_max", false)):
			var m := Label.new()
			m.theme_type_variation = "Body"
			m.text = "Already at the maximum level (L%d)." % from_level
			vb.add_child(m)
			return
		var target := int(pv.get("target_level", from_level + 1))
		var duration := int(pv.get("duration", 3))
		var head := Label.new()
		head.theme_type_variation = "Caption"
		head.text = "Level %d  →  %d   ·   takes %d turn%s to upgrade" % [from_level, target, duration, "" if duration == 1 else "s"]
		vb.add_child(head)
		# Already upgrading → countdown + cancel only.
		if bool(pv.get("already_upgrading", false)):
			var left := int(pv.get("pending_turns_left", 0))
			var awaiting := str(pv.get("pending_status", "")) == BuildingWorks.UPGRADE_STATUS_AWAITING
			var progress := BuildingWorks.upgrade_progress_snapshot(iid)
			var note := Label.new()
			note.theme_type_variation = "Body"
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			if bool(progress.get("blocked", false)):
				note.add_theme_color_override("font_color", DS.PALETTE["DANGER"])
				note.text = "Upgrade paused. %s" % str(progress.get("error", "The required materials cannot be delivered."))
			else:
				note.add_theme_color_override("font_color", DS.PALETTE["OK"])
				note.text = str(progress.get("tooltip", ("Waiting on materials, then %d turn%s to upgrade." % [left, "" if left == 1 else "s"]) if awaiting else ("Upgrade in progress — %d turn%s left." % [left, "" if left == 1 else "s"])))
			vb.add_child(note)
			var is_infra_pending := bool(pv.get("infra", false))
			var cancel := Button.new()
			cancel.text = "Cancel upgrade"
			cancel.custom_minimum_size = Vector2(0, 40)
			cancel.pressed.connect(func() -> void:
				BuildingWorks.cancel_upgrade(iid)
				MatchState.request_toast("Upgrade cancelled — %s." % ("cash refunded" if is_infra_pending else "materials returned to the tile"), "caution")
				_close_sheet()
				_queue_refresh())
			vb.add_child(cancel)
			return
		# Levellable infrastructure: cash-only — capacity delta + one pay-and-go CTA.
		if bool(pv.get("infra", false)):
			var cap: Dictionary = pv.get("capacity", {})
			if not cap.is_empty():
				vb.add_child(_make_section("Capacity at level %d" % target))
				vb.add_child(_upgrade_delta_row("%s (%s)" % [str(cap.get("label", "Capacity")), str(cap.get("unit", ""))],
					float(cap.get("cur", 0.0)), float(cap.get("new", 0.0)), DS.PALETTE["OK"], 0, ""))
			var cost := float(pv.get("cash_cost", 0.0))
			var pay := Button.new()
			pay.custom_minimum_size = Vector2(0, 44)
			if bool(pv.get("affordable", false)):
				pay.theme_type_variation = "Primary"
				pay.text = "Upgrade to Lv %d — £%d" % [target, int(cost)]
			else:
				pay.text = "Upgrade to Lv %d — £%d (not enough money)" % [target, int(cost)]
				pay.disabled = true
			pay.pressed.connect(func() -> void:
				var res := BuildingWorks.start_upgrade(iid)
				if bool(res.get("ok", false)):
					MatchState.request_toast("Upgrade started — level %d in %d turns" % [target, duration], "success")
					_close_sheet()
					_queue_refresh()
				else:
					MatchState.request_toast(str(res.get("reason", "Upgrade failed.")), "error"))
			vb.add_child(pay)
			return
		# Materials
		var materials: Array = pv.get("materials", [])
		if not materials.is_empty():
			vb.add_child(_make_section("Materials"))
			var mrow := HBoxContainer.new()
			mrow.add_theme_constant_override("separation", DS.SP["MD"])
			for m in materials:
				mrow.add_child(_upgrade_material_cell(m))
			vb.add_child(mrow)
			if not bool(pv.get("all_on_tile", false)):
				var srcnote := Label.new()
				srcnote.theme_type_variation = "Caption"
				srcnote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				srcnote.add_theme_color_override("font_color", DS.PALETTE["TEXT_MUTED"])
				srcnote.text = "Some materials aren't on this tile — order them from market or transfer them in to begin."
				vb.add_child(srcnote)
		# Per-turn stat deltas at the new level
		vb.add_child(_make_section("Per turn at level %d" % target))
		var stats: Dictionary = pv.get("stats", {})
		var cur: Dictionary = stats.get("cur", {})
		var new_s: Dictionary = stats.get("new", {})
		var cur_out: Array = cur.get("outputs", [])
		var new_out: Array = new_s.get("outputs", [])
		for i in range(mini(cur_out.size(), new_out.size())):
			vb.add_child(_upgrade_delta_row("Output: %s" % str(cur_out[i].get("name", "")), float(cur_out[i].get("qty", 0)), float(new_out[i].get("qty", 0)), DS.PALETTE["OK"], 0, ""))
		var cur_in: Array = cur.get("inputs", [])
		var new_in: Array = new_s.get("inputs", [])
		for i in range(mini(cur_in.size(), new_in.size())):
			vb.add_child(_upgrade_delta_row("Input: %s" % str(cur_in[i].get("name", "")), float(cur_in[i].get("qty", 0)), float(new_in[i].get("qty", 0)), DS.PALETTE["WARN"], 0, ""))
		if float(cur.get("energy", 0)) > 0.0 or float(new_s.get("energy", 0)) > 0.0:
			vb.add_child(_upgrade_delta_row("Energy draw", float(cur.get("energy", 0)), float(new_s.get("energy", 0)), DS.PALETTE["DANGER"], 1, ""))
		vb.add_child(_upgrade_delta_row("Labour", float(cur.get("labour", 0.0)), float(new_s.get("labour", 0.0)), DS.PALETTE["DANGER"], 1, "£"))
		vb.add_child(_upgrade_delta_row("Maintenance", float(cur.get("maintenance", 0.0)), float(new_s.get("maintenance", 0.0)), DS.PALETTE["DANGER"], 1, "£"))
		var uc: Dictionary = pv.get("unit_cost", {})
		if uc.has("cur") and uc.has("new"):
			var cc := float(uc.get("cur", 0.0))
			var cn := float(uc.get("new", 0.0))
			vb.add_child(HSeparator.new())
			vb.add_child(_upgrade_delta_row("Cost / unit", cc, cn, DS.PALETTE["DANGER"] if cn > cc else DS.PALETTE["OK"], 2, "£"))
		# Blockers
		if bool(pv.get("research_locked", false)):
			# The tech name is a link into the Research tree — it is the most actionable thing
			# on this sheet, so it is not flat text the player has to go and find by hand.
			vb.add_child(UIHelpers.make_research_requirement_link(
				str(pv.get("research_gate", "")), DS.PALETTE["DANGER"]))
		if not bool(pv.get("fits", true)):
			var nf := Label.new()
			nf.theme_type_variation = "Body"
			nf.add_theme_color_override("font_color", DS.PALETTE["DANGER"])
			# The specific reason, with the numbers. The old generic line sat under a tile panel
			# reading "122 owned" and read as a bug rather than as a refusal with a cause.
			nf.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			nf.text = str(pv.get("fits_reason", "Not enough room on the tile for the larger building."))
			vb.add_child(nf)
		# Actions
		vb.add_child(HSeparator.new())
		var blocked := bool(pv.get("research_locked", false)) or not bool(pv.get("fits", true))
		if bool(pv.get("all_on_tile", false)):
			var go := Button.new()
			go.theme_type_variation = "Primary"
			go.text = "Upgrade (%d turn%s)" % [duration, "" if duration == 1 else "s"]
			go.custom_minimum_size = Vector2(0, 44)
			go.disabled = blocked
			go.pressed.connect(func() -> void: _commit_upgrade(iid, "tile", duration))
			vb.add_child(go)
		else:
			if bool(pv.get("market_sourceable", true)):
				var mk := Button.new()
				mk.theme_type_variation = "Primary"
				mk.text = "Order from market  (£%s)" % BuildingStatus._fmt_upto2(float(pv.get("market_cost", 0.0)))
				mk.custom_minimum_size = Vector2(0, 44)
				mk.disabled = blocked
				mk.pressed.connect(func() -> void: _commit_upgrade(iid, "market", duration))
				vb.add_child(mk)
			else:
				var nomk := Label.new()
				nomk.theme_type_variation = "Caption"
				nomk.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				nomk.add_theme_color_override("font_color", DS.PALETTE["DANGER"])
				nomk.text = "No market route for some materials."
				vb.add_child(nomk)
			var src := str(pv.get("source_tile", ""))
			if src != "":
				var tr := Button.new()
				tr.text = "Use spare stockpile from %s" % Catalog.tile_label(src)
				tr.custom_minimum_size = Vector2(0, 40)
				tr.disabled = blocked
				tr.pressed.connect(func() -> void: _commit_upgrade(iid, "transfer", duration))
				vb.add_child(tr))

func _commit_upgrade(iid: String, mode: String, duration: int) -> void:
	var res := BuildingWorks.start_upgrade(iid, mode)
	if bool(res.get("ok", false)):
		var awaiting := str(res.get("status", "")) == BuildingWorks.UPGRADE_STATUS_AWAITING
		MatchState.request_toast(("Upgrade queued — sourcing materials, then %d turns." % duration) if awaiting else ("Upgrade started — ready in %d turns." % duration), "success")
		_close_sheet()
		_queue_refresh()
	else:
		MatchState.request_toast(str(res.get("reason", "Cannot upgrade.")), "warning")

## Good-icon size on the upgrade sheet. Frameless: the metal bevel ate a 52 px cell and
## left the good barely readable.
const UPGRADE_MAT_ICON := Metrics.GOOD_ICON

# A material cell for the upgrade sheet: plain good icon (need pill) + have/need caption.
func _upgrade_material_cell(m: Dictionary) -> Control:
	var good_id := str(m.get("good_id", ""))
	var need := int(m.get("need", 0))
	var have := int(m.get("have", 0))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", DS.SP["XS"])
	col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_plain_icon_pill(good_id, Catalog.get_internal_name(good_id), need,
		UPGRADE_MAT_ICON))
	var hn := Label.new()
	hn.theme_type_variation = "Caption"
	hn.text = "%d/%d" % [mini(have, need), need]
	hn.add_theme_color_override("font_color", DS.PALETTE["OK"] if have >= need else DS.PALETTE["DANGER"])
	hn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hn)
	return col

# "Label   cur → new  (±N%)" delta row for the upgrade sheet.
func _upgrade_delta_row(label_text: String, cur: float, new_v: float, color: Color, decimals: int, prefix: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DS.SP["SM"])
	var k := Label.new()
	k.theme_type_variation = "Caption"
	k.text = label_text
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(k)
	var pct_txt := ""
	if cur > 0.0:
		var pct := int(round((new_v / cur - 1.0) * 100.0))
		if new_v > cur:
			pct_txt = "  (+%d%%)" % pct
		elif new_v < cur:
			pct_txt = "  (%d%%)" % pct
	elif new_v > 0.0:
		pct_txt = "  (new)"
	var v := Label.new()
	v.theme_type_variation = "Numeric"
	v.text = "%s%s → %s%s%s" % [prefix, _fmt_dec(cur, decimals), prefix, _fmt_dec(new_v, decimals), pct_txt]
	v.add_theme_color_override("font_color", color)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(v)
	return row

func _fmt_dec(v: float, decimals: int) -> String:
	return String.num(v, decimals) if decimals > 0 else str(int(round(v)))

# --- action-sheet framework (an in-panel overlay that covers the whole panel) --------------

## `extra_width` widens the WHOLE panel while this sheet is up (see _sheet_extra_width)
## — a sheet is a same-size overlay (PanelContainer manages every direct child to the
## SAME rect), so a sheet that needs more room than the panel's normal PANEL_WIDTH has
## no other way to get it than the panel itself growing.
## One reusable upgrade dialog on a high CanvasLayer, built once and hidden on close. Same
## arrangement the building ledger uses, so the screens share one dialog rather than each
## carrying their own.
func _ensure_upgrade_dialog() -> void:
	# The DS2 panel unless `toggle upgrade ds2` switched it back; a switch replaces the one built for the other.
	if _upgrade_dialog != null and is_instance_valid(_upgrade_dialog):
		if bool(_upgrade_dialog.get_meta("ds2", false)) == UiPrefs.use_upgrade_ds2:
			return
		_upgrade_dialog.queue_free()
		_upgrade_dialog = null
	if _upgrade_dialog_layer == null or not is_instance_valid(_upgrade_dialog_layer):
		_upgrade_dialog_layer = CanvasLayer.new()
		_upgrade_dialog_layer.layer = 128
		get_tree().root.add_child(_upgrade_dialog_layer)
	_upgrade_dialog = (load("res://scripts/ledger_v3/upgrade_dialog_ds2.gd" if UiPrefs.use_upgrade_ds2 else "res://scripts/upgrade_dialog.gd") as Script).new()
	_upgrade_dialog.set_meta("ds2", UiPrefs.use_upgrade_ds2)
	_upgrade_dialog_layer.add_child(_upgrade_dialog)
	_upgrade_dialog.connect("committed", func(_iid: String) -> void: _queue_refresh())


func _open_sheet(title: String, populate: Callable, extra_width: float = 0.0) -> void:
	var restore_scroll := 0
	var preserve_scroll := false
	if _sheet != null and is_instance_valid(_sheet):
		var old_title := _sheet.find_child("SheetTitle", true, false) as Label
		var old_scroll := _sheet.find_child("ActionSheetScroll", true, false) as ScrollContainer
		if old_title != null and old_scroll != null and old_title.text == title:
			restore_scroll = old_scroll.scroll_vertical
			preserve_scroll = true
	_close_sheet()
	_sheet_extra_width = extra_width
	if extra_width > 0.0:
		_size_and_position()
	var sheet := PanelContainer.new()
	sheet.name = "ActionSheet"
	var st := StyleBoxFlat.new()
	st.bg_color = DS.PALETTE["BG_PANEL"]
	st.set_corner_radius_all(10)
	st.set_content_margin_all(0)
	sheet.add_theme_stylebox_override("panel", st)
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	var margin := MarginContainer.new()
	margin.name = "SheetMargin"
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, DS.SP["MD"])
	var slide: Control = null
	if UiPrefs.use_bdp_v3:
		slide = _v3_sheet_plate(sheet, margin)
	else:
		sheet.add_child(margin)
	var vb := VBoxContainer.new()
	vb.name = "SheetVBox"
	vb.add_theme_constant_override("separation", DS.SP["SM"])
	margin.add_child(vb)
	var header := HBoxContainer.new()
	header.name = "SheetHeader"
	header.add_theme_constant_override("separation", DS.SP["SM"])
	vb.add_child(header)
	if UiPrefs.use_bdp_v3:
		var back_key := BdpV3Key.make("back")
		back_key.pressed.connect(_close_sheet)
		header.add_child(back_key)
	else:
		var back := Button.new()
		back.text = "‹"
		back.custom_minimum_size = Vector2(36, 32)
		back.pressed.connect(_close_sheet)
		header.add_child(back)
	var tl := Label.new()
	tl.name = "SheetTitle"
	tl.theme_type_variation = "BuildingName"
	tl.text = title
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(tl)
	vb.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.name = "ActionSheetScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	if UiPrefs.use_bdp_v3:
		BdpV3Scroll.apply(scroll, true)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", DS.SP["SM"])
	scroll.add_child(body)
	populate.call(body)
	add_child(sheet)  # stacks over the panel's content (later child draws on top)
	_sheet = sheet
	if preserve_scroll:
		scroll.set_deferred("scroll_vertical", restore_scroll)
	if slide != null:
		move_child(_shade, get_child_count() - 1)   # the plate is under the lamp too
		_apply_v3_text_light()
		if not preserve_scroll:   # a sheet rebuilt in place stays put
			slide.position.x = size.x
			slide.create_tween().tween_property(slide, "position:x", 0.0, V3_SHEET_SLIDE_SECONDS) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## v3: an action sheet is a worn steel plate that slides in from the right over the panel's body, inside
## the brass trim. The sheet itself still covers the whole panel (and takes its clicks); inside it, a
## clip the trim's size holds a sliding layer with the plate and the sheet's content on it. Returns the
## sliding layer.
const V3_SHEET_INSET := (4.0 + BACKING_TRIM) / 1.875
const V3_SHEET_PAD := 14
const V3_SHEET_SLIDE_SECONDS := 0.26
## From layout.json (sheet_plate), in layout pixels: the render's room round the plate, and its corner.
const V3_SHEET_PLATE_MARGIN := 10.0
const V3_SHEET_PLATE_CORNER := 60.0

func _v3_sheet_plate(sheet: PanelContainer, margin: MarginContainer) -> Control:
	var bare := StyleBoxEmpty.new()
	bare.set_content_margin_all(0)
	sheet.add_theme_stylebox_override("panel", bare)
	var clip := Control.new()
	clip.name = "SheetClip"
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.add_child(clip)
	var slide := Control.new()
	slide.name = "SheetSlide"
	slide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slide.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip.add_child(slide)
	var plate := BdpV3Nine.make("sheet_plate", (V3_SHEET_PLATE_MARGIN + V3_SHEET_PLATE_CORNER) * 2.0 / 1.875, V3_SHEET_PLATE_MARGIN / 1.875)
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slide.add_child(plate)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, V3_SHEET_PAD)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slide.add_child(margin)
	# The clip sits inside the trim; the sheet (a container) sizes it, so its offsets are set once the
	# sheet is laid out.
	sheet.resized.connect(func() -> void:
		clip.position = Vector2(V3_SHEET_INSET, V3_SHEET_INSET)
		clip.size = sheet.size - 2.0 * Vector2(V3_SHEET_INSET, V3_SHEET_INSET))
	return slide

func _close_sheet() -> void:
	if _sheet != null and is_instance_valid(_sheet):
		remove_child(_sheet)  # Release its minimum width before resizing the panel.
		_sheet.queue_free()
	_sheet = null
	if _sheet_extra_width > 0.0:
		_sheet_extra_width = 0.0
		_size_and_position()

# --- change-recipe sheet -------------------------------------------------------------------

func _open_recipe_sheet(building: Dictionary) -> void:
	var iid := str(building.get("instance_id", ""))
	var building_id := str(building.get("building_id", ""))
	var current := str(building.get("recipe_id", ""))
	var populate := func(vb: VBoxContainer) -> void:
		if BuildingWorks.is_retooling(iid):
			var t := BuildingWorks.retrofit_turns_remaining(iid)
			var note := Label.new()
			note.theme_type_variation = "Body"
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			note.text = "Retooling in progress — %d turn%s left. The building produces nothing until it completes." % [t, "" if t == 1 else "s"]
			vb.add_child(note)
			var cancel := Button.new()
			cancel.text = "Cancel retooling"
			cancel.custom_minimum_size = Vector2(0, 40)
			cancel.pressed.connect(func() -> void:
				BuildingWorks.cancel_retrofit(iid)
				_close_sheet()
				_queue_refresh())
			vb.add_child(cancel)
			return
		var tier := BuildingWorks.retrofit_cost_tier()
		var info := Label.new()
		info.theme_type_variation = "Caption"
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.text = "A one-off fee of £%d, then %d turn%s of retooling (at %d%% labour) — the building produces nothing until it completes. Modifiers and level are kept." % [
			int(tier.get("fee", 0.0)), int(tier.get("turns", 2)), "" if int(tier.get("turns", 2)) == 1 else "s", int(round(float(tier.get("labour", 0.5)) * 100.0))]
		vb.add_child(info)
		for r in Catalog.get_recipes_for_building(building_id):
			vb.add_child(_recipe_choice_row(iid, r, str(r.get("recipe_id", "")) == current))
	# +100 (460 -> 560) matches the Construct panel's own width exactly — the mini
	# diagram bars were sized for that panel, so reusing its width, not inventing
	# a third figure, is what makes them "the same width bar" here too.
	_open_sheet("Change recipe", populate, 100.0)

func _recipe_choice_row(iid: String, recipe: Dictionary, is_current: bool) -> Control:
	var card := PanelContainer.new()
	card.name = "RecipeChoice_%s" % str(recipe.get("recipe_id", ""))   # tutorial coach spotlight

	var st := StyleBoxFlat.new()
	st.bg_color = DS.PALETTE["BG_HIGHLIGHT"] if is_current else DS.PALETTE["BG_CARD"]
	st.border_color = DS.PALETTE["ACCENT"] if is_current else DS.PALETTE["BORDER_SOFT"]
	st.set_border_width_all(1)
	st.set_corner_radius_all(8)
	st.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", st)
	if not is_current:
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				_apply_retrofit(iid, recipe))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	card.add_child(vb)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", DS.SP["SM"])
	vb.add_child(head)
	var out_internal := str(recipe.get("output_name", ""))
	var out_disp := BuildingStatus.good_display_from_internal(out_internal)
	var name := Label.new()
	name.theme_type_variation = "Body"
	name.text = str(recipe.get("display_name", "Make %s" % out_disp))
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name)
	if is_current:
		var cur := Label.new()
		cur.theme_type_variation = "Caption"
		cur.text = "current"
		cur.add_theme_color_override("font_color", DS.PALETTE["OK"])
		head.add_child(cur)
	# The same compressed look the Construct panel's own recipe cards use — icons,
	# "+", a filled navy arrow — instead of a text summary (UIHelpers.mini_recipe_diagram,
	# shared between both panels so they can't drift into two different looks).
	var diagram := UIHelpers.mini_recipe_diagram(recipe)
	diagram.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(diagram)
	return card

func _apply_retrofit(iid: String, recipe: Dictionary) -> void:
	var res := BuildingWorks.start_retrofit(iid, str(recipe.get("recipe_id", "")))
	if not bool(res.get("ok", false)):
		MatchState.request_toast(str(res.get("reason", "Could not retool.")), "warning")
	else:
		MatchState.request_toast("Retooling to %s" % str(recipe.get("display_name", "new recipe")), "success")
	_close_sheet()
	_queue_refresh()

# --- sell / demolish -----------------------------------------------------------------------

# --- Building Detail v3 (`toggle bdp v3`): the main controls on worn steel plates ----------------

func _on_bdp_v3_changed(_enabled: bool) -> void:
	_apply_v3_chrome()
	_close_sheet()
	_queue_refresh()


## The parts of the shell that v3 swaps: the title, the close and Location keys, the status lamp (in
## place of the level and location line), the backing, the scrollbar, the seam edge and the lamp over
## the panel.
func _apply_v3_chrome() -> void:
	var v3 := UiPrefs.use_bdp_v3
	_close_button.visible = not v3
	_close_key.visible = v3
	_pin_key.visible = v3
	_shade.visible = v3
	_apply_v3_title()
	_apply_v3_text_light()
	_badge.visible = not v3
	_status_v3.visible = v3
	# v3 drops the level and location line: the Location key carries the place.
	_subtitle_label.visible = not v3
	_pipe_frame.visible = not v3
	_backing.visible = v3
	BdpV3Scroll.apply(_scroll, v3)
	_seam.visible = v3
	_scroll.offset_top = BdpV3Seam.strip_height() if v3 else 0.0


## The Location key: the map pans to the building (and the tile's panel opens), or, for a building site
## not yet on the books, to its tile.
func _on_pin_pressed() -> void:
	var iid := str(_current_building.get("instance_id", ""))
	if iid != "" and not BuildingState.get_building(iid).is_empty():
		MatchState.focus_building_requested.emit(iid)
		return
	var cam := get_viewport().get_camera_2d()
	if cam != null and cam.has_method("pan_to_tile"):
		cam.pan_to_tile(str(_current_building.get("tile_id", "")))


## Under v3's lamp, the panel's text takes back part of the darkening round it (bdp_v3_light.gd), the
## action sheets' too (their plates sit under the lamp). Runs after every rebuild and sheet.
func _apply_v3_text_light() -> void:
	var m: Material = BdpV3Light.text_material() if UiPrefs.use_bdp_v3 else null
	var roots: Array[Node] = [_margin]
	if _sheet != null and is_instance_valid(_sheet):
		roots.append(_sheet)
	for root in roots:
		for n in root.find_children("*", "Label", true, false) + root.find_children("*", "RichTextLabel", true, false):
			(n as CanvasItem).material = m


## v3's raised title in place of the label, unless the title has a character its letters lack.
func _apply_v3_title() -> void:
	var raised := UiPrefs.use_bdp_v3 and BdpV3Title.can_show(_title_label.text)
	_title_v3.visible = raised
	_title_label.visible = not raised


## Moves each framed section (its heading and everything up to the next heading) into a steel
## frame. Runs after a v3 rebuild; the footer and anything above the first framed heading stay put.
func _v3_frame_sections() -> void:
	var frame: Control = null
	var frame_name := ""
	for child in _body.get_children():
		if child.has_meta("v3_section_end"):
			frame = null
			continue
		var heading := str(child.get_meta("v3_section", ""))
		if V3_FRAMED_SECTIONS.has(heading) and (frame == null or V3_FRAMED_SECTIONS[heading] != frame_name):
			frame = BdpV3Section.new()
			frame_name = V3_FRAMED_SECTIONS[heading]
			_body.add_child(frame)
			_body.move_child(frame, child.get_index())
		if frame != null:
			_body.remove_child(child)
			frame.content.add_child(child)
			if frame_name == "diagnostics":
				frame.style = "plastic"
			elif frame_name in ["cost", "shipments"]:
				frame.style = "dark"
	# The diagnostics' plate is dark plastic, their text white and embossed on it.
	for f in _body.get_children():
		if f is BdpV3Section and f.style == "plastic":
			for l in f.find_children("*", "Label", true, false):
				_v3_emboss(l)


## White lettering that stands up off dark plastic: a dark shadow down and to the right.
func _v3_emboss(l: Label) -> void:
	l.add_theme_color_override("font_color", DS.PALETTE["TEXT"])
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)


## Inputs, Outputs, Upgrade and Change recipes as one control plate. The values are the ones the
## v2 cards and buttons show; the keys open the same sheets.
func _build_v3_block(building: Dictionary, recipe: Dictionary) -> Control:
	var service = preload("res://scripts/middleman_service.gd")
	var iid := str(building.get("instance_id", ""))
	var building_id := str(building.get("building_id", ""))
	var manage_unlocked: bool = service.eligible(building) and ResearchState.open_logistics_contracts_available()
	var state := {
		"input_value": _input_summary(building, recipe),
		"output_value": _output_summary(building, recipe),
		"input_managed": manage_unlocked and service.side_all_middleman(iid, "input"),
		"output_managed": manage_unlocked and service.side_all_middleman(iid, "output"),
	}
	state.merge(v3_upgrade_state(building))
	var alt_count := maxi(0, Catalog.get_recipes_for_building(building_id).size() - 1)
	if BuildingWorks.is_retooling(iid):
		var t := BuildingWorks.retrofit_turns_remaining(iid)
		state["recipe_title"] = "Retooling — %d turn%s" % [t, "" if t == 1 else "s"]
		state["recipe_detail"] = ""
		state["recipe_enabled"] = true
	else:
		state["recipe_title"] = "Change recipes (%d)" % alt_count
		state["recipe_detail"] = "%d better for %s" % [BdpV3Block.better_recipe_count(building),
			BdpV3Block.truncate10(BdpV3Block.main_output_name(recipe))] if alt_count > 0 else "No other recipes"
		state["recipe_enabled"] = alt_count > 0
	var block: Control = BdpV3Block.new()
	block.configure(state)
	block.key_pressed.connect(_on_v3_key.bind(building, recipe))
	return block


func _on_v3_key(key: String, building: Dictionary, recipe: Dictionary) -> void:
	match key:
		"inputs": _open_input_sources_sheet(building, recipe)
		"outputs": _open_output_sheet(building, recipe)
		"upgrade": _open_upgrade_sheet(building)
		"recipe": _open_recipe_sheet(building)


## The Upgrade key: its two lines, whether the arrow is lit (the upgrade can start: not already
## upgrading, not at the top level, its research unlocked) and, when it is not, why; and its hover card
## (v3_upgrade_tip), the dot-matrix card the tile view's Upgrade keys show.
static func v3_upgrade_state(building: Dictionary) -> Dictionary:
	var iid := str(building.get("instance_id", ""))
	var level := int(building.get("level", 1))
	var tip := v3_upgrade_tip(building)
	var progress := BuildingWorks.upgrade_progress_snapshot(iid)
	if not progress.is_empty():
		return {"upgrade_title": "Upgrading…", "upgrade_detail": "", "upgrade_lit": false,
			"upgrade_tooltip": str(progress.get("tooltip", "Upgrade in progress.")), "upgrade_tip": tip}
	if level >= BuildingLevels.MAX_LEVEL:
		return {"upgrade_title": "Max level (L%d)" % level, "upgrade_detail": "", "upgrade_lit": false,
			"upgrade_tooltip": "Already at the maximum level.", "upgrade_tip": tip}
	var internal := str(Catalog.get_building(str(building.get("building_id", ""))).get("internal_name", ""))
	var gate := BuildingLevels.research_gate(internal, level + 1)
	var met := gate == "" or ResearchState.is_unlocked(gate)
	return {"upgrade_title": "Upgrade to Lv %d" % (level + 1), "upgrade_detail": BdpV3Block.upgrade_detail(level),
		"upgrade_lit": met, "upgrade_tooltip": "" if met else "Requires research: %s" % gate, "upgrade_tip": tip}


## The Upgrade key's hover card (scripts/ds2/dot_card.gd), from BuildingWorks.preview_upgrade: the
## next level's output gain, what buying the missing materials costs, the land it adds and the time it
## takes, with the materials in their wells; the turns left while it runs; the top level; why it can't run.
static func v3_upgrade_tip(building: Dictionary) -> Dictionary:
	var iid := str(building.get("instance_id", ""))
	var level := int(building.get("level", 1))
	var q: Dictionary = BuildingWorks.preview_upgrade(iid) if iid != "" else {}
	if not bool(q.get("ok", false)):
		return {}
	if bool(q.get("at_max", false)):
		return {"title": "Top level", "rows": [{"caption": "Level", "value": "%d of %d" % [level, BuildingLevels.MAX_LEVEL]}]}
	var target := int(q.get("target_level", level + 1))
	var turns := func(n: int) -> String: return "%d turn%s" % [n, "" if n == 1 else "s"]
	if bool(q.get("already_upgrading", false)):
		var waiting := str(q.get("pending_status", "")) == Construction.STATUS_AWAITING_MATERIALS
		var card := {"title": "Upgrading to level %d" % target, "tone": "warn", "rows": []}
		if waiting:
			card.notes = [{"text": "Waiting for materials", "tone": "warn"}]
		else:
			card.rows.append({"caption": "Ready in", "value": turns.call(int(q.get("pending_turns_left", 0)))})
		return card
	# What the next level brings: each output's quantity a turn and a unit's cost, now and then.
	var rows: Array = []
	var stats: Dictionary = q.get("stats", {})
	var cur_out: Array = (stats.get("cur", {}) as Dictionary).get("outputs", [])
	var new_out: Array = (stats.get("new", {}) as Dictionary).get("outputs", [])
	for i in mini(cur_out.size(), new_out.size()):
		var unit := " MW" if str(cur_out[i].get("good_id", "")) == "power" else "/turn"
		rows.append({"caption": str(cur_out[i].get("name", "Output")), "value": "%d → %d%s" % [
			int(cur_out[i].get("qty", 0)), int(new_out[i].get("qty", 0)), unit], "tone": "ok"})
	if rows.is_empty():
		var gain := BdpV3Block.upgrade_detail(level)
		if gain != "":
			rows.append({"caption": "Output", "value": gain.trim_suffix(" Output"), "tone": "ok"})
	var uc: Dictionary = q.get("unit_cost", {})
	if uc.has("cur") and uc.has("new"):
		var cheaper := float(uc.new) <= float(uc.cur)
		rows.append({"caption": "Unit cost", "value": "£%.2f → £%.2f" % [float(uc.cur), float(uc.new)], "tone": "ok" if cheaper else "bad"})
	var buy := float(q.get("market_cost", 0.0))
	if buy > 0.005:
		rows.append({"caption": "Cost", "value": "£%.2f" % buy, "tone": "" if MatchState.money >= buy else "bad"})
	if float(q.get("size_delta", 0.0)) > 0.0:
		rows.append({"caption": "Land", "value": "+%d" % roundi(float(q.get("size_delta", 0.0)))})
	rows.append({"caption": "Time", "value": turns.call(int(q.get("duration", 0)))})
	var card := {"title": "Upgrade to level %d" % target, "rows": rows, "notes": []}
	var goods := {}
	for m: Dictionary in q.get("materials", []):
		goods[str(m.get("good_id", ""))] = int(m.get("need", 0))
	if not goods.is_empty():
		card.goods = goods
		card.goods_caption = "Needs"
		card.goods_note = "On site" if bool(q.get("all_on_tile", false)) else ("Bought in" if bool(q.get("market_sourceable", true)) else "")
	if bool(q.get("research_locked", false)):
		var gate := str(q.get("research_gate", ""))
		var title := ResearchState.research_title_for_node_id(gate)
		card.tone = "bad"
		card.notes.append({"text": "Needs research: %s" % (title if title != "" else gate), "tone": "bad"})
	if not bool(q.get("fits", true)):
		card.tone = "bad"
		card.notes.append({"text": str(q.get("fits_reason", "Not enough room")).trim_suffix("."), "tone": "bad"})
	if not bool(q.get("market_sourceable", true)):
		card.tone = "bad"
		card.notes.append({"text": "Materials can't reach this tile", "tone": "bad"})
	return card


func _build_v3_footer(building: Dictionary) -> Control:
	var footer: Control = BdpV3Footer.new()
	footer.key_pressed.connect(func(key: String) -> void: _open_supply_chain(building, key))
	# While a cover is lifted, a steel plate slides up from behind the footer with what pressing the
	# button would do; it slides back when the cover drops or the button is pressed.
	var clip := Control.new()
	clip.name = "FooterSlideout"
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.visible = false
	footer.add_child(clip)
	footer.move_child(clip, 0)   # under the footer's covers, which stand in front of it
	var outs := {"sell": _v3_sell_outcome(building), "demolish": _v3_demolish_outcome(building)}
	for key in outs:
		# Laid out all along (a hidden container measures nothing), and parked below the strip until needed.
		clip.add_child(outs[key])
	footer.cover_changed.connect(func(key: String, open: bool) -> void:
		if outs.has(key):
			_v3_slide_outcome(footer, clip, outs[key], open))
	return footer

## How far in from the footer's sides the outcome plate sits, how long it takes to slide, the refund's
## icons and how many to a row.
const V3_OUTCOME_INSET := 18.0
const V3_OUTCOME_SECONDS := 0.22
const V3_REFUND_ICON := Metrics.GOOD_ICON
const V3_REFUND_COLUMNS := 5
const V3_SHEET_TEXTURE: Texture2D = preload("res://assets/ui/bdp_v3/sheet_plate.png")

## Slides `plate` up out of the footer (or back down behind it) inside `clip`, the strip above the footer
## as tall as the plate; any other plate in it is parked below.
func _v3_slide_outcome(footer: Control, clip: Control, plate: Control, open: bool) -> void:
	var h := plate.get_combined_minimum_size().y
	if open:
		clip.position = Vector2(V3_OUTCOME_INSET, -h)
		clip.size = Vector2(footer.size.x - 2.0 * V3_OUTCOME_INSET, h)
		for other: Control in clip.get_children():
			other.size = Vector2(clip.size.x, other.get_combined_minimum_size().y)
			other.position = Vector2(0.0, clip.size.y + 8.0)
		clip.visible = true
	var tween := plate.create_tween()
	tween.tween_property(plate, "position:y", 0.0 if open else clip.size.y + 8.0, V3_OUTCOME_SECONDS) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if not open:
		tween.tween_callback(func() -> void:
			clip.visible = clip.get_children().any(func(c: Control) -> bool: return c.position.y < 1.0))

## A steel outcome plate (the action sheets' plate) with rows on it.
func _v3_outcome_plate(node_name: String) -> Array:
	var plate := PanelContainer.new()
	plate.name = node_name
	plate.mouse_filter = Control.MOUSE_FILTER_PASS
	plate.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var pad := StyleBoxEmpty.new()
	pad.set_content_margin_all(V3_SHEET_PAD)
	plate.add_theme_stylebox_override("panel", pad)
	plate.draw.connect(func() -> void:
		BdpV3Nine.paint(plate, V3_SHEET_TEXTURE, Rect2(Vector2.ZERO, plate.size).grow(V3_SHEET_PLATE_MARGIN / 1.875),
			(V3_SHEET_PLATE_MARGIN + V3_SHEET_PLATE_CORNER) * 2.0 / 1.875))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", DS.SP["SM"])
	plate.add_child(vb)
	return [plate, vb]

## What selling does: the building goes to an NPC operator, and the company is paid for it.
func _v3_sell_outcome(building: Dictionary) -> Control:
	var made := _v3_outcome_plate("SellOutcome")
	var vb: VBoxContainer = made[1]
	vb.add_child(_v3_outcome_line("Building will become NPC"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DS.SP["SM"])
	var paid := _v3_outcome_line("You will receive")
	paid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(paid)
	row.add_child(_v3_money_led(float(BuildingPrice.sale_price(building)), DS.PALETTE["OK"]))
	vb.add_child(row)
	return made[0]

## What demolishing does: the building's land comes free, and part of its construction kit comes back.
func _v3_demolish_outcome(building: Dictionary) -> Control:
	var made := _v3_outcome_plate("DemolishOutcome")
	var vb: VBoxContainer = made[1]
	vb.add_child(_v3_outcome_line("%s land will be freed up" % BuildingWorks.land_text(BuildingState.space_used(building))))
	var materials: Dictionary = BuildingWorks.refund_cost(str(building.get("instance_id", ""))).get("materials", {})
	vb.add_child(_v3_outcome_line("Refund:" if not materials.is_empty() else "Refund: nothing"))
	if not materials.is_empty():
		var goods := GridContainer.new()
		goods.name = "RefundGoods"
		goods.columns = V3_REFUND_COLUMNS
		goods.add_theme_constant_override("h_separation", DS.SP["MD"])
		goods.add_theme_constant_override("v_separation", DS.SP["MD"])
		vb.add_child(goods)
		for gid in materials:
			var icon := _good_icon_pill(str(gid), Catalog.get_internal_name(str(gid)), int(materials[gid]), V3_REFUND_ICON, -1, 0, true)
			_v3_set_in_well(icon)
			goods.add_child(icon)
	return made[0]

## A line of an outcome plate: white, standing off the steel.
func _v3_outcome_line(text: String) -> Label:
	var l := Label.new()
	l.theme_type_variation = "Body"
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	_v3_emboss(l)
	return l


func _build_sell_demolish_row(building: Dictionary, building_data: Dictionary) -> Control:
	var iid := str(building.get("instance_id", ""))
	if BuildingWorks.is_demolishing(iid):
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", DS.SP["SM"])
		var t := BuildingWorks.demolish_turns_remaining(iid)
		var note := Label.new()
		note.theme_type_variation = "Body"
		note.add_theme_color_override("font_color", DS.PALETTE["DANGER"])
		note.text = "Demolishing — %d turn%s left" % [t, "" if t == 1 else "s"]
		col.add_child(note)
		var cancel := Button.new()
		cancel.text = "Cancel demolition"
		cancel.custom_minimum_size = Vector2(0, 40)
		cancel.pressed.connect(func() -> void:
			BuildingWorks.cancel_demolish(iid)
			_queue_refresh())
		col.add_child(cancel)
		return col
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DS.SP["SM"])
	var sell := Button.new()
	sell.text = "Sell building"
	sell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell.custom_minimum_size = Vector2(0, 40)
	sell.pressed.connect(func() -> void: _open_supply_chain(building, "sell"))
	row.add_child(sell)
	var demo := Button.new()
	demo.text = "Demolish"
	demo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	demo.custom_minimum_size = Vector2(0, 40)
	demo.pressed.connect(func() -> void: _open_supply_chain(building, "demolish"))
	row.add_child(demo)
	return row

# Sell/demolish route through the supply-chain review panel: the player decides what
# happens to feeding/dependent buildings (auto-fulfill vs pause) before it commits.
func _open_supply_chain(building: Dictionary, action: String) -> void:
	var iid := str(building.get("instance_id", ""))
	if iid == "":
		return
	var layer := CanvasLayer.new()
	layer.layer = 130
	get_tree().root.add_child(layer)
	var panel: Control = load("res://scripts/supply_chain_panel.gd").new()
	layer.add_child(panel)
	panel.finished.connect(func(_confirmed: bool) -> void:
		layer.queue_free()
		_queue_refresh())
	panel.open(iid, action)

func _sheet_apply(text: String, danger: bool, on_press: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 46)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if danger:
		var c: Color = DS.PALETTE["DANGER"]
		for state in ["normal", "hover", "pressed"]:
			var sb := StyleBoxFlat.new()
			var a := 0.7
			if state == "hover":
				a = 0.82
			elif state == "pressed":
				a = 0.95
			sb.bg_color = Color(c.r, c.g, c.b, a)
			sb.set_corner_radius_all(8)
			sb.set_content_margin_all(8)
			btn.add_theme_stylebox_override(state, sb)
		btn.add_theme_color_override("font_color", Color.WHITE)
	else:
		btn.theme_type_variation = "Primary"
	btn.pressed.connect(on_press)
	return btn

# --- recipe strip (frameless icons, independent input & output grids) ----------------------

# Navy right-pointing arrowhead (drawn) — the head of the recipe arrow.
class _ArrowHead extends Control:
	var col := Color(0.0, 0.119856, 0.243095)
	func _ready() -> void:
		resized.connect(queue_redraw)
	func _draw() -> void:
		var pts := PackedVector2Array([Vector2(0, 0), Vector2(size.x, size.y * 0.5), Vector2(0, size.y)])
		draw_colored_polygon(pts, col)
		# A filled polygon has hard, stepped edges; a thin smoothed line round it softens them.
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, col, 1.0, true)

# A thin navy outline rectangle inset from the card edge (the recipe card's inner border).
class _InsetOutline extends Control:
	var col := Color(0.0, 0.119856, 0.243095)
	var inset := 4.0
	func _ready() -> void:
		resized.connect(queue_redraw)
	func _draw() -> void:
		draw_rect(Rect2(inset, inset, size.x - inset * 2.0, size.y - inset * 2.0), col, false, 1.5)

# Compact route glyph used by the input/output selector cards. The hex outline gives
# stockpile routes a tile identity; the second outline marks a stockpile on another tile.
class _RouteIcon extends Control:
	var kind := "stockpile"
	var active := false
	var accent := Color(0.78, 0.64, 0.30)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _hex_points(center: Vector2, radius: float) -> PackedVector2Array:
		var points := PackedVector2Array()
		for i in 6:
			var angle := -PI * 0.5 + float(i) * TAU / 6.0
			points.append(center + Vector2(cos(angle), sin(angle)) * radius)
		return points

	func _closed(points: PackedVector2Array) -> PackedVector2Array:
		var closed := points.duplicate()
		if not points.is_empty():
			closed.append(points[0])
		return closed

	func _texture_for_kind() -> Texture2D:
		if kind == "market": return ROUTE_MARKET_ICON
		if kind == "middleman": return ROUTE_MIDDLEMAN_ICON
		return ROUTE_STOCKPILE_ICON

	func _draw() -> void:
		var ink := accent if active else Color(0.56, 0.61, 0.63, 0.92)
		var fill := Color(0.15, 0.19, 0.21, 0.22) if active else Color(0.08, 0.11, 0.13, 0.12)
		var center := size * 0.5
		# A tile stockpile carries the hex identity. Market and intermediary routes are
		# service endpoints, so their icons stand alone in the same off-white treatment
		# used by the other UI glyphs.
		var is_stockpile := kind == "stockpile" or kind == "remote_stockpile"
		var radius := minf(size.x, size.y) * (0.50 if is_stockpile else 0.38)
		# A remote stockpile is a route between two tiles. Draw two separate tile
		# hexes with a small arrow between their centres, rather than stacking the
		# hexes (which made this look like a single oversized stockpile).
		if kind == "remote_stockpile":
			var remote_radius := minf(size.x, size.y) * 0.27
			var from := Vector2(size.x * 0.23, size.y * 0.5)
			var to := Vector2(size.x * 0.77, size.y * 0.5)
			for tile_center in [from, to]:
				var tile_hex := _hex_points(tile_center, remote_radius)
				draw_colored_polygon(tile_hex, fill)
				draw_polyline(_closed(tile_hex), ink, 1.7, true)
			var direction := (to - from).normalized()
			var arrow_start := from + direction * remote_radius * 1.05
			var arrow_end := to - direction * remote_radius * 1.05
			draw_line(arrow_start, arrow_end, ink, 2.0, true)
			var perpendicular := Vector2(-direction.y, direction.x)
			var arrow_head := PackedVector2Array([
				arrow_end,
				arrow_end - direction * 7.0 + perpendicular * 4.0,
				arrow_end - direction * 7.0 - perpendicular * 4.0,
			])
			draw_colored_polygon(arrow_head, ink)
			var texture := _texture_for_kind()
			if texture != null:
				var texture_size := texture.get_size()
				var max_side := remote_radius * 1.25
				var scale := minf(max_side / maxf(1.0, texture_size.x), max_side / maxf(1.0, texture_size.y))
				var draw_size := texture_size * scale
				draw_texture_rect(texture, Rect2(to - draw_size * 0.5, draw_size), false, CREAM)
			return
		if is_stockpile:
			var hex := _hex_points(center, radius)
			draw_colored_polygon(hex, fill)
			draw_polyline(_closed(hex), ink, 2.0 if active else 1.5, true)
		if kind == "none":
			if not is_stockpile:
				center = size * 0.5
			draw_line(center + Vector2(-radius * 0.65, radius * 0.65), center + Vector2(radius * 0.65, -radius * 0.65), Color(0.75, 0.38, 0.34), 2.5, true)
			return
		var texture := _texture_for_kind()
		if texture != null:
			var max_side := minf(size.x, size.y) * (0.72 if is_stockpile else 0.86)
			var texture_size := texture.get_size()
			var scale := minf(max_side / maxf(1.0, texture_size.x), max_side / maxf(1.0, texture_size.y))
			var draw_size := texture_size * scale
			var rect := Rect2(center - draw_size * 0.5, draw_size)
			# Route assets are white alpha masks. Tinting the mask keeps the port and
			# lorry glyphs consistently off-white without bringing their source plates in.
			draw_texture_rect(texture, rect, false, CREAM)

func _build_recipe_strip(flow: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "BuildingRecipeStrip"
	card.custom_minimum_size = Vector2(0, 156)  # consistent height for 1–4 input / output grids
	# v3: an enamel sign behind the diagram, its grunge kept clear of the icons and arrow (watched below).
	var enamel: BdpV3Enamel = null
	if UiPrefs.use_bdp_v3:
		var bare := StyleBoxEmpty.new()
		bare.set_content_margin_all(0)
		card.add_theme_stylebox_override("panel", bare)
		enamel = BdpV3Enamel.new()
		card.add_child(enamel)
	else:
		var style := StyleBoxFlat.new()
		style.bg_color = CREAM
		style.set_corner_radius_all(0)  # squared corners
		style.set_content_margin_all(0)  # children fill the full card so the outline sits 4px from the edge
		card.add_theme_stylebox_override("panel", style)
		# thin navy outline inset 4px from the actual card edge
		var outline := _InsetOutline.new()
		outline.col = CREAM_INK
		outline.set_anchors_preset(Control.PRESET_FULL_RECT)
		outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(outline)

	card.clip_contents = false  # let big recipe icons bleed past the card edge
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 6)
	card.add_child(pad)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)  # 5px either side of the arrow
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	pad.add_child(row)

	# inputs — a single big icon, or a 2×2 grid; unframed art that overflows its slot by ~20%
	var inputs: Array = flow.get("inputs", [])
	if inputs.is_empty():
		var none := Label.new()
		none.text = "No inputs"
		none.add_theme_color_override("font_color", CREAM_INK)
		none.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(none)
	else:
		row.add_child(_recipe_side(inputs))

	# navy filled arrow with the power draw on its body
	var arrow := _recipe_arrow(int(flow.get("power_in", 0)))
	row.add_child(arrow)

	# outputs — one hero icon, or a grid when the recipe has CO-PRODUCTS (chlor-alkali yields
	# chlorine + sodium hydroxide + hydrogen). The pill on
	# each carries the base→modified delta.
	var outputs: Array = flow.get("outputs", [])
	if outputs.is_empty() and not (flow.get("output", {}) as Dictionary).is_empty():
		outputs = [flow.get("output", {})]
	if not outputs.is_empty():
		var out_wrap := CenterContainer.new()
		out_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		out_wrap.clip_contents = false
		var mod_pct := int(flow.get("mod_pct", 0))
		if outputs.size() == 1:
			var o0: Dictionary = outputs[0]
			out_wrap.add_child(_recipe_icon(str(o0.get("good_id", "")), str(o0.get("internal", "")),
				int(o0.get("qty", 0)), 126, 3, int(o0.get("base_qty", -1)), mod_pct))
		else:
			var grid := GridContainer.new()
			grid.columns = 2
			grid.clip_contents = false
			grid.add_theme_constant_override("h_separation", DS.SP["SM"])
			grid.add_theme_constant_override("v_separation", DS.SP["SM"])
			for o in outputs:
				grid.add_child(_recipe_icon(str((o as Dictionary).get("good_id", "")),
					str((o as Dictionary).get("internal", "")), int((o as Dictionary).get("qty", 0)),
					58, 1, int((o as Dictionary).get("base_qty", -1)), mod_pct))
			out_wrap.add_child(grid)
		row.add_child(out_wrap)
	if enamel != null:
		var clear: Array[Control] = [arrow]
		for n in card.find_children("*", "Control", true, false):
			if n.has_meta("recipe_icon"):
				clear.append(n)
		enamel.watch(clear)
	return card

# One side of the recipe diagram (inputs): a single hero icon, or a centred 2×2 grid of smaller ones.
# All unframed art that overflows its slot by ~20% so the visible good reads larger.
func _recipe_side(items: Array) -> Control:
	var wrap := CenterContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.clip_contents = false
	if items.size() == 1:
		var it: Dictionary = items[0]
		wrap.add_child(_recipe_icon(str(it.get("good_id", "")), str(it.get("internal", "")), int(it.get("qty", 0)), 126, 3))
	else:
		# Multiple inputs: a compact 2-col grid of smaller icons that barely overflow (~1%).
		var grid := GridContainer.new()
		grid.columns = 2
		grid.clip_contents = false
		grid.add_theme_constant_override("h_separation", DS.SP["SM"])
		grid.add_theme_constant_override("v_separation", DS.SP["SM"])
		for it in items:
			grid.add_child(_recipe_icon(str(it.get("good_id", "")), str(it.get("internal", "")), int(it.get("qty", 0)), 58, 1))
		wrap.add_child(grid)
	return wrap

# An UNFRAMED recipe-diagram icon: bare chroma art centred in a `size` slot but drawn `bleed` px
# larger on every side (clip off) so it overflows ~20% past the slot; qty pill on the bottom-right.
func _recipe_icon(good_id: String, internal: String, qty: int, size: int, bleed: int, base_qty: int = -1, mod_pct: int = 0) -> Control:
	var slot := Control.new()
	slot.set_meta("recipe_icon", true)
	slot.custom_minimum_size = Vector2(size, size)
	slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot.clip_contents = false
	if good_id != "":
		slot.tooltip_text = Catalog.get_display_name(good_id)  # hover shows the good's name
	# Power drawn AS A GOOD uses its isometric goods icon, matching the empire plates;
	# the flat lightning stays on the arrow's energy badge only.
	var tex: Texture2D = GoodIcons.texture_for_size(good_id, internal, float(size))
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.offset_left = -bleed
		tr.offset_top = -bleed
		tr.offset_right = bleed
		tr.offset_bottom = bleed
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(tr)
	else:
		var chip := Label.new()
		chip.text = internal.substr(0, 2).to_upper() if internal != "" else "?"
		chip.set_anchors_preset(Control.PRESET_FULL_RECT)
		chip.add_theme_color_override("font_color", CREAM_INK)
		chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot.add_child(chip)
	slot.add_child(_qty_pill(qty, base_qty, mod_pct))
	return slot

# A market-panel-style framed good icon (off-white plate + raised metal bevel, via
# UIHelpers.make_framed_good_icon) with the qty PILL superimposed on its bottom-right. The framed
# GoodIconHover root supplies the good-name hover tooltip itself. base_qty/mod_pct (output only) →
# the pill shows the struck base + effective with a coloured outline.
## The frameless variant: cream plate, rounded corners, no metal bevel. Same pill and same
## route into the Goods Graph — only the plate differs.
func _plain_icon_pill(good_id: String, internal: String, qty: int, size: int) -> Control:
	var holder := UIHelpers.make_plain_good_icon(good_id, internal, size)
	holder.add_child(_qty_pill(qty, -1, 0))
	UIHelpers.link_good_icon_to_encyclopedia(holder, good_id)
	return holder

func _good_icon_pill(good_id: String, internal: String, qty: int, size: int, base_qty: int = -1, mod_pct: int = 0, pill_inside := false) -> Control:
	var holder := UIHelpers.make_plain_good_icon(good_id, internal, size)
	holder.add_child(_qty_pill(qty, base_qty, mod_pct, pill_inside))
	# Every input and output on this panel is a way into the Goods Graph: the player is
	# already looking at what this building eats and makes, and 'how else is that made'
	# is the next question. ALWAYS, not the deferring form — a recipe card is itself
	# clickable, so the polite version handed every one of these clicks to the card and the
	# graph never opens.
	UIHelpers.link_good_icon_to_encyclopedia(holder, good_id)
	return holder

const QTY_PILL_INSET := 5

# Back-compat name used by construction / shipments / demolish — now the pill icon.
func _flat_good_cell(good_id: String, internal: String, qty: int, size: int) -> Control:
	return _good_icon_pill(good_id, internal, qty, size)

# Navy qty pill overhanging an icon's bottom-right. With a modifier (base != qty) it shows the struck
# base + effective and a green (positive) / red (negative) 2px outline; otherwise a plain pill.
## `inside` keeps the pill within the icon's corner instead of overhanging it.
func _qty_pill(qty: int, base_qty: int = -1, _mod_pct: int = 0, inside := false) -> Control:
	# Outline colour follows the ACTUAL numbers shown (effective vs base), not a separate modifier
	# figure that could disagree in sign — green when the effective output is higher, red when lower.
	var has_delta := base_qty >= 0 and base_qty != qty
	var content := ("%d %d" % [base_qty, qty]) if has_delta else str(qty)
	var h := 22
	var w := maxi(h, content.length() * 9 + 14)
	var pill := PanelContainer.new()
	pill.custom_minimum_size = Vector2(w, h)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	var overhang := -QTY_PILL_INSET if inside else 8
	pill.offset_left = -w + overhang
	pill.offset_top = -h + overhang
	pill.offset_right = overhang
	pill.offset_bottom = overhang
	var st := StyleBoxFlat.new()
	st.bg_color = DS.PALETTE["BG_PANEL"]
	st.set_corner_radius_all(int(h / 2.0))
	st.set_border_width_all(2)
	st.border_color = (DS.PALETTE["OK"] if qty > base_qty else DS.PALETTE["DANGER"]) if has_delta else DS.PALETTE["BORDER_STRONG"]
	pill.add_theme_stylebox_override("panel", st)
	if has_delta:
		var rt := RichTextLabel.new()
		rt.bbcode_enabled = true
		rt.fit_content = true
		rt.scroll_active = false
		rt.autowrap_mode = TextServer.AUTOWRAP_OFF
		rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rt.text = "[center][s][color=#7f8fa5]%d[/color][/s] [color=#eaf1f8]%d[/color][/center]" % [base_qty, qty]
		pill.add_child(rt)
	else:
		var lbl := Label.new()
		lbl.theme_type_variation = "Numeric"
		lbl.text = str(qty)
		lbl.add_theme_color_override("font_color", DS.PALETTE["ACCENT"])
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pill.add_child(lbl)
	return pill

# Navy filled arrow: a rounded-left body carrying the power label + bolt, then a triangle head.
## The recipe arrow: a square-cornered navy body holding the power draw, and a head with smoothed
## edges. The body is 10% smaller than it was (46 px tall, with 12 + 8 px of side padding round the
## number and bolt, which keep their size), and the head 25% larger than it was (28 × 46), so it flares
## past the body.
const ARROW_BODY_H := 41
const ARROW_OLD_SIDE_PAD := 20.0
const ARROW_HEAD := Vector2(35, 58)

func _recipe_arrow(power_in: int) -> Control:
	var arrow := HBoxContainer.new()
	arrow.name = "RecipeArrow"
	arrow.add_theme_constant_override("separation", 0)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var body_h := ARROW_BODY_H
	var body := PanelContainer.new()
	body.name = "ArrowBody"
	body.custom_minimum_size = Vector2(0, body_h)
	body.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bst := StyleBoxFlat.new()
	bst.bg_color = CREAM_INK   # square corners
	bst.content_margin_top = 4
	bst.content_margin_bottom = 4
	body.add_theme_stylebox_override("panel", bst)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 5)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(hb)
	if power_in > 0:
		var n := Label.new()
		n.theme_type_variation = "Numeric"
		n.add_theme_font_size_override("font_size", 21)
		n.text = str(power_in)
		n.add_theme_color_override("font_color", Color.WHITE)
		hb.add_child(n)
		var bolt := _load_texture_rect(RECIPE_POWER_ICON_PATH, Vector2(18, 18))
		if bolt != null:
			hb.add_child(bolt)
		else:
			var kw := Label.new()
			kw.text = "MW"
			kw.add_theme_color_override("font_color", DS.PALETTE["WARN"])
			hb.add_child(kw)
	else:
		var nop := Label.new()
		nop.text = "no power"
		nop.theme_type_variation = "Caption"
		nop.add_theme_color_override("font_color", Color(0.75, 0.82, 0.9))
		hb.add_child(nop)
	# Side padding for a body 10% narrower than the old one round the same content (split 12:8).
	var content_w := _arrow_content_width(power_in)
	var pad := maxf(4.0, 0.9 * (ARROW_OLD_SIDE_PAD + content_w) - content_w)
	bst.content_margin_left = pad * 0.6
	bst.content_margin_right = pad * 0.4
	arrow.add_child(body)
	var head := _ArrowHead.new()
	head.name = "ArrowHead"
	head.col = CREAM_INK
	head.custom_minimum_size = ARROW_HEAD
	head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	arrow.add_child(head)
	return arrow

## The width of what the arrow's body holds: the power draw and its bolt, or "no power".
func _arrow_content_width(power_in: int) -> float:
	if power_in > 0:
		var f: Font = DS.theme.get_font("font", "Numeric") if DS and DS.theme else null
		var w := f.get_string_size(str(power_in), HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x if f != null else 12.0 * str(power_in).length()
		return w + 5.0 + 18.0
	var cf: Font = DS.theme.get_font("font", "Caption") if DS and DS.theme else null
	return cf.get_string_size("no power", HORIZONTAL_ALIGNMENT_LEFT, -1, DS.FS["CAPTION"]).x if cf != null else 56.0

## Sticky across refreshes: a player who opened the checklist wants it to stay open while
## they watch the turn resolve, not to re-collapse under them every rebuild.
var _diagnostics_open := false
# v3's drum counters and cost gauges: what each last read, so the next rebuild rolls from it.
var _v3_last_readings := {}

# --- diagnostics ---------------------------------------------------------------------------

## The checklist, folded to one line when there is nothing wrong.
## A building that is running fine still spent six rows saying so, above the numbers the
## player opened the panel for. Nothing is hidden — the fold opens — but "all green" is a
## one-line answer and it should take one line.
func _build_diagnostics(rows: Array) -> PanelContainer:
	var card := _make_card()
	card.name = "DiagnosticsCard"   # stable target for the tutorial coach spotlight
	var vb := card.get_child(0) as VBoxContainer
	vb.add_theme_constant_override("separation", 0)
	var cable: Control = null
	if UiPrefs.use_bdp_v3:
		# v3: each row is its own module set in the plastic case, fed by a branch off the cable that
		# runs down the case's left side.
		var bare := StyleBoxEmpty.new()
		bare.content_margin_left = V3_DIAG_GUTTER
		bare.content_margin_right = 2
		bare.content_margin_top = 4
		bare.content_margin_bottom = 4
		card.add_theme_stylebox_override("panel", bare)
		vb.add_theme_constant_override("separation", V3_DIAG_MODULE_GAP)
		cable = BdpV3Cable.new()
		cable.centre_x = V3_DIAG_CABLE_X - V3_DIAG_GUTTER
		card.add_child(cable)
	var all_ok := not rows.is_empty()
	for r_variant: Variant in rows:
		if str((r_variant as Dictionary).get("tone", "info")) not in ["ok", "good", "info"]:
			all_ok = false
			break
	if not all_ok:
		var modules: Array[Control] = []
		for i in rows.size():
			var row := _diag_row(rows[i], i > 0)
			vb.add_child(row)
			modules.append(row)
		if cable != null:
			cable.taps = modules
		return card

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", V3_DIAG_MODULE_GAP if UiPrefs.use_bdp_v3 else 0)
	body.visible = _diagnostics_open
	var body_modules: Array[Control] = []
	for i in rows.size():
		var row := _diag_row(rows[i], i > 0)
		body.add_child(row)
		body_modules.append(row)

	var head := Button.new()
	head.flat = true
	head.focus_mode = Control.FOCUS_NONE
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	head.add_theme_color_override("font_color", DS.PALETTE["OK"])
	head.add_theme_color_override("font_hover_color", DS.PALETTE["OK"])
	head.text = _diag_head_text()
	head.tooltip_text = "Show every check"
	head.pressed.connect(func() -> void:
		_diagnostics_open = not _diagnostics_open
		body.visible = _diagnostics_open
		head.text = _diag_head_text())
	if cable != null:
		# v3: the folded line is a module too, with its lamp lit green.
		var head_module := _v3_diag_module()
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", DS.SP["SM"])
		head_module.add_child(hb)
		var lamp := BdpV3Lamp.new()
		lamp.lamp_scale = V3_DIAG_LAMP_SCALE
		lamp.set_tone("ok")
		hb.add_child(lamp)
		head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(head)
		vb.add_child(head_module)
		body_modules.push_front(head_module)
		cable.taps = body_modules
	else:
		vb.add_child(head)
	vb.add_child(body)
	return card


## v3's diagnostics: where the cable runs (from the card's left), and the modules' left margin, a
## branch's length to its right; the gap between modules.
const V3_DIAG_CABLE_X := 10.0
const V3_DIAG_GUTTER := V3_DIAG_CABLE_X + BdpV3Cable.TAP_LENGTH
const V3_DIAG_MODULE_GAP := 8
## The diagnostics' row lamps, as a share of the status lamp's size.
const V3_DIAG_LAMP_SCALE := 0.72
## The diagnostics' module plate (layout.json diag_module): its shadow room and 9-slice corner.
const V3_DIAG_MODULE: Texture2D = preload("res://assets/ui/bdp_v3/diag_module.png")
const V3_DIAG_MODULE_MARGIN := 10.0 / 1.875
const V3_DIAG_MODULE_CORNER := 26.0 * 2.0 / 1.875

## Whether the diagnostics show the Visual view: the player's choice on the switch (UiPrefs, kept while
## the game runs), except while a tutorial step spotlights the rows, which its words describe.
func _v3_diag_shows_visual() -> bool:
	return UiPrefs.bdp_diag_visual and Tutorial.active_spotlight_ref() != "DiagnosticsCard"

## v3: a raised module in the diagnostics' case, for one check.
func _v3_diag_module() -> PanelContainer:
	var module := PanelContainer.new()
	module.name = "DiagModule"
	module.set_meta("v3_diag_module", true)
	var pad := StyleBoxEmpty.new()
	pad.content_margin_left = 10
	pad.content_margin_right = 10
	pad.content_margin_top = 8
	pad.content_margin_bottom = 8
	module.add_theme_stylebox_override("panel", pad)
	module.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	module.draw.connect(func() -> void:
		BdpV3Nine.paint(module, V3_DIAG_MODULE, Rect2(Vector2.ZERO, module.size).grow(V3_DIAG_MODULE_MARGIN), V3_DIAG_MODULE_CORNER))
	return module

## v3: the diagnostics' Visual / Text switch, moulded into the case beside the heading, its two sides
## named in the headings' raised letters.
func _v3_view_switch() -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.name = "ViewSwitch"
	hb.add_theme_constant_override("separation", 6)
	hb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for side in ["Visual", "", "Text"]:
		if side == "":
			var sw: Control = BdpV3Toggle.new()
			sw.set_right(not _v3_diag_shows_visual())
			sw.toggled.connect(func(right: bool) -> void:
				UiPrefs.set_bdp_diag_visual(not right)
				_v3_show_diag_view())
			hb.add_child(sw)
		else:
			var raised: Control = BdpV3Heading.new()
			raised.name = "Switch" + side
			raised.text = side
			hb.add_child(raised)
	return hb

## v3's diagnostics as pictures: the chain left to right, a column a stage, each check a raised icon over
## a lamp; hovering an icon names it in the readout at the foot. Each stage's checks come from
## BuildingReadout (input_checks, inbound_checks, power_checks, plant_checks, output_checks). [stage,
## icons to a row]; a column's share of the width follows its icons to a row.
const V3_DIAG_STAGES := [["Inputs", 1], ["Inbound", 1], ["Power", 1], ["Plant", 1], ["Outputs", 1]]
## Every column is this many rows of icons tall, whatever it holds (the most any stage has, Outputs'
## five), so the columns stand level and a stage can gain checks without the case changing height.
const V3_DIAG_ROWS := 5
## The icons' side, and their lamps' size as a share of the status lamp's (the text rows' size).
const V3_DIAG_ICON_PX := 56.0
const V3_DIAG_ICON_LAMP_SCALE := 0.72
## Each check's raised icon is res://assets/ui/bdp_v3/diag_icon_<key>.png and its shadow, or the one its
## `icon` names (Sales shows the pallet for unsold stock, the coin for glut); an output check that mirrors
## an inbound one shares its icon.
const V3_DIAG_ICON_ALIAS := {"reach": "route", "transit_out": "transit", "freight_out": "freight"}
const V3_DIAG_COLUMN_GAP := 6
## A column's inside margin, left and right, and the gaps between its icons: 6 px either side of each icon.
const V3_DIAG_COLUMN_PAD := 6
const V3_DIAG_CELL_GAP := Vector2i(12, 8)
## The gap above the readout, and the least gap between it and the first row when it rises.
const V3_DIAG_READOUT_GAP := 8.0
## After the pointer leaves an icon, how long the readout waits for it to reach another before it goes
## back to the worst check, so crossing the gap between two icons doesn't flicker.
const V3_DIAG_READOUT_SETTLE := 0.15

var _v3_diag_text_card: Control = null
var _v3_diag_visual_view: Control = null
var _v3_diag_readout: Control = null
var _v3_diag_first: Control = null
var _v3_diag_worst: Control = null
var _v3_diag_hot: Control = null


## The visual view's checks, a list per stage, each {stage, key, label, detail, tone}, from the building
## (`econ` is its BuildingEconomics.per_turn). Only the checks that apply are kept: one unlit because it
## has nothing to say about this building (a deposit for a factory, works when none are under way) is left
## out, and a stage with none left is empty.
static func v3_diag_visual_checks(building: Dictionary, recipe: Dictionary, is_infra: bool, econ: Dictionary = {}) -> Array:
	var stages: Array = []
	for entry: Array in V3_DIAG_STAGES:
		var stage := str(entry[0])
		var wired: Array = []
		match stage:
			"Inputs":
				wired = BuildingReadout.input_checks(building, recipe, is_infra)
			"Inbound":
				wired = BuildingReadout.inbound_checks(building, recipe, is_infra, econ)
			"Power":
				wired = BuildingReadout.power_checks(building, recipe, is_infra)
			"Plant":
				wired = BuildingReadout.plant_checks(building, recipe, is_infra, econ)
			"Outputs":
				wired = BuildingReadout.output_checks(building, recipe, is_infra)
		var checks: Array = []
		for c: Dictionary in wired:
			if str(c.get("tone", "off")) == "off":
				continue
			var check := c.duplicate()
			check["stage"] = stage
			checks.append(check)
		stages.append(checks)
	return stages


## A check's raised icon and its shadow.
static func _v3_diag_icon(key: String) -> Array:
	var path := "res://assets/ui/bdp_v3/diag_icon_%s.png" % str(V3_DIAG_ICON_ALIAS.get(key, key))
	return [load(path), load(path.replace(".png", "_shadow.png"))]


## v3: the visual view. Each stage with checks that apply is a raised module in the case, its name in
## metal letters over its icons (one to a row, V3_DIAG_STAGES); the readout's slot is at the foot.
func _build_v3_diag_visual(building: Dictionary, recipe: Dictionary, is_infra: bool, econ: Dictionary = {}) -> VBoxContainer:
	var view := VBoxContainer.new()
	view.name = "DiagnosticsVisual"
	view.add_theme_constant_override("separation", 0)
	var columns := HBoxContainer.new()
	columns.name = "DiagColumns"
	columns.add_theme_constant_override("separation", V3_DIAG_COLUMN_GAP)
	view.add_child(columns)
	var indicators: Array[Control] = []
	var stage_checks: Array = v3_diag_visual_checks(building, recipe, is_infra, econ)
	for s in stage_checks.size():
		var checks: Array = stage_checks[s]
		if checks.is_empty():
			continue   # a stage with nothing that applies takes no column
		var across := int(V3_DIAG_STAGES[s][1])
		var column := _v3_diag_module()
		column.name = "DiagColumn"
		column.remove_meta("v3_diag_module")
		column.set_meta("v3_diag_column", true)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.size_flags_stretch_ratio = across
		var pad := column.get_theme_stylebox("panel") as StyleBoxEmpty
		pad.content_margin_left = V3_DIAG_COLUMN_PAD
		pad.content_margin_right = V3_DIAG_COLUMN_PAD
		pad.content_margin_top = 6
		pad.content_margin_bottom = 8
		columns.add_child(column)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 5)
		column.add_child(vb)
		var title := _v3_metal_label(str(V3_DIAG_STAGES[s][0]), HORIZONTAL_ALIGNMENT_CENTER)
		title.add_theme_font_size_override("font_size", 13)
		vb.add_child(title)
		var grid := GridContainer.new()
		grid.columns = across
		grid.add_theme_constant_override("h_separation", V3_DIAG_CELL_GAP.x)
		grid.add_theme_constant_override("v_separation", V3_DIAG_CELL_GAP.y)
		grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(grid)
		for check: Dictionary in checks:
			var ind: Control = BdpV3Indicator.new()
			ind.configure(V3_DIAG_ICON_PX, V3_DIAG_ICON_LAMP_SCALE)
			var art: Array = _v3_diag_icon(str(check.get("icon", check.get("key", ""))))
			ind.set_check(check, art[0], art[1])
			ind.hovered.connect(_v3_on_indicator_hovered)
			ind.unhovered.connect(_v3_on_indicator_unhovered)
			grid.add_child(ind)
			indicators.append(ind)
		if grid.get_child_count() > 0:
			var cell_h: float = (grid.get_child(0) as Control).custom_minimum_size.y
			grid.custom_minimum_size.y = V3_DIAG_ROWS * cell_h + (V3_DIAG_ROWS - 1) * V3_DIAG_CELL_GAP.y
	# The slot keeps the readout's room at the foot; the screen in it is placed by hand, so it can rise.
	var slot := Control.new()
	slot.name = "DiagReadoutSlot"
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.custom_minimum_size = Vector2(0.0, V3_DIAG_READOUT_GAP + BdpV3Readout.HEIGHT)
	view.add_child(slot)
	var readout: Control = BdpV3Readout.new()
	slot.add_child(readout)
	slot.item_rect_changed.connect(_v3_place_readout)
	_v3_diag_readout = readout
	_v3_diag_hot = null
	_v3_diag_first = indicators[0] if not indicators.is_empty() else null
	_v3_diag_worst = _v3_worst_indicator(indicators)
	if indicators.is_empty():
		readout.show_check("", "Diagnostics", "Nothing to check for this building.", "off")
	else:
		_v3_show_in_readout(_v3_diag_worst)
	return view


## The check to show when the pointer is on none: the first red, else the first amber, else the first.
static func _v3_worst_indicator(indicators: Array) -> Control:
	for want in ["bad", "warn"]:
		for ind: Control in indicators:
			if ind.tone == want:
				return ind
	return indicators[0] if not indicators.is_empty() else null


func _v3_show_in_readout(ind: Control) -> void:
	if _v3_diag_readout == null or not is_instance_valid(_v3_diag_readout) or ind == null or not is_instance_valid(ind):
		return
	_v3_diag_readout.show_check(ind.stage, ind.label, ind.detail, ind.tone)


func _v3_on_indicator_hovered(ind: Control) -> void:
	_v3_diag_hot = ind
	_v3_show_in_readout(ind)


func _v3_on_indicator_unhovered(ind: Control) -> void:
	if _v3_diag_hot == ind:
		_v3_diag_hot = null
	get_tree().create_timer(V3_DIAG_READOUT_SETTLE).timeout.connect(_v3_readout_settle)


func _v3_readout_settle() -> void:
	if _v3_diag_hot == null or not is_instance_valid(_v3_diag_hot):
		_v3_show_in_readout(_v3_diag_worst)


## v3: shows the diagnostics' view the switch is set to.
func _v3_show_diag_view() -> void:
	var visual := _v3_diag_shows_visual()
	if _v3_diag_text_card != null and is_instance_valid(_v3_diag_text_card):
		_v3_diag_text_card.visible = not visual
	if _v3_diag_visual_view != null and is_instance_valid(_v3_diag_visual_view):
		_v3_diag_visual_view.visible = visual
	_v3_place_readout.call_deferred()


## v3: keeps the diagnostics' readout in sight. It sits in its slot at the foot of the visual view; while
## the slot is below the scroll area's bottom edge, the screen rises to sit on that edge, over the lower
## icons, but never over the first row.
func _v3_place_readout(_a: Variant = null) -> void:
	var readout := _v3_diag_readout
	if readout == null or not is_instance_valid(readout) or not readout.is_inside_tree() or _scroll == null:
		return
	var slot := readout.get_parent() as Control
	var h: float = readout.custom_minimum_size.y
	var top := V3_DIAG_READOUT_GAP
	if slot.is_visible_in_tree():
		var to_slot := slot.get_global_transform().affine_inverse()
		var view_bottom: float = (to_slot * _scroll.get_global_rect().end).y
		var highest := top
		if _v3_diag_first != null and is_instance_valid(_v3_diag_first):
			highest = minf(top, (to_slot * _v3_diag_first.get_global_rect().end).y + V3_DIAG_READOUT_GAP)
		top = clampf(view_bottom - h, highest, top)
	readout.position = Vector2(0.0, top)
	readout.size = Vector2(slot.size.x, h)


func _diag_head_text() -> String:
	return ("⌄  All green" if _diagnostics_open else "›  All green")

func _diag_row(r: Dictionary, top_border: bool) -> Control:
	var wrap: PanelContainer
	if UiPrefs.use_bdp_v3:
		wrap = _v3_diag_module()
	elif top_border:
		wrap = PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_color = Color(DS.PALETTE["BORDER_SOFT"].r, DS.PALETTE["BORDER_SOFT"].g, DS.PALETTE["BORDER_SOFT"].b, 0.18)
		sb.border_width_top = 1
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		wrap.add_theme_stylebox_override("panel", sb)
	else:
		wrap = PanelContainer.new()
		var sb2 := StyleBoxEmpty.new()
		sb2.content_margin_bottom = 8
		wrap.add_theme_stylebox_override("panel", sb2)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", DS.SP["SM"])
	wrap.add_child(hb)
	var tone := str(r.get("tone", "info"))
	var c := _tone_color(tone)
	if UiPrefs.use_bdp_v3:
		# v3: a lamp like the status lamp's, lit for the row's tone; a row about a good shows it too.
		var lamp := BdpV3Lamp.new()
		lamp.lamp_scale = V3_DIAG_LAMP_SCALE
		lamp.set_tone(tone)
		hb.add_child(lamp)
		if str(r.get("good_id", "")) != "":
			var good_icon := UIHelpers.make_framed_good_icon(str(r.get("good_id", "")), Catalog.get_internal_name(str(r.get("good_id", ""))), 18)
			good_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			hb.add_child(good_icon)
	else:
		var chip := PanelContainer.new()
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var chip_style := StyleBoxFlat.new()
		chip_style.bg_color = Color(c.r, c.g, c.b, 0.16)
		chip_style.border_color = Color(c.r, c.g, c.b, 0.55)
		chip_style.set_border_width_all(1)
		chip_style.set_corner_radius_all(6)
		chip_style.set_content_margin_all(3)
		chip.add_theme_stylebox_override("panel", chip_style)
		# A row about a specific commodity shows that good's icon instead of the tone dot.
		var row_good := str(r.get("good_id", ""))
		if row_good != "":
			chip.add_child(UIHelpers.make_framed_good_icon(row_good, Catalog.get_internal_name(row_good), 18))
		else:
			var dot := ColorRect.new()
			dot.color = c
			dot.custom_minimum_size = Vector2(12, 12)
			chip.add_child(dot)
		hb.add_child(chip)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 1)
	hb.add_child(col)
	var label := Label.new()
	label.theme_type_variation = "Body"
	label.text = str(r.get("label", ""))
	label.add_theme_color_override("font_color", DS.PALETTE["TEXT_MUTED"] if tone == "info" else c)
	col.add_child(label)
	var detail := Label.new()
	detail.theme_type_variation = "Caption"
	detail.text = str(r.get("detail", ""))
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# v3's modules sit further in, past the cable's branches, so their text has less room.
	detail.custom_minimum_size = Vector2(PANEL_WIDTH - (180.0 if UiPrefs.use_bdp_v3 else 110.0), 0)
	col.add_child(detail)
	return wrap

# --- cost to produce (emphasised, per output good) -----------------------------------------

func _build_cost_to_produce(rows: Array) -> PanelContainer:
	var card := _make_card()
	card.name = "CostToProduceCard"   # stable target for the tutorial coach spotlight
	var vb := card.get_child(0) as VBoxContainer
	vb.add_theme_constant_override("separation", DS.SP["SM"])
	if UiPrefs.use_bdp_v3:
		_v3_cost_gauges(card, vb, rows)
		return card
	for i in rows.size():
		var r: Dictionary = rows[i]
		if i > 0:
			vb.add_child(HSeparator.new())
		var c: Color = r.get("color", DS.PALETTE["TEXT"])
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", DS.SP["SM"])
		vb.add_child(line)
		# good name + market ref
		var lcol := VBoxContainer.new()
		lcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lcol.add_theme_constant_override("separation", 0)
		line.add_child(lcol)
		var name_l := Label.new()
		name_l.theme_type_variation = "Body"
		name_l.text = str(r.get("name", ""))
		lcol.add_child(name_l)
		var mkt := Label.new()
		mkt.theme_type_variation = "Caption"
		var pct := int(r.get("pct", 0))
		mkt.text = "market £%s · %s%d%%" % [BuildingStatus._fmt_upto2(float(r.get("market_price", 0.0))), "+" if pct > 0 else "", pct]
		lcol.add_child(mkt)
		# big RAG-coloured £/unit
		var big := Label.new()
		big.theme_type_variation = "Numeric"
		big.add_theme_font_size_override("font_size", 24)
		big.add_theme_color_override("font_color", c)
		big.text = "£%s" % BuildingStatus._fmt_upto2(float(r.get("unit_cost", 0.0)))
		big.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(big)
		var unit := Label.new()
		unit.theme_type_variation = "Caption"
		unit.text = "/unit"
		unit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(unit)
	return card

## v3: each output's cost on a gauge set into the section's dark plate, the good's icon beside it. The
## needle is the unit cost as a share of the market price, on a scale to twice it; the zones are the
## cost's RAG bands (green under 90%, amber to 110%, red over) and the LED follows the zone. An unknown
## cost leaves the needle down and the LED off. The needle swings from where it last read. To the right,
## the unit cost on a mini screen in LED segments in its RAG colour, and the market price under it.
const V3_GAUGE_SIZE := 160.0
const V3_GAUGE_SCALE_PCT := 200.0
## The gauge's bezel is this share of its render across, the room round it this share on each side;
## its holder in the row is the share it keeps (the bezel and its shadow to the bottom-right).
const V3_GAUGE_BEZEL := 709.0 / 1024.0
const V3_GAUGE_ROOM := 150.0 / 1024.0
const V3_GAUGE_HELD := 790.0 / 1024.0
## The good's icon beside it is as tall as the bezel, frame and all.
const V3_COST_ICON := int(V3_GAUGE_SIZE * V3_GAUGE_BEZEL - 2.0 * 7.0 / 1.875)
## The hole a gauge is set into (layout.json gauge_socket), rendered for a gauge of this size.
const V3_GAUGE_SOCKET: Texture2D = preload("res://assets/ui/bdp_v3/gauge_socket.png")
const V3_GAUGE_SOCKET_AT := 160.0

## The thin metal frame round a good's icon, the icon set below it (layout.json icon_well): how far the
## render reaches beyond the opening, its 9-slice corner, and the opening's corner radius.
const V3_WELL: Texture2D = preload("res://assets/ui/bdp_v3/icon_well.png")
const V3_WELL_REACH := (12.0 + 7.0) / 1.875
const V3_WELL_CORNER := (12.0 + 7.0 + 16.0) * 2.0 / 1.875
const V3_WELL_RADIUS := 10.0 / 1.875

## v3: sets a good's icon below a thin metal frame, its tile's corners following the frame's opening.
## The frame goes over the art and under the quantity pill, if it has one.
func _v3_set_in_well(icon: Control) -> void:
	var tile := icon.get_child(0) as PanelContainer
	if tile != null and tile.get_theme_stylebox("panel") is StyleBoxFlat:
		var st := (tile.get_theme_stylebox("panel") as StyleBoxFlat).duplicate() as StyleBoxFlat
		st.set_corner_radius_all(roundi(V3_WELL_RADIUS))
		tile.add_theme_stylebox_override("panel", st)
	var well := Control.new()
	well.name = "IconWell"
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	well.set_anchors_preset(Control.PRESET_FULL_RECT)
	well.draw.connect(func() -> void:
		BdpV3Nine.paint(well, V3_WELL, Rect2(Vector2.ZERO, well.size).grow(V3_WELL_REACH), V3_WELL_CORNER))
	well.resized.connect(well.queue_redraw)
	icon.add_child(well)
	icon.move_child(well, mini(2, icon.get_child_count() - 1))

static func v3_cost_gauge_reading(unit_cost: float, market_price: float) -> Dictionary:
	if unit_cost < 0.0 or market_price <= 0.0:
		return {"value": 0.0, "known": false}
	return {"value": clampf(unit_cost / market_price * 100.0 / V3_GAUGE_SCALE_PCT, 0.0, 1.0), "known": true}

func _v3_cost_gauges(card: PanelContainer, vb: VBoxContainer, rows: Array) -> void:
	var bare := StyleBoxEmpty.new()
	bare.set_content_margin_all(4)
	card.add_theme_stylebox_override("panel", bare)
	card.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for r: Dictionary in rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", DS.SP["SM"])
		vb.add_child(line)
		var gid := str(r.get("good_id", ""))
		var good_icon := UIHelpers.make_plain_good_icon(gid, Catalog.get_internal_name(gid), V3_COST_ICON)
		UIHelpers.link_good_icon_to_encyclopedia(good_icon, gid)
		_v3_set_in_well(good_icon)
		line.add_child(good_icon)
		var reading := v3_cost_gauge_reading(float(r.get("unit_cost", -1.0)), float(r.get("market_price", 0.0)))
		var gauge: PanelGauge = PanelGauge.new()
		gauge.name = "CostGauge"
		gauge.gauge_size = V3_GAUGE_SIZE
		gauge.green_percent = 90.0 / V3_GAUGE_SCALE_PCT * 100.0
		gauge.amber_percent = 20.0 / V3_GAUGE_SCALE_PCT * 100.0
		gauge.led_mode = PanelGauge.LedMode.AUTO if bool(reading.known) else PanelGauge.LedMode.OFF
		var key := "cost:%s:%s" % [str(_current_building.get("instance_id", "")), str(r.get("name", ""))]
		var target: float = reading.value
		if _v3_last_readings.has(key):
			gauge.value = float(_v3_last_readings[key])
			gauge.ready.connect(func() -> void: gauge.value = target, CONNECT_ONE_SHOT)
		else:
			gauge.value = target
		_v3_last_readings[key] = target
		# The gauge's render has empty room round its bezel (and its shadow to the bottom-right); the row
		# holds just the bezel and shadow, the gauge overhanging its holder by the rest.
		var holder := Control.new()
		holder.name = "GaugeHolder"
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.custom_minimum_size = Vector2.ONE * V3_GAUGE_SIZE * V3_GAUGE_HELD
		holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		holder.add_child(gauge)
		gauge.position = -Vector2.ONE * V3_GAUGE_SIZE * V3_GAUGE_ROOM
		line.add_child(holder)
		# The gauge is set into the section's dark plate: its holder draws the hole cut for it underneath,
		# in its own coordinates, so the hole can't be left behind when the rows move.
		holder.draw.connect(func() -> void:
			var side := V3_GAUGE_SOCKET.get_size() / 2.0 * (V3_GAUGE_SIZE / V3_GAUGE_SOCKET_AT)
			var centre := gauge.position + gauge.size * 0.5
			holder.draw_texture_rect(V3_GAUGE_SOCKET, Rect2(centre - side * 0.5, side), false))
		gauge.item_rect_changed.connect(holder.queue_redraw)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		col.add_theme_constant_override("separation", 6)
		line.add_child(col)
		# The unit cost on a mini screen in LED segments, lit in its RAG colour, between £ and /unit.
		var price := HBoxContainer.new()
		price.name = "Price"
		price.alignment = BoxContainer.ALIGNMENT_CENTER
		price.add_theme_constant_override("separation", 4)
		col.add_child(price)
		var pound := _v3_metal_label("£", HORIZONTAL_ALIGNMENT_RIGHT)
		pound.add_theme_font_size_override("font_size", 18)
		price.add_child(pound)
		var unit_cost := float(r.get("unit_cost", -1.0))
		var led: Control = BdpV3Led.new()
		led.set_figure("%.2f" % unit_cost if unit_cost >= 0.0 else "--.--", r.get("color", DS.PALETTE["TEXT"]))
		price.add_child(led)
		var per := _v3_metal_label("/unit", HORIZONTAL_ALIGNMENT_LEFT)
		per.uppercase = false
		per.add_theme_font_size_override("font_size", 13)
		price.add_child(per)
		var mkt := Label.new()
		mkt.theme_type_variation = "Caption"
		mkt.text = "Market price £%s" % BuildingStatus._fmt_upto2(float(r.get("market_price", 0.0)))
		mkt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mkt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(mkt)

# --- modifiers (accordion above economics) --------------------------------------------------

## The sign convention each category reads by. Output and workforce are EARNINGS, so more is
## better. Power draw and maintenance are COSTS, so less is better and a negative there is
## green, not red — a research node that cuts a furnace's draw by 10% was being painted as
## damage.
const MOD_CATEGORIES: Array = [
	{"cat": "Output", "good_up": true},
	{"cat": "Workforce", "good_up": true},
	{"cat": "Power draw", "good_up": false},
	{"cat": "Maintenance", "good_up": false},
]

## Everything currently bending this building's numbers — recipe output, workforce, power draw
## and maintenance — behind a chevroned section header that expands on click (collapsed by
## default).
##
## Collapsed, the header carries the ONE number worth a glance: the net effect on OUTPUT. A
## bare count like "3 active" would fold power and maintenance modifiers into a figure the
## player reads as production, and say nothing about which way any of it went.
##
## Expanded, only the per-category summaries carry colour. Painting all fourteen individual
## rows green and red made a wall of traffic lights out of what is really four numbers.
func _add_modifiers_accordion(building: Dictionary, recipe: Dictionary) -> void:
	var by_cat: Dictionary = {}
	var mod: Dictionary = BuildingStatus.net_output_modifier(building, recipe)
	by_cat["Output"] = (mod.get("parts", []) as Array).duplicate()
	by_cat["Workforce"] = (mod.get("workforce_parts", []) as Array).duplicate()
	var bid := str(building.get("building_id", ""))
	by_cat["Power draw"] = (Modifiers.resolve_pct(
		"building_power", bid, {"building_id": bid}).get("parts", []) as Array).duplicate()
	by_cat["Maintenance"] = (Modifiers.resolve_pct(
		"maintenance", bid, {"building_id": bid}).get("parts", []) as Array).duplicate()
	var total := 0
	for cat_key: Variant in by_cat:
		total += (by_cat[cat_key] as Array).size()

	if UiPrefs.use_bdp_v3:
		_v3_modifiers(mod, total, by_cat)
		return

	# Section header doubling as the accordion trigger ("Section" is a Label
	# variation, so a chevron Label + section Label in a clickable row).
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	header.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var chevron := Label.new()
	chevron.theme_type_variation = "Section"
	chevron.text = "▸"
	header.add_child(chevron)
	var title := Label.new()
	title.theme_type_variation = "Section"
	title.text = "Modifiers"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(title)
	var right := Label.new()
	right.theme_type_variation = "Numeric"
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if total == 0:
		right.text = "none"
		right.add_theme_color_override("font_color", DS.PALETTE["TEXT"])
	else:
		var out_pct := float(mod.get("pct_f", float(mod.get("pct", 0))))
		right.text = "Output %s" % _mod_pct_text(out_pct)
		right.add_theme_color_override("font_color", _mod_tone(out_pct, true))
	header.add_child(right)
	header.set_meta("v3_section", "Modifiers")
	_body.add_child(header)

	var card := _make_card()
	card.visible = false
	var vb := card.get_child(0) as VBoxContainer
	vb.add_theme_constant_override("separation", 3)
	_fill_modifiers(vb, total, by_cat)
	_body.add_child(card)

	header.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			header.accept_event()
			card.visible = not card.visible
			chevron.text = "▾" if card.visible else "▸")


## The modifiers card's rows: each category's net figure, the only coloured one, and the modifiers that
## make it up.
func _fill_modifiers(vb: VBoxContainer, total: int, by_cat: Dictionary) -> void:
	if total == 0:
		var none := Label.new()
		none.theme_type_variation = "Caption"
		none.text = "No active modifiers on this building."
		none.add_theme_color_override("font_color", DS.PALETTE["TEXT"])
		vb.add_child(none)
	for entry_value: Variant in MOD_CATEGORIES:
		var entry: Dictionary = entry_value
		var cat := str(entry.get("cat", ""))
		var parts: Array = by_cat.get(cat, [])
		if parts.is_empty():
			continue
		var net := 0.0
		for part_value: Variant in parts:
			net += float((part_value as Dictionary).get("pct", 0.0))
		# The category summary — the only coloured figure in the card.
		var sum_row := HBoxContainer.new()
		sum_row.add_theme_constant_override("separation", DS.SP["SM"])
		var sum_label := Label.new()
		sum_label.theme_type_variation = "Body"
		sum_label.text = cat
		sum_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sum_row.add_child(sum_label)
		var sum_value := Label.new()
		sum_value.theme_type_variation = "Numeric"
		sum_value.text = _mod_pct_text(net)
		sum_value.add_theme_color_override("font_color",
			_mod_tone(net, bool(entry.get("good_up", true))))
		sum_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		sum_row.add_child(sum_value)
		vb.add_child(sum_row)
		# ...and the modifiers that make it up, plainly.
		for part_value: Variant in parts:
			var part: Dictionary = part_value
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", DS.SP["SM"])
			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(DS.SP["MD"], 0)
			spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			line.add_child(spacer)
			var lbl := Label.new()
			lbl.theme_type_variation = "Caption"
			lbl.text = str(part.get("label", ""))
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lbl.custom_minimum_size = Vector2(PANEL_WIDTH - 220.0, 0)
			lbl.add_theme_color_override("font_color", DS.PALETTE["TEXT"])
			line.add_child(lbl)
			var val := Label.new()
			val.theme_type_variation = "Caption"
			val.text = _mod_pct_text(float(part.get("pct", 0.0)))
			val.add_theme_color_override("font_color", DS.PALETTE["TEXT"])
			val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			line.add_child(val)
			vb.add_child(line)


## v3's Modifiers, laid out as Inputs is on the control plate: a % sign raised white on the metal, the
## heading in raised letters over an off-white key with the output modifier printed on it. With modifiers
## active the key opens a white plastic sheet under the row, the rows printed on it in navy (the category
## figures in darker greens and reds, to read on white); it starts open, latches down while open, and
## stays as the player leaves it across rebuilds. With none the key reads None and opens nothing.
const V3_SHEET_WHITE: Texture2D = preload("res://assets/ui/bdp_v3/sheet_white.png")
const V3_SHEET_WHITE_MARGIN := 14.0 / 1.875
const V3_SHEET_WHITE_CORNER := (14.0 + 40.0) * 2.0 / 1.875
const V3_INK := {"ok": Color("#1d6b3a"), "warn": Color("#7a4a00"), "bad": Color("#8f1f19")}
## The % sign and its swept shadow (layout.json mod_icon), in a frame this many layout pixels square.
const V3_MOD_ICON: Texture2D = preload("res://assets/ui/bdp_v3/mod_icon.png")
const V3_MOD_ICON_SHADOW: Texture2D = preload("res://assets/ui/bdp_v3/mod_icon_shadow.png")
const V3_MOD_ICON_FRAME := 110.0
## Whether the Modifiers sheet is open: closed until the player opens it, then kept across rebuilds.
var _v3_modifiers_open := false

func _v3_modifiers(mod: Dictionary, total: int, by_cat: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.name = "ModifiersRow"
	row.set_meta("v3_section", "Modifiers")
	row.add_theme_constant_override("separation", DS.SP["SM"])
	var icon := Control.new()
	icon.name = "ModifiersIcon"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	icon.custom_minimum_size = Vector2.ONE * V3_MOD_ICON_FRAME / 1.875
	icon.size_flags_vertical = Control.SIZE_SHRINK_END
	icon.draw.connect(func() -> void:
		icon.draw_texture_rect(V3_MOD_ICON_SHADOW, Rect2(Vector2.ZERO, icon.size), false)
		icon.draw_texture_rect(V3_MOD_ICON, Rect2(Vector2.ZERO, icon.size), false))
	row.add_child(icon)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)
	var heading: Control = BdpV3Heading.new()
	heading.text = "Modifiers"
	col.add_child(heading)
	var key: Control = BdpV3ModKey.new()
	key.tooltip_text = "Everything bending this building's numbers"
	col.add_child(key)
	_body.add_child(row)
	if total == 0:
		key.summary = "None"
		key.openable = false
		_v3_money_gap()
		return
	var out_pct := float(mod.get("pct_f", float(mod.get("pct", 0))))
	key.summary = "Output %s" % _mod_pct_text(out_pct)
	key.summary_ink = _v3_ink(_mod_tone(out_pct, true))
	key.set_open(_v3_modifiers_open)
	var sheet := PanelContainer.new()
	sheet.name = "ModifiersSheet"
	sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var pad := StyleBoxEmpty.new()
	pad.content_margin_left = 14
	pad.content_margin_right = 14
	pad.content_margin_top = 10
	pad.content_margin_bottom = 12
	sheet.add_theme_stylebox_override("panel", pad)
	sheet.draw.connect(func() -> void:
		BdpV3Nine.paint(sheet, V3_SHEET_WHITE, Rect2(Vector2.ZERO, sheet.size).grow(V3_SHEET_WHITE_MARGIN), V3_SHEET_WHITE_CORNER))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	sheet.add_child(vb)
	_fill_modifiers(vb, total, by_cat)
	sheet.visible = _v3_modifiers_open
	_body.add_child(sheet)
	_v3_money_gap()
	for l: Label in sheet.find_children("*", "Label", true, false):
		l.add_theme_color_override("font_color", _v3_ink(l.get_theme_color("font_color")))
	key.toggled.connect(func(open: bool) -> void:
		_v3_modifiers_open = open
		sheet.visible = open)

## The space the money frame leaves after the modifiers.
func _v3_money_gap() -> void:
	var gap := Control.new()
	gap.name = "ModifiersGap"
	gap.custom_minimum_size = Vector2(0.0, V3_MONEY_GAP)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(gap)

## The ink for a colour the dark panel shows on white plastic: the semantic greens, ambers and reds
## darkened to read on it, and everything else navy.
static func _v3_ink(c: Color) -> Color:
	if c.is_equal_approx(DS.PALETTE["OK"]):
		return V3_INK["ok"]
	if c.is_equal_approx(DS.PALETTE["WARN"]):
		return V3_INK["warn"]
	if c.is_equal_approx(DS.PALETTE["DANGER"]):
		return V3_INK["bad"]
	return BdpV3Plate.NAVY

static func _mod_pct_text(pct: float) -> String:
	return "%s%d%%" % ["+" if pct >= 0.0 else "−", absi(int(round(pct)))]


## Green when the number is in the player's favour, which is NOT the same as positive: an
## output modifier wants to go up, a power-draw or maintenance one wants to go down.
static func _mod_tone(pct: float, good_up: bool) -> Color:
	if absf(pct) < 0.5:
		return DS.PALETTE["TEXT"]
	var good: bool = pct > 0.0 if good_up else pct < 0.0
	return DS.PALETTE["OK"] if good else DS.PALETTE["DANGER"]

# --- economics -----------------------------------------------------------------------------

func _build_economics(econ: Dictionary) -> PanelContainer:
	var card := _make_card()
	var vb := card.get_child(0) as VBoxContainer
	# One "Output value" figure (market worth of the run), tagged (sold) when it actually reaches the
	# market this turn or (if sold) otherwise, plus the freight to its set destination. Net folds both
	# in. Skipped for generators / infra (no sellable good → units_out 0).
	var units_out := int(econ.get("units_out", 0))
	if units_out > 0:
		var output_values: Array = econ.get("output_values", [])
		var selling_count := int(econ.get("selling_output_count", 0))
		var tag := "(sold)" if bool(econ.get("middleman",false)) or selling_count == output_values.size() else ("(part sold)" if selling_count > 0 else "(if sold)")
		vb.add_child(_metric("Output value %s" % tag, "+£%.2f" % float(econ.get("output_value", 0.0)), DS.PALETTE["OK"], false))
		var tc := float(econ.get("transport_cost", 0.0))
		if tc > 0.0:
			vb.add_child(_metric("Transport cost", "−£%.2f" % tc, DS.PALETTE["DANGER"], false))
	var intermediary_fee := float(econ.get("logistics_intermediary_fee", econ.get("middleman_fee", 0.0)))
	if intermediary_fee > 0.0:
		vb.add_child(_metric("Logistics Intermediary Fee", "−£%.2f" % intermediary_fee, DS.PALETTE["DANGER"], false))
	var input_cost := float(econ.get("input_cost", 0.0))
	if input_cost > 0.0:
		vb.add_child(_metric("Inputs / turn", "−£%.2f" % input_cost, DS.PALETTE["DANGER"], false))
	vb.add_child(_metric("Maintenance / turn", "−£%.2f" % float(econ.get("maintenance", 0.0)), DS.PALETTE["DANGER"], false))
	vb.add_child(_metric("Labour / turn", "−£%.2f" % float(econ.get("labour_cost", 0.0)), DS.PALETTE["DANGER"], false))
	var power_cost := float(econ.get("power_cost", 0.0))
	if power_cost > 0.0:
		vb.add_child(_metric("Power / turn", "−£%.2f" % power_cost, DS.PALETTE["DANGER"], false))
	var warehousing := float(econ.get("warehousing_cost", 0.0))
	if warehousing > 0.0:
		vb.add_child(_metric("Warehousing / turn", "−£%.2f" % warehousing, DS.PALETTE["DANGER"], false))
	var financing_per_turn := _add_carried_rows(vb)
	# Carbon levy on this recipe's taxed inputs (only shown once the policy is in force).
	var carbon_tax := float(econ.get("carbon_tax", 0.0))
	if carbon_tax > 0.0:
		vb.add_child(_metric("Carbon tax / turn", "−£%.2f" % carbon_tax, DS.PALETTE["DANGER"], false))
	vb.add_child(HSeparator.new())
	# Operations net (output − running costs) minus this building's own build financing, so the
	# bottom line reflects the cash it actually contributes while its construction debt is live.
	var net := float(econ.get("net", 0.0)) - financing_per_turn
	vb.add_child(_metric("Net / turn", "%s£%.2f" % ["+" if net >= 0.0 else "−", absf(net)], DS.PALETTE["OK"] if net >= 0.0 else DS.PALETTE["DANGER"], true))
	return card

## Carried costs and held stock, both money or goods the player owns but cannot see on the tile, so they
## get a line in the economics rather than living only in the sim: this building's loan repayment and
## what is stored for it. Returns the repayment per turn.
func _add_carried_rows(vb: VBoxContainer) -> float:
	var iid_econ := str(_current_building.get("instance_id", ""))
	# The REPAYMENT, not the outstanding tab: what it takes a turn and how many turns are
	# left to run. The total is still there to read — it is this figure
	# times the turns — but the per-turn cost is what a player plans around.
	# Financing this building carries per turn: the deferred build-cost tab AND any construction
	# loan taken to build it (tag_last_loan_building tied it to this instance). Both are shown in
	# the one "Loan repayment" line and — unlike before — folded into the Net below, so the bottom
	# line is the cash this building actually leaves the company after servicing its own build debt.
	# General empire loans are excluded on purpose; they live at the company level.
	var tab_pay: Dictionary = MatchState.building_tab_repayment(iid_econ)
	var tab_per := float(tab_pay.get("per_turn", 0.0)) if float(tab_pay.get("accrued", 0.0)) > 0.0 else 0.0
	var loan_pay: Dictionary = LoanState.building_loan_repayment(iid_econ)
	var loan_per := float(loan_pay.get("per_turn", 0.0))
	var financing_per_turn := tab_per + loan_per
	if financing_per_turn > 0.0:
		var turns_left := maxi(int(tab_pay.get("turns_left", 0)), int(loan_pay.get("turns_left", 0)))
		var starts_in := int(tab_pay.get("starts_in", 0))
		var value := "−£%.2f  (%d turns)" % [financing_per_turn, turns_left]
		if starts_in > 0 and loan_per <= 0.0:
			value = "−£%.2f  (%d turns, starts in %d)" % [financing_per_turn, turns_left, starts_in]
		vb.add_child(_metric("Loan repayment", value, DS.PALETTE["WARN"], false))
	var held := MatchState.ghost_holding_units(iid_econ)
	if held > 0:
		vb.add_child(_metric("Stored for this building", "%d units" % held, DS.PALETTE["TEXT_MUTED"], false))
	return financing_per_turn

## v3's economics (BuildingEconomics.per_turn), on the frame's steel:
##   Value added in production   its output less inputs, labour and upkeep; opens to show each;
##   Transport costs             bringing its inputs in and taking its output to market; opens to show
##                               each side's cost by how it goes;
##   Net Value Added             the first less the second;
## every figure on a mini screen in LED segments after a printed £ (results green, or red below zero;
## costs red); then its revenue and its costs as two bars on one scale; then a lamp for each side's
## transport, with its icon, lit by transport's share of that side's goods (or flagged free: a mine's
## inputs, a power plant's output). Loan repayments and stored goods follow, as in v2.
const V3_ECON_ICON_PX := 30.0
const V3_ECON_INDENT := 22.0
## A row nested in another opens from a smaller key.
const V3_NESTED_KEY_SCALE := 0.8
## The space the money frame leaves after the modifiers and after the economics.
const V3_MONEY_GAP := 14.0
## Which of v3's economics rows are open, kept across rebuilds.
var _v3_econ_open := {}
## The digits every economics screen shows while they are built, so they are one width and their £
## signs line up.
var _v3_led_digits := 0

func _build_economics_v3(econ: Dictionary) -> PanelContainer:
	var card := _make_card()
	card.name = "EconomicsV3"
	var bare := StyleBoxEmpty.new()
	bare.set_content_margin_all(4)
	bare.content_margin_bottom = 4 + V3_MONEY_GAP
	card.add_theme_stylebox_override("panel", bare)
	var vb := card.get_child(0) as VBoxContainer
	vb.add_theme_constant_override("separation", DS.SP["MD"])
	var ok: Color = DS.PALETTE["OK"]
	var bad: Color = DS.PALETTE["DANGER"]
	var made: Array = [["Output (if sold)" if not bool(econ.get("sold", true)) else "Output", float(econ.output_value), ok]]
	if not bool(econ.get("inputs_free", false)):
		made.append(["Inputs", float(econ.input_value), bad])
	made.append(["Labour", float(econ.labour), bad])
	made.append(["Upkeep", float(econ.upkeep), bad])
	var va := float(econ.value_added)
	# Transport opens to each side, and each side to its goods: every good's freight by how it goes,
	# and its port charge, on their own rows.
	var sides: Array = []
	for side in [["Inputs", "inputs", "transport_in"], ["Outputs", "outputs", "transport_out"]]:
		var goods: Array = []
		for line: Dictionary in econ.get(side[1], []):
			var gid := str(line.get("good_id", ""))
			for m: Dictionary in BuildingEconomics.line_methods(line):
				goods.append(["%s · %s" % ["Power" if gid == "power" else Catalog.get_display_name(gid), m.name], float(m.cost), bad])
		if not goods.is_empty():
			sides.append([side[0], "transport_" + side[1], float(econ[side[2]]), goods])
	var transport := float(econ.transport)
	var figures: Array = [va, transport, float(econ.net_value_added)]
	for part: Array in made:
		figures.append(float(part[1]))
	for sd: Array in sides:
		figures.append(float(sd[2]))
		for part: Array in sd[3]:
			figures.append(float(part[1]))
	_v3_led_digits = 0
	for f: float in figures:
		_v3_led_digits = maxi(_v3_led_digits, BdpV3Led.cells_for("%.2f" % f).size())
	var moved: Array = []
	for sd: Array in sides:
		moved.append(_v3_econ_accordion("Transport" + str(sd[0]), str(sd[1]), str(sd[0]), float(sd[2]), bad, sd[3], V3_NESTED_KEY_SCALE))
	vb.add_child(_v3_econ_accordion("ValueAdded", "value_added", "Value added in production", va, ok if va >= 0.0 else bad, made))
	vb.add_child(_v3_econ_accordion("Transport", "transport", "Transport costs", transport, bad if transport > 0.0 else ok, moved))
	var nva := float(econ.net_value_added)
	var net := _v3_econ_line("Net Value Added", nva, ok if nva >= 0.0 else bad, true)
	net.name = "NetValueAdded"
	net.tooltip_text = "Before tax"
	vb.add_child(net)
	var bar: Control = BdpV3ValueBar.new()
	bar.set_values(econ)
	vb.add_child(bar)
	var lamps := HBoxContainer.new()
	lamps.name = "TransportLamps"
	lamps.add_theme_constant_override("separation", DS.SP["MD"])
	vb.add_child(lamps)
	lamps.add_child(_v3_transport_lamp("inputs", str(econ.lamp_in), float(econ.transport_in),
		"Inputs free" if bool(econ.inputs_free) else ""))
	lamps.add_child(_v3_transport_lamp("outputs", str(econ.lamp_out), float(econ.transport_out),
		"Output free to ship" if bool(econ.output_free_to_ship) else ""))
	_add_carried_rows(vb)
	return card

## One of v3's economics figures: its name, a printed £ and the figure on an LED screen in `colour`.
func _v3_econ_line(title: String, figure: float, colour: Color, strong: bool = false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DS.SP["SM"])
	var t := Label.new()
	t.theme_type_variation = "Body" if strong else "Caption"
	t.text = title
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if strong:
		t.add_theme_font_size_override("font_size", 17)
	row.add_child(t)
	row.add_child(_v3_money_led(figure, colour, _v3_led_digits))
	return row

## A £ figure, as the cost to produce shows it: a printed £ and the figure on an LED screen, showing at
## least `digits` digits (blank ones leading) so a column of them is one width.
func _v3_money_led(figure: float, colour: Color, digits := 0) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.name = "MoneyLed"
	hb.add_theme_constant_override("separation", 4)
	hb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pound := _v3_metal_label("£", HORIZONTAL_ALIGNMENT_RIGHT)
	pound.add_theme_font_size_override("font_size", 18)
	hb.add_child(pound)
	var led: Control = BdpV3Led.new()
	var text := "%.2f" % figure
	led.set_figure(" ".repeat(maxi(0, digits - BdpV3Led.cells_for(text).size())) + text, colour)
	hb.add_child(led)
	return hb

## One of v3's economics rows that opens: a wide worn-white key with its name printed in navy and a
## chevron (BdpV3ModKey, as Modifiers has), its figure on a screen beside it; the key latches down while
## the row is open, showing the figures that make it, indented under it, each on its own screen. A part
## is [name, figure, colour], or a row that opens in its turn (built by this, with a smaller key). With
## nothing to show under it, it is a plain row.
func _v3_econ_accordion(node_name: String, key: String, title: String, figure: float, colour: Color, parts: Array, key_scale := 1.0) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = node_name
	box.add_theme_constant_override("separation", DS.SP["SM"])
	if parts.is_empty():
		var plain := _v3_econ_line(title, figure, colour, true)
		plain.name = "Head"
		box.add_child(plain)
		return box
	var head := HBoxContainer.new()
	head.name = "Head"
	head.add_theme_constant_override("separation", DS.SP["MD"])
	box.add_child(head)
	var opener: Control = BdpV3ModKey.new()
	opener.summary = title
	opener.key_scale = key_scale
	head.add_child(opener)
	head.add_child(_v3_money_led(figure, colour, _v3_led_digits))
	var nested := VBoxContainer.new()
	nested.name = "Parts"
	nested.add_theme_constant_override("separation", 4)
	var indent := MarginContainer.new()
	indent.add_theme_constant_override("margin_left", roundi(V3_ECON_INDENT))
	indent.add_child(nested)
	box.add_child(indent)
	for p: Variant in parts:
		nested.add_child(p if p is Control else _v3_econ_line(str(p[0]), float(p[1]), p[2]))
	indent.visible = bool(_v3_econ_open.get(key, false))
	opener.set_open(indent.visible)
	opener.toggled.connect(func(open: bool) -> void:
		indent.visible = open
		_v3_econ_open[key] = open)
	return box

## A transport lamp: the side's raised icon, its lamp, and what its transport costs a turn, or a flag
## when that side travels free.
func _v3_transport_lamp(side: String, tone: String, cost: float, free_flag: String) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.name = "Lamp" + side.capitalize()
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_theme_constant_override("separation", 6)
	var icon := Control.new()
	icon.name = "Icon"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	icon.custom_minimum_size = Vector2.ONE * V3_ECON_ICON_PX
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var face: Texture2D = load("res://assets/ui/bdp_v3/econ_icon_%s.png" % side)
	var shadow: Texture2D = load("res://assets/ui/bdp_v3/econ_icon_%s_shadow.png" % side)
	icon.draw.connect(func() -> void:
		icon.draw_texture_rect(shadow, Rect2(Vector2.ZERO, icon.size), false)
		icon.draw_texture_rect(face, Rect2(Vector2.ZERO, icon.size), false))
	hb.add_child(icon)
	var lamp := BdpV3Lamp.new()
	lamp.name = "TransportLamp"
	lamp.lamp_scale = V3_DIAG_LAMP_SCALE
	lamp.set_tone(tone)
	hb.add_child(lamp)
	var col := VBoxContainer.new()
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 0)
	hb.add_child(col)
	col.add_child(_v3_metal_label("%s transport" % side.capitalize(), HORIZONTAL_ALIGNMENT_LEFT))
	var value := Label.new()
	value.theme_type_variation = "Caption"
	value.text = free_flag if free_flag != "" else "%s/turn" % _money(cost)
	col.add_child(value)
	return hb

static func _money(v: float) -> String:
	return "%s£%.2f" % ["−" if v < 0.0 else "", absf(v)]

func _metric(key: String, value: String, value_color: Color, strong: bool) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", DS.SP["SM"])
	if key.begins_with("Maintenance") or key.begins_with("Labour"):
		hb.add_child(EffectEmblem.make("gears" if key.begins_with("Maintenance") else "engineer", 26.0))
	var k := Label.new()
	k.theme_type_variation = "Body" if strong else "Caption"
	k.text = key
	k.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	k.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(k)
	var v := Label.new()
	v.theme_type_variation = "Numeric"
	v.text = value
	v.add_theme_color_override("font_color", value_color)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hb.add_child(v)
	return hb

# --- power line ----------------------------------------------------------------------------

func _build_power_line(pw: Dictionary) -> PanelContainer:
	var card := _make_card()
	var vb := card.get_child(0) as VBoxContainer
	var lbl := Label.new()
	lbl.theme_type_variation = "Caption"
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.text = "Draws %d MW · %s" % [int(pw.get("amount", 0)), BuildingReadout.power_state_text(str(pw.get("state", "none")))]
	vb.add_child(lbl)
	return card

# --- inbound shipments ---------------------------------------------------------------------

func _build_shipments(ships: Array) -> PanelContainer:
	if UiPrefs.use_bdp_v3:
		return _build_shipments_v3(ships)
	var card := _make_card()
	var vb := card.get_child(0) as VBoxContainer
	vb.add_theme_constant_override("separation", DS.SP["MD"])
	for i in ships.size():
		var s: Dictionary = ships[i]
		if i > 0:
			vb.add_child(HSeparator.new())
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", DS.SP["MD"])
		vb.add_child(hb)
		# market-panel-sized framed good icon
		var icon := _good_icon_pill(str(s.get("good_id", "")), str(s.get("internal", "")), int(s.get("need", 0)), MARKET_ICON)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(icon)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		col.add_theme_constant_override("separation", 0)
		hb.add_child(col)
		var stored := int(s.get("stored", 0))
		var need := int(s.get("need", 0))
		var top := Label.new()
		top.theme_type_variation = "Body"
		var _inbound := int(s.get("inbound", 0))
		var _available := stored + _inbound   # on tile + in transit; shown even if it exceeds need
		if _inbound > 0:
			top.text = "%s — %d on tile +%d arriving / %d needed" % [str(s.get("name", "")), stored, _inbound, need]
		else:
			top.text = "%s — %d/%d stored" % [str(s.get("name", "")), stored, need]
		top.add_theme_color_override("font_color", DS.PALETTE["OK"] if _available >= need else DS.PALETTE["WARN"])
		col.add_child(top)
		var sub := Label.new()
		sub.theme_type_variation = "Caption"
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var inbound := int(s.get("inbound", 0))
		if inbound > 0:
			var eta := int(s.get("eta_turns", -1))
			var eta_txt := ("next turn" if eta <= 1 else "in %d turns" % eta)
			sub.text = "%d inbound from %s · %s" % [inbound, str(s.get("from", "unknown")), eta_txt]
		else:
			sub.text = "no inbound shipment scheduled"
		col.add_child(sub)
	return card

## v3's inbound shipments: a bay with room for six goods, two to a row, each good's icon and a lamp
## beside it, and no text. The goods fill the bottom row first and the rows above it after; the bay's
## rolling door comes down over the rows no good needs (two with one or two inputs, one with three or
## four) and with every row in use it stays rolled up in its housing, so the bay is the same height
## whatever the recipe. The lamp is green with enough in stock to run, amber when short with something on
## its way (an inbound shipment or the logistics intermediary), red when short with nothing coming. Each
## icon's hover gives the good, what is stored, what a run needs and how it is supplied, and still opens
## the encyclopedia.
const V3_SHIP_ICON := 96
const V3_SHIP_ROWS := 3
const V3_SHIP_GAP := 12
const V3_SHIP_LAMP_SCALE := 0.62

## How many of the bay's rows the door covers for `goods` goods.
static func v3_door_rows(goods: int) -> int:
	return maxi(0, V3_SHIP_ROWS - ceili(goods / 2.0))

static func v3_stock_tone(stored: int, need: int, inbound: int, on_intermediary: bool) -> String:
	if stored >= need:
		return "ok"
	return "warn" if inbound > 0 or on_intermediary else "bad"

func _build_shipments_v3(ships: Array) -> PanelContainer:
	var card := _make_card()
	card.name = "ShipmentsV3"
	var bare := StyleBoxEmpty.new()
	bare.set_content_margin_all(4)
	card.add_theme_stylebox_override("panel", bare)
	var vb := card.get_child(0) as VBoxContainer
	vb.add_theme_constant_override("separation", V3_SHIP_GAP)
	var door: Control = BdpV3Door.new()
	door.reach = BdpV3Section.PADDING + 4.0
	door.custom_minimum_size.y = BdpV3Door.rolled_up_height() + v3_door_rows(ships.size()) * (V3_SHIP_ICON + V3_SHIP_GAP)
	vb.add_child(door)
	var chunks: Array = []
	for i in range(0, ships.size(), 2):
		chunks.append(ships.slice(i, i + 2))
	for i in range(chunks.size() - 1, -1, -1):
		vb.add_child(_v3_ship_row(chunks[i]))
	return card

func _v3_ship_row(goods: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DS.SP["MD"])
	row.custom_minimum_size.y = V3_SHIP_ICON
	var recipe: Dictionary = Catalog.get_recipe(str(_current_building.get("recipe_id", "")))
	for i in 2:
		var cell := HBoxContainer.new()
		cell.name = "ShipmentCell"
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.alignment = BoxContainer.ALIGNMENT_CENTER
		cell.add_theme_constant_override("separation", DS.SP["SM"])
		row.add_child(cell)
		if i >= goods.size():
			continue   # an odd good out keeps its half of the row
		cell.set_meta("v3_shipment_cell", true)   # Godot renames same-named siblings; this survives it
		var s: Dictionary = goods[i]
		var gid := str(s.get("good_id", ""))
		var stored := int(s.get("stored", 0))
		var need := int(s.get("need", 0))
		var inbound := int(s.get("inbound", 0))
		var supply := BuildingEconomics.input_supply(_current_building, recipe, gid, str(s.get("from", "")))
		var icon := _good_icon_pill(gid, str(s.get("internal", "")), need, V3_SHIP_ICON, -1, 0, true)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_v3_set_in_well(icon)
		var lines := PackedStringArray(["Stored: %d" % stored, "Needed to run: %d" % need, "Supplied by: %s" % supply])
		if inbound > 0:
			var eta := int(s.get("eta_turns", -1))
			lines.append("Inbound: %d, %s" % [inbound, "next turn" if eta <= 1 else "in %d turns" % eta])
		else:
			lines.append("Nothing inbound")
		icon.detail_lines = lines
		cell.add_child(icon)
		var lamp := BdpV3Lamp.new()
		lamp.name = "StockLamp"
		lamp.lamp_scale = V3_SHIP_LAMP_SCALE
		lamp.set_tone(v3_stock_tone(stored, need, inbound, supply == "Logistics intermediary"))
		lamp.tooltip_text = "Supplied by: %s" % supply
		cell.add_child(lamp)
	return row

# --- routing (read-only summary + map highlight) -------------------------------------------

func _build_routing_buttons(building: Dictionary, recipe: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DS.SP["SM"])
	if not (recipe.get("inputs", []) as Array).is_empty():
		row.add_child(_logistics_side_control(building, recipe, "input"))
	var out_card := _logistics_side_control(building, recipe, "output")
	out_card.name = "OutputDestCard"   # tutorial spotlight target
	row.add_child(out_card)
	return row

func _logistics_side_control(building: Dictionary, recipe: Dictionary, side: String) -> Control:
	var service = preload("res://scripts/middleman_service.gd")
	var active: bool = service.side_all_middleman(str(building.instance_id), side)
	# Until Open Logistics Contracts is unlocked, keep the original Inputs / Outputs
	# route cards as the primary actions. The Manage Logistics CTA is only meaningful
	# once the alternative route choices can actually be opened.
	var manage_unlocked := service.eligible(building) and ResearchState.open_logistics_contracts_available()
	var open := func() -> void:
		if side == "input": _open_input_sources_sheet(building, recipe)
		else: _open_output_sheet(building, recipe)
	if not active or not manage_unlocked:
		return _route_card("Inputs" if side == "input" else "Outputs", _input_summary(building, recipe) if side == "input" else _output_summary(building, recipe), open, INPUT_ICON if side == "input" else OUTPUT_ICON)
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var st := StyleBoxFlat.new()
	st.bg_color = DS.PALETTE["BG_CARD"]
	st.border_color = DS.PALETTE["BORDER_SOFT"]
	st.set_border_width_all(1)
	st.set_corner_radius_all(10)
	st.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", st)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	card.add_child(body)
	var side_icon := _off_white_icon_rect(INPUT_ICON if side == "input" else OUTPUT_ICON, Vector2(44, 68))
	side_icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(side_icon)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	body.add_child(col)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 6)
	col.add_child(heading)
	var label := Label.new()
	label.text = "INPUTS" if side == "input" else "OUTPUTS"
	label.theme_type_variation = "Caption"
	label.add_theme_color_override("font_color", DS.PALETTE["TEXT_DIM"])
	heading.add_child(label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	col.add_child(row)
	var route_icon := _off_white_icon_rect(ROUTE_MIDDLEMAN_ICON, Vector2(26, 26))
	route_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(route_icon)
	var button := Button.new()
	button.name = "ManageInputLogistics" if side == "input" else "ManageOutputLogistics"
	button.text = "Manage Logistics"
	button.add_theme_font_size_override("font_size", 14)
	button.pressed.connect(open)
	row.add_child(button)
	return card

func _input_summary(building: Dictionary, recipe: Dictionary) -> String:
	var service = preload("res://scripts/middleman_service.gd")
	var iid := str(building.instance_id)
	if service.side_all_middleman(iid, "input"): return "Logistics intermediary"
	var handover_turns := -1
	for item: Dictionary in recipe.get("inputs", []):
		var gid := str(item.get("good_id", ""))
		if service.in_handover(iid, gid):
			var turns: int = service.handover_turns(iid, gid)
			handover_turns = turns if handover_turns < 0 else mini(handover_turns, turns)
	if handover_turns > 0:
		return "Switching suppliers: first input from the market in %d turn%s" % [handover_turns, "" if handover_turns == 1 else "s"]
	if service.enabled(iid) and (recipe.get("inputs", []) as Array).any(func(item: Dictionary) -> bool: return service.supplies_good(iid, str(item.get("good_id", "")))): return "Mixed logistics"
	var names: Array = []
	for s in BuildingReadout.input_sources(building, recipe):
		var nm := str(s.get("building_name", ""))
		if not names.has(nm):
			names.append(nm)
	return ", ".join(names) if not names.is_empty() else "Market / unlinked"

func _output_summary(building: Dictionary, recipe: Dictionary) -> String:
	if str(recipe.get("output_name", "")) == "power": return "Electricity grid"
	var service = preload("res://scripts/middleman_service.gd")
	var iid_for_output := str(building.instance_id)
	if service.side_all_middleman(iid_for_output, "output"): return "Logistics intermediary"
	if service.enabled(iid_for_output) and (recipe.get("outputs", []) as Array).any(func(item: Dictionary) -> bool: return service.buys_output(iid_for_output, str(item.get("good_id", "")))): return "Mixed logistics"
	var iid := str(building.get("instance_id", ""))
	var gid := BuildingStatus.primary_output_good_id(recipe)
	var split := MatchState.get_output_split_destinations(iid, gid)
	if split.size() >= 2:
		var produced := BuildingStatus.primary_output_qty(recipe)
		var remaining := produced
		var automatic: Array = []
		var quantities: Dictionary = {}
		for destination in split:
			var requested := int((destination as Dictionary).get("qty", 0))
			var tile_id := str((destination as Dictionary).get("tile_id", ""))
			if requested > 0:
				quantities[tile_id] = mini(requested, remaining)
				remaining -= int(quantities[tile_id])
			else:
				automatic.append(destination)
		for index in automatic.size():
			var tile_id := str((automatic[index] as Dictionary).get("tile_id", ""))
			var share := ceili(float(remaining) / float(automatic.size() - index)) if remaining > 0 else 0
			quantities[tile_id] = share
			remaining -= share
		var lines: Array = []
		for destination in split:
			var tile_id := str((destination as Dictionary).get("tile_id", ""))
			lines.append("%s: %d" % [Catalog.tile_label(tile_id), int(quantities.get(tile_id, 0))])
		return "\n".join(lines)
	var route := BuildingReadout.output_route(building, recipe)
	var dest := str(route.get("destination", "—"))
	if not bool(route.get("reachable", true)):
		dest += " · no route"
	# Quantity-capped tile route (CTRL+click flow): show the split — what ships out
	# and what stays behind, each on its own line (the card grows to fit).
	var cap := MatchState.get_output_ship_quantity(iid, gid)
	if cap > 0 and not bool(route.get("has_market", false)):
		var produced := BuildingStatus.primary_output_qty(recipe)
		var lines := "Sending %d to %s" % [mini(cap, produced), dest]
		var rest := maxi(0, produced - cap)
		if rest > 0:
			lines += "\nSending %d to tile stockpile" % rest
		return lines
	return dest

# A clickable routing card (LABEL kicker + value + chevron) → opens a sheet. A PanelContainer,
# because Buttons don't size to child containers (the DS clickable-card pattern).
func _route_card(label: String, value: String, on_press: Callable, icon_texture: Texture2D = null) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var st := StyleBoxFlat.new()
	st.bg_color = DS.PALETTE["BG_CARD"]
	st.border_color = DS.PALETTE["BORDER_SOFT"]
	st.set_border_width_all(1)
	st.set_corner_radius_all(10)
	st.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", st)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			on_press.call())
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	card.add_child(body)
	var side_icon: TextureRect = null
	if icon_texture != null:
		side_icon = _off_white_icon_rect(icon_texture, Vector2(44, 68))
		side_icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body.add_child(side_icon)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(vb)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 6)
	vb.add_child(heading)
	var l := Label.new()
	l.theme_type_variation = "Caption"
	l.text = label.to_upper()
	l.add_theme_color_override("font_color", DS.PALETTE["TEXT_DIM"])
	heading.add_child(l)
	var vrow := HBoxContainer.new()
	vrow.add_theme_constant_override("separation", DS.SP["SM"])
	vb.add_child(vrow)
	var v := Label.new()
	v.theme_type_variation = "Body"
	v.text = value
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vrow.add_child(v)
	var chev := Label.new()
	chev.text = "›"
	chev.add_theme_color_override("font_color", DS.PALETTE["TEXT_DIM"])
	vrow.add_child(chev)
	return card

func _off_white_icon_rect(texture: Texture2D, size: Vector2) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = texture
	icon.custom_minimum_size = size
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; uniform vec4 ink : source_color; void fragment(){ COLOR = vec4(ink.rgb, texture(TEXTURE, UV).a * ink.a); }"
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("ink", CREAM)
	icon.material = material
	return icon

func _open_input_sources_sheet(building: Dictionary, recipe: Dictionary) -> void:
	var iid := str(building.get("instance_id", ""))
	_open_sheet("Input sources", func(vb: VBoxContainer) -> void:
		_add_logistics_options(vb,building,"input")
		# Group linked producers by input good so each good gets its own section.
		var producers: Dictionary = {}
		for s in BuildingReadout.input_sources(building, recipe):
			var g := str(s.get("good_id", ""))
			if not producers.has(g):
				producers[g] = []
			producers[g].append(s)
		var inputs: Array = recipe.get("inputs", [])
		var market_available := str(MatchState.ruleset.get("logistics_model", "")) != "middleman_v1" or ResearchState.global_trade_license_available()
		for ii in inputs.size():
			var inp: Dictionary = inputs[ii]
			var gid := str(inp.get("good_id", ""))
			var internal := str(inp.get("internal_name", ""))
			if ii > 0:
				vb.add_child(HSeparator.new())
			# Each material has independent primary/fallback slots, shown exactly as the
			# simulation will run them: tile stock is always used first, and the fallback
			# decides who covers any shortfall.
			var route: Dictionary = preload("res://scripts/middleman_service.gd").input_source_route(iid, gid)
			var srcs: Array = producers.get(gid, [])
			_add_input_good_group(vb, building, recipe, gid, internal, int(inp.get("qty", 0)), route, market_available, srcs)
	)

func _input_route_choices(building: Dictionary, gid: String, slot: String, market_available: bool) -> Array:
	var choices: Array = []
	var stockpile_available := ResearchState.open_logistics_contracts_available()
	choices.append({
		"source": "stockpile",
		"title": "This tile's stockpile",
		"detail": "Consume from the stockpile on the building's tile." if stockpile_available else "[Requires Open Logistics Contracts]",
		"enabled": stockpile_available,
	})
	choices.append({
		"source": "market",
		"title": "Global market",
		"detail": "Buy through the nearest port when the tile's available goods are short." if market_available else "[Requires Government Import/Export License]",
		"enabled": market_available,
	})
	var service = preload("res://scripts/middleman_service.gd")
	if not service.eligible(building):
		return choices
	var middleman_available := service.material_tradeable(gid, "input")
	choices.append({
		"source": "middleman",
		"title": "Logistics Intermediary",
		"detail": ("Buys this input for the building each turn; transport and storage are in its fee." if slot == "primary"
			else "Buys only what the tile stock does not cover this turn; its fee applies to those units.") if middleman_available else "Logistics Intermediary unavailable for this input.",
		"enabled": middleman_available,
	})
	return choices

func _add_input_good_group(vb: VBoxContainer, building: Dictionary, recipe: Dictionary, gid: String, internal: String, qty: int, route: Dictionary, market_available: bool, producers: Array) -> void:
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", 6)
	var chooser := HBoxContainer.new()
	chooser.alignment = BoxContainer.ALIGNMENT_CENTER
	chooser.add_theme_constant_override("separation", 10)
	var good_icon := _good_icon_pill(gid, internal, qty, 92)
	good_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chooser.add_child(good_icon)
	var slot_col := VBoxContainer.new()
	slot_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot_col.alignment = BoxContainer.ALIGNMENT_CENTER
	slot_col.add_theme_constant_override("separation", 6)
	slot_col.add_child(_input_route_slot_row(building, recipe, gid, route, market_available, "primary"))
	# A fallback only applies to physical routes; the intermediary as primary buys it all.
	if _input_has_fallback(building, route):
		slot_col.add_child(_input_route_slot_row(building, recipe, gid, route, market_available, "fallback"))
	elif preload("res://scripts/middleman_service.gd").eligible(building):
		slot_col.add_child(_fallback_not_needed_note())
	chooser.add_child(slot_col)
	group.add_child(chooser)
	group.add_child(_route_details_section(building, gid, qty, route, producers))
	vb.add_child(group)

## Where the fallback row would be: the intermediary as primary already buys the whole input.
func _fallback_not_needed_note() -> Control:
	var box := VBoxContainer.new()
	box.name = "FallbackNotNeeded"
	box.add_theme_constant_override("separation", 2)
	var heading := Label.new()
	heading.theme_type_variation = "Caption"
	heading.text = "FALLBACK"
	heading.add_theme_color_override("font_color", DS.PALETTE["TEXT"])
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(heading)
	var note := Label.new()
	note.theme_type_variation = "Caption"
	note.text = "Not needed: the Logistics Intermediary buys all of this input. Choose another primary to set a fallback."
	note.add_theme_color_override("font_color", DS.PALETTE["TEXT"])
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(260, 0)
	box.add_child(note)
	return box

func _input_has_fallback(building: Dictionary, route: Dictionary) -> bool:
	return preload("res://scripts/middleman_service.gd").eligible(building) and str(route.get("primary", "")) != "middleman"

func _input_route_slot_row(building: Dictionary, recipe: Dictionary, gid: String, route: Dictionary, market_available: bool, slot: String) -> Control:
	var iid := str(building.get("instance_id", ""))
	var slot_box := VBoxContainer.new()
	slot_box.alignment = BoxContainer.ALIGNMENT_CENTER
	slot_box.add_theme_constant_override("separation", 2)
	var slot_label := Label.new()
	slot_label.theme_type_variation = "Caption"
	slot_label.text = "PRIMARY" if slot == "primary" else "FALLBACK"
	slot_label.add_theme_color_override("font_color", DS.PALETTE["TEXT_DIM"])
	slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot_box.add_child(slot_label)
	var centered := CenterContainer.new()
	centered.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var selected_source := str(route.get(slot, ""))
	var service_game: bool = preload("res://scripts/middleman_service.gd").eligible(building)
	# Without the intermediary there is no fallback row: "Global market" means tile stock
	# first with market top-up, "This tile's stockpile" means tile stock only.
	if not service_game and slot == "primary" and str(route.get("fallback", "")) == "market":
		selected_source = "market"
	for choice: Dictionary in _input_route_choices(building, gid, slot, market_available):
		var source := str(choice.get("source", ""))
		var title := str(choice.get("title", ""))
		var detail := str(choice.get("detail", ""))
		var enabled := bool(choice.get("enabled", true))
		var selected := selected_source == source or (source == "stockpile" and selected_source.begins_with("tile:"))
		row.add_child(_dest_option(title, detail, selected, func() -> void:
			var service = preload("res://scripts/middleman_service.gd")
			var result: Dictionary = service.set_input_route(iid, gid, slot, source)
			if bool(result.get("ok", false)) and not service_game and slot == "primary" and source == "stockpile":
				result = service.set_input_route(iid, gid, "fallback", "")
			if not bool(result.get("ok", false)):
				MatchState.request_toast(str(result.get("reason", "Unable to change input source.")), "warning")
			_queue_refresh()
			_open_input_sources_sheet(building, recipe), enabled))
	centered.add_child(row)
	slot_box.add_child(centered)
	return slot_box

func _route_details_section(building: Dictionary, gid: String, qty: int, route: Dictionary, producers: Array = []) -> Control:
	var panel := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = DS.PALETTE["BG_INSET"]
	st.border_color = Color(DS.PALETTE["BORDER_SOFT"].r, DS.PALETTE["BORDER_SOFT"].g, DS.PALETTE["BORDER_SOFT"].b, 0.45)
	st.set_border_width_all(1)
	st.set_corner_radius_all(7)
	st.set_content_margin_all(7)
	panel.add_theme_stylebox_override("panel", st)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 3)
	panel.add_child(body)
	var toggle := Button.new()
	toggle.flat = true
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.text = "Route details [-]"
	toggle.toggle_mode = true
	toggle.set_pressed_no_signal(true)
	toggle.custom_minimum_size = Vector2(0, 28)
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	toggle.add_theme_color_override("font_color", DS.PALETTE["TEXT_DIM"])
	body.add_child(toggle)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 2)
	body.add_child(rows)
	var primary := Label.new()
	primary.theme_type_variation = "Caption"
	primary.text = _route_detail_line(building, gid, qty, str(route.get("primary", "")), "PRIMARY")
	primary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(primary)
	if _input_has_fallback(building, route):
		var fallback := Label.new()
		fallback.theme_type_variation = "Caption"
		fallback.text = _route_detail_line(building, gid, qty, str(route.get("fallback", "")), "FALLBACK")
		fallback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rows.add_child(fallback)
	var handover := _handover_line(building, gid)
	if handover != null:
		rows.add_child(handover)
	if not producers.is_empty():
		var supplied := Label.new()
		supplied.theme_type_variation = "Caption"
		supplied.text = "Supplied by:"
		supplied.add_theme_color_override("font_color", DS.PALETTE["TEXT_DIM"])
		rows.add_child(supplied)
		for source: Dictionary in producers:
			rows.add_child(_consumer_row(str(source.get("building_name", "")), str(source.get("instance_id", ""))))
	rows.visible = true
	toggle.toggled.connect(func(open: bool) -> void:
		rows.visible = open
		toggle.text = "Route details [-]" if open else "Route details [+]")
	return panel

## "Switching suppliers" while an input moves to the market and the intermediary still covers it.
func _handover_line(building: Dictionary, gid: String) -> Label:
	var service = preload("res://scripts/middleman_service.gd")
	var iid := str(building.get("instance_id", ""))
	if not service.in_handover(iid, gid):
		return null
	var turns: int = service.handover_turns(iid, gid)
	var line := Label.new()
	line.name = "SupplierHandover"
	line.theme_type_variation = "Caption"
	line.text = "Switching suppliers: first input from the market in %d turn%s" % [turns, "" if turns == 1 else "s"]
	line.add_theme_color_override("font_color", DS.PALETTE["WARN"])
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return line

func _route_detail_line(building: Dictionary, gid: String, qty: int, source: String, slot: String) -> String:
	var good_name := Catalog.get_display_name(gid)
	if source == "":
		return "%s: none" % slot.capitalize()
	if slot == "FALLBACK":
		return "Fallback: any %s shortfall from %s" % [good_name, _route_source_description(building, gid, source)]
	return "%d %s/turn from %s" % [qty, good_name, _route_source_description(building, gid, source)]

func _route_source_description(building: Dictionary, _gid: String, source: String) -> String:
	var tile_id := str(building.get("tile_id", ""))
	if source == "stockpile":
		return Catalog.tile_label(tile_id)
	if source == "market":
		var port := TransportService.nearest_port_tile(tile_id)
		return "Global Market via %s" % (Catalog.tile_label(port) if port != "" else "nearest port")
	if source == "middleman":
		return "Logistics Intermediary"
	if source.begins_with("tile:"):
		return Catalog.tile_label(source.trim_prefix("tile:"))
	return source

func _open_output_sheet(building: Dictionary, recipe: Dictionary) -> void:
	if str(recipe.get("output_name", "")) == "power":
		_open_sheet("Electricity output", func(vb: VBoxContainer) -> void:
			var note := Label.new()
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			note.text = "Electricity uses your power network and the grid. It is not stored in the tile stockpile or traded through the Logistics Intermediary. Existing power-priority settings determine local use and grid sales."
			vb.add_child(note))
		return
	var iid := str(building.get("instance_id", ""))
	var good_id := BuildingStatus.primary_output_good_id(recipe)
	_open_sheet("Output destination", func(vb: VBoxContainer) -> void:
		# Keep output routing independent from inputs. The all-output shortcuts stay
		# at the top even when this recipe has only one tradeable output.
		_add_logistics_options(vb,building,"output")
		for output: Dictionary in recipe.get("outputs", []):
			var output_gid := str(output.get("good_id", ""))
			if not preload("res://scripts/middleman_service.gd").material_tradeable(output_gid, "output"):
				continue
			if output_gid != good_id:
				vb.add_child(HSeparator.new())
			_add_output_good_options(vb, building, recipe, output_gid)
		if good_id == "":
			return
		var split := MatchState.get_output_split_destinations(iid, good_id)
		if split.size() >= 2 and not preload("res://scripts/middleman_service.gd").uses_outputs(iid):
			vb.add_child(HSeparator.new())
			var split_head := Label.new()
			split_head.theme_type_variation = "Caption"
			split_head.text = "SPLIT OUTPUT — UNITS PER TURN"
			split_head.add_theme_color_override("font_color", DS.PALETTE["TEXT_DIM"])
			vb.add_child(split_head)
			var produced := BuildingStatus.primary_output_qty(recipe)
			var automatic_count := 0
			var committed := 0
			for destination in split:
				var requested := int((destination as Dictionary).get("qty", 0))
				if requested > 0:
					committed += mini(requested, produced)
				else:
					automatic_count += 1
			var automatic_qty := ceili(float(maxi(0, produced - committed)) / float(maxi(1, automatic_count)))
			for destination in split:
				var row := HBoxContainer.new()
				row.add_theme_constant_override("separation", DS.SP["SM"])
				var tile_name := Label.new()
				tile_name.theme_type_variation = "Body"
				tile_name.text = Catalog.tile_label(str((destination as Dictionary).get("tile_id", "")))
				tile_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(tile_name)
				var amount := LineEdit.new()
				amount.custom_minimum_size = Vector2(76, 0)
				amount.max_length = 3
				amount.alignment = HORIZONTAL_ALIGNMENT_RIGHT
				amount.placeholder_text = "Auto %d" % automatic_qty if int((destination as Dictionary).get("qty", 0)) <= 0 else ""
				amount.text = str(int((destination as Dictionary).get("qty", 0))) if int((destination as Dictionary).get("qty", 0)) > 0 else ""
				var destination_tile := str((destination as Dictionary).get("tile_id", ""))
				amount.text_changed.connect(func(value: String) -> void:
					var digits := ""
					for character in value:
						if character >= "0" and character <= "9":
							digits += character
					if digits.length() > 3:
						digits = digits.left(3)
					if digits != value:
						amount.set_text(digits)
					MatchState.set_output_split_quantity(iid, good_id, destination_tile, int(digits) if digits != "" else 0))
				row.add_child(amount)
				vb.add_child(row)
		# Where the output actually ends up: the resolved destination (nearest port for a market
		# route, else the target tile) + how far/costly it is to reach.
		var route := BuildingReadout.output_route(building, recipe)
		var dest_name := str(route.get("destination", ""))
		if dest_name != "":
			vb.add_child(HSeparator.new())
			var dh := Label.new()
			dh.theme_type_variation = "Caption"
			dh.text = "DESTINATION"
			dh.add_theme_color_override("font_color", DS.PALETTE["TEXT_DIM"])
			vb.add_child(dh)
			var turns := int(route.get("turns", 0))
			var cost := float(route.get("cost", 0.0))
			var detail := "on this tile" if turns <= 0 else ("%d turn%s away · £%.2f freight / run" % [turns, "" if turns == 1 else "s", cost])
			if not bool(route.get("reachable", true)):
				detail = "no route — cannot be reached"
			vb.add_child(_dest_summary_row(dest_name, detail))
		# Which of your buildings currently draw this output from the routed destination tile.
		var consumers := BuildingReadout.output_consumers(building, recipe)
		if not consumers.is_empty():
			var h := Label.new()
			h.theme_type_variation = "Caption"
			h.text = "CONSUMED BY"
			h.add_theme_color_override("font_color", DS.PALETTE["TEXT_DIM"])
			vb.add_child(h)
			for c in consumers:
				vb.add_child(_consumer_row(str(c.get("name", "")), str(c.get("instance_id", "")))))

func _add_output_good_options(vb: VBoxContainer, building: Dictionary, recipe: Dictionary, good_id: String) -> void:
	var iid := str(building.get("instance_id", ""))
	var tile_id := str(building.get("tile_id", ""))
	var service = preload("res://scripts/middleman_service.gd")
	var split := MatchState.get_output_split_destinations(iid, good_id)
	var cur_dest := MatchState.get_output_stockpile_destination(iid, good_id)
	var is_market := MatchState.is_output_market(iid, good_id)
	var on_tile := cur_dest != "" and cur_dest == tile_id
	var other := split.size() >= 2 or (cur_dest != "" and cur_dest != tile_id)
	var intermediary := service.buys_output(iid, good_id)
	if intermediary:
		# The service owns this good's destination. Do not let the global
		# STOCKPILE_ALL fallback paint it as a tile route after a license or
		# contract becomes available.
		is_market = false
		on_tile = false
		other = false
	elif not is_market and not on_tile and not other:
		if MatchState.sell_mode == MatchState.SellMode.STOCKPILE_ALL: on_tile = true
		else: is_market = true
	var output_internal := ""
	var output_qty := 0
	for output: Dictionary in recipe.get("outputs", []):
		if str(output.get("good_id", "")) == good_id:
			output_internal = str(output.get("internal_name", ""))
			output_qty = int(output.get("qty", 0))
			break
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", 6)
	var chooser := HBoxContainer.new()
	chooser.alignment = BoxContainer.ALIGNMENT_CENTER
	chooser.add_theme_constant_override("separation", 10)
	var good_icon := _good_icon_pill(good_id, output_internal, output_qty, 92)
	good_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chooser.add_child(good_icon)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	# Only buildings the intermediary can serve (Logistics Intermediary games) offer it.
	if service.eligible(building):
		row.add_child(_dest_option("Logistics Intermediary", "Sell this output privately, including transport and storage.", service.buys_output(iid, good_id), func() -> void:
			var result := service.set_good_mode(iid, "output", good_id, "middleman")
			if not bool(result.get("ok", false)): MatchState.request_toast(str(result.get("reason", "Unable to change output destination.")), "warning")
			_queue_refresh()
			_open_output_sheet(building, recipe)))
	# Selecting Market / Tile re-renders the sheet in place; shipping to another tile
	# opens the map picker.
	var market_available := str(MatchState.ruleset.get("logistics_model", "")) != "middleman_v1" or ResearchState.global_trade_license_available()
	var market_detail := "Sell at market price via the nearest port." if market_available else "[Requires Government Import/Export License]"
	row.add_child(_logistics_route_option(building, "output", "Global market", market_detail, is_market, func() -> void:
		MatchState.route_output_to_market(iid, good_id)
		_queue_refresh()
		_open_output_sheet(building, recipe), good_id, market_available))
	var stockpile_available := ResearchState.open_logistics_contracts_available()
	var stockpile_detail := "Store the output on this tile for later use." if stockpile_available else "[Requires Open Logistics Contracts]"
	row.add_child(_logistics_route_option(building, "output", "Tile stockpile", stockpile_detail, on_tile, func() -> void:
		MatchState.set_output_stockpile_destination(iid, tile_id, good_id)
		_queue_refresh()
		_open_output_sheet(building, recipe)
		preload("res://scripts/stockpile_route_prompt.gd").offer(get_parent(), tile_id, good_id), good_id, stockpile_available))
	row.add_child(_logistics_route_option(building, "output", "Ship to another tile", "Pick a tile on the shipping map to feed a downstream building you own." if stockpile_available else "[Requires Open Logistics Contracts]", other, func() -> void:
		MatchState.begin_output_stockpile_selection(iid, good_id, true)
		_close_sheet(), good_id, stockpile_available))
	chooser.add_child(row)
	group.add_child(chooser)
	group.add_child(_output_route_details_section(building, good_id, output_qty, intermediary, is_market, on_tile, other))
	vb.add_child(group)

func _output_route_details_section(building: Dictionary, gid: String, qty: int, intermediary: bool, is_market: bool, on_tile: bool, other: bool) -> Control:
	var panel := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = DS.PALETTE["BG_INSET"]
	st.border_color = Color(DS.PALETTE["BORDER_SOFT"].r, DS.PALETTE["BORDER_SOFT"].g, DS.PALETTE["BORDER_SOFT"].b, 0.45)
	st.set_border_width_all(1)
	st.set_corner_radius_all(7)
	st.set_content_margin_all(7)
	panel.add_theme_stylebox_override("panel", st)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 3)
	panel.add_child(body)
	var toggle := Button.new()
	toggle.flat = true
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.text = "Route details [-]"
	toggle.toggle_mode = true
	toggle.set_pressed_no_signal(true)
	toggle.custom_minimum_size = Vector2(0, 28)
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	toggle.add_theme_color_override("font_color", DS.PALETTE["TEXT_DIM"])
	body.add_child(toggle)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 2)
	body.add_child(rows)
	var line := Label.new()
	line.theme_type_variation = "Caption"
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var good_name := Catalog.get_display_name(gid)
	if intermediary:
		line.text = "%d %s/turn to Logistics Intermediary" % [qty, good_name]
	elif is_market:
		var port := TransportService.nearest_port_tile(str(building.get("tile_id", "")))
		line.text = "%d %s/turn to Global Market via %s" % [qty, good_name, Catalog.tile_label(port) if port != "" else "nearest port"]
	elif on_tile:
		line.text = "%d %s/turn to %s" % [qty, good_name, Catalog.tile_label(str(building.get("tile_id", "")))]
	elif other:
		line.text = "%d %s/turn to selected stockpile route(s)" % [qty, good_name]
	else:
		line.text = "%d %s/turn — no destination selected" % [qty, good_name]
	rows.add_child(line)
	rows.visible = true
	toggle.toggled.connect(func(open: bool) -> void:
		rows.visible = open
		toggle.text = "Route details [-]" if open else "Route details [+]")
	return panel

# A read-only destination summary card (name + freight/turns detail) for the output sheet.
func _dest_summary_row(name_txt: String, detail: String) -> Control:
	var card := _make_card()
	var cvb := card.get_child(0) as VBoxContainer
	cvb.add_theme_constant_override("separation", 1)
	var nl := Label.new()
	nl.theme_type_variation = "Body"
	nl.text = name_txt
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cvb.add_child(nl)
	var dl := Label.new()
	dl.theme_type_variation = "Caption"
	dl.text = detail
	dl.add_theme_color_override("font_color", DS.PALETTE["TEXT_MUTED"])
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cvb.add_child(dl)
	return card

# A "building — Go To" row for the output-consumer / input-source lists.
func _consumer_row(name_txt: String, target_iid: String) -> Control:
	var card := _make_card()
	var cvb := card.get_child(0) as VBoxContainer
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", DS.SP["SM"])
	cvb.add_child(hb)
	var nl := Label.new()
	nl.theme_type_variation = "Body"
	nl.text = name_txt
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hb.add_child(nl)
	if target_iid != "":
		var go := Button.new()
		go.text = "Go To"
		go.custom_minimum_size = Vector2(72, 32)
		go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		go.pressed.connect(func() -> void:
			_close_sheet()
			MatchState.focus_building_requested.emit(target_iid))
		hb.add_child(go)
	return card

# An icon-only destination option card. The full name and routing detail live in the
# tooltip so several choices can sit side by side without repeating prose under each one.
func _dest_option(title: String, detail: String, active: bool, on_press: Callable, enabled: bool = true) -> Control:
	var accent: Color = DS.PALETTE["ACCENT"]
	var card := PanelContainer.new()
	# Icon-only cards carry their title in the node name so tutorial spotlights and
	# harnesses can target a specific route, e.g. RouteOption_ShipToAnotherTile.
	card.name = ("RouteOption_" + title.to_pascal_case()).validate_node_name()
	card.custom_minimum_size = Vector2(78, 78)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.modulate = Color(1, 1, 1, 0.42) if not enabled else Color.WHITE
	var st := StyleBoxFlat.new()
	st.bg_color = DS.PALETTE["BG_HIGHLIGHT"] if active else DS.PALETTE["BG_CARD"]
	st.border_color = accent if active else DS.PALETTE["BORDER_SOFT"]
	st.set_border_width_all(1)
	st.set_corner_radius_all(10)
	st.set_content_margin_all(5)
	card.add_theme_stylebox_override("panel", st)
	card.tooltip_text = "%s\n%s" % [title, detail] if detail != "" else title
	# Locked routes still need to receive hover so their tooltip can explain the
	# missing research. The click handler below remains gated by `enabled`.
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if enabled else Control.CURSOR_ARROW
	card.gui_input.connect(func(e: InputEvent) -> void:
		if enabled and e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			# The callback can hide this sheet and expose the map during this event.
			card.accept_event()
			on_press.call())
	var icon := _RouteIcon.new()
	icon.kind = _route_kind_for_title(title)
	icon.active = active
	icon.accent = accent
	icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(icon)
	return card

func _route_kind_for_title(title: String) -> String:
	var t := title.to_lower()
	if t.contains("intermediary"):
		return "middleman"
	if t.contains("market"):
		return "market"
	if t.contains("another tile") or t.begins_with("stockpile:"):
		return "remote_stockpile"
	return "stockpile"

# --- labour (headcount, not per turn — the wage is the per-turn figure) ---------------------

func _build_labour(lab: Dictionary) -> Container:
	if UiPrefs.use_bdp_v3:
		return _build_labour_v3(lab)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DS.SP["SM"])
	row.add_child(_labour_card("Unskilled", int(lab.get("unskilled", 0)), DS.PALETTE["TEXT_MUTED"]))
	row.add_child(_labour_card("Skilled", int(lab.get("skilled", 0)), DS.PALETTE["ACCENT"]))
	row.add_child(_labour_card("Highly", int(lab.get("highly", 0)), DS.PALETTE["WARN"]))
	var cost_card := PanelContainer.new()
	cost_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cs := StyleBoxFlat.new()
	cs.bg_color = DS.PALETTE["BG_HIGHLIGHT"]
	cs.border_color = DS.PALETTE["BORDER_SOFT"]
	cs.set_border_width_all(1)
	cs.set_corner_radius_all(8)
	cs.set_content_margin_all(8)
	cost_card.add_theme_stylebox_override("panel", cs)
	var cv := VBoxContainer.new()
	cv.alignment = BoxContainer.ALIGNMENT_CENTER
	cost_card.add_child(cv)
	cv.add_child(EffectEmblem.make("engineer", 28.0))
	var cnum := Label.new()
	cnum.theme_type_variation = "Numeric"
	cnum.text = "£%.2f/turn" % float(lab.get("cost", 0.0))
	cnum.add_theme_color_override("font_color", DS.PALETTE["DANGER"])
	cnum.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(cnum)
	var csub := Label.new()
	csub.theme_type_variation = "Caption"
	csub.text = "%s workers" % _fmt_int(int(lab.get("total", 0)))
	csub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	csub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(csub)
	row.add_child(cost_card)
	return row

## v3's Labour and Wages, on the frame's steel: a factory door for each kind of worker, its name over
## it and its headcount engraved on the kick plate, the window lit when any are employed; then the
## labour cost and the number of workers on drum counters, each labelled beside it. The counters roll
## from what they last read.
func _build_labour_v3(lab: Dictionary) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "LabourV3"
	box.add_theme_constant_override("separation", DS.SP["MD"])
	var doors := HBoxContainer.new()
	doors.name = "Doors"
	doors.add_theme_constant_override("separation", DS.SP["SM"])
	box.add_child(doors)
	for pair in [["Unskilled", "unskilled"], ["Skilled", "skilled"], ["Highly skilled", "highly"]]:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 2)
		doors.add_child(col)
		col.add_child(_v3_metal_label(pair[0], HORIZONTAL_ALIGNMENT_CENTER))
		var door: Control = BdpV3LabourDoor.new()
		door.count = int(lab.get(pair[1], 0))
		col.add_child(door)
	var meters := HBoxContainer.new()
	meters.add_theme_constant_override("separation", DS.SP["SM"])
	meters.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(meters)
	var iid := str(_current_building.get("instance_id", ""))
	var cost := float(lab.get("cost", 0.0))
	var pound := _v3_metal_label("£", HORIZONTAL_ALIGNMENT_RIGHT)
	pound.add_theme_font_size_override("font_size", 20)
	meters.add_child(pound)
	meters.add_child(_v3_counter("labour:%s:cost" % iid, cost, 2, BdpV3Counter.drums_for(cost, 2, 4)))
	meters.add_child(_v3_metal_label("per turn", HORIZONTAL_ALIGNMENT_LEFT))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(DS.SP["MD"], 0)
	meters.add_child(gap)
	var total := float(lab.get("total", 0))
	meters.add_child(_v3_counter("labour:%s:workers" % iid, total, 0, BdpV3Counter.drums_for(total, 0, 3)))
	meters.add_child(_v3_metal_label("workers", HORIZONTAL_ALIGNMENT_LEFT))
	return box

## A label printed on the steel: capitals, off-white, Barlow Condensed.
func _v3_metal_label(text: String, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.text = text
	l.uppercase = true
	l.add_theme_font_override("font", BdpV3Plate.FONT_SEMI)
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", DS.PALETTE["TEXT"])
	l.horizontal_alignment = align
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l

func _v3_counter(key: String, v: float, decimal_count: int, drum_count: int) -> Control:
	var counter: BdpV3Counter = BdpV3Counter.new()
	counter.configure(drum_count, decimal_count)
	counter.set_value(v, float(_v3_last_readings[key]) if _v3_last_readings.has(key) else NAN)
	_v3_last_readings[key] = v
	return counter

func _labour_card(label: String, count: int, accent: Color) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var st := StyleBoxFlat.new()
	st.bg_color = DS.PALETTE["BG_INSET"]
	st.border_color = Color(DS.PALETTE["BORDER_SOFT"].r, DS.PALETTE["BORDER_SOFT"].g, DS.PALETTE["BORDER_SOFT"].b, 0.35)
	st.set_border_width_all(1)
	st.set_corner_radius_all(8)
	st.set_content_margin_all(8)
	card.add_theme_stylebox_override("panel", st)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vb)
	var num := Label.new()
	num.theme_type_variation = "Numeric"
	num.text = str(count)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(num)
	var lb := Label.new()
	lb.theme_type_variation = "Caption"
	lb.text = label
	lb.add_theme_color_override("font_color", accent)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(lb)
	return card

# --- shared atoms --------------------------------------------------------------------------

func _make_section(text: String, right_text: String = "") -> Control:
	var hb := HBoxContainer.new()
	hb.set_meta("v3_section", text)
	var s := Label.new()
	s.theme_type_variation = "Section"
	s.text = text
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(s)
	if UiPrefs.use_bdp_v3 and BdpV3Heading.can_show(text):
		# v3: the heading in raised white letters, as INPUTS and OUTPUTS are on the control plate.
		var raised: Control = BdpV3Heading.new()
		raised.text = text
		hb.add_child(raised)
		hb.move_child(raised, 0)
		var room := Control.new()
		room.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		room.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(room)
		s.visible = false
	if right_text != "":
		var r := Label.new()
		r.theme_type_variation = "Caption"
		r.text = right_text
		r.add_theme_color_override("font_color", DS.PALETTE["TEXT_DIM"])
		hb.add_child(r)
	return hb

func _make_card() -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var st := StyleBoxFlat.new()
	st.bg_color = DS.PALETTE["BG_CARD"]
	st.border_color = DS.PALETTE["BORDER_SOFT"]
	st.set_border_width_all(1)
	st.set_corner_radius_all(10)
	st.content_margin_left = 12
	st.content_margin_right = 12
	st.content_margin_top = 8
	st.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", st)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	card.add_child(vb)
	return card

func _tone_color(tone: String) -> Color:
	match tone:
		"ok": return DS.PALETTE["OK"]
		"warn": return DS.PALETTE["WARN"]
		"bad": return DS.PALETTE["DANGER"]
		_: return DS.PALETTE["TEXT_MUTED"]

func _load_texture_rect(path: String, size: Vector2) -> TextureRect:
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	var tr := TextureRect.new()
	tr.texture = tex
	tr.custom_minimum_size = size
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return tr

# --- lifecycle / positioning ---------------------------------------------------------------

func _hide_panel() -> void:
	hide()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
		_close_sheet()
		PanelStack.remove(self)
		building_connections_changed.emit("", [], [], false)

## Match the tile view panel's height exactly (fallback: a viewport fit that stays clear of the
## bottom menu). The body scrolls inside this fixed height, so the panel never overflows downward.
func _target_height() -> float:
	var vp := get_viewport().get_visible_rect().size
	var tile_panel := get_parent().get_node_or_null("TileInfoPanel") as Control
	var h: float
	if tile_panel != null and tile_panel.visible and tile_panel.size.y > 8.0:
		h = tile_panel.size.y
	else:
		h = vp.y - TOP_BAR_CLEARANCE - BOTTOM_CLEARANCE
	return clampf(h, 200.0, vp.y - TOP_BAR_CLEARANCE - PANEL_EDGE_MARGIN)

func _resize_body() -> void:
	var h := _target_height()
	var w := PANEL_WIDTH + _sheet_extra_width
	custom_minimum_size = Vector2(w, h)
	size = Vector2(w, h)

func _size_and_position() -> void:
	_resize_body()
	var vp := get_viewport().get_visible_rect().size
	var right_edge := vp.x - PANEL_EDGE_MARGIN
	var top_edge := TOP_BAR_CLEARANCE
	if empire_dock:
		# Empire-view click: sit exactly where the tile view panel normally sits
		# (tile_info_panel_v2._apply_anchors: 30 in from the right edge, 78 down).
		right_edge = vp.x - 30.0
		top_edge = 78.0
		var x2 := clampf(right_edge - size.x, PANEL_EDGE_MARGIN, maxf(PANEL_EDGE_MARGIN, vp.x - size.x - PANEL_EDGE_MARGIN))
		global_position = Vector2(x2, top_edge)
		return
	var tile_panel := get_parent().get_node_or_null("TileInfoPanel") as Control
	if tile_panel != null and tile_panel.visible:
		right_edge = tile_panel.global_position.x - PANEL_EDGE_MARGIN
		top_edge = tile_panel.global_position.y
	var x := clampf(right_edge - size.x, PANEL_EDGE_MARGIN, maxf(PANEL_EDGE_MARGIN, vp.x - size.x - PANEL_EDGE_MARGIN))
	var y := clampf(top_edge, PANEL_EDGE_MARGIN, maxf(PANEL_EDGE_MARGIN, vp.y - size.y - PANEL_EDGE_MARGIN))
	global_position = Vector2(x, y)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
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

func _open_logistics_sheet(building: Dictionary) -> void:
	var recipe := Catalog.get_recipe(str(building.recipe_id))
	_open_sheet("Building logistics",func(vb: VBoxContainer) -> void:
		var note := Label.new()
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.text = "Choose inputs and outputs independently. Manage logistics uses generic carriers for physical deliveries. Middleman goods stay private to this building; retained goods use your tile storage."
		vb.add_child(note)
		vb.add_child(_route_card("Inputs",_input_summary(building,recipe),func() -> void: _open_input_sources_sheet(building,recipe), INPUT_ICON))
		vb.add_child(_route_card("Outputs",_output_summary(building,recipe),func() -> void: _open_output_sheet(building,recipe), OUTPUT_ICON))
		var service = preload("res://scripts/middleman_service.gd")
		var iid := str(building.instance_id)
		if service.enabled(iid):
			var p: Dictionary = service.preview(iid)
			for pair in [["Intermediary input purchases",float(p.buy.goods_value)],["Intermediary sale value",float(p.sale.goods_value)],["Upfront service + factory cash",float(p.upfront)],["Protected commitments",float(p.protected_commitments)],["Loan needed",float(p.funding_draw)]]:
				vb.add_child(_metric(str(pair[0]),"£%.2f" % float(pair[1]),DS.PALETTE["TEXT"],false))
			var status := Label.new()
			status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			status.text = str(p.reason)+" Estimates use current prices. Managed purchases and deliveries are billed separately; future sales cannot fund inputs."
			vb.add_child(status)
			for side in ["inputs","outputs"]:
				for gid in p[side]:
					vb.add_child(_metric("Private %s: %s" % [side,Catalog.get_display_name(str(gid))],str(p[side][gid]),DS.PALETTE["TEXT"],false)))

func _add_logistics_options(vb: VBoxContainer, building: Dictionary, side: String) -> void:
	var service = preload("res://scripts/middleman_service.gd")
	if not service.eligible(building) or not service.recipe_side(Catalog.get_recipe(str(building.recipe_id)), side): return
	var iid := str(building.instance_id)
	var heading := Label.new()
	heading.theme_type_variation = "Caption"
	heading.text = "ALL INPUTS" if side == "input" else "ALL OUTPUTS"
	heading.add_theme_color_override("font_color", DS.PALETTE["TEXT_DIM"])
	vb.add_child(heading)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	var active: bool = service.side_all_middleman(iid, side)
	row.add_child(_dest_option("All %s — Logistics Intermediary" % ("inputs" if side == "input" else "outputs"), "Buys inputs privately for this building." if side == "input" else "Buys this building's production. Transport and storage are included.",active,func() -> void: _request_logistics_mode(building,side,"middleman")))
	var market_available := str(MatchState.ruleset.get("logistics_model", "")) != "middleman_v1" or ResearchState.global_trade_license_available()
	var stockpile_available := ResearchState.open_logistics_contracts_available()
	if market_available:
		row.add_child(_dest_option("All %s — Global market" % ("inputs" if side == "input" else "outputs"), "Use the ordinary market route for every tradeable good on this side.", _all_managed_source(building, side, "market"), func() -> void: _request_all_managed_source(building, side, "market"), true))
	else:
		row.add_child(_dest_option("All %s — Global market" % ("inputs" if side == "input" else "outputs"), "[Requires Government Import/Export License]", false, func() -> void: pass, false))
	if stockpile_available:
		row.add_child(_dest_option("All %s — Tile stockpile" % ("inputs" if side == "input" else "outputs"), "Use this building's tile stockpile for every tradeable good on this side.", _all_managed_source(building, side, "tile"), func() -> void: _request_all_managed_source(building, side, "tile"), true))
	else:
		row.add_child(_dest_option("All %s — Tile stockpile" % ("inputs" if side == "input" else "outputs"), "[Requires Open Logistics Contracts]", false, func() -> void: pass, false))
	vb.add_child(row)
	vb.add_child(HSeparator.new())

func _all_managed_source(building: Dictionary, side: String, source: String) -> bool:
	var iid := str(building.get("instance_id", ""))
	var service = preload("res://scripts/middleman_service.gd")
	var items: Array = service._side_items(iid, side).filter(func(item: Dictionary) -> bool: return service.material_tradeable(str(item.get("good_id", "")), side))
	if items.is_empty(): return false
	for item: Dictionary in items:
		var gid := str(item.get("good_id", ""))
		if side == "input":
			if service.supplies_good(iid, gid): return false
			if source == "tile" and not MatchState.is_input_tile_only(iid, gid): return false
			if source == "market" and MatchState.is_input_tile_only(iid, gid): return false
		else:
			if service.buys_output(iid, gid): return false
			var output_tile := MatchState.get_output_stockpile_destination(iid, gid)
			var default_market := output_tile == "" and MatchState.get_output_split_destinations(iid, gid).is_empty() and MatchState.sell_mode != MatchState.SellMode.STOCKPILE_ALL
			var default_tile := output_tile == "" and MatchState.get_output_split_destinations(iid, gid).is_empty() and MatchState.sell_mode == MatchState.SellMode.STOCKPILE_ALL
			if source == "market" and not MatchState.is_output_market(iid, gid) and not default_market: return false
			if source == "tile" and output_tile != str(building.get("tile_id", "")) and not default_tile: return false
	return true

func _request_all_managed_source(building: Dictionary, side: String, source: String) -> void:
	var service = preload("res://scripts/middleman_service.gd")
	var action := func() -> bool: return _apply_all_managed_source(building, side, source)
	if service.side_all_middleman(str(building.get("instance_id", "")), side):
		preload("res://scripts/logistics_confirmation.gd").request(self, "managed", action)
	else:
		action.call()

func _apply_all_managed_source(building: Dictionary, side: String, source: String) -> bool:
	var iid := str(building.get("instance_id", ""))
	var service = preload("res://scripts/middleman_service.gd")
	var result := service.set_mode(iid, side, "managed")
	if not bool(result.get("ok", false)):
		MatchState.request_toast(str(result.get("reason", "Unable to change logistics source.")), "warning")
		return false
	var recipe := Catalog.get_recipe(str(building.get("recipe_id", "")))
	for item: Dictionary in recipe.get("inputs" if side == "input" else "outputs", []):
		var gid := str(item.get("good_id", ""))
		if not service.material_tradeable(gid, side): continue
		if side == "input":
			var chosen := "market" if source == "market" else "stockpile"
			var route_result := service.set_input_route(iid, gid, "primary", chosen)
			if not bool(route_result.get("ok", false)):
				MatchState.request_toast(str(route_result.get("reason", "Unable to change input source.")), "warning")
				return false
			var clear_result := service.set_input_route(iid, gid, "fallback", "")
			if not bool(clear_result.get("ok", false)):
				MatchState.request_toast(str(clear_result.get("reason", "Unable to clear input fallback.")), "warning")
				return false
		elif source == "market":
			MatchState.route_output_to_market(iid, gid)
		else:
			MatchState.set_output_stockpile_destination(iid, str(building.get("tile_id", "")), gid)
	_queue_refresh()
	if side == "input": _open_input_sources_sheet(building, recipe)
	else: _open_output_sheet(building, recipe)
	return true

func _logistics_route_option(building: Dictionary, side: String, title: String, detail: String, active: bool, on_press: Callable, good_id: String = "", enabled: bool = true) -> Control:
	var service = preload("res://scripts/middleman_service.gd")
	var intermediary: bool = service.supplies_good(str(building.instance_id), good_id) if side == "input" and good_id != "" else (service.buys_output(str(building.instance_id), good_id) if side == "output" and good_id != "" else service.side_all_middleman(str(building.instance_id), side))
	var action := func() -> void:
		if intermediary: _request_logistics_mode(building, side, "managed", on_press, good_id)
		else: on_press.call()
	return _dest_option(title, detail, active and not intermediary, action, enabled)

func _request_logistics_mode(building: Dictionary, side: String, mode: String, after_change: Callable = Callable(), good_id: String = "") -> void:
	var service = preload("res://scripts/middleman_service.gd")
	var active: bool = service.supplies_good(str(building.instance_id), good_id) if side == "input" and good_id != "" else (service.buys_output(str(building.instance_id), good_id) if side == "output" and good_id != "" else service.side_all_middleman(str(building.instance_id), side))
	if (mode == "middleman") == active: return
	var apply := func() -> bool:
		var result: Dictionary = service.set_good_mode(str(building.instance_id), side, good_id, mode) if good_id != "" else service.set_mode(str(building.instance_id), side, mode)
		if not bool(result.ok):
			MatchState.request_toast(str(result.reason), "warning")
			return false
		_queue_refresh()
		if after_change.is_valid(): after_change.call()
		else:
			var recipe := Catalog.get_recipe(str(building.recipe_id))
			if side == "input": _open_input_sources_sheet(building, recipe)
			else: _open_output_sheet(building, recipe)
		return true
	preload("res://scripts/logistics_confirmation.gd").request(self, mode, apply)
