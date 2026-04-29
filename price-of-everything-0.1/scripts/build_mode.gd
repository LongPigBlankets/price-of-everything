extends Node

signal mode_entered(building_id: String, recipe_id: String)
signal mode_exited
signal build_attempted(building_id: String, tile_id: String)

var is_active: bool = false
var current_building_id: String = ""
var current_recipe_id: String = ""

func enter_build_mode(building_id: String, recipe_id: String) -> void:
	if building_id == "" or recipe_id == "":
		return
	is_active = true
	current_building_id = building_id
	current_recipe_id = recipe_id
	mode_entered.emit(building_id, recipe_id)
	print("Build mode entered for %s with recipe %s" % [building_id, recipe_id])

func exit_build_mode() -> void:
	if not is_active:
		return
	var was_building := current_building_id
	is_active = false
	current_building_id = ""
	current_recipe_id = ""
	mode_exited.emit()
	print("Build mode exited (was: %s)" % was_building)

func attempt_build(tile_id: String) -> void:
	if not is_active:
		return
	build_attempted.emit(current_building_id, tile_id)
