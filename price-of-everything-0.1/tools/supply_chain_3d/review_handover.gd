extends "res://tools/supply_chain_3d/capture.gd"
## Capture both rendered intermediate frames and time repeated switches.
## AGENT_GODOT_WINDOW=1 godot --path . res://tools/supply_chain_3d/review_handover.tscn -- --continent-review --no-telemetry
var _board: Control
var _tag := ""
var _capture := false
var _draw_blend := -1.0
var _seen := {}
var _samples: Array = []
var _frames: Array = []
var _last_tick := 0
var _draw_start := 0

func _pre_draw() -> void:
	if _tag == "": return
	_draw_blend = _board._builder.handover.blend
	_draw_start = Time.get_ticks_usec()

func _frame_gap() -> void:
	if _tag == "": return
	var now := Time.get_ticks_usec()
	if _last_tick > 0: _frames.append((now - _last_tick) / 1000.0)
	_last_tick = now

func _post_draw() -> void:
	var before := Time.get_ticks_usec()
	_board._on_rendered_frame()
	var advance_ms := (Time.get_ticks_usec() - before) / 1000.0
	if _tag == "" or _draw_blend <= 0.0 or _draw_blend >= 1.0: return
	var key := "%s_%d" % [_tag, roundi(_draw_blend * 100)]
	if _seen.has(key): return
	_seen[key] = true
	if _capture and _tag == "in":
		for binding in _board._builder.handover._bindings:
			if binding.original is ShaderMaterial and binding.original.shader.resource_path.ends_with("far_sprite.gdshader"):
				print("[HANDOVER MATERIAL] colour_same=", binding.original.get_shader_parameter("artwork") == binding.node.material_override.get_shader_parameter("artwork"),
					" depth_same=", binding.original.get_shader_parameter("depth_art") == binding.node.material_override.get_shader_parameter("depth_art"))
				break
	_samples.append({"stage": _tag, "blend": _draw_blend, "tiles": _board._builder.local_tiles.size(),
		"render_ms": (before - _draw_start) / 1000.0, "advance_ms": advance_ms})
	if _capture: get_viewport().get_texture().get_image().save_png("/private/tmp/handover_" + key + ".png")

func _switch(state: Dictionary, tag: String, capture: bool) -> Dictionary:
	_tag = tag
	_capture = capture
	_seen.clear()
	_samples.clear()
	_frames.clear()
	_last_tick = Time.get_ticks_usec()
	var start := _last_tick
	var hits: int = _board._builder.bake_cache.hits
	var writes: int = _board._builder.bake_cache.writes
	_board.restore_camera(state)
	var camera_ms := (Time.get_ticks_usec() - start) / 1000.0
	await _board._stream_visible()
	var first_stream_ms := (Time.get_ticks_usec() - start) / 1000.0
	while not _board.detail_ready():
		RenderingServer.force_draw(false)
		await get_tree().process_frame
	# The outgoing view remains cached for ten seconds after both draws.
	await _board._stream_visible()
	while not _board.detail_ready():
		RenderingServer.force_draw(false)
		await get_tree().process_frame
	var elapsed := (Time.get_ticks_usec() - start) / 1000.0
	var endpoint_draws: Array = []
	for i in 3:
		var draw_start := Time.get_ticks_usec()
		RenderingServer.force_draw(false)
		endpoint_draws.append((Time.get_ticks_usec() - draw_start) / 1000.0)
		await get_tree().process_frame
	var result := {"stage": tag, "capture": capture, "ready_ms": elapsed, "camera_ms": camera_ms, "first_stream_ms": first_stream_ms,
		"max_frame_ms": _frames.max() if not _frames.is_empty() else 0.0,
		"intermediate_frames": _samples.duplicate(true), "tiles_after": _board._builder.local_tiles.size(),
		"final_blend": _board._builder.handover.blend, "endpoint_draw_ms": endpoint_draws,
		"cache_reads": _board._builder.bake_cache.hits - hits, "cache_writes": _board._builder.bake_cache.writes - writes}
	print("[HANDOVER] ", JSON.stringify(result))
	if capture: get_viewport().get_texture().get_image().save_png("/private/tmp/handover_" + tag + "_complete.png")
	_tag = ""
	return result

func _continent_review(board: Control, home: Dictionary) -> void:
	await board.set_all_tiles(true, false)
	while not board.detail_ready():
		RenderingServer.force_draw(false)
		await get_tree().process_frame
	board.set_process(false)
	_board = board
	RenderingServer.frame_post_draw.disconnect(board._on_rendered_frame)
	RenderingServer.frame_pre_draw.connect(_pre_draw)
	RenderingServer.frame_post_draw.connect(_post_draw)
	get_tree().process_frame.connect(_frame_gap)
	var far: Dictionary = board.capture_camera()
	var medium := far.duplicate()
	medium.span = 1100.0
	medium.target = home.target
	for tile in board._builder.tiles.values():
		if "Snare Harbour Coast" in str(tile.label): medium.target = board._builder.point(tile.center); break
	far.target = medium.target
	var results: Array = []
	results.append(await _switch(medium, "in", true))
	await get_tree().physics_frame
	var hit: Dictionary = board.pick_at(board.screen_point(medium.target), true)
	results.append({"medium_tile_pick": not hit.is_empty()})
	results.append(await _switch(far, "out", true))
	results.append(await _switch(medium, "timed_in", false))
	results.append(await _switch(far, "timed_out", false))
	results.append(await _switch(medium, "repeat_in", false))
	results.append(await _switch(far, "repeat_out", false))
	var file := FileAccess.open("/private/tmp/supply_handover_review.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))
	RenderingServer.frame_pre_draw.disconnect(_pre_draw)
	RenderingServer.frame_post_draw.disconnect(_post_draw)
	get_tree().process_frame.disconnect(_frame_gap)
