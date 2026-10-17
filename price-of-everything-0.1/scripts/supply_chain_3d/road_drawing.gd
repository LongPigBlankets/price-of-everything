extends RefCounted
## One map-space drawing on a graded carrier per tile. Bridge/support geometry
## remains separate; the carrier retains the original sampled road elevations.
const Geo := preload("res://scripts/supply_chain_3d/geometry.gd")
const Compact := preload("res://scripts/supply_chain_3d/surface_compact.gd")
const Legacy := preload("res://scripts/empire_board.gd")
const Sidewalks := preload("res://scripts/supply_chain_3d/urban_sidewalks.gd")
const SHADER := preload("res://scripts/supply_chain_3d/road_drawing.gdshader")
const VERSION := 1
const PIXELS_PER_UNIT := 4.0

class Painter extends Node2D:
	var art: ArrayMesh
	func _draw() -> void: draw_mesh(art,null)

static func palette() -> Dictionary:
	var result := {}
	for pair in [[Sidewalks.EDGE,-2],[Sidewalks.PAVING,-1]]: result[pair[0].to_rgba32()]=pair[1]
	var colors := [Legacy._ROAD_EDGE,Legacy._ROAD_KERB,Legacy._ROAD_EDGE_IN,Legacy._ROAD_ASPHALT,Legacy._ROAD_MARK]
	for i in colors.size():
		for tint in [Color.WHITE,Legacy._UNPAVED]: result[(colors[i]*tint).to_rgba32()]=i
	return result

static func extract(source: ArrayMesh, cell: float) -> Dictionary:
	var art := Geo.Batch.new()
	var paint_bands := {}
	var extras := Geo.Batch.new()
	var planes := {}
	var bands := palette()
	if source==null or source.get_surface_count()==0: return {"mesh":ArrayMesh.new(),"extras":ArrayMesh.new(),"art":ArrayMesh.new(),"area":Rect2()}
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		var colors: PackedColorArray=arrays[Mesh.ARRAY_COLOR]
		var ids: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		if ids.is_empty():
			for i in points.size():ids.append(i)
		for t in range(0,ids.size(),3):
			var tri := [ids[t],ids[t+1],ids[t+2]]
			var colour: Color=colors[tri[0]]
			var paint := bands.has(colour.to_rgba32())
			for id in tri: paint=paint and colors[id].to_rgba32()==colour.to_rgba32()
			var a: Vector3=points[tri[0]];var b: Vector3=points[tri[1]];var c: Vector3=points[tri[2]]
			var area := absf(Vector2(b.x-a.x,b.z-a.z).cross(Vector2(c.x-a.x,c.z-a.z)))
			var n := (b-a).cross(c-a).normalized()
			paint=paint and area>0.000001 and absf(n.y)>0.05
			if not paint:
				for id in tri:
					extras.vertices.append(points[id]);extras.normals.append(normals[id]);extras.colors.append(colors[id])
				continue
			var band: int=bands[colour.to_rgba32()]
			if not paint_bands.has(band):paint_bands[band]=Geo.Batch.new()
			var paint_batch: RefCounted=paint_bands[band]
			for id in tri:
				paint_batch.vertices.append(Vector3(points[id].x,points[id].z,0));paint_batch.normals.append(Vector3.FORWARD);paint_batch.colors.append(colors[id])
			var center := Vector2(a.x+b.x+c.x,a.z+b.z+c.z)/(3.0*cell)
			var grid := Vector2i(center.floor())
			var half := 0 if center.y-grid.y<=center.x-grid.x else 1
			var key := Vector3i(grid.x,grid.y,half)
			# All bands use the same 3D height grid. The largest clipped triangle
			# gives the most numerically stable plane for the single carrier cell.
			if not planes.has(key) or area>planes[key].area:
				if n.y<0:n=-n
				a.y+=0.24-float(bands[colour.to_rgba32()])*0.08
				planes[key]={"p":a,"n":n,"area":area}
	for band in range(-2,5):
		if not paint_bands.has(band):continue
		art.vertices.append_array(paint_bands[band].vertices)
		art.normals.append_array(paint_bands[band].normals)
		art.colors.append_array(paint_bands[band].colors)
	var bounds := Rect2()
	var first := true
	for p in art.vertices:
		var xy := Vector2(p.x,p.y)
		bounds=Rect2(xy,Vector2.ZERO) if first else bounds.expand(xy);first=false
	if first:return {"mesh":ArrayMesh.new(),"extras":Compact.build(extras.mesh(),false),"art":ArrayMesh.new(),"area":Rect2()}
	bounds=bounds.grow(2.0)
	var carrier := Geo.Batch.new()
	for key in planes:
		var plane: Dictionary=planes[key]
		var offsets := [Vector2.ZERO,Vector2.RIGHT,Vector2.ONE] if key.z==0 else [Vector2.ZERO,Vector2.ONE,Vector2.DOWN]
		var vertices: Array[Vector3]=[]
		for offset in offsets:
			var p: Vector2=(Vector2(key.x,key.y)+offset)*cell
			var height: float=plane.p.y-(plane.n.x*(p.x-plane.p.x)+plane.n.z*(p.y-plane.p.z))/plane.n.y
			vertices.append(Vector3(p.x,height,p.y))
		carrier.triangle(vertices[0],vertices[2],vertices[1],Color.WHITE,plane.n)
	return {"mesh":Compact.build(carrier.mesh(bounds)),"extras":Compact.build(extras.mesh(),false),"art":art.mesh(),"area":bounds}

static func bake(host: Node, source: ArrayMesh, cell: float, max_width: int = 4096) -> Dictionary:
	var data := extract(source,cell)
	if not data.area.has_area():
		data.erase("art");data.version=VERSION;data.texture_bytes=0;return data
	assert(DisplayServer.get_name()!="headless","Road drawing bakes need a renderer")
	var viewport := SubViewport.new()
	var scale := minf(PIXELS_PER_UNIT,float(max_width)/maxf(data.area.size.x,data.area.size.y))
	viewport.size=Vector2i(maxi(4,ceili(data.area.size.x*scale/4.0)*4),maxi(4,ceili(data.area.size.y*scale/4.0)*4))
	viewport.disable_3d=true;viewport.transparent_bg=true;viewport.msaa_2d=Viewport.MSAA_4X
	viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	host.add_child(viewport)
	var painter := Painter.new();painter.art=data.art
	painter.scale=Vector2(viewport.size)/data.area.size
	painter.position=-data.area.position*painter.scale
	viewport.add_child(painter)
	await host.get_tree().process_frame
	RenderingServer.force_draw(false)
	var picture := viewport.get_texture().get_image()
	assert(picture!=null and not picture.is_empty())
	picture.generate_mipmaps()
	# Native block compression keeps the new drawing from becoming a large
	# RGBA allocation on every resident medium tile. Conversion is bake-only.
	assert(picture.compress(Image.COMPRESS_BPTC)==OK)
	data.texture=ImageTexture.create_from_image(picture)
	data.texture_bytes=picture.get_data_size()
	data.version=VERSION;data.erase("art")
	viewport.queue_free()
	return data

static func material(base: ShaderMaterial, drawing: Dictionary) -> ShaderMaterial:
	var result := base.duplicate() as ShaderMaterial
	result.shader=SHADER
	result.set_shader_parameter("artwork",drawing.texture)
	result.set_shader_parameter("textured",true)
	result.set_meta("road",true)
	return result
