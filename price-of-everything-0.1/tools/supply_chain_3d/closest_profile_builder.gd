extends "res://scripts/supply_chain_3d/world_builder.gd"
## Measurement wrappers only: every operation delegates to current production code.
var probe: Dictionary = {}

func mark(stage: String, start: int) -> void:
	(probe.get_or_add(stage, []) as Array).append((Time.get_ticks_usec() - start) / 1000.0)

func prepare_tile(host: Node, tid: String) -> void:
	var start := Time.get_ticks_usec()
	await super.prepare_tile(host, tid)
	mark("prepare_tile", start)

func base_chunk(tid: String) -> Dictionary:
	var start := Time.get_ticks_usec()
	var result = super.base_chunk(tid)
	mark("base_chunk", start)
	return result

func tile_node(tid: String) -> Node3D:
	var start := Time.get_ticks_usec()
	var result = super.tile_node(tid)
	mark("tile_node", start)
	return result

func standing_node(s: Dictionary) -> Node3D:
	var start := Time.get_ticks_usec()
	var result = super.standing_node(s)
	mark("standing_node", start)
	return result

func trees_node(tid: String, standing: Array) -> Node3D:
	var start := Time.get_ticks_usec()
	var result = super.trees_node(tid, standing)
	mark("trees_node", start)
	return result

func append_road(parent: Node3D, tid: String) -> void:
	var start := Time.get_ticks_usec()
	super.append_road(parent, tid)
	mark("append_road", start)

func _tile_bake(host: Node, tid: String, tier: int) -> Dictionary:
	var start := Time.get_ticks_usec()
	var result = await super._tile_bake(host, tid, tier)
	mark("_tile_bake_%d" % tier, start)
	return result

func refine_tile(host: Node, item: Dictionary, tier: int) -> void:
	var start := Time.get_ticks_usec()
	await super.refine_tile(host, item, tier)
	mark("refine_tile", start)

func apply_tile_detail(item: Dictionary, tier: int) -> void:
	var start := Time.get_ticks_usec()
	super.apply_tile_detail(item, tier)
	mark("apply_tile_detail", start)

func _sync_tile_collision(item: Dictionary) -> void:
	var start := Time.get_ticks_usec()
	super._sync_tile_collision(item)
	mark("bind_terrain_collider", start)

func _terrain_shape(data: Dictionary, tier: int) -> Shape3D:
	var start := Time.get_ticks_usec()
	var result = super._terrain_shape(data, tier)
	mark("_terrain_shape_%d" % tier, start)
	return result

func cache_local_tile(tid: String) -> void:
	var start := Time.get_ticks_usec()
	super.cache_local_tile(tid)
	mark("cache_local_tile", start)

func _update_asset_tier() -> void:
	var start := Time.get_ticks_usec()
	super._update_asset_tier()
	mark("_update_asset_tier", start)

func _apply_view_visibility() -> void:
	var start := Time.get_ticks_usec()
	super._apply_view_visibility()
	mark("_apply_view_visibility", start)

func water_glints(tid: String, tile: Dictionary, relief: Dictionary) -> MeshInstance3D:
	var start := Time.get_ticks_usec()
	var result = super.water_glints(tid, tile, relief)
	mark("water_glints", start)
	return result

func _ground_clutter(tid: String, standing: Array) -> Mesh:
	var start := Time.get_ticks_usec()
	var result = super._ground_clutter(tid, standing)
	mark("_ground_clutter", start)
	return result

func _ensure_tree_near(pair: Dictionary) -> void:
	var start := Time.get_ticks_usec()
	super._ensure_tree_near(pair)
	mark("_ensure_tree_near", start)

func _ensure_standing_near(pair: Dictionary) -> void:
	var start := Time.get_ticks_usec()
	super._ensure_standing_near(pair)
	mark("_ensure_standing_near", start)

func _ensure_standing_pick(pair: Dictionary) -> void:
	var start := Time.get_ticks_usec()
	super._ensure_standing_pick(pair)
	mark("_ensure_standing_pick", start)
