class_name ForestFootprint
extends RefCounted
## Single source of truth for a forest's physical footprint (spec section 1).
## forest_visuals.gd draws the blob; roads-v2 routing and (later) occupancy
## avoid the SAME disc — both must call this so they can never diverge.
##
## A forest covers ~10% of the hex tile (≈19,440 u² of the 194,400 u² hex),
## drawn as one of five shapes (circle / blob / square / rectangle / patch),
## chosen deterministically per instance. shape_for() returns the half-extents
## + rotation + a circumscribing radius; footprint() exposes that radius as the
## disc routing/occupancy avoid (roads add their own FOREST_ROAD_BUFFER on top).

const FOREST_BUILDING_IDS := {"b_015": true, "b_016": true}
const HEX_AREA := 194400.0
const AREA_FRACTION := 0.10
const SHAPE_AREA := HEX_AREA * AREA_FRACTION          # 19,440 u²
const BASE_RADIUS := 78.69                            # sqrt(SHAPE_AREA / PI) — circle/blob
const RECT_ASPECT := 1.6
const SHAPE_KINDS := ["circle", "blob", "square", "rectangle", "patch"]
## Kept for callers that only want a quick disc; equals the circle/blob radius.
const RADIUS := BASE_RADIUS
const TILE_CENTER := Vector2(270, 240)
const HEX_VERTS: Array[Vector2] = [
	Vector2(135, 0), Vector2(405, 0), Vector2(540, 240),
	Vector2(405, 480), Vector2(135, 480), Vector2(0, 240),
]
## forest_visuals uses RIVER_SCREEN_CLEARANCE_PX / camera zoom_max; the main
## camera's zoom_max is 4.0 — bake that in as a constant so the footprint is
## camera-independent and deterministic.
const RIVER_CLEARANCE := 5.0 / 4.0
const RIVER_HALF_WIDTH := 7.5
## Forests gravitate toward neighbouring forested tiles: the centre is pulled up
## to this far toward the shared edge/corner so adjacent forests clump.
const PULL_MAGNITUDE := 105.0
const NEIGHBOUR_MIN := 60.0    # exclude self
const NEIGHBOUR_MAX := 700.0   # ~one tile away (centres are ~480-620 apart)

static func is_forest(building_id: String) -> bool:
	return FOREST_BUILDING_IDS.has(building_id)

## Deterministic disc for one forest instance. river_paths: world-space
## polylines for the tile (RiverVisuals.get_river_polylines() entries for this
## coord, or [] when none). neighbour_forests: world centres of every OTHER
## forested tile — the forest is pulled toward those within one tile so clumps
## meet at shared edges. Mirrors forest_visuals._forest_center exactly.
## Radius circumscribes the drawn shape so roads clear the whole forest.
static func footprint(instance_id: String, tile_id: String, coord: Vector2i, tile_center: Vector2, river_paths: Array, lake: Dictionary, neighbour_forests: Array = []) -> Dictionary:
	var center := _center(instance_id, tile_id, tile_center, river_paths, lake, neighbour_forests)
	var shape := shape_for(instance_id, tile_id, center)
	return {"center": center, "radius": float(shape.radius)}

## Pull a tile centre toward the average direction of nearby forested tiles
## (one-tile radius), so two adjacent forests drift toward their shared edge and
## three toward a shared corner. Returns Vector2.ZERO when isolated.
static func pull_toward(tile_center: Vector2, neighbour_forests: Array) -> Vector2:
	var dir := Vector2.ZERO
	var n := 0
	for c in neighbour_forests:
		var d: Vector2 = (c as Vector2) - tile_center
		var dist := d.length()
		if dist > NEIGHBOUR_MIN and dist < NEIGHBOUR_MAX:
			dir += d / dist
			n += 1
	if n == 0:
		return Vector2.ZERO
	return dir.normalized() * PULL_MAGNITUDE

## Deterministic shape descriptor for one forest instance (shared by the visual
## fill and the routing disc). hw/hh are half-extents in the shape's own frame;
## rot is the rotation; radius circumscribes hw×hh.
static func shape_for(instance_id: String, tile_id: String, center: Vector2) -> Dictionary:
	var h: int = abs(hash("%s|%s|shape" % [instance_id, tile_id]))
	var kind: String = SHAPE_KINDS[h % SHAPE_KINDS.size()]
	var rot := float((h / 7) % 360) * PI / 180.0
	var hw := BASE_RADIUS
	var hh := BASE_RADIUS
	match kind:
		"square":
			hw = sqrt(SHAPE_AREA) * 0.5            # ≈69.7
			hh = hw
		"rectangle":
			hh = sqrt(SHAPE_AREA / RECT_ASPECT) * 0.5   # ≈55.1
			hw = hh * RECT_ASPECT                        # ≈88.2
		"patch":
			hw = sqrt(SHAPE_AREA) * 0.5 * 1.04
			hh = hw
		_:
			hw = BASE_RADIUS
			hh = BASE_RADIUS
	var radius := BASE_RADIUS
	if kind == "square" or kind == "rectangle" or kind == "patch":
		radius = sqrt(hw * hw + hh * hh)
	return {"kind": kind, "center": center, "hw": hw, "hh": hh, "rot": rot, "radius": radius}

static func _center(instance_id: String, tile_id: String, tile_center: Vector2, river_paths: Array, lake: Dictionary, neighbour_forests: Array = []) -> Vector2:
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(hash("%s|%s|center" % [instance_id, tile_id]))
	# Bias the search toward forested neighbours; candidates that fall outside the
	# hex are rejected, so a pulled forest clusters against the shared edge.
	var anchor := tile_center + pull_toward(tile_center, neighbour_forests)
	var best := tile_center
	var best_score := -1.0
	for _i in range(28):
		var angle := rng.randf_range(0.0, TAU)
		# A ~10%-of-tile forest is large, so keep its centre nearer the anchor
		# (the shape is clipped to the hex anyway, but a tighter centre clips less).
		var distance := sqrt(rng.randf()) * rng.randf_range(16.0, 60.0)
		var candidate := anchor + Vector2(cos(angle) * distance * 1.10, sin(angle) * distance * 0.84)
		if not _inside_hex(candidate, tile_center, 40.0):
			continue
		var score := _water_clearance(candidate, river_paths)
		if score > best_score:
			best_score = score
			best = candidate
		if _candidate_ok(candidate, river_paths, lake):
			return candidate
	# Nothing inside the hex satisfied the water clearance from the anchor — fall
	# back to the best candidate, or the un-pulled centre if even that failed.
	return best if best_score >= 0.0 else tile_center

static func _candidate_ok(pos: Vector2, river_paths: Array, lake: Dictionary) -> bool:
	var clearance := 18.0 + RIVER_HALF_WIDTH + RIVER_CLEARANCE
	if _water_clearance(pos, river_paths) < clearance:
		return false
	if lake.is_empty():
		return true
	var rx: float = lake.rx + RIVER_CLEARANCE + 18.0
	var ry: float = lake.ry + RIVER_CLEARANCE + 18.0
	var lc: Vector2 = lake.center
	return Vector2((pos.x - lc.x) / rx, (pos.y - lc.y) / ry).length() >= 1.0

static func _water_clearance(point: Vector2, river_paths: Array) -> float:
	var best := 1e30
	for path_entry in river_paths:
		var pts: PackedVector2Array = path_entry
		for i in range(pts.size() - 1):
			best = minf(best, _dist_to_segment(point, pts[i], pts[i + 1]))
	return best

static func _inside_hex(point: Vector2, tile_center: Vector2, margin: float) -> bool:
	var local := point - tile_center + TILE_CENTER
	var inset := PackedVector2Array()
	for vertex in HEX_VERTS:
		var from_center := vertex - TILE_CENTER
		inset.append(TILE_CENTER + from_center.normalized() * maxf(0.0, from_center.length() - margin))
	return Geometry2D.is_point_in_polygon(local, inset)

static func _dist_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var denom := ab.length_squared()
	if denom <= 0.0001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / denom, 0.0, 1.0)
	return point.distance_to(a + ab * t)
