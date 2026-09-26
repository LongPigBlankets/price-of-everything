extends RefCounted
## Tile view v3: the Transport tab's body (docs/tile-view-ds2-plan.md §4.3 and §9), built into `pane` on each
## refresh while UiPrefs.use_tvp_v3 is on. With the switch off the v2 panel builds the tab itself.
## `panel` is the tile view (scripts/tile_info_panel_v2.gd): its tile, its signals and its helpers.
##
## The site's services, as the cabinet's concept has them, in one plastic case like Building Detail's
## diagnostics: one rack of modules with the site's cable down its left. First the links built here, each
## a module tapped off the cable: its emblem over a lamp for its load, its name on a key that opens it, its
## level on a drum with the key that raises it (the key printing the price and what the next level
## carries, greyed at the top level), its load on a meter against capacity, the goods riding it, and a line
## only when something is wrong. Then the links that can still be built, spare modules further down the
## same rack that the cable runs past without a tap, set out as a table: what each carries, how far it
## reaches in a turn and what it takes, and its Build key printing what the press will spend and what it
## buys with it. HVDC, which no building provides yet, stays hidden. The whole tab waits for
## Infrastructure Tendering, as the v2 section always has.
##
## One column grid runs through the case, the same in every state: the headings stand over the modules'
## left edge, and the emblems, the names, the drums and the keys line up in both groups; every meter's
## figure takes one fixed width, so the meters end together. The case's side screws keep clear of the
## headings and the modules' edges.
##
## Every figure comes from the engine: TileViewData.infrastructure_summary (state, load, capacity), Power's
## per tile figures for cables, BuildingWorks (level, the upgrade's quote and progress), TransportState (the
## goods on a link, its history over capacity and the overages it caused), Construction (a link being
## built and what laying one takes), EconomyConfig (a link's reach at a level), and the Build key's quote
## (scripts/tvp_v3/transport_quote.gd, the map's own pricing steps read without acting).

const TileViewData := preload("res://scripts/tile_view_data.gd")
const Section := preload("res://scripts/bdp_v3_section.gd")
const Heading := preload("res://scripts/bdp_v3_heading.gd")
const Counter := preload("res://scripts/bdp_v3_counter.gd")
const Cable := preload("res://scripts/bdp_v3_cable.gd")
const Nine := preload("res://scripts/bdp_v3_nine.gd")
const Led := preload("res://scripts/bdp_v3_led.gd")
const Plate := preload("res://scripts/bdp_v3_plate.gd")
const UIFonts := preload("res://scripts/ui_fonts.gd")
const UIHelpers := preload("res://scripts/ui_helpers.gd")
const BuildingLevels := preload("res://scripts/building_levels.gd")
const Meter := preload("res://scripts/tvp_v3/transport_meter.gd")
const Key := preload("res://scripts/tvp_v3/transport_key.gd")
const Emblem := preload("res://scripts/tvp_v3/transport_emblem.gd")
const Quote := preload("res://scripts/tvp_v3/transport_quote.gd")

## Building Detail's diagnostics module plate (layout.json diag_module): its shadow room and 9-slice corner.
const MODULE: Texture2D = preload("res://assets/ui/bdp_v3/diag_module.png")
const MODULE_MARGIN := 10.0 / 1.875
const MODULE_CORNER := 26.0 * 2.0 / 1.875
const MODULE_PAD := 10.0
## A spare module, not yet wired: the same plate, a shade duller.
const SPARE_TINT := Color(0.8, 0.8, 0.82)
## The cable down the case's left, and the modules' left margin (a branch's length to its right).
const CABLE_X := 10.0
const GUTTER := CABLE_X + Cable.TAP_LENGTH
const CARD_RIGHT := 2.0
const MODULE_GAP := 8
## The plastic case and its silver screws (layout.json diag_plastic, screw_silver), about this far apart.
const PLASTIC: Texture2D = preload("res://assets/ui/bdp_v3/diag_plastic.png")
const SCREW: Texture2D = preload("res://assets/ui/bdp_v3/screw_silver.png")
const SCREW_PITCH := 170.0
## How far a side screw keeps from a heading's line or a module's edge (its radius and a little more),
## and how far it may move off its even spacing to find a clear place before it is left out.
const SCREW_CLEAR := 14.0
const SCREW_SHIFT := 48.0
## The room above the spare modules' heading, down the rack from the last built link.
const GROUP_GAP := 12
## Text: body 14 (IBM Plex Sans Medium, a row's own title semibold), captions 15 (Barlow Condensed SemiBold).
const BODY_PX := 14
const CAPTION_PX := 15
## The column grid, the same in every state: the gap between columns, every key's width (it fits the
## longest print a key carries, "Land and materials", at 13 px), the meters' caption column, the spare
## modules' Reach and Capacity columns, and the meters' figure column, as wide as the widest figure a
## link at any level reads (a wider one, far over capacity, widens it).
const COL_GAP := 8
const KEY_SCALE := 1.0
const KEY_W := 122.0
const CAPTION_W := 50.0
const REACH_W := 42.0
const CAPACITY_W := 70.0
const FIGURE_TEMPLATES := ["8,888 of 8,888 MW", "888 of 888 a turn"]
## The gap between the lines of a module.
const BODY_GAP := 7
## The least width a wrapping sentence asks for.
const LINE_MIN_W := 160.0
## Names where the v2 grid had to abbreviate.
const NAMES := {"reinf_pipes": "Reinforced pipes"}
## The goods on a link or needed to lay one: their icons' side, how many show, and Building Detail's icon
## well (layout.json icon_well: how far the frame reaches beyond the opening, its 9-slice corner, the
## opening's radius); the quantity pill kept small and inside the icon's corner (DS2 rule 7), on an icon
## large enough that a three figure quantity leaves most of the drawing clear.
const GOOD_PX := 52
const GOODS_SHOWN := 6
const WELL: Texture2D = preload("res://assets/ui/bdp_v3/icon_well.png")
const WELL_REACH := (12.0 + 7.0) / 1.875
const WELL_CORNER := (12.0 + 7.0 + 16.0) * 2.0 / 1.875
const WELL_RADIUS := 10.0 / 1.875
const PILL_H := 16.0
const PILL_INSET := 3.0
const PILL_PX := 12
## The tile and the levels its drums last read, so a drum rolls only when a link's level changes.
const META_LEVELS := "tvp_transport_levels"


static func build(panel: Control, pane: VBoxContainer) -> void:
	var tile_id := str(panel.get("_current_tile_id"))
	var tile_data: Dictionary = panel.get("_current_tile_data")
	if tile_id == "":
		return
	# The research gating the v2 section has always had: in a logistics game the links are a tendered
	# capability, and until Infrastructure Tendering the tab shows only why.
	if not ResearchState.infrastructure_tendering_available():
		pane.add_child(_note("Links open with Infrastructure Tendering."))
		return
	var near := near_share(panel)
	var links: Array = []
	var spare: Array = []
	for slot: Dictionary in TileViewData.infrastructure_summary(tile_id, tile_data):
		match str(slot.get("state", "")):
			"exists": links.append(link_state(tile_id, slot, near, true))
			"add": spare.append(slot)
			# "unavailable": no building provides it (HVDC), so it stays hidden until one does.
	var memory: Dictionary = panel.get_meta(META_LEVELS, {}) if panel.has_meta(META_LEVELS) else {}
	var last: Dictionary = memory.get("levels", {}) if str(memory.get("tile", "")) == tile_id else {}
	var levels := {}
	if not links.is_empty() or not spare.is_empty():
		var case := _plastic_case()
		case.name = "TransportLinks"
		var content := case.get_child(0) as VBoxContainer
		content.add_theme_constant_override("separation", MODULE_GAP)
		# The headings stand over the modules' left edge: past the cable's gutter when it runs down the rack.
		var indent := GUTTER if not links.is_empty() else 0.0
		if not links.is_empty():
			content.add_child(_heading_row("Links", false, indent))
		content.add_child(_rack(panel, tile_id, links, spare, indent, last, levels))
		for l in case.find_children("*", "Label", true, false):
			_emboss(l)
		pane.add_child(case)
	panel.set_meta(META_LEVELS, {"tile": tile_id, "levels": levels})


## The share of capacity at which a link counts as near it: the one the Transport key's figure uses.
static func near_share(panel: Control) -> float:
	var s: Script = panel.get_script()
	return float(s.get_script_constant_map().get("V3_LINK_NEAR", 0.9)) if s != null else 0.9


## A link's tone from its load: red over capacity, amber near it, green with room.
static func link_tone(share: float, near: float) -> String:
	if share > 1.0:
		return "bad"
	return "warn" if share >= near else "ok"


## Everything a built link's module shows, read from the engine once: its level and the upgrade's quote,
## its meters ([caption, load, capacity, figure]), its tone, what is wrong with it, the overages it has
## caused and the goods riding it.
static func link_state(tile_id: String, slot: Dictionary, near: float, can_build: bool) -> Dictionary:
	var key := str(slot.get("key", ""))
	var inst: Dictionary = slot.get("instance", {})
	var transit: Dictionary = slot.get("transit", {})
	var mode := str(TileViewData.CAPPED_MODES.get(key, ""))
	var s := {
		"key": key, "slot": slot, "instance": inst, "title": _name(slot), "mode": mode,
		"building_id": str((slot.get("building_data", {}) as Dictionary).get("id", "")),
		"level": BuildingWorks.infra_tile_level(inst) if not inst.is_empty() else 1,
		"meters": [], "share": 0.0, "capped": false, "status": "", "status_ink": DS.PALETTE["TEXT"],
		"paid": 0.0, "riding": [], "near": near,
	}
	var level: int = s.level
	# The load: cables carry power, each way up to the tile's cable cap; the goods links carry units.
	if key == "cables":
		var pcap := Power.tile_power_cap(tile_id)
		var made := int(Power.tile_produced.get(tile_id, 0))
		var drawn := int(Power.tile_drawn.get(tile_id, 0))
		if pcap > 0:
			s.capped = true
			s.share = float(maxi(made, drawn)) / float(pcap)
			s.meters = [["Drawn", drawn, pcap, "%s of %s MW" % [_count(drawn), _count(pcap)]],
				["Made", made, pcap, "%s of %s MW" % [_count(made), _count(pcap)]]]
	elif bool(slot.get("capped", false)) and int(transit.get("cap", 0)) > 0:
		var cap := int(transit.get("cap", 0))
		var used := int(transit.get("used", 0))
		s.capped = true
		s.share = float(transit.get("pct", 0.0))
		s.meters = [["Carried", used, cap, "%s of %s a turn" % [_count(used), _count(cap)]]]
	s["tone"] = link_tone(float(s.share), near) if bool(s.capped) else "ok"

	# What is wrong with it, if anything: the words say what the lamp and the meter show.
	var link_key := "%s|%s" % [tile_id, mode]
	var share: float = s.share
	if not bool(s.capped):
		s.status = "No limit on what it carries."
	elif key == "cables":
		var limit := _count(Power.tile_power_cap(tile_id))
		if share >= near:
			s.status = ("At its limit. " if share >= 1.0 else "Near its limit. ") + "Power above %s MW each way is cut." % limit
			s.status_ink = _tone_ink(str(s.tone))
	else:
		var cap := int(transit.get("cap", 0))
		if share >= near:
			var l1 := float(EconomyConfig.TRANSPORT_LINK_CAP_BY_MODE.get(mode, 0))
			var times := "triple" if float(transit.get("used", 0)) > float(cap) + l1 else "double"
			s.status = ("Over capacity. " if share > 1.0 else "Near capacity. ") \
				+ "Goods above %s a turn pay %s freight." % [_count(cap), times]
			s.status_ink = _tone_ink(str(s.tone))
		else:
			var turns_over := TransportState.link_turns_over(link_key)
			if turns_over > 0:
				s.status = "Over capacity %d of the last %d turns." % [turns_over, TransportState.LINK_HISTORY_TURNS]
				s.status_ink = DS.PALETTE["WARN"]
	if mode != "":
		s.paid = TransportState.link_congestion_paid(link_key)
		if int(transit.get("used", 0)) > 0:
			s.riding = TransportState.tile_good_breakdown(tile_id, mode)

	# Its level and what raising it takes and brings.
	var iid := str(inst.get("instance_id", ""))
	var quote: Dictionary = BuildingWorks.preview_upgrade(iid) if iid != "" else {}
	s["quote"] = quote
	s["upgradable"] = can_build and bool(quote.get("ok", false)) and not bool(quote.get("at_max", false))
	# An upgrade under way shows whatever the research, since it is already paid for.
	s["upgrading"] = bool(quote.get("ok", false)) and bool(quote.get("already_upgrading", false))
	s["target"] = int(quote.get("target_level", level + 1))
	return s


# ── The rack ──────────────────────────────────────────────────────────────────────────────────────

## One rack of modules, `indent` in from the case's edge: the links built here, then under their heading
## the links that can still be built. When links are built the site's cable runs down the rack's left from
## the first module to the last, tapped into each built link and running past the spare ones, which are
## not wired yet; the headings keep to the modules' column, clear of it.
static func _rack(panel: Control, tile_id: String, links: Array, spare: Array, indent: float, last: Dictionary,
		levels: Dictionary) -> Control:
	var card := _card(indent)
	card.name = "TransportRack"
	var list := card.get_child(0) as VBoxContainer
	var taps: Array[Control] = []
	var figure_w := _figure_width(links)
	for s: Dictionary in links:
		var m := _link_module(panel, s, figure_w, last, levels)
		list.add_child(m)
		taps.append(m)
	if not spare.is_empty():
		if not links.is_empty():
			list.add_child(_gap(GROUP_GAP))
		list.add_child(_heading_row("Add a link", true))
		var building: Dictionary = {}
		for project: Dictionary in Construction.projects_on_tile(tile_id):
			building[str(project.get("building_id", ""))] = project
		for slot: Dictionary in spare:
			var bd: Dictionary = slot.get("building_data", {})
			list.add_child(_spare_module(panel, tile_id, slot, building.get(str(bd.get("id", "")), {})))
	if not taps.is_empty():
		var cable: Control = Cable.new()
		cable.set("centre_x", CABLE_X - indent)
		card.add_child(cable)
		cable.set("taps", taps)
	return card


# ── Links built here ──────────────────────────────────────────────────────────────────────────────


## One built link: its emblem over its lamp; its name on a key that opens it, its level on a drum and the
## key that raises it; its load against capacity; the goods on it; what is wrong, if anything.
static func _link_module(panel: Control, s: Dictionary, figure_w: float, last: Dictionary, levels: Dictionary) -> Control:
	var key: String = s.key
	var title: String = s.title
	var inst: Dictionary = s.instance
	var level: int = s.level
	var module := _module()
	module.name = "InfraCell_%s" % key
	module.set_meta("tvp_transport_tone", s.tone)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", COL_GAP)
	module.add_child(row)
	# The lamp stands level with the first meter, the line it judges.
	var emblem: Control = Emblem.new()
	var head_h := Key.height_for(KEY_SCALE)
	emblem.call("set_link", str(s.building_id), str(s.tone), head_h, true,
		head_h + BODY_GAP + Meter.HEIGHT * 0.5 if not (s.meters as Array).is_empty() else -1.0)
	row.add_child(emblem)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", BODY_GAP)
	row.add_child(body)

	# The name, on a key that opens the link; the level on a drum; the key that raises it.
	var head := HBoxContainer.new()
	head.name = "Head"
	head.add_theme_constant_override("separation", 6)
	body.add_child(head)
	var open_it: Button = Key.make("InfraOpen_%s" % key, title, "", Key.width_for(title, "", true, false, KEY_SCALE), true, false, KEY_SCALE)
	open_it.tooltip_text = "Open %s. %s." % [title.to_lower(), _carries(key, level)]
	open_it.pressed.connect(func() -> void: panel.call("_on_infra_pressed", inst, "", ""))
	head.add_child(open_it)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(fill)
	head.add_child(_caption("Level"))
	var drum: Control = Counter.new()
	drum.call("configure", 1, 0)
	drum.call("set_value", float(level), float(last[key]) if last.has(key) else NAN)
	levels[key] = level
	head.add_child(drum)
	head.add_child(_print("of %d" % BuildingLevels.MAX_LEVEL))
	head.add_child(_gap(COL_GAP - 6, true))
	head.add_child(_upgrade_key(panel, s))

	# The load against capacity, every figure in the widest one's width so the meters end together.
	for m: Array in s.meters:
		body.add_child(_meter_row(str(m[0]), float(m[1]), float(m[2]), str(m[3]), figure_w, float(s.near), float(s.share) > 1.0))
	var riding := _goods_row(s.riding)
	if riding != null:
		body.add_child(riding)
	if str(s.status) != "":
		body.add_child(_line(str(s.status), false, s.status_ink))
	if float(s.paid) >= 0.005:
		body.add_child(_overages(float(s.paid)))

	# The whole module opens the link too, as the v2 cell did, and brightens its emblem under the pointer.
	module.mouse_filter = Control.MOUSE_FILTER_STOP
	module.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	module.tooltip_text = open_it.tooltip_text
	module.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			panel.call("_on_infra_pressed", inst, "", ""))
	module.mouse_entered.connect(func() -> void: emblem.set("hot", true))
	module.mouse_exited.connect(func() -> void: emblem.set("hot", false))
	return module


## The key that raises a link's level, printing the price and what the next level takes (or, in red, that
## the cash won't cover it); latched while an upgrade runs, with the turns left; greyed at the top level, as
## Building Detail's Upgrade key is at its maximum, so every module keeps a key in the column.
static func _upgrade_key(panel: Control, s: Dictionary) -> Control:
	var key: String = s.key
	var quote: Dictionary = s.quote
	var target: int = s.target
	if bool(s.upgrading):
		var left := int(quote.get("pending_turns_left", 0))
		var busy: Button = Key.make("InfraUpgrade_%s" % key, "Upgrading", "%d turn%s left" % [left, "" if left == 1 else "s"],
			KEY_W, false, true, KEY_SCALE)
		busy.tooltip_text = "%s reach level %d in %d turn%s." % [str(s.title), target, left, "" if left == 1 else "s"]
		return busy
	if bool(s.upgradable):
		var price := float(quote.get("cash_cost", 0.0))
		var gain: Dictionary = quote.get("capacity", {})
		var to := roundi(float(gain.get("new", 0.0)))
		var what := ("To %s MW" % _count(to)) if key == "cables" else ("To %s a turn" % _count(to))
		var paid := bool(quote.get("affordable", true))
		var up: Button = Key.make("InfraUpgrade_%s" % key, "Upgrade %s" % _money(price), what if paid else "Not enough cash",
			KEY_W, false, false, KEY_SCALE)
		if not paid:
			up.set("detail_ink", Key.RED_INK)
		up.tooltip_text = "Level %d takes %s%s. Confirm it in Building Detail.%s" % [target,
			_capacity_words(key, to), _reach_gain(str(s.mode), int(s.level), target),
			"" if paid else " It costs more than the cash you have."]
		up.pressed.connect(func() -> void: _open_upgrade(panel, s.instance))
		return up
	if bool(quote.get("at_max", false)) or int(s.level) >= BuildingLevels.MAX_LEVEL:
		var top: Button = Key.make("InfraUpgrade_%s" % key, "Top level", "", KEY_W, false, false, KEY_SCALE)
		top.call("set_spent", true)
		top.tooltip_text = "Level %d is the top level. %s can't be raised further." % [int(s.level), str(s.title)]
		return top
	var room := Control.new()
	room.name = "InfraUpgrade_%s" % key
	room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	room.custom_minimum_size = Vector2(KEY_W, Key.height_for(KEY_SCALE))
	return room


## A meter's line: its caption, the meter, and the figure it reads (red when the link is over capacity).
static func _meter_row(caption: String, load_now: float, cap: float, figure: String, figure_w: float, near: float, over: bool) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	var c := _caption(caption)
	c.custom_minimum_size.x = CAPTION_W
	hb.add_child(c)
	var meter: Control = Meter.new()
	meter.name = "Meter%s" % caption
	meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The lit run in the load's own tone, by the rule the lamp and the words use.
	meter.call("set_load", load_now, cap, near, link_tone(load_now / maxf(cap, 1.0), near))
	hb.add_child(meter)
	var f := _print(figure, false, DS.PALETTE["DANGER"] if over else DS.PALETTE["TEXT"])
	f.custom_minimum_size.x = figure_w
	f.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hb.add_child(f)
	return hb


## The meters' figure column: the templates' width, the same on every tile, or a wider figure's in the case.
static func _figure_width(links: Array) -> float:
	var w := 0.0
	for t: String in FIGURE_TEMPLATES:
		w = maxf(w, UIFonts.PLEX_MED.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_PX).x)
	for s: Dictionary in links:
		for m: Array in s.meters:
			w = maxf(w, UIFonts.PLEX_MED.get_string_size(str(m[3]), HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_PX).x)
	return ceilf(w) + 2.0


## The overages this link has caused, on an LED screen after a printed £, red as costs are.
static func _overages(paid: float) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.name = "Overages"
	hb.add_theme_constant_override("separation", 6)
	hb.add_child(_caption("Overages so far"))
	var pound := _caption("£")
	pound.uppercase = false
	pound.add_theme_font_size_override("font_size", 18)
	hb.add_child(pound)
	var led: Control = Led.new()
	led.call("set_figure", "%.2f" % paid, DS.PALETTE["DANGER"])
	hb.add_child(led)
	return hb


## The goods riding a link this turn (TransportState.tile_good_breakdown), each its icon in a well with its
## quantity in a pill inside, most first; null when nothing rides it.
static func _goods_row(rows: Array) -> Control:
	var moving: Array = []
	for r: Dictionary in rows:
		if int(r.get("qty", 0)) > 0:
			moving.append(r)
	if moving.is_empty():
		return null
	moving.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("qty", 0)) > int(b.get("qty", 0)))
	var hb := HBoxContainer.new()
	hb.name = "GoodsOnLink"
	hb.add_theme_constant_override("separation", 8)
	var c := _caption("Goods")
	c.custom_minimum_size.x = CAPTION_W
	hb.add_child(c)
	var shown := mini(moving.size(), GOODS_SHOWN if moving.size() <= GOODS_SHOWN else GOODS_SHOWN - 1)
	for i in shown:
		var gid := str(moving[i].get("good_id", ""))
		hb.add_child(_good_icon(gid, int(moving[i].get("qty", 0)), "on it this turn"))
	if moving.size() > shown:
		hb.add_child(_print("and %d more" % (moving.size() - shown)))
	return hb


# ── Links that can still be built ─────────────────────────────────────────────────────────────────

## One link that can be built: its emblem (no lamp: nothing is running to judge), its name and what it
## carries, its reach and capacity at level 1 in the table's columns, what laying it takes, and its Build
## key, latched with its lamp lit while the link is being built. Named InfraCell_<key> for the tutorial,
## which presses the first Button in it: the Build key.
static func _spare_module(panel: Control, tile_id: String, slot: Dictionary, project: Dictionary) -> Control:
	var key := str(slot.get("key", ""))
	var title := _name(slot)
	var mode := str(TileViewData.CAPPED_MODES.get(key, ""))
	var bd: Dictionary = slot.get("building_data", {})
	var bid := str(bd.get("id", ""))
	var head_h := Key.height_for(KEY_SCALE)
	var module := _module()
	module.name = "InfraCell_%s" % key
	module.self_modulate = SPARE_TINT
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", COL_GAP)
	module.add_child(row)
	var emblem: Control = Emblem.new()
	emblem.call("set_link", bid, "off", head_h, false)
	row.add_child(emblem)

	var main := VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 7)
	row.add_child(main)
	var top := HBoxContainer.new()
	top.name = "Head"
	top.custom_minimum_size.y = head_h
	top.add_theme_constant_override("separation", COL_GAP)
	main.add_child(top)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", 0)
	top.add_child(words)
	words.add_child(_print(title, true))
	var carries := _print(_carried(key))
	carries.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	carries.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	carries.custom_minimum_size.x = 90
	words.add_child(carries)
	var reach := EconomyConfig.infra_range_for_level(mode, 1) if mode != "" else 0
	var cap := _capacity(key, 1)
	top.add_child(_cell(("%d tiles" % reach) if reach > 0 else "Grid", REACH_W,
		("Goods move %d tiles a turn on it." % reach) if reach > 0 else "Cables join the tile to the grid."))
	top.add_child(_cell(_capacity_short(key, cap), CAPACITY_W,
		("Power above %s MW each way is cut." % _count(cap)) if key == "cables"
		else "Goods above %s a turn pay double freight." % _count(cap)))

	# The key on the same line as the figures it would bring, in the keys' column.
	if not project.is_empty():
		var waiting := str(project.get("status", "")) == Construction.STATUS_AWAITING_MATERIALS
		var left := int(project.get("turns_remaining", 0))
		var busy: Button = Key.make("InfraBuilding_%s" % key, "Building",
			"Needs materials" if waiting else "%d turn%s left" % [left, "" if left == 1 else "s"], KEY_W, false, true, KEY_SCALE)
		busy.tooltip_text = "Waiting for its materials." if waiting else "Being built, %d turn%s to go." % [left, "" if left == 1 else "s"]
		top.add_child(busy)
	else:
		top.add_child(_build_key(panel, tile_id, slot, bid, title, module))
	# What laying it takes, under the line.
	var needs := _needs_row(tile_id, bid) if project.is_empty() else null
	if needs != null:
		main.add_child(needs)
	return module


## The Build key, printing what the press will spend (the fee, any land it buys and any materials it orders,
## from the quote) and under it what that buys besides the fee: the land, the materials, or both; in red,
## why the map would refuse it or that the cash won't cover it. It is never disabled: the map has the last
## word, as with the v2 cell.
static func _build_key(panel: Control, tile_id: String, slot: Dictionary, bid: String, title: String, module: Control) -> Button:
	var key := str(slot.get("key", ""))
	var q := Quote.quote(tile_id, bid)
	var detail := ""
	var warn := false
	if not bool(q.ok):
		detail = str(q.refusal)
		warn = true
	elif not bool(q.affordable):
		detail = "Not enough cash"
		warn = true
	elif int(q.land_units) > 0 and str(q.materials) != "":
		detail = "Land and materials"
	elif int(q.land_units) > 0:
		detail = "Buys %d land" % int(q.land_units)
	elif str(q.materials) == "order":
		detail = "Orders materials"
	elif str(q.materials) == "ship":
		detail = "Ships materials in"
	var b: Button = Key.make("InfraBuild_%s" % key, ("Build %s" % _money(float(q.total))) if bool(q.ok) else "Build", detail,
		KEY_W, false, false, KEY_SCALE)
	if warn:
		b.set("detail_ink", Key.RED_INK)
	b.tooltip_text = _build_words(title, q)
	b.set_meta("tvp_transport_quote", q)
	var internal := str(slot.get("internal_name", key))
	# The v2 cell's helper: it asks the map to build, then flashes the row. It fades in a built icon only
	# when the overlay has one, and this row has none.
	var overlay := TextureRect.new()
	overlay.visible = false
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(overlay)
	b.pressed.connect(func() -> void: panel.call("_on_infra_add_pressed", internal, module, b, overlay))
	return b


## What the Build key's press spends and does, itemised for its hover.
static func _build_words(title: String, q: Dictionary) -> String:
	if not bool(q.ok):
		return str(q.why)
	var parts: Array[String] = []
	parts.append("Laying %s costs %s%s." % [title.to_lower(), _money(float(q.fee)),
		", 50% more past the planning limit" if bool(q.planning) else ""])
	if int(q.land_units) > 0:
		parts.append("The %d land it needs costs %s." % [int(q.land_units), _money(float(q.land_cost))])
	var lacking := _goods_list(q.get("missing", {}))
	match str(q.materials):
		"order": parts.append("The materials it lacks (%s) cost %s, ordered with it." % [lacking, _money(float(q.materials_cost))])
		"ship": parts.append("Moving the materials it lacks (%s) here costs %s." % [lacking, _money(float(q.materials_cost))])
	if not bool(q.affordable):
		parts.append("That is more than the cash you have.")
	return " ".join(parts)


## A figure in one of the spare modules' columns, centred under its caption, saying what it means on hover.
static func _cell(text: String, width: float, tip: String) -> Label:
	var l := _print(text)
	l.custom_minimum_size.x = width
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	return l


## What laying a link takes (Construction.requirements_for), as goods in wells with their quantities, each
## saying on hover how many are on the tile; null when it takes none.
static func _needs_row(tile_id: String, building_id: String) -> Control:
	var reqs: Dictionary = Construction.requirements_for(building_id) if building_id != "" else {}
	if reqs.is_empty():
		return null
	var hb := HBoxContainer.new()
	hb.name = "Needs"
	hb.add_theme_constant_override("separation", 8)
	hb.add_child(_caption("Needs"))
	for gid in reqs:
		var have := Stockpile.get_at_tile(tile_id, str(gid))
		hb.add_child(_good_icon(str(gid), int(reqs[gid]), "to lay it, %s on this tile" % _count(have)))
	return hb


# ── Parts ─────────────────────────────────────────────────────────────────────────────────────────

## A group's heading in Building Detail's raised letters (the plain label when the atlas lacks a letter),
## `indent` in, over the modules' left edge. The spare group's heading, in the rack, carries the table's
## column captions over the columns in its modules.
static func _heading_row(text: String, columns: bool, indent := 0.0) -> Control:
	var hb := HBoxContainer.new()
	hb.name = "Heading"
	hb.add_theme_constant_override("separation", COL_GAP)
	if indent > 0.0:
		hb.add_child(_gap(indent - COL_GAP, true))
	if Heading.can_show(text):
		var raised: Control = Heading.new()
		raised.set("text", text)
		raised.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(raised)
	else:
		hb.add_child(_caption(text))
	if not columns:
		return hb
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(fill)
	for pair in [["Reach", REACH_W], ["Capacity", CAPACITY_W]]:
		var c := _caption(str(pair[0]))
		c.custom_minimum_size.x = float(pair[1])
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.size_flags_vertical = Control.SIZE_SHRINK_END
		hb.add_child(c)
	# The rest of the row: the key's column and the module's right margin.
	hb.add_child(_gap(KEY_W + MODULE_PAD, true))
	return hb


## A column of modules `indent` in from the case's edge.
static func _card(indent: float) -> PanelContainer:
	var card := PanelContainer.new()
	var bare := StyleBoxEmpty.new()
	bare.content_margin_left = indent
	bare.content_margin_right = CARD_RIGHT
	bare.content_margin_top = 0
	bare.content_margin_bottom = 2
	card.add_theme_stylebox_override("panel", bare)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", MODULE_GAP)
	card.add_child(list)
	return card


## Building Detail's moulded plastic case (diag_plastic, a 9-slice) with its silver screws round the edge, set
## about SCREW_PITCH apart whatever the case's length, so a short case isn't crowded with them; the side
## screws keep clear of the headings and the modules' edges (screw_points).
static func _plastic_case() -> MarginContainer:
	var case := MarginContainer.new()
	case.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	case.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var m := roundi(Section.RIM + Section.PADDING)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		case.add_theme_constant_override(side, m)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	case.add_child(content)
	case.draw.connect(func() -> void:
		Nine.paint(case, PLASTIC, Rect2(Vector2.ZERO, case.size).grow(Section.PLASTIC_MARGIN), Section.PLASTIC_CORNER_TEXELS)
		var s := SCREW.get_size() / 2.0
		for p in screw_points(case.size, _screw_bands(case)):
			case.draw_texture_rect(SCREW, Rect2(p - s * 0.5, s), false))
	case.resized.connect(case.queue_redraw)
	content.sort_children.connect(case.queue_redraw)
	return case


## The case's screws: one in each corner, then evenly along the top and bottom about SCREW_PITCH apart, and
## down each side as evenly, each side screw moved to the nearest height clear of `avoid` (bands of y, from
## _screw_bands) within SCREW_SHIFT, or left out when there is none.
static func screw_points(plate: Vector2, avoid: Array = []) -> PackedVector2Array:
	var lo := Vector2(Section.SCREW_INSET, Section.SCREW_INSET)
	var hi := plate - lo
	var across := maxi(2, roundi((hi.x - lo.x) / SCREW_PITCH) + 1)
	var down := maxi(2, roundi((hi.y - lo.y) / SCREW_PITCH) + 1)
	var pts := PackedVector2Array()
	for i in across:
		var x := lerpf(lo.x, hi.x, float(i) / (across - 1))
		pts.append(Vector2(x, lo.y))
		pts.append(Vector2(x, hi.y))
	var room := SCREW_PITCH * 0.4
	for i in range(1, down - 1):
		var y := _clear_height(lerpf(lo.y, hi.y, float(i) / (down - 1)), avoid, lo.y + room, hi.y - room)
		if is_nan(y):
			continue
		pts.append(Vector2(lo.x, y))
		pts.append(Vector2(hi.x, y))
	return pts


## The height nearest `y` within [top, bottom] that lies in none of `bands`, NAN when none lies within
## SCREW_SHIFT of it.
static func _clear_height(y: float, bands: Array, top: float, bottom: float) -> float:
	var step := 0.0
	while step <= SCREW_SHIFT:
		for at: float in [y + step, y - step]:
			if at < top or at > bottom:
				continue
			var clear := true
			for band: Vector2 in bands:
				if at >= band.x and at <= band.y:
					clear = false
					break
			if clear:
				return at
		step += 2.0
	return NAN


## The heights the case's side screws keep clear of: each heading's line and each module's top and bottom
## edge, SCREW_CLEAR either side, in the case's own coordinates.
static func _screw_bands(case: Control) -> Array:
	var bands: Array = []
	var to_case := case.get_global_transform().affine_inverse()
	for node in case.find_children("*", "Control", true, false):
		var c := node as Control
		var heading := c.name == &"Heading"
		if not heading and not str(c.name).begins_with("InfraCell_"):
			continue
		var top := (to_case * c.get_global_transform() * Vector2.ZERO).y
		var bottom := (to_case * c.get_global_transform() * Vector2(0.0, c.size.y)).y
		if heading:
			bands.append(Vector2(top - SCREW_CLEAR, bottom + SCREW_CLEAR))
		else:
			bands.append(Vector2(top - SCREW_CLEAR, top + SCREW_CLEAR))
			bands.append(Vector2(bottom - SCREW_CLEAR, bottom + SCREW_CLEAR))
	return bands


## A raised module in the plastic case, as each of Building Detail's diagnostics rows is.
static func _module() -> PanelContainer:
	var module := PanelContainer.new()
	var pad := StyleBoxEmpty.new()
	pad.content_margin_left = MODULE_PAD
	pad.content_margin_right = MODULE_PAD
	pad.content_margin_top = 8
	pad.content_margin_bottom = 9
	module.add_theme_stylebox_override("panel", pad)
	module.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	module.draw.connect(func() -> void:
		Nine.paint(module, MODULE, Rect2(Vector2.ZERO, module.size).grow(MODULE_MARGIN), MODULE_CORNER))
	return module


## Empty room: `px` tall, or wide when `across`.
static func _gap(px: float, across := false) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.custom_minimum_size = Vector2(px, 0.0) if across else Vector2(0.0, px)
	return c


## A sentence in a module: print that wraps rather than widen the tab (DS2 width discipline).
static func _line(text: String, title := false, colour: Color = DS.PALETTE["TEXT"]) -> Label:
	var l := _print(text, title, colour)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = LINE_MIN_W
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## Print on the dark plastic: white, 14 px, a row's own title semibold.
static func _print(text: String, title := false, colour: Color = DS.PALETTE["TEXT"]) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UIFonts.PLEX_SEMI if title else UIFonts.PLEX_MED)
	l.add_theme_font_size_override("font_size", BODY_PX)
	l.add_theme_color_override("font_color", colour)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


## A metal label: Barlow Condensed SemiBold capitals, 15 px, off-white.
static func _caption(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.uppercase = true
	l.add_theme_font_override("font", Plate.FONT_SEMI)
	l.add_theme_font_size_override("font_size", CAPTION_PX)
	l.add_theme_color_override("font_color", DS.PALETTE["TEXT"])
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


## White lettering that stands up off dark plastic: a dark shadow down and to the right.
static func _emboss(l: Label) -> void:
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)


## A good's cream icon set below a thin metal frame, its quantity in a small navy pill inside its corner
## (DS2 rule 7), kept clear of most of the drawing.
static func _good_icon(gid: String, qty: int, note: String) -> Control:
	var icon := UIHelpers.make_plain_good_icon(gid, Catalog.get_internal_name(gid), GOOD_PX)
	UIHelpers.link_good_icon_to_encyclopedia(icon, gid)
	var tile := icon.get_child(0) as PanelContainer
	if tile != null and tile.get_theme_stylebox("panel") is StyleBoxFlat:
		var st := (tile.get_theme_stylebox("panel") as StyleBoxFlat).duplicate() as StyleBoxFlat
		st.set_corner_radius_all(roundi(WELL_RADIUS))
		tile.add_theme_stylebox_override("panel", st)
	var well := Control.new()
	well.name = "IconWell"
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	well.set_anchors_preset(Control.PRESET_FULL_RECT)
	well.draw.connect(func() -> void:
		Nine.paint(well, WELL, Rect2(Vector2.ZERO, well.size).grow(WELL_REACH), WELL_CORNER))
	well.resized.connect(well.queue_redraw)
	icon.add_child(well)
	var text := _count(qty)
	var w := maxf(PILL_H, UIFonts.PLEX_SEMI.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, PILL_PX).x + 9.0)
	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	pill.offset_left = -w - PILL_INSET
	pill.offset_top = -PILL_H - PILL_INSET
	pill.offset_right = -PILL_INSET
	pill.offset_bottom = -PILL_INSET
	var st := StyleBoxFlat.new()
	st.bg_color = DS.PALETTE["BG_PANEL"]
	st.set_corner_radius_all(int(PILL_H / 2.0))
	st.set_border_width_all(1)
	st.border_color = DS.PALETTE["BORDER_STRONG"]
	st.content_margin_top = 0
	st.content_margin_bottom = 0
	pill.add_theme_stylebox_override("panel", st)
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UIFonts.PLEX_SEMI)
	l.add_theme_font_size_override("font_size", PILL_PX)
	l.add_theme_color_override("font_color", DS.PALETTE["ACCENT"])
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(l)
	icon.add_child(pill)
	icon.tooltip_text = ("%s %s %s" % [text, Catalog.get_display_name(gid), note]).strip_edges()
	return icon


## A tone's ink on dark: amber for warn, red for bad, white otherwise.
static func _tone_ink(tone: String) -> Color:
	match tone:
		"bad": return DS.PALETTE["DANGER"]
		"warn": return DS.PALETTE["WARN"]
	return DS.PALETTE["TEXT"]


## A note on a dark slab, for the tab when there is nothing to act on.
static func _note(text: String) -> Control:
	var slab: MarginContainer = Section.new()
	slab.name = "TransportNote"
	slab.set("style", "slab")
	var l := _print(text)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 200
	_emboss(l)
	(slab.get("content") as VBoxContainer).add_child(l)
	return slab


## Opens the link in Building Detail, on its upgrade sheet (where the price is confirmed).
static func _open_upgrade(panel: Control, inst: Dictionary) -> void:
	panel.call("_on_infra_pressed", inst, "", "")
	var detail := panel.get_tree().root.find_child("BuildingDetailPanelV2", true, false)
	if detail != null and detail.has_method("_open_upgrade_sheet"):
		detail.call_deferred("_open_upgrade_sheet", inst)


# ── Words and figures ─────────────────────────────────────────────────────────────────────────────

static func _name(slot: Dictionary) -> String:
	var key := str(slot.get("key", ""))
	return str(NAMES.get(key, slot.get("label", key)))


## What a link carries, as the spare modules' second line says it.
static func _carried(key: String) -> String:
	if key == "cables":
		return "Power in and out"
	var mode := str(TileViewData.CAPPED_MODES.get(key, key))
	var what := _goods_words(Catalog.infra(mode).get("good_types_tolerated", []))
	return what.substr(0, 1).to_upper() + what.substr(1)


## What a link carries and, for goods, how far they go on it in a turn at `level`, as a sentence.
static func _carries(key: String, level: int) -> String:
	if key == "cables":
		return "Carries power to and from the grid"
	var mode := str(TileViewData.CAPPED_MODES.get(key, key))
	var what := _goods_words(Catalog.infra(mode).get("good_types_tolerated", []))
	var reach := EconomyConfig.infra_range_for_level(mode, level)
	return ("Carries %s, %d tiles a turn" % [what, reach]) if reach > 0 else ("Carries %s" % what)


## A link's capacity at `level`: MW each way for cables, units a turn for the goods links.
static func _capacity(key: String, level: int) -> int:
	if key == "cables":
		# Power.tile_power_cap's figure for a tile with cables at `level`.
		var cap := float(EconomyConfig.CABLE_POWER_CAP.get(level, 0))
		return roundi(Modifiers.apply("transport_throughput", "cables", cap, {"mode": "cables"}))
	return roundi(TransportState.tile_mode_capacity(str(TileViewData.CAPPED_MODES.get(key, key)), level))


## A capacity for the spare modules' Capacity column.
static func _capacity_short(key: String, cap: int) -> String:
	if cap <= 0:
		return "No limit"
	return ("%s MW" % _count(cap)) if key == "cables" else ("%s a turn" % _count(cap))


## A capacity in words, for a tooltip.
static func _capacity_words(key: String, cap: int) -> String:
	return ("up to %s MW each way" % _count(cap)) if key == "cables" else ("up to %s units a turn" % _count(cap))


## The reach an upgrade adds, for its tooltip ("" when it adds none).
static func _reach_gain(mode: String, level: int, target: int) -> String:
	if mode == "":
		return ""
	var now := EconomyConfig.infra_range_for_level(mode, level)
	var then := EconomyConfig.infra_range_for_level(mode, target)
	return (" and reaches %d tiles a turn" % then) if then > now else ""


## The goods a link takes, in words, from the transport classes it tolerates.
static func _goods_words(classes: Array) -> String:
	var solids := classes.has("solid_heavy") or classes.has("solid_light") or classes.has("ultra_heavy")
	var liquids := classes.has("safe_liquid") or classes.has("liquid")
	var hazard := classes.has("hazard_liquid")
	var gas := classes.has("gas")
	if solids and hazard and gas:
		return "every good"
	var parts: Array[String] = []
	if solids:
		parts.append("solids")
	if hazard:
		parts.append("every liquid")
	elif liquids:
		parts.append("safe liquids")
	if gas:
		parts.append("gas")
	if parts.is_empty():
		return "nothing"
	if parts.size() == 1:
		return parts[0]
	return ", ".join(parts.slice(0, parts.size() - 1)) + " and " + parts[-1]


## Goods and their quantities in words ("5 Copper wiring and 2 Transformers"), for a tooltip.
static func _goods_list(goods: Dictionary) -> String:
	var parts: Array[String] = []
	for gid in goods:
		parts.append("%s %s" % [_count(int(goods[gid])), Catalog.get_display_name(str(gid))])
	if parts.size() <= 1:
		return "".join(parts)
	return ", ".join(parts.slice(0, parts.size() - 1)) + " and " + parts[-1]


static func _count(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


static func _money(v: float) -> String:
	return "£%s" % _count(roundi(v)) if is_equal_approx(v, roundf(v)) else "£%.2f" % v
