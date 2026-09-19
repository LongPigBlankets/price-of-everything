extends Node
const Service := preload("res://scripts/middleman_service.gd")
const Paths := preload("res://scripts/app_paths.gd")
var failures: Array=[]
func check(ok: bool,label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)
func _enter_tree() -> void:
	Paths._base="/tmp/pepper-p3/runtime"
	RunMetrics.enabled=false
func _ready() -> void:
	preload("res://tools/shot_harness.gd").arm_watchdog(self,180.0)
	SaveLoad.autosave_enabled=false
	var args:=OS.get_cmdline_user_args()
	var chain:="steel" if args.has("--steel") else "five"
	var mode:="middleman" if args.has("--middleman") else ("mixed" if args.has("--mixed") else "managed")
	SaveLoad.prepare_new_game("res://data/starts/pepper_valley_motors.json",{"ruleset":{"logistics_model":"middleman_v1","tutorial_enabled":false}})
	var world: Node=load("res://scenes/main.tscn").instantiate()
	add_child(world)
	for frame in 160: await get_tree().process_frame
	TurnManager.fast_mode=true
	for system in [ResearchState,EventScheduler,DecisionState]:
		var hook:=Callable(system,"_on_phase_started")
		if TurnManager.phase_started.is_connected(hook): TurnManager.phase_started.disconnect(hook)
	var map_hook:=Callable(world,"_on_turn_advanced")
	if TurnManager.turn_advanced.is_connected(map_hook): TurnManager.turn_advanced.disconnect(map_hook)
	DecisionState.enabled=false
	DecisionState.auto_resolve=true
	SolvencyState.enabled=false
	MatchState.money=100000.0
	BuildingState.tile_land_owned["tile_6_4"]=200
	Catalog.add_tile_infrastructure("tile_6_4","cables")
	Catalog.set_tile_infra_level("tile_6_4","cables",1)
	var layout: Array=[["b_002","r_003","tile_5_4","g_006"]]
	if chain=="five": layout.append_array([["b_007","r_008","tile_5_4","g_007"],["b_002","r_007","tile_6_4","g_005"],["b_002","r_005","tile_6_4","g_004"]])
	for row: Array in layout:
		var iid:=BuildingState.add_building(row[0],row[1],row[2],MatchState.LOCAL_PLAYER)
		MatchState.set_output_stockpile_destination(iid,"tile_5_4",row[3])
		MatchState.enable_auto_sell_good("tile_5_4",row[3])
	var expected_produced:={}
	var expected_middleman_buys:={}
	var players: Array=[]
	for b: Dictionary in BuildingState.buildings.values():
		if not BuildingState.is_player_owned(b): continue
		var rid:=str(b.get("recipe_id",""))
		if rid not in Service.CHAIN_RECIPES: continue
		players.append(b)
		var recipe:=Catalog.get_recipe(rid)
		for item: Dictionary in recipe.inputs:
			expected_middleman_buys[str(item.good_id)]=int(expected_middleman_buys.get(str(item.good_id),0))+Production._scaled_input_qty(item,b)
		for item: Dictionary in recipe.outputs:
			expected_produced[str(item.good_id)]=int(item.qty)
		var local: Array=["g_006"] if rid=="r_009" else []
		if chain=="five": local=["g_006","g_007"] if rid=="r_009" else (["g_004"] if rid=="r_003" else (["g_005"] if rid=="r_008" else []))
		for gid: String in local: MatchState.set_input_tile_only(str(b.instance_id),gid,true)
		if mode=="middleman": check(Service.enable(str(b.instance_id)).ok,"enable independent building "+rid)
		elif mode=="mixed" and rid=="r_009": check(Service.set_mode(str(b.instance_id),"output","middleman").ok,"managed motor inputs and middleman sale")
	var remote:=args.has("--remote")
	if remote:
		for b: Dictionary in players:
			var rid:=str(b.recipe_id)
			if rid in ["r_005","r_007"]:
				var gid:="g_004" if rid=="r_005" else "g_005"
				MatchState.set_output_stockpile_destination(str(b.instance_id),"tile_6_4",gid)
				MatchState.enable_auto_sell_good("tile_6_4",gid)
			elif rid in ["r_003","r_008"]:
				check(Service.set_input_source(str(b.instance_id),"g_004" if rid=="r_003" else "g_005","tile_6_4").ok,"remote input source selected")
	var base_prices:=MarketState.prices.duplicate(true)
	var rows:=[]
	for turn in range(1,61):
		MarketState.prices=base_prices.duplicate(true)
		MarketState.impact_pct.clear()
		var before:=MatchState.money
		TurnManager.commit_turn()
		await TurnManager.turn_resolution_completed
		var s:=Production.last_turn_summary.duplicate(true)
		check(absf(MatchState.money-before-Production.cash_change_of(s))<0.0001,"cash reconciles %d"%turn)
		if turn>=40 and turn<=49:
			for gid: String in expected_produced: check(int(s.produced.get(gid,0))==int(expected_produced[gid]),"steady production %s turn %d"%[gid,turn])
		if mode=="middleman":
			check(Stockpile.get_all_totals().is_empty(),"no shared provider goods turn %d"%turn)
			for gid: String in expected_middleman_buys: check(int(s.purchased.get(gid,0))==int(expected_middleman_buys[gid]),"independent buys %s turn %d"%[gid,turn])
		if turn==30:
			var save:=SaveLoad.export_snapshot()
			SaveLoad.import_snapshot(JSON.parse_string(JSON.stringify(save)))
			if mode=="mixed":
				for b: Dictionary in players:
					if str(b.recipe_id)=="r_009": check(Service.uses_outputs(str(b.instance_id)) and not Service.uses_inputs(str(b.instance_id)),"mixed mode round trip")
		rows.append({"turn":turn,"cash":MatchState.money,"summary":s,"stock":Stockpile.get_all_totals().duplicate(true)})
	var averages:={}
	for row: Dictionary in rows:
		if int(row.turn)<40 or int(row.turn)>49: continue
		for key in ["goods_sales_revenue","goods_purchased_cost","middleman_fee","transport_paid","warehousing_paid","labour_paid","maintenance_paid","power_purchase_cost"]:
			averages[key]=float(averages.get(key,0.0))+float(row.summary.get(key,0.0))/10.0
	var report:={"status":"passed" if failures.is_empty() else "failed","chain":chain,"mode":mode,"remote_inputs":remote,"failures":failures,"execution":"60 actual turns; controlled prices, no JIT/research/events; no mines; large working-capital reserve isolates recurring economics","sample":"40-49","averages":averages,"rows":rows}
	DirAccess.make_dir_recursive_absolute("/tmp/pepper-p3")
	var f:=FileAccess.open("/tmp/pepper-p3/"+chain+"-"+mode+("-remote" if remote else "")+".json",FileAccess.WRITE)
	f.store_string(JSON.stringify(report,"  "))
	f.close()
	print("MIDDLEMAN_P3 ",JSON.stringify({"chain":chain,"mode":mode,"remote_inputs":remote,"failures":failures,"averages":averages}))
	get_tree().quit(0 if failures.is_empty() else 1)
