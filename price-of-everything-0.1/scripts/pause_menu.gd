extends Control
class_name PauseMenu
## In-game menu opened by Esc when no other panel is left to close (see
## world_map._unhandled_input → PanelStack.close_top() returning false).
## Centered black rounded panel with: Return to game / Save Game / Load Game /
## Settings (placeholder) / Quit to Desktop. Esc or "Return to game" closes it.

const PANEL_BLACK := Color(0.03, 0.03, 0.045)
const OFF_WHITE := Color(0.995234, 0.930806, 0.763265)
const PANEL_SIZE := Vector2(420, 480)
const RESOLVING_TOOLTIP := "Please wait until the turn resolves"

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
	# Saving mid-resolution is refused by SaveLoad, and loading mid-resolution
	# would let the suspended resolution coroutine resume over the loaded state —
	# grey both out until the turn re-enters DECIDE. (The menu can be opened
	# during resolution and outlive it, so track both edges.)
	TurnManager.turn_resolution_started.connect(_refresh_locks)
	TurnManager.turn_resolution_completed.connect(_refresh_locks)
	_refresh_locks()
	vbox.add_child(_make_button("Settings", false, _on_settings_pressed))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)
	vbox.add_child(_make_button("Quit to Desktop", false, _on_quit_pressed))

	PanelStack.push(self)
	visibility_changed.connect(_on_visibility_changed)


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


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_visibility_changed() -> void:
	# Hidden by Return-to-game or PanelStack.close_top() (Esc): built per open, so free.
	if not visible:
		PanelStack.remove(self)
		queue_free()
