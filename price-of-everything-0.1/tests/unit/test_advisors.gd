extends "res://tests/test_base.gd"
## Advisor seats, loyalty, missions, payroll and the people panel.

const FEATURE := "advisors"
## Tests that also belong to other features (run under any of their tags).
const TAGS := {
	"_test_advisor_payroll_cost": ["advisors", "production"],
	"_test_advisor_payroll_model": ["advisors", "production"],
	"_test_advisor_reconcile_idempotent": ["advisors", "research"],
	"_test_advisor_seat_effects": ["advisors", "research"],
	"_test_advisor_phase2_effects": ["advisors", "construction", "finance", "market", "research"],
	"_test_advisor_missions": ["advisors", "research"],
	"_test_advisor_mission_update_signals": ["advisors", "research"],
	"_test_founder_advisor": ["advisors", "transport"],
}

func _test_advisor_payroll_cost() -> void:
	var saved_ids := AdvisorState.permanent_advisor_ids.duplicate(true)
	var saved_money := MatchState.money
	# The per-advisor `salary` field is gone (owner 2026-08-01): every advisor now costs the same
	# inflating base plus 1% of revenue each. This test used to assert 1.0 + 4.0 = 5.0 from the
	# roster fields; it now asserts the live model, and that the charge is billed against THIS
	# turn's revenue out of the summary rather than last turn's.
	var saved_turn: int = TurnManager.current_turn
	TurnManager.current_turn = 1
	AdvisorState.permanent_advisor_ids = ["vera", "alexandra"]
	MatchState.money = 1000.0
	var summary := {"advisor_paid": 0.0, "money_out": 0.0,
		"goods_sales_revenue": 800.0, "power_sales_revenue": 200.0}
	var expect: float = 2.0 * (EconomyConfig.ADVISOR_BASE_COST_PER_TURN + 1000.0 * EconomyConfig.ADVISOR_REVENUE_SHARE)
	var paid: float = Production._apply_advisor_costs(summary)
	_check(is_equal_approx(paid, expect)
		and is_equal_approx(float(summary.get("advisor_paid", 0.0)), expect)
		and is_equal_approx(float(summary.get("money_out", 0.0)), expect)
		and is_equal_approx(MatchState.money, 1000.0 - expect),
		"advisor payroll = per-advisor (base + 1%% of this turn's revenue) — £%.1f for two" % expect)
	TurnManager.current_turn = saved_turn
	AdvisorState.permanent_advisor_ids = saved_ids
	MatchState.money = saved_money
	MatchState.money_changed.emit(MatchState.money)
	AdvisorState.advisors_changed.emit()

func _test_advisor_roster_merge() -> void:
	var defs: Array = AdvisorState._advisor_definitions()
	_check(defs.size() == 13, "roster merge: _advisor_definitions() has 13 advisors")
	var required := ["id", "name", "role", "happiness", "portrait_color", "bonus", "recommendation", "bio", "agenda", "likes", "dislikes", "bonuses", "missions"]
	var all_ok := true
	for d in defs:
		for key in required:
			if not (d as Dictionary).has(key):
				all_ok = false
	_check(all_ok, "roster merge: every display advisor carries the required panel fields")
	_check(str(AdvisorState.get_advisor("vera").get("name", "")) == "Vera Ashby", "roster merge: get_advisor resolves a canonical id")
	_check(AdvisorState.get_advisor("natasha").is_empty(), "roster merge: legacy ids are retired")

func _test_advisor_seat_requires_hire() -> void:
	var saved_seats: Dictionary = AdvisorState.advisor_seats.duplicate(true)
	var saved_hired: Array = AdvisorState.permanent_advisor_ids.duplicate(true)
	var saved_rec: Array = AdvisorState.recruited_advisor_ids.duplicate(true)
	var saved_fired: Dictionary = AdvisorState.fired_advisor_cooldowns.duplicate(true)
	var saved_slots: int = AdvisorState.max_advisor_slots
	AdvisorState.advisor_seats = {}
	AdvisorState.permanent_advisor_ids = []
	AdvisorState.recruited_advisor_ids = ["vera"]
	AdvisorState.fired_advisor_cooldowns = {}
	AdvisorState.max_advisor_slots = 2
	_check(not AdvisorState.assign_advisor_to_seat("cfo", "vera"), "hire gate: cannot seat an un-hired advisor")
	AdvisorState.hire_advisor("vera")
	_check(AdvisorState.assign_advisor_to_seat("cfo", "vera"), "hire gate: can seat once hired")
	AdvisorState.advisor_seats = saved_seats
	AdvisorState.permanent_advisor_ids = saved_hired
	AdvisorState.recruited_advisor_ids = saved_rec
	AdvisorState.fired_advisor_cooldowns = saved_fired
	AdvisorState.max_advisor_slots = saved_slots

func _test_people_panel_seat_ui() -> void:
	var saved_hired: Array = AdvisorState.permanent_advisor_ids.duplicate(true)
	var saved_seats: Dictionary = AdvisorState.advisor_seats.duplicate(true)
	AdvisorState.permanent_advisor_ids = ["vera"]
	AdvisorState.advisor_seats = {}
	var pp: Node = load("res://scripts/people_panel.gd").new()
	add_child(pp)
	var vera: Dictionary = AdvisorState.get_advisor("vera")
	var section: Control = pp.call("_seat_assignment_section", vera)
	_check(section != null and str(section.name) == "SeatAssignmentSection",
		"seat UI: seat-assignment section builds for a hired advisor")
	var pent: Control = pp.call("_stat_pentagon", AdvisorState.get_advisor("vera"))
	_check(pent != null and str(pent.name) == "StatPentagon",
		"seat UI: stat pentagon builds")
	pp.call("_on_discipline_label", "fin", "vera")
	_check(pp.get("_shown_discipline") == "fin",
		"seat UI: tapping a discipline label opens its info section")
	pp.queue_free()
	AdvisorState.permanent_advisor_ids = saved_hired
	AdvisorState.advisor_seats = saved_seats

func _test_advisor_star_derivation() -> void:
	var expected := {"vera": 5, "alexandra": 5, "gerald": 4, "eleanor": 4, "sloane": 3, "priya": 3, "hitomi": 3, "hal": 3, "tom": 2, "marcus": 2, "idris": 2, "rufus": 1}
	for aid in expected:
		_check(AdvisorState.advisor_star_by_id(str(aid)) == int(expected[aid]),
			"advisor star: %s -> %d" % [str(aid), int(expected[aid])])
	# precedence edges (spec §2.2)
	_check(AdvisorState.advisor_star({"inf": 3, "ops": 3, "lead": 3, "inn": 3, "fin": 1}) == 5,
		"advisor star: four 3s -> 5 (beats the score band)")
	_check(AdvisorState.advisor_star({"inf": 3, "ops": 3, "lead": 3, "inn": 2, "fin": 1}) == 4,
		"advisor star: score 12 with three 3s -> 4")
	_check(AdvisorState.advisor_star({"inf": 1, "ops": 1, "lead": 1, "inn": 1, "fin": 1}) == 1,
		"advisor star: all 1s -> 1 (floor)")

func _test_advisor_seat_assign_and_slot_cap() -> void:
	var saved_seats: Dictionary = AdvisorState.advisor_seats.duplicate(true)
	var saved_slots: int = AdvisorState.max_advisor_slots
	var saved_hired: Array = AdvisorState.permanent_advisor_ids.duplicate(true)
	var saved_unlocked: bool = AdvisorState.all_seats_unlocked
	AdvisorState.all_seats_unlocked = true   # slot-cap mechanics, not the CFO/COO gate
	AdvisorState.permanent_advisor_ids = ["vera", "tom", "marcus", "eleanor"]
	AdvisorState.advisor_seats = {}
	AdvisorState.max_advisor_slots = 2
	_check(AdvisorState.assign_advisor_to_seat("cfo", "vera"), "seat: assign vera -> cfo")
	_check(AdvisorState.assign_advisor_to_seat("coo", "tom"), "seat: assign tom -> coo")
	_check(not AdvisorState.assign_advisor_to_seat("hr_director", "eleanor"), "seat: third assign blocked by slot cap (2)")
	_check(not AdvisorState.assign_advisor_to_seat("cfo", "not_an_advisor"), "seat: unknown advisor rejected")
	_check(not AdvisorState.assign_advisor_to_seat("bogus_seat", "vera"), "seat: unknown seat rejected")
	_check(AdvisorState.get_advisor_in_seat("cfo") == "vera", "seat: cfo holds vera")
	# re-assigning within an already-occupied seat consumes no new slot
	_check(AdvisorState.assign_advisor_to_seat("cfo", "marcus"), "seat: re-assign within cfo (no new slot)")
	_check(AdvisorState.get_advisor_in_seat("cfo") == "marcus", "seat: cfo now holds marcus")
	# MOVING a seated advisor to an empty seat consumes no new slot — their old seat is vacated,
	# so the count does not grow and a FULL council must not refuse the move. This is the bug
	# behind "I hired them for one role and they went to another": the assign was refused, the
	# panel returned to the roster without a word, and the advisor stayed where they were.
	# Council is full here (2 seats, 2 slots) and the move must still succeed.
	_check(AdvisorState.advisor_seats.size() == AdvisorState.max_advisor_slots,
		"seat: council is full before the move (%d/%d)" % [AdvisorState.advisor_seats.size(), AdvisorState.max_advisor_slots])
	_check(AdvisorState.assign_advisor_to_seat("hr_director", "tom"),
		"seat: a seated advisor can move to an empty seat with the council full")
	_check(AdvisorState.get_advisor_in_seat("hr_director") == "tom", "seat: tom landed in the seat asked for")
	_check(AdvisorState.get_advisor_in_seat("coo") == "", "seat: one seat per advisor (coo vacated)")
	# ...and a genuinely NEW arrival is still refused at the cap.
	_check(not AdvisorState.assign_advisor_to_seat("coo", "eleanor"),
		"seat: a new arrival is still blocked when the council is full")
	AdvisorState.max_advisor_slots = 3
	_check(AdvisorState.assign_advisor_to_seat("coo", "eleanor"), "seat: the same arrival fits once a slot opens")
	_check(AdvisorState.unassign_seat("cfo"), "seat: unassign frees the seat")
	_check(AdvisorState.get_advisor_in_seat("cfo") == "", "seat: cfo empty after unassign")
	AdvisorState.advisor_seats = saved_seats
	AdvisorState.max_advisor_slots = saved_slots
	AdvisorState.permanent_advisor_ids = saved_hired
	AdvisorState.all_seats_unlocked = saved_unlocked

func _test_advisor_payroll_model() -> void:
	# Owner spec 2026-08-01: each advisor costs a flat base per turn that inflates at DOUBLE the
	# labour rate, plus 1% of company revenue — charged once per advisor, so a five-strong
	# council takes 5% of turnover.
	var saved_hired: Array = AdvisorState.permanent_advisor_ids.duplicate(true)
	var saved_turn: int = TurnManager.current_turn
	var saved_sum: Dictionary = Production.last_turn_summary.duplicate(true)
	TurnManager.current_turn = 1
	Production.last_turn_summary = {"goods_sales_revenue": 0.0, "power_sales_revenue": 0.0}
	AdvisorState.permanent_advisor_ids = []
	_check(is_equal_approx(AdvisorState.advisor_cost_per_advisor(0.0), EconomyConfig.ADVISOR_BASE_COST_PER_TURN),
		"advisor cost: turn 1 base is £%.1f" % EconomyConfig.ADVISOR_BASE_COST_PER_TURN)
	_check(is_equal_approx(EconomyConfig.ADVISOR_COST_GROWTH, 2.0 * EconomyConfig.LABOUR_HIGH_SKILLED_GROWTH),
		"advisor cost: growth is exactly double high-skilled labour")
	# 1% of revenue, per advisor.
	_check(is_equal_approx(AdvisorState.advisor_cost_per_advisor(1000.0),
			EconomyConfig.ADVISOR_BASE_COST_PER_TURN + 10.0),
		"advisor cost: +1% of £1000 revenue = +£10 each")
	AdvisorState.permanent_advisor_ids = ["vera", "tom", "marcus"]
	_check(is_equal_approx(AdvisorState.advisor_payroll_per_turn(1000.0),
			3.0 * (EconomyConfig.ADVISOR_BASE_COST_PER_TURN + 10.0)),
		"advisor cost: payroll is per-advisor, not per-council")
	# The base compounds with the turn number.
	TurnManager.current_turn = 101
	var t101: float = AdvisorState.advisor_cost_per_advisor(0.0)
	_check(t101 > EconomyConfig.ADVISOR_BASE_COST_PER_TURN,
		"advisor cost: the base inflates over a long game (£%.2f at t101)" % t101)
	_check(is_equal_approx(t101, EconomyConfig.ADVISOR_BASE_COST_PER_TURN
			* pow(1.0 + EconomyConfig.ADVISOR_COST_GROWTH, 100.0)),
		"advisor cost: compounds as base * (1+growth)^(t-1)")
	AdvisorState.permanent_advisor_ids = saved_hired
	TurnManager.current_turn = saved_turn
	Production.last_turn_summary = saved_sum


func _test_advisor_seat_tier_scaling() -> void:
	# rigid seats read the governing stat directly
	_check(AdvisorState.advisor_seat_tier("vera", "cfo") == 3, "tier: vera fin 3 -> cfo tier 3")
	_check(AdvisorState.advisor_seat_tier("rufus", "cfo") == 1, "tier: rufus fin 1 -> cfo tier 1 (malus)")
	_check(AdvisorState.advisor_seat_tier("tom", "coo") == 3, "tier: tom ops 3 -> coo tier 3")
	# flexible seats read the best of eligible disciplines
	_check(AdvisorState.advisor_seat_tier("marcus", "chief_investment") == 3, "tier: marcus max(fin 3, inn 1) -> 3")
	_check(AdvisorState.advisor_seat_tier("idris", "chief_investment") == 3, "tier: idris max(fin 1, inn 3) -> 3")
	_check(AdvisorState.advisor_seat_tier("rufus", "chief_markets") == 3, "tier: rufus max(inf 3, fin 1) -> 3")
	_check(AdvisorState.advisor_seat_tier("hitomi", "sustainability") == 3, "tier: hitomi max(inf 1, ops 3, lead 1) -> 3")
	_check(AdvisorState.advisor_seat_governing_discipline("idris", "chief_investment") == "inn", "tier: flexible governing discipline reported (inn)")
	_check(AdvisorState.advisor_seat_tier("vera", "bogus_seat") == 0, "tier: unknown seat -> 0")

func _test_advisor_reconcile_idempotent() -> void:
	Modifiers.reset()
	var saved_seats: Dictionary = AdvisorState.advisor_seats.duplicate(true)
	AdvisorState.advisor_seats = {"coo": "tom", "hr_director": "eleanor"}
	# an unrelated modifier that must survive reconcile
	Modifiers.add({"id": "unrelated_test_mod", "domain": "recipe_output", "pct": 5.0})
	AdvisorState.reconcile_advisor_modifiers()
	var count1: int = Modifiers.active_count()
	AdvisorState.reconcile_advisor_modifiers()   # second run must not duplicate
	_check(Modifiers.active_count() == count1, "reconcile: idempotent (no duplicate modifiers on re-run)")
	_check(Modifiers.has("advisor_seat_coo_labour_headcount") and Modifiers.has("advisor_seat_hr_director_labour_headcount"),
		"reconcile: emits per-domain effect modifiers per occupied seat")
	_check(Modifiers.has("unrelated_test_mod"), "reconcile: leaves non-advisor modifiers untouched")
	AdvisorState.advisor_seats = {"coo": "tom"}
	AdvisorState.reconcile_advisor_modifiers()
	_check(not Modifiers.has("advisor_seat_hr_director_labour_headcount"), "reconcile: drops modifiers for vacated seats")
	AdvisorState.advisor_seats = saved_seats
	Modifiers.reset()

func _test_advisor_seat_effects() -> void:
	Modifiers.reset()
	var saved_seats: Dictionary = AdvisorState.advisor_seats.duplicate(true)
	# Tom (ops 3) in COO -> tier 3 -> full reductions
	AdvisorState.advisor_seats = {"coo": "tom"}
	AdvisorState.reconcile_advisor_modifiers()
	_check(is_equal_approx(float(Modifiers.resolve_pct("labour_headcount", "b_001", {"building_id": "b_001"}).get("net", 0.0)), -10.0),
		"effects: COO tier 3 -> labour_headcount -10%")
	_check(is_equal_approx(float(Modifiers.resolve_pct("maintenance", "b_001", {"building_id": "b_001"}).get("net", 0.0)), -10.0),
		"effects: COO tier 3 -> maintenance -10%")
	# COO + HR (Eleanor lead 3) -> dual-source labour stacks additively to -20%
	AdvisorState.advisor_seats = {"coo": "tom", "hr_director": "eleanor"}
	AdvisorState.reconcile_advisor_modifiers()
	_check(is_equal_approx(float(Modifiers.resolve_pct("labour_headcount", "b_001", {"building_id": "b_001"}).get("net", 0.0)), -20.0),
		"effects: COO + HR labour stacks additively to -20%")
	# VP Logistics (Hitomi ops 3) -> transport cost
	AdvisorState.advisor_seats = {"vp_logistics": "hitomi"}
	AdvisorState.reconcile_advisor_modifiers()
	_check(is_equal_approx(float(Modifiers.resolve_pct("transport_cost", "*", {}).get("net", 0.0)), -10.0),
		"effects: VP Logistics tier 3 -> transport_cost -10%")
	# tier-1 malus: Rufus (ops 1) in COO -> labour reduction flips to a +5% penalty
	AdvisorState.advisor_seats = {"coo": "rufus"}
	AdvisorState.reconcile_advisor_modifiers()
	_check(is_equal_approx(float(Modifiers.resolve_pct("labour_headcount", "b_001", {"building_id": "b_001"}).get("net", 0.0)), 5.0),
		"effects: COO tier 1 (ops 1) -> labour malus +5%")
	# CFO (Marcus fin 3 -> tier 3) emits its Phase-2 finance levers
	AdvisorState.advisor_seats = {"cfo": "marcus"}
	AdvisorState.reconcile_advisor_modifiers()
	_check(is_equal_approx(float(Modifiers.resolve_pct("loan_interest", "*", {}).get("net", 0.0)), -25.0)
		and is_equal_approx(float(Modifiers.resolve_pct("dividend_rate", "*", {}).get("net", 0.0)), -40.0),
		"effects: CFO tier 3 -> loan_interest -25% + dividend_rate -40%")
	AdvisorState.advisor_seats = saved_seats
	Modifiers.reset()

func _test_advisor_phase2_effects() -> void:
	Modifiers.reset()
	var saved_seats: Dictionary = AdvisorState.advisor_seats.duplicate(true)
	# Government Affairs: Hal (inf 3) -> tier 3 -> tax_rate -20%
	AdvisorState.advisor_seats = {"government_affairs": "hal"}
	AdvisorState.reconcile_advisor_modifiers()
	_check(is_equal_approx(float(Modifiers.resolve_pct("tax_rate", "*", {}).get("net", 0.0)), -20.0),
		"phase2: Government Affairs tier 3 -> tax_rate -20%")
	# Chief Markets (flexible): Sloane best-of(inf 3, fin 2) = 3 -> market_spread -25%
	AdvisorState.advisor_seats = {"chief_markets": "sloane"}
	AdvisorState.reconcile_advisor_modifiers()
	_check(is_equal_approx(float(Modifiers.resolve_pct("market_spread", "*", {}).get("net", 0.0)), -25.0),
		"phase2: Chief Markets tier 3 -> market_spread -25%")
	_check(MarketState.get_buy_price("g_001") < MarketState.get_price("g_001") * (1.0 + EconomyConfig.MARKET_BUY_MARKUP),
		"phase2: market_spread modifier tightens the buy price")
	# Chief Markets also lifts the realised SALE price via the market_price domain (+6% tier 3)
	var g := str(Catalog.all_goods()[0].get("id", "g_001"))
	var boosted: float = Modifiers.apply("market_price", g, MarketState.get_price(g),
		{"good_id": g, "good_internal": str(Catalog.get_good(g).get("internal_name", ""))})
	_check(is_equal_approx(boosted, MarketState.get_price(g) * 1.02),
		"phase2: Chief Markets tier 3 -> +2% realised sale price")
	# Arbitrage guard: realised sale price is clamped to the buy price even with a big
	# market_price uplift, so buy-then-resell can never turn a profit.
	Modifiers.add({"id": "test_big_sale_lift", "domain": "market_price", "pct": 50.0, "label": "t", "source": "test"})
	_check(MarketState.get_sale_price(g, {"good_id": g}) <= MarketState.get_buy_price(g) + 0.0001,
		"phase2: sale price is clamped to buy price (no market arbitrage)")
	Modifiers.remove("test_big_sale_lift")
	# CFO: Marcus (fin 3) -> loan interest cut + dividend holiday take effect at their sites
	AdvisorState.advisor_seats = {"cfo": "marcus"}
	AdvisorState.reconcile_advisor_modifiers()
	_check(is_equal_approx(LoanState.effective_loan_interest_rate(), EconomyConfig.LOAN_INTEREST_RATE * 0.75),
		"phase2: CFO cuts the effective loan interest rate to 75%")
	var div_mult: float = maxf(0.0, 1.0 + float(Modifiers.resolve_pct("dividend_rate", "*", {}).get("net", 0.0)) / 100.0)
	_check(is_equal_approx(div_mult, 0.6), "phase2: CFO cuts the dividend rate 40% (partial holiday)")
	# Chief Investment (Alexandra inn 3 -> tier 3) rebates 10% of build-materials value
	AdvisorState.advisor_seats = {"chief_investment": "alexandra"}
	AdvisorState.reconcile_advisor_modifiers()
	_check(is_equal_approx(float(Modifiers.resolve_pct("construction_rebate", "*", {}).get("net", 0.0)), 10.0),
		"phase2: Chief Investment tier 3 -> construction_rebate +10%")
	var ci_bid := ""
	for b in Catalog.all_buildings():
		if not Construction.requirements_for(str(b.get("id", ""))).is_empty():
			ci_bid = str(b.get("id", ""))
			break
	if ci_bid != "":
		var reqs: Dictionary = Construction.requirements_for(ci_bid)
		var mv := 0.0
		for gid2 in reqs:
			mv += float(int(reqs[gid2])) * MarketState.get_price(str(gid2))
		_check(mv > 0.0 and is_equal_approx(MatchState.construction_material_rebate(ci_bid), mv * 0.10),
			"phase2: Chief Investment rebates 10% of build-materials market value")
	# Land + NPC-building purchases discounted 10% at tier 3
	_check(is_equal_approx(AdvisorState.purchase_cost_after_advisor(100.0), 90.0),
		"phase2: Chief Investment tier 3 -> land/building purchase -10%")
	# Upgrade kit is rebated the same way as a build (shares construction_rebate)
	_check(is_equal_approx(MatchState._materials_rebate({str(g): 10}), 10.0 * MarketState.get_price(str(g)) * 0.10),
		"phase2: Chief Investment rebates 10% of upgrade-kit materials value")
	# Seated Chief Investment also unlocks build-on-credit (10-turn, 5% construction loan)
	_check(MatchState.construction_credit_available(), "phase2: seated Chief Investment unlocks build-on-credit")
	var money_b := MatchState.money
	var loans_b := LoanState.loans.size()
	var out_b := LoanState.total_outstanding()
	if LoanState.take_construction_loan(20.0):
		var new_loan: Dictionary = LoanState.loans[LoanState.loans.size() - 1]
		_check(LoanState.loans.size() == loans_b + 1
			and is_equal_approx(LoanState.total_outstanding() - out_b, 21.0)
			and int(new_loan.get("turns_remaining", 0)) == LoanState.CONSTRUCTION_LOAN_TERM,
			"phase2: construction loan owes principal + 5% over 10 turns")
		LoanState.loans.remove_at(LoanState.loans.size() - 1)
	MatchState.money = money_b
	# COO negotiates grid tariffs: cheaper imports, better-paid exports (tier 3 -10% / +10%).
	AdvisorState.advisor_seats = {"coo": "tom"}   # tom ops 3 -> COO tier 3
	AdvisorState.reconcile_advisor_modifiers()
	_check(is_equal_approx(float(Modifiers.resolve_pct("grid_buy_price", "*", {}).get("net", 0.0)), -10.0)
		and is_equal_approx(float(Modifiers.resolve_pct("grid_sell_price", "*", {}).get("net", 0.0)), 10.0),
		"phase2: COO tier 3 -> grid buy -10% / grid sell +10%")
	# Impact readout derives tier-scaled, per-domain effects for a seat.
	var gov_eff: Array = AdvisorState.advisor_seat_effect_list("hal", "government_affairs")
	_check(gov_eff.size() == 1 and str(gov_eff[0]["domain"]) == "tax_rate" and is_equal_approx(float(gov_eff[0]["pct"]), -20.0),
		"impact: advisor_seat_effect_list gives tier-scaled per-domain effects")
	# The hiring comparison is a last-turn cash snapshot, not a vague score. Hal's full
	# tax reduction values at 20% of the tax actually paid; a tier-1 malus has no
	# positive value and therefore cannot disguise itself as a benefit.
	var impact_snapshot := {
		"taxes_paid": 50.0, "labour_paid": 100.0, "maintenance_paid": 40.0,
		"power_purchase_cost": 24.0, "grid_bought": 200, "grid_sold": 20,
		"transport_paid": 30.0, "dividends_paid": 10.0,
		"goods_purchased_cost": 210.0, "goods_sales_revenue": 300.0,
	}
	_check(is_equal_approx(AdvisorState.advisor_bonus_preview_per_turn(
			"hal", "government_affairs", impact_snapshot), 10.0),
		"impact: positive bonus preview values the selected seat against that turn's ledger")
	_check(is_zero_approx(AdvisorState.advisor_bonus_preview_per_turn(
			"rufus", "coo", impact_snapshot)),
		"impact: seat maluses do not appear as positive bonus value")
	AdvisorState.advisor_seats = {}
	AdvisorState.reconcile_advisor_modifiers()
	_check(not MatchState.construction_credit_available(), "phase2: no Chief Investment -> build-on-credit locked")
	AdvisorState.advisor_seats = saved_seats
	AdvisorState.reconcile_advisor_modifiers()
	Modifiers.reset()

func _test_hr_director_policies() -> void:
	var saved_seats := AdvisorState.advisor_seats.duplicate(true)
	var saved_pol := LabourState.workforce_policies.duplicate(true)
	var saved_eff := LabourState.workforce_policy_effects.duplicate(true)
	LabourState.workforce_policies = {}
	LabourState.workforce_policy_effects = {}
	var LT: String = LabourState.WORKFORCE_POLICY_LONG_TENURE
	var SO: String = LabourState.WORKFORCE_POLICY_STOCK_OPTIONS

	AdvisorState.advisor_seats = {}
	AdvisorState.reconcile_advisor_modifiers()
	_check(not LabourState.is_workforce_policy_available(LT) and not LabourState.is_workforce_policy_available(SO),
		"HR: both policies locked with no HR Director")
	# Priya (lead 2): Long Tenure unlocked, Stock Options still locked.
	AdvisorState.advisor_seats = {"hr_director": "priya"}
	AdvisorState.reconcile_advisor_modifiers()
	_check(LabourState.is_workforce_policy_available(LT) and not LabourState.is_workforce_policy_available(SO),
		"HR: Long Tenure needs any HR Director; Stock Options stays locked until its mission")
	# Vera seated: Long Tenure available, but Stock Options is now MISSION-gated (not seat).
	AdvisorState.advisor_seats = {"hr_director": "vera"}
	AdvisorState.reconcile_advisor_modifiers()
	_check(LabourState.is_workforce_policy_available(LT) and not LabourState.is_workforce_policy_available(SO),
		"HR: Stock Options no longer unlocks by seating alone (mission-gated)")
	AdvisorState.advisor_mission_policies = [SO]   # an HR advisor's mission V grants it
	_check(LabourState.is_workforce_policy_available(SO),
		"HR: Stock Options unlocks once an HR advisor's mission grants it")

	# Long Tenure accrues -0.1%/turn labour + a +10% spike every 10th turn.
	LabourState.set_workforce_policy_enabled(LT, true)
	for _i in 5:
		LabourState.tick_workforce_policies()
	var lt_eff: Dictionary = LabourState.workforce_policy_effects.get(LT, {})
	_check(is_equal_approx(float(lt_eff.get("labour_pct", 0.0)), -0.005),
		"HR: Long Tenure accrues -0.1%/turn labour (-0.5% after 5 turns)")
	_check(is_equal_approx(LabourState.workforce_labour_cost_delta(10) - LabourState.workforce_labour_cost_delta(11), 0.10),
		"HR: Long Tenure adds a +10% labour spike every 10th turn")

	# Stock Options accrues output + a dividend bonus (persisted in workforce_dividend_bonus).
	LabourState.set_workforce_policy_enabled(SO, true)
	for _j in 5:
		LabourState.tick_workforce_policies()
	var so_eff: Dictionary = LabourState.workforce_policy_effects.get(SO, {})
	_check(float(so_eff.get("output_pct", 0.0)) > 0.0
		and float(so_eff.get("dividend_pct", 0.0)) > 0.0
		and is_equal_approx(LabourState.workforce_dividend_bonus(), float(so_eff.get("dividend_pct", 0.0))),
		"HR: Stock Options accrues output + dividend bonus")

	# Un-seating the HR Director revokes the seat-gated policy (Long Tenure); the
	# mission-unlocked Stock Options is earned permanently and stays available.
	AdvisorState.advisor_seats = {}
	AdvisorState.reconcile_advisor_modifiers()
	_check(not LabourState.is_workforce_policy_enabled(LT) and LabourState.is_workforce_policy_available(SO),
		"HR: un-seating revokes Long Tenure but keeps the mission-earned Stock Options")

	AdvisorState.advisor_mission_policies = []
	AdvisorState.advisor_seats = saved_seats
	LabourState.workforce_policies = saved_pol
	LabourState.workforce_policy_effects = saved_eff
	AdvisorState.reconcile_advisor_modifiers()

func _test_advisor_loyalty() -> void:
	var saved_perm := AdvisorState.permanent_advisor_ids.duplicate(true)
	var saved_rec := AdvisorState.recruited_advisor_ids.duplicate(true)
	var saved_loyal := AdvisorState.advisor_loyalty.duplicate(true)
	var saved_walk := AdvisorState._advisor_walk_streak.duplicate(true)
	var saved_fired := AdvisorState.fired_advisor_cooldowns.duplicate(true)
	var saved_seats := AdvisorState.advisor_seats.duplicate(true)
	AdvisorState.permanent_advisor_ids = []
	AdvisorState.recruited_advisor_ids = ["vera", "marcus"]
	AdvisorState.advisor_seats = {}
	AdvisorState.fired_advisor_cooldowns = {}
	AdvisorState.advisor_loyalty = {}
	AdvisorState._advisor_walk_streak = {}
	AdvisorState._agenda_flags = {}

	AdvisorState.hire_advisor("vera")
	_check(is_equal_approx(AdvisorState.advisor_loyalty_value("vera"), 0.0), "loyalty: starts at 0 on hire")

	AdvisorState.cheat_set_loyalty("vera", -50.0)
	_check(is_equal_approx(AdvisorState.advisor_loyalty_value("vera"), -10.0), "loyalty: cheat clamps at -10")
	AdvisorState.cheat_set_loyalty("vera", 100.0)
	_check(is_equal_approx(AdvisorState.advisor_loyalty_value("vera"), 10.0), "loyalty: cheat clamps at +10")

	AdvisorState.advisor_loyalty["vera"] = 0.0
	AdvisorState._agenda_flags = {}
	AdvisorState._evaluate_agendas({"money_in": 100.0, "money_out": 0.0}, 100.0)
	_check(is_equal_approx(AdvisorState.advisor_loyalty_value("vera"), 0.6),
		"loyalty: a per-turn liked event (+profit) raises loyalty +0.6")
	# Agenda rows: per-turn likes +0.6, per-turn dislikes -0.4, one-off actions ±1.
	var rows: Array = AdvisorState.advisor_agenda_rows("vera")
	_check(rows.size() == 4 and is_equal_approx(float(rows[0].get("points", 0.0)), 0.6)
		and bool(rows[0].get("per_turn", false)),
		"loyalty: agenda rows expose per-turn like at +0.6/turn")
	# Eleanor dislikes buying grid power (a per-turn event) -> -0.4/turn.
	var el_rows: Array = AdvisorState.advisor_agenda_rows("eleanor")
	var found_grid := false
	for r in el_rows:
		if not bool(r.get("benefit", true)) and bool(r.get("per_turn", false)):
			found_grid = found_grid or is_equal_approx(float(r.get("points", 0.0)), -0.4)
	_check(found_grid, "loyalty: a per-turn dislike is -0.4/turn")

	AdvisorState.advisor_loyalty["vera"] = 5.0
	AdvisorState._agenda_flags = {}
	AdvisorState.flag_agenda_event(AdvisorState.AGENDA_TOOK_LOAN)
	AdvisorState._evaluate_agendas({"money_in": 0.0, "money_out": 0.0}, 0.0)
	_check(is_equal_approx(AdvisorState.advisor_loyalty_value("vera"), 3.9),
		"loyalty: a disliked event lowers loyalty (net of the 0.1 decay)")

	AdvisorState.advisor_loyalty["vera"] = 1.0
	AdvisorState._agenda_flags = {}
	AdvisorState._evaluate_agendas({"money_in": 0.0, "money_out": 0.0}, 0.0)
	_check(is_equal_approx(AdvisorState.advisor_loyalty_value("vera"), 0.9), "loyalty: decays 0.1/turn toward 0")

	for _i in AdvisorState.LOYALTY_WALK_TURNS:
		AdvisorState.advisor_loyalty["vera"] = -10.0
		AdvisorState._agenda_flags = {}
		AdvisorState._evaluate_agendas({"money_in": 0.0, "money_out": 0.0}, 0.0)
	_check(not AdvisorState.permanent_advisor_ids.has("vera") and AdvisorState.is_fired("vera"),
		"loyalty: walks after LOYALTY_WALK_TURNS turns at/below the threshold")

	AdvisorState.permanent_advisor_ids = saved_perm
	AdvisorState.recruited_advisor_ids = saved_rec
	AdvisorState.advisor_loyalty = saved_loyal
	AdvisorState._advisor_walk_streak = saved_walk
	AdvisorState.fired_advisor_cooldowns = saved_fired
	AdvisorState.advisor_seats = saved_seats
	AdvisorState._agenda_flags = {}

func _test_advisor_missions() -> void:
	var demo_terminal := preload("res://scripts/debug_terminal.gd")
	var saved_demo: bool = demo_terminal._demo_unlocked
	demo_terminal._demo_unlocked = true
	var saved_perm := AdvisorState.permanent_advisor_ids.duplicate(true)
	var saved_rec := AdvisorState.recruited_advisor_ids.duplicate(true)
	var saved_loyal := AdvisorState.advisor_loyalty.duplicate(true)
	var saved_done := AdvisorState.advisor_missions_completed.duplicate(true)
	var saved_streak := AdvisorState._advisor_mission5_streak.duplicate(true)
	var saved_pol := AdvisorState.advisor_mission_policies.duplicate(true)
	var saved_unlocked := ResearchState.unlocked_titles.duplicate(true)
	Modifiers.reset()
	AdvisorState.permanent_advisor_ids = ["vera", "eleanor"]
	AdvisorState.recruited_advisor_ids = ["vera", "eleanor"]
	AdvisorState.advisor_loyalty = {"vera": 0.0, "eleanor": 0.0}
	AdvisorState.advisor_missions_completed = {}
	AdvisorState._advisor_mission5_streak = {}
	AdvisorState.advisor_mission_policies = []

	demo_terminal._demo_unlocked = false
	AdvisorState.advisor_loyalty["vera"] = 9.0
	_check(not AdvisorState._check_mission_progress("vera") and AdvisorState.advisor_missions_done("vera") == 0, "demo: advisor missions cannot progress or grant rewards")
	demo_terminal._demo_unlocked = true

	# Missions I-IV complete the first turn loyalty reaches 2 / 5 / 7 / 9.
	AdvisorState.advisor_loyalty["vera"] = 3.0
	AdvisorState._check_mission_progress("vera")
	_check(AdvisorState.advisor_missions_done("vera") == 1, "mission: M1 completes at loyalty 2")
	# M1 grants a temporary specialty modifier (CFO loan interest).
	_check(float(Modifiers.resolve_pct("loan_interest", "*", {}).get("net", 0.0)) < 0.0,
		"mission: CFO M1 applies a temporary loan-interest bonus")

	# Reaching loyalty 9 completes I-IV, but NOT V (which needs a sustained streak).
	AdvisorState.advisor_loyalty["vera"] = 9.0
	AdvisorState._check_mission_progress("vera")
	_check(AdvisorState.advisor_missions_done("vera") == 4,
		"mission: loyalty 9 completes I-IV but V needs the streak")
	# Hold at/above 9 for the full streak -> V completes.
	for _i in AdvisorState.MISSION5_STREAK_TURNS:
		AdvisorState._check_mission_progress("vera")
	_check(AdvisorState.advisor_missions_done("vera") == 5,
		"mission: V completes after MISSION5_STREAK_TURNS turns at loyalty 9+")
	# Dropping below 9 before the streak fills resets it (eleanor).
	AdvisorState.advisor_loyalty["eleanor"] = 9.0
	for _j in 5:
		AdvisorState._check_mission_progress("eleanor")
	AdvisorState.advisor_loyalty["eleanor"] = 8.0   # slips below the streak floor
	AdvisorState._check_mission_progress("eleanor")
	_check(int(AdvisorState._advisor_mission5_streak.get("eleanor", -1)) == 0,
		"mission: the V streak resets when loyalty drops below 9")

	var has_perm := false
	for m in Modifiers.active():
		if str(m.get("id", "")).begins_with("advisor_mission_perm_vera"):
			has_perm = true
	_check(has_perm, "mission: M2/M4/M5 leave permanent modifier slices")

	# Eleanor (HR) mission V unlocks the Stock Options policy once her streak fills.
	AdvisorState.advisor_loyalty["eleanor"] = 9.0
	for _k in AdvisorState.MISSION5_STREAK_TURNS + 1:
		AdvisorState._check_mission_progress("eleanor")
	_check(AdvisorState.advisor_mission_policies.has(LabourState.WORKFORCE_POLICY_STOCK_OPTIONS)
		and LabourState.is_workforce_policy_available(LabourState.WORKFORCE_POLICY_STOCK_OPTIONS),
		"mission: HR advisor mission V unlocks Stock Options")

	# Reward labels are exposed for the UI plaques (5 of them).
	var reward_labels: Array = AdvisorState.advisor_mission_reward_labels("vera")
	_check(reward_labels.size() == 5,
		"mission: 5 reward labels exposed for the detail plaques")
	_check("Applies" in str(reward_labels[0])
			and "Permanent" in str(reward_labels[1])
			and "Free research" in str(reward_labels[2]),
		"mission: reward labels describe the actual mission reward")

	Modifiers.reset()
	AdvisorState.permanent_advisor_ids = saved_perm
	AdvisorState.recruited_advisor_ids = saved_rec
	AdvisorState.advisor_loyalty = saved_loyal
	AdvisorState.advisor_missions_completed = saved_done
	AdvisorState._advisor_mission5_streak = saved_streak
	AdvisorState.advisor_mission_policies = saved_pol
	ResearchState.unlocked_titles = saved_unlocked
	AdvisorState.reconcile_advisor_modifiers()
	demo_terminal._demo_unlocked = saved_demo


func _test_advisor_mission_update_signals() -> void:
	var demo_terminal := preload("res://scripts/debug_terminal.gd")
	var saved_demo: bool = demo_terminal._demo_unlocked
	demo_terminal._demo_unlocked = true
	var saved_perm := AdvisorState.permanent_advisor_ids.duplicate(true)
	var saved_rec := AdvisorState.recruited_advisor_ids.duplicate(true)
	var saved_loyal := AdvisorState.advisor_loyalty.duplicate(true)
	var saved_done := AdvisorState.advisor_missions_completed.duplicate(true)
	var saved_streak := AdvisorState._advisor_mission5_streak.duplicate(true)
	var loyalty_events: Array = []
	var mission_events: Array = []
	var on_loyalty := func(advisor_id: String, loyalty: float) -> void:
		loyalty_events.append({"id": advisor_id, "loyalty": loyalty})
	var on_mission := func(advisor_id: String) -> void:
		mission_events.append(advisor_id)
	AdvisorState.advisor_loyalty_changed.connect(on_loyalty)
	AdvisorState.advisor_mission_state_changed.connect(on_mission)

	Modifiers.reset()
	AdvisorState.permanent_advisor_ids = ["vera"]
	AdvisorState.recruited_advisor_ids = ["vera"]
	AdvisorState.advisor_loyalty = {"vera": 0.0}
	AdvisorState.advisor_missions_completed = {}
	AdvisorState._advisor_mission5_streak = {}

	AdvisorState.cheat_set_loyalty("vera", 2.0)
	_check(AdvisorState.advisor_missions_done("vera") == 1
		and not loyalty_events.is_empty()
		and str(loyalty_events[0].get("id", "")) == "vera"
		and mission_events.has("vera"),
		"mission: loyalty changes advance missions and emit detail refresh signals")

	if AdvisorState.advisor_loyalty_changed.is_connected(on_loyalty):
		AdvisorState.advisor_loyalty_changed.disconnect(on_loyalty)
	if AdvisorState.advisor_mission_state_changed.is_connected(on_mission):
		AdvisorState.advisor_mission_state_changed.disconnect(on_mission)
	Modifiers.reset()
	AdvisorState.permanent_advisor_ids = saved_perm
	AdvisorState.recruited_advisor_ids = saved_rec
	AdvisorState.advisor_loyalty = saved_loyal
	AdvisorState.advisor_missions_completed = saved_done
	AdvisorState._advisor_mission5_streak = saved_streak
	AdvisorState.reconcile_advisor_modifiers()
	demo_terminal._demo_unlocked = saved_demo


func _test_people_panel_mission_ui() -> void:
	var pp: Node = load("res://scripts/people_panel.gd").new()
	var quests := [
		{"roman": "I", "title": "Onboard", "state": "completed", "color": Color("#CDA349"), "reward": "First reward", "req_text": "at loyalty 2"},
		{"roman": "II", "title": "Prove", "state": "next", "color": Color("#536C92"), "reward": "Second reward", "req_text": "at loyalty 5"},
		{"roman": "III", "title": "Expand", "state": "locked", "color": Color("#4F6B58"), "reward": "Third reward", "req_text": "at loyalty 7"},
		{"roman": "IV", "title": "Master", "state": "locked", "color": Color("#765742"), "reward": "Fourth reward", "req_text": "at loyalty 9"},
		{"roman": "V", "title": "Legacy", "state": "locked", "color": Color("#6B6077"), "reward": "Legacy reward", "req_text": "loyalty 9+ for 20 turns (3/20)"},
	]
	var plaque: Control = pp.call("_mission_plaque", quests[1]) as Control
	_check(_tree_has_label_text(plaque, "II")
		and not _tree_has_label_text(plaque, "Prove")
		and not _tree_has_label_text(plaque, "Second reward")
		and not _tree_has_label_text(plaque, "at loyalty"),
		"PeoplePanel missions: plaques show only the roman numeral")

	var rewards: Control = pp.call("_mission_rewards_row", quests) as Control
	_check(_tree_has_label_text(rewards, "Reward") and _tree_has_label_text(rewards, "Legacy reward"),
		"PeoplePanel missions: rewards render in the separate row")
	var rewards_margin: MarginContainer = rewards.find_child("MissionRewardsMargin", true, false) as MarginContainer
	var rewards_row: HBoxContainer = rewards.find_child("MissionRewardsRow", true, false) as HBoxContainer
	var first_reward: Control = rewards.find_child("MissionReward_I", true, false) as Control
	_check(rewards is ScrollContainer
			and rewards_margin != null
			and rewards_row != null
			and first_reward != null
			and rewards_margin.get_theme_constant("margin_left") >= 10
			and rewards_margin.get_theme_constant("margin_right") >= 10
			and rewards_row.get_theme_constant("separation") >= 20
			and first_reward.custom_minimum_size.x <= 164.0,
		"PeoplePanel missions: reward cards keep max width, edge padding, and 20px gaps")

	var bar: Control = pp.call("_loyalty_bar", 5.0, quests) as Control
	_check(_tree_has_label_text(bar, "V: loyalty 9+ for 20 turns (3/20)")
		and _tree_has_label_text(bar, "9+ 20t"),
		"PeoplePanel missions: loyalty milestones live on the bar")

func _test_advisor_seats_save_roundtrip() -> void:
	var saved_seats: Dictionary = AdvisorState.advisor_seats.duplicate(true)
	var saved_slots: int = AdvisorState.max_advisor_slots
	AdvisorState.advisor_seats = {"cfo": "vera", "coo": "tom"}
	AdvisorState.max_advisor_slots = 3
	var d: Dictionary = MatchState.export_state()
	AdvisorState.advisor_seats = {}
	AdvisorState.max_advisor_slots = 2
	MatchState.import_state(d)
	_check(AdvisorState.advisor_seats.get("cfo", "") == "vera" and AdvisorState.advisor_seats.get("coo", "") == "tom",
		"save: advisor_seats round-trips")
	_check(AdvisorState.max_advisor_slots == 3, "save: max_advisor_slots round-trips")
	# backward-compat: a v3 save missing the keys defaults to empty seats + 2 slots
	d.erase("advisor_seats")
	d.erase("max_advisor_slots")
	MatchState.import_state(d)
	_check(AdvisorState.advisor_seats.is_empty() and AdvisorState.max_advisor_slots == AdvisorState.MAX_ADVISOR_SLOTS_DEFAULT,
		"save: missing keys default (v3 back-compat)")
	# sanitize drops a bogus seat_id + an un-rostered advisor, keeps valid entries
	_check(AdvisorState._sanitize_advisor_seats({"cfo": "vera", "bogus_seat": "vera", "coo": "not_real"}) == {"cfo": "vera"},
		"save: sanitize drops bad seat + un-rostered advisor")
	AdvisorState.advisor_seats = saved_seats
	AdvisorState.max_advisor_slots = saved_slots

func _test_advisor_milestone_acquisition() -> void:
	var saved_hired: Array = AdvisorState.recruited_advisor_ids.duplicate(true)
	var saved_crossed: Array = AdvisorState.crossed_milestones.duplicate(true)
	var saved_unlocked := AdvisorState.advisors_unlocked
	# The milestone-recruit mechanism draws from the FULL roster once the gate is open; the
	# demo restriction (only the three demo advisors) is covered by _test_advisor_demo_gating.
	AdvisorState.advisors_unlocked = true
	AdvisorState.recruited_advisor_ids = []
	AdvisorState.crossed_milestones = []
	MatchState._match_rng.seed = MatchState.DEFAULT_MATCH_RNG_SEED
	AdvisorState.check_profit_milestones(40.0)
	_check(AdvisorState.recruited_advisor_ids.is_empty(), "milestone: below 50 profit recruits nothing")
	AdvisorState.check_profit_milestones(60.0)
	_check(AdvisorState.recruited_advisor_ids.size() == 1 and AdvisorState.crossed_milestones.has(50),
		"milestone: crossing 50 recruits one advisor")
	var first_id := str(AdvisorState.recruited_advisor_ids[0])
	AdvisorState.check_profit_milestones(60.0)
	_check(AdvisorState.recruited_advisor_ids.size() == 1, "milestone: re-crossing 50 does not re-recruit (latched)")
	AdvisorState.check_profit_milestones(220.0)
	_check(AdvisorState.recruited_advisor_ids.size() == 4 and AdvisorState.crossed_milestones.has(200),
		"milestone: a jump recruits each newly-crossed milestone (100/150/200)")
	AdvisorState.recruited_advisor_ids = []
	AdvisorState.crossed_milestones = []
	MatchState._match_rng.seed = MatchState.DEFAULT_MATCH_RNG_SEED
	AdvisorState.check_profit_milestones(60.0)
	_check(str(AdvisorState.recruited_advisor_ids[0]) == first_id, "milestone: seeded recruit is deterministic")
	AdvisorState.recruited_advisor_ids = saved_hired
	AdvisorState.crossed_milestones = saved_crossed
	AdvisorState.advisors_unlocked = saved_unlocked

# Demo gating (owner 2026-08-19): only Andrew/Vera/Gerald and the four base seats exist until
# the `unlock advisors` cheat opens the full roster, every seat, and the seat-unlock research.
func _test_advisor_demo_gating() -> void:
	# NB: do NOT call MatchState.reset() here — it wipes the NPC ports placed at scene _ready
	# that a later test depends on. Save/restore only the fields this test actually touches.
	var saved_hired: Array = AdvisorState.recruited_advisor_ids.duplicate(true)
	var saved_crossed: Array = AdvisorState.crossed_milestones.duplicate(true)
	var saved_unlocked := AdvisorState.advisors_unlocked
	var saved_all_seats := AdvisorState.all_seats_unlocked
	var saved_rng: int = MatchState._match_rng.state
	AdvisorState.advisors_unlocked = false
	AdvisorState.all_seats_unlocked = false
	_check(AdvisorState.DEMO_ADVISORS.size() == 3 and AdvisorState.BASE_SEATS.size() == 4,
		"gating: three demo advisors, four base seats")
	_check(AdvisorState.available_seat_ids().size() == AdvisorState.BASE_SEATS.size(),
		"gating: only the four base seats before unlock")
	# Milestones only ever recruit the three demo advisors while locked.
	AdvisorState.recruited_advisor_ids = []
	AdvisorState.crossed_milestones = []
	MatchState._match_rng.seed = MatchState.DEFAULT_MATCH_RNG_SEED
	AdvisorState.check_profit_milestones(100000.0)  # cross every milestone at once
	for id in AdvisorState.recruited_advisor_ids:
		_check(AdvisorState.DEMO_ADVISORS.has(str(id)), "gating: locked milestones recruit only demo advisors")
	_check(AdvisorState.recruited_advisor_ids.size() <= AdvisorState.DEMO_ADVISORS.size(),
		"gating: no more than the three demo advisors recruited while locked")
	# The cheat opens the roster, every seat, and (elsewhere) the seat research.
	MatchState.cheat_unlock_advisors()
	_check(AdvisorState.advisors_unlocked, "gating: unlock advisors flips the flag")
	_check(AdvisorState.is_seat_available("hr_director") and AdvisorState.is_seat_available("government_affairs"),
		"gating: unlock advisors opens the previously-closed seats")
	_check(AdvisorState.recruited_advisor_ids.has("marcus") and AdvisorState.recruited_advisor_ids.has("idris"),
		"gating: unlock advisors recruits the previously-locked advisors")
	AdvisorState.advisors_unlocked = saved_unlocked
	AdvisorState.all_seats_unlocked = saved_all_seats
	AdvisorState.recruited_advisor_ids = saved_hired
	AdvisorState.crossed_milestones = saved_crossed
	MatchState._match_rng.state = saved_rng

func _test_advisor_slot_progression() -> void:
	var saved_advisors: bool = AdvisorState.advisors_unlocked
	AdvisorState.advisors_unlocked = true # Full-roster progression; demo gating is tested separately.
	var saved_slots: int = AdvisorState.max_advisor_slots
	var saved_streak: int = AdvisorState._advisor_profit_streak
	var saved_pu: bool = AdvisorState.advisor_slot_profit_unlocked
	AdvisorState.max_advisor_slots = 2
	AdvisorState._advisor_profit_streak = 0
	AdvisorState.advisor_slot_profit_unlocked = false
	AdvisorState._update_advisor_slots(10.0)
	_check(AdvisorState.max_advisor_slots == 2, "slot progression: low profit / few buildings keeps 2")
	AdvisorState._update_advisor_slots(1000.0)
	AdvisorState._update_advisor_slots(1000.0)
	_check(not AdvisorState.advisor_slot_profit_unlocked, "slot progression: 2 turns at 1000 is not yet the streak")
	var had_fifth: bool = ResearchState.is_unlocked("Fifth Advisor Seat")
	AdvisorState._update_advisor_slots(1000.0)
	_check(AdvisorState.advisor_slot_profit_unlocked and AdvisorState.max_advisor_slots == 3,
		"slot progression: 1000 profit x3 unlocks a slot (2 -> 3)")
	_check(ResearchState.is_unlocked("Fifth Advisor Seat"),
		"slot progression: 5th-seat unlock granted (shows under People & Management)")
	AdvisorState._update_advisor_slots(0.0)
	_check(AdvisorState.max_advisor_slots == 3, "slot progression: a dip does not revoke the earned slot")
	AdvisorState.advisors_unlocked = saved_advisors
	AdvisorState.max_advisor_slots = saved_slots
	AdvisorState._advisor_profit_streak = saved_streak
	AdvisorState.advisor_slot_profit_unlocked = saved_pu
	if not had_fifth:
		ResearchState.unlocked_titles.erase("Fifth Advisor Seat")

func _test_advisor_fake_money_and_track() -> void:
	var saved_money := MatchState.money
	var saved_fake := MatchState.fake_money_this_turn
	var saved_crossed := AdvisorState.crossed_milestones.duplicate(true)
	MatchState.fake_money_this_turn = 0.0
	MatchState.cheat_add_cash(500.0)
	_check(is_equal_approx(MatchState.fake_money_this_turn, 500.0) and is_equal_approx(MatchState.money, saved_money + 500.0),
		"fake money: cheat_add_cash tracks fake money + raises the balance")
	AdvisorState.crossed_milestones = [50, 100]
	_check(AdvisorState.next_advisor_milestone() == 150, "advisor track: next milestone is the first un-crossed (150)")
	AdvisorState.crossed_milestones = [50, 100, 150, 200, 300, 400, 500, 750, 1000]
	_check(AdvisorState.next_advisor_milestone() == 0, "advisor track: all milestones crossed -> 0")
	# Cheat cash (fake money) must count toward the profit that drives advisor unlocks.
	var saved_rec_fm: Array = AdvisorState.recruited_advisor_ids.duplicate(true)
	AdvisorState.crossed_milestones = []
	AdvisorState._on_turn_processed_advisors({"money_in": 0.0, "money_out": 0.0, "fake_money": 120.0})
	_check(AdvisorState.crossed_milestones.has(50) and AdvisorState.crossed_milestones.has(100)
		and not AdvisorState.crossed_milestones.has(150),
		"fake money: cheat cash crosses profit milestones (drives advisor unlocks)")
	AdvisorState.recruited_advisor_ids = saved_rec_fm
	MatchState.money = saved_money
	MatchState.fake_money_this_turn = saved_fake
	AdvisorState.crossed_milestones = saved_crossed
	MatchState.money_changed.emit(MatchState.money)

func _test_advisor_slot_unlock() -> void:
	var saved: int = AdvisorState.max_advisor_slots
	AdvisorState.max_advisor_slots = 2
	AdvisorState.unlock_advisor_slot()
	_check(AdvisorState.max_advisor_slots == 3, "slot unlock: raises the cap by 1")
	AdvisorState.unlock_advisor_slot()
	AdvisorState.unlock_advisor_slot()
	AdvisorState.unlock_advisor_slot()
	_check(AdvisorState.max_advisor_slots == 5, "slot unlock: clamps at the cap (5)")
	AdvisorState.max_advisor_slots = saved

func _test_advisor_acquisition_save_roundtrip() -> void:
	var saved_rec: Array = AdvisorState.recruited_advisor_ids.duplicate(true)
	var saved_crossed: Array = AdvisorState.crossed_milestones.duplicate(true)
	AdvisorState.recruited_advisor_ids = []
	AdvisorState.crossed_milestones = []
	MatchState._match_rng.seed = MatchState.DEFAULT_MATCH_RNG_SEED
	AdvisorState.check_profit_milestones(60.0)   # cross 50, advance the rng past one recruit
	var d: Dictionary = MatchState.export_state()
	MatchState.import_state(d)
	_check(AdvisorState.crossed_milestones.has(50) and AdvisorState.recruited_advisor_ids.size() == 1,
		"acquisition save: crossed_milestones + recruited round-trip")
	var draw_a := AdvisorState.draw_advisor_from_pool()
	MatchState.import_state(d)                  # restore -> rng state reset to the saved value
	var draw_b := AdvisorState.draw_advisor_from_pool()
	_check(draw_a != "" and draw_a == draw_b, "acquisition save: rng state persists -> next recruit reproducible")
	AdvisorState.recruited_advisor_ids = saved_rec
	AdvisorState.crossed_milestones = saved_crossed

func _test_founder_advisor() -> void:
	# Demo gating (owner 2026-08-19): four posts exist by default — CFO, COO, Technical Director,
	# Chief Markets — and the rest wait behind `unlock advisors`. The family friend still fills one
	# of the two starting chairs pro bono. See docs/early-game-onboarding-spec.md §5.4.
	MatchState.reset()
	_check(AdvisorState.is_seat_available("cfo") and AdvisorState.is_seat_available("coo")
		and AdvisorState.is_seat_available("technical_director") and AdvisorState.is_seat_available("chief_markets"),
		"seats: the four base posts are open from the start")
	_check(not AdvisorState.is_seat_available("hr_director")
		and not AdvisorState.is_seat_available("government_affairs"),
		"seats: every other post is closed until unlocked")
	_check(AdvisorState.available_seat_ids().size() == AdvisorState.BASE_SEATS.size(),
		"seats: exactly the four base posts are offered at the start")
	AdvisorState.permanent_advisor_ids = ["vera"]
	_check(not AdvisorState.assign_advisor_to_seat("vp_logistics", "vera"),
		"seats: a closed post refuses an appointment")
	AdvisorState.advisors_unlocked = true # Executive Search is available only with the full roster.
	ResearchState.grant_unlock(ResearchState.SEATS_UNLOCK_TITLE)
	_check(AdvisorState.all_seats_unlocked,
		"seats: %s opens the rest of the council" % ResearchState.SEATS_UNLOCK_TITLE)
	_check(AdvisorState.assign_advisor_to_seat("vp_logistics", "vera"),
		"seats: a closed post accepts an appointment once unlocked")

	# Andrew joins pro bono, holds his post for the tenure, and cannot be displaced.
	MatchState.reset()
	TurnManager.current_turn = 3
	_check(AdvisorState.seat_founder("coo"), "founder: Andrew takes the post he was offered")
	_check(AdvisorState.get_advisor_in_seat("coo") == AdvisorState.FOUNDER_ADVISOR_ID,
		"founder: he is seated as COO")
	_check(AdvisorState.founder_leaves_turn == 3 + AdvisorState.FOUNDER_TENURE_TURNS,
		"founder: his tenure runs %d turns" % AdvisorState.FOUNDER_TENURE_TURNS)
	_check(not AdvisorState.founder_tenure_expired(), "founder: the tenure is live at turn 3")
	_check(AdvisorState.payrolled_advisor_count() == 0
		and is_zero_approx(AdvisorState.advisor_payroll_per_turn(1000.0)),
		"founder: Andrew's promised pro-bono tenure contributes £0 to payroll")
	AdvisorState.permanent_advisor_ids.append("vera")
	_check(AdvisorState.payrolled_advisor_count() == 1
		and is_equal_approx(AdvisorState.advisor_payroll_per_turn(1000.0),
			AdvisorState.advisor_cost_per_advisor(1000.0)),
		"founder: an ordinary advisor is still charged while Andrew remains unpaid")
	_check(not AdvisorState.assign_advisor_to_seat("coo", "vera"),
		"founder: his chair cannot be given away mid-tenure")

	TurnManager.current_turn = AdvisorState.founder_leaves_turn
	_check(AdvisorState.founder_tenure_expired(), "founder: the tenure expires on schedule")
	AdvisorState.release_founder()
	_check(AdvisorState.get_advisor_in_seat("coo") == "",
		"founder: he vacates and the post opens")
	_check(AdvisorState.assign_advisor_to_seat("coo", "vera"),
		"founder: a real hire can take the chair afterwards")

	# The COO gift: pre-paid domestic freight, spent before any charge is raised.
	MatchState.reset()
	TransportState.add_freight_credit(1000)
	_check(TransportState.freight_credit_units == 1000, "founder: the freight credit lands")
	_check(TransportState.consume_freight_credit(400) == 400
		and TransportState.freight_credit_units == 600,
		"founder: freight credit is drawn down as it is used")
	_check(TransportState.consume_freight_credit(5000) == 600
		and TransportState.freight_credit_units == 0,
		"founder: the credit covers what it can and then runs out")
	_check(TransportState.consume_freight_credit(10) == 0,
		"founder: an exhausted credit covers nothing")

	# Peeking must never spend: quotes, previews and the build forecast all run the same
	# costing path as a real shipment, so a consuming peek would drain the gift on sight.
	TransportState.add_freight_credit(100)
	_check(TransportState.peek_freight_credit(40) == 40 and TransportState.freight_credit_units == 100,
		"founder: peeking at the credit does not spend it")
	_check(TransportState.peek_freight_credit(500) == 100,
		"founder: a peek is capped at what remains")

	# The credit buys free OVERLAND movement and must not touch the port's ad valorem.
	var route := {"reachable": true, "turns": 2, "legs": [{"mode": "roads"}, {"mode": "roads"}]}
	TransportState.freight_credit_units = 0
	var full: float = TransportService.land_cost_after_credit("g_001", 100, route, false)
	_check(full > 0.0, "founder: with no credit the haul is charged in full (%.2f)" % full)
	TransportState.freight_credit_units = 100
	_check(is_zero_approx(TransportService.land_cost_after_credit("g_001", 100, route, false)),
		"founder: a fully covered haul is free")
	_check(TransportState.freight_credit_units == 100,
		"founder: quoting a covered haul still spends nothing")
	TransportState.freight_credit_units = 50
	var half: float = TransportService.land_cost_after_credit("g_001", 100, route, true)
	_check(is_equal_approx(half, full * 0.5) and TransportState.freight_credit_units == 0,
		"founder: a half-covered haul charges half and spends the rest")
	TurnManager.current_turn = 1

func _test_cfo_tax_credit() -> void:
	# CFO tax-loss carry-forward: a losing turn banks 5% of revenue, usable oldest-first
	# to shave the tax bill over the next 5 turns, then expiring.
	var seats_before: Dictionary = AdvisorState.advisor_seats.duplicate(true)
	MatchState.cfo_tax_credit_pool = []
	MatchState.cfo_tax_credit_intro_shown = false
	AdvisorState.advisor_seats = {"cfo": "vera"}
	_check(MatchState.cfo_seated(), "cfo credit: a seated CFO is detected")

	# Bank 5% of £1000 = £50; the one-time explainer fires exactly once.
	var fires := [0]
	var cb := func(_a: float) -> void: fires[0] += 1
	MatchState.cfo_tax_credit_filed.connect(cb)
	var banked := MatchState.cfo_bank_tax_credit(1000.0)
	_check(absf(banked - 50.0) < 0.001, "cfo credit: banks 5% of revenue (£1000 → £50)")
	_check(fires[0] == 1, "cfo credit: explainer fires on the first filing")
	MatchState.cfo_bank_tax_credit(500.0)   # £25; a later filing does NOT re-fire the explainer
	_check(fires[0] == 1, "cfo credit: explainer is one-time only")
	MatchState.cfo_tax_credit_filed.disconnect(cb)

	# Pool = £50 + £25 = £75. Apply against a £40 tax bill: spends £40 (oldest first).
	_check(absf(MatchState.cfo_tax_credit_available() - 75.0) < 0.001, "cfo credit: pool totals both filings")
	var applied := MatchState.cfo_apply_tax_credit(40.0)
	_check(absf(applied - 40.0) < 0.001, "cfo credit: applies up to the tax owed")
	_check(absf(MatchState.cfo_tax_credit_available() - 35.0) < 0.001, "cfo credit: pool drops by the amount spent")

	# Asking for more than what's left returns only the remainder and empties the pool.
	var rest := MatchState.cfo_apply_tax_credit(1000.0)
	_check(absf(rest - 35.0) < 0.001, "cfo credit: caps at the remaining credit")
	_check(MatchState.cfo_tax_credit_pool.is_empty(), "cfo credit: pool empties once fully spent")

	# Expiry: a fresh credit survives 4 agings and expires on the 5th.
	MatchState.cfo_tax_credit_pool = []
	MatchState.cfo_bank_tax_credit(2000.0)   # £100, turns_left 5
	for _i in range(4):
		MatchState.cfo_age_tax_credits()
	_check(MatchState.cfo_tax_credit_available() > 0.0, "cfo credit: survives 4 turns")
	MatchState.cfo_age_tax_credits()
	_check(MatchState.cfo_tax_credit_pool.is_empty(), "cfo credit: expires after the 5-turn window")

	MatchState.cfo_tax_credit_pool = []
	MatchState.cfo_tax_credit_intro_shown = false
	AdvisorState.advisor_seats = seats_before
