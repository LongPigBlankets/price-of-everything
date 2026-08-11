extends Node
## Kick off a real windowed new-game load with the per-second phase watcher attached.
##   <godot> --path . res://tools/load_phase_check.tscn --quit-after 20000
const LoadingScreenScript := preload("res://scripts/loading_screen.gd")
func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	await get_tree().process_frame
	if OS.get_environment("LEGACY_LOAD") != "":
		LoadPacing.legacy_load = true   # exercise the `swap loading_screen` cheat path headlessly
	SaveLoad.prepare_new_game("res://data/starts/coal_baron.json")
	var screen: Node = LoadingScreenScript.show_global(get_tree())
	var w := Node.new()
	# ANATOMY=1 swaps the progress watcher for the frame-anatomy one: same load, but it
	# accounts for the frame (process / render / present) instead of the job.
	if OS.get_environment("ANATOMY") != "":
		w.set_script(preload("res://tools/frame_anatomy_watcher.gd"))
	else:
		w.set_script(preload("res://tools/load_phase_watcher.gd"))
	get_tree().root.add_child(w)        # survives the change_scene
	screen.begin_load(SaveLoad.MAIN_SCENE)
