extends RefCounted
## Deterministic infill planting. Count union canopy coverage over dry land, not
## the sum of crown areas; parks' embedded trees are conservatively uncounted.
const Trial := preload("res://scripts/supply_chain_3d/stoneshore_trial.gd")
const Index := preload("res://scripts/supply_chain_3d/road_index.gd")
const Trees := preload("res://scripts/supply_chain_3d/tree_layout.gd")
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const Fit := preload("res://scripts/supply_chain_3d/road_placement.gd")
const Plazas := preload("res://scripts/supply_chain_3d/urban_plazas.gd")
const Coast := preload("res://scripts/supply_chain_3d/coast.gd")
const Ground := preload("res://scripts/empire_board_ground.gd")
const GRID := 4.0
const TARGET := .106
const BEACH_PER_TILE := 4 # at most 20 across the five-tile review
var land := {}
var covered := {}
var tree_index := {}
var occupied: Array=[]
var building_index := {}
var shapes: Array=[]
var plaza_index := {}
var plaza_shapes: Array=[]
var builder: RefCounted
var relief := {}
var center := Vector2.ZERO

static func beach(p: Vector2, rel: Dictionary) -> bool:
	# The base beach polygon underlies all land; only its visible, unpainted
	# portion is sand. Higher terrain polygons paint grass over that base.
	for i in range(rel.get("land",[]).size()-1,-1,-1):
		if Geometry2D.is_point_in_polygon(p,rel.land[i].p):return rel.land[i].get("beach",false)
	return false

static func radii(tree: Dictionary) -> Vector2:
	var key := Assets.key_for("tree",{"small":1,"fir":2,"large":3}[tree.kind])
	var dim := Assets.dimensions(key)*float(tree.height)/Assets.projected_height(key)
	return Vector2(dim.x,dim.z)*.5

func _mark(tree: Dictionary) -> int:
	var before := covered.size();var r := radii(tree);var p: Vector2=tree.pos
	for y in range(floori((p.y-r.y)/GRID),ceili((p.y+r.y)/GRID)):
		for x in range(floori((p.x-r.x)/GRID),ceili((p.x+r.x)/GRID)):
			var k := Vector2i(x,y)
			if land.has(k) and ((Vector2(k)*GRID+Vector2.ONE*GRID*.5-p)/r).length_squared()<=1:covered[k]=true
	return covered.size()-before

func _plaza(p: Vector2) -> bool:
	for id in plaza_index.get(Vector2i((p/Index.CELL).floor()),[]):
		if Geometry2D.is_point_in_polygon(p,plaza_shapes[id]):return true
	return false

func _clear(tree: Dictionary) -> bool:
	var p: Vector2=tree.pos;var r := Trees.canopy(tree)
	if not Index.contains(center,p) or not builder.rail_vegetation.clear(p,r+1.0):return false
	for id in Index.query(building_index,Rect2(p,Vector2.ZERO).grow(r)):
		if Fit.distance_to_polygon(p,p,shapes[id])<r+1:return false
	for id in Index.query(tree_index,Rect2(p,Vector2.ZERO).grow(r+18)):
		var other: Dictionary=occupied[id]
		if p.distance_to(other.pos)<.76*(r+Trees.canopy(other)):return false
	var h: float=builder.surface_height(p)
	for d in [Vector2.ZERO,Vector2.UP,Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT,Vector2(1,1).normalized(),Vector2(-1,1).normalized(),Vector2(1,-1).normalized(),Vector2(-1,-1).normalized()]:
		var q: Vector2=p+d*r
		if not builder.tiles.values().any(func(tile):return Index.contains(tile.center,q)) and not builder.sea_fringe.contains(q):return false
		if builder.open_water(q):return false
		if absf(builder.surface_height(q)-h)>3.0:return false
	return true

func plant(tid: String, source: Array, owner: RefCounted, standing: Array, plazas: Array) -> Dictionary:
	builder=owner;center=builder.tiles[tid].center;relief=Coast.relief_of(tid,center)
	plaza_shapes=plazas;plaza_index=Plazas._index(plazas)
	for s in standing:
		var key := str(builder.standing_key(s))
		if s.kind=="pylon" or (key.is_empty() and not s.has("harbour")):continue
		shapes.append_array(Plazas.polygons(s,key))
	for site in builder.neighbourhood.get("brownfields",[]):shapes.append(site.polygon)
	for station in builder.stations:shapes.append(preload("res://scripts/supply_chain_3d/rail_station.gd").polygon(station))
	for records in builder.rivers.values():
		for river in records:
			for i in range(1,river.points.size()):shapes.append(Trees.Legacy._capsule(river.points[i-1],river.points[i],16.0,[true,true]))
	for line in builder.lines:
		if not Trees.Model.PIPE_MODES.has(str(line.mode)):continue
		for i in range(1,line.pts.size()):shapes.append(Trees.Legacy._capsule(line.pts[i-1].p,line.pts[i].p,9.0,[true,true]))
	building_index=Plazas._index(shapes)
	for y in range(floori((center.y-240)/GRID),ceili((center.y+240)/GRID)):
		for x in range(floori((center.x-270)/GRID),ceili((center.x+270)/GRID)):
			var k := Vector2i(x,y);var p := Vector2(k)*GRID+Vector2.ONE*GRID*.5
			if Index.contains(center,p) and not Ground.is_water(relief,p):land[k]=true
	# Continue crowns across rendered tile edges while respecting trees already
	# placed on neighbouring tiles. This avoids empty seams in the canopy.
	for neighbours in builder.tree_placements.values():
		for tree in neighbours:
			Index.insert(tree_index,Rect2(tree.pos,Vector2.ZERO),occupied.size());occupied.append(tree)
	var trees: Array=[];var beach_count := 0;var plaza_count := 0
	for tree in source:
		if not _clear(tree):continue
		if beach(tree.pos,relief):
			if beach_count>=BEACH_PER_TILE:continue
			beach_count+=1
		trees.append(tree);_mark(tree);Index.insert(tree_index,Rect2(tree.pos,Vector2.ZERO),occupied.size());occupied.append(tree)
	var retained := trees.size()
	var before := float(covered.size())/maxi(1,land.size())
	var candidates: Array=[]
	# A jittered lattice provides even opportunity; patch noise groups accepted
	# trees into groves. Concrete forecourts receive planting before open grass.
	for y in range(floori((center.y-240)/10),ceili((center.y+240)/10)):
		for x in range(floori((center.x-270)/10),ceili((center.x+270)/10)):
			var seed_value := absi(hash("stoneshore-green:%d:%d" % [x,y]))
			var p := Vector2(x*10+2.0+(seed_value%61)*.1,y*10+2.0+((seed_value/61)%61)*.1)
			if not Index.contains(center,p) or Ground.is_water(relief,p):continue
			var on_plaza := _plaza(p)
			var patch := sin(p.x*.032)+cos(p.y*.027)+sin((p.x+p.y)*.019)
			candidates.append({"p":p,"seed":seed_value,"plaza":on_plaza,"score":(-5 if on_plaza else patch)+float(seed_value%101)*.003})
	candidates.sort_custom(func(a,b):return a.score<b.score)
	for c in candidates:
		if covered.size()>=land.size()*TARGET:break
		var on_beach := beach(c.p,relief)
		if on_beach and beach_count>=BEACH_PER_TILE:continue
		var kind := "small" if c.plaza or c.seed%5!=0 else ("large" if c.seed%2 else "fir")
		var size: float=[1.0,.75,.5][c.seed%3]
		if builder.rail_vegetation.beside_rail(c.p):size=.5
		var tree := {"pos":c.p,"kind":kind,"height":float(Trees.Legacy._TREE_HEIGHT[kind])*size,"size_scale":size,"edge":"","source":"plaza" if c.plaza else "stoneshore_infill"}
		if not _clear(tree):continue
		trees.append(tree);_mark(tree);Index.insert(tree_index,Rect2(tree.pos,Vector2.ZERO),occupied.size());occupied.append(tree)
		if c.plaza:plaza_count+=1
		if on_beach:beach_count+=1
	var audit := {"trees":trees.size(),"added":trees.size()-retained,"beach_trees":beach_count,"plaza_trees":plaza_count,"land_area":land.size()*GRID*GRID,"canopy_area":covered.size()*GRID*GRID,"before":before,"coverage":float(covered.size())/maxi(1,land.size())}
	builder=null
	return {"trees":trees,"audit":audit}
