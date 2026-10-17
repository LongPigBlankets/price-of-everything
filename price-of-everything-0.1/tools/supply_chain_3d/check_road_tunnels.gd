extends "res://tools/supply_chain_3d/check_background_loading.gd"
## Fresh-process release check for short mountain-road cuttings.
func _continent_review(board: Control, home: Dictionary) -> void:
	var output := "res://../outputs/supply-chain-3d/short-road-tunnels/after"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--review-output="):output=arg.trim_prefix("--review-output=")
	DirAccess.make_dir_recursive_absolute(output)
	while board.background_active():
		RenderingServer.force_draw(false); await get_tree().process_frame
	assert(board.background_ready())
	await board.set_all_tiles(true,false)
	await _settle(board)
	board.set_process(false); board._labels.hide(); board.animate_goods=false
	var builder: RefCounted=board._builder
	var alignment=preload("res://scripts/supply_chain_3d/road_alignment.gd")
	var runs: Array=alignment._tunnel_runs(builder.roads)
	var minimum := INF
	for run in runs:
		minimum=minf(minimum,run.length)
		assert(run.length+.001>=alignment.MIN_TUNNEL_LENGTH)
	var spot := Vector2(5168.2,3082.2)
	assert(not builder.road_alignment.portals.any(func(p):return p.p.distance_to(spot)<20.0))
	assert(not builder.road_grade.sample(spot).is_empty())
	var report := {"opening":opening,"minimum_tunnel_length":minimum,"tunnel_runs":runs.size(),"portals":builder.road_alignment.portals.size(),"views":[]}
	for span in [1000.0,560.0,240.0]:
		var state := home.duplicate()
		state.target=builder.point(board._model.tiles.tile_11_5.center)
		state.span=span;state.pitch=1.05;state.yaw=0.1
		board.restore_camera(state)
		await _settle(board)
		for i in 10: RenderingServer.force_draw(false); await get_tree().process_frame
		var name: String="mountain-"+str(int(span))
		board._viewport.get_texture().get_image().save_png(output.path_join(name+".png"))
		report.views.append({"name":name,"camera":board.capture_camera()})
	report.cache={"hits":builder.bake_cache.bundled_hits,"misses":builder.bake_cache.misses,"writes":builder.bake_cache.writes}
	assert(builder.bake_cache.misses==0 and builder.bake_cache.writes==0)
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("[ROAD TUNNEL CHECK] ",JSON.stringify(report))
