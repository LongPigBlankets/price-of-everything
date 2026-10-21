extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Placement := preload("res://scripts/supply_chain_3d/road_placement.gd")
const Builder := preload("res://scripts/supply_chain_3d/world_builder.gd")
const Pace := preload("res://scripts/supply_chain_3d/layout_pace.gd")

func _street_model() -> Dictionary:
	var tile := {"type":"urban","center":Vector2.ZERO}
	var seed := {"iid":"seed","kind":"house","tile":"tile_4_9","pos":Vector2.ZERO,"side":36.0,"level":1,"decor_asset":"house_lvl1",
		"trial_density":true,"trial_tile":tile,"trial_edge_centers":[],"trial_harbours":[]}
	return {"tiles":{"tile_4_9":tile},"trial_targets":{"tile_4_9":0},"standing":[seed],
		"authored_region":{"tiles":{"tile_4_9":Vector2.ZERO},"paths":[]},
		"roads":[{"a":Vector2(-210,0),"b":Vector2(210,0),"tile":"tile_4_9","source":"street","level":1,"paved":true,"widths":[5.0,4.5,4.0,3.5]}]}

func _test_paced_fit_matches_a_straight_one() -> void:
	var flat := func(_p: Vector2) -> float: return 40.0
	var dry := func(_p: Vector2) -> bool: return false
	var straight := _street_model()
	Placement.new().fit(straight, flat, dry, Builder.standing_key, {}, {})
	var paced := _street_model()
	var pace := Pace.new(get_tree())
	pace.budget_usec = 0
	await Placement.new().fit(paced, flat, dry, Builder.standing_key, {}, {}, pace)
	_check(pace.frames > 1, "layout pace: a paced fit is spread over frames")
	_check(paced == straight, "layout pace: a paced fit lays the street out exactly as a straight one")

func _test_given_up_fit_is_not_remembered() -> void:
	var prepared := {}
	var model := _street_model()
	var pace := Pace.new(get_tree(), func() -> bool: return false)
	pace.budget_usec = 0
	await Placement.new().fit(model, func(_p: Vector2) -> float: return 40.0, func(_p: Vector2) -> bool: return false,
		Builder.standing_key, {}, prepared, pace)
	_check(pace.stopped and pace.frames == 1, "layout pace: a fit stops at the first frame after its build is given up")
	_check((prepared.get("frontages", {}) as Dictionary).is_empty(), "layout pace: a given up fit leaves nothing in the layout memo")

func _test_no_pace_never_yields() -> void:
	var started := Engine.get_process_frames()
	await Pace.step(null)
	_check(Engine.get_process_frames() == started, "layout pace: without a pace a pass runs straight through")
