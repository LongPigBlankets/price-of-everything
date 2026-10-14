extends "res://tools/supply_chain_3d/capture.gd"
## Identical camera recipe for archived and current supply-chain renderers.
## Does not depend on authored-road/harbour/civic code, so it runs before them.
var first_open := {}

func _open_supply_view(view: Control) -> void:
	first_open.begin_elapsed_ms = Time.get_ticks_msec()
	var started := Time.get_ticks_msec()
	await super._open_supply_view(view)
	var board: Control = view.find_child("Board", true, false)
	await board._stream_visible()
	while not board.detail_ready():
		RenderingServer.force_draw(false)
		await get_tree().process_frame
	first_open.ready_ms = Time.get_ticks_msec() - started
	first_open.load = board.load_profile.duplicate()

func _ready() -> void:
	PlayerProfile.supply_chain_all_tiles = preload("res://scripts/supply_chain_3d/stoneshore_trial.gd").preview_enabled()
	await super._ready()

func _continent_review(board: Control, home: Dictionary) -> void:
	var output := "res://../outputs/supply-chain-3d/stoneshore-comparison/after"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--comparison-output="): output = arg.trim_prefix("--comparison-output=")
	DirAccess.make_dir_recursive_absolute(output)
	var open_start := Time.get_ticks_msec()
	await board.set_all_tiles(true, false)
	var open_ms := Time.get_ticks_msec() - open_start
	if "--stoneshore-review" in OS.get_cmdline_user_args(): assert(board._model.tiles.size() == 5)
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
	var report := {"engine": Engine.get_version_info().string, "views": [], "tiles": board._model.tiles.keys(), "open_ms": open_ms, "load": board.load_profile, "first_open":first_open}
	if "--stoneshore-review" in OS.get_cmdline_user_args() and "--stoneshore-baseline" not in OS.get_cmdline_user_args():
		var counts := {}
		var factories := 0
		var factory_distance := INF
		var half_scale := true
		for s in board._model.standing:
			if not s.get("trial_density", false): continue
			counts[str(s.tile)] = int(counts.get(str(s.tile),0)) + 1
			half_scale = half_scale and is_equal_approx(float(s.get("decor_scale",1)),0.5)
			if s.get("decor_family", "") == "civic_bauhaus":
				factories += 1
				factory_distance = s.pos.distance_to(s.trial_port)
		var expected: Dictionary = preload("res://scripts/supply_chain_3d/stoneshore_trial.gd").TARGET_BUILDINGS
		report.trial_validation = {"counts":counts, "target":expected, "factory_count":factories, "factory_shore_distance":factory_distance, "half_scale":half_scale}
		if "--draft-review" not in OS.get_cmdline_user_args():
			assert(factories == 1 and factory_distance <= 180 and half_scale, "Stoneshore trial scale/factory placement failed")
		report.neighbourhood = {"sites":board._model.get("district_blocks",{}).get("sites",0), "side_streets":board._model.get("district_blocks",{}).get("paths",[]).size(), "side_street_length":board._model.get("district_blocks",{}).get("length",0), "greens":{}, "semis":0, "apartments":0, "zoning_violations":[], "families":{}, "residential_by_tile":{}}
		for s in board._model.standing:
			var family: String=s.get("decor_family","")
			if s.get("trial_green",false): report.neighbourhood.greens[family]=int(report.neighbourhood.greens.get(family,0))+1
			if family=="civic_semi": report.neighbourhood.semis+=1
			if s.get("name","")=="Apartments": report.neighbourhood.apartments+=1
			if s.get("trial_density",false):
				var asset: String=board._builder.standing_key(s)
				report.neighbourhood.families[asset]=int(report.neighbourhood.families.get(asset,0))+1
			if s.has("trial_residential"):
				if s.trial_residential: report.neighbourhood.residential_by_tile[s.tile]=int(report.neighbourhood.residential_by_tile.get(s.tile,0))+1
				if preload("res://scripts/supply_chain_3d/stoneshore_trial.gd").residential(s.trial_tile,s.pos,s.trial_edge_centers,s.trial_harbours)!=s.trial_residential:
					report.neighbourhood.zoning_violations.append(s.iid)
		if "--draft-review" not in OS.get_cmdline_user_args():
			var total := 0
			for count in counts.values(): total+=int(count)
			assert(counts.size()==5 and total>80,"Neighbourhood density must improve on the previous five-tile trial")
			assert(report.neighbourhood.zoning_violations.is_empty(),"Residential buildings escaped their edge/harbour zoning")
			assert(report.neighbourhood.greens.get("civic_pond",0)==2 and report.neighbourhood.semis>=30 and report.neighbourhood.side_streets>=8,"Missing neighbourhood features")
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
		for tid in ["tile_4_9", "tile_4_10", "tile_5_9", "tile_5_10", "tile_6_9"]:
			var stats := {"houses": 0, "offices": 0, "parks": 0, "infill": 0, "trees": 0, "road_length": 0.0, "standing": []}
			for s in board._model.standing:
				if str(s.tile) != tid: continue
				stats.standing.append({"iid": s.iid, "kind": s.kind, "pos": s.pos, "side": s.side, "footprint": s.get("footprint", []), "footprints": s.get("footprints", []), "yaw": s.get("yaw", 0.0),
					"asset": board._builder.standing_key(s), "tall": s.get("tall", false), "decor_family": s.get("decor_family", ""), "dimension": board._builder.standing_frame(s).dimension, "decor_scale": s.get("decor_scale", 1.0)})
				if s.kind != "house": continue
				if s.get("decor_family", "") in ["civic_park", "civic_plaza", "civic_pond", "civic_grove"]: stats.parks += 1
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
	if "--stoneshore-review" in OS.get_cmdline_user_args():
		views.append({"name":"fields", "point":board._model.tiles.tile_5_9.center, "span":650.0, "pitch":.95, "yaw":0.0})
		views.append({"name":"coast", "point":board._model.tiles.tile_6_9.center, "span":650.0, "pitch":.95, "yaw":0.0})
		for s in board._model.standing:
			if s.get("decor_family", "") == "civic_bauhaus" and s.get("trial_density", false):
				views.append({"name":"factory", "point":s.pos, "span":180.0, "pitch":.80, "yaw":float(s.get("yaw",0))+.50})
		var ponds := 0
		for s in board._model.standing:
			if s.get("decor_family","")=="civic_pond":
				ponds+=1
				views.append({"name":"pond-%d" % ponds,"point":s.pos,"span":250.0,"pitch":.95,"yaw":.3})
		views.append({"name":"far", "point":center, "span":3600.0, "pitch":1.05, "yaw":0.0})
		for s in board._model.standing:
			if str(s.iid).begins_with("z_court:") and str(s.iid).ends_with(":front"):
				views.append({"name":"courtyard","point":s.pos,"span":190.0,"pitch":1.05,"yaw":.3})
				break
		var plots: Array=board._model.get("neighbourhood",{}).get("brownfields",[])
		if not plots.is_empty(): views.append({"name":"brownfield","point":plots[0].pos,"span":200.0,"pitch":1.05,"yaw":.3})
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
	report.interiors = board._model.get("neighbourhood",{}).duplicate(true)
	report.frontage = board._model.authored_region.frontage.duplicate(true)
	report.frontage.decorative_access_stubs=0
	var decorative_ids := {}
	for s in board._model.standing:
		if str(s.kind)=="house": decorative_ids["access:"+str(s.iid)]=true
	for road in board._model.roads:
		if decorative_ids.has(str(road.get("source",""))): report.frontage.decorative_access_stubs+=1
	if "--draft-review" not in OS.get_cmdline_user_args() and not report.frontage.get("coverage",{}).is_empty():
		assert(report.frontage.coverage.after.coverage>=0.75,"Stoneshore buildable frontage is below the 75% regional target")
		assert(report.frontage.decorative_access_stubs==0,"Decorative access-road stubs remain")
	report.footprint_audit = _footprint_audit(board)
	if not report.interiors.is_empty():
		report.interior_audit=_interior_audit(board)
		if "--draft-review" not in OS.get_cmdline_user_args():
			assert(report.footprint_audit.exact_buildings>229,"Interiors must add a net increase over the previous 229 buildings")
			assert(report.interiors.brownfields.size()>=5 and report.interiors.courtyards>=2,"Missing reserved plots or courtyards")
			assert(report.interiors.rows.get("2",0)>=10 and report.interiors.rows.get("3",0)>0,"Missing second/third housing rows")
			assert(report.interior_audit.parcel_intrusions.is_empty(),"Brownfield parcel is occupied")
			assert(report.footprint_audit.building_overlaps.is_empty() and report.footprint_audit.street_overlaps.is_empty(),"Block interiors overlap buildings or roads")
	report.final_cache = {"hits":board._builder.bake_cache.hits, "bundled_hits":board._builder.bake_cache.bundled_hits, "writes":board._builder.bake_cache.writes}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))

func _interior_audit(board: Control) -> Dictionary:
	var fit: GDScript=preload("res://scripts/supply_chain_3d/road_placement.gd")
	var result := {"parcel_intrusions":[],"brownfield_area":0.0}
	for site in board._model.neighbourhood.brownfields:
		result.brownfield_area+=float(site.size.x*site.size.y)
		for s in board._model.standing:
			for poly in s.get("footprints",[]):
				var overlap := Geometry2D.is_point_in_polygon(site.polygon[0],poly)
				for i in poly.size(): overlap=overlap or fit.distance_to_polygon(poly[i],poly[(i+1)%poly.size()],site.polygon)<.01
				if overlap: result.parcel_intrusions.append([site.id,s.iid])
		for tree in board._builder.tree_placements.get(site.tile,[]):
			if Geometry2D.is_point_in_polygon(tree.pos,site.polygon): result.parcel_intrusions.append([site.id,"tree"])
	return result

func _footprint_audit(board: Control) -> Dictionary:
	var fit: GDScript=preload("res://scripts/supply_chain_3d/road_placement.gd")
	var walks: GDScript=preload("res://scripts/supply_chain_3d/urban_sidewalks.gd")
	var result := {"exact_buildings":0,"sidewalk_segments":0,"building_overlaps":[],"street_overlaps":[]}
	var standing: Array=board._model.standing
	for road in board._model.roads:
		if walks.width(road)>0: result.sidewalk_segments+=1
	for i in standing.size():
		var s: Dictionary=standing[i]
		if not fit.exact_building(s): continue
		result.exact_buildings+=1
		for poly in s.get("footprints",[]):
			for road in board._model.roads:
				if str(road.get("source","")).begins_with("access:") or road.get("tunnel",false): continue
				var reach: float=float(road.get("widths",[5.0])[0])+walks.width(road)
				if fit.distance_to_polygon(road.a,road.b,poly)<reach-0.05:
					result.street_overlaps.append({"building":s.iid,"street":road.get("source",""),"intrusion":reach-fit.distance_to_polygon(road.a,road.b,poly)})
			for j in range(i+1,standing.size()):
				var other: Dictionary=standing[j]
				for shape in other.get("footprints",[]):
					var overlap := Geometry2D.is_point_in_polygon(shape[0],poly)
					for k in poly.size(): overlap=overlap or fit.distance_to_polygon(poly[k],poly[(k+1)%poly.size()],shape)<0.001
					if overlap: result.building_overlaps.append([s.iid,other.iid])
	return result
