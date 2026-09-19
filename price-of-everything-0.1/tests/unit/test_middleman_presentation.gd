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
	_check(absf(float(p.fee)-32.5090815)<0.000001,"preview inclusive fee matches frozen tariff")
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
	var preview := Service.preview(second)
	Production._process_production()
	_check(int(Production.last_turn_summary.sold.g_008.qty)==66,"expansion produces two independent batches")
	_check(absf(float(Service.entry(second).receipts.input_fee)+float(Service.entry(second).receipts.output_fee)-float(preview.fee))<0.0001,"new building service bill matches completion preview")
	cleanup()

func _test_playable_start_and_short_intro() -> void:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/starts/pepper_valley_motors_playable.json"))
	var snap := SaveLoad.expand_start_config(cfg)
	_check(float(snap.match.money)==1500 and snap.match.middleman_service.buildings.size()==1,"playable start contains funded operating business")
	_check(str(snap.match.ruleset.tutorial_track)=="middleman","playable start selects dedicated introduction")
	var steps := preload("res://scripts/tutorial/middleman_steps.gd").steps()
	_check(steps.size()==5 and str(steps[-1].id)=="middleman_done","short introduction has safe completion path")
