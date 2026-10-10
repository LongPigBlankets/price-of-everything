extends "res://tools/supply_chain_3d/capture.gd"
## Disposable rendered benchmark; production scripts and stored bakes are unchanged.
const ProfileBuilder := preload("res://tools/supply_chain_3d/pan_profile_builder.gd")
const ProfileBoard := preload("res://tools/supply_chain_3d/pan_profile_board.gd")
const ProfileRoads := preload("res://tools/supply_chain_3d/pan_profile_roads.gd")
const ProfileCache := preload("res://tools/supply_chain_3d/pan_profile_cache.gd")
var frames: Array = []
var sampling := false
var last_tick := 0

func _rebind(object: Object, script: Script) -> void:
	var state := {}
	for property in object.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			state[str(property.name)] = object.get(str(property.name))
	object.set_script(script)
	for key in state: object.set(key, state[key])

func _frame() -> void:
	if not sampling: return
	var now := Time.get_ticks_usec()
	frames.append((now - last_tick) / 1000.0)
	last_tick = now

func _stats(samples: Array) -> Dictionary:
	if samples.is_empty(): return {"count": 0, "total_ms": 0.0, "max_ms": 0.0}
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	for value in samples: total += float(value)
	return {"count": samples.size(), "total_ms": total, "max_ms": sorted[-1], "p95_ms": sorted[mini(sorted.size() - 1, floori(sorted.size() * 0.95))]}

func _stage_stats(stages: Dictionary) -> Dictionary:
	var result := {}
	for key in stages: result[key] = _stats(stages[key])
	return result

func _continent_review(board: Control, home: Dictionary) -> void:
	await board.call("set_all_tiles", true, false)
	while not board.call("detail_ready"): await get_tree().process_frame
	board.set_process(false)
	var builder: RefCounted = board.get("_builder")
	_rebind(builder, ProfileBuilder)
	_rebind(builder.bake_cache, ProfileCache)
	_rebind(builder.road_surface, ProfileRoads)
	_rebind(board, ProfileBoard)
	board.set_process(false)
	var initial: Dictionary = board.capture_camera()
	var focus: Vector3 = home.target
	for tile in builder.tiles.values():
		if "Snare Harbour Coast" in str(tile.label): focus = builder.point(tile.center); break
	var farthest := focus
	var farthest_distance := 0.0
	for tile in builder.tiles.values():
		if str(tile.type) in ["sea", "deep_sea"]: continue
		var p: Vector3 = builder.point(tile.center)
		if p.distance_squared_to(focus) > farthest_distance:
			farthest = p
			farthest_distance = p.distance_squared_to(focus)
	get_tree().process_frame.connect(_frame)
	var results: Array = []
	for mode in ["first_visit", "cached_baseline", "medium_only_trees", "retain_recent"]:
		builder.probe_keep = false
		builder.release_local_tiles({})
		builder.probe_keep = mode == "retain_recent"
		builder.probe_medium_only = mode == "medium_only_trees"
		board._stream_camera = {}
		for step in [{"name": "arrive", "at": focus}, {"name": "adjacent", "at": focus + Vector3(405, 0, 240)},
			{"name": "across_continent", "at": farthest}, {"name": "return", "at": focus}]:
			builder.probe.clear()
			builder.road_surface.probe.clear()
			board.probe.clear()
			builder.bake_cache.probe.clear()
			builder.bake_cache.compressed_bytes = 0
			var writes: int = builder.bake_cache.writes
			var before: int = builder.local_tiles.size()
			var state := initial.duplicate()
			state.target = step.at
			state.span = 1100.0
			frames.clear()
			var start := Time.get_ticks_usec()
			last_tick = start
			sampling = true
			board.restore_camera(state)
			var camera_ms := (Time.get_ticks_usec() - start) / 1000.0
			await board._stream_visible()
			var elapsed_ms := (Time.get_ticks_usec() - start) / 1000.0
			# Let the upload/physics work queued by the final attachment reach a frame.
			for i in 3:
				RenderingServer.force_draw(false)
				await get_tree().process_frame
			sampling = false
			var result := {"mode": mode, "step": step.name, "camera_ms": camera_ms, "ready_ms": elapsed_ms,
				"before_tiles": before, "after_tiles": builder.local_tiles.size(), "board": _stage_stats(board.probe),
				"builder": _stage_stats(builder.probe), "load": _stage_stats(builder.bake_cache.probe),
				"compressed_MiB": builder.bake_cache.compressed_bytes / 1048576.0,
				"cache_writes": builder.bake_cache.writes - writes, "frames": _stats(frames),
				"road_setup": _stats(builder.road_surface.probe), "fine_tiles": builder.terrain_lods.filter(func(item: Dictionary) -> bool: return item.data.meshes[1] != null).size()}
			results.append(result)
			print("[PAN PROFILE] ", mode, "/", step.name, " ready_ms=", elapsed_ms, " camera_ms=", camera_ms,
				" tiles=", builder.local_tiles.size(), " writes=", result.cache_writes)
			for i in 5: await get_tree().process_frame
		var file := FileAccess.open("/private/tmp/supply_pan_profile.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(results, "\t"))
	builder.probe_keep = false
	builder.release_local_tiles({})
	board.restore_camera(initial)
	print("[PAN PROFILE] complete; untouched production behaviour, benchmark variants confined to tooling")
