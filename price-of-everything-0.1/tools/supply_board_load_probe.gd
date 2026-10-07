extends Node
## How the supply chain view fares across a real load: when the world is built, when the view has
## been built and baked behind the loading screen, the worst frame while it was, and how long the
## first Tab takes once "Begin" is pressed.
##
##     AGENT_GODOT_WINDOW=1 <godot> --path . res://tools/supply_board_load_probe.tscn -- --no-telemetry
##     SB_SHOT_DIR=<dir>   also save the board as it first opens
##
## WALL CLOCK throughout: delta is clamped while the main thread is blocked, so a stall is exactly
## what it cannot report. The sampler lives on the tree ROOT, because pressing Begin frees the
## loading screen and the scene this node was loaded with.

const LoadingScreenScript := preload("res://scripts/loading_screen.gd")
const ShotHarness := preload("res://tools/shot_harness.gd")
const START := "res://data/starts/metal_magnate.json"


func _ready() -> void:
	ShotHarness.prepare_window(get_window(), Vector2i(1920, 1080))
	TelemetryState.enabled = false
	AudioServer.set_bus_mute(0, true)
	await get_tree().process_frame
	SaveLoad.prepare_new_game(START)
	var screen: Node = LoadingScreenScript.show_global(get_tree())
	var probe := Node.new()
	probe.name = "SupplyBoardLoadProbe"
	probe.set_script(preload("res://tools/supply_board_load_sampler.gd"))
	probe.set("screen", screen)
	get_tree().root.add_child(probe)
	screen.begin_load(SaveLoad.MAIN_SCENE)
