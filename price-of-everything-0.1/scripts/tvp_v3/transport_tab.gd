extends RefCounted
## Tile view v3: the Transport tab's body (docs/tile-view-ds2-plan.md §4.3 and §9), built into `pane` on each
## refresh while UiPrefs.use_tvp_v3 is on. With the switch off the v2 panel builds the tab itself.
## `panel` is the tile view (scripts/tile_info_panel_v2.gd): its tile, its signals and its helpers.
##
## The site's services, as the cabinet's concept has them, in one plastic case like Building Detail's
## diagnostics: one rack of modules, each the case's full width. Every link the tile has or can have shows
## here, always in view (the Buildings tab shows none). First the infrastructure built here, each a module:
## its emblem the card's full height, its name, its level on a drum and an Upgrade key, its load on a
## meter against capacity (cables: one meter, the larger of the power made and drawn against the cable's
## cap), the goods riding it, and a line only when something is wrong or a job runs; clicking the module
## opens the link. Then the infrastructure that can still be added, spare modules further down the rack, set
## out as a table: how many tiles it reaches, its throughput, what laying it takes, and a Build key. The
## only keys are Build and Upgrade; hovering a key lights its card (dot_card.gd): what building or
## raising the link costs and what it brings. HVDC, which no building
## provides yet, stays hidden. Building and raising links wait for Infrastructure Tendering, as the v2
## section always has: until then the links built here show read only, their Upgrade keys greyed, with a
## line saying so under them, and none can be added.
##
## One column grid runs through the case, the same in every state: the headings stand over the modules'
## left edge, and the emblems, the names, the drums and the keys line up in both groups; every meter's
## figure takes one fixed width, so the meters end together. The case's side screws keep clear of the
## headings and the modules' edges, and the case keeps clear of the body's scrollbar.
##
## Every figure comes from the engine: TileViewData.infrastructure_summary (state, load, capacity), Power's
## per tile figures for cables, BuildingWorks (level, the upgrade's quote and progress), TransportState (the
## goods on a link, its history over capacity and the overages it caused), Construction (a link being
## built and what laying one takes), EconomyConfig (a link's reach at a level), and the Build key's quote
## (scripts/tvp_v3/transport_quote.gd, the map's own pricing steps read without acting).

const Metrics := preload("res://scripts/ds2/metrics.gd")
const TileViewData := preload("res://scripts/tile_view_data.gd")
const Section := preload("res://scripts/bdp_v3_section.gd")
const Heading := preload("res://scripts/bdp_v3_heading.gd")
const Counter := preload("res://scripts/bdp_v3_counter.gd")
const Nine := preload("res://scripts/bdp_v3_nine.gd")
const Led := preload("res://scripts/bdp_v3_led.gd")
const Plate := preload("res://scripts/bdp_v3_plate.gd")
const UIFonts := preload("res://scripts/ui_fonts.gd")
const BuildingLevels := preload("res://scripts/building_levels.gd")
const Meter := preload("res://scripts/ds2/led_meter.gd")
const Key := preload("res://scripts/ds2/cream_key.gd")
const Emblem := preload("res://scripts/ds2/emblem_lamp.gd")
const Quote := preload("res://scripts/tvp_v3/transport_quote.gd")
const Tip := preload("res://scripts/ds2/dot_card.gd")
const Well := preload("res://scripts/ds2/good_well.gd")

## Building Detail's diagnostics module plate (layout.json diag_module): its shadow room and 9-slice corner.
const MODULE: Texture2D = preload("res://assets/ui/bdp_v3/diag_module.png")
const MODULE_MARGIN := 10.0 / 1.875
const MODULE_CORNER := 26.0 * 2.0 / 1.875
const MODULE_PAD := 10.0
## A spare module, not yet wired: the same plate, a shade duller.
const SPARE_TINT := Color(0.8, 0.8, 0.82)
const CARD_RIGHT := 2.0
const MODULE_GAP := 8
## The plastic case and its silver screws (layout.json diag_plastic, screw_silver), about this far apart.
const PLASTIC: Texture2D = preload("res://assets/ui/bdp_v3/diag_plastic.png")
const SCREW: Texture2D = preload("res://assets/ui/bdp_v3/screw_silver.png")
const SCREW_PITCH := 170.0
## The case's screws sit this far in from its edges, clear of modules DS2's plate padding in.
const CASE_SCREW_INSET := 7.0
## A card's emblem: the card's full height (a good's well), and no longer than this (the long pipes).
const EMBLEM_BOX := 100.0
## How far a side screw keeps from a heading's line or a module's edge (its radius and a little more),
## and how far it may move off its even spacing to find a clear place before it is left out.
const SCREW_CLEAR := 14.0
const SCREW_SHIFT := 48.0
## The room above the spare modules' heading, down the rack from the last built link.
const GROUP_GAP := 12
## The room kept between the case and the body's scrollbar while it shows, and under the case at the
## body's foot, so its edge and its shadow stay clear of both.
const RAIL_GAP := 6.0
const FOOT_GAP := 8
## Text: body 14 (IBM Plex Sans Medium, a row's own title semibold), captions 15 (Barlow Condensed SemiBold).
const BODY_PX := 14
const CAPTION_PX := 15
## The column grid, the same in every state: the gap between columns, the keys' scale (every key in the
## column is as wide as the widest, Upgrade latched with its lamp: key_width), the spare modules' Tile
## Distance and Throughput columns (at least as wide as their captions), and the meters' figure column, as
## wide as the widest figure a link at any level reads (a wider one, far over capacity, widens it).
const COL_GAP := 8
const KEY_SCALE := 1.0
const KEY_WORDS := ["Upgrade", "Build"]
const REACH_CAPTION := "Tile Distance"
const CAPACITY_CAPTION := "Throughput"
const REACH_W := 42.0
const CAPACITY_W := 70.0
const FIGURE_TEMPLATES := ["8,888 of 8,888 MW", "888 of 888/turn"]
## The gap between the lines of a module.
const BODY_GAP := 7
## The least width a wrapping sentence asks for.
const LINE_MIN_W := 160.0
## Names where the v2 grid had to abbreviate.
const NAMES := {"reinf_pipes": "Reinforced pipes"}
## A build card's note past the planning limit: the map charges half the fee again there
## (transport_quote.gd PLANNING_CHARGE); the materials a link takes don't change.
const PLANNING_NOTE := "Fee +50% past the planning limit"
## The goods on a link or needed to lay one, each in its well with its quantity in a pill (good_well.gd):
## their icons' side, how many show (four, or three and a count of the rest, fit the module's width), and
## the gap between wells, clear of each other's frames.
const GOOD_PX := Metrics.GOOD_ICON
const GOODS_SHOWN := 4
const GOOD_GAP := 14
## The room above and below a row of wells, past the lines' own gap, so a frame keeps clear of a meter's
## bezel or a module's edge.
const WELL_ROOM := 4
## The tile and the levels its drums last read, so a drum rolls only when a link's level changes.
const META_LEVELS := "tvp_transport_levels"
## Before Infrastructure Tendering: the line under the links built here, the note on a tile without any, and
## the reason on an Upgrade key's card.
const LOCKED_LINE := "New links and upgrades open with Infrastructure Tendering."
const LOCKED_EMPTY := "Links open with Infrastructure Tendering."
const LOCKED_REASON := "Opens with Infrastructure Tendering"


static func build(panel: Control, pane: VBoxContainer) -> void:
	var tile_id := str(panel.get("_current_tile_id"))
	var tile_data: Dictionary = panel.get("_current_tile_data")
	if tile_id == "":
		return
	# The research gating the v2 section has always had: in a logistics game the links are a tendered
	# capability. Until Infrastructure Tendering the links built here show read only and none can be added.
	var open := ResearchState.infrastructure_tendering_available()
	var near := near_share(panel)
	var links: Array = []
	var spare: Array = []
	for slot: Dictionary in TileViewData.infrastructure_summary(tile_id, tile_data):
		match str(slot.get("state", "")):
			"exists": links.append(link_state(tile_id, slot, near, open))
			"add":
				if open:
					spare.append(slot)
			# "unavailable": no building provides it (HVDC), so it stays hidden until one does.
	if links.is_empty() and not open:
		pane.add_child(_note(LOCKED_EMPTY))
	var memory: Dictionary = panel.get_meta(META_LEVELS, {}) if panel.has_meta(META_LEVELS) else {}
	var last: Dictionary = memory.get("levels", {}) if str(memory.get("tile", "")) == tile_id else {}
	var levels := {}
	if not links.is_empty() or not spare.is_empty():
		var case := _plastic_case()
		case.name = "TransportLinks"
		var content := case.get_child(0) as VBoxContainer
		content.add_theme_constant_override("separation", MODULE_GAP)
		var indent := 0.0
		if not links.is_empty():
			content.add_child(_heading_row("Infrastructure", false, indent))
		content.add_child(_rack(panel, tile_id, links, spare, indent, last, levels))
		if not open:
			content.add_child(_locked_line(indent))
		for l in case.find_children("*", "Label", true, false):
			_emboss(l)
		# The case keeps clear of the body's scrollbar while it shows, and its foot of the body's end.
		var row := HBoxContainer.new()
		row.name = "TransportRow"
		row.add_theme_constant_override("separation", 0)
		case.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(case)
		var gap := RailGap.new()
		row.add_child(gap)
		var scroll := panel.get("_body_scroll") as ScrollContainer
		if scroll != null:
			gap.watch(scroll.get_v_scroll_bar())
		pane.add_child(row)
		pane.add_child(_gap(FOOT_GAP))
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
## its meter ([caption, load, capacity, figure]), its tone, what is wrong with it, the overages it has
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
		"paid": 0.0, "riding": [], "near": near, "locked": not can_build,
	}
	# The load: cables carry power, each way up to the tile's cable cap, so their one meter reads the larger
	# of the power made and drawn against it; the goods links carry units.
	if key == "cables":
		var pcap := Power.tile_power_cap(tile_id)
		var worst := maxi(int(Power.tile_produced.get(tile_id, 0)), int(Power.tile_drawn.get(tile_id, 0)))
		if pcap > 0:
			s.capped = true
			s.share = float(worst) / float(pcap)
			s.meters = [["Used", worst, pcap, "%s of %s MW" % [_count(worst), _count(pcap)]]]
	elif bool(slot.get("capped", false)) and int(transit.get("cap", 0)) > 0:
		var cap := int(transit.get("cap", 0))
		var used := int(transit.get("used", 0))
		s.capped = true
		s.share = float(transit.get("pct", 0.0))
		s.meters = [["Carried", used, cap, "%s of %s/turn" % [_count(used), _count(cap)]]]
	s["tone"] = link_tone(float(s.share), near) if bool(s.capped) else "ok"

	# What is wrong with it, if anything: the words say what the lamp and the meter show.
	var link_key := "%s|%s" % [tile_id, mode]
	var share: float = s.share
	if not bool(s.capped):
		s.status = "No limit on what it carries."
	elif key == "cables":
		if share >= near:
			s.status = ("At its limit. " if share >= 1.0 else "Near its limit. ") \
				+ "Power over %s MW is cut." % _count(Power.tile_power_cap(tile_id))
			s.status_ink = _tone_ink(str(s.tone))
	else:
		var cap := int(transit.get("cap", 0))
		if share >= near:
			var l1 := float(EconomyConfig.TRANSPORT_LINK_CAP_BY_MODE.get(mode, 0))
			var times := "triple" if float(transit.get("used", 0)) > float(cap) + l1 else "double"
			s.status = ("Over capacity. " if share > 1.0 else "Near capacity. ") \
				+ "Goods over %s pay %s freight." % [_count(cap), times]
			s.status_ink = _tone_ink(str(s.tone))
		else:
			var turns_over := TransportState.link_turns_over(link_key)
			if turns_over > 0:
				s.status = "Over capacity in %d of the last %d turns." % [turns_over, TransportState.LINK_HISTORY_TURNS]
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
	s["target"] = int(quote.get("target_level", int(s.level) + 1))
	s["at_top"] = bool(quote.get("at_max", false)) or int(s.level) >= BuildingLevels.MAX_LEVEL
	return s


# ── The rack ──────────────────────────────────────────────────────────────────────────────────────

## One rack of modules, `indent` in from the case's edge: the links built here, then under their heading
## the links that can still be built.
static func _rack(panel: Control, tile_id: String, links: Array, spare: Array, indent: float, last: Dictionary,
		levels: Dictionary) -> Control:
	var card := _card(indent)
	card.name = "TransportRack"
	var list := card.get_child(0) as VBoxContainer
	var figure_w := _figure_width(links)
	for s: Dictionary in links:
		list.add_child(_link_module(panel, s, figure_w, last, levels))
	if not spare.is_empty():
		if not links.is_empty():
			list.add_child(_gap(GROUP_GAP))
		list.add_child(_heading_row("Add Infrastructure", true))
		var building: Dictionary = {}
		for project: Dictionary in Construction.projects_on_tile(tile_id):
			building[str(project.get("building_id", ""))] = project
		for slot: Dictionary in spare:
			var bd: Dictionary = slot.get("building_data", {})
			list.add_child(_spare_module(panel, tile_id, slot, building.get(str(bd.get("id", "")), {})))
	return card


# ── Links built here ──────────────────────────────────────────────────────────────────────────────


## One built link: its emblem, the card's full height; its name, its level on a drum and the key that raises it (whose
## card says what raising it costs and brings); its load against capacity; the goods on it; what is wrong,
## if anything. Clicking it opens the link.
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
	# The lamp stands level with the meter, the line it judges.
	# The emblem fills the card's height with no lamp: the meter says how loaded the link is.
	var emblem: Control = Emblem.new()
	var head_h := Key.height_for(KEY_SCALE)
	emblem.call("set_link", str(s.building_id), str(s.tone), Metrics.GOOD_ICON, false)
	emblem.call("fit_to", Metrics.GOOD_ICON, EMBLEM_BOX)
	row.add_child(emblem)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", BODY_GAP)
	row.add_child(body)

	# The name, as the spare modules have it; the level on a drum; the key that raises it.
	var head := HBoxContainer.new()
	head.name = "Head"
	head.custom_minimum_size.y = head_h
	head.add_theme_constant_override("separation", 6)
	body.add_child(head)
	var words := _name_words(title, key)
	words.name = "InfraName_%s" % key
	head.add_child(words)
	head.add_child(_caption("Level"))
	var drum: Control = Counter.new()
	drum.call("configure", 1, 0)
	drum.call("set_value", float(level), float(last[key]) if last.has(key) else NAN)
	levels[key] = level
	head.add_child(drum)
	head.add_child(_print("of %d" % BuildingLevels.MAX_LEVEL))
	head.add_child(_gap(COL_GAP - 6, true))
	var card := upgrade_card(s)
	head.add_child(_upgrade_key(panel, s, card))

	# The load against capacity, every figure in the widest one's width so the meters end together.
	for m: Array in s.meters:
		body.add_child(_meter_row(str(m[0]), float(m[1]), float(m[2]), str(m[3]), figure_w, float(s.near), float(s.share) > 1.0))
	var riding := _goods_row(s.riding)
	if riding != null:
		body.add_child(_wells_room(riding))
	if str(s.status) != "":
		body.add_child(_line(str(s.status), false, s.status_ink))
	if bool(s.upgrading):
		var left := int((s.quote as Dictionary).get("pending_turns_left", 0))
		body.add_child(_line("Level %d in %s." % [int(s.target), _turns(left)]))
	if float(s.paid) >= 0.005:
		body.add_child(_overages(float(s.paid)))

	# The whole module opens the link too, as the v2 cell did, and brightens its emblem under the pointer.
	module.mouse_filter = Control.MOUSE_FILTER_STOP
	module.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	module.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			panel.call("_on_infra_pressed", inst, "", ""))
	module.mouse_entered.connect(func() -> void: emblem.set("hot", true))
	module.mouse_exited.connect(func() -> void: emblem.set("hot", false))
	return module


## The key that raises a link's level. It says only Upgrade: its card says what the next level costs and
## brings. Red when the cash won't cover it; latched with its lamp lit while an upgrade runs; greyed at the
## top level, as Building Detail's Upgrade key is at its maximum, so every module keeps a key in the column.
static func _upgrade_key(panel: Control, s: Dictionary, card: Dictionary) -> Button:
	var key: String = s.key
	var up: Button = Key.make("InfraUpgrade_%s" % key, "Upgrade", "", key_width(), false, bool(s.upgrading), KEY_SCALE)
	Tip.attach(up, card)
	if bool(s.upgrading):
		return up
	if bool(s.upgradable):
		if not bool((s.quote as Dictionary).get("affordable", true)):
			up.set("title_ink", Key.RED_INK)
		up.pressed.connect(func() -> void: _open_upgrade(panel, s.instance))
		return up
	up.call("set_spent", true)
	return up


## The card for raising a built link: the next level's price, capacity, reach and time; the level it
## reaches while the upgrade runs; its figures at the top level; why it can't be raised otherwise.
static func upgrade_card(s: Dictionary) -> Dictionary:
	var key: String = s.key
	var mode: String = s.mode
	var level: int = s.level
	var target: int = s.target
	var quote: Dictionary = s.quote
	if bool(s.upgrading):
		var rows: Array = [{"caption": "Ready in", "value": _turns(int(quote.get("pending_turns_left", 0)))}]
		rows.append_array(_gain_rows(key, mode, level, target))
		return {"title": "Upgrading to level %d" % target, "tone": "warn", "rows": rows}
	if bool(s.upgradable):
		var paid := bool(quote.get("affordable", true))
		var rows: Array = [{"caption": "Cost", "value": _money(float(quote.get("cash_cost", 0.0))), "tone": "" if paid else "bad"}]
		rows.append_array(_gain_rows(key, mode, level, target))
		rows.append({"caption": "Time", "value": _turns(int(quote.get("duration", 0)))})
		var card := {"title": "Upgrade to level %d" % target, "rows": rows}
		if not paid:
			card.tone = "bad"
			card.notes = [{"text": "Not enough cash", "tone": "bad"}]
		return card
	var now: Array = [{"caption": "Level", "value": "%d of %d" % [level, BuildingLevels.MAX_LEVEL]}]
	now.append_array(_gain_rows(key, mode, level, level))
	if bool(s.at_top):
		return {"title": "Top level", "rows": now}
	if bool(s.get("locked", false)):
		return {"title": "Upgrade", "rows": now, "notes": [{"text": LOCKED_REASON, "tone": "warn"}]}
	var why := str(quote.get("reason", "It can't be raised here."))
	return {"title": "Upgrade", "tone": "bad", "rows": now, "notes": [{"text": why.trim_suffix("."), "tone": "bad"}]}


## A link's capacity and reach at `level` and at `target` (one figure when they match), for its card. Cables
## reach the grid, so they have no reach.
static func _gain_rows(key: String, mode: String, level: int, target: int) -> Array:
	var rows: Array = []
	var cap_now := _capacity(key, level)
	var cap_then := _capacity(key, target)
	var unit := " MW" if key == "cables" else "/turn"
	var caption := "Capacity" if key == "cables" else CAPACITY_CAPTION
	if cap_now <= 0 and cap_then <= 0:
		rows.append({"caption": caption, "value": "No limit"})
	elif cap_then != cap_now:
		rows.append({"caption": caption, "value": "%s → %s%s" % [_count(cap_now), _count(cap_then), unit]})
	else:
		rows.append({"caption": caption, "value": _count(cap_now) + unit})
	if mode != "":
		var reach_now := EconomyConfig.infra_range_for_level(mode, level)
		var reach_then := EconomyConfig.infra_range_for_level(mode, target)
		if reach_then != reach_now:
			rows.append({"caption": REACH_CAPTION, "value": "%d → %d" % [reach_now, reach_then]})
		elif reach_now > 0:
			rows.append({"caption": REACH_CAPTION, "value": "%d" % reach_now})
	return rows


## A meter's line: the meter and the figure it reads (red when the link is over capacity). `caption` names
## the meter's node.
static func _meter_row(caption: String, load_now: float, cap: float, figure: String, figure_w: float, near: float, over: bool) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
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
## quantity in a pill, most first; null when nothing rides it.
static func _goods_row(rows: Array) -> Control:
	var moving: Array = []
	for r: Dictionary in rows:
		if int(r.get("qty", 0)) > 0:
			moving.append(r)
	if moving.is_empty():
		return null
	moving.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("qty", 0)) > int(b.get("qty", 0)))
	var hb := _wells_row("GoodsOnLink", "Goods")
	var shown := mini(moving.size(), GOODS_SHOWN if moving.size() <= GOODS_SHOWN else GOODS_SHOWN - 1)
	for i in shown:
		var gid := str(moving[i].get("good_id", ""))
		hb.add_child(Well.make(gid, int(moving[i].get("qty", 0)), "on it this turn", GOOD_PX))
	if moving.size() > shown:
		hb.add_child(_print("and %d more" % (moving.size() - shown)))
	return hb


## A row of goods in their wells after its caption, the wells far enough apart that their frames stay clear
## of each other, with room above and below so they stay clear of the lines round them.
static func _wells_row(node_name: String, caption: String) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.name = node_name
	hb.add_theme_constant_override("separation", GOOD_GAP)
	hb.add_child(_caption(caption))
	return hb


## `row` with WELL_ROOM above and below it.
static func _wells_room(row: Control) -> MarginContainer:
	var room := MarginContainer.new()
	room.name = "%sRoom" % row.name
	room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	room.add_theme_constant_override("margin_top", WELL_ROOM)
	room.add_theme_constant_override("margin_bottom", WELL_ROOM)
	room.add_theme_constant_override("margin_left", 0)
	room.add_theme_constant_override("margin_right", 0)
	room.add_child(row)
	return room


# ── Links that can still be built ─────────────────────────────────────────────────────────────────

## One link that can be built: its emblem (no lamp: nothing is running to judge), its name, the tiles it
## reaches and its throughput at level 1 in the table's columns, its Build key, and under them what laying
## it takes, or how long it has left while it is being built (the key latched with its lamp lit). Hovering
## the key lights its card: what building it costs and brings. Named InfraCell_<key> for the tutorial,
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
	emblem.call("set_link", bid, "off", Metrics.GOOD_ICON, false)
	emblem.call("fit_to", Metrics.GOOD_ICON, EMBLEM_BOX)
	row.add_child(emblem)

	var main := VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", BODY_GAP)
	row.add_child(main)
	var top := HBoxContainer.new()
	top.name = "Head"
	top.custom_minimum_size.y = head_h
	top.add_theme_constant_override("separation", COL_GAP)
	main.add_child(top)
	top.add_child(_name_words(title, key))
	var reach := EconomyConfig.infra_range_for_level(mode, 1) if mode != "" else 0
	top.add_child(_cell(str(reach) if reach > 0 else "Grid", reach_width()))
	top.add_child(_cell(_capacity_short(key, _capacity(key, 1)), capacity_width()))

	# The key on the same line as the figures it would bring, in the keys' column.
	var q := Quote.quote(tile_id, bid) if project.is_empty() else {}
	var card := build_card(title, key, mode, bid, q, project)
	if not project.is_empty():
		var busy: Button = Key.make("InfraBuilding_%s" % key, "Build", "", key_width(), false, true, KEY_SCALE)
		Tip.attach(busy, card)
		top.add_child(busy)
		var waiting := str(project.get("status", "")) == Construction.STATUS_AWAITING_MATERIALS
		main.add_child(_line("Waiting for materials." if waiting else "Ready in %s." % _turns(int(project.get("turns_remaining", 0))),
			false, DS.PALETTE["WARN"] if waiting else DS.PALETTE["TEXT"]))
	else:
		top.add_child(_build_key(panel, slot, q, card, module))
		# What laying it takes, under the line.
		var needs := _needs_row(tile_id, bid)
		if needs != null:
			main.add_child(_wells_room(needs))
	return module


## The Build key. It says only Build: its card says what the press spends and what the link brings. Red
## when the map would refuse it or the cash won't cover it (its card says why); never disabled, since the
## map has the last word, as with the v2 cell.
static func _build_key(panel: Control, slot: Dictionary, q: Dictionary, card: Dictionary, module: Control) -> Button:
	var key := str(slot.get("key", ""))
	var b: Button = Key.make("InfraBuild_%s" % key, "Build", "", key_width(), false, false, KEY_SCALE)
	if not bool(q.ok) or not bool(q.affordable):
		b.set("title_ink", Key.RED_INK)
	Tip.attach(b, card)
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


## The card for building a link: what the press spends (the fee, any land it buys, any materials it
## orders, from the quote), its capacity, reach and time, and the goods it takes with how they come; why
## the map would refuse it; how long is left while it is being built.
static func build_card(title: String, key: String, mode: String, bid: String, q: Dictionary, project: Dictionary) -> Dictionary:
	var gains := _gain_rows(key, mode, 1, 1)
	var goods: Dictionary = Construction.requirements_for(bid) if bid != "" else {}
	if not project.is_empty():
		var waiting := str(project.get("status", "")) == Construction.STATUS_AWAITING_MATERIALS
		var rows: Array = []
		if not waiting:
			rows.append({"caption": "Ready in", "value": _turns(int(project.get("turns_remaining", 0)))})
		rows.append_array(gains)
		var card := {"title": "Building %s" % title, "tone": "warn", "rows": rows}
		if waiting:
			card.notes = [{"text": "Waiting for materials", "tone": "warn"}]
		return card
	var card := {"title": "Build %s" % title, "rows": [], "notes": [], "goods": goods, "goods_caption": "Needs"}
	var turns := int(q.get("turns", 0))
	var time := {"caption": "Time", "value": _turns(turns) if turns > 0 else "At once"}
	match str(q.materials):
		"order": card.goods_note = "Ordered"
		"ship": card.goods_note = "Shipped in"
		_: card.goods_note = "On site" if bool(q.ok) else ""
	if not bool(q.ok):
		# What it would cost once the reason is dealt with, in red: the key can't spend it now.
		card.tone = "bad"
		card.rows.append({"caption": "Cost", "value": _money(float(q.total)), "tone": "bad"})
		if int(q.get("land_short", 0)) > 0:
			card.rows.append({"caption": "Land", "value": "%d needed" % int(q.land_short), "tone": "bad"})
		card.rows.append_array(gains)
		card.rows.append({"caption": "Carries", "value": _carried(key)})
		card.rows.append(time)
		if bool(q.planning):
			card.notes.append({"text": PLANNING_NOTE, "tone": "warn"})
		card.notes.append({"text": str(q.refusal), "tone": "bad"})
		return card
	var paid := bool(q.affordable)
	card.rows.append({"caption": "Cost", "value": _money(float(q.total)), "tone": "" if paid else "bad"})
	if int(q.land_units) > 0:
		card.rows.append({"caption": "Land", "value": "%d to buy" % int(q.land_units)})
	card.rows.append_array(gains)
	card.rows.append({"caption": "Carries", "value": _carried(key)})
	card.rows.append(time)
	if bool(q.planning):
		card.notes.append({"text": PLANNING_NOTE, "tone": "warn"})
	if not paid:
		card.tone = "bad"
		card.notes.append({"text": "Not enough cash", "tone": "bad"})
	return card


## A link's name, filling the room its line leaves. What it carries is on its Build key's card.
static func _name_words(title: String, _key: String) -> VBoxContainer:
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", 0)
	words.add_child(_print(title, true))
	return words


## The line under the links built here before Infrastructure Tendering, in the modules' column.
static func _locked_line(indent: float) -> MarginContainer:
	var room := MarginContainer.new()
	room.name = "TransportLocked"
	room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	room.add_theme_constant_override("margin_left", roundi(indent))
	room.add_theme_constant_override("margin_right", roundi(CARD_RIGHT + MODULE_PAD))
	room.add_theme_constant_override("margin_top", 2)
	room.add_theme_constant_override("margin_bottom", 2)
	room.add_child(_line(LOCKED_LINE))
	return room


## A figure in one of the spare modules' columns, centred under its caption.
static func _cell(text: String, width: float) -> Label:
	var l := _print(text)
	l.custom_minimum_size.x = width
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## What laying a link takes (Construction.requirements_for), as goods in wells with their quantities, each
## saying on hover how many are on the tile; null when it takes none.
static func _needs_row(tile_id: String, building_id: String) -> Control:
	var reqs: Dictionary = Construction.requirements_for(building_id) if building_id != "" else {}
	if reqs.is_empty():
		return null
	var hb := _wells_row("Needs", "Needs")
	for gid in reqs:
		var have := Stockpile.get_at_tile(tile_id, str(gid))
		hb.add_child(Well.make(str(gid), int(reqs[gid]), "to lay it, %s on this tile" % _count(have), GOOD_PX))
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
	for pair in [[REACH_CAPTION, reach_width()], [CAPACITY_CAPTION, capacity_width()]]:
		var c := _caption(str(pair[0]))
		c.custom_minimum_size.x = float(pair[1])
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.size_flags_vertical = Control.SIZE_SHRINK_END
		hb.add_child(c)
	# The rest of the row: the key's column and the module's right margin.
	hb.add_child(_gap(key_width() + MODULE_PAD, true))
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
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		case.add_theme_constant_override(side, Metrics.PLATE_PAD)
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
	var lo := Vector2(CASE_SCREW_INSET, CASE_SCREW_INSET)
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


## A raised module in the plastic case, as each of Building Detail's diagnostics rows is: a building card, at
## least DS2's card height (the Buildings tab's cards are the same).
static func _module() -> PanelContainer:
	var module: PanelContainer = Tip.TipPanel.new()
	module.custom_minimum_size.y = Metrics.CARD_H
	var pad := StyleBoxEmpty.new()
	pad.content_margin_left = MODULE_PAD
	pad.content_margin_right = MODULE_PAD
	pad.content_margin_top = Metrics.CARD_PAD_Y
	pad.content_margin_bottom = Metrics.CARD_PAD_Y
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


## What a link carries, as the spare modules' second line and the name key's card say it, short enough
## for the table's column ("Safe liquids, gas").
static func _carried(key: String) -> String:
	if key == "cables":
		return "Power in and out"
	var mode := str(TileViewData.CAPPED_MODES.get(key, key))
	var what := _goods_words(Catalog.infra(mode).get("good_types_tolerated", []))
	return what.substr(0, 1).to_upper() + what.substr(1)


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
	return ("%s MW" % _count(cap)) if key == "cables" else ("%s/turn" % _count(cap))


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
		parts.append("all liquids")
	elif liquids:
		parts.append("safe liquids")
	if gas:
		parts.append("gas")
	if parts.is_empty():
		return "nothing"
	return ", ".join(parts)


## The spare modules' Tile Distance and Throughput columns: their set width, or their caption's when wider.
static func reach_width() -> float:
	return maxf(REACH_W, ceilf(Plate.FONT_SEMI.get_string_size(REACH_CAPTION.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_PX).x))


static func capacity_width() -> float:
	return maxf(CAPACITY_W, ceilf(Plate.FONT_SEMI.get_string_size(CAPACITY_CAPTION.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_PX).x))


## Every key in the column is this wide: the widest word a key says, latched with its lamp.
static func key_width() -> float:
	var w := 0.0
	for word: String in KEY_WORDS:
		w = maxf(w, Key.width_for(word, "", false, true, KEY_SCALE))
	return w


static func _turns(n: int) -> String:
	return "%d turn%s" % [n, "" if n == 1 else "s"]


static func _count(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


static func _money(v: float) -> String:
	return "£%s" % _count(roundi(v)) if is_equal_approx(v, roundf(v)) else "£%.2f" % v


## The room kept at the case's right while the body's scrollbar shows, so the case's edge stays clear of
## the rail; none when it hides. It follows the bar as it shows and hides (the connection goes with it).
class RailGap extends Control:
	func _init() -> void:
		name = "RailGap"
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func watch(bar: ScrollBar) -> void:
		bar.visibility_changed.connect(_follow.bind(bar))
		_follow(bar)

	func _follow(bar: ScrollBar) -> void:
		custom_minimum_size.x = RAIL_GAP if bar.visible else 0.0
