extends PanelContainer

@onready var title_label: Label = $MarginContainer/ModalLayout/HeaderRow/TitleLabel
@onready var close_button: Button = $MarginContainer/ModalLayout/HeaderRow/CloseButton
@onready var content_vbox: VBoxContainer = $MarginContainer/ModalLayout/ScrollContainer/ContentVBox

const HEADER_HEIGHT := 40.0
const ROW_HEIGHT := 36

# kind: "picker" = opens the good-select panel; "sentinel" = whole-map toggle;
# "none" = not yet implemented.
const ROWS: Array = [
	{"id": "producing", "label": "Producing", "kind": "picker"},
	{"id": "consuming", "label": "Consuming", "kind": "picker"},
	{"id": "deposits", "label": "Deposits", "kind": "sentinel"},
	{"id": "water", "label": "Water", "kind": "sentinel"},
	{"id": "power", "label": "Power", "kind": "sentinel"},
	{"id": "logistics", "label": "Logistics", "kind": "sentinel"},
	{"id": "surveying", "label": "Surveying", "kind": "sentinel"},
	{"id": "infrastructure", "label": "Infrastructure", "kind": "none"},
]

var _buttons := {}              # mode:int -> Button (for active-state highlight)
var _good_panel: Control = null
var _dragging := false
var _drag_offset := Vector2.ZERO

func _ready() -> void:
	close_button.pressed.connect(hide)
	title_label.text = "Mapmodes"
	_build_content()
	MapMode.selections_changed.connect(func(_m, _s) -> void: _sync_states())
	MapMode.mode_cleared.connect(_sync_states)

func _build_content() -> void:
	for child in content_vbox.get_children():
		child.queue_free()
	_buttons.clear()
	for row in ROWS:
		var button := Button.new()
		button.text = row.label
		# Unimplemented rows stay plain so they don't latch pressed.
		button.toggle_mode = row.kind != "none"
		button.custom_minimum_size = Vector2(0, ROW_HEIGHT)
		button.pressed.connect(_on_row_pressed.bind(str(row.id), str(row.kind)))
		content_vbox.add_child(button)
		var mode := _mode_for_id(str(row.id))
		if mode != MapMode.Mode.NONE:
			_buttons[mode] = button
	_sync_states()

func _on_row_pressed(id: String, kind: String) -> void:
	match kind:
		"picker":
			# Opening the picker shows its tick-list; the mode activates as goods are
			# ticked. The good panel replaces this one, so close the Mapmodes panel.
			_open_good_panel(id)
			hide()
			return
		"sentinel":
			var mode := _mode_for_id(id)
			MapMode.set_sentinel_mode(mode, _sentinel_for(id))
			if id == "deposits" and MapMode.current_mode == mode:
				_open_good_panel("deposits")  # let the player un-tick deposits to hide
		_:
			print("[Mapmodes] %s not yet implemented" % id)
	_sync_states()

func _open_good_panel(kind: String) -> void:
	if _good_panel == null:
		_good_panel = get_node_or_null("%GoodSelectPanel")
		if _good_panel == null and owner != null:
			_good_panel = owner.find_child("GoodSelectPanel", true, false)
	if _good_panel != null:
		_good_panel.open_for(kind)

func _sync_states() -> void:
	var cur: int = MapMode.current_mode
	for mode in _buttons:
		_buttons[mode].set_pressed_no_signal(cur == mode)

func _mode_for_id(mode_id: String) -> int:
	match mode_id:
		"producing":
			return MapMode.Mode.TILES_PRODUCING
		"consuming":
			return MapMode.Mode.TILES_CONSUMING
		"deposits":
			return MapMode.Mode.DEPOSITS
		"water":
			return MapMode.Mode.WATER
		"power":
			return MapMode.Mode.POWER_BALANCE
		"logistics":
			return MapMode.Mode.LOGISTICS
		"surveying":
			return MapMode.Mode.SURVEYING
		_:
			return MapMode.Mode.NONE

func _sentinel_for(mode_id: String) -> String:
	match mode_id:
		"deposits":
			return MapMode.DEPOSITS_SENTINEL
		"water":
			return MapMode.WATER_SENTINEL
		"power":
			return MapMode.POWER_SENTINEL
		"logistics":
			return MapMode.LOGISTICS_SENTINEL
		"surveying":
			return MapMode.SURVEYING_SENTINEL
		_:
			return ""

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
