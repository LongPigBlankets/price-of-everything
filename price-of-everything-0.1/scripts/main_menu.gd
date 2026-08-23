extends Control

## Title screen: navy backdrop, the animated goods board on the right, and a
## framed menu column on the left - a rounded off-white outline holding the
## buttons, with a 9-sliced ornate plate at the top carrying the centred navy
## "CARBON AND CAPITAL" title. Only New Game is wired up so far.

const MAP_SCENE := "res://scenes/main.tscn"
## The map editor, revealed by `debug CandC` in the terminal below. Referenced BY PATH and
## never preloaded: `tools/` and `scripts/map_editor/` are excluded from exported builds
## (`export_presets.cfg`), and a `preload` resolves at parse time — it would break the
## exported game outright. The runtime `ResourceLoader.exists` probe means the entry simply
## never appears where the scene was not shipped. Pinned by
## `_test_shipped_code_avoids_editor_only_paths`.
const MAP_EDITOR_SCENE := "res://tools/map_editor/map_editor.tscn"
const NAVY := Color(0, 0.07, 0.14)            # established theme background navy
const OFF_WHITE := Color(0.995234, 0.930806, 0.763265)
const TITLE_LOGO: Texture2D = preload("res://assets/ui/title_logo.png")
# Preload (not a class_name) keeps the New Game panel out of the headless class cache.
const NewGamePanelScene := preload("res://scripts/new_game_panel.gd")
const TutorialPanelScene := preload("res://scripts/tutorial_intro_panel.gd")
const HallOfRecordsPanelScene := preload("res://scripts/hall_of_records_panel.gd")
const TutorialPromptScene := preload("res://scripts/tutorial_prompt_dialog.gd")
const MenuChrome := preload("res://scripts/menu_chrome.gd")
const TUTORIAL_START := "res://data/starts/tutorial.json"
const NEW_GAME_BOTTOM_GAP := 90.0   # panel stops this far above the screen bottom (board peeks beneath); low enough that the Start CTA sits on the panel, not the board

const PANEL_INSET := 24.0   # frame inset from the screen edges
const SIDE_PAD := 30        # left/right padding inside the frame
const EDGE_PAD := 44        # New Game from the top of the buttons / Quit from the bottom
# The hexagonal metal logo floats above the button frame (outside it), inset in the left column.
const LOGO_TOP := 24.0        # gap from the top of the column down to the logo
const LOGO_H := 313.0         # display height (10% smaller than before; width follows via aspect)
const BUTTONS_TOP := 351.0    # the button frame starts here — below the logo (LOGO_TOP + LOGO_H + gap)
const BUTTONS_PAD_TOP := 26   # padding inside the button frame, above New Game

# The New Game settings panel and the goods board it slides in over.
var _new_game_panel: Control
var _tutorial_panel: Control
var _hall_of_records_panel: Control
var _tutorial_prompt: Control
var _goods_grid: Control
var _map_editor_button: Button


func _ready() -> void:
	_build_menu()
	_build_new_game_panel()
	_build_tutorial_panel()
	_build_hall_of_records_panel()
	_build_tutorial_prompt()
	# Debug/cheat terminal (toggle with `). Menu mode allows only the match-independent
	# cheats — chiefly `swap loading_screen`, so the slow-build recording can be armed
	# before the first New Game (the in-match terminal is added by world_map).
	var term: CanvasLayer = load("res://scripts/debug_terminal.gd").new()
	term.menu_mode = true
	term.cheats_unlocked.connect(_on_cheats_unlocked)
	add_child(term)
	Audio.play_music()   # looping main-menu theme (placeholder track)
	# Warm the map's heavy ASSETS off-thread while the player is on the menu: textures, the
	# tileset and audio come off disk into RAM on a worker thread (no main-thread cost, no
	# frame drop), so the loading screen has less I/O left to do. Does NOT touch the
	# Start-time freeze (that's main-thread compilation + instantiation + first-frame GPU).
	#
	# ASSETS, not the scene. Requesting main.tscn here asked a worker to compile its scripts,
	# and a GDScript compiled on a loader thread cannot resolve preload() of a non-script
	# asset — so the request failed every boot, spraying parse errors before the player had
	# touched anything, and warmed nothing at all. The scripts are compiled on the main
	# thread under the intro plates instead (LoadingScreen._warm_scene_scripts).
	_warm_map_assets()


## Ask a worker for every non-script dependency of the map scene. get_dependencies() reads
## the scene header without loading it, so this list maintains itself.
func _warm_map_assets() -> void:
	for dep in ResourceLoader.get_dependencies(MAP_SCENE):
		# Entries are either "res://path" or "uid://x::::res://path".
		var at := String(dep).rfind("res://")
		if at < 0:
			continue
		var path := String(dep).substr(at)
		if path.ends_with(".gd") or path.ends_with(".tscn"):
			continue   # compiling these off-thread is the thing that never worked
		ResourceLoader.load_threaded_request(path)


# Clicking New Game no longer launches immediately — it opens the settings panel,
# whose Start New Game button drives the load (see _on_start_requested). A player who
# has never finished the tutorial first gets a nudge to do it.
func _on_new_game_pressed() -> void:
	if PlayerProfile.has_done_tutorial():
		_show_new_game_panel()
	else:
		_show_tutorial_prompt()


# ── "Play without the tutorial?" prompt ──────────────────────────────────────────

func _build_tutorial_prompt() -> void:
	_tutorial_prompt = TutorialPromptScene.new()
	_tutorial_prompt.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tutorial_prompt.z_index = 200   # over every side panel
	_tutorial_prompt.go_to_tutorial.connect(_on_tutorial_pressed)
	_tutorial_prompt.proceed_anyway.connect(_show_new_game_panel)
	add_child(_tutorial_prompt)


func _show_tutorial_prompt() -> void:
	if _tutorial_prompt == null or _tutorial_prompt.visible:
		return
	_close_side_panels()
	_tutorial_prompt.open()


# Start New Game pressed in the settings panel. New Game flows through the same
# snapshot pipeline as Load Game: the chosen start config expands to a pending
# snapshot and applies once the map is ready. We prepare the snapshot, raise the
# loading screen, then let IT drive a threaded load of the map scene — so the loading
# visuals animate during the heavy load instead of the menu freezing. (overrides —
# difficulty/victory/tutorial — are consumed by prepare_new_game in Phase 2.)
func _on_start_requested(start_path: String, overrides: Dictionary) -> void:
	# Prepare the snapshot, raise the loading screen, and let IT drive a threaded load of the map
	# scene. The heavy instantiation + first render happen behind the animated loading screen; the
	# HUD panels build lazily (on first open) and the hill work spreads via the loading-screen
	# pacing gate, so the freeze is far smaller than it was. The panel's overrides (ruleset —
	# survey_all_tiles, tutorial_enabled, difficulty/speed) merge into the start's ruleset.
	# Telemetry consent rides overrides from the panel; stage it for the run that is
	# about to arm (state_reset) and remember the choice for the next screen.
	var metrics_on := bool(overrides.get("telemetry_opt_in", true))
	overrides.erase("telemetry_opt_in")
	PlayerProfile.set_telemetry_opt_out(not metrics_on)
	TelemetryState.set_next_run_consent(metrics_on, false)
	SaveLoad.prepare_new_game(start_path, overrides)
	var screen := LoadingScreen.show_global(get_tree())
	screen.begin_load(SaveLoad.MAIN_SCENE)


# ── Map editor (cheat-gated) ─────────────────────────────────────────────────────

## Two conditions, deliberately independent: the cheat must be unlocked this app run, AND
## the editor scene must actually be present. The second is what keeps an exported build
## clean even if someone unlocks the terminal there — the files are excluded, the probe
## fails, and the entry stays hidden.
func _map_editor_available() -> bool:
	var terminal_script := load("res://scripts/debug_terminal.gd")
	if terminal_script == null or not terminal_script.cheats_are_unlocked():
		return false
	return ResourceLoader.exists(MAP_EDITOR_SCENE)


func _on_cheats_unlocked() -> void:
	if _map_editor_button != null:
		_map_editor_button.visible = _map_editor_available()


func _on_map_editor_pressed() -> void:
	if not _map_editor_available():
		return
	# By path, never by preload — see MAP_EDITOR_SCENE.
	get_tree().change_scene_to_file(MAP_EDITOR_SCENE)


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
	# Telemetry consent from the intro panel's checkbox; tutorial runs get a
	# "-T" suffixed run id so they separate cleanly in the data.
	var metrics_on: bool = _tutorial_panel.send_metrics_enabled()
	PlayerProfile.set_telemetry_opt_out(not metrics_on)
	TelemetryState.set_next_run_consent(metrics_on, true)
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
	panel.offset_top = BUTTONS_TOP   # starts below the logo, which now floats above the frame
	panel.offset_right = -PANEL_INSET
	panel.offset_bottom = -PANEL_INSET
	add_child(panel)
	MenuChrome.apply(panel)          # navy fill + the brass metallic edge (lit top-left → bottom-right)

	# Button column: New Game at the top, Quit pinned to the bottom, the rest between.
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", SIDE_PAD)
	margin.add_theme_constant_override("margin_right", SIDE_PAD)
	margin.add_theme_constant_override("margin_top", BUTTONS_PAD_TOP)
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
		elif label == "Credits":
			_make_coming_soon(b, "Coming soon.")
		elif label == "Encyclopedia":
			_make_coming_soon(b, "Coming soon. In the meantime check out the encyclopedia in the top bar in the game.")
		vbox.add_child(b)
	# Cheat-gated: hidden until `debug CandC` is entered in the terminal ( ` ), and absent
	# entirely from a build that did not ship the editor scene.
	_map_editor_button = _make_button("Map Editor", false)
	_map_editor_button.tooltip_text = "Hand-author the map's roads, fabric and building slots."
	_map_editor_button.pressed.connect(_on_map_editor_pressed)
	_map_editor_button.visible = _map_editor_available()
	vbox.add_child(_map_editor_button)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)
	var quit_btn := _make_button("Quit", false)
	quit_btn.pressed.connect(TelemetryState.request_app_quit)
	vbox.add_child(quit_btn)

	# Hexagonal metal logo (the site emblem: navy plate, gold bolts, factory + solar icons
	# and the three-row wordmark). It floats ABOVE the button frame, spanning the left column.
	var logo := TextureRect.new()
	logo.texture = TITLE_LOGO
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE   # honour the anchored box; don't grow to the texture's full size
	logo.anchor_right = 0.25
	logo.offset_left = PANEL_INSET
	logo.offset_right = -PANEL_INSET
	logo.offset_top = LOGO_TOP
	logo.offset_bottom = LOGO_TOP + LOGO_H
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(logo)


# Grey a menu button into a "not available yet" state that STILL shows its tooltip
# on hover. A truly disabled Button (disabled=true) doesn't surface its tooltip, so
# we keep it enabled, mute it, kill the hover highlight and wire no handler.
func _make_coming_soon(b: Button, tip: String) -> void:
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_ARROW
	b.add_theme_color_override("font_color", OFF_WHITE * Color(1, 1, 1, 0.38))
	b.add_theme_color_override("font_hover_color", OFF_WHITE * Color(1, 1, 1, 0.38))
	b.add_theme_color_override("font_pressed_color", OFF_WHITE * Color(1, 1, 1, 0.38))
	var muted := StyleBoxFlat.new()
	muted.bg_color = Color(NAVY, 0.0)   # no fill — reads as inert text, not a button
	muted.set_corner_radius_all(6)
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, muted)


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
