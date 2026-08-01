extends Node
const Cap := preload("res://tools/tut_snap_capper.gd")
func _ready() -> void:
	get_window().size = Vector2i(1920, 1080)
	get_tree().root.add_child.call_deferred(Cap.new())
	SaveLoad.prepare_new_game("res://data/starts/tutorial.json")
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
