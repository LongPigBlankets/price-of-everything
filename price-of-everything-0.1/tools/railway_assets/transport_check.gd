extends Node
const Grade := preload("res://scripts/supply_chain_3d/road_grade.gd")
const Urban := preload("res://scripts/supply_chain_3d/rail_urban.gd")
const Rail := preload("res://scripts/supply_chain_3d/railway.gd")
const Depot := preload("res://scripts/supply_chain_3d/rail_depot.gd")
class FlatGround extends RefCounted:
	func height(_p: Vector2) -> float: return 34.0
	func gradient(_p: Vector2) -> Vector2: return Vector2.ZERO
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)
func road(a: Vector2,b: Vector2) -> Dictionary:
	return {"a":a,"b":b,"tile":"test","level":2,"paved":true,"widths":[6.0,5.7,5.4,4.7]}
func route(a: Vector2,b: Vector2) -> Dictionary: return {"mode":"rails","level":2,"pts":[{"p":a},{"p":b}]}
func _ready() -> void:
	TelemetryState.enabled=false; SaveLoad.autosave_enabled=false
	var slope := func(p: Vector2) -> float: return 34+p.y*0.8+p.x*0.03
	var flat := func(_p: Vector2) -> float: return 34.0
	var low := func(_p: Vector2) -> float: return 2.0
	var grade := Grade.new()
	grade.configure([road(Vector2(-200,0),Vector2(200,0))],slope)
	check(absf(grade.height_at(Vector2(0,-5),0)-grade.height_at(Vector2(0,5),0))<0.05,"Road stays level from side to side on an 80% terrain cross-slope")
	check(grade.earth_height(Vector2(0,5),slope.call(Vector2(0,5)))<slope.call(Vector2(0,5))-4,"Uphill bank is physically cut down to the carriageway")
	check(is_equal_approx(grade.earth_height(Vector2(0,40),slope.call(Vector2(0,40))),slope.call(Vector2(0,40))),"Land outside the shoulder keeps its height")
	# The bank at a bridge abutment must not obscure the road deck.
	grade.configure([road(Vector2(-40,0),Vector2.ZERO),road(Vector2.ZERO,Vector2(25,30))],slope)
	for node in grade.nodes.values(): node.core=true
	grade.refresh()
	check(grade.earth_height(Vector2(0,4),100)<grade.height_at(Vector2(0,4),100),"A bridge meeting an uphill bank cuts through intrusive terrain")
	check(grade.earth_height(Vector2(0,4),20)==20,"Bridge cutting preserves the valley below the deck")
	var plain := road(Vector2(-40,0),Vector2(40,0))
	var ramp := road(Vector2(-40,10),Vector2(40,10)); ramp.road_ha=44.0; ramp.road_hb=44.0
	grade.configure([plain,ramp],flat)
	check(grade.earth_height(Vector2(0,3),34)<34.1,"Raised approach cannot bury the neighbouring unchanged road")
	var rail_lines := [route(Vector2(-200,0),Vector2(200,0)),route(Vector2(0,-200),Vector2(0,200))]
	var plan := Rail.network(rail_lines)
	grade.configure([road(Vector2(-200,-50),Vector2(200,50))],flat)
	grade.bridge_rail_junctions(plan,flat,func(_p): return false)
	check(not grade.bridges.is_empty(),"Road crossing a rail junction receives a bridge")
	check(grade.height_at(Vector2.ZERO,0)-34-Rail.DECK_DEPTH>=Rail.CLEARANCE,"Road deck clears the entire junction")
	var art := Rail.build(rail_lines,grade.segments,flat,low)
	for prof in art.profiles:
		for sample in prof.samples: check(sample.h<36,"Rail junction remains at grade under the road bridge")
	grade.configure([road(Vector2(-200,200),Vector2(200,200))],flat)
	grade.bridge_rail_junctions(plan,flat,func(_p): return false)
	check(grade.bridges.is_empty(),"Unrelated road outside the junction stays on ground")
	grade.configure([road(Vector2(-100,0),Vector2(100,0)),road(Vector2(-12,-100),Vector2(-12,100)),road(Vector2(12,-100),Vector2(12,100))],flat)
	var urban := Urban.new()
	urban.configure({"test":{"type":"urban","center":Vector2.ZERO}},grade.segments,[Vector2(-12,0),Vector2(12,0)],plan)
	check(urban.buried(Vector2(0,15)),"Urban rail within 20u of busy road is covered")
	check(not urban.buried(Vector2(0,100)),"Rail outside busy district stays visible")
	check(urban.lowering(Vector2(0,45))>0,"Tunnel has a descending approach")
	var underground := Rail.build([route(Vector2(-220,35),Vector2(220,35))],[],flat,low,Vector2.ZERO,true,Callable(),Callable(),Callable(),{"burial":urban.profile})
	check(underground.profiles.any(func(p): return p.samples.any(func(s): return s.buried)),"Renderer omits covered urban track")
	check(underground.portals.size()>=2,"Urban tunnel has entrance and exit")
	urban.configure({"test":{"type":"rural","center":Vector2.ZERO}},grade.segments,[Vector2(-12,0),Vector2(12,0)],plan)
	check(not urban.buried(Vector2.ZERO),"Rural rail remains above ground")
	var depot := {"pos":Vector2.ZERO,"yaw":0.0,"height":34.0,"tile":"test"}
	urban.configure({"test":{"type":"urban","center":Vector2.ZERO}},grade.segments,[Vector2(-12,0),Vector2(12,0)],plan,[depot])
	check(not urban.buried(Vector2(0,15)) and urban.lowering(Vector2(0,15))==0, "City depot sidings stay at the surface")
	check(is_equal_approx(Depot.SIDING_CENTER-Rail.CORRIDOR_WIDTH*0.5-26.75,3.0),"Nearest siding bed has a 3u clear gap from the depot wall")
	var yard := Rail.network(Depot.lines(depot,Vector2(-220,0)))
	check(yard.buffers.size()==10,"Depot has six shed-track buffers, two siding buffers and paired approach ends")
	check(Depot.mesh(depot,Vector2.ZERO).get_surface_count()>0,"Depot shed geometry exists")
	var sidings := Rail.network([Depot.lines(depot,Vector2(-220,0)).back()])
	for path in sidings.paths:
		for p in path.points:
			check(not Rect2(40,-30,75,60).has_point(p),"Loading sidings clear the depot walls")
	var builder := preload("res://scripts/supply_chain_3d/world_builder.gd").new()
	builder.ground=FlatGround.new(); builder.tiles={"test":{"center":Vector2.ZERO,"type":"rural"}}
	builder.road_grade.configure([road(Vector2(-200,0),Vector2(200,0))],slope)
	builder.transport_ready=true
	var terrain := builder._surface("test",24.0)
	check(terrain.get_surface_count()>0,"Carved terrain produces visible triangles")
	var vertices: PackedVector3Array = terrain.get_faces()
	var covered := 0
	for i in range(0,vertices.size(),3):
		var middle := (vertices[i]+vertices[i+1]+vertices[i+2])/3.0
		if absf(middle.x)<190 and absf(middle.z)<5: covered+=1
	check(covered==0,"Terrain triangles cannot cover the level road cutting")
	depot.height=38.0
	builder.depots=[depot]
	builder.road_grade.configure([road(Vector2(70,-100),Vector2(70,160))],builder.formation_height)
	check(builder.road_grade.height_at(Vector2(70,45),0)>37.8,"Roads follow a raised depot formation instead of disappearing beneath it")
	print("[transport] failures=",failures)
	get_tree().quit(1 if failures else 0)
