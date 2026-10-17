extends RefCounted
## A continuous coastal margin around the visible tile perimeter. It is scenery,
## not another playable tile, and never requests that tile's buildings/detail.
const Model := preload("res://scripts/empire_board_model.gd")
const Coast := preload("res://scripts/supply_chain_3d/coast.gd")
const Ground := preload("res://scripts/empire_board_ground.gd")
const Geo := preload("res://scripts/supply_chain_3d/geometry.gd")
const Legacy := preload("res://scripts/empire_board.gd")
const FRACTION := .10
const WIDTH := Model.HEX_HALF.y * 2 * FRACTION
var strips: Array=[]
var owned := {}

func configure(tiles: Dictionary, geography: Dictionary) -> void:
	strips.clear();owned=tiles
	if not preload("res://scripts/supply_chain_3d/stoneshore_trial.gd").preview_enabled():return
	var neighbours := {}
	for tid in tiles:
		for nb in Catalog.tile_neighbours(tid):
			if not tiles.has(nb) and geography.has(nb) and Catalog.tile_type(nb) in ["sea","deep_sea"]:
				neighbours[nb]=geography[nb].center
	strips=margin_parts(tiles.values().map(func(tile):return Model.hex_points(tile.center)),neighbours)

static func margin_parts(hexes: Array, neighbours: Dictionary) -> Array:
	# Offset the union once: separately extruded edges pinch at re-entrant
	# corners and miss the third neighbouring hex at convex corners. Round joins
	# keep the nearest-boundary distance constant, including around vertices.
	var outlines: Array=[]
	for hex in hexes:
		var joined: PackedVector2Array=hex
		var i := 0
		while i<outlines.size():
			var merged := Geometry2D.merge_polygons(outlines[i],joined)
			if merged.size()==1:joined=merged[0];outlines.remove_at(i);i=0
			else:i+=1
		outlines.append(joined)
	var parts: Array=[]
	for outline in outlines:
		for expanded in Geometry2D.offset_polygon(outline,WIDTH,Geometry2D.JOIN_ROUND):
			for tid in neighbours:
				for poly in Geometry2D.intersect_polygons(expanded,Model.hex_points(neighbours[tid])):
					parts.append({"tile":tid,"center":neighbours[tid],"width":WIDTH,"p":poly})
	return parts

func contains(p: Vector2) -> bool:
	for strip in strips:
		if Geometry2D.is_point_in_polygon(p,strip.p):return true
	return false

func _visible(p: Vector2) -> bool:
	for tile in owned.values():
		if Geometry2D.is_point_in_polygon(p,Model.hex_points(tile.center)):return true
	return contains(p)

static func water_parts(poly: PackedVector2Array, land: Array) -> Array:
	var parts: Array=[poly]
	for mask in land:
		var next: Array=[]
		for part in parts: next.append_array(_subtract(part,mask))
		parts=next
	return parts.filter(func(part):return area(part)>.05)

static func margin_water(poly: PackedVector2Array, land: Array) -> Array:
	# Tiny isolated pockets at the clipping boundary would become conspicuous
	# 175u-tall pillars. Filter the full water component, never individual grid
	# cells, so normal coastlines retain their fine detail.
	return water_parts(poly,land).filter(func(part):return area(part)>=16.0)

static func area(poly: PackedVector2Array) -> float:
	# Translate before the shoelace sum to avoid cancellation in world coordinates.
	var result := 0.0
	for i in range(1,poly.size()-1):result+=(poly[i]-poly[0]).cross(poly[i+1]-poly[0])
	return absf(result)*.5

static func rim_uvs(a: float, b: float, top: float, end_top := -1.0) -> PackedVector2Array:
	var u := a/270.0;var v := b/270.0
	if end_top<0:end_top=top
	return PackedVector2Array([Vector2(u,top),Vector2(v,1),Vector2(v,end_top),Vector2(u,top),Vector2(u,1),Vector2(v,1)])

static func _subtract(poly: PackedVector2Array, mask: PackedVector2Array) -> Array:
	var parts := Geometry2D.clip_polygons(poly,mask)
	# Godot emits holes as separate clockwise rings. Split through any island
	# before triangulating so ignoring that ring cannot fill neighbouring land.
	for hole in parts:
		if not Geometry2D.is_polygon_clockwise(hole):continue
		var box := Rect2(poly[0],Vector2.ZERO);var hole_box := Rect2(hole[0],Vector2.ZERO)
		for p in poly:box=box.expand(p)
		for p in hole:hole_box=hole_box.expand(p)
		var cut := hole_box.get_center().x
		var result: Array=[]
		for bounds in [Rect2(box.position-Vector2.ONE,Vector2(cut-box.position.x+1,box.size.y+2)),Rect2(Vector2(cut,box.position.y-1),Vector2(box.end.x-cut+1,box.size.y+2))]:
			var rect := PackedVector2Array([bounds.position,bounds.position+Vector2(bounds.size.x,0),bounds.end,bounds.position+Vector2(0,bounds.size.y)])
			for section in Geometry2D.intersect_polygons(poly,rect):result.append_array(_subtract(section,mask))
		return result
	return parts

static func paint_layers(poly: PackedVector2Array, base: Color, layers: Array) -> Array:
	var pieces: Array=[{"p":poly,"color":base}]
	for layer in layers:
		var next: Array=[]
		for piece in pieces:
			var over := Geometry2D.intersect_polygons(piece.p,layer.p)
			if over.is_empty():next.append(piece);continue
			for p in _subtract(piece.p,layer.p):next.append({"p":p,"color":piece.color})
			for p in over:next.append({"p":p,"color":layer.color})
		pieces=next
	return pieces

static func polygon(batch: RefCounted, poly: PackedVector2Array, color: Color, origin: Vector2, height: float, sample := Callable(), gradient := Callable(), cached: Dictionary = {}) -> void:
	if poly.size()<3 or Geometry2D.is_polygon_clockwise(poly):return
	var local := PackedVector2Array()
	for p in poly:local.append(p-poly[0])
	var indices := Geometry2D.triangulate_polygon(local)
	for i in range(0,indices.size(),3):
		var v: Array=[]
		for j in [0,2,1]:
			var q: Vector2=poly[indices[i+j]]-origin
			if not cached.has(poly[indices[i+j]]):
				var p: Vector2=poly[indices[i+j]]
				var grad: Vector2=gradient.call(p) if gradient.is_valid() else Vector2.ZERO
				cached[p]={"height":float(sample.call(p)) if sample.is_valid() else height,"normal":Vector3(-grad.x,1,-grad.y).normalized()}
			v.append(Vector3(q.x,cached[poly[indices[i+j]]].height,q.y))
		var before: int=batch.vertices.size()
		batch.triangle(v[0],v[1],v[2],color,Vector3.UP)
		if batch.vertices.size()>before:
			for j in 3:batch.normals[before+j]=cached[poly[indices[i+j]]].normal

func bake(origin: Vector2, height: Callable, gradient: Callable) -> Dictionary:
	var top := Geo.Batch.new();var rim := Geo.Batch.new();var lip := Geo.Batch.new()
	var sea := MapStyle.sea_colors();var h := Ground.SEA_LEVEL
	var vertex_cache := {};var surface_area := 0.0;var land_area := 0.0;var rim_segments := 0
	var by_tile := {}
	for strip in strips:
		var group: Array=by_tile.get_or_add(strip.tile,[])
		var merged: PackedVector2Array=strip.p
		for i in range(group.size()-1,-1,-1):
			var union := Geometry2D.merge_polygons(group[i],merged)
			if union.size()==1:merged=union[0];group.remove_at(i)
		group.append(merged)
	for tid in by_tile:
		var center: Vector2
		for strip in strips:
			if strip.tile==tid:center=strip.center;break
		var rel := Coast.relief_of(tid,center)
		var layers: Array=[]
		for e in rel.get("sea",[]):
			layers.append({"p":e.p,"color":sea[int(e.b)]})
		for e in rel.land:
			layers.append({"p":e.p,"color":Legacy._warm(sea[5] if e.get("beach",false) else preload("res://scripts/supply_chain_3d/half_relief.gd").color(float(e.b),MapStyle.band_colors()))})
		var tones := {"shallows_outer":sea[4].lightened(.14),"shallows_inner":sea[4].lightened(.3),"sand":Legacy._SAND,"shore":Legacy._SAND.darkened(.16),"foam":Legacy._FOAM,"lake_sand":Legacy._SAND.darkened(.08),"lake_foam":sea[4].lightened(.3)}
		for ink in rel.water_ink:
			if tones.has(ink.tone):layers.append({"p":ink.p,"color":tones[ink.tone]})
		# Keep the complete envelope, including coastal land. Removing land here
		# leaves a void between the selected hex and the true cross-tile shoreline.
		for mask in by_tile[tid]:
			surface_area+=area(mask)
			for land in Coast.Water.for_tile(tid).land:
				for piece in Geometry2D.intersect_polygons(mask,land):land_area+=area(piece)
			var box := Rect2(mask[0],Vector2.ZERO)
			for p in mask:box=box.expand(p)
			const CELL := 4.0
			for y in range(floori(box.position.y/CELL),ceili(box.end.y/CELL)):
				for x in range(floori(box.position.x/CELL),ceili(box.end.x/CELL)):
					var a := Vector2(x,y)*CELL
					var square := PackedVector2Array([a,a+Vector2(CELL,0),a+Vector2(CELL,CELL),a+Vector2(0,CELL)])
					for cell in Geometry2D.intersect_polygons(square,mask):
						for piece in paint_layers(cell,sea[0 if Catalog.tile_type(tid)=="deep_sea" else 2],layers):
							polygon(top,piece.p,piece.color,origin,h,height,gradient,vertex_cache)
		# Cutaways belong only to the outer preview boundary, never the coastline.
		for poly in by_tile[tid]:
			var perimeter := 0.0
			for i in poly.size():
				var a: Vector2=poly[i];var b: Vector2=poly[(i+1)%poly.size()]
				var edge_length := a.distance_to(b)
				var start := perimeter;perimeter+=edge_length
				if edge_length<.01:continue
				var n := (b-a).orthogonal().normalized()*.2
				var count := maxi(1,ceili(a.distance_to(b)/4))
				for j in count:
					var p := a.lerp(b,float(j)/count);var q := a.lerp(b,float(j+1)/count);var middle := (p+q)*.5
					if _visible(middle+n) and _visible(middle-n):continue
					rim_segments+=1
					var wet := Ground.is_water(rel,middle)
					var depth := Legacy._WATER_DEPTH if wet else Legacy._TURF
					var v := Vector3(p.x-origin.x,float(height.call(p)),p.y-origin.y);var w := Vector3(q.x-origin.x,float(height.call(q)),q.y-origin.y)
					lip.quad(v,w,w-Vector3.UP*depth,v-Vector3.UP*depth,sea[3] if wet else Legacy._warm(sea[5]).darkened(.38))
					v.y-=depth;w.y-=depth
					rim.quad(v,w,Vector3(w.x,-150,w.z),Vector3(v.x,-150,v.z),Color.WHITE)
					var uv := (100-v.y)/250.0
					rim.uvs.append_array(rim_uvs(start+edge_length*j/count,start+edge_length*(j+1)/count,uv,(100-w.y)/250.0))
	return {"top":top.mesh(),"lip":lip.mesh(),"rim":rim.mesh(),"audit":{"surface_area":surface_area,"coastal_land_area":land_area,"rim_segments":rim_segments}}
