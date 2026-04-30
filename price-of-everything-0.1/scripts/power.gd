extends Node
# Per-turn power tracking + grid transaction settlement.
# Power is generated and consumed within the same PROCESS phase.
# Surplus auto-sells to grid; shortfall auto-buys from grid.
# Cables on a tile required for any power participation (production OR consumption).

var supply_this_turn: int = 0
var demand_this_turn: int = 0

func reset_for_turn() -> void:
	supply_this_turn = 0
	demand_this_turn = 0

func add_supply(amount: int) -> void:
	if amount > 0:
		supply_this_turn += amount

func add_demand(amount: int) -> void:
	if amount > 0:
		demand_this_turn += amount

func is_supplied(tile_id: String, _energy_req: int = 0) -> bool:
	# A building can run as long as its tile has cables.
	# Power balance is settled at end of turn against the grid.
	# energy_req parameter kept for future use.
	if tile_id == "":
		return false
	return _tile_has_cables(tile_id)

func settle_grid_transactions() -> Dictionary:
	# Returns a settlement record describing the financial impact this turn.
	var net: int = supply_this_turn - demand_this_turn
	var grid_buy_cost: float = 0.0
	var grid_sell_revenue: float = 0.0
	var grid_bought: int = 0
	var grid_sold: int = 0
	
	if net < 0:
		grid_bought = -net
		grid_buy_cost = grid_bought * EconomyConfig.GRID_BUY_PRICE
	elif net > 0:
		grid_sold = net
		grid_sell_revenue = grid_sold * EconomyConfig.GRID_SELL_PRICE
	
	return {
		"supply": supply_this_turn,
		"demand": demand_this_turn,
		"net": net,
		"grid_bought": grid_bought,
		"grid_sold": grid_sold,
		"grid_buy_cost": grid_buy_cost,
		"grid_sell_revenue": grid_sell_revenue,
	}

func _tile_has_cables(tile_id: String) -> bool:
	var hex_map = get_tree().get_first_node_in_group("hex_map")
	if hex_map == null:
		return false
	var coord: Vector2i = hex_map.id_to_coord(tile_id)
	if coord == Vector2i(-1, -1):
		return false
	var tile: Dictionary = hex_map.tiles.get(coord, {})
	return tile.get("infrastructure_present", []).has("cables")
