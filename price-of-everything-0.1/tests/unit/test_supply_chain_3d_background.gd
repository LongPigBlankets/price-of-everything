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
		"pick_shape":ConcavePolygonShape3D.new(),"foundations":{},"pits":{},"mine_rims":ArrayMesh.new()}
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

func _test_background_world_change_cancels_pending_selection() -> void:
	var board := Board.new(); add_child(board); board.set_process(false)
	var job := Load.new(); board._warming = job
	board.set_all_tiles(true, false)
	await get_tree().process_frame
	board._discard_background()
	await get_tree().process_frame
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
