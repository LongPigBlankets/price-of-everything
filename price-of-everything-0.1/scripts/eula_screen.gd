extends Control
## First-launch agreement. The startup scene owns persistence and scene changes.
## Buttons stay outside the scrolling document and cannot be scrolled offscreen.

signal accept_requested
signal close_requested

const Agreement := preload("res://scripts/demo_eula.gd")
const CreamKey := preload("res://scripts/ds2/cream_key.gd")

var document: RichTextLabel
var accept_button: Button
var close_button: Button
var _error: Label
var _panel: PanelContainer
var _layout_queued: bool = false


func _ready() -> void:
	theme = DS.theme
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	resized.connect(_queue_layout)
	_panel.minimum_size_changed.connect(_queue_layout)
	_queue_layout()
	document.grab_focus.call_deferred()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_requested.emit()


func show_save_error() -> void:
	_error.text = "Your acceptance could not be saved. Please try again or close the game."
	_error.show()
	accept_button.set_busy(false)


func _build() -> void:
	var background := ColorRect.new()
	background.color = DS.PALETTE["BG"]
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	_panel = PanelContainer.new()
	_panel.name = "AgreementPanel"
	add_child(_panel)
	var column := VBoxContainer.new()
	column.name = "Content"
	column.add_theme_constant_override("separation", DS.SP["MD"])
	_panel.add_child(column)

	var title := Label.new()
	title.text = "Carbon and Capital — Demo Licence Agreement"
	title.theme_type_variation = &"Title"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(title)

	var instruction := Label.new()
	instruction.text = "Please read the terms below. Accept terms to continue, or close the game."
	instruction.theme_type_variation = &"Body"
	instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(instruction)

	document = RichTextLabel.new()
	document.name = "AgreementText"
	document.theme_type_variation = &"LegalDocument"
	document.bbcode_enabled = false
	document.text = Agreement.text()
	document.selection_enabled = true
	document.scroll_active = true
	document.scroll_following = false
	document.focus_mode = Control.FOCUS_ALL
	document.size_flags_vertical = Control.SIZE_EXPAND_FILL
	document.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(document)

	_error = Label.new()
	_error.name = "AcceptanceError"
	_error.theme_type_variation = &"Body"
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.hide()
	column.add_child(_error)

	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", DS.SP["LG"])
	column.add_child(actions)
	close_button = CreamKey.make("CloseGame", "Reject and close game", "", 0.0)
	close_button.set("title_ink", CreamKey.RED_INK)
	close_button.focus_mode = Control.FOCUS_ALL
	close_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_button.pressed.connect(func() -> void: close_requested.emit())
	actions.add_child(close_button)
	accept_button = CreamKey.make("AcceptTerms", "Accept terms", "", 0.0)
	accept_button.focus_mode = Control.FOCUS_ALL
	accept_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	accept_button.set_spent(document.text.is_empty())
	accept_button.pressed.connect(_on_accept_pressed)
	actions.add_child(accept_button)
	if document.text.is_empty():
		_error.text = "The licence agreement could not be loaded. Please close the game and reinstall the demo."
		_error.show()


func _on_accept_pressed() -> void:
	if accept_button.disabled:
		return
	accept_button.set_busy(true)
	accept_requested.emit()


func _queue_layout() -> void:
	if _layout_queued:
		return
	_layout_queued = true
	_layout.call_deferred()


func _layout() -> void:
	_layout_queued = false
	if _panel == null:
		return
	var margin := float(DS.SP["XL"])
	var available := (size - Vector2.ONE * margin * 2.0).max(Vector2.ONE)
	_panel.size = Vector2(minf(1080.0, available.x), minf(880.0, available.y))
	_panel.position = (size - _panel.size) * 0.5
