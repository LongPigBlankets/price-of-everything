extends Node3D
## Fast rendered inspection of source trees and their separate contour shells.
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const Harness := preload("res://tools/shot_harness.gd")
func _ready() -> void:
	TelemetryState.enabled = false
	SaveLoad.autosave_enabled = false
	Harness.prepare_window(get_window(), Vector2i(1440, 900))
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("a0a582")
	add_child(environment)
	Assets.set_grade(Vector2(-100000, 100000))
	var camera := Camera3D.new()
	add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 12.0
	camera.position = Vector3(18, 18, 18)
	camera.look_at(Vector3(0, 1.0, 0))
	camera.current = true
	var outlines: Array = []
	for i in 3:
		var key := Assets.key_for("tree", i + 1)
		var ca: Array = Assets.contour_for(key).surface_get_arrays(0)
		var limits := Vector4(INF, -INF, INF, -INF)
		for uv in ca[Mesh.ARRAY_TEX_UV]: limits.x = minf(limits.x, uv.x); limits.y = maxf(limits.y, uv.x)
		for n in ca[Mesh.ARRAY_NORMAL]: limits.z = minf(limits.z, n.length()); limits.w = maxf(limits.w, n.length())
		print("[CONTOUR] ", key, " width / normal range ", limits)
		for outline in [false, true]:
			var node := MeshInstance3D.new()
			node.mesh = Assets.contour_for(key) if outline else Assets.mesh_for(key)
			if not outline: node.material_override = Assets.tree_material(i == 1)
			node.position = Vector3((i - 1) * 2.0, 0, -(i - 1) * 2.0)
			node.scale = Vector3.ONE * (3.0 / Assets.projected_height(key))
			add_child(node)
			if "--multimesh" in OS.get_cmdline_user_args():
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.mesh = node.mesh
				mm.instance_count = 1
				mm.set_instance_transform(0, node.transform)
				var mn := MultiMeshInstance3D.new()
				mn.multimesh = mm
				mn.material_override = node.material_override
				add_child(mn)
				node.queue_free()
				if outline: outlines.append(mn)
			elif outline: outlines.append(node)
	for i in 5: await get_tree().process_frame
	Harness.capture(self, "/private/tmp/supply_style_probe_contours.png", Vector2i(1440, 900))
	for outline in outlines: outline.hide()
	for i in 5: await get_tree().process_frame
	Harness.capture(self, "/private/tmp/supply_style_probe_plain.png", Vector2i(1440, 900))
	camera.size = 60.0
	for i in 5: await get_tree().process_frame
	Harness.capture(self, "/private/tmp/supply_style_probe_far_plain.png", Vector2i(1440, 900))
	for outline in outlines: outline.show()
	for i in 5: await get_tree().process_frame
	Harness.capture(self, "/private/tmp/supply_style_probe_far_contours.png", Vector2i(1440, 900))
	for child in get_children():
		if child is GeometryInstance3D: child.lod_bias = 128.0
	for i in 5: await get_tree().process_frame
	Harness.capture(self, "/private/tmp/supply_style_probe_far_full.png", Vector2i(1440, 900))
	get_tree().quit()
