extends "res://tools/supply_chain_3d/check_background_loading.gd"
## Real rendered first-open check: request the continent before background readiness.
func _continent_review(board: Control, _home: Dictionary) -> void:
	var output := "res://../outputs/supply-chain-3d/progressive-loading"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--review-output="): output = arg.trim_prefix("--review-output=")
	DirAccess.make_dir_recursive_absolute(output)
	var started := Time.get_ticks_msec()
	var owned_builder: RefCounted = board._builder
	await board.set_all_tiles(true, false)
	var result := {"opening":opening,"request_ms":Time.get_ticks_msec()-started}
	assert(is_instance_valid(board._paper) and board._paper.visible, "An early request must immediately show paper")
	RenderingServer.force_draw(false)
	board._viewport.get_texture().get_image().save_png(output.path_join("01-paper.png"))
	var frames: Array[float] = []
	var slow := []
	var previous := Time.get_ticks_usec()
	var first := false
	var panned := false
	var after_pan := 0
	var pan_start := 0
	var pan_camera := {}
	while true:
		var stage: String = board._warming.stage if board._warming != null else "none"
		RenderingServer.force_draw(false)
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frames.append((now-previous)/1000.0); previous = now
		if frames[-1]>50: slow.append({"ms":frames[-1],"stage":stage,"tiles":board.reveal_profile.tiles.size()})
		if not first and not board.reveal_profile.tiles.is_empty():
			first = true
			result.first_tile = board.reveal_profile.tiles[0]
			board._viewport.get_texture().get_image().save_png(output.path_join("02-first-tile.png"))
			previous = Time.get_ticks_usec() # PNG readback/encoding is instrumentation, not a gameplay frame.
		if first and not panned and board.reveal_profile.tiles.size()>=3:
			board._viewport.get_texture().get_image().save_png(output.path_join("03-expanding.png"))
			pan_camera = board.capture_camera()
			pan_camera.target += Vector3(810,0,480)
			after_pan = board.reveal_profile.tiles.size()
			pan_start = Time.get_ticks_msec()
			board.restore_camera(pan_camera)
			panned = true
			previous = Time.get_ticks_usec()
		if panned and board.reveal_profile.tiles.size()>after_pan and not result.has("pan_first_tile_ms"):
			result.pan_first_tile_ms = Time.get_ticks_msec()-pan_start
			result.pan_next_tiles = board.reveal_profile.tiles.slice(after_pan)
		if panned and not board.background_active() and board.detail_ready() and board._stream_camera == board.capture_camera(): break
		assert(Time.get_ticks_msec()-started<90000,"Progressive reveal timed out")
	result.settled_ms = Time.get_ticks_msec()-started
	result.background = board.background_profile.duplicate(true)
	result.reveal = board.reveal_profile.duplicate(true)
	result.slow_frames = slow
	frames.sort()
	result.p95_frame_ms = frames[int((frames.size()-1)*.95)]
	result.max_frame_ms = frames[-1]
	result.frames = frames.size()
	var builder: RefCounted = board._builder
	result.cache = {"bundled_hits":builder.bake_cache.bundled_hits,"misses":builder.bake_cache.misses,"writes":builder.bake_cache.writes}
	assert(builder.bake_cache.misses==0 and builder.bake_cache.writes==0,"Progressive loading must reuse installed artwork")
	var picks := 0
	var pick_errors := []
	var occluded := 0
	await get_tree().physics_frame
	for tid in builder.ready_tiles:
		var at: Vector3 = builder.point(builder.tiles[tid].center)
		var screen: Vector2 = board.screen_point(at)
		if not Rect2(Vector2.ZERO,board.size).has_point(screen): continue
		var hit: Dictionary = board.pick_at(screen,true)
		var actual := str(hit.get("tile_id",hit.get("collider").get_meta("tile_id","") if hit.has("collider") else ""))
		if actual!=tid and not hit.is_empty() and hit.position.y>at.y+2.0:
			occluded += 1 # The higher foreground tile correctly occludes this centre.
		elif actual!=tid:
			pick_errors.append({"tile":tid,"actual":actual,"screen":screen,"world":at,"hit":str(hit),
				"coarse":str(board._cursor_surface_hit(screen)),"camera":board.capture_camera()})
		picks += 1
	result.verified_tile_picks = picks
	result.pick_errors = pick_errors
	result.occluded_centres = occluded
	RenderingServer.force_draw(false)
	board._viewport.get_texture().get_image().save_png(output.path_join("04-ready.png"))
	var switch_start := Time.get_ticks_msec()
	await board.set_all_tiles(false,false)
	result.return_owned_ms = Time.get_ticks_msec()-switch_start
	assert(board._builder==owned_builder,"Owned coverage must remain cached")
	switch_start = Time.get_ticks_msec()
	await board.set_all_tiles(true,false)
	board.restore_camera(pan_camera)
	await _settle(board)
	result.repeat_switch_ms = Time.get_ticks_msec()-switch_start
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("[PROGRESSIVE CHECK] ",JSON.stringify(result))
	assert(pick_errors.is_empty(), "Prepared locator must preserve visible tile selection")
