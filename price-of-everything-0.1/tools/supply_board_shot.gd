extends Node
## Captures of the supply chain view in a Metal Magnate game: the first frames after it opens, the board at rest,
## and each building's network focused.
##   AGENT_GODOT_WINDOW=1 godot --path . res://tools/supply_board_shot.tscn -- --no-telemetry
## Writes supply_<view>.png into $SB_SHOT_DIR (or /tmp).

const ShotHarness := preload("res://tools/shot_harness.gd")
const START := "res://data/starts/metal_magnate.json"
## The frames after opening to capture, for anything that moves while the board settles.
const OPEN_FRAMES := [1, 2, 3, 5, 8, 13]

var _out := "/tmp"


func _ready() -> void:
	var dir := OS.get_environment("SB_SHOT_DIR")
	if dir != "":
		_out = dir
	DirAccess.make_dir_recursive_absolute(_out)
	ShotHarness.arm_watchdog(self, 240.0)
	ShotHarness.prepare_window(get_window(), Vector2i(1920, 1080))
	TelemetryState.enabled = false
	SaveLoad.autosave_enabled = false
	AudioServer.set_bus_mute(0, true)
	SaveLoad.prepare_new_game(START)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	get_tree().current_scene = main
	await _settle(200)
	MatchState.ruleset["opener_done"] = true
	Tutorial._on_overlay_skipped()
	DecisionState.enabled = false
	for layer in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var sc := (layer as Node).get_script() as Script
		if sc != null and sc.resource_path.ends_with("_intro.gd"):
			layer.queue_free()
	await _settle(20)
	var view: Node = main.find_child("EmpireView", true, false)
	view.call("toggle")
	var frame := 0
	for f: int in OPEN_FRAMES:
		await _settle(f - frame)
		frame = f
		await _shot("open_%02d" % f)
	await _settle(60)
	await _shot("board")
	var board: Control = view.find_child("Board", true, false)
	# What the pointer finds over the middle of each standing thing.
	var found: Dictionary = {}
	for s: Dictionary in board.call("standing_screen_rects"):
		var picked: Dictionary = board.call("_pick", (s["rect"] as Rect2).get_center())
		var key := "%s -> %s" % [s["kind"], picked.get("kind", "nothing")]
		found[key] = int(found.get(key, 0)) + 1
	print("[sb_shot] pointer over kind -> picks: ", found)
	var world: Control = view.find_child("GraphWorld", true, false)
	for iid: String in BuildingState.buildings:
		if not BuildingState.is_player_owned(BuildingState.buildings[iid]):
			continue
		view.call("_on_building_picked", iid)
		var guard := 0
		while float(world.get("_focus_t")) < 0.999 and guard < 1200:
			guard += 1
			await get_tree().process_frame
		await _settle(6)
		var screens: Dictionary = world.get("_screen_by_iid")
		var members: Array = (world.get("_focus_members") as Dictionary).keys()
		print("[sb_shot] focus %s members %s" % [iid, members])
		for m in members:
			print("[sb_shot]   %s at %s" % [m, screens.get(m, "?")])
		await _shot("focus_%s" % iid)
		world.call("clear_focus")
		await _settle(30)
	get_tree().quit()


func _shot(name: String) -> void:
	RenderingServer.force_draw(false)
	get_viewport().get_texture().get_image().save_png(_out.path_join("supply_%s.png" % name))
	await get_tree().process_frame


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
