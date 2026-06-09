extends PanelContainer
# Resources panel: an economy table of every good (name, stockpile, unit cost).
# The map-overlay tabs (producing / consuming / deposits) moved to the Mapmodes
# panel, so this panel is now a single informational list.

@onready var title_label: Label = $MarginContainer/VBoxContainer/HeaderRow/TitleLabel
@onready var close_button: Button = $MarginContainer/VBoxContainer/HeaderRow/CloseButton
@onready var content_vbox: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/ContentVBox

const ResourceRowScene: PackedScene = preload("res://scenes/resource_row.tscn")
const HEADER_HEIGHT := 40.0

var _dragging := false
var _drag_offset := Vector2.ZERO

func _ready() -> void:
	close_button.pressed.connect(hide)
	title_label.text = "Resources"
	_build_panel_content()

func _build_panel_content() -> void:
	for child in content_vbox.get_children():
		child.queue_free()

	for good_data in Catalog.all_goods():
		var row := ResourceRowScene.instantiate()
		content_vbox.add_child(row)
		row.setup(good_data)

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
