extends RefCounted
## The original board's rounded, colour-by-colour road surface, lifted into 3D.
## Every band shares one triangulated height field, including across tile borders.
## Drawing order alone cannot join 3D roads: their junction heights must also agree.
const Legacy := preload("res://scripts/empire_board.gd")
const Geo := preload("res://scripts/supply_chain_3d/geometry.gd")
const Markings := preload("res://scripts/supply_chain_3d/road_markings.gd")
var markings := Markings.new()
const Sidewalks := preload("res://scripts/supply_chain_3d/urban_sidewalks.gd")
const CELL := 3.0
var cell_size := CELL
var ways: Array = []
var nodes: Dictionary = {}
var _height_cache: Dictionary = {}
var _height: Callable
var _origin := Vector2.ZERO
const BUCKET := 64.0
var _way_buckets: Dictionary = {}
var _by_tile: Dictionary = {}

func finish_build() -> void:
	# The owning builder supplies its height method. Drop that bound Callable so
	# builder -> roads -> builder never becomes a RefCounted retention cycle.
	_height = Callable()
	_height_cache.clear()

func configure(roads: Array, height: Callable, origin := Vector2.ZERO) -> void:
	ways.clear()
	nodes.clear()
	_way_buckets.clear()
	_by_tile.clear()
	_height_cache.clear()
	_height = height
	_origin = origin
	for rec in roads:
		if rec.get("tunnel",false): continue
		if (rec.a as Vector2).distance_to(rec.b) < 0.5: continue
		var w: Dictionary = rec.duplicate()
		w.widths = w.get("widths", Legacy._road_widths(int(w.level)))
		ways.append(w)
		(_by_tile.get_or_add(str(w.tile), []) as Array).append(w)
		var bounds := Rect2(w.a, Vector2.ZERO).expand(w.b).grow(float(w.widths[0]) + 3.0)
		var low := Vector2i((bounds.position / BUCKET).floor())
		var high := Vector2i((bounds.end / BUCKET).floor())
		for y in range(low.y, high.y + 1):
			for x in range(low.x, high.x + 1):
				(_way_buckets.get_or_add(Vector2i(x, y), []) as Array).append(w)
		for ends in [[w.a, w.b], [w.b, w.a]]:
			var nd: Dictionary = nodes.get_or_add(Vector2i((ends[0] as Vector2).round()), {"directions": [], "reach": 0.0})
			var direction: Vector2 = ((ends[1] as Vector2) - ends[0]).normalized()
			if not nd.directions.has(direction): nd.directions.append(direction)
			nd.reach = maxf(nd.reach, float(w.widths[0]))
	for w in ways:
		w.round = []
		w.clear = []
		for end in [w.a, w.b]:
			var nd: Dictionary = nodes[Vector2i((end as Vector2).round())]
			var through: bool = nd.directions.size() == 2 and (nd.directions[0] as Vector2).dot(nd.directions[1]) < -0.999
			var tunnel_end: bool=w.get("tunnel_a",false) if end==w.a else w.get("tunnel_b",false)
			w.round.append(not through and not tunnel_end)
			w.clear.append(0.0 if through else float(nd.reach) + 2.0)

	markings.configure(ways)

func mesh_for(tile: String) -> ArrayMesh:
	var batch := Geo.Batch.new()
	var colours := [Legacy._ROAD_EDGE, Legacy._ROAD_KERB, Legacy._ROAD_EDGE_IN, Legacy._ROAD_ASPHALT]
	# All footways share the same grade and triangulation as the carriageway.
	# Asphalt overlays their union at bends/junctions, so paving never crosses a lane.
	for band in [-2, -1]:
		for w in _by_tile.get(tile, []):
			var width := Sidewalks.width(w)
			if width <= 0.0: continue
			var polygon := Legacy._capsule(w.a, w.b, float(w.widths[0]) + width - (0.18 if band == -1 else 0.0), w.round)
			_add_band(batch, polygon, Sidewalks.EDGE if band == -2 else Sidewalks.PAVING, band)
	for band in 4:
		for w in _by_tile.get(tile, []):
			var tint: Color = Color.WHITE if bool(w.paved) else Legacy._UNPAVED
			var polygon := Legacy._capsule(w.a, w.b, w.widths[band], w.round)
			_add_band(batch, polygon, colours[band] * tint, band)
	for stripe in markings.polygons_for(tile):
		_add_band(batch, stripe.points, stripe.colour, 4)
	return batch.mesh()

func _sample(grid: Vector2i) -> float:
	if _height_cache.has(grid): return _height_cache[grid]
	var p := Vector2(grid) * cell_size
	# The shared grade already resolves junctions and keeps each hairpin arm
	# at its own elevation. A second weighted blend can pull a bridge/curve
	# below the terrain, making the asphalt appear to change width.
	var result := float(_height.call(p)) + 0.85
	_height_cache[grid] = result
	return result

func _add_band(batch: RefCounted, polygon: PackedVector2Array, colour: Color, band: int) -> void:
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for p in polygon: bounds = bounds.expand(p)
	var low := Vector2i((bounds.position / cell_size).floor())
	var high := Vector2i((bounds.end / cell_size).ceil())
	for y in range(low.y, high.y):
		for x in range(low.x, high.x):
			var cell := Vector2i(x, y)
			# Identical diagonals everywhere: clipping a band must not introduce a
			# different height interpolation at an overlap with a neighbouring road.
			for offsets in [[Vector2i.ZERO, Vector2i.RIGHT, Vector2i.ONE], [Vector2i.ZERO, Vector2i.ONE, Vector2i.DOWN]]:
				var g0: Vector2i = cell + offsets[0]
				var g1: Vector2i = cell + offsets[1]
				var g2: Vector2i = cell + offsets[2]
				var a := Vector2(g0) * cell_size
				var b := Vector2(g1) * cell_size
				var c := Vector2(g2) * cell_size
				for part in Geometry2D.intersect_polygons(polygon, PackedVector2Array([a, b, c])):
					if part.size() < 3: continue
					var vertices := PackedVector3Array()
					var heights := Vector3(_sample(g0), _sample(g1), _sample(g2))
					var determinant := (b - a).cross(c - a)
					for p in part:
						var u := (p - a).cross(c - a) / determinant
						var v := (b - a).cross(p - a) / determinant
						var h := heights.x * (1.0 - u - v) + heights.y * u + heights.z * v
						vertices.append(Vector3(p.x - _origin.x, h + float(band) * 0.08, p.y - _origin.y))
					# Thin paint strips lose winding precision at continent coordinates.
					# Triangulate near zero, then retain their world-space vertices.
					var local_part := PackedVector2Array()
					for p in part: local_part.append(p - a)
					var indices := Geometry2D.triangulate_polygon(local_part)
					for i in range(0, indices.size(), 3):
						batch.triangle(vertices[indices[i]], vertices[indices[i + 2]], vertices[indices[i + 1]], colour)
