extends Node
const Paths := preload("res://scripts/app_paths.gd")
var failures: Array = []
var copies := 1
var output_dir := "/tmp/pepper-five-factories"
func _enter_tree() -> void:
	if OS.get_cmdline_user_args().has("--double"):
		copies = 2
		output_dir += "-double"
	Paths._base = output_dir + "/runtime"
	RunMetrics.enabled = false
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
func manifest_equal(actual: Dictionary, expected: Dictionary) -> bool:
	for gid in expected:
		var v: Variant = actual.get(gid,0)
		if int(v.get("qty",0) if v is Dictionary else v) != int(expected[gid]):
			return false
	for gid in actual:
		var v: Variant = actual[gid]
		var qty := int(v.get("qty",0) if v is Dictionary else v)
		if qty != 0 and not expected.has(gid): return false
	return true
func _ready() -> void:
	SaveLoad.autosave_enabled = false
	SaveLoad.prepare_new_game("res://data/starts/pepper_valley_motors.json", {"ruleset":{"logistics_model":"middleman_v1"}})
	var world: Node = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	for frame in 160:
		await get_tree().process_frame
	TurnManager.fast_mode = true
	for system in [ResearchState, EventScheduler, DecisionState]:
		var hook := Callable(system,"_on_phase_started")
		if TurnManager.phase_started.is_connected(hook): TurnManager.phase_started.disconnect(hook)
	var map_hook := Callable(world,"_on_turn_advanced")
	if TurnManager.turn_advanced.is_connected(map_hook): TurnManager.turn_advanced.disconnect(map_hook)
	DecisionState.enabled=false
	DecisionState.auto_resolve=true
	SolvencyState.enabled=false
	BuildingState.tile_land_owned["tile_6_4"]=200
	Catalog.add_tile_infrastructure("tile_6_4","cables")
	Catalog.set_tile_infra_level("tile_6_4","cables",1)
	var layout: Array = []
	for copy in copies:
		if copy > 0:
			var motor := BuildingState.add_building("b_007","r_009","tile_5_4",MatchState.LOCAL_PLAYER)
			MatchState.route_output_to_market(motor,"g_008")
		for row in [["b_002","r_003","tile_5_4","g_006"],["b_007","r_008","tile_5_4","g_007"],["b_002","r_007","tile_6_4","g_005"],["b_002","r_005","tile_6_4","g_004"]]:
			var iid := BuildingState.add_building(row[0],row[1],row[2],MatchState.LOCAL_PLAYER)
			# All intermediate output reaches the consuming tile stockpile; sell its surplus there.
			MatchState.set_output_stockpile_destination(iid,"tile_5_4",row[3])
			MatchState.enable_auto_sell_good("tile_5_4",row[3])
			layout.append({"building":row[0],"recipe":row[1],"tile":row[2],"output_stockpile":"tile_5_4"})
	for b: Dictionary in BuildingState.buildings.values():
		if not BuildingState.is_player_owned(b): continue
		var rid := str(b.get("recipe_id",""))
		var local_goods: Array = ["g_006","g_007"] if rid=="r_009" else (["g_004"] if rid=="r_003" else (["g_005"] if rid=="r_008" else []))
		for gid in local_goods: MatchState.set_input_tile_only(str(b.instance_id),gid,true)
	var produced := {"g_004":70,"g_005":25,"g_006":44,"g_007":33,"g_008":33}
	var inputs := {"g_001":40,"g_002":40,"g_003":36}
	var sales := {"g_004":33,"g_006":12,"g_007":1,"g_008":33}
	for manifest in [produced,inputs,sales]:
		for gid in manifest: manifest[gid] *= copies
	var prices := MarketState.prices.duplicate(true)
	var sample: Array = []
	var rows: Array = []
	var previous := ""
	var routes := {}
	for tile in ["tile_5_4","tile_6_4"]:
		routes[tile]={}
		for gid in inputs:
			routes[tile][gid]=TransportService.quote_market_buy(tile,gid,1)
		routes["internal"] = TransportService.route("tile_6_4","tile_5_4","g_004")
	routes["sell"]=TransportService.quote_market_sell("tile_5_4",sales)
	for index in 120:
		MarketState.prices=prices.duplicate(true)
		MarketState.impact_pct.clear()
		var turn := TurnManager.current_turn
		var cash := MatchState.money
		TurnManager.commit_turn()
		await TurnManager.turn_resolution_completed
		var s := Production.last_turn_summary.duplicate(true)
		check(absf(MatchState.money-cash-Production.cash_change_of(s))<.01,"cash reconciliation %d"%turn)
		var stock := {"tile_5_4":Stockpile.get_tile_totals("tile_5_4").duplicate(true),"tile_6_4":Stockpile.get_tile_totals("tile_6_4").duplicate(true)}
		var transit := {}
		for sh: Dictionary in TransportState.pending_transport_shipments:
			var key := str(sh.get("good_id","sale"))+str(sh.get("is_purchase",false))
			transit[key]=int(transit.get(key,0))+int(sh.get("qty",0))
			for item in sh.get("sale_record",{}).get("items",[]):
				var k := "sale:"+str(item.good_id)
				transit[k]=int(transit.get(k,0))+int(item.qty)
		var signature := JSON.stringify([stock,transit])
		var regular := manifest_equal(s.produced,produced) and manifest_equal(s.purchased,inputs) and manifest_equal(s.sold,sales) and signature==previous
		previous=signature
		var costs := float(s.labour_paid)+float(s.maintenance_paid)+float(s.power_purchase_cost)
		var contribution := float(s.goods_sales_revenue)-float(s.goods_purchased_cost)-costs-float(s.transport_paid)-float(s.warehousing_paid)
		var row := {"turn":turn,"regular":regular,"stock":stock,"transit":transit,"summary":s,"factory_costs":costs,"contribution":contribution}
		rows.append(row)
		if regular and turn>=40:sample.append(row)
		else:sample.clear()
		if sample.size()==10:break
	check(sample.size()==10,"ten steady turns")
	check(LoanState.loans.is_empty(),"no borrowing")
	var result := {"copies":copies,"layout":layout,"expected_production":produced,"expected_inputs":inputs,"expected_sales":sales,"routes":routes,"sample":sample,"turns":rows,"failures":failures,"settled_links":TransportState.active_links()}
	DirAccess.make_dir_recursive_absolute(output_dir)
	var f := FileAccess.open(output_dir + "/result.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(result,"\t"))
	print("Five factory benchmark: ",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
