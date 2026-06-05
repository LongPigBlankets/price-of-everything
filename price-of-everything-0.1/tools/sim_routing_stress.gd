extends SceneTree
# Headless ROUTING STRESS test. Builds N coal mines in the far north of the map and
# road corridors hauling their coal all the way down to Stoneshore Docks (tile_5_10),
# selling to market every turn. Seaport auto-subscribe is DISABLED so every sale routes
# the full distance over multiple turns — this is what exercises the pathfinder and the
# in-transit shipment list (the two things the routing-optimisation branch touches).
#
#   <godot> --headless --path . --script res://tools/sim_routing_stress.gd -- [turns]
#
# Reports per-turn PROCESS timing: mean, median, p90, max (the [TurnProfiler] lines are
# also printed every turn for the watcher).

const PORT := "tile_5_10"
const TURNS_DEFAULT := 80
const TARGET_ROADS := 30
const MINES_PER_TILE := 2
# Far-north tiles carrying a coal deposit (rows 1-4). 2 mines each = 10 coal mines.
const MINE_TILES := ["tile_12_1", "tile_22_3", "tile_7_4", "tile_8_4", "tile_15_4"]
const FREE_LAND := 100.0
const LAND_PATCH := 10.0
const LAND_PATCH_COST := 10.0

var MatchState: Node
var Stockpile: Node
var MarketState: Node
var Catalog: Node
var Production: Node
var TurnManager: Node
var RunMetrics: Node

var _stub
var _road_cost := 0.0
var _land_owned: Dictionary = {}
var _road_tiles: Dictionary = {}
var _cabled: Dictionary = {}
var _turn_ms: Array = []
var _build_turns: Dictionary = {}   # turn number -> ms, for turns that built mid-run
var _mode := "road"                 # "road" = furnace+new road every 5t; "cable" = cable-only


func _resolve() -> void:
	var r := get_root()
	MatchState = r.get_node("MatchState")
	Stockpile = r.get_node("Stockpile")
	MarketState = r.get_node("MarketState")
	Catalog = r.get_node("Catalog")
	Production = r.get_node("Production")
	TurnManager = r.get_node("TurnManager")
	RunMetrics = r.get_node("RunMetrics")


func _tile_path(src: String, dst: String) -> Array:
	# Shortest chain of ADJACENT LAND tiles src->dst (roads are land-only).
	if src == dst:
		return [src]
	var prev: Dictionary = {src: ""}
	var q: Array = [src]
	var head := 0
	while head < q.size():
		var u: String = str(q[head])
		head += 1
		if u == dst:
			break
		for nb in Catalog.tile_neighbours(u):
			var n := str(nb)
			if prev.has(n):
				continue
			if n != dst and not Catalog.is_land_tile(n):
				continue
			prev[n] = u
			q.append(n)
	if not prev.has(dst):
		return [src, dst]
	var path: Array = [dst]
	var c := dst
	while c != src:
		c = str(prev[c])
		path.push_front(c)
	return path


func _lay_road(tile: String) -> void:
	if not Catalog.tile_has_infrastructure(tile, "roads"):
		MatchState.add_money(-_road_cost)
		Catalog.add_tile_infrastructure(tile, "roads")
	_road_tiles[tile] = true


func _cable(tile: String) -> void:
	# Mirror the real game: placing a building cables its tile, which routes power AND,
	# crucially, calls Catalog.add_tile_infrastructure(tile, "cables"). That cable add is
	# exactly what used to clear the whole route cache pre–Phase 1. The sim must cable
	# through Catalog (not just the stub) for the Phase-1 fix to actually be exercised.
	_stub.set_cabled_tile(tile)
	Catalog.add_tile_infrastructure(tile, "cables")
	_cabled[tile] = true


func _place(building_id: String, recipe_id: String, tile: String) -> String:
	var size: float = float(Catalog.get_building(building_id).get("tile_size_used", 30.0))
	var projected: float = MatchState.get_tile_space_used(tile) + size
	var owned: float = float(_land_owned.get(tile, FREE_LAND))
	if projected > owned:
		var patches: int = int(ceil((projected - owned) / LAND_PATCH))
		MatchState.add_money(-float(patches) * LAND_PATCH_COST)
		_land_owned[tile] = owned + float(patches) * LAND_PATCH
	MatchState.add_money(-float(Catalog.get_building(building_id).get("base_price", 80.0)))
	return MatchState.add_building(building_id, recipe_id, tile)


func _place_mine(tile: String) -> String:
	return _place("b_001", "r_001", tile)


# Mid-run build: lay a road corridor port->target (grows the routing network and clears the
# route cache — a routing-mode change), cable the tile (the Phase-1 cable-skip case), and
# place a furnace. The furnace has no inputs delivered so it starves — harmless; the point
# is to grow the network and trigger a build mid-run, as in real play.
func _add_furnace_road(target: String) -> void:
	for t in _tile_path(PORT, str(target)):
		_lay_road(str(t))
	_cable(str(target))
	var inst := _place(str("b_002"), "r_003", str(target))
	MatchState.route_output_to_market(inst, "g_006")
	MatchState.enable_sell_surplus(str(target))


# Cable-only mid-run build: furnace on an ALREADY-roaded corridor tile, cabling it but
# adding NO new road. The cable is the sole infra change — under Phase 1 the route cache
# is preserved (cables don't affect goods routes); pre-Phase-1 it was fully cleared,
# forcing every route to recompute next turn. This is the case that isolates Phase 1.
func _add_furnace_cableonly(tile: String) -> void:
	_cable(str(tile))
	var inst := _place(str("b_002"), "r_003", str(tile))
	MatchState.route_output_to_market(inst, "g_006")
	MatchState.enable_sell_surplus(str(tile))


func _initialize() -> void:
	_resolve()
	var args := OS.get_cmdline_user_args()
	var turns := TURNS_DEFAULT
	if args.size() > 0 and str(args[0]).is_valid_int():
		turns = int(args[0])
	if args.size() > 1:
		_mode = str(args[1])

	print("\n==== ROUTING STRESS [mode=%s]: %d coal mines, road haul to %s, %d turns ====" % [_mode, MINE_TILES.size() * MINES_PER_TILE, PORT, turns])
	_stub = _HexMapStub.new()
	get_root().add_child(_stub)
	TurnManager.fast_mode = true
	# DISABLE seaport subscriptions so sales route the full distance every turn (the point
	# of the test). With it on, mines within 10 tiles of the port would ship in 1 covered
	# turn with no routing, hiding the cost we are measuring.
	MatchState.seaport_auto_subscribe = false
	MatchState.set_sell_mode(MatchState.SellMode.BUILDING_BY_BUILDING)
	await process_frame
	await process_frame
	await process_frame
	if RunMetrics and RunMetrics.has_method("reset"):
		RunMetrics.reset()
	_road_cost = float(Catalog.get_building("b_005").get("base_price", 25.0))

	MatchState.money = 10000.0
	if MatchState.has_signal("money_changed"):
		MatchState.money_changed.emit(MatchState.money)

	# 1) Place coal mines + cable each mine tile + route coal to market.
	var mine_count := 0
	for tile in MINE_TILES:
		_lay_road(tile)
		_cable(str(tile))
		for _i in range(MINES_PER_TILE):
			var inst := _place_mine(str(tile))
			MatchState.route_output_to_market(inst, "g_001")
			mine_count += 1
		MatchState.enable_sell_surplus(str(tile))

	# 2) Road corridors: full adjacent-tile road path from each mine tile down to the
	#    port, so coal can actually be hauled there. Stop starting new corridors once we
	#    have >= TARGET_ROADS distinct road tiles (but always finish the current path so
	#    the mine stays connected).
	for tile in MINE_TILES:
		if _road_tiles.size() >= TARGET_ROADS:
			break
		for t in _tile_path(str(tile), PORT):
			_lay_road(str(t))

	if MatchState.has_signal("money_changed"):
		MatchState.money_changed.emit(MatchState.money)
	await process_frame
	await process_frame
	print("[stress] setup: mines=%d road_tiles=%d cash=%.0f buildings=%d" % [
		mine_count, _road_tiles.size(), MatchState.money, MatchState.buildings.size()])

	# Mid-run build targets.
	var targets: Array = []
	if _mode == "cable":
		# Existing roaded-but-uncabled corridor tiles: a furnace here cables the tile with
		# NO new road, so a cable is the only infra change (isolates Phase 1).
		for rt in _road_tiles.keys():
			if not _cabled.has(rt):
				targets.append(str(rt))
	else:
		# Northern land tiles (rows 1-9), farthest from the port first, so each furnace's
		# road corridor is long and the cold-cache recompute on its build turn is heavy.
		for col in range(1, 31):
			for row in range(1, 10):
				var tid := "tile_%d_%d" % [col, row]
				if tid == PORT or MINE_TILES.has(tid):
					continue
				if Catalog.is_land_tile(tid):
					targets.append(tid)
		targets.sort_custom(func(x, y): return Catalog.tile_hex_distance(PORT, x) > Catalog.tile_hex_distance(PORT, y))

	# 3) Run turns. Every 5th turn, build a new furnace + road corridor mid-run (the case
	#    that stresses the route-cache invalidation). TurnProfiler prints per turn; we also
	#    collect the per-turn wall time and tag which turns were build turns.
	var build_idx := 0
	for t in range(turns):
		var turn := t + 1
		var built := false
		if turn % 5 == 0 and build_idx < targets.size():
			if _mode == "cable":
				_add_furnace_cableonly(str(targets[build_idx]))
			else:
				_add_furnace_road(str(targets[build_idx]))
			build_idx += 1
			built = true
		var t0 := Time.get_ticks_usec()
		TurnManager.commit_turn()
		await TurnManager.turn_resolution_completed
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		_turn_ms.append(ms)
		if built:
			_build_turns[turn] = ms

	print("[stress] mid-run builds: %d furnaces, road_tiles now=%d, buildings=%d" % [
		build_idx, _road_tiles.size(), MatchState.buildings.size()])
	_report(mine_count)
	print("==== DONE routing-stress ====\n")
	quit(0)


func _report(mine_count: int) -> void:
	var a := _turn_ms.duplicate()
	a.sort()
	var n := a.size()
	if n == 0:
		print("[stress] no turns run")
		return
	var sum := 0.0
	for v in a:
		sum += float(v)
	var mean := sum / float(n)
	var median := float(a[int(n / 2)])
	var p90 := float(a[int(floor(n * 0.9))])
	var p99 := float(a[int(floor(n * 0.99))])
	var mx := float(a[n - 1])
	print("\n==== STRESS REPORT ====")
	print("mines=%d road_tiles=%d mid_run_builds=%d turns=%d" % [mine_count, _road_tiles.size(), _build_turns.size(), n])
	print("ALL turns:    mean=%.1f  median=%.1f  p90=%.1f  p99=%.1f  max=%.1f" % [mean, median, p90, p99, mx])
	# Split build turns (every 5th — road+furnace placed, cache cold) vs the steady turns.
	var build_ms: Array = []
	var steady_ms: Array = []
	for i in range(_turn_ms.size()):
		if _build_turns.has(i + 1):
			build_ms.append(float(_turn_ms[i]))
		else:
			steady_ms.append(float(_turn_ms[i]))
	print("BUILD turns:  %s" % _summ(build_ms))
	print("STEADY turns: %s" % _summ(steady_ms))
	# Slowest 5 turns by wall time.
	var idx: Array = []
	for i in range(_turn_ms.size()):
		idx.append(i)
	idx.sort_custom(func(x, y): return float(_turn_ms[x]) > float(_turn_ms[y]))
	var slow: Array = []
	for i in range(mini(5, idx.size())):
		var tn := int(idx[i]) + 1
		var tag := "*build" if _build_turns.has(tn) else ""
		slow.append("turn%d=%.1fms%s" % [tn, float(_turn_ms[idx[i]]), tag])
	print("slowest: " + ", ".join(slow))


func _summ(arr: Array) -> String:
	if arr.is_empty():
		return "(none)"
	var a := arr.duplicate()
	a.sort()
	var s := 0.0
	for v in a:
		s += float(v)
	return "n=%d mean=%.1f median=%.1f max=%.1f" % [a.size(), s / float(a.size()), float(a[int(a.size() / 2)]), float(a[a.size() - 1])]


class _HexMapStub extends Node:
	var tiles: Dictionary = {}
	func _enter_tree() -> void:
		add_to_group("hex_map")
	func set_cabled_tile(tile_id: String) -> void:
		tiles[id_to_coord(tile_id)] = {"infrastructure_present": ["cables"]}
	func id_to_coord(id: String) -> Vector2i:
		var p := id.split("_")
		if p.size() != 3 or p[0] != "tile" or not p[1].is_valid_int() or not p[2].is_valid_int():
			return Vector2i(-1, -1)
		return Vector2i(int(p[1]) - 1, int(p[2]) - 1)
