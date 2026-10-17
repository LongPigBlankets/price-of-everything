@tool
extends ConcavePolygonShape3D
## Experimental only. Direct expansion avoids Mesh.get_faces() acceleration work,
## but does not reproduce its position snapping. Never used by production bakes.
@export var source_mesh: Mesh:
	set(value):
		source_mesh=value
		var faces := PackedVector3Array()
		if source_mesh != null:
			for surface in source_mesh.get_surface_count():
				var arrays := source_mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				if indices.is_empty():
					faces.append_array(vertices)
				else:
					var offset := faces.size()
					faces.resize(offset + indices.size())
					for i in indices.size(): faces[offset+i] = vertices[indices[i]]
		set_faces(faces)

func _validate_property(property: Dictionary) -> void:
	if property.name=="data": property.usage &= ~PROPERTY_USAGE_STORAGE
