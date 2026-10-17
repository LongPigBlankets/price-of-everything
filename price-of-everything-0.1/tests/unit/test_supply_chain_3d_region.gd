extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Region := preload("res://scripts/supply_chain_3d/authored_region.gd")
const Profile := preload("res://scripts/supply_chain_3d/authored_road_profile.gd")
const Model := preload("res://scripts/empire_board_model.gd")

func _test_stoneshore_endpoint_topology() -> void:
	var paths := [
		{"id": "main", "points": PackedVector2Array([Vector2(0, 0), Vector2(100, 0)])},
		{"id": "branch", "points": PackedVector2Array([Vector2(50, 1.5), Vector2(50, 30)])},
		{"id": "far", "points": PackedVector2Array([Vector2(80, 3.5), Vector2(80, 30)])},
		{"id": "parallel", "points": PackedVector2Array([Vector2(10, 1.5), Vector2(30, 1.5)]), "layer": 1}]
	_check(Region.join_endpoints(paths) == 1, "Stoneshore: only the endpoint inside the 3u tolerance joins")
	_check(paths[1].points[0] == Vector2(50, 0), "Stoneshore: branch endpoint projects to the trunk")
	_check(paths[0].points.has(Vector2(50, 0)), "Stoneshore: trunk is split for a connected T junction")
	_check(paths[2].points[0] == Vector2(80, 3.5), "Stoneshore: outside-tolerance geometry is retained")
	_check(paths[3].points[0] == Vector2(10, 1.5), "Stoneshore: different elevation layers are not snapped")

func _test_stoneshore_hex_clip() -> void:
	var line := Region.clip_segment(Vector2(-500, 0), Vector2(500, 0), Model.hex_points(Vector2.ZERO))
	_check(line.size() == 2 and line[0].is_equal_approx(Vector2(-270, 0)) and line[1].is_equal_approx(Vector2(270, 0)), "Stoneshore: imported roads stop exactly at the pilot tile boundary")
	_check(Region.clip_segment(Vector2(-500, 400), Vector2(500, 400), Model.hex_points(Vector2.ZERO)).is_empty(), "Stoneshore: outside segments are excluded")
	_check(Region.tile_ids().size() == 5, "Stoneshore: pilot is restricted to five named tiles")

func _test_stoneshore_bridge_profile() -> void:
	var profile := Profile.new()
	var ground := func(p: Vector2) -> float: return 10.0 if absf(p.x) > 20.0 else 0.0
	profile.configure({"tiles": {"test": Vector2.ZERO}, "paths": [{"id": "bridge", "class": "mid",
		"points": PackedVector2Array([Vector2(-100, 0), Vector2(100, 0)])}]},
		{"test": [{"points": PackedVector2Array([Vector2(0, -100), Vector2(0, 100)]), "start_width": 24.0, "end_width": 24.0}]}, ground)
	_check(profile.crossings.size() == 1, "Stoneshore: river crossing becomes one bank-to-bank bridge")
	_check(profile.height_at(Vector2.ZERO) >= 13.0, "Stoneshore: bridge clears the river and joins the bank height")
	_check(is_equal_approx(profile.height_at(Vector2(-100, 0)), 10.0), "Stoneshore: bridge approach returns to the terrain")
	_check(profile.mesh_for("test", ground, Vector2.ZERO).get_surface_count() > 0, "Stoneshore: bridge has a deck underside and guard rails")
	_check(profile.mesh_for("outside", ground, Vector2.ZERO).get_surface_count() == 0, "Stoneshore: bridge structures are clipped to pilot tiles")

func _test_stoneshore_interior_crossings() -> void:
	var roads := Region.split_crossings([
		{"a": Vector2(-20, 0), "b": Vector2(20, 0)},
		{"a": Vector2(0, -20), "b": Vector2(0, 20)},
		{"a": Vector2(10, -20), "b": Vector2(10, 20), "layer": 1}])
	_check(roads.size() == 5, "Stoneshore: at-grade crossing splits both roads, separate layer stays intact")
	var connected := 0
	for road in roads:
		if road.a == Vector2.ZERO or road.b == Vector2.ZERO: connected += 1
	_check(connected == 4, "Stoneshore: all four branches share an exact graph node")

func _test_stoneshore_package_preserves_identical_chunks() -> void:
	var package := preload("res://tools/supply_chain_3d/bake_package.gd")
	var geo := preload("res://scripts/supply_chain_3d/geometry.gd")
	var first := geo.Batch.new()
	first.box(Vector3.ZERO, Vector3.ONE, Color.WHITE)
	var second := geo.Batch.new()
	second.box(Vector3.ZERO, Vector3.ONE, Color.WHITE)
	_check(package.same_payload({"mesh": first.mesh(), "trees": [Vector3.ONE]}, {"mesh": second.mesh(), "trees": [Vector3.ONE]}),
		"Stoneshore: identical tile payloads retain their packaged resources across a regional edit")
	second.box(Vector3.ONE, Vector3.ONE, Color.WHITE)
	_check(not package.same_payload({"mesh": first.mesh()}, {"mesh": second.mesh()}), "Stoneshore: changed geometry cannot reuse an old tile bake")
	_check(not package.same_payload({"trees": [Vector3.ZERO]}, {"trees": [Vector3.ONE]}), "Stoneshore: changed tree placements cannot reuse an old tile bake")

class RegionTerrain extends Node:
	var tiles := {Vector2i(3, 8): {"id": "tile_4_9", "infrastructure_present": []}}
	func id_to_coord(_tid: String) -> Vector2i: return Vector2i(3, 8)

class RegionFootprints extends Node:
	var _placements: Array = []
	func footprint_center_for(_iid: String, _coord: Vector2i) -> Vector2: return Vector2(20, 30)

func _test_stoneshore_scoped_authored_import() -> void:
	var terrain := RegionTerrain.new()
	var document := {"settlements": {"pilot": {"roads": [
		{"id": "visible", "class": "minor", "tiles": ["tile_4_9"], "points": [[-400, 0], [400, 0]]},
		{"id": "locked", "class": "major", "tiles": ["tile_4_9"], "unlockable": true, "points": [[0, -100], [0, 100]]}]}}}
	AuthoredMap.set_document_for_tests(document)
	var outside := {"tile": "tile_9_9", "a": Vector2(400, 0), "b": Vector2(500, 0), "kind": "street"}
	var model := {"tiles": {"tile_4_9": {"center": Vector2.ZERO}, "tile_9_9": {"center": Vector2(600, 0)}},
		"roads": [{"tile": "tile_4_9", "a": Vector2.ZERO, "b": Vector2(100, 0)}, outside.duplicate()],
		"standing": [{"kind": "house", "tile": "tile_4_9"}, {"kind": "house", "tile": "tile_9_9"}], "flows": []}
	Region.apply(model, terrain, null, {}, Callable(), Region.tile_ids())
	_check(model.roads.has(outside), "Stoneshore: roads outside the pilot retain their original geometry")
	_check(model.authored_region.paths.size() == 1 and model.authored_region.paths[0].id == "visible", "Stoneshore: locked roads stay hidden exactly as on the regular map")
	_check(model.standing.size() == 2, "Stoneshore: decorative buildings remain available for frontage fitting")
	_check(AuthoredMap.data() == document, "Stoneshore: importing never mutates the authored document")
	terrain.free()
	AuthoredMap.reset_for_tests()

func _test_stoneshore_npc_footprint_and_port_identity() -> void:
	var terrain := RegionTerrain.new()
	var footprints := RegionFootprints.new()
	footprints._placements = [{"instance_id": "region_test_port", "verts": PackedVector2Array([Vector2(0, 10), Vector2(40, 10), Vector2(40, 50), Vector2(0, 50)])}]
	var saved := BuildingState.buildings.duplicate(true)
	BuildingState.buildings = {"region_test_port": {"building_id": "b_004", "owner": "npc", "tile_id": "tile_4_9", "level": 1}}
	var model := {"standing": [{"iid": "port:tile_4_9", "port_iid": "region_test_port", "kind": "port", "tile": "tile_4_9"}]}
	var count := Region.place_npcs(model, {"tile_4_9": Vector2.ZERO}, terrain, footprints)
	_check(count == 1 and model.standing.size() == 1, "Stoneshore: a trading port is repositioned, not duplicated")
	_check(model.standing[0].pos == Vector2(20, 30), "Stoneshore: NPC position uses the regular map's actual footprint centre")
	_check(model.standing[0].npc and model.standing[0].side > 0, "Stoneshore: mapped NPC retains a usable 3D footprint")
	BuildingState.buildings = saved
	footprints.free(); terrain.free()

func _test_stoneshore_authored_coast_and_harbour() -> void:
	var coast := preload("res://scripts/supply_chain_3d/coast.gd")
	var legacy := preload("res://scripts/empire_board.gd")
	var ground := preload("res://scripts/empire_board_ground.gd")
	var harbour := preload("res://scripts/supply_chain_3d/harbour.gd")
	var center := Vector2(2295, 5760)
	var original := legacy._relief_of("tile_4_10", center).duplicate(true)
	var corrected := coast.relief_of("tile_4_10", center)
	for point in [Vector2(2187.301, 5947.531), Vector2(2085.755, 5852.198), Vector2(2058.021, 5770.514)]:
		_check(not ground.is_water(corrected, point), "Stoneshore: west Old Quarter authored road remains on coastal land")
	_check(legacy._relief_of("tile_4_10", center) == original, "Stoneshore: 3D coast correction leaves regular map relief unchanged")
	var all_layouts: Dictionary = harbour.layouts()
	var directions := {"tile_11_17": Vector2(-0.445, 0.896), "tile_24_7": Vector2(0.602, 0.799), "tile_22_16": Vector2(0.649, 0.761)}
	for tid in directions:
		_check((all_layouts[tid].offshore as Vector2).dot(directions[tid].normalized()) > 0.999, "Stoneshore: " + tid + " uses authored pier orientation even without crane metadata")
	var layout: Dictionary = all_layouts["tile_5_10"]
	_check(layout.quays.size() == 1 and layout.sheds.size() == 2, "Stoneshore: duplicate authored pier records become one quay, with separate sheds")
	var saved := BuildingState.buildings.duplicate(true)
	BuildingState.buildings = {"real_port_instance": {"building_id": "b_004", "owner": "npc", "tile_id": "tile_5_10", "level": 1}}
	var model := {"tiles": {"tile_5_10": {}}, "standing": [
		{"iid": "port:tile_5_10", "port_iid": "port_port_stoneshore", "kind": "port", "tile": "tile_5_10", "pos": Vector2.ZERO},
		{"iid": "real_port_instance", "kind": "building", "internal_name": "port", "tile": "tile_5_10", "pos": Vector2.ONE}], "flows": []}
	harbour.apply(model)
	_check(model.standing.size() == 1 and model.standing[0].iid == "real_port_instance", "Stoneshore: different trade-graph and building IDs resolve to one selectable harbour")
	_check(model.standing[0].pos == layout.bounds.get_center(), "Stoneshore: harbour uses the actual waterfront art location")
	var frame: Dictionary = harbour.frame(model.standing[0], func(_p: Vector2) -> float: return 34.0, Vector2.ZERO)
	var pier: Vector3 = frame.position + frame.harbour_pier_tip
	var dock_hex := Model.hex_points(Vector2(2700, 5520))
	_check(not Geometry2D.is_point_in_polygon(Vector2(pier.x, pier.z), dock_hex), "Stoneshore: Blender pier extends beyond its logical owning tile")
	var assets := preload("res://scripts/supply_chain_3d/assets.gd")
	var metadata: Dictionary = assets.harbour_for(frame.harbour_asset)
	var anchor: Vector3 = frame.position + frame.harbour_transform * harbour.vector3(metadata.anchor)
	_check(Vector2(anchor.x, anchor.z).distance_to(layout.shore_anchor) < 0.01, "Stoneshore: Blender basin starts at the authored waterfront")
	_check(is_equal_approx(anchor.y, ground.SEA_LEVEL) and is_equal_approx(frame.harbour_deck, 35.5), "Stoneshore: ships sit on the sea and quay meets the bank")
	var forward: Vector3 = frame.harbour_transform.basis.x.normalized()
	_check(Vector2(forward.x, forward.z).dot(layout.offshore) > 0.999, "Stoneshore: Blender harbour opens toward the authored sea direction")
	var faces: PackedVector3Array = harbour.picking_shape(frame).get_faces()
	var basin: Vector3 = frame.harbour_basin
	var tip: Vector3 = frame.harbour_pier_tip
	var water_hits := 0
	var pier_hits := 0
	for i in range(0, faces.size(), 3):
		if Geometry3D.segment_intersects_triangle(basin + Vector3.UP * 200, basin - Vector3.UP * 200, faces[i], faces[i + 1], faces[i + 2]) != null: water_hits += 1
		if Geometry3D.segment_intersects_triangle(tip + Vector3.UP * 200, tip - Vector3.UP * 200, faces[i], faces[i + 1], faces[i + 2]) != null: pier_hits += 1
	_check(water_hits == 0, "Stoneshore: Blender export leaves open water in the basin, without a backdrop collider")
	_check(pier_hits > 0, "Stoneshore: the cross-tile Blender pier has an exact collider")

	var shore_line: float = layout.shore_anchor.dot(layout.offshore) - 55.0
	var curved_bank := func(p: Vector2) -> float: return 34.0 if p.dot(layout.offshore) < shore_line else ground.SEA_LEVEL
	var fitted: Dictionary = harbour.frame(model.standing[0], curved_bank, Vector2.ZERO)
	var connected := true
	for xyz in metadata.shore_edge:
		var point: Vector3 = fitted.position + fitted.harbour_transform * harbour.vector3(xyz)
		connected = connected and curved_bank.call(Vector2(point.x, point.z)) > ground.SEA_LEVEL
	_check(connected and fitted.harbour_shore_shift > 0.0 and fitted.harbour_shore_shift < 40.0, "Stoneshore: harbour moves inland just enough to connect its back edge to the coast")

	model.standing.append({"iid": "overlapping_decor", "kind": "house", "tile": "tile_5_11", "pos": layout.bounds.get_center(), "side": 40.0})
	model.standing.append({"iid": "outside_decor", "kind": "house", "tile": "tile_5_11", "pos": layout.bounds.end + Vector2.ONE * 100.0, "side": 40.0})
	model.standing.append({"iid": "real_npc", "kind": "building", "internal_name": "warehouse", "tile": "tile_5_10", "pos": layout.bounds.get_center(), "side": 40.0})
	harbour.apply(model)
	var retained: Array = model.standing.map(func(item: Dictionary) -> String: return str(item.iid))
	_check(not retained.has("overlapping_decor") and retained.has("outside_decor") and retained.has("real_npc"), "Stoneshore: harbour clears only overlapping decoration, including across tile boundaries")

	BuildingState.buildings = saved
