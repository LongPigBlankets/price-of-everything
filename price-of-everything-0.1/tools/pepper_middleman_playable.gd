extends Node
## Live public-start acceptance: actual construction, expansion and reload. The start has
## no coach introduction; its Logistics mission tree carries the progression instead.
const Service := preload("res://scripts/middleman_service.gd")
const Paths := preload("res://scripts/app_paths.gd")
const OUT := "/tmp/pepper-middleman-p2"
var failures: Array = []
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)
func _enter_tree() -> void:
	Paths._base=OUT+"/runtime"
	RunMetrics.enabled=false
	TelemetryState.enabled=false
func _ready() -> void:
	TelemetryState.enabled=false
	preload("res://tools/shot_harness.gd").arm_watchdog(self,180.0)
	AudioServer.set_bus_mute(0,true)
	SaveLoad.autosave_enabled=false
	SaveLoad.prepare_new_game("res://data/starts/pepper_valley_motors_playable.json")
	var world: Node=load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	await get_tree().process_frame
	get_tree().current_scene=world
	for frame in 180: await get_tree().process_frame
	TurnManager.fast_mode=true
	check(not Tutorial.active,"public start opens straight into play without a coach")
	# No research or random decisions: retain changing market prices, ordinary
	# construction delivery, expenses, solvency and actual turn execution.
	for system in [ResearchState,EventScheduler,DecisionState]:
		var hook:=Callable(system,"_on_phase_started")
		if TurnManager.phase_started.is_connected(hook): TurnManager.phase_started.disconnect(hook)
	DecisionState.enabled=false
	DecisionState.auto_resolve=true
	var rows:=[]
	var second:=""
	var completed_turn:=0
	var initial_motor_price:=MarketState.get_price("g_008")
	var fee:=maxf(0,float(Catalog.get_building("b_007").base_price))
	var before_cancel:=MatchState.money
	MatchState.add_money(-fee)
	var cancelled:=Construction.start_awaiting_market("b_007","r_009","tile_5_4",fee)
	check(cancelled!="","normal construction order can reserve materials")
	check(Construction.cancel(cancelled),"construction can cancel before dispatch")
	check(absf(MatchState.money-before_cancel)<0.0001,"cancellation refunds cash and material reservations")
	check(TransportState.pending_transport_shipments.is_empty(),"cancelled project leaves no pipeline")
	for turn in range(1,51):
		if turn==2:
			MatchState.add_money(-fee)
			second=Construction.start_awaiting_market("b_007","r_009","tile_5_4",fee)
			check(second!="","second factory starts using public starting cash")
			check(not Service.enabled(second),"construction is not enrolled before completion")
			check(not TransportState.pending_transport_shipments.is_empty(),"construction materials travel through ordinary transport")
		var project: Dictionary=Construction.construction_projects.get(second,{})
		if str(project.get("status",""))==Construction.STATUS_UNDER_CONSTRUCTION and int(project.get("turns_remaining",0))==1:
			var forecast:=preload("res://scripts/cash_commitments.gd").snapshot()
			check(forecast.middleman.size()==2,"completion forecast includes both independent middleman batches")
			check((forecast.orders as Array).all(func(row: Dictionary)->bool: return str(row.kind)=="middleman"),"completion creates no false physical input orders")
		var before:=MatchState.money
		TurnManager.commit_turn()
		await TurnManager.turn_resolution_completed
		for frame in 3: await get_tree().process_frame
		var s: Dictionary=Production.last_turn_summary.duplicate(true)
		check(absf(MatchState.money-before-Production.cash_change_of(s))<0.0001,"cash reconciles turn %d"%turn)
		check(MatchState.money>=0,"public business remains solvent turn %d"%turn)
		if second!="" and Service.enabled(second):
			if completed_turn==0: completed_turn=turn
			check(int(s.sold.get("g_008",{}).get("qty",0))==66,"both factories sell independent batches turn %d"%turn)
			check(Stockpile.get_all_totals().is_empty(),"completed factories do not share stock turn %d"%turn)
		rows.append({"turn":turn,"cash":MatchState.money,"motor_sales":s.sold.get("g_008",{}),"middleman_fee":s.get("middleman_fee",0),"active_factories":MatchState.middleman_service.buildings.size()})
		if turn==25:
			var snapshot:=SaveLoad.export_snapshot()
			SaveLoad.import_snapshot(JSON.parse_string(JSON.stringify(snapshot)))
			check(Service.enabled(second),"reload retains expanded service")
			check(not Tutorial.active,"reload does not start a coach")
	check(completed_turn>0,"actual construction completed within acceptance horizon")
	check(MarketState.get_price("g_008")!=initial_motor_price,"test used evolving market prices")
	var report:={"status":"passed" if failures.is_empty() else "failed","failures":failures,"starting_cash":1500,"construction_cash_fee":fee,"second_factory_completed_turn":completed_turn,"execution":"50 real turns, evolving market prices; no research/random decisions; actual public start, construction, cancellation and reload","rows":rows}
	DirAccess.make_dir_recursive_absolute(OUT)
	var file:=FileAccess.open(OUT+"/report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("MIDDLEMAN_P2 ",JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
