extends Control
## DS-themed confirmation shown the first time a player enables "Sell all Surplus"
## on a tile's stockpile. Mirrors buy_building_dialog.gd's modal shell (full-rect
## scrim + centred Card). Emits `confirmed(dont_ask_again)` on commit, else
## `cancelled` (so the caller can revert the checkbox).

signal confirmed(dont_ask_again: bool)
signal cancelled

const UIHelpers := preload("res://scripts/ui_helpers.gd")

const BODY_TEXT := "Enabling 'Sell all Surplus' will sell any units of all goods on this tile which are not reserved for recipes. This will self-adjust with every new building you add."

var _dont_ask: CheckBox

func _ready() -> void:
	_build_shell()
	visible = false

func open() -> void:
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
	card.custom_minimum_size = Vector2(480, 0)
	center.add_child(card)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", DS.SP.MD)
	card.add_child(content)

	var title := Label.new()
	title.text = "Sell all Surplus"
	title.theme_type_variation = "Section"
	content.add_child(title)

	var message := Label.new()
	message.text = BODY_TEXT
	message.theme_type_variation = "Body"
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(message)

	# "Do not show again for other tiles" tickbox on its own row.
	_dont_ask = UIHelpers.make_custom_checkbox()
	content.add_child(UIHelpers.make_setting_row("Do not show again for other tiles", _dont_ask))

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", DS.SP.SM)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(_on_cancel)
	buttons.add_child(cancel)
	var confirm := Button.new()
	confirm.text = "Confirm"
	confirm.theme_type_variation = "Primary"
	confirm.focus_mode = Control.FOCUS_NONE
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm.pressed.connect(_on_confirm)
	buttons.add_child(confirm)
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

func _on_confirm() -> void:
	var dont_ask := _dont_ask.button_pressed
	close()
	confirmed.emit(dont_ask)
