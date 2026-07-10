extends Node
## Windowed shots for the warehousing-fee batch: (1) the bottom-right turn summary
## expanded with the new Warehousing cost row, (2) the research panel's Logistics
## tab with the Just-in-Time Logistics node.
##   <godot> --path . res://tools/warehousing_shot.tscn --quit-after 4000

const MAIN_SCENE := "res://scenes/main.tscn"

var _main: Node = null
var _started := false
var _frames := 0


func _ready() -> void:
	var packed := load(MAIN_SCENE) as PackedScene
	_main = packed.instantiate()
	add_child(_main)


func _process(_dt: float) -> void:
	if _started:
		return
	_frames += 1
	if _main != null and _main.get("build_complete") == true:
		_started = true
		_run()
	elif _frames > 3000:
		get_tree().quit(1)


func _run() -> void:
	var cam := get_tree().get_first_node_in_group("camera")
	if cam != null:
		cam.set("edge_pan_enabled", false)
	# Stored goods so the fee is non-zero: 100 steel (0.01) + 20 acids (0.1) = £3.00.
	Stockpile.add("tile_16_4", "g_006", 100)
	Stockpile.add("tile_16_4", "g_065", 20)
	MatchState.money = 5000.0
	TurnManager.commit_turn()
	await TurnManager.turn_resolution_completed
	for _i in 8:
		await get_tree().process_frame
	_capture("warehousing_turn_summary.png")
	# Research panel: Logistics tab with the JIT node.
	var rp := get_tree().current_scene.find_child("ResearchPanel", true, false)
	if rp != null:
		rp.visible = true
		rp.set("_selected_category", "Logistics")
		rp.queue_redraw()
		for _i in 8:
			await get_tree().process_frame
		_capture("warehousing_research_jit.png")
	get_tree().quit(0)


func _capture(fname: String) -> void:
	var out := ProjectSettings.globalize_path("res://" + fname)
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
