extends Node
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const Fields := preload("res://scripts/supply_chain_3d/farm_fields.gd")

func _ready() -> void:
	SaveLoad.autosave_enabled = false
	TelemetryState.enabled = false
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1600, 1000)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 28.0
	viewport.add_child(camera)
	camera.position = Vector3(12, 25, 22)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	Assets.set_grade(Vector2(-100000, 100000))
	var key := Assets.key_for("farm_crop_cell", 1)
	var node := MeshInstance3D.new()
	node.mesh = Assets.mesh_for(key)
	node.scale = Vector3.ONE * Fields.SIDE
	node.position.x = -9.0
	viewport.add_child(node)
	var medium := MeshInstance3D.new()
	medium.mesh = Assets.mesh_for(Assets.key_for("farm_crop_cell_medium", 1))
	medium.scale = Vector3.ONE * Fields.SIDE
	viewport.add_child(medium)
	var multi := Fields.cells({"poses": [Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * Fields.SIDE), Vector3(9, 0, 0))]}, false)
	viewport.add_child(multi)
	for i in 8:
		await get_tree().process_frame
		RenderingServer.force_draw(false)
	var output := "res://../outputs/supply-chain-3d/farms/components.png"
	viewport.get_texture().get_image().save_png(output)
	print("[FARM COMPONENTS] ", output)
	get_tree().quit()
