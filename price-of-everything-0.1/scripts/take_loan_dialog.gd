extends PanelContainer

signal loan_confirmed(amount: float)
signal cancelled

@onready var amount_slider: HSlider = $MarginContainer/VBoxContainer/AmountRow/AmountSlider
@onready var amount_label: Label = $MarginContainer/VBoxContainer/AmountRow/AmountLabel
@onready var capacity_label: Label = $MarginContainer/VBoxContainer/CapacityLabel
@onready var term_label: Label = $MarginContainer/VBoxContainer/PreviewVBox/TermLabel
@onready var total_repay_label: Label = $MarginContainer/VBoxContainer/PreviewVBox/TotalRepayLabel
@onready var interest_label: Label = $MarginContainer/VBoxContainer/PreviewVBox/InterestLabel
@onready var per_turn_label: Label = $MarginContainer/VBoxContainer/PreviewVBox/PerTurnLabel
@onready var cancel_button: Button = $MarginContainer/VBoxContainer/ButtonsRow/CancelButton
@onready var confirm_button: Button = $MarginContainer/VBoxContainer/ButtonsRow/ConfirmButton

func _ready() -> void:
	amount_slider.value_changed.connect(_on_amount_changed)
	cancel_button.pressed.connect(_on_cancel)
	confirm_button.pressed.connect(_on_confirm)

func open() -> void:
	var capacity: float = LoanState.available_capacity()
	if capacity < 1.0:
		# Shouldn't happen if button was disabled, but guard anyway
		_on_cancel()
		return
	
	amount_slider.max_value = capacity
	amount_slider.value = min(10.0, capacity)
	capacity_label.text = "Available capacity: £%.2f" % capacity
	term_label.text = "Term: %d turns" % EconomyConfig.LOAN_TERM_TURNS
	_refresh_preview(amount_slider.value)
	show()

func _on_amount_changed(value: float) -> void:
	_refresh_preview(value)

func _refresh_preview(amount: float) -> void:
	amount_label.text = "£%.0f" % amount
	var total_repay: float = amount * (1.0 + LoanState.effective_loan_interest_rate())
	var interest: float = total_repay - amount
	var per_turn: float = total_repay / float(EconomyConfig.LOAN_TERM_TURNS)
	total_repay_label.text = "Total to repay: £%.2f" % total_repay
	interest_label.text = "Interest cost: £%.2f" % interest
	per_turn_label.text = "Per-turn payment: £%.4f" % per_turn

func _on_cancel() -> void:
	hide()
	cancelled.emit()

func _on_confirm() -> void:
	var amount: float = amount_slider.value
	hide()
	loan_confirmed.emit(amount)
