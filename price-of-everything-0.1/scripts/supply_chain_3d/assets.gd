extends RefCounted
## Only the supply-chain renderer uses these meshes. Existing sprite/map assets are untouched.
const DIRECTORY := "res://assets/supply_chain_3d/"
const PrintShader := preload("res://scripts/supply_chain_3d/building_print.gdshader")
const ContourShader := preload("res://scripts/supply_chain_3d/contour.gdshader")
static var _print: ShaderMaterial
static var _contour: ShaderMaterial
static var _contours: Dictionary = {}
static var _trees: Dictionary = {}
static var _lit: Dictionary = {}
static var _meshes: Dictionary = {}
static var _manifest: Dictionary = {}

static func key_for(name: String, level: int) -> String:
	if _manifest.is_empty():
		_manifest = JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY + "manifest.json"))
	var family := "mine_flush" if name == "mine" else name
	for lv in range(clampi(level, 1, 3), 0, -1):
		var key := "%s_lvl%d" % [family, lv]
		if _manifest.has(key):
			return key
	return ""

static func mesh_for(key: String) -> Mesh:
	if key == "":
		return null
	if not _meshes.has(key):
		var scene := load(DIRECTORY + key + ".glb") as PackedScene
		if scene == null:
			return null
		var root := scene.instantiate()
		var nodes := root.find_children("*", "MeshInstance3D", true, false)
		if root is MeshInstance3D:
			nodes.push_front(root)
		_meshes[key] = (nodes[0] as MeshInstance3D).mesh if not nodes.is_empty() else null
		root.free()
		if _meshes[key] != null:
			if _print == null:
				_print = ShaderMaterial.new()
				_print.shader = PrintShader
			for surface in _meshes[key].get_surface_count():
				_meshes[key].surface_set_material(surface, _print)
	return _meshes[key]

static func dimensions(key: String) -> Vector3:
	var data: Dictionary = _manifest.get(key, {})
	return Vector3(float(data.get("width", 1.0)), float(data.get("height", 0.65)), float(data.get("depth", 1.0)))

static func contour_for(key: String) -> Mesh:
	if key == "" or not bool(_manifest.get(key, {}).get("contour", false)): return null
	if _contour == null:
		_contour = ShaderMaterial.new()
		_contour.shader = ContourShader
	if not _contours.has(key):
		var scene := load(DIRECTORY + key + "_contour.glb") as PackedScene
		var root := scene.instantiate()
		var nodes := root.find_children("*", "MeshInstance3D", true, false)
		if root is MeshInstance3D: nodes.push_front(root)
		var mesh: Mesh = nodes[0].mesh if not nodes.is_empty() else null
		root.free()
		if mesh != null:
			for i in mesh.get_surface_count(): mesh.surface_set_material(i, _contour)
		_contours[key] = mesh
	return _contours[key]

static func projected_height(key: String) -> float:
	return float(_manifest.get(key, {}).get("projected_height", 1.0))

static func tree_material(fir: bool) -> ShaderMaterial:
	if not _trees.has(fir):
		var material := _print.duplicate() as ShaderMaterial
		# Calibrated against matching source-board tree crops: preserve its muted
		# foliage instead of the saturated greens from the general colour curve.
		material.set_shader_parameter("foliage_tint", Vector3(0.81, 0.74, 0.83) if fir else Vector3(0.835, 0.735, 0.865))
		_trees[fir] = material
	return _trees[fir]

static func pit_for(level: int) -> Dictionary:
	var key := key_for("mine", level)
	return _manifest.get(key, {}).get("pit", {})

static func set_grade(value: Vector2) -> void:
	if _print == null:
		_print = ShaderMaterial.new()
		_print.shader = PrintShader
	_print.set_shader_parameter("grade_range", value)
	if _contour == null:
		_contour = ShaderMaterial.new()
		_contour.shader = ContourShader
	_contour.set_shader_parameter("grade_range", value)
	for material in _lit.values(): material.set_shader_parameter("grade_range", value)
	for material in _trees.values(): material.set_shader_parameter("grade_range", value)

static func set_detail(tier: int) -> void:
	if _print != null: _print.set_shader_parameter("detail_level", tier)
	for material in _lit.values(): material.set_shader_parameter("detail_level", tier)
	for material in _trees.values(): material.set_shader_parameter("detail_level", tier)

static func lit_material(curtain_wall: bool = false) -> ShaderMaterial:
	if not _lit.has(curtain_wall):
		var material := _print.duplicate() as ShaderMaterial
		material.set_shader_parameter("lit_windows", true)
		material.set_shader_parameter("curtain_wall", curtain_wall)
		_lit[curtain_wall] = material
	return _lit[curtain_wall]
