extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Clearance := preload("res://scripts/supply_chain_3d/building_clearance.gd")
const Builder := preload("res://scripts/supply_chain_3d/world_builder.gd")
const BuildingScale := preload("res://scripts/supply_chain_3d/building_scale.gd")

func _works(iid: String, pos: Vector2, lot_side: float, npc: bool) -> Dictionary:
	return {"iid": iid, "kind": "building", "internal_name": "furnace", "level": 1, "tile": "tile_1_1", "pos": pos,
		"side": lot_side * BuildingScale.BUILDINGS_SCALE, "pad": lot_side * BuildingScale.BUILDINGS_SCALE, "yaw": 0.0, "npc": npc, "building_scaled": true}

func _road(a: Vector2, b: Vector2) -> Dictionary:
	return {"a": a, "b": b, "level": 2, "tile": "tile_1_1", "widths": [8.0, 7.5, 6.0, 5.0]}

func _carriageway_gap(s: Dictionary, road: Dictionary) -> float:
	var gap := INF
	for poly in Clearance.base(s, Builder.standing_key(s), float(s.side)):
		gap = minf(gap, Clearance.RoadPlacement.distance_to_polygon(road.a, road.b, poly) - float(road.widths[3]))
	return gap

func _test_clear_company_building_keeps_full_scale() -> void:
	var mine := _works("mine", Vector2(0, 0), 40.0, false)
	var model := {"standing": [mine], "roads": [_road(Vector2(-400, 300), Vector2(400, 300))]}
	_check(Clearance.apply(model, Builder.standing_key) == 0 and is_equal_approx(float(mine.side), 60.0) and mine.pos == Vector2.ZERO,
		"clearance: a company building clear of everything keeps its full 1.5x size and place")

func _test_company_building_slides_back_off_the_carriageway() -> void:
	var mine := _works("mine", Vector2(0, 0), 40.0, false)
	var full := Clearance.base(mine, Builder.standing_key(mine), float(mine.side))
	var edge := Clearance.RoadPlacement.polygon_bounds(full[0]).end.y
	var road := _road(Vector2(-400, edge), Vector2(400, edge))
	var model := {"standing": [mine], "roads": [road]}
	Clearance.apply(model, Builder.standing_key)
	_check(_carriageway_gap(mine, road) >= Clearance.CLEARANCE - 0.01, "clearance: a company building keeps off the carriageway")
	_check(is_equal_approx(float(mine.side), 60.0) and (mine.pos as Vector2).y < 0.0,
		"clearance: with room behind it, it slides back at its full size")

func _test_boxed_in_company_building_grows_as_far_as_it_can() -> void:
	var mine := _works("mine", Vector2(0, 0), 40.0, false)
	var full := Clearance.base(mine, Builder.standing_key(mine), float(mine.side))
	var box := Clearance.RoadPlacement.polygon_bounds(full[0])
	var roads := [_road(Vector2(-400, box.end.y), Vector2(400, box.end.y)), _road(Vector2(-400, box.position.y), Vector2(400, box.position.y)),
		_road(Vector2(box.end.x, -400), Vector2(box.end.x, 400)), _road(Vector2(box.position.x, -400), Vector2(box.position.x, 400))]
	var model := {"standing": [mine], "roads": roads}
	Clearance.apply(model, Builder.standing_key)
	_check(float(mine.side) >= 40.0 - 0.01 and float(mine.side) < 60.0, "clearance: boxed in by streets, it grows as far as it can, never below its lot")

func _test_slid_building_stays_on_its_tile() -> void:
	var mine := _works("mine", Vector2(0, 0), 40.0, false)
	var full := Clearance.base(mine, Builder.standing_key(mine), float(mine.side))
	var box := Clearance.RoadPlacement.polygon_bounds(full[0])
	var shore := box.position.y - 4.0
	var model := {"standing": [mine], "roads": [_road(Vector2(-400, box.end.y), Vector2(400, box.end.y))], "tiles": {"tile_1_1": {"center": Vector2(0, 0)}}}
	Clearance.apply(model, Builder.standing_key, func(p: Vector2) -> bool: return p.y < shore)
	var dry := true
	for poly in Clearance.base(mine, Builder.standing_key(mine), float(mine.side)):
		for p in poly: dry = dry and p.y >= shore - 0.01
	_check(dry, "clearance: a building never slides onto open water")

func _test_npc_works_and_homes_give_way() -> void:
	var mine := _works("mine", Vector2(0, 0), 40.0, false)
	var theirs := _works("theirs", Vector2(55, 0), 40.0, true)
	var home := {"iid": "home", "kind": "house", "tile": "tile_1_1", "pos": Vector2(0, -15), "side": 20.0, "level": 1, "yaw": 0.0}
	var far := _works("far", Vector2(600, 0), 40.0, true)
	var model := {"standing": [mine, theirs, home, far], "roads": []}
	Clearance.apply(model, Builder.standing_key)
	var ids: Array = model.standing.map(func(s: Dictionary) -> String: return str(s.iid))
	var shrunk: Dictionary = model.standing[ids.find("theirs")]
	var mine_base := Clearance.base(mine, Builder.standing_key(mine), float(mine.side))
	_check(is_equal_approx(float(mine.side), 60.0), "clearance: the company building keeps its size against NPC works and homes")
	_check(float(shrunk.side) < 60.0 and Clearance._clear(Clearance.base(shrunk, Builder.standing_key(shrunk), float(shrunk.side)), [], [mine_base]),
		"clearance: an NPC works that clips it is drawn smaller, clear of it")
	_check(is_equal_approx(float(theirs.side), 60.0), "clearance: the shared NPC record is left as it was")
	_check(not ids.has("home") and ids.has("far") and is_equal_approx(float(far.side), 60.0),
		"clearance: a home that clips it is left out, works elsewhere are untouched")

func _test_clearance_can_be_switched_off() -> void:
	Clearance.enabled = false
	var mine := _works("mine", Vector2(0, 0), 40.0, false)
	var model := {"standing": [mine, _works("theirs", Vector2(20, 0), 40.0, true)], "roads": []}
	var changed := Clearance.apply(model, Builder.standing_key)
	Clearance.enabled = true
	_check(changed == 0 and is_equal_approx(float(mine.side), 60.0), "clearance: switched off, every building stays at 1.5x")

func _test_slid_base_may_reach_a_quarter_into_a_neighbour() -> void:
	var hex := PackedVector2Array([Vector2(-100, -100), Vector2(100, -100), Vector2(100, 100), Vector2(-100, 100)])
	var square := func(x: float) -> Array: return [PackedVector2Array([Vector2(x - 20, -20), Vector2(x + 20, -20), Vector2(x + 20, 20), Vector2(x - 20, 20)])]
	var land := func(_p: Vector2) -> bool: return false
	_check(Clearance._placeable(square.call(88.0), hex, land), "clearance: a fifth of the base on the next tile is allowed")
	_check(not Clearance._placeable(square.call(95.0), hex, land), "clearance: more than a quarter on the next tile is not")
	_check(not Clearance._placeable(square.call(0.0), hex, func(p: Vector2) -> bool: return p.x > 15.0), "clearance: no part of the base over sea terrain")

func _test_homes_on_a_carriageway_are_left_out() -> void:
	var road := _road(Vector2(-400, 0), Vector2(400, 0))
	var on_road := {"iid": "on", "kind": "house", "tile": "tile_1_1", "pos": Vector2(0, 2), "side": 20.0, "level": 1, "yaw": 0.0}
	var beside := {"iid": "beside", "kind": "house", "tile": "tile_1_1", "pos": Vector2(0, 60), "side": 20.0, "level": 1, "yaw": 0.0}
	var model := {"standing": [on_road, beside], "roads": [road]}
	Clearance.apply(model, Builder.standing_key)
	var ids: Array = model.standing.map(func(s: Dictionary) -> String: return str(s.iid))
	_check(not ids.has("on") and ids.has("beside"), "clearance: a home standing on the carriageway is left out, one beside it stays")

func _test_depot_slides_off_a_carriageway() -> void:
	var depot := {"iid": "store:tile_1_1", "kind": "warehouse", "tile": "tile_1_1", "pos": Vector2(0, 0), "side": 40.0, "level": 1, "yaw": 0.0}
	var road := _road(Vector2(-400, 8), Vector2(400, 8))
	var model := {"standing": [depot], "roads": [road], "tiles": {"tile_1_1": {"center": Vector2(0, 0)}}}
	Clearance.apply(model, Builder.standing_key)
	var moved: Dictionary = model.standing[0]
	_check(float(moved.side) == 40.0 and (moved.pos as Vector2) != Vector2.ZERO and _carriageway_gap(moved, road) >= Clearance.CLEARANCE - 0.01,
		"clearance: a depot keeps its size and slides off the carriageway")
	_check(depot.pos == Vector2.ZERO, "clearance: the shared depot record is left as it was")
