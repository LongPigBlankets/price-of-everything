extends RefCounted
## Tile view v3: the Buildings tab's body (docs/tile-view-ds2-plan.md §4.3 and §9), built into `pane` on each
## refresh while UiPrefs.use_tvp_v3 is on. With the switch off the v2 panel builds the tab itself.
## `panel` is the tile view (scripts/tile_info_panel_v2.gd): its tile, its signals and its helpers.
##
## The site's equipment racked in dark cases, as Building Detail racks its diagnostics:
## - Build and Buy buildings first, two cream keys each beside its raised icon, on a steel plate.
## - The tile's port next, on a tile that has one, in a case of its own under the raised heading the
##   status line names it by (Seaport), never among the other companies' buildings: another company's
##   port with its owner, its price and a Buy key; your port as your
##   buildings read, its lamp and words.
## - Your buildings in Building Detail's black plastic case, under its raised heading. Each is a raised
##   module: its emblem, its name, a lamp and the words that explain it (buildings_readings.gd: one roll-up
##   of Building Detail's diagnostics, with the stall that makes a 0 named in it), what it makes this turn
##   as a good in its well with the quantity pill (unlit over a 0 while the engine says it is stalled), and
##   what a unit costs to make on an LED screen against its market price. Buildings of the same kind and
##   recipe are a group, its head named as its members are without their letter ("Industrial Goods
##   Factory - Motor"): the group's worst lamp, what the members that run make, and its dearest unit. A
##   group starts folded to its head; opened, its members hang off one cable with a tap into each, as
##   diagnostics rows read: lamp and name, under it in full what a member says beyond the head's words, and
##   its output as its good in a smaller well with its pill. Under construction follows under a metal
##   label, each project's turns on a drum.
## - Every figure in the case stands in one of two columns: the figure column (wells, the projects' turns)
##   and the cost column (the LED screens, a member's own cost, Cancel), one width down the case, so each
##   reads down one line as Building Detail's screens do. Each action sits beside the figure it changes.
##   The seven-segment screens show money only.
## - Hovering a module, a key or a figure shows Building Detail's readout at the pointer
##   (buildings_tip.gd): what the worst check found, in the engine's full sentence.
## - Other companies' buildings in a second case, folded behind one wide key that counts them ("4 other
##   companies' buildings") and opens it: each company's buildings under a metal label with its name,
##   grouped and folded as yours are.
## - Woods and ruins last, in their own case under a raised heading, as features of the land rather than
##   anyone's company.
## Infrastructure (roads, cables, pipes, rail) is the Transport tab's: it is neither shown nor counted here.
## The parts stand CASE_GAP apart in a column kept clear of the scroll rail (buildings_parts.gd Column), so
## no case's edge, screws or shadow lies over another's or the rail.
##
## Open groups, the open drawer and the readings are kept on the panel (meta), so a refresh keeps them.

const Parts := preload("res://scripts/tvp_v3/buildings_parts.gd")
const Readings := preload("res://scripts/tvp_v3/buildings_readings.gd")
const Recheck := preload("res://scripts/tvp_v3/buildings_recheck.gd")
const Drum := preload("res://scripts/ds2/drum_figure.gd")
const Tip := preload("res://scripts/tvp_v3/buildings_tip.gd")
const Section := preload("res://scripts/bdp_v3_section.gd")
const Cable := preload("res://scripts/bdp_v3_cable.gd")
const ModKey := preload("res://scripts/bdp_v3_mod_key.gd")
const Heading := preload("res://scripts/bdp_v3_heading.gd")
const Led := preload("res://scripts/bdp_v3_led.gd")
const Plate := preload("res://scripts/bdp_v3_plate.gd")
const MoneyFigure := preload("res://scripts/ds2/money_figure.gd")
const BuildingReadout := preload("res://scripts/building_readout.gd")
const BuildingNaming := preload("res://scripts/building_naming.gd")

const PORT_ID := "b_004"
const RUINS_ID := "b_031"

## A group's cable runs under the centre of its head's emblem; its members start a tap's length right of it.
const FEED_X := Parts.PAD.x + Parts.EMBLEM_PX * 0.5
const FEED_INDENT := FEED_X + Cable.TAP_LENGTH
## The action keys' raised icons (render set `baricon` and the diagnostics' `works`, as Building Detail's).
const ACTION_ICON_PX := 34.0
## Cancel's key, at least this wide (it takes the cost column's width).
const CANCEL_W := 96.0
## The body's width before the pane has been laid out: the sheet's, less its scrollbar.
const BODY_W := 571.0
const TURNS_LEFT := "Turns left"
const TURNS_TO_BUILD := "Turns to build"
const CANCEL_TIP := "Refunds the construction fee. Before End Turn, also refunds reserved materials and freight. Land remains owned."

const META_GROUPS := "tvp_bl_open_groups"
const META_OTHERS := "tvp_bl_others_open"


static func build(panel: Control, pane: VBoxContainer) -> void:
	var tile_id := str(panel.get("_current_tile_id"))
	var column: Parts.Column = Parts.Column.new(Parts.CASE_GAP)
	pane.add_child(column)
	var body := column.rows
	var site := _site(tile_id)
	column.reserve = not (site.others as Array).is_empty()
	var grid := _grid(panel, pane, site)
	body.add_child(_actions(panel, tile_id))
	_add_port(panel, body, site, grid)
	_add_yours(panel, body, site, grid)
	_add_others(panel, body, site, grid)
	_add_features(panel, body, site)
	if not (grid.recheck as Array).is_empty():
		pane.add_child(Recheck.new(panel, grid.recheck))


# --- what is on the tile -------------------------------------------------------------------

## The tile's buildings sorted by whose they are: yours, other companies', the land's own woods and ruins,
## the port, and your buildings under construction. Infrastructure is the Transport tab's, built or going
## up: it is left out of every list here.
static func _site(tile_id: String) -> Dictionary:
	var mine: Array = []
	var others: Array = []
	var features: Array = []
	var port: Dictionary = {}
	for b: Dictionary in BuildingState.get_buildings_on_tile(tile_id):
		var bid := str(b.get("building_id", ""))
		if bid == PORT_ID:
			port = b
			continue
		if _is_infrastructure(bid):
			continue
		if BuildingState.is_player_owned(b):
			mine.append(b)
		elif bid == RUINS_ID or BuildingState.is_land_owned_wood(b):
			features.append(b)
		else:
			others.append(b)
	var projects: Array = []
	for p: Dictionary in Construction.projects_on_tile(tile_id):
		if not _is_infrastructure(str(p.get("building_id", ""))):
			projects.append(p)
	var port_mine := not port.is_empty() and BuildingState.is_player_owned(port)
	return {"tile_id": tile_id, "mine": mine, "others": others, "features": features, "port": port,
		"port_mine": port_mine, "projects": projects}


static func _is_infrastructure(building_id: String) -> bool:
	return str(Catalog.get_building(building_id).get("category", "")).to_lower() == "infrastructure"


## Buildings of one kind and recipe (and, for other companies, one owner) together, in the order first seen.
static func _groups(buildings: Array, by_owner: bool) -> Array:
	var groups := {}
	var order: Array = []
	for b: Dictionary in buildings:
		var key := "%s|%s" % [str(b.get("building_id", "")), str(b.get("recipe_id", ""))]
		if by_owner:
			key = str(b.get("owner", "")) + "|" + key
		if not groups.has(key):
			groups[key] = []
			order.append(key)
		(groups[key] as Array).append(b)
	var out: Array = []
	for key: String in order:
		out.append({"key": key, "members": groups[key]})
	return out


## The readings of your buildings and the cases' column grid:
## - inner: a module's inside width (with the column's gutter off it, as when the scroll rail shows);
## - fig_w: the figure column, wide enough for the widest set of wells (a member's smaller well fits in
##   it), the widest turns drum and the turns' label (which may stand out past it into the gaps beside it,
##   no further);
## - cost_w: the cost column, the widest money screen or market line, or Cancel;
## - digits: one digit count for every cost screen, so the screens are one width.
static func _grid(panel: Control, pane: Control, site: Dictionary) -> Dictionary:
	var yours: Array = (site.mine as Array).duplicate()
	if bool(site.port_mine):
		yours.push_front(site.port)
	var got := Readings.readings_for(panel, yours)
	var readings: Dictionary = got.readings
	var digits := 0
	var market_w := 0.0
	var outs := 1
	for r: Dictionary in readings.values():
		var c: Dictionary = r.cost
		if not c.is_empty():
			digits = maxi(digits, Led.cells_for("%.2f" % float(c.unit_cost)).size())
			market_w = maxf(market_w, Parts.body_width(Parts.market_text(c)))
		outs = maxi(outs, mini(3, (r.outputs as Array).size()))
	var cost_w := 0.0
	if digits > 0:
		cost_w = ceilf(maxf(Parts.money_width(digits), market_w))
	var fig_w := float(outs * Parts.WELL_PX + (outs - 1) * 8)
	var turn_drums := 1
	var projects: Array = site.projects
	if not projects.is_empty():
		for p: Dictionary in projects:
			turn_drums = maxi(turn_drums, str(maxi(0, int(p.get("turns_remaining", 0)))).length())
		fig_w = maxf(fig_w, Drum.width_for(turn_drums, Drum.led_height()))
		for label in [TURNS_LEFT, TURNS_TO_BUILD]:
			fig_w = maxf(fig_w, Parts.caption_width(label) + 2.0 - 2.0 * (Parts.GAP - 2))
		cost_w = maxf(cost_w, CANCEL_W)
	var body_w := pane.size.x if pane.size.x > 200.0 else BODY_W
	return {"readings": readings, "recheck": got.recheck, "digits": digits, "cost_w": cost_w, "fig_w": ceilf(fig_w),
		"turn_drums": turn_drums, "inner": body_w - Parts.GUTTER - 2.0 * Parts.case_margin() - 2.0 * Parts.PAD.x}


## The width right of a module's words: the figure column and the cost column, each after a gap.
static func _figures_width(grid: Dictionary) -> float:
	var w: float = float(grid.fig_w) + Parts.GAP
	if float(grid.cost_w) > 0.0:
		w += float(grid.cost_w) + Parts.GAP
	return w


## How wide the words beside a lamp may be in a module with its emblem.
static func _words_width(grid: Dictionary) -> float:
	return float(grid.inner) - (Parts.EMBLEM_PX + Parts.GAP) - _figures_width(grid) - Parts.lamp_room()


# --- actions -------------------------------------------------------------------------------

## Build (Construct, locked to the tile) and Buy buildings (the market's buildings for sale on the tile),
## each a cream key beside its raised icon.
static func _actions(panel: Control, tile_id: String) -> MarginContainer:
	var plate: MarginContainer = Section.new()
	plate.name = "BLActions"
	var row := HBoxContainer.new()
	(plate.get("content") as VBoxContainer).add_child(row)
	row.add_theme_constant_override("separation", 10)
	row.add_child(Parts.raised("diag_icon_works", ACTION_ICON_PX))
	var build := Parts.key_button("Build", "BLBuildButton", 1.0)
	Tip.attach(build, {"name": "Build", "detail": "Choose a building to put up on this tile."})
	build.pressed.connect(func() -> void: panel.call("_on_bl_build_pressed"))
	row.add_child(build)
	row.add_child(Parts.spacer(6, 0))
	row.add_child(Parts.raised("bar_icon_coin", ACTION_ICON_PX))
	var buy := Parts.key_button("Buy buildings", "BLBuyBuildingsButton", 1.0)
	Tip.attach(buy, {"name": "Buy buildings", "detail": "Buildings for sale on this tile."})
	buy.pressed.connect(func() -> void: MatchState.buildings_market_for_tile_requested.emit(tile_id))
	row.add_child(buy)
	return plate


# --- the port ------------------------------------------------------------------------------

## The tile's port in a case of its own under the actions, headed as the status line names it (Seaport),
## so it reads as the tile's port and never as one of the other companies' buildings. Another company's:
## its owner, its price and its Buy key (_port_module). Yours: as your buildings read, its lamp and its
## words. Either way the module is PortBuildingCard, on screen as soon as the tab is, and a click opens the
## port in Building Detail.
static func _add_port(panel: Control, pane: VBoxContainer, site: Dictionary, grid: Dictionary) -> void:
	var port: Dictionary = site.port
	if port.is_empty():
		return
	var case := Parts.plastic_case("TilePort")
	pane.add_child(case)
	var rows := case.get_child(0) as VBoxContainer
	rows.add_child(Parts.heading("Seaport"))
	if not bool(site.port_mine):
		rows.add_child(_port_module(panel, port))
		return
	var reading: Dictionary = (grid.readings as Dictionary).get(str(port.get("instance_id", "")), {})
	if reading.is_empty():
		reading = Readings.reading(port)
	var mine := _mine_module(panel, port, reading, grid, "Port")
	mine.name = "PortBuildingCard"
	rows.add_child(mine)


# --- your buildings ------------------------------------------------------------------------

static func _add_yours(panel: Control, pane: VBoxContainer, site: Dictionary, grid: Dictionary) -> void:
	var mine: Array = site.mine
	var projects: Array = site.projects
	var readings: Dictionary = grid.readings
	var case := Parts.plastic_case("YourBuildings")
	pane.add_child(case)
	var rows := case.get_child(0) as VBoxContainer
	rows.add_child(Parts.heading("Your buildings"))
	if mine.is_empty() and projects.is_empty():
		var none := Parts.body("You have no buildings on this tile.")
		none.name = "BLNoneOfYours"
		rows.add_child(none)
		return

	var modules: int = 0
	var open: Dictionary = panel.get_meta(META_GROUPS, {})
	for g: Dictionary in _groups(mine, false):
		var members: Array = g.members
		var first: Dictionary = members[0]
		var card_name := "BuildingCard_%s_%s" % [str(first.get("building_id", "")), str(first.get("recipe_id", ""))]
		modules += 1
		if members.size() == 1:
			var solo := _mine_module(panel, first, readings[str(first.get("instance_id", ""))], grid, _name_of(first))
			solo.name = card_name
			rows.add_child(solo)
			continue
		var member_readings: Array = []
		var names: Array = []
		for m: Dictionary in members:
			member_readings.append(readings[str(m.get("instance_id", ""))])
			names.append(_member_name(m))
		var gr := Readings.group_reading(member_readings, names)
		var head := _head_module(first, gr, grid, members.size())
		head.name = card_name
		var member_modules: Array[Control] = []
		for i in members.size():
			member_modules.append(_member_module(panel, members[i], member_readings[i], gr, grid, str(names[i]),
				(gr.extra as Array)[i]))
		var key := str(g.key)
		rows.add_child(_group_block(panel, key, head, member_modules, bool(open.get(key, false))))

	if not projects.is_empty():
		if modules > 0:
			rows.add_child(Parts.spacer(0, 4))
		rows.add_child(_sub_caption("Under construction", "UnderConstruction"))
		for p: Dictionary in projects:
			rows.add_child(_project_module(panel, p, grid))


## A metal label over part of a case: the buildings under construction, a company's buildings.
static func _sub_caption(text: String, label_name: String) -> Control:
	var label := Parts.caption(text)
	label.name = label_name
	label.custom_minimum_size.y = 22
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return label


## The building's name as the game gives it on this tile ("Motor Factory E", "Mine - Coal - A"). A project
## is named the same way, by its place among the tile's buildings and projects.
static func _name_of(b: Dictionary) -> String:
	return BuildingNaming.label_for_tile(str(b.get("tile_id", "")), str(b.get("instance_id", "")),
		str(b.get("building_id", "")), str(b.get("recipe_id", "")))


## A group's name: its members' name without the letter that tells them apart
## ("Motor Factory", "Mine - Coal"), so a group and a building alone read as the same kind of thing.
static func _group_name(first: Dictionary) -> String:
	return BuildingNaming.without_letter(_name_of(first))


## A group member's name without the kind of building its head already names ("Motor - E").
static func _member_name(b: Dictionary) -> String:
	var full := _name_of(b)
	var kind := str(Catalog.get_building(str(b.get("building_id", ""))).get("display_name", ""))
	if kind != "" and full.begins_with(kind + " - "):
		return full.substr(kind.length() + 3)
	return full


## A reading's check as a readout, named for `stage`.
static func _check_tip(check: Dictionary, stage: String) -> Dictionary:
	var tip := check.duplicate()
	tip["stage"] = stage
	return tip


## A cost screen's readout: what a unit costs to make and the market price (`among`: how many buildings the
## screen shows the dearest of).
static func _cost_tip(cost: Dictionary, among: int) -> Dictionary:
	if cost.is_empty():
		return {}
	var each := "£%.2f/unit to make" % float(cost.unit_cost)
	if among > 1:
		each = "£%.2f/unit at the dearest of the %d" % [float(cost.unit_cost), among]
	return {"name": "Cost to produce", "detail": "%s. Market price £%.2f." % [each, float(cost.get("market_price", 0.0))]}


## A module for one of your buildings standing alone: its emblem, its name, its lamp and words, this turn's
## output in a well (unlit over a 0 while it is stalled), and its unit cost against the market. A click
## opens it in Building Detail; its hover is its worst check.
static func _mine_module(panel: Control, b: Dictionary, r: Dictionary, grid: Dictionary, title: String) -> PanelContainer:
	var module := Parts.module("BuildingModule")
	var row := Parts.row_of(module)
	row.add_child(Parts.emblem(str(b.get("building_id", "")), Parts.EMBLEM_PX))
	var outs: Array = r.outputs
	row.add_child(Parts.info(title, str(r.tone), Readings.fit(r.causes, _words_width(grid))))
	row.add_child(Parts.wells(outs, true, bool(r.get("runs", true)), float(grid.fig_w)))
	if float(grid.cost_w) > 0.0:
		row.add_child(Parts.cost_column(r.cost, int(grid.digits), float(grid.cost_w), true, _cost_tip(r.cost, 1)))
	Tip.attach(module, _check_tip(r.check, title))
	var iid := str(b.get("instance_id", ""))
	Parts.on_click(module, func() -> void: panel.call("_open_building_or_construction", iid))
	return module


## A group member on its cable, as a diagnostics row reads: its lamp and its short name, with what it makes
## this turn in the figure column as the head shows it, the good in its well with the quantity pill, the
## well a member's smaller one (unlit over a 0 while it is stalled), and its unit cost in the cost column
## only where it differs from the head's (the head shows the group's dearest and the market). Under that
## line, across the module, what it says beyond the head's words (`extra`), in full. A member with nothing
## to add is one line. Its cable's tap feeds its first line (meta "tap").
static func _member_module(panel: Control, b: Dictionary, r: Dictionary, gr: Dictionary, grid: Dictionary,
		title: String, extra: Array) -> PanelContainer:
	var module := Parts.module("MemberModule", true)
	var row := Parts.row_of(module)
	var outs: Array = r.outputs
	row.add_child(Parts.line_info(title, str(r.tone), ""))
	var col := HBoxContainer.new()
	col.name = "Outputs"
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.custom_minimum_size = Vector2(float(grid.fig_w), 0)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not outs.is_empty():
		var o: Dictionary = outs[0]
		var gid := str(o.good_id)
		var lit := bool(r.get("runs", true))
		col.add_child(Parts.good_in_well(gid, int(o.qty), Parts.output_tip(gid, int(o.qty), lit), lit, Parts.MEMBER_WELL_PX))
	row.add_child(col)
	if float(grid.cost_w) > 0.0:
		var c: Dictionary = r.cost
		var head_cost: Dictionary = gr.cost
		var same := not c.is_empty() and not head_cost.is_empty() and "%.2f" % float(c.unit_cost) == "%.2f" % float(head_cost.unit_cost)
		row.add_child(Parts.cost_column({} if same else c, int(grid.digits), float(grid.cost_w), false,
			{} if same else _cost_tip(c, 1)))
	if not extra.is_empty():
		Parts.words_under(module, Readings.sentence(", ".join(extra)), Parts.lamp_room())
	module.set_meta("tap", row)
	Tip.attach(module, _check_tip(r.check, title))
	var iid := str(b.get("instance_id", ""))
	Parts.on_click(module, func() -> void: panel.call("_open_building_or_construction", iid))
	return module


## A group's head: the emblem, the group's name and the fold mark, the worst member's lamp and what most
## members say (or how many are at each tone), what the members that run make this turn, its dearest unit.
## Its hover is the worst member's check.
static func _head_module(first: Dictionary, gr: Dictionary, grid: Dictionary, count: int) -> PanelContainer:
	var module := Parts.module("GroupHead")
	var row := Parts.row_of(module)
	row.add_child(Parts.emblem(str(first.get("building_id", "")), Parts.EMBLEM_PX))
	var outs: Array = gr.outputs
	var words := Readings.fit(gr.causes, _words_width(grid), str(gr.lead))
	var info := Parts.info(_group_name(first), str(gr.tone), words, true, _words_width(grid) + Parts.lamp_room())
	row.add_child(info)
	row.add_child(Parts.wells(outs, true, bool(gr.runs), float(grid.fig_w)))
	if float(grid.cost_w) > 0.0:
		row.add_child(Parts.cost_column(gr.cost, int(grid.digits), float(grid.cost_w), true, _cost_tip(gr.cost, count)))
	Tip.attach(module, gr.check)
	module.set_meta("chevron", info.find_child("Chevron", true, false))
	return module


## A head and its members, who hang off one cable that leaves from under the head, a tap into each. A group
## starts folded to its head; a click on the head shows the members or folds them away, and the choice is
## kept on the panel.
static func _group_block(panel: Control, key: String, head: PanelContainer, members: Array[Control], open: bool) -> VBoxContainer:
	var block := VBoxContainer.new()
	block.name = "Group"
	block.add_theme_constant_override("separation", Parts.MODULE_GAP)
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(head)
	var feed := PanelContainer.new()
	feed.name = "Feed"
	feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bare := StyleBoxEmpty.new()
	bare.content_margin_left = FEED_INDENT
	feed.add_theme_stylebox_override("panel", bare)
	block.add_child(feed)
	var cable: Control = Cable.new()
	cable.centre_x = FEED_X - FEED_INDENT
	cable.inset = 0.0
	feed.add_child(cable)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feed.add_child(list)
	var taps: Array[Control] = []
	for m in members:
		list.add_child(m)
		taps.append(m.get_meta("tap", m) as Control)
	cable.taps = taps
	feed.visible = open
	var chevron: Control = head.get_meta("chevron")
	if chevron != null:
		chevron.set_meta("open", open)
	Parts.on_click(head, func() -> void:
		feed.visible = not feed.visible
		if chevron != null:
			chevron.set_meta("open", feed.visible)
			chevron.queue_redraw()
		var kept: Dictionary = panel.get_meta(META_GROUPS, {})
		kept[key] = feed.visible
		panel.set_meta(META_GROUPS, kept))
	return block


## A building under construction: its emblem unlit, its name, the amber lamp Building Detail badges a
## project with and its state; the turns on a drum counter in the figure column with its label under it,
## and Cancel in the cost column beside them. A click on the module opens the project in Building Detail;
## a press on Cancel is Cancel's alone.
static func _project_module(panel: Control, p: Dictionary, grid: Dictionary) -> PanelContainer:
	var iid := str(p.get("instance_id", ""))
	var module := Parts.module("ConstructionModule_%s" % iid)
	var row := Parts.row_of(module)
	var emblem := Parts.emblem(str(p.get("building_id", "")), Parts.EMBLEM_PX)
	emblem.modulate = Color(1, 1, 1, 0.45)
	row.add_child(emblem)
	var title := _name_of(p)
	var turns := maxi(0, int(p.get("turns_remaining", 0)))
	var awaiting := str(p.get("status", "")) == Construction.STATUS_AWAITING_MATERIALS
	var words := "Under construction"
	var of := int(p.get("construction_duration", 0))
	var detail := "Construction under way, %d of %d turns left." % [turns, of] if of >= turns and of > 0 \
		else "Construction under way, %d turn%s left." % [turns, "" if turns == 1 else "s"]
	if awaiting:
		var eta := Construction.materials_eta(p)
		words = "Awaiting materials" if eta < 0 else "Materials due in %d turn%s" % [eta, "" if eta == 1 else "s"]
		detail = "Construction begins once all materials arrive, then a %d turn build." % turns
		if eta >= 0:
			detail = "Materials due in %d turn%s. %s" % [eta, "" if eta == 1 else "s", detail]
	row.add_child(Parts.info(title, "warn", words))
	var turns_col := VBoxContainer.new()
	turns_col.name = "Turns"
	turns_col.add_theme_constant_override("separation", 0)
	turns_col.custom_minimum_size = Vector2(float(grid.fig_w), 0)
	turns_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	turns_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var drum := Parts.drum(turns, int(grid.turn_drums))
	drum.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	turns_col.add_child(drum)
	turns_col.add_child(Parts.caption_under(TURNS_TO_BUILD if awaiting else TURNS_LEFT, float(grid.fig_w)))
	row.add_child(turns_col)
	var cancel := Parts.key_button("Cancel", "CancelConstruction_%s" % iid, 0.8)
	cancel.custom_minimum_size.x = float(grid.cost_w)
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_END
	cancel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	(cancel.get_child(0) as Control).set("summary_ink", Plate.DANGER_INK)
	Tip.attach(cancel, {"name": "Cancel %s" % title, "detail": CANCEL_TIP})
	cancel.pressed.connect(func() -> void: Construction.cancel(iid))
	row.add_child(cancel)
	var check := {"stage": title, "name": "Awaiting materials" if awaiting else "Under construction",
		"detail": detail, "tone": "warn"}
	Tip.attach(module, check)
	Parts.on_click(module, func() -> void: panel.call("_open_building_or_construction", iid))
	return module


# --- other companies -----------------------------------------------------------------------

## Other companies' buildings in their own case, folded behind one wide key that counts them and nothing
## else (the port has its own case, infrastructure its own tab); the key opens the case: each company's
## buildings under its name, grouped and folded as yours are, their wells in your wells' column.
static func _add_others(panel: Control, pane: VBoxContainer, site: Dictionary, grid: Dictionary) -> void:
	var others: Array = site.others
	var n := others.size()
	if n == 0:
		return
	var summary := "%d other companies' buildings" % n if n > 1 else "1 other company's building"
	var open := bool(panel.get_meta(META_OTHERS, false))
	# The case is the drawer: shut, it is only its front, the key on a slim strip of the case; open, it
	# holds the companies' buildings under the key. Its top edge keeps to its corner screws, clear of the key.
	var drawer := Parts.plastic_case("OtherCompanies", true)
	drawer.add_theme_constant_override("margin_top", Parts.DRAWER_MARGIN)
	var shut_bottom := func(is_open: bool) -> void:
		drawer.add_theme_constant_override("margin_bottom", roundi(Parts.case_margin()) if is_open else Parts.DRAWER_MARGIN)
	shut_bottom.call(open)
	pane.add_child(drawer)
	var rows := drawer.get_child(0) as VBoxContainer
	var key: Control = ModKey.new()
	key.name = "OtherCompaniesKey"
	key.set("summary", summary)
	key.set("key_scale", 0.8)
	key.mouse_filter = Control.MOUSE_FILTER_PASS
	key.call("set_open", open)
	rows.add_child(key)
	var inside := VBoxContainer.new()
	inside.name = "Drawer"
	inside.add_theme_constant_override("separation", Parts.MODULE_GAP)
	inside.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inside.visible = open
	rows.add_child(inside)
	key.connect("toggled", func(now_open: bool) -> void:
		inside.visible = now_open
		shut_bottom.call(now_open)
		panel.set_meta(META_OTHERS, now_open))
	var by_company := {}
	var companies: Array = []
	for b: Dictionary in others:
		var owner := str(b.get("owner", ""))
		if not by_company.has(owner):
			by_company[owner] = []
			companies.append(owner)
		(by_company[owner] as Array).append(b)
	var kept: Dictionary = panel.get_meta(META_GROUPS, {})
	for i in companies.size():
		var owner: String = companies[i]
		if i > 0:
			inside.add_child(Parts.spacer(0, 4))
		inside.add_child(_sub_caption(BuildingReadout.company_name(owner), "Company"))
		for g: Dictionary in _groups(by_company[owner], true):
			var members: Array = g.members
			var first: Dictionary = members[0]
			if members.size() == 1:
				inside.add_child(_their_module(panel, first, grid))
				continue
			var member_modules: Array[Control] = []
			for m: Dictionary in members:
				member_modules.append(_their_member(panel, m))
			var head := _their_head(first, members.size(), grid)
			var key_id := "other|" + str(g.key)
			inside.add_child(_group_block(panel, key_id, head, member_modules, bool(kept.get(key_id, false))))


## Another company's building: its emblem, its name and what it is set up to make, in your wells' column.
## Other companies' buildings don't run, so it shows no lamp, quantity or cost. A click opens it in
## Building Detail.
static func _their_module(panel: Control, b: Dictionary, grid: Dictionary) -> PanelContainer:
	var module := Parts.module("OtherCard_%s" % str(b.get("instance_id", "")))
	var row := Parts.row_of(module)
	row.add_child(Parts.emblem(str(b.get("building_id", "")), Parts.EMBLEM_PX))
	row.add_child(Parts.info(_name_of(b), "", ""))
	var gid := _first_output(b)
	row.add_child(Parts.wells([{"good_id": gid, "qty": -1}] if gid != "" else [], false, true, float(grid.fig_w)))
	if float(grid.cost_w) > 0.0:
		row.add_child(Parts.spacer(float(grid.cost_w), 0))
	Tip.attach(module, _owner_tip(_name_of(b), b))
	var iid := str(b.get("instance_id", ""))
	Parts.on_click(module, func() -> void: panel.call("_open_building_or_construction", iid))
	return module


## Another company's building's hover: whose it is.
static func _owner_tip(title: String, b: Dictionary) -> Dictionary:
	return {"name": title, "detail": "Owned by %s." % BuildingReadout.company_name(str(b.get("owner", "")))}


## A member of another company's group on its cable: its short name on one line (the head shows the good).
static func _their_member(panel: Control, b: Dictionary) -> PanelContainer:
	var module := Parts.module("OtherCard_%s" % str(b.get("instance_id", "")), true)
	Parts.row_of(module).add_child(Parts.line_info(_member_name(b), "", ""))
	Tip.attach(module, _owner_tip(_name_of(b), b))
	var iid := str(b.get("instance_id", ""))
	Parts.on_click(module, func() -> void: panel.call("_open_building_or_construction", iid))
	return module


static func _their_head(first: Dictionary, count: int, grid: Dictionary) -> PanelContainer:
	var module := Parts.module("OtherGroup")
	var row := Parts.row_of(module)
	row.add_child(Parts.emblem(str(first.get("building_id", "")), Parts.EMBLEM_PX))
	var info := Parts.info(_group_name(first), "", "%d buildings" % count, true, _words_width(grid) + Parts.lamp_room())
	row.add_child(info)
	var gid := _first_output(first)
	row.add_child(Parts.wells([{"good_id": gid, "qty": -1}] if gid != "" else [], false, true, float(grid.fig_w)))
	if float(grid.cost_w) > 0.0:
		row.add_child(Parts.spacer(float(grid.cost_w), 0))
	Tip.attach(module, {"name": _group_name(first), "detail": "%d buildings owned by %s." % [count,
		BuildingReadout.company_name(str(first.get("owner", "")))]})
	module.set_meta("chevron", info.find_child("Chevron", true, false))
	return module


## The port another company owns, in the port's own case: whose it is, the price the Buildings market asks
## on an LED screen in the house money format (MoneyFigure: £10.0K), and beside it a Buy key; pressing it
## opens the confirmation the v2 card used.
static func _port_module(panel: Control, port: Dictionary) -> PanelContainer:
	var module := Parts.module("PortBuildingCard")
	var row := Parts.row_of(module)
	row.add_child(Parts.emblem(PORT_ID, Parts.EMBLEM_PX))
	var owner := BuildingReadout.company_name(str(port.get("owner", "")))
	row.add_child(Parts.info("Port", "", "Owned by %s" % owner))
	var price := BuildingReadout.buy_price(port)
	var shown := MoneyFigure.led(float(price))
	var figure := str(shown.figure)
	var money := Parts.money(figure, DS.PALETTE["TEXT"], MoneyFigure.cells(figure), str(shown.suffix))
	var price_box: HBoxContainer = Tip.TipHBox.new()
	price_box.name = "PortPrice"
	price_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	price_box.mouse_filter = Control.MOUSE_FILTER_PASS
	for part in money.get_children():
		money.remove_child(part)
		price_box.add_child(part)
	money.free()
	price_box.add_theme_constant_override("separation", 4)
	Tip.attach(price_box, {"name": "The port's price", "detail": "%s from %s." % [MoneyFigure.text(float(price)), owner]})
	row.add_child(price_box)
	var buy := Parts.key_button("Buy", "PortBuyButton", 0.8)
	buy.size_flags_horizontal = Control.SIZE_SHRINK_END
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy.custom_minimum_size.x = CANCEL_W
	var iid := str(port.get("instance_id", ""))
	buy.disabled = Tutorial.port_purchase_disabled(PORT_ID)
	Tip.attach(buy, {"name": "Buy the port", "detail": Tutorial.PORT_PURCHASE_DISABLED_TOOLTIP + "." if buy.disabled \
		else "Buy it for %s." % MoneyFigure.text(float(price))})
	buy.pressed.connect(func() -> void: panel.call("_open_port_buy", iid, price))
	row.add_child(buy)
	Tip.attach(module, {"name": "Port", "detail": "Owned by %s." % owner})
	Parts.on_click(module, func() -> void: panel.emit_signal("building_clicked", port))
	return module


static func _first_output(b: Dictionary) -> String:
	var recipe: Dictionary = Catalog.get_recipe(str(b.get("recipe_id", "")))
	if recipe.is_empty():
		return ""
	for o: Dictionary in BuildingReadout.flow(b, recipe, false).get("outputs", []):
		if str(o.get("good_id", "")) != "":
			return str(o.get("good_id", ""))
	return ""


# --- the land's own ------------------------------------------------------------------------

## Woods and ruins that belong to the land, not to a company, in their own case under a raised heading:
## each kind once, a module with its emblem, its name and the land it covers (BuildingState.space_used),
## two to a row. A click opens one in Building Detail.
static func _add_features(panel: Control, pane: VBoxContainer, site: Dictionary) -> void:
	var features: Array = site.features
	if features.is_empty():
		return
	var kinds := {}
	var order: Array = []
	for b: Dictionary in features:
		var bid := str(b.get("building_id", ""))
		if not kinds.has(bid):
			kinds[bid] = []
			order.append(bid)
		(kinds[bid] as Array).append(b)
	var case := Parts.plastic_case("LandFeatures")
	pane.add_child(case)
	var rows := case.get_child(0) as VBoxContainer
	rows.add_child(Parts.heading("Land features"))
	var grid := GridContainer.new()
	grid.name = "Features"
	grid.columns = mini(2, order.size())
	grid.add_theme_constant_override("h_separation", Parts.MODULE_GAP)
	grid.add_theme_constant_override("v_separation", Parts.MODULE_GAP)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(grid)
	for bid: String in order:
		var list: Array = kinds[bid]
		var land := 0.0
		for b: Dictionary in list:
			land += BuildingState.space_used(b)
		var kind := str(Catalog.get_building(bid).get("display_name", bid))
		var name := kind if list.size() == 1 else "%d %s" % [list.size(), kind]
		var module := Parts.module("Feature_%s" % bid)
		module.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var row := Parts.row_of(module)
		row.add_child(Parts.emblem(bid, Parts.EMBLEM_PX))
		row.add_child(Parts.info(name, "", "Covers %d land" % roundi(land)))
		var first_iid := str((list[0] as Dictionary).get("instance_id", ""))
		Parts.on_click(module, func() -> void: panel.call("_open_building_or_construction", first_iid))
		Tip.attach(module, {"name": kind, "detail": "Part of the land, not a company's. It covers %d land here." % roundi(land)})
		grid.add_child(module)
