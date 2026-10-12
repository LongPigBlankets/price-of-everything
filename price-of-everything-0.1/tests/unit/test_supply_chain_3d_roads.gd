extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Index := preload("res://scripts/supply_chain_3d/road_index.gd")
const Region := preload("res://scripts/supply_chain_3d/authored_region.gd")
const Placement := preload("res://scripts/supply_chain_3d/road_placement.gd")
const Profile := preload("res://scripts/supply_chain_3d/authored_road_profile.gd")

class RoadTerrain extends Node:
	var tiles := {Vector2i.ZERO: {"id": "test", "infrastructure_present": []}}

func _test_road_rollout_cached_unlocks() -> void:
	var terrain := RoadTerrain.new()
	AuthoredMap.set_document_for_tests({"settlements": {"test": {"roads": [
		{"id": "always", "class": "minor", "tiles": ["test"], "points": [[-50, 0], [50, 0]]},
		{"id": "locked", "class": "minor", "tiles": ["test"], "unlockable": true, "points": [[0, -50], [0, 50]]}]}}})
	var model := {"tiles": {"test": {"center": Vector2.ZERO}}, "standing": [], "roads": [], "flows": []}
	var prepared := {}
	Region.apply(model, terrain, null, prepared)
	var key: String = prepared.authored_network.key
	var roads: Array = model.roads.duplicate(true)
	_check(model.authored_region.global_paths == 1, "road_rollout: locked authored roads stay hidden")
	Region.apply(model, terrain, null, prepared)
	_check(prepared.authored_network.key == key and model.roads == roads, "road_rollout: the prepared network is reusable without changing geometry")
	terrain.tiles[Vector2i.ZERO].infrastructure_present = ["roads"]
	Region.apply(model, terrain, null, prepared)
	_check(prepared.authored_network.key != key and model.authored_region.global_paths == 2, "road_rollout: unlocking roads invalidates the prepared graph")
	terrain.free()
	AuthoredMap.reset_for_tests()

func _test_road_rollout_spatial_topology() -> void:
	var paths := [
		{"id": "a", "points": PackedVector2Array([Vector2(-65, -65), Vector2(-65, -100)])},
		{"id": "b", "points": PackedVector2Array([Vector2(-62.5, -65), Vector2(-20, -120)])},
		{"id": "c", "points": PackedVector2Array([Vector2(-60, -65), Vector2(0, -120)])}]
	var original := paths.duplicate(true)
	Index.join(paths)
	for i in paths.size():
		_check((paths[i].points[0] as Vector2).distance_to(original[i].points[0]) <= 3.0, "road_rollout: endpoint clusters cannot move a point beyond the 3u tolerance")
	_check(paths[0].points[0] == paths[1].points[0], "road_rollout: spatial joins work across negative-coordinate bucket boundaries")
	_check(paths[2].points[0] != paths[0].points[0], "road_rollout: close-point chains do not merge distant endpoints")
	_check(not Index.safe_join(Vector2.ZERO, Vector2.ONE, func(p: Vector2) -> float: return 24.0 if p.x > 0.25 else 30.0), "road_rollout: short gaps across water are not welded")
	_check(not Index.safe_join(Vector2.ZERO, Vector2.ONE, func(p: Vector2) -> float: return 30.0 + p.x * 10.0), "road_rollout: short gaps across a cliff are not welded")

func _test_road_rollout_global_boundary() -> void:
	var paths := [{"id": "main", "class": "mid", "layer": 0, "points": PackedVector2Array([Vector2(0, 120), Vector2(405, 120)])},
		{"id": "branch", "class": "minor", "layer": 0, "points": PackedVector2Array([Vector2(201, 121.5), Vector2(201, 180)])}]
	var compiled := Region.compile(paths, {"left": Vector2.ZERO, "right": Vector2(405, 240)})
	_check(compiled.joined == 1, "road_rollout: boundary branches join before tile clipping")
	var left_end := false
	var right_start := false
	for road in compiled.roads:
		if road.source != "main": continue
		if road.tile == "left" and road.b.is_equal_approx(Vector2(202.5, 120)): left_end = true
		if road.tile == "right" and road.a.is_equal_approx(Vector2(202.5, 120)): right_start = true
	_check(left_end and right_start, "road_rollout: neighbouring tiles meet at the exact same boundary coordinate")
	_check(paths[1].points[0] == Vector2(201, 121.5), "road_rollout: compilation leaves authored source geometry untouched")

func _test_road_rollout_frontage_and_access() -> void:
	var model := {"tiles": {"t": {"center": Vector2.ZERO}}, "authored_region": {"tiles": {"t": Vector2.ZERO}, "paths": []},
		"roads": [{"a": Vector2(-150, 0), "b": Vector2(150, 0), "tile": "t", "widths": [6.0, 5.0, 4.0, 3.0], "layer": 0}],
		"standing": [{"iid": "house", "kind": "house", "tile": "t", "pos": Vector2.ZERO, "side": 25.0}]}
	var initial := model.duplicate(true)
	var prepared := {}
	var fitter := Placement.new()
	fitter.fit(model, func(_p: Vector2) -> float: return 40.0, func(_p: Vector2) -> bool: return false,
		func(_s: Dictionary) -> String: return "house_lvl1", {}, prepared)
	_check(model.standing.size() == 1 and model.standing[0].pos != Vector2.ZERO, "road_rollout: decoration moves off the road rather than overlapping it")
	var poly := fitter.footprint(model.standing[0])
	_check(Placement.distance_to_polygon(Vector2(-150, 0), Vector2(150, 0), poly) >= 10.0, "road_rollout: frontage clears road casing and setback")
	_check(model.authored_region.frontage.access_roads == 1 and model.standing[0].has("entrance"), "road_rollout: a dry access road connects the building door")
	var branch: Dictionary = model.roads[-1]
	var junctions := 0
	for road in model.roads:
		if road.a.is_equal_approx(branch.b) or road.b.is_equal_approx(branch.b): junctions += 1
	_check(junctions >= 3, "road_rollout: access road splits its receiving street into a connected T")
	Placement.new().fit(initial, func(_p: Vector2) -> float: return 40.0, func(_p: Vector2) -> bool: return false,
		func(_s: Dictionary) -> String: return "house_lvl1", {}, prepared)
	_check(initial == model, "road_rollout: a cached frontage layout restores identical roads, entrances and decoration")
	var wet_model := {"tiles": model.tiles, "authored_region": {"tiles": {"t": Vector2.ZERO}, "paths": []}, "roads": [model.roads[0]],
		"standing": [{"iid": "wet", "kind": "house", "tile": "t", "pos": Vector2.ZERO, "side": 25.0}]}
	Placement.new().fit(wet_model, func(_p: Vector2) -> float: return 40.0, func(_p: Vector2) -> bool: return true,
		func(_s: Dictionary) -> String: return "house_lvl1")
	_check(wet_model.standing.is_empty(), "road_rollout: an impossible decorative plot is omitted instead of placed on water")

func _test_road_rollout_bridge_cache() -> void:
	var data := {"tiles": {"t": Vector2.ZERO}, "paths": [{"id": "annotated", "class": "minor",
		"points": PackedVector2Array([Vector2(-90, 0), Vector2(90, 0)]), "bridges": [{"point": Vector2.ZERO}]}]}
	var ground := func(_p: Vector2) -> float: return 40.0
	var profile := Profile.new()
	profile.configure(data, {}, ground)
	_check(profile.crossings.size() == 1, "road_rollout: authored bridge hints survive narrow or absent river samples")
	var restored := Profile.new()
	restored.restore(profile.packed())
	_check(restored.height_at(Vector2.ZERO) == profile.height_at(Vector2.ZERO), "road_rollout: cached road profiles restore the same bridge heights")
	_check(restored.mesh_for("t", ground, Vector2.ZERO).get_surface_count() > 0, "road_rollout: cached profiles reconstruct the per-tile bridge index")
	profile.configure(data, {}, ground, func(p: Vector2) -> bool: return p.x > -10.0)
	_check(profile.crossings.is_empty() and profile.unresolved.size() == 1, "road_rollout: a road ending in open water is reported instead of inventing a half bridge")
	data.paths = [{"id": "left", "class": "minor", "points": PackedVector2Array([Vector2(-90, 0), Vector2.ZERO])},
		{"id": "right", "class": "minor", "points": PackedVector2Array([Vector2.ZERO, Vector2(90, 0)])}]
	profile.configure(data, {}, ground, func(p: Vector2) -> bool: return absf(p.x) < 20.0)
	_check(profile.unresolved.is_empty() and profile.crossings.size() == 1, "road_rollout: connected half-strokes form one complete bank-to-bank bridge")
	_check(profile.height_at(Vector2.ZERO) >= 45.0, "road_rollout: the shared midpoint stays at bridge-deck height")

func _test_road_rollout_goods_follow_graph() -> void:
	var model := {"standing": [{"iid": "works", "entrance": Vector2.ZERO}, {"iid": "store", "entrance": Vector2(100, 100)}],
		"authored_region": {}, "flows": [{"mode": "roads", "road_ends": ["works", "store"],
			"pts": [{"p": Vector2(5, 5), "tile": "t"}, {"p": Vector2(95, 95), "tile": "t"}]}]}
	Region.reroute_flows(model, {"t": Vector2.ZERO}, [{"a": Vector2.ZERO, "b": Vector2(100, 0)}, {"a": Vector2(100, 0), "b": Vector2(100, 100)}])
	_check(model.flows.size() == 1 and model.flows[0].pts.size() == 3, "road_rollout: goods follow the L-shaped road graph instead of a direct diagonal")
	_check(model.flows[0].pts[0].p == Vector2.ZERO and model.flows[0].pts[-1].p == Vector2(100, 100), "road_rollout: goods use the new building entrances")
	Region.reroute_flows(model, {"t": Vector2.ZERO}, [])
	_check(model.flows.is_empty(), "road_rollout: no road icons float along the removed legacy grid when no road exists")

func _test_road_rollout_rotated_visibility() -> void:
	var builder := preload("res://scripts/supply_chain_3d/world_builder.gd")
	var dimension := Vector3(80, 12, 10)
	var box := AABB(-dimension * 0.5, dimension)
	var contains := true
	for angle in [PI / 2.0, PI / 3.0]:
		var basis := Basis(Vector3.UP, angle)
		var visible := builder._sprite_view_bounds(Vector3.ZERO, builder.rotated_extent(dimension, basis))
		for i in 8: contains = contains and visible.has_point(basis * box.get_endpoint(i))
	_check(contains, "road_rollout: rotated narrow buildings retain every corner inside baked visibility bounds")

func _test_road_rollout_cached_snapped_entrances() -> void:
	var model := {"tiles": {"t": {"center": Vector2.ZERO}}, "authored_region": {"tiles": {"t": Vector2.ZERO}, "paths": []},
		"roads": [{"a": Vector2(-150, 0), "b": Vector2(150, 0), "tile": "t", "widths": [6.0, 5.0, 4.0, 3.0], "layer": 0}],
		"standing": [{"iid": "north", "kind": "building", "tile": "t", "pos": Vector2(0, 20), "side": 8.0},
			{"iid": "south", "kind": "building", "tile": "t", "pos": Vector2(1.5, -20), "side": 8.0}]}
	var warm := model.duplicate(true)
	var cache := {}
	var ground := func(_p: Vector2) -> float: return 40.0
	var water := func(_p: Vector2) -> bool: return false
	var key := func(_s: Dictionary) -> String: return "house_lvl1"
	Placement.new().fit(model, ground, water, key, {}, cache)
	var paths: Array = model.authored_region.paths
	_check(paths.size() == 2 and paths[0].points[-1] == paths[1].points[-1], "road_rollout: nearby access-road ends are joined")
	Placement.new().fit(warm, ground, water, key, {}, cache)
	_check(warm.authored_region.paths == paths and warm.roads == model.roads, "road_rollout: cache retains the snapped access paths rather than their pre-join geometry")

class CountingRoadGround extends RefCounted:
	var samples := 0
	func height(_point: Vector2) -> float:
		samples += 1
		return 40.0

func _road(id: String, points: Array, layer: int = 0) -> Dictionary:
	return {"id": id, "class": "minor", "layer": layer, "points": PackedVector2Array(points)}

func _test_road_rollout_three_unit_junctions() -> void:
	var paths := [_road("street", [Vector2(-30, 0), Vector2.ZERO, Vector2(30, 0)]),
		_road("branch", [Vector2(0, 2.9), Vector2(0, 30)])]
	_check(Index.audit(paths).near_endpoints_within_3u == 1, "road_rollout: audit finds a 2.9u gap at an existing road vertex")
	_check(Index.join(paths) == 1 and paths[1].points[0] == Vector2.ZERO, "road_rollout: 3u joins connect to internal vertices as well as segment interiors")
	_check(Index.audit(paths).near_endpoints_within_3u == 0, "road_rollout: connected endpoints are not reported as near misses")
	var parallel := [_road("street", [Vector2(-30, 0), Vector2(30, 0)]),
		_road("lane", [Vector2(-10, 2.5), Vector2(10, 2.5)])]
	var original := parallel.duplicate(true)
	Index.join(parallel)
	_check(parallel == original, "road_rollout: proximity alone does not merge separate parallel lanes")
	var overpass := [_road("street", [Vector2(-30, 0), Vector2(30, 0)]),
		_road("upper", [Vector2(0, -2), Vector2(0, 30)], 1)]
	original = overpass.duplicate(true)
	Index.join(overpass)
	_check(Index.trim_stubs(overpass).is_empty() and overpass == original, "road_rollout: joining and stub cleanup preserve different road layers")

func _test_road_rollout_trim_junction_overshoots() -> void:
	var paths := [_road("street", [Vector2(-30, 0), Vector2(30, 0)]),
		_road("branch", [Vector2(0, -2.8), Vector2(0, -1.5), Vector2(0, -0.5), Vector2(0, 30)])]
	var source := paths.duplicate(true)
	var compiled := Region.compile(paths, {"t": Vector2.ZERO})
	_check(compiled.trimmed_stubs.size() == 1 and is_equal_approx(compiled.trimmed_stubs[0].length, 2.8), "road_rollout: measure the complete sampled overshoot to its junction")
	_check(compiled.paths[1].points[0] == Vector2.ZERO and compiled.paths[1].points[-1] == Vector2(0, 30), "road_rollout: remove only the overshoot and keep the continuing street")
	_check(Index.audit(compiled.paths).stubs_under_3u == 0, "road_rollout: no short stub survives compilation")
	_check(paths == source, "road_rollout: trimming never edits the regular-map source paths")
	var twice := Region.compile(compiled.paths, {"t": Vector2.ZERO})
	_check(twice.paths == compiled.paths and twice.roads == compiled.roads, "road_rollout: junction cleanup is idempotent")
	# A chain's short tessellation segments do not make the full dead end short.
	paths = [_road("street", [Vector2(-30, 0), Vector2(30, 0)]),
		_road("branch", [Vector2(0, -4), Vector2(0, -2), Vector2(0, -1), Vector2(0, 30)]),
		_road("exact", [Vector2(10, -3), Vector2(10, 30)])]
	source = paths.duplicate(true)
	_check(Index.trim_stubs(paths).is_empty() and paths == source, "road_rollout: keep tails 3u or longer, even with sub-3u samples")

func _test_road_rollout_keep_short_connections() -> void:
	var paths := [_road("street", [Vector2(-30, 0), Vector2(30, 0)]),
		_road("left", [Vector2(0, -30), Vector2(0, 30)]),
		_road("right", [Vector2(2.5, -30), Vector2(2.5, 30)]),
		_road("access:door", [Vector2(10, -2), Vector2(10, 0)]),
		_road("isolated", [Vector2(50, 50), Vector2(51, 50)])]
	var original := paths.duplicate(true)
	_check(Index.trim_stubs(paths).is_empty() and paths == original, "road_rollout: keep short links between junctions, building entrances and isolated roads")
	paths = [_road("street", [Vector2(-30, 0), Vector2(2, 0)]),
		_road("overlap", [Vector2(-30, 0), Vector2.ZERO])]
	original = paths.duplicate(true)
	_check(Index.trim_stubs(paths).is_empty() and paths == original, "road_rollout: overlapping strokes do not create a false three-way junction")

func _test_road_rollout_trim_before_hex_clip() -> void:
	var paths := [_road("street", [Vector2(150, 120), Vector2(250, 120)]),
		_road("branch", [Vector2(201, 117.5), Vector2(201, 180)])]
	var both := Region.compile(paths, {"left": Vector2.ZERO, "right": Vector2(405, 240)})
	var single := Region.compile(paths, {"left": Vector2.ZERO})
	_check(both.paths == single.paths and both.trimmed_stubs.size() == 1, "road_rollout: stub trimming is independent of visible hex boundaries")
	var valid := true
	for road in both.roads:
		if road.source == "branch": valid = valid and road.a.y >= 120.0 and road.b.y >= 120.0
	_check(valid, "road_rollout: rendered segments use the same trimmed paths as terrain and bridge profiles")

func _test_road_rollout_trim_at_new_access() -> void:
	var paths := [_road("street", [Vector2(-150, 0), Vector2(1, 0)])]
	var model := {"tiles": {"t": {"center": Vector2.ZERO}}, "authored_region": {"tiles": {"t": Vector2.ZERO}, "paths": paths},
		"roads": Region.compile_segments(paths, {"t": Vector2.ZERO}),
		"standing": [{"iid": "works", "kind": "building", "tile": "t", "pos": Vector2(0, 20), "side": 8.0}]}
	var initial := model.duplicate(true)
	var prepared := {}
	var ground := func(_p: Vector2) -> float: return 40.0
	var water := func(_p: Vector2) -> bool: return false
	var key := func(_s: Dictionary) -> String: return "house_lvl1"
	Placement.new().fit(model, ground, water, key, {}, prepared)
	_check(model.authored_region.frontage.trimmed_stubs.size() == 1 and model.authored_region.paths[0].points[-1] == Vector2.ZERO,
		"road_rollout: a new driveway trims the street's 1u overshoot at the access junction")
	_check(model.authored_region.paths[1].points[0] == model.standing[0].entrance,
		"road_rollout: trimming at a driveway preserves its building door")
	Placement.new().fit(initial, ground, water, key, {}, prepared)
	_check(initial.roads == model.roads and initial.authored_region == model.authored_region
		and initial.standing[0].entrance == model.standing[0].entrance and Index.audit(initial.authored_region.paths).stubs_under_3u == 0,
		"road_rollout: cached frontages restore the trimmed street and access road together")

func _test_road_rollout_shared_endpoint_precision() -> void:
	# Actual contiguous samples from r:untitled:2190. Re-intersecting them used
	# to invent a 0.0147u reverse segment beside their shared middle vertex.
	var points := [Vector2(3627.56103515625, 7768.94384765625), Vector2(3631.29760742188, 7772.67919921875),
		Vector2(3635.2958984375, 7776.67626953125)]
	var paths := [_road("curve", points)]
	var parts := Index.path_segments(paths)
	_check(Index.split(parts) == parts, "road_rollout: shared float32 endpoints cannot create phantom branches")
	_check(Index.audit(paths).stubs_under_3u == 0 and Index.trim_stubs(paths).is_empty(),
		"road_rollout: contiguous curved-road samples are never mistaken for short dead ends")

func _test_road_rollout_cached_scene_meshes() -> void:
	var builder := preload("res://scripts/supply_chain_3d/world_builder.gd")
	var cold := builder.new()
	cold.ground = CountingRoadGround.new()
	cold.tiles = {"t": {"center": Vector2.ZERO, "type": "urban", "polluters": 0}}
	cold._scenery_key = "test-scene-meshes"
	cold.bake_cache.enabled = false
	var show := {"roads": true}
	var item := {"iid": "depot", "kind": "warehouse", "tile": "t", "pos": Vector2.ZERO, "side": 20.0}
	var model := {"standing": [item], "lines": [], "roads": [{"tile": "t", "a": Vector2(-100, 0), "b": Vector2(100, 0),
		"level": 2, "paved": true, "widths": [6.0, 5.0, 4.0, 3.0]}]}
	var cold_root: Node3D = cold.infrastructure(model, show, false)
	cold.prepare_standing_shadows(model.standing)
	var warm := builder.new()
	warm.ground = CountingRoadGround.new()
	warm.tiles = cold.tiles.duplicate(true)
	warm._scenery_key = cold._scenery_key
	warm.bake_cache.enabled = false
	warm.infrastructure_bake = cold.infrastructure_bake
	var warm_root: Node3D = warm.infrastructure(model, show, false)
	_check(cold.ground.samples > 0 and warm.ground.samples == 0 and warm.road_surface.ways.is_empty() and warm.cars == cold.cars,
		"road_rollout: cached infrastructure restores meshes and traffic without road indexing or terrain sampling")
	warm.standing_shadow_mesh = cold.standing_shadow_mesh
	warm.standing_frames.depot = {"key": "warehouse_lvl1", "position": Vector3(0, 40, 0), "dimension": Vector3(20, 12, 20), "plinth_depth": 0.0}
	warm.lazy_assets = true
	var standing: Node3D = warm.standing_node(item)
	var shadows: MeshInstance3D = warm.shadows_node()
	_check(warm.ground.samples == 0 and warm.shadow_batch.vertices.is_empty() and shadows.mesh == cold.standing_shadow_mesh,
		"road_rollout: cached building shadows are reused without sampling or drawing a duplicate shadow")
	warm.tiles.t.polluters = 1
	var relit: Node3D = warm.infrastructure(model, show, false)
	_check(warm.ground.samples > 0 and not warm.glows.is_empty(), "road_rollout: changed pollution lighting invalidates the infrastructure mesh cache")
	warm.streamed = true
	warm.local_streaming = true
	warm.cursor_picking = true
	warm.active_lod = 2
	warm._sprites_visible = false
	warm._update_asset_tier()
	var deferred: bool = warm.sprite_pairs[0].near.is_empty() and warm.sprite_pairs[0].far.visible
	warm.local_tiles.t = {"records": {"building_visuals": []}}
	warm._update_asset_tier()
	_check(deferred and not warm.sprite_pairs[0].near.is_empty() and not warm.sprite_pairs[0].far.visible,
		"road_rollout: remote buildings retain their far cards and create close meshes only when their tile is resident")
	cold_root.free(); warm_root.free(); standing.free(); shadows.free(); relit.free()
