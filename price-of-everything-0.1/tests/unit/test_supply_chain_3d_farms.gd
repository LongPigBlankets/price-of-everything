extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Fields := preload("res://scripts/supply_chain_3d/farm_fields.gd")
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const Builder := preload("res://scripts/supply_chain_3d/world_builder.gd")
const Region := preload("res://scripts/supply_chain_3d/authored_region.gd")

class FieldGround extends RefCounted:
	var roads: Array = []
	func surface_gradient(_p: Vector2) -> Vector2: return Vector2(0.02, 0.0)
	func point(p: Vector2, lift: float = 0.0) -> Vector3: return Vector3(p.x, 40.0 + p.x * 0.02 + lift, p.y)
	func open_water(_p: Vector2) -> bool: return false

func plot(size: Vector2, pos := Vector2.ZERO) -> Dictionary:
	var half := size * 0.5
	return {"iid": "farm", "tile": "test", "kind": "building", "internal_name": "farm", "level": 1,
		"side": Fields.SIDE, "pos": pos, "yaw": 0.0, "footprint": PackedVector2Array([
			pos - half, pos + Vector2(half.x, -half.y), pos + half, pos + Vector2(-half.x, half.y)])}

func _test_farm_growth_repeats_identical_cells() -> void:
	var ground := FieldGround.new()
	var small := Fields.build(ground, "test", [plot(Vector2(100, 80))])
	var large := Fields.build(ground, "test", [plot(Vector2(250, 160))])
	_check(large.poses.size() > small.poses.size() * 3, "Farm: a larger plot adds crop cells")
	var unchanged := true
	for pose in large.poses:
		unchanged = unchanged and (pose as Transform3D).basis.get_scale().is_equal_approx(Vector3.ONE * Fields.SIDE)
		unchanged = unchanged and absf(pose.origin.y - (40.0 + Fields.LIFT + 0.05 + pose.origin.x * 0.02)) < 0.001
	_check(unchanged, "Farm: all copies retain source proportions and follow ground height")
	_check(Builder.standing_key(plot(Vector2(250, 160))) == "farm_building_lvl1", "Farm: plot uses the separate building core for artwork and picking")
	var near := Fields.cells(small, false)
	var medium := Fields.cells(small, true)
	_check(near.multimesh.instance_count == medium.multimesh.instance_count, "Farm: near and medium keep the same row layout")
	_check(near.multimesh.get_instance_transform(0).is_equal_approx(medium.multimesh.get_instance_transform(0)), "Farm: changing LOD does not move or resize crops")
	near.free(); medium.free()

func _test_farm_edges_yard_and_road_clearance() -> void:
	var ground := FieldGround.new()
	ground.roads = [{"a": Vector2(-100, 25), "b": Vector2(100, 25), "widths": [6.0]}]
	var farm := plot(Vector2(150, 100))
	farm.footprint = PackedVector2Array([Vector2(-75, -50), Vector2(75, -50), Vector2(0, 50)])
	var data := Fields.build(ground, "test", [farm])
	var core := Assets.dimensions(Assets.key_for("farm_building", 1)) * Fields.SIDE
	var clear: bool = not data.poses.is_empty()
	for pose in data.poses:
		var p := Vector2(pose.origin.x, pose.origin.z)
		clear = clear and Geometry2D.is_point_in_polygon(p, farm.footprint) and absf(p.y - 25.0) > 9.0
		clear = clear and not Rect2(-Vector2(core.x, core.z) * 0.5, Vector2(core.x, core.z)).grow(3.0).has_point(p)
	_check(clear, "Farm: triangular edges, barn yard and road clearance stay free of crops")
	_check(data.soil.get_surface_count() > 0 and data.far.get_surface_count() > 0, "Farm: brown earth and far rows are baked geometry")
	var colors: PackedColorArray = data.soil.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	_check(colors[0].r > colors[0].g and colors[0].g > colors[0].b, "Farm: exposed soil is brown rather than grass green")
	var normals: PackedVector3Array = data.soil.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	_check(normals[0].y > 0.99, "Farm: exposed earth has upward terrain-following shading normals")
	var notch := PackedVector2Array([Vector2(-10,-10), Vector2(10,-10), Vector2(10,10), Vector2(1,10), Vector2(1,-2), Vector2(-1,-2), Vector2(-1,10), Vector2(-10,10)])
	_check(not Fields.fits(Vector2.ZERO, Vector2(5, 4), notch, Rect2(100, 100, 1, 1)), "Farm: crop cells cannot bridge concave plot notches")

func _test_farm_cells_use_explicit_lods() -> void:
	for family in ["farm_crop_cell", "farm_crop_cell_medium"]:
		var config := ConfigFile.new()
		config.load(Assets.DIRECTORY + Assets.key_for(family, 1) + ".glb.import")
		_check(config.get_value("params", "meshes/generate_lods", true) == false, "Farm: instance scaling cannot trigger premature automatic crop decimation")

func _test_farm_reserves_neighbouring_barns() -> void:
	var a := plot(Vector2(160, 100))
	var b := plot(Vector2(100, 80), Vector2(50, 0))
	b.iid = "neighbour"; b.tile = "next_tile"
	var data := Fields.build(FieldGround.new(), "test", [a, b])
	var clear := true
	for pose in data.poses:
		if Rect2(35, -20, 30, 40).has_point(Vector2(pose.origin.x, pose.origin.z)): clear = false
	_check(clear and not data.poses.is_empty(), "Farm: neighbouring barn yards stay clear even across a tile boundary")

class FarmTerrain extends Node:
	func id_to_coord(_tid: String) -> Vector2i: return Vector2i.ZERO
class FarmLots extends Node:
	var _placements: Array = []
	func footprint_center_for(_iid: String, _coord: Vector2i) -> Vector2: return Vector2.ZERO

func _test_farm_authored_plot_does_not_scale_the_barn() -> void:
	var terrain := FarmTerrain.new()
	var lots := FarmLots.new()
	var saved := BuildingState.buildings
	BuildingState.buildings = {"farm": {"building_id": "b_014", "owner": "npc", "tile_id": "test", "level": 1}}
	var sides: Array = []
	for size in [Vector2(100, 40), Vector2(280, 180)]:
		lots._placements = [{"instance_id": "farm", "verts": plot(size).footprint}]
		var model := {"standing": []}
		Region.place_npcs(model, {"test": Vector2.ZERO}, terrain, lots)
		sides.append(model.standing[0].side)
	_check(sides == [Fields.SIDE, Fields.SIDE], "Farm: authored small and large plots keep exactly the same barn scale")
	BuildingState.buildings = saved
	lots.free(); terrain.free()
