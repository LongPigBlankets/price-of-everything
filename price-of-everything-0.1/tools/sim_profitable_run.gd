extends SceneTree
# Headless MOTOR supply-chain run to turn 200 on the REAL tiles around Stoneshore,
# with land purchase, density build-cost penalties, and genuine inter-tile transport.
#
#   <godot> --headless --path . --script res://tools/sim_profitable_run.gd
#
# SPATIAL MODEL (this is the point of this version):
# The deposits near the Stoneshore Docks port (tile_5_10) are FIXED tiles:
#   COAL   tile_6_8   (coal,       2 hexes from port, roads)
#   IRON   tile_7_10  (iron_ore,   3 hexes from port, roads)
#   COPPER tile_8_12  (copper_ore, 4 hexes from port, no roads -> overland)
# Final assembly sits on a corridor tile next to the port:
#   MOTOR  tile_5_8   (1 hex from port, roads)
# Every chain mines the SAME deposit tiles, so as we expand the deposit tiles fill
# up: land must be bought (10 land/patch at GBP10) and, past 100 land used, every new
# building costs 1.5x (density). Per the brief we DO NOT cap a tile at 200 — buildings
# keep stacking and keep paying land + density.
#
# Each branch refines ON its deposit tile (so bulky ore never ships); only the refined
# product travels toward the port, which is where the real transport bill comes from:
#   copper:  3 mine + 2 furnace + 2 wire   on COPPER ; copper_wiring -> MOTOR
#   iron:    2 mine + 1 pig-iron + 1 steel on IRON   ; steel        -> MOTOR
#   coal:    1 mine                        on COAL   ; coal         -> IRON
#   motor:   2 motor factory               on MOTOR  ; motor        -> MARKET (port)
# Per-chain inter-tile flow (qty/turn): coal 20 (COAL->IRON), steel 30 (IRON->MOTOR),
# copper_wiring 40 (COPPER->MOTOR), motor 30 (MOTOR->port). Transport = qty x turns x 0.2,
# turns = ceil(hex_distance / 2). Refined intermediates that the next stage can't absorb
# (copper_ingots, spare iron, surplus wiring) are drained by a standing sell-surplus order
# on each tile so the 500-unit tile cap doesn't clog.
#
# Recipe quantities (data/recipes_all.csv): r_006 copper_ore 20; r_007 copper_ore 30 ->
# copper_ingots 30; r_008 copper_ingots 20 -> copper_wiring 20; r_002 iron_ore 20;
# r_001 coal 20; r_005 iron_ore 30 + coal 10 -> iron_ingots 30; r_003 iron_ingots 20 +
# coal 10 -> steel 30; r_009 steel 15 + copper_wiring 12 -> motor 15.
#
# add_building is free under --script, so _place() charges build + density + land
# manually; that (plus operating cost, transport, loan interest) is what the reported
# cash/equity trajectory reflects.

const TURNS := 200
const G_MOTOR := "g_008"
const STARTING_CASH := 300.0
const MAX_CHAINS := 10

# Real tiles near the Stoneshore Docks port (tile_5_10).
const COAL_TILE := "tile_6_8"
const IRON_TILE := "tile_7_10"
const COPPER_TILE := "tile_8_12"
const MOTOR_TILE := "tile_5_8"

# Land / density rules (mirrors MatchState + world_map._space_check_for_build, minus the
# 200 hard cap, which the brief says to ignore).
const FREE_LAND := 100.0       # MatchState.DEFAULT_TILE_LAND_OWNED
const LAND_PATCH := 10.0       # MatchState.LAND_PATCH_SIZE
const LAND_PATCH_COST := 10.0  # MatchState.LAND_PATCH_COST
const DENSITY_SOFT_CAP := 100.0  # world_map.DENSITY_SOFT_CAPACITY -> 1.5x build cost above this

# One chain's buildings: [building_id, recipe_id, count, tile_role, output_dest].
# output_dest: "" = stays on the tile (STOCKPILE_ALL default), a role = ship there, "MARKET" = sell at port.
const CHAIN_SPEC := [
	["b_001", "r_006", 3, "COPPER", ""],        # copper mine   -> copper_ore (local)
	["b_002", "r_007", 2, "COPPER", ""],        # copper furnace -> copper_ingots (local)
	["b_007", "r_008", 2, "COPPER", "MOTOR"],   # wire factory  -> copper_wiring -> MOTOR
	["b_001", "r_002", 2, "IRON", ""],          # iron mine     -> iron_ore (local)
	["b_001", "r_001", 1, "COAL", "IRON"],      # coal mine     -> coal -> IRON
	["b_002", "r_005", 1, "IRON", ""],          # pig-iron furnace -> iron_ingots (local)
	["b_002", "r_003", 1, "IRON", "MOTOR"],     # steel furnace -> steel -> MOTOR
	["b_007", "r_009", 2, "MOTOR", "MARKET"],   # motor factory -> motor -> port market
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
var _chain_cost := 0.0            # base build cost (no density/land), for reference
var _last_chain_cost := 0.0       # actual cost of the most recent chain (build + density + land)
var _turns_to_second_chain := -1
var _turn_out_of_red := -1
var _total_borrowed := 0.0
var _total_build_spent := 0.0     # build cost incl. density multiplier
var _total_land_spent := 0.0      # land patches purchased
var _land_owned: Dictionary = {}  # tile_id -> land units owned (starts at FREE_LAND)


func _role_tile(role: String) -> String:
	match role:
		"COAL": return COAL_TILE
		"IRON": return IRON_TILE
		"COPPER": return COPPER_TILE
		"MOTOR": return MOTOR_TILE
	return MOTOR_TILE


func _recipe_output_good(recipe_id: String) -> String:
	var r: Dictionary = Catalog.get_recipe(recipe_id)
	var outs: Array = r.get("outputs", [])
	if outs.size() > 0:
		return str(outs[0].get("good_id", ""))
	return ""


func _finance() -> void:
	# Draw on the dynamic (profit-gated) loan facility to cover any cash deficit. The
	# seed chain and its ramp run the company into the red; capacity scales with rolling
	# profit, so the facility digs it out once motors sell. Expansion stays CASH-funded.
	if MatchState.money >= 0.0:
		return
	var cap: float = LoanState.available_capacity()
	if cap < 1.0:
		return
	var amt: float = minf(-MatchState.money, cap)
	if amt >= 1.0 and LoanState.take_loan(amt):
		_total_borrowed += amt


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


func _place(building_id: String, recipe_id: String, tile_id: String) -> String:
	# Place one building, charging land purchase (no 200 cap) + density build cost.
	var size: float = float(Catalog.get_building(building_id).get("tile_size_used", 1.0))
	var used: float = MatchState.get_tile_space_used(tile_id)
	var projected: float = used + size
	# Buy land patches to cover the projected footprint.
	var owned: float = float(_land_owned.get(tile_id, FREE_LAND))
	if projected > owned:
		var patches: int = int(ceil((projected - owned) / LAND_PATCH))
		var land_cost: float = float(patches) * LAND_PATCH_COST
		MatchState.add_money(-land_cost)
		_land_owned[tile_id] = owned + float(patches) * LAND_PATCH
		_total_land_spent += land_cost
	# Density build-cost multiplier above the soft cap (1.5x), as in the real game.
	var mult: float = 1.5 if projected > DENSITY_SOFT_CAP else 1.0
	var cost: float = float(Catalog.get_building(building_id).get("base_price", 0.0)) * mult
	MatchState.add_money(-cost)
	_total_build_spent += cost
	return MatchState.add_building(building_id, recipe_id, tile_id)


func _build_chain() -> void:
	var spent_before: float = _total_build_spent + _total_land_spent
	var tiles_used: Dictionary = {}
	for spec in CHAIN_SPEC:
		var bid: String = str(spec[0])
		var rid: String = str(spec[1])
		var cnt: int = int(spec[2])
		var tile: String = _role_tile(str(spec[3]))
		var dest: String = str(spec[4])
		_stub.set_cabled_tile(tile)
		tiles_used[tile] = true
		var out_good: String = _recipe_output_good(rid)
		for i in cnt:
			var inst: String = _place(bid, rid, tile)
			if dest == "MARKET":
				MatchState.route_output_to_market(inst, out_good)        # sell at the nearest port
			elif dest != "":
				MatchState.set_output_stockpile_destination(inst, _role_tile(dest), out_good)  # ship to next tile
			# Force every input from the local tile stockpile (the chain makes/ships its
			# own intermediates; never top them up from the market).
			var recipe: Dictionary = Catalog.get_recipe(rid)
			for input in recipe.get("inputs", []):
				MatchState.set_input_tile_only(inst, str(input.get("good_id", "")), true)
	# Drain each touched tile's structural surplus (copper ingots, spare iron, surplus
	# wiring) so the 500-unit tile cap never clogs and starves a consumer.
	for tile in tiles_used:
		MatchState.enable_sell_surplus(tile)
	if MatchState.has_signal("money_changed"):
		MatchState.money_changed.emit(MatchState.money)
	_chains += 1
	_last_chain_cost = (_total_build_spent + _total_land_spent) - spent_before


func _initialize() -> void:
	print("\n==== sim_profitable_run (MOTOR chain on Stoneshore tiles, 200 turns) ====")
	_resolve()
	_stub = _HexMapStub.new()
	get_root().add_child(_stub)
	TurnManager.fast_mode = true   # compute-constrained: no human pacing delay
	await process_frame
	await process_frame
	await process_frame
	if RunMetrics and RunMetrics.has_method("reset"):
		RunMetrics.reset()

	_chain_cost = _compute_chain_cost()
	print("[sim] base CHAIN_COST = %.2f over %d buildings/chain (before density + land)" % [
		_chain_cost, _chain_building_count()])

	# Start with 300 cash and build the seed chain across the real deposit tiles.
	MatchState.money = STARTING_CASH
	if MatchState.has_signal("money_changed"):
		MatchState.money_changed.emit(MatchState.money)
	_build_chain()
	_finance()
	await process_frame
	await process_frame
	print("[sim] start: cash=%.2f debt=%.2f buildings=%d | seed cost(build+density+land)=%.2f" % [
		MatchState.money, LoanState.total_outstanding(), MatchState.buildings.size(), _last_chain_cost])

	for t in range(TURNS):
		TurnManager.commit_turn()
		await TurnManager.turn_resolution_completed
		var turn := t + 1

		_finance()
		if _turn_out_of_red < 0 and MatchState.money >= 0.0:
			_turn_out_of_red = turn

		# Expand when cash exceeds what the LAST chain actually cost (which climbs as the
		# deposit tiles fill with density + land charges). One new chain per turn.
		if MatchState.money > _last_chain_cost and _chains < MAX_CHAINS:
			_build_chain()
			if _chains == 2 and _turns_to_second_chain < 0:
				_turns_to_second_chain = turn
				print("[sim] >>> 2nd chain built at turn %d (cash exceeded last-chain cost %.0f)" % [
					turn, _last_chain_cost])

		if turn % 20 == 0 or turn == 1:
			var eq := _equity()
			print("[sim] turn %3d | chains=%2d buildings=%3d | cash=%9.1f debt=%8.1f equity=%9.1f | motor(life)=%5d" % [
				turn, _chains, MatchState.buildings.size(), MatchState.money,
				LoanState.total_outstanding(), eq, _lifetime(G_MOTOR)])

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
	# cash + stockpile value + building value - debt (mirrors RunMetrics' definition).
	# Land + density spend is sunk (not an asset), so it shows up only as reduced cash.
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


func _tile_land_summary() -> String:
	var parts: Array = []
	for tile in [COPPER_TILE, IRON_TILE, COAL_TILE, MOTOR_TILE]:
		var land: float = float(_land_owned.get(tile, FREE_LAND))
		var used: float = MatchState.get_tile_space_used(tile)
		parts.append("%s used=%d/owned=%d" % [tile, int(used), int(land)])
	return " | ".join(parts)


func _print_report() -> void:
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
		var de := float(last.get("equity", "0")) - float(first.get("equity", "0"))
		equity_slope = de / float(window)
		transport_last = float(last.get("cost_transport", "0"))

	var profitable := ramped_net > 0.0 and equity_slope > 0.0 and final_equity > 0.0

	print("\n============ MOTOR-CHAIN (STONESHORE TILES) REPORT ============")
	print("Base build cost / chain              : %.2f (before density + land)" % _chain_cost)
	print("Last chain actual cost               : %.2f (build+density+land)" % _last_chain_cost)
	print("Total spent on construction          : %.2f (incl. density)" % _total_build_spent)
	print("Total spent on land patches          : %.2f" % _total_land_spent)
	print("Starting cash                        : %.2f" % STARTING_CASH)
	print("Total borrowed over run              : %.2f" % _total_borrowed)
	print("Outstanding debt at end              : %.2f" % LoanState.total_outstanding())
	print("Turn cash first climbed out of red   : %s" % (
		str(_turn_out_of_red) if _turn_out_of_red > 0 else "STILL IN RED"))
	print("turns_to_second_chain                : %s" % (
		str(_turns_to_second_chain) if _turns_to_second_chain > 0 else "NOT REACHED"))
	print("Chains built by turn %d              : %d" % [TURNS, _chains])
	print("Transport cost (last logged turn)    : %.2f / turn" % transport_last)
	print("Tile occupancy: %s" % _tile_land_summary())
	print("Total motors produced (lifetime)     : %d" % _lifetime(G_MOTOR))
	print("Total units produced (all goods)     : %d" % total_produced)
	print("Per-turn net (avg post-tax, last 20) : %+.2f  (ramped/steady state)" % ramped_net)
	print("Equity slope (last 20 turns)         : %+.2f / turn" % equity_slope)
	print("Final cash                           : %.2f" % final_cash)
	print("Final equity                         : %.2f" % final_equity)
	print("Profitable (net>0 & equity growing>0): %s" % ("YES" if profitable else "NO"))
	print("===============================================================")
	print("[sim] run_metrics.csv -> user://run_metrics.csv ; summary -> %s" % summary_path)
	print("[sim] turn_profile.csv -> user://turn_profile.csv (%d turns)" % TURNS)
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
