extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Builder := preload("res://scripts/supply_chain_3d/world_builder.gd")
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const Sprites := preload("res://scripts/supply_chain_3d/far_sprites.gd")

class FlatGround extends RefCounted:
	func height(_point: Vector2) -> float: return 34.0
	func gradient(_point: Vector2) -> Vector2: return Vector2.ZERO

func _test_house_height_all_variants_and_lods() -> void:
	var builder := Builder.new()
	builder.ground = FlatGround.new()
	builder.streamed = true
	builder.scenery_ready = true
	builder.tiles = {"test": {"polluters": 0}}
	var standing: Array = []
	for level in range(1, 4):
		for side in [48.96, 50.4, 57.6, 61.2, 72.0]:
			var s := {"iid": "%s:%s" % [level, side], "kind": "house", "tile": "test", "pos": Vector2.ZERO,
				"side": side, "level": level, "yaw": 0.7}
			standing.append(s)
			var frame := builder.standing_frame(s)
			var node := builder.standing_node(s)
			var pair: Dictionary = builder.sprite_pairs.back()
			var visual: MeshInstance3D = pair.near[0]
			var actual := visual.mesh.get_aabb().size * visual.scale
			_check(is_equal_approx(actual.y, 50.0) and is_equal_approx(frame.dimension.y, 50.0),
				"House height: variant %s / footprint %s has a 50u mesh and bounds" % [level, side])
			_check(is_equal_approx(actual.x, Assets.dimensions(frame.key).x * side) and is_equal_approx(actual.z, Assets.dimensions(frame.key).z * side),
				"House height: variant %s / footprint %s retains fitted width and depth" % [level, side])
			_check(pair.far.scale.is_equal_approx(visual.scale) and pair.far.position.is_equal_approx(Sprites.center(frame.key) * visual.scale),
				"House height: individual far card has the mesh scale and anchor")
			_check((pair.near[1] as MeshInstance3D).scale.is_equal_approx(visual.scale), "House height: contour follows the mesh")
			# Keep nodes alive until the lazy medium path has run over every pair.
			node.name = s.iid.validate_node_name()
	builder.active_lod = 1
	builder._sprites_visible = false
	builder._update_asset_tier()
	var far := builder.distant_towns(standing)
	for i in standing.size():
		var s: Dictionary = standing[i]
		var pair: Dictionary = builder.sprite_pairs[i]
		var frame := builder.standing_frame(s)
		var transform: Transform3D = builder.decor_sprite_transforms[frame.key][i % 5]
		_check(pair.medium != null and pair.medium.scale.is_equal_approx(pair.near[0].scale)
			and is_equal_approx(transform.basis.y.length() * Assets.dimensions(frame.key).y, 50.0),
			"House height: streamed medium and baked continent keep the same 50u height")
		_check(transform.origin.is_equal_approx(frame.position + transform.basis * Sprites.center(frame.key)),
			"House height: rotated continent card sits at the scaled mesh centre")
		pair.root.free()
	far.free()

func _test_house_height_excludes_other_buildings() -> void:
	for family in ["towers", "civic_office", "civic_l", "civic_park", "civic_plaza", "warehouse", "farm"]:
		var key := Assets.key_for(family, 1)
		_check(Builder.BuildingScale.for_asset(key, 72.0) == Vector3.ONE * 72.0,
			"House height: %s keeps its authored scale" % family)
