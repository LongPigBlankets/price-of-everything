extends Node

# Tracks whether the player is currently selecting a tile to build on,
# and which building they intend to place. When a tile is clicked while
# active, build_completed fires and mode auto-clears.

signal mode_entered(building_id: String)
signal mode_exited
signal build_attempted(building_id: String, tile_id: String)

var is_active: bool = false
var current_building_id: String = ""

func enter_build_mode(building_id: String) -> void:
	if building_id == "":
		return
	is_active = true
	current_building_id = building_id
	mode_entered.emit(building_id)
	print("Build mode entered for: ", building_id)

func exit_build_mode() -> void:
	if not is_active:
		return
	var was_building := current_building_id
	is_active = false
	current_building_id = ""
	mode_exited.emit()
	print("Build mode exited (was: ", was_building, ")")

func attempt_build(tile_id: String) -> void:
	if not is_active:
		return
	build_attempted.emit(current_building_id, tile_id)
	# For now: stay in build mode after each placement so the player can
	# place multiple of the same building. Right-click exits.
	# Change to exit_build_mode() here if you want one-and-done behavior.
