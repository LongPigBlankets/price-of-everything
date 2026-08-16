extends Node
## RoadWorks — the roads-v2 turn-phased work-order pipeline (spec Phase 3).
##
## When a road construction completes (PROCESS), the gameplay flag flips as it
## always has; this enqueues a WorkOrder that connects the tile to the existing
## network. Planning runs in _process under PLAN_BUDGET_MS per frame via the
## realizer's resumable step() API (outside TurnProfiler brackets — frames, not
## turn phases). A routed order commits its edge as BUILDING, reveals over
## REVEAL_DURATION growing from the network attachment outward, then settles
## to BUILT (static layer redraws once, occupancy registers).
##
## Invalidation matrix (spec): road built on tile T -> a job for T only;
## building placed -> NOTHING (v1's map-wide handler is deleted); forest
## planted/removed -> restart orders still planning whose corridor intersects
## the disc — BUILT/revealing edges stay (history is history).

## Per-frame planning budget. 6 ms lets a lone hard route (e.g. a river tile
## that must detour to a bridge gate via the coarse pass) finish in a few
## seconds rather than ~10 — the work is small (~0.5 s CPU) but the conservative
## old 4 ms budget only ran ~1 search unit per frame.
## Hand-authored tiles draw their own roads and suppress procedural geometry jobs.
const AuthoredMap := preload("res://scripts/authored_map.gd")

const PLAN_BUDGET_MS := 6.0
## Mass-build burst: with a deep queue (e.g. 100 completions in one PROCESS)
## the budget rises toward the 8 ms frame ceiling so the backlog clears fast.
const PLAN_BUDGET_BURST_MS := 7.8
const BURST_QUEUE_DEPTH := 10
## Never START a planning unit with less than this left in the budget — a unit
## (one A* slice or prep chunk) runs up to ~3 ms, and starting one at the
## deadline is what pushes a frame past the 8 ms ceiling.
const UNIT_CUTOFF_MS := 3.2
const REVEAL_DURATION := 3.0
## Corridor half-width per tier for occupancy (visual width/2 + 3 u buffer —
## v1's ROAD_BUILD_BUFFER).
const OCC_HALF_WIDTH := {"trunk": 6.5, "local": 5.25}
const TRUNK_LENGTH := 1500.0   # tier rule shared with tools/bake_roads.gd
## A corridor/disc near a tile edge spills onto neighbours — stamp these too.
const NEIGHBOUR_OFFSETS: Array[Vector2i] = [
	Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1),
]

signal order_settled(order_id: int)
signal orders_changed()
## A farm tile's cosmetic web (outer ring + one through-path) was promoted to real roads because a
## player road reached it — BuildingVisuals stops drawing those brown tracks (tile_id).
signal farm_roads_promoted(tile_id: String)

## Farm rings no longer become real roads (owner 2026-07-23). Ink farms carry
## their own parcel-path fabric, so the promoted ring is redundant decoration —
## and it is only decoration: transport reads each tile's road FLAG, not whether
## carriageways physically meet, so a farm tile a road already crosses is just
## as connected without it. Roads may still serve a farm cluster; they simply
## stop at its edge or at a junction instead of being threaded around the ring.
const PROMOTE_FARM_RINGS := false

var orders: Dictionary = {}     # id -> order dict
var _queue: Array = []          # order ids awaiting planning (FIFO)
var _active: int = -1           # order id currently planning
var _revealing: Array = []      # order ids mid-reveal
var _next_order := 1
## Regions whose style jobs (spec §6) have already been generated — each region
## grows its web exactly once, on its first member road (persisted in saves).
var _styled_regions: Dictionary = {}
## Preview bridges shown the instant a river road's construction completes, at
## the tile's PREDETERMINED crossing(s) — immediate feedback while the
## connecting road plans (which can take a few seconds on a hard river tile).
## order_id -> Array[{point, tangent}]; cleared when that order settles or
## fails (the real edge's bridges then represent reality).
var _preview_bridges: Dictionary = {}
## Adjacent road-tile pairs already joined by a connect/link, so a cluster of
## built tiles meshes instead of each tile reaching back to the trunk alone.
## Key "tileA|tileB" (sorted). Persisted so a reload doesn't double-link.
var _linked_pairs: Dictionary = {}
## Farm tiles whose web (outer ring + one path) has been promoted to real RoadNetwork roads. Persisted
## so a reload doesn't re-promote (the edges themselves ride in RoadNetwork state). tile_id -> true.
var _farm_promoted: Dictionary = {}
## Promoted-ring endpoint nodes already bridged across a tile seam to a neighbour's road. endpoint_id ->
## true. Persisted so a reload never re-bridges (the bridge edge itself rides in RoadNetwork state).
var _farm_links: Dictionary = {}
## Dedicated realizer: its scratch buffers hold the one in-flight paused job.
var _realizer := RoadRealizer.new()
var _job: Dictionary = {}
## Merged road-corridor occupancy bits per tile (all settled edges).
var _road_bits: Dictionary = {}   # tile_id -> Dictionary[bit -> true]
## Planning time spent this frame (ms) — read by the B4 mass-build perf test.
var last_frame_plan_ms := 0.0
## Worst-case telemetry since reset() (B4 perf-test diagnostics).
var max_unit_ms := 0.0
var max_begin_ms := 0.0
var max_finish_ms := 0.0
## Failed-order log (read by the debug terminal / tests; printing mid-frame
## would blow the budget).
var failure_log: Array = []

func _ready() -> void:
	Construction.construction_completed.connect(_on_construction_completed)
	MatchState.building_added.connect(_on_building_added)
	MatchState.building_removed.connect(_on_building_removed)

# ----------------------------------------------------------------- enqueue

func _on_construction_completed(instance_id: String, tile_id: String) -> void:
	var building_id := str(MatchState.get_building(instance_id).get("building_id", ""))
	var internal := str(Catalog.get_building(building_id).get("internal_name", ""))
	if internal == "roads":
		# A hand-authored tile already has its roads drawn, including the connectors that
		# reveal the moment this flag lands. Planning a connect job and densify spurs here
		# would grow procedural stubs alongside the authored linework — the same "inventing
		# roads to suit something else is backwards" defect that got block service streets
		# removed. Only the GEOMETRY is skipped: the infrastructure flag, the transport
		# cost and everything else the simulation reads are set by the caller regardless.
		if AuthoredMap.covers(tile_id):
			return
		enqueue_for_tile(tile_id)
		_enqueue_densify(tile_id)

## Queue a connect-to-network job for the tile (spec: road built on tile T
## plans jobs for T only). Returns the order id, or -1 when skipped.
## The tile an order belongs to ("" if unknown). Lets a listener re-pack exactly
## the tile whose road just settled (BuildingVisuals re-snap on order_settled).
func order_tile(order_id: int) -> String:
	return str((orders.get(order_id, {}) as Dictionary).get("tile_id", ""))

func enqueue_for_tile(tile_id: String) -> int:
	for id in orders:
		var existing: Dictionary = orders[id]
		if str(existing.tile_id) == tile_id and str(existing.state) in ["queued", "planning"] \
			and str(existing.get("kind", "connect")) == "connect":
			return int(id)   # a connect is already pending for this tile (densify spurs don't count)
	var terrain := _terrain()
	if terrain == null:
		return -1
	var coord: Vector2i = terrain.id_to_coord(tile_id)
	if not terrain.tiles.has(coord):
		return -1
	var start: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
	var attach := _nearest_attachment(start)
	if attach.is_empty():
		return -1   # no network yet (bootstrap missing) — nothing to connect to
	# Forest discs rebuild here (turn context) so the ~40 ms cache build never
	# lands inside a budgeted planning frame. Building-cost discs warm here too, so a
	# road planned after a building is placed routes around it.
	_realizer.warm_forest_cache()
	_realizer.warm_building_cache()
	var id2 := _next_order
	_next_order += 1
	var order := {
		"id": id2,
		"tile_id": tile_id,
		"state": "queued",
		"start": start,
		"goal": attach.pos,
		"attach_id": str(attach.get("id", "")),   # "" -> junction created at commit
		"coord": coord,
		"tier": RoadNetwork.TIER_TRUNK if start.distance_to(attach.pos) > TRUNK_LENGTH else RoadNetwork.TIER_LOCAL,
		"salt": RoadHash.pick("works|%s" % tile_id, 1 << 30),
		"turn": TurnManager.current_turn,
		"edge_id": "",
		"reveal_t": 0.0,
		"reason": "",
		"plan_ms": 0.0,
	}
	order["kind"] = "connect"
	orders[id2] = order
	_queue.append(id2)
	# Show the tile's predetermined bridge(s) immediately — instant feedback that
	# the river road is going in, before the connecting road has planned.
	var crossings := RoadCrossings.for_tile(tile_id)
	if not crossings.is_empty():
		var pb: Array = []
		for c in crossings:
			pb.append({"point": c.point, "tangent": c.bridge_tangent})
		_preview_bridges[id2] = pb
	orders_changed.emit()
	return id2

## How many interior spur jobs a bought road adds, by region identity. A tile
## the network already crosses would otherwise gain almost no visible geometry
## from its (near zero-length) connect job — the player paid for roads and
## should see local fabric grow. Mountains stay minimal by design.
const DENSIFY_SPURS := 2
const DENSIFY_SPURS_MOUNTAIN := 1
const DENSIFY_CANDIDATES := 24    # seeded in-hex sample points to try
const DENSIFY_MAX_LEVEL := 6      # spur destinations stay below serpentine country

## Seeded interior spur jobs for a tile whose roads infrastructure just
## completed: pick up to K in-hex points on buildable land, away from the
## existing network, and connect each to the nearest attachment. The spurs run
## through the normal budgeted planning + reveal, and the reuse discount merges
## them onto existing carriageways where they coincide. Deterministic per tile.
func _enqueue_densify(tile_id: String) -> void:
	var terrain := _terrain()
	if terrain == null:
		return
	var coord: Vector2i = terrain.id_to_coord(tile_id)
	if not terrain.tiles.has(coord):
		return
	var nav := NavGrid.instance()
	if nav == null or not nav.is_ready():
		return
	var net := RoadNetwork.instance()
	var center: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
	var want := DENSIFY_SPURS_MOUNTAIN if RoadRegions.identity_for_tile(tile_id) == "mountain_range" else DENSIFY_SPURS
	var made := 0
	for i in DENSIFY_CANDIDATES:
		if made >= want:
			break
		var rel := Vector2(
			float(RoadHash.pick("densify|%s|%d|x" % [tile_id, i], 460)) - 230.0,
			float(RoadHash.pick("densify|%s|%d|y" % [tile_id, i], 400)) - 200.0)
		if 240.0 * absf(rel.x) + 135.0 * absf(rel.y) > 64800.0:
			continue   # outside the flat-top hex
		var p := center + rel
		var c := nav.cell_of(p)
		if c.x < 0 or c.y < 0 or c.x >= nav.gw or c.y >= nav.gh:
			continue
		if nav.water(c.x, c.y) != NavGrid.WATER_LAND or nav.level(c.x, c.y) >= DENSIFY_MAX_LEVEL:
			continue
		if net.near_network(p):
			continue   # too close to an existing road — the spur would be a stub
		var attach := _nearest_attachment(p)
		if attach.is_empty():
			continue
		var id3 := _next_order
		_next_order += 1
		orders[id3] = {
			"id": id3,
			"tile_id": tile_id,
			"state": "queued",
			"start": p,
			"goal": attach.pos,
			"attach_id": str(attach.get("id", "")),
			"coord": coord,
			"tier": RoadNetwork.TIER_LOCAL,
			"salt": RoadHash.pick("densify|%s|%d" % [tile_id, i], 1 << 30),
			"turn": TurnManager.current_turn,
			"edge_id": "",
			"reveal_t": 0.0,
			"reason": "",
			"plan_ms": 0.0,
			"kind": "densify",
		}
		_queue.append(id3)
		made += 1
	if made > 0:
		orders_changed.emit()

## Preview bridges to draw (RoadNetworkVisuals), flattened across pending orders.
func preview_bridges() -> Array:
	var out: Array = []
	for oid in _preview_bridges:
		out.append_array(_preview_bridges[oid])
	return out

## Generate and queue a region's style jobs (spec §6) — its beltway/minihub/
## through-route character. Runs once per region, triggered by its first
## member road settling. Ring (trunk) jobs queue FIRST so the orbital reveals
## before the branches (reveal trunk-first ruling). Runtime ring segments
## carry the inside-region bias up front (single pass — the bake does the
## spec's two-pass overflow rework, which needs whole-ring transactions).
func enqueue_region_jobs(region_id: String) -> int:
	if _styled_regions.has(region_id) or region_id == RoadRegions.DEFAULT_REGION_ID:
		return 0
	_styled_regions[region_id] = true
	var terrain := _terrain()
	if terrain == null:
		return 0
	var jobs := RoadRegionJobs.generate(region_id, terrain)
	var member_coords := RoadRegionJobs.member_coords(region_id, terrain)
	var queued := 0
	for job in jobs:
		var id3 := _next_order
		_next_order += 1
		var order := {
			"id": id3,
			"kind": "style",
			"tile_id": str(RoadRegions.tiles(region_id)[0]) if not RoadRegions.tiles(region_id).is_empty() else "",
			"state": "queued",
			"start": job.start,
			"goal": job.goal,
			"attach_id": "",
			"coord": terrain.tile_coord_for_map_coord(terrain.local_to_map(job.start as Vector2)),
			"tier": str(job.tier),
			"salt": int(job.salt),
			"turn": TurnManager.current_turn,
			"edge_id": "",
			"reveal_t": 0.0,
			"reason": "",
			"plan_ms": 0.0,
			"region_id": region_id,
			"orbital": str(job.kind) == "orbital",
		}
		orders[id3] = order
		_queue.append(id3)
		queued += 1
	if queued > 0:
		orders_changed.emit()
	return queued

## Nearest point ON the network: any node, or any point of any edge's realized
## geometry (roads connect to the road they meet, not to the distant junction).
## Returns {pos, id} — id "" when the attachment is mid-edge (a junction node is
## created there when the order commits).
## Roads merge into at most a 5-way junction. A node already carrying MAX_JUNCTION
## edges is "full": a new road attaches to a ROAD near it (an edge sample) instead
## of piling a 6th arm onto the point — it merges into a road that connects to the
## others rather than overloading the junction.
const MAX_JUNCTION := 5
## A connect-road within BRIDGE_HEAD_RANGE of a bridge prefers the bank HEAD (discounted by BRIDGE_HEAD_BIAS)
## over a nearby mid-edge point, so roads meet the bridge tidily on land instead of forcing to mid-tile.
const BRIDGE_HEAD_RANGE := 500.0
const BRIDGE_HEAD_BIAS := 0.6

## Two adjacent tiles' promoted rings are bridged only when their closest approach is within this gap —
## enough to span the two 1u hex insets plus the lateral offset between the clipped rings (~2.7u for
## straddling clusters) with a little margin, but small enough that the bridge is a short seam stub and
## never connects two clusters that aren't actually adjacent (stays below FARM_RING_DEDUP_RADIUS=14u).
const FARM_BRIDGE_MAX := 8.0

func _nearest_attachment(from: Vector2) -> Dictionary:
	var net := RoadNetwork.instance()
	var degree := _node_degrees(net)
	var best: Dictionary = {}
	var best_d := 1e30
	for node_id in net.nodes:
		if int(degree.get(str(node_id), 0)) >= MAX_JUNCTION:
			continue   # full junction — don't add a 6th arm to the point
		var node: Dictionary = net.nodes[node_id]
		var d: float = (node.pos as Vector2).distance_squared_to(from)
		if d < best_d:
			best_d = d
			best = {"pos": node.pos, "id": str(node.id)}
	for edge_id in net.edges:
		var geometry: PackedVector2Array = net.edges[edge_id].geometry
		# Project `from` onto each SEGMENT (not just every-8th vertex): the goal must pin to the
		# TRUE nearest point on the centreline. A sparse vertex sample could sit 8-20u off the
		# line, and that offset is exactly what seeds a parallel "doubled" road (the reuse bias has
		# no snap of its own). O(network) like the old loop — same cost, just exact.
		for i in range(geometry.size() - 1):
			var cp := Geometry2D.get_closest_point_to_segment(from, geometry[i], geometry[i + 1])
			var d2 := cp.distance_squared_to(from)
			if d2 < best_d:
				best_d = d2
				best = {"pos": cp, "id": ""}
	# Bridge heads: fold in each bridge's NEAR-bank head (the same-bank one is always nearer than the
	# across-river head) with a distance discount, so a connect-road near a bridge meets the bank head
	# rather than a mid-edge projection that can land on the river crossing. Positional attachment (id "").
	var reach := RoadCrossings.GATE_OFFSET + RoadRealizer.BRIDGE_BANK_STUB
	for edge_id2 in net.edges:
		for br in (net.edges[edge_id2].get("bridges", []) as Array):
			var tg: Vector2 = br.get("tangent", Vector2.ZERO)
			if tg.length_squared() < 0.01:
				continue
			var pt: Vector2 = br.get("point", Vector2.ZERO)
			var off := tg.normalized() * reach
			var head: Vector2 = pt + off if (pt + off).distance_squared_to(from) < (pt - off).distance_squared_to(from) else pt - off
			var raw := head.distance_to(from)
			if raw > BRIDGE_HEAD_RANGE:
				continue   # too far — don't pull a distant connect-road onto a bridge
			var eff := raw * BRIDGE_HEAD_BIAS
			if eff * eff < best_d:
				best_d = eff * eff
				best = {"pos": head, "id": ""}
	return best

# ---------------------------------------------------------------- planning

func _process(delta: float) -> void:
	last_frame_plan_ms = 0.0
	_advance_reveals(delta)
	if _active < 0 and _queue.is_empty():
		return
	# Use the WHOLE frame budget: when a job finishes early, begin the next in
	# the same frame instead of idling the remainder.
	var budget := PLAN_BUDGET_BURST_MS if _queue.size() > BURST_QUEUE_DEPTH else PLAN_BUDGET_MS
	var t0 := Time.get_ticks_usec()
	while true:
		var spent := float(Time.get_ticks_usec() - t0) * 0.001
		if spent >= budget - UNIT_CUTOFF_MS:
			break
		if _active < 0:
			if _queue.is_empty():
				break
			var b0 := Time.get_ticks_usec()
			_begin_next()
			max_begin_ms = maxf(max_begin_ms, float(Time.get_ticks_usec() - b0) * 0.001)
			continue   # re-check the budget — begin + unit together can overshoot
		# budget 0.0 = exactly ONE planning unit; this loop owns the clock
		var step_t0 := Time.get_ticks_usec()
		var finished := _realizer.step(_job, 0.0)
		var step_ms := float(Time.get_ticks_usec() - step_t0) * 0.001
		max_unit_ms = maxf(max_unit_ms, step_ms)
		if _active >= 0:
			var order: Dictionary = orders[_active]
			order.plan_ms = float(order.get("plan_ms", 0.0)) + step_ms
		if finished:
			var f0 := Time.get_ticks_usec()
			_finish_active()
			max_finish_ms = maxf(max_finish_ms, float(Time.get_ticks_usec() - f0) * 0.001)
	last_frame_plan_ms = float(Time.get_ticks_usec() - t0) * 0.001

func _begin_next() -> void:
	_active = int(_queue.pop_front())
	var order: Dictionary = orders[_active]
	order.state = "planning"
	var opts := {
		"identity": RoadRegions.identity_for_tile(str(order.tile_id)),
		"salt": int(order.salt),
	}
	if str(order.get("kind", "connect")) == "connect":
		# Re-attach to the FRESHEST network: edges committed by earlier orders in
		# the same batch shorten this job (mass builds become chained short hops —
		# the network literally grows outward). Deterministic: same order sequence
		# produces the same attachments. Style jobs keep their authored endpoints.
		var attach := _nearest_attachment(order.start)
		if not attach.is_empty():
			order.goal = attach.pos
			order.attach_id = str(attach.get("id", ""))
			order.tier = RoadNetwork.TIER_TRUNK if (order.start as Vector2).distance_to(order.goal) > TRUNK_LENGTH else RoadNetwork.TIER_LOCAL
	elif bool(order.get("orbital", false)):
		var terrain := _terrain()
		if terrain != null:
			opts["region_coords"] = RoadRegionJobs.member_coords(str(order.get("region_id", "")), terrain)
			opts["outside_mult"] = RoadRegionJobs.OUTSIDE_MULT
	var net := RoadNetwork.instance()
	_job = _realizer.begin(NavGrid.instance(), net, order.start, order.goal, opts)

func _finish_active() -> void:
	var order: Dictionary = orders[_active]
	var res := _realizer.result(_job)
	_job = {}
	_active = -1
	if not bool(res.get("ok", false)):
		order.state = "failed"
		order.reason = str(res.get("reason", ""))
		_preview_bridges.erase(int(order.id))   # route failed — drop its preview bridge
		# buffered, NOT printed — stdout flush (and push_warning's backtrace,
		# ~40 ms) cannot run inside the planning frame budget
		failure_log.append("order %d (%s): %s" % [int(order.id), str(order.tile_id), str(order.reason)])
		orders_changed.emit()
		return
	_snap_route_to_web(res)   # where the road crosses a farm cluster, run it ON the web (not over fields)
	var net := RoadNetwork.instance()
	var a_id: String
	if str(order.get("kind", "connect")) == "style":
		a_id = str(net.add_junction(order.start, order.coord).id)
	else:
		a_id = str(net.ensure_node("rw:%s" % str(order.tile_id), RoadNetwork.KIND_JUNCTION, order.start, order.coord).id)
	var attach_id := str(order.attach_id)
	if attach_id == "":
		# mid-edge attachment / style endpoint: a junction node right there
		var jn := net.add_junction(order.goal, order.coord)
		attach_id = str(jn.id)
		order.attach_id = attach_id
	var edge := _realizer.commit(net, a_id, attach_id, str(order.tier), res, int(order.turn), RoadNetwork.STATE_BUILDING)
	order.edge_id = str(edge.id)
	order.state = "revealing"
	order.reveal_t = 0.0
	_revealing.append(int(order.id))
	orders_changed.emit()

# ------------------------------------------------------------------ reveal

func _advance_reveals(delta: float) -> void:
	if _revealing.is_empty():
		return
	var settled: Array = []
	for id in _revealing:
		var order: Dictionary = orders[id]
		order.reveal_t = minf(float(order.reveal_t) + delta / REVEAL_DURATION, 1.0)
		if float(order.reveal_t) >= 1.0:
			settled.append(id)
	for id2 in settled:
		_revealing.erase(id2)
		_settle(orders[id2])

func _settle(order: Dictionary) -> void:
	var net := RoadNetwork.instance()
	net.set_edge_state(str(order.edge_id), RoadNetwork.STATE_BUILT)
	order.state = "built"
	# The real edge's bridges now represent the crossing — drop the preview.
	_preview_bridges.erase(int(order.id))
	if TileOccupancy.OCCUPANCY_ROADS_ENABLED:
		var edge: Dictionary = net.edges.get(str(order.edge_id), {})
		if not edge.is_empty():
			_register_edge_occupancy(edge)
	order_settled.emit(int(order.id))
	_promote_farm_roads_if_reached(order, net)
	# Roads appear only where the player builds (roadsv2.5 ruling): a settled
	# member road does NOT auto-grow the whole region's web — it just connects
	# this tile into the network. Regional beltways/webs exist only in the baked
	# starting cities (tools/bake_roads via RoadRegionJobs.realize_region).
	# enqueue_region_jobs() is kept for the bake path and possible future use.
	# But adjacent built tiles SHOULD join up: a connect that lands as a stub
	# beside neighbours that already have roads now links to them (mesh, not a
	# fan of separate spurs back to the trunk). Link orders don't recurse.
	if str(order.get("kind", "connect")) == "connect":
		_link_adjacent_roads(order)
	orders_changed.emit()

## True if this farm tile's web has already been promoted to real roads.
func is_farm_promoted(tile_id: String) -> bool:
	return bool(_farm_promoted.get(tile_id, false))

## A promoted farm-web polyline is suppressed where it runs within this of a road already on the tile
## (the connect road that reached the farm), so the ring never doubles up alongside it. ~one grid cell
## (12u) + a margin, so a road up to a cell away still counts as "already covering" the ring there.
const FARM_RING_DEDUP_RADIUS := 14.0

## Split `poly` into the maximal runs of vertices NOT already within `radius` of a road on `coord`, so
## promoting a farm-web polyline never re-draws over a connect road that's already there. Each free run
## is dilated one vertex into the covered zone on each side so it still meets the road (no visible gap).
func _undoubled_runs(net: RoadNetwork, coord: Vector2i, poly: PackedVector2Array, radius: float) -> Array:
	var segs: Array = []
	for eid in net.edges_on_tile(coord):
		var g: PackedVector2Array = net.edges[eid].geometry
		for i in range(g.size() - 1):
			segs.append([g[i], g[i + 1]])
	if segs.is_empty():
		return [poly]   # nothing to double against — promote the whole polyline
	var r2 := radius * radius
	var n := poly.size()
	var include := PackedByteArray()
	include.resize(n)
	include.fill(0)
	for i in n:
		var p: Vector2 = poly[i]
		var covered := false
		for s in segs:
			if p.distance_squared_to(Geometry2D.get_closest_point_to_segment(p, s[0], s[1])) <= r2:
				covered = true
				break
		if not covered:
			include[i] = 1
			if i > 0:
				include[i - 1] = 1   # bridge backward into the covered road
			if i < n - 1:
				include[i + 1] = 1   # bridge forward
	var runs: Array = []
	var cur := PackedVector2Array()
	for i in n:
		if include[i] == 1:
			cur.append(poly[i])
		else:
			if cur.size() >= 2:
				runs.append(cur)
			cur = PackedVector2Array()
	if cur.size() >= 2:
		runs.append(cur)
	return runs

## When a player road settles ON a farm tile, promote that tile's cosmetic web (BuildingVisuals'
## outer ring + one through-path) into real RoadNetwork roads — STATE_BUILT, drawn yellow, persisted.
## One-time per tile (idempotent via _farm_promoted; the edges themselves ride in RoadNetwork state).
func _promote_farm_roads_if_reached(order: Dictionary, net) -> void:
	if not PROMOTE_FARM_RINGS:
		return
	var bv := _building_visuals()
	if bv == null or not bv.has_method("farm_promote_candidates_for_coord"):
		return
	# Every tile the settled edge actually crosses (so a road that PASSES THROUGH a farm tile promotes it,
	# not just the order's own tile). Falls back to the order's coord when the edge has no tile list.
	var coords: Array = []
	var edge: Dictionary = net.edges.get(str(order.get("edge_id", "")), {})
	for t in edge.get("tiles", []):
		coords.append(t)
	if coords.is_empty():
		coords.append(order.get("coord", Vector2i.ZERO))
	for tc in coords:
		var coord: Vector2i = tc
		var cands: Dictionary = bv.farm_promote_candidates_for_coord(coord)
		if cands.is_empty():
			continue
		var tile_id := str(cands.get("tile_id", ""))
		if tile_id == "" or bool(_farm_promoted.get(tile_id, false)):
			continue
		var polylines: Array = []
		for poly in (cands.get("ring", []) as Array):
			polylines.append(poly)
		var trunk: PackedVector2Array = cands.get("trunk", PackedVector2Array())
		if trunk.size() >= 2:
			polylines.append(trunk)
		# The connect/through road that reached this farm has ALREADY committed; promoting the ring/trunk
		# raw would DOUBLE it wherever they overlap (the parallel roads hugging a farm cluster). So promote
		# only the parts of each web polyline that aren't already within FARM_RING_DEDUP_RADIUS of a road on
		# this tile — split each polyline into its "uncovered" runs (each bridged one vertex into the road).
		var run_id := 0
		for poly in polylines:
			if (poly as PackedVector2Array).size() < 2:
				continue
			for run in _undoubled_runs(net, coord, poly, FARM_RING_DEDUP_RADIUS):
				var rp: PackedVector2Array = run
				if rp.size() < 2:
					continue
				var na: Dictionary = net.ensure_node("farmr:%s:%d:a" % [tile_id, run_id], RoadNetwork.KIND_JUNCTION, rp[0], coord)
				var nb: Dictionary = net.ensure_node("farmr:%s:%d:b" % [tile_id, run_id], RoadNetwork.KIND_JUNCTION, rp[rp.size() - 1], coord)
				net.add_edge(str(na.id), str(nb.id), RoadNetwork.TIER_LOCAL, rp, [coord], [], 0, RoadNetwork.STATE_BUILT)
				run_id += 1
		# The ring is clipped 1u inside the hex, so adjacent tiles' rings stop ~1u short of the shared edge:
		# bridge this tile's ring to the neighbour's ring at their closest approach so the two yellow roads meet.
		_bridge_ring_to_neighbours(net, coord, tile_id)
		# Flag promoted even if everything was already covered (nothing added): the cosmetic brown ring is
		# then suppressed and the existing road stands in for it, so we never re-attempt this tile.
		_farm_promoted[tile_id] = true
		farm_roads_promoted.emit(tile_id)

## Connect this tile's freshly-promoted RING to an ADJACENT farm tile's RING across the shared hex edge,
## closing the ~2-3u inset gap that leaves two tiles' yellow ring roads unjoined. Works whether the rings
## are open (clipped) or closed loops — it bridges their CLOSEST APPROACH, not endpoints. Deterministic
## (pure geometry + sorted edge iteration, no RNG), synchronous (no work order/realizer), persisted (an
## ordinary STATE_BUILT edge; _farm_links dedupes by sorted tile-pair so a reload or the other tile
## promoting never adds a second bridge for the same seam). A genuine VISUAL join (the stub's ends land ON
## each ring's centreline; it does not split the ring edges). Never bridges across water (no bridgeless
## river/lake crossing) and only fires within FARM_BRIDGE_MAX so it's a short seam stub, never a long road.
func _bridge_ring_to_neighbours(net: RoadNetwork, coord: Vector2i, tile_id: String) -> void:
	var terrain := _terrain()
	if terrain == null:
		return
	var my_segs := _ring_segments_on(net, coord)
	if my_segs.is_empty():
		return
	var cap2 := FARM_BRIDGE_MAX * FARM_BRIDGE_MAX
	for ncoord in terrain.neighbor_coords(coord):
		if not terrain.tiles.has(ncoord):
			continue
		var n_id := "tile_%d_%d" % [ncoord.x + 1, ncoord.y + 1]
		var pair := ("%s|%s" % [tile_id, n_id]) if tile_id < n_id else ("%s|%s" % [n_id, tile_id])
		if _farm_links.has(pair):
			continue   # this seam already bridged (once per adjacent pair, in either promotion order)
		var nbr_segs := _ring_segments_on(net, ncoord)
		if nbr_segs.is_empty():
			continue   # neighbour not promoted yet — its ring isn't there to bridge to
		# closest approach between my ring and the neighbour's ring (sample my vertices onto nbr segments)
		var best_a := Vector2.ZERO
		var best_b := Vector2.ZERO
		var best_d2 := cap2
		for ms in my_segs:
			for mp in [ms[0] as Vector2, ms[1] as Vector2]:
				var mpv: Vector2 = mp
				for ns in nbr_segs:
					var cp := Geometry2D.get_closest_point_to_segment(mpv, ns[0] as Vector2, ns[1] as Vector2)
					var d2 := mpv.distance_squared_to(cp)
					if d2 < best_d2:
						best_d2 = d2
						best_a = mpv
						best_b = cp
		if best_d2 >= cap2 or best_a.distance_to(best_b) < 0.5:
			continue   # no ring within FARM_BRIDGE_MAX, or already touching (no stub needed)
		if not _bridge_on_land(best_a, best_b):
			continue   # would cross water — rivers cross only at gates, lakes never
		_farm_links[pair] = true
		var ja := net.add_junction(best_a, coord)
		var jb := net.add_junction(best_b, coord)
		net.add_edge(str(ja.id), str(jb.id), RoadNetwork.TIER_LOCAL, PackedVector2Array([best_a, best_b]), [coord], [], 0, RoadNetwork.STATE_BUILT)

## The [a,b] segments of every promoted RING (farmr:) edge on `coord` — the geometry to bridge across a seam.
func _ring_segments_on(net: RoadNetwork, coord: Vector2i) -> Array:
	var segs: Array = []
	for eid in _sorted_edge_ids(net):
		var e: Dictionary = net.edges[eid]
		if not (str(e.a).begins_with("farmr:") or str(e.b).begins_with("farmr:")):
			continue
		var on_tile := false
		for t in (e.tiles as Array):
			if (t as Vector2i) == coord:
				on_tile = true
				break
		if not on_tile:
			continue
		var g: PackedVector2Array = e.geometry
		for i in range(g.size() - 1):
			segs.append([g[i], g[i + 1]])
	return segs

## RoadNetwork edge ids in stable numeric order ("e:<n>") so the bridge is deterministic across runs/reloads
## (assumes the "e:<int>" id scheme from RoadNetwork.add_edge).
func _sorted_edge_ids(net: RoadNetwork) -> Array:
	var ids: Array = net.edges.keys()
	ids.sort_custom(func(a, b): return int(str(a).split(":")[1]) < int(str(b).split(":")[1]))
	return ids

## True only when every sample of [a,b] is on land — a ring-seam bridge must never cross open water
## (rivers cross only at gates, lakes never). Degrades to true if the navgrid isn't baked yet.
func _bridge_on_land(a: Vector2, b: Vector2) -> bool:
	var nav := NavGrid.instance()
	if nav == null or not nav.is_ready():
		return true
	var n := maxi(1, int(ceil(a.distance_to(b) / (nav.step * 0.5))))
	for i in range(n + 1):
		var c := nav.cell_of(a.lerp(b, float(i) / float(n)))
		if nav.water(c.x, c.y) != NavGrid.WATER_LAND:
			return false
	return true

## The BuildingVisuals node, via the shared "building_footprints" group (mirrors RoadRealizer).
func _building_visuals() -> Node:
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return null
	var found := (loop as SceneTree).get_nodes_in_group("building_footprints")
	return found[0] if not found.is_empty() else null

## "Borrow the web": where a routed road crosses a farm cluster, replace the in-cluster portion with the
## web route from entry to exit — the SHORTEST path through the track graph (now that the inter-field web
## extends out to meet the ring, the graph is connected, so the road can thread THROUGH the cluster), or
## the ring arc as a fallback if the graph somehow has no path. Modifies res.geometry.
func _snap_route_to_web(res: Dictionary) -> void:
	var geo: PackedVector2Array = res.get("geometry", PackedVector2Array())
	if geo.size() < 3:
		return
	var bv := _building_visuals()
	if bv == null or not bv.has_method("all_farm_cluster_rings"):
		return
	for ring in bv.all_farm_cluster_rings():
		var rp: PackedVector2Array = ring
		if rp.size() < 3:
			continue
		var enter := -1
		var exit := -1
		for i in geo.size():
			if Geometry2D.is_point_in_polygon(geo[i], rp):
				if enter < 0:
					enter = i
				exit = i
		if enter < 1 or exit <= enter or exit >= geo.size() - 1:
			continue   # this ring isn't cleanly crossed
		var path := _web_path_through(bv, geo, enter, exit, rp)
		if path.size() < 2:
			continue
		var out := PackedVector2Array()
		for i in range(0, enter):
			out.append(geo[i])
		for p in path:
			out.append(p)
		for i in range(exit + 1, geo.size()):
			out.append(geo[i])
		res.geometry = out
		return   # one cluster handled

## The web route from the road's entry to its exit: shortest path through the connected track graph
## (thread THROUGH the cluster), or the ring arc as a fallback if the graph has no path.
func _web_path_through(bv: Node, geo: PackedVector2Array, enter: int, exit: int, rp: PackedVector2Array) -> PackedVector2Array:
	var p_in: Vector2 = geo[enter - 1]
	var p_out: Vector2 = geo[exit + 1]
	# Tracks near the road's bbox (grown enough to capture the whole crossed cluster).
	var bb := Rect2(geo[0], Vector2.ZERO)
	for p in geo:
		bb = bb.expand(p)
	bb = bb.grow(160.0)
	var segs: Array = []
	for s in bv.all_farm_lane_segments():
		if bb.has_point(s[0]) or bb.has_point(s[1]):
			segs.append(s)
	if segs.size() >= 2:
		var graph := _build_web_graph(segs)
		var ni := _nearest_graph_node(graph, p_in)
		var nj := _nearest_graph_node(graph, p_out)
		if ni >= 0 and nj >= 0 and ni != nj:
			var nodes_path: Array = _dijkstra_path(graph, ni, nj)
			if nodes_path.size() >= 2:
				var out := PackedVector2Array()
				for p in nodes_path:
					out.append(p)
				return out
	return _ring_arc(rp, p_in, p_out)   # fallback: around the ring

## Undirected graph from web segments: nodes are unique endpoints (deduped within 3u), edges carry their
## length; nearby nodes (<= 16u) get short connectors so junction sub-gaps don't fragment it.
func _build_web_graph(segs: Array) -> Dictionary:
	var nodes: Array = []
	var adj: Array = []
	for s in segs:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		if a.distance_to(b) < 0.5:
			continue
		var ia := _graph_node_of(nodes, adj, a)
		var ib := _graph_node_of(nodes, adj, b)
		if ia == ib:
			continue
		var d := a.distance_to(b)
		(adj[ia] as Array).append([ib, d])
		(adj[ib] as Array).append([ia, d])
	for x in nodes.size():
		for y in range(x + 1, nodes.size()):
			var dd: float = (nodes[x] as Vector2).distance_to(nodes[y])
			if dd > 3.0 and dd <= 16.0:
				(adj[x] as Array).append([y, dd])
				(adj[y] as Array).append([x, dd])
	return {"nodes": nodes, "adj": adj}

func _graph_node_of(nodes: Array, adj: Array, p: Vector2) -> int:
	for k in nodes.size():
		if (nodes[k] as Vector2).distance_to(p) < 3.0:
			return k
	nodes.append(p)
	adj.append([])
	return nodes.size() - 1

func _nearest_graph_node(graph: Dictionary, p: Vector2) -> int:
	var nodes: Array = graph.nodes
	var best := -1
	var bd := 1.0e20
	for k in nodes.size():
		var d: float = (nodes[k] as Vector2).distance_to(p)
		if d < bd:
			bd = d
			best = k
	return best

## Dijkstra shortest path (node positions) from src to dst; [] if disconnected.
func _dijkstra_path(graph: Dictionary, src: int, dst: int) -> Array:
	var nodes: Array = graph.nodes
	var adj: Array = graph.adj
	var n := nodes.size()
	var dist := PackedFloat32Array()
	dist.resize(n)
	dist.fill(1.0e20)
	var prev := PackedInt32Array()
	prev.resize(n)
	prev.fill(-1)
	var seen := PackedByteArray()
	seen.resize(n)
	dist[src] = 0.0
	while true:
		var u := -1
		var ud := 1.0e20
		for k in n:
			if seen[k] == 0 and dist[k] < ud:
				ud = dist[k]
				u = k
		if u < 0 or u == dst:
			break
		seen[u] = 1
		for e in (adj[u] as Array):
			var v: int = e[0]
			var nd: float = dist[u] + float(e[1])
			if nd < dist[v]:
				dist[v] = nd
				prev[v] = u
	if dist[dst] >= 1.0e20:
		return []
	var path: Array = []
	var cur := dst
	while cur != -1:
		path.append(nodes[cur])
		cur = prev[cur]
	path.reverse()
	return path

## The shorter boundary arc of `poly` between the boundary point nearest `p_in` and that nearest `p_out`.
func _ring_arc(poly: PackedVector2Array, p_in: Vector2, p_out: Vector2) -> PackedVector2Array:
	var n := poly.size()
	var ei := _closest_edge(poly, p_in)
	var ej := _closest_edge(poly, p_out)
	var pe: Vector2 = ei.point
	var pj: Vector2 = ej.point
	var i0: int = ei.idx
	var j0: int = ej.idx
	if i0 == j0:
		return PackedVector2Array([pe, pj])   # entry + exit on the same ring edge
	# Forward (increasing index): pe → poly[i0+1] → … → poly[j0] → pj
	var fwd := PackedVector2Array([pe])
	var k := (i0 + 1) % n
	for _g in n + 1:
		fwd.append(poly[k])
		if k == j0:
			break
		k = (k + 1) % n
	fwd.append(pj)
	# Backward (decreasing index): pe → poly[i0] → … → poly[j0+1] → pj
	var bwd := PackedVector2Array([pe])
	k = i0
	for _g in n + 1:
		bwd.append(poly[k])
		if k == (j0 + 1) % n:
			break
		k = (k - 1 + n) % n
	bwd.append(pj)
	return fwd if _polyline_len(fwd) <= _polyline_len(bwd) else bwd

## Index of the polygon edge nearest p, and the closest point on it: {idx, point}.
func _closest_edge(poly: PackedVector2Array, p: Vector2) -> Dictionary:
	var n := poly.size()
	var best := 0
	var bp: Vector2 = poly[0]
	var bd := 1.0e20
	for k in n:
		var cp := Geometry2D.get_closest_point_to_segment(p, poly[k], poly[(k + 1) % n])
		var d: float = p.distance_to(cp)
		if d < bd:
			bd = d
			best = k
			bp = cp
	return {"idx": best, "point": bp}

func _polyline_len(pl: PackedVector2Array) -> float:
	var L := 0.0
	for i in range(pl.size() - 1):
		L += pl[i].distance_to(pl[i + 1])
	return L

## Join a just-settled connect tile to any adjacent tile that already has a road
## but isn't directly joined to it. One short link order per new adjacency (the
## later-built tile of the pair drives it); _linked_pairs dedupes, and an
## existing direct edge means the connect already joined them — skip.
func _link_adjacent_roads(order: Dictionary) -> void:
	var terrain := _terrain()
	if terrain == null:
		return
	var net := RoadNetwork.instance()
	var t_id := str(order.tile_id)
	var t_node := "rw:%s" % t_id
	if not net.nodes.has(t_node):
		return
	var degree := _node_degrees(net)
	var t_deg := int(degree.get(t_node, 0))
	for ncoord in terrain.neighbor_coords(order.coord as Vector2i):
		if t_deg >= MAX_JUNCTION:
			break   # this tile's junction is full — keep it to a 5-way
		if not terrain.tiles.has(ncoord):
			continue
		var n_id := "tile_%d_%d" % [ncoord.x + 1, ncoord.y + 1]
		var n_node := "rw:%s" % n_id
		if not net.nodes.has(n_node):
			continue   # neighbour carries no road
		var key := ("%s|%s" % [t_id, n_id]) if t_id < n_id else ("%s|%s" % [n_id, t_id])
		if _linked_pairs.has(key):
			continue
		if int(degree.get(n_node, 0)) >= MAX_JUNCTION:
			continue   # neighbour's junction is full — don't overload it
		_linked_pairs[key] = true
		if _edge_between(net, t_node, n_node):
			continue   # the connect already joined these two — no extra road
		_enqueue_link(t_id, order.coord as Vector2i, t_node, net.nodes[t_node].pos,
			n_node, net.nodes[n_node].pos)
		t_deg += 1

## Committed-edge degree per node PLUS the arms that in-flight orders will add
## once they commit (a connect/link adds one to its own tile node and one to its
## attach node). Counting the reservation stops a mass-build burst from racing a
## dozen roads onto the same junction before any of their edges exist.
func _node_degrees(net: RoadNetwork) -> Dictionary:
	var deg: Dictionary = {}
	for eid in net.edges:
		var e: Dictionary = net.edges[eid]
		deg[str(e.a)] = int(deg.get(str(e.a), 0)) + 1
		deg[str(e.b)] = int(deg.get(str(e.b), 0)) + 1
	for id in orders:
		var o: Dictionary = orders[id]
		if not (str(o.state) in ["queued", "planning"]):
			continue   # revealing/built orders already own an edge counted above
		if str(o.get("kind", "connect")) in ["connect", "link"]:
			var snode := "rw:%s" % str(o.tile_id)
			deg[snode] = int(deg.get(snode, 0)) + 1
		var aid := str(o.attach_id)
		if aid != "":
			deg[aid] = int(deg.get(aid, 0)) + 1
	return deg

func _edge_between(net: RoadNetwork, a: String, b: String) -> bool:
	for eid in net.edges:
		var e: Dictionary = net.edges[eid]
		if (str(e.a) == a and str(e.b) == b) or (str(e.a) == b and str(e.b) == a):
			return true
	return false

## A short connect between two existing road nodes. kind="link" so _begin_next
## keeps these authored endpoints (no re-attach) and _settle does not recurse.
func _enqueue_link(t_id: String, coord: Vector2i, a_node: String, a_pos: Vector2, b_node: String, b_pos: Vector2) -> void:
	var id := _next_order
	_next_order += 1
	orders[id] = {
		"id": id,
		"kind": "link",
		"tile_id": t_id,
		"state": "queued",
		"start": a_pos,
		"goal": b_pos,
		"attach_id": b_node,
		"coord": coord,
		"tier": RoadNetwork.TIER_LOCAL,
		"salt": RoadHash.pick("link|%s|%s" % [a_node, b_node], 1 << 30),
		"turn": TurnManager.current_turn,
		"edge_id": "",
		"reveal_t": 0.0,
		"reason": "",
		"plan_ms": 0.0,
	}
	_queue.append(id)

## Reveal fraction for an edge mid-reveal (visuals): 1.0 when settled/unknown.
## The reveal grows from the network attachment (the goal end of the geometry)
## back toward the new tile, i.e. network-outward.
func reveal_fraction(edge_id: String) -> float:
	for id in _revealing:
		var order: Dictionary = orders[id]
		if str(order.edge_id) == edge_id:
			return float(order.reveal_t)
	return 1.0

func has_active_reveals() -> bool:
	return not _revealing.is_empty()

func pending_count() -> int:
	return _queue.size() + (1 if _active >= 0 else 0)

# ------------------------------------------------- invalidation (forests)

func _on_building_added(instance: Dictionary) -> void:
	if not ForestFootprint.is_forest(str(instance.get("building_id", ""))):
		return
	_invalidate_planned_near_forest(instance)
	if TileOccupancy.OCCUPANCY_ROADS_ENABLED:
		refresh_forest_occupancy()

func _on_building_removed(_instance_id: String) -> void:
	# The instance is already gone; conservatively refresh forests and restart
	# nothing (a removed forest only ever OPENS space).
	if TileOccupancy.OCCUPANCY_ROADS_ENABLED:
		refresh_forest_occupancy()

## A planted forest restarts orders still planning whose corridor intersects
## its disc; BUILT and revealing edges stay (history is history).
func _invalidate_planned_near_forest(instance: Dictionary) -> void:
	var terrain := _terrain()
	if terrain == null:
		return
	var tile_id := str(instance.get("tile_id", ""))
	var coord: Vector2i = terrain.id_to_coord(tile_id)
	if not terrain.tiles.has(coord):
		return
	var center: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
	# circumscribing radius is enough for an invalidation test
	var reach := ForestFootprint.RADIUS * 1.5 + 8.0 + RoadRealizer.REFINE_RADIUS
	for id in orders:
		var order: Dictionary = orders[id]
		if not (str(order.state) in ["queued", "planning"]):
			continue
		if _dist_to_segment(center, order.start, order.goal) > reach:
			continue
		if str(order.state) == "planning" and int(order.id) == _active:
			_job = {}
			_active = -1
		order.state = "queued"
		if not _queue.has(int(order.id)):
			_queue.append(int(order.id))
	orders_changed.emit()

# ---------------------------------------------------------------- occupancy

## Rebuild the "roads" occupancy producer from every BUILT edge (bootstrap,
## save import, or flag flip) and the "forests" producer from MatchState.
func rebuild_occupancy() -> void:
	if not TileOccupancy.OCCUPANCY_ROADS_ENABLED:
		return
	_road_bits.clear()
	TileOccupancy.clear_dynamic("roads")
	var net := RoadNetwork.instance()
	for edge_id in net.edges:
		var edge: Dictionary = net.edges[edge_id]
		if str(edge.state) == RoadNetwork.STATE_BUILT:
			_register_edge_occupancy(edge)
	refresh_forest_occupancy()

## Rasterize one edge's corridor (half-width + buffer) into subtile bits on
## every tile it crosses, merged into the shared "roads" producer.
func _register_edge_occupancy(edge: Dictionary) -> void:
	var terrain := _terrain()
	if terrain == null:
		return
	var half := float(OCC_HALF_WIDTH.get(str(edge.tier), 5.25))
	var geometry: PackedVector2Array = edge.geometry
	var touched := {}
	for i in range(geometry.size()):
		var p := geometry[i]
		# also stamp the midpoint to the next vertex so thin diagonals connect
		_mark_world_disc(terrain, p, half, touched)
		if i + 1 < geometry.size():
			_mark_world_disc(terrain, p.lerp(geometry[i + 1], 0.5), half, touched)
	for tile_id in touched:
		TileOccupancy.set_dynamic("roads", str(tile_id), _road_bits[tile_id])

## Mark subtile bits within `radius` of world point `p` into _road_bits,
## accumulating the touched tile ids into `touched`.
func _mark_world_disc(terrain: HexMap, p: Vector2, radius: float, touched: Dictionary) -> void:
	var coord: Vector2i = terrain.tile_coord_for_map_coord(terrain.local_to_map(p))
	for dc in NEIGHBOUR_OFFSETS:
		var c := coord + dc
		if not terrain.tiles.has(c):
			continue
		var tile_id := str(terrain.tiles[c].get("id", ""))
		if tile_id == "":
			continue
		var origin: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(c)) - Vector2(270, 240)
		var local := p - origin
		var c_lo := Vector2i(int(floor((local.x - radius) / SubtileGrid.SUBTILE_SIZE)), int(floor((local.y - radius) / SubtileGrid.SUBTILE_SIZE)))
		var c_hi := Vector2i(int(floor((local.x + radius) / SubtileGrid.SUBTILE_SIZE)), int(floor((local.y + radius) / SubtileGrid.SUBTILE_SIZE)))
		var any := false
		for sy in range(maxi(c_lo.y, 0), mini(c_hi.y, SubtileGrid.ROWS - 1) + 1):
			for sx in range(maxi(c_lo.x, 0), mini(c_hi.x, SubtileGrid.COLUMNS - 1) + 1):
				var cell_center := Vector2((sx + 0.5) * SubtileGrid.SUBTILE_SIZE, (sy + 0.5) * SubtileGrid.SUBTILE_SIZE)
				if cell_center.distance_to(local) > radius + SubtileGrid.SUBTILE_SIZE * 0.5:
					continue
				if not _road_bits.has(tile_id):
					_road_bits[tile_id] = {}
				_road_bits[tile_id][sy * SubtileGrid.COLUMNS + sx] = true
				any = true
		if any:
			touched[tile_id] = true

## Rebuild the "forests" producer: every forest disc marks the subtiles it
## covers on each tile it overlaps.
func refresh_forest_occupancy() -> void:
	if not TileOccupancy.OCCUPANCY_ROADS_ENABLED:
		return
	var terrain := _terrain()
	if terrain == null:
		return
	TileOccupancy.clear_dynamic("forests")
	var centers: Array = []
	var forests: Array = []   # [instance_id, tile_id, coord, tile_center]
	for instance_id in MatchState.buildings:
		var b: Dictionary = MatchState.buildings[instance_id]
		if not ForestFootprint.is_forest(str(b.get("building_id", ""))):
			continue
		var coord: Vector2i = terrain.id_to_coord(str(b.get("tile_id", "")))
		if not terrain.tiles.has(coord):
			continue
		var tc: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
		centers.append(tc)
		forests.append([str(instance_id), str(b.get("tile_id", "")), coord, tc])
	var bits_by_tile := {}
	for f in forests:
		var coord2: Vector2i = f[2]
		var tc2: Vector2 = f[3]
		var paths := RiverGeometry.arms(terrain.tiles[coord2], terrain.river_properties, tc2)
		var lake := RiverGeometry.lake_ellipse(terrain.tiles[coord2], terrain.river_properties, tc2)
		var disc := ForestFootprint.footprint(f[0], f[1], coord2, tc2, paths, lake, centers)
		_mark_forest_disc(terrain, disc.center, float(disc.radius), coord2, bits_by_tile)
	for tile_id in bits_by_tile:
		TileOccupancy.set_dynamic("forests", str(tile_id), bits_by_tile[tile_id])

func _mark_forest_disc(terrain: HexMap, center: Vector2, radius: float, home: Vector2i, bits_by_tile: Dictionary) -> void:
	for dc in NEIGHBOUR_OFFSETS:
		var c := home + dc
		if not terrain.tiles.has(c):
			continue
		var tile_id := str(terrain.tiles[c].get("id", ""))
		var origin: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(c)) - Vector2(270, 240)
		var local := center - origin
		var c_lo := Vector2i(int(floor((local.x - radius) / SubtileGrid.SUBTILE_SIZE)), int(floor((local.y - radius) / SubtileGrid.SUBTILE_SIZE)))
		var c_hi := Vector2i(int(floor((local.x + radius) / SubtileGrid.SUBTILE_SIZE)), int(floor((local.y + radius) / SubtileGrid.SUBTILE_SIZE)))
		for sy in range(maxi(c_lo.y, 0), mini(c_hi.y, SubtileGrid.ROWS - 1) + 1):
			for sx in range(maxi(c_lo.x, 0), mini(c_hi.x, SubtileGrid.COLUMNS - 1) + 1):
				var cell_center := Vector2((sx + 0.5) * SubtileGrid.SUBTILE_SIZE, (sy + 0.5) * SubtileGrid.SUBTILE_SIZE)
				if cell_center.distance_to(local) > radius:
					continue
				if not bits_by_tile.has(tile_id):
					bits_by_tile[tile_id] = {}
				bits_by_tile[tile_id][sy * SubtileGrid.COLUMNS + sx] = true

# ---------------------------------------------------------------- save/load

func export_state() -> Dictionary:
	var out: Array = []
	for id in orders:
		var o: Dictionary = orders[id]
		out.append({
			"id": int(o.id), "tile_id": str(o.tile_id), "state": str(o.state),
			"attach_id": str(o.attach_id), "tier": str(o.tier),
			"salt": int(o.salt), "turn": int(o.turn), "edge_id": str(o.edge_id),
			"reason": str(o.reason),
			"start": [o.start.x, o.start.y], "goal": [(o.goal as Vector2).x, (o.goal as Vector2).y],
			"coord": [(o.coord as Vector2i).x, (o.coord as Vector2i).y],
			"kind": str(o.get("kind", "connect")),
			"region_id": str(o.get("region_id", "")),
			"orbital": bool(o.get("orbital", false)),
		})
	return {"orders": out, "next_order": _next_order, "styled_regions": _styled_regions.keys(),
		"linked_pairs": _linked_pairs.keys(), "farm_promoted": _farm_promoted.keys(),
		"farm_links": _farm_links.keys()}

## BUILT geometry rides in the network state; BUILDING orders resume planning
## deterministically; mid-reveal orders restart their reveal (cosmetic only).
func import_state(d: Dictionary) -> void:
	reset()
	_next_order = int(d.get("next_order", 1))
	for region_id in d.get("styled_regions", []):
		_styled_regions[str(region_id)] = true
	for pair_key in d.get("linked_pairs", []):
		_linked_pairs[str(pair_key)] = true
	for ftile in d.get("farm_promoted", []):
		_farm_promoted[str(ftile)] = true
		farm_roads_promoted.emit(str(ftile))   # tell BuildingVisuals to suppress those brown tracks
	for flink in d.get("farm_links", []):
		_farm_links[str(flink)] = true   # a reload must not re-bridge an already-bridged seam endpoint
	# Enclosure rings were removed in roads-v3 (save v5 strips their encl:/urbanr: edges);
	# any legacy "enclosure_bands"/"enclosure_edges" keys in old dicts are simply ignored.

	for raw in d.get("orders", []):
		var o := {
			"id": int(raw.id), "tile_id": str(raw.tile_id), "state": str(raw.state),
			"attach_id": str(raw.attach_id), "tier": str(raw.tier),
			"salt": int(raw.salt), "turn": int(raw.turn), "edge_id": str(raw.edge_id),
			"reason": str(raw.get("reason", "")),
			"start": Vector2(float(raw.start[0]), float(raw.start[1])),
			"goal": Vector2(float(raw.goal[0]), float(raw.goal[1])),
			"coord": Vector2i(int(raw.coord[0]), int(raw.coord[1])),
			"reveal_t": 0.0,
			"plan_ms": 0.0,
			"kind": str(raw.get("kind", "connect")),
			"region_id": str(raw.get("region_id", "")),
			"orbital": bool(raw.get("orbital", false)),
		}
		orders[int(o.id)] = o
		match str(o.state):
			"queued", "planning":
				o.state = "queued"
				_queue.append(int(o.id))
			"revealing":
				_revealing.append(int(o.id))
	orders_changed.emit()

func reset() -> void:
	orders.clear()
	_queue.clear()
	_revealing.clear()
	_active = -1
	_job = {}
	_next_order = 1
	_road_bits.clear()
	last_frame_plan_ms = 0.0
	max_unit_ms = 0.0
	max_begin_ms = 0.0
	max_finish_ms = 0.0
	failure_log.clear()
	_styled_regions.clear()
	_preview_bridges.clear()
	_linked_pairs.clear()
	_farm_promoted.clear()
	_farm_links.clear()

# ------------------------------------------------------------------ helpers

func _terrain() -> HexMap:
	var found := get_tree().get_nodes_in_group("hex_map")
	return found[0] as HexMap if not found.is_empty() else null

func _dist_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var denom := ab.length_squared()
	if denom <= 0.0001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / denom, 0.0, 1.0)
	return point.distance_to(a + ab * t)
