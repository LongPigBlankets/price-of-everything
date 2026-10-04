extends "res://tests/test_base.gd"
const FEATURE := "middleman"
const Service := preload("res://scripts/middleman_service.gd")
var fake: Node
var backup: Dictionary

func setup(count: int = 1, cables: bool = true) -> Array:
	backup = SaveLoad.export_snapshot().duplicate(true)
	MatchState.reset()
	Stockpile.clear_all()
	LoanState.loans.clear()
	Modifiers.reset()
	TurnManager.current_turn = 1
	TurnManager.current_phase = TurnManager.Phase.DECIDE
	MatchState.money = 10000.0
	MatchState.ruleset["logistics_model"] = "middleman_v1"
	# The Logistics missions' rewards (a tile stockpile's +5% output) would change the batches under test.
	for node_id: String in ["middleman_contracts", "tile_stockpile", "global_license", "global_surplus"]:
		MiniQuest.generic_granted[node_id] = true
	# Routes off the intermediary need their research. The tests about the locks take it away again.
	open_routes()
	fake = Node.new()
	var src := GDScript.new()
	src.source_code = "extends Node\nvar tiles := {}\nfunc id_to_coord(_t): return Vector2i(5,4)\nfunc coord_to_id(_c): return 'tile_5_4'\n"
	src.reload()
	fake.set_script(src)
	fake.set("tiles",{Vector2i(5,4):{"id":"tile_5_4","terrain":"urban","infrastructure_present":["cables"] if cables else [],"infrastructure_levels":{"cables":1}}})
	fake.add_to_group("hex_map")
	get_tree().root.add_child(fake)
	var ids := []
	for i in count:
		var iid: String = BuildingState.add_building("b_007","r_009","tile_5_4",MatchState.LOCAL_PLAYER)
		_check(Service.enable(iid).ok,"explicit supported prototype opt-in")
		ids.append(iid)
	return ids

func open_routes(contracts: bool = true, license: bool = true) -> void:
	for pair: Array in [[ResearchState.OPEN_LOGISTICS_CONTRACTS_TITLE, contracts], [ResearchState.GLOBAL_TRADE_LICENSE_TITLE, license]]:
		if bool(pair[1]): ResearchState.unlocked_titles[str(pair[0])] = true
		else: ResearchState.unlocked_titles.erase(str(pair[0]))
	ResearchState._global_trade_license_paid = license

func cleanup() -> void:
	fake.free()
	SaveLoad.import_snapshot(backup)

func summary() -> Dictionary:
	return {"goods_purchased_cost":0.0,"money_out":0.0,"money_in":0.0,"goods_sales_revenue":0.0,"transport_paid":0.0,"transport_breakdown":{},"purchased":{},"purchased_cost":{},"goods_purchased_by_type":{},"sold":{}}

func _test_live_zero_stock_and_independent_buildings() -> void:
	var ids := setup(2)
	var cash := MatchState.money
	Production._process_production()
	var s: Dictionary = Production.last_turn_summary
	_check(int(s.produced.get("g_008",0))==66 and int(s.sold.get("g_008",{}).get("qty",0))==66,"real production sells two independent motor batches")
	_check(int(s.purchased.get("g_006",0))==64 and int(s.consumed.get("g_007",0))==64,"each building purchases and consumes its full inputs")
	_check(TransportState.pending_transport_shipments.is_empty(),"provider creates no physical shipments")
	_check(Stockpile.get_tile_totals("tile_5_4").is_empty(),"private operating goods never enter shared stock")
	_check(absf(MatchState.money-cash-Production.cash_change_of(s))<0.0001,"live provider cash reconciles")
	_check(float(s.get("middleman_fee",0.0))>0 and float(s.warehousing_paid)==0,"inclusive fee and no separate storage fee")
	var before := MatchState.money
	Service.settle(BuildingState.buildings.values(),s)
	Service.prepare(BuildingState.buildings.values(),s)
	_check(MatchState.money==before,"duplicate supply/settlement cannot charge or sell twice")
	for iid in ids: _check(Service.entry(iid).state=="settled","each private batch settled")
	cleanup()

func _test_live_preflight_and_failure_recovery_save() -> void:
	var ids := setup(1,false)
	var iid: String = ids[0]
	var s := summary()
	Service.prepare(BuildingState.buildings.values(),s)
	_check(Service.entry(iid).inputs.is_empty() and s.money_out==0,"known missing cables buys nothing")
	fake.set("tiles",{Vector2i(5,4):{"id":"tile_5_4","terrain":"urban","infrastructure_present":["cables"],"infrastructure_levels":{"cables":1}}})
	TurnManager.current_turn += 1
	Service.prepare(BuildingState.buildings.values(),s)
	_check(int(Service.entry(iid).inputs.get("g_006",0))==32,"funded complete basket acquired privately")
	Service.settle(BuildingState.buildings.values(),s) # Production could not execute after acquisition.
	_check(Service.entry(iid).state=="blocked_with_private_inputs","post-purchase failure retains paid inputs")
	_check(not BuildingState.remove_building(iid),"removal cannot destroy paid goods")
	var save: Dictionary = SaveLoad.export_snapshot()
	SaveLoad.import_snapshot(JSON.parse_string(JSON.stringify(save)))
	_check(Service.entry(iid).holding_receipts.size()==1 and int(Service.entry(iid).inputs.g_006)==32,"actual SaveLoad round trip preserves paid inputs and original receipt")
	TurnManager.current_turn += 1
	Production._process_production()
	_check(Production.last_turn_summary.purchased.is_empty(),"next real production reuses retained ingredients without buying again")
	_check(int(Production.last_turn_summary.sold.get("g_008",{}).get("qty",0))==33,"retained inputs produce and sell once")
	_check(float(Service.entry(iid).receipts.get("input_fee",-1))==0,"no repeated input fee")
	cleanup()

## A building the intermediary runs can change recipe: the goods it holds move into the tile's stock, it buys
## nothing while the building retools, and it follows the new recipe once it is in.
func _test_retrofit_releases_private_goods() -> void:
	var ids := setup(1)
	var iid: String = ids[0]
	var s := summary()
	Service.prepare(BuildingState.buildings.values(), s)
	Service.settle(BuildingState.buildings.values(), s)
	_check(Service.has_assets(iid), "the service holds paid inputs for the building")
	var other := ""
	for r: Dictionary in Catalog.get_recipes_for_building("b_007"):
		if str(r.get("recipe_id", "")) != "r_009" and Catalog.is_recipe_demo_available(r):
			other = str(r.get("recipe_id", ""))
			break
	if other == "":
		_check(true, "retrofit: skipped (no second recipe for the factory)")
		cleanup()
		return
	var held := int(Service.entry(iid).inputs.get("g_006", 0))
	var res: Dictionary = BuildingWorks.start_retrofit(iid, other)
	_check(bool(res.get("ok", false)) and BuildingWorks.is_retooling(iid), "an intermediary building can start a retrofit")
	_check(not Service.has_assets(iid) and Stockpile.get_at_tile("tile_5_4", "g_006") == held,
		"its held goods move into the tile's stock")
	TurnManager.current_turn += 1
	var s2 := summary()
	Service.prepare(BuildingState.buildings.values(), s2)
	_check(float(s2.money_out) == 0.0 and Service.entry(iid).inputs.is_empty(), "nothing is bought while it retools")
	for _i in 4:
		BuildingWorks.tick_retrofits()
	_check(str(BuildingState.get_building(iid).get("recipe_id", "")) == other and str(Service.entry(iid).get("recipe_id", "")) == other,
		"the service follows the new recipe")
	cleanup()

## A batch the intermediary refused shows in the turn briefing, worded as the building's diagnostics word it;
## one held back by the player's own pause or retrofit does not.
func _test_refused_batch_alerts_the_briefing() -> void:
	var ids := setup(2)
	TurnBriefing._alert_dismissed.erase("alert:intermediary_refused")
	var saved_blocked: Dictionary = Production.blocked_reason_by_building.duplicate(true)
	var saved_run: Dictionary = Production.last_turn_run.duplicate(true)
	Production.last_turn_run = {}
	Production.blocked_reason_by_building = {
		str(ids[0]): {"code": "middleman", "message": "insufficient_funding"},
		str(ids[1]): {"code": "middleman", "message": "Building paused or recipe changed."},
	}
	var item: Dictionary = TurnBriefing._intermediary_refused_item()
	var listed: Array = item.get("list", [])
	_check(str(item.get("id", "")) == "alert:intermediary_refused" and int(item.get("magnitude", 0)) == 1
		and listed.size() == 1 and str((listed[0] as Dictionary).get("instance_id", "")) == str(ids[0]),
		"briefing: a refused batch raises an alert, a paused building does not")
	_check(str((listed[0] as Dictionary).get("why", "")).begins_with("Not enough cash"), "briefing: the refusal reads as the diagnostics read it")
	Production.blocked_reason_by_building = saved_blocked
	Production.last_turn_run = saved_run
	cleanup()

## Without the Import/Export License an intermediary game can't reach the global market by any route: the
## buy and sell primitives every manual trade goes through refuse it, and so does an upgrade's market mode.
func _test_global_market_needs_the_license() -> void:
	var ids := setup(1)
	open_routes(true, false)
	Stockpile.add("tile_5_4", "g_008", 5)
	_check(MatchState.queue_buy("tile_5_4", "g_006", 4).is_empty(), "license: no global-market buy without it")
	_check(MatchState.queue_sell("tile_5_4", {"g_008": 5}).is_empty() and Stockpile.get_at_tile("tile_5_4", "g_008") == 5,
		"license: no global-market sale without it, and the goods stay put")
	ResearchState.unlocked_titles["Conveyor Mass Assembly"] = true   # the factory's level 2
	var up: Dictionary = BuildingWorks.start_upgrade(str(ids[0]), "market")
	_check(not bool(up.get("ok", true)) and str(up.get("reason", "")).contains(ResearchState.GLOBAL_TRADE_LICENSE_TITLE)
		and not BuildingWorks.is_upgrading(str(ids[0])),
		"license: an upgrade can't order its materials from the global market without it (%s)" % str(up.get("reason", "")))
	cleanup()

## The supply chain board draws no lane to a port for output the intermediary buys: it never goes there.
func _test_board_draws_no_port_lane_for_intermediary_output() -> void:
	var ids := setup(1)
	var iid := str(ids[0])
	# A start routes its buildings' output "to market" even where the intermediary buys it.
	MatchState.output_stockpile_destinations[iid] = {"g_008": MatchState.MARKET_DESTINATION}
	var lanes: Dictionary = preload("res://scripts/empire_board_model.gd").real_lanes([{"iid": iid, "tile": "tile_5_4", "good": "g_008"}])
	var to_port := false
	for key in lanes:
		to_port = to_port or (str((lanes[key] as Dictionary).get("kind", "")) == "sell" and str((lanes[key] as Dictionary).get("good", "")) == "g_008")
	_check(Service.buys_output(iid, "g_008") and not to_port, "board: no sell lane to a port for output the intermediary buys")
	cleanup()

func _test_live_shortage_and_legacy_default() -> void:
	var ids := setup()
	MatchState.money = -1000000.0
	var s := summary()
	var loans := LoanState.loans.size()
	Service.prepare(BuildingState.buildings.values(),s)
	_check(s.money_out==0 and Service.entry(str(ids[0])).inputs.is_empty(),"unfundable basket rejects without partial inputs")
	_check(LoanState.loans.size()==loans,"rejected basket never draws credit")
	var old: Dictionary = SaveLoad.export_snapshot()
	old.save_version = 11
	old.match.erase("middleman_service")
	SaveLoad.import_snapshot(SaveLoad._migrate(old))
	_check(MatchState.middleman_service.is_empty(),"old port-rate flag never auto-enables middleman service")
	cleanup()

## Two batches short of cash in one turn borrow through one loan, sized to what both drew, and both still run.
func _test_funding_draws_one_loan_per_turn() -> void:
	setup(2)
	MatchState.money = 0.0
	var before := MatchState.money
	Production._process_production()
	var s: Dictionary = Production.last_turn_summary
	var financing := float(s.get("middleman_financing", 0.0))
	var loan_principal: float = float(LoanState.loans[0].principal_initial) if LoanState.loans.size() == 1 else -1.0
	_check(int(s.sold.get("g_008", {}).get("qty", 0)) == 66 and LoanState.loans.size() == 1 and absf(loan_principal - financing) < 0.0001,
		"two short batches borrow through one loan of what they drew (%d loans, £%.2f drawn, %d motors sold)" % [LoanState.loans.size(), financing, int(s.sold.get("g_008", {}).get("qty", 0))])
	_check(absf(MatchState.money - before - Production.cash_change_of(s)) < 0.0001, "the one loan's cash reconciles")
	cleanup()

func _test_live_funding_and_accounting() -> void:
	var ids := setup()
	var b: Dictionary = BuildingState.get_building(str(ids[0]))
	var recipe: Dictionary = Catalog.get_recipe("r_009")
	var purchase := Service.Contract.quote("buy",[{"good":"g_006","quantity":32},{"good":"g_007","quantity":32}],Service.prices(),1.5)
	MatchState.money = float(purchase.cash_out)+Production._calculate_maintenance_cost(b)+Production._calculate_labour_cost(b,recipe)+30.0*EconomyConfig.GRID_BUY_PRICE-1.0
	var before := MatchState.money
	Production._process_production()
	var s: Dictionary = Production.last_turn_summary
	_check(absf(float(s.get("middleman_financing",0))-20.0)<0.0001,"actual funding draws minimum loan before goods purchase")
	_check(LoanState.loans.size()==1,"one explicit loan, no implicit anticipated-sale funding")
	_check(absf(MatchState.money-before-Production.cash_change_of(s))<0.0001,"financed cash reconciles without inflating operating revenue")
	_check(absf(preload("res://scripts/money_panel.gd").net_cash_of(s)-Production.cash_change_of(s))<0.0001,"money panel includes financing separately")
	_check(absf(float(s.money_in)-float(s.goods_sales_revenue))<0.0001,"loan proceeds do not inflate revenue")
	_check(absf(Production.borrowed_of(s)-20.0)<0.0001 and absf(Production.net_of(s)-(Production.cash_change_of(s)-20.0))<0.0001,
		"the turn's net leaves out what was borrowed; the cash change keeps it")
	cleanup()

func _test_blocked_output_retry_and_explicit_release() -> void:
	var ids := setup()
	var iid := str(ids[0])
	var s := summary()
	Service.prepare(BuildingState.buildings.values(),s)
	Service.consume(iid,"g_006",32)
	Service.consume(iid,"g_007",32)
	Service.produce(iid,"g_008",33)
	Service.entry(iid).prices.g_008.sale=0.0
	Service.settle(BuildingState.buildings.values(),s)
	_check(Service.entry(iid).outputs.get("g_008",0)==33,"negative-net sale retains actual output")
	TurnManager.current_turn += 1
	Service.prepare(BuildingState.buildings.values(),s)
	_check(not Service.ready(iid),"held output prevents another production cycle")
	Service.settle(BuildingState.buildings.values(),s)
	_check(Service.entry(iid).outputs.is_empty() and int(s.sold.get("g_008",{}).get("qty",0))==33,"retained output settles once at next market snapshot")
	TurnManager.current_turn += 1
	Service.prepare(BuildingState.buildings.values(),s)
	_check(not Service.disable(iid).ok,"cannot disable and lose private assets")
	_check(Service.release_to_stock(iid).ok,"explicit release moves paid inputs to owned storage")
	_check(Stockpile.get_at_tile("tile_5_4","g_006")==32 and not Service.has_assets(iid),"released goods have one owner")
	_check(Service.disable(iid).ok,"mode can be disabled after disposition")
	cleanup()

func _test_mixed_arrivals_and_direct_factory_stay_separate() -> void:
	var ids := setup()
	MatchState.sell_mode = MatchState.SellMode.STOCKPILE_ALL
	var direct := BuildingState.add_building("b_007","r_009","tile_5_4",MatchState.LOCAL_PLAYER)
	Stockpile.add("tile_5_4","g_007",32)
	TransportState.pending_transport_shipments = [
		{"id":90001,"good_id":"g_006","qty":32,"source_tile":"tile_1_1","destination_tile":"tile_5_4","transport_turns":1,"turns_remaining":1,"is_purchase":true,"purchase_cost":20.0,"purchase_goods_cost":20.0},
		{"id":90002,"good_id":"g_003","qty":5,"source_tile":"tile_1_1","destination_tile":"tile_5_4","transport_turns":2,"turns_remaining":2}]
	MatchState._recompute_unpaid_purchases()
	var before := MatchState.money
	Production._process_production()
	var s: Dictionary = Production.last_turn_summary
	_check(bool(Production.last_turn_run.get(direct,false)) and bool(Production.last_turn_run.get(str(ids[0]),false)),"ordinary arrival feeds direct factory alongside private provider batch")
	_check(int(Service.entry(str(ids[0])).receipts.purchase.items[1].quantity)==32,"provider still buys wire rather than using neighbour stock")
	_check(Stockpile.get_at_tile("tile_5_4","g_008")==33,"only direct factory output reaches shared stock")
	var old_remaining := -1
	var new_unmoved := true
	for shipment: Dictionary in TransportState.pending_transport_shipments:
		if int(shipment.get("id",0))==90002: old_remaining = int(shipment.turns_remaining)
		else: new_unmoved = new_unmoved and int(shipment.turns_remaining)==int(shipment.transport_turns)
	_check(old_remaining==1,"existing physical shipment advances exactly once")
	_check(new_unmoved,"direct replenishment dispatches without moving new shipments this turn")
	_check(absf(MatchState.money-before-Production.cash_change_of(s))<0.0001,"mixed arrival payment and provider settlement reconcile together")
	cleanup()
