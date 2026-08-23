extends Node
## Does anything STALL after the player clicks Begin?
##
##     <godot> --path . res://tools/begin_click_probe.tscn --quit-after 60000
##     BEGIN_SHOT=<dir>   also save the panel before the click and the map after it
##
## The load was made fast by moving work out of the way of the film — panels built lazily,
## the world painted then hidden, hill meshes warmed post-Begin. All of that has to land
## SOMEWHERE, and the only place left is the click. This presses Begin the moment it is
## offered and then times every frame for POST_SECS, in wall clock.
##
## WALL CLOCK, not `delta`: delta is clamped while the main thread is blocked, so a stall is
## exactly the thing it cannot report. A 900 ms freeze shows up as a 900 ms gap here and as
## about 100 ms of delta.
##
## The sampler lives on the tree ROOT because pressing Begin frees the loading screen and,
## a second later, this node's own scene.

const LoadingScreenScript := preload("res://scripts/loading_screen.gd")


func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	await get_tree().process_frame
	SaveLoad.prepare_new_game("res://data/starts/coal_baron.json")
	var screen: Node = LoadingScreenScript.show_global(get_tree())
	var probe := Node.new()
	probe.name = "BeginClickProbe"
	probe.set_script(preload("res://tools/begin_click_sampler.gd"))
	probe.set("screen", screen)
	get_tree().root.add_child(probe)
	screen.begin_load(SaveLoad.MAIN_SCENE)
