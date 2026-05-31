extends PanelContainer

@onready var money_widget: Button = $MarginContainer/HBoxContainer/MoneyWidget

signal money_widget_clicked

func _ready() -> void:
	money_widget.pressed.connect(_on_money_clicked)
	MatchState.money_changed.connect(_on_money_changed)
	_refresh_money_display(MatchState.money)

func _on_money_changed(new_amount: float) -> void:
	_refresh_money_display(new_amount)

func _refresh_money_display(amount: float) -> void:
	money_widget.text = " £%.2f" % amount
	if amount < 0:
		money_widget.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))
	elif amount < 10:
		money_widget.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
	else:
		money_widget.add_theme_color_override("font_color", Color(0.995234, 0.930806, 0.763265))

func _on_money_clicked() -> void:
	money_widget_clicked.emit()
