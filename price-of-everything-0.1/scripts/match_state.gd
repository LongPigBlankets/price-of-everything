extends Node

# MatchState: the canonical store for everything that changes during a match.
# Other systems read and write here; never store match data elsewhere.

# --- Player resources ---
var money: int = 1000  # starting money for MVP

# --- Building instances ---
# Flat dictionary: instance_id -> building data dict
# Building data: {instance_id, building_id, recipe_id, tile_coord, owner}
var buildings: Dictionary = {}

# --- Tile occupancy index (derived from buildings, kept in sync) ---
# tile_id -> Array of instance_ids
# This is for fast "what's on this tile" queries.
var tile_buildings: Dictionary = {}

# --- Instance ID generation ---
var _next_instance_counter: int = 0

# --- Signals ---
signal money_changed(new_amount: int)
signal building_added(instance: Dictionary)
signal building_removed(instance_id: String)
signal state_reset

# --- Initialization ---
func _ready() -> void:
	pass  # nothing to do at startup; systems push state into MatchState as they boot

# --- Public API: money ---
func add_money(amount: int) -> void:
	money += amount
	money_changed.emit(money)

func deduct_money(amount: int) -> bool:
	# Returns true if successful, false if insufficient funds
	if money < amount:
		return false
	money -= amount
	money_changed.emit(money)
	return true

# --- Public API: buildings ---
func add_building(building_id: String, recipe_id: String, tile_id: String, owner: String = "player_1") -> String:
	# Pass the building_id here!
	var instance_id := _generate_instance_id(building_id) 
	
	var instance := {
		"instance_id": instance_id,
		"building_id": building_id,
		"recipe_id": recipe_id,
		"tile_id": tile_id,
		"owner": owner,
	}
	
	buildings[instance_id] = instance
	
	# Update tile index
	if not tile_buildings.has(tile_id):
		tile_buildings[tile_id] = []
	tile_buildings[tile_id].append(instance_id)
	
	building_added.emit(instance)
	return instance_id

func remove_building(instance_id: String) -> bool:
	if not buildings.has(instance_id):
		return false
	
	var instance: Dictionary = buildings[instance_id]
	var tile_id: String = instance.tile_id
	
	# Remove from tile index
	if tile_buildings.has(tile_id):
		tile_buildings[tile_id].erase(instance_id)
		if tile_buildings[tile_id].is_empty():
			tile_buildings.erase(tile_id)
	
	buildings.erase(instance_id)
	building_removed.emit(instance_id)
	return true

func get_buildings_on_tile(tile_id: String) -> Array:
	# Returns an Array of building instance dicts on the given tile.
	if not tile_buildings.has(tile_id):
		return []
	
	var result: Array = []
	for instance_id in tile_buildings[tile_id]:
		if buildings.has(instance_id):
			result.append(buildings[instance_id])
	return result

func get_building(instance_id: String) -> Dictionary:
	# Returns the instance dict, or empty dict if not found
	return buildings.get(instance_id, {})

# --- Helpers ---
func _generate_instance_id(building_id: String) -> String:
	_next_instance_counter += 1
	# %s injects the string, %06x injects the hex counter
	return "inst_%s_%06x" % [building_id, _next_instance_counter]

# --- Reset (useful for new game / testing) ---
func reset() -> void:
	money = 1000
	buildings.clear()
	tile_buildings.clear()
	_next_instance_counter = 0
	state_reset.emit()

# --- Debug ---
func debug_dump() -> Dictionary:
	# Returns the full state as a dict, useful for save/load and debugging
	return {
		"money": money,
		"buildings": buildings.duplicate(true),
		"tile_buildings": tile_buildings.duplicate(true),
		"_next_instance_counter": _next_instance_counter,
	}
