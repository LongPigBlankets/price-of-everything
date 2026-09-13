extends "res://tests/test_base.gd"
const FEATURE := "cash_commitments"
const Forecast := preload("res://scripts/cash_commitments.gd")
const Allocator := preload("res://scripts/input_order_planner.gd")

func _test_loan_schedule_tracks_actual_payment_turns() -> void:
	MatchState.reset()
	LoanState.import_state({})
	TurnManager.current_turn = 3
	LoanState._create_loan(100.0, 0.075, 10, 0)
	var loan: Dictionary = LoanState.loans[0]
	_check(LoanState.loan_label(loan) == "Loan #1 (7.5%)", "loan label preserves fractional interest rates")
	_check(LoanState.repayment_turns(loan) == Vector2i(3, 12), "new loan starts repayment on the next resolved turn")
	for turn in range(3, 13):
		TurnManager.current_turn = turn
		_check(LoanState.repayment_turns(loan) == Vector2i(3, 12), "original repayment range stays fixed before payment at turn %d" % turn)
		LoanState.process_payments()
		if turn < 12:
			_check(LoanState.repayment_turns(loan) == Vector2i(3, 12), "range stays fixed during post-payment UI refresh")
		else:
			_check(LoanState.loans.is_empty(), "final payment occurs on displayed last turn")
	LoanState.import_state({})
	MatchState.reset()

func _test_loan_grace_schedule_survives_conversion_and_load() -> void:
	MatchState.reset()
	LoanState.import_state({})
	TurnManager.current_turn = 20
	LoanState.take_grace_loan(100.0, 2)
	var loan: Dictionary = LoanState.loans[0]
	var expected := Vector2i(22, 22 + EconomyConfig.LOAN_TERM_TURNS - 1)
	_check(LoanState.repayment_turns(loan) == expected, "grace loan predicts first actual payment, not grace expiry")
	for turn in [20, 21]:
		TurnManager.current_turn = turn
		_check(is_zero_approx(LoanState.process_payments()), "grace and conversion turns charge no payment")
		_check(LoanState.repayment_turns(loan) == expected, "grace conversion preserves full repayment range")
	TurnManager.current_turn = 22
	var saved := LoanState.export_state()
	LoanState.import_state(saved)
	loan = LoanState.loans[0]
	_check(LoanState.repayment_turns(loan) == expected, "legacy saved loan without schedule fields shows correct dates")
	_check(LoanState.process_payments() > 0.0, "first payment occurs on displayed grace-loan start turn")
	_check(LoanState.repayment_turns(loan) == expected, "grace-loan dates remain fixed after first payment")
	MatchState.reset()
	LoanState.loans.clear()
	LoanState._create_loan(100.0, 0.1, 10, 0)
	_check(LoanState.repayment_turns(LoanState.loans[0]).x == TurnManager.current_turn, "new match clears prior payment-phase offset")
	LoanState.import_state({})
	MatchState.reset()

func _test_booked_payments_exclude_paid_and_separate_grace() -> void:
	MatchState.reset()
	Stockpile.import_state({})
	LoanState.loans = [
		{"id": 1, "principal_initial": 60.0, "principal_remaining": 60.0, "payment_per_turn": 5.0, "grace_remaining": 0, "interest_rate": 0.1, "interest_paid": 0.0, "turns_remaining": 12},
		{"id": 2, "principal_initial": 100.0, "principal_remaining": 100.0, "payment_per_turn": 0.0, "grace_remaining": 1, "total_repayment": 120.0, "interest_rate": 0.1, "interest_paid": 0.0, "turns_remaining": 37},
	]
	TransportState.pending_transport_shipments = [
		{"purchase_cost": 27.5, "purchase_goods_cost": 25.0, "turns_remaining": 1, "good_id": "g_003", "qty": 10, "destination_tile": "tile_5_10"},
		{"purchase_cost": 40.0, "turns_remaining": 2, "good_id": "g_003", "qty": 10, "destination_tile": "tile_5_10"},
		{"turns_remaining": 1, "good_id": "g_003", "qty": 10, "destination_tile": "tile_5_10"},
	]
	TransportState.overflow_shipments = [{"good_id": "g_003", "qty": 10, "destination_tile": "tile_5_10"}]
	MatchState.building_tabs = {"trial": {"turns_left": 0, "mode": "slices", "slices_left": 3, "accrued": 30.0}}
	var rows := Forecast.payments()
	_check(absf(Forecast.due_total(rows) - 42.5) < 0.001, "due includes billed freight once, loan and building credit; excludes already-paid overflow")
	_check(rows.size() == 5, "future bill and grace loan remain visible separately")
	_check(int(rows[3].due_in) == 2, "loan grace expiry is not a same-turn cash payment")
	var cash := MatchState.money
	MatchState.tick_building_tabs()
	LoanState.process_payments()
	_check(absf(cash - MatchState.money - 15.0) < 0.001, "actual loan/tab payments match forecast while grace conversion stays non-cash")
	LoanState.loans.clear()
	MatchState.reset()

func _test_preview_shipping_does_not_roll_ledger() -> void:
	MatchState.reset()
	TurnManager.current_turn = 3
	TransportState._sea_shipping_turn = 2
	TransportState._sea_port_usage_this_turn = {"tile_5_10": {"solid_heavy": 100}}
	TransportState._sea_port_charges_this_turn = {"tile_5_10": {"g_003": {"total": 1.0}}}
	var before := JSON.stringify(TransportState.export_fields())
	var quote := TransportState.preview_sea_shipping("tile_5_10", "g_003", 10)
	_check(JSON.stringify(TransportState.export_fields()) == before, "shipping quote preserves live and completed ledgers")
	_check(int(quote.get("used_before", -1)) == 0, "quote uses empty usage for the new turn without rotating state")
	var committed := TransportState.commit_sea_shipping("tile_5_10", "g_003", 10, "buy")
	_check(absf(float(committed.total) - float(quote.total)) < 0.001, "committing the quote preserves its price")
	_check(TransportState._last_sea_shipping_turn == 2, "actual shipment rotates completed ledger")
	MatchState.reset()

func _test_shared_stock_allocator_and_capacity() -> void:
	var entries: Array = [{"inputs": {"g_003": 10}}, {"inputs": {"g_003": 10}}]
	var leads := {"g_003": {"port": "tile_5_10", "lead": 1}}
	var stock := {"g_003": 25}
	var result := Allocator.allocate(entries, leads, {}, stock, {}, 100, 1.0)
	_check(int(result.orders.get("g_003", 0)) == 15, "two buildings share one stock pool rather than double-counting it")
	_check(int(stock.g_003) == 25, "allocator preserves caller stock")
	var capped := Allocator.allocate(entries, leads, {}, stock, {}, 5, 1.0)
	_check(int(capped.wanted.g_003) == 15 and int(capped.orders.g_003) == 5, "unfunded working set remains visible when storage caps orders")

func _test_extra_cost_total_is_shared_and_excludes_routine_costs() -> void:
	var data := {"due": 20.0, "labour": 8.0, "maintenance": 2.0,
		"orders": [{"kind": "input", "qty": 10, "amount": 15.0, "payment_in": 1},
		{"kind": "construction", "amount": 100.0, "payment_in": 3}]}
	var costs := Forecast.next_turn_costs(data)
	_check(is_equal_approx(float(costs.total), 0.0), "extra costs exclude construction payable later and routine spending")
	_check(costs == Forecast.attention_costs(data, {"actual_orders": []}), "panel and notice share the same total regardless of ordering history")

func _test_credit_expiry_repayment_and_refinance_cash() -> void:
	MatchState.reset()
	LoanState.loans.clear()
	MatchState.money = 1000.0
	MatchState.building_tabs = {
		"expiring": {"turns_left": 1, "accrued": 60.0, "mode": "slices", "slices_left": 0},
		"paying": {"turns_left": 0, "accrued": 120.0, "mode": "slices", "slices_left": 3},
		"refinancing": {"turns_left": 1, "accrued": 90.0, "mode": "loan", "slices_left": 0}}
	var before := MatchState.money
	var movements := MatchState.tick_building_tabs()
	_check(is_equal_approx(float(movements.repaid), 40.0), "credit: window expiry does not charge its first slice early")
	_check(is_equal_approx(float(movements.loan_received), 90.0), "credit: refinancing cash is recorded separately from repayments")
	_check(is_equal_approx(MatchState.money - before, float(movements.loan_received) - float(movements.repaid)), "credit: simultaneous borrowing and repayment reconcile to actual cash")
	_check(not MatchState.building_tabs.has("refinancing"), "credit: converted tab is not resurrected or repaid twice")
	before = MatchState.money
	movements = MatchState.tick_building_tabs()
	_check(is_equal_approx(float(movements.repaid), 40.0 + 60.0 / MatchState.TAB_SLICES), "credit: first instalment starts the turn after the window closes")
	_check(is_equal_approx(before - MatchState.money, float(movements.repaid)), "credit: next instalments reconcile to actual cash")
	var summary := {"money_in": 500.0, "money_out": 100.0, "goods_sales_revenue": 500.0,
		"labour_paid": 140.0, "building_tab_carried": 40.0, "building_credit_repaid": 30.0,
		"building_credit_loan_received": 90.0}
	_check(is_equal_approx(Production.cash_change_of(summary), 460.0), "credit: cash report includes financing without changing operating net")
	_check(is_equal_approx(preload("res://scripts/money_panel.gd").net_cash_of(summary), 460.0), "credit: Balance rows match cash report with both financing directions")
	_check(is_equal_approx(Production.cash_change_of({"money_in": 20.0, "money_out": 5.0}), 15.0), "credit: old summaries without new fields still render")
	LoanState.loans.clear()
	MatchState.reset()

func _test_attention_costs_exclude_routine_spending() -> void:
	var previous := {"actual_orders": [{"tile": "a", "good": "ore", "qty": 10}]}
	var data := {"labour": 500.0, "maintenance": 200.0, "payments": [
		{"kind": "shipment", "source_kind": "shipment", "amount": 100.0, "due_in": 1}],
		"orders": [{"kind": "input", "tile": "a", "good": "ore", "qty": 10, "amount": 100.0},
		{"kind": "recurring", "tile": "a", "good": "coal", "qty": 20, "amount": 200.0}]}
	_check(is_zero_approx(float(Forecast.attention_costs(data, previous).total)), "notice: ordinary bills, continuing orders, standing purchases and running costs do not trigger")
	(data.payments as Array).append_array([
		{"kind": "shipment", "source_kind": "construction", "amount": 25.0, "due_in": 1},
		{"kind": "shipment", "source_kind": "upgrade", "amount": 30.0, "due_in": 3},
		{"kind": "credit", "amount": 5.0, "due_in": 1},
		{"kind": "loan", "amount": 9.0, "due_in": 1},
		{"kind": "loan", "amount": 50.0, "due_in": 3}])
	(data.orders as Array).append({"kind": "input", "tile": "b", "good": "ore", "qty": 4, "amount": 40.0})
	var alert := Forecast.attention_costs(data, previous)
	_check(is_equal_approx(float(alert.bills), 25.0) and is_equal_approx(float(alert.later), 0.0) and is_equal_approx(float(alert.orders), 0.0), "notice: only construction/upgrade bills count; routine loans and intermittent input orders are excluded")
	var shared := {"orders": [{"kind": "input", "tile": "a", "good": "ore", "qty": 20, "amount": 100.0, "new_building_qty": 4}]}
	_check(is_equal_approx(float(Forecast.attention_costs(shared, previous).orders), 20.0), "notice: a new building sharing an input with a running factory contributes only its share")
	_check(is_zero_approx(float(Forecast.attention_costs({"orders": [data.orders[0]]}, {}).total)), "notice: no history after load does not label all existing orders as new")

func _test_order_trace_preserves_shared_allocation() -> void:
	var entries := [{"instance_id": "old", "inputs": {"ore": 10}}, {"instance_id": "new", "inputs": {"ore": 10}}]
	var leads := {"ore": {"port": "port", "lead": 1}}
	var basic := Allocator.allocate(entries, leads, {}, {"ore": 15}, {}, 100, 1.0)
	var traced := Allocator.allocate(entries, leads, {}, {"ore": 15}, {}, 100, 1.0, true)
	_check(basic.orders == traced.orders and basic.wanted == traced.wanted, "order attribution does not change planned purchases")
	_check(int(traced.by_instance.old.ore) == 5 and int(traced.by_instance.new.ore) == 20, "new factory allocation excludes the older factory's five units")

func _test_startup_cost_shares_and_unpaid_arrivals() -> void:
	var data := {"payments": [{"kind": "shipment", "amount": 100.0, "extra_amount": 25.0, "due_in": 1}],
		"orders": [{"kind": "input", "qty": 10, "allocated_qty": 20, "new_building_qty": 4, "amount": 50.0}]}
	var costs := Forecast.next_turn_costs(data)
	_check(is_equal_approx(float(costs.total), 35.0), "startup share survives finance clipping and includes only its unpaid arrival cost")
	_check(is_equal_approx(float(costs.order_rows[0].amount), 10.0), "detail rows reconcile with startup order subtotal")
	_check(is_equal_approx(float(costs.payments[0].amount), 25.0), "detail rows exclude the running factory's shared shipment bill")

func _test_startup_marker_only_tracks_real_restarts_and_survives_save() -> void:
	MatchState.reset()
	var iid := BuildingState.add_building("b_002", "r_007", "tile_5_10")
	BuildingWorks.set_building_paused(iid, false)
	_check(not bool(BuildingState.get_building(iid).get("startup_inputs_pending", false)), "already-online building is not marked by a no-op resume")
	BuildingWorks.set_building_paused(iid, true)
	BuildingWorks.set_building_paused(iid, false)
	_check(bool(BuildingState.get_building(iid).get("startup_inputs_pending", false)), "actual resume marks initial inputs pending")
	var saved := BuildingState.export_fields()
	BuildingState.import_fields(saved)
	_check(bool(BuildingState.get_building(iid).get("startup_inputs_pending", false)), "startup classification survives save/load")
	MatchState.reset()

func _test_startup_bill_only_warns_on_payment_turn() -> void:
	var expected := {"orders": [{"kind": "input", "qty": 40, "allocated_qty": 40, "new_building_qty": 40, "amount": 219.03, "payment_in": 2}]}
	_check(is_zero_approx(float(Forecast.next_turn_costs(expected).total)), "startup: no warning when ordering precedes payment by a turn")
	var booked := {"payments": [{"amount": 219.03, "extra_amount": 219.03, "due_in": 2}]}
	_check(is_zero_approx(float(Forecast.next_turn_costs(booked).total)), "startup: later transit bill is excluded")
	booked.payments[0].due_in = 1
	_check(is_equal_approx(float(Forecast.next_turn_costs(booked).total), 219.03), "startup: full unpaid bill appears just before payment")
	booked.payments[0].extra_amount = 0.0
	_check(is_zero_approx(float(Forecast.next_turn_costs(booked).total)), "startup: routine replenishment is excluded")
	expected.orders[0].payment_in = 1
	_check(is_equal_approx(float(Forecast.next_turn_costs(expected).total), 219.03), "startup: same-resolution purchases still warn before being charged")
	_check(Forecast.recommended_buffer(219.03) == 250, "buffer rounds upward to nearest fifty")
	_check(Forecast.recommended_buffer(250.0) == 250, "buffer keeps exact multiples")
	_check(Forecast.recommended_buffer(250.01) == 300, "buffer never rounds a bill downward")
	_check(Forecast.recommended_buffer(0.0) == 0, "zero bill needs no buffer")
