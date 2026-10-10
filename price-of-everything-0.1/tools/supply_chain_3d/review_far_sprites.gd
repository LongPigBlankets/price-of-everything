extends Node
## Render regression: mesh and sprite rows share the same world scales and lighting.
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const Far := preload("res://scripts/supply_chain_3d/far_sprites.gd")
const Rig := preload("res://scripts/supply_chain_3d/orbit_camera.gd")
const OUT := "res://../outputs/supply-chain-3d/far-sprites/"
var viewport: SubViewport
func _ready() -> void:
	TelemetryState.enabled = false
	SaveLoad.autosave_enabled = false
	preload("res://tools/shot_harness.gd").arm_watchdog(self, 90.0)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1600, 1000)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	add_child(viewport)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("999a65")
	viewport.add_child(env)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.current = true
	var grade := Vector2(-100000, 100000)
	Assets.set_grade(grade)
	var keys := ["tree_lvl1", "tree_lvl2", "tree_lvl3", "house_lvl1", "house_lvl3", "towers_lvl2",
		"warehouse_lvl1", "industrial_factory_lvl1", "industrial_factory_lvl3", "furnace_lvl3", "petro_refinery_lvl3", "mine_flush_lvl3"]
	var solids := Node3D.new()
	var cards := Node3D.new()
	viewport.add_child(solids)
	viewport.add_child(cards)
	for i in keys.size():
		var key: String = keys[i]
		Assets.key_for(key.get_slice("_lvl", 0), 3)
		var scale := float(Far.entry(key).reference_scale)
		var foot := Vector3((i % 6 - 2.5) * 170.0, 0, (i / 6 - 0.5) * 230.0)
		var mesh := MeshInstance3D.new()
		mesh.mesh = Assets.mesh_for(key)
		mesh.scale = Vector3.ONE * scale
		mesh.position = foot
		if key.begins_with("tree_"): mesh.material_override = Assets.tree_material(key == "tree_lvl2")
		solids.add_child(mesh)
		var outline := MeshInstance3D.new()
		outline.mesh = Assets.contour_for(key)
		outline.scale = mesh.scale
		outline.position = foot
		solids.add_child(outline)
		var card := Far.instance(key, grade)
		card.scale = mesh.scale
		card.position = foot + Far.center(key) * scale
		cards.add_child(card)
	var rig := Rig.new()
	rig.target = Vector3(0, 35, 0)
	rig.span = 1200.0
	var measurements := []
	for pitch in [Rig.MIN_PITCH, Rig.HOME_PITCH, Rig.MAX_PITCH]:
		for angle in [Rig.HOME_YAW, Rig.HOME_YAW + PI * 0.5]:
			rig.pitch = pitch
			rig.yaw = angle
			rig.apply(camera)
			for mode in ["meshes", "sprites"]:
				solids.visible = mode == "meshes"
				cards.visible = not solids.visible
				for j in 3: await get_tree().process_frame
				RenderingServer.force_draw(false)
				var image := viewport.get_texture().get_image()
				image.save_png(OUT + "comparison_%.2f_%.2f_%s.png" % [pitch, angle, mode])
				measurements.append({"pitch": pitch, "yaw": angle, "mode": mode,
					"triangles": viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)})
	FileAccess.open(OUT + "comparison_metrics.json", FileAccess.WRITE).store_string(JSON.stringify(measurements, "\t"))
	get_tree().quit()
