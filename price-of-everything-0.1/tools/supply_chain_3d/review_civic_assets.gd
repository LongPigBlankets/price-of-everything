extends Node
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const Civic := preload("res://scripts/supply_chain_3d/civic_layout.gd")

func _ready() -> void:
	SaveLoad.autosave_enabled = false
	TelemetryState.enabled = false
	var output := "res://../outputs/supply-chain-3d/civic/assets"
	var compare := "--style-comparison" in OS.get_cmdline_user_args()
	if compare: output = "res://../outputs/supply-chain-3d/civic/style"
	DirAccess.make_dir_recursive_absolute(output)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1800, 650) if compare else Vector2i(1800, 1200)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 170.0 if compare else 17.5
	viewport.add_child(camera)
	camera.position = Vector3(0, 220, 280) if compare else Vector3(2, 22, 26)
	camera.look_at(Vector3(0, 16 if compare else 1, 0)); camera.current = true
	Assets.set_grade(Vector2(-100000, 100000))
	var roots: Array = []
	var keys := ["civic_office_lvl1", "civic_office_lvl2", "civic_l_lvl1", "civic_park_lvl1", "civic_plaza_lvl1"]
	if compare: keys = ["house_lvl1", "house_lvl3", "civic_office_lvl1", "civic_office_lvl2", "civic_l_lvl1"]
	for i in keys.size():
		Assets.key_for(keys[i].get_slice("_lvl", 0), 2)
		var node := Node3D.new()
		var side := 6.0
		if compare: side = 72.0 if i < 2 else Civic.side_for(keys[i].get_slice("_lvl", 0), int(keys[i].get_slice("_lvl", 1)))
		node.scale = Vector3.ONE * side
		node.position = Vector3((i - 2) * 82, 0, 0) if compare else (Vector3((i - 1) * 7.5, 0, -4) if i < 3 else Vector3((i - 3.5) * 9, 0, 4))
		for mesh in [Assets.mesh_for(keys[i]), Assets.contour_for(keys[i])]:
			if mesh == null: continue
			var visual := MeshInstance3D.new(); visual.mesh = mesh
			node.add_child(visual)
		viewport.add_child(node); roots.append(node)
		if compare:
			var label := Label.new()
			label.text = ["Existing terrace", "Existing flats", "Long office", "Stepped office", "L-shaped block"][i]
			label.position = Vector2(20 + i * 350, 555)
			label.size = Vector2(330, 60); label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.add_theme_font_size_override("font_size", 23)
			viewport.add_child(label)
	for view in ["front", "back"]:
		for node in roots: node.rotation.y = 0.25 if view == "front" else PI + 0.25
		for i in 5:
			await get_tree().process_frame
			RenderingServer.force_draw(false)
		viewport.get_texture().get_image().save_png(output.path_join(view + ".png"))
	print("[CIVIC ASSETS] ", output)
	get_tree().quit()
