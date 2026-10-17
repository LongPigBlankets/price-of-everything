extends "res://tools/supply_chain_3d/check_background_loading.gd"
## Exercise the ordinary all-tiles reader without a prepared background world.
## Run rendered with --continent-review --no-background-continent.
func _ready() -> void:
	if not "--no-background-continent" in OS.get_cmdline_user_args():
		push_error("This check requires --no-background-continent")
		get_tree().quit(1)
		return
	await super._ready()

func _continent_review(board: Control, _home: Dictionary) -> void:
	assert(not board.background_active() and not board.background_ready())
	var output := "res://../outputs/supply-chain-3d/unified-bake-values/ordinary"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--review-output="): output=arg.trim_prefix("--review-output=")
	DirAccess.make_dir_recursive_absolute(output)
	var started := Time.get_ticks_msec()
	await board.set_all_tiles(true,false)
	await _settle(board)
	var cache: RefCounted = board._builder.bake_cache
	var result := {"opening":opening,"switch_ms":Time.get_ticks_msec()-started,
		"tiles":board._model.tiles.size(),"profile":board.load_profile,
		"cache":{"bundled_hits":cache.bundled_hits,"misses":cache.misses,"writes":cache.writes}}
	assert(board.show_all_tiles and result.tiles==600,"Ordinary loading must restore the complete continent")
	assert(cache.bundled_hits>0 and cache.misses==0 and cache.writes==0,"Canonical bakes must load without regeneration")
	RenderingServer.force_draw(false)
	board._viewport.get_texture().get_image().save_png(output.path_join("continent-ready.png"))
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t")+"\n")
	print("[CANONICAL LOAD CHECK] ",JSON.stringify(result))
