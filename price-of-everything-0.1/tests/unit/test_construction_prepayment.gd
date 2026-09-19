extends "res://tests/test_base.gd"
const FEATURE := "construction"
const Forecast := preload("res://scripts/cash_commitments.gd")

func _setup_cash() -> void:
	MatchState.reset()
	Stockpile.import_state({})
	LoanState.import_state({})
	Construction.import_state({})
	TurnManager.current_turn = 4
	MatchState.money = 10000.0
	MatchState.construct_material_source = "market"

func _test_confirmation_and_same_turn_cancellation_restore_cash_and_stock() -> void:
	_setup_cash()
	var tile := "tile_5_10"
	var kit := Construction.requirements_for("b_002")
	var good := str(kit.keys()[0])
	Stockpile.add(tile, good, 2)
	var stock := Stockpile.get_tile_totals(tile).duplicate()
	var quoted := Construction.estimate_market_cost(tile, "b_002")
	var market_before := MarketState._turn_bought.duplicate()
	MatchState.deduct_money(80.0)
	var iid := Construction.start_awaiting_market("b_002", "r_007", tile, 80.0)
	_check(not iid.is_empty(), "prepayment: project accepted")
	_check(absf(MatchState.money - (10000.0 - 80.0 - quoted)) < 0.01, "prepayment: complete quoted kit and fee leave treasury immediately")
	_check(is_zero_approx(MatchState.unpaid_purchase_total()), "prepayment: reserved cash does not consume purchase headroom twice")
	_check(Forecast.payments().is_empty(), "prepayment: materials already funded do not appear as another upcoming bill")
	_check(MarketState._turn_bought == market_before, "prepayment: reserving a purchase does not yet increase market pressure")
	_check(Construction.cancel(iid), "prepayment: same-turn cancellation succeeds")
	_check(is_equal_approx(MatchState.money, 10000.0), "prepayment: cancellation refunds fee, materials and freight exactly")
	_check(Stockpile.get_tile_totals(tile) == stock, "prepayment: only originally-owned stock is returned")
	_check(TransportState.pending_transport_shipments.is_empty(), "prepayment: cancelled material orders cannot later arrive")
	_check(not Construction.cancel(iid) and is_equal_approx(MatchState.money, 10000.0), "prepayment: repeated cancellation cannot refund twice")
	MatchState.reset()

func _test_reservations_survive_save_load_and_dispatch_without_double_charge() -> void:
	_setup_cash()
	var iid := Construction.start_awaiting_market("b_002", "r_007", "tile_5_10")
	var money := MatchState.money
	var transport := TransportState.export_fields()
	var projects := Construction.export_state()
	TransportState.import_fields(transport)
	Construction.import_state(projects)
	MatchState._recompute_unpaid_purchases()
	_check(is_zero_approx(MatchState.unpaid_purchase_total()), "prepayment: load does not resurrect an unpaid bill")
	var forecast := Forecast.snapshot()
	_check(is_zero_approx(float(Forecast.next_turn_costs(forecast).total)), "prepayment: awaiting project does not reorder its reserved kit")
	var summary := {"money_out": 0.0}
	Production._process_transport_arrivals(summary)
	_check(float(summary.get("prepaid_construction_arrived", 0.0)) > 0.0, "prepayment: arrival retains the material tax deduction without a cash debit")
	_check(is_equal_approx(MatchState.money, money) and is_zero_approx(float(summary.money_out)), "prepayment: delivery charges neither treasury nor next-turn spending again")
	_check(not TransportState.cancel_construction_reservations(iid) > 0.0, "prepayment: dispatched orders are no longer refundable reservations")
	Construction.claim_materials()
	_check(str(Construction.construction_projects[iid].status) == Construction.STATUS_UNDER_CONSTRUCTION, "prepayment: port delivery starts construction on the original first turn")
	MatchState.reset()

func _test_partial_confirmation_rolls_back_without_touching_another_project() -> void:
	_setup_cash()
	var first := Construction.start_awaiting_market("b_002", "r_007", "tile_5_10")
	var original_shipments := TransportState.pending_transport_shipments.duplicate(true)
	MatchState.money = 1.0
	var second := Construction.start_awaiting_market("b_002", "r_007", "tile_5_10")
	_check(second.is_empty() and is_equal_approx(MatchState.money, 1.0), "prepayment: unaffordable confirmation leaves no partial spend")
	_check(TransportState.pending_transport_shipments == original_shipments, "prepayment: failed second project preserves first project's orders")
	_check(Construction.construction_projects.has(first), "prepayment: first project remains intact")
	MatchState.reset()

func _test_own_stock_cancel_returns_materials_to_the_source_and_refunds_freight() -> void:
	_setup_cash()
	var source := "tile_5_10"
	var dest := "tile_5_11"
	var kit := Construction.requirements_for("b_002")
	for good: String in kit:
		Stockpile.add(source, good, int(kit[good]))
	var original := Stockpile.get_tile_totals(source).duplicate()
	var iid := Construction.start_awaiting_from_tile("b_002", "r_007", dest, source)
	_check(not TransportState.pending_transport_shipments.is_empty(), "prepayment: own materials are reserved in transit")
	Construction.cancel(iid)
	_check(is_equal_approx(MatchState.money, 10000.0), "prepayment: cancelling own-stock construction refunds freight")
	_check(Stockpile.get_tile_totals(source) == original, "prepayment: cancelled own materials return to their original tile")
	_check(TransportState.pending_transport_shipments.is_empty(), "prepayment: cancelled own-stock freight is removed")
	MatchState.reset()

func _test_prepaid_materials_preserve_tax_and_dividend_deductions() -> void:
	_setup_cash()
	var regular := {"money_in": 500.0, "money_out": 300.0, "goods_sales_revenue": 500.0}
	var prepaid := {"money_in": 500.0, "money_out": 100.0, "goods_sales_revenue": 500.0, "prepaid_construction_arrived": 200.0}
	var ordinary_profit := Production._apply_tax_and_dividends(regular)
	var prepaid_profit := Production._apply_tax_and_dividends(prepaid)
	_check(is_equal_approx(ordinary_profit, prepaid_profit), "prepayment: changing charge timing does not change taxable profit")
	_check(is_equal_approx(float(regular.taxes_paid), float(prepaid.taxes_paid)) and is_equal_approx(float(regular.dividends_paid), float(prepaid.dividends_paid)), "prepayment: tax and dividends retain the existing material deduction")
	MatchState.reset()
