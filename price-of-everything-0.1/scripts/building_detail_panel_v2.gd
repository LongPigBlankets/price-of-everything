extends PanelContainer
const Metrics := preload("res://scripts/ds2/metrics.gd")
const EffectEmblem := preload("res://scripts/effect_emblem.gd")
## Building Detail — the scenario-adaptive detail panel, in DS2's worn-industrial look (control plates,
## keycaps, lamps, LED screens; docs/ds2-theme.md). Code-instantiated by world_map. THE building detail panel.
## Renders a shared, UI-agnostic readout (building_readout.gd): header + status lamp → adaptive
## recipe/flow strip on an enamel sign → the control plate (inputs, outputs, upgrade, change recipe) →
## diagnostics (Visual or Text) → per-output cost-to-produce gauges → modifiers → economics → inbound
## shipments → labour → the Sell and Demolish footer, with the map-highlight signal. Live via coalesced
## refresh. Upgrade/recipe/input/output sheets slide in over the body; battery/infra/port variants.
## See docs/building-detail-v2-plan.md.

const BuildingReadout := preload("res://scripts/building_readout.gd")
const BuildingNaming := preload("res://scripts/building_naming.gd")
const DotCard := preload("res://scripts/ds2/dot_card.gd")
const BuildingStatus := preload("res://scripts/building_status.gd")
const GoodIcons := preload("res://scripts/good_icons.gd")
const UIHelpers := preload("res://scripts/ui_helpers.gd")
const BuyDialog := preload("res://scripts/buy_building_dialog.gd")
const BuildingLevels := preload("res://scripts/building_levels.gd")
const InfrastructureInfo := preload("res://scripts/infrastructure_info.gd")
const BdpV3Block := preload("res://scripts/bdp_v3_block.gd")
const BdpV3Routes := preload("res://scripts/bdp_v3_routes.gd")
const BdpV3Footer := preload("res://scripts/bdp_v3_footer.gd")
const BdpV3Key := preload("res://scripts/bdp_v3_key.gd")
const BdpV3Lamp := preload("res://scripts/bdp_v3_lamp.gd")
const BdpV3Plate := preload("res://scripts/bdp_v3_plate.gd")
const BdpV3Scroll := preload("res://scripts/bdp_v3_scroll.gd")
const BdpV3Seam := preload("res://scripts/bdp_v3_seam.gd")
const BdpV3Title := preload("res://scripts/bdp_v3_title.gd")
const BdpV3Enamel := preload("res://scripts/bdp_v3_enamel.gd")
const LampOverlay := preload("res://scripts/ds2/lamp_overlay.gd")
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
## The panel frames these sections (heading and content together); the value names the frame, so sections
## sharing a name share one frame (Modifiers and Economics).
const V3_FRAMED_SECTIONS := {
	"Diagnostics": "diagnostics", "Cost to produce": "cost", "Modifiers": "money", "Economics · per turn": "money",
	"Infrastructure": "infrastructure", "Breakdown": "breakdown", "Inbound shipments": "shipments",
	"Labour and Wages": "labour",
}
const INPUT_ICON: Texture2D = preload("res://assets/icons/ui_icons/construction_materials.png")
const OUTPUT_ICON: Texture2D = preload("res://assets/icons/research/glyph/output.png")



const HEADER_HEIGHT := 44.0
const PANEL_EDGE_MARGIN := 20.0
const TOP_BAR_CLEARANCE := 72.0   # clears the top bar and its shadow
const BOTTOM_CLEARANCE := 110.0  # fallback: keep clear of the bottom menu when no tile panel to match
## The width the panel's text is measured against.
const PANEL_WIDTH := 460.0
## The panel's width: its content held it at 495 wide; the owner widened it by 30 for the input and output sheets.
const V3_PANEL_WIDTH := 525.0
const CONTENT_MARGIN := 26
## The width the header keeps for its keys.
const V3_KEY_COLUMN := 96.0 / 1.875
## The backing's brass trim's width in layout pixels (layout.json panel_backing).
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
# The title's text; shown only when the raised white letters lack one of its characters.
var _title_label: Label = null
# The title in raised white letters.
var _title_v3: BdpV3Title = null
## The building's icon in polished metal, top left, two title lines tall.
var _emblem_v3: Control = null
# The status as a lamp and its label.
var _status_v3: HBoxContainer = null
var _status_lamp: BdpV3Lamp = null
var _status_v3_label: Label = null
var _body: VBoxContainer = null
var _scroll: ScrollContainer = null
# The non-slip edge over the seam between the header and the scrolling body.
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
# The header's Close keycap.
var _close_key: TextureButton = null
# The Location keycap under the close key: pans the map to the building.
var _pin_key: TextureButton = null
# The backing plate (dark navy-grey steel in a brass trim) drawn behind everything.
var _backing: Control = null

func _ready() -> void:
	if DS and DS.theme:
		theme = DS.theme
	custom_minimum_size = Vector2(_panel_width(), 0)
	_build_shell()
	_wire_live_refresh()
	visibility_changed.connect(_on_visibility_changed)

# --- shell ---------------------------------------------------------------------------------

func _build_shell() -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = DS.PALETTE["BG_PANEL"]
	bg.set_border_width_all(0)   # the backing's brass trim is the edge
	bg.border_color = DS.PALETTE["BORDER_SOFT"]
	bg.set_corner_radius_all(10)
	bg.set_content_margin_all(0)
	add_theme_stylebox_override("panel", bg)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, CONTENT_MARGIN)   # clear the brass trim
	add_child(margin)
	_backing = BdpV3Nine.make("panel_backing", 64.0)
	add_child(_backing)
	move_child(_backing, 0)   # behind the content

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
	_title_label.mouse_filter = Control.MOUSE_FILTER_PASS
	header.add_child(_title_label)
	_title_v3 = BdpV3Title.new()
	# The emblem takes its side and a gap from the title's width.
	_title_v3.custom_minimum_size = Vector2(_title_label.custom_minimum_size.x - BdpV3Emblem.side() - DS.SP["SM"], 0)
	_title_v3.mouse_filter = Control.MOUSE_FILTER_PASS
	header.add_child(_title_v3)
	# The keys: Close beside the title's first line and Location beside its second, each a line tall.
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
	outer.add_child(_status_v3)

	# The scroll area sits in a plain Control so that the seam edge, added after it, draws over the
	# top of the body; the body starts at the edge's lip.
	var well := Control.new()
	well.name = "BodyWell"
	well.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(well)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_top = BdpV3Seam.strip_height()
	BdpV3Scroll.apply(_scroll, true)
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
	_apply_v3_title()
	# The lamp over the panel and its sheets, part by part (docs/ds2-theme.md §4.1).
	LampOverlay.attach(self)

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
	visible = true
	PanelStack.push(self)
	_size_and_position()
	if BuildingState.is_player_owned(building):
		MiniQuest.note_building_opened()   # the Tutorial's first mission

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
	_title_label.text = display_name if is_infra else BuildingNaming.of(building)
	_title_v3.text = _title_label.text
	# The title is one name; the recipe it runs shows on hovering it, on the dot card.
	var recipe_tip := {} if is_infra else v3_recipe_tip(building, recipe)
	DotCard.attach(_title_v3, recipe_tip)
	_title_label.tooltip_text = _title_v3.tooltip_text
	_emblem_v3.visible = _emblem_v3.set_building(str(building.get("building_id", "")))
	_apply_v3_title()
	# Catalog.tile_label, not the raw id: "Stoneshore Fields - (5, 9)", never "tile_5_9".
	var _tile := str(building.get("tile_id", ""))
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

	# The control plate (inputs · outputs · upgrade · change recipe), right under the recipe strip; its
	# keys open action sheets.
	if BuildingReadout.is_recipe_kind(kind) and not is_infra:
		_body.add_child(_build_v3_block(building, recipe))

	var diag_head := _make_section("Diagnostics")
	diag_head.add_child(_v3_view_switch())
	_body.add_child(diag_head)
	var diag_card := _build_diagnostics(BuildingReadout.diagnostics(building, recipe, building_data, is_infra))
	_body.add_child(diag_card)
	# The economics, quoted once: the visual diagnostics' carbon check reads it as well as the section.
	var v3_econ: Dictionary = BuildingEconomics.per_turn(building)
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

	# Value added in production, transport, and what is left; nothing for a building with neither inputs
	# nor outputs (a battery), whose running costs are no measure beside a producer's.
	if bool(v3_econ.get("shown", false)):
		_body.add_child(_make_section("Economics · per turn"))
		_body.add_child(_build_economics_v3(v3_econ))
	if is_infra:
		_body.add_child(_make_section("Infrastructure"))
		_body.add_child(_build_infrastructure_details(building_data))
		var breakdown := _build_infra_breakdown(building, building_data)
		if breakdown != null:
			_body.add_child(_make_section("Breakdown"))
			_body.add_child(breakdown)

	# inbound shipments (the power a building draws is the diagnostics' to say)
	var ships := BuildingReadout.shipments(building, recipe)
	if not ships.is_empty():
		_body.add_child(_make_section("Inbound shipments"))
		_body.add_child(_build_shipments(ships))

	_body.add_child(_make_section("Labour and Wages"))
	# Headcounts from the recipe/building; cost is the engine's actual grown-wage charge (level +
	# labour modifiers included), the same figure the Economics card shows — not the base rate.
	var lab_readout: Dictionary = BuildingReadout.labour(building_data, recipe)
	lab_readout["cost"] = Production._calculate_labour_cost(building, recipe)
	_body.add_child(_build_labour(lab_readout))

	# sell / demolish (player-owned; the early NPC/construction returns skip this)
	var sell_row: Control
	if BuildingWorks.is_demolishing(str(building.get("instance_id", ""))):
		sell_row = _build_demolishing_row(building)
	else:
		sell_row = _build_v3_footer(building)
	sell_row.set_meta("v3_section_end", true)
	_body.add_child(sell_row)
	_v3_frame_sections()

	# map highlight: light up supplier/consumer tiles for this building
	var conn := BuildingReadout.connections(building, recipe)
	building_connections_changed.emit(str(conn.get("origin", "")), conn.get("input_tiles", []), conn.get("output_tiles", []), bool(conn.get("has_market", false)))

# --- status lamp ---------------------------------------------------------------------------

func _set_badge(st: Dictionary) -> void:
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
		var display_name := BuildingNaming.of(building)
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
	if preload("res://scripts/middleman_service.gd").active():
		vb.add_child(_port_metric("Ad valorem · all turns", "%s%% of market buy value" % String.num(EconomyConfig.SEAPORT_AD_VALOREM_INTERMEDIARY_GAMES * 100.0, 1)))
	elif TransportState.keeps_introductory_port_rate():
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

## The upgrade opens THE SHARED DIALOG (scripts/ledger_v3/upgrade_dialog_ds2.gd), the one the building
## ledger opens: one screen, one implementation. It shows the top level and an upgrade under way too.
##
## The full-height action sheet stays for the CASH-ONLY INFRASTRUCTURE upgrade, which the dialog does not
## model (and for a building that can't be upgraded at all, with the reason). Driven by
## BuildingWorks.preview_upgrade / start_upgrade / cancel_upgrade.
func _open_upgrade_sheet(building: Dictionary) -> void:
	var iid := str(building.get("instance_id", ""))
	var preview: Dictionary = BuildingWorks.preview_upgrade(iid)
	if bool(preview.get("ok", false)) and not bool(preview.get("infra", false)):
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
			var cancel := Button.new()
			cancel.text = "Cancel upgrade"
			cancel.custom_minimum_size = Vector2(0, 40)
			cancel.pressed.connect(func() -> void:
				BuildingWorks.cancel_upgrade(iid)
				MatchState.request_toast("Upgrade cancelled — cash refunded.", "caution")
				_close_sheet()
				_queue_refresh())
			vb.add_child(cancel)
			return
		# Levellable infrastructure: cash-only — capacity delta + one pay-and-go CTA.
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
		vb.add_child(pay))

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

## One reusable upgrade dialog on a high CanvasLayer, built once and hidden on close. Same
## arrangement the building ledger uses, so the screens share one dialog rather than each
## carrying their own.
func _ensure_upgrade_dialog() -> void:
	if _upgrade_dialog != null and is_instance_valid(_upgrade_dialog):
		return
	if _upgrade_dialog_layer == null or not is_instance_valid(_upgrade_dialog_layer):
		_upgrade_dialog_layer = CanvasLayer.new()
		_upgrade_dialog_layer.layer = 128
		get_tree().root.add_child(_upgrade_dialog_layer)
	_upgrade_dialog = (load("res://scripts/ledger_v3/upgrade_dialog_ds2.gd") as Script).new()
	_upgrade_dialog_layer.add_child(_upgrade_dialog)
	_upgrade_dialog.connect("committed", func(_iid: String) -> void: _queue_refresh())


## `extra_width` widens the WHOLE panel while this sheet is up (see _sheet_extra_width)
## — a sheet is a same-size overlay (PanelContainer manages every direct child to the
## SAME rect), so a sheet that needs more room than the panel's normal width has
## no other way to get it than the panel itself growing.
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
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	var margin := MarginContainer.new()
	margin.name = "SheetMargin"
	var slide := _v3_sheet_plate(sheet, margin)
	var vb := VBoxContainer.new()
	vb.name = "SheetVBox"
	vb.add_theme_constant_override("separation", DS.SP["SM"])
	margin.add_child(vb)
	var header := HBoxContainer.new()
	header.name = "SheetHeader"
	header.add_theme_constant_override("separation", DS.SP["SM"])
	vb.add_child(header)
	var back_key := BdpV3Key.make("back")
	back_key.pressed.connect(_close_sheet)
	header.add_child(back_key)
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
	BdpV3Scroll.apply(scroll, true)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", DS.SP["SM"])
	scroll.add_child(body)
	populate.call(body)
	add_child(sheet)  # stacks over the panel's content (later child draws on top)
	_sheet = sheet
	if preserve_scroll:   # a sheet rebuilt in place stays put
		scroll.set_deferred("scroll_vertical", restore_scroll)
	else:
		slide.position.x = size.x
		slide.create_tween().tween_property(slide, "position:x", 0.0, V3_SHEET_SLIDE_SECONDS) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## An action sheet is a worn steel plate that slides in from the right over the panel's body, inside
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

# --- the control plates: the main controls on worn steel plates ----------------------------

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


## The raised title in place of the label, unless the title has a character its letters lack.
func _apply_v3_title() -> void:
	var raised := BdpV3Title.can_show(_title_label.text)
	_title_v3.visible = raised
	_title_label.visible = not raised


## Moves each framed section (its heading and everything up to the next heading) into a steel
## frame. Runs after a rebuild; the footer and anything above the first framed heading stay put.
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


## Inputs, Outputs, Upgrade and Change recipes as one control plate; the keys open the sheets.
func _build_v3_block(building: Dictionary, recipe: Dictionary) -> Control:
	var service = preload("res://scripts/middleman_service.gd")
	var iid := str(building.get("instance_id", ""))
	var manage_unlocked: bool = service.eligible(building) and ResearchState.open_logistics_contracts_available()
	var state := {
		"input_value": _input_summary(building, recipe),
		"output_value": _output_summary(building, recipe),
		"input_managed": manage_unlocked and service.side_all_middleman(iid, "input"),
		"output_managed": manage_unlocked and service.side_all_middleman(iid, "output"),
	}
	state.merge(v3_upgrade_state(building))
	var alt_count := BdpV3Block.switch_recipes(building).size()
	if BuildingWorks.is_retooling(iid):
		var t := BuildingWorks.retrofit_turns_remaining(iid)
		state["recipe_title"] = "Retooling — %d turn%s" % [t, "" if t == 1 else "s"]
		state["recipe_detail"] = ""
		state["recipe_enabled"] = true
	else:
		state["recipe_title"] = "Change recipes (%d)" % alt_count
		state["recipe_detail"] = BdpV3Block.recipe_detail(alt_count,
			BdpV3Block.better_recipe_count(building) if alt_count > 0 else 0, BdpV3Block.main_output_name(recipe))
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
## The title's hover card (scripts/ds2/dot_card.gd): the recipe the building runs, what it makes a run as
## facts, the power it draws, and what it takes in the goods' wells, at the building's level. Empty with no recipe.
static func v3_recipe_tip(building: Dictionary, recipe: Dictionary) -> Dictionary:
	if recipe.is_empty():
		return {}
	var level := int(building.get("level", 1))
	var rows: Array = []
	for o: Dictionary in recipe.get("outputs", []):
		var gid := str(o.get("good_id", ""))
		var qty := int(round(float(o.get("qty", 0)) * BuildingLevels.mult("output", level)))
		var power := str(o.get("internal_name", "")) == "power"
		rows.append({"caption": "Makes" if rows.is_empty() else "",
			"value": ("%d MW" % qty) if power else "%d %s" % [qty, Catalog.get_display_name(gid)]})
	var energy := int(recipe.get("energy_req", 0))
	if energy > 0:
		rows.append({"caption": "Power", "value": "%d MW" % energy})
	var card := {"title": str(recipe.get("display_name", "")), "rows": rows}
	var goods := {}
	for i: Dictionary in recipe.get("inputs", []):
		goods[str(i.get("good_id", ""))] = int(round(float(i.get("qty", 0)) * BuildingLevels.mult("input", level)))
	if not goods.is_empty():
		card.goods = goods
		card.goods_caption = "Takes"
	return card


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


## In the footer's place while the building comes down: the turns left, and a key to call it off.
func _build_demolishing_row(building: Dictionary) -> Control:
	var iid := str(building.get("instance_id", ""))
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

func _build_recipe_strip(flow: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "BuildingRecipeStrip"
	card.custom_minimum_size = Vector2(0, 156)  # consistent height for 1–4 input / output grids
	# An enamel sign behind the diagram, its grunge kept clear of the icons and arrow (watched below).
	var bare := StyleBoxEmpty.new()
	bare.set_content_margin_all(0)
	card.add_theme_stylebox_override("panel", bare)
	var enamel := BdpV3Enamel.new()
	card.add_child(enamel)

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

# A frameless good icon (cream plate, rounded corners) with the qty PILL superimposed on its
# bottom-right. base_qty/mod_pct (output only) → the pill shows the struck base + effective with a
# coloured outline.
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
# The drum counters and cost gauges: what each last read, so the next rebuild rolls from it.
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
	# Each row is its own module set in the plastic case, fed by a branch off the cable that runs down
	# the case's left side.
	var bare := StyleBoxEmpty.new()
	bare.content_margin_left = V3_DIAG_GUTTER
	bare.content_margin_right = 2
	bare.content_margin_top = 4
	bare.content_margin_bottom = 4
	card.add_theme_stylebox_override("panel", bare)
	vb.add_theme_constant_override("separation", V3_DIAG_MODULE_GAP)
	var cable: Control = BdpV3Cable.new()
	cable.centre_x = V3_DIAG_CABLE_X - V3_DIAG_GUTTER
	card.add_child(cable)
	var all_ok := not rows.is_empty()
	for r_variant: Variant in rows:
		if str((r_variant as Dictionary).get("tone", "info")) not in ["ok", "good", "info"]:
			all_ok = false
			break
	if not all_ok:
		var modules: Array[Control] = []
		for r in rows:
			var row := _diag_row(r)
			vb.add_child(row)
			modules.append(row)
		cable.taps = modules
		return card

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", V3_DIAG_MODULE_GAP)
	body.visible = _diagnostics_open
	var body_modules: Array[Control] = []
	for r in rows:
		var row := _diag_row(r)
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
	# The folded line is a module too, with its lamp lit green.
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
	vb.add_child(body)
	return card


## The diagnostics: where the cable runs (from the card's left), and the modules' left margin, a
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

## A raised module in the diagnostics' case, for one check.
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

## The diagnostics' Visual / Text switch, moulded into the case beside the heading, its two sides
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

## The diagnostics as pictures: the chain left to right, a column a stage, each check a raised icon over
## a lamp; hovering an icon names it in the readout at the foot. Each stage's checks come from
## BuildingReadout (input_checks, inbound_checks, power_checks, plant_checks, output_checks). [stage,
## icons to a row]; a column's share of the width follows its icons to a row.
const V3_DIAG_STAGES := [["Inputs", 1], ["Inbound", 1], ["Power", 1], ["Plant", 1], ["Outputs", 1]]
## Every column is this many rows of icons tall, whatever it holds (the most any stage has, Outputs'
## five), so the columns stand level and a stage can gain checks without the case changing height.
const V3_DIAG_ROWS := 5
## The icons' side, and their lamps' size as a share of the status lamp's (the text rows' size).
const V3_DIAG_ICON_PX := 56.0
## A text row's good, beside its lamp.
const V3_DIAG_GOOD_PX := 36
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


## The visual view. Each stage with checks that apply is a raised module in the case, its name in
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


## Shows the diagnostics' view the switch is set to.
func _v3_show_diag_view() -> void:
	var visual := _v3_diag_shows_visual()
	if _v3_diag_text_card != null and is_instance_valid(_v3_diag_text_card):
		_v3_diag_text_card.visible = not visual
	if _v3_diag_visual_view != null and is_instance_valid(_v3_diag_visual_view):
		_v3_diag_visual_view.visible = visual
	_v3_place_readout.call_deferred()


## Keeps the diagnostics' readout in sight. It sits in its slot at the foot of the visual view; while
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

func _diag_row(r: Dictionary) -> Control:
	var wrap := _v3_diag_module()
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", DS.SP["SM"])
	wrap.add_child(hb)
	var tone := str(r.get("tone", "info"))
	var c := _tone_color(tone)
	# A lamp like the status lamp's, lit for the row's tone; a row about a good shows it too.
	var lamp := BdpV3Lamp.new()
	lamp.lamp_scale = V3_DIAG_LAMP_SCALE
	lamp.set_tone(tone)
	hb.add_child(lamp)
	if str(r.get("good_id", "")) != "":
		# The good itself, unframed and large enough to tell one from another (a framed 18 px icon read as
		# an empty box).
		var good_icon := UIHelpers.make_plain_good_icon(str(r.get("good_id", "")), Catalog.get_internal_name(str(r.get("good_id", ""))), V3_DIAG_GOOD_PX)
		good_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(good_icon)
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
	# The modules sit well in, past the cable's branches, so their text has less room.
	detail.custom_minimum_size = Vector2(PANEL_WIDTH - 180.0, 0)
	col.add_child(detail)
	return wrap

# --- cost to produce (emphasised, per output good) -----------------------------------------

func _build_cost_to_produce(rows: Array) -> PanelContainer:
	var card := _make_card()
	card.name = "CostToProduceCard"   # stable target for the tutorial coach spotlight
	var vb := card.get_child(0) as VBoxContainer
	vb.add_theme_constant_override("separation", DS.SP["SM"])
	_v3_cost_gauges(card, vb, rows)
	return card

## Each output's cost on a gauge set into the section's dark plate, the good's icon beside it. The
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

## Sets a good's icon below a thin metal frame, its tile's corners following the frame's opening.
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
## and maintenance — behind a key that opens a sheet of them (closed by default).
##
## Closed, the key carries the ONE number worth a glance: the net effect on OUTPUT. A
## bare count like "3 active" would fold power and maintenance modifiers into a figure the
## player reads as production, and say nothing about which way any of it went.
##
## Open, only the per-category summaries carry colour. Painting all fourteen individual
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

	_v3_modifiers(mod, total, by_cat)


## The modifiers sheet's rows: each category's net figure, the only coloured one, and the modifiers that
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


## Modifiers, laid out as Inputs is on the control plate: a % sign raised white on the metal, the
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

## Goods held for this building off the tile: the player owns them but cannot see them there,
## so they get a line in the economics rather than living only in the sim.
func _add_carried_rows(vb: VBoxContainer) -> void:
	var held := MatchState.ghost_holding_units(str(_current_building.get("instance_id", "")))
	if held > 0:
		vb.add_child(_metric("Stored for this building", "%d units" % held, DS.PALETTE["TEXT_MUTED"], false))

## The economics (BuildingEconomics.per_turn), on the frame's steel:
##   Value added in production   its output less inputs, labour and upkeep; opens to show each;
##   Transport costs             bringing its inputs in and taking its output to market; opens to show
##                               each side's cost by how it goes;
##   Net Value Added             the first less the second;
## every figure on a mini screen in LED segments after a printed £ (results green, or red below zero;
## costs red); then its revenue and its costs as two bars on one scale; then a lamp for each side's
## transport, with its icon, lit by transport's share of that side's goods (or flagged free: a mine's
## inputs, a power plant's output). Stored goods follow.
const V3_ECON_ICON_PX := 30.0
const V3_ECON_INDENT := 22.0
## A row nested in another opens from a smaller key.
const V3_NESTED_KEY_SCALE := 0.8
## The space the money frame leaves after the modifiers and after the economics.
const V3_MONEY_GAP := 14.0
## Which of the economics rows are open, kept across rebuilds.
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

## One of the economics figures: its name, a printed £ and the figure on an LED screen in `colour`.
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

## One of the economics rows that opens: a wide worn-white key with its name printed in navy and a
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

# --- inbound shipments ---------------------------------------------------------------------

## The inbound shipments: a bay with room for six goods, two to a row, each good's icon and a lamp
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

func _build_shipments(ships: Array) -> PanelContainer:
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
		lamp.set_tone(v3_stock_tone(stored, need, inbound, supply == "Local Suppliers"))
		lamp.tooltip_text = "Supplied by: %s" % supply
		cell.add_child(lamp)
	return row

# --- routing (summaries + the input and output sheets) -------------------------------------

func _input_summary(building: Dictionary, recipe: Dictionary) -> String:
	var service = preload("res://scripts/middleman_service.gd")
	var iid := str(building.instance_id)
	if service.side_all_middleman(iid, "input"): return "Local Suppliers"
	var handover_turns := -1
	for item: Dictionary in recipe.get("inputs", []):
		var gid := str(item.get("good_id", ""))
		if service.in_handover(iid, gid):
			var turns: int = service.handover_turns(iid, gid)
			handover_turns = turns if handover_turns < 0 else mini(handover_turns, turns)
	if handover_turns > 0:
		return "Switching suppliers: first input from the market in %d turn%s" % [handover_turns, "" if handover_turns == 1 else "s"]
	if service.enabled(iid) and (recipe.get("inputs", []) as Array).any(func(item: Dictionary) -> bool: return service.supplies_good(iid, str(item.get("good_id", "")))): return "Mixed logistics"
	var sources := BuildingReadout.input_sources(building, recipe)
	var many := BuildingReadout.places_label(sources)
	if many != "":
		return many
	var names: Array = []
	for s in sources:
		var nm := str(s.get("building_name", ""))
		if not names.has(nm):
			names.append(nm)
	return ", ".join(names) if not names.is_empty() else "Market / unlinked"

func _output_summary(building: Dictionary, recipe: Dictionary) -> String:
	if str(recipe.get("output_name", "")) == "power": return "Electricity grid"
	var service = preload("res://scripts/middleman_service.gd")
	var iid_for_output := str(building.instance_id)
	if service.side_all_middleman(iid_for_output, "output"): return "Local Suppliers"
	if service.enabled(iid_for_output) and (recipe.get("outputs", []) as Array).any(func(item: Dictionary) -> bool: return service.buys_output(iid_for_output, str(item.get("good_id", "")))): return "Mixed logistics"
	var iid := str(building.get("instance_id", ""))
	var gid := BuildingStatus.primary_output_good_id(recipe)
	var many := BuildingReadout.places_label(MatchState.get_output_split_destinations(iid, gid))
	if many != "":
		return many
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
	_open_sheet("Input sources", func(vb: VBoxContainer) -> void: BdpV3Routes.inputs(self, vb, building, recipe))

func _open_output_sheet(building: Dictionary, recipe: Dictionary) -> void:
	_open_sheet("Output destination", func(vb: VBoxContainer) -> void: BdpV3Routes.outputs(self, vb, building, recipe))

# --- labour (headcount, not per turn — the wage is the per-turn figure) ---------------------

## Labour and Wages, on the frame's steel: a factory door for each kind of worker, its name over
## it and its headcount engraved on the kick plate, the window lit when any are employed; then the
## labour cost and the number of workers on drum counters, each labelled beside it. The counters roll
## from what they last read.
func _build_labour(lab: Dictionary) -> VBoxContainer:
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

# --- shared atoms --------------------------------------------------------------------------

func _make_section(text: String, right_text: String = "") -> Control:
	var hb := HBoxContainer.new()
	hb.set_meta("v3_section", text)
	var s := Label.new()
	s.theme_type_variation = "Section"
	s.text = text
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(s)
	if BdpV3Heading.can_show(text):
		# The heading in raised white letters, as INPUTS and OUTPUTS are on the control plate.
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
	var w := _panel_width() + _sheet_extra_width
	custom_minimum_size = Vector2(w, h)
	size = Vector2(w, h)

## The panel's width before a sheet widens it.
func _panel_width() -> float:
	return V3_PANEL_WIDTH

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
		note.text = "Choose inputs and outputs independently. Manage logistics uses generic carriers for physical deliveries. Goods Local Suppliers hold stay private to this building. Goods they retain use your tile storage."
		vb.add_child(note)
		vb.add_child(_route_card("Inputs",_input_summary(building,recipe),func() -> void: _open_input_sources_sheet(building,recipe), INPUT_ICON))
		vb.add_child(_route_card("Outputs",_output_summary(building,recipe),func() -> void: _open_output_sheet(building,recipe), OUTPUT_ICON))
		var service = preload("res://scripts/middleman_service.gd")
		var iid := str(building.instance_id)
		if service.enabled(iid):
			var p: Dictionary = service.preview(iid)
			for pair in [["Local Suppliers input purchases",float(p.buy.goods_value)],["Local Suppliers sale value",float(p.sale.goods_value)],["Upfront service + factory cash",float(p.upfront)],["Protected commitments",float(p.protected_commitments)],["Loan needed",float(p.funding_draw)]]:
				vb.add_child(_metric(str(pair[0]),"£%.2f" % float(pair[1]),DS.PALETTE["TEXT"],false))
			var status := Label.new()
			status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			status.text = str(p.reason)+" Estimates use current prices. Managed purchases and deliveries are billed separately; future sales cannot fund inputs."
			vb.add_child(status)
			for side in ["inputs","outputs"]:
				for gid in p[side]:
					vb.add_child(_metric("Private %s: %s" % [side,Catalog.get_display_name(str(gid))],str(p[side][gid]),DS.PALETTE["TEXT"],false)))

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
		preload("res://scripts/logistics_confirmation.gd").request(self, "managed", action, Callable(), {"side": side, "destination": "market" if source == "market" else "stockpile", "tile": str(building.get("tile_id", ""))})
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

func _request_logistics_mode(building: Dictionary, side: String, mode: String, after_change: Callable = Callable(), good_id: String = "", destination: String = "", confirm: bool = true) -> void:
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
	if not confirm:
		apply.call()
		return
	preload("res://scripts/logistics_confirmation.gd").request(self, mode, apply, Callable(), {"side": side, "good": good_id, "destination": destination, "tile": str(building.get("tile_id", ""))})
