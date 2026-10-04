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
	_check(absf(float(p.fee)-58.6222134)<0.000001,"preview inclusive fee matches frozen tariff")
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

## A building the intermediary supplies keeps its power and output rows beside the intermediary's own,
## and a refused batch says why in a sentence.
func _test_diagnostics_keep_every_check_under_the_intermediary() -> void:
	var ids := setup()
	var iid: String = ids[0]
	var Readout: GDScript = load("res://scripts/building_readout.gd")
	var recipe: Dictionary = Catalog.get_recipe("r_009")
	var data: Dictionary = Catalog.get_building("b_007")
	var find := func(rows: Array, label: String) -> Dictionary:
		for row: Dictionary in rows:
			if str(row.get("label", "")) == label: return row
		return {}
	var rows: Array = Readout.diagnostics(BuildingState.get_building(iid), recipe, data, false)
	var own: Dictionary = find.call(rows, Readout.INTERMEDIARY_LABEL)
	_check(str(own.get("tone", "")) == "ok", "a funded batch lights the intermediary's row green")
	_check(rows.any(func(row: Dictionary) -> bool: return str(row.get("ic", "")) == "bolt"), "the power row shows under the intermediary")
	_check(not (find.call(rows, "Output sold to Local Suppliers") as Dictionary).is_empty(), "the output row names Local Suppliers")
	_check(not rows.any(func(row: Dictionary) -> bool: return str(row.get("label", "")) in ["Cannot run", "Starved of inputs", "Inputs idle"]),
		"an empty tile stockpile is not read as a shortage")
	MatchState.money = -1000000.0
	rows = Readout.diagnostics(BuildingState.get_building(iid), recipe, data, false)
	own = find.call(rows, Readout.INTERMEDIARY_LABEL)
	_check(str(own.get("tone", "")) == "bad" and str(own.get("detail", "")) == "Not enough cash or borrowing room to pay for this batch.",
		"an unfunded batch is red and says why (%s)" % str(own.get("detail", "")))
	_check(Readout.diagnostic_led_tone(rows) == "bad" and rows.size() > 1, "the lamp is red and the other rows stay")
	_check(Readout.intermediary_reason("Production Blocked") == Readout.intermediary_reason("production_blocked")
		and not Readout.intermediary_reason("unreleased_holding").contains("_"), "contract codes never reach the player")
	cleanup()

## The tile-wide routing the tile view's knobs turn lives in the service: one call routes a side of every
## building on the tile, and the same call reads back which choice is in force.
func _test_tile_policy_applies_and_reads_back() -> void:
	var ids := setup(2)
	var tile := "tile_5_4"
	_check(Service.tile_policy_active(tile, "input", "middleman", ids) and not Service.tile_policy_active(tile, "input", "managed", ids),
		"a new intermediary tile reads as intermediary inputs")
	var to_stock: Dictionary = Service.apply_tile_policy(tile, "input", "stockpile", ids)
	_check(bool(to_stock.get("ok", false)) and Service.tile_policy_active(tile, "input", "stockpile", ids)
		and not Service.tile_policy_active(tile, "input", "middleman", ids), "inputs turned to the tile stockpile read back as stockpile (%s)" % str(to_stock.get("reason", "")))
	_check(str(Service.input_source_route(str(ids[0]), "g_006").get("fallback", "")) == "middleman", "a stockpile input keeps the intermediary as its fallback")
	var to_market: Dictionary = Service.apply_tile_policy(tile, "output", "market", ids)
	_check(bool(to_market.get("ok", false)) and Service.tile_policy_active(tile, "output", "market", ids), "outputs turned to the market read back as market")
	var back: Dictionary = Service.apply_tile_policy(tile, "input", "middleman", ids)
	_check(bool(back.get("ok", false)) and Service.tile_policy_active(tile, "input", "middleman", ids), "inputs turned back to the intermediary")
	_check(Service.active() and Service.global_market_open() == ResearchState.global_trade_license_available(), "the market opens with the license in an intermediary game")
	cleanup()


## Before their research, the routes off the intermediary are closed in the service itself, whatever a
## control asks for. Each opens with its own unlock.
func _test_routes_stay_locked_until_their_research() -> void:
	var ids := setup()
	var iid: String = ids[0]
	open_routes(false, false)
	var managed: Dictionary = Service.set_mode(iid, "output", "managed")
	_check(not bool(managed.ok) and Service.side_all_middleman(iid, "output"), "outputs cannot leave the intermediary before any unlock (%s)" % str(managed.get("reason", "")))
	_check(not bool(Service.set_good_mode(iid, "input", "g_006", "managed").ok), "one input cannot leave the intermediary either")
	_check(not bool(Service.apply_tile_policy("tile_5_4", "input", "stockpile", ids).ok) and not bool(Service.apply_tile_policy("tile_5_4", "output", "market", ids).ok),
		"the tile-wide switch is refused too")
	_check(bool(Service.set_mode(iid, "output", "middleman").ok), "staying with the intermediary is always allowed")
	open_routes(true, false)
	_check(bool(Service.set_good_mode(iid, "input", "g_006", "managed").ok), "Open Logistics Contracts opens the tile stockpile")
	var market: Dictionary = Service.set_input_route(iid, "g_006", "primary", "market")
	_check(not bool(market.ok) and str(market.get("reason", "")).contains(ResearchState.GLOBAL_TRADE_LICENSE_TITLE), "the market still needs the license (%s)" % str(market.get("reason", "")))
	open_routes(true, true)
	_check(bool(Service.set_input_route(iid, "g_006", "primary", "market").ok), "the license opens the market")
	MatchState.ruleset["logistics_model"] = "legacy"
	_check(Service.route_lock("market") == "" and Service.route_lock("stockpile") == "", "a game without the intermediary has no locks")
	cleanup()

## With cash for one batch only, the preview names the same building the turn then funds: the one whose
## batch earns most (here the later, larger factory), not the one built first.
func _test_preview_funds_in_the_turns_order() -> void:
	var ids := setup(2)
	var later := str(ids[1])
	BuildingState.get_building(later)["level"] = 2
	var order: Array = Service.funding_order(BuildingState.buildings.values(), Service.prices())
	_check(str((order[0] as Dictionary).instance_id) == later, "the larger factory's batch earns most and is funded first")
	# No borrowing room, and cash for the larger batch alone.
	LoanState.loans.append({"id": 999, "principal_initial": 1.0e9, "principal_remaining": 1.0e9, "payment_per_turn": 0.0, "turns_remaining": 99, "interest_paid": 0.0, "interest_rate": 0.0})
	var one: Dictionary = Service.preview_building(BuildingState.get_building(later))
	MatchState.money = float(one.upfront) + float(one.protected_commitments) + 1.0
	var previews: Dictionary = Service.company_previews()
	var ready: Array = ids.filter(func(i: String) -> bool: return bool(previews[i].can_run))
	_check(ready == [later], "the preview funds the larger factory and refuses the first built (%s)" % str(ready))
	Production._process_production()
	var ran: Array = ids.filter(func(i: String) -> bool: return Production.last_turn_run.has(i))
	_check(ready == ran, "the turn runs the buildings the preview said were ready (%s against %s)" % [str(ready), str(ran)])
	cleanup()

## What a turn borrows reaches the top bar's notices: the loan's principal is counted, and a loan the
## intermediary drew for its batches is named as that.
func _test_loan_notice_counts_the_turns_loan() -> void:
	setup()
	var bar: Node = load("res://scripts/top_bar.gd").new()
	bar.call("_on_loan_taken", {"id": 1, "principal_initial": 55.0})
	_check(is_equal_approx(float(bar.get("_loan_taken_this_turn")), 55.0), "the loan's principal is what the notice counts")
	var funded: String = bar.call("loan_notice_text", 55.0, {"middleman_financing": 55.0})
	var other: String = bar.call("loan_notice_text", 55.0, {"middleman_financing": 0.0})
	_check(funded.contains("Local Suppliers") and funded.contains("55") and not other.contains("Local Suppliers"),
		"a loan for Local Suppliers' batches says so (%s / %s)" % [funded, other])
	bar.free()
	cleanup()
