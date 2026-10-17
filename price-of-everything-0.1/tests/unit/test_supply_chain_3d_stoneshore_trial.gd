extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Trial := preload("res://scripts/supply_chain_3d/stoneshore_trial.gd")
const Scale := preload("res://scripts/supply_chain_3d/building_scale.gd")
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const Placement := preload("res://scripts/supply_chain_3d/road_placement.gd")

func _test_stoneshore_trial_preserves_gameplay_and_scope() -> void:
	var player := {"iid":"player", "kind":"building", "tile":"tile_4_9", "pos":Vector2.ZERO,"side":90.0}
	var npc := {"iid":"npc", "kind":"suppliers", "tile":"tile_4_9", "pos":Vector2(90,0),"side":80.0}
	var outside := {"iid":"outside", "kind":"house", "tile":"outside", "pos":Vector2(900,0),"side":72.0}
	var model := {"tiles":{"tile_4_9":{"center":Vector2.ZERO,"type":"urban"}, "tile_5_9":{"center":Vector2(405,240),"type":"rural"}},
		"standing":[player.duplicate(true), npc.duplicate(true), outside.duplicate(true)], "roads":[], "flows":[]}
	Trial.populate(model)
	_check(model.standing.has(player) and model.standing.has(npc) , "Stoneshore trial: gameplay buildings are untouched")
	var first: Array = model.standing.duplicate(true)
	Trial.populate(model)
	_check(model.standing == first, "Stoneshore trial: regenerating seeds is deterministic and idempotent")
	var baseline := 0; var target := 0
	for value in Trial.BASELINE_BUILDINGS.values(): baseline += value
	for value in Trial.TARGET_BUILDINGS.values(): target += value
	_check(target == 34, "Stoneshore trial: initial landmarks leave room for measured street-front infill")
	var residential_only := true
	for s in model.standing:
		if s.tile == "tile_5_9" and not s.get("trial_green",false): residential_only = residential_only and s.trial_residential and s.get("decor_family", "") in ["", "civic_semi"]
	_check(residential_only, "Stoneshore trial: rural candidates are homes and apartments")

func _test_stoneshore_trial_decor_size_and_boundaries() -> void:
	for key in ["house_lvl2", "civic_semi_lvl1", "civic_u_office_lvl1", "civic_commercial_lvl1"]:
		var previous := Scale.for_asset(key, 35.0, 0.5)
		var smaller := Scale.for_asset(key, 70.0 * Trial.DECOR_SCALE, Trial.DECOR_SCALE)
		_check(smaller.is_equal_approx(previous * 0.65), "Stoneshore trial: %s is 35%% smaller in all three dimensions, including fixed house height" % key)
	var tile := {"center":Vector2.ZERO, "type":"urban"}
	var rural := [Vector2(405,240)]
	_check(not Trial.residential(tile,Vector2.ZERO,rural) and Trial.residential(tile,Vector2(170,100),rural), "Stoneshore trial: housing occupies the urban edge facing rural land")
	_check(Trial.residential(tile,Vector2(-190,0),[Vector2(-405,0)]) and Trial.residential(tile,Vector2(0,190),[Vector2(0,480)]), "Stoneshore trial: housing also follows west and seaward city boundaries")
	_check(not Trial.residential(tile,Vector2(-190,0),[Vector2(-405,0)],[Vector2(-200,0)]), "Stoneshore trial: port frontage excludes semi-detached housing")
	var fit := Placement.new()
	_check(not fit.trial_plot_allowed({"pos":Vector2(181,0), "trial_port":Vector2.ZERO,"trial_max_distance":180.0}), "Stoneshore trial: the factory cannot drift away from the harbour")

func _test_continent_decorative_scope() -> void:
	var rural := {"iid":"rural_home","kind":"house","tile":"rural","pos":Vector2(900,0),"side":72.0}
	var player := {"iid":"player","kind":"building","tile":"urban","pos":Vector2.ZERO,"side":90.0}
	var model := {"tiles":{"urban":{"center":Vector2.ZERO,"type":"urban"},"rural":{"center":Vector2(900,0),"type":"rural"}},"standing":[rural,player.duplicate(true)]}
	Trial.populate(model)
	_check(model.standing.has(player),"Continent: gameplay size stays unchanged")
	_check(model.trial_targets.has("urban") and not model.trial_targets.has("rural"),"Continent: dense infill extends to urban tiles only")
	_check(is_equal_approx(rural.side,Scale.TERRACE_ROW_SIDE*Trial.DECOR_SCALE),"Continent: rural hamlets use the same decorative scale")
	_check(model.standing.filter(func(s):return s.tile=="rural").size()==1,"Continent: countryside retains its existing settlement count")
	var first: Array=model.standing.duplicate(true)
	Trial.populate(model)
	_check(first==model.standing,"Continent: scaling and seeding are idempotent")
