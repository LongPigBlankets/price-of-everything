extends "res://tools/supply_chain_3d/profile_streaming_ready.gd"
## Frame attribution for the streaming profile: splits each slow frame into
## draw time and script time, and records pipeline compilations and video memory.
## AGENT_GODOT_WINDOW=1 godot --path . res://tools/supply_chain_3d/trials/profile_hitches.tscn -- \
##   --continent-review --no-telemetry --trial-extra-edges --trial-idle-prefetch \
##   --trial-output=<dir> --bake-cache-directory=<new empty dir>
const PIPELINES := {"canvas": Performance.PIPELINE_COMPILATIONS_CANVAS, "mesh": Performance.PIPELINE_COMPILATIONS_MESH,
	"surface": Performance.PIPELINE_COMPILATIONS_SURFACE, "draw": Performance.PIPELINE_COMPILATIONS_DRAW,
	"specialization": Performance.PIPELINE_COMPILATIONS_SPECIALIZATION}
var frame_rows := []
var view_name := "first_open"
var draw_started := 0
var draw_usec := 0
var draws := 0
var last_pipelines := {}
var frame_started := 0
var peak_video := {}

func _ready() -> void:
	RenderingServer.frame_pre_draw.connect(func() -> void: draw_started = Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(func() -> void:
		if draw_started > 0: draw_usec += Time.get_ticks_usec() - draw_started; draws += 1
		draw_started = 0)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--trial-output="): output = arg.trim_prefix("--trial-output=")
	DirAccess.make_dir_recursive_absolute(output)
	_vram_stage("startup")
	await super._ready()

func _rd_memory(kind: int) -> float:
	var device := RenderingServer.get_rendering_device()
	return device.get_memory_usage(kind) / 1048576.0 if device != null else 0.0

func _pipelines() -> Dictionary:
	var values := {}
	for name in PIPELINES: values[name] = int(Performance.get_monitor(PIPELINES[name]))
	return values

func _frame() -> void:
	super._frame()
	var now := Time.get_ticks_usec()
	var current := _pipelines()
	if frame_started > 0:
		var row := {"view": view_name, "sampling": sampling, "start": frame_started, "end": now, "ms": (now - frame_started) / 1000.0, "draw_ms": draw_usec / 1000.0, "draws": draws,
			"video_MiB": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
			"texture_MiB": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
			"buffer_MiB": Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0,
			"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
			"rd_total_MiB": _rd_memory(RenderingDevice.MEMORY_TOTAL), "rd_textures_MiB": _rd_memory(RenderingDevice.MEMORY_TEXTURES),
			"rd_buffers_MiB": _rd_memory(RenderingDevice.MEMORY_BUFFERS)}
		for name in current: row["new_" + name] = current[name] - int(last_pipelines.get(name, current[name]))
		frame_rows.append(row)
		peak_video[view_name] = maxf(float(peak_video.get(view_name, 0.0)), row.rd_total_MiB)
	last_pipelines = current
	frame_started = now
	draw_usec = 0
	draws = 0

var vram_stages := {}

func _vram_stage(stage: String) -> void:
	vram_stages[stage] = {"rd_total_MiB": _rd_memory(RenderingDevice.MEMORY_TOTAL),
		"rd_textures_MiB": _rd_memory(RenderingDevice.MEMORY_TEXTURES), "rd_buffers_MiB": _rd_memory(RenderingDevice.MEMORY_BUFFERS),
		"static_MiB": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0}
	if traced_board != null and traced_board._builder != null:
		vram_stages[stage].tile_cache_MiB = traced_board._builder.resource_cache.bytes / 1048576.0
		vram_stages[stage].local_tiles = traced_board._builder.local_tiles.size()
	if not output.is_empty(): FileAccess.open(output.path_join("vram.json"), FileAccess.WRITE).store_string(JSON.stringify(vram_stages, "\t"))

func _continent_review(board: Control, home: Dictionary) -> void:
	# Optional span tracing: present only while a board carries debug hooks.
	if "trace_enabled" in board: board.trace_enabled = true
	traced_board = board
	_vram_stage("owned_view")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--owned-dwell="):
			# A player looks at their company first; idle warming runs meanwhile.
			while not board.background_ready() or board.background_active(): await get_tree().process_frame
			var until := Time.get_ticks_msec() + int(float(arg.trim_prefix("--owned-dwell=")) * 1000.0)
			while Time.get_ticks_msec() < until: await get_tree().process_frame
			var continent_builder: RefCounted = board._coverage_states[true].builder
			print("[OWNED DWELL] warmed ", continent_builder.ground_warmed.size(), " tiles")
	if "--bench-ground" in OS.get_cmdline_user_args():
		while not board.background_ready(): await get_tree().process_frame
		var builder: RefCounted = board._coverage_states[true].builder
		var costs := []
		var total := Time.get_ticks_usec()
		for tid in builder.tiles:
			var t := Time.get_ticks_usec()
			var c: Vector2 = builder.tiles[tid].center
			for offset in [Vector2.ZERO, Vector2(120, 0), Vector2(-120, 0), Vector2(60, 100), Vector2(-60, -100), Vector2(60, -100), Vector2(-60, 100)]:
				builder.surface_height(c + offset)
			costs.append((Time.get_ticks_usec() - t) / 1000.0)
		costs.sort()
		print("[GROUND WARM] tiles=", costs.size(), " total_ms=", (Time.get_ticks_usec() - total) / 1000.0, " p50=", costs[costs.size() / 2], " p90=", costs[int(costs.size() * 0.9)], " max=", costs[-1])
	await super._continent_review(board, home)
	_vram_stage("after_trials")
	await _play_pan(board)
	_vram_stage("after_play")
	_census("after_play")
	await _hidden_return(board)

func _hidden_return(board: Control) -> void:
	var idle := Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < idle: await get_tree().process_frame
	_vram_stage("still_12s")
	var empire: Control = get_tree().root.find_child("EmpireView", true, false)
	empire.toggle() # what Tab does: back to the 2D map
	var until := Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < until: await get_tree().process_frame
	_vram_stage("hidden_12s")
	view_name = "return_after_hidden"
	_sample()
	var started := Time.get_ticks_msec()
	empire.toggle()
	await get_tree().process_frame
	while not board.detail_ready() or board._streaming or board.capture_camera() != board._stream_camera:
		await get_tree().process_frame
		if Time.get_ticks_msec() - started > 20000: errors.append("Return after hidden timeout"); break
	sampling = false
	var record := _stats(); record.view = "return_after_hidden"; record.load_ms = Time.get_ticks_msec() - started
	record.active_tiles = board._builder.local_tiles.size()
	records.append(record); print("[STREAM TRIAL] ", JSON.stringify(record)); _save(board)
	_vram_stage("returned")
	_write_hitches()

func _play_pan(board: Control) -> void:
	# Real play keeps _process, labels and animated goods on; the base profile
	# turns them off to isolate streaming. Pan continuously like a player.
	board.set_process(true); board._labels.show(); board.animate_goods = true
	var builder: RefCounted = board._builder
	for phase in [{"name": "play_medium", "span": board.size.y, "pitch": 0.6}, {"name": "play_closest", "span": board.Rig.MIN_SIZE, "pitch": board.Rig.HOME_PITCH}]:
		var camera: Dictionary = board.capture_camera()
		camera.target = builder.point(builder.tiles.tile_9_9.center)
		camera.span = phase.span; camera.pitch = phase.pitch; camera.yaw = board.Rig.HOME_YAW
		board.restore_camera(camera)
		var settle := Time.get_ticks_msec()
		while not board.detail_ready() and Time.get_ticks_msec() - settle < 20000: await get_tree().process_frame
		view_name = phase.name
		_sample()
		var started := Time.get_ticks_msec()
		var direction := Vector3(1, 0, 0.35).normalized()
		while Time.get_ticks_msec() - started < 8000:
			# About one tile width every two seconds at medium zoom.
			camera.target += direction * (phase.span * 0.004)
			board.restore_camera(camera)
			await get_tree().process_frame
		sampling = false
		var record := _stats(); record.view = phase.name
		records.append(record); print("[STREAM TRIAL] ", JSON.stringify(record)); _save(board)
		view_name = phase.name + "_after"

var traced_board: Control

func _sample() -> void:
	super._sample()
	# Harness work between views (PNG saves, camera search) is not a game frame.
	frame_started = Time.get_ticks_usec(); draw_usec = 0; draws = 0; last_pipelines = _pipelines()

func _view_trial(board: Control, camera: Dictionary, name: String) -> void:
	if name == "closest_first": _vram_stage("after_first_open"); _census("after_first_open")
	view_name = name
	await super._view_trial(board, camera, name)
	if name in ["closest_return", "medium_shallow", "mountains_jump"]: _vram_stage("after_" + name)
	view_name = name + "_after"
	_write_hitches()

func _write_hitches() -> void:
	if output.is_empty(): return
	var slow := frame_rows.filter(func(row: Dictionary) -> bool: return row.ms > 30.0 and row.sampling)
	var trace: Array = traced_board.stream_trace if traced_board != null and "stream_trace" in traced_board else []
	for row in slow:
		var spans := {}
		for span in trace:
			if span.t > row.start and span.t <= row.end:
				spans[span.l] = snappedf(float(spans.get(span.l, 0.0)) + span.ms, 0.1)
		row.spans = spans
	var totals := {}
	for row in frame_rows:
		for name in PIPELINES: totals[name] = int(totals.get(name, 0)) + int(row["new_" + name])
	var by_view := {}
	for row in frame_rows:
		if not row.sampling: continue
		var entry: Dictionary = by_view.get_or_add(row.view, {"frames": 0, "over_33": 0, "max_ms": 0.0, "sum_ms": 0.0, "max_rd_MiB": 0.0})
		entry.frames += 1; entry.sum_ms += row.ms; entry.max_ms = maxf(entry.max_ms, row.ms)
		entry.max_rd_MiB = maxf(entry.max_rd_MiB, row.rd_total_MiB)
		if row.ms > 33.4: entry.over_33 += 1
	var report := {"by_view": by_view, "slow_frames": slow, "peak_video_MiB": peak_video, "pipeline_totals": totals, "frames": frame_rows.size(),
		"final_video_MiB": frame_rows[-1].rd_total_MiB if not frame_rows.is_empty() else 0.0}
	FileAccess.open(output.path_join("hitches.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))

func _open_supply_view(view: Control) -> void:
	_vram_stage("game_before_3d")
	_census("game_before_3d")
	await super._open_supply_view(view)

# --- Texture census: unique live textures reachable from the scene tree. ---
var _census_seen := {}
var _census_textures := {}

func _bytes_per_pixel(format: int) -> float:
	match format:
		RenderingDevice.DATA_FORMAT_BC1_RGB_UNORM_BLOCK, RenderingDevice.DATA_FORMAT_BC1_RGB_SRGB_BLOCK, \
		RenderingDevice.DATA_FORMAT_BC1_RGBA_UNORM_BLOCK, RenderingDevice.DATA_FORMAT_BC1_RGBA_SRGB_BLOCK, \
		RenderingDevice.DATA_FORMAT_BC4_UNORM_BLOCK, RenderingDevice.DATA_FORMAT_ETC2_R8G8B8_UNORM_BLOCK:
			return 0.5
		RenderingDevice.DATA_FORMAT_BC3_UNORM_BLOCK, RenderingDevice.DATA_FORMAT_BC3_SRGB_BLOCK, \
		RenderingDevice.DATA_FORMAT_BC5_UNORM_BLOCK, RenderingDevice.DATA_FORMAT_BC7_UNORM_BLOCK, \
		RenderingDevice.DATA_FORMAT_BC7_SRGB_BLOCK, RenderingDevice.DATA_FORMAT_ASTC_4x4_UNORM_BLOCK, \
		RenderingDevice.DATA_FORMAT_ASTC_4x4_SRGB_BLOCK, RenderingDevice.DATA_FORMAT_ETC2_R8G8B8A8_UNORM_BLOCK, \
		RenderingDevice.DATA_FORMAT_R8_UNORM:
			return 1.0
		RenderingDevice.DATA_FORMAT_R8G8_UNORM, RenderingDevice.DATA_FORMAT_R16_SFLOAT, RenderingDevice.DATA_FORMAT_R16_UNORM:
			return 2.0
		RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, RenderingDevice.DATA_FORMAT_R32G32_SFLOAT:
			return 8.0
		RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT:
			return 16.0
	return 4.0

func _census_texture(texture: Texture2D, owner: String) -> void:
	var id := texture.get_instance_id()
	if _census_textures.has(id): return
	var device := RenderingServer.get_rendering_device()
	var rid := RenderingServer.texture_get_rd_texture(texture.get_rid())
	if device == null or not rid.is_valid(): return
	var info: RDTextureFormat = device.texture_get_format(rid)
	var bytes := float(info.width * info.height) * _bytes_per_pixel(info.format) * float(info.array_layers)
	if info.mipmaps > 1: bytes *= 1.333
	var path := texture.resource_path
	var group := path.get_base_dir() if path != "" and not path.contains("::") else ("embedded:" + path.get_slice("::", 0).get_base_dir() if path != "" else "runtime:" + owner)
	_census_textures[id] = {"group": group, "bytes": bytes, "size": "%dx%d f%d m%d" % [info.width, info.height, info.format, info.mipmaps]}

func _census_value(value: Variant, owner: String, depth: int) -> void:
	if value is Texture2D: _census_texture(value, owner)
	elif value is Resource: _census_resource(value, owner, depth + 1)
	elif value is RefCounted and depth < 6 and not _census_seen.has(value.get_instance_id()):
		_census_seen[value.get_instance_id()] = true
		var script := (value as Object).get_script() as Script
		var name: String = script.resource_path.get_file() if script != null else value.get_class()
		for property in (value as Object).get_property_list():
			if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.type in [TYPE_OBJECT, TYPE_ARRAY, TYPE_DICTIONARY]:
				_census_value((value as Object).get(property.name), owner + ">" + name, depth + 1)
	elif value is Array:
		for item in value: _census_value(item, owner, depth)
	elif value is Dictionary:
		for item in value.values(): _census_value(item, owner, depth)

func _census_resource(resource: Resource, owner: String, depth: int) -> void:
	if resource == null or depth > 6 or _census_seen.has(resource.get_instance_id()): return
	_census_seen[resource.get_instance_id()] = true
	if resource is Script: return
	if resource is ShaderMaterial and resource.shader != null:
		for uniform in resource.shader.get_shader_uniform_list():
			_census_value(resource.get_shader_parameter(uniform.name), owner, depth)
	for property in resource.get_property_list():
		if property.type in [TYPE_OBJECT, TYPE_ARRAY, TYPE_DICTIONARY] and property.usage & PROPERTY_USAGE_STORAGE:
			_census_value(resource.get(property.name), owner, depth)
	if resource is Mesh:
		for surface in resource.get_surface_count(): _census_value(resource.surface_get_material(surface), owner, depth)
	if resource is MultiMesh: _census_value(resource.mesh, owner, depth)

func _census(stage: String) -> void:
	# Reading mesh properties forces GPU read-backs; never run it in timing runs.
	if not "--census" in OS.get_cmdline_user_args(): return
	_census_seen.clear(); _census_textures.clear()
	for node in get_tree().root.find_children("*", "", true, false):
		var owner := node.get_class()
		var script := node.get_script() as Script
		if script != null: owner = script.resource_path.get_file()
		for property in node.get_property_list():
			if property.type in [TYPE_OBJECT, TYPE_ARRAY, TYPE_DICTIONARY] and property.usage & (PROPERTY_USAGE_STORAGE | PROPERTY_USAGE_SCRIPT_VARIABLE):
				var value: Variant = node.get(property.name)
				if value is Node: continue
				_census_value(value, owner, 0)
	var reached := _census_textures.size()
	for path in _script_paths("res://scripts"):
		if not ResourceLoader.has_cached(path): continue
		var script: Script = load(path)
		for property in script.get_property_list():
			if property.type in [TYPE_OBJECT, TYPE_ARRAY, TYPE_DICTIONARY] and not property.name.begins_with("script") and property.name != "resource_local_to_scene":
				var value: Variant = script.get(property.name)
				if value is Node or value is Script: continue
				_census_value(value, "static:" + path.get_file(), 0)
	var groups := {}
	var total := 0.0
	for item in _census_textures.values():
		var entry: Dictionary = groups.get_or_add(item.group, {"count": 0, "MiB": 0.0, "largest": ""})
		entry.count += 1; entry.MiB += item.bytes / 1048576.0; total += item.bytes
		if entry.largest == "": entry.largest = item.size
	var keys := groups.keys(); keys.sort_custom(func(a, b): return groups[a].MiB > groups[b].MiB)
	var listed := []
	for key in keys.slice(0, 45): listed.append([key, snappedf(groups[key].MiB, 0.1), groups[key].count, groups[key].largest])
	var report := {"stage": stage, "reached_from_tree": reached, "total_MiB": total / 1048576.0, "textures": _census_textures.size(), "rd_total_MiB": _rd_memory(RenderingDevice.MEMORY_TOTAL), "groups": listed}
	FileAccess.open(output.path_join("census_" + stage + ".json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))

func _script_paths(directory: String) -> Array:
	var paths := []
	for file in DirAccess.get_files_at(directory):
		if file.ends_with(".gd"): paths.append(directory.path_join(file))
	for sub in DirAccess.get_directories_at(directory): paths.append_array(_script_paths(directory.path_join(sub)))
	return paths

