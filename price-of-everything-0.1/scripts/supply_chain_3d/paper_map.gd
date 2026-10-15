extends Node3D
## One inexpensive instanced paper surface. No textures, terrain sampling or physics.
const Model := preload("res://scripts/empire_board_model.gd")
const Geo := preload("res://scripts/supply_chain_3d/geometry.gd")
const PaperShader := preload("res://scripts/supply_chain_3d/paper_map.gdshader")
const HEIGHT := -2.0
const InkShader := preload("res://scripts/supply_chain_3d/loading_ink.gdshader")
const Reveal := preload("res://scripts/supply_chain_3d/tile_reveal.gd")
var drawings := {}
var tiles := {}
var indices := {}
var covered := {}
var multimesh: MultiMesh

func configure(centres: Dictionary) -> void:
	tiles = centres.duplicate()
	var batch := Geo.Batch.new()
	var hex := Model.hex_points(Vector2.ZERO)
	for i in 6:
		batch.triangle(Vector3.ZERO, Vector3(hex[i].x,0,hex[i].y),
			Vector3(hex[(i+1)%6].x,0,hex[(i+1)%6].y), Color.WHITE, Vector3.UP)
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = batch.mesh()
	multimesh.instance_count = tiles.size()
	for tid in tiles:
		indices[tid] = indices.size()
		multimesh.set_instance_transform(indices[tid], _transform(tid, false))
	var surface := MultiMeshInstance3D.new()
	surface.name = "PaperHexes"
	surface.multimesh = multimesh
	var material := ShaderMaterial.new()
	material.shader = PaperShader
	surface.material_override = material
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(surface)
	# The local terrain has open edges while its neighbours are missing. A sheet
	# underneath prevents those edges exposing the viewport's navy clear colour.
	var bounds := Rect2()
	for p in centres.values(): bounds = bounds.expand(p)
	bounds = bounds.grow(600.0)
	var sheet := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = bounds.size
	sheet.mesh = plane
	sheet.position = Vector3(bounds.get_center().x,-512.0,bounds.get_center().y)
	sheet.material_override = material.duplicate()
	sheet.material_override.set_shader_parameter("draw_grid", false)
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sheet)

func _transform(tid: String, hidden: bool) -> Transform3D:
	var p: Vector2 = tiles[tid]
	return Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * (0.0 if hidden else 1.0)), Vector3(p.x,HEIGHT,p.y))

func cover(ready: Dictionary) -> void:
	for tid in tiles:
		if ready.has(tid) == covered.has(tid): continue
		multimesh.set_instance_transform(indices[tid], _transform(tid, ready.has(tid)))
		if ready.has(tid) and drawings.has(tid):
			drawings[tid].node.queue_free(); drawings.erase(tid)
	covered.clear()
	for tid in ready: covered[tid] = true

func pick(from: Vector3, direction: Vector3) -> Dictionary:
	if absf(direction.y) < 0.0001: return {}
	var distance := (HEIGHT-from.y)/direction.y
	if distance < 0: return {}
	var at := from + direction * distance
	var p := Vector2(at.x,at.z)
	for tid in tiles:
		if covered.has(tid) or p.distance_squared_to(tiles[tid]) > Model.HEX_HALF.length_squared(): continue
		if Geometry2D.is_point_in_polygon(p, Model.hex_points(tiles[tid])):
			return {"collider":self, "position":at, "tile_id":tid, "tiles_only":true}
	return {}

func draw_tile(tid: String, mesh: ArrayMesh) -> void:
	if covered.has(tid) or drawings.has(tid) or mesh.get_surface_count()==0: return
	var node := MeshInstance3D.new()
	node.name = "Ink_"+tid
	node.mesh = mesh
	var at: Vector2 = tiles[tid]
	node.position = Vector3(at.x,HEIGHT+0.2,at.y)
	var material := ShaderMaterial.new(); material.shader = InkShader
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	drawings[tid] = {"node":node,"material":material,"elapsed":0.0}

func set_time(tid: String, seconds: float) -> void:
	if not drawings.has(tid): return
	var drawing: Dictionary = drawings[tid]
	drawing.elapsed = seconds
	drawing.material.set_shader_parameter("progress",Reveal.ink_progress(seconds))
	drawing.material.set_shader_parameter("opacity",1.0-Reveal.detail_progress(seconds))

func clear_drawings() -> void:
	for drawing in drawings.values(): drawing.node.queue_free()
	drawings.clear()
