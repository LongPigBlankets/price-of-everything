extends Node
## Offline projection of existing decorative meshes. No sprite/model rebake.
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const DESTINATION := "res://assets/supply_chain_3d/building_footprints.json"

func _ready() -> void:
	Assets.key_for("house", 1)
	var output := {"version":1,"assets":{}}
	for key in Assets._manifest:
		if not (str(key).begins_with("civic_") or str(key).begins_with("house_") or str(key).begins_with("towers_")): continue
		if str(key).get_slice("_lvl",0) in ["civic_park","civic_plaza","civic_pond","civic_grove"]: continue
		var mesh := Assets.mesh_for(key)
		var cutoff := Assets.storey_height(key)*0.35
		if cutoff<=0: cutoff=Assets.dimensions(key).y*0.10
		var polygons: Array[PackedVector2Array]=[]
		var faces := mesh.get_faces()
		for i in range(0,faces.size(),3):
			if maxf(faces[i].y,maxf(faces[i+1].y,faces[i+2].y))<cutoff: continue
			var tri := PackedVector2Array()
			for j in 3: tri.append(Vector2(faces[i+j].x,faces[i+j].z).snapped(Vector2.ONE*0.00001))
			if absf((tri[1]-tri[0]).cross(tri[2]-tri[0]))<0.00000001: continue
			if Geometry2D.is_polygon_clockwise(tri): tri.reverse()
			var cursor := 0
			while cursor<polygons.size():
				var merged := Geometry2D.merge_polygons(tri,polygons[cursor])
				if merged.size()==1:
					tri=merged[0];polygons.remove_at(cursor);cursor=0
				else: cursor+=1
			polygons.append(tri)
		# Keep the largest part first for older parcel readers; the full list is
		# authoritative for reservations, foundations and vegetation clearance.
		polygons.sort_custom(func(a: PackedVector2Array,b: PackedVector2Array) -> bool: return area(a)>area(b))
		var records: Array=[]
		for poly in polygons:
			var points: Array=[]
			for p in poly: points.append([snappedf(p.x,0.00001),snappedf(p.y,0.00001)])
			records.append(points)
		output.assets[key]={"polygons":records,"source_sha256":FileAccess.get_sha256(Assets.DIRECTORY+key+".glb")}
		print("[FOOTPRINT] ",key," parts=",records.size())
	FileAccess.open(DESTINATION,FileAccess.WRITE).store_string(JSON.stringify(output,"\t")+"\n")
	print("[FOOTPRINT] saved ",output.assets.size()," assets")
	get_tree().quit()

static func area(poly: PackedVector2Array) -> float:
	var total := 0.0
	for i in poly.size(): total += poly[i].cross(poly[(i+1)%poly.size()])
	return absf(total)*0.5
