extends RefCounted
## Offline Stoneshore crossing engineering; the result is part of transport/scenery bakes.
const Index := preload("res://scripts/supply_chain_3d/road_index.gd")
const Rail := preload("res://scripts/supply_chain_3d/railway.gd")
const Geo := preload("res://scripts/supply_chain_3d/geometry.gd")
const Trial := preload("res://scripts/supply_chain_3d/stoneshore_trial.gd")
const MAX_GRADE := 0.08
const DEPOT_REACH := 600.0
## Only the depot throat itself (its fan of yard tracks) keeps every road off the rails.
const DEPOT_THROAT := 250.0

static func depot_distances(tracks: Array, depots: Array) -> Dictionary:
	var graph := {};var distance := {};var queue: Array=[];var cursor := 0
	for t in tracks:
		var a := Rail._key(t.a);var b := Rail._key(t.b);var length: float=t.a.distance_to(t.b)
		(graph.get_or_add(a,{}) as Dictionary)[b]=length
		(graph.get_or_add(b,{}) as Dictionary)[a]=length
	for key in graph:
		for depot in depots:
			var q: Vector2=(Vector2(key)*.01-depot.pos).rotated(-depot.yaw)
			if Rect2(-145,-47,290,104).has_point(q): distance[key]=0.0;queue.append(key);break
	while cursor<queue.size():
		var key: Vector2i=queue[cursor];cursor+=1
		for other in graph[key]:
			var next: float=distance[key]+graph[key][other]
			if next>=float(distance.get(other,INF)): continue
			distance[other]=next;queue.append(other)
	return distance

static func build(grade: RefCounted, plan: Dictionary, urban: RefCounted, depots: Array) -> void:
	var distances := depot_distances(urban.tracks,depots)
	var track_index := Index.segments(urban.tracks)
	var hits: Array=[]
	var rail_bridges: Array=[]
	for road in grade.segments:
		if not str(road.get("tile","")) in Trial.TILES: continue
		var dir: Vector2=(road.b-road.a).normalized()
		for ri in Index.query(track_index,Index.bounds(road.a,road.b,.01)):
			var track: Dictionary=urban.tracks[ri]
			var hit: Variant=Geometry2D.segment_intersects_segment(road.a,road.b,track.a,track.b)
			if hit==null: continue
			var p: Vector2=hit;var rail_dir: Vector2=(track.b-track.a).normalized()
			var sine := absf(dir.cross(rail_dir))
			if sine<.08: continue
			var fraction: float=track.a.distance_to(p)/maxf(.001,track.a.distance_to(track.b))
			var bed := lerpf(track.ha,track.hb,fraction)
			var hidden: bool=track.hidden_a if fraction<.5 else track.hidden_b
			var depot_distance: float=minf(float(distances.get(Rail._key(track.a),INF))+track.a.distance_to(p),float(distances.get(Rail._key(track.b),INF))+track.b.distance_to(p))
			var nearby := 0;var inside := false
			for junction in plan.junctions:
				var d: float=p.distance_to(junction.p)
				if d<220: nearby+=1
				if d<float(junction.radius)+10: inside=true
			# A mix, as a real town has: two-lane roads cross at level, even through a
			# junction fan; a four-lane road goes under a short rail bridge where the track
			# runs at grade; six-lane roads, wider roads through a junction fan and the depot
			# throat take a road bridge; covered rail stays below.
			var reason := "two-lane road"
			var mode := "level"
			if hidden: mode="tunnel";reason="already covered rail"
			elif inside and int(road.level)>=2: mode="bridge";reason="rail junction movements"
			elif depot_distance<DEPOT_THROAT: mode="bridge";reason="depot throat"
			elif int(road.level)>=3: mode="bridge";reason="six-lane main road"
			elif bed+1.25<float(grade.height_at(p,bed))-2: mode="bridge";reason="recessed rail approach"
			elif int(road.level)==2 and not track.active: mode="rail_bridge";reason="four-lane road under the line"
			elif int(road.level)==2: mode="bridge";reason="four-lane road over engineered rail"
			if mode=="rail_bridge":
				# The railway profile lifts the track over an untagged road on its own concrete
				# deck; the road keeps its grade and joins no group.
				if not rail_bridges.any(func(q): return (q.p as Vector2).distance_to(p)<1.0):
					rail_bridges.append({"p":p,"mode":mode,"reason":reason,"tile":road.tile,"sources":[road.source]})
				continue
			road.rail_crossing_mode=mode
			var duplicate := false
			for c in hits:
				if c.p.distance_to(p)<1.0 and absf(c.dir.dot(dir))>.9:
					if not road.source in c.sources: c.sources.append(road.source)
					duplicate=true;break
			if duplicate: continue
			hits.append({"p":p,"dir":dir,"rail_dir":rail_dir,"bed":bed,"mode":mode,"reason":reason,"tile":road.tile,
				"sources":[road.source],"road_base":minf(grade.nodes[road.ka].base,grade.nodes[road.kb].base),"half":road.half,"span":(Rail.CORRIDOR_WIDTH*.5+6)/sine,
				"depot_distance":depot_distance,"junctions":nearby,"points":[p]})
	# A junction fan or duplicated authored road is one continuous deck. Separate
	# nearby streets remain independent unless their carriageways are collinear.
	var groups: Array=[]
	for hit in hits:
		var joined := false
		for c in groups:
			if c.mode!=hit.mode : continue
			var delta: Vector2=hit.p-c.p
			if absf(c.dir.dot(hit.dir))<.94 or absf(delta.cross(c.dir))>minf(c.half,hit.half)+2 or delta.length()>135: continue
			c.points.append(hit.p);c.bed=maxf(c.bed,hit.bed);c.half=maxf(c.half,hit.half);c.span=maxf(c.span,hit.span)
			for source in hit.sources:
				if not source in c.sources: c.sources.append(source)
			joined=true;break
		if not joined: groups.append(hit.duplicate(true))
	# A quiet line can still be too close to another bridge: the road and rail
	# cannot separate by the required clearance within their available ramps.
	for c in groups:
		if c.mode!="level":continue
		for bridge in groups:
			if bridge.mode!="bridge" or c.p.distance_to(bridge.p)>250:continue
			var road_run := network_distance(grade.segments,c.p,bridge.p)
			var rail_run := network_distance(urban.tracks,c.p,bridge.p)
			var rail_core: float=(c.half+2)/maxf(.08,absf(c.dir.cross(c.rail_dir)))+4
			var separation := MAX_GRADE*maxf(0,road_run-c.span-bridge.span)+.10*maxf(0,rail_run-rail_core)
			if separation<Rail.CLEARANCE+Rail.DECK_DEPTH+1.25-.13:
				c.mode="bridge";c.reason="insufficient ramp distance beside another bridge"
				c.level_candidate={"road_distance":road_run,"rail_distance":rail_run,"available_separation":separation}
				break
	# Establish bridge approaches before fitting the quiet crossing to their
	# shared road grade. This avoids lifting a sloping rail into a nearby deck.
	groups.sort_custom(func(a,b): return {"bridge":0,"level":1,"tunnel":2}[a.mode]<{"bridge":0,"level":1,"tunnel":2}[b.mode])
	grade.crossings=groups+rail_bridges
	for c in groups:
		if c.mode=="tunnel": continue
		if c.mode=="level":
			grade.refresh()
			c.bed=maxf(minf(c.bed,c.road_base+1.2),grade.height_at(c.p,c.road_base)-.13)
			level_rail(urban,c)
		var first: Vector2=c.p;var low := 0.0;var high := 0.0
		for p in c.points:
			var along: float=(p-first).dot(c.dir);low=minf(low,along);high=maxf(high,along)
		c.p=first+c.dir*(low+high)*.5;c.length=high-low+2*c.span
		var start: Vector2=first+c.dir*(low-c.span);var end: Vector2=first+c.dir*(high+c.span)
		var seeds := {}
		for road in grade.segments:
			if not c.sources.any(func(source):return source==road.get("source","")): continue
			for key in [road.ka,road.kb]:
				var node: Dictionary=grade.nodes[key]
				if node.p.distance_to(Geometry2D.get_closest_point_to_segment(node.p,start,end))<=float(c.half)+3.0:
					seeds[key]=0.0
		if seeds.is_empty(): continue
		c.deck=c.bed+(1.25+Rail.CLEARANCE+Rail.DECK_DEPTH if c.mode=="bridge" else .13)
		c.ramp_length=0.0;c.core_nodes=seeds.size()
		# Road graph propagation shares elevations at every T-junction. A linear
		# 8% approach also reaches across tile boundaries instead of making humps.
		var queue: Array=seeds.keys();var cursor := 0
		while cursor<queue.size():
			var key: Vector2i=queue[cursor];cursor+=1
			var node: Dictionary=grade.nodes[key];var distance: float=seeds[key]
			var target: float=c.deck-MAX_GRADE*distance
			if distance>0 and target<=node.base: continue
			node.h=maxf(node.h,target)
			if distance==0 and c.mode=="bridge": node.core=true
			c.ramp_length=maxf(c.ramp_length,distance)
			for edge in node.edges:
				var road: Dictionary=grade.segments[edge]
				var other: Vector2i=road.kb if road.ka==key else road.ka
				var next: float=distance+node.p.distance_to(grade.nodes[other].p)
				if next<float(seeds.get(other,INF))-.0001: seeds[other]=next;queue.append(other)
		if c.mode=="bridge": grade.bridges.append(c)
	ease_joins(grade)
	grade.refresh()
	# Paired rails and sleepers can intersect the road beside its centerline.
	# Tag the entire crossing envelope, not just the one intersected sample.
	for c in groups:
		for road in grade.segments:
			if c.sources.has(road.get("source","")) and Geometry2D.get_closest_point_to_segment(c.p,road.a,road.b).distance_to(c.p)<float(c.get("length",c.span*2))*.5+8:
				road.rail_crossing_mode=c.mode

static func ease_joins(grade: RefCounted) -> void:
	# A linear ramp can meet a steeper pre-existing hillside road. Continue
	# grading through that join, including side streets, rather than ending
	# the ramp with one abrupt segment. Only propagate from modified nodes.
	var queue: Array=[];var cursor := 0
	for key in grade.nodes:
		if grade.nodes[key].h>grade.nodes[key].base+.001:queue.append(key)
	while cursor<queue.size():
		var key: Vector2i=queue[cursor];cursor+=1
		var node: Dictionary=grade.nodes[key]
		for edge in node.edges:
			var segment: Dictionary=grade.segments[edge]
			var other: Vector2i=segment.kb if segment.ka==key else segment.ka
			var neighbour: Dictionary=grade.nodes[other]
			var rise: float=node.p.distance_to(neighbour.p)*MAX_GRADE
			if node.h>neighbour.h+rise+.0001:
				neighbour.h=node.h-rise;queue.append(other)
			elif neighbour.h>node.h+rise+.0001:
				node.h=neighbour.h-rise;queue.append(key)

static func network_distance(segments: Array, from: Vector2, to: Vector2) -> float:
	var graph := {};var start := Vector2i.ZERO;var end := Vector2i.ZERO
	var first := INF;var last := INF
	for segment in segments:
		var a := Rail._key(segment.a);var b := Rail._key(segment.b)
		var length: float=segment.a.distance_to(segment.b)
		(graph.get_or_add(a,{}) as Dictionary)[b]=length
		(graph.get_or_add(b,{}) as Dictionary)[a]=length
		for pair in [[a,segment.a],[b,segment.b]]:
			var d: float=pair[1].distance_to(from)
			if d<first:first=d;start=pair[0]
			d=pair[1].distance_to(to)
			if d<last:last=d;end=pair[0]
	var distances := {start:0.0};var queue: Array=[start];var cursor := 0
	while cursor<queue.size():
		var key: Vector2i=queue[cursor];cursor+=1
		for other in graph.get(key,{}):
			var next: float=distances[key]+graph[key][other]
			if next<float(distances.get(other,INF))-.001:distances[other]=next;queue.append(other)
	return float(distances.get(end,INF))

static func level_rail(urban: RefCounted, crossing: Dictionary) -> void:
	# The crossing itself must be level across both tracks, even where the old
	# railway followed an abrupt terrain ramp. Shared graph nodes also keep
	# approaching turnout movements continuous. Buried datums remain immutable.
	var nodes := {};var distance := {};var queue: Array=[];var cursor := 0
	var sine: float=absf(crossing.dir.cross(crossing.rail_dir))
	var core: float=(crossing.half+2)/maxf(.08,sine)+4
	for track in urban.tracks:
		var a := Rail._key(track.a);var b := Rail._key(track.b)
		for pair in [[a,track.a,track.ha,track.hidden_a],[b,track.b,track.hb,track.hidden_b]]:
			if not nodes.has(pair[0]):nodes[pair[0]]={"p":pair[1],"h":pair[2],"hidden":pair[3],"edges":{}}
		var length: float=track.a.distance_to(track.b)
		nodes[a].edges[b]=length;nodes[b].edges[a]=length
	for key in nodes:
		var node: Dictionary=nodes[key];var delta: Vector2=node.p-crossing.p
		if not node.hidden and absf(delta.dot(crossing.rail_dir))<=core and absf(delta.cross(crossing.rail_dir))<3:
			distance[key]=0.0;queue.append(key)
	while cursor<queue.size():
		var key: Vector2i=queue[cursor];cursor+=1
		var node: Dictionary=nodes[key];var d: float=distance[key]
		if node.hidden:continue
		var target := clampf(node.h,crossing.bed-.10*d,crossing.bed+.10*d)
		if d>0 and absf(target-node.h)<.001:continue
		node.h=target
		for other in node.edges:
			var next: float=d+node.edges[other]
			if next<float(distance.get(other,INF))-.001:distance[other]=next;queue.append(other)
	for track in urban.tracks:
		var a: Dictionary=nodes[Rail._key(track.a)];var b: Dictionary=nodes[Rail._key(track.b)]
		if absf(a.h-track.ha)>.001 or absf(b.h-track.hb)>.001:
			track.ha=a.h;track.hb=b.h;track.active=true

static func level_mesh(crossings: Array, origin: Vector2, height: Callable) -> ArrayMesh:
	var batch := Geo.Batch.new()
	for c in crossings:
		if c.mode!="level": continue
		var dir: Vector2=c.dir;var n := dir.orthogonal()
		var at := func(along: float, across: float, lift: float) -> Vector3:
			var p: Vector2=c.p+dir*along+n*across
			return Vector3(p.x-origin.x,float(height.call(p))+lift,p.y-origin.y)
		# Crossing deck fills between the rail heads; dark flangeways stay visible.
		var reach: float=c.length*.5-3
		batch.quad(at.call(-reach,-c.half,1.10),at.call(reach,-c.half,1.10),at.call(reach,c.half,1.10),at.call(-reach,c.half,1.10),Color("92968d"))
		for side in [-1,1]:
			var distance: float=(reach+5)*side
			batch.quad(at.call(distance-.35,-c.half+.3,1.15),at.call(distance+.35,-c.half+.3,1.15),at.call(distance+.35,c.half-.3,1.15),at.call(distance-.35,c.half-.3,1.15),Color("d3cdb8"))
			var foot: Vector3=at.call(distance,side*(c.half+1.4),1.0)
			batch.tube(foot,foot+Vector3.UP*5,.17,Color("c8c7b9"),5)
			var axis := Vector3(n.x,0,n.y)
			for slope in [-1,1]:batch.tube(foot+Vector3.UP*(4.1-.7*slope)-axis,foot+Vector3.UP*(4.1+.7*slope)+axis,.14,Color("e1d9c1"),4)
			batch.box(foot+Vector3.UP*2.2,Vector3(.65,1.0,.65),Color("615d5d"))
			# Raised barriers keep the static road open; no traffic simulation added.
			for part in 5: batch.tube(foot+Vector3.UP*(1.0+part*.8),foot+Vector3.UP*(1.8+part*.8),.24,Color("b5695d") if part%2==0 else Color("e0d8bd"),4)
	return batch.mesh()
