extends PanelContainer

@onready var title_label: Label = $MarginContainer/ModalLayout/HeaderRow/TitleLabel
@onready var close_button: Button = $MarginContainer/ModalLayout/HeaderRow/CloseButton
@onready var content_vbox: VBoxContainer = $MarginContainer/ModalLayout/ScrollContainer/ContentVBox

const HEADER_HEIGHT := 40.0

var overlay_rows: Array = []
var _dragging := false
var _drag_offset := Vector2.ZERO

# Defines the rows shown in the panel. Each row is one mapmode.
# Adding a new mapmode = adding a row here + handling the button press.
const MAPMODE_ROWS: Array = [
	{"id": "power", "label": "Power"},
	{"id": "logistics", "label": "Logistics"},
	{"id": "infrastructure", "label": "Infrastructure"},
]

func _ready() -> void:
	close_button.pressed.connect(hide)
	title_label.text = "Mapmodes"
	_build_content()

func _build_content() -> void:
	for child in content_vbox.get_children():
		child.queue_free()
	
	for row_data in MAPMODE_ROWS:
		var button := Button.new()
		button.text = row_data.label
		button.custom_minimum_size = Vector2(0, 36)
		button.pressed.connect(_on_mapmode_pressed.bind(row_data.id))
		content_vbox.add_child(button)

func _on_mapmode_pressed(mode_id: String) -> void:
	var target := _mode_for_id(mode_id)
	# Toggle off if this mode is already active.
	if target != MapMode.Mode.NONE and MapMode.current_mode == target:
		MapMode.clear_all()
		return
	# Switching mapmodes: close whatever's currently open, then open the new one.
	MapMode.clear_all()
	match mode_id:
		"power":
			MapMode.add_selection(MapMode.Mode.POWER_BALANCE, MapMode.POWER_SENTINEL)
		"logistics":
			MapMode.add_selection(MapMode.Mode.LOGISTICS, MapMode.LOGISTICS_SENTINEL)
		"infrastructure":
			print("[Mapmodes] infrastructure not yet implemented")

func _mode_for_id(mode_id: String) -> int:
	match mode_id:
		"power":
			return MapMode.Mode.POWER_BALANCE
		"logistics":
			return MapMode.Mode.LOGISTICS
		_:
			return MapMode.Mode.NONE

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Only start drag if click is in the top strip
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
