extends Node
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const Civic := preload("res://scripts/supply_chain_3d/civic_layout.gd")
const Scale := preload("res://scripts/supply_chain_3d/building_scale.gd")
const FAMILIES := ["civic_u_office", "civic_semi", "civic_bauhaus", "civic_commercial"]
const TITLES := ["Courtyard office · 20 / 12 floors", "Symmetrical semi-detached homes", "Bauhaus works · decorative", "Commercial block · shops + terrace"]

func _ready() -> void:
	SaveLoad.autosave_enabled = false
	TelemetryState.enabled = false
	var output := "res://../outputs/supply-chain-3d/district-buildings/assets"
	DirAccess.make_dir_recursive_absolute(output)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1100, 1000)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("bdc0b1")
	viewport.add_child(environment)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 3000
	viewport.add_child(camera)
	camera.current = true
	Assets.set_grade(Vector2(-100000, 100000))
	var title := Label.new()
	title.position = Vector2(32, 24)
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color("303d4c"))
	viewport.add_child(title)
	var metrics := {}
	for i in FAMILIES.size():
		var family: String = FAMILIES[i]
		var key := Assets.key_for(family, 1)
		assert(not key.is_empty())
		var mesh := Assets.mesh_for(key)
		var side := Civic.side_for(family, 1)
		var scale := Scale.for_asset(key, side)
		var root := Node3D.new()
		root.scale = scale
		viewport.add_child(root)
		for part in [mesh, Assets.contour_for(key)]:
			if part == null: continue
			var visual := MeshInstance3D.new()
			visual.mesh = part
			root.add_child(visual)
		var size := mesh.get_aabb().size * scale
		var center := mesh.get_aabb().get_center() * scale
		camera.size = maxf(size.y, maxf(size.x, size.z)) * 1.45
		metrics[key] = {"dimensions": size, "side": side, "storey": Assets.storey_height(key)*side}
		title.text = TITLES[i]
		for view in ["front", "rear", "overhead"]:
			var direction := Vector3(.8, .75, 1.3).normalized()
			if view == "rear": direction = Vector3(-.9, .75, -1.2).normalized()
			if view == "overhead": direction = Vector3(.25, 2.2, .7).normalized()
			camera.position = center + direction*700
			camera.look_at(center)
			for frame in 5:
				await get_tree().process_frame
				RenderingServer.force_draw(false)
			viewport.get_texture().get_image().save_png(output.path_join(family+"-"+view+".png"))
		root.free()
	FileAccess.open(output.path_join("metrics.json"), FileAccess.WRITE).store_string(JSON.stringify(metrics,"\t"))
	# A shared camera makes the actual map-relative sizes reviewable too.
	viewport.size = Vector2i(2200, 1000)
	camera.size = 330
	camera.position = Vector3(0, 350, 720)
	camera.look_at(Vector3(0, 105, 0))
	title.text = "Common map scale · existing house included for reference"
	var keys := ["civic_u_office_lvl1", "house_lvl1", "civic_semi_lvl1", "civic_bauhaus_lvl1", "civic_commercial_lvl1"]
	var names := ["20 / 12-floor office", "Existing house · 50u", "Semi-detached · 55u", "Bauhaus works", "Commercial block"]
	for i in keys.size():
		var key: String = keys[i]
		var side := 72.0 if key == "house_lvl1" else Civic.side_for(key.get_slice("_lvl", 0), 1)
		var root := Node3D.new()
		root.scale = Scale.for_asset(key, side)
		root.position = Vector3(-240 + i*120, 0, 0)
		viewport.add_child(root)
		for part in [Assets.mesh_for(key), Assets.contour_for(key)]:
			if part == null: continue
			var visual := MeshInstance3D.new(); visual.mesh = part; root.add_child(visual)
		var label := Label.new()
		label.text = names[i]
		label.position = camera.unproject_position(root.position) + Vector2(-150, 30)
		label.size.x = 300
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 22)
		label.add_theme_color_override("font_color", Color("303d4c"))
		viewport.add_child(label)
	for frame in 5:
		await get_tree().process_frame
		RenderingServer.force_draw(false)
	viewport.get_texture().get_image().save_png(output.path_join("common-scale.png"))
	print("[DISTRICT ASSETS] ", output)
	get_tree().quit()
