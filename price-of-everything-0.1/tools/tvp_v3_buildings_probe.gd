extends Node
## Tile view v3's Buildings tab (scripts/tvp_v3/buildings_tab.gd), checked without a window: the names the
## tutorial and the tests reach for, what a click on a card opens, the port in its own case above your
## buildings (on screen with other companies' drawer shut, for the tutorial's port step too; yours reads
## as your buildings do), the drawer's key counting other companies' buildings only (never the port, never
## infrastructure), the figures (a stalled building makes nothing, the port's price in the house money
## format, the seven-segment screens for money only, a good's quantity only ever the pill on its icon, the
## drums for turns only), the fold of groups kept across rebuilds, the construction column, the width
## discipline, nothing lying over anything else (cases, screws, keys, the scroll rail) and the text rules
## (white on the dark cases, no text under 12 px, no dashes, semicolons or middle dots), plus how long a
## rebuild takes. Also: every figure in your case stands in one of two columns, a press on Cancel through
## the real input path cancels without opening the project, the hover readouts say the engine's sentence,
## a stall with no row of its own is named in the words, groups are named as their members are, and the
## lifted cover stays inside the port's module.
##   Godot --headless --path . res://tools/tvp_v3_buildings_probe.tscn --quit-after 30000
## Prints [BL_CHECK] PASS / FAIL lines, then "[BL_CHECK] N passed, M failed"; exits 1 on any failure.

const Readings := preload("res://scripts/tvp_v3/buildings_readings.gd")
const Drum := preload("res://scripts/ds2/drum_figure.gd")
const GuardKey := preload("res://scripts/ds2/guard_key.gd")
const MoneyFigure := preload("res://scripts/ds2/money_figure.gd")
const BuildingReadout := preload("res://scripts/building_readout.gd")
const TutorialDetectors := preload("res://scripts/tutorial/tutorial_detectors.gd")
const Parts := preload("res://scripts/tvp_v3/buildings_parts.gd")
const Section := preload("res://scripts/bdp_v3_section.gd")
const Led := preload("res://scripts/bdp_v3_led.gd")

const TILE := "tile_5_10"
const SOLO_TILE := "tile_6_1"
const BIG_TILE := "tile_6_10"
const FEATURE_TILE := "tile_16_1"

var _wm: Node
var _panel: Control
var _passed := 0
var _failed := 0


func _ready() -> void:
	_wm = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_wm)
	await _frames(120)
	MatchState.money = 80000.0
	for _i in 3:
		BuildingState.add_building("b_007", "r_009", TILE, MatchState.LOCAL_PLAYER)
	BuildingState.add_building("b_007", "r_003", TILE, MatchState.LOCAL_PLAYER)
	BuildingState.add_building("b_025", "r_037", TILE, MatchState.LOCAL_PLAYER)
	var solo_iid := str(BuildingState.add_building("b_007", "r_009", SOLO_TILE, MatchState.LOCAL_PLAYER))
	for _i in 10:
		BuildingState.add_building("b_007", "r_009", BIG_TILE, MatchState.LOCAL_PLAYER)
	for _i in 2:
		BuildingState.add_building("b_025", "r_037", BIG_TILE, MatchState.LOCAL_PLAYER)
	Stockpile.add(TILE, str(Catalog.get_good_by_internal_name("steel").get("id", "")), 40)
	Stockpile.add(TILE, str(Catalog.get_good_by_internal_name("copper_wiring").get("id", "")), 40)
	TurnManager.fast_mode = true
	DecisionState.auto_resolve = true
	for _i in 2:
		TurnManager.commit_turn()
		if TurnManager.is_resolving:
			await TurnManager.turn_resolution_completed
	var project := Construction.start_on_tile("b_025", "r_037", TILE)
	if Construction.construction_projects.has(project):
		var waiting: Dictionary = (Construction.construction_projects[project] as Dictionary).duplicate(true)
		var wid := BuildingState.reserve_instance_id("b_007")
		waiting["instance_id"] = wid
		waiting["building_id"] = "b_007"
		waiting["recipe_id"] = "r_009"
		waiting["status"] = Construction.STATUS_AWAITING_MATERIALS
		waiting["turns_remaining"] = 12
		Construction.construction_projects[wid] = waiting
	# Infrastructure on a tile with the land's own features: another company's road and your cable. Neither
	# is the Buildings tab's (they are Transport's).
	var infra_iids: Array = [str(BuildingState.add_building("b_005", "", FEATURE_TILE, "npc_probe_roads")),
		str(BuildingState.add_building("b_006", "", FEATURE_TILE, MatchState.LOCAL_PLAYER))]

	_panel = _wm.get("info_panel")
	if _panel == null:
		_panel = _wm.find_child("TileInfoPanel", true, false)
	UiPrefs.set_use_tvp_v3(true)
	await _frames(4)

	await _open(TILE)
	_check_contracts()
	_check_port_price()
	_check_text(TILE)
	_check_figures(TILE)
	await _check_overlaps(TILE + " as first seen")
	await _check_fold()
	await _check_member_words()
	_check_construction()
	await _check_port_step()
	await _check_width()
	await _check_columns()
	_check_tips()
	await _check_port_mine()
	await _open(SOLO_TILE)
	await _check_solo_click(solo_iid)
	_check_paused(solo_iid)
	await _open(BIG_TILE)
	_check_stalled()
	_check_text(BIG_TILE)
	_check_figures(BIG_TILE)
	await _check_overlaps(BIG_TILE)
	await _open(FEATURE_TILE)
	_check_features()
	_check_infrastructure_out(FEATURE_TILE, infra_iids)
	await _check_overlaps(FEATURE_TILE)
	await _open(_empty_tile())
	_ok(_find("BLNoneOfYours") != null and _find("TilePort") == null and _find("OtherCompanies") == null,
		"an empty tile: Build and Buy, and your empty case only")
	await _check_overlaps("the empty tile")
	_check_group_words()
	await _timings()
	await _check_hover_readout()
	await _check_cancel_press()

	UiPrefs.set_use_tvp_v3(false)
	print("[BL_CHECK] %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


# --- checks --------------------------------------------------------------------------------

func _check_contracts() -> void:
	_ok(_find("BLBuildButton") is Button, "BLBuildButton is a Button")
	_ok(_find("BLBuyBuildingsButton") is Button, "BLBuyBuildingsButton is a Button")
	var build := _find("BLBuildButton") as Button
	_ok(build != null and not build.pressed.get_connections().is_empty(), "BLBuildButton is wired")
	_ok(_find("PortBuildingCard") != null, "PortBuildingCard exists on the port tile")
	_ok(_find("PortBuyButton") != null, "PortBuyButton exists on the port tile")
	var drawer := _find("Drawer") as Control
	_ok(drawer != null and not drawer.visible, "other companies' drawer starts shut")
	_ok(_find("PlayerBuildingsOnlyCheckbox") == null, "the 'your buildings only' checkbox is retired")
	var head := _find("BuildingCard_b_007_r_009")
	_ok(head != null and head.name == "BuildingCard_b_007_r_009", "BuildingCard_b_007_r_009 names the motor group's head")
	# The port: its own case, right under the actions, on screen with the drawer shut, never in the drawer.
	var port_case := _find("TilePort") as Control
	var card := _find("PortBuildingCard") as Control
	var others := _find("OtherCompanies")
	var parts: Array = port_case.get_parent().get_children() if port_case != null else []
	_ok(port_case != null and card != null and port_case.is_ancestor_of(card) and card.is_visible_in_tree(),
		"the port stands in its own case, on screen with the drawer shut")
	_ok(parts.size() > 2 and parts[0].name == "BLActions" and parts[1] == port_case and parts[2].name == "YourBuildings",
		"the port's case stands between the actions and your buildings")
	_ok(others == null or others.find_child("PortBuildingCard", true, false) == null, "the port is not in other companies' drawer")
	var heading := port_case.find_child("Heading", true, false) if port_case != null else null
	var raised := heading.get_child(0) if heading != null and heading.get_child_count() > 0 else null
	_ok(raised != null and str(raised.get("text")).to_upper() == "SEAPORT", "the port's case is headed Seaport, as the status line names it")
	# The drawer's key counts other companies' buildings only: not the port, not infrastructure, no "more".
	var want := 0
	for b: Dictionary in BuildingState.get_buildings_on_tile(TILE):
		var bid := str(b.get("building_id", ""))
		if bid == "b_004" or BuildingState.is_player_owned(b) or bid == "b_031" or BuildingState.is_land_owned_wood(b):
			continue
		if str(Catalog.get_building(bid).get("category", "")).to_lower() == "infrastructure":
			continue
		want += 1
	var key := _find("OtherCompaniesKey")
	var said := str(key.get("summary")) if key != null else ""
	var expect := "%d other companies' buildings" % want if want > 1 else "1 other company's building"
	_ok(said == expect, "the drawer's key says '%s' (%s)" % [expect, said])
	_ok(not said.to_lower().contains("port") and not said.contains("more"), "the drawer's key names no port and no 'more'")


func _check_port_price() -> void:
	var port: Dictionary = {}
	for b: Dictionary in BuildingState.get_buildings_on_tile(TILE):
		if str(b.get("building_id", "")) == "b_004":
			port = b
	var want := MoneyFigure.led(float(BuildingReadout.buy_price(port)))
	var price := _find("PortPrice")
	var led: Control = price.get_node_or_null("Led") if price != null else null
	var suffix: Label = price.get_node_or_null("Suffix") if price != null else null
	_ok(led != null and str(led.call("figure")) == str(want.figure), "port price LED reads %s (house format)" % str(want.figure))
	_ok(str(want.suffix) == "" or (suffix != null and suffix.text == str(want.suffix)), "port price prints %s after the screen" % str(want.suffix))


## Groups start folded; a click on the head opens them, the choice survives a rebuild, a second click folds.
func _check_fold() -> void:
	var head := _find("BuildingCard_b_007_r_009") as Control
	var feed := _feed_of(head)
	_ok(feed != null and not feed.visible, "a group starts folded")
	_click(head)
	_ok(feed != null and feed.visible, "a click on the head opens the group")
	_panel.call("_refresh_pane", "bl")
	await _frames(2)
	head = _find("BuildingCard_b_007_r_009") as Control
	feed = _feed_of(head)
	_ok(feed != null and feed.visible, "an open group stays open across a rebuild")
	# The feed holds the cable, then the list of members (same-named siblings are renamed, so count them).
	var members: Array = feed.get_child(1).get_children() if feed != null and feed.get_child_count() > 1 else []
	_ok(members.size() == 3, "the open group shows its 3 members (%d)" % members.size())
	var quiet := 0
	var pilled := 0
	for m: Node in members:
		if m.find_child("Qty", true, false) != null and m.find_child("Drum", true, false) == null:
			pilled += 1
		if m.find_child("Words", true, false) == null:
			quiet += 1
			_ok((m as Control).get_combined_minimum_size().y <= Parts.MEMBER_WELL_PX + 2.0 * Parts.COMPACT_PAD_Y + 1.0,
				"a quiet member is one line, as tall as its well (%.1f)" % (m as Control).get_combined_minimum_size().y)
	_ok(pilled == 3, "each member shows its output as its good with the quantity pill, no drum (%d of 3)" % pilled)

	_ok(quiet == 3, "members that say what the group says don't repeat it (%d of 3 quiet)" % quiet)
	_click(head)
	_ok(not feed.visible and not bool((_panel.get_meta("tvp_bl_open_groups", {}) as Dictionary).get("b_007|r_009", true)),
		"a second click folds it and the fold is kept")


## A member with words of its own: they run under its line, clear of the well's frame (it reaches about
## 5 px below the good's tile; the words' letters start about 4 px under their label's top).
func _check_member_words() -> void:
	var tab: GDScript = load("res://scripts/tvp_v3/buildings_tab.gd")
	var b: Dictionary = {}
	for x: Dictionary in BuildingState.get_buildings_on_tile(TILE):
		if str(x.get("recipe_id", "")) == "r_009" and BuildingState.is_player_owned(x):
			b = x
	var holder := VBoxContainer.new()
	holder.custom_minimum_size = Vector2(480, 0)
	add_child(holder)
	var m: Control = tab.call("_member_module", _panel, b, Readings.reading(b), {"cost": {}},
		{"fig_w": 56.0, "cost_w": 0.0, "digits": 0}, "Motor - Z", ["starts next turn", "not drawing power yet"])
	holder.add_child(m)
	await _frames(3)
	var said := m.find_child("Words", true, false) as Control
	var well := m.find_child("IconWell", true, false) as Control
	var gap := said.get_global_rect().position.y + 4.0 - well.get_global_rect().end.y if said != null and well != null else -99.0
	_ok(gap >= 5.0, "a member's own words stand clear of its well's frame (%.1f px under the tile)" % gap)
	holder.queue_free()


func _check_construction() -> void:
	var rows := _pane().find_children("ConstructionModule_*", "", true, false)
	_ok(rows.size() == 2, "two construction rows (%d)" % rows.size())
	var widths: Array = []
	for r: Node in rows:
		var turns := r.find_child("Turns", true, false) as Control
		var drum := r.find_child("Drum", true, false) as Control
		if turns != null:
			widths.append(snappedf(turns.size.x, 0.5))
		_ok(drum != null and absf(drum.size.y - Drum.led_height()) < 0.6, "the turns drum stands as tall as an LED screen")
		_ok(r.find_child("CancelConstruction_*", true, false) is Button, "Cancel sits beside the turns")
	_ok(widths.size() == 2 and widths[0] == widths[1], "the turns column is one width down the case %s" % str(widths))


## The tutorial's port step (it spotlights PortBuildingCard) finds the port on screen without opening other
## companies' drawer, whether the step starts after the tab was built or the tab is built during it, and
## the port's Buy is disabled during the tutorial.
func _check_port_step() -> void:
	_panel.set_meta("tvp_bl_others_open", false)
	_panel.call("_refresh_pane", "bl")
	await _frames(2)
	var saved := {"active": Tutorial.active, "steps": Tutorial.get("_steps"), "index": Tutorial.get("_index")}
	Tutorial.set("_steps", [{"id": "probe_port", "spotlight": {"kind": "node_name", "ref": "PortBuildingCard"}}])
	Tutorial.set("_index", 0)
	Tutorial.active = true
	Tutorial.step_changed.emit("probe_port")
	await _frames(2)
	var card := _find("PortBuildingCard") as Control
	var drawer := _find("Drawer") as Control
	_ok(card != null and card.is_visible_in_tree() and drawer != null and not drawer.visible,
		"PortBuildingCard is on screen for the step started after the build, the drawer left shut")
	_panel.call("_refresh_pane", "bl")
	await _frames(2)
	card = _find("PortBuildingCard") as Control
	_ok(card != null and card.is_visible_in_tree(), "PortBuildingCard is on screen when the tab is built during the step")
	var guard := _find("PortBuyButton")
	_ok(guard != null and bool(guard.get("disabled")), "the port's Buy is disabled during the tutorial")
	Tutorial.active = bool(saved.active)
	Tutorial.set("_steps", saved.steps)
	Tutorial.set("_index", saved.index)
	Tutorial.step_changed.emit("")
	_panel.call("_refresh_pane", "bl")
	await _frames(2)
	_ok(not bool(_panel.get_meta("tvp_bl_others_open", false)), "the step stored no drawer state")


## With the drawer and the group open, no part is wider than the body (docs/ds2-theme.md §7.12).
func _check_width() -> void:
	_panel.set_meta("tvp_bl_others_open", true)
	var groups: Dictionary = _panel.get_meta("tvp_bl_open_groups", {})
	groups["b_007|r_009"] = true
	_panel.set_meta("tvp_bl_open_groups", groups)
	_panel.call("_refresh_pane", "bl")
	await _frames(3)
	var scroll := _panel.find_child("BodyScroll", true, false) as ScrollContainer
	var pane := _pane()
	var room := scroll.size.x - scroll.get_v_scroll_bar().size.x if scroll != null else 0.0
	_ok(pane != null and pane.get_combined_minimum_size().x <= room,
		"body min width %.0f fits %.0f" % [pane.get_combined_minimum_size().x if pane != null else -1.0, room])
	_panel.set_meta("tvp_bl_others_open", false)
	groups["b_007|r_009"] = false
	_panel.set_meta("tvp_bl_open_groups", groups)


## With the group and the drawer open: the wells, the members' drums and the projects' turns share one centre
## line, the cost screens and Cancel another; the head is named as its members are, without their letter;
## a member's own words are whole.
func _check_columns() -> void:
	_panel.set_meta("tvp_bl_others_open", true)
	var groups: Dictionary = _panel.get_meta("tvp_bl_open_groups", {})
	groups["b_007|r_009"] = true
	_panel.set_meta("tvp_bl_open_groups", groups)
	_panel.call("_refresh_pane", "bl")
	await _frames(3)
	var case := _find("YourBuildings") as Control
	var figs: Array = []
	var costs: Array = []
	for n: Node in case.find_children("*", "", true, false):
		var c := n as Control
		if c == null or not c.is_visible_in_tree():
			continue
		if c.name == "Outputs" or c.name == "Turns":
			figs.append(snappedf(c.get_global_rect().get_center().x, 0.5))
		elif c.name == "Cost" or str(c.name).begins_with("CancelConstruction_"):
			costs.append(snappedf(c.get_global_rect().get_center().x, 0.5))
	var one := func(xs: Array) -> bool:
		return xs.size() > 1 and xs.max() - xs.min() <= 0.5
	_ok(one.call(figs), "wells, drums and turns stand on one centre line %s" % str(figs))
	_ok(one.call(costs), "cost screens and Cancel stand on one centre line %s" % str(costs))
	var head := _find("BuildingCard_b_007_r_009") as Control
	var title := head.find_child("Title", true, false) as Label if head != null else null
	_ok(title != null and title.text == "Industrial Goods Factory - Motor", "the group is named as its members are: %s" % (title.text if title != null else ""))
	var cut := 0
	for w: Node in case.find_children("Words", "Label", true, false):
		if (w as Label).text.contains(" more"):
			cut += 1
	_ok(cut == 0, "no member's words are cut short (%d)" % cut)
	_panel.set_meta("tvp_bl_others_open", false)
	groups["b_007|r_009"] = false
	_panel.set_meta("tvp_bl_open_groups", groups)
	_panel.call("_refresh_pane", "bl")
	await _frames(2)


## A module's hover is Building Detail's readout with its worst check in the engine's words; keys have one too.
func _check_tips() -> void:
	_ok(_find("ReadoutSlot") == null, "no readout stands at the case's foot")
	var head := _find("BuildingCard_b_007_r_009") as Control
	var tip: Control = head.call("_make_custom_tooltip", head.tooltip_text) if head != null else null
	var readout := tip.find_child("HoverReadout", true, false) if tip != null else null
	_ok(readout != null and str(readout.call("shown_name")).contains(": ") and str(readout.call("shown_detail")) != "",
		"a head's hover is a readout: %s / %s" % [str(readout.call("shown_name")) if readout != null else "", str(readout.call("shown_detail")) if readout != null else ""])
	if tip != null:
		tip.free()
	var cancel := _pane().find_child("CancelConstruction_*", true, false) as Control
	var ctip: Control = cancel.call("_make_custom_tooltip", cancel.tooltip_text) if cancel != null else null
	var cr := ctip.find_child("HoverReadout", true, false) if ctip != null else null
	_ok(cr != null and str(cr.call("shown_name")).begins_with("Cancel"), "Cancel's hover says what it refunds")
	if ctip != null:
		ctip.free()
	var bare := 0
	for n: Node in _pane().find_children("*", "PanelContainer", true, false):
		var m := n as Control
		if m.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND and m.tooltip_text == "":
			bare += 1
	_ok(bare == 0, "every module has a hover readout (%d without)" % bare)


## Your own port stands in the same case and reads as your buildings do: its lamp and words, no price or Buy.
func _check_port_mine() -> void:
	var port: Dictionary = {}
	for b: Dictionary in BuildingState.get_buildings_on_tile(TILE):
		if str(b.get("building_id", "")) == "b_004":
			port = b
	if port.is_empty():
		_ok(false, "a port on %s" % TILE)
		return
	var owner := str(port.get("owner", ""))
	port["owner"] = MatchState.LOCAL_PLAYER
	_panel.call("_refresh_pane", "bl")
	await _frames(3)
	var case := _find("TilePort") as Control
	var card := _find("PortBuildingCard") as Control
	var words := card.find_child("Words", true, false) as Label if card != null else null
	_ok(case != null and card != null and case.is_ancestor_of(card) and card.find_child("BuildingLamp", true, false) != null
		and words != null and words.text != "" and _find("PortBuyButton") == null,
		"your port stands in its own case with its lamp and words, no Buy: %s" % (words.text if words != null else ""))
	var yours := _find("YourBuildings")
	_ok(yours != null and yours.find_child("PortBuildingCard", true, false) == null, "your port is not listed among your buildings")
	port["owner"] = owner
	_panel.call("_refresh_pane", "bl")
	await _frames(2)


## Infrastructure is the Transport tab's: none of it is shown or counted here, yours or another company's.
func _check_infrastructure_out(tile: String, iids: Array) -> void:
	var shown := 0
	for n: Node in _pane().find_children("*", "", true, false):
		for iid: String in iids:
			if iid != "" and str(n.name).contains(iid):
				shown += 1
	_ok(shown == 0, "%s: no infrastructure is shown (%d)" % [tile, shown])
	var mine_listed := 0
	var yours := _find("YourBuildings")
	if yours != null:
		mine_listed = yours.find_children("BuildingCard_b_006*", "", true, false).size()
	_ok(mine_listed == 0 and _find("BLNoneOfYours") != null, "%s: your cable is not one of your buildings" % tile)
	_ok(_find("OtherCompanies") == null, "%s: another company's road opens no drawer and is not counted" % tile)


## The seven-segment screens show money only (a unit cost, the port's price); a drum counts turns only; a
## good's quantity is only ever the pill on its icon.
func _check_figures(tile: String) -> void:
	var stray_led := 0
	var stray_drum := 0
	var pills := 0
	var bare_pills := 0
	for n: Node in _pane().find_children("*", "", true, false):
		if n.get_script() == Led:
			if not (_has_ancestor_named(n, "Money") or _has_ancestor_named(n, "PortPrice")):
				stray_led += 1
		elif n.get_script() == Drum:
			if not _has_ancestor_named(n, "Turns"):
				stray_drum += 1
		elif n.name == "Qty":
			pills += 1
			if n.get_parent() == null or n.get_parent().find_child("IconWell", false, false) == null:
				bare_pills += 1
	_ok(stray_led == 0, "%s: seven-segment screens show money only (%d elsewhere)" % [tile, stray_led])
	_ok(stray_drum == 0, "%s: drums count turns only (%d elsewhere)" % [tile, stray_drum])
	_ok(pills > 0 and bare_pills == 0, "%s: every quantity is a pill on its good's icon (%d pills, %d off an icon)" % [tile, pills, bare_pills])


func _has_ancestor_named(n: Node, what: String) -> bool:
	var up := n.get_parent()
	while up != null and up != _pane():
		if up.name == what:
			return true
		up = up.get_parent()
	return false


## Nothing lies over anything else. What each render draws past its control, from the renders' alpha: the
## plastic case 3 px up and left and 7.5 px down and right (its shadow), the steel frame 1.1 and 6.6, a
## module 1.3 and 5.3; a screw's head is 8 px across. Checked: the body's parts against each other and the
## scroll rail; in every case, each screw against the modules, keys and headings it holds.
func _check_overlaps(tag: String) -> void:
	_panel.set_meta("tvp_bl_others_open", true)
	var groups: Dictionary = _panel.get_meta("tvp_bl_open_groups", {})
	var was := groups.duplicate()
	for k: String in ["b_007|r_009", "b_025|r_037", "b_007|r_003"]:
		groups[k] = true
	_panel.set_meta("tvp_bl_open_groups", groups)
	for pass_open in [false, true]:
		_panel.set_meta("tvp_bl_others_open", pass_open)
		_panel.call("_refresh_pane", "bl")
		await _frames(4)
		var body := _pane().find_child("Parts", true, false) as Control
		var scroll := _panel.find_child("BodyScroll", true, false) as ScrollContainer
		var bar := scroll.get_v_scroll_bar() if scroll != null else null
		var drawn: Array = []
		for c: Node in (body.get_children() if body != null else []):
			var ctl := c as Control
			if ctl != null and ctl.visible:
				drawn.append([ctl.name, _drawn(ctl)])
		var hits: Array = []
		for i in drawn.size():
			for j in range(i + 1, drawn.size()):
				if (drawn[i][1] as Rect2).intersects(drawn[j][1] as Rect2):
					hits.append("%s over %s" % [drawn[i][0], drawn[j][0]])
		if bar != null and bar.visible:
			var rail := bar.get_global_rect()
			for d: Array in drawn:
				if (d[1] as Rect2).intersects(rail):
					hits.append("%s under the rail" % d[0])
		for case_name: String in ["TilePort", "YourBuildings", "OtherCompanies", "LandFeatures"]:
			var case := _find(case_name) as Control
			if case == null or not case.is_visible_in_tree():
				continue
			var screws: Array = []
			for p: Vector2 in Parts.screw_points(case.size, bool(case.get_meta("front", false))):
				screws.append(Rect2(case.get_global_rect().position + p - Vector2(4, 4), Vector2(8, 8)))
			for n: Node in case.find_children("*", "", true, false):
				var part := n as Control
				if part == null or not part.is_visible_in_tree():
					continue
				var is_part := part is PanelContainer and "tip" in part
				if not (is_part or part.name == "OtherCompaniesKey" or part.name == "Heading"):
					continue
				var r := _drawn(part) if is_part else part.get_global_rect()
				for sr: Rect2 in screws:
					if r.intersects(sr):
						hits.append("a screw of %s on %s" % [case_name, part.name])
		_ok(hits.is_empty(), "%s%s: nothing lies over anything else %s" % [tag, ", all open" if pass_open else "", str(hits)])
	_panel.set_meta("tvp_bl_others_open", false)
	_panel.set_meta("tvp_bl_open_groups", was)
	_panel.call("_refresh_pane", "bl")
	await _frames(2)


## The rect a part's render covers on screen, past its control by its render's reach.
func _drawn(c: Control) -> Rect2:
	var r := c.get_global_rect()
	var lo := 0.0
	var hi := 0.0
	if c is MarginContainer and c.get_child_count() > 0 and c.get_child(0).name == "Rows":
		lo = 3.0
		hi = Section.PLASTIC_MARGIN
	elif c.get_script() == Section:
		lo = 1.1
		hi = 6.6
	elif c is PanelContainer:
		lo = 1.3
		hi = Parts.MODULE_MARGIN
	return Rect2(r.position - Vector2(lo, lo), r.size + Vector2(lo + hi, lo + hi))


## A tile with nothing on it: no buildings, no projects, no port.
func _empty_tile() -> String:
	var terrain: Node = _wm.get("terrain_layer")
	var ids: Array = []
	if terrain != null:
		for t: Dictionary in (terrain.get("tiles") as Dictionary).values():
			ids.append(str(t.get("id", "")))
	ids.sort()
	for id: String in ids:
		if id != "" and BuildingState.get_buildings_on_tile(id).is_empty() and Construction.projects_on_tile(id).is_empty():
			return id
	return "tile_0_0"


## The pointer resting on a module through the real input path shows its readout as the tooltip, with no
## tooltip box drawn round it.
func _check_hover_readout() -> void:
	await _open(TILE)
	var module := _find("BuildingCard_b_025_r_037") as Control
	if module == null:
		module = _find("BuildingCard_b_007_r_003") as Control
	var scroll := _panel.find_child("BodyScroll", true, false) as ScrollContainer
	if scroll != null and module != null:
		scroll.ensure_control_visible(module)
	await _frames(3)
	var at := module.get_global_rect().get_center() if module != null else Vector2.ZERO
	for i in 3:
		var m := InputEventMouseMotion.new()
		m.position = at + Vector2(i, 0)
		m.global_position = m.position
		get_viewport().push_input(m, true)
		await _frames(2)
	await get_tree().create_timer(1.0).timeout
	await _frames(3)
	var shown: Node = null
	for w: Node in get_tree().root.find_children("*", "Window", true, false):
		if (w as Window).visible and w.find_child("HoverReadout", true, false) != null:
			shown = w
	_ok(shown != null, "resting the pointer on a module shows its readout as the tooltip")
	if shown != null:
		var r := shown.find_child("HoverReadout", true, false)
		var box := (shown as Window).get_theme_stylebox("panel")
		_ok(box is StyleBoxEmpty, "the tooltip draws no box round the readout")
		print("[BL_CHECK]    tooltip: %s / %s, window %s" % [r.call("shown_name"), r.call("shown_detail"), str((shown as Window).size)])
	var off := InputEventMouseMotion.new()
	off.position = Vector2(2, 2)
	off.global_position = off.position
	get_viewport().push_input(off, true)
	await _frames(3)


## A press on Cancel through the real input path cancels the project and does not also open it.
func _check_cancel_press() -> void:
	await _open(TILE)
	var before := Construction.projects_on_tile(TILE).size()
	var cancel := _pane().find_child("CancelConstruction_*", true, false) as Button
	if cancel == null:
		_ok(false, "a Cancel key to press")
		return
	var scroll := _panel.find_child("BodyScroll", true, false) as ScrollContainer
	if scroll != null:
		scroll.ensure_control_visible(cancel)
	await _frames(3)
	var opened: Array = []
	var on_open := func(b: Dictionary) -> void: opened.append(str(b.get("instance_id", "")))
	_panel.building_clicked.connect(on_open)
	var downs: Array = []
	cancel.button_down.connect(func() -> void: downs.append(true))
	var at := cancel.get_global_rect().get_center()
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		e.position = at
		e.global_position = at
		get_viewport().push_input(e, true)
		await _frames(2)
	_panel.building_clicked.disconnect(on_open)
	_ok(not downs.is_empty(), "the press reached Cancel through the viewport")
	_ok(opened.is_empty(), "pressing Cancel does not open the project in Building Detail %s" % str(opened))
	_ok(Construction.projects_on_tile(TILE).size() == before - 1, "Cancel cancelled the project (%d to %d)" % [before, Construction.projects_on_tile(TILE).size()])


func _check_solo_click(iid: String) -> void:
	var card := _find("BuildingCard_b_007_r_009") as Control
	_ok(card != null and _feed_of(card) == null, "a lone motor factory is a solo card")
	var got: Array = []
	var on_click := func(b: Dictionary) -> void: got.append(str(b.get("instance_id", "")))
	_panel.building_clicked.connect(on_click)
	_click(card)
	await _frames(3)
	_panel.building_clicked.disconnect(on_click)
	_ok(got == [iid], "a click on the solo card asks for its building (%s)" % str(got))
	_ok(TutorialDetectors._building_detail_open(SOLO_TILE, "b_007", "r_009"),
		"Building Detail is open on it (the tutorial's own check)")
	var bdp := _wm.find_child("BuildingDetailPanelV2", true, false) as Control
	if bdp != null:
		bdp.visible = false


## A paused building makes nothing: it reads 0 and its words say it is paused.
func _check_paused(iid: String) -> void:
	var b := BuildingState.get_building(iid)
	BuildingWorks.paused_buildings[iid] = true
	var r := Readings.reading(b)
	BuildingWorks.paused_buildings.erase(iid)
	var zero := true
	for o: Dictionary in r.outputs:
		zero = zero and int(o.qty) == 0
	_ok(not bool(r.runs) and zero and (r.causes as Array).has("paused"), "a paused building reads 0 and says it is paused %s" % str(r.causes))


## On land with no cables every building is stalled: each reads 0, the group's well sums 0 and is unlit, and
## the wind farms, whose diagnostics rows don't say it, say why in their words.
func _check_stalled() -> void:
	var stalled := 0
	var wrong := 0
	for b: Dictionary in BuildingState.get_buildings_on_tile(BIG_TILE):
		if not BuildingState.is_player_owned(b):
			continue
		var recipe: Dictionary = Catalog.get_recipe(str(b.get("recipe_id", "")))
		var r := Readings.reading(b)
		if BuildingReadout.run_state(b, recipe, false) == "stalled":
			stalled += 1
			for o: Dictionary in r.outputs:
				if int(o.qty) != 0:
					wrong += 1
			if bool(r.runs):
				wrong += 1
	_ok(stalled == 12 and wrong == 0, "10 motors and 2 wind farms, all stalled, each read 0 (%d stalled, %d wrong)" % [stalled, wrong])
	var head := _find("BuildingCard_b_007_r_009") as Control
	var qty := head.find_child("Qty", true, false) if head != null else null
	var pill := qty.get_child(0) as Label if qty != null else null
	_ok(pill != null and pill.text == "0", "the stalled group's well reads 0 (%s)" % (pill.text if pill != null else "none"))
	var words := head.find_child("Words", true, false) as Label if head != null else null
	_ok(words != null and words.text.begins_with("10 buildings: "), "the group head says how many: %s" % (words.text if words != null else ""))
	var wind := _find("BuildingCard_b_025_r_037") as Control
	var wq := wind.find_child("Qty", true, false) if wind != null else null
	var ww := wind.find_child("Words", true, false) as Label if wind != null else null
	_ok(wq != null and (wq.get_child(0) as Label).text == "0" and ww != null and ww.text.contains("stalled with no cables"),
		"stalled wind farms read 0 and their words say why: %s" % (ww.text if ww != null else ""))


func _check_features() -> void:
	var case := _find("LandFeatures")
	_ok(case != null and case.find_child("Heading", true, false) != null, "woods and ruins sit in their own case under a heading")
	var others := _find("OtherCompanies")
	_ok(others == null or others.find_child("Feature_*", true, false) == null, "land features are not listed as a company's")


## Every label in the body: white (or a quantity pill's cream on its navy pill), at least 12 px, and no
## dash, semicolon or middle dot (names such as "Motor - E" keep their spaced hyphen).
func _check_text(tile: String) -> void:
	var grey := 0
	var small := 0
	var marks: Array = []
	for n: Node in _pane().find_children("*", "Label", true, false):
		var l := n as Label
		var colour := l.get_theme_color("font_color")
		var pill := l.get_parent() != null and l.get_parent().name == "Qty"
		if not pill and not colour.is_equal_approx(DS.PALETTE["TEXT"]):
			grey += 1
			print("[BL_CHECK]    colour %s on '%s'" % [colour.to_html(), l.text])
		if l.get_theme_font_size("font_size") < 12:
			small += 1
		var bare := l.text.replace(" - ", " ")
		for bad in ["—", "–", "·", ";", "-"]:
			if bare.contains(bad):
				marks.append(l.text)
	_ok(grey == 0, "%s: every label is white on the dark cases (%d not)" % [tile, grey])
	_ok(small == 0, "%s: no label under 12 px (%d)" % [tile, small])
	_ok(marks.is_empty(), "%s: no dashes, semicolons or middle dots %s" % [tile, str(marks)])


## The group's words from its members' readings (buildings_readings.gd group_reading), on made-up readings.
func _check_group_words() -> void:
	var r := func(tone: String, causes: Array, qty: int, runs := true) -> Dictionary:
		return {"tone": tone, "causes": causes, "outputs": [{"good_id": "g", "qty": qty}], "runs": runs, "cost": {},
			"check": {"name": tone, "detail": "", "tone": tone}}
	var alike := Readings.group_reading([r.call("warn", ["grid power"], 35), r.call("warn", ["grid power"], 35)], ["A", "B"])
	_ok(alike.causes == ["grid power"] and alike.extra == [[], []], "members alike: the head says it, the members are quiet")
	var one_more := Readings.group_reading([r.call("warn", ["grid power", "market inputs"], 35),
		r.call("warn", ["grid power", "market inputs"], 35), r.call("warn", ["starts next turn", "market inputs"], 35)], ["A", "B", "C"])
	_ok(one_more.causes == ["grid power", "market inputs"] and one_more.extra == [[], [], ["starts next turn"]],
		"one member differs: the head says what most say, that member adds only its own %s" % str(one_more.extra))
	var mixed := Readings.group_reading([r.call("bad", ["no power"], 0, false), r.call("warn", ["grid power"], 35),
		r.call("warn", ["grid power"], 35)], ["A", "B", "C"])
	_ok(mixed.tone == "bad" and mixed.causes == ["1 fault", "2 warnings"], "mixed lamps: the worst lamp and how many at each %s" % str(mixed.causes))
	_ok(mixed.extra == [["no power"], ["grid power"], ["grid power"]], "mixed lamps: every member keeps its own words")
	_ok(int((mixed.outputs[0] as Dictionary).qty) == 70 and bool(mixed.runs), "the head sums the members that run (70)")
	_ok(str((mixed.check as Dictionary).stage) == "A", "the readout names the worst member")


func _timings() -> void:
	await _open(TILE)
	var t0 := Time.get_ticks_usec()
	for _i in 5:
		_panel.call("_refresh_pane", "bl")
	print("[BL_CHECK] rebuild %.1f ms each from kept readings" % ((Time.get_ticks_usec() - t0) / 5000.0))


# --- helpers -------------------------------------------------------------------------------

func _open(tile_id: String) -> void:
	var td: Dictionary = {"id": tile_id}
	var terrain: Node = _wm.get("terrain_layer")
	if terrain != null and terrain.has_method("id_to_coord"):
		td = terrain.tiles.get(terrain.id_to_coord(tile_id), td)
	_panel.call("show_tile", td, "bl")
	await _frames(4)


func _pane() -> Control:
	return (_panel.get("_panes") as Dictionary).get("bl") as Control


func _find(node_name: String) -> Node:
	return _pane().find_child(node_name, true, false)


## The members' cable run under a group head, or null for a card that is not a group's head.
func _feed_of(head: Control) -> Control:
	if head == null or head.get_parent() == null or head.get_parent().name != "Group":
		return null
	return head.get_parent().get_node_or_null("Feed") as Control


func _click(c: Control) -> void:
	if c == null:
		return
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = c.size * 0.5
	c.gui_input.emit(e)


func _ok(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
		print("[BL_CHECK] PASS %s" % what)
	else:
		_failed += 1
		print("[BL_CHECK] FAIL %s" % what)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
