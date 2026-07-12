extends Node
## Headless verification of the Metal Magnate start: buildings/tiles, output routing,
## the +10% iron-ingots modifier, cash/loans, and that the chain actually runs.

const START := "res://data/starts/metal_magnate.json"

func _ready() -> void:
	SaveLoad.prepare_new_game(START)
	var snap: Dictionary = SaveLoad._pending_snapshot
	var m: Dictionary = snap.get("match", {})
	print("[CHK] snapshot money=", m.get("money"), " loans=", (snap.get("loans", {}) as Dictionary).get("loans", []).size())
	print("[CHK] snapshot buildings=", (m.get("buildings", {}) as Dictionary).size(),
		" output_routes=", (m.get("output_stockpile_destinations", {}) as Dictionary).size(),
		" modifiers=", ((snap.get("modifiers", {}) as Dictionary).get("modifiers", {}) as Dictionary).keys())

	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	var frames := 0
	while frames < 4000 and main.get("build_complete") != true:
		await get_tree().process_frame
		frames += 1

	# Buildings on the right tiles + routing.
	var by_tile := {}
	for iid in MatchState.buildings:
		var b: Dictionary = MatchState.buildings[iid]
		if MatchState.is_player_owned(b):
			by_tile[str(b.get("tile_id", ""))] = {"iid": iid, "bid": str(b.get("building_id", "")), "rid": str(b.get("recipe_id", ""))}
	print("[CHK] coal mine @tile_6_8: ", by_tile.get("tile_6_8"))
	print("[CHK] iron mine @tile_7_10: ", by_tile.get("tile_7_10"))
	print("[CHK] furnace  @tile_6_9: ", by_tile.get("tile_6_9"))
	var coal_iid := str((by_tile.get("tile_6_8", {}) as Dictionary).get("iid", ""))
	var iron_iid := str((by_tile.get("tile_7_10", {}) as Dictionary).get("iid", ""))
	var furn_iid := str((by_tile.get("tile_6_9", {}) as Dictionary).get("iid", ""))
	print("[CHK] coal mine routes coal(g_001) -> ", MatchState.get_output_stockpile_destination(coal_iid, "g_001"), " (expect tile_6_9)")
	print("[CHK] iron mine routes iron_ore(g_002) -> ", MatchState.get_output_stockpile_destination(iron_iid, "g_002"), " (expect tile_6_9)")
	print("[CHK] furnace sells iron_ingots to market? ", MatchState.is_output_market(furn_iid, "g_004"), " (expect true)")

	# Modifier.
	var mod: Dictionary = Modifiers._modifiers.get("start_metals_magnate_iron", {})
	print("[CHK] modifier: pct=", mod.get("pct"), " domain=", mod.get("domain"),
		" match=", mod.get("target_match"), " label=", mod.get("label"))
	# Prove it lifts iron-ingots output: +10% on the furnace recipe.
	var base_out := 70.0
	var eff := Modifiers.apply("recipe_output", "r_005", base_out,
		{"recipe_id": "r_005", "good_internal": "iron_ingots", "good_id": "g_004"})
	print("[CHK] iron ingots output 70 -> ", eff, " (expect 77 = +10%)")

	print("[CHK] money=", int(MatchState.money), " (expect 300) loans=", LoanState.loans.size(), " (expect 0)")

	# Run turns and watch iron ingots flow.
	for t in range(10):
		TurnManager.commit_turn()
		var g := 0
		while g < 200 and TurnManager.is_resolving:
			await get_tree().process_frame
			g += 1
		await get_tree().process_frame
	var ingots_market := MarketState.get_price("g_004")
	var furn_ran := Production.last_turn_run.has(furn_iid)
	print("[CHK] after 8 turns: money=", int(MatchState.money), " furnace ran last turn=", furn_ran,
		" furnace stockpile iron_ingots=", Stockpile.get_at_tile("tile_6_9", "g_004"))
	get_tree().quit(0)
