extends Node
## Windowed dev shot: boot the tutorial start and capture the confined board + the
## coach overlay's first card. NOT --headless:
##   <godot> --path . res://tools/tutorial_shot.tscn --quit-after 2000
##
## A capper node is parented to the tree root (so it survives the scene change to
## main.tscn), waits until world_map.build_complete + the coach overlay settles, then
## saves the PNG and quits.

const Capper := preload("res://tools/tutorial_shot_capper.gd")

func _ready() -> void:
	get_window().size = Vector2i(1920, 1080)
	var cap := Capper.new()
	get_tree().root.add_child.call_deferred(cap)
	SaveLoad.prepare_new_game("res://data/starts/tutorial.json")
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
