extends Node
## What the slow frames of the first 3D open and the first "Show all tiles" are made
## of: frame time against pipeline compilations per frame (DRAW compilations stall
## the frame that needs them; SPECIALIZATION ones run in the background).
## AGENT_GODOT_WINDOW=1 godot --path . res://tools/supply_chain_3d/trials/first_open_hitches.tscn -- \
##   --no-telemetry --bake-cache-directory=<new dir> [--trial-output=<dir>]
const KINDS := {"canvas": Performance.PIPELINE_COMPILATIONS_CANVAS, "mesh": Performance.PIPELINE_COMPILATIONS_MESH,
	"surface": Performance.PIPELINE_COMPILATIONS_SURFACE, "draw": Performance.PIPELINE_COMPILATIONS_DRAW,
	"specialization": Performance.PIPELINE_COMPILATIONS_SPECIALIZATION}

func _counts() -> Dictionary:
	var counts := {}
	for kind in KINDS: counts[kind] = int(Performance.get_monitor(KINDS[kind]))
	return counts

## Timestamps at the first and last _process of every frame, so a frame splits into
## coroutines (signal -> first), node _process (first -> last) and frame end (render,
## present: last -> next signal). Performance.TIME_PROCESS is a per-second maximum.
class Stamp extends Node:
	var at := 0
	func _process(_delta: float) -> void: at = Time.get_ticks_usec()

var _first: Stamp
var _last: Stamp
var _board_rid := RID()

func _gpu_ms(rid: RID) -> float:
	return snappedf(RenderingServer.viewport_get_measured_render_time_gpu(rid), 0.1) if rid.is_valid() else 0.0

## Frames for `seconds` after an action: every frame's time and compilations.
func _watch(label: String, seconds: float) -> Dictionary:
	var started := Time.get_ticks_msec()
	var last := Time.get_ticks_usec()
	var before := _counts()
	var previous := before
	var slow: Array = []
	var frames := 0
	var worst := 0.0
	while Time.get_ticks_msec() - started < int(seconds * 1000.0):
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var frame := (now - last) / 1000.0
		var segments := {"coroutines_ms": snappedf((_first.at - last) / 1000.0, 0.1) if _first.at > last else -1.0,
			"nodes_ms": snappedf((_last.at - _first.at) / 1000.0, 0.1) if _last.at >= _first.at and _first.at > last else -1.0,
			"frame_end_ms": snappedf((now - _last.at) / 1000.0, 0.1) if _last.at > last else -1.0,
			"gpu_board_ms": _gpu_ms(_board_rid), "gpu_window_ms": _gpu_ms(get_viewport().get_viewport_rid())}
		last = now
		frames += 1
		worst = maxf(worst, frame)
		var counts := _counts()
		var delta := {}
		for kind in counts:
			if counts[kind] != previous[kind]: delta[kind] = counts[kind] - previous[kind]
		previous = counts
		if frame > 33.0:
			var row := {"at_ms": Time.get_ticks_msec() - started, "frame_ms": snappedf(frame, 0.1), "compiles": delta}
			row.merge(segments)
			slow.append(row)
	var total := {}
	for kind in previous: total[kind] = previous[kind] - before[kind]
	var row := {"frames": frames, "worst_ms": snappedf(worst, 0.1), "slow": slow, "compiles": total}
	print("[FIRST OPEN] ", label, " ", JSON.stringify(row))
	return row

const Harness := preload("res://tools/shot_harness.gd")
var output := ""
var marks := {}
var origin := 0

func _mark(name: String) -> void:
	marks[name] = Time.get_ticks_msec() - origin
	print("[TIMELINE] ", name, " ", marks[name], " ms")

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
	marks.compiles_at_play = _counts()
	MatchState.ruleset["opener_done"] = true
	Tutorial._on_overlay_skipped()
	DecisionState.enabled = false
	for layer in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var script := layer.get_script() as Script
		if script != null and script.resource_path.ends_with("_intro.gd"):
			if layer.has_method("_on_begin"): layer.call("_on_begin")
			else: layer.queue_free()
	_first = Stamp.new(); _first.process_priority = -10000; add_child(_first)
	_last = Stamp.new(); _last.process_priority = 10000; add_child(_last)
	_board_rid = (board.get("_viewport") as Viewport).get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_board_rid, true)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	# A player looking at the map for a moment before opening the 3D view.
	var idle := Time.get_ticks_msec()
	while Time.get_ticks_msec() - idle < 8000: await get_tree().process_frame
	marks.compiles_after_idle = _counts()
	view.call("toggle")
	marks.open_3d = await _watch("open_3d", 3.0)
	board.call("set_all_tiles", true)
	marks.show_all = await _watch("show_all_tiles", 6.0)
	var camera: Dictionary = board.call("capture_camera")
	camera.span = board.Rig.MIN_SIZE
	board.call("restore_camera", camera)
	marks.closest_zoom = await _watch("closest_zoom", 3.0)
	print("[FIRST OPEN REPORT] ", JSON.stringify(marks))
	if output != "":
		DirAccess.make_dir_recursive_absolute(output)
		FileAccess.open(output.path_join("first_open.json"), FileAccess.WRITE).store_string(JSON.stringify(marks, "\t"))
	get_tree().quit()
