extends SceneTree
# Headless integrated-economy sim. Runs ONE supply chain (selected by a cmdline arg)
# under the live rules: per-tile land cap, deposit-gated mines/wells/pumps, road/rail
# build, profit-gated loans, and a marginal-profit stop. Pick the chain with:
#   <godot> --headless --path . --script res://tools/sim_profitable_run.gd -- <chain>
# chain in: motors | concrete | electrical | upvc_windows | aluminium_windows | building_frame
#
# A chain is a list of BRANCHES. Each branch is co-located on one tile and ships its
# single export_good to another branch's tile (or MARKET). A mine-bearing branch
# (deposit != "") may only sit on a tile carrying that deposit. Inputs are produced
# in-chain (tile-only) unless listed in "buy" (bought from market — used where the
# domestic recipe chain is unavailable, e.g. oil-derived plastics/pvc, or aluminium).

const TURNS := 200
const STARTING_CASH := 300.0
const MAX_CHAINS := 12
const PORT := "tile_5_10"
const MAX_TILE_LAND := 200.0
const FREE_LAND := 100.0
const LAND_PATCH := 10.0
const LAND_PATCH_COST := 10.0
const DENSITY_SOFT_CAP := 100.0
const RAMP_TURNS := 10

const CH_MOTORS := [
	{"role": "COPPER", "deposit": "copper_ore", "builds": [["b_001", "r_006", 3], ["b_002", "r_007", 2], ["b_007", "r_008", 2]], "export_good": "g_007", "export_to": "MOTOR"},
	{"role": "IRON", "deposit": "iron_ore", "builds": [["b_001", "r_002", 2], ["b_002", "r_005", 1], ["b_002", "r_003", 1]], "export_good": "g_006", "export_to": "MOTOR"},
	{"role": "COAL", "deposit": "coal", "builds": [["b_001", "r_001", 1]], "export_good": "g_001", "export_to": "IRON"},
	{"role": "MOTOR", "deposit": "", "builds": [["b_007", "r_009", 2]], "export_good": "g_008", "export_to": "MARKET"},
]
const CH_CONCRETE_FURNACE := [
	{"role": "LIMESTONE", "deposit": "limestone", "builds": [["b_001", "r_019", 1]], "export_good": "g_016", "export_to": "CONCRETE"},
	{"role": "SAND", "deposit": "sand", "builds": [["b_001", "r_018", 1]], "export_good": "g_018", "export_to": "CONCRETE"},
	{"role": "WATER", "deposit": "water", "builds": [["b_037", "r_011", 1]], "export_good": "g_009", "export_to": "CONCRETE"},
	{"role": "COAL", "deposit": "coal", "builds": [["b_001", "r_001", 1]], "export_good": "g_001", "export_to": "CONCRETE"},
	{"role": "CONCRETE", "deposit": "", "builds": [["b_011", "r_035", 1], ["b_002", "r_029", 1]], "export_good": "g_017", "export_to": "MARKET"},
]
const CH_CONCRETE_EAF := [
	{"role": "LIMESTONE", "deposit": "limestone", "builds": [["b_001", "r_019", 1]], "export_good": "g_016", "export_to": "CONCRETE"},
	{"role": "SAND", "deposit": "sand", "builds": [["b_001", "r_018", 1]], "export_good": "g_018", "export_to": "CONCRETE"},
	{"role": "WATER", "deposit": "water", "builds": [["b_037", "r_011", 1]], "export_good": "g_009", "export_to": "CONCRETE"},
	{"role": "CONCRETE", "deposit": "", "builds": [["b_011", "r_035", 1], ["b_008", "r_030", 1]], "export_good": "g_017", "export_to": "MARKET"},
]
const CH_ELECTRICAL := [
	{"role": "COPPER", "deposit": "copper_ore", "builds": [["b_001", "r_006", 2], ["b_002", "r_007", 1], ["b_007", "r_008", 1]], "export_good": "g_007", "export_to": "EC"},
	{"role": "SALT", "deposit": "basic_salt", "builds": [["b_001", "r_010", 1]], "export_good": "g_019", "export_to": "EC"},
	{"role": "EC", "deposit": "", "builds": [["b_007", "r_126", 1]], "export_good": "g_036", "export_to": "MARKET", "buy": ["g_027"]},
]
const CH_GLASS_FEEDERS := [
	{"role": "SAND", "deposit": "sand", "builds": [["b_001", "r_018", 1]], "export_good": "g_018", "export_to": "GLASS"},
	{"role": "LIMESTONE", "deposit": "limestone", "builds": [["b_001", "r_019", 1]], "export_good": "g_016", "export_to": "GLASS"},
	{"role": "SALT", "deposit": "basic_salt", "builds": [["b_001", "r_010", 1]], "export_good": "g_015", "export_to": "CHLOR"},
	{"role": "WATER", "deposit": "water", "builds": [["b_037", "r_011", 1]], "export_good": "g_009", "export_to": "CHLOR"},
	{"role": "CHLOR", "deposit": "", "builds": [["b_012", "r_012", 1]], "export_good": "g_013", "export_to": "GLASS"},
	{"role": "GLASS", "deposit": "", "builds": [["b_002", "r_053", 1]], "export_good": "g_038", "export_to": "WINDOW"},
]
const CH_FRAME := [
	{"role": "COAL", "deposit": "coal", "builds": [["b_001", "r_001", 1]], "export_good": "g_001", "export_to": "IRON"},
	{"role": "IRON", "deposit": "iron_ore", "builds": [["b_001", "r_002", 2], ["b_002", "r_005", 1], ["b_002", "r_003", 1]], "export_good": "g_006", "export_to": "FRAME"},
	{"role": "FRAME", "deposit": "", "builds": [["b_009", "r_057", 1]], "export_good": "g_023", "export_to": "MARKET", "buy": ["g_039", "g_036", "g_021"]},
]
const CHAIN_PRODUCT := {"motors": "g_008", "concrete": "g_017", "electrical": "g_036", "upvc_windows": "g_039", "aluminium_windows": "g_039", "building_frame": "g_023"}

var MatchState: Node
var Stockpile: Node
var MarketState: Node
var Catalog: Node
var Production: Node
var TurnManager: Node
var RunMetrics: Node
var LoanState: Node

var _stub
var _chain := "motors"
var _product := "g_008"
var _pool: Array = []
var _deposit_tiles: Dictionary = {}
var _road_cost := 0.0
var _rail_cost := 0.0
var _chains := 0
var _last_chain_cost := 0.0
var _turns_to_second := -1
var _turn_out_of_red := -1
var _total_borrowed := 0.0
var _total_build := 0.0
var _total_land := 0.0
var _total_road := 0.0
var _total_rail := 0.0
var _land_owned: Dictionary = {}
var _land_exhausted := false
var _net_hist: Array = []
var _pre_expand_net := 0.0
var _judge_turn := 0
var _stopped_turn := -1
var _dbg_tile := ""


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


func _branches_for_next() -> Array:
	# The branch list for the NEXT chain. Concrete switches from furnace to EAF after 2.
	match _chain:
		"concrete":
			return CH_CONCRETE_EAF
		"electrical":
			return CH_ELECTRICAL
		"upvc_windows":
			var u := CH_GLASS_FEEDERS.duplicate(true)
			u.append({"role": "WINDOW", "deposit": "", "builds": [["b_007", "r_055", 1]], "export_good": "g_039", "export_to": "MARKET", "buy": ["g_033"]})
			return u
		"aluminium_windows":
			var a := CH_GLASS_FEEDERS.duplicate(true)
			a.append({"role": "WINDOW", "deposit": "", "builds": [["b_007", "r_056", 1]], "export_good": "g_039", "export_to": "MARKET", "buy": ["g_029"]})
			return a
		"building_frame":
			return CH_FRAME
		_:
			return CH_MOTORS


func _build_pool() -> void:
	for col in range(4, 11):
		for row in range(6, 15):
			var t := "tile_%d_%d" % [col, row]
			if t != PORT and Catalog.is_land_tile(t):
				_pool.append(t)
	_pool.sort_custom(func(a, b): return Catalog.tile_hex_distance(a, PORT) < Catalog.tile_hex_distance(b, PORT))


func _load_deposits() -> void:
	var f := FileAccess.open("res://data/tile_properties.csv", FileAccess.READ)
	if f == null:
		return
	f.get_csv_line()
	while not f.eof_reached():
		var line := f.get_csv_line()
		if line.size() < 4 or line[0] == "":
			continue
		var tid: String = line[0]
		if line[3] == "" or not Catalog.is_land_tile(tid):
			continue
		for d in line[3].split("|"):
			var base := d.strip_edges()
			var p := base.find("(")
			if p > 0:
				base = base.substr(0, p)
			if base == "":
				continue
			if not _deposit_tiles.has(base):
				_deposit_tiles[base] = []
			if not _deposit_tiles[base].has(tid):
				_deposit_tiles[base].append(tid)
	f.close()
	for k in _deposit_tiles.keys():
		_deposit_tiles[k].sort_custom(func(a, b): return Catalog.tile_hex_distance(a, PORT) < Catalog.tile_hex_distance(b, PORT))


func _recipe_output_good(recipe_id: String) -> String:
	var r: Dictionary = Catalog.get_recipe(recipe_id)
	var outs: Array = r.get("outputs", [])
	return str(outs[0].get("good_id", "")) if outs.size() > 0 else ""


func _branch_land(branch: Dictionary) -> float:
	var total := 0.0
	for b in branch.builds:
		total += float(Catalog.get_building(str(b[0])).get("tile_size_used", 1.0)) * int(b[2])
	return total


func _alloc_branch(branch: Dictionary, land: float, reserved: Dictionary) -> String:
	var dep := str(branch.get("deposit", ""))
	var cands: Array = []
	if dep != "":
		cands = _deposit_tiles.get(dep, [])
	else:
		for t in _pool:
			cands.append(t)
	for t in cands:
		if t == PORT or not Catalog.is_land_tile(str(t)):
			continue
		var occ: float = MatchState.get_tile_space_used(str(t)) + float(reserved.get(t, 0.0))
		if occ + land <= MAX_TILE_LAND:
			return str(t)
	return ""


func _ensure_roads(tile: String) -> void:
	if not Catalog.tile_has_infrastructure(tile, "roads"):
		MatchState.add_money(-_road_cost)
		_total_road += _road_cost
		Catalog.add_tile_infrastructure(tile, "roads")


func _ensure_rail_corridor(src: String, dst: String) -> void:
	if src == "" or dst == "" or src == dst:
		return
	var r: Dictionary = Catalog.route(src, dst, "")
	var tiles: Array = r.get("tiles", [])
	if tiles.is_empty():
		tiles = [src, dst]
	for t in tiles:
		if not Catalog.tile_has_infrastructure(str(t), "rail"):
			MatchState.add_money(-_rail_cost)
			_total_rail += _rail_cost
			Catalog.add_tile_infrastructure(str(t), "rail")


func _place_on(building_id: String, recipe_id: String, tile: String) -> String:
	var size: float = float(Catalog.get_building(building_id).get("tile_size_used", 1.0))
	var projected: float = MatchState.get_tile_space_used(tile) + size
	var owned: float = float(_land_owned.get(tile, FREE_LAND))
	if projected > owned:
		var patches: int = int(ceil((projected - owned) / LAND_PATCH))
		MatchState.add_money(-float(patches) * LAND_PATCH_COST)
		_land_owned[tile] = owned + float(patches) * LAND_PATCH
		_total_land += float(patches) * LAND_PATCH_COST
	var mult: float = 1.5 if projected > DENSITY_SOFT_CAP else 1.0
	var cost: float = float(Catalog.get_building(building_id).get("base_price", 0.0)) * mult
	MatchState.add_money(-cost)
	_total_build += cost
	return MatchState.add_building(building_id, recipe_id, tile)


func _build_chain() -> bool:
	var branches: Array = _branches_for_next()
	var chain_tiles: Dictionary = {}
	var reserved: Dictionary = {}
	for b in branches:
		var land: float = _branch_land(b)
		var t: String = _alloc_branch(b, land, reserved)
		if t == "":
			return false
		reserved[t] = float(reserved.get(t, 0.0)) + land
		chain_tiles[b.role] = t
	var spent_before: float = _total_build + _total_land + _total_road + _total_rail
	for b in branches:
		var tile: String = chain_tiles[b.role]
		_ensure_roads(tile)
		_stub.set_cabled_tile(tile)
		var buy: Array = b.get("buy", [])
		for build in b.builds:
			var recipe: Dictionary = Catalog.get_recipe(str(build[1]))
			# Route the export good to its destination if THIS recipe produces it as
			# ANY output (salt mine, chlor-alkali etc. have the wanted good as output 2+).
			var makes_export := false
			for o in recipe.get("outputs", []):
				if str(o.get("good_id", "")) == str(b.export_good):
					makes_export = true
			for i in int(build[2]):
				var inst: String = _place_on(str(build[0]), str(build[1]), tile)
				if makes_export:
					if str(b.export_to) == "MARKET":
						MatchState.route_output_to_market(inst, str(b.export_good))
					else:
						var dest: String = chain_tiles[str(b.export_to)]
						if dest != tile:
							MatchState.set_output_stockpile_destination(inst, dest, str(b.export_good))
				for input in recipe.get("inputs", []):
					var gid: String = str(input.get("good_id", ""))
					if not buy.has(gid):
						MatchState.set_input_tile_only(inst, gid, true)
		MatchState.enable_sell_surplus(tile)
	# Rail each export corridor (branch tile -> its destination / port).
	for b in branches:
		var src: String = chain_tiles[b.role]
		var dst: String = Catalog.nearest_port_tile(src) if str(b.export_to) == "MARKET" else chain_tiles[str(b.export_to)]
		_ensure_rail_corridor(src, dst)
	if _chains == 0:
		for b in branches:
			if str(b.export_to) == "MARKET":
				_dbg_tile = chain_tiles[b.role]
	if MatchState.has_signal("money_changed"):
		MatchState.money_changed.emit(MatchState.money)
	_chains += 1
	_last_chain_cost = (_total_build + _total_land + _total_road + _total_rail) - spent_before
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


func _lifetime(good_id: String) -> int:
	var total := 0
	for d in Production.produced_by_building.values():
		total += int(d.get(good_id, 0))
	return total


func _equity() -> float:
	var cash: float = float(MatchState.money)
	var stock := 0.0
	for gid in Stockpile.get_all_totals().keys():
		var qty := int(Stockpile.get_all_totals()[gid])
		if qty > 0:
			stock += float(qty) * MarketState.get_price(str(gid))
	var bval := 0.0
	for inst in MatchState.buildings.values():
		bval += float(Catalog.get_building(str(inst.get("building_id", ""))).get("base_price", 0.0))
	var debt := float(LoanState.total_outstanding()) if LoanState.has_method("total_outstanding") else 0.0
	return cash + stock + bval - debt


func _initialize() -> void:
	_resolve()
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_chain = str(args[0])
	_product = str(CHAIN_PRODUCT.get(_chain, "g_008"))
	print("\n==== sim: chain=%s product=%s ====" % [_chain, _product])
	_stub = _HexMapStub.new()
	get_root().add_child(_stub)
	TurnManager.fast_mode = true
	await process_frame
	await process_frame
	await process_frame
	if RunMetrics and RunMetrics.has_method("reset"):
		RunMetrics.reset()
	_build_pool()
	_load_deposits()
	_road_cost = float(Catalog.get_building("b_005").get("base_price", 25.0))
	_rail_cost = float(Catalog.get_building("b_019").get("base_price", 70.0))

	MatchState.money = STARTING_CASH
	if MatchState.has_signal("money_changed"):
		MatchState.money_changed.emit(MatchState.money)
	if not _build_chain():
		print("[sim] could not place seed chain (no deposit/land) — aborting")
		quit(1)
		return
	_finance()
	await process_frame
	await process_frame
	print("[sim] seed: cash=%.0f buildings=%d cost=%.0f" % [MatchState.money, MatchState.buildings.size(), _last_chain_cost])

	for t in range(TURNS):
		TurnManager.commit_turn()
		await TurnManager.turn_resolution_completed
		var turn := t + 1
		_finance()
		if _turn_out_of_red < 0 and MatchState.money >= 0.0:
			_turn_out_of_red = turn
		var s: Dictionary = Production.last_turn_summary
		_net_hist.append(float(s.get("money_in", 0.0)) - float(s.get("money_out", 0.0)))
		if _judge_turn > 0 and turn >= _judge_turn:
			var marginal: float = _rolling_net() - _pre_expand_net
			if marginal < 0.0:
				_stopped_turn = turn
				print("[sim] marginal profit negative (%+.1f) — stop at turn %d" % [marginal, turn])
				break
			_judge_turn = 0
		if not _land_exhausted and MatchState.money > _last_chain_cost and _chains < MAX_CHAINS:
			var pre: float = _rolling_net()
			if _build_chain():
				_pre_expand_net = pre
				_judge_turn = turn + RAMP_TURNS
				if _chains == 2 and _turns_to_second < 0:
					_turns_to_second = turn
			else:
				_land_exhausted = true

	if RunMetrics and RunMetrics.has_method("finish_run"):
		RunMetrics.finish_run()
	_report()
	quit(0)


func _report() -> void:
	var rows: Array = RunMetrics.read_rows() if RunMetrics.has_method("read_rows") else []
	var ramped := 0.0
	var slope := 0.0
	var transport := 0.0
	if rows.size() >= 2:
		var w: int = mini(20, rows.size() - 1)
		var sp := 0.0
		for i in range(rows.size() - w, rows.size()):
			sp += float(rows[i].get("profit_post_tax", "0"))
		ramped = sp / float(w)
		slope = (float(rows[rows.size() - 1].get("equity", "0")) - float(rows[rows.size() - 1 - w].get("equity", "0"))) / float(w)
		transport = float(rows[rows.size() - 1].get("cost_transport", "0"))
	print("\n==== REPORT: %s ====" % _chain)
	print("chains=%d tiles=%d  seed/last_cost=%.0f  stopped=%s" % [
		_chains, _land_owned.size(), _last_chain_cost, (str(_stopped_turn) if _stopped_turn > 0 else "no")])
	print("build=%.0f land=%.0f road=%.0f rail=%.0f borrowed=%.0f debt_end=%.0f" % [
		_total_build, _total_land, _total_road, _total_rail, _total_borrowed, LoanState.total_outstanding()])
	print("out_of_red=%s  2nd_chain=%s  transport/turn=%.1f  product_lifetime=%d" % [
		str(_turn_out_of_red), str(_turns_to_second), transport, _lifetime(_product)])
	print("steady net/turn=%+.1f  equity_slope=%+.1f  final_equity=%.0f  profitable=%s" % [
		ramped, slope, _equity(), ("YES" if (ramped > 0 and slope > 0 and _equity() > 0) else "NO")])
	print("==== DONE %s ====\n" % _chain)


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
