extends Node
## Render the installed asset with the game's actual mesh/material loader.
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const Sprites := preload("res://scripts/building_sprites.gd")
const FX := preload("res://scripts/empire_fx.gd")
const OUT := "res://../outputs/furnace-l3-integration/game"

func _ready() -> void:
	SaveLoad.autosave_enabled = false
	TelemetryState.enabled = false
	preload("res://tools/shot_harness.gd").arm_watchdog(self, 90)
	DirAccess.make_dir_recursive_absolute(OUT)
	var vp := SubViewport.new()
	vp.size = Vector2i(1200, 900)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("ece0c6")
	vp.add_child(env)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 3000
	vp.add_child(camera)
	camera.current = true
	Assets.set_grade(Vector2(-100000, 100000))
	assert(Assets.key_for("furnace", 3) == "furnace_lvl3")
	var source_hash := FileAccess.get_sha256(Assets.DIRECTORY+"furnace_lvl3.glb")
	for tier in ["far_sprites", "medium_sprites"]:
		var atlas: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Assets.DIRECTORY+tier+"/manifest.json"))
		assert(atlas.assets.furnace_lvl3.source_sha256 == source_hash)
	var picking: Resource = load(Assets.DIRECTORY+"picking/furnace_lvl3.res")
	assert(picking.get_meta("source_sha256") == source_hash)
	var mesh := Assets.mesh_for("furnace_lvl3")
	var root := Node3D.new()
	root.scale = Vector3.ONE * 100
	vp.add_child(root)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	root.add_child(visual)
	var center := mesh.get_aabb().get_center() * 100
	camera.size = 125
	for yaw in [0, 1]:
		var direction := Vector3(1, 1, 1) if yaw == 0 else Vector3(-1, 1, -1)
		camera.position = center + direction.normalized()*500
		camera.look_at(center)
		await _shot(vp, "front" if yaw == 0 else "reverse")
	root.free()
	# Identical world scale and camera for the existing progression and factory.
	vp.size = Vector2i(1800, 700)
	camera.size = 180
	camera.position = Vector3(0, 240, 480)
	camera.look_at(Vector3(0, 35, 0))
	var keys := ["furnace_lvl1", "furnace_lvl2", "furnace_lvl3", "industrial_factory_lvl3"]
	var dimensions := {}
	for i in keys.size():
		var key: String = keys[i]
		Assets.key_for(key.get_slice("_lvl", 0), int(key.get_slice("_lvl", 1)))
		var node := Node3D.new()
		node.position.x = (i-1.5)*115
		node.scale = Vector3.ONE*100
		vp.add_child(node)
		for part in [Assets.mesh_for(key), Assets.contour_for(key)]:
			if part == null: continue
			var instance := MeshInstance3D.new()
			instance.mesh = part
			node.add_child(instance)
		dimensions[key] = str(Assets.dimensions(key)*100)
		var label := Label.new()
		label.text = key.replace("_", " ") + (" (replacement soon)" if i<2 else "")
		label.position = Vector2(i*450, 610)
		label.size.x = 360
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color",Color("243140"))
		vp.add_child(label)
	await _shot(vp, "common-scale")
	var report := {"dimensions_at_side_100":dimensions,"sprite_size":str(Sprites.texture_for("furnace",3).get_size()),"anchors":FX.anchors_for("furnace",3)}
	FileAccess.open(OUT+"/review.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("[FURNACE REVIEW] ",JSON.stringify(report))
	get_tree().quit()

func _shot(vp: SubViewport, name: String) -> void:
	for i in 6:
		await get_tree().process_frame
		RenderingServer.force_draw(false)
	assert(vp.get_texture().get_image().save_png(OUT+"/"+name+".png") == OK)
