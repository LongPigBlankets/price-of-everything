extends PanelContainer
## Transport panel — the logistics dashboard behind the top bar's Transport module.
##
## Three columns, each answering one question:
##   Stockpiles       — which tiles are about to run out of room, and how soon
##   Infrastructure   — which links are over capacity, how often, and what it has cost
##   Units in transit — what is actually moving, and when it lands
##
## The dashboard reads existing simulation state; its footer applies bulk logistics choices.
## The sim already knew all of it: freight has always
## carried its route and its arrival turn, tiles have always had a fill level — it
## simply had nowhere to be seen. The only genuinely new state is HISTORY (Stockpile's
## fill ring, MatchState's per-link over-capacity ring), because a trend and an ETA
## cannot be recovered from a single frame's snapshot.
##
## See docs/top-bar-v3-spec.md §3.

const InfraIcons := preload("res://scripts/infra_icons.gd")
const BuildingNaming := preload("res://scripts/building_naming.gd")
# The DS2 parts the panel is built from.
const Ds2 := preload("res://scripts/transport_ds2/transport_ds2.gd")
const LedgerV3 := preload("res://scripts/ledger_v3/ledger_v3.gd")
const LampOverlay := preload("res://scripts/ds2/lamp_overlay.gd")
const Middleman := preload("res://scripts/middleman_service.gd")

const PANEL_WIDTH := 1220.0     # +40 over the original, 20 a side, for the infra cards
const PANEL_HEIGHT := 620.0
## The panel grows with its content, but only this far: a dashboard that resized itself
## freely would jump under the cursor every turn as freight came and went.
const PANEL_GROWTH := 60.0
## Rows the base height already shows comfortably, and what each extra one is worth.
const ROWS_BEFORE_GROWTH := 4
const ROW_GROWTH_PX := 20.0

## The filter keys over the infrastructure column, in build order. Cables carry power
## rather than freight, so they are listed for completeness and simply never have rows.
const INFRA_FILTERS: Array[Dictionary] = [
	{"mode": "roads", "label": "Roads"},
	{"mode": "rail", "label": "Rails"},
	{"mode": "pipes", "label": "Pipes"},
	{"mode": "reinf_pipes", "label": "Reinf."},
	{"mode": "cables", "label": "Cables"},
]

## A tile at or above this share of capacity counts as "full" — the same threshold the
## top bar counts with, so the module badge and this panel can never disagree.
const NEAR_FULL := 0.95
## Fill trend and the turns-until-full estimate look back this many turns (spec §3.2).
const TREND_TURNS := 3

var _global_logistics: VBoxContainer
var _settings_layer: Control
var _settings_card: PanelContainer
var _settings_button: Button
var _stock_list: VBoxContainer
var _infra_list: VBoxContainer
var _transit_list: VBoxContainer
var _dragging := false
var _drag_offset := Vector2.ZERO
var _refresh_queued := false
var _infra_enabled: Dictionary = {}      # mode -> bool, driven by the filter keys
## The routing objective's keys, by objective id.
var _routing_keys := {}


func _ready() -> void:
	name = "TransportPanel"
	theme = DS.theme
	theme_type_variation = "Card"
	visible = false
	custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	# The lamp over the whole panel (docs/ds2-theme.md §4).
	LampOverlay.attach(self)
	# Coalesced (the notification-bell pattern the other panels use): stockpile_changed
	# fires per transaction during PROCESS — hundreds of times in one burst — and each
	# would otherwise tear down and rebuild all three columns.
	Stockpile.stockpile_changed.connect(_refresh_if_visible)
	TransportState.transport_shipments_changed.connect(_refresh_if_visible)
	TurnManager.turn_resolution_completed.connect(_refresh_if_visible)
	BuildingState.building_added.connect(_refresh_if_visible)
	BuildingState.building_removed.connect(_refresh_if_visible)
	BuildingState.building_owner_changed.connect(_refresh_if_visible)


func open() -> void:
	if _settings_layer != null:
		_settings_layer.visible = false
	_refresh()
	visible = true
	_centre()
	_layout_settings_card()
	move_to_front()
	PanelStack.push(self)


func _centre() -> void:
	var vp := get_viewport_rect().size
	position = ((vp - size) * 0.5).floor()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
		if _settings_layer != null:
			_settings_layer.visible = false
		PanelStack.remove(self)


func _refresh_if_visible(_a: Variant = null) -> void:
	if not visible or _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_apply_refresh")


func _apply_refresh() -> void:
	_refresh_queued = false
	if visible:
		_refresh()


## The ledger's shell, then the three columns as plastic cases of raised modules.
func _build() -> void:
	LedgerV3.dress(self)
	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, LedgerV3.CONTENT_MARGIN)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var routing := Ds2.routing(MatchState.route_objective, func(id: int) -> void: MatchState.set_route_objective(id))
	_routing_keys = routing.keys
	_settings_button = Ds2.Parts.key_button("Logistics Settings", "LogisticsSettings", 0.8)
	_settings_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_settings_button.custom_minimum_size.x = 190.0
	_settings_button.pressed.connect(_toggle_settings)
	root.add_child(Ds2.title_row("Shipments and Stockpiles", [routing.box, _settings_button], func() -> void:
		if _settings_layer != null:
			_settings_layer.visible = false
		hide(), _on_drag))
	root.add_child(LedgerV3.seam())

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", Ds2.COLUMN_GAP)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(columns)
	var stock := Ds2.column("Stockpiles", "Fullest first")
	columns.add_child(stock.wrap)
	_stock_list = stock.list
	var filters: Array = INFRA_FILTERS.map(func(f: Dictionary) -> Array: return [str(f.label), str(f.mode)])
	for f: Dictionary in INFRA_FILTERS:
		_infra_enabled[str(f.mode)] = str(f.mode) == str(INFRA_FILTERS[0].mode)
	var filter_bed := Ds2.key_bed("InfraFilters", filters, str(INFRA_FILTERS[0].mode), func(mode: String) -> void:
		for k in _infra_enabled:
			_infra_enabled[k] = k == mode
		_build_infra())
	var infra := Ds2.column("Infrastructure", "Most congested first", filter_bed.bed)
	columns.add_child(infra.wrap)
	_infra_list = infra.list
	var transit := Ds2.column("In transit", "Largest first")
	columns.add_child(transit.wrap)
	_transit_list = transit.list

	_global_logistics = VBoxContainer.new()
	_global_logistics.add_theme_constant_override("separation", 12)
	var sheet := Ds2.settings_sheet(func() -> void: _settings_layer.visible = false)
	_settings_layer = sheet.layer
	_settings_card = sheet.card
	(sheet.body as VBoxContainer).add_child(_global_logistics)
	add_child(_settings_layer)
	_settings_layer.resized.connect(_layout_settings_card)
	call_deferred("_layout_settings_card")


## A tile's name pressed. The panel closes and the map goes to the tile.
func _go_to(tile_id: String) -> void:
	if _settings_layer != null:
		_settings_layer.visible = false
	hide()
	MatchState.focus_tile_requested.emit(tile_id)


## The title row drags the panel.
func _on_drag(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		_drag_offset = global_position - get_global_mouse_position()
	elif event is InputEventMouseMotion and _dragging:
		global_position = get_global_mouse_position() + _drag_offset


## The shipments as the In transit column lists them, largest first. A lone shipment keeps its own row
## ("Arrives in 2 turns."). Several carrying the same goods to the same place are one flow, read as what
## lands a turn: its units spread over the turns it arrives on. Each: {manifest, where, when}.
static func transit_flows(rows: Array) -> Array:
	var groups := {}
	var order: Array = []
	for row: Dictionary in rows:
		var goods: Array = (row.manifest as Array).map(func(e: Dictionary) -> String: return str(e.good_id))
		goods.sort()
		var key := "%s|%s|%s" % ["market" if bool(row.to_market) else str(row.destination), "+".join(goods), ""]
		if not groups.has(key):
			groups[key] = []
			order.append(key)
		(groups[key] as Array).append(row)
	var out: Array = []
	for key: String in order:
		var members: Array = groups[key]
		var first: Dictionary = members[0]
		var where := "To market" if bool(first.to_market) else "To %s" % place(str(first.destination))
		if members.size() == 1:
			var turns := int(first.turns)
			out.append({"manifest": first.manifest, "where": where, "units": int(first.units), "tile_id": "" if bool(first.to_market) else str(first.destination),
				"when": "Arrives now." if turns <= 0 else "Arrives in %d turn%s." % [turns, "" if turns == 1 else "s"]})
			continue
		var arrival_turns := {}
		var by_good := {}
		var units := 0
		for m: Dictionary in members:
			arrival_turns[int(m.turns)] = true
			units += int(m.units)
			for e: Dictionary in m.manifest:
				by_good[str(e.good_id)] = int(by_good.get(str(e.good_id), 0)) + int(e.qty)
		var spread := maxi(1, arrival_turns.size())
		var manifest: Array = []
		for gid in by_good:
			manifest.append({"good_id": gid, "qty": int(round(float(by_good[gid]) / float(spread)))})
		var each := int(round(float(units) / float(spread)))
		out.append({"manifest": manifest, "where": where, "units": units, "tile_id": "" if bool(first.to_market) else str(first.destination),
			"when": "%s unit%s arrive each turn." % [_thousands(each), "" if each == 1 else "s"]})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.units) > int(b.units))
	return out


static func _thousands(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return out


## A tile as the panel's copy names it: its name, without its coordinates.
static func place(tile_id: String) -> String:
	var nick := Catalog.tile_name(tile_id)
	return nick if nick != "" else Catalog.tile_label(tile_id)


## A fill or a load as a lamp's tone.
static func tone_of(color: Color) -> String:
	if color == DS.PALETTE.DANGER:
		return "bad"
	if color == DS.PALETTE.WARN:
		return "warn"
	return "ok"


## The worse of two tones.
static func worse(a: String, b: String) -> String:
	var rank := {"ok": 0, "warn": 1, "bad": 2}
	return a if int(rank.get(a, 0)) >= int(rank.get(b, 0)) else b


# ── Chrome ────────────────────────────────────────────────────────────────────

func _layout_settings_card() -> void:
	if _settings_layer == null or _settings_card == null:
		return
	var available := _settings_layer.size
	# As tall as its keys: three to a side under the title.
	var target := Vector2(minf(720.0, maxf(0.0, available.x - 52.0)), _settings_card.get_combined_minimum_size().y)
	_settings_card.size = target
	_settings_card.position = ((available - target) * 0.5).floor()


func _toggle_settings() -> void:
	if _settings_layer == null:
		return
	_settings_layer.visible = not _settings_layer.visible
	if _settings_layer.visible:
		_refresh()
		_layout_settings_card()
		_settings_layer.move_to_front()


func _empty_note(list: VBoxContainer, text: String) -> void:
	list.add_child(Ds2.note(text))


func _clear(container: Node) -> void:
	# remove THEN free: queue_free is deferred, so the old rows would otherwise still be
	# laid out beside the new ones for one frame (the flicker _clear_now fixes in the bar).
	for c in container.get_children():
		container.remove_child(c)
		c.queue_free()


func _refresh() -> void:
	for id in _routing_keys:
		(_routing_keys[id] as Control).set("latched", int(id) == MatchState.route_objective)
	_build_stockpiles()
	_build_infra()
	_build_transit()
	_build_global_logistics()
	_fit_height()


## Grow the panel, up to PANEL_GROWTH, once the longest column has more rows than the base
## height shows — and re-centre so the growth is shared top and bottom rather than pushing
## the panel down the screen.
func _fit_height() -> void:
	var rows: int = maxi(maxi(_stock_list.get_child_count(), _infra_list.get_child_count()),
			_transit_list.get_child_count())
	var over: int = maxi(0, rows - ROWS_BEFORE_GROWTH)
	var target: float = PANEL_HEIGHT + minf(PANEL_GROWTH, float(over) * ROW_GROWTH_PX)
	if is_equal_approx(target, size.y):
		return
	custom_minimum_size = Vector2(PANEL_WIDTH, target)
	size = Vector2(PANEL_WIDTH, target)
	if visible:
		_centre()


# ── Column 1 · Stockpiles ─────────────────────────────────────────────────────

func _build_stockpiles() -> void:
	_clear(_stock_list)
	_build_logistics_overview(_stock_list)
	var rows: Array = []
	for tile_key in Stockpile.tiles_with_stock():
		var tile_id := str(tile_key)
		if not tile_id.begins_with("tile_"):
			continue   # the legacy global bucket is not a place on the map
		var cap := float(Stockpile.get_capacity(tile_id))
		if cap <= 0.0:
			continue
		var used := float(Stockpile.get_used_capacity(tile_id))
		rows.append({"tile_id": tile_id, "used": used, "cap": cap, "fill": used / cap})
	rows.sort_custom(func(a, b): return float(a.fill) > float(b.fill))
	if rows.is_empty():
		_empty_note(_stock_list, "No tile is holding goods yet.")
		return
	for row: Dictionary in rows:
		_stock_list.add_child(_stockpile_row(row))


func _stockpile_row(row: Dictionary) -> Control:
	var tile_id := str(row.tile_id)
	var fill := float(row.fill)
	var cap := float(row.cap)
	var eta := _full_eta_text(tile_id, fill)
	var rate := Stockpile.fill_trend_per_turn(tile_id, TREND_TURNS)
	var dead := maxf(1.0, cap * 0.01)
	return Ds2.stock_row({
		"tile_id": tile_id, "name": place(tile_id), "on_go": _go_to.bind(tile_id), "level": Stockpile.get_warehouse_level(tile_id),
		"used": float(row.used), "cap": cap, "near": NEAR_FULL,
		"tone": worse(tone_of(_fill_color(fill)), tone_of(_eta_color(tile_id, fill)) if eta != "not filling" else "ok"),
		"words": "%d%% full, %s of %s." % [int(round(fill * 100.0)), _money(float(row.used)), _money(cap)],
		# Filling, draining or steady: a couple of units a turn is no trend.
		"trend": "up" if rate > dead else ("down" if rate < -dead else "steady"),
		"goods": Stockpile.get_top_goods(tile_id, 3),
	}, func() -> void: MatchState.tile_stockpile_requested.emit(tile_id))


func _fill_color(fill: float) -> Color:
	if fill >= NEAR_FULL:
		return DS.PALETTE.DANGER
	if fill >= 0.75:
		return DS.PALETTE.WARN
	return DS.PALETTE.OK


func _full_eta_text(tile_id: String, fill: float) -> String:
	if fill >= 1.0:
		return "FULL"
	var turns := Stockpile.turns_until_full(tile_id, TREND_TURNS)
	if turns < 0:
		return "not filling"
	if turns == 0:
		return "full now"
	return "full in %d turn%s" % [turns, "" if turns == 1 else "s"]


func _eta_color(tile_id: String, fill: float) -> Color:
	if fill >= 1.0:
		return DS.PALETTE.DANGER
	var turns := Stockpile.turns_until_full(tile_id, TREND_TURNS)
	if turns < 0:
		return DS.PALETTE.TEXT
	return DS.PALETTE.DANGER if turns <= 3 else DS.PALETTE.WARN


# ── Column 2 · Infrastructure ─────────────────────────────────────────────────

func _build_infra() -> void:
	_clear(_infra_list)
	var links: Array = []
	var hidden := 0
	var present_modes := {}
	for link_v in TransportState.active_links():
		var link: Dictionary = link_v
		present_modes[str(link.mode)] = true
		if bool(_infra_enabled.get(str(link.mode), true)):
			links.append(link)
		else:
			hidden += 1
	# Enabled filters with nothing "above 0%" this turn — named explicitly
	# rather than the column just quietly having no rows for that mode,
	# which otherwise reads identically to a broken filter. Cables especially: it
	# carries power, not freight, so it's ALWAYS in this list when enabled —
	# INFRA_FILTERS' own comment already flags that as by design, not a bug.
	var empty_enabled: Array[String] = []
	for row: Dictionary in INFRA_FILTERS:
		var mode := str(row.mode)
		if bool(_infra_enabled.get(mode, true)) and not present_modes.has(mode):
			empty_enabled.append(str(row.label))
	if links.is_empty():
		if hidden > 0:
			_empty_note(_infra_list, "%d link%s hidden by the filters above." % [hidden, "" if hidden == 1 else "s"])
		elif not empty_enabled.is_empty():
			_empty_note(_infra_list, "No %s above 0%%." % ", ".join(empty_enabled))
		else:
			_empty_note(_infra_list, "Nothing is crossing a road, rail or pipe this turn.")
		return
	for link: Dictionary in links:
		_infra_list.add_child(_infra_row(link))
	if not empty_enabled.is_empty():
		_empty_note(_infra_list, "No %s above 0%%." % ", ".join(empty_enabled))


func _infra_row(link: Dictionary) -> Control:
	var mode := str(link.mode)
	var ratio := float(link.ratio)
	# What congestion has cost, shown only once it has cost money: a £0 line on every clear link would bury
	# the ones that are really billing.
	var paid_so_far := TransportState.link_congestion_paid(str(link.key))
	return Ds2.infra_row({
		"key": str(link.key), "building_id": str(Catalog.get_building_by_internal_name(InfraIcons.normalise(mode)).get("id", "")),
		"mode_name": _mode_label(mode), "place": place(str(link.tile_id)), "on_go": _go_to.bind(str(link.tile_id)), "level": int(link.level),
		"flow": float(link.flow), "cap": float(link.cap), "near": 0.85, "tone": tone_of(_load_color(ratio)),
		"words": "%d%%, %s of %s units." % [int(round(ratio * 100.0)), _money(float(link.flow)), _money(float(link.cap))],
		"cost_words": ("Congestion has added £%s so far." % _money(paid_so_far)) if paid_so_far > 0.0 else "",
	}, func() -> void: _open_infra_building(str(link.tile_id), mode))


## Open the Building Detail panel for the infrastructure this row is about, so the player
## can inspect or upgrade it without hunting for the tile on the map.
##
## A link is a (tile, mode) pair, not a building reference — congestion is computed from
## flow over terrain — so the instance has to be found: the player-owned building on that
## tile whose type is this mode. focus_building_requested is the route the ledger and the
## starvation notifications already use, and it pans the map as well as opening the panel.
func _open_infra_building(tile_id: String, mode: String) -> void:
	var wanted := InfraIcons.normalise(mode)
	# OWNERSHIP IS NOT A FILTER HERE. A road the player uses is very often one they did
	# not build — the map ships with infrastructure, and rivals build their own — and the
	# row is about the LINK the player's freight is crossing, whoever owns it. Filtering
	# to player-owned buildings sent exactly those rows to the tile view instead.
	for b in BuildingState.buildings.values():
		if not (b is Dictionary):
			continue
		var building: Dictionary = b
		if str(building.get("tile_id", "")) != tile_id:
			continue
		var type_name := str(Catalog.get_building(str(building.get("building_id", ""))).get("internal_name", ""))
		if InfraIcons.normalise(type_name) != wanted:
			continue
		MatchState.focus_building_requested.emit(str(building.get("instance_id", "")))
		hide()   # the detail panel takes the screen; this one would sit behind it
		return
	# Nothing built there: the link is terrain infrastructure the tile came with, so the
	# tile itself is the only thing there is to show.
	MatchState.focus_tile_requested.emit(tile_id)
	hide()


func _load_color(ratio: float) -> Color:
	if ratio > 1.0:
		return DS.PALETTE.DANGER
	if ratio >= 0.85:
		return DS.PALETTE.WARN
	return DS.PALETTE.OK


func _mode_label(mode: String) -> String:
	match mode:
		"roads": return "Road"
		"rail": return "Rail"
		"pipes": return "Pipework"
		"reinf_pipes": return "Reinforced pipework"
	return mode.capitalize()


# ── Column 3 · Units in transit ───────────────────────────────────────────────

func _build_transit() -> void:
	_clear(_transit_list)
	var rows: Array = []
	for s in TransportState.pending_transport_shipments:
		var ship: Dictionary = s
		var manifest := _manifest(ship)
		var units := 0
		for entry: Dictionary in manifest:
			units += int(entry.qty)
		if units <= 0:
			continue
		rows.append({
			"manifest": manifest,
			"units": units,
			"turns": int(ship.get("turns_remaining", 0)),
			"to_market": bool(ship.get("is_sale", false)),
			"destination": str(ship.get("destination_tile", "")),
		})
	rows.sort_custom(func(a, b): return int(a.units) > int(b.units))
	if rows.is_empty():
		_empty_note(_transit_list, "Nothing is on the move.")
		return
	var flows := transit_flows(rows)
	for i in flows.size():
		var flow: Dictionary = flows[i]
		if str(flow.get("tile_id", "")) != "":
			flow["place"] = place(str(flow.tile_id))
			flow["on_go"] = _go_to.bind(str(flow.tile_id))
		_transit_list.add_child(Ds2.transit_row(flow, i))


## What a shipment is carrying, as [{good_id, qty}]. Sales carry an itemised
## sale_record; moves and purchases carry a single good.
func _manifest(ship: Dictionary) -> Array:
	var out: Array = []
	if bool(ship.get("is_sale", false)):
		for it in (ship.get("sale_record", {}) as Dictionary).get("items", []):
			var item: Dictionary = it
			if int(item.get("qty", 0)) > 0:
				out.append({"good_id": str(item.get("good_id", "")), "qty": int(item.get("qty", 0))})
		return out
	var gid := str(ship.get("good_id", ""))
	var qty := int(ship.get("qty", 0))
	if gid != "" and qty > 0:
		out.append({"good_id": gid, "qty": qty})
	return out


# ── Formatting ────────────────────────────────────────────────────────────────

func _money(amount: float) -> String:
	var v := int(round(amount))
	var s := str(absi(v))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("−" if v < 0 else "") + out


# ── Logistics ─────────────────────────────────────────────────────────────────

func _build_logistics_overview(list: VBoxContainer) -> void:
	if not preload("res://scripts/middleman_service.gd").active(): return
	var service = preload("res://scripts/middleman_service.gd")
	list.add_child(Ds2.list_heading("Building logistics"))
	for b: Dictionary in BuildingState.buildings.values():
		if not service.eligible(b): continue
		var iid := str(b.instance_id)
		list.add_child(Ds2.logistics_row(iid, BuildingNaming.of(b), "Inputs: %s. Outputs: %s." % [
			"Intermediary" if service.uses_inputs(iid) else "Managed", "Intermediary" if service.uses_outputs(iid) else "Managed"],
			func() -> void:
				hide()
				MatchState.focus_building_requested.emit(iid)))

func _build_global_logistics() -> void:
	_clear(_global_logistics)
	_global_logistics.visible = preload("res://scripts/middleman_service.gd").active()
	# The company-wide settings only exist in Logistics Intermediary games.
	if _settings_button != null:
		_settings_button.visible = _global_logistics.visible
	if not _global_logistics.visible:
		if _settings_layer != null:
			_settings_layer.visible = false
		return
	_global_logistics.add_child(Ds2.Parts.caption("For every building in the company"))
	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", 18)
	_global_logistics.add_child(sides)
	for side: String in ["input", "output"]:
		sides.add_child(_settings_side(side))


## One side's three keys, locked ones saying what they need.
func _settings_side(side: String) -> Control:
	var state: Dictionary = Middleman.global_side(side)
	var inputs := side == "input"
	var none: bool = (state.ids as Array).is_empty()
	var choices: Array = []
	for spec: Array in [
			["middleman", "Logistics Intermediary", "The Logistics Intermediary handles every building's %s." % ("inputs" if inputs else "outputs"), ""],
			["market", "Global market", "Buy all inputs at the global market through a port." if inputs else "Sell all outputs at the global market through a port.", Middleman.route_lock("market")],
			["stockpile", "Tile stockpile", "Draw all inputs from each building's tile stockpile." if inputs else "Keep all outputs in each building's tile stockpile.", Middleman.route_lock("stockpile")]]:
		var lock := str(spec[3])
		choices.append({"id": str(spec[0]), "label": str(spec[1]), "tip": lock if lock != "" else str(spec[2]),
			"enabled": not none and lock == "", "active": _global_logistics_choice_active(str(spec[0]), side, state.ids)})
	return Ds2.settings_side("Inputs" if inputs else "Outputs", choices, func(destination: String) -> void: _request_global_logistics(side, destination))


func _global_logistics_choice_active(destination: String, side: String, ids: Array) -> bool:
	if ids.is_empty(): return false
	var service = preload("res://scripts/middleman_service.gd")
	if destination == "middleman":
		return ids.all(func(iid: String) -> bool: return service.side_all_middleman(iid, side))
	for iid: String in ids:
		for item: Dictionary in service._side_items(iid, side):
			var gid := str(item.get("good_id", ""))
			if not service.material_tradeable(gid, side): continue
			if side == "input":
				var route := service.input_source_route(iid, gid)
				if destination == "market" and str(route.get("primary", "")) != "market": return false
				if destination == "stockpile" and (str(route.get("primary", "")) != "stockpile" or str(route.get("fallback", "")) != "middleman"): return false
			else:
				var output_tile := MatchState.get_output_stockpile_destination(iid, gid)
				if destination == "market" and not MatchState.is_output_market(iid, gid): return false
				if destination == "stockpile" and output_tile != str(BuildingState.get_building(iid).get("tile_id", "")): return false
	return true


func _request_global_logistics(side: String, destination: String) -> void:
	var action := func() -> bool: return _apply_global_logistics(side, destination)
	var mode := "middleman" if destination == "middleman" else "managed"
	preload("res://scripts/logistics_confirmation.gd").request(self, mode, action, _refresh, {"side": side, "destination": destination})


func _apply_global_logistics(side: String, destination: String) -> bool:
	var service = preload("res://scripts/middleman_service.gd")
	var state: Dictionary = service.global_side(side)
	var ids: Array = state.ids as Array
	if ids.is_empty(): return false
	var broad_mode := "middleman" if destination == "middleman" else "managed"
	var result: Dictionary = service.set_modes(ids, side, broad_mode)
	if not bool(result.get("ok", false)):
		MatchState.request_toast(str(result.get("reason", "Unable to change company logistics.")), "warning")
		return false
	if destination == "middleman":
		_refresh()
		return true
	for iid: String in ids:
		for item: Dictionary in service._side_items(iid, side):
			var gid := str(item.get("good_id", ""))
			if not service.material_tradeable(gid, side): continue
			if side == "input":
				var source := "market" if destination == "market" else "stockpile"
				var primary := service.set_input_route(iid, gid, "primary", source)
				if not bool(primary.get("ok", false)):
					MatchState.request_toast(str(primary.get("reason", "Unable to set company input source.")), "warning")
					return false
				var fallback := service.set_input_route(iid, gid, "fallback", "middleman")
				if not bool(fallback.get("ok", false)):
					MatchState.request_toast(str(fallback.get("reason", "Unable to set company input fallback.")), "warning")
					return false
			else:
				if destination == "market":
					MatchState.route_output_to_market(iid, gid)
				else:
					MatchState.set_output_stockpile_destination(iid, str(BuildingState.get_building(iid).get("tile_id", "")), gid)
	_refresh()
	return true
