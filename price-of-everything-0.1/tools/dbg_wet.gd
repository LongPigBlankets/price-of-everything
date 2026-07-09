extends Node2D
## TEMP probe: classify water + nearby crossings at the funnel pass's stubborn spots.
@onready var terrain: HexMap = %TerrainLayer

func _ready() -> void:
	await get_tree().process_frame
	var nav := NavGrid.instance()
	RoadCrossings.build(terrain)
	for spot in [Vector2(7849, 8737), Vector2(7786, 8536), Vector2(7972, 4318)]:
		var c: Vector2i = nav.cell_of(spot)
		print("== spot %s cell water=%d level=%d" % [str(spot), nav.water(c.x, c.y), nav.level(c.x, c.y)])
		var coord: Vector2i = terrain.tile_coord_for_map_coord(terrain.local_to_map(spot))
		if terrain.tiles.has(coord):
			var td: Dictionary = terrain.tiles[coord]
			print("   tile %s type=%s has_river=%s" % [str(td.get("id", "")), str(td.get("type", "")), str(td.get("has_river", false))])
		var found := 0
		var best := 1.0e30
		for crossing in RoadCrossings.in_rect(Rect2(spot - Vector2(800, 800), Vector2(1600, 1600))):
			found += 1
			best = minf(best, (crossing.point as Vector2).distance_to(spot))
		print("   crossings within 800: %d (nearest %.0fu)" % [found, best])
		var counts := {}
		for dy in range(-8, 9):
			for dx in range(-8, 9):
				var w := nav.water(c.x + dx, c.y + dy)
				counts[w] = int(counts.get(w, 0)) + 1
		print("   water classes near (17x17 cells): %s  [LAND=%d RIVER=%d]" % [str(counts), NavGrid.WATER_LAND, NavGrid.WATER_RIVER])
	get_tree().quit(0)
