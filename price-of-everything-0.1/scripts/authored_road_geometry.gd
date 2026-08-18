extends RefCounted
## Turns an authored road stroke into the polyline that gets drawn — and answers the two
## questions the editor must ask about one: which tiles does it touch, and does it cross
## water.
##
## SHARED ON PURPOSE. The editor's preview, the runtime layer and (in P4) the bake painter
## all call this, so what the designer sees, what the game draws and what gets baked cannot
## drift. Everything here is deterministic: curve sampling is fixed, and the wobble is
## seeded through `RoadHash` by stroke id, so a stroke looks identical on every load and in
## every process.
##
## POINT FORMAT. A stroke's `points` is an array where each entry is either
##     [x, y]                              — a corner, straight segments either side
##     [x, y, in_x, in_y, out_x, out_y]    — a curve control point, handles RELATIVE to it
## Two forms rather than a nested dictionary because this file is committed to git and read
## by hand: a straight run stays four short numbers per line instead of a wall of braces.
##
## Deliberately has NO `class_name` (the headless global-class-cache trap; see
## `scripts/mass_form_shapes.gd`).

const AuthoredRoadStyle := preload("res://scripts/authored_road_style.gd")

## A stroke shorter than this cannot carry a wobble sensibly and is almost certainly a
## mis-click; the editor lints it rather than drawing a speck.
const MIN_STROKE_LENGTH := 8.0

## World units between tile-membership samples. See [method touched_tiles] for why this is
## a chosen bound rather than a proven one.
const TILE_SAMPLE := 20.0


## The drawn polyline: curve sampled at a fixed interval, then wobbled. `stroke_id` seeds
## the wobble, so two strokes with identical geometry still differ — and the same stroke is
## identical every time.
static func polyline(stroke: Dictionary) -> PackedVector2Array:
	var sampled := sample(stroke)
	if sampled.size() < 2:
		return sampled
	return wobble(sampled, str(stroke.get("id", "")), str(stroke.get("class", "mid")))


## The stroke's geometry with no styling — the authored truth. Used for hit-testing,
## tile-touch and water tests, none of which should be answered by a wobbled line.
static func sample(stroke: Dictionary) -> PackedVector2Array:
	var points: Array = stroke.get("points", []) as Array
	if points.size() < 2:
		return PackedVector2Array()
	var curve := Curve2D.new()
	# Even spacing, because the wobble walks the line by arc length; Curve2D.tessellate
	# subdivides by angle instead and would bunch samples into the bends.
	curve.bake_interval = AuthoredRoadStyle.CURVE_SAMPLE
	var straight := true
	for entry in points:
		var values: Array = entry as Array
		if values == null or values.size() < 2:
			continue
		var position := Vector2(float(values[0]), float(values[1]))
		var handle_in := Vector2.ZERO
		var handle_out := Vector2.ZERO
		if values.size() >= 6:
			handle_in = Vector2(float(values[2]), float(values[3]))
			handle_out = Vector2(float(values[4]), float(values[5]))
			if handle_in != Vector2.ZERO or handle_out != Vector2.ZERO:
				straight = false
		curve.add_point(position, handle_in, handle_out)
	if curve.point_count < 2:
		return PackedVector2Array()
	if straight:
		# An all-corner stroke is a polyline; baking it would only resample the same
		# straight segments into a denser identical line.
		var out := PackedVector2Array()
		for i in curve.point_count:
			out.append(curve.get_point_position(i))
		return out
	return curve.get_baked_points()


## Seeded lateral wobble, the same algorithm the procedural roads use
## (`road_network_visuals._wobble_polyline`) so authored and generated linework read as one
## hand. Endpoints stay exact — a stroke must still meet what it was drawn to meet.
static func wobble(points: PackedVector2Array, stroke_id: String, stroke_class: String) -> PackedVector2Array:
	var settings: Array = AuthoredRoadStyle.wobble(stroke_class)
	if settings.size() < 2 or points.size() < 2:
		return points
	var step: float = settings[0]
	var amplitude: float = settings[1]
	var out := PackedVector2Array()
	var k := 0
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		out.append(a)
		var length := a.distance_to(b)
		var count := int(length / step)
		if count > 0:
			var direction := (b - a) / length
			var perpendicular := Vector2(-direction.y, direction.x)
			for j in range(1, count + 1):
				var offset := (float(RoadHash.pick("arwob|%s|%d" % [stroke_id, k], 200)) / 100.0 - 1.0) * amplitude
				k += 1
				out.append(a + (b - a) * (float(j) / float(count + 1)) + perpendicular * offset)
	out.append(points[points.size() - 1])
	return out


static func length_of(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	return total


## Every tile id the stroke's centreline passes through, sorted. THIS IS WHAT THE UNLOCK
## RULE READS: a stroke draws only when all of these carry the road flag, so the set must
## be complete — a missed tile would let a stroke appear across a roadless tile.
##
## Sampled along the line rather than tested per vertex: a long straight segment can cross a
## tile entirely between two vertices. (The roads bake learned the same lesson the hard way
## with wet chords between dry vertices.)
##
## THE STEP IS NOT PROVABLY SAFE, and cannot be: a stroke grazing a hex corner crosses an
## arbitrarily short chord of that tile, so no fixed step catches every case. It is set well
## below any crossing that matters instead — this runs once when a stroke is finished, never
## per frame, so accuracy is nearly free. A graze shorter than the step goes unreported,
## which is the harmless direction to err: a stroke clipping a few units of a corner should
## not hold its whole reveal hostage to that tile gaining roads.
static func touched_tiles(points: PackedVector2Array, terrain: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if terrain == null or points.size() < 2:
		return out
	var seen := {}
	var step := TILE_SAMPLE
	for i in range(1, points.size()):
		var a := points[i - 1]
		var b := points[i]
		var segment := a.distance_to(b)
		var steps := maxi(1, int(ceil(segment / step)))
		for s in range(steps + 1):
			var p := a.lerp(b, float(s) / float(steps))
			var coord: Vector2i = terrain.call("tile_coord_for_map_coord", terrain.call("local_to_map", p))
			if seen.has(coord):
				continue
			seen[coord] = true
			var tiles: Dictionary = terrain.get("tiles")
			if tiles.has(coord):
				out.append(str((tiles[coord] as Dictionary).get("id", "")))
	out.sort()
	return out


## Points along the stroke that fall on sea or lake, as `[world_position, water_kind]`.
## Rivers are NOT reported: roads bridge them, and the authored stroke carries the deck.
##
## The editor lints on this and the export gate re-runs it. It samples at 4 u, matching
## `tools/road_water_audit.gd` — the audit that found 1437 u of road drawn over open water
## by testing chords rather than vertices.
static func wet_samples(points: PackedVector2Array, nav: NavGrid) -> Array:
	var out: Array = []
	if nav == null or points.size() < 2 or not nav.is_ready():
		return out
	for i in range(1, points.size()):
		var a := points[i - 1]
		var b := points[i]
		var segment := a.distance_to(b)
		var steps := maxi(1, int(ceil(segment / 4.0)))
		for s in range(steps + 1):
			var p := a.lerp(b, float(s) / float(steps))
			var cell := nav.cell_of(p)
			var kind := nav.water(cell.x, cell.y)
			if kind == NavGrid.WATER_SEA or kind == NavGrid.WATER_LAKE:
				out.append([p, kind])
	return out


## The river crossings along a stroke, as `[position, tangent]` pairs — one per contiguous
## wet-river run, taken at its midpoint. These become the bridge decks: an authored road
## over a river must carry one, and the renderer draws nothing where a deck has no banks.
static func river_crossings(points: PackedVector2Array, nav: NavGrid) -> Array:
	var out: Array = []
	if nav == null or points.size() < 2 or not nav.is_ready():
		return out
	var run: Array = []
	for i in range(1, points.size()):
		var a := points[i - 1]
		var b := points[i]
		var segment := a.distance_to(b)
		var steps := maxi(1, int(ceil(segment / 4.0)))
		for s in range(steps + 1):
			var p := a.lerp(b, float(s) / float(steps))
			var cell := nav.cell_of(p)
			if nav.water(cell.x, cell.y) == NavGrid.WATER_RIVER:
				run.append(p)
			elif not run.is_empty():
				out.append(_crossing_of(run))
				run = []
	if not run.is_empty():
		out.append(_crossing_of(run))
	return out


static func _crossing_of(run: Array) -> Array:
	var first: Vector2 = run[0]
	var last: Vector2 = run[run.size() - 1]
	var mid: Vector2 = run[run.size() / 2]
	var tangent := (last - first)
	if tangent.length() < 0.001:
		tangent = Vector2.RIGHT
	return [mid, tangent.normalized()]
