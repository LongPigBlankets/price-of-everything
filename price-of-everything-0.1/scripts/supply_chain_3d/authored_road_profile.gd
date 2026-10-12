extends RefCounted
## Terrain-following road profiles, with continuous bank-to-bank bridge decks.
const Geo := preload("res://scripts/supply_chain_3d/geometry.gd")
const Region := preload("res://scripts/supply_chain_3d/authored_region.gd")
const Model := preload("res://scripts/empire_board_model.gd")
const Index := preload("res://scripts/supply_chain_3d/road_index.gd")
const STEP := 6.0
const BUCKET := 64.0
var segments: Array = []
var crossings: Array = []
var buckets := {}
var region := {}
var tile_index := {}
var bridge_tiles := {}
var unresolved: Array = []

func configure(data: Dictionary, rivers: Dictionary, ground: Callable, open_water: Callable = Callable()) -> void:
	segments.clear(); crossings.clear(); buckets.clear(); bridge_tiles.clear(); unresolved.clear()
	region = data.get("tiles", {})
	tile_index = Index.tiles(region)
	var water := {}
	for recs in rivers.values():
		for rec in recs:
			for i in range(1, rec.points.size()):
				var half := lerpf(float(rec.start_width), float(rec.end_width), float(i) / (rec.points.size() - 1)) * 0.5 + 8.0
				var river := {"a": rec.points[i - 1], "b": rec.points[i], "half": half}
				_index(water, river, half)
	for path in data.get("paths", []):
		var markers := PackedVector2Array()
		for bridge in path.get("bridges", []):
			if bridge is Array and bridge.size() >= 2: markers.append(Vector2(float(bridge[0]), float(bridge[1])))
			elif bridge is Dictionary and bridge.get("point") is Vector2: markers.append(bridge.point)
		var points := PackedVector2Array([path.points[0]])
		for i in range(1, path.points.size()):
			var a: Vector2 = path.points[i - 1]
			var b: Vector2 = path.points[i]
			var steps := maxi(1, ceili(a.distance_to(b) / STEP))
			for j in range(1, steps + 1): points.append(a.lerp(b, float(j) / steps))
		var heights := PackedFloat32Array()
		var wet: Array[bool] = []
		for p in points:
			heights.append(float(ground.call(p)))
			var on_water: bool = open_water.is_valid() and bool(open_water.call(p))
			for river in water.get(Vector2i((p / BUCKET).floor()), []):
				if p.distance_to(Geometry2D.get_closest_point_to_segment(p, river.a, river.b)) < river.half:
						on_water = true; break
			# The authored annotation is authoritative even when narrow rivers
			# fall between the terrain samples. Wider water still sets the span.
			for marker in markers:
				if p.distance_to(marker) < 12.0: on_water = true; break
			wet.append(on_water)
		var half := float(Region.road_widths(path.class)[0])
		var spans: Array = []
		var i := 0
		while i < points.size():
			if not wet[i]: i += 1; continue
			var start := maxi(0, i - 2)
			while i + 1 < points.size() and wet[i + 1]: i += 1
			var end := mini(points.size() - 1, i + 2)
			# A polyline ending IN the river cannot produce a safe half bridge.
			if not wet[start] and not wet[end]: spans.append([start, end])
			else: unresolved.append({"source": path.id, "a": points[start], "b": points[end]})
			i += 1
		var bridge_at := {}
		var starts := {}
		var ends := {}
		for span in spans:
			var start: int = span[0]
			var end: int = span[1]
			# Clear the full carriageway and its common height-field sampling rim,
			# not just the centreline (which can sit well below a sloped bank).
			var deck := -INF
			for k in range(start, end + 1):
				var tangent := points[mini(k + 1, points.size() - 1)] - points[maxi(0, k - 1)]
				var normal := tangent.normalized().orthogonal() * (half + 9.0)
				for p in [points[k], points[k] - normal, points[k] + normal]:
					deck = maxf(deck, float(ground.call(p)) + 5.0)
			var left := deck
			var right := deck
			starts[start] = true
			ends[end - 1] = true
			for k in range(start, end + 1):
				heights[k] = lerpf(left, right, float(k - start) / (end - start))
				if k < end: bridge_at[k] = true
			# Ease the rise into dry land instead of a vertical step at the bank.
			for sign_v in [-1, 1]:
				var anchor: int = start if sign_v < 0 else end
				var distance := 0.0
				var k: int = anchor + sign_v
				while k >= 0 and k < points.size() and distance < 42.0:
					distance += points[k].distance_to(points[k - sign_v])
					var blend := smoothstep(0.0, 42.0, distance)
					heights[k] = maxf(heights[k], lerpf(heights[anchor], heights[k], blend))
					k += sign_v
			crossings.append({"source": path.id, "a": points[start], "b": points[end], "height_a": left, "height_b": right})
		for k in range(1, points.size()):
			var rec := {"a": points[k - 1], "b": points[k], "ha": heights[k - 1], "hb": heights[k],
				"half": half, "bridge": bridge_at.has(k - 1), "post": k % 3 == 0,
				"elevated": heights[k-1]>float(ground.call(points[k-1]))+0.5 or heights[k]>float(ground.call(points[k]))+0.5,
				"start": starts.has(k - 1), "end": ends.has(k - 1), "wet_a": wet[k - 1], "wet_b": wet[k]}
			segments.append(rec)
			_index(buckets, rec, half + 8.0)
			if rec.bridge:
				for tid in Index.query(tile_index, Index.bounds(rec.a, rec.b, half), Index.TILE_CELL):
					(bridge_tiles.get_or_add(tid, []) as Array).append(rec)
	var completed := preload("res://scripts/supply_chain_3d/bridge_network.gd").complete(segments, ground)
	crossings.append_array(completed.crossings)
	unresolved = completed.unresolved
	restore(packed())

func packed() -> Dictionary:
	return {"region": region, "segments": segments, "crossings": crossings, "unresolved": unresolved}

func restore(data: Dictionary) -> void:
	region = data.region
	segments = data.segments
	crossings = data.crossings
	unresolved = data.get("unresolved", [])
	tile_index = Index.tiles(region)
	buckets.clear(); bridge_tiles.clear()
	for rec in segments:
		_index(buckets, rec, float(rec.half) + 8.0)
		if rec.bridge:
			for tid in Index.query(tile_index, Index.bounds(rec.a, rec.b, float(rec.half)), Index.TILE_CELL):
				(bridge_tiles.get_or_add(tid, []) as Array).append(rec)

static func _index(index: Dictionary, segment: Dictionary, reach: float) -> void:
	var box := Rect2(segment.a, Vector2.ZERO).expand(segment.b).grow(reach)
	var low := Vector2i((box.position / BUCKET).floor())
	var high := Vector2i((box.end / BUCKET).floor())
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1): (index.get_or_add(Vector2i(x, y), []) as Array).append(segment)

func bridge_height_at(p: Vector2) -> float:
	return height_at(p,true)

func height_at(p: Vector2, bridges_only := false) -> float:
	if Index.tile_at(tile_index, region, p) == "": return -INF
	var result := -INF
	for rec in buckets.get(Vector2i((p / BUCKET).floor()), []):
		if bridges_only and not (rec.bridge or rec.get("elevated",false)): continue
		var q := Geometry2D.get_closest_point_to_segment(p, rec.a, rec.b)
		if q.distance_to(p) > float(rec.half) + 8.0: continue
		var length: float = (rec.a as Vector2).distance_to(rec.b)
		var t: float = q.distance_to(rec.a) / maxf(length, 0.001)
		result = maxf(result, lerpf(rec.ha, rec.hb, t))
	return result

func mesh_for(tid: String, ground: Callable, origin: Vector2) -> ArrayMesh:
	var batch := Geo.Batch.new()
	if not region.has(tid): return batch.mesh()
	var hex := Model.hex_points(region[tid])
	for rec in bridge_tiles.get(tid, []):
		var clipped := Region.clip_segment(rec.a, rec.b, hex)
		if clipped.size() != 2: continue
		var length: float = (rec.a as Vector2).distance_to(rec.b)
		var a := clipped[0]
		var b := clipped[1]
		var ha := lerpf(rec.ha, rec.hb, a.distance_to(rec.a) / maxf(length, 0.001)) + 0.80
		var hb := lerpf(rec.ha, rec.hb, b.distance_to(rec.a) / maxf(length, 0.001)) + 0.80
		var n := (b - a).orthogonal().normalized() * float(rec.half)
		var left_a := Vector3(a.x + n.x - origin.x, ha, a.y + n.y - origin.y)
		var left_b := Vector3(b.x + n.x - origin.x, hb, b.y + n.y - origin.y)
		var right_a := Vector3(a.x - n.x - origin.x, ha, a.y - n.y - origin.y)
		var right_b := Vector3(b.x - n.x - origin.x, hb, b.y - n.y - origin.y)
		var down := Vector3.DOWN * 2.2
		var concrete := Color("92928a")
		batch.quad(left_a, left_b, left_b + down, left_a + down, concrete)
		batch.quad(right_b, right_a, right_a + down, right_b + down, concrete)
		batch.quad(left_a + down, left_b + down, right_b + down, right_a + down, concrete)
		for abutment in [[rec.start and a.is_equal_approx(rec.a), a, left_a, right_a],
			[rec.end and b.is_equal_approx(rec.b), b, left_b, right_b]]:
			if not abutment[0]: continue
			var foot := float(ground.call(abutment[1])) - 1.0
			var l: Vector3 = abutment[2]
			var r: Vector3 = abutment[3]
			batch.quad(l, r, Vector3(r.x, foot, r.z), Vector3(l.x, foot, l.z), concrete)
		for edge in [[left_a, left_b], [right_a, right_b]]:
			batch.tube(edge[0] + Vector3.UP * 3.0, edge[1] + Vector3.UP * 3.0, 0.35, Color("60666a"), 4)
			if rec.post: batch.tube(edge[0], edge[0] + Vector3.UP * 3.0, 0.4, concrete, 4)
	return batch.mesh()
