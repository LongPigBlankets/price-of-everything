extends RefCounted
## Read-only road adapter. The regular map remains the authority for roads/lots.
const Model := preload("res://scripts/empire_board_model.gd")
const Authored := preload("res://scripts/authored_map.gd")
const Curves := preload("res://scripts/authored_road_geometry.gd")
const Style := preload("res://scripts/authored_road_style.gd")
const Regions := preload("res://scripts/road_regions.gd")
const Sprites := preload("res://scripts/building_sprites.gd")
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const Index := preload("res://scripts/supply_chain_3d/road_index.gd")
const JOIN_DISTANCE := Index.JOIN_DISTANCE
const Cache := preload("res://scripts/supply_chain_3d/bake_cache.gd")

static func tile_ids() -> Array:
	return Regions.get_region("stoneshore").get("tiles", [])

static func apply(model: Dictionary, terrain: Node, footprints: Node, prepared: Dictionary = {}, ground: Callable = Callable(), scope: Array = []) -> void:
	var centers := {}
	var flags := {}
	for tile in terrain.get("tiles").values():
		var tid := str(tile.id)
		centers[tid] = Model.tile_center(terrain, tid) if terrain.has_method("map_to_local") else model.tiles.get(tid, {}).get("center", Vector2.ZERO)
		if "roads" in tile.get("infrastructure_present", []): flags[tid] = true
	var region := {}
	for tid in model.tiles:
		if scope.is_empty() or tid in scope: region[tid] = model.tiles[tid].center
	if region.is_empty(): return
	bind_flow_ends(model)
	var paths := source_paths(terrain, flags)
	var key := Cache.digest([Cache.source_key("roads"), Cache.source_key("terrain"), centers, paths])
	var compiled: Dictionary = prepared.get("authored_network", {})
	if compiled.get("key", "") != key:
		compiled = compile(paths, centers, ground)
		# Clip after endpoint joining, so a coastal gap cannot be snapped shut
		# and then interpreted as a sea bridge by the terrain profile builder.
		var coast := preload("res://scripts/supply_chain_3d/coastal_roads.gd").clip(compiled.paths,centers)
		compiled.paths=coast.paths;compiled.sea_clip=coast.removed
		compiled.roads=compile_segments(compiled.paths,centers)
		compiled.key = key
		prepared.authored_network = compiled
	var roads: Array = model.roads.filter(func(r: Dictionary) -> bool: return not region.has(str(r.tile)))
	var regional: Array = []
	var sources := {}
	for road in compiled.roads:
		if not region.has(str(road.tile)): continue
		regional.append(road.duplicate())
		sources[road.source] = true
	roads.append_array(regional)
	model.roads = roads
	var visible_paths: Array = compiled.paths.filter(func(p: Dictionary) -> bool: return sources.has(p.id))
	var npc_count := place_npcs(model, region, terrain, footprints)
	model.authored_region = {"tiles": region, "paths": visible_paths, "joined": compiled.joined, "npc_count": npc_count,
		"global_paths": compiled.paths.size(), "global_segments": compiled.roads.size(), "trimmed_stubs": compiled.get("trimmed_stubs", [])}

static func source_paths(terrain: Node, flags: Dictionary) -> Array:
	var paths: Array = []
	for settlement in Authored.settlements().values():
		for stroke in settlement.get("roads", []):
			if not Authored.road_visible(stroke, flags): continue
			var points := Curves.sample(stroke)
			if points.size() > 1:
				paths.append({"id": str(stroke.id), "points": points, "class": str(stroke.get("class", "mid")),
					"bridges": stroke.get("bridges", []).duplicate(true), "layer": int(stroke.get("layer", 0))})
	# Match RoadNetworkVisuals: built generated roads show only on road-built,
	# non-authored tiles. Sampling/visibility never changes the simulation graph.
	if terrain.has_method("local_to_map"):
		var allowed := {}
		for coord in terrain.get("tiles"):
			var tid := str(terrain.get("tiles")[coord].id)
			if flags.has(tid) and not Authored.covers(tid): allowed[coord] = true
		if not allowed.is_empty():
			for edge in RoadNetwork.instance().edges.values():
				if str(edge.state) != RoadNetwork.STATE_BUILT: continue
				var run := PackedVector2Array()
				var sequence := 0
				for p in edge.geometry:
					var coord: Vector2i = terrain.call("tile_coord_for_map_coord", terrain.call("local_to_map", p))
					if allowed.has(coord): run.append(p)
					else:
						if run.size() >= 2:
							paths.append(network_path(edge, run, sequence)); sequence += 1
						run = PackedVector2Array()
				if run.size() >= 2: paths.append(network_path(edge, run, sequence))
	paths.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	return paths

static func network_path(edge: Dictionary, points: PackedVector2Array, sequence: int) -> Dictionary:
	return {"id": "network:%s:%d" % [edge.id, sequence], "points": points,
		"class": "major" if edge.tier == RoadNetwork.TIER_TRUNK else "minor", "layer": 0, "bridges": edge.get("bridges", []).duplicate(true)}

static func compile(paths: Array, centers: Dictionary, ground: Callable = Callable()) -> Dictionary:
	paths = paths.duplicate(true)
	# Trim overshoots at their true intersection before endpoint snapping can
	# turn them into a tiny kink. Repeat after joining newly connected roads.
	var trimmed := Index.trim_stubs(paths)
	var joined := join_endpoints(paths, ground)
	trimmed.append_array(Index.trim_stubs(paths))
	paths = paths.filter(func(p: Dictionary) -> bool: return p.points.size() >= 2)
	return {"paths": paths, "roads": compile_segments(paths, centers), "joined": joined, "trimmed_stubs": trimmed}

static func compile_segments(paths: Array, centers: Dictionary) -> Array:
	var parts: Array = []
	for path in paths:
		var widths: Array = path.get("widths",road_widths(path.class))
		var level: int = int(path.get("level", {"minor": 1, "mid": 2, "major": 3}.get(path.class, 2)))
		for i in range(1, path.points.size()):
			parts.append({"a": path.points[i - 1], "b": path.points[i], "kind": "authored", "level": level,
				"paved": true, "widths": widths, "source": path.id, "layer": path.layer, "district_street":path.get("district_street",false)})
	# Resolve global topology first, then clip it for rendering. Company coverage
	# must not change a junction on its boundary.
	parts = split_crossings(parts)
	var index := Index.tiles(centers)
	var roads: Array = []
	for part in parts:
		for tid in Index.query(index, Index.bounds(part.a, part.b), Index.TILE_CELL):
			var clipped := clip_segment(part.a, part.b, Model.hex_points(centers[tid]))
			if clipped.size() != 2 or clipped[0].distance_to(clipped[1]) < 0.01: continue
			var road: Dictionary = part.duplicate()
			road.tile = tid; road.a = clipped[0]; road.b = clipped[1]
			roads.append(road)
	return roads

static func road_widths(road_class: String) -> Array:
	var bed := Style.bed_width(road_class) * 0.5
	var casing := Style.casing_width(road_class) * 0.5
	return [casing, lerpf(bed, casing, 0.65), lerpf(bed, casing, 0.25), bed]

## Snap to the exact nearest point, then split the receiving segment. This also
## handles T-junctions; quantizing to a grid alone leaves those disconnected.
static func join_endpoints(paths: Array, ground: Callable = Callable()) -> int:
	return Index.join(paths, ground)

static func split_crossings(roads: Array) -> Array:
	return Index.split(roads)

static func clip_segment(a: Vector2, b: Vector2, polygon: PackedVector2Array) -> PackedVector2Array:
	var cuts: Array[float] = [0.0, 1.0]
	var delta := b - a
	if delta.length_squared() < 0.000001: return PackedVector2Array()
	for i in polygon.size():
		var hit: Variant = Geometry2D.segment_intersects_segment(a, b, polygon[i], polygon[(i + 1) % polygon.size()])
		if hit != null: cuts.append(clampf(((hit as Vector2) - a).dot(delta) / delta.length_squared(), 0, 1))
	cuts.sort()
	for i in range(1, cuts.size()):
		if cuts[i] - cuts[i - 1] < 0.00001: continue
		if Geometry2D.is_point_in_polygon(a + delta * (cuts[i] + cuts[i - 1]) * 0.5, polygon):
			return PackedVector2Array([a + delta * cuts[i - 1], a + delta * cuts[i]])
	return PackedVector2Array()

static func place_npcs(model: Dictionary, region: Dictionary, terrain: Node, footprints: Node) -> int:
	if footprints == null: return 0
	var lots := {}
	# The public centre API and read-only footprint geometry refer to the SAME
	# live placements, including authored slots and savegame ownership changes.
	for lot in footprints.get("_placements"):
		lots[str(lot.instance_id)] = lot
	var existing := {}
	for s in model.standing:
		existing[str(s.iid)] = s
		if s.has("port_iid"): existing[str(s.port_iid)] = s
	var count := 0
	for iid in BuildingState.buildings:
		var live: Dictionary = BuildingState.buildings[iid]
		var tid := str(live.get("tile_id", ""))
		if not region.has(tid) or BuildingState.is_land_owned_wood(live): continue
		if not lots.has(iid): continue # No invented centre-stack when a lot is absent.
		var definition: Dictionary = Catalog.get_building(str(live.building_id))
		var family := str(definition.get("internal_name", ""))
		var level := int(live.get("level", 1))
		var key := Assets.key_for(family, level)
		var dim := Assets.dimensions(key)
		var verts: PackedVector2Array = lots[iid].verts
		if verts.is_empty(): continue
		var direction := verts[1] - verts[0]
		for i in verts.size():
			var edge := verts[(i + 1) % verts.size()] - verts[i]
			if edge.length_squared() > direction.length_squared(): direction = edge
		var angle := direction.angle()
		var box := Rect2(verts[0].rotated(-angle), Vector2.ZERO)
		for p in verts: box = box.expand(p.rotated(-angle))
		var side := maxf(4.0, minf(box.size.x / maxf(dim.x, 0.1), box.size.y / maxf(dim.z, 0.1)) * 0.90)
		if family == "farm": side = preload("res://scripts/supply_chain_3d/farm_fields.gd").SIDE
		var s: Dictionary = existing.get(iid, {"kind": "building", "iid": iid, "tile": tid})
		var npc := not BuildingState.is_player_owned(live)
		s.merge({"pos": footprints.call("footprint_center_for", iid, terrain.id_to_coord(tid)), "side": side,
			"pad": side, "internal_name": family, "level": level, "name": str(definition.get("name", family)),
			"sprite": Sprites.npc_texture_for(family, level) if npc else Sprites.texture_for(family, level),
			"npc": npc, "yaw": -angle, "footprint": verts}, true)
		if not existing.has(iid): model.standing.append(s)
		count += 1
	return count

## The legacy model's road endpoints are doors, not building centres. Resolve
## their identities before replacing its presentation layout.
static func bind_flow_ends(model: Dictionary) -> void:
	var by_tile := {}
	for s in model.standing:
		if str(s.kind) == "pylon" or not s.has("pos"): continue
		(by_tile.get_or_add(str(s.tile), []) as Array).append(s)
	for flow in model.get("flows", []):
		if str(flow.mode) not in ["roads", "drive"] or flow.pts.is_empty(): continue
		flow.road_ends = []
		for end in [flow.pts[0], flow.pts[-1]]:
			var best := 100.0
			var iid := ""
			for s in by_tile.get(str(end.tile), []):
				var distance: float = (s.pos as Vector2).distance_to(end.p)
				if distance < best: best = distance; iid = str(s.iid)
			flow.road_ends.append(iid)

## Retain the simulation's goods movements, but route their regional road legs
## along the imported graph. Pipes/rails/cables keep their independent routes.
static func reroute_flows(model: Dictionary, region: Dictionary, roads: Array) -> void:
	var tile_index := Index.tiles(region)
	var standing := {}
	for s in model.standing:
		standing[str(s.iid)] = s
		if s.has("port_iid"): standing[str(s.port_iid)] = s
		if s.has("harbour"): standing["port:" + str(s.tile)] = s
	var graph := AStar2D.new()
	var ids := {}
	for road in roads:
		var ends: Array[int] = []
		for p in [road.a, road.b]:
			var key := Vector2i(((p as Vector2) * 100.0).round())
			if not ids.has(key):
				ids[key] = ids.size()
				graph.add_point(ids[key], p)
			ends.append(ids[key])
		if ends[0] != ends[1]: graph.connect_points(ends[0], ends[1], true)
	if ids.is_empty():
		model.flows = model.flows.filter(func(flow: Dictionary) -> bool: return str(flow.mode) not in ["roads", "drive"])
		return
	var result: Array = []
	var unrouted := 0
	var routes := {}
	for flow in model.flows:
		if str(flow.mode) not in ["roads", "drive"]:
			result.append(flow); continue
		var original: Array = flow.pts
		original = original.duplicate(true)
		var valid := true
		for end in 2:
			var iid := str(flow.get("road_ends", ["", ""])[end])
			var s: Dictionary = standing.get(iid, {})
			if s.has("entrance"): original[0 if end == 0 else original.size() - 1].p = s.entrance
			elif iid != "": valid = false
		if not valid: unrouted += 1; continue
		var points: Array = []
		var i := 0
		while i < original.size():
			if not region.has(str(original[i].tile)):
				points.append(original[i]); i += 1; continue
			var first := i
			while i + 1 < original.size() and region.has(str(original[i + 1].tile)): i += 1
			var a := graph.get_closest_point(original[first].p)
			var b := graph.get_closest_point(original[i].p)
			var route_key := Vector2i(a, b)
			if not routes.has(route_key): routes[route_key] = graph.get_point_path(a, b)
			var path: PackedVector2Array = routes[route_key]
			if path.is_empty(): valid = false; break
			for p in path:
				var tid := Index.tile_at(tile_index, region, p)
				if tid == "": tid = str(original[first].tile)
				points.append({"p": p, "tile": tid, "edge": false})
			i += 1
		if valid:
			flow.pts = points
			result.append(flow)
		else: unrouted += 1
	model.flows = result
	model.authored_region.unrouted_flows = unrouted
