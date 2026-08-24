extends Node
## Dev tool: time the "sell to market" path, to find the 3-4 second freeze a playtester hit
## when clicking "Sell surplus to market" on the capacity dialog.
##   Godot --headless --path . res://tools/sell_freeze_probe.tscn --quit-after 1200
## Times each suspect COLD (first call, caches empty) and WARM, because Catalog's route cache
## is cleared whenever the network changes — so the first sale after building a road pays for
## everything the cache had memoised.

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(120)

	# A fresh boot of main.tscn has no player estate (a match starts from the menu), so seed
	# one — the tiles and the road network are real either way, which is what the timings need.
	if _a_player_tile() == "":
		var seed_tiles := ["tile_5_9", "tile_5_10", "tile_6_9", "tile_6_10", "tile_7_9",
			"tile_7_10", "tile_4_9", "tile_8_10"]
		for i in seed_tiles.size():
			MatchState.add_building("b_001", "r_001", str(seed_tiles[i]), "player_1",
				"probe_%d" % i, false)
	var tile := _a_player_tile()
	if tile == "":
		print("[SELL] no player tile — aborting")
		get_tree().quit(1)
		return
	var good := "g_001"
	print("[SELL] tile=%s good=%s" % [tile, good])

	_time("Catalog.nearest_port_tile (cold)", func() -> void:
		Catalog.nearest_port_tile(tile), true)
	_time("Catalog.nearest_port_tile (warm x50)", func() -> void:
		for _i in 50:
			Catalog.nearest_port_tile(tile), false)

	_time("TransportService.route_to_nearest_port (cold)", func() -> void:
		TransportService.route_to_nearest_port(tile, good), true)
	_time("TransportService.route_to_nearest_port (warm x50)", func() -> void:
		for _i in 50:
			TransportService.route_to_nearest_port(tile, good), false)

	_time("MatchState.warehouse_upgrade_quote (cold)", func() -> void:
		MatchState.warehouse_upgrade_quote(tile), true)
	_time("MatchState.warehouse_upgrade_quote (warm x10)", func() -> void:
		for _i in 10:
			MatchState.warehouse_upgrade_quote(tile), false)

	_time("Stockpile.get_total (warm x50)", func() -> void:
		for _i in 50:
			Stockpile.get_total(good), false)

	# The whole action the dialog runs, on a tile that actually has something to sell.
	Stockpile.add(tile, good, 50)
	_time("MarketState.execute_sale (cold)", func() -> void:
		MarketState.execute_sale(tile, {good: 10}), true)
	_time("MarketState.execute_sale (warm)", func() -> void:
		MarketState.execute_sale(tile, {good: 10}), false)

	# ...and the same after the route cache is dropped, which is what a road build does.
	Catalog._route_cache.clear()
	_time("execute_sale AFTER a route-cache clear", func() -> void:
		MarketState.execute_sale(tile, {good: 10}), false)

	# The capacity dialog's own per-tile refresh, over every player tile — the shape of
	# "apply to all tiles".
	var tiles := _player_tiles()
	print("[SELL] player tiles: %d" % tiles.size())
	Catalog._route_cache.clear()
	_time("warehouse_upgrade_quote over EVERY player tile, cache cold", func() -> void:
		for t: String in tiles:
			MatchState.warehouse_upgrade_quote(t), false)

	# The sale itself is cheap. The suspicion is the FAN-OUT: stockpile_changed carries no
	# argument, so every listener rebuilds on every mutation, and one sale mutates once per
	# good. Count the listeners, then time one emission with the real panels alive.
	var listeners := Stockpile.stockpile_changed.get_connections().size()
	print("[SELL] stockpile_changed listeners: %d" % listeners)
	_time("one bare stockpile_changed.emit()", func() -> void:
		Stockpile.stockpile_changed.emit(), false)
	_time("20 emissions (a 20-good sale)", func() -> void:
		for _i in 20:
			Stockpile.stockpile_changed.emit(), false)

	# Now with the panels a mid-game player actually has open.
	for panel_name: String in ["ResourcePanel", "TileInfoPanelV2", "TransportPanel",
			"StockpileOverlay", "StockpileView"]:
		var n: Node = game.find_child(panel_name, true, false)
		if n != null and n is CanvasItem:
			(n as CanvasItem).visible = true
	await _settle(10)
	print("[SELL] listeners after opening panels: %d" % Stockpile.stockpile_changed.get_connections().size())
	_time("20 emissions, panels visible", func() -> void:
		for _i in 20:
			Stockpile.stockpile_changed.emit(), false)

	# The capacity dialog appears DURING turn resolution, so "3-4 s before it moved on" may
	# simply be the rest of the turn. Time a few, with a real estate on the map.
	# How many times does ONE surplus sale publish a change? Every publish rebuilds ~80
	# listeners in full, so this number IS the freeze.
	var fires := {"n": 0}
	Stockpile.stockpile_changed.connect(func() -> void: fires["n"] = int(fires["n"]) + 1)
	var manifest: Dictionary = {}
	for gid: String in ["g_001", "g_002", "g_003", "g_004", "g_005",
			"g_006", "g_007", "g_008", "g_009", "g_010"]:
		Stockpile.add(tile, gid, 40)
		manifest[gid] = 20
	await _settle(2)
	fires["n"] = 0
	MarketState.execute_sale(tile, manifest)
	print("[SELL] publishes DURING a 10-good sale: %d" % int(fires["n"]))
	await _settle(2)
	print("[SELL] publishes after the frame ends:   %d" % int(fires["n"]))

	# Per-phase, so the cost is localised rather than just observed.
	var phase_us: Dictionary = {}
	var phase_t0 := {"v": 0}
	TurnManager.phase_started.connect(func(_p: int) -> void:
		phase_t0["v"] = Time.get_ticks_usec())
	TurnManager.phase_completed.connect(func(ph: int) -> void:
		phase_us[ph] = int(phase_us.get(ph, 0)) + (Time.get_ticks_usec() - int(phase_t0["v"])))
	for i in 4:
		var t0 := Time.get_ticks_usec()
		TurnManager.commit_turn()
		await TurnManager.turn_resolution_completed
		print("[SELL] turn %d resolution %8.2f ms" % [
			i + 1, float(Time.get_ticks_usec() - t0) / 1000.0])
		await _settle(2)
	var names := {TurnManager.Phase.PROCESS: "PROCESS", TurnManager.Phase.SEND: "SEND",
		TurnManager.Phase.AI: "AI", TurnManager.Phase.NARRATIVE: "NARRATIVE",
		TurnManager.Phase.RECEIVE: "RECEIVE"}
	for ph in phase_us:
		print("[SELL] phase %-10s %8.2f ms over 4 turns" % [
			str(names.get(ph, ph)), float(phase_us[ph]) / 1000.0])

	get_tree().quit(0)


func _time(label: String, body: Callable, clear_cache: bool = false) -> void:
	if clear_cache:
		Catalog._route_cache.clear()
	var t0 := Time.get_ticks_usec()
	body.call()
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("[SELL] %-52s %8.2f ms" % [label, ms])


func _a_player_tile() -> String:
	for iid in MatchState.buildings:
		var b: Dictionary = MatchState.buildings[iid]
		if MatchState.is_player_owned(b):
			return str(b.get("tile_id", ""))
	return ""


func _player_tiles() -> Array:
	var seen: Dictionary = {}
	for iid in MatchState.buildings:
		var b: Dictionary = MatchState.buildings[iid]
		if MatchState.is_player_owned(b):
			seen[str(b.get("tile_id", ""))] = true
	return seen.keys()


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
