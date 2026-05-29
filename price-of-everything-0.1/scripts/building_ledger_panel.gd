# Template panel demonstrating the design system.
# Opened by the BuildingsButton (factory icon) in the bottom menu.
# Replace the placeholder content with the real ledger data when ready.
#
# Header is drag-to-move: click anywhere in the header (except the X button)
# and drag the panel around the screen.

extends PanelContainer

signal close_requested

const LOREM_1 := "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris."
const LOREM_2 := "Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum. Sed ut perspiciatis unde omnis iste natus error sit voluptatem."
const LOREM_3 := "Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia."

@onready var section1: SectionCard = $Layout/Scroll/Body/Section1
@onready var section2: SectionCard = $Layout/Scroll/Body/Section2
@onready var section3: SectionCard = $Layout/Scroll/Body/Section3
@onready var header: HBoxContainer = $Layout/Header
@onready var close_button: Button = %CloseButton

# Drag state
var _dragging := false
var _drag_panel_start := Vector2.ZERO
var _drag_mouse_start := Vector2.ZERO

func _ready() -> void:
	# Defensive: force the design-system theme on this panel + descendants,
	# in case the root cascade hasn't reached this lazily-instantiated panel.
	if DS and DS.theme:
		theme = DS.theme
	close_button.pressed.connect(func(): close_requested.emit())
	header.gui_input.connect(_on_header_gui_input)
	_populate_section(section1, LOREM_1, [
		["Stat label", "42"],
		["Another label", "73%"],
		["Tiny metadata", "lorem ipsum"],
	])
	_populate_section(section2, LOREM_2, [
		["Lorem ipsum", "1,234"],
		["Dolor sit amet", "£420"],
	])
	_populate_section(section3, LOREM_3, [
		["Consectetur", "+15%"],
		["Adipiscing", "—"],
	])
	# Center on screen after first layout pass (size is finalised by then).
	call_deferred("_center_on_screen")

func _center_on_screen() -> void:
	position = (get_viewport_rect().size - size) / 2.0

func _on_header_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_panel_start = position
			_drag_mouse_start = get_global_mouse_position()
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		position = _drag_panel_start + (get_global_mouse_position() - _drag_mouse_start)

func _populate_section(section: SectionCard, body_text: String, stats: Array) -> void:
	# Body text — Plex Medium 14, autowrapped via container width
	var body := Label.new()
	body.theme_type_variation = "Body"
	body.text = body_text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section.content.add_child(body)

	# Stat rows — Body label (white, Plex Medium 14) + Numeric value
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", DS.SP["XS"])
	section.content.add_child(rows)
	for entry in stats:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", DS.SP["SM"])
		var label := Label.new()
		label.theme_type_variation = "Body"
		label.text = String(entry[0])
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var value := Label.new()
		value.theme_type_variation = "Numeric"
		value.text = String(entry[1])
		row.add_child(label)
		row.add_child(value)
		rows.add_child(row)
