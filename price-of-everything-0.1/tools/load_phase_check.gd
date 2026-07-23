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
	w.set_script(preload("res://tools/load_phase_watcher.gd"))
	get_tree().root.add_child(w)        # survives the change_scene
	screen.begin_load(SaveLoad.MAIN_SCENE)
