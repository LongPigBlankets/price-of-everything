extends Node
## Same geometry as the live map, baked as transparent sprite variations.
const Rail := preload("res://scripts/supply_chain_3d/railway.gd")
const Geo := preload("res://scripts/supply_chain_3d/geometry.gd")
const OUT := "res://assets/iso/rails/"
const PROOF := "res://../outputs/railway-assets/"
const FRAME := 256
var viewport: SubViewport
var camera: Camera3D
var world: Node3D
var material: StandardMaterial3D
func route(points: Array, level := 1) -> Dictionary:
	var pts: Array = []
	for p in points: pts.append({"p":p})
	return {"mode":"rail","pts":pts,"level":level}
func _ready() -> void:
	TelemetryState.enabled = false; SaveLoad.autosave_enabled = false
	if DisplayServer.get_name() == "headless": get_tree().quit(1); return
	preload("res://tools/shot_harness.gd").arm_watchdog(self,180.0)
	for path in [OUT,PROOF]: DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	viewport = SubViewport.new(); viewport.size = Vector2i(FRAME,FRAME)
	viewport.own_world_3d = true; viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0,0,0,0)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE; env.environment.ambient_light_energy = 0.65
	viewport.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-60,-30,0)
	sun.light_energy = 0.75; sun.shadow_enabled = false; viewport.add_child(sun)
	camera = Camera3D.new(); camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	viewport.add_child(camera); camera.current = true
	material = Geo.material(); material.albedo_color = Color.WHITE
	var roads: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/iso/roads/roads.json"))
	var keys: Array = roads.cells.keys(); keys.sort()
	var variants: Array = []
	for key in keys: variants.append({"key":str(key).replace("r_","rail_"),"road_key":key})
	for angle in [0,2,3,4]:
		for lv in [1,2,3]: variants.append({"key":"rail_tunnel_%d_%d" % [angle,lv],"road_key":"tunnel_%d_%d" % [angle,lv]})
	var cols := 12
	var atlas := Image.create(cols*FRAME,ceili(float(variants.size())/cols)*FRAME,false,Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	var cells := {}; var metadata := {}
	for index in variants.size():
		var variant: Dictionary = variants[index]
		var data := variant_data(variant.road_key)
		var art := Rail.build(data.lines,data.roads,data.height,data.level_at,Vector2.ZERO,false)
		_show_art(art); _set_camera(float(data.span))
		var picture := await _capture()
		var cell := Vector2i(index%cols,index/cols)
		atlas.blit_rect(picture,Rect2i(0,0,FRAME,FRAME),cell*FRAME)
		cells[variant.key] = [cell.x,cell.y]
		metadata[variant.key] = {"road_variant":variant.road_key,"switches":art.plan.switches.size(),"portals":art.portals.size(),"tracks_per_route":2,"junctions":art.plan.junctions,"world_span":data.span,"flangeways":art.flangeways}
		if index%30 == 0: print("[railway atlas] ",index,"/",variants.size())
	atlas.save_png(OUT+"rails.png")
	FileAccess.open(OUT+"rails.json",FileAccess.WRITE).store_string(JSON.stringify({"cells":cells,"cols":cols,"frame":FRAME,"version":Rail.VERSION,"road_variant_count":keys.size(),"variants":metadata},"\t"))
	viewport.size = Vector2i(720,480)
	var sheet := Image.create(2160,1440,false,Image.FORMAT_RGBA8); sheet.fill(Color("eee9db"))
	var caption := Label.new(); caption.position = Vector2(22,18)
	caption.add_theme_color_override("font_color",Color("384745")); caption.add_theme_font_size_override("font_size",24)
	viewport.add_child(caption)
	var titles := ["L1 · timber sleepers","L2 · concrete sleepers","L3 · reinforced bed + fasteners","Paired tracks · broad curve","3-way · all directions","4-way · all directions","Road overbridge · raised approaches","Height 6+ · tunnel / track hidden","Tight-angle route · eased bend"]
	var selected := ["r_straight_0_1","r_straight_0_2","r_straight_0_3","r_j_0.2_3.2","r_j_0.2_3.2_6.2","r_j_0.2_3.2_6.2_9.2","r_bridge_0_2","tunnel_0_2","r_j_0.2_2.2"]
	for i in selected.size():
		caption.text = titles[i]
		var data := variant_data(selected[i])
		var art := Rail.build(data.lines,data.roads,data.height,data.level_at,Vector2.ZERO,false)
		_show_art(art)
		if not data.roads.is_empty(): _road_underpass()
		if str(selected[i]).begins_with("tunnel"): _hill()
		_set_camera(float(data.span)*0.75)
		var picture := await _capture()
		picture.save_png(PROOF+"detail_"+selected[i]+".png")
		sheet.blend_rect(picture,Rect2i(0,0,720,480),Vector2i(i%3,i/3)*Vector2i(720,480))
	sheet.save_png(PROOF+"review.png")
	print("[railway atlas] wrote ",variants.size()," variations and review.png")
	get_tree().quit()
func _show_art(art: Dictionary) -> void:
	if world != null: world.free()
	world = Node3D.new(); viewport.add_child(world)
	world.add_child(Geo.instance(art.bed,material)); world.add_child(Geo.instance(art.detail,material))
func _set_camera(span: float) -> void:
	camera.size = span; camera.position = Vector3(1,1,1)*1200; camera.look_at(Vector3.ZERO)
func _capture() -> Image:
	for i in 3: await get_tree().process_frame
	RenderingServer.force_draw(false)
	return viewport.get_texture().get_image()
func variant_data(key: String) -> Dictionary:
	var flat := func(_p: Vector2) -> float: return 0.0
	var low := func(_p: Vector2) -> float: return 0.0
	var lines: Array = []; var roads: Array = []; var span := 380.0
	if key.begins_with("r_j_"):
		for arm in key.trim_prefix("r_j_").split("_"):
			var parts := arm.split(".")
			var direction := Vector2.RIGHT.rotated(float(parts[0])*PI/6.0)
			lines.append(route([Vector2.ZERO,direction*170],int(parts[1])))
	else:
		var parts := key.split("_")
		var angle := int(parts[-2]); var lv := int(parts[-1])
		var direction := Vector2.RIGHT.rotated(angle*PI/6.0)
		var reach := 150.0
		if "bridge" in key:
			reach = 280.0; span = 610.0
			roads.append({"a":-direction.orthogonal()*100,"b":direction.orthogonal()*100,"level":lv,"widths":[2.5 if "bridge_s" in key else 4.5+3*(lv-1)]})
		if "tunnel" in key:
			reach = 210; span = 450
			low = func(p: Vector2) -> float: return 6.0 if absf(p.dot(direction))<65 else 5.0
		lines.append(route([-direction*reach,direction*reach],lv))
	return {"lines":lines,"roads":roads,"height":flat,"level_at":low,"span":span}
func _road_underpass() -> void:
	var batch := Geo.Batch.new()
	batch.box(Vector3(0,-1,0),Vector3(20,1,230),Color("565d61"))
	for z in range(-110,111,18): batch.box(Vector3(0,-0.3,z),Vector3(1.2,0.1,9),Color("e4d8b5"))
	world.add_child(Geo.instance(batch.mesh(),material))
func _hill() -> void:
	var batch := Geo.Batch.new()
	batch.box(Vector3(0,25,0),Vector3(134,50,130),Color("a4a17a"))
	world.add_child(Geo.instance(batch.mesh(),material))
