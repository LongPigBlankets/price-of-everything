extends SceneTree
# Headless PROFITABLE, EXPANDING run to turn 100 — to map the per-turn PROCESS
# time curve as the economy grows.
#
#   <godot> --headless --path . --script res://tools/sim_profitable_run.gd
#
# Strategy: take a loan, then run a coal->iron->steel chain whose STEEL is sold to
# market (intermediates stay on the tile to feed the chain). Every EXPAND_EVERY
# turns add another identical chain on a fresh tile, up to MAX_CHAINS — so the
# building/shipment load (and thus PROCESS work) climbs over the run.
#
# Each chain unit (one tile, over-provisioned on coal/iron so the furnaces never
# starve):
#   4x coal mine     b_001/r_001 -> coal
#   3x iron mine     b_001/r_002 -> iron_ore
#   1x iron furnace  b_002/r_005  iron_ore + coal    -> iron_ingots
#   1x steel furnace b_002/r_003  iron_ingots + coal -> steel  (routed to MARKET)
#
# Note: under --script, add_building bypasses the world_map money/space checks, so
# buildings are effectively free here; costs are operating (maintenance/labour/
# power/transport) + loan interest, revenue is steel sales. We report the actual
# cash/equity trajectory rather than assuming profit.

const TURNS := 100
const EXPAND_EVERY := 8
const MAX_CHAINS := 12
const LOAN := 1500.0
const G_STEEL := "g_006"

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


func _initialize() -> void:
	print("\n==== sim_profitable_run (100 turns, expanding) ====")
	_resolve()
	_stub = _HexMapStub.new()
	get_root().add_child(_stub)
	TurnManager.phase_pause_duration = 0.0
	await process_frame
	await process_frame
	await process_frame
	if RunMetrics and RunMetrics.has_method("reset"):
		RunMetrics.reset()

	LoanState.take_loan(LOAN)
	_add_chain()                       # chain #1 from turn 1
	await process_frame
	await process_frame
	print("[sim] loan %.0f taken; cash=%.2f; buildings=%d" % [LOAN, MatchState.money, MatchState.buildings.size()])

	for t in range(TURNS):
		TurnManager.commit_turn()
		await TurnManager.turn_resolution_completed
		var turn := t + 1
		if turn % EXPAND_EVERY == 0 and _chains < MAX_CHAINS:
			_add_chain()
		if turn % 10 == 0:
			var s: Dictionary = Production.last_turn_summary
			print("[sim] turn %3d | buildings=%2d chains=%2d | cash=%.0f | steel(life)=%d | shipments=%d" % [
				turn, MatchState.buildings.size(), _chains, MatchState.money,
				_lifetime(G_STEEL), MatchState.pending_transport_shipments.size()])

	if RunMetrics and RunMetrics.has_method("finish_run"):
		RunMetrics.finish_run()

	# Summary line
	var path: String = RunMetrics.SUMMARY_PATH
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		var j = JSON.parse_string(f.get_as_text())
		f.close()
		if j is Dictionary:
			print("\n[sim] economy: final_cash=%.0f final_equity=%.0f peak_equity=%.0f turns=%d total_produced=%d" % [
				float(j.get("final_cash", 0)), float(j.get("final_equity", 0)),
				float(j.get("peak_equity", 0)), int(j.get("turns_survived", 0)), int(j.get("total_produced", 0))])
	print("[sim] turn_profile.csv -> user://turn_profile.csv (%d turns)" % TURNS)
	print("==== sim_profitable_run: DONE ====\n")
	quit(0)


func _add_chain() -> void:
	var tile := "tile_%d_5" % (5 + _chains)
	_stub.set_cabled_tile(tile)
	for i in 4:
		MatchState.add_building("b_001", "r_001", tile)        # coal mine
	for i in 3:
		MatchState.add_building("b_001", "r_002", tile)        # iron mine
	MatchState.add_building("b_002", "r_005", tile)            # iron furnace
	var steel: String = MatchState.add_building("b_002", "r_003", tile)  # steel furnace
	MatchState.route_output_to_market(steel, G_STEEL)          # sell the steel
	_chains += 1


func _lifetime(good_id: String) -> int:
	var total := 0
	for d in Production.produced_by_building.values():
		total += int(d.get(good_id, 0))
	return total


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
