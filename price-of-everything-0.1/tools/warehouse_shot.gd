extends Node
## Windowed shot of the Stockpile tab's new warehouse-expansion section: first the
## collapsed level row, then the expanded inline confirmation card (materials bill,
## empire-stock vs market cost, pay buttons).
##   <godot> --path . res://tools/warehouse_shot.tscn --quit-after 2500

const MAIN_SCENE := "res://scenes/main.tscn"
const TILE := "tile_16_4"

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
	var td: Dictionary = _main._tile_data_by_id(TILE)
	var panel = _main.info_panel
	panel.show_tile(td)
	panel._select_tab("stock")
	for _i in 6:
		await get_tree().process_frame
	_capture("warehouse_shot_collapsed.png")
	panel._warehouse_expand = true
	panel._refresh_pane("stock")
	for _i in 6:
		await get_tree().process_frame
	_capture("warehouse_shot_expanded.png")
	get_tree().quit(0)


func _capture(fname: String) -> void:
	var out := ProjectSettings.globalize_path("res://" + fname)
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
