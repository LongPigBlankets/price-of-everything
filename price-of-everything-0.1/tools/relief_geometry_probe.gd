extends Node
## Read-only Phase-B geometry oracle for exact baked contour shoulders.

const TARGETS := ["tile_10_3", "tile_12_8", "tile_13_2", "tile_17_8"]
static var HEX_VERTS := PackedVector2Array([
	Vector2(-135.0, -240.0), Vector2(135.0, -240.0), Vector2(270.0, 0.0),
	Vector2(135.0, 240.0), Vector2(-135.0, 240.0), Vector2(-270.0, 0.0),
])

func _ready() -> void:
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	for _i in 180:
		await get_tree().process_frame
	var terrain := game.get_node("%TerrainLayer") as TileMapLayer
	var hills := game.get_node("HillVisuals")
	var record := {}
	for tile_id in TARGETS:
		var coord: Vector2i = terrain.id_to_coord(tile_id)
		var center := terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
		var extent := PackedVector2Array()
		for vertex in HEX_VERTS:
			extent.append(center + vertex)
		var relief: Dictionary = hills.get_land_relief_geometry([extent])
		record[tile_id] = {
			"center": [center.x, center.y],
			"material_band_count": relief.material_band_count,
			"plateaus": relief.plateaus,
			"raw_plateaus": relief.raw_plateaus,
			"shoulder_count": (relief.shoulders as Array).size(),
		}
	var file := FileAccess.open("/tmp/poe_relief_geometry_probe.json",
		FileAccess.WRITE)
	file.store_string(JSON.stringify(record, "  "))
	file.close()
	print("[RELIEF PROBE] wrote /tmp/poe_relief_geometry_probe.json")
	get_tree().quit(0)
