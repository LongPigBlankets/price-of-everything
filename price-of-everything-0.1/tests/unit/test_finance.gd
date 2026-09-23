extends "res://tests/test_base.gd"
## Loans, tax, solvency, balance sheet and cost reports.

const FEATURE := "finance"
## Tests that also belong to other features (run under any of their tags).
const TAGS := {
	"_test_transaction_ledger": ["finance", "stockpile"],
	"_test_tax_dividend_caps": ["finance", "production"],
	"_test_tax_free_profit_floor": ["finance", "production"],
	"_test_cost_report_credits_output_modifiers": ["finance", "production", "research"],
	"_test_balance_sheet_reconciles_with_cash": ["finance", "production"],
}

func _test_transaction_ledger() -> void:
	Stockpile.add("tile_3_8", "g_001", 12)
	MatchState.queue_sell("tile_3_8", {"g_001": 12})  # one-off → logged
	var rows: Array = MatchState.get_oneoff_transaction_rows()
	_check(rows.size() > 0, "one-off sell appears in the transaction ledger")
	var last: Dictionary = rows[rows.size() - 1]
	_check(str(last.get("type", "")) == "Sell" and int(last.get("qty", 0)) == 12,
		"ledger row carries type=Sell and qty")
	TransportState.add_recurring_move("tile_3_8", "tile_3_9", {"g_001": 5})
	_check(TransportState.get_recurring_move_rows().size() > 0, "recurring move appears in the movements ledger")
	# A recurring execution must NOT also be logged as a one-off.
	var before: int = TransportState.get_oneoff_move_rows().size()
	MatchState.run_recurring_and_scheduled_moves()
	_check(TransportState.get_oneoff_move_rows().size() == before, "recurring executions are not double-logged as one-offs")
	# Production-driven sales/moves must show up too (the bulk of real activity).
	var t_before: int = MatchState.get_oneoff_transaction_rows().size()
	MatchState.log_market_sale("tile_6_8", "tile_5_10", "g_001", 20, 2)
	_check(MatchState.get_oneoff_transaction_rows().size() == t_before + 1,
		"a production market sale is logged to the transaction ledger")

func _test_tax_dividend_caps() -> void:
	MatchState.reset()
	MatchState.money = 1000.0
	var loss_summary := {
		"money_in": 235.0,
		"money_out": 239.0,
		"taxes_paid": 0.0,
		"dividends_paid": 0.0,
	}
	var money_before := MatchState.money
	var loss_pretax: float = Production._apply_tax_and_dividends(loss_summary)
	_check(loss_pretax < 0.0
		and float(loss_summary.get("taxes_paid", -1.0)) == 0.0
		and float(loss_summary.get("dividends_paid", -1.0)) == 0.0
		and is_equal_approx(MatchState.money, money_before),
		"loss-making turns do not pay tax or dividends")

	# Profit of 40 is assessed on 20 (40 − the 20 floor): tax 4.0, dividends 20% of the
	# remaining 16, retained 40 − 4 − 3.2 = 32.8.
	var profit_summary := {
		"money_in": 130.0,
		"money_out": 90.0,
		"taxes_paid": 0.0,
		"dividends_paid": 0.0,
	}
	Production._apply_tax_and_dividends(profit_summary)
	_check(is_equal_approx(float(profit_summary.get("taxes_paid", 0.0)), 4.0)
		and is_equal_approx(float(profit_summary.get("dividends_paid", 0.0)), 3.2)
		and is_equal_approx(float(profit_summary.get("money_in", 0.0)) - float(profit_summary.get("money_out", 0.0)), 32.8),
		"tax is capped to profit and dividends are calculated after tax")

	var profit_share_summary := {
		"money_in": 130.0,
		"money_out": 90.0,
		"taxes_paid": 0.0,
		"dividends_paid": 0.0,
		"profit_sharing_paid": 0.0,
	}
	LabourState.set_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_ANNUAL_PROFIT_SHARE, true)
	var share_pretax: float = Production._apply_tax_and_dividends(profit_share_summary)
	Production._apply_profit_sharing(profit_share_summary, share_pretax)
	_check(is_equal_approx(float(profit_share_summary.get("profit_sharing_paid", 0.0)), 1.64)
		and is_equal_approx(float(profit_share_summary.get("money_in", 0.0)) - float(profit_share_summary.get("money_out", 0.0)), 31.16),
		"profit sharing is paid from post-tax, post-dividend profit")
	LabourState.set_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_ANNUAL_PROFIT_SHARE, false)

func _test_tax_free_profit_floor() -> void:
	# The first TAX_FREE_PROFIT_FLOOR of each turn's profit is assessed at nothing, for
	# tax AND dividends. See docs/early-game-onboarding-spec.md §4.3.
	MatchState.reset()
	MatchState.money = 1000.0
	var floor_value: float = EconomyConfig.TAX_FREE_PROFIT_FLOOR

	# Profit strictly inside the floor: nothing is taken at all.
	var inside := {
		"money_in": floor_value - 5.0, "money_out": 0.0,
		"taxes_paid": 0.0, "dividends_paid": 0.0,
	}
	var money_before := MatchState.money
	Production._apply_tax_and_dividends(inside)
	_check(is_equal_approx(float(inside.get("taxes_paid", -1.0)), 0.0)
		and is_equal_approx(float(inside.get("dividends_paid", -1.0)), 0.0)
		and is_equal_approx(MatchState.money, money_before),
		"profit inside the tax-free floor pays neither tax nor dividends")

	# Exactly at the floor: still nothing (the floor is inclusive).
	var at_floor := {
		"money_in": floor_value, "money_out": 0.0,
		"taxes_paid": 0.0, "dividends_paid": 0.0,
	}
	Production._apply_tax_and_dividends(at_floor)
	_check(is_equal_approx(float(at_floor.get("taxes_paid", -1.0)), 0.0)
		and is_equal_approx(float(at_floor.get("dividends_paid", -1.0)), 0.0),
		"profit exactly at the tax-free floor pays nothing")

	# Above the floor: only the excess is assessed, so the relief is marginal, not a cliff.
	var above := {
		"money_in": floor_value + 100.0, "money_out": 0.0,
		"taxes_paid": 0.0, "dividends_paid": 0.0,
	}
	Production._apply_tax_and_dividends(above)
	var expected_tax: float = 100.0 * EconomyConfig.TAX_RATE
	var expected_div: float = (100.0 - expected_tax) * EconomyConfig.DIVIDEND_RATE
	_check(is_equal_approx(float(above.get("taxes_paid", 0.0)), expected_tax)
		and is_equal_approx(float(above.get("dividends_paid", 0.0)), expected_div),
		"above the floor only the excess profit is assessed (tax %.2f, dividends %.2f)"
			% [expected_tax, expected_div])

func _test_owner_costs() -> void:
	_check(BuildingState.is_player_owned({"owner": "player_1"}), "player_1 building is player-owned")
	_check(BuildingState.is_player_owned({}), "building with no owner defaults to player-owned")
	_check(not BuildingState.is_player_owned({"owner": "Three Diamonds Shipping Corporation"}),
		"NPC-owned building is not player-owned (not charged maintenance)")

func _test_cost_report_credits_output_modifiers() -> void:
	# A recipe_output modifier (the "Δ +%" on a recipe) must be credited in the cost report's
	# output quantity — not just the level multiplier — or CostSolver divides the run's fixed
	# costs by too few units and overstates unit cost for every modified building.
	Modifiers.reset()
	MatchState.reset()
	var recipe: Dictionary = Catalog.get_recipe("r_008")  # Copper Wire Drawing (single output)
	var base_out := 0
	for o in recipe.get("outputs", []):
		base_out += int(o.get("qty", 0))
	var base_in := 0
	for inp in recipe.get("inputs", []):
		base_in += int(inp.get("qty", 0))
	Modifiers.add({"id": "test_cw_output_boost", "domain": "recipe_output",
		"target_match": {"building_id": "b_007"}, "pct": 50.0, "label": "test", "source": "test"})
	Production._building_turn_reports.clear()
	Production._capture_turn_report({"instance_id": "rt_cw", "building_id": "b_007", "tile_id": "tT", "level": 1}, recipe)
	var rep: Dictionary = Production._building_turn_reports[-1]
	var rep_out := 0
	for gid in (rep.get("outputs_produced", {}) as Dictionary):
		rep_out += int(rep["outputs_produced"][gid])
	var rep_in := 0
	for gid in (rep.get("inputs_consumed", {}) as Dictionary):
		rep_in += int(rep["inputs_consumed"][gid])
	_check(base_out > 0 and rep_out == int(round(float(base_out) * 1.5)),
		"cost report credits a +50%% recipe_output modifier in output qty (was: base only)")
	_check(base_in > 0 and rep_in == base_in,
		"cost report leaves inputs at base under a recipe_output modifier")
	Production._building_turn_reports.clear()
	Modifiers.reset()
	MatchState.reset()

func _test_loan_collateral_capacity() -> void:
	# A loss-making firm with plant keeps a credit line: capacity = base + LTV x
	# building SALE value, even while the profit gate zeroes the cashflow leg. A
	# seated CFO/Chief Investment lifts the LTV from 0.75 to 1.0.
	var BP = load("res://scripts/building_price.gd")
	var profit_before: Array = LoanState._profit_history.duplicate()
	var revenue_before: Array = LoanState._revenue_history.duplicate()
	var seats_before: Dictionary = AdvisorState.advisor_seats.duplicate(true)
	AdvisorState.advisor_seats = {}                       # no CFO / Chief Investment → base LTV
	LoanState._profit_history = [-10.0, -12.0, -8.0]
	LoanState._revenue_history = [20.0, 20.0, 20.0]
	var without_plant := LoanState.capacity_total()
	var b := {"instance_id": "test_collateral_b1", "building_id": "b_001",
		"recipe_id": "", "tile_id": "tile_1_1", "owner": MatchState.LOCAL_PLAYER, "level": 1}
	var sale := float(BP.sale_price(b))
	BuildingState.buildings["test_collateral_b1"] = b
	var with_plant := LoanState.capacity_total()
	_check(sale > 0.0 and absf((with_plant - without_plant) - EconomyConfig.LOAN_COLLATERAL_LTV_BASE * sale) < 0.5,
		"loan collateral: plant adds base-LTV (0.75) x its sale value while unprofitable")
	AdvisorState.advisor_seats = {"cfo": "vera"}          # a seated CFO lifts LTV to 1.0
	var with_cfo := LoanState.capacity_total()
	_check(absf((with_cfo - without_plant) - EconomyConfig.LOAN_COLLATERAL_LTV_MAX * sale) < 0.5,
		"loan collateral: a seated CFO/Chief Investment lifts LTV to the max (1.0)")
	BuildingState.buildings.erase("test_collateral_b1")
	_check(without_plant >= EconomyConfig.LOAN_BASE_CAPACITY,
		"loan collateral: the base floor still holds with no plant")
	AdvisorState.advisor_seats = seats_before
	LoanState._profit_history = profit_before
	LoanState._revenue_history = revenue_before

func _test_loan_minimum_and_grace() -> void:
	LoanState.loans.clear()
	MatchState.money = 100000.0
	# MINIMUM: the auto-bridge used to borrow the exact shortfall, so a £1.36 gap became a
	# £1.36 loan on a 36-turn book — 18 of them by turn 57 in a player log, each carrying its
	# own interest forever. Anything smaller than the floor is written AT the floor.
	_check(LoanState.take_loan(1.36), "tiny loan request is accepted")
	var l: Dictionary = LoanState.loans[0]
	_check(absf(float(l.principal_initial) - EconomyConfig.LOAN_MINIMUM) < 0.001,
		"loan minimum: a £1.36 request is written as £%.0f" % EconomyConfig.LOAN_MINIMUM)
	# GRACE: nothing due for LOAN_GRACE_TURNS, and the loan runs grace + term in total.
	_check(absf(float(l.payment_per_turn)) < 0.001, "grace: no payment due on the turn it is taken")
	_check(int(l.turns_remaining) == EconomyConfig.LOAN_GRACE_TURNS + EconomyConfig.LOAN_TERM_TURNS,
		"grace: loan runs %d turns in total" % (EconomyConfig.LOAN_GRACE_TURNS + EconomyConfig.LOAN_TERM_TURNS))
	# Interest ACCRUES across the grace: forbearance, not a discount. A 12+36 loan at 10%
	# repays 1 + 0.10 x 48/36 = 1.1333x, against 1.10x with no grace at all.
	var expected := float(l.principal_initial) * (1.0 + EconomyConfig.LOAN_INTEREST_RATE
		* float(EconomyConfig.LOAN_GRACE_TURNS + EconomyConfig.LOAN_TERM_TURNS)
		/ float(EconomyConfig.LOAN_TERM_TURNS))
	_check(absf(float(l.get("total_repayment", 0.0)) - expected) < 0.01,
		"grace accrues interest: total is %.2fx principal, not %.2fx"
			% [expected / float(l.principal_initial), 1.0 + EconomyConfig.LOAN_INTEREST_RATE])
	var before := MatchState.money
	for _i in EconomyConfig.LOAN_GRACE_TURNS:
		LoanState.process_payments()
	_check(absf(MatchState.money - before) < 0.001, "grace: nothing is paid across the whole grace")
	_check(int(LoanState.loans[0].grace_remaining) == 0, "grace: expired after %d turns" % EconomyConfig.LOAN_GRACE_TURNS)
	_check(float(LoanState.loans[0].payment_per_turn) > 0.0, "grace: payments begin once it expires")
	LoanState.process_payments()
	_check(MatchState.money < before, "grace: money leaves the account on the first paying turn")
	LoanState.loans.clear()


func _test_liquidate_all_buildings() -> void:
	var money_before := MatchState.money
	var BP = load("res://scripts/building_price.gd")
	var b1 := {"instance_id": "test_liq_1", "building_id": "b_001", "recipe_id": "",
		"tile_id": "tile_1_1", "owner": MatchState.LOCAL_PLAYER, "level": 1}
	var b2 := {"instance_id": "test_liq_2", "building_id": "b_001", "recipe_id": "",
		"tile_id": "tile_1_2", "owner": MatchState.LOCAL_PLAYER, "level": 1}
	BuildingState.buildings["test_liq_1"] = b1
	BuildingState.buildings["test_liq_2"] = b2
	var expected := int(round(float(BP.sale_price(b1)) * 1.5)) + int(round(float(BP.sale_price(b2)) * 1.5))
	var res: Dictionary = BuildingState.liquidate_all_buildings(1.5)
	_check(int(res.count) >= 2, "liquidate: sells every player building (>=2 here)")
	_check(not BuildingState.is_player_owned(BuildingState.buildings["test_liq_1"])
		and not BuildingState.is_player_owned(BuildingState.buildings["test_liq_2"]),
		"liquidate: liquidated buildings flip to the NPC operator")
	_check(MatchState.money >= money_before + float(expected) - 1.0,
		"liquidate: player is paid 1.5x sale value for the buildings")
	BuildingState.buildings.erase("test_liq_1")
	BuildingState.buildings.erase("test_liq_2")
	MatchState.money = money_before

func _test_grace_loan() -> void:
	var loans_before: Array = LoanState.loans.duplicate(true)
	var money_before := MatchState.money
	LoanState.loans = []
	LoanState.take_grace_loan(500.0, 10)
	var loan: Dictionary = LoanState.loans.back()
	_check(absf(float(loan.principal_initial) - 500.0) < 0.001, "grace loan: £500 principal booked")
	_check(int(loan.grace_remaining) == 10 and absf(float(loan.payment_per_turn)) < 0.001,
		"grace loan: 10 interest-free turns, no payment scheduled")
	var money_after_disburse := MatchState.money
	_check(money_after_disburse >= money_before + 499.0, "grace loan: principal disbursed to the player")
	for _i in 10:
		LoanState.process_payments()
	var loan2: Dictionary = LoanState.loans.back()
	_check(absf(MatchState.money - money_after_disburse) < 0.001, "grace loan: no cash paid across the 10 grace turns")
	_check(int(loan2.grace_remaining) == 0 and float(loan2.payment_per_turn) > 0.0,
		"grace loan: converts to amortised payments once grace ends")
	_check(absf(float(loan2.principal_remaining) - 500.0 * (1.0 + float(loan2.interest_rate))) < 1.0,
		"grace loan: post-grace balance = principal x (1 + rate)")
	LoanState.loans = loans_before
	MatchState.money = money_before

func _test_distressed_program() -> void:
	var money_before := MatchState.money
	var loans_before: Array = LoanState.loans.duplicate(true)
	SolvencyState.reset()
	BuildingState.buildings["test_dist_1"] = {"instance_id": "test_dist_1", "building_id": "b_001",
		"recipe_id": "", "tile_id": "tile_1_1", "owner": MatchState.LOCAL_PLAYER, "level": 1}
	var loans_n := LoanState.loans.size()
	var res: Dictionary = SolvencyState.accept_distressed_program()
	_check(int(res.count) >= 1, "distressed: the program liquidates the player's buildings")
	_check(not BuildingState.is_player_owned(BuildingState.buildings["test_dist_1"]),
		"distressed: buildings are bought out")
	_check(LoanState.loans.size() == loans_n + 1, "distressed: a £500 grace loan lands")
	_check(int(LoanState.loans.back().grace_remaining) == SolvencyState.DISTRESSED_GRACE_TURNS,
		"distressed: the rescue loan is interest-free for the grace period")
	BuildingState.buildings.erase("test_dist_1")
	LoanState.loans = loans_before
	MatchState.money = money_before
	SolvencyState.reset()

func _test_solvency_bankruptcy() -> void:
	var ge_before := TurnManager.game_ended
	var seats_before: Dictionary = AdvisorState.advisor_seats.duplicate(true)
	SolvencyState.reset()
	AdvisorState.advisor_seats = {}                         # no CFO → no distressed offer, straight path
	for _i in 4:
		SolvencyState._evaluate(-600.0, -10.0)            # at/below floor, unprofitable
	_check(not SolvencyState.is_bankrupt(), "solvency: 4 floor+loss turns is not yet bankruptcy")
	SolvencyState._evaluate(-600.0, 5.0)                  # a profitable turn resets the clock
	_check(not SolvencyState.is_bankrupt(), "solvency: a profitable turn resets the bankruptcy clock")
	for _i in 5:
		SolvencyState._evaluate(-600.0, -10.0)
	_check(SolvencyState.is_bankrupt(), "solvency: 5 consecutive floor+loss turns → bankruptcy")
	_check(TurnManager.game_ended, "solvency: bankruptcy ends the game")
	SolvencyState.reset()
	TurnManager.game_ended = ge_before
	AdvisorState.advisor_seats = seats_before


func _test_balance_sheet_reconciles_with_cash() -> void:
	var MoneyPanel := preload("res://scripts/money_panel.gd")
	# 1. A REAL committed turn with a salaried advisor — the case that was live and wrong.
	var seats_before: Dictionary = AdvisorState.advisor_seats.duplicate(true)
	var recruited_before: Array = AdvisorState.recruited_advisor_ids.duplicate()
	var permanent_before: Array = AdvisorState.permanent_advisor_ids.duplicate()
	var loyalty_before: Dictionary = AdvisorState.advisor_loyalty.duplicate(true)
	var hired_turn_before: Dictionary = AdvisorState.advisor_hired_turn.duplicate(true)
	AdvisorState.recruited_advisor_ids = ["vera", "tom", "rufus"]
	AdvisorState.hire_advisor("vera")
	AdvisorState.assign_advisor_to_seat("cfo", "vera")
	_check(AdvisorState.advisor_payroll_per_turn(100.0) > 0.0,
		"reconcile: the seated advisor is actually on a salary (else the test proves nothing)")
	TurnManager.commit_turn()
	var s: Dictionary = Production.last_turn_summary
	var cash_delta: float = float(s.get("money_in", 0.0)) - float(s.get("money_out", 0.0))
	_check(float(s.get("advisor_paid", 0.0)) > 0.0, "reconcile: the turn charged advisor payroll")
	_check(absf(MoneyPanel.net_cash_of(s) - cash_delta) < 0.01,
		"reconcile: balance-sheet net == money_in - money_out on a real turn (%.2f vs %.2f)"
			% [MoneyPanel.net_cash_of(s), cash_delta])
	# The resolution yields a frame per phase; finish it before handing state back.
	await _await_turn_settled()
	AdvisorState.advisor_seats = seats_before
	AdvisorState.recruited_advisor_ids = recruited_before
	AdvisorState.permanent_advisor_ids = permanent_before
	AdvisorState.advisor_loyalty = loyalty_before
	AdvisorState.advisor_hired_turn = hired_turn_before

	# 2. The two keys the sheet used to drop must each move the bottom line by exactly their
	# amount — a new cash movement wired into production.gd but not into the sheet fails here.
	var base := {"goods_sales_revenue": 500.0, "labour_paid": 80.0, "transport_paid": 120.0}
	var with_advisor: Dictionary = base.duplicate()
	with_advisor["advisor_paid"] = 25.0
	_check(absf(MoneyPanel.net_cash_of(with_advisor) - (MoneyPanel.net_cash_of(base) - 25.0)) < 0.001,
		"reconcile: advisor salaries come off the net, pound for pound")
	var with_tab: Dictionary = base.duplicate()
	with_tab["building_tab_carried"] = 40.0
	_check(absf(MoneyPanel.net_cash_of(with_tab) - (MoneyPanel.net_cash_of(base) + 40.0)) < 0.001,
		"reconcile: costs carried onto a building tab are credited back, pound for pound")


func _test_auto_bridge_loan() -> void:
	# Negative cash auto-borrows up to available capacity to reach £0; capped when the
	# gap exceeds capacity (then the balance stays red and bankruptcy looms).
	var money_before := MatchState.money
	var loans_before: Array = LoanState.loans.duplicate(true)
	var profit_before: Array = LoanState._profit_history.duplicate()
	LoanState.loans = []
	LoanState._profit_history = []
	MatchState.money = 50.0
	_check(SolvencyState.auto_bridge_amount() == 0.0, "auto-bridge: solvent → borrows nothing")
	MatchState.money = -30.0
	_check(absf(SolvencyState.auto_bridge_amount() - minf(30.0, LoanState.available_capacity())) < 0.001,
		"auto-bridge: borrows the gap when capacity allows")
	MatchState.money = -1000000.0
	_check(absf(SolvencyState.auto_bridge_amount() - LoanState.available_capacity()) < 0.001,
		"auto-bridge: capped at available capacity when the gap is huge")
	# Applying it takes a loan and lifts the balance back toward £0.
	LoanState.loans = []
	MatchState.money = -30.0
	var n := LoanState.loans.size()
	SolvencyState._auto_bridge_negative_cash()
	_check(LoanState.loans.size() == n + 1, "auto-bridge: takes a loan when in the red")
	_check(MatchState.money >= -0.001, "auto-bridge: lifts the balance to ~£0 when capacity covers it")
	LoanState.loans = loans_before
	LoanState._profit_history = profit_before
	MatchState.money = money_before
