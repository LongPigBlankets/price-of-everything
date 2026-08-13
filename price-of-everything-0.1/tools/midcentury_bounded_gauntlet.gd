extends Node2D
## One deterministic, UI-hidden evidence run for the bounded mid-century pass.

const SHOTS := {
	"pepper": {"tiles": ["tile_5_4", "tile_6_5"], "zoom": 1.18},
	"klade": {"tiles": ["tile_2_4", "tile_3_3"], "zoom": 1.18},
	"arin_north": {"tiles": ["tile_9_16", "tile_10_16"], "zoom": 1.05},
	"capital": {"tiles": ["tile_23_8", "tile_24_8", "tile_25_9"], "zoom": 0.74},
	"stoneshore": {"tiles": ["tile_4_9", "tile_4_10", "tile_5_10"], "zoom": 0.90},
	"rural": {"tiles": ["tile_23_14", "tile_23_15"], "zoom": 1.10},
	"high_relief": {"tiles": ["tile_14_9"], "zoom": 1.45},
}

var _game: Node
var _terrain: TileMapLayer
var _camera: Camera2D
var _fabric: UrbanFabricVisuals
var _buildings: Node

func _ready() -> void:
	get_viewport().set_disable_input(true)
	_game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_game)
	for _i in 150:
		await get_tree().process_frame
	_terrain = _game.get_node("%TerrainLayer") as TileMapLayer
	_camera = get_viewport().get_camera_2d()
	_fabric = _game.find_child("UrbanFabricVisuals", true, false) as UrbanFabricVisuals
	_buildings = _game.find_child("BuildingVisuals", true, false)
	var ui := _game.get_node_or_null("UILayer") as CanvasLayer
	if ui != null:
		ui.visible = false
	var grid := _game.find_child("HexGridOverlay", true, false) as CanvasItem
	if grid != null:
		grid.visible = false
	_camera.set_process(false)
	_camera.set_physics_process(false)
	if "edge_pan_enabled" in _camera:
		_camera.set("edge_pan_enabled", false)
	MapStyle.set_midcentury(true)
	for _i in 30:
		await get_tree().process_frame

	for name_value in SHOTS:
		var name := str(name_value)
		var shot: Dictionary = SHOTS[name]
		await _capture(_center(shot.tiles), float(shot.zoom),
			"/tmp/poe_bounded_%s.png" % name)

	var ports := _game.find_child("PortVisuals", true, false)
	var port_plans: Array = ports.midcentury_plans() if ports != null and \
		ports.has_method("midcentury_plans") else []
	var port_center := _tile_position("tile_5_10")
	if not port_plans.is_empty():
		port_center = (port_plans[0] as Dictionary).position
	await _capture(port_center, 1.55, "/tmp/poe_bounded_port.png")

	var before_version := int(_buildings.footprint_version)
	_buildings.on_building_placed("tile_10_16", "b_002", "",
		"bounded_dense_player", _terrain.id_to_coord("tile_10_16"))
	for _i in 2:
		await get_tree().process_frame
	var dense_collision := _fabric.gameplay_collision_snapshot()
	await _capture(_tile_position("tile_10_16"), 1.50,
		"/tmp/poe_bounded_player_dense.png")
	_buildings.on_building_placed("tile_23_15", "b_002", "",
		"bounded_spill_player", _terrain.id_to_coord("tile_23_15"))
	for _i in 2:
		await get_tree().process_frame
	var spill_collision := _fabric.gameplay_collision_snapshot()
	await _capture(_tile_position("tile_23_15"), 1.50,
		"/tmp/poe_bounded_player_spill.png")

	var wide := _world_bounds()
	var viewport_size := get_viewport().get_visible_rect().size
	var wide_zoom := minf(viewport_size.x / (wide.size.x + 1200.0),
		viewport_size.y / (wide.size.y + 1200.0))
	await _capture(wide.get_center(), wide_zoom, "/tmp/poe_bounded_wide.png",
		Vector2i(1280, 720))

	var metrics := _fabric.metrics()
	var port_audit := _port_audit(port_plans)
	var record := {
		"shots": SHOTS,
		"fabric": metrics,
		"explicit_profiles": {
			"tile_5_4": (metrics.get("tile_profiles", {}) as Dictionary).get("tile_5_4", ""),
			"tile_2_4": (metrics.get("tile_profiles", {}) as Dictionary).get("tile_2_4", ""),
		},
		"collision": {
			"before_version": before_version,
			"after_version": int(_buildings.footprint_version),
			"dense": dense_collision,
			"rural_spill": spill_collision,
		},
		"port": port_audit,
		"wide_zoom": wide_zoom,
	}
	var out := FileAccess.open("/tmp/poe_bounded_metrics.json", FileAccess.WRITE)
	if out != null:
		out.store_string(JSON.stringify(record, "  "))
		out.close()
	var failures: Array[String] = []
	if str(record.explicit_profiles["tile_5_4"]) != "small_town" or \
			str(record.explicit_profiles["tile_2_4"]) != "small_town":
		failures.append("Pepper and Klade must use explicit small_town profiles")
	for collision_value in [dense_collision, spill_collision]:
		var collision: Dictionary = collision_value
		if int(collision.get("opaque_overlap_count", -1)) != 0:
			failures.append("player/decorative opaque overlap survived")
	if int(_buildings.footprint_version) <= before_version:
		failures.append("placement did not advance footprint version")
	print("[BOUNDED GAUNTLET] captures complete; failures=%s" % str(failures))
	MapStyle.set_midcentury(false)
	_game.queue_free()
	for _i in 8:
		await get_tree().process_frame
	RenderingServer.force_draw()
	get_tree().quit(0 if failures.is_empty() else 2)

func _center(tile_ids: Array) -> Vector2:
	var total := Vector2.ZERO
	for tile_id in tile_ids:
		total += _tile_position(str(tile_id))
	return total / maxf(1.0, float(tile_ids.size()))

func _tile_position(tile_id: String) -> Vector2:
	var coord: Vector2i = _terrain.id_to_coord(tile_id)
	return _terrain.map_to_local(_terrain.map_coord_for_tile_coord(coord))

func _capture(position: Vector2, zoom: float, path: String,
		size: Vector2i = Vector2i(960, 540)) -> void:
	_camera.position = position
	_camera.zoom = Vector2(zoom, zoom)
	if "_target_zoom" in _camera:
		_camera.set("_target_zoom", _camera.zoom)
	for _i in 18:
		await get_tree().process_frame
	RenderingServer.force_draw()
	var image := get_viewport().get_texture().get_image()
	var crop_size := Vector2i(mini(size.x, image.get_width()),
		mini(size.y, image.get_height()))
	var origin := Vector2i((image.get_width() - crop_size.x) / 2,
		(image.get_height() - crop_size.y) / 2)
	image.get_region(Rect2i(origin, crop_size)).save_png(path)
	print("[BOUNDED GAUNTLET] %s" % path)

func _world_bounds() -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for coord_value in _terrain.tiles:
		var point := _terrain.map_to_local(_terrain.map_coord_for_tile_coord(coord_value))
		lo = lo.min(point)
		hi = hi.max(point)
	return Rect2(lo, hi - lo)

func _port_audit(plans: Array) -> Dictionary:
	var records: Array = []
	for plan_value in plans:
		var plan: Dictionary = plan_value
		var basin_overlap := 0.0
		for opaque_value in (plan.land_polygons as Array) + \
				(plan.deck_polygons as Array) + (plan.container_polygons as Array):
			basin_overlap += _overlap_area(opaque_value, plan.basin_polygon)
		records.append({
			"tile_id": plan.tile_id,
			"crane_count": (plan.crane_sites as Array).size(),
			"crane_arms": (plan.crane_sites as Array).map(func(site: Dictionary):
				return str(site.arm)),
			"basin_water_coverage": float(plan.basin_water_coverage),
			"basin_opaque_overlap_area": basin_overlap,
			"container_count": (plan.container_polygons as Array).size(),
			"road_access": (plan.road_access as PackedVector2Array).size() == 2,
			"angle": float(plan.angle),
		})
	return {"catalog_port_count": Catalog.all_ports().size(),
		"valid_plan_count": plans.size(), "plans": records,
		"hard_gate_passes": plans.size() == Catalog.all_ports().size()}

func _overlap_area(a_value: Variant, b_value: Variant) -> float:
	var area := 0.0
	for piece_value in Geometry2D.intersect_polygons(a_value, b_value):
		var piece: PackedVector2Array = piece_value
		var signed := 0.0
		for i in piece.size():
			var p := piece[i]
			var q := piece[(i + 1) % piece.size()]
			signed += p.x * q.y - q.x * p.y
		area += absf(signed) * 0.5
	return area
