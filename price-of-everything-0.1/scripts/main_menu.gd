extends Control

## Title screen: navy backdrop, the animated goods board on the right, and a
## framed menu column on the left - a rounded off-white outline holding the
## buttons, with a 9-sliced ornate plate at the top carrying the centred navy
## "PRICE OF EVERYTHING" title. Only New Game is wired up so far.

const MAP_SCENE := "res://scenes/main.tscn"
const NAVY := Color(0, 0.07, 0.14)            # established theme background navy
const OFF_WHITE := Color(0.995234, 0.930806, 0.763265)
const TITLE_PLATE: Texture2D = preload("res://assets/ui/title_plate.png")
# Preload (not a class_name) keeps the New Game panel out of the headless class cache.
const NewGamePanelScene := preload("res://scripts/new_game_panel.gd")
const TutorialPanelScene := preload("res://scripts/tutorial_intro_panel.gd")
const HallOfRecordsPanelScene := preload("res://scripts/hall_of_records_panel.gd")
const TUTORIAL_START := "res://data/starts/tutorial.json"
const NEW_GAME_BOTTOM_GAP := 220.0   # panel stops this far above the screen bottom (board peeks beneath)

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

# The New Game settings panel and the goods board it slides in over.
var _new_game_panel: Control
var _tutorial_panel: Control
var _hall_of_records_panel: Control
var _goods_grid: Control


func _ready() -> void:
	_build_menu()
	_build_new_game_panel()
	_build_tutorial_panel()
	_build_hall_of_records_panel()
	Audio.play_music()   # looping main-menu theme (placeholder track)
	# Warm the map scene off-thread while the player is on the menu: this pulls main.tscn and
	# all its textures off disk into RAM on a worker thread (no main-thread cost, no frame drop),
	# so the loading screen's threaded load returns instantly instead of spending ~1.8 s on I/O.
	# Does NOT touch the Start-time freeze (that's main-thread instantiation + first-frame GPU).
	ResourceLoader.load_threaded_request(MAP_SCENE)


# Clicking New Game no longer launches immediately — it opens the settings panel,
# whose Start New Game button drives the load (see _on_start_requested).
func _on_new_game_pressed() -> void:
	_show_new_game_panel()


# Start New Game pressed in the settings panel. New Game flows through the same
# snapshot pipeline as Load Game: the chosen start config expands to a pending
# snapshot and applies once the map is ready. We prepare the snapshot, raise the
# loading screen, then let IT drive a threaded load of the map scene — so the loading
# visuals animate during the heavy load instead of the menu freezing. (overrides —
# difficulty/victory/tutorial — are consumed by prepare_new_game in Phase 2.)
func _on_start_requested(start_path: String, _overrides: Dictionary) -> void:
	# Prepare the snapshot, raise the loading screen, and let IT drive a threaded load of the map
	# scene. The heavy instantiation + first render happen behind the animated loading screen; the
	# HUD panels build lazily (on first open) and the hill work spreads via the loading-screen
	# pacing gate, so the freeze is far smaller than it was. (overrides — difficulty/victory/
	# tutorial — are consumed by prepare_new_game in Phase 2.)
	SaveLoad.prepare_new_game(start_path)
	var screen := LoadingScreen.show_global(get_tree())
	screen.begin_load(SaveLoad.MAIN_SCENE)


func _on_back_requested() -> void:
	_hide_new_game_panel()


# ── New Game settings panel ─────────────────────────────────────────────────────

func _build_new_game_panel() -> void:
	_goods_grid = get_node_or_null("GoodsGrid")
	_new_game_panel = NewGamePanelScene.new()
	# Occupy the right region (where the goods board is), matching the left frame inset.
	_new_game_panel.anchor_left = 0.25
	_new_game_panel.anchor_top = 0.0
	_new_game_panel.anchor_right = 1.0
	_new_game_panel.anchor_bottom = 1.0
	_new_game_panel.offset_left = PANEL_INSET
	_new_game_panel.offset_top = PANEL_INSET
	_new_game_panel.offset_right = -PANEL_INSET
	_new_game_panel.offset_bottom = -NEW_GAME_BOTTOM_GAP   # leave room so the goods board shows beneath
	_new_game_panel.visible = false
	_new_game_panel.modulate.a = 0.0
	_new_game_panel.z_index = 100   # above the goods board (its icons render at a raised z)
	_new_game_panel.start_requested.connect(_on_start_requested)
	_new_game_panel.back_requested.connect(_on_back_requested)
	add_child(_new_game_panel)


func _show_new_game_panel() -> void:
	if _new_game_panel == null or _new_game_panel.visible:
		return
	_close_side_panels(_new_game_panel)
	# Keep the goods board visible (it shows in the gap below the panel) but freeze it
	# so its periodic slide cue doesn't play while the settings screen is up.
	if _goods_grid != null:
		_goods_grid.set_process(false)
	_new_game_panel.visible = true
	_new_game_panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_new_game_panel, "modulate:a", 1.0, 0.22)


# Menu buttons are mutually exclusive: opening any panel closes the other side
# panels first (New Game then Settings must not leave New Game up underneath).
func _close_side_panels(except: Control = null) -> void:
	if _new_game_panel != null and _new_game_panel != except:
		_hide_new_game_panel()
	if _tutorial_panel != null and _tutorial_panel != except:
		_on_tutorial_back()
	if _hall_of_records_panel != null and _hall_of_records_panel != except:
		_on_hall_of_records_back()


func _hide_new_game_panel() -> void:
	if _new_game_panel == null or not _new_game_panel.visible:
		return
	if _goods_grid != null:
		_goods_grid.set_process(true)   # resume the board
	var tw := create_tween()
	tw.tween_property(_new_game_panel, "modulate:a", 0.0, 0.18)
	tw.tween_callback(func() -> void: _new_game_panel.visible = false)


# ── Tutorial panel ──────────────────────────────────────────────────────────────

func _build_tutorial_panel() -> void:
	_tutorial_panel = TutorialPanelScene.new()
	# Occupy the same right region the New Game panel uses.
	_tutorial_panel.anchor_left = 0.25
	_tutorial_panel.anchor_top = 0.0
	_tutorial_panel.anchor_right = 1.0
	_tutorial_panel.anchor_bottom = 1.0
	_tutorial_panel.offset_left = PANEL_INSET
	_tutorial_panel.offset_top = PANEL_INSET
	_tutorial_panel.offset_right = -PANEL_INSET
	_tutorial_panel.offset_bottom = -NEW_GAME_BOTTOM_GAP
	_tutorial_panel.visible = false
	_tutorial_panel.modulate.a = 0.0
	_tutorial_panel.z_index = 100
	_tutorial_panel.begin_requested.connect(_on_tutorial_begin)
	_tutorial_panel.back_requested.connect(_on_tutorial_back)
	add_child(_tutorial_panel)


func _on_tutorial_pressed() -> void:
	if _tutorial_panel == null or _tutorial_panel.visible:
		return
	_close_side_panels(_tutorial_panel)
	if _goods_grid != null:
		_goods_grid.set_process(false)
	_tutorial_panel.visible = true
	_tutorial_panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_tutorial_panel, "modulate:a", 1.0, 0.22)


func _on_tutorial_back() -> void:
	if _tutorial_panel == null or not _tutorial_panel.visible:
		return
	if _goods_grid != null:
		_goods_grid.set_process(true)
	var tw := create_tween()
	tw.tween_property(_tutorial_panel, "modulate:a", 0.0, 0.18)
	tw.tween_callback(func() -> void: _tutorial_panel.visible = false)


# ── Hall of Records panel ───────────────────────────────────────────────────────

func _build_hall_of_records_panel() -> void:
	_hall_of_records_panel = HallOfRecordsPanelScene.new()
	# Occupy the same right region the New Game panel uses.
	_hall_of_records_panel.anchor_left = 0.25
	_hall_of_records_panel.anchor_top = 0.0
	_hall_of_records_panel.anchor_right = 1.0
	_hall_of_records_panel.anchor_bottom = 1.0
	_hall_of_records_panel.offset_left = PANEL_INSET
	_hall_of_records_panel.offset_top = PANEL_INSET
	_hall_of_records_panel.offset_right = -PANEL_INSET
	_hall_of_records_panel.offset_bottom = -NEW_GAME_BOTTOM_GAP
	_hall_of_records_panel.visible = false
	_hall_of_records_panel.modulate.a = 0.0
	_hall_of_records_panel.z_index = 100
	_hall_of_records_panel.back_requested.connect(_on_hall_of_records_back)
	add_child(_hall_of_records_panel)


func _on_hall_of_records_pressed() -> void:
	if _hall_of_records_panel == null or _hall_of_records_panel.visible:
		return
	_close_side_panels(_hall_of_records_panel)
	if _goods_grid != null:
		_goods_grid.set_process(false)
	_hall_of_records_panel.refresh()
	_hall_of_records_panel.visible = true
	_hall_of_records_panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_hall_of_records_panel, "modulate:a", 1.0, 0.22)


func _on_hall_of_records_back() -> void:
	if _hall_of_records_panel == null or not _hall_of_records_panel.visible:
		return
	if _goods_grid != null:
		_goods_grid.set_process(true)
	var tw := create_tween()
	tw.tween_property(_hall_of_records_panel, "modulate:a", 0.0, 0.18)
	tw.tween_callback(func() -> void: _hall_of_records_panel.visible = false)


# Begin Tutorial boots the tutorial start config through the same snapshot + loading
# pipeline as New Game; the tutorial_enabled flag rides tutorial.json's ruleset dict
# into MatchState.ruleset, where the Tutorial autoload picks it up.
func _on_tutorial_begin() -> void:
	SaveLoad.prepare_new_game(TUTORIAL_START)
	var screen := LoadingScreen.show_global(get_tree())
	screen.begin_load(SaveLoad.MAIN_SCENE)


func _on_load_game_pressed() -> void:
	_close_side_panels()
	SaveLoadScreen.open(self, SaveLoadScreen.Mode.LOAD)


func _on_settings_pressed() -> void:
	_close_side_panels()
	SettingsPanel.open(self)


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
	var tutorial := _make_button("Tutorial", false)
	tutorial.pressed.connect(_on_tutorial_pressed)
	vbox.add_child(tutorial)
	for label in ["Load Game", "Hall of Records", "Settings", "Credits", "Encyclopedia"]:
		var b := _make_button(label, false)
		if label == "Load Game":
			b.pressed.connect(_on_load_game_pressed)
		elif label == "Hall of Records":
			b.pressed.connect(_on_hall_of_records_pressed)
		elif label == "Settings":
			b.pressed.connect(_on_settings_pressed)
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
