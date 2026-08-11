extends Node
## Measures how CLOSE neighbouring buildings actually stand.
##   <godot> --headless --path . res://tools/terrace_gap_audit.tscn --quit-after 4000
##
## This is the instrument for the terrace/packing question. `_overlaps` rejects a
## candidate that comes within DESIGN_GAP of a placed building, so DESIGN_GAP is the
## floor the packer is allowed to reach — but while the test compared upright boxes
## around ROTATED footprints, a diagonal street could never reach it: the boxes
## collided on empty corner air long before the buildings did. The symptom is
## measurable without judging a screenshot — count how many neighbours sit near the
## floor, and how far off it the tightest pair on each tile is.
##
## Reports the true polygon-to-polygon gap (not centre distance, not box distance),
## so it stays honest whatever the footprint rotation is.

const NEAR_BANDS := [2.0, 5.0, 10.0, 20.0]   # report counts under each gap (u)
const PAIR_RADIUS := 140.0                    # only measure genuinely adjacent pairs

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	for _i in 240:
		await get_tree().process_frame
	var bv: Node = get_tree().get_first_node_in_group("building_footprints")
	if bv == null:
		push_error("terrace_gap_audit: BuildingVisuals not found")
		get_tree().quit(1)
		return
	var placements: Array = bv.get("_placements")

	# Group by tile: neighbours only ever compete for space within their own tile.
	var by_tile: Dictionary = {}
	for p in placements:
		if str(p.cat) == "farm" or bool(p.get("offshore", false)):
			continue
		var tid := str(p.tile_id)
		if not by_tile.has(tid):
			by_tile[tid] = []
		(by_tile[tid] as Array).append(p)

	var gaps: Array = []                  # nearest-neighbour gap per building
	var pair_gaps: Array = []             # every adjacent pair, once
	var no_lverts := 0
	for tid in by_tile:
		var blds: Array = by_tile[tid]
		for i in blds.size():
			var a: Dictionary = blds[i]
			if (a.get("lverts", PackedVector2Array()) as PackedVector2Array).is_empty():
				no_lverts += 1
			var best := INF
			for j in blds.size():
				if i == j:
					continue
				var b: Dictionary = blds[j]
				var av: PackedVector2Array = a.verts
				var bv2: PackedVector2Array = b.verts
				if _centroid(av).distance_to(_centroid(bv2)) > PAIR_RADIUS:
					continue
				var g := _poly_gap(av, bv2)
				best = minf(best, g)
				if j > i:
					pair_gaps.append(g)
			if best < INF:
				gaps.append(best)

	gaps.sort()
	pair_gaps.sort()
	print("\n=== TERRACE GAP AUDIT ===")
	print("buildings with a neighbour: %d   adjacent pairs: %d" % [gaps.size(), pair_gaps.size()])
	print("placements missing lverts:  %d" % no_lverts)
	if gaps.is_empty():
		get_tree().quit(0)
		return
	print("nearest-neighbour gap: min %.1fu  median %.1fu  mean %.1fu" % [
		gaps[0], gaps[gaps.size() / 2], _mean(gaps)])
	for band in NEAR_BANDS:
		var n := 0
		for g in gaps:
			if float(g) < float(band):
				n += 1
		print("  buildings within %5.1fu of a neighbour: %4d  (%.1f%%)" % [
			band, n, 100.0 * float(n) / float(gaps.size())])
	print("tightest 10 pairs: %s" % str(pair_gaps.slice(0, 10).map(
		func(g): return "%.1f" % float(g))))
	get_tree().quit(0)

func _mean(a: Array) -> float:
	var s := 0.0
	for v in a:
		s += float(v)
	return s / float(a.size()) if a.size() > 0 else 0.0

func _centroid(v: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in v:
		c += p
	return c / float(v.size()) if v.size() > 0 else c

## True polygon-to-polygon gap: 0 if they intersect, else the smallest
## distance between any edge of one and any edge of the other.
func _poly_gap(a: PackedVector2Array, b: PackedVector2Array) -> float:
	if not Geometry2D.intersect_polygons(a, b).is_empty():
		return 0.0
	var best := INF
	for i in a.size():
		var p0: Vector2 = a[i]
		var p1: Vector2 = a[(i + 1) % a.size()]
		for j in b.size():
			var q0: Vector2 = b[j]
			var q1: Vector2 = b[(j + 1) % b.size()]
			best = minf(best, _seg_gap(p0, p1, q0, q1))
	return best

func _seg_gap(p0: Vector2, p1: Vector2, q0: Vector2, q1: Vector2) -> float:
	var d := Geometry2D.get_closest_points_between_segments(p0, p1, q0, q1)
	return (d[0] as Vector2).distance_to(d[1] as Vector2)
