extends Control

## Title screen: a black backdrop with a single New Game button that drops the
## player into the map (which used to be the landing scene). The goods board on
## the right runs its own slide animation + cue (see goods_grid.gd).

const MAP_SCENE := "res://scenes/main.tscn"

@onready var new_game_button: Button = $NewGameButton


func _ready() -> void:
	new_game_button.pressed.connect(_on_new_game_pressed)


func _on_new_game_pressed() -> void:
	get_tree().change_scene_to_file(MAP_SCENE)
