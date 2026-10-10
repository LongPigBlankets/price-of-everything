extends "res://tools/supply_chain_3d/compare_relief_bakes.gd"
## In-memory far-LOD prototypes; leaves runtime relief and persistent bakes intact.
## L3→L4 = 11. L4→L5 = 33/44; subsequent steps = 33 (current 22 × 1.5).
## Reuses one artwork atlas and camera to isolate the height-profile comparison.
const L4 := 77.0
const L5 := 88.0
const FOLLOWING_SCALE := 3.0

func _profiles() -> Array:
	return [{"name": "current", "scale": 2.0}, {"name": "3x", "scale": 3.0}, {"name": "4x", "scale": 4.0}]

func _output_folder() -> String:
	return "res://../outputs/supply-chain-3d/mountain-variants/"

func _height(h: float, first_scale: float) -> float:
	if h <= L4: return h
	if h <= L5: return L4 + (h - L4) * first_scale
	return L4 + (L5 - L4) * first_scale + (h - L5) * FOLLOWING_SCALE

func _slope(h: float, first_scale: float) -> float:
	if h <= L4: return 1.0
	return first_scale if h < L5 else FOLLOWING_SCALE

func _ready() -> void:
	Harness.prepare_window(get_window(), Vector2i(1920, 1080))
	Harness.arm_watchdog(self, 180.0)
	TelemetryState.enabled = false
	SaveLoad.autosave_enabled = false
	_validate_profiles()
	var directory := "user://supply_chain_3d_bakes/"
	var source: Dictionary = load(directory + OLD + ".res").data
	var current: Dictionary = load(directory + NEW + ".res").data
	var output := ProjectSettings.globalize_path(_output_folder())
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
	var bands := []
	for level in range(3, 11):
		var h := 66.0 + (level - 3) * 11.0
		var row := {"level": level, "source": h}
		for profile in _profiles():
			row[profile.name] = h + maxf(0.0, h - L4) if profile.name == "current" else _height(h, float(profile.scale))
		bands.append(row)
	var report := {"bands": bands, "variants": {}, "camera_span": rig.span, "camera_pitch": rig.pitch,
		"method": "In-memory remapping of source far geometry and normals. Static sprites translated by ground anchors, never scaled. Same current terrain atlas, grade, camera, tree colours and shading curve for all variants.",
		"scope": "Visual prototype only: no runtime selection/colliders or persisted bake changes. Fine infrastructure clearances need a native rebake if adopted."}
	for variant in _profiles():
		var data: Dictionary = current if variant.name == "current" else _remap(source, float(variant.scale))
		# Isolate geometry; foam and all other artwork are identical across candidates.
		data = data.duplicate()
		data.texture = current.texture
		var metrics := _measure(current.mesh, data.mesh, camera)
		metrics.erase("height_bands") # The parent's table describes the old 2× mapping.
		report.variants[variant.name] = metrics
		var root := _scene(data, grade)
		viewport.add_child(root)
		for i in 5:
			RenderingServer.force_draw(false)
			await get_tree().process_frame
		var image := viewport.get_texture().get_image()
		assert(image.save_png(output + variant.name + "_far.png") == OK)
		assert(image.save_webp(output + variant.name + "_far.webp", true, 0.90) == OK)
		for crop in [{"name": "north", "rect": Rect2i(755, 88, 525, 245)}, {"name": "east", "rect": Rect2i(1100, 235, 475, 305)}]:
			var detail := image.get_region(crop.rect)
			detail.resize(detail.get_width() * 3, detail.get_height() * 3, Image.INTERPOLATE_NEAREST)
			assert(detail.save_png(output + variant.name + "_" + crop.name + "_3x.png") == OK)
		print("[RELIEF VARIANT] ", variant.name, " ", JSON.stringify(metrics))
		root.queue_free()
		for i in 4: await get_tree().process_frame
	var file := FileAccess.open(output + "measurements.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	viewport.queue_free()
	for i in 5:
		RenderingServer.force_draw(false)
		await get_tree().process_frame
	get_tree().quit()

func _remap(source: Dictionary, first_scale: float) -> Dictionary:
	var data := source.duplicate()
	for key in ["mesh", "roads_mesh", "props_mesh", "rim_mesh", "lip_mesh"]:
		data[key] = _remap_mesh(source[key], first_scale)
	for group in ["tree_sprites", "decor_sprites"]:
		var groups := {}
		for key in source[group]:
			var transforms: Array = []
			for transform: Transform3D in source[group][key]:
				var shifted := transform
				var scale := transform.basis.x.length()
				var foot := transform.origin - Sprites.center(key) * scale
				var clearance := 0.0 if group == "tree_sprites" else 1.0
				shifted.origin.y += _height(foot.y - clearance, first_scale) - (foot.y - clearance)
				assert(shifted.basis == transform.basis)
				transforms.append(shifted)
			groups[key] = transforms
		data[group] = groups
	return data

func _remap_mesh(source: ArrayMesh, first_scale: float) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in vertices.size():
			var h := vertices[i].y
			vertices[i].y = _height(h, first_scale)
			# Inverse-transpose of the vertical remap; no new lighting treatment.
			var n := normals[i]
			normals[i] = Vector3(n.x, n.y / _slope(h, first_scale), n.z).normalized()
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		mesh.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays)
	return mesh

func _validate_profiles() -> void:
	for multiplier in [3.0, 4.0]:
		for h in [25.0, 34.0, 50.0, 66.0, 77.0]: assert(is_equal_approx(_height(h, multiplier), h))
		assert(is_equal_approx(_height(88.0, multiplier) - _height(77.0, multiplier), 11.0 * multiplier))
		for h in [88.0, 99.0, 110.0, 121.0, 132.0]:
			assert(is_equal_approx(_height(h + 11.0, multiplier) - _height(h, multiplier), 33.0))
		for h in [77.0, 88.0]: assert(_height(h + 0.001, multiplier) - _height(h - 0.001, multiplier) < 0.009)
		for h in [70.0, 80.0, 100.0]:
			var finite_difference := (_height(h + 0.01, multiplier) - _height(h - 0.01, multiplier)) / 0.02
			assert(absf(finite_difference - _slope(h, multiplier)) < 0.001)
	assert(is_equal_approx(_height(132.0, 3.0), 242.0))
	assert(is_equal_approx(_height(132.0, 4.0), 253.0))
	print("[RELIEF VARIANT] band spacing, continuity, normals and lowlands validated")
