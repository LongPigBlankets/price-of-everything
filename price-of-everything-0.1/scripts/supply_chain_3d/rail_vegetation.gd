extends RefCounted
## Prepared from the actual curved/graded railway, including its tunnel cutoffs.
## Stored with scenery so loading and tile streaming never re-solve rail geometry.
const Index := preload("res://scripts/supply_chain_3d/road_index.gd")
const Rail := preload("res://scripts/supply_chain_3d/railway.gd")
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const SPACING := 13.0
const ROW_GAP := 10.5
const FIRST_ROW := 25.0
const BELT_WIDTH := FIRST_ROW + ROW_GAP * 2.0 + 6.0
var segments: Array = []
var buckets := {}
var parcels: Array = []
var rows := {}

static func first_offset(canopy: float) -> float:
	var edge := Rail.CORRIDOR_WIDTH * 0.5 + canopy
	return edge + (FIRST_ROW - edge) / 3.0

func packed() -> Dictionary:
	return {"segments": segments, "buckets": buckets, "parcels": parcels, "rows": rows}

func restore(data: Dictionary) -> void:
	segments = data.get("segments", []); buckets = data.get("buckets", {})
	parcels = data.get("parcels", []); rows = data.get("rows", {})

func _segment(a: Vector2, b: Vector2, half: float, rail: bool = false) -> void:
	segments.append({"a": a, "b": b, "half": half, "rail": rail})
	Index.insert(buckets, Index.bounds(a, b, maxf(half + 32.0, BELT_WIDTH if rail else 0.0)), segments.size() - 1)

func configure(art: Dictionary, roads: Array, road_portals: Array, depots: Array, tiles: Dictionary, height: Callable) -> void:
	segments.clear(); buckets.clear(); parcels.clear(); rows.clear()
	for prof in art.get("corridor_profiles", []):
		for i in range(1, prof.samples.size()):
			var a: Dictionary = prof.samples[i-1]; var b: Dictionary = prof.samples[i]
			if a.hidden or b.hidden: continue
			# Reserve open cuts and the full earthwork toe, as well as the deck.
			var fill := maxf(absf(float(a.h) - float(height.call(a.p))), absf(float(b.h) - float(height.call(b.p))))
			_segment(a.p, b.p, Rail.CORRIDOR_WIDTH * 0.5 + 3.0 + minf(fill * 0.8, 14.0), true)
	for road in roads:
		if road.get("tunnel", false): continue
		_segment(road.a, road.b, float(road.get("half", road.get("widths", [5.0])[0])) + 2.0)
	for portal in art.get("portals", []) + road_portals:
		# Include the wings/hood behind the mouth and a clear approach ahead.
		_segment(portal.p - portal.dir * 22.0, portal.p + portal.dir * float(portal.get("depth", 22.0)), float(portal.half_width) + 8.0)
	for depot in depots:
		parcels.append({"pos": depot.pos, "yaw": depot.yaw, "rect": Rect2(-150, -48, 300, 110)})
	var centers := {}
	for tid in tiles: centers[tid] = tiles[tid].center
	var tile_index := Index.tiles(centers)
	var occupied := {}
	for prof in art.get("corridor_profiles", []):
		var samples: Array = prof.samples
		if samples.size() < 2: continue
		var seed_value := hash(str(samples[0].p) + ":" + str(samples[-1].p))
		var row_count := 3 if posmod(seed_value, 3) == 0 else 2
		for i in range(1, samples.size()):
			var a: Dictionary = samples[i-1]; var b: Dictionary = samples[i]
			if a.hidden or b.hidden or a.bridge or b.bridge: continue
			for row in row_count:
				for side in [-1.0, 1.0]:
					var row_seed := hash(str(seed_value) + ":" + str(row) + ":" + str(side))
					var phase := float(posmod(row_seed, 1000)) / 1000.0 * SPACING
					var station := ceilf((float(a.s) - phase) / SPACING) * SPACING + phase
					# Independent starts/ends and phases prevent a clipped rectangular belt.
					var start := 10.0 + row * 9.0 + float(posmod(row_seed, 4)) * SPACING
					var end := 10.0 + (row_count - row) * 7.0 + float(posmod(row_seed / 7, 4)) * SPACING
					if station >= float(b.s) or station < start or station > float(samples[-1].s) - end: continue
					var t := (station - float(a.s)) / maxf(0.001, float(b.s) - float(a.s))
					var p: Vector2 = a.p.lerp(b.p, t)
					var normal: Vector2 = (b.p - a.p).normalized().orthogonal()
					var seed_at := hash(str(p.snapped(Vector2.ONE)) + ":" + str(row) + ":" + str(side))
					var jitter := float(posmod(seed_at, 101)) / 100.0 - 0.5
					var kind := "fir" if posmod(seed_at, 5) == 0 else "small"
					var tree_height := (17.0 + float(posmod(seed_at, 5))) * 0.5
					var asset := Assets.key_for("tree", 2 if kind == "fir" else 1)
					var dim := Assets.dimensions(asset)
					var canopy := maxf(dim.x, dim.z) * tree_height / Assets.projected_height(asset) * 0.5
					var at: Vector2 = p + normal * side * (first_offset(canopy) + row * ROW_GAP + jitter)
					var tid := Index.tile_at(tile_index, centers, at)
					if tid == "" or str(tiles[tid].type) != "rural": continue
					var near := Index.query(occupied, Rect2(at, Vector2.ZERO).grow(8.5))
					if near.any(func(q): return at.distance_to(q) < 8.5): continue
					Index.insert(occupied, Rect2(at, Vector2.ZERO), at)
					(rows.get_or_add(tid, []) as Array).append({"pos": at, "kind": kind,
						"height": tree_height, "size_scale": 0.5,
						"edge": "", "source": "rail_row", "row": row, "side": side})

func beside_rail(p: Vector2) -> bool:
	for id in buckets.get(Vector2i((p/Index.CELL).floor()), []):
		var rec: Dictionary = segments[id]
		if rec.get("rail", false) and p.distance_to(Geometry2D.get_closest_point_to_segment(p, rec.a, rec.b)) <= BELT_WIDTH: return true
	return false

func clear(p: Vector2, canopy: float = 0.0) -> bool:
	for rec in parcels:
		if (rec.rect as Rect2).grow(canopy).has_point((p-rec.pos).rotated(-rec.yaw)): return false
	for id in buckets.get(Vector2i((p/Index.CELL).floor()), []):
		var rec: Dictionary = segments[id]
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p, rec.a, rec.b)) < float(rec.half) + canopy: return false
	return true
