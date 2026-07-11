extends Node
## Verification shots #2: the construct panel under a search query (only matching
## recipes may list under each building) and a power-building row (recipe diagram
## must use the tile-panel lightning icon for the power output).
##   <godot> --path . res://tools/bugfix_shot2.tscn --quit-after 2500

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
	var cp := get_tree().root.find_child("ConstructPanel", true, false)
	if cp == null:
		print("[SHOT] ConstructPanel not found")
		get_tree().quit(1)
		return
	cp.show()
	for _i in 4:
		await get_tree().process_frame
	cp.search_input.text = "steel"
	cp._search_query = "steel"
	cp._build_panel_content()
	for _i in 4:
		await get_tree().process_frame
	_capture("bugfix_shot_search_steel.png")

	cp.search_input.text = "power"
	cp._search_query = "power"
	cp._build_panel_content()
	for _i in 4:
		await get_tree().process_frame
	_capture("bugfix_shot_search_power.png")
	get_tree().quit(0)


func _capture(fname: String) -> void:
	var out := ProjectSettings.globalize_path("res://" + fname)
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
