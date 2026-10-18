extends RefCounted
## Two rendered intermediate states. Never capture/copy the viewport or bake new art.
const INTERMEDIATE_FRAMES := 2
const SHADERS := ["ground.gdshader", "road_drawing.gdshader", "far_sprite.gdshader", "building_print.gdshader", "building_glass.gdshader", "contour.gdshader", "water_glints.gdshader"]
var blend := 0.0
var target := 0.0
var active := false
var _from := 0.0
var _frame := 0
var _bindings: Array = []
var _materials: Dictionary = {}

func reset(value: float) -> void:
	clear()
	blend = value
	target = value

func clear() -> void:
	for record in _bindings:
		if not is_instance_valid(record.node): continue
		if record.has("surfaces"):
			for i in record.surfaces.size(): record.node.set_surface_override_material(i, record.surfaces[i])
		else: record.node.material_override = record.original
	_bindings.clear()
	_materials.clear()
	active = false

func begin(value: float, local: Array, far: Array) -> void:
	clear()
	target = value
	_from = blend
	if is_equal_approx(blend, target): return
	active = true
	_frame = 1
	var seen := {}
	for group in [{"nodes": local, "side": 1}, {"nodes": far, "side": -1}]:
		for node in group.nodes:
			if not is_instance_valid(node) or seen.has(node.get_instance_id()): continue
			seen[node.get_instance_id()] = true
			if node is MeshInstance3D and node.material_override == null and node.mesh != null:
				# Surface by surface: a building's glass keeps its own (transparent) paint.
				var surfaces: Array = []
				var bound := false
				for i in node.mesh.get_surface_count():
					surfaces.append(node.get_surface_override_material(i))
					var paint: Material = surfaces[i] if surfaces[i] != null else node.mesh.surface_get_material(i)
					var blended := _blended(paint, group.side)
					if blended != null:
						node.set_surface_override_material(i, blended)
						bound = true
				if bound: _bindings.append({"node": node, "surfaces": surfaces})
				continue
			var original: Material = node.material_override
			var source: Material = original
			if source == null:
				var mesh: Mesh = node.mesh if node is MeshInstance3D else (node.multimesh.mesh if node is MultiMeshInstance3D else null)
				if mesh != null and mesh.get_surface_count() > 0: source = mesh.surface_get_material(0)
			var blended := _blended(source, group.side)
			if blended == null: continue
			_bindings.append({"node": node, "original": original})
			node.material_override = blended
	_update_blend()

## A copy of `source` drawn on one side of the fade, shared by every node that uses it.
func _blended(source: Material, side: int) -> ShaderMaterial:
	if not source is ShaderMaterial or source.shader == null or not source.shader.resource_path.get_file() in SHADERS: return null
	var key := "%s:%s" % [source.get_instance_id(), side]
	if not _materials.has(key):
		var material := source.duplicate() as ShaderMaterial
		material.set_shader_parameter("lod_side", side)
		_materials[key] = material
	return _materials[key]

func advance() -> void:
	if not active: return
	_frame += 1
	if _frame > INTERMEDIATE_FRAMES:
		blend = target
		clear()
	else:
		_update_blend()

func _update_blend() -> void:
	blend = lerpf(_from, target, float(_frame) / (INTERMEDIATE_FRAMES + 1))
	for material in _materials.values(): material.set_shader_parameter("lod_blend", blend)
