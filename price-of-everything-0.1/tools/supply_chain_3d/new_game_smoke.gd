extends Node
## Exercises the threaded menu -> loading screen -> Begin -> supply-chain path.
## Headless companion to capture.gd; uses the actual threaded New Game loader.
func _ready() -> void:
	get_tree().create_timer(150).timeout.connect(func() -> void:
		push_error("New-game smoke timed out")
		get_tree().quit(1))
	SaveLoad.autosave_enabled = false
	TelemetryState.enabled = false
	AudioServer.set_bus_mute(0, true)
	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	get_tree().root.add_child.call_deferred(menu)
	await get_tree().process_frame
	get_tree().current_scene = menu
	menu.call("_on_new_game_pressed")
	await get_tree().process_frame
	var start := "res://data/starts/metal_magnate.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--start="): start = arg.trim_prefix("--start=")
	# The same loading path as the menu's start callback, without writing profile consent.
	SaveLoad.prepare_new_game(start)
	var loading := LoadingScreen.show_global(get_tree())
	loading.begin_load(SaveLoad.MAIN_SCENE)
	var main: Node
	while true:
		main = get_tree().current_scene
		if main != menu and main != null and bool(main.get("build_complete")): break
		await get_tree().process_frame
	print("[NEW GAME] map built: ", start)
	while not bool(loading.call("_ready_to_begin")): await get_tree().process_frame
	loading.call("_on_begin_pressed")
	while is_instance_valid(loading): await get_tree().process_frame
	Tutorial._on_overlay_skipped()
	MatchState.ruleset["opener_done"] = true
	DecisionState.enabled = false
	var view: Control = main.find_child("EmpireView", true, false)
	view.call("toggle")
	var board: Control = view.find_child("Board", true, false)
	while bool(board.get("_building")): await get_tree().process_frame
	print("[NEW GAME] Begin and supply-chain open succeeded; ", board.get_script().resource_path)
	view.hide()
	print("[NEW GAME] returned to regular map")
	get_tree().quit()
