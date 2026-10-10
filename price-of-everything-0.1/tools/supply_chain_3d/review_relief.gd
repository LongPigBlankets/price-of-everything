extends "res://tools/supply_chain_3d/capture.gd"
## Review continent tree contrast at an identical camera, then raised mountain relief.
## AGENT_GODOT_WINDOW=1 godot --windowed res://tools/supply_chain_3d/review_relief.tscn -- --continent-review --review-tag=relief

func _continent_review(board: Control, home: Dictionary) -> void:
	await super._continent_review(board, home)
	await board.call("set_all_tiles", true, false)
	board.call("fit_view")
	board.set_process(false)
	var builder: RefCounted = board.get("_builder")
	var viewport: SubViewport = board.get("_viewport")
	var sprites := preload("res://scripts/supply_chain_3d/far_sprites.gd")
	var output := ProjectSettings.globalize_path("res://../outputs/supply-chain-3d/continent-relief/")
	DirAccess.make_dir_recursive_absolute(output)
	var state: Dictionary = board.call("capture_camera")
	sprites.set_overview_scale(1.0, true)
	await _save_view(viewport, output + "trees_original_contrast.png")
	sprites.set_overview_scale(board.size.y / float(state.span), true)
	await _save_view(viewport, output + "trees_softened.png")
	# Sample actual source heights, including tile interiors, to find a summit.
	var summit := Vector2.ZERO
	var highest := -INF
	for tile in builder.tiles.values():
		for y in range(-180, 181, 60):
			for x in range(-180, 181, 60):
				var p: Vector2 = tile.center + Vector2(x, y)
				var h: float = builder.ground.height(p)
				if h > highest: highest = h; summit = p
	print("[RELIEF] source summit=", highest, " displayed=", builder.surface_height(summit), " at=", summit)
	state.target = builder.point(summit)
	state.pitch = 0.48
	state.span = 1600.0
	for yaw in [PI / 4.0, PI * 0.75]:
		state.yaw = yaw
		board.call("restore_camera", state)
		await board.call("_ensure_continent_detail")
		builder.set_overview_scale(board.size.y / float(state.span), true)
		await board.call("_stream_visible")
		await _save_view(viewport, output + "mountains_%.2f.png" % yaw)
	board.set_process(true)

func _save_view(viewport: SubViewport, path: String) -> void:
	for i in 4:
		RenderingServer.force_draw(false)
		await get_tree().process_frame
	assert(viewport.get_texture().get_image().save_png(path) == OK)
	print("[RELIEF REVIEW] ", path)
