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

var orders: Dictionary = {}     # id -> order dict
var _queue: Array = []          # order ids awaiting planning (FIFO)
var _active: int = -1           # order id currently planning
var _revealing: Array = []      # order ids mid-reveal
var _next_order := 1
## Regions whose style jobs (spec §6) have already been generated — each region
## grows its web exactly once, on its first member road (persisted in saves).
var _styled_regions: Dictionary = {}
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
	if not RoadNetwork.v2_enabled:
		return
	var building_id := str(MatchState.get_building(instance_id).get("building_id", ""))
	var internal := str(Catalog.get_building(building_id).get("internal_name", ""))
	if internal != "roads":
		return
	enqueue_for_tile(tile_id)

## Queue a connect-to-network job for the tile (spec: road built on tile T
## plans jobs for T only). Returns the order id, or -1 when skipped.
func enqueue_for_tile(tile_id: String) -> int:
	for id in orders:
		var existing: Dictionary = orders[id]
		if str(existing.tile_id) == tile_id and str(existing.state) in ["queued", "planning"]:
			return int(id)   # already pending for this tile
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
	# lands inside a budgeted planning frame.
	_realizer.warm_forest_cache()
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
	orders_changed.emit()
	return id2

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
func _nearest_attachment(from: Vector2) -> Dictionary:
	var net := RoadNetwork.instance()
	var best: Dictionary = {}
	var best_d := 1e30
	for node_id in net.nodes:
		var node: Dictionary = net.nodes[node_id]
		var d: float = (node.pos as Vector2).distance_squared_to(from)
		if d < best_d:
			best_d = d
			best = {"pos": node.pos, "id": str(node.id)}
	for edge_id in net.edges:
		var geometry: PackedVector2Array = net.edges[edge_id].geometry
		# sparse samples are plenty (~60-100 u apart) — the realizer's reuse
		# discount snaps the final approach onto the road anyway, and this runs
		# inside the planning frame for every order start
		for i in range(0, geometry.size(), 8):
			var d2 := geometry[i].distance_squared_to(from)
			if d2 < best_d:
				best_d = d2
				best = {"pos": geometry[i], "id": ""}
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
		# buffered, NOT printed — stdout flush (and push_warning's backtrace,
		# ~40 ms) cannot run inside the planning frame budget
		failure_log.append("order %d (%s): %s" % [int(order.id), str(order.tile_id), str(order.reason)])
		orders_changed.emit()
		return
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
	if TileOccupancy.OCCUPANCY_ROADS_ENABLED:
		var edge: Dictionary = net.edges.get(str(order.edge_id), {})
		if not edge.is_empty():
			_register_edge_occupancy(edge)
	order_settled.emit(int(order.id))
	# Roads appear only where the player builds (roadsv2.5 ruling): a settled
	# member road does NOT auto-grow the whole region's web — it just connects
	# this tile into the network. Regional beltways/webs exist only in the baked
	# starting cities (tools/bake_roads via RoadRegionJobs.realize_region).
	# enqueue_region_jobs() is kept for the bake path and possible future use.
	orders_changed.emit()

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
	return {"orders": out, "next_order": _next_order, "styled_regions": _styled_regions.keys()}

## BUILT geometry rides in the network state; BUILDING orders resume planning
## deterministically; mid-reveal orders restart their reveal (cosmetic only).
func import_state(d: Dictionary) -> void:
	reset()
	_next_order = int(d.get("next_order", 1))
	for region_id in d.get("styled_regions", []):
		_styled_regions[str(region_id)] = true
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
