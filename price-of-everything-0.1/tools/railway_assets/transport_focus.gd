extends "res://tools/railway_assets/render.gd"
func _ready() -> void:
	TelemetryState.enabled=false; SaveLoad.autosave_enabled=false
	preload("res://tools/shot_harness.gd").arm_watchdog(self,600.0)
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
	await review()
	get_tree().quit()

func review() -> void:
	var Builder := preload("res://scripts/supply_chain_3d/world_builder.gd")
	var Network := preload("res://scripts/supply_chain_3d/rail_network.gd")
	var Authored := preload("res://scripts/supply_chain_3d/authored_region.gd")
	var terrain := preload("res://scripts/hex_map.gd").new()
	terrain.tile_set=load("res://assets/main_tileset.tres"); terrain._generate_tile_data(); terrain._load_tile_overrides()
	var ground := Builder.Coast.ground_for(terrain,{},preload("res://scripts/empire_board_relief.gd").plates(terrain,{}))
	var probe := Builder.new(); probe.ground=ground
	var centers := {}; var flags := {}; var all := {"tiles":{},"lines":[]}
	for tile in terrain.tiles.values():
		centers[tile.id]=Builder.Model.tile_center(terrain,tile.id)
		flags[tile.id]=true
		all.tiles[tile.id]={"center":centers[tile.id],"type":Catalog.tile_type(tile.id),"label":tile.id}
	var paths := Authored.source_paths(terrain,flags)
	var compiled := Authored.compile(paths,centers,probe.natural_height)
	Network.apply(all,terrain,Builder.Legacy._water_test(terrain),probe.surface_height, true)
	var cases: Array = [{"tile":"tile_7_2","name":"transport-road-tunnels","span":650.0},{"tile":"tile_14_8","name":"transport-hill","span":700.0},{"tile":"tile_23_8","name":"transport-urban","span":700.0}]
	for depot in all.depots: cases.append({"tile":depot.tile,"name":"transport-depot-"+str(depot.city).to_snake_case(),"span":450.0,"focus":depot.pos})
	for entry in cases:
		var chosen := ""
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--case="): chosen=arg.trim_prefix("--case=")
		if chosen!="" and not chosen.split(",").has(entry.name): continue
		if world!=null: world.free()
		world=Node3D.new(); viewport.add_child(world)
		var model := {"tiles":{},"lines":[],"roads":[],"standing":[],"authored_region":{}}
		for tid in [entry.tile]+Catalog.tile_neighbours(entry.tile):
			if all.tiles.has(tid): model.tiles[tid]=all.tiles[tid]
		model.roads=compiled.roads.filter(func(road): return model.tiles.has(road.tile))
		var builder := Builder.new(); builder.ground=ground; builder.tiles=model.tiles
		Network.apply(model,terrain,Builder.Legacy._water_test(terrain),builder.surface_height, true)
		builder.prepare_transport(model); builder.configure_grade()
		builder.road_surface.configure(model.roads,builder.road_height)
		print("[FOCUS] ",entry.name," prepared; bridges=",builder.road_grade.bridges.size())
		var terrain_triangles := {}; var road_triangles := {}
		for tid in model.tiles:
			var tile: Dictionary=model.tiles[tid]
			var textures := await Builder.Paint.bake(self,tile,Builder.Coast.relief_of(tid,tile.center),[],[],builder.surface_height,[512])
			var mat := builder.mat.duplicate() as ShaderMaterial
			mat.set_shader_parameter("textured",true); mat.set_shader_parameter("artwork",textures[0])
			var terrain_mesh := builder._surface(tid,12.0); var road_mesh := builder.road_surface.mesh_for(tid)
			world.add_child(Geo.instance(terrain_mesh,mat))
			world.add_child(Geo.instance(road_mesh,builder.mat))
			if "--connections-review" in OS.get_cmdline_user_args():
				_index_mesh(terrain_triangles,terrain_mesh); _index_mesh(road_triangles,road_mesh)
			world.add_child(Geo.instance(builder.road_grade.bridge_mesh(tid,Vector2.ZERO,builder.natural_height),builder.mat))
		for tid in model.tiles: world.add_child(Geo.instance(builder.road_alignment.mesh_for(tid,builder.road_height,Vector2.ZERO,builder.surface_height,builder.railway_earth_color),builder.mat))
		print("[ROAD] switchbacks=",builder.road_alignment.switchbacks," constrained=",builder.road_alignment.constrained," eased=",builder.road_alignment.grade_eased," portals=",builder.road_alignment.portals.size())
		var art:=Rail.build(model.lines,builder.road_grade.segments,builder.railway_ground_height,builder.railway_level,Vector2.ZERO,true,builder.railway_earth_color,builder.road_height,builder.surface_height,{"plan":builder.rail_plan,"burial":builder.rail_urban.profile})
		world.add_child(Geo.instance(art.bed,builder.mat)); world.add_child(Geo.instance(art.detail,builder.mat))
		for depot in model.depots: world.add_child(Geo.instance(Builder.RailDepot.mesh(depot,Vector2.ZERO),builder.mat))
		var focus: Vector2=entry.get("focus",centers[entry.tile])
		camera.size=entry.span; camera.position=builder.point(focus)+Vector3(800,900,800); camera.look_at(builder.point(focus))
		var picture:=await _capture(); picture.save_png(PROOF+entry.name+".png")
		print("[FOCUS] captured ",entry.name," portals=",art.portals.size())
		if not builder.road_grade.bridges.is_empty() and entry.name=="transport-hill":
			focus=builder.road_grade.bridges[0].p
			camera.size=380; camera.position=builder.point(focus)+Vector3(800,900,800); camera.look_at(builder.point(focus))
			picture=await _capture(); picture.save_png(PROOF+"transport-road-bridge.png")
		if "--connections-review" in OS.get_cmdline_user_args():
			# Fixed regressions from the user's three screenshots, retained even
			# after the automatic defect scanner can no longer find a defect.
			for target in [
				{"p":Vector2(6285,4271),"name":"rail-window","span":130.0},
				{"p":Vector2(6203.05,4887.83),"name":"road-join","span":100.0},
				{"p":Vector2(5831.355,5105.589),"name":"road-width","span":100.0}]:
				focus=target.p; camera.size=target.span
				camera.position=builder.point(focus)+Vector3(800,900,800); camera.look_at(builder.point(focus))
				picture=await _capture(); picture.save_png(PROOF+"connection-"+target.name+".png")
			var pinches: Array=[]
			for r in model.roads:
				if r.get("tunnel",false): continue
				var n: Vector2=(r.b-r.a).normalized().orthogonal()*float(r.widths[3])*0.85
				for side in [-1.0,0.0,1.0]:
					var p: Vector2=(r.a+r.b)*0.5+n*side
					var road_y := _mesh_height(road_triangles,p); var terrain_y := _mesh_height(terrain_triangles,p)
					if road_y==-INF or terrain_y<road_y+0.1: continue
					if pinches.any(func(q): return q.distance_to(p)<25): continue
					pinches.append(p); print("[PINCH] ",p," burial=",terrain_y-road_y," source=",r.source)
					if pinches.size()>8: continue
					focus=p; camera.size=85; camera.position=builder.point(focus)+Vector3(800,900,800); camera.look_at(builder.point(focus))
					picture=await _capture(); picture.save_png(PROOF+"road-pinch-%d.png" % pinches.size())
			for i in art.portals.size():
				var portal: Dictionary=art.portals[i]
				print("[MOUTH] ",i," ",portal)
				for j in range(i+1,art.portals.size()):
					if portal.p.distance_to(art.portals[j].p)>60: continue
					focus=(portal.p+art.portals[j].p)*0.5
					camera.size=110; camera.position=builder.point(focus)+Vector3(800,900,800); camera.look_at(builder.point(focus))
					picture=await _capture(); picture.save_png(PROOF+"rail-pair-%d-%d.png" % [i,j])
			var ends := {}
			for r in model.roads:
				for p in [r.a,r.b]: (ends.get_or_add(Builder.RoadGrade.Index.EPSILON * (p/Builder.RoadGrade.Index.EPSILON).round(),[]) as Array).append(r)
			var road_index := Builder.RoadGrade.Index.segments(model.roads,30)
			var near_count := 0
			for p in ends:
				if ends[p].size()!=1: continue
				var r: Dictionary=ends[p][0]
				if r.get("tunnel",false): continue
				for id in Builder.RoadGrade.Index.query(road_index,Rect2(p,Vector2.ZERO).grow(25)):
					var other: Dictionary=model.roads[id]
					if other==r or other.source==r.source or other.get("tunnel",false): continue
					var q := Geometry2D.get_closest_point_to_segment(p,other.a,other.b)
					var gap: float=p.distance_to(q)-float(r.widths[0])-float(other.widths[0])
					if gap>3 or gap< -3: continue
					print("[NEAR] ",p," -> ",q," gap=",gap," source=",r.source," other=",other.source)
					if near_count<8:
						focus=p; camera.size=100; camera.position=builder.point(focus)+Vector3(800,900,800); camera.look_at(builder.point(focus))
						picture=await _capture(); picture.save_png(PROOF+"road-near-%d.png" % near_count)
					near_count+=1; break
		if "--portal-review" in OS.get_cmdline_user_args():
			var mouths: Array=[]
			if not art.portals.is_empty(): mouths.append({"portal":art.portals[0],"name":"rail-mouth"})
			if not builder.road_alignment.portals.is_empty():
				var near := builder.road_alignment.portals.duplicate()
				near.sort_custom(func(a,b): return a.p.distance_squared_to(centers[entry.tile])<b.p.distance_squared_to(centers[entry.tile]))
				mouths.append({"portal":near[0],"name":"road-mouth"})
			for mouth in mouths:
				var p: Vector2=mouth.portal.p; var dir: Vector2=mouth.portal.dir
				var h := builder.road_height(p) if mouth.name=="road-mouth" else float(mouth.portal.h)
				for sign_v in [-1.0,1.0]:
					camera.size=95
					camera.position=Vector3(p.x+dir.x*120*sign_v,h+80,p.y+dir.y*120*sign_v)
					camera.look_at(Vector3(p.x,h+3,p.y))
					picture=await _capture()
					picture.save_png(PROOF+mouth.name+("-front.png" if sign_v<0 else "-back.png"))
		builder.road_surface.finish_build()
	terrain.free()

func _index_mesh(index: Dictionary, mesh: ArrayMesh) -> void:
	if mesh.get_surface_count()==0: return
	var vertices: PackedVector3Array=mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for i in range(0,vertices.size(),3):
		var tri := [vertices[i],vertices[i+1],vertices[i+2]]
		var bounds := Rect2(Vector2(tri[0].x,tri[0].z),Vector2.ZERO)
		for v in tri: bounds=bounds.expand(Vector2(v.x,v.z))
		for y in range(floori(bounds.position.y/16),floori(bounds.end.y/16)+1):
			for x in range(floori(bounds.position.x/16),floori(bounds.end.x/16)+1):
				(index.get_or_add(Vector2i(x,y),[]) as Array).append(tri)

func _mesh_height(index: Dictionary,p: Vector2) -> float:
	var h := -INF
	for tri in index.get(Vector2i((p/16).floor()),[]):
		var a := Vector2(tri[0].x,tri[0].z); var b := Vector2(tri[1].x,tri[1].z); var c := Vector2(tri[2].x,tri[2].z)
		var det := (b-a).cross(c-a)
		if absf(det)<0.000001: continue
		var u := (p-a).cross(c-a)/det; var v := (b-a).cross(p-a)/det
		if u>=-0.00001 and v>=-0.00001 and u+v<=1.00001: h=maxf(h,tri[0].y*(1-u-v)+tri[1].y*u+tri[2].y*v)
	return h
