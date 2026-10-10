extends Node
## Compare two persisted far bakes with one camera and colour treatment.
## Runtime rendering is unchanged; no game save or bake is written.
const Harness := preload("res://tools/shot_harness.gd")
const Rig := preload("res://scripts/supply_chain_3d/orbit_camera.gd")
const Geo := preload("res://scripts/supply_chain_3d/geometry.gd")
const Sprites := preload("res://scripts/supply_chain_3d/far_sprites.gd")
const GroundShader := preload("res://scripts/supply_chain_3d/ground.gdshader")
const OLD := "continent-cafc4de4859b70d3d46c225cb41b544a514066150a2587688e6c082fea4b5459"
const NEW := "continent-ebec3348de49ede231422d6bfcecbc1346c979933e1767f1ca5b003a58c591d5"

func _ready() -> void:
	Harness.prepare_window(get_window(), Vector2i(1920, 1080))
	Harness.arm_watchdog(self, 120.0)
	TelemetryState.enabled = false
	SaveLoad.autosave_enabled = false
	var directory := "user://supply_chain_3d_bakes/"
	var old: Dictionary = load(directory + OLD + ".res").data
	var current: Dictionary = load(directory + NEW + ".res").data
	var output := ProjectSettings.globalize_path("res://../outputs/supply-chain-3d/mountain-comparison/")
	DirAccess.make_dir_recursive_absolute(output)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1044)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("2b3757")
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	viewport.add_child(environment)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.current = true
	var rig := Rig.new()
	rig.target = (current.metadata.bounds as AABB).get_center()
	rig.span = 10760.3658203125
	rig.apply(camera)
	Sprites.set_overview_scale(float(viewport.size.y) / rig.span, true)
	var grade: Vector2 = current.metadata.grade
	var report := _measure(old.mesh, current.mesh, camera)
	report.camera = {"span": rig.span, "pitch": rig.pitch, "yaw": rig.yaw, "target": [rig.target.x, rig.target.y, rig.target.z]}
	report.viewport = [viewport.size.x, viewport.size.y]
	report.method = "Both actual cached far meshes, same camera, same grade range and current softened tree colours; static baked scenery only."
	var file := FileAccess.open(output + "measurements.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	for variant in [{"name": "old", "bake": old}, {"name": "new", "bake": current}]:
		var root := _scene(variant.bake, grade)
		viewport.add_child(root)
		for i in 5:
			RenderingServer.force_draw(false)
			await get_tree().process_frame
		var image := viewport.get_texture().get_image()
		assert(image.save_png(output + variant.name + "_far.png") == OK)
		# Diagnostic crops retain the far LOD and its pixels; never zoom the camera.
		for crop in [{"name": "north", "rect": Rect2i(755, 98, 525, 235)}, {"name": "east", "rect": Rect2i(1100, 245, 475, 295)}]:
			var detail := image.get_region(crop.rect)
			detail.resize(detail.get_width() * 3, detail.get_height() * 3, Image.INTERPOLATE_NEAREST)
			assert(detail.save_png(output + variant.name + "_" + crop.name + "_3x.png") == OK)
		root.queue_free()
		for i in 3: await get_tree().process_frame
	print("[RELIEF COMPARISON] ", JSON.stringify(report))
	viewport.queue_free()
	for i in 5:
		RenderingServer.force_draw(false)
		await get_tree().process_frame
	get_tree().quit()

func _scene(data: Dictionary, grade: Vector2) -> Node3D:
	var root := Node3D.new()
	var mat := ShaderMaterial.new()
	mat.shader = GroundShader
	mat.set_shader_parameter("grade_range", grade)
	var terrain := mat.duplicate() as ShaderMaterial
	terrain.set_shader_parameter("textured", true)
	terrain.set_shader_parameter("artwork", data.texture)
	root.add_child(Geo.instance(data.mesh, terrain))
	var roads := mat.duplicate() as ShaderMaterial
	roads.set_shader_parameter("road_fade", 0.78)
	root.add_child(Geo.instance(data.roads_mesh, roads))
	root.add_child(Geo.instance(data.props_mesh, mat))
	var strata := mat.duplicate() as ShaderMaterial
	strata.set_shader_parameter("textured", true)
	strata.set_shader_parameter("strata", true)
	strata.set_shader_parameter("artwork", load("res://assets/iso/ground/strata.png"))
	root.add_child(Geo.instance(data.rim_mesh, strata))
	root.add_child(Geo.instance(data.lip_mesh, mat))
	for groups in [data.tree_sprites, data.decor_sprites]:
		for key in groups:
			var grove := Sprites.grove(key, groups[key], grade)
			if grove != null: root.add_child(grove)
	return root

func _measure(old: ArrayMesh, current: ArrayMesh, camera: Camera3D) -> Dictionary:
	var a := old.surface_get_arrays(0)
	var b := current.surface_get_arrays(0)
	var before: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var after: PackedVector3Array = b[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	assert(before.size() == after.size())
	var highest_before := -INF
	var highest_after := -INF
	var max_rise := 0.0
	var max_pixels := 0.0
	var upper_vertices := 0
	var saturated_before := 0
	for i in before.size():
		assert(Vector2(before[i].x, before[i].z).distance_squared_to(Vector2(after[i].x, after[i].z)) < 0.0001)
		highest_before = maxf(highest_before, before[i].y)
		highest_after = maxf(highest_after, after[i].y)
		max_rise = maxf(max_rise, after[i].y - before[i].y)
		max_pixels = maxf(max_pixels, camera.unproject_position(before[i]).distance_to(camera.unproject_position(after[i])))
		if before[i].y > 77.0:
			upper_vertices += 1
			var slope := Vector2(normals[i].x, normals[i].z).length() / maxf(0.08, normals[i].y)
			if slope >= 0.13235: saturated_before += 1
	var bands := []
	for h in [88.0, 99.0, 110.0, 121.0, 132.0]:
		var elevated: float = h + maxf(0.0, h - 77.0)
		bands.append({"old_height": h, "new_height": elevated,
			"pixel_rise": camera.unproject_position(Vector3(0, h, 0)).distance_to(camera.unproject_position(Vector3(0, elevated, 0)))})
	return {"vertices": before.size(), "highest_before": highest_before, "highest_after": highest_after,
		"max_height_rise": max_rise, "max_pixel_rise": max_pixels, "height_bands": bands,
		"upper_vertex_count": upper_vertices, "upper_shading_already_saturated_count": saturated_before,
		"upper_shading_already_saturated_percent": 100.0 * saturated_before / maxi(1, upper_vertices)}
