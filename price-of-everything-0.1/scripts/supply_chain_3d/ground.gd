extends "res://scripts/empire_board_ground.gd"
## 3D-only extension of the shared terrain sampler. Keep the regular map's
## integer contours and tile plates intact; add half rungs inside existing hills.
const DisplayRelief := preload("res://scripts/supply_chain_3d/relief.gd")
const HALF_RISE_MIN := 5.5
const Water := preload("res://scripts/supply_chain_3d/water_geography.gd")
var water_geography := false

func _wet(tile: String) -> bool:
	if not water_geography: return super._wet(tile)
	if not _wet_tiles.has(tile):
		var rel: Dictionary = relief.call(tile, tiles[tile].center)
		_wet_tiles[tile] = not rel.get("shore", []).is_empty() or not rel.get("lakes", []).is_empty() or is_water(rel, tiles[tile].center)
	return _wet_tiles[tile]

func _file_shore(tile: String) -> void:
	if not water_geography:
		super._file_shore(tile)
		return
	var rel: Dictionary = relief.call(tile, tiles[tile].center)
	for seg in rel.get("shore", []): _file(_shore_segs, seg[0], seg[1], [seg[0], seg[1], SEA_LEVEL])
	var box := Rect2(tiles[tile].center - HEX_HALF, HEX_HALF * 2.0)
	for lake in Water.lakes():
		if not (lake.box as Rect2).intersects(box): continue
		for shore in lake.shores:
			for i in shore.size():
				var a: Vector2 = shore[i]; var b: Vector2 = shore[(i+1)%shore.size()]
				if Rect2(a, Vector2.ZERO).expand(b).grow(0.01).intersects(box):
					_file(_shore_segs, a, b, [a, b, lake.level])

func _water_level(p: Vector2) -> float:
	if not water_geography: return super._water_level(p)
	var surface := Water.lake_surface(p)
	return surface.x if surface.y == 1 else SEA_LEVEL

func height(p: Vector2) -> float:
	if not water_geography: return super.height(p)
	var surface := Water.lake_surface(p)
	if surface.y == 1: return surface.x
	var value := super.height(p)
	if surface.y == 2: return maxf(value, surface.x)
	return value

func gradient(p: Vector2) -> Vector2:
	var surface := Water.lake_surface(p) if water_geography else Vector2.ZERO
	if surface.y == 1: return Vector2.ZERO
	if surface.y == 2:
		return Vector2(height(p + Vector2.RIGHT * 0.25) - height(p - Vector2.RIGHT * 0.25),
			height(p + Vector2.DOWN * 0.25) - height(p - Vector2.DOWN * 0.25)) * 2.0
	return super.gradient(p)

func _ground(p: Vector2, full: bool) -> float:
	var value := super._ground(p, full)
	if not full or not water_geography: return value
	var tid := tile_at(p)
	if tid != "" and tiles[tid].water and not is_water(relief.call(tid, tiles[tid].center), p):
		# Small new islands/peninsulas can straddle nominal sea tiles. Their
		# land is raised from the water instead of inheriting the sea tile plate.
		var distance := SLOPE_W
		for seg in relief.call(tid, tiles[tid].center).get("shore", []):
			distance = minf(distance, p.distance_to(Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1])))
		value = maxf(value, lerpf(SEA_LEVEL, 34.0, clampf(distance / 8.0, 0, 1)))
	return value

func setup() -> void:
	var levels: Array = bands.map(func(e: Dictionary) -> float: return float(e.b))
	super.setup()
	# Base setup boxes polygons but casts their band identifiers to integers.
	for i in bands.size(): bands[i].b = levels[i]

func _rises(tile: String) -> Array:
	var out: Array = []
	if bool(tiles[tile].water): return out
	var h := float(tiles[tile].height)
	var reg := region(tile)
	var box := _box_of(reg).grow(RISE_ROUND * 3.0)
	var window := PackedVector2Array([box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)])
	var near: Array = []
	for e in bands:
		var level := DisplayRelief.band_height(float(e.b))
		if level < h + HALF_RISE_MIN or not (e.box as Rect2).intersects(box): continue
		for piece in Geometry2D.intersect_polygons(e.p, window):
			if not Geometry2D.is_polygon_clockwise(piece): near.append([level, piece])
	# The same rounding/slope model as the source sampler, now at half intervals.
	for half_band in range(5, 23):
		var rung := DisplayRelief.band_height(half_band * 0.5)
		if rung < h + HALF_RISE_MIN: continue
		var merged: Array = []
		for e in near:
			if float(e[0]) >= rung: merged = _merge_in(merged, e[1])
		var rounded: Array = []
		for poly in merged:
			for opened in _offset(_offset([poly], -RISE_ROUND), RISE_ROUND): rounded = _merge_in(rounded, opened)
		var closed: Array = _offset(_offset(rounded, RISE_ROUND), -RISE_ROUND)
		for poly in closed:
			for piece in Geometry2D.intersect_polygons(poly, reg):
				if Geometry2D.is_polygon_clockwise(piece) or _area(piece) < RISE_MIN_AREA: continue
				var ring := _thinned(piece)
				if ring.size() >= 3: out.append({"v": rung, "ring": ring, "box": _box_of(ring)})
	return out
