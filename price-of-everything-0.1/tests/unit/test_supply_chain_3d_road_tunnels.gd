extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Alignment := preload("res://scripts/supply_chain_3d/road_alignment.gd")
const Grade := preload("res://scripts/supply_chain_3d/road_grade.gd")

func _road(a: float, b: float, tile := "test") -> Dictionary:
	return {"a":Vector2(a,0),"b":Vector2(b,0),"tile":tile,"level":1,"widths":[3.0,2.8,2.5,2.0]}

func _alignment(length: float) -> RefCounted:
	var alignment := Alignment.new()
	alignment._height=func(_p: Vector2) -> float: return 34.0
	alignment._level=func(p: Vector2) -> float: return 7.0 if p.x>=0 and p.x<=length else 6.0
	return alignment

func _test_road_tunnels_minimum_continuous_underground_length() -> void:
	for length in [3.4095,9.99,10.0,10.01,30.0]:
		var alignment := _alignment(length)
		# Source fragments and a tile boundary cannot split one legitimate bore.
		var roads: Array=alignment._tunnels([_road(-30,4),_road(4,8,"next"),_road(8,50,"next")])
		var expected: bool=length>=10
		_check(roads.any(func(r):return r.tunnel)==expected,"Road tunnel: %.4fu threshold" % length)
		_check(alignment.portals.size()==(2 if expected else 0),"Road tunnel: entrances only for qualifying bore %.4fu" % length)
		if expected:
			for portal in alignment.portals:
				_check(portal.depth<=length*.45+.001,"Road tunnel: covers leave space between opposite entrances")
		else:
			var grade := Grade.new()
			grade.configure(roads,func(_p):return 34.0)
			_check(not grade.sample(Vector2(length*.5,0)).is_empty(),"Road tunnel: rejected bore remains in surface cutting")

func _test_road_tunnels_do_not_add_disconnected_or_branch_lengths() -> void:
	var alignment := _alignment(6)
	alignment._level=func(p: Vector2) -> float: return 7.0 if (p.x>=0 and p.x<=6) or (p.x>=15 and p.x<=21) else 6.0
	var roads: Array=alignment._tunnels([_road(-30,60)])
	_check(not roads.any(func(r):return r.tunnel) and alignment.portals.is_empty(),"Road tunnel: two short ridge grazes do not qualify through daylight merging")
	roads=[_road(-6,0),_road(0,6),{"a":Vector2.ZERO,"b":Vector2(0,6)}]
	for road in roads: road.tunnel=true
	var runs: Array=Alignment._tunnel_runs(roads)
	_check(runs.size()==3 and runs.all(func(r):return is_equal_approx(r.length,6)),"Road tunnel: junction arms are measured separately")

func _test_road_tunnels_mesh_respects_cover_depth() -> void:
	var alignment := Alignment.new()
	alignment.portals=[{"p":Vector2.ZERO,"dir":Vector2.RIGHT,"tile":"test","half_width":4.8,"depth":4.5}]
	var mesh: ArrayMesh=alignment.mesh_for("test",func(_p):return 34.0,Vector2.ZERO,func(_p):return 34.0)
	_check(mesh.get_aabb().end.x<=4.501,"Road tunnel: renderer does not replace calculated cover depth with 22u")
