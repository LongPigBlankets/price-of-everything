extends RefCounted
## Offline, reusable sprites, scaled in world units exactly like the original models.
## No mesh load, collider construction, or live render is needed to create a card.
const DIRECTORY := "res://assets/supply_chain_3d/far_sprites/"
const MEDIUM_DIRECTORY := "res://assets/supply_chain_3d/medium_sprites/"
static var _medium_manifest: Dictionary = {}
const ShaderSource := preload("res://scripts/supply_chain_3d/far_sprite.gdshader")
static var _manifest: Dictionary = {}
static var _meshes: Dictionary = {}
static var _materials: Dictionary = {}
static var _foliage_softness := 0.0

static func set_overview_scale(ppu: float, whole_continent: bool) -> void:
	# Fade the trees' dark ink towards a muted leaf tone at continent scale.
	# Recover the original colour before the mesh handover, with no density pop.
	# Outgoing medium cards share this softness during the two-frame zoom-out.
	var softness := 0.55 * (1.0 - smoothstep(0.10, 0.27, ppu)) if whole_continent else 0.0
	if is_equal_approx(softness, _foliage_softness): return
	_foliage_softness = softness
	for key in _materials:
		if str(key).trim_prefix("medium:").begins_with("tree_"):
			_materials[key].set_shader_parameter("foliage_softness", softness)

static func entry(key: String, tier: int = 0) -> Dictionary:
	if tier == 1:
		if _medium_manifest.is_empty():
			var medium_path := MEDIUM_DIRECTORY + "manifest.json"
			if FileAccess.file_exists(medium_path):
				_medium_manifest = JSON.parse_string(FileAccess.get_file_as_string(medium_path)).get("assets", {})
		return _medium_manifest.get(key, {})
	if _manifest.is_empty():
		var path := DIRECTORY + "manifest.json"
		if not FileAccess.file_exists(path): return {}
		_manifest = JSON.parse_string(FileAccess.get_file_as_string(path)).get("assets", {})
	return _manifest.get(key, {})

static func center(key: String) -> Vector3:
	var xyz: Array = entry(key).get("center", [0.0, 0.0, 0.0])
	return Vector3(xyz[0], xyz[1], xyz[2])

static func mesh_for(key: String) -> Mesh:
	var data := entry(key)
	if data.is_empty(): return null
	if not _meshes.has(key):
		var mesh := QuadMesh.new()
		mesh.size = Vector2.ONE * float(data.span)
		# A camera-facing card needs a spherical culling bound, including when
		# viewed edge-on to the authored XY plane.
		mesh.custom_aabb = AABB(Vector3.ONE * -float(data.span) * 0.5, Vector3.ONE * float(data.span))
		_meshes[key] = mesh
	return _meshes[key]

static func material_for(key: String, tier: int = 0, lit: bool = false) -> ShaderMaterial:
	var cache_key := ("medium:" if tier == 1 else "") + key + (":lit" if lit else "")
	var directory := MEDIUM_DIRECTORY if tier == 1 else DIRECTORY
	if not _materials.has(cache_key):
		var material := ShaderMaterial.new()
		material.shader = ShaderSource
		var artwork := str(entry(key, tier).get("lit_texture", key + ".png")) if lit else key + ".png"
		material.set_shader_parameter("artwork", load(directory + artwork))
		material.set_shader_parameter("depth_art", load(directory + key + "_depth.png"))
		material.set_shader_parameter("span", float(entry(key).span))
		var data := entry(key, tier)
		material.set_shader_parameter("atlas_grid", Vector2(data.get("yaws", 16), data.get("pitches", 5)))
		material.set_shader_parameter("foliage_softness", _foliage_softness if key.begins_with("tree_") else 0.0)
		_materials[cache_key] = material
	return _materials[cache_key]

static func instance(key: String, grade: Vector2, tier: int = 0, lit: bool = false) -> MeshInstance3D:
	if tier == 1 and entry(key, 1).is_empty(): return null
	var mesh := mesh_for(key)
	if mesh == null: return null
	var node := MeshInstance3D.new()
	node.name = "MediumSprite" if tier == 1 else "FarSprite"
	node.mesh = mesh
	node.material_override = material_for(key, tier, lit)
	node.material_override.set_shader_parameter("grade_range", grade)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

static func grove(key: String, transforms: Array, grade: Vector2, tier: int = 0) -> MultiMeshInstance3D:
	if tier == 1 and entry(key, 1).is_empty(): return null
	var mesh := mesh_for(key)
	if mesh == null or transforms.is_empty(): return null
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in transforms.size(): multi.set_instance_transform(i, transforms[i])
	var node := MultiMeshInstance3D.new()
	node.name = "FarTrees_" + key
	node.multimesh = multi
	node.material_override = material_for(key, tier)
	node.material_override.set_shader_parameter("grade_range", grade)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node
