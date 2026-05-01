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

signal loans_updated
signal loan_taken(loan: Dictionary)
signal loan_repaid(loan_id: int)
signal payment_made(total_amount: float)
signal bankruptcy_warning(money: float, floor: float)

# === Public API ===

func take_loan(amount: float) -> bool:
	# Returns true if loan was created, false otherwise.
	if amount <= 0.0:
		return false
	if amount > available_capacity():
		return false
	
	var total_repayment: float = amount * (1.0 + EconomyConfig.LOAN_INTEREST_RATE)
	var per_turn: float = total_repayment / float(EconomyConfig.LOAN_TERM_TURNS)
	
	var loan: Dictionary = {
		"id": _next_loan_id,
		"principal_initial": amount,
		"principal_remaining": total_repayment,
		"payment_per_turn": per_turn,
		"turns_remaining": EconomyConfig.LOAN_TERM_TURNS,
		"interest_paid": 0.0,
	}
	_next_loan_id += 1
	loans.append(loan)
	
	# Disburse principal to player
	MatchState.add_money(amount)
	
	print("[LoanState] Loan #%d taken: £%.2f (£%.4f/turn for %d turns, total £%.2f)" % [
		loan.id, amount, per_turn, EconomyConfig.LOAN_TERM_TURNS, total_repayment
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
		var interest_portion: float = pay * (EconomyConfig.LOAN_INTEREST_RATE / (1.0 + EconomyConfig.LOAN_INTEREST_RATE))
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

func available_capacity() -> float:
	# Capacity = MAX - sum of initial principal of active loans.
	# Once you fully repay a loan, its initial principal returns to capacity.
	var initial_outstanding: float = 0.0
	for loan in loans:
		initial_outstanding += loan.principal_initial
	return EconomyConfig.LOAN_MAX_CAPACITY - initial_outstanding

# === Helpers ===

func _find_loan_index(loan_id: int) -> int:
	for i in loans.size():
		if loans[i].id == loan_id:
			return i
	return -1
