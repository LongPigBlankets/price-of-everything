extends Node
## Captures of Local Suppliers' depot on the supply chain board in a Metal Magnate game: the white warehouse, its
## hover card, and its panel showing the buildings' outputs, then their inputs.
##   AGENT_GODOT_WINDOW=1 godot --path . res://tools/local_suppliers_shot.tscn --quit-after 100000 -- --no-telemetry
## Writes local_suppliers_<view>.png into $SUPPLIERS_SHOT_DIR (or /tmp).

const ShotHarness := preload("res://tools/shot_harness.gd")
const START := "res://data/starts/metal_magnate.json"

var _out := "/tmp"


func _ready() -> void:
	var dir := OS.get_environment("SUPPLIERS_SHOT_DIR")
	if dir != "":
		_out = dir
	DirAccess.make_dir_recursive_absolute(_out)
	ShotHarness.arm_watchdog(self, 180.0)
	ShotHarness.prepare_window(get_window(), Vector2i(1920, 1080))
	TelemetryState.enabled = false
	SaveLoad.autosave_enabled = false
	AudioServer.set_bus_mute(0, true)
	SaveLoad.prepare_new_game(START)
	var world: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	await get_tree().process_frame
	get_tree().current_scene = world
	await _settle(200)
	MatchState.ruleset["opener_done"] = true
	Tutorial._on_overlay_skipped()
	DecisionState.enabled = false
	for layer in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var sc := (layer as Node).get_script() as Script
		if sc != null and sc.resource_path.ends_with("_intro.gd"):
			layer.queue_free()
	await _settle(30)
	var ev: Node = world.find_child("EmpireView", true, false)
	ev.call("toggle")
	await _settle(90)
	var board: Control = ev.get_node("Board")
	var depot: Dictionary = {}
	for st in (board.get("_standing") as Array):
		if str((st as Dictionary).get("kind", "")) == "suppliers":
			depot = st
			break
	print("[suppliers_shot] depot: %s" % str(depot.get("iid", "none")))
	var model: Dictionary = board.get("_model")
	for f in model.get("flows", []):
		var pts: Array = (f as Dictionary).get("pts", [])
		if pts.is_empty():
			continue
		var ends := [(pts[0] as Dictionary)["p"], (pts[pts.size() - 1] as Dictionary)["p"]]
		for e in ends:
			if (e as Vector2).distance_to(depot["pos"]) < 200.0:
				print("[suppliers_shot] flow at depot: ", f["good"], " ", f["kind"], " pts ", pts.size())
	if depot.is_empty():
		get_tree().quit(1)
		return
	var zoom := 0.9
	board.set("_zoom", zoom)
	board.set("_offset", board.size * 0.5 - (depot["rect"] as Rect2).get_center() * zoom)
	board.call("_view_changed")
	await _wait(1.5)
	await _shot("board")
	board.call("_set_hover", depot)
	await _settle(4)
	await _shot("hover")
	board.call("_set_hover", {})
	board.call("_click", (depot["rect"] as Rect2).get_center() * zoom + (board.get("_offset") as Vector2))
	await _settle(8)
	await _shot("outputs")
	var panel: Node = get_tree().root.find_child("LocalSuppliersPanel", true, false)
	if panel != null:
		panel.call("_show", "input")
	await _settle(6)
	await _shot("inputs")
	get_tree().quit()


func _shot(name: String) -> void:
	RenderingServer.force_draw(false)
	get_viewport().get_texture().get_image().save_png(_out.path_join("local_suppliers_%s.png" % name))
	await get_tree().process_frame


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
