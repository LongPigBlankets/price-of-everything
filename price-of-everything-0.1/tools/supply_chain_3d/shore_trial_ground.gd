extends "res://scripts/empire_board_ground.gd"
## Retain the corrected outer coast, but lower newly reclaimed/beach land into a shelf.
var historical: RefCounted

func _block_level(_block: Vector2i) -> float:
	# The historical inland bank is absent from the new coast's segment index.
	# Evaluate its lattice nodes too instead of treating the whole block as flat.
	return NAN

func _ground(p: Vector2, full: bool) -> float:
	var current := super._ground(p, full)
	if not full or historical == null: return current
	return minf(current, maxf(27.0, historical.height(p) + 2.0))
