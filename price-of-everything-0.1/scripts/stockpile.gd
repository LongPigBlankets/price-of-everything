extends Node
# Single source of truth for goods stockpiles.
# Per-tile storage with aggregate helpers for panels that still show global totals.

const TILE_CAPACITY := 500
const LEGACY_TILE_KEY := "__legacy_global__"

var _by_tile: Dictionary = {}  # tile_key -> good_id -> int

# --- Silent-leak metric: goods that couldn't be stored this turn because the tile
# was at capacity. RunMetrics reads + resets this once per turn. Purely additive;
# nothing in the game loop depends on it, so it can never change stockpile behaviour.
var _capacity_lost_this_turn: int = 0

# Tracks which tiles are currently at/over capacity, so tile_reached_capacity fires
# only on the FIRST add that fills a tile (not every subsequent add while it stays
# full). Cleared when a consume drops the tile back below capacity.
var _at_capacity: Dictionary = {}  # tile_key -> bool

signal stockpile_changed()
# Fired the moment a tile crosses from below to at/over its storage capacity. The
# capacity dialog listens to this to prompt the player (sell surplus / expand / stop).
signal tile_reached_capacity(tile_id: String)

# --- Public API ---

func get_total(good_id: String) -> int:
	var total := 0
	for tile_stockpile in _by_tile.values():
		total += int(tile_stockpile.get(good_id, 0))
	return total

func get_at_tile(coord, good_id: String) -> int:
	var tile_stockpile := _stockpile_for_tile(coord, false)
	if tile_stockpile.is_empty():
		return 0
	return int(tile_stockpile.get(good_id, 0))

func get_capacity(coord) -> int:
	if coord == null:
		return 999999
	# tile_storage research (warehouse upgrades) scales the per-tile capacity.
	return int(round(Modifiers.apply("tile_storage", "", float(TILE_CAPACITY + _storage_boost_for(coord)), {})))

func _storage_boost_for(coord) -> int:
	var tile_id := str(coord)
	var boost := 0
	for instance_id in MatchState.tile_buildings.get(tile_id, []):
		var inst: Dictionary = MatchState.get_building(instance_id)
		var bd: Dictionary = Catalog.get_building(str(inst.get("building_id", "")))
		boost += int(bd.get("storage_boost", 0))
	return boost

func get_used_capacity(coord) -> int:
	var used := 0
	for qty in _stockpile_for_tile(coord, false).values():
		used += int(qty)
	return used

func get_free_capacity(coord) -> int:
	return maxi(0, get_capacity(coord) - get_used_capacity(coord))

func get_tile_totals(coord) -> Dictionary:
	return _stockpile_for_tile(coord, false).duplicate()

func get_top_goods(coord, limit: int = 3) -> Array:
	var rows: Array = []
	for good_id in _stockpile_for_tile(coord, false).keys():
		var qty: int = get_at_tile(coord, good_id)
		if qty > 0:
			rows.append({"good_id": good_id, "qty": qty})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.qty) == int(b.qty):
			return str(a.good_id) < str(b.good_id)
		return int(a.qty) > int(b.qty)
	)
	if limit < 0 or rows.size() <= limit:
		return rows
	return rows.slice(0, limit)

func add(coord, good_id: String, qty: int) -> int:
	# Returns actually added; capped by remaining tile capacity.
	if qty <= 0 or good_id == "":
		return 0
	var free_capacity := get_free_capacity(coord)
	var added: int = mini(qty, free_capacity)
	if added < qty:
		# Whatever couldn't fit is lost to the capacity cap — record it for metrics.
		_capacity_lost_this_turn += (qty - added)
	if added <= 0:
		return 0
	var tile_stockpile := _stockpile_for_tile(coord, true)
	tile_stockpile[good_id] = int(tile_stockpile.get(good_id, 0)) + added
	stockpile_changed.emit()
	_check_capacity(coord)
	return added

func consume(coord, good_id: String, qty: int) -> int:
	# Returns actually consumed (may be less than qty if shortage).
	if qty <= 0 or good_id == "":
		return 0
	var tile_stockpile := _stockpile_for_tile(coord, false)
	if tile_stockpile.is_empty():
		return 0
	var available: int = int(tile_stockpile.get(good_id, 0))
	var taken: int = mini(available, qty)
	if taken > 0:
		var remaining := available - taken
		if remaining > 0:
			tile_stockpile[good_id] = remaining
		else:
			tile_stockpile.erase(good_id)
		_prune_empty_tile(coord)
		stockpile_changed.emit()
		_check_capacity(coord)
	return taken

func _check_capacity(coord) -> void:
	# Emit tile_reached_capacity on the rising edge (below -> at/over capacity); reset
	# the latch once the tile drops back below, so a later refill can prompt again.
	if coord == null:
		return
	var key := str(coord)
	var full: bool = get_used_capacity(coord) >= get_capacity(coord)
	if full and not bool(_at_capacity.get(key, false)):
		_at_capacity[key] = true
		tile_reached_capacity.emit(key)
	elif not full and bool(_at_capacity.get(key, false)):
		_at_capacity[key] = false

func consume_anywhere(good_id: String, qty: int) -> int:
	if qty <= 0 or good_id == "":
		return 0
	var remaining := qty
	var taken := 0
	for tile_key in _by_tile.keys():
		if remaining <= 0:
			break
		var tile_stockpile: Dictionary = _by_tile[tile_key]
		var available: int = int(tile_stockpile.get(good_id, 0))
		if available <= 0:
			continue
		var tile_taken: int = mini(available, remaining)
		var left_on_tile := available - tile_taken
		if left_on_tile > 0:
			tile_stockpile[good_id] = left_on_tile
		else:
			tile_stockpile.erase(good_id)
		if tile_stockpile.is_empty():
			_by_tile.erase(tile_key)
		taken += tile_taken
		remaining -= tile_taken
	if taken > 0:
		stockpile_changed.emit()
	return taken

func clear_all() -> void:
	_by_tile.clear()
	_at_capacity.clear()
	_capacity_lost_this_turn = 0
	stockpile_changed.emit()

# --- Save/load (orchestrated by the SaveLoad autoload; docs/save_load_spec.md) ---

func export_state() -> Dictionary:
	return {"by_tile": _by_tile.duplicate(true)}

func import_state(d: Dictionary) -> void:
	# Silent: SaveLoad emits stockpile_changed once after every system imports.
	_by_tile = (d.get("by_tile", {}) as Dictionary).duplicate(true)
	_at_capacity.clear()
	_capacity_lost_this_turn = 0

func tiles_with_stock() -> Array:
	# Tile keys that currently hold goods (callers filter to real "tile_*" ids).
	return _by_tile.keys()

func get_all_totals() -> Dictionary:
	var totals := {}
	for tile_stockpile in _by_tile.values():
		for good_id in tile_stockpile.keys():
			totals[good_id] = int(totals.get(good_id, 0)) + int(tile_stockpile[good_id])
	return totals

# --- Silent-leak metric API (read + reset by RunMetrics each turn) ---

func get_capacity_lost_this_turn() -> int:
	return _capacity_lost_this_turn

func reset_capacity_lost_this_turn() -> void:
	_capacity_lost_this_turn = 0

func _stockpile_for_tile(coord, create_if_missing: bool) -> Dictionary:
	var tile_key := _tile_key(coord)
	if not _by_tile.has(tile_key):
		if not create_if_missing:
			return {}
		_by_tile[tile_key] = {}
	return _by_tile[tile_key]

func _tile_key(coord) -> String:
	if coord == null:
		return LEGACY_TILE_KEY
	if coord is Vector2i:
		return "%d,%d" % [coord.x, coord.y]
	if coord is Vector2:
		return "%d,%d" % [int(coord.x), int(coord.y)]
	return str(coord)

func _prune_empty_tile(coord) -> void:
	var tile_key := _tile_key(coord)
	if _by_tile.has(tile_key) and (_by_tile[tile_key] as Dictionary).is_empty():
		_by_tile.erase(tile_key)
