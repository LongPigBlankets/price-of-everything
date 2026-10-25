extends Control
class_name SettingsPanel
## DS2 control cabinet with latched page keys: Gameplay / Audio /
## Graphics / Controls / Telemetry. Audio has Master / Music / SFX volume sliders (0–100);
## Graphics has a window-resolution dropdown persisted via PlayerProfile; Controls
## lists the whole scheme, read-only for the demo except the map-mode hotkeys, which
## ship unbound for the player to set. Gameplay holds a dummy seven-position "Test
## setting" on the rotary knob, kept for the session only, and a "Test gauge" preview with
## a control for each panel-gauge attribute. All but the preview commit on Apply.
##
## Opened from the main menu (`SettingsPanel.open(self)`) and the in-game pause
## menu (`SettingsPanel.open(get_parent())`). Built per open and freed on hide, so
## it always reflects the live volumes. Esc / Back closes without applying; Apply
## commits and closes. Presentation-only (routes through Audio) — no sim state.

const OFF_WHITE := Color(0.995234, 0.930806, 0.763265)
const Parts := preload("res://scripts/ds2/parts.gd")
const Section := preload("res://scripts/bdp_v3_section.gd")
const CreamKey := preload("res://scripts/ds2/cream_key.gd")
const Title := preload("res://scripts/bdp_v3_title.gd")
const Key := preload("res://scripts/bdp_v3_key.gd")
const Plate := preload("res://scripts/bdp_v3_plate.gd")
const Scroll := preload("res://scripts/bdp_v3_scroll.gd")
const Drum := preload("res://scripts/ds2/drum_figure.gd")
const LampOverlay := preload("res://scripts/ds2/lamp_overlay.gd")
const PreferencesKit := preload("res://scripts/ds2/preferences_kit.gd")
const UIFonts := preload("res://scripts/ui_fonts.gd")

var _cabinet: PanelContainer
var _tabs: TabContainer
var _tab_keys: Array[Button] = []
const Keybinds := preload("res://scripts/keybinds.gd")
const RotarySelector := preload("res://scripts/rotary_selector.gd")
const PanelGauge := preload("res://scripts/panel_gauge.gd")

## Dummy Gameplay setting (1–7) that exercises the rotary knob. Session-only: not saved.
static var test_setting: int = 1

# Selectable window resolutions offered on the Graphics tab.
const RESOLUTIONS: Array[Vector2i] = [Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3440, 1440)]

var _sliders: Dictionary = {}   # bus StringName -> HSlider
var _resolution_option: OptionButton
var _fullscreen_check: CheckBox
var _screen_option: OptionButton   # only built when more than one monitor is present
var _quality_option: OptionButton
var _telemetry_option: OptionButton
const TELEMETRY_HINT := "Turn-by-turn profit and revenue, building counts and types, power generated, goods produced, workforce satisfaction and strikes. Reports include a random user ID, run/session IDs, run timing and end reason, the start played, whether cheats were used, operating system and game version. No IP address, account details or text you type is included."
const TELEMETRY_ID_EXPLANATION := "This is the randomly generated user ID that any data going to the developer is marked with. No IP is collected, no identifying information is recorded. If you ever want your data deleted, please contact the developer at carbonandcapital.game@gmail.com and quote this user ID number. This can take several weeks."
## Settings → Graphics quality presets, in dropdown order: [profile value, label].
const QUALITY_PRESETS := [["high", "High"], ["low", "Low"]]
const QUALITY_HINT := "Low preset shows only flat maps everywhere whereas High uses 3D assets for relief and roads."
var _test_knob: Control            # rotary_selector.gd, staged until Apply
var _test_gauge: Control           # panel_gauge.gd, a live preview with its own controls


static func open(parent: Node) -> SettingsPanel:
	var panel := SettingsPanel.new()
	parent.add_child(panel)
	return panel


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	_cabinet = PanelContainer.new()
	_cabinet.name = "SettingsCabinet"
	var backing := StyleBoxTexture.new()
	backing.texture = preload("res://assets/ui/bdp_v3/panel_backing.png")
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		backing.set_texture_margin(side, 64)
		backing.set_content_margin(side, 30)
	_cabinet.add_theme_stylebox_override("panel", backing)
	add_child(_cabinet)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 20)
	_cabinet.add_child(layout)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	layout.add_child(header)
	var gear := TextureRect.new()
	gear.name = "SettingsGear"
	gear.texture = Plate.tex("construct_settings")
	gear.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gear.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	gear.custom_minimum_size = Vector2(70, 70)
	gear.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(gear)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(titles)
	var title: Control = Title.new()
	title.set("text", "Settings")
	titles.add_child(title)
	titles.add_child(Parts.caption("Control cabinet", 16))
	var close: TextureButton = Key.make("close", 36)
	close.tooltip_text = "Close without applying"
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(_on_back_pressed)
	header.add_child(close)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 26)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(body)
	var rail: MarginContainer = Section.new()
	rail.name = "SettingsSelectorPlate"
	rail.set("style", "plate")
	rail.custom_minimum_size.x = 220
	rail.size_flags_horizontal = Control.SIZE_FILL
	body.add_child(rail)
	var selectors: VBoxContainer = rail.get("content")
	selectors.add_theme_constant_override("separation", 16)
	var legend := Parts.caption("Settings", 18)
	legend.add_theme_color_override("font_color", Plate.NAVY)
	legend.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.3))
	selectors.add_child(legend)

	_tabs = TabContainer.new()
	_tabs.name = "SettingsPages"
	_tabs.tabs_visible = false
	_tabs.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_child(_build_gameplay_tab())
	_tabs.add_child(_build_audio_tab())
	_tabs.add_child(_build_graphics_tab())
	_tabs.add_child(_build_controls_tab())
	_tabs.add_child(_build_telemetry_tab())
	body.add_child(_tabs)
	for i in _tabs.get_tab_count():
		var tab_index: int = i
		var key := CreamKey.make("Settings" + _tabs.get_tab_title(i), _tabs.get_tab_title(i), "", 174)
		key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		key.focus_mode = Control.FOCUS_ALL
		key.pressed.connect(func() -> void: _tabs.current_tab = tab_index)
		selectors.add_child(key)
		_tab_keys.append(key)
	_tabs.tab_changed.connect(_sync_tab_keys)
	_tabs.current_tab = 1
	_sync_tab_keys(1)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 18)
	layout.add_child(footer)
	footer.add_child(_make_button("Back", false, _on_back_pressed))
	var note := Parts.body("Changes take effect when you select Apply.")
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_child(note)
	footer.add_child(_make_button("Apply", true, _on_apply_pressed))
	_style_widgets()
	resized.connect(_place_cabinet)
	_place_cabinet()
	LampOverlay.attach(_cabinet)
	PanelStack.push(self)
	visibility_changed.connect(_on_visibility_changed)


func _place_cabinet() -> void:
	if _cabinet == null: return
	var available := get_viewport_rect().size - Vector2(72, 72)
	_cabinet.size = Vector2(minf(1480, available.x), minf(960, available.y))
	_cabinet.position = (get_viewport_rect().size - _cabinet.size) * 0.5


func _sync_tab_keys(index: int) -> void:
	for i in _tab_keys.size():
		_tab_keys[i].set("chosen", i == index)


func _control_plate(title: String, node_name: String, style := "slab") -> MarginContainer:
	var section: MarginContainer = Section.new()
	section.name = node_name
	section.set("style", style)
	var content: VBoxContainer = section.get("content")
	content.add_theme_constant_override("separation", 18)
	if title != "": content.add_child(Parts.heading(title))
	return section


func _add_scroll_plate(tab: Control, plate: Control) -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab.add_child(scroll)
	plate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(plate)


## Reuse the kit's cream caps and physical slider knobs, retaining Godot's native input.
func _style_widgets() -> void:
	for option in find_children("*", "OptionButton", true, false):
		PreferencesKit.key_control(option)
	for slider in find_children("*", "HSlider", true, false):
		slider.custom_minimum_size.y = 48
		for icon in ["grabber", "grabber_highlight", "grabber_disabled"]:
			slider.add_theme_icon_override(icon, Plate.tex("toggle_knob"))
		var track := StyleBoxFlat.new()
		track.bg_color = Color("#080f16")
		track.border_color = Color("#6c7276")
		track.set_border_width_all(2)
		track.set_corner_radius_all(4)
		track.content_margin_top = 5
		track.content_margin_bottom = 5
		slider.add_theme_stylebox_override("slider", track)
		var fill := track.duplicate() as StyleBoxFlat
		fill.bg_color = Color("#bda06b")
		slider.add_theme_stylebox_override("grabber_area", fill)
		slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	for scroll in find_children("*", "ScrollContainer", true, false):
		Scroll.apply(scroll, true)
	for button in _bind_buttons.values(): PreferencesKit.key_control(button)


# --- Tab builders ------------------------------------------------------------

func _build_telemetry_tab() -> Control:
	var tab := MarginContainer.new()
	tab.name = "Telemetry"
	for side in ["left", "right", "top", "bottom"]:
		tab.add_theme_constant_override("margin_" + side, 12)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 24)
	scroll.add_child(col)
	var reporting := _control_plate("Telemetry", "TelemetryReportingPlate")
	col.add_child(reporting)
	var reporting_rows: VBoxContainer = reporting.get("content")
	reporting_rows.add_child(Parts.body("Choose which gameplay reports you send to the developer."))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var label := Parts.caption("Send data to developer:", 17)
	label.uppercase = false
	row.add_child(label)
	_telemetry_option = OptionButton.new()
	_telemetry_option.add_item("Send critical data for balancing")
	_telemetry_option.add_item("Send no data to developer")
	_telemetry_option.select(1 if PlayerProfile.telemetry_opt_out else 0)
	_telemetry_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_telemetry_option)
	row.add_child(_info_badge(TELEMETRY_HINT))
	reporting_rows.add_child(row)
	reporting_rows.add_child(Parts.body("A basic launch event is still sent in either mode. Your choice takes effect when you select Apply."))

	var identity := _control_plate("", "TelemetryIdentityPlate", "plate")
	col.add_child(identity)
	var identity_rows: VBoxContainer = identity.get("content")
	var id_label := Parts.caption("User ID:", 20)
	id_label.uppercase = false
	id_label.add_theme_color_override("font_color", Plate.NAVY)
	id_label.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.35))
	identity_rows.add_child(id_label)
	var id_row := HBoxContainer.new()
	id_row.add_theme_constant_override("separation", 18)
	identity_rows.add_child(id_row)
	var identifier := LineEdit.new()
	identifier.name = "TelemetryUserID"
	identifier.text = PlayerProfile.get_telemetry_player_id()
	identifier.editable = false
	identifier.add_theme_color_override("font_uneditable_color", OFF_WHITE)
	identifier.add_theme_font_override("font", UIFonts.mono())
	identifier.add_theme_font_size_override("font_size", 22)
	identifier.custom_minimum_size.y = 52
	var readout := StyleBoxFlat.new()
	readout.bg_color = Plate.NAVY.darkened(0.6)
	readout.border_color = Color("#151b20")
	readout.set_border_width_all(3)
	readout.set_content_margin_all(12)
	readout.set_corner_radius_all(4)
	identifier.add_theme_stylebox_override("normal", readout)
	identifier.add_theme_stylebox_override("read_only", readout)
	identifier.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_row.add_child(identifier)
	var copy := CreamKey.make("CopyUserID", "Copy ID", "", 130)
	copy.focus_mode = Control.FOCUS_ALL
	copy.pressed.connect(func() -> void: DisplayServer.clipboard_set(identifier.text))
	id_row.add_child(copy)
	var explanation_heading := Parts.caption("What's this?", 20)
	explanation_heading.uppercase = false
	explanation_heading.add_theme_color_override("font_color", Plate.NAVY)
	explanation_heading.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.35))
	identity_rows.add_child(explanation_heading)
	var explanation := Parts.body(TELEMETRY_ID_EXPLANATION)
	explanation.name = "TelemetryUserIDExplanation"
	explanation.add_theme_color_override("font_color", Plate.NAVY)
	explanation.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.35))
	identity_rows.add_child(explanation)
	return tab


func _build_audio_tab() -> Control:
	var tab := MarginContainer.new()
	tab.name = "Audio"
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		tab.add_theme_constant_override(side, 24)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 22)
	col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var plate := _control_plate("Audio levels", "AudioControlPlate")
	_add_scroll_plate(tab, plate)
	(plate.get("content") as VBoxContainer).add_child(col)

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

	var readout: Control = Drum.new(38, 3, int(slider.value))
	row.add_child(readout)
	row.add_child(Parts.caption("%", 18))
	slider.value_changed.connect(func(v: float) -> void:
		readout.set("value", int(round(v)))
		readout.queue_redraw())
	return row


func _build_gameplay_tab() -> Control:
	var tab := MarginContainer.new()
	tab.name = "Gameplay"
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		tab.add_theme_constant_override(side, 24)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var plate := _control_plate("Gameplay", "GameplayControlPlate")
	_add_scroll_plate(tab, plate)
	(plate.get("content") as VBoxContainer).add_child(col)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var name_label := Label.new()
	name_label.text = "Test setting"
	name_label.theme_type_variation = &"Body"
	name_label.custom_minimum_size = Vector2(140, 0)
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name_label)
	_test_knob = RotarySelector.new()
	_test_knob.set_value_no_signal(test_setting)
	row.add_child(_test_knob)
	col.add_child(row)
	col.add_child(_build_test_gauge_row())
	return tab


## A panel gauge with a control for each of its attributes. It is a live preview: nothing
## here is staged, applied or saved.
func _build_test_gauge_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var name_label := Label.new()
	name_label.text = "Test gauge"
	name_label.theme_type_variation = &"Body"
	name_label.custom_minimum_size = Vector2(140, 0)
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name_label)

	_test_gauge = PanelGauge.new()
	_test_gauge.gauge_size = 220.0
	_test_gauge.value = 0.3
	_test_gauge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_test_gauge)

	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	controls.custom_minimum_size = Vector2(340, 0)
	controls.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(controls)

	var red_value := Label.new()
	var show_red := func() -> void:
		red_value.text = "%d%%" % roundi(100.0 - _test_gauge.green_percent - _test_gauge.amber_percent)
	controls.add_child(_gauge_slider_row("Needle", _test_gauge.value * 100.0, "%d", func(v: float) -> void:
		_test_gauge.value = v / 100.0))
	# Built before the green row because the green row's callback needs its slider (lambdas
	# capture locals by value, so it has to exist when that callback is created).
	var amber_row := _gauge_slider_row("Amber", _test_gauge.amber_percent, "%d%%", func(v: float) -> void:
		_test_gauge.amber_percent = minf(v, 100.0 - _test_gauge.green_percent)
		show_red.call())
	var amber_slider := amber_row.get_child(1) as HSlider
	controls.add_child(_gauge_slider_row("Green", _test_gauge.green_percent, "%d%%", func(v: float) -> void:
		_test_gauge.green_percent = v
		# Amber can only fill what green leaves; pull it back so the three still add to 100.
		if _test_gauge.green_percent + _test_gauge.amber_percent > 100.0:
			amber_slider.value = 100.0 - _test_gauge.green_percent
		show_red.call()))
	controls.add_child(amber_row)

	var red_row := HBoxContainer.new()
	red_row.add_theme_constant_override("separation", 12)
	var red_label := Label.new()
	red_label.text = "Red"
	red_label.theme_type_variation = &"Body"
	red_label.custom_minimum_size = Vector2(70, 0)
	red_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	red_row.add_child(red_label)
	red_value.theme_type_variation = &"Numeric"
	red_value.custom_minimum_size = Vector2(52, 0)
	red_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	red_row.add_child(red_value)
	controls.add_child(red_row)
	show_red.call()

	var led_row := HBoxContainer.new()
	led_row.add_theme_constant_override("separation", 12)
	var led_label := Label.new()
	led_label.text = "LED"
	led_label.theme_type_variation = &"Body"
	led_label.custom_minimum_size = Vector2(70, 0)
	led_row.add_child(led_label)
	var led_option := OptionButton.new()
	for item: String in ["Follows the needle's zone", "Green", "Amber", "Red", "Off"]:
		led_option.add_item(item)
	led_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	led_option.item_selected.connect(func(i: int) -> void:
		_test_gauge.led_mode = i)
	led_row.add_child(led_option)
	var flash_check := CheckBox.new()
	flash_check.text = "Flash"
	flash_check.toggled.connect(func(on: bool) -> void:
		_test_gauge.flash = on)
	led_row.add_child(flash_check)
	controls.add_child(led_row)
	return row


func _gauge_slider_row(label_text: String, initial: float, fmt: String, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = label_text
	label.theme_type_variation = &"Body"
	label.custom_minimum_size = Vector2(70, 0)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = initial
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var readout := Label.new()
	readout.theme_type_variation = &"Numeric"
	readout.custom_minimum_size = Vector2(52, 0)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	readout.text = fmt % roundi(initial)
	row.add_child(readout)
	slider.value_changed.connect(func(v: float) -> void:
		readout.text = fmt % roundi(v)
		on_change.call(v))
	return row


func _build_graphics_tab() -> Control:
	var tab := MarginContainer.new()
	tab.name = "Graphics"
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		tab.add_theme_constant_override(side, 24)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var plate := _control_plate("Display and rendering", "GraphicsControlPlate")
	_add_scroll_plate(tab, plate)
	(plate.get("content") as VBoxContainer).add_child(col)

	# Monitor picker — only meaningful with more than one display (laptop + external). Lets
	# the player put the game on the right screen; fullscreen then fills THAT monitor.
	if DisplayServer.get_screen_count() > 1:
		var scr_row := HBoxContainer.new()
		scr_row.add_theme_constant_override("separation", 16)
		scr_row.custom_minimum_size = Vector2(0, 40)
		var scr_label := Label.new()
		scr_label.text = "Monitor"
		scr_label.theme_type_variation = &"Body"
		scr_label.custom_minimum_size = Vector2(140, 0)
		scr_row.add_child(scr_label)
		_screen_option = OptionButton.new()
		for i in DisplayServer.get_screen_count():
			var sz := DisplayServer.screen_get_size(i)
			var tag := "  (primary)" if i == DisplayServer.get_primary_screen() else ""
			_screen_option.add_item("Screen %d — %d × %d%s" % [i + 1, sz.x, sz.y, tag])
		var cur_screen := PlayerProfile.screen_index
		if cur_screen < 0 or cur_screen >= DisplayServer.get_screen_count():
			cur_screen = DisplayServer.window_get_current_screen()
		_screen_option.select(cur_screen)
		_screen_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_screen_option.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		scr_row.add_child(_screen_option)
		col.add_child(scr_row)

	# Fullscreen toggle — the reliable "fill the whole screen" control. A windowed pick
	# smaller than the monitor only floats centred, so fullscreen is what actually fills.
	var fs_row := HBoxContainer.new()
	fs_row.add_theme_constant_override("separation", 16)
	fs_row.custom_minimum_size = Vector2(0, 40)
	var fs_label := Label.new()
	fs_label.text = "Fullscreen"
	fs_label.theme_type_variation = &"Body"
	fs_label.custom_minimum_size = Vector2(140, 0)
	fs_row.add_child(fs_label)
	_fullscreen_check = PreferencesKit.slide_checkbox(PlayerProfile.fullscreen)
	_fullscreen_check.button_pressed = PlayerProfile.fullscreen
	_fullscreen_check.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	fs_row.add_child(_fullscreen_check)
	var fullscreen_state := Parts.caption("On" if _fullscreen_check.button_pressed else "Off", 17)
	fs_row.add_child(fullscreen_state)
	_fullscreen_check.toggled.connect(func(on: bool) -> void: fullscreen_state.text = "On" if on else "Off")
	col.add_child(fs_row)

	# Resolution row: label + dropdown, mirroring the audio slider-row layout. It sets the
	# WINDOWED size, so it's greyed out while Fullscreen is on.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.custom_minimum_size = Vector2(0, 40)
	var name_label := Label.new()
	name_label.text = "Window size"
	name_label.theme_type_variation = &"Body"
	name_label.custom_minimum_size = Vector2(140, 0)
	row.add_child(name_label)

	_resolution_option = OptionButton.new()
	for res: Vector2i in RESOLUTIONS:
		_resolution_option.add_item("%d × %d" % [res.x, res.y])
	_resolution_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resolution_option.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_resolution_option.select(_current_resolution_index())
	_resolution_option.disabled = _fullscreen_check.button_pressed
	row.add_child(_resolution_option)
	col.add_child(row)

	# Fullscreen owns the screen, so the windowed-size picker is only live when it's off.
	_fullscreen_check.toggled.connect(func(on: bool) -> void:
		_resolution_option.disabled = on)

	var hint := Label.new()
	hint.text = "Fullscreen fills the selected monitor. Turn it off to run in a window at the size below — always clamped to fit the screen (3440 × 1440 is ultrawide 21:9; the others are 16:9)."
	hint.theme_type_variation = &"Caption"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(OFF_WHITE.r, OFF_WHITE.g, OFF_WHITE.b, 0.6))
	col.add_child(hint)
	col.add_child(_build_quality_row())
	return tab


## Quality preset: a dropdown and an info badge whose hover explains the presets.
func _build_quality_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.custom_minimum_size = Vector2(0, 40)
	var label := Label.new()
	label.text = "Quality preset"
	label.theme_type_variation = &"Body"
	label.custom_minimum_size = Vector2(140, 0)
	row.add_child(label)
	_quality_option = OptionButton.new()
	for preset: Array in QUALITY_PRESETS:
		_quality_option.add_item(str(preset[1]))
		if preset[0] == PlayerProfile.graphics_quality:
			_quality_option.select(_quality_option.item_count - 1)
	_quality_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quality_option.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_quality_option)
	row.add_child(_info_badge(QUALITY_HINT))
	return row


## A round "i" with a hover explanation. A plain letter, because no shipped font has "ⓘ".
func _info_badge(text: String) -> Button:
	var badge: Button = preload("res://scripts/info_button.gd").new()
	badge.text = "i"
	badge.tooltip_text = text
	badge.focus_mode = Control.FOCUS_NONE
	badge.custom_minimum_size = Vector2(26, 26)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ring := StyleBoxFlat.new()
	ring.bg_color = Color(0, 0, 0, 0)
	ring.border_color = OFF_WHITE
	ring.set_border_width_all(2)
	ring.set_corner_radius_all(13)
	for state in ["normal", "hover", "pressed", "focus"]:
		badge.add_theme_stylebox_override(state, ring)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		badge.add_theme_color_override(state, OFF_WHITE)
	return badge


# Index into RESOLUTIONS of the currently-applied (or saved) window size, else 0 (1920×1080).
func _current_resolution_index() -> int:
	var cur := PlayerProfile.window_size
	if cur.x <= 0 and DisplayServer.get_name() != "headless":
		cur = DisplayServer.window_get_size()
	for i in RESOLUTIONS.size():
		if RESOLUTIONS[i] == cur:
			return i
	return 0




# --- Controls tab ------------------------------------------------------------
#
# The demo shows the scheme and lets the player change ONE part of it: the map-mode
# hotkeys, which ship unbound. Everything else is listed read-only and says so on hover,
# because a rebinding screen that half works is worse than one that is honest about not
# working yet.
#
# Edits are STAGED in _pending_binds and only written on Apply, matching the audio sliders
# and the display settings — backing out of Settings changes nothing.

const DEMO_LOCKED_HINT := "Not editable in the demo"
## Reading width for the key list. Left to fill the tab, a row on a 3440px ultrawide puts
## its key most of a metre from its label, which is not a table any more.
const CONTROLS_WIDTH := 720

var _pending_binds: Dictionary = {}      # mapmode id -> keycode, staged until Apply
var _bind_buttons: Dictionary = {}       # mapmode id -> Button
var _listening_for: String = ""          # mapmode id currently capturing a key, "" if none
var _listening_frame: int = -1            # frame the capture began, see _input
var _bind_errors: Dictionary = {}         # mapmode id -> Label, inline beside its field


func _build_controls_tab() -> Control:
	var tab := MarginContainer.new()
	tab.name = "Controls"
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		tab.add_theme_constant_override(side, 24)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab.add_child(scroll)

	# Centred at a fixed reading width rather than stretched to the panel.
	var centre := CenterContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(centre)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.custom_minimum_size = Vector2(CONTROLS_WIDTH, 0)
	var plate := _control_plate("Controls", "ControlsPlate")
	centre.add_child(plate)
	(plate.get("content") as VBoxContainer).add_child(col)

	_pending_binds = Keybinds.mapmode_bindings()
	_bind_buttons.clear()
	_listening_for = ""

	var group := ""
	for row: Dictionary in Keybinds.FIXED:
		if str(row.group) != group:
			group = str(row.group)
			col.add_child(_controls_heading(group))
		col.add_child(_fixed_row(str(row.label), str(row.keys)))

	col.add_child(_controls_heading(Keybinds.GROUP_MAPMODES))
	var note := Label.new()
	note.theme_type_variation = &"Caption"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(CONTROLS_WIDTH, 0)
	note.text = "Map modes start unbound. Click a key field and press the key you want."
	col.add_child(note)
	for m: Dictionary in Keybinds.MAPMODES:
		col.add_child(_bindable_row(str(m.id), str(m.label)))

	return tab


func _controls_heading(text: String) -> Control:
	var l := Label.new()
	l.text = text.to_upper()
	l.theme_type_variation = &"Section"
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", OFF_WHITE)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", 14)
	pad.add_child(l)
	return pad


## Label on the left, key on the right. The whole row carries the hover hint, so a player
## who tries to click the key finds out why nothing happens.
func _fixed_row(label: String, keys: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.tooltip_text = DEMO_LOCKED_HINT
	row.mouse_filter = Control.MOUSE_FILTER_STOP   # a PASS row never shows its own tooltip
	var name_label := Label.new()
	name_label.text = label
	name_label.theme_type_variation = &"Body"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_label)
	var key_label := Label.new()
	key_label.text = keys
	key_label.theme_type_variation = &"Numeric"
	key_label.add_theme_color_override("font_color", DS.PALETTE.TEXT_DIM)
	key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(key_label)
	return row


func _bindable_row(id: String, label: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var name_label := Label.new()
	name_label.text = label
	name_label.theme_type_variation = &"Body"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var button := Button.new()
	button.custom_minimum_size = Vector2(150, 0)
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = "Click, then press a key"
	button.pressed.connect(_on_bind_pressed.bind(id))
	row.add_child(button)
	_bind_buttons[id] = button
	# The refusal belongs BESIDE the field it refused, not in a shared line at the foot of
	# the list where it reads as a statement about the whole tab.
	var err := Label.new()
	err.theme_type_variation = "Caption"
	err.add_theme_font_size_override("font_size", DS.FS.CAPTION - 2)
	err.add_theme_color_override("font_color", DS.PALETTE.DANGER)
	err.custom_minimum_size = Vector2(300, 0)
	err.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	err.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	err.text = ""
	row.add_child(err)
	_bind_errors[id] = err
	_refresh_bind_button(id)
	return row


func _refresh_bind_button(id: String) -> void:
	var button := _bind_buttons.get(id) as Button
	if button == null:
		return
	if _listening_for == id:
		button.text = "Press a key…"
		return
	button.text = Keybinds.key_name(int(_pending_binds.get(id, 0)))


func _on_bind_pressed(id: String) -> void:
	var previous := _listening_for
	_listening_for = id
	_listening_frame = int(Engine.get_process_frames())
	_clear_bind_errors()
	if previous != "":
		_refresh_bind_button(previous)
	_refresh_bind_button(id)


## Captured here rather than on the button so the key never reaches the game underneath,
## and so Esc can cancel a capture instead of closing the whole settings panel.
##
## Mouse buttons come through here too, and are refused by the same validator the keys go
## through — otherwise a mouse press would simply fall past this and leave the field stuck
## waiting. The frame guard is for the click that STARTED the capture: the button emits
## `pressed` on release, and that release is still travelling when listening begins.
func _input(event: InputEvent) -> void:
	if _listening_for == "":
		return
	var id := _listening_for
	if event is InputEventMouseButton:
		if not (event as InputEventMouseButton).pressed:
			return
		if int(Engine.get_process_frames()) == _listening_frame:
			return   # the click that opened this capture
		get_viewport().set_input_as_handled()
		_reject_bind(id, Keybinds.MSG_UNUSABLE)
		return
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	get_viewport().set_input_as_handled()
	# Escape cancels rather than erroring. It can never BE a binding either (keybinds.gd
	# refuses it), but inside a menu it is the way out, and taking that away to show a
	# message would be a worse trade than simply not binding it.
	if k.keycode == KEY_ESCAPE:
		_listening_for = ""
		_refresh_bind_button(id)
		return
	var verdict: Dictionary = Keybinds.validate(k, id)
	if not bool(verdict.ok):
		_reject_bind(id, str(verdict.message))
		return
	_pending_binds[id] = int(k.keycode)
	_clear_bind_errors()
	_listening_for = ""
	_refresh_bind_button(id)


func _clear_bind_errors() -> void:
	for l in _bind_errors.values():
		(l as Label).text = ""


func _set_bind_error(id: String, message: String) -> void:
	_clear_bind_errors()
	var l := _bind_errors.get(id) as Label
	if l != null:
		l.text = message


## Stop listening and say why, leaving the field on whatever it held before.
func _reject_bind(id: String, message: String) -> void:
	_set_bind_error(id, message)
	_listening_for = ""
	_refresh_bind_button(id)

# --- Buttons / lifecycle -----------------------------------------------------

func _make_button(text: String, primary: bool, handler: Callable) -> Button:
	var button := CreamKey.make(text + "Settings", text, "", 170)
	if primary: button.set("rim", "brass")
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(handler)
	return button


func _on_apply_pressed() -> void:
	_apply_telemetry_preference()
	if _test_knob != null:
		test_setting = int(_test_knob.value)
	# Controls: the staged map-mode hotkeys. Fixed bindings are read-only in the demo, so
	# there is nothing else here to write.
	Keybinds.set_mapmode_bindings(_pending_binds)
	# Audio: apply live, then persist the slider positions so they survive a restart.
	var levels: Dictionary = {}
	for bus: StringName in _sliders:
		var v: float = (_sliders[bus] as HSlider).value
		Audio.set_bus_percent(bus, v)
		levels[str(bus)] = v
	PlayerProfile.set_audio_levels(levels)
	# Display: commit monitor + fullscreen + the windowed size together.
	if _fullscreen_check != null:
		var size := PlayerProfile.window_size
		if _resolution_option != null:
			var idx := _resolution_option.selected
			if idx >= 0 and idx < RESOLUTIONS.size():
				size = RESOLUTIONS[idx]
		var screen := PlayerProfile.screen_index
		if _screen_option != null:
			screen = _screen_option.selected
		PlayerProfile.set_display(_fullscreen_check.button_pressed, size, screen)
	# Quality: read by the next loading screen.
	if _quality_option != null and _quality_option.selected >= 0:
		PlayerProfile.set_graphics_quality(str(QUALITY_PRESETS[_quality_option.selected][0]))
	hide()


func _apply_telemetry_preference() -> void:
	if _telemetry_option != null:
		PlayerProfile.set_telemetry_opt_out(_telemetry_option.selected == 1)


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
