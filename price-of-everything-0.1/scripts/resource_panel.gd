extends PanelContainer

@onready var title_label: Label = $MarginContainer/VBoxContainer/HeaderRow/TitleLabel
@onready var close_button: Button = $MarginContainer/VBoxContainer/HeaderRow/CloseButton
@onready var economy_vbox: VBoxContainer = $MarginContainer/VBoxContainer/TabContainer/EconomyTab/ScrollContainer/ContentVBox
@onready var resource_overlays_vbox: VBoxContainer = $MarginContainer/VBoxContainer/TabContainer/MapOverlaysTab/ScrollContainer/ContentVBox

const ResourceRowScene: PackedScene = preload("res://scenes/resource_row.tscn")
const HEADER_HEIGHT := 40.0

var overlay_rows: Array = []
var _dragging := false
var _drag_offset := Vector2.ZERO

func _ready() -> void:
	close_button.pressed.connect(hide)
	title_label.text = "Resources"
	_build_panel_content()
	MapMode.selections_changed.connect(_on_selections_changed)
	MapMode.mode_cleared.connect(_on_mode_cleared)

func _build_panel_content() -> void:
	overlay_rows.clear()
	
	var econ_children := economy_vbox.get_children()
	for i in range(econ_children.size() - 1, 0, -1):
		econ_children[i].queue_free()
	var overlay_children := resource_overlays_vbox.get_children()
	for i in range(overlay_children.size() - 1, 0, -1):
		overlay_children[i].queue_free()
	
	for good_data in Catalog.all():
		var econ_row := ResourceRowScene.instantiate()
		economy_vbox.add_child(econ_row)
		econ_row.setup(good_data)
		econ_row.set_mode(true)
		
		var overlay_row := ResourceRowScene.instantiate()
		resource_overlays_vbox.add_child(overlay_row)
		overlay_row.setup(good_data)
		overlay_row.set_mode(false)
		overlay_rows.append(overlay_row)
		
		overlay_row.potentials_pressed.connect(_on_potentials_pressed)
		overlay_row.producing_pressed.connect(_on_producing_pressed)
		overlay_row.consuming_pressed.connect(_on_consuming_pressed)

func _on_potentials_pressed(good_id: String) -> void:
	MapMode.add_selection(MapMode.Mode.POTENTIALS, good_id)

func _on_producing_pressed(good_id: String) -> void:
	MapMode.add_selection(MapMode.Mode.TILES_PRODUCING, good_id)

func _on_consuming_pressed(good_id: String) -> void:
	MapMode.add_selection(MapMode.Mode.TILES_CONSUMING, good_id)

func _on_selections_changed(_mode: int, _selections: Array) -> void:
	_refresh_button_states()

func _on_mode_cleared() -> void:
	_refresh_button_states()

func _refresh_button_states() -> void:
	for row in overlay_rows:
		row.update_button_states()
		
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
