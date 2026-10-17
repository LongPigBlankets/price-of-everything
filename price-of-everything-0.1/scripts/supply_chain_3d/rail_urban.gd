extends RefCounted
## A busy road has multiple junctions within 80u. Urban rail within 20u of
## that road is covered; the preceding 45u is a recessed open approach.
const Index := preload("res://scripts/supply_chain_3d/road_index.gd")
const Rail := preload("res://scripts/supply_chain_3d/railway.gd")
const COVER := 20.0
const APPROACH := 45.0
const Elevation := preload("res://scripts/supply_chain_3d/rail_elevation.gd")
const DEPTH := Elevation.DEPTH
const FIELD_STEP := 3.0
var distance_field := {}
var centers := {}
var depots: Array = []
var tile_index := {}
var busy: Array = []
var buckets := {}
var solved := false
var components: Array = []
var tracks: Array = []
var track_buckets := {}

func configure(tiles: Dictionary, roads: Array, junctions: Array, plan: Dictionary, yards: Array = [], height: Callable = Callable(), level: Callable = Callable(), stations: Array = [], standing: Array = [], key_for: Callable = Callable(), river: Callable = Callable()) -> void:
	depots = yards
	solved=false; components.clear()
	centers.clear(); busy.clear(); buckets.clear(); tracks.clear(); track_buckets.clear(); distance_field.clear()
	for tid in tiles:
		if str(tiles[tid].type)=="urban": centers[tid]=tiles[tid].center
	tile_index=Index.tiles(centers)
	var junction_index := {}
	for i in junctions.size(): Index.insert(junction_index,Rect2(junctions[i],Vector2.ZERO).grow(80),i)
	for road in roads:
		var middle: Vector2 = (road.a+road.b)*0.5
		var nearby := 0
		for i in junction_index.get(Vector2i((middle/Index.CELL).floor()),[]):
			if middle.distance_to(junctions[i])<=80: nearby+=1
		if nearby<2: continue
		busy.append(road)
		Index.insert(buckets,Index.bounds(road.a,road.b,COVER+APPROACH+road.half),busy.size()-1)
	if height.is_valid() and level.is_valid():
		var clearance := preload("res://scripts/supply_chain_3d/rail_clearance.gd").new()
		clearance.configure(plan,roads,standing,tiles,depots,key_for)
		var result := Elevation.solve(plan,height,level,func(p): return distance(p)<=COVER,yard_distance,stations,clearance.covered,river)
		tracks=result.tracks; components=result.components; solved=true
		for i in tracks.size(): Index.insert(track_buckets,Index.bounds(tracks[i].a,tracks[i].b,Rail.CORRIDOR_WIDTH*0.5+14),i)
		return
	for corridor in plan.corridors:
		for i in range(1,corridor.points.size()):
			var a: Vector2 = corridor.points[i-1]; var b: Vector2 = corridor.points[i]
			if lowering((a+b)*0.5)<=0: continue
			tracks.append({"a":a,"b":b})
			Index.insert(track_buckets,Index.bounds(a,b,Rail.CORRIDOR_WIDTH*0.5+7),tracks.size()-1)

func distance(p: Vector2) -> float:
	if Index.tile_at(tile_index,centers,p)=="": return INF
	# Reuse a smooth distance field across track profiles and terrain vertices.
	# Three-unit cells match railway sampling; bilinear interpolation avoids
	# stair-stepped tunnel mouths and millions of repeated road scans.
	var cell := Vector2i((p/FIELD_STEP).floor())
	var t := p/FIELD_STEP-Vector2(cell)
	var result := lerpf(lerpf(field_node(cell),field_node(cell+Vector2i.RIGHT),t.x),
		lerpf(field_node(cell+Vector2i.DOWN),field_node(cell+Vector2i.ONE),t.x),t.y)
	# Working yards stay on the surface; underground city lines emerge before
	# entering the sidings, with a full approach outside the parcel.
	for depot in depots:
		var q: Vector2 = (p-depot.pos).rotated(-depot.yaw)
		var outside := maxf(maxf(-145-q.x,q.x-145),maxf(-47-q.y,q.y-57))
		result = maxf(result, COVER+APPROACH-maxf(0.0,outside))
	return result

func field_node(cell: Vector2i) -> float:
	if distance_field.has(cell): return distance_field[cell]
	var p := Vector2(cell)*FIELD_STEP
	var nearest := COVER+APPROACH+10.0
	for i in buckets.get(Vector2i((p/Index.CELL).floor()),[]):
		var rec: Dictionary = busy[i]
		nearest=minf(nearest,p.distance_to(Geometry2D.get_closest_point_to_segment(p,rec.a,rec.b))-rec.half)
	distance_field[cell]=nearest
	return nearest

func yard_distance(p: Vector2) -> float:
	var result := INF
	for depot in depots:
		var q: Vector2 = (p-depot.pos).rotated(-depot.yaw)
		result=minf(result,maxf(0.0,maxf(maxf(-145-q.x,q.x-145),maxf(-47-q.y,q.y-57))))
	return result

func nearest(p: Vector2) -> Dictionary:
	var result := {}; var best := INF
	for i in track_buckets.get(Vector2i((p/Index.CELL).floor()),[]):
		var rec: Dictionary=tracks[i]
		var q := Geometry2D.get_closest_point_to_segment(p,rec.a,rec.b)
		var gap := p.distance_squared_to(q)
		if gap>=best or gap>pow(Rail.CORRIDOR_WIDTH*0.5+14,2): continue
		best=gap
		var t := clampf((q-rec.a).dot(rec.b-rec.a)/maxf(.0001,rec.a.distance_squared_to(rec.b)),0,1)
		result={"h":lerpf(rec.ha,rec.hb,t),"base":lerpf(rec.base_a,rec.base_b,t),"active":rec.active,
			"hidden":rec.hidden_a if t<0.5 else rec.hidden_b,"q":q,"gap":sqrt(gap)}
	return result

## Absolute rail elevation and shared visibility. INF leaves ordinary surface
## rail/bridges with the existing crossing envelope.
func track_profile(p: Vector2) -> Vector3:
	var rec := nearest(p)
	if rec.is_empty() or not rec.active: return Vector3(INF,0,0)
	return Vector3(rec.h,1.0 if rec.hidden else 0.0,1.0)

func buried(p: Vector2) -> bool:
	if not solved: return distance(p)<=COVER
	var rec := nearest(p)
	return not rec.is_empty() and rec.hidden

func lowering(p: Vector2) -> float:
	if not solved: return DEPTH*(1.0-smoothstep(COVER,COVER+APPROACH,distance(p)))
	var rec := nearest(p)
	return maxf(0,rec.base-rec.h) if not rec.is_empty() else 0.0
func profile(p: Vector2) -> Vector2:
	if solved: return Vector2(lowering(p),1.0 if buried(p) else 0.0)
	var d := distance(p)
	return Vector2(DEPTH*(1.0-smoothstep(COVER,COVER+APPROACH,d)),1.0 if d<=COVER else 0.0)

func cut_height(p: Vector2, natural: float, height: Callable) -> float:
	if solved:
		var rec := nearest(p)
		if rec.is_empty() or not rec.active or rec.hidden: return natural
		var weight := 1.0-smoothstep(Rail.CORRIDOR_WIDTH*0.5+1,Rail.CORRIDOR_WIDTH*0.5+14,rec.gap)
		return minf(natural,lerpf(natural,float(rec.h)-1.4,weight))
	# Leave the roof intact over buried rail; open only the ramp before its mouth.
	if buried(p): return natural
	var result := natural
	for i in track_buckets.get(Vector2i((p/Index.CELL).floor()),[]):
		var rec: Dictionary = tracks[i]
		var q := Geometry2D.get_closest_point_to_segment(p,rec.a,rec.b)
		if buried(q): continue
		var depth := lowering(q)
		if depth<=0: continue
		var gap := p.distance_to(q)
		var weight := 1.0-smoothstep(Rail.CORRIDOR_WIDTH*0.5+1,Rail.CORRIDOR_WIDTH*0.5+7,gap)
		result=minf(result,lerpf(natural,float(height.call(q))-depth-0.2,weight))
	return result
