extends RefCounted
## Shared railway kit: continuous track geometry, also baked into the sprite atlas.
## Coordinates/grades belong to the map, never to the camera. All levels keep one gauge.
const Geo := preload("res://scripts/supply_chain_3d/geometry.gd")
const Index := preload("res://scripts/supply_chain_3d/road_index.gd")
const VERSION := 9
# Match the authored two-lane road carriageway, including map draw scale.
const CORRIDOR_WIDTH := 12.6 * 0.75
const WIDTH_SCALE := CORRIDOR_WIDTH / 28.4
const TUNNEL_LEVEL := 6
const GAUGE := 4.8 * WIDTH_SCALE
const TRACK_SPACING := 16.0 * WIDTH_SCALE
const HALF := 6.2 * WIDTH_SCALE
const SAMPLE := 3.0
const CURVE := 110.0
const CLEARANCE := CORRIDOR_WIDTH * 0.85 # ~5m: slightly less than a two-lane road
const APPROACH := 80.0
const DECK_DEPTH := 1.0
const BALLAST := Color("827d70")
const STEEL := Color("cad0cc")
const WEB := Color("485359")
const GIRDER := Color("536a65")
const CONCRETE := Color("a8aa9b")
const CONCRETE_FACE := Color("969889")
## River crossings: a through truss (steel) on concrete abutments and piers.
const TRUSS := Color("4f625d")
const TRUSS_HEIGHT := 6.5
const TRUSS_PANEL := 7.0
const TRUSS_OFFSET := CORRIDOR_WIDTH * 0.5 + 1.1
## Track this far beyond the water either side still stands on the bridge.
const RIVER_PAD := 7.0
## How many samples a truss may reach past its bank to stand clear of a road under its end.
const ABUTMENT_REACH := 12
## Clear height a road needs under a deck.
const ROAD_HEADROOM := 4.5
## The steepest visible track: anything steeper is a step where two height rules meet.
const MAX_GRADE := 0.25
## The steepest a ramp lifting track over a road climbs (smoothstep peaks at 1.5x its mean).
const LIFT_GRADE := 0.06
const MAX_LIFT_APPROACH := 220.0
## A river pier stands at most this far from the next support.
const PIER_SPACING := 38.0

static func is_rail(mode: String) -> bool:
	return mode in ["rail", "rails"]

static func _key(p: Vector2) -> Vector2i:
	return Vector2i((p * 100.0).round())

static func _curve(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var steps := maxi(8, ceili((a.distance_to(b) + b.distance_to(c) + c.distance_to(d)) / SAMPLE))
	for i in range(steps + 1):
		var t := float(i) / steps
		out.append(a.bezier_interpolate(b, c, d, t))
	return out

static func _line(a: Vector2, b: Vector2) -> PackedVector2Array:
	return _curve(a, a.lerp(b, 0.333333), a.lerp(b, 0.666667), b)

## Split at real intersections AND collinear overlaps before constructing any switches.
## This makes shared track independent of route order and route duplication.
static func network(lines: Array, display_only := false) -> Dictionary:
	var segments: Array = []
	for rec in lines:
		if not is_rail(str(rec.get("mode", ""))): continue
		var pts: Array = rec.get("pts", [])
		for i in range(1, pts.size()):
			var a: Vector2 = pts[i - 1].p
			var b: Vector2 = pts[i].p
			if a.distance_to(b) > 0.1: segments.append({"a": a, "b": b, "cuts": [0.0, 1.0], "level": int(rec.get("level", 1))})
	var segment_index := Index.segments(segments, 0.01)
	for i in segments.size():
		var s: Dictionary = segments[i]
		for j in Index.query(segment_index, Index.bounds(s.a, s.b, 0.01)):
			if j <= i: continue
			var t: Dictionary = segments[j]
			var hit: Variant = Geometry2D.segment_intersects_segment(s.a, s.b, t.a, t.b)
			if hit != null:
				_cut(s, hit); _cut(t, hit)
			for p in [s.a, s.b]:
				if Geometry2D.get_closest_point_to_segment(p, t.a, t.b).distance_to(p) < 0.01: _cut(t, p)
			for p in [t.a, t.b]:
				if Geometry2D.get_closest_point_to_segment(p, s.a, s.b).distance_to(p) < 0.01: _cut(s, p)
	var nodes := {}
	var edges := {}
	for s in segments:
		s.cuts.sort()
		for i in range(1, s.cuts.size()):
			var a: Vector2 = s.a.lerp(s.b, float(s.cuts[i - 1]))
			var b: Vector2 = s.a.lerp(s.b, float(s.cuts[i]))
			if a.distance_to(b) < 0.05: continue
			var ka := _key(a); var kb := _key(b)
			var id := str(ka) + ":" + str(kb) if str(ka) < str(kb) else str(kb) + ":" + str(ka)
			if edges.has(id):
				edges[id].level = maxi(int(edges[id].level), int(s.level))
				continue
			edges[id] = {"a": ka, "b": kb, "level": s.level}
			for pair in [[ka, a, kb], [kb, b, ka]]:
				if not nodes.has(pair[0]): nodes[pair[0]] = {"p": pair[1], "arms": []}
				nodes[pair[0]].arms.append({"to": pair[2], "level": s.level})
	var paths: Array = []
	var switches: Array = []
	var buffers: Array = []
	var junctions: Array = []
	for key in nodes:
		var node: Dictionary = nodes[key]
		for arm in node.arms:
			var delta: Vector2 = nodes[arm.to].p - node.p
			arm.dir = delta.normalized()
			arm.reach = minf(CURVE, delta.length() * 0.44) if node.arms.size() > 1 else 0.0
			arm.port = node.p + arm.dir * arm.reach
		node.arms.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.dir.angle() < b.dir.angle())
	for edge in edges.values():
		var a := _arm(nodes[edge.a], edge.b)
		var b := _arm(nodes[edge.b], edge.a)
		a.level = edge.level; b.level = edge.level
		paths.append({"points": _line(a.port, b.port), "level": edge.level})
	for node in nodes.values():
		var arms: Array = node.arms
		if arms.size() == 1:
			buffers.append({"p": node.p, "dir": arms[0].dir})
			continue
		if arms.size() == 2 or (not display_only and arms.size() <= 4):
			# Every pair of arms has a direct through movement. A train can enter
			# from any arm and leave any other without reversing at the junction.
			var movements: Array = []
			for i in arms.size():
				for j in range(i + 1, arms.size()):
					var a: Dictionary = arms[i]; var b: Dictionary = arms[j]
					var handle: float = a.port.distance_to(b.port) * 0.40
					paths.append({"points": _curve(a.port, a.port - a.dir * handle, b.port - b.dir * handle, b.port),
						"level": maxi(int(a.level), int(b.level)), "start_dir": -a.dir, "end_dir": b.dir,
						"movement": Vector2i(i,j), "junction": _key(node.p)})
					movements.append(Vector2i(i,j))
			if arms.size() >= 3:
				junctions.append({"p": node.p, "arms": arms.size(), "radius":arms.map(func(arm): return arm.reach).max(), "movements": movements})
				for arm in arms:
					switches.append({"p": arm.port, "dir": -arm.dir, "degree": arms.size(), "junction_arms": arms.size()})
			continue
		junctions.append({"p":node.p,"arms":arms.size(),"radius":arms.map(func(arm): return arm.reach).max(),"movements":[]})
		# The display uses one trunk and one turnout per extra arm. Keep the
		# full logical movement network for engineering, without drawing every turn.
		# The straightest pair is the through route. Other arms join that route
		# tangentially at staggered points: a turnout ladder, never a road-like fan.
		var pair := Vector2i(0, 1)
		var best := 2.0
		for i in arms.size():
			for j in range(i + 1, arms.size()):
				var dot: float = arms[i].dir.dot(arms[j].dir)
				if dot < best: best = dot; pair = Vector2i(i, j)
		var a: Dictionary = arms[pair.x]; var b: Dictionary = arms[pair.y]
		var handle: float = a.port.distance_to(b.port) * 0.40
		var trunk := _curve(a.port, a.port - a.dir * handle, b.port - b.dir * handle, b.port)
		paths.append({"points": trunk, "level": maxi(int(a.level), int(b.level)), "junction":_key(node.p), "start_dir":-a.dir, "end_dir":b.dir})
		var branch_index := 0
		for i in arms.size():
			if i == pair.x or i == pair.y: continue
			var branch: Dictionary = arms[i]
			var forward: bool = branch.dir.dot(a.dir) < branch.dir.dot(b.dir)
			var t := clampf(0.26 + branch_index * 0.10, 0.20, 0.44)
			if not forward: t = 1.0 - t
			var index := clampi(roundi(t * (trunk.size() - 1)), 1, trunk.size() - 2)
			var start := trunk[index]
			var tangent := (trunk[index + 1] - trunk[index - 1]).normalized() * (1.0 if forward else -1.0)
			var length := start.distance_to(branch.port)
			paths.append({"points": _curve(start, start + tangent * length * 0.55,
				branch.port - branch.dir * length * 0.55, branch.port), "level": branch.level, "turnout": true, "junction":_key(node.p), "start_dir":tangent, "end_dir":branch.dir})
			switches.append({"p": start, "dir": tangent, "degree": 3, "junction_arms": arms.size()})
			branch_index += 1
	var paired: Array = []
	for index in paths.size():
		var path: Dictionary = paths[index]
		for side in [-1.0, 1.0]:
			var lane: Dictionary = path.duplicate()
			lane.points = _offset_track(path, side * TRACK_SPACING * 0.5)
			lane.pair_id = index; lane.side = side
			paired.append(lane)
	var paired_switches: Array = []
	for switch in switches:
		for side in [-1.0, 1.0]:
			var item: Dictionary = switch.duplicate()
			item.p += item.dir.orthogonal() * side * TRACK_SPACING * 0.5
			item.actuator_side = side
			paired_switches.append(item)
	var paired_buffers: Array = []
	for buffer in buffers:
		for side in [-1.0,1.0]:
			var item: Dictionary = buffer.duplicate()
			item.p += item.dir.orthogonal() * side * TRACK_SPACING * 0.5
			paired_buffers.append(item)
	return {"paths": paired, "corridors": paths, "switches": paired_switches, "buffers": paired_buffers,
		"nodes": nodes.size(), "junctions": junctions}

static func _offset_track(path: Dictionary, offset: float) -> PackedVector2Array:
	var points: PackedVector2Array = path.points
	var out := PackedVector2Array()
	for i in points.size():
		var tangent := (points[mini(i+1,points.size()-1)] - points[maxi(0,i-1)]).normalized()
		if i == 0: tangent = path.get("start_dir", tangent)
		elif i == points.size()-1: tangent = path.get("end_dir", tangent)
		out.append(points[i] + tangent.orthogonal() * offset)
	return out

static func _cut(s: Dictionary, p: Vector2) -> void:
	s.cuts.append(clampf((p - s.a).dot(s.b - s.a) / s.a.distance_squared_to(s.b), 0, 1))

static func _arm(node: Dictionary, to: Vector2i) -> Dictionary:
	for arm in node.arms:
		if arm.to == to: return arm
	return {}

## Profile each whole track, with a horizontal deck and smooth approach on BOTH sides.
## Adjacent bridges form one raised envelope. Mountain intervals are explicitly omitted.
static func profile(points: PackedVector2Array, roads: Array, height: Callable, level_at: Callable, shared_crossings: Array = [], half_width: float = HALF + 0.8, road_index: Dictionary = {}, crossing_index: Dictionary = {}, crossings_only := false, crossing_height: Callable = Callable(), burial: Callable = Callable(), rail_profile: Callable = Callable()) -> Dictionary:
	var distances := PackedFloat32Array([0.0])
	for i in range(1, points.size()): distances.append(distances[-1] + points[i - 1].distance_to(points[i]))
	var crossings: Array = []
	for i in range(1, points.size()):
		for road_id in (range(roads.size()) if road_index.is_empty() else Index.query(road_index, Index.bounds(points[i-1], points[i], 0.01))):
			var road: Dictionary = roads[road_id]
			if road.get("over_rail",false) or road.has("rail_crossing_mode"): continue
			var hit: Variant = Geometry2D.segment_intersects_segment(points[i - 1], points[i], road.a, road.b)
			if hit == null: continue
			var p: Vector2 = hit
			if burial.is_valid() and (burial.call(p) as Vector2).x>0: continue
			if float(level_at.call(p)) >= TUNNEL_LEVEL: continue
			var dir := (points[i] - points[i - 1]).normalized()
			var road_dir: Vector2 = (road.b - road.a).normalized()
			var sine := absf(dir.cross(road_dir))
			if sine < 0.05: continue # parallel tracks are not a crossing
			var half := float(road.get("widths", [4.5 + 3.0 * (int(road.get("level", 1)) - 1)])[0])
			var span := (half + HALF + 5.0) / sine
			var station := float(distances[i - 1]) + points[i - 1].distance_to(p)
			var duplicate := false
			for c in crossings:
				if absf(c.s - station) < 0.5: duplicate = true
			if not duplicate: crossings.append({"p": p, "s": station, "half": span, "h": float(crossing_height.call(p) if crossing_height.is_valid() else height.call(p)) + CLEARANCE + DECK_DEPTH, "dir": dir})
	if crossings_only: return {"crossings": crossings}
	var samples: Array = []
	var envelope: Array = crossings if shared_crossings.is_empty() else shared_crossings
	for i in points.size():
		var p := points[i]
		var d := float(distances[i])
		var base_height := float(height.call(p)) + 1.2
		var h := base_height
		# What the crossings ask for here, so the engineered urban profile cannot cut off a ramp.
		var lifted := -INF
		var bridge := false
		for crossing_id in (range(envelope.size()) if crossing_index.is_empty() else crossing_index.get(Vector2i((p / Index.CELL).floor()), [])):
			var c: Dictionary = envelope[crossing_id]
			var away := maxf(0.0, p.distance_to(c.p) - float(c.half))
			if away > APPROACH: continue
			var weight := 1.0 - smoothstep(0.0, APPROACH, away)
			h = maxf(h, lerpf(base_height, float(c.h), weight))
			lifted = maxf(lifted, lerpf(base_height, float(c.h), weight))
			bridge = bridge or away < 0.01
		var underground: Vector2 = burial.call(p) if burial.is_valid() else Vector2.ZERO
		if underground.x>0:
			h = lerpf(h,base_height-underground.x,smoothstep(0,6,underground.x)); bridge=false
		var tangent := (points[mini(i + 1, points.size() - 1)] - points[maxi(0, i - 1)]).normalized()
		var side := tangent.orthogonal() * half_width
		var hidden := float(level_at.call(p)) >= TUNNEL_LEVEL or float(level_at.call(p + side)) >= TUNNEL_LEVEL or float(level_at.call(p - side)) >= TUNNEL_LEVEL
		if rail_profile.is_valid():
			var engineered: Vector3=rail_profile.call(p)
			hidden=engineered.y>0; underground.y=engineered.y
			# At grade the engineered profile keeps a crossing's ramp; buried track is its own.
			if engineered.z>0 and (engineered.y>0 or lifted<=engineered.x): h=engineered.x; bridge=false
			elif engineered.z>0: h=lifted
		samples.append({"p": p, "h": h, "s": d, "hidden": hidden or underground.y>0, "buried":underground.y>0, "bridge": bridge, "dir": tangent})
	_lift_over_roads(samples, crossings, roads, road_index)
	_limit_grade(samples, roads, road_index, half_width)
	return {"samples": samples, "crossings": crossings}

## Where visible track crosses a road neither at level nor with a road's headroom under it (the
## approach to a river truss, a flat road deck meeting a truss), the track rises over the road
## on its own concrete deck. The ramp lengthens with the lift so it never climbs more steeply
## than LIFT_GRADE. A road meant to pass over the railway is left to its own deck.
static func _lift_over_roads(samples: Array, crossings: Array, roads: Array, road_index: Dictionary) -> void:
	var lifts: Array = []
	for i in range(1, samples.size()):
		var a: Dictionary = samples[i - 1]
		var b: Dictionary = samples[i]
		if a.hidden or b.hidden: continue
		for road_id in (range(roads.size()) if road_index.is_empty() else Index.query(road_index, Index.bounds(a.p, b.p, 0.01))):
			var road: Dictionary = roads[road_id]
			if not road.has("ha") or str(road.get("rail_crossing_mode", "")) in ["bridge", "tunnel"]: continue
			var hit: Variant = Geometry2D.segment_intersects_segment(a.p, b.p, road.a, road.b)
			if hit == null: continue
			var t := (a.p as Vector2).distance_to(hit) / maxf(0.01, (a.p as Vector2).distance_to(b.p))
			var rail_h := lerpf(float(a.h), float(b.h), t)
			var road_h := lerpf(float(road.ha), float(road.hb), (road.a as Vector2).distance_to(hit) / maxf(0.01, (road.a as Vector2).distance_to(road.b)))
			var target := road_h + CLEARANCE + DECK_DEPTH + 0.25
			var truss: bool = a.get("river", false) or b.get("river", false)
			if rail_h < road_h - 0.8 or rail_h >= target - 0.01: continue
			if absf(rail_h - road_h) < 0.8 and not truss: continue
			var dir := ((b.p as Vector2) - (a.p as Vector2)).normalized()
			var sine := maxf(0.2, absf(dir.cross(((road.b as Vector2) - (road.a as Vector2)).normalized())))
			lifts.append({"p": hit, "s": lerpf(float(a.s), float(b.s), t), "half": (CORRIDOR_WIDTH * 0.5 + float(road.get("half", 4.0)) + 2.0) / sine,
				"h": target, "dir": dir, "lift": target - rail_h})
	for lift in lifts:
		var approach := clampf(float(lift.lift) * 1.5 / LIFT_GRADE, APPROACH, MAX_LIFT_APPROACH)
		for sample in samples:
			if sample.hidden: continue
			var away := maxf(0.0, absf(float(sample.s) - float(lift.s)) - float(lift.half))
			if away > approach: continue
			sample.h = maxf(float(sample.h), lerpf(float(sample.h), float(lift.h), 1.0 - smoothstep(0.0, approach, away)))
			if away < 0.01: sample.bridge = true
		crossings.append({"p": lift.p, "s": lift.s, "half": lift.half, "h": lift.h, "dir": lift.dir})

## Where two height rules meet (crossing ramps, the engineered urban profile, a depot), visible
## track could step. It never climbs or drops more steeply than MAX_GRADE: the low side is
## raised into a ramp on an embankment, never cut, and never into a road deck's headroom.
## Buried and tunnel track keeps its own.
static func _limit_grade(samples: Array, roads: Array = [], road_index: Dictionary = {}, half_width: float = HALF) -> void:
	# A ramp never rises into the headroom of a road deck above the track.
	var ceilings := PackedFloat32Array(); ceilings.resize(samples.size())
	for i in samples.size():
		ceilings[i] = INF
		var p: Vector2 = samples[i].p
		for road_id in (range(roads.size()) if road_index.is_empty() else Index.query(road_index, Rect2(p, Vector2.ZERO).grow(half_width + 12.0))):
			var road: Dictionary = roads[road_id]
			if not road.has("ha"): continue
			var q := Geometry2D.get_closest_point_to_segment(p, road.a, road.b)
			if q.distance_to(p) > half_width + float(road.get("half", 4.0)): continue
			var road_h := lerpf(float(road.ha), float(road.hb), q.distance_to(road.a) / maxf(0.01, (road.a as Vector2).distance_to(road.b)))
			if road_h > float(samples[i].h) + 2.0: ceilings[i] = minf(ceilings[i], road_h - CLEARANCE - DECK_DEPTH - 0.25)
	for forward in [true, false]:
		var order: Array = range(1, samples.size()) if forward else range(samples.size() - 2, -1, -1)
		for i in order:
			var previous: Dictionary = samples[i - 1 if forward else i + 1]
			var sample: Dictionary = samples[i]
			if sample.hidden or previous.hidden: continue
			var run := absf(float(sample.s) - float(previous.s))
			sample.h = maxf(float(sample.h), minf(float(previous.h) - MAX_GRADE * run, ceilings[i]))

static func _v(p: Vector2, h: float, origin: Vector2) -> Vector3:
	return Vector3(p.x - origin.x, h, p.y - origin.y)

static func _strip(batch: RefCounted, a: Dictionary, b: Dictionary, offset: float, width: float, lift: float, color: Color, origin: Vector2) -> void:
	var na: Vector2 = a.dir.orthogonal(); var nb: Vector2 = b.dir.orthogonal()
	batch.quad(_v(a.p + na * (offset - width * 0.5), a.h + lift, origin),
		_v(b.p + nb * (offset - width * 0.5), b.h + lift, origin),
		_v(b.p + nb * (offset + width * 0.5), b.h + lift, origin),
		_v(a.p + na * (offset + width * 0.5), a.h + lift, origin), color)

static func build(lines: Array, roads: Array, height: Callable, level_at: Callable, origin := Vector2.ZERO, cap_ends := true, earth_color: Callable = Callable(), crossing_height: Callable = Callable(), terrain_height: Callable = Callable(), context: Dictionary = {}) -> Dictionary:
	var soil_height: Callable = terrain_height if terrain_height.is_valid() else height
	var plan: Dictionary = network(lines, true)
	var burial: Callable = context.get("burial",Callable())
	var rail_profile: Callable = context.get("rail_profile",Callable())
	var bed := Geo.Batch.new(); var fittings := Geo.Batch.new()
	var overview := Geo.Batch.new()
	var profiles: Array = []
	var portals: Array = []
	var sleepers := {}
	var visible_segments := 0
	# One elevation envelope spans edge, curve and turnout boundaries. A bridge
	# must not reset to ground where one reusable track piece joins another.
	var shared_crossings: Array = []
	var crossing_keys := {}
	var road_index := Index.segments(roads, 0.01)
	for path in plan.paths:
		for crossing in profile(path.points, roads, height, level_at, [], HALF + 0.8, road_index, {}, true, crossing_height, burial, rail_profile).crossings:
			var key := Vector2i((crossing.p as Vector2).round())
			if crossing_keys.has(key): continue
			crossing_keys[key] = true; shared_crossings.append(crossing)
	var crossing_index := {}
	for i in shared_crossings.size():
		Index.insert(crossing_index, Rect2(shared_crossings[i].p, Vector2.ZERO).grow(APPROACH + shared_crossings[i].half), i)
	var tunnels := _tunnel_profiles(plan,roads,height,level_at,shared_crossings,road_index,crossing_index,crossing_height,burial,rail_profile)
	var river: Callable = context.get("river",Callable())
	var river_spans: Array = _river_spans(tunnels.profiles, river, roads, road_index)
	for path in plan.paths:
		var prof := profile(path.points, roads, height, level_at, shared_crossings, HALF + 0.8, road_index, crossing_index, false, crossing_height, burial, rail_profile)
		var shared: Array=tunnels.profiles[path.pair_id].samples
		for i in prof.samples.size():
			# One datum and one cutoff for both tracks and the full-width portal.
			prof.samples[i].hidden=shared[i].hidden
			prof.samples[i].h=shared[i].h
			prof.samples[i].bridge=shared[i].bridge
			prof.samples[i].river=shared[i].get("river",false)
		profiles.append(prof)
	var height_index := {}
	for prof in profiles:
		for sample in prof.samples:
			var cell := Vector2i((sample.p / 4.0).floor())
			height_index[cell] = maxf(float(height_index.get(cell, -INF)), float(sample.h))
	var frogs := _flangeways(profiles)
	for path_index in plan.paths.size():
		var path: Dictionary = plan.paths[path_index]
		var prof: Dictionary = profiles[path_index]
		var pts: Array = prof.samples
		for i in range(1, pts.size()):
			var a: Dictionary = pts[i - 1]; var b: Dictionary = pts[i]
			if a.hidden or b.hidden: continue
			visible_segments += 1
			_strip(bed, a, b, 0, HALF * 2, 0, BALLAST, origin)
			# At medium/far zoom the running heads and sleepers are subpixel.
			# A continuous, low-contrast track band keeps the paired railway legible
			# without bright dots and moire. Full steel/switchwork returns up close.
			_strip(overview, a, b, 0, GAUGE + 0.8, 0.85, Color("69716b"), origin)
			# Sloped ballast embankments carry the approaches; track cannot float.
			if not a.bridge and not b.bridge:
				var ga := float(height.call(a.p)); var gb := float(height.call(b.p))
				if maxf(float(a.h) - ga, float(b.h) - gb) > 1.8:
					for sign_v in [-1.0, 1.0]:
						var na: Vector2 = a.dir.orthogonal() * sign_v; var nb: Vector2 = b.dir.orthogonal() * sign_v
						var foot_a: Vector2 = a.p + na * (HALF + (float(a.h) - ga) * 0.8)
						var foot_b: Vector2 = b.p + nb * (HALF + (float(b.h) - gb) * 0.8)
						if float(level_at.call(foot_a)) < TUNNEL_LEVEL and float(level_at.call(foot_b)) < TUNNEL_LEVEL:
							var low_a := _v(foot_a, float(soil_height.call(foot_a)) + 0.15, origin)
							var low_b := _v(foot_b, float(soil_height.call(foot_b)) + 0.15, origin)
							var high_a := _v(a.p + na * HALF, a.h, origin)
							var high_b := _v(b.p + nb * HALF, b.h, origin)
							# Exposed fill follows the terrain's elevation palette. Sample
							# vertically too, so a raised bank does not use one grey wall.
							for strip in 4:
								var lo := float(strip)/4.0; var hi := float(strip+1)/4.0
								var at := (low_a.lerp(high_a,(lo+hi)*0.5)+low_b.lerp(high_b,(lo+hi)*0.5))*0.5
								var color: Color = earth_color.call(at.y) if earth_color.is_valid() else Color("a48b60")
								bed.quad(low_a.lerp(high_a,lo),low_b.lerp(high_b,lo),low_b.lerp(high_b,hi),low_a.lerp(high_a,hi),color)
			for sign_v in [-1.0, 1.0]:
				var gaps: Array = frogs.gaps.get(_rail_id(path_index, i, sign_v), [])
				var cuts: Array = [0.0, 1.0]
				for gap in gaps: cuts.append(gap.x); cuts.append(gap.y)
				cuts.sort()
				for k in range(1, cuts.size()):
					var middle: float = (cuts[k - 1] + cuts[k]) * 0.5
					var skip := false
					for gap in gaps:
						if middle >= gap.x and middle <= gap.y: skip = true
					if skip: continue
					var left := _lerp_sample(a, b, cuts[k - 1]); var right := _lerp_sample(a, b, cuts[k])
					_strip(fittings, left, right, sign_v * GAUGE * 0.5, 0.95 * WIDTH_SCALE, 0.8, WEB, origin)
					_strip(fittings, left, right, sign_v * GAUGE * 0.5, 0.48 * WIDTH_SCALE, 1.25, STEEL, origin)
			if a.get("river", false) and b.get("river", false):
				# The deck under each track; the truss and its slab are drawn per corridor.
				_strip(bed, a, b, 0, HALF * 2 + 3.5, -0.5, CONCRETE, origin)
			elif a.bridge or b.bridge:
				# Over a road: a plain concrete deck with low parapets.
				_strip(bed, a, b, 0, HALF * 2 + 3.5, -0.5, CONCRETE, origin)
				for sign_v in [-1.0, 1.0]:
					var n: Vector2 = a.dir.orthogonal() * sign_v * (HALF + 1.0)
					var m: Vector2 = b.dir.orthogonal() * sign_v * (HALF + 1.0)
					bed.quad(_v(a.p + n, a.h - DECK_DEPTH, origin), _v(b.p + m, b.h - DECK_DEPTH, origin), _v(b.p + m, b.h + 1.0, origin), _v(a.p + n, a.h + 1.0, origin), CONCRETE_FACE)
			# Fixed arc-length spacing; no pile of sleepers at every curve subdivision.
			var station := ceilf(float(a.s) / 6.0) * 6.0
			if station >= float(b.s): continue
			var t := (station - float(a.s)) / maxf(0.001, float(b.s) - float(a.s))
			var p: Vector2 = a.p.lerp(b.p, t)
			var sk := Vector2i((p / 2.0).round())
			if sleepers.has(sk): continue
			sleepers[sk] = true
			var h := lerpf(float(a.h), float(b.h), t) + 0.3
			var u: Vector2 = (b.p - a.p).normalized() * 0.70
			var n: Vector2 = u.normalized().orthogonal() * 4.3 * WIDTH_SCALE
			fittings.quad(_v(p - n - u, h, origin), _v(p + n - u, h, origin), _v(p + n + u, h, origin), _v(p - n + u, h, origin), Color("665747") if int(path.level) == 1 else CONCRETE)
			if int(path.level) == 3:
				for sign_v in [-1.0, 1.0]:
					fittings.box(_v(p + n.normalized() * (GAUGE * 0.5 + 0.6) * sign_v, h + 0.35, origin), Vector3(0.65,0.4,1.1), WEB)
		for c in prof.crossings:
			for sign_v in [-1.0, 1.0]:
				var p: Vector2 = c.p + c.dir * (float(c.half) + 5.0) * sign_v
				if float(level_at.call(p)) >= TUNNEL_LEVEL: continue
				var base := float(height.call(p))
				bed.box(_v(p, (base + float(c.h) - DECK_DEPTH) * 0.5, origin), Vector3(2.4, maxf(1, float(c.h) - DECK_DEPTH - base), 2.4), CONCRETE)
	for span in river_spans: _truss_bridge(bed, span, origin, soil_height)
	for frog in frogs.guards:
		if not _clear(frog.p, level_at, 5.0): continue
		var n: Vector2 = frog.dir.orthogonal() * 0.9
		fittings.tube(_v(frog.p - frog.dir * 3.5 + n, frog.h + 1.05, origin),
			_v(frog.p + frog.dir * 3.5 + n, frog.h + 1.05, origin), 0.17, WEB, 4)
	for prof in tunnels.profiles:
		for i in range(1,prof.samples.size()):
			var a: Dictionary=prof.samples[i-1]; var b: Dictionary=prof.samples[i]
			if a.hidden==b.hidden: continue
			var visible: Dictionary=a if not a.hidden else b
			var dir: Vector2=(b.p-a.p).normalized()*(1.0 if not a.hidden else -1.0)
			var portal := {"p":visible.p,"h":visible.h-0.2,"dir":dir,"half_width":CORRIDOR_WIDTH*0.5+0.55}
			var unique := true
			for old in portals:
				if old.p.distance_to(portal.p)<0.05 and old.dir.dot(dir)>0.99: unique=false
			if unique: portals.append(portal)
	var track_vertex_count := bed.vertices.size()
	for portal in portals:
		preload("res://scripts/supply_chain_3d/tunnel_portal.gd").append(bed,portal,origin,soil_height,earth_color)
	for switch in plan.switches:
		if _covered_fitting(switch.p,tunnels.covered_ports,portals,18): continue
		if not _clear(switch.p, level_at, 17.0) or (burial.is_valid() and (burial.call(switch.p) as Vector2).y>0): continue
		var h := _plan_height(switch.p, height_index, height)
		if rail_profile.is_valid():
			var engineered: Vector3=rail_profile.call(switch.p)
			if engineered.z>0: h=engineered.x
		var n: Vector2 = switch.dir.orthogonal() * float(switch.get("actuator_side", 1.0))
		fittings.box(_v(switch.p + n * 8.5 * WIDTH_SCALE, h + 1.4, origin), Vector3(3.4, 2.4, 2.7) * WIDTH_SCALE, Color("d0aa45"))
		fittings.tube(_v(switch.p + n * 2, h + 0.9, origin), _v(switch.p + n * 8.5 * WIDTH_SCALE, h + 0.9, origin), 0.22, WEB, 4)
		# Tapered point blades join the stock rails over a long, shallow lead.
		for sign_v in [-1.0, 1.0]:
			fittings.tube(_v(switch.p + n * GAUGE * 0.5 * sign_v, h + 1.3, origin),
				_v(switch.p + switch.dir * 14.0 + n * (GAUGE * 0.5 - 0.55) * sign_v, h + 1.3, origin), 0.13, STEEL, 4)
	for buffer in (plan.buffers if cap_ends else []):
		if _covered_fitting(buffer.p,tunnels.covered_ports,portals,6): continue
		if not _clear(buffer.p, level_at, 6.0) or (burial.is_valid() and (burial.call(buffer.p) as Vector2).y>0): continue
		var h := _plan_height(buffer.p, height_index, height)
		if rail_profile.is_valid():
			var engineered: Vector3=rail_profile.call(buffer.p)
			if engineered.z>0: h=engineered.x
		var n: Vector2 = buffer.dir.orthogonal() * 4.2 * WIDTH_SCALE
		fittings.tube(_v(buffer.p - n, h + 3.3, origin), _v(buffer.p + n, h + 3.3, origin), 0.85, Color("a9694e"), 4)
		for sign_v in [-1, 1]: fittings.tube(_v(buffer.p + n * sign_v, h, origin), _v(buffer.p + n * sign_v, h + 3.3, origin), 0.6, WEB, 4)
	return {"bed": bed.mesh(), "overview": overview.mesh(), "detail": fittings.mesh(), "plan": plan, "profiles": profiles, "portals": portals, "visible_segments": visible_segments, "flangeways": frogs.gaps.size(), "track_vertex_count":track_vertex_count, "corridor_profiles":tunnels.profiles, "river_bridges": river_spans.size()}

## Cover a whole junction when its switchwork meets a mountain/urban bore.
## Portals then sit on the two-track approaches, before any fan of movements.
static func _tunnel_profiles(plan: Dictionary, roads: Array, height: Callable, level_at: Callable, crossings: Array, road_index: Dictionary, crossing_index: Dictionary, crossing_height: Callable, burial: Callable, rail_profile: Callable = Callable()) -> Dictionary:
	var profiles: Array=[]; var junctions := {}; var covered_ports := {}
	for corridor in plan.corridors:
		var prof := profile(corridor.points,roads,height,level_at,crossings,CORRIDOR_WIDTH*0.5+0.8,road_index,crossing_index,false,crossing_height,burial,rail_profile)
		profiles.append(prof)
		if corridor.has("junction") and prof.samples.any(func(s): return s.hidden): junctions[corridor.junction]=true
	if rail_profile.is_valid(): return {"profiles":profiles,"covered_ports":covered_ports}
	for i in plan.corridors.size():
		var corridor: Dictionary=plan.corridors[i]
		if not corridor.has("junction") or not junctions.has(corridor.junction): continue
		for sample in profiles[i].samples: sample.hidden=true
		for p in [corridor.points[0],corridor.points[-1]]: covered_ports[_key(p)]=p
	for i in plan.corridors.size():
		var samples: Array=profiles[i].samples
		for end in [0,samples.size()-1]:
			if covered_ports.has(_key(samples[end].p)): samples[end].hidden=true
	_merge_tunnel_daylight(profiles)
	return {"profiles":profiles,"covered_ports":covered_ports}

## Treat the sampled corridors as one graph, including their shared endpoints.
## Short daylight windows between bores cannot accommodate two portal collars;
## keep them covered rather than drawing an isolated length of track.
static func _merge_tunnel_daylight(profiles: Array) -> void:
	var nodes := {}
	for prof in profiles:
		var previous := Vector2i.ZERO
		for i in prof.samples.size():
			var sample: Dictionary=prof.samples[i]; var key := _key(sample.p)
			var node: Dictionary=nodes.get_or_add(key,{"p":sample.p,"hidden":false,"samples":[],"edges":{}})
			node.samples.append(sample); node.hidden=node.hidden or sample.hidden
			if i>0 and previous!=key:
				node.edges[previous]=true; nodes[previous].edges[key]=true
			previous=key
	var seen := {}
	for first in nodes:
		if nodes[first].hidden or seen.has(first): continue
		var queue: Array=[first]; var component: Array=[]; var cursor := 0
		var length := 0.0; var boundary := false; var terminal := false
		seen[first]=true
		while cursor<queue.size():
			var key: Vector2i=queue[cursor]; cursor+=1
			var node: Dictionary=nodes[key]; component.append(key)
			terminal=terminal or node.edges.size()<2
			for other in node.edges:
				if nodes[other].hidden: boundary=true; continue
				length+=node.p.distance_to(nodes[other].p)*0.5
				if not seen.has(other): seen[other]=true; queue.append(other)
		if boundary and not terminal and length<54.0:
			for key in component: nodes[key].hidden=true
	for node in nodes.values():
		for sample in node.samples: sample.hidden=node.hidden

static func _covered_fitting(p: Vector2, covered_ports: Dictionary, portals: Array, reach: float) -> bool:
	for q in covered_ports.values():
		if p.distance_to(q)<reach+CORRIDOR_WIDTH: return true
	for portal in portals:
		var delta: Vector2=p-portal.p
		if absf(delta.dot(portal.dir.orthogonal()))<CORRIDOR_WIDTH and delta.dot(portal.dir)>-reach and delta.length()<reach+24: return true
	return false

static func _plan_height(p: Vector2, heights: Dictionary, height: Callable) -> float:
	var h := float(height.call(p)) + 1.2
	var cell := Vector2i((p / 4.0).floor())
	for y in range(-1, 2):
		for x in range(-1, 2): h = maxf(h, float(heights.get(cell + Vector2i(x,y), h)))
	return h

static func _portal(batch: RefCounted, portal: Dictionary, origin: Vector2) -> void:
	preload("res://scripts/supply_chain_3d/tunnel_portal.gd").append(batch,portal,origin,func(_p): return float(portal.h)-1.0)

static func append_mesh(batch: RefCounted, mesh: ArrayMesh) -> void:
	if mesh.get_surface_count() == 0: return
	var arrays := mesh.surface_get_arrays(0)
	batch.vertices.append_array(arrays[Mesh.ARRAY_VERTEX])
	batch.normals.append_array(arrays[Mesh.ARRAY_NORMAL])
	batch.colors.append_array(arrays[Mesh.ARRAY_COLOR])

static func _rail_id(path: int, segment: int, side: float) -> String:
	return "%d:%d:%d" % [path, segment, int(side)]

static func _lerp_sample(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	return {"p": (a.p as Vector2).lerp(b.p, t), "h": lerpf(a.h, b.h, t), "dir": (a.dir as Vector2).lerp(b.dir, t).normalized()}

## Intersect running RAILS, not track centrelines. Leave an actual flangeway at
## each frog, with a short check rail; do not overlap solid steel at crossings.
static func _flangeways(profiles: Array) -> Dictionary:
	var buckets := {}; var gaps := {}; var guards: Array = []; var compared := {}
	for j in profiles.size():
		var pts: Array = profiles[j].samples
		for i in range(1, pts.size()):
			var a: Dictionary = pts[i - 1]; var b: Dictionary = pts[i]
			if a.hidden or b.hidden: continue
			for side in [-1.0, 1.0]:
				var start: Vector2 = a.p + a.dir.orthogonal() * GAUGE * 0.5 * side
				var end: Vector2 = b.p + b.dir.orthogonal() * GAUGE * 0.5 * side
				var id := _rail_id(j, i, side)
				var rec := {"a": start, "b": end, "id": id, "path": j, "h": (float(a.h) + float(b.h)) * 0.5}
				var area := Rect2(start, Vector2.ZERO).expand(end).grow(1.0)
				var lo := Vector2i((area.position / 24.0).floor()); var hi := Vector2i((area.end / 24.0).floor())
				for y in range(lo.y, hi.y + 1):
					for x in range(lo.x, hi.x + 1):
						var bucket: Array = buckets.get_or_add(Vector2i(x, y), [])
						for other in bucket:
							if other.path == j: continue
							var pair := id + "|" + str(other.id)
							if compared.has(pair): continue
							compared[pair] = true
							if absf((end - start).normalized().cross((other.b - other.a).normalized())) < 0.12: continue
							var hit: Variant = Geometry2D.segment_intersects_segment(start, end, other.a, other.b)
							if hit == null: continue
							for segment in [rec, other]:
								var length: float = segment.a.distance_to(segment.b)
								if length < 0.01: continue
								var t: float = segment.a.distance_to(hit) / length
								(gaps.get_or_add(segment.id, []) as Array).append(Vector2(maxf(0, t - 0.45 / length), minf(1, t + 0.45 / length)))
								guards.append({"p": hit, "h": segment.h, "dir": (segment.b - segment.a).normalized()})
						bucket.append(rec)
	return {"gaps": gaps, "guards": guards}

static func _clear(p: Vector2, level_at: Callable, radius: float) -> bool:
	if float(level_at.call(p)) >= TUNNEL_LEVEL: return false
	for i in 8:
		if float(level_at.call(p + Vector2.RIGHT.rotated(i * PI / 4.0) * radius)) >= TUNNEL_LEVEL: return false
	return true

## Runs of corridor samples over a river (plus RIVER_PAD of bank either side) are bridges:
## they take no embankment, and draw a truss. A run reaches on past any road passing under its
## end, so the abutment stands clear of the road. Returns one span per run, with the roads that
## pass under it (its piers keep off them).
static func _river_spans(profiles: Array, river: Callable, roads: Array = [], road_index: Dictionary = {}) -> Array:
	var spans: Array = []
	if not river.is_valid(): return spans
	for prof in profiles:
		var samples: Array = prof.samples
		var on := PackedByteArray(); on.resize(samples.size())
		for i in samples.size():
			if samples[i].hidden or not bool(river.call(samples[i].p, 2.0)): continue
			var j := i
			while j > 0 and float(samples[i].s) - float(samples[j - 1].s) <= RIVER_PAD and not samples[j - 1].hidden: j -= 1
			var k := i
			while k < samples.size() - 1 and float(samples[k + 1].s) - float(samples[i].s) <= RIVER_PAD and not samples[k + 1].hidden: k += 1
			for m in range(j, k + 1): on[m] = 1
		var runs: Array = []
		var start := -1
		for i in samples.size() + 1:
			var inside := i < samples.size() and on[i] == 1
			if inside and start < 0: start = i
			if not inside and start >= 0:
				if i - start >= 2: runs.append([start, i - 1])
				start = -1
		for run in runs:
			for side in [0, 1]:
				var edge: int = run[side]
				var step := -1 if side == 0 else 1
				for reach in ABUTMENT_REACH:
					if _under(samples[edge], roads, road_index, TRUSS_OFFSET + 3.6).is_empty(): break
					var next := edge + step
					if next < 0 or next >= samples.size() or samples[next].hidden: break
					edge = next
				run[side] = edge
			for m in range(run[0], run[1] + 1):
				samples[m].bridge = true; samples[m].river = true
			var span_samples: Array = samples.slice(run[0], run[1] + 1)
			var under: Array = []
			for q in span_samples:
				for road in _under(q, roads, road_index, TRUSS_OFFSET + 40.0):
					if not under.has(road): under.append(road)
			spans.append({"samples": span_samples, "roads": under})
	return spans

## Roads within `reach` of a track sample that pass under its deck (with a road's headroom).
static func _under(sample: Dictionary, roads: Array, road_index: Dictionary, reach: float) -> Array:
	var found: Array = []
	var p: Vector2 = sample.p
	var ids: Array = range(roads.size()) if road_index.is_empty() else Index.query(road_index, Rect2(p, Vector2.ZERO).grow(reach + 12.0))
	for i in ids:
		var road: Dictionary = roads[i]
		if road.get("tunnel", false) or not road.has("ha"): continue
		var q := Geometry2D.get_closest_point_to_segment(p, road.a, road.b)
		var half := float(road.get("half", 4.0))
		if q.distance_to(p) > reach + half: continue
		var t := q.distance_to(road.a) / maxf(0.01, (road.a as Vector2).distance_to(road.b))
		if lerpf(float(road.ha), float(road.hb), t) > float(sample.h) - DECK_DEPTH - 0.6 - ROAD_HEADROOM: continue
		found.append(road)
	return found

## A box standing on `p`, long axis along `dir`.
static func _block(batch: RefCounted, p: Vector2, dir: Vector2, half_length: float, half_width: float, z0: float, z1: float, color: Color, origin: Vector2) -> void:
	var n := dir.orthogonal()
	var c := [p - dir * half_length - n * half_width, p + dir * half_length - n * half_width,
		p + dir * half_length + n * half_width, p - dir * half_length + n * half_width]
	for i in 4:
		var a: Vector2 = c[i]; var b: Vector2 = c[(i + 1) % 4]
		batch.quad(_v(a, z0, origin), _v(b, z0, origin), _v(b, z1, origin), _v(a, z1, origin), color)
	batch.quad(_v(c[0], z1, origin), _v(c[1], z1, origin), _v(c[2], z1, origin), _v(c[3], z1, origin), color)

static func _span_sample(samples: Array, s: float) -> Dictionary:
	for i in range(1, samples.size()):
		if float(samples[i].s) >= s:
			var t := (s - float(samples[i - 1].s)) / maxf(0.001, float(samples[i].s) - float(samples[i - 1].s))
			return _lerp_sample(samples[i - 1], samples[i], clampf(t, 0.0, 1.0))
	return samples[-1]

## A double-track through truss: concrete deck slab, two Pratt trusses with inclined end
## posts, top lateral struts, concrete abutments at both banks and piers in the water.
static func _truss_bridge(batch: RefCounted, span: Dictionary, origin: Vector2, ground: Callable) -> void:
	var samples: Array = span.samples
	var s0 := float(samples[0].s); var s1 := float(samples[-1].s)
	var length := s1 - s0
	if length < 6.0: return
	# Deck slab under both tracks, with concrete fascias.
	for i in range(1, samples.size()):
		var a: Dictionary = samples[i - 1]; var b: Dictionary = samples[i]
		var na: Vector2 = a.dir.orthogonal() * TRUSS_OFFSET; var nb: Vector2 = b.dir.orthogonal() * TRUSS_OFFSET
		for sign_v in [-1.0, 1.0]:
			batch.quad(_v(a.p + na * sign_v, a.h - DECK_DEPTH - 0.6, origin), _v(b.p + nb * sign_v, b.h - DECK_DEPTH - 0.6, origin),
				_v(b.p + nb * sign_v, b.h + 0.2, origin), _v(a.p + na * sign_v, a.h + 0.2, origin), CONCRETE_FACE)
		batch.quad(_v(a.p - na, a.h - DECK_DEPTH - 0.6, origin), _v(b.p - nb, b.h - DECK_DEPTH - 0.6, origin),
			_v(b.p + nb, b.h - DECK_DEPTH - 0.6, origin), _v(a.p + na, a.h - DECK_DEPTH - 0.6, origin), CONCRETE_FACE)
	# Panel points: an even number of panels, at least two.
	var panels := maxi(2, int(round(length / TRUSS_PANEL / 2.0)) * 2)
	var points: Array = []
	for k in panels + 1: points.append(_span_sample(samples, s0 + length * float(k) / panels))
	for sign_v in [-1.0, 1.0]:
		var low: Array = []; var high: Array = []
		for q in points:
			var n: Vector2 = (q.dir as Vector2).orthogonal() * TRUSS_OFFSET * sign_v
			low.append(_v(q.p + n, float(q.h) + 0.3, origin))
			high.append(_v(q.p + n, float(q.h) + TRUSS_HEIGHT, origin))
		for k in panels: batch.tube(low[k], low[k + 1], 0.42, TRUSS, 4)          # bottom chord
		for k in range(1, panels - 1): batch.tube(high[k], high[k + 1], 0.48, TRUSS, 4)  # top chord
		batch.tube(low[0], high[1], 0.48, TRUSS, 4)                                  # end posts
		batch.tube(low[panels], high[panels - 1], 0.48, TRUSS, 4)
		for k in range(1, panels): batch.tube(low[k], high[k], 0.28, TRUSS, 4)       # verticals
		var middle := panels / 2
		for k in range(1, panels - 1):
			# Pratt: diagonals fall toward mid-span.
			if k < middle: batch.tube(high[k], low[k + 1], 0.24, TRUSS, 4)
			else: batch.tube(low[k], high[k + 1], 0.24, TRUSS, 4)
	# Top lateral struts between the two trusses.
	for k in range(1, panels):
		if k % 2 == 1 or k == panels - 1:
			var q: Dictionary = points[k]; var n: Vector2 = (q.dir as Vector2).orthogonal() * TRUSS_OFFSET
			batch.tube(_v(q.p - n, float(q.h) + TRUSS_HEIGHT, origin), _v(q.p + n, float(q.h) + TRUSS_HEIGHT, origin), 0.26, TRUSS, 4)
	# Concrete abutments at both banks, piers in between at most PIER_SPACING apart.
	for end in [samples[0], samples[-1]]:
		var base := float(ground.call(end.p)) - 2.0
		_block(batch, end.p, end.dir, 2.2, TRUSS_OFFSET + 1.4, base, float(end.h) - DECK_DEPTH - 0.6, CONCRETE, origin)
	var piers := int(floor(length / PIER_SPACING))
	for k in range(1, piers + 1):
		var station := s0 + length * float(k) / (piers + 1)
		# A pier keeps off any road passing under the span: moved along it, or left out.
		var q := {}
		for offset in [0.0, -4.0, 4.0, -8.0, 8.0, -12.0, 12.0]:
			var candidate: Dictionary = _span_sample(samples, clampf(station + offset, s0 + 4.0, s1 - 4.0))
			if _clear_of_roads(candidate.p, span.get("roads", []), TRUSS_OFFSET + 1.6): q = candidate; break
		if q.is_empty(): continue
		var base := float(ground.call(q.p)) - 3.0
		_block(batch, q.p, q.dir, 1.4, TRUSS_OFFSET + 0.6, base, float(q.h) - DECK_DEPTH - 0.6, CONCRETE, origin)

static func _clear_of_roads(p: Vector2, roads: Array, reach: float) -> bool:
	for road in roads:
		if Geometry2D.get_closest_point_to_segment(p, road.a, road.b).distance_to(p) < reach + float(road.get("half", 4.0)): return false
	return true
