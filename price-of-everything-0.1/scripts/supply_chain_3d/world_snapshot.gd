extends RefCounted
## Optional prepared board data. Artwork remains in the existing independent bakes.
## A snapshot is usable only for the same live inputs and source fingerprints.
const Cache := preload("res://scripts/supply_chain_3d/bake_cache.gd")
const VERSION := 6
const KEY_FIELDS := ["_map_key", "_road_key", "_scenery_key", "_continent_key", "transport_key"]
const AUTHORED_FIELDS := ["region", "segments", "crossings", "unresolved", "tile_index", "buckets", "bridge_tiles"]

static func plain(value: Variant) -> Variant:
	if value is Resource: return ["resource", value.resource_path]
	if value is Object: return null
	if value is Dictionary:
		var result := {}
		for key in value: result[key] = plain(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(plain(item))
		return result
	return value

static func inputs(board: Control) -> Array:
	var footprints: Node = board.get_tree().get_first_node_in_group("building_footprints")
	var builder: RefCounted = board._builder
	# Copy live inputs on the main thread. The digest worker receives only values,
	# never scene nodes, shared dictionaries, or references to mutable game state.
	return plain([VERSION, Cache.source_fingerprints(), board._model,
		builder.ground.get("tiles"), BuildingState.buildings,
		footprints.get("_placements") if footprints != null else [],
		preload("res://scripts/authored_map.gd").settlements(),
		board._last_terrain.get("tiles"), board._last_show])

static func packed(board: Control, input_key: String) -> Dictionary:
	var keys := {}
	for field in KEY_FIELDS: keys[field] = board._builder.get(field)
	var foundations := {}
	var authored := {}
	for field in AUTHORED_FIELDS: authored[field] = board._builder.authored_profile.get(field)
	for standing in board._model.standing:
		if str(standing.kind) != "house" and board._builder.prepared_foundations.has(str(standing.iid)):
			foundations[str(standing.iid)] = board._builder.prepared_foundations[str(standing.iid)]
	return {"version": VERSION, "input_key": input_key, "keys": keys,
		"fingerprints": Cache.source_fingerprints(), "model": board._model,
		"rivers": board._builder.rivers, "foundations": foundations,
		"pits": board._builder.pits,
		"mine_rims": board._builder.prepared_mine_rims,
		"overview": {"bounds":board._builder.bounds,"labels":board._builder.labels,
			"visibility":board._builder.visibility_bake(), "tile_chunks":board._builder.tile_chunks},
		"authored_profile": authored,
		"pick_shape": _locator_shape(board._builder)}

static func _locator_shape(builder: RefCounted) -> ConcavePolygonShape3D:
	# Only locates the cursor's tile. Exact resident terrain/building colliders
	# still decide local hits. Reusing the full rendered continent here makes
	# Jolt build a huge acceleration structure on first scene attachment.
	var faces := PackedVector3Array()
	for tile in builder.tiles.values():
		var center: Vector2 = tile.center
		var hex: PackedVector2Array = builder.Model.hex_points(center)
		for i in 6: _locator_triangle(builder, center, hex[i], hex[(i+1)%6], 2, faces)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	return shape

static func _locator_triangle(builder: RefCounted, a: Vector2, b: Vector2, c: Vector2, depth: int, faces: PackedVector3Array) -> void:
	if depth>0:
		var ab := (a+b)*0.5; var bc := (b+c)*0.5; var ca := (c+a)*0.5
		_locator_triangle(builder,a,ab,ca,depth-1,faces)
		_locator_triangle(builder,ab,b,bc,depth-1,faces)
		_locator_triangle(builder,ca,bc,c,depth-1,faces)
		_locator_triangle(builder,ab,bc,ca,depth-1,faces)
	else:
		# Godot front faces use clockwise winding when viewed from above.
		for p in [a,b,c]: faces.append(builder.point(p))

static func matches(data: Dictionary, input_key: String, manifest: Dictionary) -> bool:
	if data.get("version", -1) != VERSION or data.get("input_key", "") != input_key: return false
	if not data.get("pick_shape") is ConcavePolygonShape3D or not data.get("foundations") is Dictionary: return false
	if not data.get("pits") is Dictionary: return false
	if not data.get("mine_rims") is Mesh: return false
	for field in ["bounds", "labels", "visibility", "tile_chunks"]:
		if not data.get("overview", {}).has(field): return false
	for field in AUTHORED_FIELDS:
		if not data.get("authored_profile", {}).has(field): return false
	if not Cache.fingerprints_match(data.get("fingerprints", {}), Cache.source_fingerprints()): return false
	var keys: Dictionary = data.get("keys", {})
	for field in KEY_FIELDS:
		if str(keys.get(field, "")).is_empty(): return false
	for pair in [["_map_key", "map_key"], ["_continent_key", "continent_key"], ["_scenery_key", "scenery_key"], ["transport_key", "transport_key"]]:
		if keys[pair[0]] != manifest.get(pair[1], ""): return false
	return data.get("model", {}).get("tiles", {}).size() == int(manifest.get("tile_count", -1))
