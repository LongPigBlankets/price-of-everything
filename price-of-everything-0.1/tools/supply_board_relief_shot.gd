extends Node
## Close captures of the supply chain board's relief in a Metal Magnate game: the seams where tiles
## of different kinds or heights meet, the edges rivers cross, and the bridges over rivers' valleys.
##   AGENT_GODOT_WINDOW=1 godot --path . res://tools/supply_board_relief_shot.tscn -- --no-telemetry
## Writes relief_<phase>_board.png, relief_<phase>_<tile>_<tile>.png and relief_<phase>_bridge_<tile>_<n>.png
## into $SB_SHOT_DIR (or /tmp).
##
## Phase "start" is the opening board. Phase "far" adds works on high ground and a standing move
## out to it, so hill and mountain tiles, and tiles the goods only pass through, come onto the board.

const ShotHarness := preload("res://tools/shot_harness.gd")
const START := "res://data/starts/metal_magnate.json"
const ZOOM := 1.2
const MAX_SEAMS := 16
const MAX_BRIDGES := 4
## Works stood on high ground and by rivers for the second phase, and the moves that reach them.
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
	await _phase(view, "start")
	for i in range(FAR_WORKS.size()):
		BuildingState.add_building("b_001", "r_001", str(FAR_WORKS[i]), "player_1", "relief_shot_%d" % i)
	var good := str(Catalog.get_recipe("r_001").get("outputs", [{}])[0].get("good_id", ""))
	for mv in FAR_MOVES:
		TransportState.recurring_moves.append({"source": str(mv[0]), "dest": str(mv[1]), "goods": {good: 1}})
	await _phase(view, "far")
	get_tree().quit()


func _phase(view: Node, phase: String) -> void:
	view.call("toggle")
	await _settle(30)
	(view.find_child("Board", true, false) as Control).call("fit_view")
	# A covered window draws no frames, so the tile bakes stall and the board shows after its time limit.
	await get_tree().create_timer(3.0).timeout
	await _shot("%s_board" % phase)
	var board: Control = view.find_child("Board", true, false)
	var model: Dictionary = board.get("_model")
	var tiles: Dictionary = model.get("tiles", {})
	var rivers: Dictionary = board.get("_rivers")
	var ids: Array = tiles.keys()
	ids.sort()
	for tid in ids:
		var t: Dictionary = tiles[tid]
		print("[relief_shot] %s %s %s height %.0f store %s rivers %d" % [phase, tid, t["type"], float(t["height"]),
			t["store"], (rivers.get(tid, []) as Array).size()])
	# Shared edges worth a close look: where a river crosses, or the two tiles differ.
	var seams: Array = []
	for a in ids:
		for b in ids:
			if str(a) >= str(b):
				continue
			var ca: Vector2 = tiles[a]["center"]
			var cb: Vector2 = tiles[b]["center"]
			if ca.distance_to(cb) > 500.0:
				continue
			var mid := (ca + cb) * 0.5
			var crossed := false
			for tile in [a, b]:
				for line in rivers.get(tile, []):
					for p in line:
						crossed = crossed or (p as Vector2).distance_to(mid) < 140.0
			var differ := str(tiles[a]["type"]) != str(tiles[b]["type"]) \
				or absf(float(tiles[a]["height"]) - float(tiles[b]["height"])) > 0.5
			if crossed or differ:
				seams.append([a, b, mid, crossed])
	for s in seams.slice(0, MAX_SEAMS):
		var a := str(s[0])
		var b := str(s[1])
		var h := (float(tiles[a]["height"]) + float(tiles[b]["height"])) * 0.5
		var at: Vector2 = board.call("iso", s[2], h)
		board.set("_zoom", ZOOM)
		board.set("_offset", board.size * 0.5 - at * ZOOM)
		board.call("_view_changed")
		await _settle(4)
		await get_tree().create_timer(1.0).timeout
		print("[relief_shot] %s seam %s %s (%.0f) | %s %s (%.0f) river %s" % [phase, a, tiles[a]["type"],
			float(tiles[a]["height"]), b, tiles[b]["type"], float(tiles[b]["height"]), s[3]])
		await _shot("%s_%s_%s" % [phase, a.trim_prefix("tile_"), b.trim_prefix("tile_")])
	# Every bridge a way crosses a river's valley on.
	var spans: Dictionary = board.get("_spans")
	var bridges := 0
	for tile in spans:
		for span in spans[tile]:
			if not bool(span["used"]) or bridges >= MAX_BRIDGES:
				continue
			bridges += 1
			var at: Vector2 = board.call("iso", span["at"], float(span["deck"]))
			board.set("_zoom", ZOOM * 1.5)
			board.set("_offset", board.size * 0.5 - at * ZOOM * 1.5)
			board.call("_view_changed")
			await _settle(4)
			await get_tree().create_timer(1.0).timeout
			print("[relief_shot] %s bridge on %s at %s deck %.1f" % [phase, tile, span["at"], float(span["deck"])])
			await _shot("%s_bridge_%s_%d" % [phase, str(tile).trim_prefix("tile_"), bridges])
	view.call("toggle")
	await _settle(20)


func _shot(name: String) -> void:
	RenderingServer.force_draw(false)
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out.path_join("relief_%s.png" % name))
	await get_tree().process_frame


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
