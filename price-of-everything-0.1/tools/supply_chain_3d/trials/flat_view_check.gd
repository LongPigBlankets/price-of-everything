extends "res://tools/supply_chain_3d/capture.gd"
## The supply chain view on a quality preset: video memory, what the scene holds, captures,
## and a rebuild after a change. Run once per preset to compare.
## AGENT_GODOT_WINDOW=1 godot --path . res://tools/supply_chain_3d/trials/flat_view_check.tscn -- \
##   --continent-review --no-telemetry --quality=low|high --trial-output=<dir> --bake-cache-directory=<new dir>
var output := ""
var report := {}

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--trial-output="): output = arg.trim_prefix("--trial-output=")
		# This run only; the saved profile is not touched.
		if arg.begins_with("--quality="): PlayerProfile.graphics_quality = arg.trim_prefix("--quality=")
	DirAccess.make_dir_recursive_absolute(output)
	report.quality = PlayerProfile.graphics_quality
	await super._ready()

func _mib() -> float:
	return snappedf(RenderingServer.get_rendering_device().get_memory_usage(RenderingDevice.MEMORY_TOTAL) / 1048576.0, 1)

func _settle(board: Control, seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until or not bool(board.call("detail_ready")):
		RenderingServer.force_draw(false); await get_tree().process_frame
		if Time.get_ticks_msec() > until + 60000: break

func _scene(board: Control) -> Dictionary:
	var builder: RefCounted = board._builder
	var houses := 0
	var far_cards := 0
	for pair in builder.sprite_pairs:
		if not pair.get("standing") is Dictionary: continue
		var standing: Dictionary = pair.standing
		if str(standing.kind) == "house": houses += 1
		if pair.get("far") != null and not standing.has("harbour"): far_cards += 1
	return {"flat": board.call("built_flat"), "tiles": builder.tiles.size(), "standing_nodes": builder.sprite_pairs.size(), "houses": houses,
		"far_cards": far_cards, "tree_nodes": builder.tree_nodes.size(), "local_tiles": builder.local_tiles.size(), "gpu_MiB": _mib()}

func _view_shot(board: Control, name: String, span: float, pitch: float) -> void:
	var builder: RefCounted = board._builder
	var camera: Dictionary = board.capture_camera()
	camera.target = builder.point(builder.tiles["tile_9_10"].center if builder.tiles.has("tile_9_10") else builder.tiles.values()[0].center)
	camera.span = span; camera.pitch = pitch; camera.yaw = board.Rig.HOME_YAW
	board.restore_camera(camera)
	await _settle(board, 2.0)
	report[name] = _scene(board)
	board._viewport.get_texture().get_image().save_png(output.path_join("%s_%s.png" % [report.quality, name]))

func _open_supply_view(view: Control) -> void:
	report.gpu_MiB_2d = _mib()
	var started := Time.get_ticks_msec()
	await super._open_supply_view(view)
	report.open_call_ms = Time.get_ticks_msec() - started

func _continent_review(board: Control, _home: Dictionary) -> void:
	await _settle(board, 3.0)
	report.opened = _scene(board)
	await _view_shot(board, "closest", board.Rig.MIN_SIZE, board.Rig.HOME_PITCH)
	await _view_shot(board, "medium", board.size.y * 0.8, 0.6)
	await _view_shot(board, "far", 2600.0, 0.75)
	# Show all tiles is refused on Low; the company stays.
	await board.set_all_tiles(true, false)
	for i in 30: await get_tree().process_frame
	report.show_all_after_request = board.show_all_tiles
	if board.show_all_tiles: await board.set_all_tiles(false, false)
	# A change in the sim: a building on a tile new to the company.
	var map: Node = null
	for node in get_tree().root.find_children("*", "", true, false):
		var script := node.get_script() as Script
		if script != null and script.resource_path.ends_with("/world_map.gd"): map = node; break
	var fresh := ""
	for tid in board._model.tiles:
		for neighbour in Catalog.tile_neighbours(str(tid)):
			if not board._model.tiles.has(neighbour) and Catalog.tile_type(neighbour) in ["rural", "hill"]: fresh = neighbour; break
		if fresh != "": break
	var before: Dictionary = board.load_profile
	var started := Time.get_ticks_msec()
	var iid := BuildingState.add_building("b_024", "", fresh)
	map.building_placed.emit(fresh, "b_024", "", iid, map.terrain_layer.id_to_coord(fresh))
	while board.load_profile == before or board._building:
		await get_tree().process_frame
		if Time.get_ticks_msec() - started > 120000: break
	await _settle(board, 2.0)
	report.after_change = _scene(board)
	report.after_change.rebuild_ms = Time.get_ticks_msec() - started
	report.after_change.cache = {"hits": board.load_profile.get("cache_hits"), "misses": board.load_profile.get("cache_misses"), "writes": board.load_profile.get("cache_writes")}
	await _view_shot(board, "medium_after_change", board.size.y * 0.8, 0.6)
	print("[FLAT VIEW] ", JSON.stringify(report))
	FileAccess.open(output.path_join("report_%s.json" % report.quality), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
