extends Node
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")

func _ready() -> void:
	SaveLoad.autosave_enabled = false
	TelemetryState.enabled = false
	var output := "res://../outputs/supply-chain-3d/civic/modular-assets"
	DirAccess.make_dir_recursive_absolute(output)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1800, 1200)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 20.0
	viewport.add_child(camera)
	camera.position = Vector3(0, 24, 30)
	camera.look_at(Vector3(0, 1, 0)); camera.current = true
	Assets.set_grade(Vector2(-100000, 100000))
	var roots: Array = []
	var keys := ["civic_long_04_lvl1", "civic_long_07_lvl1", "civic_long_10_lvl1",
		"civic_corner_04x02_lvl1", "civic_corner_06x03_lvl1", "civic_corner_08x04_lvl1"]
	var labels := ["4 columns", "7 columns", "10 columns", "4 + 2 columns", "6 + 3 columns", "8 + 4 columns"]
	for i in keys.size():
		Assets.key_for(keys[i].get_slice("_lvl", 0), 1)
		var node := Node3D.new()
		# Same floor and bay size across the entire gallery; never fit each asset.
		node.scale = Vector3.ONE / Assets.storey_height(keys[i])
		node.position = Vector3((i % 3 - 1) * 9, 0, -5 if i < 3 else 5)
		for mesh in [Assets.mesh_for(keys[i]), Assets.contour_for(keys[i])]:
			var visual := MeshInstance3D.new(); visual.mesh = mesh
			node.add_child(visual)
		viewport.add_child(node); roots.append(node)
		var label := Label.new()
		label.text = labels[i]
		label.position = Vector2(130 + (i % 3) * 540, 180 if i < 3 else 1040)
		label.size = Vector2(460, 50); label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 25)
		viewport.add_child(label)
	for view in ["front", "back"]:
		for node in roots: node.rotation.y = .22 if view == "front" else PI + .22
		for i in 5:
			await get_tree().process_frame
			RenderingServer.force_draw(false)
		viewport.get_texture().get_image().save_png(output.path_join(view + ".png"))
	print("[CIVIC MODULES] ", output)
	get_tree().quit()
