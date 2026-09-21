extends "res://tests/test_base.gd"
const FEATURE := "middleman"
const Contract := preload("res://scripts/middleman_contract.gd")

func prices() -> Dictionary:
	var out := {}
	for good in Contract.PROTOTYPE_GOODS:
		var ctx := {"good_id":good,"good_internal":str(Catalog.get_good(good).get("internal_name", ""))}
		out[good] = {"reference":MarketState.get_price(good),"buy":MarketState.get_buy_price(good),"sale":MarketState.get_sale_price(good,ctx),"transport_class":Catalog.get_good(good).get("transport_class", "")}
	return out

func budget(cash: float, credit: float = 0.0) -> Dictionary:
	return {"cash":cash,"credit_available":credit,"commitments":0.0,"running_reserve":0.0,"minimum_loan":EconomyConfig.LOAN_MINIMUM}

func _test_quote_uses_actual_market_prices_and_does_not_trade() -> void:
	var p := prices()
	var state := JSON.stringify([MatchState.money,Stockpile.export_state(),MarketState.export_state(),LoanState.export_state(),TransportState.export_fields()])
	var buy := Contract.quote("buy",[{"good":"g_006","quantity":32},{"good":"g_007","quantity":32}],p,1.5)
	var sell := Contract.quote("sell",[{"good":"g_008","quantity":33}],p,1.5)
	_check(buy.ok and sell.ok,"both ordinary market sides can be quoted")
	_check(absf(buy.goods_value - 32.0*(MarketState.get_buy_price("g_006")+MarketState.get_buy_price("g_007")))<0.000001,"goods purchases match market API prices")
	_check(absf(sell.goods_value-33.0*p.g_008.sale)<0.000001,"sale uses ordinary sale API including its modifier context")
	var expected: float = 32*(.005*p.g_006.reference+.12)+32*(.005*p.g_007.reference+.12)
	_check(absf(buy.fee-expected)<0.000001,"fee excludes buying markup, includes full reference price")
	_check(state==JSON.stringify([MatchState.money,Stockpile.export_state(),MarketState.export_state(),LoanState.export_state(),TransportState.export_fields()]),"quote has no cash, stock, volume, debt or shipment side effects")
	p.g_006.reference = 12.0
	p.g_006.buy = 12.6
	p.g_006.sale = 12.3
	var changed := Contract.quote("buy",[{"good":"g_006","quantity":2}],p,1.5)
	_check(absf(changed.goods_value-25.2)<0.000001 and absf(changed.fee-.36)<0.000001,"changed market snapshot affects goods and fee separately")

func _test_split_order_and_zero_quantity_are_fee_invariant() -> void:
	var p := prices()
	var whole := Contract.quote("buy",[{"good":"g_006","quantity":32}],p,1.5)
	var split := Contract.quote("buy",[{"good":"g_006","quantity":12},{"good":"g_006","quantity":20},{"good":"unused","quantity":0}],p,1.5)
	_check(whole==split,"split/reordered calls canonicalise to the same complete basket")
	var zero := Contract.quote("buy",[],p,1.5)
	_check(zero.ok and zero.cash_out==0 and zero.fee==0,"no activity means no fee")
	_check(not Contract.quote("buy",[{"good":"g_006","quantity":-1}],p,1.5).ok,"negative quantity rejected")
	_check(not Contract.quote("buy",[{"good":"g_006","quantity":.5}],p,1.5).ok,"fractional goods rejected")
	_check(not Contract.quote("buy",[{"good":"g_001","quantity":1}],p,1.5).ok,"unsupported prototype good does not get silent service")
	_check(not Contract.quote("buy",[{"good":"g_006","quantity":1}],{},1.5).ok,"missing price rejects entire quote")
	_check(not Contract.quote("buy",[],p,9.0).ok,"unknown location cannot quote")

func _test_complete_batch_funding_boundary_and_running_reserve() -> void:
	var p := prices()
	var need := {"g_006":32,"g_007":32}
	var full := Contract.plan_batch(need,{},p,1.5,budget(1000))
	var required := float(full.batch_reserve)
	_check(Contract.plan_batch(need,{},p,1.5,budget(required)).ok,"exact complete-basket funding accepted")
	var poor := Contract.plan_batch(need,{},p,1.5,budget(required-.01))
	_check(not poor.ok and poor.reason=="insufficient_funding" and not poor.has("purchase"),"short by a penny rejects whole batch without partial purchase")
	var b := budget(required+15)
	b.commitments=10.0
	b.running_reserve=6.0
	_check(not Contract.plan_batch(need,{},p,1.5,b).ok,"due commitments and running reserve cannot be spent on ingredients")
	b.cash+=1.0
	_check(Contract.plan_batch(need,{},p,1.5,b).ok,"funded operating reserve admits full batch")
	b.anticipated_sales=1000000.0
	b.cash=0.0
	_check(not Contract.plan_batch(need,{},p,1.5,b).ok,"anticipated sales never create budget")

func _test_explicit_credit_respects_loan_minimum_and_reuses_surplus() -> void:
	var p := prices()
	var need := {"g_006":32,"g_007":32}
	var full := Contract.plan_batch(need,{},p,1.5,budget(1000))
	var cost := float(full.batch_reserve)
	var plan := Contract.plan_batch(need,{},p,1.5,budget(cost-1,20))
	_check(plan.ok and absf(plan.funding_draw-20)<0.000001,"one pound short requests the real minimum loan")
	_check(absf(plan.unallocated_cash-19)<0.000001 and absf(plan.credit_remaining)<0.000001,"surplus loan cash remains available, capacity is used once")
	_check(not Contract.plan_batch(need,{},p,1.5,budget(cost-1,19)).ok,"nominal shortfall below capacity still rejects an unavailable minimum loan")
	var b := budget(1000)
	b.building_credit_tab=true
	_check(Contract.plan_batch(need,{},p,1.5,b).reason=="unsupported_building_credit_tab","unimplemented tab funding cannot receive a synthetic second refund")

func _test_private_partial_holdings_complete_or_wait_and_failed_batch_reuses() -> void:
	var p := prices()
	var need := {"g_006":32,"g_007":32}
	var held := {"g_006":12}
	var before := JSON.stringify(held)
	var plan := Contract.plan_batch(need,held,p,1.5,budget(1000))
	_check(plan.ok and plan.reuse.g_006==12,"building uses its own existing partial holding")
	_check(plan.purchase.items[0].quantity==20 and plan.purchase.items[1].quantity==32,"only missing quantities quoted, but both ingredients funded")
	_check(JSON.stringify(held)==before,"planning does not consume paid holdings")
	_check(not Contract.plan_batch(need,held,p,1.5,budget(0)).ok,"unaffordable top-up leaves partial holding intact")
	_check(Contract.plan_batch(need,{},p,1.5,budget(1000),false).reason=="production_blocked","known power/resource failure prevents acquisition")
	# A previous post-acquisition failure left the complete cycle owned by this building.
	var retry := Contract.plan_batch(need,need,p,1.5,budget(0))
	_check(retry.ok and retry.purchase.cash_out==0 and retry.purchase.fee==0,"paid complete holding retries without another buy or fee")
	var other := Contract.plan_batch(need,{},p,1.5,budget(0))
	_check(not other.ok,"neighbour cannot claim another building's private holding")
	_check(Contract.plan_batch(need,{"g_006":33},p,1.5,budget(1000)).reason=="holding_exceeds_cycle","no unlimited operating warehouse")
	_check(Contract.plan_batch(need,{"g_008":1},p,1.5,budget(1000)).reason=="unreleased_holding","recipe changes require explicit leftover disposition")

func _test_identity_and_private_holding_fixture_round_trip() -> void:
	_check(Contract.operation_id("m",3,"b")!=Contract.operation_id("m",4,"b"),"turn identity is distinct")
	_check(Contract.operation_id("m/a",3,"b")!=Contract.operation_id("m",3,"a/b"),"identifiers cannot collide through separator ambiguity")
	var f: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/scenarios/middleman_phase0_holding_fixture.json"))
	var loaded: Dictionary = JSON.parse_string(JSON.stringify(f))
	var p := prices()
	var holding: Dictionary = loaded.middleman_service.buildings.motor_a.input_holdings
	var retry := Contract.plan_batch({"g_006":32,"g_007":32},holding,p,1.5,budget(0))
	_check(retry.ok and retry.purchase.cash_out==0,"proposed holding fixture retains paid goods across serialization")
	_check(loaded.middleman_service.settled_ids==f.middleman_service.settled_ids,"idempotency receipts survive serialization; runtime replay gate is phase 1")
	_check(not f.ruleset.has("logistics_model") or f.ruleset.logistics_model=="middleman_v1","fixture explicitly opts in, does not mutate legacy saves")

func _test_versioned_contract_matches_pure_profile() -> void:
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/scenarios/middleman_phase0_contract.json"))
	_check(int(spec.contract_version)==Contract.VERSION and spec.tariff.id==Contract.TARIFF_ID,"version and tariff identifiers are consistent")
	_check(absf(float(spec.tariff.ad_valorem)-Contract.AD_VALOREM)<0.000001,"active fee is 0.5 percent")
	for cargo: String in spec.tariff.class_rates:
		_check(spec.tariff.class_rates[cargo]==Contract.CLASS_RATES[cargo],"historical class rate matches executable quote: "+cargo)
	_check(spec.prototype.goods==Contract.PROTOTYPE_GOODS,"prototype eligibility is explicit")

func _test_pepper_golden_quote_and_cash_trace() -> void:
	var f: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/snapshots/middleman_phase0_reference_v1.json"))
	var b := budget(1000)
	b.running_reserve=float(f.running_reserve)
	var plan := Contract.plan_batch(f.required,{},f.prices,float(f.coefficient),b)
	var sell := Contract.quote("sell",[{"good":"g_008","quantity":33}],f.prices,float(f.coefficient))
	_check(absf(plan.purchase.goods_value-f.expected.input_goods)<0.000001,"golden goods purchase matches baseline market spread")
	_check(absf(plan.purchase.fee-f.expected.input_fee)<0.000001,"golden input fee matches dynamic tariff")
	_check(absf(sell.fee-f.expected.output_fee)<0.000001,"golden output fee matches dynamic tariff")
	_check(absf(plan.batch_reserve-f.expected.required_starting_funding)<0.000001,"startup reserve includes inputs, fee and running costs without sale proceeds")
	var close: float = plan.cash_after_purchase + sell.net_receipt - float(f.running_reserve)
	_check(absf(close-f.funding_trace.closing_after_operating_costs)<0.000001,"reference cash trace reconciles without freight/port/storage double charge")
	for g in f.prices:
		_check(absf(float(Catalog.get_good(g).get("base_price",0))-float(f.prices[g].reference))<0.000001,"golden catalogue price stays versioned: "+str(g))
