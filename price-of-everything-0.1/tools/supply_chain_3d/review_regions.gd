extends "res://tools/supply_chain_3d/capture.gd"
## Disposable full-map review: numeric geometry for overlap audits plus each
## named region at regional, neighbourhood and street zooms.
const Regions := preload("res://scripts/road_regions.gd")
const Clearance := preload("res://scripts/supply_chain_3d/rail_clearance.gd")
const Civic := preload("res://scripts/supply_chain_3d/civic_layout.gd")
var opening := {}

func _ready() -> void:
	PlayerProfile.supply_chain_all_tiles="--owned-start" not in OS.get_cmdline_user_args()
	await super._ready()

func _open_supply_view(view: Control) -> void:
	opening.begin_elapsed_ms=Time.get_ticks_msec()
	var start := Time.get_ticks_msec()
	await super._open_supply_view(view)
	var board: Control=view.find_child("Board",true,false)
	await _settle(board)
	opening.ready_ms=Time.get_ticks_msec()-start
	opening.load=board.load_profile.duplicate(true)

func _settle(board: Control) -> void:
	await board._stream_visible()
	while not board.detail_ready():
		RenderingServer.force_draw(false)
		await get_tree().process_frame

func _numeric(value: Variant) -> Variant:
	if value is float and not is_finite(value):return null
	if value is Vector2: return [value.x,value.y]
	if value is Vector3: return [value.x,value.y,value.z]
	if value is Array or value is PackedVector2Array:
		var result: Array=[]
		for v in value: result.append(_numeric(v))
		return result
	if value is Dictionary:
		var result := {}
		for k in value: result[str(k)]=_numeric(value[k])
		return result
	if value is Object: return null
	return value

func _continent_review(board: Control, home: Dictionary) -> void:
	var output := "res://../outputs/supply-chain-3d/continent-rollout/draft"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--review-output="): output=arg.trim_prefix("--review-output=")
	DirAccess.make_dir_recursive_absolute(output)
	var toggle_start := Time.get_ticks_msec()
	await board.set_all_tiles(true,false)
	await _settle(board)
	opening.show_all_ms=Time.get_ticks_msec()-toggle_start
	opening.show_all_load=board.load_profile.duplicate(true)
	board.set_process(false);board._labels.hide();board.animate_goods=false
	var b: RefCounted=board._builder
	var plan := {"tiles":{},"buildings":[],"roads":b.road_grade.segments,"rails":b.rail_urban.tracks,
		"crossings":b.road_grade.crossings,"depots":b.depots,"frontage":board._model.authored_region.frontage,
		"neighbourhood":board._model.get("neighbourhood",{}),"greenery":b.greenery_audit}
	for tid in b.tiles:
		plan.tiles[tid]={"center":b.tiles[tid].center,"type":b.tiles[tid].type,"region":Regions.region_of(tid),"trees":b.tree_placements.get(tid,[]).size()}
	for s in board._model.standing:
		var key: String=b.standing_key(s)
		if key.is_empty() or s.kind=="pylon":continue
		plan.buildings.append({"iid":s.iid,"kind":s.kind,"tile":s.tile,"pos":s.pos,"yaw":s.get("yaw",0.0),"asset":key,"space":Civic.is_space(s),
			"polygons":Clearance.building_polygons(s,key),"side":s.side,"scale":s.get("decor_scale",1),"height":b.standing_frame(s).position.y,"top":b.standing_frame(s).position.y+b.standing_frame(s).dimension.y,
			"harbour":s.has("harbour"),"field":s.get("footprint",[]) if s.get("internal_name","") in ["farm","farm_building"] else []})
	b._prepare_rail_art()
	plan.visible_rails=[]
	for profile in b._prepared_rail_art.get("corridor_profiles",[]):
		for i in range(1,profile.samples.size()):
			var a: Dictionary=profile.samples[i-1];var z: Dictionary=profile.samples[i]
			plan.visible_rails.append({"a":a.p,"b":z.p,"ha":a.h,"hb":z.h,"hidden":a.hidden or z.hidden,"bridge":a.bridge or z.bridge})
	FileAccess.open(output.path_join("plan.json"),FileAccess.WRITE).store_string(JSON.stringify(_numeric(plan)))
	var report := {"opening":opening,"regions":{},"tile_count":b.tiles.size()}
	var regions := Regions.all_regions()
	# Also inspect otherwise unassigned rural/hill tiles in bounded map sectors.
	for tid in b.tiles:
		if Regions.region_of(tid)!=Regions.DEFAULT_REGION_ID or b.tiles[tid].type in ["sea","deep_sea"]:continue
		var cell := Vector2i((b.tiles[tid].center as Vector2)/2000.0)
		var id := "countryside_%d_%d" % [cell.x,cell.y]
		var entry: Dictionary=regions.get_or_add(id,{"name":id,"identity":"sparse_rural","tiles":[]})
		entry.tiles.append(tid)
	for id in regions:
		if "--quick-review" in OS.get_cmdline_user_args() and id not in ["stoneshore","capital_port","pepper_valley","holyfinger","grey_peaks"]:continue
		var region: Dictionary=regions[id]
		var points: Array=[];var urban: Array=[]
		for tid in region.tiles:
			if not b.tiles.has(tid):continue
			points.append(b.tiles[tid].center)
			if b.tiles[tid].type=="urban":urban.append(tid)
		if points.is_empty():continue
		var box := Rect2(points[0],Vector2.ZERO)
		for p in points:box=box.expand(p)
		var detail: Vector2=box.get_center()
		var best := -1
		for tid in (urban if not urban.is_empty() else region.tiles):
			if not b.tiles.has(tid):continue
			var count := 0
			for s in plan.buildings:
				if s.tile==tid and not s.space:count+=1
			if count>best:best=count;detail=b.tiles[tid].center
		var views := [{"name":"region","p":box.get_center(),"span":maxf(1600,maxf(box.size.y+850,(box.size.x+850)/1.65))},
			{"name":"medium","p":detail,"span":1050.0},{"name":"near","p":detail,"span":420.0}]
		report.regions[id]={"name":region.name,"identity":region.identity,"tiles":region.tiles,"urban":urban,"detail":detail,"views":[]}
		for v in views:
			var state := home.duplicate();state.target=b.point(v.p);state.span=v.span;state.pitch=1.05;state.yaw=.2
			board.restore_camera(state);await _settle(board)
			for i in 6:
				RenderingServer.force_draw(false)
				await get_tree().process_frame
			for item in board._goods:item.sprite.hide()
			RenderingServer.force_draw(false)
			board._viewport.get_texture().get_image().save_png(output.path_join(id+"-"+v.name+".png"))
			report.regions[id].views.append({"name":v.name,"span":v.span,"lod":board._detail})
		print("[REGION REVIEW] ",id," ",report.regions.size(),"/",regions.size())
	# Inspect numeric audit candidates in the same fresh process. These are
	# conservative mesh bounds, so a flag is not automatically a visible clash.
	var issue_file := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--issue-file="):issue_file=arg.trim_prefix("--issue-file=")
	if not issue_file.is_empty():
		var audit: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(issue_file))
		report.issue_views=[]
		for issue in audit.issues:
			if issue.kind=="building_building":continue
			var p := Vector2(issue.point[0],issue.point[1])
			if report.issue_views.any(func(v):return (Vector2(v.point[0],v.point[1])).distance_to(p)<65):continue
			var state := home.duplicate();state.target=b.point(p);state.span=220.0;state.pitch=.95;state.yaw=.2
			board.restore_camera(state);await _settle(board)
			for i in 6:
				RenderingServer.force_draw(false)
				await get_tree().process_frame
			for item in board._goods:item.sprite.hide()
			RenderingServer.force_draw(false)
			var file := "issue-%03d-%s.png" % [report.issue_views.size()+1,issue.region]
			board._viewport.get_texture().get_image().save_png(output.path_join(file))
			var entry: Dictionary=issue.duplicate();entry.file=file;report.issue_views.append(entry)
			print("[ISSUE REVIEW] ",file," ",issue.kind)
	report.cache={"hits":b.bake_cache.hits,"bundled_hits":b.bake_cache.bundled_hits,"misses":b.bake_cache.misses,"writes":b.bake_cache.writes}
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(_numeric(report),"\t"))
	print("[REGION REVIEW COMPLETE] ",JSON.stringify(report.cache))
