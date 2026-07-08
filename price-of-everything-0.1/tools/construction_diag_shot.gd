extends Node
## Windowed shot of the NEW construction-site delivery diagnostics row. Boots the tutorial
## start, places a stalled Chemical Plant (b_012) build on tile_5_8 — an unpiped tile whose
## hazard-liquid build material (industrial_acids) can never arrive — opens that project's
## Building Detail panel, and screenshots the "No reinforced pipeline to deliver …" row.
##   <godot> --path . res://tools/construction_diag_shot.tscn --quit-after 2500

const MAIN_SCENE := "res://scenes/main.tscn"
const TUTORIAL_START := "res://data/starts/tutorial.json"

var _main: Node = null
var _started := false
var _shot := false
var _frames := 0


func _ready() -> void:
	SaveLoad.prepare_new_game(TUTORIAL_START)
	var packed := load(MAIN_SCENE) as PackedScene
	_main = packed.instantiate()
	add_child(_main)


func _process(_dt: float) -> void:
	if _shot or _started:
		return
	_frames += 1
	if _main != null and _main.get("build_complete") == true:
		_started = true
		_run()
	elif _frames > 3000:
		_capture("timeout")


func _run() -> void:
	var cam := get_tree().get_first_node_in_group("camera")
	if cam != null:
		cam.set("edge_pan_enabled", false)
	# Place a market-sourced chem-plant build on the unpiped tile. Its solids can be ordered,
	# but industrial_acids (hazard_liquid) can't route here — so it stays in missing_materials.
	var iid := Construction.start_awaiting_market("b_012", "r_050", "tile_5_8", 18.0)
	var bdp := get_tree().current_scene.find_child("BuildingDetailPanelV2", true, false)
	if bdp != null and bdp.has_method("show_building"):
		bdp.show_building({
			"instance_id": iid, "building_id": "b_012", "recipe_id": "r_050",
			"tile_id": "tile_5_8", "level": 1,
		})
	for _i in 5:
		await get_tree().process_frame
	_capture("iid=%s bdp=%s" % [iid, str(bdp != null)])


func _capture(tag: String) -> void:
	_shot = true
	var out := ProjectSettings.globalize_path("res://construction_diag_shot.png")
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out, " | ", tag)
	get_tree().quit(0)
