extends RefCounted
## Builds the supply-chain world's static geometry. Map-space coordinates and the shared
## height field are authoritative; the camera never participates in generation.
const Geo := preload("res://scripts/supply_chain_3d/geometry.gd")
const Legacy := preload("res://scripts/empire_board.gd")
const Model := preload("res://scripts/empire_board_model.gd")
const Ground := preload("res://scripts/empire_board_ground.gd")
const Relief := preload("res://scripts/supply_chain_3d/relief.gd")
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const ShadowArt := preload("res://scripts/supply_chain_3d/shadow_art.gd")
const FarSprites := preload("res://scripts/supply_chain_3d/far_sprites.gd")
const CELL := 12.0
const Detail := preload("res://scripts/supply_chain_3d/detail.gd")
const Paint := preload("res://scripts/supply_chain_3d/terrain_paint.gd")
const GroundShader := preload("res://scripts/supply_chain_3d/ground.gdshader")
const TreeLayout := preload("res://scripts/supply_chain_3d/tree_layout.gd")
const GlintShader := preload("res://scripts/supply_chain_3d/water_glints.gdshader")
const RoadSurface := preload("res://scripts/supply_chain_3d/road_surface.gd")
const BakeCache := preload("res://scripts/supply_chain_3d/bake_cache.gd")
const Residency := preload("res://scripts/supply_chain_3d/detail_residency.gd")
const LocalDetail := preload("res://scripts/supply_chain_3d/local_detail.gd")
const TileCache := preload("res://scripts/supply_chain_3d/tile_resource_cache.gd")
var resource_cache := TileCache.new()
const Handover := preload("res://scripts/supply_chain_3d/lod_handover.gd")
var handover := Handover.new()
var handover_enabled := false
var _handover_preparing := false
var terrain_lods: Array = []
var detail_nodes: Array = []
var building_visuals: Array = []
var sprite_pairs: Array = []
var tree_sprite_nodes: Array = []
var tree_sprite_transforms: Dictionary = {}
var _sprites_visible := false
var _asset_tier := -1
var grade_range := Vector2.ZERO
var active_lod := -1
var lazy_assets := false
var shadow_batch := Geo.Batch.new()
var origin := Vector2.ZERO
var ground: RefCounted
var rivers: Dictionary = {}
var tiles: Dictionary = {}
var terrain_cache: Dictionary = {}
var mat := ShaderMaterial.new()
var line_mat := Geo.material(true)
var bounds := AABB()
var pickables: Array = []
var labels: Array = []
var flows: Array = []
var cars: Array = []
var smoke: Array = []
var glows: Array = []
var roads: Array = []
var lines: Array = []
var tree_placements: Dictionary = {}
var road_surface := RoadSurface.new()
var pits: Dictionary = {}
var streamed := false
const BASE_RESIDENT_TILES := 96
var local_tiles: Dictionary = {}
var residency := Residency.new()
var backdrop_materials: Array = []
var local_streaming := false
var view_hulls: Dictionary = {}
var _visibility_standing: Dictionary = {}
var _visibility_centers: Dictionary = {}
const VISIBILITY_VERSION := 4
const FOUNDATION_VERSION := 2
var tree_nodes: Array = []
var far_nodes: Array = []
var decor_nodes: Array = []
var _overview := false
var _river_buckets: Dictionary = {}
var _road_height_cache: Dictionary = {}
var road_mat: ShaderMaterial
var glint_nodes: Array = []
var bake_cache := BakeCache.new()
var _map_key := ""
var _continent_key := ""
var _previous_continent_key := ""
var continent: Dictionary = {}
var continent_node: Node3D
var continent_body: StaticBody3D
var road_nodes: Array = []
var _road_key := ""
var frame_nodes: Array = []
var rim_material: ShaderMaterial
var scenery_ready := false
var static_shadows: Dictionary = {}
var decor_sprite_transforms: Dictionary = {}
var standing_frames: Dictionary = {}
var _scenery_key := ""
var tile_chunks: Dictionary = {}
var base_ready := true
var base_loading := false
var _chunk_data: Dictionary = {}
var _detail_standing: Array = []
var _repair_chunks: Dictionary = {}
## Board-controlled picking residency is independent of visual/resource residency.
var cursor_picking := false
var collision_tiles: Dictionary = {}
var collision_revision := 0

func configure_bakes(model: Dictionary) -> void:
	# Hash actual geography, never an instance ID: this survives a fresh process.
	_map_key = BakeCache.digest([BakeCache.source_key("terrain"), ground.get("tiles"), ground.get("bands"),
		ground.get("lakes"), ground.get("rivers"), MapStyle.band_colors(), MapStyle.sea_colors()])
	_road_key = BakeCache.digest([BakeCache.source_key("roads"), _map_key, model.get("roads", []), pits])
	var layout: Array = []
	var geography: Array = []
	var pipes: Array = []
	for tid in tiles: geography.append([tid, tiles[tid].center, tiles[tid].type])
	for s in model.get("standing", []):
		layout.append([s.iid, s.kind, s.tile, s.pos, s.side, s.get("pad", s.side), s.get("internal_name", ""), s.get("tall", false), s.get("level", 1),
			(s.sprite as Texture2D).resource_path if s.get("sprite") is Texture2D else ""])
	for line in model.get("lines", []):
		if Model.PIPE_MODES.has(str(line.mode)): pipes.append([line.mode, line.pts])
	_scenery_key = "scenery-" + BakeCache.digest([BakeCache.source_key("scenery"), _road_key, geography, layout, pipes, Legacy.show.trees, Legacy.show.decor,
		FileAccess.get_sha256(Assets.DIRECTORY + "manifest.json")])
	_continent_key = "continent-" + BakeCache.digest([BakeCache.source_key("continent"), _scenery_key, _road_key, geography, layout, pipes, Legacy.show.trees, Legacy.show.roads, Legacy.show.decor,
		FileAccess.get_sha256(FarSprites.DIRECTORY + "manifest.json")])
	_previous_continent_key = _continent_key
	_continent_key = "continent-" + BakeCache.digest([_previous_continent_key, FOUNDATION_VERSION])

func tile_bake_key(tid: String, tier: int) -> String:
	var holes: Array = []
	var area := Rect2((tiles[tid].center as Vector2) - Model.HEX_HALF, Model.HEX_HALF * 2.0).grow(16.0)
	for pit in pits.values():
		# The graded shoulder reaches beyond the excavation polygon and can
		# alter a neighbouring tile even when the opening stays outside it.
		var reach := float(pit.side) * 0.80
		if area.intersects(Rect2((pit.pos as Vector2) - Vector2.ONE * reach, Vector2.ONE * reach * 2.0)):
			holes.append(pit)
	return "tile-" + BakeCache.digest([_map_key, tid, tiles[tid].center, tiles[tid].type, holes, static_shadows.get(tid, []), tier])

func prepare_scenery(host: Node, model: Dictionary) -> void:
	_detail_standing = model.get("standing", [])
	_visibility_standing.clear()
	for s in model.get("standing", []):
		(_visibility_standing.get_or_add(str(s.tile), []) as Array).append(s)
	var cached := bake_cache.read(_scenery_key) if _scenery_key != "" else {}
	if not cached.is_empty():
		tree_placements = cached.trees
		static_shadows = cached.shadows
		standing_frames = cached.standing
		grade_range = cached.grade
		scenery_ready = true
		return
	var all_shadows: Array = []
	for s in model.get("standing", []):
		standing_frames[str(s.iid)] = standing_frame(s)
		if str(s.kind) == "house": all_shadows.append(ShadowArt.footprint(s.pos, float(s.side), false))
	roads = model.get("roads", [])
	lines = model.get("lines", [])
	for tid in tiles:
		var placements := placements_for(str(tid), model.get("standing", [])) if Legacy.show.trees else []
		tree_placements[tid] = placements
		for tree in placements:
			var key := Assets.key_for("tree", {"small": 1, "fir": 2, "large": 3}[tree.kind])
			var scale := float(tree.height) / Assets.projected_height(key)
			all_shadows.append(ShadowArt.footprint(tree.pos, Assets.dimensions(key).x * scale, true))
		if tree_placements.size() % 16 == 0: await host.get_tree().process_frame
	# A shadow can reach over a hex edge. Include it in both tile painters so
	# filtering and changing terrain tiers cannot cut its footprint at that edge.
	var buckets := {}
	for i in all_shadows.size():
		var area := ShadowArt.bounds(all_shadows[i])
		var low := Vector2i((area.position / 256.0).floor())
		var high := Vector2i((area.end / 256.0).floor())
		for y in range(low.y, high.y + 1):
			for x in range(low.x, high.x + 1): (buckets.get_or_add(Vector2i(x, y), []) as Array).append(i)
	for tid in tiles:
		var area := Rect2(tiles[tid].center - Paint.EXTENT * 0.5, Paint.EXTENT)
		var low := Vector2i((area.position / 256.0).floor())
		var high := Vector2i((area.end / 256.0).floor())
		var found := {}
		for y in range(low.y, high.y + 1):
			for x in range(low.x, high.x + 1):
				for i in buckets.get(Vector2i(x, y), []):
					if area.intersects(ShadowArt.bounds(all_shadows[i])): found[i] = true
		static_shadows[tid] = []
		var ids := found.keys()
		ids.sort()
		for i in ids: static_shadows[tid].append(all_shadows[i])
	scenery_ready = true
	configure_grade()
	if _scenery_key != "": bake_cache.write(_scenery_key, {"trees": tree_placements, "shadows": static_shadows, "standing": standing_frames, "grade": grade_range})

func placements_for(tid: String, standing: Array) -> Array:
	if tree_placements.has(tid): return tree_placements[tid]
	var tile: Dictionary = tiles[tid]
	var area := Rect2(tile.center - Model.HEX_HALF, Model.HEX_HALF * 2.0).grow(30.0)
	var local_roads: Array = []
	for road in roads:
		if area.intersects(Rect2(road.a, Vector2.ZERO).expand(road.b).grow(20.0)): local_roads.append(road)
	var local_standing: Array = []
	for item in standing:
		if (item.pos as Vector2).distance_squared_to(tile.center) < 500000.0: local_standing.append(item)
	return TreeLayout.placements(tid, tile, Legacy._relief_of(tid, tile.center), local_standing, local_roads, lines, rivers.get(tid, []))

func prepare_continent(host: Node) -> void:
	continent = bake_cache.read(_continent_key) if _continent_key != "" else {}
	if continent.is_empty() and not _previous_continent_key.is_empty():
		var previous := bake_cache.read(_previous_continent_key)
		if not previous.is_empty():
			# Only the joined foundations changed. Reuse every terrain texture,
			# tile chunk, road and tree without a continent repaint.
			continent = previous.duplicate()
			var foundations := Geo.Batch.new()
			for group in _visibility_standing.values():
				for standing in group:
					if str(standing.kind) == "house":
						var frame := standing_frame(standing)
						_append_foundation(foundations, standing, frame, frame.position)
			continent.props_mesh = foundations.mesh()
			bake_cache.write(_continent_key, continent)
	if not continent.is_empty():
		tile_chunks = continent.get("tile_chunks", {})
		base_ready = false
		bounds = continent.metadata.bounds
		labels = continent.metadata.get("labels", []).duplicate(true)
		await prepare_visibility_bounds(host, continent.metadata.get("visibility", {}))
		return
	var area := Rect2()
	var first := true
	var parts := {}
	for tid in tiles:
		var tile_area := Rect2((tiles[tid].center as Vector2) - Paint.EXTENT * 0.5, Paint.EXTENT)
		area = tile_area if first else area.merge(tile_area)
		first = false
		parts[tid] = _surface(str(tid), 24.0)
		tile_view_hull(str(tid))
		if parts.size() % 16 == 0: await host.get_tree().process_frame
	var texture := await Paint.bake_continent(host, tiles, rivers, pits.values(), surface_height, area, static_shadows)
	continent = {"area": area, "texture": texture, "parts": parts,
		"mesh": Geo.joined(parts.values(), area), "roads": {}}

func tile_view_hull(tid: String) -> PackedVector3Array:
	if not view_hulls.has(tid):
		var center: Vector2 = tiles[tid].center
		var low := center - Model.HEX_HALF
		var high := center + Model.HEX_HALF
		var heights := Vector2(INF, -INF)
		if ground.has_method("node"):
			# Every spline sample is a positive weighted average of these lattice
			# nodes. Their extrema conservatively bound every terrain LOD, including
			# a summit between the centre and the six corners of the tile.
			var start := (low / Ground.NODE).floor() - Vector2.ONE
			var end := (high / Ground.NODE).ceil() + Vector2.ONE * 2.0
			for y in range(int(start.y), int(end.y) + 1):
				for x in range(int(start.x), int(end.x) + 1):
					var h := Relief.height(ground.node(x, y))
					heights.x = minf(heights.x, h)
					heights.y = maxf(heights.y, h)
		else:
			# Small synthetic/tool ground providers have no lattice to inspect.
			for p in Model.hex_points(center):
				var h := surface_height(p)
				heights.x = minf(heights.x, h)
				heights.y = maxf(heights.y, h)
			heights.x = minf(heights.x, surface_height(center))
			heights.y = maxf(heights.y, surface_height(center))
		for pit in pits.values():
			if Rect2(low, high - low).intersects(pit.area.grow(float(pit.side))):
				heights.x = minf(heights.x, float(pit.height) - float(pit.sink))
				heights.y = maxf(heights.y, float(pit.height))
		if _visibility_centers.is_empty():
			for tile in tiles.values(): _visibility_centers[Vector2i((tile.center as Vector2).round())] = true
		var bottom := heights.x - 24.0
		var hex := Model.hex_points(center)
		for i in 6:
			if not _visibility_centers.has(Vector2i((hex[i] + hex[(i + 1) % 6] - center).round())):
				bottom = minf(bottom, -150.0) # the visible outer cutaway slab
		var box := AABB(Vector3(low.x - origin.x, bottom, low.y - origin.y),
			Vector3(high.x - low.x, heights.y - bottom, high.y - low.y))
		for s in _visibility_standing.get(tid, []):
			var frame := standing_frame(s)
			var anchor: Vector3 = frame.position + FarSprites.center(frame.key) * float(s.side) if str(frame.key) != "" else frame.position + Vector3.UP * float(frame.dimension.y) * 0.5
			box = box.merge(_sprite_view_bounds(anchor, frame.dimension))
		for tree in tree_placements.get(tid, []):
			var key := Assets.key_for("tree", {"small": 1, "fir": 2, "large": 3}[tree.kind])
			var scale := float(tree.height) / Assets.projected_height(key)
			var dimension := Assets.dimensions(key) * scale
			var anchor := point(tree.pos) + FarSprites.center(key) * scale
			box = box.merge(_sprite_view_bounds(anchor, dimension))
		box = box.grow(16.0) # outlines, foundations and sprite angle quantisation
		var hull := PackedVector3Array([point(center)])
		for i in 8: hull.append(box.get_endpoint(i))
		view_hulls[tid] = hull
	return view_hulls[tid]

static func _sprite_view_bounds(anchor: Vector3, dimension: Vector3) -> AABB:
	# A depth card at the nearest baked angle effectively rotates its source
	# around the anchor. Bound that displacement too, especially tall chimneys.
	var angular_slack := dimension.length() * 0.5 * (PI / 16.0 + (1.35 - 0.30) / 8.0)
	return AABB(anchor - dimension * 0.5, dimension).grow(angular_slack)

func visibility_bake() -> Dictionary:
	return {"version": VISIBILITY_VERSION, "origin": origin, "hulls": view_hulls}

func _restore_visibility(data: Dictionary) -> bool:
	if data.get("version", -1) != VISIBILITY_VERSION or data.get("origin") != origin: return false
	var hulls: Dictionary = data.get("hulls", {})
	if hulls.size() != tiles.size(): return false
	for tid in tiles:
		if not hulls.get(tid) is PackedVector3Array or hulls[tid].size() != 9: return false
	view_hulls = hulls
	return true

func visibility_bake_key() -> String:
	return "visibility-" + BakeCache.digest([_continent_key, origin, VISIBILITY_VERSION])

func prepare_visibility_bounds(host: Node, baked: Dictionary = {}) -> void:
	if _restore_visibility(baked): return
	# Old continent bakes can acquire the small metadata supplement without
	# invalidating their artwork or rewriting hundreds of geometry chunks.
	var key := visibility_bake_key()
	if _continent_key != "" and _restore_visibility(bake_cache.read(key)): return
	view_hulls.clear()
	for tid in tiles:
		tile_view_hull(str(tid))
		if view_hulls.size() % 16 == 0: await host.get_tree().process_frame
	if _continent_key != "": bake_cache.write(key, visibility_bake())

func base_chunk(tid: String) -> Dictionary:
	if _chunk_data.has(tid): return _chunk_data[tid]
	var key := str(tile_chunks.get(tid, ""))
	var data := bake_cache.read(key) if key != "" else {}
	if data.is_empty():
		# A user cache can be partially evicted. Recreate only the requested tile;
		# the existing far resource remains usable while detail is repaired.
		data = {"mesh": _surface(tid, 24.0)}
		_repair_chunks[tid] = true
	_chunk_data[tid] = data
	return data

func prepare_local_detail(tid: String, standing: Array) -> Dictionary:
	var chunk := base_chunk(tid)
	var fingerprint := BakeCache.source_key("detail")
	if chunk.get("detail_source", "") != fingerprint or not chunk.has("local_detail"):
		chunk.local_detail = LocalDetail.build(self, tid, standing)
		chunk.detail_source = fingerprint
	return chunk.local_detail

static func prepare_picking(data: Dictionary) -> void:
	if not data.get("pick_shape") is ConcavePolygonShape3D:
		data.pick_shape = (data.mesh as Mesh).create_trimesh_shape()

func persist_base_chunk(tid: String) -> void:
	if not _repair_chunks.has(tid): return
	var data: Dictionary = _chunk_data[tid]
	if not data.has("rim_mesh") or (Legacy.show.roads and not data.has("roads_mesh")): return
	var key := str(tile_chunks.get(tid, ""))
	if key != "": bake_cache.write(key, data)
	_repair_chunks.erase(tid)

func finish_continent(parent: Node3D) -> void:
	if continent.is_empty(): return
	if not continent.has("roads_mesh"):
		bake_cache.defer_trim = true
		continent.roads_mesh = Geo.joined(continent.roads.values())
		var props: Array = []
		for node in far_nodes:
			if node is MeshInstance3D: props.append(node.mesh)
			for child in node.find_children("*", "MeshInstance3D", true, false): props.append(child.mesh)
		continent.props_mesh = Geo.joined(props)
		continent.tree_sprites = tree_sprite_transforms
		continent.decor_sprites = decor_sprite_transforms
		var rims: Array = []
		var lips: Array = []
		for frame in frame_nodes:
			rims.append(frame.rim.mesh)
			lips.append(frame.lip.mesh)
			var tid := str(frame.tile)
			var chunk := {"mesh": continent.parts[tid], "roads_mesh": continent.roads.get(tid),
				"rim_mesh": frame.rim.mesh, "lip_mesh": frame.lip.mesh}
			var key := "base-tile-" + BakeCache.digest([BakeCache.source_key("continent"), _road_key, tid, tiles[tid].center, tiles[tid].type, tiles.keys()])
			tile_chunks[tid] = key
			if _continent_key != "": bake_cache.write(key, chunk)
			else: _chunk_data[tid] = chunk
		continent.rim_mesh = Geo.joined(rims)
		continent.lip_mesh = Geo.joined(lips)
		continent.tile_chunks = tile_chunks
		continent.metadata = {"origin": origin, "bounds": bounds, "grade": grade_range,
			"tiles": tiles.duplicate(true), "labels": labels.duplicate(true), "standing": standing_frames, "scenery_key": _scenery_key,
			"visibility": visibility_bake()}
		# Only string keys link to detail resources. Resource subreferences would
		# eagerly deserialize every tile when opening the far map again.
		continent.erase("parts")
		continent.erase("roads")
		if _continent_key != "":
			bake_cache.write(_continent_key, continent)
			bake_cache.trim()
		bake_cache.defer_trim = false
	continent_node = Node3D.new()
	continent_node.name = "ContinentBake"
	var paint := mat.duplicate() as ShaderMaterial
	paint.set_shader_parameter("textured", true)
	paint.set_shader_parameter("artwork", continent.texture)
	continent_node.add_child(Geo.instance(continent.mesh, paint))
	continent_node.add_child(Geo.instance(continent.roads_mesh, road_mat))
	continent_node.add_child(Geo.instance(continent.props_mesh, mat))
	continent_node.add_child(Geo.instance(continent.rim_mesh, strata_material()))
	continent_node.add_child(Geo.instance(continent.lip_mesh, mat))
	for groups in [continent.get("tree_sprites", {}), continent.get("decor_sprites", {})]:
		for key in groups:
			var grove := FarSprites.grove(key, groups[key], grade_range)
			if grove != null: continent_node.add_child(grove)
	continent_node.visible = false
	parent.add_child(continent_node)
	# The joined far surface doubles as the selection surface; tile identity is
	# recovered from its map-space hit position, without 600 duplicate meshes.
	var body := StaticBody3D.new()
	continent_body = body
	body.name = "ContinentPick"
	body.collision_layer = 4 if cursor_picking else 1
	body.collision_mask = 0
	body.set_meta("continent_pick", true)
	var shape := CollisionShape3D.new()
	shape.shape = _coarse_pick_shape(continent.mesh) if cursor_picking else (continent.mesh as Mesh).create_trimesh_shape()
	body.add_child(shape)
	parent.add_child(body)
	residency.configure(tiles, origin)
	for child in continent_node.get_children():
		if not child is GeometryInstance3D or child.material_override == null: continue
		var material := child.material_override.duplicate() as ShaderMaterial
		material.set_meta("road", child.material_override == road_mat)
		material.set_meta("foliage", str(child.name).begins_with("FarTrees_tree_"))
		child.material_override = material
		residency.bind(material)
		backdrop_materials.append(material)

func prepare_company_pick_surface(parent: Node3D) -> void:
	# Reuse the lowest-detail company surfaces to locate the cursor while detailed
	# tile collision is detached. Continent views already have this shared surface.
	if not cursor_picking or continent_body != null: return
	var meshes: Array = []
	for item in terrain_lods: meshes.append(item.data.meshes[0])
	if meshes.is_empty(): return
	continent_body = StaticBody3D.new()
	continent_body.name = "CompanyPick"
	continent_body.collision_layer = 4
	continent_body.collision_mask = 0
	continent_body.set_meta("continent_pick", true)
	var shape := CollisionShape3D.new()
	shape.shape = _coarse_pick_shape(Geo.joined(meshes))
	continent_body.add_child(shape)
	parent.add_child(continent_body)

func _coarse_pick_shape(mesh: Mesh) -> Shape3D:
	# Mine openings must still select a tile at far zoom when their individual
	# bodies are detached. Cap only the invisible shared locator at the rim level.
	if pits.is_empty(): return mesh.create_trimesh_shape()
	var faces := mesh.get_faces()
	for pit in pits.values():
		var indices := Geometry2D.triangulate_polygon(pit.rim)
		for index in indices: faces.append(at_height(pit.rim[index], pit.height))
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	return shape

func collision_detail_visible() -> bool:
	return not _sprites_visible and not _overview and (not handover_enabled or handover.blend >= 1.0)

func set_collision_tiles(wanted: Dictionary) -> void:
	if collision_tiles == wanted: return
	collision_tiles = wanted.duplicate()
	for item in terrain_lods: _sync_tile_collision(item)
	for pair in sprite_pairs:
		if pair.get("standing") is Dictionary: _ensure_standing_pick(pair)

func _sync_tile_collision(item: Dictionary) -> void:
	var active := not cursor_picking or (collision_detail_visible() and collision_tiles.has(str(item.tile)))
	if not active:
		if item.has("collider") and item.collider.shape != null: item.collider.shape = null
		item.collision_tier = -1
		return
	if not item.has("collider"):
		var body := StaticBody3D.new()
		body.name = "TilePick"
		body.collision_layer = 1
		body.collision_mask = 0
		body.set_meta("tile_id", str(item.tile))
		var collider := CollisionShape3D.new()
		body.add_child(collider)
		item.node.get_parent().add_child(body)
		item.collider = collider
	var tier := int(item.get("display_tier", 0)) if streamed or cursor_picking else 0
	if int(item.get("collision_tier", -1)) == tier: return
	item.collider.shape = _terrain_shape(item.data, tier)
	item.collision_tier = tier

func update_residency() -> void:
	residency.update(local_tiles if not _overview or handover.active else {})
	for material in backdrop_materials:
		material.set_shader_parameter("local_detail_mask", not _overview or handover.active)
		material.set_shader_parameter("local_detail_blend", handover.blend if handover_enabled else 1.0)

func complete_detail_request() -> void:
	if handover_enabled and not _overview and handover.blend < 1.0:
		_begin_handover(1.0)

func _begin_handover(target: float) -> void:
	if handover.active and is_equal_approx(handover.target, target): return
	handover.clear()
	if is_equal_approx(handover.blend, target):
		_apply_view_visibility()
		return
	# Both representations must be drawable before their complementary coverage
	# is applied. Materials are temporary copies; stable shared assets stay intact.
	_handover_preparing = true
	_apply_view_visibility()
	var local: Array = []
	var far: Array = []
	for record in local_tiles.values():
		for node in record.root.find_children("*", "GeometryInstance3D", true, false):
			if node.is_visible_in_tree(): local.append(node)
	for pair in sprite_pairs:
		if pair.get("decor", false): continue # The continent already contains its far houses.
		if pair.get("far") != null: far.append(pair.far)
		if pair.get("medium") != null and pair.medium.visible: local.append(pair.medium)
		for node in pair.near:
			if node.visible: local.append(node)
	handover.begin(target, local, far)
	_handover_preparing = false
	_apply_view_visibility()

func advance_handover() -> void:
	if not handover.active: return
	handover.advance()
	_apply_view_visibility()

func _apply_view_visibility() -> void:
	if cursor_picking and not collision_detail_visible(): set_collision_tiles({})
	var local := not _overview
	if handover_enabled: local = handover.blend > 0.0 or _handover_preparing
	if continent_node != null:
		continent_node.visible = true
		update_residency()
		for record in local_tiles.values(): record.root.visible = local
		for item in terrain_lods: item.node.visible = local
		for node in road_nodes: node.visible = local
		for frame in frame_nodes:
			frame.rim.visible = local
			frame.lip.visible = local
	for node in decor_nodes: node.visible = local
	for node in far_nodes: node.visible = _overview and continent_node == null
	for node in glint_nodes: node.visible = local
	_update_asset_tier()

func release_local_tiles(keep: Dictionary, retain_resources: bool = false) -> void:
	for tid in local_tiles.keys():
		if keep.has(tid): continue
		if retain_resources: cache_local_tile(str(tid))
		else: resource_cache.erase(str(tid))
		var record: Dictionary = local_tiles[tid]
		collision_revision += 1
		# Metadata arrays must not retain freed nodes or accumulate duplicate
		# pickables/glows after a pan away and back.
		for field in record.records:
			var items: Array = get(field)
			for value in record.records[field]: items.erase(value)
		record.root.free()
		terrain_cache.erase(terrain_key(tid))
		_chunk_data.erase(tid)
		local_tiles.erase(tid)
	if continent_node != null: update_residency()

func cache_local_tile(tid: String) -> void:
	var key := terrain_key(tid)
	if terrain_cache.has(key): resource_cache.put(tid, terrain_cache[key], _chunk_data.get(tid, {}), Time.get_ticks_msec())

func prefetch_medium(tid: String) -> bool:
	if not resource_cache.can_prefetch() or local_tiles.has(tid): return false
	var existing: Dictionary = resource_cache.entries.get(tid, {})
	if not existing.is_empty() and existing.data.meshes[1] != null: return false
	# Prefetch never generates scenery or creates a node/collider. Missing bakes
	# remain a foreground repair, so travel cannot launch an invisible rebake.
	var key := str(tile_chunks.get(tid, ""))
	if key == "": return false
	var chunk: Dictionary = existing.get("chunk", {})
	if chunk.is_empty(): chunk = bake_cache.read(key)
	if chunk.is_empty(): return false
	var fine := bake_cache.read(tile_bake_key(tid, 1))
	# Admission can fail after the read. Work on new containers so a rejected
	# upgrade cannot silently grow an existing entry without updating its cost.
	var data: Dictionary = existing.get("data", {"textures": [continent.texture, null, null],
		"meshes": [chunk.mesh, null, null], "streamed": true, "ground_id": ground.get_instance_id()}).duplicate()
	data.textures = data.textures.duplicate()
	data.meshes = data.meshes.duplicate()
	data.shapes = data.get("shapes", [chunk.get("pick_shape"), null, null]).duplicate()
	if not fine.is_empty():
		data.textures[1] = fine.texture
		data.meshes[1] = fine.mesh
		data.shapes[1] = fine.get("pick_shape")
	if not resource_cache.can_prefetch(maxi(0, TileCache.estimate(data, chunk) - int(existing.get("bytes", 0)))): return false
	resource_cache.put(tid, data, chunk, Time.get_ticks_msec())
	return true

func _terrain_shape(data: Dictionary, tier: int) -> Shape3D:
	if not data.has("shapes"): data.shapes = [null, null, null]
	if data.shapes[tier] == null: data.shapes[tier] = (data.meshes[tier] as Mesh).create_trimesh_shape()
	return data.shapes[tier]

func strata_material() -> ShaderMaterial:
	if rim_material == null:
		rim_material = mat.duplicate() as ShaderMaterial
		rim_material.set_shader_parameter("textured", true)
		rim_material.set_shader_parameter("strata", true)
		rim_material.set_shader_parameter("artwork", load("res://assets/iso/ground/strata.png"))
	return rim_material

func tile_at(p: Vector3) -> String:
	var map_point := Vector2(p.x, p.z) + origin
	var nearest := ""
	var distance := INF
	for tid in tiles:
		var d := map_point.distance_squared_to(tiles[tid].center)
		if d <= Model.HEX_HALF.length_squared() and Geometry2D.is_point_in_polygon(map_point, Model.hex_points(tiles[tid].center)): return str(tid)
		if d < distance: nearest = str(tid); distance = d
	return nearest

func configure_pits(standing: Array) -> void:
	pits.clear()
	for s in standing:
		if str(s.get("internal_name", "")) != "mine": continue
		var data := Assets.pit_for(int(s.get("level", 1)))
		if data.is_empty(): continue
		var rim := PackedVector2Array()
		var side := float(s.get("side", 80.0))
		for xy in data.rim: rim.append((s.pos as Vector2) + Vector2(xy[0], xy[1]) * side)
		var area := Rect2(rim[0], Vector2.ZERO)
		for p in rim: area = area.expand(p)
		pits[str(s.iid)] = {"rim": rim, "area": area, "tile": str(s.tile), "height": ground_height(s.pos),
			"sink": float(data.sink) * side, "step": float(data.step) * side, "pos": s.pos, "side": side, "seed": hash(str(s.iid))}

func _mine_grade(p: Vector2) -> Vector2:
	var result := Vector2.ZERO # weight, mine datum
	for pit in pits.values():
		var distance := p.distance_to(pit.pos) / float(pit.side)
		if distance >= 0.80: continue
		var weight := 1.0 - smoothstep(0.62, 0.80, distance)
		if weight > result.x: result = Vector2(weight, pit.height)
	return result

func ground_height(p: Vector2) -> float:
	return Relief.height(ground.height(p))

func surface_height(p: Vector2) -> float:
	var grade := _mine_grade(p)
	return lerpf(ground_height(p), grade.y, grade.x)

func surface_gradient(p: Vector2) -> Vector2:
	var grade := _mine_grade(p)
	if grade.x == 0.0: return ground.gradient(p) * Relief.slope_scale(ground.height(p))
	if grade.x == 1.0: return Vector2.ZERO
	return Vector2(surface_height(p + Vector2.RIGHT) - surface_height(p - Vector2.RIGHT),
		surface_height(p + Vector2.DOWN) - surface_height(p - Vector2.DOWN)) * 0.5

func _cut_pits(poly: PackedVector2Array) -> Array[PackedVector2Array]:
	var parts: Array[PackedVector2Array] = [poly]
	var bounds := Rect2(poly[0], Vector2.ZERO)
	for p in poly: bounds = bounds.expand(p)
	for pit in pits.values():
		if not bounds.intersects(pit.area): continue
		var cut: Array[PackedVector2Array] = []
		for part in parts: cut.append_array(Geometry2D.clip_polygons(part, pit.rim))
		parts = cut
	return parts

func mine_rims_node() -> MeshInstance3D:
	# The sprite cut pass kept the first inward-facing wall of the removed earth
	# block. In 3D it joins the terrain opening to the first submerged bench.
	var batch := Geo.Batch.new()
	for pit in pits.values():
		var rim: PackedVector2Array = pit.rim
		for i in rim.size():
			var a := rim[i]
			var b := rim[(i + 1) % rim.size()]
			var steps := maxi(1, ceili(a.distance_to(b) / 3.0))
			for j in steps:
				var p := a.lerp(b, float(j) / steps)
				var q := a.lerp(b, float(j + 1) / steps)
				var h: float = pit.height - pit.step
				batch.quad(point(p, 0.08), point(q, 0.08), at_height(q, h), at_height(p, h), Color(0.310, 0.273, 0.226))
	var material := Assets.print_material()
	return Geo.instance(batch.mesh(), material)

func point(p: Vector2, lift: float = 0.0) -> Vector3:
	return Vector3(p.x - origin.x, surface_height(p) + lift, p.y - origin.y)

func at_height(p: Vector2, height: float) -> Vector3:
	return Vector3(p.x - origin.x, height, p.y - origin.y)

func configure_grade() -> void:
	if grade_range == Vector2.ZERO:
		grade_range = Vector2(INF, -INF)
		for tile in tiles.values():
			for p in Model.hex_points(tile.center):
				var y := Legacy.iso(p, ground_height(p)).y
				grade_range.x = minf(grade_range.x, y)
				grade_range.y = maxf(grade_range.y, y)
	mat.shader = GroundShader
	mat.set_shader_parameter("grade_range", grade_range)
	Assets.set_grade(grade_range)

func terrain_key(tid: String) -> String:
	var holes: Array = []
	var bounds := Rect2((tiles[tid].center as Vector2) - Model.HEX_HALF, Model.HEX_HALF * 2.0)
	for pit in pits.values():
		var reach := float(pit.side) * 0.80
		if bounds.intersects(Rect2((pit.pos as Vector2) - Vector2.ONE * reach, Vector2.ONE * reach * 2.0)):
			holes.append([pit.rim, pit.height, pit.seed])
	return "%s:%s:%s:%s" % [tid, ground.get_instance_id(), hash([MapStyle.band_colors(), MapStyle.sea_colors(), holes]), _continent_key if streamed else "company"]

func prepare_tile(host: Node, tid: String) -> void:
	var key := terrain_key(tid)
	if streamed and not terrain_cache.has(key):
		var retained := resource_cache.restore(tid)
		if not retained.is_empty():
			terrain_cache[key] = retained.data
			_chunk_data[tid] = retained.chunk
	if streamed:
		prepare_local_detail(tid, _detail_standing)
	if terrain_cache.has(key):
		if streamed and not continent.is_empty():
			# All tiles share the one atlas loaded for this build, including after
			# owned → all → owned → all switches; never retain two atlas copies.
			terrain_cache[key].textures[0] = continent.texture
			terrain_cache[key].meshes[0] = continent.parts[tid] if continent.has("parts") else base_chunk(tid).mesh
		return
	if streamed:
		if continent.is_empty(): await prepare_continent(host)
		terrain_cache[key] = {"textures": [continent.texture, null, null], "meshes": [continent.parts[tid] if continent.has("parts") else base_chunk(tid).mesh, null, null], "shapes": [base_chunk(tid).get("pick_shape"), null, null], "streamed": true, "ground_id": ground.get_instance_id()}
		return
	var textures: Array = []
	var meshes: Array = []
	for tier in 3:
		var data := await _tile_bake(host, tid, tier)
		textures.append(data.texture)
		meshes.append(data.mesh)
		await host.get_tree().process_frame
	terrain_cache[key] = {"textures": textures, "meshes": meshes}

func _tile_bake(host: Node, tid: String, tier: int) -> Dictionary:
	var key := tile_bake_key(tid, tier)
	var cached := bake_cache.read(key) if _map_key != "" else {}
	if not cached.is_empty(): return cached
	var textures := await Paint.bake(host, tiles[tid], Legacy._relief_of(tid, tiles[tid].center), rivers.get(tid, []), pits.values(), surface_height, [Detail.TEXTURES[tier]], static_shadows.get(tid, []))
	var data := {"texture": textures[0], "mesh": _surface(tid, Detail.CELLS[tier])}
	prepare_picking(data)
	if _map_key != "": bake_cache.write(key, data)
	return data

func refine_tile(host: Node, item: Dictionary, tier: int) -> void:
	if item.data.meshes[tier] != null:
		apply_tile_detail(item, tier)
		return
	var tid := str(item.tile)
	var data := await _tile_bake(host, tid, tier)
	if not is_instance_valid(item.node): return
	item.data.textures[tier] = data.texture
	item.data.meshes[tier] = data.mesh
	if not item.data.has("shapes"): item.data.shapes = [null, null, null]
	item.data.shapes[tier] = data.get("pick_shape")
	apply_tile_detail(item, tier)
	if streamed: cache_local_tile(tid)

func apply_tile_detail(item: Dictionary, tier: int) -> void:
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
	if int(item.get("display_tier", -1)) != tier: collision_revision += 1
	item.display_tier = tier
	_sync_tile_collision(item)

func release_detail(keep: Dictionary, retain_resources: bool = false) -> void:
	for item in terrain_lods:
		if keep.has(str(item.tile)): continue
		if item.data.meshes[1] == null and item.data.meshes[2] == null: continue
		apply_tile_detail(item, 0)
		if retain_resources: continue
		for tier in [1, 2]:
			item.data.meshes[tier] = null
			item.data.textures[tier] = null
			if item.data.has("shapes"): item.data.shapes[tier] = null

func _surface(tid: String, cell: float) -> ArrayMesh:
	var center: Vector2 = tiles[tid].center
	var hex := Model.hex_points(center)
	var batch := Geo.Batch.new()
	var low := ((center - Model.HEX_HALF) / cell).floor()
	var high := ((center + Model.HEX_HALF) / cell).ceil()
	for y in range(int(low.y), int(high.y)):
		for x in range(int(low.x), int(high.x)):
			var a := Vector2(x, y) * cell
			var square := PackedVector2Array([a, a + Vector2(cell, 0), a + Vector2(cell, cell), a + Vector2(0, cell)])
			for tile_part in Geometry2D.intersect_polygons(square, hex):
				for poly in _cut_pits(tile_part):
					var indices := Geometry2D.triangulate_polygon(poly)
					for i in range(0, indices.size(), 3):
						var before := batch.vertices.size()
						batch.triangle(point(poly[indices[i]]), point(poly[indices[i + 2]]), point(poly[indices[i + 1]]), Color.WHITE)
						for j in range(before, batch.vertices.size()):
							var v: Vector3 = batch.vertices[j]
							var grad := surface_gradient(Vector2(v.x, v.z) + origin)
							batch.normals[j] = Vector3(-grad.x, 1, -grad.y).normalized()
	return batch.mesh(Rect2(center - origin - Paint.EXTENT * 0.5, Paint.EXTENT))

func tile_node(tid: String) -> Node3D:
	var tile: Dictionary = tiles[tid]
	var center: Vector2 = tile.center
	var root := Node3D.new()
	root.name = tid
	var data: Dictionary = terrain_cache[terrain_key(tid)]
	var surface: ArrayMesh = data.meshes[0]
	var paint := mat.duplicate() as ShaderMaterial
	paint.set_shader_parameter("textured", true)
	if not data.textures.is_empty(): paint.set_shader_parameter("artwork", data.textures[0])
	var land := Geo.instance(surface, paint)
	land.name = "Terrain"
	root.add_child(land)
	var item := {"node": land, "material": paint, "data": data, "tile": tid, "display_tier": 0, "collision_tier": -1}
	terrain_lods.append(item)
	collision_revision += 1
	_sync_tile_collision(item)
	var cached: Dictionary = _chunk_data.get(tid, {})
	if cached.has("rim_mesh"):
		var rim_node := Geo.instance(cached.rim_mesh, strata_material())
		var lip_node := Geo.instance(cached.lip_mesh, mat)
		root.add_child(rim_node)
		root.add_child(lip_node)
		frame_nodes.append({"tile": tid, "rim": rim_node, "lip": lip_node})
		_tile_finishing(root, tid)
		return root
	var rim := Geo.Batch.new()
	var lip := Geo.Batch.new()
	var relief: Dictionary = Legacy._relief_of(tid, center)
	var is_sea := str(tile.type) in ["sea", "deep_sea"]
	var sea := MapStyle.sea_colors()
	var hex := Model.hex_points(center)
	var centers: Dictionary = {}
	for t in tiles.values(): centers[Vector2i((t.center as Vector2).round())] = true
	for i in 6:
		var a: Vector2 = hex[i]
		var b: Vector2 = hex[(i + 1) % 6]
		if centers.has(Vector2i((a + b - center).round())): continue
		var steps := ceili(a.distance_to(b) / 4.0)
		for j in steps:
			var pa := a.lerp(b, float(j) / steps)
			var pb := a.lerp(b, float(j + 1) / steps)
			var ah := surface_height(pa)
			var bh := surface_height(pb)
			# Coast cutaways keep the original blue water depth above the strata;
			# dry land has a thin turf lip. Both follow the real surface at every edge.
			var inward := (center - (pa + pb) * 0.5).normalized()
			var edge_width := (b - a).orthogonal().normalized() * Legacy._INK_W * 0.65
			lip.quad(point(pa - edge_width, 0.12), point(pb - edge_width, 0.12),
				point(pb + edge_width, 0.12), point(pa + edge_width, 0.12), Legacy._INK)
			var wet := is_sea or Ground.is_water(relief, (pa + pb) * 0.5 + inward * 3.0)
			var depth := Legacy._WATER_DEPTH if wet else Legacy._TURF
			var first_lip := lip.vertices.size()
			lip.quad(at_height(pa, ah), at_height(pb, bh), at_height(pb, bh - depth), at_height(pa, ah - depth),
				sea[4].lightened(0.12) if wet else Legacy._warm(sea[5]).darkened(0.38))
			if wet:
				for k in range(first_lip, lip.vertices.size()):
					var v: Vector3 = lip.vertices[k]
					var h := surface_height(Vector2(v.x, v.z) + origin)
					lip.colors[k] = sea[4].lightened(0.12).lerp(sea[1], clampf((h - v.y) / depth, 0.0, 1.0))
				lip.quad(at_height(pa, ah - depth), at_height(pb, bh - depth),
					at_height(pb, bh - depth - 1.6), at_height(pa, ah - depth - 1.6), Legacy._INK)
			ah -= depth
			bh -= depth
			rim.quad(at_height(pa, ah), at_height(pb, bh), at_height(pb, -150.0), at_height(pa, -150.0), Color.WHITE)
			var ua := float(j) / steps
			var ub := float(j + 1) / steps
			var va := (100.0 - ah) / 250.0
			var vb := (100.0 - bh) / 250.0
			rim.uvs.append_array(PackedVector2Array([Vector2(ua, va), Vector2(ub, 1), Vector2(ub, vb), Vector2(ua, va), Vector2(ua, 1), Vector2(ub, 1)]))
	var strata := mat.duplicate() as ShaderMaterial
	strata.set_shader_parameter("textured", true)
	strata.set_shader_parameter("strata", true)
	strata.set_shader_parameter("artwork", load("res://assets/iso/ground/strata.png"))
	var rim_node := Geo.instance(rim.mesh(), strata)
	var lip_node := Geo.instance(lip.mesh(), mat)
	root.add_child(rim_node)
	root.add_child(lip_node)
	frame_nodes.append({"tile": tid, "rim": rim_node, "lip": lip_node})
	if _repair_chunks.has(tid):
		_chunk_data[tid].rim_mesh = rim_node.mesh
		_chunk_data[tid].lip_mesh = lip_node.mesh
		persist_base_chunk(tid)
	rim_material = strata
	_tile_finishing(root, tid)
	return root

func _tile_finishing(root: Node3D, tid: String) -> void:
	var tile: Dictionary = tiles[tid]
	var center: Vector2 = tile.center
	var relief: Dictionary = Legacy._relief_of(tid, center)
	var glints := water_glints(tid, tile, relief)
	root.add_child(glints)
	glint_nodes.append(glints)
	if not local_streaming:
		labels.append({"tile": tid, "text": tile.label, "point": point(center + Vector2(135, 240) * 0.72, 4.0)})

func water_glints(tid: String, tile: Dictionary, relief: Dictionary) -> MeshInstance3D:
	var detail: Dictionary = _chunk_data.get(tid, {}).get("local_detail", {}) if streamed else {}
	var mesh: ArrayMesh = detail.get("glint_mesh")
	if mesh == null: mesh = LocalDetail.glints(self, tid, tile, relief)
	var material := ShaderMaterial.new()
	material.shader = GlintShader
	return Geo.instance(mesh, material)

func set_detail(tier: int, update_assets: bool = true) -> void:
	if tier == active_lod: return
	active_lod = tier
	# Keep the outgoing medium surface/collider through its two transition frames.
	# Streaming will release fine terrain once the far handover has completed.
	if not (handover_enabled and tier == 0):
		for item in terrain_lods: apply_tile_detail(item, tier)
	for item in detail_nodes: item.node.visible = tier >= int(item.minimum)
	# Imported glTF mesh LODs handle individual buildings as projected size changes.
	for visual in building_visuals: visual.lod_bias = [0.8, 1.2, 2.0][tier]
	Assets.set_detail(tier)
	if update_assets: _update_asset_tier()

func set_overview_scale(ppu: float, force: bool = false) -> void:
	FarSprites.set_overview_scale(ppu, streamed)
	var sprites_visible := (streamed and not base_ready) or ppu < (0.33 if _sprites_visible else 0.27)
	if sprites_visible != _sprites_visible or _asset_tier != active_lod or force:
		_sprites_visible = sprites_visible
		_update_asset_tier()
	for material in backdrop_materials:
		if material.get_meta("foliage", false): material.set_shader_parameter("foliage_softness", FarSprites._foliage_softness)
		if material.get_meta("road", false): material.set_shader_parameter("road_fade", 0.78 if sprites_visible else 0.18)
	var overview := streamed and (not base_ready or ppu < (0.33 if _overview else 0.27))
	if road_mat != null: road_mat.set_shader_parameter("road_fade", 0.78 if overview else (0.18 if streamed and ppu < 1.5 else 0.0))
	if overview == _overview and not force: return
	_overview = overview
	if continent_body != null: continent_body.collision_layer = 4 if cursor_picking else 1
	if handover_enabled and overview:
		_begin_handover(0.0)
	else:
		# A zoom-in waits for its requested tiles before revealing local detail.
		if handover_enabled and handover.active and handover.target == 0.0: _begin_handover(1.0)
		_apply_view_visibility()

func _update_asset_tier() -> void:
	_asset_tier = active_lod
	var far_visible := _sprites_visible
	var local_visible := not _sprites_visible
	if handover_enabled:
		far_visible = handover.blend < 1.0 or _handover_preparing
		local_visible = handover.blend > 0.0 or _handover_preparing
	for pair in sprite_pairs:
		if pair.get("clutter", false):
			if local_visible and active_lod == 2: _ensure_tree_near(pair)
			for node in pair.near: node.visible = local_visible and active_lod == 2
			continue
		var medium := local_visible and active_lod < 2 and bool(pair.get("medium_allowed", true))
		if medium and pair.get("medium") == null and pair.has("standing"):
			var card := FarSprites.instance(pair.key, grade_range, 1, pair.get("lit", false))
			if card != null:
				card.scale = Vector3.ONE * float(pair.standing.side)
				card.position = FarSprites.center(pair.key) * float(pair.standing.side)
				pair.root.add_child(card)
				pair.medium = card
		medium = medium and pair.get("medium") != null
		if local_visible:
			if pair.has("standing"): _ensure_standing_pick(pair)
			if not medium:
				if pair.get("tree", false): _ensure_tree_near(pair)
				elif pair.has("standing"): _ensure_standing_near(pair)
		if pair.get("far") != null: pair.far.visible = far_visible and not (handover_enabled and pair.get("decor", false))
		if pair.get("medium") != null: pair.medium.visible = medium
		for node in pair.near: node.visible = local_visible and not medium
	for node in tree_sprite_nodes: node.visible = far_visible
	for node in tree_nodes: node.visible = local_visible or not streamed


func distant_towns(standing: Array) -> Node3D:
	var root := Node3D.new()
	var foundations := Geo.Batch.new()
	decor_sprite_transforms.clear()
	for s in standing:
		if str(s.kind) != "house": continue
		var frame := standing_frame(s)
		var key := str(frame.key)
		var scale := float(s.side)
		var transforms: Array = decor_sprite_transforms.get_or_add(key, [])
		transforms.append(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale), frame.position + FarSprites.center(key) * scale))
		_append_foundation(foundations, s, frame, frame.position)
	root.add_child(Geo.instance(foundations.mesh(), mat))
	root.visible = false
	far_nodes.append(root)
	return root

func add_detail(parent: Node3D, mesh: Mesh, minimum: int) -> void:
	var node := Geo.instance(mesh, mat)
	parent.add_child(node)
	detail_nodes.append({"node": node, "minimum": minimum})

func shadow(p: Vector2, side: float, tree: bool = false) -> void:
	# The old board's north-west shadow, with a feathered perimeter and soft contact.
	var throw := Vector2(-0.70710678, -0.70710678) * side * 0.38
	var center := p + throw * 0.45
	var radii := Vector2(side * 0.62, side * 0.48) if tree else Vector2(side * 0.69, side * 0.69)
	var count := 8 if streamed and tree else 16
	var rings := 2 if streamed and tree else 4
	for ring in rings:
		var r0 := float(ring) / rings
		var r1 := float(ring + 1) / rings
		for j in count:
			var a := TAU * j / count
			var b := TAU * (j + 1) / count
			var pa := center + Vector2(cos(a), sin(a)) * radii * r0
			var pb := center + Vector2(cos(b), sin(b)) * radii * r0
			var pc := center + Vector2(cos(b), sin(b)) * radii * r1
			var pd := center + Vector2(cos(a), sin(a)) * radii * r1
			var start := shadow_batch.colors.size()
			shadow_batch.quad(point(pa, 1.0), point(pb, 1.0), point(pc, 1.0), point(pd, 1.0), Color(0.04, 0.06, 0.14, 0.12))
			# Vertex alpha makes the edge soft without translucent overlapping disks.
			for k in range(start, shadow_batch.vertices.size()):
				var v: Vector3 = shadow_batch.vertices[k]
				var dist := ((Vector2(v.x, v.z) + origin - center) / radii).length()
				shadow_batch.colors[k].a = 0.17 * (1.0 - smoothstep(0.35, 1.0, dist))

func shadows_node() -> MeshInstance3D:
	var material := Geo.material(true)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return Geo.instance(shadow_batch.mesh(), material)

func ribbon(batch: RefCounted, path: PackedVector2Array, width: float, color: Color, lift: float, road: bool = false) -> void:
	for i in range(path.size() - 1):
		var a := path[i]
		var b := path[i + 1]
		var normal := (b - a).orthogonal().normalized() * width * 0.5
		var steps := maxi(1, ceili(a.distance_to(b) / 9.0))
		for j in steps:
			var p := a.lerp(b, float(j) / steps)
			var q := a.lerp(b, float(j + 1) / steps)
			if road:
				batch.quad(at_height(p - normal, road_height(p) + lift), at_height(q - normal, road_height(q) + lift),
					at_height(q + normal, road_height(q) + lift), at_height(p + normal, road_height(p) + lift), color)
			else:
				batch.quad(point(p - normal, lift), point(q - normal, lift), point(q + normal, lift), point(p + normal, lift), color)

## Keep streets and traffic over a river valley rather than diving into its water.
func road_height(p: Vector2) -> float:
	if _road_height_cache.has(p): return _road_height_cache[p]
	var h := surface_height(p)
	for segment in _river_buckets.get(Vector2i((p / 128.0).floor()), []):
		var closest := Geometry2D.get_closest_point_to_segment(p, segment.a, segment.b)
		if closest.distance_squared_to(p) < float(segment.half) * float(segment.half):
			var n: Vector2 = (segment.b - segment.a).orthogonal().normalized() * (float(segment.half) + 20.0)
			h = maxf(h, maxf(ground_height(closest - n), ground_height(closest + n)) + 2.0)
	_road_height_cache[p] = h
	return h

func _index_rivers() -> void:
	_river_buckets.clear()
	_road_height_cache.clear()
	for tid in rivers:
		for rec in rivers[tid]:
			var half := (float(rec.start_width) + float(rec.end_width)) * 0.25 + 17.0
			for i in range(rec.points.size() - 1):
				var segment := {"a": rec.points[i], "b": rec.points[i + 1], "half": half}
				var bounds := Rect2(segment.a, Vector2.ZERO).expand(segment.b).grow(half)
				var low := Vector2i((bounds.position / 128.0).floor())
				var high := Vector2i((bounds.end / 128.0).floor())
				for y in range(low.y, high.y + 1):
					for x in range(low.x, high.x + 1): (_river_buckets.get_or_add(Vector2i(x, y), []) as Array).append(segment)

func append_road(parent: Node3D, tid: String) -> void:
	var mesh: ArrayMesh
	if streamed and continent.get("roads", {}).has(tid): mesh = continent.roads[tid]
	elif streamed and tile_chunks.has(tid) and base_chunk(tid).get("roads_mesh") != null: mesh = base_chunk(tid).roads_mesh
	else:
		var key := "road-" + BakeCache.digest([_road_key, tid, road_surface.cell_size])
		var cached := bake_cache.read(key) if not streamed and _map_key != "" else {}
		if not cached.is_empty():
			mesh = cached.mesh
		else:
			# Ordinary LOD handovers already have road geometry. Reserve the
			# spatial lookup and height sampler for actual generation/cache repair.
			if not road_surface._height.is_valid(): road_surface.configure(roads, road_height, origin)
			mesh = road_surface.mesh_for(tid)
		if streamed and continent.has("roads"): continent.roads[tid] = mesh
		elif cached.is_empty() and _map_key != "": bake_cache.write(key, {"mesh": mesh})
	var surface := Geo.instance(mesh, road_mat)
	surface.name = "JoinedRoads_" + tid.validate_node_name()
	parent.add_child(surface)
	road_nodes.append(surface)
	if _repair_chunks.has(tid):
		_chunk_data[tid].roads_mesh = mesh
		persist_base_chunk(tid)

func infrastructure(model: Dictionary, show: Dictionary, build_roads: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = "Infrastructure"
	var streets := Geo.Batch.new()
	var details := Geo.Batch.new()
	roads = model.get("roads", [])
	lines = model.get("lines", [])
	_index_rivers()
	road_mat = mat.duplicate()
	if bool(show["roads"]):
		road_surface.cell_size = 6.0 if streamed else RoadSurface.CELL
		road_surface.configure(roads, road_height, origin)
		if build_roads:
			for tid in tiles: append_road(root, str(tid))
			road_surface.finish_build()
			_road_height_cache.clear()
		for rec in roads:
			var a: Vector2 = rec.a
			var b: Vector2 = rec.b
			var across := (b - a).orthogonal().normalized()
			var half := float(Legacy._road_widths(int(rec.level))[0])
			if int(rec.level) > 1 and bool(rec.get("paved", true)):
				for k in range(1, int(a.distance_to(b) / 55.0)):
					var p := a.move_toward(b, k * 55.0) + across * (half + 1.5)
					var foot := at_height(p, road_height(p) + 1.0)
					streets.tube(foot, foot + Vector3.UP * 14, 0.55, Color("50565e"), 5)
					streets.box(foot + Vector3(0, 14, 0), Vector3(2.5, 1.3, 2.5), Color("efd68e"))
					if int(tiles.get(str(rec.get("tile", "")), {}).get("polluters", 0)) > 0:
						glows.append({"point": foot + Vector3.UP * 14, "size": Vector2(15, 15)})
			if a.distance_to(b) > 80.0:
				cars.append({"a": a, "b": b, "phase": fmod(absf(float(hash(str(a)))), 100.0) / 100.0})
	add_detail(root, streets.mesh(), 1 if streamed else 0)
	var tubes := Geo.Batch.new()
	for rec in model.get("lines", []):
		var mode := str(rec.get("mode", ""))
		if not bool(show.get(mode, true)): continue
		var path: Array = rec.get("pts", [])
		for i in range(path.size() - 1):
			var a: Vector2 = path[i].p
			var b: Vector2 = path[i + 1].p
			if mode == "rails":
				var line := PackedVector2Array([a, b])
				ribbon(tubes, line, 10.0, Color("766956"), 2.0, true)
				var across := (b - a).orthogonal().normalized() * 2.4
				for k in int(a.distance_to(b) / 6.0):
					var p := a.move_toward(b, k * 6.0)
					ribbon(details, PackedVector2Array([p - across * 1.7, p + across * 1.7]), 1.3, Color("524939"), 2.6, true)
				for sign_v in [-1.0, 1.0]:
					ribbon(tubes, PackedVector2Array([a + across * sign_v, b + across * sign_v]), 0.9, Color("d7d4c0"), 2.8, true)
			else:
				var cable := mode == "cables"
				var count := maxi(2, ceili(a.distance_to(b) / 12.0))
				var previous := Vector3.ZERO
				for j in range(count + 1):
					var t := float(j) / count
					var p := a.lerp(b, t)
					var h := lerpf(ground_height(a), ground_height(b), t) + 62.0 - sin(t * PI) * 12.0 if cable else road_height(p) + 5.5
					var current := at_height(p, h)
					if j > 0: tubes.tube(previous, current, 0.8 if cable else 2.4, Color("d6b560") if cable else (Color("a0a7aa") if mode == "reinf_pipes" else Color("b78552")))
					previous = current
	root.add_child(Geo.instance(tubes.mesh(), mat))
	add_detail(root, details.mesh(), 1)
	return root

func standing_frame(s: Dictionary) -> Dictionary:
	if standing_frames.has(str(s.iid)): return standing_frames[str(s.iid)]
	var kind := str(s["kind"])
	var family := str(s.get("internal_name", ""))
	if kind == "warehouse" or kind == "suppliers": family = "warehouse"
	elif kind == "port": family = "port"
	elif kind == "pylon": family = "pylon"
	elif kind == "site": family = "construction_site"
	elif kind == "house": family = "towers" if bool(s.get("tall", false)) else "house"
	var level := int(s.get("level", 1))
	# Decorative metadata uses level 3 for footprint sizing, while its chosen sprite
	# carries the actual house/tower variety. Preserve that variety in the 3D mesh.
	if kind == "house" and s.get("sprite") is Texture2D:
		var filename: String = s.sprite.resource_path.get_file().get_basename()
		if filename.begins_with(family + "_lvl"):
			level = filename.trim_prefix(family + "_lvl").to_int()
	var key := Assets.key_for(family, level)
	var side := float(s.get("side", 80.0))
	var p: Vector2 = s.pos
	var floor_h := surface_height(p)
	var low_h := floor_h
	var half := side * 0.42
	for off in [Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)]:
		var h := surface_height(p + off)
		floor_h = maxf(floor_h, h)
		low_h = minf(low_h, h)
	var pit: Dictionary = pits.get(str(s.iid), {})
	if not pit.is_empty(): floor_h = float(pit.height)
	var position := at_height(p, floor_h - float(pit.sink) if not pit.is_empty() else floor_h + 1.0)
	var dimension := Assets.dimensions(key) * side

	return {"key": key, "position": position, "dimension": dimension,
		"plinth_depth": floor_h - low_h + 1.0 if pit.is_empty() and floor_h - low_h > 0.75 else 0.0}

func _append_foundation(batch: Geo.Batch, s: Dictionary, frame: Dictionary, offset := Vector3.ZERO) -> void:
	if float(frame.plinth_depth) <= 0.0: return
	# Fit the real footprint (a terrace is often long and narrow), then skirt it
	# down to the terrain instead of suspending a square slab over a hillside.
	var center := FarSprites.center(str(frame.key)) * float(s.side)
	var half: Vector3 = frame.dimension * 0.5 + Vector3(1.0, 0.0, 1.0)
	var corners: Array[Vector3] = [Vector3(center.x - half.x, 0, center.z - half.z),
		Vector3(center.x + half.x, 0, center.z - half.z), Vector3(center.x + half.x, 0, center.z + half.z),
		Vector3(center.x - half.x, 0, center.z + half.z)]
	var colour := Color("868579")
	batch.quad(corners[3] + offset, corners[2] + offset, corners[1] + offset, corners[0] + offset, colour)
	for i in 4:
		var a := corners[i]
		var b := corners[(i + 1) % 4]
		var steps := maxi(1, ceili(a.distance_to(b) / 12.0))
		for step in steps:
			var p := a.lerp(b, float(step) / steps)
			var q := a.lerp(b, float(step + 1) / steps)
			var low_p := p + Vector3.UP * minf(0.0, surface_height(s.pos + Vector2(p.x, p.z)) - frame.position.y - 1.0)
			var low_q := q + Vector3.UP * minf(0.0, surface_height(s.pos + Vector2(q.x, q.z)) - frame.position.y - 1.0)
			batch.quad(p + offset, q + offset, low_q + offset, low_p + offset, colour)

func _track_visual(node: GeometryInstance3D, tid: String) -> void:
	building_visuals.append(node)
	node.lod_bias = [0.8, 1.2, 2.0][clampi(active_lod, 0, 2)]
	if local_tiles.has(tid): local_tiles[tid].records.building_visuals.append(node)

func _ensure_standing_near(pair: Dictionary) -> void:
	if not pair.near.is_empty(): return
	var mesh := Assets.mesh_for(pair.key)
	var visual := MeshInstance3D.new()
	if mesh != null:
		visual.mesh = mesh
		visual.scale = Vector3.ONE * float(pair.standing.side)
		if pair.lit: visual.material_override = Assets.lit_material(str(pair.key).begins_with("towers_"))
	else:
		var box := BoxMesh.new()
		box.size = pair.dimension
		visual.mesh = box
		visual.position.y = box.size.y * 0.5
		var fallback := StandardMaterial3D.new()
		fallback.albedo_color = Color("cbc6a8")
		visual.material_override = fallback
	pair.root.add_child(visual)
	pair.near.append(visual)
	_track_visual(visual, str(pair.tile))
	var contour := Assets.contour_for(pair.key)
	if contour != null:
		var outline := MeshInstance3D.new()
		outline.name = "OuterContour"
		outline.mesh = contour
		outline.scale = visual.scale
		pair.root.add_child(outline)
		pair.near.append(outline)
		_track_visual(outline, str(pair.tile))

func _ensure_standing_pick(pair: Dictionary) -> void:
	if cursor_picking and (not collision_detail_visible() or not collision_tiles.has(str(pair.tile))):
		if pair.get("body") != null:
			var collider: CollisionShape3D = pair.body.get_child(0)
			if collider.shape != null: collider.shape = null
		return
	if pair.get("body") != null:
		if cursor_picking:
			var collider: CollisionShape3D = pair.body.get_child(0)
			if collider.shape == null: collider.shape = pair.pick_shape
		return
	var s: Dictionary = pair.standing
	if str(s.kind) not in ["building", "site", "warehouse", "suppliers"]: return
	var pit: Dictionary = pits.get(str(s.iid), {})
	var body := StaticBody3D.new()
	body.collision_layer = 2 if pit.is_empty() else 3
	body.collision_mask = 0
	body.set_meta("standing", s)
	body.set_meta("tile_id", str(s.tile))
	var dimension: Vector3 = pair.dimension
	body.set_meta("pick_bounds", AABB(Vector3(-dimension.x * 0.5, 0, -dimension.z * 0.5), dimension))
	var collider := CollisionShape3D.new()
	if str(pair.key) != "" and pit.is_empty():
		collider.shape = Assets.picking_shape(pair.key)
		collider.scale = Vector3.ONE * float(s.side)
	else:
		var shape := BoxShape3D.new()
		shape.size = dimension.max(Vector3.ONE * 6.0)
		if not pit.is_empty(): shape.size.y = maxf(shape.size.y, float(pit.sink) + 3.0)
		collider.shape = shape
		collider.position.y = shape.size.y * 0.5
	body.add_child(collider)
	pair.root.add_child(body)
	pair.body = body
	pair.pick_shape = collider.shape

func standing_node(s: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = str(s["iid"]).validate_node_name()
	var frame := standing_frame(s)
	var kind := str(s.kind)
	var key := str(frame.key)
	var family := key.get_slice("_lvl", 0)
	var side := float(s.side)
	var p: Vector2 = s.pos
	var pit: Dictionary = pits.get(str(s.iid), {})
	root.position = frame.position
	var dimension: Vector3 = frame.dimension
	if key == "": dimension = Vector3(side * 0.8, side * 0.55, side * 0.65)
	var lit := int(tiles.get(str(s.tile), {}).get("polluters", 0)) > 0 and kind != "pylon" and family not in ["mine", "mine_flush"]
	var pair := {"key": key, "far": null, "near": [], "medium": null, "root": root, "standing": s,
		"dimension": dimension, "tile": str(s.tile), "lit": lit,
		"medium_allowed": not lit or FarSprites.entry(key, 1).has("lit_texture"), "decor": streamed and kind == "house"}
	if not lazy_assets:
		_ensure_standing_near(pair)
		_ensure_standing_pick(pair)
	if lit:
		glows.append({"point": root.position + Vector3(0, dimension.y * 0.3, side * 0.45), "size": Vector2(side * 1.3, side * 0.7)})
	if streamed and kind == "house": decor_nodes.append(root)
	if kind != "pylon" and pit.is_empty() and not (kind == "house" and scenery_ready): shadow(p, side)
	if float(frame.plinth_depth) > 0.0:
		var plinth := Geo.Batch.new()
		_append_foundation(plinth, s, frame)
		root.add_child(Geo.instance(plinth.mesh(), mat))
	var card := FarSprites.instance(key, grade_range)
	if card != null:
		card.scale = Vector3.ONE * side
		card.position = FarSprites.center(key) * side
		card.visible = false
		root.add_child(card)
		pair.far = card
	sprite_pairs.append(pair)
	pickables.append({"iid": s.iid, "kind": kind, "tile": s.tile, "point": root.position + Vector3.UP * dimension.y * 0.5, "top": root.position + Vector3.UP * (dimension.y + 12.0), "size": dimension})
	if bool(s.get("polluting", false)):
		smoke.append({"point": root.position + Vector3.UP * dimension.y, "radius": maxf(4.0, side * 0.08)})
	return root

func trees_node(tid: String, standing: Array) -> Node3D:
	var root := Node3D.new()
	root.name = "LandscapeDetail"
	if str(tiles[tid].type) in ["sea", "deep_sea"]: return root
	# Tree shadows are batched with their tile so the renderer can cull them.
	var saved_shadows := shadow_batch
	if streamed: shadow_batch = Geo.Batch.new()
	var placements := placements_for(tid, standing)
	if lazy_assets:
		var prepared: Dictionary = _chunk_data.get(tid, {}).get("local_detail", {}) if streamed else {}
		var all_cards: Dictionary = prepared.get("tree_cards", {})
		if not prepared.has("tree_cards"): all_cards = LocalDetail.tree_cards(self, tid, standing)
		for kind in ["small", "fir", "large"]:
			var key := Assets.key_for("tree", {"small": 1, "fir": 2, "large": 3}[kind])
			var cards: Array = all_cards.get(kind, [])
			if not scenery_ready:
				for tree in placements:
					if tree.kind == kind: shadow(tree.pos, Assets.dimensions(key).x * float(tree.height) / Assets.projected_height(key), true)
			if cards.is_empty(): continue
			if streamed and not local_streaming:
				if not tree_sprite_transforms.has(key): tree_sprite_transforms[key] = []
				tree_sprite_transforms[key].append_array(cards)
			var medium := FarSprites.grove(key, cards, grade_range, 1)
			if medium != null: root.add_child(medium)
			var far := FarSprites.grove(key, cards, grade_range) if not streamed else null
			if far != null: root.add_child(far)
			sprite_pairs.append({"tree": true, "key": key, "kind": kind, "tile": tid, "root": root, "cards": cards,
				"near": [], "medium": medium, "far": far})
		sprite_pairs.append({"clutter": true, "tile": tid, "root": root, "standing": standing, "near": [], "far": null, "medium": null})
		if streamed:
			if not scenery_ready: root.add_child(shadows_node())
			shadow_batch = saved_shadows
		tree_nodes.append(root)
		return root
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
		for mesh in [Assets.mesh_for(key), Assets.contour_for(key)]:
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
	add_detail(root, _ground_clutter(tid, standing), 2)
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

func _ensure_tree_near(pair: Dictionary) -> void:
	if not pair.near.is_empty(): return
	if pair.get("clutter", false):
		var node := Geo.instance(_ground_clutter(pair.tile, pair.standing), mat)
		pair.root.add_child(node)
		pair.near.append(node)
		return
	var key := str(pair.key)
	var species_scale := float(Legacy._TREE_HEIGHT[pair.kind]) / Assets.projected_height(key)
	for mesh in [Assets.mesh_for(key), Assets.contour_for(key)]:
		if mesh == null: continue
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh
		multi.instance_count = pair.cards.size()
		for i in pair.cards.size():
			var card: Transform3D = pair.cards[i]
			var scale := card.basis.x.length()
			multi.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale / species_scale),
				(card.origin - FarSprites.center(key) * scale) / species_scale))
		var node := MultiMeshInstance3D.new()
		node.name = "Trees_" + str(pair.kind)
		node.multimesh = multi
		node.scale = Vector3.ONE * species_scale
		if mesh == Assets.mesh_for(key): node.material_override = Assets.tree_material(pair.kind == "fir")
		pair.root.add_child(node)
		pair.near.append(node)
		_track_visual(node, str(pair.tile))

func _ground_clutter(tid: String, standing: Array) -> Mesh:
	var detail: Dictionary = _chunk_data.get(tid, {}).get("local_detail", {}) if streamed else {}
	if detail.get("clutter_mesh") is Mesh: return detail.clutter_mesh
	return LocalDetail.clutter(self, tid, standing)

func _plantable(p: Vector2, tid: String, rel: Dictionary, standing: Array, road_margin: float, nearby_roads: Array) -> bool:
	if not Geometry2D.is_point_in_polygon(p, Model.hex_points(tiles[tid].center)) or Ground.is_water(rel, p): return false
	for s in standing:
		if (s.pos as Vector2).distance_to(p) < float(s.get("side", 80)) * 0.74 + 12.0: return false
	for road in nearby_roads:
		if Geometry2D.get_closest_point_to_segment(p, road.a, road.b).distance_to(p) < road_margin: return false
	for rec in rivers.get(tid, []):
		for j in range(rec.points.size() - 1):
			if Geometry2D.get_closest_point_to_segment(p, rec.points[j], rec.points[j + 1]).distance_to(p) < (float(rec.start_width) + float(rec.end_width)) * 0.25 + 6.0: return false
	return true

func _crown(batch: RefCounted, center: Vector3, radius: Vector3, color: Color, sides: int) -> void:
	# Rounded, faceted broadleaf crowns rather than the first pass's pointed diamonds.
	var levels := [-0.82, -0.35, 0.30, 0.78]
	for ring in range(levels.size() - 1):
		var y0: float = levels[ring]
		var y1: float = levels[ring + 1]
		var r0 := sqrt(1.0 - y0 * y0)
		var r1 := sqrt(1.0 - y1 * y1)
		for j in sides:
			var a := TAU * j / sides
			var b := TAU * (j + 1) / sides
			batch.quad(center + Vector3(cos(a) * r0, y0, sin(a) * r0) * radius,
				center + Vector3(cos(b) * r0, y0, sin(b) * r0) * radius,
				center + Vector3(cos(b) * r1, y1, sin(b) * r1) * radius,
				center + Vector3(cos(a) * r1, y1, sin(a) * r1) * radius, color)
	for j in sides:
		var a := TAU * j / sides
		var b := TAU * (j + 1) / sides
		batch.triangle(center + Vector3(cos(a) * 0.626, 0.78, sin(a) * 0.626) * radius,
			center + Vector3.UP * radius.y, center + Vector3(cos(b) * 0.626, 0.78, sin(b) * 0.626) * radius, color.lightened(0.04))

func prepare_flows(model: Dictionary) -> void:
	flows.clear()
	for flow in model.get("flows", []):
		var points := PackedVector3Array()
		var distances := PackedFloat32Array([0.0])
		var source: Array = flow.get("pts", [])
		var cable := str(flow.get("mode", "")) == "cables"
		for i in range(source.size() - 1):
			var a: Vector2 = source[i].p
			var b: Vector2 = source[i + 1].p
			var count := maxi(1, ceili(a.distance_to(b) / 18.0))
			for j in range(count + (1 if i == source.size() - 2 else 0)):
				var t := float(j) / count
				var p := a.lerp(b, t)
				var h := lerpf(ground_height(a), ground_height(b), t) + 70.0 - sin(t * PI) * 12.0 if cable else road_height(p) + 16.0
				var at := at_height(p, h)
				if not points.is_empty(): distances.append(distances[-1] + points[-1].distance_to(at))
				points.append(at)
		if points.size() >= 2:
			flows.append({"points": points, "distances": distances, "length": distances[-1], "icon": flow.get("icon"), "good": flow.get("good", "")})
