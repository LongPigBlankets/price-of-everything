extends RefCounted
## A stable, map-wide presentation network. Never grants transport infrastructure.
const Authored := preload("res://scripts/authored_map.gd")
const Painter := preload("res://scripts/authored_fabric_painter.gd")
const Index := preload("res://scripts/supply_chain_3d/road_index.gd")
const Model := preload("res://scripts/empire_board_model.gd")
const Rail := preload("res://scripts/supply_chain_3d/railway.gd")
const Depot := preload("res://scripts/supply_chain_3d/rail_depot.gd")
const VERSION := 7
## Each river crossing costs this much when a line picks its route, so a line crosses a
## river once on one bridge, not repeatedly where it meanders.
const RIVER_CROSSING_COST := 6000.0
## Rivers run through tile centres, so a centred anchor puts the junction fan on the water
## and every line leaving it on the banks. Anchors keep this clearance from a river.
const ANCHOR_RIVER_CLEARANCE := 130.0
## Hand-placed anchors, as offsets from the tile centre. Stoneshore Fields: the default
## anchor sat on the tile's central road junction, so five lines fanned out under it and
## every road arm needed a deck. North of it the fan has open ground.
const ANCHOR_OFFSETS := {"tile_5_9": Vector2(120, -210)}
## Hand-placed via points, listed from the first tile in the edge id. The Fields line to
## tile_5_10 crosses the six-lane avenue square on, then rejoins its old corridor under the
## north–south street instead of cutting through the grove block beside it.
const LINE_VIAS := {"tile_5_10|tile_5_9": [Vector2(2700, 5200), Vector2(2845, 5080)]}
static var _cache: Dictionary = {}
const Cache := preload("res://scripts/supply_chain_3d/bake_cache.gd")
static var prepared_keys := {}
static var cache_hits := 0
static var cache_misses := 0

static func edge_id(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a

## Urban protection precedes development; equal building counts use terrain,
## then a seeded random draw. Ranking never depends on Dictionary iteration order.
static func dropout_rank(tile: Dictionary) -> Vector3i:
	return Vector3i(1 if tile.type == "urban" else 0, int(tile.get("buildings", 0)),
		{"mountain": 0, "hill": 1, "rural": 2, "urban": 3}.get(tile.type, 2))

static func topology(tiles: Dictionary, seed: int) -> Dictionary:
	var graph := {}; var edges := {}; var drops: Array = []; var kept: Array = []
	var order := tiles.keys(); order.sort()
	for tid in order: graph[tid] = {}
	for tid in order:
		for nb in tiles[tid].get("neighbours", []):
			if not tiles.has(nb) or nb == tid: continue
			graph[tid][nb] = true; graph[nb][tid] = true
			edges[edge_id(tid,nb)] = {"a": min_str(tid,nb), "b": max_str(tid,nb)}
	var original := graph.duplicate(true)
	order.sort_custom(func(a: String,b: String) -> bool: return RoadHash.fnv1a("rail-order:%d:%s" % [seed,a]) < RoadHash.fnv1a("rail-order:%d:%s" % [seed,b]))
	for tid in order:
		# A neighbour may already have removed this shared edge. Only a tile
		# still connected to ALL its land neighbours requests another dropout.
		if graph[tid].size() != original[tid].size() or graph[tid].size() < 2: continue
		var candidates: Array = graph[tid].keys()
		candidates.sort_custom(func(a: String,b: String) -> bool:
			var ra := dropout_rank(tiles[a]); var rb := dropout_rank(tiles[b])
			if ra != rb:
				if ra.x != rb.x: return ra.x < rb.x
				if ra.y != rb.y: return ra.y < rb.y
				return ra.z < rb.z
			return RoadHash.fnv1a("rail-drop:%d:%s:%s" % [seed,tid,a]) < RoadHash.fnv1a("rail-drop:%d:%s:%s" % [seed,tid,b]))
		var removed := false
		for nb in candidates:
			graph[tid].erase(nb); graph[nb].erase(tid)
			if reachable(graph,tid,nb):
				edges.erase(edge_id(tid,nb))
				drops.append({"tile":tid,"neighbour":nb,"buildings":tiles[nb].get("buildings",0),"type":tiles[nb].type})
				removed = true; break
			graph[tid][nb] = true; graph[nb][tid] = true
		if not removed: kept.append(tid)
	var ordered_edges: Array = edges.values()
	ordered_edges.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return edge_id(a.a,a.b)<edge_id(b.a,b.b))
	return {"edges":ordered_edges,"adjacency":graph,"drops":drops,"protected_bridges":kept,"components":components(graph)}

static func reachable(graph: Dictionary, a: String, b: String) -> bool:
	var seen := {a:true}; var queue: Array = [a]; var next := 0
	while next < queue.size():
		var at: String = queue[next]; next += 1
		if at == b: return true
		for nb in graph[at]:
			if not seen.has(nb): seen[nb] = true; queue.append(nb)
	return false

static func components(graph: Dictionary) -> Array:
	var seen := {}; var result: Array = []
	var order := graph.keys(); order.sort()
	for tid in order:
		if seen.has(tid): continue
		var group: Array = [tid]; seen[tid] = true; var i := 0
		while i < group.size():
			for nb in graph[group[i]]:
				if not seen.has(nb): seen[nb] = true; group.append(nb)
			i += 1
		group.sort(); result.append(group)
	return result

static func min_str(a: String,b: String) -> String: return a if a < b else b
static func max_str(a: String,b: String) -> String: return a if a > b else b

## Count actual authored decorative masses/special buildings, not empty slots,
## trees, parks, or the generated 3D infill. Group multi-piece masses by ID.
static func authored_buildings(centers: Dictionary, settlements: Dictionary) -> Dictionary:
	var tile_index := Index.tiles(centers)
	var counts := {}; var obstacles: Array = []; var ids := {}
	for tid in centers: counts[tid] = 0
	for settlement in settlements.values():
		for kind in ["decor","specials"]:
			for rec in settlement.get(kind,[]):
				if str(rec.get("port_role", "")) in ["quay","pier","apron"]: continue
				var id := str(rec.get("id", ""))
				if id != "" and ids.has(id): continue
				var polygons: Array = Painter.drawn_mass_polygons(rec) if kind == "decor" else [Painter.drawn_special_polygon(rec)]
				var centroid := Vector2.ZERO; var count := 0
				for poly in polygons:
					if poly.size() < 3: continue
					var bb := Rect2(poly[0],Vector2.ZERO)
					for p in poly: centroid += p; count += 1; bb = bb.expand(p)
					obstacles.append({"poly":poly,"bb":bb,"kind":kind,"protected":str(rec.get("port_role", "")) != ""})
				if count == 0: continue
				ids[id] = true
				var tid := Index.tile_at(tile_index,centers,centroid/float(count))
				if counts.has(tid): counts[tid] += 1
	return {"counts":counts,"obstacles":obstacles}

static func apply(model: Dictionary, terrain: Node, water: Callable = Callable(), height: Callable = Callable(), preview_depots: bool = false) -> void:
	var centers := {}; var tiles := {}
	for tile in terrain.get("tiles").values():
		var tid := str(tile.id); var kind := str(Catalog.tile_type(tid))
		if kind in ["sea","deep_sea",""]: continue
		centers[tid] = Model.tile_center(terrain,tid)
		var neighbours: Array = Catalog.tile_neighbours(tid)
		tiles[tid] = {"center":centers[tid],"type":kind,"neighbours":neighbours}
	var authored := authored_buildings(centers,Authored.settlements())
	# Live port parcels include their access yards, beyond the decorative quay.
	# Preserve these while making room for the city depot.
	var tree := Engine.get_main_loop() as SceneTree
	var footprints := tree.get_first_node_in_group("building_footprints") if tree != null else null
	if footprints != null:
		for lot in footprints.get("_placements"):
			if str(lot.get("building_id", "")) != "b_004": continue
			var poly: PackedVector2Array = lot.verts
			if poly.size() < 3: continue
			var bounds := Rect2(poly[0], Vector2.ZERO)
			for p in poly: bounds = bounds.expand(p)
			authored.obstacles.append({"poly":poly,"bb":bounds,"protected":true})
	var saved_depots: Array = preload("res://scripts/rail_hub.gd").sites()
	for depot in saved_depots:
		for rect in [Rect2(40,-43,75,71),Rect2(Depot.CRANE_X-8,Depot.SIDING_CENTER-13,16,26)]:
			var poly := PackedVector2Array()
			for p in [rect.position,rect.position+Vector2(rect.size.x,0),rect.end,rect.position+Vector2(0,rect.size.y)]: poly.append(Depot.world(depot,p))
			var bounds := Rect2(poly[0],Vector2.ZERO)
			for p in poly: bounds=bounds.expand(p)
			authored.obstacles.append({"poly":poly,"bb":bounds,"protected":true})
	for tid in tiles: tiles[tid].buildings = authored.counts[tid]
	var seed: int = MatchState.match_rng_seed
	var river_segments := river_polylines(terrain)
	var key := hash([tiles,authored.obstacles,seed,VERSION,river_segments.size()])
	var land_index := Index.tiles(centers)
	var water_at := func(p: Vector2) -> bool:
		var tid := Index.tile_at(land_index,centers,p)
		return tid == "" or (water.is_valid() and water.call(tid,p))
	var store := Cache.new()
	var persistent_key := "rail-layout-"+Cache.digest([Cache.source_key("scenery"),Cache.source_key("roads"),Cache.source_key("terrain"),
		tiles,authored.obstacles,seed,VERSION,river_segments,Authored.active_name(),FileAccess.get_md5(Authored.path_for(Authored.active_name())),
		FileAccess.get_md5("res://data/roads_baked.json"),FileAccess.get_md5("res://data/hills_baked.json")])
	var changed := false
	if _cache.get("key") != key:
		_cache = store.read(persistent_key)
		if _cache.is_empty():
			cache_misses+=1
			_cache = create(tiles,authored.obstacles,seed,water_at,river_segments); _cache.depots = []; changed=true
		else: cache_hits+=1
		_cache.key = key
	if preview_depots and _cache.depots.is_empty():
		var traffic: Array = []
		var flags := {}
		for tile in terrain.get("tiles").values():
			if "roads" in tile.get("infrastructure_present",[]): flags[str(tile.id)]=true
		for path in preload("res://scripts/supply_chain_3d/authored_region.gd").source_paths(terrain,flags):
			for i in range(1,path.points.size()): traffic.append({"a":path.points[i-1],"b":path.points[i]})
		for corridor in Rail.network(_cache.lines).corridors:
			for i in range(1,corridor.points.size()): traffic.append({"a":corridor.points[i-1],"b":corridor.points[i]})
		_cache.depots = Depot.place(tiles,_cache.anchors,authored.obstacles,water_at,height,traffic)
		changed=true
	if changed: store.write(persistent_key,_cache)
	# Keep records available to the offline packager even if terrain generation
	# evicts their runtime files from the bounded disk cache.
	prepared_keys[persistent_key]=_cache

	# Generate globally first, then select visible tiles; company/continent views
	# must share exactly the same network and stochastic dropout decisions.
	var depots: Array = _cache.depots if preview_depots else saved_depots
	var source_lines: Array = _cache.lines.duplicate()
	for depot in depots:
		if _cache.anchors.has(depot.tile): source_lines.append_array(Depot.lines(depot, _cache.anchors[depot.tile], _cache.lines))
	var selected: Array = []
	for source in source_lines:
		var a_visible: bool = model.tiles.has(source.a)
		var b_visible: bool = model.tiles.has(source.b)
		if not a_visible and not b_visible: continue
		var line: Dictionary = source.duplicate()
		if line.get("kind","")!="depot": line.level = clampi(maxi(Catalog.tile_infra_level(line.a,"rails"),Catalog.tile_infra_level(line.b,"rails")),1,3)
		if a_visible and b_visible:
			selected.append(line); continue
		# Company view ends at its visible tile boundary, rather than drawing
		# unsupported track across the empty space around the company diorama.
		var tid: String = line.a if a_visible else line.b
		var points := PackedVector2Array()
		for point in line.pts: points.append(point.p)
		for part in Geometry2D.intersect_polyline_with_polygon(points,Model.hex_points(centers[tid])):
			if part.size()<2: continue
			var clipped: Dictionary = line.duplicate(); clipped.pts = []
			for point in part: clipped.pts.append({"p":point,"tile":tid,"edge":false})
			selected.append(clipped)
	var lines: Array = model.get("lines",[]).filter(func(line: Dictionary) -> bool: return not Rail.is_rail(str(line.get("mode",""))))
	lines.append_array(selected); model.lines = lines
	model.depots = depots.filter(func(d): return model.tiles.has(d.tile))
	if model.has("standing"):
		model.standing = model.standing.filter(func(s: Dictionary) -> bool:
			if str(s.get("internal_name", "")) == "rail_hub": return false
			if str(s.get("kind", "")) != "house": return true
			for depot in model.depots:
				var poly := Depot.yard_polygon(depot)
				if Geometry2D.is_point_in_polygon(s.pos, poly): return false
				var footprint: PackedVector2Array = s.get("footprint", PackedVector2Array())
				if footprint.size() >= 3 and not Geometry2D.intersect_polygons(footprint, poly).is_empty(): return false
			return true)
	model.rail_network = {"seed":seed,"version":VERSION,"tiles":tiles,"edges":_cache.edges,"drops":_cache.drops,
		"components":_cache.components,"anchors":_cache.anchors,"visible_edges":selected.size(),"global_edges":_cache.edges.size(),"protected_bridges":_cache.protected_bridges}

## Every river as segments in map space, from the map's RiverVisuals.
static func river_polylines(terrain: Node) -> Array:
	var result: Array = []
	var rv: Node = terrain.get_parent().get_node_or_null("RiverVisuals") if terrain != null and terrain.get_parent() != null else null
	if rv == null and Engine.get_main_loop() is SceneTree: rv = (Engine.get_main_loop() as SceneTree).get_first_node_in_group("river_visuals")
	if rv == null or not rv.has_method("get_river_polylines"): return result
	for rec in rv.call("get_river_polylines"):
		var points: PackedVector2Array = rec.points
		for i in range(1, points.size()): result.append({"a": points[i - 1], "b": points[i]})
	return result

## How many times a polyline crosses a river (crossings within 6u of each other count once:
## river records meet end to end at tile borders).
static func river_crossings(points: PackedVector2Array, rivers: Array, river_index: Dictionary) -> int:
	var hits: Array = []
	for j in range(1, points.size()):
		for i in Index.query(river_index, Index.bounds(points[j - 1], points[j], 0.01)):
			var hit: Variant = Geometry2D.segment_intersects_segment(points[j - 1], points[j], rivers[i].a, rivers[i].b)
			if hit == null: continue
			if hits.any(func(q): return (q as Vector2).distance_to(hit) < 6.0): continue
			hits.append(hit)
	return hits.size()

static func create(tiles: Dictionary, obstacles: Array, seed: int, water: Callable = Callable(), rivers: Array = []) -> Dictionary:
	var plan := topology(tiles,seed)
	var obstacle_index := {}
	for i in obstacles.size(): Index.insert(obstacle_index,obstacles[i].bb.grow(16),i)
	var anchors := {}
	var river_index := Index.segments(rivers, 0.01)
	var order := tiles.keys(); order.sort()
	for tid in order:
		var center: Vector2 = tiles[tid].center
		var best := center; var score := INF
		for i in 33:
			var angle := TAU * float((i+RoadHash.pick(tid,16))%16)/16.0
			var p := center if i == 0 else center + Vector2.RIGHT.rotated(angle)*(65.0 if i<=16 else 130.0)
			var cost := point_cost(p,obstacles,obstacle_index,water) + p.distance_to(center)*0.05
			cost += maxf(0.0, ANCHOR_RIVER_CLEARANCE-river_gap(p,rivers,river_index))*400.0
			if cost < score: best = p; score = cost
		if ANCHOR_OFFSETS.has(tid): best = center + ANCHOR_OFFSETS[tid]
		anchors[tid] = best
	var lines: Array = []
	for edge in plan.edges:
		var a: Vector2 = anchors[edge.a]; var b: Vector2 = anchors[edge.b]
		var axis := (b-a).normalized(); var side := axis.orthogonal()
		var jitter := float(RoadHash.pick("rail-curve:%d:%s" % [seed,edge_id(edge.a,edge.b)],101)-50)
		var best := PackedVector2Array(); var score := INF; var best_crossings := 0
		if LINE_VIAS.has(edge_id(edge.a,edge.b)):
			var vias: Array = LINE_VIAS[edge_id(edge.a,edge.b)].duplicate()
			if edge.a > edge.b: vias.reverse()
			best.append(a)
			for via in vias: best.append(via)
			best.append(b)
		var bends: Array = [[jitter,jitter],[-jitter,-jitter],[0.0,0.0],[75.0,75.0],[-75.0,-75.0],[125.0,125.0],[-125.0,-125.0]]
		var tried := 0 if best.is_empty() else bends.size()
		while tried < bends.size():
			var bend: Array = bends[tried]; tried += 1
			var p := PackedVector2Array([a,a.lerp(b,0.33)+side*float(bend[0]),a.lerp(b,0.67)+side*float(bend[1]),b])
			var cost := (absf(float(bend[0])-jitter)+absf(float(bend[1])-jitter))*0.025
			for j in range(1,p.size()):
				var n := maxi(2,ceili(p[j-1].distance_to(p[j])/10))
				for k in range(n+1): cost += point_cost(p[j-1].lerp(p[j],float(k)/n),obstacles,obstacle_index,water)
			var crossings := river_crossings(p, rivers, river_index)
			cost += RIVER_CROSSING_COST*crossings
			if cost < score: best = p; score = cost; best_crossings = crossings
			# A line still crossing a river more than once also tries gentle S-curves, the two
			# control points bending independently. Sharper ones loop when the curve is filleted.
			if tried == 7 and best_crossings > 1:
				for first in [0.0, 75.0, -75.0, 125.0, -125.0]:
					for second in [0.0, 75.0, -75.0, 125.0, -125.0]:
						if first != second and absf(first - second) <= 125.0: bends.append([first, second])
		var points: Array = []
		for i in best.size(): points.append({"p":best[i],"tile":edge.a if i<best.size()/2 else edge.b,"edge":false})
		lines.append({"mode":"rails","kind":"network","a":edge.a,"b":edge.b,"level":2,"pts":points})
	plan.lines = lines; plan.anchors = anchors
	return plan

static func river_gap(p: Vector2, rivers: Array, river_index: Dictionary) -> float:
	var gap := INF
	for i in Index.query(river_index, Rect2(p, Vector2.ZERO).grow(ANCHOR_RIVER_CLEARANCE)):
		gap = minf(gap, p.distance_to(Geometry2D.get_closest_point_to_segment(p, rivers[i].a, rivers[i].b)))
	return gap

static func point_cost(p: Vector2, obstacles: Array, index: Dictionary, water: Callable) -> float:
	var score := 100000.0 if water.is_valid() and water.call(p) else 0.0
	for i in Index.query(index,Rect2(p,Vector2.ZERO).grow(12)):
		var poly: PackedVector2Array = obstacles[i].poly
		if Geometry2D.is_point_in_polygon(p,poly): score += 10000; continue
		for j in poly.size():
			var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p,poly[j],poly[(j+1)%poly.size()]))
			if d<12: score += (12-d)*20
	return score
