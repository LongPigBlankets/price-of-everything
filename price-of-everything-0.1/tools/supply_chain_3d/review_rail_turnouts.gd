extends Node
const Rail := preload("res://scripts/supply_chain_3d/railway.gd")
const Geo := preload("res://scripts/supply_chain_3d/geometry.gd")
func _ready() -> void:
	get_window().size=Vector2i(1600,1000)
	var old: Script=load("/private/tmp/railway-before-stream-ready.gd")
	var viewport := SubViewport.new()
	viewport.size=Vector2i(1600,1000);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var env := WorldEnvironment.new();env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("d9d6be")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.6
	viewport.add_child(env)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,-30,0);viewport.add_child(light)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=650;camera.far=2000
	viewport.add_child(camera);camera.position=Vector3(0,800,1);camera.look_at(Vector3.ZERO)
	var report:=[]
	for degree in [3,4]:
		for newer in [false,true]:
			var lines:=[]
			for i in degree:lines.append({"mode":"rails","pts":[{"p":Vector2.ZERO},{"p":Vector2.RIGHT.rotated(TAU*i/degree)*140}]})
			var kit:Dictionary=(Rail if newer else old).build(lines,[],func(_p):return 0.0,func(_p):return 1.0)
			var root:=Node3D.new();viewport.add_child(root);root.position=Vector3(190 if newer else -190,0,155 if degree==4 else -155)
			for field in ["bed","detail"]:root.add_child(Geo.instance(kit[field],Geo.material()))
			report.append({"degree":degree,"new":newer,"corridors":kit.plan.corridors.size(),"vertices":kit.track_vertex_count})
	for i in 8:await get_tree().process_frame;RenderingServer.force_draw(false)
	var output:="res://../outputs/supply-chain-3d/stream-ready"
	DirAccess.make_dir_recursive_absolute(output)
	viewport.get_texture().get_image().save_png(output+"/rail-turnouts-before-after.png")
	FileAccess.open(output+"/rail-turnouts.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	get_tree().quit()
