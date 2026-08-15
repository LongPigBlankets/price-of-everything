class_name DensityAudit
extends RefCounted
## Pure classification and gate logic for the per-tile decorative-density audit
## required by docs/map-density-and-port-addendum.md section 6.
##
## Everything here is a static, side-effect-free function over already-measured
## numbers so the classification and the small/large split can be pinned by unit
## tests without a scene tree, a viewport or a rebuild. The geometry that feeds
## these functions is measured by `UrbanFabricVisuals.density_audit_snapshot()`
## and assembled by `tools/density_audit.gd`.
##
## THE SMALL / LARGE THRESHOLD
## ---------------------------
## `LARGE_MASS_AREA` is ONE absolute world-unit area, applied map-wide, so counts
## are comparable between tiles (the addendum forbids a per-tile relative split).
## It is derived from the mid-century mass-area distribution recorded by
## `UrbanFabricVisuals._morph_mass_distribution` in the frozen v0 baseline:
## reconstructing the global histogram from every settlement's 125u size buckets
## (961 ordinary masses) gives median 1030u^2, p75 ~1640u^2, p90 ~2500u^2.
##
## 1600u^2 is the p75 of that distribution rounded to a round number. Two
## independent checks agree on that cut:
##   * The addendum's own urban row asks for >= 10 small and >= 3 large, i.e. a
##     large share of 3/13 = 23% of masses. The p75 cut yields ~25% large,
##     the nearest principled match.
##   * 1600u^2 sits just above `UrbanFabricVisuals.MORPH_FACE_MIN_AREA` (1500u^2),
##     the minimum area the face subdivider will leave undivided. A mass at or
##     above the cut therefore occupies a whole un-subdivided street face — it
##     reads as a block-scale building — while anything under it is a parcel
##     inside a subdivided face.
##
## The constant is FROZEN at the baseline value on purpose. It must not be
## recomputed from a candidate run: if a stream adds hundreds of small masses,
## a re-derived p75 would slide down and silently re-label the same buildings.
const LARGE_MASS_AREA := 1600.0

## Median area of a baseline SMALL mass (below the cut), used only by the
## advisory physical-capacity estimate below. Measured from the same histogram.
const SMALL_MASS_MEDIAN_AREA := 800.0

## How much dry land a settlement consumes per unit of building footprint once
## streets, setbacks, yards, parks and road corridors are paid for. Baseline
## whole-body coverage runs 12-46% built, so ~3x footprint is the honest
## allowance for "could this tile physically hold its floor".
const PACKING_ALLOWANCE := 3.0

## A mass smaller than this is a fragment (a clipped remnant, a roof cut), not a
## building, and is excluded from both counts. Matches the smallest park/mass
## retention floors already used by the fabric.
const MIN_COUNTED_MASS_AREA := 120.0

## Two green polygons whose merged outline is one shape are ONE green space.
## Fragments below this are not a "green space" for the >= 2 urban floor.
const MIN_COUNTED_GREEN_AREA := 200.0

const CLASS_URBAN := "urban"
const CLASS_SPARSE := "sparse"
const CLASS_MOUNTAIN := "mountain"
const CLASS_REMOTE := "remote"
const CLASS_WATER := "water"

## Decorative mass kinds that count as a BUILDING. `industry_support` masses are
## decorative sheds and aprons the fabric draws beside gameplay industry; they
## are rendered decoration, not gameplay geometry, so they count.
const BUILDING_KINDS := {
	"ordinary": true, "core": true, "industry_support": true,
}

## Green kinds that count as a PUBLIC GREEN SPACE for the urban >= 2 floor.
## `courtyard` is deliberately excluded: an inner court belongs to the building
## that encloses it, and counting it would let a stream satisfy the park floor by
## stamping courtyards instead of making public green.
const GREEN_KINDS := {
	"park": true, "green": true, "accommodation_park": true,
}

## Terrain classes that carry no land and are not audited at all.
const WATER_TERRAIN := {"sea": true, "deep_sea": true}


## Class assignment, from authoritative data only. Never invents or mutates a
## classification: `terrain_type` is the tile's own terrain class,
## `is_profiled_urban` is membership of data/visual_settlement_profiles.json,
## and `built_road_edge_count` is the count of BUILT RoadNetwork edges on the
## tile.
##
## Precedence, exactly as the addendum states it:
##   water      - sea/deep_sea, not audited
##   urban      - the 92 profiled urban tiles
##   mountain   - terrain class mountain; the cap WINS over the sparse floor,
##                so a mountain tile that carries a road is still mountain
##   sparse     - non-urban, non-mountain, with >= 1 authoritative road
##   remote     - non-urban, non-mountain, with no road; exempt from the floor
static func classify(terrain_type: String, is_profiled_urban: bool,
		built_road_edge_count: int) -> String:
	if WATER_TERRAIN.has(terrain_type):
		return CLASS_WATER
	if terrain_type == CLASS_URBAN and is_profiled_urban:
		return CLASS_URBAN
	if terrain_type == CLASS_MOUNTAIN:
		return CLASS_MOUNTAIN
	if built_road_edge_count > 0:
		return CLASS_SPARSE
	return CLASS_REMOTE


## The section-2 row for a class. `-1` means "no bound on this side".
static func requirements(tile_class: String) -> Dictionary:
	match tile_class:
		CLASS_URBAN:
			return {"small_min": 10, "small_max": -1, "large_min": 3,
				"large_max": -1, "park_min": 2}
		CLASS_SPARSE:
			return {"small_min": 3, "small_max": 10, "large_min": 0,
				"large_max": 2, "park_min": -1}
		CLASS_MOUNTAIN:
			return {"small_min": -1, "small_max": 2, "large_min": 0,
				"large_max": 0, "park_min": -1}
		CLASS_REMOTE:
			return {"small_min": 1, "small_max": 4, "large_min": 0,
				"large_max": 0, "park_min": -1}
		_:
			return {"small_min": -1, "small_max": -1, "large_min": -1,
				"large_max": -1, "park_min": -1}


## True when the mass belongs in the small/large counts at all.
static func counts_as_building(kind: String, area: float) -> bool:
	return BUILDING_KINDS.has(kind) and area >= MIN_COUNTED_MASS_AREA


static func counts_as_green(kind: String, area: float) -> bool:
	return GREEN_KINDS.has(kind) and area >= MIN_COUNTED_GREEN_AREA


static func is_large(area: float) -> bool:
	return area >= LARGE_MASS_AREA


## Dry buildable area a tile would need to physically hold its floor. Advisory
## only: it separates "this tile is empty because nothing built there" from
## "this tile could never comply", so a shortfall can be documented rather than
## chased. A documented shortfall is acceptable; a silent miss is a failure.
static func required_dry_area(tile_class: String) -> float:
	var req := requirements(tile_class)
	var small_floor := maxi(0, int(req.small_min))
	var large_floor := maxi(0, int(req.large_min))
	return PACKING_ALLOWANCE * (float(small_floor) * SMALL_MASS_MEDIAN_AREA +
		float(large_floor) * LARGE_MASS_AREA)


## Evaluate one tile against its section-2 row. Returns the named failures, the
## pass flag, and whether the miss is plausibly physical.
##
## `green_count` MUST be the DELIBERATE park count from instrument 2 below, not
## the raw green-polygon count. An undrawn hole is bare ground, not a civic
## green, and the addendum's >= 2 parks-per-urban-tile floor is not satisfied by
## one. This is the correction the V5 blind pass forced: the park counter rose
## while the plate lost its civic blocks.
##
## `documented_shortfall` is the caller's evidence that the fabric itself
## reported this tile as unable to comply, with rejected-candidate counts. A
## tile that misses its floor WITHOUT such a record is a gate failure; that is
## the "silent miss" the addendum forbids.
static func evaluate(tile_class: String, small_count: int, large_count: int,
		green_count: int, dry_buildable_area: float,
		documented_shortfall: bool) -> Dictionary:
	var req := requirements(tile_class)
	var failures: Array[String] = []
	if int(req.small_min) >= 0 and small_count < int(req.small_min):
		failures.append("small_below_floor")
	if int(req.small_max) >= 0 and small_count > int(req.small_max):
		failures.append("small_above_cap")
	if int(req.large_min) >= 0 and large_count < int(req.large_min):
		failures.append("large_below_floor")
	if int(req.large_max) >= 0 and large_count > int(req.large_max):
		failures.append("large_above_cap")
	if int(req.park_min) >= 0 and green_count < int(req.park_min):
		failures.append("green_below_floor")
	var below_floor := failures.has("small_below_floor") or \
		failures.has("large_below_floor") or failures.has("green_below_floor")
	var needed := required_dry_area(tile_class)
	var physically_constrained := below_floor and dry_buildable_area < needed
	return {
		"requirements": req,
		"failures": failures,
		"passes": failures.is_empty(),
		"below_floor": below_floor,
		"required_dry_area": needed,
		"physically_constrained": physically_constrained,
		"documented_shortfall": documented_shortfall,
		# The gate: a miss is only acceptable when the fabric documented it.
		"gate_failure": not failures.is_empty() and not documented_shortfall,
	}


# =============================================================================
# INSTRUMENT 1 - ARTICULATION / VISIBLE PIECE COUNT
# =============================================================================
#
# WHY THIS EXISTS
# ---------------
# Built area and mass count are both blind to the failure that got the V5
# vocabulary pass rejected: coverage rose 2.1% map-wide while the plate visibly
# LOST parcels, because one wide-vocabulary form stood where the legacy splitter
# had drawn two or three masses. The aggregate mass count concealed it exactly
# (2037 -> 2044) because fusing three masses into one and adding four companions
# elsewhere nets to zero.
#
# A NAIVE POLYGON COUNT CANNOT SEE THIS EITHER. The implementing agent measured
# the rejected Vandel blob as "several adjacent masses rather than one polygon"
# whose outlines abut "with only their outlines between them and read as one
# silhouette" - a polygon counter reports that blob as N healthy masses while a
# human sees one amoeba.
#
# THE DEFINITION
# --------------
# Two masses are VISUALLY FUSED when their outlines, each dilated by
# FUSION_DILATION, overlap - i.e. when the bare ground between them is narrower
# than 2 * FUSION_DILATION. A VISIBLE PIECE is a connected component of the
# masses under that relation, and its SILHOUETTE is the union of those dilated
# outlines. The count of visible pieces, not of polygons, is what the eye reads.
#
# FUSION_DILATION is not tuned. It is HALF of the map's own narrowest legible
# separation: `UrbanFabricVisuals.HERO_ALLEY_HALF_WIDTH` is 1.9u, so every alley
# the fabric accepts as a visible gap is 3.8u wide. Anything narrower than an
# accepted alley is not a gap the plate shows, so the two masses either side of
# it are one silhouette. Dilating each mass by 1.9u closes exactly that gap and
# no more. The constant is FROZEN for the same reason LARGE_MASS_AREA is: a
# candidate that fuses its fabric must not be able to redefine "fused".
const FUSION_DILATION := 1.9

## Sampling step, in world units, for the perimeter walks below. Fine enough to
## resolve one dilated alley (3.8u) and coarse enough to stay cheap.
const OUTLINE_SAMPLE_STEP := 2.0


static func poly_perimeter(poly: PackedVector2Array) -> float:
	if poly.size() < 2:
		return 0.0
	var total := 0.0
	for i in poly.size():
		total += poly[i].distance_to(poly[(i + 1) % poly.size()])
	return total


static func signed_area(poly: PackedVector2Array) -> float:
	var total := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		total += a.x * b.y - b.x * a.y
	return total * 0.5


## Outward dilation of one outline by `delta`. Winding is normalised to CCW
## first, exactly as `UrbanFabricVisuals._sanitize_gameplay_collisions` does,
## because Clipper deflates a clockwise ring for a positive delta. JOIN_SQUARE
## is used rather than JOIN_MITER so an acute corner cannot throw a long spike
## that would fuse two masses that are nowhere near each other.
static func dilate_outline(poly: PackedVector2Array,
		delta: float) -> PackedVector2Array:
	if poly.size() < 3:
		return PackedVector2Array()
	var ccw := poly.duplicate()
	if Geometry2D.is_polygon_clockwise(ccw):
		ccw.reverse()
	var offsets: Array = Geometry2D.offset_polygon(ccw, delta,
		Geometry2D.JOIN_SQUARE)
	var best := PackedVector2Array()
	var best_area := -1.0
	for offset_value in offsets:
		var offset: PackedVector2Array = offset_value
		if offset.size() < 3:
			continue
		var area := absf(signed_area(offset))
		if area > best_area:
			best_area = area
			best = offset
	return best if best.size() >= 3 else ccw


static func _bounds(poly: PackedVector2Array) -> Rect2:
	if poly.is_empty():
		return Rect2()
	var mn := poly[0]
	var mx := poly[0]
	for point in poly:
		mn = mn.min(point)
		mx = mx.max(point)
	return Rect2(mn, mx - mn)


## Union-find root with path compression.
static func _uf_find(parent: PackedInt32Array, node: int) -> int:
	var root := node
	while parent[root] != root:
		root = parent[root]
	var walk := node
	while parent[walk] != root:
		var next := parent[walk]
		parent[walk] = root
		walk = next
	return root


## Group already-counted masses into VISIBLE PIECES.
##
## `shapes` is an array of dictionaries carrying at least `poly` (the drawn
## outline) and `area`. The return is one dictionary per visible piece:
##   members               indices into `shapes`
##   mass_count            how many drawn masses hide inside this one silhouette
##   area                  summed ink area of those masses
##   silhouette            the union outline (dilated), for tile assignment
##   silhouette_center     centroid of the silhouette bounding box
##   silhouette_perimeter  outer perimeter of that union
##   outline_perimeter_sum summed perimeter of the dilated member outlines
##
## `silhouette_perimeter` < `outline_perimeter_sum` exactly when boundary was
## lost to fusion, so their ratio is a second, independent fusion signal that
## does not depend on the piece count at all.
static func visible_pieces(shapes: Array,
		dilation: float = FUSION_DILATION) -> Array:
	var count := shapes.size()
	var dilated: Array = []
	var boxes: Array[Rect2] = []
	for shape_value in shapes:
		var shape: Dictionary = shape_value
		var grown := dilate_outline(shape.get("poly", PackedVector2Array()),
			dilation)
		dilated.append(grown)
		boxes.append(_bounds(grown))

	# Spatial hash so the pair test is local, not quadratic over the map.
	var cell := 96.0
	var buckets: Dictionary = {}
	for i in count:
		if (dilated[i] as PackedVector2Array).size() < 3:
			continue
		var box: Rect2 = boxes[i]
		var x0 := floori(box.position.x / cell)
		var x1 := floori((box.position.x + box.size.x) / cell)
		var y0 := floori(box.position.y / cell)
		var y1 := floori((box.position.y + box.size.y) / cell)
		for cx in range(x0, x1 + 1):
			for cy in range(y0, y1 + 1):
				var key := Vector2i(cx, cy)
				if not buckets.has(key):
					buckets[key] = PackedInt32Array()
				var bucket: PackedInt32Array = buckets[key]
				bucket.append(i)
				buckets[key] = bucket

	var parent := PackedInt32Array()
	parent.resize(count)
	for i in count:
		parent[i] = i
	var tested: Dictionary = {}
	for bucket_value in buckets.values():
		var bucket: PackedInt32Array = bucket_value
		for a in bucket.size():
			for b in range(a + 1, bucket.size()):
				var i: int = bucket[a]
				var j: int = bucket[b]
				if i > j:
					var swap := i
					i = j
					j = swap
				var pair_key := i * count + j
				if tested.has(pair_key):
					continue
				tested[pair_key] = true
				if not (boxes[i] as Rect2).intersects(boxes[j]):
					continue
				if _uf_find(parent, i) == _uf_find(parent, j):
					continue
				if Geometry2D.intersect_polygons(dilated[i],
						dilated[j]).is_empty():
					continue
				parent[_uf_find(parent, i)] = _uf_find(parent, j)

	var groups: Dictionary = {}
	for i in count:
		var root := _uf_find(parent, i)
		if not groups.has(root):
			groups[root] = PackedInt32Array()
		var members: PackedInt32Array = groups[root]
		members.append(i)
		groups[root] = members

	var roots: Array = groups.keys()
	roots.sort()
	var pieces: Array = []
	for root_value in roots:
		var members: PackedInt32Array = groups[root_value]
		var area := 0.0
		var outline_sum := 0.0
		var union: Array = []
		for index in members:
			var shape: Dictionary = shapes[index]
			area += float(shape.get("area", 0.0))
			var grown: PackedVector2Array = dilated[index]
			outline_sum += poly_perimeter(grown)
			union = _merge_into(union, grown)
		var silhouette := PackedVector2Array()
		var silhouette_area := -1.0
		var silhouette_perimeter := 0.0
		for piece_value in union:
			var piece: PackedVector2Array = piece_value
			if piece.size() < 3 or Geometry2D.is_polygon_clockwise(piece):
				continue  # clockwise rings are holes, not silhouette outline
			silhouette_perimeter += poly_perimeter(piece)
			var piece_area := absf(signed_area(piece))
			if piece_area > silhouette_area:
				silhouette_area = piece_area
				silhouette = piece
		var box := _bounds(silhouette)
		pieces.append({
			"members": members,
			"mass_count": members.size(),
			"area": area,
			"silhouette": silhouette,
			"silhouette_center": box.position + box.size * 0.5,
			"silhouette_area": maxf(0.0, silhouette_area),
			"silhouette_perimeter": silhouette_perimeter,
			"outline_perimeter_sum": outline_sum,
		})
	return pieces


static func _merge_into(union: Array, poly: PackedVector2Array) -> Array:
	if union.is_empty():
		return [poly]
	var pending := poly
	var out: Array = []
	var i := 0
	var accumulated: Array = union.duplicate()
	while i < accumulated.size():
		var merged: Array = Geometry2D.merge_polygons(accumulated[i], pending)
		if merged.size() == 1:
			pending = merged[0]
			accumulated.remove_at(i)
			i = 0
		else:
			i += 1
	out = accumulated
	out.append(pending)
	return out


## Roll a set of visible pieces up into the numbers a report quotes.
##
## `masses_per_visible_piece` is the headline: 1.00 is a perfectly articulated
## fabric where every drawn mass reads as its own building, and it rises as
## masses disappear into shared silhouettes. `mean_visible_piece_area` and
## `median_visible_piece_area` are what make "denser in ink, sparser in city"
## legible - the V5 candidate raised built area while these rose too, which is
## the signature of fewer, fatter pieces.
static func articulation_summary(pieces: Array) -> Dictionary:
	var piece_count := pieces.size()
	var mass_count := 0
	var fused_pieces := 0
	var fused_masses := 0
	var largest_piece_mass_count := 0
	var outline_sum := 0.0
	var silhouette_sum := 0.0
	var areas: Array[float] = []
	for piece_value in pieces:
		var piece: Dictionary = piece_value
		var members := int(piece.mass_count)
		mass_count += members
		if members >= 2:
			fused_pieces += 1
			fused_masses += members
		largest_piece_mass_count = maxi(largest_piece_mass_count, members)
		outline_sum += float(piece.outline_perimeter_sum)
		silhouette_sum += float(piece.silhouette_perimeter)
		areas.append(float(piece.area))
	areas.sort()
	var mean_area := 0.0
	for area in areas:
		mean_area += area
	mean_area = mean_area / maxf(1.0, float(areas.size()))
	var median_area := 0.0
	if not areas.is_empty():
		var mid := areas.size() / 2
		median_area = areas[mid] if areas.size() % 2 == 1 else \
			(areas[mid - 1] + areas[mid]) * 0.5
	return {
		"visible_piece_count": piece_count,
		"mass_count": mass_count,
		"masses_per_visible_piece": float(mass_count) / maxf(1.0,
			float(piece_count)),
		"fused_piece_count": fused_pieces,
		"fused_mass_count": fused_masses,
		"fused_mass_share_pct": 100.0 * float(fused_masses) / maxf(1.0,
			float(mass_count)),
		"largest_piece_mass_count": largest_piece_mass_count,
		"mean_visible_piece_area": mean_area,
		"median_visible_piece_area": median_area,
		"silhouette_perimeter_ratio": outline_sum / maxf(0.001, silhouette_sum),
	}


# =============================================================================
# INSTRUMENT 2 - DELIBERATE COURT vs UNDRAWN HOLE
# =============================================================================
#
# WHY THIS EXISTS
# ---------------
# The blind critic's verdict on the V5 vocabulary pass was literally
# "You cannot tell a park from a hole." The park counter went UP (361 -> 373)
# while the plate lost its civic blocks, because a parcel where a mass failed to
# draw leaves bare ground that the old counter scored identically to an
# intentional civic green. The critic found "a bare green pentagon inked on only
# two of its five edges" where a civic block used to be, and the reverted base
# tree still carries "hollow unfilled parcel outlines" at Stoneshore.
#
# THE DEFINITION - two independent tests, both required
# -----------------------------------------------------
# 1. ROLE. The plan must have assigned this ground a park/green role, recorded
#    at the moment the role was decided (`role` on the render entry), not
#    inferred afterwards from its colour. A green with no owning role record is
#    a HOLE.
# 2. ENCLOSURE. The green's own outline must actually be inked. A deliberate
#    court is drawn as a court - its ring goes into the block-edge layer - so
#    nearly all of its perimeter sits on ink. A residual pocket left where a
#    mass under-filled or was rejected is bounded by whatever happened to
#    survive, so much of its perimeter has no ink on it at all. This is the
#    critic's "inked on only two of its five edges", measured directly.
#
# A green failing EITHER test is a HOLE. Holes are reported separately, with
# their area, and DO NOT COUNT toward the >= 2 parks-per-urban-tile floor of
# docs/map-density-and-port-addendum.md section 2.
#
# A third hole shape has no green at all: a parcel the plan assigned a BUILT
# role whose mass never reached the render arrays (rejected by the dry-land
# guard, the gameplay-collision guard, or a min-area drop). That leaves an inked
# but empty plot. Those are counted as `bare_parcel`s.

## Roles the plan uses to mean "this ground is public green".
const PARK_ROLES := {
	"face_park": true, "street_park": true, "row_pocket": true,
	"accommodation_release": true, "hero_park": true,
}

## Roles that mean "an inner court belonging to the building around it". Already
## excluded from the public-green count by GREEN_KINDS; named here so a
## courtyard is never misfiled as an undrawn hole.
const COURT_ROLES := {"courtyard": true}

## Roles that mean "this ground is DELIBERATELY bare" - a vacant lot, a yard, a
## purposeful void. Bare ground here is the drawing working, not failing.
const VACANT_PARCEL_ROLES := {
	"open_lot": true, "inner_court": true, "enclosed_court": true,
	"accommodation_lot": true, "face_open": true, "face_yard": true,
	"face_none": true, "hero_open": true, "rural_garden": true,
}

## Roles that mean "a mass was supposed to stand on this plot".
const BUILT_PARCEL_ROLES := {
	"core_lot": true, "terrace_lot": true, "core_refine_lot": true,
	"gradient_lot": true, "hamlet_lot": true, "forced_core_lot": true,
	"hero_built": true, "face_built": true, "face_village_built": true,
}

## Fraction of a green's outline that must sit on ink for it to read as a court
## that was drawn as such. A fully inked ring scores 1.00; the critic's pentagon
## "inked on only two of its five edges" scores about 0.40.
const PARK_ENCLOSURE_MIN := 0.75

## How far from an inked segment a perimeter sample may sit and still count as
## inked. Rings are appended vertex-for-vertex from the same polygon, so the
## true distance is 0; this only absorbs float noise and the merge of two
## touching greens into one outline.
const INK_TOLERANCE := 1.5

## A built-role parcel covered by less than this fraction of drawn ink is bare
## ground with an outline round it. Ordinary built parcels run far above this -
## even a loose village cluster covers a third of its face - so the band only
## catches plots where essentially nothing was drawn.
const BARE_PARCEL_MAX_COVER := 0.10

## Parcels smaller than this are clipped remnants, not plots, and are not
## judged. Sits below both face-min-area constants and above the 110-120 u^2
## lot slivers the hamlet and morph passes emit.
const MIN_COUNTED_PARCEL_AREA := 600.0


static func is_park_role(role: String) -> bool:
	return PARK_ROLES.has(role)


static func is_built_parcel_role(role: String) -> bool:
	return BUILT_PARCEL_ROLES.has(role)


## The verdict on ONE merged green space.
##   `role_share` is the fraction of the merged area contributed by entries
##                carrying a park role
##   `enclosure`  is the fraction of the merged outline sitting on ink
## Returns {"deliberate": bool, "reason": String}. `reason` is "" when the green
## is a deliberate court, and otherwise names WHY it is a hole, so a regression
## report can say which failure mode grew.
static func green_verdict(role_share: float, enclosure: float) -> Dictionary:
	var has_role := role_share >= 0.5
	var enclosed := enclosure >= PARK_ENCLOSURE_MIN
	if has_role and enclosed:
		return {"deliberate": true, "reason": ""}
	if not has_role and not enclosed:
		return {"deliberate": false, "reason": "no_role_and_unenclosed"}
	if not has_role:
		return {"deliberate": false, "reason": "no_role"}
	return {"deliberate": false, "reason": "unenclosed"}


## True when a parcel the plan meant to build on ended up as bare ground.
static func parcel_is_bare(role: String, area: float,
		covered_fraction: float) -> bool:
	if not is_built_parcel_role(role):
		return false
	if area < MIN_COUNTED_PARCEL_AREA:
		return false
	return covered_fraction < BARE_PARCEL_MAX_COVER


# --- inked-outline measurement ----------------------------------------------

## Bucket a flat a->b segment array (the fabric's edge layers) into a spatial
## grid so an outline walk only ever tests nearby ink.
static func build_ink_grid(segments: PackedVector2Array,
		cell: float = 32.0) -> Dictionary:
	var grid: Dictionary = {}
	var pairs := segments.size() / 2
	for i in pairs:
		var a := segments[i * 2]
		var b := segments[i * 2 + 1]
		var box := Rect2(a.min(b), (a - b).abs())
		var x0 := floori(box.position.x / cell)
		var x1 := floori((box.position.x + box.size.x) / cell)
		var y0 := floori(box.position.y / cell)
		var y1 := floori((box.position.y + box.size.y) / cell)
		for cx in range(x0, x1 + 1):
			for cy in range(y0, y1 + 1):
				var key := Vector2i(cx, cy)
				if not grid.has(key):
					grid[key] = PackedInt32Array()
				var bucket: PackedInt32Array = grid[key]
				bucket.append(i)
				grid[key] = bucket
	return {"grid": grid, "cell": cell, "segments": segments}


## Fraction of `poly`'s perimeter that sits within INK_TOLERANCE of an inked
## segment. 1.00 = drawn as a court; low = an outline that only exists where
## something else happened to stop.
static func enclosure_fraction(poly: PackedVector2Array, ink: Dictionary,
		tolerance: float = INK_TOLERANCE,
		step: float = OUTLINE_SAMPLE_STEP) -> float:
	if poly.size() < 3:
		return 0.0
	var grid: Dictionary = ink.get("grid", {})
	var cell := float(ink.get("cell", 32.0))
	var segments: PackedVector2Array = ink.get("segments",
		PackedVector2Array())
	var total := 0.0
	var covered := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var length := a.distance_to(b)
		if length <= 0.0001:
			continue
		var samples := maxi(1, ceili(length / step))
		var weight := length / float(samples)
		for s in samples:
			var point := a.lerp(b, (float(s) + 0.5) / float(samples))
			total += weight
			if _point_on_ink(point, grid, cell, segments, tolerance):
				covered += weight
	if total <= 0.0:
		return 0.0
	return covered / total


static func _point_on_ink(point: Vector2, grid: Dictionary, cell: float,
		segments: PackedVector2Array, tolerance: float) -> bool:
	var cx := floori(point.x / cell)
	var cy := floori(point.y / cell)
	var reach := maxi(1, ceili(tolerance / cell))
	for dx in range(-reach, reach + 1):
		for dy in range(-reach, reach + 1):
			var bucket_value: Variant = grid.get(Vector2i(cx + dx, cy + dy))
			if bucket_value == null:
				continue
			var bucket: PackedInt32Array = bucket_value
			for index in bucket:
				var a := segments[index * 2]
				var b := segments[index * 2 + 1]
				if point.distance_to(
						Geometry2D.get_closest_point_to_segment(point, a, b)) \
						<= tolerance:
					return true
	return false
