extends PanelContainer
## Building Detail v2 — the redesigned, scenario-adaptive detail panel (Phase 1).
## Code-instantiated by world_map, toggled by the `swap bdp` cheat (MatchState.use_bdp_v2).
## Renders a shared, UI-agnostic readout (building_readout.gd): header + status badge → adaptive
## recipe/flow strip (frameless good icons in independent input/output grids) → always-open
## diagnostics checklist → emphasised per-output cost-to-produce → economics → inbound shipments →
## routing (with the map-highlight signal) → labour. Live via coalesced refresh. Upgrade/recipe/
## sell/demolish sheets, banners and battery/infra/port variants land in later phases.
## See docs/building-detail-v2-plan.md. Mirrors the tile_info_panel v1→v2 swap.

const BuildingReadout := preload("res://scripts/building_readout.gd")
const BuildingStatus := preload("res://scripts/building_status.gd")
const GoodIcons := preload("res://scripts/good_icons.gd")
const UIHelpers := preload("res://scripts/ui_helpers.gd")
const BuyDialog := preload("res://scripts/buy_building_dialog.gd")
const BuildingLevels := preload("res://scripts/building_levels.gd")
const InfrastructureInfo := preload("res://scripts/infrastructure_info.gd")

const HEADER_HEIGHT := 44.0
const PANEL_EDGE_MARGIN := 20.0
const TOP_BAR_CLEARANCE := 114.0   # clears the top bar AND the briefing notch hang + shadow (owner 2026-07-11)
const BOTTOM_CLEARANCE := 110.0  # fallback: keep clear of the bottom menu when no tile panel to match
const PANEL_WIDTH := 460.0
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
var _subtitle_label: Label = null
var _badge: PanelContainer = null
var _badge_label: Label = null
var _body: VBoxContainer = null
var _scroll: ScrollContainer = null
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
var _sheet: Control = null

func _ready() -> void:
	if DS and DS.theme:
		theme = DS.theme
	custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_build_shell()
	_wire_live_refresh()
	visibility_changed.connect(_on_visibility_changed)

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
		margin.add_theme_constant_override("margin_" + side, 26)   # clear the brass frame
	add_child(margin)
	add_child(preload("res://scripts/brass_pipe_frame.gd").new())   # brass frame, drawn on top

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", DS.SP["SM"])
	margin.add_child(outer)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", DS.SP["SM"])
	outer.add_child(header)
	_title_label = Label.new()
	_title_label.theme_type_variation = "Title"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_label.custom_minimum_size = Vector2(PANEL_WIDTH - 2.0 * DS.SP["MD"] - 44.0, 0)
	header.add_child(_title_label)
	var close_button := Button.new()
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(32, 32)
	close_button.pressed.connect(_hide_panel)
	header.add_child(close_button)

	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", DS.SP["SM"])
	outer.add_child(meta)
	_badge = PanelContainer.new()
	_badge_label = Label.new()
	_badge_label.theme_type_variation = "Caption"
	_badge.add_child(_badge_label)
	meta.add_child(_badge)
	_subtitle_label = Label.new()
	_subtitle_label.theme_type_variation = "Caption"
	_subtitle_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.add_child(_subtitle_label)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", DS.SP["SM"])
	_scroll.add_child(_body)

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
	var live: Dictionary = MatchState.get_building(iid) if iid != "" else {}
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

func _rebuild(building: Dictionary) -> void:
	for child in _body.get_children():
		child.queue_free()

	var building_data: Dictionary = Catalog.get_building(str(building.get("building_id", "")))
	var recipe: Dictionary = Catalog.get_recipe(str(building.get("recipe_id", "")))
	var is_infra := str(building_data.get("category", "")).to_lower() == "infrastructure"
	var kind := BuildingReadout.classify(building_data, recipe, str(building.get("building_id", "")))

	var display_name := str(building_data.get("display_name", building.get("building_id", "Building")))
	var recipe_name := str(recipe.get("display_name", ""))
	_title_label.text = display_name if recipe_name == "" else "%s — %s" % [display_name, recipe_name]
	# Catalog.tile_label, not the raw id: this was the one surface still printing
	# "tile_5_9" at the player instead of "Stoneshore Fields - (5, 9)".
	var _tile := str(building.get("tile_id", ""))
	_subtitle_label.text = "Level %d · %s" % [
		int(building.get("level", 1)), Catalog.tile_label(_tile) if _tile != "" else "—"]

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
		_body.add_child(_build_port_card())
	elif is_infra:
		_body.add_child(_build_infra_card())
		# Levellable infra (roads/rails/pipes/reinf_pipes/cables) gets the same Upgrade
		# button as production buildings — it opens the cash-only upgrade sheet.
		if MatchState.INFRA_UPGRADABLE.has(str(building_data.get("internal_name", ""))):
			_body.add_child(_build_primary_actions(building, building_data))
	elif BuildingReadout.is_recipe_kind(kind) and (not (fl.get("output", {}) as Dictionary).is_empty() or not (fl.get("inputs", []) as Array).is_empty()):
		_body.add_child(_build_recipe_strip(fl))

	# primary actions (upgrade · change recipe) + routing (input sources · output destination),
	# both right under the recipe strip; routing opens action sheets.
	if BuildingReadout.is_recipe_kind(kind) and not is_infra:
		_body.add_child(_build_primary_actions(building, building_data))
		_body.add_child(_build_routing_buttons(building, recipe))

	_body.add_child(_make_section("Diagnostics", "always shown"))
	_body.add_child(_build_diagnostics(BuildingReadout.diagnostics(building, recipe, building_data, is_infra)))

	# emphasised cost-to-produce (per output good, vs its market price)
	if not is_infra and kind != "battery":
		var cost_rows := BuildingReadout.cost_to_produce(building)
		if not cost_rows.is_empty():
			_body.add_child(_make_section("Cost to produce"))
			_body.add_child(_build_cost_to_produce(cost_rows))

	# Modifiers (owner 2026-07-10): everything currently bending this building's
	# numbers, in an accordion whose chevroned section header expands on click.
	if not is_infra and kind != "battery":
		_add_modifiers_accordion(building, recipe)

	_body.add_child(_make_section("Economics · per turn"))
	_body.add_child(_build_economics(BuildingReadout.economics(building, recipe, building_data)))
	if is_infra:
		_body.add_child(_make_section("Infrastructure"))
		_body.add_child(_build_infrastructure_details(building_data))

	var pw := BuildingReadout.power(building, recipe)
	if bool(pw.get("needs", false)):
		_body.add_child(_build_power_line(pw))

	# inbound shipments
	var ships := BuildingReadout.shipments(building, recipe)
	if not ships.is_empty():
		_body.add_child(_make_section("Inbound shipments"))
		_body.add_child(_build_shipments(ships))

	_body.add_child(_make_section("Labour on this building"))
	_body.add_child(_build_labour(BuildingReadout.labour(building_data, recipe)))

	# sell / demolish (player-owned; the early NPC/construction returns skip this)
	_body.add_child(_build_sell_demolish_row(building, building_data))

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

# --- NPC-owned body (recipe + big "Owned by [company]" + Buy; nothing else, no frost) ------

func _render_npc(building: Dictionary, building_data: Dictionary, recipe: Dictionary, own: Dictionary) -> void:
	_set_badge({"label": "NPC-owned", "tone": "info"})
	var kind := BuildingReadout.classify(building_data, recipe, str(building.get("building_id", "")))
	if kind == "port":
		_body.add_child(_build_port_card())
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
		buy.theme_type_variation = "Primary"
		buy.text = "Buy — £%s" % _fmt_int(price)
		buy.custom_minimum_size = Vector2(0, 46)
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
	if iid == "" or not MatchState.buildings.has(iid):
		return
	if not MatchState.deduct_money(float(price)):
		MatchState.build_rejected_no_funds.emit("Not enough money to buy %s — need £%d, you have £%.0f" % [building_name, price, MatchState.money])
		return
	MatchState.set_building_owner(iid, MatchState.LOCAL_PLAYER)
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
	head.text = "Energy storage — %d / %d cells loaded" % [int(b.get("loaded", 0)), int(b.get("slots", 0))]
	vb.add_child(head)
	var note := Label.new()
	note.add_theme_color_override("font_color", CREAM_INK)
	note.text = "Stores energy — runs no recipe"
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
			var unlocked := MatchState.battery_type_loadable(gid)
			var fill := MatchState.battery_cells_to_fill(tile, gid)
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
				var n := MatchState.load_battery_cells(tile, gid, loadable)
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
			var unlocked := MatchState.battery_type_loadable(gid)
			var fill := MatchState.battery_cells_to_fill(tile, gid)
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
				var quote := TransportService.quote_market_buy(tile, gid, fill, MatchState.seaport_would_cover(gid))
				var cost := float(quote.get("cost", 0.0))
				subtitle = ("fills %d cells · £%.2f" % [fill, cost]) if not quote.is_empty() else "no market route to this tile"
				btn_text = "Order %d" % fill
				enabled = not quote.is_empty()
			vb.add_child(_battery_type_row(gid, str(internal), subtitle, btn_text, enabled, func() -> void:
				var r := MatchState.order_battery_fill_market(tile, gid, fill)
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

func _build_port_card() -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = CREAM
	style.set_corner_radius_all(10)
	style.set_content_margin_all(14)
	card.add_theme_stylebox_override("panel", style)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	card.add_child(vb)
	var head := Label.new()
	head.theme_type_variation = "BuildingName"
	head.add_theme_color_override("font_color", CREAM_INK)
	head.text = "Connected to the global market"
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(head)
	var sub := Label.new()
	sub.add_theme_color_override("font_color", CREAM_INK)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.text = "The default sea route for this coastal region — output ships out to, and inputs arrive from, the world market through this port."
	vb.add_child(sub)
	return card

# --- primary actions (upgrade · change recipe) ---------------------------------------------

func _build_primary_actions(building: Dictionary, _building_data: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DS.SP["SM"])
	var iid := str(building.get("instance_id", ""))
	var lvl := int(building.get("level", 1))
	# Infra levels live on the TILE (the instance copy can lag) — label from the truth.
	var b_internal := str(Catalog.get_building(str(building.get("building_id", ""))).get("internal_name", ""))
	if MatchState.INFRA_UPGRADABLE.has(b_internal):
		lvl = MatchState.infra_tile_level(building)

	var up := Button.new()
	up.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	up.custom_minimum_size = Vector2(0, 40)
	if not MatchState.pending_upgrade(iid).is_empty():
		up.text = "Upgrading…"
		up.disabled = true
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
		if MatchState.is_retooling(iid):
			var t := MatchState.retrofit_turns_remaining(iid)
			rc.text = "Retooling — %d turn%s" % [t, "" if t == 1 else "s"]
		else:
			rc.text = "Change recipe (%d)" % alt_count
		rc.pressed.connect(func() -> void: _open_recipe_sheet(building))
		row.add_child(rc)
	return row

# In-panel upgrade action sheet — the upgrade_dialog.gd content (level stat deltas, material
# sourcing modes) rendered as one of the BDP's own sheets. Driven by MatchState.preview_upgrade /
# start_upgrade / cancel_upgrade.
func _open_upgrade_sheet(building: Dictionary) -> void:
	var iid := str(building.get("instance_id", ""))
	_open_sheet("Upgrade", func(vb: VBoxContainer) -> void:
		var pv := MatchState.preview_upgrade(iid)
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
			var awaiting := str(pv.get("pending_status", "")) == MatchState.UPGRADE_STATUS_AWAITING
			var note := Label.new()
			note.theme_type_variation = "Body"
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			note.add_theme_color_override("font_color", DS.PALETTE["OK"])
			note.text = ("Waiting on materials, then %d turn%s to upgrade." % [left, "" if left == 1 else "s"]) if awaiting else ("Upgrade in progress — %d turn%s left." % [left, "" if left == 1 else "s"])
			vb.add_child(note)
			var is_infra_pending := bool(pv.get("infra", false))
			var cancel := Button.new()
			cancel.text = "Cancel upgrade"
			cancel.custom_minimum_size = Vector2(0, 40)
			cancel.pressed.connect(func() -> void:
				MatchState.cancel_upgrade(iid)
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
				var res := MatchState.start_upgrade(iid)
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
			var rl := Label.new()
			rl.theme_type_variation = "Body"
			rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			rl.add_theme_color_override("font_color", DS.PALETTE["DANGER"])
			rl.text = "Requires research: %s" % str(pv.get("research_gate", ""))
			vb.add_child(rl)
		if not bool(pv.get("fits", true)):
			var nf := Label.new()
			nf.theme_type_variation = "Body"
			nf.add_theme_color_override("font_color", DS.PALETTE["DANGER"])
			nf.text = "Not enough room on the tile for the larger building."
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
	var res := MatchState.start_upgrade(iid, mode)
	if bool(res.get("ok", false)):
		var awaiting := str(res.get("status", "")) == MatchState.UPGRADE_STATUS_AWAITING
		MatchState.request_toast(("Upgrade queued — sourcing materials, then %d turns." % duration) if awaiting else ("Upgrade started — ready in %d turns." % duration), "success")
		_close_sheet()
		_queue_refresh()
	else:
		MatchState.request_toast(str(res.get("reason", "Cannot upgrade.")), "warning")

# A material cell for the upgrade sheet: framed good icon (need pill) + have/need caption.
func _upgrade_material_cell(m: Dictionary) -> Control:
	var good_id := str(m.get("good_id", ""))
	var need := int(m.get("need", 0))
	var have := int(m.get("have", 0))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", DS.SP["XS"])
	col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_good_icon_pill(good_id, Catalog.get_internal_name(good_id), need, 52))
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

func _open_sheet(title: String, populate: Callable) -> void:
	_close_sheet()
	var sheet := PanelContainer.new()
	sheet.name = "ActionSheet"
	var st := StyleBoxFlat.new()
	st.bg_color = DS.PALETTE["BG_PANEL"]
	st.set_corner_radius_all(10)
	st.set_content_margin_all(0)
	sheet.add_theme_stylebox_override("panel", st)
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, DS.SP["MD"])
	sheet.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", DS.SP["SM"])
	margin.add_child(vb)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", DS.SP["SM"])
	vb.add_child(header)
	var back := Button.new()
	back.text = "‹"
	back.custom_minimum_size = Vector2(36, 32)
	back.pressed.connect(_close_sheet)
	header.add_child(back)
	var tl := Label.new()
	tl.theme_type_variation = "BuildingName"
	tl.text = title
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(tl)
	vb.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", DS.SP["SM"])
	scroll.add_child(body)
	populate.call(body)
	add_child(sheet)  # stacks over the panel's content (later child draws on top)
	_sheet = sheet

func _close_sheet() -> void:
	if _sheet != null and is_instance_valid(_sheet):
		_sheet.queue_free()
	_sheet = null

# --- change-recipe sheet -------------------------------------------------------------------

func _open_recipe_sheet(building: Dictionary) -> void:
	var iid := str(building.get("instance_id", ""))
	var building_id := str(building.get("building_id", ""))
	var current := str(building.get("recipe_id", ""))
	_open_sheet("Change recipe", func(vb: VBoxContainer) -> void:
		if MatchState.is_retooling(iid):
			var t := MatchState.retrofit_turns_remaining(iid)
			var note := Label.new()
			note.theme_type_variation = "Body"
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			note.text = "Retooling in progress — %d turn%s left. The building produces nothing until it completes." % [t, "" if t == 1 else "s"]
			vb.add_child(note)
			var cancel := Button.new()
			cancel.text = "Cancel retooling"
			cancel.custom_minimum_size = Vector2(0, 40)
			cancel.pressed.connect(func() -> void:
				MatchState.cancel_retrofit(iid)
				_close_sheet()
				_queue_refresh())
			vb.add_child(cancel)
			return
		var tier := MatchState.retrofit_cost_tier()
		var info := Label.new()
		info.theme_type_variation = "Caption"
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.text = "A one-off fee of £%d, then %d turn%s of retooling (at %d%% labour) — the building produces nothing until it completes. Modifiers and level are kept." % [
			int(tier.get("fee", 0.0)), int(tier.get("turns", 2)), "" if int(tier.get("turns", 2)) == 1 else "s", int(round(float(tier.get("labour", 0.5)) * 100.0))]
		vb.add_child(info)
		for r in Catalog.get_recipes_for_building(building_id):
			vb.add_child(_recipe_choice_row(iid, r, str(r.get("recipe_id", "")) == current)))

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
	var parts: Array = []
	for inp in recipe.get("inputs", []):
		parts.append("%d %s" % [int(inp.get("qty", 0)), BuildingStatus.good_display_from_internal(str(inp.get("internal_name", "")))])
	var flow_line := Label.new()
	flow_line.theme_type_variation = "Caption"
	flow_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	flow_line.text = "%s  →  %d %s · %d MW" % [
		", ".join(parts) if not parts.is_empty() else "no inputs", int(recipe.get("output_qty", 0)), out_disp, int(recipe.get("energy_req", 0))]
	vb.add_child(flow_line)
	return card

func _apply_retrofit(iid: String, recipe: Dictionary) -> void:
	var res := MatchState.start_retrofit(iid, str(recipe.get("recipe_id", "")))
	if not bool(res.get("ok", false)):
		MatchState.request_toast(str(res.get("reason", "Could not retool.")), "warning")
	else:
		MatchState.request_toast("Retooling to %s" % str(recipe.get("display_name", "new recipe")), "success")
	_close_sheet()
	_queue_refresh()

# --- sell / demolish -----------------------------------------------------------------------

func _build_sell_demolish_row(building: Dictionary, building_data: Dictionary) -> Control:
	var iid := str(building.get("instance_id", ""))
	if MatchState.is_demolishing(iid):
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", DS.SP["SM"])
		var t := MatchState.demolish_turns_remaining(iid)
		var note := Label.new()
		note.theme_type_variation = "Body"
		note.add_theme_color_override("font_color", DS.PALETTE["DANGER"])
		note.text = "Demolishing — %d turn%s left" % [t, "" if t == 1 else "s"]
		col.add_child(note)
		var cancel := Button.new()
		cancel.text = "Cancel demolition"
		cancel.custom_minimum_size = Vector2(0, 40)
		cancel.pressed.connect(func() -> void:
			MatchState.cancel_demolish(iid)
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
		draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(size.x, size.y * 0.5), Vector2(0, size.y)]), col)

# A thin navy outline rectangle inset from the card edge (the recipe card's inner border).
class _InsetOutline extends Control:
	var col := Color(0.0, 0.119856, 0.243095)
	var inset := 4.0
	func _ready() -> void:
		resized.connect(queue_redraw)
	func _draw() -> void:
		draw_rect(Rect2(inset, inset, size.x - inset * 2.0, size.y - inset * 2.0), col, false, 1.5)

# A radio dot (ring + filled centre when on) for the destination option cards.
class _RadioDot extends Control:
	var on := false
	var col := Color(0.65, 0.78, 0.83)
	func _ready() -> void:
		resized.connect(queue_redraw)
	func _draw() -> void:
		var ctr := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 1.0
		draw_arc(ctr, r, 0.0, TAU, 24, Color(col.r, col.g, col.b, 1.0 if on else 0.5), 2.0, true)
		if on:
			draw_circle(ctr, r * 0.5, col)

func _build_recipe_strip(flow: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = CREAM
	style.set_corner_radius_all(0)  # squared corners
	style.set_content_margin_all(0)  # children fill the full card so the outline sits 4px from the edge
	card.add_theme_stylebox_override("panel", style)
	card.custom_minimum_size = Vector2(0, 156)  # consistent height for 1–4 input / output grids
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
	row.add_child(_recipe_arrow(int(flow.get("power_in", 0))))

	# outputs — a single big icon; its pill carries the base→modified delta (struck base + effective)
	var output: Dictionary = flow.get("output", {})
	if not output.is_empty():
		var out_wrap := CenterContainer.new()
		out_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		out_wrap.clip_contents = false
		out_wrap.add_child(_recipe_icon(str(output.get("good_id", "")), str(output.get("internal", "")),
			int(output.get("qty", 0)), 126, 3, int(output.get("base_qty", -1)), int(flow.get("mod_pct", 0))))
		row.add_child(out_wrap)
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
	slot.custom_minimum_size = Vector2(size, size)
	slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot.clip_contents = false
	if good_id != "":
		slot.tooltip_text = Catalog.get_display_name(good_id)  # hover shows the good's name
	var tex := GoodIcons.texture_for(good_id, internal, size <= 48)
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
func _good_icon_pill(good_id: String, internal: String, qty: int, size: int, base_qty: int = -1, mod_pct: int = 0) -> Control:
	var holder := UIHelpers.make_framed_good_icon(good_id, internal, size, size <= 48)
	holder.add_child(_qty_pill(qty, base_qty, mod_pct))
	return holder

# Back-compat name used by construction / shipments / demolish — now the pill icon.
func _flat_good_cell(good_id: String, internal: String, qty: int, size: int) -> Control:
	return _good_icon_pill(good_id, internal, qty, size)

# Navy qty pill overhanging an icon's bottom-right. With a modifier (base != qty) it shows the struck
# base + effective and a green (positive) / red (negative) 2px outline; otherwise a plain pill.
func _qty_pill(qty: int, base_qty: int = -1, _mod_pct: int = 0) -> Control:
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
	pill.offset_left = -w + 8
	pill.offset_top = -h + 8
	pill.offset_right = 8
	pill.offset_bottom = 8
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
func _recipe_arrow(power_in: int) -> Control:
	var arrow := HBoxContainer.new()
	arrow.add_theme_constant_override("separation", 0)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var body_h := 46
	var body := PanelContainer.new()
	body.custom_minimum_size = Vector2(0, body_h)
	body.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bst := StyleBoxFlat.new()
	bst.bg_color = CREAM_INK
	bst.corner_radius_top_left = 6
	bst.corner_radius_bottom_left = 6
	bst.content_margin_left = 12
	bst.content_margin_right = 8
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
	arrow.add_child(body)
	var head := _ArrowHead.new()
	head.col = CREAM_INK
	head.custom_minimum_size = Vector2(28, body_h)
	head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	arrow.add_child(head)
	return arrow

# --- diagnostics ---------------------------------------------------------------------------

func _build_diagnostics(rows: Array) -> PanelContainer:
	var card := _make_card()
	card.name = "DiagnosticsCard"   # stable target for the tutorial coach spotlight
	var vb := card.get_child(0) as VBoxContainer
	vb.add_theme_constant_override("separation", 0)
	for i in rows.size():
		vb.add_child(_diag_row(rows[i], i > 0))
	return card

func _diag_row(r: Dictionary, top_border: bool) -> Control:
	var wrap := PanelContainer.new()
	if top_border:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_color = Color(DS.PALETTE["BORDER_SOFT"].r, DS.PALETTE["BORDER_SOFT"].g, DS.PALETTE["BORDER_SOFT"].b, 0.18)
		sb.border_width_top = 1
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		wrap.add_theme_stylebox_override("panel", sb)
	else:
		var sb2 := StyleBoxEmpty.new()
		sb2.content_margin_bottom = 8
		wrap.add_theme_stylebox_override("panel", sb2)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", DS.SP["SM"])
	wrap.add_child(hb)
	var tone := str(r.get("tone", "info"))
	var c := _tone_color(tone)
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
		chip.add_child(UIHelpers.make_framed_good_icon(row_good, Catalog.get_internal_name(row_good), 18, true))
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
	detail.custom_minimum_size = Vector2(PANEL_WIDTH - 110.0, 0)
	col.add_child(detail)
	return wrap

# --- cost to produce (emphasised, per output good) -----------------------------------------

func _build_cost_to_produce(rows: Array) -> PanelContainer:
	var card := _make_card()
	card.name = "CostToProduceCard"   # stable target for the tutorial coach spotlight
	var vb := card.get_child(0) as VBoxContainer
	vb.add_theme_constant_override("separation", DS.SP["SM"])
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

# --- modifiers (accordion above economics) --------------------------------------------------

## Everything currently bending this building's numbers — recipe-output modifiers,
## workforce output effects, and power-draw modifiers — behind a chevroned section
## header that expands on click (collapsed by default).
func _add_modifiers_accordion(building: Dictionary, recipe: Dictionary) -> void:
	var rows: Array = []
	var mod: Dictionary = BuildingStatus.net_output_modifier(building, recipe)
	for p in (mod.get("parts", []) as Array):
		rows.append({"cat": "Output", "label": str(p.get("label", "")), "pct": float(p.get("pct", 0.0))})
	for p in (mod.get("workforce_parts", []) as Array):
		rows.append({"cat": "Workforce", "label": str(p.get("label", "")), "pct": float(p.get("pct", 0.0))})
	var bid := str(building.get("building_id", ""))
	var pw: Dictionary = Modifiers.resolve_pct("building_power", bid, {"building_id": bid})
	for p in (pw.get("parts", []) as Array):
		rows.append({"cat": "Power draw", "label": str(p.get("label", "")), "pct": float(p.get("pct", 0.0))})

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
	var count_tag := ("%d active" % rows.size()) if not rows.is_empty() else "none"
	var right := Label.new()
	right.theme_type_variation = "Caption"
	right.text = count_tag
	right.add_theme_color_override("font_color", DS.PALETTE["TEXT_DIM"])
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(right)
	_body.add_child(header)

	var card := _make_card()
	card.visible = false
	var vb := card.get_child(0) as VBoxContainer
	vb.add_theme_constant_override("separation", 3)
	if rows.is_empty():
		var none := Label.new()
		none.theme_type_variation = "Caption"
		none.text = "No active modifiers on this building."
		none.add_theme_color_override("font_color", DS.PALETTE["TEXT_MUTED"])
		vb.add_child(none)
	for r in rows:
		var pct := float(r.get("pct", 0.0))
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", DS.SP["SM"])
		var cat := Label.new()
		cat.theme_type_variation = "Caption"
		cat.text = str(r.get("cat", ""))
		cat.add_theme_color_override("font_color", DS.PALETTE["TEXT_DIM"])
		cat.custom_minimum_size = Vector2(84, 0)
		line.add_child(cat)
		var lbl := Label.new()
		lbl.theme_type_variation = "Body"
		lbl.text = str(r.get("label", ""))
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.custom_minimum_size = Vector2(PANEL_WIDTH - 220.0, 0)
		line.add_child(lbl)
		var val := Label.new()
		val.theme_type_variation = "Numeric"
		val.text = "%s%d%%" % ["+" if pct >= 0.0 else "−", absi(int(round(pct)))]
		val.add_theme_color_override("font_color", DS.PALETTE["OK"] if pct >= 0.0 else DS.PALETTE["DANGER"])
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(val)
		vb.add_child(line)
	_body.add_child(card)

	header.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			header.accept_event()
			card.visible = not card.visible
			chevron.text = "▾" if card.visible else "▸")

# --- economics -----------------------------------------------------------------------------

func _build_economics(econ: Dictionary) -> PanelContainer:
	var card := _make_card()
	var vb := card.get_child(0) as VBoxContainer
	# One "Output value" figure (market worth of the run), tagged (sold) when it actually reaches the
	# market this turn or (if sold) otherwise, plus the freight to its set destination. Net folds both
	# in. Skipped for generators / infra (no sellable good → units_out 0).
	var units_out := int(econ.get("units_out", 0))
	if units_out > 0:
		var tag := "(sold)" if bool(econ.get("sells", false)) else "(if sold)"
		vb.add_child(_metric("Output value %s" % tag, "+£%.2f" % float(econ.get("output_value", 0.0)), DS.PALETTE["OK"], false))
		var tc := float(econ.get("transport_cost", 0.0))
		vb.add_child(_metric("Transport cost", ("−£%.2f" % tc) if tc > 0.0 else "£0.00", DS.PALETTE["DANGER"] if tc > 0.0 else DS.PALETTE["TEXT_MUTED"], false))
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
	# Carbon levy on this recipe's taxed inputs (only shown once the policy is in force).
	var carbon_tax := float(econ.get("carbon_tax", 0.0))
	if carbon_tax > 0.0:
		vb.add_child(_metric("Carbon tax / turn", "−£%.2f" % carbon_tax, DS.PALETTE["DANGER"], false))
	vb.add_child(HSeparator.new())
	var net := float(econ.get("net", 0.0))
	vb.add_child(_metric("Net / turn", "%s£%.2f" % ["+" if net >= 0.0 else "−", absf(net)], DS.PALETTE["OK"] if net >= 0.0 else DS.PALETTE["DANGER"], true))
	return card

func _metric(key: String, value: String, value_color: Color, strong: bool) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", DS.SP["SM"])
	var k := Label.new()
	k.theme_type_variation = "Body" if strong else "Caption"
	k.text = key
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
		top.text = "%s — %d/%d stored" % [str(s.get("name", "")), stored, need]
		top.add_theme_color_override("font_color", DS.PALETTE["OK"] if stored >= need else DS.PALETTE["WARN"])
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

# --- routing (read-only summary + map highlight) -------------------------------------------

func _build_routing_buttons(building: Dictionary, recipe: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DS.SP["SM"])
	if not (recipe.get("inputs", []) as Array).is_empty():
		row.add_child(_route_card("Input sources", _input_summary(building, recipe), func() -> void: _open_input_sources_sheet(building, recipe)))
	var out_card := _route_card("Output destination", _output_summary(building, recipe), func() -> void: _open_output_sheet(building, recipe))
	out_card.name = "OutputDestCard"   # tutorial spotlight target
	row.add_child(out_card)
	return row

func _input_summary(building: Dictionary, recipe: Dictionary) -> String:
	var names: Array = []
	for s in BuildingReadout.input_sources(building, recipe):
		var nm := str(s.get("building_name", ""))
		if not names.has(nm):
			names.append(nm)
	return ", ".join(names) if not names.is_empty() else "Market / unlinked"

func _output_summary(building: Dictionary, recipe: Dictionary) -> String:
	var route := BuildingReadout.output_route(building, recipe)
	var dest := str(route.get("destination", "—"))
	if not bool(route.get("reachable", true)):
		dest += " · no route"
	# Quantity-capped tile route (CTRL+click flow): show the split — what ships out
	# and what stays behind, each on its own line (the card grows to fit).
	var iid := str(building.get("instance_id", ""))
	var gid := BuildingStatus.primary_output_good_id(recipe)
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
func _route_card(label: String, value: String, on_press: Callable) -> Control:
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
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	card.add_child(vb)
	var l := Label.new()
	l.theme_type_variation = "Caption"
	l.text = label.to_upper()
	l.add_theme_color_override("font_color", DS.PALETTE["TEXT_DIM"])
	vb.add_child(l)
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

func _open_input_sources_sheet(building: Dictionary, recipe: Dictionary) -> void:
	var iid := str(building.get("instance_id", ""))
	_open_sheet("Input sources", func(vb: VBoxContainer) -> void:
		var note := Label.new()
		note.theme_type_variation = "Caption"
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.text = "Choose where each input is drawn from — auto-routed from a linked producer on your network (falling back to the market), or restricted to this tile's stockpile only."
		vb.add_child(note)
		# Group linked producers by input good so each good gets its own section.
		var producers: Dictionary = {}
		for s in BuildingReadout.input_sources(building, recipe):
			var g := str(s.get("good_id", ""))
			if not producers.has(g):
				producers[g] = []
			producers[g].append(s)
		var inputs: Array = recipe.get("inputs", [])
		for ii in inputs.size():
			var inp: Dictionary = inputs[ii]
			var gid := str(inp.get("good_id", ""))
			var internal := str(inp.get("internal_name", ""))
			var nm := BuildingStatus.good_display_from_internal(internal)
			if ii > 0:
				vb.add_child(HSeparator.new())
			# per-good section header (icon + name + qty/turn)
			var head := HBoxContainer.new()
			head.add_theme_constant_override("separation", DS.SP["SM"])
			head.add_child(_good_icon_pill(gid, internal, int(inp.get("qty", 0)), MARKET_ICON))
			var hcol := VBoxContainer.new()
			hcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hcol.add_theme_constant_override("separation", 0)
			hcol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			head.add_child(hcol)
			var name_l := Label.new()
			name_l.theme_type_variation = "BuildingName"
			name_l.text = nm
			hcol.add_child(name_l)
			var qty_l := Label.new()
			qty_l.theme_type_variation = "Caption"
			qty_l.text = "%d / turn" % int(inp.get("qty", 0))
			hcol.add_child(qty_l)
			vb.add_child(head)
			# editable source toggle — auto-route vs tile-only
			var tile_only := MatchState.is_input_tile_only(iid, gid)
			vb.add_child(_dest_option("Auto-route", "Draw from a linked producer on your network, or buy from the market.", not tile_only, func() -> void:
				MatchState.set_input_tile_only(iid, gid, false)
				_queue_refresh()
				_open_input_sources_sheet(building, recipe)))
			vb.add_child(_dest_option("Tile stockpile only", "Only consume this input from this tile's stockpile.", tile_only, func() -> void:
				MatchState.set_input_tile_only(iid, gid, true)
				_queue_refresh()
				_open_input_sources_sheet(building, recipe)))
			# linked producers feeding this good (Go To), if any
			var srcs: Array = producers.get(gid, [])
			if not srcs.is_empty():
				var sh := Label.new()
				sh.theme_type_variation = "Caption"
				sh.text = "SUPPLIED BY"
				sh.add_theme_color_override("font_color", DS.PALETTE["TEXT_DIM"])
				vb.add_child(sh)
				for s in srcs:
					vb.add_child(_consumer_row(str(s.get("building_name", "")), str(s.get("instance_id", ""))))
			elif not tile_only:
				var mkt := Label.new()
				mkt.theme_type_variation = "Caption"
				mkt.text = "No linked producer — bought from the market."
				mkt.add_theme_color_override("font_color", DS.PALETTE["TEXT_MUTED"])
				vb.add_child(mkt))

func _open_output_sheet(building: Dictionary, recipe: Dictionary) -> void:
	var iid := str(building.get("instance_id", ""))
	var tile_id := str(building.get("tile_id", ""))
	var good_id := BuildingStatus.primary_output_good_id(recipe)
	_open_sheet("Output destination", func(vb: VBoxContainer) -> void:
		if good_id == "":
			return
		var cur_dest := MatchState.get_output_stockpile_destination(iid, good_id)
		var is_market := MatchState.is_output_market(iid, good_id)
		var on_tile := cur_dest != "" and cur_dest == tile_id
		var other := cur_dest != "" and cur_dest != tile_id
		if not is_market and not on_tile and not other:  # no explicit route → the global sell mode
			if MatchState.sell_mode == MatchState.SellMode.STOCKPILE_ALL:
				on_tile = true
			else:
				is_market = true
		# Selecting Market / Tile re-renders the sheet in place (keeps it open); only
		# "ship to another tile" hides the panel so the player can pick a map tile.
		vb.add_child(_dest_option("Global market", "Sell at market price via the nearest port.", is_market, func() -> void:
			MatchState.route_output_to_market(iid, good_id)
			_queue_refresh()
			_open_output_sheet(building, recipe)))
		vb.add_child(_dest_option("Tile stockpile", "Store the output on this tile for later use.", on_tile, func() -> void:
			MatchState.set_output_stockpile_destination(iid, tile_id, good_id)
			_queue_refresh()
			_open_output_sheet(building, recipe)))
		vb.add_child(_dest_option("Ship to another tile", "Pick a tile on the map to feed a downstream building you own.", other, func() -> void:
			MatchState.begin_output_stockpile_selection(iid, good_id)
			_close_sheet()))
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

# A radio-style destination option card (dot filled when active).
func _dest_option(title: String, detail: String, active: bool, on_press: Callable) -> Control:
	var accent: Color = DS.PALETTE["ACCENT"]
	var card := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = DS.PALETTE["BG_HIGHLIGHT"] if active else DS.PALETTE["BG_CARD"]
	st.border_color = accent if active else DS.PALETTE["BORDER_SOFT"]
	st.set_border_width_all(1)
	st.set_corner_radius_all(10)
	st.set_content_margin_all(11)
	card.add_theme_stylebox_override("panel", st)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			on_press.call())
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", DS.SP["SM"])
	card.add_child(hb)
	var dot := _RadioDot.new()
	dot.on = active
	dot.col = accent
	dot.custom_minimum_size = Vector2(18, 18)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(dot)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 1)
	hb.add_child(col)
	var t := Label.new()
	t.theme_type_variation = "Body"
	t.text = title
	col.add_child(t)
	var d := Label.new()
	d.theme_type_variation = "Caption"
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.text = detail
	col.add_child(d)
	return card

# --- labour (headcount, not per turn — the wage is the per-turn figure) ---------------------

func _build_labour(lab: Dictionary) -> HBoxContainer:
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
	var s := Label.new()
	s.theme_type_variation = "Section"
	s.text = text
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(s)
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
	custom_minimum_size = Vector2(PANEL_WIDTH, h)
	size = Vector2(PANEL_WIDTH, h)

func _size_and_position() -> void:
	_resize_body()
	var vp := get_viewport().get_visible_rect().size
	var right_edge := vp.x - PANEL_EDGE_MARGIN
	var top_edge := TOP_BAR_CLEARANCE
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
