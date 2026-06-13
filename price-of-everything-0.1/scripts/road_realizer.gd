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
## RESUMABLE (Phase 3): routing is a stage machine driven by begin()/step()/
## result(). step() runs bounded slices (EXPANSIONS_PER_SLICE A* expansions
## per unit) until a time budget is spent, so RoadWorks can plan inside a
## 4 ms/frame budget. route() is the synchronous wrapper (bake, debug cheat,
## tests). The A* scratch buffers live on the instance, so AT MOST ONE job
## may be in flight per RoadRealizer — give each consumer its own instance.
##
## Determinism: cost jitter and quartile crossings key off RoadHash; identical
## inputs produce identical geometry regardless of slicing (asserted by tests).

const FINE_DIRECT_MAX := 1500.0      # straight-line cutoff for single-level routing
const DIRECT_CAPSULE := 480.0        # corridor radius for direct fine jobs
const REFINE_RADIUS := 110.0         # corridor radius around the coarse polyline
const REFINE_SEGMENT := 560.0        # coarse path is refined in chunks of this length
const MAX_FINE_EXPANSIONS := 90000
const MAX_COARSE_EXPANSIONS := 60000
## Epsilon-weighted A*. Higher = greedier = far fewer expansions; the road's
## character comes from the cost terms (jitter, hug bands, serpentines), not
## from exhaustive optimality. 1.30 is the lever that lets a 100-job mass
## build plan inside the frame budget (B4); revisit at the Phase-5 visual gate.
const ROUTE_WEIGHT := 1.30
## ~84 expansions ≈ 1.2 ms of GDScript A* — the atomic pause/resume unit.
const EXPANSIONS_PER_SLICE := 84
## Corridor prep (passability raster) cells processed per pause/resume unit.
const PREP_CELLS_PER_SLICE := 1100

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
const INV_SQRT2 := 0.70710678
# unit direction components (the per-neighbour normalized() was a hot-loop sqrt)
const DIR_NX := [1.0, INV_SQRT2, 0.0, -INV_SQRT2, -1.0, -INV_SQRT2, 0.0, INV_SQRT2]
const DIR_NY := [0.0, INV_SQRT2, 1.0, INV_SQRT2, 0.0, -INV_SQRT2, -1.0, -INV_SQRT2]

# Reused scratch buffers (corridor-local). One in-flight job per instance.
var _heap_state := PackedInt32Array()
var _heap_cost := PackedFloat32Array()
var _heap_size := 0
var _score := PackedFloat32Array()
var _parent := PackedInt32Array()
var _closed := PackedByteArray()
var _passable := PackedByteArray()
var _near_net := PackedByteArray()   # corridor-local reuse-discount bitmap
var _region_out := PackedByteArray() # corridor-local outside-region penalty bitmap
# All forest discs, cached across jobs and invalidated by a mutation key over
# the forest instance set (computing ~150 footprints was a 40 ms prep spike
# per corridor). Safe: RoadWorks restarts any planning order when a forest is
# planted or removed, so a job never outlives its disc snapshot.
var _forest_discs_cache: Array = []
var _forest_discs_key := 0

# ------------------------------------------------------------------ public

## Route a job synchronously. opts: {identity: String, salt: int,
## retry_serpentine: bool}. Returns {ok, geometry: PackedVector2Array,
## tiles: Array[Vector2i], bridges: Array, expansions: int, reason: String}.
## Synchronous callers (bake, cheat, tests) have no frame budget, so they get
## THOROUGH search caps unless they say otherwise.
func route(nav: NavGrid, network: RoadNetwork, start: Vector2, goal: Vector2, opts: Dictionary = {}) -> Dictionary:
	if not opts.has("thorough"):
		opts = opts.duplicate()
		opts.thorough = true
	var job := begin(nav, network, start, goal, opts)
	while not step(job, 1.0e12):
		pass
	return result(job)

## Start a resumable routing job. Drive it with step() until it returns true,
## then read result().
func begin(nav: NavGrid, network: RoadNetwork, start: Vector2, goal: Vector2, opts: Dictionary = {}) -> Dictionary:
	var job := {
		"nav": nav, "network": network, "start": start, "goal": goal,
		"identity": str(opts.get("identity", "sparse_rural")),
		"salt": int(opts.get("salt", 0)),
		"retry_serpentine": bool(opts.get("retry_serpentine", true)),
		"thorough": bool(opts.get("thorough", false)),
		# orbital containment (spec §6): member tile coords + the cost multiplier
		# applied to cells OUTSIDE them (used by the overflow rework / runtime rings)
		"region_coords": opts.get("region_coords", []),
		"outside_mult": float(opts.get("outside_mult", 1.0)),
		"grad_k": COST_GRADIENT_K,
		"retried": false,
		"stage": "init",
		"done": false,
		"res": {},
		"full_points": [] as Array[Vector2],
		"full_levels": [] as Array[int],
		"bridges": [],
		"expansions": 0,
		"waypoints": [] as Array[Vector2],
		"seg_i": 1,
		"cursor": start,
		"seg_wide_retry": false,
		"mode": "",        # "direct" | "segments"
		"fine": {},        # in-flight fine search context
		"coarse": {},      # in-flight coarse search context
	}
	if nav == null or not nav.is_ready():
		job.done = true
		job.res = {"ok": false, "reason": "navgrid_missing"}
	return job

## Advance a job by up to budget_ms of work. Returns true when the job is
## finished (success or failure — read result()).
func step(job: Dictionary, budget_ms: float) -> bool:
	if bool(job.done):
		return true
	var t0 := Time.get_ticks_usec()
	while true:
		_advance(job)
		if bool(job.done):
			return true
		if float(Time.get_ticks_usec() - t0) * 0.001 >= budget_ms:
			return false
	return false   # unreachable

func result(job: Dictionary) -> Dictionary:
	return job.res

## Commit a routed job into the network: agree gateway tangents (first writer
## wins) and store the edge with its bridges. state defaults to BUILT; the
## RoadWorks reveal commits as BUILDING and settles later.
func commit(network: RoadNetwork, a_id: String, b_id: String, tier: String, result_dict: Dictionary, turn: int, state: String = RoadNetwork.STATE_BUILT) -> Dictionary:
	var geometry: PackedVector2Array = result_dict.geometry
	if geometry.size() >= 2:
		network.agree_tangent(a_id, (geometry[1] - geometry[0]).normalized())
		network.agree_tangent(b_id, (geometry[geometry.size() - 2] - geometry[geometry.size() - 1]).normalized())
	return network.add_edge(a_id, b_id, tier, geometry, result_dict.tiles, result_dict.bridges, turn, state)

# ------------------------------------------------------------- stage machine

## One bounded unit of work: a slice of A* expansions, or a (cheap) stage
## transition. Called in a loop by step() until the time budget is spent.
func _advance(job: Dictionary) -> void:
	match str(job.stage):
		"init":
			job.seg_wide_retry = false
			var start: Vector2 = job.start
			var goal: Vector2 = job.goal
			if start.distance_to(goal) <= FINE_DIRECT_MAX:
				job.mode = "direct"
				# Short connect jobs get a proportionally tighter corridor — the
				# state space (and so planning time) scales with corridor area.
				var radius := clampf(start.distance_to(goal) * 0.45, 200.0, DIRECT_CAPSULE)
				_fine_begin(job, [start, goal], radius, int(job.salt), start, goal)
				job.stage = "fine"
			else:
				job.mode = "segments"
				_coarse_begin(job)
				job.stage = "coarse"
		"coarse":
			var status := _coarse_step(job)
			if status == "failed":
				_fail(job, "coarse_" + str(job.coarse.get("reason", "no_route")))
			elif status == "done":
				job.waypoints = _resample(job.coarse.path, REFINE_SEGMENT)
				job.expansions = int(job.expansions) + int(job.coarse.expansions)
				job.seg_i = 1
				job.cursor = job.start
				job.stage = "seg_begin"
		"seg_begin":
			var waypoints: Array = job.waypoints
			var i: int = job.seg_i
			var target: Vector2 = job.goal if i == waypoints.size() - 1 else waypoints[i]
			job.seg_wide_retry = false
			_fine_begin(job, [job.cursor, waypoints[i]], REFINE_RADIUS, int(job.salt) + i, job.cursor, target)
			job.stage = "fine"
		"fine":
			var status := _fine_step(job)
			if status == "failed":
				if str(job.mode) == "segments" and not bool(job.seg_wide_retry):
					# fall back to a wider direct attempt for this chunk
					job.seg_wide_retry = true
					var waypoints2: Array = job.waypoints
					var i2: int = job.seg_i
					var target2: Vector2 = job.goal if i2 == waypoints2.size() - 1 else waypoints2[i2]
					_fine_begin(job, [job.cursor, target2], DIRECT_CAPSULE, int(job.salt) + i2, job.cursor, target2)
				elif str(job.mode) == "direct" and not bool(job.seg_wide_retry):
					# the tight adaptive corridor can miss a detour around water/
					# forests — retry once at the full capsule before failing
					job.seg_wide_retry = true
					_fine_begin(job, [job.start, job.goal], DIRECT_CAPSULE, int(job.salt), job.start, job.goal)
				else:
					_fail(job, ("refine_failed:" if str(job.mode) == "segments" else "") + str(job.fine.get("reason", "no_route")))
			elif status == "done":
				_append_segment(job)
				if str(job.mode) == "direct" or int(job.seg_i) >= (job.waypoints as Array).size() - 1:
					job.stage = "assembled"
				else:
					job.seg_i = int(job.seg_i) + 1
					job.stage = "seg_begin"
		"assembled":
			# serpentine post-check (spec 2.3): steep climbs must wind
			if bool(job.retry_serpentine) and not bool(job.retried):
				var climb := _total_climb(job.full_levels)
				if climb >= 2 and _direction_reversals(job.full_points) < 2:
					# keep the first attempt — a failed retry falls back to it
					job.first_attempt = {
						"points": job.full_points, "levels": job.full_levels,
						"bridges": job.bridges, "expansions": job.expansions,
					}
					job.retried = true
					job.grad_k = COST_GRADIENT_K * 2.0
					job.full_points = [] as Array[Vector2]
					job.full_levels = [] as Array[int]
					job.bridges = []
					job.stage = "init"
					return
			job.stage = "finish_smooth"
		"finish_smooth":
			job.smoothed = _smooth(_thin(job.full_points, 30.0), 1)
			job.stage = "finish"
		"finish":
			var smoothed: PackedVector2Array = job.smoothed
			job.res = {
				"ok": true,
				"geometry": smoothed,
				"tiles": _tiles_crossed(smoothed),
				"bridges": job.bridges,
				"expansions": int(job.expansions),
				"reason": "",
			}
			job.done = true
		_:
			_fail(job, "bad_stage")

func _fail(job: Dictionary, reason: String) -> void:
	# A failed serpentine retry falls back to the (valid) first attempt — the
	# old synchronous code only adopted the retry when it succeeded.
	if job.has("first_attempt"):
		var fa: Dictionary = job.first_attempt
		job.erase("first_attempt")
		job.full_points = fa.points
		job.full_levels = fa.levels
		job.bridges = fa.bridges
		job.expansions = fa.expansions
		job.stage = "finish_smooth"
		return
	job.res = {"ok": false, "reason": reason}
	job.done = true

func _append_segment(job: Dictionary) -> void:
	var seg: Dictionary = job.fine.res
	var full_points: Array[Vector2] = job.full_points
	var full_levels: Array[int] = job.full_levels
	var bridges: Array = job.bridges
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
	job.expansions = int(job.expansions) + int(seg.expansions)
	if not full_points.is_empty():
		job.cursor = full_points[full_points.size() - 1]

# -------------------------------------------------------------- coarse pass

func _coarse_begin(job: Dictionary) -> void:
	var nav: NavGrid = job.nav
	var gw := nav.coarse_gw
	var gh := nav.coarse_gh
	var s := _nearest_coarse_land(nav, job.start)
	var g := _nearest_coarse_land(nav, job.goal)
	var ctx := {
		"s": s, "g": g, "gw": gw, "gh": gh,
		"expansions": 0, "reason": "", "path": [],
		# distance-budgeted cap (unroutable far jobs must not burn the max)
		"exp_cap": MAX_COARSE_EXPANSIONS if bool(job.get("thorough", false)) \
			else clampi(int(job.start.distance_to(job.goal) / nav.coarse_step) * 140, 3000, 16000),
	}
	job.coarse = ctx
	if s < 0 or g < 0:
		ctx.reason = "no_land_endpoint"
		ctx.failed = true
		return
	_reset_search(gw * gh)
	var sx := s % gw
	var sy := int(s / float(gw))
	var gx := g % gw
	var gy := int(g / float(gw))
	ctx.gx = gx
	ctx.gy = gy
	_score[s] = 0.0
	_heap_push(s, Vector2(sx, sy).distance_to(Vector2(gx, gy)) * nav.coarse_step * ROUTE_WEIGHT)

## One slice of the coarse search. Returns "running" | "done" | "failed".
func _coarse_step(job: Dictionary) -> String:
	var ctx: Dictionary = job.coarse
	if bool(ctx.get("failed", false)):
		return "failed"
	var nav: NavGrid = job.nav
	var gw: int = ctx.gw
	var gh: int = ctx.gh
	var g: int = ctx.g
	var gx: int = ctx.gx
	var gy: int = ctx.gy
	var grid := nav.coarse
	var expansions: int = ctx.expansions
	var exp_cap: int = ctx.exp_cap
	var slice := 0
	while _heap_size > 0 and slice < EXPANSIONS_PER_SLICE:
		var cell := _heap_pop()
		if _closed[cell] == 1:
			continue
		_closed[cell] = 1
		expansions += 1
		slice += 1
		if expansions > exp_cap:
			ctx.reason = "expansion_cap"
			ctx.expansions = expansions
			return "failed"
		if cell == g:
			var path: Array[Vector2] = []
			var cur := cell
			while cur >= 0:
				path.append(nav.coarse_world_of(cur % gw, int(cur / float(gw))))
				cur = _parent[cur] - 2   # PARENT_UNVISITED (the start) ends the walk
			path.reverse()
			path[0] = job.start
			path[path.size() - 1] = job.goal
			ctx.path = path
			ctx.expansions = expansions
			return "done"
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
			if _parent[ncell] == PARENT_UNVISITED or ng < _score[ncell]:
				if _closed[ncell] == 0:
					_score[ncell] = ng
					_parent[ncell] = cell + 2
					var h := Vector2(nx, ny).distance_to(Vector2(gx, gy)) * nav.coarse_step
					_heap_push(ncell, ng + h * ROUTE_WEIGHT)
	ctx.expansions = expansions
	if _heap_size == 0:
		ctx.reason = "no_route"
		return "failed"
	return "running"

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

## Set up a corridor-local fine search. State = (corridor cell, incoming
## octant); scratch arrays on the instance hold the open search across slices.
## Prep (passability raster, gates, forests, reuse bitmap, heap seed) is itself
## CHUNKED — _fine_step runs prep units until ctx.ready, then searches.
func _fine_begin(job: Dictionary, corridor: Array, radius: float, salt: int, start: Vector2, goal: Vector2) -> void:
	var nav: NavGrid = job.nav
	var a: Vector2 = corridor[0]
	var b: Vector2 = corridor[1]
	var lo := Vector2(minf(a.x, b.x) - radius, minf(a.y, b.y) - radius)
	var hi := Vector2(maxf(a.x, b.x) + radius, maxf(a.y, b.y) + radius)
	var c0 := nav.cell_of(lo)
	var c1 := nav.cell_of(hi)
	var lw := c1.x - c0.x + 1
	var lh := c1.y - c0.y + 1
	var ctx := {
		"c0": c0, "lw": lw, "lh": lh, "salt": salt,
		"a": a, "b": b, "radius": radius, "start": start, "goal": goal,
		"ready": false, "prep_phase": "passable", "prep_row": 0,
		"expansions": 0, "goal_state": -1, "reason": "", "res": {},
		# Hopeless searches must fail FAST, but detoury legitimate routes
		# (rivers, forest fields) need real headroom — budget by job length.
		# Thorough (frame-budget-free) callers search to the hard maximum.
		"exp_cap": MAX_FINE_EXPANSIONS if bool(job.get("thorough", false)) \
			else clampi(int(start.distance_to(goal) / nav.step) * 280, 7000, 20000),
	}
	job.fine = ctx
	if lw < 2 or lh < 2:
		ctx.reason = "degenerate_corridor"
		ctx.failed = true
		return
	var lcount := lw * lh
	if _passable.size() < lcount:
		_passable.resize(lcount)
	if _near_net.size() < lcount:
		_near_net.resize(lcount)
	if _region_out.size() < lcount:
		_region_out.resize(lcount)

## One bounded prep unit. Returns when the unit's work is done; flips
## ctx.ready after the final phase.
func _fine_prep_unit(job: Dictionary) -> void:
	var ctx: Dictionary = job.fine
	var nav: NavGrid = job.nav
	var c0: Vector2i = ctx.c0
	var lw: int = ctx.lw
	var lh: int = ctx.lh
	match str(ctx.prep_phase):
		"passable":
			var rows := maxi(1, int(PREP_CELLS_PER_SLICE / float(lw)))
			var row0: int = ctx.prep_row
			_build_passable_rows(nav, c0, lw, row0, mini(row0 + rows, lh), ctx.a, ctx.b, float(ctx.radius))
			ctx.prep_row = row0 + rows
			if int(ctx.prep_row) >= lh:
				ctx.prep_phase = "gates"
		"gates":
			_open_crossing_gates(nav, c0, lw, lh)
			ctx.prep_phase = "forests"
		"forests":
			if not ctx.has("forest_list"):
				ctx.forest_list = _forest_discs_in(nav, c0, lw, lh)
				ctx.forest_i = 0
			var fl: Array = ctx.forest_list
			var f1 := mini(int(ctx.forest_i) + 8, fl.size())   # ≤8 disc rasters per unit
			_block_forest_discs_range(nav, c0, lw, lh, fl, int(ctx.forest_i), f1)
			ctx.forest_i = f1
			if f1 >= fl.size():
				ctx.prep_phase = "nearnet"
		"nearnet":
			if not ctx.has("nearnet_keys"):
				_near_net.fill(0)   # C++ fill — a GDScript per-index zeroing loop cost ~10 ms
				ctx.nearnet_keys = _near_net_keys(nav, job.network, c0, lw, lh)
				ctx.nearnet_i = 0
			var keys: Array = ctx.nearnet_keys
			var i0: int = ctx.nearnet_i
			var i1 := mini(i0 + 130, keys.size())
			_scatter_near_net(nav, c0, lw, lh, keys, i0, i1)
			ctx.nearnet_i = i1
			if i1 >= keys.size():
				ctx.prep_phase = "region"
		"region":
			var region: Array = job.region_coords
			if region.is_empty() or float(job.outside_mult) <= 1.0:
				ctx.use_region = false
				ctx.prep_phase = "seed"
				return
			if not ctx.has("region_i"):
				_region_out.fill(1)   # default: everything is outside
				ctx.region_i = 0
				ctx.use_region = true
			var terrain := _terrain()
			if terrain == null:
				ctx.use_region = false
				ctx.prep_phase = "seed"
				return
			var r1 := mini(int(ctx.region_i) + 2, region.size())   # 2 hex rasters per unit
			_clear_region_hexes(nav, terrain, c0, lw, lh, region, int(ctx.region_i), r1)
			ctx.region_i = r1
			if r1 >= region.size():
				ctx.prep_phase = "seed"
		"seed":
			var s_local := _nearest_passable_local(nav, c0, lw, lh, ctx.start)
			var g_local := _nearest_passable_local(nav, c0, lw, lh, ctx.goal)
			if s_local < 0 or g_local < 0:
				ctx.reason = "no_passable_endpoint"
				ctx.failed = true
				return
			_reset_search(lw * lh * 8)
			ctx.g_local = g_local
			ctx.gx_l = g_local % lw
			ctx.gy_l = int(g_local / float(lw))
			ctx.turn_mult = float(TURN_MULT_BY_IDENTITY.get(str(job.identity), 1.0))
			ctx.jitter_amp = float(JITTER_BY_IDENTITY.get(str(job.identity), 0.06))
			for d0 in 8:
				var st := s_local * 8 + d0
				_score[st] = 0.0
				_parent[st] = PARENT_ROOT
				var sx := s_local % lw
				var sy := int(s_local / float(lw))
				_heap_push(st, Vector2(sx - int(ctx.gx_l), sy - int(ctx.gy_l)).length() * nav.step * ROUTE_WEIGHT)
			ctx.ready = true

## One slice of the fine search (or one prep unit while the corridor is being
## prepared). Returns "running" | "done" | "failed". On "done", job.fine.res
## holds {ok, raw_points, raw_levels, bridges, expansions}.
func _fine_step(job: Dictionary) -> String:
	var ctx: Dictionary = job.fine
	if bool(ctx.get("failed", false)):
		return "failed"
	if not bool(ctx.get("ready", false)):
		_fine_prep_unit(job)
		return "failed" if bool(ctx.get("failed", false)) else "running"
	if int(ctx.get("goal_state", -1)) >= 0:
		# goal found last unit — reconstruction + bridge scan is its own unit
		_fine_reconstruct(job)
		return "done"
	var nav: NavGrid = job.nav
	var c0: Vector2i = ctx.c0
	var lw: int = ctx.lw
	var lh: int = ctx.lh
	var g_local: int = ctx.g_local
	var gx_l: int = ctx.gx_l
	var gy_l: int = ctx.gy_l
	var turn_mult: float = ctx.turn_mult
	var jitter_amp: float = ctx.jitter_amp
	var salt: int = ctx.salt
	var grad_k: float = job.grad_k
	var step_u := nav.step
	var expansions: int = ctx.expansions
	var exp_cap: int = ctx.exp_cap
	# hoisted hot-loop locals (member access on RefCounted is slow in GDScript)
	var cells: PackedByteArray = nav.cells
	var dist4: PackedByteArray = nav.dist4
	var nav_gw: int = nav.gw
	var nav_gh: int = nav.gh
	var use_region: bool = bool(ctx.get("use_region", false))
	var outside_mult: float = job.outside_mult
	var slice := 0
	var goal_state := -1
	while _heap_size > 0 and slice < EXPANSIONS_PER_SLICE:
		var state := _heap_pop()
		if _closed[state] == 1:
			continue
		_closed[state] = 1
		expansions += 1
		slice += 1
		if expansions > exp_cap:
			ctx.reason = "expansion_cap"
			ctx.expansions = expansions
			return "failed"
		var cell := int(state / 8.0)
		if cell == g_local:
			goal_state = state
			break
		var dir := state % 8
		var cx := cell % lw
		var cy := int(cell / float(lw))
		var nav_idx := (c0.y + cy) * nav_gw + (c0.x + cx)
		var cur_level := (cells[nav_idx] & 0x0F) - 1
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
			var wx_n := c0.x + nx
			var wy_n := c0.y + ny
			var n_nav := wy_n * nav_gw + wx_n
			var next_level := (cells[n_nav] & 0x0F) - 1
			var move := step_u * float(DIR_LEN[nd])
			var dl := next_level - cur_level
			move *= 1.0 + COST_ALTITUDE_PER_LEVEL * absf(float(dl))
			move *= 1.0 + COST_VALLEY * maxf(float(next_level), 0.0)
			# river hug band from the baked water distance
			var wd := float(dist4[n_nav]) * 4.0
			if wd >= 30.0 and wd <= 60.0:
				move *= COST_HUG_DISCOUNT
			elif wd > 13.0 and wd < 30.0:
				move *= COST_HUG_CROWD
			# serpentines: moving along the height gradient on steep ground is
			# dear (inlined, sqrt-free until the steep branch actually fires)
			var grad_len_sq := 0.0
			var gx_f := 0.0
			var gy_f := 0.0
			if wx_n > 0 and wy_n > 0 and wx_n < nav_gw - 1 and wy_n < nav_gh - 1:
				gx_f = float((cells[n_nav + 1] & 0x0F) - (cells[n_nav - 1] & 0x0F))
				gy_f = float((cells[n_nav + nav_gw] & 0x0F) - (cells[n_nav - nav_gw] & 0x0F))
				grad_len_sq = gx_f * gx_f + gy_f * gy_f
			if grad_len_sq >= STEEP_GRAD:
				var grad_len := sqrt(grad_len_sq)
				var along := absf(float(DIR_NX[nd]) * gx_f + float(DIR_NY[nd]) * gy_f) / grad_len
				move *= 1.0 + grad_k * along * clampf(grad_len / 2.0, 0.0, 1.0)
			# reuse discount: merge with the existing network (precomputed bitmap)
			if _near_net[ncell] == 1:
				move *= COST_REUSE
			# orbital containment: leaving the region's member tiles is dear
			if use_region and _region_out[ncell] == 1:
				move *= outside_mult
			# organic wobble
			move *= 1.0 + RoadHash.jitter01(wx_n, wy_n, salt) * jitter_amp
			# turn penalty (+ hairpin waiver on steep climbs)
			var delta: int = absi(dir - nd)
			delta = mini(delta, 8 - delta)
			var turn := 0.0
			match delta:
				1: turn = TURN_45 * step_u
				2: turn = TURN_90 * step_u
				3, 4: turn = TURN_135 * step_u
			if delta >= 3 and grad_len_sq >= STEEP_GRAD and absi(dl) >= 1:
				turn *= HAIRPIN_WAIVER
			move += turn * turn_mult
			var ng := cur_g + move
			if _parent[nstate] == PARENT_UNVISITED or ng < _score[nstate]:
				_score[nstate] = ng
				_parent[nstate] = state + 2
				var dx_h := float(nx - gx_l)
				var dy_h := float(ny - gy_l)
				_heap_push(nstate, ng + sqrt(dx_h * dx_h + dy_h * dy_h) * step_u * ROUTE_WEIGHT)
	ctx.expansions = expansions
	if goal_state < 0:
		if _heap_size == 0:
			ctx.reason = "no_route"
			return "failed"
		return "running"
	ctx.goal_state = goal_state   # reconstruction happens as the NEXT unit
	return "running"

## Reconstruct points + levels + bridges (gate traversals) — one prep-sized
## unit, separated from the search slice that found the goal.
func _fine_reconstruct(job: Dictionary) -> void:
	var ctx: Dictionary = job.fine
	var nav: NavGrid = job.nav
	var c0: Vector2i = ctx.c0
	var lw: int = ctx.lw
	var raw_points: Array[Vector2] = []
	var raw_levels: Array[int] = []
	var cursor: int = ctx.goal_state
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
		cursor = (parent - 2) if parent != PARENT_ROOT else -1
	raw_points.reverse()
	raw_levels.reverse()
	ctx.res = {
		"ok": true, "raw_points": raw_points, "raw_levels": raw_levels,
		"bridges": _bridges_for_path(nav, raw_points), "expansions": int(ctx.expansions),
	}

## Corridor-local passability for rows [row0, row1): land inside the capsule.
## Gates/forests are applied afterwards by their own prep phases.
func _build_passable_rows(nav: NavGrid, c0: Vector2i, lw: int, row0: int, row1: int, a: Vector2, b: Vector2, radius: float) -> void:
	var seg := b - a
	var seg_len_sq := maxf(seg.length_squared(), 1.0)
	var r_sq := radius * radius
	for ly in range(row0, row1):
		for lx in lw:
			var li := ly * lw + lx
			var world := nav.world_of(c0.x + lx, c0.y + ly)
			var t := clampf((world - a).dot(seg) / seg_len_sq, 0.0, 1.0)
			if world.distance_squared_to(a + seg * t) > r_sq:
				_passable[li] = 0
				continue
			var w := nav.cells[(c0.y + ly) * nav.gw + (c0.x + lx)] >> 4
			_passable[li] = 1 if w == NavGrid.WATER_LAND else 0

## Crossing gates re-open river cells along the bridge line (principle (a)).
func _open_crossing_gates(nav: NavGrid, c0: Vector2i, lw: int, lh: int) -> void:
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

## Forest discs are hard obstacles (spec section 1); rasterized in chunks.
func _block_forest_discs_range(nav: NavGrid, c0: Vector2i, lw: int, lh: int, discs: Array, i0: int, i1: int) -> void:
	for i in range(i0, i1):
		var disc: Dictionary = discs[i]
		var dc: Vector2 = disc.center
		var dr: float = disc.radius + 8.0   # FOREST_ROAD_BUFFER
		var d0 := nav.cell_of(dc - Vector2(dr, dr))
		var d1 := nav.cell_of(dc + Vector2(dr, dr))
		for ny2 in range(maxi(d0.y, c0.y), mini(d1.y, c0.y + lh - 1) + 1):
			for nx2 in range(maxi(d0.x, c0.x), mini(d1.x, c0.x + lw - 1) + 1):
				if nav.world_of(nx2, ny2).distance_squared_to(dc) <= dr * dr:
					_passable[(ny2 - c0.y) * lw + (nx2 - c0.x)] = 0

## Reuse-discount bitmap support: built by SCATTERING from the network's
## occupancy set (O(network size)) instead of probing per corridor cell
## (O(corridor x 9 dict probes)) — that probe loop was a 30+ ms prep spike.
## _near_net_keys collects the occupied cells near the corridor; _scatter_
## near_net marks a key range (chunked across prep units).
func _near_net_keys(nav: NavGrid, network: RoadNetwork, c0: Vector2i, lw: int, lh: int) -> Array:
	if network == null or not network.has_any_edges():
		return []
	var cell_u := RoadNetwork.OCCUPANCY_CELL
	# corridor bounds in occupancy-cell space (±1 cell: the near_network test)
	var lo_w := nav.world_of(c0.x, c0.y)
	var hi_w := nav.world_of(c0.x + lw - 1, c0.y + lh - 1)
	var oc_lo := Vector2i(int(floor(lo_w.x / cell_u)) - 1, int(floor(lo_w.y / cell_u)) - 1)
	var oc_hi := Vector2i(int(floor(hi_w.x / cell_u)) + 1, int(floor(hi_w.y / cell_u)) + 1)
	var keys: Array = []
	for key in network.occupied_cells():
		var oc: Vector2i = key
		if oc.x >= oc_lo.x and oc.y >= oc_lo.y and oc.x <= oc_hi.x and oc.y <= oc_hi.y:
			keys.append(oc)
	return keys

## Clear the outside-region penalty bitmap inside member hexes [i0, i1).
## Inline flat-top hex test: |dx|<=270, |dy|<=240, 240|dx|+135|dy|<=64800
## (vertices (135,0)(405,0)(540,240)(405,480)(135,480)(0,240), centre (270,240)).
func _clear_region_hexes(nav: NavGrid, terrain: HexMap, c0: Vector2i, lw: int, lh: int, region: Array, i0: int, i1: int) -> void:
	for i in range(i0, i1):
		var coord: Vector2i = region[i]
		if not terrain.tiles.has(coord):
			continue
		var center: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
		var lo := nav.cell_of(center - Vector2(270.0, 240.0))
		var hi := nav.cell_of(center + Vector2(270.0, 240.0))
		for ny in range(maxi(lo.y, c0.y), mini(hi.y, c0.y + lh - 1) + 1):
			for nx in range(maxi(lo.x, c0.x), mini(hi.x, c0.x + lw - 1) + 1):
				var w := nav.world_of(nx, ny)
				var dx := absf(w.x - center.x)
				var dy := absf(w.y - center.y)
				if dx <= 270.0 and dy <= 240.0 and 240.0 * dx + 135.0 * dy <= 64800.0:
					_region_out[(ny - c0.y) * lw + (nx - c0.x)] = 0

func _scatter_near_net(nav: NavGrid, c0: Vector2i, lw: int, lh: int, keys: Array, i0: int, i1: int) -> void:
	var cell_u := RoadNetwork.OCCUPANCY_CELL
	for i in range(i0, i1):
		var oc: Vector2i = keys[i]
		# every nav cell whose 24u cell is within ±1 of this occupied cell
		var w_lo := Vector2(float(oc.x - 1) * cell_u, float(oc.y - 1) * cell_u)
		var w_hi := Vector2(float(oc.x + 2) * cell_u, float(oc.y + 2) * cell_u)
		var n_lo := nav.cell_of(w_lo)
		var n_hi := nav.cell_of(w_hi)
		for ny in range(maxi(n_lo.y, c0.y), mini(n_hi.y, c0.y + lh - 1) + 1):
			for nx in range(maxi(n_lo.x, c0.x), mini(n_hi.x, c0.x + lw - 1) + 1):
				_near_net[(ny - c0.y) * lw + (nx - c0.x)] = 1

## Rebuild the forest-disc cache now if stale — call OUTSIDE the frame budget
## (e.g. at enqueue, in turn context) so the ~40 ms rebuild never lands inside
## a budgeted planning frame.
func warm_forest_cache() -> void:
	var terrain: HexMap = _terrain()
	if terrain != null:
		_ensure_forest_discs(terrain)

## Forest obstacle discs intersecting the corridor, from the cached full-map
## disc list (rebuilt when the forest instance set changes).
func _forest_discs_in(nav: NavGrid, c0: Vector2i, lw: int, lh: int) -> Array:
	var terrain: HexMap = _terrain()
	if terrain == null:
		return []
	_ensure_forest_discs(terrain)
	var rect := Rect2(nav.world_of(c0.x, c0.y), Vector2(lw * nav.step, lh * nav.step)).grow(80.0)
	var out: Array = []
	for disc in _forest_discs_cache:
		if rect.grow(float(disc.radius)).has_point(disc.center):
			out.append(disc)
	return out

## Order-independent mutation key over the forest instance set.
func _forest_key() -> int:
	var key := 1
	for instance_id in MatchState.buildings:
		if ForestFootprint.is_forest(str(MatchState.buildings[instance_id].get("building_id", ""))):
			key = (key + hash(instance_id)) & 0x7FFFFFFF
	return key

func _ensure_forest_discs(terrain: HexMap) -> void:
	var key := _forest_key()   # always >= 1, so the initial 0 forces a build
	if key == _forest_discs_key:
		return
	_forest_discs_key = key
	_forest_discs_cache = []
	# All forest tile centres feed the gravitate-toward-neighbours pull, so the
	# disc lands on the same clumped centre the visual draws.
	var centers: Array = []
	var forests: Array = []   # [instance_id, tile_id, coord, center]
	for instance_id in MatchState.buildings:
		var b: Dictionary = MatchState.buildings[instance_id]
		if not ForestFootprint.is_forest(str(b.get("building_id", ""))):
			continue
		var tile_id := str(b.get("tile_id", ""))
		var coord: Vector2i = terrain.id_to_coord(tile_id)
		if not terrain.tiles.has(coord):
			continue
		var center: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
		centers.append(center)
		forests.append([str(instance_id), tile_id, coord, center])
	for f in forests:
		var coord2: Vector2i = f[2]
		var center2: Vector2 = f[3]
		var paths := _river_paths_for(terrain, coord2)
		var lake := RiverGeometry.lake_ellipse(terrain.tiles[coord2], terrain.river_properties, center2)
		_forest_discs_cache.append(ForestFootprint.footprint(f[0], f[1], coord2, center2, paths, lake, centers))

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
	# True ring-perimeter scan, O(8r) per ring. (The old full-square loop with a
	# perimeter skip test burned ~18k iterations per blocked endpoint — a 4-5 ms
	# tax on every search whose endpoint sat inside a forest disc.)
	var c := nav.cell_of(world)
	var lx := clampi(c.x - c0.x, 0, lw - 1)
	var ly := clampi(c.y - c0.y, 0, lh - 1)
	if _passable[ly * lw + lx] == 1:
		return ly * lw + lx
	for radius in range(1, 24):
		# top and bottom rows of the ring (dy = ±radius), left-to-right
		for dy: int in [-radius, radius]:
			var ny: int = ly + dy
			if ny < 0 or ny >= lh:
				continue
			for dx in range(-radius, radius + 1):
				var nx: int = lx + dx
				if nx < 0 or nx >= lw:
					continue
				if _passable[ny * lw + nx] == 1:
					return ny * lw + nx
		# left and right columns (corners already covered above)
		for dx2: int in [-radius, radius]:
			var nx2: int = lx + dx2
			if nx2 < 0 or nx2 >= lw:
				continue
			for dy2 in range(-radius + 1, radius):
				var ny2: int = ly + dy2
				if ny2 < 0 or ny2 >= lh:
					continue
				if _passable[ny2 * lw + nx2] == 1:
					return ny2 * lw + nx2
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
#
# Parent encoding: 0 = unvisited, 1 = root, else parent_state + 2. Zero-default
# lets _reset_search clear EXACTLY `states` entries via resize (C++ memset)
# instead of fill() over the whole high-water buffer — filling a 600k-entry
# buffer for a 20k-state corridor was a 2-4 ms tax on every search start.
const PARENT_UNVISITED := 0
const PARENT_ROOT := 1

func _reset_search(states: int) -> void:
	_heap_size = 0
	_closed.resize(0)
	_closed.resize(states)   # zero-filled
	_parent.resize(0)
	_parent.resize(states)   # zero-filled = PARENT_UNVISITED
	if _score.size() < states:
		_score.resize(states)   # stale values are fine — guarded by _parent
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
