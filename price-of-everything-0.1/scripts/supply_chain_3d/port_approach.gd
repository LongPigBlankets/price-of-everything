extends RefCounted
## Match Stoneshore's approach to the actual road in the harbour mesh. A small
## along-shore adjustment lets the quay move inland while keeping berths afloat.
const Harbour := preload("res://scripts/supply_chain_3d/harbour.gd")
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const Region := preload("res://scripts/supply_chain_3d/authored_region.gd")
const Curves := preload("res://scripts/supply_chain_3d/street_curves.gd")
const Cache := preload("res://scripts/supply_chain_3d/bake_cache.gd")
const SOURCE := "port:stoneshore:approach"

static func design(s: Dictionary, paths: Array, height: Callable) -> Dictionary:
	var frame := Harbour.frame(s,height,Vector2.ZERO)
	var asset := Assets.harbour_for(frame.harbour_asset)
	var original: Transform3D=frame.harbour_transform
	var offshore: Vector2=s.harbour.offshore;var across := offshore.orthogonal()
	var pose := original;var delta := Vector2.ZERO;var score := -INF
	for inland in range(24,41,2):
		for lateral in range(-32,33,2):
			var value := inland-absf(lateral)*.3
			if value<=score:continue
			var shift := -offshore*inland+across*lateral
			var candidate := original;candidate.origin+=Vector3(shift.x,0,shift.y)
			if not Harbour.ships_afloat(asset,candidate,s.pos,height):continue
			pose=candidate;delta=shift;score=value
	if score==-INF:
		push_error("No afloat inland Stoneshore port pose found")
		return {}
	frame.harbour_transform=pose
	frame.harbour_shore_shift+=-delta.dot(offshore)
	for field in ["pier_tip","basin"]:frame["harbour_"+field]=pose*Harbour.vector3(asset[field])
	var low := Harbour.vector3(asset.bounds_min)
	var bounds := pose*AABB(low,Harbour.vector3(asset.bounds_max)-low)
	frame.dimension=Vector3(maxf(absf(bounds.position.x),absf(bounds.end.x))*2,bounds.end.y,maxf(absf(bounds.position.z),absf(bounds.end.z))*2)
	var entry3: Vector3=pose*Harbour.vector3(asset.road_entry)
	var entry: Vector2=s.pos+Vector2(entry3.x,entry3.z)
	var corner := entry;var start := entry;var distance := INF
	# Project a real approach point onto the asset's road axis. The connecting
	# legs are perpendicular; a fixed-length leg can miss the authored road.
	for path in paths:
		if str(path.id) not in ["r:untitled:66","r:untitled:67"]:continue
		for i in range(1,path.points.size()):
			var steps := maxi(1,ceili(path.points[i-1].distance_to(path.points[i])/3.0))
			for step in steps+1:
				var q: Vector2=path.points[i-1].lerp(path.points[i],float(step)/steps)
				var along := (entry-q).dot(offshore)
				var side := absf((entry-q).dot(across))
				if along<18 or side<12:continue
				if along+side<distance:distance=along+side;start=q;corner=entry-offshore*along
	if distance==INF:return {}
	var points := Curves.rounded_path(PackedVector2Array([start,corner,entry]),10.0)
	var layout: Dictionary=s.harbour.duplicate(true)
	layout.trial_frame=frame;layout.shore_anchor+=delta
	# Reserve the three rendered quay slabs, not the old authored envelope.
	var x0: float=asset.shore_edge[0][0];var x1: float=asset.bounds_max[0]
	var z0: float=asset.shore_edge[-1][2];var z1: float=asset.shore_edge[0][2]
	var arm: float=asset.anchor[0]-x0
	layout.quays=[]
	for rect in [Rect2(x0,z0,arm,z1-z0),Rect2(x0,z0,x1-x0,arm),Rect2(x0,z1-arm,x1-x0,arm)]:
		var poly := PackedVector2Array()
		for p in [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]:
			var q: Vector3=pose*Vector3(p.x,asset.deck,p.y);poly.append(s.pos+Vector2(q.x,q.z))
		layout.quays.append(poly)
	layout.main_quay=layout.quays[0]
	var box := Rect2(layout.quays[0][0],Vector2.ZERO)
	for poly in layout.quays:
		for p in poly:box=box.expand(p)
	layout.bounds=box;layout.road_connection=entry
	var half: float=asset.road_width*pose.basis.x.length()*.5
	return {"layout":layout,"points":points,"widths":[half+.6,half+.4,half+.15,half],"entry":entry,"shift":delta,"inland":-delta.dot(offshore),"lateral":delta.dot(across),"deck":entry3.y,"start_height":float(height.call(start)),"afloat":true}

static func apply(model: Dictionary, height: Callable, prepared: Dictionary) -> void:
	if not preload("res://scripts/supply_chain_3d/stoneshore_trial.gd").preview_enabled():return
	for s in model.standing:
		if str(s.tile)!="tile_5_10" or not s.has("harbour"):continue
		var key := Cache.digest([Cache.source_key("roads"),Cache.source_key("terrain"),s.harbour,Assets.harbour_for(Assets.key_for("port",1)),model.authored_region.paths])
		var saved: Dictionary=prepared.get("port_approach",{})
		var plan: Dictionary=saved.plan if saved.get("key","")==key else design(s,model.authored_region.paths,height)
		prepared.port_approach={"key":key,"plan":plan}
		if plan.is_empty():return
		s.harbour=plan.layout.duplicate(true);s.entrance=plan.entry
		model.port_approach=plan
		model.authored_region.paths.append({"id":SOURCE,"class":"minor","layer":0,"level":1,"widths":plan.widths,"points":plan.points})
		model.roads=Region.compile_segments(model.authored_region.paths,model.authored_region.tiles)

static func grade(roads: Array, plan: Dictionary) -> void:
	if plan.is_empty():return
	var points: PackedVector2Array=plan.points;var lengths := PackedFloat32Array([0.0])
	for i in range(1,points.size()):lengths.append(lengths[-1]+points[i-1].distance_to(points[i]))
	for road in roads:
		if road.source!=SOURCE:continue
		for pair in [["a","road_ha"],["b","road_hb"]]:
			var p: Vector2=road[pair[0]];var distance := INF;var along := 0.0
			for i in range(1,points.size()):
				var q := Geometry2D.get_closest_point_to_segment(p,points[i-1],points[i])
				if q.distance_to(p)<distance:distance=q.distance_to(p);along=lengths[i-1]+points[i-1].distance_to(q)
			# Surface asphalt sits 0.85 + 3*0.08 above its earthwork datum.
			road[pair[1]]=lerpf(plan.start_height,plan.deck-1.09,clampf(along/lengths[-1],0,1))
