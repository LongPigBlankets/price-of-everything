extends "res://tools/supply_chain_3d/capture.gd"
## Render the real game's pylons from both sides, including the medium impostors.
var output := "res://../outputs/supply-chain-3d/pylons/"

func _ready() -> void:
	PlayerProfile.supply_chain_all_tiles = false
	await super._ready()

func _continent_review(board: Control, home: Dictionary) -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pylon-output="): output = arg.trim_prefix("--pylon-output=")
	DirAccess.make_dir_recursive_absolute(output)
	board.set_process(false)
	board._labels.hide()
	board.animate_goods = false
	var pylons: Array = board._model.standing.filter(func(s: Dictionary) -> bool: return s.kind == "pylon")
	assert(not pylons.is_empty())
	var pylon: Dictionary = pylons[0]
	var frame: Dictionary = board._builder.standing_frame(pylon)
	if "--all-tiles" in OS.get_cmdline_user_args():
		await board.set_all_tiles(true, false)
		await board._stream_visible()
		while not board.detail_ready():
			RenderingServer.force_draw(false)
			await get_tree().process_frame
	var state := home.duplicate()
	state.target = frame.position + Vector3.UP * float(frame.dimension.y) * 0.5
	state.pitch = 0.45
	var record := {"pylon": pylon.iid, "frame": frame, "load": board.load_profile.duplicate(), "views": [],
		"lines": board._model.lines.filter(func(s: Dictionary) -> bool: return s.mode == "cables")}
	for tier in ["near", "medium", "far"]:
		state.span = {"near": 240.0, "medium": board.size.y / 1.2, "far": board.size.y / 0.22}[tier]
		for angle in [0, 45, 90, 135, 180, 225]:
			state.yaw = deg_to_rad(angle)
			board.restore_camera(state)
			await board._stream_visible()
			while not board.detail_ready():
				RenderingServer.force_draw(false)
				await get_tree().process_frame
			for i in 3:
				RenderingServer.force_draw(false)
				await get_tree().process_frame
			board._viewport.get_texture().get_image().save_png(output.path_join("%s-%03d.png" % [tier, angle]))
			record.views.append({"tier": tier, "angle": angle, "actual_lod": board._detail,
				"far_sprites": board._builder._sprites_visible})
			assert(board._detail == {"far": 0, "medium": 1, "near": 2}[tier])
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(record, "\t"))
	if "--analyse-roads" in OS.get_cmdline_user_args():
		var roads: Dictionary = preload("res://tools/supply_chain_3d/analyse_roads.gd").inspect(get_tree().current_scene)
		FileAccess.open(output.path_join("roads-analysis.json"), FileAccess.WRITE).store_string(JSON.stringify(roads, "\t"))
		print("[ROAD ANALYSIS] ", roads.visible_polylines, " polylines, ", roads.near_endpoints_within_2u, " candidate joins")
	print("[PYLON REVIEW] ", output)
