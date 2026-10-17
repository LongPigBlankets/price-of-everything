extends "res://tools/supply_chain_3d/bake_company_start.gd"
## Dry run of bake_company_start: prints the owned-tile keys it would index, writes nothing to the package.

func _continent_review(board: Control, _home: Dictionary) -> void:
	var builder: RefCounted = board._builder
	print("[KEY PROBE] scenery ", builder._scenery_key)
	print("[KEY PROBE] transport ", builder.transport_key)
	for tid in builder.tiles:
		print("[KEY PROBE] ", tid, " ", builder.road_mesh_key(tid))
		for tier in 3: print("[KEY PROBE] ", tid, " ", builder.tile_bake_key(tid, tier))
	get_tree().quit()
