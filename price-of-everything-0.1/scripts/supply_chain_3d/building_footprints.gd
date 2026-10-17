extends RefCounted
## Prepared mesh silhouettes in local X/Z. Concavities and separate wings stay open.
const PATH := "res://assets/supply_chain_3d/building_footprints.json"
static var _assets := {}
static var _polygons := {}

static func local(key: String) -> Array:
	if _assets.is_empty(): _assets=JSON.parse_string(FileAccess.get_file_as_string(PATH)).assets
	if not _polygons.has(key):
		var result: Array=[]
		for points in _assets.get(key,{}).get("polygons",[]):
			var poly := PackedVector2Array()
			for p in points: poly.append(Vector2(p[0],p[1]))
			result.append(poly)
		_polygons[key]=result
	return _polygons[key]

static func world(key: String, s: Dictionary) -> Array:
	var result: Array=[]
	for shape in local(key):
		var poly := PackedVector2Array()
		for p in shape: poly.append(s.pos+(p*float(s.side)).rotated(-float(s.get("yaw",0.0))))
		result.append(poly)
	return result
