extends SceneTree
# Phase 0 baseline harness for the foundations sprint.
#
# Run:
#   <godot> --headless --path . --script res://tools/phase0_baseline.gd -- [turns]
#
# It records the current load and early-turn timing baseline without applying
# pass/fail thresholds. Later phases can compare against the emitted JSON.

const DEFAULT_TURNS := 20
const OUTPUT_PATH := "user://phase0_baseline.json"

var _turn_ms: Array = []


func _initialize() -> void:
	var turns := _requested_turns()
	print("\n==== Phase 0 Baseline: %d turns ====" % turns)

	var load_started := Time.get_ticks_usec()
	var packed: PackedScene = load("res://scenes/main.tscn")
	var scene_load_ms := _elapsed_ms(load_started)
	if packed == null:
		_fail("Could not load res://scenes/main.tscn")
		return

	var ready_started := Time.get_ticks_usec()
	var main_scene := packed.instantiate()
	get_root().add_child(main_scene)
	await process_frame
	await process_frame
	await process_frame
	var scene_ready_ms := _elapsed_ms(ready_started)

	var turn_manager := get_root().get_node_or_null("TurnManager")
	if turn_manager == null:
		_fail("TurnManager autoload missing")
		return
	turn_manager.fast_mode = true

	var run_metrics := get_root().get_node_or_null("RunMetrics")
	if run_metrics != null and run_metrics.has_method("reset"):
		run_metrics.reset()

	for _i in range(turns):
		var t0 := Time.get_ticks_usec()
		turn_manager.commit_turn()
		await turn_manager.turn_resolution_completed
		_turn_ms.append(_elapsed_ms(t0))

	var data := _baseline_data(main_scene, turns, scene_load_ms, scene_ready_ms)
	_write_json(data)
	_print_report(data)

	main_scene.queue_free()
	await process_frame
	quit(0)


func _requested_turns() -> int:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and str(args[0]).is_valid_int():
		return maxi(1, int(args[0]))
	return DEFAULT_TURNS


func _baseline_data(main_scene: Node, turns: int, scene_load_ms: float, scene_ready_ms: float) -> Dictionary:
	var match_state := get_root().get_node("MatchState")
	var catalog := get_root().get_node("Catalog")
	var turn_manager := get_root().get_node("TurnManager")
	var stats := _stats(_turn_ms)
	var tile_panel := main_scene.find_child("TileInfoPanel", true, false)
	return {
		"schema": 1,
		"unix_time": Time.get_unix_time_from_system(),
		"turns_requested": turns,
		"turns_completed": _turn_ms.size(),
		"scene_load_resource_ms": scene_load_ms,
		"scene_instantiate_ready_ms": scene_ready_ms,
		"turn_wall_ms": stats,
		"current_turn": int(turn_manager.current_turn),
		"money": float(match_state.money),
		"building_count": match_state.buildings.size(),
		"pending_shipments": match_state.pending_transport_shipments.size(),
		"catalog_goods": catalog.all_goods().size(),
		"catalog_buildings": catalog.all_buildings().size(),
		"catalog_recipes": catalog.all_recipes().size(),
		"default_bottom_menu_alt": bool(match_state.use_alt_bottom_menu),
		"tile_panel_present": tile_panel != null,
	}


func _stats(values: Array) -> Dictionary:
	if values.is_empty():
		return {
			"count": 0,
			"mean": 0.0,
			"median": 0.0,
			"p95": 0.0,
			"max": 0.0,
		}
	var sorted := values.duplicate()
	sorted.sort()
	var sum := 0.0
	for v in sorted:
		sum += float(v)
	var n := sorted.size()
	var p95_idx := clampi(int(ceil(float(n) * 0.95)) - 1, 0, n - 1)
	return {
		"count": n,
		"mean": sum / float(n),
		"median": float(sorted[int(n / 2)]),
		"p95": float(sorted[p95_idx]),
		"max": float(sorted[n - 1]),
	}


func _write_json(data: Dictionary) -> void:
	var f := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if f == null:
		_fail("Could not write %s" % OUTPUT_PATH)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	print("[phase0] wrote %s" % OUTPUT_PATH)


func _print_report(data: Dictionary) -> void:
	var turn_wall: Dictionary = data.get("turn_wall_ms", {})
	print("[phase0] scene_load_resource_ms=%.2f scene_instantiate_ready_ms=%.2f" % [
		float(data.get("scene_load_resource_ms", 0.0)),
		float(data.get("scene_instantiate_ready_ms", 0.0)),
	])
	print("[phase0] turns=%d mean=%.2fms median=%.2fms p95=%.2fms max=%.2fms" % [
		int(turn_wall.get("count", 0)),
		float(turn_wall.get("mean", 0.0)),
		float(turn_wall.get("median", 0.0)),
		float(turn_wall.get("p95", 0.0)),
		float(turn_wall.get("max", 0.0)),
	])
	print("[phase0] buildings=%d pending_shipments=%d money=%.2f bottom_menu_alt=%s" % [
		int(data.get("building_count", 0)),
		int(data.get("pending_shipments", 0)),
		float(data.get("money", 0.0)),
		str(data.get("default_bottom_menu_alt", false)),
	])


func _elapsed_ms(start_usec: int) -> float:
	return float(Time.get_ticks_usec() - start_usec) / 1000.0


func _fail(message: String) -> void:
	printerr("[phase0] ERROR: " + message)
	quit(1)
