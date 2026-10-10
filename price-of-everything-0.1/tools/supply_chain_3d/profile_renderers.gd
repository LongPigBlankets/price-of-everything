extends "res://tools/supply_chain_3d/profile_closest_loading.gd"
## Disposable, matched-renderer experiment. Never change production bake keys.
## Run from an isolated copy with --continent-review --range-output=<absolute path>.
const BakeCache := preload("res://scripts/supply_chain_3d/bake_cache.gd")
var rendering_results: Array = []
var run_metadata := {}

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--range-output="): output = arg.trim_prefix("--range-output=")
	DirAccess.make_dir_recursive_absolute(output)
	# This explicit profiling flag reuses the identical reference payload across
	# engines. It is not a claim that upgraded production caches are validated.
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BakeCache.BUNDLED.path_join("source_fingerprints.json")))
	if "--reuse-reference-bakes" in OS.get_cmdline_user_args():
		BakeCache._source_keys = reference.layers.duplicate()
	run_metadata = {"engine": Engine.get_version_info(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"reference_bake_engine": reference.engine,
		"reference_keys_override": "--reuse-reference-bakes" in OS.get_cmdline_user_args(),
		"sprite_shader_sha256": FileAccess.get_sha256("res://scripts/supply_chain_3d/far_sprite.gdshader"),
		"method": "Identical packaged resources, forced background draws, no OS cache purge; no streaming-format conversion"}
	_write_render_report()
	await super._ready()

func _write_render_report() -> void:
	FileAccess.open(output.path_join("rendering.json"), FileAccess.WRITE).store_string(JSON.stringify({"metadata": run_metadata, "stages": rendering_results}, "\t"))

func _stats(samples: Array) -> Dictionary:
	var result := super._stats(samples)
	if samples.is_empty(): return result
	var sorted := samples.duplicate()
	sorted.sort()
	result.median_ms = sorted[sorted.size() / 2]
	result.p99_ms = sorted[mini(sorted.size() - 1, floori(sorted.size() * 0.99))]
	result.over_16_67_ms = samples.filter(func(value: float) -> bool: return value > 16.67).size()
	result.over_33_33_ms = samples.filter(func(value: float) -> bool: return value > 33.33).size()
	return result

func _frame() -> void:
	if sampling: RenderingServer.force_draw(false)
	super._frame()

func _pipelines() -> Dictionary:
	var result := {}
	for name in ["PIPELINE_COMPILATIONS_MESH", "PIPELINE_COMPILATIONS_SURFACE", "PIPELINE_COMPILATIONS_DRAW", "PIPELINE_COMPILATIONS_SPECIALIZATION"]:
		var id := ClassDB.class_get_integer_constant("Performance", name)
		result[name] = Performance.get_monitor(id)
	return result

func _draw_view(board: Control, name: String) -> void:
	if sampling: frames.append((Time.get_ticks_usec() - last_tick) / 1000.0)
	sampling = false
	var rid: RID = board._viewport.get_viewport_rid()
	var started := Time.get_ticks_usec()
	RenderingServer.force_draw(false)
	var first_draw := (Time.get_ticks_usec() - started) / 1000.0
	var wall: Array = []
	var gpu: Array = []
	var cpu: Array = []
	for i in 35:
		await get_tree().process_frame
		started = Time.get_ticks_usec()
		RenderingServer.force_draw(false)
		if i < 5: continue
		wall.append((Time.get_ticks_usec() - started) / 1000.0)
		if run_metadata.renderer != "gl_compatibility":
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
			cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
	var hit: Dictionary = board.pick_at(board.screen_point(board.capture_camera().target), true)
	var record := {"view": name, "first_force_draw_ms": first_draw,
		"steady_force_draw_ms": _stats(wall), "viewport_gpu_ms": _stats(gpu), "viewport_render_cpu_ms": _stats(cpu),
		"gpu_timing_available": not gpu.is_empty() and gpu.max() > 0.0,
		"pipelines": _pipelines(), "tile_pick": not hit.is_empty(),
		"texture_MiB": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		"buffer_MiB": Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0,
		"draw_calls": board._viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"primitives": board._viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)}
	rendering_results.append(record)
	_write_render_report()
	assert(board._viewport.get_texture().get_image().save_png(output.path_join(name + ".png")) == OK)
	print("[RENDERER PROFILE] ", name, " ", JSON.stringify(record))

func _continent_review(board: Control, home: Dictionary) -> void:
	var start := Time.get_ticks_usec()
	await board.set_all_tiles(true, false)
	while not board.detail_ready():
		RenderingServer.force_draw(false)
		await get_tree().process_frame
	run_metadata.continent_ready_ms = (Time.get_ticks_usec() - start) / 1000.0
	board.set_process(false)
	board._labels.hide()
	board.animate_goods = false
	_rebind(board._builder, ProfileBuilder)
	_rebind(board._builder.bake_cache, ProfileCache)
	_rebind(board, ProfileBoard)
	board.set_process(false)
	var builder: RefCounted = board._builder
	builder.bake_cache.directory = "user://renderer-probe-empty-%d" % Time.get_ticks_usec()
	get_tree().process_frame.connect(_frame)
	RenderingServer.viewport_set_measure_render_time(board._viewport.get_viewport_rid(), true)
	run_metadata.viewport_size = [board._viewport.size.x, board._viewport.size.y]
	var far: Dictionary = board.capture_camera()
	await _view(board, far, "far_initial")
	var medium := far.duplicate()
	medium.span = 1100.0
	medium.target = home.target
	for tile in builder.tiles.values():
		if "Snare Harbour Coast" in str(tile.label): medium.target = builder.point(tile.center); break
	await _view(board, medium, "medium_first")
	var adjacent := medium.duplicate()
	adjacent.target += Vector3(405, 0, 240)
	await _view(board, adjacent, "medium_adjacent")
	var across := medium.duplicate()
	var greatest := 0.0
	for tile in builder.tiles.values():
		if str(tile.type) in ["sea", "deep_sea"]: continue
		var at: Vector3 = builder.point(tile.center)
		if at.distance_squared_to(medium.target) > greatest:
			greatest = at.distance_squared_to(medium.target)
			across.target = at
	await _view(board, across, "medium_across")
	await _view(board, medium, "medium_return")
	var near := medium.duplicate()
	near.span = board.Rig.MIN_SIZE
	near.target = builder.point(builder.tiles.tile_10_10.center)
	await _view(board, near, "closest_first")
	near.target = builder.point(builder.tiles.tile_11_10.center)
	await _view(board, near, "closest_adjacent")
	near.target = builder.point(builder.tiles.tile_10_10.center)
	await _view(board, near, "closest_return")
	await _view(board, far, "far_return")
	run_metadata.total_cache_writes = builder.bake_cache.writes
	run_metadata.total_cache_misses = builder.bake_cache.misses
	_write_render_report()
	for record in results:
		assert(record.missing.is_empty(), "Matched renderer run has missing terrain")
		assert(int(record.cache_writes) == 0, "Benchmark must reuse packaged resources")
	assert(builder.bake_cache.writes == 0, "Benchmark generated a new bake")
