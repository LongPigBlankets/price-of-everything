extends SceneTree
# Headless integrated-economy sim. Runs ONE supply chain (selected by a cmdline arg)
# under the live rules: per-tile land cap, deposit-gated mines/wells/pumps, road/rail
# build, profit-gated loans, and a marginal-profit stop. Pick the chain with:
#   <godot> --headless --path . --script res://tools/sim_profitable_run.gd -- <chain>
# chain in: motors | concrete | electrical | upvc_windows | aluminium_windows | building_frame | plastics
# Once a chain turns profitable it builds ONE self-supply power station (coal-fired,
# or processed_oil-fired for the plastics chain) whose power flows into the shared grid.
#
# A chain is a list of BRANCHES. Each branch is co-located on one tile and ships its
# single export_good to another branch's tile (or MARKET). A mine-bearing branch
# (deposit != "") may only sit on a tile carrying that deposit. Inputs are produced
# in-chain (tile-only) unless listed in "buy" (bought from market — used where the
# domestic recipe chain is unavailable, e.g. oil-derived plastics/pvc, or aluminium).

const TURNS := 300
const STARTING_CASH := 300.0
const MAX_CHAINS := 12
const PROFIT_MILESTONES := [100, 500, 1000]
const EQUITY_MILESTONES := [500, 1000, 2500, 5000, 10000]
const PORT := "tile_5_10"
const MAX_TILE_LAND := 200.0
const FREE_LAND := 100.0
const LAND_PATCH := 10.0
const LAND_PATCH_COST := 10.0
const DENSITY_SOFT_CAP := 100.0
const RAMP_TURNS := 10
const WC_FLOOR := 400.0   # per-turn working-capital floor (tracked as construction debt; equity-neutral)

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
# Electrical components make their OWN plastics in-chain. The whole oil train (shale
# fracking -> refining -> ethylene -> plastics) is CO-LOCATED on a shale_oil tile so
# crude/processed/ethylene never leave the tile (no fragile liquid pipes); only solid
# plastics ships (by rail) to the EC factory. copper_wiring + chem_salts self too.
const CH_ELECTRICAL := [
	{"role": "COPPER", "deposit": "copper_ore", "builds": [["b_001", "r_006", 2], ["b_002", "r_007", 1], ["b_007", "r_008", 1]], "export_good": "g_007", "export_to": "EC"},
	{"role": "SALT", "deposit": "basic_salt", "builds": [["b_001", "r_010", 1]], "export_good": "g_019", "export_to": "EC"},
	{"role": "PLASTICS", "deposit": "shale_oil", "builds": [["b_034", "r_177", 2], ["b_011", "r_180", 1], ["b_011", "r_023", 1], ["b_013", "r_024", 1]], "export_good": "g_027", "export_to": "EC"},
	{"role": "EC", "deposit": "", "builds": [["b_007", "r_126", 1]], "export_good": "g_036", "export_to": "MARKET"},
]
# uPVC glass feeders: full chlor-alkali chain. CHLOR sits on a river tile with its
# OWN water pump (r_011) so chlor-alkali's water is produced & consumed on-tile (no
# piped-water latency); it ships only NaOH (reinforced pipe) to the glass furnaces.
const CH_GLASS_FEEDERS := [
	{"role": "SAND", "deposit": "sand", "builds": [["b_001", "r_018", 1]], "export_good": "g_018", "export_to": "GLASS"},
	{"role": "LIMESTONE", "deposit": "limestone", "builds": [["b_001", "r_019", 1]], "export_good": "g_016", "export_to": "GLASS"},
	{"role": "SALT", "deposit": "basic_salt", "builds": [["b_001", "r_010", 1]], "export_good": "g_015", "export_to": "CHLOR"},
	{"role": "CHLOR", "deposit": "water", "builds": [["b_037", "r_011", 1], ["b_012", "r_012", 1]], "export_good": "g_013", "export_to": "GLASS"},
	{"role": "GLASS", "deposit": "", "builds": [["b_002", "r_053", 1]], "export_good": "g_038", "export_to": "WINDOW"},
]
# Aluminium glass feeders: NO chlor-alkali chain — the glass furnaces import NaOH
# from the market (cheap at £0.8) instead of building salt + water + electrochemistry.
const CH_GLASS_FEEDERS_IMPORT := [
	{"role": "SAND", "deposit": "sand", "builds": [["b_001", "r_018", 1]], "export_good": "g_018", "export_to": "GLASS"},
	{"role": "LIMESTONE", "deposit": "limestone", "builds": [["b_001", "r_019", 1]], "export_good": "g_016", "export_to": "GLASS"},
	{"role": "GLASS", "deposit": "", "builds": [["b_002", "r_053", 1]], "export_good": "g_038", "export_to": "WINDOW", "buy": ["g_013"]},
]
# Building frame: makes its OWN windows in-chain by importing glass + pvc to a window
# factory, then assembles (steel self; copper_pipe + electrical_components imported).
const CH_FRAME := [
	{"role": "COAL", "deposit": "coal", "builds": [["b_001", "r_001", 1]], "export_good": "g_001", "export_to": "IRON"},
	{"role": "IRON", "deposit": "iron_ore", "builds": [["b_001", "r_002", 2], ["b_002", "r_005", 1], ["b_002", "r_003", 1]], "export_good": "g_006", "export_to": "FRAME"},
	{"role": "WINDOW", "deposit": "", "builds": [["b_007", "r_055", 1]], "export_good": "g_039", "export_to": "FRAME", "buy": ["g_038", "g_033"]},
	{"role": "FRAME", "deposit": "", "builds": [["b_009", "r_057", 1]], "export_good": "g_023", "export_to": "MARKET", "buy": ["g_036", "g_021"]},
]
# Plastics-only chain: the entire train (shale fracking -> refining -> ethylene ->
# plastics) is co-located on one shale_oil tile; only solid plastics ships to market.
# Its self-supply power plant burns processed_oil (r_181), not coal (CH_POWER_STATION_OIL).
const CH_PLASTICS := [
	{"role": "PLASTICS", "deposit": "shale_oil", "builds": [["b_034", "r_177", 2], ["b_011", "r_180", 1], ["b_011", "r_023", 1], ["b_013", "r_024", 1]], "export_good": "g_027", "export_to": "MARKET"},
]
# Self-supply power station, built ONCE per run after the chain turns profitable. The
# PLANT branch exports to itself (export_to == role) so the power good is NOT routed
# off-tile — it flows into the shared grid and offsets the chain's own consumption.
const CH_POWER_STATION := [
	{"role": "COAL", "deposit": "coal", "builds": [["b_001", "r_001", 1]], "export_good": "g_001", "export_to": "PLANT"},
	{"role": "PLANT", "deposit": "water", "builds": [["b_037", "r_011", 1], ["b_003", "r_004", 1]], "export_good": "g_010", "export_to": "PLANT"},
]
const CH_POWER_STATION_OIL := [
	{"role": "PLANT", "deposit": "shale_oil", "builds": [["b_034", "r_177", 2], ["b_011", "r_180", 1], ["b_003", "r_181", 1]], "export_good": "g_010", "export_to": "PLANT"},
]
const CHAIN_PRODUCT := {"motors": "g_008", "concrete": "g_017", "electrical": "g_036", "upvc_windows": "g_039", "aluminium_windows": "g_039", "building_frame": "g_023", "plastics": "g_027"}

var MatchState: Node
var Stockpile: Node
var MarketState: Node
var Catalog: Node
var Production: Node
var TurnManager: Node
var RunMetrics: Node
var LoanState: Node
var TransportService: Node

var _stub
var _chain := "motors"
var _product := "g_008"
var _pool: Array = []
var _deposit_tiles: Dictionary = {}
var _road_cost := 0.0
var _rail_cost := 0.0
var _pipe_cost := 0.0
var _reinf_pipe_cost := 0.0
var _chains := 0
var _last_chain_cost := 0.0
var _turns_to_second := -1
var _turn_out_of_red := -1
var _total_borrowed := 0.0
var _total_build := 0.0
var _total_land := 0.0
var _total_road := 0.0
var _total_rail := 0.0
var _total_pipe := 0.0
var _land_owned: Dictionary = {}
var _land_exhausted := false
var _construction_debt := 0.0
var _net_hist: Array = []
var _pre_expand_net := 0.0
var _judge_turn := 0
var _stopped_turn := -1
var _profit_at: Dictionary = {}     # profit/turn threshold -> first turn reached
var _equity_at: Dictionary = {}     # equity threshold -> first turn reached
var _power_built := false            # self-supply power station built once profitable
var _power_turn := -1


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
	TransportService = r.get_node("TransportService")


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
			var a := CH_GLASS_FEEDERS_IMPORT.duplicate(true)
			a.append({"role": "WINDOW", "deposit": "", "builds": [["b_007", "r_056", 1]], "export_good": "g_039", "export_to": "MARKET", "buy": ["g_029"]})
			return a
		"building_frame":
			return CH_FRAME
		"plastics":
			return CH_PLASTICS
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


func _corridor_mode(good_id: String) -> String:
	# Liquids/gases move by pipe (hazard liquids need reinforced pipe); solids by rail.
	match Catalog.get_transport_class(good_id):
		"hazard_liquid":
			return "reinf_pipes"
		"safe_liquid", "liquid", "gas":
			return "pipes"
		_:
			return "rail"


func _infra_cost(infra: String) -> float:
	match infra:
		"pipes":
			return _pipe_cost
		"reinf_pipes":
			return _reinf_pipe_cost
		_:
			return _rail_cost


func _tile_path(src: String, dst: String) -> Array:
	# Shortest chain of ADJACENT LAND tiles src->dst (dst itself may be a coastal port
	# tile). All infrastructure — rail and pipes alike — is land-only. Laying infra on
	# every tile of this path yields a connected corridor.
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


func _ensure_corridor(src: String, dst: String, infra: String) -> void:
	if src == "" or dst == "" or src == dst:
		return
	var cost: float = _infra_cost(infra)
	for t in _tile_path(src, dst):
		if not Catalog.tile_has_infrastructure(str(t), infra):
			MatchState.add_money(-cost)
			if infra == "rail":
				_total_rail += cost
			else:
				_total_pipe += cost
			Catalog.add_tile_infrastructure(str(t), infra)


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
	return _build_branches(_branches_for_next(), true)


func _build_power_station() -> bool:
	var branches: Array = CH_POWER_STATION_OIL if _chain == "plastics" else CH_POWER_STATION
	if _build_branches(branches, false):
		_power_built = true
		return true
	return false


func _build_branches(branches: Array, count_as_chain: bool) -> bool:
	var chain_tiles: Dictionary = {}
	var reserved: Dictionary = {}
	for b in branches:
		var land: float = _branch_land(b)
		var t: String = _alloc_branch(b, land, reserved)
		if t == "":
			return false
		reserved[t] = float(reserved.get(t, 0.0)) + land
		chain_tiles[b.role] = t
	var spent_before: float = _total_build + _total_land + _total_road + _total_rail + _total_pipe
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
	# Build each export corridor (branch tile -> destination / port): pipes for
	# liquids & gases (reinforced for hazardous), rail for solids.
	for b in branches:
		var src: String = chain_tiles[b.role]
		var dst: String = TransportService.nearest_port_tile(src) if str(b.export_to) == "MARKET" else chain_tiles[str(b.export_to)]
		_ensure_corridor(src, dst, _corridor_mode(str(b.export_good)))
		# Imported fluids (e.g. NaOH) can only be delivered from the port by pipe, so
		# lay an import pipeline tile -> port for any bought liquid/gas input.
		for gid in b.get("buy", []):
			var mode: String = _corridor_mode(str(gid))
			if mode != "rail":
				_ensure_corridor(src, TransportService.nearest_port_tile(src), mode)
	if MatchState.has_signal("money_changed"):
		MatchState.money_changed.emit(MatchState.money)
	if count_as_chain:
		_chains += 1
		_last_chain_cost = (_total_build + _total_land + _total_road + _total_rail + _total_pipe) - spent_before
	return true


func _finance() -> void:
	if MatchState.money < 0.0:
		var cap: float = LoanState.available_capacity()
		if cap >= 1.0:
			var amt: float = minf(-MatchState.money, cap)
			if amt >= 1.0 and LoanState.take_loan(amt):
				_total_borrowed += amt
	# Working-capital floor, drawn as a construction loan tracked in _construction_debt.
	# EQUITY-NEUTRAL (it just turns ignored negative cash into cash minus an equal debt)
	# but lets every chain pay for market imports during ramp, since the buy primitive
	# refuses to purchase while cash is non-positive. Expansion is paced separately (one
	# chain per marginal-profit judgment) so this floor does not cause over-building.
	if MatchState.money < WC_FLOOR:
		var topup: float = WC_FLOOR - MatchState.money
		MatchState.add_money(topup)
		_construction_debt += topup
		_total_borrowed += topup


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
	return cash + stock + bval - debt - _construction_debt


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
	MatchState.seaport_auto_subscribe = true   # seaports transfer any volume in 1 turn for a flat per-good fee
	await process_frame
	await process_frame
	await process_frame
	if RunMetrics and RunMetrics.has_method("reset"):
		RunMetrics.reset()
	_build_pool()
	_load_deposits()
	_road_cost = float(Catalog.get_building("b_005").get("base_price", 25.0))
	_rail_cost = float(Catalog.get_building("b_019").get("base_price", 70.0))
	_pipe_cost = float(Catalog.get_building("b_017").get("base_price", 30.0))
	_reinf_pipe_cost = float(Catalog.get_building("b_018").get("base_price", 50.0))

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
		var s: Dictionary = Production.last_turn_summary
		_net_hist.append(float(s.get("money_in", 0.0)) - float(s.get("money_out", 0.0)))
		var rn: float = _rolling_net()
		# "Out of red" = operating cash flow first turns positive (the WC floor keeps raw
		# cash positive, so this tracks real operations, not the construction loan).
		if _turn_out_of_red < 0 and rn > 0.0:
			_turn_out_of_red = turn
		var eq: float = _equity()
		for m in PROFIT_MILESTONES:
			if not _profit_at.has(m) and rn >= float(m):
				_profit_at[m] = turn
		for m in EQUITY_MILESTONES:
			if not _equity_at.has(m) and eq >= float(m):
				_equity_at[m] = turn
		# Once the chain is profitable, add ONE self-supply power station.
		if not _power_built and rn > 0.0 and turn > RAMP_TURNS:
			if _build_power_station():
				_power_turn = turn
				_finance()
		if _judge_turn > 0 and turn >= _judge_turn:
			# Marginal profit of the last expansion went negative: record the turn and
			# stop expanding, but keep running to TURNS so the held trajectory is logged.
			if rn - _pre_expand_net < 0.0:
				if _stopped_turn < 0:
					_stopped_turn = turn
				_land_exhausted = true
			_judge_turn = 0
		# Expand only when no marginal-profit judgment is pending: build one chain, wait
		# RAMP_TURNS, judge whether it helped, THEN consider the next. This paces growth
		# so thin-margin chains don't over-build before the guard can fire. Funded from
		# REAL accumulated cash (net of the working-capital loan) so a loss-making chain
		# — whose cash is only propped up by the WC floor — never expands.
		if not _land_exhausted and _judge_turn == 0 and (MatchState.money - _construction_debt) > _last_chain_cost and _chains < MAX_CHAINS:
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
	print("build=%.0f land=%.0f road=%.0f rail=%.0f pipe=%.0f borrowed=%.0f wc_debt=%.0f debt_end=%.0f" % [
		_total_build, _total_land, _total_road, _total_rail, _total_pipe, _total_borrowed, _construction_debt, LoanState.total_outstanding()])
	print("out_of_red=%s  2nd_chain=%s  transport/turn=%.1f  product_lifetime=%d" % [
		str(_turn_out_of_red), str(_turns_to_second), transport, _lifetime(_product)])
	print("steady net/turn=%+.1f  equity_slope=%+.1f  final_equity=%.0f  profitable=%s" % [
		ramped, slope, _equity(), ("YES" if (ramped > 0 and slope > 0 and _equity() > 0) else "NO")])
	print("profit@/turn: 100=%s 500=%s 1000=%s" % [_ms(_profit_at, 100), _ms(_profit_at, 500), _ms(_profit_at, 1000)])
	print("equity@: 500=%s 1000=%s 2500=%s 5000=%s 10000=%s" % [
		_ms(_equity_at, 500), _ms(_equity_at, 1000), _ms(_equity_at, 2500), _ms(_equity_at, 5000), _ms(_equity_at, 10000)])
	var tm := _tile_metrics()
	print("tiles=%d  80pct-cap_tiles=%d  transit-cap_tiles=%d (max outflow=%.0f/turn vs road200/rail400)  marginal0@turn=%s" % [
		int(tm[0]), int(tm[1]), int(tm[2]), float(tm[3]), (str(_stopped_turn) if _stopped_turn > 0 else "never")])
	print("power_station=%s (%s)" % [
		(("built@turn " + str(_power_turn)) if _power_built else "not built"),
		("processed_oil-fired" if _chain == "plastics" else "coal-fired")])
	print("==== DONE %s ====\n" % _chain)


func _ms(d: Dictionary, key: int) -> String:
	return str(d[key]) if d.has(key) else "-"


func _tile_metrics() -> Array:
	var present := 0
	var eighty := 0
	var transit := 0
	var maxflow := 0.0
	for tid in MatchState.tile_buildings.keys():
		present += 1
		if MatchState.get_tile_space_used(tid) >= 0.8 * MAX_TILE_LAND:
			eighty += 1
		var outflow := 0.0
		for inst_id in MatchState.tile_buildings[tid]:
			var inst: Dictionary = MatchState.get_building(inst_id)
			for o in Catalog.get_recipe(str(inst.get("recipe_id", ""))).get("outputs", []):
				var gid: String = str(o.get("good_id", ""))
				if MatchState.is_output_market(inst_id, gid) or MatchState.get_output_stockpile_destination(inst_id, gid) != "":
					outflow += float(o.get("qty", 0))
		maxflow = maxf(maxflow, outflow)
		if outflow >= 200.0:
			transit += 1
	return [present, eighty, transit, maxflow]


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
