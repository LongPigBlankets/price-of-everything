extends RefCounted
## Read-only pilot adapter. The regular map remains the authority for roads/lots.
const Model := preload("res://scripts/empire_board_model.gd")
const Authored := preload("res://scripts/authored_map.gd")
const Curves := preload("res://scripts/authored_road_geometry.gd")
const Style := preload("res://scripts/authored_road_style.gd")
const Regions := preload("res://scripts/road_regions.gd")
const Sprites := preload("res://scripts/building_sprites.gd")
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const JOIN_DISTANCE := 2.0

static func tile_ids() -> Array:
	return Regions.get_region("stoneshore").get("tiles", [])

static func apply(model: Dictionary, terrain: Node, footprints: Node) -> void:
	var region := {}
	for tid in tile_ids():
		if model.tiles.has(tid): region[tid] = model.tiles[tid].center
	if region.is_empty(): return
	var flagged := {}
	for tile in terrain.get("tiles").values():
		if "roads" in tile.get("infrastructure_present", []): flagged[str(tile.id)] = true
	var paths: Array = []
	for settlement in Authored.settlements().values():
		for stroke in settlement.get("roads", []):
			if not Authored.road_visible(stroke, flagged): continue
			var touches := false
			for tid in stroke.get("tiles", []):
				if region.has(tid): touches = true; break
			if not touches: continue
			var points := Curves.sample(stroke)
			if points.size() > 1:
				paths.append({"id": str(stroke.id), "points": points, "class": str(stroke.get("class", "mid")),
					"bridges": stroke.get("bridges", []), "layer": int(stroke.get("layer", 0))})
	paths.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	var joined := join_endpoints(paths)
	var roads: Array = model.roads.filter(func(r: Dictionary) -> bool: return not region.has(str(r.tile)))
	var regional: Array = []
	for path in paths:
		var widths := road_widths(path.class)
		var level: int = {"minor": 1, "mid": 2, "major": 3}.get(path.class, 2)
		for i in range(1, path.points.size()):
			for tid in region:
				var clipped := clip_segment(path.points[i - 1], path.points[i], Model.hex_points(region[tid]))
				if clipped.size() != 2 or clipped[0].distance_to(clipped[1]) < 0.01: continue
				regional.append({"tile": tid, "a": clipped[0], "b": clipped[1], "kind": "authored",
					"level": level, "paved": true, "widths": widths, "source": path.id, "layer": path.layer})
	regional = split_crossings(regional)
	roads.append_array(regional)
	model.roads = roads
	model.standing = model.standing.filter(func(s: Dictionary) -> bool: return not (region.has(str(s.tile)) and s.kind == "house"))
	var npc_count := place_npcs(model, region, terrain, footprints)
	model.authored_region = {"tiles": region, "paths": paths, "joined": joined, "npc_count": npc_count}
	reroute_flows(model, region, regional)

static func road_widths(road_class: String) -> Array:
	var bed := Style.bed_width(road_class) * 0.5
	var casing := Style.casing_width(road_class) * 0.5
	return [casing, lerpf(bed, casing, 0.65), lerpf(bed, casing, 0.25), bed]

## Snap to the exact nearest point, then split the receiving segment. This also
## handles T-junctions; quantizing to a grid alone leaves those disconnected.
static func join_endpoints(paths: Array) -> int:
	var count := 0
	for path in paths:
		for end in [0, -1]:
			var points: PackedVector2Array = path.points
			var p := points[end]
			var tangent := (p - points[1 if end == 0 else -2]).normalized()
			var best := JOIN_DISTANCE + 0.0001
			var target: Dictionary = {}
			var at := -1
			var snapped := p
			for other in paths:
				if other.id == path.id or other.get("layer", 0) != path.get("layer", 0): continue
				var line: PackedVector2Array = other.points
				for i in range(1, line.size()):
					var q := Geometry2D.get_closest_point_to_segment(p, line[i - 1], line[i])
					var distance := p.distance_to(q)
					if distance >= best: continue
					# Do not fold a parallel lane into its neighbour's interior.
					var interior := q.distance_to(line[i - 1]) > 0.05 and q.distance_to(line[i]) > 0.05
					if distance > 0.05 and interior and absf(tangent.dot((line[i] - line[i - 1]).normalized())) > 0.97: continue
					best = distance; target = other; at = i; snapped = q
			if at < 0: continue
			points[end] = snapped
			path.points = points
			var line: PackedVector2Array = target.points
			if snapped.distance_to(line[at - 1]) > 0.01 and snapped.distance_to(line[at]) > 0.01:
				line.insert(at, snapped)
				target.points = line
			if best > 0.001: count += 1
	return count

## Interior crossings are graph junctions too, even when neither authored
## stroke happens to put a control point at the crossing.
static func split_crossings(roads: Array) -> Array:
	var cuts: Array = []
	for road in roads: cuts.append([road.a, road.b])
	for i in roads.size():
		var a: Dictionary = roads[i]
		for j in range(i + 1, roads.size()):
			var b: Dictionary = roads[j]
			if a.get("layer", 0) != b.get("layer", 0): continue
			var hit: Variant = Geometry2D.segment_intersects_segment(a.a, a.b, b.a, b.b)
			if hit == null: continue
			for index in [i, j]:
				var found := false
				for p in cuts[index]:
					if (p as Vector2).distance_to(hit) < 0.01: found = true; break
				if not found: cuts[index].append(hit)
	var result: Array = []
	for i in roads.size():
		var source: Dictionary = roads[i]
		var points: Array = cuts[i]
		points.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_squared_to(source.a) < b.distance_squared_to(source.a))
		for j in range(1, points.size()):
			if (points[j - 1] as Vector2).distance_to(points[j]) < 0.01: continue
			var part := source.duplicate()
			part.a = points[j - 1]
			part.b = points[j]
			result.append(part)
	return result

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
		if not region.has(tid) or BuildingState.is_player_owned(live) or BuildingState.is_land_owned_wood(live): continue
		if not lots.has(iid): continue # No invented centre-stack when a lot is absent.
		var definition: Dictionary = Catalog.get_building(str(live.building_id))
		var family := str(definition.get("internal_name", ""))
		var level := int(live.get("level", 1))
		var key := Assets.key_for(family, level)
		var dim := Assets.dimensions(key)
		var verts: PackedVector2Array = lots[iid].verts
		if verts.is_empty(): continue
		var box := Rect2(verts[0], Vector2.ZERO)
		for p in verts: box = box.expand(p)
		var side := maxf(4.0, minf(box.size.x / maxf(dim.x, 0.1), box.size.y / maxf(dim.z, 0.1)) * 0.90)
		var s: Dictionary = existing.get(iid, {"kind": "building", "iid": iid, "tile": tid})
		s.merge({"pos": footprints.call("footprint_center_for", iid, terrain.id_to_coord(tid)), "side": side,
			"pad": side, "internal_name": family, "level": level, "name": str(definition.get("name", family)),
			"sprite": Sprites.npc_texture_for(family, level), "npc": true, "polluting": false}, true)
		if not existing.has(iid): model.standing.append(s)
		count += 1
	return count

## Retain the simulation's goods movements, but route their regional road legs
## along the imported graph. Pipes/rails/cables keep their independent routes.
static func reroute_flows(model: Dictionary, region: Dictionary, roads: Array) -> void:
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
	if ids.is_empty(): return
	var result: Array = []
	var unrouted := 0
	for flow in model.flows:
		if str(flow.mode) not in ["roads", "drive"]:
			result.append(flow); continue
		var original: Array = flow.pts
		var points: Array = []
		var valid := true
		var i := 0
		while i < original.size():
			if not region.has(str(original[i].tile)):
				points.append(original[i]); i += 1; continue
			var first := i
			while i + 1 < original.size() and region.has(str(original[i + 1].tile)): i += 1
			var a := graph.get_closest_point(original[first].p)
			var b := graph.get_closest_point(original[i].p)
			var path := graph.get_point_path(a, b)
			if path.is_empty(): valid = false; break
			points.append(original[first])
			for p in path:
				var tid := str(original[first].tile)
				for candidate in region:
					if Geometry2D.is_point_in_polygon(p, Model.hex_points(region[candidate])): tid = candidate; break
				points.append({"p": p, "tile": tid, "edge": false})
			points.append(original[i])
			i += 1
		if valid:
			flow.pts = points
			result.append(flow)
		else: unrouted += 1
	model.flows = result
	model.authored_region.unrouted_flows = unrouted
