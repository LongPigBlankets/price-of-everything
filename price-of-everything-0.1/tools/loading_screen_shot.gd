extends Node
## Dev tool: render the real LoadingScreen and save its plate while loading and with the Begin key showing,
## each full frame and a close crop of the plate. Windowed:
##   AGENT_GODOT_WINDOW=1 godot --path . res://tools/loading_screen_shot.tscn -- --no-telemetry
## Writes loading_<state>.png and loading_<state>_plate.png into $LOADING_SHOT_DIR (or /tmp).

const LoadingScreenScript := preload("res://scripts/loading_screen.gd")

var _out := "/tmp"


func _ready() -> void:
	var dir := OS.get_environment("LOADING_SHOT_DIR")
	if dir != "":
		_out = dir
	DirAccess.make_dir_recursive_absolute(_out)
	get_window().size = Vector2i(1920, 1080)
	var ls: Node = LoadingScreenScript.new()
	add_child(ls)
	await _settle(12)
	await get_tree().create_timer(1.5).timeout
	_shot(ls, "loading")
	ls.call("_show_begin")
	await get_tree().create_timer(1.5).timeout
	_shot(ls, "begin")
	get_tree().quit(0)


func _shot(ls: Node, state: String) -> void:
	RenderingServer.force_draw(false)
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out.path_join("loading_%s.png" % state))
	var plate: Control = ls.get("_plate")
	if plate != null:
		var k := float(img.get_width()) / get_viewport().get_visible_rect().size.x
		var r := Rect2i(plate.get_global_rect().grow(40.0).position * k, plate.get_global_rect().grow(40.0).size * k)
		img.get_region(r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))).save_png(_out.path_join("loading_%s_plate.png" % state))
	print("saved loading_%s" % state)


func _settle(frames: int) -> void:
	for _i in range(frames):
		await get_tree().process_frame
