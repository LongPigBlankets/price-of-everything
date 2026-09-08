extends Node
## Controlled, real-turn comparison of the tutorial's window/aluminium chain.
const Fixture := preload("res://tools/recipe_profitability_case.gd")
const Economics := preload("res://scripts/economics_snapshot.gd")
const SITE := "tile_5_9"
var _map: HexMap

func _ready() -> void:
	preload("res://scripts/app_paths.gd")._base = "/tmp/tutorial-aluminium-audit"
	TelemetryState.enabled = false
	RunMetrics.enabled = false
	await get_tree().process_frame
	var results: Array = []
	for start_turn: int in [10, 30]:
		for recipe: String in ["", "r_050", "r_232"]:
			results.append(await run_case(recipe, start_turn))
	results.append(await run_case("r_232", 30, true))
	var hall: Dictionary = results[4].totals
	var carbo: Dictionary = results[5].totals
	var improvement := float(carbo.money_in) - float(carbo.money_out) - (float(hall.money_in) - float(hall.money_out))
	if improvement < 6.0 or improvement > 7.0:
		push_error("Carbochlorination should add £6 to £7 after chain overhead at tutorial-era fees; got %.2f" % improvement)
		get_tree().quit(1)
		return
	print("[aluminium audit] upgrade improvement: £%.2f per turn" % improvement)
	var file := FileAccess.open("/tmp/tutorial-aluminium-audit.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))
	get_tree().quit()

func run_case(recipe: String, start_turn: int, coastal_stock: bool = false) -> Dictionary:
	MatchState.reset()
	TurnManager.reset_for_test()
	TurnManager.fast_mode = true
	TurnManager.current_turn = start_turn
	MarketState.import_state({})
	Stockpile.import_state({})
	Production.import_state({})
	Modifiers.import_state({})
	DecisionState.enabled = false
	MatchState.debug_turn_logs_enabled = false
	MatchState.ruleset["tutorial_enabled"] = true
	MatchState._unlock_defs.clear()
	MatchState.money = 100000.0
	MatchState.seaport_auto_subscribe = false
	_map = Fixture.DataMap.new()
	add_child(_map)
	_map.add_to_group("hex_map")
	install_infra(SITE, "cables", true)
	install_infra("tile_5_10", "reinf_pipes", false)
	if recipe == "r_232":
		install_infra(SITE, "reinf_pipes", true)
	var factory := MatchState.add_building("b_007", "r_056", SITE)
	var furnace := ""
	if recipe != "":
		furnace = MatchState.add_building("b_002", recipe, SITE)
		MatchState.set_output_stockpile_destination(furnace, SITE, str(Catalog.get_good_by_internal_name("aluminium").id))
	MatchState.enable_sell_surplus(SITE)
	if coastal_stock:
		Stockpile.add("tile_6_9", str(Catalog.get_good_by_internal_name("windows").id), 64)
	var rows: Array = []
	for i in 16:
		var cash := MatchState.money
		TurnManager.commit_turn()
		await TurnManager.turn_resolution_completed
		var row := Economics.capture(cash, factory)
		row["furnace"] = Production.turn_report_for(furnace).duplicate(true)
		row["in_sample"] = i >= 6
		if i >= 6:
			assert(Production.last_turn_run.get(factory, false), "Factory must run in every sampled turn")
			assert(furnace == "" or Production.last_turn_run.get(furnace, false), "Furnace must run in every sampled turn")
		rows.append(row)
	var totals: Dictionary = {}
	for row: Dictionary in rows.slice(6):
		for key: String in ["goods_sales_revenue", "goods_purchased_cost", "power_purchase_cost", "labour_paid", "maintenance_paid", "advisor_paid", "transport_paid", "warehousing_paid", "taxes_paid", "dividends_paid", "money_in", "money_out"]:
			totals[key] = float(totals.get(key, 0.0)) + float(row.empire.get(key, 0.0)) / 10.0
	print("[aluminium audit] ", recipe, " ", JSON.stringify(totals))
	_map.queue_free()
	await get_tree().process_frame
	return {"coastal_stock": coastal_stock, "start_turn": start_turn, "recipe": recipe, "totals": totals, "rows": rows, "buildings": MatchState.buildings.duplicate(true)}

func install_infra(tile_id: String, infra: String, owned: bool) -> void:
	Catalog.add_tile_infrastructure(tile_id, infra)
	var tile: Dictionary = _map.tiles[_map.id_to_coord(tile_id)]
	var present: Array = tile.get("infrastructure_present", [])
	if not present.has(infra):
		present.append(infra)
	tile["infrastructure_present"] = present
	if owned:
		MatchState.add_building(str(Catalog.get_building_by_internal_name(infra).id), "", tile_id)
