extends "res://tools/supply_chain_3d/capture.gd"
## Video memory at the Metal Magnate start and under a heavier company.
## AGENT_GODOT_WINDOW=1 godot --path . res://tools/supply_chain_3d/trials/vram_load_profile.tscn -- \
##   --continent-review --no-telemetry --trial-output=<dir> --bake-cache-directory=<new dir> [--heavy]
## --heavy adds player buildings on land tiles near the company before the 3D view opens:
## --heavy-tiles=N tiles (default 12) with --per-tile=K buildings each (default 3).
const EXTRA_BUILDINGS := ["b_002", "b_008", "b_007", "b_009", "b_012", "b_003", "b_024", "b_025",
	"b_030", "b_028", "b_013", "b_010", "b_011", "b_036", "b_023", "b_020", "b_021", "b_022"]
var output := ""
var stages := []
var peak_mib := 0.0
var peak_stage := ""
var current_stage := "startup"
var started_msec := 0

func _ready() -> void:
	started_msec = Time.get_ticks_msec()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--trial-output="): output = arg.trim_prefix("--trial-output=")
	DirAccess.make_dir_recursive_absolute(output)
	get_tree().process_frame.connect(func() -> void:
		var used := _rd_mib()
		if used > peak_mib: peak_mib = used; peak_stage = current_stage)
	await super._ready()

func _rd_mib() -> float:
	var device := RenderingServer.get_rendering_device()
	return device.get_memory_usage(RenderingDevice.MEMORY_TOTAL) / 1048576.0 if device != null else 0.0

func _stage(name: String, extra: Dictionary = {}) -> void:
	for i in 3: RenderingServer.force_draw(false); await get_tree().process_frame
	var row := {"stage": name, "gpu_MiB": snappedf(_rd_mib(), 1), "elapsed_s": snappedf((Time.get_ticks_msec() - started_msec) / 1000.0, 0.1),
		"player_buildings": BuildingState.buildings.values().filter(func(b): return BuildingState.is_player_owned(b)).size()}
	row.merge(extra)
	stages.append(row)
	current_stage = name
	print("[VRAM STAGE] ", JSON.stringify(row))
	FileAccess.open(output.path_join("vram_profile.json"), FileAccess.WRITE).store_string(JSON.stringify(
		{"stages": stages, "peak_MiB": snappedf(peak_mib, 1), "peak_stage": peak_stage}, "\t"))

func _open_supply_view(view: Control) -> void:
	await _stage("2d_game")
	if "--heavy" in OS.get_cmdline_user_args():
		_add_company()
		for i in 120: await get_tree().process_frame
		await _stage("2d_game_heavy")
	await super._open_supply_view(view)

func _add_company() -> void:
	var map: Node = null
	for node in get_tree().current_scene.find_children("*", "", true, false):
		var script := node.get_script() as Script
		if script != null and script.resource_path.ends_with("/world_map.gd"): map = node; break
	var owned := {}
	for b in BuildingState.buildings.values():
		if BuildingState.is_player_owned(b): owned[str(b.tile_id)] = true
	# Breadth-first outward from the company, land tiles only.
	var chosen: Array = []
	var seen := owned.duplicate()
	var front: Array = owned.keys()
	var wanted := 12
	var per_tile := 3
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--heavy-tiles="): wanted = int(arg.trim_prefix("--heavy-tiles="))
		if arg.begins_with("--per-tile="): per_tile = int(arg.trim_prefix("--per-tile="))
	while chosen.size() < wanted and not front.is_empty():
		var next: Array = []
		for tid in front:
			for neighbour in Catalog.tile_neighbours(str(tid)):
				if seen.has(neighbour): continue
				seen[neighbour] = true
				next.append(neighbour)
				if Catalog.tile_type(neighbour) in ["rural", "hill", "urban"] and chosen.size() < wanted: chosen.append(neighbour)
		front = next
	var index := 0
	for tid in chosen:
		for i in per_tile:
			var building_id: String = EXTRA_BUILDINGS[index % EXTRA_BUILDINGS.size()]
			index += 1
			var iid := BuildingState.add_building(building_id, "", tid)
			if map != null: map.building_placed.emit(tid, building_id, "", iid, map.terrain_layer.id_to_coord(tid))
	print("[HEAVY] added ", index, " buildings on ", chosen)

func _settle(board: Control, seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until or not board.detail_ready():
		RenderingServer.force_draw(false); await get_tree().process_frame
		if Time.get_ticks_msec() > until + 30000: break

func _view(board: Control, name: String, tile: String, span: float, pitch: float) -> void:
	var builder: RefCounted = board._builder
	var camera: Dictionary = board.capture_camera()
	camera.target = builder.point(builder.tiles[tile].center)
	camera.span = span; camera.pitch = pitch; camera.yaw = board.Rig.HOME_YAW
	board.restore_camera(camera)
	await _settle(board, 3.0)
	await _stage(name, {"local_tiles": builder.local_tiles.size(), "tile_cache_MiB": snappedf(builder.resource_cache.bytes / 1048576.0, 1)})
	board._viewport.get_texture().get_image().save_png(output.path_join(name + ".png"))

func _continent_review(board: Control, _home: Dictionary) -> void:
	while board.background_active() or not board.detail_ready(): await get_tree().process_frame
	await _settle(board, 3.0)
	await _stage("3d_company_view", {"company_tiles": board._model.tiles.size()})
	board._viewport.get_texture().get_image().save_png(output.path_join("3d_company_view.png"))
	await board.set_all_tiles(true, false)
	await _settle(board, 3.0)
	await _stage("3d_all_tiles_open", {"local_tiles": board._builder.local_tiles.size()})
	if "--dump-model" in OS.get_cmdline_user_args():
		# Live continent model next to the bundled base snapshot's, for per-tile divergence analysis.
		var Snapshot := preload("res://scripts/supply_chain_3d/world_snapshot.gd")
		var cache: RefCounted = board._builder.bake_cache
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(cache.bundled_directory.path_join("manifest.json")))
		var base: Dictionary = cache.read(str(manifest.world_snapshot_key))
		FileAccess.open(output.path_join("model_live.json"), FileAccess.WRITE).store_string(JSON.stringify(Snapshot.plain(board._model)))
		FileAccess.open(output.path_join("model_base.json"), FileAccess.WRITE).store_string(JSON.stringify(Snapshot.plain(base.get("model", {}))))
		print("[DUMP] live standing=", board._model.get("standing", []).size(), " base standing=", base.get("model", {}).get("standing", []).size())
		get_tree().quit()
		return
	var home := str(board._model.tiles.keys()[0]) if not board._model.tiles.is_empty() else "tile_9_9"
	await _view(board, "3d_closest_company", home, board.Rig.MIN_SIZE, board.Rig.HOME_PITCH)
	await _view(board, "3d_medium_company", home, board.size.y, 0.6)
	await _view(board, "3d_medium_capital", "tile_23_8", board.size.y, 0.6)
	await _view(board, "3d_far_region", home, 2600.0, 0.75)
	await _view(board, "3d_overview_all", "tile_15_10", 9000.0, 0.9)
	print("[VRAM PEAK] ", snappedf(peak_mib, 1), " at ", peak_stage)
