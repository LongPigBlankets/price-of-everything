extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Placement := preload("res://scripts/supply_chain_3d/road_placement.gd")
const Builder := preload("res://scripts/supply_chain_3d/world_builder.gd")
const Fill := preload("res://scripts/supply_chain_3d/frontage_fill.gd")

func _test_frontage_target_and_cached_infill() -> void:
	var tile := {"type":"urban","center":Vector2.ZERO}
	var seed := {"iid":"seed","kind":"house","tile":"tile_4_9","pos":Vector2.ZERO,"side":36.0,"level":1,"decor_asset":"house_lvl1",
		"trial_density":true,"trial_tile":tile,"trial_edge_centers":[],"trial_harbours":[]}
	var model := {"tiles":{"tile_4_9":tile},"trial_targets":{"tile_4_9":0},"standing":[seed],
		"authored_region":{"tiles":{"tile_4_9":Vector2.ZERO},"paths":[]},
		"roads":[{"a":Vector2(-210,0),"b":Vector2(210,0),"tile":"tile_4_9","source":"street","level":1,"paved":true,"widths":[5.0,4.5,4.0,3.5]}]}
	var fresh := model.duplicate(true)
	var prepared := {}
	var flat := func(_p: Vector2) -> float:return 40.0
	var dry := func(_p: Vector2) -> bool:return false
	Placement.new().fit(model,flat,dry,Builder.standing_key,{},prepared)
	var coverage: Dictionary=model.authored_region.frontage.coverage
	_check(coverage.after.coverage>=0.75 and coverage.added>0,"frontage: fill at least 75% of both sides of an unobstructed street")
	_check(is_equal_approx(coverage.after.roadside_length,840.0),"frontage: denominator counts each side once, regardless of building count")
	_check(model.roads.size()==1 and model.standing.all(func(s: Dictionary)->bool:return not s.has("entrance")),"frontage: infill never creates decorative road stubs")
	Placement.new().fit(fresh,flat,dry,Builder.standing_key,{},prepared)
	_check(fresh==model,"frontage: cached load restores generated infill and coverage exactly")
	var outside: Dictionary= model.roads[0].duplicate();outside.tile="elsewhere"
	var access: Dictionary= model.roads[0].duplicate();access.source="access:player"
	_check(Fill.street(outside) and not Fill.street(access),"frontage: roads outside Stoneshore are eligible and access roads stay excluded")

func _test_frontage_fields_and_narrow_corridors() -> void:
	var Assets: GDScript=preload("res://scripts/supply_chain_3d/assets.gd")
	var key: String=Assets.key_for("farm_building",1)
	var road := {"a":Vector2(-100,0),"b":Vector2(100,0),"tile":"tile_4_9","source":"street","level":1,"paved":true,"widths":[5.0,4.5,4.0,3.5],"sidewalk":2.0}
	var field := PackedVector2Array([Vector2(-80,5),Vector2(80,5),Vector2(80,110),Vector2(-80,110)])
	var farm := {"iid":"farm","kind":"building","tile":"tile_4_9","pos":Vector2(0,70),"side":40.0,"footprint":field}
	var model := {"tiles":{"tile_4_9":{"type":"urban","center":Vector2.ZERO}},"roads":[road],"standing":[farm]}
	var fit := Placement.new()
	fit.roads=model.roads;fit.road_index=Placement.Index.segments(fit.roads,20)
	fit.ground=func(_p: Vector2) -> float:return 40.0
	fit.asset_key=func(_s: Dictionary) -> String:return key
	fit.reserve("farm",field)
	var result: Dictionary = await Fill.new().run(model,fit,{})
	_check(result.before.covered_length==0.0 and result.before.excluded.get("reserved_plot",0)>0,"frontage: a farm field or works yard does not count as a building facade")
	var parallel: Dictionary=road.duplicate(true);parallel.a.y=22;parallel.b.y=22
	model.standing=[];model.roads=[road,parallel]
	fit=Placement.new();fit.roads=model.roads;fit.road_index=Placement.Index.segments(fit.roads,20)
	fit.ground=func(_p: Vector2) -> float:return 40.0
	result=await Fill.new().run(model,fit,{})
	_check(result.before.excluded.get("plot_junction",0)>100.0,"frontage: slivers between close roads require enough depth for an actual building")

func _test_frontage_quarter_turn_keeps_house_scale() -> void:
	var tile := {"type":"rural","center":Vector2.ZERO}
	var seed := {"iid":"seed","kind":"house","tile":"tile_5_9","pos":Vector2.ZERO,"side":36.0,"level":1,"decor_asset":"house_lvl1",
		"trial_density":true,"trial_tile":tile,"trial_edge_centers":[],"trial_harbours":[]}
	var model := {"tiles":{"tile_5_9":tile},"trial_targets":{"tile_5_9":0},"standing":[seed],
		"authored_region":{"tiles":{"tile_5_9":Vector2.ZERO},"paths":[]},
		"roads":[{"a":Vector2(-50,0),"b":Vector2(50,0),"tile":"tile_5_9","source":"street","level":1,"paved":true,"widths":[5.0,4.5,4.0,3.5]}]}
	# Keep the fixture narrower than the resized home's frontage, so a quarter
	# turn is still required rather than an ordinary street-facing placement.
	var half_width: float=11.0*preload("res://scripts/supply_chain_3d/stoneshore_trial.gd").DECOR_SIZE_FACTOR
	Placement.new().fit(model,func(_p: Vector2)->float:return 40.0,func(p: Vector2)->bool:return absf(p.x)>half_width,Builder.standing_key)
	var Scale: GDScript=preload("res://scripts/supply_chain_3d/building_scale.gd")
	_check(model.standing.size()==2,"frontage: quarter-turn homes occupy narrow plots on both sides")
	var correct := true
	for s in model.standing:
		var expected: float=(Scale.semi_side() if str(s.decor_asset).begins_with("civic_semi") else Scale.TERRACE_ROW_SIDE)*preload("res://scripts/supply_chain_3d/stoneshore_trial.gd").DECOR_SCALE
		correct=correct and absf(sin(float(s.yaw)))>0.99 and is_equal_approx(float(s.side),expected)
	_check(correct,"frontage: narrow plots rotate existing homes without shrinking them")
