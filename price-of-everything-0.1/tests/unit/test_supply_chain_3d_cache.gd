extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Builder := preload("res://scripts/supply_chain_3d/world_builder.gd")
const Board := preload("res://scripts/supply_chain_3d/board.gd")
const Cache := preload("res://scripts/supply_chain_3d/tile_resource_cache.gd")
const Sprites := preload("res://scripts/supply_chain_3d/far_sprites.gd")
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")

class FlatGround extends RefCounted:
	func height(_p: Vector2) -> float: return 30.0
	func gradient(_p: Vector2) -> Vector2: return Vector2.ZERO

class CountedGround extends RefCounted:
	var calls := 0
	func height(_p: Vector2) -> float:
		calls += 1
		return 30.0
	func gradient(_p: Vector2) -> Vector2:
		calls += 1
		return Vector2.ZERO

class StoredBakes extends "res://scripts/supply_chain_3d/bake_cache.gd":
	var records := {}
	func read(key: String) -> Dictionary:
		hits += 1
		return records.get(key, {})

func _payload() -> Dictionary:
	return {"meshes": [null, null, null], "textures": [null,
		ImageTexture.create_from_image(Image.create(8, 8, true, Image.FORMAT_RGBA8)), null]}

func _test_resource_cache_protection_and_pressure() -> void:
	var cache := Cache.new()
	for tid in ["visible", "nearby", "recent", "old"]: cache.put(tid, _payload(), {}, 0)
	var cost: int = cache.entries.old.bytes
	cache.target_bytes = cost * 3
	cache.touch("recent", 9000)
	cache.trim(10000, {"visible": true}, {"nearby": true})
	_check(cache.entries.size() == 3 and not cache.entries.has("old"),
		"3D resource cache: pressure evicts eligible old tiles while pinning visible, nearby and recent tiles")
	cache.target_bytes = cost
	cache.trim(18999, {"visible": true}, {"nearby": true})
	_check(cache.entries.has("recent") and cache.bytes > cache.target_bytes,
		"3D resource cache: minimum ten-second protection takes precedence over the soft budget")
	cache.trim(19000, {"visible": true}, {"nearby": true})
	_check(not cache.entries.has("recent") and cache.entries.has("nearby"),
		"3D resource cache: nearby tiles outlive ten seconds; other expired tiles become eligible")
	cache.trim(20000, {"visible": true}, {})
	_check(cache.entries.size() == 1 and cache.entries.has("visible") and cache.bytes == cost,
		"3D resource cache: dropping proximity protection allows memory to return to target")
	_check(not cache.can_prefetch(), "3D resource cache: prefetch stops under pressure rather than displacing protected work")

func _test_resource_cache_lru_and_accounting() -> void:
	var cache := Cache.new()
	for i in 3: cache.put(str(i), _payload(), {}, i * 1000)
	var cost: int = cache.entries["0"].bytes
	_check(cost == 340, "3D resource cache: a complete RGBA mip chain is included in byte accounting")
	cache.target_bytes = cost
	cache.trim(20000, {}, {})
	_check(cache.entries.keys() == ["2"], "3D resource cache: pressure drops the least recently used eligible tiles first")
	cache.put("2", _payload(), {}, 25000)
	_check(cache.entries["2"].last_used == 2000 and cache.bytes == cost,
		"3D resource cache: refreshing a payload does not reset its age or double-count it")
	cache.target_bytes = cost * 10
	cache.trim(99999, {}, {})
	_check(cache.entries.has("2"), "3D resource cache: passing ten seconds alone does not force needless reloads")

func _test_lazy_medium_assets_and_lighting() -> void:
	var builder := Builder.new()
	builder.lazy_assets = true
	builder.ground = FlatGround.new()
	builder.tiles = {"tile": {"center": Vector2.ZERO, "type": "rural", "polluters": 1}}
	builder.configure_grade()
	var root := builder.standing_node({"iid": "factory", "kind": "building", "internal_name": "industrial_factory",
		"level": 1, "side": 72.0, "tile": "tile", "pos": Vector2.ZERO})
	add_child(root)
	var pair: Dictionary = builder.sprite_pairs[0]
	_check(pair.near.is_empty() and not pair.has("body") and builder.building_visuals.is_empty(),
		"3D lazy assets: far standing objects do not instantiate close meshes, contours or physics bodies")
	builder.set_detail(1)
	builder.set_overview_scale(1.0)
	_check(pair.near.is_empty() and pair.medium != null and pair.medium.visible and pair.has("body"),
		"3D lazy assets: lit medium buildings use sprites and retain selectable source geometry")
	var texture: Texture2D = pair.medium.material_override.get_shader_parameter("artwork")
	_check(texture.resource_path.ends_with("_lit.png") and pair.medium.mesh is QuadMesh,
		"3D lazy assets: lit windows select their baked colour variant instead of loading a render mesh")
	var collider: CollisionShape3D = pair.body.get_child(0)
	_check(collider.shape == Assets.picking_shape(pair.key),
		"3D lazy assets: identical buildings share the precomputed picking resource")
	builder.set_detail(2)
	_check(not pair.near.is_empty() and pair.near[0].visible and not pair.medium.visible,
		"3D lazy assets: nearest zoom creates and shows the original model")
	var mesh_id: int = pair.near[0].get_instance_id()
	builder.set_detail(1)
	builder.set_detail(2)
	_check(pair.near[0].get_instance_id() == mesh_id,
		"3D lazy assets: revisiting near zoom does not duplicate its model")
	root.free()

func _test_medium_lighting_and_picking_assets_current() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Assets.DIRECTORY + "manifest.json"))
	var valid := true
	var lit_count := 0
	var pick_count := 0
	for key in catalog:
		if str(key).begins_with("tree_"): continue
		var digest := FileAccess.get_sha256(Assets.DIRECTORY + key + ".glb")
		var path: String = Assets.DIRECTORY + "picking/" + key + ".res"
		if not ResourceLoader.exists(path): valid = false; continue
		var shape := load(path) as ConcavePolygonShape3D
		valid = valid and shape != null and shape.get_meta("source_sha256", "") == digest
		pick_count += 1
		if str(key).begins_with("mine_") or str(key).begins_with("mine_flush_") or str(key).begins_with("pylon_"): continue
		var entry: Dictionary = Sprites.entry(key, 1)
		valid = valid and entry.get("lit_source_sha256", "") == digest and ResourceLoader.exists(Sprites.MEDIUM_DIRECTORY + str(entry.get("lit_texture", "missing")))
		lit_count += 1
	_check(valid and lit_count > 0 and pick_count > lit_count,
		"3D medium assets: every selectable model and lit variant has a current source-matched offline resource")

func _test_prefetch_is_resource_only_and_budgeted() -> void:
	var builder := Builder.new()
	builder.ground = FlatGround.new()
	builder.tiles = {"tile": {"center": Vector2.ZERO, "type": "rural"}}
	builder.tile_chunks.tile = "base"
	builder.continent = {"texture": null}
	var disk := StoredBakes.new()
	builder.bake_cache = disk
	disk.records.base = {"mesh": BoxMesh.new()}
	disk.records[builder.tile_bake_key("tile", 1)] = {"mesh": BoxMesh.new(), "texture":
		ImageTexture.create_from_image(Image.create(2048, 2048, true, Image.FORMAT_RGBA8))}
	var data := {"textures": [null, null, null], "meshes": [disk.records.base.mesh, null, null]}
	builder.resource_cache.put("tile", data, disk.records.base, 0)
	builder.resource_cache.target_bytes = 20 * 1048576
	var before: int = builder.resource_cache.bytes
	_check(not builder.prefetch_medium("tile") and data.meshes[1] == null and builder.resource_cache.bytes == before,
		"3D prefetch: an oversized speculative upgrade is rejected without mutating retained data or accounting")
	builder.resource_cache.target_bytes = 64 * 1048576
	_check(builder.prefetch_medium("tile") and builder.resource_cache.entries.tile.data.meshes[1] != null
		and builder.resource_cache.bytes > before and builder.local_tiles.is_empty() and builder.terrain_lods.is_empty(),
		"3D prefetch: admits existing medium resources within spare capacity without scene nodes or physics")
	disk.records.clear()
	builder.resource_cache.erase("tile")
	_check(not builder.prefetch_medium("tile") and disk.writes == 0 and builder.resource_cache.entries.is_empty(),
		"3D prefetch: a missing base bake never triggers invisible generation")

func _test_lazy_tree_geometry_and_clutter() -> void:
	var builder := Builder.new()
	builder.lazy_assets = true
	builder.streamed = true
	builder.local_streaming = true
	builder.scenery_ready = true
	builder.ground = FlatGround.new()
	builder.tiles = {"tile": {"center": Vector2.ZERO, "type": "rural"}}
	builder.tree_placements.tile = [{"kind": "small", "pos": Vector2.ZERO, "height": 22.0}]
	builder.configure_grade()
	var root := builder.trees_node("tile", [])
	add_child(root)
	builder.set_detail(1)
	builder.set_overview_scale(1.0)
	_check(builder.building_visuals.is_empty() and builder.sprite_pairs.all(func(pair: Dictionary) -> bool: return pair.near.is_empty()),
		"3D lazy trees: medium has no full tree, contour, stone or grass geometry")
	builder.set_detail(2)
	_check(builder.building_visuals.size() == 2 and builder.sprite_pairs[-1].near.size() == 1,
		"3D lazy trees: nearest zoom constructs the source tree/contour and ground clutter once")
	builder.set_detail(1)
	_check(builder.sprite_pairs[-1].near[0].visible == false and builder.sprite_pairs[0].medium.visible,
		"3D lazy trees: medium restores its sprite and hides near-only clutter")
	root.free()

func _test_cached_resources_survive_node_eviction() -> void:
	var board := Board.new()
	add_child(board)
	board.set_process(false)
	var builder := Builder.new()
	builder.streamed = true
	builder.local_streaming = true
	builder.lazy_assets = true
	builder.ground = FlatGround.new()
	builder.tiles = {"tile": {"center": Vector2.ZERO, "type": "rural", "label": "Tile"}}
	builder.tree_placements.tile = [{"kind": "small", "pos": Vector2.ZERO, "height": 22.0}]
	builder.configure_grade()
	await builder.prepare_continent(self)
	board._builder = builder
	board._content = Node3D.new()
	board._world.add_child(board._content)
	board._model = {"standing": []}
	builder.road_mat = builder.mat
	await board._build_local_tile(builder, board._content, board._model, "tile", board._generation)
	var item: Dictionary = builder.terrain_lods[0]
	await builder.refine_tile(self, item, 1)
	var mesh: Mesh = item.data.meshes[1]
	var shape: Shape3D = item.collider.shape
	var root: Node3D = builder.local_tiles.tile.root
	builder.set_detail(2)
	_check(not builder.building_visuals.is_empty(), "3D lazy cache: close geometry registers after tile attachment")
	builder.resource_cache.touch("tile", 123)
	builder.release_local_tiles({}, true)
	_check(not is_instance_valid(root) and builder.local_tiles.is_empty() and builder.terrain_lods.is_empty()
		and builder.terrain_cache.is_empty() and builder._chunk_data.is_empty() and builder.building_visuals.is_empty()
		and builder.sprite_pairs.is_empty(),
		"3D resource cache: panning releases scene nodes and their registrations")
	_check(builder.resource_cache.entries.tile.data.meshes[1] == mesh and builder.resource_cache.entries.tile.last_used == 123,
		"3D resource cache: eviction retains medium payload without extending unused time")
	await board._build_local_tile(builder, board._content, board._model, "tile", board._generation)
	item = builder.terrain_lods[0]
	await builder.refine_tile(self, item, 1)
	_check(item.node.mesh == mesh and item.collider.shape == shape and builder.resource_cache.hits == 1,
		"3D resource cache: a pan back reattaches the same medium mesh and collider without rereading or rebuilding")
	builder.road_surface.finish_build()
	board.queue_free()
	await get_tree().process_frame

func _test_prepared_detail_reloads_without_sampling_terrain() -> void:
	var first := Builder.new()
	first.streamed = true
	first.ground = FlatGround.new()
	first.tiles = {"tile": {"center": Vector2.ZERO, "type": "rural", "label": "Fixture"}}
	first.tree_placements.tile = [{"kind": "small", "pos": Vector2.ZERO, "height": 22.0}]
	var batch := first.Geo.Batch.new()
	batch.box(Vector3.ZERO, Vector3.ONE * 10.0, Color.WHITE)
	var chunk := {"mesh": batch.mesh(), "rim_mesh": ArrayMesh.new(), "lip_mesh": ArrayMesh.new(), "roads_mesh": ArrayMesh.new()}
	first._chunk_data.tile = chunk
	first.prepare_local_detail("tile", [])
	first.prepare_picking(chunk)
	var disk := first.BakeCache.new()
	disk.enabled = true
	disk.directory = "user://prepared-detail-test-%d" % Time.get_ticks_usec()
	disk.bundled_directory = disk.directory
	disk.write("fixture", chunk)
	_check(disk.storage_format(disk.directory.path_join("fixture.res")) == "zstd", "3D compact bake: new resources use lossless Zstd storage")
	var fresh := Builder.new()
	fresh.streamed = true
	fresh.local_streaming = true
	fresh.lazy_assets = true
	fresh.scenery_ready = true
	fresh.ground = CountedGround.new()
	fresh.tiles = first.tiles
	fresh.tree_placements = first.tree_placements
	fresh.tile_chunks.tile = "fixture"
	fresh.bake_cache = disk
	fresh.continent = {"texture": null}
	fresh.configure_grade()
	fresh.ground.calls = 0
	await fresh.prepare_tile(self, "tile")
	var restored := fresh.base_chunk("tile")
	var root := fresh.trees_node("tile", [])
	add_child(root)
	fresh.set_detail(2)
	fresh.set_overview_scale(4.0)
	var glints := fresh.water_glints("tile", fresh.tiles.tile, {})
	_check(fresh.ground.calls == 0 and glints.mesh == restored.local_detail.glint_mesh
		and fresh.sprite_pairs[-1].near[0].mesh == restored.local_detail.clutter_mesh,
		"3D prepared detail: fresh disk load reuses clutter, glints and tree transforms without terrain sampling")
	var terrain: Dictionary = fresh.terrain_cache[fresh.terrain_key("tile")]
	_check(fresh._terrain_shape(terrain, 0) == restored.pick_shape
		and restored.pick_shape.get_faces() == restored.mesh.get_faces(),
		"3D prepared picking: disk shape matches the rendered mesh and is reused directly")
	var cost := Cache.estimate(terrain, restored)
	var empty_detail := restored.duplicate()
	empty_detail.erase("local_detail")
	_check(cost > Cache.estimate(terrain, empty_detail), "3D prepared detail: retained mesh/transform memory is included in the cache budget")
	# Existing raw user bakes still load through the same reader.
	disk.compress = false
	disk.write("legacy", chunk)
	_check(disk.is_raw(disk.directory.path_join("legacy.res")) and not disk.read("legacy").is_empty(),
		"3D compact bake: the reader remains compatible with raw bakes")
	root.free()
	glints.free()
	for file in DirAccess.get_files_at(disk.directory): DirAccess.remove_absolute(disk.directory.path_join(file))
	DirAccess.remove_absolute(disk.directory)
