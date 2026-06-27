extends Control
## Simple DS-themed "confirm purchase" dialog for buying an NPC building from the market.
## Built in code from the DS design system (theme variations + DS.SP tokens — no ad-hoc styling),
## mirroring upgrade_dialog.gd's modal shell (full-rect scrim + centred Card). One instance is
## reused across buildings via open(). Emits `confirmed(dont_ask_again)` on commit, else `cancelled`.

signal confirmed(dont_ask_again: bool)
signal cancelled

const UIHelpers := preload("res://scripts/ui_helpers.gd")

var _message: Label
var _dont_ask: CheckBox
var _buy_btn: Button

func _ready() -> void:
	_build_shell()
	visible = false

func open(building_name: String, price: int) -> void:
	_message.text = "Are you sure you want to buy %s?" % building_name
	_buy_btn.text = "Buy for £%d" % price
	_dont_ask.set_pressed_no_signal(false)
	visible = true
	move_to_front()

func close() -> void:
	visible = false

func _build_shell() -> void:
	theme = DS.theme
	# Lives directly under a CanvasLayer, so FULL_RECT resolves to nothing — size to the viewport.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_fit_to_viewport()
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_fit_to_viewport):
		vp.size_changed.connect(_fit_to_viewport)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var scrim := ColorRect.new()
	scrim.color = Color(0.0, 0.0, 0.0, 0.55)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.gui_input.connect(_on_scrim_input)
	add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	# Default PanelContainer = the DS base panel (navy + cream outline, rounded corners).
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(460, 0)
	center.add_child(card)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", DS.SP.MD)
	card.add_child(content)

	var title := Label.new()
	title.text = "Confirm purchase"
	title.theme_type_variation = "Section"
	content.add_child(title)

	_message = Label.new()
	_message.theme_type_variation = "Body"
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_message)

	# "Do not show again" tickbox on its own row (label left, custom tickbox right).
	_dont_ask = UIHelpers.make_custom_checkbox()
	content.add_child(UIHelpers.make_setting_row("Do not show again", _dont_ask))

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", DS.SP.SM)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(_on_cancel)
	buttons.add_child(cancel)
	_buy_btn = Button.new()
	_buy_btn.theme_type_variation = "Primary"
	_buy_btn.focus_mode = Control.FOCUS_NONE
	_buy_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_buy_btn.pressed.connect(_on_buy)
	buttons.add_child(_buy_btn)
	content.add_child(buttons)

func _fit_to_viewport() -> void:
	var vp := get_viewport()
	if vp != null:
		size = vp.get_visible_rect().size
		position = Vector2.ZERO

func _on_scrim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_on_cancel()

func _on_cancel() -> void:
	close()
	cancelled.emit()

func _on_buy() -> void:
	var dont_ask := _dont_ask.button_pressed
	close()
	confirmed.emit(dont_ask)
