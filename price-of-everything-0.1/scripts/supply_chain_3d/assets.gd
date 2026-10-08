extends RefCounted
## Only the supply-chain renderer uses these meshes. Existing sprite/map assets are untouched.
const DIRECTORY := "res://assets/supply_chain_3d/"
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
	return _meshes[key]

static func dimensions(key: String) -> Vector3:
	var data: Dictionary = _manifest.get(key, {})
	return Vector3(float(data.get("width", 1.0)), float(data.get("height", 0.65)), float(data.get("depth", 1.0)))
