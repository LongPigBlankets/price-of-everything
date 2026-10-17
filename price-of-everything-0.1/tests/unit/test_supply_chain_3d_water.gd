extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Water := preload("res://scripts/supply_chain_3d/water_geography.gd")
const Ground := preload("res://scripts/empire_board_ground.gd")
const Builder := preload("res://scripts/supply_chain_3d/world_builder.gd")

func _test_water_geography_flat_lakes_and_tile_edges() -> void:
	var valid := true
	var samples := 0
	var failures := 0
	for lake in Water.lakes():
		var local := PackedVector2Array()
		for p in lake.p: local.append(p - lake.box.position)
		var tri := Geometry2D.triangulate_polygon(local)
		if tri.is_empty(): print("[WATER TEST] untriangulated ", lake.box, " points=", lake.p.size())
		valid = valid and not tri.is_empty()
		for i in range(0, tri.size(), 3):
			var p: Vector2 = (lake.p[tri[i]] + lake.p[tri[i+1]] + lake.p[tri[i+2]]) / 3.0
			var surface := Water.lake_surface(p)
			if surface.y != 1 or not is_equal_approx(surface.x, lake.level):
				if failures < 6: print("[WATER TEST] point=",p," got=",surface," expected=",lake.level)
				failures += 1
			valid = valid and surface.y == 1 and is_equal_approx(surface.x, lake.level)
			samples += 1
	_check(valid and samples > 100, "Water geography: every triangulated lake interior samples its continuous flat water level")
	var boundary_samples := 0
	valid = true
	# Clipped polygons may close along a tile edge; these cuts must remain water,
	# rather than introducing a dry bank into the global lake sampler.
	for tid in Water.data().tiles:
		for lake in Water.for_tile(tid).lakes:
			for i in lake.size():
				var p: Vector2 = (lake[i] + lake[(i+1)%lake.size()]) * 0.5
				var delta: Vector2 = (lake[(i+1)%lake.size()] - lake[i]).normalized().orthogonal() * 0.1
				var a := Water.lake_surface(p + delta); var b := Water.lake_surface(p - delta)
				if a.y == 1 and b.y == 1:
					boundary_samples += 1
					if Water.lake_surface(p).y != 1 and failures < 12:
						print("[WATER TEST] seam=",p," center=",Water.lake_surface(p)," a=",a," b=",b)
						failures += 1
					valid = valid and is_equal_approx(a.x, b.x) and Water.lake_surface(p).y == 1
	_check(valid and boundary_samples > 10, "Water geography: lake crossings and internal polygon cuts do not create a raised seam")

func _test_water_geography_constraints_and_legacy_isolation() -> void:
	var valid := true
	for check in Water.data().lake_checks:
		valid = valid and float(check.minimum_lip) >= 1.0 and float(check.area_after) > 0
	_check(valid and Water.data().lake_checks.size() == HillBaked.lakes().size(), "Water geography: every authored lake retains water and a verified 1u terrain lip")
	_check(Water.data().source_sha256 == FileAccess.get_sha256("res://data/hills_baked.json"), "Water geography: baked contours match the authored geography source")
	var original := Ground.new()
	original.lakes = HillBaked.lakes()
	_check(original.lakes.size() == 11, "Water geography: regular-map lake source remains unchanged")

func _test_water_geography_bank_height_and_earthworks() -> void:
	var valid := true
	var builder := Builder.new()
	builder.ground = preload("res://scripts/supply_chain_3d/ground.gd").new()
	builder.ground.water_geography = true
	builder.transport_ready = true
	for lake in Water.lakes():
		var p := Ground._inside(lake.p)
		valid = valid and absf(Builder.Relief.height(lake.plate) - Builder.Relief.height(lake.level) - 3.0) < 0.001
		# Even an overlapping grading/depot footprint must not corrugate water.
		builder.depots = [{"pos": p, "yaw": 0.0, "height": 900.0}]
		valid = valid and is_equal_approx(builder.surface_height(p), Builder.Relief.height(lake.level))
		valid = valid and builder.surface_gradient(p) == Vector2.ZERO
	_check(valid, "Water geography: lake banks stay 3u high after mountain scaling and grading cannot warp water")
