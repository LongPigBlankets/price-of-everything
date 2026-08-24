extends Node
## Dev tool: what a START's cluster is worth, by the game's own reckoning — the same
## `BuildingPrice.sale_price()` sum that SolvencyState calls the empire value, plus the land
## and infrastructure the start hands over.
##   Godot --headless --path . res://tools/cluster_value.tscn --quit-after 600
## Pass a start name after `--` (default: metal_magnate).

const BuildingPrice := preload("res://scripts/building_price.gd")


func _ready() -> void:
	var start := "metal_magnate"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		start = str(args[0])
	# expand_start_config gives the full snapshot; apply_snapshot is what a real new game
	# does with it. prepare_new_game only STAGES it for the map scene, so on its own the
	# match stays empty.
	var cfg: Dictionary = SaveLoad._read_json_file("res://data/starts/%s.json" % start)
	var snap: Dictionary = SaveLoad.expand_start_config(cfg)
	SaveLoad.import_snapshot(snap)
	await _settle(20)

	print("[CLUSTER] start: %s   cash on hand: £%d" % [start, int(round(MatchState.money))])
	var buildings_total := 0.0
	print("[CLUSTER] %-28s %-22s %8s" % ["BUILDING", "TILE", "VALUE"])
	for iid in MatchState.buildings:
		var b: Dictionary = MatchState.buildings[iid]
		if not MatchState.is_player_owned(b):
			continue
		var price := float(BuildingPrice.sale_price(b))
		buildings_total += price
		print("[CLUSTER] %-28s %-22s %8d" % [
			str(Catalog.get_building(str(b.get("building_id", ""))).get("display_name", "?")),
			str(b.get("tile_id", "")), int(price)])

	# Land the start hands over, at what it would cost to buy.
	var land_units := 0
	for tile_id in MatchState.tile_land_owned:
		land_units += int(MatchState.tile_land_owned[tile_id])
	var land_value := ceilf(float(land_units) / float(MatchState.LAND_PATCH_SIZE)) * MatchState.LAND_PATCH_COST

	# Stock on the tiles, at market.
	var stock_value := 0.0
	var stock_units := 0
	for tile_id in Stockpile.tiles_with_stock():
		for gid in Stockpile.get_tile_totals(tile_id):
			var qty := int(Stockpile.get_tile_totals(tile_id)[gid])
			stock_units += qty
			stock_value += float(qty) * MarketState.get_price(str(gid))

	print("[CLUSTER] ---------------------------------------------")
	print("[CLUSTER] buildings (empire sale value)      £%8d" % int(round(buildings_total)))
	print("[CLUSTER] land: %4d units                    £%8d" % [land_units, int(round(land_value))])
	print("[CLUSTER] stock: %4d units at market         £%8d" % [stock_units, int(round(stock_value))])
	print("[CLUSTER] cash on hand                       £%8d" % int(round(MatchState.money)))
	print("[CLUSTER] ---------------------------------------------")
	print("[CLUSTER] buildings + land                   £%8d" % int(round(buildings_total + land_value)))
	print("[CLUSTER] buildings + land + stock           £%8d" % int(round(buildings_total + land_value + stock_value)))
	get_tree().quit(0)


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
