extends RefCounted
## A water-only margin of one tenth of the adjacent hex depth. It is scenery,
## not another playable tile, and never requests that tile's buildings/detail.
const Model := preload("res://scripts/empire_board_model.gd")
const Coast := preload("res://scripts/supply_chain_3d/coast.gd")
const Ground := preload("res://scripts/empire_board_ground.gd")
const Geo := preload("res://scripts/supply_chain_3d/geometry.gd")
const Legacy := preload("res://scripts/empire_board.gd")
const FRACTION := .10
var strips: Array=[]
var owned := {}

func configure(tiles: Dictionary, geography: Dictionary) -> void:
	strips.clear();owned=tiles
	if not preload("res://scripts/supply_chain_3d/stoneshore_trial.gd").preview_enabled():return
	for tid in tiles:
		var center: Vector2=tiles[tid].center
		var hex := Model.hex_points(center)
		for nb in Catalog.tile_neighbours(tid):
			if tiles.has(nb) or not geography.has(nb) or Catalog.tile_type(nb) not in ["sea","deep_sea"]:continue
			var other: Vector2=geography[nb].center
			for i in 6:
				var a: Vector2=hex[i];var b: Vector2=hex[(i+1)%6]
				if (a+b-center).distance_to(other)>1:continue
				var middle := (a+b)*.5
				var out := (middle-center).normalized()
				var width := 2*middle.distance_to(center)*FRACTION
				var along := (b-a).normalized()*width
				var strip := PackedVector2Array([a-along,b+along,b+along+out*width,a-along+out*width])
				for poly in Geometry2D.intersect_polygons(strip,Model.hex_points(other)):
					strips.append({"tile":nb,"center":other,"width":width,"a":a,"b":b,"p":poly})

func contains(p: Vector2) -> bool:
	for strip in strips:
		if Geometry2D.is_point_in_polygon(p,strip.p) and Ground.is_water(Coast.relief_of(strip.tile,strip.center),p):return true
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
	return parts

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

static func polygon(batch: RefCounted, poly: PackedVector2Array, color: Color, origin: Vector2, height: float) -> void:
	if poly.size()<3 or Geometry2D.is_polygon_clockwise(poly):return
	var local := PackedVector2Array()
	for p in poly:local.append(p-poly[0])
	var indices := Geometry2D.triangulate_polygon(local)
	for i in range(0,indices.size(),3):
		var v: Array=[]
		for j in [0,2,1]:
			var q: Vector2=poly[indices[i+j]]-origin
			v.append(Vector3(q.x,height,q.y))
		batch.triangle(v[0],v[1],v[2],color,Vector3.UP)

func bake(origin: Vector2) -> Dictionary:
	var top := Geo.Batch.new();var rim := Geo.Batch.new();var lip := Geo.Batch.new()
	var sea := MapStyle.sea_colors();var h := Ground.SEA_LEVEL
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
		var land: Array=Coast.Water.for_tile(tid).land
		var water: Array=[]
		for mask in by_tile[tid]:water.append_array(water_parts(mask,land))
		# Grid cells avoid triangulating a polygon with an enclosed land hole.
		for mask in by_tile[tid]:
			var box := Rect2(mask[0],Vector2.ZERO)
			for p in mask:box=box.expand(p)
			for y in range(floori(box.position.y/24),ceili(box.end.y/24)):
				for x in range(floori(box.position.x/24),ceili(box.end.x/24)):
					var a := Vector2(x,y)*24
					var square := PackedVector2Array([a,a+Vector2(24,0),a+Vector2(24,24),a+Vector2(0,24)])
					for cell in Geometry2D.intersect_polygons(square,mask):
						for part in water_parts(cell,land):
							var layers: Array=[]
							for e in rel.get("sea",[]):
								if int(e.b)<5:layers.append({"p":e.p,"color":sea[int(e.b)]})
							var tones := {"shallows_outer":sea[4].lightened(.14),"shallows_inner":sea[4].lightened(.3),"sand":Legacy._SAND,"shore":Legacy._SAND.darkened(.16),"foam":Legacy._FOAM}
							for ink in rel.water_ink:
								if tones.has(ink.tone):layers.append({"p":ink.p,"color":tones[ink.tone]})
							for piece in paint_layers(part,sea[0 if Catalog.tile_type(tid)=="deep_sea" else 2],layers):
								polygon(top,piece.p,piece.color,origin,h)
		for poly in water:
			for i in poly.size():
				var a: Vector2=poly[i];var b: Vector2=poly[(i+1)%poly.size()]
				var n := (b-a).orthogonal().normalized()*.2
				var count := maxi(1,ceili(a.distance_to(b)/4))
				for j in count:
					var p := a.lerp(b,float(j)/count);var q := a.lerp(b,float(j+1)/count);var middle := (p+q)*.5
					if _visible(middle+n) and _visible(middle-n):continue
					var v := Vector3(p.x-origin.x,h,p.y-origin.y);var w := Vector3(q.x-origin.x,h,q.y-origin.y)
					lip.quad(v,w,w-Vector3.UP*Legacy._WATER_DEPTH,v-Vector3.UP*Legacy._WATER_DEPTH,sea[3])
					v.y-=Legacy._WATER_DEPTH;w.y=v.y
					rim.quad(v,w,Vector3(w.x,-150,w.z),Vector3(v.x,-150,v.z),Color.WHITE)
					var uv := (100-v.y)/250.0
					rim.uvs.append_array(PackedVector2Array([Vector2(float(j)/count,uv),Vector2(float(j+1)/count,1),Vector2(float(j+1)/count,uv),Vector2(float(j)/count,uv),Vector2(float(j)/count,1),Vector2(float(j+1)/count,1)]))
	return {"top":top.mesh(),"lip":lip.mesh(),"rim":rim.mesh()}
