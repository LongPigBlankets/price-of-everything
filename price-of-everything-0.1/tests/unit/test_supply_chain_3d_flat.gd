extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Builder := preload("res://scripts/supply_chain_3d/world_builder.gd")

## A terrain sampler with real relief, so a flat builder can be told apart from it.
class SlopedGround extends RefCounted:
	var tiles := {}
	func height(p: Vector2) -> float: return 40.0 + p.x * 0.1
	func gradient(_p: Vector2) -> Vector2: return Vector2(0.1, 0.0)

func _builder(flat: bool) -> RefCounted:
	var builder: RefCounted = Builder.new()
	builder.ground = SlopedGround.new()
	builder.tiles = {"tile_1_1": {"center": Vector2(300, 300), "type": "rural"}}
	builder.flat = flat
	return builder

## The Low quality preset: every height on the flat ground, the relief kept for painting only.
func _test_flat_builder_lies_on_flat_ground() -> void:
	var flat: RefCounted = _builder(true)
	var relief: RefCounted = _builder(false)
	var p := Vector2(500, 120)
	_check(flat.ground_height(p) == Builder.FLAT_HEIGHT and flat.natural_height(p) == Builder.FLAT_HEIGHT
		and flat.formation_height(p) == Builder.FLAT_HEIGHT and flat.surface_height(p) == Builder.FLAT_HEIGHT,
		"flat view: ground, natural, formation and surface heights are all the flat ground")
	_check(flat.surface_gradient(p) == Vector2.ZERO and flat.railway_level(p) == 0.0 and flat.railway_ground_height(p) == Builder.FLAT_HEIGHT,
		"flat view: no slope, no mountain level for tunnels, rails on the flat ground")
	_check(flat.relief_height(p) == relief.ground_height(p) and relief.ground_height(p) != Builder.FLAT_HEIGHT,
		"flat view: the map's relief is still there to paint the ground with")
	_check(flat.terrain_key("tile_1_1") != relief.terrain_key("tile_1_1"), "flat view: flat terrain is cached apart from the 3D view's")
	_check(not flat.alignment_seeded() or flat.alignment_input.is_empty(), "flat view: nothing to seed into the road alignment memo")

func _test_flat_builder_aligns_plain_road_copies() -> void:
	var flat: RefCounted = _builder(true)
	var shipped := {"a": Vector2.ZERO, "b": Vector2(100, 0), "level": 1, "road_ha": 50.0, "road_hb": 60.0, "tunnel": true, "serpentine": true}
	var input: Dictionary = flat._flat_alignment_input({"roads": [shipped], "tiles": flat.tiles, "standing": []})
	var copy: Dictionary = input.roads[0]
	_check(not copy.has("road_ha") and not copy.has("road_hb") and not copy.has("tunnel") and not copy.has("serpentine") and copy.a == shipped.a,
		"flat view: roads are aligned without the 3D view's graded heights, tunnels and switchbacks")
	_check(shipped.has("road_ha") and shipped.tunnel, "flat view: the shipped roads keep their engineering for the 3D view")

func _test_flat_builder_shows_models_not_sprite_sheets() -> void:
	var flat: RefCounted = _builder(true)
	flat.base_ready = true
	flat.set_overview_scale(0.05, true)
	_check(not flat._sprites_visible, "flat view: zoomed far out, buildings stay models; no distant sprite sheets are loaded")
