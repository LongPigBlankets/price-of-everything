extends Node
## Does the loading film actually PLAY while the game loads underneath it?
##
##     <godot> --path . res://tools/loading_film_check.tscn --quit-after 40000
##     FILM_SHOT=<path>.png   also save a frame mid-load, to eyeball the composition
##
## This half just starts a real new game with the real loading screen. The sampling lives in
## loading_film_sampler.gd, parented to the tree ROOT, because begin_load swaps the current
## scene out and frees everything in it — this node included, and the scene change is exactly
## the moment worth watching.

const LoadingScreenScript := preload("res://scripts/loading_screen.gd")


func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	await get_tree().process_frame
	SaveLoad.prepare_new_game("res://data/starts/coal_baron.json")
	var screen: Node = LoadingScreenScript.show_global(get_tree())
	var sampler := Node.new()
	sampler.name = "LoadingFilmSampler"
	sampler.set_script(preload("res://tools/loading_film_sampler.gd"))
	sampler.set("screen", screen)
	get_tree().root.add_child(sampler)
	screen.begin_load(SaveLoad.MAIN_SCENE)
