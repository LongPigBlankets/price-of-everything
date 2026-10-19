extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Builder := preload("res://scripts/supply_chain_3d/world_builder.gd")

func _builder(polluters: int, evening: bool, calm: bool) -> RefCounted:
	var builder: RefCounted = Builder.new()
	builder.flat = true
	builder.lazy_assets = true
	builder.tiles = {"tile_1_1": {"center": Vector2(300, 300), "type": "urban", "polluters": polluters}}
	builder.evening = evening
	builder.calm_scenery = calm
	return builder

## The share of homes lit on the builder's tile, and the yard glows they brought.
func _homes(builder: RefCounted, count: int) -> Dictionary:
	var lit := 0
	for i in count:
		var root: Node3D = builder.standing_node({"iid": "home_%d" % i, "kind": "house", "tile": "tile_1_1",
			"pos": Vector2(300, 300), "side": 40.0, "level": 1})
		root.free()
		if bool(builder.sprite_pairs.back().lit): lit += 1
	return {"share": float(lit) / count, "glows": builder.glows.size()}

func _test_calm_scenery_lights_homes_in_the_evening_only() -> void:
	var day := _homes(_builder(2, false, false), 40)
	var calm_day := _homes(_builder(2, false, true), 40)
	_check(day.share == 1.0 and day.glows == 40, "scenery: every home on a polluted tile is lit by day, each with a yard glow")
	_check(calm_day.share == 0.0 and calm_day.glows == 0, "calm scenery: homes never light up for pollution")
	var evening := _homes(_builder(0, true, false), 300)
	var calm_evening := _homes(_builder(2, true, true), 300)
	_check(evening.share > 0.65 and evening.share < 0.85, "scenery: about three homes in four are lit in the evening")
	_check(calm_evening.share > 0.25 and calm_evening.share < 0.42 and calm_evening.glows == 0,
		"calm scenery: about a third of homes are lit in the evening, with no yard glow on a polluted tile")

func _test_calm_scenery_leaves_works_lit() -> void:
	var builder := _builder(2, false, true)
	var root: Node3D = builder.standing_node({"iid": "store", "kind": "warehouse", "tile": "tile_1_1",
		"pos": Vector2(300, 300), "side": 60.0, "level": 1})
	root.free()
	_check(bool(builder.sprite_pairs.back().lit) and builder.glows.size() == 1,
		"calm scenery: works on a polluted tile stay lit, with their yard glow")

func _test_print_look_globals_are_declared() -> void:
	for global in ["sc3d_print", "sc3d_calm"]:
		_check(ProjectSettings.has_setting("shader_globals/" + global), "print look: shader global %s is declared" % global)
	var include := FileAccess.get_file_as_string("res://scripts/supply_chain_3d/print_look.gdshaderinc")
	for path in ["ground", "road_drawing", "far_sprite", "contour"]:
		var code := FileAccess.get_file_as_string("res://scripts/supply_chain_3d/%s.gdshader" % path)
		_check(code.contains("print_look.gdshaderinc") and code.contains("print_paint("), "print look: %s prints its paint" % path)
	_check(include.contains("global uniform float sc3d_print") and FileAccess.get_file_as_string(
		"res://scripts/supply_chain_3d/building_paint.gdshaderinc").contains("print_paint("), "print look: buildings print their paint")
