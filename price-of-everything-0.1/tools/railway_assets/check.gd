extends Node
const Rail := preload("res://scripts/supply_chain_3d/railway.gd")
const Builder := preload("res://scripts/supply_chain_3d/world_builder.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures += 1; push_error(message)
func route(points: Array, mode := "rail", level := 1) -> Dictionary:
	var pts: Array = []
	for p in points: pts.append({"p": p, "tile": "test", "edge": false})
	return {"mode": mode, "pts": pts, "level": level}
func _ready() -> void:
	TelemetryState.enabled = false; SaveLoad.autosave_enabled = false
	var flat := func(_p: Vector2) -> float: return 0.0
	var low := func(_p: Vector2) -> float: return 2.0
	var straight := route([Vector2(-400, 0), Vector2(400, 0)])
	var art := Rail.build([straight], [], flat, low)
	check(art.bed.get_surface_count() == 1, "Legacy rail mode must produce track")
	check(Rail.network([straight, straight]).paths.size() == 2, "Duplicate routes must share one pair of tracks")
	check(Rail.is_rail("rails") and not Rail.is_rail("pipes"), "Rail mode aliases")
	var roads := [{"a": Vector2(0, -90), "b": Vector2(0, 90), "level": 3}]
	art = Rail.build([straight], roads, flat, low)
	var samples: Array = art.profiles[0].samples
	var top := 0.0
	var previous := 0.0
	for p in samples:
		top = maxf(top, p.h)
		check(absf(p.h - previous) < 3.0, "Bridge profile must rise continuously")
		previous = p.h
	check(top - Rail.DECK_DEPTH >= Rail.CLEARANCE, "Road clearance below deck")
	check(samples[0].h < 2 and samples[-1].h < 2, "Both bridge ramps return to grade")
	check(samples[samples.size()*7/16].h > samples[0].h and samples[samples.size()*9/16].h > samples[-1].h, "Raised ascent and descent")
	check(Rail.CLEARANCE < Rail.CORRIDOR_WIDTH, "Five-metre bridge clearance is slightly under two lanes wide")
	check(is_equal_approx(top,Rail.CLEARANCE+Rail.DECK_DEPTH), "No extra rise above required clearance and deck")
	var elevated_road := func(_p: Vector2) -> float: return 4.0
	var coloured := Rail.build([straight],roads,flat,low,Vector2.ZERO,false,func(h: float) -> Color: return Color.RED if h<5 else Color.YELLOW,elevated_road)
	check(is_equal_approx(coloured.profiles[0].crossings[0].h,4+Rail.CLEARANCE+Rail.DECK_DEPTH),"Crossing clearance follows the road, separately from the ground")
	var fill_colors: PackedColorArray = coloured.bed.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	check(fill_colors.has(Color.RED) and fill_colors.has(Color.YELLOW),"Earth slopes sample their own elevation colours")
	# Each painted upland band must have real geometry, particularly level 6.
	var Ground := preload("res://scripts/empire_board_ground.gd")
	var DisplayRelief := preload("res://scripts/supply_chain_3d/relief.gd")
	var previous_height := -INF
	for band in range(3,12):
		var ground := Ground.new()
		ground.tiles = {"test":{"center":Vector2.ZERO,"height":34.0,"water":false}}
		ground.bands = [{"b":band,"p":PackedVector2Array([Vector2(-180,-180),Vector2(180,-180),Vector2(180,180),Vector2(-180,180)])}]
		ground.may_be_wet = func(_p: Vector2) -> bool: return false
		ground.setup()
		var actual := ground.height(Vector2.ZERO)
		check(is_equal_approx(actual,Ground.Relief.band_level(band)),"Painted band %d has its own terrain plateau" % band)
		check(DisplayRelief.height(actual)>previous_height,"Successive upland levels visibly rise")
		previous_height = DisplayRelief.height(actual)
	var mountain := func(p: Vector2) -> float: return 6.0 if absf(p.x) < 80 else 5.0
	art = Rail.build([straight], [], flat, mountain)
	check(art.portals.size() == 2, "Entry and exit tunnel portals at height 6")
	for mesh in [art.bed, art.detail]:
		if mesh.get_surface_count() == 0: continue
		var vertices: PackedVector3Array=mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var count: int=art.track_vertex_count if mesh==art.bed else vertices.size()
		for i in count:
			var v := vertices[i]
			check(mountain.call(Vector2(v.x, v.z)) < 6, "No exposed railway geometry on height 6+")
	art = Rail.build([straight], [], flat, func(_p: Vector2) -> float: return 7.0)
	check(art.bed.get_surface_count() == 0 and art.detail.get_surface_count() == 0, "Entire high route is invisible")
	for arms in [3,4,5]:
		var lines := [route([Vector2(-220,0), Vector2(220,0)])]
		for k in range(arms - 2): lines.append(route([Vector2.ZERO, Vector2(0,220).rotated(k * TAU / maxf(2, arms-2))]))
		var net := Rail.network(lines)
		check(not net.switches.is_empty(), "Branches produce turnouts")
		for sw in net.switches: check(sw.degree <= 4, "No five-way railway junction")
		for path in net.paths:
			var pts: PackedVector2Array = path.points
			for i in range(2, pts.size()):
				var a := (pts[i-1] - pts[i-2]).normalized(); var b := (pts[i] - pts[i-1]).normalized()
				check(a.dot(b) > 0.9, "Track bends must not contain angular corners")
	# Every distinct arm pair has two direct curved/straight movements: 3 pairs
	# for a T junction, 6 for a four-way. No reversal through an unrelated arm.
	for count in [3,4]:
		var lines: Array = []
		var directions := [Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT,Vector2.UP]
		for i in count: lines.append(route([Vector2.ZERO,directions[i]*220]))
		var net := Rail.network(lines)
		check(net.junctions.size() == 1, "One railway junction")
		var junction: Dictionary = net.junctions[0]
		check(junction.movements.size() == count*(count-1)/2, "All arm pairs connect directly")
		for i in count:
			for j in range(i+1,count):
				var pair_paths: Array = net.paths.filter(func(p: Dictionary) -> bool: return p.get("movement",Vector2i(-1,-1)) == Vector2i(i,j))
				check(pair_paths.size() == 2, "Every junction movement has paired tracks")
		# Track offsets must meet the same ports on the approach and connector.
		var ends := {}
		for path in net.paths:
			for p in [path.points[0],path.points[-1]]:
				var key := Vector2i((p * 100).round())
				ends[key] = int(ends.get(key,0))+1
		for point in ends:
			if Vector2(point).length()/100 < 210:
				check(ends[point] >= 2, "Paired junction track must meet approach without gaps")
	var paired: Array = Rail.network([straight]).paths
	check(paired.size() == 2, "Two complete tracks on a straight route")
	for i in paired[0].points.size():
		check(is_equal_approx(paired[0].points[i].distance_to(paired[1].points[i]),Rail.TRACK_SPACING), "Paired tracks keep separate centres")
	# Exercise the real renderer dispatch, including its visibility toggle.
	var builder := Builder.new()
	builder.ground = preload("res://scripts/empire_board_ground.gd").new()
	builder.ground.tiles = {}; builder.ground.setup()
	var root := builder.infrastructure({"lines": [straight], "roads": []}, {"roads": false, "rails": true})
	check(root.get_child_count() >= 3, "Runtime infrastructure builds railway")
	var visible_count := vertices(root)
	root.free()
	root = builder.infrastructure({"lines": [straight], "roads": []}, {"roads": false, "rails": false})
	check(visible_count > vertices(root), "Runtime railway toggle hides rail and rails modes")
	root.free()
	var t_lines := [route([Vector2(-220,0),Vector2(220,0)]), route([Vector2.ZERO,Vector2(0,220)])]
	art = Rail.build(t_lines,[],flat,low)
	check(art.flangeways > 0, "Turnout frog has an actual gap between running rails")
	var junction_mountain := func(p: Vector2) -> float: return 6.0 if p.x>40 and p.x<160 else 5.0
	var tunnel_junction := Rail.build(t_lines,[],flat,junction_mountain)
	check(tunnel_junction.portals.size()==3,"Three-way mountain junction has one two-track portal on each approach")
	for i in tunnel_junction.plan.paths.size():
		var path: Dictionary=tunnel_junction.plan.paths[i]
		var samples_pair: Array=tunnel_junction.profiles[i].samples
		if path.has("junction"): check(samples_pair.all(func(p): return p.hidden),"Entire branching fan is inside the tunnel")
		var shared: Array=tunnel_junction.corridor_profiles[path.pair_id].samples
		for j in samples_pair.size():
			check(samples_pair[j].hidden==shared[j].hidden and samples_pair[j].h==shared[j].h,"Both tracks use one cutoff and height at the portal")
	for portal in tunnel_junction.portals:
		for prof in tunnel_junction.profiles:
			for sample in prof.samples:
				var d: Vector2=sample.p-portal.p
				if sample.hidden or d.length()>12 or absf(d.dot(portal.dir.orthogonal()))>Rail.CORRIDOR_WIDTH: continue
				check(d.dot(portal.dir)<0.02,"Visible rails terminate at the portal instead of sticking through it")
	var broken_mountain := func(p: Vector2) -> float: return 6.0 if absf(p.x)>8 and absf(p.x)<90 else 5.0
	var continuous := Rail.build([route([Vector2(-240,0),Vector2.ZERO,Vector2(240,0)])],[],flat,broken_mountain)
	check(continuous.portals.size()==2,"A short daylight window across corridor boundaries stays inside one bore")
	var endpoints := {}
	for prof in continuous.corridor_profiles:
		for sample in prof.samples:
			if absf(sample.p.x)<80: check(sample.hidden,"No isolated rail stub between covered sections")
		for sample in [prof.samples[0],prof.samples[-1]]:
			var key := Rail._key(sample.p)
			if endpoints.has(key): check(endpoints[key]==sample.hidden,"Connected rail pieces share tunnel visibility at their seam")
			endpoints[key]=sample.hidden
	var l2 := Rail.build([route([Vector2(-100,0),Vector2(100,0)],"rails",2)],[],flat,low)
	var l3 := Rail.build([route([Vector2(-100,0),Vector2(100,0)],"rails",3)],[],flat,low)
	check(l3.detail.surface_get_array_len(0)>l2.detail.surface_get_array_len(0), "L3 fastening details distinguish L2")
	var atlas_path := "res://assets/iso/rails/rails.json"
	if FileAccess.file_exists(atlas_path):
		var atlas: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(atlas_path))
		var roads_atlas: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/iso/roads/roads.json"))
		for road in roads_atlas.cells: check(atlas.cells.has(str(road).replace("r_","rail_")), "Missing road-equivalent rail variation: " + road)
	print("[railway] checks finished; failures=", failures)
	get_tree().quit(1 if failures else 0)

func vertices(root: Node) -> int:
	var count := 0
	for node in root.find_children("*","MeshInstance3D",true,false):
		if node.mesh != null:
			for surface in node.mesh.get_surface_count(): count += node.mesh.surface_get_array_len(surface)
	return count
