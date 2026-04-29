extends HBoxContainer

@export var target: Control  # The thing to actually move (the panel)

var _dragging := false
var _drag_offset := Vector2.ZERO

func _ready() -> void:
	# If no target set in inspector, walk up to find the PanelContainer
	if target == null:
		var node = get_parent()
		while node and not (node is PanelContainer):
			node = node.get_parent()
		target = node
	mouse_filter = Control.MOUSE_FILTER_STOP

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_offset = target.global_position - get_global_mouse_position()
			accept_event()
		else:
			_dragging = false
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		target.global_position = get_global_mouse_position() + _drag_offset
		accept_event()
