extends Node
## Close captures of the supply chain board's roads in a Metal Magnate game, at the view's closest
## zoom: the town streets of a few tiles, corners and junctions, a road running up a slope, and a car
## passing behind a building.
##   AGENT_GODOT_WINDOW=1 godot --path . res://tools/supply_board_roads_shot.tscn -- --no-telemetry
## Writes roads_<name>.png (the whole view) and roads_<name>_crop.png (round the subject) into
## $SB_SHOT_DIR (or /tmp).

const ShotHarness := preload("res://tools/shot_harness.gd")
const Pipes := preload("res://scripts/empire_board_pipes.gd")
const START := "res://data/starts/metal_magnate.json"
const ZOOM := 1.5
const TOWNS := ["tile_7_11", "tile_8_5", "tile_9_9"]
const CROP := Vector2(560.0, 360.0)           # the crop round a subject, in view units
const FAR_WORKS := ["tile_10_8", "tile_10_6", "tile_8_4", "tile_12_9"]
const FAR_MOVES := [["tile_9_9", "tile_12_9"], ["tile_6_8", "tile_8_4"]]

var _out := "/tmp"
var _board: Control


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
	# Works on high ground and moves out to them, as the relief captures have, so the streets of more
	# towns and the roads up the hills come onto the board.
	for i in range(FAR_WORKS.size()):
		BuildingState.add_building("b_001", "r_001", str(FAR_WORKS[i]), "player_1", "roads_shot_%d" % i)
	var good := str(Catalog.get_recipe("r_001").get("outputs", [{}])[0].get("good_id", ""))
	for mv in FAR_MOVES:
		TransportState.recurring_moves.append({"source": str(mv[0]), "dest": str(mv[1]), "goods": {good: 1}})
	var view: Node = main.find_child("EmpireView", true, false)
	view.call("toggle")
	await _settle(30)
	await get_tree().create_timer(3.0).timeout
	_board = view.find_child("Board", true, false)
	await ShotHarness.await_board_baked(self, _board)
	var model: Dictionary = _board.get("_model")
	var tiles: Dictionary = model.get("tiles", {})
	var roads: Array = model.get("roads", [])
	# The town streets.
	for tid in TOWNS:
		var sum := Vector2.ZERO
		var n := 0
		for r in roads:
			if str(r["tile"]) == tid:
				sum += (r["a"] as Vector2) + (r["b"] as Vector2)
				n += 2
		if n > 0:
			await _frame("town_" + str(tid).trim_prefix("tile_"), sum / float(n), tid)
	# Where roads meet: a corner is two arms that turn, a junction three or more.
	var nodes: Dictionary = {}
	for r in roads:
		for e in [[r["a"], r["b"]], [r["b"], r["a"]]]:
			var here: Vector2 = e[0]
			var nd: Dictionary = nodes.get_or_add(Vector2i(here.round()), {"p": here, "tile": str(r["tile"]), "ks": {}})
			(nd["ks"] as Dictionary)[Pipes.k_of((e[1] as Vector2) - here)] = true
	var corners: Array = []
	var junctions: Array = []
	for key in nodes:
		var nd: Dictionary = nodes[key]
		var ks: Array = (nd["ks"] as Dictionary).keys()
		if ks.size() == 2 and posmod(int(ks[0]) - int(ks[1]), 12) != 6:
			corners.append(nd)
		elif ks.size() >= 3:
			junctions.append(nd)
	var by_town := func(x: Dictionary, y: Dictionary) -> bool:
		return TOWNS.has(x["tile"]) and not TOWNS.has(y["tile"])
	corners.sort_custom(by_town)
	junctions.sort_custom(by_town)
	for i in range(mini(4, corners.size())):
		await _frame("corner_%d" % i, corners[i]["p"], str(corners[i]["tile"]))
	for i in range(mini(3, junctions.size())):
		await _frame("junction_%d" % i, junctions[i]["p"], str(junctions[i]["tile"]))
	# Roads up a slope: the stretches that climb most.
	var ramps: Array = []
	for r in roads:
		var prof: Array = _board.call("_profile", r["a"], r["b"], str(r["tile"]))
		var lo := INF
		var hi := -INF
		for q in prof:
			lo = minf(lo, float(q[1]))
			hi = maxf(hi, float(q[1]))
		if hi - lo > 2.0:
			ramps.append({"rise": hi - lo, "p": (r["a"] as Vector2).lerp(r["b"], 0.5), "tile": str(r["tile"])})
	ramps.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["rise"]) > float(y["rise"]))
	print("[roads_shot] %d roads, %d corners, %d junctions, %d ramps" % [roads.size(), corners.size(), junctions.size(), ramps.size()])
	for i in range(mini(3, ramps.size())):
		await _frame("ramp_%d" % i, ramps[i]["p"], str(ramps[i]["tile"]))
	await _car_behind(tiles)
	get_tree().quit()


## Frame a plan point at the closest zoom, wait for its bakes, and capture.
func _frame(name: String, p: Vector2, tile: String) -> void:
	var tiles: Dictionary = (_board.get("_model") as Dictionary)["tiles"]
	var at: Vector2 = _board.call("iso", p, float(tiles[tile]["height"]))
	_board.set("_zoom", ZOOM)
	_board.set("_offset", _board.size * 0.5 - at * ZOOM)
	_board.call("_view_changed")
	await _settle(10)
	await get_tree().create_timer(3.0).timeout
	await ShotHarness.await_board_baked(self, _board)
	await _shot(name, _board.size * 0.5)


## A car passing behind a building: the first car whose way runs behind a building's sprite, the
## clock set to put it there, captured as it goes in, behind, and as it comes out.
func _car_behind(_tiles: Dictionary) -> void:
	var cars: Array = _board.get("_cars")
	var standing: Array = _board.get("_standing")
	for c in cars:
		var pts: PackedVector2Array = c["pts"]
		var shares: PackedFloat32Array = c["shares"]
		for k in range(1, 100):
			var t := float(k) / 100.0
			var at := _car_at(pts, shares, t)
			for s in standing:
				if str(s["kind"]) == "pylon" or s.get("sprite") == null:
					continue
				var r: Rect2 = s.get("tex_rect", s["rect"])
				var foot: Vector2 = _board.call("iso", s["pos"], float(s["h"]))
				# Behind it: within its sprite, over the middle of it, and further back than its foot.
				if not r.has_point(at) or absf(at.x - r.get_center().x) > r.size.x * 0.2 or at.y > foot.y - 4.0:
					continue
				_board.set("_zoom", ZOOM)
				_board.set("_offset", _board.size * 0.5 - foot * ZOOM)
				_board.call("_view_changed")
				await _settle(10)
				await get_tree().create_timer(3.0).timeout
				await ShotHarness.await_board_baked(self, _board)
				print("[roads_shot] car behind %s %s" % [s["kind"], s["iid"]])
				var step := 6.0 / float(c["length"])
				for frame in [["in", -step], ["behind", 0.0], ["out", step]]:
					var when := t + float(frame[1])
					_board.set("_clock", (when - float(c["phase"]) + 2.0) * float(c["length"]) / float(c["pace"]))
					for layer in _board.get_children():
						if layer is CanvasItem:
							(layer as CanvasItem).queue_redraw()
					await _shot("car_" + str(frame[0]), _board.size * 0.5)
				return
	print("[roads_shot] no car passes behind a building")


func _car_at(pts: PackedVector2Array, shares: PackedFloat32Array, t: float) -> Vector2:
	var k := 0
	while k < shares.size() - 2 and shares[k + 1] < t:
		k += 1
	return pts[k].lerp(pts[k + 1], clampf((t - shares[k]) / maxf(shares[k + 1] - shares[k], 0.0001), 0.0, 1.0))


func _shot(name: String, centre: Vector2) -> void:
	RenderingServer.force_draw(false)
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out.path_join("roads_%s.png" % name))
	var scale := float(img.get_width()) / get_viewport().get_visible_rect().size.x
	var box := Rect2i(Vector2i(((centre - CROP * 0.5) * scale).round()), Vector2i((CROP * scale).round()))
	img.get_region(box.intersection(Rect2i(Vector2i.ZERO, img.get_size()))).save_png(_out.path_join("roads_%s_crop.png" % name))
	print("[roads_shot] wrote ", _out.path_join("roads_%s.png" % name))
	await get_tree().process_frame


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
