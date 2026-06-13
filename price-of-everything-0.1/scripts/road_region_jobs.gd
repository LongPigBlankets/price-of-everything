class_name RoadRegionJobs
extends RefCounted
## Phase-4 region-style job generation (roads-v2 spec §6). Given a region,
## produce the deterministic list of routing jobs that give it its character:
##
##  dense_city     routed beltway (orbital ring through inset boundary ports),
##                 minihub spokes from urban subcenters, gateway spokes, short
##                 adjacent-member links
##  sparse_city    1-2 urban minihubs wired to gateways and nearby members —
##                 never a full orbital
##  dense_rural    hub-and-spokes (urban hub if present, else most central)
##                 plus one redundant cross-link per ~4 tiles
##  sparse_rural   one through-route, then spurs to farm tiles near it
##  mountain_range at most 3 segments: cheapest pass route(s) to the far side
##
## Jobs are pure data ({kind, start, goal, tier, salt}); the caller routes them
## (tools/bake_roads synchronously, RoadWorks as budgeted orders). The dense
## city orbital overflow rule (≤50% of ring length outside member tiles, one
## ×1.5 outside-penalty rework, then accept and warn) lives in
## realize_region(), the synchronous helper the bake and tests use.

const ORBITAL_INSET := 130.0          # ring ports sit this far inside the boundary
const GATEWAY_SPOKE_CAP := 6          # max gateway spokes per dense city
const MEMBER_LINK_DIST := 750.0       # "adjacent member" link reach (~1.5 tiles)
const NEAR_PORT_SKIP := 150.0         # a hub already this close to the ring needs no spoke
const FARM_SPUR_REACH := 900.0        # farms this close to the through-route get spurs
const OUTSIDE_MULT := 1.5             # orbital rework penalty for non-member cells
const OVERFLOW_LIMIT := 0.5           # ≤50% of ring length may leave the region

# odd-q offset neighbours (flat-top, odd columns shifted down)
const NEI_ODD: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0)]
const NEI_EVEN: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(-1, -1)]

## All jobs for a region, deterministic. Returns [] for empty/unknown regions.
static func generate(region_id: String, terrain: HexMap) -> Array:
	var coords := member_coords(region_id, terrain)
	if coords.is_empty():
		return []
	var identity := RoadRegions.identity(region_id)
	match identity:
		RoadRegions.ID_DENSE_CITY:
			return _dense_city_jobs(region_id, terrain, coords)
		RoadRegions.ID_SPARSE_CITY:
			return _sparse_city_jobs(region_id, terrain, coords)
		RoadRegions.ID_DENSE_RURAL:
			return _dense_rural_jobs(region_id, terrain, coords)
		RoadRegions.ID_MOUNTAIN_RANGE:
			return _mountain_jobs(region_id, terrain, coords)
		_:
			return _sparse_rural_jobs(region_id, terrain, coords)

# ------------------------------------------------------------ identity jobs

static func _dense_city_jobs(region_id: String, terrain: HexMap, coords: Array) -> Array:
	var jobs: Array = []
	var centroid := _centroid(coords, terrain)
	var style := RoadRegions.style_for_identity(RoadRegions.ID_DENSE_CITY)
	var gateways := external_land_gateways(coords, terrain)
	var ports := orbital_ports(gateways, centroid, int(style.orbital_ports_min), int(style.orbital_ports_max))
	# 1. the beltway ring, port to port, closing the loop (trunk: A-road ring)
	for i in ports.size():
		jobs.append(_job(region_id, "orbital", ports[i], ports[(i + 1) % ports.size()], RoadNetwork.TIER_TRUNK, i))
	# 2. minihub spokes: each urban subcenter onto the ring
	var spoke_i := 0
	for coord in coords:
		if _tile_type(terrain, coord) != "urban":
			continue
		var center := _center(terrain, coord)
		var port := _nearest_point(center, ports)
		if port != Vector2.INF and center.distance_to(port) > NEAR_PORT_SKIP:
			jobs.append(_job(region_id, "spoke", center, port, RoadNetwork.TIER_LOCAL, 100 + spoke_i))
			spoke_i += 1
	# 3. gateway spokes (spaced; the world arrives at the ring)
	var picked := _spaced_pick(gateways, GATEWAY_SPOKE_CAP)
	for gi in picked.size():
		var g: Vector2 = picked[gi]
		var port2 := _nearest_point(g, ports)
		if port2 != Vector2.INF and g.distance_to(port2) > NEAR_PORT_SKIP * 0.6:
			jobs.append(_job(region_id, "gateway", g, port2, RoadNetwork.TIER_LOCAL, 200 + gi))
	# 4. short adjacent-member links (the inner street grid seed)
	jobs.append_array(_member_links(region_id, terrain, coords, 300))
	return jobs

static func _sparse_city_jobs(region_id: String, terrain: HexMap, coords: Array) -> Array:
	var jobs: Array = []
	var hubs: Array = []
	for coord in coords:
		if _tile_type(terrain, coord) == "urban":
			hubs.append(coord)
		if hubs.size() >= 2:
			break
	if hubs.is_empty():
		hubs.append(_closest_to_centroid(coords, terrain))
	var hub_pts: Array = []
	for h in hubs:
		hub_pts.append(_center(terrain, h))
	if hub_pts.size() == 2:
		jobs.append(_job(region_id, "link", hub_pts[0], hub_pts[1], RoadNetwork.TIER_LOCAL, 0))
	# each hub reaches its 2 nearest gateways
	var gateways := external_land_gateways(coords, terrain)
	for hi in hub_pts.size():
		var nearest := _nearest_n(hub_pts[hi], gateways, 2)
		for gi in nearest.size():
			jobs.append(_job(region_id, "gateway", hub_pts[hi], nearest[gi], RoadNetwork.TIER_LOCAL, 100 + hi * 10 + gi))
	# nearby members wire to their closest hub
	var li := 200
	for coord2 in coords:
		if coord2 in hubs:
			continue
		var c := _center(terrain, coord2)
		var hub_pt := _nearest_point(c, hub_pts)
		if hub_pt != Vector2.INF and c.distance_to(hub_pt) <= MEMBER_LINK_DIST:
			jobs.append(_job(region_id, "spoke", c, hub_pt, RoadNetwork.TIER_LOCAL, li))
			li += 1
	return jobs

static func _dense_rural_jobs(region_id: String, terrain: HexMap, coords: Array) -> Array:
	var jobs: Array = []
	var hub: Vector2i = Vector2i(-999, -999)
	for coord in coords:
		if _tile_type(terrain, coord) == "urban":
			hub = coord
			break
	if hub == Vector2i(-999, -999):
		hub = _closest_to_centroid(coords, terrain)
	var hub_pt := _center(terrain, hub)
	var others: Array = []
	for coord2 in coords:
		if coord2 != hub:
			others.append(coord2)
	for i in others.size():
		var c := _center(terrain, others[i])
		var tier := RoadNetwork.TIER_TRUNK if hub_pt.distance_to(c) > 1500.0 else RoadNetwork.TIER_LOCAL
		jobs.append(_job(region_id, "spoke", hub_pt, c, tier, i))
	# one redundant cross-link per ~4 tiles
	var n_links := maxi(coords.size() / 4, 0)
	for li in n_links:
		var a_i: int = (li * 4 + 1) % others.size()
		var b_i: int = (li * 4 + 3) % others.size()
		if a_i == b_i:
			continue
		jobs.append(_job(region_id, "link", _center(terrain, others[a_i]), _center(terrain, others[b_i]), RoadNetwork.TIER_LOCAL, 100 + li))
	return jobs

static func _sparse_rural_jobs(region_id: String, terrain: HexMap, coords: Array) -> Array:
	var jobs: Array = []
	var ends := _through_endpoints(coords, terrain)
	if ends.is_empty():
		return jobs
	var a: Vector2 = ends[0]
	var b: Vector2 = ends[1]
	var tier := RoadNetwork.TIER_TRUNK if a.distance_to(b) > 1500.0 else RoadNetwork.TIER_LOCAL
	jobs.append(_job(region_id, "through", a, b, tier, 0))
	# farm spurs: member tiles holding anchor buildings near the through-line
	var style := RoadRegions.style_for_identity(RoadRegions.ID_SPARSE_RURAL)
	var anchor_ids: Array = style.get("rural_anchor_building_ids", [])
	var si := 100
	for coord in coords:
		var tile_id := str(terrain.tiles[coord].get("id", ""))
		if not _tile_has_any_building(tile_id, anchor_ids):
			continue
		var c := _center(terrain, coord)
		var on_line := _closest_on_segment(c, a, b)
		var d := c.distance_to(on_line)
		if d > 40.0 and d <= FARM_SPUR_REACH:
			jobs.append(_job(region_id, "spur", c, on_line, RoadNetwork.TIER_LOCAL, si))
			si += 1
	return jobs

static func _mountain_jobs(region_id: String, terrain: HexMap, coords: Array) -> Array:
	# deliberately sparse: the cheapest crossing(s) to the far side, max 3
	var jobs: Array = []
	var gateways := external_land_gateways(coords, terrain)
	if gateways.size() < 2:
		return jobs
	var style := RoadRegions.style_for_identity(RoadRegions.ID_MOUNTAIN_RANGE)
	var max_segments := int(style.get("max_segments", 3))
	var pairs := _distant_pairs(gateways, max_segments)
	for i in pairs.size():
		var pa: Vector2 = pairs[i][0]
		var pb: Vector2 = pairs[i][1]
		var tier := RoadNetwork.TIER_TRUNK if pa.distance_to(pb) > 1500.0 else RoadNetwork.TIER_LOCAL
		jobs.append(_job(region_id, "pass", pa, pb, tier, i))
	return jobs

# ------------------------------------------------- synchronous realization

## Route + commit a region's jobs synchronously (bake, tests). Implements the
## orbital overflow rule: realize the ring plainly; if more than OVERFLOW_LIMIT
## of its realized length lies outside member tiles, re-route ALL ring segments
## once with the ×1.5 outside-region penalty; then accept (and warn).
## Returns {jobs, committed, failed, overflow, reworked}.
static func realize_region(region_id: String, terrain: HexMap, nav: NavGrid, network: RoadNetwork, realizer: RoadRealizer, turn: int) -> Dictionary:
	var jobs := generate(region_id, terrain)
	var coords := member_coords(region_id, terrain)
	var identity := RoadRegions.identity(region_id)
	var ring_jobs: Array = []
	var other_jobs: Array = []
	for job in jobs:
		if str(job.kind) == "orbital":
			ring_jobs.append(job)
		else:
			other_jobs.append(job)
	var committed := 0
	var failed := 0
	var overflow := 0.0
	var reworked := false
	# ring first (reveal/network grows trunk-first); two-pass overflow rule
	if not ring_jobs.is_empty():
		var ring_results: Array = []
		for job in ring_jobs:
			ring_results.append(realizer.route(nav, network, job.start, job.goal, {
				"identity": identity, "salt": int(job.salt), "thorough": true}))
		overflow = ring_overflow_fraction(ring_results, coords, terrain)
		if overflow > OVERFLOW_LIMIT:
			reworked = true
			var rering: Array = []
			for job in ring_jobs:
				rering.append(realizer.route(nav, network, job.start, job.goal, {
					"identity": identity, "salt": int(job.salt), "thorough": true,
					"region_coords": coords, "outside_mult": OUTSIDE_MULT}))
			var re_overflow := ring_overflow_fraction(rering, coords, terrain)
			if re_overflow > OVERFLOW_LIMIT:
				push_warning("RoadRegionJobs: %s orbital still %.0f%% outside after rework — accepting (heightmap wins)." % [region_id, re_overflow * 100.0])
			ring_results = rering
			overflow = re_overflow
		for i in ring_jobs.size():
			var res: Dictionary = ring_results[i]
			if bool(res.get("ok", false)):
				_commit_job(network, realizer, region_id, ring_jobs[i], res, turn)
				committed += 1
			else:
				failed += 1
	for job2 in other_jobs:
		var res2 := realizer.route(nav, network, job2.start, job2.goal, {
			"identity": identity, "salt": int(job2.salt), "thorough": true})
		if bool(res2.get("ok", false)):
			_commit_job(network, realizer, region_id, job2, res2, turn)
			committed += 1
		else:
			failed += 1
	return {"jobs": jobs.size(), "committed": committed, "failed": failed,
		"overflow": overflow, "reworked": reworked}

static func _commit_job(network: RoadNetwork, realizer: RoadRealizer, region_id: String, job: Dictionary, res: Dictionary, turn: int) -> void:
	var a := network.add_junction(job.start, Vector2i.ZERO)
	var b := network.add_junction(job.goal, Vector2i.ZERO)
	realizer.commit(network, str(a.id), str(b.id), str(job.tier), res, turn)

## Length-weighted fraction of the realized ring lying OUTSIDE member tiles.
static func ring_overflow_fraction(ring_results: Array, coords: Array, terrain: HexMap) -> float:
	var members := {}
	for c in coords:
		members[c] = true
	var inside := 0.0
	var total := 0.0
	for res in ring_results:
		if not bool(res.get("ok", false)):
			continue
		var pts: PackedVector2Array = res.geometry
		for i in range(1, pts.size()):
			var seg := pts[i - 1].distance_to(pts[i])
			total += seg
			var mid := pts[i - 1].lerp(pts[i], 0.5)
			var coord: Vector2i = terrain.tile_coord_for_map_coord(terrain.local_to_map(mid))
			if members.has(coord):
				inside += seg
	return 0.0 if total <= 0.0 else 1.0 - inside / total

# ---------------------------------------------------------------- geometry

static func member_coords(region_id: String, terrain: HexMap) -> Array:
	var out: Array = []
	for tile_id in RoadRegions.tiles(region_id):
		var coord: Vector2i = terrain.id_to_coord(str(tile_id))
		if terrain.tiles.has(coord):
			out.append(coord)
	out.sort()
	return out

## Midpoints of every member edge facing an external LAND tile, sorted by
## angle around the region centroid (deterministic).
static func external_land_gateways(coords: Array, terrain: HexMap) -> Array:
	var members := {}
	for c in coords:
		members[c] = true
	var centroid := _centroid(coords, terrain)
	var gateways: Array = []
	for c2 in coords:
		var coord: Vector2i = c2
		var neighbours := NEI_ODD if coord.x % 2 != 0 else NEI_EVEN
		for off in neighbours:
			var nb: Vector2i = coord + off
			if members.has(nb) or not terrain.tiles.has(nb):
				continue
			var nb_type := _tile_type(terrain, nb)
			if nb_type == "sea" or nb_type == "deep_sea":
				continue
			gateways.append(_center(terrain, coord).lerp(_center(terrain, nb), 0.5))
	gateways.sort_custom(func(a, b) -> bool:
		var aa := (a as Vector2 - centroid).angle()
		var ab := (b as Vector2 - centroid).angle()
		return aa < ab if aa != ab else (a as Vector2).x < (b as Vector2).x)
	return gateways

## N ring ports: gateway midpoints thinned to even angular spacing and inset
## toward the centroid (the beltway runs just inside the boundary). Coastal
## stretches simply have no gateways there — the realizer hugs land anyway.
static func orbital_ports(gateways: Array, centroid: Vector2, n_min: int, n_max: int) -> Array:
	if gateways.is_empty():
		return []
	var n := clampi(gateways.size(), mini(n_min, gateways.size()), n_max)
	var picked := _spaced_pick(gateways, n)
	var ports: Array = []
	for g in picked:
		var v: Vector2 = (g as Vector2) - centroid
		var inset := maxf(v.length() - ORBITAL_INSET, v.length() * 0.45)
		ports.append(centroid + v.normalized() * inset)
	return ports

## Pick up to n entries maximally spread by angular order (input pre-sorted).
static func _spaced_pick(sorted_pts: Array, n: int) -> Array:
	if sorted_pts.size() <= n:
		return sorted_pts.duplicate()
	var out: Array = []
	for i in n:
		out.append(sorted_pts[int(floor(float(i) * float(sorted_pts.size()) / float(n)))])
	return out

static func _through_endpoints(coords: Array, terrain: HexMap) -> Array:
	var pts: Array = external_land_gateways(coords, terrain)
	if pts.size() < 2:
		pts = []
		for c in coords:
			pts.append(_center(terrain, c))
	if pts.size() < 2:
		return []
	var best_a := Vector2.ZERO
	var best_b := Vector2.ZERO
	var best_d := -1.0
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			var d: float = (pts[i] as Vector2).distance_squared_to(pts[j])
			if d > best_d:
				best_d = d
				best_a = pts[i]
				best_b = pts[j]
	return [best_a, best_b]

## Up to n far-apart gateway pairs (first = the farthest pair; later pairs keep
## their endpoints away from already-used ones).
static func _distant_pairs(gateways: Array, n: int) -> Array:
	var pairs: Array = []
	var used: Array = []
	for _k in n:
		var best_d := -1.0
		var best: Array = []
		for i in gateways.size():
			for j in range(i + 1, gateways.size()):
				var a: Vector2 = gateways[i]
				var b: Vector2 = gateways[j]
				var clear := true
				for u in used:
					if (u as Vector2).distance_to(a) < 800.0 or (u as Vector2).distance_to(b) < 800.0:
						clear = false
						break
				if not clear:
					continue
				var d := a.distance_squared_to(b)
				if d > best_d:
					best_d = d
					best = [a, b]
		if best.is_empty():
			break
		pairs.append(best)
		used.append(best[0])
		used.append(best[1])
	return pairs

static func _member_links(region_id: String, terrain: HexMap, coords: Array, salt_base: int) -> Array:
	var jobs: Array = []
	var li := 0
	for i in coords.size():
		for j in range(i + 1, coords.size()):
			var a := _center(terrain, coords[i])
			var b := _center(terrain, coords[j])
			if a.distance_to(b) <= MEMBER_LINK_DIST:
				jobs.append(_job(region_id, "link", a, b, RoadNetwork.TIER_LOCAL, salt_base + li))
				li += 1
	return jobs

# ------------------------------------------------------------------ helpers

static func _job(region_id: String, kind: String, start: Vector2, goal: Vector2, tier: String, index: int) -> Dictionary:
	return {
		"region_id": region_id, "kind": kind, "start": start, "goal": goal,
		"tier": tier, "salt": RoadHash.pick("region|%s|%s|%d" % [region_id, kind, index], 1 << 30),
	}

static func _tile_type(terrain: HexMap, coord: Vector2i) -> String:
	return str(terrain.tiles[coord].get("type", "")).strip_edges().to_lower()

static func _center(terrain: HexMap, coord: Vector2i) -> Vector2:
	return terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))

static func _centroid(coords: Array, terrain: HexMap) -> Vector2:
	var c := Vector2.ZERO
	for coord in coords:
		c += _center(terrain, coord)
	return c / float(coords.size())

static func _closest_to_centroid(coords: Array, terrain: HexMap) -> Vector2i:
	var centroid := _centroid(coords, terrain)
	var best: Vector2i = coords[0]
	var best_d := 1e30
	for coord in coords:
		var d := _center(terrain, coord).distance_squared_to(centroid)
		if d < best_d:
			best_d = d
			best = coord
	return best

static func _nearest_point(from: Vector2, pts: Array) -> Vector2:
	var best := Vector2.INF
	var best_d := 1e30
	for p in pts:
		var d: float = (p as Vector2).distance_squared_to(from)
		if d < best_d:
			best_d = d
			best = p
	return best

static func _nearest_n(from: Vector2, pts: Array, n: int) -> Array:
	var sorted_pts := pts.duplicate()
	sorted_pts.sort_custom(func(a, b) -> bool:
		return (a as Vector2).distance_squared_to(from) < (b as Vector2).distance_squared_to(from))
	return sorted_pts.slice(0, n)

static func _closest_on_segment(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab := b - a
	var denom := maxf(ab.length_squared(), 0.0001)
	var t := clampf((p - a).dot(ab) / denom, 0.0, 1.0)
	return a + ab * t

static func _tile_has_any_building(tile_id: String, building_ids: Array) -> bool:
	for iid in MatchState.tile_buildings.get(tile_id, []):
		if str(MatchState.get_building(str(iid)).get("building_id", "")) in building_ids:
			return true
	return false
