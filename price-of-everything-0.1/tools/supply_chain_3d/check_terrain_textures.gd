extends "res://tools/supply_chain_3d/check_background_loading.gd"
## Fixed-camera comparisons of protected urban, rural, hill and mountain tiles.
func _continent_review(board: Control, home: Dictionary) -> void:
	var output := "res://../outputs/supply-chain-3d/terrain-textures/visual"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--review-output="):output=arg.trim_prefix("--review-output=")
	DirAccess.make_dir_recursive_absolute(output)
	while board.background_active():
		RenderingServer.force_draw(false); await get_tree().process_frame
	assert(board.background_ready())
	await board.set_all_tiles(true,false)
	await _settle(board)
	board.set_process(false); board._labels.hide(); board.animate_goods=false
	var report := {"views":[]}
	for entry in [["urban","tile_4_9"],["rural","tile_10_10"],["hill","tile_11_6"],["mountain","tile_11_5"],["lake","tile_12_5"],["coast","tile_15_16"]]:
		for span in [1000.0,240.0]:
			var state := home.duplicate()
			state.target=board._builder.point(board._model.tiles[entry[1]].center)
			state.span=span;state.pitch=1.05;state.yaw=0.1
			board.restore_camera(state)
			var started := Time.get_ticks_msec()
			await _settle(board)
			var elapsed := Time.get_ticks_msec()-started
			for i in 10: RenderingServer.force_draw(false); await get_tree().process_frame
			var name: String=entry[0]+("-medium" if span==1000.0 else "-closest")
			board._viewport.get_texture().get_image().save_png(output.path_join(name+".png"))
			var texture: Texture2D=board._builder.terrain_cache[board._builder.terrain_key(entry[1])].textures[1 if span==1000.0 else 2]
			report.views.append({"name":name,"tile":entry[1],"camera":board.capture_camera(),"settle_ms":elapsed,
				"format":texture.get_format(),"size":Vector2i(texture.get_width(),texture.get_height()),"retained_bytes":board._builder.resource_cache.bytes})
	for span in [6000.0,12000.0]:
		var state := home.duplicate()
		state.target=board._builder.point(board._model.tiles.tile_4_9.center)
		state.span=span;state.pitch=1.05;state.yaw=0.1
		board.restore_camera(state)
		await _settle(board)
		for i in 10: RenderingServer.force_draw(false); await get_tree().process_frame
		board._viewport.get_texture().get_image().save_png(output.path_join("continent.png" if span==6000.0 else "whole-continent.png"))
	var cache: RefCounted=board._builder.bake_cache
	report.cache={"hits":cache.bundled_hits,"misses":cache.misses,"writes":cache.writes}
	report.far_format=board._builder.continent.texture.get_format()
	assert(cache.misses==0 and cache.writes==0)
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("[TERRAIN VISUAL CHECK] ",JSON.stringify(report))
