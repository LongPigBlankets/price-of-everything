extends Node
# Per-turn power tracking + grid transaction settlement.
# Power is generated and consumed within the same PROCESS phase.
# Surplus auto-sells to grid; shortfall auto-buys from grid.
# Cables on a tile required for any power participation (production OR consumption).

var supply_this_turn: int = 0
var demand_this_turn: int = 0
# Per-tile power generated (export) and drawn (import) this turn — each hard-capped
# by the tile's cable level (see tile_power_cap). Reset each turn.
var tile_produced: Dictionary = {}
var tile_drawn: Dictionary = {}

func reset_for_turn() -> void:
	supply_this_turn = 0
	demand_this_turn = 0
	tile_produced.clear()
	tile_drawn.clear()

func add_supply(amount: int) -> void:
	if amount > 0:
		supply_this_turn += amount

func add_demand(amount: int) -> void:
	if amount > 0:
		demand_this_turn += amount

# ── Per-tile cable power cap ────────────────────────────────────────────────
## A tile's per-turn power cap: cable-level cap (L1 200 / L2 400 / L3 700) × cable
## throughput research. 0 means no cables → no power production or draw.
func tile_power_cap(tile_id: String) -> int:
	var level := _tile_cable_level(tile_id)
	if level <= 0:
		return 0
	var cap := float(EconomyConfig.CABLE_POWER_CAP.get(level, 200))
	return int(round(Modifiers.apply("transport_throughput", "cables", cap, {"mode": "cables"})))

## True if the tile can still produce `amount` more power this turn (export cap).
func can_produce(tile_id: String, amount: int) -> bool:
	if amount <= 0:
		return true
	return int(tile_produced.get(tile_id, 0)) + amount <= tile_power_cap(tile_id)

## True if the tile can still draw `amount` more power this turn (import cap).
func can_draw(tile_id: String, amount: int) -> bool:
	if amount <= 0:
		return true
	return int(tile_drawn.get(tile_id, 0)) + amount <= tile_power_cap(tile_id)

## Record `amount` of power generated on a tile (counts toward its export cap + grid).
func record_produced(tile_id: String, amount: int) -> void:
	if amount <= 0:
		return
	tile_produced[tile_id] = int(tile_produced.get(tile_id, 0)) + amount
	add_supply(amount)

## Record `amount` of power drawn on a tile (counts toward its import cap + grid).
func record_drawn(tile_id: String, amount: int) -> void:
	if amount <= 0:
		return
	tile_drawn[tile_id] = int(tile_drawn.get(tile_id, 0)) + amount
	add_demand(amount)

func _tile_cable_level(tile_id: String) -> int:
	var hex_map = get_tree().get_first_node_in_group("hex_map") if get_tree() else null
	if hex_map == null:
		return 0
	var coord: Vector2i = hex_map.id_to_coord(tile_id)
	if coord == Vector2i(-1, -1):
		return 0
	var tile: Dictionary = hex_map.tiles.get(coord, {})
	if not tile.get("infrastructure_present", []).has("cables"):
		return 0
	return int(tile.get("infrastructure_levels", {}).get("cables", 1))

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
