extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Footprints := preload("res://scripts/supply_chain_3d/building_footprints.gd")
const Placement := preload("res://scripts/supply_chain_3d/road_placement.gd")
const Sidewalks := preload("res://scripts/supply_chain_3d/urban_sidewalks.gd")
const Surface := preload("res://scripts/supply_chain_3d/road_surface.gd")

func _test_building_footprints_courtyards_and_clearance() -> void:
	var shapes := Footprints.local("civic_u_office_lvl1")
	var courtyard := Vector2(0,0.20)
	var wing := Vector2(0.38,0.20)
	var free := true
	var occupied := false
	for shape in shapes:
		free = free and not Geometry2D.is_point_in_polygon(courtyard,shape)
		occupied = occupied or Geometry2D.is_point_in_polygon(wing,shape)
	_check(free and occupied,"footprints: the U courtyard is free while its wings remain occupied")
	var s := {"pos":Vector2(100,150),"side":80.0,"yaw":PI/3.0}
	var transformed := Footprints.world("civic_u_office_lvl1",s)
	_check((transformed[0][0] as Vector2).is_equal_approx(s.pos+(shapes[0][0]*80.0).rotated(-PI/3.0)),"footprints: rotation and size match the rendered mesh")
	var fit := Placement.new()
	fit.ground=func(_p: Vector2) -> float: return 0.0
	var box := PackedVector2Array([Vector2(0,0),Vector2(10,0),Vector2(10,10),Vector2(0,10)])
	fit.reserve("first",box)
	var adjacent := PackedVector2Array([Vector2(10.1,0),Vector2(20,0),Vector2(20,10),Vector2(10.1,10)])
	_check(fit.clear_plot(adjacent,Vector2.ZERO,"second",12.0,0.01),"footprints: a 0.1u building gap no longer reserves an extra 4u box")
	_check(not fit.clear_plot(box,Vector2.ZERO,"second",12.0,0.01),"footprints: actual overlapping buildings are still rejected")
	var current := true
	var metadata: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Footprints.PATH)).assets
	for key in metadata:
		current=current and metadata[key].source_sha256==FileAccess.get_sha256("res://assets/supply_chain_3d/"+key+".glb")
	_check(current,"footprints: every silhouette matches its source GLB")

func _test_urban_sidewalk_scope_and_junction() -> void:
	var roads: Array=[]
	for item in [["urban","street",true],["rural","street",true],["urban","access:home",true],["urban","track",false]]:
		roads.append({"a":Vector2(-30,0),"b":Vector2(30,0),"tile":item[0],"source":item[1],"paved":item[2],"level":1,"widths":[5.0,4.7,4.4,4.1]})
	Sidewalks.apply(roads,{"urban":{"type":"urban"},"rural":{"type":"rural"}})
	_check(Sidewalks.width(roads[0])==2.0 and Sidewalks.width(roads[1])==0.0 and Sidewalks.width(roads[2])==0.0 and Sidewalks.width(roads[3])==0.0,"sidewalks: paved urban streets only; rural roads and access paths stay unchanged")
	var cross: Dictionary=roads[0].duplicate(true)
	cross.a=Vector2(0,-30);cross.b=Vector2(0,30)
	var surface := Surface.new()
	surface.configure([roads[0],cross],func(_p: Vector2) -> float: return 0.0)
	var mesh := surface.mesh_for("urban")
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var colours: PackedColorArray=arrays[Mesh.ARRAY_COLOR]
	var paving := false
	var covered := false
	for i in vertices.size():
		if colours[i].is_equal_approx(Sidewalks.PAVING) and absf(vertices[i].z)>6.7: paving=true
		if absf(vertices[i].x)<0.1 and absf(vertices[i].z)<0.1 and vertices[i].y>0.95: covered=true
	_check(paving and covered,"sidewalks: the 2u paved edge reaches both sides and the junction keeps its carriageway above paving")
	surface.finish_build()
