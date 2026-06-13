class_name TileOccupancy
extends RefCounted
## Static registry of blocked subtiles per tile — the spatial occupancy
## substrate. Hills (upper contour rings, from the baked hill data) are the
## static producer; roads-v2 corridors and forest discs register as DYNAMIC
## producers (Phase 3), gated behind OCCUPANCY_ROADS_ENABLED until the Phase-5
## cutover. Consumers ask "is this subtile blocked?" via
## SubtileGrid.is_subtile_buildable(..., tile_id) or directly, and read the
## per-tile congestion factor (occupied subtile fraction) for routing costs.

## Dynamic producers (roads/forests) contribute to is_blocked only when true.
## Default off until the Phase-5 cutover; tests and the cheat may enable it.
static var OCCUPANCY_ROADS_ENABLED := false

static var _blocked: Dictionary = {}   # tile_id -> Dictionary[int bit -> true]
static var _loaded := false
## producer name -> tile_id -> Dictionary[int bit -> true]
static var _dynamic: Dictionary = {}
## tile_id -> float occupied fraction (lazy; invalidated on dynamic updates)
static var _congestion_cache: Dictionary = {}

const SUBTILE_COUNT := 27 * 24   # SubtileGrid.COLUMNS x ROWS

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for tile_id in HillBaked.blocked():
		var bits := {}
		for b in HillBaked.blocked()[tile_id]:
			bits[int(b)] = true
		_blocked[tile_id] = bits

static func is_blocked(tile_id: String, col: int, row: int) -> bool:
	if tile_id == "":
		return false
	_ensure_loaded()
	var bit := (row - 1) * SubtileGrid.COLUMNS + (col - 1)
	if _blocked.has(tile_id) and _blocked[tile_id].has(bit):
		return true
	if OCCUPANCY_ROADS_ENABLED:
		for producer in _dynamic:
			var tiles: Dictionary = _dynamic[producer]
			if tiles.has(tile_id) and tiles[tile_id].has(bit):
				return true
	return false

static func blocked_count(tile_id: String) -> int:
	_ensure_loaded()
	return _blocked[tile_id].size() if _blocked.has(tile_id) else 0

# -------------------------------------------------------- dynamic producers

## Replace one producer's bits for one tile (bits: Dictionary[int -> true]).
static func set_dynamic(producer: String, tile_id: String, bits: Dictionary) -> void:
	if not _dynamic.has(producer):
		_dynamic[producer] = {}
	if bits.is_empty():
		_dynamic[producer].erase(tile_id)
	else:
		_dynamic[producer][tile_id] = bits
	_congestion_cache.erase(tile_id)

## Clear one producer entirely, or just its bits on one tile.
static func clear_dynamic(producer: String, tile_id: String = "") -> void:
	if not _dynamic.has(producer):
		return
	if tile_id == "":
		for t in _dynamic[producer]:
			_congestion_cache.erase(t)
		_dynamic.erase(producer)
	else:
		_dynamic[producer].erase(tile_id)
		_congestion_cache.erase(tile_id)

static func dynamic_count(producer: String, tile_id: String) -> int:
	if not _dynamic.has(producer):
		return 0
	var tiles: Dictionary = _dynamic[producer]
	return tiles[tile_id].size() if tiles.has(tile_id) else 0

## Occupied subtile fraction for the tile (static + dynamic, union), cached.
## Drives the congestion cost factor / contextual road tiers.
static func congestion(tile_id: String) -> float:
	if _congestion_cache.has(tile_id):
		return _congestion_cache[tile_id]
	_ensure_loaded()
	var bits := {}
	if _blocked.has(tile_id):
		for b in _blocked[tile_id]:
			bits[b] = true
	if OCCUPANCY_ROADS_ENABLED:
		for producer in _dynamic:
			var tiles: Dictionary = _dynamic[producer]
			if tiles.has(tile_id):
				for b2 in tiles[tile_id]:
					bits[b2] = true
	var f := float(bits.size()) / float(SUBTILE_COUNT)
	_congestion_cache[tile_id] = f
	return f

## Test/tooling hook: replace the registry.
static func reset_for_tests() -> void:
	_blocked = {}
	_loaded = false
	_dynamic = {}
	_congestion_cache = {}
	OCCUPANCY_ROADS_ENABLED = false
