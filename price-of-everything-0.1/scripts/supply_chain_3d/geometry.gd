extends RefCounted
## Small batched meshes in real world coordinates. No camera projection is baked into them.

class Batch:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()

	func triangle(a: Vector3, b: Vector3, c: Vector3, color: Color, normal := Vector3.ZERO) -> void:
		if (b - a).cross(c - a).length_squared() < 0.000001:
			return
		var n: Vector3 = normal if normal != Vector3.ZERO else (b - a).cross(c - a).normalized()
		vertices.append_array(PackedVector3Array([a, c, b]))
		normals.append_array(PackedVector3Array([n, n, n]))
		colors.append_array(PackedColorArray([color, color, color]))

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
		triangle(a, b, c, color)
		triangle(a, c, d, color)

	func tube(a: Vector3, b: Vector3, radius: float, color: Color, sides: int = 6) -> void:
		var axis := b - a
		if axis.length_squared() < 0.001:
			return
		axis = axis.normalized()
		var u := axis.cross(Vector3.UP if absf(axis.y) < 0.95 else Vector3.RIGHT).normalized() * radius
		var v := axis.cross(u)
		for i in sides:
			var aa := TAU * float(i) / float(sides)
			var ab := TAU * float(i + 1) / float(sides)
			var ra := u * cos(aa) + v * sin(aa)
			var rb := u * cos(ab) + v * sin(ab)
			quad(a + ra, a + rb, b + rb, b + ra, color)
			triangle(a, a + rb, a + ra, color)
			triangle(b, b + ra, b + rb, color)

	func box(center: Vector3, size: Vector3, color: Color) -> void:
		var h := size * 0.5
		var p: Array[Vector3] = []
		for y in [-1.0, 1.0]:
			for z in [-1.0, 1.0]:
				for x in [-1.0, 1.0]:
					p.append(center + h * Vector3(x, y, z))
		for face in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
			quad(p[face[0]], p[face[1]], p[face[2]], p[face[3]], color)

	func mesh(uv_rect := Rect2()) -> ArrayMesh:
		var result := ArrayMesh.new()
		if vertices.is_empty():
			return result
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		if uv_rect.has_area():
			uvs.clear()
			for v in vertices: uvs.append((Vector2(v.x, v.z) - uv_rect.position) / uv_rect.size)
		if uvs.size() == vertices.size(): arrays[Mesh.ARRAY_TEX_UV] = uvs
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return result

static func material(unshaded: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.albedo_color = Color(0.58, 0.58, 0.58) if not unshaded else Color.WHITE
	mat.roughness = 0.9
	# Ribbons and the cutaway's underside are visible from every orbit direction.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat

static func instance(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	return node
