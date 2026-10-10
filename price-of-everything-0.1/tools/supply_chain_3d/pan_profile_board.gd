extends "res://scripts/supply_chain_3d/board.gd"
var probe: Dictionary = {}
func _wanted_detail_tiles() -> Array:
	var start := Time.get_ticks_usec()
	var result := super._wanted_detail_tiles()
	(probe.get_or_add("visibility", []) as Array).append((Time.get_ticks_usec() - start) / 1000.0)
	return result
func _build_local_tile(builder: RefCounted, parent: Node3D, model: Dictionary, tid: String, generation: int) -> bool:
	var start := Time.get_ticks_usec()
	var result := await super._build_local_tile(builder, parent, model, tid, generation)
	(probe.get_or_add("build_local_tile", []) as Array).append((Time.get_ticks_usec() - start) / 1000.0)
	return result
