class_name RiverGeometry
extends RefCounted
## Single owner of world-space river polylines for roads-v2 (spec 0.1).
## Thin wrapper over SubtileGrid's tile-local sampling — the only
## implementation that handles all four CSV kinds (single/joint/source/merge).
## v1 road_planner's private single-kind copy is the known-buggy one; new code
## must use this. (Full consumer migration of river_visuals/forest_visuals
## happens at v1 deletion; their outputs are cosmetic-only.)

const TILE_CENTER := Vector2(270, 240)

## World-space arm polylines for one tile. An "arm" is one continuous river
## branch; branch tiles (exit_hsm_2 set) yield 2+ arms — principle (a) gives
## each arm its own crossing.
static func arms(tile_data: Dictionary, river_properties: Dictionary, center: Vector2) -> Array:
	if not tile_data.get("has_river", false):
		return []
	var river_type := str(tile_data.get("river_type", ""))
	if river_type == "" or not river_properties.has(river_type):
		return []
	var river_data: Dictionary = river_properties[river_type]
	var out: Array = []
	for local_path in SubtileGrid._river_paths_points(river_data):
		var world := PackedVector2Array()
		for p in local_path:
			world.append(center + p - TILE_CENTER)
		out.append(world)
	return out

## Source-lake ellipse for the tile in world space, or {} when none.
static func lake_ellipse(tile_data: Dictionary, river_properties: Dictionary, center: Vector2) -> Dictionary:
	if not tile_data.get("has_river", false):
		return {}
	var river_type := str(tile_data.get("river_type", ""))
	if river_type == "" or not river_properties.has(river_type):
		return {}
	var river_data: Dictionary = river_properties[river_type]
	if str(river_data.get("kind", "single")) != "source":
		return {}
	var lake_point := str(river_data.get("lake_point", "C0"))
	var lp: Vector2 = SubtileGrid.RIVER_POINTS.get(lake_point, TILE_CENTER)
	var lw := 200.0 if str(river_data.get("lake_width", "")) == "" else float(river_data.get("lake_width"))
	var lh := 150.0 if str(river_data.get("lake_height", "")) == "" else float(river_data.get("lake_height"))
	return {"center": center + lp - TILE_CENTER, "rx": lw * 0.5, "ry": lh * 0.5}

static func arc_length(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(points.size() - 1):
		total += points[i].distance_to(points[i + 1])
	return total

## Point + tangent at a fraction of the polyline's arc length.
static func point_at_fraction(points: PackedVector2Array, fraction: float) -> Dictionary:
	var total := arc_length(points)
	if total <= 0.0 or points.size() < 2:
		return {}
	var target := clampf(fraction, 0.0, 1.0) * total
	var walked := 0.0
	for i in range(points.size() - 1):
		var seg := points[i].distance_to(points[i + 1])
		if walked + seg >= target and seg > 0.0:
			var t := (target - walked) / seg
			return {
				"point": points[i].lerp(points[i + 1], t),
				"tangent": (points[i + 1] - points[i]).normalized(),
			}
		walked += seg
	return {
		"point": points[points.size() - 1],
		"tangent": (points[points.size() - 1] - points[points.size() - 2]).normalized(),
	}
