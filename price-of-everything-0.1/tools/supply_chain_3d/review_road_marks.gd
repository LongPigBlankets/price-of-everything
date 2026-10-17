extends Node
const Cache := preload("res://scripts/supply_chain_3d/bake_cache.gd")
const Surface := preload("res://scripts/supply_chain_3d/road_surface.gd")
const Geo := preload("res://scripts/supply_chain_3d/geometry.gd")
const Legacy := preload("res://scripts/empire_board.gd")
var output := "res://../outputs/supply-chain-3d/road-marks/before"

func _ready() -> void:
	TelemetryState.enabled = false; SaveLoad.autosave_enabled = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Cache.BUNDLED.path_join("manifest.json")))
	var resource: Resource = load(Cache.BUNDLED.path_join(str(manifest.layout_key) + ".res"))
	var largest := {}
	for frontage in resource.data.frontages.values():
		if frontage.roads.size() > largest.get("roads", []).size(): largest = frontage
	var roads: Array = largest.roads
	var area := Rect2(4190, 7930, 720, 280)
	var nearby := roads.filter(func(r: Dictionary) -> bool: return area.intersects(Rect2(r.a, Vector2.ZERO).expand(r.b).grow(20.0)))
	FileAccess.open(output.path_join("roads.json"), FileAccess.WRITE).store_string(JSON.stringify(nearby, "\t"))
	var markings := preload("res://scripts/supply_chain_3d/road_markings.gd").new()
	var started := Time.get_ticks_msec()
	markings.configure(roads.filter(func(r: Dictionary) -> bool: return r.a.distance_to(r.b) >= 0.5))
	var report := {"segments": roads.size(), "duplicate_segments": markings.duplicate_segments,
		"suppressed_overlaps": markings.suppressed_overlaps, "prepare_ms": Time.get_ticks_msec() - started}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("[ROAD MARK AUDIT] ", report)
	if DisplayServer.get_name() == "headless": get_tree().quit(); return
	var viewport := SubViewport.new()
	viewport.own_world_3d = true; viewport.size = Vector2i(1800, 1000)
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 420.0
	camera.near = 1.0; camera.far = 100000.0
	viewport.add_child(camera)
	camera.position = Vector3(0, 500, 350); camera.look_at(Vector3.ZERO); camera.current = true
	var node := MeshInstance3D.new()
	viewport.add_child(node)
	var material := Geo.material(true)
	node.material_override = material
	for pass_name in ["flat", "flat-marks", "baked", "baked-marks"]:
		var meshes: Array = []
		if pass_name.begins_with("flat"):
			var surface := Surface.new()
			surface.cell_size = 6.0
			surface.configure(nearby, func(_p: Vector2) -> float: return 0.0, area.get_center())
			for tid in surface._by_tile: meshes.append(surface.mesh_for(tid))
			surface.finish_build()
			node.position = Vector3.ZERO
		else:
			var tiles := {}
			for r in nearby: tiles[r.tile] = true
			for tid in tiles:
				var data: Resource = load(Cache.BUNDLED.path_join(str(manifest.tiles[tid].base) + ".res"))
				meshes.append(data.data.roads_mesh)
			node.position = Vector3(-area.get_center().x, -60, -area.get_center().y)
		var mesh := Geo.joined(meshes)
		if pass_name.ends_with("marks"):
			var batch := Geo.Batch.new()
			var arrays := mesh.surface_get_arrays(0)
			for i in range(0, arrays[Mesh.ARRAY_VERTEX].size(), 3):
				if (arrays[Mesh.ARRAY_COLOR][i] as Color).is_equal_approx(Legacy._ROAD_MARK):
					batch.triangle(arrays[Mesh.ARRAY_VERTEX][i], arrays[Mesh.ARRAY_VERTEX][i + 2], arrays[Mesh.ARRAY_VERTEX][i + 1], Color.WHITE)
			mesh = batch.mesh()
		node.mesh = mesh
		for i in 4:
			await get_tree().process_frame
			RenderingServer.force_draw(false)
		viewport.get_texture().get_image().save_png(output.path_join(pass_name + ".png"))
	print("[ROAD MARKS] ", output, " segments=", nearby.size())
	get_tree().quit()
