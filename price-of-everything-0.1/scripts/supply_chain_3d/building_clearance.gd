extends RefCounted
## The company's own buildings stand BuildingScale.BUILDINGS_SCALE times their lot in 3D. Where
## that would run one onto a street, it grows only as far as it stays clear, never below its lot.
## At each size it may also sit centred on its lot (an asset's plan is not centred on its anchor)
## or slide back a little (up to MAX_SLIDE of its size), its driveway following it.
## The company's buildings come first: an NPC works that would clip one is drawn smaller (down to
## MIN_LOT_SHARE of its lot), and a decorative home that would is left out. Everything else keeps
## the shipped layout.
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const FarSprites := preload("res://scripts/supply_chain_3d/far_sprites.gd")
const BuildingScale := preload("res://scripts/supply_chain_3d/building_scale.gd")
const Footprints := preload("res://scripts/supply_chain_3d/building_footprints.gd")
const FarmFields := preload("res://scripts/supply_chain_3d/farm_fields.gd")
const RoadPlacement := preload("res://scripts/supply_chain_3d/road_placement.gd")
const Legacy := preload("res://scripts/empire_board.gd")
const Model := preload("res://scripts/empire_board_model.gd")
const Index := preload("res://scripts/supply_chain_3d/road_index.gd")
## Clear ground kept between a building's base and a carriageway or another building.
const CLEARANCE := 1.5
## Growth tried, from the full scale down to the lot, in this many steps.
const STEPS := 10
## Half the width kept clear along a rail line.
const RAIL_HALF := 6.0
## How far a building may slide, as a share of its size, and in how many rings. A slid building
## stays on land and keeps most of its base on its own tile.
const MAX_SLIDE := 0.6
const SLIDE_RINGS := 6
## The share of a slid base that may stand on a neighbouring tile.
const MAX_NEIGHBOUR := 0.25
## The smallest share of its lot an NPC works is drawn at to clear the company's buildings.
const MIN_LOT_SHARE := 0.8

## Off: every building at the full scale, as before.
static var enabled := true

static func company(s: Dictionary) -> bool:
	return BuildingScale.is_building(s) and not bool(s.get("npc", false)) and not s.has("harbour") \
		and not FarmFields.is_plot(s) and bool(s.get("building_scaled", false))

static func yields(s: Dictionary) -> bool:
	return BuildingScale.is_building(s) and bool(s.get("npc", false)) and not s.has("harbour") \
		and not FarmFields.is_plot(s) and bool(s.get("building_scaled", false))

## The base a standing thing draws on the ground at `side`: a home's footprint, otherwise the
## asset's plan rectangle (the foundation world_builder.gd draws).
static func base(s: Dictionary, key: String, side: float, shift := Vector2.ZERO) -> Array:
	if str(s.kind) == "house":
		var homes := Footprints.local(key)
		if not homes.is_empty():
			var shapes: Array = []
			for shape in homes:
				var poly := PackedVector2Array()
				for p in shape: poly.append((s.pos as Vector2) + ((p as Vector2) * side).rotated(-float(s.get("yaw", 0.0))))
				shapes.append(poly)
			return shapes
		if s.has("footprint"): return [s.footprint]
	var dim := Assets.dimensions(key) * side
	var center := FarSprites.center(key) * side
	var c := Vector2(center.x, center.z)
	var half := Vector2(dim.x, dim.z) * 0.5
	var poly := PackedVector2Array()
	for p in [c - half, c + Vector2(half.x, -half.y), c + half, c + Vector2(-half.x, half.y)]:
		poly.append((s.pos as Vector2) + shift + (p as Vector2).rotated(-float(s.get("yaw", 0.0))))
	return [poly]

## The move that puts the drawn base's centre on the building's anchor, its lot centre.
static func centring(s: Dictionary, key: String, side: float) -> Vector2:
	var center := FarSprites.center(key) * side
	return -Vector2(center.x, center.z).rotated(-float(s.get("yaw", 0.0)))

static func _bounds(shapes: Array) -> Rect2:
	var box := RoadPlacement.polygon_bounds(shapes[0])
	for poly in shapes: box = box.merge(RoadPlacement.polygon_bounds(poly))
	return box

static func _driveway(road: Dictionary, s: Dictionary) -> bool:
	if not s.has("entrance"): return false
	var door: Vector2 = s.entrance
	return (road.a as Vector2).distance_to(door) < 1.5 or (road.b as Vector2).distance_to(door) < 1.5

static func _clear(shapes: Array, roads: Array, others: Array) -> bool:
	for poly in shapes:
		var grown := Geometry2D.offset_polygon(poly, CLEARANCE * 0.5)
		if grown.is_empty(): continue
		for road in roads:
			if RoadPlacement.distance_to_polygon(road.a, road.b, poly) < float(road.reach): return false
		for theirs in others:
			for other in theirs:
				if not Geometry2D.intersect_polygons(grown[0], other).is_empty(): return false
	return true

## The largest size, from `top` down to `smallest`, at which the base clears the given roads and
## bases, plain or centred. A smaller base lies inside a larger one, so only what the largest
## clashes with is tried again. Returns [side, shift], the smallest plain when nothing clears.
## A slid base stands on land throughout, never over sea terrain, and keeps at least
## 1 - MAX_NEIGHBOUR of its area on its own tile.
static func _placeable(shapes: Array, hex: PackedVector2Array, water: Callable) -> bool:
	for poly in shapes:
		if water.is_valid():
			for p in _samples(poly):
				if bool(water.call(p)): return false
		if hex.is_empty(): continue
		var area := absf(_area(poly))
		var outside := 0.0
		for part in Geometry2D.clip_polygons(poly, hex): outside += absf(_area(part))
		if area > 0.0 and outside / area > MAX_NEIGHBOUR: return false
	return true

## Points across a base: its corners and a grid over a four-sided one.
static func _samples(poly: PackedVector2Array) -> PackedVector2Array:
	var points := poly.duplicate()
	if poly.size() != 4: return points
	for i in 5:
		for j in 5:
			var u := (i + 0.5) / 5.0
			var v := (j + 0.5) / 5.0
			points.append(poly[0].lerp(poly[1], u).lerp(poly[3].lerp(poly[2], u), v))
	return points

static func _area(poly: PackedVector2Array) -> float:
	var total := 0.0
	for i in poly.size(): total += poly[i].cross(poly[(i + 1) % poly.size()])
	return total * 0.5

static func _fit(s: Dictionary, key: String, top: float, smallest: float, roads: Array, others: Array, slide := false,
		hex := PackedVector2Array(), water := Callable()) -> Array:
	var full := base(s, key, top)
	var box := _bounds(full).grow(CLEARANCE)
	var near_roads: Array = []
	for road in roads:
		if not box.grow(float(road.reach)).intersects(Rect2(road.a, Vector2.ZERO).expand(road.b).grow(0.5)): continue
		if not _clear(full, [road], []): near_roads.append(road)
	var near: Array = []
	for theirs in others:
		if box.intersects(_bounds(theirs)) and not _clear(full, [], [theirs]): near.append(theirs)
	if near_roads.is_empty() and near.is_empty(): return [top, Vector2.ZERO]
	for step in range(STEPS, -1, -1):
		var side := lerpf(smallest, top, float(step) / STEPS)
		var shifts: Array = [Vector2.ZERO, centring(s, key, side)]
		if slide:
			for ring in range(1, SLIDE_RINGS + 1):
				for k in 8: shifts.append(Vector2.RIGHT.rotated(TAU * k / 8.0) * side * MAX_SLIDE * ring / SLIDE_RINGS)
		for shift in shifts:
			var moved := base(s, key, side, shift)
			if _clear(moved, near_roads, near) and (shift == Vector2.ZERO or _placeable(moved, hex, water)): return [side, shift]
	return [smallest, Vector2.ZERO]

## Decorative homes never stand on a carriageway (a driveway to their own door aside): a home
## that does is left out. Returns how many were.
static func _clear_homes(model: Dictionary, key_for: Callable) -> int:
	var roads: Array = []
	for road in model.get("roads", []):
		if road.get("tunnel", false): continue
		var widths: Array = road.get("widths", Legacy._road_widths(int(road.get("level", 1))))
		roads.append({"a": road.a, "b": road.b, "half": float(widths[widths.size() - 1])})
	var index := Index.segments(roads, 12.0)
	var kept: Array = []
	var dropped := 0
	for s in model.get("standing", []):
		if str(s.get("kind", "")) != "house" or not _on_road(s, base(s, str(key_for.call(s)), float(s.side)), roads, index):
			kept.append(s)
		else: dropped += 1
	if dropped > 0: model.standing = kept
	return dropped

static func _on_road(s: Dictionary, shapes: Array, roads: Array, index: Dictionary) -> bool:
	for poly in shapes:
		if poly.size() < 3: continue
		var box := RoadPlacement.polygon_bounds(poly)
		for id in Index.query(index, box.grow(2.0)):
			var road: Dictionary = roads[id]
			if _driveway(road, s): continue
			if RoadPlacement.distance_to_polygon(road.a, road.b, poly) < float(road.half) - 0.5: return true
	return false

## The driveway's door end follows a building that slid. Road records may be the shipped
## model's, so the moved one is a copy.
static func _follow(model: Dictionary, s: Dictionary, shift: Vector2) -> void:
	if not s.has("entrance"): return
	var door: Vector2 = s.entrance
	var roads: Array = model.get("roads", [])
	for i in roads.size():
		var road: Dictionary = roads[i]
		for end in ["a", "b"]:
			if (road[end] as Vector2).distance_to(door) < 1.5:
				road = road.duplicate()
				road[end] = (road[end] as Vector2) + shift
				roads[i] = road
	s.entrance = door + shift

static func _resize(s: Dictionary, side: float, shift: Vector2) -> void:
	var pad_share := float(s.get("pad", s.side)) / float(s.side)
	s.side = side
	s.pad = side * pad_share
	s.pos = (s.pos as Vector2) + shift

## Fits the company's buildings, then makes the NPC works and homes around them give way.
## Returns how many standing things it changed.
static func apply(model: Dictionary, key_for: Callable, water := Callable()) -> int:
	if not enabled: return 0
	var standing: Array = model.get("standing", [])
	var roads: Array = []
	for road in model.get("roads", []):
		if road.get("tunnel", false): continue
		var widths: Array = road.get("widths", Legacy._road_widths(int(road.get("level", 1))))
		# Up to the pavement like any town building, never onto the carriageway.
		roads.append({"a": road.a, "b": road.b, "reach": float(widths[widths.size() - 1]) + CLEARANCE})
	var rails: Array = []
	for line in model.get("lines", []):
		if str(line.get("mode", "")) != "rail": continue
		var pts: Array = line.get("pts", [])
		for i in range(1, pts.size()): rails.append({"a": pts[i - 1], "b": pts[i], "reach": RAIL_HALF + CLEARANCE})
	var changed := 0
	# Depots (the company's warehouses, Local Suppliers) keep their size and slide off a
	# carriageway they stand on, their driveway following; the works then fit around them.
	for i in standing.size():
		var depot: Dictionary = standing[i]
		if str(depot.get("kind", "")) not in ["warehouse", "suppliers"] or depot.has("harbour"): continue
		var key := str(key_for.call(depot))
		var own_roads := roads.filter(func(road: Dictionary) -> bool: return not _driveway(road, depot)) + rails
		if _clear(base(depot, key, float(depot.side)), own_roads, []): continue
		var tile: Dictionary = model.get("tiles", {}).get(str(depot.get("tile", "")), {})
		var hex := Model.hex_points(tile.center) if tile.has("center") else PackedVector2Array()
		var fit := _fit(depot, key, float(depot.side), float(depot.side), own_roads, [], true, hex, water)
		if fit[1] == Vector2.ZERO: continue
		# The shipped model's records are shared: the view draws its own copy.
		var copy := depot.duplicate()
		copy.pos = (copy.pos as Vector2) + fit[1]
		_follow(model, copy, fit[1])
		standing[i] = copy
		changed += 1
	var settled: Array = []
	# The company's buildings, against the streets and whatever does not give way to them.
	for s in standing:
		if not company(s): continue
		var key := str(key_for.call(s))
		var lot_side := float(s.get("lot_side", float(s.side) / BuildingScale.BUILDINGS_SCALE))
		s.lot_side = lot_side
		if s.has("lot_pos"): s.pos = s.lot_pos
		s.lot_pos = s.pos
		var own_roads := roads.filter(func(road: Dictionary) -> bool: return not _driveway(road, s)) + rails
		var fixed: Array = settled.duplicate()
		for o in standing:
			if o == s or company(o) or yields(o) or str(o.get("kind", "")) in ["house", "pylon"] or o.has("harbour"): continue
			fixed.append(base(o, str(key_for.call(o)), float(o.side)))
		var tile: Dictionary = model.get("tiles", {}).get(str(s.get("tile", "")), {})
		var hex := Model.hex_points(tile.center) if tile.has("center") else PackedVector2Array()
		var fit := _fit(s, key, lot_side * BuildingScale.BUILDINGS_SCALE, lot_side, own_roads, fixed, true, hex, water)
		if fit[0] < lot_side * BuildingScale.BUILDINGS_SCALE - 0.01 or fit[1] != Vector2.ZERO: changed += 1
		_resize(s, fit[0], fit[1])
		if fit[1] != Vector2.ZERO: _follow(model, s, fit[1])
		settled.append(base(s, key, float(s.side)))
	changed += _clear_homes(model, key_for)
	standing = model.standing
	if settled.is_empty(): return changed
	# NPC works and homes give way to them.
	var kept: Array = []
	for i in standing.size():
		var o: Dictionary = standing[i]
		if not yields(o) and str(o.get("kind", "")) != "house":
			kept.append(o)
			continue
		var key := str(key_for.call(o))
		var theirs := base(o, key, float(o.side))
		var box := _bounds(theirs).grow(CLEARANCE)
		var clips := settled.filter(func(mine: Array) -> bool: return box.intersects(_bounds(mine)) and not _clear(theirs, [], [mine]))
		if clips.is_empty():
			kept.append(o)
			continue
		changed += 1
		if str(o.kind) == "house": continue
		# The shipped model's records are shared: the company view draws its own copy.
		var copy := o.duplicate()
		var lot_side := float(copy.side) / BuildingScale.BUILDINGS_SCALE
		var fit := _fit(copy, key, float(copy.side), lot_side * MIN_LOT_SHARE, [], clips)
		_resize(copy, fit[0], fit[1])
		kept.append(copy)
	model.standing = kept
	return changed
