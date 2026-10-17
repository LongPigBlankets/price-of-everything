extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Grade := preload("res://scripts/supply_chain_3d/road_grade.gd")
const Urban := preload("res://scripts/supply_chain_3d/rail_urban.gd")
const Rail := preload("res://scripts/supply_chain_3d/railway.gd")
const Crossing := preload("res://scripts/supply_chain_3d/rail_crossings.gd")
const Station := preload("res://scripts/supply_chain_3d/rail_station.gd")
const Depot := preload("res://scripts/supply_chain_3d/rail_depot.gd")

func fixture(busy := false, hidden := false) -> Dictionary:
	var lines := [{"mode":"rails","level":2,"pts":[{"p":Vector2(-700,0)},{"p":Vector2(700,0)}]}]
	var roads := [{"a":Vector2(0,-400),"b":Vector2(0,400),"level":1,"tile":"tile_4_10","source":"crossing","widths":[3.0,2.8,2.6,2.4]}]
	var grade := Grade.new();grade.configure(roads,func(_p):return 34.0)
	var plan := Rail.network(lines);var urban := Urban.new()
	var yards: Array=[{"pos":Vector2(250,0),"yaw":0.0}] if busy else []
	urban.configure({},[],[],plan,yards,func(_p):return 34.0,func(_p):return 1.0)
	if hidden:
		for track in urban.tracks:track.hidden=true;track.hidden_a=true;track.hidden_b=true;track.active=true;track.ha=21.2;track.hb=21.2
	Crossing.build(grade,plan,urban,yards)
	return {"grade":grade,"urban":urban,"plan":plan,"lines":lines}

func _test_rail_crossings_busy_bridge_clearance_and_grade() -> void:
	var f := fixture(true);var g: RefCounted=f.grade
	_check(g.crossings.size()==1 and g.crossings[0].mode=="bridge","Crossings: depot approach selects one road bridge")
	var max_grade := 0.0
	for s in g.segments:max_grade=maxf(max_grade,absf(s.hb-s.ha)/s.a.distance_to(s.b))
	_check(max_grade<=Crossing.MAX_GRADE+.001,"Crossings: both bridge approaches stay at or below 8%")
	_check(g.height_at(Vector2.ZERO,0)-.5-(35.2+1.25)>=Rail.CLEARANCE,"Crossings: bridge underside clears rail heads")
	_check(is_equal_approx(g.height_at(Vector2(0,-390),0),34.0) and is_equal_approx(g.height_at(Vector2(0,390),0),34.0),"Crossings: ascent and descent return to the original road")

func _test_rail_crossings_quiet_level_and_buried() -> void:
	var f := fixture();var g: RefCounted=f.grade
	_check(g.crossings.size()==1 and g.crossings[0].mode=="level" and g.bridges.is_empty(),"Crossings: quiet branch uses a level crossing")
	_check(absf(g.height_at(Vector2.ZERO,0)+1.09-(35.2+1.25))<.05,"Crossings: road surface meets the running rail without a hump")
	var prof := Rail.profile(PackedVector2Array([Vector2(-100,0),Vector2(100,0)]),g.segments,func(_p):return 34.0,func(_p):return 1.0)
	_check(prof.crossings.is_empty(),"Crossings: explicit level crossing suppresses the automatic rail-over-road bridge")
	var hidden := fixture(false,true)
	_check(hidden.grade.crossings[0].mode=="tunnel" and hidden.grade.bridges.is_empty() and is_equal_approx(hidden.grade.height_at(Vector2.ZERO,0),34.0),"Crossings: already buried rail leaves the surface road untouched")

func _test_rail_crossings_connected_distance_not_proximity() -> void:
	var tracks := [{"a":Vector2.ZERO,"b":Vector2(50,0)},{"a":Vector2(0,200),"b":Vector2(50,200)}]
	var distance := Crossing.depot_distances(tracks,[{"pos":Vector2.ZERO,"yaw":0.0}])
	_check(distance.has(Rail._key(Vector2.ZERO)) and not distance.has(Rail._key(Vector2(0,200))),"Crossings: a disconnected nearby siding does not inherit depot traffic")

func _test_rail_crossings_station_flat_and_depot_lead() -> void:
	var station := {"pos":Vector2.ZERO,"dir":Vector2.RIGHT,"normal":Vector2.DOWN,"track_length":80.0}
	var plan := Rail.network([{"mode":"rails","level":2,"pts":[{"p":Vector2.ZERO},{"p":Vector2(400,0)}]}])
	var solved := preload("res://scripts/supply_chain_3d/rail_elevation.gd").solve(plan,func(_p):return 34.0,func(_p):return 1.0,func(p):return p.x>75,func(_p):return INF,[station])
	var low := INF;var high := -INF
	for t in solved.tracks:
		if t.a.x<65:low=minf(low,t.ha);high=maxf(high,t.ha)
	_check(high-low<.001,"Station: the terminal platform tracks stay level beside the covered line")
	var depot := {"tile":"tile_5_10","pos":Vector2(2790,5550),"yaw":2*PI/3}
	var anchor := Vector2(2700,5520)
	var line := {"a":"tile_5_10","b":"tile_5_9","pts":[{"p":anchor},{"p":Vector2(2700,5361.6)},{"p":Vector2(2700,5198.4)},{"p":Vector2(2700,5040)}]}
	var join := Depot.connection(depot,anchor,[line]);var outer := Depot.world(depot,Vector2(-280,0));var inner := Depot.world(depot,Vector2(-100,0))
	var turn := absf((outer-join).angle_to(inner-outer))
	_check(join==line.pts[2].p and turn<deg_to_rad(100),"Depot: the lead joins an existing mainline vertex with a turn below 100 degrees, replacing the 150-degree reversal")

func _test_rail_crossings_sloping_branch_is_level_across_the_road() -> void:
	var urban := Urban.new();var plan := Rail.network([{"mode":"rails","level":2,"pts":[{"p":Vector2(-300,0)},{"p":Vector2(300,0)}]}])
	urban.configure({},[],[],plan,[],func(p):return 34+clampf(p.x*.35,-10,10),func(_p):return 1.0)
	var c := {"p":Vector2.ZERO,"dir":Vector2.DOWN,"rail_dir":Vector2.RIGHT,"half":4.0,"bed":35.2}
	Crossing.level_rail(urban,c)
	var flat := true;var largest := 0.0
	for track in urban.tracks:
		if absf(track.a.x)<9:flat=flat and absf(track.ha-35.2)<.001
		largest=maxf(largest,absf(track.hb-track.ha)/track.a.distance_to(track.b))
	_check(flat and largest<=.101,"Crossings: a sloping branch gets a flat rail section and approaches no steeper than 10%")

func _test_rail_crossings_curved_deck_covers_both_intersections() -> void:
	var urban := Urban.new()
	var lines := [{"mode":"rails","level":2,"pts":[{"p":Vector2(-300,-25)},{"p":Vector2(300,-25)}]},
		{"mode":"rails","level":2,"pts":[{"p":Vector2(-300,25)},{"p":Vector2(300,25)}]}]
	var plan := Rail.network(lines)
	urban.configure({},[],[],plan,[],func(_p):return 34.0,func(_p):return 1.0)
	var roads: Array=[];var pts := PackedVector2Array([Vector2(0,-250),Vector2(0,0),Vector2(8,50),Vector2(8,250)])
	for i in range(1,pts.size()):roads.append({"a":pts[i-1],"b":pts[i],"source":"curve","tile":"tile_5_9","level":3,"widths":[8.4,7.8,7.1,6.7]})
	var grade := Grade.new();grade.configure(roads,func(_p):return 34.0)
	Crossing.build(grade,plan,urban,[])
	_check(grade.crossings.size()==1 and grade.crossings[0].points.size()==2,"Crossings: a curved road over two nearby tracks becomes one deck")
	var clear := true
	for p in grade.crossings[0].points:clear=clear and grade.height_at(p,0)-.5-36.45>=Rail.CLEARANCE-.01
	_check(clear,"Crossings: the grouped deck clears both rail intersections, including the curved end")

func _test_rail_crossings_station_access_connects_to_two_lane_road() -> void:
	var road := {"a":Vector2(-180,-50),"b":Vector2(180,-50),"level":1,"tile":Station.TILE,"source":"street","widths":[3.0,2.8,2.6,2.4]}
	var model := {"tiles":{Station.TILE:{"center":Vector2.ZERO}},"roads":[road],
		"lines":[{"mode":"rails","level":2,"pts":[{"p":Vector2(-100,0)},{"p":Vector2(1000,0)}]}],
		"authored_region":{"tiles":{Station.TILE:Vector2.ZERO},"paths":[{"id":"street","class":"minor","layer":0,"level":1,"points":PackedVector2Array([road.a,road.b])}]}}
	Station.apply(model,func(_p):return 34.0)
	_check(model.stations.size()==1 and model.stations[0].road_source=="street","Station: places the entrance beside the terminal's nearby two-lane road")
	var joins := 0
	for segment in model.roads:
		if segment.a.distance_to(model.stations[0].road_join)<.01 or segment.b.distance_to(model.stations[0].road_join)<.01:joins+=1
	_check(joins==3,"Station: the thin access road makes a connected T-junction")

func _test_rail_crossings_recessed_buffers_follow_the_track() -> void:
	var lines := [{"mode":"rails","level":2,"pts":[{"p":Vector2.ZERO},{"p":Vector2(100,0)}]}]
	var art := Rail.build(lines,[],func(_p):return 34.0,func(_p):return 1.0,Vector2.ZERO,true,Callable(),Callable(),Callable(),
		{"rail_profile":func(_p):return Vector3(21.2,0,1)})
	var highest := -INF
	for v in art.detail.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		if absf(v.x)<1:highest=maxf(highest,v.y)
	_check(highest<26 and highest>24,"Station: buffer fittings use the recessed rail elevation instead of floating at natural ground height")

func _test_rail_crossings_reject_level_site_without_ramp_space() -> void:
	var urban := Urban.new();var plan := Rail.network([{"mode":"rails","level":2,"pts":[{"p":Vector2(-300,-300)},{"p":Vector2(300,300)}]}])
	urban.configure({},[],[],plan,[],func(_p):return 34.0,func(_p):return 1.0)
	var roads: Array=[]
	for pair in [[Vector2(-200,0),Vector2(40,0),3,"main"],[Vector2(40,0),Vector2(200,0),3,"main"],[Vector2(40,0),Vector2(40,200),1,"side"]]:
		roads.append({"a":pair[0],"b":pair[1],"level":pair[2],"source":pair[3],"tile":"tile_5_9","widths":[4.0,3.7,3.4,3.0]})
	var grade := Grade.new();grade.configure(roads,func(_p):return 34.0)
	Crossing.build(grade,plan,urban,[])
	_check(grade.crossings.size()==2 and grade.crossings.all(func(c):return c.mode=="bridge"),"Crossings: a quiet site too close to a bridge is also grade-separated")
	_check(grade.crossings.any(func(c):return c.has("level_candidate")),"Crossings: records why the quiet level-crossing candidate lacks approach space")

func _test_rail_crossings_eases_join_with_existing_hillside_road() -> void:
	var f := fixture(true);var grade: RefCounted=f.grade
	for node in grade.nodes.values():
		if node.p.y>110:node.base=46.0;node.h=maxf(node.h,46.0)
	Crossing.ease_joins(grade);grade.refresh()
	var largest := 0.0
	for segment in grade.segments:
		if segment.over_rail:largest=maxf(largest,absf(segment.ha-segment.hb)/segment.a.distance_to(segment.b))
	_check(largest<=Crossing.MAX_GRADE+.001,"Crossings: an existing hillside at the ramp end cannot leave a sudden steep join")
