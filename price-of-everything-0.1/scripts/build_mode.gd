extends Node

signal mode_entered(building_id: String, recipe_id: String)
signal mode_exited
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
var _last_attempt_ms: int = 0

func enter_build_mode(building_id: String, recipe_id: String) -> void:
	if building_id == "" or recipe_id == "":
		return
	is_active = true
	kind = Kind.BUILDING
	current_building_id = building_id
	current_recipe_id = recipe_id
	current_infrastructure_type = ""
	mode_entered.emit(building_id, recipe_id)
	print("Build mode entered for %s with recipe %s" % [building_id, recipe_id])

func enter_infrastructure_mode(infra_type: String) -> void:
	if infra_type == "":
		return
	is_active = true
	kind = Kind.INFRASTRUCTURE
	current_infrastructure_type = infra_type
	current_building_id = ""
	current_recipe_id = ""
	print("Infrastructure mode entered for %s" % infra_type)

func exit_build_mode() -> void:
	if not is_active:
		return
	var was_kind := kind
	var was_building := current_building_id
	var was_infra := current_infrastructure_type
	is_active = false
	kind = Kind.NONE
	current_building_id = ""
	current_recipe_id = ""
	current_infrastructure_type = ""
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

func attempt_direct_build(building_id: String, recipe_id: String, tile_id: String) -> void:
	if building_id == "" or recipe_id == "" or tile_id == "":
		return
	if not _can_attempt_now():
		return
	var previous_kind := kind
	var previous_building := current_building_id
	var previous_recipe := current_recipe_id
	var previous_infra := current_infrastructure_type
	kind = Kind.BUILDING
	current_building_id = building_id
	current_recipe_id = recipe_id
	current_infrastructure_type = ""
	build_attempted.emit(building_id, tile_id)
	kind = previous_kind
	current_building_id = previous_building
	current_recipe_id = previous_recipe
	current_infrastructure_type = previous_infra

func _can_attempt_now() -> bool:
	var now: int = Time.get_ticks_msec()
	if now - _last_attempt_ms < MIN_BUILD_INTERVAL_MS:
		return false
	_last_attempt_ms = now
	return true
