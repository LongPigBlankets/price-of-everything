extends "res://tools/supply_chain_3d/review_colour.gd"
## The furnace, both refineries and the power plant on company tiles, one tile per level,
## shot in daylight with pollution hidden and in the evening with their lights on.
## AGENT_GODOT_WINDOW=1 godot --path . res://tools/supply_chain_3d/trials/works_tile_shot.tscn -- --no-telemetry --out=<dir>
const Legacy := preload("res://scripts/empire_board.gd")
## b_002 furnace, b_011 petrochemical refinery, b_013 polymerisation refinery, b_003 power plant.
const WORKS := [["b_002", "r_005"], ["b_011", "r_022"], ["b_013", "r_024"], ["b_003", "r_038"]]
const CANDIDATES := ["tile_10_9", "tile_8_9", "tile_9_10", "tile_10_10", "tile_8_10", "tile_10_8", "tile_8_8"]

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	Harness.prepare_window(get_window(), Vector2i(1920, 1080))
	Harness.arm_watchdog(self, 1500.0)
	TelemetryState.enabled = false
	SaveLoad.autosave_enabled = false
	AudioServer.set_bus_mute(0, true)
	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	get_tree().root.add_child.call_deferred(menu)
	await get_tree().process_frame
	get_tree().current_scene = menu
	menu.call("_on_new_game_pressed")
	SaveLoad.prepare_new_game("res://data/starts/metal_magnate.json")
	var loading := LoadingScreen.show_global(get_tree())
	loading.begin_load(SaveLoad.MAIN_SCENE)
	var main: Node
	while true:
		main = get_tree().current_scene
		if main != menu and main != null and bool(main.get("build_complete")): break
		await get_tree().process_frame
	while not bool(loading.call("_ready_to_begin")): await get_tree().process_frame
	loading.call("_on_begin_pressed")
	while is_instance_valid(loading): await get_tree().process_frame
	for i in 3: await get_tree().process_frame
	MatchState.ruleset["opener_done"] = true
	Tutorial._on_overlay_skipped()
	DecisionState.enabled = false
	for layer in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var script := layer.get_script() as Script
		if script != null and script.resource_path.ends_with("_intro.gd"):
			if layer.has_method("_on_begin"): layer.call("_on_begin")
			else: layer.queue_free()
	for i in 3: await get_tree().process_frame
	var tiles := _clean_tiles(3)
	for level in tiles.size():
		var tile: String = tiles[level]
		print("[TILE] L", level + 1, " ", tile, " type=", Catalog.tile_type(tile), " label=", Catalog.tile_label(tile))
		BuildingState.tile_land_owned[tile] = BuildingState.max_tile_land(tile)
		for work in WORKS:
			var iid := BuildingState.add_building(work[0], work[1], tile, MatchState.LOCAL_PLAYER, "", true, level + 1)
			print("[WORK] L", level + 1, " ", work[0], " -> ", iid)
	var view: Control = main.find_child("EmpireView", true, false)
	await view.call("prepare")
	Harness.prepare_window(get_window(), Vector2i(1920, 1080))
	for i in 5: await get_tree().process_frame
	view.call("toggle")
	await get_tree().physics_frame
	var board: Control = view.find_child("Board", true, false)
	await board.call("set_all_tiles", false, false)
	await _settle(board)
	Legacy.show.pollution = false
	await board.call("build_async", board.get("_last_graph"), board.get("_last_terrain"))
	await _settle(board)
	var frames := []
	for level in tiles.size():
		for span in [420.0, 240.0]: frames.append(["L%d" % (level + 1), tiles[level], span, Vector2.ZERO])
	frames.append(["overview", tiles[1], 1300.0, Vector2.ZERO])
	# The first frame after a rebuild can be refitted by the board; shoot it twice.
	await _frame(board, "day", frames[0])
	for frame in frames: await _frame(board, "day", frame)
	await board.call("set_evening", true)
	await _settle(board)
	await _frame(board, "evening", frames[0])
	for frame in frames: await _frame(board, "evening", frame)
	await _finish(main, board)

## The start's neighbours with the fewest buildings, leaving out water.
func _clean_tiles(count: int) -> Array:
	var ranked := []
	for tid in CANDIDATES:
		var kind := str(Catalog.tile_type(tid))
		var buildings: int = BuildingState.tile_buildings.get(tid, []).size()
		print("[CANDIDATE] ", tid, " ", kind, " buildings=", buildings, " land=", BuildingState.max_tile_land(tid))
		if kind in ["sea", "water", "ocean", "lake"] or BuildingState.max_tile_land(tid) <= 0: continue
		ranked.append([buildings, tid])
	ranked.sort()
	return ranked.slice(0, count).map(func(entry: Array) -> String: return entry[1])
