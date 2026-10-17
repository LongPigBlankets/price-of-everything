extends Node
## Shared-camera comparison at the actual Stoneshore half scale.
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const Scale := preload("res://scripts/supply_chain_3d/building_scale.gd")

func _ready() -> void:
	SaveLoad.autosave_enabled=false
	TelemetryState.enabled=false
	var output := "res://../outputs/supply-chain-3d/stoneshore-semi-scale/assets"
	DirAccess.make_dir_recursive_absolute(output)
	var viewport := SubViewport.new()
	viewport.size=Vector2i(1600,700)
	viewport.own_world_3d=true
	viewport.msaa_3d=Viewport.MSAA_4X
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color("bdc0b1")
	viewport.add_child(environment)
	var camera := Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=70
	camera.far=1000
	viewport.add_child(camera)
	camera.current=true
	Assets.set_grade(Vector2(-100000,100000))
	var semi := Assets.key_for("civic_semi",1)
	var terrace := Assets.key_for("house",1)
	var entries := [
		{"key":semi,"scale":Vector3(32,25/Assets.dimensions(semi).y,32),"label":"Previous pair\n32u wide · 25u tall"},
		{"key":terrace,"scale":Scale.for_asset(terrace,36,.5),"label":"Reference: three terrace homes\n36u wide · 25u tall"},
		{"key":semi,"scale":Scale.for_asset(semi,Scale.semi_side()*.5,.5),"label":"Revised pair\n30u wide · 27.5u tall"}]
	var metrics := []
	for i in entries.size():
		var e: Dictionary=entries[i]
		var root := Node3D.new()
		root.scale=e.scale
		root.position=Vector3((i-1)*51,0,0)
		viewport.add_child(root)
		for mesh in [Assets.mesh_for(e.key),Assets.contour_for(e.key)]:
			if mesh==null: continue
			var visual := MeshInstance3D.new()
			visual.mesh=mesh
			root.add_child(visual)
		metrics.append({"label":e.label,"dimensions":Assets.mesh_for(e.key).get_aabb().size*e.scale})
		var label := Label.new()
		label.text=e.label
		label.position=Vector2(i*533,565)
		label.size.x=533
		label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size",24)
		label.add_theme_color_override("font_color",Color("303d4c"))
		viewport.add_child(label)
	for view in ["front","angle"]:
		camera.position=Vector3(0,14,350) if view=="front" else Vector3(0,150,350)
		camera.look_at(Vector3(0,14,0))
		for frame in 6:
			await get_tree().process_frame
			RenderingServer.force_draw(false)
		viewport.get_texture().get_image().save_png(output.path_join(view+".png"))
	FileAccess.open(output.path_join("dimensions.json"),FileAccess.WRITE).store_string(JSON.stringify(metrics,"\t"))
	print("[HOUSING SCALE] ",JSON.stringify(metrics))
	get_tree().quit()
