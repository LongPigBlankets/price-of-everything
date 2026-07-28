extends RefCounted
class_name ServiceLanes

## Plans ONE narrow service lane for a tile: a thin street that leaves a clean run of
## main road, reaches into a large roadless pocket, and — when it can — rejoins the
## network further along, on a single branch.
##
## Everything here is pure grid work over the caller's tile raster.
## building_visuals.gd owns the world knowledge (water, elevation, forests, rivers,
## placed footprints) and bakes it into `blocked` + `cost` before calling in; this
## file never touches NavGrid, RoadNetwork or the scene tree. That split is what
## makes the routing unit-testable without a map.
##
## DETERMINISTIC: no RNG anywhere. Every tie breaks on the lowest cell index, so the
## same tile raster always yields the same lane (required by rule #3 — the layout is
## replayed wholesale by relayout()).
##
## Why a lane is worth its land: a main road sterilises ROAD_CLEAR (15u) either side,
## a lane only SERVICE_CLEAR (4u). It is laid to WIN frontage, so it must cost far
## less ground than the frontage it opens up.

const SQRT2 := 1.41421356237

## Cells nearer a main road than this get a cost bump — a lane running 5u alongside
## a trunk road reads as a drafting mistake. Crossing one is still allowed (it is a
## bump, not a wall), because a lane that must cross to reach its pocket should.
const ROAD_HUG := 14.0
const ROAD_HUG_COST := 3.0

## Junctions and stubs are the network's busy points; a lane grafted across one reads
## as a mistake. Priced high enough to detour around, low enough that a lane with no
## other way through still takes it.
const JUNCTION_KEEP := 26.0
const JUNCTION_COST := 12.0

## Plan a lane. `ctx` keys:
##   cols, rows, cell   - the tile raster (see BuildingVisuals.GRID_COLS/ROWS/CELL)
##   tile_center        - raster-space origin offset (BuildingVisuals.TILE_CENTER)
##   segs               - Array of [a, b] main-road segments, tile-centre-relative
##   blocked            - PackedByteArray, 1 = the lane may not enter (terrain, sea,
##                        lake, forest core, placed footprints, outside the hex).
##                        Must NOT include the road-clearance carve: the lane has to
##                        be able to touch a road to join it.
##   cost               - PackedFloat32Array of ADDITIONAL per-cell cost (0 = open
##                        ground). Mild bumps steer it; they never forbid.
##   void_radius        - a cell further than this from every road is the middle of a
##                        roadless pocket ~2x this across. Only such a pocket earns a lane.
##   anchor_keep        - the lane leaves the road at least this far from any junction or stub
##   fork_keep          - and rejoins at least this far from one, so it meets ONE branch
##   rejoin_min         - a rejoin must be at least this far from the anchor (else it loops)
##   simplify           - RDP epsilon for the returned polyline
##
## Returns the lane as a tile-centre-relative polyline, or empty if the tile has not
## earned one (no pocket, no clean run facing it, or nowhere to route).
static func plan(ctx: Dictionary) -> PackedVector2Array:
	var cols: int = int(ctx.cols)
	var rows: int = int(ctx.rows)
	var cell: float = float(ctx.cell)
	var tc: Vector2 = ctx.tile_center
	var segs: Array = ctx.segs
	var blocked: PackedByteArray = ctx.blocked
	var base_cost: PackedFloat32Array = ctx.cost
	if segs.is_empty():
		return PackedVector2Array()

	var n := cols * rows
	var dist := _road_distance(cols, rows, cell, tc, segs)

	# 1. The pocket. The deepest roadless cell IS the centre of the largest roadless
	#    area — a cell `d` from every road has a clear disc of diameter 2d around it.
	var void_key := -1
	var void_d := float(ctx.get("void_radius", 60.0))
	for key in n:
		if blocked[key] == 1:
			continue
		if dist[key] > void_d:
			void_d = dist[key]
			void_key = key
	if void_key < 0:
		return PackedVector2Array()   # no pocket big enough: the tile is served already
	var vpos := _cell_pos(void_key, cols, cell, tc)

	# 2. Junctions and stubs. A lane may not start where the network already branches
	#    or ends — those are busy, and a 4th arm at a stub just reads as a mistake.
	var deg := {}
	for s in segs:
		for p in [s[0], s[1]]:
			var vk := _vkey(p)
			deg[vk] = int(deg.get(vk, 0)) + 1
	var node_map := {}
	for s in segs:
		for p in [s[0], s[1]]:
			var vk := _vkey(p)
			if int(deg[vk]) != 2:
				node_map[vk] = p
	var nodes: Array = node_map.values()

	# 3. The anchor: the closest clean mid-run point that FACES the pocket. The
	#    perpendicularity gate stops a lane peeling off at a graze and running
	#    alongside its parent road.
	var keep := float(ctx.get("anchor_keep", 30.0))
	var anchor := Vector2.INF
	var anchor_dir := Vector2.ZERO
	var best := INF
	for s in segs:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		if int(deg.get(_vkey(a), 0)) != 2 or int(deg.get(_vkey(b), 0)) != 2:
			continue
		var tan := b - a
		if tan.length() < 0.5:
			continue
		tan = tan.normalized()
		var mid := (a + b) * 0.5
		var clean := true
		for nd in nodes:
			if mid.distance_to(nd) < keep:
				clean = false
				break
		if not clean:
			continue
		var to_void := vpos - mid
		var d := to_void.length()
		if d < 1.0:
			continue
		to_void /= d
		if absf(to_void.dot(tan)) > 0.8:
			continue
		if d < best:
			best = d
			anchor = mid
			anchor_dir = to_void
	# Fork origin: with no clean run facing the pocket, a lane may instead sprout as a
	# further arm of an existing fork. Second choice — forks are the busy points.
	if anchor == Vector2.INF:
		for nd in nodes:
			var nv: Vector2 = nd
			if int(deg.get(_vkey(nv), 0)) < 3:
				continue   # a stub, not a fork
			var d2 := nv.distance_to(vpos)
			if d2 < best:
				best = d2
				anchor = nv
				anchor_dir = (vpos - nv).normalized()
	if anchor == Vector2.INF:
		return PackedVector2Array()

	# Route cost: the caller's terrain bumps, plus a penalty for shadowing a main road.
	var cost := PackedFloat32Array()
	cost.resize(n)
	for key in n:
		var c := base_cost[key]
		if dist[key] < ROAD_HUG:
			c += ROAD_HUG_COST
		# Crossing a main road is allowed; crossing it AT a junction is not, in
		# practice — a lane grafted onto an existing X reads as a drafting slip.
		# Priced, not forbidden, so a lane boxed in can still take the bad crossing.
		if dist[key] < JUNCTION_KEEP:
			var p := _cell_pos(key, cols, cell, tc)
			for nd in nodes:
				if p.distance_to(nd) < JUNCTION_KEEP:
					c += JUNCTION_COST
					break
		cost[key] = c

	# 4. Step off the carriageway to find a legal first cell, then route to the pocket.
	var start_key := -1
	for step in range(1, 14):
		var k := _key_of(anchor + anchor_dir * (float(step) * cell), cols, rows, cell, tc)
		if k >= 0 and blocked[k] == 0:
			start_key = k
			break
	if start_key < 0:
		return PackedVector2Array()
	var leg1 := _route(cols, rows, cost, blocked, start_key, {void_key: true}, void_key)
	if leg1.is_empty():
		return PackedVector2Array()

	# 5. Rejoin, if there is somewhere honest to rejoin. Goals are cells beside a road,
	#    far enough from the anchor not to double back, and fork_keep clear of every
	#    junction — so the lane always meets ONE branch, never the crossing itself.
	var fork_keep := float(ctx.get("fork_keep", 20.0))
	var rejoin_min := float(ctx.get("rejoin_min", 90.0))
	var goals := {}
	for key in n:
		if blocked[key] == 1 or dist[key] > cell * 2.0:
			continue
		var p := _cell_pos(key, cols, cell, tc)
		if p.distance_to(anchor) < rejoin_min:
			continue
		var ok := true
		for nd in nodes:
			if p.distance_to(nd) < fork_keep:
				ok = false
				break
		if ok:
			goals[key] = true
	var pts := PackedVector2Array([anchor])
	for k in leg1:
		pts.append(_cell_pos(k, cols, cell, tc))
	if not goals.is_empty():
		# The return leg must not shadow the outbound one. Without this it retraces it a
		# cell or two away and the lane comes out as a hairpin — measured on tile_6_12:
		# ...(-142,-218) -> (-122,-218)..., a 20u-wide U-turn at the far end.
		var self_keep := float(ctx.get("self_keep", 30.0))
		var keep_cells := int(ceilf(self_keep / cell))
		var blocked2 := blocked.duplicate()
		var vc := void_key % cols
		var vr := void_key / cols
		for k in leg1:
			var kc := k % cols
			var kr := k / cols
			if maxi(absi(kc - vc), absi(kr - vr)) <= keep_cells:
				continue   # leave the pocket end open: leg 2 has to start there
			for dr in range(-keep_cells, keep_cells + 1):
				var rr := kr + dr
				if rr < 0 or rr >= rows:
					continue
				for dc in range(-keep_cells, keep_cells + 1):
					var cc := kc + dc
					if cc < 0 or cc >= cols:
						continue
					blocked2[rr * cols + cc] = 1
		var leg2 := _route(cols, rows, cost, blocked2, void_key, goals, -1)
		# A rejoin is only worth it if the way back is comparable to the way out.
		# Anything longer is a lane touring the tile to find a second doorway; a
		# cul-de-sac at the pocket is both cheaper in land and perfectly ordinary.
		var out_len := 0.0
		for i in range(1, pts.size()):
			out_len += pts[i].distance_to(pts[i - 1])
		var back_len := 0.0
		for i in range(1, leg2.size()):
			back_len += _cell_pos(leg2[i], cols, cell, tc).distance_to(_cell_pos(leg2[i - 1], cols, cell, tc))
		if not leg2.is_empty() and back_len <= out_len * float(ctx.get("rejoin_ratio", 1.8)):
			for i in range(1, leg2.size()):
				pts.append(_cell_pos(leg2[i], cols, cell, tc))
	return _rdp(pts, float(ctx.get("simplify", 5.0)))


## Distance (world units) from every cell to the nearest main-road centreline, by
## two-pass chamfer. O(cells) — the brute-force per-cell scan over finely-sampled
## roads-v3 polylines is the exact cost the mask rasteriser was rewritten to avoid.
static func _road_distance(cols: int, rows: int, cell: float, tc: Vector2, segs: Array) -> PackedFloat32Array:
	var n := cols * rows
	var d := PackedFloat32Array()
	d.resize(n)
	var big := float(cols + rows) * 2.0
	for i in n:
		d[i] = big
	# Seed: cells the carriageway passes through, stamped over each segment's own bbox.
	var pad := cell * 0.75
	for s in segs:
		var a: Vector2 = (s[0] as Vector2) + tc
		var b: Vector2 = (s[1] as Vector2) + tc
		var c0 := clampi(int(floorf((minf(a.x, b.x) - pad) / cell - 0.5)), 0, cols - 1)
		var c1 := clampi(int(ceilf((maxf(a.x, b.x) + pad) / cell - 0.5)), 0, cols - 1)
		var r0 := clampi(int(floorf((minf(a.y, b.y) - pad) / cell - 0.5)), 0, rows - 1)
		var r1 := clampi(int(ceilf((maxf(a.y, b.y) + pad) / cell - 0.5)), 0, rows - 1)
		for row in range(r0, r1 + 1):
			for col in range(c0, c1 + 1):
				var key := row * cols + col
				if d[key] == 0.0:
					continue
				var rel := Vector2((col + 0.5) * cell, (row + 0.5) * cell) - tc
				if _pt_seg(rel, s[0], s[1]) < pad:
					d[key] = 0.0
	for row in rows:
		for col in cols:
			var key := row * cols + col
			var v := d[key]
			if row > 0:
				v = minf(v, d[key - cols] + 1.0)
				if col > 0:
					v = minf(v, d[key - cols - 1] + SQRT2)
				if col < cols - 1:
					v = minf(v, d[key - cols + 1] + SQRT2)
			if col > 0:
				v = minf(v, d[key - 1] + 1.0)
			d[key] = v
	for row in range(rows - 1, -1, -1):
		for col in range(cols - 1, -1, -1):
			var key := row * cols + col
			var v := d[key]
			if row < rows - 1:
				v = minf(v, d[key + cols] + 1.0)
				if col > 0:
					v = minf(v, d[key + cols - 1] + SQRT2)
				if col < cols - 1:
					v = minf(v, d[key + cols + 1] + SQRT2)
			if col < cols - 1:
				v = minf(v, d[key + 1] + 1.0)
			d[key] = v
	for i in n:
		d[i] *= cell
	return d


## 8-connected least-cost route from `start` to any key in `goals`. `heur_key >= 0`
## turns on the octile heuristic toward that single cell (A*); -1 runs plain Dijkstra
## for a multi-goal search. Base step cost is 1, so the heuristic stays admissible.
static func _route(cols: int, rows: int, cost: PackedFloat32Array, blocked: PackedByteArray, start: int, goals: Dictionary, heur_key: int) -> PackedInt32Array:
	var n := cols * rows
	if start < 0 or start >= n or blocked[start] == 1:
		return PackedInt32Array()
	var g := PackedFloat32Array()
	g.resize(n)
	var came := PackedInt32Array()
	came.resize(n)
	var done := PackedByteArray()
	done.resize(n)
	for i in n:
		g[i] = INF
		came[i] = -1
	g[start] = 0.0
	var gx := heur_key % cols
	var gy := heur_key / cols
	# Binary heap of [f, key]; GDScript has no priority queue and the grid is ~10k cells.
	var heap: Array = [[0.0, start]]
	var hit := -1
	while not heap.is_empty():
		var top: Array = _heap_pop(heap)
		var key: int = top[1]
		if done[key] == 1:
			continue
		done[key] = 1
		if goals.has(key):
			hit = key
			break
		var col := key % cols
		var row := key / cols
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var nc := col + dx
				var nr := row + dy
				if nc < 0 or nc >= cols or nr < 0 or nr >= rows:
					continue
				var nk := nr * cols + nc
				if blocked[nk] == 1 or done[nk] == 1:
					continue
				var step := SQRT2 if dx != 0 and dy != 0 else 1.0
				var ng: float = g[key] + step + cost[nk]
				if ng >= g[nk]:
					continue
				g[nk] = ng
				came[nk] = key
				var f := ng
				if heur_key >= 0:
					var ax := absf(float(nc - gx))
					var ay := absf(float(nr - gy))
					f += maxf(ax, ay) + (SQRT2 - 1.0) * minf(ax, ay)
				_heap_push(heap, [f, nk])
	if hit < 0:
		return PackedInt32Array()
	var rev := PackedInt32Array()
	var cur := hit
	while cur != -1:
		rev.append(cur)
		cur = came[cur]
	rev.reverse()
	return rev


static func _heap_push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) / 2
		if heap[parent][0] <= heap[i][0]:
			break
		var t: Array = heap[parent]
		heap[parent] = heap[i]
		heap[i] = t
		i = parent


static func _heap_pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty():
		return top
	heap[0] = last
	var i := 0
	var n := heap.size()
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var small := i
		if l < n and heap[l][0] < heap[small][0]:
			small = l
		if r < n and heap[r][0] < heap[small][0]:
			small = r
		if small == i:
			break
		var t: Array = heap[small]
		heap[small] = heap[i]
		heap[i] = t
		i = small
	return top


## Ramer-Douglas-Peucker. The grid route is 5u-stair-stepped; simplifying it to a few
## long chords is what lets the road renderer's hand-wobble read as a drawn line
## rather than as pixel noise.
static func _rdp(pts: PackedVector2Array, eps: float) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var worst := 0.0
	var idx := 0
	for i in range(1, pts.size() - 1):
		var d := _pt_seg(pts[i], pts[0], pts[pts.size() - 1])
		if d > worst:
			worst = d
			idx = i
	if worst <= eps:
		return PackedVector2Array([pts[0], pts[pts.size() - 1]])
	var left := _rdp(pts.slice(0, idx + 1), eps)
	var right := _rdp(pts.slice(idx), eps)
	var out := PackedVector2Array(left)
	for i in range(1, right.size()):
		out.append(right[i])
	return out


## Hand-drawn jitter, baked once at plan time (_draw runs every frame). A looser hand
## than the trunk roads' 20u/1.5u — an unmade access track was never surveyed.
##
## The caller measures clearance on the WOBBLED line, not the straight chords it came
## from. Treating the wiggle as free decoration put the drawn lane up to WOBBLE_AMP off
## the geometry everything else was validated against, and two lanes ended up drawn over
## a building. The wiggle does cost land — about WOBBLE_AMP of it.
const WOBBLE_STEP := 16.0
const WOBBLE_AMP := 2.5

static func wobble(pts: PackedVector2Array, seed_key: String) -> PackedVector2Array:
	if pts.size() < 2:
		return pts
	var out := PackedVector2Array()
	var k := 0
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		out.append(a)
		var seg_len := a.distance_to(b)
		var n := int(seg_len / WOBBLE_STEP)
		if n > 0:
			var perp := Vector2(-(b - a).y, (b - a).x) / seg_len
			for j in range(1, n + 1):
				var off := (float(RoadHash.pick("svcwob|%s|%d" % [seed_key, k], 200)) / 100.0 - 1.0) * WOBBLE_AMP
				k += 1
				out.append(a + (b - a) * (float(j) / float(n + 1)) + perp * off)
	out.append(pts[pts.size() - 1])
	return out


static func _pt_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.000001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _cell_pos(key: int, cols: int, cell: float, tc: Vector2) -> Vector2:
	return Vector2((float(key % cols) + 0.5) * cell, (float(key / cols) + 0.5) * cell) - tc


static func _key_of(rel: Vector2, cols: int, rows: int, cell: float, tc: Vector2) -> int:
	var local := rel + tc
	var col := int(local.x / cell)
	var row := int(local.y / cell)
	if col < 0 or col >= cols or row < 0 or row >= rows:
		return -1
	return row * cols + col


## Vertex identity for degree counting: road polylines share endpoints exactly, but
## quantising to 0.5u keeps float drift from splitting a junction into two stubs.
static func _vkey(p: Vector2) -> String:
	return "%d,%d" % [roundi(p.x * 2.0), roundi(p.y * 2.0)]
