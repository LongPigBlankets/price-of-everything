extends Node

signal mode_entered(building_id: String, recipe_id: String)
signal mode_exited
signal mode_exited_with_selection(building_id: String, recipe_id: String, infra_type: String, return_to_construct_v2: bool)
signal build_attempted(building_id: String, tile_id: String)
signal infrastructure_attempted(infra_type: String, tile_id: String)

enum Kind { NONE, BUILDING, INFRASTRUCTURE }

# Minimum gap between successful attempt_build calls. Rapid clicks below this
# threshold are silently ignored — protects downstream signal handlers (toasts,
# building visuals, money panel) from queuing more work than a frame can absorb.
const MIN_BUILD_INTERVAL_MS := 150

var is_active: bool = false
var kind: Kind = Kind.NONE
var current_building_id: String = ""
var current_recipe_id: String = ""
var current_infrastructure_type: String = ""
var return_to_construct_v2_on_exit: bool = false
var _last_attempt_ms: int = 0
## Set by the map when an attempt is turned away before anything is placed — no land, no room,
## sea under a road. The construct panel reads it back through attempt_direct_build: a refusal
## the player can act on should leave their choices on screen, not throw the panel away and
## make them rebuild the whole selection to try the tile next door (owner, 25 Aug).
var last_attempt_refused: bool = false

func enter_build_mode(building_id: String, recipe_id: String, return_to_construct_v2: bool = false) -> void:
	if building_id == "" or recipe_id == "":
		return
	is_active = true
	kind = Kind.BUILDING
	current_building_id = building_id
	current_recipe_id = recipe_id
	current_infrastructure_type = ""
	return_to_construct_v2_on_exit = return_to_construct_v2
	mode_entered.emit(building_id, recipe_id)
	print("Build mode entered for %s with recipe %s" % [building_id, recipe_id])

func enter_infrastructure_mode(infra_type: String, return_to_construct_v2: bool = false) -> void:
	if infra_type == "":
		return
	is_active = true
	kind = Kind.INFRASTRUCTURE
	current_infrastructure_type = infra_type
	current_building_id = ""
	current_recipe_id = ""
	return_to_construct_v2_on_exit = return_to_construct_v2
	# Infrastructure is a first-class build mode too. The map overlay listens to
	# this signal to render its placement viability mask.
	mode_entered.emit("", "")
	print("Infrastructure mode entered for %s" % infra_type)

func exit_build_mode() -> void:
	if not is_active:
		return
	var was_kind := kind
	var was_building := current_building_id
	var was_recipe := current_recipe_id
	var was_infra := current_infrastructure_type
	var was_return_to_construct_v2 := return_to_construct_v2_on_exit
	is_active = false
	kind = Kind.NONE
	current_building_id = ""
	current_recipe_id = ""
	current_infrastructure_type = ""
	return_to_construct_v2_on_exit = false
	mode_exited_with_selection.emit(was_building, was_recipe, was_infra, was_return_to_construct_v2)
	mode_exited.emit()
	if was_kind == Kind.BUILDING:
		print("Build mode exited (was: %s)" % was_building)
	elif was_kind == Kind.INFRASTRUCTURE:
		print("Infrastructure mode exited (was: %s)" % was_infra)

func attempt_build(tile_id: String) -> void:
	if not is_active:
		return
	if not _can_attempt_now():
		return
	if kind == Kind.BUILDING:
		build_attempted.emit(current_building_id, tile_id)
	elif kind == Kind.INFRASTRUCTURE:
		infrastructure_attempted.emit(current_infrastructure_type, tile_id)

## Returns true when the attempt got as far as placing something (or opening a dialog that
## will). False means it was refused outright and nothing changed.
func attempt_direct_build(building_id: String, recipe_id: String, tile_id: String) -> bool:
	if building_id == "" or recipe_id == "" or tile_id == "":
		return false
	if not _can_attempt_now():
		return false
	last_attempt_refused = false
	var previous_kind := kind
	var previous_building := current_building_id
	var previous_recipe := current_recipe_id
	var previous_infra := current_infrastructure_type
	var previous_return_to_construct_v2 := return_to_construct_v2_on_exit
	kind = Kind.BUILDING
	current_building_id = building_id
	current_recipe_id = recipe_id
	current_infrastructure_type = ""
	return_to_construct_v2_on_exit = false
	build_attempted.emit(building_id, tile_id)
	kind = previous_kind
	current_building_id = previous_building
	current_recipe_id = previous_recipe
	current_infrastructure_type = previous_infra
	return_to_construct_v2_on_exit = previous_return_to_construct_v2
	# build_attempted is emitted synchronously, so the map has already run its gates.
	return not last_attempt_refused

func _can_attempt_now() -> bool:
	var now: int = Time.get_ticks_msec()
	if now - _last_attempt_ms < MIN_BUILD_INTERVAL_MS:
		return false
	_last_attempt_ms = now
	return true
