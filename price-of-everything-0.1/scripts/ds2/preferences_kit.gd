extends RefCounted
## The Settings native controls wear the DS2 cream keycaps.
const Plate := preload("res://scripts/bdp_v3_plate.gd")


static func key_control(control: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var cap := StyleBoxTexture.new()
		cap.texture = Plate.tex("tile_key_pressed" if state == "pressed" else "tile_key")
		cap.texture_margin_left = 32
		cap.texture_margin_right = 32
		cap.texture_margin_top = 0
		cap.texture_margin_bottom = 0
		cap.content_margin_left = 22
		cap.content_margin_right = 36 if control is OptionButton else 22
		cap.content_margin_top = 10
		cap.content_margin_bottom = 10
		cap.modulate_color = Color(1.08, 1.08, 1.08) if state == "hover" else (Color(0.62, 0.62, 0.62) if state == "disabled" else Color.WHITE)
		control.add_theme_stylebox_override(state, cap)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		control.add_theme_color_override(state, Plate.NAVY)
	control.add_theme_color_override("font_disabled_color", Color("#626566"))
	control.add_theme_font_override("font", Plate.FONT_SEMI)
	control.add_theme_font_size_override("font_size", 18)
	control.custom_minimum_size.y = 46


## A native checkbox with the Labour panel's two-way mechanical switch as its face.
## Keyboard focus, toggling and the Settings staged value remain native CheckBox behavior.
static func slide_checkbox(value: bool) -> CheckBox:
	var checkbox := CheckBox.new()
	checkbox.button_pressed = value
	checkbox.custom_minimum_size = Vector2(112, 46)
	var transparent := GradientTexture2D.new()
	transparent.width = 1
	transparent.height = 1
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color.TRANSPARENT, Color.TRANSPARENT])
	transparent.gradient = gradient
	for icon in ["checked", "unchecked", "checked_disabled", "unchecked_disabled"]:
		checkbox.add_theme_icon_override(icon, transparent)
	var switch: Control = load("res://scripts/bdp_v3_toggle.gd").new()
	switch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	switch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	switch.call("set_right", value)
	checkbox.add_child(switch)
	checkbox.toggled.connect(func(on: bool) -> void: switch.call("set_right", on))
	return checkbox
