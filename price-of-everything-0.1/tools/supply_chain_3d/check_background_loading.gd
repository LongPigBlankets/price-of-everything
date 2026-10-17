extends "res://tools/supply_chain_3d/capture.gd"
const Snapshot := preload("res://scripts/supply_chain_3d/world_snapshot.gd")
var opening := {}

func _ready() -> void:
	PlayerProfile.supply_chain_all_tiles = true # prove old saved choice is ignored
	await super._ready()

func _open_supply_view(view: Control) -> void:
	opening.begin_elapsed_ms = Time.get_ticks_msec()
	var start := Time.get_ticks_msec()
	await super._open_supply_view(view)
	var board: Control = view.find_child("Board",true,false)
	opening.ready_ms = Time.get_ticks_msec() - start
	opening.owned_tiles = board._model.tiles.size()
	opening.profile = board.load_profile.duplicate(true)
	assert(not board.show_all_tiles, "Each game must open on the owned view")

func _settle(board: Control) -> void:
	await board._stream_visible()
	while not board.detail_ready():
		RenderingServer.force_draw(false)
		await get_tree().process_frame

func _continent_review(board: Control, home: Dictionary) -> void:
	var output := "res://../outputs/supply-chain-3d/background-loading"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--review-output="): output = arg.trim_prefix("--review-output=")
	DirAccess.make_dir_recursive_absolute(output)
	var frames: Array[float] = []
	var slow_frames := []
	var frame_start := Time.get_ticks_usec()
	var owned_builder: RefCounted = board._builder
	var waited := Time.get_ticks_msec()
	while board.background_active():
		var previous_stage := str(board._warming.stage)
		var camera: Dictionary = board.capture_camera()
		camera.target += Vector3(0.3,0,0.1)
		board.restore_camera(camera)
		RenderingServer.force_draw(false)
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frames.append((now-frame_start)/1000.0);frame_start=now
		if frames[-1] > 50.0: slow_frames.append({"ms":frames[-1], "from":previous_stage, "to":board._warming.stage})
		assert(board._builder == owned_builder and not board._building, "Preparation must not replace or block the owned world")
		assert(Time.get_ticks_msec()-waited < 120000, "Background preparation timed out")
	board.restore_camera(home)
	RenderingServer.force_draw(false)
	board._viewport.get_texture().get_image().save_png(output.path_join("owned-ready.png"))
	var result := {"opening":opening, "background_status":board.background_status,
		"background":board.background_profile, "owned_frames":frames.size(), "slow_frames":slow_frames}
	frames.sort()
	result.max_owned_frame_ms = frames[-1] if not frames.is_empty() else 0
	result.p95_owned_frame_ms = frames[int((frames.size()-1)*.95)] if not frames.is_empty() else 0
	result.frames_over_50ms = frames.filter(func(ms): return ms>50).size()
	if not board.background_ready():
		FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
		push_error("Expected a matching prepared continent: "+JSON.stringify(result));get_tree().quit(1);return
	var switch_start := Time.get_ticks_msec()
	await board.set_all_tiles(true,false)
	await _settle(board)
	result.switch_ms = Time.get_ticks_msec()-switch_start
	result.tiles = board._model.tiles.size()
	var builder: RefCounted = board._builder
	result.cache = {"bundled_hits":builder.bake_cache.bundled_hits,"misses":builder.bake_cache.misses,"writes":builder.bake_cache.writes}
	RenderingServer.force_draw(false)
	board._viewport.get_texture().get_image().save_png(output.path_join("continent-ready.png"))
	switch_start = Time.get_ticks_msec()
	await board.set_all_tiles(false,false)
	result.return_owned_ms = Time.get_ticks_msec()-switch_start
	assert(board._builder==owned_builder,"Returning to owned tiles should retain its prepared world")
	switch_start = Time.get_ticks_msec()
	await board.set_all_tiles(true,false)
	await _settle(board)
	result.repeat_switch_ms = Time.get_ticks_msec()-switch_start
	assert(board._builder==builder,"Repeated coverage switches must reuse the prepared continent")
	assert(builder.bake_cache.misses==0 and builder.bake_cache.writes==0,"Cached background loading must not generate artwork")
	if "--verify-retention" in OS.get_cmdline_user_args():
		await board.set_all_tiles(false,false)
		var grace_start := Time.get_ticks_msec()
		var retained_tiles: int = builder.local_tiles.size()
		assert(retained_tiles > 0, "Inactive detail should survive the immediate return to owned coverage")
		while Time.get_ticks_msec()-grace_start < 10500:
			RenderingServer.force_draw(false)
			await get_tree().process_frame
		assert(builder.local_tiles.is_empty(), "Inactive detail nodes must retire after ten seconds")
		assert(board.background_ready() and board._builder==owned_builder, "Retiring detail must retain both coverage roots")
		switch_start = Time.get_ticks_msec()
		await board.set_all_tiles(true,false)
		await _settle(board)
		result.switch_after_grace_ms = Time.get_ticks_msec()-switch_start
		result.retired_tiles = retained_tiles
		assert(builder.bake_cache.writes==0,"Returning after eviction must reuse the installed package")
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("[BACKGROUND CHECK] ",JSON.stringify(result))
