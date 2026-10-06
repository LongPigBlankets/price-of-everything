extends Node
## Close captures of the supply chain board's coastal tiles in a Metal Magnate game: where rivers
## run into the sea, and the streets and buildings by the shore.
##   AGENT_GODOT_WINDOW=1 godot --path . res://tools/supply_board_coast_shot.tscn -- --no-telemetry
## Writes coast_board.png and coast_<tile>.png (phase "start"), coast_far_board.png and
## coast_far_<tile>.png (phase "far") into $SB_SHOT_DIR (or /tmp), and prints for each coastal tile
## what stands on it and anything on the water.
##
## Phase "start" is the opening board. Phase "far" adds works on high ground and moves out to them,
## as the relief captures do, so more tiles come onto the board.

const ShotHarness := preload("res://tools/shot_harness.gd")
const Ground := preload("res://scripts/empire_board_ground.gd")
const START := "res://data/starts/metal_magnate.json"
const ZOOM := 1.6
const FAR_WORKS := ["tile_10_8", "tile_10_6", "tile_8_4", "tile_12_9"]
const FAR_MOVES := [["tile_9_9", "tile_12_9"], ["tile_6_8", "tile_8_4"]]

var _out := "/tmp"


func _ready() -> void:
	var dir := OS.get_environment("SB_SHOT_DIR")
	if dir != "":
		_out = dir
	DirAccess.make_dir_recursive_absolute(_out)
	ShotHarness.arm_watchdog(self, 300.0)
	ShotHarness.prepare_window(get_window(), Vector2i(1920, 1080))
	TelemetryState.enabled = false
	SaveLoad.autosave_enabled = false
	AudioServer.set_bus_mute(0, true)
	SaveLoad.prepare_new_game(START)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	get_tree().current_scene = main
	await _settle(200)
	MatchState.ruleset["opener_done"] = true
	Tutorial._on_overlay_skipped()
	DecisionState.enabled = false
	for layer in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var sc := (layer as Node).get_script() as Script
		if sc != null and sc.resource_path.ends_with("_intro.gd"):
			layer.queue_free()
	await _settle(20)
	var view: Node = main.find_child("EmpireView", true, false)
	await _phase(view, "")
	for i in range(FAR_WORKS.size()):
		BuildingState.add_building("b_001", "r_001", str(FAR_WORKS[i]), "player_1", "coast_shot_%d" % i)
	var good := str(Catalog.get_recipe("r_001").get("outputs", [{}])[0].get("good_id", ""))
	for mv in FAR_MOVES:
		TransportState.recurring_moves.append({"source": str(mv[0]), "dest": str(mv[1]), "goods": {good: 1}})
	await _phase(view, "far_")
	get_tree().quit()


func _phase(view: Node, prefix: String) -> void:
	view.call("toggle")
	await _settle(30)
	# A covered window draws no frames, so the tile bakes stall and the board shows after its time limit.
	await get_tree().create_timer(3.0).timeout
	var board: Control = view.find_child("Board", true, false)
	await ShotHarness.await_board_baked(self, board)
	await _shot(prefix + "board")
	var model: Dictionary = board.get("_model")
	var tiles: Dictionary = model.get("tiles", {})
	var coast: Array = []
	for tid in tiles:
		var t: Dictionary = tiles[tid]
		if str(t["type"]) in ["sea", "deep_sea"]:
			continue
		var rel: Dictionary = board.call("_relief_of", str(tid), t["center"])
		if (rel.get("sea", []) as Array).is_empty():
			continue
		coast.append(str(tid))
		var wet := 0
		var counts := {"house": 0, "works": 0, "other": 0, "streets": 0, "shore": 0}
		for s in model.get("standing", []):
			if str(s["tile"]) != str(tid):
				continue
			match str(s["kind"]):
				"house":
					counts["house"] += 1
				"building", "site":
					counts["works"] += 1
				_:
					counts["other"] += 1
			# Its footprint, edge and inside.
			var half := float(s["side"]) * 0.5
			var over := false
			for gx in range(-4, 5):
				for gy in range(-4, 5):
					over = over or Ground.is_water(rel, (s["pos"] as Vector2) + Vector2(gx, gy) * half * 0.25)
			if over:
				wet += 1
				print("[coast_shot] %s%s %s %s stands on water at %s" % [prefix, tid, s["kind"], s["iid"], (s["pos"] as Vector2) - (t["center"] as Vector2)])
		for r in model.get("roads", []):
			if str(r["tile"]) != str(tid):
				continue
			counts["streets"] += 1
			if str(r["kind"]) == "shore":
				counts["shore"] += 1
			var steps := maxi(1, ceili((r["a"] as Vector2).distance_to(r["b"]) / 3.0))
			for k in range(steps + 1):
				var p: Vector2 = (r["a"] as Vector2).lerp(r["b"], float(k) / float(steps))
				if Ground.is_water(rel, p):
					wet += 1
					print("[coast_shot] %s%s road %s on water at %s" % [prefix, tid, r["kind"], p - (t["center"] as Vector2)])
					break
		print("[coast_shot] %scoastal %s (%s) rivers %d, %d houses, %d works, %d other, %d streets (%d shore), %d things on water"
			% [prefix, tid, t["label"], ((board.get("_rivers") as Dictionary).get(tid, []) as Array).size(),
				counts["house"], counts["works"], counts["other"], counts["streets"], counts["shore"], wet])
	for tid in coast:
		var at: Vector2 = board.call("iso", tiles[tid]["center"], float(tiles[tid]["height"]))
		board.set("_zoom", ZOOM)
		board.set("_offset", board.size * 0.5 - at * ZOOM)
		board.call("_view_changed")
		await _settle(10)
		await get_tree().create_timer(3.0).timeout
		await ShotHarness.await_board_baked(self, board)
		await _shot(prefix + str(tid))
	view.call("toggle")
	await _settle(10)


func _shot(name: String) -> void:
	RenderingServer.force_draw(false)
	get_viewport().get_texture().get_image().save_png(_out.path_join("coast_%s.png" % name))
	print("[coast_shot] wrote ", _out.path_join("coast_%s.png" % name))
	await get_tree().process_frame


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
