extends Node2D
## Captures of the tile view v3's Transport tab in states the general tool (tools/tvp_v3_shot.tscn) doesn't
## reach, in the real HUD at 1920 × 1080 (two pixels each), cropped to the panel:
##   transport_busy       the busy port tile after three turns, from the top of the body
##   transport_hover_*    a module or key hovered through the real input path, its card at the pointer:
##                        _upgrade (the roads), _build (pipework's Build key), _upgrading (the cables while
##                        they are raised), _top (the roads at the top level), _materials (the empty tile's
##                        cables: land to buy, materials ordered), _refused (automatic land buying off: the
##                        cost and time still shown, in red), _broke (the cash won't cover it); each card's
##                        lines, whether its dot cells run edge to edge with the wells on them, and whether
##                        it sits inside the body are printed
##   transport_near       the cables at 91.5% of their limit and the roads at 92.7% of theirs: each meter's
##                        lit run, its lamp and its words must all read near capacity
##   transport_stress     the same with roads over capacity (a heavy shipment leaving), their history and
##                        overages, the cables near their limit, cables upgrading and rail being built
##   transport_overload   the roads far over capacity (900 and more of 300), so the meter's scale stretches,
##                        with six goods riding them (three wells and a count of the rest)
##   transport_top        the roads at the top level: the Upgrade key greyed, the drum 3 of 3
##   transport_locked     a logistics game before Infrastructure Tendering: the links built here read only,
##                        their Upgrade keys greyed, nothing to add, the line saying why under them;
##                        transport_hover_locked its roads' card; transport_locked_empty the empty tile then;
##                        transport_locked_bare a tile with no links then: only the note
##   transport_empty      the empty mountain tile, from the top: unowned, so every Build key buys land
##   transport_noauto     the same with automatic land buying off: every Build key says to buy land first
##   transport_broke      the busy tile with £20 in the bank: the keys say the cash won't cover them
##   transport_bare       a tile with no links at all: the one group, without the cable's gutter
## It also prints probes: the Build key's quote against what the press actually spent, the Build key laying
## pipework, the Upgrade key opening the upgrade sheet, the first Button in the empty tile's cables row (the
## tutorial presses it), whether a drum rolls when the tile changes (it must not), how long the tab takes
## to build, every key's print (Build or Upgrade only), and an overlap audit of every page: the case clear
## of the scrollbar, the modules clear of each other, the screws clear of the modules and headings, the
## wells' frames clear of each other.
##   Godot --path . res://tools/tvp_v3_transport_shot.tscn --quit-after 30000 -- --no-telemetry
## Writes into $TVP_SHOT_DIR (or /tmp); each state a page at a time down the body (_p1, _p2 ...).

const LOGICAL := Vector2i(1920, 1080)
const TILE := "tile_5_10"
const EMPTY_TILE := "tile_6_1"

var _vp: SubViewport
var _wm
var _out := "/tmp"


func _ready() -> void:
	var dir := OS.get_environment("TVP_SHOT_DIR")
	if dir != "":
		_out = dir
	_vp = SubViewport.new()
	_vp.size = LOGICAL * 2
	_vp.size_2d_override = LOGICAL
	_vp.size_2d_override_stretch = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.gui_embed_subwindows = true
	add_child(_vp)
	_wm = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_vp.add_child(_wm)
	await _settle(140)
	var cam := _vp.get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false

	MatchState.money = 8000.0
	BuildingState.add_building("b_007", "r_009", TILE, MatchState.LOCAL_PLAYER, "7e5701a1")
	BuildingState.add_building("b_007", "r_003", TILE, MatchState.LOCAL_PLAYER, "7e5701a2")
	BuildingState.add_building("b_025", "r_037", TILE, MatchState.LOCAL_PLAYER, "7e5701a3")
	Stockpile.add(TILE, str(Catalog.get_good_by_internal_name("steel").get("id", "")), 40)
	Stockpile.add(TILE, str(Catalog.get_good_by_internal_name("copper_wiring").get("id", "")), 40)
	TurnManager.fast_mode = true
	DecisionState.auto_resolve = true
	for _i in 3:
		TurnManager.commit_turn()
		if TurnManager.is_resolving:
			await TurnManager.turn_resolution_completed
	var dock: Node = _wm.find_child("EndTurnDock", true, false)
	if dock != null and dock.get("_expanded") == true:
		dock.call("_collapse")
	var toasts: Node = _wm.get_node_or_null("UILayer/HUD/ToastLayer")
	if toasts != null:
		toasts.call("clear")
	await _settle(30)

	var panel: Control = _wm.find_child("TileInfoPanel", true, false)
	var terrain: Node = _wm.get("terrain_layer")
	var td := _tile(terrain, TILE)
	UiPrefs.set_use_tvp_v3(true)
	await _settle(6)

	await _shoot(panel, td, "transport_busy")
	_print_keys(panel, "busy")
	await _hover(panel, panel.find_child("InfraCell_roads", true, false), Vector2(0.5, 0.75), "transport_hover_upgrade")
	await _hover(panel, panel.find_child("InfraBuild_pipes", true, false), Vector2(0.5, 0.5), "transport_hover_build")

	# The keys do what they say: Build lays pipework here (the row then shows it being built), and Upgrade
	# opens the roads in Building Detail on its upgrade sheet.
	_time_build(panel)
	var build_key: Button = panel.find_child("InfraBuild_pipes", true, false)
	if build_key != null:
		var q: Dictionary = build_key.get_meta("tvp_transport_quote", {})
		var before := MatchState.money
		build_key.pressed.emit()
		print("[TVP_SHOT] pipework Build key: %s over %s; quoted %.2f (fee %.2f, %d land %.2f, materials %.2f), the press spent %.2f" % [
			str(build_key.get("title")), str(build_key.get("detail")), float(q.get("total", -1.0)), float(q.get("fee", -1.0)),
			int(q.get("land_units", 0)), float(q.get("land_cost", 0.0)), float(q.get("materials_cost", 0.0)), before - MatchState.money])
		await _settle(20)
		var pipes_row: Node = panel.find_child("InfraCell_pipes", true, false)
		print("[TVP_SHOT] pipework after Build: %s" % ("being built" if pipes_row != null and pipes_row.find_child("InfraBuilding_pipes", true, false) != null else "not started"))
		await _shoot(panel, td, "transport_after_build")
		_print_keys(panel, "after build")
	var up_key: Button = panel.find_child("InfraUpgrade_roads", true, false)
	if up_key != null:
		up_key.pressed.emit()
		await _settle(40)
		_save(Rect2(Vector2.ZERO, Vector2(LOGICAL)), "transport_upgrade_sheet")
		var detail: Control = _wm.find_child("BuildingDetailPanelV2", true, false)
		print("[TVP_SHOT] detail open after Upgrade: %s" % str(detail != null and detail.visible))
		if detail != null and detail.has_method("close"):
			detail.call("close")
		elif detail != null:
			detail.visible = false
		await _settle(10)

	# Near: the cables drawing 1,830 of their 2,000 MW and 278 units of steel leaving by road against the
	# roads' 300, both just past the near share (0.9), where a meter's cells round down past the amber zone.
	var steel := str(Catalog.get_good_by_internal_name("steel").get("id", ""))
	TransportState._last_transit_shipments.append({"good_id": steel, "qty": 278, "source_tile": TILE,
		"destination_tile": "tile_5_9", "transport_turns": 1, "turns_remaining": 1, "tiles": [], "legs": []})
	TransportState._has_transport_snapshot = true
	Power.tile_drawn[TILE] = 1830
	await _shoot(panel, td, "transport_near", 1)
	_print_tones(panel, "near")

	# Stress: a heavy shipment of steel leaving by road this turn (350, over the roads' 300), roads over
	# capacity in three of the last turns with overages paid, the cables near their limit, cables being
	# upgraded and rail being built.
	TransportState._last_transit_shipments.append({"good_id": steel, "qty": 72, "source_tile": TILE,
		"destination_tile": "tile_5_9", "transport_turns": 1, "turns_remaining": 1, "tiles": [], "legs": []})
	TransportState._link_over_history["%s|roads" % TILE] = [false, true, true, false, true]
	TransportState._link_congestion_paid["%s|roads" % TILE] = 42.5
	Power.tile_drawn[TILE] = 1850
	for slot: Dictionary in load("res://scripts/tile_view_data.gd").infrastructure_summary(TILE, td):
		if str(slot.get("key", "")) == "cables" and str(slot.get("state", "")) == "exists":
			var up: Dictionary = BuildingWorks.start_upgrade(str((slot.get("instance", {}) as Dictionary).get("instance_id", "")))
			print("[TVP_SHOT] cables upgrade: %s" % str(up))
	var rail := str(Catalog.get_building_by_internal_name("rails").get("id", ""))
	if rail != "":
		Construction.start_on_tile(rail, "", TILE, 70.0)
	await _shoot(panel, td, "transport_stress")
	_print_tones(panel, "stress")
	_print_keys(panel, "stress")
	await _hover(panel, panel.find_child("InfraCell_cables", true, false), Vector2(0.5, 0.8), "transport_hover_upgrading")

	# Overload: the same roads carrying 900 against their 300, and then at the top level (750).
	TransportState._last_transit_shipments.append({"good_id": steel, "qty": 550, "source_tile": TILE,
		"destination_tile": "tile_5_9", "transport_turns": 1, "turns_remaining": 1, "tiles": [], "legs": []})
	# Six goods on the roads at once: three wells and a count of the rest must fit the module's width.
	for g: String in ["copper_wiring", "concrete", "glass", "aluminium", "motor"]:
		var gid := str(Catalog.get_good_by_internal_name(g).get("id", ""))
		if gid != "":
			TransportState._last_transit_shipments.append({"good_id": gid, "qty": 12, "source_tile": TILE,
				"destination_tile": "tile_5_9", "transport_turns": 1, "turns_remaining": 1, "tiles": [], "legs": []})
	await _shoot(panel, td, "transport_overload", 1)
	_print_tones(panel, "overload")
	BuildingWorks.set_tile_infra_level(TILE, "roads", 3)
	td = _tile(terrain, TILE)
	await _shoot(panel, td, "transport_top", 1)
	var roads_up := panel.find_child("InfraUpgrade_roads", true, false)
	if roads_up is Button:
		print("[TVP_SHOT] top level roads hover: %s" % (roads_up as Button).tooltip_text.replace("\n", " | "))
	print("[TVP_SHOT] top level roads: upgrade key %s" % ("missing" if roads_up == null or not (roads_up is Button) else
		"[%s] %s" % [str(roads_up.get("title")), "greyed, can't be pressed" if (roads_up as Button).disabled and bool(roads_up.get("spent")) else "LIVE"]))
	if roads_up is Control:
		await _hover(panel, roads_up, Vector2(0.5, 0.5), "transport_hover_top")

	# A drum rolls only when its link's level changes, not when the view moves to another tile: from the
	# roads here at level 3 to the empty tile's roads at level 1.
	panel.call("show_tile", _tile(terrain, EMPTY_TILE), "transport")
	await _settle(2)
	var other_roads := panel.find_child("InfraCell_roads", true, false)
	var drum: Node = other_roads.find_child("BdpV3Counter", true, false) if other_roads != null else null
	print("[TVP_SHOT] drum on a new tile: %s" % ("still" if drum != null and float(drum.get("_t")) >= 1.0 else "ROLLING" if drum != null else "missing"))
	BuildingWorks.set_tile_infra_level(TILE, "roads", 1)
	td = _tile(terrain, TILE)

	# A logistics game before Infrastructure Tendering: the links built here read only.
	var model_was: Variant = MatchState.ruleset.get("logistics_model", "")
	MatchState.ruleset["logistics_model"] = "middleman_v1"
	print("[TVP_SHOT] tendering available: %s" % str(ResearchState.infrastructure_tendering_available()))
	await _shoot(panel, td, "transport_locked")
	_print_keys(panel, "locked")
	await _hover(panel, panel.find_child("InfraUpgrade_roads", true, false), Vector2(0.5, 0.5), "transport_hover_locked")
	await _shoot(panel, _tile(terrain, EMPTY_TILE), "transport_locked_empty", 1)
	var bare_locked := _bare_tile(terrain)
	if bare_locked != "":
		await _shoot(panel, _tile(terrain, bare_locked), "transport_locked_bare", 1)
	MatchState.ruleset["logistics_model"] = model_was

	await _shoot(panel, _tile(terrain, EMPTY_TILE), "transport_empty")
	var cable_cell := panel.find_child("InfraCell_cables", true, false)
	var first: Array = cable_cell.find_children("*", "Button", true, false) if cable_cell != null else []
	print("[TVP_SHOT] empty tile, first Button in the cables row: %s" % (str((first[0] as Node).name) if not first.is_empty() else "none"))
	_print_keys(panel, "empty")
	await _hover(panel, panel.find_child("InfraCell_cables", true, false), Vector2(0.4, 0.3), "transport_hover_materials")
	var auto_was := MatchState.construct_auto_buy_land
	MatchState.construct_auto_buy_land = false
	await _shoot(panel, _tile(terrain, EMPTY_TILE), "transport_noauto", 1)
	_print_keys(panel, "noauto")
	await _hover(panel, panel.find_child("InfraBuild_cables", true, false), Vector2(0.5, 0.5), "transport_hover_refused")
	MatchState.construct_auto_buy_land = auto_was

	# The rail key's quote against the real press on the unowned tile: land bought and cash spent.
	await _shoot(panel, _tile(terrain, EMPTY_TILE), "transport_empty_again", 0)
	var rail_key: Button = panel.find_child("InfraBuild_rails", true, false)
	if rail_key != null:
		var rq: Dictionary = rail_key.get_meta("tvp_transport_quote", {})
		var cash := MatchState.money
		var land := BuildingState.get_tile_land_owned(EMPTY_TILE)
		rail_key.pressed.emit()
		await _settle(4)
		print("[TVP_SHOT] rail on the empty tile: quoted %.2f with %d land, the press spent %.2f and bought %d land" % [
			float(rq.get("total", -1.0)), int(rq.get("land_units", 0)), cash - MatchState.money,
			BuildingState.get_tile_land_owned(EMPTY_TILE) - land])
		for project: Dictionary in Construction.projects_on_tile(EMPTY_TILE):
			Construction.cancel(str(project.get("instance_id", "")))

	var money_was := MatchState.money
	MatchState.money = 20.0
	await _shoot(panel, td, "transport_broke", 3)
	_print_keys(panel, "broke")
	await _hover(panel, panel.find_child("InfraUpgrade_roads", true, false), Vector2(0.5, 0.5), "transport_hover_broke")
	MatchState.money = money_was

	var bare := _bare_tile(terrain)
	print("[TVP_SHOT] bare tile: %s" % bare)
	if bare != "":
		await _shoot(panel, _tile(terrain, bare), "transport_bare", 2)
		_print_keys(panel, "bare")
		# The cables' quote against the real press where the materials are missing and get ordered.
		var cable_key: Button = panel.find_child("InfraBuild_cables", true, false)
		if cable_key != null:
			print("[TVP_SHOT] cables Build key hover: %s" % cable_key.tooltip_text)
			var cq: Dictionary = cable_key.get_meta("tvp_transport_quote", {})
			var cash_before := MatchState.money
			cable_key.pressed.emit()
			await _settle(4)
			print("[TVP_SHOT] cables on the bare tile: quoted %.2f (fee %.2f, %d land %.2f, materials %s %.2f), the press spent %.2f, projects %d" % [
				float(cq.get("total", -1.0)), float(cq.get("fee", -1.0)), int(cq.get("land_units", 0)), float(cq.get("land_cost", 0.0)),
				str(cq.get("materials", "")), float(cq.get("materials_cost", 0.0)), cash_before - MatchState.money,
				Construction.projects_on_tile(bare).size()])
	UiPrefs.set_use_tvp_v3(false)
	print("[TVP_SHOT] done")
	get_tree().quit(0)


## A land tile with no links on it and none being built, for the one-group layout.
func _bare_tile(terrain: Node) -> String:
	for coord in terrain.tiles:
		var t: Dictionary = terrain.tiles[coord]
		var id := str(t.get("id", ""))
		if id == "" or not (t.get("infrastructure_present", []) as Array).is_empty():
			continue
		if Catalog.tile_type(id) in ["sea", "deep_sea"] or not Construction.projects_on_tile(id).is_empty():
			continue
		if BuildingState.max_tile_land(id) >= 150:
			return id
	return ""


## Each built link's lamp against its meters' lit runs and its words: they must read the same state.
func _print_tones(panel: Control, tag: String) -> void:
	var out: Array[String] = []
	for cell in panel.find_children("InfraCell_*", "PanelContainer", true, false):
		if not cell.has_meta("tvp_transport_tone"):
			continue
		var meters: Array[String] = []
		for m in cell.find_children("Meter*", "Control", true, false):
			meters.append("%s %s (%.0f of %.0f)" % [str(m.name).trim_prefix("Meter"), str(m.get("tone")), float(m.get("used")), float(m.get("cap"))])
		var words := ""
		for l in cell.find_children("*", "Label", true, false):
			var t := str((l as Label).text)
			if t.begins_with("Near") or t.begins_with("Over capacity") or t.begins_with("At its"):
				words = t.substr(0, t.find(".") + 1)
		out.append("%s lamp %s, meters [%s], words '%s'" % [cell.name, str(cell.get_meta("tvp_transport_tone")), ", ".join(meters), words])
	print("[TVP_SHOT] %s tones: %s" % [tag, " | ".join(out)])


## Every key in the tab: its name, its print and its state (red print, latched, greyed); a key printing
## anything but Build or Upgrade is flagged.
func _print_keys(panel: Control, tag: String) -> void:
	var out: Array[String] = []
	for b in panel.find_children("Infra*", "Button", true, false):
		var state := ""
		if bool(b.get("busy")):
			state = " latched"
		elif bool(b.get("spent")):
			state = " greyed"
		elif b.get("title_ink") == load("res://scripts/ds2/cream_key.gd").RED_INK:
			state = " red"
		var t := str(b.get("title"))
		var odd := not (t in ["Build", "Upgrade"]) or str(b.get("detail")) != ""
		out.append("%s [%s%s]%s" % [b.name, t, state, "  WORDS" if odd else ""])
	print("[TVP_SHOT] %s keys: %s" % [tag, ", ".join(out)])


## How long the tab takes to build, as the panel rebuilds it on each refresh.
func _time_build(panel: Control) -> void:
	var tab: GDScript = load("res://scripts/tvp_v3/transport_tab.gd")
	var pane := VBoxContainer.new()
	add_child(pane)
	var runs := 20
	var t0 := Time.get_ticks_usec()
	for _i in runs:
		tab.build(panel, pane)
		for c in pane.get_children():
			pane.remove_child(c)
			c.free()
	print("[TVP_SHOT] tab build: %.2f ms a build (%d runs)" % [(Time.get_ticks_usec() - t0) / 1000.0 / runs, runs])
	pane.free()


func _tile(terrain: Node, tile_id: String) -> Dictionary:
	var td: Dictionary = {"id": tile_id}
	if terrain != null and terrain.has_method("id_to_coord"):
		td = terrain.tiles.get(terrain.id_to_coord(tile_id), td)
	return td


## The tab from the top of its body, a page at a time.
func _shoot(panel: Control, td: Dictionary, tag: String, pages := 4) -> void:
	panel.call("show_tile", td, "transport")
	# Long enough for a drum that rolls to come to rest (half a second).
	await _settle(45)
	var scroll: ScrollContainer = panel.find_child("BodyScroll", true, false)
	if scroll != null:
		scroll.scroll_vertical = 0
	await _settle(8)
	if scroll != null and scroll.get_child_count() > 0:
		# Width discipline: the body must never ask for more than the scroll can show.
		var host := scroll.get_child(0) as Control
		var bar := scroll.get_v_scroll_bar()
		var room := scroll.size.x - (bar.size.x if bar.visible else 0.0)
		print("[TVP_SHOT] %s width: body asks %.0f, room %.0f%s" % [tag, host.get_combined_minimum_size().x, room,
			"" if host.get_combined_minimum_size().x <= room + 0.5 else "  TOO WIDE"])
	var step := maxf(80.0, scroll.size.y - 60.0) if scroll != null else 0.0
	for page in range(1, pages + 1):
		_audit(panel, "%s_p%d" % [tag, page])
		_save(panel.get_global_rect().grow(16.0), "%s_p%d" % [tag, page])
		if scroll == null or scroll.scroll_vertical + scroll.size.y >= scroll.get_v_scroll_bar().max_value - 1.0:
			break
		scroll.scroll_vertical = int(scroll.scroll_vertical + step)
		await _settle(4)


func _save(r: Rect2, tag: String) -> void:
	RenderingServer.force_draw(false)
	var img := _vp.get_texture().get_image()
	var k := img.get_width() / float(LOGICAL.x)
	var px := Rect2i(Vector2i(r.position * k), Vector2i(r.size * k)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	img.get_region(px).save_png(_out.path_join("%s.png" % tag))
	print("[TVP_SHOT] saved %s" % tag)


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame


## Moves the pointer onto `c` (at `at`, a share of its size) through the viewport's input, as a mouse does,
## waits for the tooltip, saves the panel with the card, and moves the pointer off again. If the engine's
## tooltip timer does not run in this offscreen viewport, the card is put up as the engine puts it up (the
## hovered control's own custom tooltip in a TooltipPanel popup at the pointer, offset as the engine offsets
## it) and the log says it was staged. Prints the card's lines.
func _hover(panel: Control, c: Control, at: Vector2, tag: String) -> void:
	if c == null:
		print("[TVP_SHOT] %s: nothing to hover" % tag)
		return
	var scroll: ScrollContainer = panel.find_child("BodyScroll", true, false)
	if scroll != null:
		var r := c.get_global_rect()
		var view := scroll.get_global_rect()
		scroll.scroll_vertical = int(scroll.scroll_vertical + r.get_center().y - view.get_center().y - 60.0)
		await _settle(4)
	var pos := c.get_global_rect().position + c.size * at
	_vp.notification(Node.NOTIFICATION_VP_MOUSE_ENTER)
	for i in 3:
		var m := InputEventMouseMotion.new()
		m.position = pos + Vector2(i, 0)
		m.global_position = m.position
		_vp.push_input(m, true)
		await _settle(2)
	var hovered := _vp.gui_get_hovered_control()
	print("[TVP_SHOT] %s: pointer on %s" % [tag, str(hovered.name) if hovered != null else "nothing"])
	await get_tree().create_timer(1.2).timeout
	await _settle(4)
	var staged: Window = null
	if _shown_tip() == null and hovered != null:
		var tip_owner: Control = hovered
		while tip_owner != null and tip_owner.tooltip_text == "":
			tip_owner = tip_owner.get_parent() as Control
		if tip_owner != null:
			var custom: Object = tip_owner.call("_make_custom_tooltip", tip_owner.tooltip_text) if tip_owner.has_method("_make_custom_tooltip") else null
			staged = PopupPanel.new()
			staged.theme_type_variation = "TooltipPanel"
			staged.transparent_bg = true
			staged.transparent = true
			if custom is Control:
				staged.add_child(custom as Control)
			else:
				var l := Label.new()
				l.text = tip_owner.tooltip_text
				staged.add_child(l)
			tip_owner.add_child(staged)
			var offset: Vector2 = ProjectSettings.get_setting("display/mouse_cursor/tooltip_position_offset", Vector2(10, 10))
			staged.popup(Rect2i(Vector2i(pos + Vector2(2, 0) + offset), Vector2i(staged.get_contents_minimum_size())))
			await _settle(6)
			print("[TVP_SHOT] %s: card staged at the pointer (the offscreen viewport runs no tooltip timer)" % tag)
	var shown := _shown_tip()
	if shown != null:
		var board := shown.find_child("DotBoard", true, false)
		var lines: Array[String] = []
		if board != null:
			for i in int(board.call("line_count")):
				lines.append(str(board.call("line_text", i)).strip_edges())
		print("[TVP_SHOT] %s: card %s at %s: %s" % [tag, str(shown.size), str(shown.position), " | ".join(lines)])
		_check_card(panel, shown, tag)
	else:
		print("[TVP_SHOT] %s: NO CARD" % tag)
	var area := panel.get_global_rect().grow(16.0)
	if shown != null:
		area = area.merge(Rect2(Vector2(shown.position), Vector2(shown.size)).grow(12.0))
	_save(area, tag)
	if staged != null:
		staged.queue_free()
	var off := InputEventMouseMotion.new()
	off.position = Vector2(4, 4)
	off.global_position = off.position
	_vp.push_input(off, true)
	await _settle(4)


## A card's screen and place: every dot line the shared DotMatrix part, all as wide as each other (the cells
## run edge to edge), every well on the cells, and the card with its bezel inside the body (BodyScroll, short
## of its scrollbar's rail), so it covers neither the navy sheet's rim, the rail nor the panel's frame.
func _check_card(panel: Control, shown: Window, tag: String) -> void:
	var dm: Script = load("res://scripts/ds2/dot_matrix.gd")
	var card := shown.find_child("TransportCard", true, false) as Control
	var found: Array[String] = []
	var widths := {}
	var field := Rect2()
	var count := 0
	for c in card.find_children("*", "Control", true, false):
		if (c as Control).get_script() != dm:
			continue
		count += 1
		widths[snappedf((c as Control).size.x, 0.1)] = true
		var r := (c as Control).get_global_rect()
		field = r if field.size == Vector2.ZERO else field.merge(r)
	if widths.size() != 1:
		found.append("dot lines of %d widths %s" % [widths.size(), str(widths.keys())])
	var ml := float(card.get_theme_constant("margin_left"))
	var mt := float(card.get_theme_constant("margin_top"))
	var pane := Rect2(card.global_position + Vector2(ml, mt),
		card.size - Vector2(ml + float(card.get_theme_constant("margin_right")), mt + float(card.get_theme_constant("margin_bottom"))))
	if field.size.x < pane.size.x - 1.0 or field.size.y < pane.size.y - 1.0:
		found.append("dot field %s short of the glass %s" % [str(field.size), str(pane.size)])
	for w in card.find_children("IconWell", "Control", true, false):
		var wr := (w as Control).get_global_rect()
		if not field.encloses(wr):
			found.append("a well %s off the dot field %s" % [str(wr), str(field)])
	# The card with its bezel's render, against the body short of the scrollbar's rail.
	var drop := shown.find_child("TransportTip", true, false)
	var reach := 8.0 / 1.875
	var face := Rect2(Vector2(shown.position) + Vector2(6, 6), card.size).grow(reach)
	var body: Rect2 = drop.call("bounds") if drop != null else Rect2()
	if not body.grow(0.5).encloses(face):
		found.append("card %s outside the body %s" % [str(face), str(body)])
	print("[TVP_SHOT] %s card: %d dot lines, %s" % [tag, count, "clear" if found.is_empty() else "; ".join(found)])


## The tooltip window on screen with a transport card in it, if any.
func _shown_tip() -> Window:
	for w: Node in _vp.find_children("*", "Window", true, false):
		if (w as Window).visible and w.find_child("TransportCard", true, false) != null:
			return w as Window
	return null


## What overlaps on the page in view: the case against the scrollbar's rail, each module against the next,
## the case's screws against the modules and headings, and each pair of wells' frames. Prints "clear" or
## each overlap found.
func _audit(panel: Control, tag: String) -> void:
	var tab: GDScript = load("res://scripts/tvp_v3/transport_tab.gd")
	var well: GDScript = load("res://scripts/ds2/good_well.gd")
	var found: Array[String] = []
	var scroll: ScrollContainer = panel.find_child("BodyScroll", true, false)
	var case := panel.find_child("TransportLinks", true, false) as Control
	if case == null or scroll == null:
		print("[TVP_SHOT] %s overlaps: no case" % tag)
		return
	var bar := scroll.get_v_scroll_bar()
	var cr := case.get_global_rect()
	if bar.visible:
		var gap := bar.get_global_rect().position.x - cr.end.x
		if gap < 4.0:
			found.append("case %.1f px from the rail" % gap)
	var modules: Array = case.find_children("InfraCell_*", "Control", true, false)
	for i in modules.size():
		for j in range(i + 1, modules.size()):
			var a := (modules[i] as Control).get_global_rect()
			var b := (modules[j] as Control).get_global_rect()
			if a.intersects(b):
				found.append("%s over %s" % [modules[i].name, modules[j].name])
	# The screws, as the case draws them (their radius is a quarter of the render's side).
	var screw_r := (load("res://assets/ui/bdp_v3/screw_silver.png") as Texture2D).get_size().x / 4.0
	var bands: Array = tab.call("_screw_bands", case)
	var edges: Array = []
	for m in modules:
		edges.append((m as Control).get_global_rect())
	for h in case.find_children("Heading", "Control", true, false):
		edges.append((h as Control).get_global_rect())
	for p: Vector2 in tab.call("screw_points", case.size, bands):
		var at := case.get_global_transform() * p
		var disc := Rect2(at - Vector2(screw_r, screw_r), Vector2(screw_r, screw_r) * 2.0)
		for e: Rect2 in edges:
			if disc.intersects(e):
				found.append("screw at %s over %s" % [str(p.round()), str(e)])
	# Each well's frame (its visible metal, a third of its reach) against the others'.
	var frame := float(well.call("reach")) / 3.0
	var wells: Array = case.find_children("IconWell", "Control", true, false)
	for i in wells.size():
		for j in range(i + 1, wells.size()):
			var a := (wells[i] as Control).get_global_rect().grow(frame)
			var b := (wells[j] as Control).get_global_rect().grow(frame)
			if a.intersects(b):
				found.append("wells %d and %d touch" % [i, j])
	# Nothing of the case may reach outside the body sheet's padding.
	var sheet := panel.find_child("BodySheet", true, false) as Control
	if sheet != null:
		var inner := sheet.get_global_rect().grow(-16.0)
		if cr.position.x < inner.position.x or cr.end.x > inner.end.x:
			found.append("case %s outside the sheet's padding %s" % [str(cr), str(inner)])
	print("[TVP_SHOT] %s overlaps: %s" % [tag, "clear" if found.is_empty() else "; ".join(found)])
