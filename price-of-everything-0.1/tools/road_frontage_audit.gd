extends Node
## Audits how far each building sits from the road it fronts.
##   <godot> --headless --path . res://tools/road_frontage_audit.tscn --quit-after 4000
##
## For every tile that actually carries road geometry, measures the gap from
## each building's footprint to the nearest road centreline and reports the
## tiles where any building exceeds MAX_GAP. Categories that are placed away
## from roads BY DESIGN (extraction seeks tile edges, farms are fields) are
## counted separately rather than silently excluded — they are not failures.

const MAX_GAP := 15.0
const EDGE_SAMPLE := 3.0   # perimeter sampling step (u) for polygon->segment distance

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	for _i in 240:
		await get_tree().process_frame
	var bv: Node = get_tree().get_first_node_in_group("building_footprints")
	if bv == null:
		push_error("road_frontage_audit: BuildingVisuals not found")
		get_tree().quit(1)
		return
	var placements: Array = bv.get("_placements")
	var tile_segs: Dictionary = bv.get("_tile_segs")

	var by_tile: Dictionary = {}          # tile_id -> [worst_gap, worst_name]
	var fails: Array = []                 # [tile_id, iname, cat, gap]
	var by_design: Array = []             # same, for edge-placed/farm categories
	var measured := 0
	for p in placements:
		var tile_id := str(p.get("tile_id", ""))
		var segs: Array = tile_segs.get(tile_id, [])
		if segs.is_empty():
			continue   # tile has no road geometry — nothing to front onto
		var verts: PackedVector2Array = p.get("verts", PackedVector2Array())
		if verts.size() < 3:
			continue
		var origin: Vector2 = bv.call("_tile_center_world_pos", p.get("coord"))
		var gap := _poly_to_segs(verts, segs, origin)
		measured += 1
		var cat := str(p.get("cat", ""))
		var iname := str(p.get("iname", ""))
		var row := [tile_id, iname if iname != "" else cat, cat, gap]
		var by_design_cat := cat == "farm" or cat == "extraction" or iname == "mine"
		if gap > MAX_GAP:
			if by_design_cat:
				by_design.append(row)
			else:
				fails.append(row)
				var cur: Array = by_tile.get(tile_id, [0.0, ""])
				if gap > float(cur[0]):
					by_tile[tile_id] = [gap, row[1]]

	var road_tiles := 0
	for t in tile_segs:
		if not (tile_segs[t] as Array).is_empty():
			road_tiles += 1

	print("\n=== ROAD FRONTAGE AUDIT (max %.0fu) ===" % MAX_GAP)
	print("tiles with roads:            %d" % road_tiles)
	print("buildings measured:          %d" % measured)
	print("TILES FAILING:               %d" % by_tile.size())
	print("buildings over %.0fu:          %d" % [MAX_GAP, fails.size()])
	print("off-road by design (farm/extraction), not counted: %d" % by_design.size())
	fails.sort_custom(func(a, b) -> bool: return float(a[3]) > float(b[3]))
	print("\nworst offenders:")
	for i in mini(15, fails.size()):
		print("  %-12s %-22s %6.1fu" % [fails[i][0], fails[i][1], fails[i][3]])
	var tiles: Array = by_tile.keys()
	tiles.sort_custom(func(a, b) -> bool: return float(by_tile[a][0]) > float(by_tile[b][0]))
	print("\nfailing tiles (worst building each):")
	for i in mini(20, tiles.size()):
		print("  %-12s %6.1fu  (%s)" % [tiles[i], by_tile[tiles[i]][0], by_tile[tiles[i]][1]])
	get_tree().quit(0)

## Minimum distance from the footprint's perimeter to any road centreline.
## Segments are tile-relative; footprints are world — hence `origin`.
func _poly_to_segs(verts: PackedVector2Array, segs: Array, origin: Vector2) -> float:
	var best := INF
	for i in verts.size():
		var a := verts[i]
		var b := verts[(i + 1) % verts.size()]
		var edge_len := a.distance_to(b)
		var steps := maxi(1, int(edge_len / EDGE_SAMPLE))
		for s in steps + 1:
			var pt := a.lerp(b, float(s) / float(steps))
			for seg in segs:
				var s0: Vector2 = (seg[0] as Vector2) + origin
				var s1: Vector2 = (seg[1] as Vector2) + origin
				best = minf(best, pt.distance_to(Geometry2D.get_closest_point_to_segment(pt, s0, s1)))
	return best
