extends "res://tools/supply_chain_3d/check_background_loading.gd"
## Matching cameras and production loading path for the compact-render comparison.
func _continent_review(board: Control, home: Dictionary) -> void:
	var output := "res://../outputs/supply-chain-3d/surface-compaction/before"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--review-output="):output=arg.trim_prefix("--review-output=")
	DirAccess.make_dir_recursive_absolute(output)
	while board.background_active():
		RenderingServer.force_draw(false); await get_tree().process_frame
	assert(board.background_ready(),"Comparison requires a valid prepared continent")
	var started := Time.get_ticks_msec()
	await board.set_all_tiles(true,false)
	await _settle(board)
	var report := {"opening":opening,"prepared_switch_ms":Time.get_ticks_msec()-started,"views":[]}
	board.set_process(false); board._labels.hide(); board.animate_goods=false
	var views := [["far",2400.0,0.1],["medium",1000.0,0.1],["near",500.0,0.1],["near-rotated",500.0,1.0],["closest",240.0,0.1]]
	if "--overview-only" in OS.get_cmdline_user_args():views=[["continent",6000.0,0.1],["whole-continent",12000.0,0.1]]
	for view in views:
		var state := home.duplicate()
		state.target=board._builder.point(board._model.tiles.tile_4_9.center)
		state.span=view[1]; state.pitch=1.05; state.yaw=view[2]
		board.restore_camera(state)
		var stage := Time.get_ticks_msec()
		await _settle(board)
		for i in 10: RenderingServer.force_draw(false); await get_tree().process_frame
		board._viewport.get_texture().get_image().save_png(output.path_join(view[0]+".png"))
		report.views.append({"name":view[0],"camera":board.capture_camera(),"settle_ms":Time.get_ticks_msec()-stage,"ppu":board.size.y/board._rig.span,"overview":board._builder._overview,"active_lod":board._builder.active_lod})
	var cache: RefCounted=board._builder.bake_cache
	report.cache={"hits":cache.bundled_hits,"misses":cache.misses,"writes":cache.writes}
	assert(cache.misses==0 and cache.writes==0,"Visual comparison must use installed bakes")
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("[SURFACE COMPARISON] ",JSON.stringify(report))
