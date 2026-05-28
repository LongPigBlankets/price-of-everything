extends Node

# MatchState: the canonical store for everything that changes during a match.
# Other systems read and write here; never store match data elsewhere.

# --- Player resources ---
var money: float = 1000.0  # was: int = 1000

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

# --- Labour Slider ---
var labour_multiplier: float = EconomyConfig.LABOUR_MULTIPLIER_DEFAULT

# --- Output routing ---
var output_stockpile_destinations: Dictionary = {}  # instance_id -> {tile_id, good_id}
var pending_output_stockpile_selection: Dictionary = {}
var queued_stockpile_market_sales: Dictionary = {}  # tile_id -> true
var sell_surplus_tiles: Dictionary = {}              # tile_id -> true (standing order)
var pending_transport_shipments: Array = []

enum SellMode { SELL_ALL, STOCKPILE_ALL }
var sell_mode: int = SellMode.SELL_ALL

# --- Signals ---
signal money_changed(new_amount: float) 
signal building_added(instance: Dictionary)
signal building_removed(instance_id: String)
signal state_reset
signal sell_mode_changed(new_mode: int)
signal labour_multiplier_changed(new_value: float)
signal output_stockpile_selection_started(selection: Dictionary)
signal output_stockpile_selection_cancelled
signal output_stockpile_destination_changed(instance_id: String, tile_id: String, good_id: String)
signal stockpile_market_sale_queue_changed(tile_id: String)
signal stockpile_market_sale_completed(sale_record: Dictionary)
signal sell_surplus_changed(tile_id: String)
signal transport_shipments_changed

# --- Initialization ---
func _ready() -> void:
	pass  # nothing to do at startup; systems push state into MatchState as they boot
	money = EconomyConfig.STARTING_MONEY
	money_changed.emit(money)
# --- Public API: money ---
func add_money(delta: float) -> void:
	money += delta
	money_changed.emit(money)

func deduct_money(amount: float) -> bool:  # was: int
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
	output_stockpile_destinations.erase(instance_id)
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
	output_stockpile_destinations.clear()
	pending_output_stockpile_selection.clear()
	queued_stockpile_market_sales.clear()
	sell_surplus_tiles.clear()
	pending_transport_shipments.clear()
	_next_instance_counter = 0
	state_reset.emit()

# --- Debug ---
func debug_dump() -> Dictionary:
	# Returns the full state as a dict, useful for save/load and debugging
	return {
		"money": money,
		"buildings": buildings.duplicate(true),
		"tile_buildings": tile_buildings.duplicate(true),
		"output_stockpile_destinations": output_stockpile_destinations.duplicate(true),
		"queued_stockpile_market_sales": queued_stockpile_market_sales.duplicate(true),
		"pending_transport_shipments": pending_transport_shipments.duplicate(true),
		"_next_instance_counter": _next_instance_counter,
	}

func set_sell_mode(mode: int) -> void:
	sell_mode = mode
	sell_mode_changed.emit(mode)

func begin_output_stockpile_selection(instance_id: String, good_id: String) -> void:
	if instance_id == "" or good_id == "":
		return
	pending_output_stockpile_selection = {
		"instance_id": instance_id,
		"good_id": good_id,
	}
	output_stockpile_selection_started.emit(pending_output_stockpile_selection.duplicate())

func cancel_output_stockpile_selection() -> void:
	if pending_output_stockpile_selection.is_empty():
		return
	pending_output_stockpile_selection.clear()
	output_stockpile_selection_cancelled.emit()

func set_output_stockpile_destination(instance_id: String, tile_id: String, good_id: String) -> void:
	if instance_id == "" or tile_id == "" or good_id == "":
		return
	output_stockpile_destinations[instance_id] = {
		"tile_id": tile_id,
		"good_id": good_id,
	}
	pending_output_stockpile_selection.clear()
	output_stockpile_destination_changed.emit(instance_id, tile_id, good_id)

func clear_output_stockpile_destination(instance_id: String) -> void:
	if instance_id == "":
		return
	output_stockpile_destinations.erase(instance_id)

func get_output_stockpile_destination(instance_id: String, good_id: String = "") -> String:
	var destination: Dictionary = output_stockpile_destinations.get(instance_id, {})
	if destination.is_empty():
		return ""
	if good_id != "" and destination.get("good_id", "") != good_id:
		return ""
	return destination.get("tile_id", "")

func queue_stockpile_market_sale(tile_id: String) -> void:
	if tile_id == "":
		return
	queued_stockpile_market_sales[tile_id] = true
	stockpile_market_sale_queue_changed.emit(tile_id)

func clear_stockpile_market_sale_queue(tile_id: String) -> void:
	if tile_id == "":
		return
	if queued_stockpile_market_sales.erase(tile_id):
		stockpile_market_sale_queue_changed.emit(tile_id)

func is_stockpile_market_sale_queued(tile_id: String) -> bool:
	return queued_stockpile_market_sales.has(tile_id)

func consume_queued_stockpile_market_sales() -> Array:
	var queued_tiles: Array = queued_stockpile_market_sales.keys()
	queued_stockpile_market_sales.clear()
	for tile_id in queued_tiles:
		stockpile_market_sale_queue_changed.emit(str(tile_id))
	return queued_tiles

func emit_stockpile_market_sale_completed(sale_record: Dictionary) -> void:
	stockpile_market_sale_completed.emit(sale_record)

func queue_transport_shipment(shipment: Dictionary) -> void:
	pending_transport_shipments.append(shipment.duplicate(true))
	transport_shipments_changed.emit()

func get_pending_transport_shipments() -> Array:
	return pending_transport_shipments.duplicate(true)

func get_inbound_transport_shipments(destination_tile: String, good_id: String = "") -> Array:
	var result: Array = []
	for shipment in pending_transport_shipments:
		if shipment.get("destination_tile", "") != destination_tile:
			continue
		if good_id != "" and shipment.get("good_id", "") != good_id:
			continue
		result.append(shipment.duplicate(true))
	return result

func advance_transport_shipments() -> Array:
	var arrived: Array = []
	var remaining: Array = []
	for shipment in pending_transport_shipments:
		var record: Dictionary = shipment.duplicate(true)
		record.turns_remaining = int(record.get("turns_remaining", 0)) - 1
		if int(record.turns_remaining) <= 0:
			arrived.append(record)
		else:
			remaining.append(record)
	pending_transport_shipments = remaining
	if not arrived.is_empty():
		transport_shipments_changed.emit()
	return arrived

func enable_sell_surplus(tile_id: String) -> void:
	if tile_id == "" or sell_surplus_tiles.has(tile_id):
		return
	sell_surplus_tiles[tile_id] = true
	sell_surplus_changed.emit(tile_id)

func disable_sell_surplus(tile_id: String) -> void:
	if tile_id == "" or not sell_surplus_tiles.has(tile_id):
		return
	sell_surplus_tiles.erase(tile_id)
	sell_surplus_changed.emit(tile_id)

func is_sell_surplus_enabled(tile_id: String) -> bool:
	return sell_surplus_tiles.has(tile_id)

func get_sell_surplus_tiles() -> Array:
	return sell_surplus_tiles.keys()

func set_labour_multiplier(value: float) -> void:
	# Clamp to valid range
	value = clamp(value, EconomyConfig.LABOUR_MULTIPLIER_MIN, EconomyConfig.LABOUR_MULTIPLIER_MAX)
	if value == labour_multiplier:
		return
	labour_multiplier = value
	labour_multiplier_changed.emit(value)
	print("[MatchState] Labour multiplier set to: %.2fx" % value)
