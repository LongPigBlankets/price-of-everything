extends Node2D
## Captures of the tile view v3's Power tab (scripts/tvp_v3/power_tab.gd), in the real HUD at 1920 × 1080
## (two pixels each), cropped to the panel. First three turns with wind and solar selling to the national
## grid (the game's default), then three with it running first for your buildings:
##   busygrid     the standard busy port tile (two factories and a wind farm, as tools/tvp_v3_shot.gd sets
##                it), its wind sold to the grid: "Y MW sold to the national grid." over "Z MW bought from the national grid."
##   producergrid a solar farm alone on its own cables: "Y MW sold to the national grid."
##   fedgrid      one factory on cables joined to the producer's only: "Z MW bought from the national grid."
##   mixedgrid    a solar farm and two factories on their own cables, consuming more than it produces
##   busy         the busy tile with its wind running first for you
##   green        a cabled tile with a solar farm running first, factories consuming it, and battery storage
##                with two lithium cells loaded and more in stock: intermittency and the bank
##   deficit      a cabled tile with factories and no plant, on the busy and green tiles' cables: "A MW
##                bought from the national grid."
##   mixed        mixedgrid running first for you: "A MW bought from the national grid."
##   producer     the producer, part of its power used by the fed tile: "A MW sold to the national grid."
##   fed          the fed tile: "Nothing sold to or bought from the national grid."
##   nocables     a tile with a factory and no cables
##   empty        the empty unowned mountain tile
## Each is paged down its whole body: tvp_v3_power_<scenario>_p1.png, _p2 ... and, where the tile has an
## intermittency readout that flashes, its row in both phases of its lamp (tvp_v3_power_<scenario>_flash_a
## and _b). Each scenario checks its own page: the national grid's words against the engine's figures in the
## sentence the scenario should read (one sentence, at most two lines), the intermittency lamp and words
## against their reading, no seven segment LED on the tab (money only), keys one width within a row, and
## nothing overlapping or touching (a case inside its parent's rim and screws, at least a pixel clear of its
## neighbours, each section's drawn edge at least 2 px inside the body sheet and clear of its scrollbar, the
## sections' edges lined up). Then the checks (what the keys do, the figures against the engine's, each lamp
## against its reading and the Power key, the intermittency rule on made up figures, the layout's rules)
## print PASS or FAIL, with green_loaded (cells just loaded), green_next (a turn later, the bank reading what
## the new cells firmed) and the meter alone with 4 to 10 kinds of building (crowd_N).
##   Godot --path . res://tools/tvp_v3_power_shot.tscn --quit-after 30000 -- --no-telemetry
## Writes into $TVP_SHOT_DIR (or /tmp).

const Lamp := preload("res://scripts/bdp_v3_lamp.gd")
const LOGICAL := Vector2i(1920, 1080)
## What each scenario's intermittency lamp should show after its turns: the tones it cycles, or one steady
## tone. Sold to the grid (busygrid, producergrid, mixedgrid): amber and green; consuming only grid power
## (fedgrid): green, none of it intermittent; running first for your buildings with no batteries (busy,
## mixed, producer, fed): red; solar partly firmed by two cells (green): amber and red; consuming wind and
## solar from the other tiles, partly firmed at the plants (deficit): amber and red.
const EXPECTED_LAMP := {"busygrid": ["warn", "ok"], "producergrid": ["warn", "ok"], "fedgrid": ["ok"],
	"mixedgrid": ["warn", "ok"], "busy": ["bad"], "green": ["warn", "bad"], "deficit": ["warn", "bad"],
	"mixed": ["bad"], "producer": ["bad"], "fed": ["bad"]}
## The phase each scenario is shot in: these with wind and solar sold to the grid, the rest running first.
const GRID_PHASE := ["busygrid", "producergrid", "fedgrid", "mixedgrid"]
## How far a staged network of its own stands from every other staged tile, in hexes, so neither its cables
## nor the engine's nearest first share of wind and solar reach the others much.
const APART := 4
## How far the staged networks of their own stand from each other, in hexes.
const NEAR := 3
## Where a section's case is drawn inside its rect (left, right; measured on the captures): the steel frame's
## rim, and the plastic case's render, which reaches almost to its rect's edges.
const STEEL_RIM_IN := Vector2(1.5, 3.0)
const PLASTIC_RIM_IN := Vector2(0.0, 0.5)
## The room a section's drawn edge keeps from the body sheet's edges and its scrollbar.
const SHEET_CLEAR := 2.0
const BUSY := "tile_5_10"
const EMPTY_TILE := "tile_6_1"

var _vp: SubViewport
var _wm
var _out := "/tmp"
## The staged tiles by scenario.
var _staged := {}
## Goods kept in stock on a staged tile before every turn, {tile: {good id: qty}}, and the goods taken out
## ({tile: [good id]}), so its buildings run every turn without filling the tile's storage.
var _keep := {}
var _drain := {}


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
	var terrain: Node = _wm.get("terrain_layer")

	# Staged tiles near the busy one: two given cables here (the capture's own staging, not saved), one left
	# without.
	var green := _pick_tile(terrain, [BUSY])
	var deficit := _pick_tile(terrain, [BUSY, green])
	var bare := _pick_tile(terrain, [BUSY, green, deficit])
	for tid in [green, deficit]:
		_lay_cables(terrain, tid)
	# Two networks of their own, away from the others: a mixed tile, and a producer and the one tile it feeds.
	# The engine hands each plant's wind and solar to the nearest buildings with room, plant by plant in tile
	# id order (Production._allocate_power_derates), so their plants are staged on tiles whose ids sort after
	# the busy and green tiles': those tiles' own plants reach their own buildings first, as in play.
	var mixed := _pick_isolated(terrain, [BUSY, green, deficit, bare], [], green)
	var pair := _pick_pair(terrain, [BUSY, green, deficit, bare], [mixed], green)
	var producer := str(pair[0]) if pair.size() == 2 else ""
	var fed := str(pair[1]) if pair.size() == 2 else ""
	for tid in [producer, fed, mixed]:
		_lay_cables(terrain, tid)
	print("[TVP_SHOT] tiles busy=%s green=%s deficit=%s nocables=%s producer=%s fed=%s mixed=%s" % [BUSY, green,
		deficit, bare, producer, fed, mixed])

	MatchState.money = 50000.0
	var steel := str(Catalog.get_good_by_internal_name("steel").get("id", ""))
	var wiring := str(Catalog.get_good_by_internal_name("copper_wiring").get("id", ""))
	var ingots := str(Catalog.get_good_by_internal_name("iron_ingots").get("id", ""))
	var coal := str(Catalog.get_good_by_internal_name("coal").get("id", ""))
	# The busy tile, as the standard captures have it.
	BuildingState.add_building("b_007", "r_009", BUSY, MatchState.LOCAL_PLAYER, "inst_b_007_b1")
	BuildingState.add_building("b_007", "r_003", BUSY, MatchState.LOCAL_PLAYER, "inst_b_007_b2")
	BuildingState.add_building("b_025", "r_037", BUSY, MatchState.LOCAL_PLAYER, "inst_b_025_b3")
	Stockpile.add(BUSY, steel, 40)
	Stockpile.add(BUSY, wiring, 40)
	# Green: a solar farm running first for its own tile, three kinds of users, a battery housing.
	if green != "":
		BuildingState.add_building("b_024", "r_146", green, MatchState.LOCAL_PLAYER, "inst_b_024_c1")
		BuildingState.add_building("b_007", "r_009", green, MatchState.LOCAL_PLAYER, "inst_b_007_c2")
		BuildingState.add_building("b_007", "r_009", green, MatchState.LOCAL_PLAYER, "inst_b_007_c3")
		BuildingState.add_building("b_007", "r_003", green, MatchState.LOCAL_PLAYER, "inst_b_007_c4")
		BuildingState.add_building("b_028", "r_225", green, MatchState.LOCAL_PLAYER, "inst_b_028_c5")
		for g in [steel, wiring, ingots]:
			Stockpile.add(green, g, 120)
	if deficit != "":
		BuildingState.add_building("b_007", "r_009", deficit, MatchState.LOCAL_PLAYER, "inst_b_007_d1")
		BuildingState.add_building("b_007", "r_003", deficit, MatchState.LOCAL_PLAYER, "inst_b_007_d2")
		for g in [steel, wiring, ingots]:
			Stockpile.add(deficit, g, 120)
	if bare != "":
		BuildingState.add_building("b_007", "r_009", bare, MatchState.LOCAL_PLAYER, "inst_b_007_e1")
		for g in [steel, wiring]:
			Stockpile.add(bare, g, 200)
	if producer != "":
		BuildingState.add_building("b_024", "r_146", producer, MatchState.LOCAL_PLAYER, "inst_b_024_f1")
		BuildingState.add_building("b_007", "r_009", fed, MatchState.LOCAL_PLAYER, "inst_b_007_f2")
		for g in [steel, wiring, ingots]:
			Stockpile.add(fed, g, 200)
	if mixed != "":
		BuildingState.add_building("b_024", "r_146", mixed, MatchState.LOCAL_PLAYER, "inst_b_024_1a1")
		BuildingState.add_building("b_007", "r_003", mixed, MatchState.LOCAL_PLAYER, "inst_b_007_1a2")
		BuildingState.add_building("b_007", "r_003", mixed, MatchState.LOCAL_PLAYER, "inst_b_007_1a3")
		# Two steelworks: their ingots and coal kept in stock, their steel taken out, each turn.
		_keep[mixed] = {ingots: 120, coal: 80}
		_drain[mixed] = [steel]
	# Lithium cells researched (staged directly: the capture needs the state, not the research path).
	ResearchState.unlocked_titles["Lithium Battery Storage"] = true
	var lithium := str(Catalog.get_good_by_internal_name("lithium_battery").get("id", ""))
	if green != "" and lithium != "":
		Stockpile.add(green, lithium, 12)
		var loaded := Power.load_battery_cells(green, lithium, 2)
		print("[TVP_SHOT] loaded %d lithium cells on %s (slots %d)" % [loaded, green, Power.tile_battery_slots(green)])

	TurnManager.fast_mode = true
	DecisionState.auto_resolve = true
	var panel: Control = _wm.find_child("TileInfoPanel", true, false)
	var only := OS.get_environment("TVP_POWER_SCENARIOS")
	var wanted := only.split(",") if only != "" else PackedStringArray(["busygrid", "producergrid", "fedgrid", "mixedgrid",
		"busy", "green", "deficit", "mixed", "producer", "fed", "nocables", "empty"])
	var tiles := {"busy": BUSY, "green": green, "deficit": deficit, "nocables": bare, "empty": EMPTY_TILE,
		"producer": producer, "fed": fed, "mixed": mixed}
	_staged = tiles
	# First with wind and solar selling to the grid (the game's default): the busy tile as a new player sees it.
	await _turns(3)
	UiPrefs.set_use_tvp_v3(true)
	await _settle(6)
	for scenario: String in GRID_PHASE:
		var tid := str(tiles.get(scenario.trim_suffix("grid"), ""))
		if tid == "" or not wanted.has(scenario):
			continue
		await _shoot(panel, terrain, tid, "tvp_v3_power_%s" % scenario)
		await _scenario_checks(panel, tid, scenario, EXPECTED_LAMP.get(scenario, null))
	UiPrefs.set_use_tvp_v3(false)
	# Then with wind and solar running first for your own buildings: intermittency.
	MatchState.set_power_priority("wind_solar", "self")
	await _turns(3)
	# A staged building that did not run would change what its scenario shows: say why.
	for t: String in tiles.values():
		for b: Dictionary in BuildingState.get_buildings_on_tile(t):
			var iid := str(b.get("instance_id", ""))
			if BuildingState.is_player_owned(b) and not bool(Production.last_turn_run.get(iid, false)):
				print("[TVP_SHOT] %s on %s did not run: %s %s" % [iid, t, str(Production.blocked_reason_by_building.get(iid, "")),
					str(Production.missing_by_building.get(iid, ""))])
	var dock: Node = _wm.find_child("EndTurnDock", true, false)
	if dock != null and dock.get("_expanded") == true:
		dock.call("_collapse")
	var toasts: Node = _wm.get_node_or_null("UILayer/HUD/ToastLayer")
	if toasts != null:
		toasts.call("clear")
	# A storage prompt the staging may raise would cover the panel.
	for n in _wm.find_children("*", "PanelContainer", true, false):
		var sc: Script = n.get_script()
		if sc != null and sc.resource_path.ends_with("capacity_dialog.gd"):
			(n as Control).hide()
	await _settle(30)

	UiPrefs.set_use_tvp_v3(true)
	await _settle(6)
	for scenario: String in wanted:
		var tid := str(tiles.get(scenario, ""))
		if tid == "" or GRID_PHASE.has(scenario):
			continue
		var im: Dictionary = Production.get_tile_intermittency(tid)
		print("[TVP_SHOT] %s: made %d drawn %d cap %d im %s" % [scenario, int(Power.tile_produced.get(tid, 0)),
			int(Power.tile_drawn.get(tid, 0)), Power.tile_power_cap(tid), str(im)])
		await _shoot(panel, terrain, tid, "tvp_v3_power_%s" % scenario)
		await _scenario_checks(panel, tid, scenario, EXPECTED_LAMP.get(scenario, null))
		# The body is rebuilt on every refresh: how long that takes here, and whether it stays inside the scroll.
		var t0 := Time.get_ticks_usec()
		for _i in 10:
			panel.call("_refresh_pane", "power")
		var pane: Control = (panel.get("_panes") as Dictionary).get("power")
		var scroll: ScrollContainer = panel.find_child("BodyScroll", true, false)
		await _settle(2)
		print("[TVP_SHOT] %s: rebuild %.2f ms, body min width %.0f of %.0f" % [scenario,
			float(Time.get_ticks_usec() - t0) / 10000.0, pane.get_combined_minimum_size().x,
			scroll.size.x - scroll.get_v_scroll_bar().size.x])
	if only == "" or wanted.has("checks"):
		_verdict_checks()
	if green != "" and (only == "" or wanted.has("checks")):
		await _checks(panel, terrain, green, deficit, bare)
	if only == "" or wanted.has("crowd"):
		await _crowd()
	UiPrefs.set_use_tvp_v3(false)
	print("[TVP_SHOT] done")
	get_tree().quit(0)


## What the tab's keys do, whether its figures add up to the engine's, and whether each lamp agrees with its
## words and with the Power key, on the staged tiles.
func _checks(panel: Control, terrain: Node, tid: String, deficit: String, bare: String) -> void:
	var PowerTab: GDScript = load("res://scripts/tvp_v3/power_tab.gd")
	var TVD: GDScript = load("res://scripts/tile_view_data.gd")
	for t: String in [BUSY, tid, deficit]:
		var made := int(Power.tile_produced.get(t, 0))
		var drawn := int(Power.tile_drawn.get(t, 0))
		var split: Dictionary = PowerTab.grid_split(t, made, drawn)
		_check(int(split.own) + int(split.network) + int(split.grid) == drawn,
			"%s: the draw's sources add up to the drawn figure (%d + %d + %d = %d)" % [t, int(split.own),
			int(split.network), int(split.grid), drawn])
	# Each staged tile: the plate's keys, and the lamps against their readings and the Power key.
	for t: String in [BUSY, tid, deficit, bare, EMPTY_TILE, str(_staged.get("producer", "")), str(_staged.get("fed", "")),
			str(_staged.get("mixed", ""))]:
		if t == "":
			continue
		var tdd: Dictionary = terrain.tiles.get(terrain.id_to_coord(t), {"id": t})
		panel.call("show_tile", tdd, "power")
		await _settle(4)
		var plate: Node = panel.find_child("PowerBalance", true, false)
		var keys := _keys_under(plate)
		_check(keys.size() <= 3 and keys.has("PowerBuildKey"),
			"%s: the balance plate has Build power and at most 3 keys (%s)" % [t, ", ".join(keys)])
		# Every cell key (Load, Order, Unload) inside Batteries, none in the balance or the cut-short case.
		var stray := 0
		for n: Node in panel.find_child("BodyScroll", true, false).find_children("*", "Control", true, false):
			if not (str(n.name).begins_with("Load_") or str(n.name).begins_with("Order_") or str(n.name).begins_with("Unload_")):
				continue
			var up := n.get_parent()
			while up != null and str(up.name) != "PowerBatteries":
				up = up.get_parent()
			if up == null:
				stray += 1
		_check(stray == 0, "%s: Load, Order and Unload stand only in Batteries" % t)
		var power: Dictionary = TVD.power_summary(t)
		# The Power key's mark as the panel sets it: red for missing cables, else from the power summary.
		var stranded := str(PowerTab.cables_missing(t))
		var key_tone: String = "red" if stranded != "" else {"warn": "amber", "problem": "red"}.get(str(power.status), "off")
		var grid: Node = plate.find_child("Readout_Nationalgrid", true, false)
		if bool(power.connected):
			var reading: Dictionary = PowerTab.grid_reading(t, power)
			var lamp: String = str(grid.find_child("Lamp", true, false).get("colour")) if grid != null else "?"
			var words: String = (grid.find_child("Words", true, false) as Label).text if grid != null else ""
			_check(grid != null and words == str(reading.words) and (key_tone == "off" or lamp == key_tone),
				"%s: the grid lamp (%s) agrees with the Power key (%s), and its words are its reading's (%s)" % [t, lamp, key_tone, words])
			if lamp == "amber":
				_check(words.contains("bought from the national grid"), "%s: an amber grid lamp's words say what was bought (%s)" % [t, words])
		else:
			_check(grid == null, "%s: no grid readout on a tile with no cables" % t)
		var cables: Node = plate.find_child("Readout_Cables", true, false)
		if Power.tile_power_cap(t) <= 0 and cables != null:
			var lamp: String = str(cables.find_child("Lamp", true, false).get("colour"))
			_check(lamp == key_tone, "%s: with no cables, the cables lamp (%s) is the Power key's (%s)" % [t, lamp, key_tone])
		if t == bare:
			var words: String = (cables.find_child("Words", true, false) as Label).text
			var key: Node = plate.find_child("PowerCablesKey", true, false)
			_check(words == "Cables missing. Power consumption not possible." and key != null and str(key.get("text")) == "Build"
				and plate.find_child("PowerMeter", true, false) == null and words == stranded,
				"no cables: the readout is the owner's words and the Power key's (%s), with Build, and no meter" % words)
		if t == EMPTY_TILE and cables != null:
			var words: String = (cables.find_child("Words", true, false) as Label).text
			_check(words == "No cables here." and str(cables.find_child("Lamp", true, false).get("colour")) == "off",
				"the empty tile's cables read %s on an unlit lamp" % words)
		if t == EMPTY_TILE:
			_check(keys == ["PowerBuildKey"], "the empty tile offers Build power alone (%s)" % ", ".join(keys))
		# The verdict's words fit its glass (two lines at most, never trimmed).
		var verdict: Node = panel.find_child("VerdictScreen", true, false)
		if verdict != null:
			var detail: Label = verdict.get("_detail")
			_check(detail.get_line_count() <= 2, "%s: the verdict's words fit its glass (%d lines: %s)" % [t, detail.get_line_count(), detail.text])
	var td: Dictionary = terrain.tiles.get(terrain.id_to_coord(tid), {"id": tid})
	panel.call("show_tile", td, "power")
	await _settle(6)
	var meter: Control = panel.find_child("PowerMeter", true, false)
	var sums := [0.0, 0.0]
	for r in 2:
		for sl: Dictionary in (meter.get("rows") as Array)[r].slices:
			sums[r] += float(sl.value)
	_check(int(sums[0]) == int(Power.tile_produced.get(tid, 0)) and int(sums[1]) == int(Power.tile_drawn.get(tid, 0)),
		"the meters' slices add up to the engine's made and drawn (%d/%d, %d/%d)" % [int(sums[0]),
		int(Power.tile_produced.get(tid, 0)), int(sums[1]), int(Power.tile_drawn.get(tid, 0))])
	_check(str(meter.call("figure", 0)) == str(int(Power.tile_produced.get(tid, 0))) and str(meter.call("figure", 1)) == str(int(Power.tile_drawn.get(tid, 0)))
		and meter.find_child("MadeFigure", true, false).get_script().resource_path.ends_with("dot_matrix.gd"),
		"the meter's MW figures are the engine's, on dot matrix screens (%s, %s, %s)" % [meter.call("figure", 0), meter.call("figure", 1), meter.call("figure", 2)])
	var tags: Array = meter.get("_tags")
	_check((tags[1] as Array).size() == (meter.get("rows") as Array)[1].slices.size() and str((tags[1] as Array)[0].mode) == "both",
		"every drawn slice has a tag with its emblem and name")
	var build: Control = panel.find_child("PowerBuildKey", true, false)
	var made_led: Control = meter.find_child("MadeFigure", true, false)
	_check(build.get_parent() == meter and absf(build.get_global_rect().end.x - made_led.get_global_rect().end.x) < 40.0
		and build.get_global_rect().end.y <= made_led.get_global_rect().position.y,
		"Build power stands over the PRODUCED figure")
	# No dead band: the made tags share the key's band, centred on its midline, and the key is the meter's top.
	var band_mid: float = float(meter.call("_band_y", 0)) + float(meter.get("TAG_H")) * 0.5
	var key_mid := build.position.y + build.size.y * 0.5
	var heading: Control = panel.find_child("PowerBalance", true, false).find_child("Heading", true, false)
	_check(absf(band_mid - key_mid) < 1.0 and build.position.y == 0.0,
		"the made tags are centred on Build power's midline (%.1f against %.1f), at the meter's top" % [band_mid, key_mid])
	_check(heading != null and meter.get_global_rect().position.y - heading.get_global_rect().end.y <= 14.0,
		"the meter starts right under the heading (%.0f px)" % (meter.get_global_rect().position.y - heading.get_global_rect().end.y))
	var cp: Control = _wm.find_child("ConstructPanelV2", true, false)
	build.emit_signal("pressed")
	await _settle(4)
	_check(cp != null and cp.visible and (cp.get("_active_filters") as Dictionary).has("power")
		and str(cp.get("_locked_tile_id")) == tid, "Build power opens Construct on this tile, on its power buildings")
	cp.hide()
	PanelStack.remove(cp)
	panel.find_child("PowerMapKey", true, false).emit_signal("pressed")
	await _settle(2)
	_check(MapMode.current_mode == MapMode.Mode.POWER_BALANCE and MapMode.is_selected(MapMode.POWER_SENTINEL),
		"Power map shows the power map mode")
	MapMode.clear_all()
	# The cut-short modules: each lamp and its words from one reading.
	var cut: Control = panel.find_child("CutShort", true, false)
	_check(cut != null and panel.find_child("PowerAffectedKey", true, false) != null,
		"the buildings cut short are listed, with the ledger key")
	var PT: GDScript = load("res://scripts/tvp_v3/power_tab.gd")
	var any_red := false
	for m: Node in cut.find_children("CutShort_*", "", true, false):
		var lamp: String = str(m.find_child("Lamp", true, false).get("colour"))
		var words: String = (m.find_child("Words", true, false) as Label).text
		var iid := str(m.name).trim_prefix("CutShort_")
		var derate := float(Production.get_building_intermittency(iid).get("derate", 0.0))
		any_red = any_red or lamp == "red"
		_check((lamp == "red") == words.begins_with("All ") and (lamp == "red") == bool(PT.is_full_cut(derate)),
			"%s: its lamp is %s at a cut of %.3f, and its words say %s" % [m.name, lamp, derate, words])
		var lines := (m.find_child("Title", true, false) as Label).get_line_count() + (m.find_child("Words", true, false) as Label).get_line_count()
		_check(lines == 2 and (m as Control).size.y <= 66.0, "%s is two lines (%d, %.0f px tall)" % [m.name, lines, (m as Control).size.y])
		var go: Control = m.find_child("GoTo", true, false)
		_check(go != null and go.size.x >= 44.0, "%s: its Go to key is the cabinet's Location key size (%.0f px)" % [m.name, go.size.x if go != null else 0.0])
	var verdict_lamp: String = str((panel.find_child("VerdictScreen", true, false).get("_lamp") as Control).get("colour"))
	_check((verdict_lamp == "red") == any_red,
		"the verdict's lamp (%s) follows the modules' rule (any red: %s)" % [verdict_lamp, str(any_red)])
	var cap: Control = panel.find_child("CutCaption", true, false)
	var first_cut: Control = cut.find_child("Cut", true, false)
	var cap_label: Control = cap.get_child(1) if cap != null else null
	_check(cap_label != null and absf(cap_label.get_global_rect().get_center().x - first_cut.get_global_rect().get_center().x) < 1.5,
		"OUTPUT CUT is printed once, centred over the modules' LEDs")
	# The bank's figures agree with the verdict: last turn it backed all it held, on the wind and solar made here.
	var im: Dictionary = Production.get_tile_intermittency(tid)
	var bank_read: Dictionary = PT.bank_reading(tid, im)
	var bank_node: Node = panel.find_child("Readout_Bank", true, false)
	_check(bank_node != null and (bank_node.find_child("Words", true, false) as Label).text == str(bank_read.words)
		and str(bank_read.words).begins_with("Firmed %d of the %d MW" % [int(im.battery_cap), int(im.green_intermittent_produced)])
		and str(bank_node.find_child("Lamp", true, false).get("colour")) == "amber",
		"the bank's readout says what it firmed last turn (%s), amber while buildings here were cut short" % str(bank_read.words))
	var lithium := str(Catalog.get_good_by_internal_name("lithium_battery").get("id", ""))
	var before := int(Power.get_tile_battery_cells(tid).get(lithium, 0))
	var stock := Stockpile.get_at_tile(tid, lithium)
	var screen: Node = panel.find_child("VerdictScreen", true, false)
	_check(panel.find_child("PowerReduceKey", true, false) == null and screen != null
		and str(screen.call("shown_detail")).contains("has room"),
		"with room in the battery storage, the verdict points to it and offers no Reduce intermittency")
	panel.find_child("Load_lithium_battery", true, false).emit_signal("pressed")
	await _settle(4)
	var after := int(Power.get_tile_battery_cells(tid).get(lithium, 0))
	_check(after == before + stock and Stockpile.get_at_tile(tid, lithium) == 0,
		"Load puts the lithium cells in stock into the storage (%d to %d)" % [before, after])
	var bank_words: String = (panel.find_child("Readout_Bank", true, false).find_child("Words", true, false) as Label).text
	var loaded_fig: String = str(panel.find_child("LoadedFigure", true, false).get("text")).strip_edges()
	_check(bank_words.contains("From next turn it firms up to %d MW" % Power.tile_firming_cap(tid)) and loaded_fig == str(Power.tile_firming_cap(tid))
		and panel.find_child("Order_lithium_battery", true, false) != null,
		"after loading, LOADED shows %s, last turn's reading says the new figure counts from next turn (%s), and the row offers Order" % [loaded_fig, bank_words])
	_save(panel.get_global_rect().grow(16.0), "tvp_v3_power_green_loaded")
	var scroll: ScrollContainer = panel.find_child("BodyScroll", true, false)
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	await _settle(4)
	_save(panel.get_global_rect().grow(16.0), "tvp_v3_power_green_loaded_foot")
	panel.find_child("Unload_lithium_battery", true, false).emit_signal("pressed")
	await _settle(4)
	_check(int(Power.get_tile_battery_cells(tid).get(lithium, 0)) == 0 and Stockpile.get_at_tile(tid, lithium) == after,
		"Unload takes every lithium cell back into stock")
	# The cells loaded again, and a turn played: the bank now reads what the new cells backed, the balance's
	# wind and solar readout says nothing ran short, and the cut short case is gone if the bank covered it.
	Power.load_battery_cells(tid, lithium, Stockpile.get_at_tile(tid, lithium))
	await _turns(1)
	panel.call("show_tile", td, "power")
	await _settle(8)
	var im2: Dictionary = Production.get_tile_intermittency(tid)
	var read2: Dictionary = PT.bank_reading(tid, im2)
	print("[TVP_SHOT] green after a turn with %d MW loaded: im %s, bank reads %s" % [Power.tile_firming_cap(tid), str(im2), str(read2)])
	var node2: Node = panel.find_child("Readout_Bank", true, false)
	_check(node2 != null and (node2.find_child("Words", true, false) as Label).text == str(read2.words)
		and int(im2.get("battery_cap", 0)) == Power.tile_firming_cap(tid) and not str(read2.words).contains("From next turn"),
		"a turn later the bank reads what the loaded cells firmed (%s)" % str(read2.words))
	await _scenario_checks(panel, tid, "green_next", ["ok"])
	_save(panel.get_global_rect().grow(16.0), "tvp_v3_power_green_next")
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	await _settle(4)
	_save(panel.get_global_rect().grow(16.0), "tvp_v3_power_green_next_foot")
	if deficit != "":
		var dd: Dictionary = terrain.tiles.get(terrain.id_to_coord(deficit), {"id": deficit})
		panel.call("show_tile", dd, "power")
		await _settle(6)
		var reduce: Node = panel.find_child("PowerReduceKey", true, false)
		_check(reduce != null and panel.find_child("PowerIntermittency", true, false).find_child("PowerReduceKey", true, false) != null,
			"with no battery storage, Reduce intermittency stands beside the verdict")
		if reduce != null:
			reduce.emit_signal("pressed")
			await _settle(4)
			_check(cp.visible and str(cp.get("_search_query")) == "Battery" and str(cp.get("_locked_tile_id")) == deficit,
				"Reduce intermittency opens Construct on this tile's batteries")
			cp.hide()
			PanelStack.remove(cp)
	if bare != "":
		var bd: Dictionary = terrain.tiles.get(terrain.id_to_coord(bare), {"id": bare})
		panel.call("show_tile", bd, "power")
		await _settle(4)
		panel.find_child("PowerCablesKey", true, false).emit_signal("pressed")
		await _settle(2)
		_check(str(panel.get("_active_tab")) == "transport", "the cables' Build key opens the Transport tab")


## One scenario's own checks, on the tile the panel shows: the intermittency row's lamp and words against
## its reading (and `expected`, the tones the scenario should show), no seven segment LED on the tab (money
## only, and the tab shows none), keys one width within a row, and nothing overlapping. Then the row in both
## phases of its lamp, when it flashes.
func _scenario_checks(panel: Control, tid: String, scenario: String, expected: Variant) -> void:
	var PT: GDScript = load("res://scripts/tvp_v3/power_tab.gd")
	var pane: Control = (panel.get("_panes") as Dictionary).get("power")
	var power: Dictionary = (load("res://scripts/tile_view_data.gd") as GDScript).power_summary(tid)
	var im: Dictionary = Production.get_tile_intermittency(tid)
	var row: Control = pane.find_child("Readout_Intermittency", true, false)
	if int(power.produced) > 0 or int(power.consumed) > 0:
		var r: Dictionary = PT.intermittency_reading(tid, power, im)
		var lamp: Control = row.find_child("Lamp", true, false) if row != null else null
		var shown: Array = lamp.call("tones") if lamp != null else []
		var want: Array = r.cycle if not (r.cycle as Array).is_empty() else [Lamp.colour_for(str(r.tone))]
		var words: String = (row.find_child("Words", true, false) as Label).text if row != null else ""
		_check(row != null and shown == want and words == str(r.words),
			"%s: the intermittency row's lamp shows %s and its words are its reading's (%s)" % [scenario, str(shown), words.replace("\n", " / ")])
		if lamp != null and shown.size() == 1:
			_check(not lamp.is_processing(), "%s: the steady intermittency lamp runs no flash (scripts/ds2/flash_lamp.gd)" % scenario)
		if expected != null:
			var exp: Array = expected
			var exp_shown: Array = exp if exp.size() > 1 else [Lamp.colour_for(str(exp[0]))]
			_check(shown == exp_shown, "%s: the intermittency lamp is %s, as the scenario expects (%s)" % [scenario, str(shown), str(exp_shown)])
		# The row sits right under the national grid's.
		var grid: Control = pane.find_child("Readout_Nationalgrid", true, false)
		_check(grid != null and row != null and row.get_parent() == grid.get_parent() and row.get_index() == grid.get_index() + 1,
			"%s: intermittency is the row under the national grid" % scenario)
		var grid_label: Label = grid.find_child("Words", true, false) as Label if grid != null else null
		var grid_words: String = grid_label.text if grid_label != null else ""
		print("[TVP_SHOT] %s: national grid reads: %s" % [scenario, grid_words])
		# The owner's words, what the tile sold and bought, with the engine's figures.
		var want_words := _grid_expected(scenario, tid)
		if want_words != "":
			_check(grid_words == want_words, "%s: the national grid reads the sentence it should (%s)" % [scenario, want_words])
		_check(grid_words.ends_with(".") and grid_label != null and grid_label.get_line_count() == grid_words.count("."),
			"%s: the national grid is a line a sentence (%d)" % [scenario, grid_label.get_line_count() if grid_label != null else -1])
		var cables: Control = pane.find_child("Readout_Cables", true, false)
		print("[TVP_SHOT] %s: cables read: %s" % [scenario, (cables.find_child("Words", true, false) as Label).text if cables != null else "(none)"])
	else:
		_check(row == null, "%s: an idle tile shows no intermittency row" % scenario)
	var leds := 0
	for n: Node in pane.find_children("*", "Control", true, false):
		var sc: Script = n.get_script()
		if sc != null and sc.resource_path.ends_with("bdp_v3_led.gd"):
			leds += 1
	_check(leds == 0, "%s: no seven segment LED on the tab (%d)" % [scenario, leds])
	_check_key_rows(pane, scenario)
	_check_overlaps(panel, pane, scenario)
	if row != null and (row.find_child("Lamp", true, false).call("tones") as Array).size() > 1:
		var scroll: ScrollContainer = panel.find_child("BodyScroll", true, false)
		scroll.ensure_control_visible(row)
		await _settle(4)
		# Sampled every quarter second through one cycle: each tone lasts half of it, so both show, and the
		# first sight of each is saved.
		var lamp: Control = row.find_child("Lamp", true, false)
		var seen := {}
		var t0 := Time.get_ticks_msec()
		for _i in 7:
			var tone := str(lamp.get("colour"))
			if not seen.has(tone):
				seen[tone] = Time.get_ticks_msec() - t0
				_save(row.get_global_rect().grow(10.0), "tvp_v3_power_%s_flash_%s" % [scenario, "ab"[mini(seen.size() - 1, 1)]])
			await get_tree().create_timer(0.25).timeout
			await _settle(1)
		_check(seen.size() == 2, "%s: the intermittency lamp flashes between two tones over the %.1f s cycle (%s)" % [scenario,
			float(lamp.get("_period")), str(seen)])
		scroll.scroll_vertical = 0
		await _settle(2)


## The national grid sentence a scenario should read, with the engine's figures for its tile ("" for none):
## each of the owner's patterns, and the forms that join them, on the tile staged to show it.
func _grid_expected(scenario: String, tid: String) -> String:
	var made := int(Power.tile_produced.get(tid, 0))
	var drawn := int(Power.tile_drawn.get(tid, 0))
	var settled: Dictionary = Power.get("_tile_grid_draw")
	var from_grid := int(settled.get(tid, 0))
	var sold := "%d MW sold to the national grid."
	var bought := "%d MW bought from the national grid."
	var none := "Nothing sold to or bought from the national grid."
	match scenario:
		"busygrid", "mixedgrid":
			return "\n".join([sold % made, bought % drawn])
		"producergrid":
			return sold % made
		"fedgrid":
			return bought % drawn
		"busy", "green", "green_next", "fed":
			return none
		"deficit", "mixed":
			return bought % from_grid
		"producer":
			var used := int(Power.tile_drawn.get(str(_staged.get("fed", "")), 0))
			return sold % (made - used)
	return ""


## The intermittency lamp's rule on made up figures, each of the owner's four states and the two cases a
## tile's own figures cannot show while the game sets wind and solar's priority for every plant at once: a
## tile with wind sold to the grid and wind running first, all of that firmed; and a tile selling all its
## own wind while its buildings consume unfirmed wind from elsewhere.
func _verdict_checks() -> void:
	var PT: GDScript = load("res://scripts/tvp_v3/power_tab.gd")
	var cases := [
		["none", {"made": 0, "drawn": 100}, ["ok"], "none"],
		["all firmed", {"made": 200, "drawn": 150, "made_int": 200, "self_int": 200, "firmed_made": 200, "used_made": true,
			"drawn_int": 150.0, "unfirmed_drawn": 0.0}, ["ok"], "made"],
		["sold to the grid", {"made": 200, "drawn": 0, "made_int": 200, "self_int": 0}, ["warn", "ok"], "made"],
		["partly firmed and used", {"made": 200, "drawn": 150, "made_int": 200, "self_int": 200, "firmed_made": 80,
			"used_made": true, "drawn_int": 150.0, "unfirmed_drawn": 70.0}, ["warn", "bad"], "made"],
		["unfirmed and used", {"made": 200, "drawn": 150, "made_int": 200, "self_int": 200, "firmed_made": 0,
			"used_made": true, "drawn_int": 150.0, "unfirmed_drawn": 150.0}, ["bad"], "made"],
		["running first, fully firmed, the rest sold", {"made": 200, "drawn": 100, "made_int": 200, "self_int": 100,
			"firmed_made": 100, "used_made": true, "drawn_int": 100.0, "unfirmed_drawn": 0.0}, ["warn", "ok"], "made"],
		["own wind sold, unfirmed wind consumed from elsewhere", {"made": 100, "drawn": 80, "made_int": 100, "self_int": 0,
			"drawn_int": 80.0, "unfirmed_drawn": 80.0}, ["bad"], "drawn"],
		["own wind sold, wind from elsewhere partly firmed", {"made": 100, "drawn": 80, "made_int": 100, "self_int": 0,
			"drawn_int": 80.0, "unfirmed_drawn": 30.0}, ["warn", "bad"], "drawn"],
		["running first but reaching none of yours", {"made": 200, "drawn": 0, "made_int": 200, "self_int": 200,
			"firmed_made": 50, "used_made": false}, ["warn", "ok"], "made"],
	]
	for c: Array in cases:
		var r: Dictionary = PT.intermittency_verdict(c[1])
		var shown: Array = r.cycle if not (r.cycle as Array).is_empty() else [str(r.tone)]
		_check(shown == c[2] and str(r.side) == str(c[3]) and str(r.words).ends_with("."),
			"intermittency rule, %s: %s on the %s side (%s)" % [c[0], str(shown), str(r.side), str(r.words).replace("\n", " / ")])


## Every row of cabinet keys on the tab: the keys that stand side by side in one row are one width.
func _check_key_rows(pane: Control, scenario: String) -> void:
	var rows := {}
	for n: Node in pane.find_children("*", "Control", true, false):
		var sc: Script = n.get_script()
		if sc == null or not sc.resource_path.ends_with("latch_key.gd"):
			continue
		var parent := n.get_parent()
		if parent is HBoxContainer:
			var widths: Array = rows.get(parent, [])
			widths.append(roundi((n as Control).size.x))
			rows[parent] = widths
	var bad: PackedStringArray = []
	for parent: Node in rows:
		var widths: Array = rows[parent]
		if widths.size() > 1 and widths.min() != widths.max():
			bad.append("%s %s" % [parent.name, str(widths)])
	_check(bad.is_empty(), "%s: keys side by side in a row are one width%s" % [scenario,
		(" (" + ", ".join(bad) + ")") if not bad.is_empty() else ""])


## Nothing overlaps or touches: each case (a section's frame or plate, a module, a glass readout, a screen,
## the bank, a key, an icon's well) stays inside its parent case's rim and screws and at least a pixel clear
## of the cases beside it; each section's drawn edge (the steel frame's rim, the plastic case's edge) stays
## inside the body's scroll (the sheet's 22 px padding and rim lie outside it) and SHEET_CLEAR clear of the
## scrollbar when it shows; and the sections' drawn edges line up.
func _check_overlaps(panel: Control, pane: Control, scenario: String) -> void:
	var cases: Array[Control] = []
	for n: Node in pane.find_children("*", "Control", true, false):
		if n is Control and (n as Control).is_visible_in_tree() and _case_rim(n as Control) >= 0.0:
			cases.append(n as Control)
	var issues: PackedStringArray = []
	var scroll: ScrollContainer = panel.find_child("BodyScroll", true, false)
	var sheet := scroll.get_global_rect()
	var bar := scroll.get_v_scroll_bar()
	var right := sheet.end.x - (bar.size.x if bar.visible else 0.0)
	var lefts: Array = []
	var rights: Array = []
	var tightest := INF
	for c in cases:
		var rect := c.get_global_rect()
		var parent := _parent_case(c, cases)
		if parent == null:
			var drawn := _drawn_rect(c)
			lefts.append(drawn.position.x)
			rights.append(drawn.end.x)
			if bar.visible:
				tightest = minf(tightest, right - drawn.end.x)
			if drawn.position.x < sheet.position.x - 0.5 or drawn.end.x > (right - SHEET_CLEAR if bar.visible else sheet.end.x + 0.5):
				issues.append("%s's edge outside the sheet's room or within %.0f px of its scrollbar (%.1f to %.1f of %.0f to %.0f)" % [
					c.name, SHEET_CLEAR, drawn.position.x, drawn.end.x, sheet.position.x, right])
		else:
			var inner := parent.get_global_rect().grow(-_case_rim(parent))
			if not inner.grow(0.5).encloses(rect):
				issues.append("%s over %s's rim" % [c.name, parent.name])
		for o in cases:
			if o.get_instance_id() <= c.get_instance_id() or _parent_case(o, cases) != parent:
				continue
			if o.is_ancestor_of(c) or c.is_ancestor_of(o):
				continue
			if rect.grow(0.5).intersects(o.get_global_rect().grow(0.5)):
				issues.append("%s touches %s" % [c.name, o.name])
	if lefts.size() > 1 and (float(lefts.max()) - float(lefts.min()) > 1.0 or float(rights.max()) - float(rights.min()) > 1.0):
		issues.append("the sections' edges do not line up (left %s, right %s)" % [str(lefts), str(rights)])
	var clear := ("the sections %.1f px or more clear of the scrollbar" % tightest) if tightest < INF else "no scrollbar"
	_check(issues.is_empty(), "%s: nothing overlaps or touches (%d cases, %s)%s" % [scenario, cases.size(), clear,
		(": " + ", ".join(issues.slice(0, 6))) if not issues.is_empty() else ""])


## Where a section's case is drawn: the steel frame's rim inside its rect (STEEL_RIM_IN), the plastic case's
## render (PLASTIC_RIM_IN).
func _drawn_rect(c: Control) -> Rect2:
	var rect := c.get_global_rect()
	var sc: Script = c.get_script()
	if sc != null and sc.resource_path.ends_with("bdp_v3_section.gd"):
		var inset := PLASTIC_RIM_IN if str(c.get("style")) == "plastic" else STEEL_RIM_IN
		rect.position.x += inset.x
		rect.size.x -= inset.x + inset.y
	return rect


## A case's rim, the room its own parts take round its inside edge (its frame, its screws, its bezel), or -1
## for a control that is not a case.
func _case_rim(c: Control) -> float:
	var sc: Script = c.get_script()
	var path := sc.resource_path if sc != null else ""
	if path.ends_with("bdp_v3_section.gd"):
		# The steel frame's rim (26 layout px), or the plastic plate's screws (their centres 9 px in).
		return 14.0
	if path.ends_with("bdp_v3_readout.gd") or path.ends_with("dot_matrix.gd") or path.ends_with("power_bank.gd"):
		return 3.0
	if path.ends_with("latch_key.gd") or path.ends_with("bdp_v3_key.gd"):
		return 0.0
	if str(c.name).begins_with("CutShort_"):
		return 2.0
	if str(c.name) == "IconWell":
		return 0.0
	return -1.0


## The case a case sits in: its nearest ancestor among the cases, or null.
func _parent_case(c: Control, cases: Array[Control]) -> Control:
	var up := c.get_parent()
	while up != null:
		if up is Control and cases.has(up):
			return up as Control
		up = up.get_parent()
	return null


## The names of the cabinet keys under a node.
func _keys_under(root: Node) -> Array:
	var out: Array = []
	if root == null:
		return out
	for n: Node in root.find_children("*", "Control", true, false):
		var sc: Script = n.get_script()
		if sc != null and sc.resource_path.ends_with("latch_key.gd"):
			out.append(str(n.name))
	return out


## The meter alone with many kinds of building on it, to see its tags give up their emblems, then their
## names.
func _crowd() -> void:
	var Meter: GDScript = load("res://scripts/tvp_v3/power_meter.gd")
	var layer := CanvasLayer.new()
	layer.layer = 100
	_vp.add_child(layer)
	var bids := ["b_007", "b_008", "b_009", "b_010", "b_011", "b_012", "b_019", "b_030", "b_031", "b_020"]
	var names := ["Steel", "Motor", "Glass", "Aluminium", "Copper Wiring", "Plastics", "Chemicals", "Cement", "Paper", "Ingots"]
	for n in [4, 6, 8, 10]:
		var holder := PanelContainer.new()
		var st := StyleBoxFlat.new()
		st.bg_color = Color("#1b1d21")
		st.set_content_margin_all(12)
		holder.add_theme_stylebox_override("panel", st)
		holder.position = Vector2(100, 100)
		holder.custom_minimum_size = Vector2(551, 0)
		layer.add_child(holder)
		var m: Control = Meter.new()
		holder.add_child(m)
		var drawn: Array = []
		var total := 0
		for i in n:
			var v: int = 20 + (i * 37) % 60
			total += v
			drawn.append({"name": names[i], "short": names[i], "value": float(v), "count": 1 + i % 2, "iid": "", "building_id": bids[i]})
		m.call("set_reading", [{"name": "Solar Farm", "short": "Solar Farm", "value": 120.0, "count": 1, "iid": "", "building_id": "b_024"}],
			drawn, 120, total, 120 - total, "warn")
		await _settle(6)
		_save(holder.get_global_rect().grow(8.0), "tvp_v3_power_crowd_%d" % n)
		holder.queue_free()
		await _settle(2)
	layer.queue_free()


func _check(ok: bool, what: String) -> void:
	print("[TVP_SHOT] %s %s" % ["PASS" if ok else "FAIL", what])


func _turns(n: int) -> void:
	for _i in n:
		_feed()
		TurnManager.commit_turn()
		if TurnManager.is_resolving:
			await TurnManager.turn_resolution_completed
	for c in _wm.find_children("*", "PanelContainer", true, false):
		var sc: Script = c.get_script()
		if sc != null and sc.resource_path.ends_with("capacity_dialog.gd"):
			(c as Control).hide()
	await _settle(10)


## Tops up and drains the staged tiles' stock (_keep, _drain) before a turn.
func _feed() -> void:
	for t: String in _drain:
		for g: String in _drain[t]:
			Stockpile.consume(t, g, Stockpile.get_at_tile(t, g))
	for t: String in _keep:
		for g: String in _keep[t]:
			var short := int(_keep[t][g]) - Stockpile.get_at_tile(t, g)
			if short > 0:
				Stockpile.add(t, g, short)


## A tile to stage on: no cables and no buildings yet, not one already taken, land you could build on.
func _pick_tile(terrain: Node, not_these: Array) -> String:
	if terrain == null:
		return ""
	var best := ""
	var best_d := 1e9
	var home: Vector2i = terrain.id_to_coord(BUSY)
	for coord: Vector2i in terrain.tiles.keys():
		var td: Dictionary = terrain.tiles[coord]
		var tid := str(td.get("id", ""))
		if tid == "" or not_these.has(tid):
			continue
		if str(td.get("type", "")) not in ["rural", "urban", "hill"]:
			continue
		if (td.get("infrastructure_present", []) as Array).has("cables"):
			continue
		if not BuildingState.get_buildings_on_tile(tid).is_empty():
			continue
		var d := float((coord - home).length_squared())
		if d < best_d:
			best_d = d
			best = tid
	return best


## Two neighbouring tiles to stage a network of their own on: land you could build on, no cables or
## buildings, no cabled tile beside either but the other, APART hexes from the tiles in `far` and NEAR
## from those in `near`; the first, the plant's, with an id sorting after `after`.
func _pick_pair(terrain: Node, far: Array, near: Array, after: String) -> Array:
	if terrain == null:
		return []
	var best: Array = []
	var best_d := 1e9
	for coord: Vector2i in terrain.tiles.keys():
		var a := str((terrain.tiles[coord] as Dictionary).get("id", ""))
		if a <= after or not _stageable(terrain, a, far, near, []):
			continue
		var d := float(Catalog.tile_hex_distance(BUSY, a))
		if d >= best_d:
			continue
		for nc: Vector2i in Power.call("_neighbor_coords", coord):
			var b := str((terrain.tiles.get(nc, {}) as Dictionary).get("id", ""))
			if b != "" and _stageable(terrain, b, far, near, [a]) and _stageable(terrain, a, far, near, [b]):
				best = [a, b]
				best_d = d
				break
	return best


## One tile to stage a network of its own on, by the same rules.
func _pick_isolated(terrain: Node, far: Array, near: Array, after: String) -> String:
	if terrain == null:
		return ""
	var best := ""
	var best_d := 1e9
	for coord: Vector2i in terrain.tiles.keys():
		var a := str((terrain.tiles[coord] as Dictionary).get("id", ""))
		var d := float(Catalog.tile_hex_distance(BUSY, a))
		if d < best_d and a > after and _stageable(terrain, a, far, near, []):
			best = a
			best_d = d
	return best


## Whether a tile can hold a staged network of its own: buildable land with no buildings, APART hexes from
## every tile in `far` and NEAR from every tile in `near` (non empty ids), and no cable network through it or
## beside it but `with`'s unless that network is quiet (no building of yours on it and no staged tile): a
## quiet network settles as part of the staged one without changing its figures.
func _stageable(terrain: Node, tid: String, far: Array, near: Array, with: Array) -> bool:
	if tid == "" or far.has(tid) or near.has(tid):
		return false
	var td: Dictionary = terrain.tiles.get(terrain.id_to_coord(tid), {})
	if str(td.get("type", "")) not in ["rural", "urban", "hill"]:
		return false
	if not BuildingState.get_buildings_on_tile(tid).is_empty():
		return false
	if (td.get("infrastructure_present", []) as Array).has("cables") and not _quiet_network(tid, far + near):
		return false
	for t: String in far:
		if t != "" and Catalog.tile_hex_distance(t, tid) < APART:
			return false
	for t: String in near:
		if t != "" and Catalog.tile_hex_distance(t, tid) < NEAR:
			return false
	for nc: Vector2i in Power.call("_neighbor_coords", terrain.id_to_coord(tid)):
		var nd: Dictionary = terrain.tiles.get(nc, {})
		var nid := str(nd.get("id", ""))
		if nid == "" or with.has(nid):
			continue
		if (nd.get("infrastructure_present", []) as Array).has("cables") and not _quiet_network(nid, far + near):
			return false
	return true


## Whether the cable network through a cabled tile holds no building of yours and none of `staged`.
func _quiet_network(tid: String, staged: Array) -> bool:
	var cabled: Dictionary = Power.call("_cabled_tile_set")
	for t: String in Power.call("_cable_component", tid, cabled, {}):
		if staged.has(t):
			return false
		for b: Dictionary in BuildingState.get_buildings_on_tile(t):
			if BuildingState.is_player_owned(b):
				return false
	return true


## Level 1 cables on a staged tile, in the map's own tile record (what Power reads).
func _lay_cables(terrain: Node, tid: String) -> void:
	if terrain == null or tid == "":
		return
	var td: Dictionary = terrain.tiles.get(terrain.id_to_coord(tid), {})
	var present: Array = td.get("infrastructure_present", [])
	if not present.has("cables"):
		present.append("cables")
	td["infrastructure_present"] = present
	var levels: Dictionary = td.get("infrastructure_levels", {})
	levels["cables"] = 1
	td["infrastructure_levels"] = levels


func _shoot(panel: Control, terrain: Node, tid: String, tag: String) -> void:
	var td: Dictionary = {"id": tid}
	if terrain != null and terrain.has_method("id_to_coord"):
		td = terrain.tiles.get(terrain.id_to_coord(tid), td)
	panel.call("show_tile", td, "power")
	await _settle(12)
	var scroll: ScrollContainer = panel.find_child("BodyScroll", true, false)
	if scroll != null:
		scroll.scroll_vertical = 0
	await _settle(6)
	var page := 1
	var step := maxf(80.0, scroll.size.y - 60.0) if scroll != null else 0.0
	while page <= 5:
		_save(panel.get_global_rect().grow(16.0), "%s_p%d" % [tag, page])
		if scroll == null or scroll.scroll_vertical + scroll.size.y >= scroll.get_v_scroll_bar().max_value - 1.0:
			break
		scroll.scroll_vertical = int(scroll.scroll_vertical + step)
		await _settle(4)
		page += 1


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
