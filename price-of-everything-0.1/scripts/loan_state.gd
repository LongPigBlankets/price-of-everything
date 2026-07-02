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
	# Standard 36-turn loan at the config rate (minus any CFO discount).
	if amount <= 0.0 or amount > available_capacity():
		return false
	return _create_loan(amount, effective_loan_interest_rate(), EconomyConfig.LOAN_TERM_TURNS)

func take_construction_loan(amount: float) -> bool:
	# 10-turn, 5% build loan. Respects the same borrowing capacity as any other loan.
	if amount <= 0.0 or amount > available_capacity():
		return false
	return _create_loan(amount, CONSTRUCTION_LOAN_RATE, CONSTRUCTION_LOAN_TERM)

# Shared loan creation: bakes the (rate, term) into the amortisation and disburses
# the principal. Per-loan rate/term are stored so processing stays accurate even when
# multiple loans of different terms coexist.
func _create_loan(amount: float, rate: float, term: int) -> bool:
	var total_repayment: float = amount * (1.0 + rate)
	var per_turn: float = total_repayment / float(term)
	var loan: Dictionary = {
		"id": _next_loan_id,
		"principal_initial": amount,
		"principal_remaining": total_repayment,
		"payment_per_turn": per_turn,
		"turns_remaining": term,
		"interest_paid": 0.0,
		"interest_rate": rate,
	}
	_next_loan_id += 1
	loans.append(loan)
	MatchState.add_money(amount)   # disburse principal
	print("[LoanState] Loan #%d taken: £%.2f (£%.4f/turn for %d turns @ %.1f%%, total £%.2f)" % [
		loan.id, amount, per_turn, term, rate * 100.0, total_repayment
	])
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
	print("[LoanState] Loan #%d repaid in full: £%.2f" % [loan_id, amount])
	loan_repaid.emit(loan_id)
	loans_updated.emit()
	return true

# === Per-turn processing ===
# Called explicitly by Production during PROCESS phase.
# Returns the total amount paid this turn.

func process_payments() -> float:
	last_payment_total = 0.0
	if loans.is_empty():
		return 0.0
	
	var loans_to_remove: Array = []
	
	for loan in loans:
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

func capacity_total() -> float:
	# Total borrowing capacity (initial principal you may have outstanding at once).
	# Starts at LOAN_BASE_CAPACITY and grows so the per-turn loan repayment of a
	# fully-drawn facility stays within recent profit plus a slice of revenue:
	#   serviceable/turn = max(0, avg_profit_5) + REVENUE_BUFFER * avg_revenue_5
	#   per-turn payment per £1 borrowed = (1 + INTEREST) / TERM   (amortised)
	#   capacity = serviceable / payment_rate
	# The amortised payment (not bare interest) is the bar, so the "paid off in
	# ~40 turns" affordance is baked in: debt service can exceed pure interest while
	# the principal is whittled down over the term.
	var base: float = EconomyConfig.LOAN_BASE_CAPACITY
	if _profit_history.is_empty():
		return base
	# PROFIT GATE: until the company is actually making money on a rolling basis,
	# borrowing is limited to the base floor. Revenue alone must not unlock credit —
	# a loss-making firm with strong turnover is still a bad lend, and without this
	# gate "10% of revenue" amplified over the loan term hands a brand-new, still
	# unprofitable business a four-figure credit line.
	var avg_profit: float = _avg(_profit_history)
	if avg_profit <= 0.0:
		return base
	# Serviceable debt service = genuinely-available rolling profit + a small slice of
	# revenue (LOAN_REVENUE_BUFFER). The profit gate above keeps revenue from unlocking
	# credit on its own, so the slice is a modest top-up, not the driver.
	var avg_revenue: float = _avg(_revenue_history)
	var serviceable: float = avg_profit + EconomyConfig.LOAN_REVENUE_BUFFER * maxf(0.0, avg_revenue)
	var payment_rate: float = (1.0 + EconomyConfig.LOAN_INTEREST_RATE) / float(EconomyConfig.LOAN_TERM_TURNS)
	var scaled: float = serviceable / payment_rate
	return maxf(base, scaled)

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
	}

func import_state(d: Dictionary) -> void:
	# Silent: SaveLoad emits loans_updated once after every system imports.
	loans = (d.get("loans", []) as Array).duplicate(true)
	_next_loan_id = int(d.get("next_loan_id", 1))
	_profit_history = (d.get("profit_history", []) as Array).duplicate()
	_revenue_history = (d.get("revenue_history", []) as Array).duplicate()
	last_payment_total = 0.0

# === Helpers ===

func _find_loan_index(loan_id: int) -> int:
	for i in loans.size():
		if loans[i].id == loan_id:
			return i
	return -1
