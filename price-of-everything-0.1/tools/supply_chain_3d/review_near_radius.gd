extends "res://tools/supply_chain_3d/review_medium_range.gd"
## Exercise real near streaming, a neighbouring pan, retained resources and expiry.

func _continent_review(board: Control, _home: Dictionary) -> void:
	output = "res://../outputs/supply-chain-3d/near-radius/"
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
	if "--bundled-only" in OS.get_cmdline_user_args():
		# No runtime cache fallback: every requested near tile must ship on disk.
		builder.bake_cache.directory = "user://near-package-review-empty-%d" % Time.get_ticks_usec()
	var state: Dictionary = board.capture_camera()
	state.span = board.Rig.MIN_SIZE
	state.pitch = board.Rig.HOME_PITCH
	state.yaw = board.Rig.HOME_YAW
	state.target = builder.point(builder.tiles.tile_10_10.center)
	await _view(board, state, "closest_first")
	var first := {}
	for item in board._wanted_detail_tiles():
		if item.near: first[item.tile] = builder.resource_cache.entries[item.tile].data.meshes[2].get_instance_id()
	assert(first.size() == 61)
	state.target = builder.point(builder.tiles.tile_11_10.center)
	await _view(board, state, "closest_adjacent")
	var second := {}
	for item in board._wanted_detail_tiles():
		if item.near: second[item.tile] = true
	assert(second.size() == 61)
	var reused := 0
	var departed := []
	for tid in first:
		assert(builder.resource_cache.entries.has(tid), "Departed resources must survive the ten-second grace period")
		assert(builder.resource_cache.entries[tid].data.meshes[2].get_instance_id() == first[tid], "Cached near geometry must survive the pan")
		if second.has(tid): reused += 1
		else: departed.append(tid)
	results.append({"near_radius": board.NEAR_TILE_RADIUS, "first_tiles": first.size(), "second_tiles": second.size(),
		"shared_near_resources": reused, "departed_retained": departed.size(),
		"near_resource_MiB": builder.resource_cache.bytes / 1048576.0})
	state.target = builder.point(builder.tiles.tile_10_10.center)
	await _view(board, state, "closest_return")
	# A far zoom ends residency but preserves the ten-second view/resource grace.
	board.fit_view()
	await _view(board, board.capture_camera(), "far_grace")
	assert(not builder.local_tiles.is_empty())
	board._far_detail_expires_msec = Time.get_ticks_msec() - 1
	for entry in builder.resource_cache.entries.values(): entry.last_used = Time.get_ticks_msec() - 10001
	await board._stream_visible()
	assert(builder.local_tiles.is_empty())
	assert(builder.resource_cache.bytes <= builder.resource_cache.target_bytes)
	results.append({"expired_scene_tiles": builder.local_tiles.size(), "after_expiry_MiB": builder.resource_cache.bytes / 1048576.0,
		"evictions": builder.resource_cache.evictions})
	_save_report()
	if "--bundled-only" in OS.get_cmdline_user_args():
		for result in results:
			assert(int(result.get("cache_writes", 0)) == 0, "Bundled closest terrain must not need runtime generation")
	print("[NEAR RADIUS] ", JSON.stringify(results.slice(-2)))
