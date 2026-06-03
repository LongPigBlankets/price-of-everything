extends SceneTree
# Headless PROFITABLE MOTOR supply-chain run to turn 200, with CASH-GATED expansion.
#
#   <godot> --headless --path . --script res://tools/sim_profitable_run.gd
#
# Strategy: start the player with 300 cash and build ONE balanced motor chain on a
# tile (deducting its real build cost). The chain sells ONLY its motors (g_008) to
# market; every intermediate stays on-tile to feed the next stage. Each turn AFTER
# resolution, if cash exceeds the build cost of one full chain, build the next
# identical chain on a fresh tile and deduct the cost. "Stabilise then expand"
# therefore emerges on its own: the first chain must ramp and accumulate cash before
# the gate (cash > CHAIN_COST) opens. We record the turn the 2nd chain is built.
#
# One chain lives on ONE tile. Balanced so nothing starves at steady state (per-turn,
# full-output throughput in []):
#   copper branch
#     3x copper mine     b_001/r_006  -> copper_ore [60]
#     2x copper furnace  b_002/r_007  copper_ore 60 -> copper_ingots [60]
#     2x wire factory    b_007/r_008  copper_ingots 40 -> copper_wiring [40]
#   steel branch
#     2x iron mine       b_001/r_002  -> iron_ore [40]
#     1x coal mine       b_001/r_001  -> coal [20]
#     1x pig-iron furnace b_002/r_005 iron_ore 30 + coal 10 -> iron_ingots [30]
#     1x steel furnace   b_002/r_003  iron_ingots 20 + coal 10 -> steel [30]
#   motor
#     2x motor factory   b_007/r_009  steel 30 + copper_wiring 24 -> motor [30]  (-> MARKET)
#
# Limiter is the motor stage at a clean 30 steel + 24 copper_wiring per turn, so the two
# motor factories run at full output (30 motors/turn) once ramped. The steel->motor and
# coal handoffs are exactly balanced; the copper branch carries a small STRUCTURAL
# surplus that the motor recipe can't absorb (copper_ingots +20/turn, copper_wiring
# +16/turn) — the motor quantities simply don't tile evenly onto the furnaces/wire
# factories, and no integer building count removes it.
#
# Why this matters: a tile's stockpile is hard-capped at 500 units
# (Stockpile.TILE_CAPACITY). Left alone, that copper surplus saturates the cap in ~15
# turns, then crowds STEEL and COPPER_WIRING off the tile and the motor factories
# starve (motors stop, revenue -> 0). So per the brief's "rebalance if it runs a big
# surplus", each chain tile runs a standing AUTO-SELL-SURPLUS order
# (MatchState.enable_sell_surplus). The engine sells only what is left AFTER every
# on-tile consumer's full per-turn demand is reserved (Production.compute_committed_for_tile),
# so it can NEVER starve the chain — it just drains the genuine, unconsumable copper
# surplus and keeps the tile lean. Motors are the primary product (routed to market);
# the small surplus-copper sales are incidental.
#
# Build cost is charged manually (add_building is free under --script): CHAIN_COST is
# the sum of Catalog.get_building(id).base_price over the chain's buildings. Operating
# cost is maintenance + labour + grid power + transport; revenue is motor + surplus
# sales. We report the actual cash/equity trajectory from RunMetrics, not an assumption.

const TURNS := 200
const G_MOTOR := "g_008"
const STARTING_CASH := 300.0
# Cap on simultaneous chains. The motor chain is so profitable that, left unbounded,
# cash clears CHAIN_COST several times over every turn and the run builds dozens of
# chains per turn — thousands of buildings — which makes the per-turn PROCESS pass (no
# route cache here) explode and turn 200 unreachable. We therefore build at most ONE
# new chain per turn (the brief's "build the next chain") and stop at MAX_CHAINS, which
# keeps the 200-turn run tractable while still exercising cash-gated expansion. Set to a
# large number to let it run away.
const MAX_CHAINS := 10

# One chain's buildings: [building_id, recipe_id, count, is_motor_factory].
const CHAIN_SPEC := [
	# copper branch
	["b_001", "r_006", 3, false],   # 3x copper mine
	["b_002", "r_007", 2, false],   # 2x copper furnace
	["b_007", "r_008", 2, false],   # 2x wire factory
	# steel branch
	["b_001", "r_002", 2, false],   # 2x iron mine
	["b_001", "r_001", 1, false],   # 1x coal mine
	["b_002", "r_005", 1, false],   # 1x pig-iron furnace
	["b_002", "r_003", 1, false],   # 1x steel furnace
	# motor
	["b_007", "r_009", 2, true],    # 2x motor factory -> MARKET
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
var _chains := 0
var _chain_cost := 0.0
var _turns_to_second_chain := -1


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


func _chain_building_count() -> int:
	var n := 0
	for spec in CHAIN_SPEC:
		n += int(spec[2])
	return n


func _compute_chain_cost() -> float:
	var total := 0.0
	for spec in CHAIN_SPEC:
		var bd: Dictionary = Catalog.get_building(str(spec[0]))
		total += float(bd.get("base_price", 0.0)) * int(spec[2])
	return total


func _initialize() -> void:
	print("\n==== sim_profitable_run (MOTOR chain, 200 turns, cash-gated expansion) ====")
	_resolve()
	_stub = _HexMapStub.new()
	get_root().add_child(_stub)
	TurnManager.phase_pause_duration = 0.0
	# Let the autoloads settle before we touch money / build.
	await process_frame
	await process_frame
	await process_frame
	if RunMetrics and RunMetrics.has_method("reset"):
		RunMetrics.reset()

	_chain_cost = _compute_chain_cost()

	# RULE 1: start with 300 cash. Take a loan ONLY if 300 can't fund chain #1.
	MatchState.money = STARTING_CASH
	if MatchState.has_signal("money_changed"):
		MatchState.money_changed.emit(MatchState.money)
	var loan_taken := 0.0
	if MatchState.money < _chain_cost:
		loan_taken = ceil(_chain_cost - MatchState.money)
		LoanState.take_loan(loan_taken)
		print("[sim] loan %.0f taken (300 < chain cost %.0f)" % [loan_taken, _chain_cost])

	print("[sim] CHAIN_COST = %.2f (sum of base_price over %d buildings/chain)" % [
		_chain_cost, _chain_building_count()])

	# Build chain #1 at start and deduct its cost (RULE 2 + RULE 3).
	_build_chain()
	await process_frame
	await process_frame
	print("[sim] start: cash=%.2f buildings=%d chains=%d (no expansion until cash > CHAIN_COST)" % [
		MatchState.money, MatchState.buildings.size(), _chains])

	for t in range(TURNS):
		TurnManager.commit_turn()
		await TurnManager.turn_resolution_completed
		var turn := t + 1

		# RULE 3: expand when affordable (cash strictly greater than one chain's cost).
		# One new chain per turn, up to MAX_CHAINS — "stabilise then expand" plays out
		# turn by turn instead of all at once.
		if MatchState.money > _chain_cost and _chains < MAX_CHAINS:
			_build_chain()
			if _chains == 2 and _turns_to_second_chain < 0:
				_turns_to_second_chain = turn
				print("[sim] >>> 2nd chain built at turn %d (cash before deduct was > %.0f)" % [
					turn, _chain_cost])

		if turn % 20 == 0 or turn == 1:
			var eq := _equity()
			print("[sim] turn %3d | chains=%2d buildings=%3d | cash=%9.1f equity=%9.1f | motor(life)=%5d shipments=%d" % [
				turn, _chains, MatchState.buildings.size(), MatchState.money, eq,
				_lifetime(G_MOTOR), MatchState.pending_transport_shipments.size()])

	if RunMetrics and RunMetrics.has_method("finish_run"):
		RunMetrics.finish_run()

	_print_report(loan_taken)
	quit(0)


func _chain_tile(idx: int) -> String:
	# Each chain gets its OWN tile (sharing one would re-trigger the 500-unit cap clog).
	# Lay them out in a compact band of tiles hugging the nearest port (tile_5_10):
	# columns 3..7, rows 9 up to 1 — 45 distinct tiles, all a few hops from the port so
	# the motor-sale + surplus-drain shipping stays cheap (cost = qty x turns x 0.2, and
	# turns grows with port distance).
	var cols := [5, 4, 6, 3, 7]
	var col: int = cols[idx % cols.size()]
	var row: int = 9 - int(idx / cols.size())   # 9, 8, 7, ... as the band fills
	if row < 1:
		row = 1                                  # clamp (we never expect this many chains)
	return "tile_%d_%d" % [col, row]


func _build_chain() -> void:
	var tile := _chain_tile(_chains)
	_stub.set_cabled_tile(tile)
	for spec in CHAIN_SPEC:
		for i in int(spec[2]):
			var inst: String = MatchState.add_building(str(spec[0]), str(spec[1]), tile)
			if bool(spec[3]):
				MatchState.route_output_to_market(inst, G_MOTOR)   # sell ONLY the motors
			# Force every input to come from the ON-TILE stockpile only — the chain
			# produces all its own intermediates, so it must never buy them from the
			# market (the default "stockpile then buy the shortfall" would bleed cash
			# topping up inputs we already make).
			var recipe: Dictionary = Catalog.get_recipe(str(spec[1]))
			for input in recipe.get("inputs", []):
				MatchState.set_input_tile_only(inst, str(input.get("good_id", "")), true)
	# Standing auto-sell-surplus order: drains the unconsumable copper surplus AFTER
	# every on-tile consumer's full demand is reserved, so it can never starve the
	# chain. Without it the 500/tile cap clogs and the motor factories starve.
	MatchState.enable_sell_surplus(tile)
	# Charge the build cost manually — add_building is free under --script, so this
	# is what makes the expansion gate real.
	MatchState.money -= _chain_cost
	if MatchState.has_signal("money_changed"):
		MatchState.money_changed.emit(MatchState.money)
	_chains += 1


func _lifetime(good_id: String) -> int:
	var total := 0
	for d in Production.produced_by_building.values():
		total += int(d.get(good_id, 0))
	return total


func _equity() -> float:
	# cash + stockpile value + building value - debt (mirrors RunMetrics' definition).
	var cash: float = float(MatchState.money)
	var stock := 0.0
	var totals: Dictionary = Stockpile.get_all_totals()
	for gid in totals.keys():
		var qty := int(totals[gid])
		if qty > 0:
			stock += float(qty) * MarketState.get_price(str(gid))
	var bval := 0.0
	for inst in MatchState.buildings.values():
		var bd: Dictionary = Catalog.get_building(str(inst.get("building_id", "")))
		bval += float(bd.get("base_price", 0.0))
	var debt := 0.0
	if LoanState and LoanState.has_method("total_outstanding"):
		debt = float(LoanState.total_outstanding())
	return cash + stock + bval - debt


func _print_report(loan_taken: float) -> void:
	# Pull the per-run roll-up + the per-turn CSV to judge steady-state profitability.
	var final_cash := float(MatchState.money)
	var final_equity := _equity()
	var peak_equity := final_equity
	var total_produced := 0
	var summary_path: String = RunMetrics.SUMMARY_PATH
	if FileAccess.file_exists(summary_path):
		var f := FileAccess.open(summary_path, FileAccess.READ)
		var j = JSON.parse_string(f.get_as_text())
		f.close()
		if j is Dictionary:
			final_cash = float(j.get("final_cash", final_cash))
			final_equity = float(j.get("final_equity", final_equity))
			peak_equity = float(j.get("peak_equity", peak_equity))
			total_produced = int(j.get("total_produced", 0))

	# Steady-state per-turn net: average post-tax profit over the LAST 20 logged turns
	# (well after the first chain has ramped), plus the equity slope over that window.
	var rows: Array = RunMetrics.read_rows() if RunMetrics.has_method("read_rows") else []
	var ramped_net := 0.0
	var equity_slope := 0.0
	if rows.size() >= 2:
		var window: int = mini(20, rows.size() - 1)
		var first: Dictionary = rows[rows.size() - 1 - window]
		var last: Dictionary = rows[rows.size() - 1]
		var sum_profit := 0.0
		for i in range(rows.size() - window, rows.size()):
			sum_profit += float(rows[i].get("profit_post_tax", "0"))
		ramped_net = sum_profit / float(window)
		var de := float(last.get("equity", "0")) - float(first.get("equity", "0"))
		equity_slope = de / float(window)

	var profitable := ramped_net > 0.0 and equity_slope > 0.0 and final_equity > 0.0

	print("\n================ MOTOR-CHAIN PROFITABILITY REPORT ================")
	print("CHAIN_COST (build cost / chain)      : %.2f" % _chain_cost)
	print("Starting cash                        : %.2f%s" % [
		STARTING_CASH, (" (+ loan %.0f)" % loan_taken) if loan_taken > 0.0 else " (no loan)"])
	print("turns_to_second_chain                : %s" % (
		str(_turns_to_second_chain) if _turns_to_second_chain > 0 else "NOT REACHED"))
	print("Chains built by turn %d              : %d" % [TURNS, _chains])
	print("Total motors produced (lifetime)     : %d" % _lifetime(G_MOTOR))
	print("Total units produced (all goods)     : %d" % total_produced)
	print("Per-turn net (avg post-tax, last 20) : %+.2f  (ramped/steady state)" % ramped_net)
	print("Equity slope (last 20 turns)         : %+.2f / turn" % equity_slope)
	print("Final cash                           : %.2f" % final_cash)
	print("Final equity                         : %.2f" % final_equity)
	print("Peak equity                          : %.2f" % peak_equity)
	print("Profitable (net>0 & equity growing>0): %s" % ("YES" if profitable else "NO"))
	print("Equity positive & growing            : %s" % (
		"YES" if (final_equity > 0.0 and equity_slope > 0.0) else "NO"))
	print("==================================================================")
	print("[sim] run_metrics.csv -> user://run_metrics.csv ; summary -> %s" % summary_path)
	print("[sim] turn_profile.csv -> user://turn_profile.csv (%d turns)" % TURNS)
	print("==== sim_profitable_run: DONE ====\n")


# Minimal hex_map stub so Power.is_supplied() sees cables on each chain's tile.
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
