extends Node
## Render the actual menu notice/settings and verify persistence in an isolated profile.
const AppPaths := preload("res://scripts/app_paths.gd")
const Settings := preload("res://scripts/settings_panel.gd")
const Profile := preload("res://scripts/player_profile.gd")
var output := ""
var results := {}


func _ready() -> void:
	output = OS.get_environment("TELEMETRY_REVIEW_OUTPUT")
	if output == "" or not OS.get_cmdline_user_args().has("--no-telemetry"):
		push_error("Set TELEMETRY_REVIEW_OUTPUT and pass --no-telemetry")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	AppPaths._base = output.path_join("isolated-profile")
	PlayerProfile.telemetry_notice_seen = false
	PlayerProfile.telemetry_opt_out = false
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	get_window().size = Vector2i(1280, 800)
	var menu: Node = load("res://scenes/main_menu.tscn").instantiate()
	add_child(menu)
	await _settle(100)
	# Menu startup restores display preferences; size the review after that restore.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	get_window().size = Vector2i(1280, 800)
	await _settle(40)
	await _capture("first-menu-notice")
	var notice: Node = menu.get_node_or_null("TelemetryNotice")
	if notice == null:
		for child in menu.get_children():
			if child.get_script() == preload("res://scripts/telemetry_notice.gd"):
				notice = child
				break
	assert(notice != null)
	notice.understood_button.pressed.emit()
	await _settle(3)
	var panel := Settings.open(menu)
	for tabs in panel.find_children("*", "TabContainer", true, false):
		for i in tabs.get_tab_count():
			if tabs.get_tab_title(i) == "Telemetry": tabs.current_tab = i
	await _settle(8)
	await _capture("telemetry-settings")
	for badge in panel.find_children("*", "Button", true, false):
		if badge.text == "i" and badge.is_visible_in_tree():
			var tip: Control = badge.call("_make_custom_tooltip", badge.tooltip_text)
			panel.add_child(tip)
			await _settle(2)
			tip.position = Vector2(maxf(40, badge.global_position.x - tip.size.x), badge.global_position.y + 34)
			await _capture("telemetry-tooltip")
			tip.queue_free()
			break
	panel._telemetry_option.select(1)
	panel._apply_telemetry_preference()
	var persisted := Profile.new()
	persisted._load()
	results["notice_seen_after_reload"] = persisted.telemetry_notice_seen
	results["opt_out_after_reload"] = persisted.telemetry_opt_out
	persisted.free()
	assert(results.notice_seen_after_reload and results.opt_out_after_reload)
	panel._telemetry_option.select(0)
	panel._apply_telemetry_preference()
	persisted = Profile.new()
	persisted._load()
	results["opt_in_after_reload"] = not persisted.telemetry_opt_out
	assert(results.opt_in_after_reload)
	persisted.free()
	var file := FileAccess.open(output.path_join("validation.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))
	file.close()
	get_tree().quit()


func _settle(frames: int) -> void:
	for i in frames: await get_tree().process_frame


func _capture(name: String) -> void:
	await _settle(3)
	RenderingServer.force_draw(false)
	var image := get_viewport().get_texture().get_image()
	image.save_png(output.path_join(name + ".png"))
	print("[telemetry-review] ", name, " ", image.get_size())
