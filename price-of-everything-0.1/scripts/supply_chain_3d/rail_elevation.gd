extends RefCounted
## Offline engineering on the sampled railway graph. A covered component has
## one absolute datum; the approach is measured along rail, across tile borders.
const Rail := preload("res://scripts/supply_chain_3d/railway.gd")
const DEPTH := 14.0
const APPROACH := 180.0
const MAX_APPROACH_GRADE := 0.12

static func solve(plan: Dictionary, height: Callable, level: Callable, requested: Callable, yard_distance: Callable, stations: Array = [], required_cover: Callable = Callable()) -> Dictionary:
	var nodes := {}; var profiles: Array = []; var junctions := {}
	for corridor in plan.corridors:
		var samples: Array = []
		for i in corridor.points.size():
			var p: Vector2 = corridor.points[i]
			var side: Vector2 = (corridor.points[mini(i+1,corridor.points.size()-1)]-corridor.points[maxi(0,i-1)]).normalized().orthogonal()*(Rail.CORRIDOR_WIDTH*0.5+1.8)
			var hidden: bool = requested.call(p) or maxf(float(level.call(p)),maxf(float(level.call(p-side)),float(level.call(p+side))))>=Rail.TUNNEL_LEVEL
			var mandatory: bool=required_cover.is_valid() and bool(required_cover.call(p))
			hidden = (hidden and float(yard_distance.call(p))>=APPROACH) or mandatory
			var base := float(height.call(p))+1.2
			var roof := minf(float(height.call(p)),minf(float(height.call(p-side)),float(height.call(p+side))))
			samples.append({"p":p,"hidden":hidden})
			var key := Rail._key(p)
			var node: Dictionary = nodes.get_or_add(key,{"p":p,"base":base,"h":base,"roof":roof,"hidden":false,"mandatory":false,"edges":{}})
			node.roof=minf(node.roof,roof)
			node.mandatory=node.mandatory or mandatory
			if i>0:
				var previous := Rail._key(corridor.points[i-1])
				if previous!=key:
					node.edges[previous]=p.distance_to(nodes[previous].p)
					nodes[previous].edges[key]=node.edges[previous]
		profiles.append({"samples":samples})
		if corridor.has("junction") and samples.any(func(s): return s.hidden): junctions[corridor.junction]=true
	for i in plan.corridors.size():
		if junctions.has(plan.corridors[i].get("junction",null)):
			for sample in profiles[i].samples: sample.hidden=true
	Rail._merge_tunnel_daylight(profiles)
	for prof in profiles:
		for sample in prof.samples: nodes[Rail._key(sample.p)].hidden=sample.hidden
	var seen := {}; var components: Array = []
	for first in nodes:
		if not nodes[first].hidden or seen.has(first): continue
		var queue: Array = [first]; var cursor := 0; var datum := INF
		seen[first]=true
		while cursor<queue.size():
			var key: Vector2i=queue[cursor]; cursor+=1
			datum=minf(datum,float(nodes[key].roof)+1.2-DEPTH)
			for other in nodes[key].edges:
				if nodes[other].hidden and not seen.has(other): seen[other]=true; queue.append(other)
		components.append({"nodes":queue,"datum":datum,"mandatory":queue.any(func(key):return nodes[key].mandatory)})
	# Minimum-distance relaxation; only preprocessing, never on a cache hit.
	for component in components:
		var distance := {}; var queue: Array = component.nodes.duplicate(); var cursor := 0
		for key in queue: distance[key]=0.0
		while cursor<queue.size():
			var key: Vector2i=queue[cursor]; cursor+=1
			var node: Dictionary=nodes[key]
			var drop := maxf(0.0,float(node.base)-float(component.datum))
			var reach := maxf(APPROACH,1.5*drop/MAX_APPROACH_GRADE)
			if float(distance[key])>reach: continue
			var target := lerpf(component.datum,node.base,smoothstep(0.0,reach,float(distance[key])))
			# A compulsory roof already overrode depot proximity. Applying the
			# old XY yard blend only outside its mouth would create a height step.
			# Use distance along the connected track for these approaches instead.
			var yard_weight := 1.0 if component.mandatory else smoothstep(0.0,APPROACH,float(yard_distance.call(node.p)))
			node.h=minf(node.h,lerpf(node.base,target,yard_weight))
			for other in node.edges:
				var d := float(distance[key])+float(node.edges[other])
				if d<float(distance.get(other,INF))-0.0001: distance[other]=d; queue.append(other)
	# Overlapping approaches must never deform a neighbouring covered datum.
	for component in components:
		for key in component.nodes: nodes[key].h=component.datum
	# A terminus in an open cutting needs level platforms. Extend the nearby
	# bore datum along its short surfaced tail, while leaving the roof open.
	for station in stations:
		var platform_nodes: Array=[];var datum := INF
		for node in nodes.values():
			if preload("res://scripts/supply_chain_3d/rail_station.gd").contains_track(station,node.p):
				platform_nodes.append(node);datum=minf(datum,node.h)
		for node in platform_nodes: node.h=datum
	var tracks: Array = []
	for prof in profiles:
		for i in range(1,prof.samples.size()):
			var a: Dictionary=nodes[Rail._key(prof.samples[i-1].p)]
			var b: Dictionary=nodes[Rail._key(prof.samples[i].p)]
			tracks.append({"a":a.p,"b":b.p,"ha":a.h,"hb":b.h,"base_a":a.base,"base_b":b.base,
				"hidden_a":a.hidden,"hidden_b":b.hidden,"hidden":a.hidden and b.hidden,
				"active":a.hidden or b.hidden or a.h<a.base-0.001 or b.h<b.base-0.001})
	return {"tracks":tracks,"components":components.map(func(c): return {"datum":c.datum,"samples":c.nodes.size()})}
