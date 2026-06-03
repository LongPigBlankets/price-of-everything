extends Control

## Title screen: navy backdrop, the animated goods board on the right, and a
## framed menu column on the left - a rounded off-white outline holding the
## buttons, with the large "PRICE OF EVERYTHING" title overlapping (and hiding)
## the top of the frame. Only New Game is wired up so far.

const MAP_SCENE := "res://scenes/main.tscn"
const NAVY := Color(0, 0.07, 0.14)            # established theme background navy
const OFF_WHITE := Color(0.995234, 0.930806, 0.763265)

const PANEL_INSET := 24.0   # frame inset from the screen edges
const SIDE_PAD := 30        # left/right padding inside the frame
const EDGE_PAD := 44        # New Game from the top of the buttons / Quit from the bottom
const TITLE_AREA := 210     # top strip the title occupies (buttons start below it)


func _ready() -> void:
	_build_menu()


func _on_new_game_pressed() -> void:
	get_tree().change_scene_to_file(MAP_SCENE)


func _build_menu() -> void:
	var panel := Panel.new()
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 0.25
	panel.anchor_bottom = 1.0
	panel.offset_left = PANEL_INSET
	panel.offset_top = PANEL_INSET
	panel.offset_right = -PANEL_INSET
	panel.offset_bottom = -PANEL_INSET
	var sb := StyleBoxFlat.new()
	sb.bg_color = NAVY
	sb.border_color = OFF_WHITE
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(22)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	# Button column: New Game at the top, Quit pinned to the bottom, the rest
	# between. The top margin clears the title strip.
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", SIDE_PAD)
	margin.add_theme_constant_override("margin_right", SIDE_PAD)
	margin.add_theme_constant_override("margin_top", TITLE_AREA)
	margin.add_theme_constant_override("margin_bottom", EDGE_PAD)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var new_game := _make_button("New Game", true)
	new_game.pressed.connect(_on_new_game_pressed)
	vbox.add_child(new_game)
	for label in ["Load Game", "Settings", "Credits", "Encyclopedia"]:
		vbox.add_child(_make_button(label, false))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)
	vbox.add_child(_make_button("Quit", false))

	# Title overlapping the top of the frame. A navy backing covers the top of
	# the outline so the title appears to sit in front of it.
	var backing := ColorRect.new()
	backing.color = NAVY
	backing.anchor_right = 1.0
	backing.offset_left = -2.0
	backing.offset_right = 2.0
	backing.offset_top = -PANEL_INSET
	backing.offset_bottom = TITLE_AREA - 28
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(backing)

	var title := Label.new()
	title.text = "PRICE OF EVERYTHING"
	title.theme_type_variation = &"Title"   # Bebas Neue - block capitals
	title.add_theme_font_size_override("font_size", 66)
	title.add_theme_color_override("font_color", OFF_WHITE)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD
	title.anchor_right = 1.0
	title.offset_left = SIDE_PAD - 6.0
	title.offset_right = -10.0
	title.offset_top = -10.0
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(title)


func _make_button(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	if primary:
		b.theme_type_variation = &"Primary"
		b.custom_minimum_size = Vector2(0, 62)
		b.add_theme_font_size_override("font_size", 26)
	else:
		b.custom_minimum_size = Vector2(0, 46)
	return b
