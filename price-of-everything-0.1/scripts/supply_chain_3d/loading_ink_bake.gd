extends RefCounted
## Offline cartographic strokes. Runtime only binds these meshes and advances ink.
## Bump Snapshot.VERSION when changing this geometry; terrain/art keys stay valid.
const Model := preload("res://scripts/empire_board_model.gd")
const CELL := 24.0
const INTERVAL := 5.5

static func build(builder: RefCounted) -> Dictionary:
	var result := {}
	var roads := {}
	for road in builder.roads:
		if not road.get("tunnel", false):
			(roads.get_or_add(str(road.tile), []) as Array).append(PackedVector2Array([road.a, road.b]))
	for tid in builder.tiles:
		var centre: Vector2 = builder.tiles[tid].center
		var hex := Model.hex_points(centre)
		var layers: Array = [contours(centre, builder.ground.height), [], _joined(roads.get(tid, []))]
		for river in builder.rivers.get(tid, []): layers[1].append(river.points)
		result[tid] = stroke_mesh(layers, hex, centre)
	return result

static func contours(centre: Vector2, height: Callable) -> Array:
	# A world-aligned lattice shares samples and contour levels across hex edges.
	# Join isolines before smoothing, so relief reads as curves rather than hatching.
	var low := Vector2i(((centre-Vector2(294,264))/CELL).floor())
	var high := Vector2i(((centre+Vector2(294,264))/CELL).ceil())
	var heights := {}
	for y in range(low.y, high.y+1):
		for x in range(low.x, high.x+1): heights[Vector2i(x,y)] = float(height.call(Vector2(x,y)*CELL))
	var levels := {}
	for y in range(low.y, high.y):
		for x in range(low.x, high.x):
			var cell := Vector2i(x,y)
			for corners in [[Vector2i.ZERO,Vector2i.RIGHT,Vector2i.ONE],[Vector2i.ZERO,Vector2i.ONE,Vector2i.DOWN]]:
				var points := PackedVector2Array()
				var hs := PackedFloat32Array()
				for offset in corners:
					points.append(Vector2(cell+offset)*CELL); hs.append(heights[cell+offset])
				# Start above the sea datum. No fictitious contours on flat ground/water.
				for band in range(maxi(5,ceili(minf(hs[0],minf(hs[1],hs[2]))/INTERVAL)), floori(maxf(hs[0],maxf(hs[1],hs[2]))/INTERVAL)+1):
					var level := band*INTERVAL
					var cuts := PackedVector2Array()
					for i in 3:
						var j := (i+1)%3
						if (hs[i]<level) != (hs[j]<level): cuts.append(points[i].lerp(points[j], (level-hs[i])/(hs[j]-hs[i])))
					if cuts.size()==2 and cuts[0].distance_squared_to(cuts[1])>0.0001:
						(levels.get_or_add(band, []) as Array).append(cuts)
	var paths: Array = []
	for segments in levels.values():
		for path in _joined(segments): paths.append(_smooth(path))
	return paths

static func _joined(segments: Array) -> Array:
	var nodes := {}; var positions := {}
	for i in segments.size():
		for p in segments[i]:
			var key := Vector2i((p*100.0).round())
			(nodes.get_or_add(key, []) as Array).append(i); positions[key] = p
	var used := {}; var result: Array = []
	# Open lines first; then closed loops. Avoid cutting a long contour into pieces.
	var starts: Array = nodes.keys()
	starts.sort_custom(func(a, b): return nodes[a].size()<nodes[b].size())
	for start in starts:
		var at: Vector2i = start
		var path := PackedVector2Array([positions[at]])
		while true:
			var next := -1
			for edge in nodes[at]:
				if not used.has(edge): next=edge; break
			if next<0: break
			used[next] = true
			var segment: PackedVector2Array = segments[next]
			var end: Vector2 = segment[1] if Vector2i((segment[0]*100.0).round())==at else segment[0]
			path.append(end); at=Vector2i((end*100.0).round())
		if path.size()>1: result.append(path)
	return result

static func _smooth(path: PackedVector2Array) -> PackedVector2Array:
	if path.size()<3: return path
	var closed := path[0].distance_to(path[-1])<0.02
	for pass_index in 2:
		var next := PackedVector2Array()
		if not closed: next.append(path[0])
		for i in range(path.size()-1):
			next.append(path[i].lerp(path[i+1],0.25)); next.append(path[i].lerp(path[i+1],0.75))
		next.append(next[0] if closed else path[-1]); path=next
	return path

static func _simplify(path: PackedVector2Array) -> PackedVector2Array:
	# Subpixel cartographic accuracy at the medium loading view. In particular,
	# don't store four spline subdivisions for every almost-straight contour.
	if path.size()<3: return path
	var keep := {0:true,path.size()-1:true}
	var stack: Array[Vector2i] = [Vector2i(0,path.size()-1)]
	while not stack.is_empty():
		var span := stack.pop_back() as Vector2i
		var furthest := -1; var distance := 0.7*0.7
		for i in range(span.x+1,span.y):
			var closest := Geometry2D.get_closest_point_to_segment(path[i],path[span.x],path[span.y])
			var error := closest.distance_squared_to(path[i])
			if error>distance: distance=error; furthest=i
		if furthest>=0:
			keep[furthest]=true
			stack.append(Vector2i(span.x,furthest)); stack.append(Vector2i(furthest,span.y))
	var result := PackedVector2Array()
	for i in path.size():
		if keep.has(i): result.append(path[i])
	return result

static func stroke_mesh(layers: Array, hex: PackedVector2Array, centre: Vector2) -> ArrayMesh:
	var vertices := PackedVector3Array(); var uvs := PackedVector2Array(); var colors := PackedColorArray()
	for phase in 3:
		var paths: Array = layers[phase]
		for path_index in paths.size():
			for clipped in Geometry2D.intersect_polyline_with_polygon(paths[path_index], hex):
				var path := _simplify(clipped)
				var length := 0.0
				for i in range(path.size()-1): length += path[i].distance_to(path[i+1])
				if length<1.0: continue
				var distance := 0.0
				var delay := fposmod(path_index*0.618,1.0)*0.22
				for i in range(path.size()-1):
					var a: Vector2 = path[i]-centre; var b: Vector2 = path[i+1]-centre
					var span := a.distance_to(b)
					if span<0.001: continue
					var normal: Vector2 = (b-a).orthogonal()/span * [2.0,4.0,3.0][phase]
					var begin := phase+delay+(distance/length)*0.72
					var end := phase+delay+((distance+span)/length)*0.72
					var corners := [a-normal,a+normal,b+normal,b-normal]
					var uv := [Vector2(begin,-1),Vector2(begin,1),Vector2(end,1),Vector2(end,-1)]
					for j in [0,2,1,0,3,2]:
						vertices.append(Vector3(corners[j].x,0.02*phase,corners[j].y))
						uvs.append(uv[j]); colors.append(Color(phase/2.0,0,0))
					distance += span
	var mesh := ArrayMesh.new()
	if vertices.is_empty(): return mesh
	var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_TEX_UV]=uvs; arrays[Mesh.ARRAY_COLOR]=colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh
