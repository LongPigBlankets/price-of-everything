extends Node
## Reads the shipped world snapshot and measures every building's drawn mass, at its shipped size and
## scaled further by --scale, against the roads (paved half and footway), the other works and the
## harbour quays. The shipped size already includes building_scale.gd BUILDINGS_SCALE.
## godot --headless --path . res://tools/supply_chain_3d/trials/works_scale_audit.tscn -- --scale=1.5
const Package := preload("res://tools/supply_chain_3d/bake_package.gd")
const Builder := preload("res://scripts/supply_chain_3d/world_builder.gd")
const Footprints := preload("res://scripts/supply_chain_3d/building_footprints.gd")
const Placement := preload("res://scripts/supply_chain_3d/road_placement.gd")
const Sidewalks := preload("res://scripts/supply_chain_3d/urban_sidewalks.gd")
const Index := preload("res://scripts/supply_chain_3d/road_index.gd")
const Scale := preload("res://scripts/supply_chain_3d/building_scale.gd")

func _ready() -> void:
	var scale := 1.5
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scale="): scale = float(arg.trim_prefix("--scale="))
	var cache := Package.Cache.new()
	cache.enabled = true
	cache.directory = Package.Cache.BUNDLED
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(cache.directory.path_join("manifest.json")))
	var data: Dictionary = cache.read(str(manifest.world_snapshot_key))
	var model: Dictionary = data.get("model", {})
	print("[AUDIT] standing=", model.get("standing", []).size(), " roads=", model.get("roads", []).size())
	var roads := Index.segments(model.roads, 20.0)
	for factor in [1.0, scale]:
		var works: Array = []
		var others: Array = []
		for s in model.standing:
			var item: Dictionary = s.duplicate()
			if str(item.kind) in ["building", "site"] and Scale.is_building(item):
				item.side = float(item.side) * factor
				works.append(item)
			elif str(item.kind) not in ["house", "pylon"]:
				others.append(item)
		var road_hits := 0
		var work_hits := 0
		var quay_hits := 0
		var shown: Array = []
		for i in works.size():
			var s: Dictionary = works[i]
			var shapes := Footprints.rendered(Builder.standing_key(s), s)
			var hit_road := false
			for poly in shapes:
				for k in Index.query(roads, Placement.polygon_bounds(poly).grow(20.0)):
					var road: Dictionary = model.roads[k]
					if str(road.get("source", "")).begins_with("access:"): continue
					if Placement.distance_to_polygon(road.a, road.b, poly) < float(road.get("widths", [5.0])[0]) + Sidewalks.width(road):
						hit_road = true
			if hit_road:
				road_hits += 1
				if shown.size() < 12: shown.append("%s@%s" % [s.get("internal_name", ""), s.tile])
			for j in range(i + 1, works.size()):
				for mine in shapes:
					for theirs in Footprints.rendered(Builder.standing_key(works[j]), works[j]):
						if not Geometry2D.intersect_polygons(mine, theirs).is_empty(): work_hits += 1
			for o in others:
				var quays: Array = []
				if o.has("harbour"): quays = [o.harbour.main_quay] + Array(o.harbour.quays)
				for q in quays:
					for mine in shapes:
						if not Geometry2D.intersect_polygons(mine, q).is_empty(): quay_hits += 1
		print("[AUDIT] scale=", factor, " works=", works.size(), " on a road=", road_hits, " overlapping another works=", work_hits, " on a quay=", quay_hits, " e.g. ", shown)
	_grow_to_fit(model, roads, scale)
	get_tree().quit()

## Each works as large as it stays clear of roads and of the works already grown, up to `top`.
func _grow_to_fit(model: Dictionary, roads: Dictionary, top: float) -> void:
	var steps := [top]
	var f := top - 0.05
	while f > 1.0 + 0.001:
		steps.append(snappedf(f, 0.01)); f -= 0.05
	steps.append(1.0)
	var placed: Array = []
	var hist := {}
	var works: Array = model.standing.filter(func(s: Dictionary) -> bool: return Scale.is_building(s))
	for s in works:
		var chosen := 1.0
		for factor in steps:
			var item: Dictionary = s.duplicate()
			item.side = float(s.side) * factor
			var shapes := Footprints.rendered(Builder.standing_key(item), item)
			if _clear(shapes, model, roads, placed):
				chosen = factor
				break
		var item: Dictionary = s.duplicate()
		item.side = float(s.side) * chosen
		placed.append_array(Footprints.rendered(Builder.standing_key(item), item))
		var bucket := "1.5" if chosen >= top - 0.001 else ("1.25-1.45" if chosen >= 1.25 else ("1.05-1.2" if chosen > 1.0 else "1.0"))
		hist[bucket] = int(hist.get(bucket, 0)) + 1
	print("[GROW] up to ", top, ": ", hist)

func _clear(shapes: Array, model: Dictionary, roads: Dictionary, placed: Array) -> bool:
	for poly in shapes:
		for k in Index.query(roads, Placement.polygon_bounds(poly).grow(20.0)):
			var road: Dictionary = model.roads[k]
			if str(road.get("source", "")).begins_with("access:"): continue
			if Placement.distance_to_polygon(road.a, road.b, poly) < float(road.get("widths", [5.0])[0]) + Sidewalks.width(road): return false
		for other in placed:
			if not Geometry2D.intersect_polygons(poly, other).is_empty(): return false
	return true
