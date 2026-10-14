extends RefCounted
## Presentation-only frontage fitting. One layout is shared by all three LODs.
const Index := preload("res://scripts/supply_chain_3d/road_index.gd")
const Region := preload("res://scripts/supply_chain_3d/authored_region.gd")
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const Cache := preload("res://scripts/supply_chain_3d/bake_cache.gd")
const Civic := preload("res://scripts/supply_chain_3d/civic_layout.gd")
const Footprints := preload("res://scripts/supply_chain_3d/building_footprints.gd")
const FrontageFill := preload("res://scripts/supply_chain_3d/frontage_fill.gd")
const Sidewalks := preload("res://scripts/supply_chain_3d/urban_sidewalks.gd")
var roads: Array = []
var road_index := {}
var lots: Array = []
var lot_index := {}
var rivers := {}
var ground: Callable
var water: Callable
var asset_key: Callable

func fit(model: Dictionary, height_at: Callable, water_at: Callable, key_for: Callable, river_lines: Dictionary = {}, prepared: Dictionary = {}) -> void:
	ground = height_at; water = water_at; asset_key = key_for
	Sidewalks.apply(model.roads, model.tiles)
	var inputs: Array = []
	for s in model.standing:
		inputs.append([s.iid, s.kind, s.tile, s.pos, s.side, s.get("yaw", 0.0), s.get("footprint", []),
			s.get("harbour", {}), s.get("decor_family", ""), s.get("decor_asset", ""), s.get("max_relief", 12.0), Assets.dimensions(str(asset_key.call(s)))])
	var key := Cache.digest([Cache.source_key("roads"), Cache.source_key("terrain"), model.roads, inputs, river_lines, Civic.catalog_signature(), model.get("trial_rail_segments",[]), model.get("depots",[])])
	var variants: Dictionary = prepared.get_or_add("frontages", {})
	var cached: Dictionary = variants.get(key, {})
	if not cached.is_empty():
		var retained: Array = []
		for s in model.standing:
			if not cached.placements.has(str(s.iid)): continue
			s.merge(cached.placements[str(s.iid)], true)
			retained.append(s)
		retained.append_array(cached.get("infill",[]).duplicate(true))
		model.standing = retained
		model.roads = cached.roads
		model.authored_region.paths = cached.paths
		model.authored_region.frontage = cached.metrics.duplicate(true)
		return
	roads = model.roads
	road_index = Index.segments(roads, 20.0)
	for records in river_lines.values():
		for rec in records:
			for i in range(1, rec.points.size()):
				var half := maxf(float(rec.start_width), float(rec.end_width)) * 0.5 + 3.0
				var segment := {"a": rec.points[i - 1], "b": rec.points[i], "half": half}
				Index.insert(rivers, Index.bounds(segment.a, segment.b, half), segment)
	var zoning := {}
	for s in model.standing:
		if s.has("trial_edge_centers"): zoning[str(s.tile)]=s
	var movable: Array = []
	for s in model.standing:
		if s.has("harbour"):
			reserve(str(s.iid), s.harbour.main_quay)
			for poly in s.harbour.quays: reserve(str(s.iid), poly)
		elif str(s.kind) in ["house", "warehouse", "suppliers"]: movable.append(s)
		elif str(s.kind) != "pylon":
			for poly in footprints(s): reserve(str(s.iid), poly)
	# The pilot's new plots must clear the actual rail corridors and depot yard.
	for depot in model.get("depots",[]):
		if str(depot.tile) in preload("res://scripts/supply_chain_3d/stoneshore_trial.gd").TILES:
			reserve("__rail_yard",preload("res://scripts/supply_chain_3d/rail_depot.gd").yard_polygon(depot))
	for rail in model.get("trial_rail_segments",[]):
		var a: Vector2=rail.a;var b: Vector2=rail.b
		var n := (b-a).normalized().orthogonal()*7.0
		reserve("__rail_track",PackedVector2Array([a+n,b+n,b-n,a-n]))
	movable.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if (a.kind == "house") != (b.kind == "house"): return b.kind == "house"
		var pa := 0 if a.get("trial_green",false) else (1 if a.has("trial_port") else (2 if a.get("decor_family","")=="civic_u_office" else 3))
		var pb := 0 if b.get("trial_green",false) else (1 if b.has("trial_port") else (2 if b.get("decor_family","")=="civic_u_office" else 3))
		return pa<pb if pa!=pb else str(a.iid) < str(b.iid))
	var omitted := 0
	var restored := 0
	var civic_spaces := {}
	var district_counts := {}
	var trial_counts := {}
	var residential_counts := {}
	for s in movable:
		if not model.authored_region.tiles.has(str(s.tile)): continue
		if s.get("trial_density", false) and int(trial_counts.get(str(s.tile), 0)) >= int(model.get("trial_targets", {}).get(str(s.tile), 100000)):
			model.standing.erase(s); omitted += 1; continue
		if s.get("trial_residential",false) and int(residential_counts.get(str(s.tile),0))>=int(model.get("trial_residential_limits",{}).get(str(s.tile),100000)):
			model.standing.erase(s); omitted+=1; continue
		var space_key := str(s.tile) + ":" + str(s.get("decor_family", ""))
		var limit := int(Civic.DISTRICT_LIMITS.get(str(s.get("decor_family", "")), 100000))
		if s.get("trial_density", false): limit = 1 if s.get("decor_family", "") in ["civic_u_office", "civic_bauhaus"] else 100000
		if int(district_counts.get(space_key, 0)) >= limit:
			model.standing.erase(s); omitted += 1; continue
		if s.get("trial_green",false): limit = int(preload("res://scripts/supply_chain_3d/stoneshore_trial.gd").GREEN_LIMITS.get(s.decor_family,1))
		if int(district_counts.get(space_key,0))>=limit:
			model.standing.erase(s); omitted+=1; continue
		if Civic.is_space(s) and not s.get("trial_green",false) and civic_spaces.has(space_key):
			model.standing.erase(s); omitted += 1; continue
		var placed := frontage(s, model.tiles[s.tile].center)
		if not placed and str(s.kind) == "house":
			model.standing.erase(s); omitted += 1; continue
		s.footprints = footprints(s)
		s.footprint = s.footprints[0]
		for poly in s.footprints: reserve(str(s.iid), poly)
		district_counts[space_key] = int(district_counts.get(space_key, 0)) + 1
		if Civic.is_space(s): civic_spaces[space_key] = true
		if s.get("trial_density", false): trial_counts[str(s.tile)] = int(trial_counts.get(str(s.tile), 0)) + 1
		if s.get("trial_residential",false): residential_counts[str(s.tile)] = int(residential_counts.get(str(s.tile),0)) + 1
		if str(s.kind) == "house": restored += 1
	var infill := FrontageFill.new()
	var coverage := infill.run(model,self,zoning) if not zoning.is_empty() else {}
	restored += infill.added.size()
	var connections: Array = []
	var access_stubs: Array = []
	var unconnected: Array = []
	for s in model.standing:
		if str(s.kind) == "pylon" or not model.authored_region.tiles.has(str(s.tile)): continue
		if str(s.kind)=="house":
			s.erase("entrance")
			continue # decorative doors open onto the sidewalk; no asphalt access stubs
		var entry := entrance(s)
		if entry.is_empty():
			if str(s.kind) != "house": unconnected.append(str(s.iid))
			continue
		s.entrance = entry[0]
		if entry[0].distance_to(entry[1]) > 0.05:
			var access := {"id": "access:" + str(s.iid), "points": entry, "class": "minor", "layer": 0}
			if s.get("trial_density",false): access.widths=[1.8,1.6,1.5,1.4]
			connections.append(access)
	if not connections.is_empty():
		var compiled := Region.compile(connections, model.authored_region.tiles)
		model.roads.append_array(compiled.roads)
		model.authored_region.paths = model.authored_region.paths.duplicate(true)
		model.authored_region.paths.append_array(compiled.paths)
		# A new driveway can make the last metre of its receiving street a stub.
		# Clean the full paths before clipping; door endpoints stay protected.
		access_stubs = Index.trim_stubs(model.authored_region.paths)
		if access_stubs.is_empty(): model.roads = Index.split(model.roads)
		else:
			var outside: Array = model.roads.filter(func(r: Dictionary) -> bool: return not model.authored_region.tiles.has(str(r.tile)))
			model.roads = Region.compile_segments(model.authored_region.paths, model.authored_region.tiles)
			model.roads.append_array(outside)
	Sidewalks.apply(model.roads, model.tiles)
	model.authored_region.frontage = {"decorative": restored, "omitted": omitted, "access_roads": connections.size(), "unconnected": unconnected, "trimmed_stubs": access_stubs,"coverage":coverage}
	var placements := {}
	for s in model.standing:
		var placement := {"pos": s.pos, "side": s.side, "yaw": s.get("yaw", 0.0)}
		if s.has("pad"): placement.pad = s.pad
		if s.has("entrance"): placement.entrance = s.entrance
		if s.has("footprint"): placement.footprint = s.footprint
		if s.has("footprints"): placement.footprints = s.footprints
		if s.has("decor_asset"): placement.decor_asset = s.decor_asset
		if s.has("civic_bays"): placement.civic_bays = s.civic_bays
		placements[str(s.iid)] = placement
	# Company-only and full-continent openings must not evict one another.
	while variants.size() >= 4: variants.erase(variants.keys()[0])
	variants[key] = {"placements": placements,"infill":infill.added.duplicate(true), "roads": model.roads, "paths": model.authored_region.paths, "metrics": model.authored_region.frontage}

func reserve(iid: String, polygon: PackedVector2Array) -> void:
	if polygon.is_empty(): return
	var box := polygon_bounds(polygon)
	Index.insert(lot_index, box.grow(4.0), lots.size())
	lots.append({"iid": iid, "polygon": polygon, "box": box})

static func exact_building(s: Dictionary) -> bool:
	return str(s.kind) == "house" and not Civic.is_space(s)

func footprints(s: Dictionary) -> Array:
	if exact_building(s):
		var shapes := Footprints.world(str(asset_key.call(s)), s)
		if not shapes.is_empty(): return shapes
	if s.has("footprint"): return [s.footprint]
	var dim := Assets.dimensions(str(asset_key.call(s))) * float(s.side)
	var half := Vector2(dim.x, dim.z) * 0.5
	var poly := PackedVector2Array()
	for p in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)]:
		poly.append(s.pos + p.rotated(-float(s.get("yaw", 0.0))))
	return [poly]

func footprint(s: Dictionary) -> PackedVector2Array:
	return footprints(s)[0]

func clear_building(s: Dictionary, center: Vector2) -> bool:
	for poly in footprints(s):
		if not clear_plot(poly, center, str(s.iid), float(s.get("max_relief",12.0)), 0.01 if exact_building(s) else 4.0): return false
	return true

static func polygon_bounds(poly: PackedVector2Array) -> Rect2:
	var box := Rect2(poly[0], Vector2.ZERO)
	for p in poly: box = box.expand(p)
	return box

static func distance_to_polygon(a: Vector2, b: Vector2, poly: PackedVector2Array) -> float:
	if Geometry2D.is_point_in_polygon(a, poly) or Geometry2D.is_point_in_polygon(b, poly): return 0.0
	var distance := INF
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		if Geometry2D.segment_intersects_segment(a, b, p, q) != null: return 0.0
		distance = minf(distance, a.distance_to(Geometry2D.get_closest_point_to_segment(a, p, q)))
		distance = minf(distance, b.distance_to(Geometry2D.get_closest_point_to_segment(b, p, q)))
		distance = minf(distance, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return distance

func wet(p: Vector2) -> bool:
	if water.is_valid() and bool(water.call(p)): return true
	for rec in rivers.get(Vector2i((p / Index.CELL).floor()), []):
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p, rec.a, rec.b)) < float(rec.half): return true
	return false

func clear_lots(a: Vector2, b: Vector2, reach: float, ignore: String) -> bool:
	for i in Index.query(lot_index, Index.bounds(a, b, reach)):
		if str(lots[i].iid) != ignore and distance_to_polygon(a, b, lots[i].polygon) < reach: return false
	return true

func clear_plot(poly: PackedVector2Array, center: Vector2, iid: String, max_relief: float = 12.0, clearance: float = 4.0) -> bool:
	var low := INF
	var high := -INF
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		if not clear_lots(a, b, clearance, iid): return false
		for t in [0.0, 0.5]:
			var p := a.lerp(b, t)
			if not Index.contains(center, p) or wet(p): return false
			var height := float(ground.call(p))
			low = minf(low, height); high = maxf(high, height)
	if high - low > max_relief: return false
	for i in Index.query(road_index, polygon_bounds(poly).grow(20.0)):
		var road: Dictionary = roads[i]
		var half := float(road.get("widths", [5.0])[0])
		if distance_to_polygon(road.a, road.b, poly) < half + Sidewalks.width(road) + clearance: return false
	# Edge tests also need the case where a small reserved lot is fully enclosed.
	for i in Index.query(lot_index, polygon_bounds(poly)):
		if str(lots[i].iid) != iid and Geometry2D.is_point_in_polygon(lots[i].polygon[0], poly): return false
	return true

func candidates(p: Vector2, reach: float = 240.0) -> Array:
	var found: Array = []
	for i in Index.query(road_index, Rect2(p, Vector2.ZERO).grow(reach)):
		var road: Dictionary = roads[i]
		var point := Geometry2D.get_closest_point_to_segment(p, road.a, road.b)
		var distance := p.distance_squared_to(point)
		if distance <= reach * reach: found.append({"road": road, "point": point, "distance": distance})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.distance < b.distance)
	return found.slice(0, 40)

func frontage(s: Dictionary, center: Vector2) -> bool:
	if s.get("fixed_plot",false): return clear_building(s,center)
	var modules := Civic.options_for(s)
	if modules.is_empty(): return _fixed_frontage(s, center)
	var saved := s.duplicate(true)
	var options := candidates(s.pos)
	# Largest whole-bay assembly that clears the plot. Windows, storeys and
	# wing thickness stay fixed; the chosen mesh/atlas is shared by its key.
	for module in modules:
		s.decor_asset = module.key
		s.civic_bays = module.bays
		s.side = module.side * float(s.get("decor_scale", 1.0))
		s.erase("footprint"); s.erase("footprints")
		if _fixed_frontage(s, center, options):
			s.pad = s.side
			return true
	s.clear(); s.merge(saved)
	return false

func _fixed_frontage(s: Dictionary, center: Vector2, nearby: Array = []) -> bool:
	var original: Vector2 = s.pos
	var side := float(s.side)
	var yaw := float(s.get("yaw", 0.0))
	var options := candidates(original) if nearby.is_empty() else nearby
	# Civic buildings use a common storey scale. Skip a crowded plot instead of
	# shrinking its doors and floors to 80% of the neighbouring office's size.
	for scale in ([1.0] if s.get("trial_density", false) or (s.has("decor_family") and not Civic.is_space(s)) else [1.0, 0.8]):
		s.side = side * scale
		for option in options:
			for direction in [1.0, -1.0]:
				for along in [0.0, -0.65, 0.65]:
					street_pose(s,option.road,option.point,direction,along)
					if not trial_plot_allowed(s): continue
					if clear_building(s, center): return true
		s.side = side
		if str(s.kind) != "house": break
	s.pos = original; s.side = side; s.yaw = yaw
	return false

func street_pose(s: Dictionary, road: Dictionary, point: Vector2, direction: float, along: float=0.0, turn: float=0.0) -> void:
	var dim := Assets.dimensions(str(asset_key.call(s))) * float(s.side)
	var tangent: Vector2=(road.b-road.a).normalized()
	var toward: Vector2=tangent.orthogonal()*direction
	var half := float(road.get("widths",[5.0])[0])
	s.yaw=-tangent.angle()+turn
	if s.has("decor_family") and direction<0: s.yaw+=PI
	s.pos=point+tangent*dim.x*along
	if exact_building(s):
		var front := INF
		for shape in footprints(s):
			for p in shape: front=minf(front,(p-s.pos).dot(toward))
		s.pos+=toward*(half+Sidewalks.width(road)+0.1-front)
	else: s.pos+=toward*(dim.z*0.5+half+7.0)

func entrance(s: Dictionary) -> PackedVector2Array:
	var center: Vector2 = s.pos
	var shapes := footprints(s) if not s.has("harbour") else [s.harbour.main_quay]
	if s.has("harbour"):
		center = Vector2.ZERO
		for p in shapes[0]: center += p
		center /= shapes[0].size()
	for option in candidates(center):
		var q: Vector2 = option.point
		var door := center
		var closest := INF
		var inside := false
		for poly in shapes:
			inside = inside or Geometry2D.is_point_in_polygon(q, poly)
			for i in poly.size():
				var hit := Geometry2D.get_closest_point_to_segment(q, poly[i], poly[(i + 1) % poly.size()])
				if hit.distance_squared_to(q) < closest:
					closest = hit.distance_squared_to(q); door = hit
		if inside: continue
		if not clear_lots(door, q, 1.8 if exact_building(s) else 4.0, str(s.iid)): continue
		var dry := true
		var steps := maxi(1, ceili(door.distance_to(q) / 4.0))
		var previous := float(ground.call(door))
		for j in range(steps + 1):
			var p := door.lerp(q, float(j) / steps)
			var h := float(ground.call(p))
			if wet(p) or absf(h - previous) > 4.0: dry = false; break
			previous = h
		if dry: return PackedVector2Array([door, q])
	return PackedVector2Array()

func trial_plot_allowed(s: Dictionary) -> bool:
	if s.has("trial_port") and s.pos.distance_to(s.trial_port) > float(s.trial_max_distance): return false
	if s.has("trial_residential"):
		return preload("res://scripts/supply_chain_3d/stoneshore_trial.gd").residential(s.trial_tile, s.pos, s.trial_edge_centers,s.get("trial_harbours",[])) == bool(s.trial_residential)
	return true
