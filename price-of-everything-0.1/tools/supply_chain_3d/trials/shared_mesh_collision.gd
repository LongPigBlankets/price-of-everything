@tool
extends ConcavePolygonShape3D
## Experimental only. Shares render geometry on disk but reconstructs native
## collision on load. Measured slower than the prepared production shape.
@export var source_mesh: Mesh:
	set(value):
		source_mesh = value
		set_faces(source_mesh.get_faces() if source_mesh != null else PackedVector3Array())

func _validate_property(property: Dictionary) -> void:
	if property.name == "data": property.usage &= ~PROPERTY_USAGE_STORAGE
