class_name RoadOffshoots
extends Node2D
## Ancillary road offshoots (roadsv2.5). A tile with more than 3 non-forest,
## non-farm buildings sprouts short branching stubs off the road(s) running
## through it — local access streets for a built-up tile. A stub that ends
## within ~3u of another road bends to connect INTO it; otherwise it's a short
## dead-end spur.
##
## These are NOT routing edges. Per the building-visuals LOD plan they are
## ancillary roads: drawn only when zoomed in, and (later) abstracted into the
## grey built-up blob at zoom-out. The major network (RoadNetworkVisuals) draws
## above this and is never abstracted.

const BUILDING_THRESHOLD := 3        # > this many qualifying buildings -> offshoots
# Stub length range (1u..3u, where 1u ≈ 10 world units). Tune freely.
const OFFSHOOT_MIN_LEN := 10.0       # ~1u
const OFFSHOOT_MAX_LEN := 30.0       # ~3u
const OFFSHOOT_CURVE := 0.32         # lateral bulge as a fraction of length (the curve)
const OFFSHOOT_CONNECT_DIST := 30.0  # ~3u: nearer than this to another road -> bend in
const ZOOM_SHOW := 0.6               # only drawn when zoomed in past this
const MAX_STUBS := 240               # global draw-cost cap
const NON_BUILDINGS := {"farm": true, "new_forest": true, "roads": true}
const NAV_WATER_RIVER := 3           # navgrid cell high-nibble class (see hill_field)

const COLOR := Color("e8c84a")       # matches the network's LOCAL_COLOR
const CASING := Color(0.24, 0.16, 0.05, 0.85)
const WIDTH := 3.0

var _stubs: Array = []               # Array[PackedVector2Array]
var _dirty := true

func _ready() -> void:
	MatchState.building_added.connect(func(_i: Dictionary) -> void: _dirty = true)
	MatchState.building_removed.connect(func(_i: String) -> void: _dirty = true)
	RoadWorks.order_settled.connect(func(_i: int) -> void: _dirty = true)

func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		_stubs = generate_stubs(_terrain(), RoadNetwork.instance())
		queue_redraw()
	# Ancillary detail: shown only when zoomed in (LOD plan).
	var cam := get_viewport().get_camera_2d()
	var want := cam != null and cam.zoom.x >= ZOOM_SHOW and not _stubs.is_empty()
	if want != visible:
		visible = want
		if want:
			queue_redraw()

func _draw() -> void:
	for stub in _stubs:
		var poly: PackedVector2Array = stub
		if poly.size() < 2:
			continue
		draw_polyline(poly, CASING, WIDTH + 2.0, true)
	for stub2 in _stubs:
		var poly2: PackedVector2Array = stub2
		if poly2.size() < 2:
			continue
		draw_polyline(poly2, COLOR, WIDTH, true)

func _terrain() -> HexMap:
	var found := get_tree().get_nodes_in_group("hex_map")
	return found[0] as HexMap if not found.is_empty() else null

## Build the stub set. Deterministic: choices key off the tile id. Static so it
## can be driven from tests without the scene tree.
static func generate_stubs(terrain: HexMap, net: RoadNetwork) -> Array:
	if terrain == null or net == null or not net.has_any_edges():
		return []
	var nav := NavGrid.instance()   # for the river-aim test (may be null in tests)
	# Count qualifying (non-forest/farm/road) buildings per tile.
	var count_by_tile: Dictionary = {}
	for iid in MatchState.buildings:
		var b: Dictionary = MatchState.buildings[iid]
		var bid := str(b.get("building_id", ""))
		var internal := str(Catalog.get_building(bid).get("internal_name", ""))
		if NON_BUILDINGS.has(internal) or ForestFootprint.is_forest(bid):
			continue
		var tid := str(b.get("tile_id", ""))
		count_by_tile[tid] = int(count_by_tile.get(tid, 0)) + 1
	# Flat list of every road point, for the "near another road" connect test.
	var all_pts: Array[Vector2] = []
	for eid in net.edges:
		for p in (net.edges[eid].geometry as PackedVector2Array):
			all_pts.append(p)
	var stubs: Array = []
	var tids: Array = count_by_tile.keys()
	tids.sort()   # determinism independent of dictionary order
	for tid in tids:
		if int(count_by_tile[tid]) <= BUILDING_THRESHOLD:
			continue
		var coord: Vector2i = terrain.id_to_coord(str(tid))
		if not terrain.tiles.has(coord):
			continue
		var center: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
		var origins := _road_origins_in_tile(net, center)
		if origins.is_empty():
			continue
		var n_stubs: int = clampi(int(count_by_tile[tid]) - BUILDING_THRESHOLD, 1, 4)
		for i in n_stubs:
			if stubs.size() >= MAX_STUBS:
				return stubs
			var oi: int = RoadHash.pick("offshoot|%s|%d|origin" % [tid, i], origins.size())
			var origin: Vector2 = origins[oi][0]
			var dir: Vector2 = origins[oi][1]
			var perp := Vector2(-dir.y, dir.x)
			if RoadHash.pick("offshoot|%s|%d|side" % [tid, i], 2) == 1:
				perp = -perp
			# only bridges cross rivers — a stub near a river always aims away from it
			perp = _away_from_river(origin, perp, nav)
			var span := OFFSHOOT_MAX_LEN - OFFSHOOT_MIN_LEN
			var length := OFFSHOOT_MIN_LEN + float(RoadHash.pick("offshoot|%s|%d|len" % [tid, i], int(span) + 1))
			var endp := origin + perp * length
			if not _in_hex(endp, center):
				length *= 0.5
				endp = origin + perp * length
				if not _in_hex(endp, center):
					continue
			# bend into a nearby road if the stub reaches one (skip the origin road itself)
			var snap := _nearest_road(all_pts, endp, origin)
			if not snap.is_empty():
				endp = snap.point
			# curve the stub one way or the other (seeded)
			var curve_sign := 1.0 if RoadHash.pick("offshoot|%s|%d|curve" % [tid, i], 2) == 0 else -1.0
			stubs.append(_curved_stub(origin, endp, curve_sign))
	return stubs

## Quadratic-bezier polyline from `a` to `b`, bulging to one side (curve_sign).
static func _curved_stub(a: Vector2, b: Vector2, curve_sign: float) -> PackedVector2Array:
	var d := b - a
	var lateral := Vector2(-d.y, d.x) * (curve_sign * OFFSHOOT_CURVE)
	var ctrl := (a + b) * 0.5 + lateral
	var out := PackedVector2Array()
	for k in 6:
		var t := float(k) / 5.0
		out.append(a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t))
	return out

## Orient `perp` to point AWAY from the nearest river within OFFSHOOT_MAX_LEN of
## `origin` (rivers are crossed only by bridges, never by a stub). Unchanged when
## no river is near.
static func _away_from_river(origin: Vector2, perp: Vector2, nav: NavGrid) -> Vector2:
	if nav == null or not nav.is_ready():
		return perp
	var c := nav.cell_of(origin)
	var reach := int(ceil(OFFSHOOT_MAX_LEN / nav.step)) + 1
	var best := OFFSHOOT_MAX_LEN * OFFSHOOT_MAX_LEN
	var nearest := Vector2.ZERO
	var found := false
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var nx := c.x + dx
			var ny := c.y + dy
			if nx < 0 or ny < 0 or nx >= nav.gw or ny >= nav.gh:
				continue
			if (nav.cells[ny * nav.gw + nx] >> 4) != NAV_WATER_RIVER:
				continue
			var wp := nav.world_of(nx, ny)
			var d := wp.distance_squared_to(origin)
			if d < best:
				best = d
				nearest = wp
				found = true
	if not found:
		return perp
	var away := origin - nearest
	if away.length_squared() < 1.0:
		return perp
	return perp if perp.dot(away) >= 0.0 else -perp

## (point, unit_tangent) pairs along network edges whose segment midpoint sits
## inside this tile's hex — the road through the tile, sampled for branch roots.
static func _road_origins_in_tile(net: RoadNetwork, center: Vector2) -> Array:
	var out: Array = []
	for eid in net.edges:
		var geo: PackedVector2Array = net.edges[eid].geometry
		for i in range(geo.size() - 1):
			var mid := (geo[i] + geo[i + 1]) * 0.5
			if _in_hex(mid, center):
				var d := geo[i + 1] - geo[i]
				if d.length_squared() > 1.0:
					out.append([mid, d.normalized()])
	return out

## Nearest road point within OFFSHOOT_CONNECT_DIST of `to`, ignoring points on
## the origin road (within one stub length of `from`). {} if none.
static func _nearest_road(all_pts: Array[Vector2], to: Vector2, from: Vector2) -> Dictionary:
	var best: Vector2 = Vector2.ZERO
	var best_d := OFFSHOOT_CONNECT_DIST * OFFSHOOT_CONNECT_DIST
	var found := false
	for p in all_pts:
		if p.distance_squared_to(from) < OFFSHOOT_MAX_LEN * OFFSHOOT_MAX_LEN:
			continue   # same through-road we branched off
		var d := p.distance_squared_to(to)
		if d < best_d:
			best_d = d
			best = p
			found = true
	return {"point": best} if found else {}

## Flat-top hex containment about `center` (vertices per the project geometry).
static func _in_hex(p: Vector2, center: Vector2) -> bool:
	var dx := absf(p.x - center.x)
	var dy := absf(p.y - center.y)
	return dx <= 270.0 and dy <= 240.0 and 240.0 * dx + 135.0 * dy <= 64800.0
