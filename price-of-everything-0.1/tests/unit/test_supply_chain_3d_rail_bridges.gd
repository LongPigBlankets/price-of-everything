extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Rail := preload("res://scripts/supply_chain_3d/railway.gd")
const Elevation := preload("res://scripts/supply_chain_3d/rail_elevation.gd")
const Network := preload("res://scripts/supply_chain_3d/rail_network.gd")
const Grade := preload("res://scripts/supply_chain_3d/road_grade.gd")
const Urban := preload("res://scripts/supply_chain_3d/rail_urban.gd")
const Crossing := preload("res://scripts/supply_chain_3d/rail_crossings.gd")
const Index := preload("res://scripts/supply_chain_3d/road_index.gd")

func _line() -> Array:
	return [{"mode":"rails","level":2,"pts":[{"p":Vector2(-500,0)},{"p":Vector2(500,0)}]}]

## A covered bore for x < 0 and a river at x = 40..60: the old approach dug through it.
func _test_rail_bridges_river_stays_at_grade_beside_a_bore() -> void:
	var plan := Rail.network(_line())
	var wet := func(p: Vector2) -> bool: return p.x > 40.0 and p.x < 60.0
	var solved := Elevation.solve(plan, func(_p): return 34.0, func(_p): return 1.0, func(p): return p.x < 0.0, func(_p): return INF, [], Callable(), wet)
	var over_water := INF; var shoulder := INF; var max_grade := 0.0
	for track in solved.tracks:
		var middle: float = (track.a.x + track.b.x) * 0.5
		if middle > 40.0 and middle < 60.0: over_water = minf(over_water, minf(track.ha, track.hb))
		for end in [[track.a, track.ha], [track.b, track.hb]]:
			if end[0].x >= 40.0 - Elevation.BRIDGE_SHOULDER and end[0].x <= 60.0 + Elevation.BRIDGE_SHOULDER: shoulder = minf(shoulder, end[1])
		if not track.hidden: max_grade = maxf(max_grade, absf(track.hb - track.ha) / track.a.distance_to(track.b))
	_check(is_equal_approx(over_water, 35.2), "Rail bridges: track over a river keeps its deck at grade instead of the bore's approach depth")
	_check(is_equal_approx(shoulder, 35.2), "Rail bridges: both abutments stay level beyond the water")
	_check(max_grade <= Elevation.RIVER_GRADE + 0.001, "Rail bridges: the climb from the bore to the bridge is no steeper than 12%")
	var plain := Elevation.solve(plan, func(_p): return 34.0, func(_p): return 1.0, func(p): return p.x < 0.0, func(_p): return INF)
	var deepest := INF
	for track in plain.tracks:
		if (track.a.x + track.b.x) * 0.5 > 40.0 and (track.a.x + track.b.x) * 0.5 < 60.0: deepest = minf(deepest, track.ha)
	_check(deepest < 30.0, "Rail bridges: without the river constraint the approach would lie below the river (the reported fault)")

func _test_rail_bridges_truss_over_rivers_concrete_over_roads() -> void:
	var flat := func(_p): return 34.0
	var low := func(_p): return 1.0
	var river := func(p: Vector2, margin: float) -> bool: return absf(p.x - 100.0) < 15.0 + margin
	var art := Rail.build(_line(), [], flat, low, Vector2.ZERO, true, Callable(), Callable(), Callable(), {"river": river})
	_check(int(art.river_bridges) >= 1, "Rail bridges: a river crossing becomes a truss span")
	var bridged := true
	for prof in art.profiles:
		for sample in prof.samples:
			if absf(sample.p.x - 100.0) < 15.0 and not (sample.bridge and sample.river): bridged = false
	_check(bridged, "Rail bridges: every track sample over the water stands on the bridge deck")
	var dry := Rail.build(_line(), [], flat, low, Vector2.ZERO, true, Callable(), Callable(), Callable(), {"river": func(_p, _m): return false})
	_check(int(dry.river_bridges) == 0, "Rail bridges: no river, no truss")
	var colours := {}
	var arrays: Array = art.bed.surface_get_arrays(0)
	for c in arrays[Mesh.ARRAY_COLOR]: colours[(c as Color).to_html(false)] = true
	_check(colours.has(Rail.TRUSS.to_html(false)) and colours.has(Rail.CONCRETE.to_html(false)), "Rail bridges: the river span draws steel truss members on concrete supports")
	var roads := [{"a": Vector2(-150, -200), "b": Vector2(-150, 200), "level": 1}]
	var over_road := Rail.build(_line(), roads, flat, low)
	var road_colours := {}
	for c in over_road.bed.surface_get_arrays(0)[Mesh.ARRAY_COLOR]: road_colours[(c as Color).to_html(false)] = true
	_check(road_colours.has(Rail.CONCRETE_FACE.to_html(false)) and not road_colours.has(Rail.GIRDER.to_html(false)), "Rail bridges: over a road the deck is plain concrete")

func _test_rail_bridges_routing_crosses_a_meander_once() -> void:
	# A river meanders across the straight route between two anchors three times.
	var meander := PackedVector2Array()
	for i in 41:
		var x := -400.0 + 20.0 * i
		meander.append(Vector2(x, 60.0 * sin(x / 70.0)))
	var rivers: Array = []
	for i in range(1, meander.size()): rivers.append({"a": meander[i - 1], "b": meander[i]})
	var index := Index.segments(rivers, 0.01)
	_check(Network.river_crossings(PackedVector2Array([Vector2(0, -300), Vector2(0, 300)]), rivers, index) == 1, "Rail routing: a straight cut through the river counts one crossing")
	_check(Network.river_crossings(PackedVector2Array([Vector2(-400, 0), Vector2(400, 0)]), rivers, index) >= 3, "Rail routing: a line along the meander counts every crossing")
	var tiles := {"tile_a": {"center": Vector2(-480, 0), "type": "rural", "neighbours": ["tile_b"]},
		"tile_b": {"center": Vector2(480, 0), "type": "rural", "neighbours": ["tile_a"]}}
	var plan := Network.create(tiles, [], 7, Callable(), rivers)
	var points := PackedVector2Array()
	for q in plan.lines[0].pts: points.append(q.p)
	_check(Network.river_crossings(points, rivers, index) <= 1, "Rail routing: the chosen route crosses the meander at most once")

func _test_rail_bridges_crossing_mix_for_quiet_and_busy_roads() -> void:
	var lines := [{"mode":"rails","level":2,"pts":[{"p":Vector2(-700,0)},{"p":Vector2(700,0)}]}]
	var roads := [{"a":Vector2(-200,-300),"b":Vector2(-200,300),"level":1,"tile":"tile_5_9","source":"lane","widths":[3.0,2.8,2.6,2.4]},
		{"a":Vector2(200,-300),"b":Vector2(200,300),"level":2,"tile":"tile_5_9","source":"avenue","widths":[6.0,5.6,5.2,4.8]}]
	var grade := Grade.new(); grade.configure(roads, func(_p): return 34.0)
	var plan := Rail.network(lines); var urban := Urban.new()
	# The yard is 500u of track away: an approach, but not its throat.
	var yards: Array = [{"pos": Vector2(-850, 0), "yaw": 0.0}]
	urban.configure({}, [], [], plan, yards, func(_p): return 34.0, func(_p): return 1.0)
	Crossing.build(grade, plan, urban, yards)
	var modes := {}
	for c in grade.crossings: modes[str(c.sources[0])] = str(c.mode)
	_check(modes.get("lane", "") == "level", "Crossings: a two-lane road on a depot approach crosses at level")
	_check(modes.get("avenue", "") == "rail_bridge", "Crossings: a four-lane road passes under a short rail bridge")
	var tagged := false
	for segment in grade.segments:
		if segment.get("source", "") == "avenue" and segment.has("rail_crossing_mode"): tagged = true
	_check(not tagged and grade.bridges.is_empty(), "Crossings: the four-lane road keeps its grade; the railway profile lifts the track instead")

func _test_rail_bridges_lane_crosses_a_junction_fan_at_level() -> void:
	# Three lines meet at the origin; a lane and an avenue both cut through the fan.
	var lines := [{"mode":"rails","level":2,"pts":[{"p":Vector2(-700,0)},{"p":Vector2(0,0)}]},
		{"mode":"rails","level":2,"pts":[{"p":Vector2(0,0)},{"p":Vector2(700,0)}]},
		{"mode":"rails","level":2,"pts":[{"p":Vector2(0,0)},{"p":Vector2(600,450)}]}]
	var plan := Rail.network(lines)
	_check(not plan.junctions.is_empty(), "Crossings: the three lines form a junction fan")
	if plan.junctions.is_empty(): return
	var reach: float = float(plan.junctions[0].get("radius", Rail.CURVE)) * 0.5
	var roads := [{"a":Vector2(-reach,-300),"b":Vector2(-reach,300),"level":1,"tile":"tile_5_9","source":"lane","widths":[3.0,2.8,2.6,2.4]},
		{"a":Vector2(reach,-300),"b":Vector2(reach,300),"level":2,"tile":"tile_5_9","source":"avenue","widths":[6.0,5.6,5.2,4.8]}]
	var grade := Grade.new(); grade.configure(roads, func(_p): return 34.0)
	var urban := Urban.new()
	urban.configure({}, [], [], plan, [], func(_p): return 34.0, func(_p): return 1.0)
	Crossing.build(grade, plan, urban, [])
	var modes := {}
	for c in grade.crossings: modes[str(c.sources[0])] = [str(c.mode), str(c.reason)]
	_check(modes.get("lane", [""])[0] == "level", "Crossings: a two-lane road crosses a junction fan at level")
	_check(modes.get("avenue", ["", ""]) == ["bridge", "rail junction movements"], "Crossings: a four-lane road still bridges a junction fan")

func _test_rail_bridges_anchor_keeps_its_junction_off_the_river() -> void:
	# The river runs straight through both tile centres, as rivers on this map do.
	var rivers: Array = [{"a": Vector2(-300, -600), "b": Vector2(-300, 600)}, {"a": Vector2(300, -600), "b": Vector2(300, 600)}]
	var tiles := {"tile_a": {"center": Vector2(-300, 0), "type": "rural", "neighbours": ["tile_b"]},
		"tile_b": {"center": Vector2(300, 0), "type": "rural", "neighbours": ["tile_a"]}}
	var plan := Network.create(tiles, [], 7, Callable(), rivers)
	var index := Index.segments(rivers, 0.01)
	for tid in plan.anchors:
		_check(Network.river_gap(plan.anchors[tid], rivers, index) >= Network.ANCHOR_RIVER_CLEARANCE - 0.5, "Rail routing: %s's junction stands clear of the river" % tid)

func _test_rail_bridges_hand_placed_vias_shape_the_line() -> void:
	var vias: Array = Network.LINE_VIAS["tile_5_10|tile_5_9"]
	var tiles := {"tile_5_9": {"center": Vector2(2700, 5040), "type": "urban", "neighbours": ["tile_5_10"]},
		"tile_5_10": {"center": Vector2(2700, 5520), "type": "urban", "neighbours": ["tile_5_9"]}}
	var plan := Network.create(tiles, [], 7)
	var points: Array = []
	for q in plan.lines[0].pts: points.append(q.p)
	var forward: bool = (points[0] as Vector2).distance_to(plan.anchors["tile_5_10"]) < 0.1
	var expected: Array = [plan.anchors["tile_5_10"]] + vias + [plan.anchors["tile_5_9"]]
	if not forward: expected.reverse()
	_check(points == expected, "Rail routing: the Fields line to tile_5_10 follows its via points in order")
	_check(plan.anchors["tile_5_9"] == Vector2(2700, 5040) + Network.ANCHOR_OFFSETS["tile_5_9"], "Rail routing: the Fields junction uses its hand-placed anchor")
