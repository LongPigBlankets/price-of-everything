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


## G7b REPAIR (break F2) — WHAT MAY CERTIFY A GREEN.
##
## The outward enclosure probe answers only to ink that is itself a COUNTED
## BUILDING. `masses` is the snapshot's mass array (`kind` + `area` + `poly`);
## the returned polygons are exactly the entries `counts_as_building` admits.
## A ring of sub-floor dots is not among them, so it cannot buy a verdict, and
## anything that CAN buy one is charged on every count row of section 2.
static func counted_mass_polys(masses: Array) -> Array:
	var out: Array = []
	for mass_value in masses:
		var mass: Dictionary = mass_value
		if not counts_as_building(str(mass.get("kind", "")),
				float(mass.get("area", 0.0))):
			continue
		out.append(mass.get("poly", PackedVector2Array()))
	return out


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
## G7 REPAIR (break A1). `masses_per_visible_piece` at or above this means at
## least half the drawn masses on this tile are NOT separately visible — one
## silhouette per two buildings.
##
## G7b REPAIR (break F1) — THIS NUMBER NO LONGER GATES ANYTHING. `mass_count`
## is the number of entries the audited code CHOSE TO EMIT, so every ratio
## built on it is a self-declaration: the gauntlet7 adversary re-cut eight
## fused 40x40 masses as ONE entry drawing the identical outer shape (14,792.5
## u² against 14,793.2 u², a delta of 0.6 u²) and the tile went
## `["fabric_fused"] -> []`. Map-wide the same re-cut takes 2191 masses to 1032
## with every silhouette untouched: 51 `fabric_fused` tiles to zero and nine
## tiles FAIL -> PASS, scoring the slab HIGHER than the articulated fabric that
## draws the same picture. `excess_mass_count` is monotone under ADDING
## geometry — which is what the first repair proved — and not under RE-CUTTING
## it, and re-cutting is free.
##
## The ratio is retained as a REPORTED diagnostic because it is the honest
## description of the fabric's own partition. It is no longer evidence.
const FUSED_TILE_MAX := 2.0

## G7b REPAIR (break F9). The articulation gates used to be silent below this
## many drawn masses, which excused 279 of the 395 audited tiles (71%) and
## excused two whole terrain classes BY CONSTRUCTION. The gated numbers below
## are areas of drawn silhouettes, and an area is meaningful at n = 1, so the
## sample floor is gone. The constant is kept only to state that it is no
## longer read by `evaluate()`; a unit test pins that.
const ARTICULATION_MIN_SAMPLE := 5


## =========================================================================
## G7b REPAIR (break F1) — THE GATED ARTICULATION NUMBERS ARE NOW AREAS OF
## DRAWN SILHOUETTES, AND NOTHING THE GATE READS COUNTS ENTRIES
## =========================================================================
##
## The requirement the adversary set: "a slab and eight fused masses score
## alike because they draw alike". Both numbers below are functions of the
## SILHOUETTE SET only — the connected components of the drawn ink and their
## areas — so re-cutting one entry into eight, or eight into one, moves them by
## exactly zero. The clustering that produces them takes the shadow layer and
## the sub-floor crumbs as bridges, so it is the shape the plate fills.
##
## THE COST, STATED. Without the partition a drawing cannot distinguish ONE
## very large building from TWO fused ordinary ones: they are the same ink in
## the same place. So this gate charges both. `single_mass_slab_piece_count` is
## reported every run — the number of oversize silhouettes that hold exactly
## one declared mass — so the false-positive rate of that decision is a
## measured number and not an assumption.
##
## THE CEILING is the area of TWO block-scale masses drawn side by side with
## one accepted alley between them, drawn the way the plate draws them (shadow
## offset, plus the fusion dilation the silhouette carries on each side). A
## silhouette at or above it draws at least as much shape as two separate
## block-scale buildings would; whatever the fabric calls it, the eye is
## reading one object where an articulated fabric shows two. Every term is a
## frozen constant of the drawing: `LARGE_MASS_AREA` (the block-scale cut),
## `FUSION_DILATION` (half the map's narrowest accepted alley) and
## `BLOCK_SHADOW_OFFSET` (the fabric's own shadow).
static func drawn_piece_ceiling_area() -> float:
	var side := sqrt(LARGE_MASS_AREA)
	var alley := 2.0 * FUSION_DILATION
	var width := side + alley + side + BLOCK_SHADOW_OFFSET.x + \
		2.0 * FUSION_DILATION
	var height := side + BLOCK_SHADOW_OFFSET.y + 2.0 * FUSION_DILATION
	return width * height


## G7b REPAIR (breaks A3, F8) — A GROUND-TRUTH DENOMINATOR.
##
## Every parcel number instrument 2 reports is a sum over records the audited
## code emits (break F8: suppressing the empty parcels takes a 64% uncovered
## fraction to 10%, duplicating the covered ones takes it to 45.7%, same
## drawing). `dry_buildable_area` is not one of those records — it is measured
## from terrain, relief and water, none of which the decorative fabric authors.
##
## The share of a tile's dry buildable ground covered by counted building ink
## is therefore a number the fabric cannot manufacture by editing its own
## bookkeeping, and it is what catches PAVING (break A3): a plate laid on
## 3.81u gaps — one hundredth of a unit over the accepted alley — reports a
## perfect fusion ratio while covering 84.6% of its own ground.
##
## The cap is `1 / PACKING_ALLOWANCE`. That is not a new number: this file
## already asserts, in `required_dry_area`, that a complying settlement spends
## about three units of land per unit of building footprint. A tile denser than
## its own audit's model of a settlement is paved.
const PAVED_INK_SHARE_MAX := 1.0 / PACKING_ALLOWANCE


## The smallest area a VISIBLE PIECE may have and still read as a building
## rather than a crumb, derived — not tuned — from three frozen numbers:
##   * `SMALL_MASS_MEDIAN_AREA` (800 u^2), the measured median of a baseline
##     SMALL mass in the frozen v0 histogram, taken as a square;
##   * `BLOCK_SHADOW_OFFSET`, because the plate draws that square with a shadow;
##   * `FUSION_DILATION` on each side, because a silhouette is the dilated union.
## A plate whose MEDIAN visible piece is smaller than one baseline small
## building drawn the way the plate draws it is confetti: the same ink cut into
## more, smaller readable objects.
static func drawn_piece_floor_area() -> float:
	var side := sqrt(SMALL_MASS_MEDIAN_AREA)
	return (side + BLOCK_SHADOW_OFFSET.x + 2.0 * FUSION_DILATION) * \
		(side + BLOCK_SHADOW_OFFSET.y + 2.0 * FUSION_DILATION)


## G7b REPAIR (breaks F1, F6, F9, F10). THE ARTICULATION GATE READS THE DRAWING.
##
## `masses_per_visible_piece` and `piece_mass_count` are still accepted so the
## reported series is continuous, and NEITHER IS READ. What the gate reads:
##
##   largest_visible_piece_area  the area of the biggest silhouette any of this
##                               tile's own masses is part of. Invariant under
##                               re-cutting (F1). Not payable elsewhere: adding
##                               separated buildings cannot shrink it (F6).
##                               Charged wherever the silhouette sits, so
##                               welding a tile's fabric into its neighbours'
##                               amoebas is charged to it too (F10).
##   median_visible_piece_area   the confetti direction, also an area.
##   built_ink_share             counted ink over dry buildable ground — a
##                               denominator the fabric does not author (F8),
##                               and the number that sees minimum-alley paving
##                               (A3).
static func evaluate(tile_class: String, small_count: int, large_count: int,
		green_count: int, dry_buildable_area: float,
		documented_shortfall: bool,
		masses_per_visible_piece: float = 1.0,
		median_visible_piece_area: float = -1.0,
		piece_mass_count: int = 0,
		largest_visible_piece_area: float = -1.0,
		built_ink_share: float = -1.0) -> Dictionary:
	var req := requirements(tile_class)
	var failures: Array[String] = []
	# G7 REPAIR: the gauntlet6 confetti "guard" was mean/median piece area
	# reported BESIDE the count — and `evaluate()` read no articulation number
	# at all, so shattering a plate into four crumbs per building scored a
	# perfect report and passed the gate. Both directions are now gated.
	# G7b REPAIR: and both gated numbers are now areas of drawn silhouettes,
	# with no sample floor in front of them.
	if largest_visible_piece_area >= drawn_piece_ceiling_area():
		failures.append("fabric_slab")
	if median_visible_piece_area >= 0.0 and \
			median_visible_piece_area < drawn_piece_floor_area():
		failures.append("fabric_confetti")
	if built_ink_share >= PAVED_INK_SHARE_MAX:
		failures.append("fabric_paved")
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

## G7 REPAIR (break A3): THE FUSION TEST MUST NOT BE A STEP FUNCTION.
##
## The gauntlet6 instrument answered one question at one dilation, so a plate
## laid entirely on 3.81u gaps — 0.01u over the accepted alley — scored a
## PERFECT report (144 pieces, 1.000 masses/piece, 0 fused) while covering 84.6%
## of its own bounding box, and the same plate at 3.79u collapsed to one piece.
## That is the N2 move: satisfy the metric by paving to just inside its limit.
##
## The repair is a GRADED response. The clustering is run at three dilations —
## half an accepted alley, one accepted alley, and two — and the answer is the
## CURVE, not one point. A fabric separated by real streets barely moves across
## that curve; a fabric paved to the legal minimum collapses between the first
## scale and the last. `fusion_fragility` is exactly that collapse, and it is a
## continuous number with no threshold in it.
##
## The multipliers are derivations, not tuning: 0.5x closes half an accepted
## alley, 1.0x closes exactly one, 2.0x closes two.
const FUSION_SCALES: Array[float] = [0.5, 1.0, 2.0]

## The offset the fabric draws every block SHADOW fill at. Declared here rather
## than imported so this file states the number it measures against; pinned
## equal to `UrbanFabricVisuals.BLOCK_SHADOW_OFFSET` by a unit test.
##
## G7 REPAIR (break A4): the gauntlet6 instrument was handed `block_entries`
## ONLY. The fabric also fills a shadow for every block at this offset, so the
## shape the instrument clustered was strictly smaller than the shape the plate
## draws — 18% of the reported visible pieces existed only because the shadow
## layer was withheld (1259 reported against 1031 as drawn). The audit now feeds
## the real shadow fills in as non-counting BRIDGE shapes.
const BLOCK_SHADOW_OFFSET := Vector2(2.2, 2.8)

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


## Group drawn ink into VISIBLE PIECES.
##
## `shapes` is an array of dictionaries carrying at least `poly` (the drawn
## outline) and `area`, plus an optional `counts` flag (default `true`).
##
## G7 REPAIR (breaks A4 and P5). A shape with `counts == false` is a BRIDGE: it
## joins the pieces it touches and contributes its ink to the silhouette, but it
## adds nothing to `mass_count`. That is what the plate's SHADOW fills are, and
## what a sub-floor crumb below `MIN_COUNTED_MASS_AREA` is. Both are ink a human
## sees and neither is a building, so both must be able to fuse two masses while
## neither may inflate the articulation numerator. Without bridges the
## instrument could be beaten twice over: by withholding the shadow layer, and
## by chaining 119 u^2 crumbs between two masses it still called two pieces.
##
## The return is one dictionary per visible piece:
##   members               indices into `shapes` (bridges included)
##   mass_count            COUNTED masses hidden inside this one silhouette
##   member_count          every shape in it, bridges included
##   area                  summed ink area of the counted masses
##   silhouette            the largest union ring, for tile assignment
##   silhouette_center     centroid of the silhouette bounding box
##   silhouette_area       AREA OF THE UNION, outer rings minus holes. This is
##                         the number a reader means by "how big is this piece";
##                         `area` above is a SUM OF INK and double-counts every
##                         overlap (break A5).
##   silhouette_perimeter  outer perimeter of that union
##   outline_perimeter_sum summed perimeter of the dilated member outlines
##
## `silhouette_perimeter` < `outline_perimeter_sum` exactly when boundary was
## lost to fusion, so their ratio is a second, independent fusion signal that
## does not depend on the piece count at all.
static func visible_pieces(shapes: Array,
		dilation: float = FUSION_DILATION,
		with_silhouette: bool = true) -> Array:
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
		var counted := 0
		var outline_sum := 0.0
		var union: Array = []
		for index in members:
			var shape: Dictionary = shapes[index]
			if bool(shape.get("counts", true)):
				counted += 1
				area += float(shape.get("area", 0.0))
			var grown: PackedVector2Array = dilated[index]
			outline_sum += poly_perimeter(grown)
			if with_silhouette:
				union = _merge_into(union, grown)
		var silhouette := PackedVector2Array()
		var largest_ring := -1.0
		# G7 REPAIR (break A5): the silhouette AREA is the area of the union —
		# every outer ring, minus every hole — not the area of its largest ring
		# and emphatically not the sum of the member ink areas.
		var silhouette_area := 0.0
		var silhouette_perimeter := 0.0
		for piece_value in union:
			var piece: PackedVector2Array = piece_value
			if piece.size() < 3:
				continue
			var piece_area := absf(signed_area(piece))
			if Geometry2D.is_polygon_clockwise(piece):
				silhouette_area -= piece_area  # a clockwise ring is a hole
				continue
			silhouette_perimeter += poly_perimeter(piece)
			silhouette_area += piece_area
			if piece_area > largest_ring:
				largest_ring = piece_area
				silhouette = piece
		var box := _bounds(silhouette)
		pieces.append({
			"members": members,
			"mass_count": counted,
			"member_count": members.size(),
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
## masses disappear into shared silhouettes.
##
## G7 REPAIR (break A5). `mean_visible_piece_area` and
## `median_visible_piece_area` are now the areas of the SILHOUETTES. In
## gauntlet6 they were the SUM of the member ink areas, so four coincident
## masses reported a 6,400 u^2 "piece area" for a 1,916 u^2 shape and the real
## map reported 103,003 u^2 of ink inside a 64,323 u^2 silhouette. The old
## number is still carried, honestly named `*_piece_ink_area`, and their ratio
## (`ink_to_silhouette_ratio`) is now reported: it is exactly the overlap the
## old field hid.
##
## G7 REPAIR (break A2 — NETTING). Every ratio below can be paid for elsewhere:
## at the real baseline 22 crumbs anywhere bought one ten-mass amoeba on all
## five gauntlet6 headline numbers at once. `excess_mass_count` cannot be.
## It is `mass_count - visible_piece_count` — the absolute number of drawn
## masses that are NOT separately visible. Adding a well-separated building adds
## one mass and one piece and moves it by ZERO; adding a crumb that fuses to
## something adds one mass and no piece and moves it by +1; fusing g masses into
## one silhouette moves it by +(g-1). There is no arrangement of new geometry
## that lowers it, so a local fusion cannot be bought off map-wide.
## `pieces_holding_3_or_more`, `_5_or_more`, `_10_or_more` and
## `largest_piece_mass_count` are monotone in the same sense.
static func articulation_summary(pieces: Array) -> Dictionary:
	var piece_count := 0
	var bridge_only_pieces := 0
	var mass_count := 0
	var fused_pieces := 0
	var fused_masses := 0
	var largest_piece_mass_count := 0
	var pieces_ge_3 := 0
	var pieces_ge_5 := 0
	var pieces_ge_10 := 0
	var outline_sum := 0.0
	var silhouette_sum := 0.0
	var ink_total := 0.0
	var silhouette_total := 0.0
	var areas: Array[float] = []
	var ink_areas: Array[float] = []
	# G7b REPAIR (break F1) — THE LABEL-FREE FAMILY. Every number in this block
	# is a function of the silhouette set alone. None of them reads
	# `mass_count`, so re-cutting one entry into eight (or eight into one)
	# moves them by exactly zero.
	var ceiling := drawn_piece_ceiling_area()
	var largest_piece_area := 0.0
	var slab_pieces := 0
	var slab_area := 0.0
	var single_mass_slabs := 0
	var bridge_only_slabs := 0
	var all_silhouette_total := 0.0
	var all_piece_count := 0
	for piece_value in pieces:
		var piece: Dictionary = piece_value
		var members := int(piece.mass_count)
		var drawn_area := float(piece.get("silhouette_area", 0.0))
		# The slab family is taken over EVERY drawn silhouette, bridge-only
		# groups included: a slab made entirely of sub-floor ink is still a slab
		# on the plate, and excluding it would let a candidate hide one by
		# declaring its parts too small to count.
		all_piece_count += 1
		all_silhouette_total += drawn_area
		largest_piece_area = maxf(largest_piece_area, drawn_area)
		if drawn_area >= ceiling:
			slab_pieces += 1
			slab_area += drawn_area
			if members == 1:
				single_mass_slabs += 1
			elif members <= 0:
				bridge_only_slabs += 1
		# A group that holds no COUNTED mass is bridge ink (a shadow fill, a
		# sub-floor crumb chain). It is not a building the eye can count, and
		# admitting it would let a candidate manufacture "visible pieces" out of
		# crumbs. It is reported, not counted.
		if members <= 0:
			bridge_only_pieces += 1
			continue
		piece_count += 1
		mass_count += members
		if members >= 2:
			fused_pieces += 1
			fused_masses += members
		if members >= 3:
			pieces_ge_3 += 1
		if members >= 5:
			pieces_ge_5 += 1
		if members >= 10:
			pieces_ge_10 += 1
		largest_piece_mass_count = maxi(largest_piece_mass_count, members)
		outline_sum += float(piece.outline_perimeter_sum)
		silhouette_sum += float(piece.silhouette_perimeter)
		var silhouette_area := float(piece.get("silhouette_area", 0.0))
		var ink_area := float(piece.area)
		ink_total += ink_area
		silhouette_total += silhouette_area
		areas.append(silhouette_area)
		ink_areas.append(ink_area)
	areas.sort()
	ink_areas.sort()
	return {
		"visible_piece_count": piece_count,
		"bridge_only_piece_count": bridge_only_pieces,
		"mass_count": mass_count,
		"masses_per_visible_piece": float(mass_count) / maxf(1.0,
			float(piece_count)),
		# THE NETTING-PROOF NUMBER. Absolute, monotone, never recoverable.
		"excess_mass_count": maxi(0, mass_count - piece_count),
		"fused_piece_count": fused_pieces,
		"fused_mass_count": fused_masses,
		"fused_mass_share_pct": 100.0 * float(fused_masses) / maxf(1.0,
			float(mass_count)),
		"largest_piece_mass_count": largest_piece_mass_count,
		"pieces_holding_3_or_more": pieces_ge_3,
		"pieces_holding_5_or_more": pieces_ge_5,
		"pieces_holding_10_or_more": pieces_ge_10,
		# The AREA of the drawn silhouettes (the repaired number).
		"mean_visible_piece_area": _mean_of(areas),
		"median_visible_piece_area": _median_of(areas),
		# The gauntlet6 number, kept under an honest name.
		"mean_piece_ink_area": _mean_of(ink_areas),
		"median_piece_ink_area": _median_of(ink_areas),
		# > 1.000 means masses are drawn on top of each other.
		"ink_to_silhouette_ratio": ink_total / maxf(0.001, silhouette_total),
		"total_silhouette_area": silhouette_total,
		"total_ink_area": ink_total,
		"silhouette_perimeter_ratio": outline_sum / maxf(0.001, silhouette_sum),
		# --- THE LABEL-FREE FAMILY (break F1) ---------------------------
		# THE GATED NUMBER. The biggest single object the plate draws.
		"largest_visible_piece_area": largest_piece_area,
		"drawn_piece_ceiling_area": ceiling,
		# Absolute and monotone: a silhouette can only grow when geometry is
		# added, and two silhouettes that merge give a bigger one, so no amount
		# of building elsewhere lowers it.
		"slab_piece_count": slab_pieces,
		"slab_silhouette_area": slab_area,
		"slab_area_share_pct": 100.0 * slab_area / maxf(0.001,
			all_silhouette_total),
		# THE MEASURED FALSE-POSITIVE RATE of refusing to read the partition:
		# oversize silhouettes that hold exactly one declared mass. A drawing
		# cannot tell one big building from two fused ordinary ones, so this
		# gate charges both; this number says how often that costs.
		"single_mass_slab_piece_count": single_mass_slabs,
		"bridge_only_slab_piece_count": bridge_only_slabs,
		# Objects drawn per 10,000 u² of drawn shape. Slabs push it down,
		# confetti pushes it up, and neither direction can be reached by
		# re-labelling.
		"pieces_per_10k_silhouette": 10000.0 * float(all_piece_count) / maxf(
			0.001, all_silhouette_total),
		"all_silhouette_area": all_silhouette_total,
		"all_piece_count": all_piece_count,
	}


static func _mean_of(sorted_values: Array[float]) -> float:
	if sorted_values.is_empty():
		return 0.0
	var total := 0.0
	for value in sorted_values:
		total += value
	return total / float(sorted_values.size())


static func _median_of(sorted_values: Array[float]) -> float:
	if sorted_values.is_empty():
		return 0.0
	var mid := sorted_values.size() / 2
	if sorted_values.size() % 2 == 1:
		return sorted_values[mid]
	return (sorted_values[mid - 1] + sorted_values[mid]) * 0.5


## THE GRADED FUSION RESPONSE (G7 repair, break A3).
##
## Cluster the same shapes at every scale in `FUSION_SCALES` and report the
## curve. `fusion_fragility` is the rise in masses-per-visible-piece between the
## narrowest scale and the widest: how much of this plate's articulation exists
## only because a gap is a hair wider than the metric's limit.
##
##   real streets      fragility ~ 0.0   (widening the question changes nothing)
##   minimum-alley pave fragility huge   (the whole plate collapses at 2x)
##
## There is no threshold in this number. It is reported beside the headline so a
## perfect score at 1.0x that is worthless at 2.0x cannot be quoted alone.
static func fusion_curve(shapes: Array) -> Dictionary:
	var points: Array = []
	var narrow := 0.0
	var wide := 0.0
	for i in FUSION_SCALES.size():
		var scale := FUSION_SCALES[i]
		# `with_silhouette` off: the curve reads counts only, and unioning
		# whole settlements at 2x dilation would cost minutes for numbers this
		# function never looks at.
		var summary := articulation_summary(visible_pieces(shapes,
			FUSION_DILATION * scale, false))
		var ratio := float(summary.masses_per_visible_piece)
		points.append({
			"scale": scale,
			"dilation": FUSION_DILATION * scale,
			"visible_piece_count": int(summary.visible_piece_count),
			"masses_per_visible_piece": ratio,
			"excess_mass_count": int(summary.excess_mass_count),
			"largest_piece_mass_count": int(summary.largest_piece_mass_count),
		})
		if i == 0:
			narrow = ratio
		wide = ratio
	return {
		"points": points,
		"fusion_fragility": wide - narrow,
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


## G7b REPAIR (break F7) — SUB-FLOOR GREENS ARE NOT INVISIBLE.
##
## `MIN_COUNTED_GREEN_AREA` dropped every green under 200 u² BEFORE any verdict,
## so a 1,000 u² hole shattered into six 168 u² shards left no trace in either
## instrument — the same crumb trick the first repair closed for MASSES (a
## sub-floor mass became a bridge) and left open for GREENS.
##
## This merges the sub-floor greens AMONG THEMSELVES — undilated, so the
## returned outline is ground that is actually green — and returns every merged
## shape whose own area reaches the floor. Those outlines are then judged like
## any other green, against the same outward probe.
##
## Undilated on purpose: a dilated union would push the probe start 1.9u
## outward and make shards measure MORE enclosed than they are, which is the
## wrong direction of error for a test that exists to catch dropouts.
##
## It cannot launder (break P3): only sub-floor entries are merged, and merging
## them can only ADD entries to be judged. Nothing is ever removed by it.
static func cluster_subfloor_greens(entries: Array) -> Array:
	var union: Array = []
	for entry_value in entries:
		var entry: Dictionary = entry_value
		var poly: PackedVector2Array = entry.get("poly", PackedVector2Array())
		if poly.size() < 3:
			continue
		union = _merge_into(union, poly)
	var out: Array = []
	for poly_value in union:
		var poly: PackedVector2Array = poly_value
		if poly.size() < 3 or Geometry2D.is_polygon_clockwise(poly):
			continue
		var area := absf(signed_area(poly))
		if area < MIN_COUNTED_GREEN_AREA:
			continue
		out.append({"poly": poly, "area": area})
	return out


static func is_park_role(role: String) -> bool:
	return PARK_ROLES.has(role)


static func is_built_parcel_role(role: String) -> bool:
	return BUILT_PARCEL_ROLES.has(role)


## =========================================================================
## G7 REPAIR — THE ENCLOSURE TEST WAS TAUTOLOGICAL AND HAS BEEN REPLACED
## =========================================================================
##
## Every one of the six park-creation sites in `urban_fabric_visuals.gd` does
## `park_entries.append({poly: P, ...})` and then `_append_ring(_block_edges, P)`
## on THE SAME polygon, and `snapshot.ink_segments` is that ring layer. So the
## gauntlet6 test walked a green's perimeter against an ink set CONTAINING THAT
## GREEN'S OWN RING and could not return anything but 1.000 — which is exactly
## what it reported: n=181, min 1.000, p05 1.000, median 1.000. `role_share` sat
## at 1.000 for the same reason (the role is stamped at the same site), so both
## halves of the verdict were at their ceiling for every sample and
## `park_hole_count == 0` was a STRUCTURAL IDENTITY, not a measurement. The
## instrument could not see the critic's unfilled pentagon because the fabric
## cannot emit a green without its own complete ring. It is the L1 failure
## verbatim: 100% of a polygon constructed to score 100%.
##
## The repair measures what a human means by "enclosed": THE FRACTION OF THE
## GREEN'S PERIMETER THAT HAS DRAWN FABRIC JUST OUTSIDE IT. It walks the
## outline, steps OUTWARD, and asks whether a drawn mass is there. The green's
## own geometry contributes nothing to the answer, so the measurement can fail —
## and on the real map it does.
##
## The setback the fabric GUARANTEES between a parcel boundary and the mass
## inside it. Declared here rather than imported so this file states the number
## it measures against; pinned equal to `UrbanFabricVisuals.PARCEL_MARGIN` by a
## unit test.
const PARCEL_SETBACK := 4.5

## THE BAND, and it is a derivation from the fabric's own constants.
##
## The first attempt used `2 x FUSION_DILATION` (3.8u, one accepted alley) and
## THE MEASUREMENT WAS DEAD ON ARRIVAL: the fabric insets every mass by
## `PARCEL_MARGIN` (4.5u) inside its parcel, so a neighbouring building CANNOT
## legally sit within 3.8u of a green's edge and the median green scored 0.000
## against a control at 0.018 — a test that could barely fire. A band narrower
## than the drawing's own guaranteed setback measures nothing.
##
## The band is therefore the closest a neighbouring building is ALLOWED to be,
## plus the narrowest gap this map calls visible:
##     PARCEL_SETBACK (4.5) + 2 x FUSION_DILATION (3.8) = 8.3u
## Both terms are frozen constants of the drawing. The whole curve either side
## of it is reported every run (`fabric_band_curve`) so the choice of band is
## auditable rather than asserted.
const PARK_FABRIC_BAND := PARCEL_SETBACK + 2.0 * FUSION_DILATION

## The three depths probed within that band, as fractions of it. A single depth
## would be a step function of exactly the kind break A3 punished on instrument
## 1; probing near, mid and far makes the test insensitive to where inside the
## alley the neighbouring wall happens to sit.
const PARK_FABRIC_PROBE_DEPTHS: Array[float] = [0.35, 0.7, 1.0]

## A green with fabric on at least this much of its edge is bounded by the city
## rather than by whatever happened to survive — MORE of its outline faces built
## ground than does not. The critic's pentagon, "inked on only two of its five
## edges", scores about 0.40 and fails.
const PARK_FABRIC_ENCLOSURE_MIN := 0.5

## A green with fabric on essentially ALL of its edge is WRAPPED: the buildings
## close round it. It is not public ground, so it never satisfies the
## public-green floor.
const COURT_FABRIC_ENCLOSURE_MIN := 0.9


## The verdict on ONE drawn green, from geometry alone.
##
## WHAT THIS MEASURES, AND WHAT IT DOES NOT (G7b, break F3)
## -------------------------------------------------------
## `fabric_enclosure` is SURROUNDEDNESS: the fraction of this green's own
## perimeter with a COUNTED BUILDING within one accepted alley outside it.
## Surroundedness is not deliberateness, and the gauntlet7 adversary showed the
## two point opposite ways on this map — deleting a building inside a 3x3 block
## measures 1.000, and a civic green with buildings on one side and streets on
## three measures 0.289. The first repair paid a "deliberate" verdict for the
## first shape and excluded it from the hole count as well as the park count,
## which is the same free exit `kind == "courtyard"` used to give, bought with
## geometry instead of a string: a candidate could raise its park count AND
## lower its hole count by DELETING block interiors.
##
## So this function no longer claims to see intent. It answers one geometric
## question and sorts greens into three buckets, of which exactly ONE is
## evidence of a civic green and the other two are both charged:
##
##   shape "public_green"   bounded by buildings on most of its edge and open
##                          on the rest — counts toward the section-2 floor
##   shape "wrapped_green"  closed in by buildings on essentially all of it —
##                          not public ground, and NOT exempt: it counts as an
##                          UNVERIFIED green exactly as a hole does, so
##                          deleting a block interior cannot improve any number
##   shape "hole"           bounded by nothing — an undrawn dropout
##
## The consequence is stated rather than hidden: a REAL courtyard is now
## reported as unverified green, and a real civic park facing streets on three
## sides is reported as a hole. Both are false in the direction that COSTS a
## candidate. That is the correct direction of error for an instrument whose
## project has already shipped five metrics that certified a visible defect.
##
## NO SELF-DECLARED LABEL REACHES THIS FUNCTION. `kind` and `role` are strings
## written by the very code being audited; in gauntlet6 renaming a residual
## pocket `courtyard` deleted it from both counts and renaming it `face_park`
## promoted it to a park. Neither rename can move this verdict.
##
## Returns {"public", "unverified", "shape", "reason"}.
static func green_verdict(fabric_enclosure: float) -> Dictionary:
	if fabric_enclosure >= COURT_FABRIC_ENCLOSURE_MIN:
		return {"public": false, "unverified": true, "shape": "wrapped_green",
			"reason": "wrapped_by_fabric"}
	if fabric_enclosure >= PARK_FABRIC_ENCLOSURE_MIN:
		return {"public": true, "unverified": false, "shape": "public_green",
			"reason": ""}
	return {"public": false, "unverified": true, "shape": "hole",
		"reason": "no_bounding_fabric"}


## True when a parcel the plan meant to build on ended up as bare ground.
## ROLE-DEPENDENT, and therefore beatable by renaming `face_built` to
## `face_open` at the creation site. Kept for continuity of the reported series;
## `parcel_is_empty()` below is the number that cannot be renamed away.
static func parcel_is_bare(role: String, area: float,
		covered_fraction: float) -> bool:
	if not is_built_parcel_role(role):
		return false
	if area < MIN_COUNTED_PARCEL_AREA:
		return false
	return covered_fraction < BARE_PARCEL_MAX_COVER


## G7 REPAIR (break P4) — THE LABEL-FREE EMPTY-PARCEL TEST.
##
## `parcel_is_bare` reads a role string written by the code being audited, so
## the gauntlet6 report could be cleared by renaming `face_built` to
## `face_open`. This asks the same question of EVERY drawn parcel whatever it
## calls itself: is there an inked outline here with essentially nothing drawn
## inside it? Renaming moves a parcel between the reported sub-buckets and
## leaves this total exactly where it was.
static func parcel_is_empty(area: float, covered_fraction: float) -> bool:
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


# --- fabric-band enclosure (the repaired instrument 2 measurement) ----------

## Bucket an array of drawn polygons into a spatial grid so the outward probes
## below only ever test nearby fabric.
static func build_mass_grid(polys: Array, cell: float = 64.0) -> Dictionary:
	var grid: Dictionary = {}
	for i in polys.size():
		var poly: PackedVector2Array = polys[i]
		if poly.size() < 3:
			continue
		var box := _bounds(poly)
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
	return {"grid": grid, "cell": cell, "polys": polys}


## THE REPAIRED ENCLOSURE MEASUREMENT.
##
## Fraction of `poly`'s perimeter that has a drawn mass within `band` OUTSIDE
## it. For every sample on the outline the walk steps out along the local
## outward normal at each of `PARK_FABRIC_PROBE_DEPTHS` and asks whether that
## ground is inside any polygon in `masses`. The green's own outline is never
## consulted, so — unlike the gauntlet6 test — this can and does return values
## below 1.0 on the real map.
##
## The outward direction is resolved by PROBING, not by winding: the normal that
## lands outside `poly` is the outward one. That is correct on concave outlines,
## where a centroid rule is not.
##
## `masses` may contain `poly` itself; a polygon cannot cover ground outside its
## own outline, so a green never measures itself as its own bounding fabric.
static func mass_band_enclosure(poly: PackedVector2Array, masses: Dictionary,
		band: float = PARK_FABRIC_BAND,
		step: float = OUTLINE_SAMPLE_STEP) -> float:
	if poly.size() < 3:
		return 0.0
	var grid: Dictionary = masses.get("grid", {})
	var cell := float(masses.get("cell", 64.0))
	var polys: Array = masses.get("polys", [])
	var total := 0.0
	var covered := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var length := a.distance_to(b)
		if length <= 0.0001:
			continue
		var edge := (b - a) / length
		var normal := Vector2(-edge.y, edge.x)
		var samples := maxi(1, ceili(length / step))
		var weight := length / float(samples)
		for s in samples:
			var point := a.lerp(b, (float(s) + 0.5) / float(samples))
			total += weight
			# Resolve outward by probe: whichever side is NOT inside the green.
			var outward := normal
			if Geometry2D.is_point_in_polygon(point + normal * 0.05, poly):
				outward = -normal
			var hit := false
			for depth in PARK_FABRIC_PROBE_DEPTHS:
				if _point_in_any_poly(point + outward * (band * depth), grid,
						cell, polys):
					hit = true
					break
			if hit:
				covered += weight
	if total <= 0.0:
		return 0.0
	return covered / total


## Bands the enclosure curve is reported at, as multiples of PARK_FABRIC_BAND:
## one accepted alley, two, four, eight. Instrument 1's step-function failure
## (break A3) applies here too - a single band would be a single point on a
## curve, and a candidate could sit just outside it. The verdict is taken at the
## first band, and the whole curve is reported beside it so that choice is
## visible rather than hidden.
const PARK_BAND_SCALES: Array[float] = [0.5, 1.0, 2.0, 4.0]


## True when `poly` overlaps no drawn mass at all - the ground it stands on is
## unbuilt. Used to place a FAIR negative control: a displaced outline that
## lands inside a building is trivially "surrounded" by that building, which
## says nothing about whether clear ground is bounded by fabric.
static func poly_is_on_clear_ground(poly: PackedVector2Array,
		masses: Dictionary) -> bool:
	if poly.size() < 3:
		return false
	var grid: Dictionary = masses.get("grid", {})
	var cell := float(masses.get("cell", 64.0))
	var polys: Array = masses.get("polys", [])
	var box := _bounds(poly)
	var seen: Dictionary = {}
	var x0 := floori(box.position.x / cell)
	var x1 := floori((box.position.x + box.size.x) / cell)
	var y0 := floori(box.position.y / cell)
	var y1 := floori((box.position.y + box.size.y) / cell)
	for cx in range(x0, x1 + 1):
		for cy in range(y0, y1 + 1):
			var bucket_value: Variant = grid.get(Vector2i(cx, cy))
			if bucket_value == null:
				continue
			var bucket: PackedInt32Array = bucket_value
			for index in bucket:
				if seen.has(index):
					continue
				seen[index] = true
				if not Geometry2D.intersect_polygons(poly,
						polys[index]).is_empty():
					return false
	return true


static func _point_in_any_poly(point: Vector2, grid: Dictionary, cell: float,
		polys: Array) -> bool:
	var bucket_value: Variant = grid.get(Vector2i(floori(point.x / cell),
		floori(point.y / cell)))
	if bucket_value == null:
		return false
	var bucket: PackedInt32Array = bucket_value
	for index in bucket:
		if Geometry2D.is_point_in_polygon(point, polys[index]):
			return true
	return false


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
