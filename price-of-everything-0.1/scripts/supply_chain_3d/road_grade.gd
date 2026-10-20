extends RefCounted
## Shared road datum, terrain cut and road-over-rail bridge profile.
const Index := preload("res://scripts/supply_chain_3d/road_index.gd")
const Geo := preload("res://scripts/supply_chain_3d/geometry.gd")
const Legacy := preload("res://scripts/empire_board.gd")
const Rail := preload("res://scripts/supply_chain_3d/railway.gd")
const STEP := 6.0
const CELL := 16.0
const SHOULDER := 8.0
## A river deck stands above its banks: every road meeting it climbs over this distance.
const RIVER_APPROACH := 40.0
var segments: Array = []
var buckets := {}
var earth_buckets := {}
var nodes := {}
var bridges: Array = []
var crossings: Array = []
var junctions: Array = []

func configure(roads: Array, height: Callable, authored: RefCounted = null) -> void:
	segments.clear(); buckets.clear(); earth_buckets.clear(); nodes.clear(); bridges.clear(); crossings.clear(); junctions.clear()
	for road in roads:
		if road.get("tunnel",false): continue
		var a: Vector2 = road.a; var b: Vector2 = road.b
		if a.distance_to(b)<0.1: continue
		var half := float(road.get("widths",Legacy._road_widths(int(road.get("level",1))))[0])
		var n := (b-a).normalized().orthogonal()*half
		var steps := maxi(1,ceili(a.distance_to(b)/STEP))
		var previous := Vector2i.ZERO
		for i in range(steps+1):
			var p := a.lerp(b,float(i)/steps); var key := Vector2i((p*100).round())
			# Cut into the uphill bank rather than banking the carriageway across it.
			var left := float(height.call(p-n)); var right := float(height.call(p+n)); var center := float(height.call(p))
			var h := minf(center,minf(left,right))
			var cut := maxf(center,maxf(left,right))-h>0.2
			if road.has("road_ha"):
				h=lerpf(road.road_ha,road.road_hb,float(i)/steps)
				cut=cut or absf(h-center)>0.1
			var river_bridge := false
			if authored != null and not road.get("serpentine",false):
				var ah: float = authored.bridge_height_at(p)
				if ah > float(height.call(p))+1.0: h = ah; river_bridge = true
			if not nodes.has(key): nodes[key] = {"p":p,"h":h,"edges":[],"core":false,"river":river_bridge,"cut":cut}
			else:
				nodes[key].h = minf(nodes[key].h,h)
				nodes[key].river = nodes[key].river or river_bridge
				nodes[key].cut = nodes[key].cut or cut
			if i>0:
				var rec: Dictionary = road.duplicate()
				rec.a = nodes[previous].p; rec.b = p; rec.ka = previous; rec.kb = key; rec.half = half
				var id := segments.size(); segments.append(rec)
				nodes[previous].edges.append(id); nodes[key].edges.append(id)
			previous = key
	for node in nodes.values():
		node.base = node.h
		if node.edges.size()>=3: junctions.append(node.p)
	refresh()

## Ease every road that meets a river deck up to it over RIVER_APPROACH, across junctions too.
## A deck path's own ramp stops where its path does, and the road it joins would otherwise
## step onto the deck at the bank. Run once the rail crossings are known: a road that crosses
## the railway at level keeps its height there, so the ramp stops short of it.
func ease_river_decks() -> void:
	var level := {}
	for rec in segments:
		if str(rec.get("rail_crossing_mode", "")) == "level": level[rec.ka] = true; level[rec.kb] = true
	for key in nodes:
		var deck_node: Dictionary = nodes[key]
		if not deck_node.river: continue
		var distances := {key: 0.0}
		var queue: Array = [key]
		var cursor := 0
		while cursor < queue.size():
			var at: Vector2i = queue[cursor]; cursor += 1
			for edge in nodes[at].edges:
				var rec: Dictionary = segments[edge]
				var other: Vector2i = rec.kb if rec.ka == at else rec.ka
				var node: Dictionary = nodes[other]
				if node.river or level.has(other): continue
				var next: float = float(distances[at]) + nodes[at].p.distance_to(node.p)
				if next >= RIVER_APPROACH or next >= float(distances.get(other, INF)): continue
				distances[other] = next
				queue.append(other)
				var eased := lerpf(float(deck_node.h), float(node.base), smoothstep(0.0, RIVER_APPROACH, next))
				if eased > node.h:
					node.h = eased
					node.eased = true
	refresh()

func refresh() -> void:
	buckets.clear(); earth_buckets.clear()
	for i in segments.size():
		var rec: Dictionary = segments[i]
		rec.ha = nodes[rec.ka].h; rec.hb = nodes[rec.kb].h
		rec.bridge = nodes[rec.ka].core or nodes[rec.kb].core or nodes[rec.ka].river or nodes[rec.kb].river
		# A river approach is raised too, but it is not a deck over the railway.
		rec.over_rail = nodes[rec.ka].core or nodes[rec.kb].core or (rec.ha>nodes[rec.ka].base+0.01 and not nodes[rec.ka].get("eased",false)) or (rec.hb>nodes[rec.kb].base+0.01 and not nodes[rec.kb].get("eased",false))
		rec.earthwork = nodes[rec.ka].cut or nodes[rec.kb].cut or rec.over_rail
		rec.cut = Legacy._capsule(rec.a,rec.b,maxf(0.5,float(rec.half)-0.8),[false,false])
		Index.insert(buckets,Index.bounds(rec.a,rec.b,float(rec.half)+SHOULDER),i,CELL)
		if rec.earthwork: Index.insert(earth_buckets,Index.bounds(rec.a,rec.b,float(rec.half)+SHOULDER),i,CELL)

func bridge_rail_junctions(plan: Dictionary, rail_height: Callable, buried: Callable) -> void:
	var road_index := Index.segments(segments)
	var zones: Array = []
	var movements := {}
	for corridor in plan.corridors:
		if not corridor.has("junction"): continue
		for i in range(1,corridor.points.size()):
			(movements.get_or_add(corridor.junction,[]) as Array).append({"a":corridor.points[i-1],"b":corridor.points[i]})
	for junction in plan.junctions:
		var radius := float(junction.get("radius",Rail.CURVE))+Rail.CORRIDOR_WIDTH
		var affected := {}; var candidates := {}; var seeds: Array = []
		var rails: Array = movements.get(Rail._key(junction.p),[])
		var rail_index := Index.segments(rails)
		for i in Index.query(road_index,Rect2(junction.p,Vector2.ZERO).grow(radius)):
			var rec: Dictionary = segments[i]
			if str(rec.get("tile","")) in preload("res://scripts/supply_chain_3d/stoneshore_trial.gd").TILES: continue
			var p := Geometry2D.get_closest_point_to_segment(junction.p,rec.a,rec.b)
			if p.distance_to(junction.p)>radius or (buried.is_valid() and buried.call(p)): continue
			candidates[i]=true
			for rail_id in Index.query(rail_index,Index.bounds(rec.a,rec.b)):
				var rail: Dictionary = rails[rail_id]
				if Geometry2D.segment_intersects_segment(rec.a,rec.b,rail.a,rail.b)!=null:
					seeds.append(rec.ka); seeds.append(rec.kb); break
		var visit := 0
		while visit<seeds.size():
			var key: Vector2i = seeds[visit]; visit+=1
			if affected.has(key): continue
			affected[key]=true
			for edge in nodes[key].edges:
				if candidates.has(edge): seeds.append(segments[edge].ka); seeds.append(segments[edge].kb)
		if affected.is_empty(): continue
		# The whole junction remains at rail grade. Road decks span its envelope.
		var deck := -INF
		for key in affected:
			deck = maxf(deck,float(rail_height.call(nodes[key].p))+1.25+Rail.CLEARANCE+Rail.DECK_DEPTH)
		var distances := {}; var queue: Array = affected.keys(); var cursor := 0
		for key in queue: distances[key] = 0.0; nodes[key].core = true
		while cursor<queue.size():
			var key: Vector2i = queue[cursor]; cursor += 1
			var node: Dictionary = nodes[key]; var distance: float = distances[key]
			node.h = maxf(node.h,lerpf(deck,node.base,smoothstep(0,Rail.APPROACH,distance)))
			for edge in node.edges:
				var rec: Dictionary = segments[edge]
				var other: Vector2i = rec.kb if rec.ka==key else rec.ka
				var next: float = distance+node.p.distance_to(nodes[other].p)
				if next>=Rail.APPROACH or next>=float(distances.get(other,INF)): continue
				distances[other]=next; queue.append(other)
		zones.append({"p":junction.p,"radius":radius,"deck":deck,"nodes":affected.size()})
	bridges = zones; refresh()

func sample(p: Vector2, earth_only := false) -> Dictionary:
	# A nearby hairpin arm can be many metres higher. Blending every road in
	# the bucket pulls the lower arm uphill and defeats its engineered grade.
	var closest := INF; var result := {}
	for i in (earth_buckets if earth_only else buckets).get(Vector2i((p/CELL).floor()),[]):
		var rec: Dictionary=segments[i]
		var q := Geometry2D.get_closest_point_to_segment(p,rec.a,rec.b)
		var d := p.distance_to(q)
		if d>=float(rec.half)+SHOULDER or d>=closest: continue
		var t: float=rec.a.distance_to(q)/maxf(0.01,rec.a.distance_to(rec.b))
		closest=d
		result={"h":lerpf(rec.ha,rec.hb,t),"distance":d,"half":rec.half,"bridge":rec.bridge}
	return result

func height_at(p: Vector2, fallback: float) -> float:
	var hit := sample(p)
	return fallback if hit.is_empty() else float(hit.h)

func earth_height(p: Vector2, natural: float) -> float:
	# Include unchanged roads: an adjacent raised approach must not spill its
	# embankment across a closer, lower carriageway.
	var hit := sample(p)
	if hit.is_empty(): return natural
	# A bridge may meet an uphill bank. Cut intruding ground but retain the
	# valley below the deck; never fill underneath a bridge.
	var blend := 1.0-smoothstep(float(hit.half)+0.4,float(hit.half)+SHOULDER,float(hit.distance))
	var datum := minf(natural,float(hit.h)-0.15) if hit.bridge else float(hit.h)-0.15
	return lerpf(natural,datum,blend)

func cut_out(poly: PackedVector2Array) -> Array:
	var bounds := Rect2(poly[0],Vector2.ZERO)
	for p in poly: bounds=bounds.expand(p)
	var parts: Array = [poly]
	for i in Index.query(earth_buckets,bounds,CELL):
		var rec: Dictionary = segments[i]
		if rec.bridge or not bounds.intersects(Index.bounds(rec.a,rec.b,rec.half+0.4)): continue
		var next: Array = []
		for part in parts: next.append_array(Geometry2D.clip_polygons(part,rec.cut))
		parts=next
	return parts

func bridge_mesh(tid: String, origin: Vector2, ground: Callable) -> ArrayMesh:
	var batch := Geo.Batch.new()
	for rec in segments:
		if str(rec.get("tile",""))!=tid or not (nodes[rec.ka].core or nodes[rec.kb].core): continue
		var n: Vector2 = (rec.b-rec.a).normalized().orthogonal()*(float(rec.half)+float(rec.get("sidewalk",0)))
		var a := Vector3(rec.a.x-origin.x,rec.ha+0.5,rec.a.y-origin.y)
		var b := Vector3(rec.b.x-origin.x,rec.hb+0.5,rec.b.y-origin.y)
		var side := Vector3(n.x,0,n.y)
		for sign_v in [-1,1]:
			var pa: Vector3 = a+side*sign_v; var pb: Vector3 = b+side*sign_v
			batch.quad(pa,pb,pb-Vector3.UP*Rail.DECK_DEPTH,pa-Vector3.UP*Rail.DECK_DEPTH,Color("8d9692"))
			batch.tube(pa+Vector3.UP*1.2,pb+Vector3.UP*1.2,0.18,Color("60726c"),4)
		batch.quad(a-side-Vector3.UP,b-side-Vector3.UP,b+side-Vector3.UP,a+side-Vector3.UP,Color("8d9692"))
		# Supports only at deck ends: no column through the rail switchwork.
		for key in [rec.ka,rec.kb]:
			var node: Dictionary = nodes[key]
			if not node.core: continue
			if not node.edges.any(func(e): return not (nodes[segments[e].ka].core and nodes[segments[e].kb].core)): continue
			var base: float = ground.call(node.p)
			for sign_v in [-1,1]:
				var p: Vector2 = node.p+n*sign_v
				batch.box(Vector3(p.x-origin.x,(base+node.h)*0.5,p.y-origin.y),Vector3(1.4,maxf(1,node.h-base),1.4),Color("a5a393"))
	return batch.mesh()
