extends Node
## Dev tool: render each of the demo's endings on the real end screen, so the owner's copy
## is checked where a player meets it. Mirrors tools/victory_end_shot.gd, but under the
## demo ruleset — which is what selects the endings at all.
##   Godot --path . res://tools/demo_endings_shot.tscn --quit-after 4000
## Writes poe_demo_ending_<id>.png to user://.

const EndGameData := preload("res://scripts/end_game_data.gd")

var _screen: CanvasLayer


func _ready() -> void:
	# The demo ruleset lands before anything else, as it does in a real match.
	var rules := {"speed_turns": 100, "policy_timeline": "demo_itch", "victory_set": "demo_itch"}
	MatchState.ruleset = rules
	TurnManager.apply_ruleset(rules)
	VictoryState.apply_ruleset(rules)

	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(120)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false

	_screen = (load("res://scripts/victory_end_screen.gd") as Script).new()
	add_child(_screen)

	# One render per score-band ending. Bankruptcy has its own screen (game_over_panel).
	for row: Array in [
			["full_ledger", ["crown", "tiers", "distance", "green_demo"], {}],
			["jack_of_all_trades", [], {"crown": 0.8, "tiers": 0.7, "distance": 0.6}],
			["sequel", [], {"crown": 0.9}],
			["lukewarm", [], {"crown": 0.2, "tiers": 0.2}]]:
		_seed(row[1] as Array, row[2] as Dictionary)
		var data: Dictionary = EndGameData.gather()
		print("[DEMO_ENDING] %-18s -> %-22s %-9s  %s" % [
			str(row[0]), str(data.get("ending_id", "")), str(data.get("result", "")),
			str(data.get("epithet", ""))])
		if str(data.get("ending_id", "")) != str(row[0]):
			print("[DEMO_ENDING]   MISMATCH — expected %s" % str(row[0]))
		_screen.show_end(data)
		await _settle(30)
		get_viewport().get_texture().get_image().save_png(
			"user://poe_demo_ending_%s.png" % str(row[0]))

	# The sections below the fold — company showcase and charts — for the ledger ending.
	_screen.show_end(EndGameData.gather())
	await _settle(20)
	var sc: ScrollContainer = _screen.get_node_or_null("Scroll")
	if sc != null:
		sc.scroll_vertical = 980
		await _settle(8)
		get_viewport().get_texture().get_image().save_png("user://poe_end_scroll1.png")
		sc.scroll_vertical = 2000
		await _settle(8)
		get_viewport().get_texture().get_image().save_png("user://poe_end_scroll2.png")
		print("[DEMO_ENDING] scrolled shots written")

	# The expand overlay: the supply-chain view, and whether its buildings can be clicked.
	_screen.show_end(EndGameData.gather())
	await _settle(20)
	_screen.call("_open_expand")
	await _settle(20)
	get_viewport().get_texture().get_image().save_png("user://poe_end_expand.png")
	var worlds: Array[Node] = []
	_find_graph_worlds(_screen, worlds)
	for w_i in worlds.size():
		var w: Node = worlds[w_i]
		var n_click := 0
		for c in w.get_children():
			if c is Control and (c as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
				n_click += 1
		print("[DEMO_ENDING] graph world %d: filter=%s panels=%d clickable=%d visible=%s" % [
			w_i, str((w as Control).mouse_filter), w.get_child_count(), n_click,
			str((w as Control).is_visible_in_tree())])
	var world: Node = worlds[0] if worlds.size() > 0 else null
	if world != null:
		var clickable := 0
		for c in world.get_children():
			if c is Control and (c as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
				clickable += 1
		print("[DEMO_ENDING] expand graph: %d node panels, %d clickable" % [
			world.get_child_count(), clickable])
	else:
		print("[DEMO_ENDING] expand graph world NOT FOUND")
	_screen.call("_close_expand")
	await _settle(8)

	# The fifth ending has its own screen — SolvencyState mounts this one mid-game.
	_screen.hide()
	var over: Control = (load("res://scripts/game_over_panel.gd") as GDScript).new()
	var layer := CanvasLayer.new()
	layer.layer = 250
	add_child(layer)
	layer.add_child(over)
	over.open(SolvencyState.history)
	await _settle(30)
	get_viewport().get_texture().get_image().save_png("user://poe_demo_ending_bankruptcy.png")
	print("[DEMO_ENDING] bankruptcy screen rendered")

	print("[DEMO_ENDING] done")
	get_tree().quit(0)


## Seed one render: a small player estate, then the tracks this ending needs.
func _seed(secured: Array, partial: Dictionary) -> void:
	MatchState.buildings.clear()
	MatchState.tile_buildings.clear()
	MatchState.money = 50000.0
	var tiles := ["tile_5_9", "tile_5_10", "tile_6_9", "tile_6_10", "tile_7_9",
		"tile_7_10", "tile_4_9", "tile_8_10"]
	MatchState.add_building("b_001", "r_001", tiles[0], "player_1", "dshot_m1", false)
	MatchState.add_building("b_001", "r_001", tiles[1], "player_1", "dshot_m2", false)
	MatchState.add_building("b_002", "r_003", tiles[2], "player_1", "dshot_f1", false)
	MatchState.add_building("b_002", "r_003", tiles[3], "player_1", "dshot_f2", false)
	MatchState.add_building("b_007", "r_009", tiles[4], "player_1", "dshot_g1", false)
	MatchState.add_building("b_007", "r_009", tiles[5], "player_1", "dshot_g2", false)
	MatchState.add_building("b_007", "r_009", tiles[6], "player_1", "dshot_g3", false)
	MatchState.add_building("b_004", "", tiles[7], "player_1", "dshot_p1", false)

	VictoryState.reset()
	TurnManager.current_turn = 100
	for key: String in VictoryState.TRACK_ORDER:
		if key in secured:
			VictoryState.track_best[key] = 1.0
			VictoryState.track_secured_turn[key] = 60 + int(hash(key) % 30)
		else:
			VictoryState.track_best[key] = float(partial.get(key, 0.0))
	VictoryState.won = VictoryState.total_for_turn(100) >= VictoryState.win_threshold_for_turn(100)
	VictoryState.won_turn = 100 if VictoryState.won else 0
	VictoryState.demo_crown_points = 650
	VictoryState.demo_long_hauls = 4
	VictoryState.history_revenue = []
	VictoryState.history_output = []
	VictoryState.history_buildings = []
	for i in 100:
		VictoryState.history_revenue.append(200.0 + float(i) * 55.0)
		VictoryState.history_output.append(50 + i * 7)
		VictoryState.history_buildings.append(3 + i / 4)
	VictoryState.produced_by_good = {"g_005": 8600, "g_004": 4300, "g_010": 2690,
		"g_002": 1820, "g_008": 1540}
	# The company showcase reads three more ledgers; seed them so the plates carry the
	# game's art rather than their empty-state dashes.
	MarketState._lifetime_sold = {"g_005": 6100, "g_004": 2200}
	Production.produced_by_building = {"dshot_g1": {"g_009": 5400}, "dshot_f1": {"g_004": 2100}}
	# The per-building lifetime P&L the "most value created" plate reads. Seeded here too:
	# the ledger is accumulated turn by turn by the live sim, and a synthetic end screen has
	# no turns behind it.
	Production.lifetime_pl_by_building = {
		"dshot_g1": {"value": 3067.0, "inputs": 940.0, "power": 310.0, "labour": 520.0,
			"maint": 180.0, "turns": 88},
		"dshot_f1": {"value": 1820.0, "inputs": 610.0, "power": 140.0, "labour": 300.0,
			"maint": 110.0, "turns": 64},
	}
	# The league cards: the rank arc CompanyRankings records per turn, and the per-good
	# table it builds from the last turn's production. Both are seeded for the same reason
	# as the P&L above — a synthetic end screen has no turns behind it.
	var ranks: Array = []
	for i in 100:
		var r := 9 - int(float(i) / 14.0)
		if i > 82:
			r = 1
		ranks.append(maxi(1, r))
	# import_state CLEARS player_rank_history before reading the dict, so the dict must not
	# hold the same array — pass a copy or the clear empties what is about to be read.
	CompanyRankings.import_state({"player_revenue_history": [4200.0, 4600.0, 5100.0, 5600.0, 6000.0],
		"player_goods_produced": {"g_005": 9400, "g_004": 5200, "g_010": 3100, "g_002": 2400,
			"g_008": 1800, "g_009": 900},
		"player_rank_history": ranks.duplicate()})
	MatchState.advisor_seats = {"seat_founder": "andrew"}
	MatchState.advisor_hired_turn = {"andrew": 3}


func _find_graph_worlds(n: Node, out: Array[Node]) -> void:
	if n.get_script() != null and str(n.get_script().resource_path).ends_with("empire_graph_world.gd"):
		out.append(n)
	for c in n.get_children():
		_find_graph_worlds(c, out)

func _find_graph_world(n: Node) -> Node:
	if n.get_script() != null and str(n.get_script().resource_path).ends_with("empire_graph_world.gd"):
		return n
	for c in n.get_children():
		var hit := _find_graph_world(c)
		if hit != null:
			return hit
	return null

func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
