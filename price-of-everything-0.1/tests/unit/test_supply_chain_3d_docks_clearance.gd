extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Rail := preload("res://scripts/supply_chain_3d/railway.gd")
const Clearance := preload("res://scripts/supply_chain_3d/rail_clearance.gd")
const Elevation := preload("res://scripts/supply_chain_3d/rail_elevation.gd")
const Fringe := preload("res://scripts/supply_chain_3d/sea_fringe.gd")

func _test_docks_clearance_parallel_road_and_yard_preference() -> void:
	var plan := Rail.network([{"mode":"rails","pts":[{"p":Vector2(-400,0)},{"p":Vector2(400,0)}]}])
	var clearance := Clearance.new()
	var roads := [{"a":Vector2(-150,4),"b":Vector2(150,4),"half":5.0}]
	clearance.configure(plan,roads,[],{"tile_5_10":{"center":Vector2.ZERO}},[],Callable())
	_check(clearance.covered(Vector2.ZERO),"Docks clearance: overlapping parallel road widths require a roof without a centreline crossing")
	_check(not clearance.covered(Vector2(0,40)),"Docks clearance: separated road and track remain unaffected")
	var solved := Elevation.solve(plan,func(_p):return 34.0,func(_p):return 1.0,func(_p):return false,func(_p):return 80.0,[],clearance.covered)
	var conflicts: Array= solved.tracks.filter(func(t):return absf(t.a.x)<140)
	_check(conflicts.all(func(t):return t.hidden and absf(t.ha-21.2)<.001 and absf(t.hb-21.2)<.001),"Docks clearance: mandatory overlap protection beats the nearby-depot preference and keeps one tunnel datum")
	var max_grade := 0.0
	for t in solved.tracks:max_grade=maxf(max_grade,absf(t.hb-t.ha)/t.a.distance_to(t.b))
	_check(max_grade<=Elevation.MAX_APPROACH_GRADE+.001,"Docks clearance: mandatory tunnel approaches stay continuous below 12% despite nearby depot proximity")
	clearance.configure(plan,[{"a":Vector2(0,-180),"b":Vector2(0,180),"half":5.0}],[],{"tile_5_10":{"center":Vector2.ZERO}},[],Callable())
	_check(not clearance.covered(Vector2.ZERO),"Docks clearance: ordinary perpendicular intersections remain available for bridges or level crossings")

func _test_docks_clearance_sea_only_clipping() -> void:
	var strip := PackedVector2Array([Vector2.ZERO,Vector2(200,0),Vector2(200,48),Vector2(0,48)])
	var land := PackedVector2Array([Vector2(0,0),Vector2(70,0),Vector2(70,60),Vector2(0,60)])
	var parts := Fringe.water_parts(strip,[land])
	_check(parts.size()==1 and Geometry2D.is_point_in_polygon(Vector2(100,24),parts[0]),"Sea margin: water within the tenth-tile strip survives clipping")
	_check(not Geometry2D.is_point_in_polygon(Vector2(30,24),parts[0]),"Sea margin: neighbouring land is excluded")
	_check(not Geometry2D.is_point_in_polygon(Vector2(100,49),parts[0]),"Sea margin: scenery stops at the requested ten-percent depth")
	var batch := preload("res://scripts/supply_chain_3d/geometry.gd").Batch.new()
	Fringe.polygon(batch,parts[0],Color.BLUE,Vector2.ZERO,12.0)
	_check(batch.normals.size()>0 and Array(batch.normals).all(func(n):return n==Vector3.UP),"Sea margin: water triangles face upward at all camera angles")

func _test_docks_clearance_enclosed_islet() -> void:
	var strip := PackedVector2Array([Vector2.ZERO,Vector2(200,0),Vector2(200,48),Vector2(0,48)])
	var islet := PackedVector2Array([Vector2(80,10),Vector2(110,10),Vector2(110,35),Vector2(80,35)])
	var pieces := Fringe.water_parts(strip,[islet])
	_check(pieces.size()>=2 and not pieces.any(func(p):return Geometry2D.is_point_in_polygon(Vector2(95,24),p)),"Sea margin: enclosed islets become true holes instead of a filled water triangle")
	var painted := Fringe.paint_layers(strip,Color.BLUE,[{"p":islet,"color":Color.RED}])
	_check(painted.filter(func(p):return Geometry2D.is_point_in_polygon(Vector2(95,24),p.p)).size()==1,"Sea margin: depth/shore colours partition the surface without overlapping coplanar layers")

func _test_docks_clearance_fixed_industrial_asset() -> void:
	var assets := preload("res://scripts/supply_chain_3d/assets.gd")
	var key := assets.key_for("eaf",1)
	var factory := {"iid":"fixed-eaf","kind":"building","tile":"tile_5_10","pos":Vector2.ZERO,"side":51.0,"level":1,
		"footprint":PackedVector2Array([Vector2(80,80),Vector2(90,80),Vector2(90,90),Vector2(80,90)])}
	var plan := Rail.network([{"mode":"rails","pts":[{"p":Vector2(-180,0)},{"p":Vector2(180,0)}]}])
	var clearance := Clearance.new()
	clearance.configure(plan,[],[factory],{"tile_5_10":{"center":Vector2.ZERO}},[],func(_s):return key)
	_check(clearance.covered(Vector2.ZERO),"Docks clearance: fixed industrial assets protect their rendered footprint, regardless of the gameplay plot polygon")
	_check(not clearance.covered(Vector2(100,0)),"Docks clearance: industrial protection is local, leaving clear approaches available")
