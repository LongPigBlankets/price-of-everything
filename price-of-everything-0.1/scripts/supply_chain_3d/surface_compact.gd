extends RefCounted
## Offline/render-bake optimisation. Preserve every non-flat triangle and all
## boundary positions/normals; replace only connected horizontal interiors.
const VERSION := 2
const CHUNK := 96.0
const HEIGHT_EPS := 0.0001

static func build(source: ArrayMesh, flatten: bool = true) -> ArrayMesh:
	if source == null or source.get_surface_count() == 0: return source
	var result := ArrayMesh.new()
	for surface in source.get_surface_count():
		var tool := SurfaceTool.new()
		tool.create_from(source,surface)
		tool.index()
		var a := tool.commit_to_arrays()
		var points: PackedVector3Array=a[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array=a[Mesh.ARRAY_NORMAL]
		var colors: PackedColorArray=a[Mesh.ARRAY_COLOR]
		var indices: PackedInt32Array=a[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for i in points.size(): indices.append(i)
		var kept := PackedInt32Array()
		var groups := {}
		for t in range(0,indices.size(),3):
			var ids := PackedInt32Array([indices[t],indices[t+1],indices[t+2]])
			var p: Vector3=points[ids[0]]
			if _sliver(p,points[ids[1]],points[ids[2]]): continue
			var flat := flatten and normals.size()==points.size()
			for id in ids:
				flat=flat and absf(points[id].y-p.y)<HEIGHT_EPS and normals[id].dot(Vector3.UP)>0.999999
				flat=flat and (colors.is_empty() or colors[id].is_equal_approx(Color.WHITE))
			if not flat:
				kept.append_array(ids); continue
			var center: Vector3=(p+points[ids[1]]+points[ids[2]])/3.0
			var key := Vector3i(floori(center.x/CHUNK),roundi(p.y*256.0),floori(center.z/CHUNK))
			(groups.get_or_add(key,[]) as Array).append(ids)
		for triangles in groups.values(): kept.append_array(_patch(triangles,points))
		if kept.is_empty(): continue
		var arrays := _used_arrays(a,kept)
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		result.surface_set_material(result.get_surface_count()-1,source.surface_get_material(surface))
	return result

static func _patch(triangles: Array, points: PackedVector3Array) -> PackedInt32Array:
	var original := PackedInt32Array()
	var edges := {}
	var reference_area := 0.0
	for tri in triangles:
		original.append_array(tri)
		reference_area+=_area(points[tri[0]],points[tri[1]],points[tri[2]])
		for i in 3:
			var a: int=tri[i]; var b: int=tri[(i+1)%3]
			var key := Vector2i(mini(a,b),maxi(a,b))
			if edges.has(key): edges[key].count+=1
			else: edges[key]={"a":a,"b":b,"count":1}
	if triangles.size()<8: return original
	var next := {}
	var incoming := {}
	for edge in edges.values():
		if edge.count>2: return original
		if edge.count!=1: continue
		if next.has(edge.a) or incoming.has(edge.b): return original
		next[edge.a]=edge.b; incoming[edge.b]=true
	var visited := {}
	var replacement := PackedInt32Array()
	var replacement_area := 0.0
	for start in next:
		if visited.has(start): continue
		var ring := PackedInt32Array()
		var polygon := PackedVector2Array()
		var at: int=start
		var origin: Vector3=points[start]
		while not visited.has(at):
			if not next.has(at): return original
			visited[at]=true; ring.append(at)
			polygon.append(Vector2(points[at].x-origin.x,points[at].z-origin.z))
			at=next[at]
		if at!=start or ring.size()<3: return original
		var ring_area := 0.0
		for i in polygon.size(): ring_area+=polygon[i].cross(polygon[(i+1)%polygon.size()])
		# A hole needs constrained triangulation. Retain this small chunk intact;
		# never bridge across a mine, water opening or engineered road cutting.
		if ring_area*reference_area<=0.0: return original
		var ids := Geometry2D.triangulate_polygon(polygon)
		if ids.is_empty(): return original
		for i in range(0,ids.size(),3):
			var a: int=ring[ids[i]]; var b: int=ring[ids[i+1]]; var c: int=ring[ids[i+2]]
			var area := _area(points[a],points[b],points[c])
			if _sliver(points[a],points[b],points[c]): continue
			if area*reference_area<0.0:
				var swap := b; b=c; c=swap; area=-area
			replacement_area+=area
			replacement.append_array(PackedInt32Array([a,b,c]))
	if absf(reference_area-replacement_area)>maxf(0.001,absf(reference_area)*0.00001): return original
	return replacement if replacement.size()<original.size() else original

static func _area(a: Vector3,b: Vector3,c: Vector3) -> float:
	return Vector2(b.x-a.x,b.z-a.z).cross(Vector2(c.x-a.x,c.z-a.z))

static func _used_arrays(source: Array, indices: PackedInt32Array) -> Array:
	var order := PackedInt32Array()
	var remap := {}
	var compact := PackedInt32Array()
	for id in indices:
		if not remap.has(id): remap[id]=order.size(); order.append(id)
		compact.append(remap[id])
	var result: Array=[]; result.resize(Mesh.ARRAY_MAX)
	for field in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_COLOR,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2]:
		if source[field]==null: continue
		var values: Variant=source[field].slice(0,0)
		for id in order: values.append(source[field][id])
		result[field]=values
	result[Mesh.ARRAY_INDEX]=compact
	return result

static func joined(meshes: Array, uv_rect := Rect2()) -> ArrayMesh:
	# Keep shared vertices when combining already compact terrain chunks.
	var points:=PackedVector3Array();var normals:=PackedVector3Array()
	var colors:=PackedColorArray();var uvs:=PackedVector2Array();var ids:=PackedInt32Array()
	for mesh in meshes:
		if mesh==null:continue
		for surface in mesh.get_surface_count():
			var a:Array=mesh.surface_get_arrays(surface)
			var offset:=points.size()
			points.append_array(a[Mesh.ARRAY_VERTEX]);normals.append_array(a[Mesh.ARRAY_NORMAL]);colors.append_array(a[Mesh.ARRAY_COLOR])
			if a[Mesh.ARRAY_TEX_UV]!=null:uvs.append_array(a[Mesh.ARRAY_TEX_UV])
			if a[Mesh.ARRAY_INDEX]!=null and not a[Mesh.ARRAY_INDEX].is_empty():
				for i in a[Mesh.ARRAY_INDEX]:ids.append(offset+i)
			else:
				for i in a[Mesh.ARRAY_VERTEX].size():ids.append(offset+i)
	var result:=ArrayMesh.new()
	if points.is_empty():return result
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=points;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_COLOR]=colors;arrays[Mesh.ARRAY_INDEX]=ids
	if uv_rect.has_area():
		uvs.clear()
		for p in points:uvs.append((Vector2(p.x,p.z)-uv_rect.position)/uv_rect.size)
	if uvs.size()==points.size():arrays[Mesh.ARRAY_TEX_UV]=uvs
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return result

static func without_slivers(source: ArrayMesh) -> ArrayMesh:
	# Upgrade v1 bakes without repainting roads or retriangulating their terrain.
	# Reject sub-millimetre triangles at numerically collinear cut boundaries.
	if source==null or source.get_surface_count()==0:return source
	var result:=ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays:=source.surface_get_arrays(surface)
		var points:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var ids:PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		if ids.is_empty():
			for i in points.size():ids.append(i)
		var kept:=PackedInt32Array()
		for i in range(0,ids.size(),3):
			if _sliver(points[ids[i]],points[ids[i+1]],points[ids[i+2]]):continue
			kept.append_array(ids.slice(i,i+3))
		if kept.is_empty():continue
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,_used_arrays(arrays,kept))
		result.surface_set_material(result.get_surface_count()-1,source.surface_get_material(surface))
	return result

static func _sliver(a: Vector3,b: Vector3,c: Vector3) -> bool:
	var longest := maxf((b-a).length_squared(),maxf((c-a).length_squared(),(c-b).length_squared()))
	return (b-a).cross(c-a).length_squared()<=maxf(0.000001,longest*0.000001)
