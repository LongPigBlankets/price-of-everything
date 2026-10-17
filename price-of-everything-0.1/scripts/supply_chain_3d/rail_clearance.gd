extends RefCounted
## Mandatory roofs for parallel road overlaps and actual building masses. The
## depot proximity preference must not expose these conflicts at ground level.
const Index := preload("res://scripts/supply_chain_3d/road_index.gd")
const Rail := preload("res://scripts/supply_chain_3d/railway.gd")
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const Footprints := preload("res://scripts/supply_chain_3d/building_footprints.gd")
const Far := preload("res://scripts/supply_chain_3d/far_sprites.gd")
var zones: Array=[]
var buckets := {}

static func building_polygons(s: Dictionary, key: String) -> Array:
	return Footprints.rendered(key,s)

func configure(plan: Dictionary, roads: Array, standing: Array, tiles: Dictionary, depots: Array, key_for: Callable) -> void:
	zones.clear();buckets.clear()
	var road_index := Index.segments(roads,24)
	var buildings: Array=[]
	for s in standing:
		if str(s.kind) in ["pylon","port"] or s.has("harbour"):continue
		var key := str(key_for.call(s))
		if key=="" or s.get("decor_family","") in ["civic_grove","civic_park","civic_plaza","civic_pond"]:continue
		buildings.append_array(building_polygons(s,key))
	var building_index := {}
	for i in buildings.size(): Index.insert(building_index,preload("res://scripts/supply_chain_3d/road_placement.gd").polygon_bounds(buildings[i]).grow(Rail.CORRIDOR_WIDTH*.5+2),i)
	for corridor in plan.corridors:
		for i in range(1,corridor.points.size()):
			var a: Vector2=corridor.points[i-1];var b: Vector2=corridor.points[i];var p: Vector2=(a+b)*.5
			# Real working yards remain open; bridges handle roads across them.
			if depots.any(func(d):return Geometry2D.is_point_in_polygon(p,preload("res://scripts/supply_chain_3d/rail_depot.gd").yard_polygon(d))):continue
			var conflict := false
			for ri in Index.query(road_index,Index.bounds(a,b,24)):
				var road: Dictionary=roads[ri]
				if absf((b-a).normalized().dot((road.b-road.a).normalized()))<.95:continue
				if p.distance_to(Geometry2D.get_closest_point_to_segment(p,road.a,road.b))<float(road.half)+Rail.CORRIDOR_WIDTH*.5+2:
					conflict=true;break
			if not conflict:
				for id in Index.query(building_index,Index.bounds(a,b)):
					var polygon: PackedVector2Array=buildings[id]
					if preload("res://scripts/supply_chain_3d/road_placement.gd").distance_to_polygon(a,b,polygon)<Rail.CORRIDOR_WIDTH*.5+2:
						conflict=true;break
			if conflict:
				Index.insert(buckets,Index.bounds(a,b,14),zones.size());zones.append({"a":a,"b":b})

func covered(p: Vector2) -> bool:
	for i in buckets.get(Vector2i((p/Index.CELL).floor()),[]):
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p,zones[i].a,zones[i].b))<14:return true
	return false
