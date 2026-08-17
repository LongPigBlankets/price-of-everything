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
const MapEditorFormButton := preload("res://scripts/map_editor/map_editor_form_button.gd")
const MassFormShapes := preload("res://scripts/mass_form_shapes.gd")
const AuthoredSpecialShapes := preload("res://scripts/authored_special_shapes.gd")

const WIDTH := 244.0
const BG := Color(0.05, 0.07, 0.10, 0.93)
const HEADING := Color(0.60, 0.95, 0.75)
const MUTED := Color(0.72, 0.78, 0.82)
const ACCENT := Color(0.98, 0.80, 0.45)

## `[key, label, shortcut]` — the shortcut text is shown, not bound here; the editor owns the
## keys so there is one source of truth for what a key does.
## Tools that are not about roads. The road ones live in their own section.
const TOOLS := [
	["pan", "Navigate", "V"],
	["select", "Select / move", "X"],
	["stamp", "Stamp mass", "B"],
	["area", "Farm / wood / park", "N"],
	["special", "Special primitive", "M"],
]

## Everything to do with making and editing roads, in one place.
const ROAD_TOOLS := [
	["road", "Road pen", "R"],
	["trace", "Freehand", "F"],
	["dots", "Connect dots", "C"],
	["anchor", "Add anchor", "T"],
	["upgrade", "Upgrade class", "U"],
]

const ROAD_CLASSES := [
	["major", "Major", "1"],
	["mid", "Mid", "2"],
	["minor", "Minor", "3"],
]

## Sections that start folded. Visibility is long and consulted occasionally; session
## commands are rare.
const FOLDED := {"Visibility": true, "Session": true, "Buildings": true, "Farms & Forests": true,
	"Special Buildings": true, "Create roads": true, "Building Slots": true}

## Picker tiles per row. Three 50 px tiles plus their separation fit the column with room to
## spare; the grid is fixed rather than measured because the panel has a fixed width.
const PICKER_COLUMNS := 3

var _editor: Node
var _layers: MapEditorLayers
var _tool_buttons: Dictionary = {}
var _class_buttons: Dictionary = {}
var _layer_buttons: Dictionary = {}
var _form_tiles: Dictionary = {}
var _kind_tiles: Dictionary = {}
var _special_tiles: Dictionary = {}
var _slot_buttons: Dictionary = {}
var _special_rows: VBoxContainer
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

	# ── Create roads: the ways of drawing one, and how thick it is ──────────────
	var roads := _fold(column, "Create roads")
	for entry in ROAD_TOOLS:
		var key := str(entry[0])
		var button := _toggle_button("%s   (%s)" % [entry[1], entry[2]])
		button.pressed.connect(func() -> void: _editor.call("set_tool", key))
		_tool_buttons[key] = button
		roads.add_child(button)
	roads.add_child(_heading("Thickness"))
	for entry in ROAD_CLASSES:
		var key := str(entry[0])
		var button := _toggle_button("%s   (%s)" % [entry[1], entry[2]])
		button.pressed.connect(func() -> void: _editor.call("set_road_class", key))
		_class_buttons[key] = button
		roads.add_child(button)

	# ── Buildings, a grid of shapes ──────────────────────────────────────────────
	# The whole vocabulary as silhouettes. Selecting one also selects the stamp tool: picking
	# a shape is a statement of intent to place it.
	var buildings := _fold(column, "Buildings")
	var building_grid := GridContainer.new()
	building_grid.columns = PICKER_COLUMNS
	building_grid.add_theme_constant_override("h_separation", 6)
	building_grid.add_theme_constant_override("v_separation", 6)
	buildings.add_child(building_grid)
	for form_value in MassFormShapes.ALL_FORMS:
		var form := str(form_value)
		var tile := MapEditorFormButton.new()
		tile.kind = "form"
		tile.key = form
		tile.tooltip_text = form
		tile.picked.connect(func(picked_key: String) -> void:
			_editor.call("pick_form", picked_key))
		_form_tiles[form] = tile
		building_grid.add_child(tile)

	# ── Special buildings: parametric primitives ────────────────────────────────
	# Laid at their side lengths rather than dragged to size, and reshaped afterwards by
	# dragging their corners. The parameter rows below the grid act on whichever primitive is
	# selected.
	var specials := _fold(column, "Special Buildings")
	var special_grid := GridContainer.new()
	special_grid.columns = PICKER_COLUMNS
	special_grid.add_theme_constant_override("h_separation", 6)
	special_grid.add_theme_constant_override("v_separation", 6)
	specials.add_child(special_grid)
	for kind_value in AuthoredSpecialShapes.kinds():
		var special_kind := str(kind_value)
		var tile := MapEditorFormButton.new()
		tile.kind = "special"
		tile.key = special_kind
		tile.tooltip_text = special_kind.to_upper()
		tile.picked.connect(func(picked_key: String) -> void:
			_editor.call("pick_special", picked_key))
		_special_tiles[special_kind] = tile
		special_grid.add_child(tile)
	_special_rows = VBoxContainer.new()
	_special_rows.add_theme_constant_override("separation", 3)
	specials.add_child(_special_rows)

	# ── Farms & forests, the polygon tools ──────────────────────────────────────
	# Parks live here too: they are the same outline tool, and leaving them out of the panel
	# would hide a working tool rather than simplify anything.
	var ground := _fold(column, "Farms & Forests")
	var ground_grid := GridContainer.new()
	ground_grid.columns = PICKER_COLUMNS
	ground_grid.add_theme_constant_override("h_separation", 6)
	ground_grid.add_theme_constant_override("v_separation", 6)
	ground.add_child(ground_grid)
	for entry in [["farms", "Farm"], ["forests", "Wood"], ["parks", "Park"], ["plazas", "Plaza"]]:
		var area_key := str(entry[0])
		var tile := MapEditorFormButton.new()
		tile.kind = "area"
		tile.key = area_key
		tile.tooltip_text = str(entry[1])
		tile.picked.connect(func(picked_key: String) -> void:
			_editor.call("set_area_kind", picked_key))
		_kind_tiles[area_key] = tile
		ground_grid.add_child(tile)

	# ── Building slots ──────────────────────────────────────────────────────────
	# Empty ground reserved for a gameplay building — placed at a size class, facing the
	# nearest road, and rotatable afterwards with Z / Y like anything else.
	var slots := _fold(column, "Building Slots")
	for entry in [["small", "Small slot"], ["medium", "Medium slot"]]:
		var slot_class := str(entry[0])
		var button := _toggle_button("%s   (K)" % str(entry[1]))
		button.pressed.connect(func() -> void: _editor.call("pick_slot_class", slot_class))
		_slot_buttons[slot_class] = button
		slots.add_child(button)
	slots.add_child(_caption("Large is a farm or wood polygon, drawn above."))
	slots.add_child(_caption("Placed facing the nearest road · Z / Y rotate."))

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
	var water := _toggle_button("Water mask   (H)")
	water.pressed.connect(func() -> void: _editor.call("toggle_water_mask"))
	_layer_buttons["__water"] = water
	visibility.add_child(water)

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
		elif str(key) == "__water":
			_mark(_layer_buttons[key], bool(_editor.call("water_mask_shown")))
		else:
			_mark(_layer_buttons[key], _layers.is_on(str(key)))
	# The pickers show what is selected whichever tool is live, so a glance at the panel says
	# what the next stamp or outline will be.
	var current_form := str(_editor.call("current_form"))
	for key in _form_tiles:
		var tile: Control = _form_tiles[key]
		tile.selected = str(key) == current_form and tool_name == "stamp"
		tile.queue_redraw()
	var slot_class := str(_editor.call("current_slot_class"))
	for key in _slot_buttons:
		_mark(_slot_buttons[key], str(key) == slot_class and tool_name == "slot")
	var special_kind := str(_editor.call("current_special_kind"))
	for key in _special_tiles:
		var tile: Control = _special_tiles[key]
		tile.selected = str(key) == special_kind and tool_name == "special"
		tile.queue_redraw()
	_rebuild_special_rows()
	var area_kind := str(_editor.call("current_area_kind"))
	for key in _kind_tiles:
		var tile: Control = _kind_tiles[key]
		tile.selected = str(key) == area_kind and tool_name == "area"
		tile.queue_redraw()
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
			_hint.text = "Drag to move (hold Ctrl/Cmd to snap to a road) · click to select · +/- resize · Bksp deletes"
		"stamp":
			_hint.text = "Drag to size a mass · the drag direction is its facing · [ ] picks the form"
		"area":
			_hint.text = "Click corners (max 8) · Enter closes · Bksp undoes a corner"
		"slot":
			_hint.text = "Click to reserve ground for a gameplay building · Z / Y rotate"
		"special":
			_hint.text = ("Click up to 6 corners · Enter closes · Bksp steps back"
				if str(_editor.call("current_special_kind")) == "poly"
				else "Click to lay the primitive · then Select (X) and drag its corners")


## One row per side length of the selected primitive: a name, its value, and a pair of
## nudges. Steppers rather than sliders — a side length is a number the designer has in mind,
## and a slider in a 240 px column cannot hit one.
func _rebuild_special_rows() -> void:
	if _special_rows == null:
		return
	var names: Array = _editor.call("special_parameter_names")
	var sides: Array = _editor.call("special_sides")
	# Rebuilt only when the shape of the controls changes; otherwise values are updated in
	# place, so a held nudge does not rebuild the button under the cursor.
	if _special_rows.get_child_count() != names.size():
		for child in _special_rows.get_children():
			child.queue_free()
		for i in names.size():
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			var label := Label.new()
			label.add_theme_font_size_override("font_size", 11)
			label.add_theme_color_override("font_color", MUTED)
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(label)
			for step_value in [-10.0, 10.0]:
				var step: float = step_value
				var button := Button.new()
				button.text = "−" if step < 0.0 else "+"
				button.custom_minimum_size = Vector2(26, 22)
				var index := i
				var delta: float = step
				button.pressed.connect(func() -> void:
					_editor.call("adjust_special_side", index, delta))
				row.add_child(button)
			_special_rows.add_child(row)
	for i in mini(names.size(), _special_rows.get_child_count()):
		var row: Control = _special_rows.get_child(i)
		var label: Label = row.get_child(0)
		label.text = "%s  %d" % [str(names[i]), int(float(sides[i])) if i < sides.size() else 0]


## Open a named section. For capture harnesses, and for anything that later wants to reveal
## the section a command belongs to.
func open_section(title: String) -> void:
	var entry: Dictionary = _folds.get(title, {})
	if entry.is_empty():
		return
	(entry["body"] as Control).visible = true
	_paint_fold(title)


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
