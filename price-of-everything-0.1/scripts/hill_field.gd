class_name HillField
extends RefCounted
## Deterministic global elevation-field generator: lowlands, hills, mountains.
## Pure logic — no scene access.
##
## v3: ONE continuous field over the whole map (no per-massif islands).
## Level model (band = level + 1):
##   lv -1  budgeted depressions below sea level (max ~100 subtile units, each
##          >= 10 contiguous; never within 200 units of the sea) — darker green
##   lv  0  baseline land (flat-tile colour; most of the map)
##   lv 1-2 lowland swells, allowed everywhere on land (flat tiles cap < lv3)
##   lv 3-6 hill bands (greens -> pale yellow); non-mountain capped < lv7
##   lv 7-9 mountain browns; lv 10 snow
## Rivers no longer carve to zero: the field near a river is clamped to a
## blurred per-tile-type valley cap (mountain ~lv5, hill ~lv4, flat ~lv2,
## sea -> 0), so rivers ride their local band and descend to the sea while
## higher bands pull away from them.
##
## Outputs paint-ordered contour polygons and blocked-subtile masks, BAKED by
## tools/bake_hills.tscn to data/hills_baked.json — the map is hand-painted,
## so the baked shape is canonical and identical every start.

const GEN_VERSION := 10
const STEP := 12.0                  # field sample spacing (world units)
const MARGIN := 300.0               # bbox inflation
## THRESHOLDS[k] is the lower bound of level k-1... band index = number of
## thresholds passed; band 0 = level -1, band 1 = level 0, band 11 = level 10.
const THRESHOLDS: Array[float] = [-0.06, 0.13, 0.27, 0.42, 0.57, 0.72, 0.86, 1.00, 1.14, 1.28, 1.42]
const BLOCK_FIELD := 0.42           # field >= this blocks a subtile (lv 3+)
const TILE_CENTER := Vector2(270, 240)
const HEX_VERTS := [Vector2(135, 0), Vector2(405, 0), Vector2(540, 240), Vector2(405, 480), Vector2(135, 480), Vector2(0, 240)]
const SUBTILE_SIZE := 20.0
const COLS := 27
const ROWS := 24
const SMAX_K := 0.05
const BIN_CELL := 256.0

# type raster codes
const T_VOID := 0
const T_SEA := 1
const T_FLAT := 2
const T_HILL := 3
const T_MTN := 4
const T_LAKE := 5

const FLAT_TYPES := ["rural", "grass", "urban"]
const SEA_TYPES := ["sea", "deep_sea"]

## Hand-placed lakes (the map is hand-painted; edit + re-bake). Each
## contiguous cluster becomes one organic lake with a constant rim level
## (0, 1 or 2) and a river exit to the big outer sea.
const LAKE_TILES := [
	"tile_5_15", "tile_4_16", "tile_3_16",
	"tile_20_13", "tile_20_14", "tile_20_15", "tile_21_16", "tile_21_15", "tile_22_14",
	"tile_25_15", "tile_23_13", "tile_23_12", "tile_21_11",
	"tile_21_6", "tile_21_4", "tile_23_3", "tile_22_2",
]
const RIM_VALUES := [0.06, 0.19, 0.33]   # mid-band field values for lv 0 / 1 / 2

## Regional lowland boosts: tile id -> [radius, extra height]. Raises the
## ambient toward lv2 in hand-picked bland areas.
const LOWLAND_BOOSTS := {"tile_10_11": [1500.0, 0.09]}

## ---- coast ----
## The organic land/sea line stays within ~100 units of the hex limit
## (deviation onto either side). Regional character: jagged on the NW coast
## down to Stoneshore (gulfs + peninsulas), very smooth in the SW, ~20 small
## islands off the SE coast. Sea bands (rendered, not gameplay):
##   shelf  river blue, out to ~300 units from the hex limit
##   -3     slightly darker, the open sea
##   -4/-5/-6  blended rings around deep-sea tiles; -6 = DS navy
const SEA_THRESHOLDS: Array[float] = [-7.6, -6.6, -5.6, -3.4, 0.0]
const ISLAND_TARGET := 20           # tear/sliver capsules, cores 5-10 subtile units
const ESTUARY_R := 170.0            # coast anchors around river mouths

## Hand-authored peninsulas: tile id -> Array of [direction, length, root
## half-width, tip half-width]. Anchored at the tile's most seaward point
## (found via the sea-distance gradient).
const PENINSULAS := {
	"tile_3_19": [
		[Vector2(0.7071, 0.7071), 115.0, 50.0, 32.0],   # south-east finger
		[Vector2(-1.0, 0.0), 115.0, 54.0, 30.0],        # due-west finger
	],
}
const MINI_LAKE_TARGET := 8         # 1-3 subtile coastal ponds on the SE coast

## Tolerated level ranges per tile type, expressed as elevation floors and
## caps (blurred + warped before use, so transitions are wavy ramps rather
## than hex-shaped cliffs):
##   flat  lv -1..2   (floor 0,    cap just under lv3)
##   hill  lv  2..6   (floor 0.29, cap just under lv7)
##   mtn   lv  5..10  (floor 0.74, cap open)
const TYPE_FLOOR := {T_VOID: 0.0, T_SEA: 0.0, T_FLAT: 0.0, T_HILL: 0.29, T_MTN: 0.74, T_LAKE: 0.0}
const TYPE_CAP := {T_VOID: 0.3864, T_SEA: 0.3864, T_FLAT: 0.3864, T_HILL: 0.995, T_MTN: 1.80, T_LAKE: 0.3864}
## River valley floors: within 40 units of a river the field EQUALS this
## (the low end of the local tile type's range); the valley blends back into
## the terrain by 170 units.
const RIVER_CAP := {T_VOID: 0.02, T_SEA: 0.02, T_FLAT: 0.19, T_HILL: 0.48, T_MTN: 0.76, T_LAKE: 0.19}

## level -1 depressions
const DEPRESSION_BUDGET := 100.0    # max total subtile units of lv -1
const DEPRESSION_MIN := 10.0        # min subtile units per depression
const DEPRESSION_SEA_DIST := 200.0
const DEPRESSION_LEVEL := -0.06

## Crest-system tuning per terrain class. Amplitudes are RELIEF ON TOP of the
## type floor (floors are additive). north_bonus raises mountain summits
## toward the map's north edge; nwse_west forces west-side mountain crests
## onto a north-west -> south-east axis.
const HILL_PARAMS := {
	"summit_amp_min": 0.38, "summit_amp_max": 0.55,
	"saddle_amp_min": 0.08, "saddle_amp_max": 0.22,
	"summit_w_min": 110.0, "summit_w_max": 160.0,
	"saddle_w_min": 80.0, "saddle_w_max": 110.0,
	"end_amp": 0.06, "end_w": 55.0,
	"spawn_min": 120.0, "spawn_var": 60.0,
	"spur_prob": 0.7, "spur_ang_min": 30.0, "spur_ang_var": 40.0,
	"sub_prob": 0.35, "pull_mtn": true, "push_flat": true,
	"north_bonus": 0.0, "nwse_west": false,
}
const MTN_PARAMS := {
	"summit_amp_min": 0.32, "summit_amp_max": 0.60,
	"saddle_amp_min": 0.05, "saddle_amp_max": 0.20,
	"summit_w_min": 120.0, "summit_w_max": 180.0,
	"saddle_w_min": 90.0, "saddle_w_max": 120.0,
	"end_amp": 0.05, "end_w": 70.0,
	"spawn_min": 90.0, "spawn_var": 50.0,
	"spur_prob": 0.85, "spur_ang_min": 35.0, "spur_ang_var": 40.0,
	"sub_prob": 0.5, "pull_mtn": false, "push_flat": false,
	"north_bonus": 0.28, "nwse_west": true,
}

# bake-time diagnostics
static var debug_closed := 0
static var debug_open_chains := 0
static var debug_raw_loops := 0

# ---------------------------------------------------------------- public API

## tiles: Vector2i -> tile dict (needs "type" and "id").
## centers: Vector2i -> Vector2 world centre of the tile.
## rivers: Array of PackedVector2Array river polylines (world space).
## lakes: Array of [Vector2 centre, float rx, float ry] source-lake ellipses.
## tile_filter: optional Array of tile ids — restricts to the matching
##   massifs' bounding box (lowland included, depressions skipped). Used by
##   tests for fast deterministic regeneration; the full bake is canonical.
static func generate(tiles: Dictionary, centers: Dictionary, rivers: Array, lakes: Array, seed_base: int, tile_filter: Array = [], include_nav_source: bool = false, nav_source_only: bool = false) -> Dictionary:
	var ctx := {}
	ctx.seed_base = seed_base
	ctx.filtered = not tile_filter.is_empty()
	var lake_coords := {}
	for coord in tiles:
		if str(tiles[coord].get("id", "")) in LAKE_TILES:
			lake_coords[coord] = true
	ctx.lake_coords = lake_coords
	var massif_groups := _find_massifs(tiles, lake_coords)
	if ctx.filtered:
		var kept: Array = []
		for group in massif_groups:
			for coord in group.hills + group.mtn_tiles:
				if str(tiles[coord].get("id", "")) in tile_filter:
					kept.append(group)
					break
		massif_groups = kept

	# global bbox: whole map, or the matched massifs' tiles when filtered
	var bb_min := Vector2(1e9, 1e9)
	var bb_max := Vector2(-1e9, -1e9)
	if ctx.filtered:
		for group in massif_groups:
			for coord in group.hills + group.mtn_tiles:
				bb_min = bb_min.min(centers[coord] - Vector2(290, 260))
				bb_max = bb_max.max(centers[coord] + Vector2(290, 260))
	else:
		for coord in centers:
			bb_min = bb_min.min(centers[coord] - Vector2(290, 260))
			bb_max = bb_max.max(centers[coord] + Vector2(290, 260))
	bb_min -= Vector2(MARGIN, MARGIN)
	bb_max += Vector2(MARGIN, MARGIN)
	ctx.origin = bb_min
	ctx.gw = int(ceil((bb_max.x - bb_min.x) / STEP)) + 1
	ctx.gh = int(ceil((bb_max.y - bb_min.y) / STEP)) + 1

	# full-map extent (independent of filtering) for north bias / west split
	var map_min := Vector2(1e9, 1e9)
	var map_max := Vector2(-1e9, -1e9)
	for coord in centers:
		map_min = map_min.min(centers[coord])
		map_max = map_max.max(centers[coord])
	ctx.map_min = map_min
	ctx.map_max = map_max

	_rasterize_types(ctx, tiles, centers)
	ctx.dt_sea = _chamfer_dt(ctx, [T_SEA, T_VOID])
	_build_type_grids(ctx)
	_build_lake_grid(ctx)

	# global noises (seeded from the base seed only — massif-independent)
	var grng := RandomNumberGenerator.new()
	grng.seed = hash("global|" + str(seed_base))
	ctx.n_mul = _make_noise(grng.randi(), 1.0 / 200.0, 3, 0.55)
	ctx.n_fine = _make_noise(grng.randi(), 1.0 / 55.0, 1, 0.5)
	ctx.n_wx1 = _make_noise(grng.randi(), 1.0 / 140.0, 1, 0.5)
	ctx.n_wx2 = _make_noise(grng.randi(), 1.0 / 55.0, 1, 0.5)
	ctx.n_wy1 = _make_noise(grng.randi(), 1.0 / 140.0, 1, 0.5)
	ctx.n_wy2 = _make_noise(grng.randi(), 1.0 / 55.0, 1, 0.5)
	ctx.n_ridge = _make_ridged_noise(grng.randi(), 1.0 / 90.0)
	ctx.n_low1 = _make_noise(grng.randi(), 1.0 / 700.0, 2, 0.5)
	ctx.n_low2 = _make_noise(grng.randi(), 1.0 / 180.0, 1, 0.5)
	ctx.n_coast = _make_noise(grng.randi(), 1.0 / 42.0, 2, 0.5)

	# regional lowland boosts (resolved from tile ids)
	ctx.low_boosts = []
	for boost_id in LOWLAND_BOOSTS:
		for coord in tiles:
			if str(tiles[coord].get("id", "")) == boost_id and centers.has(coord):
				var spec: Array = LOWLAND_BOOSTS[boost_id]
				ctx.low_boosts.append([centers[coord].x, centers[coord].y, spec[0], spec[1]])
				break

	# lake clusters: constant rim level all around. Lakes do NOT get new
	# rivers — wherever an EXISTING river touches the shore, the river-valley
	# clamp cuts the rim and acts as the exit; lakes with no nearby river
	# (e.g. the south-west ones) simply keep an unbroken rim.
	ctx.lake_clusters = []
	var lake_stats: Array = []
	if not lake_coords.is_empty():
		for cl in _flood_groups(lake_coords):
			var centroid := Vector2.ZERO
			var u_sum := 0.0
			for coord in cl:
				centroid += centers[coord]
				u_sum += _lowland_at(ctx, centers[coord].x, centers[coord].y)
			centroid /= float(cl.size())
			var u_mean := u_sum / float(cl.size())
			var rim_lv := 0 if u_mean < 0.13 else (1 if u_mean < 0.27 else 2)
			var max_r := 0.0
			for coord in cl:
				max_r = maxf(max_r, centroid.distance_to(centers[coord]))
			ctx.lake_clusters.append([centroid.x, centroid.y, max_r + 700.0, RIM_VALUES[rim_lv]])
			# report whether an existing river reaches this lake (its exit)
			var has_exit := false
			for poly in rivers:
				for p in poly:
					for coord2 in cl:
						if centers[coord2].distance_to(p) < 380.0:
							has_exit = true
							break
					if has_exit:
						break
				if has_exit:
					break
			lake_stats.append({"tiles": cl.size(), "rim_lv": rim_lv, "has_exit": has_exit})
	ctx.lake_stats = lake_stats

	# rivers and source lakes (global; existing map rivers only)
	var riv_buf := PackedFloat32Array()
	for poly in rivers:
		for i in range(poly.size() - 1):
			var a: Vector2 = poly[i]
			var b: Vector2 = poly[i + 1]
			if not _seg_near_bbox(a, b, bb_min, bb_max, 220.0):
				continue
			var d := b - a
			var ll := d.length_squared()
			if ll < 1e-6:
				continue
			riv_buf.append_array([a.x, a.y, d.x, d.y, 1.0 / ll])
	ctx.riv_buf = riv_buf
	ctx.lakes = []
	for lk in lakes:
		var lc: Vector2 = lk[0]
		if lc.x > bb_min.x - 360 and lc.x < bb_max.x + 360 and lc.y > bb_min.y - 360 and lc.y < bb_max.y + 360:
			ctx.lakes.append(lk)

	# skeletons from every massif into shared buffers
	ctx.seg_buf = PackedFloat32Array()
	ctx.knolls = PackedFloat32Array()
	ctx.sinks = PackedFloat32Array()
	ctx.rav_buf = PackedFloat32Array()
	ctx.crev_buf = PackedFloat32Array()
	var massif_stats: Array = []
	var massifs: Array = []
	for group in massif_groups:
		var m := _build_massif(ctx, group, tiles, centers, seed_base)
		massifs.append(m)
		massif_stats.append({
			"tiles": m.tile_ids,
			"mtns": m.mtn_ids,
			"knolls": m.knoll_count,
		})
	ctx.massifs = massifs

	# budgeted lv -1 depressions (full bake only)
	ctx.depressions = PackedFloat32Array()   # 8 floats: x y cos sin 1/ra2 1/rb2 depth pad
	var depr_subtiles := 0.0
	if not ctx.filtered:
		depr_subtiles = _place_depressions(ctx)

	# resolve hand-authored peninsulas: anchor at the tile's most seaward point
	ctx.peninsulas = PackedFloat32Array()
	for pid in PENINSULAS:
		for coord in tiles:
			if str(tiles[coord].get("id", "")) != pid or not centers.has(coord):
				continue
			var pc: Vector2 = centers[coord]
			var pgx := clampi(int(round((pc.x - ctx.origin.x) / STEP)), 2, ctx.gw - 3)
			var pgy := clampi(int(round((pc.y - ctx.origin.y) / STEP)), 2, ctx.gh - 3)
			var pgi: int = pgy * ctx.gw + pgx
			var gvx: float = ctx.dt_sea[pgi + 2] - ctx.dt_sea[pgi - 2]
			var gvy: float = ctx.dt_sea[pgi + 2 * ctx.gw] - ctx.dt_sea[pgi - 2 * ctx.gw]
			var seaward := Vector2(-gvx, -gvy)
			seaward = seaward.normalized() if seaward.length_squared() > 0.01 else Vector2(0, 1)
			var p_origin: Vector2 = pc + seaward * maxf(ctx.dt_sea[pgi] - 30.0, 0.0)
			for spec in PENINSULAS[pid]:
				var dvec: Vector2 = (spec[0] as Vector2).normalized() * float(spec[1])
				ctx.peninsulas.append_array([p_origin.x, p_origin.y, dvec.x, dvec.y, 1.0 / (float(spec[1]) * float(spec[1])), float(spec[2]), float(spec[3])])
			break
	_build_coast(ctx, rivers)
	_sample_field(ctx)
	if nav_source_only:
		return {
			"version": GEN_VERSION,
			"nav_source": _nav_source_from_ctx(ctx),
			"grid": [ctx.gw, ctx.gh],
			"field_max": ctx.field_max,
		}
	var polys := _extract_contours(ctx)
	var lake_polys: Array = [] if ctx.filtered else _extract_lake_polys(ctx)
	var sea_polys: Array = [] if ctx.filtered else _extract_sea_polys(ctx)
	var blocked := {}
	for m2 in massifs:
		_collect_blocked(ctx, m2, blocked)
	var result := {
		"version": GEN_VERSION,
		"polys": polys,
		"lakes": lake_polys,
		"sea": sea_polys,
		"lake_stats": ctx.lake_stats,
		"islands": ctx.get("island_count", 0),
		"river_mouths": ctx.get("mouth_count", 0),
		"blocked": blocked,
		"massifs": massif_stats,
		"depression_subtiles": depr_subtiles,
		"grid": [ctx.gw, ctx.gh],
		"field_max": ctx.field_max,
	}
	if include_nav_source:
		result["nav_source"] = _nav_source_from_ctx(ctx)
	if not ctx.filtered:
		result["navgrid"] = _collect_navgrid(ctx)
	return result

## Routing navgrid for roads-v2 (spec 1.1): one byte per 12u lattice cell —
## low nibble = band (0..11, level+1), high nibble = water class
## (0 land, 1 sea/void, 2 lake, 3 river corridor) — plus a water-distance
## byte (units of 4u, clamped 255) for the river-hug cost band. Baked so the
## game/preview never regenerates the field (72 s) to route.
const NAV_WATER_LAND := 0
const NAV_WATER_SEA := 1
const NAV_WATER_LAKE := 2
const NAV_WATER_RIVER := 3
const NAV_RIVER_CORRIDOR := 13.0   # RIVER_BLOCK_RADIUS 10.5 + road half-width

static func _collect_navgrid(ctx: Dictionary) -> Dictionary:
	var gw: int = ctx.gw
	var gh: int = ctx.gh
	var origin: Vector2 = ctx.origin
	var grid: PackedFloat32Array = ctx.grid
	var types: PackedByteArray = ctx.types
	var coast: PackedFloat32Array = ctx.coast_land
	var lake_blur: PackedFloat32Array = ctx.lake_blur
	var riv_bins := _bin_segments(ctx.riv_buf, 5, NAV_RIVER_CORRIDOR + BIN_CELL, origin)
	var cells := PackedByteArray()
	cells.resize(gw * gh)
	var water_mask := PackedByteArray()
	water_mask.resize(gw * gh)
	for gy in gh:
		var y := origin.y + gy * STEP
		for gx in gw:
			var gi := gy * gw + gx
			var t := types[gi]
			var water := NAV_WATER_LAND
			if t == T_VOID or t == T_SEA or coast[gi] < 0.5:
				water = NAV_WATER_SEA
			elif t == T_LAKE or lake_blur[gi] > 0.5:
				water = NAV_WATER_LAKE
			else:
				var x := origin.x + gx * STEP
				var key := int(floor((y - origin.y) / BIN_CELL)) * 100000 + int(floor((x - origin.x) / BIN_CELL))
				if _min_dist_binned(ctx.riv_buf, riv_bins, key, x, y) < NAV_RIVER_CORRIDOR:
					water = NAV_WATER_RIVER
				elif _lake_dist(ctx, x, y) <= 0.0:
					water = NAV_WATER_LAKE   # source lakes sit on land tiles
			var band := 0
			var v := grid[gi]
			for thr in THRESHOLDS:
				if v >= thr:
					band += 1
				else:
					break
			cells[gi] = clampi(band, 0, 11) | (water << 4)
			water_mask[gi] = 1 if water != NAV_WATER_LAND else 0
	var dist := _chamfer_mask(water_mask, gw, gh)
	var dist_q := PackedByteArray()
	dist_q.resize(gw * gh)
	for i in gw * gh:
		dist_q[i] = clampi(int(dist[i] / 4.0), 0, 255)
	return {
		"origin": [origin.x, origin.y],
		"step": STEP,
		"gw": gw,
		"gh": gh,
		"cells_b64": Marshalls.raw_to_base64(cells),
		"dist_b64": Marshalls.raw_to_base64(dist_q),
	}

static func _chamfer_mask(mask: PackedByteArray, gw: int, gh: int) -> PackedFloat32Array:
	var dt := PackedFloat32Array()
	dt.resize(gw * gh)
	for i in gw * gh:
		dt[i] = 0.0 if mask[i] == 1 else 1e9
	var a := STEP
	var b := STEP * 1.41421356
	for j in gh:
		for i in gw:
			var idx := j * gw + i
			var v := dt[idx]
			if i > 0:
				v = minf(v, dt[idx - 1] + a)
			if j > 0:
				v = minf(v, dt[idx - gw] + a)
				if i > 0:
					v = minf(v, dt[idx - gw - 1] + b)
				if i < gw - 1:
					v = minf(v, dt[idx - gw + 1] + b)
			dt[idx] = v
	for j2 in range(gh - 1, -1, -1):
		for i2 in range(gw - 1, -1, -1):
			var idx2 := j2 * gw + i2
			var v2 := dt[idx2]
			if i2 < gw - 1:
				v2 = minf(v2, dt[idx2 + 1] + a)
			if j2 < gh - 1:
				v2 = minf(v2, dt[idx2 + gw] + a)
				if i2 < gw - 1:
					v2 = minf(v2, dt[idx2 + gw + 1] + b)
				if i2 > 0:
					v2 = minf(v2, dt[idx2 + gw - 1] + b)
			dt[idx2] = v2
	return dt

static func _nav_source_from_ctx(ctx: Dictionary) -> Dictionary:
	return {
		"origin": ctx.origin,
		"step": STEP,
		"gw": ctx.gw,
		"gh": ctx.gh,
		"field": ctx.grid,
		"types": ctx.types,
		"coast_land": ctx.coast_land,
		"lake_blur": ctx.lake_blur,
	}

## Blocked-percentage report per hill tile — drives the hand-tuning loop.
static func blocked_report(result: Dictionary) -> String:
	var lines: Array[String] = []
	var keys: Array = result.blocked.keys()
	keys.sort()
	for tile_id in keys:
		var n: int = result.blocked[tile_id].size()
		lines.append("%s: %d/%d subtiles blocked (%.0f%%)" % [tile_id, n, COLS * ROWS, 100.0 * n / float(COLS * ROWS)])
	return "\n".join(lines)

# ------------------------------------------------------------ massif finding

static func _neighbor_offsets(coord: Vector2i) -> Array:
	var odd := coord.x % 2 != 0
	if odd:
		return [Vector2i(0, -1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0)]
	return [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(-1, -1)]

static func _flood_groups(members: Dictionary) -> Array:
	var groups: Array = []
	var seen := {}
	for coord in members:
		if seen.has(coord):
			continue
		var stack: Array = [coord]
		var group: Array = []
		seen[coord] = true
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			group.append(c)
			for off in _neighbor_offsets(c):
				var nb: Vector2i = c + off
				if members.has(nb) and not seen.has(nb):
					seen[nb] = true
					stack.append(nb)
		group.sort()
		groups.append(group)
	groups.sort_custom(func(a, b): return a[0] < b[0])
	return groups

## Massifs: contiguous hill groups merged with every mountain CLUSTER they
## touch; clusters touching no hills are standalone massifs. Lake tiles are
## water — excluded even if the CSV still types them hill/mountain.
static func _find_massifs(tiles: Dictionary, lake_coords: Dictionary = {}) -> Array:
	var hills := {}
	var mtns := {}
	for coord in tiles:
		if lake_coords.has(coord):
			continue
		var t := str(tiles[coord].get("type", ""))
		if t == "hill":
			hills[coord] = true
		elif t == "mountain":
			mtns[coord] = true
	var hill_groups := _flood_groups(hills)
	var clusters := _flood_groups(mtns)
	var group_of := {}
	for gi in hill_groups.size():
		for c in hill_groups[gi]:
			group_of[c] = gi
	var parent: Array[int] = []
	for i in hill_groups.size():
		parent.append(i)
	var cluster_owner: Array[int] = []
	for ci in clusters.size():
		var adj := {}
		for c in clusters[ci]:
			for off in _neighbor_offsets(c):
				var nb: Vector2i = c + off
				if group_of.has(nb):
					adj[group_of[nb]] = true
		if adj.is_empty():
			cluster_owner.append(-1)
		else:
			var keys: Array = adj.keys()
			keys.sort()
			var root: int = _find_root(parent, keys[0])
			for k in keys:
				_union(parent, root, k)
			cluster_owner.append(_find_root(parent, root))
	var merged := {}
	for gi2 in hill_groups.size():
		var root2 := _find_root(parent, gi2)
		if not merged.has(root2):
			merged[root2] = {"hills": [], "clusters": []}
		merged[root2].hills.append_array(hill_groups[gi2])
	var out: Array = []
	for ci2 in clusters.size():
		var owner := cluster_owner[ci2]
		if owner < 0:
			out.append({"hills": [], "clusters": [clusters[ci2]]})
		else:
			merged[_find_root(parent, owner)].clusters.append(clusters[ci2])
	for root3 in merged:
		merged[root3].hills.sort()
		out.append(merged[root3])
	for entry in out:
		var mt: Array = []
		for cl in entry.clusters:
			mt.append_array(cl)
		mt.sort()
		entry["mtn_tiles"] = mt
	out.sort_custom(func(a, b):
		var ka: Vector2i = a.hills[0] if not a.hills.is_empty() else a.mtn_tiles[0]
		var kb: Vector2i = b.hills[0] if not b.hills.is_empty() else b.mtn_tiles[0]
		return ka < kb)
	return out

static func _find_root(parent: Array[int], i: int) -> int:
	while parent[i] != i:
		i = parent[i]
	return i

static func _union(parent: Array[int], a: int, b: int) -> void:
	var ra := _find_root(parent, a)
	var rb := _find_root(parent, b)
	if ra != rb:
		parent[maxi(ra, rb)] = mini(ra, rb)

# ------------------------------------------- type raster + distance transforms

## Scanline-fill every tile hex into the grid (flat-top hexes tessellate, so
## the raster is seam-free by construction — no union-SDF edge cases).
static func _rasterize_types(ctx: Dictionary, tiles: Dictionary, centers: Dictionary) -> void:
	var gw: int = ctx.gw
	var gh: int = ctx.gh
	var origin: Vector2 = ctx.origin
	var types := PackedByteArray()
	types.resize(gw * gh)   # zero-filled = T_VOID
	var deep := PackedByteArray()
	deep.resize(gw * gh)
	for coord in tiles:
		if not centers.has(coord):
			continue
		var t := str(tiles[coord].get("type", ""))
		var code := T_FLAT
		if ctx.lake_coords.has(coord):
			code = T_LAKE
		elif t in SEA_TYPES:
			code = T_SEA
		elif t == "hill":
			code = T_HILL
		elif t == "mountain":
			code = T_MTN
		elif not (t in FLAT_TYPES):
			code = T_FLAT
		var is_deep := t == "deep_sea"
		var c: Vector2 = centers[coord]
		var top := c.y - 240.0
		var j0 := maxi(0, int(ceil((top - origin.y) / STEP)))
		var j1 := mini(gh - 1, int(floor((top + 480.0 - origin.y) / STEP)))
		for j in range(j0, j1 + 1):
			var ly := origin.y + j * STEP - top
			var half := 135.0 * (ly / 240.0) if ly <= 240.0 else 135.0 * ((480.0 - ly) / 240.0)
			var xl := c.x - 135.0 - half
			var xr := c.x + 135.0 + half
			var i0 := maxi(0, int(ceil((xl - origin.x) / STEP)))
			var i1 := mini(gw - 1, int(floor((xr - origin.x) / STEP)))
			for i in range(i0, i1 + 1):
				types[j * gw + i] = code
				if is_deep:
					deep[j * gw + i] = 1
	ctx.types = types
	ctx.deep_mask = deep

## Two-pass chamfer distance transform (world units) to the cells whose type
## is in `targets`.
static func _chamfer_dt(ctx: Dictionary, targets: Array) -> PackedFloat32Array:
	var gw: int = ctx.gw
	var gh: int = ctx.gh
	var types: PackedByteArray = ctx.types
	var dt := PackedFloat32Array()
	dt.resize(gw * gh)
	for i in gw * gh:
		dt[i] = 0.0 if types[i] in targets else 1e9
	var a := STEP
	var b := STEP * 1.41421356
	for j in gh:
		for i in gw:
			var idx := j * gw + i
			var v := dt[idx]
			if i > 0:
				v = minf(v, dt[idx - 1] + a)
			if j > 0:
				v = minf(v, dt[idx - gw] + a)
				if i > 0:
					v = minf(v, dt[idx - gw - 1] + b)
				if i < gw - 1:
					v = minf(v, dt[idx - gw + 1] + b)
			dt[idx] = v
	for j2 in range(gh - 1, -1, -1):
		for i2 in range(gw - 1, -1, -1):
			var idx2 := j2 * gw + i2
			var v2 := dt[idx2]
			if i2 < gw - 1:
				v2 = minf(v2, dt[idx2 + 1] + a)
			if j2 < gh - 1:
				v2 = minf(v2, dt[idx2 + gw] + a)
				if i2 < gw - 1:
					v2 = minf(v2, dt[idx2 + gw + 1] + b)
				if i2 > 0:
					v2 = minf(v2, dt[idx2 + gw - 1] + b)
			dt[idx2] = v2
	return dt

## Per-cell river caps, type floors and type caps, box-blurred so they ramp
## smoothly across tile borders (rivers descend 5 -> 4 -> ... -> 0; hill and
## mountain edges become slopes instead of cliffs). Floors/caps are sampled
## at amplified warp coordinates later, which makes the ramps wavy.
static func _build_type_grids(ctx: Dictionary) -> void:
	var gw: int = ctx.gw
	var gh: int = ctx.gh
	var types: PackedByteArray = ctx.types
	var cap := PackedFloat32Array()
	var fl := PackedFloat32Array()
	var tc := PackedFloat32Array()
	cap.resize(gw * gh)
	fl.resize(gw * gh)
	tc.resize(gw * gh)
	for i in gw * gh:
		cap[i] = RIVER_CAP[types[i]]
		fl[i] = TYPE_FLOOR[types[i]]
		tc[i] = TYPE_CAP[types[i]]
	for pass_i in 2:
		cap = _box_blur(cap, gw, gh, 2)
		fl = _box_blur(fl, gw, gh, 3)
		tc = _box_blur(tc, gw, gh, 3)
	ctx.river_cap = cap
	ctx.floor_grid = fl
	ctx.cap_grid = tc

static func _box_blur(src: PackedFloat32Array, gw: int, gh: int, r: int) -> PackedFloat32Array:
	var tmp := PackedFloat32Array()
	tmp.resize(gw * gh)
	var inv := 1.0 / float(2 * r + 1)
	for j in gh:
		var base := j * gw
		for i in gw:
			var s := 0.0
			for k in range(-r, r + 1):
				s += src[base + clampi(i + k, 0, gw - 1)]
			tmp[base + i] = s * inv
	var dst := PackedFloat32Array()
	dst.resize(gw * gh)
	for j2 in gh:
		for i2 in gw:
			var s2 := 0.0
			for k2 in range(-r, r + 1):
				s2 += tmp[clampi(j2 + k2, 0, gh - 1) * gw + i2]
			dst[j2 * gw + i2] = s2 * inv
	return dst

# ----------------------------------------------------------------- coast

## Regional coast character at a point: returns [warp_scale, jag_amplitude].
## Jagged on the west coast from the north edge down to Stoneshore (~45% of
## map height); very smooth on the SW coast below it; moderate elsewhere.
static func _coast_region(ctx: Dictionary, x: float, y: float) -> Array:
	var span: Vector2 = ctx.map_max - ctx.map_min
	var nx: float = (x - ctx.map_min.x) / maxf(span.x, 1.0)
	var ny: float = (y - ctx.map_min.y) / maxf(span.y, 1.0)
	var jag_w := (1.0 - _sstep(nx, 0.30, 0.48)) * (1.0 - _sstep(ny, 0.45, 0.58))
	var smooth_w := (1.0 - _sstep(nx, 0.35, 0.50)) * _sstep(ny, 0.50, 0.62)
	var se_w := _sstep(nx, 0.55, 0.70) * _sstep(ny, 0.45, 0.60)   # extra gulfs SE
	return [
		1.0 + 1.1 * jag_w - 0.45 * smooth_w + 0.7 * se_w,
		0.05 + 0.15 * jag_w - 0.028 * smooth_w + 0.085 * se_w,
	]

## Builds ctx.coast_land — the organic "landness" field (>= 0.5 is land).
## Blurred land mask sampled at regionally-scaled warp + jag noise, carved by
## estuary kernels at river mouths, plus seeded SE islands.
static func _build_coast(ctx: Dictionary, rivers: Array) -> void:
	var gw: int = ctx.gw
	var gh: int = ctx.gh
	var origin: Vector2 = ctx.origin
	var types: PackedByteArray = ctx.types
	var dt_sea: PackedFloat32Array = ctx.dt_sea
	# blurred land indicator (lakes count as land — they sit inland)
	var ind := PackedFloat32Array()
	ind.resize(gw * gh)
	for i in gw * gh:
		var t := types[i]
		ind[i] = 1.0 if (t == T_FLAT or t == T_HILL or t == T_MTN or t == T_LAKE) else 0.0
	for pass_i in 2:
		ind = _box_blur(ind, gw, gh, 3)
	ctx.coast_blur = ind
	ctx.dt_land = _chamfer_dt(ctx, [T_FLAT, T_HILL, T_MTN, T_LAKE])
	var dt_land: PackedFloat32Array = ctx.dt_land
	# river mouths: polyline endpoints that land on sea cells
	var mouths: Array = []
	for poly in rivers:
		if poly.size() < 2:
			continue
		for ep in [poly[0], poly[poly.size() - 1]]:
			var gx := int(round((ep.x - origin.x) / STEP))
			var gy := int(round((ep.y - origin.y) / STEP))
			if gx < 0 or gy < 0 or gx >= gw or gy >= gh:
				continue
			if types[gy * gw + gx] != T_SEA:
				continue
			var dup := false
			for m in mouths:
				if m.distance_squared_to(ep) < 100.0 * 100.0:
					dup = true
					break
			if not dup:
				mouths.append(ep)
	ctx.mouth_count = mouths.size()
	# islands off the SE coast: bunched around 2-3 anchor points, shaped as
	# tears and slivers oriented away from the mainland ("torn off")
	var irng := RandomNumberGenerator.new()
	irng.seed = hash("islands|" + str(ctx.seed_base))
	var span: Vector2 = ctx.map_max - ctx.map_min
	var anchors: Array = []
	for attempt in 800:
		if anchors.size() >= 3:
			break
		var agx := irng.randi_range(0, gw - 1)
		var agy := irng.randi_range(0, gh - 1)
		var agi := agy * gw + agx
		var ax2 := origin.x + agx * STEP
		var ay2 := origin.y + agy * STEP
		if (ax2 - ctx.map_min.x) / maxf(span.x, 1.0) < 0.55 or (ay2 - ctx.map_min.y) / maxf(span.y, 1.0) < 0.45:
			continue
		if types[agi] != T_SEA or ctx.deep_mask[agi] == 1:
			continue
		if dt_land[agi] < 90.0 or dt_land[agi] > 340.0:
			continue
		var a_clear := true
		for a2 in anchors:
			if (a2 as Vector2).distance_squared_to(Vector2(ax2, ay2)) < 700.0 * 700.0:
				a_clear = false
				break
		if a_clear:
			anchors.append(Vector2(ax2, ay2))
	var island_segs: Array = []   # [ax, ay, dx, dy, iLL, w0, w1]
	for attempt2 in 1500:
		if island_segs.size() >= ISLAND_TARGET or anchors.is_empty():
			break
		var anc: Vector2 = anchors[irng.randi_range(0, anchors.size() - 1)]
		var px := anc.x + irng.randf_range(-430.0, 430.0)
		var py := anc.y + irng.randf_range(-390.0, 390.0)
		var gx2 := int(round((px - origin.x) / STEP))
		var gy2 := int(round((py - origin.y) / STEP))
		if gx2 < 2 or gy2 < 2 or gx2 >= gw - 2 or gy2 >= gh - 2:
			continue
		var gi2 := gy2 * gw + gx2
		if types[gi2] != T_SEA or ctx.deep_mask[gi2] == 1:
			continue
		if dt_land[gi2] < 55.0:
			continue
		var clear := true
		for seg in island_segs:
			if Vector2(px, py).distance_squared_to(Vector2(seg[0], seg[1])) < 95.0 * 95.0:
				clear = false
				break
		if not clear:
			continue
		# orient along the tear-away direction (the dt_land gradient)
		var gdx := dt_land[gi2 + 2] - dt_land[gi2 - 2]
		var gdy := dt_land[gi2 + 2 * gw] - dt_land[gi2 - 2 * gw]
		var ang := atan2(gdy, gdx) if absf(gdx) + absf(gdy) > 1.0 else irng.randf() * TAU
		ang += irng.randf_range(-0.5, 0.5)
		var tear := irng.randf() < 0.6
		var seg_len := (50.0 + irng.randf() * 45.0) if tear else (95.0 + irng.randf() * 65.0)
		var w0 := (36.0 + irng.randf() * 10.0) if tear else (24.0 + irng.randf() * 8.0)
		var w1 := 8.0 if tear else w0 * 0.75
		var dxv := cos(ang) * seg_len
		var dyv := sin(ang) * seg_len
		island_segs.append([px - dxv * 0.5, py - dyv * 0.5, dxv, dyv, 1.0 / (seg_len * seg_len), w0, w1])
	ctx.island_count = island_segs.size()
	var isl_buf := PackedFloat32Array()
	var isl_caps := PackedFloat32Array()
	for seg2 in island_segs:
		isl_buf.append_array([seg2[0], seg2[1], seg2[2], seg2[3], seg2[4]])
		isl_caps.append_array([seg2[0], seg2[1], seg2[2], seg2[3], seg2[4], seg2[5], seg2[6]])
	ctx.island_buf = isl_buf
	ctx.island_caps = isl_caps
	# assemble the landness grid
	var n_wx1: FastNoiseLite = ctx.n_wx1
	var n_wx2: FastNoiseLite = ctx.n_wx2
	var n_wy1: FastNoiseLite = ctx.n_wy1
	var n_wy2: FastNoiseLite = ctx.n_wy2
	var n_coast: FastNoiseLite = ctx.n_coast
	var L := PackedFloat32Array()
	L.resize(gw * gh)
	for gy in gh:
		var y := origin.y + gy * STEP
		for gx in gw:
			var gi := gy * gw + gx
			if dt_sea[gi] > 250.0:
				L[gi] = 1.0   # deep inland — warp cannot reach the coast
				continue
			if dt_land[gi] > 260.0:
				L[gi] = 0.0   # open sea — islands are added below
				continue
			var x := origin.x + gx * STEP
			var reg := _coast_region(ctx, x, y)
			var ws: float = reg[0]
			var wxc := x + (n_wx1.get_noise_2d(x, y) * 26.0 + n_wx2.get_noise_2d(x, y) * 10.0) * ws
			var wyc := y + (n_wy1.get_noise_2d(x, y) * 26.0 + n_wy2.get_noise_2d(x, y) * 10.0) * ws
			var lv := _grid_bilinear(ind, ctx, wxc, wyc)
			lv += reg[1] * n_coast.get_noise_2d(x, y)
			for m2 in mouths:
				var md: float = (m2 as Vector2).distance_squared_to(Vector2(x, y))
				if md < ESTUARY_R * ESTUARY_R:
					var omm := 1.0 - md / (ESTUARY_R * ESTUARY_R)
					lv -= 0.45 * omm * omm
			L[gi] = lv
	_add_capsules(L, ctx.island_caps, gw, gh, origin)
	_add_capsules(L, ctx.get("peninsulas", PackedFloat32Array()), gw, gh, origin)
	# coastal mini lakes (1-3 subtile ponds) just inside the SE coast
	var mrng := RandomNumberGenerator.new()
	mrng.seed = hash("minilakes|" + str(ctx.seed_base))
	var minis: Array = []
	for attempt3 in 500:
		if minis.size() >= MINI_LAKE_TARGET:
			break
		var mgx := mrng.randi_range(2, gw - 3)
		var mgy := mrng.randi_range(2, gh - 3)
		var mgi := mgy * gw + mgx
		var mx := origin.x + mgx * STEP
		var my := origin.y + mgy * STEP
		if (mx - ctx.map_min.x) / maxf(span.x, 1.0) < 0.55 or (my - ctx.map_min.y) / maxf(span.y, 1.0) < 0.50:
			continue
		if types[mgi] != T_FLAT:
			continue
		if dt_sea[mgi] < 60.0 or dt_sea[mgi] > 200.0:
			continue
		var m_clear := true
		for mp in minis:
			if (mp as Vector2).distance_squared_to(Vector2(mx, my)) < 130.0 * 130.0:
				m_clear = false
				break
		if not m_clear:
			continue
		var mr := 26.0 + mrng.randf() * 12.0
		var reach := int(ceil(mr / STEP)) + 1
		for dj in range(-reach, reach + 1):
			for di in range(-reach, reach + 1):
				var jj := mgy + dj
				var ii := mgx + di
				if ii < 0 or jj < 0 or ii >= gw or jj >= gh:
					continue
				var mdx := (ii - mgx) * STEP
				var mdy := (jj - mgy) * STEP
				var q2m := (mdx * mdx + mdy * mdy) / (mr * mr)
				if q2m < 1.0:
					var omm := 1.0 - q2m
					L[jj * gw + ii] -= 0.9 * omm * omm
		minis.append(Vector2(mx, my))
	ctx.mini_lake_count = minis.size()
	ctx.mouths = mouths
	ctx.coast_land = L

## Adds tapered capsule kernels (7 floats: ax ay dx dy iLL w0 w1) to a grid.
static func _add_capsules(L: PackedFloat32Array, buf: PackedFloat32Array, gw: int, gh: int, origin: Vector2) -> void:
	var i := 0
	while i < buf.size():
		var sax := buf[i]
		var say := buf[i + 1]
		var sdx := buf[i + 2]
		var sdy := buf[i + 3]
		var ill := buf[i + 4]
		var w0i := buf[i + 5]
		var w1i := buf[i + 6]
		var pad := maxf(w0i, w1i) + 4.0
		var lo_x := maxi(0, int((minf(sax, sax + sdx) - pad - origin.x) / STEP))
		var hi_x := mini(gw - 1, int((maxf(sax, sax + sdx) + pad - origin.x) / STEP) + 1)
		var lo_y := maxi(0, int((minf(say, say + sdy) - pad - origin.y) / STEP))
		var hi_y := mini(gh - 1, int((maxf(say, say + sdy) + pad - origin.y) / STEP) + 1)
		for gy3 in range(lo_y, hi_y + 1):
			for gx3 in range(lo_x, hi_x + 1):
				var rx3: float = origin.x + gx3 * STEP - sax
				var ry3: float = origin.y + gy3 * STEP - say
				var t3 := clampf((rx3 * sdx + ry3 * sdy) * ill, 0.0, 1.0)
				var ex3 := rx3 - sdx * t3
				var ey3 := ry3 - sdy * t3
				var w3 := w0i + (w1i - w0i) * t3
				var d23 := ex3 * ex3 + ey3 * ey3
				if d23 < w3 * w3:
					var om3 := 1.0 - d23 / (w3 * w3)
					L[gy3 * gw + gx3] += 0.85 * om3 * om3
		i += 7

## Sea bands: one continuous "sea field" cut by SEA_THRESHOLDS into
## land base / shelf / -3 / -4 / -5 / -6 polygons (paint-ordered).
static func _extract_sea_polys(ctx: Dictionary) -> Array:
	var gw: int = ctx.gw
	var gh: int = ctx.gh
	var origin: Vector2 = ctx.origin
	var L: PackedFloat32Array = ctx.coast_land
	var dt_land: PackedFloat32Array = ctx.dt_land
	var deep_blur := PackedFloat32Array()
	deep_blur.resize(gw * gh)
	var dm: PackedByteArray = ctx.deep_mask
	for i in gw * gh:
		deep_blur[i] = float(dm[i])
	for pass_i in 2:
		deep_blur = _box_blur(deep_blur, gw, gh, 3)
	var n_wx1: FastNoiseLite = ctx.n_wx1
	var n_wx2: FastNoiseLite = ctx.n_wx2
	var n_wy1: FastNoiseLite = ctx.n_wy1
	var n_wy2: FastNoiseLite = ctx.n_wy2
	var n_ridge: FastNoiseLite = ctx.n_ridge
	var n_low2: FastNoiseLite = ctx.n_low2
	var mouths: Array = ctx.get("mouths", [])
	var isl_bins := _bin_segments(ctx.island_buf, 5, 460.0, origin)
	var seaf := PackedFloat32Array()
	seaf.resize(gw * gh)
	for gy in gh:
		var y := origin.y + gy * STEP
		for gx in gw:
			var gi := gy * gw + gx
			var base: float = (L[gi] - 0.5) * 6.0
			if L[gi] >= 0.65:
				seaf[gi] = base
				continue
			var x := origin.x + gx * STEP
			var wdx := n_wx1.get_noise_2d(x, y) * 26.0 + n_wx2.get_noise_2d(x, y) * 10.0
			var wdy := n_wy1.get_noise_2d(x, y) * 26.0 + n_wy2.get_noise_2d(x, y) * 10.0
			var dtl := _grid_bilinear(dt_land, ctx, x + wdx, y + wdy)
			# the -3 step fades out near river mouths — estuaries stay shelf
			var shelf_t := _sstep(dtl, 260.0, 360.0)
			if shelf_t > 0.0 and not mouths.is_empty():
				var md := 1e18
				for m3 in mouths:
					md = minf(md, (m3 as Vector2).distance_squared_to(Vector2(x, y)))
				shelf_t *= _sstep(sqrt(md), 240.0, 420.0)
			# deep boundary: strong warp + ridged crevasse fingers
			var dw := _grid_bilinear(deep_blur, ctx, x + wdx * 2.2, y + wdy * 2.2)
			var v_sea: float = base - 2.0 * shelf_t - 3.2 * dw
			var r01: float = (n_ridge.get_noise_2d(x, y) + 1.0) * 0.5
			v_sea -= 1.6 * maxf(0.0, r01 - 0.6) * _sstep(dw, 0.04, 0.30)
			# shallow organic halo around the torn-off islands
			if L[gi] < 0.45 and not ctx.island_buf.is_empty():
				var key_i := int(floor((y - origin.y) / BIN_CELL)) * 100000 + int(floor((x - origin.x) / BIN_CELL))
				var d_isl := _min_dist_binned(ctx.island_buf, isl_bins, key_i, x, y)
				if d_isl < 420.0:
					var halo := _sstep(d_isl, 400.0, 150.0) * clampf(0.7 + 0.6 * (n_low2.get_noise_2d(x, y) + 1.0) * 0.5, 0.0, 1.0)
					v_sea = lerpf(v_sea, -1.6, clampf(halo, 0.0, 1.0))
			seaf[gi] = v_sea
	# fake land frame at the bbox rim so every water contour closes
	for gx4 in gw:
		seaf[gx4] = 3.0
		seaf[(gh - 1) * gw + gx4] = 3.0
	for gy4 in gh:
		seaf[gy4 * gw] = 3.0
		seaf[gy4 * gw + gw - 1] = 3.0
	var loops: Array = []
	for thr in SEA_THRESHOLDS:
		for lp in _marching_squares(ctx, thr, seaf):
			if lp.size() < 6:
				continue
			var smooth := _chaikin(lp)
			var area := _polygon_area(smooth)
			if absf(area) < 400.0:
				continue
			var band := _band_in_grid(ctx, seaf, SEA_THRESHOLDS, smooth)
			loops.append({"b": band, "p": smooth, "a": absf(area)})
	loops.sort_custom(func(a, b): return a.a > b.a)
	for lp2 in loops:
		lp2.erase("a")
	return loops

static func _band_in_grid(ctx: Dictionary, grid: PackedFloat32Array, thresholds: Array, loop: PackedVector2Array) -> int:
	var p0 := loop[0]
	var p1 := loop[mini(2, loop.size() - 1)]
	var mid := (p0 + p1) * 0.5
	var d := (p1 - p0)
	var probe := mid
	if d.length_squared() >= 1e-9:
		var nrm := Vector2(d.y, -d.x).normalized() * 5.0
		probe = (mid + nrm) if Geometry2D.is_point_in_polygon(mid + nrm, loop) else (mid - nrm)
	var v := _grid_bilinear(grid, ctx, probe.x, probe.y)
	var b := 0
	for t in thresholds:
		if v >= t:
			b += 1
		else:
			break
	return b

# ----------------------------------------------------------------- lakes

## Blurred lake indicator (1 inside lake-tile hexes). Sampled at warped
## coords later, its 0.5 contour is the organic lake outline and its value
## drives the constant-rim clamp around the shore.
static func _build_lake_grid(ctx: Dictionary) -> void:
	var gw: int = ctx.gw
	var gh: int = ctx.gh
	var types: PackedByteArray = ctx.types
	var ind := PackedFloat32Array()
	ind.resize(gw * gh)
	for i in gw * gh:
		ind[i] = 1.0 if types[i] == T_LAKE else 0.0
	for pass_i in 2:
		ind = _box_blur(ind, gw, gh, 3)
	ctx.lake_blur = ind

## Organic lake outlines: marching squares at 0.5 over the warp-sampled lake
## indicator (computed only near lake clusters).
static func _extract_lake_polys(ctx: Dictionary) -> Array:
	if ctx.lake_clusters.is_empty():
		return []
	var gw: int = ctx.gw
	var gh: int = ctx.gh
	var origin: Vector2 = ctx.origin
	var lkw := PackedFloat32Array()
	lkw.resize(gw * gh)
	var n_wx1: FastNoiseLite = ctx.n_wx1
	var n_wx2: FastNoiseLite = ctx.n_wx2
	var n_wy1: FastNoiseLite = ctx.n_wy1
	var n_wy2: FastNoiseLite = ctx.n_wy2
	for cl in ctx.lake_clusters:
		var r: float = cl[2]
		var lo_x := maxi(0, int((cl[0] - r - origin.x) / STEP))
		var hi_x := mini(gw - 1, int((cl[0] + r - origin.x) / STEP) + 1)
		var lo_y := maxi(0, int((cl[1] - r - origin.y) / STEP))
		var hi_y := mini(gh - 1, int((cl[1] + r - origin.y) / STEP) + 1)
		for gy in range(lo_y, hi_y + 1):
			var y := origin.y + gy * STEP
			for gx in range(lo_x, hi_x + 1):
				var gi := gy * gw + gx
				if lkw[gi] != 0.0:
					continue
				var x := origin.x + gx * STEP
				var flx := x + (n_wx1.get_noise_2d(x, y) * 26.0 + n_wx2.get_noise_2d(x, y) * 10.0) * 1.7
				var fly := y + (n_wy1.get_noise_2d(x, y) * 26.0 + n_wy2.get_noise_2d(x, y) * 10.0) * 1.7
				lkw[gi] = _grid_bilinear(ctx.lake_blur, ctx, flx, fly)
	var out: Array = []
	for lp in _marching_squares(ctx, 0.5, lkw):
		if lp.size() < 6:
			continue
		var smooth := _chaikin(lp)
		if absf(_polygon_area(smooth)) < 1500.0:
			continue
		out.append({"p": smooth})
	return out

static func _rim_at(ctx: Dictionary, x: float, y: float) -> float:
	var best := 1e18
	var rim := RIM_VALUES[1]
	for cl in ctx.lake_clusters:
		var dx: float = x - cl[0]
		var dy: float = y - cl[1]
		var d := dx * dx + dy * dy
		if d < best:
			best = d
			rim = cl[3]
	return rim

# -------------------------------------------------------------- hex geometry

static func _make_hex(center: Vector2) -> Dictionary:
	var e := PackedFloat32Array()
	for i in 6:
		var a: Vector2 = center + HEX_VERTS[i] - TILE_CENTER
		var b: Vector2 = center + HEX_VERTS[(i + 1) % 6] - TILE_CENTER
		var n := Vector2(b.y - a.y, -(b.x - a.x)).normalized()
		if n.dot(a - center) < 0.0:
			n = -n
		e.append_array([a.x, a.y, n.x, n.y])
	return {"c": center, "e": e}

static func _sd_hex(h: Dictionary, x: float, y: float) -> float:
	var e: PackedFloat32Array = h.e
	var m := -1e9
	for i in 6:
		var d := (x - e[i * 4]) * e[i * 4 + 2] + (y - e[i * 4 + 1]) * e[i * 4 + 3]
		if d > m:
			m = d
	return m

static func _sd_set(hexes: Array, x: float, y: float) -> float:
	var m := 1e9
	for j in hexes.size():
		var h: Dictionary = hexes[j]
		var c: Vector2 = h.c
		var dx := x - c.x
		var dy := y - c.y
		var lower := sqrt(dx * dx + dy * dy) - 272.0
		if lower > m:
			continue
		var d := _sd_hex(h, x, y)
		if d < m:
			m = d
	return m

# ------------------------------------------------------------- massif build

static func _build_massif(ctx: Dictionary, group: Dictionary, tiles: Dictionary, centers: Dictionary, seed_base: int) -> Dictionary:
	var m := {}
	m.coords = group.hills
	m.tile_ids = []
	m.mtn_ids = []
	var hill_hexes: Array = []
	for coord in group.hills:
		m.tile_ids.append(str(tiles[coord].get("id", "")))
		hill_hexes.append(_make_hex(centers[coord]))
	var mtn_clusters: Array = []
	var mtn_hexes: Array = []
	for cl in group.clusters:
		var cl_hexes: Array = []
		for coord in cl:
			m.mtn_ids.append(str(tiles[coord].get("id", "")))
			var h := _make_hex(centers[coord])
			cl_hexes.append(h)
			mtn_hexes.append(h)
		mtn_clusters.append(cl_hexes)
	var flat_hexes: Array = []
	var flat_seen := {}
	for coord in group.hills + group.mtn_tiles:
		for off in _neighbor_offsets(coord):
			var nb: Vector2i = coord + off
			if not tiles.has(nb) or not centers.has(nb) or flat_seen.has(nb):
				continue
			if str(tiles[nb].get("type", "")) in FLAT_TYPES:
				flat_seen[nb] = true
				flat_hexes.append(_make_hex(centers[nb]))
	m.hills = hill_hexes
	m.mtns = mtn_hexes
	m.mtn_clusters = mtn_clusters
	m.flats = flat_hexes
	m.dom = hill_hexes + mtn_hexes

	var all_ids: Array = m.tile_ids + m.mtn_ids
	all_ids.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(",".join(PackedStringArray(all_ids)) + "|" + str(seed_base))
	m.rng = rng
	m.ctx = ctx
	m.knoll_count = 0
	m.skel_pts = PackedVector2Array()

	if not m.hills.is_empty():
		_build_crest_system(ctx, m, m.hills, HILL_PARAMS)
		_place_knolls(ctx, m)
		_place_sinks_and_ravines(ctx, m)
	for cl_hexes in m.mtn_clusters:
		_build_crest_system(ctx, m, cl_hexes, MTN_PARAMS)
	_place_crevices(ctx, m)
	return m

static func _make_noise(s: int, freq: float, octaves: int, gain: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_VALUE
	n.seed = s
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	n.fractal_octaves = octaves
	n.fractal_gain = gain
	return n

static func _make_ridged_noise(s: int, freq: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.seed = s
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	n.fractal_octaves = 2
	n.fractal_gain = 0.55
	return n

static func _seg_near_bbox(a: Vector2, b: Vector2, bb_min: Vector2, bb_max: Vector2, pad: float) -> bool:
	var lo := a.min(b) - Vector2(pad, pad)
	var hi := a.max(b) + Vector2(pad, pad)
	return hi.x >= bb_min.x and lo.x <= bb_max.x and hi.y >= bb_min.y and lo.y <= bb_max.y

# ------------------------------------------------------------------ skeleton

static func _build_crest_system(ctx: Dictionary, m: Dictionary, hexes: Array, p: Dictionary) -> void:
	var rng: RandomNumberGenerator = m.rng
	var mean := Vector2.ZERO
	for h in hexes:
		mean += h.c
	mean /= float(hexes.size())
	var dir := Vector2.RIGHT
	if hexes.size() > 1:
		var sxx := 0.0
		var sxy := 0.0
		var syy := 0.0
		for h in hexes:
			var d: Vector2 = h.c - mean
			sxx += d.x * d.x
			sxy += d.x * d.y
			syy += d.y * d.y
		var ang := 0.5 * atan2(2.0 * sxy, sxx - syy)
		dir = Vector2(cos(ang), sin(ang))
	else:
		var a := rng.randf() * TAU
		dir = Vector2(cos(a), sin(a))
	# west-side mountain ranges run north-west -> south-east; east keeps PCA
	if p.get("nwse_west", false):
		var map_min: Vector2 = ctx.map_min
		var map_max: Vector2 = ctx.map_max
		if mean.x < map_min.x + (map_max.x - map_min.x) * 0.55:
			dir = Vector2(1, 1).normalized()
	if not m.has("pca_ang"):
		m.pca_ang = dir.angle()

	var ordered: Array = hexes.duplicate()
	ordered.sort_custom(func(a, b): return (a.c - mean).dot(dir) < (b.c - mean).dot(dir))

	var ctrl: Array = []
	if ordered.size() == 1:
		var c: Vector2 = ordered[0].c
		ctrl.append(_place_ctrl(m, c - dir * 150.0, p))
		ctrl.append(_place_ctrl(m, c, p))
		ctrl.append(_place_ctrl(m, c + dir * 150.0, p))
	else:
		for i in ordered.size():
			ctrl.append(_place_ctrl(m, ordered[i].c, p))
			if i < ordered.size() - 1:
				var c2: Vector2 = ordered[i + 1].c
				var c1: Vector2 = ordered[i].c
				var t := (c2 - c1).normalized()
				var perp := Vector2(-t.y, t.x)
				ctrl.append((c1 + c2) * 0.5 + perp * (rng.randf() - 0.5) * 300.0)

	var crest := _catmull_rom(ctrl, 10)
	var head_dir: Vector2 = (crest[0] - crest[1]).normalized()
	var tail_dir: Vector2 = (crest[crest.size() - 1] - crest[crest.size() - 2]).normalized()
	var cpts: Array = []
	for e in [3, 2, 1]:
		cpts.append(crest[0] + head_dir * 50.0 * e)
	cpts.append_array(crest)
	for e2 in [1, 2, 3]:
		cpts.append(crest[crest.size() - 1] + tail_dir * 50.0 * e2)
	var n := cpts.size()

	var amp_nodes: Array = [[0, p.end_amp]]
	var wid_nodes: Array = [[0, p.end_w]]
	var y_span: float = maxf(ctx.map_max.y - ctx.map_min.y, 1.0)
	for j in ctrl.size():
		var idx := 3 + j * 10
		if j % 2 == 0:
			var amp: float = rng.randf_range(p.summit_amp_min, p.summit_amp_max)
			# taller peaks toward the map's north edge
			var north_t: float = 1.0 - clampf((ctrl[j][1] - ctx.map_min.y) / y_span, 0.0, 1.0)
			amp += float(p.north_bonus) * north_t
			amp_nodes.append([idx, amp])
			wid_nodes.append([idx, rng.randf_range(p.summit_w_min, p.summit_w_max)])
		else:
			amp_nodes.append([idx, rng.randf_range(p.saddle_amp_min, p.saddle_amp_max)])
			wid_nodes.append([idx, rng.randf_range(p.saddle_w_min, p.saddle_w_max)])
	amp_nodes.append([n - 1, p.end_amp])
	wid_nodes.append([n - 1, p.end_w])
	var camp := _interp_nodes(amp_nodes, n)
	var cwid := _interp_nodes(wid_nodes, n)

	_add_poly_segs(ctx, cpts, camp, cwid)
	for pp in cpts:
		m.skel_pts.append(pp)

	var side := 1 if rng.randf() < 0.5 else -1
	var acc := 0.0
	var next_spawn: float = p.spawn_min + rng.randf() * p.spawn_var
	for ci in range(4, n - 4):
		acc += cpts[ci].distance_to(cpts[ci - 1])
		if acc < next_spawn:
			continue
		acc = 0.0
		next_spawn = p.spawn_min + rng.randf() * p.spawn_var
		var do_spawn: bool = rng.randf() < p.spur_prob
		var tang: Vector2 = (cpts[ci + 1] - cpts[ci - 1])
		var t_ang := atan2(tang.y, tang.x)
		if do_spawn:
			_grow_spur(ctx, m, cpts[ci], t_ang + side * deg_to_rad(p.spur_ang_min + rng.randf() * p.spur_ang_var), 0.85 * camp[ci], 0.8 * cwid[ci], 0, p)
		if rng.randf() >= 0.15:
			side = -side

static func _place_ctrl(m: Dictionary, c: Vector2, p: Dictionary) -> Vector2:
	var rng: RandomNumberGenerator = m.rng
	var pt := c + Vector2((rng.randf() - 0.5) * 200.0, (rng.randf() - 0.5) * 200.0)
	if p.pull_mtn and not m.mtns.is_empty():
		var best := 1e18
		var best_c := Vector2.ZERO
		for h in m.mtns:
			var d: float = pt.distance_squared_to(h.c)
			if d < best:
				best = d
				best_c = h.c
		if best < 700.0 * 700.0:
			pt += (best_c - pt).normalized() * 140.0
	if p.push_flat and not m.flats.is_empty():
		var sd_f := _sd_set(m.flats, pt.x, pt.y)
		if sd_f < 240.0:
			var best2 := 1e18
			var best_c2 := Vector2.ZERO
			for h2 in m.flats:
				var d2: float = pt.distance_squared_to(h2.c)
				if d2 < best2:
					best2 = d2
					best_c2 = h2.c
			var away := (pt - best_c2).normalized()
			pt += away * (240.0 - sd_f) * 0.45
	return pt

static func _grow_spur(ctx: Dictionary, m: Dictionary, origin: Vector2, base_ang: float, a0: float, w0: float, depth: int, p: Dictionary) -> void:
	var rng: RandomNumberGenerator = m.rng
	var snap_len: int = m.skel_pts.size()
	var nseg := (3 + rng.randi_range(0, 2)) if depth == 0 else (2 + rng.randi_range(0, 1))
	var drift := deg_to_rad(5.0 + rng.randf() * 7.0) * (1.0 if rng.randf() < 0.5 else -1.0)
	var pts: Array = [origin]
	var cur_ang := base_ang
	for s in nseg:
		if s > 0:
			cur_ang += drift + (rng.randf() - 0.5) * deg_to_rad(30.0)
		var seg_len := (60.0 + rng.randf() * 50.0) if depth == 0 else (60.0 + rng.randf() * 30.0)
		var nxt: Vector2 = pts[pts.size() - 1] + Vector2(cos(cur_ang), sin(cur_ang)) * seg_len
		if _near_skel(m, nxt, snap_len, 70.0, origin):
			break
		if _dist_to_rivers(ctx, nxt) < 60.0:
			break
		if not m.flats.is_empty() and _sd_set(m.flats, nxt.x, nxt.y) < -130.0:
			break
		var sd_dom := _sd_set(m.dom, nxt.x, nxt.y)
		if sd_dom > 150.0:
			break
		pts.append(nxt)
	if pts.size() < 2:
		return
	var alen: Array[float] = [0.0]
	for i in range(1, pts.size()):
		alen.append(alen[i - 1] + pts[i].distance_to(pts[i - 1]))
	var total: float = maxf(alen[alen.size() - 1], 1.0)
	var amp: Array[float] = []
	var wid: Array[float] = []
	for j in pts.size():
		var t: float = alen[j] / total
		amp.append(maxf(0.15, a0 * pow(1.0 - t, 1.4)))
		wid.append(w0 + (35.0 - w0) * t)
	_add_poly_segs(ctx, pts, amp, wid)
	for pp in pts:
		m.skel_pts.append(pp)
	if depth == 0:
		for j2 in range(1, pts.size() - 1):
			if alen[j2] / total < 0.4:
				continue
			if rng.randf() < float(p.sub_prob):
				var pd: Vector2 = pts[j2 + 1] - pts[j2 - 1]
				var p_ang := atan2(pd.y, pd.x)
				var sgn := 1.0 if rng.randf() < 0.5 else -1.0
				_grow_spur(ctx, m, pts[j2], p_ang + sgn * deg_to_rad(35.0 + rng.randf() * 30.0), amp[j2] * 0.75, wid[j2] * 0.7, 1, p)

static func _place_knolls(ctx: Dictionary, m: Dictionary) -> void:
	var rng: RandomNumberGenerator = m.rng
	for h in m.hills:
		var want := 1 + (1 if rng.randf() < 0.5 else 0)
		var got := 0
		for att in 8:
			if got >= want:
				break
			var kx: float = h.c.x + (rng.randf() - 0.5) * 460.0
			var ky: float = h.c.y + (rng.randf() - 0.5) * 400.0
			if _sd_set(m.hills, kx, ky) > -30.0:
				continue
			var kd2 := 1e18
			for sp in m.skel_pts:
				var dd: float = (kx - sp.x) * (kx - sp.x) + (ky - sp.y) * (ky - sp.y)
				if dd < kd2:
					kd2 = dd
			var kd: float = sqrt(kd2)
			if kd < 90.0 or kd > 260.0:
				continue
			var ea := 60.0 + rng.randf() * 70.0
			var eb := ea * (0.65 + rng.randf() * 0.35)
			var th: float = m.pca_ang + (rng.randf() - 0.5) * deg_to_rad(50.0)
			ctx.knolls.append_array([kx, ky, cos(th), sin(th), 1.0 / (ea * ea), 1.0 / (eb * eb), 0.30 + rng.randf() * 0.20])
			got += 1
			m.knoll_count += 1

static func _place_sinks_and_ravines(ctx: Dictionary, m: Dictionary) -> void:
	var rng: RandomNumberGenerator = m.rng
	var hills: Array = m.hills
	var sink_n := maxi(1, int(ceil(hills.size() * 0.7)))
	for s in sink_n:
		var hh: Dictionary = hills[rng.randi_range(0, hills.size() - 1)]
		var r := 60.0 + rng.randf() * 80.0
		ctx.sinks.append_array([hh.c.x + (rng.randf() - 0.5) * 460.0, hh.c.y + (rng.randf() - 0.5) * 400.0, r * r, 0.12 + rng.randf() * 0.25])
	var rav_n := maxi(1, hills.size() / 3)
	for rv in rav_n:
		var hr: Dictionary = hills[rng.randi_range(0, hills.size() - 1)]
		var st := Vector2(hr.c.x + (rng.randf() - 0.5) * 440.0, hr.c.y + (rng.randf() - 0.5) * 380.0)
		var ra := rng.randf() * TAU
		var rl := 380.0 + rng.randf() * 220.0
		var rdir := Vector2(cos(ra), sin(ra))
		var perp := Vector2(-rdir.y, rdir.x)
		var mid := st + perp * (rng.randf() - 0.5) * 240.0
		var rpts := _catmull_rom([st - rdir * rl, mid, st + rdir * rl], 10)
		_append_carve_segs(ctx.rav_buf, rpts)

static func _place_crevices(ctx: Dictionary, m: Dictionary) -> void:
	var rng: RandomNumberGenerator = m.rng
	for cl_hexes in m.mtn_clusters:
		for h in cl_hexes:
			for k in 3:
				var probe := Vector2(h.c.x + (rng.randf() - 0.5) * 440.0, h.c.y + (rng.randf() - 0.5) * 400.0)
				var best := 1e18
				var near := Vector2.ZERO
				for sp in m.skel_pts:
					var dd := probe.distance_squared_to(sp)
					if dd < best:
						best = dd
						near = sp
				var dir := (probe - near)
				if dir.length_squared() < 1.0:
					var a := rng.randf() * TAU
					dir = Vector2(cos(a), sin(a))
				dir = dir.normalized()
				var start := near + dir * 30.0
				var length := 180.0 + rng.randf() * 140.0
				var perp := Vector2(-dir.y, dir.x)
				var mid := start + dir * length * 0.5 + perp * (rng.randf() - 0.5) * 90.0
				var cpts := _catmull_rom([start, mid, start + dir * length], 8)
				_append_carve_segs(ctx.crev_buf, cpts)

static func _append_carve_segs(buf: PackedFloat32Array, pts: Array) -> void:
	for i in range(pts.size() - 1):
		var d: Vector2 = pts[i + 1] - pts[i]
		var ll := d.length_squared()
		if ll < 1e-6:
			continue
		buf.append_array([pts[i].x, pts[i].y, d.x, d.y, 1.0 / ll])

static func _near_skel(m: Dictionary, p: Vector2, upto: int, rad: float, origin: Vector2) -> bool:
	var r2 := rad * rad
	var pts: PackedVector2Array = m.skel_pts
	for i in upto:
		var sp := pts[i]
		if sp.distance_squared_to(origin) < 19600.0:
			continue
		if sp.distance_squared_to(p) < r2:
			return true
	return false

static func _dist_to_rivers(ctx: Dictionary, p: Vector2) -> float:
	var buf: PackedFloat32Array = ctx.riv_buf
	var best := 1e18
	var i := 0
	while i < buf.size():
		var rx := p.x - buf[i]
		var ry := p.y - buf[i + 1]
		var t := clampf((rx * buf[i + 2] + ry * buf[i + 3]) * buf[i + 4], 0.0, 1.0)
		var ex := rx - buf[i + 2] * t
		var ey := ry - buf[i + 3] * t
		var d := ex * ex + ey * ey
		if d < best:
			best = d
		i += 5
	for lk in ctx.lakes:
		var lc: Vector2 = lk[0]
		var q := Vector2((p.x - lc.x) / maxf(lk[1], 1.0), (p.y - lc.y) / maxf(lk[2], 1.0)).length()
		var approx := (q - 1.0) * minf(lk[1], lk[2])
		if approx < 0.0:
			return 0.0
		best = minf(best, approx * approx)
	return sqrt(best)

static func _add_poly_segs(ctx: Dictionary, pts: Array, amp: Array, wid: Array) -> void:
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var d: Vector2 = pts[i + 1] - a
		var ll := d.length_squared()
		if ll < 1e-6:
			continue
		ctx.seg_buf.append_array([a.x, a.y, d.x, d.y, 1.0 / ll, amp[i], amp[i + 1] - amp[i], wid[i], wid[i + 1] - wid[i]])

static func _catmull_rom(pts: Array, per: int) -> Array:
	var out: Array = []
	for i in range(pts.size() - 1):
		var p0: Vector2 = pts[maxi(0, i - 1)]
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[i + 1]
		var p3: Vector2 = pts[mini(pts.size() - 1, i + 2)]
		for t in per:
			var u := float(t) / float(per)
			var u2 := u * u
			var u3 := u2 * u
			out.append(0.5 * (2.0 * p1 + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u3))
	out.append(pts[pts.size() - 1])
	return out

static func _interp_nodes(nodes: Array, len_total: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(len_total)
	for ni in range(nodes.size() - 1):
		var i0: int = nodes[ni][0]
		var v0: float = nodes[ni][1]
		var i1: int = nodes[ni + 1][0]
		var v1: float = nodes[ni + 1][1]
		for i in range(i0, mini(i1 + 1, len_total)):
			var t := 0.0 if i1 == i0 else float(i - i0) / float(i1 - i0)
			var tt := t * t * (3.0 - 2.0 * t)
			out[i] = v0 + (v1 - v0) * tt
	return out

# ----------------------------------------------------------- lv -1 depressions

## Budgeted sub-sea-level basins on flat land: never near sea/rivers/skeletons,
## each footprint >= DEPRESSION_MIN subtile units, total <= DEPRESSION_BUDGET.
## Footprints are rasterized against the actual lowland noise at placement, so
## the budget is enforced by construction.
static func _place_depressions(ctx: Dictionary) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("depressions|" + str(ctx.seed_base))
	var gw: int = ctx.gw
	var gh: int = ctx.gh
	var origin: Vector2 = ctx.origin
	var types: PackedByteArray = ctx.types
	var dt_sea: PackedFloat32Array = ctx.dt_sea
	var seg_bins := _bin_segments(ctx.seg_buf, 9, 280.0, origin)
	var total := 0.0
	var placed: Array = []
	for attempt in 400:
		if total >= DEPRESSION_BUDGET - DEPRESSION_MIN:
			break
		var gx := rng.randi_range(0, gw - 1)
		var gy := rng.randi_range(0, gh - 1)
		var gi := gy * gw + gx
		if types[gi] != T_FLAT:
			continue
		var x := origin.x + gx * STEP
		var y := origin.y + gy * STEP
		var ra := 110.0 + rng.randf() * 50.0
		var rb := ra * (0.7 + rng.randf() * 0.3)
		var depth := 0.30 + rng.randf() * 0.10
		var th := rng.randf() * TAU
		if dt_sea[gi] < DEPRESSION_SEA_DIST + ra + 40.0:
			continue
		if _dist_to_rivers(ctx, Vector2(x, y)) < ra + 120.0:
			continue
		var key := int(floor((y - origin.y) / BIN_CELL)) * 100000 + int(floor((x - origin.x) / BIN_CELL))
		if seg_bins.has(key):
			continue   # too close to a hill/mountain skeleton
		if ctx.floor_grid[gi] > 0.02:
			continue   # type floor (blurred hill/mtn ramp) would distort the basin
		var ring_flat := true
		for rp in 8:
			var rang := TAU * rp / 8.0
			var rx2 := x + cos(rang) * (ra + 160.0)
			var ry2 := y + sin(rang) * (ra + 160.0)
			var rgx := int(round((rx2 - origin.x) / STEP))
			var rgy := int(round((ry2 - origin.y) / STEP))
			if rgx < 0 or rgy < 0 or rgx >= gw or rgy >= gh or types[rgy * gw + rgx] != T_FLAT:
				ring_flat = false
				break
		if not ring_flat:
			continue
		# rasterize candidate footprint against the lowland noise
		var ct := cos(th)
		var st := sin(th)
		var iea2 := 1.0 / (ra * ra)
		var ieb2 := 1.0 / (rb * rb)
		var cells := 0
		var reach := int(ceil(ra / STEP)) + 1
		var sea_ok := true
		for dj in range(-reach, reach + 1):
			for di in range(-reach, reach + 1):
				var jj := gy + dj
				var ii := gx + di
				if ii < 0 or jj < 0 or ii >= gw or jj >= gh:
					continue
				var px := origin.x + ii * STEP
				var py := origin.y + jj * STEP
				var dxp := px - x
				var dyp := py - y
				var u := ct * dxp + st * dyp
				var vv := -st * dxp + ct * dyp
				var q2 := u * u * iea2 + vv * vv * ieb2
				if q2 >= 1.0:
					continue
				var om := 1.0 - q2
				var low := _lowland_at(ctx, px, py)
				if low - depth * om * om < DEPRESSION_LEVEL:
					if types[jj * gw + ii] != T_FLAT or dt_sea[jj * gw + ii] < DEPRESSION_SEA_DIST:
						sea_ok = false
					cells += 1
		var subtiles := cells * (STEP * STEP) / (SUBTILE_SIZE * SUBTILE_SIZE)
		if not sea_ok or subtiles < DEPRESSION_MIN or total + subtiles > DEPRESSION_BUDGET:
			continue
		placed.append([x, y, ct, st, iea2, ieb2, depth, 0.0])
		total += subtiles
	for d in placed:
		ctx.depressions.append_array(d)
	return total

## Baseline lowland undulation: inland sits at lv1 with frequent lv2 swells
## and only SPARSE lv0 hollows — lv0 mostly appears as the coastal ring (the
## sea falloff applied by the caller). Regional boosts (LOWLAND_BOOSTS) lift
## hand-picked bland areas toward lv2.
static func _lowland_at(ctx: Dictionary, x: float, y: float) -> float:
	var u: float = 0.18 + 0.10 * ctx.n_low1.get_noise_2d(x, y) + 0.05 * ctx.n_low2.get_noise_2d(x, y)
	for b in ctx.get("low_boosts", []):
		var dx: float = x - b[0]
		var dy: float = y - b[1]
		u += b[3] * (1.0 - _sstep(sqrt(dx * dx + dy * dy), b[2] * 0.4, b[2]))
	return clampf(u, 0.075, 0.40)

# ------------------------------------------------------------ field sampling

static func _sstep(x: float, a: float, b: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

static func _smax(a: float, b: float, k: float) -> float:
	var h := clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return a + (b - a) * h + k * h * (1.0 - h)

static func _bin_segments(buf: PackedFloat32Array, stride: int, inflate: float, origin: Vector2) -> Dictionary:
	var bins := {}
	var seg_i := 0
	var i := 0
	while i < buf.size():
		var ax := buf[i]
		var ay := buf[i + 1]
		var bx := ax + buf[i + 2]
		var by := ay + buf[i + 3]
		var lo_x := int(floor((minf(ax, bx) - inflate - origin.x) / BIN_CELL))
		var hi_x := int(floor((maxf(ax, bx) + inflate - origin.x) / BIN_CELL))
		var lo_y := int(floor((minf(ay, by) - inflate - origin.y) / BIN_CELL))
		var hi_y := int(floor((maxf(ay, by) + inflate - origin.y) / BIN_CELL))
		for cy in range(lo_y, hi_y + 1):
			for cx in range(lo_x, hi_x + 1):
				var key := cy * 100000 + cx
				if not bins.has(key):
					bins[key] = PackedInt32Array()
				bins[key].append(seg_i)
		seg_i += 1
		i += stride
	return bins

static func _sample_field(ctx: Dictionary) -> void:
	var gw: int = ctx.gw
	var gh: int = ctx.gh
	var origin: Vector2 = ctx.origin
	var grid := PackedFloat32Array()
	grid.resize(gw * gh)
	var types: PackedByteArray = ctx.types
	var dt_sea: PackedFloat32Array = ctx.dt_sea
	var river_cap: PackedFloat32Array = ctx.river_cap
	var floor_grid: PackedFloat32Array = ctx.floor_grid
	var cap_grid: PackedFloat32Array = ctx.cap_grid
	var coast_land: PackedFloat32Array = ctx.coast_land
	var seg_buf: PackedFloat32Array = ctx.seg_buf
	var knolls: PackedFloat32Array = ctx.knolls
	var sinks: PackedFloat32Array = ctx.sinks
	var depr: PackedFloat32Array = ctx.depressions
	var seg_bins := _bin_segments(seg_buf, 9, 430.0 + 170.0, origin)
	var riv_bins := _bin_segments(ctx.riv_buf, 5, 300.0, origin)
	var rav_bins := _bin_segments(ctx.rav_buf, 5, 240.0, origin)
	var crev_bins := _bin_segments(ctx.crev_buf, 5, 160.0, origin)
	var n_mul: FastNoiseLite = ctx.n_mul
	var n_fine: FastNoiseLite = ctx.n_fine
	var n_wx1: FastNoiseLite = ctx.n_wx1
	var n_wx2: FastNoiseLite = ctx.n_wx2
	var n_wy1: FastNoiseLite = ctx.n_wy1
	var n_wy2: FastNoiseLite = ctx.n_wy2
	var n_ridge: FastNoiseLite = ctx.n_ridge
	var field_max := 0.0
	for gy in gh:
		var y := origin.y + gy * STEP
		for gx in gw:
			var gi := gy * gw + gx
			var ti := types[gi]
			if ti == T_VOID or ti == T_SEA:
				continue   # sea level: rivers arrive at lv 0
			var x := origin.x + gx * STEP
			var wx := x + n_wx1.get_noise_2d(x, y) * 26.0 + n_wx2.get_noise_2d(x, y) * 10.0
			var wy := y + n_wy1.get_noise_2d(x, y) * 26.0 + n_wy2.get_noise_2d(x, y) * 10.0
			var key := int(floor((wy - origin.y) / BIN_CELL)) * 100000 + int(floor((wx - origin.x) / BIN_CELL))
			var v := 0.0
			var min_d2 := 1e18
			if seg_bins.has(key):
				for si in seg_bins[key]:
					var o: int = si * 9
					var rx := wx - seg_buf[o]
					var ry := wy - seg_buf[o + 1]
					var t := clampf((rx * seg_buf[o + 2] + ry * seg_buf[o + 3]) * seg_buf[o + 4], 0.0, 1.0)
					var ex := rx - seg_buf[o + 2] * t
					var ey := ry - seg_buf[o + 3] * t
					var d2 := ex * ex + ey * ey
					if d2 < min_d2:
						min_d2 = d2
					var w: float = seg_buf[o + 7] + seg_buf[o + 8] * t
					if d2 < w * w:
						var q2 := d2 / (w * w)
						var om := 1.0 - q2
						var g: float = (seg_buf[o + 5] + seg_buf[o + 6] * t) * om * om
						if g > 0.0:
							v = _smax(v, g, SMAX_K)
			var ki := 0
			while ki < knolls.size():
				var dxk := wx - knolls[ki]
				var dyk := wy - knolls[ki + 1]
				var u := knolls[ki + 2] * dxk + knolls[ki + 3] * dyk
				var vv := -knolls[ki + 3] * dxk + knolls[ki + 2] * dyk
				var q2k := u * u * knolls[ki + 4] + vv * vv * knolls[ki + 5]
				if q2k < 1.0:
					var omk := 1.0 - q2k
					v = _smax(v, knolls[ki + 6] * omk * omk * omk, SMAX_K)
				ki += 7
			v += 0.16 * _sstep(sqrt(min_d2), 420.0, 60.0)
			v *= 1.0 + 0.15 * n_mul.get_noise_2d(wx, wy)
			if v > 0.03:
				v += 0.025 * n_fine.get_noise_2d(wx, wy)
			var si2 := 0
			while si2 < sinks.size():
				var sdx := wx - sinks[si2]
				var sdy := wy - sinks[si2 + 1]
				var sd2 := sdx * sdx + sdy * sdy
				if sd2 < sinks[si2 + 2]:
					var ts := 1.0 - sd2 / sinks[si2 + 2]
					v -= sinks[si2 + 3] * ts * ts
				si2 += 4
			if v < 0.0:
				v = 0.0
			var rav_d := _min_dist_binned(ctx.rav_buf, rav_bins, key, wx, wy)
			v *= 0.05 + 0.95 * _sstep(rav_d, 20.0, 95.0)
			var crev_d := _min_dist_binned(ctx.crev_buf, crev_bins, key, wx, wy)
			v *= 0.45 + 0.55 * _sstep(crev_d, 12.0, 60.0)
			# type floor, sampled at amplified warp so tile-border ramps go wavy
			var flx := x + (wx - x) * 1.7
			var fly := y + (wy - y) * 1.7
			var fl := _grid_bilinear(floor_grid, ctx, flx, fly)
			var lake_d := _lake_dist(ctx, x, y)
			fl = maxf(0.0, fl - 0.30 * _sstep(lake_d, 300.0, 80.0))
			# global lowland: lv1-2 across all land, fading at coasts and where
			# the type floor already provides elevation
			var u_low := _lowland_at(ctx, wx, wy)
			u_low *= _sstep(dt_sea[gi], 20.0, 160.0)
			u_low *= 1.0 - _sstep(fl, 0.10, 0.28)
			v = _smax(v, u_low, SMAX_K)
			# budgeted lv -1 depressions
			var di := 0
			while di < depr.size():
				var dxd := x - depr[di]
				var dyd := y - depr[di + 1]
				var ud := depr[di + 2] * dxd + depr[di + 3] * dyd
				var vd := -depr[di + 3] * dxd + depr[di + 2] * dyd
				var q2d := ud * ud * depr[di + 4] + vd * vd * depr[di + 5]
				if q2d < 1.0:
					var omd := 1.0 - q2d
					v -= depr[di + 6] * omd * omd
				di += 8
			v += fl
			# eroded ridge-and-valley texture, gated to lv7+ elevations
			if v > 0.90:
				var r01: float = (n_ridge.get_noise_2d(wx, wy) + 1.0) * 0.5
				v += (r01 - 0.45) * 0.34 * _sstep(v, 1.00, 1.26)
			# type cap (warped + blurred: wavy dropoffs, not hex cliffs)
			var cp := _grid_bilinear(cap_grid, ctx, flx, fly)
			if v > cp:
				v = cp
			# lakes: hold the terrain at the cluster's constant rim level all
			# the way around the organic shore (the exit river cuts it below)
			if not ctx.lake_clusters.is_empty():
				var lkv := _grid_bilinear(ctx.lake_blur, ctx, flx, fly)
				if lkv > 0.05:
					var rim := _rim_at(ctx, x, y)
					v = v + (rim - v) * _sstep(lkv, 0.12, 0.5)
			# river valley: flat floor at the local valley level within 40 units,
			# blending back into the terrain by 170
			var key_t := int(floor((y - origin.y) / BIN_CELL)) * 100000 + int(floor((x - origin.x) / BIN_CELL))
			var riv_d := _min_dist_binned(ctx.riv_buf, riv_bins, key_t, x, y)
			var water_d := minf(riv_d, lake_d)
			if water_d < 170.0:
				var cap_r: float = river_cap[gi]
				v = cap_r + (v - cap_r) * _sstep(water_d, 40.0, 170.0)
			# land bands stop at the organic coastline (gulfs carve into tiles)
			v *= _sstep(coast_land[gi], 0.42, 0.58)
			grid[gi] = v
			if v > field_max:
				field_max = v
	ctx.grid = grid
	ctx.field_max = field_max

static func _min_dist_binned(buf: PackedFloat32Array, bins: Dictionary, key: int, x: float, y: float) -> float:
	if not bins.has(key):
		return 1e9
	var best := 1e18
	for si in bins[key]:
		var o: int = si * 5
		var rx := x - buf[o]
		var ry := y - buf[o + 1]
		var t := clampf((rx * buf[o + 2] + ry * buf[o + 3]) * buf[o + 4], 0.0, 1.0)
		var ex := rx - buf[o + 2] * t
		var ey := ry - buf[o + 3] * t
		var d := ex * ex + ey * ey
		if d < best:
			best = d
	return sqrt(best)

static func _lake_dist(ctx: Dictionary, x: float, y: float) -> float:
	var best := 1e9
	for lk in ctx.lakes:
		var lc: Vector2 = lk[0]
		var q := Vector2((x - lc.x) / maxf(lk[1], 1.0), (y - lc.y) / maxf(lk[2], 1.0)).length()
		var approx := (q - 1.0) * minf(lk[1], lk[2])
		best = minf(best, maxf(approx, 0.0))
	return best

static func _grid_bilinear(buf: PackedFloat32Array, ctx: Dictionary, x: float, y: float) -> float:
	var origin: Vector2 = ctx.origin
	var gx: float = (x - origin.x) / STEP
	var gy: float = (y - origin.y) / STEP
	var ix := clampi(int(floor(gx)), 0, ctx.gw - 2)
	var iy := clampi(int(floor(gy)), 0, ctx.gh - 2)
	var fx := clampf(gx - ix, 0.0, 1.0)
	var fy := clampf(gy - iy, 0.0, 1.0)
	var gw: int = ctx.gw
	var v00 := buf[iy * gw + ix]
	var v10 := buf[iy * gw + ix + 1]
	var v01 := buf[(iy + 1) * gw + ix]
	var v11 := buf[(iy + 1) * gw + ix + 1]
	var top: float = v00 + (v10 - v00) * fx
	return top + ((v01 + (v11 - v01) * fx) - top) * fy

static func _field_at(ctx: Dictionary, x: float, y: float) -> float:
	var origin: Vector2 = ctx.origin
	var gx: float = (x - origin.x) / STEP
	var gy: float = (y - origin.y) / STEP
	var ix := int(floor(gx))
	var iy := int(floor(gy))
	if ix < 0 or iy < 0 or ix >= ctx.gw - 1 or iy >= ctx.gh - 1:
		return 0.0
	var fx: float = gx - ix
	var fy: float = gy - iy
	var g: PackedFloat32Array = ctx.grid
	var gw: int = ctx.gw
	var v00 := g[iy * gw + ix]
	var v10 := g[iy * gw + ix + 1]
	var v01 := g[(iy + 1) * gw + ix]
	var v11 := g[(iy + 1) * gw + ix + 1]
	var top: float = v00 + (v10 - v00) * fx
	return top + ((v01 + (v11 - v01) * fx) - top) * fy

## band index = number of thresholds passed; band 0 = level -1.
static func _band_at(ctx: Dictionary, x: float, y: float) -> int:
	var v := _field_at(ctx, x, y)
	var b := 0
	for t in THRESHOLDS:
		if v >= t:
			b += 1
		else:
			break
	return b

# --------------------------------------------------------- contour extraction

static func _extract_contours(ctx: Dictionary) -> Array:
	var loops: Array = []
	for ti in THRESHOLDS.size():
		var thr: float = THRESHOLDS[ti]
		if thr > ctx.field_max:
			break
		for lp in _marching_squares(ctx, thr):
			debug_raw_loops += 1
			if lp.size() < 6:
				continue
			var smooth := _chaikin(lp)
			var area := _polygon_area(smooth)
			if absf(area) < 400.0:
				continue
			var band := _fill_band(ctx, smooth)
			loops.append({"b": band, "p": smooth, "a": absf(area)})
	loops.sort_custom(func(a, b): return a.a > b.a)
	for lp in loops:
		lp.erase("a")
	return loops

static func _marching_squares(ctx: Dictionary, thr: float, grid_override: PackedFloat32Array = PackedFloat32Array()) -> Array:
	var gw: int = ctx.gw
	var gh: int = ctx.gh
	var g: PackedFloat32Array = grid_override if not grid_override.is_empty() else ctx.grid
	var origin: Vector2 = ctx.origin
	var seg_from := {}
	var xs := PackedFloat32Array()
	var ys := PackedFloat32Array()
	for i in gw:
		xs.append(origin.x + i * STEP)
	for j in gh:
		ys.append(origin.y + j * STEP)
	for j in range(gh - 1):
		for i in range(gw - 1):
			var v_tl := g[j * gw + i]
			var v_tr := g[j * gw + i + 1]
			var v_br := g[(j + 1) * gw + i + 1]
			var v_bl := g[(j + 1) * gw + i]
			var c := 0
			if v_tl >= thr: c += 8
			if v_tr >= thr: c += 4
			if v_br >= thr: c += 2
			if v_bl >= thr: c += 1
			if c == 0 or c == 15:
				continue
			var x0 := xs[i]
			var x1 := xs[i + 1]
			var y0 := ys[j]
			var y1 := ys[j + 1]
			var pt := Vector2(x0 + (x1 - x0) * _cross(v_tl, v_tr, thr), y0)
			var pb := Vector2(x0 + (x1 - x0) * _cross(v_bl, v_br, thr), y1)
			var pl := Vector2(x0, y0 + (y1 - y0) * _cross(v_tl, v_bl, thr))
			var pr := Vector2(x1, y0 + (y1 - y0) * _cross(v_tr, v_br, thr))
			match c:
				1: _emit(seg_from, pb, pl)
				2: _emit(seg_from, pr, pb)
				3: _emit(seg_from, pr, pl)
				4: _emit(seg_from, pt, pr)
				5:
					if (v_tl + v_tr + v_br + v_bl) * 0.25 >= thr:
						_emit(seg_from, pt, pl)
						_emit(seg_from, pb, pr)
					else:
						_emit(seg_from, pt, pr)
						_emit(seg_from, pb, pl)
				6: _emit(seg_from, pt, pb)
				7: _emit(seg_from, pt, pl)
				8: _emit(seg_from, pl, pt)
				9: _emit(seg_from, pb, pt)
				10:
					if (v_tl + v_tr + v_br + v_bl) * 0.25 >= thr:
						_emit(seg_from, pr, pt)
						_emit(seg_from, pl, pb)
					else:
						_emit(seg_from, pl, pt)
						_emit(seg_from, pr, pb)
				11: _emit(seg_from, pr, pt)
				12: _emit(seg_from, pl, pr)
				13: _emit(seg_from, pb, pr)
				14: _emit(seg_from, pl, pb)
	var out: Array = []
	while not seg_from.is_empty():
		var start: Vector2 = seg_from.keys()[0]
		var loop := PackedVector2Array()
		var cur := start
		var guard := 0
		while guard < 400000:
			guard += 1
			loop.append(cur)
			if not seg_from.has(cur):
				debug_open_chains += 1
				break
			var ends: Array = seg_from[cur]
			var nxt: Vector2 = ends.pop_back()
			if ends.is_empty():
				seg_from.erase(cur)
			cur = nxt
			if cur == start:
				debug_closed += 1
				out.append(loop)
				break
		if guard >= 400000:
			break
	return out

static func _cross(v0: float, v1: float, thr: float) -> float:
	if absf(v1 - v0) < 1e-12:
		return 0.5
	return clampf((thr - v0) / (v1 - v0), 0.0, 1.0)

static func _emit(seg_from: Dictionary, a: Vector2, b: Vector2) -> void:
	if a == b:
		return
	if not seg_from.has(a):
		seg_from[a] = []
	seg_from[a].append(b)

static func _chaikin(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var p := pts[i]
		var q := pts[(i + 1) % n]
		out.append(p * 0.75 + q * 0.25)
		out.append(p * 0.25 + q * 0.75)
	return out

static func _polygon_area(pts: PackedVector2Array) -> float:
	var area := 0.0
	var n := pts.size()
	for i in n:
		var p := pts[i]
		var q := pts[(i + 1) % n]
		area += p.x * q.y - q.x * p.y
	return area * 0.5

static func _fill_band(ctx: Dictionary, loop: PackedVector2Array) -> int:
	var p0 := loop[0]
	var p1 := loop[mini(2, loop.size() - 1)]
	var mid := (p0 + p1) * 0.5
	var d := (p1 - p0)
	if d.length_squared() < 1e-9:
		return _band_at(ctx, mid.x, mid.y)
	var nrm := Vector2(d.y, -d.x).normalized() * 5.0
	var cand_a := mid + nrm
	var cand_b := mid - nrm
	var inside := cand_a if Geometry2D.is_point_in_polygon(cand_a, loop) else cand_b
	return _band_at(ctx, inside.x, inside.y)

# ------------------------------------------------------------ blocked masks

static func _collect_blocked(ctx: Dictionary, m: Dictionary, blocked: Dictionary) -> void:
	for idx in m.coords.size():
		var tile_id: String = m.tile_ids[idx]
		if not tile_id.begins_with("tile_"):
			continue   # decorative border tiles have no gameplay subtiles
		var center: Vector2 = m.hills[idx].c
		var bits: Array[int] = []
		for row in range(1, ROWS + 1):
			for col in range(1, COLS + 1):
				var local := Vector2((float(col) - 0.5) * SUBTILE_SIZE, (float(row) - 0.5) * SUBTILE_SIZE)
				var world := center + local - TILE_CENTER
				if _field_at(ctx, world.x, world.y) >= BLOCK_FIELD:
					bits.append((row - 1) * COLS + (col - 1))
		if not bits.is_empty():
			blocked[tile_id] = bits
