extends PanelContainer
## "Save as" — names a document.
##
## EDITOR-ONLY (see the header of `map_editor.gd`). An in-canvas Control for the same reason
## as the confirmation: a Window would sit outside viewport captures and bring its own focus
## handling, and this is a step the harness must be able to drive.
##
## Names are VALIDATED, not sanitised. Silently turning "coast v2!" into "coast_v2" means the
## name in the editor is not the name on disk, and the designer goes looking for a file that
## is not there.

signal accepted(name: String)
signal cancelled

const AuthoredMap := preload("res://scripts/authored_map.gd")

const BG := Color(0.06, 0.08, 0.12, 0.97)
const EDGE := Color(0.45, 0.85, 0.6, 0.85)
const WARN := Color(1.0, 0.62, 0.45)

var _field: LineEdit
var _note: Label
var _existing: Label


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
	title.text = "Save map as"
	column.add_child(title)

	_field = LineEdit.new()
	_field.placeholder_text = "e.g. capital-draft"
	_field.text_changed.connect(func(_t: String) -> void: _revalidate())
	_field.text_submitted.connect(func(_t: String) -> void: _accept())
	column.add_child(_field)

	_note = Label.new()
	_note.add_theme_font_size_override("font_size", 11)
	column.add_child(_note)

	_existing = Label.new()
	_existing.add_theme_font_size_override("font_size", 11)
	_existing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_existing)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)

	var cancel := Button.new()
	cancel.text = "Cancel   (Esc)"
	cancel.custom_minimum_size = Vector2(150, 32)
	cancel.pressed.connect(func() -> void: close(); cancelled.emit())
	row.add_child(cancel)

	var save := Button.new()
	save.text = "Save   (Enter)"
	save.custom_minimum_size = Vector2(150, 32)
	save.pressed.connect(_accept)
	row.add_child(save)

	hide()


func open(current: String) -> void:
	_field.text = current
	var names := AuthoredMap.list_documents()
	_existing.text = ("On disk: %s" % ", ".join(names)) if not names.is_empty() \
		else "No saved maps yet."
	_revalidate()
	show()
	# Deferred: the field cannot take focus in the same frame it becomes visible.
	_field.call_deferred("grab_focus")
	_field.call_deferred("select_all")


func close() -> void:
	hide()


func is_open() -> bool:
	return visible


## Accept from the button, from Enter in the field, or from the editor's key handling.
func accept() -> void:
	_accept()


func _accept() -> void:
	var name := _field.text.strip_edges()
	if not AuthoredMap.is_valid_name(name):
		_revalidate()
		return
	close()
	accepted.emit(name)


func _revalidate() -> void:
	var name := _field.text.strip_edges()
	if name == "":
		_note.text = "Enter a name."
		_note.add_theme_color_override("font_color", WARN)
		return
	if not AuthoredMap.is_valid_name(name):
		_note.text = "Letters, numbers, spaces, - and _ only (max 48)."
		_note.add_theme_color_override("font_color", WARN)
		return
	var exists := AuthoredMap.list_documents().has(name)
	_note.text = ("Overwrites the existing '%s'." % name) if exists \
		else "Saves as %s.json and makes it the active map." % name
	_note.add_theme_color_override("font_color", WARN if exists else EDGE)
