extends Node
## Dev tool: open the supply chain view on a seeded company and save pictures of the board
## and of a selected building's network. Needs a window:
##   AGENT_GODOT_WINDOW=1 godot --path . res://tools/empire_board_shot.tscn --quit-after 3000 -- --no-telemetry --shot=<dir>

const SEED := [
	["b_007", "tile_9_10", 1], ["b_008", "tile_9_10", 3], ["b_002", "tile_9_10", 2],
	["b_003", "tile_10_10", 1], ["b_001", "tile_10_11", 2], ["b_009", "tile_8_9", 1],
	["b_010", "tile_8_9", 3], ["b_011", "tile_10_10", 2], ["b_012", "tile_7_9", 1],
	["b_013", "tile_10_11", 1], ["b_014", "tile_9_10", 1], ["b_020", "tile_7_9", 2],
]


func _ready() -> void:
	var dir := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			dir = a.substr(7).rstrip("/") + "/"
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(30)
	var k := 0
	for row in SEED:
		var recs: Array = Catalog.get_recipes_for_building(str(row[0]))
		if recs.is_empty():
			continue
		var iid := "emp_%d" % k
		k += 1
		BuildingState.add_building(str(row[0]), str((recs[0] as Dictionary).get("recipe_id", "")), str(row[1]), "player_1", iid)
		if BuildingState.buildings.has(iid):
			BuildingState.buildings[iid]["level"] = int(row[2])
	_seed_movements()
	await _settle(4)
	var ev: Node = game.get_node_or_null("UILayer/HUD/HUDContent/EmpireView")
	ev.call("toggle")
	await _settle(90)
	var board: Control = ev.get_node("Board")
	var model: Dictionary = board.get("_model")
	print("BAKES ", (board.get("_bakes") as Dictionary).keys(), " zoom ", board.get("_zoom"),
		" baking ", board.get("_baking"), " want ", board.call("_bake_zoom"), " next ", board.call("_next_bake"),
		" view ", board.get("_bake_view").get("size"))
	print("BOARD tiles=", (model.get("tiles", {}) as Dictionary).size(),
		" standing=", (model.get("standing", []) as Array).size(),
		" lines=", (model.get("lines", []) as Array).size(),
		" flows=", (model.get("flows", []) as Array).size())
	for l in model.get("lanes", []):
		print("  lane ", l["kind"], " ", l["good"], " ", l["from"], " -> ", l["to"], "  from ", l["sources"], " to ", l["dests"], "  live ", (l["live"] as Array).size(), "  hops ", l["hops"])
	_shot(dir + "board.png")
	# Close on the busiest tile: the junction, the pipes and their signs.
	for st in board.call("standing_screen_rects"):
		if str(st["iid"]) == "store:tile_8_9":
			var at: Vector2 = (st["rect"] as Rect2).get_center()
			board.set("_offset", (board.get("_offset") as Vector2) + board.size * 0.5 - at)
	board.call("_zoom_at", board.size * 0.5, 3.4)
	await _settle(90)
	_shot(dir + "board_tile.png")
	board.call("fit_view")
	board.call("_zoom_at", board.size * 0.5, 2.2)
	await _settle(90)
	_shot(dir + "board_close.png")
	board.call("fit_view")
	await _settle(30)
	for s in board.call("standing_screen_rects"):
		if str(s["kind"]) == "building" and str((board.call("_pick", (s["rect"] as Rect2).get_center()) as Dictionary).get("iid", "")) == str(s["iid"]):
			# push_input takes window pixels; the board works in the stretched viewport's own.
			var c: Vector2 = get_viewport().get_final_transform() * ((s["rect"] as Rect2).get_center() + board.global_position)
			for pressed in [true, false]:
				var click := InputEventMouseButton.new()
				click.button_index = MOUSE_BUTTON_LEFT
				click.pressed = pressed
				click.position = c
				click.global_position = c
				get_viewport().push_input(click)
				await _settle(2)
			print("CLICK at ", c, " window ", get_window().size, " board ", board.size)
			print("PICKED ", s["iid"], " focus=", ev.get_node("GraphWorld").call("focus_iid"))
			break
	await _settle(40)
	var gw: Control = ev.get_node("GraphWorld")
	print("END focus=", gw.call("focus_iid"), " gw.visible=", gw.visible, " board.visible=", board.visible, " ev.processing=", ev.is_processing())
	_shot(dir + "network.png")
	get_tree().quit(0)


## Real movements for the board to plot: a purchase and a sale through the port, a move
## between two tiles, a fluid down a pipe that has to cross the road, and a cabled power run.
func _seed_movements() -> void:
	var hm: Node = get_tree().get_first_node_in_group("hex_map")
	for tid in ["tile_8_9", "tile_9_10", "tile_10_10", "tile_10_11"]:
		Catalog.add_tile_infrastructure(tid, "pipes")
		var tile: Dictionary = hm.tiles.get(hm.id_to_coord(tid), {})
		if not (tile.get("infrastructure_present", []) as Array).has("cables"):
			(tile["infrastructure_present"] as Array).append("cables")
	# Roads of every level, so the wide streets and the narrowing between tiles both show.
	for row in [["tile_8_9", 3], ["tile_9_10", 2], ["tile_7_9", 3], ["tile_6_9", 2]]:
		Catalog.set_tile_infra_level(str(row[0]), "roads", int(row[1]))
	var fluid := "g_012"
	print("FLUID ", fluid)
	Stockpile.add("tile_9_10", "g_001", 200)
	Stockpile.add("tile_8_9", "g_005", 200)
	TransportState.queue_move("tile_9_10", "tile_10_11", {"g_001": 60})
	TransportState.queue_move("tile_8_9", "tile_9_10", {"g_005": 40})
	# A piped shipment, written out leg by leg so the tool does not depend on the router's choice.
	TransportState.queue_transport_shipment({
		"source_tile": "tile_8_9", "destination_tile": "tile_10_11", "good_id": fluid, "qty": 80,
		"turns_remaining": 2, "transport_turns": 2, "transport_cost": 0.0,
		"tiles": ["tile_8_9", "tile_9_10", "tile_10_10", "tile_10_11"],
		"path": ["tile_8_9", "tile_10_10", "tile_10_11"],
		"legs": [{"mode": "pipes", "from": "tile_8_9", "to": "tile_10_10"},
			{"mode": "reinf_pipes", "from": "tile_10_10", "to": "tile_10_11"}],
	})
	MatchState.add_money(5000.0)
	MatchState.queue_buy("tile_10_10", "g_004", 30)
	var port := str(Catalog.nearest_port_tile("tile_7_9"))
	MatchState.log_market_sale("tile_7_9", port, "g_006", 25, 2, 100.0)


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame


func _shot(path: String) -> void:
	RenderingServer.force_draw()
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SAVED ", path)
