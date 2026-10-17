extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Rail := preload("res://scripts/supply_chain_3d/railway.gd")
const Urban := preload("res://scripts/supply_chain_3d/rail_urban.gd")
const Elevation := preload("res://scripts/supply_chain_3d/rail_elevation.gd")

func _lines() -> Array:
	return [{"mode":"rails","level":2,"pts":[{"p":Vector2(-500,0)},{"p":Vector2(500,0)}]}]

func _test_rail_elevation_fixed_bore_and_smooth_approaches() -> void:
	var plan := Rail.network(_lines())
	var height := func(p: Vector2) -> float: return 34.0+3.0*sin(p.x/40.0)
	var result := Elevation.solve(plan,height,func(_p): return 1.0,func(p): return absf(p.x)<110,func(_p): return INF)
	var low := INF; var high := -INF; var cover := INF; var max_grade := 0.0
	for track in result.tracks:
		if not track.hidden: continue
		low=minf(low,minf(track.ha,track.hb));high=maxf(high,maxf(track.ha,track.hb))
		cover=minf(cover,minf(track.base_a-track.ha,track.base_b-track.hb))
	_check(high-low<.001 and cover>=14.0-.001,"Rail datum: undulating terrain does not deform a connected bore, with at least 14u burial")
	var flat := Elevation.solve(plan,func(_p): return 34.0,func(_p): return 1.0,func(p): return absf(p.x)<110,func(_p): return INF)
	for track in flat.tracks: max_grade=maxf(max_grade,absf(track.hb-track.ha)/track.a.distance_to(track.b))
	_check(max_grade<=Elevation.MAX_APPROACH_GRADE+.001,"Rail datum: flat-ground approaches stay below 12% instead of jumping 14u at a tile edge")
	_check(is_equal_approx(flat.tracks.front().ha,35.2) and is_equal_approx(flat.tracks.back().hb,35.2),"Rail datum: distant surface track keeps its original elevation")

func _test_rail_elevation_cover_cut_portal_and_cache_agree() -> void:
	var lines := _lines();var plan := Rail.network(lines)
	var flat := func(_p): return 34.0
	var urban := Urban.new()
	# The urban tile ends at x=300; busy roads reach its boundary. The rail
	# must emerge smoothly in the rural tile, not spring back to the surface.
	var roads := [{"a":Vector2(-290,0),"b":Vector2(290,0),"half":6.0}]
	urban.configure({"town":{"type":"urban","center":Vector2.ZERO}},roads,[Vector2(-20,0),Vector2(20,0)],plan,[],flat,func(_p): return 1.0)
	var art := Rail.build(lines,[],flat,func(_p): return 1.0,Vector2.ZERO,true,Callable(),Callable(),Callable(),{"plan":plan,"burial":urban.profile,"rail_profile":urban.track_profile})
	var roofs := true;var cuts := true;var covered := 0;var open_cuts := 0
	for sample in art.corridor_profiles[0].samples:
		if sample.hidden:
			covered+=1;roofs=roofs and is_equal_approx(urban.cut_height(sample.p,34.0,flat),34.0)
		elif urban.lowering(sample.p)>1.0:
			open_cuts+=1;cuts=cuts and absf(urban.cut_height(sample.p,34.0,flat)-(sample.h-1.4))<.01
	_check(covered>20 and roofs,"Rail datum: every hidden rail sample retains an intact roof")
	_check(open_cuts>10 and cuts,"Rail datum: visible approach floor follows exactly the rendered rail profile")
	var portals_fit: bool = art.portals.size()==2
	for portal in art.portals: portals_fit=portals_fit and portal.h+9.75<34.0
	_check(portals_fit,"Rail datum: both portal crowns fit below the original ground")
	var restored := Urban.new()
	for field in preload("res://scripts/supply_chain_3d/transport_bake.gd").URBAN: restored.set(field,urban.get(field))
	_check(restored.track_profile(Vector2(310,0))==urban.track_profile(Vector2(310,0)) and restored.buried(Vector2.ZERO),"Rail datum: baked restoration preserves absolute height and coverage without solving")

func _test_rail_elevation_junction_and_depot() -> void:
	var lines := _lines()
	lines.append({"mode":"rails","level":2,"pts":[{"p":Vector2(0,-400)},{"p":Vector2(0,400)}]})
	var result := Elevation.solve(Rail.network(lines),func(_p): return 34.0,func(_p): return 1.0,func(p): return p.x>0 and p.x<70 and absf(p.y)<30,func(_p): return INF)
	var datums := {}
	for track in result.tracks:
		if track.hidden: datums[snappedf(track.ha,.001)]=true
	_check(datums.size()==1,"Rail datum: all movements of a covered junction share one elevation")
	var yard := Elevation.solve(Rail.network(_lines()),func(_p): return 34.0,func(_p): return 1.0,func(_p): return true,func(p): return maxf(0,absf(p.x)-100))
	var clear := true
	for track in yard.tracks:
		if absf(track.a.x)<=100: clear=clear and not track.hidden_a and is_equal_approx(track.ha,35.2)
	_check(clear,"Rail datum: operating yard remains at grade even beside a covered district")
