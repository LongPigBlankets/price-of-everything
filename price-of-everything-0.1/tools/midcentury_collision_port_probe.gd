extends Node
## Focused executable gate for placement invalidation and the shared port plan.

var _wm: Node

func _ready() -> void:
	_wm = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_wm)
	for _i in 150:
		await get_tree().process_frame
	MapStyle.set_midcentury(true)
	for _i in 24:
		await get_tree().process_frame
	var buildings := _wm.find_child("BuildingVisuals", true, false)
	var fabric := _wm.find_child("UrbanFabricVisuals", true, false)
	var terrain := _wm.get_node("%TerrainLayer") as TileMapLayer
	assert(buildings != null and fabric != null)
	var before_version := int(buildings.footprint_version)
	buildings.on_building_placed("tile_23_15", "b_002", "", \
		"midcentury_probe_building", terrain.id_to_coord("tile_23_15"))
	for _i in 2:
		await get_tree().process_frame
	var collision: Dictionary = fabric.gameplay_collision_snapshot()
	assert(int(buildings.footprint_version) > before_version,
		"Building placement must mutate the authoritative footprint cache")
	assert(int(collision.get("footprint_version", -1)) == int(buildings.footprint_version),
		"Urban fabric must rebuild from the post-mutation footprint version within two frames")
	assert(int(collision.get("opaque_overlap_count", -1)) == 0,
		"Opaque decorative geometry must not overlap the newly placed rural-spill building")
	var ports := _wm.find_child("PortVisuals", true, false)
	assert(ports != null and ports.has_method("midcentury_plans"))
	var plans: Array = ports.midcentury_plans()
	assert(plans.size() == Catalog.all_ports().size(),
		"Every valid authoritative port must produce exactly one mid-century compound")
	for plan_value in plans:
		var plan: Dictionary = plan_value
		assert((plan.crane_sites as Array).size() == 2)
		assert(str(plan.crane_sites[0].arm) != str(plan.crane_sites[1].arm))
		assert(float(plan.basin_water_coverage) >= 0.999)
		assert(bool((plan.diagnostics as Dictionary).open_sea_connectivity))
		assert(float((plan.diagnostics as Dictionary).river_overlap_area) <= 0.01)
		assert((plan.road_access as PackedVector2Array).size() >= 2)
		for opaque_value in (plan.land_polygons as Array) + \
				(plan.warehouse_polygons as Array) + (plan.deck_polygons as Array) + \
				(plan.container_polygons as Array):
			assert(_overlap_area(opaque_value, plan.basin_polygon) <= 0.1,
				"Port opaque geometry must remain outside the water-filled basin")
	var reservations: Array = buildings.call(
		"_midcentury_port_marine_reservations")
	assert(reservations.size() == Catalog.all_ports().size() * 2,
		"Every authoritative port must reserve basin and harbour mouth from offshore placement")
	print("[MIDCENTURY PROBE] footprint_version=%d overlap=0 ports=%d" % [
		int(buildings.footprint_version), plans.size()])
	MapStyle.set_midcentury(false)
	get_tree().quit(0)

func _overlap_area(a_value: Variant, b_value: Variant) -> float:
	var area := 0.0
	var a: PackedVector2Array = a_value
	var b: PackedVector2Array = b_value
	for intersection_value in Geometry2D.intersect_polygons(a, b):
		var intersection: PackedVector2Array = intersection_value
		for i in intersection.size():
			var p := intersection[i]
			var q := intersection[(i + 1) % intersection.size()]
			area += p.x * q.y - q.x * p.y
	return absf(area) * 0.5
