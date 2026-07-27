extends Node
# Per-turn power tracking + grid transaction settlement.
# Power is generated and consumed within the same PROCESS phase.
#
# Power flows over PHYSICAL cable networks: a network is a connected component of
# hex-adjacent cabled tiles. Generation on a tile covers that tile's own draw first,
# then the rest of its cable network; only the network's residual SURPLUS is sold to
# the national grid, and only its residual DEFICIT is bought — networks settle
# independently (a surplus network can sell while an isolated one buys).
# Cables on a tile are required for any power participation (production OR consumption).

var supply_this_turn: int = 0
var demand_this_turn: int = 0
# Per-tile power generated (export) and drawn (import) this turn — each hard-capped
# by the tile's cable level (see tile_power_cap). Reset each turn.
var tile_produced: Dictionary = {}
var tile_drawn: Dictionary = {}
# Per-tile attribution set during settlement: true when this tile's draw was fully
# covered by its own cable network's generation (own supply), false when any of it was
# imported from the national grid. Read by BuildingStatus.power_supply for the UI.
var _tile_self_supplied: Dictionary = {}

func reset_for_turn() -> void:
	supply_this_turn = 0
	demand_this_turn = 0
	tile_produced.clear()
	tile_drawn.clear()
	_tile_self_supplied.clear()

func add_supply(amount: int) -> void:
	if amount > 0:
		supply_this_turn += amount

func add_demand(amount: int) -> void:
	if amount > 0:
		demand_this_turn += amount

# ── Per-tile cable power cap ────────────────────────────────────────────────
## A tile's per-turn power cap: cable-level cap (EconomyConfig.CABLE_POWER_CAP) × cable
## throughput research. 0 means no cables → no power production or draw.
func tile_power_cap(tile_id: String) -> int:
	var level := _tile_cable_level(tile_id)
	if level <= 0:
		return 0
	var cap := float(EconomyConfig.CABLE_POWER_CAP.get(level, 0))
	if cap <= 0.0:
		# Cable level above the table (e.g. a future L4 before the config is
		# extended): fall back to the highest defined cap, never a stale magic
		# number that would silently throttle the tile.
		cap = float(EconomyConfig.CABLE_POWER_CAP.values().max())
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

## A tile's cable level (0 = uncabled). Public so the building-detail diagnostics can tell
## "upgrade your cables" from "this tile is already at the maximum".
func cable_level(tile_id: String) -> int:
	return _tile_cable_level(tile_id)

## True when this tile's cables are at the highest level the cap table defines — there is
## no upgrade left to suggest.
func cable_level_is_max(tile_id: String) -> bool:
	return _tile_cable_level(tile_id) >= EconomyConfig.CABLE_POWER_CAP.size()

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
	# Settle each cable network's residual net independently against the national grid, then
	# aggregate. A network is a connected component of adjacent cabled tiles; a surplus network
	# SELLS while a deficit network BUYS in the same turn (they don't cancel each other).
	_tile_self_supplied.clear()
	var grid_bought: int = 0
	var grid_sold: int = 0
	var cabled := _cabled_tile_set()
	if cabled.is_empty():
		# No map / cable data available (headless unit context): single global pool fallback.
		var net_g: int = supply_this_turn - demand_this_turn
		if net_g < 0:
			grid_bought = -net_g
		elif net_g > 0:
			grid_sold = net_g
	else:
		# Seed a BFS from every tile with power activity; walk adjacent cabled tiles to build the
		# network, sum its generation vs demand, and settle only the residual with the grid.
		var active: Dictionary = {}
		for t in tile_produced:
			active[t] = true
		for t in tile_drawn:
			active[t] = true
		var seeds: Array = active.keys()
		seeds.sort()  # determinism
		var visited: Dictionary = {}
		for seed in seeds:
			if visited.has(seed):
				continue
			var comp: Array = _cable_component(str(seed), cabled, visited)
			var gen: int = 0
			var dem: int = 0
			for t in comp:
				gen += int(tile_produced.get(t, 0))
				dem += int(tile_drawn.get(t, 0))
			var net: int = gen - dem
			if net < 0:
				grid_bought += -net
			elif net > 0:
				grid_sold += net
			_mark_network_supply(comp, gen, dem)

	# A COO advisor negotiates grid tariffs: cheaper imported power (grid_buy_price)
	# and better-paid exports (grid_sell_price).
	var buy_mult: float = maxf(0.0, 1.0 + float(Modifiers.resolve_pct("grid_buy_price", "*", {}).get("net", 0.0)) / 100.0)
	var sell_mult: float = maxf(0.0, 1.0 + float(Modifiers.resolve_pct("grid_sell_price", "*", {}).get("net", 0.0)) / 100.0)
	return {
		"supply": supply_this_turn,
		"demand": demand_this_turn,
		"net": supply_this_turn - demand_this_turn,
		"grid_bought": grid_bought,
		"grid_sold": grid_sold,
		"grid_buy_cost": grid_bought * EconomyConfig.GRID_BUY_PRICE * buy_mult,
		"grid_sell_revenue": grid_sold * EconomyConfig.GRID_SELL_PRICE * sell_mult,
	}

## True when this tile's power draw was fully covered by its own cable network's generation
## this turn (own supply); false when any of it was imported from the national grid.
func is_self_supplied(tile_id: String) -> bool:
	return bool(_tile_self_supplied.get(tile_id, false))

# --- Cable-network connectivity (physical adjacency) ---------------------------------------

# Every cabled tile_id on the map. Empty when no hex_map is present (pure headless context).
func _cabled_tile_set() -> Dictionary:
	var out: Dictionary = {}
	var hex_map = get_tree().get_first_node_in_group("hex_map") if get_tree() else null
	if hex_map == null:
		return out
	var tiles = hex_map.get("tiles")
	if tiles == null:
		return out
	for coord in tiles:
		var tile: Dictionary = tiles[coord]
		if (tile.get("infrastructure_present", []) as Array).has("cables"):
			out[_coord_to_id(coord)] = true
	return out

# Connected component of cabled tiles reachable from `seed` (flood-fill over hex adjacency).
func _cable_component(seed: String, cabled: Dictionary, visited: Dictionary) -> Array:
	var comp: Array = []
	var stack: Array = [seed]
	visited[seed] = true
	while not stack.is_empty():
		var t: String = str(stack.pop_back())
		comp.append(t)
		var c := _id_to_coord(t)
		if c == Vector2i(-1, -1):
			continue
		for nc in _neighbor_coords(c):
			var nid := _coord_to_id(nc)
			if cabled.has(nid) and not visited.has(nid):
				visited[nid] = true
				stack.append(nid)
	return comp

# Attribution: mark each tile own-supplied (draw covered by network generation) or grid.
# Same-tile generation covers same-tile draw first, then the network's residual generation
# pool covers the rest (deterministic tile order); any uncovered draw is a grid import.
func _mark_network_supply(comp: Array, gen: int, dem: int) -> void:
	if gen >= dem:
		for t in comp:
			_tile_self_supplied[t] = true  # network self-sufficient → every draw is own supply
		return
	var pool: int = 0  # network residual generation after same-tile self-coverage
	var residual_dem: Dictionary = {}
	for t in comp:
		var g: int = int(tile_produced.get(t, 0))
		var d: int = int(tile_drawn.get(t, 0))
		var self_cov: int = mini(g, d)
		pool += g - self_cov
		var rd: int = d - self_cov
		# Fully self-covered (or a pure generator / no draw) is own supply; residual decided below.
		_tile_self_supplied[t] = rd == 0
		if rd > 0:
			residual_dem[t] = rd
	var order: Array = residual_dem.keys()
	order.sort()
	for t in order:
		var rd: int = int(residual_dem[t])
		var take: int = mini(rd, pool)
		pool -= take
		_tile_self_supplied[t] = take >= rd  # fully covered by the network → own supply, else grid

# Hex (odd-q offset) neighbour coords — mirrors hex_map._neighbor_offset_for_hsm (pure).
func _neighbor_coords(c: Vector2i) -> Array:
	var odd: bool = c.x % 2 == 1
	return [
		c + Vector2i(0, -1),
		c + (Vector2i(1, 0) if odd else Vector2i(1, -1)),
		c + (Vector2i(1, 1) if odd else Vector2i(1, 0)),
		c + Vector2i(0, 1),
		c + (Vector2i(-1, 1) if odd else Vector2i(-1, 0)),
		c + (Vector2i(-1, 0) if odd else Vector2i(-1, -1)),
	]

func _coord_to_id(c: Vector2i) -> String:
	return "tile_%d_%d" % [c.x + 1, c.y + 1]

func _id_to_coord(t: String) -> Vector2i:
	var parts := t.split("_")
	if parts.size() != 3 or parts[0] != "tile":
		return Vector2i(-1, -1)
	if not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return Vector2i(-1, -1)
	return Vector2i(int(parts[1]) - 1, int(parts[2]) - 1)

func _tile_has_cables(tile_id: String) -> bool:
	var hex_map = get_tree().get_first_node_in_group("hex_map")
	if hex_map == null:
		return false
	var coord: Vector2i = hex_map.id_to_coord(tile_id)
	if coord == Vector2i(-1, -1):
		return false
	var tile: Dictionary = hex_map.tiles.get(coord, {})
	return tile.get("infrastructure_present", []).has("cables")
