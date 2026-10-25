extends PanelContainer
## The Mapmodes panel in DS2's plain dress: the dark plate in its polished silver rim (the tutorial card's), a raised
## heading with the close key, and a latching cream key for each map mode, held down while its mode is on.

const SilverPlate := preload("res://scripts/tutorial/coach_plate.gd")
const LatchKey := preload("res://scripts/ds2/latch_key.gd")
const Heading := preload("res://scripts/bdp_v3_heading.gd")
const SmallKey := preload("res://scripts/bdp_v3_key.gd")
## Inside the silver rim: the plate's frame and the padding round its keys.
const PAD := 20

@onready var title_label: Label = $MarginContainer/ModalLayout/HeaderRow/TitleLabel
@onready var close_button: Button = $MarginContainer/ModalLayout/HeaderRow/CloseButton
@onready var scroll: ScrollContainer = $MarginContainer/ModalLayout/ScrollContainer
@onready var content_vbox: VBoxContainer = $MarginContainer/ModalLayout/ScrollContainer/ContentVBox

const HEADER_HEIGHT := 48.0
const MENU_GAP := 12.0   # gap kept between the panel's bottom and the bottom menu's top

# kind: "picker" = opens the good-select panel; "sentinel" = whole-map toggle;
# "none" = not yet implemented.
const ROWS: Array = [
	{"id": "producing", "label": "Producing", "kind": "picker"},
	{"id": "consuming", "label": "Consuming", "kind": "picker"},
	{"id": "deposits", "label": "Deposits", "kind": "sentinel"},
	{"id": "water", "label": "Water", "kind": "sentinel"},
	{"id": "power", "label": "Power", "kind": "sentinel"},
	{"id": "logistics", "label": "Logistics", "kind": "sentinel"},
	# demo:strip
	{"id": "surveying", "label": "Surveying", "kind": "sentinel"},
	# demo:end
	{"id": "infrastructure", "label": "Infrastructure", "kind": "sentinel"},
	{"id": "stockpile", "label": "Stockpile", "kind": "sentinel"},
	{"id": "ownership", "label": "Ownership", "kind": "sentinel"},
	{"id": "land_price", "label": "Land price", "kind": "sentinel"},
]

var _buttons := {}              # mode:int -> latching key (held down while its mode is on)
var _good_panel: Control = null
var _dragging := false
var _drag_offset := Vector2.ZERO

func _ready() -> void:
	close_button.pressed.connect(hide)
	title_label.text = "Mapmodes"
	_dress()
	_build_content()
	MapMode.selections_changed.connect(func(_m, _s) -> void: _sync_states())
	MapMode.mode_cleared.connect(_sync_states)
	visibility_changed.connect(func() -> void:
		if visible:
			call_deferred("_resize_to_content"))
	get_viewport().size_changed.connect(_resize_to_content)
	call_deferred("_resize_to_content")

# Size the panel to exactly fit its buttons + padding (no scrolling) and grow downward as map
# modes are added, capping at the bottom menu's top so it never overlaps it (scrolls only then).
func _resize_to_content() -> void:
	if scroll == null:
		return
	scroll.custom_minimum_size.y = 0.0
	var chrome_h := get_combined_minimum_size().y          # header + separators + margins (empty scroll)
	var content_h := content_vbox.get_combined_minimum_size().y
	var room := maxf(0.0, _max_panel_height() - chrome_h)
	var scroll_h := clampf(content_h, 0.0, room)
	scroll.custom_minimum_size.y = scroll_h
	offset_bottom = offset_top + chrome_h + scroll_h

func _max_panel_height() -> float:
	var cap_y := get_viewport_rect().size.y - 100.0       # fallback: bottom-menu buttons' top
	var parent := get_parent()
	if parent != null:
		var bm: Node = parent.get_node_or_null("BottomMenu")
		if bm is Control:
			cap_y = (bm as Control).global_position.y
	return maxf(140.0, cap_y - global_position.y - MENU_GAP)

## The plate behind everything, the heading and its close key in place of the old title and X, and a fine silver
## rule under them.
func _dress() -> void:
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var plate := SilverPlate.new()
	plate.name = "Plate"
	add_child(plate)
	move_child(plate, 0)
	var margin := $MarginContainer as MarginContainer
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, PAD)
	var header := title_label.get_parent() as HBoxContainer
	title_label.hide()
	close_button.hide()
	var words := "MAP MODES"
	if Heading.can_show(words):
		var heading: Control = Heading.new()
		heading.set("text", words)
		header.add_child(heading)
	else:
		var plain := Label.new()
		plain.text = words
		plain.add_theme_font_size_override("font_size", 16)
		plain.add_theme_color_override("font_color", DS.PALETTE.TEXT)
		header.add_child(plain)
	var flex := Control.new()
	flex.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(flex)
	var close: TextureButton = SmallKey.make("close", 26.0)
	close.name = "MapModesCloseKey"
	close.pressed.connect(hide)
	header.add_child(close)
	var rule := StyleBoxLine.new()
	rule.color = Color(SilverPlate.SILVER, 0.35)
	rule.thickness = 1
	($MarginContainer/ModalLayout/HSeparator as HSeparator).add_theme_stylebox_override("separator", rule)


func _build_content() -> void:
	for child in content_vbox.get_children():
		child.queue_free()
	_buttons.clear()
	# Two-column grid: row-major fill puts odd list positions (1st, 3rd, …) in
	# the left column and even positions in the right one.
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vbox.add_child(grid)
	for row in ROWS:
		var button: Control = LatchKey.new()
		button.set("text", str(row.label))
		button.name = "MapModeRow_%s" % str(row.id)   # e.g. MapModeRow_logistics
		button.connect("pressed", _on_row_pressed.bind(str(row.id), str(row.kind)))
		grid.add_child(button)
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
		_buttons[mode].set("latched", cur == mode)

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
		"infrastructure":
			return MapMode.Mode.INFRASTRUCTURE
		"stockpile":
			return MapMode.Mode.STOCKPILE
		"ownership":
			return MapMode.Mode.OWNERSHIP
		"land_price":
			return MapMode.Mode.LAND_PRICE
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
		"infrastructure":
			return MapMode.INFRASTRUCTURE_SENTINEL
		"stockpile":
			return MapMode.STOCKPILE_SENTINEL
		"ownership":
			return MapMode.OWNERSHIP_SENTINEL
		"land_price":
			return MapMode.LAND_PRICE_SENTINEL
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
