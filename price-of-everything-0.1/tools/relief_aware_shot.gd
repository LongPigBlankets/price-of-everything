extends Node2D
## Fixed UI-hidden Phase-B evidence: steep, occupied higher, empty higher.

const TARGETS := [
	{"name": "steep_multiband", "tile": "tile_14_9", "zoom": 1.50},
]

func _ready() -> void:
	get_viewport().set_disable_input(true)
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	for _i in 150:
		await get_tree().process_frame
	var ui := game.get_node_or_null("UILayer") as CanvasLayer
	if ui != null:
		ui.visible = false
	var grid := game.find_child("HexGridOverlay", true, false) as CanvasItem
	if grid != null:
		grid.visible = false
	MapStyle.set_midcentury(true)
	for _i in 30:
		await get_tree().process_frame
	var terrain := game.get_node("%TerrainLayer") as TileMapLayer
	var camera := get_viewport().get_camera_2d()
	camera.set_process(false)
	camera.set_physics_process(false)
	for target_value in TARGETS:
		var target: Dictionary = target_value
		var coord: Vector2i = terrain.id_to_coord(str(target.tile))
		var position := terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
		await _capture(camera, position, float(target.zoom),
			"/tmp/poe_relief_%s.png" % str(target.name))
	var fabric := game.get_node("UrbanFabricVisuals") as UrbanFabricVisuals
	var capital := fabric.settlement_plan("capital-port")
	if capital == null:
		push_error("relief_aware_shot: Capital SettlementPlan unavailable")
		get_tree().quit(2)
		return
	var base_band := 99
	for band_value in capital.material_relief_bands:
		base_band = mini(base_band, int(band_value))
	var occupied_center := Vector2.INF
	for mass_value in capital.masses:
		var mass: Dictionary = mass_value
		var center := _poly_center(mass.poly)
		if _land_band(center) > base_band:
			occupied_center = center
			break
	if occupied_center == Vector2.INF:
		push_error("relief_aware_shot: no occupied higher plateau")
		get_tree().quit(2)
		return
	await _capture(camera, occupied_center, 2.0,
		"/tmp/poe_relief_higher_plateau_cluster.png")
	var empty_center := Vector2.INF
	for plateau_value in capital.relief_plateaus:
		var plateau: Dictionary = plateau_value
		if int(plateau.band) <= base_band or float(plateau.area) < 1700.0:
			continue
		var near_mass := false
		for mass_value in capital.masses:
			if _poly_center((mass_value as Dictionary).poly).distance_to(
					plateau.center) < 95.0:
				near_mass = true
				break
		if not near_mass:
			empty_center = plateau.center
			break
	if empty_center == Vector2.INF:
		push_error("relief_aware_shot: no deliberately empty higher plateau")
		get_tree().quit(2)
		return
	await _capture(camera, empty_center, 1.7,
		"/tmp/poe_relief_higher_plateau_empty.png")
	var metrics := fabric.metrics()
	var record := {
		"capital": metrics.get("settlement_plan_capital", {}),
		"silkstown": metrics.get("settlement_plan_silkstown", {}),
		"settlements": metrics.get("settlements", {}),
	}
	var errors := PackedStringArray()
	var keys := ["contour_crossing_decorative_mass_count",
		"decorative_fill_relief_shoulder_overlap_area",
		"disconnected_mass_after_relief_count",
		"multi_band_decorative_building_count"]
	for plan_name in ["capital", "silkstown"]:
		var diagnostics: Dictionary = record[plan_name].get("diagnostics", {})
		for key in keys:
			if float(diagnostics.get(key, -1.0)) != 0.0:
				errors.append("%s %s=%s" % [plan_name, key,
					diagnostics.get(key, "missing")])
	for settlement_key in record.settlements:
		var settlement: Dictionary = record.settlements[settlement_key]
		var relief: Dictionary = settlement.get("relief", {})
		if relief.is_empty():
			continue
		for key in keys:
			if float(relief.get(key, -1.0)) != 0.0:
				errors.append("%s %s=%s" % [settlement_key, key,
					relief.get(key, "missing")])
	var file := FileAccess.open("/tmp/poe_relief_metrics.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(record, "  "))
	file.close()
	MapStyle.set_midcentury(false)
	if not errors.is_empty():
		push_error("relief_aware_shot: %s" % "; ".join(errors))
	get_tree().quit(0 if errors.is_empty() else 2)

func _capture(camera: Camera2D, position: Vector2, zoom: float,
		path: String) -> void:
	camera.position = position
	camera.zoom = Vector2(zoom, zoom)
	if "_target_zoom" in camera:
		camera.set("_target_zoom", camera.zoom)
	for _i in 18:
		await get_tree().process_frame
	RenderingServer.force_draw()
	var image := get_viewport().get_texture().get_image()
	var size := Vector2i(mini(960, image.get_width()), mini(540, image.get_height()))
	var origin := Vector2i((image.get_width() - size.x) / 2,
		(image.get_height() - size.y) / 2)
	image.get_region(Rect2i(origin, size)).save_png(path)
	print("[RELIEF SHOT] captured %s" % path)

func _poly_center(poly: PackedVector2Array) -> Vector2:
	var center := Vector2.ZERO
	for point in poly:
		center += point
	return center / maxf(1.0, float(poly.size()))

func _land_band(point: Vector2) -> int:
	var nav := NavGrid.instance()
	var cell := nav.cell_of(point)
	return nav.band(cell.x, cell.y) if nav.water(cell.x, cell.y) == \
		NavGrid.WATER_LAND else -1
