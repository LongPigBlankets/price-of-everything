extends Node
## Render the actual Settings screen in an isolated profile.
const Settings := preload("res://scripts/settings_panel.gd")
const AppPaths := preload("res://scripts/app_paths.gd")
var output := ""
var results := {}
func _ready() -> void:
	output = OS.get_environment("SETTINGS_REVIEW_OUTPUT")
	if output == "" or not OS.get_cmdline_user_args().has("--no-telemetry"):
		push_error("Set SETTINGS_REVIEW_OUTPUT and pass --no-telemetry")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	AppPaths._base = output.path_join("isolated-profile")
	PlayerProfile.telemetry_notice_seen = true
	# Avoid opening a native tooltip while the scripted window resize is in flight.
	get_viewport().warp_mouse(Vector2(2, 2))
	print("[settings-review] construct menu")
	var menu: Node = load("res://scenes/main_menu.tscn").instantiate()
	add_child(menu)
	await _settle(100)
	print("[settings-review] resize")
	get_viewport().warp_mouse(Vector2(2, 2))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	get_window().size = Vector2i(1920, 1080) if OS.get_environment("SETTINGS_REVIEW_LARGE") == "1" else Vector2i(1280, 800)
	await _settle(40)
	# Keep incidental hover tooltips out of the layout captures while pages switch.
	get_viewport().warp_mouse(Vector2(2, 2))
	print("[settings-review] open settings")
	var panel := Settings.open(menu)
	await _settle(8)
	for index in [4, 1, 2, 3, 0]:
		print("[settings-review] select page ", index)
		panel._tab_keys[index].pressed.emit()
		await _settle(8)
		assert(panel._tabs.current_tab == index)
		if index == 2:
			var original := panel._fullscreen_check.button_pressed
			panel._fullscreen_check.button_pressed = false
			assert(not panel._resolution_option.disabled)
			panel._fullscreen_check.button_pressed = true
			assert(panel._resolution_option.disabled)
			panel._fullscreen_check.button_pressed = original
			results["fullscreen_switch_controls_resolution"] = true
		await _capture("settings-" + panel._tabs.get_tab_title(index).to_lower())
	panel._tabs.current_tab = 4
	await _settle(3)
	var identifier := panel.find_child("TelemetryUserID", true, false) as LineEdit
	var identity_plate := panel.find_child("TelemetryIdentityPlate", true, false)
	results["id_explanation_on_same_plate"] = identity_plate.is_ancestor_of(panel.find_child("TelemetryUserIDExplanation", true, false))
	assert(results.id_explanation_on_same_plate)
	var actual_id := identifier.text
	identifier.text = "0123456789abcdef0123456789abcdef"
	await _capture("settings-user-id-layout")
	results["long_id_fits"] = identifier.get_theme_font("font").get_string_size(identifier.text, HORIZONTAL_ALIGNMENT_LEFT, -1, identifier.get_theme_font_size("font_size")).x + 30 < identifier.size.x
	assert(results.long_id_fits)
	identifier.text = actual_id
	results["cabinet_fits_viewport"] = get_viewport().get_visible_rect().encloses(panel._cabinet.get_global_rect())
	assert(results.cabinet_fits_viewport)
	panel._on_back_pressed()
	await _settle(5)
	var file := FileAccess.open(output.path_join("validation.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))
	file.close()
	get_tree().quit()
func _settle(frames: int) -> void:
	for i in frames: await get_tree().process_frame
func _capture(label: String) -> void:
	await _settle(3)
	RenderingServer.force_draw(false)
	var screenshot := get_viewport().get_texture().get_image()
	screenshot.save_png(output.path_join(label + ".png"))
	print("[settings-review] ", label, " ", screenshot.get_size())
