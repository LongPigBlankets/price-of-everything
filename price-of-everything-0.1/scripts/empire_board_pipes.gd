extends RefCounted
## Supply chain board — pipework laid from baked pieces.
##
## The pieces are rendered in Blender by the sprite rig (.claude/skills/blender-building-sprites/
## pipe_pieces.py) and packed into one atlas (bake_pipes.py): straights, bends of 30, 60 and 90
## degrees, the turns between flat and vertical, a vertical run, the entry into the ground and
## the trestle a raised run stands on. A sprite is seen from one fixed angle, so a finite set
## only covers pipework that keeps to a finite set of directions: here twelve, every 30
## degrees in plan. plan() snaps a route onto that grid and lay() turns it into pieces.
##
## DIRECTIONS. Index k is the Blender angle 30*k degrees. Map y points down and Blender y up,
## so direction k in map space is (cos, -sin).
##
## Pure geometry: nothing here draws or reads the sim.

const Atlas := preload("res://scripts/empire_board_atlas.gd")

const ISO_X := 0.70710678
const ISO_Y := 0.40824829
const ISO_RISE := 0.81649658

## A leg shorter than this is dropped: there is no room on it for the bends at its ends.
const MIN_LEG := 14.0
## How far a run may land from the middle of a tile edge and still cross in one straight leg.
const EDGE_SLACK := 70.0
## A run carries straight on this far past a tile edge before it may turn.
const EDGE_CLEAR := 16.0
## Room between a road's edge and the riser of the bridge over it.
const ROAD_CLEAR := 6.0
const SUPPORT_GAP := 30.0
static var _kit: Atlas = null


## The baked pieces. `ready()` is false when they have not been baked.
static func kit() -> Atlas:
	if _kit == null:
		_kit = Atlas.new("pipes")
	return _kit


static func ready() -> bool:
	return kit().ok()


static func dim(name: String) -> float:
	return kit().dim(name)


static func iso(p: Vector2, h: float = 0.0) -> Vector2:
	return Vector2((p.x - p.y) * ISO_X, (p.x + p.y) * ISO_Y - h * ISO_RISE)


static func dir_of(k: int) -> Vector2:
	var a := deg_to_rad(30.0 * float(posmod(k, 12)))
	return Vector2(cos(a), -sin(a))


static func k_of(v: Vector2) -> int:
	return posmod(int(round(rad_to_deg(atan2(-v.y, v.x)) / 30.0)), 12)


## Steps from direction a to direction b, -5..6.
static func turn(a: int, b: int) -> int:
	var d := posmod(b - a, 12)
	return d - 12 if d > 6 else d


## The name of the bend from travel direction i to travel direction j. The same object walked
## backwards is the bend from j+6 to i+6, and only one of the pair is baked.
static func bend_name(i: int, j: int) -> String:
	var a := [posmod(i, 12), posmod(j, 12)]
	var b := [posmod(j + 6, 12), posmod(i + 6, 12)]
	if b[0] < a[0] or (b[0] == a[0] and b[1] < a[1]):
		a = b
	return "bend_%d_%d" % [a[0], a[1]]


## v as lengths along the two grid directions either side of it: [k1, a, k2, b], a and b >= 0.
static func split(v: Vector2) -> Array:
	var ang := rad_to_deg(atan2(-v.y, v.x))
	var k1 := int(floor(ang / 30.0))
	var u1 := dir_of(k1)
	var u2 := dir_of(k1 + 1)
	var det := u1.x * u2.y - u1.y * u2.x
	var a := (v.x * u2.y - v.y * u2.x) / det
	var b := (u1.x * v.y - u1.y * v.x) / det
	return [posmod(k1, 12), maxf(0.0, a), posmod(k1 + 1, 12), maxf(0.0, b)]


## Snap a route onto the grid. `waypoints` is [{p, base, edge, normal}]: `base` the ground
## height there, and a tile edge given twice (once per tile) with `normal` pointing across it.
## An edge is crossed exactly on the edge's line, so the step up a tile's wall stands on the
## wall; the two ends land within a short leg of where they were asked to.
## Returns legs: [{a, b, k, base}].
static func plan(waypoints: Array) -> Array:
	var legs: Array = []
	if waypoints.size() < 2:
		return legs
	var cur: Vector2 = waypoints[0]["p"]
	var base := float(waypoints[0]["base"])
	var prev_k := -1
	var i := 1
	while i < waypoints.size():
		var w: Dictionary = waypoints[i]
		var target: Vector2 = w["p"]
		var v := target - cur
		if bool(w.get("edge", false)) and i + 1 < waypoints.size():
			var n: Vector2 = w["normal"]
			var parts: Array = split(v)
			# Cross along whichever of the two directions meets the edge more squarely.
			var cross_k: int = parts[0] if absf(dir_of(parts[0]).dot(n)) >= absf(dir_of(parts[2]).dot(n)) else parts[2]
			var g := dir_of(cross_k)
			var reach := (target - cur).dot(n) / g.dot(n)
			var hit := cur + g * reach
			if reach > 0.0 and hit.distance_to(target) <= EDGE_SLACK:
				_add_leg(legs, cur, hit, cross_k, base)
			else:
				var other_k: int = parts[2] if cross_k == parts[0] else parts[0]
				var along: float = parts[3] if cross_k == parts[0] else parts[1]
				if along >= MIN_LEG:
					var mid := cur + dir_of(other_k) * along
					_add_leg(legs, cur, mid, other_k, base)
					cur = mid
				reach = (target - cur).dot(n) / g.dot(n)
				hit = cur + g * maxf(reach, 0.0)
				_add_leg(legs, cur, hit, cross_k, base)
			base = float(waypoints[i + 1]["base"])
			cur = hit + g * EDGE_CLEAR
			_add_leg(legs, hit, cur, cross_k, base)
			prev_k = cross_k
			i += 2
			continue
		var parts2: Array = split(v)
		var first := [parts2[0], parts2[1]]
		var second := [parts2[2], parts2[3]]
		var swap: bool = float(second[1]) > float(first[1])
		if prev_k >= 0:
			swap = absi(turn(prev_k, second[0])) < absi(turn(prev_k, first[0]))
		if swap:
			var t: Array = first
			first = second
			second = t
		for part in [first, second]:
			if float(part[1]) < MIN_LEG:
				continue
			var nxt := cur + dir_of(part[0]) * float(part[1])
			_add_leg(legs, cur, nxt, part[0], base)
			cur = nxt
			prev_k = part[0]
		i += 1
	return legs


static func _add_leg(legs: Array, a: Vector2, b: Vector2, k: int, base: float) -> void:
	if a.distance_to(b) < 0.5:
		return
	if not legs.is_empty():
		var last: Dictionary = legs[legs.size() - 1]
		if int(last["k"]) == k and is_equal_approx(float(last["base"]), base):
			last["b"] = b
			return
	legs.append({"a": a, "b": b, "k": k, "base": base})


## The stretches of a leg that lie over a road, as [from, to] distances along it, with room
## either side for the risers. `roads` is [{a, b, half}] in plan.
static func road_spans(a: Vector2, b: Vector2, roads: Array) -> Array:
	var length := a.distance_to(b)
	var raw: Array = []
	if length < 0.01:
		return raw
	var dir := (b - a) / length
	for r in roads:
		var hit: Variant = Geometry2D.segment_intersects_segment(a, b, r["a"], r["b"])
		if hit == null:
			continue
		var along := (hit as Vector2).distance_to(a)
		var road_dir := ((r["b"] as Vector2) - (r["a"] as Vector2)).normalized()
		# A shallow crossing takes longer to clear the road's width.
		var sine := maxf(0.4, absf(dir.cross(road_dir)))
		var reach := (float(r["half"]) + ROAD_CLEAR) / sine
		raw.append([along - reach, along + reach])
	return raw


## Turn planned legs into pieces. `roads` is what the run has to bridge; `enter` says whether
## each end goes into the ground. Returns {items, line}:
##   items  [{kind: "run"|"vert"|"fit", ...}] each with `depth`, far to near
##   line   the run's centreline as board points, for what flows along it
static func lay(legs: Array, roads: Array, set_id: String, enter: Array = [true, true]) -> Dictionary:
	var items: Array = []
	var line := PackedVector2Array()
	if legs.is_empty():
		return {"items": items, "line": line}
	var rest := dim("rest")
	var lift := dim("raise_")
	var riser := dim("riser_r")
	var bend_r := dim("bend_r")

	# Distances along the whole run, and the places a riser must keep clear of: the bends, the
	# steps between tiles and the two ends.
	var starts := PackedFloat32Array()
	var total := 0.0
	for leg in legs:
		starts.append(total)
		total += (leg["a"] as Vector2).distance_to(leg["b"])
	var zones: Array = [[0.0, rest + 1.0], [total - rest - 1.0, total]]
	for i in range(1, legs.size()):
		var steps := absi(turn(int(legs[i - 1]["k"]), int(legs[i]["k"])))
		var room := bend_r * tan(deg_to_rad(15.0 * float(steps))) + 2.0
		if not is_equal_approx(float(legs[i - 1]["base"]), float(legs[i]["base"])):
			room = riser + 2.0
		zones.append([starts[i] - room, starts[i] + room])
	var raised: Array = []
	for i in range(legs.size()):
		for span in road_spans(legs[i]["a"], legs[i]["b"], roads):
			raised.append([starts[i] + float(span[0]), starts[i] + float(span[1])])
	raised.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
	for span in raised:
		# Push each riser off any bend or step it would land on, outward from the road.
		for _pass in range(6):
			var moved := false
			for z in zones:
				if float(span[0]) - riser < float(z[1]) and float(span[0]) + riser > float(z[0]) and float(z[0]) > 0.0:
					span[0] = float(z[0]) - riser - 0.5
					moved = true
				if float(span[1]) - riser < float(z[1]) and float(span[1]) + riser > float(z[0]) and float(z[1]) < total:
					span[1] = float(z[1]) + riser + 0.5
					moved = true
			if not moved:
				break
		span[0] = maxf(float(span[0]), rest + riser + 2.0)
		span[1] = minf(float(span[1]), total - rest - riser - 2.0)
	var merged: Array = []
	for span in raised:
		if float(span[1]) - float(span[0]) < 2.0 * riser + 2.0:
			continue
		if not merged.is_empty() and float(span[0]) <= float(merged[merged.size() - 1][1]) + 2.0 * riser + 2.0:
			merged[merged.size() - 1][1] = maxf(float(merged[merged.size() - 1][1]), float(span[1]))
		else:
			merged.append(span)

	var up := false
	var first_k := int(legs[0]["k"])
	var last_leg: Dictionary = legs[legs.size() - 1]
	if bool(enter[0]):
		_fit(items, set_id + "_entry_%d" % posmod(first_k + 6, 12), legs[0]["a"], float(legs[0]["base"]))
		line.append(iso(legs[0]["a"], float(legs[0]["base"])))
	for i in range(legs.size()):
		var leg: Dictionary = legs[i]
		var k := int(leg["k"])
		var d := dir_of(k)
		var a: Vector2 = leg["a"]
		var length := a.distance_to(leg["b"])
		var base := float(leg["base"])
		# How much of each end the fitting there takes.
		var head := 0.0
		var tail := 0.0
		if i == 0:
			head = rest if bool(enter[0]) else 0.0
		else:
			var before: Dictionary = legs[i - 1]
			if not is_equal_approx(float(before["base"]), base):
				head = riser
			else:
				head = bend_r * tan(deg_to_rad(15.0 * float(absi(turn(int(before["k"]), k)))))
		if i == legs.size() - 1:
			tail = rest if bool(enter[1]) else 0.0
		else:
			var after: Dictionary = legs[i + 1]
			if not is_equal_approx(float(after["base"]), base):
				tail = riser
			else:
				tail = bend_r * tan(deg_to_rad(15.0 * float(absi(turn(k, int(after["k"]))))))
		# Walk the leg, changing height where a bridge starts or ends.
		var at := head
		var marks: Array = []
		for span in merged:
			for e in range(2):
				var s := float(span[e]) - starts[i]
				if s > 0.0 and s < length:
					marks.append([s, e == 0])
			if float(span[0]) < starts[i] and float(span[1]) > starts[i] and i > 0:
				up = true
		for mark in marks:
			var s := float(mark[0])
			var going_up: bool = mark[1]
			var z0 := base + rest + (lift if up else 0.0)
			_run(items, set_id, a + d * at, a + d * (s - riser), z0, k, up)
			_supports(items, a, d, at, s - riser, z0, k, up, roads)
			var p := a + d * s
			var low := base + rest
			var high := low + lift
			if going_up:
				_fit(items, set_id + "_rise_%d" % k, p, low)
				_fit(items, set_id + "_top_%d" % k, p, high)
			else:
				_fit(items, set_id + "_top_%d" % posmod(k + 6, 12), p, high)
				_fit(items, set_id + "_rise_%d" % posmod(k + 6, 12), p, low)
			_vert(items, set_id, p, low + riser, high - riser)
			line.append(iso(p, z0))
			up = going_up
			line.append(iso(p, base + rest + (lift if up else 0.0)))
			at = s + riser
		var z := base + rest + (lift if up else 0.0)
		_run(items, set_id, a + d * at, a + d * (length - tail), z, k, up)
		_supports(items, a, d, at, length - tail, z, k, up, roads)
		line.append(iso(leg["b"], z))
		# The fitting at this leg's far end.
		if i < legs.size() - 1:
			var nxt: Dictionary = legs[i + 1]
			var nbase := float(nxt["base"])
			if not is_equal_approx(nbase, base):
				var p2: Vector2 = leg["b"]
				var lo := minf(base, nbase) + rest + (lift if up else 0.0)
				var hi := maxf(base, nbase) + rest + (lift if up else 0.0)
				if hi - lo >= 2.0 * riser:
					if nbase > base:
						_fit(items, set_id + "_rise_%d" % k, p2, lo)
						_fit(items, set_id + "_top_%d" % k, p2, hi)
					else:
						_fit(items, set_id + "_top_%d" % posmod(k + 6, 12), p2, hi)
						_fit(items, set_id + "_rise_%d" % posmod(k + 6, 12), p2, lo)
					_vert(items, set_id, p2, lo + riser, hi - riser)
				line.append(iso(p2, nbase + rest + (lift if up else 0.0)))
			elif int(nxt["k"]) != k:
				_fit(items, set_id + "_" + bend_name(k, int(nxt["k"])), leg["b"], z)
	if bool(enter[1]):
		_fit(items, set_id + "_entry_%d" % int(last_leg["k"]), last_leg["b"], float(last_leg["base"]))
		line.append(iso(last_leg["b"], float(last_leg["base"])))
	items.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["depth"]) < float(y["depth"]))
	return {"items": items, "line": line}


static func _fit(items: Array, name: String, p: Vector2, z: float) -> void:
	if not kit().has(name):
		return
	items.append({"kind": "fit", "name": name, "at": iso(p, z), "depth": p.x + p.y + z * 0.02})


static func _run(items: Array, set_id: String, a: Vector2, b: Vector2, z: float, k: int, up: bool) -> void:
	if (b - a).dot(dir_of(k)) < 0.5:
		return
	var mid := (a + b) * 0.5
	items.append({"kind": "run", "name": "%s_%s_%d" % [set_id, "raised" if up else "straight", posmod(k, 6)],
		"a": iso(a, z), "b": iso(b, z), "step": iso(dir_of(posmod(k, 6)) * dim("tile")),
		"depth": mid.x + mid.y + z * 0.02, "depth_a": a.x + a.y + z * 0.02, "depth_b": b.x + b.y + z * 0.02})


static func _vert(items: Array, set_id: String, p: Vector2, z0: float, z1: float) -> void:
	if z1 - z0 < 0.5:
		return
	items.append({"kind": "run", "name": set_id + "_vert", "a": iso(p, z0), "b": iso(p, z1),
		"step": Vector2(0.0, -dim("tile") * ISO_RISE),
		"depth": p.x + p.y + (z0 + z1) * 0.01, "depth_a": p.x + p.y + z0 * 0.02, "depth_b": p.x + p.y + z1 * 0.02})


static func _supports(items: Array, a: Vector2, d: Vector2, from: float, to: float, z: float,
		k: int, up: bool, roads: Array) -> void:
	if not up or to - from < 4.0:
		return
	var n := maxi(1, int(round((to - from) / SUPPORT_GAP)))
	for i in range(n):
		var want := from + (to - from) * (float(i) + 0.5) / float(n)
		# A trestle never stands on a road: it slides along the run to the nearest clear
		# ground, and is left out when there is none.
		var at := -1.0
		for step in [0.0, 5.0, -5.0, 10.0, -10.0, 15.0, -15.0, 20.0, -20.0]:
			var s := want + float(step)
			if s >= from and s <= to and not _on_road(a + d * s, roads):
				at = s
				break
		if at < 0.0:
			continue
		_fit(items, "x_support_%d" % posmod(k, 6), a + d * at, z)
		# The trestle stands behind its run.
		items[items.size() - 1]["depth"] = float(items[items.size() - 1]["depth"]) - 1.0


static func _on_road(p: Vector2, roads: Array) -> bool:
	var reach := dim("support_w") + 2.0
	for r in roads:
		if Geometry2D.get_closest_point_to_segment(p, r["a"], r["b"]).distance_to(p) < float(r["half"]) + reach:
			return true
	return false
