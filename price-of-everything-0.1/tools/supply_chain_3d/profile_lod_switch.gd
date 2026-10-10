extends "res://tools/supply_chain_3d/profile_pan.gd"
## Measures current switching and a tooling-only retained-detail variant.

func _switch_case(board: Control, state: Dictionary, mode: String, direction: String) -> Dictionary:
	var builder: RefCounted = board._builder
	builder.probe.clear()
	builder.road_surface.probe.clear()
	builder.bake_cache.probe.clear()
	builder.bake_cache.compressed_bytes = 0
	board.probe.clear()
	var writes: int = builder.bake_cache.writes
	var before: int = builder.local_tiles.size()
	frames.clear()
	var start := Time.get_ticks_usec()
	last_tick = start
	sampling = true
	board.restore_camera(state)
	var camera_ms := (Time.get_ticks_usec() - start) / 1000.0
	# Observe the first rendered response separately from subsequent eviction/loading.
	RenderingServer.force_draw(false)
	await get_tree().process_frame
	var first_frame_ms := (Time.get_ticks_usec() - start) / 1000.0
	await board._stream_visible()
	var ready_ms := (Time.get_ticks_usec() - start) / 1000.0
	for i in 3:
		RenderingServer.force_draw(false)
		await get_tree().process_frame
	sampling = false
	var result := {"mode": mode, "direction": direction, "camera_ms": camera_ms,
		"first_render_response_ms": first_frame_ms, "ready_ms": ready_ms, "frames": _stats(frames),
		"builder": _stage_stats(builder.probe), "road_setup": _stats(builder.road_surface.probe),
		"board": _stage_stats(board.probe), "load": _stage_stats(builder.bake_cache.probe),
		"before_tiles": before, "after_tiles": builder.local_tiles.size(), "overview": builder._overview,
		"cache_writes": builder.bake_cache.writes - writes,
		"compressed_MiB": builder.bake_cache.compressed_bytes / 1048576.0}
	print("[LOD SWITCH] ", mode, " ", direction, " camera_ms=", camera_ms,
		" first_frame_ms=", first_frame_ms, " ready_ms=", ready_ms)
	for i in 5: await get_tree().process_frame
	return result

func _continent_review(board: Control, home: Dictionary) -> void:
	await board.set_all_tiles(true, false)
	while not board.detail_ready(): await get_tree().process_frame
	board.set_process(false)
	var builder: RefCounted = board._builder
	_rebind(builder, ProfileBuilder)
	_rebind(builder.bake_cache, ProfileCache)
	_rebind(builder.road_surface, ProfileRoads)
	_rebind(board, ProfileBoard)
	board.set_process(false)
	var far: Dictionary = board.capture_camera()
	var medium := far.duplicate()
	medium.span = 1100.0
	medium.target = home.target
	for tile in builder.tiles.values():
		if "Snare Harbour Coast" in str(tile.label): medium.target = builder.point(tile.center); break
	far.target = medium.target
	get_tree().process_frame.connect(_frame)
	var results: Array = []
	results.append(await _switch_case(board, medium, "warmup", "far_to_medium"))
	for mode in ["current", "retain_recent"]:
		builder.probe_keep = mode == "retain_recent"
		for i in 3:
			results.append(await _switch_case(board, far, mode, "medium_to_far"))
			results.append(await _switch_case(board, medium, mode, "far_to_medium"))
		var file := FileAccess.open("/private/tmp/supply_lod_switch.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(results, "\t"))
	builder.probe_keep = false
	builder.release_local_tiles({})
	board.restore_camera(far)
