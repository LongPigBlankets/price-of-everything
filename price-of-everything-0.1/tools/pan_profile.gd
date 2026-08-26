extends Node
## Kick off a real windowed new-game load with the pan profiler attached.
##
## The profiler itself lives on a node parented to the ROOT, not to this scene: begin_load
## calls change_scene, which frees the current scene -- this node -- and a profiler that goes
## with it never samples a single play frame. See tools/pan_profile_watcher.gd.
##
##   <godot> --path . res://tools/pan_profile.tscn --quit-after 200000

const LoadingScreenScript := preload("res://scripts/loading_screen.gd")


func _ready() -> void:
	var w := int(_env("PAN_W", "1920"))
	var h := int(_env("PAN_H", "1080"))
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(w, h)
	get_window().position = Vector2i(20, 20)
	await get_tree().process_frame
	var prof := Node.new()
	# DRAW_SWEEP=1 swaps the frame-anatomy watcher for the per-node draw-call sweep: same
	# boot, same world, a different question asked of it.
	if OS.get_environment("DRAW_SWEEP") != "":
		prof.name = "DrawSweepWatcher"
		prof.set_script(preload("res://tools/draw_sweep_watcher.gd"))
	else:
		prof.name = "PanProfileWatcher"
		prof.set_script(preload("res://tools/pan_profile_watcher.gd"))
	get_tree().root.add_child(prof)   # survives the change_scene
	SaveLoad.prepare_new_game("res://data/starts/coal_baron.json")
	var screen: Node = LoadingScreenScript.show_global(get_tree())
	screen.begin_load(SaveLoad.MAIN_SCENE)


func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d
