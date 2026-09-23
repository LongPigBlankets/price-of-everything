extends Node

# A loan is a Dictionary with:
#   id: int (incremental, unique)
#   principal_initial: float (originally borrowed amount)
#   principal_remaining: float (decreases each turn until 0)
#   payment_per_turn: float
#   turns_remaining: int
#   interest_paid: float (running total, for stats)

var loans: Array = []
var _next_loan_id: int = 1

# Set during process_payments(); read by Production.
var last_payment_total: float = 0.0
var _last_payments_turn: int = -1

# Transit credit: in intermediary games a port sale is paid only when it reaches the port.
# This line advances the sale's locked-in revenue when the goods leave, secured on the
# cargo rather than on borrowing capacity. Each shipment repays its own advance when it
# lands, and the balance on the road pays the standard rate spread over the loan term each
# turn, so a faster route to the port costs less.
var transit_credit_enabled: bool = true
var transit_credit_balance: float = 0.0
# This turn's line movements, copied into the turn summary by Production.
var transit_drawn_this_turn: float = 0.0
var transit_repaid_this_turn: float = 0.0

func _ready() -> void:
	MatchState.state_reset.connect(func() -> void:
		_last_payments_turn = -1
		begin_turn())

## Absolute schedule from the saved amortisation amounts. No new save fields needed.
## current_turn names the next turn to resolve in DECIDE, not the last completed turn.
func repayment_turns(loan: Dictionary) -> Vector2i:
	var next_turn := TurnManager.current_turn + (1 if _last_payments_turn == TurnManager.current_turn else 0)
	var grace := int(loan.get("grace_remaining", 0))
	if grace > 0:
		var first := next_turn + grace
		return Vector2i(first, first + EconomyConfig.LOAN_TERM_TURNS - 1)
	var payment := float(loan.get("payment_per_turn", 0.0))
	if payment <= 0.0:
		return Vector2i.ZERO
	var total := float(loan.get("total_repayment", float(loan.get("principal_initial", 0.0)) * (1.0 + float(loan.get("interest_rate", EconomyConfig.LOAN_INTEREST_RATE)))))
	var original_count := ceili(total / payment - 0.000001)
	var remaining_count := mini(int(loan.get("turns_remaining", 0)), ceili(float(loan.get("principal_remaining", 0.0)) / payment - 0.000001))
	if remaining_count <= 0:
		return Vector2i.ZERO
	return Vector2i(next_turn - maxi(0, original_count - remaining_count), next_turn + remaining_count - 1)

func repayment_label(loan: Dictionary) -> String:
	var span := repayment_turns(loan)
	return "Repay Turn %d–%d" % [span.x, span.y] if span != Vector2i.ZERO else "Repaid"

func loan_label(loan: Dictionary) -> String:
	var rate := ("%.2f" % (float(loan.get("interest_rate", EconomyConfig.LOAN_INTEREST_RATE)) * 100.0)).trim_suffix("0").trim_suffix("0").trim_suffix(".")
	return "Loan #%d (%s%%)" % [int(loan.get("id", 0)), rate]

# Rolling per-turn economics that drive the dynamic borrowing capacity. Production
# pushes (net_profit, revenue) here each turn via record_turn_economics(); only the
# last LOAN_PROFIT_WINDOW turns are kept.
var _profit_history: Array = []   # retained net profit per turn (can be negative)
var _revenue_history: Array = []  # gross sales revenue per turn

signal loans_updated
signal loan_taken(loan: Dictionary)
signal loan_repaid(loan_id: int)
signal payment_made(total_amount: float)
signal bankruptcy_warning(money: float, floor: float)

# === Public API ===

# The current borrowing rate, after any CFO "loan_interest" discount (clamped ≥ 0).
func effective_loan_interest_rate() -> float:
	var mult: float = maxf(0.0, 1.0 + float(Modifiers.resolve_pct("loan_interest", "*", {}).get("net", 0.0)) / 100.0)
	return EconomyConfig.LOAN_INTEREST_RATE * mult

# Construction-on-credit (unlocked by a Chief Investment advisor): a fixed short-term,
# low-interest loan financing a single build.
const CONSTRUCTION_LOAN_TERM := 10
const CONSTRUCTION_LOAN_RATE := 0.05

func take_loan(amount: float) -> bool:
	# Standard loan: LOAN_GRACE_TURNS interest-accruing turns, then 36 turns of repayment.
	if amount <= 0.0:
		return false
	amount = maxf(amount, EconomyConfig.LOAN_MINIMUM)
	if amount > available_capacity():
		return false
	return _create_loan(amount, effective_loan_interest_rate(), EconomyConfig.LOAN_TERM_TURNS,
		EconomyConfig.LOAN_GRACE_TURNS)

# Distress loan (decision events, spec §12.1): standard rate/term but BYPASSES the
# profit-gated borrowing capacity — an unaffordable decision choice must always be
# payable, so the shortfall is forced onto the books instead of blocking the choice.
func take_distress_loan(amount: float) -> bool:
	if amount <= 0.0:
		return false
	return _create_loan(maxf(amount, EconomyConfig.LOAN_MINIMUM), effective_loan_interest_rate(),
		EconomyConfig.LOAN_TERM_TURNS, EconomyConfig.LOAN_GRACE_TURNS)

# Founder's gift (spec §5.4): a one-off loan at a favourable rate on the standard life,
# bypassing borrowing capacity — it is offered by a board member, not applied for.
func take_founder_loan(amount: float, rate: float) -> bool:
	if amount <= 0.0:
		return false
	return _create_loan(maxf(amount, EconomyConfig.LOAN_MINIMUM), maxf(0.0, rate),
		EconomyConfig.LOAN_TERM_TURNS, EconomyConfig.LOAN_GRACE_TURNS)

func take_construction_loan(amount: float) -> bool:
	# 10-turn, 5% build loan. Respects the same borrowing capacity as any other loan.
	if amount <= 0.0 or amount > available_capacity():
		return false
	return _create_loan(amount, CONSTRUCTION_LOAN_RATE, CONSTRUCTION_LOAN_TERM)

# Grace loan (distressed-asset bailout): `amount` disbursed now, then `grace_turns`
# with NO payments and NO interest, after which it converts to a normal amortised
# loan at the standard rate over LOAN_TERM_TURNS. Bypasses borrowing capacity (it's a
# rescue). Grace bookkeeping lives on the loan dict and is handled in process_payments.
func take_grace_loan(amount: float, grace_turns: int) -> bool:
	if amount <= 0.0:
		return false
	var rate: float = effective_loan_interest_rate()
	var loan: Dictionary = {
		"id": _next_loan_id,
		"principal_initial": amount,
		"principal_remaining": amount,          # no interest during grace
		"payment_per_turn": 0.0,                # no payments during grace
		"turns_remaining": grace_turns + EconomyConfig.LOAN_TERM_TURNS,
		"interest_paid": 0.0,
		"interest_rate": rate,
		"grace_remaining": grace_turns,
	}
	_next_loan_id += 1
	loans.append(loan)
	AdvisorState.flag_agenda_event(AdvisorState.AGENDA_TOOK_LOAN)
	MatchState.add_money(amount)
	print("[LoanState] Grace loan #%d: £%.2f, %d interest-free turns then %.1f%% over %d" % [
		loan.id, amount, grace_turns, rate * 100.0, EconomyConfig.LOAN_TERM_TURNS])
	loan_taken.emit(loan)
	loans_updated.emit()
	return true

# Shared loan creation: bakes the (rate, term) into the amortisation and disburses
# the principal. Per-loan rate/term are stored so processing stays accurate even when
# multiple loans of different terms coexist.
func _create_loan(amount: float, rate: float, term: int, grace: int = 0) -> bool:
	# Interest is charged for the loan's whole LIFE, grace included, then amortised over the
	# paying turns only. So grace defers the burden and enlarges it — it is forbearance, not a
	# discount — and a 12+36 loan at 15% repays 1 + 0.15 x 48/36 = 1.20x rather than 1.15x.
	var life: float = float(term + grace)
	var total_repayment: float = amount * (1.0 + rate * life / float(term))
	var per_turn: float = total_repayment / float(term)
	var loan: Dictionary = {
		"id": _next_loan_id,
		"principal_initial": amount,
		# During grace nothing is due, so the books carry the principal until it converts.
		"principal_remaining": amount if grace > 0 else total_repayment,
		"payment_per_turn": 0.0 if grace > 0 else per_turn,
		"turns_remaining": term + grace,
		"interest_paid": 0.0,
		"interest_rate": rate,
		"grace_remaining": grace,
		"total_repayment": total_repayment,
		# The building this loan financed, when it is a construction loan taken to build one
		# specific site (set via tag_last_loan_building right after the site is placed). "" for
		# a general empire loan — those stay a company-level cost and are not attributed to any
		# building's economics. Saved with the loan (export_state deep-copies the dict).
		"building_instance": "",
	}
	_next_loan_id += 1
	loans.append(loan)
	AdvisorState.flag_agenda_event(AdvisorState.AGENDA_TOOK_LOAN)
	MatchState.add_money(amount)   # disburse principal
	if grace > 0:
		print("[LoanState] Loan #%d taken: £%.2f (%d grace turns, then £%.4f/turn for %d @ %.1f%%, total £%.2f)" % [
			loan.id, amount, grace, per_turn, term, rate * 100.0, total_repayment])
	else:
		print("[LoanState] Loan #%d taken: £%.2f (£%.4f/turn for %d turns @ %.1f%%, total £%.2f)" % [
			loan.id, amount, per_turn, term, rate * 100.0, total_repayment])
	loan_taken.emit(loan)
	loans_updated.emit()
	return true

func repay_loan(loan_id: int) -> bool:
	# Pays off remaining balance immediately. Removes loan.
	# Returns true on success, false if loan not found or insufficient money.
	var idx: int = _find_loan_index(loan_id)
	if idx == -1:
		return false
	
	var loan: Dictionary = loans[idx]
	var amount: float = loan.principal_remaining
	
	if not MatchState.deduct_money(amount):
		return false
	
	loans.remove_at(idx)
	AdvisorState.flag_agenda_event(AdvisorState.AGENDA_EARLY_LOAN_PAYOFF)
	AdvisorState.flag_agenda_event(AdvisorState.AGENDA_PAID_OFF_LOAN)
	print("[LoanState] Loan #%d repaid in full: £%.2f" % [loan_id, amount])
	loan_repaid.emit(loan_id)
	loans_updated.emit()
	return true

# === Per-turn processing ===
# Called explicitly by Production during PROCESS phase.
# Returns the total amount paid this turn.

func process_payments() -> float:
	_last_payments_turn = TurnManager.current_turn
	last_payment_total = 0.0
	if loans.is_empty():
		return 0.0
	
	var loans_to_remove: Array = []
	
	for loan in loans:
		# Grace loans: interest-free, no payments, until grace expires — then convert
		# to a normal amortised loan (principal + interest over LOAN_TERM_TURNS).
		if int(loan.get("grace_remaining", 0)) > 0:
			loan.grace_remaining = int(loan.grace_remaining) - 1
			loan.turns_remaining = int(loan.turns_remaining) - 1
			if int(loan.grace_remaining) == 0:
				# Standard loans banked the whole-life total at creation; the distressed-asset
				# grace loan (take_grace_loan) has no such total and is interest-free by design,
				# so it still converts at the plain rate.
				var g_rate: float = float(loan.get("interest_rate", EconomyConfig.LOAN_INTEREST_RATE))
				loan.principal_remaining = float(loan.get("total_repayment",
					float(loan.principal_initial) * (1.0 + g_rate)))
				loan.payment_per_turn = float(loan.principal_remaining) / float(EconomyConfig.LOAN_TERM_TURNS)
				loan.turns_remaining = EconomyConfig.LOAN_TERM_TURNS
			continue
		var pay: float = min(loan.payment_per_turn, loan.principal_remaining)
		MatchState.add_money(-pay)
		loan.principal_remaining -= pay
		# Track interest portion (approximate split; payment is fixed per turn)
		var loan_rate: float = float(loan.get("interest_rate", EconomyConfig.LOAN_INTEREST_RATE))
		var interest_portion: float = pay * (loan_rate / (1.0 + loan_rate))
		loan.interest_paid += interest_portion
		loan.turns_remaining -= 1
		last_payment_total += pay
		
		if loan.principal_remaining <= 0.001 or loan.turns_remaining <= 0:
			loans_to_remove.append(loan.id)
			AdvisorState.flag_agenda_event(AdvisorState.AGENDA_PAID_OFF_LOAN)
	
	# Clean up paid-off loans
	for loan_id in loans_to_remove:
		var idx: int = _find_loan_index(loan_id)
		if idx != -1:
			loans.remove_at(idx)
			print("[LoanState] Loan #%d paid off (term ended)" % loan_id)
			loan_repaid.emit(loan_id)
	
	if last_payment_total > 0:
		payment_made.emit(last_payment_total)
	
	if not loans_to_remove.is_empty():
		loans_updated.emit()
	
	# Bankruptcy check
	if MatchState.money < EconomyConfig.BANKRUPTCY_FLOOR:
		bankruptcy_warning.emit(MatchState.money, EconomyConfig.BANKRUPTCY_FLOOR)
		print("[BANKRUPTCY] Money £%.2f below floor £%.2f" % [
			MatchState.money, EconomyConfig.BANKRUPTCY_FLOOR
		])
	
	return last_payment_total

# === Transit credit ===

func transit_credit_available() -> bool:
	return str(MatchState.ruleset.get("logistics_model", "")) == "middleman_v1"

func set_transit_credit_enabled(enabled: bool) -> void:
	transit_credit_enabled = enabled
	loans_updated.emit()

## Per-turn interest on the balance: the standard rate over the standard loan term.
func transit_credit_rate_per_turn() -> float:
	return effective_loan_interest_rate() / float(EconomyConfig.LOAN_TERM_TURNS)

func begin_turn() -> void:
	transit_drawn_this_turn = 0.0
	transit_repaid_this_turn = 0.0

## Advance a plain market sale shipment's revenue now. Special orders settle on delivery
## terms of their own and are never advanced. Returns the amount advanced.
func advance_sale(shipment: Dictionary) -> float:
	if not transit_credit_available() or not transit_credit_enabled:
		return 0.0
	if str(shipment.get("special_order_id", "")) != "" or not bool(shipment.get("is_sale", false)):
		return 0.0
	var amount := float((shipment.get("sale_record", {}) as Dictionary).get("total_revenue", 0.0))
	if amount <= 0.0:
		return 0.0
	shipment["credit_advance"] = amount
	transit_credit_balance += amount
	transit_drawn_this_turn += amount
	MatchState.add_money(amount)
	loans_updated.emit()
	return amount

## The shipment reached its port and its revenue has been paid: repay its advance from it.
func settle_sale_advance(shipment: Dictionary) -> float:
	var advance := float(shipment.get("credit_advance", 0.0))
	if advance <= 0.0:
		return 0.0
	transit_credit_balance = maxf(0.0, transit_credit_balance - advance)
	transit_repaid_this_turn += advance
	MatchState.add_money(-advance)
	loans_updated.emit()
	return advance

func charge_transit_interest() -> float:
	var interest := transit_credit_balance * transit_credit_rate_per_turn()
	if interest <= 0.0:
		return 0.0
	MatchState.add_money(-interest)
	return interest

# === Queries ===

func total_outstanding() -> float:
	# Total principal_remaining across all active loans (what you'd pay to clear all loans now)
	var sum: float = 0.0
	for loan in loans:
		sum += loan.principal_remaining
	return sum

func total_per_turn_payment() -> float:
	var sum: float = 0.0
	for loan in loans:
		sum += loan.payment_per_turn
	return sum

# Attribute the most recently created loan to a specific building — called right after a
# construction-credit build places its site, so that build's loan shows in ITS economics rather
# than only in the company-wide total. Safe no-op when there is no loan or no instance to tag.
func tag_last_loan_building(instance_id: String) -> void:
	if instance_id == "" or loans.is_empty():
		return
	loans[loans.size() - 1]["building_instance"] = instance_id
	loans_updated.emit()

# The per-turn repayment (and turns left) of every active loan tied to this building — i.e. the
# construction loan(s) that financed its build. {per_turn, turns_left}; zero when none. General
# empire loans (building_instance == "") are deliberately excluded: they are not this building's cost.
func building_loan_repayment(instance_id: String) -> Dictionary:
	var per_turn: float = 0.0
	var turns_left: int = 0
	if instance_id != "":
		for loan in loans:
			if str(loan.get("building_instance", "")) == instance_id and float(loan.get("principal_remaining", 0.0)) > 0.0:
				per_turn += float(loan.get("payment_per_turn", 0.0))
				turns_left = maxi(turns_left, int(loan.get("turns_remaining", 0)))
	return {"per_turn": per_turn, "turns_left": turns_left}

func record_turn_economics(net_profit: float, revenue: float) -> void:
	# Called once per turn by Production with the company's retained net profit and
	# gross revenue. Feeds the rolling average that scales borrowing capacity.
	_profit_history.append(net_profit)
	_revenue_history.append(revenue)
	var window: int = EconomyConfig.LOAN_PROFIT_WINDOW
	while _profit_history.size() > window:
		_profit_history.pop_front()
	while _revenue_history.size() > window:
		_revenue_history.pop_front()

const BuildingPrice := preload("res://scripts/building_price.gd")

# Collateral: what the player's plant is worth to a lender = the SALE value of every
# player building (BuildingPrice.sale_price — the same deterministic, level-aware
# valuation the building market lists at), summed.
func collateral_value() -> float:
	var total: float = 0.0
	for b in BuildingState.buildings.values():
		if not BuildingState.is_player_owned(b):
			continue
		total += float(BuildingPrice.sale_price(b))
	return total

# Loan-to-value on that collateral: 0.75, lifted to 1.0 by a seated CFO or Chief
# Investment (the expansion/capex seat). The two don't stack — either presence maxes it.
func collateral_ltv() -> float:
	var has_expander := AdvisorState.get_advisor_in_seat("cfo") != "" \
		or AdvisorState.get_advisor_in_seat("chief_investment") != ""
	return EconomyConfig.LOAN_COLLATERAL_LTV_MAX if has_expander else EconomyConfig.LOAN_COLLATERAL_LTV_BASE

func capacity_total() -> float:
	# Total borrowing capacity (initial principal you may have outstanding at once) =
	# CASHFLOW leg + COLLATERAL leg.
	#
	# Cashflow leg: starts at LOAN_BASE_CAPACITY and grows so the per-turn loan
	# repayment of a fully-drawn facility stays within recent profit plus a slice of
	# revenue:
	#   serviceable/turn = max(0, avg_profit_5) + REVENUE_BUFFER * avg_revenue_5
	#   per-turn payment per £1 borrowed = (1 + INTEREST) / TERM   (amortised)
	#   capacity = serviceable / payment_rate
	# The amortised payment (not bare interest) is the bar, so the "paid off in
	# ~40 turns" affordance is baked in: debt service can exceed pure interest while
	# the principal is whittled down over the term.
	#
	# Collateral leg (2026-07-08, owner-requested forgiveness): LTV x plant sale value.
	# The PROFIT GATE below still zeroes the cashflow leg for a loss-making firm —
	# revenue alone must never unlock credit — but a firm with real assets can now
	# borrow against them through a trough instead of spiralling on £0 headroom.
	var base: float = EconomyConfig.LOAN_BASE_CAPACITY
	var collateral: float = collateral_ltv() * collateral_value()
	if _profit_history.is_empty():
		return base + collateral
	var avg_profit: float = _avg(_profit_history)
	if avg_profit <= 0.0:
		return base + collateral
	var avg_revenue: float = _avg(_revenue_history)
	var serviceable: float = avg_profit + EconomyConfig.LOAN_REVENUE_BUFFER * maxf(0.0, avg_revenue)
	var payment_rate: float = (1.0 + EconomyConfig.LOAN_INTEREST_RATE) / float(EconomyConfig.LOAN_TERM_TURNS)
	var scaled: float = serviceable / payment_rate
	return maxf(base, scaled) + collateral

func available_capacity() -> float:
	# Headroom = dynamic total capacity minus initial principal of active loans.
	# Once you fully repay a loan, its initial principal returns to capacity.
	var initial_outstanding: float = 0.0
	for loan in loans:
		initial_outstanding += loan.principal_initial
	return capacity_total() - initial_outstanding

func _avg(arr: Array) -> float:
	if arr.is_empty():
		return 0.0
	var sum: float = 0.0
	for v in arr:
		sum += float(v)
	return sum / float(arr.size())

# === Save/load (orchestrated by the SaveLoad autoload; docs/save_load_spec.md) ===

func export_state() -> Dictionary:
	return {
		"loans": loans.duplicate(true),
		"next_loan_id": _next_loan_id,
		# The rolling windows drive borrowing capacity, so they are part of the save.
		"profit_history": _profit_history.duplicate(),
		"revenue_history": _revenue_history.duplicate(),
		"transit_credit": {"enabled": transit_credit_enabled, "balance": transit_credit_balance},
	}

func import_state(d: Dictionary) -> void:
	_last_payments_turn = -1
	# Silent: SaveLoad emits loans_updated once after every system imports.
	loans = (d.get("loans", []) as Array).duplicate(true)
	_next_loan_id = int(d.get("next_loan_id", 1))
	_profit_history = (d.get("profit_history", []) as Array).duplicate()
	_revenue_history = (d.get("revenue_history", []) as Array).duplicate()
	last_payment_total = 0.0
	var transit: Dictionary = d.get("transit_credit", {})
	transit_credit_enabled = bool(transit.get("enabled", true))
	transit_credit_balance = float(transit.get("balance", 0.0))
	begin_turn()

# === Helpers ===

func _find_loan_index(loan_id: int) -> int:
	for i in loans.size():
		if loans[i].id == loan_id:
			return i
	return -1
