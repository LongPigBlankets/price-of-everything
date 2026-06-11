class_name TileOccupancy
extends RefCounted
## Static registry of statically-blocked subtiles per tile — the spatial
## occupancy substrate. Hills (upper contour rings, from the baked hill data)
## are the first producer; polygon building footprints and forests are meant
## to register here later. Consumers ask "is this subtile blocked?" via
## SubtileGrid.is_subtile_buildable(..., tile_id) or directly.

static var _blocked: Dictionary = {}   # tile_id -> Dictionary[int bit -> true]
static var _loaded := false

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
	if not _blocked.has(tile_id):
		return false
	return _blocked[tile_id].has((row - 1) * SubtileGrid.COLUMNS + (col - 1))

static func blocked_count(tile_id: String) -> int:
	_ensure_loaded()
	return _blocked[tile_id].size() if _blocked.has(tile_id) else 0

## Test/tooling hook: replace the registry (e.g. before save/load adds
## dynamic producers).
static func reset_for_tests() -> void:
	_blocked = {}
	_loaded = false
