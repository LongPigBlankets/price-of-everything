extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Queries := preload("res://scripts/supply_chain_3d/layout_queries.gd")
const Builder := preload("res://scripts/supply_chain_3d/world_builder.gd")
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const Sprites := preload("res://scripts/supply_chain_3d/far_sprites.gd")

class StoredBakes extends "res://scripts/supply_chain_3d/bake_cache.gd":
	var records := {}
	func read(key: String) -> Dictionary: return records.get(key, {}).duplicate(true)
	func write(key: String, data: Dictionary) -> void:
		records[key] = data.duplicate(true)
		writes += 1

class Ground extends RefCounted:
	var tiles := {}
	var bands := []
	var lakes := []
	var rivers := {}

func _test_startup_layout_query_portability() -> void:
	var cache := StoredBakes.new()
	var original_relief: Dictionary = Queries.Landscape._relief_cache.duplicate(true)
	var original_geography: String = Queries._relief_geography
	var water_a := func(_tile: String, _p: Vector2) -> bool: return false
	var water_b := func(_tile: String, _p: Vector2) -> bool: return true
	var first := Queries.new()
	first.prepare(cache, ["same geography"], water_a)
	var cost_key := "tile|(100, 200)|river_hash|" + str(water_a.hash())
	var shore_prefix := str(["tile", Vector2(12, 34), [Vector2(56, 78)], []]).trim_suffix("]")
	var shore_key := shore_prefix + ", " + str(water_a.hash()) + "]"
	var path := PackedVector2Array([Vector2(12, 34), Vector2(56, 78)])
	Queries.Model._street_costs[cost_key] = {"edge": 500.0}
	Queries.Model._shore_streets[shore_key] = path
	Queries.Model.Streets._paths["tile|start|end"] = ["start", "junction", "end"]
	Queries.Landscape._relief_cache.tile = {"sea": [], "land": [{"b": 2, "p": path}], "lakes": []}
	first.finish(cache)
	_check(not Queries.Model._street_costs.has(cost_key) and not Queries.Model._shore_streets.has(shore_key),
		"3D startup: transient callable keys are removed after collecting geographical queries")
	var second := Queries.new()
	second.prepare(cache, ["same geography"], water_b)
	_check(Queries.Landscape._relief_cache.get("tile", {}).get("land", []) == [{"b": 2, "p": path}],
		"3D startup: clipped relief is restored from the package before checking building plots")
	_check(second.key == first.key and Queries.Model._street_costs.get("tile|(100, 200)|river_hash|" + str(water_b.hash())) == {"edge": 500.0},
		"3D startup: packaged street costs survive a different process/callable identity")
	_check(Queries.Model._shore_streets.get(shore_prefix + ", " + str(water_b.hash()) + "]") == path,
		"3D startup: shore paths preserve every query argument while rebinding the callable suffix")
	_check(Queries.Model.Streets._paths.get("tile|start|end") == ["start", "junction", "end"],
		"3D startup: the shipped layout restores street routes without rerunning pathfinding")
	_check(not Queries.Model._shore_streets.has(str(["tile", Vector2(99, 34), [Vector2(56, 78)], [], water_b.hash()])),
		"3D startup: moving a plot cannot reuse a shore path from a different layout")
	second.finish(cache)
	_check(cache.writes == 1, "3D startup: a cache hit does not rewrite the layout resource")
	var changed := Queries.new()
	changed.prepare(cache, ["changed geography"], water_b)
	_check(changed.key != first.key and changed.data.is_empty(), "3D startup: changed geography rejects stored queries")
	_check(Queries.Landscape._relief_cache.is_empty(), "3D startup: changed geography cannot retain another map's clipped coastline")
	changed.finish(cache)
	Queries.Landscape._relief_cache = original_relief
	Queries._relief_geography = original_geography

func _test_startup_bake_asset_dependencies() -> void:
	var key := Assets.key_for("industrial_factory", 1)
	var original := Assets._manifest.duplicate(true)
	var builder := Builder.new()
	builder.ground = Ground.new()
	builder.tiles = {"tile": {"center": Vector2.ZERO, "type": "rural"}}
	var model := {"standing": [{"iid": "factory", "kind": "building", "internal_name": "industrial_factory",
		"tile": "tile", "pos": Vector2.ZERO, "side": 72.0, "level": 1}]}
	builder.configure_bakes(model)
	var scenery := builder._scenery_key
	var continent := builder._continent_key
	Assets._manifest["unused_new_building_lvl1"] = {"width": 20, "height": 30, "depth": 40}
	Assets._manifest[key]["triangles"] = 999999
	builder.configure_bakes(model)
	_check(builder._scenery_key == scenery and builder._continent_key == continent,
		"3D startup: unused assets and mesh/artwork-only metadata do not invalidate the continent")
	Assets._manifest[key].height = float(Assets._manifest[key].height) + 1.0
	builder.configure_bakes(model)
	_check(builder._scenery_key != scenery and builder._continent_key != continent,
		"3D startup: changing the dimensions of a placed building invalidates its baked bounds")
	Assets._manifest = original
	var entry := Sprites.entry(key).duplicate(true)
	Sprites._manifest[key].center = [1.0, 2.0, 3.0]
	builder.configure_bakes(model)
	_check(builder._scenery_key == scenery and builder._continent_key != continent,
		"3D startup: changed sprite anchoring invalidates the backdrop without rebaking scenery")
	Sprites._manifest[key] = entry
