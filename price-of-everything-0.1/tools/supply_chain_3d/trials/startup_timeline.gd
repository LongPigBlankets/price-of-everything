extends Node
## Player-facing timeline of a new Metal Magnate game, through the real menu,
## loading screen and visibility setting:
##   New Game -> Begin offered -> 3D company view open -> "Show all tiles" ready.
## AGENT_GODOT_WINDOW=1 godot --path . res://tools/supply_chain_3d/trials/startup_timeline.tscn -- \
##   --no-telemetry --bake-cache-directory=<new dir> [--wait-background] [--trial-output=<dir>]
## --wait-background: idle in the company view until the continent is prepared
## before choosing "Show all tiles" (a player who looks around first).
const Harness := preload("res://tools/shot_harness.gd")
var output := ""
var marks := {}
var origin := 0

func _mark(name: String) -> void:
	marks[name] = Time.get_ticks_msec() - origin
	print("[TIMELINE] ", name, " ", marks[name], " ms")

## Waits for a condition and reports the longest frame meanwhile.
func _until(condition: Callable, limit_ms: int) -> Dictionary:
	var started := Time.get_ticks_msec()
	var last := Time.get_ticks_usec()
	var worst := 0.0
	var slow := 0
	while not condition.call() and Time.get_ticks_msec() - started < limit_ms:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var frame := (now - last) / 1000.0
		worst = maxf(worst, frame)
		if frame > 50.0: slow += 1
		last = now
	return {"ms": Time.get_ticks_msec() - started, "worst_frame_ms": snappedf(worst, 0.1), "frames_over_50ms": slow, "met": condition.call()}

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--trial-output="): output = arg.trim_prefix("--trial-output=")
	Harness.prepare_window(get_window(), Vector2i(1920, 1080))
	Harness.arm_watchdog(self, 1200.0)
	TelemetryState.enabled = false
	SaveLoad.autosave_enabled = false
	AudioServer.set_bus_mute(0, true)
	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	get_tree().root.add_child.call_deferred(menu)
	await get_tree().process_frame
	get_tree().current_scene = menu
	for i in 10: await get_tree().process_frame
	origin = Time.get_ticks_msec()
	marks.engine_start_to_menu_ms = origin
	menu.call("_on_new_game_pressed")
	SaveLoad.prepare_new_game("res://data/starts/metal_magnate.json")
	var loading := LoadingScreen.show_global(get_tree())
	loading.begin_load(SaveLoad.MAIN_SCENE)
	_mark("new_game_pressed")
	var main: Node
	while true:
		main = get_tree().current_scene
		if main != menu and main != null and bool(main.get("build_complete")): break
		await get_tree().process_frame
	_mark("world_built")
	while not bool(loading.call("_ready_to_begin")): await get_tree().process_frame
	_mark("begin_offered")
	var view: Control = main.find_child("EmpireView", true, false)
	var board: Control = view.find_child("Board", true, false)
	marks.company_view_prepared_at_begin = bool(view.call("is_prepared"))
	marks.continent_ready_at_begin = bool(board.call("background_ready"))
	loading.call("_on_begin_pressed")
	while is_instance_valid(loading): await get_tree().process_frame
	_mark("map_playable")
	MatchState.ruleset["opener_done"] = true
	Tutorial._on_overlay_skipped()
	DecisionState.enabled = false
	for layer in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var script := layer.get_script() as Script
		if script != null and script.resource_path.ends_with("_intro.gd"):
			if layer.has_method("_on_begin"): layer.call("_on_begin")
			else: layer.queue_free()
	for i in 30: await get_tree().process_frame
	# Open the 3D view the way its bottom-menu button does.
	_mark("open_3d_pressed")
	view.call("toggle")
	marks.open_3d = await _until(func() -> bool: return board.is_visible_in_tree() and not bool(board.get("_building")) and bool(board.call("detail_ready")), 120000)
	_mark("open_3d_ready")
	var shown := Time.get_ticks_msec()
	marks.open_3d_first_2s = await _until(func() -> bool: return Time.get_ticks_msec() - shown >= 2000, 3000)
	marks.company_tiles = board.get("_model").tiles.size()
	marks.continent_ready_at_open = bool(board.call("background_ready"))
	if "--wait-background" in OS.get_cmdline_user_args():
		marks.idle_until_continent = await _until(func() -> bool: return bool(board.call("background_ready")) and not bool(board.call("background_active")), 600000)
		_mark("continent_prepared")
	marks.continent_ready_at_show_all = bool(board.call("background_ready"))
	# The visibility setting.
	_mark("show_all_pressed")
	board.call("set_all_tiles", true)
	marks.show_all = await _until(func() -> bool:
		var builder: RefCounted = board.get("_builder")
		return bool(board.get("show_all_tiles")) and builder != null and builder.streamed and not bool(board.call("background_active")) and bool(board.call("detail_ready")), 900000)
	_mark("show_all_ready")
	marks.background_profile = board.get("background_profile")
	var reveal: Dictionary = board.get("reveal_profile")
	marks.reveal = {"backdrop_ms": reveal.get("backdrop_ms", -1), "tiles": reveal.tiles.size(),
		"first_tile_ms": reveal.tiles.map(func(t: Dictionary) -> int: return int(t.ms)).min() if not reveal.tiles.is_empty() else -1,
		"last_tile_ms": reveal.tiles.map(func(t: Dictionary) -> int: return int(t.ms)).max() if not reveal.tiles.is_empty() else -1}
	print("[TIMELINE REPORT] ", JSON.stringify(marks))
	if output != "":
		DirAccess.make_dir_recursive_absolute(output)
		FileAccess.open(output.path_join("timeline.json"), FileAccess.WRITE).store_string(JSON.stringify(marks, "\t"))
		board.get("_viewport").get_texture().get_image().save_png(output.path_join("show_all.png"))
	get_tree().quit()
