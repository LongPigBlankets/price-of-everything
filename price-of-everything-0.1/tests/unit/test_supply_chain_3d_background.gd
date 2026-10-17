extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Board := preload("res://scripts/supply_chain_3d/board.gd")
const Snapshot := preload("res://scripts/supply_chain_3d/world_snapshot.gd")
const Load := preload("res://scripts/supply_chain_3d/background_load.gd")
const Sprites := preload("res://scripts/supply_chain_3d/far_sprites.gd")

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
