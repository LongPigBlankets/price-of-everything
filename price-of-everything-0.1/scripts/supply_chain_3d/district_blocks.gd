extends RefCounted
## Renderer-only, road-seeded Voronoi neighbourhoods. No simulation road edits.
const Trial := preload("res://scripts/supply_chain_3d/stoneshore_trial.gd")
const Index := preload("res://scripts/supply_chain_3d/road_index.gd")
const Model := preload("res://scripts/empire_board_model.gd")
const Region := preload("res://scripts/supply_chain_3d/authored_region.gd")
const Cache := preload("res://scripts/supply_chain_3d/bake_cache.gd")
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const Depot := preload("res://scripts/supply_chain_3d/rail_depot.gd")
const WIDTHS := [4.8, 4.6, 4.4, 4.2] # 8.4u carriageway, one lane each way
var centers := {}
var tile_index := {}
var roads: Array = []
var road_index := {}
var obstacles: Array = []
var obstacle_index := {}
var rails: Array = []
var harbours: Array = []
var rail_index := {}
var ground: Callable
var water: Callable

static func clip_half_plane(poly: PackedVector2Array, normal: Vector2, distance: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if poly.is_empty(): return out
	var a := poly[-1]; var da := a.dot(normal) - distance
	for b in poly:
		var db := b.dot(normal) - distance
		if (da <= 0.0) != (db <= 0.0): out.append(a.lerp(b, da / (da-db)))
		if db <= 0.0: out.append(b)
		a=b; da=db
	return out

static func cells(sites: PackedVector2Array, bounds: Rect2) -> Array:
	# Local coordinates avoid cancellation between squared world coordinates.
	var origin := bounds.get_center()
	var local := PackedVector2Array()
	for p in sites: local.append(p-origin)
	var box := Rect2(bounds.position-origin,bounds.size)
	var result: Array = []
	for i in local.size():
		var poly := PackedVector2Array([box.position, Vector2(box.end.x,box.position.y), box.end, Vector2(box.position.x,box.end.y)])
		for j in local.size():
			if i==j: continue
			var normal := local[j]-local[i]
			poly=clip_half_plane(poly,normal,(local[j].length_squared()-local[i].length_squared())*0.5)
			if poly.is_empty(): break
		for k in poly.size(): poly[k]+=origin
		result.append(poly)
	return result

func apply(model: Dictionary, height: Callable, wet: Callable, prepared: Dictionary) -> void:
	if "--stoneshore-baseline" in OS.get_cmdline_user_args(): return
	ground=height; water=wet
	for tid in Trial.TILES:
		if model.tiles.has(tid) and str(model.tiles[tid].type)=="urban": centers[tid]=model.tiles[tid].center
	if centers.is_empty(): return
	tile_index=Index.tiles(centers)
	roads=model.roads.filter(func(r: Dictionary) -> bool: return centers.has(str(r.tile)))
	road_index=Index.segments(roads,30)
	for s in model.standing:
		if str(s.kind) in ["house","pylon"]: continue
		if s.has("harbour"):
			harbours.append(s.harbour.shore_anchor)
			obstacles.append(s.harbour.main_quay)
			obstacles.append_array(s.harbour.quays)
		else:
			var dim := Assets.dimensions(preload("res://scripts/supply_chain_3d/world_builder.gd").standing_key(s))*float(s.side)
			var half := Vector2(maxf(dim.x,12),maxf(dim.z,12))*.5
			var poly := PackedVector2Array()
			for p in [Vector2(-half.x,-half.y),Vector2(half.x,-half.y),half,Vector2(-half.x,half.y)]: poly.append(s.pos+p.rotated(-float(s.get("yaw",0))))
			obstacles.append(s.get("footprint",poly))
	for depot in model.get("depots",[]): obstacles.append(Depot.yard_polygon(depot))
	for i in obstacles.size():
		var box := Rect2(obstacles[i][0],Vector2.ZERO)
		for p in obstacles[i]: box=box.expand(p)
		Index.insert(obstacle_index,box.grow(10),i)
	var rail_plan := preload("res://scripts/supply_chain_3d/railway.gd").network(model.get("lines",[]))
	var pilot_centers := {}
	for tid in Trial.TILES:
		if model.tiles.has(tid): pilot_centers[tid]=model.tiles[tid].center
	var pilot_index := Index.tiles(pilot_centers)
	for corridor in rail_plan.corridors:
		for i in range(1,corridor.points.size()):
			var a: Vector2=corridor.points[i-1];var b: Vector2=corridor.points[i]
			if Index.tile_at(pilot_index,pilot_centers,(a+b)*.5)=="": continue
			rails.append({"a":a,"b":b})
	model.trial_rail_segments=rails
	rail_index=Index.segments(rails,14)
	var key := Cache.digest([Cache.source_key("roads"),Cache.source_key("terrain"),centers,roads,obstacles,rails,harbours])
	var variants: Dictionary=prepared.get_or_add("district_blocks",{})
	var plan: Dictionary=variants.get(key,{})
	if plan.is_empty():
		plan=generate()
		while variants.size()>=4: variants.erase(variants.keys()[0])
		variants[key]=plan
	model.district_blocks=plan
	model.authored_region.paths.append_array(plan.paths.duplicate(true))
	model.roads=Index.split(model.roads+Region.compile_segments(plan.paths,centers))

func safe_point(p: Vector2, margin: float = 7.0) -> bool:
	for shore in harbours:
		if p.distance_to(shore)<205.0: return false
	if Index.tile_at(tile_index,centers,p).is_empty() or bool(water.call(p)): return false
	for id in obstacle_index.get(Vector2i((p/Index.CELL).floor()),[]):
		var poly: PackedVector2Array=obstacles[id]
		if Geometry2D.is_point_in_polygon(p,poly): return false
		for i in poly.size():
			if p.distance_to(Geometry2D.get_closest_point_to_segment(p,poly[i],poly[(i+1)%poly.size()]))<margin: return false
	for id in rail_index.get(Vector2i((p/Index.CELL).floor()),[]):
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p,rails[id].a,rails[id].b))<margin+5: return false
	return true

func safe_road(a: Vector2, b: Vector2) -> bool:
	var length := a.distance_to(b)
	var n := (b-a).normalized().orthogonal()*5.5
	var low := INF; var high := -INF
	var steps := maxi(1,ceili(length/4))
	for i in range(steps+1):
		var p := a.lerp(b,float(i)/steps)
		for q in [p,p+n,p-n]:
			if not safe_point(q,6): return false
			var h := float(ground.call(q));low=minf(low,h);high=maxf(high,h)
		if high-low>3.0: return false
	return true

func generate() -> Dictionary:
	var sites := PackedVector2Array()
	# Offset samples from real roads establish frontage depth and orientation.
	for r in roads:
		var length: float=r.a.distance_to(r.b)
		var count := maxi(1,ceili(length/100.0))
		for i in count:
			var p: Vector2=r.a.lerp(r.b,(i+.5)/count)
			var n: Vector2=(r.b-r.a).normalized().orthogonal()
			for direction in [-1,1]: _site(sites,p+n*direction*64)
	# Fill only large holes left by the authored network.
	for tid in centers:
		for y in range(-180,181,120):
			for x in range(-180,181,120):
				var h := absi(hash("%s:%d:%d" % [tid,x,y]))
				_site(sites,centers[tid]+Vector2(x+(h%37)-18,y+((h/37)%37)-18))
	var bounds := Rect2(centers.values()[0],Vector2.ZERO)
	for c in centers.values(): bounds=bounds.expand(c)
	bounds=bounds.grow(300)
	var polygons := cells(sites,bounds)
	var unique := {}; var edges: Array=[]
	for poly in polygons:
		for i in poly.size():
			var a: Vector2=poly[i];var b: Vector2=poly[(i+1)%poly.size()]
			var ka := Vector2i((a*100).round());var kb := Vector2i((b*100).round())
			var id := "%s:%s" % [ka if ka<kb else kb,kb if ka<kb else ka]
			if unique.has(id): continue
			unique[id]=true
			# Split at authored centrelines. Each accepted piece terminates exactly
			# at a main road, not at the edge of its painted casing.
			var cuts: Array=[a,b]
			for ri in Index.query(road_index,Index.bounds(a,b,1)):
				var hit: Variant=Geometry2D.segment_intersects_segment(a,b,roads[ri].a,roads[ri].b)
				if hit!=null: cuts.append(hit)
			cuts.sort_custom(func(p: Vector2,q: Vector2) -> bool: return p.distance_squared_to(a)<q.distance_squared_to(a))
			for j in range(1,cuts.size()):
				var p: Vector2=cuts[j-1];var q: Vector2=cuts[j]
				if p.distance_to(q)<24 or not safe_road(p,q) or parallel_main(p,q): continue
				edges.append({"a":p,"b":q})
	edges=connected_edges(edges)
	var paths: Array=[]; var length := 0.0
	for edge in edges:
		paths.append({"id":"district:%04d" % paths.size(),"points":PackedVector2Array([edge.a,edge.b]),
			"class":"minor","layer":0,"widths":WIDTHS,"level":2,"district_street":true})
		length+=edge.a.distance_to(edge.b)
	var plots: Array=[]
	for i in sites.size(): plots.append({"pos":sites[i],"polygon":polygons[i],"tile":Index.tile_at(tile_index,centers,sites[i])})
	return {"paths":paths,"plots":plots,"sites":sites.size(),"length":length}

func _site(sites: PackedVector2Array, p: Vector2) -> void:
	if not safe_point(p,15): return
	for other in sites:
		if p.distance_squared_to(other)<92*92: return
	sites.append(p)

func parallel_main(a: Vector2,b: Vector2) -> bool:
	var tangent := (b-a).normalized()
	for id in Index.query(road_index,Index.bounds(a,b,28)):
		var r: Dictionary=roads[id]
		if absf(tangent.dot((r.b-r.a).normalized()))<0.92: continue
		for t in [.25,.5,.75]:
			var p := a.lerp(b,t)
			if p.distance_to(Geometry2D.get_closest_point_to_segment(p,r.a,r.b))<float(r.widths[0])+10: return true
	return false

func connected_edges(edges: Array) -> Array:
	var nodes := {}; var anchored := {}; var live := {}
	for i in edges.size():
		for p in [edges[i].a,edges[i].b]:
			var key := Vector2i((p*20).round())
			(nodes.get_or_add(key,[]) as Array).append(i)
			for id in road_index.get(Vector2i((p/Index.CELL).floor()),[]):
				if p.distance_to(Geometry2D.get_closest_point_to_segment(p,roads[id].a,roads[id].b))<.1: anchored[key]=true
		live[i]=true
	# Remove unconnected dead ends, retaining loops and main-road connections.
	var changed := true
	while changed:
		changed=false
		for key in nodes:
			if anchored.has(key): continue
			var active: Array=nodes[key].filter(func(id): return live.has(id))
			if active.size()==1: live.erase(active[0]);changed=true
	var reached := {};var queue: Array=anchored.keys();var cursor := 0
	while cursor<queue.size():
		var key: Vector2i=queue[cursor];cursor+=1
		for id in nodes.get(key,[]):
			if reached.has(id) or not live.has(id): continue
			reached[id]=true
			for p in [edges[id].a,edges[id].b]: queue.append(Vector2i((p*20).round()))
	var result: Array=[]
	for i in edges.size():
		if reached.has(i): result.append(edges[i])
	return result
