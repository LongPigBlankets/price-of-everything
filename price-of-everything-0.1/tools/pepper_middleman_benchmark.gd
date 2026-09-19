extends Node
const Service := preload("res://scripts/middleman_service.gd")
const Paths := preload("res://scripts/app_paths.gd")
const OUT := "/tmp/pepper-middleman-phase1"
var failures: Array = []
var output_dir := OUT
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)
func _enter_tree() -> void:
	if OS.get_cmdline_user_args().has("--funding"): output_dir += "-funded"
	Paths._base = output_dir+"/runtime"
	RunMetrics.enabled = false
func _ready() -> void:
	preload("res://tools/shot_harness.gd").arm_watchdog(self,180.0)
	AudioServer.set_bus_mute(0,true)
	SaveLoad.autosave_enabled = false
	SaveLoad.prepare_new_game("res://data/starts/pepper_valley_motors_middleman.json")
	var world: Node = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	for frame in 160: await get_tree().process_frame
	TurnManager.fast_mode = true
	for system in [ResearchState,EventScheduler,DecisionState]:
		var hook := Callable(system,"_on_phase_started")
		if TurnManager.phase_started.is_connected(hook): TurnManager.phase_started.disconnect(hook)
	var map_hook := Callable(world,"_on_turn_advanced")
	if TurnManager.turn_advanced.is_connected(map_hook): TurnManager.turn_advanced.disconnect(map_hook)
	DecisionState.enabled = false
	DecisionState.auto_resolve = true
	SolvencyState.enabled = false
	var ids: Array = MatchState.middleman_service.get("buildings",{}).keys()
	check(ids.size()==1,"start explicitly enables one provider factory")
	if ids.size()!=1:
		get_tree().quit(1)
		return
	var iid := str(ids[0])
	if OS.get_cmdline_user_args().has("--funding"): MatchState.money = 300.0
	var prices: Dictionary = MarketState.prices.duplicate(true)
	var rows := []
	for turn in range(1,51):
		MarketState.prices = prices.duplicate(true)
		MarketState.impact_pct.clear()
		var before := MatchState.money
		TurnManager.commit_turn()
		await TurnManager.turn_resolution_completed
		var s: Dictionary = Production.last_turn_summary.duplicate(true)
		check(int(s.produced.get("g_008",0))==33,"turn %d produces 33 motors" % turn)
		check(int(s.sold.get("g_008",{}).get("qty",0))==33,"turn %d sells actual motors" % turn)
		check(TransportState.pending_transport_shipments.is_empty(),"provider has no physical pipeline")
		check(Stockpile.get_all_totals().is_empty(),"provider has no shared storage")
		check(absf(MatchState.money-before-Production.cash_change_of(s))<0.0001,"cash reconciliation turn %d" % turn)
		check(absf(float(s.get("middleman_fee",0))-32.5090815)<0.0001,"dynamic inclusive fee turn %d" % turn)
		var common := float(s.labour_paid)+float(s.maintenance_paid)+float(s.power_purchase_cost)
		rows.append({"turn":turn,"goods_purchases":s.goods_purchased_cost,"goods_sales":s.goods_sales_revenue,
			"middleman_fee":s.middleman_fee,"factory_costs":common,"operating_contribution":float(s.goods_sales_revenue)-float(s.goods_purchased_cost)-float(s.middleman_fee)-common,
			"cash_before":before,"cash_after":MatchState.money,"summary":s})
		if turn==25:
			var saved: Dictionary = SaveLoad.export_snapshot()
			SaveLoad.import_snapshot(JSON.parse_string(JSON.stringify(saved)))
			check(Service.entry(iid).state=="settled","mid-benchmark reload retains receipts")
	var mean := 0.0
	for row: Dictionary in rows:
		if int(row.turn)>=40 and int(row.turn)<=49: mean += float(row.operating_contribution)/10.0
	var report := {"status":"passed" if failures.is_empty() else "failed","execution":"real TurnManager and Production; controlled catalogue prices, no research/events/public road building","turns":50,"sample":"40-49","mean_operating_contribution":mean,"failures":failures,"rows":rows}
	DirAccess.make_dir_recursive_absolute(output_dir)
	var f := FileAccess.open(output_dir+"/report.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(report,"  "))
	f.close()
	print("MIDDLEMAN_PHASE1 ",JSON.stringify({"failures":failures,"mean_operating_contribution":mean}))
	get_tree().quit(0 if failures.is_empty() else 1)
