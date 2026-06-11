class_name ForestFootprint
extends RefCounted
## Single source of truth for a forest's physical footprint (spec section 1).
## forest_visuals.gd draws the blob; roads-v2 routing and (later) occupancy
## avoid the SAME disc — both must call this so they can never diverge.
##
## The disc: the seeded centre forest_visuals picks, with radius = max lobe
## reach (distance 25 + lobe radius 7) + 4 u pad = 36 u. Routing adds its own
## FOREST_ROAD_BUFFER on top.

const FOREST_BUILDING_IDS := {"b_015": true, "b_016": true}
const RADIUS := 36.0
const TILE_CENTER := Vector2(270, 240)
const HEX_VERTS: Array[Vector2] = [
	Vector2(135, 0), Vector2(405, 0), Vector2(540, 240),
	Vector2(405, 480), Vector2(135, 480), Vector2(0, 240),
]
## forest_visuals uses RIVER_SCREEN_CLEARANCE_PX / camera zoom_max; the main
## camera's zoom_max is 4.0 — bake that in as a constant so the footprint is
## camera-independent and deterministic.
const RIVER_CLEARANCE := 5.0 / 4.0
const RIVER_HALF_WIDTH := 7.5

static func is_forest(building_id: String) -> bool:
	return FOREST_BUILDING_IDS.has(building_id)

## Deterministic disc for one forest instance. river_paths: world-space
## polylines for the tile (RiverVisuals.get_river_polylines() entries for this
## coord, or [] when none). Mirrors forest_visuals._forest_center exactly.
static func footprint(instance_id: String, tile_id: String, coord: Vector2i, tile_center: Vector2, river_paths: Array, lake: Dictionary) -> Dictionary:
	var center := _center(instance_id, tile_id, tile_center, river_paths, lake)
	return {"center": center, "radius": RADIUS}

static func _center(instance_id: String, tile_id: String, tile_center: Vector2, river_paths: Array, lake: Dictionary) -> Vector2:
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(hash("%s|%s|center" % [instance_id, tile_id]))
	var best := tile_center
	var best_score := -1.0
	for _i in range(28):
		var angle := rng.randf_range(0.0, TAU)
		var distance := sqrt(rng.randf()) * rng.randf_range(32.0, 104.0)
		var candidate := tile_center + Vector2(cos(angle) * distance * 1.10, sin(angle) * distance * 0.84)
		if not _inside_hex(candidate, tile_center, 28.0):
			continue
		var score := _water_clearance(candidate, river_paths)
		if score > best_score:
			best_score = score
			best = candidate
		if _candidate_ok(candidate, river_paths, lake):
			return candidate
	return best

static func _candidate_ok(pos: Vector2, river_paths: Array, lake: Dictionary) -> bool:
	var clearance := 18.0 + RIVER_HALF_WIDTH + RIVER_CLEARANCE
	if _water_clearance(pos, river_paths) < clearance:
		return false
	if lake.is_empty():
		return true
	var rx: float = lake.rx + RIVER_CLEARANCE + 18.0
	var ry: float = lake.ry + RIVER_CLEARANCE + 18.0
	var lc: Vector2 = lake.center
	return Vector2((pos.x - lc.x) / rx, (pos.y - lc.y) / ry).length() >= 1.0

static func _water_clearance(point: Vector2, river_paths: Array) -> float:
	var best := 1e30
	for path_entry in river_paths:
		var pts: PackedVector2Array = path_entry
		for i in range(pts.size() - 1):
			best = minf(best, _dist_to_segment(point, pts[i], pts[i + 1]))
	return best

static func _inside_hex(point: Vector2, tile_center: Vector2, margin: float) -> bool:
	var local := point - tile_center + TILE_CENTER
	var inset := PackedVector2Array()
	for vertex in HEX_VERTS:
		var from_center := vertex - TILE_CENTER
		inset.append(TILE_CENTER + from_center.normalized() * maxf(0.0, from_center.length() - margin))
	return Geometry2D.is_point_in_polygon(local, inset)

static func _dist_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var denom := ab.length_squared()
	if denom <= 0.0001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / denom, 0.0, 1.0)
	return point.distance_to(a + ab * t)
