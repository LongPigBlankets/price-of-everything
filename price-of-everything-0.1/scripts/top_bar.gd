extends PanelContainer

@onready var money_widget: Button = $MarginContainer/HBoxContainer/MoneyWidget

signal money_widget_clicked
## The top-bar victory score widget was clicked (opens the Victory panel).
signal victory_widget_clicked

const FLASH_RED := Color(0.9, 0.2, 0.2)

var _flashing := false

func _ready() -> void:
	money_widget.pressed.connect(_on_money_clicked)
	MatchState.money_changed.connect(_on_money_changed)
	MatchState.build_rejected_no_funds.connect(_on_build_rejected_no_funds)
	_refresh_money_display(MatchState.money)
	_add_victory_widget()
	_add_save_button()
	_add_notification_bell()

func _add_victory_widget() -> void:
	# The victory score widget sits next to MoneyWidget at the left of the top-bar
	# HBox (peer to the Save button + NotificationBell). Click opens the Victory panel.
	var widget: Control = load("res://scripts/victory_widget.gd").new()
	widget.name = "VictoryWidget"
	widget.clicked.connect(func() -> void: victory_widget_clicked.emit())
	money_widget.get_parent().add_child(widget)

func _add_notification_bell() -> void:
	# The bell sits at the right end of the top-bar HBox, just inside the money
	# row's container — it's a peer to MoneyWidget and the (programmatic) Save
	# button. EventScheduler signals drive its colour, badge and dropdown.
	var bell: Control = load("res://scripts/notification_bell.gd").new()
	bell.name = "NotificationBell"
	money_widget.get_parent().add_child(bell)

func _add_save_button() -> void:
	# Quicksave to the "quicksave" slot (named saves via the debug terminal /
	# the main menu's Load Game lists both). Saving is DECIDE-phase-only;
	# SaveLoad returns the reason when it refuses and we toast it either way.
	var save_button := Button.new()
	save_button.text = "Save"
	save_button.tooltip_text = "Save the game (quicksave slot)"
	save_button.pressed.connect(_on_save_pressed)
	money_widget.get_parent().add_child(save_button)

func _on_save_pressed() -> void:
	var err: String = SaveLoad.save_slot("quicksave")
	if err == "":
		MatchState.request_toast("Game saved (quicksave).", "success")
	else:
		MatchState.request_toast("Could not save: %s" % err, "warning")

func _on_money_changed(new_amount: float) -> void:
	_refresh_money_display(new_amount)

func _on_build_rejected_no_funds(_message: String) -> void:
	flash_red()

func _base_money_color() -> Color:
	var amount: float = MatchState.money
	if amount < 0:
		return FLASH_RED
	elif amount < 10:
		return Color(1.0, 0.6, 0.2)
	return Color(0.995234, 0.930806, 0.763265)

func _refresh_money_display(amount: float) -> void:
	money_widget.text = " £%.2f" % amount
	if not _flashing:
		money_widget.add_theme_color_override("font_color", _base_money_color())

func _set_money_color(c: Color) -> void:
	money_widget.add_theme_color_override("font_color", c)

func flash_red() -> void:
	# Flash twice: base→red→base→red→base, 0.2s each leg. Re-triggering while
	# flashing is ignored (the sequence completes once and does not loop).
	if _flashing:
		return
	_flashing = true
	var base := _base_money_color()
	var tween := create_tween()
	tween.tween_method(_set_money_color, base, FLASH_RED, 0.2)
	tween.tween_method(_set_money_color, FLASH_RED, base, 0.2)
	tween.tween_method(_set_money_color, base, FLASH_RED, 0.2)
	tween.tween_method(_set_money_color, FLASH_RED, base, 0.2)
	tween.tween_callback(func() -> void:
		_flashing = false
		_set_money_color(_base_money_color())
	)

func _on_money_clicked() -> void:
	money_widget_clicked.emit()
