extends "res://tools/supply_chain_3d/capture.gd"
const Traffic := preload("res://scripts/supply_chain_3d/harbour_traffic.gd")
var output := "res://../outputs/supply-chain-3d/harbour-traffic"

func _ready() -> void:
	PlayerProfile.supply_chain_all_tiles = false
	await super._ready()

func _continent_review(board: Control, home: Dictionary) -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--traffic-output="): output = arg.trim_prefix("--traffic-output=")
	DirAccess.make_dir_recursive_absolute(output)
	var started := Time.get_ticks_usec()
	await board.set_all_tiles(true, false)
	await board._stream_visible()
	while not board.detail_ready():
		RenderingServer.force_draw(false)
		await get_tree().process_frame
	var ready_ms := (Time.get_ticks_usec() - started) / 1000.0
	board.set_process(false)
	board._labels.hide()
	board.animate_goods = false
	var builder: RefCounted = board._builder
	var setup := Time.get_ticks_usec()
	builder.update_harbour_traffic(0.0)
	var report := {"ready_ms": ready_ms, "load": board.load_profile.duplicate(), "warm_update_ms": (Time.get_ticks_usec() - setup) / 1000.0, "ports": [], "views": []}
	var stoneshore: Dictionary = {}
	for item in builder.harbour_traffic:
		if item.root.name == "inst_b_004_0003ed": stoneshore = item
		if (item.center as Vector2).distance_to(Vector2(2640, 5840)) < 100.0: stoneshore = item
		var records: Array = []
		for index in item.traffic.ships.size():
			var ship: Dictionary = item.traffic.ships[index]
			var route: Dictionary = ship.route
			if not route.mobile: push_error("Harbour ship cannot depart: " + str(item.center)); get_tree().quit(1); return
			for step in int(Traffic.CYCLE) * 2:
				var state := Traffic.sample(route, step * 0.5, index)
				if state.opacity > 0.001 and not Traffic.water_safe(route, state.position, state.heading, item.center, builder.surface_height):
					push_error("Harbour ship crosses land: " + str(item.center)); get_tree().quit(1); return
			records.append({"key": ship.asset.near, "distance": route.distance, "turning": route.turning, "radius": route.radius})
		report.ports.append({"center": item.center, "ships": records})
	assert(not stoneshore.is_empty())
	var state := home.duplicate()
	var port: Vector2 = stoneshore.center
	state.target = builder.point(port + (stoneshore.traffic.ships[0].route.forward as Vector2) * 120.0)
	state.pitch = 1.05
	state.yaw = 0.0
	var snapshots := [
		{"name": "near-berthed", "span": 500.0, "time": 0.0},
		{"name": "near-departing", "span": 500.0, "time": 15.0},
		{"name": "near-empty", "span": 500.0, "time": 42.0},
		{"name": "near-arriving", "span": 500.0, "time": 63.0},
		{"name": "near-docking", "span": 500.0, "time": 76.0},
		{"name": "near-replaced", "span": 500.0, "time": 164.0},
		{"name": "medium-departing", "span": board.size.y / 1.1, "time": 15.0},
		{"name": "far-no-ships", "span": board.size.y / 0.24, "time": 15.0}]
	for view in snapshots:
		state.span = view.span
		board.restore_camera(state)
		await board._stream_visible()
		while not board.detail_ready():
			RenderingServer.force_draw(false)
			await get_tree().process_frame
		for item in builder.harbour_traffic: Traffic.update(item.traffic, view.time, 0 if builder._overview else builder.active_lod)
		for i in 4:
			RenderingServer.force_draw(false)
			await get_tree().process_frame
		board._viewport.get_texture().get_image().save_png(output.path_join(view.name + ".png"))
		report.views.append({"name": view.name, "tier": builder.active_lod, "ships_visible": stoneshore.traffic.root.visible})
		if view.name == "far-no-ships": assert(not stoneshore.traffic.root.visible)
	if "--traffic-movie" in OS.get_cmdline_user_args():
		state.span = 590.0
		board.restore_camera(state)
		await board._stream_visible()
		while not board.detail_ready():
			RenderingServer.force_draw(false)
			await get_tree().process_frame
		var movie_path := output.path_join("frames")
		DirAccess.make_dir_recursive_absolute(movie_path)
		for index in 425:
			for item in builder.harbour_traffic: Traffic.update(item.traffic, index * Traffic.CYCLE / 424.0, builder.active_lod)
			await get_tree().process_frame
			RenderingServer.force_draw(false)
			board._viewport.get_texture().get_image().save_png(movie_path.path_join("%04d.png" % index))
	# Profile transform/material updates after meshes and routes have warmed.
	var sample_start := Time.get_ticks_usec()
	for step in 600:
		for item in builder.harbour_traffic: Traffic.update(item.traffic, step / 10.0, 1)
	report.medium_cpu_ms_per_frame = (Time.get_ticks_usec() - sample_start) / 600000.0
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("[HARBOUR TRAFFIC] ", JSON.stringify(report))
