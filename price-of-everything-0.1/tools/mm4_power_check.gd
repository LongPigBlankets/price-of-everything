extends Node
## Metal Magnate + coal power plant: verify the plant runs (bootstrap past the
## coal↔power circular start), water buys from market via the pipe, and cash
## trajectory (should climb once the plant is self-powering + selling surplus).

const START := "res://data/starts/metal_magnate.json"

func _ready() -> void:
	SaveLoad.prepare_new_game(START)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	var frames := 0
	while frames < 4000 and main.get("build_complete") != true:
		await get_tree().process_frame
		frames += 1

	var plant_iid := ""
	var furn_iid := ""
	for iid in MatchState.buildings:
		var b: Dictionary = MatchState.buildings[iid]
		if not MatchState.is_player_owned(b):
			continue
		if str(b.get("building_id", "")) == "b_003":
			plant_iid = str(iid)
		elif str(b.get("building_id", "")) == "b_002":
			furn_iid = str(iid)
	print("[CHK] power plant present: ", plant_iid != "", " on tile_6_9=",
		str(MatchState.buildings.get(plant_iid, {}).get("tile_id", "")))
	print("[CHK] tile_6_9 has pipes: ", Catalog.tile_has_infrastructure("tile_6_9", "pipes"),
		"  port tile_5_10 has pipes: ", Catalog.tile_has_infrastructure("tile_5_10", "pipes"))

	for t in range(14):
		TurnManager.commit_turn()
		var g := 0
		while g < 300 and TurnManager.is_resolving:
			await get_tree().process_frame
			g += 1
		await get_tree().process_frame
		var pran := Production.last_turn_run.has(plant_iid)
		var fran := Production.last_turn_run.has(furn_iid)
		var water := Stockpile.get_at_tile("tile_6_9", "g_009")
		print("[T%02d] money=%d  plant_ran=%s  furnace_ran=%s  water@furn=%d  ingots@furn=%d" % [
			int(TurnManager.current_turn), int(MatchState.money), str(pran), str(fran),
			int(water), int(Stockpile.get_at_tile("tile_6_9", "g_004"))])
	get_tree().quit(0)
