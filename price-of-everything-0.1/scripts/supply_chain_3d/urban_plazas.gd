extends RefCounted
## Concrete within 20u of urban non-house footprints, clipped to free dry ground.
## Prepared once with scenery; all LODs paint the same polygons under shadows.
const Index := preload("res://scripts/supply_chain_3d/road_index.gd")
const Fit := preload("res://scripts/supply_chain_3d/road_placement.gd")
const Coast := preload("res://scripts/supply_chain_3d/coast.gd")
const Clip := preload("res://scripts/supply_chain_3d/sea_fringe.gd")
const Legacy := preload("res://scripts/empire_board.gd")
const Trial := preload("res://scripts/supply_chain_3d/stoneshore_trial.gd")
const Walks := preload("res://scripts/supply_chain_3d/urban_sidewalks.gd")
const PAVING := Color("b6b8ad")
const REACH := 20.0

static func eligible(s: Dictionary, key: String) -> bool:
	if s.has("harbour") or s.kind in ["pylon","site","port"] or key.is_empty():return false
	if s.get("internal_name","") in ["farm","farm_building","mine"]:return false
	if s.get("decor_family","") in ["civic_semi","civic_park","civic_grove","civic_pond","civic_plaza"]:return false
	if key.begins_with("house_lvl1") or key.begins_with("house_lvl2") or key.begins_with("terrace"):return false
	return true

static func polygons(s: Dictionary, key: String) -> Array:
	if s.has("harbour"):return [s.harbour.main_quay]+s.harbour.quays
	if s.get("internal_name","") in ["farm","farm_building","mine"] and s.has("footprint"):return [s.footprint]
	return preload("res://scripts/supply_chain_3d/rail_clearance.gd").building_polygons(s,key)

static func _index(polys: Array) -> Dictionary:
	var result := {}
	for i in polys.size():
		if polys[i].size()>2:Index.insert(result,Fit.polygon_bounds(polys[i]),i)
	return result

static func build(builder: RefCounted, standing: Array) -> Dictionary:
	var result := {"tiles":{},"targets":0,"area":0.0}
	if not Trial.preview_enabled():return result
	var targets: Array=[];var obstacles: Array=[]
	for s in standing:
		var key := str(builder.standing_key(s))
		if key.is_empty() and not s.has("harbour"):continue
		var shapes := polygons(s,key)
		for shape in shapes:
			if shape.size()<3:continue
			obstacles.append_array(Geometry2D.offset_polygon(shape,.5))
		if builder.tiles.get(str(s.tile),{}).get("type","")!="urban" or not eligible(s,key):continue
		result.targets+=1
		for shape in shapes:targets.append_array(Geometry2D.offset_polygon(shape,REACH,Geometry2D.JOIN_ROUND))
	for site in builder.neighbourhood.get("brownfields",[]):obstacles.append(site.polygon)
	for station in builder.stations:obstacles.append(preload("res://scripts/supply_chain_3d/rail_station.gd").polygon(station))
	for depot in builder.depots:obstacles.append(preload("res://scripts/supply_chain_3d/rail_depot.gd").yard_polygon(depot))
	for road in builder.road_grade.segments:
		if road.get("tunnel",false):continue
		obstacles.append(Legacy._capsule(road.a,road.b,float(road.half)+Walks.width(road)+.6,[true,true]))
	for track in builder.rail_urban.tracks:
		if not track.hidden:obstacles.append(Legacy._capsule(track.a,track.b,7.7,[true,true]))
	var target_index := _index(targets);var obstacle_index := _index(obstacles)
	for tid in builder.tiles:
		var tile: Dictionary=builder.tiles[tid]
		if tile.type!="urban":continue
		var polygons_out: Array=[]
		var hex := preload("res://scripts/empire_board_model.gd").hex_points(tile.center)
		var water := Coast.Water.for_tile(tid)
		var bounds := Fit.polygon_bounds(hex)
		const CELL := 12.0
		for y in range(floori(bounds.position.y/CELL),ceili(bounds.end.y/CELL)):
			for x in range(floori(bounds.position.x/CELL),ceili(bounds.end.x/CELL)):
				var p := Vector2(x,y)*CELL
				var rect := Rect2(p,Vector2.ONE*CELL)
				var ids := Index.query(target_index,rect)
				if ids.is_empty():continue
				var square := PackedVector2Array([p,p+Vector2(CELL,0),p+Vector2(CELL,CELL),p+Vector2(0,CELL)])
				var remaining: Array=Geometry2D.intersect_polygons(square,hex)
				var covered: Array=[]
				for id in ids:
					var next: Array=[]
					for part in remaining:
						covered.append_array(Geometry2D.intersect_polygons(part,targets[id]))
						next.append_array(Clip._subtract(part,targets[id]))
					remaining=next
				var dry: Array=[]
				for part in covered:
					for land in water.land:dry.append_array(Geometry2D.intersect_polygons(part,land))
				var cuts: Array=water.lakes.duplicate()
				for id in Index.query(obstacle_index,rect):cuts.append(obstacles[id])
				for cut in cuts:
					var next: Array=[]
					for part in dry:next.append_array(Clip._subtract(part,cut))
					dry=next
					if dry.is_empty():break
				for part in dry:
					var area := Clip.area(part)
					if area<.02:continue
					polygons_out.append(part);result.area+=area
		result.tiles[tid]=polygons_out
	return result
