extends RefCounted
## Stoneshore-only presentation roads. Reserve both connections before frontage.
const Region := preload("res://scripts/supply_chain_3d/authored_region.gd")
const Rail := preload("res://scripts/supply_chain_3d/railway.gd")
const Depot := preload("res://scripts/supply_chain_3d/rail_depot.gd")
const Trial := preload("res://scripts/supply_chain_3d/stoneshore_trial.gd")
const WIDTHS := [4.8,4.6,4.4,4.2]
const ROAD_HALF := 6.8 # casing + two 2u urban sidewalks
const CLEARANCE := 10.0
const OFFSET := ROAD_HALF+Rail.CORRIDOR_WIDTH*.5+CLEARANCE
const A := "depot:stoneshore:coastal"
const B := "depot:stoneshore:bridge"
const WEST := "depot:stoneshore:west_join"

static func nearest(p: Vector2, paths: Array, ids: Array) -> Vector2:
	var best := p;var distance := INF
	for path in paths:
		if str(path.id) not in ids:continue
		for i in range(1,path.points.size()):
			var q := Geometry2D.get_closest_point_to_segment(p,path.points[i-1],path.points[i])
			if p.distance_to(q)<distance:distance=p.distance_to(q);best=q
	return best

static func rounded(points: PackedVector2Array, reach := 10.0) -> PackedVector2Array:
	var out := PackedVector2Array([points[0]])
	for i in range(1,points.size()-1):
		var p: Vector2=points[i]
		var radius := minf(reach,minf(p.distance_to(points[i-1]),p.distance_to(points[i+1]))*.3)
		var a := p.move_toward(points[i-1],radius);var b := p.move_toward(points[i+1],radius)
		out.append(a)
		for step in range(1,9):
			var t := step/8.0
			out.append(a.lerp(p,t).lerp(p.lerp(b,t),t))
	out.append(points[-1]);return out

static func rail_distance(p: Vector2, plan: Dictionary) -> float:
	var distance := INF
	for c in plan.corridors:
		for i in range(1,c.points.size()):distance=minf(distance,p.distance_to(Geometry2D.get_closest_point_to_segment(p,c.points[i-1],c.points[i])))
	return distance

static func offset_point(x: float, plan: Dictionary, depot: Dictionary) -> Vector2:
	var low := INF
	for c in plan.corridors:
		for i in range(1,c.points.size()):
			var a: Vector2=(c.points[i-1]-depot.pos).rotated(-depot.yaw)
			var b: Vector2=(c.points[i]-depot.pos).rotated(-depot.yaw)
			if x<minf(a.x,b.x) or x>maxf(a.x,b.x) or absf(a.x-b.x)<.001:continue
			low=minf(low,lerpf(a.y,b.y,(x-a.x)/(b.x-a.x)))
	return Depot.world(depot,Vector2(x,(low if is_finite(low) else 0.0)-OFFSET-2.0))

static func local_lines(lines: Array) -> Array:
	# This road follows the Stoneshore fan, even when the model contains the
	# entire continent. Distant tracks can share its local X coordinate.
	return lines.filter(func(line):
		for p in line.get("pts",[]):
			if str(p.get("tile","")) not in Trial.TILES:return false
		return true)

static func design(paths: Array, depot: Dictionary, plan: Dictionary) -> Dictionary:
	var original: Dictionary={}
	for path in paths:
		if path.id=="r:untitled:65":original=path
	if original.is_empty():return {}
	var coast: Vector2=original.points[-1]
	var start: Vector2=original.points[0]
	if (coast-depot.pos).rotated(-depot.yaw).y>(start-depot.pos).rotated(-depot.yaw).y:
		var swap := coast;coast=start;start=swap
	var a := rounded(PackedVector2Array([coast,depot.pos+Vector2(70,110),depot.pos+Vector2(25,126),
		Depot.world(depot,Vector2(165,-65)),Depot.world(depot,Vector2(165,40)),
		nearest(depot.pos+Vector2(-125,103),paths,["r:untitled:66"])]))
	# The only straight pair between the fan and the broad northern lead.
	var bridge := {};var score := INF
	for c in plan.corridors:
		if c.has("junction"):continue
		var p: Vector2=(c.points[0]+c.points[-1])*.5
		var local: Vector2=(p-depot.pos).rotated(-depot.yaw)
		var candidate := absf(local.x+190)+absf(local.y)*10
		if candidate<score:score=candidate;bridge={"p":p,"x":local.x,"dir":(c.points[-1]-c.points[0]).normalized()}
	if bridge.is_empty():return {}
	# Keep the red road until approaching the outermost fan corridor. Leave a
	# little extra room for the rounded turn, settling to 10u beside the ballast.
	var turn := coast
	for step in range(1,1001):
		var p := coast.lerp(start,step/1000.0)
		if rail_distance(p,plan)<OFFSET+12:break
		turn=p
	var b := PackedVector2Array([coast,turn])
	var turn_x: float=(turn-depot.pos).rotated(-depot.yaw).x
	for x in range(floori(turn_x)-8,ceili(bridge.x)+15,-8):b.append(offset_point(x,plan,depot))
	var outward := Vector2(cos(depot.yaw-PI*.5),sin(depot.yaw-PI*.5))
	b.append(bridge.p+outward*(OFFSET+2))
	b.append(bridge.p-outward*(OFFSET+2))
	b.append(nearest(bridge.p-outward*70,paths,["r:procedural:159","r:procedural:48"]))
	b=rounded(b,8.0)
	var west := PackedVector2Array()
	for path in paths:
		if path.id!="r:untitled:66":continue
		var p: Vector2=path.points[0]
		west=PackedVector2Array([p,nearest(p,paths,["r:procedural:159","r:procedural:48"])])
	return {"a":a,"b":b,"west":west,"bridge":bridge.p,"turn":turn,"clearance":CLEARANCE}

static func apply(model: Dictionary, prepared: Dictionary = {}) -> void:
	if not model.tiles.has("tile_5_10"):return
	var depot := {}
	for d in model.get("depots",[]):
		if d.tile=="tile_5_10":depot=d;break
	if depot.is_empty():return
	var paths: Array=model.authored_region.paths.duplicate(true)
	var cache := preload("res://scripts/supply_chain_3d/bake_cache.gd")
	var lines := local_lines(model.lines)
	var key := cache.digest([cache.source_key("roads"),paths,depot,lines])
	var saved: Dictionary=prepared.get("depot_roads",{})
	var proposal: Dictionary=saved.get("proposal",{}) if saved.get("key","")==key else design(paths,depot,Rail.network(lines))
	prepared.depot_roads={"key":key,"proposal":proposal}
	if proposal.is_empty():return
	paths=paths.filter(func(p):return p.id!="r:untitled:65")
	for pair in [[A,proposal.a],[B,proposal.b],[WEST,proposal.west]]:
		if pair[1].size()<2:continue
		paths.append({"id":pair[0],"class":"minor","layer":0,"level":1,"widths":WIDTHS,"points":pair[1]})
	model.authored_region.paths=paths
	model.roads=Region.compile_segments(paths,model.authored_region.tiles)
	model.depot_roads=proposal
