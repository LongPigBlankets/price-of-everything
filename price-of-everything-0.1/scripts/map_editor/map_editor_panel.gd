extends PanelContainer
## The editor's tool panel: what you are drawing with, what you can see, and what the last
## action did.
##
## EDITOR-ONLY (see the header of `map_editor.gd`).
##
## LAYOUT follows how often things are reached for. Tools and the road class are the whole
## job and stay open. Document actions — save, load, delete — are few, consequential and
## must never be behind a fold. Everything else (a dozen layer toggles, session commands)
## collapses, because a panel where the important controls scroll off the bottom is a panel
## that gets fought with.
##
## It OWNS no state. Every control reads from and writes to the editor through the callbacks
## handed in at build time, so the keyboard shortcuts and the buttons cannot drift apart:
## pressing R and clicking "Road pen" run the same line.

const MapEditorLayers := preload("res://scripts/map_editor/map_editor_layers.gd")

const WIDTH := 244.0
const BG := Color(0.05, 0.07, 0.10, 0.93)
const HEADING := Color(0.60, 0.95, 0.75)
const MUTED := Color(0.72, 0.78, 0.82)
const ACCENT := Color(0.98, 0.80, 0.45)

## `[key, label, shortcut]` — the shortcut text is shown, not bound here; the editor owns the
## keys so there is one source of truth for what a key does.
const TOOLS := [
	["pan", "Navigate", "V"],
	["road", "Road pen", "R"],
	["anchor", "Add anchor", "T"],
	["trace", "Freehand", "F"],
	["dots", "Connect dots", "C"],
	["upgrade", "Upgrade class", "U"],
	["select", "Select / delete", "X"],
]

const ROAD_CLASSES := [
	["major", "Major", "1"],
	["mid", "Mid", "2"],
	["minor", "Minor", "3"],
]

## Sections that start folded. Visibility is long and consulted occasionally; session
## commands are rare.
const FOLDED := {"Visibility": true, "Session": true}

var _editor: Node
var _layers: MapEditorLayers
var _tool_buttons: Dictionary = {}
var _class_buttons: Dictionary = {}
var _layer_buttons: Dictionary = {}
var _folds: Dictionary = {}
var _status: Label
var _hint: Label


func build(editor: Node, layers: MapEditorLayers) -> void:
	_editor = editor
	_layers = layers
	custom_minimum_size = Vector2(WIDTH, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = BG
	style.set_content_margin_all(12)
	add_theme_stylebox_override("panel", style)

	# Scrolls, because the folded sections can be opened all at once on a short window.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Without this the column collapses to its minimum inside the scroll container and every
	# button shrinks to its text — the ScrollContainer trap this project has hit before.
	column.custom_minimum_size = Vector2(WIDTH - 30.0, 0)
	scroll.add_child(column)

	column.add_child(_title("MAP EDITOR"))
	_hint = _caption("")
	column.add_child(_hint)

	column.add_child(_heading("Tool"))
	for entry in TOOLS:
		var key := str(entry[0])
		var button := _toggle_button("%s   (%s)" % [entry[1], entry[2]])
		button.pressed.connect(func() -> void: _editor.call("set_tool", key))
		_tool_buttons[key] = button
		column.add_child(button)

	column.add_child(_heading("Road class"))
	for entry in ROAD_CLASSES:
		var key := str(entry[0])
		var button := _toggle_button("%s   (%s)" % [entry[1], entry[2]])
		button.pressed.connect(func() -> void: _editor.call("set_road_class", key))
		_class_buttons[key] = button
		column.add_child(button)

	# ── Visibility, folded ──────────────────────────────────────────────────────
	var visibility := _fold(column, "Visibility")
	for entry in MapEditorLayers.LAYERS:
		var key := str(entry["key"])
		var button := _toggle_button(str(entry["label"]))
		button.pressed.connect(func() -> void:
			_layers.toggle(key)
			refresh())
		_layer_buttons[key] = button
		visibility.add_child(button)
	var grid := _toggle_button("Tile grid & ids   (G)")
	grid.pressed.connect(func() -> void: _editor.call("toggle_grid"))
	_layer_buttons["__grid"] = grid
	visibility.add_child(grid)

	# ── Session, folded ─────────────────────────────────────────────────────────
	var session := _fold(column, "Session")
	for entry in [["Undo   (Ctrl+Z)", "undo"], ["Redo   (Ctrl+Shift+Z)", "redo"],
			["Revert to saved   (F6)", "reload"], ["Back to menu   (Esc)", "leave"]]:
		var action := str(entry[1])
		var button := Button.new()
		button.text = str(entry[0])
		button.custom_minimum_size = Vector2(0, 26)
		button.pressed.connect(func() -> void: _editor.call("run_action", action))
		session.add_child(button)

	# ── Document actions, always open ───────────────────────────────────────────
	column.add_child(_heading("Map"))
	for entry in [["Save   (F5)", "save"], ["Save as…", "save_as"], ["Load…", "load"],
			["Delete selected   (Del)", "delete"]]:
		var action := str(entry[1])
		var button := Button.new()
		button.text = str(entry[0])
		button.custom_minimum_size = Vector2(0, 30)
		if action == "delete":
			button.add_theme_color_override("font_color", ACCENT)
		button.pressed.connect(func() -> void: _editor.call("run_action", action))
		column.add_child(button)

	_status = _caption("")
	_status.custom_minimum_size = Vector2(0, 46)
	column.add_child(_status)
	refresh()


## A collapsible section. Returns the container its contents go in.
func _fold(parent: Control, title: String) -> VBoxContainer:
	var header := Button.new()
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.custom_minimum_size = Vector2(0, 26)
	header.add_theme_color_override("font_color", MUTED)
	parent.add_child(header)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	body.visible = not bool(FOLDED.get(title, false))
	parent.add_child(body)

	_folds[title] = {"header": header, "body": body}
	header.pressed.connect(func() -> void:
		body.visible = not body.visible
		_paint_fold(title))
	_paint_fold(title)
	return body


func _paint_fold(title: String) -> void:
	var entry: Dictionary = _folds.get(title, {})
	if entry.is_empty():
		return
	var open: bool = (entry["body"] as Control).visible
	(entry["header"] as Button).text = "%s  %s" % ["▾" if open else "▸", title.to_upper()]


## Repaint the panel from the editor's state. Called after anything that could change it,
## rather than each control tracking its own truth.
func refresh() -> void:
	if _editor == null:
		return
	var tool_name := str(_editor.call("current_tool"))
	for key in _tool_buttons:
		_mark(_tool_buttons[key], str(key) == tool_name)
	var road_class := str(_editor.call("current_road_class"))
	var drawing := tool_name in ["road", "trace", "dots"]
	for key in _class_buttons:
		_mark(_class_buttons[key], str(key) == road_class)
		(_class_buttons[key] as Button).disabled = not drawing
	for key in _layer_buttons:
		if str(key) == "__grid":
			_mark(_layer_buttons[key], bool(_editor.call("grid_shown")))
		else:
			_mark(_layer_buttons[key], _layers.is_on(str(key)))
	match tool_name:
		"pan":
			_hint.text = "WASD or drag to pan · wheel or Q/E to zoom"
		"road":
			_hint.text = "Click a corner · drag for a curve · Enter ends · Bksp back"
		"anchor":
			_hint.text = "Click a road to add a point · drag it to curve both sides"
		"trace":
			_hint.text = "Press and drag to trace a line · it is simplified on release"
		"dots":
			_hint.text = "Click to drop a dot · click two dots to join them · Bksp undo"
		"upgrade":
			_hint.text = "Click a road to widen it · Shift-click to narrow it"
		"select":
			_hint.text = "Drag a box over roads · Delete removes them · Esc clears"


func set_status(text: String) -> void:
	if _status != null:
		_status.text = text


## The label is rebuilt from the base text held in metadata rather than parsed back out of
## the button, so repeated refreshes cannot accumulate or strip bullets.
func _mark(button: Button, on: bool) -> void:
	button.add_theme_color_override("font_color", HEADING if on else MUTED)
	button.text = ("●  " if on else "○  ") + str(button.get_meta("base_text", ""))


func _toggle_button(text: String) -> Button:
	var button := Button.new()
	button.set_meta("base_text", text)
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 26)
	return button


func _title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", HEADING)
	label.add_theme_font_size_override("font_size", 16)
	return label


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_color_override("font_color", MUTED)
	label.add_theme_font_size_override("font_size", 11)
	return label


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", MUTED)
	label.add_theme_font_size_override("font_size", 11)
	return label
