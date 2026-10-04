extends Node
## Captures of the Goods Graph in a Metal Magnate game: the whole chart as it opens, a closer view around steel,
## and steel focused.
##   AGENT_GODOT_WINDOW=1 godot --path . res://tools/goods_graph_ds2_shot.tscn --quit-after 100000 -- --no-telemetry
## Writes goods_graph_<view>.png into $GG_SHOT_DIR (or /tmp).

const ShotHarness := preload("res://tools/shot_harness.gd")
const GoodsFlowGraph := preload("res://scripts/goods_flow_graph.gd")
const START := "res://data/starts/metal_magnate.json"
const GOOD := "steel"
## A good whose chain runs on liquids, for the pipes.
const FLUID_GOOD := "ethylene"

var _out := "/tmp"


func _ready() -> void:
	var dir := OS.get_environment("GG_SHOT_DIR")
	if dir != "":
		_out = dir
	DirAccess.make_dir_recursive_absolute(_out)
	ShotHarness.arm_watchdog(self, 180.0)
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
	var view: Node = main.find_child("GoodsGraphView", true, false)
	view.call("toggle")
	await _settle(40)
	var world: Control = view.find_child("GraphWorld", true, false)
	await _shot("overview")
	var anchor: Dictionary = (world.get("_by_id") as Dictionary).get(GOOD, {})
	var zoom := 0.5
	world.set("_view_zoom", zoom)
	world.set("_view_offset", world.size * 0.5 - (anchor.get("pos", Vector2.ZERO) as Vector2) * zoom)
	world.call("queue_redraw")
	await _settle(10)
	await _shot("zoom")
	var node: Dictionary = (world.get("_by_id") as Dictionary).get(GOOD, {})
	var plate: Rect2 = world.call("_tier_plate_rect", Rect2((node["pos"] as Vector2) - (node["half"] as Vector2), (node["half"] as Vector2) * 2.0))
	print("[gg_shot] %s tier plate says: %s" % [GOOD, world.call("_tier_tooltip", GOOD, plate.get_center())])
	world.set("_hover_id", "aluminium")
	world.call("queue_redraw")
	await _settle(4)
	await _shot("hover")
	world.set("_hover_id", "")
	world.call("select_good", GOOD)
	await _settle(80)
	await _shot("focus")
	world.call("_enter_grid", GOOD)
	await _settle(20)
	await _shot("grid")
	world.call("_exit_grid")
	await _settle(6)
	world.call("select_good", FLUID_GOOD)
	await _settle(80)
	await _shot("focus_fluid")
	get_tree().quit()


func _shot(name: String) -> void:
	RenderingServer.force_draw(false)
	get_viewport().get_texture().get_image().save_png(_out.path_join("goods_graph_%s.png" % name))
	await get_tree().process_frame


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
