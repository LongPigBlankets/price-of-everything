extends SceneTree
# Headless mini-strategy validation sim for RunMetrics.
#
# Stands up a small, deliberately-imperfect production chain and runs ~12 turns
# so RunMetrics logs a realistic trajectory, then ASSERTS the metrics are correct.
#
# Run it:
#   <godot> --headless --path . --script res://tools/sim_mini_strategy.gd
#
# The chain (all on ONE tile so same-tile outputs flow to the next building the
# NEXT turn via the output-buffer flush — the chain ramps over several turns):
#   1 coal mine        b_001 / r_001  -> coal
#   2 iron mines       b_001 / r_002  -> iron_ore   (x2)
#   1 iron furnace     b_002 / r_005  iron_ore + coal      -> iron_ingots
#   1 steel furnace    b_002 / r_003  iron_ingots + coal   -> steel        (mid-good)
#   1 copper furnace   b_002 / r_007  copper_ore           -> copper_ingots (STARVED: no copper mine)
#   1 wiring factory   b_007 / r_008  copper_ingots        -> copper_wiring
#   1 motor factory    b_007 / r_009  steel + copper_wiring -> motor        (capstone)
#
# Mines have no inputs and must produce every turn regardless of deposits.
# The copper furnace has no copper-ore source and must report starved every turn
# — that validates the starvation metric.

const TILE := "tile_8_8"           # everything lives here so the chain can flow
const STARVED_BUILDING := "b_002"  # copper furnace (r_007) — intentionally starved
const TURNS := 12

# good ids (from data/Goods - goodsMVP.csv)
const G_COAL := "g_001"
const G_IRON_ORE := "g_002"
const G_IRON_INGOTS := "g_004"
const G_STEEL := "g_006"
const G_COPPER_WIRING := "g_007"
const G_MOTOR := "g_008"

var _failures: int = 0
var _checks: int = 0
var _copper_furnace_inst: String = ""
var _starved_every_turn := true
var _starved_turns_seen := 0

# Autoload singletons. Under `--script` (vs running as a scene) the autoloads are
# added to root but are NOT exposed as compile-time global identifiers, so resolve
# them from /root by name and hold typed references.
var MatchState: Node
var Stockpile: Node
var MarketState: Node
var Catalog: Node
var Production: Node
var TurnManager: Node
var RunMetrics: Node
var LoanState: Node


func _resolve_singletons() -> void:
	var r := get_root()
	MatchState = r.get_node("MatchState")
	Stockpile = r.get_node("Stockpile")
	MarketState = r.get_node("MarketState")
	Catalog = r.get_node("Catalog")
	Production = r.get_node("Production")
	TurnManager = r.get_node("TurnManager")
	RunMetrics = r.get_node("RunMetrics")
	LoanState = r.get_node("LoanState")


func _initialize() -> void:
	print("\n==== sim_mini_strategy ====")
	_resolve_singletons()
	# A fresh --script launch starts autoloads in default state, so no reset needed.
	# Stand up a minimal hex_map stub so Power.is_supplied() (which looks for cables
	# on the building's tile via a node in group "hex_map") returns true headless —
	# every production recipe in this chain has energy_req > 0.
	_install_hexmap_stub()

	# Compute-constrained: no human pacing delay needed for a headless sim.
	if TurnManager:
		TurnManager.fast_mode = true

	# Let the autoloads finish their deferred _ready wiring (Production connects to
	# TurnManager.phase_started, MarketState to turn_advanced, RunMetrics to both).
	await process_frame
	await process_frame
	await process_frame

	# Make sure RunMetrics starts from a clean CSV even if a previous run left one.
	if RunMetrics and RunMetrics.has_method("reset"):
		RunMetrics.reset()

	_place_chain()
	await process_frame
	await process_frame

	print("[sim] placed %d buildings on %s" % [MatchState.buildings.size(), TILE])

	# Run the turns. commit_turn() drives PROCESS..RECEIVE then advances the turn.
	for t in range(TURNS):
		TurnManager.commit_turn()
		await TurnManager.turn_resolution_completed
		_observe_turn(t + 1)

	# Finalise the per-run roll-up.
	if RunMetrics and RunMetrics.has_method("finish_run"):
		RunMetrics.finish_run()

	_run_assertions()
	_print_tail()
	_report()
	quit(1 if _failures > 0 else 0)


# === Setup ===

func _install_hexmap_stub() -> void:
	var stub := _HexMapStub.new()
	stub.set_cabled_tile(TILE)
	get_root().add_child(stub)

func _place_chain() -> void:
	# Default sell_mode is STOCKPILE_ALL: outputs land on the building's own tile,
	# so same-tile consumers can read them the next turn. Keep it that way.
	MatchState.add_building("b_001", "r_001", TILE)               # coal mine
	MatchState.add_building("b_001", "r_002", TILE)               # iron mine 1
	MatchState.add_building("b_001", "r_002", TILE)               # iron mine 2
	MatchState.add_building("b_002", "r_005", TILE)               # iron furnace (pig iron)
	MatchState.add_building("b_002", "r_003", TILE)               # steel furnace
	_copper_furnace_inst = MatchState.add_building("b_002", "r_007", TILE)  # copper furnace (starved)
	MatchState.add_building("b_007", "r_008", TILE)               # copper-wiring factory
	MatchState.add_building("b_007", "r_009", TILE)               # motor factory (capstone)


# === Per-turn observation ===

func _observe_turn(turn: int) -> void:
	# Did the copper furnace report starved this turn? Check the latest production summary.
	var starved_ids: Array = []
	for rec in Production.last_turn_summary.get("starved", []):
		starved_ids.append(str(rec.get("instance_id", "")))
	var copper_starved: bool = starved_ids.has(_copper_furnace_inst)
	if copper_starved:
		_starved_turns_seen += 1
	else:
		_starved_every_turn = false

	var produced: Dictionary = Production.last_turn_summary.get("produced", {})
	print("[sim] turn %2d | cash £%.2f | produced=%s | starved=%d (copper_furnace=%s)" % [
		turn, MatchState.money, _compact(produced),
		Production.last_turn_summary.get("starved", []).size(),
		"yes" if copper_starved else "no",
	])


# === Assertions ===

func _run_assertions() -> void:
	var rows: Array = RunMetrics.read_rows()
	_check(rows.size() == TURNS, "RunMetrics logged one row per turn (got %d, want %d)" % [rows.size(), TURNS])

	# 1) The chain's mid-good (steel) is produced > 0 once the chain ramps.
	var steel_total: int = _lifetime_good(G_STEEL)
	_check(steel_total > 0, "steel (mid-good) produced once chain ramped (lifetime=%d)" % steel_total)

	# Coal + iron ore (the raw mines) must run every single turn from turn 1.
	var coal_total: int = _lifetime_good(G_COAL)
	var iron_ore_total: int = _lifetime_good(G_IRON_ORE)
	_check(coal_total > 0, "coal mine produced (lifetime=%d)" % coal_total)
	_check(iron_ore_total > 0, "iron mines produced (lifetime=%d)" % iron_ore_total)

	# Capstone: the motor needs copper_wiring, whose chain (copper furnace) is
	# intentionally starved — so the capstone must NOT produce. This proves the
	# starvation propagates all the way down the dependency chain (a "silent" dead
	# branch the metrics make visible). The valid coal->iron->steel branch flows;
	# the copper->wiring->motor branch is dead.
	var motor_total: int = _lifetime_good(G_MOTOR)
	var wiring_total: int = _lifetime_good(G_COPPER_WIRING)
	_check(wiring_total == 0, "copper_wiring dead (copper furnace starved) — none produced (got %d)" % wiring_total)
	_check(motor_total == 0, "motor capstone dead (copper_wiring starved upstream) — none produced (got %d)" % motor_total)

	# 2) The copper furnace is reported starved EVERY turn (no copper-ore source).
	_check(_starved_every_turn and _starved_turns_seen == TURNS,
		"copper furnace starved every turn (%d/%d turns)" % [_starved_turns_seen, TURNS])

	# The starved-input metric should name copper_ore on at least one logged row.
	var copper_ore_named := false
	for r in rows:
		if str(r.get("most_missing_input", "")) == "copper_ore":
			copper_ore_named = true
			break
	_check(copper_ore_named, "CSV most_missing_input names 'copper_ore' on a starved turn")

	# 3) Equity + cash are logged every turn (numeric, non-empty).
	var equity_ok := true
	var cash_ok := true
	for r in rows:
		if str(r.get("equity", "")).is_empty() or not str(r.get("equity")).is_valid_float():
			equity_ok = false
		if str(r.get("cash", "")).is_empty() or not str(r.get("cash")).is_valid_float():
			cash_ok = false
	_check(equity_ok, "equity logged (numeric) every turn")
	_check(cash_ok, "cash logged (numeric) every turn")

	# starved_count >= 1 on every row (copper furnace is always starved).
	var starved_ok := true
	for r in rows:
		if int(str(r.get("starved_count", "0")).to_int()) < 1:
			starved_ok = false
	_check(starved_ok, "starved_count >= 1 on every logged row")

	# 4) The capacity-loss counter works: overflow a tile and confirm it's counted,
	#    and that reset zeroes it (deterministic, independent of the chain).
	_check_capacity_counter()

	# Per-run summary file exists and has the expected keys.
	_check_summary_file()


func _check_capacity_counter() -> void:
	var t := "tile_29_19"  # a tile the chain never touches
	Stockpile.reset_capacity_lost_this_turn()
	var cap: int = Stockpile.get_capacity(t)
	# Fill to capacity, then push 50 more — those 50 must be recorded as lost.
	var added_full: int = Stockpile.add(t, G_COAL, cap)
	var added_over: int = Stockpile.add(t, G_COAL, 50)
	var lost: int = Stockpile.get_capacity_lost_this_turn()
	_check(added_full == cap, "stockpile add fills to capacity (%d/%d)" % [added_full, cap])
	_check(added_over == 0, "stockpile add over capacity stores nothing")
	_check(lost == 50, "capacity-loss counter recorded the 50 lost units (got %d)" % lost)
	Stockpile.reset_capacity_lost_this_turn()
	_check(Stockpile.get_capacity_lost_this_turn() == 0, "capacity-loss counter resets to 0")
	# Clean up so we don't leave stray stock around.
	Stockpile.consume(t, G_COAL, cap)


func _check_summary_file() -> void:
	var path: String = RunMetrics.SUMMARY_PATH
	_check(FileAccess.file_exists(path), "run_metrics_summary.json written")
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	var ok: bool = parsed is Dictionary \
		and parsed.has("peak_equity") and parsed.has("final_equity") \
		and parsed.has("final_cash") and parsed.has("time_to_first_positive_profit") \
		and parsed.has("max_drawdown") and parsed.has("turns_survived") \
		and parsed.has("total_produced")
	_check(ok, "summary JSON carries the per-run roll-up keys")
	if ok:
		print("[sim] run summary: turns_survived=%d total_produced=%d peak_equity=%.2f final_equity=%.2f final_cash=%.2f" % [
			int(parsed.turns_survived), int(parsed.total_produced),
			float(parsed.peak_equity), float(parsed.final_equity), float(parsed.final_cash),
		])


# === Helpers ===

func _lifetime_good(good_id: String) -> int:
	var total := 0
	for d in Production.produced_by_building.values():
		total += int(d.get(good_id, 0))
	return total

func _compact(d: Dictionary) -> String:
	var parts: Array = []
	for k in d.keys():
		parts.append("%s:%d" % [Catalog.get_display_name(str(k)), int(d[k])])
	return "{" + ", ".join(parts) + "}"

func _print_tail() -> void:
	# Print the last few CSV rows so the run trajectory is visible in the log.
	var path: String = RunMetrics.CSV_PATH
	if not FileAccess.file_exists(path):
		print("[sim] (no CSV to show)")
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var lines: Array = []
	while not f.eof_reached():
		var l := f.get_line()
		if l.strip_edges() != "":
			lines.append(l)
	f.close()
	print("\n[sim] run_metrics.csv (header + last 4 rows):")
	if lines.size() > 0:
		print("  ", lines[0])
	var start: int = maxi(1, lines.size() - 4)
	for i in range(start, lines.size()):
		print("  ", lines[i])

func _check(ok: bool, name: String) -> void:
	_checks += 1
	if ok:
		print("  PASS  ", name)
	else:
		_failures += 1
		printerr("  FAIL  ", name)

func _report() -> void:
	var verdict := "PASS" if _failures == 0 else "FAIL"
	print("\n==== sim_mini_strategy: %s (%d/%d checks passed) ====\n" % [
		verdict, _checks - _failures, _checks])


# === Minimal hex_map stub: just enough for Power.is_supplied() ===
# Power._tile_has_cables() does:
#   var hex_map = get_tree().get_first_node_in_group("hex_map")
#   var coord = hex_map.id_to_coord(tile_id)
#   return hex_map.tiles[coord].infrastructure_present.has("cables")
class _HexMapStub extends Node:
	var tiles: Dictionary = {}

	func _enter_tree() -> void:
		add_to_group("hex_map")

	func set_cabled_tile(tile_id: String) -> void:
		var coord := id_to_coord(tile_id)
		tiles[coord] = {"infrastructure_present": ["cables"]}

	func id_to_coord(id: String) -> Vector2i:
		var parts := id.split("_")
		if parts.size() != 3 or parts[0] != "tile":
			return Vector2i(-1, -1)
		if not parts[1].is_valid_int() or not parts[2].is_valid_int():
			return Vector2i(-1, -1)
		return Vector2i(int(parts[1]) - 1, int(parts[2]) - 1)
