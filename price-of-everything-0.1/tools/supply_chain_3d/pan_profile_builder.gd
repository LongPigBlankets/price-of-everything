extends "res://scripts/supply_chain_3d/world_builder.gd"
## Measurement-only subclass installed into a disposable capture world.
var probe: Dictionary = {}
var probe_keep := false
var probe_medium_only := false

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

func append_road(parent: Node3D, tid: String) -> void:
	var start := Time.get_ticks_usec()
	super.append_road(parent, tid)
	mark("append_road", start)

func _tile_bake(host: Node, tid: String, tier: int) -> Dictionary:
	var start := Time.get_ticks_usec()
	var result = await super._tile_bake(host, tid, tier)
	mark("_tile_bake", start)
	return result

func refine_tile(host: Node, item: Dictionary, tier: int) -> void:
	var start := Time.get_ticks_usec()
	await super.refine_tile(host, item, tier)
	mark("refine_tile", start)

func apply_tile_detail(item: Dictionary, tier: int) -> void:
	var start := Time.get_ticks_usec()
	_probe_apply_tile_detail(item, tier)
	mark("apply_tile_detail", start)

func release_local_tiles(keep: Dictionary) -> void:
	if probe_keep: return
	var start := Time.get_ticks_usec()
	super.release_local_tiles(keep)
	mark("release_local_tiles", start)

func release_detail(keep: Dictionary) -> void:
	if probe_keep: return
	var start := Time.get_ticks_usec()
	super.release_detail(keep)
	mark("release_detail", start)

func _update_asset_tier() -> void:
	var start := Time.get_ticks_usec()
	super._update_asset_tier()
	mark("_update_asset_tier", start)

func set_detail(tier: int, update_assets: bool = true) -> void:
	var start := Time.get_ticks_usec()
	super.set_detail(tier, update_assets)
	mark("set_detail", start)

func set_overview_scale(ppu: float, force: bool = false) -> void:
	var start := Time.get_ticks_usec()
	super.set_overview_scale(ppu, force)
	mark("set_overview_scale", start)

func water_glints(tid: String, tile: Dictionary, relief: Dictionary) -> MeshInstance3D:
	var start := Time.get_ticks_usec()
	var result = super.water_glints(tid, tile, relief)
	mark("water_glints", start)
	return result

func terrain_key(tid: String) -> String:
	var start := Time.get_ticks_usec()
	var result = super.terrain_key(tid)
	mark("terrain_key", start)
	return result

func _plantable(p: Vector2, tid: String, rel: Dictionary, standing: Array, road_margin: float, nearby_roads: Array) -> bool:
	var start := Time.get_ticks_usec()
	var result = super._plantable(p, tid, rel, standing, road_margin, nearby_roads)
	mark("_plantable", start)
	return result

func standing_frame(s: Dictionary) -> Dictionary:
	var start := Time.get_ticks_usec()
	var result = super.standing_frame(s)
	mark("standing_frame", start)
	return result

func trees_node(tid: String, standing: Array) -> Node3D:
	var start := Time.get_ticks_usec()
	var result := _probe_trees_node(tid, standing)
	mark("trees_node", start)
	return result

func _probe_trees_node(tid: String, standing: Array) -> Node3D:
	var root := Node3D.new()
	root.name = "LandscapeDetail"
	if str(tiles[tid].type) in ["sea", "deep_sea"]: return root
	# Tree shadows are batched with their tile so the renderer can cull them.
	var saved_shadows := shadow_batch
	if streamed: shadow_batch = Geo.Batch.new()
	var near := Geo.Batch.new()
	var c: Vector2 = tiles[tid].center
	var rel: Dictionary = Legacy._relief_of(tid, c)
	var area := Rect2(c - Model.HEX_HALF, Model.HEX_HALF * 2.0).grow(30.0)
	var local_roads: Array = []
	for road in roads:
		if area.intersects(Rect2(road.a, Vector2.ZERO).expand(road.b).grow(20.0)): local_roads.append(road)
	var local_standing: Array = []
	for item in standing:
		if (item.pos as Vector2).distance_squared_to(c) < 500000.0: local_standing.append(item)
	var placements := placements_for(tid, standing)
	tree_placements[tid] = placements
	for kind in ["small", "fir", "large"]:
		var level: int = {"small": 1, "fir": 2, "large": 3}[kind]
		var key := Assets.key_for("tree", level)
		# Godot selects a MultiMesh's mesh LOD from the node transform. Keep the
		# species' main scale there, rather than hiding a 20x scale in each instance;
		# otherwise tiny LODs and their contour shells diverge even at close zoom.
		var species_scale := float(Legacy._TREE_HEIGHT[kind]) / Assets.projected_height(key)
		var transforms: Array[Transform3D] = []
		var cards: Array = []
		for tree in placements:
			if tree.kind != kind: continue
			var scale := float(tree.height) / Assets.projected_height(key)
			transforms.append(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale / species_scale), point(tree.pos) / species_scale))
			cards.append(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale), point(tree.pos) + FarSprites.center(key) * scale))
			var radius := Assets.dimensions(key).x * scale * 0.5
			if not scenery_ready: shadow(tree.pos, radius * 2.0, true)
		if transforms.is_empty(): continue
		if streamed and not local_streaming:
			if not tree_sprite_transforms.has(key): tree_sprite_transforms[key] = []
			tree_sprite_transforms[key].append_array(cards)
		elif not streamed:
			var grove := FarSprites.grove(key, cards, grade_range)
			if grove != null:
				grove.visible = false
				tree_sprite_nodes.append(grove)
		var near_nodes: Array = []
		var medium_grove := FarSprites.grove(key, cards, grade_range, 1) if local_streaming or not streamed else null
		if medium_grove != null: root.add_child(medium_grove)
		for mesh in ([] if probe_medium_only else [Assets.mesh_for(key), Assets.contour_for(key)]):
			if mesh == null: continue
			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.mesh = mesh
			multi.instance_count = transforms.size()
			for i in transforms.size(): multi.set_instance_transform(i, transforms[i])
			var node := MultiMeshInstance3D.new()
			node.name = "Trees_" + kind
			node.multimesh = multi
			node.scale = Vector3.ONE * species_scale
			if mesh == Assets.mesh_for(key): node.material_override = Assets.tree_material(kind == "fir")
			root.add_child(node)
			building_visuals.append(node)
			near_nodes.append(node)
		if medium_grove != null: sprite_pairs.append({"far": null, "medium": medium_grove, "near": near_nodes})
	if not probe_medium_only:
		# Retain close-up ground detail without replacing the source tree composition.
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(tid)
		for i in 130:
			var p := c + Vector2(rng.randf_range(-260, 260), rng.randf_range(-235, 235))
			if not _plantable(p, tid, rel, local_standing, 6.0, local_roads): continue
			var foot := point(p, 0.2)
			if i % 7 == 0:
				# Sparse stones belong on exposed slopes; uniformly scattered grey
				# pebbles made the source board's clear grass read as visual noise.
				if i % 21 != 0 or surface_gradient(p).length() < 0.25: continue
				_crown(near, foot + Vector3.UP * 0.55, Vector3(1.5, 1.1, 1.2), Color("85816b"), 5)
			else:
				for j in 3:
					var angle := float(j) * PI / 3.0
					var side := Vector3(cos(angle), 0, sin(angle)) * 0.6
					near.triangle(foot - side, foot + Vector3.UP * rng.randf_range(1.5, 3.2), foot + side, Color("81834c"))
		add_detail(root, near.mesh(), 2)

	if streamed:
		if not scenery_ready: root.add_child(shadows_node())
		shadow_batch = saved_shadows
	tree_nodes.append(root)
	var group := Node3D.new()
	group.add_child(root)
	if not streamed:
		for node in tree_sprite_nodes:
			if node.get_parent() == null: group.add_child(node)
	return group


func _probe_apply_tile_detail(item: Dictionary, tier: int) -> void:
	while tier > 0 and item.data.meshes[tier] == null: tier -= 1
	item.node.mesh = item.data.meshes[tier]
	item.material.set_shader_parameter("artwork", item.data.textures[tier])
	var rect := Vector4(0, 0, 1, 1)
	if streamed and tier == 0 and not continent.is_empty():
		var area: Rect2 = continent.area
		var offset: Vector2 = ((tiles[item.tile].center as Vector2) - Paint.EXTENT * 0.5 - area.position) / area.size
		var scale := Paint.EXTENT / area.size
		rect = Vector4(offset.x, offset.y, scale.x, scale.y)
	item.material.set_shader_parameter("artwork_rect", rect)
	# Picking follows the displayed surface, including higher-detail river banks.
	if streamed and int(item.get("collision_tier", -1)) != tier and item.has("collider"):
		var shape_start := Time.get_ticks_usec()
		item.collider.shape = (item.node.mesh as Mesh).create_trimesh_shape()
		mark("collision_shape", shape_start)
		item.collision_tier = tier
