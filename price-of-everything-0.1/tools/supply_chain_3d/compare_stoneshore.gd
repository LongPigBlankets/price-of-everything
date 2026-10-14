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
	views.append({"name":"docks-centre","point":board._model.tiles.tile_5_10.center,"span":550.0,"pitch":1.05,"yaw":0.0})
	views.append({"name":"depot-routes","point":Vector2(2800,5500),"span":420.0,"pitch":1.10,"yaw":.1})
	views.append({"name":"coastal-margin","point":Vector2(2785,5760),"span":370.0,"pitch":.75,"yaw":.5})
	views.append({"name":"docks-north","point":Vector2(2700,5370),"span":330.0,"pitch":.95,"yaw":.3})
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
	report.docks_rails=_docks_rail_audit(board)
	report.skyline=[]
	for s in board._model.standing:
		if s.has("trial_skyline"):report.skyline.append({"iid":s.iid,"p":s.pos,"distance":s.pos.distance_to(s.trial_skyline),"asset":board._builder.standing_key(s)})
	report.sea_margin={"fraction":board._builder.sea_fringe.FRACTION,"width":board._builder.sea_fringe.WIDTH,"parts":board._builder.sea_fringe.strips.size()}
	report.sea_margin.merge(_coastal_surface_audit(board))
	report.depot_roads=_depot_routes_audit(board)
	report.street_curves=board._model.get("street_curves",{})
	report.plazas={"targets":board._builder.urban_plazas.get("targets",0),"area":board._builder.urban_plazas.get("area",0)}
	report.greenery={"tiles":board._builder.greenery_audit,"land_area":0.0,"canopy_area":0.0,"trees":0,"beach_trees":0,"plaza_trees":0}
	for stats in report.greenery.tiles.values():
		for field in ["land_area","canopy_area","trees","beach_trees","plaza_trees"]:report.greenery[field]+=stats[field]
	report.greenery.coverage=report.greenery.canopy_area/maxf(1,report.greenery.land_area)
	report.greenery.fine_grid=_canopy_audit(board)
	report.junctions=_flare_audit(board)
	report.port_approach=_port_audit(board)
	_export_review_plan(board,output)
	if "--draft-review" not in OS.get_cmdline_user_args():
		assert(report.docks_rails.yard_height_error<.01 and report.docks_rails.hidden_yard_samples==0,"Docks working yard must remain open at its original elevation")
		assert(report.docks_rails.building_conflicts.is_empty() and report.docks_rails.parallel_road_conflicts.is_empty(),"Docks rail still overlaps buildings or parallel road surfaces")
		assert(report.skyline.size()==3,"Missing central Docks skyline landmarks")
		assert(report.sea_margin.parts>0 and report.sea_margin.get("coastal_land_area",0)>0 and report.sea_margin.get("coverage_error",1)<.0001,"Missing continuous coastal land and sea margin")
		assert(report.depot_roads.a_crossings==0 and report.depot_roads.b_bridges==1 and report.depot_roads.single_pair and report.depot_roads.old_spur==0,"Depot routes must remove the fan crossing and bridge just the single pair")
		assert(report.greenery.coverage>=.10 and report.greenery.fine_grid.coverage>=.10 and report.greenery.beach_trees<=20 and report.greenery.plaza_trees>0,"Stoneshore canopy/beach/plaza planting target failed")
		assert(report.junctions.overlaps.is_empty(),"Junction flares intrude into buildings")
		assert(report.port_approach.get("inland",0)>=24 and report.port_approach.get("afloat",false) and report.port_approach.get("gap",INF)<.05 and report.port_approach.get("alignment",0)>.999 and report.port_approach.get("height_error",INF)<.2,"Port road does not meet the moved asset entrance")
		assert(report.plazas.targets>0 and report.plazas.area>0 and report.street_curves.get("rounded_bends",0)>0,"Missing plaza or road curve work")
		assert(report.depot_roads.a_clearance>=10 and report.depot_roads.b_clearance>=10,"Depot roads must leave a 10u clear gap to ballast")
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

func _docks_rail_audit(board: Control) -> Dictionary:
	var b: RefCounted=board._builder
	var clearance := preload("res://scripts/supply_chain_3d/rail_clearance.gd")
	var rail := preload("res://scripts/supply_chain_3d/railway.gd")
	var fit := preload("res://scripts/supply_chain_3d/road_placement.gd")
	var index := preload("res://scripts/supply_chain_3d/road_index.gd")
	var buildings: Array=[]
	for s in board._model.standing:
		if str(s.tile)!="tile_5_10" or str(s.kind) in ["pylon","port"] or s.has("harbour") or s.get("decor_family","") in ["civic_grove","civic_park","civic_plaza","civic_pond"]:continue
		var key: String=b.standing_key(s)
		if key!="":buildings.append({"id":s.iid,"polygons":clearance.building_polygons(s,key)})
	var road_index: Dictionary=index.segments(b.road_grade.segments,24)
	var report := {"building_conflicts":[],"parallel_road_conflicts":[],"covered_length":0.0,"yard_height_error":0.0,"hidden_yard_samples":0}
	for t in b.rail_urban.tracks:
		var p: Vector2=(t.a+t.b)*.5
		if not index.contains(board._model.tiles.tile_5_10.center,p):continue
		for depot in b.depots:
			if Geometry2D.is_point_in_polygon(p,preload("res://scripts/supply_chain_3d/rail_depot.gd").yard_polygon(depot)):
				report.yard_height_error=maxf(report.yard_height_error,maxf(absf(t.ha-t.base_a),absf(t.hb-t.base_b)))
				if t.hidden_a or t.hidden_b:report.hidden_yard_samples+=1
		if t.hidden_a or t.hidden_b:
			report.covered_length+=t.a.distance_to(t.b);continue
		for building in buildings:
			for poly in building.polygons:
				if fit.distance_to_polygon(t.a,t.b,poly)<rail.CORRIDOR_WIDTH*.5:
					report.building_conflicts.append({"building":building.id,"p":p});break
		for ri in index.query(road_index,index.bounds(t.a,t.b,24)):
			var road: Dictionary=b.road_grade.segments[ri]
			if absf((t.b-t.a).normalized().dot((road.b-road.a).normalized()))<.95:continue
			var q := Geometry2D.get_closest_point_to_segment(p,road.a,road.b)
			if q.distance_to(p)>=float(road.half)+rail.CORRIDOR_WIDTH*.5:continue
			var road_h := lerpf(road.ha,road.hb,road.a.distance_to(q)/maxf(.001,road.a.distance_to(road.b)))
			if road_h-.5-((t.ha+t.hb)*.5+1.25)<rail.CLEARANCE:
				report.parallel_road_conflicts.append({"road":road.source,"p":p})
	return report

func _export_review_plan(board: Control, output: String) -> void:
	# Numeric, read-only inputs for road alternatives and sea-envelope audits.
	var b: RefCounted=board._builder
	var plan := {"tiles":{},"sea_margin":b.sea_fringe.strips,"roads":b.road_grade.segments,"rails":b.rail_urban.tracks,"depots":b.depots,"buildings":[],"land":[],"depot_roads":board._model.get("depot_roads",{}),"plazas":b.urban_plazas,"trees":b.tree_placements}
	for tid in b.tiles:plan.tiles[tid]=b.tiles[tid].center
	for s in board._model.standing:
		plan.buildings.append({"iid":s.iid,"pos":s.pos,"kind":s.kind,"polygons":preload("res://scripts/supply_chain_3d/rail_clearance.gd").building_polygons(s,b.standing_key(s))})
	var tids := {}
	for tid in b.tiles:
		tids[tid]=true
		for nb in Catalog.tile_neighbours(tid):tids[nb]=true
	for tid in tids:plan.land.append_array(preload("res://scripts/supply_chain_3d/water_geography.gd").for_tile(tid).land)
	FileAccess.open(output.path_join("plan.json"),FileAccess.WRITE).store_string(JSON.stringify(_numeric(plan)))

func _numeric(value: Variant) -> Variant:
	if value is Vector2 or value is Vector2i:return [value.x,value.y]
	if value is Array or value is PackedVector2Array:
		var result: Array=[]
		for item in value:result.append(_numeric(item))
		return result
	if value is Dictionary:
		var result := {}
		for key in value:result[str(key)]=_numeric(value[key])
		return result
	return value

func _depot_routes_audit(board: Control) -> Dictionary:
	var routes := preload("res://scripts/supply_chain_3d/depot_roads.gd")
	var result := {"a_clearance":INF,"b_clearance":INF,"a_crossings":0,"b_bridges":0,"old_spur":0,"bridge":{},"single_pair":false}
	var proposal: Dictionary=board._model.get("depot_roads",{})
	if proposal.is_empty():return result
	var corridors: Array=[]
	for c in board._builder.rail_plan.corridors:
		for i in range(1,c.points.size()):
			if proposal.bridge.distance_to(Geometry2D.get_closest_point_to_segment(proposal.bridge,c.points[i-1],c.points[i]))<.01:
				corridors.append(c);break
	result.single_pair=corridors.size()==1 and not corridors[0].has("junction")
	for road in board._builder.road_grade.segments:
		if road.source=="r:untitled:65":result.old_spur+=1
		if road.source not in [routes.A,routes.B]:continue
		var key := "a_clearance" if road.source==routes.A else "b_clearance"
		var steps := maxi(1,ceili(road.a.distance_to(road.b)))
		for i in steps+1:
			var p: Vector2=road.a.lerp(road.b,float(i)/steps)
			# The crossing and its curved turn necessarily approach the ballast.
			if road.source==routes.B and p.distance_to(proposal.bridge)<40:continue
			result[key]=minf(result[key],routes.rail_distance(p,board._builder.rail_plan)-routes.ROAD_HALF-routes.Rail.CORRIDOR_WIDTH*.5)
	for crossing in board._builder.road_grade.crossings:
		if routes.A in crossing.sources:result.a_crossings+=1
		if routes.B in crossing.sources:
			if crossing.mode=="bridge":result.b_bridges+=1
			result.bridge=crossing
	return result

func _coastal_surface_audit(board: Control) -> Dictionary:
	var data: Dictionary=board._builder.infrastructure_bake.get("sea_fringe",{})
	if data.is_empty():return {}
	var result: Dictionary=data.audit.duplicate()
	var vertices: PackedVector3Array=data.top.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var area := 0.0
	for i in range(0,vertices.size(),3):
		var a := Vector2(vertices[i].x,vertices[i].z)
		var b := Vector2(vertices[i+1].x,vertices[i+1].z)
		var c := Vector2(vertices[i+2].x,vertices[i+2].z)
		area+=absf((b-a).cross(c-a))*.5
	result.rendered_area=area
	result.coverage_error=absf(area-result.surface_area)/result.surface_area
	return result

func _canopy_audit(board: Control) -> Dictionary:
	# Independent finer grid over the whole region: catches boundary-spanning
	# crowns and never double-counts overlapping canopies or land area.
	const Grid := 2.0
	var canopy := {};var dry := {};var b: RefCounted=board._builder
	for trees in b.tree_placements.values():
		for tree in trees:
			var r: Vector2=preload("res://scripts/supply_chain_3d/stoneshore_greenery.gd").radii(tree)
			for y in range(floori((tree.pos.y-r.y)/Grid),ceili((tree.pos.y+r.y)/Grid)):
				for x in range(floori((tree.pos.x-r.x)/Grid),ceili((tree.pos.x+r.x)/Grid)):
					var k := Vector2i(x,y)
					if ((Vector2(k)*Grid+Vector2.ONE*Grid*.5-tree.pos)/r).length_squared()<=1:canopy[k]=true
	for tid in b.tiles:
		var center: Vector2=b.tiles[tid].center
		var rel := preload("res://scripts/supply_chain_3d/coast.gd").relief_of(tid,center)
		for y in range(floori((center.y-240)/Grid),ceili((center.y+240)/Grid)):
			for x in range(floori((center.x-270)/Grid),ceili((center.x+270)/Grid)):
				var k := Vector2i(x,y);var p := Vector2(k)*Grid+Vector2.ONE*Grid*.5
				if preload("res://scripts/supply_chain_3d/road_index.gd").contains(center,p) and not preload("res://scripts/empire_board_ground.gd").is_water(rel,p):dry[k]=true
	var count := 0
	for k in dry:if canopy.has(k):count+=1
	return {"cell_size":Grid,"land_area":dry.size()*Grid*Grid,"canopy_area":count*Grid*Grid,"coverage":float(count)/maxi(1,dry.size())}

func _flare_audit(board: Control) -> Dictionary:
	var surface := preload("res://scripts/supply_chain_3d/road_surface.gd").new()
	surface.configure(board._builder.road_grade.segments,board._builder.road_height)
	var fit := preload("res://scripts/supply_chain_3d/road_placement.gd")
	var index := preload("res://scripts/supply_chain_3d/road_index.gd")
	var polys: Array=[];var buckets := {};var result := {"flares":0,"overlaps":[]}
	for s in board._model.standing:
		if not fit.exact_building(s):continue
		for poly in s.get("footprints",[]):
			index.insert(buckets,fit.polygon_bounds(poly),polys.size());polys.append({"poly":poly,"iid":s.iid})
	for joint in surface.flares:
		var a: Dictionary=joint.a.road;var b: Dictionary=joint.b.road
		var walks := preload("res://scripts/supply_chain_3d/urban_sidewalks.gd")
		var poly := preload("res://scripts/supply_chain_3d/street_curves.gd").flare(joint.p,joint.a.d,joint.b.d,float(a.widths[0])+walks.width(a),float(b.widths[0])+walks.width(b),4)
		if poly.is_empty():continue
		result.flares+=1
		for id in index.query(buckets,fit.polygon_bounds(poly)):
			for overlap in Geometry2D.intersect_polygons(poly,polys[id].poly):
				if preload("res://scripts/supply_chain_3d/sea_fringe.gd").area(overlap)>.05:result.overlaps.append(polys[id].iid)
	surface.finish_build();return result

func _port_audit(board: Control) -> Dictionary:
	var plan: Dictionary=board._model.get("port_approach",{})
	if plan.is_empty():return {}
	var result := {"inland":plan.inland,"lateral":plan.lateral,"gap":INF,"alignment":0.0,"height_error":INF,"afloat":false}
	var b: RefCounted=board._builder
	var harbour := preload("res://scripts/supply_chain_3d/harbour.gd")
	for s in board._model.standing:
		if not s.has("harbour") or not s.harbour.has("trial_frame"):continue
		var frame: Dictionary=b.standing_frames[s.iid]
		var asset := preload("res://scripts/supply_chain_3d/assets.gd").harbour_for(frame.harbour_asset)
		var pose: Transform3D=frame.harbour_transform
		var entry3 := pose*harbour.vector3(asset.road_entry)
		var entry: Vector2=s.pos+Vector2(entry3.x,entry3.z)
		result.afloat=harbour.ships_afloat(asset,pose,s.pos,b.natural_height)
		for road in b.road_grade.segments:
			if road.source!=preload("res://scripts/supply_chain_3d/port_approach.gd").SOURCE:continue
			var q := Geometry2D.get_closest_point_to_segment(entry,road.a,road.b)
			if q.distance_to(entry)<result.gap:
				result.gap=q.distance_to(entry)
				result.alignment=absf((road.b-road.a).normalized().dot(s.harbour.offshore))
				result.height_error=absf(b.road_height(entry)+1.09-entry3.y)
	return result
