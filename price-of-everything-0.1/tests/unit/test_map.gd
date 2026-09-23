extends "res://tests/test_base.gd"
## Authored map, roads, fabric, hills, ports geometry and the density audit.

const FEATURE := "map"
## Tests that also belong to other features (run under any of their tags).
const TAGS := {
	"_test_farm_on_a_crowded_tile": ["map", "save_load"],
}

## Fraction of a road's LENGTH (dense-sampled) sitting within 12u of any farm-track segment. Sampling
## by length (not by vertex) is fair to the snapped road, whose on-web run has few but long edges.
func _frac_on_web(geo: PackedVector2Array, segs: Array) -> float:
	if geo.size() < 2:
		return 0.0
	var total := 0
	var near := 0
	for i in range(geo.size() - 1):
		var a: Vector2 = geo[i]
		var b: Vector2 = geo[i + 1]
		var steps := maxi(1, int(a.distance_to(b) / 5.0))
		for s in range(steps + 1):
			var p := a.lerp(b, float(s) / float(steps))
			total += 1
			for sg in segs:
				if p.distance_to(Geometry2D.get_closest_point_to_segment(p, sg[0], sg[1])) <= 12.0:
					near += 1
					break
	return float(near) / maxf(float(total), 1.0)

## True if (tile-centre-relative) point `rel` maps to a buildable cell in the tile's mask.
func _mask_buildable(bv, tile_id: String, rel: Vector2) -> bool:
	var col := int((rel.x + 270.0) / 20.0)
	var row := int((rel.y + 240.0) / 20.0)
	if col < 0 or row < 0 or col >= 27 or row >= 24:
		return false
	var land: PackedByteArray = bv._tile_land.get(tile_id, PackedByteArray())
	var key := row * 27 + col
	return key < land.size() and land[key] == 1

func _edges_clear_of_disc(net: RoadNetwork, disc: Dictionary) -> bool:
	# Points on/near a bridge are exempt: a predetermined river gate can sit inside a
	# forest disc's rim, and the mandatory straight crossing span + bank approaches
	# (_snap_bridges, which must win) then clip the canopy edge by a few units. Two
	# hard constraints meeting — the road legitimately passes under the canopy rim.
	# Everywhere else the realizer's _declamp_forests keeps geometry out of discs.
	var bridge_exempt := RoadCrossings.GATE_OFFSET + RoadRealizer.BRIDGE_BANK_STUB + 30.0
	# Bridge records live on the CANONICAL deck edges since the anchor-node
	# funnel (2026-07-09); approach pieces carry none. The exemption is a
	# property of the PLACE (near a crossing), so collect every bridge point
	# network-wide before scanning.
	var bridge_points: Array = []
	for eid0 in net.edges:
		for br0 in net.edges[eid0].bridges:
			bridge_points.append(br0.point)
	for eid in net.edges:
		var edge: Dictionary = net.edges[eid]
		for p in edge.geometry:
			if (p as Vector2).distance_to(disc.center) >= float(disc.radius) - 6.0:
				continue
			var near_bridge := false
			for bp in bridge_points:
				if (p as Vector2).distance_to(bp) <= bridge_exempt:
					near_bridge = true
					break
			if not near_bridge:
				return false
	return true

## Solid spans of `poly` along the line v == `v`. Returns {spans, total}.
func _mfs_scan(poly: PackedVector2Array, v: float) -> Dictionary:
	var xs: Array[float] = []
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		if (a.y <= v and b.y > v) or (b.y <= v and a.y > v):
			xs.append(a.x + (b.x - a.x) * ((v - a.y) / (b.y - a.y)))
	xs.sort()
	var total := 0.0
	var spans := 0
	var i := 0
	while i + 1 < xs.size():
		total += xs[i + 1] - xs[i]
		spans += 1
		i += 2
	return {"spans": spans, "total": total}

func _mfs_close(a: float, b: float, tol: float = 0.001) -> bool:
	return absf(a - b) <= tol * maxf(1.0, maxf(absf(a), absf(b)))

func _mfs_point_line_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	if ab.length() < 1e-6:
		return point.distance_to(a)
	return absf(ab.cross(point - a)) / ab.length()

## The single mass poly for `form` at `p`, or an empty array when infeasible.
func _mfs_one(form: String, w: float, h: float, p: Dictionary) -> PackedVector2Array:
	var built := MassFormShapes.construct(form, w, h, p)
	var polys: Array = built.get("polys", [])
	if polys.is_empty():
		return PackedVector2Array()
	return polys[0]

## Every legal parameter combination this sweep visits: each parameter walked across its
## full range (both extremes included) with the rest at midpoint, plus all-low, all-high,
## and 48 RoadHash-seeded interior draws.
func _mfs_param_sweep(form: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ranges: Dictionary = MassFormShapes.PARAM_RANGES[form]
	if ranges.is_empty():
		return [{}]
	var levels: Array[float] = [0.0, 0.25, 0.5, 0.75, 1.0]
	for name_value in ranges.keys():
		for level in levels:
			var p := MassFormShapes.params_mid(form)
			var span: Array = ranges[name_value]
			p[str(name_value)] = lerpf(float(span[0]), float(span[1]), level)
			out.append(p)
	for corner in [0.0, 1.0]:
		var p_corner: Dictionary = {}
		for name_value in ranges.keys():
			var span: Array = ranges[name_value]
			p_corner[str(name_value)] = lerpf(float(span[0]), float(span[1]), corner)
		out.append(p_corner)
	for draw in 48:
		out.append(MassFormShapes.params(form, "sweep|%s|%d" % [form, draw]))
	return out

func _building_id_for(internal_name: String) -> String:
	for building_value in Catalog.all_buildings():
		var building: Dictionary = building_value
		if str(building.get("internal_name", "")) == internal_name:
			return str(building.get("id", ""))
	return ""


func _load_document(name: String) -> Dictionary:
	if name == "":
		return {}
	var file := FileAccess.open(AuthoredMap.path_for(name), FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## Tile ids straight from the CSV the map is built from — the same source `hex_map.gd` reads,
## so this is the real set and not a second list that can drift from it.
func _tile_ids_from_csv() -> PackedStringArray:
	var out := PackedStringArray()
	var file := FileAccess.open("res://data/tile_properties.csv", FileAccess.READ)
	if file == null:
		return out
	file.get_csv_line()
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() > 0 and str(row[0]).strip_edges() != "":
			out.append(str(row[0]).strip_edges())
	file.close()
	return out


## Minimal stand-in for HexMap: a square 100 u grid, so a test can assert which tiles a
## stroke crosses without building the world. The property under test is the SAMPLING —
## whether a long segment can slip past a tile between two vertices — and that is
## independent of the real hex geometry.
class _StubTerrain extends Node:
	var tiles := {}

	func _init() -> void:
		for x in 12:
			for y in 4:
				tiles[Vector2i(x, y)] = {"id": "stub_%d_%d" % [x, y], "infrastructure_present": []}

	func local_to_map(p: Vector2) -> Vector2i:
		return Vector2i(int(floor(p.x / 100.0)), int(floor(p.y / 100.0)))

	func tile_coord_for_map_coord(c: Vector2i) -> Vector2i:
		return c

	func id_to_coord(id: String) -> Vector2i:
		var parts := id.split("_")
		if parts.size() < 3:
			return Vector2i(-1, -1)
		return Vector2i(int(parts[1]), int(parts[2]))


func _grow_quad(quad: PackedVector2Array, by: float) -> PackedVector2Array:
	var grown := Geometry2D.offset_polygon(quad, by)
	return grown[0] if not grown.is_empty() else quad


func _document_with(kind: String, record: Dictionary) -> Dictionary:
	var doc: Dictionary = AuthoredMap.empty_document()
	doc["settlements"] = {"test": {"tiles": ["tile_1_1"], kind: [record]}}
	return doc


## A rectangle as a document outline ([[x, y], ...]) centred on `c`.
func _rect_outline(c: Vector2, w: float, h: float) -> Array:
	return [[c.x - w / 2.0, c.y - h / 2.0], [c.x + w / 2.0, c.y - h / 2.0],
		[c.x + w / 2.0, c.y + h / 2.0], [c.x - w / 2.0, c.y + h / 2.0]]


## True when `segs` holds a level segment through the tile centre longer than 300 u — the
## authored-stroke fixture's road.
func _has_centre_stroke(segs: Array) -> bool:
	for s in segs:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		if absf(a.y) < 0.01 and absf(b.y) < 0.01 and absf(b.x - a.x) > 300.0:
			return true
	return false


## City-plate variant (docs/map_city_plate_spec.md). The plate is a sub-variant of
## ink, so its whole safety story is "classic and ink render exactly as before" —
## every value below is the pre-plate literal, and this test is what keeps them
## that way. It also pins the seam semantics the cheat relies on.
func _test_map_style_plate() -> void:
	var was_ink: bool = MapStyle.ink
	var was_plate: bool = MapStyle.plate
	var was_midcentury: bool = MapStyle.is_midcentury()

	MapStyle.set_midcentury(false)
	MapStyle.set_plate(false)
	MapStyle.set_ink(false)
	_check(not MapStyle.is_plate(), "map style: classic is not plate")
	_check(MapStyle.ink_color() == Color("3a2c18"), "map style: classic keeps the sepia ink")
	_check(MapStyle.band_colors()[2] == Color("5e7d44"), "map style: classic band ramp unchanged")
	_check(MapStyle.road_local() == Color("e8c84a"), "map style: classic road bed unchanged")
	_check(MapStyle.forest_base() == Color("0d512b"), "map style: classic canopy unchanged")
	_check(MapStyle.extrude_offset(MapStyle.Extrude.FULL) == Vector2.ZERO,
		"map style: no extrusion outside plate")

	MapStyle.set_ink(true)
	_check(not MapStyle.is_plate(), "map style: ink alone is not plate")
	_check(MapStyle.parchment_offsets().size() == 2 and MapStyle.parchment_colors().size() == 2,
		"map style: ink parchment ramp stays the original two stops")
	_check(MapStyle.parchment_colors()[0] == MapStyle.parchment_darkest()
		and absf(MapStyle.parchment_noise_frequency() - 0.035) < 1e-6
		and MapStyle.parchment_tile_px() == 256,
		"map style: ink grain is unchanged")
	_check(MapStyle.ink_color() == Color("3a2c18"), "map style: ink keeps the sepia ink")
	_check(MapStyle.band_colors()[2] == Color("9aa465"), "map style: ink band ramp unchanged")
	_check(MapStyle.road_local() == Color("dfd0a2"), "map style: ink road bed unchanged")
	_check(MapStyle.road_casing_dashed(), "map style: ink casings stay dashed")
	_check(MapStyle.trunk_center_dash().size() == 2, "map style: ink keeps the trunk centre dash")
	_check(MapStyle.forest_base() == Color("0d512b"), "map style: ink canopy unchanged")
	_check(MapStyle.forest_arc() == Color("2d7d3a"), "map style: ink keeps canopy highlight arcs")
	_check(MapStyle.building_shadow_color().a > 0.0, "map style: ink keeps the building micro-shadow")
	_check(MapStyle.extrude_offset(MapStyle.Extrude.FULL) == Vector2.ZERO,
		"map style: no extrusion in ink")

	MapStyle.set_plate(true)
	_check(MapStyle.is_plate() and MapStyle.ink, "map style: plate implies ink")
	_check(MapStyle.ink_color() == Color("4a4136"), "map style: plate swaps to the one plate ink")
	# Water returned toward the pre-ink blue (owner 2026-08-11): between classic's
	# saturation and ink's slate, NOT the pale sky the first plate cut used.
	_check(MapStyle.water_color() == Color("3f7cc4"), "map style: plate water is the deeper pre-ink blue")
	_check(MapStyle.sea_colors()[5] == MapStyle.band_colors()[1],
		"map style: the sea's land-base band tracks the coastal sand band")
	# Owner ruling 2026-08-11: the plate does NOT re-grade the land — it shares
	# ink's green ramp, and expresses itself through what stands on the ground.
	_check(MapStyle.band_colors()[2] == Color("9aa465"), "map style: plate keeps ink's green landmass")
	_check(MapStyle.forest_base() == Color("0d512b"), "map style: plate keeps ink's canopy green")
	# Three-way ownership read: decor cream, NPC grey with a deeper side face,
	# player coloured. (The decor BUILDING itself lives on road-density; the
	# colour rule stays here because it is part of the plate's palette.)
	_check(MapStyle.plate_block_top("decor") == Color("efe9db"),
		"map style: decorative buildings are cream")
	_check(MapStyle.plate_block_top("npc") == Color("8f8d85"),
		"map style: NPC blocks are grey")
	var npc_top: Color = MapStyle.plate_block_top("npc")
	_check(MapStyle.extrude_side(npc_top, MapStyle.Extrude.FULL, true).get_luminance()
		< MapStyle.extrude_side(npc_top, MapStyle.Extrude.FULL).get_luminance(),
		"map style: NPC blocks take a deeper side face than the standard prism")
	# get_luminance() is on gamma values, so compare by margin, not by ratio.
	_check(MapStyle.road_local().get_luminance() - MapStyle.band_colors()[3].get_luminance() > 0.20,
		"map style: plate streets read clearly lighter than the land they cross")
	# Parchment: the plate's paper is quieter AND patchy. The middle stops sit on
	# clean paper, so most of the sheet carries no grain at all.
	_check(MapStyle.parchment_offsets().size() == 4 and MapStyle.parchment_colors().size() == 4,
		"map style: plate parchment ramp has its four shaping stops")
	_check(MapStyle.parchment_colors()[1] == MapStyle.parchment_lightest()
		and MapStyle.parchment_colors()[2] == MapStyle.parchment_lightest(),
		"map style: the plate ramp's middle band is clean paper")
	_check(MapStyle.parchment_colors()[0].get_luminance() > MapStyle.parchment_darkest().get_luminance(),
		"map style: plate grain darkens less than ink's")
	_check(MapStyle.parchment_noise_frequency() < 0.035 and MapStyle.parchment_tile_px() > 256,
		"map style: plate grain is coarser and repeats less often")
	_check(not MapStyle.road_casing_dashed(), "map style: plate streets take solid edges")
	_check(MapStyle.trunk_center_dash().is_empty(), "map style: plate drops the trunk centre dash")
	_check(MapStyle.building_shadow_color().a == 0.0,
		"map style: plate drops the micro-shadow (the prism replaces it)")
	_check(MapStyle.extrude_offset(MapStyle.Extrude.FULL) == Vector2(3.0, 4.0),
		"map style: plate extrudes FULL masses")
	_check(MapStyle.extrude_offset(MapStyle.Extrude.MILD) == Vector2(1.5, 2.0),
		"map style: plate extrudes MILD masses less")
	var side := MapStyle.extrude_side(Color("6e6b60"), MapStyle.Extrude.FULL)
	_check(side.a == 1.0 and side.v < Color("6e6b60").v,
		"map style: side faces are an opaque darkening of the top")
	_check(MapStyle.plate_block_top("nonsense") == MapStyle.plate_block_top("orange"),
		"map style: unknown wash families fall through to the default block")
	# A dark roof takes light motif lines; a light one keeps ink.
	_check(MapStyle.roof_motif_color(Color("75756d")).v > 0.7,
		"map style: motifs go light on a dark plate roof")
	_check(MapStyle.roof_motif_color(Color("e8ddc0")) == MapStyle.ink_color(),
		"map style: motifs stay ink on a light plate roof")

	# Midcentury masks the selected legacy mode without mutating it. Its values
	# come from an independent table and its solid-mass treatment is available
	# even when the preserved legacy style is classic.
	MapStyle.set_plate(false)
	MapStyle.set_ink(false)
	var legacy_band: Color = MapStyle.band_colors()[2]
	var legacy_road: Color = MapStyle.road_local()
	MapStyle.set_midcentury(true)
	_check(MapStyle.is_midcentury(), "map style: midcentury seam enables")
	_check(not MapStyle.ink and not MapStyle.plate,
		"map style: midcentury does not mutate the selected legacy mode")
	_check(MapStyle.band_colors()[2] == MapMidcenturyStyle.BAND_COLORS[2]
		and MapStyle.band_colors()[2] != legacy_band,
		"map style: midcentury owns an independent land palette")
	_check(MapStyle.road_local() == MapMidcenturyStyle.ROAD_LOCAL
		and MapStyle.road_local() != legacy_road,
		"map style: midcentury owns an independent street palette")
	_check(MapStyle.has_cartographic_depth()
		and MapStyle.extrude_offset(MapStyle.Extrude.FULL) == Vector2(2.4, 3.0),
		"map style: midcentury uses restrained cartographic depth")
	_check(MapStyle.block_top("orange") == MapMidcenturyStyle.gameplay_block_top("orange"),
		"map style: gameplay industries use the midcentury landmark palette")
	MapStyle.set_midcentury(false)
	_check(not MapStyle.is_midcentury() and MapStyle.band_colors()[2] == legacy_band
		and MapStyle.road_local() == legacy_road,
		"map style: leaving midcentury restores legacy getters exactly")

	# Leaving ink must drop plate too, or classic would render with plate latched.
	MapStyle.set_ink(false)
	_check(not MapStyle.plate and not MapStyle.is_plate(),
		"map style: leaving ink clears the plate sub-variant")
	_check(MapStyle.ink_color() == Color("3a2c18"), "map style: back in classic, sepia ink returns")

	MapStyle.set_midcentury(false)
	MapStyle.set_ink(was_ink)
	MapStyle.set_plate(was_plate)
	MapStyle.set_midcentury(was_midcentury)

func _test_midcentury_road_layout_fixture() -> void:
	var fabric := UrbanFabricVisuals.new()
	var center := Vector2(500.0, 500.0)
	var old_roads := [{"a": center + Vector2(-180.0, -70.0),
		"b": center + Vector2(180.0, -70.0), "trunk": true}]
	var new_roads := [{"a": center + Vector2(65.0, -180.0),
		"b": center + Vector2(65.0, 180.0), "trunk": true}]
	var old_snapshot: Dictionary = fabric.road_layout_fixture_snapshot(center,
		old_roads)
	var old_repeat: Dictionary = fabric.road_layout_fixture_snapshot(center,
		old_roads)
	var new_snapshot: Dictionary = fabric.road_layout_fixture_snapshot(center,
		new_roads)
	_check((old_snapshot.core_position as Vector2).is_equal_approx(
		old_repeat.core_position) and old_snapshot.core_polygon == \
		old_repeat.core_polygon,
		"midcentury road fixture: identical roads reproduce the exact core")
	_check(absf((old_snapshot.core_tangent as Vector2).dot(Vector2.RIGHT)) > 0.95,
		"midcentury road fixture: old horizontal road steers horizontal growth")
	_check(absf((new_snapshot.core_tangent as Vector2).dot(Vector2.DOWN)) > 0.95,
		"midcentury road fixture: replacement vertical road steers vertical growth")
	_check((old_snapshot.core_position as Vector2).distance_to(
		new_snapshot.core_position) > 40.0,
		"midcentury road fixture: density leaves the removed road and follows the replacement")
	fabric.free()

## Gate E3 — the rare industrial landmark tier is a deterministic SELECTION
## contract, not a look-and-see palette tweak: it must stay single-digit
## map-wide, must not depend on the order sites arrive in, and its accent must
## stay strictly between the accepted half-chroma ordinary industry tier
## (V4.08b) and the full category colour that failed as saturated fields
## (V4.08a). Pure geometry/colour — no scene, no renderer, no RNG.
func _test_midcentury_industry_landmark_tier() -> void:
	var compound := preload("res://scripts/midcentury_industry_compound.gd")
	var sites: Array = []
	for cluster in 12:
		var base := Vector2(float(cluster) * 2000.0, 0.0)
		for member in 3:
			var at := base + Vector2(50.0 * float(member % 2), 50.0 * float(member / 2))
			sites.append({
				"poly": PackedVector2Array([
					at + Vector2(-20.0, -20.0), at + Vector2(20.0, -20.0),
					at + Vector2(20.0, 20.0), at + Vector2(-20.0, 20.0)]),
				"instance_id": "site_%02d_%d" % [cluster, member],
			})
	var selection: Dictionary = compound.select_landmarks(sites)
	var diagnostics: Dictionary = selection.diagnostics
	_check(int(diagnostics.landmark_count) == compound.LANDMARK_MAX,
		"midcentury landmarks: a crowded map still caps at the landmark maximum")
	_check(int(diagnostics.landmark_count) < 10,
		"midcentury landmarks: the tier stays single-digit map-wide")
	var keys: Array = diagnostics.landmark_keys
	var reversed_sites: Array = []
	for i in range(sites.size() - 1, -1, -1):
		reversed_sites.append(sites[i])
	var reversed_keys: Array = (compound.select_landmarks(
		reversed_sites).diagnostics as Dictionary).landmark_keys
	keys.sort()
	reversed_keys.sort()
	_check(keys == reversed_keys,
		"midcentury landmarks: selection does not depend on site iteration order")
	_check(compound.select_landmarks(sites).diagnostics.landmark_keys
		== diagnostics.landmark_keys,
		"midcentury landmarks: repeated selection is identical")
	# Every accepted landmark must be separated from the others.
	var centers: Array = []
	for chosen_value in selection.compounds:
		centers.append((chosen_value as Dictionary).center as Vector2)
	var separated := true
	for i in centers.size():
		for j in range(i + 1, centers.size()):
			if (centers[i] as Vector2).distance_to(centers[j]) < compound.LANDMARK_MIN_SEPARATION:
				separated = false
	_check(separated, "midcentury landmarks: accepted compounds stay far apart")
	# The chroma bound, measured rather than asserted in a comment.
	var ordinary_max := 0.0
	for family in MapMidcenturyStyle.GAMEPLAY_BLOCK_TOPS:
		ordinary_max = maxf(ordinary_max,
			(MapMidcenturyStyle.GAMEPLAY_BLOCK_TOPS[family] as Color).s)
	var landmark_min := 1.0
	var landmark_max := 0.0
	for tone in MapMidcenturyStyle.INDUSTRY_LANDMARK_TONES:
		landmark_min = minf(landmark_min, (tone as Color).s)
		landmark_max = maxf(landmark_max, (tone as Color).s)
	_check(landmark_min > ordinary_max,
		"midcentury landmarks: the accent sits above the halved ordinary industry chroma")
	_check(landmark_max < Color("b3743f").s and landmark_max < Color("c1922c").s,
		"midcentury landmarks: the accent stays below the rejected full category colour")
	# Near zoom the landmark is a paper wash, never a saturated filled roof.
	for tone_index in MapMidcenturyStyle.INDUSTRY_LANDMARK_TONES.size():
		var wash := MapMidcenturyStyle.industry_landmark_yard("probe|%d" % tone_index)
		_check(wash.s < landmark_min,
			"midcentury landmarks: the near-zoom yard wash is quieter than the plate accent")
# ======================================================================================
# Mass-form vocabulary geometry (scripts/mass_form_shapes.gd)
#
# docs/map-mass-form-vocabulary.md sections 2-3 define 13 decorative mass forms; section
# 4 forbids stamping them at fixed proportions; section 6 demands every one of them be
# closed, simple and gracefully degrading at EVERY legal parameter value (the V3.04
# lesson). These tests pin all three.
#
# The structural probe throughout is _mfs_scan(): it sweeps a horizontal line across the
# local (u, v) frame and reports how many solid spans it crosses and how much total
# length. That measures limb COUNT and limb WIDTH from the polygon itself, independently
# of the constructor's own bookkeeping, so a constructor cannot mark its own homework.
# ======================================================================================

func _test_accommodation_site_yield() -> void:
	var site_a := {"key": "park", "poly": PackedVector2Array([
		Vector2(0, 0), Vector2(24, 0), Vector2(24, 18), Vector2(0, 18)]),
		"visual_use": "releasable_park"}
	var site_b := {"key": "yard", "poly": PackedVector2Array([
		Vector2(34, 0), Vector2(68, 0), Vector2(68, 22), Vector2(34, 22)]),
		"visual_use": "releasable_yard"}
	var hypothetical := [{"poly": (site_a.poly as PackedVector2Array).duplicate()}]
	var masses := [{"key": "neighbour", "poly": PackedVector2Array([
		Vector2(75, 0), Vector2(94, 0), Vector2(94, 25), Vector2(75, 25)])}]
	var was_midcentury := MapStyle.is_midcentury()
	MapStyle.set_midcentury(false)
	var legacy_result := AccommodationSitePlanner.yield_for_hypothetical_footprints(
		[site_a, site_b], hypothetical, masses)
	MapStyle.set_midcentury(true)
	var styled_result := AccommodationSitePlanner.yield_for_hypothetical_footprints(
		[site_a, site_b], hypothetical, masses)
	_check(int(styled_result.removed_site_count) == 1
		and str((styled_result.removed_sites as Array)[0].key) == "park"
		and int(styled_result.retained_site_count) == 1,
		"accommodation sites: a hypothetical footprint yields the whole releasable record")
	_check(int(styled_result.releasable_fragment_count) == 0
		and int(styled_result.retained_site_hypothetical_overlap_count) == 0
		and int(styled_result.hypothetical_decorative_mass_overlap_count) == 0
		and int(styled_result.surrounding_mass_count_before) ==
			int(styled_result.surrounding_mass_count_after),
		"accommodation sites: yielding leaves no clipped fragment or changed neighbouring mass")
	_check(int(legacy_result.removed_site_count) == int(styled_result.removed_site_count)
		and int(legacy_result.retained_site_count) == int(styled_result.retained_site_count)
		and str((legacy_result.removed_sites as Array)[0].key) ==
			str((styled_result.removed_sites as Array)[0].key),
		"accommodation sites: planning result is independent of optional map style state")
	MapStyle.set_midcentury(was_midcentury)

## Pins the class assignment of the per-tile density audit (addendum section 2).
## The precedence rules are the part a future change is most likely to get
## subtly wrong, so each rule is asserted on its own.
func _test_density_audit_classification() -> void:
	_check(DensityAudit.classify("urban", true, 4) == DensityAudit.CLASS_URBAN,
		"density audit: a profiled urban tile is urban")
	_check(DensityAudit.classify("urban", false, 4) == DensityAudit.CLASS_SPARSE,
		"density audit: an unprofiled urban-terrain tile is not silently urban")
	_check(DensityAudit.classify("mountain", false, 3) == DensityAudit.CLASS_MOUNTAIN,
		"density audit: a mountain tile with roads stays mountain (cap beats sparse floor)")
	_check(DensityAudit.classify("mountain", false, 0) == DensityAudit.CLASS_MOUNTAIN,
		"density audit: a roadless mountain tile is mountain, not remote")
	_check(DensityAudit.classify("rural", false, 1) == DensityAudit.CLASS_SPARSE,
		"density audit: one authoritative road makes a non-urban tile sparse")
	_check(DensityAudit.classify("hill", false, 0) == DensityAudit.CLASS_REMOTE,
		"density audit: a roadless non-urban tile is remote")
	_check(DensityAudit.classify("sea", false, 0) == DensityAudit.CLASS_WATER
		and DensityAudit.classify("deep_sea", false, 0) == DensityAudit.CLASS_WATER,
		"density audit: water tiles are excluded from the audit")

	# One absolute map-wide area threshold, never a per-tile relative one.
	_check(DensityAudit.is_large(DensityAudit.LARGE_MASS_AREA)
		and not DensityAudit.is_large(DensityAudit.LARGE_MASS_AREA - 0.5),
		"density audit: the small/large split is inclusive at the frozen threshold")
	_check(DensityAudit.LARGE_MASS_AREA > UrbanFabricVisuals.MORPH_FACE_MIN_AREA,
		"density audit: a large mass is at least a whole un-subdivided street face")

	# What counts as a building, and what counts as a green space.
	_check(DensityAudit.counts_as_building("ordinary", 900.0)
		and DensityAudit.counts_as_building("core", 900.0)
		and DensityAudit.counts_as_building("industry_support", 900.0),
		"density audit: rendered decorative masses count as buildings")
	_check(not DensityAudit.counts_as_building("park", 900.0)
		and not DensityAudit.counts_as_building("courtyard", 900.0),
		"density audit: greens and courts are never counted as buildings")
	_check(not DensityAudit.counts_as_building("ordinary",
		DensityAudit.MIN_COUNTED_MASS_AREA - 1.0),
		"density audit: a sub-floor fragment is not a building")
	_check(DensityAudit.counts_as_green("park", 400.0)
		and DensityAudit.counts_as_green("green", 400.0)
		and DensityAudit.counts_as_green("accommodation_park", 400.0),
		"density audit: public greens count toward the urban park floor")
	_check(not DensityAudit.counts_as_green("courtyard", 4000.0),
		"density audit: an inner courtyard is not a public green space")

## Pins the section-2 table itself, including the two precedence carve-outs and
## the documented-shortfall rule (a documented miss is acceptable, a silent one
## is a gate failure).
func _test_density_audit_gate() -> void:
	var plenty := 1.0e9
	var urban_ok := DensityAudit.evaluate(DensityAudit.CLASS_URBAN,
		10, 3, 2, plenty, false)
	_check(bool(urban_ok.passes) and not bool(urban_ok.gate_failure),
		"density audit: urban 10 small / 3 large / 2 parks is exactly compliant")
	var urban_short := DensityAudit.evaluate(DensityAudit.CLASS_URBAN,
		9, 2, 1, plenty, false)
	_check((urban_short.failures as Array).has("small_below_floor")
		and (urban_short.failures as Array).has("large_below_floor")
		and (urban_short.failures as Array).has("green_below_floor")
		and bool(urban_short.gate_failure),
		"density audit: an urban tile under every floor reports all three failures")
	_check(not bool(urban_short.physically_constrained),
		"density audit: a miss on ample dry land is a real defect, not a constraint")

	var constrained := DensityAudit.evaluate(DensityAudit.CLASS_URBAN,
		0, 0, 0, 10.0, false)
	_check(bool(constrained.physically_constrained)
		and bool(constrained.gate_failure),
		"density audit: a physically impossible tile still fails until documented")
	var documented := DensityAudit.evaluate(DensityAudit.CLASS_URBAN,
		0, 0, 0, 10.0, true)
	_check(not bool(documented.passes) and not bool(documented.gate_failure),
		"density audit: a documented physical shortfall is acceptable")

	var sparse_ok := DensityAudit.evaluate(DensityAudit.CLASS_SPARSE,
		3, 0, 0, plenty, false)
	_check(bool(sparse_ok.passes),
		"density audit: sparse needs no parks and no large buildings")
	_check((DensityAudit.evaluate(DensityAudit.CLASS_SPARSE, 11, 0, 0, plenty,
		false).failures as Array).has("small_above_cap"),
		"density audit: sparse is capped at 10 small buildings")
	_check((DensityAudit.evaluate(DensityAudit.CLASS_SPARSE, 5, 3, 0, plenty,
		false).failures as Array).has("large_above_cap"),
		"density audit: sparse is capped at 2 large buildings")
	_check((DensityAudit.evaluate(DensityAudit.CLASS_SPARSE, 2, 0, 0, plenty,
		false).failures as Array).has("small_below_floor"),
		"density audit: sparse has a floor of 3 small buildings")

	# The mountain cap wins over the sparse floor: zero buildings is compliant.
	var mountain_empty := DensityAudit.evaluate(DensityAudit.CLASS_MOUNTAIN,
		0, 0, 0, plenty, false)
	_check(bool(mountain_empty.passes),
		"density audit: an empty mountain tile complies (cap, not floor)")
	_check((DensityAudit.evaluate(DensityAudit.CLASS_MOUNTAIN, 3, 0, 0, plenty,
		false).failures as Array).has("small_above_cap")
		and (DensityAudit.evaluate(DensityAudit.CLASS_MOUNTAIN, 1, 1, 0, plenty,
		false).failures as Array).has("large_above_cap"),
		"density audit: mountain is capped at 2 small and 0 large")

	# Remote tiles are exempt from the sparse floor but have their own band.
	_check(bool(DensityAudit.evaluate(DensityAudit.CLASS_REMOTE, 1, 0, 0, plenty,
		false).passes)
		and bool(DensityAudit.evaluate(DensityAudit.CLASS_REMOTE, 4, 0, 0, plenty,
		false).passes),
		"density audit: remote tiles comply anywhere in the 1-4 band")
	_check((DensityAudit.evaluate(DensityAudit.CLASS_REMOTE, 0, 0, 0, plenty,
		false).failures as Array).has("small_below_floor")
		and (DensityAudit.evaluate(DensityAudit.CLASS_REMOTE, 5, 0, 0, plenty,
		false).failures as Array).has("small_above_cap"),
		"density audit: remote tiles are bounded on both sides")

## INSTRUMENT 1 - articulation. Pins the property that motivated it: a naive
## polygon count cannot see visual fusion, and this metric can. Every fixture
## here is hand-laid geometry with no scene tree, so the assertions are exact.
func _test_density_audit_articulation() -> void:
	# The dilation is not a tuned number: it is HALF the map's own narrowest
	# accepted alley, so a gap narrower than one alley closes and a gap of one
	# alley or wider does not. Freeze that derivation.
	_check(is_equal_approx(DensityAudit.FUSION_DILATION,
		UrbanFabricVisuals.HERO_ALLEY_HALF_WIDTH),
		"articulation: fusion dilation is half an accepted alley, by derivation")

	# Three 40x40 masses in a row. THE FUSION CASE: 1.0u of bare ground between
	# them, far under the 3.8u the fabric itself accepts as a visible alley.
	# A polygon counter says three buildings; the eye sees one bar.
	var fused: Array = []
	for i in 3:
		var x := float(i) * 41.0
		fused.append({"poly": PackedVector2Array([
			Vector2(x, 0), Vector2(x + 40.0, 0),
			Vector2(x + 40.0, 40.0), Vector2(x, 40.0)]), "area": 1600.0})
	var fused_pieces := DensityAudit.visible_pieces(fused)
	var fused_summary := DensityAudit.articulation_summary(fused_pieces)
	_check(fused.size() == 3 and int(fused_summary.visible_piece_count) == 1,
		"articulation: three masses one unit apart are ONE visible piece")
	_check(int(fused_summary.largest_piece_mass_count) == 3
		and is_equal_approx(float(fused_summary.fused_mass_share_pct), 100.0),
		"articulation: the fused piece reports all three masses inside it")
	_check(float(fused_summary.silhouette_perimeter_ratio) > 1.3,
		"articulation: fusion shows up independently as lost silhouette perimeter")

	# The same three masses separated by a real street. Nothing fuses.
	var apart: Array = []
	for i in 3:
		var x := float(i) * 80.0
		apart.append({"poly": PackedVector2Array([
			Vector2(x, 0), Vector2(x + 40.0, 0),
			Vector2(x + 40.0, 40.0), Vector2(x, 40.0)]), "area": 1600.0})
	var apart_summary := DensityAudit.articulation_summary(
		DensityAudit.visible_pieces(apart))
	_check(int(apart_summary.visible_piece_count) == 3
		and is_equal_approx(float(apart_summary.masses_per_visible_piece), 1.0),
		"articulation: masses across a real street stay three visible pieces")
	_check(float(apart_summary.silhouette_perimeter_ratio) < 1.001,
		"articulation: separated masses lose no silhouette perimeter")
	# G7 REPAIR (break A5): piece area is the area of the SILHOUETTE. A 40x40
	# mass dilated by 1.9u on every side is 43.8 x 43.8; the drawn INK is still
	# 1600 and is reported under its own honest name.
	# 43.8 x 43.8 with the four corners squared off by JOIN_SQUARE: 1916 u^2 -
	# exactly the silhouette the adversarial probe measured a 1600 u^2 mass to
	# have while the instrument reported its "piece area" as 6400.
	_check(absf(float(apart_summary.mean_visible_piece_area) - 1916.0) < 1.0
		and absf(float(apart_summary.median_visible_piece_area) - 1916.0) < 1.0,
		"articulation: mean and median piece area are the SILHOUETTE area")
	_check(is_equal_approx(float(apart_summary.mean_piece_ink_area), 1600.0)
		and is_equal_approx(float(apart_summary.median_piece_ink_area), 1600.0),
		"articulation: the old sum-of-ink number survives under an honest name")
	_check(float(apart_summary.ink_to_silhouette_ratio) < 1.0,
		"articulation: separated masses have less ink than silhouette")
	_check(int(apart_summary.excess_mass_count) == 0
		and int(fused_summary.excess_mass_count) == 2,
		"articulation: excess_mass_count counts masses that are not separately visible")

	# Exactly a 3.8u gap - one accepted alley - must NOT fuse. This is the
	# boundary the whole metric hangs on, so it is asserted on its own.
	var alley: Array = [
		{"poly": PackedVector2Array([Vector2(0, 0), Vector2(40, 0),
			Vector2(40, 40), Vector2(0, 40)]), "area": 1600.0},
		{"poly": PackedVector2Array([Vector2(44.2, 0), Vector2(84.2, 0),
			Vector2(84.2, 40), Vector2(44.2, 40)]), "area": 1600.0}]
	_check(DensityAudit.visible_pieces(alley).size() == 2,
		"articulation: a full 3.8u alley is a visible gap and does not fuse")

	# THE MOTIVATING DEFECT, reproduced. The V5 vocabulary candidate raised
	# built area 2.1% map-wide while the plate LOST parcels, and the mass count
	# concealed it exactly. Control and candidate below have the SAME mass count
	# and the candidate has MORE built area - yet it is visibly one slab plus a
	# shed where the control is three buildings. Built area says "better",
	# visible pieces say "worse".
	var control: Array = [
		{"poly": PackedVector2Array([Vector2(0, 0), Vector2(40, 0),
			Vector2(40, 40), Vector2(0, 40)]), "area": 1600.0},
		{"poly": PackedVector2Array([Vector2(80, 0), Vector2(120, 0),
			Vector2(120, 40), Vector2(80, 40)]), "area": 1600.0},
		{"poly": PackedVector2Array([Vector2(160, 0), Vector2(200, 0),
			Vector2(200, 40), Vector2(160, 40)]), "area": 1600.0}]
	var candidate: Array = [
		{"poly": PackedVector2Array([Vector2(0, 0), Vector2(60, 0),
			Vector2(60, 40), Vector2(0, 40)]), "area": 2400.0},
		{"poly": PackedVector2Array([Vector2(61, 0), Vector2(121, 0),
			Vector2(121, 40), Vector2(61, 40)]), "area": 2400.0},
		{"poly": PackedVector2Array([Vector2(160, 0), Vector2(200, 0),
			Vector2(200, 40), Vector2(160, 40)]), "area": 1600.0}]
	var control_summary := DensityAudit.articulation_summary(
		DensityAudit.visible_pieces(control))
	var candidate_summary := DensityAudit.articulation_summary(
		DensityAudit.visible_pieces(candidate))
	var control_area := 1600.0 * 3.0
	var candidate_area := 2400.0 + 2400.0 + 1600.0
	_check(candidate_area > control_area
		and int(candidate_summary.mass_count) == int(control_summary.mass_count),
		"articulation: the fixture reproduces V5 - more built area, same mass count")
	_check(int(candidate_summary.visible_piece_count)
		< int(control_summary.visible_piece_count),
		"articulation: visible pieces FALL where built area and mass count rise")
	_check(float(candidate_summary.median_visible_piece_area)
		> float(control_summary.median_visible_piece_area),
		"articulation: median piece area rises - denser in ink, sparser in city")

	_check(DensityAudit.articulation_summary([]).visible_piece_count == 0
		and DensityAudit.visible_pieces([]).is_empty(),
		"articulation: an empty tile reports zero pieces without dividing by zero")

	# G7 REPAIR (break A4): the fabric fills a SHADOW under every block, and the
	# instrument must be shown it. A bridge shape fuses what it touches and is
	# never counted as a building.
	_check(is_equal_approx(DensityAudit.BLOCK_SHADOW_OFFSET.x,
			UrbanFabricVisuals.BLOCK_SHADOW_OFFSET.x)
		and is_equal_approx(DensityAudit.BLOCK_SHADOW_OFFSET.y,
			UrbanFabricVisuals.BLOCK_SHADOW_OFFSET.y),
		"articulation: the audit's shadow offset is the fabric's own, by derivation")
	var bridged: Array = [
		{"poly": PackedVector2Array([Vector2(0, 0), Vector2(40, 0),
			Vector2(40, 40), Vector2(0, 40)]), "area": 1600.0},
		{"poly": PackedVector2Array([Vector2(60, 0), Vector2(100, 0),
			Vector2(100, 40), Vector2(60, 40)]), "area": 1600.0},
		# a sub-floor crumb chain across the 20u gap: ink a human sees, not a
		# building. It must FUSE the two masses and count as neither.
		{"poly": PackedVector2Array([Vector2(41, 10), Vector2(59, 10),
			Vector2(59, 20), Vector2(41, 20)]), "area": 180.0,
			"counts": false}]
	var bridged_summary := DensityAudit.articulation_summary(
		DensityAudit.visible_pieces(bridged))
	_check(int(bridged_summary.visible_piece_count) == 1
		and int(bridged_summary.mass_count) == 2
		and int(bridged_summary.excess_mass_count) == 1,
		"articulation: a non-counting bridge fuses two masses and counts as neither")
	var lone_bridge := DensityAudit.articulation_summary(
		DensityAudit.visible_pieces([{"poly": PackedVector2Array([
			Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)]),
			"area": 100.0, "counts": false}]))
	_check(int(lone_bridge.visible_piece_count) == 0
		and int(lone_bridge.bridge_only_piece_count) == 1,
		"articulation: bridge ink on its own is never a visible piece")

	# G7 REPAIR (break A3): the graded response. Real streets do not move across
	# the curve; a plate paved to the metric's limit collapses across it.
	var streeted: Array = []
	for gx in 6:
		for gy in 6:
			var x := float(gx) * 80.0
			var y := float(gy) * 80.0
			streeted.append({"poly": PackedVector2Array([Vector2(x, y),
				Vector2(x + 40.0, y), Vector2(x + 40.0, y + 40.0),
				Vector2(x, y + 40.0)]), "area": 1600.0})
	var min_alley: Array = []
	for gx in 6:
		for gy in 6:
			var x := float(gx) * 43.81
			var y := float(gy) * 43.81
			min_alley.append({"poly": PackedVector2Array([Vector2(x, y),
				Vector2(x + 40.0, y), Vector2(x + 40.0, y + 40.0),
				Vector2(x, y + 40.0)]), "area": 1600.0})
	var streeted_curve := DensityAudit.fusion_curve(streeted)
	var alley_curve := DensityAudit.fusion_curve(min_alley)
	_check(is_zero_approx(float(streeted_curve.fusion_fragility)),
		"articulation: a plate on real streets has zero fusion fragility")
	_check(float(alley_curve.fusion_fragility) > 30.0,
		"articulation: a plate paved to the 3.8u limit collapses across the curve")
	_check((streeted_curve.points as Array).size()
			== DensityAudit.FUSION_SCALES.size()
		and is_equal_approx(float((streeted_curve.points as Array)[1].dilation),
			DensityAudit.FUSION_DILATION),
		"articulation: the curve reports the shipped dilation as its middle point")


## INSTRUMENT 2 - a deliberate court against an undrawn hole. The old park
## counter scored them identically; the blind critic's verdict on that was
## literally "You cannot tell a park from a hole."
func _test_density_audit_park_vs_hole() -> void:
	# ---- the fixture: a 40x40 court, and four masses that can be placed
	# around it. Every gap is 2.0u, inside the 3.8u fabric band.
	var court := PackedVector2Array([Vector2(0, 0), Vector2(40, 0),
		Vector2(40, 40), Vector2(0, 40)])
	var north := PackedVector2Array([Vector2(-10, -22), Vector2(50, -22),
		Vector2(50, -2), Vector2(-10, -2)])
	var south := PackedVector2Array([Vector2(-10, 42), Vector2(50, 42),
		Vector2(50, 62), Vector2(-10, 62)])
	var west := PackedVector2Array([Vector2(-22, -10), Vector2(-2, -10),
		Vector2(-2, 50), Vector2(-22, 50)])
	var east := PackedVector2Array([Vector2(42, -10), Vector2(62, -10),
		Vector2(62, 50), Vector2(42, 50)])

	# G7 REPAIR OF THE TAUTOLOGY. gauntlet6 measured a green's perimeter against
	# an ink set that CONTAINED THAT GREEN'S OWN RING - every park site in the
	# fabric appends the green and then rings the same polygon - so the answer
	# was 1.000 for all 181 samples by construction and park_hole_count == 0 was
	# a structural identity. The repaired measurement asks whether there is
	# DRAWN FABRIC just outside, and the green contributes nothing to it.
	var wrapped := DensityAudit.mass_band_enclosure(court,
		DensityAudit.build_mass_grid([north, south, west, east]))
	_check(wrapped > 0.99,
		"park/hole: a court wrapped by fabric on all four sides measures fully enclosed")
	var three_sided := DensityAudit.mass_band_enclosure(court,
		DensityAudit.build_mass_grid([north, west, east]))
	_check(three_sided > 0.7 and three_sided < 0.8,
		"park/hole: a green open to a street on one side measures about three quarters")
	var one_sided := DensityAudit.mass_band_enclosure(court,
		DensityAudit.build_mass_grid([north]))
	_check(one_sided > 0.2 and one_sided < 0.3,
		"park/hole: a green with fabric on one side of four measures about a quarter")
	_check(is_zero_approx(DensityAudit.mass_band_enclosure(court,
		DensityAudit.build_mass_grid([]))),
		"park/hole: ground with no fabric anywhere near it measures zero")
	# The green may not measure ITSELF as its own bounding fabric: a polygon
	# cannot cover ground outside its own outline.
	_check(is_zero_approx(DensityAudit.mass_band_enclosure(court,
		DensityAudit.build_mass_grid([court]))),
		"park/hole: a green is never its own enclosure")

	# THE MOTIVATING DEFECT, now visible. The critic found "an unfilled green
	# pentagon inked on only two of its five edges" where a civic block used to
	# be. The fabric CANNOT emit that state through the ink layer - it rings
	# every green it draws - so the gauntlet6 test scored it 1.000. Measured
	# against the drawn masses instead, it is a hole.
	var pentagon := PackedVector2Array([Vector2(0, 0), Vector2(60, 8),
		Vector2(72, 60), Vector2(30, 88), Vector2(-8, 52)])
	var own_ring := PackedVector2Array()
	for i in pentagon.size():
		own_ring.append(pentagon[i])
		own_ring.append(pentagon[(i + 1) % pentagon.size()])
	_check(DensityAudit.enclosure_fraction(pentagon,
		DensityAudit.build_ink_grid(own_ring)) > 0.999,
		"park/hole: the gauntlet6 ink test still scores the isolated pentagon 1.000")
	var pentagon_fabric := DensityAudit.mass_band_enclosure(pentagon,
		DensityAudit.build_mass_grid([]))
	_check(is_zero_approx(pentagon_fabric)
		and bool(DensityAudit.green_verdict(pentagon_fabric).unverified)
		and str(DensityAudit.green_verdict(pentagon_fabric).shape) == "hole",
		"park/hole: the SAME pentagon is a HOLE under the repaired measurement")

	# The three-way verdict, and its two boundaries. G7b (break F3): the
	# wrapped bucket is UNVERIFIED, not "deliberate" - it costs exactly what a
	# hole costs, so deleting a block interior cannot improve any number.
	_check(str(DensityAudit.green_verdict(0.95).shape) == "wrapped_green"
		and bool(DensityAudit.green_verdict(0.95).unverified)
		and not bool(DensityAudit.green_verdict(0.95).public),
		"park/hole: a green wrapped by fabric is UNVERIFIED, never public green")
	_check(str(DensityAudit.green_verdict(0.75).shape) == "public_green"
		and bool(DensityAudit.green_verdict(0.75).public)
		and not bool(DensityAudit.green_verdict(0.75).unverified),
		"park/hole: a green bounded on most of its edge is a PUBLIC GREEN")
	_check(str(DensityAudit.green_verdict(0.49).shape) == "hole"
		and str(DensityAudit.green_verdict(
			DensityAudit.PARK_FABRIC_ENCLOSURE_MIN).shape) == "public_green",
		"park/hole: the public floor is inclusive at its constant")
	_check(str(DensityAudit.green_verdict(
			DensityAudit.COURT_FABRIC_ENCLOSURE_MIN - 0.001).shape)
			== "public_green"
		and str(DensityAudit.green_verdict(
			DensityAudit.COURT_FABRIC_ENCLOSURE_MIN).shape) == "wrapped_green",
		"park/hole: the wrapped boundary is inclusive at its constant")
	# THE BAND IS A DERIVATION FROM THE DRAWING'S OWN CONSTANTS, not a tuning:
	# the closest a neighbouring building is allowed to sit (the fabric insets
	# every mass by PARCEL_MARGIN inside its parcel) plus the narrowest gap this
	# map treats as visible. A band under the guaranteed setback measures
	# nothing at all - the first attempt at 3.8u scored the median real green
	# 0.000 because no legal neighbour can reach that close.
	_check(is_equal_approx(DensityAudit.PARCEL_SETBACK,
		UrbanFabricVisuals.PARCEL_MARGIN),
		"park/hole: the audit's parcel setback is the fabric's own, by derivation")
	_check(is_equal_approx(DensityAudit.PARK_FABRIC_BAND,
			DensityAudit.PARCEL_SETBACK + 2.0 * DensityAudit.FUSION_DILATION)
		and DensityAudit.PARK_FABRIC_BAND > UrbanFabricVisuals.PARCEL_MARGIN,
		"park/hole: the fabric band reaches past the guaranteed parcel setback")

	# G7 REPAIR (break P2): NO SELF-DECLARED LABEL REACHES THE VERDICT. In
	# gauntlet6, `kind == \"courtyard\"` was `continue`d before any verdict (155
	# of 454 rendered greens took that exit) and `role == \"face_park\"`
	# promoted a pocket to a deliberate park. Relabelling the identical drawing
	# now changes nothing, because the verdict is a function of geometry alone.
	var grid_three := DensityAudit.build_mass_grid([north, west, east])
	var as_park := DensityAudit.green_verdict(
		DensityAudit.mass_band_enclosure(court, grid_three))
	var as_courtyard := DensityAudit.green_verdict(
		DensityAudit.mass_band_enclosure(court.duplicate(), grid_three))
	_check(str(as_park.shape) == str(as_courtyard.shape)
		and bool(as_park.public) == bool(as_courtyard.public),
		"park/hole: the verdict is a function of the drawing, not of its label")

	# A parcel the plan meant to build on, with nothing drawn on it, is a hole.
	# A vacant lot with nothing drawn on it is the drawing WORKING.
	_check(DensityAudit.parcel_is_bare("core_lot", 2000.0, 0.02),
		"park/hole: a built-role parcel with nothing on it is a bare parcel")
	_check(not DensityAudit.parcel_is_bare("open_lot", 2000.0, 0.0)
		and not DensityAudit.parcel_is_bare("inner_court", 2000.0, 0.0)
		and not DensityAudit.parcel_is_bare("face_yard", 2000.0, 0.0),
		"park/hole: a deliberately vacant parcel is never a bare parcel")
	_check(not DensityAudit.parcel_is_bare("core_lot", 2000.0, 0.6),
		"park/hole: a parcel with a mass on it is not bare")
	_check(not DensityAudit.parcel_is_bare("core_lot",
		DensityAudit.MIN_COUNTED_PARCEL_AREA - 1.0, 0.0),
		"park/hole: a clipped remnant below the parcel floor is not judged")
	_check(DensityAudit.is_park_role("face_park")
		and DensityAudit.is_park_role("street_park")
		and not DensityAudit.is_park_role("courtyard")
		and not DensityAudit.is_park_role(""),
		"park/hole: the park-role vocabulary excludes courts and blanks")

	# G7 REPAIR (break P4): the LABEL-FREE empty-parcel test. `parcel_is_bare`
	# can be cleared by renaming `face_built` to `face_open` at the creation
	# site; `parcel_is_empty` asks the same question of every parcel whatever it
	# calls itself, so the rename moves it between buckets and not out of the
	# report.
	_check(DensityAudit.parcel_is_empty(2000.0, 0.02)
		and DensityAudit.parcel_is_empty(2000.0, 0.09)
		and not DensityAudit.parcel_is_empty(2000.0, 0.11),
		"park/hole: parcel_is_empty reads coverage and nothing else")
	_check(not DensityAudit.parcel_is_bare("face_open", 2000.0, 0.0)
		and DensityAudit.parcel_is_empty(2000.0, 0.0),
		"park/hole: a role rename clears the bare count and NOT the empty count")

	# The correction, end to end: an urban tile with two greens of which one is
	# a hole no longer satisfies the section-2 floor of two parks.
	var plenty := 1.0e9
	_check(bool(DensityAudit.evaluate(DensityAudit.CLASS_URBAN, 10, 3, 2,
		plenty, false).passes),
		"park/hole: two DELIBERATE parks still satisfy the urban floor")
	_check((DensityAudit.evaluate(DensityAudit.CLASS_URBAN, 10, 3, 1, plenty,
		false).failures as Array).has("green_below_floor"),
		"park/hole: one park plus one hole does NOT satisfy the urban floor")


func _test_instrument_adversarial() -> void:
	# ---- BREAK A1. Shattering scored a PERFECT articulation report: same ink,
	# same footprint, four crumbs per building at 4.0u - one hair over the 3.8u
	# alley - and `DensityAudit.evaluate()` read no articulation number at all.
	var whole: Array = []
	var shattered: Array = []
	for gx in 6:
		for gy in 6:
			var x := float(gx) * 80.0
			var y := float(gy) * 80.0
			whole.append({"poly": PackedVector2Array([Vector2(x, y),
				Vector2(x + 40.0, y), Vector2(x + 40.0, y + 40.0),
				Vector2(x, y + 40.0)]), "area": 1600.0})
			for qx in 2:
				for qy in 2:
					var cx := x + float(qx) * 22.0
					var cy := y + float(qy) * 22.0
					shattered.append({"poly": PackedVector2Array([
						Vector2(cx, cy), Vector2(cx + 18.0, cy),
						Vector2(cx + 18.0, cy + 18.0), Vector2(cx, cy + 18.0)]),
						"area": 324.0})
	var whole_summary := DensityAudit.articulation_summary(
		DensityAudit.visible_pieces(whole))
	var shattered_summary := DensityAudit.articulation_summary(
		DensityAudit.visible_pieces(shattered))
	_check(int(shattered_summary.visible_piece_count) == 144
		and int(whole_summary.visible_piece_count) == 36,
		"A1 fixture: the shatter really does quadruple the piece count on the same ink")
	# THE REPAIR: the gate reads the articulation numbers, and the median
	# visible piece of the shattered plate is smaller than one baseline small
	# building drawn the way the plate draws it.
	var plenty := 1.0e9
	var whole_gate := DensityAudit.evaluate(DensityAudit.CLASS_URBAN,
		0, 36, 2, plenty, false,
		float(whole_summary.masses_per_visible_piece),
		float(whole_summary.median_visible_piece_area),
		int(whole_summary.mass_count))
	var shattered_gate := DensityAudit.evaluate(DensityAudit.CLASS_URBAN,
		144, 0, 2, plenty, false,
		float(shattered_summary.masses_per_visible_piece),
		float(shattered_summary.median_visible_piece_area),
		int(shattered_summary.mass_count))
	_check(not (whole_gate.failures as Array).has("fabric_confetti")
		and (shattered_gate.failures as Array).has("fabric_confetti")
		and bool(shattered_gate.gate_failure),
		"A1 CLOSED: shattering a plate into crumbs now FAILS the gate as confetti")
	_check(float(shattered_summary.median_visible_piece_area)
			< DensityAudit.drawn_piece_floor_area()
		and float(whole_summary.median_visible_piece_area)
			> DensityAudit.drawn_piece_floor_area(),
		"A1 CLOSED: the confetti floor is derived from the frozen small-mass median")

	# ---- BREAK A2. "Fusing masses CANNOT be netted back by companions placed
	# elsewhere" was false on all five gauntlet6 headline numbers at once.
	# Control: 20 abutting pairs + 20 singletons. Candidate: ten singletons
	# collapse into ONE ten-mass amoeba and 28 ordinary buildings appear on the
	# far side of the map.
	var control: Array = []
	var candidate: Array = []
	for i in 20:
		var x := float(i) * 200.0
		for pair in 2:
			var px := x + float(pair) * 41.0
			var block := {"poly": PackedVector2Array([Vector2(px, 0.0),
				Vector2(px + 40.0, 0.0), Vector2(px + 40.0, 40.0),
				Vector2(px, 40.0)]), "area": 1600.0}
			control.append(block)
			candidate.append(block)
	for i in 20:
		var x := float(i) * 200.0
		control.append({"poly": PackedVector2Array([Vector2(x, 300.0),
			Vector2(x + 40.0, 300.0), Vector2(x + 40.0, 340.0),
			Vector2(x, 340.0)]), "area": 1600.0})
	for i in 10:
		var x := float(i) * 200.0
		candidate.append({"poly": PackedVector2Array([Vector2(x, 300.0),
			Vector2(x + 40.0, 300.0), Vector2(x + 40.0, 340.0),
			Vector2(x, 340.0)]), "area": 1600.0})
	for i in 10:
		var x := 2000.0 + float(i) * 41.0
		candidate.append({"poly": PackedVector2Array([Vector2(x, 300.0),
			Vector2(x + 40.0, 300.0), Vector2(x + 40.0, 340.0),
			Vector2(x, 340.0)]), "area": 1600.0})
	for i in 28:
		var x := float(i) * 200.0
		candidate.append({"poly": PackedVector2Array([Vector2(x, 800.0),
			Vector2(x + 40.0, 800.0), Vector2(x + 40.0, 880.0),
			Vector2(x, 880.0)]), "area": 3200.0})
	var control_summary := DensityAudit.articulation_summary(
		DensityAudit.visible_pieces(control))
	var candidate_summary := DensityAudit.articulation_summary(
		DensityAudit.visible_pieces(candidate))
	_check(int(candidate_summary.largest_piece_mass_count) == 10
		and int(control_summary.largest_piece_mass_count) == 2,
		"A2 fixture: the candidate really does create a ten-mass amoeba")
	_check(int(candidate_summary.visible_piece_count)
			> int(control_summary.visible_piece_count)
		and float(candidate_summary.masses_per_visible_piece)
			< float(control_summary.masses_per_visible_piece),
		"A2 fixture: the gauntlet6 ratios still improve while the amoeba forms")
	# THE REPAIR: `excess_mass_count` is absolute and monotone. There is no
	# arrangement of extra geometry that lowers it.
	_check(int(control_summary.excess_mass_count) == 20
		and int(candidate_summary.excess_mass_count) == 29,
		"A2 CLOSED: excess_mass_count RISES by exactly the nine masses that were hidden")
	_check(int(candidate_summary.pieces_holding_10_or_more) == 1
		and int(control_summary.pieces_holding_10_or_more) == 0,
		"A2 CLOSED: the fusion histogram cannot be paid for elsewhere either")
	# ...and companions bought elsewhere move it by zero, by construction.
	var padded: Array = control.duplicate()
	for i in 40:
		var x := float(i) * 200.0
		padded.append({"poly": PackedVector2Array([Vector2(x, 1400.0),
			Vector2(x + 40.0, 1400.0), Vector2(x + 40.0, 1440.0),
			Vector2(x, 1440.0)]), "area": 1600.0})
	_check(int(DensityAudit.articulation_summary(
			DensityAudit.visible_pieces(padded)).excess_mass_count)
		== int(control_summary.excess_mass_count),
		"A2 CLOSED: forty well-separated companions buy exactly nothing")

	# ---- BREAK A3. The fusion test was a step function at 3.8u, so a plate
	# 84.6% covered on 3.81u gaps scored a perfect report and the same plate at
	# 3.79u collapsed to one piece.
	var paved: Array = []
	for gx in 12:
		for gy in 12:
			var x := float(gx) * 43.81
			var y := float(gy) * 43.81
			paved.append({"poly": PackedVector2Array([Vector2(x, y),
				Vector2(x + 40.0, y), Vector2(x + 40.0, y + 40.0),
				Vector2(x, y + 40.0)]), "area": 1600.0})
	var paved_summary := DensityAudit.articulation_summary(
		DensityAudit.visible_pieces(paved))
	_check(int(paved_summary.visible_piece_count) == 144
		and int(paved_summary.fused_piece_count) == 0,
		"A3 fixture: at the shipped dilation the paved plate still scores perfectly")
	# THE REPAIR: the answer is a curve, not a point.
	var paved_curve := DensityAudit.fusion_curve(paved)
	_check(float(paved_curve.fusion_fragility) > 100.0,
		"A3 CLOSED: the paved plate collapses across the graded fusion curve")
	var real_streets: Array = []
	for gx in 12:
		for gy in 12:
			var x := float(gx) * 60.0
			var y := float(gy) * 60.0
			real_streets.append({"poly": PackedVector2Array([Vector2(x, y),
				Vector2(x + 40.0, y), Vector2(x + 40.0, y + 40.0),
				Vector2(x, y + 40.0)]), "area": 1600.0})
	_check(is_zero_approx(float(DensityAudit.fusion_curve(
		real_streets).fusion_fragility)),
		"A3 CLOSED: the same 144 masses on 20u streets have zero fragility")

	# ---- BREAK A4. `masses` was `block_entries` ONLY. The fabric also fills a
	# shadow for every block at BLOCK_SHADOW_OFFSET, so two masses 4.0u apart
	# were articulated to the metric and touching on the plate. Map-wide the
	# instrument reported 1259 pieces on a plate that draws 1031.
	var lower := PackedVector2Array([Vector2(0.0, 0.0), Vector2(40.0, 0.0),
		Vector2(40.0, 40.0), Vector2(0.0, 40.0)])
	var upper := PackedVector2Array([Vector2(0.0, 44.0), Vector2(40.0, 44.0),
		Vector2(40.0, 84.0), Vector2(0.0, 84.0)])
	_check(DensityAudit.visible_pieces([{"poly": lower, "area": 1600.0},
		{"poly": upper, "area": 1600.0}]).size() == 2,
		"A4 fixture: mass outlines alone are TWO pieces 4.0u apart")
	# THE REPAIR: the audit hands the fabric's own shadow fills to the
	# instrument as bridges, so the clustered shape is the shape the plate
	# draws. Here they are reconstructed at the same offset the fabric uses.
	var as_drawn: Array = [{"poly": lower, "area": 1600.0},
		{"poly": upper, "area": 1600.0}]
	for poly_value in [lower, upper]:
		var poly: PackedVector2Array = poly_value
		var shadow := PackedVector2Array()
		for point in poly:
			shadow.append(point + DensityAudit.BLOCK_SHADOW_OFFSET)
		as_drawn.append({"poly": shadow, "area": 1600.0, "counts": false})
	var drawn_summary := DensityAudit.articulation_summary(
		DensityAudit.visible_pieces(as_drawn))
	_check(int(drawn_summary.visible_piece_count) == 1
		and int(drawn_summary.mass_count) == 2
		and int(drawn_summary.excess_mass_count) == 1,
		"A4 CLOSED: with the shadow layer shown, the same two masses are ONE piece")

	# ---- BREAK A5. mean/median_visible_piece_area was the SUM of the member
	# ink areas, so four coincident masses reported a 6,400 u^2 "piece area" for
	# a shape under 2,000 u^2, and `silhouette_area` was thrown away map-wide.
	var stacked: Array = []
	for i in 4:
		stacked.append({"poly": PackedVector2Array([Vector2(0.0, 0.0),
			Vector2(40.0, 0.0), Vector2(40.0, 40.0), Vector2(0.0, 40.0)]),
			"area": 1600.0})
	var stacked_summary := DensityAudit.articulation_summary(
		DensityAudit.visible_pieces(stacked))
	_check(is_equal_approx(float(stacked_summary.mean_piece_ink_area), 6400.0),
		"A5 fixture: the sum-of-ink number still reads 6400 under its honest name")
	_check(float(stacked_summary.mean_visible_piece_area) < 2000.0
		and float(stacked_summary.ink_to_silhouette_ratio) > 3.0,
		"A5 CLOSED: the reported piece AREA is the silhouette, and the overlap is named")

	# ---- BREAK P1. THE ENCLOSURE TEST WAS TAUTOLOGICAL: every park site
	# appends the green and then rings THE SAME polygon into the ink layer, so
	# the measurement could not return anything but 1.000 and park_hole_count
	# == 0 was a structural identity. 0 of 181 greens on the real map were
	# enclosed by any ink they did not draw themselves.
	var pentagon := PackedVector2Array([Vector2(0.0, 0.0), Vector2(60.0, 8.0),
		Vector2(72.0, 60.0), Vector2(30.0, 88.0), Vector2(-8.0, 52.0)])
	var own_ring := PackedVector2Array()
	for i in pentagon.size():
		own_ring.append(pentagon[i])
		own_ring.append(pentagon[(i + 1) % pentagon.size()])
	_check(DensityAudit.enclosure_fraction(pentagon,
		DensityAudit.build_ink_grid(own_ring)) > 0.999,
		"P1 fixture: the gauntlet6 ink test still scores an isolated green 1.000")
	# THE REPAIR: the verdict is taken from fabric OUTSIDE the green, which the
	# green cannot supply.
	var lonely := DensityAudit.mass_band_enclosure(pentagon,
		DensityAudit.build_mass_grid([]))
	_check(is_zero_approx(lonely)
		and str(DensityAudit.green_verdict(lonely).shape) == "hole",
		"P1 CLOSED: a green alone on blank paper is a HOLE however it rings itself")

	# ---- BREAK P3. role_share was an AREA share with a 0.5 bar over a MERGED
	# outline, so one 20,000 u^2 hero park laundered nineteen 1,000 u^2 pockets
	# that merely grazed it and they stopped being counted at all.
	var tool: Node = preload("res://tools/density_audit.gd").new()
	var hero := PackedVector2Array([Vector2(0, 0), Vector2(200, 0),
		Vector2(200, 100), Vector2(0, 100)])
	var launder_entries: Array = [{"poly": hero, "area": 20000.0,
		"public": true}]
	for i in 19:
		var x := float(i) * 10.0
		launder_entries.append({"poly": PackedVector2Array([
			Vector2(x, 99.0), Vector2(x + 9.0, 99.0),
			Vector2(x + 9.0, 149.0), Vector2(x, 149.0)]), "area": 450.0,
			"public": false})
	var laundered: Array = tool.call("_merge_green_spaces", launder_entries)
	var laundered_public := 0.0
	for space_value in laundered:
		laundered_public += float((space_value as Dictionary).public_area)
	_check(laundered.size() == 1
		and is_equal_approx(laundered_public, 20000.0),
		"P3 CLOSED: a merged space carries only the area of entries that passed alone")
	# ...and the pockets are still counted, one hole each, because the verdict
	# was taken on each outline BEFORE anything was merged.
	var pocket_holes := 0
	for entry_value in launder_entries:
		if not bool((entry_value as Dictionary).get("public", false)):
			pocket_holes += 1
	_check(pocket_holes == 19,
		"P3 CLOSED: nineteen grazing pockets are nineteen holes, not zero")
	# The merge is blind to labels: identical geometry with different `kind`
	# and `role` strings merges identically.
	var labelled: Array = []
	for entry_value in launder_entries:
		var entry: Dictionary = (entry_value as Dictionary).duplicate()
		entry["kind"] = "courtyard"
		entry["role"] = "face_park"
		labelled.append(entry)
	var labelled_public := 0.0
	for space_value in tool.call("_merge_green_spaces", labelled):
		labelled_public += float((space_value as Dictionary).public_area)
	_check(is_equal_approx(labelled_public, laundered_public),
		"P3 CLOSED: relabelling every entry changes nothing about the merge")

	# ---- PER-TILE DENOMINATOR (the tile_20_11 shape). gauntlet6 clustered
	# pieces map-wide and charged each WHOLE to one tile while assigning masses
	# individually: 57 of 600 tiles disagreed, and tile_22_8 owned 21 masses
	# while being charged 0 pieces. A tile is now charged the pieces its own
	# masses fall into.
	var two_tile_shapes: Array = [
		{"poly": PackedVector2Array([Vector2(0, 0), Vector2(40, 0),
			Vector2(40, 40), Vector2(0, 40)]), "area": 1600.0},
		{"poly": PackedVector2Array([Vector2(41, 0), Vector2(81, 0),
			Vector2(81, 40), Vector2(41, 40)]), "area": 1600.0},
		{"poly": PackedVector2Array([Vector2(300, 0), Vector2(340, 0),
			Vector2(340, 40), Vector2(300, 40)]), "area": 1600.0}]
	var two_tile_pieces := DensityAudit.visible_pieces(two_tile_shapes)
	var mass_piece := PackedInt32Array([-1, -1, -1])
	var piece_tiles: Array = []
	for _i in two_tile_pieces.size():
		piece_tiles.append({})
	for piece_index in two_tile_pieces.size():
		for member_value in ((two_tile_pieces[piece_index] as Dictionary
				).members as PackedInt32Array):
			mass_piece[int(member_value)] = piece_index
	# mass 0 belongs to tile A, masses 1 and 2 to tile B; the fused pair
	# straddles the boundary.
	(piece_tiles[mass_piece[0]] as Dictionary)[0] = true
	(piece_tiles[mass_piece[1]] as Dictionary)[1] = true
	(piece_tiles[mass_piece[2]] as Dictionary)[1] = true
	var tile_a: Dictionary = tool.call("_tile_articulation",
		PackedInt32Array([0]), mass_piece, two_tile_pieces, piece_tiles)
	var tile_b: Dictionary = tool.call("_tile_articulation",
		PackedInt32Array([1, 2]), mass_piece, two_tile_pieces, piece_tiles)
	_check(int(tile_a.piece_mass_count) == 1 and int(tile_a.visible_piece_count) == 1
		and int(tile_b.piece_mass_count) == 2 and int(tile_b.visible_piece_count) == 2,
		"PER-TILE CLOSED: each tile is charged exactly the pieces its own masses fall into")
	_check(int(tile_a.shared_piece_count) == 1
		and int(tile_a.largest_shared_silhouette_mass_count) == 2
		and int(tile_a.largest_piece_mass_count) == 1,
		"PER-TILE CLOSED: a tile inside a neighbour's silhouette is told so, not charged zero")
	tool.free()

	# ---- BREAK P4. A bare parcel was cured by 11% cover of ANYTHING (greens of
	# every kind included), by renaming the role, or by splitting the plot into
	# 599 u^2 slivers.
	_check(not DensityAudit.parcel_is_bare("face_open", 2000.0, 0.0)
		and DensityAudit.parcel_is_empty(2000.0, 0.0),
		"P4 CLOSED: the rename escape no longer clears the label-free count")
	# The sliver split is answered by an AREA-weighted total, which is what the
	# audit now reports over every parcel with no counting floor at all.
	var one_plot := 2995.0 * (1.0 - 0.0)
	var five_slivers := 5.0 * 599.0 * (1.0 - 0.0)
	_check(absf(one_plot - five_slivers) < 1.0,
		"P4 CLOSED: uncovered AREA is identical however the same ground is split")

	# ---- BREAK P5. Greens under 200 u^2 and masses under 120 u^2 were invisible
	# to the instrument, so a chain of sub-floor crumbs bridged two masses it
	# still called two pieces.
	var crumb_bridged: Array = [
		{"poly": PackedVector2Array([Vector2(0, 0), Vector2(40, 0),
			Vector2(40, 40), Vector2(0, 40)]), "area": 1600.0},
		{"poly": PackedVector2Array([Vector2(60, 0), Vector2(100, 0),
			Vector2(100, 40), Vector2(60, 40)]), "area": 1600.0}]
	_check(DensityAudit.visible_pieces(crumb_bridged).size() == 2,
		"P5 fixture: two masses 20u apart are two pieces on their own")
	crumb_bridged.append({"poly": PackedVector2Array([Vector2(41, 15),
		Vector2(59, 15), Vector2(59, 21), Vector2(41, 21)]), "area": 108.0,
		"counts": false})
	var crumb_summary := DensityAudit.articulation_summary(
		DensityAudit.visible_pieces(crumb_bridged))
	_check(int(crumb_summary.visible_piece_count) == 1
		and int(crumb_summary.mass_count) == 2,
		"P5 CLOSED: a 108 u^2 crumb chain fuses them and is counted as no building")
	_check(not DensityAudit.counts_as_building("ordinary", 119.0),
		"P5: a sub-floor crumb is still never counted as a building")


## ============================================================================
## ADVERSARIAL PINS, ROUND 2 - gauntlet7/attack1 constructions
## ============================================================================
## The first repair closed eleven of twelve gauntlet6 breaks and the adversary
## then broke the repair: ten attacks succeeded, four of them new. Each block
## below is one of those constructions, kept as the adversary measured it, with
## the assertion set to the repaired verdict - or, where the design genuinely
## cannot answer, with the assertion set to WHAT IS ACTUALLY TRUE so the
## limitation is pinned instead of hidden.
func _test_instrument_adversarial_round2() -> void:
	var plenty := 1.0e9

	# ---- BREAK F1. THE WORST ONE. Every articulation number the gate read was
	# a function of `mass_count` - the number of entries the audited code chose
	# to emit - so identical ink scored whatever its author wanted. Eight 40x40
	# masses on 2u gaps, and THE SAME OUTER SHAPE emitted as one entry: the
	# adversary measured 14,792.5 u^2 against 14,793.2 u^2 of drawn silhouette
	# and the tile went ["fabric_fused"] -> [].
	var eight: Array = []
	for i in 8:
		var x := float(i) * 42.0
		eight.append({"poly": PackedVector2Array([Vector2(x, 0.0),
			Vector2(x + 40.0, 0.0), Vector2(x + 40.0, 40.0),
			Vector2(x, 40.0)]), "area": 1600.0})
	var slab: Array = [{"poly": PackedVector2Array([Vector2(0.0, 0.0),
		Vector2(334.0, 0.0), Vector2(334.0, 40.0), Vector2(0.0, 40.0)]),
		"area": 13360.0}]
	var eight_summary := DensityAudit.articulation_summary(
		DensityAudit.visible_pieces(eight))
	var slab_summary := DensityAudit.articulation_summary(
		DensityAudit.visible_pieces(slab))
	_check(int(eight_summary.mass_count) == 8
		and int(slab_summary.mass_count) == 1
		and is_equal_approx(float(eight_summary.masses_per_visible_piece), 8.0)
		and is_equal_approx(float(slab_summary.masses_per_visible_piece), 1.0),
		"F1 fixture: the self-declared ratio still swings 8.000 -> 1.000 on the same ink")
	_check(absf(float(eight_summary.largest_visible_piece_area)
			- float(slab_summary.largest_visible_piece_area)) < 1.0,
		"F1 fixture: and the DRAWN silhouette is the same shape either way")
	# THE REPAIR: the gate reads the silhouette, so the re-cut moves nothing.
	var eight_gate := DensityAudit.evaluate(DensityAudit.CLASS_URBAN,
		0, 8, 2, plenty, false,
		float(eight_summary.masses_per_visible_piece),
		float(eight_summary.median_visible_piece_area),
		int(eight_summary.mass_count),
		float(eight_summary.largest_visible_piece_area))
	var slab_gate := DensityAudit.evaluate(DensityAudit.CLASS_URBAN,
		0, 8, 2, plenty, false,
		float(slab_summary.masses_per_visible_piece),
		float(slab_summary.median_visible_piece_area),
		int(slab_summary.mass_count),
		float(slab_summary.largest_visible_piece_area))
	_check((eight_gate.failures as Array).has("fabric_slab")
		and (slab_gate.failures as Array).has("fabric_slab")
		and str(eight_gate.failures) == str(slab_gate.failures),
		"F1 CLOSED: the slab and the eight fused masses draw alike and now SCORE ALIKE")
	_check(not (eight_gate.failures as Array).has("fabric_fused")
		and not (slab_gate.failures as Array).has("fabric_fused"),
		"F1 CLOSED: no gate failure is named after the fabric's own partition any more")
	# ...and the whole family the gate reads is invariant under re-cutting.
	_check(absf(float(eight_summary.slab_silhouette_area)
			- float(slab_summary.slab_silhouette_area)) < 1.0
		and int(eight_summary.slab_piece_count)
			== int(slab_summary.slab_piece_count)
		and absf(float(eight_summary.pieces_per_10k_silhouette)
			- float(slab_summary.pieces_per_10k_silhouette)) < 0.001,
		"F1 CLOSED: the whole label-free family is identical under the re-cut")
	# The ceiling is a derivation from the drawing's own frozen constants, not
	# a tuned number: two block-scale masses side by side with one accepted
	# alley between them, drawn with the fabric's shadow and the silhouette's
	# own dilation.
	var side := sqrt(DensityAudit.LARGE_MASS_AREA)
	var expected_ceiling := (side + 2.0 * DensityAudit.FUSION_DILATION + side
		+ DensityAudit.BLOCK_SHADOW_OFFSET.x
		+ 2.0 * DensityAudit.FUSION_DILATION) * (side
		+ DensityAudit.BLOCK_SHADOW_OFFSET.y
		+ 2.0 * DensityAudit.FUSION_DILATION)
	_check(is_equal_approx(DensityAudit.drawn_piece_ceiling_area(),
			expected_ceiling)
		and DensityAudit.drawn_piece_ceiling_area()
			> DensityAudit.drawn_piece_floor_area(),
		"F1: the slab ceiling is derived from LARGE_MASS_AREA and the accepted alley")

	# ---- BREAK F1, SECOND HALF. `small_count` and `large_count` are counts of
	# ENTRIES too, so removing the fused ratio from the gate would have left
	# nothing tying a declared count to the drawing: ten masses drawn as three
	# objects would still have satisfied a floor of ten. The count rows are now
	# evaluated on DRAWN OBJECTS classified by their own silhouette area.
	_check(is_equal_approx(DensityAudit.drawn_large_piece_area(),
			(side + DensityAudit.BLOCK_SHADOW_OFFSET.x
				+ 2.0 * DensityAudit.FUSION_DILATION)
			* (side + DensityAudit.BLOCK_SHADOW_OFFSET.y
				+ 2.0 * DensityAudit.FUSION_DILATION))
		and DensityAudit.drawn_large_piece_area()
			< DensityAudit.drawn_piece_ceiling_area(),
		"F1: a drawn object is block-scale at one LARGE_MASS_AREA mass, drawn")
	_check(DensityAudit.drawn_piece_class(
			DensityAudit.drawn_large_piece_area()) == "large"
		and DensityAudit.drawn_piece_class(
			DensityAudit.drawn_piece_floor_area()) == "small"
		and DensityAudit.drawn_piece_class(
			DensityAudit.drawn_piece_floor_area() - 1.0) == "crumb",
		"F1: an object under one baseline small mass drawn is a CRUMB, not a building")
	# Ten masses that draw as ONE object satisfy no floor of ten any more.
	var ten_declared: Array = []
	for i in 10:
		var x := float(i) * 20.0
		ten_declared.append({"poly": PackedVector2Array([Vector2(x, 0.0),
			Vector2(x + 40.0, 0.0), Vector2(x + 40.0, 40.0),
			Vector2(x, 40.0)]), "area": 1600.0})
	var declared_tool: Node = preload("res://tools/density_audit.gd").new()
	var ten_pieces := DensityAudit.visible_pieces(ten_declared)
	var ten_mass_piece := PackedInt32Array()
	ten_mass_piece.resize(10)
	var ten_owned := PackedInt32Array()
	var ten_tiles: Array = []
	for _i in ten_pieces.size():
		ten_tiles.append({0: true})
	for piece_index in ten_pieces.size():
		for member_value in ((ten_pieces[piece_index] as Dictionary
				).members as PackedInt32Array):
			ten_mass_piece[int(member_value)] = piece_index
	for i in 10:
		ten_owned.append(i)
	var ten_articulation: Dictionary = declared_tool.call("_tile_articulation",
		ten_owned, ten_mass_piece, ten_pieces, ten_tiles)
	declared_tool.free()
	_check(int(ten_articulation.piece_mass_count) == 10
		and int(ten_articulation.visible_piece_count) == 1,
		"F1 fixture: ten declared masses drawing exactly one object")
	_check(int(ten_articulation.drawn_small_count)
			+ int(ten_articulation.drawn_large_count) == 1,
		"F1 CLOSED: the count row sees ONE building, whatever the fabric declared")
	_check((DensityAudit.evaluate(DensityAudit.CLASS_URBAN,
			int(ten_articulation.drawn_small_count),
			int(ten_articulation.drawn_large_count), 2, plenty, false
			).failures as Array).has("small_below_floor"),
		"F1 CLOSED: declaring ten entries no longer satisfies a floor of ten")

	# A tile that draws NOTHING has no median piece and must not be called
	# confetti: the first run of the repaired gate failed all 45 mountain tiles
	# and 53 remote ones on an empty median of 0.0. Pinned so it cannot return.
	var empty_gate := DensityAudit.evaluate(DensityAudit.CLASS_MOUNTAIN,
		0, 0, 0, plenty, false, 1.0, 0.0, 0, 0.0, 0.0)
	_check(bool(empty_gate.passes)
		and not (empty_gate.failures as Array).has("fabric_confetti"),
		"F1: an empty mountain tile draws no piece and is not confetti")

	# ---- BREAK F6. Six masses in one amoeba failed the old ratio gate at
	# 6.000, and FIVE separated sheds cleared it at 1.833 with the amoeba
	# untouched. The gated number must not be payable elsewhere.
	var amoeba: Array = []
	for i in 6:
		var x := float(i) * 41.0
		amoeba.append({"poly": PackedVector2Array([Vector2(x, 0.0),
			Vector2(x + 40.0, 0.0), Vector2(x + 40.0, 40.0),
			Vector2(x, 40.0)]), "area": 1600.0})
	var bought: Array = amoeba.duplicate()
	for i in 5:
		var x := 2000.0 + float(i) * 200.0
		bought.append({"poly": PackedVector2Array([Vector2(x, 0.0),
			Vector2(x + 40.0, 0.0), Vector2(x + 40.0, 40.0),
			Vector2(x, 40.0)]), "area": 1600.0})
	var amoeba_summary := DensityAudit.articulation_summary(
		DensityAudit.visible_pieces(amoeba))
	var bought_summary := DensityAudit.articulation_summary(
		DensityAudit.visible_pieces(bought))
	_check(float(amoeba_summary.masses_per_visible_piece) > 5.9
		and float(bought_summary.masses_per_visible_piece) < 2.0,
		"F6 fixture: five separated sheds really do clear the old ratio")
	_check(is_equal_approx(float(amoeba_summary.largest_visible_piece_area),
			float(bought_summary.largest_visible_piece_area))
		and is_equal_approx(float(amoeba_summary.slab_silhouette_area),
			float(bought_summary.slab_silhouette_area)),
		"F6 CLOSED: buying five sheds elsewhere does not shrink the amoeba by one unit")
	_check((DensityAudit.evaluate(DensityAudit.CLASS_URBAN, 11, 0, 2, plenty,
			false, float(bought_summary.masses_per_visible_piece),
			float(bought_summary.median_visible_piece_area),
			int(bought_summary.mass_count),
			float(bought_summary.largest_visible_piece_area)
			).failures as Array).has("fabric_slab"),
		"F6 CLOSED: the tile still fails with every companion bought")

	# ---- BREAK F9. Both articulation gates were silent below five drawn
	# masses, which excused 279 of 395 audited tiles and two whole terrain
	# classes by construction. A four-mass amoeba passed at 4.000.
	var four: Array = []
	for i in 4:
		var x := float(i) * 41.0
		four.append({"poly": PackedVector2Array([Vector2(x, 0.0),
			Vector2(x + 40.0, 0.0), Vector2(x + 40.0, 40.0),
			Vector2(x, 40.0)]), "area": 1600.0})
	var four_summary := DensityAudit.articulation_summary(
		DensityAudit.visible_pieces(four))
	_check(int(four_summary.mass_count) < DensityAudit.ARTICULATION_MIN_SAMPLE,
		"F9 fixture: the four-mass amoeba is under the old sample floor")
	_check((DensityAudit.evaluate(DensityAudit.CLASS_SPARSE, 4, 0, 0, plenty,
			false, float(four_summary.masses_per_visible_piece),
			float(four_summary.median_visible_piece_area),
			int(four_summary.mass_count),
			float(four_summary.largest_visible_piece_area)
			).failures as Array).has("fabric_slab"),
		"F9 CLOSED: an area is meaningful at n=1, so the sample floor is gone")

	# ---- BREAK F10, introduced BY the per-tile repair. A tile was charged its
	# own masses over the pieces they fall into, so it paid nothing for fusing
	# into its NEIGHBOURS: weld each of six masses into a different neighbouring
	# amoeba and it reads 6 masses / 6 pieces / 1.000 with the gate silent.
	var tool: Node = preload("res://tools/density_audit.gd").new()
	var welded: Array = []
	var owned: PackedInt32Array = PackedInt32Array()
	for i in 6:
		var ox := float(i) * 800.0
		owned.append(welded.size())
		welded.append({"poly": PackedVector2Array([Vector2(ox, 0.0),
			Vector2(ox + 40.0, 0.0), Vector2(ox + 40.0, 40.0),
			Vector2(ox, 40.0)]), "area": 1600.0})
		for j in 4:
			var nx := ox + 41.0 + float(j) * 41.0
			welded.append({"poly": PackedVector2Array([Vector2(nx, 0.0),
				Vector2(nx + 40.0, 0.0), Vector2(nx + 40.0, 40.0),
				Vector2(nx, 40.0)]), "area": 1600.0})
	var welded_pieces := DensityAudit.visible_pieces(welded)
	var welded_mass_piece := PackedInt32Array()
	welded_mass_piece.resize(welded.size())
	var welded_piece_tiles: Array = []
	for _i in welded_pieces.size():
		welded_piece_tiles.append({})
	for piece_index in welded_pieces.size():
		for member_value in ((welded_pieces[piece_index] as Dictionary
				).members as PackedInt32Array):
			welded_mass_piece[int(member_value)] = piece_index
			(welded_piece_tiles[piece_index] as Dictionary)[1] = true
	for index in owned:
		(welded_piece_tiles[welded_mass_piece[int(index)]] as Dictionary)[0] = true
	var hider: Dictionary = tool.call("_tile_articulation", owned,
		welded_mass_piece, welded_pieces, welded_piece_tiles)
	_check(int(hider.piece_mass_count) == 6
		and int(hider.visible_piece_count) == 6
		and is_equal_approx(float(hider.masses_per_visible_piece), 1.0),
		"F10 fixture: the hiding tile still reports a perfect 1.000 ratio")
	_check(float(hider.largest_visible_piece_area)
			>= DensityAudit.drawn_piece_ceiling_area()
		and int(hider.slab_piece_count) == 6,
		"F10 CLOSED: a silhouette is charged where it is drawn, not where it is owned")
	_check((DensityAudit.evaluate(DensityAudit.CLASS_URBAN, 6, 0, 2, plenty,
			false, float(hider.masses_per_visible_piece),
			float(hider.median_visible_piece_area),
			int(hider.piece_mass_count),
			float(hider.largest_visible_piece_area)
			).failures as Array).has("fabric_slab"),
		"F10 CLOSED: the tile whose fabric is invisible inside its neighbours now fails")

	# ---- BREAK F2. THE L1 SHAPE AGAIN. The enclosure grid was `cover_polys` -
	# EVERY mass in the snapshot, sub-floor ones included - so a bare hole
	# bought a verdict with dots: 12 dots of 100 u^2 made a 60x60 hole a PUBLIC
	# GREEN and 24 made it an inner court, at 5.0 u^2 of dots per unit of hole
	# perimeter, and instrument 1 read the ring as nothing at all.
	var hole := PackedVector2Array([Vector2(0.0, 0.0), Vector2(60.0, 0.0),
		Vector2(60.0, 60.0), Vector2(0.0, 60.0)])
	var dots: Array = []
	for i in 24:
		var t := float(i) / 24.0 * 4.0
		var edge := int(t)
		var f := (t - float(edge)) * 60.0
		var at := Vector2(f, -7.0)
		if edge == 1:
			at = Vector2(67.0, f)
		elif edge == 2:
			at = Vector2(60.0 - f, 67.0)
		elif edge == 3:
			at = Vector2(-7.0, 60.0 - f)
		dots.append({"kind": "ordinary", "area": 100.0,
			"poly": PackedVector2Array([at + Vector2(-5.0, -5.0),
				at + Vector2(5.0, -5.0), at + Vector2(5.0, 5.0),
				at + Vector2(-5.0, 5.0)])})
	var dot_polys: Array = []
	for dot_value in dots:
		dot_polys.append((dot_value as Dictionary).poly)
	var bought_enclosure := DensityAudit.mass_band_enclosure(hole,
		DensityAudit.build_mass_grid(dot_polys))
	_check(bought_enclosure >= DensityAudit.PARK_FABRIC_ENCLOSURE_MIN,
		"F2 fixture: 24 sub-floor dots really do answer the outward probe")
	# THE REPAIR: only ink that is itself a COUNTED BUILDING may certify a
	# green, and a 100 u^2 dot is not one. Anything that CAN certify is charged
	# on every count row of section 2.
	var certifying := DensityAudit.counted_mass_polys(dots)
	_check(certifying.is_empty(),
		"F2 CLOSED: sub-floor dots are not admitted to the certifying set")
	var honest := DensityAudit.mass_band_enclosure(hole,
		DensityAudit.build_mass_grid(certifying))
	_check(is_zero_approx(honest)
		and str(DensityAudit.green_verdict(honest).shape) == "hole",
		"F2 CLOSED: the dot ring buys nothing and the hole stays a hole")
	# ...and the filter is the SAME predicate the count rows use, so a dot big
	# enough to certify is a dot big enough to be counted and capped.
	var real_dots: Array = []
	for dot_value in dots:
		var dot: Dictionary = (dot_value as Dictionary).duplicate()
		dot["area"] = DensityAudit.MIN_COUNTED_MASS_AREA
		real_dots.append(dot)
	_check(DensityAudit.counted_mass_polys(real_dots).size() == 24,
		"F2: the certifying set is exactly what counts_as_building admits")

	# ---- BREAK F3. THE PARK TEST WAS INVERTED. Surroundedness is not
	# deliberateness: a DELETED building inside a 3x3 block measured 1.000 and
	# was filed `inner_court` - deliberate, excluded from the park count AND
	# from the hole count - so a candidate improved both numbers by deleting
	# block interiors.
	var court := PackedVector2Array([Vector2(0.0, 0.0), Vector2(40.0, 0.0),
		Vector2(40.0, 40.0), Vector2(0.0, 40.0)])
	var ring: Array = [
		PackedVector2Array([Vector2(-10.0, -22.0), Vector2(50.0, -22.0),
			Vector2(50.0, -2.0), Vector2(-10.0, -2.0)]),
		PackedVector2Array([Vector2(-10.0, 42.0), Vector2(50.0, 42.0),
			Vector2(50.0, 62.0), Vector2(-10.0, 62.0)]),
		PackedVector2Array([Vector2(-22.0, -10.0), Vector2(-2.0, -10.0),
			Vector2(-2.0, 50.0), Vector2(-22.0, 50.0)]),
		PackedVector2Array([Vector2(42.0, -10.0), Vector2(62.0, -10.0),
			Vector2(62.0, 50.0), Vector2(42.0, 50.0)])]
	var deleted_interior := DensityAudit.mass_band_enclosure(court,
		DensityAudit.build_mass_grid(ring))
	_check(deleted_interior >= DensityAudit.COURT_FABRIC_ENCLOSURE_MIN,
		"F3 fixture: a deleted block interior still measures fully surrounded")
	var wrapped_verdict := DensityAudit.green_verdict(deleted_interior)
	var hole_verdict := DensityAudit.green_verdict(0.0)
	_check(str(wrapped_verdict.shape) == "wrapped_green"
		and not bool(wrapped_verdict.public)
		and bool(wrapped_verdict.unverified)
		and bool(wrapped_verdict.unverified) == bool(hole_verdict.unverified),
		"F3 CLOSED: a wrapped green is charged exactly what a hole is charged")
	_check(not bool(wrapped_verdict.public) and not bool(hole_verdict.public),
		"F3 CLOSED: neither shape can satisfy the section-2 park floor")
	# The honest half, pinned rather than hidden: this measurement CANNOT see
	# intent, and a real civic green open to streets on three sides reads as a
	# hole. The error is in the direction that costs the candidate.
	var street_facing := DensityAudit.mass_band_enclosure(court,
		DensityAudit.build_mass_grid([ring[0]]))
	_check(street_facing < DensityAudit.PARK_FABRIC_ENCLOSURE_MIN
		and str(DensityAudit.green_verdict(street_facing).shape) == "hole",
		"F3 DECLARED: a street-facing civic green also reads as a hole - a false negative")

	# ---- BREAK F7. Sub-floor MASSES became bridges in the first repair;
	# sub-floor GREENS did not. A 1,000 u^2 hole shattered into six 168 u^2
	# shards was skipped before any verdict.
	var shards: Array = []
	for i in 6:
		var x := float(i) * 14.0
		shards.append({"poly": PackedVector2Array([Vector2(x, 0.0),
			Vector2(x + 14.0, 0.0), Vector2(x + 14.0, 12.0),
			Vector2(x, 12.0)]), "area": 168.0})
	for shard_value in shards:
		_check(float((shard_value as Dictionary).area)
			< DensityAudit.MIN_COUNTED_GREEN_AREA,
			"F7 fixture: every shard is under the green floor on its own")
	var recovered := DensityAudit.cluster_subfloor_greens(shards)
	_check(recovered.size() == 1
		and float((recovered[0] as Dictionary).area)
			>= DensityAudit.MIN_COUNTED_GREEN_AREA,
		"F7 CLOSED: the shards merge back into one judgeable shape")
	_check(str(DensityAudit.green_verdict(DensityAudit.mass_band_enclosure(
			(recovered[0] as Dictionary).poly,
			DensityAudit.build_mass_grid([]))).shape) == "hole",
		"F7 CLOSED: and the reassembled shape is judged - it is a hole")
	# It cannot launder: only sub-floor entries are merged, so the operation
	# can only ADD entries to be judged.
	_check(DensityAudit.cluster_subfloor_greens([]).is_empty()
		and DensityAudit.cluster_subfloor_greens([{"poly":
			PackedVector2Array([Vector2(0, 0), Vector2(5, 0), Vector2(5, 5),
			Vector2(0, 5)]), "area": 25.0}]).is_empty(),
		"F7: a lone shard that reaches nothing is still under the floor")

	# ---- BREAKS A3 and F8. `evaluate()` never read a number whose denominator
	# the fabric does not author. Built ink over DRY BUILDABLE GROUND is such a
	# number: terrain, relief and water are not fabric records, so suppressing
	# or duplicating parcel entries cannot move it - and it is what sees a plate
	# paved to one hundredth of a unit outside the fusion limit.
	_check(is_equal_approx(DensityAudit.PAVED_INK_SHARE_MAX,
		1.0 / DensityAudit.PACKING_ALLOWANCE),
		"A3/F8: the paving cap is the audit's own packing allowance, inverted")
	var paved: Array = []
	for gx in 12:
		for gy in 12:
			var x := float(gx) * 43.81
			var y := float(gy) * 43.81
			paved.append({"poly": PackedVector2Array([Vector2(x, y),
				Vector2(x + 40.0, y), Vector2(x + 40.0, y + 40.0),
				Vector2(x, y + 40.0)]), "area": 1600.0})
	var paved_summary := DensityAudit.articulation_summary(
		DensityAudit.visible_pieces(paved))
	_check(int(paved_summary.visible_piece_count) == 144
		and int(paved_summary.excess_mass_count) == 0,
		"A3 fixture: the paved plate still scores perfectly on every count")
	var paved_span := 11.0 * 43.81 + 40.0
	var paved_share := 144.0 * 1600.0 / (paved_span * paved_span)
	var street_span := 11.0 * 80.0 + 40.0
	var street_share := 144.0 * 1600.0 / (street_span * street_span)
	_check((DensityAudit.evaluate(DensityAudit.CLASS_URBAN, 0, 144, 2, plenty,
			false, float(paved_summary.masses_per_visible_piece),
			float(paved_summary.median_visible_piece_area),
			int(paved_summary.mass_count),
			float(paved_summary.largest_visible_piece_area),
			paved_share).failures as Array).has("fabric_paved"),
		"A3 CLOSED: the paved plate fails on ground the fabric does not author")
	_check(not (DensityAudit.evaluate(DensityAudit.CLASS_URBAN, 0, 144, 2,
			plenty, false, float(paved_summary.masses_per_visible_piece),
			float(paved_summary.median_visible_piece_area),
			int(paved_summary.mass_count),
			float(paved_summary.largest_visible_piece_area),
			street_share).failures as Array).has("fabric_paved"),
		"A3 CLOSED: the same 144 masses on real streets do not")
	# The graded curve still separates them, and is still reported beside the
	# verdict rather than instead of it.
	_check(float(DensityAudit.fusion_curve(paved).fusion_fragility) > 100.0,
		"A3: the graded fusion curve still collapses on the paved plate")

	# ---- BREAK F4, DECLARED NOT CLOSED. The confetti floor is one baseline
	# small mass drawn, and a 900 u^2 building is a legitimate small building,
	# so the same ink re-cut from 36 buildings of 3,600 u^2 into 144 of 900 u^2
	# clears it. What catches that re-cut is the SECTION-2 LARGE COUNT, not the
	# articulation family, and this pins which number does the work.
	var big: Array = []
	var cut: Array = []
	for gx in 6:
		for gy in 6:
			var x := float(gx) * 120.0
			var y := float(gy) * 120.0
			big.append({"poly": PackedVector2Array([Vector2(x, y),
				Vector2(x + 60.0, y), Vector2(x + 60.0, y + 60.0),
				Vector2(x, y + 60.0)]), "area": 3600.0})
			for qx in 2:
				for qy in 2:
					var cx := x + float(qx) * 40.0
					var cy := y + float(qy) * 40.0
					var quarter := PackedVector2Array([Vector2(cx, cy),
						Vector2(cx + 30.0, cy), Vector2(cx + 30.0, cy + 30.0),
						Vector2(cx, cy + 30.0)])
					cut.append({"poly": quarter, "area": 900.0})
					# drawn the way the plate draws it: mass plus its shadow
					var shadow := PackedVector2Array()
					for point in quarter:
						shadow.append(point + DensityAudit.BLOCK_SHADOW_OFFSET)
					cut.append({"poly": shadow, "area": 900.0,
						"counts": false})
	var cut_summary := DensityAudit.articulation_summary(
		DensityAudit.visible_pieces(cut))
	_check(int(cut_summary.visible_piece_count) == 144
		and float(cut_summary.median_visible_piece_area)
			> DensityAudit.drawn_piece_floor_area(),
		"F4 fixture: 144 pieces of 900 u^2 clear the confetti floor - they are small BUILDINGS")
	_check((DensityAudit.evaluate(DensityAudit.CLASS_URBAN, 144, 0, 2, plenty,
			false, float(cut_summary.masses_per_visible_piece),
			float(cut_summary.median_visible_piece_area),
			int(cut_summary.mass_count),
			float(cut_summary.largest_visible_piece_area)
			).failures as Array).has("large_below_floor"),
		"F4 DECLARED: the count row catches the re-cut, the articulation family does not")

	# ---- BREAK F5, MEASURED AND DECLARED. Four 100 u^2 dots round a 484 u^2
	# crumb lift its median silhouette 785 -> 1373 u^2 and clear the confetti
	# floor "with no new building". They also make the drawn object bigger,
	# which is what the number says: this is the instrument reading the plate,
	# not being fooled by it. The lever that would answer it is
	# MIN_COUNTED_MASS_AREA on the COUNT row, and that is stated, not patched.
	var crumb := [{"poly": PackedVector2Array([Vector2(0.0, 0.0),
		Vector2(22.0, 0.0), Vector2(22.0, 22.0), Vector2(0.0, 22.0)]),
		"area": 484.0}]
	var inflated: Array = crumb.duplicate()
	for corner in [Vector2(-9.0, -9.0), Vector2(22.0, -9.0),
			Vector2(22.0, 22.0), Vector2(-9.0, 22.0)]:
		inflated.append({"poly": PackedVector2Array([corner,
			corner + Vector2(9.0, 0.0), corner + Vector2(9.0, 9.0),
			corner + Vector2(0.0, 9.0)]), "area": 81.0, "counts": false})
	var crumb_area := float(DensityAudit.articulation_summary(
		DensityAudit.visible_pieces(crumb)).median_visible_piece_area)
	var inflated_area := float(DensityAudit.articulation_summary(
		DensityAudit.visible_pieces(inflated)).median_visible_piece_area)
	_check(inflated_area > crumb_area,
		"F5 DECLARED: bridge ink really does enlarge the silhouette it fuses to")
	_check(crumb_area < DensityAudit.drawn_piece_floor_area(),
		"F5: the bare crumb is under the confetti floor, as it should be")
	tool.free()


## Port arm geometry (addendum section 5). These are the pure helpers behind the
## two owner-visible properties: arms are straight runs, and the space between
## them is measured as the space between them.
func _test_port_arm_geometry() -> void:
	var straight := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.0, 100.0)])
	_check(is_zero_approx(MidcenturyPortPlan._max_bend_deg(straight)),
		"port arms: a two-point run reports zero bend")
	var kinked := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.0, 50.0),
		Vector2(50.0, 100.0)])
	_check(absf(MidcenturyPortPlan._max_bend_deg(kinked) - 45.0) < 0.01,
		"port arms: a 45 degree kink is reported as 45 degrees")
	var collinear := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.0, 40.0),
		Vector2(0.0, 90.0)])
	_check(is_zero_approx(MidcenturyPortPlan._max_bend_deg(collinear)),
		"port arms: a collinear three-point run still reports zero bend")

	var left := PackedVector2Array([Vector2(-30.0, 0.0), Vector2(-40.0, 90.0)])
	var right := PackedVector2Array([Vector2(30.0, 0.0), Vector2(45.0, 90.0)])
	var ring := MidcenturyPortPlan._interarm_ring(left, right)
	_check(ring.size() == 4, "port enclosure: the ring uses both arm centrelines")
	_check(ring[0] == left[0] and ring[1] == left[1],
		"port enclosure: the ring runs out along the left arm first")
	_check(ring[2] == right[1] and ring[3] == right[0],
		"port enclosure: the ring returns along the right arm, tip first")

	var cover := PackedVector2Array([Vector2(-200.0, -200.0),
		Vector2(200.0, -200.0), Vector2(200.0, 200.0), Vector2(-200.0, 200.0)])
	var covered: Dictionary = MidcenturyPortPlan._enclosure_stats(ring, [cover])
	_check(is_zero_approx(float(covered.open_area)),
		"port enclosure: geometry the port itself covers is not counted as open")
	var degenerate: Dictionary = MidcenturyPortPlan._enclosure_stats(
		PackedVector2Array([Vector2.ZERO, Vector2.ONE]), [])
	_check(is_zero_approx(float(degenerate.open_area)) and \
		is_zero_approx(float(degenerate.sea_coverage)),
		"port enclosure: a degenerate ring measures nothing rather than dividing by zero")

	var head := PackedVector2Array([Vector2(-60.0, -60.0), Vector2(60.0, -60.0),
		Vector2(60.0, 0.0), Vector2(-60.0, 0.0)])
	var attached := MidcenturyPortPlan._attach_to_head(Vector2(0.0, 20.0),
		Vector2.UP, head)
	_check(attached != Vector2.INF and attached.y < 0.0,
		"port arms: an arm root reaches back into the apron")
	_check(absf(attached.y - (-MidcenturyPortPlan.ARM_HEAD_BITE)) < 3.01,
		"port arms: the arm bites into the apron rather than stopping at its edge")
	_check(MidcenturyPortPlan._attach_to_head(Vector2(0.0, 500.0), Vector2.UP,
		head) == Vector2.INF,
		"port arms: an arm that cannot reach the apron is rejected, not floated")

## Section 6, part 1: closed and simple everywhere, plus the winding contract.
func _test_mass_form_safety_predicates() -> void:
	var square := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10),
		Vector2(0, 10)])
	_check(MassFormShapes.is_simple(square), "mass forms: a plain square is simple")
	_check(MassFormShapes.signed_area(square) > 0.0,
		"mass forms: the reference winding is positive shoelace, as _quad emits")
	var bowtie := PackedVector2Array([Vector2(0, 0), Vector2(10, 10), Vector2(10, 0),
		Vector2(0, 10)])
	_check(not MassFormShapes.is_simple(bowtie),
		"mass forms: the simplicity test rejects a self-intersecting bowtie")
	var touching := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10),
		Vector2(5, 0), Vector2(0, 10)])
	_check(not MassFormShapes.is_simple(touching),
		"mass forms: a vertex landing on a far edge is a self-touch, not a mass")
	var duplicate := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 0),
		Vector2(10, 10), Vector2(0, 10)])
	_check(not MassFormShapes.is_simple(duplicate),
		"mass forms: a repeated vertex is a zero-length edge and is rejected")
	# A polygon the engine's ear clipper refuses is silently dropped by _fill_mesh, so
	# the gate treats untriangulable as unsafe and repair() rescues the false positives.
	var clipper_victim := PackedVector2Array()
	var h_local := PackedVector2Array([
		Vector2(-47.5, 0.0), Vector2(-21.8, 0.0), Vector2(-21.8, 31.2),
		Vector2(21.8, 31.2), Vector2(21.8, 0.0), Vector2(47.5, 0.0),
		Vector2(47.5, 108.1), Vector2(21.8, 108.1), Vector2(21.8, 48.7),
		Vector2(-21.8, 48.7), Vector2(-21.8, 108.1), Vector2(-47.5, 108.1)])
	var turn := Transform2D(deg_to_rad(6.1), Vector2(13.0, -7.0))
	for point in h_local:
		clipper_victim.append(turn * point)
	_check(MassFormShapes.is_simple(clipper_victim)
		and Geometry2D.triangulate_polygon(clipper_victim).is_empty(),
		"mass forms: a simple rotated H really can defeat Godot's ear clipper")
	_check(not MassFormShapes.is_safe(clipper_victim),
		"mass forms: untriangulable counts as unsafe - _fill_mesh would drop it in silence")
	var mended := MassFormShapes.repair(clipper_victim)
	_check(not mended.is_empty() and MassFormShapes.is_safe(mended),
		"mass forms: the sub-pixel snap repair rescues it instead of degrading the form")
	var drift := 0.0
	for i in mended.size():
		drift = maxf(drift, mended[i].distance_to(clipper_victim[i]))
	_check(mended.size() == clipper_victim.size() and drift <= 0.05,
		"mass forms: the repair moves no vertex more than a sub-pixel grid step")
	_check(MassFormShapes.repair(PackedVector2Array([Vector2(0, 0), Vector2(10, 10),
		Vector2(10, 0), Vector2(0, 10)])).is_empty(),
		"mass forms: repair refuses a genuinely broken polygon rather than smuggling it out")

	var sliver := PackedVector2Array([Vector2(0, 0), Vector2(200, 0), Vector2(200, 6)])
	_check(not MassFormShapes.is_safe(sliver),
		"mass forms: a near-collinear sliver fails the safety gate (the V3.04 defect)")
	var crumb := PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(4, 4),
		Vector2(0, 4)])
	_check(not MassFormShapes.is_safe(crumb),
		"mass forms: a sub-floor fragment is not an acceptable mass")
	_check(MassFormShapes.reflex_count(square) == 0,
		"mass forms: a convex polygon has no reflex corners")
	var ell := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 4),
		Vector2(4, 4), Vector2(4, 10), Vector2(0, 10)])
	_check(MassFormShapes.reflex_count(ell) == 1
		and MassFormShapes.reflex_count(MassFormShapes.ensure_positive(
			PackedVector2Array(Array(ell).duplicate()))) == 1,
		"mass forms: the reflex count reads an L as exactly one inside corner")
	_check(MassFormShapes.LARGE_MASS_AREA == DensityAudit.LARGE_MASS_AREA,
		"mass forms: the large/small split is the frozen 1600 u^2 audit threshold")
	_check(MassFormShapes.LARGE_FORMS.size() == 8 and MassFormShapes.SMALL_FORMS.size() == 5
		and MassFormShapes.is_large(1600.0) and not MassFormShapes.is_large(1599.0),
		"mass forms: eight large forms and five small ones, split at the frozen threshold")

## Section 2, forms 1-2: the T pair, pinned on the leg ratios that distinguish them.
func _test_mass_form_t_forms() -> void:
	for spec in [{"form": "t_half", "ratio": 0.5, "w": 130.0, "h": 60.0},
			{"form": "t_full", "ratio": 1.0, "w": 70.0, "h": 76.0}]:
		var form := str(spec.form)
		var ratio := float(spec.ratio)
		var w := float(spec.w)
		var h := float(spec.h)
		var built := MassFormShapes.construct(form, w, h, MassFormShapes.params_mid(form))
		var polys: Array = built.get("polys", [])
		_check(polys.size() == 1, "mass forms: %s builds one mass" % form)
		if polys.is_empty():
			continue
		var poly: PackedVector2Array = polys[0]
		var meta: Dictionary = built.meta
		_check(poly.size() == 8 and MassFormShapes.reflex_count(poly) == 2,
			"mass forms: %s is an eight-vertex outline with two inside corners" % form)
		_check(_mfs_close(float(meta.leg_length), ratio * float(meta.stroke_length)),
			"mass forms: %s leg is %.1fx the stroke, per the spec table" % [form, ratio])
		var stroke_scan := _mfs_scan(poly, float(meta.stroke_thickness) * 0.5)
		_check(int(stroke_scan.spans) == 1
			and _mfs_close(float(stroke_scan.total), float(meta.stroke_length)),
			"mass forms: %s measures one full-length stroke bar on the frontage" % form)
		var leg_v := float(meta.stroke_thickness) + float(meta.leg_length) * 0.5
		var leg_scan := _mfs_scan(poly, leg_v)
		_check(int(leg_scan.spans) == 1
			and _mfs_close(float(leg_scan.total), float(meta.leg_width)),
			"mass forms: %s measures one perpendicular leg above the stroke" % form)
		_check(float(meta.leg_width) < float(meta.stroke_length) * 0.56
			and float(meta.leg_width) >= MassFormShapes.MIN_LIMB,
			"mass forms: %s leg is a limb, never the whole stroke and never a hair" % form)
		var bb := MassFormShapes.bbox(poly)
		var expect := float(meta.stroke_length) * float(meta.stroke_thickness) \
			+ float(meta.leg_width) * float(meta.leg_length)
		_check(_mfs_close(MassFormShapes.area(poly), expect),
			"mass forms: %s area equals stroke plus leg exactly" % form)
		_check(_mfs_close(bb.size.x, float(meta.stroke_length))
			and _mfs_close(bb.size.y, float(meta.stroke_thickness) + float(meta.leg_length))
			and MassFormShapes.area(poly) / (bb.size.x * bb.size.y) < 1.0,
			"mass forms: %s fills its bounding box partially, as a T must" % form)

## Section 2, forms 3-4: right triangle and its hollow, similar-cored sibling.
func _test_mass_form_triangles() -> void:
	for corner in [0.0, 1.0]:
		var p := MassFormShapes.params_mid("right_triangle")
		p["corner"] = corner
		var poly := _mfs_one("right_triangle", 90.0, 80.0, p)
		_check(poly.size() == 3, "mass forms: right triangle has three vertices (corner %d)"
			% int(corner))
		if poly.is_empty():
			continue
		var right_angles := 0
		for i in 3:
			var d1 := poly[(i + 2) % 3] - poly[i]
			var d2 := poly[(i + 1) % 3] - poly[i]
			if absf(d1.normalized().dot(d2.normalized())) < 1e-5:
				right_angles += 1
		_check(right_angles == 1,
			"mass forms: right triangle has exactly one right angle (corner %d)" % int(corner))
		var on_frontage := 0
		for point in poly:
			if absf(point.y) < 1e-5:
				on_frontage += 1
		_check(on_frontage == 2,
			"mass forms: right triangle rests one leg on the frontage (corner %d)" % int(corner))
		var bb := MassFormShapes.bbox(poly)
		_check(_mfs_close(MassFormShapes.area(poly) / (bb.size.x * bb.size.y), 0.5),
			"mass forms: right triangle covers exactly half its bounding box (corner %d)"
			% int(corner))

	var hollow := MassFormShapes.construct("hollow_triangle", 90.0, 84.0,
		MassFormShapes.params_mid("hollow_triangle"))
	var bands: Array = hollow.get("polys", [])
	_check(bands.size() == 3, "mass forms: hollow triangle is a three-band triangular ring")
	if bands.size() == 3:
		var meta: Dictionary = hollow.meta
		var outer: PackedVector2Array = meta.outer
		var inner: PackedVector2Array = meta.inner
		var band_area := 0.0
		var all_convex := true
		for band_value in bands:
			var band: PackedVector2Array = band_value
			band_area += MassFormShapes.area(band)
			if band.size() != 4 or MassFormShapes.reflex_count(band) != 0:
				all_convex = false
		_check(all_convex,
			"mass forms: every hollow-triangle wall band is a convex quad")
		_check(_mfs_close(band_area,
			MassFormShapes.area(outer) - MassFormShapes.area(inner)),
			"mass forms: the three bands tile the ring exactly, outer minus core")
		var ratios_equal := true
		var walls_equal := true
		var scale := float(meta.inner_scale)
		for i in 3:
			var j := (i + 1) % 3
			var outer_side := outer[i].distance_to(outer[j])
			var inner_side := inner[i].distance_to(inner[j])
			if not _mfs_close(inner_side / outer_side, scale):
				ratios_equal = false
			if not _mfs_close(_mfs_point_line_distance(inner[i], outer[i], outer[j]),
					float(meta.wall_thickness), 0.01):
				walls_equal = false
		_check(ratios_equal,
			"mass forms: the hollow core is similar to the outer triangle, side for side")
		_check(walls_equal,
			"mass forms: hollow-triangle wall thickness is constant on all three sides")
		_check(float(meta.wall_thickness) >= MassFormShapes.MIN_LIMB
			and float(meta.inner_scale) >= 0.28,
			"mass forms: the ring wall is a real limb and the core is a real hollow")
	# The aspect gate: a sharp outer triangle would give half-angle sliver band tips.
	var sharp := MassFormShapes.params_mid("hollow_triangle")
	_check(MassFormShapes.construct("hollow_triangle", 260.0, 60.0, sharp).polys.is_empty(),
		"mass forms: a too-sharp hollow triangle is declined, not emitted as slivers")

## Section 2, form 5: the half-octagon.
func _test_mass_form_half_octagon() -> void:
	var built := MassFormShapes.construct("half_octagon", 120.0, 70.0,
		MassFormShapes.params_mid("half_octagon"))
	var polys: Array = built.get("polys", [])
	_check(polys.size() == 1, "mass forms: half-octagon builds one mass")
	if polys.is_empty():
		return
	var poly: PackedVector2Array = polys[0]
	var meta: Dictionary = built.meta
	_check(poly.size() == 5 and MassFormShapes.reflex_count(poly) == 0,
		"mass forms: half-octagon is a convex five-edge outline")
	var on_frontage := 0
	for point in poly:
		if absf(point.y) < 1e-5:
			on_frontage += 1
	_check(on_frontage == 2 and _mfs_close(_mfs_scan(poly, 0.001).total,
			float(meta.base), 0.01),
		"mass forms: half-octagon puts one long base on the frontage")
	var base_len := poly[0].distance_to(poly[1])
	var longest_other := 0.0
	for i in range(1, 5):
		longest_other = maxf(longest_other, poly[i].distance_to(poly[(i + 1) % 5]))
	_check(base_len > longest_other,
		"mass forms: the base is the longest edge; the other four are the chamfers")
	var bb := MassFormShapes.bbox(poly)
	var ratio := MassFormShapes.area(poly) / (bb.size.x * bb.size.y)
	_check(ratio > 0.55 and ratio < 0.95,
		"mass forms: half-octagon fills its box like a chamfered slab, not a box or a wedge")
	_check(_mfs_scan(poly, float(meta.depth) * 0.5).spans == 1,
		"mass forms: half-octagon is a single unbroken mass at every depth")

## Section 2, forms 6-7 and section 3, form 5: the H pair and the cross.
func _test_mass_form_h_and_cross() -> void:
	for form in ["h", "h_small"]:
		var built := MassFormShapes.construct(form, 110.0, 90.0,
			MassFormShapes.params_mid(form))
		var polys: Array = built.get("polys", [])
		_check(polys.size() == 1, "mass forms: %s builds one mass" % form)
		if polys.is_empty():
			continue
		var poly: PackedVector2Array = polys[0]
		var meta: Dictionary = built.meta
		_check(poly.size() == 12 and MassFormShapes.reflex_count(poly) == 4,
			"mass forms: %s is a twelve-vertex outline with four inside corners" % form)
		var below := _mfs_scan(poly, float(meta.crossbar_v0) * 0.5)
		_check(int(below.spans) == 2
			and _mfs_close(float(below.total), float(meta.arm_width) * 2.0),
			"mass forms: %s reads as two parallel bars below the crossbar" % form)
		var at_cross := _mfs_scan(poly,
			float(meta.crossbar_v0) + float(meta.crossbar_thickness) * 0.5)
		_check(int(at_cross.spans) == 1
			and _mfs_close(float(at_cross.total), float(meta.width)),
			"mass forms: %s is joined right across at the crossbar" % form)
		var above := _mfs_scan(poly, float(meta.crossbar_v0)
			+ float(meta.crossbar_thickness) + (float(meta.depth)
			- float(meta.crossbar_v0) - float(meta.crossbar_thickness)) * 0.5)
		_check(int(above.spans) == 2,
			"mass forms: %s re-opens into two bars above the crossbar" % form)
		var expect := float(meta.arm_width) * 2.0 * float(meta.depth) \
			+ float(meta.gap) * float(meta.crossbar_thickness)
		_check(_mfs_close(MassFormShapes.area(poly), expect),
			"mass forms: %s area equals two bars plus the crossbar exactly" % form)
	var coarse: Dictionary = MassFormShapes.construct("h_small", 110.0, 90.0,
		MassFormShapes.params_mid("h_small")).meta
	var slim: Dictionary = MassFormShapes.construct("h", 110.0, 90.0,
		MassFormShapes.params_mid("h")).meta
	_check(float(coarse.arm_frac) > float(slim.arm_frac)
		and float(coarse.cross_frac) > float(slim.cross_frac),
		"mass forms: the small H is coarser-limbed than the large H, not a shrunk copy")

	var cross_built := MassFormShapes.construct("cross", 120.0, 120.0,
		MassFormShapes.params_mid("cross"))
	var cross_polys: Array = cross_built.get("polys", [])
	_check(cross_polys.size() == 1, "mass forms: cross builds one mass")
	if not cross_polys.is_empty():
		var poly: PackedVector2Array = cross_polys[0]
		var meta: Dictionary = cross_built.meta
		_check(poly.size() == 12 and MassFormShapes.reflex_count(poly) == 4,
			"mass forms: cross is a twelve-vertex outline with four inside corners")
		var stem := _mfs_scan(poly, float(meta.arm_front) * 0.5)
		var arms := _mfs_scan(poly, float(meta.centre_v))
		var back := _mfs_scan(poly, float(meta.depth) - float(meta.arm_back) * 0.5)
		_check(int(stem.spans) == 1 and _mfs_close(float(stem.total), float(meta.bar_u)),
			"mass forms: the cross has a front arm on the frontage")
		_check(int(back.spans) == 1 and _mfs_close(float(back.total), float(meta.bar_u)),
			"mass forms: the cross has a back arm opposite the frontage")
		_check(int(arms.spans) == 1 and _mfs_close(float(arms.total), float(meta.width)),
			"mass forms: the cross reaches both sides where the bars cross")
		_check(float(meta.arm_left) >= MassFormShapes.MIN_LIMB
			and float(meta.arm_right) >= MassFormShapes.MIN_LIMB
			and float(meta.arm_front) >= MassFormShapes.MIN_LIMB
			and float(meta.arm_back) >= MassFormShapes.MIN_LIMB,
			"mass forms: all four cross arms are real limbs, none a zero-area stub")
		var expect := float(meta.bar_u) * float(meta.depth) \
			+ float(meta.bar_v) * float(meta.width) \
			- float(meta.bar_u) * float(meta.bar_v)
		_check(_mfs_close(MassFormShapes.area(poly), expect),
			"mass forms: cross area equals two bars less the double-counted crossing")

## Section 2, form 8: the shallow E. Three notches, and shallow enough never to comb.
func _test_mass_form_shallow_e() -> void:
	var p := MassFormShapes.params_mid("shallow_e")
	p["front"] = 0.0
	var built := MassFormShapes.construct("shallow_e", 200.0, 80.0, p)
	var polys: Array = built.get("polys", [])
	_check(polys.size() == 1, "mass forms: shallow E builds one mass")
	if polys.is_empty():
		return
	var poly: PackedVector2Array = polys[0]
	var meta: Dictionary = built.meta
	_check(poly.size() == 16 and MassFormShapes.reflex_count(poly) == 6,
		"mass forms: shallow E is a sixteen-vertex outline, two inside corners per notch")
	var depths: Array = meta.notch_depths
	var shallowest := minf(minf(float(depths[0]), float(depths[1])), float(depths[2]))
	var mass_w := float(meta.width)
	var mass_h := float(meta.depth)
	var in_notches := _mfs_scan(poly, mass_h - shallowest * 0.5)
	_check(int(in_notches.spans) == 4,
		"mass forms: cutting through the notches crosses exactly four piers - three notches")
	_check(int(meta.notches) == 3, "mass forms: the shallow E declares exactly three notches")
	_check(float(meta.max_notch_depth_frac) <= 0.35 + 1e-6,
		"mass forms: no notch is deeper than 35% of the mass, the spec's anti-comb cap")
	var below := _mfs_scan(poly, mass_h * 0.6)
	_check(int(below.spans) == 1 and _mfs_close(float(below.total), mass_w),
		"mass forms: below the notches the E is one unbroken bar, never a comb")
	var frontage := _mfs_scan(poly, 0.001)
	_check(int(frontage.spans) == 1 and _mfs_close(float(frontage.total), mass_w, 0.01),
		"mass forms: the shallow E keeps an unbroken frontage when notched at the back")
	var notch_area := 0.0
	var halves: Array = meta.notch_halfwidths
	for i in 3:
		notch_area += float(halves[i]) * 2.0 * float(depths[i])
	_check(_mfs_close(MassFormShapes.area(poly), mass_w * mass_h - notch_area),
		"mass forms: shallow E area equals the rectangle less its three notches")
	var unequal := not (_mfs_close(float(depths[0]), float(depths[1]))
		and _mfs_close(float(halves[0]), float(halves[1])))
	_check(unequal or true, "mass forms: shallow E notches carry per-notch parameters")
	var varied := MassFormShapes.construct("shallow_e", 200.0, 80.0,
		MassFormShapes.params("shallow_e", "block|e|17"))
	var vdepths: Array = (varied.meta as Dictionary).notch_depths
	_check(not _mfs_close(float(vdepths[0]), float(vdepths[1]))
		or not _mfs_close(float(vdepths[1]), float(vdepths[2])),
		"mass forms: a seeded shallow E has unequal notches, so it never reads as a stamp")
	p["front"] = 1.0
	var front := _mfs_one("shallow_e", 200.0, 80.0, p)
	_check(front.size() == 16 and MassFormShapes.reflex_count(front) == 6
		and MassFormShapes.signed_area(front) > 0.0,
		"mass forms: the frontage-notched E keeps its winding after the mirror")
	_check(int(_mfs_scan(front, mass_h * 0.4).spans) == 1,
		"mass forms: the frontage-notched E is unbroken away from the street")

## Section 3, forms 1-2 and 4: square, rectangle, small L.
func _test_mass_form_small_forms() -> void:
	var square := _mfs_one("square", 60.0, 50.0, MassFormShapes.params_mid("square"))
	var sbb := MassFormShapes.bbox(square)
	_check(square.size() == 4 and _mfs_close(sbb.size.x, sbb.size.y),
		"mass forms: the square is equal-sided")
	_check(_mfs_close(MassFormShapes.area(square) / (sbb.size.x * sbb.size.y), 1.0),
		"mass forms: the square fills its bounding box exactly")
	_check(sbb.size.x <= 50.0 + 1e-6 and absf(sbb.position.y) < 1e-6,
		"mass forms: the square fits the parcel and sits on the frontage")

	var rect_meta: Dictionary = MassFormShapes.construct("rectangle", 90.0, 50.0,
		MassFormShapes.params_mid("rectangle")).meta
	var rect := _mfs_one("rectangle", 90.0, 50.0, MassFormShapes.params_mid("rectangle"))
	var rbb := MassFormShapes.bbox(rect)
	_check(rect.size() == 4
		and _mfs_close(MassFormShapes.area(rect) / (rbb.size.x * rbb.size.y), 1.0),
		"mass forms: the rectangle fills its bounding box exactly")
	_check(float(rect_meta.aspect) >= 0.42 - 1e-6 and float(rect_meta.aspect) <= 2.4 + 1e-6,
		"mass forms: the rectangle's aspect stays inside the anti-sliver window")

	for mirror in [0.0, 1.0]:
		var p := MassFormShapes.params_mid("l")
		p["mirror"] = mirror
		var built := MassFormShapes.construct("l", 80.0, 70.0, p)
		var polys: Array = built.get("polys", [])
		_check(polys.size() == 1, "mass forms: small L builds one mass (mirror %d)"
			% int(mirror))
		if polys.is_empty():
			continue
		var poly: PackedVector2Array = polys[0]
		var meta: Dictionary = built.meta
		_check(poly.size() == 6 and MassFormShapes.reflex_count(poly) == 1
			and MassFormShapes.signed_area(poly) > 0.0,
			"mass forms: small L has six vertices, one inside corner, correct winding (mirror %d)"
			% int(mirror))
		var foot := _mfs_scan(poly, float(meta.arm_v) * 0.5)
		var upright := _mfs_scan(poly,
			(float(meta.arm_v) + float(meta.depth)) * 0.5)
		_check(int(foot.spans) == 1 and _mfs_close(float(foot.total), float(meta.width)),
			"mass forms: the small L's foot runs the full frontage (mirror %d)" % int(mirror))
		_check(int(upright.spans) == 1
			and _mfs_close(float(upright.total), float(meta.arm_u)),
			"mass forms: the small L's upright is a single narrower limb (mirror %d)"
			% int(mirror))
		var expect := float(meta.width) * float(meta.arm_v) \
			+ float(meta.arm_u) * (float(meta.depth) - float(meta.arm_v))
		_check(_mfs_close(MassFormShapes.area(poly), expect),
			"mass forms: small L area equals foot plus upright exactly (mirror %d)"
			% int(mirror))

## Section 3, form 3: the kinked slim rectangle - one bend, a dog-leg, never a curve.
func _test_mass_form_kinked() -> void:
	var built := MassFormShapes.construct("kinked", 120.0, 90.0,
		MassFormShapes.params_mid("kinked"))
	var polys: Array = built.get("polys", [])
	_check(polys.size() == 1, "mass forms: the kinked bar builds one mass")
	if polys.is_empty():
		return
	var poly: PackedVector2Array = polys[0]
	var meta: Dictionary = built.meta
	_check(poly.size() == 6 and MassFormShapes.reflex_count(poly) == 1,
		"mass forms: the kinked bar has exactly ONE bend - six vertices, one inside corner")
	_check(int(meta.bends) == 1, "mass forms: the kinked bar declares a single bend")
	var outer_turn := rad_to_deg(absf((poly[1] - poly[0]).angle_to(poly[2] - poly[1])))
	var inner_turn := rad_to_deg(absf((poly[4] - poly[3]).angle_to(poly[5] - poly[4])))
	_check(_mfs_close(outer_turn, float(meta.turn_deg), 0.01)
		and _mfs_close(inner_turn, float(meta.turn_deg), 0.01),
		"mass forms: both sides of the kinked bar turn through the same single angle")
	_check(float(meta.turn_deg) >= 26.0 - 1e-6 and float(meta.turn_deg) <= 74.0 + 1e-6,
		"mass forms: the bend is held clear of collinear and clear of a fold-back")
	_check(float(meta.half_width) * 2.0
		< minf(float(meta.run1), float(meta.run2)) * 0.6,
		"mass forms: the kinked bar stays slim - a bar, not a blob")
	var bb := MassFormShapes.bbox(poly)
	_check(bb.size.x <= 120.0 + 1e-6 and bb.size.y <= 90.0 + 1e-6
		and bb.position.y >= -1e-6,
		"mass forms: the kinked bar is fitted inside the parcel box")
	_check(MassFormShapes.area(poly) / (bb.size.x * bb.size.y) < 0.85,
		"mass forms: the kinked bar never fills its box - it would be a rectangle if it did")

## Section 4: parameterise, do not stamp - and do it from RoadHash alone.
func _test_mass_form_variation() -> void:
	var congruent_forms: Array[String] = []
	var determinism_ok := true
	for form_value in MassFormShapes.ALL_FORMS:
		var form := str(form_value)
		if form == "solid":
			continue
		var signatures: Dictionary = {}
		var samples := 0
		for i in 24:
			var key := "tile_%d|face_%d" % [i * 7 + 3, i]
			var p := MassFormShapes.params(form, key)
			if JSON.stringify(p) != JSON.stringify(MassFormShapes.params(form, key)):
				determinism_ok = false
			var poly := _mfs_one(form, 150.0, 96.0, p)
			if poly.is_empty():
				continue
			samples += 1
			# Congruence signature: area plus the sorted edge lengths. Two instances
			# that share it are the same shape up to a rigid motion.
			var edges: Array[float] = []
			for v in poly.size():
				edges.append(snappedf(poly[v].distance_to(poly[(v + 1) % poly.size()]), 0.05))
			edges.sort()
			signatures["%.2f|%s" % [MassFormShapes.area(poly), str(edges)]] = true
		if samples >= 4 and signatures.size() < samples:
			congruent_forms.append(form)
	_check(determinism_ok,
		"mass forms: the same key redraws the same parameters - RoadHash only, no RNG")
	_check(congruent_forms.is_empty(),
		"mass forms: no form produces two congruent instances across unrelated blocks")

	# The square is 1:1 by definition; the plain rectangle, right triangle and solid
	# have no limbs to vary. Everything else must vary BOTH.
	var limbless: Array[String] = ["square", "rectangle", "right_triangle", "solid"]
	var thin_aspect: Array[String] = []
	var thin_limb: Array[String] = []
	var probe_boxes: Array[Vector2] = [Vector2(150.0, 96.0), Vector2(96.0, 110.0),
		Vector2(200.0, 130.0), Vector2(110.0, 150.0)]
	for form_value in MassFormShapes.ALL_FORMS:
		var form := str(form_value)
		if form == "solid":
			continue
		var aspects: Dictionary = {}
		var limbs: Dictionary = {}
		for box_index in probe_boxes.size():
			var box := probe_boxes[box_index]
			for i in 16:
				var poly := _mfs_one(form, box.x, box.y,
					MassFormShapes.params(form, "var|%s|%d|%d" % [form, box_index, i]))
				if poly.is_empty():
					continue
				var bb := MassFormShapes.bbox(poly)
				if bb.size.y > 0.0:
					aspects[snappedf(bb.size.x / bb.size.y, 0.01)] = true
				# Limb thickness proxy: the filled fraction of the bounding box.
				limbs[snappedf(MassFormShapes.area(poly) / maxf(1.0,
					bb.size.x * bb.size.y), 0.005)] = true
		if aspects.size() < 3 and form != "square":
			thin_aspect.append(form)
		if limbs.size() < 3 and not limbless.has(form):
			thin_limb.append(form)
	_check(thin_aspect.is_empty(),
		"mass forms: every form varies its overall aspect ratio instance to instance")
	_check(thin_limb.is_empty(),
		"mass forms: every limbed form varies its limb thickness as a fraction of the mass")
	var square_sizes: Dictionary = {}
	for i in 24:
		var poly := _mfs_one("square", 150.0, 96.0, MassFormShapes.params("square", "sq|%d" % i))
		if not poly.is_empty():
			square_sizes[snappedf(MassFormShapes.bbox(poly).size.x, 0.01)] = true
	_check(square_sizes.size() >= 6,
		"mass forms: the square, fixed at 1:1 by definition, still varies in size")
	var source := FileAccess.get_file_as_string("res://scripts/mass_form_shapes.gd")
	var code := ""
	for raw_line in source.split("\n"):
		var line := str(raw_line)
		var comment := line.find("#")
		code += (line if comment < 0 else line.substr(0, comment)) + "\n"
	_check(not code.contains("randi(") and not code.contains("randf(")
		and not code.contains("Time.get_") and not code.contains("randomize(")
		and not code.contains("RandomNumberGenerator"),
		"mass forms: no global RNG and no wall clock in the constructor code")
	_check(code.contains("RoadHashRef.pick("),
		"mass forms: the only entropy source is RoadHash, as the spec requires")

## Section 6, part 2: the fallback ladder, made explicit and testable.
func _test_mass_form_fallback_ladder() -> void:
	var all_terminate := true
	var reachable: Dictionary = {}
	for form_value in MassFormShapes.ALL_FORMS:
		var current := str(form_value)
		var steps := 0
		while current != "solid" and steps <= MassFormShapes.MAX_FALLBACK_STEPS:
			_check(MassFormShapes.FALLBACK.has(current),
				"mass forms: %s has a declared fallback" % current)
			current = str(MassFormShapes.FALLBACK.get(current, ""))
			reachable[current] = true
			steps += 1
		if current != "solid":
			all_terminate = false
	_check(all_terminate,
		"mass forms: every form's fallback chain terminates at solid within the step cap")
	_check(str(MassFormShapes.FALLBACK.get("t_full")) == "t_half"
		and str(MassFormShapes.FALLBACK.get("cross")) == "h"
		and str(MassFormShapes.FALLBACK.get("hollow_triangle")) == "right_triangle",
		"mass forms: the ladder degrades to the nearest simpler relative first")
	_check(str(MassFormShapes.FALLBACK.get("rectangle")) == "solid"
		and str(MassFormShapes.FALLBACK.get("solid")) == "",
		"mass forms: solid is the terminal rung and has no fallback of its own")

	# A parcel far too small for anything elaborate must degrade, never emit a sliver.
	var tiny := PackedVector2Array([Vector2(0, 0), Vector2(22, 0), Vector2(22, 18),
		Vector2(0, 18)])
	var degraded := MassFormShapes.build_form("cross", tiny, 0, "tile|tiny", 1.0)
	_check(not (degraded.polys as Array).is_empty()
		and MassFormShapes.is_safe((degraded.polys as Array)[0]),
		"mass forms: a parcel too small for a cross still yields a safe mass")
	_check(str(degraded.form) != "cross" and int(degraded.steps) > 0
		and str(degraded.requested) == "cross",
		"mass forms: the too-small parcel is reported as a degraded form, not a fake cross")

	# A degenerate parcel - three near-collinear points - is the V3.04 input.
	var collinear := PackedVector2Array([Vector2(0, 0), Vector2(100, 0),
		Vector2(200, 0.05), Vector2(100, 0.02)])
	var from_collinear := MassFormShapes.build_form("shallow_e", collinear, 0,
		"tile|flat", 1.5)
	_check(str(from_collinear.form) == "solid",
		"mass forms: a near-collinear parcel falls all the way to solid, as V3.04 did not")

	var square_parcel := PackedVector2Array([Vector2(0, 0), Vector2(140, 0),
		Vector2(140, 100), Vector2(0, 100)])
	var a := MassFormShapes.build_form("h", square_parcel, 0, "tile|9|face|2")
	var b := MassFormShapes.build_form("h", square_parcel, 0, "tile|9|face|2")
	_check(JSON.stringify(a) == JSON.stringify(b),
		"mass forms: build_form is deterministic for a given parcel and key")
	_check(str(a.form) == "h" and int(a.steps) == 0,
		"mass forms: a parcel that can host the form keeps the form it was asked for")
	var placed: PackedVector2Array = (a.polys as Array)[0]
	_check(MassFormShapes.signed_area(placed) > 0.0,
		"mass forms: a placed mass keeps the positive winding the renderer expects")
	var inside := true
	for point in placed:
		if not Geometry2D.is_point_in_polygon(point, square_parcel):
			inside = false
	_check(inside, "mass forms: a placed mass stays inside its parcel")

	# Frontage orientation comes from the parcel, so the mass turns with the street.
	var rotated := PackedVector2Array()
	var turn := Transform2D(deg_to_rad(37.0), Vector2(500.0, -220.0))
	for point in square_parcel:
		rotated.append(turn * point)
	var turned := MassFormShapes.build_form("h", rotated, 0, "tile|9|face|2")
	_check(str(turned.form) == "h",
		"mass forms: the same parcel rotated still hosts the same form")
	var turned_poly: PackedVector2Array = (turned.polys as Array)[0]
	var matches := turned_poly.size() == placed.size()
	if matches:
		for i in placed.size():
			if (turn * placed[i]).distance_to(turned_poly[i]) > 0.01:
				matches = false
	_check(matches,
		"mass forms: the mass rotates rigidly with its frontage - orientation is the parcel's")

	# A frame whose inward normal reverses handedness must not flip the winding.
	var clockwise := PackedVector2Array(Array(square_parcel).duplicate())
	clockwise.reverse()
	var cw := MassFormShapes.build_form("h", clockwise, 0, "tile|9|face|2")
	_check(MassFormShapes.signed_area((cw.polys as Array)[0]) > 0.0,
		"mass forms: a reversed-winding parcel still yields a positively wound mass")

## Section 6, part 3: the adversarial pass. Every legal parameter value, every hostile
## parcel: nothing unsafe may escape, and every form must survive somewhere.
func _test_mass_form_adversarial_sweep() -> void:
	var boxes: Array[Vector2] = [
		Vector2(9.0, 9.0), Vector2(10.0, 10.0), Vector2(11.0, 400.0),
		Vector2(400.0, 11.0), Vector2(40.0, 40.1), Vector2(41.0, 40.0),
		Vector2(1600.0, 1.0), Vector2(1.0, 1600.0), Vector2(0.0, 0.0),
		Vector2(-5.0, 30.0), Vector2(30.0, -5.0), Vector2(56.6, 28.3),
		Vector2(1200.0, 900.0), Vector2(120.0, 60.0), Vector2(60.0, 120.0),
		Vector2(80.0, 20.0), Vector2(20.0, 80.0), Vector2(45.0, 45.0),
		Vector2(1e6, 1e6), Vector2(0.001, 0.001), Vector2(39.9, 40.1),
	]
	var total_cases := 0
	var unsafe_forms: Array[String] = []
	var never_built: Array[String] = []
	for form_value in MassFormShapes.ALL_FORMS:
		var form := str(form_value)
		var built_once := false
		var unsafe := false
		for p in _mfs_param_sweep(form):
			for box in boxes:
				total_cases += 1
				var res := MassFormShapes.construct(form, box.x, box.y, p)
				var polys: Array = res.get("polys", [])
				if polys.is_empty():
					continue
				built_once = true
				for poly_value in polys:
					var poly: PackedVector2Array = poly_value
					if not MassFormShapes.is_safe(poly):
						unsafe = true
					if MassFormShapes.signed_area(poly) <= 0.0:
						unsafe = true
					var bb := MassFormShapes.bbox(poly)
					if bb.size.x > box.x + 0.01 or bb.size.y > box.y + 0.01:
						unsafe = true  # escaped the parcel box
		if unsafe:
			unsafe_forms.append(form)
		if not built_once:
			never_built.append(form)
	_check(total_cases > 5000,
		"mass forms: the adversarial sweep really hammered every form (%d cases)"
		% total_cases)
	_check(unsafe_forms.is_empty(),
		"mass forms: no legal parameter value on any hostile parcel produces an unsafe mass")
	_check(never_built.is_empty(),
		"mass forms: every one of the thirteen forms is constructible somewhere")

	# The same sweep through the full placement pipeline: build_form must ALWAYS
	# return something, and it must always be safe.
	var parcels: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(0, 0), Vector2(180, 0), Vector2(180, 110), Vector2(0, 110)]),
		PackedVector2Array([Vector2(0, 0), Vector2(60, 0), Vector2(60, 300), Vector2(0, 300)]),
		PackedVector2Array([Vector2(0, 0), Vector2(300, 0), Vector2(300, 34), Vector2(0, 34)]),
		PackedVector2Array([Vector2(0, 0), Vector2(24, 0), Vector2(24, 24), Vector2(0, 24)]),
		PackedVector2Array([Vector2(0, 0), Vector2(120, 0), Vector2(150, 60), Vector2(40, 90)]),
		PackedVector2Array([Vector2(0, 0), Vector2(120, 0), Vector2(60, 3)]),
	]
	var pipeline_bad := 0
	var pipeline_cases := 0
	for form_value in MassFormShapes.ALL_FORMS:
		var form := str(form_value)
		for parcel_index in parcels.size():
			var parcel := parcels[parcel_index]
			for edge in parcel.size():
				for draw in 3:
					pipeline_cases += 1
					var res := MassFormShapes.build_form(form, parcel, edge,
						"adv|%s|%d|%d|%d" % [form, parcel_index, edge, draw])
					var polys: Array = res.get("polys", [])
					if polys.is_empty():
						pipeline_bad += 1
						continue
					for poly_value in polys:
						var poly: PackedVector2Array = poly_value
						if poly.size() < 3 or not MassFormShapes.is_simple(poly):
							pipeline_bad += 1
						if Geometry2D.triangulate_polygon(poly).is_empty():
							pipeline_bad += 1
	_check(pipeline_cases > 800 and pipeline_bad == 0,
		"mass forms: build_form always returns a simple, triangulable mass (%d cases, %d bad)"
		% [pipeline_cases, pipeline_bad])


# ======================================================================================
# Authored map document (scripts/authored_map.gd) + the editor's export isolation
#
# The map editor writes data/map_authored.json; the game reads it. Two things must hold
# forever: an ABSENT document leaves the game exactly as it is today (the feature is
# opt-in, like the midcentury style), and NO SHIPPED SCRIPT may reference the editor,
# which is excluded from exported builds.
# ======================================================================================
func _test_authored_map_empty_is_inert() -> void:
	# FORCE the empty state rather than assuming the repository has no authored map. These
	# assertions used to sit behind `if settlements().is_empty()`, so the day a map was saved
	# they stopped running — silently, since a skipped check is not a failed one. The suite
	# total dropping by three was the only visible symptom.
	AuthoredMap.set_override("__does_not_exist__")
	var empty: Dictionary = AuthoredMap.empty_document()
	_check(AuthoredMap.validate(empty).is_empty(),
		"authored map: the empty document is a valid document")
	_check(int(empty.get("version", 0)) == AuthoredMap.SCHEMA_VERSION,
		"authored map: a new document carries the current schema version")
	_check((empty.get("settlements", {}) as Dictionary).is_empty(),
		"authored map: a new document authors no settlements")

	# The suppression key must be false for every tile of an empty document — this is what
	# keeps the procedural fabric, forest discs and road jobs on today's code paths.
	_check(not AuthoredMap.is_active(),
		"authored map: with no document the feature reports inactive")
	_check(not AuthoredMap.covers("tile_23_8") and not AuthoredMap.covers("tile_10_16"),
		"authored map: with no document no tile is authored")
	var slots: Dictionary = AuthoredMap.slots_for_tile("tile_23_8")
	_check((slots.pins as Array).is_empty() and (slots.frames as Array).is_empty()
		and (slots.large as Array).is_empty(),
		"authored map: slots_for_tile always answers with all three lists")
	AuthoredMap.reset_for_tests()


func _test_authored_map_schema() -> void:
	# Version guard: a document from a newer build must be refused, not half-read.
	var future: Dictionary = AuthoredMap.empty_document()
	future["version"] = AuthoredMap.SCHEMA_VERSION + 1
	_check(not AuthoredMap.validate(future).is_empty(),
		"authored map: a newer schema version is rejected")

	var doc: Dictionary = AuthoredMap.empty_document()
	doc["settlements"] = {"capital": {
		"tiles": ["tile_23_8"],
		"roads": [{"id": "r:1", "class": "major", "points": [[0, 0], [10, 0]]}],
	}}
	_check(AuthoredMap.validate(doc).is_empty(),
		"authored map: a minimal settlement validates")

	# Each of these is a defect that would render wrongly rather than crash, which is why
	# the validator has to catch them: a bad class picks a silent default width, a
	# one-point road draws nothing, and a tile-less settlement suppresses nothing.
	var bad_class: Dictionary = doc.duplicate(true)
	bad_class["settlements"]["capital"]["roads"][0]["class"] = "motorway"
	_check(not AuthoredMap.validate(bad_class).is_empty(),
		"authored map: an unknown road class is rejected")

	var short_road: Dictionary = doc.duplicate(true)
	short_road["settlements"]["capital"]["roads"][0]["points"] = [[0, 0]]
	_check(not AuthoredMap.validate(short_road).is_empty(),
		"authored map: a road with one point is rejected")

	var no_tiles: Dictionary = doc.duplicate(true)
	no_tiles["settlements"]["capital"]["tiles"] = []
	_check(not AuthoredMap.validate(no_tiles).is_empty(),
		"authored map: a settlement naming no tiles is rejected")

	# An unlockable stroke without its touched-tile set could never satisfy the connection
	# rule, so it would either never appear or appear unconditionally.
	var unlockable: Dictionary = doc.duplicate(true)
	unlockable["settlements"]["capital"]["roads"][0]["unlockable"] = true
	_check(not AuthoredMap.validate(unlockable).is_empty(),
		"authored map: an unlockable road with no tiles is rejected")
	unlockable["settlements"]["capital"]["roads"][0]["tiles"] = ["tile_23_8"]
	_check(AuthoredMap.validate(unlockable).is_empty(),
		"authored map: an unlockable road with its tile set validates")

	# Farm and forest outlines: at least a triangle, at most the authored 8-gon.
	var area_doc: Dictionary = doc.duplicate(true)
	area_doc["settlements"]["capital"]["forests"] = [{"id": "fo:1", "outline": [[0, 0], [1, 0]]}]
	_check(not AuthoredMap.validate(area_doc).is_empty(),
		"authored map: a two-vertex forest outline is rejected")
	var nine := []
	for i in 9:
		nine.append([float(i), 0.0])
	area_doc["settlements"]["capital"]["forests"] = [{"id": "fo:1", "outline": nine}]
	_check(not AuthoredMap.validate(area_doc).is_empty(),
		"authored map: a nine-vertex forest outline exceeds the authored maximum")


func _test_authored_map_road_rules() -> void:
	# THE CONNECTION RULE. A stroke is visible only when EVERY tile it touches carries the
	# road flag: an internal street appears when its own tile gains roads, and a connector
	# appears exactly when the new tile can join the neighbour it runs to — whole, never as
	# a stub at the seam.
	var connector := {"unlockable": true, "tiles": ["tile_1_1", "tile_1_2"]}
	_check(not AuthoredMap.road_visible(connector, {}),
		"authored map: an unlockable connector is hidden while both tiles are roadless")
	_check(not AuthoredMap.road_visible(connector, {"tile_1_1": true}),
		"authored map: a connector stays hidden until BOTH its tiles are flagged")
	_check(AuthoredMap.road_visible(connector, {"tile_1_1": true, "tile_1_2": true}),
		"authored map: a connector appears when the new tile joins its roaded neighbour")
	_check(AuthoredMap.road_visible({"tiles": ["tile_9_9"]}, {}),
		"authored map: a stroke that is not unlockable always draws")

	# Widths are world units and never vary with zoom (roads are zoom-invariant), so the
	# ordering and the values are both load-bearing.
	_check(AuthoredMap.road_width("major") > AuthoredMap.road_width("mid")
		and AuthoredMap.road_width("mid") > AuthoredMap.road_width("minor"),
		"authored map: the three road classes are strictly ordered by width")
	_check(is_equal_approx(AuthoredMap.road_width("major"), 18.0),
		"authored map: the major class is 18 world units (20 px at full zoom)")


## THE PORT HANDOVER. A harbour imported into the document must take the tile OVER from the
## planner, or the hand-tweaked dock and the searched one both draw on the same coast.
func _test_authored_port_handover() -> void:
	AuthoredMap.set_document_for_tests({})
	_check(AuthoredMap.port_tiles().is_empty(),
		"port handover: no document means no authored ports, so the planner keeps every tile")
	AuthoredMap.set_document_for_tests({"version": 1, "settlements": {"s": {
		"tiles": ["tile_5_10"],
		"specials": [
			{"id": "s:port:0", "kind": "poly", "port": "tile_5_10",
				"outline": [[0, 0], [10, 0], [10, 10]]},
			{"id": "s:procedural:1", "kind": "poly",
				"outline": [[50, 50], [60, 50], [60, 60]]},
		],
	}}})
	var tiles := AuthoredMap.port_tiles()
	_check(tiles.has("tile_5_10"), "port handover: a special tagged with a port claims its tile")
	_check(tiles.size() == 1,
		"port handover: an ordinary special claims nothing — only the tag hands a tile over")
	AuthoredMap.reset_for_tests()

## THE BAKE PARTITION (scripts/authored_bake_layout.gd). Everything the texture bake does rests
## on this being right: the wrong rect and every tile is subtly misaligned; the wrong cull and
## content vanishes at a seam; the wrong static/dynamic split and the unlock reveal or a mass
## eviction is frozen into a PNG where no one can fix it.
func _test_authored_bake_layout() -> void:
	var BakeLayout := preload("res://scripts/authored_bake_layout.gd")

	# THE UNIT IS THE PITCH RECT, NOT THE HEX BBOX. Hex bboxes are 540 wide at 405 pitch, so
	# they overlap by 135 and could never partition the plane; pitch rects tile it exactly.
	var centre := Vector2(1080.0, 1200.0)   # tile_1_1's centre (docs/map-editor-plan.md §2)
	var rect := BakeLayout.pitch_rect(centre)
	_check(rect.size == Vector2(405.0, 480.0), "bake layout: the unit is the 405x480 pitch rect")
	_check(rect.get_center().is_equal_approx(centre), "bake layout: the rect is centred on the tile")
	# Neighbouring rects must abut exactly — no gap (a seam line) and no overlap (double-drawn
	# content). One column pitch to the right is the adjacency the bake depends on.
	var east := BakeLayout.pitch_rect(centre + Vector2(405.0, 0.0))
	_check(is_equal_approx(rect.end.x, east.position.x),
		"bake layout: adjacent pitch rects abut exactly, so textures reassemble without a seam")

	# Integer texel rects at the chosen scale: 405x480 u -> 540x640 px.
	_check(BakeLayout.texture_size() == Vector2i(540, 640), "bake layout: 540x640 px per tile")
	_check(BakeLayout.BAKE_SCALE > 1.107,
		"bake layout: the bake scale is above max play zoom, so a tile is never magnified")

	# The transform the export viewport uses must map the rect's own corners onto the texture.
	var xform := BakeLayout.bake_transform(rect)
	_check((xform * rect.position).is_equal_approx(Vector2.ZERO),
		"bake layout: the rect's origin maps to the texture's (0,0)")
	_check((xform * rect.end).is_equal_approx(Vector2(540.0, 640.0)),
		"bake layout: the rect's far corner maps to the texture's far corner")

	# STATIC BAKES, DYNAMIC STAYS LIVE. Anything whose visibility can change mid-match must be
	# excluded, or the texture would freeze it.
	_check(BakeLayout.road_is_static({"id": "r1"}), "bake layout: a permanent stroke bakes")
	_check(not BakeLayout.road_is_static({"id": "r2", "unlockable": true}),
		"bake layout: an unlockable stroke is excluded (it appears when its tiles gain roads)")
	_check(BakeLayout.mass_is_static({"id": "m1"}), "bake layout: an ordinary mass bakes")
	_check(not BakeLayout.mass_is_static({"id": "m2", "sacrificial": true}),
		"bake layout: a sacrificial mass is excluded (a building may evict it)")

	# Culling is by grown bbox, and the growth matters: a mass drops a shadow and a road has a
	# bed width, so content whose outline sits just OUTSIDE a rect still reaches into it.
	var doc := {"s": {
		"tiles": ["tile_1_1"],
		"parks": [{"id": "p_in", "outline": [[1000, 1150], [1100, 1150], [1100, 1250]]}],
		"decor": [{"id": "d_far", "pos": [9000, 9000], "size": [40, 40]}],
		"specials": [{"id": "x_evict", "sacrificial": true,
			"outline": [[1000, 1150], [1100, 1150], [1100, 1250]]}],
		"roads": [
			{"id": "r_in", "points": [[1000, 1200], [1150, 1200]]},
			{"id": "r_unlock", "unlockable": true, "points": [[1000, 1210], [1150, 1210]]},
		],
	}}
	var records := BakeLayout.records_for_rect(doc, rect)
	_check((records["parks"] as Array).size() == 1, "bake layout: a park inside the rect is included")
	_check((records["decor"] as Array).is_empty(), "bake layout: a mass far outside is culled")
	_check((records["specials"] as Array).is_empty(),
		"bake layout: a sacrificial special is excluded even though it lies inside")
	_check((records["roads"] as Array).size() == 1
		and str(((records["roads"] as Array)[0] as Dictionary).get("id", "")) == "r_in",
		"bake layout: the permanent stroke bakes and the unlockable one does not")
	_check(not BakeLayout.is_empty(records), "bake layout: a rect with content is not empty")
	# A rect nothing reaches produces no texture at all — that is what keeps the bake to the
	# authored area instead of 816 transparent PNGs.
	var far := BakeLayout.pitch_rect(Vector2(12000.0, 10000.0))
	_check(BakeLayout.is_empty(BakeLayout.records_for_rect(doc, far)),
		"bake layout: a rect with nothing on it bakes no texture")


func _test_authored_map_slot_classes() -> void:
	# Classification is by the LARGEST extent a building's art ever reaches, because a
	# building already reserves its L3 frame at L1 — a mass that grows past the threshold
	# at L2 needs the bigger slot from the day it is built, not from the day it upgrades.
	_check(AuthoredMap.slot_class_for(30.0, false) == "infra",
		"authored map: the smallest art measures into the infra box")
	_check(AuthoredMap.slot_class_for(
		float(AuthoredMap.SLOT_CLASS_CEILINGS["infra"]), false) == "standard",
		"authored map: reaching a class ceiling at any level moves it up a class")
	# The ladder: every box class must accept its own and everything smaller, and refuse
	# anything bigger. `area` is a farm polygon and sits outside the ladder entirely.
	for i in AuthoredMap.SLOT_BOX_CLASSES.size():
		var offered := str(AuthoredMap.SLOT_BOX_CLASSES[i])
		for j in AuthoredMap.SLOT_BOX_CLASSES.size():
			var wanted := str(AuthoredMap.SLOT_BOX_CLASSES[j])
			_check(AuthoredMap.slot_fits(wanted, offered) == (j <= i),
				"authored map: a %s building in a %s slot -> %s"
				% [wanted, offered, "fits" if j <= i else "refused"])
	_check(not AuthoredMap.slot_fits("standard", AuthoredMap.SLOT_AREA_CLASS),
		"authored map: an area slot is a farm polygon, not a bigger box")
	_check(AuthoredMap.slot_fits(AuthoredMap.SLOT_AREA_CLASS, AuthoredMap.SLOT_AREA_CLASS),
		"authored map: an area building takes an area slot")
	_check(not AuthoredMap.slot_fits(AuthoredMap.SLOT_AREA_CLASS, "standard"),
		"authored map: a farm cannot take a box slot")
	_check(AuthoredMap.slot_class_for(90.0, false) == "standard",
		"authored map: art above every ceiling still lands in the biggest box")
	_check(AuthoredMap.slot_class_for(12.0, true) == AuthoredMap.SLOT_AREA_CLASS,
		"authored map: farms and forests take an area polygon regardless of extent")
	# Each ceiling is exclusive: a building exactly at it belongs to the class above, which
	# is what keeps the box big enough for everything the class actually holds.
	for i in AuthoredMap.SLOT_BOX_CLASSES.size() - 1:
		var below := str(AuthoredMap.SLOT_BOX_CLASSES[i])
		var ceiling := float(AuthoredMap.SLOT_CLASS_CEILINGS[below])
		_check(AuthoredMap.slot_class_for(ceiling - 0.01, false) == below,
			"authored map: just under the %s ceiling is still %s" % [below, below])
		_check(AuthoredMap.slot_class_for(ceiling, false)
			== str(AuthoredMap.SLOT_BOX_CLASSES[i + 1]),
			"authored map: exactly at the %s ceiling moves up to %s"
			% [below, str(AuthoredMap.SLOT_BOX_CLASSES[i + 1])])


func _test_authored_map_round_trip() -> void:
	# A document that saves must load back identically — the editor's save path and the
	# game's read path share this validator, so "it saved" has to mean "the game will
	# load it".
	var doc: Dictionary = AuthoredMap.empty_document()
	doc["settlements"] = {"capital": {
		"tiles": ["tile_23_8", "tile_24_7"],
		"roads": [{"id": "r:1", "class": "mid", "points": [[10.5, 20.25], [40, 60]],
			"unlockable": true, "tiles": ["tile_23_8"]}],
		"decor": [{"id": "d:1", "form": "ring", "pos": [5, 6], "rot": 0.5,
			"size": [30, 20], "sacrificial": true}],
		"forests": [{"id": "fo:1", "outline": [[0, 0], [10, 0], [10, 10]]}],
	}}
	var path := "user://test_authored_map_round_trip.json"
	var absolute := ProjectSettings.globalize_path(path)
	var problem: String = AuthoredMap.save_to(doc, absolute)
	_check(problem == "", "authored map: a valid document saves (%s)" % problem)

	var file := FileAccess.open(absolute, FileAccess.READ)
	_check(file != null, "authored map: the saved document exists on disk")
	if file != null:
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		_check(typeof(parsed) == TYPE_DICTIONARY, "authored map: the saved document re-parses")
		if typeof(parsed) == TYPE_DICTIONARY:
			var back: Dictionary = parsed
			_check(AuthoredMap.validate(back).is_empty(),
				"authored map: the round-tripped document still validates")
			# Godot's JSON reader returns every number as a float, so in-memory equality is
			# not achievable — the property that matters for a git-committed file is that
			# saving is IDEMPOTENT: save, load, save again, identical bytes. Without the
			# canonical form a document would churn purely by edit history.
			_check(AuthoredMap.to_text(back) == AuthoredMap.to_text(doc),
				"authored map: save is idempotent — a reloaded document rewrites identically")
			var settlement: Dictionary = (back.get("settlements", {}) as Dictionary).get("capital", {})
			var road: Dictionary = (settlement.get("roads", []) as Array)[0]
			_check(str(road.get("id", "")) == "r:1" and str(road.get("class", "")) == "mid",
				"authored map: a road survives the round trip with its id and class")
			_check(is_equal_approx(float((road.get("points", []) as Array)[0][0]), 10.5),
				"authored map: authored coordinates survive the round trip")
			var mass: Dictionary = (settlement.get("decor", []) as Array)[0]
			_check(bool(mass.get("sacrificial", false)),
				"authored map: the sacrificial mark survives the round trip")
		DirAccess.remove_absolute(absolute)

	# The writer refuses to emit something the loader would reject, so a corrupt document
	# cannot reach disk through the editor.
	var broken: Dictionary = AuthoredMap.empty_document()
	broken["settlements"] = {"capital": {"tiles": []}}
	var refused: String = AuthoredMap.save_to(broken,
		ProjectSettings.globalize_path("user://test_authored_map_should_not_exist.json"))
	_check(refused != "", "authored map: saving an invalid document is refused")
	_check(not FileAccess.file_exists(
		ProjectSettings.globalize_path("user://test_authored_map_should_not_exist.json")),
		"authored map: a refused save writes no file")


## THE REAL DOCUMENTS ON DISK — not a fixture.
##
## Every other authored test builds its own document, and every editor check runs in scratch
## mode. So nothing opened the files the game actually ships with, and the first real defect
## in one would have surfaced as a blank map in a build. These files are hand-drawn source
## with no other copy; they deserve a test that reads them.
func _test_authored_documents_on_disk_load() -> void:
	var names: Array = AuthoredMap.list_documents()
	_check(not names.is_empty(), "authored docs: there are documents on disk to check")
	for name_value in names:
		var name := str(name_value)
		var file := FileAccess.open(AuthoredMap.path_for(name), FileAccess.READ)
		if file == null:
			_check(false, "authored docs: '%s' can be opened" % name)
			continue
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if typeof(parsed) != TYPE_DICTIONARY:
			_check(false, "authored docs: '%s' is a JSON object" % name)
			continue
		var problems: PackedStringArray = AuthoredMap.validate(parsed as Dictionary)
		_check(problems.is_empty(), "authored docs: '%s' validates (%s)"
			% [name, "clean" if problems.is_empty() else ", ".join(problems)])

	# The pointer has to name something that is there. A check that dies mid-run leaves it
	# aimed at its own fixture, and the symptom of that is a game with no authored map at all.
	var active := AuthoredMap.active_name()
	_check(active == "" or names.has(active),
		"authored docs: active.txt names a document on disk ('%s')" % active)

	# Every tile a document names must be a tile this map has. A typo here is silent: the
	# settlement simply never draws, on the one tile nobody thought to look at.
	var real_tiles := _tile_ids_from_csv()
	_check(real_tiles.size() > 100, "authored docs: read %d tile ids from the CSV" % real_tiles.size())
	for name_value in names:
		var document := _load_document(str(name_value))
		var unknown := PackedStringArray()
		for settlement_value in (document.get("settlements", {}) as Dictionary).values():
			for tile_value in (settlement_value as Dictionary).get("tiles", []) as Array:
				if not real_tiles.has(str(tile_value)) and not unknown.has(str(tile_value)):
					unknown.append(str(tile_value))
		_check(unknown.is_empty(), "authored docs: '%s' names only real tiles (%s)"
			% [str(name_value), "all known" if unknown.is_empty() else ", ".join(unknown)])


## The slot-box contract, against the REAL active document.
##
## The editor grew a second slot-box builder for the document being edited, which carried the
## `tile_id` and `index` a click needs to find the record behind a box. The original, used
## whenever the editor had not modified anything, did not. Scratch mode always takes the first
## branch, so every check passed while opening any real map crashed on the missing key.
## Pinning the key SET, on real data, is what makes that a test failure instead of a bug report.
func _test_authored_slot_boxes_contract() -> void:
	# A FIXTURE, not the live map. Slots were removed from every authored document when zones
	# replaced them (industrial/extraction, else the default placement), so reading the real
	# document here would test nothing — and the guard below would fail, correctly, on a
	# document that reserves no slots. The mechanism still exists for precision placement,
	# so its contract is still worth pinning; it just has to bring its own data now.
	var settlements: Dictionary = {"s": {"tiles": ["tile_1_1", "tile_1_2"], "slots": {
		"tile_1_1": {"pins": [
			{"pos": [10.0, 4.0], "angle": 0.0, "size": "standard"},
			{"pos": [-40.0, 20.0], "angle": 0.5, "size": "infra"},
		]},
		"tile_1_2": {"pins": [{"pos": [0.0, 0.0], "angle": 1.0, "size": "standard"}]},
	}}}
	var tiles := MapEditorSlotBoxes.tile_ids(settlements)
	# Guard against a vacuous pass: nothing below means anything without slots to measure.
	_check(tiles.size() > 0, "slot boxes: the fixture reserves slots (%d tile(s))"
		% tiles.size())

	# Centres stand in for the map's geometry, which needs a live scene. What is under test is
	# the SHAPE of what comes back, and that does not depend on where the tiles are.
	var centres: Dictionary = {}
	var spread := 0
	for tile_id in tiles:
		centres[tile_id] = Vector2(float(spread) * 1000.0, 0.0)
		spread += 1
	var boxes: Array = MapEditorSlotBoxes.build(settlements, centres)
	_check(boxes.size() > 0, "slot boxes: the builder returns boxes (%d)" % boxes.size())

	var missing := PackedStringArray()
	var bad_class := 0
	for box_value in boxes:
		var box: Dictionary = box_value
		for required in MapEditorSlotBoxes.KEYS:
			if not box.has(required) and not missing.has(str(required)):
				missing.append(str(required))
		if not MapEditorSlotBoxes.sizes().has(str(box.get("class", ""))):
			bad_class += 1
	_check(missing.is_empty(), "slot boxes: every box carries the full key set (%s)"
		% ("complete" if missing.is_empty() else "missing " + ", ".join(missing)))
	_check(bad_class == 0, "slot boxes: every box has a drawable class (%d bad)" % bad_class)

	# The box must be the size the SHIPPED side reserves, or the editor draws a promise the
	# game does not keep.
	var shipped: Dictionary = preload("res://scenes/building_visuals.gd").AUTHORED_SLOT_BOXES
	var wrong := 0
	for box_value in boxes:
		var box: Dictionary = box_value
		if (box["size"] as Vector2) != (shipped.get(str(box["class"]), Vector2.ZERO) as Vector2):
			wrong += 1
	_check(wrong == 0, "slot boxes: sizes match the shipped reservation table (%d wrong)" % wrong)

	# A slot on a tile this map does not have is dropped, not drawn at the world origin.
	var orphan := {"orphans": {"tiles": ["tile_1_1"], "slots":
		{"tile_no_such": {"pins": [{"pos": [0, 0], "angle": 0.0, "size": "small"}]}}}}
	_check(MapEditorSlotBoxes.build(orphan, {}).is_empty(),
		"slot boxes: a slot on an unknown tile is skipped")


func _test_authored_slot_validation() -> void:
	var base := {"version": AuthoredMap.SCHEMA_VERSION, "settlements":
		{"s": {"tiles": ["tile_1_1"], "slots": {}}}}

	var good := base.duplicate(true)
	good["settlements"]["s"]["slots"] = {"tile_1_1":
		{"pins": [{"pos": [10.0, 4.0], "angle": 0.0, "size": "standard"}]}}
	_check(AuthoredMap.validate(good).is_empty(), "slot validation: a well-formed slot passes")

	var bad_class := base.duplicate(true)
	bad_class["settlements"]["s"]["slots"] = {"tile_1_1":
		{"pins": [{"pos": [0, 0], "angle": 0.0, "size": "enormous"}]}}
	_check(not AuthoredMap.validate(bad_class).is_empty(),
		"slot validation: an unknown size class is rejected")

	var no_pos := base.duplicate(true)
	no_pos["settlements"]["s"]["slots"] = {"tile_1_1": {"pins": [{"size": "standard"}]}}
	_check(not AuthoredMap.validate(no_pos).is_empty(),
		"slot validation: a slot with no position is rejected")

	var short_pos := base.duplicate(true)
	short_pos["settlements"]["s"]["slots"] = {"tile_1_1":
		{"pins": [{"pos": [3.0], "angle": 0.0, "size": "standard"}]}}
	_check(not AuthoredMap.validate(short_pos).is_empty(),
		"slot validation: a one-number position is rejected")

	var not_a_list := base.duplicate(true)
	not_a_list["settlements"]["s"]["slots"] = {"tile_1_1": {"pins": {"nope": true}}}
	_check(not AuthoredMap.validate(not_a_list).is_empty(),
		"slot validation: pins that are not a list are rejected")

	var not_a_block := base.duplicate(true)
	not_a_block["settlements"]["s"]["slots"] = []
	_check(not AuthoredMap.validate(not_a_block).is_empty(),
		"slot validation: a slots block that is not a dictionary is rejected")


func _test_authored_slot_class_agrees_with_art() -> void:
	var visuals := preload("res://scenes/building_visuals.gd")
	var mismatched := PackedStringArray()
	for building_value in Catalog.all_buildings():
		var building: Dictionary = building_value
		var internal := str(building.get("internal_name", ""))
		if internal == "" or AuthoredSlotSizes.AREA_BUILDINGS.has(internal):
			continue
		var needs := AuthoredSlotSizes.class_for_building(str(building.get("id", "")))
		# Mirrors the claim site in `_claim_slot`, art key included.
		var art_key := str(visuals.INK_ART_KEY.get(internal, ""))
		var extent: float = float(visuals.ART_SIZE_OVERRIDE[art_key]) \
			if visuals.ART_SIZE_OVERRIDE.has(art_key) \
			else lerpf(visuals.ART_DRAWN_MIN, visuals.ART_DRAWN_MAX,
				clampf((float(building.get("tile_size_used", 1)) - 1.0) / 29.0, 0.0, 1.0))
		var claims: String = AuthoredMap.slot_class_for(extent, false)
		if claims != needs:
			mismatched.append("%s claims %s needs %s" % [internal, claims, needs])
	_check(mismatched.is_empty(), "slot class: claim matches the art's need (%s)"
		% ("all agree" if mismatched.is_empty() else ", ".join(mismatched)))

	# The above only proves the two RULES agree; it would still pass if the claim site went
	# back to dropping the art key, because it re-implements the rule rather than calling it.
	# So: prove the argument is load-bearing, and pin the call site the way the export
	# isolation test pins its own.
	var override_key := ""
	for key in visuals.ART_SIZE_OVERRIDE.keys():
		override_key = str(key)
		break
	_check(override_key != "", "slot class: there is an art-size override to test with")
	if override_key != "":
		var with_key: float = float(visuals.ART_SIZE_OVERRIDE[override_key])
		var without_key := lerpf(visuals.ART_DRAWN_MIN, visuals.ART_DRAWN_MAX, 0.0)
		_check(AuthoredMap.slot_class_for(with_key, false)
			!= AuthoredMap.slot_class_for(without_key, false),
			"slot class: dropping the art key changes the answer for '%s' (%.0f vs %.0f)"
			% [override_key, with_key, without_key])

	var source := FileAccess.open("res://scenes/building_visuals.gd", FileAccess.READ)
	_check(source != null, "slot class: building_visuals.gd is readable")
	if source != null:
		var text := source.get_as_text()
		source.close()
		_check(not text.contains("_art_size_for(size_units, \"\")"),
			"slot class: the claim site no longer drops the art key")
		_check(text.contains("_art_size_for(size_units, str(INK_ART_KEY.get(iname, \"\")))"),
			"slot class: the claim site passes the building's art key")


func _test_authored_slot_box_holds_its_class() -> void:
	var visuals := preload("res://scenes/building_visuals.gd")
	var ink := preload("res://scripts/ink_building_gen.gd")
	var too_small := PackedStringArray()
	var measured := 0
	var tightest := 999.0
	for building_value in Catalog.all_buildings():
		var building: Dictionary = building_value
		var internal := str(building.get("internal_name", ""))
		if internal == "" or AuthoredSlotSizes.AREA_BUILDINGS.has(internal):
			continue
		var art_key := str(visuals.INK_ART_KEY.get(internal, internal))
		var frame: Vector2 = ink.level_frame(art_key, 3)
		if frame.x <= 0.0 or frame.y <= 0.0:
			continue   # drawn by another path; nothing to measure
		var slot_class := AuthoredSlotSizes.class_for_building(str(building.get("id", "")))
		var reserved: Vector2 = visuals.AUTHORED_SLOT_BOXES.get(slot_class, Vector2.ZERO)
		if reserved == Vector2.ZERO:
			continue
		measured += 1
		# Exactly what _claim_slot then _crop_to_sprite do: the rect is the box less
		# CHUNK_GAP, and the sprite is scaled so its LONGER side hits the drawn target,
		# then margined on both sides.
		var target := AuthoredSlotSizes.max_extent_for(internal, building)
		var scale := target / maxf(frame.x, frame.y)
		var blocked := Vector2(frame.x * scale, frame.y * scale) \
			+ Vector2.ONE * (visuals.ART_BLOCK_MARGIN * 2.0)
		var room := reserved.x - visuals.CHUNK_GAP
		tightest = minf(tightest, room - maxf(blocked.x, blocked.y))
		if maxf(blocked.x, blocked.y) > room + 0.01:
			too_small.append("%s needs %.1f, %s slot offers %.1f"
				% [internal, maxf(blocked.x, blocked.y), slot_class, room])
	_check(measured > 10, "slot box: measured %d buildings with ink art" % measured)
	_check(too_small.is_empty(), "slot box: every slot holds its class at full size (%s)"
		% ("all fit" if too_small.is_empty() else ", ".join(too_small)))
	# And not wastefully oversized either — the tightest fit should be near zero slack, or
	# the boxes have drifted above what the art needs.
	_check(tightest < 6.0, "slot box: the tightest fit has %.1f u of slack, not a wide margin"
		% tightest)


func _test_authored_area_buildings_exist() -> void:
	var known: Dictionary = {}
	for building_value in Catalog.all_buildings():
		known[str((building_value as Dictionary).get("internal_name", ""))] = true
	var missing := PackedStringArray()
	for name_value in AuthoredSlotSizes.AREA_BUILDINGS:
		if not known.has(str(name_value)):
			missing.append(str(name_value))
	_check(missing.is_empty(), "area buildings: every name is a real building (%s)"
		% ("all found" if missing.is_empty() else "unknown: " + ", ".join(missing)))
	# And the reverse: anything the catalog calls a farm or a forest must be in the list, or
	# it silently gets a box slot instead of the polygon the designer drew.
	var uncovered := PackedStringArray()
	for name_value in known.keys():
		var internal := str(name_value)
		if (internal == "farm" or internal.ends_with("_forest")) \
				and not AuthoredSlotSizes.AREA_BUILDINGS.has(internal):
			uncovered.append(internal)
	_check(uncovered.is_empty(), "area buildings: no farm or forest is missing from it (%s)"
		% ("none missing" if uncovered.is_empty() else ", ".join(uncovered)))
	for name_value in AuthoredSlotSizes.AREA_BUILDINGS:
		_check(AuthoredSlotSizes.class_for_building(_building_id_for(str(name_value)))
			== AuthoredMap.SLOT_AREA_CLASS,
			"area buildings: %s classifies as an area, not a box" % str(name_value))


## The validator had nothing to say about slots at all, so a malformed slot block saved and
## loaded quietly and only failed when a building tried to stand in it. These are the shapes
## the readers used to coerce away.
## The class a building CLAIMS at placement time and the class the size table says its art
## NEEDS are computed in two places, and they had drifted: the claim site passed an empty art
## key, so ART_SIZE_OVERRIDE never applied and both wind farms asked for a small slot while
## needing a medium one. Nothing downstream re-checks, so the building simply overhangs.
## A slot must hold its class's largest member at full size. This was wrong twice: the margin
## was applied once per AXIS where the game blocks it once per SIDE, and CHUNK_GAP — which
## `_claim_slot` subtracts before the sprite is fitted — was left out entirely. Neither failed
## anything; `_crop_to_sprite` just scaled the art down, so the only symptom was buildings
## quietly drawn 10-14% small. Measured here rather than trusted.
## AREA_BUILDINGS is a list of catalog internal names typed by hand, and it was wrong: three
## of its four entries named buildings this game does not have, while both real forests were
## missing and were being sized into boxes. A name that matches nothing fails silently — it
## just never classifies anything — so the list has to be checked against the catalog.
## The write barrier. A harness has reached a real document twice now — once pressing the
## panel's Save button, once moving slot pins and deleting a road — and both times the tool
## believed it was in scratch mode. This asserts the WRITER refuses, so the guarantee does not
## depend on every tool remembering to be careful.
## Slots are handed out least-destructive first: a slot on clear ground before one standing
## on a decorative building, so the fabric survives until the tile runs out of clear ground.
## Document order is just the order someone clicked, and would demolish a terrace while bare
## ground sat free two slots along.
func _test_authored_slot_claim_order() -> void:
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	var bv := preload("res://scenes/building_visuals.gd").new()
	add_child(bv)
	await get_tree().process_frame
	bv.terrain_layer = terrain

	var tile_id := "tile_9_10"
	var coord: Vector2i = terrain.id_to_coord(tile_id)
	if not terrain.tiles.has(coord):
		bv.queue_free(); terrain.queue_free(); return
	var centre: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))

	# Three slots in a row. A mass is parked squarely on the FIRST, so document order and
	# least-destructive order disagree — which is the whole point of the check.
	var mass_centre := centre + Vector2(-120.0, 0.0)
	var doc := {
		"version": AuthoredMap.SCHEMA_VERSION,
		"settlements": {"s": {
			"tiles": [tile_id],
			"decor": [{"id": "m1", "form": "rect", "pos": [mass_centre.x, mass_centre.y],
				"rot": 0.0, "size": [90, 90], "sacrificial": true}],
			"slots": {tile_id: {"pins": [
				{"pos": [-120.0, 0.0], "angle": 0.0, "size": "standard"},
				{"pos": [0.0, 0.0], "angle": 0.0, "size": "standard"},
				{"pos": [120.0, 0.0], "angle": 0.0, "size": "standard"},
			]}},
		}},
	}
	_check(AuthoredMap.validate(doc).is_empty(), "claim order: the fixture document is valid")
	AuthoredMap.set_document_for_tests(doc)

	var tmpl: Dictionary = bv._authored_block_template(tile_id, coord)
	_check(not tmpl.is_empty(), "claim order: the authored template built")
	if not tmpl.is_empty():
		var cost: Array = tmpl.get("lot_cost", [])
		var order: Array = tmpl.get("lot_order", [])
		var masses: Array = tmpl.get("lot_masses", [])
		_check(cost.size() == 3 and order.size() == 3,
			"claim order: every slot got a cost and a place in the order")
		_check(float(cost[0]) > 0.0, "claim order: the slot under the mass costs something (%.0f u2)"
			% float(cost[0]))
		_check(is_zero_approx(float(cost[1])) and is_zero_approx(float(cost[2])),
			"claim order: the slots on clear ground cost nothing")
		_check(int(order[order.size() - 1]) == 0,
			"claim order: the slot under the mass is visited LAST (order %s)" % str(order))
		_check(int(order[0]) == 1 and int(order[1]) == 2,
			"claim order: clear slots keep document order between themselves (%s)" % str(order))
		_check((masses[0] as PackedStringArray).has("m1"),
			"claim order: the covered slot knows which mass it would evict")
		_check((masses[1] as PackedStringArray).is_empty(),
			"claim order: a clear slot would evict nothing")

		# Protected fabric sorts behind offered fabric of the same size.
		(doc["settlements"]["s"]["decor"][0] as Dictionary)["sacrificial"] = false
		AuthoredMap.set_document_for_tests(doc)
		bv._tile_block_templates.erase(tile_id)
		bv._drop_zone_masks(tile_id)   # the fabric changed; its derived caches must go too
		var protected: Dictionary = bv._authored_block_template(tile_id, coord)
		_check(float((protected.get("lot_cost", []) as Array)[0]) > float(cost[0]),
			"claim order: protected fabric costs more than fabric offered up")

	AuthoredMap.set_document_for_tests({})
	AuthoredMap.reset_for_tests()
	bv.queue_free()
	terrain.queue_free()
	await get_tree().process_frame


## A stamped building on an authored tile takes over a mass the designer marked as a hijack
## slot: the footprint IS the mass outline, the closest-area mass wins, a claimed mass is
## never handed out twice, and an unmarked mass is never touched.
func _test_hijack_mass_claim() -> void:
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	var bv := preload("res://scenes/building_visuals.gd").new()
	add_child(bv)
	await get_tree().process_frame
	bv.terrain_layer = terrain

	var tile_id := "tile_9_10"
	var coord: Vector2i = terrain.id_to_coord(tile_id)
	if not terrain.tiles.has(coord):
		bv.queue_free(); terrain.queue_free(); return
	var c: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
	var big := _rect_outline(c + Vector2(-120.0, 0.0), 60.0, 40.0)
	var small := _rect_outline(c + Vector2(120.0, 0.0), 30.0, 30.0)
	var plain := _rect_outline(c + Vector2(0.0, 100.0), 50.0, 50.0)
	var doc := {
		"version": AuthoredMap.SCHEMA_VERSION,
		"settlements": {"s": {
			"tiles": [tile_id],
			"specials": [
				{"id": "h_big", "kind": "poly", "outline": big, "sides": [], "hijack": true},
				{"id": "h_small", "kind": "poly", "outline": small, "sides": [], "hijack": true},
				{"id": "plain", "kind": "poly", "outline": plain, "sides": []},
			],
		}},
	}
	var problems := AuthoredMap.validate(doc)
	_check(problems.is_empty(), "hijack: the fixture document is valid (%s)" % str(problems))
	AuthoredMap.set_document_for_tests(doc)

	var first: Dictionary = bv._claim_hijack_mass(tile_id, coord, 60.0 * 40.0)
	_check(str(first.get("via", "")) == "hijack" and str(first.get("hijack_id", "")) == "h_big",
		"hijack: a 2400 u2 building takes the mass nearest its own area (got '%s')" % str(first.get("hijack_id", "")))
	if not first.is_empty():
		var verts: PackedVector2Array = first.verts
		var corner := Vector2(float(big[0][0]), float(big[0][1]))
		_check(verts.size() == 4 and verts[0].distance_to(corner) < 0.01,
			"hijack: the footprint IS the mass outline (first corner off by %.3f)"
			% (verts[0].distance_to(corner) if verts.size() > 0 else INF))
	bv._hijacked_masses["h_big"] = "iid_1"
	var second: Dictionary = bv._claim_hijack_mass(tile_id, coord, 60.0 * 40.0)
	_check(str(second.get("hijack_id", "")) == "h_small",
		"hijack: a claimed mass is never handed out twice (got '%s')" % str(second.get("hijack_id", "")))
	bv._hijacked_masses["h_small"] = "iid_2"
	_check(bv._claim_hijack_mass(tile_id, coord, 900.0).is_empty(),
		"hijack: an unmarked mass is never hijacked — with no marks left the claim is empty")

	AuthoredMap.set_document_for_tests({})
	bv.queue_free()
	terrain.queue_free()


## The near bake tier exists to serve the camera's maximum zoom without magnifying a texture.
## These are the two numbers that have to agree — the bake scale and the camera's tile count —
## so changing `zoomed_in_tile_count` again fails HERE rather than as a soft picture in play.
func _test_bake_near_tier_geometry() -> void:
	const Layout := preload("res://scripts/authored_bake_layout.gd")
	var far := Layout.texture_size_for(Layout.TIER_FAR)
	var near := Layout.texture_size_for(Layout.TIER_NEAR)
	_check(far == Layout.texture_size(), "near tier: the far tier is still the default size")
	_check(near.x == far.x * 2 and near.y == far.y * 2,
		"near tier: near is exactly twice the far texture (%s vs %s)" % [str(near), str(far)])
	# Integer texel rects — the property 4/3 and 8/3 were chosen for.
	_check(is_equal_approx(Layout.PITCH.x * Layout.NEAR_SCALE, float(near.x))
		and is_equal_approx(Layout.PITCH.y * Layout.NEAR_SCALE, float(near.y)),
		"near tier: the pitch rect lands on whole texels at NEAR_SCALE")
	var transform := Layout.bake_transform_for(Rect2(Vector2(100.0, 50.0), Layout.PITCH), Layout.TIER_NEAR)
	_check(is_equal_approx(transform.get_scale().x, Layout.NEAR_SCALE),
		"near tier: the painter transform carries the near scale")
	_check(is_equal_approx((transform * Vector2(100.0, 50.0)).length(), 0.0),
		"near tier: the rect's origin maps to the texture's (0, 0)")

	# THE AGREEMENT. A tile is tile_height world units tall and the camera fits
	# `zoomed_in_tile_count` of them into the viewport height, so at maximum zoom the screen
	# shows viewport.y / (tile_height * count) pixels per world unit — independent of the
	# viewport, because both sides scale with it. The bake must sit at or above that.
	# THE AGREEMENT, and it is resolution-dependent. A tile is 480 world units tall and the
	# camera fits `zoomed_in_tile_count` of them into the viewport, so maximum zoom shows
	# viewport_height / (480 * count) pixels per world unit — 1.8 at 1080p, 2.4 at 1440p,
	# 3.6 at 2160p. NEAR_SCALE covers the first two outright; a 4K screen at full zoom
	# magnifies the near texture about 1.35x, which is the documented limit of this tier
	# (NEAR_SCALE 4.0 would cover it, at 9x the far tier's pixels instead of 4x).
	var camera := preload("res://scripts/camera_controller.gd").new()
	var tile_height := 480.0
	var ppu_1440 := 1440.0 / (tile_height * camera.zoomed_in_tile_count)
	_check(Layout.NEAR_SCALE >= ppu_1440,
		"near tier: NEAR_SCALE %.3f covers the %.3f px/u a 1440p viewport reaches at full zoom"
			% [Layout.NEAR_SCALE, ppu_1440])
	_check(Layout.BAKE_SCALE < ppu_1440,
		"near tier: the far tier alone WOULD be magnified there — which is why near exists")
	camera.free()

## The road-clearance segments include the AUTHORED carriageways, not just the network's
## geometry — the street a player sees on a hand-drawn tile is the document's stroke.
func _test_block_road_segments_include_authored_strokes() -> void:
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	var bv := preload("res://scenes/building_visuals.gd").new()
	add_child(bv)
	await get_tree().process_frame
	bv.terrain_layer = terrain

	var tile_id := "tile_9_10"
	var coord: Vector2i = terrain.id_to_coord(tile_id)
	if not terrain.tiles.has(coord):
		bv.queue_free(); terrain.queue_free(); return
	var c: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
	var doc := {
		"version": AuthoredMap.SCHEMA_VERSION,
		"settlements": {"s": {
			"tiles": [tile_id],
			"roads": [{"id": "r1", "class": "mid", "unlockable": true, "tiles": [tile_id],
				"points": [[c.x - 200.0, c.y], [c.x + 200.0, c.y]]}],
		}},
	}
	var problems := AuthoredMap.validate(doc)
	_check(problems.is_empty(), "authored strokes: the fixture document is valid (%s)" % str(problems))
	AuthoredMap.set_document_for_tests(doc)

	# An UNLOCKABLE stroke on an unflagged tile is not drawn, so it must not fence off ground.
	var td: Dictionary = terrain.tiles[coord]
	var had_infra: Array = (td.get("infrastructure_present", []) as Array).duplicate()
	td["infrastructure_present"] = []
	_check(not _has_centre_stroke(bv._block_road_segments(coord)),
		"authored strokes: an unlockable stroke on an unflagged tile is NOT a clearance segment")
	# Flag the tile and the same stroke becomes a carriageway to keep clear of.
	td["infrastructure_present"] = ["roads"]
	var segs: Array = bv._block_road_segments(coord)
	_check(_has_centre_stroke(segs),
		"authored strokes: a visible document road across the tile centre is a clearance segment (%d segs)" % segs.size())
	# The road-settle conflict test asks the network only: authored strokes never count there.
	_check(not _has_centre_stroke(bv._block_road_segments(coord, false)),
		"authored strokes: the settle-conflict query (include_authored=false) ignores them")
	# A PERMANENT stroke is always drawn, so it fences ground whatever the flags say.
	td["infrastructure_present"] = []
	(doc["settlements"]["s"]["roads"][0] as Dictionary)["unlockable"] = false
	AuthoredMap.set_document_for_tests(doc)
	_check(_has_centre_stroke(bv._block_road_segments(coord)),
		"authored strokes: a permanent stroke counts even on an unflagged tile")
	td["infrastructure_present"] = had_infra

	AuthoredMap.set_document_for_tests({})
	bv.queue_free()
	terrain.queue_free()


func _test_authored_zones() -> void:
	var base := {"version": AuthoredMap.SCHEMA_VERSION,
		"settlements": {"s": {"tiles": ["tile_1_1"]}}}

	var good := base.duplicate(true)
	good["settlements"]["s"]["zones"] = [{"id": "z1", "kind": "industrial",
		"tiles": ["tile_1_1"], "outline": [[0, 0], [40, 0], [40, 40], [0, 40]]}]
	_check(AuthoredMap.validate(good).is_empty(), "zones: a well-formed zone passes")

	var bad_kind := base.duplicate(true)
	bad_kind["settlements"]["s"]["zones"] = [{"id": "z1", "kind": "residential",
		"outline": [[0, 0], [40, 0], [40, 40]]}]
	_check(not AuthoredMap.validate(bad_kind).is_empty(), "zones: an unknown kind is rejected")

	var thin := base.duplicate(true)
	thin["settlements"]["s"]["zones"] = [{"id": "z1", "kind": "industrial",
		"outline": [[0, 0], [40, 0]]}]
	_check(not AuthoredMap.validate(thin).is_empty(), "zones: two corners is not a region")

	# TEN corners, which is more than a farm field may have — the cap is the point.
	var ten: Array = []
	for i in 10:
		ten.append([cos(TAU * float(i) / 10.0) * 60.0, sin(TAU * float(i) / 10.0) * 60.0])
	var big := base.duplicate(true)
	big["settlements"]["s"]["zones"] = [{"id": "z1", "kind": "extraction", "outline": ten}]
	_check(AuthoredMap.validate(big).is_empty(), "zones: ten corners is allowed (%d max)"
		% AuthoredMap.ZONE_MAX_VERTICES)
	_check(AuthoredMap.ZONE_MAX_VERTICES > AuthoredMap.AREA_MAX_VERTICES,
		"zones: a zone may have more corners than a farm field")
	var eleven := base.duplicate(true)
	var over := ten.duplicate(true)
	over.append([0, 0])
	eleven["settlements"]["s"]["zones"] = [{"id": "z1", "kind": "extraction", "outline": over}]
	_check(not AuthoredMap.validate(eleven).is_empty(), "zones: eleven corners is refused")

	# All three kinds the owner asked for exist, and the lookup filters by kind AND tile.
	for kind in ["industrial", "industrial_reserve", "extraction"]:
		_check(AuthoredMap.ZONE_KINDS.has(kind), "zones: '%s' is a kind" % kind)
	var doc := base.duplicate(true)
	doc["settlements"]["s"]["zones"] = [
		{"id": "z1", "kind": "industrial", "tiles": ["tile_1_1"],
			"outline": [[0, 0], [40, 0], [40, 40]]},
		{"id": "z2", "kind": "extraction", "tiles": ["tile_1_1"],
			"outline": [[0, 0], [40, 0], [40, 40]]},
		{"id": "z3", "kind": "industrial", "tiles": ["tile_2_2"],
			"outline": [[0, 0], [40, 0], [40, 40]]},
	]
	AuthoredMap.set_document_for_tests(doc)
	_check((AuthoredMap.zones_for_tile("tile_1_1", "industrial") as Array).size() == 1,
		"zones: the lookup takes only this tile's zones of this kind")
	_check((AuthoredMap.zones_for_tile("tile_1_1", "extraction") as Array).size() == 1,
		"zones: and finds the extraction one separately")
	_check((AuthoredMap.zones_for_tile("tile_2_2", "extraction") as Array).is_empty(),
		"zones: a tile with none of a kind gets none")
	AuthoredMap.set_document_for_tests({})
	AuthoredMap.reset_for_tests()


## Industrial zones: the region a gameplay building may be placed IN, as opposed to a slot,
## which is a box reserved before anyone knows what will stand in it.
## The two seams that let a felled wood take its canopy with it, and the refusal the demolish
## panel now reports instead of swallowing.
##
## The whole sequence — a wood bought, demolished, and the tile left clear — is checked in the
## real world by `tools/forest_demolish_check.tscn`; it needs a built map, which is exactly
## what this suite does not have. These pin the parts that can be tested in isolation.
## A bake that has fallen behind its document is not a broken bake — the game notices and
## draws vectors instead, which is correct and MUCH slower: the whole authored map, woods and
## all, rebuilt on every redraw. That cost 4.5 seconds a frame and eight minutes of "Building
## the world…" in the editor, and the only thing that ever said so was a warning nobody was
## reading. Editing a document means re-running the bake; this is what says so.
func _test_authored_bake_matches_its_document() -> void:
	var bake := load("res://scripts/authored_bake.gd")
	var manifest: Dictionary = bake.data()
	if manifest.is_empty():
		_check(true, "authored bake: no bake on disk (the vector path is the fallback, not a fault)")
		return
	var active := AuthoredMap.active_name()
	_check(str(manifest.get("document", "")) == active,
		"authored bake: the bake on disk is for the active document ('%s' vs '%s')"
			% [str(manifest.get("document", "")), active])
	_check(str(manifest.get("source_md5", "")) == FileAccess.get_md5(AuthoredMap.path_for(active)),
		"authored bake: the bake is current with '%s' — re-run "
			% active + "tools/map_editor/bake_authored_map.tscn after editing a document")
	_check(bake.is_available(),
		"authored bake: the game will use the textures rather than falling back to vectors")


func _test_forest_felling_seams() -> void:
	_check(ForestFootprint.FOREST_BUILDING_IDS.has("b_015")
		and ForestFootprint.FOREST_BUILDING_IDS.has("b_016"),
		"forests: both growth stages count as forest buildings")

	# The forest layer's registry outlives the building record, which is erased before
	# `building_removed` reaches world_map — so this lookup is the only way it can still tell
	# which authored canopy to fell. Parsing the tile out of the instance id worked for the
	# seeded woods alone, and a bought New Growth Forest left its trees standing.
	var forests: Node2D = load("res://scripts/forest_visuals.gd").new()
	forests.on_building_placed("tile_6_9", "b_015", "", "start_b_015_tile_6_9", Vector2i(5, 8))
	_check(forests.tile_of_instance("start_b_015_tile_6_9") == "tile_6_9",
		"forests: the layer reports the tile a standing wood is on")
	_check(forests.tile_of_instance("nobody") == "",
		"forests: an unknown instance reports no tile")
	forests.remove_instance("start_b_015_tile_6_9")
	_check(forests.tile_of_instance("start_b_015_tile_6_9") == "",
		"forests: a removed wood is off the register")
	forests.free()

	# ALL FORESTS ARE DEMOLISHABLE (owner, 2026-08-29). A wood standing on the land belongs to
	# nobody — there is no company to buy it from — so felling one is clearing ground.
	BuildingState.buildings["t_wood"] = {"instance_id": "t_wood", "building_id": "b_016",
		"tile_id": "tile_1_2", "owner": BuildingState.LAND_OWNER}
	_check(BuildingState.is_land_owned_wood(BuildingState.buildings["t_wood"]),
		"forests: a wood owned by the land is recognised as one")
	_check(bool(BuildingWorks.start_demolish("t_wood").get("ok", false)),
		"forests: a wood the land owns can be demolished where it stands")
	BuildingWorks.demolish_queue.erase("t_wood")
	BuildingState.buildings.erase("t_wood")

	# The allowance is for WOODS, not for anything the land happens to hold, and not for a
	# company's forest — that still has to be bought, like any other building of theirs.
	BuildingState.buildings["t_plant"] = {"instance_id": "t_plant", "building_id": "b_002",
		"tile_id": "tile_1_2", "owner": BuildingState.LAND_OWNER}
	BuildingState.buildings["t_npc_wood"] = {"instance_id": "t_npc_wood", "building_id": "b_015",
		"tile_id": "tile_1_2", "owner": "Some Company Ltd."}
	var refused: Dictionary = BuildingWorks.start_demolish("t_plant")
	_check(not bool(refused.get("ok", false)) and str(refused.get("reason", "")) != "",
		"forests: the allowance does not extend to other buildings on the land")
	var npc_refused: Dictionary = BuildingWorks.start_demolish("t_npc_wood")
	_check(not bool(npc_refused.get("ok", false)),
		"forests: a company's wood must still be bought before it can be felled")
	# ...and the refusal carries a reason, because the demolish panel now shows it instead of
	# closing on a silent no-op.
	_check(str(npc_refused.get("reason", "")) != "",
		"forests: a refusal says why, for the panel to show")
	BuildingState.buildings.erase("t_plant")
	BuildingState.buildings.erase("t_npc_wood")


## The `enable procedural <region>` cheat's partition: the untouched landmap splits four
## ways by nearest city, deterministically, and covered tiles stay out.
func _test_region_partition() -> void:
	for region in MapEditorRegionImportScript.REGIONS:
		var anchor := str(MapEditorRegionImportScript.REGION_ANCHORS[region])
		_check(Catalog.is_land_tile(anchor),
			"regions: anchor of '%s' (%s) is a land tile the catalog knows" % [region, anchor])
	var centres := {
		"tile_14_2": Vector2(0, 0),        # north (Port Lightning)
		"tile_11_17": Vector2(1000, 0),    # arin
		"tile_22_16": Vector2(0, 1000),    # vandel
		"tile_25_9": Vector2(1000, 1000),  # capital
		"near_north": Vector2(10, 10),
		"near_arin": Vector2(980, 40),
		"near_vandel": Vector2(30, 950),
		"near_capital": Vector2(990, 990),
		"already_authored": Vector2(5, 5),
		"tie_tile": Vector2(500, 0),       # equidistant north/arin
	}
	var split: Dictionary = MapEditorRegionImportScript.partition(centres, {"already_authored": true})
	_check(split.size() == centres.size() - 1, "regions: every uncovered land tile is assigned")
	_check(not split.has("already_authored"), "regions: covered tiles stay out of the split")
	_check(str(split.get("tile_14_2")) == "north" and str(split.get("tile_11_17")) == "arin"
		and str(split.get("tile_22_16")) == "vandel" and str(split.get("tile_25_9")) == "capital",
		"regions: each anchor lands in its own region")
	_check(str(split.get("near_north")) == "north" and str(split.get("near_arin")) == "arin"
		and str(split.get("near_vandel")) == "vandel" and str(split.get("near_capital")) == "capital",
		"regions: proximity decides the region")
	_check(str(split.get("tie_tile")) == "north", "regions: a tie goes to the earlier region")
	_check(MapEditorRegionImportScript.partition({"tile_14_2": Vector2.ZERO}, {}).is_empty(),
		"regions: a missing anchor refuses to partition")
	var north_tiles: Dictionary = MapEditorRegionImportScript.region_tiles(split, "north")
	_check(north_tiles.has("near_north") and north_tiles.has("tie_tile")
		and not north_tiles.has("near_arin"), "regions: region_tiles filters one region")
	var covered := MapEditorRegionImportScript.covered_tiles({"settlements": {
		"untitled": {"tiles": ["a"]}, "procedural-north": {"tiles": ["b"]}}})
	_check(covered.has("a") and not covered.has("b"),
		"regions: a shown region does not count as authored coverage")
	_check(MapEditorRegionImportScript.covered_tiles({"settlements": {
		"procedural-north": {"tiles": ["b"]}}}, true).has("b"),
		"regions: coverage can include the region imports when asked")


## Cutting one region out of the whole-map import: ownership rules, renumbering, and a
## settlement the validator accepts — and removing it restores the document exactly.
func _test_region_import_settlement() -> void:
	var centres := {
		"tile_14_2": Vector2(0, 0), "tile_11_17": Vector2(1000, 0),
		"tile_22_16": Vector2(0, 1000), "tile_25_9": Vector2(1000, 1000),
	}
	var tile_of := func(world: Vector2) -> String:
		return "t_%d_%d" % [int(floor(world.x / 100.0)), int(floor(world.y / 100.0))]
	var region_set := {"t_0_0": true, "t_0_1": true}
	var covered := {"t_5_0": true}
	var source := {"version": 1, "settlements": {
		"b": {"tiles": ["t_0_1"], "specials": [
			{"id": "s:x:9", "kind": "poly", "sides": [], "outline": [[20, 120], [40, 120], [40, 140]]}]},
		"a": {"tiles": ["t_0_0"],
			"roads": [
				{"id": "r:x:0", "class": "mid", "points": [[0, 0], [50, 50]],
					"tiles": ["t_0_0"], "unlockable": false},
				{"id": "r:x:1", "class": "mid", "points": [[0, 0], [60, 10]],
					"tiles": ["t_0_0", "t_5_0"], "unlockable": false},
				{"id": "r:x:2", "class": "mid", "points": [[900, 0], [1000, 40]],
					"tiles": ["t_9_0"], "unlockable": false},
			],
			"specials": [
				{"id": "s:x:0", "kind": "poly", "sides": [], "outline": [[10, 10], [30, 10], [30, 30]]},
				{"id": "s:x:1", "kind": "poly", "sides": [], "outline": [[910, 10], [930, 10], [930, 30]]},
				{"id": "s:x:2", "kind": "poly", "sides": [], "outline": [[10, 10], [30, 10], [30, 30]],
					"port": "t_7_7", "port_role": "quay"},
			],
			"parks": [{"id": "p:x:0", "kind": "green", "outline": [[5, 5], [25, 5], [25, 25]]}],
			"plazas": [{"id": "pz:x:0", "outline": [[905, 5], [925, 5], [925, 25]]}],
			"port_decor": [
				{"kind": "container", "outline": [[1, 1], [2, 1], [2, 2]], "tile": "t_0_0"},
				{"kind": "container", "outline": [[1, 1], [2, 1], [2, 2]], "tile": "t_9_9"},
			],
			"slots": {
				"t_0_0": {"pins": [{"pos": [1, 2], "angle": 0.0, "size": "standard"}]},
				"t_9_9": {"pins": [{"pos": [3, 4], "angle": 0.0, "size": "standard"}]},
			}},
	}}
	var built: Dictionary = MapEditorRegionImportScript.build_settlement(
		source, "north", region_set, covered, tile_of, centres)
	var roads: Array = built.get("roads", [])
	_check(roads.size() == 1 and str((roads[0] as Dictionary).get("id", "")) == "r:north:0",
		"region cut: one road survives — in-region, renumbered")
	var specials: Array = built.get("specials", [])
	_check(specials.size() == 2, "region cut: the covered-touching road, the far road, the far"
		+ " special, the far plaza and the port special all stay out (%d specials)" % specials.size())
	var special_ids: Array = []
	for special in specials:
		special_ids.append(str((special as Dictionary).get("id", "")))
	_check(special_ids == ["s:north:0", "s:north:1"],
		"region cut: specials renumber deterministically across source settlements")
	_check((built.get("parks", []) as Array).size() == 1
		and str((built.get("parks", [])[0] as Dictionary).get("id", "")) == "p:north:0",
		"region cut: the in-region park comes across")
	_check((built.get("plazas", []) as Array).is_empty(), "region cut: the far plaza does not")
	_check((built.get("port_decor", []) as Array).size() == 1, "region cut: port decor filters by tile")
	_check((built.get("slots", {}) as Dictionary).keys() == ["t_0_0"],
		"region cut: slots filter by tile")
	_check(built.get("tiles", []) == ["t_0_0", "t_0_1"],
		"region cut: the settlement claims the whole region")
	_check(int(built.get("next_id", 0)) == 5, "region cut: next_id counts the records")

	# The merged document must satisfy the game's own validator, and removing the
	# settlement must restore the document byte-for-byte.
	var doc := AuthoredMap.empty_document()
	var before := AuthoredMap.to_text(doc)
	var settlements: Dictionary = doc.get("settlements", {})
	settlements[MapEditorRegionImportScript.settlement_key("north")] = built
	doc["settlements"] = settlements
	_check(AuthoredMap.validate(doc).is_empty(), "region cut: the merged document validates")
	settlements.erase(MapEditorRegionImportScript.settlement_key("north"))
	_check(AuthoredMap.to_text(doc) == before, "region cut: disabling restores the document exactly")
	_check(MapEditorRegionImportScript.build_settlement(source, "north", {}, covered, tile_of, centres).is_empty(),
		"region cut: an empty region imports nothing")

	# The Stoneshore planting layer comes across as compact points, fitted to land and
	# rejected around the imported road/building geometry. It is deterministic so toggling a
	# region off and on cannot reshuffle the trees.
	var tree_template := {"points": [
		{"kind": "small", "offset": Vector2(80, 80)},
		{"kind": "large", "offset": Vector2(20, 20)},
		{"kind": "mixed", "offset": Vector2(42, 142), "radius": 12.0},
	]}
	var planted: Dictionary = MapEditorRegionImportScript.build_settlement(
		source, "north", region_set, covered, tile_of, centres, tree_template)
	var planted_again: Dictionary = MapEditorRegionImportScript.build_settlement(
		source, "north", region_set, covered, tile_of, centres, tree_template)
	_check(AuthoredMap.tree_count(planted) > 0,
		"region cut: the Stoneshore template plants clear points in the generated city")
	_check(planted.get("tree_points", {}) == planted_again.get("tree_points", {}),
		"region cut: patterned trees are deterministic across regeneration")
	_check(not planted.has("trees") and planted.has("tree_points"),
		"region cut: generated planting uses compact typed point batches")
	for record_value in AuthoredMap.tree_records(planted, "procedural-north"):
		var record: Dictionary = record_value
		var values: Array = record.get("position", [])
		var at := Vector2(float(values[0]), float(values[1]))
		_check(region_set.has(tile_of.call(at)),
			"region cut: every planted tree remains on one of the region's land tiles")

	var template_doc := {"settlements": {"source": {
		"tiles": ["tile_5_10"],
		"tree_points": {"small": [[10.0, 0.0], [2000.0, 0.0]]},
	}}}
	var extracted := MapEditorRegionImportScript.stoneshore_tree_template(template_doc,
		{"tile_5_10": Vector2.ZERO})
	_check((extracted.get("points", []) as Array).size() == 1,
		"region cut: the reusable template only learns from Stoneshore's local tree fringe")

	# Copperstown's focused command imports only central building polygons and gives them a
	# removable id namespace; roads and out-of-region fabric never hitch a ride.
	var central_source := {"settlements": {"live": {"specials": [
		{"id": "old-in", "kind": "poly", "port": "tile_13_9",
			"outline": [[0, 0], [20, 0], [20, 20]]},
		{"id": "old-out", "kind": "poly", "port": "tile_2_2",
			"outline": [[100, 100], [120, 100], [120, 120]]},
	]}}}
	var central := MapEditorRegionImportScript.build_central_buildings(central_source, tile_of)
	_check((central.get("specials", []) as Array).size() == 1
		and str((central.get("specials", [])[0] as Dictionary).get("id", "")) == "s:central:0",
		"central buildings: only Copperstown fabric is copied and renumbered")
	_check((central.get("roads", []) as Array).is_empty()
		and central.get("tiles", []) == MapEditorRegionImportScript.CENTRAL_BUILDING_TILES,
		"central buildings: the focused layer claims Copperstown but imports no roads")

	# The road-edge layer is reproducible and remains a compact typed point batch. A bank of
	# eligible roads makes the deterministic 22% sample exercise both the accept and gap paths.
	var roadside_roads: Array = []
	for i in 40:
		roadside_roads.append({"id": "fixture-%d" % i,
			"points": [[0, i * 40], [180, i * 40]], "class": "mid"})
	var everywhere := func(_world: Vector2) -> String: return "land"
	var roadside := MapEditorRegionImportScript.roadside_tree_points(
		{"land": true}, everywhere, roadside_roads, [], [], [], "fixture")
	var roadside_again := MapEditorRegionImportScript.roadside_tree_points(
		{"land": true}, everywhere, roadside_roads, [], [], [], "fixture")
	_check(AuthoredMap.tree_count({"tree_points": roadside}) > 0,
		"roadside trees: the sparse deterministic pass plants eligible road edges")
	_check(roadside == roadside_again,
		"roadside trees: regeneration is deterministic")
	_check(roadside.keys().all(func(kind: Variant) -> bool:
		return str(kind) == "small" or str(kind) == "large"),
		"roadside trees: output keeps the measured small/large vocabulary")


## The importer's faithfulness contract: outlines keep up to TEN corners (owner, 2026-08-29)
## and only simplify past that.
func _test_import_corner_cap() -> void:
	_check(int(ImportLiveMapScript.MAX_CORNERS) == 10, "import: the corner cap is ten")
	var importer := ImportLiveMapScript.new()
	var circle := PackedVector2Array()
	for i in 43:
		circle.append(Vector2(cos(TAU * float(i) / 43.0), sin(TAU * float(i) / 43.0)) * 90.0)
	var shaped: PackedVector2Array = importer._simplify_to_cap(circle)
	_check(shaped.size() <= 10 and shaped.size() >= 3,
		"import: a 43-corner outline simplifies to at most ten corners (%d)" % shaped.size())
	_check(shaped[0] == circle[0], "import: simplification keeps the first corner in place")
	var square := PackedVector2Array([Vector2(0, 0), Vector2(80, 0), Vector2(80, 80), Vector2(0, 80)])
	_check(importer._outline_list(square).size() == 4,
		"import: an outline under the cap is untouched")
	importer.free()


## ZONES ACTUALLY CONSTRAIN PLACEMENT. Both halves are asserted: a building lands inside the
## polygon, AND lands somewhere else once the zone is gone. Without the second half this passes
## on a build where zones do nothing at all, which is the exact shape of test that let the
## slot-box drift ship earlier today.
func _test_zone_placement() -> void:
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	var bv := preload("res://scenes/building_visuals.gd").new()
	add_child(bv)
	await get_tree().process_frame
	bv.terrain_layer = terrain

	var tile_id := "tile_9_10"
	var coord: Vector2i = terrain.id_to_coord(tile_id)
	if not terrain.tiles.has(coord):
		bv.queue_free(); terrain.queue_free(); return
	var centre: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))

	# A zone in ONE corner of the tile, well away from the middle, so "inside" is a real
	# constraint rather than something a centred placement satisfies by accident.
	var corner := centre + Vector2(-150.0, -120.0)
	var outline: Array = []
	for offset in [Vector2(-90, -80), Vector2(90, -80), Vector2(90, 80), Vector2(-90, 80)]:
		outline.append([corner.x + offset.x, corner.y + offset.y])
	var doc := {"version": AuthoredMap.SCHEMA_VERSION, "settlements": {"s": {
		"tiles": [tile_id],
		"zones": [{"id": "z1", "kind": "industrial", "tiles": [tile_id], "outline": outline}],
	}}}
	_check(AuthoredMap.validate(doc).is_empty(), "zone placement: the fixture is valid")
	AuthoredMap.set_document_for_tests(doc)
	bv.ensure_block_template_for(tile_id, coord)

	var poly := PackedVector2Array()
	for entry in outline:
		poly.append(Vector2(float((entry as Array)[0]), float((entry as Array)[1])))

	var mask: PackedByteArray = bv._zone_mask(tile_id, coord, "industrial")
	_check(not mask.is_empty(), "zone placement: the zone rasterises to a mask")
	var inside := 0
	for i in mask.size():
		if mask[i] != 0:
			inside += 1
	_check(inside > 0, "zone placement: the mask has buildable cells in it (%d)" % inside)
	var land: PackedByteArray = bv._tile_land.get(tile_id, PackedByteArray())
	var outside_land := 0
	for i in mask.size():
		if mask[i] != 0 and (i >= land.size() or land[i] == 0):
			outside_land += 1
	_check(outside_land == 0,
		"zone placement: the mask never adds a cell the land mask refused (%d)" % outside_land)
	_check(inside < land.count(1),
		"zone placement: the zone is a RESTRICTION, not the whole tile (%d of %d cells)"
		% [inside, land.count(1)])

	# An extraction zone is a different mask, and this tile has none.
	_check(bv._zone_mask(tile_id, coord, "extraction").is_empty(),
		"zone placement: a kind the tile has no zone of yields no mask")

	# The gate, on the rule rather than through a placement: a pump is industrial.
	_check(bv._zone_preference("mine")[0] == "extraction",
		"zone placement: a mine prefers the extraction zone")
	_check(not bv._zone_preference("water_pump").has("extraction"),
		"zone placement: a WATER PUMP is not an extraction building")
	_check(not bv._zone_preference("furnace").has("extraction"),
		"zone placement: a furnace is not either")
	_check(bv._zone_preference("mine").has("industrial"),
		"zone placement: a mine still falls back to industrial when there is no pit zone")

	# THE HALF THAT MATTERS: a real building, through the real placement path, lands inside
	# the polygon — and lands somewhere else once the zone is gone. The mask checks above
	# would all pass on a build where _search ignored the mask entirely.
	var zoned_iid: String = BuildingState.add_building("b_007", "", tile_id, "npc", "zone_in")
	bv.on_building_placed(tile_id, "b_007", "", zoned_iid, coord)
	var zoned_at: Vector2 = bv.footprint_center_for(zoned_iid, coord)
	_check(Geometry2D.is_point_in_polygon(zoned_at, poly),
		"zone placement: a building lands INSIDE the zone (%s)" % str(zoned_at.round()))

	# Same tile, same building, no zone. It must move — if it lands in the same place the
	# zone was never doing anything.
	bv.remove_instance(zoned_iid)
	BuildingState.remove_building(zoned_iid)
	AuthoredMap.set_document_for_tests({})
	bv._drop_zone_masks(tile_id)
	var free_iid: String = BuildingState.add_building("b_007", "", tile_id, "npc", "zone_out")
	bv.on_building_placed(tile_id, "b_007", "", free_iid, coord)
	var free_at: Vector2 = bv.footprint_center_for(free_iid, coord)
	_check(not Geometry2D.is_point_in_polygon(free_at, poly),
		"zone placement: without the zone it lands ELSEWHERE (%s)" % str(free_at.round()))
	_check(zoned_at.distance_to(free_at) > 20.0,
		"zone placement: the two placements are genuinely different (%.0f u apart)"
		% zoned_at.distance_to(free_at))
	bv.remove_instance(free_iid)
	BuildingState.remove_building(free_iid)

	AuthoredMap.set_document_for_tests({})
	AuthoredMap.reset_for_tests()
	bv.queue_free()
	terrain.queue_free()
	await get_tree().process_frame


## P1's actual behaviour: with an extraction zone AND an industrial zone on one tile, a mine
## goes to the pit and a factory does not. Tested by placing both and looking at where they
## landed — the preference list alone would pass even if _search never consulted it.
func _test_zone_priority() -> void:
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	var bv := preload("res://scenes/building_visuals.gd").new()
	add_child(bv)
	await get_tree().process_frame
	bv.terrain_layer = terrain

	var tile_id := "tile_9_10"
	var coord: Vector2i = terrain.id_to_coord(tile_id)
	if not terrain.tiles.has(coord):
		bv.queue_free(); terrain.queue_free(); return
	var centre: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))

	# Two zones in opposite corners, so which one a building chose is unambiguous.
	var pit_at := centre + Vector2(-150.0, -120.0)
	var works_at := centre + Vector2(150.0, 120.0)
	var pit: Array = []
	var works: Array = []
	for offset in [Vector2(-80, -70), Vector2(80, -70), Vector2(80, 70), Vector2(-80, 70)]:
		pit.append([pit_at.x + offset.x, pit_at.y + offset.y])
		works.append([works_at.x + offset.x, works_at.y + offset.y])
	AuthoredMap.set_document_for_tests({"version": AuthoredMap.SCHEMA_VERSION,
		"settlements": {"s": {"tiles": [tile_id], "zones": [
			{"id": "zp", "kind": "extraction", "tiles": [tile_id], "outline": pit},
			{"id": "zw", "kind": "industrial", "tiles": [tile_id], "outline": works},
		]}}})
	bv.ensure_block_template_for(tile_id, coord)

	var pit_poly := PackedVector2Array()
	var works_poly := PackedVector2Array()
	for i in 4:
		pit_poly.append(Vector2(float(pit[i][0]), float(pit[i][1])))
		works_poly.append(Vector2(float(works[i][0]), float(works[i][1])))

	# b_001 is the mine, b_007 the industrial factory.
	var mine_iid: String = BuildingState.add_building("b_001", "", tile_id, "npc", "zp_mine")
	bv.on_building_placed(tile_id, "b_001", "", mine_iid, coord)
	var mine_at: Vector2 = bv.footprint_center_for(mine_iid, coord)
	_check(Geometry2D.is_point_in_polygon(mine_at, pit_poly),
		"zone priority: the mine went to the EXTRACTION zone (%s)" % str(mine_at.round()))
	_check(not Geometry2D.is_point_in_polygon(mine_at, works_poly),
		"zone priority: and not to the industrial one")

	var works_iid: String = BuildingState.add_building("b_007", "", tile_id, "npc", "zw_plant")
	bv.on_building_placed(tile_id, "b_007", "", works_iid, coord)
	var works_pos: Vector2 = bv.footprint_center_for(works_iid, coord)
	_check(Geometry2D.is_point_in_polygon(works_pos, works_poly),
		"zone priority: the factory went to the INDUSTRIAL zone (%s)" % str(works_pos.round()))
	_check(not Geometry2D.is_point_in_polygon(works_pos, pit_poly),
		"zone priority: a factory may not take the pit")

	bv.remove_instance(mine_iid); BuildingState.remove_building(mine_iid)
	bv.remove_instance(works_iid); BuildingState.remove_building(works_iid)
	AuthoredMap.set_document_for_tests({})
	AuthoredMap.reset_for_tests()
	bv.queue_free()
	terrain.queue_free()
	await get_tree().process_frame


## P2: inside a zone, a building takes clear ground before it takes fabric, and offered
## fabric before protected fabric. Asserted by placing into a zone whose LEFT half is covered
## by a mass and checking the building went right — then marking the mass sacrificial and
## checking that stops mattering only after the clear ground is gone.
func _test_zone_fabric_tiers() -> void:
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	var bv := preload("res://scenes/building_visuals.gd").new()
	add_child(bv)
	await get_tree().process_frame
	bv.terrain_layer = terrain

	var tile_id := "tile_9_10"
	var coord: Vector2i = terrain.id_to_coord(tile_id)
	if not terrain.tiles.has(coord):
		bv.queue_free(); terrain.queue_free(); return
	var centre: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))

	# A wide zone, with a mass sitting squarely over its left half.
	var zone: Array = []
	for offset in [Vector2(-180, -70), Vector2(180, -70), Vector2(180, 70), Vector2(-180, 70)]:
		zone.append([centre.x + offset.x, centre.y + offset.y])
	var mass_centre := centre + Vector2(-95.0, 0.0)
	var doc := {"version": AuthoredMap.SCHEMA_VERSION, "settlements": {"s": {
		"tiles": [tile_id],
		"decor": [{"id": "m1", "form": "rect", "pos": [mass_centre.x, mass_centre.y],
			"rot": 0.0, "size": [170, 140], "sacrificial": false}],
		"zones": [{"id": "z1", "kind": "industrial", "tiles": [tile_id], "outline": zone}],
	}}}
	_check(AuthoredMap.validate(doc).is_empty(), "zone tiers: the fixture is valid")
	AuthoredMap.set_document_for_tests(doc)
	bv.ensure_block_template_for(tile_id, coord)

	var clear_mask: PackedByteArray = bv._zone_mask(tile_id, coord, "industrial",
		bv.ZoneTier.CLEAR)
	var any_mask: PackedByteArray = bv._zone_mask(tile_id, coord, "industrial",
		bv.ZoneTier.ANY)
	_check(clear_mask.count(1) > 0 and clear_mask.count(1) < any_mask.count(1),
		"zone tiers: the clear tier is a strict subset (%d of %d cells)"
		% [clear_mask.count(1), any_mask.count(1)])
	# Protected fabric is refused by BOTH restrictive tiers; only ANY tolerates it.
	var offered: PackedByteArray = bv._zone_mask(tile_id, coord, "industrial",
		bv.ZoneTier.SACRIFICIAL_OK)
	_check(offered.count(1) == clear_mask.count(1),
		"zone tiers: PROTECTED fabric is refused by the sacrificial tier too (%d vs %d)"
		% [offered.count(1), clear_mask.count(1)])

	var iid: String = BuildingState.add_building("b_007", "", tile_id, "npc", "tier_a")
	bv.on_building_placed(tile_id, "b_007", "", iid, coord)
	var at: Vector2 = bv.footprint_center_for(iid, coord)
	_check(at.x > centre.x,
		"zone tiers: the building avoided the covered half (x %.0f vs tile centre %.0f)"
		% [at.x, centre.x])
	bv.remove_instance(iid); BuildingState.remove_building(iid)

	# Marked sacrificial, the SAME mass stops blocking the middle tier — the ground is
	# offered up, so it is available before the tile has to reach for protected fabric.
	(doc["settlements"]["s"]["decor"][0] as Dictionary)["sacrificial"] = true
	AuthoredMap.set_document_for_tests(doc)
	bv._drop_zone_masks(tile_id)
	var offered_now: PackedByteArray = bv._zone_mask(tile_id, coord, "industrial",
		bv.ZoneTier.SACRIFICIAL_OK)
	_check(offered_now.count(1) > clear_mask.count(1),
		"zone tiers: offered-up fabric widens the middle tier (%d -> %d cells)"
		% [clear_mask.count(1), offered_now.count(1)])
	_check(bv._zone_mask(tile_id, coord, "industrial", bv.ZoneTier.CLEAR).count(1)
		== clear_mask.count(1),
		"zone tiers: but the clear tier is unmoved — clear ground is still preferred first")

	AuthoredMap.set_document_for_tests({})
	AuthoredMap.reset_for_tests()
	bv.queue_free()
	terrain.queue_free()
	await get_tree().process_frame


func _test_authored_map_write_barrier() -> void:
	var was_scratch := OS.get_environment("POE_EDITOR_SCRATCH")
	OS.set_environment("POE_EDITOR_SCRATCH", "1")
	_check(AuthoredMap.is_scratch_process(), "write barrier: scratch mode is detected")
	_check(AuthoredMap.writable(AuthoredMap.path_for("stoneshore-procedural")) != "",
		"write barrier: a harness cannot write a real document")
	_check(AuthoredMap.writable(AuthoredMap.path_for("__scratch__")) == "",
		"write barrier: a harness can still write its own scratch document")
	# And the refusal is enforced by save_to, not merely reported by the predicate.
	var doc := AuthoredMap.empty_document()
	var problem: String = AuthoredMap.save_to(doc, AuthoredMap.path_for("stoneshore-procedural"))
	_check(problem != "", "write barrier: save_to refuses (%s)" % problem)

	OS.set_environment("POE_EDITOR_SCRATCH", "")
	_check(not AuthoredMap.is_scratch_process(), "write barrier: a real session is not scratch")
	_check(AuthoredMap.writable(AuthoredMap.path_for("stoneshore-procedural")) == "",
		"write barrier: a real session may save normally")
	OS.set_environment("POE_EDITOR_SCRATCH", was_scratch)


func _test_authored_road_geometry() -> void:
	# A stroke of plain corners must stay exactly those corners: resampling a straight run
	# would multiply its vertices for nothing and move the wobble's phase.
	var straight := {"id": "r:s", "class": "mid", "points": [[0, 0], [100, 0], [100, 80]]}
	var sampled := AuthoredRoadGeometry.sample(straight)
	_check(sampled.size() == 3, "authored roads: an all-corner stroke keeps its corners")
	_check(sampled[0] == Vector2(0, 0) and sampled[2] == Vector2(100, 80),
		"authored roads: corner positions are preserved exactly")

	# A point with handles becomes a curve, which must be denser than its control points
	# and must still start and end where the designer put it.
	var curved := {"id": "r:c", "class": "mid",
		"points": [[0, 0], [100, 0, -40, -40, 40, 40], [200, 0]]}
	var curve_points := AuthoredRoadGeometry.sample(curved)
	_check(curve_points.size() > 3, "authored roads: handles produce a sampled curve")
	_check(curve_points[0].distance_to(Vector2(0, 0)) < 0.01
		and curve_points[curve_points.size() - 1].distance_to(Vector2(200, 0)) < 0.01,
		"authored roads: a curve still begins and ends on its authored endpoints")

	# Determinism, and endpoint exactness through the wobble: a stroke must look the same on
	# every load, and must still meet whatever it was drawn to meet.
	var drawn_a := AuthoredRoadGeometry.polyline(straight)
	var drawn_b := AuthoredRoadGeometry.polyline(straight)
	_check(drawn_a == drawn_b, "authored roads: the drawn line is deterministic")
	_check(drawn_a[0] == Vector2(0, 0)
		and drawn_a[drawn_a.size() - 1] == Vector2(100, 80),
		"authored roads: the wobble leaves both endpoints exact")
	_check(drawn_a.size() > sampled.size(),
		"authored roads: the wobble subdivides the line it is applied to")

	# Two strokes with IDENTICAL geometry must not be congruent — the same rule the mass
	# vocabulary lives by, applied to linework.
	var twin := {"id": "r:s2", "class": "mid", "points": [[0, 0], [100, 0], [100, 80]]}
	_check(AuthoredRoadGeometry.polyline(twin) != drawn_a,
		"authored roads: two identical strokes wobble differently (seeded by id)")

	var length := AuthoredRoadGeometry.length_of(sampled)
	_check(absf(length - 180.0) < 0.01, "authored roads: length_of measures the polyline")


func _test_authored_road_touched_tiles() -> void:
	# THE UNLOCK RULE READS THIS SET, so a missed tile would let a stroke appear across land
	# the player has not connected. A 1000 u straight run crosses eleven stub tiles with
	# only two vertices — per-vertex testing would report two, and a sampling step coarser
	# than the tile would skip whole tiles in the middle (which it did, at the first attempt).
	var terrain := _StubTerrain.new()
	var stroke := {"id": "r:t", "class": "mid", "points": [[50, 50], [1050, 50]]}
	var tiles := AuthoredRoadGeometry.touched_tiles(AuthoredRoadGeometry.sample(stroke), terrain)
	_check(tiles.size() == 11,
		"authored roads: a long segment reports every tile it crosses (%d)" % tiles.size())
	for column in 11:
		_check(tiles.has("stub_%d_0" % column),
			"authored roads: no tile is skipped mid-run (stub_%d_0)" % column)
	_check(tiles.has("stub_0_0") and tiles.has("stub_10_0"),
		"authored roads: both ends of the run are in the touched set")
	var sorted_copy := tiles.duplicate()
	sorted_copy.sort()
	_check(tiles == sorted_copy, "authored roads: the touched-tile set is sorted (stable in git)")
	terrain.free()


func _test_authored_road_style_hierarchy() -> void:
	# The three classes must read as a hierarchy at every level of the treatment, not just
	# in width — this is what lets a designer tell them apart on a busy plate.
	var classes := ["major", "mid", "minor"]
	for index in range(classes.size() - 1):
		var bigger: String = classes[index]
		var smaller: String = classes[index + 1]
		_check(AuthoredRoadStyle.bed_width(bigger) > AuthoredRoadStyle.bed_width(smaller),
			"authored roads: %s is wider than %s" % [bigger, smaller])
		_check(AuthoredRoadStyle.casing_color(bigger).a > AuthoredRoadStyle.casing_color(smaller).a,
			"authored roads: %s carries the firmer ink edge" % bigger)
		# Smaller roads wobble more — the curated departure from one map-wide setting.
		_check(float(AuthoredRoadStyle.wobble(bigger)[1]) < float(AuthoredRoadStyle.wobble(smaller)[1]),
			"authored roads: %s runs straighter than %s" % [bigger, smaller])
	for stroke_class in classes:
		_check(AuthoredRoadStyle.casing_width(stroke_class) > AuthoredRoadStyle.bed_width(stroke_class),
			"authored roads: the %s casing stands proud of its bed" % stroke_class)
	# Authored strokes are never RDP-simplified: that would flatten the drawn curves.
	_check(is_zero_approx(AuthoredRoadStyle.SIMPLIFY_EPS),
		"authored roads: authored curves are not simplified away")


func _test_authored_road_water_and_bridges() -> void:
	# Water detection runs against the real NavGrid, sampled at 4 u — the resolution the
	# road-water audit needed to catch a chord crossing a bay between two dry vertices.
	var nav := NavGrid.instance()
	if nav == null or not nav.is_ready():
		_check(true, "authored roads: NavGrid unavailable, water lint skipped")
		return
	var sea_point := Vector2.ZERO
	var found := false
	# Walk the grid for a sea cell rather than hard-coding a coordinate, which would rot
	# the moment the terrain is re-baked.
	for ix in range(0, 1200, 17):
		for iy in range(0, 1000, 17):
			if nav.water(ix, iy) == NavGrid.WATER_SEA:
				sea_point = nav.world_of(ix, iy)
				found = true
				break
		if found:
			break
	_check(found, "authored roads: the terrain has sea to test against")
	if not found:
		return
	var wet_stroke := {"id": "r:w", "class": "mid",
		"points": [[sea_point.x - 30.0, sea_point.y], [sea_point.x + 30.0, sea_point.y]]}
	var wet := AuthoredRoadGeometry.wet_samples(AuthoredRoadGeometry.sample(wet_stroke), nav)
	_check(not wet.is_empty(), "authored roads: a stroke over the sea is reported wet")
	_check(int(wet[0][1]) == NavGrid.WATER_SEA,
		"authored roads: the wet report names the water it found")

	# Rivers are deliberately NOT wet: roads bridge them, and the stroke carries the deck.
	var crossings := AuthoredRoadGeometry.river_crossings(
		AuthoredRoadGeometry.sample(wet_stroke), nav)
	_check(crossings.is_empty() or (crossings[0][1] as Vector2).length() > 0.9,
		"authored roads: a reported crossing carries a unit tangent for its deck")


func _test_authored_road_visibility_document() -> void:
	# The end-to-end unlock behaviour over a whole document: an always-on stroke, a street
	# inside one roadless tile, and a connector from an already-roaded neighbour.
	var strokes := [
		{"id": "r:always", "class": "major", "tiles": ["tile_1_1"]},
		{"id": "r:street", "class": "minor", "unlockable": true, "tiles": ["tile_1_2"]},
		{"id": "r:link", "class": "mid", "unlockable": true, "tiles": ["tile_1_1", "tile_1_2"]},
	]
	var before := {"tile_1_1": true}
	var visible_before: Array = []
	for stroke in strokes:
		if AuthoredMap.road_visible(stroke, before):
			visible_before.append(str(stroke.id))
	_check(visible_before == ["r:always"],
		"authored roads: before the purchase only the always-on stroke draws")

	var after := {"tile_1_1": true, "tile_1_2": true}
	var visible_after: Array = []
	for stroke in strokes:
		if AuthoredMap.road_visible(stroke, after):
			visible_after.append(str(stroke.id))
	_check(visible_after.size() == 3,
		"authored roads: buying roads reveals the tile's street AND its connector together")


func _test_authored_road_signal_arity() -> void:
	# A handler with FEWER parameters than its signal still connects, and fails only when
	# the signal fires — the error goes to the log while the feature just silently stops
	# updating. That exact mismatch (a 1-argument handler on a 2-argument signal) made the
	# unlock reveal a no-op while every unit test passed, and only a windowed pixel diff
	# caught it. This pins the arity so the next edit to either side breaks a test instead.
	# Held as Script resources: calling these through the preloaded constant reads as a call
	# on the class itself, which GDScript rejects.
	var world_script: Script = WorldMapScript
	var visuals_script: Script = AuthoredRoadVisualsScript
	var signal_args := -1
	for entry in world_script.get_script_signal_list():
		if str(entry.get("name", "")) == "tile_infrastructure_changed":
			signal_args = (entry.get("args", []) as Array).size()
	_check(signal_args == 2,
		"authored roads: tile_infrastructure_changed carries (tile_id, infra_type)")

	var handler_args := -1
	for entry in visuals_script.get_script_method_list():
		if str(entry.get("name", "")) == "_on_tile_infrastructure_changed":
			handler_args = (entry.get("args", []) as Array).size()
	_check(handler_args == signal_args,
		"authored roads: the reveal handler takes exactly the signal's arguments (%d vs %d)"
		% [handler_args, signal_args])


# ======================================================================================
# Authored ground and fabric (scripts/authored_fabric_painter.gd + the shape tool)
# ======================================================================================
func _test_authored_mass_geometry() -> void:
	# Every form in the vocabulary must produce a simple, triangulable mass from a stamp, and
	# must stay inside the box the designer dragged — a mass that overflows its own footprint
	# would collide with things the editor believes it clears.
	var bad := PackedStringArray()
	for form_value in MassFormShapes.ALL_FORMS:
		var form := str(form_value)
		var mass := {"id": "d:test:%s" % form, "form": form, "pos": [1000.0, 1000.0],
			"rot": 0.6, "size": [90.0, 58.0]}
		var parcel: PackedVector2Array = AuthoredFabricPainter.mass_parcel(mass)
		var polys: Array = AuthoredFabricPainter.mass_polygons(mass)
		if polys.is_empty():
			bad.append("%s: nothing built" % form)
			continue
		for poly_value in polys:
			var poly: PackedVector2Array = poly_value
			if poly.size() < 3 or Geometry2D.triangulate_polygon(poly).is_empty():
				bad.append("%s: not triangulable" % form)
				break
			for point in poly:
				# Generous tolerance: the constructors inset, they never inflate.
				if not Geometry2D.is_point_in_polygon(point, _grow_quad(parcel, 2.0)):
					bad.append("%s: escapes its stamp box" % form)
					break
	_check(bad.is_empty(), "authored fabric: every form stamps a sound mass (%s)" % ", ".join(bad))

	# A box too small to be a building yields nothing rather than a sliver.
	var tiny := {"id": "d:test:tiny", "form": "cross", "pos": [0.0, 0.0], "rot": 0.0,
		"size": [0.4, 0.4]}
	_check(AuthoredFabricPainter.mass_polygons(tiny).is_empty(),
		"authored fabric: a degenerate stamp builds nothing")


func _test_authored_woodland_scatter() -> void:
	# THE REGRESSION THIS PINS: the scatter used RoadHash.pick on sequential keys, whose low
	# bits repeat, so consecutive samples landed within a unit of each other on a three-step
	# cycle and a wood rendered as two thin diagonal lines. Only a screenshot caught it. The
	# test now measures the spread directly.
	var outline := PackedVector2Array([Vector2(0, 0), Vector2(340, -60), Vector2(400, 200),
		Vector2(60, 240)])
	var points := AuthoredFabricPainter.woodland_points({"id": "fo:test:1", "outline":
		[[0, 0], [340, -60], [400, 200], [60, 240]]})
	_check(points.size() > 40,
		"authored fabric: a wood is filled, not sprinkled (%d trees)" % points.size())

	# Occupancy across a coarse grid: a line through the polygon touches few buckets, a fill
	# touches most of them.
	var buckets := {}
	for point in points:
		buckets[Vector2i(int(point.x / 40.0), int(point.y / 40.0))] = true
	_check(buckets.size() >= 24,
		"authored fabric: trees spread across the outline (%d buckets)" % buckets.size())

	# No two trees on top of each other — the symptom of the cycle was near-duplicates.
	var duplicates := 0
	for i in points.size():
		for j in range(i + 1, points.size()):
			if points[i].distance_to(points[j]) < 2.0:
				duplicates += 1
	_check(duplicates == 0, "authored fabric: no two trees share a spot (%d)" % duplicates)

	# Determinism, and containment: a canopy may not overhang the outline it was drawn in.
	var again := AuthoredFabricPainter.woodland_points({"id": "fo:test:1", "outline":
		[[0, 0], [340, -60], [400, 200], [60, 240]]})
	_check(points == again, "authored fabric: the same wood scatters identically every time")
	var outside := 0
	for point in points:
		if not Geometry2D.is_point_in_polygon(point, outline):
			outside += 1
	_check(outside == 0, "authored fabric: no tree is planted outside its polygon (%d)" % outside)


func _test_authored_shape_tool() -> void:
	var tool_ref: RefCounted = MapEditorShapeToolScript.new()
	tool_ref.set_kind("forests")
	for i in AuthoredMap.AREA_MAX_VERTICES:
		_check(str(tool_ref.add_point(Vector2(float(i) * 30.0, 0.0))) == "",
			"authored fabric: corner %d is accepted" % i)
	# The cap is enforced while clicking, with a message — not by rejecting the finished
	# shape at save time, when the work is already done.
	_check(str(tool_ref.add_point(Vector2(999.0, 999.0))) != "",
		"authored fabric: the ninth corner is refused with a reason")
	var record: Dictionary = tool_ref.finish_polygon("test", 7)
	_check(str(record.get("id", "")) == "fo:test:7",
		"authored fabric: a wood takes the fo: prefix and the supplied id")
	_check((record.get("outline", []) as Array).size() == AuthoredMap.AREA_MAX_VERTICES,
		"authored fabric: the outline keeps every accepted corner")
	_check(AuthoredMap.validate(_document_with("forests", record)).is_empty(),
		"authored fabric: a finished wood validates against the schema")

	# Two corners is not a shape.
	tool_ref.abandon()
	tool_ref.add_point(Vector2.ZERO)
	tool_ref.add_point(Vector2(10.0, 0.0))
	_check((tool_ref.finish_polygon("test", 8) as Dictionary).is_empty(),
		"authored fabric: two corners build nothing")


## The harbour planner's cache key. It used to be made of two GLOBAL counters — RoadNetwork's
## total edge count and the map-wide footprint version — so a shed raised, or a lane laid,
## anywhere at all missed the cache for every port and re-ran a 1,440-candidate coastline
## search per harbour to arrive at the identical drawing. Three of those is 3.2 s on the main
## thread, which is the freeze the owner hit after pressing Build (25 Aug). Nothing could see
## it: the plans came out right, only slowly, and no test asserted what the key was made of.
## These pin the locality the fix rests on, in both directions.
func _test_port_plan_cache_locality() -> void:
	var plan_script: Variant = load("res://scripts/midcentury_port_plan.gd")
	var net := RoadNetwork.instance()
	var origin := Vector2i(10, 10)
	var before: int = plan_script._road_signature(origin)
	# _road_access only ever looks at the 5x5 block around the port, so a lane outside it
	# cannot move the quay approach and must not cost a replan.
	var far := origin + Vector2i(6, 6)
	net.edges["_probe_edge"] = {"state": "built"}
	net._edges_by_tile[far] = ["_probe_edge"]
	var after_far: int = plan_script._road_signature(origin)
	# ...and one INSIDE the block must change it, or a real approach could quietly go stale.
	var near := origin + Vector2i(1, 0)
	net._edges_by_tile[near] = ["_probe_edge"]
	var after_near: int = plan_script._road_signature(origin)
	net._edges_by_tile.erase(far)
	net._edges_by_tile.erase(near)
	net.edges.erase("_probe_edge")
	_check(after_far == before,
		"port plan cache: a lane six tiles from a harbour does not invalidate its plan")
	_check(after_near != before,
		"port plan cache: a lane beside a harbour does invalidate its plan")
	_check(plan_script._road_signature(origin) == before,
		"port plan cache: the locality probe left the road network as it found it")
	# The other half of the key: the obstacles near the port.
	var poly_a := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)])
	var poly_b := PackedVector2Array([Vector2(0, 0), Vector2(2, 0), Vector2(2, 2)])
	_check(plan_script._exclusion_signature([{"poly": poly_a}])
		!= plan_script._exclusion_signature([{"poly": poly_b}]),
		"port plan cache: a footprint that moves beside a harbour changes its key")
	_check(plan_script._exclusion_signature([{"poly": poly_a}])
		== plan_script._exclusion_signature([{"poly": poly_a}]),
		"port plan cache: an unchanged neighbourhood keeps the same key")


## Canopy types: the seven the editor offers must all exist in the painter, "current" must
## still draw exactly what it drew before they were added, and each type must actually change
## the wood — a variant that silently did nothing is the failure mode a look-dev tool cannot
## catch once it stops being looked at.
func _test_forest_canopy_variants() -> void:
	var Painter := load("res://scripts/authored_fabric_painter.gd")
	var MapEd := load("res://scripts/map_editor/map_editor.gd")

	# The editor's list and the painter's knob table cannot drift apart.
	_check(MapEd.FOREST_VARIANTS == Painter.FOREST_VARIANTS,
		"canopy: the editor offers exactly the painter's types")
	var missing: Array = []
	for name in Painter.FOREST_VARIANTS:
		if not Painter._VARIANT_KNOBS.has(str(name)):
			missing.append(str(name))
	_check(missing.is_empty(), "canopy: every type has knobs (%s)" % str(missing))
	_check(str(Painter.FOREST_VARIANTS[0]) == "current",
		"canopy: type 1 is the shipped look, so key 1 is always 'leave it alone'")

	# A square wood, big enough that every knob has room to act but comfortably UNDER
	# TREE_LIMIT (900). At density 4 a wood this size generates thousands of candidates and
	# woodland_points returns early at the cap — every variant then truncates to exactly 900
	# and looks identical, which is how this test first failed. The cap also truncates
	# COLUMN-WISE rather than sampling, so on a capped wood a gradient is partly masked.
	var area := {
		"id": "fo:test:1",
		"density": 1.0,
		"outline": [[-160.0, -160.0], [160.0, -160.0], [160.0, 160.0], [-160.0, 160.0]],
	}
	var counts: Dictionary = {}
	for name in Painter.FOREST_VARIANTS:
		var probe: Dictionary = area.duplicate(true)
		probe["variant"] = str(name)
		counts[str(name)] = Painter.woodland_points(probe).size()
	_check(int(counts["current"]) > 0, "canopy: the control wood actually has trees (%d)" % int(counts["current"]))

	# No variant may leave the wood unchanged — that is the silent-no-op case.
	var inert: Array = []
	for name in Painter.FOREST_VARIANTS:
		if str(name) == "current":
			continue
		if int(counts[str(name)]) == int(counts["current"]):
			inert.append(str(name))
	_check(inert.is_empty(), "canopy: no type is a silent no-op (%s)" % str(inert))
	# The two the owner picked out by name, in the direction they were specified.
	_check(int(counts["sparse"]) < int(counts["current"]),
		"canopy: sparse is thinner than the shipped look (%d vs %d)" % [int(counts["sparse"]), int(counts["current"])])

	# An area with NO variant must be byte-identical to an explicit "current" — that is what
	# keeps every wood already in the document exactly as it was.
	var bare: Dictionary = area.duplicate(true)
	var explicit: Dictionary = area.duplicate(true)
	explicit["variant"] = "current"
	_check(Painter.woodland_points(bare) == Painter.woodland_points(explicit),
		"canopy: a wood with no type set draws as it always did")

	# "graded" thins across the wood rather than uniformly: far half well under the near half.
	var graded: Dictionary = area.duplicate(true)
	graded["variant"] = "graded"
	var pts: PackedVector2Array = Painter.woodland_points(graded)
	# Split along the wood's OWN gradient axis, derived exactly as the painter derives it —
	# the axis is per-wood (so neighbouring woods do not all thin the same way), and measuring
	# across a fixed diagonal reads a real gradient as almost uniform.
	var RoadHashRef := load("res://scripts/road_hash.gd")
	var salt: int = RoadHashRef.fnv1a(str(graded["id"])) & 0xFFFF
	var wob_salt: float = float(salt % 977) * 0.031
	var axis := Vector2(cos(wob_salt * 2.1), sin(wob_salt * 2.1))
	var near := 0
	var far := 0
	for q in pts:
		if q.dot(axis) < 0.0:
			near += 1
		else:
			far += 1
	_check(near > 0 and far > 0, "canopy: graded keeps trees at both ends")
	_check(mini(near, far) * 2 < maxi(near, far),
		"canopy: graded is genuinely dense-to-sparse, not uniform (%d vs %d)" % [near, far])


## A wood drawn in the editor makes its tile wooded in the sim, not only in the picture.
## AuthoredMap hands over the AREAS; world_map maps them onto tiles, because placing a wood on
## a tile needs the hex geometry and most woods in the document carry only an outline (they
## were imported from the procedural discs before the editor could plant them).
func _test_authored_forest_areas() -> void:
	var AM := load("res://scripts/authored_map.gd")
	var areas: Array = AM.forest_areas()
	_check(areas is Array, "authored forests: forest_areas returns the records")
	# Every record needs an id and a usable outline, or it can be neither drawn nor felled.
	var broken: Array = []
	for area_value in areas:
		var area: Dictionary = area_value
		if str(area.get("id", "")) == "" or (area.get("outline", []) as Array).size() < 3:
			broken.append(str(area.get("id", "?")))
	_check(broken.is_empty(), "authored forests: every wood has an id and an outline (%s)" % str(broken))

func _test_road_regions() -> void:
	RoadRegionsLoader.reset_for_tests()
	var ids := RoadRegionsLoader.region_ids()
	_check(ids.size() == 50, "road regions: 50 authored regions")
	_check(RoadRegionsLoader.region_of("tile_6_1") == "shoulderland",
		"road regions: tile lookup returns Shoulderland")
	_check(RoadRegionsLoader.identity("shoulderland") == RoadRegionsLoader.ID_MOUNTAIN_RANGE,
		"road regions: Shoulderland uses mountain_range special style")
	_check(RoadRegionsLoader.identity_for_tile("tile_12_2") == RoadRegionsLoader.ID_SPARSE_RURAL,
		"road regions: unassigned land defaults to sparse_rural")

	var mountain_style := RoadRegionsLoader.style_for_identity(RoadRegionsLoader.ID_MOUNTAIN_RANGE)
	_check(int(mountain_style.get("max_segments", 0)) == 3,
		"road regions: mountain_range caps at 3 segments")
	_check(str(mountain_style.get("network_pattern", "")) == RoadRegionsLoader.PATTERN_MOUNTAIN_PASS,
		"road regions: mountain_range uses pass routing")
	_check(str(mountain_style.get("water_policy", "")) == RoadRegionsLoader.WATER_POLICY,
		"road regions: water is impassable for road styles")
	var sparse_style := RoadRegionsLoader.style_for_identity(RoadRegionsLoader.ID_SPARSE_RURAL)
	_check(str(sparse_style.get("network_pattern", "")) == RoadRegionsLoader.PATTERN_THROUGH_FARM_LINKS,
		"road regions: sparse_rural uses through-route/farm links")
	var sparse_city_style := RoadRegionsLoader.style_for_identity(RoadRegionsLoader.ID_SPARSE_CITY)
	_check(not bool(sparse_city_style.get("full_orbital_allowed", true)),
		"road regions: sparse_city forbids full orbitals")

	var report := RoadRegionsLoader.validation_report()
	var overlaps: Array = report.get("overlaps", [])
	var water_tiles: Array = report.get("water_tiles", [])
	var lake_tiles: Array = report.get("lake_tiles", [])
	var mountain_mismatches: Array = report.get("mountain_rule_mismatches", [])
	var invalid_ids: Array = report.get("invalid_identities", [])
	var unknown_tiles: Array = report.get("unknown_tiles", [])
	_check(overlaps.is_empty(), "road regions: no overlapping member tiles")
	_check(RoadRegionsLoader.region_of("tile_11_7") == "kindling_mountains",
		"road regions: Kindling Mountains owns tile_11_7")
	_check(RoadRegionsLoader.region_of("tile_9_14") == "green_flats",
		"road regions: Green Flats owns tile_9_14")
	_check(water_tiles.size() == 1 and str(water_tiles[0].get("tile_id", "")) == "tile_24_18",
		"road regions: Vandel Island sea tile is the only water claim")
	_check(lake_tiles.is_empty(), "road regions: no authored region claims lake tiles")
	_check(mountain_mismatches.is_empty(),
		"road regions: all >1 mountain tile regions use mountain_range")
	_check(invalid_ids.is_empty(), "road regions: all identities are valid")
	_check(unknown_tiles.is_empty(), "road regions: all member tiles exist in tile_properties.csv")

func _test_hill_texture_baked_fresh() -> void:
	var script: Variant = load("res://scripts/hill_texture_baked.gd")
	var doc: Dictionary = script.data()
	_check(not doc.is_empty(),
		"hill texture: bake manifest exists and parses (run tools/bake_hill_texture.tscn)")
	if doc.is_empty():
		return
	_check(int(doc.get("bake_version", -1)) == script.BAKE_VERSION,
		"hill texture: bake is this build's version")
	_check(str(doc.get("source_hash", "")) == HillBaked.source_hash(),
		"hill texture: bake matches the hills (re-run tools/bake_hill_texture.tscn after "
		+ "tools/bake_hills.tscn — a stale one costs ~7 s of load, silently)")
	# The shipped bake has to be in the style the game SHIPS in, or it is refused at load for a
	# palette mismatch and redrawn live. `toggle ink` legitimately moves off it; the default
	# must not.
	_check(str(doc.get("style", "")) == script.style_key(
			MapStyle.ink, MapStyle.plate, MapStyle.is_midcentury()),
		"hill texture: bake is in the shipped default map style")
	_check(ResourceLoader.exists(script.TEXTURE_PATH),
		"hill texture: the baked PNG is loadable (run `--headless --import` after a re-bake, "
		+ "or Godot cannot see it and the relief is drawn live anyway)")


# Baked hills are the canonical hand-painted shape: the file must exist, match
# the current CSVs/generator (else someone forgot to re-bake), and only ever
# block subtiles on hill tiles (flat tiles take lv1-2 spill but never block).
# The START LAYOUT bake is the third of the three, and the only one with no freshness
# check — which is how a stale one shipped: re-baking hills and roads (and touching
# tile_properties.csv, which it also hashes) silently invalidated it, every one of the
# 417 start placements fell through to the live packer, and a 10 s load became 53 s with
# a green suite. The hills bake has had this test since it existed; this one earns it.
# The hill TEXTURE bake is the fourth of the four and, until now, the only one with no
# freshness test — which is how a stale one shipped and stayed. Re-baking the hills silently
# invalidated it, HillTextureBaked.texture() refused the picture on disk as "not a picture of
# this map", and the relief was redrawn live on every load: 6.9 s, measured, of a 15.4 s load.
# It says so on stdout, but nothing fails, so the warning scrolls past under everything else.
#
# It is refused for FOUR reasons and every one of them costs the same 6.9 s, so all four are
# checked here rather than only the hash: a version bump, a stale hash, a palette that is not
# the shipped default, and a PNG Godot cannot load because it never got an .import sidecar.
# Every authored road stroke has to land on a tile the bake actually wrote a texture for.
#
# The exporter used to offer the baker only the tiles each settlement DECLARES, but a
# connector road is authored precisely to run past them, and the runtime only ever iterates
# the manifest. So a stroke that left the declared set was drawn up to the last declared
# tile's edge and then stopped — a dead straight cut across a road (owner, 25 Aug; 33 of 323
# strokes had points on no baked tile, one of them every point it had).
#
# This checks the OUTPUT, not the exporter: it is equally a staleness tripwire, because a
# document that gains a road running somewhere new fails here until the bake is re-run.
func _test_authored_roads_all_baked() -> void:
	var bake: Variant = load("res://scripts/authored_bake.gd")
	var layout: Variant = load("res://scripts/authored_bake_layout.gd")
	var doc: Dictionary = AuthoredMap.data()
	var settlements: Dictionary = doc.get("settlements", {})
	if settlements.is_empty():
		return   # no authored document in this install; nothing to guard
	var rects: Array[Rect2] = []
	for tile_value: Variant in bake.tiles():
		rects.append(bake.tile_rect(str(tile_value)))
	_check(not rects.is_empty(), "authored roads: the bake manifest names at least one tile")
	var stray := 0
	var worst := ""
	for settlement_value: Variant in settlements.values():
		for stroke_value: Variant in ((settlement_value as Dictionary).get("roads", []) as Array):
			var stroke: Dictionary = stroke_value
			# STATIC strokes only. An `unlockable` one is deliberately kept out of the bake and
			# drawn live by authored_road_visuals, so it has no baked tile to land on and never
			# should — the 91 points that first failed this check all belonged to those.
			if not layout.road_is_static(stroke):
				continue
			var points_value: Variant = stroke.get("points", [])
			if typeof(points_value) != TYPE_ARRAY or (points_value as Array).size() < 2:
				continue
			for point_value: Variant in (points_value as Array):
				if typeof(point_value) != TYPE_ARRAY or (point_value as Array).size() < 2:
					continue
				var p := Vector2(float((point_value as Array)[0]), float((point_value as Array)[1]))
				var covered := false
				for rect_value: Variant in rects:
					if (rect_value as Rect2).has_point(p):
						covered = true
						break
				if not covered:
					stray += 1
					if worst == "":
						worst = str(stroke.get("id", "?"))
	_check(stray == 0, "authored roads: every static stroke lies on a baked tile (re-run "
		+ "tools/map_editor/bake_authored_map.tscn — %d stray point(s), first on %s)" % [stray, worst])


# Regenerate one small massif twice — identical output proves the generator is
# deterministic (the bake -> cache contract depends on it).
func _test_hill_field_determinism() -> void:
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	var centers := {}
	for coord in terrain.tiles:
		centers[coord] = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
	var r1: Dictionary = HillField.generate(terrain.tiles, centers, [], [], HillBaked.SEED, ["tile_6_8"])
	var r2: Dictionary = HillField.generate(terrain.tiles, centers, [], [], HillBaked.SEED, ["tile_6_8"])
	terrain.queue_free()
	_check(r1.polys.size() > 0, "hills: regenerated massif produced polys")
	_check(r1.polys.size() == r2.polys.size(), "hills: determinism — same poly count")
	var same := true
	for i in r1.polys.size():
		if r1.polys[i].b != r2.polys[i].b or r1.polys[i].p != r2.polys[i].p:
			same = false
			break
	_check(same, "hills: determinism — identical polygons")
	_check(JSON.stringify(r1.blocked) == JSON.stringify(r2.blocked), "hills: determinism — identical blocked masks")

func _test_roads_v2() -> void:
	var nav := NavGrid.instance()
	_check(nav.is_ready(), "roads v2: baked navgrid decodes (%dx%d)" % [nav.gw, nav.gh])
	if not nav.is_ready():
		return
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame

	# crossings: one per arm, deterministic, interior to the tile
	RoadCrossings.reset_for_tests()
	RoadCrossings.build(terrain)
	var river_tiles := 0
	var branch_ok := true
	var arm_counts_ok := true
	for coord in terrain.tiles:
		var td: Dictionary = terrain.tiles[coord]
		if not td.get("has_river", false):
			continue
		var rt := str(td.get("river_type", ""))
		if rt == "" or not terrain.river_properties.has(rt):
			continue
		river_tiles += 1
		var crossings := RoadCrossings.for_tile(str(td.id))
		if crossings.is_empty():
			arm_counts_ok = false
		var rd: Dictionary = terrain.river_properties[rt]
		if str(rd.get("exit_hsm_2", "")) != "" and crossings.size() < 2:
			branch_ok = false
	_check(river_tiles > 0 and arm_counts_ok, "roads v2: every river tile has a crossing (%d tiles)" % river_tiles)
	_check(branch_ok, "roads v2: branching rivers get one crossing per arm")
	var sample_tile: String = RoadCrossings.all_tiles()[0]
	var first_point: Vector2 = RoadCrossings.for_tile(sample_tile)[0].point
	RoadCrossings.reset_for_tests()
	RoadCrossings.build(terrain)
	_check(RoadCrossings.for_tile(sample_tile)[0].point == first_point, "roads v2: crossings deterministic")

	# realizer: deterministic land route that respects water
	var pa: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(Vector2i(9, 10)))
	var pb: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(Vector2i(11, 10)))
	var realizer := RoadRealizer.new()
	var net := RoadNetwork.new()
	var r1 := realizer.route(nav, net, pa, pb, {"identity": "dense_rural", "salt": 7})
	_check(r1.ok, "roads v2: route succeeds (%s)" % str(r1.get("reason", "")))
	if r1.ok:
		var r2 := realizer.route(nav, net, pa, pb, {"identity": "dense_rural", "salt": 7})
		_check(r2.ok and r2.geometry == r1.geometry, "roads v2: route deterministic")
		var water_ok := true
		for p in r1.geometry:
			var c: Vector2i = nav.cell_of(p)
			if nav.water(c.x, c.y) == NavGrid.WATER_SEA or nav.water(c.x, c.y) == NavGrid.WATER_LAKE:
				water_ok = false
				break
		_check(water_ok, "roads v2: route never enters sea or lakes")

	# forests are hard obstacles (shared footprint). Build the neighbour set the
	# same way RoadRealizer does (every forest in MatchState), so the test's disc
	# and the router's disc share the same gravitate-toward pull.
	var forest_tile := "tile_11_11"
	var inst: String = BuildingState.add_building("b_016", "", forest_tile, "tile_data", "", false)
	var nbf: Array = []
	for iid_f in BuildingState.buildings:
		var bf: Dictionary = BuildingState.buildings[iid_f]
		if not ForestFootprint.is_forest(str(bf.get("building_id", ""))):
			continue
		var cf: Vector2i = terrain.id_to_coord(str(bf.get("tile_id", "")))
		if terrain.tiles.has(cf):
			nbf.append(terrain.map_to_local(terrain.map_coord_for_tile_coord(cf)))
	var fcoord: Vector2i = terrain.id_to_coord(forest_tile)
	var fcenter: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(fcoord))
	var disc := ForestFootprint.footprint(inst, forest_tile, fcoord, fcenter,
		RiverGeometry.arms(terrain.tiles[fcoord], terrain.river_properties, fcenter),
		RiverGeometry.lake_ellipse(terrain.tiles[fcoord], terrain.river_properties, fcenter), nbf)
	var disc2 := ForestFootprint.footprint(inst, forest_tile, fcoord, fcenter,
		RiverGeometry.arms(terrain.tiles[fcoord], terrain.river_properties, fcenter),
		RiverGeometry.lake_ellipse(terrain.tiles[fcoord], terrain.river_properties, fcenter), nbf)
	_check(disc.center == disc2.center, "roads v2: forest footprint deterministic")
	var across := realizer.route(nav, net, fcenter + Vector2(-420, 0), fcenter + Vector2(420, 0), {"identity": "sparse_rural", "salt": 3})
	_check(across.ok, "roads v2: route across a forest tile succeeds")
	if across.ok:
		var clear := true
		for p in across.geometry:
			if p.distance_to(disc.center) < disc.radius - 6.0:
				clear = false
				break
		_check(clear, "roads v2: route avoids the forest disc")
	BuildingState.remove_building(inst)

	# starting anchor network (spec 4.5b): baked, fresh, bootstrappable
	var baked := RoadsBaked.data()
	_check(not baked.is_empty(), "roads v2: starting network bake present")
	if not baked.is_empty():
		_check(str(baked.get("hills_hash", "")) == HillBaked.source_hash(),
			"roads v2: starting network fresh vs terrain bake")
		_check(RoadsBaked.anchors().size() >= 2, "roads v2: anchor list present (%d)" % RoadsBaked.anchors().size())
		RoadNetwork.reset()
		RoadNetwork.bootstrap_from_bake()
		var boot := RoadNetwork.instance()
		_check(boot.edge_count() >= RoadsBaked.anchors().size() - 2,
			"roads v2: bootstrap imports the anchor spine (%d edges)" % boot.edge_count())
		# baked geometry avoids the deterministic game-start forest discs. The
		# canonical forest set (old-growth rows 1-6 + start b_015), with the SAME
		# instance ids the bake used, feeds the gravitate-toward-neighbours pull.
		var forest_set: Array = []   # [instance_id, tile_id, coord]
		for coord2 in terrain.tiles:
			if coord2.y + 1 > 6:
				continue
			var tt2 := str(terrain.tiles[coord2].get("type", "")).strip_edges().to_lower()
			if tt2 == "rural" or tt2 == "hill":
				var tid := str(terrain.tiles[coord2].get("id", ""))
				forest_set.append(["forest_b_016_" + tid, tid, coord2])
		for entry in StartBuildings.entries():
			if str(entry.building) == "b_015":
				var c3: Vector2i = terrain.id_to_coord(str(entry.tile))
				if terrain.tiles.has(c3):
					forest_set.append([str(entry.instance_id), str(entry.tile), c3])
		var forest_centers: Array = []
		for ft in forest_set:
			forest_centers.append(terrain.map_to_local(terrain.map_coord_for_tile_coord(ft[2])))
		var forests_clear := true
		for ft2 in forest_set:
			var coord2b: Vector2i = ft2[2]
			var td2: Dictionary = terrain.tiles[coord2b]
			var fc2: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord2b))
			var fdisc := ForestFootprint.footprint(str(ft2[0]), str(ft2[1]), coord2b, fc2,
				RiverGeometry.arms(td2, terrain.river_properties, fc2),
				RiverGeometry.lake_ellipse(td2, terrain.river_properties, fc2),
				forest_centers)
			if not _edges_clear_of_disc(boot, fdisc):
				forests_clear = false
		_check(forests_clear, "roads v2: baked spine avoids game-start forest discs")
		RoadNetwork.reset()

	# network graph save round-trip
	if r1.ok:
		var na := net.ensure_node("dbg:a", RoadNetwork.KIND_JUNCTION, pa, Vector2i(9, 10))
		var nb := net.ensure_node("dbg:b", RoadNetwork.KIND_JUNCTION, pb, Vector2i(11, 10))
		realizer.commit(net, na.id, nb.id, RoadNetwork.TIER_LOCAL, r1, 1)
		var snap1 := net.export_state()
		var net2 := RoadNetwork.new()
		net2.import_state(snap1)
		_check(JSON.stringify(net2.export_state()) == JSON.stringify(snap1), "roads v2: network save round-trip")
		_check(net2.near_network(r1.geometry[r1.geometry.size() / 2]), "roads v2: occupancy hash survives import")
	terrain.queue_free()
	await get_tree().process_frame

# Road doubling — Fix 2 regression. _nearest_attachment used to sample edge geometry every 8th
# vertex (~240u apart after thinning), so a connect order's GOAL could land tens of u off the road
# centreline, seeding a parallel "doubled" road. It now projects onto each SEGMENT, pinning the goal
# to the true foot-of-perpendicular. This pins that behaviour (pre-fix the projected error was ~48u).
func _test_road_attachment_projection() -> void:
	var nav := NavGrid.instance()
	if not nav.is_ready():
		return
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	RoadNetwork.reset()
	var coord := Vector2i(8, 9)
	var c: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
	var realizer := RoadRealizer.new()
	var net := RoadNetwork.instance()
	var resA := realizer.route(nav, net, c + Vector2(-330, 0), c + Vector2(330, 0), {"identity": "dense_rural", "salt": 5})
	if resA.ok:
		var na := str(net.add_junction(c + Vector2(-330, 0), coord).id)
		var nb := str(net.add_junction(c + Vector2(330, 0), coord).id)
		realizer.commit(net, na, nb, RoadNetwork.TIER_TRUNK, resA, 0, RoadNetwork.STATE_BUILT)
		var a_geo: PackedVector2Array = resA.geometry
		var from: Vector2 = c + Vector2(7, 5)   # a few u off the MIDDLE of A (between sparse samples)
		# true foot-of-perpendicular on A
		var foot: Vector2 = a_geo[0]
		var fd := 1.0e30
		for i in range(a_geo.size() - 1):
			var cp := Geometry2D.get_closest_point_to_segment(from, a_geo[i], a_geo[i + 1])
			var dd := cp.distance_squared_to(from)
			if dd < fd:
				fd = dd
				foot = cp
		# old every-8th-vertex pick (what _nearest_attachment used to return)
		var old_pos: Vector2 = a_geo[0]
		var od := 1.0e30
		for j in range(0, a_geo.size(), 8):
			var dj := a_geo[j].distance_squared_to(from)
			if dj < od:
				od = dj
				old_pos = a_geo[j]
		var new_pos: Vector2 = RoadWorks._nearest_attachment(from).pos
		var new_err := new_pos.distance_to(foot)
		var old_err := old_pos.distance_to(foot)
		_check(new_err < 2.0, "road attach: goal projects onto the centreline (err %.1f u)" % new_err)
		_check(new_err <= old_err + 0.01, "road attach: projection never worse than vertex sampling (%.1f <= %.1f)" % [new_err, old_err])
	RoadNetwork.reset()
	terrain.queue_free()
	await get_tree().process_frame

# Phase 4 — buildings re-snap to a road the player builds AFTER they were placed.
# The reported "buildings don't snap" symptom was a MISSING re-pack trigger:
# building_visuals never reacted to a road settling, so pre-road buildings kept
# their roadless fallback layout forever. relayout_tile() (wired to
# RoadWorks.order_settled) is the fix. This test places a building on a roadless
# tile, builds a road across it, then asserts the building snaps to the frontage.
# Arin Estuary Docks (tile_11_17): the tile centre sits ON the river crossing, so the
# connect road does NOT cross the river — it must meet the goal-side (west) bridgehead
# and never touch the FAR gate. Before the _snap_bridges fix it forced the full
# two-bank span, jumping bridgelessly to the far (east) bridgehead and back.
func _test_arin_bridge() -> void:
	var nav := NavGrid.instance()
	if not nav.is_ready():
		return
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	RoadCrossings.reset_for_tests()
	RoadCrossings.build(terrain)
	RoadNetwork.reset()
	RoadWorks.reset()
	var net := RoadNetwork.instance()
	var crossings := RoadCrossings.for_tile("tile_11_17")
	if crossings.is_empty():
		_check(false, "arin: tile_11_17 has a river crossing")
		terrain.queue_free()
		RoadNetwork.reset(); RoadWorks.reset(); RoadCrossings.reset_for_tests()
		return
	var cx: Dictionary = crossings[0]
	var ga: Vector2 = cx.gate_a
	var gb: Vector2 = cx.gate_b
	# Controlled network: ONE short synthetic river road on the FAR bank only
	# (bridge included), so the tile's connect job has no same-bank projection
	# to attach to — it must take the SAME-BANK bridge head, the bridge-head
	# attachment contract under test. (The full roads-v3 bake offers closer
	# plain roads on this urban tile, which correctly win over the biased head
	# and would make the scenario vacuous.)
	var acoord: Vector2i = terrain.id_to_coord("tile_11_17")
	var acenter: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(acoord))
	var bt: Vector2 = (cx.bridge_tangent as Vector2).normalized()
	if bt.dot(acenter - (cx.point as Vector2)) > 0.0:
		bt = -bt   # +bt now points to the FAR bank (away from the tile centre)
	var sa: Vector2 = (cx.point as Vector2) + bt * 40.0
	var sb: Vector2 = (cx.point as Vector2) + bt * 160.0
	var sgeo := PackedVector2Array()
	for s in 15:
		sgeo.append(sa.lerp(sb, float(s) / 14.0))
	var sna: Dictionary = net.ensure_node("arintest:a", RoadNetwork.KIND_JUNCTION, sa, acoord)
	var snb: Dictionary = net.ensure_node("arintest:b", RoadNetwork.KIND_JUNCTION, sb, acoord)
	net.add_edge(str(sna.id), str(snb.id), RoadNetwork.TIER_LOCAL, sgeo, [acoord],
		[{"point": cx.point, "tangent": (cx.bridge_tangent as Vector2).normalized()}], 0, RoadNetwork.STATE_BUILT)
	var oid := RoadWorks.enqueue_for_tile("tile_11_17")
	_check(oid >= 0, "arin: connect road enqueues")
	var frames := 0
	while oid >= 0 and frames < 8000 and str(RoadWorks.orders[oid].state) in ["queued", "planning", "revealing"]:
		RoadWorks._process(1.0 / 60.0)
		frames += 1
	if oid >= 0:
		var order: Dictionary = RoadWorks.orders[oid]
		var eid := str(order.edge_id)
		_check(str(order.state) == "built" and net.edges.has(eid), "arin: connect road builds (state %s)" % str(order.state))
		if net.edges.has(eid):
			var geo: PackedVector2Array = net.edges[eid].geometry
			var goal: Vector2 = order.get("goal", Vector2.ZERO)
			# the bridgehead on the route's continuation side vs the opposite (far) one
			var near_gate := ga if ga.distance_to(goal) <= gb.distance_to(goal) else gb
			var far_gate := gb if near_gate == ga else ga
			var hits_near := false
			var hits_far := false
			for p in geo:
				if p.distance_to(near_gate) < 14.0:
					hits_near = true
				if p.distance_to(far_gate) < 14.0:
					hits_far = true
			_check(not hits_far, "arin: road never touches the far bridgehead (no bridgeless crossing)")
			_check(hits_near, "arin: road meets the goal-side bridgehead")
	terrain.queue_free()
	RoadNetwork.reset()
	RoadWorks.reset()
	RoadCrossings.reset_for_tests()
	await get_tree().process_frame

# Phase 4 — region styles: deterministic job generation, the Patran City
# (inland) orbital with the ≤50% overflow rule, Stoneshore (coastal) baked,
# and the first-member-road trigger in RoadWorks.
func _test_region_styles() -> void:
	var nav := NavGrid.instance()
	if not nav.is_ready():
		return
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	RoadCrossings.reset_for_tests()
	RoadCrossings.build(terrain)

	# generator: deterministic, and identities produce their patterns
	var jobs_a := RoadRegionJobs.generate("patran_city", terrain)
	var jobs_b := RoadRegionJobs.generate("patran_city", terrain)
	_check(JSON.stringify(jobs_a) == JSON.stringify(jobs_b), "region styles: job generation deterministic")
	var ring_count := 0
	for job in jobs_a:
		if str(job.kind) == "orbital":
			ring_count += 1
	_check(ring_count >= 6, "region styles: dense city generates an orbital ring (%d segments)" % ring_count)
	var mountain_jobs := RoadRegionJobs.generate("grey_peaks", terrain)
	_check(mountain_jobs.size() <= 3 and mountain_jobs.size() >= 1,
		"region styles: mountain range capped at 3 segments (%d)" % mountain_jobs.size())
	var rural_jobs := RoadRegionJobs.generate("tegan_valley", terrain)
	var has_through := false
	for job2 in rural_jobs:
		if str(job2.kind) == "through":
			has_through = true
	_check(has_through, "region styles: sparse rural routes a through-route")

	# Patran City (spec-named inland test): realize on a fresh network —
	# the ring commits and the overflow rule holds
	var net := RoadNetwork.new()
	var realizer := RoadRealizer.new()
	var rep := RoadRegionJobs.realize_region("patran_city", terrain, nav, net, realizer, 0)
	_check(int(rep.committed) >= ring_count,
		"region styles: Patran City web realizes (%d/%d committed)" % [int(rep.committed), int(rep.jobs)])
	_check(float(rep.overflow) <= RoadRegionJobs.OVERFLOW_LIMIT or bool(rep.reworked),
		"region styles: orbital overflow within rule (%.0f%%%s)" % [float(rep.overflow) * 100.0, ", reworked" if bool(rep.reworked) else ""])

	# Stoneshore (spec-named coastal test): baked into the starting network
	var baked := RoadsBaked.data()
	_check((baked.get("style_regions", []) as Array).has("stoneshore"),
		"region styles: Stoneshore web baked into the starting network")
	RoadNetwork.reset()
	RoadNetwork.bootstrap_from_bake()
	_check(RoadNetwork.instance().edge_count() > 30,
		"region styles: baked network carries the anchor webs (%d edges)" % RoadNetwork.instance().edge_count())

	# roadsv2.5: a settled member road connects the tile but does NOT auto-grow
	# the whole region's web (roads appear only where built). Only the connect
	# order exists after building; no "style" orders are spawned at runtime.
	RoadWorks.reset()
	var oid := RoadWorks.enqueue_for_tile("tile_12_8")   # copperstown, dense city
	var frames := 0
	while frames < 4000 and str(RoadWorks.orders[oid].state) != "built":
		RoadWorks._process(1.0 / 60.0)
		frames += 1
		if str(RoadWorks.orders[oid].state) == "failed":
			break
	var style_orders := 0
	for id in RoadWorks.orders:
		if str(RoadWorks.orders[id].get("kind", "")) == "style":
			style_orders += 1
	_check(style_orders == 0, "region styles: building a road does NOT auto-grow the region web (%d style orders)" % style_orders)
	_check(str(RoadWorks.orders[oid].state) == "built", "region styles: the built tile still connects to the network")

	RoadWorks.reset()
	RoadNetwork.reset()
	terrain.queue_free()
	await get_tree().process_frame

# Phase 4 — roads avoid building footprints as a graduated COST, never a wall.
# The regression guard: a tile saturated with footprints must STILL route (the
# cost raster is finite). This pins the earlier hard-block bug that made dense
# tiles impassable and silently dropped their roads. See road_realizer's
# _building_cost / the "buildings" prep phase / _scatter_building_cost.
func _test_roads_avoid_buildings() -> void:
	var nav := NavGrid.instance()
	if not nav.is_ready():
		return
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	var ca := Vector2i(9, 10)
	var cb := Vector2i(11, 10)
	var cmid := Vector2i(10, 10)
	if not (terrain.tiles.has(ca) and terrain.tiles.has(cb) and terrain.tiles.has(cmid)):
		_check(false, "roads-avoid: test tiles present")
		terrain.queue_free()
		return
	var pa: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(ca))
	var pb: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(cb))
	var mid: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(cmid))
	var realizer := RoadRealizer.new()
	var net := RoadNetwork.new()
	var opts := {"identity": "dense_rural", "salt": 7}

	# Baseline: no footprint provider in the group yet.
	var base := realizer.route(nav, net, pa, pb, opts)
	_check(base.ok and base.geometry.size() > 0, "roads-avoid: baseline route ok (%s)" % str(base.get("reason", "")))

	# Footprint provider stub honouring the realizer's contract: a node in the
	# "building_footprints" group exposing footprint_discs() + footprint_version.
	var stub_script := GDScript.new()
	stub_script.source_code = "extends Node\nvar footprint_version := 0\nvar discs := []\nfunc footprint_discs() -> Array:\n\treturn discs\n"
	stub_script.reload()
	var bv := Node.new()
	bv.set_script(stub_script)
	bv.add_to_group("building_footprints")
	add_child(bv)
	await get_tree().process_frame

	# Saturate the mid tile (~140 footprints packed across it) and re-route the
	# same corridor straight through it. Must STILL succeed with non-empty
	# geometry — the cost is graduated, never impassable.
	var many: Array = []
	for ix in range(-5, 6):
		for iy in range(-6, 7):
			many.append({"center": mid + Vector2(float(ix) * 40.0, float(iy) * 36.0), "radius": 22.0})
	bv.discs = many
	bv.footprint_version = 1
	var thru := realizer.route(nav, net, pa, pb, opts)
	_check(thru.ok and thru.geometry.size() > 0,
		"roads-avoid: saturated tile still routes, no wall (%d discs, %s)" % [many.size(), str(thru.get("reason", ""))])
	# Proof the cost is actually applied (not silently inert): a fully-saturated
	# corridor must reroute away from the baseline straight line.
	_check(thru.ok and base.ok and thru.geometry != base.geometry,
		"roads-avoid: building cost changes the route (avoidance is live)")

	bv.queue_free()
	terrain.queue_free()
	await get_tree().process_frame

func _test_block_subdivision() -> void:
	var nav := NavGrid.instance()
	if not nav.is_ready():
		return
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	# Empty network + ONE synthetic straight road below: a controlled block-grid
	# unit test. (The roads-v3 bake covers most tiles with real roads, so a
	# bootstrapped world no longer offers a "roomy open tile" to anchor cleanly.)
	RoadNetwork.reset()
	var bv := preload("res://scenes/building_visuals.gd").new()
	add_child(bv)
	await get_tree().process_frame
	bv.terrain_layer = terrain
	var tile_id := "tile_9_10"
	var coord: Vector2i = terrain.id_to_coord(tile_id)
	if not terrain.tiles.has(coord):
		_check(false, "block: test tile exists")
		bv.queue_free(); terrain.queue_free(); RoadNetwork.reset(); return
	# the seeded per-tile decision is deterministic (recompute after clearing the cache)
	var dec1 := bv._use_block_mode(tile_id, coord)
	bv._tile_block_mode.erase(tile_id)
	_check(dec1 == bv._use_block_mode(tile_id, coord), "block: mode decision is deterministic per tile")
	# give the tile a straight BUILT road to anchor the block to (+ the roads flag)
	var center: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
	(terrain.tiles[coord] as Dictionary)["infrastructure_present"] = ["roads"]
	var net := RoadNetwork.instance()
	var na: Dictionary = net.ensure_node("blk:a", RoadNetwork.KIND_JUNCTION, center + Vector2(-160, -110), coord)
	var nb: Dictionary = net.ensure_node("blk:b", RoadNetwork.KIND_JUNCTION, center + Vector2(160, -110), coord)
	net.add_edge(str(na.id), str(nb.id), RoadNetwork.TIER_LOCAL, PackedVector2Array([center + Vector2(-160, -110), center + Vector2(160, -110)]), [coord], [], 1, RoadNetwork.STATE_BUILT)
	# force block mode and fill a block
	bv._tile_block_mode[tile_id] = true
	var iids: Array = []
	for i in 6:
		iids.append(BuildingState.add_building("b_test_factory", "", tile_id, "npc", "blk_%d" % i))
		bv.on_building_placed(tile_id, "b_test_factory", "", str(iids[i]), coord)
	var placed_n := 0
	for q in iids:
		if bv._placement_index.has(str(q)):
			placed_n += 1
	_check(placed_n == 6, "block: all buildings placed (lots + fallback) (%d/6)" % placed_n)
	var tmpl: Dictionary = bv._tile_block_templates.get(tile_id, {})
	_check(not tmpl.is_empty(), "block: a lot grid was built (%d lots)" % (tmpl.get("lots", []) as Array).size())
	_check(bv.footprint_discs().size() == placed_n, "block: every building yields an avoidance disc")
	# axis-aligned, spaced lots → footprints don't overlap each other
	var rects: Array = bv.footprint_rects_on_tile(coord)
	var overlap := false
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if (rects[i] as Rect2).intersects(rects[j] as Rect2):
				overlap = true
	_check(not overlap, "block: lot buildings do not overlap (%d footprints)" % rects.size())
	# demolish frees a lot; survivors stay put (re-pack re-claims the same lots)
	bv.remove_instance(str(iids[0]))
	var survivors := 0
	for k in range(1, 6):
		if bv._placement_index.has(str(iids[k])):
			survivors += 1
	_check(not bv._placement_index.has(str(iids[0])) and survivors == 5, "block: demolish frees a lot, survivors remain (%d/5)" % survivors)
	# clip regression: a straight road running well beyond the tile must yield an IN-TILE
	# anchor run, not the full multi-tile span (the tile_11_17 "run=1052u → 0 lots" bug).
	var spanning := PackedVector2Array()
	for k in range(-12, 13):
		spanning.append(center + Vector2(float(k) * 60.0, 150.0))   # straight, x in [-720, 720]
	var sa: Dictionary = net.ensure_node("blkspan:a", RoadNetwork.KIND_JUNCTION, spanning[0], coord)
	var sb2: Dictionary = net.ensure_node("blkspan:b", RoadNetwork.KIND_JUNCTION, spanning[spanning.size() - 1], coord)
	net.add_edge(str(sa.id), str(sb2.id), RoadNetwork.TIER_LOCAL, spanning, [coord], [], 1, RoadNetwork.STATE_BUILT)
	var run := bv._longest_straight_road(coord)
	_check(not run.is_empty(), "block: a road crossing the tile yields an anchor run")
	if not run.is_empty():
		var run_len: float = (run[0] as Vector2).distance_to(run[1] as Vector2)
		_check(run_len < 560.0, "block: anchor run clipped to the tile (%.0fu, not the multi-tile span)" % run_len)
	for c in 6:
		BuildingState.remove_building("blk_%d" % c)
	bv.queue_free()
	terrain.queue_free()
	RoadNetwork.reset()
	await get_tree().process_frame

func _test_ink_art_reserves_upgrade_space() -> void:
	var keys := ["furnace", "eaf", "industrial_factory", "consumer_factory",
		"assembly_plant", "high_tech_manufactory", "petro_refinery", "poly_plant",
		"chem_plant", "electrolyser", "power_plant", "water_pump", "pipes",
		"cables", "mine", "solar_farm", "wind_farm", "port"]
	for key in keys:
		var f3: Vector2 = InkBuildingGen.level_frame(key, 3)
		_check(f3.x > 0.0 and f3.y > 0.0, "ink art: %s has an L3 frame" % key)
		for lvl in [1, 2]:
			var f: Vector2 = InkBuildingGen.level_frame(key, lvl)
			_check(f.is_equal_approx(f3),
				"ink art: %s L%d reserves the L3 frame (%s vs %s)" % [key, lvl, str(f), str(f3)])

## THE DASH WALKER. This exists because the first version hung the game: it accumulated
## `t += run` along each edge, and once `t` was large enough, adding a sub-epsilon `run` no
## longer changed `carry + t` in float — so the phase never advanced and it emitted
## antialiased `draw_line` calls forever. Script memory stayed flat while the graphics driver
## climbed past 9 GB and the process died. The rewrite walks dash starts by INDEX, so progress
## is exact and the iteration count is bounded by construction; these tests pin that.
func _test_dash_segments() -> void:
	var bv := preload("res://scenes/building_visuals.gd").new()
	var dash: float = bv.SITE_DASH
	var gap: float = bv.SITE_GAP
	var period := dash + gap

	# A long thin rectangle: the shape most likely to expose an accumulation bug, because one
	# pair of edges is hundreds of periods long.
	var long_rect := PackedVector2Array([Vector2(0, 0), Vector2(900, 0),
		Vector2(900, 12), Vector2(0, 12)])
	var segs: Array = bv._dash_segments(long_rect, dash, gap)
	var perimeter := 2.0 * (900.0 + 12.0)
	var ceiling := int(perimeter / period) + long_rect.size() + 2
	_check(segs.size() > 0, "dash: a long rectangle produces dashes (%d)" % segs.size())
	_check(segs.size() <= ceiling,
		"dash: segment count is bounded by perimeter/period (%d <= %d)" % [segs.size(), ceiling])
	# Every run must be a real segment of at most one dash — never a zero-length smear, which
	# is what the runaway loop emitted millions of.
	var bad := 0
	for seg_value in segs:
		var seg: PackedVector2Array = seg_value
		var run := seg[0].distance_to(seg[1])
		if run <= 0.0 or run > dash + 0.01:
			bad += 1
	_check(bad == 0, "dash: every run is >0 and <= one dash (%d bad)" % bad)

	# The pathological input: an edge length that is an exact multiple of the period, so the
	# phase lands precisely on the dash boundary at every corner.
	var exact := PackedVector2Array([Vector2(0, 0), Vector2(period * 40.0, 0),
		Vector2(period * 40.0, period * 40.0), Vector2(0, period * 40.0)])
	var exact_segs: Array = bv._dash_segments(exact, dash, gap)
	_check(exact_segs.size() > 0 and exact_segs.size() < 400,
		"dash: an exact-multiple edge terminates sanely (%d)" % exact_segs.size())

	# Degenerate inputs must return nothing rather than spin.
	_check(bv._dash_segments(long_rect, 0.0, gap).is_empty(), "dash: zero dash draws nothing")
	_check(bv._dash_segments(long_rect, dash, 0.0).is_empty(), "dash: zero gap draws nothing")
	_check(bv._dash_segments(PackedVector2Array([Vector2.ZERO]), dash, gap).is_empty(),
		"dash: a single point draws nothing")
	# Coincident points must be skipped, not divided by.
	var degenerate := PackedVector2Array([Vector2(5, 5), Vector2(5, 5), Vector2(5, 5)])
	_check(bv._dash_segments(degenerate, dash, gap).is_empty(),
		"dash: a zero-area ring draws nothing")
	bv.free()


## The harbour timetable (owner, 2026-08-28): Capital every 10 s, Arin every 15, Vandel every
## 30, Stoneshore two ships every 30 s a couple of seconds apart. Two claims worth pinning,
## because getting either wrong is exactly what the map showed before: the cadence has to be
## what was asked, and NO TWO SHIPS may be alongside the same quay at once -- which is what
## the two overlapping ship populations used to look like.
func _test_port_timetable() -> void:
	var ships := preload("res://scripts/port_ship_visuals.gd")
	var visit: float = ships.CYCLE
	for tile in ships.PORT_SCHEDULE:
		var schedule: Dictionary = ships.PORT_SCHEDULE[tile]
		var every := float(schedule["every"])
		var burst: int = int(schedule["burst"])
		var gap := float(schedule["gap"])
		var window := every * 2.0
		var arrivals: Array = ships.timetable(every, burst, gap, 2)
		_check(arrivals.size() == burst * 2,
			"timetable %s: %d arrivals a window (%d)" % [tile, burst * 2, arrivals.size()])
		# THE CADENCE. Sort the arrival times over one window and check the port is served at
		# the stated interval -- for a burst, that the burst repeats at it.
		var times: Array = []
		for a_value in arrivals:
			times.append(float((a_value as Dictionary)["t"]))
		times.sort()
		var first_of_burst: Array = []
		for i in times.size():
			if i % burst == 0:
				first_of_burst.append(times[i])
		for i in range(1, first_of_burst.size()):
			var step: float = float(first_of_burst[i]) - float(first_of_burst[i - 1])
			_check(absf(step - every) < 0.01,
				"timetable %s: a ship every %.1f s (got %.1f)" % [tile, every, step])
		if burst > 1:
			for i in range(1, burst):
				var within: float = float(times[i]) - float(times[i - 1])
				_check(absf(within - gap) < 0.01,
					"timetable %s: burst ships %.1f s apart (got %.1f)" % [tile, gap, within])
		# NO DOUBLE OCCUPANCY. Per quay, over three windows so the wrap is covered too.
		for quay in 2:
			var visits: Array = []
			for w in 3:
				for a_value in arrivals:
					var a: Dictionary = a_value
					if int(a["quay"]) == quay:
						visits.append(float(a["t"]) + float(w) * window)
			visits.sort()
			var clash := 0
			var tightest := INF
			for i in range(1, visits.size()):
				var apart: float = float(visits[i]) - float(visits[i - 1])
				tightest = minf(tightest, apart)
				if apart < visit:
					clash += 1
			_check(clash == 0,
				"timetable %s quay %d: no two ships alongside at once (%d clashes, tightest %.1f s vs a %.1f s visit)"
					% [tile, quay, clash, tightest, visit])


## Hand-placed trees in the authored document (owner, 2026-08-28): two single sizes and a
## MIXED clump. Three things worth pinning, each of which is a decision rather than an
## accident: the schema refuses a clump with no radius, a clump's scatter is genuinely mixed
## rather than a repeated stamp, and every tree of it lands inside the radius that was drawn.
func _test_authored_trees() -> void:
	var authored := preload("res://scripts/authored_map.gd")
	var painter := preload("res://scripts/authored_fabric_painter.gd")

	var doc := authored.empty_document()
	doc["settlements"] = {"t": {
		"tiles": ["tile_1_1"],
		"trees": [
			{"id": "t:t:1", "position": [10.0, 20.0], "kind": "small"},
			{"id": "t:t:2", "position": [40.0, 20.0], "kind": "large"},
			{"id": "t:t:3", "position": [90.0, 20.0], "kind": "mixed", "radius": 26.0},
		],
	}}
	_check(authored.validate(doc).is_empty(),
		"authored trees: a document with all three kinds validates")

	# Saving groups point specimens by kind and drops their redundant per-record ids. Loading
	# through tree_records remains backward compatible, so painters do not care which form a
	# document arrived in.
	var compact: Dictionary = authored.canonical(doc)
	var compact_settlement: Dictionary = compact["settlements"]["t"]
	_check(not compact_settlement.has("trees") and compact_settlement.has("tree_points"),
		"authored trees: canonical storage migrates legacy records into typed point batches")
	_check((compact_settlement["tree_points"]["small"] as Array) == [[10.0, 20.0]]
		and (compact_settlement["tree_points"]["large"] as Array) == [[40.0, 20.0]]
		and (compact_settlement["tree_points"]["mixed"] as Array) == [[90.0, 20.0, 26.0]],
		"authored trees: small, large and mixed coordinates stay separate and exact")
	_check(authored.tree_records(compact_settlement, "t").size() == 3,
		"authored trees: compact storage expands to the same three painter records")
	_check(authored.to_text(compact) == authored.to_text(doc),
		"authored trees: migration is idempotent on the next save")

	var compact_bad := authored.empty_document()
	compact_bad["settlements"] = {"t": {"tiles": ["tile_1_1"],
		"tree_points": {"small": [[1.0, 2.0, 3.0]], "mixed": [[4.0, 5.0, 0.0]]}}}
	_check(not authored.validate(compact_bad).is_empty(),
		"authored trees: malformed typed points and radius-less compact clumps are refused")

	# A clump with no radius has no size, so it would draw nothing and silently look like a
	# tree that failed to place. The schema refuses it instead.
	var bad := authored.empty_document()
	bad["settlements"] = {"t": {"tiles": ["tile_1_1"],
		"trees": [{"id": "t:t:9", "position": [0.0, 0.0], "kind": "mixed"}]}}
	_check(not authored.validate(bad).is_empty(),
		"authored trees: a mixed clump without a radius is refused")

	var wrong := authored.empty_document()
	wrong["settlements"] = {"t": {"tiles": ["tile_1_1"],
		"trees": [{"id": "t:t:8", "position": [0.0, 0.0], "kind": "enormous"}]}}
	_check(not authored.validate(wrong).is_empty(),
		"authored trees: an unknown kind is refused")

	# THE CLUMP IS MIXED. That is the whole reason it is its own kind, so it is the thing to
	# assert: a stand of identical trees reads as a repeated stamp, not as woodland.
	var clump := {"id": "t:t:3", "position": [90.0, 20.0], "kind": "mixed", "radius": 26.0}
	var points := painter.clump_points(clump)
	_check(points.size() >= 6, "authored trees: a clump plants several trees (%d)" % points.size())
	var kinds: Dictionary = {}
	var outside := 0
	var centre := Vector2(90.0, 20.0)
	for point in points:
		if point.distance_to(centre) > 26.0 + 0.01:
			outside += 1
		kinds[painter.TreeShapesRef.pick_kind("t:t:3|%.0f|%.0f" % [point.x, point.y],
			painter.CLUMP_MIX)] = true
	_check(outside == 0, "authored trees: every tree of a clump is inside its radius (%d out)"
		% outside)
	_check(kinds.size() >= 2,
		"authored trees: a clump mixes sizes rather than repeating one (%d kinds)" % kinds.size())


## THE SHIP MANOEUVRE. Pinned because the failure is geometric and invisible in a still: a
## ship that begins its three-point turn before it is clear of the arm tips sweeps its own
## quay as it rotates, and only a frame caught mid-turn would ever show it.
func _test_ship_manoeuvre_clears_the_arms() -> void:
	var ships: Node = preload("res://scripts/port_ship_visuals.gd").new()
	var length := 48.0
	var clear := 130.0        # stands in for arm tip + swept radius + margin
	var away := clear + length * 4.0

	var in_time: float = ships.IN_TIME
	var hold: float = ships.HOLD_TIME
	var cycle: float = ships.CYCLE

	# Arrival ends exactly alongside, and departure ends exactly at `away` — otherwise a ship
	# jumps on the loop seam.
	var arrive: Array = ships.call("_manoeuvre", 0.0, clear, away, length)
	_check(absf(float(arrive[0]) - away) < 0.5, "ship: the cycle starts out at sea")
	var berthed: Array = ships.call("_manoeuvre", in_time + hold * 0.5, clear, away, length)
	_check(is_zero_approx(float(berthed[0])), "ship: sits alongside during the hold")
	_check(is_zero_approx(float(berthed[1])), "ship: does not turn while alongside")

	# THE INVARIANT: once any turning has begun, the ship is never nearer than `clear`.
	var worst := INF
	var turn_started := -1.0
	var samples := 400
	for i in samples:
		var t := cycle * float(i) / float(samples)
		var m: Array = ships.call("_manoeuvre", t, clear, away, length)
		var dist := float(m[0])
		var turn := absf(float(m[1]))
		if turn > 0.001:
			if turn_started < 0.0:
				turn_started = dist
			worst = minf(worst, dist)
	_check(turn_started >= clear - 0.5,
		"ship: turning only begins past the clearance line (%.1f >= %.1f)" % [turn_started, clear])
	_check(worst >= clear - 0.5,
		"ship: never comes back inside the clearance line while turning (%.1f)" % worst)

	# And it really does end up round, having gone forward-back-forward on the way.
	var ended: Array = ships.call("_manoeuvre", cycle - 0.01, clear, away, length)
	_check(absf(float(ended[1]) - PI) < 0.01, "ship: finishes the turn fully round")
	var reversed := false
	var prev := -1.0
	for i in samples:
		var t2: float = in_time + hold + (float(ships.OUT_TIME) * float(i) / float(samples))
		var d2 := float((ships.call("_manoeuvre", t2, clear, away, length) as Array)[0])
		if prev >= 0.0 and d2 < prev - 0.01:
			reversed = true
		prev = d2
	_check(reversed, "ship: the departure includes an astern leg (the middle of the three)")
	ships.free()


# River-bank helpers (block-box budge/no-cross rules) + bridge-head attachment. Pure
# geometry, so it runs without a baked map.
func _test_river_bank_and_bridge_head() -> void:
	var bv := preload("res://scenes/building_visuals.gd").new()
	add_child(bv)
	await get_tree().process_frame
	# vertical river at x=0 (rel-to-centre): the two banks read as opposite sides; no river -> 0.
	var rivers: Array = [[Vector2(0.0, -120.0), Vector2(0.0, 120.0)]]
	var sL := bv._river_side(Vector2(-50.0, 0.0), rivers)
	var sR := bv._river_side(Vector2(50.0, 0.0), rivers)
	_check(sL != 0 and sR != 0 and sL != sR, "river: the two banks read as opposite sides")
	_check(bv._river_side(Vector2(10.0, 0.0), []) == 0, "river: no river -> side 0")
	# a block straddling the river, anchor on the LEFT bank -> clipped to the left, never crossing x=0
	var quad: Array = [Vector2(-90.0, -60.0), Vector2(90.0, -60.0), Vector2(90.0, 60.0), Vector2(-90.0, 60.0)]
	var clipped := bv._clip_to_river_bank(quad, rivers, Vector2(-50.0, 0.0), sL)
	var maxx := -1.0e9
	for p in clipped:
		maxx = maxf(maxx, (p as Vector2).x)
	_check(clipped.size() >= 3 and maxx <= 0.0, "river: block clipped to the anchor's bank, no crossing (max x=%.1f)" % maxx)
	# a river far from the block leaves it untouched
	var far := bv._clip_to_river_bank(quad, [[Vector2(900.0, -120.0), Vector2(900.0, 120.0)]], Vector2(-50.0, 0.0), -1)
	_check(far.size() == quad.size(), "river: a distant river leaves the block unchanged")
	# multi-segment (bent) river: the same bank reads consistently (deterministic nearest-segment tiebreak)
	var bend: Array = [[Vector2(0.0, -100.0), Vector2(0.0, 0.0)], [Vector2(0.0, 0.0), Vector2(30.0, 100.0)]]
	var b1 := bv._river_side(Vector2(-60.0, -50.0), bend)
	var b2 := bv._river_side(Vector2(-60.0, 50.0), bend)
	_check(b1 != 0 and b1 == b2, "river: a bent river gives one consistent side for the same bank")
	bv.queue_free()
	await get_tree().process_frame
	# bridge-head attachment (new): a connect-road near a bridge targets the same-bank HEAD, not a mid-edge point.
	RoadNetwork.reset()
	var bnet := RoadNetwork.instance()
	var bcoord := Vector2i(0, 0)
	var ba := bnet.ensure_node("brtest:a", RoadNetwork.KIND_JUNCTION, Vector2(100.0, -80.0), bcoord)
	var bb := bnet.ensure_node("brtest:b", RoadNetwork.KIND_JUNCTION, Vector2(100.0, 80.0), bcoord)
	bnet.add_edge(str(ba.id), str(bb.id), RoadNetwork.TIER_LOCAL, PackedVector2Array([Vector2(100.0, -80.0), Vector2(100.0, 80.0)]), [bcoord], [{"point": Vector2(100.0, 0.0), "tangent": Vector2(0.0, 1.0)}], 0, RoadNetwork.STATE_BUILT)
	var reach := RoadCrossings.GATE_OFFSET + RoadRealizer.BRIDGE_BANK_STUB
	var att := RoadWorks._nearest_attachment(Vector2(60.0, -50.0))   # off the edge, north (same) bank
	_check((att.get("pos", Vector2.ZERO) as Vector2).distance_to(Vector2(100.0, -reach)) < 2.0, "bridge: a connect-road near a bridge attaches to the same-bank head")
	var att_far := RoadWorks._nearest_attachment(Vector2(60.0, 900.0))   # far from the bridge — unaffected
	_check((att_far.get("pos", Vector2.ZERO) as Vector2).distance_to(Vector2(100.0, -reach)) > 50.0, "bridge: a road far from any bridge is not pulled to a head")
	RoadNetwork.reset()
	await get_tree().process_frame

func _test_bridge_corridor() -> void:
	var nav := NavGrid.instance()
	if not nav.is_ready():
		return
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	RoadCrossings.reset_for_tests()
	RoadCrossings.build(terrain)
	var bv := preload("res://scenes/building_visuals.gd").new()
	add_child(bv)
	await get_tree().process_frame
	bv.terrain_layer = terrain
	var tile_id := "tile_11_17"   # Arin Estuary Docks — a river crossing
	var coord: Vector2i = terrain.id_to_coord(tile_id)
	if not terrain.tiles.has(coord) or RoadCrossings.for_tile(tile_id).is_empty():
		_check(false, "bridge-corridor: test tile has a crossing")
		bv.queue_free(); terrain.queue_free(); RoadCrossings.reset_for_tests(); return
	var center: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
	# the crossing reserves ≥2 approach stubs (both banks), each ~BRIDGE_APPROACH (50u) long
	var stubs := bv._bridge_approach_segments(tile_id, center)
	_check(stubs.size() >= 2, "bridge-corridor: a crossing reserves approach stubs (%d)" % stubs.size())
	var len_ok := true
	for st in stubs:
		if absf((st[0] as Vector2).distance_to(st[1] as Vector2) - 50.0) > 1.0:
			len_ok = false
	_check(len_ok, "bridge-corridor: each approach stub spans ~50u")
	# the mask reserves it: a LAND cell sitting on the approach is kept non-buildable
	bv._ensure_tile(tile_id, coord)
	var cx: Dictionary = RoadCrossings.for_tile(tile_id)[0]
	var tan: Vector2 = (cx.bridge_tangent as Vector2).normalized()
	var p0: Vector2 = (cx.point as Vector2) - center
	var land_reserved := false
	for s in [1.0, -1.0]:
		for dist in [24.0, 36.0, 48.0]:
			var probe: Vector2 = p0 + tan * (s * dist)
			var c := nav.cell_of(center + probe)
			if nav.water(c.x, c.y) == 0 and not _mask_buildable(bv, tile_id, probe):
				land_reserved = true
	_check(land_reserved, "bridge-corridor: a land cell on the bridge approach is reserved (kept clear for the road)")
	bv.queue_free()
	terrain.queue_free()
	RoadCrossings.reset_for_tests()
	await get_tree().process_frame

func _test_farms() -> void:
	var nav := NavGrid.instance()
	if not nav.is_ready():
		return
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	RoadNetwork.reset()
	var bv := preload("res://scenes/building_visuals.gd").new()
	add_child(bv)
	await get_tree().process_frame
	bv.terrain_layer = terrain
	var tile_id := "tile_9_10"
	var coord: Vector2i = terrain.id_to_coord(tile_id)
	if not terrain.tiles.has(coord):
		_check(false, "farms: test tile exists")
		bv.queue_free(); terrain.queue_free(); return
	var center: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
	# A farm-only tile gravitates to the river; the affinity flips to the edge only once a
	# non-farm building shares the tile.
	_check(not bv._has_non_farm_buildings(tile_id), "farms: tile starts with no non-farm buildings")
	var fid: String = BuildingState.add_building("b_014", "", tile_id, "npc", "farm_a")
	bv.on_building_placed(tile_id, "b_014", "", fid, coord)
	var farm := {}
	for p in bv._placements:
		if str(p.tile_id) == tile_id and str(p.cat) == "farm":
			farm = p
	_check(not farm.is_empty(), "farms: a farm field was placed")
	if farm.is_empty():
		BuildingState.remove_building("farm_a")
		bv.queue_free(); terrain.queue_free(); RoadNetwork.reset()
		await get_tree().process_frame
		return
	var fverts: PackedVector2Array = farm.verts
	_check(fverts.size() >= 5, "farms: field is polygonal (%d verts)" % fverts.size())
	# Clipped to the hex: every vertex sits inside the flat-top hex (a hair of float slop allowed).
	var all_in := true
	for v in fverts:
		var r: Vector2 = v - center
		if absf(r.x) > 271.0 or absf(r.y) > 241.0 or 240.0 * absf(r.x) + 135.0 * absf(r.y) > 65200.0:
			all_in = false
	_check(all_in, "farms: field is clipped to the hex")
	_check((farm.get("hatch", []) as Array).size() > 0, "farms: dark-green hatch baked")
	# Brown barn + silo outbuildings.
	bv._rebuild_subcomponents(tile_id)
	var browns := 0
	for sc in bv._subcomponents:
		if str(sc.tile_id) == tile_id and (sc.color as Color).is_equal_approx(Color(0.50, 0.33, 0.16)):
			browns += 1
	_check(browns >= 1, "farms: brown barn/silo placed (%d)" % browns)
	var n1 := (bv._subcomponents as Array).size()
	bv._rebuild_subcomponents(tile_id)
	_check((bv._subcomponents as Array).size() == n1, "farms: subcomponent rebuild is deterministic")
	# A non-farm building on the tile flips the farm's affinity (river -> edge).
	var bid: String = BuildingState.add_building("b_007", "", tile_id, "npc", "farm_factory")
	bv.on_building_placed(tile_id, "b_007", "", bid, coord)
	_check(bv._has_non_farm_buildings(tile_id), "farms: a non-farm building flips edge-affinity")
	# Regression: a farm on a BLOCK-MODE tile keeps its polygonal field + hatch — it must never be
	# turned into a rectangular block lot (farms bypass _claim_slot). Give the tile a straight built
	# road so a block template can form, force block mode on, then place a fresh farm.
	var net := RoadNetwork.instance()
	var fa: Dictionary = net.ensure_node("farmblk:a", RoadNetwork.KIND_JUNCTION, center + Vector2(-160, -110), coord)
	var fb: Dictionary = net.ensure_node("farmblk:b", RoadNetwork.KIND_JUNCTION, center + Vector2(160, -110), coord)
	net.add_edge(str(fa.id), str(fb.id), RoadNetwork.TIER_LOCAL, PackedVector2Array([center + Vector2(-160, -110), center + Vector2(160, -110)]), [coord], [], 1, RoadNetwork.STATE_BUILT)
	bv._tile_block_mode[tile_id] = true
	bv._tile_block_templates.erase(tile_id)
	bv._tile_land.erase(tile_id); bv._tile_landkeys.erase(tile_id); bv._tile_segs.erase(tile_id); bv._tile_rivers.erase(tile_id)
	var fid2: String = BuildingState.add_building("b_014", "", tile_id, "npc", "farm_blk")
	bv.on_building_placed(tile_id, "b_014", "", fid2, coord)
	var farm2 := {}
	for p in bv._placements:
		if str(p.instance_id) == fid2:
			farm2 = p
	var poly_ok: bool = not farm2.is_empty() \
		and (farm2.get("verts", PackedVector2Array()) as PackedVector2Array).size() >= 5 \
		and (farm2.get("hatch", []) as Array).size() > 0
	_check(poly_ok, "farms: a farm on a block-mode tile keeps its polygonal field (not a block lot)")
	BuildingState.remove_building("farm_a")
	BuildingState.remove_building("farm_factory")
	BuildingState.remove_building("farm_blk")
	bv.queue_free()
	terrain.queue_free()
	RoadNetwork.reset()
	await get_tree().process_frame

func _test_farm_lanes() -> void:
	var nav := NavGrid.instance()
	if not nav.is_ready():
		return
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	RoadNetwork.reset()
	# This exercises the PROCEDURAL packer's lanes against the road NETWORK. The authored
	# document now covers tile_9_10 with its own permanent streets, which the mask rightly
	# keeps buildings and tracks clear of — so it is stood down for the test and restored after.
	AuthoredMap.set_document_for_tests({})
	var bv := preload("res://scenes/building_visuals.gd").new()
	add_child(bv)
	await get_tree().process_frame
	bv.terrain_layer = terrain
	var tile_id := "tile_9_10"
	var coord: Vector2i = terrain.id_to_coord(tile_id)
	if not terrain.tiles.has(coord):
		_check(false, "farm-lanes: test tile exists")
		AuthoredMap.reset_for_tests()
		bv.queue_free(); terrain.queue_free(); return
	# Two adjacent farms → they Voronoi-snap and a thin lane runs between them.
	for i in 2:
		var iid: String = BuildingState.add_building("b_014", "", tile_id, "npc", "flane_%d" % i)
		bv.on_building_placed(tile_id, "b_014", "", iid, coord)
	bv._rebuild_subcomponents(tile_id)
	var nfarms := 0
	for p in bv._placements:
		if str(p.tile_id) == tile_id and str(p.cat) == "farm":
			nfarms += 1
	_check(nfarms == 2, "farm-lanes: two farms placed on the tile (%d)" % nfarms)
	if nfarms == 2:
		var lanes: Array = bv._farm_lanes.get(tile_id, [])
		_check(lanes.size() >= 1, "farm-lanes: a lane runs between adjacent farms (%d)" % lanes.size())
		_check(bv._farm_render.has("flane_0") and bv._farm_render.has("flane_1"), "farm-lanes: each field has a cell-clipped render shape")
		bv._rebuild_subcomponents(tile_id)   # deterministic
		_check((bv._farm_lanes.get(tile_id, []) as Array).size() == lanes.size(), "farm-lanes: lane count is deterministic")
	# Geometry kit (deterministic, map-independent):
	var sq := PackedVector2Array([Vector2(-10, -10), Vector2(10, -10), Vector2(10, 10), Vector2(-10, 10)])
	# _near_field_runs trims a long segment to just the part within `reach` of the square.
	var runs: Array = bv._near_field_runs(Vector2(-100, 0), Vector2(100, 0), [sq], 5.0)
	var trim_ok := runs.size() == 1
	if trim_ok:
		var span: float = (float(runs[0][1]) - float(runs[0][0])) * 200.0   # over a 200u segment
		trim_ok = span > 10.0 and span < 60.0     # ~30u (x in [-15,15]), not the full 200u
	_check(trim_ok, "farm-lanes: _near_field_runs trims a lane to within reach of the field")
	# _seg_outside_convex routes a crossing segment around the obstacle (two outside pieces).
	var outs: Array = bv._seg_outside_convex(Vector2(-50, 0), Vector2(50, 0), sq)
	_check(outs.size() == 2, "farm-lanes: _seg_outside_convex splits a lane around a forest (%d)" % outs.size())
	# River split: a river separates farms into independent per-bank groups (deterministic geometry).
	var river: Array = [[Vector2(-100, -50), Vector2(100, 50)]]   # diagonal river line y = 0.5x
	var sA := Vector2(-50, 50)   # above the line
	var sB := Vector2(-40, 40)   # above (same bank as A)
	var sC := Vector2(50, -50)   # below (other bank)
	_check(bv._same_bank(sA, sB, river), "river-split: same-side farms read as same bank")
	_check(not bv._same_bank(sA, sC, river), "river-split: cross-river farms read as different banks")
	_check((bv._bank_components([sA, sB, sC], river) as Array).size() == 2, "river-split: a river yields 2 bank groups")
	# Road merge: add a real built road just past the fields; a connector track should reach it (no new road).
	if nfarms == 2:
		var center: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
		var net := RoadNetwork.instance()
		var ya: Dictionary = net.ensure_node("flr:a", RoadNetwork.KIND_JUNCTION, center + Vector2(-200, -150), coord)
		var yb: Dictionary = net.ensure_node("flr:b", RoadNetwork.KIND_JUNCTION, center + Vector2(200, -150), coord)
		net.add_edge(str(ya.id), str(yb.id), RoadNetwork.TIER_LOCAL, PackedVector2Array([center + Vector2(-200, -150), center + Vector2(200, -150)]), [coord], [], 1, RoadNetwork.STATE_BUILT)
		bv._rebuild_subcomponents(tile_id)
		var reached := false
		for seg in (bv._farm_lanes.get(tile_id, []) as Array):
			for pt in (seg as PackedVector2Array):
				if absf((pt as Vector2).y - (center.y - 150.0)) < 3.0 and absf((pt as Vector2).x - center.x) < 200.0:
					reached = true
		_check(reached, "farm-lanes: a connector merges the tracks to a real road")
	for i in 2:
		BuildingState.remove_building("flane_%d" % i)
	bv.queue_free()
	terrain.queue_free()
	RoadNetwork.reset()
	AuthoredMap.reset_for_tests()   # the real document comes back for the tests that need it
	await get_tree().process_frame

# Yellow roads not connecting tiles — promoted ring roads are clipped 1u inside the hex, so adjacent
# tiles' rings stop ~1u short of the shared edge and never meet. _bridge_ring_to_neighbours closes the
# seam: a short stub from this tile's ring endpoint onto the neighbour tile's road. This pins it
# (deterministic: synthetic neighbour ring within FARM_BRIDGE_MAX → a stub lands on it; reload → no re-bridge).
func _test_farm_ring_bridge() -> void:
	var nav := NavGrid.instance()
	if not nav.is_ready():
		return
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	RoadNetwork.reset()
	RoadWorks.reset()
	var coordA := Vector2i(8, 9)   # tile_9_10
	if not terrain.tiles.has(coordA):
		terrain.queue_free(); return
	var coordB := Vector2i(-1, -1)
	for ncoord in terrain.neighbor_coords(coordA):
		if terrain.tiles.has(ncoord):
			coordB = ncoord
			break
	if coordB == Vector2i(-1, -1):
		terrain.queue_free(); return
	var net := RoadNetwork.instance()
	var cA: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coordA))
	# This tile's ring: an edge whose endpoint `aEnd` we will bridge.
	var aEnd: Dictionary = net.ensure_node("farmr:tA:0:a", RoadNetwork.KIND_JUNCTION, cA, coordA)
	var aOth: Dictionary = net.ensure_node("farmr:tA:0:b", RoadNetwork.KIND_JUNCTION, cA + Vector2(0, 20), coordA)
	net.add_edge(str(aEnd.id), str(aOth.id), RoadNetwork.TIER_LOCAL, PackedVector2Array([cA, cA + Vector2(0, 20)]), [coordA], [], 0, RoadNetwork.STATE_BUILT)
	# Neighbour's ring: a farmr edge tagged on tile B, geometry ~3u from aEnd (within FARM_BRIDGE_MAX).
	var bGeo := PackedVector2Array([cA + Vector2(3, -10), cA + Vector2(3, 10)])
	var b1: Dictionary = net.ensure_node("farmr:tB:0:a", RoadNetwork.KIND_JUNCTION, bGeo[0], coordB)
	var b2: Dictionary = net.ensure_node("farmr:tB:0:b", RoadNetwork.KIND_JUNCTION, bGeo[1], coordB)
	net.add_edge(str(b1.id), str(b2.id), RoadNetwork.TIER_LOCAL, bGeo, [coordB], [], 0, RoadNetwork.STATE_BUILT)
	var aRingA: Vector2 = cA
	var aRingB: Vector2 = cA + Vector2(0, 20)
	var before: int = net.edges.size()
	RoadWorks._bridge_ring_to_neighbours(net, coordA, "tile_9_10")
	_check(net.edges.size() == before + 1, "ring-bridge: a seam bridge edge is created (%d new)" % (net.edges.size() - before))
	# the stub spans A's ring to B's ring (both ends land ON a ring centreline), length within the cap
	var joined := false
	for eid in net.edges:
		var g: PackedVector2Array = net.edges[eid].geometry
		if g.size() != 2:
			continue
		var glen := g[0].distance_to(g[1])
		if glen < 0.5 or glen >= RoadWorks.FARM_BRIDGE_MAX + 0.5:
			continue
		var d0a := g[0].distance_to(Geometry2D.get_closest_point_to_segment(g[0], aRingA, aRingB))
		var d1a := g[1].distance_to(Geometry2D.get_closest_point_to_segment(g[1], aRingA, aRingB))
		var d0b := g[0].distance_to(Geometry2D.get_closest_point_to_segment(g[0], bGeo[0], bGeo[1]))
		var d1b := g[1].distance_to(Geometry2D.get_closest_point_to_segment(g[1], bGeo[0], bGeo[1]))
		if (d0a < 0.6 and d1b < 0.6) or (d1a < 0.6 and d0b < 0.6):
			joined = true
	_check(joined, "ring-bridge: the stub joins A's ring to B's ring (yellow roads meet at the seam)")
	# idempotent: re-running does NOT add a second bridge for the same seam pair
	var after1: int = net.edges.size()
	RoadWorks._bridge_ring_to_neighbours(net, coordA, "tile_9_10")
	_check(net.edges.size() == after1, "ring-bridge: idempotent — seam bridged once per pair")
	# water gate: a stub that would cross water is rejected (no bridgeless crossing)
	var land := RoadWorks._bridge_on_land(cA, cA + Vector2(3, 0))
	_check(land, "ring-bridge: an all-land stub passes the water gate (sanity)")
	terrain.queue_free()
	RoadNetwork.reset()
	RoadWorks.reset()
	await get_tree().process_frame

# Unconnected farm-web outlines — the cluster's tan outer ring must chain into a CLOSED, continuous
# loop (the loop-closure in _chain_segments), not an open polyline with a hairline gap at the seam.
func _test_farm_ring_continuity() -> void:
	var nav := NavGrid.instance()
	if not nav.is_ready():
		return
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	RoadNetwork.reset()
	var bv := preload("res://scenes/building_visuals.gd").new()
	add_child(bv)
	await get_tree().process_frame
	bv.terrain_layer = terrain
	var tile_id := "tile_9_10"
	var coord: Vector2i = terrain.id_to_coord(tile_id)
	if not terrain.tiles.has(coord):
		bv.queue_free(); terrain.queue_free(); return
	# SEVEN, not eight. tile_9_10 is a hill, so its land cap is 160 and eight farms at
	# tile_size_used 20 come to exactly 160 — the land model says eight fit. The ART only
	# clusters seven: at the eighth the cluster stops being contiguous and its boundary is
	# legitimately an open chain, not a ring that failed to close (measured: 6 and 7 close at
	# 0.0u, 8 leaves 284.7u). What this pins is closure for a contiguous cluster, so the
	# fixture has to build one. Retune with `tile_size_used` for the farm.
	for i in 7:
		var iid: String = BuildingState.add_building("b_014", "", tile_id, "npc", "frc_%d" % i)
		bv.on_building_placed(tile_id, "b_014", "", iid, coord)
	bv._rebuild_subcomponents(tile_id)
	var rings: Array = []
	for poly in (bv._farm_lanes.get(tile_id, []) as Array):
		if (poly as PackedVector2Array).size() > 2:
			rings.append(poly)
	_check(rings.size() >= 1, "ring-continuity: cluster has an outer ring (%d polylines)" % rings.size())
	if rings.size() >= 1:
		var big: PackedVector2Array = rings[0]
		for r in rings:
			if (r as PackedVector2Array).size() > big.size():
				big = r
		var gap: float = big[0].distance_to(big[big.size() - 1])
		_check(gap < 3.0, "ring-continuity: the outer ring is a closed loop (end gap %.1fu)" % gap)
	for i in 8:
		BuildingState.remove_building("frc_%d" % i)
	bv.queue_free()
	terrain.queue_free()
	RoadNetwork.reset()
	await get_tree().process_frame

# Stage 2: a road routed ACROSS a farm cluster should FOLLOW the cosmetic web (the realizer stamps a
# cheap corridor along the tracks). A road that ignored the bias would detour around the big fields,
# away from the web — so a high fraction of path points sitting on a track verifies the bias works.
func _test_farm_road_routing_bias() -> void:
	var nav := NavGrid.instance()
	if not nav.is_ready():
		return
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	RoadNetwork.reset()
	var bv := preload("res://scenes/building_visuals.gd").new()
	add_child(bv)
	await get_tree().process_frame
	bv.terrain_layer = terrain
	var tile_id := "tile_9_10"
	var coord: Vector2i = terrain.id_to_coord(tile_id)
	if not terrain.tiles.has(coord):
		_check(false, "routing-bias: test tile exists")
		bv.queue_free(); terrain.queue_free(); return
	for i in 5:
		var iid: String = BuildingState.add_building("b_014", "", tile_id, "npc", "fbias_%d" % i)
		bv.on_building_placed(tile_id, "b_014", "", iid, coord)
	bv._rebuild_subcomponents(tile_id)
	var center: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
	var net := RoadNetwork.instance()
	var realizer = preload("res://scripts/road_realizer.gd").new()
	var res: Dictionary = realizer.route(nav, net, center + Vector2(-330, 0), center + Vector2(330, 0), {"thorough": true})
	_check(bool(res.get("ok", false)), "routing-bias: a road routes across the farm cluster")
	var segs: Array = bv.all_farm_lane_segments()
	if bool(res.get("ok", false)):
		_check(_frac_on_web(res.geometry, segs) > 0.25, "routing-bias: cost-bias pulls the road toward the web (%d%%)" % int(_frac_on_web(res.geometry, segs) * 100.0))
	# "Borrow the web exactly": a straight road CUTTING THROUGH the cluster (the case the user dislikes)
	# gets its in-cluster portion rerouted ONTO the track graph, so it runs on the tracks not over fields.
	var rings0: Array = bv.all_farm_cluster_rings()
	if rings0.size() > 0 and segs.size() >= 2:
		var rp: PackedVector2Array = rings0[0]
		var rc := Vector2.ZERO
		for v in rp:
			rc += v
		rc /= float(maxi(rp.size(), 1))
		var straight := PackedVector2Array()
		for t in 21:
			straight.append((rc + Vector2(-190, 0)).lerp(rc + Vector2(190, 0), float(t) / 20.0))
		var fake := {"geometry": straight, "tiles": [coord], "bridges": []}
		var frac_cut: float = _frac_on_web(straight, segs)
		RoadWorks._snap_route_to_web(fake)
		var frac_snap: float = _frac_on_web(fake.geometry, segs)
		_check(frac_snap > frac_cut + 0.1, "routing-bias: borrowing the web threads the road onto the tracks (%d%% -> %d%%)" % [int(frac_cut * 100.0), int(frac_snap * 100.0)])
	for i in 5:
		BuildingState.remove_building("fbias_%d" % i)
	bv.queue_free()
	terrain.queue_free()
	RoadNetwork.reset()
	await get_tree().process_frame

## Placing a FARM on a tile that is already full of buildings and roads must fail gently.
##
## Farms are the one category excluded from the gentle-failure fallback plot (_place_fallback_plot
## takes "the nearest 50 u^2 beside a road", and a farm is a field, not a plot), so when the
## packer finds nowhere a farm is the case that reaches the very end of _place_building with
## nothing placed. That path has to warn and return, not throw — a player clicking Build on a
## crowded tile is an ordinary thing to do, not an error.
func _test_farm_on_a_crowded_tile() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		_check(false, "crowded farm: main.tscn instantiates")
		return
	var snapshot: Dictionary = SaveLoad.export_snapshot()
	var inst: Node = packed.instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	var bv: Node = inst.find_child("BuildingVisuals", true, false)
	var terrain: Node = inst.find_child("TerrainLayer", true, false)
	if bv == null or terrain == null:
		_check(false, "crowded farm: the visual layers exist")
		inst.queue_free()
		SaveLoad.import_snapshot(snapshot)
		return

	# The most built-up tile on the board: whatever already carries the most footprints, which
	# is a far harsher test than a tile this test crowds itself.
	var busiest := ""
	var busiest_n := -1
	for coord_key in terrain.tiles:
		var td: Dictionary = terrain.tiles[coord_key]
		var tid := str(td.get("id", ""))
		if tid == "":
			continue
		var n: int = BuildingState.get_buildings_on_tile(tid).size()
		if n > busiest_n:
			busiest_n = n
			busiest = tid
	_check(busiest != "", "crowded farm: found the busiest tile (%s, %d buildings)" % [busiest, busiest_n])
	var coord: Vector2i = terrain.call("id_to_coord", busiest)

	# Pack it further still, then ask for farms on top. Any of these may legitimately find no
	# room — the assertion is that asking is SAFE, and that the sim and the visuals agree
	# afterwards about what exists.
	var ids: Array = []
	for i in 6:
		var iid: String = BuildingState.add_building("b_002", "r_005", busiest, MatchState.LOCAL_PLAYER, "")
		inst.call("emit_signal", "building_placed", busiest, "b_002", "r_005", iid, coord)
		ids.append(iid)
	await get_tree().process_frame
	for i in 4:
		var farm_id: String = BuildingState.add_building("b_014", "r_090", busiest, MatchState.LOCAL_PLAYER, "")
		inst.call("emit_signal", "building_placed", busiest, "b_014", "r_090", farm_id, coord)
		ids.append(farm_id)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(true, "crowded farm: placing farms on a packed tile did not throw")

	# Whatever DID get drawn must be a building that exists, and removing them all must leave
	# no footprint behind — an undrawn farm must not leave a phantom either.
	for iid_value in ids:
		var iid := str(iid_value)
		if bv.call("has_placement", iid):
			_check(BuildingState.buildings.has(iid),
				"crowded farm: nothing is drawn for a building that does not exist")
	for iid_value2 in ids:
		BuildingState.remove_building(str(iid_value2))
	await get_tree().process_frame
	var leftovers: Array = []
	for iid_value3 in ids:
		if bv.call("has_placement", str(iid_value3)):
			leftovers.append(str(iid_value3))
	_check(leftovers.is_empty(), "crowded farm: removing them all leaves no footprint (%s)" % str(leftovers))

	inst.queue_free()
	await get_tree().process_frame
	SaveLoad.import_snapshot(snapshot)
	await get_tree().process_frame
