extends Node2D
## Captures of the tile view v3's Power tab (scripts/tvp_v3/power_tab.gd), in the real HUD at 1920 × 1080
## (two pixels each), cropped to the panel. After three turns of play:
##   busy     the standard busy port tile (two factories and a wind farm, as tools/tvp_v3_shot.gd sets it)
##   green    a cabled tile with a solar farm running first, factories drawing on it, and battery storage
##            with two lithium cells loaded and more in stock: intermittency and the bank
##   deficit  a cabled tile with factories and no plant: power from the grid
##   nocables a tile with a factory and no cables
##   empty    the empty unowned mountain tile
## Each is paged down its whole body: tvp_v3_power_<scenario>_p1.png, _p2 ... Then the checks (what the keys
## do, the figures against the engine's, each lamp against its reading and the Power key, the layout's
## rules) print PASS or FAIL, with green_loaded (cells just loaded), green_next (a turn later, the bank
## reading what the new cells backed) and the meter alone with 4 to 10 kinds of building (crowd_N).
##   Godot --path . res://tools/tvp_v3_power_shot.tscn --quit-after 30000 -- --no-telemetry
## Writes into $TVP_SHOT_DIR (or /tmp).

const LOGICAL := Vector2i(1920, 1080)
const BUSY := "tile_5_10"
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
	var terrain: Node = _wm.get("terrain_layer")

	# Staged tiles near the busy one: two given cables here (the capture's own staging, not saved), one left
	# without.
	var green := _pick_tile(terrain, [BUSY])
	var deficit := _pick_tile(terrain, [BUSY, green])
	var bare := _pick_tile(terrain, [BUSY, green, deficit])
	for tid in [green, deficit]:
		_lay_cables(terrain, tid)
	print("[TVP_SHOT] tiles busy=%s green=%s deficit=%s nocables=%s" % [BUSY, green, deficit, bare])

	MatchState.money = 50000.0
	var steel := str(Catalog.get_good_by_internal_name("steel").get("id", ""))
	var wiring := str(Catalog.get_good_by_internal_name("copper_wiring").get("id", ""))
	var ingots := str(Catalog.get_good_by_internal_name("iron_ingots").get("id", ""))
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
	var wanted := only.split(",") if only != "" else PackedStringArray(["busygrid", "busy", "green", "deficit", "nocables", "empty"])
	# First with wind and solar selling to the grid (the game's default): the busy tile as a new player sees it.
	await _turns(3)
	if wanted.has("busygrid"):
		UiPrefs.set_use_tvp_v3(true)
		await _settle(6)
		await _shoot(panel, terrain, BUSY, "tvp_v3_power_busygrid")
		UiPrefs.set_use_tvp_v3(false)
	# Then with wind and solar running first for your own buildings: intermittency.
	MatchState.set_power_priority("wind_solar", "self")
	await _turns(3)
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
	var tiles := {"busy": BUSY, "green": green, "deficit": deficit, "nocables": bare, "empty": EMPTY_TILE}
	for scenario: String in wanted:
		var tid := str(tiles.get(scenario, ""))
		if tid == "":
			continue
		var im: Dictionary = Production.get_tile_intermittency(tid)
		print("[TVP_SHOT] %s: made %d drawn %d cap %d im %s" % [scenario, int(Power.tile_produced.get(tid, 0)),
			int(Power.tile_drawn.get(tid, 0)), Power.tile_power_cap(tid), str(im)])
		await _shoot(panel, terrain, tid, "tvp_v3_power_%s" % scenario)
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
	for t: String in [BUSY, tid, deficit, bare, EMPTY_TILE]:
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
		var key_tone: String = {"warn": "amber", "problem": "red"}.get(str(power.status), "off")
		var grid: Node = plate.find_child("Readout_Nationalgrid", true, false)
		if bool(power.connected):
			var reading: Dictionary = PowerTab.grid_reading(t, power)
			var lamp: String = str(grid.find_child("Lamp", true, false).get("colour")) if grid != null else "?"
			var words: String = (grid.find_child("Words", true, false) as Label).text if grid != null else ""
			_check(grid != null and words == str(reading.words) and (key_tone == "off" or lamp == key_tone),
				"%s: the grid lamp (%s) agrees with the Power key (%s), and its words are its reading's" % [t, lamp, key_tone])
			if lamp == "amber":
				_check(words.begins_with("Draws "), "%s: an amber grid lamp says the tile draws more than it makes" % t)
		else:
			_check(grid == null, "%s: no grid readout on a tile with no cables" % t)
		var cables: Node = plate.find_child("Readout_Cables", true, false)
		if Power.tile_power_cap(t) <= 0 and cables != null:
			var lamp: String = str(cables.find_child("Lamp", true, false).get("colour"))
			_check(lamp == key_tone, "%s: with no cables, the cables lamp (%s) is the Power key's (%s)" % [t, lamp, key_tone])
		if t == bare:
			var words: String = (cables.find_child("Words", true, false) as Label).text
			_check(words.contains("cannot run without them") and plate.find_child("PowerCablesKey", true, false) != null
				and plate.find_child("PowerMeter", true, false) == null,
				"no cables: the readout names what cannot run (%s), with Add cables, and no meter" % words)
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
	var tags: Array = meter.get("_tags")
	_check((tags[1] as Array).size() == (meter.get("rows") as Array)[1].slices.size() and str((tags[1] as Array)[0].mode) == "both",
		"every drawn slice has a tag with its emblem and name")
	var build: Control = panel.find_child("PowerBuildKey", true, false)
	var made_led: Control = meter.find_child("MadeFigure", true, false)
	_check(build.get_parent() == meter and absf(build.get_global_rect().end.x - made_led.get_global_rect().end.x) < 40.0
		and build.get_global_rect().end.y <= made_led.get_global_rect().position.y,
		"Build power stands over the MADE figure")
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
		and str(bank_read.words).begins_with("Backed %d of the %d MW" % [int(im.battery_cap), int(im.green_intermittent_produced)])
		and str(bank_node.find_child("Lamp", true, false).get("colour")) == "amber",
		"the bank's readout says what it backed last turn (%s), amber while buildings here were cut short" % str(bank_read.words))
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
	var loaded_fig: String = str(panel.find_child("LoadedFigure", true, false).call("figure")).strip_edges()
	_check(bank_words.contains("From next turn it backs up %d MW" % Power.tile_firming_cap(tid)) and loaded_fig == str(Power.tile_firming_cap(tid))
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
		"a turn later the bank reads what the loaded cells backed (%s)" % str(read2.words))
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
		_check(str(panel.get("_active_tab")) == "transport", "Add cables opens the Transport tab")


## The names of the cabinet keys under a node.
func _keys_under(root: Node) -> Array:
	var out: Array = []
	if root == null:
		return out
	for n: Node in root.find_children("*", "Control", true, false):
		var sc: Script = n.get_script()
		if sc != null and sc.resource_path.ends_with("tile_cabinet_key.gd"):
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
			drawn, 120, total, 120 - total, 4, [DS.PALETTE.OK, DS.PALETTE.DANGER, DS.PALETTE.WARN])
		await _settle(6)
		_save(holder.get_global_rect().grow(8.0), "tvp_v3_power_crowd_%d" % n)
		holder.queue_free()
		await _settle(2)
	layer.queue_free()


func _check(ok: bool, what: String) -> void:
	print("[TVP_SHOT] %s %s" % ["PASS" if ok else "FAIL", what])


func _turns(n: int) -> void:
	for _i in n:
		TurnManager.commit_turn()
		if TurnManager.is_resolving:
			await TurnManager.turn_resolution_completed
	for c in _wm.find_children("*", "PanelContainer", true, false):
		var sc: Script = c.get_script()
		if sc != null and sc.resource_path.ends_with("capacity_dialog.gd"):
			(c as Control).hide()
	await _settle(10)


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
