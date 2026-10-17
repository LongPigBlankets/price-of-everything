extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Civic := preload("res://scripts/supply_chain_3d/civic_layout.gd")
const Placement := preload("res://scripts/supply_chain_3d/road_placement.gd")
const Builder := preload("res://scripts/supply_chain_3d/world_builder.gd")
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const Far := preload("res://scripts/supply_chain_3d/far_sprites.gd")
const Scale := preload("res://scripts/supply_chain_3d/building_scale.gd")

func _model() -> Dictionary:
	return {"tiles": {"t": {"center": Vector2.ZERO, "type": "urban"}, "rural": {"center": Vector2(405, 240), "type": "rural"},
		"outside": {"center": Vector2(810, 0), "type": "urban"}}, "standing": [], "roads": [], "flows": [],
		"authored_region": {"tiles": {"t": Vector2.ZERO}, "paths": []}}

func _test_civic_scope_and_determinism() -> void:
	var model := _model()
	Civic.populate(model, ["t", "rural"])
	var initial: Array = model.standing.duplicate(true)
	Civic.populate(model, ["t", "rural"])
	_check(model.standing == initial, "civic: repeated preparation does not duplicate plots")
	var families := {}
	var valid := true
	for s in model.standing:
		families[s.decor_family] = true
		valid = valid and s.tile == "t" and s.kind == "house" and not s.get("npc", false)
	_check(valid and families.size() == 8, "civic: only scoped urban tiles gain all eight decorative families")
	_check(model.roads.is_empty() and model.flows.is_empty(), "civic: seeds never invent simulation goods or authored roads")
	var fresh := _model(); Civic.populate(fresh, ["t", "rural"])
	_check(fresh == model, "civic: the same map produces identical infill seeds")

func _test_civic_frontage_cache_and_clearance() -> void:
	var model := _model()
	for y in [-120, 0, 120]:
		model.roads.append({"a": Vector2(-220, y), "b": Vector2(220, y), "tile": "t", "source": "street"+str(y),
			"level": 1, "layer": 0, "paved": true, "widths": [5.0, 4.5, 4.0, 3.5]})
	Civic.populate(model, ["t"])
	var warm := model.duplicate(true)
	var spaces_only := model.duplicate(true)
	spaces_only.standing = spaces_only.standing.filter(func(s: Dictionary) -> bool: return Civic.is_space(s))
	var prepared := {}
	var flat := func(_p: Vector2) -> float: return 40.0
	var dry := func(_p: Vector2) -> bool: return false
	var fitter := Placement.new()
	fitter.fit(model, flat, dry, Builder.standing_key, {}, prepared)
	_check(model.standing.size() > 12, "civic: vacant flat street fronts gain a useful density of infill")
	var safe := true
	var spaces := 0
	for s in model.standing:
		if Civic.is_space(s):
			spaces += 1
			safe = safe and not s.has("entrance")
		elif s.decor_family == "civic_semi":
			var key := Builder.standing_key(s)
			safe = safe and is_equal_approx(Assets.dimensions(key).y * Scale.for_asset(key, s.side).y, 55.0)
		else:
			safe = safe and is_equal_approx(Assets.storey_height(Builder.standing_key(s)) * float(s.side), Civic.STOREY)
		for road in model.roads:
			if str(road.source).begins_with("access:"): continue
			for poly in s.footprints:
				safe = safe and Placement.distance_to_polygon(road.a, road.b, poly) >= 7.0
	# Dense frontage can fill before green candidates; separately exercise their
	# explicit public-space parcels without depending on seed ordering.
	Placement.new().fit(spaces_only, flat, dry, Builder.standing_key)
	for s in spaces_only.standing:
		safe = safe and not s.has("entrance")
		spaces += 1
	_check(safe and spaces > 0, "civic: placement keeps storey scale, clears roads and gives public spaces no asphalt driveways")
	Placement.new().fit(warm, flat, dry, Builder.standing_key, {}, prepared)
	_check(warm == model, "civic: cached frontage preserves every asset choice, public space and orientation")
	var wet_model := _model(); Civic.populate(wet_model, ["t"])
	wet_model.roads = warm.roads
	Placement.new().fit(wet_model, flat, func(_p: Vector2) -> bool: return true, Builder.standing_key)
	_check(wet_model.standing.is_empty(), "civic: infill is omitted when there is no dry plot")

func _test_civic_three_lod_assets() -> void:
	for key in ["civic_office_lvl1", "civic_office_lvl2", "civic_l_lvl1", "civic_park_lvl1", "civic_plaza_lvl1",
		"civic_u_office_lvl1", "civic_semi_lvl1", "civic_bauhaus_lvl1", "civic_commercial_lvl1"]:
		var family: String = key.get_slice("_lvl", 0)
		_check(Assets.key_for(family, int(key.get_slice("_lvl", 1))) == key and Assets.mesh_for(key) != null
			and not Far.entry(key).is_empty() and not Far.entry(key, 1).is_empty(), "civic: %s has near geometry and both distant sprite tiers" % key)

func _test_civic_storey_scale_and_outline() -> void:
	var model := _model(); Civic.populate(model, ["t"])
	var consistent := true
	for s in model.standing:
		if Civic.is_space(s): continue
		var key := Builder.standing_key(s)
		if s.decor_family == "civic_semi":
			consistent = consistent and is_equal_approx(Assets.dimensions(key).y * Scale.for_asset(key, s.side).y, 55.0)
		else:
			consistent = consistent and is_equal_approx(Assets.storey_height(key) * float(s.side), 12.0)
		consistent = consistent and Assets.contour_for(key) != null
	_check(consistent, "civic: offices share a 12u storey, semis stand 10% above terraces, and all use the housing contour")

func _modular_plot(family: String, half_width: float, back: float) -> Dictionary:
	var model := _model()
	model.standing = [{"iid": "z_civic:test", "kind": "house", "tile": "t", "pos": Vector2.ZERO,
		"side": Civic.side_for(family, 1), "pad": 70.0, "level": 1, "decor_family": family, "max_relief": 6.0}]
	model.roads = [{"a": Vector2(-200, 0), "b": Vector2(200, 0), "tile": "t", "source": "street",
		"level": 1, "layer": 0, "paved": true, "widths": [5.0, 4.5, 4.0, 3.5]}]
	var wet := func(p: Vector2) -> bool: return absf(p.x) > half_width or p.y < 7.0 or p.y > back
	Placement.new().fit(model, func(_p: Vector2) -> float: return 40.0, wet, Builder.standing_key)
	return model.standing[0] if not model.standing.is_empty() else {}

func _test_civic_modular_plot_fit() -> void:
	var narrow := _modular_plot("civic_office", 27.0, 110.0)
	var wide := _modular_plot("civic_office", 55.0, 110.0)
	_check(narrow.get("civic_bays") == Vector2i(5, 0), "civic modular: a 54u frontage fits five columns, not a stretched six-column office")
	_check(wide.get("civic_bays") == Vector2i(10, 0), "civic modular: a wider plot gains full window columns")
	var shallow := _modular_plot("civic_l", 34.0, 74.0)
	var deep := _modular_plot("civic_l", 34.0, 94.0)
	_check(shallow.get("civic_bays") == Vector2i(6, 3), "civic modular: exact footprint fits six front columns with a three-column return")
	_check(deep.get("civic_bays") == Vector2i(6, 4), "civic modular: deeper L plot extends only the return wing")
	_check(_modular_plot("civic_office", 18.0, 110.0).is_empty(), "civic modular: plots below the minimum bay count omit the building")
	var scale_ok := true
	for s in [narrow, wide, shallow, deep]:
		if s.is_empty(): scale_ok = false; continue
		scale_ok = scale_ok and is_equal_approx(Assets.storey_height(Builder.standing_key(s)) * float(s.side), 12.0)
	_check(scale_ok, "civic modular: fitting preserves the same floor height in both axes")

func _test_civic_modular_catalog() -> void:
	var count := 0
	var metrics := true
	var resources := true
	for shape in ["long", "l"]:
		for option in Assets.civic_modules(shape):
			count += 1
			var side := 12.0 / float(option.storey)
			metrics = metrics and is_equal_approx(float(option.module.bay_pitch) * side, 12.0*.9/1.1)
			resources = resources and Assets.mesh_for(option.key) != null and Assets.contour_for(option.key) != null
			resources = resources and not Far.entry(option.key).is_empty() and not Far.entry(option.key, 1).is_empty()
	_check(count == 22, "civic modular: seven long and fifteen independently sized L variants")
	_check(metrics, "civic modular: every extension uses the same world-space window pitch")
	_check(resources, "civic modular: all variants have near geometry, contours and both sprite LODs")

func _roof_at(mesh: Mesh, x: float, z: float) -> float:
	var faces := mesh.get_faces()
	var highest := -INF
	for i in range(0, faces.size(), 3):
		var hit: Variant = Geometry3D.ray_intersects_triangle(Vector3(x, 10, z), Vector3.DOWN, faces[i], faces[i+1], faces[i+2])
		if hit != null: highest = maxf(highest, hit.y)
	return highest

func _test_civic_district_geometry() -> void:
	var key := Assets.key_for("civic_u_office", 1)
	var mesh := Assets.mesh_for(key)
	var side := Civic.side_for("civic_u_office", 1)
	_check(_roof_at(mesh, 0, .12)*side < 2.0,
		"civic: U-office courtyard is open to the ground after GLB export")
	_check(_roof_at(mesh, 0, -.25)*side > 240.0 and _roof_at(mesh, .38, .15)*side < 155.0,
		"civic: the central twenty floors stand above the twelve-floor wings")
	var semi := Assets.key_for("civic_semi", 1)
	_check(is_equal_approx(Assets.dimensions(semi).y * Scale.for_asset(semi, Civic.side_for("civic_semi",1)).y, 55.0),
		"civic: semis are 10% taller than the 50u terrace reference")

	var terrace := Assets.key_for("house",1)
	var pair_width := Assets.dimensions(semi).x * Civic.side_for("civic_semi",1)
	_check(is_equal_approx(pair_width/(Assets.dimensions(terrace).x*72.0/3.0),2.5),
		"civic: the complete semidetached pair is 2.5 terrace homes wide")
