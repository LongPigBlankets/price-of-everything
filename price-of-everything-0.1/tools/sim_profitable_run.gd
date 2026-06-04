extends SceneTree
# Headless MOTOR supply-chain run to turn 200 on the REAL tiles around Stoneshore,
# now respecting the per-tile land HARD CAP, spilling to nearby tiles when a tile is
# full, and buying roads on any roadless tile it builds on. Loans (profit-gated),
# land purchase and density costs are unchanged from the earlier runs.
#
#   <godot> --headless --path . --script res://tools/sim_profitable_run.gd
#
# Each chain is four co-located branches; each branch sits on ONE tile (it fits under
# the 200 land cap) and ships only its finished product onward:
#   COPPER  3 mine + 2 furnace + 2 wire  (150 land)  -> copper_wiring -> MOTOR tile
#   IRON    2 mine + pig-iron + steel    (100 land)  -> steel        -> MOTOR tile
#   COAL    1 mine                        (30 land)  -> coal         -> IRON tile
#   MOTOR   2 motor factory               (20 land)  -> motor        -> MARKET (port)
# Branch tiles are allocated each chain, preferring the real deposit/port anchors; once
# an anchor is full (200 land) the branch SPILLS to the nearest free land tile. Building
# on a roadless tile (e.g. the copper deposit tile_8_12) triggers a road purchase so the
# router can reach it. When no nearby land tile can fit the next branch, expansion stops.

const TURNS := 200
const STARTING_CASH := 300.0
const MAX_CHAINS := 10

const PORT := "tile_5_10"           # Stoneshore Docks
const COPPER_ANCHOR := "tile_8_12"  # copper deposit (no roads -> must buy roads)
const IRON_ANCHOR := "tile_7_10"    # iron deposit
const COAL_ANCHOR := "tile_6_8"     # coal deposit
const MOTOR_ANCHOR := "tile_5_8"    # assembly, 1 hex from port

const MAX_TILE_LAND := 200.0        # MatchState.MAX_TILE_LAND — now a HARD cap
const FREE_LAND := 100.0
const LAND_PATCH := 10.0
const LAND_PATCH_COST := 10.0
const DENSITY_SOFT_CAP := 100.0

# Each chain's branches. builds = [[building_id, recipe_id, count], ...]; the building
# whose recipe output == export_good ships to the export_to branch's tile (or MARKET).
const BRANCHES := [
	{"role": "COPPER", "anchor": "tile_8_12", "builds": [["b_001", "r_006", 3], ["b_002", "r_007", 2], ["b_007", "r_008", 2]], "export_good": "g_007", "export_to": "MOTOR"},
	{"role": "IRON", "anchor": "tile_7_10", "builds": [["b_001", "r_002", 2], ["b_002", "r_005", 1], ["b_002", "r_003", 1]], "export_good": "g_006", "export_to": "MOTOR"},
	{"role": "COAL", "anchor": "tile_6_8", "builds": [["b_001", "r_001", 1]], "export_good": "g_001", "export_to": "IRON"},
	{"role": "MOTOR", "anchor": "tile_5_8", "builds": [["b_007", "r_009", 2]], "export_good": "g_008", "export_to": "MARKET"},
]

var MatchState: Node
var Stockpile: Node
var MarketState: Node
var Catalog: Node
var Production: Node
var TurnManager: Node
var RunMetrics: Node
var LoanState: Node

var _stub
var _pool: Array = []               # nearby land tiles (spill targets), nearest port first
var _road_cost := 0.0
var _rail_cost := 0.0
var _total_rail_spent := 0.0
var _chains := 0
var _last_chain_cost := 0.0
var _turns_to_second_chain := -1
var _turn_out_of_red := -1
var _total_borrowed := 0.0
var _total_build_spent := 0.0
var _total_land_spent := 0.0
var _total_road_spent := 0.0
var _land_owned: Dictionary = {}    # tile -> land units owned
var _land_exhausted := false
var _net_hist: Array = []           # per-turn operating net (money_in - money_out)
var _pre_expand_net := 0.0          # rolling net just before the most recent expansion
var _judge_turn := 0                # turn at which to judge that expansion's marginal effect
var _stopped_turn := -1

const RAMP_TURNS := 10              # let a new chain ramp before judging its marginal profit


func _rolling_net() -> float:
	if _net_hist.is_empty():
		return 0.0
	var n: int = mini(5, _net_hist.size())
	var s := 0.0
	for i in range(_net_hist.size() - n, _net_hist.size()):
		s += float(_net_hist[i])
	return s / float(n)


func _resolve() -> void:
	var r := get_root()
	MatchState = r.get_node("MatchState")
	Stockpile = r.get_node("Stockpile")
	MarketState = r.get_node("MarketState")
	Catalog = r.get_node("Catalog")
	Production = r.get_node("Production")
	TurnManager = r.get_node("TurnManager")
	RunMetrics = r.get_node("RunMetrics")
	LoanState = r.get_node("LoanState")


func _build_pool() -> void:
	# Land tiles in a band around the port (excluding the port itself), nearest first,
	# as spill targets when a branch can't fit on its preferred anchor.
	for col in range(4, 11):
		for row in range(6, 15):
			var t := "tile_%d_%d" % [col, row]
			if t == PORT:
				continue
			if Catalog.is_land_tile(t):
				_pool.append(t)
	_pool.sort_custom(func(a, b): return Catalog.tile_hex_distance(a, PORT) < Catalog.tile_hex_distance(b, PORT))


func _recipe_output_good(recipe_id: String) -> String:
	var r: Dictionary = Catalog.get_recipe(recipe_id)
	var outs: Array = r.get("outputs", [])
	return str(outs[0].get("good_id", "")) if outs.size() > 0 else ""


func _branch_land(branch: Dictionary) -> float:
	var total := 0.0
	for b in branch.builds:
		total += float(Catalog.get_building(str(b[0])).get("tile_size_used", 1.0)) * int(b[2])
	return total


func _alloc_branch(anchor: String, land: float, reserved: Dictionary) -> String:
	# First land tile (anchor, then nearest pool tiles) that can fit `land` under the cap,
	# accounting for what other branches of THIS chain have already reserved this turn.
	var cands: Array = [anchor]
	for t in _pool:
		if not cands.has(t):
			cands.append(t)
	for t in cands:
		if t == PORT or not Catalog.is_land_tile(t):
			continue
		var occ: float = MatchState.get_tile_space_used(t) + float(reserved.get(t, 0.0))
		if occ + land <= MAX_TILE_LAND:
			return t
	return ""


func _ensure_roads(tile: String) -> void:
	# Build on a roadless tile -> buy roads so the router can reach it. Idempotent: once
	# the tile has roads (native or bought) this is a no-op.
	if not Catalog.tile_has_infrastructure(tile, "roads"):
		MatchState.add_money(-_road_cost)
		_total_road_spent += _road_cost
		Catalog.add_tile_infrastructure(tile, "roads")


func _ensure_rail_corridor(src: String, dst: String, good: String) -> void:
	# Lay rail along the whole route between src and dst so the haul runs at rail range
	# (4 tiles/turn, infrastructure.csv) instead of the road/overland fallback (2),
	# roughly halving transport turns -> cost. Rail is added to every tile on the path;
	# idempotent per tile.
	if src == "" or dst == "" or src == dst:
		return
	var r: Dictionary = Catalog.route(src, dst, good)
	var tiles: Array = r.get("tiles", [])
	if tiles.is_empty():
		tiles = [src, dst]
	for t in tiles:
		if not Catalog.tile_has_infrastructure(str(t), "rail"):
			MatchState.add_money(-_rail_cost)
			_total_rail_spent += _rail_cost
			Catalog.add_tile_infrastructure(str(t), "rail")


func _place_on(building_id: String, recipe_id: String, tile: String) -> String:
	var size: float = float(Catalog.get_building(building_id).get("tile_size_used", 1.0))
	var used: float = MatchState.get_tile_space_used(tile)
	var projected: float = used + size
	# Buy land to cover the footprint (capped at MAX_TILE_LAND — the allocator guarantees
	# projected <= cap, so this never overshoots).
	var owned: float = float(_land_owned.get(tile, FREE_LAND))
	if projected > owned:
		var patches: int = int(ceil((projected - owned) / LAND_PATCH))
		var land_cost: float = float(patches) * LAND_PATCH_COST
		MatchState.add_money(-land_cost)
		_land_owned[tile] = owned + float(patches) * LAND_PATCH
		_total_land_spent += land_cost
	# Density build-cost multiplier above the soft cap.
	var mult: float = 1.5 if projected > DENSITY_SOFT_CAP else 1.0
	var cost: float = float(Catalog.get_building(building_id).get("base_price", 0.0)) * mult
	MatchState.add_money(-cost)
	_total_build_spent += cost
	return MatchState.add_building(building_id, recipe_id, tile)


func _build_chain() -> bool:
	# Allocate a tile for every branch first (so export targets exist), respecting the
	# cap + this chain's own reservations. Abort if any branch can't find nearby room.
	var chain_tiles: Dictionary = {}
	var reserved: Dictionary = {}
	for b in BRANCHES:
		var land: float = _branch_land(b)
		var t: String = _alloc_branch(str(b.anchor), land, reserved)
		if t == "":
			return false   # no nearby land left
		reserved[t] = float(reserved.get(t, 0.0)) + land
		chain_tiles[b.role] = t

	var spent_before: float = _total_build_spent + _total_land_spent + _total_road_spent + _total_rail_spent
	for b in BRANCHES:
		var tile: String = chain_tiles[b.role]
		_ensure_roads(tile)
		_stub.set_cabled_tile(tile)
		for build in b.builds:
			for i in int(build[2]):
				var inst: String = _place_on(str(build[0]), str(build[1]), tile)
				var out: String = _recipe_output_good(str(build[1]))
				if out == str(b.export_good):
					if str(b.export_to) == "MARKET":
						MatchState.route_output_to_market(inst, out)
					else:
						var dest: String = chain_tiles[str(b.export_to)]
						if dest != tile:
							MatchState.set_output_stockpile_destination(inst, dest, out)
				var recipe: Dictionary = Catalog.get_recipe(str(build[1]))
				for input in recipe.get("inputs", []):
					MatchState.set_input_tile_only(inst, str(input.get("good_id", "")), true)
		MatchState.enable_sell_surplus(tile)
	# Lay rail along this chain's shipment corridors (inter-tile hauls + each tile to
	# its nearest port), so transport runs at rail range instead of the fallback.
	var motor_tile: String = chain_tiles["MOTOR"]
	_ensure_rail_corridor(chain_tiles["COAL"], chain_tiles["IRON"], "g_001")
	_ensure_rail_corridor(chain_tiles["COPPER"], motor_tile, "g_007")
	_ensure_rail_corridor(chain_tiles["IRON"], motor_tile, "g_006")
	_ensure_rail_corridor(motor_tile, Catalog.nearest_port_tile(motor_tile), "g_008")
	for role in ["COPPER", "IRON", "COAL"]:
		var rt: String = chain_tiles[role]
		_ensure_rail_corridor(rt, Catalog.nearest_port_tile(rt), "")
	if MatchState.has_signal("money_changed"):
		MatchState.money_changed.emit(MatchState.money)
	_chains += 1
	_last_chain_cost = (_total_build_spent + _total_land_spent + _total_road_spent + _total_rail_spent) - spent_before
	return true


func _finance() -> void:
	if MatchState.money >= 0.0:
		return
	var cap: float = LoanState.available_capacity()
	if cap < 1.0:
		return
	var amt: float = minf(-MatchState.money, cap)
	if amt >= 1.0 and LoanState.take_loan(amt):
		_total_borrowed += amt


func _initialize() -> void:
	print("\n==== sim_profitable_run (Stoneshore, hard land cap + road buys, 200 turns) ====")
	_resolve()
	_stub = _HexMapStub.new()
	get_root().add_child(_stub)
	TurnManager.fast_mode = true
	await process_frame
	await process_frame
	await process_frame
	if RunMetrics and RunMetrics.has_method("reset"):
		RunMetrics.reset()

	_build_pool()
	_road_cost = float(Catalog.get_building("b_005").get("base_price", 25.0))
	_rail_cost = float(Catalog.get_building("b_019").get("base_price", 1.0))
	print("[sim] %d nearby land tiles in pool; road=%.0f rail=%.0f /tile; tile cap = %.0f" % [
		_pool.size(), _road_cost, _rail_cost, MAX_TILE_LAND])

	MatchState.money = STARTING_CASH
	if MatchState.has_signal("money_changed"):
		MatchState.money_changed.emit(MatchState.money)
	if not _build_chain():
		print("[sim] could not place the seed chain — aborting")
		quit(1)
		return
	_finance()
	await process_frame
	await process_frame
	print("[sim] start: cash=%.2f debt=%.2f buildings=%d | seed cost=%.2f" % [
		MatchState.money, LoanState.total_outstanding(), MatchState.buildings.size(), _last_chain_cost])

	for t in range(TURNS):
		TurnManager.commit_turn()
		await TurnManager.turn_resolution_completed
		var turn := t + 1

		_finance()
		if _turn_out_of_red < 0 and MatchState.money >= 0.0:
			_turn_out_of_red = turn

		var s: Dictionary = Production.last_turn_summary
		_net_hist.append(float(s.get("money_in", 0.0)) - float(s.get("money_out", 0.0)))

		# STOP the run the moment a ramped expansion has driven marginal profit < 0
		# (the rolling net is now lower than it was just before that expansion).
		if _judge_turn > 0 and turn >= _judge_turn:
			var marginal: float = _rolling_net() - _pre_expand_net
			if marginal < 0.0:
				_stopped_turn = turn
				print("[sim] >>> marginal profit negative (%+.1f/turn) after the last expansion — stopping at turn %d" % [marginal, turn])
				break
			_judge_turn = 0   # that expansion paid off; clear the pending judgment

		# Expand from CASH when affordable, until nearby land runs out.
		if not _land_exhausted and MatchState.money > _last_chain_cost and _chains < MAX_CHAINS:
			var pre: float = _rolling_net()
			if _build_chain():
				_pre_expand_net = pre
				_judge_turn = turn + RAMP_TURNS
				if _chains == 2 and _turns_to_second_chain < 0:
					_turns_to_second_chain = turn
					print("[sim] >>> 2nd chain built at turn %d" % turn)
			else:
				_land_exhausted = true
				print("[sim] >>> nearby land exhausted at turn %d after %d chains" % [turn, _chains])

		if turn % 20 == 0 or turn == 1:
			print("[sim] turn %3d | chains=%2d buildings=%3d tiles=%2d | cash=%9.1f debt=%8.1f equity=%9.1f | motor(life)=%5d" % [
				turn, _chains, MatchState.buildings.size(), _land_owned.size(), MatchState.money,
				LoanState.total_outstanding(), _equity(), _lifetime("g_008")])

	if RunMetrics and RunMetrics.has_method("finish_run"):
		RunMetrics.finish_run()
	_print_report()
	quit(0)


func _lifetime(good_id: String) -> int:
	var total := 0
	for d in Production.produced_by_building.values():
		total += int(d.get(good_id, 0))
	return total


func _equity() -> float:
	var cash: float = float(MatchState.money)
	var stock := 0.0
	var totals: Dictionary = Stockpile.get_all_totals()
	for gid in totals.keys():
		var qty := int(totals[gid])
		if qty > 0:
			stock += float(qty) * MarketState.get_price(str(gid))
	var bval := 0.0
	for inst in MatchState.buildings.values():
		bval += float(Catalog.get_building(str(inst.get("building_id", ""))).get("base_price", 0.0))
	var debt := 0.0
	if LoanState and LoanState.has_method("total_outstanding"):
		debt = float(LoanState.total_outstanding())
	return cash + stock + bval - debt


func _print_report() -> void:
	var final_cash := float(MatchState.money)
	var final_equity := _equity()
	var rows: Array = RunMetrics.read_rows() if RunMetrics.has_method("read_rows") else []
	var ramped_net := 0.0
	var equity_slope := 0.0
	var transport_last := 0.0
	if rows.size() >= 2:
		var window: int = mini(20, rows.size() - 1)
		var first: Dictionary = rows[rows.size() - 1 - window]
		var last: Dictionary = rows[rows.size() - 1]
		var sum_profit := 0.0
		for i in range(rows.size() - window, rows.size()):
			sum_profit += float(rows[i].get("profit_post_tax", "0"))
		ramped_net = sum_profit / float(window)
		equity_slope = (float(last.get("equity", "0")) - float(first.get("equity", "0"))) / float(window)
		transport_last = float(last.get("cost_transport", "0"))
	var profitable := ramped_net > 0.0 and equity_slope > 0.0 and final_equity > 0.0

	print("\n========= MOTOR-CHAIN (HARD CAP + ROADS) REPORT =========")
	if _stopped_turn > 0:
		print("STOPPED early at turn %d (marginal profit went negative)" % _stopped_turn)
	print("Chains built                         : %d%s" % [_chains,
		"  (land-limited)" if _land_exhausted else ""])
	print("Distinct tiles built on              : %d" % _land_owned.size())
	print("Last chain actual cost               : %.2f (build+density+land+roads)" % _last_chain_cost)
	print("Total construction (incl. density)   : %.2f" % _total_build_spent)
	print("Total land purchased                 : %.2f" % _total_land_spent)
	print("Total roads purchased                : %.2f" % _total_road_spent)
	print("Total rail purchased                 : %.2f" % _total_rail_spent)
	print("Total borrowed over run              : %.2f" % _total_borrowed)
	print("Outstanding debt at end              : %.2f" % LoanState.total_outstanding())
	print("Turn cash first climbed out of red   : %s" % (str(_turn_out_of_red) if _turn_out_of_red > 0 else "STILL IN RED"))
	print("turns_to_second_chain                : %s" % (str(_turns_to_second_chain) if _turns_to_second_chain > 0 else "NOT REACHED"))
	print("Transport cost (last logged turn)    : %.2f / turn" % transport_last)
	print("Total motors produced (lifetime)     : %d" % _lifetime("g_008"))
	print("Per-turn net (avg post-tax, last 20) : %+.2f" % ramped_net)
	print("Equity slope (last 20 turns)         : %+.2f / turn" % equity_slope)
	print("Final cash                           : %.2f" % final_cash)
	print("Final equity                         : %.2f" % final_equity)
	print("Profitable (net>0 & equity growing>0): %s" % ("YES" if profitable else "NO"))
	print("=========================================================")
	print("==== sim_profitable_run: DONE ====\n")


# Minimal hex_map stub so Power.is_supplied() sees cables on each production tile.
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
