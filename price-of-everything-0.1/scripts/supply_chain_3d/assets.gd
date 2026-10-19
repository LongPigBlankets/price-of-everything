extends RefCounted
## Only the supply-chain renderer uses these meshes. Existing sprite/map assets are untouched.
const DIRECTORY := "res://assets/supply_chain_3d/"
const BuildingSprites := preload("res://scripts/building_sprites.gd")
const PrintShader := preload("res://scripts/supply_chain_3d/building_print.gdshader")
const ContourShader := preload("res://scripts/supply_chain_3d/contour.gdshader")
const GlassShader := preload("res://scripts/supply_chain_3d/building_glass.gdshader")
const PAINT_INCLUDE := "res://scripts/supply_chain_3d/building_paint.gdshaderinc"
static var _print: ShaderMaterial
static var _glass: ShaderMaterial
static var _lit_glass: Dictionary = {}
static var _contour: ShaderMaterial
static var _contours: Dictionary = {}
static var _trees: Dictionary = {}
static var _lit: Dictionary = {}
static var _meshes: Dictionary = {}
static var _picking: Dictionary = {}
static var _manifest: Dictionary = {}

static func key_for(name: String, level: int) -> String:
	if name in BuildingSprites.WITHHELD_FAMILIES:
		return ""
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
		if not ResourceLoader.exists(DIRECTORY + key + ".glb"):
			return null
		_meshes[key] = load_mesh(DIRECTORY + key + ".glb")
		if _meshes[key] != null: prepare_mesh(_meshes[key])
	return _meshes[key]

## One mesh from a building GLB. The export writes see-through faces as a second object
## named "..._Glass"; its surfaces are appended last and keep the 'Glass' material name.
static func load_mesh(path: String) -> Mesh:
	var scene := load(path) as PackedScene
	if scene == null: return null
	var root := scene.instantiate()
	var nodes := root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D: nodes.push_front(root)
	var mesh: Mesh = (nodes[0] as MeshInstance3D).mesh if not nodes.is_empty() else null
	if nodes.size() > 1 and mesh is ArrayMesh:
		mesh = mesh.duplicate()
		for node in nodes.slice(1):
			var part: Mesh = (node as MeshInstance3D).mesh
			for surface in part.get_surface_count():
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, part.surface_get_arrays(surface))
				var material := part.surface_get_material(surface)
				var tag := StandardMaterial3D.new()
				# The material may be shared or unnamed after import; the node name is certain.
				tag.resource_name = "Glass" if str(node.name).ends_with("_Glass") or (material != null and material.resource_name.begins_with("Glass")) else ""
				mesh.surface_set_material(mesh.get_surface_count() - 1, tag)
	root.free()
	return mesh

## Gives an imported building mesh the print paint, and its see-through surface (the
## export's 'Glass' slot) the glass paint. Remembers which surfaces are glass.
static func prepare_mesh(mesh: Mesh) -> void:
	var glass: Array = []
	for surface in mesh.get_surface_count():
		var source := mesh.surface_get_material(surface)
		var is_glass := source != null and source.resource_name.begins_with("Glass")
		if is_glass: glass.append(surface)
		mesh.surface_set_material(surface, glass_material() if is_glass else print_material())
	mesh.set_meta("glass_surfaces", glass)

static func is_glass(mesh: Mesh, surface: int) -> bool:
	return mesh != null and surface in mesh.get_meta("glass_surfaces", [])

## Paints one building visual surface by surface, so lit windows never turn its glass opaque.
static func paint(node: MeshInstance3D, opaque: Material, glass: Material) -> void:
	node.material_override = null
	for surface in node.mesh.get_surface_count():
		node.set_surface_override_material(surface, glass if is_glass(node.mesh, surface) else opaque)

## Blender units per model unit for this asset, which keeps material patterns at one real size.
static func span(key: String) -> float:
	if _manifest.is_empty(): key_for("warehouse", 1)
	return float(_manifest.get(key, {}).get("span", 0.0))

## The print paint as one source string, for tools that edit or recompile it.
static func print_code(glass: bool = false, defines: PackedStringArray = PackedStringArray()) -> String:
	var source := FileAccess.get_file_as_string((GlassShader if glass else PrintShader).resource_path)
	var extra := ""
	for define in defines: extra += "#define %s\n" % define
	return source.replace('#include "%s"' % PAINT_INCLUDE, extra + FileAccess.get_file_as_string(PAINT_INCLUDE))

static func dimensions(key: String) -> Vector3:
	var data: Dictionary = _manifest.get(key, {})
	return Vector3(float(data.get("width", 1.0)), float(data.get("height", 0.65)), float(data.get("depth", 1.0)))

static func storey_height(key: String) -> float:
	return float(_manifest.get(key, {}).get("storey_height", 0.0))

static func civic_modules(shape: String) -> Array:
	key_for("civic_office", 1)
	var result: Array = []
	for key in _manifest:
		var module: Dictionary = _manifest[key].get("civic_module", {})
		if module.get("shape", "") != shape: continue
		result.append({"key": key, "module": module, "storey": storey_height(key), "dimensions": dimensions(key)})
	return result

static func harbour_for(key: String) -> Dictionary:
	return _manifest.get(key, {}).get("harbour", {})

static func component_for(key: String) -> Dictionary:
	return _manifest.get(key, {}).get("component", {})

static func cable_anchors(key: String) -> PackedVector3Array:
	var points := PackedVector3Array()
	for xyz in _manifest.get(key, {}).get("cable_anchors", []):
		points.append(Vector3(xyz[0], xyz[1], xyz[2]))
	return points

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
		material.set_shader_parameter("landscape", true)
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
	glass_material().set_shader_parameter("grade_range", value)
	for material in _lit_glass.values(): material.set_shader_parameter("grade_range", value)
	for material in _lit.values(): material.set_shader_parameter("grade_range", value)
	for material in _trees.values(): material.set_shader_parameter("grade_range", value)

static func set_detail(tier: int) -> void:
	if _print != null: _print.set_shader_parameter("detail_level", tier)
	if _glass != null: _glass.set_shader_parameter("detail_level", tier)
	for material in _lit_glass.values(): material.set_shader_parameter("detail_level", tier)
	for material in _lit.values(): material.set_shader_parameter("detail_level", tier)
	for material in _trees.values(): material.set_shader_parameter("detail_level", tier)

static func lit_material(curtain_wall: bool = false) -> ShaderMaterial:
	if not _lit.has(curtain_wall):
		var material := _print.duplicate() as ShaderMaterial
		material.set_shader_parameter("lit_windows", true)
		material.set_shader_parameter("curtain_wall", curtain_wall)
		_lit[curtain_wall] = material
	return _lit[curtain_wall]

static func lit_glass_material(curtain_wall: bool = false) -> ShaderMaterial:
	if not _lit_glass.has(curtain_wall):
		var material := glass_material().duplicate() as ShaderMaterial
		material.set_shader_parameter("lit_windows", true)
		material.set_shader_parameter("curtain_wall", curtain_wall)
		_lit_glass[curtain_wall] = material
	return _lit_glass[curtain_wall]

static func glass_material() -> ShaderMaterial:
	if _glass == null:
		_glass = ShaderMaterial.new()
		_glass.shader = GlassShader
	return _glass

static func print_material() -> ShaderMaterial:
	if _print == null:
		_print = ShaderMaterial.new()
		_print.shader = PrintShader
	return _print

static func picking_shape(key: String) -> Shape3D:
	if key == "": return null
	if not _picking.has(key):
		var path := DIRECTORY + "picking/" + key + ".res"
		if ResourceLoader.exists(path): _picking[key] = load(path)
		else:
			var mesh := mesh_for(key)
			if mesh != null: _picking[key] = mesh.create_trimesh_shape()
	return _picking.get(key)
