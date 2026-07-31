extends Node
## Windowed dev shot: boots the REAL tutorial and samples the coach overlay across a step
## transition, to verify the 1s settle (dim fades up, spotlight travels to its target)
## rather than the old hard cut.
##   <godot> --path . res://tools/coach_settle_shot.tscn --quit-after 3000
## Writes /tmp/poe_coach_<phase>_<nn>.png and prints reveal + the drawn hole per sample.
##
## Follows tutorial_shot.gd exactly: a root-parented capper that survives the scene change
## and captures from _process. Capturing from a coroutine in a tool that holds main.tscn as
## a CHILD returns the same frozen frame every time — every shot came back byte-identical.

const Capper := preload("res://tools/coach_settle_capper.gd")

func _ready() -> void:
	get_window().size = Vector2i(1920, 1080)
	var cap := Capper.new()
	get_tree().root.add_child.call_deferred(cap)
	SaveLoad.prepare_new_game("res://data/starts/tutorial.json")
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
