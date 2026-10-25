extends "res://tests/test_base.gd"
const FEATURE := "ui"
const TopBar := preload("res://scripts/top_bar.gd")

func _test_payments_rise_at_the_first_grace_end() -> void:
	var saved: Array = LoanState.loans.duplicate(true)
	LoanState.loans = []
	_check(int(TopBar.next_grace_expiry().turn) == 0, "treasury loans: no loans, no grace expiry due")
	LoanState.loans = [
		{"id": 1, "principal_remaining": 100.0, "payment_per_turn": 5.0, "turns_remaining": 20, "total_repayment": 120.0, "grace_remaining": 0},
		{"id": 2, "principal_initial": 200.0, "principal_remaining": 200.0, "payment_per_turn": 0.0, "turns_remaining": 46, "grace_remaining": 10},
		{"id": 3, "principal_initial": 300.0, "principal_remaining": 300.0, "payment_per_turn": 0.0, "turns_remaining": 40, "grace_remaining": 4},
	]
	var expected := LoanState.repayment_turns(LoanState.loans[2]).x
	var expiry: Dictionary = TopBar.next_grace_expiry()
	_check(expected > 0 and int(expiry.turn) == expected and is_equal_approx(float(expiry.size), 300.0) and int(expiry.count) == 1,
		"treasury loans: the first grace period to end, its turn and the loan's size (%s)" % str(expiry))
	LoanState.loans = saved
