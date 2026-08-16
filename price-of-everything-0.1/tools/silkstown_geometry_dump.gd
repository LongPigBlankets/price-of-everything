extends Node
## Read-only geometry oracle for the Silkstown visual riverfront-street pass.
## Writes sampled river paths and built-road segments for tile_9_8/tile_9_9.

const TARGET_IDS := ["tile_9_8", "tile_9_9"]

func _ready() -> void:
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	for _i in 180:
		await get_tree().process_frame
	var terrain := game.get_node("%TerrainLayer") as TileMapLayer
	var buildings := game.get_node("%BuildingVisuals")
	var river_visuals := game.get_node("RiverVisuals")
	var target_coords: Array[Vector2i] = []
	for tile_id in TARGET_IDS:
		var coord: Vector2i = terrain.id_to_coord(tile_id)
		assert(coord != Vector2i(-1, -1), "Silkstown oracle cannot resolve %s" % tile_id)
		target_coords.append(coord)
	var record := {
		"river_paths": [], "roads": [], "tiles": [],
		"footprints": [], "industry_sites": [],
	}
	for coord in target_coords:
		var center := terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
		var data: Dictionary = terrain.tiles.get(coord, {})
		record.tiles.append({
			"coord": [coord.x, coord.y],
			"id": str(data.get("id", "")),
			"nickname": str(data.get("nickname", "")),
			"center": [center.x, center.y],
		})
		for rect_value in buildings.footprint_rects_on_tile(coord):
			var rect: Rect2 = rect_value
			record.footprints.append({
				"coord": [coord.x, coord.y],
				"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
			})
		for site_value in buildings.midcentury_industry_sites_on_tile(coord):
			var site: Dictionary = site_value
			var rect: Rect2 = site.rect
			var poly_points: Array = []
			for point in (site.poly as PackedVector2Array):
				poly_points.append([point.x, point.y])
			record.industry_sites.append({
				"coord": [coord.x, coord.y],
				"instance_id": str(site.get("instance_id", "")),
				"family": str(site.get("family", "")),
				"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
				"poly": poly_points,
			})
	for entry_value in river_visuals.get_river_polylines():
		var entry: Dictionary = entry_value
		if not target_coords.has(entry.coord):
			continue
		var points: Array = []
		for point in (entry.points as PackedVector2Array):
			points.append([point.x, point.y])
		record.river_paths.append({"coord": [entry.coord.x, entry.coord.y], "points": points})
	var seen: Dictionary = {}
	for coord in target_coords:
		for edge_id_value in RoadNetwork.instance().edges_on_tile(coord):
			var edge_id := str(edge_id_value)
			if seen.has(edge_id):
				continue
			seen[edge_id] = true
			var edge: Dictionary = RoadNetwork.instance().edges.get(edge_id, {})
			if str(edge.get("state", "")) != RoadNetwork.STATE_BUILT:
				continue
			var geometry: Array = []
			for point in (edge.get("geometry", PackedVector2Array()) as PackedVector2Array):
				geometry.append([point.x, point.y])
			record.roads.append({
				"edge_id": edge_id,
				"tier": str(edge.get("tier", "")),
				"bridges": edge.get("bridges", []),
				"geometry": geometry,
			})
	var file := FileAccess.open("/tmp/poe_silkstown_geometry.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(record, "  "))
	file.close()
	print("[SILKSTOWN] %d river paths, %d built roads, %d footprints" % [
		record.river_paths.size(), record.roads.size(), record.footprints.size()])
	get_tree().quit(0)
