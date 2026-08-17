extends Node
## Measures what could actually be IMPORTED from the live map into the editor, per tile.
## Read-only: boots the world in midcentury, counts what each source can hand over, and
## reports corner counts so the authored schema's limits can be checked against reality.

const SAMPLE_TILES := ["tile_10_16", "tile_23_8", "tile_9_15", "tile_4_9"]

func _ready() -> void:
	MapStyle.set_midcentury(true)
	var world := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(world)
	for _i in 240:
		await get_tree().process_frame

	# 1. ROADS — the baked network's geometry, tier and touched tiles.
	var network := RoadNetwork.instance()
	var built := 0
	var pts := 0
	for edge_id in network.edges:
		var edge: Dictionary = network.edges[edge_id]
		if str(edge.get("state", "")) == "built":
			built += 1
			pts += (edge.get("geometry", []) as Array).size()
	print("[IMPORT] roads: %d built edges, %d geometry points (avg %.1f/edge)"
		% [built, pts, float(pts) / maxf(built, 1)])

	# 2. DECORATIVE MASSES — the fabric's own records, world polygons.
	var fabric := world.get_node_or_null(NodePath("UrbanFabricVisuals"))
	var masses: Array = fabric.get("_decorative_mass_records") if fabric != null else []
	var corner_counts := {}
	var max_corners := 0
	for record_value in masses:
		var poly: PackedVector2Array = (record_value as Dictionary).get("poly", PackedVector2Array())
		var n := poly.size()
		corner_counts[n] = int(corner_counts.get(n, 0)) + 1
		max_corners = maxi(max_corners, n)
	print("[IMPORT] decorative masses: %d records, max %d corners" % [masses.size(), max_corners])
	var keys := corner_counts.keys()
	keys.sort()
	var summary := ""
	for k in keys:
		summary += "%d:%d  " % [k, corner_counts[k]]
	print("[IMPORT] corner histogram: %s" % summary)

	# 3. GAMEPLAY BUILDINGS — footprints, per tile, which become slots.
	var visuals := world.get_node_or_null(NodePath("BuildingVisuals"))
	var placements: Array = visuals.get("_placements") if visuals != null else []
	var per_tile := {}
	for placement_value in placements:
		var tile := str((placement_value as Dictionary).get("tile_id", ""))
		per_tile[tile] = int(per_tile.get(tile, 0)) + 1
	print("[IMPORT] gameplay buildings: %d placed across %d tiles"
		% [placements.size(), per_tile.size()])
	for tile in SAMPLE_TILES:
		print("[IMPORT]   %s: %d buildings" % [tile, int(per_tile.get(tile, 0))])

	# 4. FORESTS — canopy discs, which would become authored woodland polygons.
	var forests := world.get_node_or_null(NodePath("ForestVisuals"))
	print("[IMPORT] forest layer present: %s" % (forests != null))
	get_tree().quit(0)
