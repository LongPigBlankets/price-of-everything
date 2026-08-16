extends Node
## Finds drawn road-coloured geometry that lies on sea or lake.
##   <godot> --headless --path . res://tools/road_water_audit.tscn --quit-after 40000
##
## Roads must never appear on lakes or sea (owner rule 2026-08-16). Water is
## declamped at bake time at polyline VERTICES only, and several layers draw
## road-coloured lines that never route on NavGrid at all. This samples every
## such layer DENSELY and classifies each sample, so the wet geometry is
## attributed to the layer that actually owns it rather than guessed at.

const SAMPLE_STEP := 4.0        # sampling step along the polyline (u)
const BRIDGE_COVER := 26.0      # a wet run within this of a bridge point is that crossing
const MIN_REPORT_RUN := 6.0     # ignore sub-cell nicks at the waterline

const KIND_NAME := {1: "SEA", 2: "LAKE", 3: "river"}

var _nav: NavGrid = null
var _terrain: Node = null

func _ready() -> void:
	# The mid-century fabric only builds behind MapStyle.is_midcentury(); without
	# this the fabric arrays stay EMPTY and the sweep silently measures nothing.
	MapStyle.set_midcentury(true)
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	for _i in 420:
		await get_tree().process_frame
	_nav = NavGrid.instance()
	if not _nav.is_ready():
		push_error("road_water_audit: navgrid not ready")
		get_tree().quit(1)
		return
	# TerrainLayer is reached through the world-map node (there is no "terrain"
	# group); without this every row reports its tile as "?".
	var wm := _find_named(get_tree().root, "TerrainLayer")
	_terrain = wm
	_audit_network()
	_audit_building_visuals()
	_audit_fabric()
	get_tree().quit(0)

## The baked road network: routed on NavGrid, so only vertex-gap spans and
## unbridged river crossings should show.
func _audit_network() -> void:
	var network := RoadNetwork.instance()
	var wet: Array = []
	var edges_seen := 0
	for edge_id in network.edges:
		var edge: Dictionary = network.edges[edge_id]
		if str(edge.state) != RoadNetwork.STATE_BUILT:
			continue
		edges_seen += 1
		var geo: PackedVector2Array = edge.geometry
		if geo.size() < 2:
			continue
		var bridges: Array = edge.get("bridges", [])
		for run in _wet_runs(geo):
			if float(run[1]) < MIN_REPORT_RUN:
				continue
			var bridged := false
			for b in bridges:
				if (b.point as Vector2).distance_to(run[0]) <= BRIDGE_COVER + float(run[1]) * 0.5:
					bridged = true
					break
			if not bridged:
				wet.append([float(run[1]), run[0], int(run[2]), str(edge_id)])
	_report("road_network", edges_seen, wet)

## Service lanes and farm tracks live on BuildingVisuals in world space.
func _audit_building_visuals() -> void:
	var bv: Node = get_tree().get_first_node_in_group("building_footprints")
	if bv == null:
		print("[WATER] building_footprints not found")
		return
	for src_name in ["_service_world", "_farm_lanes"]:
		var src = bv.get(src_name)
		if src == null:
			print("[WATER] %s: absent" % src_name)
			continue
		var wet: Array = []
		var n := 0
		for tid in (src as Dictionary):
			var v = (src as Dictionary)[tid]
			var polys: Array = [v] if v is PackedVector2Array else (v as Array)
			for poly in polys:
				var pv: PackedVector2Array = poly
				if pv.size() < 2:
					continue
				n += 1
				for run in _wet_runs(pv):
					if float(run[1]) >= MIN_REPORT_RUN:
						wet.append([float(run[1]), run[0], int(run[2]), str(tid)])
		_report(src_name, n, wet)

## The mid-century fabric draws its own street/alley/service lines as
## draw_multiline point PAIRS. These never route on NavGrid.
func _audit_fabric() -> void:
	var fab := _find_fabric(get_tree().root)
	if fab == null:
		print("[WATER] UrbanFabricVisuals not found")
		return
	for fname in ["_settlement_streets", "_service_lines", "_hero_alleys"]:
		var ml = fab.get(fname)
		if ml == null:
			print("[WATER] %s: absent" % fname)
			continue
		var pv: PackedVector2Array = ml
		var wet: Array = []
		var i := 0
		while i + 1 < pv.size():
			var seg := PackedVector2Array([pv[i], pv[i + 1]])
			for run in _wet_runs(seg):
				if float(run[1]) >= MIN_REPORT_RUN:
					wet.append([float(run[1]), run[0], int(run[2]), "seg%d" % (i / 2)])
			i += 2
		_report(fname, pv.size() / 2, wet)

func _report(label: String, n_items: int, wet: Array) -> void:
	wet.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	var total := 0.0
	var sea := 0.0
	for w in wet:
		total += float(w[0])
		if int(w[2]) == NavGrid.WATER_SEA or int(w[2]) == NavGrid.WATER_LAKE:
			sea += float(w[0])
	print("[WATER] %-22s items=%-6d wet_runs=%-4d wet=%.0fu  SEA/LAKE=%.0fu"
		% [label, n_items, wet.size(), total, sea])
	var shown := 0
	for w in wet:
		if int(w[2]) == NavGrid.WATER_RIVER:
			continue     # rivers are a separate (minor) concern
		if shown >= 12:
			break
		shown += 1
		print("    %7.1fu  %-4s  %-12s  %s at (%.0f,%.0f)"
			% [float(w[0]), str(KIND_NAME.get(int(w[2]), "?")),
				_tile_of(w[1]), str(w[3]), (w[1] as Vector2).x, (w[1] as Vector2).y])

## Contiguous runs of wet samples along a polyline -> [[midpoint, length, kind]].
func _wet_runs(pts: PackedVector2Array) -> Array:
	var out: Array = []
	var run_start := Vector2.INF
	var run_last := Vector2.INF
	var run_kind := 0
	var run_len := 0.0
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var n := maxi(1, int(ceil(a.distance_to(b) / SAMPLE_STEP)))
		for j in range(n + 1):
			var p := a.lerp(b, float(j) / float(n))
			var c := _nav.cell_of(p)
			var w := _nav.water(c.x, c.y)
			if w != NavGrid.WATER_LAND:
				if run_start == Vector2.INF:
					run_start = p
					run_kind = w
					run_len = 0.0
				else:
					run_len += run_last.distance_to(p)
					if w == NavGrid.WATER_SEA:
						run_kind = w      # sea dominates the label
				run_last = p
			elif run_start != Vector2.INF:
				out.append([(run_start + run_last) * 0.5, run_len, run_kind])
				run_start = Vector2.INF
	if run_start != Vector2.INF:
		out.append([(run_start + run_last) * 0.5, run_len, run_kind])
	return out

func _tile_of(world: Vector2) -> String:
	if _terrain == null or not _terrain.has_method("tile_coord_for_map_coord"):
		return "?"
	var tc: Vector2i = _terrain.tile_coord_for_map_coord(_terrain.local_to_map(world))
	return "tile_%d_%d" % [tc.x + 1, tc.y + 1]

func _find_fabric(n: Node) -> Node:
	var scr: Variant = n.get_script()
	if scr != null and str(scr.resource_path).ends_with("urban_fabric_visuals.gd"):
		return n
	for c in n.get_children():
		var r := _find_fabric(c)
		if r != null:
			return r
	return null

func _find_named(n: Node, want: String) -> Node:
	if n.name == want:
		return n
	for c in n.get_children():
		var r := _find_named(c, want)
		if r != null:
			return r
	return null
