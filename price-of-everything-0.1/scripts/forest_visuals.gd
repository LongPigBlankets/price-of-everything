extends Node2D
## Draws forest buildings as blobby terrain patches instead of small icon slots.

const FOREST_BUILDING_IDS := {"b_015": true, "b_016": true}
const TILE_CENTER := Vector2(270, 240)
const HEX_VERTS: Array[Vector2] = [
	Vector2(135, 0), Vector2(405, 0), Vector2(540, 240),
	Vector2(405, 480), Vector2(135, 480), Vector2(0, 240),
]
const RIVER_POINTS := {
	"C0": Vector2(270, 240),
	"S1": Vector2(390, 120),
	"S2": Vector2(390, 360),
	"S3": Vector2(150, 360),
	"S4": Vector2(150, 120),
	"HSM1": Vector2(270, 0),
	"HSM2": Vector2(472.5, 120),
	"HSM3": Vector2(472.5, 360),
	"HSM4": Vector2(270, 480),
	"HSM5": Vector2(67.5, 360),
	"HSM6": Vector2(67.5, 120),
}

const FOREST_BASE := Color("#0d512b")
const FOREST_DARK := Color("#083b22")
const FOREST_SHADOW := Color(0.02, 0.10, 0.05, 0.28)
const FOREST_ARC := Color("#2d7d3a")
const FOREST_DOT := Color("#0a4325")
const RIVER_SCREEN_CLEARANCE_PX := 5.0
const RIVER_HALF_WIDTH := 7.5
const DOT_SIZE := 2.0
const SOURCE_LAKE_DEFAULT_WIDTH := 200.0
const SOURCE_LAKE_DEFAULT_HEIGHT := 150.0

@onready var terrain_layer: HexMap = get_node_or_null("%TerrainLayer") as HexMap
@onready var river_visuals: Node = get_node_or_null("../RiverVisuals")

var _forests: Dictionary = {}
var _river_paths_by_coord: Dictionary = {}
var _river_cache_ready: bool = false

func on_building_placed(tile_id: String, building_id: String, _recipe_id: String, instance_id: String, coord: Vector2i) -> void:
	if not FOREST_BUILDING_IDS.has(building_id):
		return
	var key: String = instance_id if instance_id != "" else "%s:%s" % [tile_id, building_id]
	_forests[key] = {
		"tile_id": tile_id,
		"building_id": building_id,
		"coord": coord,
	}
	queue_redraw()

func clear_all() -> void:
	_forests.clear()
	_river_paths_by_coord.clear()
	_river_cache_ready = false
	queue_redraw()

func remove_instance(instance_id: String) -> void:
	if not _forests.has(instance_id):
		return
	_forests.erase(instance_id)
	queue_redraw()

func _draw() -> void:
	if terrain_layer == null:
		return
	_ensure_river_cache()
	for instance_key in _forests.keys():
		var instance_id: String = str(instance_key)
		var entry: Dictionary = _forests[instance_id] as Dictionary
		var coord: Vector2i = entry.get("coord", Vector2i(-1, -1))
		if not terrain_layer.tiles.has(coord):
			continue
		_draw_forest_patch(str(instance_id), str(entry.get("tile_id", "")), coord)

func _draw_forest_patch(instance_id: String, tile_id: String, coord: Vector2i) -> void:
	var center: Vector2 = _forest_center(instance_id, tile_id, coord)
	var circles: Array[Dictionary] = _forest_circles(instance_id, tile_id, center)
	var visible_circles: Array[Dictionary] = []
	for circle in circles:
		var pos: Vector2 = circle.get("pos", Vector2.ZERO)
		var radius: float = float(circle.get("r", 0.0))
		if _circle_drawable(pos, radius, coord):
			visible_circles.append(circle)
	if visible_circles.is_empty():
		var fallback_radius: float = 18.0
		if _circle_drawable(center, fallback_radius, coord):
			visible_circles.append({"pos": center, "r": fallback_radius, "color": FOREST_BASE})
	visible_circles.sort_custom(_sort_circle_radius_desc)

	for circle in visible_circles:
		var pos: Vector2 = circle.get("pos", Vector2.ZERO)
		var radius: float = float(circle.get("r", 0.0))
		draw_circle(pos + Vector2(0, 1.6), radius, FOREST_SHADOW)
	for circle in visible_circles:
		var pos: Vector2 = circle.get("pos", Vector2.ZERO)
		var radius: float = float(circle.get("r", 0.0))
		var color: Color = circle.get("color", FOREST_BASE)
		draw_circle(pos, radius, color)

	_draw_highlight_arc(instance_id, visible_circles, coord)
	_draw_edge_dots(instance_id, tile_id, center, visible_circles, coord)

func _forest_center(instance_id: String, tile_id: String, coord: Vector2i) -> Vector2:
	# Delegates to ForestFootprint so the drawn blob and the road/occupancy
	# obstacle disc can never diverge (roads-v2 spec section 1).
	_ensure_river_cache()
	var paths: Array = _river_paths_by_coord.get(coord, [])
	return ForestFootprint._center(instance_id, tile_id, _tile_center(coord), paths, _lake_for_coord(coord))

func _lake_for_coord(coord: Vector2i) -> Dictionary:
	if terrain_layer == null or not terrain_layer.tiles.has(coord):
		return {}
	return RiverGeometry.lake_ellipse(terrain_layer.tiles[coord], terrain_layer.river_properties, _tile_center(coord))

func _sort_circle_radius_desc(a: Dictionary, b: Dictionary) -> bool:
	return float(a.get("r", 0.0)) > float(b.get("r", 0.0))

func _forest_circles(instance_id: String, tile_id: String, center: Vector2) -> Array[Dictionary]:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _seed("%s|%s|lobes" % [instance_id, tile_id])
	var circles: Array[Dictionary] = []
	circles.append({"pos": center, "r": rng.randf_range(11.0, 14.0), "color": FOREST_BASE})
	var phase: float = rng.randf_range(0.0, TAU)
	for i in range(9):
		var angle: float = phase + TAU * float(i) / 9.0 + rng.randf_range(-0.22, 0.22)
		var distance: float = rng.randf_range(8.0, 18.0)
		var radius: float = rng.randf_range(6.0, 10.0)
		var color: Color = FOREST_BASE.lerp(FOREST_DARK, rng.randf_range(0.0, 0.20))
		circles.append({"pos": center + Vector2(cos(angle), sin(angle)) * distance, "r": radius, "color": color})
	for i in range(4):
		var angle: float = phase + TAU * (float(i) + 0.45) / 4.0 + rng.randf_range(-0.20, 0.20)
		var distance: float = rng.randf_range(18.0, 25.0)
		var radius: float = rng.randf_range(4.0, 7.0)
		circles.append({"pos": center + Vector2(cos(angle), sin(angle)) * distance, "r": radius, "color": FOREST_BASE})
	return circles

func _draw_highlight_arc(instance_id: String, circles: Array[Dictionary], coord: Vector2i) -> void:
	if circles.is_empty():
		return
	var circle: Dictionary = circles[0]
	var center: Vector2 = circle.get("pos", Vector2.ZERO)
	var radius: float = maxf(8.0, float(circle.get("r", 18.0)) * 0.70)
	if not _circle_drawable(center, radius + 2.0, coord):
		return
	var start: float = float(_seed(instance_id + "|arc") % 628) / 100.0
	draw_arc(center + Vector2(-1.5, -2.0), radius, start, start + 1.65, 18, FOREST_ARC, 3.0, true)

func _draw_edge_dots(instance_id: String, tile_id: String, center: Vector2, circles: Array[Dictionary], coord: Vector2i) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _seed("%s|%s|dots" % [instance_id, tile_id])
	var tile_center: Vector2 = _tile_center(coord)
	var drawn: int = 0
	for _i in range(24):
		if drawn >= 7:
			break
		var angle: float = rng.randf_range(0.0, TAU)
		var distance: float = rng.randf_range(27.0, 39.0)
		var pos: Vector2 = center + Vector2(cos(angle) * distance, sin(angle) * distance)
		if not _inside_hex(pos, tile_center, 20.0):
			continue
		if not _circle_drawable(pos, DOT_SIZE * 0.5, coord):
			continue
		if _distance_from_blob(pos, circles) < 3.0:
			continue
		var top_left: Vector2 = (pos - Vector2.ONE * (DOT_SIZE * 0.5)).round()
		draw_rect(Rect2(top_left, Vector2(DOT_SIZE, DOT_SIZE)), FOREST_DOT, true)
		drawn += 1

func _distance_from_blob(point: Vector2, circles: Array[Dictionary]) -> float:
	var best: float = INF
	for circle in circles:
		var pos: Vector2 = circle.get("pos", Vector2.ZERO)
		var radius: float = float(circle.get("r", 0.0))
		best = minf(best, point.distance_to(pos) - radius)
	return best

func _circle_drawable(pos: Vector2, radius: float, coord: Vector2i) -> bool:
	if not _inside_hex(pos, _tile_center(coord), 14.0):
		return false
	var clearance: float = radius + RIVER_HALF_WIDTH + _river_clearance_world()
	if _water_clearance_score(pos, coord) < clearance:
		return false
	return _clear_of_source_lake(pos, radius, coord)

func _water_clearance_score(point: Vector2, coord: Vector2i) -> float:
	var best: float = INF
	var paths: Array = _river_paths_by_coord.get(coord, [])
	for path_data in paths:
		var pts: PackedVector2Array = path_data
		for i in range(pts.size() - 1):
			best = minf(best, _distance_to_segment(point, pts[i], pts[i + 1]))
	return best

func _clear_of_source_lake(point: Vector2, radius: float, coord: Vector2i) -> bool:
	if terrain_layer == null or not terrain_layer.tiles.has(coord):
		return true
	var tile_data: Dictionary = terrain_layer.tiles[coord]
	if not bool(tile_data.get("has_river", false)):
		return true
	var river_type: String = str(tile_data.get("river_type", ""))
	if river_type == "" or not terrain_layer.river_properties.has(river_type):
		return true
	var river_data: Dictionary = terrain_layer.river_properties[river_type]
	if str(river_data.get("kind", "")) != "source":
		return true
	var lake_point: String = str(river_data.get("lake_point", "C0"))
	if not RIVER_POINTS.has(lake_point):
		return true
	var lake_offset: Vector2 = RIVER_POINTS[lake_point]
	var lake_center: Vector2 = _tile_center(coord) + lake_offset - TILE_CENTER
	var lake_w: float = _float_or_default(str(river_data.get("lake_width", "")), SOURCE_LAKE_DEFAULT_WIDTH)
	var lake_h: float = _float_or_default(str(river_data.get("lake_height", "")), SOURCE_LAKE_DEFAULT_HEIGHT)
	var clearance: float = _river_clearance_world() + radius
	var dx: float = (point.x - lake_center.x) / (lake_w * 0.5 + clearance)
	var dy: float = (point.y - lake_center.y) / (lake_h * 0.5 + clearance)
	return Vector2(dx, dy).length() >= 1.0

func _ensure_river_cache() -> void:
	if _river_cache_ready:
		return
	if river_visuals == null:
		river_visuals = get_node_or_null("../RiverVisuals")
	_river_paths_by_coord.clear()
	if river_visuals != null and river_visuals.has_method("get_river_polylines"):
		var river_paths: Array = river_visuals.call("get_river_polylines") as Array
		for entry in river_paths:
			var path_entry: Dictionary = entry as Dictionary
			var coord: Vector2i = path_entry.get("coord", Vector2i(-1, -1))
			if not _river_paths_by_coord.has(coord):
				_river_paths_by_coord[coord] = []
			var points: PackedVector2Array = path_entry.get("points", PackedVector2Array())
			_river_paths_by_coord[coord].append(points)
	_river_cache_ready = true

func _inside_hex(point: Vector2, tile_center: Vector2, margin: float) -> bool:
	var local: Vector2 = point - tile_center + TILE_CENTER
	var inset: PackedVector2Array = PackedVector2Array()
	for vertex in HEX_VERTS:
		var from_center: Vector2 = vertex - TILE_CENTER
		inset.append(TILE_CENTER + from_center.normalized() * maxf(0.0, from_center.length() - margin))
	return Geometry2D.is_point_in_polygon(local, inset)

func _tile_center(coord: Vector2i) -> Vector2:
	if terrain_layer == null:
		return Vector2.ZERO
	return terrain_layer.map_to_local(terrain_layer.map_coord_for_tile_coord(coord))

func _river_clearance_world() -> float:
	var zoom_max: float = 1.0
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam != null:
		var value: Variant = cam.get("zoom_max")
		if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
			zoom_max = maxf(float(value), 0.01)
	return RIVER_SCREEN_CLEARANCE_PX / zoom_max

func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var denom: float = ab.length_squared()
	if denom <= 0.0001:
		return point.distance_to(a)
	var t: float = clampf((point - a).dot(ab) / denom, 0.0, 1.0)
	return point.distance_to(a + ab * t)

func _seed(text: String) -> int:
	return abs(hash(text))

func _float_or_default(value: String, fallback: float) -> float:
	if value == "":
		return fallback
	return float(value)
