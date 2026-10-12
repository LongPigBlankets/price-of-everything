extends Node
const Alignment := preload("res://scripts/supply_chain_3d/road_alignment.gd")
const Grade := preload("res://scripts/supply_chain_3d/road_grade.gd")
const Surface := preload("res://scripts/supply_chain_3d/road_surface.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures+=1; push_error(message)
func road(a: Vector2,b: Vector2) -> Dictionary:
	return {"a":a,"b":b,"tile":"test","level":2,"paved":true,"widths":[6.0,5.7,5.4,4.7]}
func model(roads: Array) -> Dictionary: return {"roads":roads,"tiles":{},"standing":[]}
func _ready() -> void:
	TelemetryState.enabled=false; SaveLoad.autosave_enabled=false
	var flat := func(_p: Vector2) -> float: return 34.0
	var low := func(_p: Vector2) -> float: return 6.0
	var level := func(p: Vector2) -> float: return 7.0 if absf(p.x)<40 else 6.0
	var art := Alignment.new()
	var original := [road(Vector2(-150,0),Vector2(150,0))]
	var roads := art.configure(model(original),flat,low)
	check(roads.size()==1 and not roads[0].tunnel,"Height 6 keeps surface road")
	roads=art.configure(model(original),flat,level)
	check(roads.size()==3 and roads[1].tunnel,"Mountain inside one segment is hidden with visible approaches")
	check(art.portals.size()==2,"Tunnel has exactly two portals")
	check(absf(roads[0].b.x+40)<0.01 and absf(roads[2].a.x-40)<0.01,"Tunnel transitions match height boundary precisely")
	check(roads[0].tunnel_b and roads[2].tunnel_a,"No rounded road caps protrude inside tunnel")
	var grade := Grade.new(); grade.configure(roads,func(p): return 34+absf(p.x)*0.2)
	check(grade.sample(Vector2.ZERO).is_empty(),"Covered road excluded from surface grading and rail crossing detection")
	check(grade.earth_height(Vector2.ZERO,90)==90,"Tunnel leaves mountain roof intact")
	var surface := Surface.new(); surface.configure(roads,flat)
	check(surface.ways.size()==2,"Asphalt and markings only receive visible road")
	check(art.mesh_for("test",flat).get_surface_count()>0,"Road portals have geometry")
	roads=art.configure(model([road(Vector2(150,0),Vector2(-150,0))]),flat,level)
	check(art.portals.size()==2 and roads[1].tunnel,"Tunnel also works with reversed road direction")
	roads=art.configure(model([road(Vector2(-150,0),Vector2(-40,0)),road(Vector2(-40,0),Vector2(40,0)),road(Vector2(40,0),Vector2(150,0))]),flat,level)
	check(art.portals.size()==2,"Portals deduplicated at existing segment boundaries")
	roads=art.configure(model(original),flat,func(_p): return 8.0)
	check(roads.all(func(r): return r.tunnel) and art.portals.is_empty(),"Fully covered height 8 road has no exposed surface or stray portal")
	roads=art.configure(model(original),flat,func(p): return 7.0 if absf(p.x)<70 and absf(p.x)>10 else 6.0)
	check(art.portals.size()==2,"Short daylight gap stays inside one mountain tunnel")
	check(roads.filter(func(r): return r.tunnel).size()>=3,"Merged bore still hides both high sections")
	roads=art.configure(model(original),flat,func(p): return 7.0 if p.y>4 else 6.0)
	check(roads.all(func(r): return r.tunnel),"A high band under the road edge also covers the carriageway")
	var slope := func(p: Vector2) -> float: return 34+clampf(p.x+120,0,240)*0.5
	var m := model([road(Vector2(-150,0),Vector2(150,0))])
	roads=art.configure(m,slope,low)
	check(art.switchbacks>0,"Steep 50 percent climb becomes a serpentine")
	var length := 0.0; var lateral := 0.0; var maximum := 0.0
	for r in roads:
		length+=r.a.distance_to(r.b); lateral=maxf(lateral,absf(r.a.y))
		if r.has("road_ha"): maximum=maxf(maximum,absf(r.road_hb-r.road_ha)/r.a.distance_to(r.b))
	check(length>800 and lateral>30,"Switchbacks gain sufficient travel distance and bend sideways")
	check(maximum<=Alignment.MAX_GRADE+0.001,"Engineered ascent never exceeds target grade")
	check(roads[0].a==Vector2(-150,0) and roads[-1].b==Vector2(150,0),"Original connections remain fixed")
	grade.configure(roads,slope)
	for r in grade.segments:
		check(absf(r.hb-r.ha)/r.a.distance_to(r.b)<=Alignment.MAX_GRADE+0.005,"Shared road datum preserves switchback grade")
	var authored := preload("res://scripts/supply_chain_3d/authored_road_profile.gd").new()
	authored.restore({"region":{"test":Vector2.ZERO},"crossings":[],"segments":[{"a":Vector2(-200,0),"b":Vector2(200,0),"ha":110.0,"hb":110.0,"half":6.0,"bridge":false}]})
	var engineered := road(Vector2(-100,0),Vector2(100,0)); engineered.road_ha=34.0; engineered.road_hb=54.0
	grade.configure([engineered],flat,authored)
	check(absf(grade.height_at(Vector2.ZERO,0)-44)<0.05,"Old authored hill surface cannot override an engineered road grade")
	authored.segments[0].bridge=true
	grade.configure([engineered],flat,authored)
	check(grade.height_at(Vector2.ZERO,0)>109,"Actual river bridge profile remains authoritative")
	engineered.serpentine=true
	grade.configure([engineered],flat,authored)
	check(absf(grade.height_at(Vector2.ZERO,0)-44)<0.05,"A relocated switchback cannot inherit a nearby old bridge ramp")
	var lower := road(Vector2(-100,0),Vector2(100,0)); lower.road_ha=34.0; lower.road_hb=34.0
	var upper := road(Vector2(-100,15),Vector2(100,15)); upper.road_ha=54.0; upper.road_hb=54.0
	grade.configure([lower,upper],flat)
	check(absf(grade.height_at(Vector2(0,3),0)-34)<0.01,"Higher hairpin arm cannot pull the lower carriageway uphill")
	# Surface tessellation must use the exact shared grade, without a second
	# blend that drags the low arm upward or the high arm below the ground.
	surface.configure([lower,upper],func(p): return grade.height_at(p,34))
	check(absf(surface._sample(Vector2i(0,2))-(grade.height_at(Vector2(0,6),34)+0.85))<0.001,"Rendered road uses the shared grade without blending neighbouring arms")
	surface.finish_build()
	var Index := preload("res://scripts/supply_chain_3d/road_index.gd")
	var near_paths := [
		{"id":"incoming","class":"mid","points":PackedVector2Array([Vector2(-60,0),Vector2(-11.5,0)])},
		{"id":"through","class":"minor","points":PackedVector2Array([Vector2(0,-60),Vector2(0,60)])}]
	check(Index.join(near_paths,flat)==1,"Facing roads separated by a 2.3u visible gap join")
	check(near_paths[0].points[-1]==Vector2.ZERO and near_paths[1].points.has(Vector2.ZERO),"Near join extends to the centreline and splits the receiving road")
	var overlapping := [
		{"id":"low","class":"mid","points":PackedVector2Array([Vector2(-40,0),Vector2(2,0)])},
		{"id":"ramp","class":"mid","points":PackedVector2Array([Vector2(-2,1),Vector2(40,1)])}]
	check(Index.join(overlapping,flat)==1 and overlapping[0].points[-1]==overlapping[1].points[0],"Overlapping collinear end caps share one grading node")
	var separated := [
		{"id":"a","class":"mid","points":PackedVector2Array([Vector2(-60,0),Vector2(-14,0)])},
		{"id":"b","class":"minor","points":PackedVector2Array([Vector2(0,-60),Vector2(0,60)])}]
	check(Index.join(separated,flat)==0,"Roads beyond the visible-gap tolerance remain separate")
	separated[0].points[-1]=Vector2(-11.5,0); separated[1].layer=1
	check(Index.join(separated,flat)==0,"Nearby grade-separated roads do not acquire a junction")
	var approach := model([road(Vector2(-150,0),Vector2(150,0))])
	var cliff := func(p: Vector2) -> float: return 34+clampf(p.x+60,0,100)*1.2
	var cliff_level := func(p: Vector2) -> float: return 7.0 if p.x>=40 else 6.0
	var entering := art.configure(approach,cliff,cliff_level,func(p): return absf(p.y)>8)
	check(not art.portals.is_empty() and art.portals[0].p.x<0,"Constrained tunnel entrance retreats to the foot of a cliff")
	for r in entering:
		if not r.tunnel: check(absf(cliff.call(r.b)-cliff.call(r.a))/maxf(0.01,r.a.distance_to(r.b))<0.16,"Visible tunnel approach avoids the original cliff ascent")
	var protected := model([road(Vector2(-150,0),Vector2(150,0))])
	protected.standing=[{"pos":Vector2(0,65),"pad":110}]
	var around := art.configure(protected,slope,low)
	for r in around:
		check(not Rect2(-58,7,116,116).has_point((r.a+r.b)*0.5),"Rerouted road avoids the protected building")
	roads=art.configure(m,slope,low)
	var snapshot := var_to_bytes(roads)
	check(snapshot==var_to_bytes(art.configure(m,slope,low)),"Alignment is deterministic")
	# An impassable ocean on both sides must never acquire a new road.
	roads=art.configure(m,slope,low,func(p): return absf(p.y)>10)
	check(art.switchbacks==0 and roads.all(func(r): return absf(r.a.y)<0.01),"Constrained routes do not create ocean crossings")
	if "--map" in OS.get_cmdline_user_args(): audit_map()
	print("[road-check] failures=",failures," grade=",maximum," length=",length)
	get_tree().quit(1 if failures else 0)
func audit_map() -> void:
	var Builder := preload("res://scripts/supply_chain_3d/world_builder.gd")
	var Authored := preload("res://scripts/supply_chain_3d/authored_region.gd")
	var terrain := preload("res://scripts/hex_map.gd").new()
	terrain.tile_set=load("res://assets/main_tileset.tres"); terrain._generate_tile_data(); terrain._load_tile_overrides()
	var builder := Builder.new()
	builder.ground=Builder.Coast.ground_for(terrain,{},preload("res://scripts/empire_board_relief.gd").plates(terrain,{}))
	var centers := {}; var flags := {}; var m := {"tiles":{},"roads":[],"standing":[],"lines":[]}
	for tile in terrain.tiles.values():
		centers[tile.id]=Builder.Model.tile_center(terrain,tile.id); flags[tile.id]=true
		m.tiles[tile.id]={"center":centers[tile.id],"type":Catalog.tile_type(tile.id)}
	m.roads=Authored.compile(Authored.source_paths(terrain,flags),centers,builder.natural_height).roads
	var before := _components(m.roads)
	builder.tiles=m.tiles
	builder.prepare_transport(m)
	var after := _components(m.roads)
	print("[ROAD-CONNECTIVITY] before=",before," after=",after)
	check(after==before,"Road realignment preserves the authored network connectivity")
	var by_tile := {}
	for r in m.roads:
		if r.get("serpentine",false): by_tile[r.tile]=int(by_tile.get(r.tile,0))+1
	print("[ROAD-MAP] bends=",builder.road_alignment.switchbacks," constrained=",builder.road_alignment.constrained," eased=",builder.road_alignment.grade_eased," portals=",builder.road_alignment.portals.size()," changed_tiles=",by_tile.size())

	builder.road_surface.finish_build(); terrain.free()

func _components(roads: Array) -> int:
	var parents := {}
	for r in roads:
		var a := Alignment._key(r.a); var b := Alignment._key(r.b)
		if not parents.has(a): parents[a]=a
		if not parents.has(b): parents[b]=b
		var ra := a; var rb := b
		while parents[ra]!=ra: ra=parents[ra]
		while parents[rb]!=rb: rb=parents[rb]
		parents[ra]=rb
	var roots := {}
	for key in parents:
		var root: Vector2i=key
		while parents[root]!=root: root=parents[root]
		roots[root]=true
	return roots.size()
