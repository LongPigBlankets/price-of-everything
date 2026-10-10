extends Node
## Resource contract check, with an optional real-render sprite/mesh comparison.
const Sprites := preload("res://scripts/building_sprites.gd")
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const Harness := preload("res://tools/shot_harness.gd")
const FAMILIES: Array[String] = ["farm", "water_pump", "new_forest", "old_forest", "desal", "oil_well", "fracking_oil_well"]

func _ready() -> void:
	TelemetryState.enabled = false
	SaveLoad.autosave_enabled = false
	AudioServer.set_bus_mute(0, true)
	var failures: int = 0
	for family in FAMILIES:
		for level in range(1, 4):
			var texture: Texture2D = Sprites.texture_for(family, level)
			var key: String = Assets.key_for(family, level)
			var mesh: Mesh = Assets.mesh_for(key)
			if texture == null or texture.get_size() != Vector2(800, 800):
				push_error("Missing/wrong sprite: %s L%d" % [family, level])
				failures += 1
			if key != "%s_lvl%d" % [family, level] or mesh == null:
				push_error("Missing/exact-level mesh: %s L%d" % [family, level])
				failures += 1
			elif mesh.get_surface_count() < 1:
				push_error("Missing surface: " + key)
				failures += 1
			else:
				var format: int = mesh.surface_get_format(0)
				for flag in [Mesh.ARRAY_FORMAT_COLOR, Mesh.ARRAY_FORMAT_TEX_UV, Mesh.ARRAY_FORMAT_TEX_UV2, Mesh.ARRAY_FORMAT_NORMAL]:
					if (format & int(flag)) == 0:
						push_error("Missing shader attribute %s: %s" % [flag, key])
						failures += 1
			if Assets.contour_for(key) != null:
				push_error("Unexpected outer contour: " + key)
				failures += 1
	print("[building assets] %d sprites + %d meshes, no outer contours checked; failures=%d" % [FAMILIES.size() * 3, FAMILIES.size() * 3, failures])
	if failures > 0 or not "--capture" in OS.get_cmdline_user_args():
		get_tree().quit(1 if failures > 0 else 0)
		return
	if DisplayServer.get_name() == "headless":
		push_error("--capture requires a windowed rendering run")
		get_tree().quit(1)
		return
	var proof_size := Vector2i(1600, 100 + FAMILIES.size() * 150)
	Harness.prepare_window(get_window(), proof_size)
	Harness.arm_watchdog(self, 90.0)
	get_window().content_scale_size = proof_size
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	var background := ColorRect.new()
	background.color = Color("eee9db")
	background.size = Vector2(proof_size)
	add_child(background)
	var title := Label.new()
	title.text = "DETAILED BUILDINGS  /  SPRITE → LIVE GAME MESH  /  L1 · L2 · L3"
	title.position = Vector2(24, 14)
	title.add_theme_color_override("font_color", Color("2f3b59"))
	add_child(title)
	for row in FAMILIES.size():
		var label := Label.new()
		label.text = FAMILIES[row].replace("_", " ").to_upper()
		label.position = Vector2(18, 90 + row * 150)
		label.add_theme_color_override("font_color", Color("2f3b59"))
		label.add_theme_font_size_override("font_size", 16)
		add_child(label)
		for level in range(1, 4):
			var left: float = 180 + (level - 1) * 465
			var top: float = 52 + row * 150
			var sprite := TextureRect.new()
			sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			sprite.texture = Sprites.texture_for(FAMILIES[row], level)
			sprite.position = Vector2(left, top)
			sprite.size = Vector2(210, 140)
			sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			add_child(sprite)
			_add_mesh(FAMILIES[row], level, Vector2(left + 218, top))
	for i in range(12):
		await get_tree().process_frame
	# Capture the whole canvas on Retina displays; a pixel crop would cut off rows.
	RenderingServer.force_draw()
	var proof := get_viewport().get_texture().get_image()
	proof.resize(proof_size.x, proof_size.y, Image.INTERPOLATE_LANCZOS)
	var save_error := proof.save_png("/private/tmp/poe_detailed_buildings.png")
	if save_error != OK:
		push_error("Could not save building proof: %s" % save_error)
		get_tree().quit(1)
		return
	print("[building assets] captured /private/tmp/poe_detailed_buildings.png")
	get_tree().quit()

func _add_mesh(family: String, level: int, at: Vector2) -> void:
	var container := SubViewportContainer.new()
	container.position = at
	container.size = Vector2(230, 140)
	add_child(container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(230, 140)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	var key: String = Assets.key_for(family, level)
	var mesh := MeshInstance3D.new()
	mesh.mesh = Assets.mesh_for(key)
	viewport.add_child(mesh)
	var contour_mesh := Assets.contour_for(key)
	if contour_mesh != null:
		var contour := MeshInstance3D.new()
		contour.mesh = contour_mesh
		viewport.add_child(contour)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.40
	var target := Vector3(0, Assets.dimensions(key).y * 0.40, 0)
	camera.position = target + Vector3(3, 3, 3)
	viewport.add_child(camera)
	camera.look_at(target)
	camera.current = true
