extends "res://tools/railway_assets/render.gd"
func _ready() -> void:
	TelemetryState.enabled=false; SaveLoad.autosave_enabled=false
	preload("res://tools/shot_harness.gd").arm_watchdog(self,60.0)
	viewport=SubViewport.new(); viewport.size=Vector2i(1400,1000); viewport.own_world_3d=true
	viewport.msaa_3d=Viewport.MSAA_4X; viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var env := WorldEnvironment.new(); env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR; env.environment.background_color=Color("ded9c5")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color.WHITE; env.environment.ambient_light_energy=0.7; viewport.add_child(env)
	var sun:=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-55,-35,0); sun.light_energy=0.8; sun.shadow_enabled=true; viewport.add_child(sun)
	camera=Camera3D.new(); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; viewport.add_child(camera); camera.current=true
	material=Geo.material(); material.albedo_color=Color.WHITE
	var depot: Dictionary={"pos":Vector2.ZERO,"yaw":0.0,"height":0.0,"tile":"test"}
	var kit:=preload("res://scripts/supply_chain_3d/rail_depot.gd")
	var flat:=func(_p:Vector2)->float:return 0.0
	var art:=Rail.build(kit.lines(depot,Vector2(-220,0)),[],flat,flat)
	_show_art(art); world.add_child(Geo.instance(kit.mesh(depot,Vector2.ZERO),material))
	var ground:=Geo.Batch.new(); ground.box(Vector3(0,-1,25),Vector3(550,1,350),Color("a3a57a")); world.add_child(Geo.instance(ground.mesh(),material))
	camera.size=280; camera.position=Vector3(-350,330,300); camera.look_at(Vector3(-15,0,25))
	var picture:=await _capture(); picture.save_png(PROOF+"depot-review.png")
	print("[DEPOT] rendered six track yard")
	get_tree().quit()
