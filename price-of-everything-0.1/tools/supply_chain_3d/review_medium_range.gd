extends "res://tools/supply_chain_3d/capture.gd"
## Production coverage/appearance review across the whole local-medium range.
## AGENT_GODOT_WINDOW=1 godot --path . res://tools/supply_chain_3d/review_medium_range.tscn -- --continent-review --no-telemetry
var output := "res://../outputs/supply-chain-3d/medium-range/"
var results: Array = []

func _save_report() -> void:
	FileAccess.open(output.path_join("measurements.json"), FileAccess.WRITE).store_string(JSON.stringify(results, "\t"))

func _draw_view(board: Control, name: String) -> void:
	board._update_goods()
	for i in 3:
		RenderingServer.force_draw(false)
		await get_tree().process_frame
	assert(board._viewport.get_texture().get_image().save_png(output.path_join(name + ".png")) == OK)

func _view(board: Control, state: Dictionary, name: String) -> void:
	var builder: RefCounted = board._builder
	var writes: int = builder.bake_cache.writes
	var start := Time.get_ticks_msec()
	board.restore_camera(state)
	# Match a player keeping the cursor at viewport centre during the camera move.
	board._update_cursor_collision(board.size * 0.5)
	await board._stream_visible()
	while not board.detail_ready():
		RenderingServer.force_draw(false)
		await get_tree().process_frame
	board._update_cursor_collision(board.size * 0.5)
	var elapsed := Time.get_ticks_msec() - start
	var wanted: Array = board._wanted_detail_tiles()
	var plan: Dictionary = board._fine_detail_plan(wanted)
	var missing := []
	for item in wanted:
		if item.visible and not builder.local_tiles.has(item.tile): missing.append(item.tile + ":scene")
	for item in builder.terrain_lods:
		if plan.has(item.tile) and item.node.mesh != item.data.meshes[plan[item.tile]]: missing.append(item.tile + ":terrain")
	var record := {"view": name, "ppu": board.size.y / state.span, "terrain_tier": board._detail,
		"visible_tiles": wanted.filter(func(item: Dictionary) -> bool: return item.visible).size(),
		"active_tiles": builder.local_tiles.size(), "fine_tiles": plan.size(), "missing": missing,
		"collision_tiles": builder.collision_tiles.keys(),
		"terrain_colliders": builder.terrain_lods.filter(func(item: Dictionary) -> bool: return item.has("collider") and item.collider.shape != null).size(),
		"cache_writes": builder.bake_cache.writes - writes, "load_ms": elapsed,
		"tile_cache_MiB": builder.resource_cache.bytes / 1048576.0,
		"camera": {"target": [state.target.x, state.target.y, state.target.z], "span": state.span, "pitch": state.pitch, "yaw": state.yaw}}
	results.append(record)
	_save_report()
	print("[MEDIUM RANGE] ", JSON.stringify(record))
	await _draw_view(board, name)

func _continent_review(board: Control, home: Dictionary) -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--range-output="): output = arg.trim_prefix("--range-output=")
	DirAccess.make_dir_recursive_absolute(output)
	await board.set_all_tiles(true, false)
	while not board.detail_ready():
		RenderingServer.force_draw(false)
		await get_tree().process_frame
	board.set_process(false)
	board._labels.hide()
	board.animate_goods = false
	var builder: RefCounted = board._builder
	# An empty runtime directory proves that every reviewed medium tile ships.
	builder.bake_cache.directory = "user://medium-review-empty-%d" % Time.get_ticks_usec()
	var state: Dictionary = board.capture_camera()
	state.target = home.target
	for tile in builder.tiles.values():
		if "Stoneshore Coast" in str(tile.label): state.target = builder.point(tile.center); break
	state.span = board.size.y
	await _view(board, state, "coast_middle")
	state.span = board.size.y / 0.70
	await _view(board, state, "coast_widest_fine")
	# Matched diagnostic reconstructs the previous fixed-24 policy for comparison.
	var wanted: Array = board._wanted_detail_tiles()
	var old_keep := {}
	for item in wanted.slice(0, 24): old_keep[item.tile] = true
	for item in builder.terrain_lods:
		if not old_keep.has(item.tile): builder.apply_tile_detail(item, 0)
	await _draw_view(board, "coast_old_24_tile_limit")
	var plan: Dictionary = board._fine_detail_plan(wanted)
	for item in builder.terrain_lods:
		if plan.has(item.tile): builder.apply_tile_detail(item, plan[item.tile])
	state.span = board.size.y / 1.70
	await _view(board, state, "coast_closest_medium")
	state.span = board.size.y / 0.34
	await _view(board, state, "coast_widest_local")
	state.span = board.size.y
	state.target += Vector3(405, 0, -480)
	await _view(board, state, "rivers_middle")
	state.span = board.size.y / 1.70
	await _view(board, state, "rivers_close")
	state.yaw = deg_to_rad(11.0)
	await _view(board, state, "angle_before")
	state.yaw = deg_to_rad(11.5)
	await _view(board, state, "angle_after")
	state.yaw = deg_to_rad(5.5)
	await _view(board, state, "pylon_angle_before")
	state.yaw = deg_to_rad(5.75)
	await _view(board, state, "pylon_angle_after")
	state.yaw = PI / 4.0
	state.pitch = 0.6932
	await _view(board, state, "pitch_before")
	state.pitch = 0.6943
	await _view(board, state, "pitch_after")
	state.yaw = PI * 0.75
	state.pitch = 1.35
	await _view(board, state, "city_high_pitch")
	var summit := Vector2.ZERO
	var top := -INF
	for tile in builder.tiles.values():
		for y in range(-180, 181, 90):
			for x in range(-180, 181, 90):
				var p: Vector2 = tile.center + Vector2(x, y)
				var h: float = builder.surface_height(p)
				if h > top: top = h; summit = p
	var peak: Vector3 = builder.point(summit)
	state.target = peak
	state.span = board.size.y / 0.70
	state.pitch = 0.30
	state.yaw = PI / 4.0
	await _view(board, state, "mountains_low_pitch")
	# Move the summit to the viewport bottom while its foot lies below the frame.
	state.span = board.size.y / 1.2
	state.target = peak - Vector3(sin(state.yaw), 0, cos(state.yaw)) * (state.span * 0.5 - 4.0 / 1.2) / sin(state.pitch)
	await _view(board, state, "summit_at_bottom_edge")
	var peak_tid: String = builder.tile_at(peak)
	results.append({"summit_tile": peak_tid, "summit_local": builder.local_tiles.has(peak_tid),
		"summit_screen": str(board.screen_point(peak)), "summit_height": top})
	var tallest := {}
	for s in board._model.standing:
		var frame: Dictionary = builder.standing_frame(s)
		if tallest.is_empty() or frame.dimension.y > tallest.frame.dimension.y: tallest = {"standing": s, "frame": frame}
	var roof: Vector3 = tallest.frame.position + Vector3.UP * float(tallest.frame.dimension.y)
	state.target = roof - Vector3(sin(state.yaw), 0, cos(state.yaw)) * (state.span * 0.5 - 4.0 / 1.2) / sin(state.pitch)
	await _view(board, state, "tower_at_bottom_edge")
	results.append({"tower_tile": tallest.standing.tile, "tower_local": builder.local_tiles.has(tallest.standing.tile), "roof_screen": str(board.screen_point(roof))})
	board.fit_view()
	await _view(board, board.capture_camera(), "far_fit")
	var far_state: Dictionary = board.capture_camera()
	far_state.span = board.size.y / 0.30
	far_state.target = home.target
	await _view(board, far_state, "far_closest")
	_save_report()
