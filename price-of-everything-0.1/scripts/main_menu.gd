extends Control

## Title screen: navy backdrop, the animated goods board on the right, and a
## framed menu column on the left - a rounded off-white outline holding the
## buttons, with a 9-sliced ornate plate at the top carrying the centred navy
## "PRICE OF EVERYTHING" title. Only New Game is wired up so far.

const MAP_SCENE := "res://scenes/main.tscn"
const NAVY := Color(0, 0.07, 0.14)            # established theme background navy
const OFF_WHITE := Color(0.995234, 0.930806, 0.763265)
const TITLE_PLATE: Texture2D = preload("res://assets/ui/title_plate.png")

const PANEL_INSET := 24.0   # frame inset from the screen edges
const SIDE_PAD := 30        # left/right padding inside the frame
const EDGE_PAD := 44        # New Game from the top of the buttons / Quit from the bottom
const TITLE_AREA := 270     # top strip the title plate occupies (buttons start below it)

# 9-slice borders of the plate (source pixels) and where it sits in the frame.
const PLATE_L := 95
const PLATE_R := 107
const PLATE_T := 65
const PLATE_B := 79
const PLATE_TOP := -16.0
const PLATE_BOTTOM := 258.0


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
	# between. The top margin clears the title plate.
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

	# 9-sliced ornate plate overlapping the top of the frame (hides the outline
	# behind it), with the title centred in its cream middle.
	var plate := NinePatchRect.new()
	plate.texture = TITLE_PLATE
	plate.patch_margin_left = PLATE_L
	plate.patch_margin_right = PLATE_R
	plate.patch_margin_top = PLATE_T
	plate.patch_margin_bottom = PLATE_B
	plate.anchor_right = 1.0
	plate.offset_left = -10.0
	plate.offset_right = 10.0
	plate.offset_top = PLATE_TOP
	plate.offset_bottom = PLATE_BOTTOM
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(plate)

	var title := Label.new()
	title.text = "PRICE OF EVERYTHING"
	title.theme_type_variation = &"Title"   # Bebas Neue - block capitals
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", NAVY)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	title.add_theme_constant_override("shadow_outline_size", 2)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD
	title.anchor_right = 1.0
	title.anchor_bottom = 1.0
	title.offset_left = PLATE_L
	title.offset_top = PLATE_T
	title.offset_right = -PLATE_R
	title.offset_bottom = -PLATE_B
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(title)


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
