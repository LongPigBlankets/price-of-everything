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
