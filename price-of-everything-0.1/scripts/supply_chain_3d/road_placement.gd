extends RefCounted
## Presentation-only frontage fitting. One layout is shared by all three LODs.
const Index := preload("res://scripts/supply_chain_3d/road_index.gd")
const Region := preload("res://scripts/supply_chain_3d/authored_region.gd")
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const Cache := preload("res://scripts/supply_chain_3d/bake_cache.gd")
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
	var inputs: Array = []
	for s in model.standing:
		inputs.append([s.iid, s.kind, s.tile, s.pos, s.side, s.get("yaw", 0.0), s.get("footprint", []),
			s.get("harbour", {}), Assets.dimensions(str(asset_key.call(s)))])
	var key := Cache.digest([Cache.source_key("roads"), Cache.source_key("terrain"), model.roads, inputs, river_lines])
	var variants: Dictionary = prepared.get_or_add("frontages", {})
	var cached: Dictionary = variants.get(key, {})
	if not cached.is_empty():
		var retained: Array = []
		for s in model.standing:
			if not cached.placements.has(str(s.iid)): continue
			s.merge(cached.placements[str(s.iid)], true)
			retained.append(s)
		model.standing = retained
		model.roads = cached.roads
		model.authored_region.paths = model.authored_region.paths.duplicate()
		model.authored_region.paths.append_array(cached.paths)
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
	var movable: Array = []
	for s in model.standing:
		if s.has("harbour"):
			reserve(str(s.iid), s.harbour.main_quay)
			for poly in s.harbour.quays: reserve(str(s.iid), poly)
		elif str(s.kind) in ["house", "warehouse", "suppliers"]: movable.append(s)
		elif str(s.kind) != "pylon": reserve(str(s.iid), footprint(s))
	movable.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if (a.kind == "house") != (b.kind == "house"): return b.kind == "house"
		return str(a.iid) < str(b.iid))
	var omitted := 0
	var restored := 0
	for s in movable:
		if not model.authored_region.tiles.has(str(s.tile)): continue
		var placed := frontage(s, model.tiles[s.tile].center)
		if not placed and str(s.kind) == "house":
			model.standing.erase(s); omitted += 1; continue
		s.footprint = footprint(s)
		reserve(str(s.iid), s.footprint)
		if str(s.kind) == "house": restored += 1
	var connections: Array = []
	var access_paths: Array = []
	var unconnected: Array = []
	for s in model.standing:
		if str(s.kind) == "pylon" or not model.authored_region.tiles.has(str(s.tile)): continue
		var entry := entrance(s)
		if entry.is_empty():
			if str(s.kind) != "house": unconnected.append(str(s.iid))
			continue
		s.entrance = entry[0]
		if entry[0].distance_to(entry[1]) > 0.05:
			connections.append({"id": "access:" + str(s.iid), "points": entry, "class": "minor", "layer": 0})
	if not connections.is_empty():
		var compiled := Region.compile(connections, model.authored_region.tiles)
		access_paths = compiled.paths
		model.roads.append_array(compiled.roads)
		model.roads = Index.split(model.roads)
		model.authored_region.paths = model.authored_region.paths.duplicate()
		model.authored_region.paths.append_array(compiled.paths)
	model.authored_region.frontage = {"decorative": restored, "omitted": omitted, "access_roads": connections.size(), "unconnected": unconnected}
	var placements := {}
	for s in model.standing:
		var placement := {"pos": s.pos, "side": s.side, "yaw": s.get("yaw", 0.0)}
		if s.has("entrance"): placement.entrance = s.entrance
		if s.has("footprint"): placement.footprint = s.footprint
		placements[str(s.iid)] = placement
	# Company-only and full-continent openings must not evict one another.
	while variants.size() >= 4: variants.erase(variants.keys()[0])
	variants[key] = {"placements": placements, "roads": model.roads, "paths": access_paths, "metrics": model.authored_region.frontage}

func reserve(iid: String, polygon: PackedVector2Array) -> void:
	if polygon.is_empty(): return
	var box := polygon_bounds(polygon)
	Index.insert(lot_index, box.grow(4.0), lots.size())
	lots.append({"iid": iid, "polygon": polygon, "box": box})

func footprint(s: Dictionary) -> PackedVector2Array:
	if s.has("footprint"): return s.footprint
	var dim := Assets.dimensions(str(asset_key.call(s))) * float(s.side)
	var half := Vector2(maxf(dim.x, 8.0), maxf(dim.z, 8.0)) * 0.5
	var poly := PackedVector2Array()
	for p in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)]:
		poly.append(s.pos + p.rotated(-float(s.get("yaw", 0.0))))
	return poly

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

func clear_plot(poly: PackedVector2Array, center: Vector2, iid: String) -> bool:
	var low := INF
	var high := -INF
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		if not clear_lots(a, b, 4.0, iid): return false
		for t in [0.0, 0.5]:
			var p := a.lerp(b, t)
			if not Index.contains(center, p) or wet(p): return false
			var height := float(ground.call(p))
			low = minf(low, height); high = maxf(high, height)
	if high - low > 12.0: return false
	for i in Index.query(road_index, polygon_bounds(poly).grow(20.0)):
		var road: Dictionary = roads[i]
		var half := float(road.get("widths", [5.0])[0])
		if distance_to_polygon(road.a, road.b, poly) < half + 4.0: return false
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
	var original: Vector2 = s.pos
	var side := float(s.side)
	var yaw := float(s.get("yaw", 0.0))
	var options := candidates(original)
	for scale in [1.0, 0.8]:
		s.side = side * scale
		var dim := Assets.dimensions(str(asset_key.call(s))) * float(s.side)
		for option in options:
			var tangent: Vector2 = (option.road.b - option.road.a).normalized()
			var normal := tangent.orthogonal()
			var half := float(option.road.get("widths", [5.0])[0])
			for direction in [1.0, -1.0]:
				for along in [0.0, -0.65, 0.65]:
					s.pos = option.point + normal * direction * (dim.z * 0.5 + half + 7.0) + tangent * dim.x * along
					s.yaw = -tangent.angle()
					if clear_plot(footprint(s), center, str(s.iid)): return true
		s.side = side
		if str(s.kind) != "house": break
	s.pos = original; s.side = side; s.yaw = yaw
	return false

func entrance(s: Dictionary) -> PackedVector2Array:
	var center: Vector2 = s.pos
	var poly := footprint(s) if not s.has("harbour") else s.harbour.main_quay as PackedVector2Array
	if s.has("harbour"):
		center = Vector2.ZERO
		for p in poly: center += p
		center /= poly.size()
	for option in candidates(center):
		var q: Vector2 = option.point
		if Geometry2D.is_point_in_polygon(q, poly): continue
		var door := center
		for i in poly.size():
			var hit: Variant = Geometry2D.segment_intersects_segment(center, q, poly[i], poly[(i + 1) % poly.size()])
			if hit != null: door = hit
		if not clear_lots(door, q, 4.0, str(s.iid)): continue
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
