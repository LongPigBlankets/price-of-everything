extends PanelContainer
## The editor's tool panel: what you are drawing with, what you can see, and what the last
## action did.
##
## EDITOR-ONLY (see the header of `map_editor.gd`).
##
## It is a plain Control column rather than anything from the game's own HUD. The DS theme
## is assigned to the root viewport, so these inherit the project's fonts and colours for
## free, but nothing here should look like a panel a player sees — this is a workbench.
##
## The panel OWNS no state. Every control reads from and writes to the editor through the
## callbacks handed in at build time, so the keyboard shortcuts and the buttons cannot drift
## apart: pressing R and clicking "Road" run the same line.

const MapEditorLayers := preload("res://scripts/map_editor/map_editor_layers.gd")

const WIDTH := 232.0
const BG := Color(0.05, 0.07, 0.10, 0.93)
const HEADING := Color(0.60, 0.95, 0.75)
const MUTED := Color(0.72, 0.78, 0.82)

## `[key, label, shortcut]` — the shortcut text is shown, not bound here; the editor owns
## the keys so there is one source of truth for what a key does.
const TOOLS := [
	["pan", "Navigate", "V"],
	["road", "Road pen", "R"],
]

const ROAD_CLASSES := [
	["major", "Major", "1"],
	["mid", "Mid", "2"],
	["minor", "Minor", "3"],
]

var _editor: Node
var _layers: MapEditorLayers
var _tool_buttons: Dictionary = {}
var _class_buttons: Dictionary = {}
var _layer_buttons: Dictionary = {}
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

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)

	column.add_child(_title("MAP EDITOR"))
	_hint = _caption("")
	column.add_child(_hint)

	column.add_child(_heading("Tool"))
	for entry in TOOLS:
		var button := _toggle_button("%s   (%s)" % [entry[1], entry[2]])
		var key := str(entry[0])
		button.pressed.connect(func() -> void: _editor.call("set_tool", key))
		_tool_buttons[key] = button
		column.add_child(button)

	column.add_child(_heading("Road class"))
	for entry in ROAD_CLASSES:
		var button := _toggle_button("%s   (%s)" % [entry[1], entry[2]])
		var key := str(entry[0])
		button.pressed.connect(func() -> void: _editor.call("set_road_class", key))
		_class_buttons[key] = button
		column.add_child(button)

	column.add_child(_heading("Show"))
	for entry in MapEditorLayers.LAYERS:
		var key := str(entry["key"])
		var button := _toggle_button(str(entry["label"]))
		button.pressed.connect(func() -> void:
			_layers.toggle(key)
			refresh())
		_layer_buttons[key] = button
		column.add_child(button)
	var grid := _toggle_button("Tile grid & ids   (G)")
	grid.pressed.connect(func() -> void: _editor.call("toggle_grid"))
	_layer_buttons["__grid"] = grid
	column.add_child(grid)

	column.add_child(_heading("Document"))
	for entry in [["Save   (F5)", "save"], ["Reload   (F6)", "reload"], ["Back to menu   (Esc)", "leave"]]:
		var button := Button.new()
		button.text = str(entry[0])
		button.custom_minimum_size = Vector2(0, 28)
		var action := str(entry[1])
		button.pressed.connect(func() -> void: _editor.call("run_action", action))
		column.add_child(button)

	_status = _caption("")
	_status.custom_minimum_size = Vector2(0, 46)
	column.add_child(_status)
	refresh()


## Repaint the panel from the editor's state. Called after anything that could change it,
## rather than each control tracking its own truth.
func refresh() -> void:
	if _editor == null:
		return
	var tool_name := str(_editor.call("current_tool"))
	for key in _tool_buttons:
		_mark(_tool_buttons[key], str(key) == tool_name)
	var road_class := str(_editor.call("current_road_class"))
	for key in _class_buttons:
		_mark(_class_buttons[key], str(key) == road_class)
		(_class_buttons[key] as Button).disabled = tool_name != "road"
	for key in _layer_buttons:
		if str(key) == "__grid":
			_mark(_layer_buttons[key], bool(_editor.call("grid_shown")))
		else:
			_mark(_layer_buttons[key], _layers.is_on(str(key)))
	_hint.text = ("Drag to pan · wheel to zoom" if tool_name == "pan"
		else "Click a corner · drag for a curve · Enter ends · Bksp back")


func set_status(text: String) -> void:
	if _status != null:
		_status.text = text


## The label is rebuilt from the base text held in metadata rather than parsed back out of
## the button, so repeated refreshes cannot accumulate or strip bullets.
func _mark(button: Button, on: bool) -> void:
	button.add_theme_color_override("font_color", HEADING if on else MUTED)
	button.text = ("\u25cf  " if on else "\u25cb  ") + str(button.get_meta("base_text", ""))


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
