extends PanelContainer
## A modal confirmation drawn INSIDE the editor's canvas rather than as a `ConfirmationDialog`.
##
## EDITOR-ONLY (see the header of `map_editor.gd`).
##
## Godot's dialog is a Window, and a Window brings its own focus handling and does not appear
## in a viewport capture — which would put the one prompt that guards destructive work outside
## the reach of the harness that tests everything else here. A Control is testable, captures
## with the rest of the frame, and cannot steal focus from the editor.

signal confirmed
signal cancelled

const BG := Color(0.06, 0.08, 0.12, 0.97)
const EDGE := Color(0.85, 0.55, 0.35, 0.9)

var _message: Label


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = BG
	style.border_color = EDGE
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(18)
	add_theme_stylebox_override("panel", style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	add_child(column)

	_message = Label.new()
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_message)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)

	var cancel := Button.new()
	cancel.text = "Cancel   (Esc)"
	cancel.custom_minimum_size = Vector2(140, 32)
	cancel.pressed.connect(func() -> void: close(); cancelled.emit())
	row.add_child(cancel)

	var confirm := Button.new()
	confirm.text = "Delete   (Enter)"
	confirm.custom_minimum_size = Vector2(140, 32)
	confirm.pressed.connect(func() -> void: close(); confirmed.emit())
	row.add_child(confirm)

	hide()


func ask(text: String) -> void:
	_message.text = text
	show()


func close() -> void:
	hide()


func is_open() -> bool:
	return visible
