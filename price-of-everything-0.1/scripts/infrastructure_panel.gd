extends PanelContainer
# Infrastructure mapmode panel: a DS-themed radio grid of the six canonical
# infrastructure types (the tile panel's slot set). Shows itself while the
# Infrastructure mapmode is active (which also darkens the map); exactly one
# type can be lit at a time, and the map shows that type's icon on every tile
# that has it. Built in code by world_map, like the capacity/overflow dialogs.

const InfraIcons := preload("res://scripts/infra_icons.gd")

const HEADER_HEIGHT := 40.0
const PANEL_POSITION := Vector2(440, 58)
const ICON_BUTTON_SIZE := Vector2(80, 80)
const GRID_COLUMNS := 3
const CELL_WIDTH := 110.0

var _buttons := {}              # infra_key -> Button
var _dragging := false
var _drag_offset := Vector2.ZERO

func _ready() -> void:
	name = "InfrastructurePanel"
	visible = false
	position = PANEL_POSITION
	_build_content()
	MapMode.selections_changed.connect(_on_mode_changed)
	MapMode.mode_cleared.connect(hide)
	MapMode.infrastructure_selection_changed.connect(_sync_buttons)

func _build_content() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	margin.add_child(vb)
	# Header: title + close. Closing exits the mode (the panel is the mode's UI).
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	vb.add_child(header)
	var title := Label.new()
	title.text = "Infrastructure"
	title.theme_type_variation = &"Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "X"
	close.custom_minimum_size = Vector2(20, 20)
	close.add_theme_font_size_override("font_size", 20)
	close.pressed.connect(MapMode.clear_all)
	header.add_child(close)
	vb.add_child(HSeparator.new())
	var grid := GridContainer.new()
	grid.columns = GRID_COLUMNS
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	vb.add_child(grid)
	for slot in InfraIcons.SLOTS:
		grid.add_child(_make_cell(str(slot.key), str(slot.label)))

func _make_cell(infra_key: String, label_text: String) -> Control:
	var cell := VBoxContainer.new()
	cell.custom_minimum_size = Vector2(CELL_WIDTH, 0)
	cell.add_theme_constant_override("separation", 4)
	var button := Button.new()
	button.toggle_mode = true
	button.custom_minimum_size = ICON_BUTTON_SIZE
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.focus_mode = Control.FOCUS_NONE
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	var building: Dictionary = Catalog.get_building_by_internal_name(infra_key)
	var icon := InfraIcons.texture_for(str(building.get("id", "")), infra_key)
	if icon == null:
		button.disabled = true
		button.tooltip_text = "%s is not available yet" % label_text
	else:
		button.icon = icon
		button.tooltip_text = label_text
		button.pressed.connect(_on_type_pressed.bind(infra_key))
		_buttons[infra_key] = button
	cell.add_child(button)
	var name_label := Label.new()
	name_label.text = label_text
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.theme_type_variation = &"Caption"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.add_child(name_label)
	return cell

func _on_type_pressed(infra_key: String) -> void:
	MapMode.set_infrastructure_selection(infra_key)
	# _sync_buttons (via the MapMode signal) re-applies the authoritative radio
	# state — pressing the lit button again deselects it.

func _sync_buttons() -> void:
	for key in _buttons:
		_buttons[key].set_pressed_no_signal(MapMode.infrastructure_selection == key)

func _on_mode_changed(mode: int, _selections: Array) -> void:
	var active: bool = mode == MapMode.Mode.INFRASTRUCTURE
	visible = active
	if active:
		_sync_buttons()
		move_to_front()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if event.position.y > HEADER_HEIGHT:
				return
			_dragging = true
			_drag_offset = global_position - get_global_mouse_position()
			accept_event()
		else:
			_dragging = false
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		global_position = get_global_mouse_position() + _drag_offset
		accept_event()
