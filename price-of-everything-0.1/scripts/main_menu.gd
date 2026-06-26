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
const TITLE_AREA := 218     # top strip the title plate occupies (buttons start below it)
const TITLE_FONT := 56      # block-caps title size

# 9-slice borders of the plate (source pixels, sized to keep the corner bolts in
# the fixed corner regions) and where the plate sits in the frame.
const PLATE_L := 44
const PLATE_R := 44
const PLATE_T := 42
const PLATE_B := 42
const PLATE_TOP := -16.0
const PLATE_BOTTOM := 206.0


func _ready() -> void:
	_build_menu()


func _on_new_game_pressed() -> void:
	# New Game flows through the same snapshot pipeline as Load Game: the default
	# start config expands to a pending snapshot and applies once the map is ready.
	# We prepare the snapshot, raise the loading screen, then let IT drive a threaded
	# load of the map scene — so the posters + tip animate during the heavy load
	# instead of the menu freezing until the map is ready.
	SaveLoad.prepare_new_game()
	var screen := LoadingScreen.show_global(get_tree())
	screen.begin_load(SaveLoad.MAIN_SCENE)


func _on_load_game_pressed() -> void:
	SaveLoadScreen.open(self, SaveLoadScreen.Mode.LOAD)


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
		var b := _make_button(label, false)
		if label == "Load Game":
			b.pressed.connect(_on_load_game_pressed)
		vbox.add_child(b)
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

	# Title in the plate's cream middle: a navy block-caps label over a soft,
	# fading black shadow - stacked outlines that grow and fade out, rather than
	# one hard-edged shadow.
	var title_box := Control.new()
	title_box.anchor_right = 1.0
	title_box.anchor_bottom = 1.0
	title_box.offset_left = PLATE_L
	title_box.offset_top = PLATE_T
	title_box.offset_right = -PLATE_R
	title_box.offset_bottom = -PLATE_B
	title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(title_box)
	for layer in [Vector2(4, 0.26), Vector2(8, 0.15), Vector2(13, 0.07)]:
		var s := _title_label()
		s.add_theme_color_override("font_color", Color(0, 0, 0, layer.y))
		s.add_theme_color_override("font_outline_color", Color(0, 0, 0, layer.y))
		s.add_theme_constant_override("outline_size", int(layer.x))
		title_box.add_child(s)
	var title := _title_label()
	title.add_theme_color_override("font_color", NAVY)
	title_box.add_child(title)


func _title_label() -> Label:
	var l := Label.new()
	l.text = "PRICE OF EVERYTHING"
	l.theme_type_variation = &"Title"   # Bebas Neue - block capitals
	l.add_theme_font_size_override("font_size", TITLE_FONT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


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
