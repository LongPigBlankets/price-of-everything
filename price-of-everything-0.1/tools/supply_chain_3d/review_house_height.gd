extends Node
const Assets = preload("res://scripts/supply_chain_3d/assets.gd")
const Scale = preload("res://scripts/supply_chain_3d/building_scale.gd")
const Sprites = preload("res://scripts/supply_chain_3d/far_sprites.gd")
func _ready():
	SaveLoad.autosave_enabled = false
	TelemetryState.enabled = false
	call_deferred("render")
func render():
	var output = "res://../outputs/supply-chain-3d/house-height"
	DirAccess.make_dir_recursive_absolute(output)
	var viewport = SubViewport.new()
	viewport.size = Vector2i(480, 320)
	viewport.own_world_3d = true
	viewport.transparent_bg = false
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 110.0
	camera.near = 0.1
	camera.far = 1000.0
	camera.position = Vector3(110, 180, 220)
	camera.look_at_from_position(camera.position, Vector3(0,25,0))
	viewport.add_child(camera)
	camera.current = true
	Assets.set_grade(Vector2(-100000,100000))
	var canvas = CanvasLayer.new()
	viewport.add_child(canvas)
	var label = Label.new()
	label.position = Vector2(12,12)
	canvas.add_child(label)
	var sheet = Image.create(1440,960,false,Image.FORMAT_RGBA8)
	for row in 3:
		var key = Assets.key_for("house", row+1)
		for tier in 3:
			var node = Node3D.new()
			viewport.add_child(node)
			var scale = Scale.for_asset(key, 57.6)
			if tier < 2:
				var card = Sprites.instance(key,Vector2(-100000,100000),tier)
				card.scale = scale
				card.position = Sprites.center(key) * scale
				node.add_child(card)
			else:
				for mesh in [Assets.mesh_for(key),Assets.contour_for(key)]:
					if mesh == null: continue
					var visual = MeshInstance3D.new()
					visual.mesh = mesh
					visual.scale = scale
					node.add_child(visual)
			label.text = "%s — %s — 50u" % [key, ["Far", "Medium", "Mesh"][tier]]
			for i in 5:
				await get_tree().process_frame
				RenderingServer.force_draw(false)
			var frame = viewport.get_texture().get_image()
			frame.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(frame,Rect2i(0,0,480,320),Vector2i(tier*480,row*320))
			node.free()
	assert(sheet.save_png(output.path_join("houses-lod-check.png")) == OK)
	print("HOUSE LOD CHECK saved")
	get_tree().quit()
