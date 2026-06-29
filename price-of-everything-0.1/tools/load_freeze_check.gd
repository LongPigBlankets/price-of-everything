extends Node
## Measure the loading-screen freeze on a real new-game load (the normal path).
##   <godot> --path . res://tools/load_freeze_check.tscn --quit-after 3500
const LoadingScreenScript := preload("res://scripts/loading_screen.gd")
func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	await get_tree().process_frame
	SaveLoad.prepare_new_game("res://data/starts/coal_baron.json")
	var screen: Node = LoadingScreenScript.show_global(get_tree())
	var w := Node.new()
	w.set_script(preload("res://tools/load_freeze_watcher.gd"))
	get_tree().root.add_child(w)        # survives the change_scene
	screen.begin_load(SaveLoad.MAIN_SCENE)
