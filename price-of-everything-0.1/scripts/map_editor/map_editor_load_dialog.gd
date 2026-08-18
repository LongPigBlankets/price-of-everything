extends PanelContainer
## Picks a saved map to open.
##
## EDITOR-ONLY (see the header of `map_editor.gd`). In-canvas for the same reason as the
## other dialogs: a Window sits outside viewport captures and brings its own focus handling.
##
## Loading also makes the chosen map ACTIVE, matching save. The alternative — editing one
## map while the game renders another — is a trap that costs an hour before anyone works out
## why their changes are not showing up.

signal chosen(name: String)
signal cancelled

const AuthoredMap := preload("res://scripts/authored_map.gd")

const BG := Color(0.06, 0.08, 0.12, 0.97)
const EDGE := Color(0.45, 0.85, 0.6, 0.85)
const MUTED := Color(0.72, 0.78, 0.82)

var _list: VBoxContainer
var _note: Label


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = BG
	style.border_color = EDGE
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(18)
	add_theme_stylebox_override("panel", style)
	custom_minimum_size = Vector2(420, 0)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)

	var title := Label.new()
	title.text = "Open a map"
	column.add_child(title)

	_note = Label.new()
	_note.add_theme_font_size_override("font_size", 11)
	_note.add_theme_color_override("font_color", MUTED)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_note)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	column.add_child(_list)

	var cancel := Button.new()
	cancel.text = "Cancel   (Esc)"
	cancel.custom_minimum_size = Vector2(0, 32)
	cancel.pressed.connect(func() -> void: close(); cancelled.emit())
	column.add_child(cancel)

	hide()


## `dirty` warns that opening will discard unsaved work — the list is rebuilt each time
## because a document may have been written since the dialog was last opened.
func open(current: String, dirty: bool) -> void:
	for child in _list.get_children():
		child.queue_free()
	var names := AuthoredMap.list_documents()
	if names.is_empty():
		_note.text = "No saved maps yet — draw something and use Save as."
	elif dirty:
		_note.text = "UNSAVED CHANGES will be lost. Save first if you want to keep them."
	else:
		_note.text = "Opening a map also makes it the one the game renders."
	for name in names:
		var button := Button.new()
		button.text = ("●  %s   (open)" % name) if name == current else ("○  %s" % name)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 30)
		var picked := name
		button.pressed.connect(func() -> void: close(); chosen.emit(picked))
		_list.add_child(button)
	show()


func close() -> void:
	hide()


func is_open() -> bool:
	return visible
