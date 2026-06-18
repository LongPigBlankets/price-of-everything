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
# Stub length range (4u..12u, where 1u ≈ 10 world units). Tune freely.
const OFFSHOOT_MIN_LEN := 40.0       # ~4u
const OFFSHOOT_MAX_LEN := 120.0      # ~12u
const OFFSHOOT_Y_SPLIT := 80.0       # stubs longer than ~8u fork into a Y at the tip
const OFFSHOOT_Y_BRANCH := 30.0      # ~3u each Y arm
const OFFSHOOT_Y_ANGLE := 0.5        # ~29° spread of each Y arm off the stub's heading
const OFFSHOOT_CURVE := 0.32         # lateral bulge as a fraction of length (the curve)
const OFFSHOOT_CONNECT_DIST := 30.0  # ~3u: nearer than this to another road -> bend in
const ZOOM_SHOW := 0.6               # only drawn when zoomed in past this
const MAX_STUBS := 240               # global draw-cost cap
const MAX_STUBS_PER_TILE := 2        # at most this many stub ROOTS per tile (each may fork into a Y)
const NON_BUILDINGS := {"farm": true, "new_forest": true, "roads": true}
const NAV_WATER_RIVER := 3           # navgrid cell high-nibble class (see hill_field)

const COLOR := Color("e8c84a")       # matches the network's LOCAL_COLOR
const CASING := Color(0.24, 0.16, 0.05, 0.85)
const WIDTH := 3.0                   # Y-arm thickness (the thin forks at a stub tip)
const ROOT_WIDTH := 4.5              # stub TRUNK = a real LOCAL road (RoadNetworkVisuals.LOCAL_WIDTH)
const STUB_CLEAR := 6.0              # keep stubs this far off building footprints (own const; NOT building_visuals.DESIGN_GAP)
const STUB_MIN_GAP := 50.0           # two stub ROOTS on the same tile must start at least this far apart
const STUB_CONNECT_GAP := 20.0       # free stub TIPS closer than this join up — if the link clears water/peaks
const STUB_OVERLAP_RADIUS := 20.0    # a MID stub segment within this of a parallel road = "doubled"
const STUB_OVERLAP_END_SKIP := 24.0  # ignore segments near either END (the root sits on its origin road; the tip may snap into one)
const STUB_OVERLAP_FRAC := 0.4       # drop the stub if >= this fraction of its MIDDLE segments run alongside a road

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
	# Roots (6-pt curved beziers) draw at road thickness; Y-arms (2-pt) stay thin.
	# Casings under all, then cores over all, so a trunk's casing never paints over
	# an adjacent core.
	for stub in _stubs:
		var poly: PackedVector2Array = stub
		if poly.size() < 2:
			continue
		var w: float = ROOT_WIDTH if poly.size() > 2 else WIDTH
		draw_polyline(poly, CASING, w + 2.0, true)
	for stub2 in _stubs:
		var poly2: PackedVector2Array = stub2
		if poly2.size() < 2:
			continue
		var w2: float = ROOT_WIDTH if poly2.size() > 2 else WIDTH
		draw_polyline(poly2, COLOR, w2, true)

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
	# Flat list of every NON-enclosure road point, for the "near another road" connect test (a stub
	# never snaps to a block ring), plus the enclosure rings grouped by tile so stubs can avoid their
	# interior. Both come straight from the network, so they survive a reload with no extra state.
	var all_pts: Array[Vector2] = []
	var road_segs: Array = []   # non-enclosure road SEGMENTS, for the "runs alongside a road" overlap test
	var encl_by_coord: Dictionary = {}
	for eid in net.edges:
		var e: Dictionary = net.edges[eid]
		if str(e.a).begins_with("encl:") or str(e.b).begins_with("encl:"):
			for tc in (e.tiles as Array):
				var arr: PackedVector2Array = encl_by_coord.get(tc, PackedVector2Array())
				arr.append_array(e.geometry as PackedVector2Array)
				encl_by_coord[tc] = arr
		else:
			var g: PackedVector2Array = e.geometry
			for p in g:
				all_pts.append(p)
			for i in range(g.size() - 1):
				road_segs.append([g[i], g[i + 1]])
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
		var footprints := _tile_footprints(coord)   # world rects; [] when no provider (tests)
		# Block-enclosure keep-out: the convex hull of this tile's encl: ring points. Stubs never project
		# inside it (the block already has its ring); only stubs OUTSIDE the block are kept.
		var encl_pts: PackedVector2Array = encl_by_coord.get(coord, PackedVector2Array())
		var encl_hull: PackedVector2Array = Geometry2D.convex_hull(encl_pts) if encl_pts.size() >= 3 else PackedVector2Array()
		var has_encl := encl_hull.size() >= 3
		var encl_centroid := Vector2.ZERO
		if has_encl:
			for hp in encl_hull:
				encl_centroid += hp
			encl_centroid /= float(encl_hull.size())
		var placed_origins: Array = []   # stub roots already used on this tile (STUB_MIN_GAP spacing)
		var n_stubs: int = clampi(int(count_by_tile[tid]) - BUILDING_THRESHOLD, 1, MAX_STUBS_PER_TILE)
		for i in n_stubs:
			if stubs.size() >= MAX_STUBS:
				return stubs
			var oi: int = RoadHash.pick("offshoot|%s|%d|origin" % [tid, i], origins.size())
			if _too_close(origins[oi][0], placed_origins, STUB_MIN_GAP):
				oi = _alt_origin(origins, placed_origins, STUB_MIN_GAP)   # find a root >= 50u from the others
				if oi < 0:
					continue   # no root far enough from the already-placed stubs — drop this one
			var origin: Vector2 = origins[oi][0]
			var dir: Vector2 = origins[oi][1]
			var perp := Vector2(-dir.y, dir.x)
			if RoadHash.pick("offshoot|%s|%d|side" % [tid, i], 2) == 1:
				perp = -perp
			# only bridges cross rivers — a stub near a river always aims away from it
			perp = _away_from_river(origin, perp, nav)
			# never project INTO a block enclosure — aim away from it
			perp = _away_from_enclosure(origin, perp, encl_centroid, has_encl)
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
			var snapped := not snap.is_empty()
			if snapped:
				endp = snap.point
			# curve the stub one way or the other (seeded)
			var curve_sign := 1.0 if RoadHash.pick("offshoot|%s|%d|curve" % [tid, i], 2) == 0 else -1.0
			var poly := _curved_stub(origin, endp, curve_sign)
			# keep cosmetic stubs off building footprints: if the DRAWN curve would cross
			# one (including a crossing the road-snap just introduced), re-aim to thread a
			# gap, else shorten. The replacement is drawn straight so geometry == tested ray.
			if not footprints.is_empty() and _poly_hits(poly, footprints, STUB_CLEAR):
				var fixed := _avoid_footprints(origin, perp, length, center, nav, footprints, tid, i)
				if fixed.is_empty():
					continue   # avoidance failed — drop this stub rather than draw it over a building
				poly = fixed
				endp = poly[poly.size() - 1]
				snapped = false   # the re-aimed/shortened endpoint is free-ending again
			# a stub never crosses water — only bridges do. A snap-into-a-road or a curve can still span
			# a river even though the root aimed away from it, so drop any stub that touches water.
			if _crosses_water(poly, nav):
				continue
			# final guard: drop any stub that still lands inside a block enclosure
			if has_encl and _poly_in_polygon(poly, encl_hull):
				continue
			# never draw a stub ALONGSIDE an existing road (the "doubled road"): drop parallel overlaps.
			# A perpendicular spur or a tip-snapped connector isn't parallel, so it survives.
			if _runs_alongside_road(poly, road_segs):
				continue
			stubs.append(poly)
			placed_origins.append(origin)
			# a long free-ending stub forks into a Y at the tip (arms also skip footprints, water, enclosures, doubling)
			if not snapped and origin.distance_to(endp) > OFFSHOOT_Y_SPLIT:
				var heading := (endp - origin).normalized()
				for sgn in [1.0, -1.0]:
					var arm := endp + heading.rotated(OFFSHOOT_Y_ANGLE * sgn) * OFFSHOOT_Y_BRANCH
					if not _in_hex(arm, center) or _seg_hits_any(endp, arm, footprints, STUB_CLEAR):
						continue
					if _crosses_water(PackedVector2Array([endp, arm]), nav):
						continue
					if has_encl and Geometry2D.is_point_in_polygon(arm, encl_hull):
						continue
					if _runs_alongside_road(PackedVector2Array([endp, arm]), road_segs):
						continue
					stubs.append(PackedVector2Array([endp, arm]))
	# Join stub TIPS that nearly meet so roads connect — but only when the short link clears water and
	# banned terrain (peaks). Never bridge a river, run over a summit, or cross the sea.
	_connect_stub_tips(stubs, nav)
	return stubs

## Link free stub tips closer than STUB_CONNECT_GAP, each tip to its nearest CLEARABLE neighbour (one link
## per tip). A link is added only if the straight connector crosses neither water nor a banned level.
## Mutates `stubs` in place (appends the connector polylines, drawn at road width).
static func _connect_stub_tips(stubs: Array, nav: NavGrid) -> void:
	var tips: Array = []   # [tip_point, stub_index]
	for si in stubs.size():
		var s: PackedVector2Array = stubs[si]
		if s.size() >= 2:
			tips.append([s[s.size() - 1], si])
	var connected: Dictionary = {}
	var links: Array = []
	for i in tips.size():
		if connected.has(i):
			continue
		var ti: Vector2 = (tips[i] as Array)[0]
		var best := -1
		var best_d := STUB_CONNECT_GAP
		for j in range(tips.size()):
			if j == i or connected.has(j) or (tips[i] as Array)[1] == (tips[j] as Array)[1]:
				continue
			var tj: Vector2 = (tips[j] as Array)[0]
			var d := ti.distance_to(tj)
			if d > 0.5 and d < best_d and _connector_clear(ti, tj, nav):
				best_d = d
				best = j
		if best >= 0:
			var tb: Vector2 = (tips[best] as Array)[0]
			links.append(PackedVector2Array([ti, (ti + tb) * 0.5, tb]))   # 3 pts -> drawn at road width
			connected[i] = true
			connected[best] = true
	stubs.append_array(links)

## True if the straight segment a-b stays on buildable land — no water (river/sea/lake) and no banned
## level (e.g. a snow-capped peak) — sampled at half the nav step. False (don't connect) without a nav.
static func _connector_clear(a: Vector2, b: Vector2, nav: NavGrid) -> bool:
	if nav == null or not nav.is_ready():
		return false
	var stepd := maxf(nav.step * 0.5, 1.0)
	var n := maxi(1, int(ceil(a.distance_to(b) / stepd)))
	for s in n + 1:
		var c := nav.cell_of(a.lerp(b, float(s) / float(n)))
		if c.x < 0 or c.y < 0 or c.x >= nav.gw or c.y >= nav.gh:
			return false
		if nav.water(c.x, c.y) != NavGrid.WATER_LAND:
			return false   # river / sea / lake
		if nav.level(c.x, c.y) >= RoadRealizer.BAN_LEVEL:
			return false   # banned peak
	return true

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

## World-space building footprint rects on this tile (one per non-forest footprint),
## via the BuildingVisuals provider in the "building_footprints" group. Empty when no
## provider is present (tests / early startup) — avoidance then no-ops.
static func _tile_footprints(coord: Vector2i) -> Array:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return []
	for n in (loop as SceneTree).get_nodes_in_group("building_footprints"):
		if n.has_method("footprint_rects_on_tile"):
			return n.footprint_rects_on_tile(coord)
	return []

## Re-aim a stub off building footprints: try a seeded sequence of bearings around
## perp; the first whose STRAIGHT stub clears every (grown) footprint wins — drawn
## straight (curve 0) so the rendered polyline matches the tested ray. If no bearing is
## clear, shorten along the original perp. Returns [] if nothing works (caller keeps it).
## Re-applies _away_from_river after each rotation so the no-bridgeless-crossing invariant holds.
static func _avoid_footprints(origin: Vector2, perp: Vector2, length: float, center: Vector2, nav: NavGrid, rects: Array, tid: String, i: int) -> PackedVector2Array:
	var sgn := 1.0 if RoadHash.pick("offshoot|%s|%d|reaim" % [tid, i], 2) == 0 else -1.0
	for off in [sgn * 0.30, -sgn * 0.30, sgn * 0.60, -sgn * 0.60, sgn * 0.95, -sgn * 0.95]:
		var rot := _away_from_river(origin, perp.rotated(off), nav)
		var ep := origin + rot * length
		if not _in_hex(ep, center):
			continue
		if not _seg_hits_any(origin, ep, rects, STUB_CLEAR):
			return _curved_stub(origin, ep, 0.0)
	var stop := _shorten_before(origin, perp, length, rects)
	if origin.distance_to(stop) >= OFFSHOOT_MIN_LEN * 0.5:
		return _curved_stub(origin, stop, 0.0)
	return PackedVector2Array()

## Longest point along perp (from full length down) whose stub clears every footprint.
static func _shorten_before(origin: Vector2, perp: Vector2, length: float, rects: Array) -> Vector2:
	var t := length
	while t > 0.0:
		var ep := origin + perp * t
		if not _seg_hits_any(origin, ep, rects, STUB_CLEAR):
			return ep
		t -= 6.0
	return origin

## True if any sub-segment of the polyline touches any footprint (grown by `clear`).
static func _poly_hits(poly: PackedVector2Array, rects: Array, clear: float) -> bool:
	for i in range(poly.size() - 1):
		if _seg_hits_any(poly[i], poly[i + 1], rects, clear):
			return true
	return false

## True if segment a-b touches any footprint rect grown by `clear`.
static func _seg_hits_any(a: Vector2, b: Vector2, rects: Array, clear: float) -> bool:
	for r in rects:
		if _seg_hits_rect(a, b, (r as Rect2).grow(clear)):
			return true
	return false

## Segment a-b vs an AABB: an endpoint inside, or the segment crosses any rect edge.
static func _seg_hits_rect(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	if rect.has_point(a) or rect.has_point(b):
		return true
	var p := rect.position
	var s := rect.size
	var c := [p, Vector2(p.x + s.x, p.y), p + s, Vector2(p.x, p.y + s.y)]
	for i in 4:
		if Geometry2D.segment_intersects_segment(a, b, c[i], c[(i + 1) % 4]) != null:
			return true
	return false

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

## Orient `perp` to point AWAY from a block enclosure's centroid (stubs never reach into a ring's
## interior). Unchanged when the tile has no enclosure.
static func _away_from_enclosure(origin: Vector2, perp: Vector2, centroid: Vector2, has_encl: bool) -> Vector2:
	if not has_encl:
		return perp
	var away := origin - centroid
	if away.length_squared() < 1.0:
		return perp
	return perp if perp.dot(away) >= 0.0 else -perp

## True if `p` is within `gap` of any already-placed stub root.
static func _too_close(p: Vector2, placed: Array, gap: float) -> bool:
	for q in placed:
		if p.distance_to(q as Vector2) < gap:
			return true
	return false

## Index of the first road origin at least `gap` from every already-placed root, or -1 if none.
static func _alt_origin(origins: Array, placed: Array, gap: float) -> int:
	for idx in origins.size():
		if not _too_close((origins[idx] as Array)[0], placed, gap):
			return idx
	return -1

## True if `poly` runs ALONGSIDE an existing road — a fraction (>= STUB_OVERLAP_FRAC) of its segments sit
## within STUB_OVERLAP_RADIUS of a road segment AND point roughly the same way (|dot| >= 0.7). A perpendicular
## spur or a tip-snapped connector is NOT parallel, so it isn't flagged; only "doubled" parallels are.
static func _runs_alongside_road(poly: PackedVector2Array, road_segs: Array) -> bool:
	if poly.size() < 2 or road_segs.is_empty():
		return false
	var r2 := STUB_OVERLAP_RADIUS * STUB_OVERLAP_RADIUS
	var skip2 := STUB_OVERLAP_END_SKIP * STUB_OVERLAP_END_SKIP
	var head: Vector2 = poly[0]
	var tail: Vector2 = poly[poly.size() - 1]
	var alongside := 0
	var total := 0
	for i in range(poly.size() - 1):
		var mid: Vector2 = (poly[i] + poly[i + 1]) * 0.5
		if mid.distance_squared_to(head) < skip2 or mid.distance_squared_to(tail) < skip2:
			continue   # the ends legitimately touch the origin road / a snap target — only the MIDDLE matters
		var d: Vector2 = poly[i + 1] - poly[i]
		if d.length_squared() < 1.0:
			continue
		total += 1
		var dir := d.normalized()
		for s in road_segs:
			var sa: Vector2 = (s as Array)[0]
			var sb: Vector2 = (s as Array)[1]
			if Geometry2D.get_closest_point_to_segment(mid, sa, sb).distance_squared_to(mid) > r2:
				continue
			var sd: Vector2 = sb - sa
			if sd.length_squared() >= 1.0 and absf(dir.dot(sd.normalized())) >= 0.7:
				alongside += 1
				break
	# needs a STRETCH parallel (>= 2 mid segments ~ >40u), not a single brief coincidence, to read as "doubled"
	return alongside >= 2 and float(alongside) / float(total) >= STUB_OVERLAP_FRAC

## True if any vertex OR edge-midpoint of `poly` lies inside the polygon `hull` (midpoints catch a curved
## stub that bulges across a hull edge between two outside vertices).
static func _poly_in_polygon(poly: PackedVector2Array, hull: PackedVector2Array) -> bool:
	for i in poly.size():
		if Geometry2D.is_point_in_polygon(poly[i], hull):
			return true
		if i + 1 < poly.size() and Geometry2D.is_point_in_polygon((poly[i] + poly[i + 1]) * 0.5, hull):
			return true
	return false

## True if `poly` crosses any water cell (river/sea/lake) — sampled at half the nav step. Stubs are
## cosmetic local roads and never cross water (only the major network bridges do). False without a nav.
static func _crosses_water(poly: PackedVector2Array, nav: NavGrid) -> bool:
	if nav == null or not nav.is_ready():
		return false
	var stepd := maxf(nav.step * 0.5, 1.0)
	for i in range(poly.size() - 1):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[i + 1]
		var n := maxi(1, int(ceil(a.distance_to(b) / stepd)))
		for s in n + 1:
			var c := nav.cell_of(a.lerp(b, float(s) / float(n)))
			if c.x < 0 or c.y < 0 or c.x >= nav.gw or c.y >= nav.gh:
				continue
			if nav.water(c.x, c.y) != NavGrid.WATER_LAND:
				return true
	return false

## (point, unit_tangent) pairs along network edges whose segment midpoint sits
## inside this tile's hex — the road through the tile, sampled for branch roots.
static func _road_origins_in_tile(net: RoadNetwork, center: Vector2) -> Array:
	var out: Array = []
	for eid in net.edges:
		var e: Dictionary = net.edges[eid]
		if str(e.a).begins_with("encl:") or str(e.b).begins_with("encl:"):
			continue   # a block-enclosure ring is not a through-road — never sprout stubs off it
		var geo: PackedVector2Array = e.geometry
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
