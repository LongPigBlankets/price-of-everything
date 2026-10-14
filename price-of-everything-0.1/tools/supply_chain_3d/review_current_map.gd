extends "res://tools/supply_chain_3d/capture.gd"
## Read-only visual tour of the installed production package, without trial patches.
var output := "res://../outputs/supply-chain-3d/current-map-review"
var reference := {}

func _ready() -> void:
	PlayerProfile.supply_chain_all_tiles = true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--review-output="): output = arg.trim_prefix("--review-output=")
		if arg.begins_with("--reference-review="):
			var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(arg.trim_prefix("--reference-review=")))
			for view in doc.views: reference[view.name] = view.camera
	DirAccess.make_dir_recursive_absolute(output)
	await super._ready()

func _continent_review(board: Control, home: Dictionary) -> void:
	await board.set_all_tiles(true, false)
	await _settle_review(board)
	board.set_process(false)
	board._labels.hide()
	board.animate_goods = false
	var builder: RefCounted = board._builder
	var model: Dictionary = board._model
	var cache: RefCounted = builder.bake_cache
	var fingerprints: Dictionary = cache.source_fingerprints()
	var bundled: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(cache.BUNDLED.path_join("source_fingerprints.json")))
	var report := {"engine": Engine.get_version_info().string, "production_fingerprints_match": cache.fingerprints_match(bundled, fingerprints),
		"load": board.load_profile.duplicate(true), "tiles": model.tiles.size(), "views": [], "places": [],
		"continent_key": builder._continent_key, "depots": builder.depots, "housing_sides": {}, "housing_heights": {}, "trees": 0}
	for s in model.standing:
		if s.kind == "house" and not s.get("tall", false) and not s.has("decor_family"):
			var side := str(snappedf(float(s.side), 0.01))
			report.housing_sides[side] = int(report.housing_sides.get(side, 0)) + 1
			var height := str(snappedf(float(builder.standing_frame(s).dimension.y), 0.01))
			report.housing_heights[height] = int(report.housing_heights.get(height, 0)) + 1
	for records in builder.tree_placements.values(): report.trees += records.size()
	var rural_focus := Vector2.ZERO
	report.civic = {}
	for s in model.standing:
		if s.has("decor_family"):
			var family := str(s.decor_family)
			report.civic[family] = int(report.civic.get(family, 0)) + 1
	var most_rows := 0
	report.rail_vegetation = {"row_trees": 0, "tiles_with_rows": 0, "clearance_violations": 0, "rail_size_violations": 0, "sizes": {}, "row_sizes": {}}
	for tid in builder.tree_placements:
		var count := 0
		for tree in builder.tree_placements[tid]:
			var size := str(tree.get("size_scale", 1.0))
			report.rail_vegetation.sizes[size] = int(report.rail_vegetation.sizes.get(size, 0)) + 1
			if tree.get("source", "") == "rail_row":
				count += 1
				report.rail_vegetation.row_sizes[size] = int(report.rail_vegetation.row_sizes.get(size, 0)) + 1
			if builder.rail_vegetation.beside_rail(tree.pos) and float(tree.get("size_scale", 1.0)) != 0.5:
				report.rail_vegetation.rail_size_violations += 1
			if not builder.rail_vegetation.clear(tree.pos, builder.TreeLayout.canopy(tree)):
				report.rail_vegetation.clearance_violations += 1
		report.rail_vegetation.row_trees += count
		if count > 0: report.rail_vegetation.tiles_with_rows += 1
		if count > most_rows: most_rows = count; rural_focus = model.tiles[tid].center
	var summit := Vector2.ZERO
	var highest := -INF
	for tile in model.tiles.values():
		if "Capital" in str(tile.label) or "Stoneshore" in str(tile.label): report.places.append({"label": tile.label, "center": tile.center})
		for y in range(-160, 161, 160):
			for x in range(-160, 161, 160):
				var p: Vector2 = tile.center + Vector2(x, y)
				var h: float = builder.ground_height(p)
				if h > highest: highest = h; summit = p
	report.summit = {"position": summit, "height": highest}
	var coast := preload("res://scripts/supply_chain_3d/coast.gd")
	report.water = {"limits": coast.Water.data().limits, "lake_checks": coast.Water.data().lake_checks,
		"islets": coast.Water.data().islets, "source": coast.Water.data().source_sha256}
	if coast._grounds.has(false):
		var original: RefCounted = coast._grounds[false]
		var changed := 0; var samples := 0; var maximum := 0.0
		for y in range(-480, 481, 24):
			for x in range(-480, 481, 24):
				var p := summit + Vector2(x, y)
				var delta: float = builder.ground_height(p) - builder.Relief.height(original.height(p))
				samples += 1
				if absf(delta) > 0.1: changed += 1
				maximum = maxf(maximum, absf(delta))
		report.half_relief = {"mountain_samples": samples, "changed_samples": changed, "maximum_height_change": maximum}
	board.fit_view()
	var fitted: Dictionary = board.capture_camera()
	var views: Array = [{"name": "continent", "point": Vector2(fitted.target.x, fitted.target.z), "span": fitted.span, "pitch": 1.05, "yaw": 0.0}]
	var stoneshore: Vector2 = (model.tiles.tile_4_9.center + model.tiles.tile_4_10.center + model.tiles.tile_5_10.center) / 3.0
	views.append_array([
		{"name": "overlap-stoneshore", "point": Vector2(2700,5221), "span": 360.0, "pitch": 1.15, "yaw": 0.0},
		{"name": "overlap-snare", "point": Vector2(3490,5687), "span": 380.0, "pitch": 1.15, "yaw": 0.0},
		{"name": "overlap-holyfinger", "point": Vector2(2287,9605), "span": 380.0, "pitch": 1.15, "yaw": 0.0},
		{"name": "lake-upland", "point": Vector2(4312,1196), "span": 1150.0, "pitch": 0.85, "yaw": 0.35},
		{"name": "lake-seam-far", "point": Vector2(9170,7786), "span": 2600.0, "pitch": 1.05, "yaw": 0.0},
		{"name": "lake-seam-medium", "point": Vector2(9170,7786), "span": 1100.0, "pitch": 1.05, "yaw": 0.0},
		{"name": "lake-seam-near", "point": Vector2(9201,7695), "span": 480.0, "pitch": 0.95, "yaw": 0.35},
		{"name": "coast-islets", "point": model.tiles.tile_4_10.center + Vector2(-240, 0), "span": 600.0, "pitch": 1.05, "yaw": 0.0},
		{"name": "stoneshore-far", "point": stoneshore, "span": 2600.0, "pitch": 1.05, "yaw": 0.0},
		{"name": "stoneshore-medium", "point": stoneshore, "span": 1100.0, "pitch": 1.05, "yaw": 0.0},
		{"name": "stoneshore-near", "point": model.tiles.tile_4_10.center, "span": 480.0, "pitch": 1.05, "yaw": 0.35},
		{"name": "harbour", "point": Vector2(2640,5840), "span": 650.0, "pitch": 0.95, "yaw": 0.35},
		{"name": "mountains-far", "point": summit, "span": 2900.0, "pitch": 0.72, "yaw": 0.55},
		{"name": "mountains-medium", "point": summit, "span": 1100.0, "pitch": 0.72, "yaw": 0.55},
		{"name": "mountains-near", "point": summit, "span": 580.0, "pitch": 0.72, "yaw": 0.55}
	])
	if most_rows > 0:
		for tier in ["far", "medium", "near"]:
			views.append({"name": "rural-rail-" + tier, "point": rural_focus, "span": {"far": 2600.0, "medium": 1100.0, "near": 480.0}[tier], "pitch": 0.95, "yaw": 0.35})
		views.append({"name": "rural-rail-old-linework", "point": rural_focus, "span": 1100.0, "pitch": 0.95, "yaw": 0.35})
	for tile in model.tiles.values():
		if str(tile.label).begins_with("Capital Port -"):
			views.append({"name": "capital-medium", "point": tile.center, "span": 1100.0, "pitch": 0.95, "yaw": 0.0})
			views.append({"name": "capital-near", "point": tile.center, "span": 500.0, "pitch": 0.95, "yaw": 0.0})
			views.append({"name": "capital-orbit", "point": tile.center, "span": 500.0, "pitch": 0.70, "yaw": 1.2})
			break
	for depot in builder.depots:
		if "stoneshore" in str(depot.city).to_lower():
			views.append({"name": "stoneshore-rail-depot", "point": depot.pos, "span": 560.0, "pitch": 0.85, "yaw": 0.35})
			break
	if not builder.road_grade.bridges.is_empty():
		views.append({"name": "road-rail-crossing", "point": builder.road_grade.bridges[0].p, "span": 420.0, "pitch": 0.75, "yaw": 0.6})
	if "--district-review" in OS.get_cmdline_user_args():
		var seen := {}
		for s in model.standing:
			var family := str(s.get("decor_family", ""))
			if family not in ["civic_u_office", "civic_semi", "civic_bauhaus", "civic_commercial"] or seen.has(family): continue
			seen[family] = true
			views.append({"name": family, "point": s.pos, "span": 480.0 if family == "civic_u_office" else 250.0,
				"pitch": .85, "yaw": float(s.get("yaw", 0.0)) + .5})
		assert(seen.size() == 4, "Every new decorative family must fit at least one real plot")
	var only := PackedStringArray()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-names="): only = arg.trim_prefix("--capture-names=").split(",")
	for view in views:
		if not only.is_empty() and str(view.name) not in only: continue
		var state := home.duplicate()
		state.target = builder.point(view.point)
		state.span = view.span
		state.pitch = view.pitch
		state.yaw = view.yaw
		if reference.has(view.name):
			state = reference[view.name].duplicate()
			var xyz := str(state.target).trim_prefix("(").trim_suffix(")").split(",")
			state.target = Vector3(float(xyz[0]), float(xyz[1]), float(xyz[2]))
		board.restore_camera(state)
		await _settle_review(board)
		# A controlled old/new medium linework comparison on identical scenery.
		for item in builder.detail_nodes:
			if item.node.mesh == builder.infrastructure_bake.get("rail_near"):
				item.node.visible = board._detail == 2 or view.name == "rural-rail-old-linework"
			elif item.node.mesh == builder.infrastructure_bake.get("rail_overview"):
				item.node.visible = board._detail < 2 and view.name != "rural-rail-old-linework"
		for i in 3:
			await get_tree().process_frame
			RenderingServer.force_draw(false)
		var image: Image = board._viewport.get_texture().get_image()
		assert(image.save_png(output.path_join(view.name + ".png")) == OK)
		report.views.append({"name": view.name, "camera": board.capture_camera(), "lod": board._detail,
			"cache_hits": cache.hits, "bundled_hits": cache.bundled_hits, "cache_writes": cache.writes})
		print("[MAP REVIEW] ", view.name, " lod=", board._detail, " bundled=", cache.bundled_hits, " writes=", cache.writes)
	if "--audit-transport" in OS.get_cmdline_user_args():
		preload("res://tools/supply_chain_3d/export_transport_audit.gd").write(builder, model)
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))

func _settle_review(board: Control) -> void:
	await board._stream_visible()
	while not board.detail_ready():
		RenderingServer.force_draw(false)
		await get_tree().process_frame
	for i in 12:
		RenderingServer.force_draw(false)
		await get_tree().process_frame
