extends RefCounted
## Smooth the presentation network before fitting lots. Junction anchors stay put.
const Index := preload("res://scripts/supply_chain_3d/road_index.gd")
const Region := preload("res://scripts/supply_chain_3d/authored_region.gd")
const Trial := preload("res://scripts/supply_chain_3d/stoneshore_trial.gd")
const Cache := preload("res://scripts/supply_chain_3d/bake_cache.gd")

static func arc(a: Vector2, p: Vector2, b: Vector2, reach: float) -> PackedVector2Array:
	var trim := minf(reach,minf(a.distance_to(p),b.distance_to(p))*.38)
	var first := p.move_toward(a,trim);var last := p.move_toward(b,trim)
	var points := PackedVector2Array()
	var steps := maxi(6,ceili(first.distance_to(last)/2.0))
	for i in steps+1:
		var t := float(i)/steps
		points.append(first.lerp(p,t).lerp(p.lerp(last,t),t))
	return points

static func rounded_path(points: PackedVector2Array, reach := 18.0) -> PackedVector2Array:
	var result := PackedVector2Array([points[0]])
	for i in range(1,points.size()-1):
		var angle := absf((points[i]-points[i-1]).angle_to(points[i+1]-points[i]))
		if angle<deg_to_rad(18) or angle>deg_to_rad(150):result.append(points[i]);continue
		result.append_array(arc(points[i-1],points[i],points[i+1],reach))
	result.append(points[-1]);return result

static func apply(model: Dictionary, height: Callable, water: Callable, key_for: Callable, prepared: Dictionary) -> void:
	var protected: Array=[]
	for s in model.standing:
		if not s.has("harbour") and s.kind in ["house","warehouse","suppliers","pylon"]:continue
		protected.append([s.pos,s.side,s.get("yaw",0),s.get("footprint",[]),s.get("harbour",{}),str(key_for.call(s))])
	var key := Cache.digest([Cache.source_key("roads"),Cache.source_key("terrain"),model.roads,model.get("trial_rail_segments",[]),protected])
	var variants: Dictionary=prepared.get_or_add("street_curves",{})
	if variants.has(key):
		model.roads=variants[key].roads.duplicate(true)
		model.authored_region.paths=variants[key].paths.duplicate(true)
		model.street_curves=variants[key].audit;return
	var fixed: Array=[]
	for s in model.standing:
		if s.has("harbour"):fixed.append(s.harbour.main_quay);fixed.append_array(s.harbour.quays)
		elif s.kind not in ["house","warehouse","suppliers","pylon"]:
			fixed.append_array(preload("res://scripts/supply_chain_3d/building_footprints.gd").reserved(str(key_for.call(s)),s))
	var fixed_index := {}
	for i in fixed.size(): Index.insert(fixed_index,preload("res://scripts/supply_chain_3d/road_placement.gd").polygon_bounds(fixed[i]).grow(30),i)
	var rails: Array=model.get("trial_rail_segments",[])
	var rail_index := Index.segments(rails,32)
	var edges: Array=[];var unique := {};var nodes := {};var centers := {}
	for tid in model.tiles:centers[tid]=model.tiles[tid].center
	for road in model.roads:
		var a := Vector2i((road.a*100).round());var b := Vector2i((road.b*100).round())
		var id := str([a if a<b else b,b if a<b else a,road.get("layer",0)])
		if unique.has(id):continue
		unique[id]=true;var edge: Dictionary=road.duplicate(true);edge.ka=a;edge.kb=b
		for k in [a,b]:(nodes.get_or_add(k,[]) as Array).append(edges.size())
		edges.append(edge)
	var corners := {};var count := 0
	for k in nodes:
		if nodes[k].size()!=2:continue
		var e: Dictionary=edges[nodes[k][0]];var f: Dictionary=edges[nodes[k][1]]
		if e.get("layer",0)!=f.get("layer",0) or e.widths!=f.widths:continue
		var p := Vector2(k)*.01
		var a: Vector2=e.b if e.ka==k else e.a;var b: Vector2=f.b if f.ka==k else f.a
		var angle := absf((p-a).angle_to(b-p))
		if angle<deg_to_rad(18) or angle>deg_to_rad(150):continue
		# Preserve the already engineered depot routes and bridge/rail approaches.
		if str(e.source).begins_with("depot:") or str(f.source).begins_with("depot:") or str(e.source).begins_with("port:") or str(f.source).begins_with("port:"):continue
		var near_rail := false
		for ri in rail_index.get(Vector2i((p/Index.CELL).floor()),[]):
			var r: Dictionary=rails[ri]
			if p.distance_to(Geometry2D.get_closest_point_to_segment(p,r.a,r.b))<32:near_rail=true;break
		if near_rail:continue
		var curve := arc(a,p,b,clampf(float(e.widths[0])*4,18,36))
		var safe := true
		for q in curve:
			if water.call(q) or absf(float(height.call(q))-float(height.call(p)))>3:safe=false;break
			for id in fixed_index.get(Vector2i((q/Index.CELL).floor()),[]):
				var shape: PackedVector2Array=fixed[id]
				if preload("res://scripts/supply_chain_3d/road_placement.gd").distance_to_polygon(q,q,shape)<float(e.widths[0])+3.0:safe=false;break
		if not safe:continue
		corners[k]={"points":curve,"first":nodes[k][0],"owner":e};count+=1
	var paths: Array=[]
	for i in edges.size():
		var e: Dictionary=edges[i];var a: Vector2=e.a;var b: Vector2=e.b
		if corners.has(e.ka):a=corners[e.ka].points[0 if corners[e.ka].first==i else -1]
		if corners.has(e.kb):b=corners[e.kb].points[0 if corners[e.kb].first==i else -1]
		paths.append(_path(e,PackedVector2Array([a,b])))
	for corner in corners.values():paths.append(_path(corner.owner,corner.points))
	model.authored_region.paths=paths
	model.roads=Region.compile_segments(paths,centers)
	model.street_curves={"rounded_bends":count}
	variants[key]={"roads":model.roads.duplicate(true),"paths":paths.duplicate(true),"audit":model.street_curves}

static func _path(road: Dictionary, points: PackedVector2Array) -> Dictionary:
	return {"id":road.source,"points":points,"class":"minor","layer":road.get("layer",0),"level":road.level,"widths":road.widths,"district_street":road.get("district_street",false)}

## A small concave fillet between outgoing road edges. Collinear joins remain
## straight; no circles or bulbous end caps are added to a through junction.
static func flare(p: Vector2, a: Vector2, b: Vector2, wa: float, wb: float, reach := 5.0) -> PackedVector2Array:
	var angle := fposmod(b.angle()-a.angle(),TAU)
	if angle<deg_to_rad(35) or angle>deg_to_rad(145):return PackedVector2Array()
	var na := Vector2(-a.y,a.x);var nb := Vector2(b.y,-b.x)
	var corner: Variant=Geometry2D.line_intersects_line(p+na*wa,a,p+nb*wb,b)
	if corner==null or corner.distance_to(p)>maxf(wa,wb)*3:return PackedVector2Array()
	var first: Vector2=corner+a*reach;var last: Vector2=corner+b*reach
	var poly := PackedVector2Array([p,first])
	for i in range(1,9):
		var t := i/8.0;poly.append(first.lerp(corner,t).lerp((corner as Vector2).lerp(last,t),t))
	poly.append(p)
	return poly

static func junctions(roads: Array) -> Array:
	var nodes := {};var result: Array=[]
	for road in roads:
		if road.get("tunnel",false) or str(road.get("source","")).begins_with("access:"):continue
		for ends in [[road.a,road.b],[road.b,road.a]]:
			var k := Vector2i((ends[0]*100).round());var arms: Array=nodes.get_or_add(k,[])
			var d: Vector2=(ends[1]-ends[0]).normalized()
			if not arms.any(func(arm):return arm.d.dot(d)>.99):arms.append({"d":d,"road":road})
	for k in nodes:
		var arms: Array=nodes[k]
		if arms.size()<3:continue
		arms.sort_custom(func(a,b):return a.d.angle()<b.d.angle())
		for i in arms.size():result.append({"p":Vector2(k)*.01,"a":arms[i],"b":arms[(i+1)%arms.size()]})
	return result
