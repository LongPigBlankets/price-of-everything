extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Blocks := preload("res://scripts/supply_chain_3d/neighbourhood_blocks.gd")
const Placement := preload("res://scripts/supply_chain_3d/road_placement.gd")
const Builder := preload("res://scripts/supply_chain_3d/world_builder.gd")
const Index := preload("res://scripts/supply_chain_3d/road_index.gd")
const Fill := preload("res://scripts/supply_chain_3d/frontage_fill.gd")

func _test_neighbourhood_blocks_cached_layout_and_reservations() -> void:
	var tile := {"type":"urban","center":Vector2.ZERO}
	var seed := {"iid":"seed","kind":"house","tile":"tile_4_9","pos":Vector2.ZERO,"side":36.0,"level":1,"decor_asset":"house_lvl1",
		"trial_density":true,"trial_tile":tile,"trial_edge_centers":[],"trial_harbours":[]}
	var model := {"tiles":{"tile_4_9":tile},"trial_targets":{"tile_4_9":0},"standing":[seed],"district_blocks":{},
		"authored_region":{"tiles":{"tile_4_9":Vector2.ZERO},"paths":[{"id":"street","class":"minor","layer":0,"points":PackedVector2Array([Vector2(-210,0),Vector2(210,0)])}]},
		"roads":[{"a":Vector2(-210,0),"b":Vector2(210,0),"tile":"tile_4_9","source":"street","level":1,"paved":true,"widths":[5.0,4.5,4.0,3.5]}]}
	model.roads.append({"a":Vector2(-165,140),"b":Vector2(165,140),"tile":"tile_4_9","source":"district:test","level":1,"paved":true,"district_street":true,"widths":[4.8,4.6,4.4,4.2]})
	model.authored_region.paths.append({"id":"district:test","class":"minor","layer":0,"points":PackedVector2Array([Vector2(-165,140),Vector2(165,140)]),"widths":[4.8,4.6,4.4,4.2],"district_street":true})
	var saved := model.duplicate(true);var prepared := {}
	var flat := func(_p: Vector2)->float:return 40.0
	var dry := func(_p: Vector2)->bool:return false
	Placement.new().fit(model,flat,dry,Builder.standing_key,{},prepared)
	_check(not model.neighbourhood.paths.is_empty() and not model.neighbourhood.brownfields.is_empty(),"neighbourhood blocks: connected lanes and usable brownfields on available flat land")
	_check(model.neighbourhood.greens>0 and model.neighbourhood.buildings>0,"neighbourhood blocks: public greens and additional housing share the block")
	_check(model.neighbourhood.courtyards>0,"neighbourhood blocks: fixture includes courtyard buildings emitted before frontage infill")
	var clear := true
	for site in model.neighbourhood.brownfields:
		clear=clear and site.size.x>=50 and site.size.y>=40 and site.entrance.distance_to(site.road_join)<14
		for s in model.standing:
			for poly in s.get("footprints",[]):
				for i in poly.size(): clear=clear and Placement.distance_to_polygon(poly[i],poly[(i+1)%poly.size()],site.polygon)>.01
	_check(clear,"neighbourhood blocks: brownfields have road gates and remain free of decoration")
	Placement.new().fit(saved,flat,dry,Builder.standing_key,{},prepared)
	_check(saved==model,"neighbourhood blocks: a cache hit restores streets, parcels, courtyard buildings and greens exactly")
	var layers := true
	for s in model.standing:
		if int(s.get("neighbourhood_row",0))>=2: layers=layers and s.decor_asset in ["house_lvl1","civic_semi_lvl1"]
	_check(layers,"neighbourhood blocks: shops stay on the first row; deeper rows use homes")
	var lanes: Array=model.roads.filter(Blocks.lane)
	_check(lanes.all(func(r):return r.widths==Blocks.WIDTHS and not Fill.street(r)),"neighbourhood blocks: quiet lanes retain their narrower widths and separate frontage target")

func _test_neighbourhood_blocks_safe_connections() -> void:
	var fit := Placement.new()
	fit.ground=func(_p):return 40.0
	fit.water=func(_p):return false
	fit.roads=[{"a":Vector2(-200,0),"b":Vector2(200,0),"widths":[5.0],"sidewalk":2.0}];fit.road_index=Index.segments(fit.roads,20)
	var blocks := Blocks.new();blocks.fit=fit;blocks.world={"tiles":{"t":{"center":Vector2.ZERO}}}
	var path := PackedVector2Array([Vector2(-50,0),Vector2(-50,70),Vector2(50,70),Vector2(50,0)])
	_check(blocks._lane_clear(path,"t"),"neighbourhood blocks: both loop mouths reach the original road")
	fit.water=func(p):return p.y>60
	_check(not blocks._lane_clear(path,"t"),"neighbourhood blocks: no lanes through water")
	fit.water=func(_p):return false
	fit.ground=func(p):return 40.0 if p.y<40 else 48.0
	_check(not blocks._lane_clear(path,"t"),"neighbourhood blocks: no lanes over terrace steps")
	fit.ground=func(_p):return 40.0
	fit.reserve("station",Blocks.rectangle(Vector2(0,70),Vector2.RIGHT,Vector2(30,30)))
	_check(not blocks._lane_clear(path,"t"),"neighbourhood blocks: preserve rail, station and player footprint reservations")
	_check(Blocks.row_for(20)==1 and Blocks.row_for(55)==2 and Blocks.row_for(100)==3,"neighbourhood blocks: depth bands decrease density away from main roads")
	blocks.fit=null

func _test_neighbourhood_blocks_parcel_and_path_art() -> void:
	var fit := Placement.new()
	fit.ground=func(_p):return 40.0
	fit.water=func(p):return p.distance_to(Vector2.ZERO)<3
	var blocks := Blocks.new();blocks.fit=fit
	_check(not blocks._parcel_dry(Vector2.ZERO,Vector2.RIGHT,Vector2(52,40)),"neighbourhood blocks: empty parcel cannot bridge over a small water patch in its interior")
	blocks.fit=null
	var art: ArrayMesh=preload("res://scripts/supply_chain_3d/neighbourhood_art.gd").mesh({"footpaths":[PackedVector2Array([Vector2.ZERO,Vector2(30,20)])]},Vector2.ZERO,func(_p):return 40.0)
	var arrays := art.surface_get_arrays(0)
	var upward := true
	for normal in arrays[Mesh.ARRAY_NORMAL]: upward=upward and normal.y>.99
	_check(upward,"neighbourhood blocks: garden paths face upward and remain visible from above")
