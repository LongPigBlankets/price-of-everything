extends Control
class_name PauseMenu
## In-game menu opened by Esc when no other panel is left to close (see
## world_map._unhandled_input → PanelStack.close_top() returning false).
## Centered black rounded panel with: Return to game / Save Game / Load Game /
## Settings (placeholder) / Exit to Main Menu / Exit to Desktop. Esc or
## "Return to game" closes it.
##
## In DS2 (UiPrefs.use_pause_ds2) the menu is a cabinet on Building Detail's navy steel backing in its brass
## trim, its raised title over two sections: the game's keys (Return to game, Save, Load, Settings) on a steel
## plate, and the two ways out on a dark metal plate, printed in red ink. Each is one of the cabinet's cream
## keys (scripts/ds2/cream_key.gd). While a turn resolves Save and Load are greyed, their tooltip saying why.

const PANEL_BLACK := Color(0.03, 0.03, 0.045)
const OFF_WHITE := Color(0.995234, 0.930806, 0.763265)
const PANEL_SIZE := Vector2(420, 480)
const RESOLVING_TOOLTIP := "Please wait until the turn resolves"
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"  # matches bottom_menu.gd

const CreamKey := preload("res://scripts/ds2/cream_key.gd")
const Nine := preload("res://scripts/bdp_v3_nine.gd")
const Title := preload("res://scripts/bdp_v3_title.gd")
const Section := preload("res://scripts/bdp_v3_section.gd")
## Building Detail's backing: its 9-slice corner in texels and the content's margin inside the brass trim.
const BACKING_CORNER := 64.0
const CONTENT_MARGIN := 26
const KEY_W := 280.0

var _save_btn: Button
var _load_btn: Button


static func open(parent: Node) -> PauseMenu:
	var menu := PauseMenu.new()
	parent.add_child(menu)
	return menu


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	if UiPrefs.use_pause_ds2:
		_build_ds2()
	else:
		_build_v2()
	# Saving mid-resolution is refused by SaveLoad, and loading mid-resolution
	# would let the suspended resolution coroutine resume over the loaded state —
	# grey both out until the turn re-enters DECIDE. (The menu can be opened
	# during resolution and outlive it, so track both edges.)
	TurnManager.turn_resolution_started.connect(_refresh_locks)
	TurnManager.turn_resolution_completed.connect(_refresh_locks)
	_refresh_locks()

	PanelStack.push(self)
	visibility_changed.connect(_on_visibility_changed)


func _build_v2() -> void:
	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = PANEL_SIZE
	panel.offset_left = -PANEL_SIZE.x / 2
	panel.offset_top = -PANEL_SIZE.y / 2
	panel.offset_right = PANEL_SIZE.x / 2
	panel.offset_bottom = PANEL_SIZE.y / 2
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BLACK
	sb.border_color = OFF_WHITE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(24)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 30)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "MENU"
	title.theme_type_variation = &"Title"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", OFF_WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(_make_button("Return to game", true, _on_return_pressed))
	_save_btn = _make_button("Save Game", false, _on_save_pressed)
	vbox.add_child(_save_btn)
	_load_btn = _make_button("Load Game", false, _on_load_pressed)
	vbox.add_child(_load_btn)
	vbox.add_child(_make_button("Settings", false, _on_settings_pressed))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)
	vbox.add_child(_make_button("Exit to Main Menu", false, _on_exit_to_menu_pressed))
	vbox.add_child(_make_button("Exit to Desktop", false, _on_quit_pressed))


func _build_ds2() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	var cabinet := PanelContainer.new()
	cabinet.name = "MenuCabinet"
	cabinet.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	cabinet.add_child(Nine.make("panel_backing", BACKING_CORNER))
	centre.add_child(cabinet)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, CONTENT_MARGIN)
	cabinet.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)
	var title: Control = Title.new()
	title.call("set_text", "Menu")
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(title)

	var game := _key_section(col, "steel")
	game.add_child(_key("ReturnKey", "Return to game", _on_return_pressed))
	_save_btn = _key("SaveKey", "Save Game", _on_save_pressed)
	game.add_child(_save_btn)
	_load_btn = _key("LoadKey", "Load Game", _on_load_pressed)
	game.add_child(_load_btn)
	game.add_child(_key("SettingsKey", "Settings", _on_settings_pressed))

	var out := _key_section(col, "dark")
	for spec: Array in [["ExitToMenuKey", "Exit to Main Menu", _on_exit_to_menu_pressed],
			["ExitToDesktopKey", "Exit to Desktop", _on_quit_pressed]]:
		var key := _key(spec[0], spec[1], spec[2])
		key.set("title_ink", CreamKey.RED_INK)
		out.add_child(key)


## A section of the cabinet in `style`, its content a column of keys.
func _key_section(col: VBoxContainer, style: String) -> VBoxContainer:
	var section: Control = Section.new()
	section.set("style", style)
	col.add_child(section)
	var keys: VBoxContainer = section.get("content")
	keys.add_theme_constant_override("separation", 10)
	return keys


## A cream key `KEY_W` wide printing `words`.
func _key(node_name: String, words: String, handler: Callable) -> Button:
	var key: Button = CreamKey.make(node_name, words, "", KEY_W)
	key.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	key.pressed.connect(handler)
	return key


func _make_button(text: String, primary: bool, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 56 if primary else 48)
	if primary:
		b.theme_type_variation = &"Primary"
	if not handler.is_null():
		b.pressed.connect(handler)
	return b


func _refresh_locks() -> void:
	var locked: bool = TurnManager.is_resolving
	for b: Button in [_save_btn, _load_btn]:
		if b.has_method("set_spent"):
			b.call("set_spent", locked)
		else:
			b.disabled = locked
		b.tooltip_text = RESOLVING_TOOLTIP if locked else ""


func _on_return_pressed() -> void:
	hide()


func _on_save_pressed() -> void:
	# The screen stacks above this menu; Esc/Cancel there falls back here.
	SaveLoadScreen.open(get_parent(), SaveLoadScreen.Mode.SAVE)


func _on_load_pressed() -> void:
	SaveLoadScreen.open(get_parent(), SaveLoadScreen.Mode.LOAD)


func _on_settings_pressed() -> void:
	# Opened on our parent so it stacks above this menu (Esc/Back falls back here).
	SettingsPanel.open(get_parent())


func _on_exit_to_menu_pressed() -> void:
	# Autoloads survive; the scene tree (and this menu) is freed. A subsequent
	# New Game reinitialises via SaveLoad.apply_pending() → MatchState.reset(),
	# exactly as the victory/bankruptcy return-to-menu paths rely on.
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _on_quit_pressed() -> void:
	# Neither this path nor request_app_quit raises WM_CLOSE_REQUEST, so flush
	# the session log here; SessionLog guards against a duplicate on _exit_tree.
	# TelemetryState spools + uploads (bounded) and owns the quit() call.
	SessionLog.flush()
	TelemetryState.request_app_quit()


func _on_visibility_changed() -> void:
	# Hidden by Return-to-game or PanelStack.close_top() (Esc): built per open, so free.
	if not visible:
		PanelStack.remove(self)
		queue_free()
