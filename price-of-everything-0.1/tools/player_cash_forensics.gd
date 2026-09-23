extends Node
## Conditional financial replay of supplied telemetry. Production net is observed input,
## NOT a regenerated economy. Actual loan, credit and decision services test the hypothesis.
const Paths := preload("res://scripts/app_paths.gd")
var out_path: String

func _enter_tree() -> void:
	out_path = OS.get_cmdline_user_args()[1]
	Paths._base = out_path.get_base_dir().path_join("runtime")
	RunMetrics.enabled = false
	TelemetryState.enabled = false

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	MatchState.reset()
	TurnManager.reset_for_test()
	DecisionState.enabled = false
	SolvencyState.enabled = false
	MatchState.money = 300.0
	var input := FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.READ)
	var rows: Array = []
	while not input.eof_reached():
		var line := input.get_line()
		if not line.strip_edges().is_empty():
			rows.append(line.split("\t"))
	var results: Array = []
	var broker_loan_id := -1
	var founder_loan_id := -1
	var max_cash_error := 0.0
	var max_debt_error := 0.0
	var variant := OS.get_cmdline_user_args()[2] if OS.get_cmdline_user_args().size() > 2 else "baseline"
	for columns: PackedStringArray in rows:
		var turn := int(columns[3])
		TurnManager.current_turn = turn
		TurnManager.current_phase = TurnManager.Phase.DECIDE
		var actions: Array = []
		if turn == 4:
			assert(AdvisorState.seat_founder("cfo"))
			assert(LoanState.take_founder_loan(200.0, 0.05))
			founder_loan_id = int(LoanState.loans.back().id)
			MatchState.add_money(-303.41)
			actions.append("Founder CFO +200; inferred unitemised desal/startup cash spending -303.41")
		if turn == 12:
			assert(LoanState.repay_loan(founder_loan_id))
			MatchState.add_money(-120.0)
			actions.append("Repay founder 200; inferred build/land spending 120")
		if turn == 13:
			var choice := DecisionState._find_choice(DecisionState.DECISION_DEFINITIONS.brokers_offer, "sign")
			DecisionState._execute_effects(choice.effects, {"scope": "company", "good_id": "g_004"})
			broker_loan_id = int(LoanState.loans.back().id)
			actions.append("Broker offer: pay 80, automatically financed because cash is zero; +10% iron sale modifier")
		if turn == 14:
			assert(MatchState.open_building_tab("forensic_combined_furnaces", "slices"))
		if turn == 18:
			MatchState.add_money(-240.0)
			actions.append("Inferred three rail build fees 210 plus three land patches 30")
		if turn == 19:
			MatchState.add_money(-70.0)
			actions.append("Inferred fourth rail build fee 70")
		if turn == 24:
			if variant not in ["keep_loan", "neither"]:
				assert(LoanState.repay_loan(broker_loan_id))
			var choice := DecisionState._find_choice(DecisionState.DECISION_DEFINITIONS.environmental_inspection, "pay_fine")
			if variant not in ["no_fine", "neither"]:
				DecisionState._execute_effects(choice.effects, {"scope": "building", "instance_id": "forensic_furnace"})
			actions.append("Turn 24 counterfactual variant: " + variant)
		var costs := 0.0
		for cost in columns[15].split("|"):
			costs += float(cost.split(":")[1])
		var observed_net := float(columns[6])
		var inferred_credit := snappedf(observed_net - (float(columns[5]) - costs), 0.01) if turn in [15, 16, 17, 18] else 0.0
		# Net already contains the cash benefit: accrue the liability without double crediting.
		if inferred_credit > 0.0:
			assert(is_equal_approx(MatchState.accrue_building_tab("forensic_combined_furnaces", inferred_credit), inferred_credit))
		var before_tabs := MatchState.money
		MatchState.tick_building_tabs()
		var tab_payment := before_tabs - MatchState.money
		var loan_before := LoanState.total_outstanding()
		var loan_payment := LoanState.process_payments()
		# Aggregate observed retained net substitutes for production/tax, not loan mechanics.
		MatchState.add_money(observed_net + loan_payment)
		var broker_pct := float(Modifiers.resolve_pct("market_price", "g_004", {}).get("net", 0.0))
		TurnManager.current_phase = TurnManager.Phase.NARRATIVE
		Modifiers._prune_expired()
		var cash_error := MatchState.money - float(columns[4])
		var debt_error := LoanState.total_outstanding() - float(columns[7])
		max_cash_error = maxf(max_cash_error, absf(cash_error))
		max_debt_error = maxf(max_debt_error, absf(debt_error))
		results.append({"turn": turn, "cash": MatchState.money, "observed_cash": float(columns[4]),
			"cash_error": cash_error, "debt": LoanState.total_outstanding(), "observed_debt": float(columns[7]),
			"debt_error": debt_error, "tab_payment": tab_payment, "credit_carried": inferred_credit,
			"tab_debt": MatchState.total_building_tab_debt(), "loan_payment": loan_payment,
			"loan_book_change_during_process": LoanState.total_outstanding() - loan_before,
			"loan_rate": LoanState.effective_loan_interest_rate(), "broker_bonus_during_production_pct": broker_pct,
			"actions": actions, "loans": LoanState.loans.duplicate(true)})
		# The pasted snapshot precedes the observed bridge disbursement. Test that boundary
		# explicitly, without claiming all clients have the same signal subscriber order.
		if MatchState.money < 0.0:
			TurnManager.current_turn = turn + 1
			var deficit := -MatchState.money
			assert(LoanState.take_distress_loan(deficit))
			actions.append("Post-snapshot bridge for deficit %.4f" % deficit)
	var copper_price := MarketState.get_price("g_005")
	var fingerprint := {"catalog_copper_sell_price": copper_price,
		"stop_selling_32_ingots_revenue_loss": 32.0 * copper_price,
		"stop_buying_13_ingots_input_saving": 13.0 * MarketState.get_buy_price("g_005"),
		"retained_ingots_per_turn": 32 - 13,
		"incremental_storage_fee_growth": 19.0 * EconomyConfig.warehousing_cost_per_unit("g_005"),
		"observed_revenue_loss_t21_t22": 328.73 - 229.31,
		"observed_input_saving_t21_t22": 53.14 - 10.62,
		"observed_storage_growth_t22_t23": 17.22 - 15.91,
		"earlier_storage_growth_t19_t20": 12.20 - 11.50}
	var result := {"variant": variant, "copper_routing_fingerprint": fingerprint,
		"scope": "Conditional finance replay; production net and initial unitemised spending are observed/calibrated inputs. No map, shipment, price or event RNG replay. Copper comparison uses current catalog prices, not recovered historical quotes.",
		"max_cash_error": max_cash_error, "max_debt_error": max_debt_error, "rows": results}
	var output := FileAccess.open(out_path, FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "\t"))
	output.close()
	print("FORENSICS_RESULT cash_error=%.5f debt_error=%.5f" % [max_cash_error, max_debt_error])
	get_tree().quit(0 if variant != "baseline" or (max_cash_error < 0.06 and max_debt_error < 0.06) else 1)
