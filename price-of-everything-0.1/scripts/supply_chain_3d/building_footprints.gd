extends RefCounted
## Prepared mesh silhouettes in local X/Z. Concavities and separate wings stay open.
const PATH := "res://assets/supply_chain_3d/building_footprints.json"
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const Far := preload("res://scripts/supply_chain_3d/far_sprites.gd")
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

static func rendered(key: String, s: Dictionary) -> Array:
	if str(s.kind)=="house": return world(key,s)
	var dim := Assets.dimensions(key)*float(s.side)
	var offset := Far.center(key)*float(s.side)
	var half := Vector2(dim.x,dim.z)*.5
	var polygon := PackedVector2Array()
	for p in [Vector2(-half.x,-half.y),Vector2(half.x,-half.y),half,Vector2(-half.x,half.y)]:
		polygon.append(s.pos+(p+Vector2(offset.x,offset.z)).rotated(-float(s.get("yaw",0))))
	return [polygon]

static func reserved(key: String, s: Dictionary) -> Array:
	# Gameplay plots can be smaller than an offset industrial mesh. Keep both
	# the working plot (including farm fields) and the visible mass clear.
	var result := rendered(key,s)
	if str(s.kind)!="house" and s.has("footprint") and s.footprint.size()>=3:
		result.append(s.footprint)
	return result
