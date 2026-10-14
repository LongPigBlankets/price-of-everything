extends "res://tools/supply_chain_3d/capture.gd"
## Diagnostic only: reads the installed pilot and audits transport profiles.
## Never writes a map bake or changes production rendering.
const OUTPUT := "res://../outputs/supply-chain-3d/stoneshore-transport-review"
const Index := preload("res://scripts/supply_chain_3d/road_index.gd")

func _ready() -> void:
	PlayerProfile.supply_chain_all_tiles=true
	await super._ready()

func _continent_review(board: Control, home: Dictionary) -> void:
	assert(board._model.tiles.size()==5,"Diagnostic must remain scoped to Stoneshore")
	await board._stream_visible()
	while not board.detail_ready():
		RenderingServer.force_draw(false)
		await get_tree().process_frame
	board.set_process(false)
	board._labels.hide()
	board.animate_goods=false
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var b: RefCounted=board._builder
	# Reconstruct profile diagnostics from the restored transport plan, without
	# invalidating or saving the already prepared landscape/scenery.
	b._prepare_rail_art()
	var centers := {}
	for tid in b.tiles: centers[tid]=b.tiles[tid].center
	var index := Index.tiles(centers)
	var report := {"tiles":centers,"portals":[],"runs":[],"corridors":[],"road_bridges":b.road_grade.bridges,
		"visible_length":0.0,"hidden_length":0.0,"hidden_open_cut_length":0.0,"steep_visible_length":0.0,
		"max_visible_grade":0.0,"shading_samples":[],"views":[]}
	for portal in b._prepared_rail_art.portals:
		var tid := Index.tile_at(index,centers,portal.p)
		if tid.is_empty(): continue
		var natural: float=b.natural_height(portal.p)
		var surface: float=b.surface_height(portal.p)
		report.portals.append({"p":portal.p,"tile":tid,"rail_base":portal.h,"natural":natural,"surface":surface,
			"lowering":b.rail_urban.lowering(portal.p),"crown_above_natural":float(portal.h)+9.75-natural,
			"crown_above_surface":float(portal.h)+9.75-surface,"dir":portal.dir})
	for ci in b._prepared_rail_art.corridor_profiles.size():
		var prof: Dictionary=b._prepared_rail_art.corridor_profiles[ci]
		var records: Array=[]
		var run := {}
		for i in range(1,prof.samples.size()):
			var a: Dictionary=prof.samples[i-1];var z: Dictionary=prof.samples[i]
			var p: Vector2=(a.p+z.p)*.5
			var tid := Index.tile_at(index,centers,p)
			if tid.is_empty(): continue
			var length: float=a.p.distance_to(z.p)
			var hidden: bool=a.hidden or z.hidden
			var ground: float=b.formation_height(p)
			var road: float=b.road_grade.earth_height(p,ground)
			var surface: float=b.surface_height(p)
			var grade: float=absf(z.h-a.h)/maxf(.001,length)
			var record := {"p":p,"tile":tid,"hidden":hidden,"lowering":b.rail_urban.lowering(p),"buried_by_roads":b.rail_urban.buried(p),
				"start":a.p,"end":z.p,"start_height":a.h,"end_height":z.h,
				"start_lowering":b.rail_urban.lowering(a.p),"end_lowering":b.rail_urban.lowering(z.p),
				"start_urban":Index.tile_at(b.rail_urban.tile_index,b.rail_urban.centers,a.p),
				"end_urban":Index.tile_at(b.rail_urban.tile_index,b.rail_urban.centers,z.p),
				"cut":surface-road,"natural":ground,"surface":surface,"track_height":(a.h+z.h)*.5,"grade":grade,"bridge":a.bridge or z.bridge}
			records.append(record)
			report["hidden_length" if hidden else "visible_length"]+=length
			if hidden and surface<road-1.0: report.hidden_open_cut_length+=length
			if not hidden:
				report.max_visible_grade=maxf(report.max_visible_grade,grade)
				if grade>.15: report.steep_visible_length+=length
			if run.is_empty() or run.hidden!=hidden:
				if not run.is_empty(): report.runs.append(run)
				run={"corridor":ci,"hidden":hidden,"start":a.p,"end":z.p,"length":0.0,"minimum_height":INF,"maximum_height":-INF}
			run.length+=length;run.end=z.p
			run.minimum_height=minf(run.minimum_height,minf(a.h,z.h));run.maximum_height=maxf(run.maximum_height,maxf(a.h,z.h))
		if not run.is_empty(): report.runs.append(run)
		report.corridors.append(records)
	var natural_slopes: Array=[];var engineered_slopes: Array=[]
	for tid in centers:
		for y in range(-220,221,8):
			for x in range(-260,261,8):
				var p: Vector2=centers[tid]+Vector2(x,y)
				if not Index.contains(centers[tid],p) or b.open_water(p): continue
				var natural: float=b.natural_height(p)
				var surface: float=b.surface_height(p)
				var gradient: Vector2=b.surface_gradient(p)
				var magnitude := gradient.length()
				var facing := (-gradient/maxf(.0001,magnitude)).dot(Vector2.ONE.normalized())
				var darkening := clampf(magnitude/.13235,0,1)*(.2-.16*maxf(0,facing))
				var record := {"p":p,"slope":magnitude,"darkening":darkening,"earthwork":surface-natural}
				(engineered_slopes if absf(surface-natural)>1 else natural_slopes).append(record)
	for pair in [["natural",natural_slopes],["engineered",engineered_slopes]]:
		var slopes: Array=pair[1];slopes.sort_custom(func(a,z):return a.slope<z.slope)
		var saturated := slopes.filter(func(s):return s.slope>=.13235)
		report.shading_samples.append({"type":pair[0],"samples":slopes.size(),"saturated":saturated.size(),
			"p95_slope":slopes[int(slopes.size()*.95)].slope if not slopes.is_empty() else 0,
			"worst":slopes.slice(maxi(0,slopes.size()-8))})
	var center: Vector2=(centers.tile_4_9+centers.tile_5_10)*.5
	var views := [{"name":"town","p":centers.tile_4_9,"span":600.0},
		{"name":"rail-corridor","p":center,"span":450.0}]
	var mouths: Array=report.portals.duplicate()
	mouths.sort_custom(func(a,z):return a.crown_above_natural>z.crown_above_natural)
	if not mouths.is_empty(): views.append({"name":"protruding-portal","p":mouths[0].p,"span":150.0})
	for view in views:
		var state := home.duplicate()
		state.target=b.point(view.p);state.span=view.span;state.pitch=.95;state.yaw=0.0
		board.restore_camera(state)
		await board._stream_visible()
		while not board.detail_ready():
			RenderingServer.force_draw(false)
			await get_tree().process_frame
		for i in 30:
			RenderingServer.force_draw(false)
			await get_tree().process_frame
		board._viewport.get_texture().get_image().save_png(OUTPUT.path_join(view.name+"-current.png"))
		report.views.append({"name":view.name,"camera":board.capture_camera()})
	report.cache={"bundled_hits":b.bake_cache.bundled_hits,"writes":b.bake_cache.writes}
	FileAccess.open(OUTPUT.path_join("audit.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("[TRANSPORT REVIEW] portals=",report.portals.size()," visible=",report.visible_length," hidden_open_cuts=",report.hidden_open_cut_length," cache=",report.cache)
