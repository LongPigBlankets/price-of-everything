extends "res://scripts/supply_chain_3d/board.gd"
## Disposable A/B policy, never instantiated by the shipped game.
## _stream_visible is a frozen copy of the production loop with read-ahead hooks.
const ReadAhead = preload("res://tools/supply_chain_3d/trials/stream_read_ahead.gd")
var trial_visibility := "--trial-visibility" in OS.get_cmdline_user_args()
var trial_queue := "--trial-queue" in OS.get_cmdline_user_args()
var queue_reports := []
var trial_rear := "--trial-rear" in OS.get_cmdline_user_args()
var demoted_tiles := []

func _wanted_detail_tiles() -> Array:
	var original := super._wanted_detail_tiles()
	if not trial_visibility or _builder == null or _builder._overview: return original
	var result := []
	demoted_tiles.clear()
	var margin := Rect2(-size * 0.20, size * 1.40)
	var candidates := []
	# Keep resources for recent/nearby tiles under the existing ten-second rule.
	# Scene nodes are required only for visible bounds. The original visibility
	# test includes baked height/building bounds and a conservative 40px guard.
	for item in original:
		if item.visible:
			var demote := false
			# Reuse the far backdrop only for tiles entirely in the rear third.
			if trial_rear and _detail == 1 and not _builder.backdrop_pending and _rig.pitch < 0.45 and item.ring > 1:
				var points: PackedVector3Array = _builder.tile_view_hull(item.tile)
				var bounds := Rect2(screen_point(points[0]), Vector2.ZERO)
				for p in points: bounds = bounds.expand(screen_point(p))
				demote = bounds.end.y < size.y * 0.35
			if demote: demoted_tiles.append(item.tile)
			else: result.append(item)
		else:
			var points: PackedVector3Array = _builder.tile_view_hull(item.tile)
			var bounds := Rect2(screen_point(points[0]), Vector2.ZERO)
			for p in points: bounds = bounds.expand(screen_point(p))
			if bounds.intersects(margin): candidates.append({"tile":item.tile,"distance":item.distance,"ahead":false})
	for item in _prefetch_tiles:
		var points: PackedVector3Array = _builder.tile_view_hull(item.tile)
		var bounds := Rect2(screen_point(points[0]), Vector2.ZERO)
		for p in points: bounds = bounds.expand(screen_point(p))
		if bounds.intersects(margin): candidates.append(item)
	candidates.sort_custom(func(a:Dictionary,b:Dictionary)->bool:
		if a.ahead != b.ahead: return a.ahead
		return a.distance < b.distance)
	_prefetch_tiles = candidates.slice(0,PREFETCH_TILES)
	return result

func _prefetch_resources(builder: RefCounted, generation: int, camera_state: Dictionary) -> void:
	if not trial_visibility:
		await super._prefetch_resources(builder,generation,camera_state)
		return
	if builder._overview or builder.backdrop_pending: return
	var attempted := 0
	for item in _prefetch_tiles:
		var tid := str(item.tile)
		if _prefetch_checked.has(tid) or builder.local_tiles.has(tid): continue
		if not builder.resource_cache.can_prefetch(): break
		_prefetch_checked[tid] = true
		# Work on private containers so rejected speculative upgrades cannot
		# silently change the cache's retained-byte accounting.
		var key: String = builder.terrain_key(tid)
		var retained: Dictionary = builder.resource_cache.restore(tid)
		if not retained.is_empty(): builder.terrain_cache[key] = retained.data.duplicate(true)
		var prepared: bool = await ProgressiveTile.prepare(self,builder,tid,maxi(1,_detail),generation)
		if prepared:
			var data: Dictionary = builder.terrain_cache.get(key,{})
			var chunk: Dictionary = builder._chunk_data.get(tid,{})
			var cost := Builder.TileCache.estimate(data,chunk)
			if builder.resource_cache.can_prefetch(maxi(0,cost-int(retained.get("bytes",0)))):
				builder.resource_cache.put(tid,data,chunk,Time.get_ticks_msec())
		builder.terrain_cache.erase(key);builder._chunk_data.erase(tid)
		builder.tile_load_resources.clear()
		attempted += 1
		await get_tree().process_frame
		if generation != _generation or camera_state != capture_camera() or attempted >= 2: break


func _stream_visible() -> void:
	if _builder == null or not _builder.streamed or _streaming or _building: return
	if _builder.handover.active: return
	var camera_state := capture_camera()
	var far_expired: bool = _builder._overview and _far_detail_expires_msec > 0 and Time.get_ticks_msec() >= _far_detail_expires_msec
	var changed := _stream_generation != _generation or _stream_camera != camera_state or _stream_tier != _detail
	_streaming = true
	var generation := _generation
	var builder: RefCounted = _builder
	if not changed and not far_expired:
		_maintain_resource_cache()
		await _prefetch_resources(builder, generation, camera_state)
		_streaming = false
		return
	_prefetch_checked.clear()
	var wanted := _wanted_detail_tiles()
	var keep := {}
	for item in wanted: keep[item.tile] = true
	var hold_far_detail: bool = builder._overview and Time.get_ticks_msec() < _far_detail_expires_msec
	if hold_far_detail:
		for tid in builder.local_tiles: keep[tid] = true
	if not builder._overview:
		# Start the existing unused-resource grace period at departure, even if
		# the previous streaming pass took longer than the normal idle tick.
		var now := Time.get_ticks_msec()
		for tid in builder.local_tiles: builder.resource_cache.touch(tid, now)
	builder.release_local_tiles(keep, true)
	if far_expired: _far_detail_expires_msec = 0
	var fine := _fine_detail_plan(wanted)
	if not hold_far_detail: builder.release_detail(fine, true)
	var terrain_by_tile := {}
	for item in builder.terrain_lods: terrain_by_tile[item.tile] = item
	var slice_start := Time.get_ticks_usec()
	var completed := true
	var read_ahead := ReadAhead.new()
	var request_index := 0
	for request in wanted:
		var tile_started := Time.get_ticks_usec()
		var tile_timings := {}
		var tid := str(request.tile)
		var tier := int(fine.get(tid, 0))
		if builder.backdrop_pending: tier = maxi(1,tier)
		if trial_queue:
			read_ahead.enqueue(builder,wanted,fine,request_index)
			await read_ahead.ready_current(get_tree(),builder,tid)
		request_index += 1
		if not builder.local_tiles.has(tid) or (tier>0 and terrain_by_tile[tid].data.meshes[tier]==null):
			if not await ProgressiveTile.prepare(self,builder,tid,tier,generation):
				completed = false
				break
			if generation != _generation: break
		if trial_queue: read_ahead.release_current(builder,tid)
		tile_timings.prepare_ms = (Time.get_ticks_usec()-tile_started)/1000.0
		var node_started := Time.get_ticks_usec()
		if not builder.local_tiles.has(tid):
			if not await _build_local_tile(builder,_content,_model,tid,generation):
				completed = false
				break
			terrain_by_tile[tid] = builder.terrain_lods[-1]
		if tier>0: await builder.refine_tile(self,terrain_by_tile[tid],tier)
		else: builder.apply_tile_detail(terrain_by_tile[tid],0)
		if generation != _generation: break
		tile_timings.node_ms = (Time.get_ticks_usec()-node_started)/1000.0
		var reveal_started := Time.get_ticks_usec()
		if not builder.ready_tiles.has(tid):
			if builder.loading_reveal != null:
				builder.loading_reveal.bind(builder.local_tiles[tid].root)
				if request.visible: _start_tile_reveal(builder,tid)
				else: builder.loading_reveal.skip(tid)
			builder.reveal_tile(tid)
			if _reveal_started>0:
				reveal_profile.tiles.append({"tile":tid,"ring":request.ring,"visible":request.visible,
					"ms":Time.get_ticks_msec()-_reveal_started,"before_far":builder.backdrop_pending,"stages":tile_timings})
			_sync_paper()
		else: builder._apply_view_visibility()
		tile_timings.reveal_ms = (Time.get_ticks_usec()-reveal_started)/1000.0
		builder.cache_local_tile(tid)
		builder.tile_load_resources.clear()
		# A complete tile is published before yielding; the next frame can display
		# it while the next tile's resources load. Never wait for a whole layer.
		if Time.get_ticks_usec()-slice_start >= SCENE_BUDGET_USEC:
			await get_tree().process_frame
			slice_start = Time.get_ticks_usec()
		if camera_state != capture_camera() or generation != _generation: break
	if trial_queue:
		await read_ahead.finish(get_tree())
		queue_reports.append({"requests":read_ahead.requested,"peak_requests":read_ahead.peak_requests,"peak_disk_bytes":read_ahead.peak_disk_bytes,"errors":read_ahead.errors})
	builder.road_surface.finish_build()
	builder._road_height_cache.clear()
	if completed and generation == _generation and camera_state == capture_camera():
		for tid in builder.local_tiles: builder.cache_local_tile(str(tid))
		_stream_camera = camera_state
		_stream_generation = generation
		_stream_tier = _detail
		_maintain_resource_cache()
		builder.complete_detail_request()
		if not background_active() and _coverage_states.has(true): _coverage_states[true].get("resources", {}).clear()
	_streaming = false
