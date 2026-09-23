extends "res://tests/unit/test_middleman_service.gd"
## Setup/cleanup reuse the isolated powered Pepper Valley fixture.
const Readout := preload("res://scripts/building_readout.gd")
const Graph := preload("res://scripts/empire_graph.gd")
const Commitments := preload("res://scripts/cash_commitments.gd")

func _test_preview_matches_live_and_is_pure() -> void:
	var ids := setup(2)
	var before := JSON.stringify(SaveLoad.export_snapshot())
	var p := Service.preview(str(ids[0]))
	_check(bool(p.can_run),"service preview admits a funded batch")
	_check(absf(float(p.fee)-40.3390815)<0.000001,"preview inclusive fee matches frozen tariff")
	_check(JSON.stringify(SaveLoad.export_snapshot())==before,"preview never changes money, goods, debt or receipts")
	var b: Dictionary = BuildingState.get_building(str(ids[0]))
	var e := Readout.economics(b,Catalog.get_recipe("r_009"),Catalog.get_building("b_007"))
	_check(bool(e.middleman) and float(e.warehousing_cost)==0,"building economics uses provider fee without shared storage")
	_check(Readout.run_state(b,Catalog.get_recipe("r_009"),false)=="restarting","zero-stock provider displays ready rather than missing inputs")
	Production._process_production()
	_check(absf(float(Production.last_turn_summary.middleman_fee)-2.0*float(p.fee))<0.000001,"two preview fees reconcile to live settlement")
	cleanup()

func _test_truck_endpoints_are_independent() -> void:
	var ids := setup(2)
	var g := Graph.build(fake)
	_check((g.ports as Array).any(func(p: Dictionary) -> bool: return str(p.iid)=="middleman" and p.icon==Graph.TRUCK_ICON),"gold sell endpoint uses truck")
	_check((g.buy_ports as Array).any(func(p: Dictionary) -> bool: return str(p.iid)=="buy_middleman" and p.icon==Graph.TRUCK_ICON),"gold buy endpoint uses truck")
	_check(g.sell_edges.size()==2 and g.market_edges.size()==2,"both provider factories have separate buy and sell connections")
	_check(g.edges.is_empty(),"provider customers never become internal suppliers")
	for node: Dictionary in g.nodes:
		if ids.has(str(node.iid)): _check(node.port_badge==Graph.TRUCK_ICON,"building sale badge uses truck on gold hex")
	cleanup()

func _test_forecast_excludes_provider_from_extra_alerts() -> void:
	var ids := setup()
	var data := Commitments.snapshot()
	_check(data.middleman.has(str(ids[0])),"cash forecast includes service operation")
	_check(float(Commitments.next_turn_costs(data).total)==0,"routine provider basket produces no exceptional-cost warning")
	_check(data.orders.size()==2 and str(data.orders[0].kind)=="middleman","forecast orders contain only actual provider input basket")
	MatchState.ruleset["middleman_new_buildings"] = true
	var projected := preload("res://scripts/build_forecast.gd").project("b_007","r_009","tile_5_4")
	_check(bool(projected.middleman) and int(projected.sale_delay)==0,"construction preview promises same-turn operating sales after completion")
	var second := Construction._complete_build("b_007","r_009","tile_5_4","inst_b_007_000099")
	_check(Service.enabled(second),"completed second motor factory automatically uses selected start's middleman policy")
	_check(Service.buys_output(second, "g_008") and not MatchState.is_output_market(second, "g_008")
		and MatchState.get_output_stockpile_destination(second, "g_008") == "",
		"new middleman building keeps its output private until the player changes it")
	var preview := Service.preview(second)
	Production._process_production()
	_check(int(Production.last_turn_summary.sold.g_008.qty)==66,"expansion produces two independent batches")
	_check(absf(float(Service.entry(second).receipts.input_fee)+float(Service.entry(second).receipts.output_fee)-float(preview.fee))<0.0001,"new building service bill matches completion preview")
	cleanup()

func _test_playable_start_and_short_intro() -> void:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/starts/pepper_valley_motors_playable.json"))
	var snap := SaveLoad.expand_start_config(cfg)
	_check(float(snap.match.money)==1500 and snap.match.middleman_service.buildings.size()==1,"playable start contains funded operating business")
	_check(not bool(snap.match.ruleset.get("tutorial_enabled", true)),
		"Pepper Valley Motors starts as a campaign, without the five-step tutorial coach")

func _test_temporary_sale_price_modifier_reaches_both_settlements() -> void:
	var ids := setup()
	var iid := str(ids[0])
	var good_id := "g_008"
	var ctx := {"good_id": good_id, "good_internal": Catalog.get_internal_name(good_id)}
	var base_price := MarketState.get_sale_price(good_id, ctx)
	var modifier_id := MiniQuest.GENERIC_SALE_REWARD_ID
	MiniQuest._grant_generic("global_surplus")
	var uplifted_price := MarketState.get_sale_price(good_id, ctx)
	_check(is_equal_approx(uplifted_price, base_price * 1.02), "global-surplus reward lifts the global sale quote by 2%")

	# Exercise the intermediary's authoritative settlement, not only its preview.  The contract
	# receives the same market sale snapshot used by a live provider sale.
	var e: Dictionary = Service.entry(iid)
	e["turn"] = TurnManager.current_turn
	e["state"] = "produced"
	e["outputs"] = {good_id: 1}
	e["prices"] = Service.prices()
	var middleman_summary := summary()
	Service.settle([BuildingState.get_building(iid)], middleman_summary)
	var receipt: Dictionary = Service.entry(iid).get("receipts", {}).get("sale", {})
	var middleman_item: Dictionary = (receipt.get("items", []) as Array)[0] if not (receipt.get("items", []) as Array).is_empty() else {}
	_check(is_equal_approx(float(middleman_item.get("goods_value", 0.0)), uplifted_price), "2% sale modifier reaches intermediary settlement")

	# The global route uses MarketState.execute_sale directly.  Its realised revenue must match
	# the same uplifted unit sale price, proving the modifier is applied at settlement rather than
	# only in a panel estimate.
	var global_sale := MarketState.execute_sale("tile_5_10", {good_id: 1}, {"skip_consume": true, "log_oneoff": false})
	_check(not global_sale.is_empty() and is_equal_approx(float(global_sale.get("total_revenue", 0.0)), uplifted_price), "2% sale modifier reaches global-market settlement")
	Modifiers.remove(modifier_id)
	cleanup()

func _test_input_route_primary_and_fallback_persist() -> void:
	var ids := setup()
	var iid := str(ids[0])
	var route := Service.input_source_route(iid, "g_006")
	_check(str(route.get("primary", "")) == "middleman", "legacy enabled service is the input primary")
	var managed := Service.set_input_route(iid, "g_006", "primary", "stockpile")
	_check(bool(managed.get("ok", false)), "physical input primary can replace the intermediary")
	var fallback := Service.set_input_route(iid, "g_006", "fallback", "market")
	_check(bool(fallback.get("ok", false)), "market can be saved as an input fallback")
	route = Service.input_source_route(iid, "g_006")
	_check(str(route.get("primary", "")) == "stockpile" and str(route.get("fallback", "")) == "market", "input route stores both slots")
	_check(not MatchState.is_input_tile_only(iid, "g_006"), "market fallback keeps market top-up enabled")
	var cleared := Service.set_input_route(iid, "g_006", "fallback", "")
	_check(bool(cleared.get("ok", false)) and str(Service.input_source_route(iid, "g_006").get("fallback", "")) == "middleman", "a cleared fallback returns to the intermediary, never none")
	_check(MatchState.is_input_tile_only(iid, "g_006"), "removing the market fallback stops market top-up")
	cleanup()
