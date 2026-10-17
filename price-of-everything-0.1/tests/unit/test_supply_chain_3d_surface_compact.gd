extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Compact := preload("res://scripts/supply_chain_3d/surface_compact.gd")
const Geo := preload("res://scripts/supply_chain_3d/geometry.gd")
const Roads := preload("res://scripts/supply_chain_3d/road_drawing.gd")
const Surface := preload("res://scripts/supply_chain_3d/road_surface.gd")

func _grid(hole: bool=false, sloped: bool=false) -> ArrayMesh:
	var batch := Geo.Batch.new()
	for y in 12:
		for x in 12:
			if hole and x in [5,6] and y in [5,6]:continue
			var points: Array[Vector3]=[]
			for offset in [Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]:
				var p: Vector2 = (Vector2(x,y)+offset)*4.0
				points.append(Vector3(p.x,12.0+p.x*0.2 if sloped else 12.0,p.y))
			batch.quad(points[0],points[3],points[2],points[1],Color.WHITE)
	return batch.mesh(Rect2(0,0,48,48))

func _area(mesh: Mesh) -> float:
	var faces := mesh.get_faces();var area := 0.0
	for i in range(0,faces.size(),3):area+=(faces[i+1]-faces[i]).cross(faces[i+2]-faces[i]).length()*0.5
	return area

func _test_compact_surface_flat_area_and_boundaries() -> void:
	var original := _grid();var mesh := Compact.build(original)
	_check(mesh.get_faces().size()<original.get_faces().size()/3,"Compact surface: flat interior loses redundant triangles")
	_check(is_equal_approx(_area(mesh),_area(original)) and mesh.get_aabb()==original.get_aabb(),"Compact surface: area and exact bounds survive")
	var a := mesh.surface_get_arrays(0)
	for i in a[Mesh.ARRAY_VERTEX].size():
		var p:Vector3=a[Mesh.ARRAY_VERTEX][i]
		_check((a[Mesh.ARRAY_TEX_UV][i] as Vector2).is_equal_approx(Vector2(p.x,p.z)/48.0),"Compact surface: texture coordinates stay in place")
	_check(a[Mesh.ARRAY_VERTEX].size()<original.surface_get_array_len(0)/3,"Compact surface: shared vertices retained")

func _test_compact_surface_hole_and_slope_preserved() -> void:
	var original := _grid(true);var mesh := Compact.build(original)
	_check(is_equal_approx(_area(mesh),_area(original)),"Compact surface: lake/road openings retain their area")
	var faces := mesh.get_faces();var covers_hole:=false
	for i in range(0,faces.size(),3):
		var polygon:=PackedVector2Array()
		for j in 3:polygon.append(Vector2(faces[i+j].x,faces[i+j].z))
		covers_hole=covers_hole or Geometry2D.is_point_in_polygon(Vector2(24,24),polygon)
	_check(not covers_hole,"Compact surface: no triangle fills the opening")
	original=_grid(false,true);mesh=Compact.build(original)
	_check(mesh.get_faces().size()==original.get_faces().size(),"Compact surface: sloped relief keeps every triangle")
	_check(is_equal_approx(_area(mesh),_area(original)) and mesh.get_aabb()==original.get_aabb(),"Compact surface: relief height and area unchanged")
	var joined := Compact.joined([mesh,mesh])
	_check(joined.get_faces().size()==mesh.get_faces().size()*2 and is_equal_approx(_area(joined),_area(mesh)*2),"Compact surface: indexed joins preserve complete triangles")

func _test_compact_surface_road_grade_and_bridge_structure() -> void:
	var surface:=Surface.new();surface.cell_size=6.0
	var height:=func(p: Vector2)->float:return 40.0+p.x*0.1
	surface.configure([{"tile":"test","a":Vector2(12,18),"b":Vector2(90,18),"level":2,"paved":true}],height)
	var source:=surface.mesh_for("test")
	var support:=Geo.Batch.new();support.box(Vector3(48,20,18),Vector3(2,40,2),Color("92928a"))
	var drawing:=Roads.extract(Geo.joined([source,support.mesh()]),6.0)
	_check(drawing.mesh.get_faces().size()<source.get_faces().size()/2,"Compact surface: road layers become one carrier")
	var good:=true
	for p in drawing.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:good=good and absf(p.y-(40.0+p.x*0.1+1.09))<0.005
	_check(good,"Compact surface: raised road retains the bridge grade")
	_check(is_equal_approx(_area(drawing.extras),_area(support.mesh())),"Compact surface: support geometry stays three dimensional")
	_check(drawing.area.has_area(),"Compact surface: road drawing includes a transparent gutter")
	surface.finish_build()

func _test_compact_surface_reveal_handover_and_retention() -> void:
	var drawing := {"mesh":_grid(),"texture":ImageTexture.create_from_image(Image.create(4,4,false,Image.FORMAT_RGBA8)),"texture_bytes":64}
	var node := Geo.instance(drawing.mesh,Roads.material(ShaderMaterial.new(),drawing))
	add_child(node)
	var handover := preload("res://scripts/supply_chain_3d/lod_handover.gd").new()
	handover.begin(1.0,[node],[])
	_check(node.material_override.get_shader_parameter("lod_side")==1,"Compact surface: road participates in two-frame LOD handover")
	handover.clear()
	var reveal := preload("res://scripts/supply_chain_3d/tile_reveal.gd").new()
	reveal.configure({"a":{"center":Vector2.ZERO}},Vector2.ZERO)
	reveal.begin({});reveal.bind(node)
	_check(node.material_override.get_shader_parameter("loading_mask")==true,"Compact surface: road participates in ink reveal")
	var retention := preload("res://scripts/supply_chain_3d/tile_resource_cache.gd")
	var cost := retention.estimate({}, {"road_drawing":drawing})
	_check(cost>64,"Compact surface: retained budget counts road texture and mesh")
	node.free()
