extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Blocks := preload("res://scripts/supply_chain_3d/district_blocks.gd")
const Index := preload("res://scripts/supply_chain_3d/road_index.gd")
const Region := preload("res://scripts/supply_chain_3d/authored_region.gd")
const Paint := preload("res://scripts/supply_chain_3d/road_markings.gd")

func _test_district_blocks_voronoi_partition() -> void:
	var sites := PackedVector2Array([Vector2(2300,5500),Vector2(2420,5490),Vector2(2360,5620)])
	var bounds := Rect2(2200,5400,340,340)
	var cells := Blocks.cells(sites,bounds)
	var area := 0.0
	var valid := true
	for i in cells.size():
		var poly: PackedVector2Array=cells[i]
		valid=valid and Geometry2D.is_point_in_polygon(sites[i],poly)
		for p in poly:
			for j in sites.size(): valid=valid and p.distance_squared_to(sites[i])<=p.distance_squared_to(sites[j])+0.3
		for j in poly.size(): area+=poly[j].cross(poly[(j+1)%poly.size()])*.5
	_check(valid,"district blocks: every Voronoi cell belongs to its nearest seed at map coordinates")
	_check(absf(area-bounds.get_area())<2.0,"district blocks: cells cover the domain without gaps or overlap")
	var blocks := Blocks.new();blocks.centers={"t":Vector2.ZERO};blocks.tile_index=Index.tiles(blocks.centers)
	blocks.water=func(_p):return false
	var seeded := PackedVector2Array();blocks._site(seeded,Vector2.ZERO);blocks._site(seeded,Vector2(5,0));blocks._site(seeded,Vector2(110,0))
	_check(seeded.size()==2,"district blocks: road seeds share a deterministic minimum spacing")

func _test_district_blocks_connected_thin_roads() -> void:
	var blocks := Blocks.new()
	blocks.roads=[{"a":Vector2(-100,0),"b":Vector2(100,0)}];blocks.road_index=Index.segments(blocks.roads,30)
	var edges := [{"a":Vector2(0,0),"b":Vector2(0,60)},{"a":Vector2(0,60),"b":Vector2(60,60)},
		{"a":Vector2(60,60),"b":Vector2(60,0)},{"a":Vector2(0,60),"b":Vector2(-30,90)},
		{"a":Vector2(150,150),"b":Vector2(170,170)}]
	var connected := blocks.connected_edges(edges)
	_check(connected.size()==3,"district blocks: retain road-to-road connections and prune detached/dead-end stubs")
	var paths := [{"id":"district:test","points":PackedVector2Array([Vector2(-50,0),Vector2(50,0)]),
		"class":"minor","layer":0,"widths":Blocks.WIDTHS,"level":2,"district_street":true}]
	var roads := Region.compile_segments(paths,{"t":Vector2.ZERO})
	_check(roads.size()==1 and roads[0].district_street and roads[0].widths==Blocks.WIDTHS and roads[0].level==2,
		"district blocks: custom narrow widths and two-lane paint survive network compilation")
	_check(Paint.lane_lines(2,Blocks.WIDTHS[3])==[[0.0,true]],"district blocks: side streets have one centre divider, two lanes total")
	blocks.centers={"t":Vector2.ZERO};blocks.tile_index=Index.tiles(blocks.centers)
	blocks.water=func(p):return p.x>30
	blocks.ground=func(_p):return 34.0
	_check(not blocks.safe_road(Vector2.ZERO,Vector2(60,0)),"district blocks: reject roads that cross water")
	blocks.water=func(_p):return false
	blocks.ground=func(p):return 34.0 if p.x<30 else 42.0
	_check(not blocks.safe_road(Vector2.ZERO,Vector2(60,0)),"district blocks: reject roads crossing a height step")
