extends "res://tests/unit/test_middleman_service.gd"
const Graph := preload("res://scripts/empire_graph.gd")

func _test_per_good_input_route_mixes_private_and_market_pipeline() -> void:
	var iid := str(setup()[0])
	_check(Service.set_good_mode(iid, "input", "g_006", "managed").ok, "switch one input to managed")
	Stockpile.add("tile_5_4", "g_006", 32)
	MatchState.set_input_tile_only(iid, "g_006", true)
	var before := MatchState.money
	Production._process_production()
	var s := Production.last_turn_summary
	_check(not Service.supplies_good(iid, "g_006") and Service.supplies_good(iid, "g_007"), "per-good input modes remain independent")
	_check(int(s.purchased.get("g_007", 0)) == 32 and int(s.purchased.get("g_006", 0)) == 0, "only the intermediary-selected input is privately purchased")
	_check(int(s.sold.get("g_008", {}).get("qty", 0)) == 33, "mixed input routes still complete the batch")
	_check(absf(MatchState.money - before - Production.cash_change_of(s)) < 0.0001, "per-good route cash reconciles")
	cleanup()

func _test_managed_inputs_middleman_output() -> void:
	var iid := str(setup()[0])
	_check(Service.set_mode(iid,"input","managed").ok,"switch only inputs to managed")
	Stockpile.add("tile_5_4","g_006",32)
	Stockpile.add("tile_5_4","g_007",32)
	MatchState.set_input_tile_only(iid,"g_006",true)
	MatchState.set_input_tile_only(iid,"g_007",true)
	var p := Service.preview(iid)
	var before := MatchState.money
	Production._process_production()
	var s := Production.last_turn_summary
	_check(int(s.sold.get("g_008",{}).get("qty",0))==33,"shared inputs produce middleman-sold motors")
	_check(s.purchased.is_empty(),"managed inputs are not also privately purchased")
	_check(absf(float(s.middleman_fee)-float(p.sale.fee))<0.00001,"only the output service fee is billed")
	_check(Stockpile.get_all_totals().is_empty(),"shared inputs consumed exactly once")
	_check(absf(MatchState.money-before-Production.cash_change_of(s))<0.0001,"mixed output case cash reconciles")
	_check(int(Production.compute_sell_reserve_for_tile("tile_5_4").get("g_006",0))==32,"managed consumer reserves shared steel")
	var g := Graph.build(fake)
	_check(not (g.market_edges as Array).any(func(e: Dictionary)->bool: return str(e.from)=="buy_middleman"),"managed inputs have no middleman graph connection")
	_check((g.sell_edges as Array).any(func(e: Dictionary)->bool: return str(e.to)=="middleman"),"output still has truck endpoint")
	cleanup()

func _test_middleman_inputs_retained_outputs() -> void:
	var iid := str(setup()[0])
	_check(Service.set_mode(iid,"output","managed").ok,"switch only output to managed")
	var p := Service.preview(iid)
	Production._process_production()
	var s := Production.last_turn_summary
	_check(Stockpile.get_at_tile("tile_5_4","g_008")==33,"managed output defaults to owned local storage")
	_check(s.sold.is_empty(),"retained output produces no sale proceeds")
	_check(absf(float(s.middleman_fee)-float(p.buy.fee))<0.00001,"retained output has no middleman sales fee")
	_check(Production.compute_sell_reserve_for_tile("tile_5_4").is_empty(),"private inputs never reserve shared stock")
	_check(not Service.has_assets(iid),"success consumed paid private inputs")
	var snap := SaveLoad.export_snapshot()
	SaveLoad.import_snapshot(JSON.parse_string(JSON.stringify(snap)))
	_check(Service.uses_inputs(iid) and not Service.uses_outputs(iid),"mixed modes persist through save/load")
	_check(Stockpile.get_at_tile("tile_5_4","g_008")==33,"owned retained stock survives reload")
	cleanup()

func _test_atomic_side_release_and_pipeline_preservation() -> void:
	var iid := str(setup()[0])
	Service.entry(iid).inputs={"g_006":32}
	Service.entry(iid).outputs={"g_008":33}
	Stockpile.add("tile_5_4","g_001",Stockpile.get_capacity("tile_5_4"))
	var cash := MatchState.money
	_check(not Service.set_mode(iid,"input","managed").ok,"full warehouse rejects transition atomically")
	_check(Service.uses_inputs(iid) and int(Service.entry(iid).inputs.g_006)==32,"rejection preserves mode and goods")
	Stockpile.consume("tile_5_4","g_001",32)
	_check(Service.set_mode(iid,"input","managed").ok,"release fits available capacity")
	_check(Stockpile.get_at_tile("tile_5_4","g_006")==32 and int(Service.entry(iid).outputs.g_008)==33,"only selected side is released")
	_check(MatchState.money==cash,"mode changes never refund or sell goods")
	TransportState.pending_transport_shipments.append({"good_id":"g_007","qty":7,"source_tile":"tile_5_5","destination_tile":"tile_5_4","turns_remaining":3,"paid":true})
	var pipeline := JSON.stringify(TransportState.pending_transport_shipments)
	_check(Service.set_mode(iid,"input","middleman").ok,"switch can coexist with an old physical delivery")
	_check(JSON.stringify(TransportState.pending_transport_shipments)==pipeline,"switch never alters existing physical delivery")
	cleanup()

func _test_colocated_furnace_feeds_managed_motor() -> void:
	var iid := str(setup()[0])
	Service.set_mode(iid,"input","managed")
	MatchState.set_input_tile_only(iid,"g_006",true)
	MatchState.set_input_tile_only(iid,"g_007",true)
	Stockpile.add("tile_5_4","g_007",32)
	Stockpile.add("tile_5_4","g_006",32) # established shared-stock cycle; no JIT unlock
	var furnace := BuildingState.add_building("b_002","r_003","tile_5_4",MatchState.LOCAL_PLAYER)
	_check(Service.enable(furnace).ok,"steel furnace uses selected heavy-goods tariff")
	Service.set_mode(furnace,"output","managed")
	Production._process_production()
	var s := Production.last_turn_summary
	_check(int(s.produced.get("g_006",0))==49 and int(s.sold.get("g_008",{}).get("qty",0))==33,"ordinary bounded cascade integrates same-tile steel and motors")
	_check(Stockpile.get_at_tile("tile_5_4","g_006")==49,"new furnace output is retained for the next operating cycle")
	_check(int(s.purchased.get("g_006",0))==0,"integrated motor never buys duplicate middleman steel")
	var before := Stockpile.get_at_tile("tile_5_4","g_006")
	Production._process_production()
	_check(Stockpile.get_at_tile("tile_5_4","g_006")==before,"repeated service hooks cannot manufacture a second private batch")
	cleanup()

func _test_remote_source_orders_scale_and_pause() -> void:
	var iid := str(setup()[0])
	Service.set_mode(iid,"input","managed")
	BuildingState.add_building("b_002","r_003","tile_6_4",MatchState.LOCAL_PLAYER)
	_check(Service.set_input_source(iid,"g_006","tile_6_4").ok,"remote stockpile is an explicit managed source")
	var order: Dictionary = TransportState.recurring_moves[-1]
	_check(int(Service.managed_move_goods(order).g_006)==32,"standing delivery matches current recipe consumption")
	BuildingState.buildings[iid].level=2
	_check(int(Service.managed_move_goods(order).g_006)==64,"standing delivery scales with building level")
	Service.set_mode(iid,"input","middleman")
	_check(Service.managed_move_goods(order).is_empty(),"future remote deliveries pause while using private input service")
	Service.set_mode(iid,"input","managed")
	_check(int(Service.managed_move_goods(order).g_006)==64,"managed mode resumes configured source")
	Service.set_input_source(iid,"g_006","auto")
	_check(not TransportState.recurring_moves.has(order),"choosing auto removes only this input's standing order")
	cleanup()

func _test_v12_migration_retains_both_service_sides() -> void:
	var iid := str(setup()[0])
	var snapshot:=SaveLoad.export_snapshot()
	snapshot.save_version=12
	SaveLoad.import_snapshot(JSON.parse_string(JSON.stringify(snapshot)))
	_check(Service.fully_managed(iid),"v12 whole-building service migrates to both middleman sides")
	_check(int(SaveLoad.export_snapshot().save_version)==SaveLoad.SAVE_VERSION,"new saves protect expanded logistics with current version")
	cleanup()

func _test_fallback_intermediary_buys_only_the_shortfall() -> void:
	var iid := str(setup()[0])
	_check(Service.set_good_mode(iid, "input", "g_006", "managed").ok, "take steel in-house")
	var route := Service.input_source_route(iid, "g_006")
	_check(str(route.primary) == "stockpile" and str(route.fallback) == "middleman", "an input taken in-house keeps the intermediary as its saved fallback")
	_check(MatchState.is_input_tile_only(iid, "g_006"), "the intermediary fallback does not also open market top-up")
	Stockpile.add("tile_5_4", "g_006", 20)
	var before := MatchState.money
	Production._process_production()
	var s := Production.last_turn_summary
	_check(int(s.purchased.get("g_006", 0)) == 12, "the fallback buys only the 12 steel the tile stock lacks")
	_check(int(s.purchased.get("g_007", 0)) == 32, "the intermediary input is still bought in full")
	_check(int(s.sold.get("g_008", {}).get("qty", 0)) == 33, "the bridged batch produces and sells")
	_check(Stockpile.get_at_tile("tile_5_4", "g_006") == 0 and Service.bridge_held(iid, "g_006") == 0, "tile stock and bridged units are both consumed")
	_check(absf(MatchState.money - before - Production.cash_change_of(s)) < 0.0001, "bridged batch cash reconciles")
	cleanup()

func _test_fallback_stays_idle_when_tile_stock_covers() -> void:
	var iid := str(setup()[0])
	_check(Service.set_good_mode(iid, "input", "g_006", "managed").ok, "take steel in-house")
	Stockpile.add("tile_5_4", "g_006", 40)
	Production._process_production()
	var s := Production.last_turn_summary
	_check(int(s.purchased.get("g_006", 0)) == 0, "no fallback purchase while the tile stock covers the batch")
	_check(Stockpile.get_at_tile("tile_5_4", "g_006") == 8, "the batch draws its 32 steel from the tile")
	cleanup()

func _test_fallback_shares_tile_stock_in_production_order() -> void:
	var ids := setup(2)
	for iid in ids:
		_check(Service.set_good_mode(str(iid), "input", "g_006", "managed").ok, "take steel in-house at both factories")
	Stockpile.add("tile_5_4", "g_006", 40)
	Production._process_production()
	var s := Production.last_turn_summary
	_check(int(s.purchased.get("g_006", 0)) == 24, "two consumers share 40 steel and the fallback buys the remaining 24")
	_check(int(s.sold.get("g_008", {}).get("qty", 0)) == 66, "both factories run")
	_check(Stockpile.get_at_tile("tile_5_4", "g_006") == 0, "shared stock is not double-counted")
	cleanup()

func _test_fallback_holding_survives_failure_and_reload() -> void:
	var iid := str(setup()[0])
	_check(Service.set_good_mode(iid, "input", "g_006", "managed").ok, "take steel in-house")
	Stockpile.add("tile_5_4", "g_006", 20)
	Service.prepare([BuildingState.get_building(iid)], summary())
	_check(Service.bridge_held(iid, "g_006") == 12, "the fallback purchase is held privately for the building")
	var snap := SaveLoad.export_snapshot()
	SaveLoad.import_snapshot(JSON.parse_string(JSON.stringify(snap)))
	_check(Service.bridge_held(iid, "g_006") == 12, "paid fallback goods survive save/load")
	TurnManager.current_turn += 1
	Production._process_production()
	var s := Production.last_turn_summary
	_check(int(s.purchased.get("g_006", 0)) == 0, "held fallback goods are reused before buying again")
	_check(int(s.sold.get("g_008", {}).get("qty", 0)) == 33, "the retained purchase completes the next batch")
	_check(Service.bridge_held(iid, "g_006") == 0 and Stockpile.get_at_tile("tile_5_4", "g_006") == 0, "held units and tile stock are consumed once")
	cleanup()

func _test_mixed_goods_survive_taking_outputs_in_house() -> void:
	var iid := str(setup()[0])
	_check(Service.set_mode(iid, "output", "managed").ok, "take outputs in-house")
	_check(Service.set_good_mode(iid, "input", "g_007", "managed").ok, "take wiring in-house")
	_check(Service.supplies_good(iid, "g_006"), "steel stays with the intermediary when no side is fully on it")
	var snap := SaveLoad.export_snapshot()
	SaveLoad.import_snapshot(JSON.parse_string(JSON.stringify(snap)))
	_check(Service.supplies_good(iid, "g_006") and not Service.supplies_good(iid, "g_007"), "the mixed per-good setup survives save/load")
	cleanup()

func _test_legacy_rules_have_no_intermediary_fallback() -> void:
	var iid := str(setup()[0])
	_check(Service.set_good_mode(iid, "input", "g_006", "managed").ok, "take steel in-house")
	MatchState.ruleset["logistics_model"] = ""
	_check(not Service.bridges_good(iid, "g_006"), "without the intermediary ruleset nothing is bridged")
	var legacy := BuildingState.add_building("b_007", "r_009", "tile_5_4", MatchState.LOCAL_PLAYER)
	var route := Service.input_source_route(legacy, "g_006")
	_check(str(route.fallback) == "market", "a legacy building keeps stock-first market top-up, not the intermediary")
	Stockpile.add("tile_5_4", "g_006", 20)
	Service.prepare(BuildingState.buildings.values().filter(func(b: Dictionary) -> bool: return BuildingState.is_player_owned(b)), summary())
	_check(Service.bridge_held(legacy, "g_006") == 0 and Service.bridge_held(iid, "g_006") == 0, "legacy rules never buy a fallback shortfall")
	cleanup()

func _test_same_turn_cancel_refunds_an_intermediary_kit() -> void:
	setup()
	var before := MatchState.money
	var project := Construction.start_awaiting_middleman("b_007", "r_009", "tile_5_4", 0.0)
	_check(project != "" and MatchState.money < before, "the intermediary construction kit is paid when ordered")
	_check(Construction.cancel(project), "the order can be cancelled before delivery")
	_check(absf(MatchState.money - before) < 0.0001, "cancelling before delivery refunds the kit in full")
	cleanup()
