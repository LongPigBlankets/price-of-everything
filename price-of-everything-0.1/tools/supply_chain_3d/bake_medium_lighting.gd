extends "res://tools/supply_chain_3d/bake_far_sprites.gd"
## AGENT_GODOT_WINDOW=1 godot --path . res://tools/supply_chain_3d/bake_medium_lighting.tscn -- --no-telemetry
## Reuses the unlit atlas framing/depth. Only the lit colour variant is new.
func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Lighting sprites require a rendered run")
		get_tree().quit(1)
		return
	preload("res://tools/shot_harness.gd").arm_watchdog(self, 900.0)
	SaveLoad.autosave_enabled = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--asset-keys="): selected_keys = arg.trim_prefix("--asset-keys=").split(",")
	output = "res://assets/supply_chain_3d/medium_sprites/"
	DirAccess.make_dir_recursive_absolute(Assets.DIRECTORY + "picking")
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Assets.DIRECTORY + "manifest.json"))
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output + "manifest.json"))
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = 0.01
	camera.far = 50.0
	viewport.add_child(camera)
	camera.current = true
	source = MeshInstance3D.new()
	contour = MeshInstance3D.new()
	viewport.add_child(source)
	viewport.add_child(contour)
	var outline := ShaderMaterial.new()
	outline.shader = Shader.new()
	outline.shader.code = FileAccess.get_file_as_string("res://scripts/supply_chain_3d/contour.gdshader").replace(
		"ink *= mix(vec3(0.66, 0.74, 1.0), vec3(1.0, 0.92, 0.72), t);", "")
	if outline.shader.get_shader_uniform_list().is_empty():
		push_error("Outline shader failed to compile; sprite bake aborted")
		get_tree().quit(1)
		return
	contour.material_override = outline
	for key in catalog:
		if not selected_keys.is_empty() and key not in selected_keys: continue
		if str(key).begins_with("tree_"): continue
		Assets.key_for(str(key).get_slice("_lvl", 0), 3)
		source.mesh = Assets.mesh_for(key)
		if "--colour-only" not in OS.get_cmdline_user_args():
			var shape := source.mesh.create_trimesh_shape()
			shape.set_meta("source_sha256", FileAccess.get_sha256(Assets.DIRECTORY + key + ".glb"))
			assert(ResourceSaver.save(shape, Assets.DIRECTORY + "picking/" + key + ".res", ResourceSaver.FLAG_COMPRESS) == OK)
		if str(key).begins_with("mine_") or str(key).begins_with("mine_flush_") or str(key).begins_with("pylon_"): continue
		var entry: Dictionary = manifest.assets[key]
		contour.mesh = Assets.contour_for(key)
		var center := source.mesh.get_aabb().get_center()
		var cell := int(entry.cell)
		var yaws := int(entry.get("yaws", YAWS))
		viewport.size = Vector2i.ONE * cell
		camera.size = float(entry.span)
		var paint := ShaderMaterial.new()
		paint.shader = Shader.new()
		paint.shader.code = FileAccess.get_file_as_string("res://scripts/supply_chain_3d/building_print.gdshader").replace(
			"paint *= mix(vec3(0.66, 0.74, 1.0), vec3(1.0, 0.92, 0.72), t);", "")
		paint.set_shader_parameter("stipple_strength", 0.10)
		paint.set_shader_parameter("detail_level", 1)
		paint.set_shader_parameter("lit_windows", true)
		paint.set_shader_parameter("curtain_wall", str(key).begins_with("towers_"))
		source.material_override = paint
		var colour := Image.create(cell * yaws, cell * PITCHES, false, Image.FORMAT_RGBA8)
		for pitch_index in PITCHES:
			var pitch := lerpf(Rig.MIN_PITCH, Rig.MAX_PITCH, float(pitch_index) / (PITCHES - 1))
			for yaw_index in yaws:
				var yaw := TAU * yaw_index / yaws
				var direction := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
				camera.position = center + direction * 12.0
				camera.look_at(center)
				camera.force_update_transform()
				await get_tree().process_frame
				RenderingServer.force_draw(false)
				var frame := viewport.get_texture().get_image()
				_straight_alpha(frame)
				colour.blit_rect(frame, Rect2i(0, 0, cell, cell), Vector2i(yaw_index, pitch_index) * cell)
		var path: String = key + "_lit.png"
		assert(colour.save_png(output + path) == OK)
		entry.lit_texture = path
		entry.lit_source_sha256 = FileAccess.get_sha256(Assets.DIRECTORY + key + ".glb")
		FileAccess.open(output + "manifest.json", FileAccess.WRITE).store_string(JSON.stringify(manifest, "\t") + "\n")
		print("[MEDIUM LIGHTING] ", key)
	get_tree().quit()
