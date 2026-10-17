extends RefCounted
## Mesh-authored insulator clamps and line-aligned towers, independent of camera/LOD.
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")

static func layout(model: Dictionary, frame_for: Callable) -> Dictionary:
	var pylons := {}
	var directions := {}
	for s in model.get("standing", []):
		if str(s.kind) == "pylon": pylons[str(s.iid)] = s
	var links := []
	for line in model.get("lines", []):
		if str(line.mode) != "cables": continue
		var ids: Array = line.get("ids", [])
		if ids.size() != 2 or not pylons.has(str(ids[0])) or not pylons.has(str(ids[1])): continue
		var delta: Vector2 = pylons[str(ids[1])].pos - pylons[str(ids[0])].pos
		if delta.length_squared() < 0.01: continue
		links.append(ids)
		# An undirected line axis: opposite incoming/outgoing spans reinforce
		# instead of cancelling. At bends the crossarms bisect the span axes.
		var angle := delta.angle()
		var axis := Vector2(cos(2.0 * angle), sin(2.0 * angle))
		for id in ids: directions[str(id)] = directions.get(str(id), Vector2.ZERO) + axis
	var yaws := {}
	var anchors := {}
	for id in pylons:
		var s: Dictionary = pylons[id]
		var frame: Dictionary = frame_for.call(s)
		var direction: Vector2 = directions.get(id, Vector2.RIGHT)
		var yaw := -direction.angle() * 0.5 if direction.length_squared() > 0.000001 else 0.0
		yaws[id] = yaw
		var points := PackedVector3Array()
		for point in Assets.cable_anchors(str(frame.key)):
			points.append(frame.position + Basis(Vector3.UP, yaw) * point * float(s.side))
		anchors[id] = points
	var spans := []
	for ids in links:
		var a: PackedVector3Array = anchors[str(ids[0])]
		var b: PackedVector3Array = anchors[str(ids[1])]
		# Keep tiers separate; match left/right by shortest total length so an
		# axis sign change cannot cross the two conductors between the towers.
		for tier in range(0, mini(a.size(), b.size()) - 1, 2):
			var direct := a[tier].distance_squared_to(b[tier]) + a[tier + 1].distance_squared_to(b[tier + 1])
			var swapped := a[tier].distance_squared_to(b[tier + 1]) + a[tier + 1].distance_squared_to(b[tier])
			for side in 2:
				var end := tier + (1 - side if swapped < direct else side)
				spans.append({"a": a[tier + side], "b": b[end], "ids": ids, "tier": tier / 2})
	return {"yaws": yaws, "anchors": anchors, "spans": spans}

static func curve(a: Vector3, b: Vector3) -> PackedVector3Array:
	var length := Vector2(b.x - a.x, b.z - a.z).length()
	var count := maxi(2, ceili(length / 12.0))
	var sag := minf(12.0, length * 0.045)
	var points := PackedVector3Array()
	for i in range(count + 1):
		var t := float(i) / count
		points.append(a.lerp(b, t) - Vector3.UP * sin(t * PI) * sag)
	# Exact endpoints keep the conductors seated even on sloping terrain.
	points[0] = a
	points[-1] = b
	return points
