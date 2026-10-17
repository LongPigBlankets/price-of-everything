extends "res://tools/supply_chain_3d/capture.gd"
## Identical camera recipe for archived and current supply-chain renderers.
## Does not depend on authored-road/harbour/civic code, so it runs before them.
func _ready() -> void:
	PlayerProfile.supply_chain_all_tiles = false
	await super._ready()

func _continent_review(board: Control, home: Dictionary) -> void:
	var output := "res://../outputs/supply-chain-3d/stoneshore-comparison/after"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--comparison-output="): output = arg.trim_prefix("--comparison-output=")
	DirAccess.make_dir_recursive_absolute(output)
	await board.set_all_tiles(true, false)
	await board._stream_visible()
	while not board.detail_ready():
		RenderingServer.force_draw(false)
		await get_tree().process_frame
	board.set_process(false)
	board._labels.hide()
	board.animate_goods = false
	var center := Vector2.ZERO
	for tid in ["tile_4_9", "tile_4_10", "tile_5_9", "tile_5_10", "tile_6_9"]:
		center += board._model.tiles[tid].center
	center /= 5.0
	var views := [
		{"name": "region", "point": center, "span": 1450.0, "pitch": 1.05, "yaw": 0.0},
		{"name": "town", "point": board._model.tiles.tile_4_9.center, "span": 600.0, "pitch": 0.95, "yaw": 0.0},
		{"name": "old-quarter", "point": board._model.tiles.tile_4_10.center, "span": 480.0, "pitch": 1.05, "yaw": 0.35},
		{"name": "harbour", "point": Vector2(2640, 5840), "span": 650.0, "pitch": 0.95, "yaw": 0.35}]
	var report := {"engine": Engine.get_version_info().string, "views": []}
	if "--coastal-road-review" in OS.get_cmdline_user_args():
		var trial: GDScript = load("res://tools/supply_chain_3d/coastal_road_trial.gd")
		report.authored_trees = trial.tree_metrics
		report.lanes = {}
		for road_class in ["minor", "mid", "major"]:
			var level: int = {"minor": 1, "mid": 2, "major": 3}[road_class]
			var widths: Array = trial.widths(road_class)
			report.lanes[road_class] = {"lanes": trial.lanes(level), "widths": widths, "markings": trial.lane_lines(level, widths[3])}
	if "--density-review" in OS.get_cmdline_user_args():
		report.stats = {}
		for tid in ["tile_4_9", "tile_4_10", "tile_5_10"]:
			var stats := {"houses": 0, "offices": 0, "parks": 0, "infill": 0, "trees": 0, "road_length": 0.0, "standing": []}
			for s in board._model.standing:
				if str(s.tile) != tid: continue
				stats.standing.append({"iid": s.iid, "kind": s.kind, "pos": s.pos, "side": s.side, "footprint": s.get("footprint", []),
					"asset": board._builder.standing_key(s), "tall": s.get("tall", false), "decor_family": s.get("decor_family", "")})
				if s.kind != "house": continue
				if s.get("decor_family", "") in ["civic_park", "civic_plaza"]: stats.parks += 1
				elif s.has("decor_family"): stats.offices += 1
				else: stats.houses += 1
				if s.get("infill", false): stats.infill += 1
			for road in board._model.roads:
				if str(road.tile) == tid: stats.road_length += road.a.distance_to(road.b)
			stats.trees = board._builder.tree_placements.get(tid, []).size()
			report.stats[tid] = stats
		var ground: RefCounted = board._builder.ground
		if "historical" in ground:
			var current := preload("res://scripts/empire_board_ground.gd").new()
			for property in ["tiles", "bands", "lakes", "rivers", "flows", "level_at", "relief", "may_be_wet"]:
				current.set(property, ground.get(property))
			current.setup()
			report.coastal_samples = []
			for y in range(5400, 5970, 12):
				for x in range(2000, 2900, 12):
					var p := Vector2(x,y)
					var old: float = ground.historical.height(p)
					var now: float = current.height(p)
					if old < 25.5 and now > 33.5 and report.coastal_samples.size() < 12:
						report.coastal_samples.append({"point": p, "historical": old, "current": now, "trial": ground.height(p)})
	for view in views:
		var state := home.duplicate()
		state.target = board._builder.point(view.point)
		state.span = view.span
		state.pitch = view.pitch
		state.yaw = view.yaw
		board.restore_camera(state)
		await board._stream_visible()
		while not board.detail_ready():
			RenderingServer.force_draw(false)
			await get_tree().process_frame
		for i in 8:
			RenderingServer.force_draw(false)
			await get_tree().process_frame
		board._viewport.get_texture().get_image().save_png(output.path_join(view.name + ".png"))
		report.views.append({"name": view.name, "camera": board.capture_camera()})
		print("[STONESHORE COMPARISON] ", view.name)
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
