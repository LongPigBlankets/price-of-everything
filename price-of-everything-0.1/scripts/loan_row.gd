extends PanelContainer

signal repay_pressed(loan_id: int)

@onready var header_label: Label = $MarginContainer/HBoxContainer/InfoVBox/HeaderLabel
@onready var detail_label: Label = $MarginContainer/HBoxContainer/InfoVBox/DetailLabel
@onready var repay_button: Button = $MarginContainer/HBoxContainer/InfoVBox/RepayButton

var loan_id: int = 0

func setup(loan: Dictionary) -> void:
	loan_id = loan.id
	header_label.text = "Loan #%d: £%.2f borrowed" % [loan.id, loan.principal_initial]
	detail_label.text = "£%.2f remaining · %d turns · £%.2f/turn" % [
		loan.principal_remaining,
		loan.turns_remaining,
		loan.payment_per_turn
	]
	repay_button.text = "Repay £%.2f" % loan.principal_remaining
	repay_button.pressed.connect(_on_repay_pressed)

func _on_repay_pressed() -> void:
	repay_pressed.emit(loan_id)
