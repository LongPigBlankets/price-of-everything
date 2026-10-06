extends Node
## Close captures of the supply chain board's coastal tiles in a Metal Magnate game: where rivers
## run into the sea, and the streets and buildings by the shore.
##   AGENT_GODOT_WINDOW=1 godot --path . res://tools/supply_board_coast_shot.tscn -- --no-telemetry
## Writes coast_board.png and coast_<tile>.png into $SB_SHOT_DIR (or /tmp).

const ShotHarness := preload("res://tools/shot_harness.gd")
const Ground := preload("res://scripts/empire_board_ground.gd")
const START := "res://data/starts/metal_magnate.json"
const ZOOM := 1.6

var _out := "/tmp"


func _ready() -> void:
	var dir := OS.get_environment("SB_SHOT_DIR")
	if dir != "":
		_out = dir
	DirAccess.make_dir_recursive_absolute(_out)
	ShotHarness.arm_watchdog(self, 240.0)
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
	view.call("toggle")
	await _settle(30)
	# A covered window draws no frames, so the tile bakes stall and the board shows after its time limit.
	await get_tree().create_timer(3.0).timeout
	var board: Control = view.find_child("Board", true, false)
	await ShotHarness.await_board_baked(self, board)
	await _shot("board")
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
		for s in model.get("standing", []):
			if str(s["tile"]) != str(tid):
				continue
			var half := float(s["side"]) * 0.5
			var over := false
			for gx in range(-2, 3):
				for gy in range(-2, 3):
					over = over or Ground.is_water(rel, (s["pos"] as Vector2) + Vector2(gx, gy) * half * 0.5)
			if over:
				wet += 1
				print("[coast_shot] %s %s %s stands on water at %s" % [tid, s["kind"], s["iid"], (s["pos"] as Vector2) - (t["center"] as Vector2)])
		for r in model.get("roads", []):
			if str(r["tile"]) != str(tid):
				continue
			for k in range(11):
				var p: Vector2 = (r["a"] as Vector2).lerp(r["b"], float(k) / 10.0)
				if Ground.is_water(rel, p):
					wet += 1
					print("[coast_shot] %s road %s on water at %s" % [tid, r["kind"], p - (t["center"] as Vector2)])
					break
		print("[coast_shot] coastal %s (%s) rivers %d, %d things on water" % [tid, t["label"],
			((board.get("_rivers") as Dictionary).get(tid, []) as Array).size(), wet])
	for tid in coast:
		var at: Vector2 = board.call("iso", tiles[tid]["center"], float(tiles[tid]["height"]))
		board.set("_zoom", ZOOM)
		board.set("_offset", board.size * 0.5 - at * ZOOM)
		board.call("_view_changed")
		await _settle(10)
		await get_tree().create_timer(3.0).timeout
		await ShotHarness.await_board_baked(self, board)
		await _shot(tid)
	get_tree().quit()


func _shot(name: String) -> void:
	RenderingServer.force_draw(false)
	get_viewport().get_texture().get_image().save_png(_out.path_join("coast_%s.png" % name))
	print("[coast_shot] wrote ", _out.path_join("coast_%s.png" % name))
	await get_tree().process_frame


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
