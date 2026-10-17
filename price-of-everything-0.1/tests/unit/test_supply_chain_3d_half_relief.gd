extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const DisplayGround := preload("res://scripts/supply_chain_3d/ground.gd")
const SourceGround := preload("res://scripts/empire_board_ground.gd")
const Relief := preload("res://scripts/supply_chain_3d/relief.gd")
const Halves := preload("res://scripts/supply_chain_3d/half_relief.gd")

func _square(radius: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(-radius,-radius), Vector2(radius,-radius), Vector2(radius,radius), Vector2(-radius,radius)])

func _test_half_relief_terraces_and_regular_map_isolation() -> void:
	var original := [{"b": 4, "p": _square(225)}, {"b": 5, "p": _square(75)}]
	var source := SourceGround.new()
	var display := DisplayGround.new()
	for ground in [source, display]:
		ground.tiles = {"hill": {"center": Vector2.ZERO, "height": 50.0, "water": false}}
		ground.may_be_wet = func(_p: Vector2) -> bool: return false
		ground.bands = original.duplicate(true)
	display.bands.append({"b": 4.5, "p": _square(150)})
	source.setup(); display.setup()
	_check(absf(source.height(Vector2(115,0)) - 66.0) < 0.05 and absf(display.height(Vector2(115,0)) - 71.5) < 0.05,
		"Half relief: level 3.5 creates a physical terrace where the original map stays at level 3")
	_check(is_equal_approx(source.height(Vector2.ZERO), display.height(Vector2.ZERO)), "Half relief: full-level summit height stays unchanged")
	_check(original.size() == 2 and original[0].b is int, "Half relief: source polygons are not mutated")
	_check(is_equal_approx(Relief.height(Relief.band_height(5.5)), 88.0), "Half relief: level 4.5 uses the midpoint of the existing amplified rise")
	var colors := [Color.BLACK, Color.WHITE]
	_check(Halves.color(0.5, colors).is_equal_approx(Color(.5,.5,.5)), "Half relief: intermediate terrain colours interpolate without integer truncation")

func _test_half_relief_shipped_geography_and_fingerprint() -> void:
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Halves.PATH))
	_check(doc.source_sha256 == FileAccess.get_sha256("res://data/hills_baked.json"), "Half relief: derived contours match the current authored map")
	var bands := {}
	var valid := true
	for rec in Halves.polys():
		bands[rec.b] = true
		valid = valid and rec.p.size() >= 3 and fposmod(float(rec.b), 1.0) == 0.5
	_check(valid and bands.size() == 9, "Half relief: existing continent has intermediate contours from level 1.5 through 9.5")
	var cache := preload("res://scripts/supply_chain_3d/bake_cache.gd")
	_check("../../data/supply_chain_half_relief.json" in cache.SOURCES.terrain, "Half relief: changing derived geography invalidates production terrain bakes")

class SingleTerrain extends Node:
	func id_to_coord(tid: String) -> Vector2i:
		return Vector2i.ZERO if tid == "tile_4_10" else Vector2i(-1,-1)
	func map_coord_for_tile_coord(coord: Vector2i) -> Vector2i: return coord
	func map_to_local(_coord: Vector2i) -> Vector2: return Vector2(2700, 5400)

func _test_half_relief_depot_sampler_stays_original() -> void:
	var coast := preload("res://scripts/supply_chain_3d/coast.gd")
	var terrain := SingleTerrain.new()
	var original: RefCounted = coast.ground_for(terrain, {}, {"tile_4_10": 34.0})
	var display: RefCounted = coast.ground_for(terrain, {}, {"tile_4_10": 34.0}, true)
	_check(original.get_script() == SourceGround and display.get_script() == DisplayGround,
		"Half relief: depot seeding keeps the original sampler; the 3D board opts into half contours")
	_check(original != display and coast.ground_for(terrain, {}, {}) == original and coast.ground_for(terrain, {}, {}, true) == display,
		"Half relief: default and 3D ground caches remain separate whichever is requested first")
	_check(original.bands.size() == HillBaked.polys().size() and display.bands.size() > original.bands.size(),
		"Half relief: intermediate bands never enter the depot placement terrain")
	terrain.free()
