extends RefCounted
## Six individual shed tracks (three pairs), with the outer pair branching
## into two dead-end loading sidings beside the building, served by one crane.
const Rail := preload("res://scripts/supply_chain_3d/railway.gd")
const Geo := preload("res://scripts/supply_chain_3d/geometry.gd")
const Index := preload("res://scripts/supply_chain_3d/road_index.gd")
const CITIES := {"Stoneshore":"tile_5_10","Arin":"tile_11_17","Capital Port":"tile_24_7","Vandel’s Skip":"tile_22_16","Port Lightning":"tile_14_2"}
const PAIR_CENTERS := [-15.0,0.0,15.0]
const SIDING_GAP := 3.0
const SIDING_CENTER := 26.75+SIDING_GAP+Rail.CORRIDOR_WIDTH*0.5
const CRANE_X := 125.0
static func world(rec: Dictionary,p: Vector2) -> Vector2: return rec.pos+p.rotated(rec.yaw)
static func polygon(rec: Dictionary) -> PackedVector2Array:
	var p := PackedVector2Array()
	for q in [Vector2(43,-27),Vector2(112,-27),Vector2(112,27),Vector2(43,27)]: p.append(world(rec,q))
	return p

static func place(tiles: Dictionary, anchors: Dictionary, obstacles: Array, water: Callable, height: Callable, traffic: Array = []) -> Array:
	var out: Array = []; var used := {}; var obstacle_index := {}
	for i in obstacles.size(): Index.insert(obstacle_index,obstacles[i].bb.grow(8),i)
	var traffic_index := Index.segments(traffic,12.0)
	for city in CITIES:
		var source: String = CITIES[city]
		if not tiles.has(source): continue
		var best := {}; var best_score := INF
		var rejected := {"traffic":0,"land":0,"building":0,"relief":0}
		# Search the city parcel itself. Use the depot's entire yard, including
		# approach tracks, to reject water and steep ground.
		for turn in 12:
			for ox in range(-150,151,30):
				for oy in range(-150,151,30):
					var tid := source
					var rec := {"city":city,"city_tile":source,"tile":tid,"pos":tiles[tid].center+Vector2(ox,oy),"yaw":turn*PI/6,"tracks":6,"siding_tracks":2}
					if occupied(rec,traffic,traffic_index): rejected.traffic+=1; continue
					var parcel := yard_polygon(rec)
					var bounds := Rect2(parcel[0],Vector2.ZERO)
					for point in parcel: bounds=bounds.expand(point)
					var protected := false
					for i in Index.query(obstacle_index,bounds):
						if bool(obstacles[i].get("protected",false)) and not Geometry2D.intersect_polygons(parcel,obstacles[i].poly).is_empty(): protected=true; break
					if protected: rejected.building+=1; continue
					var score: float = Vector2(ox,oy).length()*0.1
					var low := INF; var high := -INF; var valid := true
					for x in range(-140,146,28):
						for y in range(-42,57,14):
							var p := world(rec,Vector2(x,y))
							if not Index.contains(tiles[tid].center,p) or (water.is_valid() and water.call(p)): rejected.land+=1; valid=false; break
							var h := float(height.call(p)) if height.is_valid() else 0.0
							low=minf(low,h); high=maxf(high,h)
							for i in Index.query(obstacle_index,Rect2(p,Vector2.ZERO).grow(12)):
								if Geometry2D.is_point_in_polygon(p,obstacles[i].poly):
									if bool(obstacles[i].get("protected", false)): rejected.building+=1; valid=false; break
									score += 100.0
							if not valid: break
						if not valid: break
					if not valid: continue
					if high-low>8: rejected.relief+=1; continue
					score += (high-low)*60+world(rec,Vector2(-140,0)).distance_to(anchors[tid])*0.3
					if score<best_score: best=rec; best_score=score; best.height=(low+high)*0.5
		print("[depot-site] ",city," rejected=",rejected," site=",best)
		if not best.is_empty(): out.append(best); used[best.tile]=true
	return out

static func occupied(rec: Dictionary, traffic: Array, index: Dictionary) -> bool:
	# Reserve shed/office and the separate gantry footprint; leave the space
	# between them available instead of rejecting the whole yard rectangle.
	for rect in [Rect2(30,-56,95,96),Rect2(CRANE_X-9,SIDING_CENTER-15,18,30)]:
		var poly := PackedVector2Array()
		for p in [rect.position,rect.position+Vector2(rect.size.x,0),rect.end,rect.position+Vector2(0,rect.size.y)]: poly.append(world(rec,p))
		var area := Rect2(poly[0],Vector2.ZERO)
		for p in poly: area=area.expand(p)
		for id in Index.query(index,area):
			var segment: Dictionary = traffic[id]
			if Geometry2D.is_point_in_polygon(segment.a,poly) or Geometry2D.is_point_in_polygon(segment.b,poly): return true
			for i in poly.size():
				if Geometry2D.segment_intersects_segment(segment.a,segment.b,poly[i],poly[(i+1)%poly.size()])!=null: return true
	return false

static func connection(rec: Dictionary, anchor: Vector2, network: Array = []) -> Vector2:
	# Stoneshore's former anchor lies behind its outward-facing throat. Join
	# the northbound main line instead, with space for a broad curve.
	if str(rec.tile)!="tile_5_10": return anchor
	var target := anchor+Vector2(0,-300);var best := target;var distance := INF
	for line in network:
		if line.a!=rec.tile and line.b!=rec.tile: continue
		for point in line.pts:
			if point.p.distance_to(anchor)<150: continue
			var d: float=point.p.distance_to(target)
			if d<distance: best=point.p;distance=d
	return best

static func lines(rec: Dictionary, anchor: Vector2, network: Array = []) -> Array:
	var result: Array = []
	var throat := -280.0 if str(rec.tile)=="tile_5_10" else -140.0
	var routes: Array = [[connection(rec,anchor,network),world(rec,Vector2(throat,0)),world(rec,Vector2(-100,0)),world(rec,Vector2(103,0))]]
	for side in [-1,1]:
		routes.append([world(rec,Vector2(-100,0)),world(rec,Vector2(-55,15*side)),world(rec,Vector2(103,15*side))])
	# Two individual loading sidings terminate beside the rear of the shed.
	routes.append([world(rec,Vector2(-55,15)),world(rec,Vector2(0,SIDING_CENTER)),world(rec,Vector2(136,SIDING_CENTER))])
	for route in routes:
		var points: Array = []
		for p in route: points.append({"p":p,"tile":rec.tile,"edge":false})
		result.append({"mode":"rails","kind":"depot","a":rec.tile,"b":rec.tile,"level":2,"pts":points})
	return result

static func mesh(rec: Dictionary, origin: Vector2) -> ArrayMesh:
	var batch := Geo.Batch.new(); var h: float = rec.height
	var at := func(p: Vector3) -> Vector3:
		var q := world(rec,Vector2(p.x,p.z))
		return Vector3(q.x-origin.x,h+p.y,q.y-origin.y)
	var box := func(p: Vector3,size: Vector3,color: Color) -> void:
		# Build in local coordinates, then rotate vertices to preserve shed orientation.
		var part := Geo.Batch.new(); part.box(p,size,color)
		for i in part.vertices.size(): batch.vertices.append(at.call(part.vertices[i])); batch.normals.append(part.normals[i].rotated(Vector3.UP,-rec.yaw)); batch.colors.append(part.colors[i])
	var wall := Color("b9aa87"); var roof := Color("547b79"); var trim := Color("526166")
	box.call(Vector3(78,6.5,-26),Vector3(68,13,1.5),wall)
	box.call(Vector3(78,6.5,26),Vector3(68,13,1.5),wall)
	box.call(Vector3(111,6.5,0),Vector3(1.5,13,53),wall)
	# Six open bays: slender piers between the paired running tracks.
	var tracks: Array = []
	for center in PAIR_CENTERS:
		for side in [-1,1]: tracks.append(center+side*Rail.TRACK_SPACING*0.5)
	for z in [-25,-20,-10,-5,5,10,20,25]: box.call(Vector3(44,5,z),Vector3(1.6,10,1.0),wall)
	box.call(Vector3(44,11.5,0),Vector3(2,3,53),wall)
	for z in tracks:
		box.call(Vector3(43,10,z),Vector3(0.8,0.65,4.7),Color("d9b448"))
		box.call(Vector3(44.5,6,z),Vector3(0.2,7.5,4.1),Color("293c40"))
		# Recessed darkness above rail level leaves the track entrances open.
		for x in [60,83,103]:
			var corners: Array = []
			for d in [Vector2(-4.5,-1.6),Vector2(4.5,-1.6),Vector2(4.5,1.6),Vector2(-4.5,1.6)]:
				corners.append(at.call(Vector3(x+d.x,18.25-absf(z+d.y)*5/27,z+d.y)))
			batch.quad(corners[0],corners[1],corners[2],corners[3],Color("adc9bf"))
	for side in [-1,1]:
		var a: Vector3 = at.call(Vector3(41,13,27*side)); var b: Vector3 = at.call(Vector3(114,13,27*side))
		batch.quad(a,b,at.call(Vector3(114,18,0)),at.call(Vector3(41,18,0)),roof)
	for x in range(44,114,5):
		for side in [-1,1]: batch.tube(at.call(Vector3(x,13.2,27*side)),at.call(Vector3(x,18.2,0)),0.15,trim,4)
	box.call(Vector3(83,5,-34),Vector3(27,10,14),Color("c5b78f"))
	box.call(Vector3(83,10.4,-34),Vector3(30,1.0,16),roof)
	for x in [74,82,90]: box.call(Vector3(x,6,-41.2),Vector3(4.5,3.0,0.3),Color("517883"))
	# One travelling gantry crane straddles both siding ends. Its legs stay
	# outside the loading gauge; trolley, cable and hook meet at real joints.
	var yellow := Color("d7ae32"); var steel := Color("46585b")
	for z in [SIDING_CENTER-11,SIDING_CENTER+11]:
		box.call(Vector3(CRANE_X,1.2,z),Vector3(12,2.4,3.4),steel)
		for x in [CRANE_X-5,CRANE_X+5]:
			batch.tube(at.call(Vector3(x,2,z)),at.call(Vector3(CRANE_X,22,z)),0.7,yellow,4)
		batch.tube(at.call(Vector3(CRANE_X-5,3,z)),at.call(Vector3(CRANE_X+5,12,z)),0.35,steel,4)
	box.call(Vector3(CRANE_X,23,SIDING_CENTER),Vector3(3.5,2.4,26),yellow)
	box.call(Vector3(CRANE_X,24.8,SIDING_CENTER),Vector3(4.6,1.5,4.5),steel)
	box.call(Vector3(CRANE_X,22,SIDING_CENTER),Vector3(2.5,2,3),steel)
	for x in [CRANE_X-0.6,CRANE_X+0.6]: batch.tube(at.call(Vector3(x,21,SIDING_CENTER)),at.call(Vector3(x,12,SIDING_CENTER)),0.1,steel,4)
	box.call(Vector3(CRANE_X,11.5,SIDING_CENTER),Vector3(2,1.4,2.2),yellow)
	batch.tube(at.call(Vector3(CRANE_X,11,SIDING_CENTER)),at.call(Vector3(CRANE_X,9.8,SIDING_CENTER)),0.22,steel,5)
	batch.tube(at.call(Vector3(CRANE_X,9.8,SIDING_CENTER)),at.call(Vector3(CRANE_X+1,9.8,SIDING_CENTER)),0.22,steel,5)
	batch.tube(at.call(Vector3(CRANE_X+1,9.8,SIDING_CENTER)),at.call(Vector3(CRANE_X+1.4,10.6,SIDING_CENTER)),0.22,steel,5)
	return batch.mesh()

static func yard_polygon(rec: Dictionary) -> PackedVector2Array:
	var result := PackedVector2Array()
	for p in [Vector2(-145,-47),Vector2(145,-47),Vector2(145,57),Vector2(-145,57)]: result.append(world(rec,p))
	return result
