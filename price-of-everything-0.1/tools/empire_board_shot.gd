extends Node
## Dev tool: open the supply chain view on a seeded company and save pictures of the board
## and of a selected building's network. Needs a window:
##   AGENT_GODOT_WINDOW=1 godot --path . res://tools/empire_board_shot.tscn --quit-after 3000 -- --no-telemetry --shot=<dir>

const SEED := [
	["b_003", "tile_10_10", 1], ["b_001", "tile_10_11", 2], ["b_009", "tile_8_9", 1],
	["b_010", "tile_8_9", 3], ["b_011", "tile_10_10", 2], ["b_012", "tile_7_9", 1],
	["b_013", "tile_10_11", 1], ["b_020", "tile_7_9", 2],
]
## The busy tile: motors, hydraulic components and everything both are made from, each by its
## own recipe. [recipe, level]
const BUSY_TILE := "tile_9_10"
const BUSY := [
	["r_009", 1], ["r_236", 2], ["r_003", 2], ["r_005", 1], ["r_008", 1], ["r_007", 1],
	["r_180", 2], ["r_028", 1], ["r_004", 1],
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
	for row in BUSY:
		var recipe: Dictionary = Catalog.get_recipe(str(row[0]))
		var iid := "busy_%s" % str(row[0])
		BuildingState.add_building(str(recipe.get("building_id", "")), str(row[0]), BUSY_TILE, "player_1", iid)
		if BuildingState.buildings.has(iid):
			BuildingState.buildings[iid]["level"] = int(row[1])
		else:
			print("BUSY not built ", row[0], " ", recipe.get("building_id", ""))
	_seed_movements()
	_seed_busy()
	await _settle(4)
	var ev: Node = game.get_node_or_null("UILayer/HUD/HUDContent/EmpireView")
	ev.call("toggle")
	await _settle(90)
	var board: Control = ev.get_node("Board")
	if OS.get_cmdline_user_args().has("--compare"):
		await _compare(ev, board, dir)
		get_tree().quit(0)
		return
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
	for tid in model["tiles"]:
		var tc: Vector2 = model["tiles"][tid]["center"]
		print("TYPES ", tid, " ", model["tiles"][tid]["type"])
		print("DUMP ", tid, " hub ", (model["tiles"][tid]["hub"] as Vector2) - tc, " manifold ", model["tiles"][tid]["manifold"])
		for st in model["standing"]:
			if str(st["tile"]) == tid:
				print("DUMP   ", st["kind"], " ", st["iid"], " ", (st["pos"] as Vector2) - tc)
		for l in model["lines"]:
			var row: Array = []
			for n in l["pts"]:
				if str(n["tile"]) == tid:
					row.append(((n["p"] as Vector2) - tc).round())
			if not row.is_empty():
				print("DUMP   line ", l["mode"], " ", l.get("good", ""), " ", l.get("kind", ""), " ", row)
		for r in model["roads"]:
			if str(r["tile"]) == tid:
				print("DUMP   road ", r["kind"], " ", ((r["a"] as Vector2) - tc).round(), ((r["b"] as Vector2) - tc).round())
	_shot(dir + "board.png")
	# The visibility key: open its plate, then everything off, then back on.
	var vis: Control = board.get_node("Visibility")
	vis.call("set_open", true)
	await _settle(20)
	_shot(dir + "board_visibility.png")
	for row in vis.get("ROWS"):
		(vis.get_node("VisibilityPanel").find_child("Show_" + str(row[0]), true, false) as Button).pressed.emit()
	await _settle(160)
	_shot(dir + "board_all_off.png")
	for row in vis.get("ROWS"):
		(vis.get_node("VisibilityPanel").find_child("Show_" + str(row[0]), true, false) as Button).pressed.emit()
	vis.call("set_open", false)
	await _settle(160)
	# Close on the busy tile: every kind of infrastructure, the pipes and their signs.
	var busy: Rect2 = board.call("_tile_rect", BUSY_TILE)
	board.set("_zoom", 1.5)
	board.set("_offset", board.size * 0.5 - busy.get_center() * 1.5 - Vector2(0.0, 60.0))
	board.call("_view_changed")
	await _settle(140)
	_shot(dir + "board_tile.png")
	var pit: Rect2 = board.call("_tile_rect", "tile_10_11")
	board.set("_offset", board.size * 0.5 - pit.get_center() * 1.5 - Vector2(0.0, 60.0))
	board.call("_view_changed")
	await _settle(140)
	_shot(dir + "board_mine.png")
	var city: Rect2 = board.call("_tile_rect", "tile_5_10")
	board.set("_offset", board.size * 0.5 - city.get_center() * 1.5 - Vector2(0.0, 60.0))
	board.call("_view_changed")
	await _settle(140)
	_shot(dir + "board_city.png")
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


## The busy tile's traffic over every kind of infrastructure: ore in and motors out by rail,
## crude oil in down a pipe, hydraulic components to market, and its works fed from the stockpile.
func _seed_busy() -> void:
	var hm: Node = get_tree().get_first_node_in_group("hex_map")
	var port := str(Catalog.nearest_port_tile(BUSY_TILE))
	var way: Array = (TransportService.route(BUSY_TILE, port, "g_008") as Dictionary).get("tiles", [])
	print("BUSY port ", port, " way ", way)
	for tid in way:
		for infra in ["rail", "pipes"]:
			Catalog.add_tile_infrastructure(str(tid), infra)
	for infra in ["reinf_pipes", "rail", "roads"]:
		Catalog.add_tile_infrastructure(BUSY_TILE, infra)
	var tile: Dictionary = hm.tiles.get(hm.id_to_coord(BUSY_TILE), {})
	if not (tile.get("infrastructure_present", []) as Array).has("cables"):
		(tile["infrastructure_present"] as Array).append("cables")
	Catalog.set_tile_infra_level(BUSY_TILE, "roads", 3)
	var back: Array = way.duplicate()
	back.reverse()
	var by := func(mode: String, tiles: Array) -> Array:
		return [{"mode": mode, "from": str(tiles[0]), "to": str(tiles[tiles.size() - 1])}]
	if way.size() >= 2:
		# Motors go out by rail and are sold; iron ore and copper ore come in the same way.
		TransportState.queue_transport_shipment({
			"source_tile": BUSY_TILE, "destination_tile": port, "is_sale": true, "qty": 40,
			"sale_record": {"items": [{"good_id": "g_008", "qty": 40}]},
			"turns_remaining": 2, "transport_turns": 3, "transport_cost": 0.0,
			"tiles": way, "path": way, "legs": by.call("rail", way)})
		for ore in ["iron_ore", "copper_ore"]:
			TransportState.queue_transport_shipment({
				"source_tile": port, "destination_tile": BUSY_TILE, "is_purchase": true, "qty": 90,
				"good_id": _good(ore), "turns_remaining": 1, "transport_turns": 3, "transport_cost": 0.0,
				"tiles": back, "path": back, "legs": by.call("rail", back)})
		TransportState.queue_transport_shipment({
			"source_tile": port, "destination_tile": BUSY_TILE, "is_purchase": true, "qty": 120,
			"good_id": _good("crude_oil"), "turns_remaining": 1, "transport_turns": 2, "transport_cost": 0.0,
			"tiles": back, "path": back, "legs": by.call("pipes", back)})
	MatchState.route_output_to_market("busy_r_236", _good("hydraulic_components"))
	for g in ["steel", "rubber", "processed_oil", "copper_wiring", "coal"]:
		Stockpile.add(BUSY_TILE, _good(g), 120)


func _good(internal: String) -> String:
	for g in Catalog.all_goods():
		if str((g as Dictionary).get("internal_name", "")) == internal:
			return str((g as Dictionary).get("id", (g as Dictionary).get("good_id", "")))
	return ""


## The same tiles with each of the plate's last three parts off, on alone, and all on.
func _compare(ev: Node, board: Control, dir: String) -> void:
	var script: GDScript = board.get_script()
	var sets := {"none": [false, false, false], "lamps": [true, false, false], "sea": [false, true, false],
		"town": [false, false, true], "all": [true, true, true]}
	for frame in [["bench", ["tile_8_9", "tile_9_10", "tile_10_10"]], ["coast", ["tile_5_10", "tile_6_9"]]]:
		for tag in sets:
			script.set("plate_lamps", sets[tag][0])
			script.set("plate_sea", sets[tag][1])
			script.set("plate_town", sets[tag][2])
			ev.call("refresh_graph")
			await _settle(4)
			var bounds := Rect2()
			for tid in frame[1]:
				var r: Rect2 = board.call("_tile_rect", tid)
				bounds = r if bounds.size == Vector2.ZERO else bounds.merge(r)
			var zoom := minf(minf((board.size.x - 80.0) / bounds.size.x, (board.size.y - 120.0) / bounds.size.y), 1.2)
			board.set("_zoom", zoom)
			board.set("_offset", board.size * 0.5 - bounds.get_center() * zoom)
			board.call("_view_changed")
			await _settle(140)
			_shot("%s%s_%s.png" % [dir, frame[0], tag])


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame


func _shot(path: String) -> void:
	RenderingServer.force_draw()
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SAVED ", path)
