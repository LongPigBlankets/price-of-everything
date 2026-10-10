extends "res://tools/supply_chain_3d/capture.gd"
## Fresh-process cache validation plus matched views at the sprite handover.
## AGENT_GODOT_WINDOW=1 godot --windowed res://tools/supply_chain_3d/review_far_decor.tscn -- --continent-review --review-tag=far_decor_final

func _continent_review(board: Control, home: Dictionary) -> void:
	await super._continent_review(board, home)
	await board.call("set_all_tiles", true, false)
	await board.call("_ensure_continent_detail")
	board.set_process(false)
	var builder: RefCounted = board.get("_builder")
	var viewport: SubViewport = board.get("_viewport")
	var output := ProjectSettings.globalize_path("res://../outputs/supply-chain-3d/decor-shadow-cache/")
	DirAccess.make_dir_recursive_absolute(output)
	var state: Dictionary = board.call("capture_camera")
	state.target = home.target
	state.span = 4300.0
	for yaw in [PI / 4.0, PI * 0.75]:
		state.yaw = yaw
		board.call("restore_camera", state)
		for mode in ["sprites", "meshes"]:
			builder.set_overview_scale(0.26 if mode == "sprites" else 1.0, true)
			await _save_view(viewport, output + "handover_%.2f_%s.png" % [yaw, mode])
	for pitch in [0.30, 1.35]:
		state.pitch = pitch
		state.yaw = PI / 4.0
		board.call("restore_camera", state)
		builder.set_overview_scale(0.26, true)
		await _save_view(viewport, output + "far_pitch_%.2f.png" % pitch)
	board.set_process(true)

func _save_view(viewport: SubViewport, path: String) -> void:
	for i in 4:
		RenderingServer.force_draw(false)
		await get_tree().process_frame
	assert(viewport.get_texture().get_image().save_png(path) == OK)
	print("[DECOR REVIEW] ", path)
