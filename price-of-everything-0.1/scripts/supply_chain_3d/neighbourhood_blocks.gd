extends RefCounted
## Offline, Stoneshore-only block interiors. The normal frontage bake owns this
## plan, so opening a cached view never repeats street/parcel searches.
const Trial := preload("res://scripts/supply_chain_3d/stoneshore_trial.gd")
const Index := preload("res://scripts/supply_chain_3d/road_index.gd")
const Region := preload("res://scripts/supply_chain_3d/authored_region.gd")
const Walks := preload("res://scripts/supply_chain_3d/urban_sidewalks.gd")
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const Scale := preload("res://scripts/supply_chain_3d/building_scale.gd")
const WIDTHS := [2.8,2.6,2.4,2.2] # quiet two-way lanes, narrower than district streets
var added: Array = []
var fit: RefCounted
var world: Dictionary
var main_roads: Array = []
var main_index := {}
var plan := {"paths":[],"footpaths":[],"brownfields":[],"greens":0,"courtyards":0,"rows":{},"buildings":0}

static func lane(road: Dictionary) -> bool:
	return str(road.get("source","")).begins_with("neighbourhood:")

static func rectangle(p: Vector2, tangent: Vector2, size: Vector2) -> PackedVector2Array:
	var n := tangent.orthogonal()
	return PackedVector2Array([p-tangent*size.x*.5-n*size.y*.5,p+tangent*size.x*.5-n*size.y*.5,
		p+tangent*size.x*.5+n*size.y*.5,p-tangent*size.x*.5+n*size.y*.5])

func prepare(model: Dictionary, fitter: RefCounted) -> void:
	world=model;fit=fitter
	main_roads=fit.roads.filter(func(r):return str(r.tile) in Trial.TILES and not r.get("district_street",false) and not str(r.get("source","")).begins_with("access:"))
	main_index=Index.segments(main_roads,150)
	_lanes()
	_connections()
	_brownfields()
	_courtyards()
	world.neighbourhood=plan

func _lane_clear(points: PackedVector2Array, tile: String) -> bool:
	var low := INF;var high := -INF
	for i in range(1,points.size()):
		var a := points[i-1];var b := points[i]
		if not fit.clear_lots(a,b,WIDTHS[0]+Walks.WIDTH+1.0,""): return false
		var n := (b-a).normalized().orthogonal()*(WIDTHS[0]+Walks.WIDTH+.5)
		var steps := maxi(1,ceili(a.distance_to(b)/4.0))
		var previous: float=fit.ground.call(a)
		for j in range(steps+1):
			var p := a.lerp(b,float(j)/steps)
			var current: float=fit.ground.call(p)
			if j>0 and absf(current-previous)>a.distance_to(b)/steps*.08+.01: return false
			previous=current
			for q in [p,p+n,p-n]:
				if not Index.contains(world.tiles[tile].center,q) or fit.wet(q): return false
				var h: float=fit.ground.call(q);low=minf(low,h);high=maxf(high,h)
			if high-low>6.0: return false
			for ri in fit.road_index.get(Vector2i((p/Index.CELL).floor()),[]):
				var r: Dictionary=fit.roads[ri]
				var distance := p.distance_to(Geometry2D.get_closest_point_to_segment(p,r.a,r.b))
				var reach: float=float(r.widths[0])+Walks.width(r)+WIDTHS[0]+2.0
				# Only the two mouths may intersect an existing road. All three
				# new edges must otherwise stay clear of its carriageway.
				if distance<reach and minf(p.distance_to(points[0]),p.distance_to(points[-1]))>reach+2.0: return false
	return true

func _lanes() -> void:
	var counts := {};var centers: Array=[]
	var candidates := main_roads.duplicate()
	candidates.sort_custom(func(a,b):return a.a.distance_squared_to(a.b)>b.a.distance_squared_to(b.b))
	for r in candidates:
		var tid := str(r.tile)
		var urban: bool=world.tiles[tid].type=="urban"
		if int(counts.get(tid,0)) >= (3 if urban else 1): continue
		var length: float=r.a.distance_to(r.b)
		if length<85: continue
		var tangent: Vector2=(r.b-r.a).normalized();var n := tangent.orthogonal()
		var accepted := false
		for fraction in [.5,.28,.72]:
			if accepted: break
			var mid: Vector2=r.a.lerp(r.b,fraction)
			var run := minf(130.0,length*minf(fraction,1.0-fraction)*2.0-12.0)
			if run<74: continue
			for depth in [92.0,62.0]:
				if accepted: break
				for sign_v in [-1.0,1.0]:
					var c: Vector2=mid+n*depth*sign_v
					if centers.any(func(other):return other.distance_to(c)<135.0): continue
					var a := mid-tangent*run*.5;var b := mid+tangent*run*.5
					var points := preload("res://scripts/supply_chain_3d/street_curves.gd").rounded_path(PackedVector2Array([a,a+n*depth*sign_v,b+n*depth*sign_v,b]),18.0)
					if not _lane_clear(points,tid): continue
					var path := {"id":"neighbourhood:%s:%d" % [tid,int(counts.get(tid,0))],"points":points,
						"class":"minor","layer":0,"level":1,"widths":WIDTHS,"district_street":true}
					plan.paths.append(path);centers.append(c);counts[tid]=int(counts.get(tid,0))+1
					world.authored_region.paths.append(path)
					fit.roads=Index.split(fit.roads+Region.compile_segments([path],{tid:world.tiles[tid].center}))
					Walks.apply(fit.roads,world.tiles)
					fit.road_index=Index.segments(fit.roads,20)
					accepted=true;break
	world.roads=fit.roads

func _connections() -> void:
	# Road-to-road cuts open wedge-shaped blocks where a rectangular loop will
	# not fit. Both ends are real graph junctions; no isolated decorative stubs.
	var anchors: Array=[]
	for r in fit.roads:
		if not str(r.tile) in Trial.TILES or str(r.get("source","")).begins_with("access:"): continue
		var count := maxi(1,ceili(r.a.distance_to(r.b)/48.0))
		for i in count:
			anchors.append({"p":r.a.lerp(r.b,(i+.5)/count),"road":r})
	var options: Array=[]
	for i in anchors.size():
		var a: Dictionary=anchors[i]
		for j in range(i+1,anchors.size()):
			var b: Dictionary=anchors[j]
			if a.road.tile!=b.road.tile or a.road.source==b.road.source: continue
			var distance: float=a.p.distance_to(b.p)
			if distance<80 or distance>280: continue
			var tangent: Vector2=(b.p-a.p).normalized()
			if absf(tangent.dot((a.road.b-a.road.a).normalized()))>.82 or absf(tangent.dot((b.road.b-b.road.a).normalized()))>.82: continue
			options.append({"a":a.p,"b":b.p,"tile":a.road.tile,"length":distance})
	options.sort_custom(func(a,b):return a.length>b.length)
	var counts := {}
	for option in options:
		var tid: String=option.tile
		if int(counts.get(tid,0)) >= (5 if world.tiles[tid].type=="urban" else 2): continue
		var points := PackedVector2Array([option.a,option.b])
		if not _lane_clear(points,tid): continue
		var path := {"id":"neighbourhood:%s:cut%d" % [tid,int(counts.get(tid,0))],"points":points,
			"class":"minor","layer":0,"level":1,"widths":WIDTHS,"district_street":true}
		plan.paths.append(path);counts[tid]=int(counts.get(tid,0))+1
		world.authored_region.paths.append(path)
		fit.roads=Index.split(fit.roads+Region.compile_segments([path],{tid:world.tiles[tid].center}))
		Walks.apply(fit.roads,world.tiles);fit.road_index=Index.segments(fit.roads,20)
	world.roads=fit.roads

func _brownfields() -> void:
	var counts := {}
	# Prefer useful street-facing sites, not scraps left after building packing.
	var candidates: Array=fit.roads.duplicate()
	candidates.sort_custom(func(a,b):
		if lane(a)!=lane(b): return lane(a)
		return a.a.distance_squared_to(a.b)>b.a.distance_squared_to(b.b))
	for road in candidates:
		var tid := str(road.tile)
		if not tid in Trial.TILES or str(road.get("source","")).begins_with("access:"): continue
		if int(counts.get(tid,0)) >= (2 if world.tiles[tid].type=="urban" else 1): continue
		if road.a.distance_to(road.b)<56: continue
		var tangent: Vector2=(road.b-road.a).normalized()
		var accepted := false
		for t in [.5,.25,.75]:
			if accepted: break
			for sign_v in [-1.0,1.0]:
				var n: Vector2=tangent.orthogonal()*sign_v
				var size := Vector2(52,40)
				var p: Vector2=road.a.lerp(road.b,t)+n*(float(road.widths[0])+Walks.width(road)+size.y*.5+1)
				if plan.brownfields.any(func(other):return other.pos.distance_to(p)<165): continue
				var poly := rectangle(p,tangent,size)
				var id := "brownfield:%s:%d" % [tid,int(counts.get(tid,0))]
				if not fit.clear_plot(poly,world.tiles[tid].center,id,1.8,.5): continue
				if not _parcel_dry(p,tangent,size): continue
				var entry: Vector2=p-n*size.y*.5
				plan.brownfields.append({"id":id,"tile":tid,"pos":p,"polygon":poly,"tangent":tangent,"normal":n,
					"size":size,"entrance":entry,"road_join":road.a.lerp(road.b,t)})
				fit.reserve(id,poly);counts[tid]=int(counts.get(tid,0))+1;accepted=true;break

func _parcel_dry(p: Vector2, tangent: Vector2, size: Vector2) -> bool:
	var low := INF;var high := -INF
	for y in range(0,ceili(size.y)+1,4):
		for x in range(0,ceili(size.x)+1,4):
			var q := p+tangent*(x-size.x*.5)+tangent.orthogonal()*(y-size.y*.5)
			if fit.wet(q): return false
			var h: float=fit.ground.call(q);low=minf(low,h);high=maxf(high,h)
	return high-low<=1.8

func _greens() -> void:
	for tid in Trial.TILES:
		if not world.tiles.has(tid): continue
		var choices: Array=[]
		for y in range(-190,191,38):
			for x in range(-190,191,38):
				var p: Vector2=world.tiles[tid].center+Vector2(x,y)
				choices.append({"p":p,"seed":absi(hash("green:"+str(p)))})
		choices.sort_custom(func(a,b):return a.seed<b.seed)
		var count := 0;var placed: Array=[]
		for choice in choices:
			if count>=(3 if world.tiles[tid].type=="urban" else 2): break
			var options: Array=fit.candidates(choice.p,110)
			if options.is_empty() or float(options[0].distance)<30*30: continue
			if placed.any(func(p):return p.distance_to(choice.p)<86): continue
			var family := "civic_park" if count==1 and world.tiles[tid].type=="urban" else "civic_grove"
			var s := {"iid":"z_block_green:%s:%d" % [tid,count],"kind":"house","tile":tid,"pos":choice.p,
				"side":38.0 if family=="civic_grove" else 32.0,"level":1,"decor_family":family,"sprite":null,"polluting":false,
				"name":"Neighbourhood grove" if family=="civic_grove" else "Neighbourhood park","trial_green":true,"max_relief":1.8}
			if not fit.clear_building(s,world.tiles[tid].center): continue
			_accept(s);placed.append(s.pos);plan.greens+=1;count+=1

func _main_distance(p: Vector2) -> float:
	var d := INF
	for id in main_index.get(Vector2i((p/Index.CELL).floor()),[]):
		var r: Dictionary=main_roads[id]
		d=minf(d,p.distance_to(Geometry2D.get_closest_point_to_segment(p,r.a,r.b))-float(r.widths[0]))
	return d

func _near_port(p: Vector2) -> bool:
	for s in world.standing:
		if s.has("harbour") and p.distance_to(s.harbour.shore_anchor)<240: return true
	return false

func _courtyards() -> void:
	var counts := {}
	for r in fit.roads:
		if not lane(r) and not r.get("district_street",false): continue
		if not str(r.tile) in Trial.TILES or int(counts.get(r.tile,0))>=2 or r.a.distance_to(r.b)<40: continue
		var tangent: Vector2=(r.b-r.a).normalized()
		for t in [.5,.25,.75]:
			if int(counts.get(r.tile,0))>=2: break
			for sign_v in [-1.0,1.0]:
				var point: Vector2=r.a.lerp(r.b,t)
				var id := "z_court:%s:%d" % [r.tile,int(counts.get(r.tile,0))]
				var side := Scale.TERRACE_ROW_SIDE * Trial.DECOR_SCALE
				var a := {"iid":id+":front","kind":"house","tile":r.tile,"pos":point,"side":side,"level":1,
					"decor_asset":"house_lvl1","decor_scale":Trial.DECOR_SCALE,"trial_density":true,"neighbourhood_row":2,
					"sprite":null,"polluting":false,"max_relief":2.0,"name":"Courtyard homes"}
				fit.street_pose(a,r,point,sign_v)
				var n: Vector2=tangent.orthogonal()*sign_v
				if _near_port(a.pos): continue
				var depth := Assets.dimensions("house_lvl1").z*side
				var b := a.duplicate(true);b.iid=id+":return"
				b.pos=a.pos+tangent*(-side*.5+depth*.5)+n*(side*.5+depth*.5+.6);b.yaw=float(a.yaw)+PI*.5
				var green := {"iid":id+":garden","kind":"house","tile":r.tile,"pos":a.pos+tangent*7+n*24,
					"side":19.0,"level":1,"decor_family":"civic_park","yaw":a.yaw,"sprite":null,"polluting":false,
					"trial_green":true,"max_relief":2.0,"name":"Shared courtyard garden"}
				if not fit.clear_building(a,world.tiles[r.tile].center) or not fit.clear_building(b,world.tiles[r.tile].center) or not fit.clear_building(green,world.tiles[r.tile].center): continue
				_accept(a);_accept(b);_accept(green)
				counts[r.tile]=int(counts.get(r.tile,0))+1;plan.courtyards+=1;plan.buildings+=2;plan.greens+=1
				plan.rows["2"]=int(plan.rows.get("2",0))+2
				break

static func row_for(distance: float) -> int:
	return 1 if distance<38 else (2 if distance<80 else 3)

func populate() -> void:
	_greens()
	# Two additional layers face the new lanes. Beyond the main-road frontage,
	# remove commerce and leave progressively wider gaps for gardens/greenery.
	for r in fit.roads:
		if not lane(r): continue
		var length: float=r.a.distance_to(r.b)
		var count := maxi(1,floori(length/19.0))
		for i in count:
			var point: Vector2=r.a.lerp(r.b,(i+.5)/count)
			for sign_v in [-1.0,1.0]:
				var row := row_for(_main_distance(point))
				var seed := absi(hash(str(point)+str(sign_v)))
				if row==3 and seed%3==0: continue
				var choices := ["house_lvl1","civic_semi_lvl1"] if row>=2 else ["civic_commercial_lvl1","house_lvl3","house_lvl1"]
				if row==3: choices.reverse()
				for key in choices:
					var side := Scale.TERRACE_ROW_SIDE*Trial.DECOR_SCALE
					if key=="civic_semi_lvl1": side=Scale.semi_side()*Trial.DECOR_SCALE
					elif key.begins_with("civic_"): side=12.0/Assets.storey_height(key)*Trial.DECOR_SCALE
					var s := {"iid":"z_block:%s:%d" % [r.tile,plan.buildings],"kind":"house","tile":r.tile,"pos":point,
						"side":side,"pad":side,"level":1,"decor_asset":key,"decor_scale":Trial.DECOR_SCALE,
						"trial_density":true,"neighbourhood_row":row,"sprite":null,"polluting":false,"max_relief":3.0,
						"name":"Backstreet homes" if row>=2 else "Apartments and shops"}
					if key.begins_with("civic_"): s.decor_family=key.get_slice("_lvl",0)
					fit.street_pose(s,r,point,sign_v)
					if not fit.clear_building(s,world.tiles[r.tile].center): continue
					# Respect the existing residential exclusion around industrial docks.
					if _near_port(s.pos) and (row>=2 or key in ["house_lvl1","civic_semi_lvl1"]): continue
					_accept(s);plan.buildings+=1
					plan.rows[str(row)]=int(plan.rows.get(str(row),0))+1
					break
	_back_rows()
	world.neighbourhood=plan
	fit=null;world={}

func _back_rows() -> void:
	# Walkable secondary rows can share a lane without lining every rear facade
	# with asphalt. Each accepted door has a clear, reserved pedestrian connection.
	var counts := {};var used := {}
	for depth in [32.0,62.0]:
		for r in fit.roads:
			if not str(r.tile) in Trial.TILES or str(r.get("source","")).begins_with("access:"): continue
			if int(counts.get(r.tile,0))>=24: continue
			var length: float=r.a.distance_to(r.b)
			var count := maxi(1,floori(length/24.0))
			for i in count:
				var point: Vector2=r.a.lerp(r.b,(i+.5)/count)
				for sign_v in [-1.0,1.0]:
					var key := "house_lvl1" if depth<40 else "civic_semi_lvl1"
					var side := (Scale.TERRACE_ROW_SIDE if key=="house_lvl1" else Scale.semi_side())*Trial.DECOR_SCALE
					var s := {"iid":"z_back:%s:%d" % [r.tile,plan.buildings],"kind":"house","tile":r.tile,"pos":point,
						"side":side,"pad":side,"level":1,"decor_asset":key,"decor_scale":Trial.DECOR_SCALE,
						"trial_density":true,"sprite":null,"polluting":false,"max_relief":3.0,"name":"Garden-row homes"}
					if key.begins_with("civic_"): s.decor_family="civic_semi"
					fit.street_pose(s,r,point,sign_v)
					s.pos+=(r.b-r.a).normalized().orthogonal()*sign_v*depth
					var cell := Vector2i((s.pos/12.0).round())
					if used.has(cell): continue
					used[cell]=true
					var row := row_for(_main_distance(s.pos))
					if row<2 or row>3 or _main_distance(s.pos)>135 or _near_port(s.pos): continue
					if row==3 and absi(hash(str(cell)))%3==0: continue
					s.neighbourhood_row=row
					if not fit.clear_building(s,world.tiles[r.tile].center): continue
					var connection: PackedVector2Array=fit.entrance(s)
					if connection.is_empty() or connection[0].distance_to(connection[1])>85: continue
					# Keep garden paths off cleared expansion parcels and other homes.
					_accept(s);plan.buildings+=1;counts[r.tile]=int(counts.get(r.tile,0))+1
					plan.rows[str(row)]=int(plan.rows.get(str(row),0))+1
					plan.footpaths.append(connection)
					var n := (connection[1]-connection[0]).normalized().orthogonal()*1.0
					fit.reserve("path:"+s.iid,PackedVector2Array([connection[0]+n,connection[1]+n,connection[1]-n,connection[0]-n]))

func _accept(s: Dictionary) -> void:
	s.footprints=fit.footprints(s);s.footprint=s.footprints[0]
	for poly in s.footprints: fit.reserve(str(s.iid),poly)
	world.standing.append(s);added.append(s)
