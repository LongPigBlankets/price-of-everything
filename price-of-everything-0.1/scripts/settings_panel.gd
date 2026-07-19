extends Control
class_name SettingsPanel
## Full-screen settings overlay with tabs across the top: Gameplay / Audio /
## Graphics / Controls. Audio has Master / Music / SFX volume sliders (0–100);
## Graphics has a window-resolution dropdown persisted via PlayerProfile. Both
## commit on Apply; Gameplay / Controls are still placeholders.
##
## Opened from the main menu (`SettingsPanel.open(self)`) and the in-game pause
## menu (`SettingsPanel.open(get_parent())`). Built per open and freed on hide, so
## it always reflects the live volumes. Esc / Back closes without applying; Apply
## commits and closes. Presentation-only (routes through Audio) — no sim state.

const PANEL_BLACK := Color(0.03, 0.03, 0.045)
const OFF_WHITE := Color(0.995234, 0.930806, 0.763265)

# Selectable window resolutions offered on the Graphics tab.
const RESOLUTIONS: Array[Vector2i] = [Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3440, 1440)]

var _sliders: Dictionary = {}   # bus StringName -> HSlider
var _resolution_option: OptionButton


static func open(parent: Node) -> SettingsPanel:
	var panel := SettingsPanel.new()
	parent.add_child(panel)
	return panel


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	# Near-full-screen dark plate over the dim.
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 48
	panel.offset_top = 40
	panel.offset_right = -48
	panel.offset_bottom = -40
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BLACK
	sb.border_color = OFF_WHITE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(20)
	sb.set_content_margin_all(30)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "SETTINGS"
	title.theme_type_variation = &"Title"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", OFF_WHITE)
	vbox.add_child(title)

	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(_build_gameplay_tab())
	var audio_tab := _build_audio_tab()
	tabs.add_child(audio_tab)
	tabs.add_child(_build_graphics_tab())
	tabs.add_child(_build_placeholder_tab("Controls"))
	tabs.current_tab = audio_tab.get_index()   # land on the only working tab
	vbox.add_child(tabs)

	# Footer: Back (discard) on the left, Apply (commit + close) on the right.
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	vbox.add_child(footer)
	footer.add_child(_make_button("Back", false, _on_back_pressed))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	footer.add_child(_make_button("Apply", true, _on_apply_pressed))

	PanelStack.push(self)
	visibility_changed.connect(_on_visibility_changed)


# --- Tab builders ------------------------------------------------------------

func _build_audio_tab() -> Control:
	var tab := MarginContainer.new()
	tab.name = "Audio"
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		tab.add_theme_constant_override(side, 24)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 22)
	col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	tab.add_child(col)

	# One row per bus, initialised to the live volume so nothing jumps on Apply.
	for row: Array in [[Audio.BUS_MASTER, "Master"], [Audio.BUS_MUSIC, "Music"], [Audio.BUS_SFX, "SFX"]]:
		col.add_child(_make_slider_row(row[0], row[1]))
	return tab


func _make_slider_row(bus: StringName, label_text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.custom_minimum_size = Vector2(0, 40)

	var name_label := Label.new()
	name_label.text = label_text
	name_label.theme_type_variation = &"Body"
	name_label.custom_minimum_size = Vector2(90, 0)
	row.add_child(name_label)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = round(Audio.get_bus_percent(bus))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	_sliders[bus] = slider

	var value_label := Label.new()
	value_label.theme_type_variation = &"Numeric"
	value_label.custom_minimum_size = Vector2(44, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.text = str(int(slider.value))
	row.add_child(value_label)

	# Live-update the numeric readout as the slider moves; the value only reaches
	# the audio bus on Apply.
	slider.value_changed.connect(func(v: float) -> void:
		value_label.text = str(int(round(v))))
	return row


func _build_gameplay_tab() -> Control:
	return _build_placeholder_tab("Gameplay")


func _build_graphics_tab() -> Control:
	var tab := MarginContainer.new()
	tab.name = "Graphics"
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		tab.add_theme_constant_override(side, 24)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	tab.add_child(col)

	# Resolution row: label + dropdown, mirroring the audio slider-row layout.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.custom_minimum_size = Vector2(0, 40)
	var name_label := Label.new()
	name_label.text = "Resolution"
	name_label.theme_type_variation = &"Body"
	name_label.custom_minimum_size = Vector2(140, 0)
	row.add_child(name_label)

	_resolution_option = OptionButton.new()
	for res: Vector2i in RESOLUTIONS:
		_resolution_option.add_item("%d × %d" % [res.x, res.y])
	_resolution_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resolution_option.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_resolution_option.select(_current_resolution_index())
	row.add_child(_resolution_option)
	col.add_child(row)

	var hint := Label.new()
	hint.text = "Applied on Apply. 3440 × 1440 is ultrawide (21:9); the others are 16:9."
	hint.theme_type_variation = &"Caption"
	hint.add_theme_color_override("font_color", Color(OFF_WHITE.r, OFF_WHITE.g, OFF_WHITE.b, 0.6))
	col.add_child(hint)
	return tab


# Index into RESOLUTIONS of the currently-applied (or saved) window size, else 0 (1920×1080).
func _current_resolution_index() -> int:
	var cur := PlayerProfile.window_size
	if cur.x <= 0 and DisplayServer.get_name() != "headless":
		cur = DisplayServer.window_get_size()
	for i in RESOLUTIONS.size():
		if RESOLUTIONS[i] == cur:
			return i
	return 0


func _build_placeholder_tab(tab_name: String) -> Control:
	var center := CenterContainer.new()
	center.name = tab_name
	var label := Label.new()
	label.text = "Coming soon"
	label.theme_type_variation = &"Caption"
	center.add_child(label)
	return center


# --- Buttons / lifecycle -----------------------------------------------------

func _make_button(text: String, primary: bool, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(120, 48 if primary else 44)
	if primary:
		b.theme_type_variation = &"Primary"
	if not handler.is_null():
		b.pressed.connect(handler)
	return b


func _on_apply_pressed() -> void:
	for bus: StringName in _sliders:
		Audio.set_bus_percent(bus, (_sliders[bus] as HSlider).value)
	if _resolution_option != null:
		var idx := _resolution_option.selected
		if idx >= 0 and idx < RESOLUTIONS.size():
			PlayerProfile.set_window_size(RESOLUTIONS[idx])
	hide()


func _on_back_pressed() -> void:
	hide()


func _unhandled_input(event: InputEvent) -> void:
	# Esc acts as Back (close without applying). In-game the pause menu below also
	# reacts to Esc via PanelStack, but consuming it here keeps closes to one panel.
	if visible and event.is_action_pressed("ui_cancel"):
		hide()
		get_viewport().set_input_as_handled()


func _on_visibility_changed() -> void:
	# Built per open (Back / Apply / Esc), so free it once hidden.
	if not visible:
		PanelStack.remove(self)
		queue_free()
