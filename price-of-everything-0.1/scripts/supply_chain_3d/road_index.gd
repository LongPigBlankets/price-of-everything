extends RefCounted
## Deterministic spatial queries for offline road topology and live local fitting.
const CELL := 64.0
const TILE_CELL := 512.0
const JOIN_DISTANCE := 3.0
const EPSILON := 0.01
const RoadStyle := preload("res://scripts/authored_road_style.gd")

static func path_half(path: Dictionary) -> float:
	return float(path.widths[0]) if path.has("widths") else RoadStyle.casing_width(str(path.get("class","mid")))*0.5

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

## Cluster endpoints around a fixed original anchor, then attach loose ends to
## interiors. Tolerances refer to the visible gap and retain layer/grade checks.
static func join(paths: Array, ground: Callable = Callable()) -> int:
	var ends: Array = []
	var index := {}
	var endpoint_reach := JOIN_DISTANCE
	for path in paths: endpoint_reach=maxf(endpoint_reach,JOIN_DISTANCE+path_half(path)*2)
	for p in paths.size():
		for end in [0, paths[p].points.size() - 1]:
			var position: Vector2 = paths[p].points[end]
			insert(index, Rect2(position, Vector2.ZERO).grow(endpoint_reach), ends.size())
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
			if gap>JOIN_DISTANCE:
				# Nearly collinear ends can overlap their rounded caps without
				# sharing a graph node. Join these before independent bridge
				# grading turns an apparent continuous road into two elevations.
				var ap: PackedVector2Array=paths[a.path].points; var bp: PackedVector2Array=paths[b.path].points
				var da: Vector2=(a.point-ap[1 if a.end==0 else a.end-1]).normalized()
				var db: Vector2=(b.point-bp[1 if b.end==0 else b.end-1]).normalized()
				var delta: Vector2=b.point-a.point
				if gap>JOIN_DISTANCE+path_half(paths[a.path])+path_half(paths[b.path]): continue
				if da.dot(db)>-0.8 or maxf(absf(da.cross(delta)),absf(db.cross(delta)))>JOIN_DISTANCE: continue
			if not safe_join(a.point, b.point, ground): continue
			paths[b.path].points[b.end] = a.point
			ends[j].anchor = i
			connected[i] = true; connected[j] = true
			if gap > 0.001: count += 1
	var pieces: Array = []
	for p in paths.size():
		for i in range(1, paths[p].points.size()):
			pieces.append({"path": p, "segment": i, "a": paths[p].points[i - 1], "b": paths[p].points[i], "cuts": []})
	var reach := JOIN_DISTANCE
	for path in paths: reach=maxf(reach,JOIN_DISTANCE+path_half(path)*2)
	index = segments(pieces, reach)
	for e in ends.size():
		if connected.has(e): continue
		var endpoint: Dictionary = ends[e]
		var path: Dictionary = paths[endpoint.path]
		var p: Vector2 = path.points[endpoint.end]
		var adjacent: int = 1 if endpoint.end == 0 else endpoint.end - 1
		var tangent: Vector2 = (p - path.points[adjacent]).normalized()
		var best := INF
		var chosen := -1
		var snap := p
		for j in index.get(Vector2i((p / CELL).floor()), []):
			var other: Dictionary = pieces[j]
			if other.path == endpoint.path or paths[other.path].get("layer", 0) != path.get("layer", 0): continue
			var q := Geometry2D.get_closest_point_to_segment(p, other.a, other.b)
			var gap := p.distance_to(q)
			if gap >= best: continue
			# Ends facing another road can be only 2–3u from its visible edge
			# while their centrelines are much farther apart. Join through both
			# casings, then split the receiver so grading sees a real T junction.
			var limit := JOIN_DISTANCE
			if gap>0.05 and tangent.dot((q-p).normalized())>0.5:
				limit+=path_half(path)+path_half(paths[other.path])
			if gap>limit: continue
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
		if rebuilt[piece.path][-1].distance_to(source[piece.segment]) > EPSILON:
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
			# Shared endpoints are already a junction. Intersecting nearly collinear
			# neighbours at large map coordinates can fabricate millimetre-long
			# reverse segments through float32 cancellation.
			if (a.a as Vector2).distance_to(b.a) < EPSILON or (a.a as Vector2).distance_to(b.b) < EPSILON \
				or (a.b as Vector2).distance_to(b.a) < EPSILON or (a.b as Vector2).distance_to(b.b) < EPSILON: continue
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

## Arc distances survive intersection splitting, so trimming changes the paths
## used by bridges and terrain profiles as well as the rendered road segments.
static func path_segments(paths: Array) -> Array:
	var parts: Array = []
	for p in paths.size():
		var distance := 0.0
		for i in range(1, paths[p].points.size()):
			var a: Vector2 = paths[p].points[i - 1]
			var b: Vector2 = paths[p].points[i]
			if a.distance_to(b) > EPSILON:
				parts.append({"a": a, "b": b, "origin": a, "offset": distance, "path": p,
					"source": paths[p].id, "layer": paths[p].get("layer", 0)})
			distance += a.distance_to(b)
	return parts

static func _graph_node(point: Vector2, layer: int, nodes: Array, index: Dictionary) -> int:
	var cell := Vector2i((point / EPSILON).floor())
	for y in range(cell.y - 1, cell.y + 2):
		for x in range(cell.x - 1, cell.x + 2):
			for id in index.get(Vector3i(x, y, layer), []):
				if point.distance_to(nodes[id].point) < EPSILON: return id
	var id := nodes.size()
	(index.get_or_add(Vector3i(cell.x, cell.y, layer), []) as Array).append(id)
	nodes.append({"point": point, "edges": []})
	return id

## Only degree-one tails ending at a junction count as stubs. Measure the entire
## chain, not individual sampled/clipped segments. Access roads end at doors.
static func short_stubs(parts: Array) -> Array:
	var nodes: Array = []
	var index := {}
	var links: Array = []
	var unique := {}
	var aliases := {}
	for part in parts:
		var a := _graph_node(part.a, int(part.get("layer", 0)), nodes, index)
		var b := _graph_node(part.b, int(part.get("layer", 0)), nodes, index)
		var edge := links.size()
		links.append([a, b])
		if a == b: continue
		var key := Vector2i(mini(a, b), maxi(a, b))
		if unique.has(key):
			aliases[unique[key]].append(edge)
			continue
		unique[key] = edge
		aliases[edge] = [edge]
		nodes[a].edges.append(edge); nodes[b].edges.append(edge)
	var stubs: Array = []
	for start in nodes.size():
		if nodes[start].edges.size() != 1: continue
		var current := start
		var previous := -1
		var length := 0.0
		var edges: Array = []
		while true:
			var next: int = nodes[current].edges[0]
			if next == previous: next = nodes[current].edges[1]
			var entrance := false
			for edge in aliases[next]:
				entrance = entrance or str(parts[edge].source).begins_with("access:")
			if entrance: break
			length += (parts[next].a as Vector2).distance_to(parts[next].b)
			if length >= JOIN_DISTANCE: break
			edges.append_array(aliases[next])
			current = links[next][1] if links[next][0] == current else links[next][0]
			previous = next
			var degree: int = nodes[current].edges.size()
			if degree >= 3:
				stubs.append({"source": parts[edges[0]].source, "from": nodes[start].point,
					"to": nodes[current].point, "length": length, "edges": edges})
				break
			if degree != 2: break
	return stubs

static func trim_stubs(paths: Array) -> Array:
	var parts := split(path_segments(paths))
	var stubs := short_stubs(parts)
	if stubs.is_empty(): return []
	var removed := {}
	var changed := {}
	for stub in stubs:
		for edge in stub.edges:
			removed[edge] = true
			changed[parts[edge].path] = true
		stub.erase("edges")
	var retained := {}
	for i in parts.size():
		var part: Dictionary = parts[i]
		if removed.has(i) or not changed.has(part.path): continue
		var lo: float = part.offset + (part.a as Vector2).distance_to(part.origin)
		var hi: float = part.offset + (part.b as Vector2).distance_to(part.origin)
		var interval: Vector2 = retained.get(part.path, Vector2(INF, -INF))
		retained[part.path] = Vector2(minf(interval.x, lo), maxf(interval.y, hi))
	var result: Array = []
	for p in paths.size():
		if not changed.has(p): result.append(paths[p]); continue
		if not retained.has(p): continue
		var interval: Vector2 = retained[p]
		var clipped := PackedVector2Array()
		var distance := 0.0
		var points: PackedVector2Array = paths[p].points
		for i in range(1, points.size()):
			var length := points[i - 1].distance_to(points[i])
			if length > EPSILON and distance + length > interval.x and distance < interval.y:
				var a := points[i - 1].lerp(points[i], clampf((interval.x - distance) / length, 0.0, 1.0))
				var b := points[i - 1].lerp(points[i], clampf((interval.y - distance) / length, 0.0, 1.0))
				if clipped.is_empty(): clipped.append(a)
				if b.distance_to(clipped[-1]) > EPSILON: clipped.append(b)
			distance += length
		if clipped.size() < 2: continue
		paths[p].points = clipped
		result.append(paths[p])
	paths.assign(result)
	return stubs

## Read-only audit for tools: endpoints already meeting a road are not gaps.
## Close parallel approaches are reported, but are deliberately not welded.
static func audit(paths: Array, ground: Callable = Callable()) -> Dictionary:
	var parts := path_segments(paths)
	var index := segments(parts, JOIN_DISTANCE)
	var nearby: Array = []
	for p in paths.size():
		var points: PackedVector2Array = paths[p].points
		for end in [0, points.size() - 1]:
			var position := points[end]
			var best := INF
			var candidate := {}
			for i in index.get(Vector2i((position / CELL).floor()), []):
				var part: Dictionary = parts[i]
				if part.path == p or part.layer != paths[p].get("layer", 0): continue
				var nearest := Geometry2D.get_closest_point_to_segment(position, part.a, part.b)
				var distance := position.distance_to(nearest)
				if distance >= best: continue
				best = distance
				var adjacent: int = 1 if end == 0 else end - 1
				var tangent := (position - points[adjacent]).normalized()
				var reason := "joinable"
				if str(paths[p].id).begins_with("access:") and end == 0: reason = "building_entrance"
				elif not safe_join(position, nearest, ground): reason = "water_or_relief"
				elif distance > 0.05 and absf(tangent.dot((part.b - part.a).normalized())) > 0.97: reason = "parallel"
				candidate = {"source": paths[p].id, "target": part.source, "from": position, "to": nearest, "gap": distance, "reason": reason}
			if best > EPSILON and not candidate.is_empty(): nearby.append(candidate)
	var stubs := short_stubs(split(parts))
	for stub in stubs: stub.erase("edges")
	var parallel := {}
	for i in parts.size():
		var a: Dictionary = parts[i]
		var direction: Vector2 = (a.b - a.a).normalized()
		var length: float = (a.b - a.a).length()
		if length < 2.0 * JOIN_DISTANCE: continue
		for j in query(index, bounds(a.a, a.b, JOIN_DISTANCE)):
			var b: Dictionary = parts[j]
			if j <= i or a.path == b.path or a.layer != b.layer: continue
			if absf(direction.dot((b.b - b.a).normalized())) < 0.97: continue
			var lo: float = (b.a - a.a).dot(direction)
			var hi: float = (b.b - a.a).dot(direction)
			var overlap := minf(length, maxf(lo, hi)) - maxf(0.0, minf(lo, hi))
			if overlap < 2.0 * JOIN_DISTANCE: continue
			var pair := Geometry2D.get_closest_points_between_segments(a.a, a.b, b.a, b.b)
			var gap := pair[0].distance_to(pair[1])
			if gap <= EPSILON or gap > JOIN_DISTANCE: continue
			var key := Vector2i(mini(a.path, b.path), maxi(a.path, b.path))
			if parallel.has(key) and parallel[key].gap <= gap: continue
			parallel[key] = {"source": a.source, "target": b.source, "from": pair[0], "to": pair[1], "gap": gap}
	return {"near_endpoints_within_3u": nearby.size(), "near_endpoints": nearby, "stubs_under_3u": stubs.size(), "stubs": stubs,
		"close_parallel_pairs": parallel.size(), "parallel_pairs": parallel.values()}
