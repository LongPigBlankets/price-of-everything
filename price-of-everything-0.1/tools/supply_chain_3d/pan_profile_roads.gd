extends "res://scripts/supply_chain_3d/road_surface.gd"
var probe: Array = []
func configure(roads: Array, height: Callable, origin := Vector2.ZERO) -> void:
	var start := Time.get_ticks_usec()
	super.configure(roads, height, origin)
	probe.append((Time.get_ticks_usec() - start) / 1000.0)
