extends RefCounted
## Deterministic spatial queries for offline road topology and live local fitting.
const CELL := 64.0
const TILE_CELL := 512.0

static func insert(index: Dictionary, area: Rect2, id: Variant, size: float = CELL) -> void:
	var lo := Vector2i((area.position / size).floor())
	var hi := Vector2i((area.end / size).floor())
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1): (index.get_or_add(Vector2i(x, y), []) as Array).append(id)

static func query(index: Dictionary, area: Rect2, size: float = CELL) -> Array:
	var found := {}
	var lo := Vector2i((area.position / size).floor())
	var hi := Vector2i((area.end / size).floor())
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			for id in index.get(Vector2i(x, y), []): found[id] = true
	var ids := found.keys()
	ids.sort()
	return ids

static func bounds(a: Vector2, b: Vector2, margin: float = 0.0) -> Rect2:
	return Rect2(a, Vector2.ZERO).expand(b).grow(margin)

static func tiles(centers: Dictionary) -> Dictionary:
	var index := {}
	for tid in centers: insert(index, Rect2(centers[tid] - Vector2(270, 240), Vector2(540, 480)), tid, TILE_CELL)
	return index

static func contains(center: Vector2, p: Vector2) -> bool:
	var d := (p - center).abs()
	return d.y <= 240.001 and d.x <= 270.001 - d.y * 0.5625

static func tile_at(index: Dictionary, centers: Dictionary, p: Vector2) -> String:
	for tid in index.get(Vector2i((p / TILE_CELL).floor()), []):
		if contains(centers[tid], p): return str(tid)
	return ""

static func segments(roads: Array, margin: float = 0.0) -> Dictionary:
	var index := {}
	for i in roads.size(): insert(index, bounds(roads[i].a, roads[i].b, margin), i)
	return index

static func safe_join(a: Vector2, b: Vector2, ground: Callable) -> bool:
	if a.distance_to(b) < 0.001 or not ground.is_valid(): return true
	if absf(float(ground.call(a)) - float(ground.call(b))) > 4.0: return false
	for t in [0.0, 0.5, 1.0]:
		if float(ground.call(a.lerp(b, t))) <= 25.5: return false
	return true

## Cluster endpoints around a fixed original anchor (never a transitive chain
## which can move an endpoint more than 2u), then attach loose ends to interiors.
static func join(paths: Array, ground: Callable = Callable()) -> int:
	var ends: Array = []
	var index := {}
	for p in paths.size():
		for end in [0, paths[p].points.size() - 1]:
			var position: Vector2 = paths[p].points[end]
			insert(index, Rect2(position, Vector2.ZERO).grow(2.0), ends.size())
			ends.append({"path": p, "end": end, "point": position, "anchor": -1})
	var count := 0
	var connected := {}
	for i in ends.size():
		if ends[i].anchor >= 0: continue
		ends[i].anchor = i
		var a: Dictionary = ends[i]
		for j in index.get(Vector2i(((a.point as Vector2) / CELL).floor()), []):
			if j == i or ends[j].anchor >= 0: continue
			var b: Dictionary = ends[j]
			if a.path == b.path or paths[a.path].get("layer", 0) != paths[b.path].get("layer", 0): continue
			var gap: float = a.point.distance_to(b.point)
			if gap > 2.0 or not safe_join(a.point, b.point, ground): continue
			paths[b.path].points[b.end] = a.point
			ends[j].anchor = i
			connected[i] = true; connected[j] = true
			if gap > 0.001: count += 1
	var pieces: Array = []
	for p in paths.size():
		for i in range(1, paths[p].points.size()):
			pieces.append({"path": p, "segment": i, "a": paths[p].points[i - 1], "b": paths[p].points[i], "cuts": []})
	index = segments(pieces, 2.0)
	for e in ends.size():
		if connected.has(e): continue
		var endpoint: Dictionary = ends[e]
		var path: Dictionary = paths[endpoint.path]
		var p: Vector2 = path.points[endpoint.end]
		var adjacent: int = 1 if endpoint.end == 0 else endpoint.end - 1
		var tangent: Vector2 = (p - path.points[adjacent]).normalized()
		var best := 2.0001
		var chosen := -1
		var snap := p
		for j in index.get(Vector2i((p / CELL).floor()), []):
			var other: Dictionary = pieces[j]
			if other.path == endpoint.path or paths[other.path].get("layer", 0) != path.get("layer", 0): continue
			var q := Geometry2D.get_closest_point_to_segment(p, other.a, other.b)
			var gap := p.distance_to(q)
			if gap >= best or q.distance_to(other.a) < 0.01 or q.distance_to(other.b) < 0.01: continue
			if gap > 0.05 and absf(tangent.dot((other.b - other.a).normalized())) > 0.97: continue
			if not safe_join(p, q, ground): continue
			best = gap; chosen = j; snap = q
		if chosen < 0: continue
		paths[endpoint.path].points[endpoint.end] = snap
		pieces[chosen].cuts.append(snap)
		if best > 0.001: count += 1
	var rebuilt := {}
	for piece in pieces:
		var source: PackedVector2Array = paths[piece.path].points
		if not rebuilt.has(piece.path): rebuilt[piece.path] = PackedVector2Array([source[0]])
		piece.cuts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_squared_to(piece.a) < b.distance_squared_to(piece.a))
		for point in piece.cuts:
			if rebuilt[piece.path][-1].distance_to(point) > 0.01: rebuilt[piece.path].append(point)
		rebuilt[piece.path].append(source[piece.segment])
	for p in rebuilt: paths[p].points = rebuilt[p]
	return count

static func split(roads: Array) -> Array:
	var index := segments(roads, 0.01)
	var cuts: Array = []
	for road in roads: cuts.append([road.a, road.b])
	for i in roads.size():
		var a: Dictionary = roads[i]
		for j in query(index, bounds(a.a, a.b, 0.01)):
			if j <= i or roads[j].get("layer", 0) != a.get("layer", 0): continue
			var b: Dictionary = roads[j]
			var hit: Variant = Geometry2D.segment_intersects_segment(a.a, a.b, b.a, b.b)
			if hit == null: continue
			for k in [i, j]:
				var found := false
				for point in cuts[k]:
					if (point as Vector2).distance_to(hit) < 0.01: found = true; break
				if not found: cuts[k].append(hit)
	var result: Array = []
	for i in roads.size():
		var road: Dictionary = roads[i]
		cuts[i].sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_squared_to(road.a) < b.distance_squared_to(road.a))
		for j in range(1, cuts[i].size()):
			if (cuts[i][j - 1] as Vector2).distance_to(cuts[i][j]) < 0.01: continue
			var part := road.duplicate()
			part.a = cuts[i][j - 1]; part.b = cuts[i][j]
			result.append(part)
	return result
