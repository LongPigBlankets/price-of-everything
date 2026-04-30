extends Node
# Single source of truth for goods stockpiles.
# Pass 1: single global bucket. The coord parameter is accepted but ignored.
# Pass 2 (later): coord routes to per-tile internal storage; call sites unchanged.

var _global: Dictionary = {}  # good_id -> int

signal stockpile_changed()

# --- Public API ---

func get_total(good_id: String) -> int:
	return _global.get(good_id, 0)

func get_at_tile(_coord, good_id: String) -> int:
	# Pass 1: ignores coord, returns global. Pass 2 will route to per-tile.
	return get_total(good_id)

func get_capacity(_coord) -> int:
	# Pass 1: effectively infinite. Pass 2 returns real per-tile capacity.
	return 999999

func add(_coord, good_id: String, qty: int) -> int:
	# Returns actually added (always equals qty in Pass 1; capped by capacity in Pass 2).
	if qty <= 0:
		return 0
	_global[good_id] = _global.get(good_id, 0) + qty
	stockpile_changed.emit()
	return qty

func consume(_coord, good_id: String, qty: int) -> int:
	# Returns actually consumed (may be less than qty if shortage).
	if qty <= 0:
		return 0
	var available: int = _global.get(good_id, 0)
	var taken: int = mini(available, qty)
	if taken > 0:
		_global[good_id] = available - taken
		stockpile_changed.emit()
	return taken

func consume_anywhere(good_id: String, qty: int) -> int:
	# Convenience: consume without specifying a tile. Used during fallback.
	return consume(null, good_id, qty)

func clear_all() -> void:
	_global.clear()
	stockpile_changed.emit()

func get_all_totals() -> Dictionary:
	# Returns a copy of the global stockpile dict. Used by Production for the auto-sell phase.
	return _global.duplicate()
