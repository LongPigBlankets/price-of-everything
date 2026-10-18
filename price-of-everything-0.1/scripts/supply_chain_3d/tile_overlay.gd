extends RefCounted
## The continent is the shipped base world plus the tiles that differ from it.
## Only tiles whose buildings, warehouses, suppliers or pylons changed are laid
## out again; every other tile keeps the base layout and its packaged bakes.
## See docs/supply-chain-3d-tile-overlay.md.
const Model := preload("res://scripts/empire_board_model.gd")
const Builder := preload("res://scripts/supply_chain_3d/world_builder.gd")
const Legacy := preload("res://scripts/empire_board.gd")
const LayoutQueries := preload("res://scripts/supply_chain_3d/layout_queries.gd")
const AuthoredRegion := preload("res://scripts/supply_chain_3d/authored_region.gd")

## Per tile, this session's layout of its current contents. A tile that changed
## earlier is not laid out again when a different tile changes.
static var _solved_tiles := {}

## Per tile: what the layout is built from, never what it produces. Decor houses,
## roads and running ids are outputs and are left out.
static func identity(model: Dictionary, only: Dictionary = {}) -> Dictionary:
	var parts := {}
	for s in model.get("standing", []):
		var tid := str(s.tile)
		if str(s.kind) == "house" or (not only.is_empty() and not only.has(tid)): continue
		# Later passes turn these into harbours and rail depots, which stay shipped.
		if str(s.kind) == "port" or str(s.get("internal_name", "")) == "rail_hub": continue
		(parts.get_or_add(tid, []) as Array).append("%s|%s|%s|%d|%s" % [s.iid, s.kind, s.get("internal_name", ""), int(s.get("level", 1)), bool(s.get("npc", false))])
	for tid in model.get("tiles", {}):
		if not only.is_empty() and not only.has(tid): continue
		var t: Dictionary = model.tiles[tid]
		if bool(t.get("store", false)) or int(t.get("polluters", 0)) > 0 or t.has("pylon"):
			(parts.get_or_add(str(tid), []) as Array).append("tile|%s|%d|%s" % [bool(t.get("store", false)), int(t.get("polluters", 0)), t.has("pylon")])
	var result := {}
	for tid in parts:
		var items: Array = parts[tid]
		items.sort()
		result[tid] = "\n".join(PackedStringArray(items))
	return result

static func divergent(base: Dictionary, live: Dictionary, scope: Dictionary) -> Array:
	var changed: Array = []
	for tid in scope:
		if str(base.get(tid, "")) != str(live.get(tid, "")): changed.append(str(tid))
	changed.sort()
	return changed

## Base layout everywhere except the changed tiles, which take the sub-model's.
static func merge(base: Dictionary, sub: Dictionary, changed: Array) -> Dictionary:
	var inside := {}
	for tid in changed: inside[tid] = true
	var model := base.duplicate()
	var standing: Array = base.get("standing", []).filter(func(s: Dictionary) -> bool: return not inside.has(str(s.tile)))
	for s in sub.get("standing", []):
		if inside.has(str(s.tile)): standing.append(s)
	model.standing = standing
	var tiles: Dictionary = base.get("tiles", {}).duplicate()
	for tid in changed:
		if not sub.get("tiles", {}).has(tid) or not tiles.has(tid): continue
		var record: Dictionary = tiles[tid].duplicate()
		for field in ["store", "polluters", "hub", "hub_node", "manifold"]:
			if sub.tiles[tid].has(field): record[field] = sub.tiles[tid][field]
		for field in ["pylon", "power_icon"]:
			if sub.tiles[tid].has(field): record[field] = sub.tiles[tid][field]
			else: record.erase(field)
		tiles[tid] = record
	model.tiles = tiles
	var blocks: Dictionary = base.get("district_blocks", {}).duplicate()
	if blocks.has("plots"):
		var plots: Array = blocks.plots.filter(func(p: Dictionary) -> bool: return not inside.has(str(p.get("tile", ""))))
		for p in sub.get("district_blocks", {}).get("plots", []):
			if inside.has(str(p.get("tile", ""))): plots.append(p)
		blocks.plots = plots
		model.district_blocks = blocks
	var dense: Array = base.get("dense_tiles", []).filter(func(t) -> bool: return not inside.has(str(t)))
	for t in sub.get("dense_tiles", []):
		if inside.has(str(t)): dense.append(t)
	model.dense_tiles = dense
	# Goods on the move follow the live company, on the base roads.
	for field in ["flows", "made", "lanes"]:
		if sub.has(field): model[field] = sub[field]
	return model

## Lays out only the tiles that differ from the shipped snapshot model. Returns
## {"model": merged, "changed": [...], "profile": {...}} or {} when unusable.
static func prepare(board: Control, base: Dictionary, ground: RefCounted, cache: RefCounted, only: Array = [], prepared: RefCounted = null, alive: Callable = Callable()) -> Dictionary:
	var terrain: Node = board._last_terrain
	var graph: Dictionary = board._last_graph
	if not is_instance_valid(terrain) or graph.is_empty(): return {}
	var started := Time.get_ticks_usec()
	var profile := {}
	var rivers: Dictionary = board._rivers_by_tile(terrain)
	var river_lines := {}
	for tid in rivers:
		river_lines[tid] = []
		for rec in rivers[tid]: river_lines[tid].append(rec.points)
	var water := Legacy._water_test(terrain)
	var town: bool = Legacy.plate_town and Legacy.show.decor
	var builder := Builder.new()
	builder.ground = ground
	# A caller that already prepared the layout memo passes it in and finishes it.
	var queries: RefCounted = prepared
	if queries == null:
		queries = LayoutQueries.new()
		var geography: Array = []
		for coord in terrain.get("tiles"):
			var tid := "tile_%d_%d" % [coord.x + 1, coord.y + 1]
			geography.append([tid, Model.tile_center(terrain, tid), Catalog.tile_type(tid)])
		queries.prepare(cache, [geography, ground.get("bands"), ground.get("lakes"), ground.get("rivers"), HillBaked.sea()], water)
	# Candidates: anywhere the base or the live game has something standing,
	# or just the given tiles (the company view).
	var scope := {}
	for tid in only: scope[str(tid)] = true
	for s in ([] if not only.is_empty() else base.get("standing", [])):
		if str(s.kind) != "house": scope[str(s.tile)] = true
	if only.is_empty():
		for tid in base.get("tiles", {}):
			var t: Dictionary = base.tiles[tid]
			if bool(t.get("store", false)) or t.has("pylon"): scope[tid] = true
		for iid in BuildingState.buildings:
			var tid := str(BuildingState.buildings[iid].get("tile_id", ""))
			if base.get("tiles", {}).has(tid): scope[tid] = true
		for n in graph.get("nodes", []):
			var tid := str(n.get("tile_id", ""))
			if base.get("tiles", {}).has(tid): scope[tid] = true
	var positions: Dictionary = board._true_positions(graph, terrain)
	var probe := Model.build(terrain, graph, positions, river_lines, town, water, Legacy._shore_test(terrain), scope.keys())
	# The company view also draws the tiles its routes and pylons cross.
	if not only.is_empty():
		for tid in probe.get("tiles", {}):
			if base.get("tiles", {}).has(tid): scope[tid] = true
	var footprints := board.get_tree().get_first_node_in_group("building_footprints")
	AuthoredRegion.apply(probe, terrain, footprints, queries.data, builder.surface_height)
	var base_identity := identity(base, scope)
	var live_identity := identity(probe, scope)
	var changed := divergent(base_identity, live_identity, scope)
	if "--trace-overlay" in preload("res://scripts/demo_build.gd").user_args():
		for tid in changed: print("[TILE OVERLAY TRACE] ", tid, "\n  base: ", str(base_identity.get(tid, "")).replace("\n", " ; "), "\n  live: ", str(live_identity.get(tid, "")).replace("\n", " ; "))
	profile.candidates = scope.size()
	profile.changed = changed.size()
	profile.detect_ms = (Time.get_ticks_usec() - started) / 1000.0
	# A frame between steps: the game keeps drawing while tiles are laid out.
	await board.get_tree().process_frame
	if not is_instance_valid(board) or (alive.is_valid() and not alive.call()):
		if prepared == null: queries.finish(cache)
		return {}
	if changed.is_empty():
		var same := base.duplicate()
		for field in ["flows", "made", "lanes"]:
			if probe.has(field): same[field] = probe[field]
		if prepared == null: queries.finish(cache)
		return {"model": same, "changed": changed, "profile": profile, "probe": probe, "tiles": scope.keys()}
	# Each changed tile is laid out alone: the cost follows that tile's contents,
	# and the layout memo then remembers it per tile, so an unchanged diverged
	# tile is a memo hit when another tile changes later.
	var solve_started := Time.get_ticks_usec()
	var solved := {"standing": [], "tiles": {}, "district_blocks": {"plots": []}, "dense_tiles": []}
	var tile_ms := {}
	var reused: Array = []
	for tid in changed:
		var memo_key := "%s|%s" % [town, live_identity.get(tid, "")]
		var tile: Dictionary = _solved_tiles.get(tid, {}).get(memo_key, {})
		if tile.is_empty():
			var tile_started := Time.get_ticks_usec()
			var sub := Model.build(terrain, graph, positions, river_lines, town, water, Legacy._shore_test(terrain), [tid])
			_restrict(sub, tid)
			var drawn: Array = base.get("roads", []).filter(func(r: Dictionary) -> bool: return str(r.get("tile", "")) == tid)
			board._solve_layout(sub, terrain, rivers, queries, builder, water, {}, drawn)
			tile = {"standing": sub.get("standing", []).filter(func(s: Dictionary) -> bool: return str(s.tile) == tid),
				"tile": sub.get("tiles", {}).get(tid, {}), "plots": sub.get("district_blocks", {}).get("plots", []), "dense": sub.get("dense_tiles", [])}
			_solved_tiles[tid] = {memo_key: tile}
			tile_ms[tid] = snappedf((Time.get_ticks_usec() - tile_started) / 1000.0, 0.1)
		else:
			reused.append(tid)
		# Copies: the builder annotates the items it is given.
		solved.standing.append_array(tile.standing.map(func(item: Dictionary) -> Dictionary: return item.duplicate(true)))
		if not tile.tile.is_empty(): solved.tiles[tid] = tile.tile.duplicate(true)
		solved.district_blocks.plots.append_array(tile.plots.map(func(item: Dictionary) -> Dictionary: return item.duplicate(true)))
		solved.dense_tiles.append_array(tile.dense)
		if not tile_ms.has(tid): continue
		await board.get_tree().process_frame
		# A cancelled owner stops here, with the shared memo tables restored.
		if not is_instance_valid(board) or (alive.is_valid() and not alive.call()):
			if prepared == null: queries.finish(cache)
			return {}
	for field in ["flows", "made", "lanes"]:
		if probe.has(field): solved[field] = probe[field]
	if prepared == null: queries.finish(cache)
	profile.solve_ms = (Time.get_ticks_usec() - solve_started) / 1000.0
	profile.tile_ms = tile_ms
	profile.reused = reused
	profile.total_ms = (Time.get_ticks_usec() - started) / 1000.0
	print("[TILE OVERLAY] ", JSON.stringify({"changed": changed, "profile": profile}))
	return {"model": merge(base, solved, changed), "changed": changed, "profile": profile, "probe": probe, "tiles": scope.keys()}

## The company view: the merged world cut down to the company's tiles, with the
## live company's own lines and goods. Items are copied, never shared with the
## cached shipped world, because the builder annotates them.
static func restrict(model: Dictionary, probe: Dictionary, keep: Array, ground: RefCounted, shipped_index: Dictionary = {}) -> Dictionary:
	var inside := {}
	for tid in keep:
		if model.get("tiles", {}).has(tid): inside[tid] = true
	var within := func(p: Vector2) -> bool: return inside.has(str(ground.tile_at(p)))
	var result := model.duplicate()
	var tiles := {}
	for tid in inside: tiles[tid] = model.tiles[tid].duplicate(true)
	result.tiles = tiles
	result.standing = model.get("standing", []).filter(func(s: Dictionary) -> bool: return inside.has(str(s.tile))).map(func(s: Dictionary) -> Dictionary: return s.duplicate(true))
	if shipped_index.is_empty():
		result.roads = model.get("roads", []).filter(func(r: Dictionary) -> bool: return inside.has(str(r.get("tile", ""))))
		result.trial_rail_segments = model.get("trial_rail_segments", []).filter(func(r: Dictionary) -> bool: return within.call(r.a) or within.call(r.b))
	else:
		var picked: Array = []
		var rails := {}
		for tid in inside:
			picked.append_array(shipped_index.roads.get(tid, []))
			for i in shipped_index.rails.get(tid, []): rails[i] = true
		result.roads = picked
		var segments: Array = model.get("trial_rail_segments", [])
		var indices: Array = rails.keys()
		indices.sort()
		result.trial_rail_segments = indices.map(func(i: int) -> Dictionary: return segments[i])
	for field in ["depots", "stations"]:
		result[field] = model.get(field, []).filter(func(d: Dictionary) -> bool: return inside.has(str(d.get("tile", ""))))
	result.dense_tiles = model.get("dense_tiles", []).filter(func(t) -> bool: return inside.has(str(t)))
	var blocks: Dictionary = model.get("district_blocks", {}).duplicate()
	blocks.plots = blocks.get("plots", []).filter(func(p: Dictionary) -> bool: return inside.has(str(p.get("tile", ""))))
	blocks.paths = blocks.get("paths", []).filter(func(p: Dictionary) -> bool: return not (p.get("points", []) as Array).is_empty() and within.call(p.points[0]))
	result.district_blocks = blocks
	var neighbourhood: Dictionary = model.get("neighbourhood", {}).duplicate()
	neighbourhood.brownfields = neighbourhood.get("brownfields", []).filter(func(b: Dictionary) -> bool: return inside.has(str(b.get("tile", ""))))
	neighbourhood.paths = neighbourhood.get("paths", []).filter(func(p: Dictionary) -> bool: return not (p.get("points", []) as Array).is_empty() and within.call(p.points[0]))
	neighbourhood.footpaths = neighbourhood.get("footpaths", []).filter(func(f: Array) -> bool: return within.call(((f[0] as Vector2) + (f[1] as Vector2)) * 0.5))
	result.neighbourhood = neighbourhood
	var region: Dictionary = model.get("authored_region", {}).duplicate()
	var sources := {}
	for road in result.roads: sources[str(road.get("source", ""))] = true
	var centres := {}
	for tid in inside: centres[tid] = tiles[tid].center
	region.tiles = centres
	region.paths = region.get("paths", []).filter(func(p: Dictionary) -> bool: return sources.has(str(p.get("id", ""))))
	result.authored_region = region
	for field in ["lines", "flows", "made", "lanes"]:
		if probe.has(field): result[field] = probe[field]
	return result

## Only the one tile: the company's other tiles are not this tile's business.
static func _restrict(model: Dictionary, tid: String) -> void:
	var tiles := {}
	if model.get("tiles", {}).has(tid): tiles[tid] = model.tiles[tid]
	model.tiles = tiles
	model.standing = model.get("standing", []).filter(func(s: Dictionary) -> bool: return str(s.tile) == tid)
	model.roads = model.get("roads", []).filter(func(r: Dictionary) -> bool: return str(r.get("tile", "")) == tid)
	model.flows = []

## The shipped world's roads and rail segments by tile, built once per session
## for the company view. Rail segments are listed under both end tiles, by index.
static func index(model: Dictionary, ground: RefCounted) -> Dictionary:
	var roads := {}
	for r in model.get("roads", []): (roads.get_or_add(str(r.get("tile", "")), []) as Array).append(r)
	var rails := {}
	var segments: Array = model.get("trial_rail_segments", [])
	for i in segments.size():
		for tid in {str(ground.tile_at(segments[i].a)): true, str(ground.tile_at(segments[i].b)): true}:
			(rails.get_or_add(tid, []) as Array).append(i)
	return {"roads": roads, "rails": rails}
