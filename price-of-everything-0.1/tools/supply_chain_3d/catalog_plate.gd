extends Node
## One building rendered through the board's own print shader, alone on a transparent
## background at the board's home angle, for catalogue-plate mock-ups.
## AGENT_GODOT_WINDOW=1 godot --path . res://tools/supply_chain_3d/catalog_plate.tscn -- --no-telemetry
##   --asset=high_tech_manufactory_lvl3 --out=<dir> [--palette=res://tools/supply_chain_3d/catalog_plate_poster_palette.json] [--strong-faces] [--ink=1.8]
## --dir=res://assets/supply_chain_3d_trial draws a trial export instead of the shipped model:
##   POE_MODEL_OUTPUT=<tmp> blender -b --factory-startup --python tools/supply_chain_3d/export_models.py -- <family>
##   then copy the GLBs into that folder and import (the shipped models and sprites stay untouched).
## Prints the mesh's vertex colours with their share of the surface, so a palette remap
## (the equivalent of re-colouring the Blender materials) can be written against them.
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const Rig := preload("res://scripts/supply_chain_3d/orbit_camera.gd")
const Harness := preload("res://tools/shot_harness.gd")
const SIZE := 2048

func _ready() -> void:
	Harness.prepare_window(get_window(), Vector2i(800, 800))
	Harness.arm_watchdog(self, 120)
	TelemetryState.enabled = false
	AudioServer.set_bus_mute(0, true)
	var key := "high_tech_manufactory_lvl3"
	var out := "/private/tmp/catalog_plate"
	var palette := {}
	var strong_faces := false
	var ink_width := 1.0
	var directory := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--asset="): key = argument.trim_prefix("--asset=")
		if argument.begins_with("--out="): out = argument.trim_prefix("--out=")
		if argument == "--strong-faces": strong_faces = true
		if argument.begins_with("--dir="): directory = argument.trim_prefix("--dir=")
		if argument.begins_with("--ink="): ink_width = float(argument.trim_prefix("--ink="))
		if argument.begins_with("--palette="):
			palette = JSON.parse_string(FileAccess.get_file_as_string(argument.trim_prefix("--palette=")))
	DirAccess.make_dir_recursive_absolute(out)
	Assets.set_grade(Vector2(-100000, 100000))
	var mesh := Assets.mesh_for(key)
	var contour := Assets.contour_for(key)
	var span := Assets.span(key)
	if directory != "":
		# A trial export in another folder, drawn with the board's own materials.
		mesh = _mesh_from(directory.path_join(key + ".glb"))
		Assets.prepare_mesh(mesh)
		if contour != null: contour = _mesh_from(directory.path_join(key + "_contour.glb"), contour.surface_get_material(0))
		var trial: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("manifest.json")))
		span = float(trial.get(key, {}).get("span", 0.0))
	_report(mesh)
	if not palette.is_empty(): mesh = _remapped(mesh, palette)
	var opaque: ShaderMaterial = Assets.print_material()
	var glass: ShaderMaterial = Assets.glass_material()
	if strong_faces or ink_width != 1.0:
		# Plate-only copies: stronger light-to-shade steps between faces, heavier ink.
		opaque = _plate_paint(false, strong_faces, ink_width)
		glass = _plate_paint(true, strong_faces, ink_width)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(SIZE, SIZE)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_8X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	viewport.add_child(environment)
	var building := MeshInstance3D.new()
	building.mesh = mesh
	Assets.paint(building, opaque, glass)
	if span > 0.0: building.set_instance_shader_parameter("pattern_scale", span)
	viewport.add_child(building)
	if contour != null:
		var outline := MeshInstance3D.new()
		outline.mesh = contour
		if ink_width != 1.0:
			var contour_material := contour.surface_get_material(0).duplicate() as ShaderMaterial
			contour_material.set_shader_parameter("outline_width_scale", ink_width)
			outline.material_override = contour_material
		viewport.add_child(outline)
	var box := mesh.get_aabb()
	var rig := Rig.new()
	rig.target = box.get_center()
	rig.span = box.size.length() * 1.05
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.current = true
	rig.apply(camera)
	for i in 12:
		RenderingServer.force_draw(false)
		await get_tree().process_frame
	var image := viewport.get_texture().get_image()
	var name := key + ("_trial" if directory != "" else "") + ("_palette" if not palette.is_empty() else "") + ("_faces" if strong_faces else "") + ("_ink" if ink_width != 1.0 else "") + ".png"
	image.save_png(out.path_join(name))
	print("[PLATE] saved ", name)
	get_tree().quit()

func _plate_paint(see_through: bool, strong_faces: bool, ink_width: float) -> ShaderMaterial:
	var code := Assets.print_code(see_through)
	if strong_faces:
		code = code.replace("mix(vec3(0.90, 0.92, 0.96), vec3(1.0, 1.0, 0.98)",
			"mix(vec3(0.42, 0.47, 0.60), vec3(1.0, 0.99, 0.95)").replace("smoothstep(-0.45, 0.8, diffuse)", "smoothstep(-0.2, 0.75, diffuse)").replace(
			# Still a south-east sun, swung to cast shadows at 11 o'clock so the two visible walls separate.
			"normalize(vec3(0.50, 0.74, 0.45))", "normalize(vec3(0.35, 0.70, 0.61))")
	var material := ShaderMaterial.new()
	material.shader = Shader.new()
	material.shader.code = code
	material.set_shader_parameter("grade_range", Vector2(-100000, 100000))
	material.set_shader_parameter("stroke_width_scale", ink_width)
	return material

func _mesh_from(path: String, material: Material = null) -> Mesh:
	var mesh := Assets.load_mesh(path)
	if material != null:
		for surface in mesh.get_surface_count(): mesh.surface_set_material(surface, material)
	return mesh

func _report(mesh: Mesh) -> void:
	var share := {}
	var alphas := {}
	var total := 0.0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for t in range(0, indices.size(), 3):
			var a := vertices[indices[t]]
			var area := (vertices[indices[t + 1]] - a).cross(vertices[indices[t + 2]] - a).length() * 0.5
			var c := colours[indices[t]]
			var k := "%.3f,%.3f,%.3f" % [c.r, c.g, c.b]
			share[k] = share.get(k, 0.0) + area
			alphas["%s a=%.3f%s" % [k, c.a, " glass" if Assets.is_glass(mesh, surface) else ""]] = true
			total += area
	var keys := share.keys()
	keys.sort_custom(func(x: String, y: String) -> bool: return share[x] > share[y])
	for k in keys: print("[COLOUR] ", k, " ", snappedf(100.0 * share[k] / total, 0.1), "%")
	for k in alphas: print("[ALPHA] ", k)
	print("[SURFACES] ", mesh.get_surface_count(), " glass=", mesh.get_meta("glass_surfaces", []))

func _remapped(mesh: Mesh, palette: Dictionary) -> ArrayMesh:
	var copy := ArrayMesh.new()
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		for i in colours.size():
			var c := colours[i]
			var k := "%.3f,%.3f,%.3f" % [c.r, c.g, c.b]
			if palette.has(k):
				var v: Array = palette[k]
				colours[i] = Color(v[0], v[1], v[2], c.a)
		arrays[Mesh.ARRAY_COLOR] = colours
		copy.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		copy.surface_set_material(surface, mesh.surface_get_material(surface))
	copy.set_meta("glass_surfaces", mesh.get_meta("glass_surfaces", []))
	return copy
