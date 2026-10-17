extends "res://tools/supply_chain_3d/check_background_loading.gd"
const TrialBoard = preload("res://tools/supply_chain_3d/trials/stream_board.gd")
var output := ""
var records := []
var frames := []
var sampling := false
var previous := 0
var peak_memory := 0.0
var errors := []

func _ready() -> void:
	get_tree().node_added.connect(_install_trial)
	await super._ready()

func _install_trial(node:Node) -> void:
	# Install before _ready and before any background coroutine starts.
	if node.name == "Board" and node.get_script() != null and node.get_script().resource_path == "res://scripts/supply_chain_3d/board.gd":
		node.set_script(TrialBoard)


func _frame() -> void:
	if not sampling: return
	var now := Time.get_ticks_usec()
	frames.append((now-previous)/1000.0); previous=now
	peak_memory=maxf(peak_memory,Performance.get_monitor(Performance.MEMORY_STATIC))

func _stats() -> Dictionary:
	var sorted := frames.duplicate(); sorted.sort()
	return {"frames":sorted.size(),"p95_ms":sorted[int((sorted.size()-1)*.95)] if not sorted.is_empty() else 0,
		"max_ms":sorted[-1] if not sorted.is_empty() else 0,"over_50ms":sorted.filter(func(x):return x>50).size(),
		"peak_static_MiB":peak_memory/1048576.0}

func _sample() -> void:
	frames.clear();previous=Time.get_ticks_usec();peak_memory=0;sampling=true

func _save(board:Control) -> void:
	var result := {"queue_version":board.ReadAhead.VERSION,"visibility":board.trial_visibility,"queue":board.trial_queue,"rear":board.trial_rear,"opening":opening,
		"records":records,"errors":errors,"queue_reports":board.queue_reports,
		"cache":{"hits":board._builder.bake_cache.bundled_hits,"misses":board._builder.bake_cache.misses,"writes":board._builder.bake_cache.writes}}
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))

func _settled(board:Control) -> bool:
	return not board.background_active() and board.detail_ready() and board._stream_camera==board.capture_camera()

func _continent_review(board:Control, home:Dictionary) -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--trial-output="):output=arg.trim_prefix("--trial-output=")
	assert(not output.is_empty())
	DirAccess.make_dir_recursive_absolute(output)
	get_tree().process_frame.connect(_frame)
	_sample()
	var started := Time.get_ticks_msec()
	await board.set_all_tiles(true,false)
	var first_complete := -1
	var debug_at := 0
	while not _settled(board):
		RenderingServer.force_draw(false);await get_tree().process_frame
		if Time.get_ticks_msec()-debug_at>5000:
			debug_at=Time.get_ticks_msec()
			print("[STREAM WAIT] ", {"process":board.is_processing(),"background":board.background_active(),"streaming":board._streaming,"ready":board.detail_ready(),"camera":board._stream_camera==board.capture_camera(),"tiles":board._builder.local_tiles.size(),"overview":board._builder._overview,"detail":board._detail})
		if first_complete<0 and board._builder.loading_reveal!=null and not board._builder.loading_reveal.timeline.is_empty():first_complete=Time.get_ticks_msec()-started
		if Time.get_ticks_msec()-started>90000:errors.append("First opening timeout");_save(board);get_tree().quit(1);return
	sampling=false
	var initial := _stats();initial.merge({"view":"first_open","load_ms":Time.get_ticks_msec()-started,"first_complete_ms":first_complete,
		"active_tiles":board._builder.local_tiles.size(),"tile_cache_MiB":board._builder.resource_cache.bytes/1048576.0})
	records.append(initial);print("[STREAM TRIAL] ",JSON.stringify(initial));_save(board)
	board.set_process(false);board._labels.hide();board.animate_goods=false
	var builder:RefCounted=board._builder
	var camera:Dictionary=board.capture_camera()
	camera.target=builder.point(builder.tiles.tile_10_10.center)
	camera.span=board.Rig.MIN_SIZE;camera.pitch=board.Rig.HOME_PITCH;camera.yaw=board.Rig.HOME_YAW
	await _view_trial(board,camera,"closest_first")
	camera.target=builder.point(builder.tiles.tile_11_10.center)
	await _view_trial(board,camera,"closest_adjacent")
	camera.target=builder.point(builder.tiles.tile_10_10.center)
	await _view_trial(board,camera,"closest_return")
	camera.span=board.size.y;camera.pitch=.30
	await _view_trial(board,camera,"medium_shallow")
	camera.target=builder.point(builder.tiles.tile_11_10.center)
	await _view_trial(board,camera,"medium_adjacent")
	camera.yaw+=PI*.5
	await _view_trial(board,camera,"shallow_quarter_turn")
	camera.target=builder.point(builder.tiles.tile_11_5.center)
	await _view_trial(board,camera,"mountains_jump")
	camera.yaw+=PI
	await _view_trial(board,camera,"mountains_reverse")
	# Move again while preparation is in flight, without waiting for the first
	# view to settle. Already issued native requests must be drained safely.
	camera.target=builder.point(builder.tiles.tile_15_16.center)
	board.restore_camera(camera);board._stream_visible()
	await get_tree().process_frame
	camera.target=builder.point(builder.tiles.tile_4_9.center);camera.yaw+=PI*.5
	await _view_trial(board,camera,"interrupted_jump")
	if "--trial-extra-edges" in OS.get_cmdline_user_args():
		var tallest := {}
		for standing in board._model.standing:
			var frame:Dictionary=builder.standing_frame(standing)
			if tallest.is_empty() or frame.dimension.y>tallest.frame.dimension.y:tallest={"standing":standing,"frame":frame}
		var roof:Vector3=tallest.frame.position+Vector3.UP*float(tallest.frame.dimension.y)
		camera.span=board.size.y/1.2;camera.pitch=.30
		camera.target=roof-Vector3(sin(camera.yaw),0,cos(camera.yaw))*(camera.span*.5-4.0/1.2)/sin(camera.pitch)
		await _view_trial(board,camera,"tower_at_bottom_edge")
		if not builder.local_tiles.has(tallest.standing.tile):errors.append("Visible tower omitted at viewport edge")
		var peak:=Vector3.ZERO;var height:=-INF
		for tile in builder.tiles.values():
			for x in range(-180,181,90):
				for z in range(-180,181,90):
					var at:Vector3=builder.point(tile.center+Vector2(x,z))
					if at.y>height:height=at.y;peak=at
		camera.target=peak-Vector3(sin(camera.yaw),0,cos(camera.yaw))*(camera.span*.5-4.0/1.2)/sin(camera.pitch)
		await _view_trial(board,camera,"summit_at_bottom_edge")
		if not builder.local_tiles.has(builder.tile_at(peak)):errors.append("Visible summit omitted at viewport edge")
	if builder.bake_cache.misses!=0 or builder.bake_cache.writes!=0:errors.append("Unexpected runtime bake generation")
	for report in board.queue_reports:
		if not report.errors.is_empty():errors.append("Read-ahead request failed")
	_save(board)
	if not errors.is_empty():push_error(JSON.stringify(errors));get_tree().quit(1)

func _view_trial(board:Control,camera:Dictionary,name:String) -> void:
	var builder:RefCounted=board._builder
	var retained := {}
	for tid in builder.resource_cache.entries:retained[tid]=builder.resource_cache.entries[tid].last_used
	_sample();var start:=Time.get_ticks_msec()
	board.restore_camera(camera)
	while board._streaming:RenderingServer.force_draw(false);await get_tree().process_frame
	await board._stream_visible()
	while not board.detail_ready():RenderingServer.force_draw(false);await get_tree().process_frame
	board._update_cursor_collision(board.size*.5)
	sampling=false
	var record:=_stats()
	var wanted:Array=board._wanted_detail_tiles();var plan:Dictionary=board._fine_detail_plan(wanted)
	var missing:=[]
	for item in wanted:
		if item.visible and not builder.local_tiles.has(item.tile):missing.append(item.tile+":scene")
	for item in builder.terrain_lods:
		if plan.has(item.tile) and item.node.mesh!=item.data.meshes[plan[item.tile]]:missing.append(item.tile+":terrain")
	for tid in retained:
		if Time.get_ticks_msec()-int(retained[tid])<10000 and not builder.resource_cache.entries.has(tid):missing.append(tid+":retention")
	if not missing.is_empty():errors.append({"view":name,"missing":missing})
	record.merge({"view":name,"load_ms":Time.get_ticks_msec()-start,"active_tiles":builder.local_tiles.size(),
		"visible_tiles":wanted.filter(func(x):return x.visible).size(),"fine_tiles":plan.size(),"missing":missing,
		"tile_cache_MiB":builder.resource_cache.bytes/1048576.0,
		"collision_tiles":builder.collision_tiles.keys(),"prefetch_candidates":board._prefetch_tiles.size(),"demoted_tiles":board.demoted_tiles.duplicate()})
	await get_tree().physics_frame
	var hit:Dictionary=board.pick_at(board.size*.5,true)
	record.centre_pick=str(hit.get("tile_id",hit.get("collider").get_meta("tile_id","") if hit.has("collider") else ""))
	if board.trial_queue and not board.queue_reports.is_empty():
		record.read_ahead_requests = board.queue_reports[-1].requests
		if name == "closest_return" and record.read_ahead_requests != 0: errors.append("Read-ahead reread retained terrain")
	records.append(record);print("[STREAM TRIAL] ",JSON.stringify(record));_save(board)
	# Readback/PNG encoding is outside the measured interval.
	for i in 3:RenderingServer.force_draw(false);await get_tree().process_frame
	board._viewport.get_texture().get_image().save_png(output.path_join(name+".png"))
	if "--trial-idle-prefetch" in OS.get_cmdline_user_args() and name in ["closest_first","medium_shallow"]:
		_sample();var prefetch_start := Time.get_ticks_msec()
		await board._prefetch_resources(builder,board._generation,board.capture_camera())
		sampling=false
		var prefetched := _stats();prefetched.merge({"view":name+"_idle_prefetch","load_ms":Time.get_ticks_msec()-prefetch_start,
			"tile_cache_MiB":builder.resource_cache.bytes/1048576.0,"active_tiles":builder.local_tiles.size()})
		records.append(prefetched);_save(board)
