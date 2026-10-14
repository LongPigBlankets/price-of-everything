extends RefCounted
## One paint layout per continuous carriageway, independent of curve sampling or
## tile clipping. This changes only paint: authored road positions stay intact.
const Index := preload("res://scripts/supply_chain_3d/road_index.gd")
const Legacy := preload("res://scripts/empire_board.gd")
var _by_tile := {}
var suppressed_overlaps := 0
var duplicate_segments := 0

func configure(ways: Array) -> void:
	_by_tile.clear()
	suppressed_overlaps = 0; duplicate_segments = 0
	var ordered := ways.duplicate()
	ordered.sort_custom(_priority)
	var nodes: Array = []
	var node_index := {}
	var edges: Array = []
	var unique := {}
	for w in ordered:
		var a := Index._graph_node(w.a, int(w.get("layer", 0)), nodes, node_index)
		var b := Index._graph_node(w.b, int(w.get("layer", 0)), nodes, node_index)
		if a == b: continue
		var key := Vector2i(mini(a, b), maxi(a, b))
		if unique.has(key): duplicate_segments += 1; continue
		unique[key] = true
		for n in [a, b]: nodes[n].edges.append(edges.size())
		edges.append({"way": w, "a": a, "b": b})
	var visited := {}
	var pieces: Array = []
	for first in edges.size():
		if visited.has(first): continue
		# Find a chain end before walking forward. Closed loops use a stable seam.
		var start: int = edges[first].a
		var previous := first
		var walked := {}
		while _through(start, nodes, edges):
			var other := _other_edge(start, previous, nodes)
			if walked.has(other) or other == first: break
			walked[other] = true
			start = _other_node(edges[other], start)
			previous = other
		var chain: Array = []
		var at := start
		var edge := previous
		var distance := 0.0
		while not visited.has(edge):
			visited[edge] = true
			var next := _other_node(edges[edge], at)
			var a: Vector2 = nodes[at].point
			var b: Vector2 = nodes[next].point
			chain.append({"way": edges[edge].way, "a": a, "b": b, "offset": distance,
				"length": a.distance_to(b), "chain": first, "blocked": []})
			distance += a.distance_to(b)
			at = next
			if not _through(at, nodes, edges): break
			edge = _other_edge(at, edge, nodes)
		var closed := at == start
		if not closed and str(chain[-1].b) < str(chain[0].a):
			chain.reverse()
			for p in chain:
				var a: Vector2 = p.a
				p.a = p.b; p.b = a
				p.offset = distance - p.offset - p.length
			var end := at
			at = start; start = end
		var clear_start := 0.0 if closed else _clearance(start, nodes, edges)
		var clear_end := 0.0 if closed else _clearance(at, nodes, edges)
		for i in chain.size():
			var p: Dictionary = chain[i]
			var normal: Vector2 = (p.b - p.a).normalized().orthogonal()
			p.start_normal = normal; p.end_normal = normal
			if i > 0 or closed:
				var prev: Dictionary = chain[(i - 1 + chain.size()) % chain.size()]
				p.start_normal = _miter((prev.b - prev.a).normalized().orthogonal(), normal)
			if i + 1 < chain.size() or closed:
				var next: Dictionary = chain[(i + 1) % chain.size()]
				p.end_normal = _miter(normal, (next.b - next.a).normalized().orthogonal())
			p.from = maxf(0.0, clear_start - p.offset)
			p.to = minf(p.length, distance - clear_end - p.offset)
			pieces.append(p)
	# Duplicate/near-coincident parallel strokes share paint with the wider road.
	# Keep different elevation layers and genuinely separate carriageways apart.
	pieces.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _priority(a.way, b.way))
	var spatial := Index.segments(pieces, 3.0)
	for i in pieces.size():
		var p: Dictionary = pieces[i]
		if int(p.way.level) < 2: continue
		var direction: Vector2 = (p.b - p.a).normalized()
		for j in Index.query(spatial, Index.bounds(p.a, p.b, 3.0)):
			if j >= i: continue
			var q: Dictionary = pieces[j]
			if p.chain == q.chain or p.way.get("layer", 0) != q.way.get("layer", 0): continue
			var tangent: Vector2 = (q.b - q.a).normalized()
			if absf(direction.dot(tangent)) < 0.985: continue
			var lo := maxf(0.0, minf((q.a - p.a).dot(direction), (q.b - p.a).dot(direction)))
			var hi := minf(p.length, maxf((q.a - p.a).dot(direction), (q.b - p.a).dot(direction)))
			if hi - lo < 0.01: continue
			var reach := minf(3.0, minf(p.way.widths[3], q.way.widths[3]))
			var separation: float = (p.a - q.a).cross(tangent)
			var slope := direction.cross(tangent)
			if absf(slope) < 0.00001:
				if absf(separation) > reach: continue
			else:
				# A shallow crossing may be close only at its middle, not along
				# the whole pair of segments. Solve its actual overlap interval.
				var t0 := (-reach - separation) / slope
				var t1 := (reach - separation) / slope
				lo = maxf(lo, minf(t0, t1)); hi = minf(hi, maxf(t0, t1))
			if hi - lo < 0.01: continue
			p.blocked.append(Vector2(lo, hi))
			suppressed_overlaps += 1
		(_by_tile.get_or_add(str(p.way.tile), []) as Array).append(p)

static func _priority(a: Dictionary, b: Dictionary) -> bool:
	if a.widths[3] != b.widths[3]: return a.widths[3] > b.widths[3]
	if a.level != b.level: return a.level > b.level
	# Canonical ordering also covers roads without authored source IDs.
	return str([a.get("source", ""), a.a, a.b, a.tile]) < str([b.get("source", ""), b.a, b.b, b.tile])

static func _other_node(edge: Dictionary, node: int) -> int:
	return int(edge.b) if edge.a == node else int(edge.a)

static func _other_edge(node: int, previous: int, nodes: Array) -> int:
	return int(nodes[node].edges[1]) if nodes[node].edges[0] == previous else int(nodes[node].edges[0])

static func _through(node: int, nodes: Array, edges: Array) -> bool:
	if nodes[node].edges.size() != 2: return false
	var a: Dictionary = edges[nodes[node].edges[0]]
	var b: Dictionary = edges[nodes[node].edges[1]]
	if a.way.level != b.way.level or a.way.paved != b.way.paved or a.way.widths != b.way.widths: return false
	var point: Vector2 = nodes[node].point
	var da: Vector2 = (nodes[_other_node(a, node)].point - point).normalized()
	var db: Vector2 = (nodes[_other_node(b, node)].point - point).normalized()
	return da.dot(db) < 0.5

static func _clearance(node: int, nodes: Array, edges: Array) -> float:
	var reach := 0.0
	for edge in nodes[node].edges: reach = maxf(reach, edges[edge].way.widths[0])
	return reach + 2.0

static func _miter(a: Vector2, b: Vector2) -> Vector2:
	var bisector := (a + b).normalized()
	return bisector / maxf(0.5, bisector.dot(b))

static func lane_lines(level: int, half_width: float) -> Array:
	if level == 2: return [[0.0, true]]
	if level < 3: return []
	# Three lanes in each direction, separated by a double centre line.
	return [[-0.55, false], [0.55, false], [-half_width / 3.0, true], [half_width / 3.0, true],
		[-half_width * 2.0 / 3.0, true], [half_width * 2.0 / 3.0, true]]

func polygons_for(tile: String) -> Array:
	var result: Array = []
	var period: float = Legacy._ROAD_DASH + Legacy._ROAD_DASH_GAP
	for p in _by_tile.get(tile, []):
		var spans: Array = [Vector2(p.from, p.to)] if p.to > p.from else []
		for cut in p.blocked:
			var remaining: Array = []
			for span in spans:
				if cut.y <= span.x or cut.x >= span.y: remaining.append(span); continue
				if cut.x > span.x: remaining.append(Vector2(span.x, cut.x))
				if cut.y < span.y: remaining.append(Vector2(cut.y, span.y))
			spans = remaining
		var tint: Color = Color.WHITE if bool(p.way.paved) else Legacy._UNPAVED
		for line in lane_lines(int(p.way.level), float(p.way.widths[3])):
			for span in spans:
				if not line[1]:
					result.append({"points": _stripe(p, span.x, span.y, line[0]), "colour": Legacy._ROAD_MARK * tint})
					continue
				var at := floorf((p.offset + span.x) / period) * period - float(p.offset)
				while at < span.y:
					var from := maxf(span.x, at)
					var to := minf(span.y, at + Legacy._ROAD_DASH)
					if to - from > 0.01:
						result.append({"points": _stripe(p, from, to, line[0]), "colour": Legacy._ROAD_MARK * tint})
					at += period
	return result

static func _stripe(p: Dictionary, from: float, to: float, lateral: float) -> PackedVector2Array:
	var a: Vector2 = p.a.lerp(p.b, from / p.length)
	var b: Vector2 = p.a.lerp(p.b, to / p.length)
	var na: Vector2 = p.start_normal.lerp(p.end_normal, from / p.length)
	var nb: Vector2 = p.start_normal.lerp(p.end_normal, to / p.length)
	var half: float = 0.18 if p.way.get("district_street",false) else Legacy._ROAD_MARK_W
	return PackedVector2Array([a + na * (lateral + half), b + nb * (lateral + half),
		b + nb * (lateral - half), a + na * (lateral - half)])
