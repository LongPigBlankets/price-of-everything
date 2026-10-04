extends Node
## Captures of Local Suppliers' depots in a Metal Magnate game: a depot on the map with its hover card, and its
## panel showing the buildings' outputs, then their inputs.
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
	var depots: Node = world.find_child("LocalSuppliersDepots", true, false)
	var list: Array = depots.get("_depots") if depots != null else []
	print("[suppliers_shot] depots: %d" % list.size())
	if list.is_empty():
		get_tree().quit(1)
		return
	var tile_id := str(list[0].tile_id)
	var cam: Camera2D = get_viewport().get_camera_2d()
	cam.call("_apply_intro_zoom", 0.8)
	cam.global_position = depots.to_global((list[0].rect as Rect2).get_center())
	await _wait(0.6)
	await _shot("map")
	depots.set("_hovered", 0)
	depots.queue_redraw()
	await _settle(4)
	await _shot("hover")
	depots.set("_hovered", -1)
	var panel: Control = preload("res://scripts/local_suppliers_panel.gd").open(world.find_child("HUD", true, false), tile_id)
	await _settle(6)
	await _shot("outputs")
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
