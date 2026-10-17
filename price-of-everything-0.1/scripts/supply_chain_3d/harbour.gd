extends RefCounted
## Authored waterfront art is separate from the small gameplay building lot.
## Keep one logical building, with its whole quay crossing hex boundaries.
const Authored := preload("res://scripts/authored_map.gd")
const Shapes := preload("res://scripts/authored_special_shapes.gd")
const Fabric := preload("res://scripts/authored_fabric_painter.gd")
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const Ground := preload("res://scripts/empire_board_ground.gd")

static func layouts() -> Dictionary:
	var result := {}
	for settlement in Authored.settlements().values():
		for rec in settlement.get("specials", []):
			var tid := str(rec.get("port", ""))
			if tid == "": continue
			var entry: Dictionary = result.get_or_add(tid, {"quays": [], "sheds": [], "decor": []})
			var poly := Shapes.render_polygon(rec)
			if poly.size() < 3: continue
			if str(rec.get("port_role", "")) == "warehouse": entry.sheds.append(poly)
			else: entry.quays.append(poly)
		for rec in settlement.get("port_decor", []):
			var tid := str(rec.get("tile", ""))
			if result.has(tid): result[tid].decor.append(rec.duplicate(true))
	for entry in result.values():
		# The broad main quay fixes the shore edge; the two narrow piers point out
		# to sea. Keep that pose before unioning duplicate authored pier records.
		var main := PackedVector2Array()
		var largest := 0.0
		for poly in entry.quays:
			var area := 0.0
			for i in poly.size(): area += poly[i].cross(poly[(i + 1) % poly.size()])
			if absf(area) > largest: main = poly; largest = absf(area)
		# Older authored ports have no crane decor. Their narrow pier's long
		# edge still supplies an exact direction, signed away from the main quay.
		var main_center := polygon_center(main)
		var offshore := Vector2.DOWN
		for poly in entry.quays:
			if poly == main: continue
			var longest := Vector2.ZERO
			for i in poly.size():
				var edge: Vector2 = poly[(i + 1) % poly.size()] - poly[i]
				if edge.length_squared() > longest.length_squared(): longest = edge
			offshore = longest.normalized()
			if offshore.dot(polygon_center(poly) - main_center) < 0.0: offshore = -offshore
			break
		for rec in entry.decor:
			if str(rec.get("kind", "")) == "crane":
				offshore = Vector2(rec.direction[0], rec.direction[1]).normalized()
				break
		var across := Vector2(-offshore.y, offshore.x)
		var front := -INF
		var lo := INF
		var hi := -INF
		for point in main:
			front = maxf(front, point.dot(offshore))
			lo = minf(lo, point.dot(across))
			hi = maxf(hi, point.dot(across))
		entry.shore_anchor = offshore * front + across * (lo + hi) * 0.5
		entry.offshore = offshore
		entry.width = hi - lo
		entry.main_quay = main
		entry.quays = Fabric.merged_rings(entry.quays)
		var box := Rect2()
		var started := false
		for poly in entry.quays:
			for point in poly:
				if not started: box = Rect2(point, Vector2.ZERO); started = true
				box = box.expand(point)
		entry.bounds = box
	return result

static func apply(model: Dictionary) -> void:
	var authored := layouts()
	for tid in authored:
		if not model.tiles.has(tid): continue
		var layout: Dictionary = authored[tid]
		if layout.quays.is_empty(): continue
		var iid := ""
		var live := {}
		for id in BuildingState.buildings:
			var rec: Dictionary = BuildingState.buildings[id]
			if str(rec.get("tile_id", "")) == tid and str(rec.get("building_id", "")) == "b_004":
				iid = str(id); live = rec; break
		# Deduplicate by logical port tile, not the unrelated trade-graph ID.
		var removed: Array = []
		for s in model.standing:
			if str(s.tile) == tid and (str(s.kind) == "port" or str(s.get("internal_name", "")) == "port"):
				removed.append(s)
		if iid == "" and removed.is_empty(): continue
		for s in removed: model.standing.erase(s)
		var center: Vector2 = layout.bounds.get_center()
		var standing := {"kind": "building" if iid != "" else "port", "iid": iid if iid != "" else "port:" + tid,
			"tile": tid, "pos": center, "side": 1.0, "pad": 1.0, "internal_name": "port",
			"name": "Port", "npc": not BuildingState.is_player_owned(live), "level": int(live.get("level", 1)), "harbour": layout}
		model.standing.append(standing)
		# Procedural scenery may occupy the authored port's lot outside the road
		# pilot. Reserve its waterfront footprint, including across tile borders.
		for decor in model.standing.duplicate():
			if str(decor.kind) != "house": continue
			var clearance: Rect2 = layout.bounds.grow(float(decor.get("side", 0.0)) * 0.6 + 8.0)
			if clearance.has_point(decor.pos): model.standing.erase(decor)
		# Move visual trade endpoints with their harbour. The simulation IDs stay intact.
		for flow in model.get("flows", []):
			if flow.pts.is_empty(): continue
			for index in [0, flow.pts.size() - 1]:
				for old in removed:
					if (flow.pts[index].p as Vector2).distance_to(old.pos) < 2.0:
						flow.pts[index] = flow.pts[index].duplicate()
						flow.pts[index].p = center

static func frame(s: Dictionary, height_at: Callable, origin: Vector2) -> Dictionary:
	var layout: Dictionary = s.harbour
	var key := Assets.key_for("port", 1)
	var asset := Assets.harbour_for(key)
	# Set the ship waterline on the game's sea, and the quay deck on the bank.
	# Horizontal fitting follows the authored shore edge, independently of relief.
	var level := Ground.SEA_LEVEL
	for point in layout.main_quay: level = maxf(level, float(height_at.call(point)))
	level += 1.5
	var scale_xz := float(layout.width) / float(asset.across)
	var scale_y := (level - Ground.SEA_LEVEL) / (float(asset.deck) - float(asset.waterline))
	var basis := Basis(Vector3.UP, -(layout.offshore as Vector2).angle()).scaled_local(Vector3(scale_xz, scale_y, scale_xz))
	var anchor: Vector2 = layout.shore_anchor - s.pos
	var offset := Vector3(anchor.x, Ground.SEA_LEVEL, anchor.y) - basis * vector3(asset.anchor)
	var pose := Transform3D(basis, offset)
	# The coast curves under a rectangular dock. Slide the back edge inland only
	# as far as needed for its three shore contact points to reach dry ground.
	var inland: Vector2 = -layout.offshore
	var shore_shift := 0.0
	while shore_shift < 100.0:
		var connected := true
		for xyz in asset.shore_edge:
			var contact: Vector3 = pose * vector3(xyz)
			if float(height_at.call(s.pos + Vector2(contact.x, contact.z))) < Ground.SEA_LEVEL + 2.0:
				connected = false
				break
		if connected: break
		pose.origin += Vector3(inland.x, 0, inland.y) * 2.0
		shore_shift += 2.0
	# A curved coast need not touch every corner. Prefer a partially overhanging
	# back quay to grounding the ships when the three-point fit reaches inland.
	# If authoring offers no wet fit, retain its original shore solution.
	var shore_pose := pose
	var dry_shift := shore_shift
	while shore_shift > 0.0 and not ships_afloat(asset, pose, s.pos, height_at):
		pose.origin -= Vector3(inland.x, 0, inland.y) * 2.0
		shore_shift -= 2.0
	if not ships_afloat(asset, pose, s.pos, height_at):
		pose = shore_pose
		shore_shift = dry_shift
	var low := vector3(asset.bounds_min)
	var bounds := pose * AABB(low, vector3(asset.bounds_max) - low)
	var dimension := Vector3(maxf(absf(bounds.position.x), absf(bounds.end.x)) * 2.0,
		bounds.end.y, maxf(absf(bounds.position.z), absf(bounds.end.z)) * 2.0)
	return {"key": "", "position": Vector3(s.pos.x - origin.x, 0, s.pos.y - origin.y),
		"dimension": dimension, "plinth_depth": 0.0, "harbour_asset": key, "harbour_transform": pose,
		"harbour_deck": level, "harbour_shore_shift": shore_shift, "harbour_pier_tip": pose * vector3(asset.pier_tip),
		"harbour_basin": pose * vector3(asset.basin)}

static func picking_shape(frame_data: Dictionary) -> ConcavePolygonShape3D:
	# Bake the transform into the four harbour colliders: physics must not receive
	# the nonuniform scaling used to align deck and waterline with terrain relief.
	var faces := Assets.mesh_for(frame_data.harbour_asset).get_faces()
	for i in faces.size(): faces[i] = frame_data.harbour_transform * faces[i]
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	return shape

static func vector3(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])

static func polygon_center(poly: PackedVector2Array) -> Vector2:
	var center := Vector2.ZERO
	for point in poly: center += point
	return center / maxi(poly.size(), 1)

static func ships_afloat(asset: Dictionary, pose: Transform3D, center: Vector2, height_at: Callable) -> bool:
	for xyz in asset.ship_water:
		var contact: Vector3 = pose * vector3(xyz)
		if float(height_at.call(center + Vector2(contact.x, contact.z))) > Ground.SEA_LEVEL + 0.5: return false
	return true
