extends Node2D

const RoadPlannerScript := preload("res://scripts/road_planner.gd")
const RegionRoadPlannerScript := preload("res://scripts/region_road_planner.gd")

const USE_REGION_PLANNER := true
const ROAD_COLOR := Color.BLACK

@onready var terrain_layer: HexMap = %TerrainLayer

var _region_city_plan_cache := {}

func _ready() -> void:
	var world_map: Node = get_parent()
	if world_map != null and world_map.has_signal("building_placed"):
		world_map.connect("building_placed", Callable(self, "_on_building_placed"))
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_0:
			var variant: int = RoadPlannerScript.cycle_city_shape_variant()
			print("[RoadVisuals] City shape variant %d/%d" % [variant + 1, RoadPlannerScript.CITY_SHAPE_VARIANT_COUNT])
			queue_redraw()

func _draw() -> void:
	if terrain_layer == null:
		return
	var planner = RoadPlannerScript.new(terrain_layer)
	var drawn_city_ids := {}
	for coord in terrain_layer.tiles:
		var tile_coord: Vector2i = coord
		var tile_data: Dictionary = terrain_layer.tiles[tile_coord]
		if not _tile_has_roads(tile_data):
			continue
		var city_id: String = str(tile_data.get("city_id", "")).strip_edges()
		if city_id != "":
			if drawn_city_ids.has(city_id):
				continue
			drawn_city_ids[city_id] = true
			if USE_REGION_PLANNER:
				_draw_region_plan(_region_plan_for_city(city_id))
				continue
		var plan: Dictionary = planner.build_tile_plan(tile_coord)
		_draw_plan(plan)

func _region_plan_for_city(city_id: String):
	var members: Array[Vector2i] = _city_member_tiles(city_id)
	var cache_key := "%s:%s" % [city_id, _member_signature(members)]
	if _region_city_plan_cache.has(cache_key):
		return _region_city_plan_cache[cache_key]

	var params = _region_params_for_city(city_id, members)
	var planner = RegionRoadPlannerScript.new(terrain_layer)
	var plan = planner.plan(members, params)
	_region_city_plan_cache[cache_key] = plan
	print("[RoadVisuals] Region city plan %s signature=%s edges=%d" % [city_id, plan.signature(), plan.edges.size()])
	return plan

func _draw_region_plan(plan) -> void:
	for edge in plan.edges:
		var path: PackedVector2Array = edge["path"]
		var width: float = float(edge.get("width", RoadPlannerScript.ROAD_WIDTH))
		_draw_path(path, width)

	for junction in plan.junctions:
		var point: Vector2 = junction["point"]
		var radius: float = float(junction.get("radius", RoadPlannerScript.JUNCTION_RADIUS))
		draw_circle(point, radius, ROAD_COLOR)

	for bridge in plan.bridges:
		var point: Vector2 = bridge["point"]
		var tangent: Vector2 = bridge.get("tangent", Vector2.RIGHT)
		_draw_bridge(point, tangent)

func _draw_plan(plan: Dictionary) -> void:
	var edges: Array = plan.get("edges", [])
	for edge in edges:
		var path: PackedVector2Array = edge["path"]
		var width: float = float(edge.get("width", RoadPlannerScript.ROAD_WIDTH))
		_draw_path(path, width)

	var junctions: Array = plan.get("junctions", [])
	for junction in junctions:
		var point: Vector2 = junction["point"]
		var radius: float = float(junction.get("radius", RoadPlannerScript.JUNCTION_RADIUS))
		draw_circle(point, radius, ROAD_COLOR)

	var bridges: Array = plan.get("bridges", [])
	for bridge in bridges:
		var point: Vector2 = bridge["point"]
		var tangent: Vector2 = Vector2.RIGHT
		if bridge.has("tangent"):
			tangent = bridge["tangent"]
		_draw_bridge(point, tangent)

func _draw_path(path: PackedVector2Array, width: float) -> void:
	if path.size() < 2:
		return
	var previous: Vector2 = path[0]
	for i in range(1, path.size()):
		var point: Vector2 = path[i]
		draw_line(previous, point, ROAD_COLOR, width, true)
		previous = point

func _draw_bridge(center: Vector2, tangent: Vector2) -> void:
	if tangent.is_zero_approx():
		tangent = Vector2.RIGHT
	var along: Vector2 = tangent.normalized() * (RoadPlannerScript.BRIDGE_LENGTH * 0.5)
	var across: Vector2 = Vector2(-tangent.y, tangent.x).normalized() * (RoadPlannerScript.BRIDGE_WIDTH * 0.5)
	var points: PackedVector2Array = PackedVector2Array([
		center - along - across,
		center + along - across,
		center + along + across,
		center - along + across,
	])
	draw_colored_polygon(points, ROAD_COLOR)

func _tile_has_roads(tile_data: Dictionary) -> bool:
	var infrastructure: Array = tile_data.get("infrastructure_present", [])
	return infrastructure.has("roads")

func _on_building_placed(_tile_id: String, _building_id: String, _recipe_id: String, _instance_id: String, _coord: Vector2i) -> void:
	_region_city_plan_cache.clear()
	queue_redraw()

func _city_member_tiles(city_id: String) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var city_data: Dictionary = terrain_layer.cities.get(city_id, {})
	var member_ids: Array = city_data.get("member_tiles", [])
	for tile_id_data in member_ids:
		var coord: Vector2i = terrain_layer.id_to_coord(str(tile_id_data))
		if coord != Vector2i(-1, -1) and terrain_layer.tiles.has(coord) and not result.has(coord):
			result.append(coord)

	for coord_data in terrain_layer.tiles:
		var coord: Vector2i = coord_data
		var tile_data: Dictionary = terrain_layer.tiles[coord]
		if str(tile_data.get("city_id", "")).strip_edges() == city_id and not result.has(coord):
			result.append(coord)

	result.sort_custom(_sort_tile_coord)
	return result

func _region_params_for_city(_city_id: String, members: Array[Vector2i]):
	var tier := "dense"
	for coord in members:
		var density := str(terrain_layer.tiles[coord].get("road_density", "")).strip_edges()
		if density != "":
			tier = density
			break

	var params = RegionRoadPlannerScript.RegionParams.new()
	params.density_tier = tier
	match tier:
		"sparse":
			params.beltway_inset_ratio = 0.42
			params.spur_length_ratio = 0.42
			params.spur_stride = 4
			params.trunk_length_ratio = 1.15
			params.trunk_stride = 5
			params.fractal_depth = 2
			params.branch_split_chance = 0.45
			params.branch_continue_chance = 0.08
			params.branch_junction_spacing_ratio = 0.48
			params.core_connector_arm_count = 3
			params.core_connector_drop_count = 0
			params.core_connector_dogleg_count = 1
		"medium":
			params.beltway_inset_ratio = 0.34
			params.spur_length_ratio = 0.48
			params.spur_stride = 3
			params.trunk_length_ratio = 1.35
			params.trunk_stride = 3
			params.fractal_depth = 3
			params.branch_split_chance = 0.58
			params.branch_continue_chance = 0.12
			params.branch_junction_spacing_ratio = 0.44
			params.core_connector_arm_count = 4
			params.core_connector_drop_count = 1
			params.core_connector_dogleg_count = 1
		"dense", _:
			params.beltway_inset_ratio = 0.32
			params.spur_length_ratio = 0.56
			params.spur_stride = 2
			params.trunk_length_ratio = 1.35
			params.trunk_stride = 1
			params.fractal_depth = 3
			params.branch_split_chance = 0.60
			params.branch_continue_chance = 0.10
			params.branch_junction_spacing_ratio = 0.42
			params.core_connector_arm_count = 4
			params.core_connector_drop_count = 1
			params.core_connector_dogleg_count = 1
	params.rng_seed = RegionRoadPlannerScript.hash_region_signature(members)
	return params

func _member_signature(members: Array[Vector2i]) -> String:
	var parts: Array[String] = []
	for coord in members:
		parts.append("%d_%d" % [coord.x, coord.y])
	return "|".join(parts)

func _sort_tile_coord(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x or (a.x == b.x and a.y < b.y)
