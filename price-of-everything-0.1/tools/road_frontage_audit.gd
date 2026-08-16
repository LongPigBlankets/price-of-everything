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
## Half the widest drawn road casing (trunk 8.2u carriageway + 4.0u casing).
## A footprint closer than this to a centreline is drawn UNDER the road.
const UNDER_ROAD_HALF_CASING := 6.1
## Per-tile tolerance: an occasional building under a road reads as an overpass.
## More than this on one tile is a placement defect, not a flourish.
const UNDER_ROAD_TILE_TOLERANCE := 2
const EDGE_SAMPLE := 3.0   # perimeter sampling step (u) for polygon->segment distance
## Off-road by design (mirrors BuildingVisuals.OFF_ROAD_NAMES): pits and
## renewable farms belong on open ground, so they are reported separately
## rather than counted as frontage failures.
const OFF_ROAD := {
	"mine": true, "solar_farm": true,
	"onshore_wind_farm": true, "offshore_wind_farm": true,
}

func _ready() -> void:
	# Classify every rejected frontage candidate (off in play — it costs four
	# extra predicate calls per rejection).
	var bv_script := load("res://scenes/building_visuals.gd")
	bv_script.set("DIAG", true)
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
	var block_streets: Dictionary = {}   # (blocks no longer invent their own streets)
	# A building fronting a SERVICE LANE has frontage — the lane is a street, just a
	# thin one. Measuring only against main roads would score the lane as a failure.
	var lanes: Dictionary = bv.get("_service_segs")
	var lane_only := 0

	# UNDER-ROAD: a footprint whose perimeter comes within half the drawn road
	# casing of a centreline is sitting ON the carriageway, not beside it. Widest
	# mid-century casing is trunk 8.2u + 4.0u = 12.2u, so half is 6.1u. One or two
	# per region read diegetically as an overpass; a systemic rise does not, which
	# is why this is counted per tile rather than only map-wide.
	var under_road: Array = []            # [tile_id, name, gap]
	var under_by_tile: Dictionary = {}    # tile_id -> count

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
		var road_gap := minf(_poly_to_segs(verts, segs, origin),
			_poly_to_segs(verts, block_streets.get(tile_id, []), Vector2.ZERO))
		var lane_gap := _poly_to_segs(verts, lanes.get(tile_id, []), origin)
		var gap := minf(road_gap, lane_gap)
		if road_gap > MAX_GAP and lane_gap <= MAX_GAP:
			lane_only += 1
		if road_gap < UNDER_ROAD_HALF_CASING:
			under_road.append([tile_id, str(p.get("iname", p.get("cat", "?"))), road_gap])
			under_by_tile[tile_id] = int(under_by_tile.get(tile_id, 0)) + 1
		measured += 1
		var cat := str(p.get("cat", ""))
		var iname := str(p.get("iname", ""))
		var row := [tile_id, iname if iname != "" else cat, cat, gap,
			str(p.get("via", "?")), float(p.get("shrink", 1.0)), p.get("diag", {}), _extent(verts)]
		var by_design_cat := cat == "farm" or cat == "extraction" or OFF_ROAD.has(iname)
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
	print("saved by a service lane:     %d buildings" % lane_only)
	print("buildings over %.0fu:          %d" % [MAX_GAP, fails.size()])
	print("off-road by design (farm/extraction), not counted: %d" % by_design.size())
	# WHY: which placement route produced the failures, and how big they were.
	var via_fail: Dictionary = {}
	var via_pass: Dictionary = {}
	var rej: Dictionary = {"land": 0, "overlap": 0, "road": 0, "river": 0, "tried": 0}
	var fail_extent := 0.0
	var pass_extent := 0.0
	var shrunk := 0
	for p in placements:
		var tile_id2 := str(p.get("tile_id", ""))
		if (tile_segs.get(tile_id2, []) as Array).is_empty():
			continue
		var cat2 := str(p.get("cat", ""))
		if cat2 == "farm" or cat2 == "extraction" or str(p.get("iname", "")) == "mine":
			continue
		var v := str(p.get("via", "?"))
		var verts2: PackedVector2Array = p.get("verts", PackedVector2Array())
		if verts2.size() < 3:
			continue
		var g := minf(_poly_to_segs(verts2, tile_segs[tile_id2], bv.call("_tile_center_world_pos", p.get("coord"))),
			_poly_to_segs(verts2, block_streets.get(tile_id2, []), Vector2.ZERO))
		if g > MAX_GAP:
			via_fail[v] = int(via_fail.get(v, 0)) + 1
			fail_extent += _extent(verts2)
			if float(p.get("shrink", 1.0)) < 1.0:
				shrunk += 1
			var d: Dictionary = p.get("diag", {})
			for k in rej.keys():
				rej[k] = int(rej[k]) + int(d.get(k, 0))
		else:
			via_pass[v] = int(via_pass.get(v, 0)) + 1
			pass_extent += _extent(verts2)
	var street_tiles := 0
	var street_count := 0
	for t in block_streets:
		street_tiles += 1
		street_count += (block_streets[t] as Array).size()
	var fail_block_with_streets := 0
	var fail_block_no_streets := 0
	for f in fails:
		if str(f[4]) == "block":
			if (block_streets.get(str(f[0]), []) as Array).is_empty():
				fail_block_no_streets += 1
			else:
				fail_block_with_streets += 1
	print("\nblock streets: %d tiles, %d streets" % [street_tiles, street_count])
	print("failing block bldgs on tiles WITH streets: %d / WITHOUT: %d" % [fail_block_with_streets, fail_block_no_streets])
	print("placed VIA (failing):  %s" % str(via_fail))
	print("placed VIA (passing):  %s" % str(via_pass))
	print("mean footprint extent: failing %.1fu vs passing %.1fu" % [
		fail_extent / maxf(1.0, float(fails.size())),
		pass_extent / maxf(1.0, float(via_pass.values().reduce(func(a, b): return a + b, 0)))])
	print("failing buildings that had already been SHRUNK: %d" % shrunk)
	print("frontage candidates rejected (failing bldgs): %s" % str(rej))

	fails.sort_custom(func(a, b) -> bool: return float(a[3]) > float(b[3]))
	# Buildings drawn under a road.
	var hot: Array = []
	for t in under_by_tile:
		if int(under_by_tile[t]) > UNDER_ROAD_TILE_TOLERANCE:
			hot.append([t, int(under_by_tile[t])])
	hot.sort_custom(func(a, b): return a[1] > b[1])
	print("\nUNDER-ROAD (footprint within %.1fu of a centreline — drawn on the carriageway):" % UNDER_ROAD_HALF_CASING)
	print("  buildings under a road:  %d of %d measured" % [under_road.size(), measured])
	print("  tiles carrying any:      %d" % under_by_tile.size())
	print("  tiles OVER tolerance:    %d  (more than %d on one tile)" % [hot.size(), UNDER_ROAD_TILE_TOLERANCE])
	for i in mini(hot.size(), 8):
		print("    %-12s %d buildings" % [hot[i][0], hot[i][1]])
	under_road.sort_custom(func(a, b): return a[2] < b[2])
	for i in mini(under_road.size(), 5):
		print("    deepest: %-12s %-22s %.1fu from centreline" % [under_road[i][0], under_road[i][1], under_road[i][2]])

	print("\nworst offenders:")
	for i in mini(15, fails.size()):
		print("  %-12s %-22s %6.1fu  via=%-9s ext=%.0fu" % [
			fails[i][0], fails[i][1], fails[i][3], fails[i][4], fails[i][7]])
	var tiles: Array = by_tile.keys()
	tiles.sort_custom(func(a, b) -> bool: return float(by_tile[a][0]) > float(by_tile[b][0]))
	print("\nfailing tiles (worst building each):")
	for i in mini(20, tiles.size()):
		print("  %-12s %6.1fu  (%s)" % [tiles[i], by_tile[tiles[i]][0], by_tile[tiles[i]][1]])
	get_tree().quit(0)

## Longest side of a footprint, world units.
func _extent(pts: PackedVector2Array) -> float:
	var mn := Vector2(1e30, 1e30)
	var mx := Vector2(-1e30, -1e30)
	for p in pts:
		mn = mn.min(p)
		mx = mx.max(p)
	return maxf((mx - mn).x, (mx - mn).y)

## Minimum distance from the footprint's perimeter to any road centreline.
## Segments are tile-relative; footprints are world — hence `origin`.
func _poly_to_segs(verts: PackedVector2Array, segs: Array, origin: Vector2) -> float:
	var best := INF
	if segs.is_empty():
		return best
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
