extends RefCounted
## Offline world-space water geometry. Tile cuts never define a shoreline.
const PATH := "res://data/supply_chain_water.json"
const Index := preload("res://scripts/supply_chain_3d/road_index.gd")
static var _data := {}
static var _tiles := {}
static var _lakes: Array = []
static var _edges := {}
static var _shore_edges: Array = []
static var _shore_index := {}
static var _lake_index := {}

static func ring(flat: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in range(0, flat.size(), 2): result.append(Vector2(flat[i], flat[i+1]))
	return result

static func data() -> Dictionary:
	if _data.is_empty(): _data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return _data

static func lakes() -> Array:
	if _lakes.is_empty():
		for entry in data().lakes:
			var p := ring(entry.p)
			var box := Rect2(p[0], Vector2.ZERO)
			for q in p: box = box.expand(q)
			var bank: Array = []
			for mask in entry.bank_mask: bank.append(ring(mask))
			var shores: Array = []
			for shore in entry.shores: shores.append(ring(shore))
			for shore in shores:
				for i in shore.size():
					var a: Vector2 = shore[i]; var b: Vector2 = shore[(i+1)%shore.size()]
					Index.insert(_shore_index, Index.bounds(a, b, 1.01), _shore_edges.size())
					_shore_edges.append([a, b, float(entry.level)])
			var id := _lakes.size()
			Index.insert(_lake_index, box.grow(24.01), id, 256.0)
			_lakes.append({"p": p, "box": box, "level": float(entry.level), "plate": float(entry.plate),
				"banks": bank, "shores": shores, "rim": Geometry2D.offset_polygon(p, 1.0)})
			for i in p.size(): Index.insert(_edges, Index.bounds(p[i], p[(i+1)%p.size()], 1.1), id)
	return _lakes

static func lake_surface(p: Vector2) -> Vector2:
	lakes()
	var nearby: Array = _lake_index.get(Vector2i((p / 256.0).floor()), [])
	if nearby.is_empty(): return Vector2.ZERO
	for id in nearby:
		var lake: Dictionary = _lakes[id]
		if (lake.box as Rect2).grow(0.002).has_point(p) and Geometry2D.is_point_in_polygon(p, lake.p): return Vector2(lake.level, 1)
	var distance := 1.0
	for id in _shore_index.get(Vector2i((p / Index.CELL).floor()), []):
		var edge: Array = _shore_edges[id]
		distance = minf(distance, p.distance_to(Geometry2D.get_closest_point_to_segment(p, edge[0], edge[1])))
		# Godot's float32 vectors can round a boundary vertex outside its ring.
		# Keep those sub-millimetre slivers at water height rather than spiking.
		if distance <= 0.002: return Vector2(edge[2], 1)
	for id in nearby:
		var lake: Dictionary = _lakes[id]
		if not (lake.box as Rect2).grow(24).has_point(p): continue
		if not lake.banks.any(func(poly): return Geometry2D.is_point_in_polygon(p, poly)): continue
		return Vector2(lerpf(lake.level, lake.plate, clampf(distance, 0, 1)), 2)
	return Vector2.ZERO

static func partition(poly: PackedVector2Array) -> Array:
	lakes()
	var box := Rect2(poly[0], Vector2.ZERO)
	for p in poly: box = box.expand(p)
	var parts: Array = [poly]
	for id in Index.query(_edges, box):
		var lake: Dictionary = _lakes[id]
		for ring in [lake.p] + Array(lake.rim):
			var next: Array = []
			for part in parts:
				next.append_array(Geometry2D.intersect_polygons(part, ring))
				next.append_array(Geometry2D.clip_polygons(part, ring))
			parts = next
	return parts

static func for_tile(tid: String) -> Dictionary:
	if _tiles.has(tid): return _tiles[tid]
	var raw: Dictionary = data().tiles.get(tid, {})
	var result := {"land": [], "lakes": [], "ink": [], "shore": []}
	for key in ["land", "lakes"]:
		for p in raw.get(key, []): result[key].append(ring(p))
	for ink in raw.get("ink", []): result.ink.append({"p": ring(ink.p), "tone": ink.tone})
	for s in raw.get("shore", []): result.shore.append([Vector2(s[0],s[1]), Vector2(s[2],s[3]), Vector2(s[4],s[5])])
	_tiles[tid] = result
	return result
