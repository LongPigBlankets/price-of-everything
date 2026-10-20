extends RefCounted
## Display road engineering. Keep graph junctions fixed; lengthen steep approaches
## with rounded contour traverses, and omit the surface of mountain tunnels.
const Index := preload("res://scripts/supply_chain_3d/road_index.gd")
const Legacy := preload("res://scripts/empire_board.gd")
const Geo := preload("res://scripts/supply_chain_3d/geometry.gd")
const Rail := preload("res://scripts/supply_chain_3d/railway.gd")
const STEP := 6.0
const MAX_GRADE := 0.15
## Where no serpentine fits and the grade cannot be held to MAX_GRADE, a road climbs on an even
## profile at the gentlest of these grades rather than stepping with the ground.
const STEEP_GRADES := [0.2, 0.25, 0.3, 0.4]
const MAX_EARTHWORK := 14.0
const TUNNEL_LEVEL := 7.0
const MIN_TUNNEL_LENGTH := 10.0
var portals: Array = []
var switchbacks := 0
var constrained := 0
var grade_eased := 0
var _height: Callable
var _level: Callable
var _water: Callable
var _roads: Array = []
var _index := {}
var _obstacles: Array = []
var _obstacle_index := {}
var _centers := {}
var _tile_index := {}

func configure(model: Dictionary, height: Callable, level: Callable, water := Callable()) -> Array:
	portals.clear(); switchbacks=0; constrained=0; grade_eased=0
	_height=height; _level=level; _water=water
	_roads=model.get("roads",[]).duplicate(); _index=Index.segments(_roads,20)
	_centers.clear(); _obstacles.clear(); _obstacle_index.clear()
	for tid in model.get("tiles",{}): _centers[tid]=model.tiles[tid].center
	_tile_index=Index.tiles(_centers)
	for s in model.get("standing",[]):
		if s.has("footprints"):
			for shape in s.footprints: _add_obstacle(shape)
			continue
		var poly := PackedVector2Array(s.get("footprint",[]))
		if poly.size()<3:
			var p: Vector2=s.pos; var half: float=float(s.get("pad",s.get("side",16)))*0.5+3
			poly=PackedVector2Array([p+Vector2(-half,-half),p+Vector2(half,-half),p+Vector2(half,half),p+Vector2(-half,half)])
		_add_obstacle(poly)
	for depot in model.get("depots",[]): _add_obstacle(preload("res://scripts/supply_chain_3d/rail_depot.gd").yard_polygon(depot))
	var result: Array=[]
	for chain in _chains():
		var engineered := _engineer(chain)
		result.append_array(engineered)
	result=_tunnels(result)
	# No reference cycle through the owning WorldBuilder's bound methods.
	_height=Callable(); _level=Callable(); _water=Callable()
	_roads=[]; _index.clear(); _obstacles.clear(); _obstacle_index.clear()
	return result

func _add_obstacle(poly: PackedVector2Array) -> void:
	var bounds := Rect2(poly[0],Vector2.ZERO)
	for p in poly: bounds=bounds.expand(p)
	Index.insert(_obstacle_index,bounds.grow(20),_obstacles.size()); _obstacles.append(poly)

static func _key(p: Vector2) -> Vector2i: return Vector2i((p*100).round())
static func _half(road: Dictionary) -> float: return float(road.get("widths",Legacy._road_widths(int(road.get("level",1))))[0])

func _chains() -> Array:
	var nodes := {}; var used := {}; var result: Array=[]
	for i in _roads.size():
		for p in [_roads[i].a,_roads[i].b]: (nodes.get_or_add(_key(p),[]) as Array).append(i)
	# Junctions, width changes and layer changes are immutable anchors.
	var anchors := {}
	for key in nodes:
		var edges: Array=nodes[key]
		anchors[key]=edges.size()!=2
		if edges.size()==2:
			anchors[key]=not is_equal_approx(_half(_roads[edges[0]]),_half(_roads[edges[1]])) or _roads[edges[0]].get("layer",0)!=_roads[edges[1]].get("layer",0)
	for pass_id in 2:
		for start in nodes:
			if pass_id==0 and not anchors[start]: continue
			for first in nodes[start]:
				if used.has(first): continue
				var edge: int=first; var current: Vector2i=start; var chain: Array=[]
				while not used.has(edge):
					used[edge]=true
					var rec: Dictionary=_roads[edge].duplicate(); rec.original=edge
					if _key(rec.b)==current:
						var swap: Vector2=rec.a; rec.a=rec.b; rec.b=swap
					chain.append(rec); current=_key(rec.b)
					if anchors[current]: break
					var next: Array=nodes[current]; edge=next[1] if next[0]==edge else next[0]
				result.append(chain)
	return result

func _datum(p: Vector2, dir: Vector2, half: float) -> float:
	var side := dir.orthogonal()*half
	return minf(float(_height.call(p)),minf(float(_height.call(p+side)),float(_height.call(p-side))))

func _engineer(chain: Array) -> Array:
	var points := PackedVector2Array(); var owners: Array=[]; var distances := PackedFloat32Array([0.0])
	var half := _half(chain[0])
	points.append(chain[0].a)
	for rec in chain:
		var count := maxi(1,ceili(rec.a.distance_to(rec.b)/STEP))
		for j in range(1,count+1):
			var p: Vector2=rec.b if j==count else rec.a.lerp(rec.b,float(j)/count)
			distances.append(distances[-1]+points[-1].distance_to(p)); points.append(p); owners.append(rec)
	var runs: Array=[]
	for i in range(1,points.size()):
		var a := points[i-1]; var b := points[i]
		if float(_level.call(a))>=TUNNEL_LEVEL or float(_level.call(b))>=TUNNEL_LEVEL: continue
		if _water.is_valid() and (_water.call(a) or _water.call(b)): continue
		if absf(float(_height.call(b))-float(_height.call(a)))<=MAX_GRADE*a.distance_to(b)+0.1: continue
		var lo := maxi(0,i-1); var hi := i
		while lo>0 and distances[i-1]-distances[lo]<45 and float(_level.call(points[lo-1]))<TUNNEL_LEVEL: lo-=1
		while hi<points.size()-1 and distances[hi]-distances[i]<45 and float(_level.call(points[hi+1]))<TUNNEL_LEVEL: hi+=1
		if not runs.is_empty() and lo<=int(runs[-1][1]): runs[-1][1]=maxi(runs[-1][1],hi)
		else: runs.append([lo,hi])
	if runs.is_empty(): return chain
	var replacements := {}
	for run in runs:
		var lo: int=run[0]; var hi: int=run[1]
		if distances[hi]-distances[lo]<6: continue
		var source := points.slice(lo,hi+1)
		var excluded := {}
		for j in range(lo,hi): excluded[owners[j].original]=true
		var proposal := _serpentine(source,half,excluded) if distances[hi]-distances[lo]>=30 else {}
		if proposal.is_empty():
			# A short steep ripple can be removed by a shallow cutting when a
			# junction or existing building leaves no room to move the road.
			var heights := _profile(source,half,source)
			# With no room to wind, climb evenly at the gentlest grade that fits: steep, never stepped.
			for grade in STEEP_GRADES:
				if not heights.is_empty(): break
				heights = _profile(source,half,source,grade)
			if heights.is_empty(): heights = _ramp(source,half)
			if heights.is_empty(): constrained+=1; continue
			proposal={"points":source,"heights":heights,"eased":true}; grade_eased+=1
		var pieces: Array=[]; var routed: PackedVector2Array=proposal.points
		for i in range(1,routed.size()):
			var rec: Dictionary=owners[lo].duplicate()
			rec.a=routed[i-1]; rec.b=routed[i]; rec.road_ha=proposal.heights[i-1]; rec.road_hb=proposal.heights[i]; rec.serpentine=not proposal.get("eased",false)
			var tid := Index.tile_at(_tile_index,_centers,(rec.a+rec.b)*0.5)
			if tid!="": rec.tile=tid
			pieces.append(rec)
		replacements[lo]={"end":hi,"pieces":pieces}
		if not proposal.get("eased",false):
			switchbacks+=1
			# Reserve each accepted bend before routing another run, including
			# separate climbs belonging to this same original road chain.
			for rec in pieces:
				Index.insert(_index,Index.bounds(rec.a,rec.b,20),_roads.size()); _roads.append(rec)
	var result: Array=[]; var i := 0
	while i<points.size()-1:
		if replacements.has(i): result.append_array(replacements[i].pieces); i=replacements[i].end
		else:
			var rec: Dictionary=owners[i].duplicate(); rec.a=points[i]; rec.b=points[i+1]; result.append(rec); i+=1
	return result

func _serpentine(source: PackedVector2Array, half: float, excluded: Dictionary) -> Dictionary:
	var length := 0.0
	for i in range(1,source.size()): length+=source[i-1].distance_to(source[i])
	var axis := (source[-1]-source[0]).normalized(); var side := axis.orthogonal()
	# Search broad, few-turn alignments first. Every candidate gets a bounded
	# cut/fill profile; hairpin tips must not retain the original steep gradient.
	for turns in range(1,7):
		if length/turns<half*5: break
		for amplitude in [35.0,60.0,90.0,125.0,165.0,210.0]:
			for sign_v in [1.0,-1.0]:
				var controls := PackedVector2Array([source[0]])
				for k in turns:
					var t := (float(k)+0.5)/turns
					var pos := _along(source,t*length)
					controls.append(pos+side*amplitude*sign_v*(1.0 if k%2==0 else -1.0))
				controls.append(source[-1])
				var path := _rounded(controls,half*3.5)
				var heights := _profile(path,half,source)
				if heights.is_empty() or not _clear(path,half,excluded): continue
				return {"points":path,"heights":heights}
	return {}

static func _along(points: PackedVector2Array, distance: float) -> Vector2:
	for i in range(1,points.size()):
		var step := points[i-1].distance_to(points[i])
		if distance<=step: return points[i-1].lerp(points[i],distance/maxf(step,0.001))
		distance-=step
	return points[-1]

static func _rounded(controls: PackedVector2Array, radius: float) -> PackedVector2Array:
	var path := PackedVector2Array([controls[0]])
	for i in range(1,controls.size()-1):
		var p := controls[i]; var before := controls[i-1]; var after := controls[i+1]
		var reach := minf(radius*2.5,minf(p.distance_to(before),p.distance_to(after))*0.38)
		var a := p.move_toward(before,reach); var b := p.move_toward(after,reach)
		_line(path,a)
		var count := maxi(8,ceili((a.distance_to(p)+p.distance_to(b))/STEP))
		for j in range(1,count+1):
			var t := float(j)/count
			path.append(a.lerp(p,t).lerp(p.lerp(b,t),t))
	_line(path,controls[-1]); return path

static func _line(path: PackedVector2Array, end: Vector2) -> void:
	var start := path[-1]; var count := maxi(1,ceili(start.distance_to(end)/STEP))
	for i in range(1,count+1): path.append(end if i==count else start.lerp(end,float(i)/count))

## An even climb between the two anchors, for a stretch too short or tight for any other profile.
func _ramp(path: PackedVector2Array, half: float) -> PackedFloat32Array:
	if path.size() < 2: return PackedFloat32Array()
	var first := _datum(path[0],(path[1]-path[0]).normalized(),half)
	var last := _datum(path[-1],(path[-1]-path[-2]).normalized(),half)
	var length := 0.0
	for i in range(1,path.size()): length+=path[i-1].distance_to(path[i])
	var result := PackedFloat32Array([first]); var along := 0.0
	for i in range(1,path.size()):
		along+=path[i-1].distance_to(path[i])
		result.append(lerpf(first,last,along/maxf(length,0.001)))
	return result

func _profile(path: PackedVector2Array, half: float, source: PackedVector2Array, grade: float = MAX_GRADE) -> PackedFloat32Array:
	var lower := PackedFloat32Array(); var upper := PackedFloat32Array(); var natural := PackedFloat32Array()
	for i in path.size():
		var dir := (path[mini(i+1,path.size()-1)]-path[maxi(0,i-1)]).normalized()
		var h := _datum(path[i],dir,half)
		natural.append(h); lower.append(h-MAX_EARTHWORK); upper.append(h+MAX_EARTHWORK)
	# Match the unchanged carriageway at both anchors, including its crossfall cut.
	lower[0]=_datum(source[0],(source[1]-source[0]).normalized(),half); upper[0]=lower[0]
	lower[-1]=_datum(source[-1],(source[-1]-source[-2]).normalized(),half); upper[-1]=lower[-1]
	for i in range(1,path.size()):
		var rise := path[i].distance_to(path[i-1])*grade
		lower[i]=maxf(lower[i],lower[i-1]-rise); upper[i]=minf(upper[i],upper[i-1]+rise)
	for i in range(path.size()-2,-1,-1):
		var rise := path[i].distance_to(path[i+1])*grade
		lower[i]=maxf(lower[i],lower[i+1]-rise); upper[i]=minf(upper[i],upper[i+1]+rise)
	for i in path.size():
		if lower[i]>upper[i]+0.001: return PackedFloat32Array()
	var result := PackedFloat32Array([lower[0]])
	for i in range(1,path.size()):
		var rise := path[i].distance_to(path[i-1])*grade
		result.append(clampf(natural[i],maxf(lower[i],result[-1]-rise),minf(upper[i],result[-1]+rise)))
	return result

func _clear(path: PackedVector2Array, half: float, excluded: Dictionary) -> bool:
	for i in range(1,path.size()):
		var a := path[i-1]; var b := path[i]; var dir := (b-a).normalized(); var side := dir.orthogonal()*(half+3)
		for p in [b,b-side,b+side]:
			if float(_level.call(p))>=TUNNEL_LEVEL: return false
			if _water.is_valid() and _water.call(p): return false
			if not _centers.is_empty() and Index.tile_at(_tile_index,_centers,p)=="": return false
			for id in _obstacle_index.get(Vector2i((p/Index.CELL).floor()),[]):
				if Geometry2D.is_point_in_polygon(p,_obstacles[id]): return false
		for id in Index.query(_index,Index.bounds(a,b,half+12)):
			if excluded.has(id): continue
			var road: Dictionary=_roads[id]
			# Other arms sharing a pinned junction may touch only at that junction.
			if b.distance_to(path[0])<half*3 or b.distance_to(path[-1])<half*3: continue
			if Geometry2D.segment_intersects_segment(a,b,road.a,road.b)!=null: return false
			if b.distance_to(Geometry2D.get_closest_point_to_segment(b,road.a,road.b))<half+_half(road)+3: return false
	# Non-adjacent arms must leave room for both road shoulders.
	var own := {}; var distance := 0.0; var along := PackedFloat32Array([0.0])
	for i in range(1,path.size()):
		distance+=path[i-1].distance_to(path[i]); along.append(distance)
		for j in Index.query(own,Index.bounds(path[i-1],path[i],half*2+3)):
			if distance-along[j]<half*8: continue
			if path[i].distance_to(Geometry2D.get_closest_point_to_segment(path[i],path[j-1],path[j]))<half*2+3: return false
		Index.insert(own,Index.bounds(path[i-1],path[i]),i)
	return true

func _hidden(p: Vector2, dir: Vector2, half: float) -> bool:
	var side := dir.orthogonal()*half
	return float(_level.call(p))>=TUNNEL_LEVEL or float(_level.call(p+side))>=TUNNEL_LEVEL or float(_level.call(p-side))>=TUNNEL_LEVEL

func _tunnels(roads: Array) -> Array:
	var result: Array=[]; var ends := {}
	for road in roads:
		var a: Vector2=road.a; var b: Vector2=road.b; var dir := (b-a).normalized(); var half := _half(road)
		# Sample inside segments as well: a mountain may lie between two low ends.
		var count := maxi(1,ceili(a.distance_to(b)/3.0)); var cuts := [0.0]
		var previous := _hidden(a,dir,half)
		for i in range(1,count+1):
			var t := float(i)/count; var hidden := _hidden(a.lerp(b,t),dir,half)
			if hidden!=previous:
				var lo := float(i-1)/count; var hi := t
				for iteration in 12:
					var mid := (lo+hi)*0.5
					if _hidden(a.lerp(b,mid),dir,half)==previous: lo=mid
					else: hi=mid
				cuts.append((lo+hi)*0.5)
			previous=hidden
		cuts.append(1.0)
		for i in range(1,cuts.size()):
			var rec: Dictionary=road.duplicate(); rec.a=a if cuts[i-1]==0.0 else a.lerp(b,cuts[i-1]); rec.b=b if cuts[i]==1.0 else a.lerp(b,cuts[i])
			if rec.a.distance_to(rec.b)<0.005: continue
			rec.tunnel=_hidden((rec.a+rec.b)*0.5,dir,half)
			if road.has("road_ha"):
				rec.road_ha=lerpf(road.road_ha,road.road_hb,cuts[i-1]); rec.road_hb=lerpf(road.road_ha,road.road_hb,cuts[i])
			result.append(rec)
			for p in [rec.a,rec.b]: (ends.get_or_add(_key(p),[]) as Array).append(rec)
	# Measure continuous covered runs, including across source segments and hex
	# edges. Reject tiny ridge grazes before extending approaches or merging
	# daylight, either of which could otherwise inflate a false tunnel.
	for run in _tunnel_runs(result):
		if run.length + 0.001 < MIN_TUNNEL_LENGTH:
			for id in run.ids: result[id].tunnel=false
	_extend_steep_approaches(result,ends)
	_merge_daylight(result,ends)
	for run in _tunnel_runs(result):
		for id in run.ids: result[id]._bore_length=run.length
	# Build each portal once, also when the transition coincides with a tile edge.
	for key in ends:
		var visible: Array=ends[key].filter(func(r): return not r.tunnel)
		var covered: Array=ends[key].filter(func(r): return r.tunnel)
		if visible.is_empty() or covered.is_empty(): continue
		for surface in visible:
			surface["tunnel_a" if _key(surface.a)==key else "tunnel_b"]=true
		var road: Dictionary=visible[0]; var p: Vector2=road.a if _key(road.a)==key else road.b
		var dir: Vector2=(p-(road.b if _key(road.a)==key else road.a)).normalized()
		portals.append({"p":p,"dir":dir,"tile":road.tile,"half_width":_half(road)+1.8,"depth":minf(22.0,float(covered[0]._bore_length)*0.45)})
	for road in result: road.erase("_bore_length")
	return result

static func _tunnel_runs(roads: Array) -> Array:
	var nodes := {}; var seen := {}; var runs: Array=[]
	for id in roads.size():
		for p in [roads[id].a,roads[id].b]: (nodes.get_or_add(_key(p),[]) as Array).append(id)
	for first in roads.size():
		if not roads[first].get("tunnel",false) or seen.has(first): continue
		var ids: Array=[first]; var length := 0.0; var cursor := 0
		seen[first]=true
		while cursor<ids.size():
			var road: Dictionary=roads[ids[cursor]]; cursor+=1
			length+=road.a.distance_to(road.b)
			for p in [road.a,road.b]:
				var adjacent: Array=nodes[_key(p)]
				# Branch lengths cannot be added together to qualify a short arm.
				if adjacent.size()!=2: continue
				for id in adjacent:
					if not seen.has(id) and roads[id].get("tunnel",false):
						seen[id]=true; ids.append(id)
		runs.append({"ids":ids,"length":length})
	return runs


func _extend_steep_approaches(roads: Array, ends: Dictionary) -> void:
	# A constrained road should enter the foot of a mountain, not climb a cliff
	# to reach the numeric band boundary. Preserve engineered switchbacks.
	var queue: Array=[]
	for key in ends:
		if ends[key].any(func(r): return r.tunnel) and ends[key].any(func(r): return not r.tunnel):
			queue.append({"key":key,"distance":0.0})
	var cursor := 0
	while cursor<queue.size():
		var item: Dictionary=queue[cursor]; cursor+=1
		var adjacent: Array=ends[item.key]
		if adjacent.size()!=2 or item.distance>180: continue
		for road in adjacent:
			if road.tunnel or road.has("road_ha"): continue
			var length: float=road.a.distance_to(road.b)
			var ha := _datum(road.a,(road.b-road.a).normalized(),_half(road))
			var hb := _datum(road.b,(road.b-road.a).normalized(),_half(road))
			if absf(hb-ha)<=MAX_GRADE*length+0.05: continue
			road.tunnel=true
			var other := _key(road.b) if _key(road.a)==item.key else _key(road.a)
			queue.append({"key":other,"distance":float(item.distance)+length})

func _merge_daylight(roads: Array, ends: Dictionary) -> void:
	# Jagged band boundaries otherwise produce several portal pairs a few metres
	# apart. Keep short intervening sections inside the same mountain bore.
	var seen := {}
	for id in roads.size(): roads[id]._alignment_id=id
	for first in roads:
		if first.tunnel or seen.has(first._alignment_id): continue
		var queue: Array=[first]; var component: Array=[]; var rim := {}; var length := 0.0; var closed := true
		seen[first._alignment_id]=true
		while not queue.is_empty():
			var road: Dictionary=queue.pop_back(); component.append(road); length+=road.a.distance_to(road.b)
			for p in [road.a,road.b]:
				var key := _key(p); var neighbors: Array=ends[key]
				if neighbors.size()!=2: closed=false
				for other in neighbors:
					if other.tunnel: rim[key]=true
					elif not seen.has(other._alignment_id): seen[other._alignment_id]=true; queue.append(other)
		if closed and rim.size()==2 and length<32:
			for road in component: road.tunnel=true
	for road in roads: road.erase("_alignment_id")

func mesh_for(tile: String, height: Callable, origin := Vector2.ZERO, terrain := Callable(), earth := Callable()) -> ArrayMesh:
	var batch := Geo.Batch.new()
	for portal in portals:
		if str(portal.tile)!=tile: continue
		var rec: Dictionary=portal.duplicate()
		rec.h=float(height.call(rec.p))+0.8; rec.half_width=portal.half_width-1.8
		preload("res://scripts/supply_chain_3d/tunnel_portal.gd").append(batch,rec,origin,terrain if terrain.is_valid() else height,earth)
	return batch.mesh()
