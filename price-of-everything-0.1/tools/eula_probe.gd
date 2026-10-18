extends Node
## Fresh-process startup/accept/decline probe and bounded windowed capture.
## Always use --no-telemetry and an isolated --acceptance-file outside player data.

const Harness := preload("res://tools/shot_harness.gd")
const Agreement := preload("res://scripts/demo_eula.gd")

var _action: String = "show"
var _record: String = ""
var _captures: String = ""


func _ready() -> void:
	Harness.prepare_window(get_window())
	Harness.arm_watchdog(self, 90.0)
	AudioServer.set_bus_mute(0, true)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--eula-action="):
			_action = argument.trim_prefix("--eula-action=")
		elif argument.begins_with("--acceptance-file="):
			_record = argument.trim_prefix("--acceptance-file=")
		elif argument.begins_with("--capture-dir="):
			_captures = argument.trim_prefix("--capture-dir=")
	if _record.is_empty() or not OS.get_cmdline_user_args().has("--no-telemetry"):
		push_error("eula probe requires an isolated acceptance file and --no-telemetry")
		get_tree().quit(1)
		return
	await get_tree().process_frame
	var startup: Control = load("res://scenes/demo_startup.tscn").instantiate()
	startup.acceptance_file = _record
	get_tree().root.add_child(startup)
	get_tree().current_scene = startup
	await get_tree().process_frame
	await get_tree().process_frame
	if _action == "relaunch":
		await _assert_menu()
		return
	var screen: Control = startup.get_node_or_null("EulaScreen")
	if screen == null or get_tree().current_scene != startup:
		push_error("eula probe: unaccepted launch did not stop before the main menu")
		get_tree().quit(1)
		return
	print("[EULA PROBE] agreement_ready; accepted=%s; telemetry=%s" % [Agreement.is_accepted(_record), TelemetryState.enabled])
	print("[EULA PROBE] viewport=%s texture=%s startup=%s screen=%s panel=%s document=%s scroll=%s/%s" % [
		get_viewport().get_visible_rect(), get_viewport().get_texture().get_size(), startup.size,
		screen.size, screen.get_node("AgreementPanel").get_rect(), screen.document.get_global_rect(),
		screen.document.get_v_scroll_bar().value, screen.document.get_v_scroll_bar().max_value])
	print("[EULA PROBE] document fit_content=%s minimum=%s panel_min=%s" % [screen.document.fit_content,
		screen.document.get_combined_minimum_size(), screen.get_node("AgreementPanel").get_combined_minimum_size()])
	await _capture("eula-top.png")
	screen.document.get_v_scroll_bar().value = screen.document.get_v_scroll_bar().max_value
	await _capture("eula-bottom.png")
	match _action:
		"accept":
			screen.accept_button.pressed.emit()
			await _assert_menu()
		"decline":
			print("[EULA PROBE] decline; acceptance_file_exists=%s" % FileAccess.file_exists(_record))
			screen.close_button.pressed.emit()
		"show":
			get_tree().quit(0)
		_:
			push_error("Unknown eula probe action")
			get_tree().quit(1)


func _assert_menu() -> void:
	while get_tree().current_scene == null or get_tree().current_scene.name != "MainMenu":
		await get_tree().process_frame
	if not Agreement.is_accepted(_record):
		push_error("eula probe: menu opened without persistent acceptance")
		get_tree().quit(1)
		return
	# The menu warms map assets asynchronously. Do not kill the loader mid-read
	# and mistake teardown errors for startup failures.
	for dependency: String in ResourceLoader.get_dependencies("res://scenes/main.tscn"):
		var at := dependency.rfind("res://")
		if at < 0:
			continue
		var path := dependency.substr(at)
		if path.ends_with(".gd") or path.ends_with(".tscn"):
			continue
		while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await get_tree().process_frame
		if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
			ResourceLoader.load_threaded_get(path)
	await _capture("accepted-main-menu.png")
	print("[EULA PROBE] menu_ready; accepted=true")
	get_tree().paused = true
	Audio.silence_for_quit()
	await get_tree().create_timer(0.1, true).timeout
	get_tree().quit(0)


func _capture(filename: String) -> void:
	if _captures.is_empty() or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(_captures)
	for _frame: int in 4:
		await get_tree().process_frame
	# Use the render texture size: a Retina window can have twice the logical
	# viewport dimensions, and a logical-size crop would hide the fixed actions.
	Harness.capture(self, _captures.path_join(filename), Vector2i(get_viewport().get_texture().get_size()))
