extends Node

## Current-data Pepper Valley comparison:
##   integrated: steel + copper wiring feed motors through the tile stockpile;
##               raw inputs and surplus/output sales use rail L1 to the port.
##   middleman:  the same three buildings trade independently through the
##               Logistics Intermediary, with no physical shipment invoice.

const Paths := preload("res://scripts/app_paths.gd")
const Service := preload("res://scripts/middleman_service.gd")
const OUT := "/tmp/pepper-three-chain-comparison"

var case_name := "integrated"
var transport_mode := "rail"
var legacy_outputs := false
var transport_instances: Array[String] = []
var transport_tiles: Array[String] = []
var owned_transport_tiles: Array[String] = []

func _enter_tree() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--case="):
			case_name = arg.trim_prefix("--case=")
		if arg.begins_with("--mode="):
			transport_mode = arg.trim_prefix("--mode=")
		if arg == "--legacy-outputs":
			legacy_outputs = true
	Paths._base = OUT + "/" + case_name + "/runtime"
	RunMetrics.enabled = false

func _ready() -> void:
	SaveLoad.autosave_enabled = false
	SaveLoad.prepare_new_game("res://data/starts/pepper_valley_motors.json", {"ruleset":{"logistics_model":"middleman_v1"}})
	var world: Node = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	for frame in 160:
		await get_tree().process_frame
	if legacy_outputs:
		_apply_legacy_outputs()
	TurnManager.fast_mode = true
	for system in [ResearchState, EventScheduler, DecisionState]:
		var hook := Callable(system, "_on_phase_started")
		if TurnManager.phase_started.is_connected(hook): TurnManager.phase_started.disconnect(hook)
	var map_hook := Callable(world, "_on_turn_advanced")
	if TurnManager.turn_advanced.is_connected(map_hook): TurnManager.turn_advanced.disconnect(map_hook)
	DecisionState.enabled = false
	DecisionState.auto_resolve = true
	SolvencyState.enabled = false
	# The integrated rail case is the licensed global-market route.  The intermediary
	# case deliberately leaves this off so its buildings can trade only through the
	# Logistics Intermediary, matching the early-game comparison.
	if case_name == "integrated":
		ResearchState.unlocked_titles[ResearchState.GLOBAL_TRADE_LICENSE_TITLE] = true
		ResearchState.activate_global_trade_license()
	var tile := "tile_5_4"
	var steel_gid := str(Catalog.get_good_by_internal_name("steel").id)
	var wire_gid := str(Catalog.get_good_by_internal_name("copper_wiring").id)
	var motor_gid := str(Catalog.get_good_by_internal_name("motor").id)
	var motor_id := ""
	for b: Dictionary in BuildingState.buildings.values():
		if BuildingState.is_player_owned(b) and str(b.get("recipe_id", "")) == "r_009":
			motor_id = str(b.instance_id)
			break
	check(not motor_id.is_empty(), "start motor exists")
	if case_name == "integrated":
		_install_owned_infrastructure(tile, TransportService.nearest_port_tile(tile))
	var steel_id := BuildingState.add_building("b_002", "r_003", tile, MatchState.LOCAL_PLAYER)
	var wire_id := BuildingState.add_building("b_007", "r_008", tile, MatchState.LOCAL_PLAYER)
	if case_name == "integrated":
		MatchState.set_output_stockpile_destination(steel_id, tile, steel_gid)
		MatchState.set_output_stockpile_destination(wire_id, tile, wire_gid)
		MatchState.enable_auto_sell_good(tile, steel_gid)
		MatchState.enable_auto_sell_good(tile, wire_gid)
		MatchState.route_output_to_market(motor_id, motor_gid)
		MatchState.set_input_tile_only(motor_id, steel_gid, true)
		MatchState.set_input_tile_only(motor_id, wire_gid, true)
	else:
		for iid in [motor_id, steel_id, wire_id]:
			var enabled := Service.enable(str(iid))
			check(bool(enabled.get("ok", false)), "intermediary enabled: " + str(iid))
	var initial_prices := MarketState.prices.duplicate(true)
	var rows: Array = []
	var signatures: Array[String] = []
	for turn in range(1, 91):
		MarketState.prices = initial_prices.duplicate(true)
		MarketState.impact_pct.clear()
		var before := MatchState.money
		var transport_maintenance := 0.0
		var transport_labour := 0.0
		for iid: String in transport_instances:
			var transport_building := BuildingState.get_building(iid)
			transport_maintenance += Production._calculate_maintenance_cost(transport_building)
			transport_labour += Production._calculate_labour_cost(transport_building)
		TurnManager.commit_turn()
		await TurnManager.turn_resolution_completed
		var s: Dictionary = Production.last_turn_summary.duplicate(true)
		var stock := Stockpile.get_tile_totals(tile).duplicate(true)
		var transit := _transit_totals()
		var signature := JSON.stringify([stock, transit])
		var factory_costs := float(s.labour_paid) + float(s.maintenance_paid) + float(s.power_purchase_cost) - transport_maintenance - transport_labour
		var middleman_fee := float(s.get("middleman_fee", 0.0))
		var direct_logistics := float(s.transport_paid) + float(s.warehousing_paid) + transport_maintenance + transport_labour
		var contribution := float(s.goods_sales_revenue) - float(s.goods_purchased_cost) - factory_costs - float(s.transport_paid) - float(s.warehousing_paid) - transport_maintenance - transport_labour
		rows.append({"turn":turn,"produced":s.produced,"purchased":s.purchased,"sold":s.sold,"stock":stock,"transit":transit,"signature":signature,"goods_purchases":float(s.goods_purchased_cost),"goods_receipts":float(s.goods_sales_revenue),"middleman_fee":middleman_fee,"factory_costs":factory_costs,"labour":float(s.labour_paid) - transport_labour,"maintenance":float(s.maintenance_paid) - transport_maintenance,"power":float(s.power_purchase_cost),"transport":float(s.transport_paid),"transport_breakdown":s.get("transport_breakdown", {}),"warehousing":float(s.warehousing_paid),"transport_maintenance":transport_maintenance,"transport_labour":transport_labour,"direct_logistics":direct_logistics,"contribution":contribution,"money_in":float(s.money_in),"money_out":float(s.money_out),"advisor":float(s.advisor_paid),"taxes":float(s.taxes_paid),"dividends":float(s.dividends_paid),"profit_sharing":float(s.profit_sharing_paid),"interest":float(s.interest_paid),"carbon_tax":float(s.carbon_tax_paid),"cash_change":Production.cash_change_of(s),"cash_reconciles":absf(MatchState.money-before-Production.cash_change_of(s)) < 0.01})
		signatures.append(signature)
	var sample: Array = []
	for row: Dictionary in rows:
		if int(row.turn) >= 40 and int(row.turn) <= 49: sample.append(row)
	var output_values := {"steel":44,"copper_wiring":33,"motor":33} if legacy_outputs else {"steel":49,"copper_wiring":37,"motor":33}
	var report := {"case":case_name,"assumptions":{"tile":tile,"port":TransportService.nearest_port_tile(tile),"transport":"%s L1; three player-owned transport tiles, remaining corridor public" % transport_mode,"turn_window":"40-49","prices":"reset to initial catalogue prices each turn","current_recipe_outputs":output_values,"integrated_internal_feed":"steel and copper wiring use the same-tile stockpile; surplus is sold to market","middleman":"each building independently buys inputs and sells outputs through the intermediary; no physical rail shipment"},"transport_tiles":transport_tiles,"owned_transport_tiles":owned_transport_tiles,"rows":rows,"sample":sample,"means":_means(sample),"failures":failures}
	DirAccess.make_dir_recursive_absolute(OUT + "/" + case_name)
	var f := FileAccess.open(OUT + "/" + case_name + "/result.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "\t"))
	print("THREE_CHAIN ", JSON.stringify({"case":case_name,"means":report.means,"failures":failures,"result":OUT + "/" + case_name + "/result.json"}))
	get_tree().quit(0 if failures.is_empty() else 1)

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func _apply_legacy_outputs() -> void:
	# Re-run the current benchmark with the pre-20 September quantities. This is
	# a controlled sensitivity switch; the catalogue file itself is unchanged.
	for pair in [{"recipe":"r_003","good":"g_006","qty":44},{"recipe":"r_008","good":"g_007","qty":33}]:
		var recipe: Dictionary = Catalog._recipes_by_id.get(str(pair.recipe), {})
		if recipe.is_empty():
			check(false, "legacy recipe exists: " + str(pair.recipe))
			continue
		recipe["output_qty"] = int(pair.qty)
		for output: Dictionary in recipe.get("outputs", []):
			if str(output.get("good_id", "")) == str(pair.good):
				output["qty"] = int(pair.qty)

func _means(sample: Array) -> Dictionary:
	var result := {}
	if sample.is_empty(): return result
	for key in ["goods_purchases","goods_receipts","middleman_fee","factory_costs","labour","maintenance","power","transport","warehousing","transport_maintenance","transport_labour","direct_logistics","contribution"]:
		var total := 0.0
		for row: Dictionary in sample: total += float(row.get(key, 0.0))
		result[key] = total / sample.size()
	result["cash_reconciles"] = sample.all(func(row: Dictionary) -> bool: return bool(row.get("cash_reconciles", false)))
	return result

func _transit_totals() -> Dictionary:
	var totals := {"buy":{},"sell":{}}
	for sh: Dictionary in TransportState.pending_transport_shipments:
		if bool(sh.get("is_purchase", false)):
			var gid := str(sh.get("good_id", ""))
			totals.buy[gid] = int(totals.buy.get(gid, 0)) + int(sh.get("qty", 0))
		elif bool(sh.get("is_sale", false)):
			for item: Dictionary in sh.get("sale_record", {}).get("items", []):
				var sgid := str(item.get("good_id", ""))
				totals.sell[sgid] = int(totals.sell.get(sgid, 0)) + int(item.get("qty", 0))
	return totals

func _install_owned_infrastructure(source: String, destination: String) -> void:
	var infra_key := "rail" if transport_mode == "rail" else "roads"
	var present_key := "rails" if transport_mode == "rail" else "roads"
	var infra_building_id := "b_019" if transport_mode == "rail" else "b_005"
	var queue: Array = [source]
	var previous := {source:""}
	var index := 0
	while index < queue.size():
		var current := str(queue[index]); index += 1
		if current == destination: break
		for neighbour in Catalog.tile_neighbours(current):
			var next := str(neighbour)
			if previous.has(next) or not bool(Catalog._tile_land.get(next, false)): continue
			previous[next] = current; queue.append(next)
	check(previous.has(destination), "%s corridor reaches port" % transport_mode)
	if not previous.has(destination): return
	var cursor := destination
	while cursor != "":
		transport_tiles.push_front(cursor); cursor = str(previous[cursor])
	var terrain := get_tree().get_first_node_in_group("hex_map")
	for tile in transport_tiles:
		Catalog.add_tile_infrastructure(tile, infra_key)
		Catalog.set_tile_infra_level(tile, infra_key, 1)
		var data: Dictionary = terrain.tiles[terrain.id_to_coord(tile)]
		var present: Array = data.get("infrastructure_present", [])
		if not present.has(present_key): present.append(present_key)
		data["infrastructure_present"] = present
		var levels: Dictionary = data.get("infrastructure_levels", {}); levels[present_key] = 1; data["infrastructure_levels"] = levels
		if owned_transport_tiles.size() < 3:
			owned_transport_tiles.append(tile)
			# Roads are government-maintained in this benchmark, matching the prior
			# Pepper Valley assumption. Rail instances remain player-owned for upkeep.
			if transport_mode == "rail":
				transport_instances.append(BuildingState.add_building(infra_building_id, "", tile, MatchState.LOCAL_PLAYER))
