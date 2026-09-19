extends Node
const Paths := preload("res://scripts/app_paths.gd")
func _enter_tree() -> void:
	Paths._base = "/tmp/pepper-chain-quotes/runtime"
	RunMetrics.enabled = false
func _ready() -> void:
	SaveLoad.autosave_enabled = false
	SaveLoad.prepare_new_game("res://data/starts/pepper_valley_motors.json", {"ruleset":{"logistics_model":"middleman_v1"}})
	var world: Node = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	for frame in 160:
		await get_tree().process_frame
	var costs := {}
	for rid in ["r_009", "r_003", "r_008", "r_007", "r_005"]:
		var bid := "b_007" if rid in ["r_009", "r_008"] else "b_002"
		var b := {"building_id":bid,"recipe_id":rid,"level":1,"tile_id":"tile_5_4"}
		var labour := 0.0
		for turn in range(40,50):
			TurnManager.current_turn = turn
			labour += Production._calculate_labour_cost(b)/10.0
		costs[rid] = {"labour":labour,"maintenance":Production._calculate_maintenance_cost(b),"power":Production._effective_energy_req(b,Catalog.get_recipe(rid))*EconomyConfig.GRID_BUY_PRICE}
	TurnManager.current_turn = 44
	var routes := {}
	for tile in ["tile_5_4", "tile_6_4"]:
		routes[tile] = {}
		for gid in ["g_001","g_002","g_003","g_004","g_005","g_006","g_007"]:
			routes[tile][gid] = TransportService.quote_market_buy(tile,gid,1)
		routes[tile]["sell"] = TransportService.quote_market_sell(tile,{"g_008":33})
	var internal := TransportService.route("tile_6_4","tile_5_4","g_004")
	var out := {"costs":costs,"routes":routes,"internal":internal}
	DirAccess.make_dir_recursive_absolute("/tmp/pepper-chain-quotes")
	var f := FileAccess.open("/tmp/pepper-chain-quotes/result.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(out,"\t"))
	get_tree().quit()
