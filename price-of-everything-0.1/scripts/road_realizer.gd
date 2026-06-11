class_name RoadRealizer
extends RefCounted
## Height-aware road router (roads-v2 spec 2.3). Routes world-space jobs over
## the baked NavGrid with the principle cost model, then smooths and emits
## bridges where the route uses a predetermined crossing gate.
##
## Architecture forced by the Phase-0 benchmark (G3: ~16 us/expansion in
## GDScript; a direct 12u trunk route costs seconds):
## - jobs longer than FINE_DIRECT_MAX route COARSE-FIRST on NavGrid's 36u
##   downsample, then refine along the coarse polyline at 12u inside a tight
##   corridor;
## - all fine state lives in CORRIDOR-LOCAL arrays (the full-map state arrays
##   of the preview prototype cost ~120 MB; a corridor costs a few hundred KB
##   and the buffers are reused across jobs);
## - binary heap + parents on packed arrays, no Dictionaries in the hot loop.
##
## Determinism: cost jitter and quartile crossings key off RoadHash; identical
## inputs produce identical geometry (asserted by tests).

const FINE_DIRECT_MAX := 1500.0      # straight-line cutoff for single-level routing
const DIRECT_CAPSULE := 480.0        # corridor radius for direct fine jobs
const REFINE_RADIUS := 110.0         # corridor radius around the coarse polyline
const REFINE_SEGMENT := 560.0        # coarse path is refined in chunks of this length
const MAX_FINE_EXPANSIONS := 90000
const MAX_COARSE_EXPANSIONS := 60000
const ROUTE_WEIGHT := 1.08           # epsilon-weighted A*

## Cost table (spec Appendix A — change knowingly).
const COST_ALTITUDE_PER_LEVEL := 0.5     # decision #2: +50% per level crossed
const COST_VALLEY := 0.03                # prefer the lowest path
const COST_HUG_DISCOUNT := 0.85          # 30-60 u from water
const COST_HUG_CROWD := 1.15             # 13-30 u from water
const COST_GRADIENT_K := 1.5             # serpentine: across-slope is cheap, up-slope is not
const STEEP_GRAD := 1.0                  # |level gradient| (per cell pair) considered steep
const COST_REUSE := 0.6                  # within ~24 u of the network
const TURN_45 := 0.18
const TURN_90 := 0.85
const TURN_135 := 3.0
const HAIRPIN_WAIVER := 0.25             # >=135 turns on steep climbs cost this fraction
const JITTER_BY_IDENTITY := {
	"dense_city": 0.018, "sparse_city": 0.035, "dense_rural": 0.045,
	"sparse_rural": 0.06, "mountain_range": 0.07,
}
const TURN_MULT_BY_IDENTITY := {
	"dense_city": 0.92, "sparse_city": 1.0, "dense_rural": 1.2,
	"sparse_rural": 1.3, "mountain_range": 1.45,
}

const DIRS := [
	Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
]
const DIR_LEN := [1.0, 1.41421356, 1.0, 1.41421356, 1.0, 1.41421356, 1.0, 1.41421356]

# Reused scratch buffers (corridor-local).
var _heap_state := PackedInt32Array()
var _heap_cost := PackedFloat32Array()
var _heap_size := 0
var _score := PackedFloat32Array()
var _parent := PackedInt32Array()
var _closed := PackedByteArray()
var _passable := PackedByteArray()
var _gate_pass := PackedByteArray()

## Route a job. opts: {identity: String, salt: int, retry_serpentine: bool}.
## Returns {ok, geometry: PackedVector2Array, tiles: Array[Vector2i],
##          bridges: Array, expansions: int, reason: String}.
func route(nav: NavGrid, network: RoadNetwork, start: Vector2, goal: Vector2, opts: Dictionary = {}) -> Dictionary:
	if not nav.is_ready():
		return {"ok": false, "reason": "navgrid_missing"}
	var identity := str(opts.get("identity", "sparse_rural"))
	var salt := int(opts.get("salt", 0))
	var grad_k := COST_GRADIENT_K
	var attempt := _route_once(nav, network, start, goal, identity, salt, grad_k)
	if attempt.ok and bool(opts.get("retry_serpentine", true)):
		var climb := _total_climb(attempt.raw_levels)
		if climb >= 2 and _direction_reversals(attempt.raw_points) < 2:
			# serpentine post-check (spec 2.3): steep climbs must wind
			var retry := _route_once(nav, network, start, goal, identity, salt, grad_k * 2.0)
			if retry.ok:
				attempt = retry
	if not attempt.ok:
		return attempt
	var smoothed := _smooth(_thin(attempt.raw_points, 30.0), 1)
	return {
		"ok": true,
		"geometry": smoothed,
		"tiles": _tiles_crossed(smoothed),
		"bridges": attempt.bridges,
		"expansions": attempt.expansions,
		"reason": "",
	}

## Commit a routed job into the network: agree gateway tangents (first writer
## wins) and store the edge with its bridges.
func commit(network: RoadNetwork, a_id: String, b_id: String, tier: String, result: Dictionary, turn: int) -> Dictionary:
	var geometry: PackedVector2Array = result.geometry
	if geometry.size() >= 2:
		network.agree_tangent(a_id, (geometry[1] - geometry[0]).normalized())
		network.agree_tangent(b_id, (geometry[geometry.size() - 2] - geometry[geometry.size() - 1]).normalized())
	return network.add_edge(a_id, b_id, tier, geometry, result.tiles, result.bridges, turn)

# ----------------------------------------------------------------- pipeline

func _route_once(nav: NavGrid, network: RoadNetwork, start: Vector2, goal: Vector2, identity: String, salt: int, grad_k: float) -> Dictionary:
	if start.distance_to(goal) <= FINE_DIRECT_MAX:
		return _route_fine(nav, network, [start, goal], DIRECT_CAPSULE, identity, salt, grad_k, start, goal)
	var coarse := _route_coarse(nav, start, goal)
	if not coarse.ok:
		return {"ok": false, "reason": "coarse_" + str(coarse.reason)}
	# refine along the coarse polyline in overlapping chunks
	var waypoints := _resample(coarse.path, REFINE_SEGMENT)
	var full_points: Array[Vector2] = []
	var full_levels: Array[int] = []
	var bridges: Array = []
	var expansions := int(coarse.expansions)
	var cursor := start
	for i in range(1, waypoints.size()):
		var target: Vector2 = goal if i == waypoints.size() - 1 else waypoints[i]
		var corridor: Array = [cursor, waypoints[i]]
		var seg := _route_fine(nav, network, corridor, REFINE_RADIUS, identity, salt + i, grad_k, cursor, target)
		if not seg.ok:
			# fall back to a wider direct attempt for this chunk
			seg = _route_fine(nav, network, [cursor, target], DIRECT_CAPSULE, identity, salt + i, grad_k, cursor, target)
		if not seg.ok:
			return {"ok": false, "reason": "refine_failed:" + str(seg.reason)}
		for p in seg.raw_points:
			if full_points.is_empty() or full_points[full_points.size() - 1].distance_squared_to(p) > 1.0:
				full_points.append(p)
		for l in seg.raw_levels:
			full_levels.append(l)
		for b in seg.bridges:
			var dup := false
			for known in bridges:
				if known.point.distance_squared_to(b.point) < 1.0:
					dup = true
					break
			if not dup:
				bridges.append(b)
		expansions += int(seg.expansions)
		cursor = full_points[full_points.size() - 1]
	return {
		"ok": true, "raw_points": full_points, "raw_levels": full_levels,
		"bridges": bridges, "expansions": expansions,
	}

# -------------------------------------------------------------- coarse pass

func _route_coarse(nav: NavGrid, start: Vector2, goal: Vector2) -> Dictionary:
	var gw := nav.coarse_gw
	var gh := nav.coarse_gh
	var grid := nav.coarse
	var s := _nearest_coarse_land(nav, start)
	var g := _nearest_coarse_land(nav, goal)
	if s < 0 or g < 0:
		return {"ok": false, "reason": "no_land_endpoint"}
	var count := gw * gh
	_ensure_scratch(count)
	_heap_size = 0
	_closed.fill(0)
	_parent.fill(-1)
	var sx := s % gw
	var sy := int(s / float(gw))
	var gx := g % gw
	var gy := int(g / float(gw))
	_score[s] = 0.0
	_heap_push(s, Vector2(sx, sy).distance_to(Vector2(gx, gy)) * nav.coarse_step * ROUTE_WEIGHT)
	var expansions := 0
	while _heap_size > 0:
		var cell := _heap_pop()
		if _closed[cell] == 1:
			continue
		_closed[cell] = 1
		expansions += 1
		if expansions > MAX_COARSE_EXPANSIONS:
			return {"ok": false, "reason": "expansion_cap"}
		if cell == g:
			var path: Array[Vector2] = []
			var cur := cell
			while cur >= 0:
				path.append(nav.coarse_world_of(cur % gw, int(cur / float(gw))))
				cur = _parent[cur]
			path.reverse()
			path[0] = start
			path[path.size() - 1] = goal
			return {"ok": true, "path": path, "expansions": expansions}
		var cx := cell % gw
		var cy := int(cell / float(gw))
		var cur_band := grid[cell] & 0x0F if grid[cell] != 0xFF else 0
		for d in 8:
			var nx: int = cx + DIRS[d].x
			var ny: int = cy + DIRS[d].y
			if nx < 0 or ny < 0 or nx >= gw or ny >= gh:
				continue
			var ncell := ny * gw + nx
			if grid[ncell] == 0xFF or _closed[ncell] == 1:
				continue
			var nband := grid[ncell] & 0x0F
			var move: float = nav.coarse_step * DIR_LEN[d]
			move *= 1.0 + COST_ALTITUDE_PER_LEVEL * absf(float(nband - cur_band))
			move *= 1.0 + COST_VALLEY * maxf(float(nband - 1), 0.0)
			var ng := _score[cell] + move
			if _parent[ncell] == -1 or ng < _score[ncell]:
				if _closed[ncell] == 0:
					_score[ncell] = ng
					_parent[ncell] = cell
					var h := Vector2(nx, ny).distance_to(Vector2(gx, gy)) * nav.coarse_step
					_heap_push(ncell, ng + h * ROUTE_WEIGHT)
	return {"ok": false, "reason": "no_route"}

func _nearest_coarse_land(nav: NavGrid, world: Vector2) -> int:
	var c := nav.coarse_cell_of(world)
	var gw := nav.coarse_gw
	var gh := nav.coarse_gh
	for radius in range(0, 16):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var nx := c.x + dx
				var ny := c.y + dy
				if nx < 0 or ny < 0 or nx >= gw or ny >= gh:
					continue
				if nav.coarse[ny * gw + nx] != 0xFF:
					return ny * gw + nx
	return -1

# ---------------------------------------------------------------- fine pass

## Fine A* inside a corridor around `corridor` (a 2-point capsule). State =
## (corridor-local cell, incoming octant). Returns raw lattice points + the
## level sequence (for the serpentine post-check) + bridges used.
func _route_fine(nav: NavGrid, network: RoadNetwork, corridor: Array, radius: float, identity: String, salt: int, grad_k: float, start: Vector2, goal: Vector2) -> Dictionary:
	var a: Vector2 = corridor[0]
	var b: Vector2 = corridor[1]
	var lo := Vector2(minf(a.x, b.x) - radius, minf(a.y, b.y) - radius)
	var hi := Vector2(maxf(a.x, b.x) + radius, maxf(a.y, b.y) + radius)
	var c0 := nav.cell_of(lo)
	var c1 := nav.cell_of(hi)
	var lw := c1.x - c0.x + 1
	var lh := c1.y - c0.y + 1
	if lw < 2 or lh < 2:
		return {"ok": false, "reason": "degenerate_corridor"}
	var lcount := lw * lh
	_build_passable(nav, c0, lw, lh, a, b, radius)
	var s_local := _nearest_passable_local(nav, c0, lw, lh, start)
	var g_local := _nearest_passable_local(nav, c0, lw, lh, goal)
	if s_local < 0 or g_local < 0:
		return {"ok": false, "reason": "no_passable_endpoint"}
	var states := lcount * 8
	_ensure_scratch(states)
	_heap_size = 0
	_closed.fill(0)
	_parent.fill(-1)
	var gx_l := g_local % lw
	var gy_l := int(g_local / float(lw))
	var turn_mult := float(TURN_MULT_BY_IDENTITY.get(identity, 1.0))
	var jitter_amp := float(JITTER_BY_IDENTITY.get(identity, 0.06))
	var step := nav.step
	for d0 in 8:
		var st := s_local * 8 + d0
		_score[st] = 0.0
		_parent[st] = -2   # root marker (distinct from unvisited -1)
		var sx := s_local % lw
		var sy := int(s_local / float(lw))
		_heap_push(st, Vector2(sx - gx_l, sy - gy_l).length() * step * ROUTE_WEIGHT)
	var expansions := 0
	var goal_state := -1
	while _heap_size > 0:
		var state := _heap_pop()
		if _closed[state] == 1:
			continue
		_closed[state] = 1
		expansions += 1
		if expansions > MAX_FINE_EXPANSIONS:
			return {"ok": false, "reason": "expansion_cap"}
		var cell := int(state / 8.0)
		if cell == g_local:
			goal_state = state
			break
		var dir := state % 8
		var cx := cell % lw
		var cy := int(cell / float(lw))
		var nav_idx := (c0.y + cy) * nav.gw + (c0.x + cx)
		var cur_level := (nav.cells[nav_idx] & 0x0F) - 1
		var cur_g := _score[state]
		for nd in 8:
			var nx: int = cx + DIRS[nd].x
			var ny: int = cy + DIRS[nd].y
			if nx < 0 or ny < 0 or nx >= lw or ny >= lh:
				continue
			var ncell := ny * lw + nx
			if _passable[ncell] == 0:
				continue
			var nstate := ncell * 8 + nd
			if _closed[nstate] == 1:
				continue
			var n_nav := (c0.y + ny) * nav.gw + (c0.x + nx)
			var next_level := (nav.cells[n_nav] & 0x0F) - 1
			var move := step * float(DIR_LEN[nd])
			var dl := next_level - cur_level
			move *= 1.0 + COST_ALTITUDE_PER_LEVEL * absf(float(dl))
			move *= 1.0 + COST_VALLEY * maxf(float(next_level), 0.0)
			# river hug band from the baked water distance
			var wd := float(nav.dist4[n_nav]) * 4.0
			if wd >= 30.0 and wd <= 60.0:
				move *= COST_HUG_DISCOUNT
			elif wd > 13.0 and wd < 30.0:
				move *= COST_HUG_CROWD
			# serpentines: moving along the height gradient on steep ground is dear
			var grad := _level_gradient(nav, n_nav)
			if grad.length_squared() >= STEEP_GRAD:
				var mdir := Vector2(DIRS[nd]).normalized()
				move *= 1.0 + grad_k * absf(mdir.dot(grad.normalized())) * clampf(grad.length() / 2.0, 0.0, 1.0)
			# reuse discount: merge with the existing network
			if network != null and network.has_any_edges():
				if network.near_network(nav.world_of(c0.x + nx, c0.y + ny)):
					move *= COST_REUSE
			# organic wobble
			move *= 1.0 + RoadHash.jitter01(c0.x + nx, c0.y + ny, salt) * jitter_amp
			# turn penalty (+ hairpin waiver on steep climbs)
			var delta: int = absi(dir - nd)
			delta = mini(delta, 8 - delta)
			var turn := 0.0
			match delta:
				1: turn = TURN_45 * step
				2: turn = TURN_90 * step
				3, 4: turn = TURN_135 * step
			if delta >= 3 and grad.length_squared() >= STEEP_GRAD and absi(dl) >= 1:
				turn *= HAIRPIN_WAIVER
			move += turn * turn_mult
			var ng := cur_g + move
			if _parent[nstate] == -1 or ng < _score[nstate]:
				_score[nstate] = ng
				_parent[nstate] = state
				var h := Vector2(nx - gx_l, ny - gy_l).length() * step
				_heap_push(nstate, ng + h * ROUTE_WEIGHT)
	if goal_state < 0:
		return {"ok": false, "reason": "no_route"}
	# reconstruct: points + levels + bridges (gate traversals)
	var raw_points: Array[Vector2] = []
	var raw_levels: Array[int] = []
	var cursor := goal_state
	var guard := 0
	while cursor >= 0 and guard < 200000:
		guard += 1
		var cell2 := int(cursor / 8.0)
		var wx := c0.x + (cell2 % lw)
		var wy := c0.y + int(cell2 / float(lw))
		var nav_i := wy * nav.gw + wx
		if raw_points.is_empty() or raw_points[raw_points.size() - 1].distance_squared_to(nav.world_of(wx, wy)) > 0.5:
			raw_points.append(nav.world_of(wx, wy))
			raw_levels.append((nav.cells[nav_i] & 0x0F) - 1)
		var parent := _parent[cursor]
		cursor = parent if parent != -2 else -1
	raw_points.reverse()
	raw_levels.reverse()
	var bridges := _bridges_for_path(nav, raw_points)
	return {
		"ok": true, "raw_points": raw_points, "raw_levels": raw_levels,
		"bridges": bridges, "expansions": expansions,
	}

## Corridor-local passability: land inside the capsule, plus river cells
## whitelisted near predetermined crossing gates (principle (a)), minus
## forest obstacle discs (spec section 1).
func _build_passable(nav: NavGrid, c0: Vector2i, lw: int, lh: int, a: Vector2, b: Vector2, radius: float) -> void:
	var lcount := lw * lh
	if _passable.size() < lcount:
		_passable.resize(lcount)
	var seg := b - a
	var seg_len_sq := maxf(seg.length_squared(), 1.0)
	var r_sq := radius * radius
	for ly in lh:
		for lx in lw:
			var li := ly * lw + lx
			var world := nav.world_of(c0.x + lx, c0.y + ly)
			var t := clampf((world - a).dot(seg) / seg_len_sq, 0.0, 1.0)
			if world.distance_squared_to(a + seg * t) > r_sq:
				_passable[li] = 0
				continue
			var w := nav.cells[(c0.y + ly) * nav.gw + (c0.x + lx)] >> 4
			_passable[li] = 1 if w == NavGrid.WATER_LAND else 0
	# crossing gates re-open river cells along the bridge line
	var rect := Rect2(nav.world_of(c0.x, c0.y), Vector2(lw * nav.step, lh * nav.step))
	for crossing in RoadCrossings.in_rect(rect.grow(RoadCrossings.GATE_OFFSET + RoadCrossings.GATE_RADIUS)):
		var ga: Vector2 = crossing.gate_a
		var gb: Vector2 = crossing.gate_b
		var pad := RoadCrossings.GATE_RADIUS
		var lo := Vector2(minf(ga.x, gb.x) - pad, minf(ga.y, gb.y) - pad)
		var hi := Vector2(maxf(ga.x, gb.x) + pad, maxf(ga.y, gb.y) + pad)
		var g0 := nav.cell_of(lo)
		var g1 := nav.cell_of(hi)
		for ny in range(maxi(g0.y, c0.y), mini(g1.y, c0.y + lh - 1) + 1):
			for nx in range(maxi(g0.x, c0.x), mini(g1.x, c0.x + lw - 1) + 1):
				var world2 := nav.world_of(nx, ny)
				if _dist_to_segment(world2, ga, gb) <= pad:
					_passable[(ny - c0.y) * lw + (nx - c0.x)] = 1
	# forest discs are hard obstacles
	for disc in _forest_discs_in(nav, c0, lw, lh):
		var dc: Vector2 = disc.center
		var dr: float = disc.radius + 8.0   # FOREST_ROAD_BUFFER
		var d0 := nav.cell_of(dc - Vector2(dr, dr))
		var d1 := nav.cell_of(dc + Vector2(dr, dr))
		for ny2 in range(maxi(d0.y, c0.y), mini(d1.y, c0.y + lh - 1) + 1):
			for nx2 in range(maxi(d0.x, c0.x), mini(d1.x, c0.x + lw - 1) + 1):
				if nav.world_of(nx2, ny2).distance_squared_to(dc) <= dr * dr:
					_passable[(ny2 - c0.y) * lw + (nx2 - c0.x)] = 0

## Forest obstacle discs intersecting the corridor, derived live from
## MatchState buildings via the shared ForestFootprint (never cached across
## jobs — forests are plantable/removable).
func _forest_discs_in(nav: NavGrid, c0: Vector2i, lw: int, lh: int) -> Array:
	var out: Array = []
	var terrain: HexMap = _terrain()
	if terrain == null:
		return out
	var rect := Rect2(nav.world_of(c0.x, c0.y), Vector2(lw * nav.step, lh * nav.step)).grow(80.0)
	for instance_id in MatchState.buildings:
		var building: Dictionary = MatchState.buildings[instance_id]
		var building_id := str(building.get("building_id", ""))
		if not ForestFootprint.is_forest(building_id):
			continue
		var tile_id := str(building.get("tile_id", ""))
		var coord: Vector2i = terrain.id_to_coord(tile_id)
		if not terrain.tiles.has(coord):
			continue
		var center: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
		if not rect.has_point(center):
			continue
		var paths := _river_paths_for(terrain, coord)
		var lake := RiverGeometry.lake_ellipse(terrain.tiles[coord], terrain.river_properties, center)
		out.append(ForestFootprint.footprint(str(instance_id), tile_id, coord, center, paths, lake))
	return out

func _river_paths_for(terrain: HexMap, coord: Vector2i) -> Array:
	return RiverGeometry.arms(terrain.tiles[coord], terrain.river_properties, terrain.map_to_local(terrain.map_coord_for_tile_coord(coord)))

func _terrain() -> HexMap:
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return null
	var found := (loop as SceneTree).get_nodes_in_group("hex_map")
	return found[0] as HexMap if not found.is_empty() else null

# ------------------------------------------------------------------ helpers

func _level_gradient(nav: NavGrid, nav_idx: int) -> Vector2:
	var gw := nav.gw
	var x := nav_idx % gw
	var y := int(nav_idx / float(gw))
	if x <= 0 or y <= 0 or x >= gw - 1 or y >= nav.gh - 1:
		return Vector2.ZERO
	var gx := float((nav.cells[y * gw + x + 1] & 0x0F) - (nav.cells[y * gw + x - 1] & 0x0F))
	var gy := float((nav.cells[(y + 1) * gw + x] & 0x0F) - (nav.cells[(y - 1) * gw + x] & 0x0F))
	return Vector2(gx, gy)

func _nearest_passable_local(nav: NavGrid, c0: Vector2i, lw: int, lh: int, world: Vector2) -> int:
	var c := nav.cell_of(world)
	var lx := clampi(c.x - c0.x, 0, lw - 1)
	var ly := clampi(c.y - c0.y, 0, lh - 1)
	for radius in range(0, 24):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var nx := lx + dx
				var ny := ly + dy
				if nx < 0 or ny < 0 or nx >= lw or ny >= lh:
					continue
				if _passable[ny * lw + nx] == 1:
					return ny * lw + nx
	return -1

func _bridges_for_path(nav: NavGrid, points: Array[Vector2]) -> Array:
	var bridges: Array = []
	for p in points:
		var c := nav.cell_of(p)
		if nav.water(c.x, c.y) != NavGrid.WATER_RIVER:
			continue
		var best: Dictionary = {}
		var best_d := 1e30
		for crossing in RoadCrossings.in_rect(Rect2(p - Vector2(120, 120), Vector2(240, 240))):
			var d: float = (crossing.point as Vector2).distance_squared_to(p)
			if d < best_d:
				best_d = d
				best = crossing
		if best.is_empty():
			continue
		var dup := false
		for known in bridges:
			if known.point.distance_squared_to(best.point) < 1.0:
				dup = true
				break
		if not dup:
			bridges.append({"point": best.point, "tangent": best.bridge_tangent})
	return bridges

func _total_climb(levels: Array[int]) -> int:
	if levels.is_empty():
		return 0
	var lo := levels[0]
	var hi := levels[0]
	for l in levels:
		lo = mini(lo, l)
		hi = maxi(hi, l)
	return hi - lo

func _direction_reversals(points: Array[Vector2]) -> int:
	if points.size() < 5:
		return 0
	var reversals := 0
	var last_sign := 0
	for i in range(2, points.size()):
		var v1 := points[i - 1] - points[i - 2]
		var v2 := points[i] - points[i - 1]
		var cross := v1.x * v2.y - v1.y * v2.x
		var angle := absf(v1.angle_to(v2))
		if angle < 0.6:
			continue
		var s := 1 if cross > 0.0 else -1
		if last_sign != 0 and s != last_sign:
			reversals += 1
		last_sign = s
	return reversals

func _tiles_crossed(points: PackedVector2Array) -> Array:
	var terrain := _terrain()
	var out: Array = []
	if terrain == null:
		return out
	var seen := {}
	for p in points:
		var coord: Vector2i = terrain.tile_coord_for_map_coord(terrain.local_to_map(p))
		if not seen.has(coord) and terrain.tiles.has(coord):
			seen[coord] = true
			out.append(coord)
	return out

func _resample(path: Array, spacing: float) -> Array[Vector2]:
	var out: Array[Vector2] = [path[0]]
	var walked := 0.0
	for i in range(1, path.size()):
		var a: Vector2 = path[i - 1]
		var b: Vector2 = path[i]
		var seg := a.distance_to(b)
		while walked + seg >= spacing:
			var t := (spacing - walked) / seg
			var p: Vector2 = a.lerp(b, t)
			out.append(p)
			a = p
			seg = a.distance_to(b)
			walked = 0.0
		walked += seg
	if out[out.size() - 1].distance_squared_to(path[path.size() - 1]) > 1.0:
		out.append(path[path.size() - 1])
	return out

func _thin(points: Array[Vector2], min_step: float) -> Array[Vector2]:
	if points.size() <= 2:
		return points
	var out: Array[Vector2] = [points[0]]
	for i in range(1, points.size() - 1):
		if points[i].distance_to(out[out.size() - 1]) >= min_step:
			out.append(points[i])
	out.append(points[points.size() - 1])
	return out

func _smooth(points: Array[Vector2], iterations: int) -> PackedVector2Array:
	var current := points
	for _i in iterations:
		if current.size() < 3:
			break
		var next: Array[Vector2] = [current[0]]
		for i in range(current.size() - 1):
			next.append(current[i].lerp(current[i + 1], 0.25))
			next.append(current[i].lerp(current[i + 1], 0.75))
		next.append(current[current.size() - 1])
		current = next
	var out := PackedVector2Array()
	for p in current:
		out.append(p)
	return out

func _dist_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var denom := ab.length_squared()
	if denom <= 0.0001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / denom, 0.0, 1.0)
	return point.distance_to(a + ab * t)

# ----------------------------------------------------------------- scratch

func _ensure_scratch(states: int) -> void:
	if _score.size() < states:
		_score.resize(states)
		_parent.resize(states)
		_closed.resize(states)
	if _heap_state.size() < states:
		_heap_state.resize(states + 8)
		_heap_cost.resize(states + 8)

func _heap_push(state: int, cost: float) -> void:
	var i := _heap_size
	_heap_size += 1
	while i > 0:
		var parent := (i - 1) >> 1
		if _heap_cost[parent] <= cost:
			break
		_heap_state[i] = _heap_state[parent]
		_heap_cost[i] = _heap_cost[parent]
		i = parent
	_heap_state[i] = state
	_heap_cost[i] = cost

func _heap_pop() -> int:
	var root := _heap_state[0]
	_heap_size -= 1
	if _heap_size == 0:
		return root
	var last_state := _heap_state[_heap_size]
	var last_cost := _heap_cost[_heap_size]
	var i := 0
	while true:
		var left := i * 2 + 1
		if left >= _heap_size:
			break
		var child := left
		if left + 1 < _heap_size and _heap_cost[left + 1] < _heap_cost[left]:
			child = left + 1
		if _heap_cost[child] >= last_cost:
			break
		_heap_state[i] = _heap_state[child]
		_heap_cost[i] = _heap_cost[child]
		i = child
	_heap_state[i] = last_state
	_heap_cost[i] = last_cost
	return root
