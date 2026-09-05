extends Node

const BuildForecast := preload("res://scripts/build_forecast.gd")
## Dev probe: what does the build forecast tell a player, and WHICH LINE drives it? Boots a
## start, runs a few turns, then prints BuildForecast.project() line by line for a building on
## a tile — so "−£15/turn" can be read as the sum it actually is.
##   <godot> --headless --path . res://tools/forecast_probe.tscn --quit-after 60000 -- \
##       --start=metal_magnate --turns=3 --tile=tile_5_10 --building=b_009 --recipe=r_009

func _ready() -> void:
	var start_id := "metal_magnate"
	var turns := 3
	var tile_id := "tile_5_10"
	var building_id := "b_007"
	var recipe_id := "r_009"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--start="): start_id = a.trim_prefix("--start=")
		elif a.begins_with("--turns="): turns = int(a.trim_prefix("--turns="))
		elif a.begins_with("--tile="): tile_id = a.trim_prefix("--tile=")
		elif a.begins_with("--building="): building_id = a.trim_prefix("--building=")
		elif a.begins_with("--recipe="): recipe_id = a.trim_prefix("--recipe=")
	SaveLoad.prepare_new_game("res://data/starts/%s.json" % start_id, {"ruleset": {
		"start_id": start_id, "difficulty": "normal", "speed_turns": 100,
		"policy_timeline": "demo_itch", "victory_set": "demo_itch",
		"tutorial_enabled": false, "survey_all_tiles": true, "company_colour": "diesel_red",
	}})
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	for _i in 200:
		await get_tree().process_frame
	for _t in range(turns - 1):
		TurnManager.commit_turn()
		await TurnManager.turn_resolution_completed
	var recipe: Dictionary = Catalog.get_recipe(recipe_id)
	print("[FC] turn %d  money=%.1f  %s on %s (%s)" % [
		TurnManager.current_turn, MatchState.money, str(recipe.get("display_name", recipe_id)),
		tile_id, building_id])
	var f: Dictionary = BuildForecast.project(building_id, recipe_id, tile_id)
	var b: Dictionary = f.get("breakdown", {})
	print("[FC] steady_net = %+.2f / turn   payback_turn=%s   sale_delay=%d   no_supply=%s %s" % [
		float(f.get("steady_net", 0.0)), str(f.get("payback_turn", -1)),
		int(f.get("sale_delay", 1)), str(f.get("no_supply", false)), str(f.get("input_names", []))])
	var keys: Array = b.keys()
	keys.sort()
	for k in keys:
		print("[FC]    %-18s %+10.2f" % [str(k), float(b[k])])
	# Where does each input come from, and at what price?
	for item in recipe.get("inputs", []):
		var gid := str(item.get("good_id", ""))
		var qty := int(item.get("qty", 0))
		if gid == "" or qty <= 0:
			continue
		var own := BuildForecast._own_source_tile(tile_id, gid)
		print("[FC]    input %-16s qty=%-4d own_source=%-12s sell=%.3f buy=%.3f stock_here=%d" % [
			str(Catalog.get_good(gid).get("display_name", gid)), qty,
			own if own != "" else "(market)", MarketState.get_price(gid),
			MarketState.get_buy_price(gid), Stockpile.get_at_tile(tile_id, gid)])
	for item in Production._recipe_output_items(recipe):
		var gid := str(item.get("good_id", ""))
		if gid == "" and str(item.get("internal_name", "")) != "":
			gid = str(Catalog.get_good_by_internal_name(str(item.get("internal_name", ""))).get("id", ""))
		print("[FC]    output %-15s qty=%-4d sell=%.3f" % [
			str(Catalog.get_good(gid).get("display_name", gid)), int(item.get("qty", 0)),
			MarketState.get_price(gid)])
	get_tree().quit(0)
