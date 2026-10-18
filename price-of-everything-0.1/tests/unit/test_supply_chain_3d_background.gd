extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Board := preload("res://scripts/supply_chain_3d/board.gd")
const Snapshot := preload("res://scripts/supply_chain_3d/world_snapshot.gd")
const Load := preload("res://scripts/supply_chain_3d/background_load.gd")
const Sprites := preload("res://scripts/supply_chain_3d/far_sprites.gd")

class LocatorFixture extends RefCounted:
	const Model := preload("res://scripts/empire_board_model.gd")
	var tiles := {"a":{"center":Vector2.ZERO}}
	func point(p: Vector2) -> Vector3: return Vector3(p.x,20.0,p.y)

func _test_background_lightweight_locator() -> void:
	var shape := Snapshot._locator_shape(LocatorFixture.new())
	var faces := shape.get_faces()
	_check(faces.size()==288, "Prepared cursor locator uses 96 triangles per tile instead of the detailed rendered mesh")
	var area := 0.0
	for i in range(0,faces.size(),3): area += (faces[i+1]-faces[i]).cross(faces[i+2]-faces[i]).length()*0.5
	_check(is_equal_approx(area,194400.0), "Cursor locator covers the entire hex without holes or overlap")
	var board := Board.new(); add_child(board); board.set_process(false)
	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new(); collider.shape = shape
	body.add_child(collider); board._world.add_child(body)
	await get_tree().physics_frame; await get_tree().physics_frame
	var ray := PhysicsRayQueryParameters3D.create(Vector3(10,100,10),Vector3(10,-100,10))
	ray.hit_back_faces = true
	var hit: Dictionary = board._viewport.find_world_3d().direct_space_state.intersect_ray(ray)
	_check(not hit.is_empty(), "Prepared locator accepts camera rays from above")
	board.queue_free(); await get_tree().process_frame

func _test_background_starts_owned_despite_saved_preference() -> void:
	var previous: bool = PlayerProfile.supply_chain_all_tiles
	PlayerProfile.supply_chain_all_tiles = true
	var board := Board.new(); add_child(board); board.set_process(false)
	_check(not board.show_all_tiles and board._coverage.selected == 0,
		"Background continent: a saved all-tiles choice cannot delay a new game's owned opening")
	PlayerProfile.supply_chain_all_tiles = previous
	board.queue_free(); await get_tree().process_frame

func _test_background_pending_selection_can_be_cancelled() -> void:
	var board := Board.new(); add_child(board); board.set_process(false)
	var job := Load.new(); board._warming = job
	board.set_all_tiles(true, false)
	await get_tree().process_frame
	_check(not board.show_all_tiles and not board._building and board._requested_all_tiles,
		"Background continent: an early request keeps owned coverage usable while preparation runs")
	await board.set_all_tiles(false, false)
	await get_tree().process_frame
	_check(not board._requested_all_tiles and not board.show_all_tiles and not job.cancelled,
		"Background continent: cancelling the switch retains owned coverage without discarding useful preparation")
	board.queue_free(); await get_tree().process_frame
	_check(job.cancelled, "Background continent: leaving the board cancels its pending preparation")

func _test_background_snapshot_rejects_changed_world() -> void:
	var keys := {"_map_key":"map", "_road_key":"roads", "_scenery_key":"scenery", "_continent_key":"continent", "transport_key":"transport"}
	var manifest := {"map_key":"map", "scenery_key":"scenery", "continent_key":"continent", "transport_key":"transport", "tile_count":1}
	var data := {"version":Snapshot.VERSION, "input_key":"same-world", "keys":keys,
		"fingerprints":Snapshot.Cache.source_fingerprints(), "model":{"tiles":{"a":{}}},
		"pick_shape":ConcavePolygonShape3D.new(),"foundations":{},"pits":{},"mine_rims":ArrayMesh.new(),"ink":{"a":ArrayMesh.new()}}
	data.authored_profile = {}
	data.overview = {"bounds":AABB(), "labels":[], "visibility":{}, "tile_chunks":{}}
	for field in Snapshot.AUTHORED_FIELDS: data.authored_profile[field] = {}
	_check(Snapshot.matches(data,"same-world",manifest), "Background continent: matching prepared inputs can reuse the installed artwork")
	_check(not Snapshot.matches(data,"changed-world",manifest), "Background continent: simulation changes reject the prepared world")
	data.authored_profile.erase("buckets")
	_check(not Snapshot.matches(data,"same-world",manifest), "Background continent: incomplete road indexes cannot enter the fast loading path")
	data.authored_profile.buckets = {}
	manifest.transport_key = "changed-roads"
	_check(not Snapshot.matches(data,"same-world",manifest), "Background continent: a different art/transport package cannot reuse a stale snapshot")

func _test_background_worker_uses_detached_values() -> void:
	var live := [{"pos":Vector2(2,3), "roads":[1,2]}]
	var copied: Array = Snapshot.plain(live)
	var expected := Snapshot.Cache.digest(copied)
	live[0].roads.append(3)
	var job := Load.new()
	var digest := await job.digest(get_tree(),copied)
	_check(digest == expected and digest != Snapshot.Cache.digest(live),
		"Background continent: worker hashing reads its captured values rather than changing live game state")
	var resource := ConcavePolygonShape3D.new()
	var prepared := {"nested":{"items":[1,2]}, "shape":resource}
	var copied_model := await job.copy_model(get_tree(), prepared)
	copied_model.nested.items.append(3)
	_check(prepared.nested.items.size() == 2 and copied_model.shape == resource,
		"Background continent: copying immutable model data detaches containers and preserves resource identity")
	var paths: Array = []
	for asset in ["tree_lvl1","tree_lvl2"]:
		for suffix in [".png","_depth.png"]: paths.append(Sprites.DIRECTORY+asset+suffix)
	await job.batch(get_tree(),paths+paths)
	_check(job.resources.size()==4 and job.resources.values().all(func(item): return item is Texture2D),
		"Batched artwork reads deduplicate paths and retain all completed texture handles")
	var cancelled := Load.new(); cancelled.cancelled = true
	await cancelled.batch(get_tree(),paths)
	_check(cancelled.resources.is_empty(), "Cancelled batches cannot acquire more resources")

func _test_background_material_does_not_regrade_owned_view() -> void:
	var owner := Sprites.material_for("tree_lvl1",0,false,Vector2(10,20))
	var continent := Sprites.material_for("tree_lvl1",0,false,Vector2(-30,70))
	_check(owner != continent and owner.get_shader_parameter("grade_range") == Vector2(10,20),
		"Background continent: preparing a second world cannot change the current world's sprite shading")

func _test_background_startup_bundle_preserves_values_and_resources() -> void:
	var codec := preload("res://scripts/supply_chain_3d/bake_values.gd")
	var mesh := ArrayMesh.new()
	var values := {"nested":[{Vector2i(2,3):mesh},null,mesh],"numbers":PackedFloat32Array([1.5,7.0])}
	var packed := codec.pack(values)
	var job := Load.new()
	var resource := Load.Cache.Data.new(); resource.encoded_values=packed
	var decoded := await job.decode_resource(get_tree(),resource,true)
	_check(decoded==values and packed.resources.size()==1, "Startup encoding preserves vector keys, packed arrays, nulls and shared mesh identity")
	decoded.nested.append("local")
	_check(values.nested.size()==3 and codec.unpack(packed).nested.size()==3, "Each startup decode owns its containers and cannot mutate another board or the saved payload")
	job.cancelled=true
	_check((await job.decode_resource(get_tree(),resource,true)).is_empty(), "Cancelled startup decoding cannot publish a world")
	packed.resources.clear()
	_check(codec.unpack(packed).is_empty(), "An incomplete resource table rejects the startup package")

func _test_background_backdrop_reveals_in_camera_order() -> void:
	var reveal := preload("res://scripts/supply_chain_3d/tile_reveal.gd").new()
	var tiles := {}
	for i in 5: tiles[str(i)]={"center":Vector2(i*405,i*240)}
	reveal.configure(tiles,Vector2.ZERO); reveal.begin({"4":true})
	_check(reveal.backdrop_batch(["0","1","2","3"],1000)==["0","1"], "The first far-backed group starts without waiting for later groups")
	reveal.advance(0.12)
	_check(reveal.backdrop_batch(["3","2","1","0"],1100).is_empty(), "A far resource arriving at once cannot start every tile in the same frame")
	_check(reveal.backdrop_batch(["3","2","1","0"],1120)==["3","2"], "The next group follows the latest camera priority without restarting active tiles")
	reveal.advance(1.38)
	_check(reveal.complete.has("0") and reveal.complete.has("1") and not reveal.complete.has("2"), "Early tiles finish while later tiles continue their own 1.5-second animation")
	reveal.advance(0.12)
	_check(not reveal.active and reveal.timeline.size()==4, "All groups finish and existing owned tiles never replay")

func _test_background_world_change_cancels_pending_selection() -> void:
	var board := Board.new(); add_child(board); board.set_process(false)
	var job := Load.new(); board._warming = job
	board.set_all_tiles(true, false)
	await get_tree().process_frame
	var shared_ink := {"a":ArrayMesh.new()}
	board._loading_ink = shared_ink
	board._discard_background()
	await get_tree().process_frame
	_check(shared_ink.size()==1 and board._loading_ink.is_empty(), "Invalidation releases ink without mutating the reusable snapshot resource")
	_check(job.cancelled and not board._requested_all_tiles and not board.show_all_tiles,
		"Background continent: a world change cancels a waiting selection instead of installing stale coverage")
	board.queue_free(); await get_tree().process_frame

func _test_background_paper_pick_follows_reveal() -> void:
	var paper := Board.PaperMap.new()
	paper.configure({"a":Vector2.ZERO,"b":Vector2(405,240)})
	add_child(paper)
	_check(paper.pick(Vector3(0,100,0),Vector3.DOWN).get("tile_id", "") == "a",
		"Paper placeholders support tile selection before terrain and physics arrive")
	paper.cover({"a":true})
	_check(paper.pick(Vector3(0,100,0),Vector3.DOWN).is_empty()
		and paper.pick(Vector3(405,100,240),Vector3.DOWN).get("tile_id", "") == "b",
		"Revealing a tile removes only its paper surface and placeholder hit area")
	paper.queue_free(); await get_tree().process_frame

func _test_background_reveal_is_per_complete_tile() -> void:
	var builder := Board.Builder.new()
	builder.progressive_tiles = true; builder.backdrop_pending = true
	var first := Node3D.new(); var second := Node3D.new()
	add_child(first); add_child(second)
	builder.local_tiles = {"a":{"root":first},"b":{"root":second}}
	builder.reveal_tile("a")
	_check(first.visible and not second.visible and builder.tile_ready("a") and not builder.tile_ready("b"),
		"A complete tile can appear while the next tile and far backdrop are still loading")
	builder.paper_owned_tiles = {"a":true}
	builder._apply_view_visibility()
	_check(not first.visible, "Retained company tiles suppress overlapping replacement geometry during paper reveal")
	builder.paper_owned_tiles.clear(); builder._apply_view_visibility()
	_check(first.visible, "Replacement geometry appears when the retained company view is released")
	first.queue_free(); second.queue_free(); await get_tree().process_frame

func _test_background_detached_scene_cleanup() -> void:
	var board := Board.new(); add_child(board); board.set_process(false)
	var active := Node3D.new(); board._world.add_child(active); board._content = active
	var dormant := Node3D.new()
	board._coverage_states = {
		false:{"content":active,"builder":Board.Builder.new()},
		true:{"content":dormant,"builder":Board.Builder.new()}}
	board._discard_background()
	_check(is_instance_valid(active) and not is_instance_valid(dormant) and board._coverage_states.is_empty(),
		"Background continent: invalidation frees the detached scene while retaining the currently visible scene")
	board.queue_free(); await get_tree().process_frame

func _test_background_ink_follows_relief_and_reveal() -> void:
	var ink := preload("res://scripts/supply_chain_3d/loading_ink_bake.gd")
	var hill := func(p: Vector2) -> float: return 34.0+33.0*exp(-p.length_squared()/14000.0)
	var paths: Array = ink.contours(Vector2.ZERO,hill)
	_check(paths.size()>=5, "Ink relief has several nested isolines for a real hill")
	var curved := paths.all(func(p): return p.size()>16 and p[0].distance_to(p[-1])<0.1)
	_check(curved, "Hill contours are continuous closed curves rather than disconnected hatches")
	_check(ink.contours(Vector2.ZERO,func(_p): return 34.0).is_empty(), "Flat land gains no invented relief rings")
	var crossing := PackedVector2Array([Vector2(-400,0),Vector2(400,0)])
	var mesh := ink.stroke_mesh([paths,[crossing],[crossing]],Board.Model.hex_points(Vector2.ZERO),Vector2.ZERO)
	var arrays := mesh.surface_get_arrays(0)
	var outside := 0
	for p in arrays[Mesh.ARRAY_VERTEX]:
		if not Geometry2D.is_point_in_polygon(Vector2(p.x,p.z)/1.02,Board.Model.hex_points(Vector2.ZERO)): outside+=1
	_check(outside==0, "Ink clips rivers, roads and contours to their own hex")
	var paper := Board.PaperMap.new(); paper.configure({"a":Vector2.ZERO}); add_child(paper)
	paper.draw_tile("a",mesh)
	paper.set_process(false)
	paper.set_time("a",0.25)
	var material: ShaderMaterial = paper.drawings.a.material
	_check(float(material.get_shader_parameter("progress"))<1.0, "Relief traces first while river and road ink stay hidden")
	paper.set_time("a",0.55)
	_check(float(material.get_shader_parameter("progress"))>1.0 and float(material.get_shader_parameter("progress"))<2.0,
		"River tracing follows completed contours, before roads")
	paper.set_time("a",0.85)
	_check(float(material.get_shader_parameter("progress"))>2.0, "Road tracing is the last ink layer")
	paper.cover({"a":true})
	_check(paper.drawings.is_empty(), "Finished terrain removes its ink and releases the drawing node")
	paper.queue_free(); await get_tree().process_frame

func _test_background_tile_transition_runs_concurrently() -> void:
	var Reveal := preload("res://scripts/supply_chain_3d/tile_reveal.gd")
	var reveal := Reveal.new()
	reveal.configure({"a":{"center":Vector2.ZERO},"b":{"center":Vector2(405,240)},"owned":{"center":Vector2(810,0)}},Vector2.ZERO)
	reveal.begin({"owned":true})
	_check(reveal.complete.has("owned") and not reveal.complete.has("a"), "Existing owned tiles stay detailed when the reveal begins")
	reveal.start("a"); reveal.start("b")
	reveal.advance(0.05)
	_check(Reveal.ink_progress(reveal.elapsed.a)==0.0 and Reveal.detail_progress(reveal.elapsed.a)==0.0,
		"Each ready tile starts with an empty-paper beat")
	reveal.advance(0.85)
	_check(Reveal.ink_progress(reveal.elapsed.a)==3.0 and Reveal.detail_progress(reveal.elapsed.a)==0.0,
		"All ink finishes before detail begins its dissolve")
	reveal.advance(0.30)
	_check(is_equal_approx(Reveal.detail_progress(reveal.elapsed.a),0.5), "Detail is halfway revealed at 1.2 seconds")
	reveal.advance(0.30)
	_check(not reveal.active and reveal.elapsed.is_empty() and reveal.timeline.size()==2,
		"Both tiles finish together at 1.5 seconds rather than blocking the loading queue sequentially")
	_check(not reveal.start("a"), "A completed tile does not replay when reused")
	var root := MeshInstance3D.new(); root.mesh=PlaneMesh.new()
	var source := ShaderMaterial.new(); source.shader=preload("res://scripts/supply_chain_3d/ground.gdshader")
	source.set_shader_parameter("loading_mask",false)
	root.material_override=source
	var fresh := Reveal.new(); fresh.configure({"a":{"center":Vector2.ZERO}},Vector2.ZERO)
	fresh.begin({}); fresh.bind(root)
	_check(root.material_override!=source and root.material_override.get_shader_parameter("loading_mask")==true and source.get_shader_parameter("loading_mask")==false,
		"Loading masks use private materials and cannot change retained company visuals")
	var intrinsic := MeshInstance3D.new()
	var plane := PlaneMesh.new(); plane.material=source; intrinsic.mesh=plane
	fresh.bind(intrinsic)
	var revealed: Material = intrinsic.get_surface_override_material(0)
	_check(intrinsic.material_override==null and revealed is ShaderMaterial and revealed!=source and revealed.get_shader_parameter("loading_mask")==true,
		"Mesh-surface materials used by near buildings and instanced crops join the same reveal")
	var building := MeshInstance3D.new()
	var faces := ArrayMesh.new()
	for shader in [preload("res://scripts/supply_chain_3d/building_print.gdshader"), preload("res://scripts/supply_chain_3d/building_glass.gdshader")]:
		faces.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, PlaneMesh.new().get_mesh_arrays())
		var paint := ShaderMaterial.new(); paint.shader=shader
		faces.surface_set_material(faces.get_surface_count()-1, paint)
	building.mesh=faces
	fresh.bind(building)
	var opaque: Material = building.get_surface_override_material(0)
	var glass: Material = building.get_surface_override_material(1)
	_check(opaque is ShaderMaterial and glass is ShaderMaterial and opaque.shader==faces.surface_get_material(0).shader and glass.shader==faces.surface_get_material(1).shader,
		"A building's see-through glass keeps its own paint while its tile is revealed")
	fresh.start("a"); fresh._started_at.a=Time.get_ticks_msec()-1200
	fresh.advance(0.001,true)
	_check(absf(fresh.elapsed.a-1.2)<0.02, "The live clock catches up after a slow frame instead of stretching the 1.5-second animation")
	fresh.finish(); fresh.restore()
	_check(intrinsic.material_override==null and intrinsic.get_surface_override_material(0)==null, "Restoring a surface material preserves its original null override")
	_check(building.get_surface_override_material(0)==null and building.get_surface_override_material(1)==null, "Restoring a building returns every surface to its own paint")
	intrinsic.free(); building.free()
	_check(root.material_override==source and fresh.bindings.is_empty(), "Completed reveals restore original materials for subsequent LOD and grading changes")
	root.free()
