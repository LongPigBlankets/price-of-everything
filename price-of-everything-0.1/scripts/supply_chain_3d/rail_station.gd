extends RefCounted
## Stoneshore presentation station: street-level entrance above recessed platforms.
const Rail := preload("res://scripts/supply_chain_3d/railway.gd")
const Geo := preload("res://scripts/supply_chain_3d/geometry.gd")
const Region := preload("res://scripts/supply_chain_3d/authored_region.gd")
const Index := preload("res://scripts/supply_chain_3d/road_index.gd")
const TILE := "tile_4_10"
const ID := "station:stoneshore_old_quarter"

static func local_point(s: Dictionary, p: Vector2) -> Vector2:
	return s.pos+s.dir*p.x+s.normal*p.y

static func polygon(s: Dictionary, rect := Rect2(-8,-38,78,55)) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in [rect.position,rect.position+Vector2(rect.size.x,0),rect.end,rect.position+Vector2(0,rect.size.y)]: out.append(local_point(s,p))
	return out

static func apply(model: Dictionary, height: Callable) -> void:
	model.stations=[]
	if not model.tiles.has(TILE) or "--stoneshore-baseline" in OS.get_cmdline_user_args(): return
	var plan := Rail.network(model.lines)
	var centers: Dictionary={TILE:model.tiles[TILE].center}
	var candidates: Array=[]
	for buffer in plan.buffers:
		if Index.contains(centers[TILE],buffer.p): candidates.append(buffer)
	if candidates.size()<2: return
	# Paired buffers describe the same terminal; average them to find its axis.
	var end: Dictionary=candidates[0]
	var pair := candidates.filter(func(b): return b.p.distance_to(end.p)<Rail.CORRIDOR_WIDTH+1 and b.dir.dot(end.dir)>.99)
	var p := Vector2.ZERO
	for b in pair: p+=b.p
	p/=float(pair.size())
	var best := {};var cost := INF
	for sign_v in [-1.0,1.0]:
		var normal: Vector2 = Vector2(-end.dir.y,end.dir.x)*sign_v
		var s := {"id":ID,"tile":TILE,"pos":p,"dir":end.dir,"normal":normal,"height":float(height.call(p)),"track_length":80.0}
		var entry := local_point(s,Vector2(24,-36))
		for road in model.roads:
			if int(road.level)!=1 or str(road.get("source","")).begins_with("access:"): continue
			var q := Geometry2D.get_closest_point_to_segment(entry,road.a,road.b)
			var d := entry.distance_to(q)
			if d>=cost or d>110 or (q-p).dot(normal)>0: continue
			cost=d;best=s.duplicate();best.entrance=entry;best.road_join=q;best.road_source=road.get("source","")
	if best.is_empty(): return
	best.height=float(height.call(best.entrance))
	model.stations=[best]
	var path := {"id":ID+":road","class":"minor","layer":0,"level":1,"widths":[2.4,2.2,2.0,1.8],
		"points":PackedVector2Array([best.entrance,best.road_join])}
	# Compile and split the complete network so the small road has a real T join.
	model.authored_region.paths.append(path)
	model.roads=Region.compile_segments(model.authored_region.paths,model.authored_region.tiles)

static func contains_track(s: Dictionary, p: Vector2) -> bool:
	var q: Vector2=p-s.pos
	return q.dot(s.dir)>=-1 and q.dot(s.dir)<=s.track_length and absf(q.dot(s.normal))<7

static func cut_height(s: Dictionary, p: Vector2, natural: float, datum: float) -> float:
	var q: Vector2=p-s.pos
	var x := q.dot(s.dir);var y := absf(q.dot(s.normal))
	var weight := (1.0-smoothstep(14,20,y))*(1.0-smoothstep(62,70,x))*(1.0-smoothstep(0,7,-x))
	return minf(natural,lerpf(natural,datum-1.4,weight))

static func mesh(s: Dictionary, origin: Vector2, datum: float) -> ArrayMesh:
	var batch := Geo.Batch.new()
	var at := func(p: Vector3) -> Vector3:
		var q := local_point(s,Vector2(p.x,p.z))
		return Vector3(q.x-origin.x,p.y,q.y-origin.y)
	var box := func(p: Vector3,size: Vector3,color: Color) -> void:
		var part := Geo.Batch.new();part.box(p,size,color)
		for i in part.vertices.size():
			# Reflecting the entrance to the other side also flips triangle winding.
			var j := i
			if s.dir.cross(s.normal)<0: j=i-i%3+([0,2,1][i%3])
			var v: Vector3=part.vertices[j];batch.vertices.append(at.call(v))
			var n: Vector3=part.normals[j];batch.normals.append(Vector3(s.dir.x*n.x+s.normal.x*n.z,n.y,s.dir.y*n.x+s.normal.y*n.z))
			batch.colors.append(part.colors[j])
	var platform := datum+1.25;var street: float=s.height;var wall := Color("b7a287");var roof := Color("626f7b");var trim := Color("647078")
	# Two platforms, restrained canopies and a street-level brick ticket hall.
	for sign_v in [-1.0,1.0]:
		box.call(Vector3(32,platform-.9,9.3*sign_v),Vector3(60,1.8,7.0),Color("b7b6a7"))
		box.call(Vector3(32,platform+.04,6.0*sign_v),Vector3(60,.08,.55),Color("ded6ad"))
		box.call(Vector3(34,platform+7.2,9.6*sign_v),Vector3(42,.7,7.2),roof)
		for x in [16,28,40,52]:box.call(Vector3(x,platform+3.5,11.2*sign_v),Vector3(.5,7,.5),trim)
		for x in [24,43]:
			box.call(Vector3(x,platform+1.2,10.2*sign_v),Vector3(5,.6,1.3),Color("927c60"))
			box.call(Vector3(x,platform+1.9,10.8*sign_v),Vector3(5,1.2,.3),Color("927c60"))
	box.call(Vector3(28,(datum-1.4+street)*.5,-26),Vector3(34,maxf(.5,street-datum+1.4),17),Color("9b9b8c"))
	box.call(Vector3(28,street+6,-26),Vector3(32,12,15),wall)
	box.call(Vector3(28,street+12.4,-26),Vector3(35,.8,18),roof)
	for x in [10.6,45.4]:box.call(Vector3(x,street+12.8,-26),Vector3(.35,.3,18),trim)
	for z in [-34.8,-17.2]:box.call(Vector3(28,street+12.8,z),Vector3(35,.3,.35),trim)
	for x in [16,22,34,40]:
		box.call(Vector3(x,street+6.8,-33.6),Vector3(3.9,4.8,.2),Color("567482"))
		box.call(Vector3(x,street+6.8,-18.4),Vector3(3.9,4.8,.2),Color("567482"))
	box.call(Vector3(28,street+3.4,-33.8),Vector3(5.5,6.8,.35),Color("435961"))
	box.call(Vector3(28,street+7.5,-35),Vector3(8,.6,3),roof)
	box.call(Vector3(28,street+13.8,-26),Vector3(8,2.2,8),wall)
	box.call(Vector3(28,street+15.2,-26),Vector3(9,.7,9),roof)
	# A pale clock face on the entrance tower reads even at medium zoom.
	box.call(Vector3(28,street+13.8,-30.1),Vector3(2.0,1.8,.12),Color("e4daba"))
	box.call(Vector3(28,street+14.1,-30.2),Vector3(.13,.8,.13),trim)
	box.call(Vector3(28.3,street+13.8,-30.2),Vector3(.7,.13,.13),trim)
	box.call(Vector3(24,street+.1,-36),Vector3(38,.2,5),Color("b9b5a7"))
	# Access stairs reach the recessed platform; no road plunges down the cutting.
	for i in 16:
		var t := float(i+1)/16;var top := lerpf(street,platform,t)
		box.call(Vector3(5+i*1.5,(datum-1.4+top)*.5,-14.2),Vector3(1.5,maxf(.2,top-datum+1.4),3.5),Color("b7b6a7"))
	box.call(Vector3(7,street-.3,-20),Vector3(6,.6,13),Color("b7b6a7"))
	# Retaining walls keep the platform cut crisp; rear access reaches both sides
	# behind the buffers without an at-grade pedestrian crossing of live tracks.
	for sign_v in [-1.0,1.0]:
		box.call(Vector3(31,(platform+street)*.5,15.5*sign_v),Vector3(62,street-platform,.8),Color("a7a79a"))
		box.call(Vector3(31,street+.15,15.5*sign_v),Vector3(63,.4,1.1),Color("c1bdab"))
	box.call(Vector3(-5,street-.2,0),Vector3(4,.6,33),Color("b7b6a7"))
	for i in 16:
		var top := lerpf(street,platform,float(i+1)/16)
		box.call(Vector3(-2+i*1.5,(datum-1.4+top)*.5,13.2),Vector3(1.5,maxf(.2,top-datum+1.4),3.5),Color("b7b6a7"))
	return batch.mesh()
