extends PanelContainer

@onready var title_label: Label = $MarginContainer/VBoxContainer/HeaderRow/TitleLabel
@onready var close_button: Button = $MarginContainer/VBoxContainer/HeaderRow/CloseButton
@onready var content_vbox: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/ContentVBox

const MarketRowScene: PackedScene = preload("res://scenes/market_row.tscn")
const HEADER_HEIGHT := 40.0

var rows: Array = []
var _dragging := false
var _drag_offset := Vector2.ZERO

func _ready() -> void:
	title_label.text = "Market"
	close_button.pressed.connect(hide)
	_build_content()
	MarketState.prices_updated.connect(_on_prices_updated)

func _build_content() -> void:
	for child in content_vbox.get_children():
		child.queue_free()
	rows.clear()
	
	var all_goods = Catalog.all()
	print("MarketPanel building rows for %d goods" % all_goods.size())
	
	for good_data in all_goods:
		print("  Adding row: ", good_data.id, " / ", good_data.display_name)
		var row := MarketRowScene.instantiate()
		content_vbox.add_child(row)
		row.setup(good_data)
		rows.append(row)

func _on_prices_updated() -> void:
	# Pass 2 will use this to refresh visible prices when decay ticks
	for row in rows:
		row._update_price()

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
