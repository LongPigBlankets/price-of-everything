extends Node
# Single source of truth for goods stockpiles.
# Per-tile storage with aggregate helpers for panels that still show global totals.

const TILE_CAPACITY := 500
const LEGACY_TILE_KEY := "__legacy_global__"

var _by_tile: Dictionary = {}  # tile_key -> good_id -> int

signal stockpile_changed()

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
	return TILE_CAPACITY + _storage_boost_for(coord)

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
	if added <= 0:
		return 0
	var tile_stockpile := _stockpile_for_tile(coord, true)
	tile_stockpile[good_id] = int(tile_stockpile.get(good_id, 0)) + added
	stockpile_changed.emit()
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
	return taken

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
	stockpile_changed.emit()

func get_all_totals() -> Dictionary:
	var totals := {}
	for tile_stockpile in _by_tile.values():
		for good_id in tile_stockpile.keys():
			totals[good_id] = int(totals.get(good_id, 0)) + int(tile_stockpile[good_id])
	return totals

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
