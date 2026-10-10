extends "res://tools/supply_chain_3d/capture.gd"
## Production board/builder only; no profiler subclasses or altered cache policy.
## AGENT_GODOT_WINDOW=1 godot --path . res://tools/supply_chain_3d/review_medium_cache.tscn -- --continent-review --no-telemetry
const OUTPUT := "/private/tmp/medium_resource_cache"
var results: Array = []

func _record(result: Dictionary) -> void:
	results.append(result)
	FileAccess.open(OUTPUT + ".json", FileAccess.WRITE).store_string(JSON.stringify(results, "\t"))
	print("[MEDIUM CACHE] ", JSON.stringify(result))

func _settle(board: Control) -> void:
	while not board.detail_ready():
		RenderingServer.force_draw(false)
		await get_tree().process_frame
	board._update_goods()
	board._labels.queue_redraw()
	await get_tree().physics_frame
	RenderingServer.force_draw(false)
	await get_tree().process_frame

func _visit(board: Control, state: Dictionary, name: String, screenshot: bool = false) -> void:
	var builder: RefCounted = board._builder
	var reads: int = builder.bake_cache.hits
	var writes: int = builder.bake_cache.writes
	var hits: int = builder.resource_cache.hits
	var start := Time.get_ticks_usec()
	board.restore_camera(state)
	await board._stream_visible()
	var attach_ms := (Time.get_ticks_usec() - start) / 1000.0
	await _settle(board)
	var ready_ms := (Time.get_ticks_usec() - start) / 1000.0
	var near_nodes := 0
	var lit_cards := 0
	for pair in builder.sprite_pairs:
		near_nodes += pair.near.size()
		if pair.get("lit", false) and pair.get("medium") != null and pair.medium.is_visible_in_tree(): lit_cards += 1
	var hit: Dictionary = board.pick_at(board.screen_point(state.target), true)
	_record({"stage": name, "attach_ms": attach_ms, "ready_with_draw_ms": ready_ms,
		"disk_reads": builder.bake_cache.hits - reads, "writes": builder.bake_cache.writes - writes,
		"retained_hits": builder.resource_cache.hits - hits, "active_tiles": builder.local_tiles.size(),
		"cached_tiles": builder.resource_cache.entries.size(), "estimated_tile_MiB": builder.resource_cache.bytes / 1048576.0,
		"near_nodes": near_nodes, "lit_cards": lit_cards, "tile_pick": not hit.is_empty(),
		"collision_tiles": builder.collision_tiles.keys(),
		"terrain_colliders": builder.terrain_lods.filter(func(item: Dictionary) -> bool: return item.has("collider") and item.collider.shape != null).size(),
		"fine_tiles": builder.terrain_lods.filter(func(item: Dictionary) -> bool: return item.node.mesh == item.data.meshes[1]).size()})
	if screenshot: get_viewport().get_texture().get_image().save_png(OUTPUT + "_" + name + ".png")

func _continent_review(board: Control, home: Dictionary) -> void:
	await board.set_all_tiles(true, false)
	await _settle(board)
	board.set_process(false)
	var builder: RefCounted = board._builder
	var far: Dictionary = board.capture_camera()
	var focus: Vector3 = home.target
	for tile in builder.tiles.values():
		if "Snare Harbour Coast" in str(tile.label): focus = builder.point(tile.center); break
	var farthest := focus
	var distance := 0.0
	for tile in builder.tiles.values():
		if str(tile.type) in ["sea", "deep_sea"]: continue
		var at: Vector3 = builder.point(tile.center)
		if at.distance_squared_to(focus) > distance:
			farthest = at
			distance = at.distance_squared_to(focus)
	var medium := far.duplicate()
	medium.span = 1100.0
	medium.target = focus
	await _visit(board, medium, "arrive", true)
	var original_meshes := {}
	for item in builder.terrain_lods: original_meshes[item.tile] = item.data.meshes[1]
	var reads: int = builder.bake_cache.hits
	var writes: int = builder.bake_cache.writes
	var nodes: int = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	for i in 5: await board._stream_visible()
	_record({"stage": "prefetch", "checked": board._prefetch_checked.size(),
		"disk_reads": builder.bake_cache.hits - reads, "writes": builder.bake_cache.writes - writes,
		"node_delta": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) - nodes,
		"cached_tiles": builder.resource_cache.entries.size()})
	var adjacent := medium.duplicate()
	adjacent.target += Vector3(405, 0, 240)
	await _visit(board, adjacent, "adjacent", true)
	var across := medium.duplicate()
	across.target = farthest
	await _visit(board, across, "across", true)
	await _visit(board, medium, "return", true)
	var reused := 0
	var expected := 0
	for item in builder.terrain_lods:
		if original_meshes.get(item.tile) != null:
			expected += 1
			if original_meshes[item.tile] == item.data.meshes[1]: reused += 1
	_record({"stage": "identity", "medium_meshes_reused": reused, "expected": expected})
	var orbit := medium.duplicate()
	orbit.yaw += PI * 0.5
	await _visit(board, orbit, "orbit", true)
	var near := medium.duplicate()
	near.span = 450.0
	await _visit(board, near, "near", true)
	await _visit(board, medium, "medium_after_near", true)
	await _visit(board, across, "across_after_near")
	await _visit(board, medium, "return_after_near")
	await _visit(board, far, "far", true)
	# Advance only the disposable deadline, not the retention policy. Far drops
	# hidden scene nodes while resources remain available for subsequent zoom-in.
	board._far_detail_expires_msec = Time.get_ticks_msec() - 1
	await board._stream_visible()
	_record({"stage": "far_nodes_released", "active_tiles": builder.local_tiles.size(),
		"cached_tiles": builder.resource_cache.entries.size()})
	await _visit(board, medium, "medium_after_far_release")
	var lit_bytes := 0
	var lit_atlases := 0
	for key in builder.FarSprites._materials:
		if not str(key).ends_with(":lit"): continue
		var texture: Texture2D = builder.FarSprites._materials[key].get_shader_parameter("artwork")
		lit_bytes += builder.TileCache.estimate({"textures": [null, texture]}, {})
		lit_atlases += 1
	_record({"stage": "shared_assets", "loaded_lit_atlases": lit_atlases,
		"lit_colour_MiB": lit_bytes / 1048576.0, "loaded_picking_shapes": builder.Assets._picking.size()})
	# Matched camera/terrain reference isolates sprite versus original model.
	for pair in builder.sprite_pairs:
		if not pair.get("lit", false) or not pair.get("standing") is Dictionary or str(pair.standing.kind) not in ["building", "site", "warehouse", "suppliers"]: continue
		var lit_view := medium.duplicate()
		lit_view.target = pair.root.position
		await _visit(board, lit_view, "lit_medium", true)
		var selectable := 0
		for candidate in builder.sprite_pairs:
			if not candidate.get("standing") is Dictionary or str(candidate.standing.kind) not in ["building", "site", "warehouse", "suppliers"]: continue
			var point: Vector3 = candidate.root.position + Vector3.UP * float(candidate.dimension.y) * 0.5
			var screen: Vector2 = board.screen_point(point)
			if not Rect2(Vector2.ZERO, board.size).has_point(screen): continue
			var hit: Dictionary = board.pick_at(screen)
			if not hit.is_empty() and str(hit.collider.get_meta("standing", {}).get("iid", "")) == str(candidate.standing.iid): selectable += 1
		_record({"stage": "building_picking", "matched_building_hits": selectable})
		builder.active_lod = 2
		builder._update_asset_tier()
		await _settle(board)
		get_viewport().get_texture().get_image().save_png(OUTPUT + "_lit_mesh_reference.png")
		builder.active_lod = board._detail
		builder._update_asset_tier()
		break
