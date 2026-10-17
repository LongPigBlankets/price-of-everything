extends Node
## Fast terrain-only iteration; does not write or replace any runtime cache.
const Builder := preload("res://scripts/supply_chain_3d/world_builder.gd")
const OUT := "res://../outputs/supply-chain-3d/water-greenery/terrain-preview"

func _ready() -> void:
	TelemetryState.enabled = false; SaveLoad.autosave_enabled = false
	preload("res://tools/shot_harness.gd").arm_watchdog(self, 600.0)
	DirAccess.make_dir_recursive_absolute(OUT)
	var terrain := preload("res://scripts/hex_map.gd").new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain._generate_tile_data(); terrain._load_tile_overrides()
	var visual := preload("res://scripts/river_visuals.gd").new()
	visual.terrain_layer = terrain; visual.river_properties = visual._load_river_properties()
	var rivers := {}; var lines := {}
	for rec in visual.get_river_polylines():
		var tid := "tile_%d_%d" % [rec.coord.x+1, rec.coord.y+1]
		(rivers.get_or_add(tid, []) as Array).append(rec)
		(lines.get_or_add(tid, []) as Array).append(rec.points)
	var builder := Builder.new()
	builder.ground = Builder.Coast.ground_for(terrain, rivers, preload("res://scripts/empire_board_relief.gd").plates(terrain, lines), true)
	for tid in builder.ground.tiles:
		builder.tiles[tid] = {"center": builder.ground.tiles[tid].center, "type": Catalog.tile_type(tid)}
	builder.configure_grade()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1600, 1000); viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var environment := WorldEnvironment.new(); environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("2b3757")
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	viewport.add_child(environment)
	var camera := Camera3D.new(); viewport.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.far = 20000; camera.current = true
	for view in [{"name": "lake-upland", "p": Vector2(4312,1196), "span": 1100.0},
		{"name": "lake-shore", "p": Vector2(9201,7695), "span": 600.0}]:
		var root := Node3D.new(); viewport.add_child(root)
		for tid in builder.tiles:
			var tile: Dictionary = builder.tiles[tid]
			if tile.center.distance_to(view.p) > float(view.span)*1.1 + 400: continue
			var textures := await Builder.Paint.bake(self, tile, Builder.Coast.relief_of(tid,tile.center), rivers.get(tid,[]), [], builder.surface_height, [1024])
			var mat := builder.mat.duplicate() as ShaderMaterial
			mat.set_shader_parameter("textured", true); mat.set_shader_parameter("artwork", textures[0])
			root.add_child(Builder.Geo.instance(builder._surface(tid, 8.0), mat))
		camera.size = view.span
		var point := builder.point(view.p)
		camera.position = point + Vector3(350,950,1050); camera.look_at(point)
		for i in 4:
			await get_tree().process_frame
			RenderingServer.force_draw(false)
		assert(viewport.get_texture().get_image().save_png(OUT.path_join(view.name+".png")) == OK)
		print("[WATER FOCUS] ", view.name)
		root.free()
	visual.free(); terrain.free(); get_tree().quit()
