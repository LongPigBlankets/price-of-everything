class_name UrbanFabricVisuals
extends Node2D
## Deterministic, draw-only inhabited fabric for the optional mid-century map.
##
## The layer derives quiet terraces, courtyard blocks, alleys, open lots and
## parks from urban tile classification plus the BUILT road geometry. It owns
## no simulation objects and creates no per-building nodes. Gameplay footprints,
## roads, water and forest discs are avoidance inputs only.

# An authored map REPLACES the procedural fabric (see authored_fabric_visuals.gd's header),
# so this node stands down when an authored document is active — otherwise its decorative
# buildings would draw under the authored parks/plazas (owner bug, 2026-08-19).
const AuthoredMap := preload("res://scripts/authored_map.gd")

const TILE_CENTER := Vector2(270.0, 240.0)
## How far beyond a tile's own box a NEIGHBOUR's gameplay footprint can still
## reach into it. Generous on purpose: the cost of over-including a footprint is
## one extra polygon test, the cost of under-including is a reserved plot drawn
## underneath a building that already exists.
const ACCOMMODATION_FOOTPRINT_REACH := 160.0
static var HEX_VERTS := PackedVector2Array([
	Vector2(-135.0, -240.0), Vector2(135.0, -240.0), Vector2(270.0, 0.0),
	Vector2(135.0, 240.0), Vector2(-135.0, 240.0), Vector2(-270.0, 0.0),
])
const BLOCK_SHADOW_OFFSET := Vector2(2.2, 2.8)
const PARCEL_MARGIN := 4.5
const ROAD_CLEAR := 7.0
const FOREST_CLEAR := 5.0
const HERO_ARIN_TILES := {
	"tile_9_16": true,
	"tile_9_18": true,
	"tile_10_16": true,
	"tile_10_17": true,
	"tile_10_18": true,
	"tile_11_16": true,
	"tile_11_17": true,
	"tile_12_16": true,
	"tile_12_17": true,
}
const HERO_ROAD_MARGIN := 5.2
const HERO_FACE_TARGET_AREA := 10500.0
const HERO_FACE_MIN_AREA := 1800.0
const HERO_MAX_SPLIT_DEPTH := 5
const HERO_ALLEY_HALF_WIDTH := 1.9
const MORPH_FACE_MIN_AREA := 1500.0
const MORPH_MAX_SPLIT_DEPTH := 5
const MORPH_MIN_RELIEF_AREA_RETENTION := 0.72
const MORPH_MIN_RELIEF_FACE_RETENTION := 0.60
const MORPH_NEAR_ROAD_DEPTH := 82.0
const MORPH_CORE_USABLE_MIN_AREA := 700.0
const MORPH_HEX_EDGE_FAILURE_FRACTION := 0.30
## Coastal reach.  Water-adjacent hex edges never carry an authoritative road
## crossing, so the directional crossing lobes can never grow the district field
## seaward and the extent stops roughly a core radius short of the shoreline.
## These constants drive one extra pair of the SAME organic influence cell —
## a reach spur and a shore-parallel frontage — per wet bearing.  They only move
## the PRE-CLIP extent: the water exclusion, the forbidden sea/mountain hexes,
## forest, roads, relief and the final dry-land and gameplay guards all run
## afterwards and remain the sole authority on where a mass may sit.
const MORPH_COAST_PROBE_STEP := 8.0
const MORPH_COAST_PROBE_LIMIT := 460.0
const MORPH_COAST_EDGE_SAMPLES := 7
const MORPH_COAST_MIN_GAP := 26.0
const MORPH_COAST_OVERSHOOT := 24.0
const MORPH_COAST_FRONT_INSET := 12.0
const MORPH_COAST_FRONT_SPAN := 0.52
const MORPH_COAST_FRONT_DEPTH := 38.0
const MORPH_COAST_SPUR_START := 0.30
## The extent and the growth-intensity field are two faces of the same district
## field.  Growing the extent alone hands the new waterfront to the low-intensity
## tail, which enlarges the subdivision target and lowers the built share: the
## extent-only variant rendered coarse floating slabs, moved greens 412 -> 473
## and dropped Vandel road-frontage occupancy 97.5 -> 80.6.  A coastal bearing
## therefore also floors the growth intensity, so the waterfront subdivides at
## core grain and reads as dense frontage rather than lawn.  The floor applies
## inside the wedge the frontage cell occupies and fades out past the shoreline.
##
## Two rejected variants are recorded so they are not retried.  A WIDER frontage
## cell (0.80 core radii, 44u depth) draws more buildings in absolute terms —
## 1,624 against 1,556 small masses map-wide — and holds Vandel Port Works
## denser, but it loses on the addendum's own section 2 gate (27 compliant urban
## tiles against 32, with Stoneshore Docks and Vandel Port both falling from
## PASS to FAIL) and degrades the structural counters (new hex-coincident tiles
## 16 against 11, road-gradient failures 8 against 6, median road-frontage
## occupancy 84.3 against 91.9).  Section 2 wins, so the narrow cell ships.
##
## The second rejected variant is bounding the
## reach by how far an authoritative road already leads seaward.  It is the
## honest structural objection — roads are frozen and are the only source of
## street faces — but measured, it starved the owner's named targets, leaving
## Stoneshore Old Quarter and Stoneshore Docks at exactly 0% growth while
## raising dense-core failures from 0 to 2.  Density has to come from intensity,
## not from refusing to grow.
const MORPH_COAST_INTENSITY_TARGET := 0.78
const MORPH_COAST_WEDGE_SPREAD := 1.25
const MORPH_COAST_TAIL_DEPTH := 70.0
## Minimum-retention gate for the reach geometry itself: the enlarged extent is
## a superset of the core-only extent, so after the identical clip every tile
## must retain at least this ratio of its core-only usable area.  Anything below
## one means the new geometry has SUBTRACTED envelope somewhere, which is the
## failure mode the relief investigation caught, and the run reports it.
const MORPH_COAST_MIN_RETENTION := 1.0
const AUDIT_CORE_STANDARD_AREA := 2500.0
const AUDIT_CORE_CONSTRAINED_MIN_MASSES := 3
const AUDIT_RICH_POOR_MIN_AREA := 5000.0
const AUDIT_RICH_POOR_MIN_DELTA := 5.0
const AUDIT_LOCAL_HEX_FAILURE_FRACTION := 0.20
const AUDIT_SAMPLE_STEP := 14.0
const MORPH_PROFILE_METRO := "metropolitan"
const MORPH_PROFILE_TOWN := "town"
const MORPH_PROFILE_SMALL_TOWN := "small_town"
const MORPH_PROFILE_FRINGE := "industrial_fringe"
const MORPH_PROFILE_VILLAGE := "village"
const MORPH_PROFILE_RURAL := "rural"
const SETTLEMENT_PROFILE_PATH := "res://data/visual_settlement_profiles.json"
const FAR_PLATE_ZOOM := 0.28

var _terrain: TileMapLayer = null
var _buildings: Node = null
var _forests: Node = null
var _queued := false
var _settlement_plans: Dictionary = {}

var _parcel_mesh: ArrayMesh = null
var _yard_mesh: ArrayMesh = null
var _shadow_mesh: ArrayMesh = null
var _park_mesh: ArrayMesh = null
var _block_mesh: ArrayMesh = null
var _roof_shadow_mesh: ArrayMesh = null
var _roof_top_mesh: ArrayMesh = null
var _far_plate_mesh: ArrayMesh = null
var _roof_shadow_entries: Array = []
var _roof_top_entries: Array = []
var _parcel_edges := PackedVector2Array()
var _block_edges := PackedVector2Array()
var _roof_edges := PackedVector2Array()
var _roof_marks := PackedVector2Array()
var _park_marks := PackedVector2Array()
var _open_lot_marks := PackedVector2Array()
var _service_lines := PackedVector2Array()
var _hero_alleys := PackedVector2Array()
var _settlement_streets := PackedVector2Array()
var _active_plan: SettlementPlan = null
var _active_plan_water_exclusions: Array = []
var _active_relief_shoulders: Array = []
var _active_relief_masses: Array = []
var _active_relief_fills: Array = []
var _active_relief_shadows: Array = []
var _active_relief_roofs: Array = []
var _accommodation_sites: Array = []
var _decorative_mass_records: Array = []
var _urban_audit_components: Array = []
var _rural_growth_metrics: Dictionary = {}
var _rural_growth_records: Dictionary = {}
var _suburban_metrics: Dictionary = {}
var _dry_land_rejections: Dictionary = {}
var _footprint_signal_source: Node = null
var _explicit_profiles: Dictionary = {}
var _far_plate_active := false
## Read-only record of the SANITIZED decorative geometry the mid-century style
## actually renders. Filled at the end of every rebuild, AFTER the dry-land and
## gameplay-collision guards have removed entries, so the density audit measures
## what is drawn rather than what was requested. Draw-only: never read by the
## simulation, occupancy, placement legality, click testing or save data.
var _render_mass_entries: Array = []
var _render_park_entries: Array = []
## Sanitised parcel layer, retained for the articulation / park-vs-hole audit
## ONLY. Nothing draws from it (the parcel mesh is built from the same array),
## so retaining the reference cannot change a pixel.
var _render_parcel_entries: Array = []
## Sanitised BLOCK SHADOW layer, retained for the articulation audit ONLY.
## `_shadow_mesh` is built from this same array, so retaining the reference
## cannot change a pixel. The gauntlet6 instrument was never shown this layer
## and therefore clustered a shape strictly smaller than the plate draws.
var _render_shadow_entries: Array = []
## Rare industrial landmark tier: instance id -> landmark compound key, plus the
## selected compounds themselves. Draw-only accent bookkeeping; it reserves no
## land and never enters placement, occupancy or selection.
var _industry_landmark_ids: Dictionary = {}
var _industry_landmark_compounds: Array = []

var _metrics := {
	"tiles": 0, "parcels": 0, "blocks": 0, "parks": 0, "open_lots": 0,
	"accommodation": {},
}

func _ready() -> void:
	visible = false
	set_process(false)
	_load_explicit_profiles()
	MapStyle.style_changed.connect(_on_style_changed)
	RoadWorks.order_settled.connect(_on_road_settled)
	_bind_footprint_change_signal.call_deferred()
	_on_style_changed()

func _bind_footprint_change_signal() -> void:
	var source := get_tree().get_first_node_in_group("building_footprints")
	if source == null or source == _footprint_signal_source:
		return
	_footprint_signal_source = source
	if source.has_signal("footprints_changed"):
		source.footprints_changed.connect(_on_footprints_changed)

func _load_explicit_profiles() -> void:
	_explicit_profiles = {}
	if not FileAccess.file_exists(SETTLEMENT_PROFILE_PATH):
		return
	var file := FileAccess.open(SETTLEMENT_PROFILE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		_explicit_profiles = parsed

## THE ONE CONDITION. It used to be spelled out here and paraphrased as a bare
## `MapStyle.is_midcentury()` in the rebuild guards, which is not the same test: an authored
## document turns this layer OFF, and the guards did not know that. While midcentury was an
## opt-in cheat the difference never showed. The moment it shipped as the default, every
## footprint change on an authored map -- four hundred of them during a load -- queued a full
## procedural-fabric rebuild for a layer that draws nothing, and the CPU that went into it
## starved the hill triangulation's worker pool: 6 s of contour work took 380 s.
func _draws_here() -> bool:
	return MapStyle.is_midcentury() and not AuthoredMap.is_active()


func _on_style_changed() -> void:
	visible = _draws_here()
	set_process(visible)
	if visible:
		_update_far_plate_state()
		_schedule_rebuild()
	else:
		_clear_geometry()

func _process(_delta: float) -> void:
	_update_far_plate_state()

func _update_far_plate_state() -> void:
	var camera := get_viewport().get_camera_2d()
	var next_active := camera != null and camera.zoom.x <= FAR_PLATE_ZOOM
	if next_active == _far_plate_active:
		return
	_far_plate_active = next_active
	queue_redraw()

func _on_footprints_changed(_version: int, _affected_tile_ids: Array) -> void:
	_schedule_rebuild()

func _on_road_settled(_order_id: int) -> void:
	_schedule_rebuild()

func _schedule_rebuild() -> void:
	if not _draws_here() or _queued:
		return
	_queued = true
	_rebuild.call_deferred()

func _rebuild() -> void:
	_queued = false
	if not _draws_here():
		return
	_terrain = get_node_or_null("../TerrainLayer") as TileMapLayer
	_buildings = get_tree().get_first_node_in_group("building_footprints")
	_bind_footprint_change_signal()
	_forests = get_node_or_null("../ForestVisuals")
	if _terrain == null:
		return

	var parcel_entries: Array = []
	var yard_entries: Array = []
	var shadow_entries: Array = []
	var park_entries: Array = []
	var block_entries: Array = []
	var roof_shadow_entries: Array = []
	var roof_top_entries: Array = []
	var hero_coords: Array[Vector2i] = []
	var morphology_coords: Array[Vector2i] = []
	_parcel_edges = PackedVector2Array()
	_block_edges = PackedVector2Array()
	_roof_edges = PackedVector2Array()
	_roof_marks = PackedVector2Array()
	_park_marks = PackedVector2Array()
	_open_lot_marks = PackedVector2Array()
	_service_lines = PackedVector2Array()
	_hero_alleys = PackedVector2Array()
	_settlement_streets = PackedVector2Array()
	_active_plan = null
	_active_plan_water_exclusions = []
	_active_relief_shoulders = []
	_active_relief_masses = []
	_active_relief_fills = []
	_active_relief_shadows = []
	_active_relief_roofs = []
	_accommodation_sites = []
	_decorative_mass_records = []
	_render_mass_entries = []
	_render_park_entries = []
	_render_parcel_entries = []
	_render_shadow_entries = []
	_urban_audit_components = []
	_dry_land_rejections = {"block": 0, "shadow": 0, "accommodation": 0}
	_rural_growth_records = {}
	_rural_growth_metrics = {"tiles": {}, "total_masses": 0,
		"within_frontage_depth": 0, "junction_masses": 0,
		"back_row_masses": 0, "roadless_skips": 0,
		"water_overlap_count": 0, "relief_overlap_count": 0,
		"forest_overlap_count": 0, "gameplay_overlap_count": 0,
		"road_overlap_count": 0}
	_suburban_metrics = {"districts": [], "total_masses": 0,
		"access_streets": 0, "street_width": 3.0,
		"cross_tile_districts": 0, "road_connection_failure_count": 0,
		"floating_street_count": 0, "water_overlap_count": 0,
		"relief_overlap_count": 0, "forest_overlap_count": 0,
		"gameplay_overlap_count": 0, "decorative_overlap_count": 0,
		"accommodation_overlap_count": 0, "mountain_mass_count": 0}
	_metrics = {
		"tiles": 0, "parcels": 0, "blocks": 0, "parks": 0, "open_lots": 0,
		"morph_roofs": {"plain": 0, "pitched": 0, "raised": 0, "utility": 0},
		"settlements": {}, "tile_profiles": {}, "tile_to_settlement": {},
		"district_field": {"components": {}, "tiles": {},
			"usable_urban_tiles": 0, "missing_visible_core_count": 0,
			"density_direction_failure_count": 0,
			"hex_boundary_failure_count": 0,
			"universal_tile_count": 0, "dense_core_failure_count": 0,
			"gradient_applicable_count": 0, "gradient_failure_count": 0,
			"internal_seam_failure_count": 0,
			"local_hex_failure_count": 0, "actual_spill_tile_count": 0},
		"accommodation": {"tiles": {}, "total_sites": 0,
			"constrained_tiles": [], "failure_totals": {
				"pairwise_overlap_count": 0, "water_overlap_count": 0,
				"contour_overlap_count": 0,
				"existing_footprint_overlap_count": 0,
				"decorative_mass_overlap_count": 0,
			}},
	}
	_settlement_plans = {}
	# Roof arrays are class-local scratch so the established street-wall call
	# graph remains compact and the layer still emits only a handful of batches.
	_roof_shadow_entries = roof_shadow_entries
	_roof_top_entries = roof_top_entries

	for coord_value in _terrain.tiles:
		var coord: Vector2i = coord_value
		var tile_data: Dictionary = _terrain.tiles[coord]
		if str(tile_data.get("type", "")) != "urban":
			continue
		var tile_id := str(tile_data.get("id", "%d_%d" % [coord.x, coord.y]))
		if HERO_ARIN_TILES.has(tile_id):
			hero_coords.append(coord)
			continue
		morphology_coords.append(coord)
	_select_industry_landmarks()
	for component_value in _urban_components(morphology_coords):
		var component: Array[Vector2i] = component_value
		_build_morph_component(component, parcel_entries, yard_entries, shadow_entries,
			park_entries, block_entries)
	_metrics["urban_blocks_before_rural"] = int(_metrics.blocks)
	_metrics["urban_parcels_before_rural"] = int(_metrics.parcels)
	_build_rural_growth(parcel_entries, shadow_entries, park_entries, block_entries)
	_build_suburban_fringe()
	_metrics["suburban"] = _suburban_metrics.duplicate(true)
	_build_hero_arin(hero_coords, parcel_entries, shadow_entries, park_entries, block_entries)
	_ensure_universal_dense_cores(parcel_entries, shadow_entries, block_entries)
	_ensure_universal_road_gradients(parcel_entries, shadow_entries, block_entries)
	_build_universal_district_audit()
	_metrics["rural_growth"] = _rural_growth_metrics.duplicate(true)
	_metrics["dry_land_guard"] = _sanitize_decorative_fills({
		"parcel": parcel_entries,
		"yard": yard_entries,
		"shadow": shadow_entries,
		"park": park_entries,
		"block": block_entries,
		"roof_shadow": roof_shadow_entries,
		"roof_top": roof_top_entries,
	})
	_metrics["gameplay_collision_guard"] = _sanitize_gameplay_collisions({
		"parcel": parcel_entries,
		"yard": yard_entries,
		"shadow": shadow_entries,
		"park": park_entries,
		"block": block_entries,
		"roof_shadow": roof_shadow_entries,
		"roof_top": roof_top_entries,
	})

	# CLEANUP PASS — an outline round ground nobody built on reads as a surveyed
	# plot that was never developed, and a field of them is the "unfinished plate"
	# the critic keeps naming. Drop the RING of any parcel that ends up with no
	# drawn mass in it; keep its fill, because uncovered parcel area is most of the
	# settlement's paper ground and deleting it would leave buildings on bare
	# terrain. Park/yard/open roles are content in their own right and are exempt.
	_metrics["empty_parcel_cleanup"] = _suppress_empty_parcel_outlines(
		parcel_entries, block_entries)

	# The sanitized arrays are the render truth: everything below draws from
	# them, and so does the per-tile density audit.
	_render_mass_entries = block_entries
	_render_park_entries = park_entries
	_render_parcel_entries = parcel_entries
	_render_shadow_entries = shadow_entries

	_parcel_mesh = _fill_mesh(parcel_entries)
	_yard_mesh = _fill_mesh(yard_entries)
	_shadow_mesh = _fill_mesh(shadow_entries)
	_park_mesh = _fill_mesh(park_entries)
	_block_mesh = _fill_mesh(block_entries)
	_roof_shadow_mesh = _fill_mesh(roof_shadow_entries)
	_roof_top_mesh = _fill_mesh(roof_top_entries)
	var far_plate_entries: Array = []
	var far_plate_area := 0.0
	for entry_value in block_entries:
		var entry: Dictionary = entry_value
		var poly: PackedVector2Array = entry.get("poly", PackedVector2Array())
		if poly.size() < 3:
			continue
		far_plate_entries.append({"poly": poly,
			"color": MapMidcenturyStyle.far_urban_plate()})
		far_plate_area += _poly_area(poly)
	var landmark_plate := _append_industry_landmark_plate(far_plate_entries)
	_far_plate_mesh = _fill_mesh(far_plate_entries)
	_metrics["far_zoom_plate"] = {
		"source": "sanitized_decorative_masses",
		"switch_zoom": FAR_PLATE_ZOOM,
		"mass_count": far_plate_entries.size() - int(landmark_plate.drawn_count),
		"area": far_plate_area,
		"uses_tile_envelopes": false,
		"industry_landmarks": landmark_plate,
	}
	queue_redraw()
	print("[MIDCENTURY] fabric: %d urban tiles, %d parcels, %d blocks, %d parks, %d open lots" % [
		int(_metrics.tiles), int(_metrics.parcels), int(_metrics.blocks),
		int(_metrics.parks), int(_metrics.open_lots),
	])
	if _metrics.has("hero_arin"):
		var hero: Dictionary = _metrics.hero_arin
		print("[MIDCENTURY] Arin hero: %d street faces, %d parcels, %.1f%% built, %.1f%% green, %.1f%% negative" % [
			int(hero.street_faces), int(hero.parcels), float(hero.built_pct),
			float(hero.green_pct), float(hero.negative_pct),
		])
	if _metrics.has("hero_forms"):
		var forms: Dictionary = _metrics.hero_forms
		print("[MIDCENTURY] Arin masses: %d solid, %d U, %d L, %d courtyard rings" % [
			int(forms.solid), int(forms.u), int(forms.l), int(forms.ring),
		])

## ── Rare industrial landmark tier ───────────────────────────────────────────
## The references carry a handful of strong oxide/rust works that survive world
## scale while every other industry stays a quiet half-chroma print. This picks
## that single-digit subset once per rebuild from the authoritative gameplay
## footprints, so the accent is identical in every capture of the same map.
func _select_industry_landmarks() -> void:
	_industry_landmark_ids = {}
	_industry_landmark_compounds = []
	if _buildings == null or not _buildings.has_method("midcentury_industry_sites_on_tile"):
		return
	var sites: Array = []
	for coord_value in _terrain.tiles:
		sites.append_array(_buildings.midcentury_industry_sites_on_tile(
			coord_value as Vector2i))
	var selection := MidcenturyIndustryCompound.select_landmarks(sites)
	_industry_landmark_ids = selection.instance_ids
	_industry_landmark_compounds = selection.compounds
	_metrics["industry_landmarks"] = selection.diagnostics
	var diagnostics: Dictionary = selection.diagnostics
	print("[MIDCENTURY] industry landmarks: %d of %d sites (%d candidates): %s" % [
		int(diagnostics.landmark_count), int(diagnostics.site_count),
		int(diagnostics.candidate_count), str(diagnostics.landmark_keys),
	])

## True when this real industry belongs to a selected landmark compound.
## Compound apron wash: the ordinary half-chroma family, or the rare landmark
## oxide for the selected few.
func _industry_apron_color(instance_id: String, family: String) -> Color:
	if _is_industry_landmark(instance_id):
		return MapMidcenturyStyle.industry_landmark_yard(
			_industry_landmark_key(instance_id))
	return MapMidcenturyStyle.industrial_apron(family)

func _is_industry_landmark(instance_id: String) -> bool:
	return _industry_landmark_ids.has(instance_id)

func _industry_landmark_key(instance_id: String) -> String:
	return str(_industry_landmark_ids.get(instance_id, instance_id))

## World-scale accent masses, appended after the quiet settlement plate so the
## few landmarks read on top of it. Each patch shrinks its halo until it sits
## wholly on dry land, exactly like every other decorative fill.
func _append_industry_landmark_plate(far_plate_entries: Array) -> Dictionary:
	var drawn := 0
	var area := 0.0
	var shrunk := 0
	var dropped := 0
	for compound_value in _industry_landmark_compounds:
		var compound: Dictionary = compound_value
		var key := str(compound.key)
		var patch := PackedVector2Array()
		var halo_index := 0
		for halo in MidcenturyIndustryCompound.LANDMARK_HALOS:
			var candidate := MidcenturyIndustryCompound.landmark_patch(
				compound.bounds as Rect2, halo, key)
			if candidate.size() >= 3 and _poly_on_dry_land(candidate):
				patch = candidate
				break
			halo_index += 1
		if patch.size() < 3:
			dropped += 1
			continue
		if halo_index > 0:
			shrunk += 1
		far_plate_entries.append({"poly": patch,
			"color": MapMidcenturyStyle.industry_landmark_plate(key)})
		drawn += 1
		area += _poly_area(patch)
	return {
		"selected_count": _industry_landmark_compounds.size(),
		"drawn_count": drawn,
		"shrunk_count": shrunk,
		"dropped_count": dropped,
		"area": area,
	}

func _urban_components(coords: Array[Vector2i]) -> Array:
	var ordered := coords.duplicate()
	ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x or (a.x == b.x and a.y < b.y)
	)
	var remaining: Dictionary = {}
	for coord in ordered:
		remaining[coord] = true
	var out: Array = []
	for seed in ordered:
		if not remaining.has(seed):
			continue
		remaining.erase(seed)
		var queue: Array[Vector2i] = [seed]
		var component: Array[Vector2i] = []
		while not queue.is_empty():
			var current: Vector2i = queue.pop_front()
			component.append(current)
			for neighbor_value in _terrain.call("neighbor_coords", current):
				var neighbor: Vector2i = neighbor_value
				if remaining.has(neighbor):
					remaining.erase(neighbor)
					queue.append(neighbor)
		component.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return a.x < b.x or (a.x == b.x and a.y < b.y)
		)
		out.append(component)
	return out

func _build_morph_component(coords: Array[Vector2i], parcel_entries: Array,
		yard_entries: Array, shadow_entries: Array, park_entries: Array,
		block_entries: Array) -> void:
	if coords.is_empty():
		return
	var named_count := 0
	for coord in coords:
		if str((_terrain.tiles[coord] as Dictionary).get("nickname", "")) != "":
			named_count += 1
	var specs: Array = []
	var footprints: Array = []
	var gameplay_sites: Array = []
	var industry_sites: Array = []
	var forest_discs: Array = []
	var road_segments: Array = []
	var seen_edges: Dictionary = {}
	var tile_ids: Array[String] = []
	var profile_counts: Dictionary = {}
	var hill_visuals := get_node_or_null("../HillVisuals")
	for coord in coords:
		var tile_data: Dictionary = _terrain.tiles[coord]
		var tile_id := str(tile_data.get("id", "%d_%d" % [coord.x, coord.y]))
		var center := _terrain.map_to_local(_terrain.map_coord_for_tile_coord(coord))
		var profile := _morph_profile_for_tile(tile_data, named_count)
		specs.append({"coord": coord, "id": tile_id, "center": center, "profile": profile})
		tile_ids.append(tile_id)
		profile_counts[profile] = int(profile_counts.get(profile, 0)) + 1
		if _buildings != null and _buildings.has_method("footprint_rects_on_tile"):
			footprints.append_array(_buildings.footprint_rects_on_tile(coord))
		if _buildings != null and _buildings.has_method("midcentury_footprint_sites_on_tile"):
			gameplay_sites.append_array(_buildings.midcentury_footprint_sites_on_tile(coord))
		if _buildings != null and _buildings.has_method("midcentury_industry_sites_on_tile"):
			industry_sites.append_array(_buildings.midcentury_industry_sites_on_tile(coord))
		if _forests != null and _forests.has_method("discs_on_tile"):
			forest_discs.append_array(_forests.discs_on_tile(coord))
		for edge_id_value in RoadNetwork.instance().edges_on_tile(coord):
			var edge_id := str(edge_id_value)
			if seen_edges.has(edge_id):
				continue
			seen_edges[edge_id] = true
			var edge: Dictionary = RoadNetwork.instance().edges.get(edge_id, {})
			if str(edge.get("state", "")) != RoadNetwork.STATE_BUILT:
				continue
			var geo: PackedVector2Array = edge.get("geometry", PackedVector2Array())
			var trunk := str(edge.get("tier", "")) == RoadNetwork.TIER_TRUNK
			for i in range(geo.size() - 1):
				road_segments.append({"a": geo[i], "b": geo[i + 1], "trunk": trunk,
					"edge_id": edge_id})

	tile_ids.sort()
	var component_key := "settlement|%s" % tile_ids[0]
	var edge_properties := _morph_edge_properties(specs, road_segments)
	if tile_ids.has("tile_23_8"):
		assert(tile_ids.size() == 7,
			"Capital Port settlement component must contain all seven recorded urban tiles")
		assert(int(edge_properties.internal_edge_count) > 0,
			"Capital Port settlement component must contain real internal edges")
		var capital_rivers := get_node_or_null("../RiverVisuals")
		if capital_rivers != null:
			var capital_plan := SettlementPlanBuilder.build_capital(_terrain,
				capital_rivers, hill_visuals, road_segments, footprints, gameplay_sites,
				industry_sites, specs)
			_settlement_plans[capital_plan.key] = capital_plan
			_build_capital_plan(capital_plan, coords, specs, footprints, gameplay_sites,
				parcel_entries, yard_entries, shadow_entries, park_entries,
				block_entries)
			_metrics["settlement_plan_capital"] = capital_plan.summary()
			for spec_value in specs:
				var spec: Dictionary = spec_value
				_metrics.tile_profiles[spec.id] = spec.profile
				_metrics.tile_to_settlement[spec.id] = "settlement-plan|capital-port"
			return
	if tile_ids.has("tile_9_8"):
		var river_visuals := get_node_or_null("../RiverVisuals")
		if river_visuals != null:
			var plan := SettlementPlanBuilder.build_silkstown(_terrain, river_visuals,
				hill_visuals, road_segments, footprints, gameplay_sites, industry_sites)
			_settlement_plans[plan.key] = plan
			_build_silkstown_plan(plan, coords, specs, footprints, gameplay_sites,
				parcel_entries,
				yard_entries, shadow_entries, park_entries, block_entries)
			_metrics["settlement_plan_silkstown"] = plan.summary()
			for spec_value in specs:
				var spec: Dictionary = spec_value
				_metrics.tile_profiles[spec.id] = spec.profile
				_metrics.tile_to_settlement[spec.id] = "settlement-plan|silkstown"
			return
	var district_field := _morph_district_field(specs, road_segments, component_key)
	var envelopes: Array = district_field.polys
	if envelopes.is_empty():
		for spec_value in specs:
			var spec: Dictionary = spec_value
			_metrics.tile_profiles[spec.id] = spec.profile
		return
	var envelope_bounds := _hero_polys_bbox(envelopes)
	var water_exclusions := _hero_water_exclusions(envelope_bounds)
	var natural_exclusions := water_exclusions.duplicate(true)
	var forbidden_tiles := _forbidden_settlement_tile_exclusions(envelopes)
	natural_exclusions.append_array(forbidden_tiles)
	natural_exclusions.append_array(_hero_forest_exclusions(forest_discs))
	envelopes = _hero_clip_polys(envelopes, natural_exclusions, MORPH_FACE_MIN_AREA)
	var envelope_area := _hero_polys_area(envelopes)
	_morph_record_coastal_reach(component_key, district_field, envelopes,
		natural_exclusions)
	var road_corridors := _hero_road_corridors(road_segments)
	var relief := _relief_geometry_for_extents(envelopes)
	var relief_shoulders: Array = relief.get("shoulders", [])
	var street_faces := _hero_clip_polys(envelopes, road_corridors, MORPH_FACE_MIN_AREA)
	var relief_faces: Array = []
	for i in street_faces.size():
		var street_face: PackedVector2Array = street_faces[i]
		var pieces := _hero_clip_polys([street_face], relief_shoulders,
			MORPH_FACE_MIN_AREA) if not relief_shoulders.is_empty() else [street_face]
		for piece_value in pieces:
			relief_faces.append({"poly": piece_value, "street_face": i})
	var street_face_area := _hero_polys_area(street_faces)
	var relief_face_polys: Array = []
	for face_value in relief_faces:
		relief_face_polys.append((face_value as Dictionary).poly)
	var relief_area_retention := _hero_polys_area(relief_face_polys) / maxf(
		1.0, street_face_area)
	var relief_face_retention := float(relief_faces.size()) / maxf(1.0,
		float(street_faces.size()))
	var relief_retention_fallback := bool(relief.get("active", false)) and (
		relief_faces.is_empty() or
		relief_area_retention < MORPH_MIN_RELIEF_AREA_RETENTION or
		relief_face_retention < MORPH_MIN_RELIEF_FACE_RETENTION)
	if relief_retention_fallback:
		relief = relief.duplicate(true)
		relief["active"] = false
		relief["shoulders"] = []
		relief["relief_retention_fallback"] = true
		relief["relief_face_area_retention"] = relief_area_retention
		relief["relief_face_count_retention"] = relief_face_retention
		relief["relief_shoulders_deferred_count"] = relief_shoulders.size()
		relief_shoulders = []
		relief_faces = []
		for i in street_faces.size():
			relief_faces.append({"poly": street_faces[i], "street_face": i})
	else:
		relief["relief_retention_fallback"] = false
		relief["relief_face_area_retention"] = relief_area_retention
		relief["relief_face_count_retention"] = relief_face_retention
	var records: Array = []
	for relief_face_value in relief_faces:
		var relief_face: Dictionary = relief_face_value
		var plateau_face: PackedVector2Array = relief_face.poly
		var street_face_index := int(relief_face.street_face)
		var face_sample := _morph_field_sample(_poly_center(plateau_face),
			district_field.tiles, road_segments)
		var profile := str(face_sample.profile)
		for parcel_value in _morph_subdivide_face(plateau_face,
				"%s|face|%d" % [component_key, street_face_index], 0, profile,
				float(face_sample.intensity)):
			var parcel: PackedVector2Array = parcel_value
			var sample := _morph_field_sample(_poly_center(parcel),
				district_field.tiles, road_segments)
			records.append({
				"poly": parcel,
				"profile": str(sample.profile),
				"owner_tile": str(sample.tile_id),
				"core_position": sample.core_position,
				"core_distance": float(sample.core_distance),
				"core_radius": float(sample.core_radius),
				"road_distance": float(sample.road_distance),
				"road_richness": float(sample.road_richness),
				"growth_intensity": float(sample.intensity),
				"street_face": street_face_index,
				"cluster": "%s|street-face|%d" % [component_key, street_face_index],
				"key": "%s|parcel|%d" % [component_key, records.size()],
				"role": "none",
				"relief_band": _land_band_at(_poly_center(parcel)),
			})

	_assign_morph_roles(records, component_key, specs, industry_sites,
		district_field.tiles)
	var footprint_exclusions := _hero_footprint_exclusions(footprints)
	footprint_exclusions.append_array(relief_shoulders)
	var industry_plan := MidcenturyIndustryCompound.plan(industry_sites,
		gameplay_sites, road_segments, water_exclusions, relief_shoulders,
		16.0, component_key)
	var industry_exclusions: Array = industry_plan.reservations
	if not _metrics.has("industry_compound_diagnostics"):
		_metrics.industry_compound_diagnostics = {}
	_metrics.industry_compound_diagnostics[component_key] = industry_plan.diagnostics
	footprint_exclusions.append_array(industry_exclusions)
	_active_relief_shoulders = relief_shoulders
	_active_relief_masses = []
	_active_relief_fills = []
	_active_relief_shadows = []
	_active_relief_roofs = []
	var mass_start := _decorative_mass_records.size()
	var industry_yard_area := _morph_add_industry_yards(industry_exclusions, street_faces,
		component_key, yard_entries)
	var built_area := 0.0
	var green_area := 0.0
	var yard_area := 0.0
	var open_area := 0.0
	for record_value in records:
		var record: Dictionary = record_value
		var result := _morph_add_face(record, footprint_exclusions, parcel_entries,
			shadow_entries, park_entries, block_entries)
		built_area += float(result.built_area)
		green_area += float(result.green_area)
		yard_area += float(result.yard_area)
		open_area += float(result.open_area)
	_morph_ensure_visible_cores(district_field.tiles, envelopes, road_corridors,
		footprint_exclusions, mass_start, shadow_entries, block_entries)
	var component_masses := _decorative_mass_records.slice(mass_start)
	var mass_distribution := _morph_mass_distribution(component_masses,
		district_field.tiles, road_segments)
	var tile_diagnostics := _morph_tile_diagnostics(district_field.tiles,
		envelopes, component_masses, road_segments)
	_register_urban_audit_component(component_key, specs, envelopes, records,
		component_masses, road_segments, district_field.tiles, {
			"water": water_exclusions + forbidden_tiles,
			"forest": _hero_forest_exclusions(forest_discs),
			"relief": relief_shoulders,
			"gameplay": _hero_footprint_exclusions(footprints),
			"industrial": industry_exclusions,
		})
	var site_exclusions := industry_exclusions.duplicate(true)
	site_exclusions.append_array(component_masses)
	var accommodation_sites := _plan_accommodation_sites(specs, road_segments,
		gameplay_sites, water_exclusions, relief_shoulders, records,
		site_exclusions, null)
	_draw_accommodation_sites(accommodation_sites, parcel_entries,
		yard_entries, park_entries)
	_finalize_accommodation_mass_overlap(accommodation_sites,
		_active_relief_masses)
	var relief_diagnostics := _relief_component_diagnostics(relief, records,
		gameplay_sites, specs, component_key)
	_active_relief_shoulders = []
	_active_relief_masses = []
	_active_relief_fills = []
	_active_relief_shadows = []
	_active_relief_roofs = []

	var stats := {
		"tiles": tile_ids,
		"profiles": profile_counts,
		"edge_properties": edge_properties,
		"street_faces": street_faces.size(),
		"parcels": records.size(),
		"envelope_area": envelope_area,
		"built_area": built_area,
		"green_area": green_area,
		"yard_area": yard_area,
		"industry_yard_area": industry_yard_area,
		"open_area": open_area,
		"built_pct": 100.0 * built_area / maxf(1.0, envelope_area),
		"green_pct": 100.0 * green_area / maxf(1.0, envelope_area),
		"yard_pct": 100.0 * yard_area / maxf(1.0, envelope_area),
		"negative_pct": 100.0 * maxf(0.0,
			envelope_area - built_area - green_area) / maxf(1.0, envelope_area),
		"mass_distribution": mass_distribution,
		"whole_body_gate": _morph_whole_body_gate(profile_counts,
			envelope_area, built_area, mass_distribution),
		"relief": relief_diagnostics,
		"district_field": tile_diagnostics,
	}
	_metrics.settlements[component_key] = stats
	_register_district_field_metrics(component_key, tile_diagnostics)
	_metrics.tiles = int(_metrics.tiles) + coords.size()
	for spec_value in specs:
		var spec: Dictionary = spec_value
		_metrics.tile_profiles[spec.id] = spec.profile
		_metrics.tile_to_settlement[spec.id] = component_key

func _build_silkstown_plan(plan: SettlementPlan, coords: Array[Vector2i],
		specs: Array, footprints: Array, gameplay_sites: Array, parcel_entries: Array,
		yard_entries: Array, shadow_entries: Array, park_entries: Array,
		block_entries: Array) -> void:
	_active_plan = plan
	_active_plan_water_exclusions = plan.water_exclusions
	_active_relief_shoulders = plan.relief_shoulders
	_reset_plan_visual_diagnostics(plan)
	# Contour shoulders separate massing geometrically. Do not also demote every
	# small parcel above the component-global minimum band; that erased valid
	# neighbourhoods in settlements whose relief varies elsewhere in the plan.
	for street_value in plan.decorative_streets:
		var street: Dictionary = street_value
		var points: PackedVector2Array = street.points
		for i in range(points.size() - 1):
			_append_dry_line(_settlement_streets, points[i], points[i + 1])
	var footprint_exclusions := _hero_footprint_exclusions(footprints)
	footprint_exclusions.append_array(plan.water_exclusions)
	var forbidden_tiles := _forbidden_settlement_tile_exclusions(
		plan.extent_polygons)
	footprint_exclusions.append_array(forbidden_tiles)
	_active_plan_water_exclusions = plan.water_exclusions + forbidden_tiles
	var visible_extents := _hero_clip_polys(plan.extent_polygons,
		forbidden_tiles, 1.0)
	var visible_parcels: Array = []
	var visible_face_area := 0.0
	var built_area := 0.0
	var green_area := 0.0
	var yard_area := 0.0
	var open_area := 0.0
	var mass_start := _decorative_mass_records.size()
	for parcel_value in _plan_massing_records(plan):
		var parcel: Dictionary = parcel_value
		var pieces := _hero_clip_polys([parcel.poly], forbidden_tiles, 1.0)
		for piece_index in pieces.size():
			visible_face_area += _poly_area(pieces[piece_index])
			var record := {
				"poly": pieces[piece_index],
				"profile": MORPH_PROFILE_TOWN,
				"cluster": "silkstown|%s" % str(parcel.face_key),
				"key": "%s|valid|%d" % [str(parcel.key), piece_index],
				"role": str(parcel.role),
			}
			visible_parcels.append(record)
			var result := _morph_add_face(record, footprint_exclusions,
				parcel_entries, shadow_entries, park_entries, block_entries)
			built_area += float(result.built_area)
			green_area += float(result.green_area)
			yard_area += float(result.yard_area)
			open_area += float(result.open_area)
	var compound_result := _add_silkstown_industry_compounds(plan, yard_entries,
		shadow_entries, block_entries)
	var compound_area := float(compound_result.area)
	plan.accommodation_sites = []
	var site_exclusions := plan.industrial_reservations.duplicate(true)
	site_exclusions.append_array(_decorative_mass_records.slice(mass_start))
	var accommodation_sites := _plan_accommodation_sites(specs,
		plan.authoritative_roads, gameplay_sites, plan.water_exclusions,
		plan.relief_shoulders, plan.parcels, site_exclusions, plan)
	_draw_accommodation_sites(accommodation_sites, parcel_entries,
		yard_entries, park_entries)
	_finalize_accommodation_mass_overlap(accommodation_sites,
		_decorative_mass_records.slice(mass_start))
	plan.diagnostics["accommodation_sites"] = _plan_accommodation_summary(
		plan.tile_ids)
	_finalize_plan_water_diagnostics(plan)
	_finalize_plan_relief_diagnostics(plan, gameplay_sites)
	_active_plan = null
	_active_plan_water_exclusions = []
	_active_relief_shoulders = []
	var extent_area := visible_face_area
	_metrics.settlements["settlement-plan|silkstown"] = {
		"tiles": plan.tile_ids.duplicate(),
		"profiles": {MORPH_PROFILE_TOWN: specs.size()},
		"street_faces": plan.faces.size(),
		"parcels": plan.parcels.size(),
		"envelope_area": plan.extent_area(),
		"face_area": extent_area,
		"built_area": built_area,
		"green_area": green_area,
		"yard_area": yard_area,
		"industry_compound_area": compound_area,
		"open_area": open_area,
		"built_pct": 100.0 * built_area / maxf(1.0, extent_area),
		"green_pct": 100.0 * green_area / maxf(1.0, extent_area),
		"yard_pct": 100.0 * yard_area / maxf(1.0, extent_area),
		"open_pct": 100.0 * open_area / maxf(1.0, extent_area),
		"decorative_streets": plan.decorative_streets.size(),
		"masses": plan.masses.size(),
	}
	_register_urban_audit_component("settlement-plan|silkstown", specs,
		visible_extents, visible_parcels,
		_decorative_mass_records.slice(mass_start), plan.authoritative_roads, {}, {
			"water": plan.water_exclusions + forbidden_tiles,
			"forest": [],
			"relief": plan.relief_shoulders,
			"gameplay": _hero_footprint_exclusions(footprints),
			"industrial": plan.industrial_reservations,
		})
	_metrics.tiles = int(_metrics.tiles) + coords.size()

func _build_capital_plan(plan: SettlementPlan, coords: Array[Vector2i],
		specs: Array, footprints: Array, gameplay_sites: Array, parcel_entries: Array,
		yard_entries: Array, shadow_entries: Array, park_entries: Array,
		block_entries: Array) -> void:
	_active_plan = plan
	_active_plan_water_exclusions = plan.water_exclusions
	_active_relief_shoulders = plan.relief_shoulders
	_reset_plan_visual_diagnostics(plan)
	# See Silkstown: geometry owns the contour gap. Component-global capacity
	# demotion is deliberately deferred until it can be evaluated per source tile.
	var footprint_exclusions := _hero_footprint_exclusions(footprints)
	footprint_exclusions.append_array(plan.water_exclusions)
	var forbidden_tiles := _forbidden_settlement_tile_exclusions(
		plan.extent_polygons)
	footprint_exclusions.append_array(forbidden_tiles)
	_active_plan_water_exclusions = plan.water_exclusions + forbidden_tiles
	var visible_extents := _hero_clip_polys(plan.extent_polygons,
		forbidden_tiles, 1.0)
	var visible_parcels: Array = []
	var visible_face_area := 0.0
	var built_area := 0.0
	var green_area := 0.0
	var yard_area := 0.0
	var open_area := 0.0
	var mass_start := _decorative_mass_records.size()
	for parcel_value in _plan_massing_records(plan):
		var parcel: Dictionary = parcel_value
		var context := str(parcel.get("context", "ordinary"))
		var profile := MORPH_PROFILE_TOWN
		if context == "core":
			profile = MORPH_PROFILE_METRO
		elif context == "works":
			profile = MORPH_PROFILE_FRINGE
		var pieces := _hero_clip_polys([parcel.poly], forbidden_tiles, 1.0)
		for piece_index in pieces.size():
			visible_face_area += _poly_area(pieces[piece_index])
			var record := {"poly": pieces[piece_index], "profile": profile,
				"cluster": "capital|%s" % str(parcel.face_key),
				"key": "%s|valid|%d" % [str(parcel.key), piece_index],
				"role": str(parcel.role)}
			visible_parcels.append(record)
			var result := _morph_add_face(record, footprint_exclusions,
				parcel_entries, shadow_entries, park_entries, block_entries)
			built_area += float(result.built_area)
			green_area += float(result.green_area)
			yard_area += float(result.yard_area)
			open_area += float(result.open_area)
	var industry_apron_area := _add_plan_industry_aprons(plan, yard_entries)
	plan.accommodation_sites = []
	var site_exclusions := plan.industrial_reservations.duplicate(true)
	site_exclusions.append_array(_decorative_mass_records.slice(mass_start))
	var accommodation_sites := _plan_accommodation_sites(specs,
		plan.authoritative_roads, gameplay_sites, plan.water_exclusions,
		plan.relief_shoulders, plan.parcels, site_exclusions, plan)
	_draw_accommodation_sites(accommodation_sites, parcel_entries,
		yard_entries, park_entries)
	_finalize_accommodation_mass_overlap(accommodation_sites,
		_decorative_mass_records.slice(mass_start))
	plan.diagnostics["accommodation_sites"] = _plan_accommodation_summary(
		plan.tile_ids)
	_finalize_plan_water_diagnostics(plan)
	_finalize_plan_relief_diagnostics(plan, gameplay_sites)
	_active_plan = null
	_active_plan_water_exclusions = []
	_active_relief_shoulders = []
	_update_capital_mass_diagnostics(plan)
	var face_area := visible_face_area
	_metrics.settlements["settlement-plan|capital-port"] = {
		"tiles": plan.tile_ids.duplicate(),
		"profiles": {MORPH_PROFILE_METRO: 2, MORPH_PROFILE_FRINGE: 3,
			MORPH_PROFILE_TOWN: 2},
		"street_faces": plan.faces.size(),
		"parcels": plan.parcels.size(),
		"envelope_area": plan.extent_area(),
		"face_area": face_area,
		"built_area": built_area,
		"green_area": green_area,
		"yard_area": yard_area,
		"open_area": open_area,
		"industry_apron_area": industry_apron_area,
		"built_pct": 100.0 * built_area / maxf(1.0, face_area),
		"green_pct": 100.0 * green_area / maxf(1.0, face_area),
		"yard_pct": 100.0 * yard_area / maxf(1.0, face_area),
		"open_pct": 100.0 * open_area / maxf(1.0, face_area),
		"masses": plan.masses.size(),
	}
	_register_urban_audit_component("settlement-plan|capital-port", specs,
		visible_extents, visible_parcels,
		_decorative_mass_records.slice(mass_start), plan.authoritative_roads, {}, {
			"water": plan.water_exclusions + forbidden_tiles,
			"forest": [],
			"relief": plan.relief_shoulders,
			"gameplay": _hero_footprint_exclusions(footprints),
			"industrial": plan.industrial_reservations,
		})
	_metrics.tiles = int(_metrics.tiles) + coords.size()

func _add_plan_industry_aprons(plan: SettlementPlan,
		yard_entries: Array) -> float:
	var total_area := 0.0
	for reservation_value in plan.industrial_reservations:
		var reservation: Dictionary = reservation_value
		for draw_value in reservation.get("draw_polys", [reservation.poly]):
			var draw_poly: PackedVector2Array = draw_value
			yard_entries.append({
				"poly": draw_poly,
				"color": _industry_apron_color(str(reservation.get("instance_id", "")),
					str(reservation.family)),
			})
			_active_relief_fills.append({"key": str(reservation.key),
				"poly": draw_poly.duplicate(), "role": "industry-apron"})
			_append_ring(_parcel_edges, draw_poly)
			total_area += _poly_area(draw_poly)
	return total_area

func _update_capital_mass_diagnostics(plan: SettlementPlan) -> void:
	var mass_areas: Array[float] = []
	for mass_value in plan.masses:
		mass_areas.append(_poly_area((mass_value as Dictionary).poly))
	mass_areas.sort()
	var largest_parcel := 0.0
	var largest_paper := 0.0
	var open_area := 0.0
	for parcel_value in plan.parcels:
		var parcel: Dictionary = parcel_value
		var area := _poly_area(parcel.poly)
		if str(parcel.role) == "built":
			largest_parcel = maxf(largest_parcel, area)
		elif str(parcel.role) == "open":
			largest_paper = maxf(largest_paper, area)
			open_area += area
	plan.diagnostics["block_area_distribution"] = {
		"count": mass_areas.size(),
		"min": mass_areas[0] if not mass_areas.is_empty() else 0.0,
		"median": mass_areas[mass_areas.size() / 2] if not mass_areas.is_empty() else 0.0,
		"p75": mass_areas[int(floor(float(mass_areas.size() - 1) * 0.75))] if not mass_areas.is_empty() else 0.0,
		"max": mass_areas[-1] if not mass_areas.is_empty() else 0.0,
	}
	plan.diagnostics["largest_ordinary_parcel"] = largest_parcel
	plan.diagnostics["largest_continuous_paper_polygon"] = largest_paper
	plan.diagnostics["intentional_open_lot_area"] = open_area

func _reset_plan_visual_diagnostics(plan: SettlementPlan) -> void:
	_active_relief_masses = []
	_active_relief_fills = []
	_active_relief_shadows = []
	_active_relief_roofs = []
	plan.masses = []
	plan.visual_shadows = []
	plan.visual_roof_elements = []
	plan.visual_roof_marks = []
	for key in [
		"ordinary_mass_water_overlap_area",
		"industrial_support_water_overlap_area",
		"cross_bank_mass_count",
		"disconnected_mass_after_water_clip_count",
		"roof_element_water_overlap_count",
		"shadow_water_overlap_count",
		"contour_crossing_decorative_mass_count",
		"decorative_fill_relief_shoulder_overlap_area",
		"disconnected_mass_after_relief_count",
		"multi_band_decorative_building_count",
	]:
		plan.diagnostics[key] = 0.0 if str(key).ends_with("_area") else 0

func _finalize_plan_water_diagnostics(plan: SettlementPlan) -> void:
	var ordinary_overlap := 0.0
	var support_overlap := 0.0
	var cross_bank := 0
	var disconnected_after_clip := 0
	for mass_value in plan.masses:
		var mass: Dictionary = mass_value
		var poly: PackedVector2Array = mass.poly
		var overlap := _poly_water_overlap_area(poly, plan.water_exclusions)
		if str(mass.get("role", "ordinary")) == "industry-support":
			support_overlap += overlap
		else:
			ordinary_overlap += overlap
		var land_pieces := _clip_poly_from_water(poly, plan.water_exclusions)
		if land_pieces.size() > 1:
			disconnected_after_clip += 1
			cross_bank += 1
		elif overlap > 0.001:
			cross_bank += 1
	var roof_overlaps := 0
	for roof_value in plan.visual_roof_elements:
		var roof: Dictionary = roof_value
		if _poly_water_overlap_area(roof.poly, plan.water_exclusions) > 0.001:
			roof_overlaps += 1
	var shadow_overlaps := 0
	for shadow_value in plan.visual_shadows:
		var shadow: Dictionary = shadow_value
		if _poly_water_overlap_area(shadow.poly, plan.water_exclusions) > 0.001:
			shadow_overlaps += 1
	var mark_overlaps := 0
	for mark_value in plan.visual_roof_marks:
		var mark: Dictionary = mark_value
		if _segment_overlaps_water(mark.a, mark.b, plan.water_exclusions):
			mark_overlaps += 1
	plan.diagnostics["ordinary_mass_water_overlap_area"] = (
		0.0 if ordinary_overlap < 0.001 else ordinary_overlap)
	plan.diagnostics["industrial_support_water_overlap_area"] = (
		0.0 if support_overlap < 0.001 else support_overlap)
	plan.diagnostics["cross_bank_mass_count"] = cross_bank
	plan.diagnostics["disconnected_mass_after_water_clip_count"] = disconnected_after_clip
	plan.diagnostics["roof_element_water_overlap_count"] = roof_overlaps + mark_overlaps
	plan.diagnostics["shadow_water_overlap_count"] = shadow_overlaps
	if not plan.diagnostics.has("uncovered_river_join_count"):
		plan.diagnostics["uncovered_river_join_count"] = 0

func _poly_overlaps_active_plan_water(poly: PackedVector2Array) -> float:
	if _active_plan_water_exclusions.is_empty():
		return 0.0
	return _poly_water_overlap_area(poly, _active_plan_water_exclusions)

func _poly_overlaps_active_relief(poly: PackedVector2Array) -> float:
	if _active_relief_shoulders.is_empty():
		return 0.0
	return _poly_water_overlap_area(poly, _active_relief_shoulders)

func _poly_water_overlap_area(poly: PackedVector2Array, exclusions: Array) -> float:
	if poly.size() < 3:
		return 0.0
	var total := 0.0
	var poly_bb := _bbox(poly)
	for exclusion_value in exclusions:
		var exclusion: Dictionary = exclusion_value
		if not poly_bb.intersects(exclusion.bb):
			continue
		for intersection_value in Geometry2D.intersect_polygons(poly, exclusion.poly):
			var intersection: PackedVector2Array = intersection_value
			if intersection.size() >= 3:
				total += _poly_area(intersection)
	return total

func _clip_poly_from_water(poly: PackedVector2Array, exclusions: Array) -> Array:
	var pieces: Array = [poly]
	for exclusion_value in exclusions:
		var exclusion: Dictionary = exclusion_value
		var next: Array = []
		for piece_value in pieces:
			var piece: PackedVector2Array = piece_value
			if not _bbox(piece).intersects(exclusion.bb):
				next.append(piece)
				continue
			for clipped_value in Geometry2D.clip_polygons(piece, exclusion.poly):
				var clipped: PackedVector2Array = clipped_value
				if clipped.size() >= 3 and _poly_area(clipped) > 0.01:
					next.append(clipped)
		pieces = next
	return pieces

func _segment_overlaps_water(a: Vector2, b: Vector2, exclusions: Array) -> bool:
	if a == b:
		return false
	var probe := _segment_quad(a, b, 0.4)
	return _poly_water_overlap_area(probe, exclusions) > 0.001

func _append_safe_roof_mark(a: Vector2, b: Vector2, key: String) -> void:
	if _active_plan != null and _segment_overlaps_water(a, b,
			_active_plan_water_exclusions):
		return
	if _segment_overlaps_water(a, b, _active_relief_shoulders):
		return
	_append_line(_roof_marks, a, b)
	if _active_plan != null:
		_active_plan.visual_roof_marks.append({"key": key, "a": a, "b": b})

func _add_silkstown_industry_compounds(plan: SettlementPlan,
		yard_entries: Array, shadow_entries: Array, block_entries: Array) -> Dictionary:
	var total_area := 0.0
	var support_count := 0
	var support_omitted_count := 0
	plan.diagnostics["support_building_overlap_count"] = 0
	for i in plan.industrial_reservations.size():
		var reservation: Dictionary = plan.industrial_reservations[i]
		var footprint: PackedVector2Array = reservation.footprint_poly
		var family := str(reservation.family)
		var key := "silkstown-industry|%s" % str(reservation.key)
		var apron: PackedVector2Array = reservation.poly
		var draw_polys: Array = reservation.get("draw_polys", [apron])
		for draw_value in draw_polys:
			var draw_poly: PackedVector2Array = draw_value
			yard_entries.append({
				"poly": draw_poly,
				"color": _industry_apron_color(
					str(reservation.get("instance_id", "")), family),
			})
			_active_relief_fills.append({"key": key, "poly": draw_poly.duplicate(),
				"role": "industry-apron"})
			_append_ring(_parcel_edges, draw_poly)
			total_area += _poly_area(draw_poly)
		var side := -1.0 if i % 2 == 0 else 1.0
		var tangent: Vector2 = reservation.tangent
		var normal: Vector2 = reservation.normal
		var center := _poly_center(footprint)
		var tangent_half := _poly_projected_half_extent(footprint, center, tangent)
		var normal_half := _poly_projected_half_extent(footprint, center, normal)
		var shed_size := Vector2(clampf(tangent_half * 0.88, 16.0, 24.0), 9.0)
		var shed_center := center + normal * side * (
			normal_half + shed_size.y * 0.5 + 3.2)
		shed_center += tangent * _rr("%s|shed-tangent" % key, -0.12, 0.12) \
			* tangent_half
		var shed := _oriented_rect_poly(shed_center, tangent, normal,
			shed_size.x, shed_size.y)
		if _add_industry_support_mass(shed, tangent, key, family, draw_polys,
				reservation.blocked_exclusions, footprint, shadow_entries,
				block_entries):
			total_area += _poly_area(shed)
			support_count += 1
		else:
			support_omitted_count += 1
		var tank_center := center - normal * side * (normal_half + 8.2)
		tank_center += tangent * _rr("%s|tank-tangent" % key, -0.16, 0.16) \
			* tangent_half
		var tank := _circle_poly(tank_center, 7.5, 12)
		var tank_added := _add_industry_support_mass(tank, tangent,
			"%s|tank" % key, family, draw_polys, reservation.blocked_exclusions,
			footprint, shadow_entries, block_entries)
		var pipe_start := center - normal * side * normal_half
		if tank_added and not _segment_overlaps_water(pipe_start, tank_center,
				_active_plan_water_exclusions):
			_append_dry_line(_service_lines, pipe_start, tank_center)
		if tank_added:
			_append_safe_roof_mark(tank_center - Vector2(4.3, 0.0),
				tank_center + Vector2(4.3, 0.0), "%s|tank" % key)
			total_area += _poly_area(tank)
			support_count += 1
		else:
			support_omitted_count += 1
	plan.diagnostics["industry_support_count"] = support_count
	plan.diagnostics["industry_support_omitted_count"] = support_omitted_count
	return {"area": total_area, "support_count": support_count,
		"support_omitted_count": support_omitted_count}

func _add_industry_support_mass(poly: PackedVector2Array, tangent: Vector2,
		key: String, family: String, apron_polys: Array,
		blocked_exclusions: Array, footprint: PackedVector2Array,
		shadow_entries: Array, block_entries: Array) -> bool:
	if not _poly_fully_inside_any(poly, apron_polys):
		return false
	if _polys_overlap_area(poly, footprint) > 0.001:
		return false
	for exclusion_value in blocked_exclusions:
		var exclusion: Dictionary = exclusion_value
		if _bbox(poly).intersects(exclusion.bb) and \
				_polys_overlap_area(poly, exclusion.poly) > 0.001:
			return false
	if _poly_overlaps_active_plan_water(poly) > 0.001:
		return false
	if _poly_overlaps_active_relief(poly) > 0.001:
		return false
	var shadow_poly := _offset(poly, BLOCK_SHADOW_OFFSET)
	if not _poly_fully_inside_any(shadow_poly, apron_polys):
		return false
	if _polys_overlap_area(shadow_poly, footprint) > 0.001:
		return false
	for exclusion_value in blocked_exclusions:
		var exclusion: Dictionary = exclusion_value
		if _bbox(shadow_poly).intersects(exclusion.bb) and \
				_polys_overlap_area(shadow_poly, exclusion.poly) > 0.001:
			return false
	if _poly_overlaps_active_plan_water(shadow_poly) > 0.001:
		return false
	if _poly_overlaps_active_relief(shadow_poly) > 0.001:
		return false
	shadow_entries.append({
		"poly": shadow_poly,
		"color": Color(MapMidcenturyStyle.SHADOW, 0.68),
	})
	var top := MapMidcenturyStyle.gameplay_block_top(family).lerp(
		MapMidcenturyStyle.URBAN_EDGE[0], 0.42)
	block_entries.append({"poly": poly, "color": top,
		"kind": "industry_support"})
	_append_ring(_block_edges, poly)
	var center := _poly_center(poly)
	var axis := tangent.normalized()
	_append_safe_roof_mark(center - axis * 4.0, center + axis * 4.0, key)
	_metrics.blocks = int(_metrics.blocks) + 1
	_active_plan.masses.append({
		"key": key, "poly": poly.duplicate(), "role": "industry-support",
	})
	_active_plan.visual_shadows.append({"key": key, "poly": shadow_poly.duplicate(),
		"role": "industry-support"})
	return true

func _poly_projected_half_extent(poly: PackedVector2Array, center: Vector2,
		axis: Vector2) -> float:
	var extent := 0.0
	for point in poly:
		extent = maxf(extent, absf((point - center).dot(axis)))
	return extent

func _oriented_rect_poly(center: Vector2, tangent: Vector2, normal: Vector2,
		length: float, depth: float) -> PackedVector2Array:
	var t := tangent.normalized() * length * 0.5
	var n := normal.normalized() * depth * 0.5
	return PackedVector2Array([center - t - n, center + t - n,
		center + t + n, center - t + n])

func _poly_fully_inside(poly: PackedVector2Array,
		container: PackedVector2Array) -> bool:
	var intersection_area := _polys_overlap_area(poly, container)
	return intersection_area >= _poly_area(poly) - 0.05

func _poly_fully_inside_any(poly: PackedVector2Array, containers: Array) -> bool:
	for container_value in containers:
		if _poly_fully_inside(poly, container_value as PackedVector2Array):
			return true
	return false

func _polys_overlap_area(a: PackedVector2Array,
		b: PackedVector2Array) -> float:
	var area := 0.0
	for intersection_value in Geometry2D.intersect_polygons(a, b):
		area += _poly_area(intersection_value as PackedVector2Array)
	return area

func _plan_massing_records(plan: SettlementPlan) -> Array:
	var out: Array = []
	for parcel_value in plan.parcels:
		var parcel: Dictionary = parcel_value
		if str(parcel.role) != "built":
			out.append(parcel)
			continue
		var groups := _silkstown_subdivide_frontage_group(parcel.poly,
			str(parcel.key), 0)
		for i in groups.size():
			var group_record := parcel.duplicate(true)
			group_record.key = "%s|frontage|%d" % [str(parcel.key), i]
			group_record.poly = groups[i]
			out.append(group_record)
	return out

func _silkstown_subdivide_frontage_group(poly: PackedVector2Array,
		key: String, depth: int) -> Array:
	var area := _poly_area(poly)
	var target := _rr("%s|frontage-target" % key, 3600.0, 5000.0)
	if area <= target or depth >= 2:
		return [poly]
	var edge_index := _hero_longest_edge(poly)
	var edge_a := poly[edge_index]
	var edge_b := poly[(edge_index + 1) % poly.size()]
	var frontage := (edge_b - edge_a).normalized()
	if frontage == Vector2.ZERO:
		return [poly]
	var split_axis := Vector2(-frontage.y, frontage.x)
	var center := _poly_center(poly)
	center += frontage * _rr("%s|frontage-shift" % key, -0.10, 0.10) * sqrt(area)
	var span := _bbox(poly).size.length() + 18.0
	var corridor := _segment_quad(center - split_axis * span,
		center + split_axis * span, 1.35)
	var pieces := _hero_clip_polys([poly], [{"poly": corridor, "bb": _bbox(corridor)}],
		620.0)
	if pieces.size() < 2:
		return [poly]
	_hero_record_alley(poly, corridor, split_axis)
	var out: Array = []
	for i in pieces.size():
		out.append_array(_silkstown_subdivide_frontage_group(pieces[i],
			"%s|%d" % [key, i], depth + 1))
	return out

func _morph_profile_for_tile(tile_data: Dictionary, named_count: int) -> String:
	var tile_id := str(tile_data.get("id", ""))
	if _explicit_profiles.has(tile_id):
		match str(_explicit_profiles[tile_id]):
			"metro":
				return MORPH_PROFILE_METRO
			"small_town":
				return MORPH_PROFILE_SMALL_TOWN
			"town":
				return MORPH_PROFILE_TOWN
			"industrial_fringe":
				return MORPH_PROFILE_FRINGE
			"suburban_edge":
				return "suburban_edge"
			"rural":
				return MORPH_PROFILE_RURAL
			_:
				return MORPH_PROFILE_VILLAGE
	var name := str(tile_data.get("nickname", "")).to_lower()
	if name == "":
		# A blank label does not make an authoritative urban tile rural. It still
		# contributes a compact road-led neighbourhood to its wider settlement.
		return MORPH_PROFILE_VILLAGE
	if (name.contains("industrial zone") or name.contains("works")
			or name.contains("foundry") or name.contains("docks")
			or name.contains("wharf")):
		return MORPH_PROFILE_FRINGE
	if (str(tile_data.get("road_density", "")) == "dense" or named_count >= 6
			or name.contains("capital port") or name.contains("patran city")):
		return MORPH_PROFILE_METRO
	if named_count >= 2 or name.contains("city") or name.contains("port") or name.contains("old quarter"):
		return MORPH_PROFILE_TOWN
	return MORPH_PROFILE_VILLAGE

func _morph_edge_properties(specs: Array, road_segments: Array) -> Dictionary:
	var records: Array = []
	var internal_keys: Dictionary = {}
	var crossed_count := 0
	var internal_crossed_count := 0
	var water_count := 0
	var external_types: Dictionary = {}
	var participating: Dictionary = {}
	var ids_by_coord: Dictionary = {}
	for spec_value in specs:
		var spec: Dictionary = spec_value
		if str(spec.profile) != MORPH_PROFILE_RURAL:
			participating[spec.coord] = true
			ids_by_coord[spec.coord] = str(spec.id)
	for spec_value in specs:
		var spec: Dictionary = spec_value
		if not participating.has(spec.coord):
			continue
		var neighbors: Array[Vector2i] = _terrain.call("neighbor_coords", spec.coord)
		for edge_index in HEX_VERTS.size():
			var a: Vector2 = spec.center + HEX_VERTS[edge_index]
			var b: Vector2 = spec.center + HEX_VERTS[(edge_index + 1) % HEX_VERTS.size()]
			var neighbor: Vector2i = neighbors[edge_index]
			var internal := participating.has(neighbor)
			var crossed := _morph_edge_has_authoritative_road(a, b, road_segments)
			var external_type := ""
			if not internal:
				external_type = "sea"
				if _terrain.tiles.has(neighbor):
					external_type = str((_terrain.tiles[neighbor] as Dictionary).get("type", "rural"))
				external_types[external_type] = int(external_types.get(external_type, 0)) + 1
			var water_adjacent := external_type in ["sea", "deep_sea"] or _morph_edge_touches_water(a, b)
			if internal:
				var pair := [str(spec.id), str(ids_by_coord.get(neighbor, "%d_%d" % [neighbor.x, neighbor.y]))]
				pair.sort()
				internal_keys["%s|%s" % pair] = true
			if crossed:
				crossed_count += 1
				if internal:
					internal_crossed_count += 1
			if water_adjacent:
				water_count += 1
			records.append({
				"tile_id": str(spec.id),
				"edge_index": edge_index,
				"neighbor_id": str(ids_by_coord.get(neighbor, "")),
				"internal_to_same_settlement": internal,
				"crossed_by_authoritative_road": crossed,
				"external_terrain_type": external_type,
				"water_adjacent": water_adjacent,
			})
	return {
		"records": records,
		"internal_edge_count": internal_keys.size(),
		"internal_edge_sides": records.filter(func(record: Dictionary) -> bool:
			return bool(record.internal_to_same_settlement)).size(),
		"crossed_by_authoritative_road": crossed_count,
		"internal_crossed_by_authoritative_road": internal_crossed_count / 2,
		"external_terrain_type": external_types,
		"water_adjacent": water_count,
	}

func _morph_edge_touches_water(a: Vector2, b: Vector2) -> bool:
	var nav := NavGrid.instance()
	if not nav.is_ready():
		return false
	for t in [0.2, 0.5, 0.8]:
		var cell := nav.cell_of(a.lerp(b, float(t)))
		if nav.water(cell.x, cell.y) != NavGrid.WATER_LAND:
			return true
	return false

func _morph_district_field(specs: Array, road_segments: Array,
		component_key: String) -> Dictionary:
	# Settlement extent is a union of irregular influence cells. The cells begin
	# at a road-rich focus in every urban tile, then lean toward actual crossings.
	# Neither the tile hex nor a buffered road becomes an outer boundary.
	var cells: Array = []
	var field_tiles: Dictionary = {}
	var spec_by_coord: Dictionary = {}
	for spec_value in specs:
		var spec: Dictionary = spec_value
		spec_by_coord[spec.coord] = spec
	for spec_value in specs:
		var spec: Dictionary = spec_value
		var context := _morph_tile_road_context(spec, road_segments,
			"%s|%s" % [component_key, str(spec.id)])
		var radius := _morph_core_radius(str(spec.profile), float(context.road_richness))
		var core := _morph_organic_field_cell(context.position, context.tangent,
			radius * (1.08 + float(context.road_richness) * 0.10),
			radius * 0.78, "%s|%s|core" % [component_key, str(spec.id)])
		cells.append(core)
		field_tiles[str(spec.id)] = {
			"id": str(spec.id), "coord": spec.coord, "center": spec.center,
			"profile": str(spec.profile), "core_position": context.position,
			"core_tangent": context.tangent, "core_radius": radius,
			"core_poly": core, "road_richness": float(context.road_richness),
			"road_segment_count": int(context.road_segment_count),
			"spill_destinations": [],
		}

	# The crossing lobes are directional urban pressure, not shared-edge strips.
	# Only authoritative road crossings can connect neighbouring cores or carry a
	# limited lobe into actual rural land.
	for spec_value in specs:
		var spec: Dictionary = spec_value
		var field_tile: Dictionary = field_tiles[str(spec.id)]
		var neighbors: Array[Vector2i] = _terrain.call("neighbor_coords", spec.coord)
		for edge_index in HEX_VERTS.size():
			var a: Vector2 = spec.center + HEX_VERTS[edge_index]
			var b: Vector2 = spec.center + HEX_VERTS[(edge_index + 1) % HEX_VERTS.size()]
			var crossing := _morph_authoritative_crossing(a, b, road_segments)
			if crossing == Vector2.INF:
				continue
			var neighbor: Vector2i = neighbors[edge_index]
			var internal := spec_by_coord.has(neighbor)
			var rural_spill := false
			var spill_id := ""
			if not internal and _terrain.tiles.has(neighbor):
				var neighbor_data: Dictionary = _terrain.tiles[neighbor]
				rural_spill = str(neighbor_data.get("type", "")) == "rural"
				spill_id = str(neighbor_data.get("id", ""))
			if not internal and not rural_spill:
				continue
			var core_position: Vector2 = field_tile.core_position
			var direction := (crossing - core_position).normalized()
			if direction == Vector2.ZERO:
				direction = (crossing - spec.center).normalized()
			if direction == Vector2.ZERO:
				continue
			var reach := core_position.distance_to(crossing)
			var pull_center := core_position.lerp(crossing, 0.62)
			cells.append(_morph_organic_field_cell(pull_center, direction,
				clampf(reach * 0.38, 58.0, 92.0),
				clampf(float(field_tile.core_radius) * 0.38, 42.0, 62.0),
				"%s|%s|pull|%d" % [component_key, str(spec.id), edge_index]))
			cells.append(_morph_organic_field_cell(crossing, direction,
				58.0 if internal else 50.0, 48.0 if internal else 40.0,
				"%s|%s|crossing|%d" % [component_key, str(spec.id), edge_index]))
			if rural_spill:
				var outward: Vector2 = (_terrain.map_to_local(
					_terrain.map_coord_for_tile_coord(neighbor)) - spec.center).normalized()
				var spill_center: Vector2 = crossing + outward * 48.0
				cells.append(_morph_organic_field_cell(spill_center, direction,
					62.0, 43.0, "%s|%s|spill|%d" % [component_key,
					str(spec.id), edge_index]))
				(field_tile.spill_destinations as Array).append(spill_id)
		field_tile.spill_destinations.sort()
		field_tiles[str(spec.id)] = field_tile

	# Core-only union, kept for the minimum-retention gate.  The coastal cells are
	# added on top of it, so the reach extent is a strict superset by construction
	# and any per-tile shortfall after the identical downstream clip is a real
	# defect rather than a tuning artefact.
	var base_polys := _hero_merge_polys(cells)

	# Coastal reach.  Real cities build up to their waterfront; the field stops
	# short of it because only authoritative road crossings can pull the extent
	# outward and a shoreline edge never carries one.  For every hex edge whose
	# samples fall on open water (sea or lake — rivers keep their own bank
	# treatment and are deliberately excluded) march from the core to the actual
	# shoreline and lay the accepted organic cell twice: a spur closing the gap,
	# and a shore-parallel frontage straddling the water line.
	var coast_bearings := 0
	var coast_tiles := 0
	for spec_value in specs:
		var spec: Dictionary = spec_value
		var field_tile: Dictionary = field_tiles[str(spec.id)]
		var core_position: Vector2 = field_tile.core_position
		var core_radius := float(field_tile.core_radius)
		var tile_bearings := 0
		var tile_coastal_bearings: Array = []
		for edge_index in HEX_VERTS.size():
			var a: Vector2 = spec.center + HEX_VERTS[edge_index]
			var b: Vector2 = spec.center + HEX_VERTS[(edge_index + 1) % HEX_VERTS.size()]
			if not _morph_edge_touches_open_water(a, b):
				continue
			var direction := ((a + b) * 0.5 - core_position).normalized()
			if direction == Vector2.ZERO:
				continue
			var shore := _morph_open_water_distance(core_position, direction)
			if shore < 0.0:
				continue
			var frontage_half := clampf(core_radius * MORPH_COAST_FRONT_SPAN, 56.0, 92.0)
			var reach := shore
			if reach <= core_radius + MORPH_COAST_MIN_GAP:
				continue
			var spur_start := core_position + direction * (core_radius * MORPH_COAST_SPUR_START)
			var spur_end := core_position + direction * (reach + MORPH_COAST_OVERSHOOT)
			var spur_half := spur_start.distance_to(spur_end) * 0.5
			if spur_half <= 1.0:
				continue
			cells.append(_morph_organic_field_cell(spur_start.lerp(spur_end, 0.5),
				direction, spur_half, clampf(core_radius * 0.52, 48.0, 96.0),
				"%s|%s|coast-spur|%d" % [component_key, str(spec.id), edge_index]))
			var shore_normal := Vector2(-direction.y, direction.x)
			cells.append(_morph_organic_field_cell(
				core_position + direction * maxf(0.0, reach - MORPH_COAST_FRONT_INSET),
				shore_normal, frontage_half, MORPH_COAST_FRONT_DEPTH,
				"%s|%s|coast-front|%d" % [component_key, str(spec.id), edge_index]))
			tile_coastal_bearings.append({
				"direction": direction,
				"reach": reach + MORPH_COAST_OVERSHOOT,
				"frontage_half_width": frontage_half,
			})
			tile_bearings += 1
			coast_bearings += 1
		field_tile["coastal_bearings"] = tile_coastal_bearings
		field_tile["coastal_reach_bearings"] = tile_bearings
		field_tiles[str(spec.id)] = field_tile
		if tile_bearings > 0:
			coast_tiles += 1
	return {
		"polys": _hero_merge_polys(cells),
		"base_polys": base_polys,
		"tiles": field_tiles,
		"coast_bearings": coast_bearings,
		"coast_tiles": coast_tiles,
	}

## True when a hex edge runs along open water — sea or lake.  Rivers are
## deliberately excluded: they keep the existing bank and casing treatment, and
## the owner's direction is about the sea and the lake.
func _morph_edge_touches_open_water(a: Vector2, b: Vector2) -> bool:
	var nav := NavGrid.instance()
	if not nav.is_ready():
		return false
	for i in MORPH_COAST_EDGE_SAMPLES:
		var t := float(i + 1) / float(MORPH_COAST_EDGE_SAMPLES + 1)
		var cell := nav.cell_of(a.lerp(b, t))
		var kind := nav.water(cell.x, cell.y)
		if kind == NavGrid.WATER_SEA or kind == NavGrid.WATER_LAKE:
			return true
	return false

## Growth intensity floor inside a coastal wedge.  Intensity is what makes the
## fabric fine grained: it shrinks the subdivision target and raises the built
## share of the role ballot.  The default field decays with distance from the
## core, so simply enlarging the extent seaward hands the new land to the sparse
## tail — measured on the extent-only variant as coarse floating slabs, road
## frontage occupancy 97.5 -> 80.6 on Vandel, and rendered greens 412 -> 473.
## Treating a waterfront as core-grade instead is both the truer reading of a
## port and the only way the new area resolves into small buildings.
func _morph_coastal_intensity(point: Vector2, tile: Dictionary) -> float:
	var bearings: Array = tile.get("coastal_bearings", [])
	if bearings.is_empty():
		return 0.0
	var offset := point - (tile.core_position as Vector2)
	var best := 0.0
	for bearing_value in bearings:
		var bearing: Dictionary = bearing_value
		var direction: Vector2 = bearing.direction
		var along := offset.dot(direction)
		if along <= 0.0:
			continue
		var lateral := absf(offset.dot(Vector2(-direction.y, direction.x)))
		var lateral_falloff := clampf(1.0 - lateral / maxf(1.0,
			float(bearing.frontage_half_width) * MORPH_COAST_WEDGE_SPREAD), 0.0, 1.0)
		if lateral_falloff <= 0.0:
			continue
		var overrun := maxf(0.0, along - float(bearing.reach))
		var along_falloff := clampf(1.0 - overrun / MORPH_COAST_TAIL_DEPTH, 0.0, 1.0)
		best = maxf(best, MORPH_COAST_INTENSITY_TARGET * lateral_falloff * along_falloff)
	return best

## Distance from `origin` along `direction` to the first open-water cell, or -1
## when none is found inside the probe limit.  Read-only against the nav grid.
func _morph_open_water_distance(origin: Vector2, direction: Vector2) -> float:
	var nav := NavGrid.instance()
	if not nav.is_ready():
		return -1.0
	var travelled := MORPH_COAST_PROBE_STEP
	while travelled <= MORPH_COAST_PROBE_LIMIT:
		var cell := nav.cell_of(origin + direction * travelled)
		var kind := nav.water(cell.x, cell.y)
		if kind == NavGrid.WATER_SEA or kind == NavGrid.WATER_LAKE:
			return travelled
		travelled += MORPH_COAST_PROBE_STEP
	return -1.0

## Minimum-retention gate for the coastal reach, measured in the same run that
## draws it.  The core-only union is clipped by the identical exclusion set and
## compared per tile against the reach union.  The reach union is a superset
## before clipping, so every tile must retain at least its core-only usable
## area; a ratio below one means the new geometry has subtracted envelope, which
## is precisely the silent-emptying failure the relief investigation caught.
func _morph_record_coastal_reach(component_key: String, district_field: Dictionary,
		envelopes: Array, natural_exclusions: Array) -> void:
	if not _metrics.has("coastal_reach"):
		_metrics.coastal_reach = {
			"bearing_count": 0, "tile_count": 0, "component_count": 0,
			"retention_failure_count": 0, "minimum_retention": 1.0,
			"reach_area_gain": 0.0, "tiles": {},
		}
	var summary: Dictionary = _metrics.coastal_reach
	var bearings := int(district_field.get("coast_bearings", 0))
	summary.bearing_count = int(summary.bearing_count) + bearings
	summary.tile_count = int(summary.tile_count) + int(district_field.get("coast_tiles", 0))
	if bearings > 0:
		summary.component_count = int(summary.component_count) + 1
	var base_polys: Array = district_field.get("base_polys", [])
	var base_clipped := _hero_clip_polys(base_polys, natural_exclusions,
		MORPH_FACE_MIN_AREA)
	var field_tiles: Dictionary = district_field.get("tiles", {})
	var tile_ids: Array = field_tiles.keys()
	tile_ids.sort()
	for tile_id_value in tile_ids:
		var tile_id := str(tile_id_value)
		var tile: Dictionary = field_tiles[tile_id]
		var center: Vector2 = tile.center
		var base_area := _morph_polys_area_in_hex(base_clipped, center)
		var reach_area := _morph_polys_area_in_hex(envelopes, center)
		var retention := 1.0 if base_area <= 1.0 else reach_area / base_area
		if retention < MORPH_COAST_MIN_RETENTION - 0.001:
			summary.retention_failure_count = int(summary.retention_failure_count) + 1
		summary.minimum_retention = minf(float(summary.minimum_retention), retention)
		summary.reach_area_gain = float(summary.reach_area_gain) + (reach_area - base_area)
		(summary.tiles as Dictionary)[tile_id] = {
			"component": component_key,
			"coastal_reach_bearings": int(tile.get("coastal_reach_bearings", 0)),
			"core_only_usable_area": base_area,
			"usable_area": reach_area,
			"retention": retention,
		}
	_metrics.coastal_reach = summary

## Envelope area falling inside one tile hex.  Used by the coastal-reach
## minimum-retention gate.
func _morph_polys_area_in_hex(polys: Array, center: Vector2) -> float:
	var hex := PackedVector2Array()
	for vertex in HEX_VERTS:
		hex.append(center + vertex)
	var area := 0.0
	for poly_value in polys:
		for piece_value in Geometry2D.intersect_polygons(poly_value, hex):
			area += _poly_area(piece_value)
	return area

func _register_urban_audit_component(component_key: String, specs: Array,
		field_polys: Array, parcel_records: Array, masses: Array, roads: Array,
		core_tiles: Dictionary, constraints: Dictionary) -> void:
	var parcels: Array = []
	for value in parcel_records:
		if value is PackedVector2Array:
			parcels.append(value)
		elif value is Dictionary:
			var record: Dictionary = value
			var poly: PackedVector2Array = record.get("poly", PackedVector2Array())
			if poly.size() >= 3:
				parcels.append(poly)
	var normalized_roads: Array = []
	for value in roads:
		var road: Dictionary = value
		var a: Vector2 = road.get("a", Vector2.ZERO)
		var b: Vector2 = road.get("b", Vector2.ZERO)
		if a == b:
			continue
		normalized_roads.append({
			"a": a, "b": b, "trunk": bool(road.get("trunk", false)),
			"edge_id": str(road.get("edge_id", "legacy:%s" % component_key)),
		})
	_urban_audit_components.append({
		"key": component_key,
		"specs": specs.duplicate(true),
		"field_polys": field_polys.duplicate(true),
		"parcel_polys": parcels,
		"masses": masses.duplicate(true),
		"roads": normalized_roads,
		"core_tiles": core_tiles.duplicate(true),
		"constraints": constraints.duplicate(true),
	})

func _dense_core_radius(profile: String) -> float:
	match profile:
		MORPH_PROFILE_METRO:
			return 86.0
		MORPH_PROFILE_TOWN:
			return 80.0
		MORPH_PROFILE_FRINGE:
			return 74.0
		_:
			return 68.0

func _ensure_universal_dense_cores(parcel_entries: Array,
		shadow_entries: Array, block_entries: Array) -> void:
	var components := _urban_audit_components.duplicate()
	components.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.key) < str(b.key))
	for component_value in components:
		var component: Dictionary = component_value
		var specs: Array = component.specs.duplicate()
		specs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return str(a.id) < str(b.id))
		for spec_value in specs:
			var spec: Dictionary = spec_value
			var profile := str(spec.profile)
			var tile_poly := PackedVector2Array()
			for vertex in HEX_VERTS:
				tile_poly.append((spec.center as Vector2) + vertex)
			var exclusions := _dense_core_base_exclusions(component, tile_poly)
			var field_inside := _audit_intersections(component.field_polys, tile_poly)
			field_inside = _hero_clip_polys(field_inside, exclusions, 1.0)
			if field_inside.is_empty():
				continue
			var structure := _audit_road_structure(spec.coord, tile_poly)
			var candidates := _audit_rank_core_candidates(spec, structure,
				field_inside, "%s|dense-core|%s" % [str(component.key), str(spec.id)])
			var radius := _dense_core_radius(profile)
			var selected: Dictionary = {}
			var best_progress := -INF
			var attempted_positions: Array = []
			for candidate_value in candidates.slice(0, mini(12, candidates.size())):
				var candidate: Dictionary = candidate_value
				var trial := _dense_core_candidate_plan(component, spec, field_inside,
					exclusions, structure, candidate.position, radius)
				var required_count := int(trial.required_count)
				var required_coverage := float(trial.required_coverage)
				var projected_count := int(trial.existing_count) + \
					(trial.layout as Array).size()
				var projected_coverage := 100.0 * (float(trial.existing_area) +
					float(trial.layout_area)) / maxf(1.0, float(trial.core_area))
				attempted_positions.append({
					"position": candidate.position,
					"score": float(candidate.score),
					"raw_influence": float(candidate.raw_influence),
					"usable_land_score": float(candidate.usable_land_score),
					"junction_degree": int(candidate.junction_degree),
					"buildable_core_zone_area": float(trial.core_area),
					"existing_mass_count": int(trial.existing_count),
					"existing_built_coverage": 100.0 * float(trial.existing_area) /
						maxf(1.0, float(trial.core_area)),
					"projected_mass_count": projected_count,
					"projected_built_coverage": projected_coverage,
				})
				var meets := projected_count >= required_count and (
					required_coverage <= 0.0 or projected_coverage >= required_coverage)
				var progress := float(projected_count) / maxf(1.0,
					float(required_count))
				if required_coverage > 0.0:
					progress += projected_coverage / required_coverage
				if meets:
					selected = trial
					break
				if progress > best_progress:
					best_progress = progress
					selected = trial
			if selected.is_empty():
				continue
			var core_tiles: Dictionary = component.core_tiles
			var core_tile: Dictionary = core_tiles.get(str(spec.id), {
				"id": str(spec.id), "coord": spec.coord, "center": spec.center,
				"profile": profile, "core_position": selected.position,
				"core_radius": radius, "spill_destinations": []})
			core_tile["audit_core_position"] = selected.position
			core_tile["audit_core_radius"] = radius
			core_tile["attempted_core_positions"] = attempted_positions
			core_tiles[str(spec.id)] = core_tile
			component.core_tiles = core_tiles
			var current_count := int(selected.existing_count)
			var current_area := float(selected.existing_area)
			var target_count := int(selected.required_count)
			var target_coverage := float(selected.required_coverage)
			var core_area := float(selected.core_area)
			for layout_value in selected.layout:
				if current_count >= target_count and (target_coverage <= 0.0 or
						100.0 * current_area / maxf(1.0, core_area) >= target_coverage):
					break
				var layout: Dictionary = layout_value
				var mass: PackedVector2Array = layout.poly
				var lot: PackedVector2Array = layout.get("lot", mass)
				parcel_entries.append({"poly": lot,
					"color": MapMidcenturyStyle.PAPER, "role": "core_lot"})
				(component.parcel_polys as Array).append(lot.duplicate())
				_metrics.parcels = int(_metrics.parcels) + 1
				var before := _decorative_mass_records.size()
				_add_dense_core_block(mass, layout.tangent, 0.90,
					"%s|dense-core|%s|%d" % [str(component.key), str(spec.id),
						current_count], shadow_entries, block_entries, "", profile)
				if _decorative_mass_records.size() <= before:
					continue
				var added: Dictionary = _decorative_mass_records[-1]
				(component.masses as Array).append(added.duplicate(true))
				current_count += 1
				current_area += _hero_polys_area(_audit_intersections(
					[added.poly], selected.core_zone))

func _dense_core_terrace_refine(component: Dictionary, spec: Dictionary,
		selected: Dictionary, parcel_entries: Array, shadow_entries: Array,
		block_entries: Array) -> void:
	var target_count := int(selected.required_count)
	for pass_index in 3:
		var stats := _dense_core_mass_stats(component.masses,
			selected.core_available)
		if int(stats.count) >= target_count:
			return
		var ranked: Array = []
		for mass_value in component.masses:
			var mass: Dictionary = mass_value
			var overlap := _hero_polys_area(_audit_intersections([mass.poly],
				selected.core_zone))
			if overlap >= 36.0:
				ranked.append({"mass": mass, "overlap": overlap})
		ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.overlap) > float(b.overlap))
		if ranked.is_empty():
			return
		var target: Dictionary = (ranked[0] as Dictionary).mass
		var needed := maxi(2, target_count - int(stats.count) + 1)
		var pieces := _dense_core_terrace_pieces(target.poly, needed,
			"%s|terrace|%s|%d" % [str(component.key), str(spec.id), pass_index])
		if pieces.size() < 2:
			return
		_dense_core_remove_mass_visual(target, component, shadow_entries,
			block_entries)
		for piece_index in pieces.size():
			var poly: PackedVector2Array = pieces[piece_index]
			parcel_entries.append({"poly": poly,
				"color": MapMidcenturyStyle.PAPER, "role": "terrace_lot"})
			(component.parcel_polys as Array).append(poly.duplicate())
			_metrics.parcels = int(_metrics.parcels) + 1
			var edge := _hero_longest_edge(poly)
			var tangent := (poly[(edge + 1) % poly.size()] - poly[edge]).normalized()
			var before := _decorative_mass_records.size()
			_add_dense_core_block(poly, tangent, 0.90,
				"%s|terrace|%s|%d|%d" % [str(component.key), str(spec.id),
				pass_index, piece_index], shadow_entries, block_entries, "",
				str(spec.profile))
			if _decorative_mass_records.size() > before:
				(component.masses as Array).append(
					_decorative_mass_records[-1].duplicate(true))

func _add_dense_core_block(poly: PackedVector2Array, tangent: Vector2,
		density: float, key: String, shadow_entries: Array, block_entries: Array,
		color_cluster: String, roof_context: String) -> void:
	# The caller has already clipped both the top and shadow to authoritative
	# usable street faces.  Do not reapply the coarser raster land oracle here.
	var shadow_poly := _offset(poly, BLOCK_SHADOW_OFFSET)
	shadow_entries.append({"poly": shadow_poly,
		"color": MapMidcenturyStyle.SHADOW})
	_decorative_mass_records.append({"key": key, "poly": poly.duplicate()})
	var top := MapMidcenturyStyle.urban_block(key, density)
	if color_cluster != "":
		top = MapMidcenturyStyle.urban_block_cluster(color_cluster, key, density)
	block_entries.append({"poly": poly, "color": top, "kind": "core"})
	_append_ring(_block_edges, poly)
	_metrics.blocks = int(_metrics.blocks) + 1
	var center := _poly_center(poly)
	var axis := tangent.normalized()
	if axis == Vector2.ZERO:
		axis = Vector2.RIGHT
	if RoadHash.pick("mc-core-roof|%s" % key, 100) < 16:
		var half := clampf(sqrt(_poly_area(poly)) * 0.13, 2.2, 5.0)
		_append_safe_roof_mark(center - axis * half, center + axis * half, key)

func _dense_core_terrace_pieces(poly: PackedVector2Array, desired: int,
		key: String) -> Array:
	var edge := _hero_longest_edge(poly)
	var axis := (poly[(edge + 1) % poly.size()] - poly[edge]).normalized()
	if axis == Vector2.ZERO:
		return []
	var normal := Vector2(-axis.y, axis.x)
	var minimum := INF
	var maximum := -INF
	for point in poly:
		minimum = minf(minimum, point.dot(axis))
		maximum = maxf(maximum, point.dot(axis))
	var span := maximum - minimum
	var divisions := clampi(desired, 2, 7)
	var cuts: Array = []
	var reach := _bbox(poly).size.length() + 16.0
	for cut_index in range(1, divisions):
		var offset := lerpf(minimum, maximum,
			float(cut_index) / float(divisions))
		offset += _rr("%s|cut|%d" % [key, cut_index], -0.035, 0.035) * span
		var center := axis * offset + normal * _poly_center(poly).dot(normal)
		var cut := _segment_quad(center - normal * reach,
			center + normal * reach, 1.45)
		cuts.append({"poly": cut, "bb": _bbox(cut)})
	var split := _hero_clip_polys([poly], cuts, 14.0)
	var out: Array = []
	for split_value in split:
		for inset_value in _hero_inset_polys(split_value, 1.05):
			var piece: PackedVector2Array = inset_value
			if _poly_area(piece) < 14.0:
				continue
			var shadow := _offset(piece, BLOCK_SHADOW_OFFSET)
			if not _poly_on_dry_land(piece) or not _poly_on_dry_land(shadow) or \
					_poly_overlaps_active_plan_water(piece) > 0.001 or \
					_poly_overlaps_active_plan_water(shadow) > 0.001:
				continue
			out.append(piece)
	return out

func _dense_core_refine_existing(component: Dictionary, spec: Dictionary,
		selected: Dictionary, parcel_entries: Array, shadow_entries: Array,
		block_entries: Array) -> void:
	var target_count := int(selected.required_count)
	var target_coverage := float(selected.required_coverage)
	var core_area := float(selected.core_area)
	if core_area <= 0.01:
		return
	for pass_index in 3:
		var stats := _dense_core_mass_stats(component.masses,
			selected.core_available)
		var coverage := 100.0 * float(stats.area) / core_area
		if int(stats.count) >= target_count and (target_coverage <= 0.0 or
				coverage >= target_coverage):
			return
		var needs_count := int(stats.count) < target_count
		var needs_coverage := target_coverage > 0.0 and coverage < target_coverage
		var ranked: Array = []
		for mass_value in component.masses:
			var mass: Dictionary = mass_value
			var overlap := _hero_polys_area(_audit_intersections([mass.poly],
				selected.core_zone))
			if overlap < 24.0:
				continue
			ranked.append({"mass": mass, "overlap": overlap})
		ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.overlap) > float(b.overlap))
		var refined := false
		for ranked_value in ranked:
			var target: Dictionary = ranked_value.mass
			var other_exclusions: Array = []
			for other_value in component.masses:
				var other: Dictionary = other_value
				if other == target:
					continue
				other_exclusions.append({"poly": other.poly,
					"bb": _bbox(other.poly)})
			var pieces := _dense_core_refined_mass_pieces(target.poly,
				selected.core_available, other_exclusions, needs_count,
				needs_coverage,
				"%s|core-refine|%s|%d" % [str(component.key), str(spec.id),
				pass_index])
			if pieces.size() < 2:
				continue
			_dense_core_remove_mass_visual(target, component, shadow_entries,
				block_entries)
			for piece_index in pieces.size():
				var poly: PackedVector2Array = pieces[piece_index]
				parcel_entries.append({"poly": poly,
					"color": MapMidcenturyStyle.PAPER, "role": "core_refine_lot"})
				(component.parcel_polys as Array).append(poly.duplicate())
				_metrics.parcels = int(_metrics.parcels) + 1
				var edge := _hero_longest_edge(poly)
				var tangent := (poly[(edge + 1) % poly.size()] - poly[edge]).normalized()
				var before := _decorative_mass_records.size()
				_add_block(poly, tangent, 0.90,
					"%s|core-refine|%s|%d|%d" % [str(component.key),
					str(spec.id), pass_index, piece_index], shadow_entries,
					block_entries, "", str(spec.profile))
				if _decorative_mass_records.size() > before:
					(component.masses as Array).append(
						_decorative_mass_records[-1].duplicate(true))
			refined = true
			break
		if not refined:
			return

func _dense_core_refined_mass_pieces(poly: PackedVector2Array,
		containers: Array, other_exclusions: Array, needs_count: bool,
		needs_coverage: bool, key: String) -> Array:
	var center := _poly_center(poly)
	var scale := 1.0
	if needs_coverage:
		scale = 1.78
	var scaled := _scale_poly(poly, center, scale)
	var grown := _audit_intersections([scaled], containers)
	grown = _hero_clip_polys(grown, other_exclusions, 24.0)
	var cuts: Array = []
	var reach := _bbox(poly).size.length() * 1.2 + 16.0
	var cut_count := 2 if needs_count else 1
	for cut_index in cut_count:
		var angle := TAU * float(cut_index) / float(cut_count) + _rr(
			"%s|cut|%d" % [key, cut_index], -0.13, 0.13)
		var direction := Vector2.RIGHT.rotated(angle)
		var cut := _segment_quad(center - direction * reach,
			center + direction * reach, 1.55)
		cuts.append({"poly": cut, "bb": _bbox(cut)})
	var split := _hero_clip_polys(grown, cuts, 20.0)
	var out: Array = []
	for split_value in split:
		for inset_value in _hero_inset_polys(split_value, 4.2):
			var piece: PackedVector2Array = inset_value
			if _poly_area(piece) < 16.0:
				continue
			var shadow := _offset(piece, BLOCK_SHADOW_OFFSET)
			if not _poly_fully_inside_any(shadow, containers) or \
					not _poly_on_dry_land(piece) or not _poly_on_dry_land(shadow) or \
					_poly_overlaps_active_plan_water(piece) > 0.001 or \
					_poly_overlaps_active_plan_water(shadow) > 0.001 or \
					_poly_overlaps_active_relief(piece) > 0.001 or \
					_poly_overlaps_active_relief(shadow) > 0.001:
				continue
			out.append(piece)
	return out

func _dense_core_remove_mass_visual(target: Dictionary, component: Dictionary,
		shadow_entries: Array, block_entries: Array) -> void:
	var poly: PackedVector2Array = target.poly
	var shadow := _offset(poly, BLOCK_SHADOW_OFFSET)
	for index in range(block_entries.size() - 1, -1, -1):
		if _dense_core_same_poly((block_entries[index] as Dictionary).poly, poly):
			block_entries.remove_at(index)
			break
	for index in range(shadow_entries.size() - 1, -1, -1):
		if _dense_core_same_poly((shadow_entries[index] as Dictionary).poly, shadow):
			shadow_entries.remove_at(index)
			break
	for index in range(_decorative_mass_records.size() - 1, -1, -1):
		if _dense_core_same_poly((_decorative_mass_records[index] as Dictionary).poly,
				poly):
			_decorative_mass_records.remove_at(index)
			break
	for index in range((component.masses as Array).size() - 1, -1, -1):
		if _dense_core_same_poly(((component.masses as Array)[index] as Dictionary).poly,
				poly):
			(component.masses as Array).remove_at(index)
			break
	_dense_core_remove_ring_lines(poly)
	_metrics.blocks = maxi(0, int(_metrics.blocks) - 1)

func _dense_core_same_poly(a: PackedVector2Array,
		b: PackedVector2Array) -> bool:
	return absf(_poly_area(a) - _poly_area(b)) < 0.1 and \
		_poly_center(a).distance_to(_poly_center(b)) < 0.1

func _dense_core_remove_ring_lines(poly: PackedVector2Array) -> void:
	var kept := PackedVector2Array()
	for line_index in range(0, _block_edges.size(), 2):
		var a := _block_edges[line_index]
		var b := _block_edges[line_index + 1]
		var matches := false
		for edge_index in poly.size():
			var p := poly[edge_index]
			var q := poly[(edge_index + 1) % poly.size()]
			if (a.distance_to(p) < 0.1 and b.distance_to(q) < 0.1) or \
					(a.distance_to(q) < 0.1 and b.distance_to(p) < 0.1):
				matches = true
				break
		if not matches:
			kept.append(a)
			kept.append(b)
	_block_edges = kept

func _dense_core_base_exclusions(component: Dictionary,
		tile_poly: PackedVector2Array) -> Array:
	var out: Array = []
	var constraints: Dictionary = component.constraints
	for key in ["water", "forest", "relief", "gameplay", "industrial"]:
		out.append_array(constraints.get(key, []))
	out.append_array(_hero_road_corridors(component.roads))
	var tile_bb := _bbox(tile_poly)
	for site_value in _accommodation_sites:
		var site: Dictionary = site_value
		var poly: PackedVector2Array = site.get("poly", PackedVector2Array())
		if poly.size() >= 3 and _bbox(poly).intersects(tile_bb):
			out.append({"poly": poly, "bb": _bbox(poly)})
	return out

func _ensure_universal_road_gradients(parcel_entries: Array,
		shadow_entries: Array, block_entries: Array) -> void:
	var components := _urban_audit_components.duplicate()
	components.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.key) < str(b.key))
	for component_value in components:
		var component: Dictionary = component_value
		# H2.11 remains the locked image. Three visually distinct road-gradient
		# mechanisms failed to improve it without weakening the accepted hero.
		if str(component.key) == "hero|arin-old":
			continue
		var specs: Array = component.specs.duplicate()
		specs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return str(a.id) < str(b.id))
		for spec_value in specs:
			var spec: Dictionary = spec_value
			var tile_poly := PackedVector2Array()
			for vertex in HEX_VERTS:
				tile_poly.append((spec.center as Vector2) + vertex)
			var exclusions := _dense_core_base_exclusions(component, tile_poly)
			var field_inside := _audit_intersections(component.field_polys, tile_poly)
			field_inside = _hero_clip_polys(field_inside, exclusions, 1.0)
			if field_inside.is_empty():
				continue
			var structure := _audit_road_structure(spec.coord, tile_poly)
			var core_position: Vector2 = spec.center
			var core_radius := _dense_core_radius(str(spec.profile))
			var core_tiles: Dictionary = component.core_tiles
			if core_tiles.has(str(spec.id)):
				var core: Dictionary = core_tiles[str(spec.id)]
				core_position = core.get("audit_core_position", core.core_position)
				core_radius = float(core.get("audit_core_radius", core_radius))
			var samples := _road_gradient_samples(field_inside, component.masses,
				structure, core_position, core_radius)
			if not bool(samples.applicable) or bool(samples.ok):
				continue
			var rich: Array = samples.rich
			var poor: Array = samples.poor
			var poor_built := 0
			for sample_value in poor:
				if bool((sample_value as Dictionary).built):
					poor_built += 1
			var target_rich := ceili((100.0 * float(poor_built) /
				maxf(1.0, float(poor.size())) + AUDIT_RICH_POOR_MIN_DELTA) *
				float(rich.size()) / 100.0)
			var rich_built := 0
			for sample_value in rich:
				if bool((sample_value as Dictionary).built):
					rich_built += 1
			var candidates := rich.duplicate(true)
			candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				if not is_equal_approx(float(a.influence), float(b.influence)):
					return float(a.influence) > float(b.influence)
				if not is_equal_approx(float(a.point.x), float(b.point.x)):
					return float(a.point.x) < float(b.point.x)
				return float(a.point.y) < float(b.point.y))
			var added_count := 0
			for candidate_value in candidates:
				if rich_built >= target_rich or added_count >= 56:
					break
				var candidate: Dictionary = candidate_value
				if bool(candidate.built):
					continue
				var point: Vector2 = candidate.point
				var tangent := _dense_core_tangent(point, structure)
				var candidate_key := "%s|road-rich|%s|%d" % [str(component.key),
					str(spec.id), int(candidate.order)]
				var length := _rr("%s|length" % candidate_key, 17.0, 28.0)
				var depth := _rr("%s|depth" % candidate_key, 10.0, 17.0)
				var poly := _quad(point, tangent, length, depth, candidate_key, 0.58)
				var shadow := _offset(poly, BLOCK_SHADOW_OFFSET)
				if not _poly_fully_inside_any(poly, field_inside) or \
						not _poly_fully_inside_any(shadow, field_inside) or \
						_audit_poly_overlaps_exclusions(poly, component.masses) or \
						_audit_poly_overlaps_exclusions(shadow, component.masses):
					continue
				parcel_entries.append({"poly": poly,
					"color": MapMidcenturyStyle.PAPER, "role": "gradient_lot"})
				(component.parcel_polys as Array).append(poly.duplicate())
				_metrics.parcels = int(_metrics.parcels) + 1
				var before := _decorative_mass_records.size()
				_add_dense_core_block(poly, tangent, 0.84, candidate_key,
					shadow_entries, block_entries, "", str(spec.profile))
				if _decorative_mass_records.size() <= before:
					continue
				var added: Dictionary = _decorative_mass_records[-1]
				(component.masses as Array).append(added.duplicate(true))
				added_count += 1
				for rich_value in rich:
					var rich_sample: Dictionary = rich_value
					if not bool(rich_sample.built) and \
							Geometry2D.is_point_in_polygon(rich_sample.point, poly):
						rich_sample.built = true
						rich_built += 1
			var after_add := _road_gradient_samples(field_inside, component.masses,
				structure, core_position, core_radius)
			if bool(after_add.applicable) and not bool(after_add.ok):
				_road_gradient_demote_poor(component, spec, field_inside,
					structure, core_position, core_radius, shadow_entries,
					block_entries)

func _road_gradient_demote_poor(component: Dictionary, spec: Dictionary,
		field_inside: Array, structure: Dictionary, core_position: Vector2,
		core_radius: float, shadow_entries: Array, block_entries: Array) -> void:
	for pass_index in 32:
		var samples := _road_gradient_samples(field_inside, component.masses,
			structure, core_position, core_radius)
		if not bool(samples.applicable) or bool(samples.ok):
			return
		var poor: Array = samples.poor
		var rich: Array = samples.rich
		var ranked: Array = []
		for mass_value in component.masses:
			var mass: Dictionary = mass_value
			var center := _poly_center(mass.poly)
			if center.distance_to(core_position) <= core_radius * 0.90 or \
					str(mass.get("key", "")).contains("|dense-core|"):
				continue
			var poor_hits := 0
			var rich_hits := 0
			for sample_value in poor:
				var sample: Dictionary = sample_value
				if bool(sample.built) and Geometry2D.is_point_in_polygon(
						sample.point, mass.poly):
					poor_hits += 1
			for sample_value in rich:
				var sample: Dictionary = sample_value
				if bool(sample.built) and Geometry2D.is_point_in_polygon(
						sample.point, mass.poly):
					rich_hits += 1
			if poor_hits <= 0 or rich_hits > poor_hits / 3:
				continue
			ranked.append({"mass": mass, "poor_hits": poor_hits,
				"rich_hits": rich_hits,
				"score": float(poor_hits) - float(rich_hits) * 2.5})
		ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if not is_equal_approx(float(a.score), float(b.score)):
				return float(a.score) > float(b.score)
			return str((a.mass as Dictionary).get("key", "")) < \
				str((b.mass as Dictionary).get("key", "")))
		if ranked.is_empty():
			return
		var target: Dictionary = (ranked[0] as Dictionary).mass
		_dense_core_remove_mass_visual(target, component, shadow_entries,
			block_entries)

func _road_gradient_samples(field_pieces: Array, masses: Array,
		structure: Dictionary, core_position: Vector2,
		core_radius: float) -> Dictionary:
	var samples: Array = []
	var bounds := _hero_polys_bbox(field_pieces)
	var y := bounds.position.y + AUDIT_SAMPLE_STEP * 0.5
	while y < bounds.end.y:
		var x := bounds.position.x + AUDIT_SAMPLE_STEP * 0.5
		while x < bounds.end.x:
			var point := Vector2(x, y)
			if _audit_point_in_polys(point, field_pieces) and \
					point.distance_to(core_position) > core_radius * 0.82:
				var built := false
				for mass_value in masses:
					if Geometry2D.is_point_in_polygon(point,
							(mass_value as Dictionary).poly):
						built = true
						break
				samples.append({"point": point, "built": built,
					"influence": _audit_point_road_influence(point, structure),
					"order": samples.size()})
			x += AUDIT_SAMPLE_STEP
		y += AUDIT_SAMPLE_STEP
	samples.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a.influence), float(b.influence)):
			return float(a.influence) < float(b.influence)
		return int(a.order) < int(b.order))
	var third := int(floor(float(samples.size()) / 3.0))
	var poor: Array = samples.slice(0, third)
	var rich: Array = samples.slice(samples.size() - third, samples.size())
	var sample_area := AUDIT_SAMPLE_STEP * AUDIT_SAMPLE_STEP
	var spread := 0.0
	if samples.size() >= 2:
		spread = float((samples[-1] as Dictionary).influence) - \
			float((samples[0] as Dictionary).influence)
	var applicable := float(poor.size()) * sample_area >= \
		AUDIT_RICH_POOR_MIN_AREA and float(rich.size()) * sample_area >= \
		AUDIT_RICH_POOR_MIN_AREA and spread >= 0.15
	var poor_built := 0
	var rich_built := 0
	for value in poor:
		if bool((value as Dictionary).built):
			poor_built += 1
	for value in rich:
		if bool((value as Dictionary).built):
			rich_built += 1
	var poor_pct := 100.0 * float(poor_built) / maxf(1.0, float(poor.size()))
	var rich_pct := 100.0 * float(rich_built) / maxf(1.0, float(rich.size()))
	return {"poor": poor, "rich": rich, "poor_built": poor_built,
		"rich_built": rich_built, "applicable": applicable,
		"ok": not applicable or rich_pct >= poor_pct +
			AUDIT_RICH_POOR_MIN_DELTA}

func _dense_core_candidate_plan(component: Dictionary, spec: Dictionary,
		field_inside: Array, exclusions: Array, structure: Dictionary,
		position: Vector2, radius: float) -> Dictionary:
	var core_zone := _circle_poly(position, radius * 0.82, 24)
	var core_available := _audit_union_polys(_audit_intersections(
		field_inside, core_zone))
	var core_area := _hero_polys_area(core_available)
	var stats := _dense_core_mass_stats(component.masses, core_available)
	var profile := str(spec.profile)
	var required_count := AUDIT_CORE_CONSTRAINED_MIN_MASSES
	var required_coverage := 0.0
	if core_area >= AUDIT_CORE_STANDARD_AREA:
		if [MORPH_PROFILE_VILLAGE, MORPH_PROFILE_FRINGE].has(profile):
			required_count = 4
			required_coverage = 18.0
		else:
			required_count = 6
			required_coverage = 25.0
	var tangent := _dense_core_tangent(position, structure)
	var occupied: Array = exclusions.duplicate()
	for mass_value in component.masses:
		var mass: Dictionary = mass_value
		occupied.append({"poly": mass.poly, "bb": _bbox(mass.poly)})
	var layout := _dense_core_layout(position, radius, tangent, core_available,
		occupied, "%s|%s" % [str(component.key), str(spec.id)])
	var layout_area := 0.0
	for layout_value in layout:
		layout_area += _poly_area((layout_value as Dictionary).poly)
	return {"position": position, "core_zone": core_zone,
		"core_available": core_available, "core_area": core_area,
		"existing_count": int(stats.count),
		"existing_area": float(stats.area), "required_count": required_count,
		"required_coverage": required_coverage, "layout": layout,
		"layout_area": layout_area}

func _dense_core_mass_stats(masses: Array, core_available: Array) -> Dictionary:
	var count := 0
	var area := 0.0
	for mass_value in masses:
		var mass: Dictionary = mass_value
		var overlap := 0.0
		for available_value in core_available:
			overlap += _hero_polys_area(_audit_intersections(
				[mass.poly], available_value))
		if overlap > 0.01:
			count += 1
			area += overlap
	return {"count": count, "area": area}

func _dense_core_tangent(position: Vector2,
		structure: Dictionary) -> Vector2:
	var best := INF
	var tangent := Vector2.RIGHT
	for segment_value in structure.segments:
		var segment: Dictionary = segment_value
		var distance := _point_segment_distance(position, segment.a, segment.b)
		if distance >= best:
			continue
		var axis := ((segment.b as Vector2) - (segment.a as Vector2)).normalized()
		if axis == Vector2.ZERO:
			continue
		best = distance
		tangent = axis
	return tangent

func _dense_core_layout(position: Vector2, radius: float, tangent: Vector2,
		core_available: Array, base_exclusions: Array, key: String) -> Array:
	# Restored best Phase-1 checkpoint: recursively subdivide actual clipped
	# street faces, never a map-space placement grid.
	var available := _hero_clip_polys(core_available, base_exclusions, 55.0)
	var parcels: Array = []
	for i in available.size():
		parcels.append_array(_dense_core_subdivide_face(available[i],
			"%s|face|%d" % [key, i], 0))
	var normal := Vector2(-tangent.y, tangent.x)
	var ranked: Array = []
	for i in parcels.size():
		var parcel: PackedVector2Array = parcels[i]
		var parcel_center := _poly_center(parcel)
		var delta := parcel_center - position
		var distance_score := clampf(1.0 - delta.length() /
			maxf(1.0, radius), 0.0, 1.0)
		var frontage_score := absf(delta.normalized().dot(normal)) \
			if delta != Vector2.ZERO else 1.0
		ranked.append({"poly": parcel, "index": i,
			"score": distance_score * 1.8 + frontage_score * 0.35})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a.score), float(b.score)):
			return float(a.score) > float(b.score)
		return int(a.index) < int(b.index))
	var out: Array = []
	for ranked_value in ranked:
		var record: Dictionary = ranked_value
		var parcel: PackedVector2Array = record.poly
		var inset := _hero_inset_polys(parcel, _rr(
			"%s|inset|%d" % [key, int(record.index)], 2.0, 3.0))
		if inset.is_empty():
			continue
		inset.sort_custom(func(a: PackedVector2Array,
				b: PackedVector2Array) -> bool:
			return _poly_area(a) > _poly_area(b))
		var poly: PackedVector2Array = inset[0]
		if _poly_area(poly) < 72.0:
			continue
		var shadow := _offset(poly, BLOCK_SHADOW_OFFSET)
		if not _poly_fully_inside_any(shadow, core_available):
			continue
		var edge := _hero_longest_edge(poly)
		var mass_tangent := (poly[(edge + 1) % poly.size()] - poly[edge]).normalized()
		if mass_tangent == Vector2.ZERO:
			mass_tangent = tangent
		out.append({"poly": poly, "lot": parcel,
			"tangent": mass_tangent})
		if out.size() >= 42:
			break
	return out

func _dense_core_subdivide_face(poly: PackedVector2Array,
		key: String, depth: int) -> Array:
	var area := _poly_area(poly)
	var target := _rr("%s|target" % key, 820.0, 1240.0)
	if area <= target or depth >= 6:
		return [poly]
	var edge := _hero_longest_edge(poly)
	var a := poly[edge]
	var b := poly[(edge + 1) % poly.size()]
	var frontage := (b - a).normalized()
	if frontage == Vector2.ZERO:
		return [poly]
	var split_axis := Vector2(-frontage.y, frontage.x)
	var center := _poly_center(poly) + frontage * _rr(
		"%s|shift" % key, -0.09, 0.09) * sqrt(area)
	var span := _bbox(poly).size.length() + 16.0
	var corridor := _segment_quad(center - split_axis * span,
		center + split_axis * span, 1.25)
	var pieces := _hero_clip_polys([poly], [{"poly": corridor,
		"bb": _bbox(corridor)}], 90.0)
	if pieces.size() < 2:
		return [poly]
	var out: Array = []
	for i in pieces.size():
		out.append_array(_dense_core_subdivide_face(pieces[i],
			"%s|%d" % [key, i], depth + 1))
	return out

func _dense_core_face_anchor(face: PackedVector2Array,
		preferred: Vector2, key: String) -> Dictionary:
	var bb := _bbox(face)
	var best_position := _poly_center(face)
	var best_clearance := 0.0
	var best_score := -INF
	# A fixed sample lattice is only an oracle for the interior maximum; it does
	# not place buildings.  The resulting massing remains a single organic court.
	for y_index in 9:
		for x_index in 9:
			var point := bb.position + Vector2(
				bb.size.x * (float(x_index) + 0.5) / 9.0,
				bb.size.y * (float(y_index) + 0.5) / 9.0)
			if not Geometry2D.is_point_in_polygon(point, face):
				continue
			var clearance := INF
			for edge_index in face.size():
				clearance = minf(clearance, _point_segment_distance(point,
					face[edge_index], face[(edge_index + 1) % face.size()]))
			var score := clearance - point.distance_to(preferred) * 0.055 + \
				_rr("%s|%d|%d" % [key, x_index, y_index], -0.001, 0.001)
			if score > best_score:
				best_score = score
				best_position = point
				best_clearance = clearance
	return {"position": best_position, "clearance": best_clearance}

func _audit_poly_overlaps_exclusions(poly: PackedVector2Array,
		exclusions: Array) -> bool:
	var bb := _bbox(poly)
	for value in exclusions:
		var other := PackedVector2Array()
		var other_bb := Rect2()
		if value is PackedVector2Array:
			other = value
			other_bb = _bbox(other)
		elif value is Dictionary:
			var record: Dictionary = value
			other = record.get("poly", PackedVector2Array())
			other_bb = record.get("bb", _bbox(other))
		if other.size() < 3 or not bb.intersects(other_bb):
			continue
		if _polys_overlap_area(poly, other) > 0.05:
			return true
	return false

func _build_universal_district_audit() -> void:
	var sources_by_tile: Dictionary = {}
	for component_value in _urban_audit_components:
		var component: Dictionary = component_value
		for spec_value in component.specs:
			var spec: Dictionary = spec_value
			sources_by_tile[str(spec.id)] = {"component": component, "spec": spec}
	var tile_ids: Array = sources_by_tile.keys()
	tile_ids.sort()
	var universal_tiles: Dictionary = {}
	for tile_id_value in tile_ids:
		var tile_id := str(tile_id_value)
		universal_tiles[tile_id] = _audit_urban_tile(
			sources_by_tile[tile_id], sources_by_tile)
	var field: Dictionary = _metrics.district_field
	field["g1_01_generic_tiles"] = field.get("tiles", {}).duplicate(true)
	field.tiles = universal_tiles
	field.universal_tile_count = universal_tiles.size()
	field.usable_urban_tiles = 0
	field.missing_visible_core_count = 0
	field.density_direction_failure_count = 0
	field.hex_boundary_failure_count = 0
	field.dense_core_failure_count = 0
	field.gradient_applicable_count = 0
	field.gradient_failure_count = 0
	field.internal_seam_failure_count = 0
	field.local_hex_failure_count = 0
	field.actual_spill_tile_count = 0
	field.actual_building_spill_tile_count = 0
	field.rural_building_spill_area = 0.0
	field.hill_building_spill_area = 0.0
	field.invalid_building_spill_area = 0.0
	field.invalid_spill_destination_count = 0
	for tile_value in universal_tiles.values():
		var tile: Dictionary = tile_value
		if float(tile.dry_buildable_urban_area) >= MORPH_CORE_USABLE_MIN_AREA:
			field.usable_urban_tiles = int(field.usable_urban_tiles) + 1
			if int(tile.distinct_core_mass_count) <= 0:
				field.missing_visible_core_count = int(
					field.missing_visible_core_count) + 1
			if not bool(tile.dense_core_ok):
				field.dense_core_failure_count = int(field.dense_core_failure_count) + 1
		if bool(tile.gradient_applicable):
			field.gradient_applicable_count = int(field.gradient_applicable_count) + 1
			if not bool(tile.road_density_gradient_ok):
				field.gradient_failure_count = int(field.gradient_failure_count) + 1
		if int(tile.internal_edge_failure_count) > 0:
			field.internal_seam_failure_count = int(
				field.internal_seam_failure_count) + int(tile.internal_edge_failure_count)
		if not bool(tile.boundary_organic):
			field.local_hex_failure_count = int(field.local_hex_failure_count) + 1
		if float(tile.actual_field_spill_area) > 1.0:
			field.actual_spill_tile_count = int(field.actual_spill_tile_count) + 1
		if float(tile.actual_building_spill_area) > 1.0:
			field.actual_building_spill_tile_count = int(
				field.actual_building_spill_tile_count) + 1
		for spill_value in (tile.spill_by_neighbor as Dictionary).values():
			var spill: Dictionary = spill_value
			var spill_area := float(spill.building_area)
			match str(spill.terrain_type):
				"rural":
					field.rural_building_spill_area = float(
						field.rural_building_spill_area) + spill_area
				"hill":
					field.hill_building_spill_area = float(
						field.hill_building_spill_area) + spill_area
				_:
					field.invalid_building_spill_area = float(
						field.invalid_building_spill_area) + spill_area
					if spill_area > 0.01:
						field.invalid_spill_destination_count = int(
							field.invalid_spill_destination_count) + 1
	field.density_direction_failure_count = int(field.gradient_failure_count)
	field.hex_boundary_failure_count = int(field.local_hex_failure_count)
	_metrics.district_field = field

func _audit_urban_tile(source_record: Dictionary,
		sources_by_tile: Dictionary) -> Dictionary:
	var component: Dictionary = source_record.component
	var spec: Dictionary = source_record.spec
	var tile_id := str(spec.id)
	var center: Vector2 = spec.center
	var profile := str(spec.profile)
	var tile_poly := PackedVector2Array()
	for vertex in HEX_VERTS:
		tile_poly.append(center + vertex)
	var constraints: Dictionary = component.constraints
	var usable_exclusions: Array = []
	for key in ["water", "forest", "relief", "gameplay", "industrial"]:
		usable_exclusions.append_array(constraints.get(key, []))
	usable_exclusions.append_array(_hero_road_corridors(component.roads))
	var accommodation_exclusions: Array = []
	for site_value in _accommodation_sites:
		var site: Dictionary = site_value
		var site_poly: PackedVector2Array = site.get("poly", PackedVector2Array())
		if site_poly.size() >= 3 and _bbox(site_poly).intersects(_bbox(tile_poly)):
			var exclusion := {"poly": site_poly, "bb": _bbox(site_poly)}
			usable_exclusions.append(exclusion)
			accommodation_exclusions.append(exclusion)
	var dry_pieces := _hero_clip_polys([tile_poly], usable_exclusions, 1.0)
	dry_pieces = _audit_union_polys(dry_pieces)
	var field_inside := _audit_intersections(component.field_polys, tile_poly)
	field_inside = _hero_clip_polys(field_inside, usable_exclusions, 1.0)
	field_inside = _audit_union_polys(field_inside)
	var road_structure := _audit_road_structure(spec.coord, tile_poly)
	var ranked_cores := _audit_rank_core_candidates(spec, road_structure,
		dry_pieces, "%s|%s" % [str(component.key), tile_id])
	var current_core := center
	var current_radius := _morph_core_radius(profile, 0.0)
	var attempted_core_positions: Array = []
	var core_tiles: Dictionary = component.core_tiles
	if core_tiles.has(tile_id):
		var current: Dictionary = core_tiles[tile_id]
		current_core = current.get("audit_core_position", current.core_position)
		current_radius = float(current.get("audit_core_radius",
			_dense_core_radius(profile)))
		attempted_core_positions = current.get("attempted_core_positions", [])
	elif not ranked_cores.is_empty():
		current_core = (ranked_cores[0] as Dictionary).position
		current_radius = _dense_core_radius(profile)
	var core_zone := _circle_poly(current_core, current_radius * 0.82, 24)
	var core_buildable := _audit_union_polys(_audit_intersections(
		field_inside, core_zone))
	var mass_pieces: Array = []
	var total_built_area := 0.0
	var total_mass_count := 0
	var core_built_area := 0.0
	var core_mass_count := 0
	for mass_value in component.masses:
		var mass: Dictionary = mass_value
		var mass_poly: PackedVector2Array = mass.get("poly", PackedVector2Array())
		var intersections := _audit_intersections([mass_poly], tile_poly)
		var area := _hero_polys_area(intersections)
		if area <= 0.01:
			continue
		total_mass_count += 1
		total_built_area += area
		mass_pieces.append_array(intersections)
		var core_area := 0.0
		for piece_value in intersections:
			for available_value in core_buildable:
				core_area += _hero_polys_area(_audit_intersections(
					[piece_value], available_value))
		if core_area > 0.01:
			core_mass_count += 1
			core_built_area += core_area
	var core_buildable_area := _hero_polys_area(core_buildable)
	var field_area := _hero_polys_area(field_inside)
	var dry_area := _hero_polys_area(dry_pieces)
	var core_coverage := 100.0 * core_built_area / maxf(1.0, core_buildable_area)
	var required_core_masses := 3
	var required_core_coverage := 0.0
	var constrained_core := core_buildable_area < AUDIT_CORE_STANDARD_AREA
	if not constrained_core:
		if [MORPH_PROFILE_VILLAGE, MORPH_PROFILE_FRINGE].has(profile):
			required_core_masses = 4
			required_core_coverage = 18.0
		else:
			required_core_masses = 6
			required_core_coverage = 25.0
	var dense_core_ok := core_mass_count >= required_core_masses and (
		constrained_core or core_coverage >= required_core_coverage)
	var sectors := _audit_density_sectors(field_inside, mass_pieces,
		road_structure, current_core, current_radius)
	var seams := _audit_internal_edges(spec, component, sources_by_tile,
		usable_exclusions)
	var boundary := _audit_local_exterior_boundary(spec, component,
		sources_by_tile)
	var spill := _audit_actual_spill(spec, component)
	var alternatives: Array = []
	var alternative_source: Array = attempted_core_positions
	if alternative_source.is_empty():
		alternative_source = ranked_cores
	for candidate_value in alternative_source.slice(0,
			mini(6, alternative_source.size())):
		var candidate: Dictionary = candidate_value
		var alternative := {
			"position": [float(candidate.position.x), float(candidate.position.y)],
			"score": float(candidate.score),
			"raw_influence": float(candidate.raw_influence),
			"usable_land_score": float(candidate.usable_land_score),
			"junction_degree": int(candidate.junction_degree),
		}
		for diagnostic_key in ["buildable_core_zone_area",
				"existing_mass_count", "existing_built_coverage",
				"projected_mass_count", "projected_built_coverage"]:
			if candidate.has(diagnostic_key):
				alternative[diagnostic_key] = candidate[diagnostic_key]
		alternatives.append(alternative)
	var tile_data: Dictionary = _terrain.tiles.get(spec.coord, {})
	var constraint_areas := {}
	for key in ["water", "forest", "relief", "gameplay", "industrial"]:
		constraint_areas["%s_area" % key] = _audit_constraint_area(
			tile_poly, constraints.get(key, []))
	constraint_areas["accommodation_area"] = _audit_constraint_area(
		tile_poly, accommodation_exclusions)
	return {
		"tile_id": tile_id,
		"nickname": str(tile_data.get("nickname", "")),
		"profile": profile,
		"settlement_key": str(component.key),
		"dry_buildable_urban_area": dry_area,
		"usable_area": field_area,
		"field_area": field_area,
		"core_position": [current_core.x, current_core.y],
		"attempted_alternative_core_positions": alternatives,
		"buildable_core_zone_area": core_buildable_area,
		"core_built_area": core_built_area,
		"core_built_coverage": core_coverage,
		"distinct_core_mass_count": core_mass_count,
		"core_mass_count": core_mass_count,
		"required_core_mass_count": required_core_masses,
		"required_core_built_coverage": required_core_coverage,
		"constrained_core_zone": constrained_core,
		"dense_core_ok": dense_core_ok,
		"total_mass_count": total_mass_count,
		"built_area": total_built_area,
		"built_coverage": 100.0 * total_built_area / maxf(1.0, field_area),
		"unique_road_edge_count": int(road_structure.unique_edge_count),
		"total_road_length_within_tile": float(road_structure.road_length),
		"junction_count": int(road_structure.junction_count),
		"maximum_junction_degree": int(road_structure.max_junction_degree),
		"raw_road_influence_score": float(road_structure.raw_score),
		"road_rich_usable_area": float(sectors.rich_area),
		"road_intermediate_usable_area": float(sectors.intermediate_area),
		"road_poor_usable_area": float(sectors.poor_area),
		"road_rich_built_coverage": float(sectors.rich_coverage),
		"road_intermediate_built_coverage": float(sectors.intermediate_coverage),
		"road_poor_built_coverage": float(sectors.poor_coverage),
		"near_road_coverage": float(sectors.near_coverage),
		"far_road_coverage": float(sectors.far_coverage),
		"gradient_delta": float(sectors.rich_coverage) - float(sectors.poor_coverage),
		"gradient_applicable": bool(sectors.applicable),
		"road_density_gradient_ok": bool(sectors.ok),
		"internal_edges": seams.records,
		"internal_urban_edge_continuity": float(seams.continuity),
		"internal_edge_failure_count": int(seams.failure_count),
		"local_exterior_boundary_length": float(boundary.length),
		"local_hex_coincident_length": float(boundary.hex_length),
		"local_hex_coincident_fraction": float(boundary.fraction),
		"hex_boundary_fraction": float(boundary.fraction),
		"boundary_organic": float(boundary.fraction) < AUDIT_LOCAL_HEX_FAILURE_FRACTION,
		"spill_destination": spill.destinations,
		"spill_by_neighbor": spill.by_neighbor,
		"actual_field_spill_area": float(spill.field_area),
		"actual_parcel_spill_area": float(spill.parcel_area),
		"actual_building_spill_area": float(spill.building_area),
		"actual_spill_mass_count": int(spill.mass_count),
		"constraints": constraint_areas,
	}

func _audit_intersections(polys: Array,
		clip_poly: PackedVector2Array) -> Array:
	var out: Array = []
	var clip_bb := _bbox(clip_poly)
	for value in polys:
		var poly: PackedVector2Array = value
		if poly.size() < 3 or not _bbox(poly).intersects(clip_bb):
			continue
		for intersection_value in Geometry2D.intersect_polygons(poly, clip_poly):
			var intersection: PackedVector2Array = intersection_value
			if intersection.size() >= 3 and _poly_area(intersection) > 0.01:
				out.append(intersection)
	return out

func _audit_union_polys(polys: Array) -> Array:
	# Clipped organic lobes can retain overlapping pieces with mixed winding.
	# Normalize them before area accounting so the oracle measures visible land
	# once; this does not modify renderer geometry.
	var normalized: Array = []
	for value in polys:
		var poly: PackedVector2Array = value
		if poly.size() < 3 or _poly_area(poly) <= 0.01:
			continue
		poly = poly.duplicate()
		if Geometry2D.is_polygon_clockwise(poly):
			poly.reverse()
		normalized.append(poly)
	return _hero_merge_polys(normalized)

func _audit_constraint_area(tile_poly: PackedVector2Array,
		exclusions: Array) -> float:
	var polys: Array = []
	for value in exclusions:
		if value is PackedVector2Array:
			polys.append(value)
		elif value is Dictionary:
			var record: Dictionary = value
			var poly: PackedVector2Array = record.get("poly", PackedVector2Array())
			if poly.size() >= 3:
				polys.append(poly)
	return _hero_polys_area(_audit_intersections(polys, tile_poly))

func _audit_road_structure(coord: Vector2i,
		tile_poly: PackedVector2Array) -> Dictionary:
	var net := RoadNetwork.instance()
	var edge_ids: Array = []
	var segments: Array = []
	var road_length := 0.0
	for edge_id_value in net.edges_on_tile(coord):
		var edge_id := str(edge_id_value)
		var edge: Dictionary = net.edges.get(edge_id, {})
		if str(edge.get("state", "")) != RoadNetwork.STATE_BUILT:
			continue
		edge_ids.append(edge_id)
		var geometry: PackedVector2Array = edge.get("geometry", PackedVector2Array())
		for i in range(geometry.size() - 1):
			var length_inside := _audit_segment_length_in_poly(
				geometry[i], geometry[i + 1], tile_poly)
			if length_inside <= 0.01:
				continue
			road_length += length_inside
			segments.append({"a": geometry[i], "b": geometry[i + 1],
				"edge_id": edge_id, "length_inside": length_inside,
				"trunk": str(edge.get("tier", "")) == RoadNetwork.TIER_TRUNK})
	edge_ids.sort()
	var node_degrees: Dictionary = {}
	for edge_value in net.edges.values():
		var edge: Dictionary = edge_value
		if str(edge.get("state", "")) != RoadNetwork.STATE_BUILT:
			continue
		for node_key in [str(edge.get("a", "")), str(edge.get("b", ""))]:
			if node_key != "":
				node_degrees[node_key] = int(node_degrees.get(node_key, 0)) + 1
	var junctions: Array = []
	var max_degree := 0
	for node_id_value in node_degrees:
		var node_id := str(node_id_value)
		var node: Dictionary = net.nodes.get(node_id, {})
		if node.is_empty():
			continue
		var position: Vector2 = node.get("pos", Vector2.INF)
		if position == Vector2.INF or not Geometry2D.is_point_in_polygon(
				position, tile_poly):
			continue
		var degree := int(node_degrees[node_id])
		var kind := str(node.get("kind", ""))
		if degree < 3 and kind != RoadNetwork.KIND_JUNCTION:
			continue
		junctions.append({"id": node_id, "position": position,
			"degree": degree, "kind": kind})
		max_degree = maxi(max_degree, degree)
	junctions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.id) < str(b.id))
	var raw_score := float(edge_ids.size()) + road_length / 180.0 + \
		float(junctions.size()) * 0.9 + float(max_degree) * 0.35
	return {"edge_ids": edge_ids, "unique_edge_count": edge_ids.size(),
		"segments": segments, "road_length": road_length,
		"junctions": junctions, "junction_count": junctions.size(),
		"max_junction_degree": max_degree, "raw_score": raw_score}

func _audit_segment_length_in_poly(a: Vector2, b: Vector2,
		poly: PackedVector2Array) -> float:
	var length := a.distance_to(b)
	if length <= 0.01:
		return 0.0
	var steps := maxi(1, ceili(length / 8.0))
	var inside_length := 0.0
	for i in steps:
		var p0 := a.lerp(b, float(i) / float(steps))
		var p1 := a.lerp(b, float(i + 1) / float(steps))
		if Geometry2D.is_point_in_polygon((p0 + p1) * 0.5, poly):
			inside_length += p0.distance_to(p1)
	return inside_length

func _audit_rank_core_candidates(spec: Dictionary, structure: Dictionary,
		dry_pieces: Array, key: String) -> Array:
	var raw_candidates: Array = []
	for piece_value in dry_pieces:
		var piece: PackedVector2Array = piece_value
		if _poly_area(piece) < 90.0:
			continue
		var piece_center := _poly_center(piece)
		if Geometry2D.is_point_in_polygon(piece_center, piece):
			raw_candidates.append({"position": piece_center,
				"junction_degree": 0})
	for junction_value in structure.junctions:
		var junction: Dictionary = junction_value
		raw_candidates.append({"position": junction.position,
			"junction_degree": int(junction.degree)})
	var by_edge: Dictionary = {}
	for segment_value in structure.segments:
		var segment: Dictionary = segment_value
		var edge_id := str(segment.edge_id)
		if not by_edge.has(edge_id):
			by_edge[edge_id] = []
		(by_edge[edge_id] as Array).append(segment)
	for edge_id_value in by_edge:
		var edge_segments: Array = by_edge[edge_id_value]
		var best_point := Vector2.INF
		var best_distance := INF
		for segment_value in edge_segments:
			var segment: Dictionary = segment_value
			for point in [segment.a, (segment.a as Vector2).lerp(segment.b, 0.5),
					segment.b, _closest_point_on_segment(spec.center,
					segment.a, segment.b)]:
				var candidate: Vector2 = point
				if not _inside_hex(candidate, spec.center, 10.0):
					continue
				var distance := candidate.distance_squared_to(spec.center)
				if distance < best_distance:
					best_distance = distance
					best_point = candidate
		if best_point != Vector2.INF:
			raw_candidates.append({"position": best_point, "junction_degree": 0})
	if raw_candidates.is_empty():
		raw_candidates.append({"position": spec.center, "junction_degree": 0})
	var seen: Dictionary = {}
	var out: Array = []
	for candidate_value in raw_candidates:
		var candidate: Dictionary = candidate_value
		var position: Vector2 = candidate.position
		var snapped_key := "%d:%d" % [roundi(position.x / 4.0),
			roundi(position.y / 4.0)]
		if seen.has(snapped_key):
			continue
		seen[snapped_key] = true
		var raw_influence := _audit_point_road_influence(position, structure)
		var usable_score := _audit_local_usable_score(position, dry_pieces,
			"%s|%s" % [key, snapped_key])
		var center_penalty := position.distance_to(spec.center) / 900.0
		# Road anchoring must not bury the buildable face centroids on constrained
		# coast and river tiles.  Keep the road term continuous but bounded while
		# making local usable area the primary relocation signal.
		var normalized_influence := raw_influence / (raw_influence + 6.0)
		var score := normalized_influence * 8.0 + usable_score * 6.0 + \
			minf(3.0, float(candidate.junction_degree)) * 0.35 - center_penalty
		out.append({"position": position, "score": score,
			"raw_influence": raw_influence,
			"usable_land_score": usable_score,
			"junction_degree": int(candidate.junction_degree)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a.score), float(b.score)):
			return float(a.score) > float(b.score)
		if not is_equal_approx(float(a.position.x), float(b.position.x)):
			return float(a.position.x) < float(b.position.x)
		return float(a.position.y) < float(b.position.y))
	return out

func _audit_local_usable_score(position: Vector2, dry_pieces: Array,
		_key: String) -> float:
	var usable := 0
	var count := 1
	if _audit_point_in_polys(position, dry_pieces):
		usable += 1
	for ring in [30.0, 58.0, 84.0]:
		for i in 12:
			count += 1
			var point := position + Vector2.RIGHT.rotated(
				TAU * float(i) / 12.0) * float(ring)
			if _audit_point_in_polys(point, dry_pieces):
				usable += 1
	return float(usable) / float(count)

func _audit_point_road_influence(point: Vector2,
		structure: Dictionary) -> float:
	var edge_distances: Dictionary = {}
	var local_length := 0.0
	for segment_value in structure.segments:
		var segment: Dictionary = segment_value
		var distance := _point_segment_distance(point, segment.a, segment.b)
		var edge_id := str(segment.edge_id)
		edge_distances[edge_id] = minf(float(edge_distances.get(edge_id, INF)),
			distance)
		if distance < 150.0:
			local_length += float(segment.length_inside) * (1.0 - distance / 150.0)
	var score := 0.0
	for distance_value in edge_distances.values():
		var distance := float(distance_value)
		score += clampf(1.0 - distance / 190.0, 0.0, 1.0)
	score += local_length / 170.0
	for junction_value in structure.junctions:
		var junction: Dictionary = junction_value
		var distance := point.distance_to(junction.position)
		if distance < 180.0:
			score += clampf(1.0 - distance / 180.0, 0.0, 1.0) * \
				maxf(1.0, float(junction.degree) - 1.0) * 0.55
	return score

func _audit_density_sectors(field_pieces: Array, mass_pieces: Array,
		structure: Dictionary, core_position: Vector2,
		core_radius: float) -> Dictionary:
	var samples: Array = []
	var near_total := 0
	var near_built := 0
	var far_total := 0
	var far_built := 0
	var bounds := _hero_polys_bbox(field_pieces)
	var y := bounds.position.y + AUDIT_SAMPLE_STEP * 0.5
	while y < bounds.end.y:
		var x := bounds.position.x + AUDIT_SAMPLE_STEP * 0.5
		while x < bounds.end.x:
			var point := Vector2(x, y)
			if not _audit_point_in_polys(point, field_pieces):
				x += AUDIT_SAMPLE_STEP
				continue
			var built := _audit_point_in_polys(point, mass_pieces)
			var road_distance := _audit_nearest_structure_distance(point, structure)
			if road_distance <= MORPH_NEAR_ROAD_DEPTH:
				near_total += 1
				if built:
					near_built += 1
			else:
				far_total += 1
				if built:
					far_built += 1
			if point.distance_to(core_position) > core_radius * 0.82:
				samples.append({"influence": _audit_point_road_influence(
					point, structure), "built": built, "point": point})
			x += AUDIT_SAMPLE_STEP
		y += AUDIT_SAMPLE_STEP
	samples.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a.influence), float(b.influence)):
			return float(a.influence) < float(b.influence)
		if not is_equal_approx(float(a.point.x), float(b.point.x)):
			return float(a.point.x) < float(b.point.x)
		return float(a.point.y) < float(b.point.y))
	var sector_counts := [0, 0, 0]
	var sector_built := [0, 0, 0]
	for i in samples.size():
		var sector := mini(2, int(floor(3.0 * float(i) /
			maxf(1.0, float(samples.size())))))
		sector_counts[sector] += 1
		if bool((samples[i] as Dictionary).built):
			sector_built[sector] += 1
	var sample_area := AUDIT_SAMPLE_STEP * AUDIT_SAMPLE_STEP
	var poor_area := float(sector_counts[0]) * sample_area
	var intermediate_area := float(sector_counts[1]) * sample_area
	var rich_area := float(sector_counts[2]) * sample_area
	var poor_coverage := 100.0 * float(sector_built[0]) / \
		maxf(1.0, float(sector_counts[0]))
	var intermediate_coverage := 100.0 * float(sector_built[1]) / \
		maxf(1.0, float(sector_counts[1]))
	var rich_coverage := 100.0 * float(sector_built[2]) / \
		maxf(1.0, float(sector_counts[2]))
	var influence_spread := 0.0
	if samples.size() >= 2:
		influence_spread = float((samples[-1] as Dictionary).influence) - \
			float((samples[0] as Dictionary).influence)
	var applicable := rich_area >= AUDIT_RICH_POOR_MIN_AREA and \
		poor_area >= AUDIT_RICH_POOR_MIN_AREA and influence_spread >= 0.15
	return {
		"rich_area": rich_area, "intermediate_area": intermediate_area,
		"poor_area": poor_area, "rich_coverage": rich_coverage,
		"intermediate_coverage": intermediate_coverage,
		"poor_coverage": poor_coverage,
		"near_coverage": 100.0 * float(near_built) / maxf(1.0, float(near_total)),
		"far_coverage": 100.0 * float(far_built) / maxf(1.0, float(far_total)),
		"influence_spread": influence_spread, "applicable": applicable,
		"ok": not applicable or rich_coverage >= poor_coverage +
			AUDIT_RICH_POOR_MIN_DELTA,
	}

func _audit_nearest_structure_distance(point: Vector2,
		structure: Dictionary) -> float:
	var best := INF
	for segment_value in structure.segments:
		var segment: Dictionary = segment_value
		best = minf(best, _point_segment_distance(point, segment.a, segment.b))
	return best

func _audit_point_in_polys(point: Vector2, polys: Array) -> bool:
	for value in polys:
		var poly: PackedVector2Array = value
		if Geometry2D.is_point_in_polygon(point, poly):
			return true
	return false

func _audit_internal_edges(spec: Dictionary, component: Dictionary,
		sources_by_tile: Dictionary, exclusions: Array) -> Dictionary:
	var records: Array = []
	var applicable := 0
	var continuous := 0
	var failure_count := 0
	var neighbors: Array[Vector2i] = _terrain.call("neighbor_coords", spec.coord)
	var masses: Array = []
	for mass_value in component.masses:
		masses.append((mass_value as Dictionary).poly)
	for edge_index in HEX_VERTS.size():
		var neighbor_coord: Vector2i = neighbors[edge_index]
		var neighbor_id := ""
		if _terrain.tiles.has(neighbor_coord):
			neighbor_id = str((_terrain.tiles[neighbor_coord] as Dictionary).get(
				"id", ""))
		if neighbor_id == "" or not sources_by_tile.has(neighbor_id):
			continue
		var neighbor_source: Dictionary = sources_by_tile[neighbor_id]
		if str((neighbor_source.component as Dictionary).key) != str(component.key):
			continue
		var a: Vector2 = spec.center + HEX_VERTS[edge_index]
		var b: Vector2 = spec.center + HEX_VERTS[(edge_index + 1) % HEX_VERTS.size()]
		var neighbor_center: Vector2 = (neighbor_source.spec as Dictionary).center
		var field_crossings := _audit_crossing_count(component.field_polys,
			a, b, spec.center, neighbor_center)
		var parcel_crossings := _audit_crossing_count(component.parcel_polys,
			a, b, spec.center, neighbor_center)
		var mass_crossings := _audit_crossing_count(masses, a, b,
			spec.center, neighbor_center)
		var road_crossing := _morph_edge_has_authoritative_road(a, b,
			component.roads)
		var constrained_samples := 0
		for sample in range(1, 6):
			var point := a.lerp(b, float(sample) / 6.0)
			if _audit_point_excluded(point, exclusions) or not _land_clear(point):
				constrained_samples += 1
		var physically_constrained := constrained_samples >= 3
		if not physically_constrained:
			applicable += 1
		var edge_continuous := physically_constrained or (
			field_crossings > 0 and (parcel_crossings > 0 or road_crossing))
		if not physically_constrained and edge_continuous:
			continuous += 1
		if not edge_continuous:
			failure_count += 1
		records.append({
			"edge_index": edge_index, "neighbor_id": neighbor_id,
			"field_crossing_count": field_crossings,
			"parcel_crossing_count": parcel_crossings,
			"building_crossing_count": mass_crossings,
			"road_crossing": road_crossing,
			"physically_constrained": physically_constrained,
			"continuous": edge_continuous,
		})
	return {"records": records, "failure_count": failure_count,
		"continuity": 1.0 if applicable == 0 else float(continuous) /
			float(applicable)}

func _audit_crossing_count(polys: Array, a: Vector2, b: Vector2,
		inside_center: Vector2, neighbor_center: Vector2) -> int:
	var outward := (neighbor_center - inside_center).normalized()
	if outward == Vector2.ZERO:
		return 0
	var count := 0
	for sample in range(1, 8):
		var edge_point := a.lerp(b, float(sample) / 8.0)
		var inside := edge_point - outward * 12.0
		var outside := edge_point + outward * 12.0
		if _audit_point_in_polys(inside, polys) and \
				_audit_point_in_polys(outside, polys):
			count += 1
	return count

func _audit_point_excluded(point: Vector2, exclusions: Array) -> bool:
	for value in exclusions:
		var poly := PackedVector2Array()
		if value is PackedVector2Array:
			poly = value
		elif value is Dictionary:
			poly = (value as Dictionary).get("poly", PackedVector2Array())
		if poly.size() >= 3 and Geometry2D.is_point_in_polygon(point, poly):
			return true
	return false

func _audit_local_exterior_boundary(spec: Dictionary, component: Dictionary,
		sources_by_tile: Dictionary) -> Dictionary:
	var external_edges: Array = []
	var neighbors: Array[Vector2i] = _terrain.call("neighbor_coords", spec.coord)
	for edge_index in HEX_VERTS.size():
		var neighbor_id := ""
		if _terrain.tiles.has(neighbors[edge_index]):
			neighbor_id = str((_terrain.tiles[neighbors[edge_index]] as Dictionary).get(
				"id", ""))
		if neighbor_id == "" or not sources_by_tile.has(neighbor_id):
			external_edges.append(edge_index)
	if external_edges.is_empty():
		return {"length": 0.0, "hex_length": 0.0, "fraction": 0.0}
	var local_length := 0.0
	var hex_length := 0.0
	for poly_value in component.field_polys:
		var poly: PackedVector2Array = poly_value
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			var length := a.distance_to(b)
			if length <= 0.01:
				continue
			var steps := maxi(1, ceili(length / 8.0))
			for step in steps:
				var p0 := a.lerp(b, float(step) / float(steps))
				var p1 := a.lerp(b, float(step + 1) / float(steps))
				var midpoint := (p0 + p1) * 0.5
				var nearest_edge := -1
				var nearest_distance := INF
				for edge_index_value in external_edges:
					var edge_index := int(edge_index_value)
					var ha: Vector2 = spec.center + HEX_VERTS[edge_index]
					var hb: Vector2 = spec.center + HEX_VERTS[
						(edge_index + 1) % HEX_VERTS.size()]
					var distance := _point_segment_distance(midpoint, ha, hb)
					if distance < nearest_distance:
						nearest_distance = distance
						nearest_edge = edge_index
				# Measure only the true component perimeter near this tile's external
				# sides. The former inside-hex test admitted every internal road,
				# park and water edge in the tile while discarding organic spill just
				# outside it, so its denominator was not a local exterior perimeter.
				if nearest_edge < 0 or nearest_distance > 48.0:
					continue
				var chunk_length := p0.distance_to(p1)
				local_length += chunk_length
				var ha: Vector2 = spec.center + HEX_VERTS[nearest_edge]
				var hb: Vector2 = spec.center + HEX_VERTS[
					(nearest_edge + 1) % HEX_VERTS.size()]
				var tangent := (p1 - p0).normalized()
				var hex_tangent := (hb - ha).normalized()
				if nearest_distance <= 3.0 and absf(
						tangent.dot(hex_tangent)) >= 0.985:
					hex_length += chunk_length
	return {"length": local_length, "hex_length": hex_length,
		"fraction": hex_length / maxf(1.0, local_length)}

func _audit_actual_spill(spec: Dictionary, component: Dictionary) -> Dictionary:
	var destinations: Array = []
	var by_neighbor: Dictionary = {}
	var total_field := 0.0
	var total_parcel := 0.0
	var total_building := 0.0
	var total_masses := 0
	for neighbor_coord_value in _terrain.call("neighbor_coords", spec.coord):
		var neighbor_coord: Vector2i = neighbor_coord_value
		if not _terrain.tiles.has(neighbor_coord):
			continue
		var neighbor_data: Dictionary = _terrain.tiles[neighbor_coord]
		if str(neighbor_data.get("type", "")) == "urban":
			continue
		var neighbor_id := str(neighbor_data.get("id", ""))
		var neighbor_center := _terrain.map_to_local(
			_terrain.map_coord_for_tile_coord(neighbor_coord))
		if _audit_spill_owner(component, neighbor_center) != str(spec.id):
			continue
		var neighbor_poly := PackedVector2Array()
		for vertex in HEX_VERTS:
			neighbor_poly.append(neighbor_center + vertex)
		var parcel_area := _hero_polys_area(_audit_intersections(
			component.parcel_polys, neighbor_poly))
		# Parcel fill is the visible settlement field.  Raw component envelopes are
		# construction geometry and may extend under clipped water/relief.
		var field_area := parcel_area
		var building_area := 0.0
		var mass_count := 0
		for mass_value in component.masses:
			var mass: Dictionary = mass_value
			var area := _hero_polys_area(_audit_intersections(
				[mass.poly], neighbor_poly))
			if area <= 0.01:
				continue
			mass_count += 1
			building_area += area
		if field_area <= 0.01 and parcel_area <= 0.01 and building_area <= 0.01:
			continue
		by_neighbor[neighbor_id] = {
			"terrain_type": str(neighbor_data.get("type", "")),
			"relief_band": _land_band_at(neighbor_center),
			"nickname": str(neighbor_data.get("nickname", "")),
			"field_area": field_area, "parcel_area": parcel_area,
			"building_area": building_area, "building_mass_count": mass_count,
		}
		if field_area > 1.0:
			destinations.append(neighbor_id)
		total_field += field_area
		total_parcel += parcel_area
		total_building += building_area
		total_masses += mass_count
	destinations.sort()
	return {"destinations": destinations, "by_neighbor": by_neighbor,
		"field_area": total_field, "parcel_area": total_parcel,
		"building_area": total_building, "mass_count": total_masses}

func _audit_spill_owner(component: Dictionary,
		neighbor_center: Vector2) -> String:
	var best_id := ""
	var best_distance := INF
	for spec_value in component.specs:
		var candidate: Dictionary = spec_value
		var distance := neighbor_center.distance_squared_to(candidate.center)
		if distance < best_distance or (is_equal_approx(distance, best_distance) and
				str(candidate.id) < best_id):
			best_distance = distance
			best_id = str(candidate.id)
	return best_id

func _morph_tile_diagnostics(field_tiles: Dictionary, envelopes: Array,
		masses: Array, roads: Array) -> Dictionary:
	var out: Dictionary = {}
	for tile_id_value in field_tiles:
		var tile_id := str(tile_id_value)
		var tile: Dictionary = field_tiles[tile_id]
		var usable_area := 0.0
		var envelope_inside: Array = []
		var tile_poly := PackedVector2Array()
		for vertex in HEX_VERTS:
			tile_poly.append((tile.center as Vector2) + vertex)
		for envelope_value in envelopes:
			for piece_value in Geometry2D.intersect_polygons(envelope_value, tile_poly):
				var piece: PackedVector2Array = piece_value
				usable_area += _poly_area(piece)
				envelope_inside.append(piece)
		var total_mass_area := 0.0
		var near_mass_area := 0.0
		var far_mass_area := 0.0
		var road_distance_mass_sum := 0.0
		var total_mass_count := 0
		var core_mass_count := 0
		var owner_core := tile.core_position as Vector2
		var owner_radius := float(tile.core_radius)
		for mass_value in masses:
			var mass: Dictionary = mass_value
			var mass_poly: PackedVector2Array = mass.poly
			var center := _poly_center(mass_poly)
			if not Geometry2D.is_point_in_polygon(center, tile_poly):
				continue
			var area := _poly_area(mass_poly)
			var road_distance := _nearest_segment_distance(center, roads)
			total_mass_count += 1
			total_mass_area += area
			road_distance_mass_sum += road_distance * area
			if center.distance_to(owner_core) <= owner_radius * 0.82:
				core_mass_count += 1
			if road_distance <= MORPH_NEAR_ROAD_DEPTH:
				near_mass_area += area
			else:
				far_mass_area += area
		var near_usable := 0.0
		var far_usable := 0.0
		var nav := NavGrid.instance()
		var sample_step := 18.0
		var bb := _bbox(tile_poly)
		var sample_area := sample_step * sample_step
		var y := bb.position.y + sample_step * 0.5
		while y < bb.end.y:
			var x := bb.position.x + sample_step * 0.5
			while x < bb.end.x:
				var point := Vector2(x, y)
				var inside_field := false
				for envelope_value in envelope_inside:
					if Geometry2D.is_point_in_polygon(point, envelope_value):
						inside_field = true
						break
				if inside_field and (not nav.is_ready() or _land_clear(point)):
					if _nearest_segment_distance(point, roads) <= MORPH_NEAR_ROAD_DEPTH:
						near_usable += sample_area
					else:
						far_usable += sample_area
				x += sample_step
			y += sample_step
		var near_coverage := 100.0 * near_mass_area / maxf(1.0, near_usable)
		var far_coverage := 100.0 * far_mass_area / maxf(1.0, far_usable)
		var near_share := 100.0 * near_mass_area / maxf(1.0, total_mass_area)
		var mean_road_distance := road_distance_mass_sum / maxf(1.0, total_mass_area)
		var boundary_fraction := _morph_hex_boundary_fraction(envelopes, tile_poly)
		out[tile_id] = {
			"usable_area": usable_area,
			"core_position": [owner_core.x, owner_core.y],
			"core_mass_count": core_mass_count,
			"total_mass_count": total_mass_count,
			"built_coverage": 100.0 * total_mass_area / maxf(1.0, usable_area),
			"near_road_coverage": near_coverage,
			"far_road_coverage": far_coverage,
			"near_road_built_share": near_share,
			"mean_built_road_distance": mean_road_distance,
			"near_road_usable_area": near_usable,
			"far_road_usable_area": far_usable,
			"spill_destination": (tile.spill_destinations as Array).duplicate(),
			"road_richness": float(tile.road_richness),
			"road_segment_count": int(tile.road_segment_count),
			"hex_boundary_fraction": boundary_fraction,
			"visible_core": core_mass_count > 0,
			"density_direction_ok": int(tile.road_segment_count) == 0 or
				far_usable < 700.0 or total_mass_area <= 0.0 or near_share >= 60.0,
			"boundary_organic": boundary_fraction < MORPH_HEX_EDGE_FAILURE_FRACTION,
		}
	return out

func _morph_hex_boundary_fraction(envelope_pieces: Array,
		tile_poly: PackedVector2Array) -> float:
	var boundary_length := 0.0
	var hex_like_length := 0.0
	for piece_value in envelope_pieces:
		var piece: PackedVector2Array = piece_value
		for i in piece.size():
			var a := piece[i]
			var b := piece[(i + 1) % piece.size()]
			var length := a.distance_to(b)
			if length <= 0.01:
				continue
			boundary_length += length
			var midpoint := (a + b) * 0.5
			var tangent := (b - a).normalized()
			for edge_index in tile_poly.size():
				var ha := tile_poly[edge_index]
				var hb := tile_poly[(edge_index + 1) % tile_poly.size()]
				var hex_tangent := (hb - ha).normalized()
				if _point_segment_distance(midpoint, ha, hb) <= 3.0 and \
						absf(tangent.dot(hex_tangent)) >= 0.985:
					hex_like_length += length
					break
	return hex_like_length / maxf(1.0, boundary_length)

func _register_district_field_metrics(component_key: String,
		tiles: Dictionary) -> void:
	var field: Dictionary = _metrics.district_field
	field.components[component_key] = {"tiles": (tiles.keys() as Array).duplicate(),
		"tile_count": tiles.size()}
	for tile_id_value in tiles:
		var tile_id := str(tile_id_value)
		var diagnostics: Dictionary = tiles[tile_id]
		field.tiles[tile_id] = diagnostics.duplicate(true)
		if float(diagnostics.usable_area) >= MORPH_CORE_USABLE_MIN_AREA:
			field.usable_urban_tiles = int(field.usable_urban_tiles) + 1
			if not bool(diagnostics.visible_core):
				field.missing_visible_core_count = int(
					field.missing_visible_core_count) + 1
		if float(diagnostics.usable_area) >= MORPH_CORE_USABLE_MIN_AREA and \
				not bool(diagnostics.density_direction_ok):
			field.density_direction_failure_count = int(
				field.density_direction_failure_count) + 1
		if not bool(diagnostics.boundary_organic):
			field.hex_boundary_failure_count = int(field.hex_boundary_failure_count) + 1
	_metrics.district_field = field

func _morph_ensure_visible_cores(field_tiles: Dictionary, envelopes: Array,
		road_corridors: Array, exclusions: Array, mass_start: int,
		shadow_entries: Array, block_entries: Array) -> void:
	# Final safety net for physically awkward docks/islands: search only the
	# usable field close to the recorded road focus. This adds a small street-wall
	# fragment, never a tile-centred marker or full-cell fill.
	for tile_id_value in field_tiles:
		var tile_id := str(tile_id_value)
		var tile: Dictionary = field_tiles[tile_id]
		var has_core := false
		for mass_value in _decorative_mass_records.slice(mass_start):
			var mass: Dictionary = mass_value
			if _poly_center(mass.poly).distance_to(tile.core_position) <= \
					float(tile.core_radius) * 0.82:
				has_core = true
				break
		if has_core:
			continue
		var core_zone := _circle_poly(tile.core_position,
			float(tile.core_radius) * 0.82, 20)
		var candidates: Array = []
		for envelope_value in envelopes:
			for core_value in Geometry2D.intersect_polygons(envelope_value, core_zone):
				var core_piece: PackedVector2Array = core_value
				for street_value in _hero_clip_polys([core_piece], road_corridors, 90.0):
					for available_value in _hero_clip_polys([street_value], exclusions, 90.0):
						candidates.append(available_value)
		candidates.sort_custom(func(a: PackedVector2Array,
				b: PackedVector2Array) -> bool:
			var da := _poly_center(a).distance_squared_to(tile.core_position)
			var db := _poly_center(b).distance_squared_to(tile.core_position)
			if not is_equal_approx(da, db):
				return da < db
			return _poly_area(a) > _poly_area(b))
		for candidate_value in candidates:
			var candidate: PackedVector2Array = candidate_value
			var scale := clampf(sqrt(420.0 / maxf(420.0, _poly_area(candidate))),
				0.16, 0.76)
			var mass := _scale_poly(candidate, _poly_center(candidate), scale)
			var bb := _bbox(mass)
			if minf(bb.size.x, bb.size.y) < 6.0:
				continue
			var edge := _hero_longest_edge(mass)
			var tangent := (mass[(edge + 1) % mass.size()] - mass[edge]).normalized()
			_add_block(mass, tangent, 0.48, "%s|field-core" % tile_id,
				shadow_entries, block_entries, "", str(tile.profile))
			break

func _morph_tile_road_context(spec: Dictionary, roads: Array,
		key: String) -> Dictionary:
	var candidates: Array = []
	var local_segments: Array = []
	for road_value in roads:
		var road: Dictionary = road_value
		var closest := _closest_point_on_segment(spec.center, road.a, road.b)
		if closest.distance_to(spec.center) > 310.0:
			continue
		local_segments.append(road)
		for point in [closest, (road.a as Vector2).lerp(road.b, 0.5), road.a, road.b]:
			var candidate: Vector2 = point
			if not _inside_hex(candidate, spec.center, 12.0):
				continue
			var local_score := 0.0
			var directions: Array[Vector2] = []
			for other_value in roads:
				var other: Dictionary = other_value
				var distance := _point_segment_distance(candidate, other.a, other.b)
				if distance > 84.0:
					continue
				local_score += 1.0 - distance / 104.0
				var axis := ((other.b as Vector2) - (other.a as Vector2)).normalized()
				if axis != Vector2.ZERO:
					directions.append(axis)
			if bool(road.get("trunk", false)):
				local_score += 0.65
			local_score -= candidate.distance_to(spec.center) / 720.0
			candidates.append({"point": candidate, "score": local_score,
				"tangent": _morph_mean_road_axis(directions, road.b - road.a)})
	var fallback_angle := _rr("%s|fallback-angle" % key, -PI, PI)
	if candidates.is_empty():
		return {"position": spec.center, "tangent": Vector2.RIGHT.rotated(fallback_angle),
			"road_richness": 0.0, "road_segment_count": 0}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a.score), float(b.score)):
			return float(a.score) > float(b.score)
		if not is_equal_approx(float(a.point.x), float(b.point.x)):
			return float(a.point.x) < float(b.point.x)
		return float(a.point.y) < float(b.point.y))
	var best: Dictionary = candidates[0]
	var richness := clampf((float(best.score) - 0.6) / 4.6, 0.0, 1.0)
	return {"position": best.point, "tangent": best.tangent,
		"road_richness": richness, "road_segment_count": local_segments.size()}

## Focused deterministic fixture seam: keep the input deliberately limited to
## current road geometry and one tile centre.  Tests use this to prove that a
## removed road stops steering the generated core and its replacement does,
## without changing terrain, tile metadata or a named settlement.
func road_layout_fixture_snapshot(center: Vector2, roads: Array,
		key: String = "road-layout-fixture") -> Dictionary:
	var context := _morph_tile_road_context({"center": center}, roads, key)
	var tangent: Vector2 = context.tangent
	var position: Vector2 = context.position
	var core := _morph_organic_field_cell(position, tangent, 112.0, 78.0,
		"%s|core" % key)
	return {
		"core_position": position,
		"core_tangent": tangent,
		"core_polygon": core,
		"road_richness": float(context.road_richness),
		"road_segment_count": int(context.road_segment_count),
	}

func _morph_mass_distribution(masses: Array, field_tiles: Dictionary,
		roads: Array) -> Dictionary:
	var areas: Array[float] = []
	var size_buckets: Dictionary = {}
	var shape_buckets: Dictionary = {}
	var total_area := 0.0
	var outside_core_area := 0.0
	var frontage_area := 0.0
	for mass_value in masses:
		var mass: Dictionary = mass_value
		var poly: PackedVector2Array = mass.get("poly", PackedVector2Array())
		if poly.size() < 3:
			continue
		var area := _poly_area(poly)
		var center := _poly_center(poly)
		areas.append(area)
		total_area += area
		var size_key := str(int(floor(area / 125.0)) * 125)
		size_buckets[size_key] = int(size_buckets.get(size_key, 0)) + 1
		var bb := _bbox(poly)
		var aspect := maxf(bb.size.x, bb.size.y) / maxf(1.0,
			minf(bb.size.x, bb.size.y))
		var shape_key := "%d-%.1f" % [poly.size(), snappedf(aspect, 0.25)]
		shape_buckets[shape_key] = int(shape_buckets.get(shape_key, 0)) + 1
		if _nearest_segment_distance(center, roads) <= MORPH_NEAR_ROAD_DEPTH:
			frontage_area += area
		var inside_any_core := false
		for tile_value in field_tiles.values():
			var tile: Dictionary = tile_value
			if center.distance_to(tile.core_position) <= float(tile.core_radius):
				inside_any_core = true
				break
		if not inside_any_core:
			outside_core_area += area
	areas.sort()
	var descending := areas.duplicate()
	descending.reverse()
	var largest_three := 0.0
	for i in mini(3, descending.size()):
		largest_three += descending[i]
	return {
		"mass_count": areas.size(),
		"total_mass_area": total_area,
		"mass_area_p25": _morph_percentile(areas, 0.25),
		"median_mass_area": _morph_percentile(areas, 0.50),
		"mass_area_p75": _morph_percentile(areas, 0.75),
		"mass_area_p90": _morph_percentile(areas, 0.90),
		"largest_mass_share": (descending[0] / maxf(1.0, total_area)) if \
			not descending.is_empty() else 0.0,
		"largest_three_share": largest_three / maxf(1.0, total_area),
		"repeated_size_bucket_dominance": float(_dictionary_max_count(
			size_buckets)) / maxf(1.0, float(areas.size())),
		"repeated_shape_dominance": float(_dictionary_max_count(shape_buckets)) /
			maxf(1.0, float(areas.size())),
		"size_buckets": size_buckets,
		"shape_buckets": shape_buckets,
		"road_frontage_occupancy": 100.0 * frontage_area / maxf(1.0, total_area),
		"outside_core_built_area": outside_core_area,
		"outside_core_built_share": 100.0 * outside_core_area /
			maxf(1.0, total_area),
	}

func _morph_percentile(sorted_values: Array[float], percentile: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var index := clampi(roundi(percentile * float(sorted_values.size() - 1)),
		0, sorted_values.size() - 1)
	return sorted_values[index]

func _dictionary_max_count(counts: Dictionary) -> int:
	var maximum := 0
	for value in counts.values():
		maximum = maxi(maximum, int(value))
	return maximum

func _morph_whole_body_gate(profile_counts: Dictionary, envelope_area: float,
		built_area: float, distribution: Dictionary) -> Dictionary:
	var dominant_profile := MORPH_PROFILE_TOWN
	var dominant_count := -1
	for profile_value in profile_counts:
		var count := int(profile_counts[profile_value])
		if count > dominant_count:
			dominant_count = count
			dominant_profile = str(profile_value)
	var minimum_masses := 12
	var minimum_built_pct := 12.0
	var minimum_frontage_pct := 55.0
	var maximum_largest_three_share := 0.48
	var minimum_outside_core_share := 10.0
	if dominant_profile == MORPH_PROFILE_METRO:
		minimum_masses = 28
		minimum_built_pct = 22.0
		minimum_frontage_pct = 58.0
	elif dominant_profile == MORPH_PROFILE_TOWN:
		minimum_masses = 18
		minimum_built_pct = 15.0
	elif dominant_profile == MORPH_PROFILE_FRINGE:
		minimum_masses = 10
		minimum_built_pct = 10.0
		minimum_frontage_pct = 48.0
	var measured_built_area := float(distribution.get("total_mass_area", built_area))
	var built_pct := 100.0 * measured_built_area / maxf(1.0, envelope_area)
	var failures: Array[String] = []
	if int(distribution.mass_count) < minimum_masses:
		failures.append("minimum_mass_count")
	if built_pct < minimum_built_pct:
		failures.append("minimum_built_coverage")
	if float(distribution.road_frontage_occupancy) < minimum_frontage_pct:
		failures.append("minimum_road_frontage_occupancy")
	if float(distribution.largest_three_share) > maximum_largest_three_share:
		failures.append("largest_mass_dominance")
	if float(distribution.outside_core_built_share) < minimum_outside_core_share:
		failures.append("minimum_body_area_outside_core")
	return {
		"profile": dominant_profile,
		"built_pct": built_pct,
		"minimum_mass_count": minimum_masses,
		"minimum_built_pct": minimum_built_pct,
		"minimum_road_frontage_pct": minimum_frontage_pct,
		"maximum_largest_three_share": maximum_largest_three_share,
		"minimum_outside_core_share": minimum_outside_core_share,
		"failures": failures,
		"passes": failures.is_empty(),
	}

func _morph_mean_road_axis(directions: Array[Vector2], fallback: Vector2) -> Vector2:
	var base := fallback.normalized()
	if base == Vector2.ZERO:
		base = Vector2.RIGHT
	var total := Vector2.ZERO
	for direction in directions:
		var aligned := direction if direction.dot(base) >= 0.0 else -direction
		total += aligned
	return total.normalized() if total.length_squared() > 0.001 else base

func _morph_core_radius(profile: String, road_richness: float) -> float:
	var base := 112.0
	if profile == MORPH_PROFILE_METRO:
		base = 164.0
	elif profile == MORPH_PROFILE_TOWN:
		base = 146.0
	elif profile == MORPH_PROFILE_SMALL_TOWN:
		base = 132.0
	elif profile == MORPH_PROFILE_FRINGE:
		base = 132.0
	return base * lerpf(0.94, 1.08, road_richness)

func _morph_organic_field_cell(center: Vector2, tangent: Vector2,
		along: float, across: float, key: String) -> PackedVector2Array:
	var t := tangent.normalized()
	if t == Vector2.ZERO:
		t = Vector2.RIGHT
	var n := Vector2(-t.y, t.x)
	var phase := _rr("%s|phase" % key, -PI, PI)
	var out := PackedVector2Array()
	for i in 14:
		var angle := TAU * float(i) / 14.0
		var irregularity := 1.0 + sin(angle * 3.0 + phase) * 0.075 + \
			cos(angle * 5.0 - phase * 0.7) * 0.045 + \
			_rr("%s|jitter|%d" % [key, i], -0.035, 0.035)
		out.append(center + t * cos(angle) * along * irregularity +
			n * sin(angle) * across * irregularity)
	return out

func _morph_authoritative_crossing(a: Vector2, b: Vector2,
		roads: Array) -> Vector2:
	var best := Vector2.INF
	var best_distance := INF
	var midpoint := (a + b) * 0.5
	for road_value in roads:
		var road: Dictionary = road_value
		var intersection: Variant = Geometry2D.segment_intersects_segment(
			a, b, road.a, road.b)
		if intersection == null:
			continue
		var point: Vector2 = intersection
		var distance := point.distance_squared_to(midpoint)
		if distance < best_distance:
			best_distance = distance
			best = point
	return best

func _morph_edge_has_authoritative_road(a: Vector2, b: Vector2, road_segments: Array) -> bool:
	for road_value in road_segments:
		var road: Dictionary = road_value
		var ra: Vector2 = road.a
		var rb: Vector2 = road.b
		if Geometry2D.segment_intersects_segment(a, b, ra, rb) != null:
			return true
		if _point_segment_distance((a + b) * 0.5, ra, rb) < 14.0:
			return true
	return false

func _morph_profile_at(point: Vector2, specs: Array) -> String:
	var nearest_profile := MORPH_PROFILE_RURAL
	var nearest_distance := INF
	for spec_value in specs:
		var spec: Dictionary = spec_value
		if str(spec.profile) == MORPH_PROFILE_RURAL:
			continue
		var distance := point.distance_squared_to(spec.center)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_profile = str(spec.profile)
	return nearest_profile

func _morph_field_sample(point: Vector2, field_tiles: Dictionary,
		roads: Array) -> Dictionary:
	var nearest: Dictionary = {}
	var nearest_distance := INF
	for tile_value in field_tiles.values():
		var tile: Dictionary = tile_value
		var distance := point.distance_squared_to(tile.core_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = tile
	if nearest.is_empty():
		return {"tile_id": "", "profile": MORPH_PROFILE_VILLAGE,
			"core_position": point, "core_distance": INF, "core_radius": 1.0,
			"road_distance": INF, "road_richness": 0.0, "intensity": 0.0}
	var core_distance := sqrt(nearest_distance)
	var road_distance := _nearest_segment_distance(point, roads)
	# A waterfront belongs to the core, not to its decaying tail.  Along a coastal
	# bearing the effective core radius is stretched to the shoreline, so the
	# reach delivers dense frontage instead of the parks and open ground the
	# low-intensity tail of the role ballot would otherwise produce.  Every other
	# bearing keeps the tile's own radius exactly.
	var core_strength := clampf(1.0 - core_distance /
		maxf(1.0, float(nearest.core_radius) * 1.34), 0.0, 1.0)
	var road_strength := clampf(1.0 - road_distance / 150.0, 0.0, 1.0)
	var intensity := clampf(core_strength * 0.62 + road_strength * 0.30 +
		float(nearest.road_richness) * 0.08, 0.0, 1.0)
	intensity = maxf(intensity, _morph_coastal_intensity(point, nearest))
	return {"tile_id": str(nearest.id), "profile": str(nearest.profile),
		"core_position": nearest.core_position, "core_distance": core_distance,
		"core_radius": float(nearest.core_radius), "road_distance": road_distance,
		"road_richness": float(nearest.road_richness), "intensity": intensity}

func _morph_subdivide_face(face: PackedVector2Array, key: String, depth: int,
		profile: String, intensity: float = 0.5) -> Array:
	var area := _poly_area(face)
	var target := 10500.0
	match profile:
		MORPH_PROFILE_TOWN:
			target = 14000.0
		MORPH_PROFILE_SMALL_TOWN:
			target = 6500.0
		MORPH_PROFILE_FRINGE:
			target = 17000.0
		MORPH_PROFILE_VILLAGE:
			target = 26000.0
	# Dense cores inherit smaller urban grain; road-poor margins resolve into
	# larger parcels before their role is chosen.
	target *= lerpf(1.48, 0.26, clampf(intensity, 0.0, 1.0))
	target *= _rr("%s|target" % key, 0.78, 1.22)
	if area <= target or depth >= MORPH_MAX_SPLIT_DEPTH:
		return [face]
	var edge_index := _hero_longest_edge(face)
	var edge_a := face[edge_index]
	var edge_b := face[(edge_index + 1) % face.size()]
	var frontage := (edge_b - edge_a).normalized()
	if frontage == Vector2.ZERO:
		return [face]
	var split_axis := Vector2(-frontage.y, frontage.x)
	if RoadHash.pick("%s|oblique" % key, 100) < 72:
		var angle := _rr("%s|oblique-angle" % key, 0.10, 0.25)
		if RoadHash.pick("%s|oblique-side" % key, 2) == 0:
			angle = -angle
		split_axis = split_axis.rotated(angle)
	var center := _poly_center(face)
	center += frontage * _rr("%s|split-offset" % key, -0.17, 0.17) * sqrt(area)
	var span := _bbox(face).size.length() + 24.0
	var corridor := _segment_quad(center - split_axis * span, center + split_axis * span,
		HERO_ALLEY_HALF_WIDTH)
	var raw := Geometry2D.clip_polygons(face, corridor)
	var pieces: Array = []
	for piece_value in raw:
		var piece: PackedVector2Array = piece_value
		if piece.size() >= 3 and _poly_area(piece) >= MORPH_FACE_MIN_AREA:
			pieces.append(piece)
	if pieces.size() < 2:
		return [face]
	_hero_record_alley(face, corridor, split_axis)
	var out: Array = []
	for i in pieces.size():
		out.append_array(_morph_subdivide_face(pieces[i], "%s|%d" % [key, i],
			depth + 1, profile, intensity))
	return out

func _assign_morph_roles(records: Array, component_key: String, specs: Array,
		industry_sites: Array, field_tiles: Dictionary) -> void:
	var village_records: Array = []
	var records_by_tile: Dictionary = {}
	for record_value in records:
		var record: Dictionary = record_value
		var profile := str(record.profile)
		var owner_tile := str(record.get("owner_tile", ""))
		if not records_by_tile.has(owner_tile):
			records_by_tile[owner_tile] = []
		(records_by_tile[owner_tile] as Array).append(record)
		if profile == MORPH_PROFILE_VILLAGE:
			village_records.append(record)
			continue
		var roll := RoadHash.pick("%s|field-role" % str(record.key), 100)
		var intensity := float(record.get("growth_intensity", 0.0))
		var built_cut := clampi(roundi(24.0 + intensity * 67.0), 24, 91)
		var park_share := roundi(18.0 + (1.0 - intensity) * 15.0)
		var yard_share := 0
		match profile:
			MORPH_PROFILE_METRO:
				built_cut = mini(94, built_cut + 5)
			MORPH_PROFILE_TOWN:
				built_cut = mini(91, built_cut + 1)
			MORPH_PROFILE_SMALL_TOWN:
				built_cut = mini(93, built_cut + 8)
			MORPH_PROFILE_FRINGE:
				built_cut = maxi(20, built_cut - 12)
				yard_share = roundi(17.0 + (1.0 - intensity) * 15.0)
			_:
				pass
		if roll < built_cut:
			record.role = "built"
		else:
			var residual := roll - built_cut
			if residual < park_share:
				record.role = "park"
			elif residual < park_share + yard_share:
				record.role = "yard"
			else:
				record.role = "open"

	# Every usable authoritative urban tile contributes a guaranteed visible
	# core. Select the closest usable parcel(s), not a tile-centred stamp.
	for tile_id_value in field_tiles:
		var tile_id := str(tile_id_value)
		var candidates: Array = records_by_tile.get(tile_id, [])
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if not is_equal_approx(float(a.core_distance), float(b.core_distance)):
				return float(a.core_distance) < float(b.core_distance)
			return str(a.key) < str(b.key))
		var core_count := mini(candidates.size(), 2 if str(
			(field_tiles[tile_id] as Dictionary).profile) == MORPH_PROFILE_VILLAGE else 3)
		var selected := 0
		for candidate_value in candidates:
			var candidate: Dictionary = candidate_value
			var center := _poly_center(candidate.poly)
			var tile: Dictionary = field_tiles[tile_id]
			if center.distance_to(tile.core_position) > float(tile.core_radius) * 0.82:
				continue
			candidate.role = "village_built" if str(candidate.profile) == \
				MORPH_PROFILE_VILLAGE else "built"
			candidate["forced_core"] = true
			selected += 1
			if selected >= core_count:
				break
		# If exclusions left no parcel centroid in the core circle, mark the nearest
		# record and let the forced-core fallback intersect it with the core zone.
		if selected == 0 and not candidates.is_empty():
			var candidate: Dictionary = candidates[0]
			candidate.role = "village_built" if str(candidate.profile) == \
				MORPH_PROFILE_VILLAGE else "built"
			candidate["forced_core"] = true
	# Reserve only the nearest few fringe parcels. The first candidate used a
	# broad distance threshold and converted entire districts into yards.
	var reserve_candidates: Array = []
	for record_value in records:
		var record: Dictionary = record_value
		if str(record.profile) != MORPH_PROFILE_FRINGE:
			continue
		reserve_candidates.append({
			"record": record,
			"distance": _morph_nearest_industry_distance(_poly_center(record.poly), industry_sites),
		})
	reserve_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da := float(a.distance)
		var db := float(b.distance)
		return da < db if not is_equal_approx(da, db) else str(a.record.key) < str(b.record.key)
	)
	var reserve_count := mini(reserve_candidates.size(),
		clampi(ceili(float(industry_sites.size()) / 3.0), 0, 3))
	for i in reserve_count:
		(reserve_candidates[i].record as Dictionary).role = "yard"
	if village_records.is_empty():
		return
	village_records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a.get("forced_core", false)) != bool(b.get("forced_core", false)):
			return bool(a.get("forced_core", false))
		if not is_equal_approx(float(a.core_distance), float(b.core_distance)):
			return float(a.core_distance) < float(b.core_distance)
		return str(a.key) < str(b.key)
	)
	for record_value in village_records:
		var record: Dictionary = record_value
		if bool(record.get("forced_core", false)):
			record.role = "village_built"
		elif float(record.get("growth_intensity", 0.0)) > 0.58 and RoadHash.pick(
				"%s|village-field" % str(record.key), 100) < 34:
			record.role = "village_built"
		else:
			record.role = "none"

func _plan_accommodation_sites(specs: Array, roads: Array,
		gameplay_sites: Array, water_exclusions: Array, relief_shoulders: Array,
		role_records: Array, extra_exclusions: Array,
		plan: SettlementPlan = null) -> Array:
	var out: Array = []
	for spec_value in specs:
		var spec: Dictionary = spec_value
		var profile := str(spec.profile)
		if profile == MORPH_PROFILE_RURAL:
			continue
		var allowed: Array = []
		var allowed_roles: Dictionary = {}
		for record_value in role_records:
			var record: Dictionary = record_value
			var role := str(record.get("role", "none"))
			if str(_nearest_spec(_poly_center(record.poly), specs).id) != str(spec.id):
				continue
			allowed.append(record.poly)
			allowed_roles[allowed.size() - 1] = role
		# A gameplay footprint can SPILL across a tile boundary, so selecting it by
		# tile_id alone hides a neighbour's building from this tile's planner — and,
		# because validate_sites() is handed this same list, from its validator too.
		# That is why existing_footprint_overlap_count read zero while sites were
		# visibly reserved underneath existing buildings. Select by GEOMETRY instead:
		# any footprint whose bounds reach this tile's box, whichever tile owns it.
		# (Same defect the K1-A pass fixed for decorative masses — "source-tile-only
		# footprint discovery" — which the accommodation planner never inherited.)
		var tile_box := Rect2(spec.center - TILE_CENTER, TILE_CENTER * 2.0).grow(
			ACCOMMODATION_FOOTPRINT_REACH)
		var tile_gameplay: Array = []
		for gameplay_value in gameplay_sites:
			var gameplay: Dictionary = gameplay_value
			var bb: Rect2 = gameplay.get("rect", Rect2())
			if bb.size.x <= 0.0 or bb.size.y <= 0.0:
				# No bounds recorded — fall back to the old ownership test rather
				# than silently dropping the footprint.
				if str(gameplay.get("tile_id", "")) == str(spec.id):
					tile_gameplay.append(gameplay)
				continue
			if tile_box.intersects(bb):
				tile_gameplay.append(gameplay)
		var service_lanes: Array = []
		if _buildings != null and _buildings.has_method(
				"midcentury_service_lanes_on_tile"):
			service_lanes = _buildings.midcentury_service_lanes_on_tile(spec.coord)
		var tile_forests: Array = []
		if _forests != null and _forests.has_method("discs_on_tile"):
			tile_forests = _forests.discs_on_tile(spec.coord)
		var result := AccommodationSitePlanner.plan_tile(str(spec.id), spec.center,
			profile, roads, service_lanes, tile_gameplay, water_exclusions,
			relief_shoulders, tile_forests, extra_exclusions, allowed)
		var sites: Array = result.sites
		for site_value in sites:
			var site: Dictionary = site_value
			var containing_role := "open"
			for allowed_index in allowed.size():
				if Geometry2D.is_point_in_polygon(site.center, allowed[allowed_index]):
					containing_role = str(allowed_roles.get(allowed_index, "open"))
					break
			if containing_role == "park":
				site.visual_use = "releasable_park"
			elif containing_role == "yard":
				site.visual_use = ("industrial_growth" if profile == MORPH_PROFILE_FRINGE
					and str(site.size_class) == "large" else "releasable_yard")
			else:
				site.visual_use = "hard_open_lot"
			out.append(site)
			_accommodation_sites.append(site)
			if plan != null:
				plan.accommodation_sites.append(site.duplicate(true))
		_register_accommodation_diagnostics(str(spec.id), result.diagnostics)
	return out

func _accommodation_frontage_bay(site: Dictionary) -> PackedVector2Array:
	var a: Vector2 = site.access_a
	var b: Vector2 = site.access_b
	var tangent := (b - a).normalized()
	if tangent == Vector2.ZERO:
		return site.poly
	var road_point := _closest_point_on_segment(site.center, a, b)
	var outward := Vector2(-tangent.y, tangent.x)
	if ((site.center as Vector2) - road_point).dot(outward) < 0.0:
		outward = -outward
	# Use the road tangent as the bay frontage and the actual road-to-site vector
	# as its depth. The bay starts on the real carriageway and reaches just past
	# the site's back edge, removing a whole street-wall segment rather than
	# punching a disconnected hole through one.
	var low_u := 0.0
	var high_u := 0.0
	var low_v := 0.0
	var high_v := 0.0
	for point in (site.poly as PackedVector2Array):
		var delta := point - road_point
		low_u = minf(low_u, delta.dot(tangent))
		high_u = maxf(high_u, delta.dot(tangent))
		low_v = minf(low_v, delta.dot(outward))
		high_v = maxf(high_v, delta.dot(outward))
	var bay_center: Vector2 = road_point + tangent * (low_u + high_u) * 0.5 + \
		outward * (low_v + high_v) * 0.5
	return _oriented_rect_poly(bay_center, tangent, outward,
		high_u - low_u + 9.0, high_v - low_v + 9.0)

func _draw_accommodation_sites(sites: Array, parcel_entries: Array,
		yard_entries: Array, park_entries: Array) -> void:
	for site_value in sites:
		var site: Dictionary = site_value
		var poly: PackedVector2Array = site.poly
		if not _poly_on_dry_land(poly):
			_dry_land_rejections.accommodation = int(
				_dry_land_rejections.accommodation) + 1
			continue
		var use := str(site.visual_use)
		var key := str(site.key)
		if use == "releasable_park":
			park_entries.append({"poly": poly,
				"color": MapMidcenturyStyle.park(key),
				"kind": "accommodation_park",
				"role": "accommodation_release"})
			_append_ring(_block_edges, poly)
			_hero_add_park_mark(poly)
		elif use in ["releasable_yard", "industrial_growth"]:
			yard_entries.append({"poly": poly,
				"color": MapMidcenturyStyle.industrial_yard(key)})
			_append_ring(_parcel_edges, poly)
			_add_accommodation_yard_marks(site)
		else:
			parcel_entries.append({"poly": poly,
				"color": MapMidcenturyStyle.vacant_lot(key),
				"role": "accommodation_lot"})
			_append_ring(_parcel_edges, poly)
			_add_accommodation_lot_marks(site)

func _add_accommodation_lot_marks(site: Dictionary) -> void:
	var center: Vector2 = site.center
	var tangent: Vector2 = site.tangent
	var normal: Vector2 = site.normal
	var scale := 4.0 if str(site.size_class) == "small" else 7.0
	_append_line(_open_lot_marks, center - tangent * scale,
		center + tangent * scale)
	if str(site.size_class) == "large":
		_append_line(_open_lot_marks, center - normal * 6.0,
			center + normal * 6.0)

func _add_accommodation_yard_marks(site: Dictionary) -> void:
	var center: Vector2 = site.center
	var tangent: Vector2 = site.tangent
	var normal: Vector2 = site.normal
	var extent := 5.0 if str(site.size_class) == "small" else 8.0
	for index in [-1, 1]:
		var mark_center := center + tangent * float(index) * extent * 0.55
		_append_line(_open_lot_marks, mark_center - normal * extent * 0.62,
			mark_center + normal * extent * 0.62)

func _closest_point_on_segment(point: Vector2, a: Vector2,
		b: Vector2) -> Vector2:
	var ab := b - a
	if ab.length_squared() <= 0.0001:
		return a
	var t := clampf((point - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return a + ab * t

func _nearest_spec(point: Vector2, specs: Array) -> Dictionary:
	var nearest: Dictionary = specs[0] if not specs.is_empty() else {}
	var best := INF
	for spec_value in specs:
		var spec: Dictionary = spec_value
		var distance := point.distance_squared_to(spec.center)
		if distance < best:
			best = distance
			nearest = spec
	return nearest

func _register_accommodation_diagnostics(tile_id: String,
		diagnostics: Dictionary) -> void:
	var accommodation: Dictionary = _metrics.accommodation
	(accommodation.tiles as Dictionary)[tile_id] = diagnostics.duplicate(true)
	accommodation.total_sites = int(accommodation.total_sites) + int(
		diagnostics.valid_count)
	if bool(diagnostics.constrained):
		(accommodation.constrained_tiles as Array).append({
			"tile_id": tile_id,
			"valid_count": int(diagnostics.valid_count),
			"target": int(diagnostics.target),
			"shortfall": int(diagnostics.shortfall),
			"rejected": diagnostics.rejected,
		})
	for key in (accommodation.failure_totals as Dictionary):
		(accommodation.failure_totals as Dictionary)[key] = int(
			(accommodation.failure_totals as Dictionary)[key]) + int(
				diagnostics.get(key, 0))

func _plan_accommodation_summary(tile_ids: Array) -> Dictionary:
	var summary := {"site_count": 0, "tiles": {}, "constrained_tiles": [],
		"failure_totals": {"pairwise_overlap_count": 0,
			"water_overlap_count": 0, "contour_overlap_count": 0,
			"existing_footprint_overlap_count": 0,
			"decorative_mass_overlap_count": 0}}
	for tile_id_value in tile_ids:
		var tile_id := str(tile_id_value)
		var tile_metrics: Dictionary = (_metrics.accommodation.tiles as Dictionary).get(
			tile_id, {})
		if tile_metrics.is_empty():
			continue
		summary.tiles[tile_id] = tile_metrics.duplicate(true)
		summary.site_count = int(summary.site_count) + int(
			tile_metrics.get("valid_count", 0))
		if bool(tile_metrics.get("constrained", false)):
			(summary.constrained_tiles as Array).append({
				"tile_id": tile_id,
				"valid_count": int(tile_metrics.get("valid_count", 0)),
				"target": int(tile_metrics.get("target", 0)),
				"shortfall": int(tile_metrics.get("shortfall", 0)),
			})
		for key in (summary.failure_totals as Dictionary):
			(summary.failure_totals as Dictionary)[key] = int(
				(summary.failure_totals as Dictionary)[key]) + int(
					tile_metrics.get(key, 0))
	return summary

func _finalize_accommodation_mass_overlap(sites: Array, masses: Array) -> void:
	var by_tile: Dictionary = {}
	var keys_by_tile: Dictionary = {}
	for site_value in sites:
		var site: Dictionary = site_value
		var overlap := false
		for mass_value in masses:
			var mass: Dictionary = mass_value
			if _polys_overlap_area(site.poly, mass.poly) > 0.05:
				overlap = true
				break
		if overlap:
			var tile_id := str(site.tile_id)
			by_tile[tile_id] = int(by_tile.get(tile_id, 0)) + 1
			if not keys_by_tile.has(tile_id):
				keys_by_tile[tile_id] = []
			(keys_by_tile[tile_id] as Array).append(str(site.key))
	for tile_id_value in by_tile:
		var tile_id := str(tile_id_value)
		var tile_metrics: Dictionary = (_metrics.accommodation.tiles as Dictionary).get(
			tile_id, {})
		tile_metrics.decorative_mass_overlap_count = int(by_tile[tile_id])
		tile_metrics.decorative_mass_overlap_keys = keys_by_tile[tile_id]
		(_metrics.accommodation.tiles as Dictionary)[tile_id] = tile_metrics
	_metrics.accommodation.failure_totals.decorative_mass_overlap_count = int(
		_metrics.accommodation.failure_totals.decorative_mass_overlap_count) + \
		by_tile.values().reduce(func(total: int, count: Variant) -> int:
			return total + int(count), 0)

func _morph_nearest_industry_distance(point: Vector2, industry_sites: Array) -> float:
	var best := INF
	for site_value in industry_sites:
		var site: Dictionary = site_value
		var rect: Rect2 = site.rect
		var nearest := Vector2(
			clampf(point.x, rect.position.x, rect.end.x),
			clampf(point.y, rect.position.y, rect.end.y)
		)
		best = minf(best, point.distance_to(nearest))
	return best

func _morph_industry_exclusions(industry_sites: Array, component_key: String) -> Array:
	var out: Array = []
	for i in industry_sites.size():
		var site: Dictionary = industry_sites[i]
		var site_key := "%s|industry|%s|%d" % [component_key,
			str(site.get("instance_id", "site")), i]
		var rect: Rect2 = (site.rect as Rect2).grow(_rr("%s|halo" % site_key, 13.0, 18.0))
		var chamfer := minf(_rr("%s|chamfer" % site_key, 5.0, 11.0),
			minf(rect.size.x, rect.size.y) * 0.22)
		var poly := PackedVector2Array([
			rect.position + Vector2(chamfer, 0.0),
			Vector2(rect.end.x - chamfer, rect.position.y),
			Vector2(rect.end.x, rect.position.y + chamfer),
			rect.end - Vector2(0.0, chamfer),
			rect.end - Vector2(chamfer, 0.0),
			Vector2(rect.position.x + chamfer, rect.end.y),
			Vector2(rect.position.x, rect.end.y - chamfer),
			Vector2(rect.position.x, rect.position.y + chamfer),
		])
		out.append({"poly": poly, "bb": rect, "key": site_key,
			"instance_id": str(site.get("instance_id", ""))})
	return out

func _morph_add_industry_yards(industry_exclusions: Array, street_faces: Array,
		component_key: String, yard_entries: Array) -> float:
	var area := 0.0
	for i in industry_exclusions.size():
		var exclusion: Dictionary = industry_exclusions[i]
		var piece_index := 0
		for face_value in street_faces:
			var face: PackedVector2Array = face_value
			if not _bbox(face).intersects(exclusion.bb):
				continue
			for draw_value in exclusion.get("draw_polys", [exclusion.poly]):
				var draw_poly: PackedVector2Array = draw_value
				for piece_value in Geometry2D.intersect_polygons(face, draw_poly):
					var piece: PackedVector2Array = piece_value
					if piece.size() < 3 or _poly_area(piece) < 120.0:
						continue
					var yard_key := "%s|yard|%d|%d" % [component_key, i, piece_index]
					var yard_instance := str(exclusion.get("instance_id", ""))
					var yard_color := MapMidcenturyStyle.industrial_yard(yard_key)
					if _is_industry_landmark(yard_instance):
						yard_color = MapMidcenturyStyle.industry_landmark_yard(
							_industry_landmark_key(yard_instance))
					yard_entries.append({
						"poly": piece,
						"color": yard_color,
					})
					_active_relief_fills.append({"key": yard_key,
						"poly": piece.duplicate(), "role": "yard"})
					area += _poly_area(piece)
					piece_index += 1
	return area

func _morph_add_face(record: Dictionary, footprint_exclusions: Array,
		parcel_entries: Array, shadow_entries: Array, park_entries: Array,
		block_entries: Array) -> Dictionary:
	var face: PackedVector2Array = record.poly
	var role := str(record.role)
	var profile := str(record.profile)
	var key := str(record.key)
	var zero := {"built_area": 0.0, "green_area": 0.0, "yard_area": 0.0, "open_area": 0.0}
	if role == "none":
		return zero
	if _poly_overlaps_active_relief(face) > 0.001:
		return zero
	if role == "village_built":
		return _morph_add_village_cluster(face, key, footprint_exclusions,
			parcel_entries, shadow_entries, block_entries,
			bool(record.get("forced_core", false)))
	var parcel_color := MapMidcenturyStyle.PAPER
	if role == "yard":
		parcel_color = MapMidcenturyStyle.industrial_yard(key)
	elif role == "open":
		parcel_color = MapMidcenturyStyle.vacant_lot(key)
	parcel_entries.append({"poly": face, "color": parcel_color,
		"role": "face_%s" % role})
	_active_relief_fills.append({"key": key, "poly": face.duplicate(),
		"role": "parcel-%s" % role})
	_metrics.parcels = int(_metrics.parcels) + 1
	if role == "park":
		var green_area := 0.0
		var park_sources := _hero_inset_polys(face, _rr("%s|park-inset" % key, 3.2, 6.2))
		for park_value in park_sources:
			for piece_value in _hero_clip_polys([park_value], footprint_exclusions, 120.0):
				var piece: PackedVector2Array = piece_value
				park_entries.append({"poly": piece,
					"color": MapMidcenturyStyle.park(key), "kind": "green",
					"role": "face_park"})
				_active_relief_fills.append({"key": "%s|park" % key,
					"poly": piece.duplicate(), "role": "park"})
				_append_ring(_block_edges, piece)
				green_area += _poly_area(piece)
				_hero_add_park_mark(piece)
		_metrics.parks = int(_metrics.parks) + 1
		return {"built_area": 0.0, "green_area": green_area, "yard_area": 0.0, "open_area": 0.0}
	if role == "open" or role == "yard":
		_append_ring(_parcel_edges, face)
		var center := _poly_center(face)
		var edge := _hero_longest_edge(face)
		var axis := (face[(edge + 1) % face.size()] - face[edge]).normalized()
		if axis != Vector2.ZERO:
			_append_line(_open_lot_marks, center - axis * 8.0, center + axis * 8.0)
		_metrics.open_lots = int(_metrics.open_lots) + 1
		var area := _poly_area(face)
		return {
			"built_area": 0.0, "green_area": 0.0,
			"yard_area": area if role == "yard" else 0.0,
			"open_area": area if role == "open" else 0.0,
		}
	var profile_floor := 0.38 if profile == MORPH_PROFILE_FRINGE else (0.46 if \
		profile == MORPH_PROFILE_TOWN else (0.50 if profile == \
		MORPH_PROFILE_SMALL_TOWN else 0.54))
	var density := lerpf(profile_floor, 0.96,
		clampf(float(record.get("growth_intensity", 0.5)), 0.0, 1.0))
	var form_override := ""
	if _active_plan != null:
		var form_roll := RoadHash.pick("%s|settlement-plan-form" % key, 100)
		form_override = "ring" if form_roll < 48 else ("u" if form_roll < 78 else "l")
	var mass_start := _decorative_mass_records.size()
	var result: Dictionary
	if profile == MORPH_PROFILE_SMALL_TOWN:
		result = _morph_add_small_town_micro(face, key, str(record.cluster),
			footprint_exclusions, shadow_entries, park_entries, block_entries,
			density, float(record.get("growth_intensity", 0.5)))
	else:
		result = _hero_add_street_walls(face, key,
			str(record.cluster), footprint_exclusions, shadow_entries, park_entries,
			block_entries, "", density, profile, form_override)
	if bool(record.get("forced_core", false)):
		var core_has_mass := false
		var core_position: Vector2 = record.get("core_position", _poly_center(face))
		var core_radius := float(record.get("core_radius", 80.0))
		for mass_value in _decorative_mass_records.slice(mass_start):
			var mass: Dictionary = mass_value
			if _poly_center(mass.poly).distance_to(core_position) <= core_radius * 0.82:
				core_has_mass = true
				break
		if not core_has_mass:
			var core_exclusions := footprint_exclusions.duplicate(true)
			for mass_value in _decorative_mass_records.slice(mass_start):
				var mass: Dictionary = mass_value
				core_exclusions.append({"poly": mass.poly, "bb": _bbox(mass.poly)})
			var added := _morph_add_forced_core_mass(face, core_position,
				core_radius, key, profile, density, core_exclusions, shadow_entries,
				block_entries)
			result.built_area = float(result.built_area) + added
	return {
		"built_area": float(result.built_area), "green_area": float(result.green_area),
		"yard_area": 0.0, "open_area": 0.0,
	}

func _morph_add_small_town_micro(face: PackedVector2Array, key: String,
		color_cluster: String, exclusions: Array, shadow_entries: Array,
		park_entries: Array, block_entries: Array, density: float,
		growth_intensity: float) -> Dictionary:
	# Compact towns need addressable street frontage, not one footprint-shaped
	# roof per parcel. Divide one or two coherent rows into small attached or
	# near-attached masses; the slot gaps are subordinate alleys, never roads.
	var edge := _hero_longest_edge(face)
	var a := face[edge]
	var b := face[(edge + 1) % face.size()]
	var tangent := (b - a).normalized()
	if tangent == Vector2.ZERO:
		return {"built_area": 0.0, "green_area": 0.0}
	var inward := _hero_inward_normal(face, a, b)
	var frontage := a.distance_to(b)
	var area := _poly_area(face)
	var primary_count := clampi(roundi(frontage / lerpf(31.0, 23.0,
		growth_intensity)), 2, 6)
	var rows := 2 if area >= 4700.0 and growth_intensity >= 0.56 else 1
	var built_area := 0.0
	var green_area := 0.0
	var local_index := 0
	var max_primary_depth := 0.0
	for row in rows:
		var row_count := primary_count if row == 0 else maxi(2, primary_count - 1)
		var usable_frontage := maxf(24.0, frontage - 8.0)
		var slot := usable_frontage / float(row_count)
		var row_depth := _rr("%s|micro-depth|%d" % [key, row],
			13.0 if row == 0 else 11.0, 21.0 if row == 0 else 17.0)
		if row == 0:
			max_primary_depth = row_depth
		var row_inset := 2.2 + row_depth * 0.5
		if row == 1:
			row_inset = 4.8 + max_primary_depth + row_depth * 0.5
		for child in row_count:
			var child_key := "%s|micro|%d|%d" % [key, row, child]
			var gap := _rr("%s|gap" % child_key, 1.5, 3.0)
			var child_length := maxf(8.0, slot - gap)
			var offset := -usable_frontage * 0.5 + slot * (float(child) + 0.5)
			offset += _rr("%s|shift" % child_key, -0.7, 0.7)
			var center := (a + b) * 0.5 + tangent * offset + inward * row_inset
			var candidate := _quad(center, tangent, child_length, row_depth,
				child_key, 0.55)
			var pieces: Array = []
			for inside_value in Geometry2D.intersect_polygons(candidate, face):
				pieces.append_array(_hero_clip_polys([inside_value], exclusions, 62.0))
			if pieces.is_empty():
				continue
			var pocket := row > 0 and RoadHash.pick("%s|pocket" % child_key, 100) < 10
			for piece_value in pieces:
				var piece: PackedVector2Array = piece_value
				var bb := _bbox(piece)
				if minf(bb.size.x, bb.size.y) < 5.2:
					continue
				if pocket:
					park_entries.append({"poly": piece,
						"color": MapMidcenturyStyle.park(child_key),
						"kind": "green", "role": "row_pocket"})
					_append_ring(_block_edges, piece)
					_hero_add_park_mark(piece)
					green_area += _poly_area(piece)
					_metrics.parks = int(_metrics.parks) + 1
				else:
					_add_block(piece, tangent, density, child_key, shadow_entries,
						block_entries, color_cluster, MORPH_PROFILE_SMALL_TOWN)
					built_area += _poly_area(piece)
				local_index += 1
			if child < row_count - 1:
				var alley_center := (a + b) * 0.5 + tangent * (
					-usable_frontage * 0.5 + slot * float(child + 1))
				_append_dry_line(_hero_alleys, alley_center + inward * 1.0,
					alley_center + inward * (row_inset + row_depth * 0.5))
	return {"built_area": built_area, "green_area": green_area,
		"micro_mass_count": local_index}

func _morph_add_forced_core_mass(face: PackedVector2Array,
		core_position: Vector2, core_radius: float, key: String, profile: String,
		density: float, exclusions: Array, shadow_entries: Array,
		block_entries: Array) -> float:
	var core_zone := _circle_poly(core_position, core_radius * 0.76, 18)
	var candidates: Array = []
	for inset_value in _hero_inset_polys(face, 4.0):
		for core_value in Geometry2D.intersect_polygons(inset_value, core_zone):
			var core_piece: PackedVector2Array = core_value
			for available_value in _hero_clip_polys([core_piece], exclusions, 95.0):
				candidates.append(available_value)
	candidates.sort_custom(func(a: PackedVector2Array,
			b: PackedVector2Array) -> bool:
		var da := _poly_center(a).distance_squared_to(core_position)
		var db := _poly_center(b).distance_squared_to(core_position)
		if not is_equal_approx(da, db):
			return da < db
		return _poly_area(a) > _poly_area(b))
	for candidate_value in candidates:
		var candidate: PackedVector2Array = candidate_value
		var scale := clampf(sqrt(520.0 / maxf(520.0, _poly_area(candidate))),
			0.18, 0.78)
		var mass := _scale_poly(candidate, _poly_center(candidate), scale)
		var bb := _bbox(mass)
		if minf(bb.size.x, bb.size.y) < 6.0:
			continue
		var edge := _hero_longest_edge(mass)
		var tangent := (mass[(edge + 1) % mass.size()] - mass[edge]).normalized()
		_add_block(mass, tangent, density, "%s|guaranteed-core" % key,
			shadow_entries, block_entries, "", profile)
		return _poly_area(mass)
	return 0.0

func _morph_add_village_cluster(face: PackedVector2Array, key: String,
		footprint_exclusions: Array, parcel_entries: Array, shadow_entries: Array,
		block_entries: Array, forced_core: bool = false) -> Dictionary:
	var edge := _hero_longest_edge(face)
	var a := face[edge]
	var b := face[(edge + 1) % face.size()]
	var tangent := (b - a).normalized()
	if tangent == Vector2.ZERO:
		return {"built_area": 0.0, "green_area": 0.0, "yard_area": 0.0, "open_area": 0.0}
	var inward := _hero_inward_normal(face, a, b)
	var length := minf(a.distance_to(b) - 8.0, _rr("%s|cluster-length" % key, 46.0, 72.0))
	var depth := _rr("%s|cluster-depth" % key, 19.0, 27.0)
	if length < 24.0:
		return {"built_area": 0.0, "green_area": 0.0, "yard_area": 0.0, "open_area": 0.0}
	var center := (a + b) * 0.5 + inward * (depth * 0.5 + 2.4)
	var rows: Array = [_stepped_row(center, tangent, length, depth,
		2 + RoadHash.pick("%s|cluster-units" % key, 2), "%s|front" % key).poly]
	# A compact back row turns the chosen frontage into a hamlet group rather
	# than a lone rural bar. It remains inside the same road-caused face and
	# does not seed additional clusters across the tile.
	var back_depth := depth * _rr("%s|back-depth" % key, 0.72, 0.88)
	var back_length := length * _rr("%s|back-length" % key, 0.54, 0.72)
	var back_shift := tangent * _rr("%s|back-shift" % key, -0.13, 0.13) * length
	var back_center := center + inward * (depth * 0.5 + back_depth * 0.5 + 5.5) + back_shift
	rows.append(_stepped_row(back_center, tangent, back_length, back_depth,
		2 + RoadHash.pick("%s|back-units" % key, 2), "%s|back" % key).poly)
	var built_area := 0.0
	var piece_index := 0
	for row_value in rows:
		for piece_value in _hero_clip_polys([row_value], footprint_exclusions, 90.0):
			var piece: PackedVector2Array = piece_value
			var lot := _scale_poly(piece, _poly_center(piece), 1.24)
			for lot_value in Geometry2D.intersect_polygons(lot, face):
				var lot_piece: PackedVector2Array = lot_value
				if _poly_area(lot_piece) >= 110.0:
					parcel_entries.append({"poly": lot_piece,
						"color": MapMidcenturyStyle.PAPER, "role": "hamlet_lot"})
			_add_block(piece, tangent, 0.38, "%s|hamlet|%d" % [key, piece_index],
				shadow_entries, block_entries, "", MORPH_PROFILE_VILLAGE)
			built_area += _poly_area(piece)
			piece_index += 1
	if built_area <= 0.0 and forced_core:
		var available := _hero_clip_polys(_hero_inset_polys(face, 4.0),
			footprint_exclusions, 95.0)
		available.sort_custom(func(a: PackedVector2Array,
				b: PackedVector2Array) -> bool:
			var da := _poly_center(a).distance_squared_to(_poly_center(face))
			var db := _poly_center(b).distance_squared_to(_poly_center(face))
			if not is_equal_approx(da, db):
				return da < db
			return _poly_area(a) > _poly_area(b))
		for available_value in available:
			var available_poly: PackedVector2Array = available_value
			var available_bb := _bbox(available_poly)
			if minf(available_bb.size.x, available_bb.size.y) < 7.0:
				continue
			var scale := clampf(sqrt(310.0 / maxf(310.0,
				_poly_area(available_poly))), 0.16, 0.72)
			var fallback := _scale_poly(available_poly,
				_poly_center(available_poly), scale)
			var fallback_bb := _bbox(fallback)
			if minf(fallback_bb.size.x, fallback_bb.size.y) < 6.0:
				continue
			var fallback_edge := _hero_longest_edge(fallback)
			var fallback_tangent := (fallback[(fallback_edge + 1) % fallback.size()] -
				fallback[fallback_edge]).normalized()
			parcel_entries.append({"poly": fallback,
				"color": MapMidcenturyStyle.PAPER, "role": "forced_core_lot"})
			_add_block(fallback, fallback_tangent, 0.38, "%s|forced-core" % key,
				shadow_entries, block_entries, "", MORPH_PROFILE_VILLAGE)
			built_area += _poly_area(fallback)
			break
	if built_area <= 0.0:
		return {"built_area": 0.0, "green_area": 0.0, "yard_area": 0.0, "open_area": 0.0}
	_metrics.parcels = int(_metrics.parcels) + 1
	return {"built_area": built_area, "green_area": 0.0, "yard_area": 0.0, "open_area": 0.0}

func _build_suburban_fringe() -> void:
	# Phase E promotes an already validated relief-safe rural frontage group into
	# a suburban district. It adds no mass and probes no new relief geometry: the
	# houses, gardens and access lanes come directly from Phase D records. Two
	# separated frontage components avoid a uniform suburban ring.
	var configurations := [
		{"key": "vandel-tallow-fringe", "route_id": "e:1166",
			"source_tiles": ["tile_22_16", "tile_23_16"],
			"spill_tiles": ["tile_23_14", "tile_23_15"]},
	]
	for config_value in configurations:
		var config: Dictionary = config_value
		var records: Array = []
		for tile_id_value in config.spill_tiles:
			for record_value in _rural_growth_records.get(str(tile_id_value), []):
				var record: Dictionary = record_value
				if str(record.route_id) == str(config.route_id):
					records.append(record)
		if records.size() < 3:
			_suburban_metrics.road_connection_failure_count = int(
				_suburban_metrics.road_connection_failure_count) + 1
			continue
		var accesses: Array = []
		for record_value in records:
			var record: Dictionary = record_value
			if str(record.role) != "back-row":
				continue
			var access := PackedVector2Array([record.road_point,
				record.center - record.normal * float(record.side) *
					(float(record.depth) * 0.5)])
			_append_dry_line(_settlement_streets, access[0], access[1])
			accesses.append(access)
		if accesses.is_empty():
			_suburban_metrics.road_connection_failure_count = int(
				_suburban_metrics.road_connection_failure_count) + 1
			continue
		var district := SettlementPlan.new("suburban|%s" % str(config.key))
		var district_tiles: Array = config.source_tiles.duplicate()
		district_tiles.append_array(config.spill_tiles)
		district.tile_ids.assign(district_tiles)
		var district_records: Array = []
		for record_value in records:
			var record: Dictionary = record_value
			district_records.append({"key": record.key,
				"poly": record.poly.duplicate(), "lot_poly": record.lot_poly.duplicate(),
				"role": record.role})
		var accommodation_count := 0
		for site_value in _accommodation_sites:
			var site: Dictionary = site_value
			if not (config.source_tiles as Array).has(str(site.tile_id)):
				continue
			district.accommodation_sites.append(site.duplicate(true))
			accommodation_count += 1
			if accommodation_count >= 2:
				break
		district.suburban_districts.append({"key": "%s-fringe" % str(config.key),
			"polys": district_records, "access_streets": accesses})
		_settlement_plans[district.key] = district
		var edge: Dictionary = RoadNetwork.instance().edges.get(str(config.route_id), {})
		var route: PackedVector2Array = edge.get("geometry", PackedVector2Array())
		_suburban_metrics.total_masses = int(_suburban_metrics.total_masses) + records.size()
		_suburban_metrics.access_streets = int(_suburban_metrics.access_streets) + accesses.size()
		_suburban_metrics.cross_tile_districts = int(
			_suburban_metrics.cross_tile_districts) + 1
		(_suburban_metrics.districts as Array).append({
			"key": district.key, "source_tiles": config.source_tiles,
			"touched_tiles": config.spill_tiles, "cross_tile": true,
			"mass_count": records.size(), "small_park_count": records.filter(
				func(record: Dictionary) -> bool: return bool(record.garden)).size(),
			"access_street_count": accesses.size(), "street_width": 3.0,
			"connector_edge_count": 1, "authoritative_edge_id": str(config.route_id),
			"authoritative_route_points": route.size(),
			"accepted_records": records.size(),
			"accommodation_sites": accommodation_count,
		})

func _build_rural_growth(parcel_entries: Array, shadow_entries: Array,
		park_entries: Array, block_entries: Array) -> void:
	# Rural growth is its own road-derived grammar. It never builds a settlement
	# envelope and never invents a route: every frontage, junction group and back
	# row starts from one selected BUILT RoadNetwork edge.
	var coords: Array[Vector2i] = []
	var rural_mass_start := _decorative_mass_records.size()
	for coord_value in _terrain.tiles:
		var coord: Vector2i = coord_value
		var tile_data: Dictionary = _terrain.tiles[coord]
		var tile_id := str(tile_data.get("id", ""))
		var actual_rural := str(tile_data.get("type", "")) == "rural"
		var profiled_rural := str(_metrics.tile_profiles.get(tile_id, "")) == \
			MORPH_PROFILE_RURAL
		if actual_rural or profiled_rural:
			coords.append(coord)
	coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x or (a.x == b.x and a.y < b.y))
	var route_tile_counts: Dictionary = {}
	for coord in coords:
		var tile_data: Dictionary = _terrain.tiles[coord]
		var tile_id := str(tile_data.get("id", "%d_%d" % [coord.x, coord.y]))
		var center := _terrain.map_to_local(_terrain.map_coord_for_tile_coord(coord))
		var route := _rural_primary_route(coord, tile_data)
		if route.is_empty():
			_rural_growth_metrics.roadless_skips = int(
				_rural_growth_metrics.roadless_skips) + 1
			continue
		var road_segments := _rural_all_road_segments(coord)
		var gameplay_sites: Array = []
		if _buildings != null and _buildings.has_method(
				"midcentury_footprint_sites_on_tile"):
			gameplay_sites = _buildings.midcentury_footprint_sites_on_tile(coord)
		var forest_discs: Array = []
		if _forests != null and _forests.has_method("discs_on_tile"):
			forest_discs = _forests.discs_on_tile(coord)
		var extent := PackedVector2Array()
		for vertex in HEX_VERTS:
			extent.append(center + vertex)
		var water_exclusions := _hero_water_exclusions(_bbox(extent))
		var relief := _relief_geometry_for_extents([extent])
		var relief_shoulders: Array = relief.get("shoulders", [])
		_active_plan_water_exclusions = water_exclusions
		_active_relief_shoulders = relief_shoulders
		_active_relief_masses = []
		_active_relief_shadows = []
		_active_relief_roofs = []
		var anchors := _rural_route_anchors(route, center)
		var frontage_target := 4 if str(route.tier) == RoadNetwork.TIER_TRUNK else 3
		var frontage_records: Array = []
		var rejected := {"off_land": 0, "water": 0, "relief": 0,
			"forest": 0, "gameplay": 0, "road": 0, "occupied": 0}
		for anchor_value in anchors:
			if frontage_records.size() >= frontage_target:
				break
			var anchor: Dictionary = anchor_value
			var side := -1.0 if RoadHash.pick("rural-side|%s" % str(anchor.key), 2) == 0 else 1.0
			for side_try in [side, -side]:
				var record := _rural_frontage_candidate(anchor, float(side_try), tile_id,
					frontage_records.size(), false)
				var reason := _rural_candidate_reason(record.lot_poly, center,
					gameplay_sites, water_exclusions, relief_shoulders, forest_discs,
					road_segments)
				if reason != "":
					rejected[reason] = int(rejected.get(reason, 0)) + 1
					continue
				if not _rural_add_candidate(record, "frontage", parcel_entries,
						shadow_entries, park_entries, block_entries):
					continue
				frontage_records.append(record)
				break
		var junction_count := 0
		var junction_record: Dictionary = {}
		if frontage_records.size() >= 2:
			for anchor_value in anchors:
				var anchor: Dictionary = anchor_value
				if not _rural_is_junction(anchor.p, anchor.tangent, road_segments):
					continue
				var side := -1.0 if RoadHash.pick("rural-junction-side|%s" % str(
					anchor.key), 2) == 0 else 1.0
				var record := _rural_frontage_candidate(anchor, side, tile_id,
					frontage_records.size(), true)
				var reason := _rural_candidate_reason(record.lot_poly, center,
					gameplay_sites, water_exclusions, relief_shoulders, forest_discs,
					road_segments)
				if reason == "" and _rural_add_candidate(record, "junction",
						parcel_entries, shadow_entries, park_entries, block_entries):
					junction_count = 1
					junction_record = record
					break
		var back_count := 0
		var back_record: Dictionary = {}
		if frontage_records.size() >= 3:
			var source: Dictionary = frontage_records[RoadHash.pick(
				"rural-back-source|%s" % tile_id, frontage_records.size())]
			var record := _rural_back_row_candidate(source, tile_id)
			var reason := _rural_candidate_reason(record.lot_poly, center,
				gameplay_sites, water_exclusions, relief_shoulders, forest_discs,
				road_segments)
			if reason == "" and _rural_add_candidate(record, "back-row",
					parcel_entries, shadow_entries, park_entries, block_entries):
				back_count = 1
				back_record = record
				_append_dry_line(_service_lines, source.road_point,
					record.center - record.normal * float(record.side) *
					(float(record.depth) * 0.5))
		var front_count := frontage_records.size()
		var total := front_count + junction_count + back_count
		if total <= 0:
			_active_plan_water_exclusions = []
			_active_relief_shoulders = []
			continue
		var route_id := str(route.edge_id)
		var accepted_records: Array = []
		for record_value in frontage_records:
			var record: Dictionary = record_value
			accepted_records.append(_rural_growth_record(record, "frontage", route_id))
		if junction_count > 0:
			accepted_records.append(_rural_growth_record(junction_record,
				"junction", route_id))
		if back_count > 0:
			accepted_records.append(_rural_growth_record(back_record, "back-row", route_id))
		_rural_growth_records[tile_id] = accepted_records
		route_tile_counts[route_id] = int(route_tile_counts.get(route_id, 0)) + 1
		_rural_growth_metrics.total_masses = int(
			_rural_growth_metrics.total_masses) + total
		_rural_growth_metrics.within_frontage_depth = int(
			_rural_growth_metrics.within_frontage_depth) + front_count + junction_count
		_rural_growth_metrics.junction_masses = int(
			_rural_growth_metrics.junction_masses) + junction_count
		_rural_growth_metrics.back_row_masses = int(
			_rural_growth_metrics.back_row_masses) + back_count
		(_rural_growth_metrics.tiles as Dictionary)[tile_id] = {
			"tile_id": tile_id,
			"primary_edge_id": route_id,
			"primary_tier": str(route.tier),
			"selection_reason": str(route.reason),
			"continuity_tile_count": int(route.continuity_tile_count),
			"frontage_masses": front_count,
			"junction_masses": junction_count,
			"back_row_masses": back_count,
			"total_masses": total,
			"within_frontage_depth": front_count + junction_count,
			"frontage_pct": 100.0 * float(front_count + junction_count) /
				maxf(1.0, float(total)),
			"candidate_anchors": anchors.size(),
			"rejected": rejected,
		}
		_active_plan_water_exclusions = []
		_active_relief_shoulders = []
		_active_relief_masses = []
		_active_relief_shadows = []
		_active_relief_roofs = []
	_rural_growth_metrics["route_tile_counts"] = route_tile_counts
	var total := int(_rural_growth_metrics.total_masses)
	_rural_growth_metrics["frontage_pct"] = 100.0 * float(
		_rural_growth_metrics.within_frontage_depth) / maxf(1.0, float(total))
	_finalize_accommodation_mass_overlap(_accommodation_sites,
		_decorative_mass_records.slice(rural_mass_start))

func _rural_growth_record(record: Dictionary, role: String,
		route_id: String) -> Dictionary:
	var garden := role == "back-row" or RoadHash.pick(
		"rural-garden|%s" % str(record.key), 100) < 36
	return {"key": str(record.key), "poly": record.poly.duplicate(),
		"lot_poly": record.lot_poly.duplicate(), "center": record.center,
		"road_point": record.road_point, "tangent": record.tangent,
		"normal": record.normal, "side": record.side, "depth": record.depth,
		"role": role, "route_id": route_id, "garden": garden}

func _rural_primary_route(coord: Vector2i, tile_data: Dictionary) -> Dictionary:
	var candidates: Array = []
	for edge_id_value in RoadNetwork.instance().edges_on_tile(coord):
		var edge_id := str(edge_id_value)
		var edge: Dictionary = RoadNetwork.instance().edges.get(edge_id, {})
		if str(edge.get("state", "")) != RoadNetwork.STATE_BUILT:
			continue
		var geo: PackedVector2Array = edge.get("geometry", PackedVector2Array())
		if geo.size() < 2:
			continue
		var tier := str(edge.get("tier", RoadNetwork.TIER_LOCAL))
		var crosses_boundary := false
		var continuity_tiles: Dictionary = {}
		for edge_coord_value in edge.get("tiles", []):
			var edge_coord: Vector2i = edge_coord_value
			crosses_boundary = crosses_boundary or edge_coord != coord
			if _terrain.tiles.has(edge_coord):
				var other: Dictionary = _terrain.tiles[edge_coord]
				var other_id := str(other.get("id", ""))
				if str(other.get("type", "")) == "rural" or str(
						_metrics.tile_profiles.get(other_id, "")) == MORPH_PROFILE_RURAL:
					continuity_tiles[other_id] = true
		var rank := 99
		var reason := ""
		if tier == RoadNetwork.TIER_TRUNK:
			rank = 0
			reason = "authoritative-trunk"
		elif crosses_boundary:
			rank = 1
			reason = "longest-through-road"
		elif str(tile_data.get("nickname", "")) != "":
			rank = 2
			reason = "named-settlement-road"
		if rank >= 99:
			continue
		candidates.append({"edge_id": edge_id, "edge": edge, "geo": geo,
			"tier": tier, "reason": reason, "rank": rank,
			"length": _rural_polyline_length(geo),
			"continuity_tile_count": continuity_tiles.size()})
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.rank) != int(b.rank):
			return int(a.rank) < int(b.rank)
		if not is_equal_approx(float(a.length), float(b.length)):
			return float(a.length) > float(b.length)
		return str(a.edge_id) < str(b.edge_id))
	return candidates[0]

func _rural_all_road_segments(coord: Vector2i) -> Array:
	var out: Array = []
	for edge_id_value in RoadNetwork.instance().edges_on_tile(coord):
		var edge_id := str(edge_id_value)
		var edge: Dictionary = RoadNetwork.instance().edges.get(edge_id, {})
		if str(edge.get("state", "")) != RoadNetwork.STATE_BUILT:
			continue
		var geo: PackedVector2Array = edge.get("geometry", PackedVector2Array())
		for i in range(geo.size() - 1):
			out.append({"edge_id": edge_id, "a": geo[i], "b": geo[i + 1]})
	return out

func _rural_route_anchors(route: Dictionary, tile_center: Vector2) -> Array:
	var geo: PackedVector2Array = route.geo
	var spacing := 62.0
	var next_distance := 20.0 + float(RoadHash.pick(
		"rural-route-phase|%s" % str(route.edge_id), 37))
	var distance := 0.0
	var out: Array = []
	for i in range(geo.size() - 1):
		var a := geo[i]
		var b := geo[i + 1]
		var segment_length := a.distance_to(b)
		if segment_length <= 0.001:
			continue
		while next_distance <= distance + segment_length:
			var t := (next_distance - distance) / segment_length
			var point := a.lerp(b, t)
			if _inside_hex(point, tile_center, 20.0):
				out.append({"p": point, "tangent": (b - a).normalized(),
					"key": "%s|%d" % [str(route.edge_id), roundi(next_distance)],
					"route_distance": next_distance})
			next_distance += spacing
		distance += segment_length
	if out.is_empty():
		var midpoint := geo[0].lerp(geo[geo.size() - 1], 0.5)
		if _inside_hex(midpoint, tile_center, 20.0):
			out.append({"p": midpoint,
				"tangent": (geo[geo.size() - 1] - geo[0]).normalized(),
				"key": "%s|mid" % str(route.edge_id),
				"route_distance": distance * 0.5})
	return out

func _rural_frontage_candidate(anchor: Dictionary, side: float,
		tile_id: String, index: int, junction: bool) -> Dictionary:
	var tangent: Vector2 = anchor.tangent
	var normal := Vector2(-tangent.y, tangent.x)
	var key := "rural|%s|%s|%d%s" % [tile_id, str(anchor.key), index,
		"|junction" if junction else ""]
	var length := _rr("%s|length" % key, 19.0, 38.0)
	var depth := _rr("%s|depth" % key, 12.0, 19.0)
	if RoadHash.pick("%s|terrace" % key, 100) < 24:
		length = _rr("%s|terrace-length" % key, 38.0, 54.0)
	var road_point: Vector2 = anchor.p
	var center := road_point + normal * side * (15.0 + depth * 0.5)
	var row: Dictionary = _stepped_row(center, tangent, length, depth,
		clampi(roundi(length / 18.0), 1, 3), key)
	var mass: PackedVector2Array = row.poly
	var lot: PackedVector2Array = _scale_poly(mass, center,
		_rr("%s|lot-scale" % key, 1.22, 1.40))
	return {"key": key, "poly": mass, "lot_poly": lot, "center": center,
		"road_point": road_point, "tangent": tangent, "normal": normal,
		"side": side, "length": length, "depth": depth}

func _rural_back_row_candidate(source: Dictionary, tile_id: String) -> Dictionary:
	var key := "%s|back" % str(source.key)
	var tangent: Vector2 = source.tangent
	var normal: Vector2 = source.normal
	var side := float(source.side)
	var length := _rr("%s|length" % key, 18.0, 31.0)
	var depth := _rr("%s|depth" % key, 11.0, 16.0)
	var center: Vector2 = source.center + normal * side * (
		float(source.depth) * 0.5 + depth * 0.5 + 9.0) + tangent * _rr(
			"%s|shift" % key, -8.0, 8.0)
	var mass: PackedVector2Array = _quad(center, tangent, length, depth, key, 0.7)
	var lot: PackedVector2Array = _scale_poly(mass, center,
		_rr("%s|lot-scale" % key, 1.24, 1.38))
	return {"key": key, "poly": mass, "lot_poly": lot, "center": center,
		"road_point": source.road_point, "tangent": tangent, "normal": normal,
		"side": side, "length": length, "depth": depth, "tile_id": tile_id}

func _rural_add_candidate(record: Dictionary, role: String,
		parcel_entries: Array, shadow_entries: Array, park_entries: Array,
		block_entries: Array) -> bool:
	var before := _decorative_mass_records.size()
	var lot_color := MapMidcenturyStyle.vacant_lot("%s|garden" % str(record.key))
	if role == "back-row" or RoadHash.pick("rural-garden|%s" % str(record.key), 100) < 36:
		lot_color = MapMidcenturyStyle.park("%s|garden" % str(record.key))
	parcel_entries.append({"poly": record.lot_poly, "color": lot_color,
		"role": "rural_garden"})
	_append_ring(_parcel_edges, record.lot_poly)
	_add_block(record.poly, record.tangent, 0.28, str(record.key),
		shadow_entries, block_entries, "", MORPH_PROFILE_VILLAGE)
	if _decorative_mass_records.size() == before:
		parcel_entries.pop_back()
		return false
	_metrics.parcels = int(_metrics.parcels) + 1
	if lot_color in MapMidcenturyStyle.PARKS:
		_hero_add_park_mark(record.lot_poly)
		_metrics.parks = int(_metrics.parks) + 1
	return true

func _rural_candidate_reason(poly: PackedVector2Array, tile_center: Vector2,
		gameplay_sites: Array, water_exclusions: Array, relief_shoulders: Array,
		forests: Array, roads: Array) -> String:
	var shadow := _offset(poly, BLOCK_SHADOW_OFFSET)
	for candidate in [poly, shadow]:
		if not _poly_on_dry_land(candidate as PackedVector2Array):
			return "water"
		for point in (candidate as PackedVector2Array):
			if not _inside_hex(point, tile_center, 14.0) or not _land_clear(point):
				return "off_land"
		for exclusion_value in water_exclusions:
			var exclusion: Dictionary = exclusion_value
			if _bbox(candidate).intersects(exclusion.bb) and _polys_overlap_area(
					candidate, exclusion.poly) > 0.001:
				return "water"
		for shoulder_value in relief_shoulders:
			var shoulder: Dictionary = shoulder_value
			if _bbox(candidate).intersects(shoulder.bb) and _polys_overlap_area(
					candidate, shoulder.poly) > 0.001:
				return "relief"
		for site_value in gameplay_sites:
			var site: Dictionary = site_value
			if _polys_overlap_area(candidate, site.poly) > 0.001:
				return "gameplay"
		for forest_value in forests:
			var forest: Dictionary = forest_value
			var radius := float(forest.radius) + FOREST_CLEAR
			if Geometry2D.is_point_in_polygon(forest.center, candidate):
				return "forest"
			for point in (candidate as PackedVector2Array):
				if point.distance_to(forest.center) < radius:
					return "forest"
		for road_value in roads:
			var road: Dictionary = road_value
			for point in (candidate as PackedVector2Array):
				if _point_segment_distance(point, road.a, road.b) < 5.5:
					return "road"
		for mass_value in _decorative_mass_records:
			var mass: Dictionary = mass_value
			if _polys_overlap_area(candidate, mass.poly) > 0.001:
				return "occupied"
		for site_value in _accommodation_sites:
			var site: Dictionary = site_value
			if _polys_overlap_area(candidate, site.poly) > 0.001:
				return "occupied"
	return ""

func _rural_is_junction(point: Vector2, tangent: Vector2, roads: Array) -> bool:
	for road_value in roads:
		var road: Dictionary = road_value
		if _point_segment_distance(point, road.a, road.b) > 26.0:
			continue
		var other := ((road.b as Vector2) - (road.a as Vector2)).normalized()
		if other != Vector2.ZERO and absf(tangent.dot(other)) < 0.74:
			return true
	return false

func _rural_polyline_length(geo: PackedVector2Array) -> float:
	var length := 0.0
	for i in range(geo.size() - 1):
		length += geo[i].distance_to(geo[i + 1])
	return length

func _build_hero_arin(coords: Array[Vector2i], parcel_entries: Array,
		shadow_entries: Array, park_entries: Array, block_entries: Array) -> void:
	if coords.is_empty():
		return
	var centers: Array[Vector2] = []
	var footprints: Array = []
	var gameplay_sites: Array = []
	var forest_discs: Array = []
	var road_segments: Array = []
	var specs: Array = []
	var seen_edges: Dictionary = {}
	for coord in coords:
		var center := _terrain.map_to_local(_terrain.map_coord_for_tile_coord(coord))
		centers.append(center)
		var tile_data: Dictionary = _terrain.tiles[coord]
		var tile_id := str(tile_data.get("id", "%d_%d" % [coord.x, coord.y]))
		specs.append({"coord": coord, "id": tile_id, "center": center,
			"profile": MORPH_PROFILE_METRO})
		if _buildings != null and _buildings.has_method("footprint_rects_on_tile"):
			footprints.append_array(_buildings.footprint_rects_on_tile(coord))
		if _buildings != null and _buildings.has_method(
				"midcentury_footprint_sites_on_tile"):
			gameplay_sites.append_array(
				_buildings.midcentury_footprint_sites_on_tile(coord))
		if _forests != null and _forests.has_method("discs_on_tile"):
			forest_discs.append_array(_forests.discs_on_tile(coord))
		for edge_id_value in RoadNetwork.instance().edges_on_tile(coord):
			var edge_id := str(edge_id_value)
			if seen_edges.has(edge_id):
				continue
			seen_edges[edge_id] = true
			var edge: Dictionary = RoadNetwork.instance().edges.get(edge_id, {})
			if str(edge.get("state", "")) != RoadNetwork.STATE_BUILT:
				continue
			var geo: PackedVector2Array = edge.get("geometry", PackedVector2Array())
			var trunk := str(edge.get("tier", "")) == RoadNetwork.TIER_TRUNK
			for i in range(geo.size() - 1):
				road_segments.append({"a": geo[i], "b": geo[i + 1], "trunk": trunk,
					"edge_id": edge_id})

	var envelopes := _hero_envelopes(centers)
	var envelope_bounds := _hero_polys_bbox(envelopes)
	var water_exclusions := _hero_water_exclusions(envelope_bounds)
	var natural_exclusions := water_exclusions.duplicate(true)
	natural_exclusions.append_array(_hero_forest_exclusions(forest_discs))
	envelopes = _hero_clip_polys(envelopes, natural_exclusions, HERO_FACE_MIN_AREA)
	var envelope_area := _hero_polys_area(envelopes)
	var road_corridors := _hero_road_corridors(road_segments)
	var street_faces := _hero_clip_polys(envelopes, road_corridors, HERO_FACE_MIN_AREA)
	var faces: Array = []
	for i in street_faces.size():
		var face: PackedVector2Array = street_faces[i]
		for parcel_value in _hero_subdivide_face(face, "hero-arin-face|%d" % i, 0):
			faces.append({"poly": parcel_value, "street_face": i})

	var footprint_exclusions := _hero_footprint_exclusions(footprints)
	var built_area := 0.0
	var green_area := 0.0
	var mass_start := _decorative_mass_records.size()
	for i in faces.size():
		var face_entry: Dictionary = faces[i]
		var face: PackedVector2Array = face_entry.poly
		var color_cluster := "hero-arin-street-face|%d" % int(face_entry.street_face)
		var result := _hero_add_face(face, "hero-arin-parcel|%d" % i, color_cluster,
			footprint_exclusions, parcel_entries, shadow_entries, park_entries, block_entries)
		built_area += float(result.built_area)
		green_area += float(result.green_area)
	# H2.11 remains the locked hero image. Sites are planned only in its existing
	# road-reachable voids and retained as records; no new fill or marks repaint
	# the accepted Arin composition.
	var relief := _relief_geometry_for_extents(envelopes)
	var hero_records: Array = []
	for face_value in faces:
		var face: Dictionary = face_value
		hero_records.append({"poly": face.poly, "role": "hero-void"})
	var site_exclusions := _decorative_mass_records.slice(mass_start)
	var hero_sites := _plan_accommodation_sites(specs, road_segments,
		gameplay_sites, water_exclusions, relief.get("shoulders", []),
		hero_records, site_exclusions, null)
	_finalize_accommodation_mass_overlap(hero_sites,
		_decorative_mass_records.slice(mass_start))

	if not faces.is_empty():
		_metrics.tiles = int(_metrics.tiles) + coords.size()
	var negative_area := maxf(0.0, envelope_area - built_area - green_area)
	_metrics.hero_arin = {
		"street_faces": street_faces.size(),
		"parcels": faces.size(),
		"envelope_area": envelope_area,
		"built_area": built_area,
		"green_area": green_area,
		"built_pct": 100.0 * built_area / maxf(1.0, envelope_area),
		"green_pct": 100.0 * green_area / maxf(1.0, envelope_area),
		"negative_pct": 100.0 * negative_area / maxf(1.0, envelope_area),
		"accommodation_sites": hero_sites.size(),
	}
	for spec_value in specs:
		var spec: Dictionary = spec_value
		_metrics.tile_profiles[spec.id] = MORPH_PROFILE_METRO
		_metrics.tile_to_settlement[spec.id] = "hero|arin-old"
	_register_urban_audit_component("hero|arin-old", specs, envelopes,
		hero_records, _decorative_mass_records.slice(mass_start), road_segments, {}, {
			"water": water_exclusions,
			"forest": _hero_forest_exclusions(forest_discs),
			# H2.11 does not subtract relief shoulders from its locked massing.
			# Enforce only exclusions that are applicable to that image.
			"relief": [],
			"gameplay": _hero_footprint_exclusions(footprints),
			"industrial": [],
		})

func _hero_envelopes(centers: Array[Vector2]) -> Array:
	var hexes: Array = []
	for center in centers:
		var hex := PackedVector2Array()
		for vertex in HEX_VERTS:
			hex.append(center + vertex)
		hexes.append(hex)
	return _hero_merge_polys(hexes)

func _hero_road_corridors(roads: Array) -> Array:
	var raw: Array = []
	for road_value in roads:
		var road: Dictionary = road_value
		var a: Vector2 = road.a
		var b: Vector2 = road.b
		var tangent := (b - a).normalized()
		if tangent == Vector2.ZERO:
			continue
		var half_width := MapStyle.road_width(bool(road.trunk)) * 0.5 + HERO_ROAD_MARGIN
		raw.append(_segment_quad(a - tangent * half_width, b + tangent * half_width, half_width))
	var merged := _hero_merge_polys(raw)
	var out: Array = []
	for poly_value in merged:
		var poly: PackedVector2Array = poly_value
		out.append({"poly": poly, "bb": _bbox(poly)})
	return out

func _hero_water_exclusions(bounds: Rect2) -> Array:
	var nav := NavGrid.instance()
	if not nav.is_ready() or bounds.size == Vector2.ZERO:
		return []
	var pad := Vector2(nav.step, nav.step)
	var lo := nav.cell_of(bounds.position - pad)
	var hi := nav.cell_of(bounds.end + pad)
	var out: Array = []
	for iy in range(lo.y, hi.y + 1):
		var run_start := -1
		for ix in range(lo.x, hi.x + 2):
			var blocked := false
			if ix <= hi.x:
				blocked = nav.water(ix, iy) != NavGrid.WATER_LAND or nav.water_distance(ix, iy) < 4.0
			if blocked and run_start < 0:
				run_start = ix
			elif not blocked and run_start >= 0:
				var a := nav.world_of(run_start, iy) - Vector2(nav.step * 0.5, nav.step * 0.5)
				var b := nav.world_of(ix - 1, iy) + Vector2(nav.step * 0.5, nav.step * 0.5)
				var rect := Rect2(a, b - a)
				var poly := _rect_poly(rect)
				out.append({"poly": poly, "bb": rect})
				run_start = -1
	return out

func _hero_forest_exclusions(forests: Array) -> Array:
	var out: Array = []
	for disc_value in forests:
		var disc: Dictionary = disc_value
		var center: Vector2 = disc.center
		var radius := float(disc.radius) + FOREST_CLEAR
		var poly := PackedVector2Array()
		for i in 12:
			poly.append(center + Vector2.RIGHT.rotated(TAU * float(i) / 12.0) * radius)
		out.append({"poly": poly, "bb": _bbox(poly)})
	return out

func _hero_footprint_exclusions(footprints: Array) -> Array:
	var out: Array = []
	for footprint_value in footprints:
		var footprint: Rect2 = (footprint_value as Rect2).grow(8.0)
		var poly := _rect_poly(footprint)
		out.append({"poly": poly, "bb": footprint})
	return out

func _forbidden_settlement_tile_exclusions(extents: Array) -> Array:
	if extents.is_empty():
		return []
	var bounds := _hero_polys_bbox(extents).grow(8.0)
	var out: Array = []
	var coords: Array = _terrain.tiles.keys()
	coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x or (a.x == b.x and a.y < b.y))
	for coord_value in coords:
		var coord: Vector2i = coord_value
		var tile_data: Dictionary = _terrain.tiles[coord]
		if not ["mountain", "sea", "deep_sea"].has(
				str(tile_data.get("type", ""))):
			continue
		var center := _terrain.map_to_local(
			_terrain.map_coord_for_tile_coord(coord))
		var poly := PackedVector2Array()
		for vertex in HEX_VERTS:
			poly.append(center + vertex)
		var bb := _bbox(poly)
		if bounds.intersects(bb):
			out.append({"poly": poly, "bb": bb,
				"tile_id": str(tile_data.get("id", "")),
				"terrain_type": str(tile_data.get("type", ""))})
	return out

func _relief_geometry_for_extents(extents: Array) -> Dictionary:
	var hill_visuals := get_node_or_null("../HillVisuals")
	if hill_visuals == null or not hill_visuals.has_method(
			"get_land_relief_geometry"):
		return {"active": false, "material_band_count": 0,
			"material_bands": [], "plateaus": [], "shoulders": []}
	return hill_visuals.call("get_land_relief_geometry", extents)

func _land_band_at(point: Vector2) -> int:
	var nav := NavGrid.instance()
	if not nav.is_ready():
		return -1
	var cell := nav.cell_of(point)
	if nav.water(cell.x, cell.y) != NavGrid.WATER_LAND:
		return -1
	return nav.band(cell.x, cell.y)

func _apply_relief_plateau_capacity(records: Array, relief: Dictionary,
		roads: Array) -> void:
	if not bool(relief.get("active", false)):
		return
	var plateaus: Array = relief.get("plateaus", [])
	if plateaus.is_empty():
		return
	var base_band := 99
	for plateau_value in plateaus:
		base_band = mini(base_band, int((plateau_value as Dictionary).band))
	for record_value in records:
		var record: Dictionary = record_value
		var band := int(record.get("relief_band", _land_band_at(
			_poly_center(record.poly))))
		if band <= base_band or not ["built", "village_built"].has(str(record.role)):
			continue
		var area := _poly_area(record.poly)
		var access := _nearest_segment_distance(_poly_center(record.poly), roads)
		if area < 1700.0 or access > 120.0:
			record.role = "none"

func _apply_plan_relief_capacity(plan: SettlementPlan) -> void:
	if plan.material_relief_bands.size() < 3:
		return
	var base_band := 99
	for band_value in plan.material_relief_bands:
		base_band = mini(base_band, int(band_value))
	for parcel_value in plan.parcels:
		var parcel: Dictionary = parcel_value
		if str(parcel.role) != "built":
			continue
		var band := _land_band_at(_poly_center(parcel.poly))
		if band > base_band and _poly_area(parcel.poly) < 1700.0:
			parcel.role = "open"

func _relief_component_diagnostics(relief: Dictionary, records: Array,
		gameplay_sites: Array, specs: Array, component_key: String) -> Dictionary:
	var result := _relief_render_diagnostics(relief.get("shoulders", []),
		gameplay_sites, relief.get("material_bands", []))
	result["material_land_band_count"] = int(relief.get(
		"material_band_count", 0))
	result["material_land_band_count_by_tile"] = {}
	for spec_value in specs:
		var spec: Dictionary = spec_value
		var bands: Dictionary = {}
		for sample_x in [-180.0, -90.0, 0.0, 90.0, 180.0]:
			for sample_y in [-150.0, -75.0, 0.0, 75.0, 150.0]:
				var band := _land_band_at(spec.center + Vector2(sample_x, sample_y))
				if band >= 0:
					bands[band] = true
		result.material_land_band_count_by_tile[spec.id] = bands.size()
	var plateaus: Array = relief.get("plateaus", [])
	var lowest_band := 99
	for plateau_value in plateaus:
		lowest_band = mini(lowest_band, int((plateau_value as Dictionary).band))
	var usable := 0
	var occupied: Dictionary = {}
	for plateau_value in plateaus:
		var plateau: Dictionary = plateau_value
		if int(plateau.band) > lowest_band and float(plateau.area) >= 1700.0:
			usable += 1
	for record_value in records:
		var record: Dictionary = record_value
		if ["built", "village_built"].has(str(record.role)) and int(
				record.get("relief_band", -1)) > lowest_band:
			occupied[int(record.relief_band)] = true
	result["usable_higher_plateaus"] = usable
	result["occupied_higher_plateaus"] = occupied.size()
	result["component_key"] = component_key
	return result

func _relief_render_diagnostics(shoulders: Array,
		gameplay_sites: Array, material_bands: Array = []) -> Dictionary:
	var crossing_mass_count := 0
	var disconnected_count := 0
	var multi_band_count := 0
	var raw_multi_band_count := 0
	var material_band_set: Dictionary = {}
	for band_value in material_bands:
		material_band_set[int(band_value)] = true
	for mass_value in _active_relief_masses:
		var mass: Dictionary = mass_value
		var shoulder_overlap := _poly_water_overlap_area(mass.poly, shoulders)
		if shoulder_overlap > 0.001:
			crossing_mass_count += 1
		var pieces := _clip_poly_from_water(mass.poly, shoulders)
		if pieces.size() > 1:
			disconnected_count += 1
		var bands: Dictionary = {}
		for point in (mass.poly as PackedVector2Array):
			var band := _land_band_at(point)
			if band >= 0:
				bands[band] = true
		if bands.size() > 1:
			raw_multi_band_count += 1
			# Material elevation assignment follows the exact baked contour
			# shoulders. Raw NavGrid corner changes that do not touch one of
			# those shoulders are tiny/noise islands excluded by the trigger.
			var meaningful := 0
			for band_value in bands:
				if material_band_set.has(int(band_value)):
					meaningful += 1
			if meaningful > 1 and shoulder_overlap > 0.001:
				multi_band_count += 1
	var fill_overlap := 0.0
	var fill_overlap_by_role: Dictionary = {}
	for fill_value in _active_relief_fills:
		var fill: Dictionary = fill_value
		var overlap := _poly_water_overlap_area(fill.poly, shoulders)
		fill_overlap += overlap
		if overlap > 0.001:
			var role := str(fill.get("role", "fill"))
			fill_overlap_by_role[role] = float(
				fill_overlap_by_role.get(role, 0.0)) + overlap
	for shadow_value in _active_relief_shadows:
		fill_overlap += _poly_water_overlap_area(
			(shadow_value as Dictionary).poly, shoulders)
	for roof_value in _active_relief_roofs:
		var roof: Dictionary = roof_value
		fill_overlap += _poly_water_overlap_area(roof.poly, shoulders)
		fill_overlap += _poly_water_overlap_area(roof.shadow_poly, shoulders)
	var gameplay_conflicts := 0
	for gameplay_value in gameplay_sites:
		var gameplay: Dictionary = gameplay_value
		if _poly_water_overlap_area(gameplay.poly, shoulders) > 0.001:
			gameplay_conflicts += 1
	return {
		"contour_crossing_decorative_mass_count": crossing_mass_count,
		"decorative_fill_relief_shoulder_overlap_area": 0.0 if fill_overlap < 0.01 else fill_overlap,
		"decorative_fill_relief_shoulder_overlap_by_role": fill_overlap_by_role,
		"disconnected_mass_after_relief_count": disconnected_count,
		"multi_band_decorative_building_count": multi_band_count,
		"raw_navgrid_multi_band_mass_count": raw_multi_band_count,
		"existing_gameplay_footprint_contour_conflicts": gameplay_conflicts,
	}

func _finalize_plan_relief_diagnostics(plan: SettlementPlan,
		gameplay_sites: Array) -> void:
	var result := _relief_render_diagnostics(plan.relief_shoulders,
		gameplay_sites, plan.material_relief_bands)
	plan.diagnostics.merge(result, true)
	var base_band := 99
	for band_value in plan.material_relief_bands:
		base_band = mini(base_band, int(band_value))
	var usable := 0
	for plateau_value in plan.relief_plateaus:
		var plateau: Dictionary = plateau_value
		if int(plateau.band) > base_band and float(plateau.area) >= 1700.0:
			usable += 1
	var occupied: Dictionary = {}
	for mass_value in plan.masses:
		var band := _land_band_at(_poly_center((mass_value as Dictionary).poly))
		if band > base_band:
			occupied[band] = true
	plan.diagnostics["usable_higher_plateaus"] = usable
	plan.diagnostics["occupied_higher_plateaus"] = occupied.size()

func _nearest_segment_distance(point: Vector2, segments: Array) -> float:
	var best := INF
	for segment_value in segments:
		var segment: Dictionary = segment_value
		best = minf(best, _point_segment_distance(point, segment.a, segment.b))
	return best

func _hero_clip_polys(polys: Array, exclusions: Array, min_area: float) -> Array:
	var pieces: Array = polys.duplicate()
	for exclusion_value in exclusions:
		var exclusion: Dictionary = exclusion_value
		var next: Array = []
		for piece_value in pieces:
			var piece: PackedVector2Array = piece_value
			if not _bbox(piece).intersects(exclusion.bb):
				next.append(piece)
				continue
			for clipped_value in Geometry2D.clip_polygons(piece, exclusion.poly):
				var clipped: PackedVector2Array = clipped_value
				if clipped.size() >= 3 and _poly_area(clipped) >= min_area:
					next.append(clipped)
		pieces = next
		if pieces.is_empty():
			break
	return pieces

func _hero_merge_polys(polys: Array) -> Array:
	var merged: Array = []
	for poly_value in polys:
		var pending: PackedVector2Array = poly_value
		var i := 0
		while i < merged.size():
			var unions := Geometry2D.merge_polygons(merged[i], pending)
			if unions.size() == 1:
				pending = unions[0]
				merged.remove_at(i)
				i = 0
			else:
				i += 1
		merged.append(pending)
	return merged

func _hero_subdivide_face(face: PackedVector2Array, key: String, depth: int) -> Array:
	var area := _poly_area(face)
	var target := HERO_FACE_TARGET_AREA * _rr("%s|target" % key, 0.78, 1.22)
	if area <= target or depth >= HERO_MAX_SPLIT_DEPTH:
		return [face]
	var edge_index := _hero_longest_edge(face)
	var edge_a := face[edge_index]
	var edge_b := face[(edge_index + 1) % face.size()]
	var frontage := (edge_b - edge_a).normalized()
	if frontage == Vector2.ZERO:
		return [face]
	var split_axis := Vector2(-frontage.y, frontage.x)
	# Most inherited parcel boundaries pre-date the final street frontage and
	# therefore meet it obliquely. Keep a minority square to the road so the
	# city reads as accumulated rather than globally skewed.
	if RoadHash.pick("%s|oblique" % key, 100) < 72:
		var angle := _rr("%s|oblique-angle" % key, 0.10, 0.25)
		if RoadHash.pick("%s|oblique-side" % key, 2) == 0:
			angle = -angle
		split_axis = split_axis.rotated(angle)
	var center := _poly_center(face)
	center += frontage * _rr("%s|split-offset" % key, -0.17, 0.17) * sqrt(area)
	var span := _bbox(face).size.length() + 24.0
	var corridor := _segment_quad(center - split_axis * span, center + split_axis * span,
		HERO_ALLEY_HALF_WIDTH)
	var raw := Geometry2D.clip_polygons(face, corridor)
	var pieces: Array = []
	for piece_value in raw:
		var piece: PackedVector2Array = piece_value
		if piece.size() >= 3 and _poly_area(piece) >= HERO_FACE_MIN_AREA:
			pieces.append(piece)
	if pieces.size() < 2:
		return [face]
	_hero_record_alley(face, corridor, split_axis)
	var out: Array = []
	for i in pieces.size():
		out.append_array(_hero_subdivide_face(pieces[i], "%s|%d" % [key, i], depth + 1))
	return out

func _hero_record_alley(face: PackedVector2Array, corridor: PackedVector2Array,
		axis: Vector2) -> void:
	for intersection_value in Geometry2D.intersect_polygons(face, corridor):
		var intersection: PackedVector2Array = intersection_value
		if intersection.size() < 3:
			continue
		var low := INF
		var high := -INF
		var low_point := Vector2.ZERO
		var high_point := Vector2.ZERO
		for point in intersection:
			var projection := point.dot(axis)
			if projection < low:
				low = projection
				low_point = point
			if projection > high:
				high = projection
				high_point = point
		if low_point.distance_to(high_point) >= 7.0:
			_append_dry_line(_hero_alleys, low_point, high_point)

func _hero_add_face(face: PackedVector2Array, key: String, color_cluster: String,
		footprint_exclusions: Array, parcel_entries: Array, shadow_entries: Array, park_entries: Array,
		block_entries: Array) -> Dictionary:
	var area := _poly_area(face)
	if area < HERO_FACE_MIN_AREA:
		return {"built_area": 0.0, "green_area": 0.0}
	# The role roll is read one statement earlier than it used to be so the
	# parcel record can carry the role the plan actually assigned. RoadHash.pick
	# is a pure FNV-1a of its key, so moving the read changes no value anywhere.
	var roll := RoadHash.pick("%s|role" % key, 100)
	parcel_entries.append({"poly": face, "color": MapMidcenturyStyle.PAPER,
		"role": "hero_park" if roll < 18 else (
			"hero_open" if roll < 23 else "hero_built")})
	_metrics.parcels = int(_metrics.parcels) + 1
	if roll < 18:
		var green_area := 0.0
		for park_value in _hero_inset_polys(face, _rr("%s|park-inset" % key, 2.8, 5.2)):
			for piece_value in _hero_clip_polys([park_value], footprint_exclusions, 140.0):
				var piece: PackedVector2Array = piece_value
				park_entries.append({"poly": piece,
					"color": MapMidcenturyStyle.park(key), "kind": "green",
					"role": "face_park"})
				_append_ring(_block_edges, piece)
				green_area += _poly_area(piece)
				_hero_add_park_mark(piece)
		_metrics.parks = int(_metrics.parks) + 1
		return {"built_area": 0.0, "green_area": green_area}
	if roll < 23:
		_append_ring(_parcel_edges, face)
		var center := _poly_center(face)
		var edge := face[_hero_longest_edge(face)] - center
		var mark_axis := edge.normalized() if edge.length_squared() > 1.0 else Vector2.RIGHT
		_append_line(_open_lot_marks, center - mark_axis * 8.0, center + mark_axis * 8.0)
		_metrics.open_lots = int(_metrics.open_lots) + 1
		return {"built_area": 0.0, "green_area": 0.0}
	return _hero_add_street_walls(face, key, color_cluster, footprint_exclusions, shadow_entries,
		park_entries, block_entries)

func _hero_add_street_walls(face: PackedVector2Array, key: String, color_cluster: String,
		footprint_exclusions: Array, shadow_entries: Array, park_entries: Array,
		block_entries: Array, form_metrics_key: String = "hero_forms",
		mass_density: float = 0.92, roof_context: String = "",
		form_override: String = "") -> Dictionary:
	var form_roll := RoadHash.pick("%s|mass-form" % key, 100)
	var form := form_override
	if form == "":
		form = "solid" if form_roll < 32 else ("u" if form_roll < 58 else ("l" if form_roll < 78 else "ring"))
	if form_metrics_key != "":
		if not _metrics.has(form_metrics_key):
			_metrics[form_metrics_key] = {"solid": 0, "u": 0, "l": 0, "ring": 0}
		var form_counts: Dictionary = _metrics[form_metrics_key]
		form_counts[form] = int(form_counts.get(form, 0)) + 1

	if form == "solid":
		var solid_area := 0.0
		var solid_index := 0
		for solid_value in _hero_inset_polys(face, _rr("%s|solid-inset" % key, 2.2, 4.4)):
			for piece_value in _hero_clip_polys([solid_value], footprint_exclusions, 115.0):
				var piece: PackedVector2Array = piece_value
				for mass_value in _hero_split_oversized_mass(piece, "%s|solid" % key):
					var mass: PackedVector2Array = mass_value
					var bb := _bbox(mass)
					if minf(bb.size.x, bb.size.y) < 5.5:
						continue
					var long_edge := _hero_longest_edge(mass)
					var tangent := (mass[(long_edge + 1) % mass.size()] - mass[long_edge]).normalized()
					var mass_key := "%s|solid|%d" % [key, solid_index]
					_add_block(mass, tangent, mass_density, mass_key,
						shadow_entries, block_entries, color_cluster, roof_context)
					solid_area += _poly_area(mass)
					solid_index += 1
		return {"built_area": solid_area, "green_area": 0.0}

	var eligible_edges: Array[int] = []
	for i in face.size():
		if face[i].distance_to(face[(i + 1) % face.size()]) >= 17.0:
			eligible_edges.append(i)
	if eligible_edges.is_empty():
		return {"built_area": 0.0, "green_area": 0.0}
	var primary := _hero_longest_edge(face)
	var primary_pos := eligible_edges.find(primary)
	if primary_pos < 0:
		primary_pos = 0
		primary = eligible_edges[0]
	var selected_edges: Dictionary = {}
	if form == "ring":
		for edge_index in eligible_edges:
			selected_edges[edge_index] = true
	elif form == "u":
		selected_edges[primary] = true
		selected_edges[eligible_edges[(primary_pos - 1 + eligible_edges.size()) % eligible_edges.size()]] = true
		selected_edges[eligible_edges[(primary_pos + 1) % eligible_edges.size()]] = true
	else:
		selected_edges[primary] = true
		var side := -1 if RoadHash.pick("%s|l-side" % key, 2) == 0 else 1
		selected_edges[eligible_edges[(primary_pos + side + eligible_edges.size()) % eligible_edges.size()]] = true

	var bars: Array = []
	var depth_sum := 0.0
	var depth_count := 0
	for i in face.size():
		if not selected_edges.has(i):
			continue
		var a := face[i]
		var b := face[(i + 1) % face.size()]
		var length := a.distance_to(b)
		if length < 17.0:
			continue
		if form == "ring" and face.size() > 5 and RoadHash.pick("%s|edge-keep|%d" % [key, i], 100) < 8:
			continue
		var tangent := (b - a).normalized()
		var inward := _hero_inward_normal(face, a, b)
		var depth_low := 13.0 if form == "ring" else (20.0 if form == "u" else 23.0)
		var depth_high := 20.5 if form == "ring" else (29.0 if form == "u" else 32.0)
		var depth := _rr("%s|depth|%d" % [key, i], depth_low, depth_high)
		var trim := minf(1.4 if form != "ring" else 1.8, length * 0.055)
		var center := (a + b) * 0.5 + inward * (depth * 0.5 + 0.7)
		var candidate := _quad(center, tangent, length - trim * 2.0, depth,
			"%s|wall|%d" % [key, i], 0.45)
		for intersection_value in Geometry2D.intersect_polygons(candidate, face):
			var intersection: PackedVector2Array = intersection_value
			if intersection.size() >= 3 and _poly_area(intersection) >= 90.0:
				bars.append(intersection)
		depth_sum += depth
		depth_count += 1
	if bars.is_empty():
		return {"built_area": 0.0, "green_area": 0.0}

	var walls := _hero_merge_polys(bars)
	var local_exclusions: Array = footprint_exclusions.duplicate()
	var longest := _hero_longest_edge(face)
	var entry_a := face[longest]
	var entry_b := face[(longest + 1) % face.size()]
	var entry_tangent := (entry_b - entry_a).normalized()
	var entry_inward := _hero_inward_normal(face, entry_a, entry_b)
	var average_depth := depth_sum / maxf(1.0, float(depth_count))
	if (form == "ring" and entry_tangent != Vector2.ZERO and entry_a.distance_to(entry_b) >= 34.0
			and RoadHash.pick("%s|court-entry" % key, 100) < 76):
		var entry_center := (entry_a + entry_b) * 0.5
		entry_center += entry_tangent * _rr("%s|entry-shift" % key, -0.18, 0.18) * entry_a.distance_to(entry_b)
		var entry := _segment_quad(entry_center - entry_inward * 2.0,
			entry_center + entry_inward * (average_depth + 8.0), 2.4)
		local_exclusions.append({"poly": entry, "bb": _bbox(entry)})
		_append_dry_line(_hero_alleys, entry_center, entry_center + entry_inward * (average_depth + 5.0))

	var built_area := 0.0
	var piece_index := 0
	for wall_value in walls:
		for piece_value in _hero_clip_polys([wall_value], local_exclusions, 115.0):
			var piece: PackedVector2Array = piece_value
			for mass_value in _hero_split_oversized_mass(piece, "%s|wall" % key):
				var mass: PackedVector2Array = mass_value
				var bb := _bbox(mass)
				if minf(bb.size.x, bb.size.y) < 5.5:
					continue
				var long_edge := _hero_longest_edge(mass)
				var tangent := (mass[(long_edge + 1) % mass.size()] - mass[long_edge]).normalized()
				_add_block(mass, tangent, mass_density, "%s|mass|%d" % [key, piece_index],
					shadow_entries, block_entries, color_cluster, roof_context)
				built_area += _poly_area(mass)
				piece_index += 1

	var green_area := 0.0
	if form == "l":
		return {"built_area": built_area, "green_area": green_area}
	var courts := _hero_inset_polys(face, average_depth + 4.5)
	for i in courts.size():
		var court: PackedVector2Array = courts[i]
		if _poly_area(court) < 180.0:
			continue
		var green_cut := 100 if form == "ring" else 48
		if RoadHash.pick("%s|court-green|%d" % [key, i], 100) < green_cut:
			for piece_value in _hero_clip_polys([court], footprint_exclusions, 140.0):
				var piece: PackedVector2Array = piece_value
				park_entries.append({"poly": piece,
					"color": MapMidcenturyStyle.park("%s|court" % key),
					"kind": "courtyard", "role": "courtyard"})
				_append_ring(_block_edges, piece)
				green_area += _poly_area(piece)
				_hero_add_park_mark(piece)
			_metrics.parks = int(_metrics.parks) + 1
		else:
			_append_ring(_parcel_edges, court)
			var center := _poly_center(court)
			_append_line(_open_lot_marks, center - Vector2(5.0, 0.0), center + Vector2(5.0, 0.0))
	return {"built_area": built_area, "green_area": green_area}

func _hero_inset_polys(poly: PackedVector2Array, amount: float) -> Array:
	var ccw := poly.duplicate()
	if Geometry2D.is_polygon_clockwise(ccw):
		ccw.reverse()
	var out: Array = []
	for inset_value in Geometry2D.offset_polygon(ccw, -amount, Geometry2D.JOIN_MITER):
		var inset: PackedVector2Array = inset_value
		if inset.size() >= 3:
			out.append(inset)
	return out

func _hero_inward_normal(poly: PackedVector2Array, a: Vector2, b: Vector2) -> Vector2:
	var tangent := (b - a).normalized()
	var normal := Vector2(-tangent.y, tangent.x)
	var midpoint := (a + b) * 0.5
	if Geometry2D.is_point_in_polygon(midpoint + normal * 4.0, poly):
		return normal
	return -normal

func _hero_longest_edge(poly: PackedVector2Array) -> int:
	var best := 0
	var best_length := -1.0
	for i in poly.size():
		var length := poly[i].distance_squared_to(poly[(i + 1) % poly.size()])
		if length > best_length:
			best = i
			best_length = length
	return best

func _hero_split_oversized_mass(poly: PackedVector2Array, _key: String) -> Array:
	var edge := _hero_longest_edge(poly)
	var axis := (poly[(edge + 1) % poly.size()] - poly[edge]).normalized()
	if axis == Vector2.ZERO:
		return [poly]
	var normal := Vector2(-axis.y, axis.x)
	var low := INF
	var high := -INF
	for point in poly:
		var projection := point.dot(axis)
		low = minf(low, projection)
		high = maxf(high, projection)
	var frontage := high - low
	var by_frontage := ceili(frontage / 84.0)
	var by_area := ceili(_poly_area(poly) / 7200.0)
	var count := clampi(maxi(by_frontage, by_area), 1, 3)
	if count <= 1:
		return [poly]

	var pieces: Array = [poly]
	var center := _poly_center(poly)
	var center_projection := center.dot(axis)
	var span := _bbox(poly).size.length() + 18.0
	for cut_index in range(1, count):
		var cut_projection := lerpf(low, high, float(cut_index) / float(count))
		var cut_center := center + axis * (cut_projection - center_projection)
		var corridor := _segment_quad(cut_center - normal * span, cut_center + normal * span, 1.7)
		var exclusion := {"poly": corridor, "bb": _bbox(corridor)}
		pieces = _hero_clip_polys(pieces, [exclusion], 115.0)
		_hero_record_alley(poly, corridor, normal)
	return pieces

func _hero_add_park_mark(poly: PackedVector2Array) -> void:
	var center := _poly_center(poly)
	var edge := _hero_longest_edge(poly)
	var axis := (poly[(edge + 1) % poly.size()] - poly[edge]).normalized()
	var normal := Vector2(-axis.y, axis.x)
	var bend := center + normal * 4.0
	_append_line(_park_marks, center - axis * 9.0, bend)
	_append_line(_park_marks, bend, center + axis * 10.0)

func _hero_polys_bbox(polys: Array) -> Rect2:
	if polys.is_empty():
		return Rect2()
	var out := _bbox(polys[0])
	for i in range(1, polys.size()):
		out = out.merge(_bbox(polys[i]))
	return out

func _hero_polys_area(polys: Array) -> float:
	var area := 0.0
	for poly_value in polys:
		area += _poly_area(poly_value)
	return area

func _rect_poly(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	])

func _circle_poly(center: Vector2, radius: float, steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in steps:
		out.append(center + Vector2.RIGHT.rotated(TAU * float(i) / float(steps)) * radius)
	return out

func _segment_quad(a: Vector2, b: Vector2, half_width: float) -> PackedVector2Array:
	var tangent := (b - a).normalized()
	var normal := Vector2(-tangent.y, tangent.x) * half_width
	return PackedVector2Array([a - normal, b - normal, b + normal, a + normal])

func _scale_poly(poly: PackedVector2Array, center: Vector2, scale: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in poly:
		out.append(center + (point - center) * scale)
	return out

func _poly_center(poly: PackedVector2Array) -> Vector2:
	var center := Vector2.ZERO
	for point in poly:
		center += point
	return center / maxf(1.0, float(poly.size()))

func _poly_area(poly: PackedVector2Array) -> float:
	var twice_area := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		twice_area += a.x * b.y - b.x * a.y
	return absf(twice_area) * 0.5

func _build_tile(coord: Vector2i, tile_data: Dictionary, parcel_entries: Array,
		shadow_entries: Array, park_entries: Array, block_entries: Array) -> void:
	var center := _terrain.map_to_local(_terrain.map_coord_for_tile_coord(coord))
	var tile_id := str(tile_data.get("id", "%d_%d" % [coord.x, coord.y]))
	var density := _density(tile_data)
	var footprints: Array = _buildings.footprint_rects_on_tile(coord) if _buildings != null and _buildings.has_method("footprint_rects_on_tile") else []
	var forest_discs: Array = _forests.discs_on_tile(coord) if _forests != null and _forests.has_method("discs_on_tile") else []
	var road_segments: Array = []
	var anchors := _road_anchors(coord, center, tile_id, road_segments, density)
	if anchors.size() < 3:
		_append_service_plan(center, tile_id, anchors, road_segments)
	var focus := _district_focus(center, tile_id, anchors)
	anchors.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da := (a.p as Vector2).distance_squared_to(focus)
		var db := (b.p as Vector2).distance_squared_to(focus)
		if is_equal_approx(da, db):
			return str(a.key) < str(b.key)
		return da < db
	)
	var occupied: Array[PackedVector2Array] = []
	var target := int(round(lerpf(8.0, 28.0, density)))
	var accepted := 0

	for anchor_value in anchors:
		if accepted >= target:
			break
		var anchor: Dictionary = anchor_value
		var tangent: Vector2 = anchor.t
		var normal := Vector2(-tangent.y, tangent.x)
		var junction := density >= 0.78 and _junction_anchor(anchor.p, tangent, road_segments)
		for side in [-1.0, 1.0]:
			if accepted >= target:
				break
			var key := "%s|%s|%d" % [tile_id, str(anchor.key), int(side)]
			var centrality := clampf(1.0 - (anchor.p as Vector2).distance_to(focus) / 245.0, 0.0, 1.0)
			var keep_chance := int(19.0 + density * 49.0 + centrality * 27.0)
			if RoadHash.pick("mc-keep|%s" % key, 100) >= keep_chance:
				continue
			var length := _rr("mc-len|%s" % key, 36.0, 72.0 if density > 0.72 else 66.0)
			var depth := _rr("mc-depth|%s" % key, 23.0, 42.0 if density > 0.68 else 37.0)
			var gap := 11.0 if bool(anchor.actual) else 8.5
			var parcel_center: Vector2 = (anchor.p as Vector2) + normal * side * (gap + depth * 0.5 + PARCEL_MARGIN)
			var parcel := _quad(parcel_center, tangent, length + PARCEL_MARGIN * 2.0,
				depth + PARCEL_MARGIN * 2.0, "mc-parcel|%s" % key, 1.6)
			var parcel_bb := _bbox(parcel)
			if not _candidate_clear(parcel, parcel_bb, center, footprints, forest_discs, road_segments, occupied):
				continue

			occupied.append(parcel)
			accepted += 1
			_metrics.parcels = int(_metrics.parcels) + 1
			var roll := RoadHash.pick("mc-kind|%s" % key, 100)
			# A few shaped greens punctuate the core; they do not replace its street
			# wall. Loose edge districts retain a higher share of breathing space.
			var park_cut := int(5.0 + (1.0 - density) * 12.0)
			if roll < park_cut:
				_add_park(parcel_center, tangent, length, depth, key, park_entries)
				continue
			if roll >= 94:
				_add_open_lot(parcel_center, tangent, length, depth, key, parcel_entries)
				continue
			if junction and length >= 55.0 and depth >= 34.0 and RoadHash.pick("mc-enclose|%s" % key, 100) < 62:
				_add_enclosed_corner(parcel_center, tangent, length, depth, density, key,
					parcel_entries, park_entries, shadow_entries, block_entries)
			elif roll < park_cut + int(14.0 * density) and length >= 61.0 and depth >= 36.0:
				_add_courtyard(parcel_center, tangent, length, depth, density, key,
					parcel_entries, shadow_entries, block_entries)
			else:
				_add_terrace(parcel_center, tangent, length, depth, density, key, shadow_entries, block_entries)

	if accepted > 0:
		_metrics.tiles = int(_metrics.tiles) + 1

func _road_anchors(coord: Vector2i, center: Vector2, tile_id: String, road_segments: Array,
		density: float) -> Array:
	var out: Array = []
	var net := RoadNetwork.instance()
	var stride := 2 if density >= 0.84 else (3 if density >= 0.62 else 4)
	var anchor_clear := 27.0 if density >= 0.84 else 32.0
	for edge_id_value in net.edges_on_tile(coord):
		var edge_id := str(edge_id_value)
		var edge: Dictionary = net.edges.get(edge_id, {})
		if str(edge.get("state", "")) != RoadNetwork.STATE_BUILT:
			continue
		var geo: PackedVector2Array = edge.get("geometry", PackedVector2Array())
		for i in range(geo.size() - 1):
			road_segments.append([geo[i], geo[i + 1]])
		if geo.size() < 2:
			continue
		var phase := RoadHash.pick("mc-phase|%s|%s" % [tile_id, edge_id], stride)
		for i in range(phase, geo.size(), stride):
			var point := geo[i]
			if not _inside_hex(point, center, 48.0):
				continue
			var lo := maxi(0, i - 2)
			var hi := mini(geo.size() - 1, i + 2)
			var tangent := (geo[hi] - geo[lo]).normalized()
			if tangent == Vector2.ZERO or _near_anchor(point, out, anchor_clear):
				continue
			out.append({"p": point, "t": tangent, "key": "%s|%d" % [edge_id, i], "actual": true})
	return out

func _append_service_plan(center: Vector2, tile_id: String, anchors: Array, road_segments: Array) -> void:
	var angle := _rr("mc-axis|%s" % tile_id, -0.42, 0.42)
	var t1 := Vector2.RIGHT.rotated(angle)
	var n1 := Vector2(-t1.y, t1.x)
	var offset := n1 * _rr("mc-axisoff|%s" % tile_id, -24.0, 24.0)
	var a1 := center + offset - t1 * 172.0
	var b1 := center + offset + t1 * 172.0
	road_segments.append([a1, b1])
	_append_dry_line(_service_lines, a1, b1)
	for i in range(-2, 3):
		var p := center + offset + t1 * (float(i) * 67.0 + _rr("mc-aj|%s|%d" % [tile_id, i], -8.0, 8.0))
		anchors.append({"p": p, "t": t1, "key": "service-a|%d" % i, "actual": false})

	var turn := deg_to_rad(_rr("mc-cross|%s" % tile_id, 58.0, 78.0))
	var t2 := t1.rotated(turn)
	var cross_center := center + t1 * _rr("mc-crossoff|%s" % tile_id, -62.0, 62.0)
	var a2 := cross_center - t2 * 128.0
	var b2 := cross_center + t2 * 128.0
	road_segments.append([a2, b2])
	_append_dry_line(_service_lines, a2, b2)
	for i in range(-1, 2):
		var p2 := cross_center + t2 * float(i) * 64.0
		if not _near_anchor(p2, anchors, 42.0):
			anchors.append({"p": p2, "t": t2, "key": "service-b|%d" % i, "actual": false})

func _add_terrace(center: Vector2, tangent: Vector2, length: float, depth: float,
		density: float, key: String, shadow_entries: Array, block_entries: Array) -> void:
	var count := clampi(int(round(length / _rr("mc-unit|%s" % key, 18.0, 25.0))), 2, 5)
	var row := _stepped_row(center, tangent, length, depth, count, key)
	_add_block(row.poly, tangent, density, "%s|row" % key, shadow_entries, block_entries)
	# Fine divisions imply several terrace addresses without cutting the street
	# wall into repeated detached cards.
	for i in row.seams.size():
		if RoadHash.pick("mc-seam-keep|%s|%d" % [key, i], 100) < 18:
			continue
		var seam_value: Variant = row.seams[i]
		var seam: Array = seam_value
		_append_safe_roof_mark((seam[0] as Vector2).lerp(seam[1], 0.12),
			(seam[0] as Vector2).lerp(seam[1], 0.88), "%s|seam|%d" % [key, i])
func _add_courtyard(center: Vector2, tangent: Vector2, length: float, depth: float,
		density: float, key: String, parcel_entries: Array, shadow_entries: Array,
		block_entries: Array) -> void:
	var normal := Vector2(-tangent.y, tangent.x)
	var wing := clampf(minf(length, depth) * 0.22, 9.0, 14.0)
	var back_center := center + normal * (depth * 0.5 - wing * 0.5)
	_add_block(_quad(back_center, tangent, length, wing, "%s|back" % key, 1.0), tangent,
		density, "%s|back" % key, shadow_entries, block_entries)
	var side_depth := depth - wing - 4.0
	for side in [-1.0, 1.0]:
		var side_f := float(side)
		var side_center: Vector2 = center + tangent * side_f * (length * 0.5 - wing * 0.5) - normal * 2.0
		_add_block(_quad(side_center, normal, side_depth, wing, "%s|side|%d" % [key, int(side_f)], 1.0),
			normal, density, "%s|side|%d" % [key, int(side_f)], shadow_entries, block_entries)
	# A tiny interior mark makes the purposeful void discoverable only close in.
	var court_half := minf(length, depth) * 0.12
	var court := _irregular_lot(center - normal * 1.0, tangent, court_half * 2.4,
		maxf(10.0, (depth - wing * 2.0) * 0.74), "%s|court" % key)
	parcel_entries.append({"poly": court, "color": Color("d8cba8"),
		"role": "inner_court"})
	_append_line(_open_lot_marks, center - tangent * court_half, center + tangent * court_half)

func _add_enclosed_corner(center: Vector2, tangent: Vector2, length: float, depth: float,
		density: float, key: String, parcel_entries: Array, park_entries: Array,
		shadow_entries: Array, block_entries: Array) -> void:
	var t := tangent.normalized()
	var n := Vector2(-t.y, t.x)
	var wing := clampf(minf(length, depth) * 0.20, 8.0, 12.5)
	# Street and rear bars establish a block face on both sides of the parcel.
	for side in [-1.0, 1.0]:
		var side_f := float(side)
		var bar_center := center + n * side_f * (depth * 0.5 - wing * 0.5)
		_add_block(_quad(bar_center, t, length, wing, "%s|edge|%d" % [key, int(side_f)], 0.9),
			t, density, "%s|edge|%d" % [key, int(side_f)], shadow_entries, block_entries)
	# One full return and one split return leave a narrow alley into the court.
	var return_depth := maxf(10.0, depth - wing * 2.0)
	var full_center := center - t * (length * 0.5 - wing * 0.5)
	_add_block(_quad(full_center, n, return_depth, wing, "%s|return-full" % key, 0.8),
		n, density, "%s|return-full" % key, shadow_entries, block_entries)
	var alley := clampf(return_depth * 0.24, 6.0, 9.0)
	var half_return := maxf(5.0, (return_depth - alley) * 0.5)
	for side in [-1.0, 1.0]:
		var side_f := float(side)
		var split_center := center + t * (length * 0.5 - wing * 0.5) + n * side_f * (alley * 0.5 + half_return * 0.5)
		_add_block(_quad(split_center, n, half_return, wing,
			"%s|return-split|%d" % [key, int(side_f)], 0.7), n, density,
			"%s|return-split|%d" % [key, int(side_f)], shadow_entries, block_entries)
	var court_length := maxf(13.0, length - wing * 2.0 - 4.0)
	var court_depth := maxf(11.0, depth - wing * 2.0 - 3.0)
	var court := _irregular_lot(center, t, court_length, court_depth, "%s|inner" % key)
	if RoadHash.pick("mc-court-green|%s" % key, 100) < 28:
		park_entries.append({"poly": court,
			"color": MapMidcenturyStyle.park("%s|inner" % key),
			"kind": "courtyard", "role": "courtyard"})
		_metrics.parks = int(_metrics.parks) + 1
		var bend := center + n * court_depth * 0.18
		_append_line(_park_marks, center - t * court_length * 0.30, bend)
		_append_line(_park_marks, bend, center + t * court_length * 0.30)
	else:
		parcel_entries.append({"poly": court, "color": Color("d8cba8"),
			"role": "enclosed_court"})
		_append_line(_open_lot_marks, center - t * court_length * 0.24, center + t * court_length * 0.24)
	# The short gap in the split return is an alley, not a second road.
	var alley_outer := center + t * length * 0.5
	var alley_inner := center + t * (length * 0.5 - wing - court_length * 0.12)
	_append_line(_open_lot_marks, alley_inner, alley_outer)

func _add_block(poly: PackedVector2Array, tangent: Vector2, density: float, key: String,
		shadow_entries: Array, block_entries: Array, color_cluster: String = "",
		roof_context: String = "") -> void:
	if not _poly_on_dry_land(poly):
		_dry_land_rejections.block = int(_dry_land_rejections.block) + 1
		return
	if _poly_overlaps_active_plan_water(poly) > 0.001:
		return
	if _poly_overlaps_active_relief(poly) > 0.001:
		return
	var shadow_poly := _offset(poly, BLOCK_SHADOW_OFFSET)
	if not _poly_on_dry_land(shadow_poly):
		_dry_land_rejections.shadow = int(_dry_land_rejections.shadow) + 1
		return
	if _poly_overlaps_active_plan_water(shadow_poly) > 0.001:
		return
	if _poly_overlaps_active_relief(shadow_poly) > 0.001:
		return
	shadow_entries.append({"poly": shadow_poly, "color": MapMidcenturyStyle.SHADOW})
	_active_relief_masses.append({"key": key, "poly": poly.duplicate(),
		"relief_band": _land_band_at(_poly_center(poly))})
	_decorative_mass_records.append({"key": key, "poly": poly.duplicate()})
	_active_relief_shadows.append({"key": key, "poly": shadow_poly.duplicate()})
	var top := MapMidcenturyStyle.urban_block(key, density)
	if color_cluster != "":
		top = MapMidcenturyStyle.urban_block_cluster(color_cluster, key, density)
	block_entries.append({"poly": poly, "color": top, "kind": "ordinary"})
	if _active_plan != null:
		_active_plan.masses.append({
			"key": key,
			"poly": poly.duplicate(),
			"tangent": tangent,
			"density": density,
		})
		_active_plan.visual_shadows.append({"key": key,
			"poly": shadow_poly.duplicate(), "role": "ordinary"})
	_append_ring(_block_edges, poly)
	_metrics.blocks = int(_metrics.blocks) + 1
	var bb := _bbox(poly)
	var center := bb.get_center()
	var t := tangent.normalized()
	var n := Vector2(-t.y, t.x)
	var mark_half := clampf(minf(bb.size.x, bb.size.y) * 0.15, 2.2, 5.0)
	if roof_context != "":
		_add_morph_roof(poly, top, center, t, n, mark_half, key, roof_context)
		return
	var roof_roll := RoadHash.pick("mc-roof-mark|%s" % key, 100)
	if roof_roll < 14:
		# An off-centre short ridge: discoverable close up, invisible at wide zoom.
		var ridge_center := center + n * _rr("mc-ridge-off|%s" % key, -3.0, 3.0)
		_append_safe_roof_mark(ridge_center - t * mark_half,
			ridge_center + t * mark_half, key)
	elif roof_roll < 27:
		# Two tiny parallel vents instead of the former repeated cross glyph.
		var along := center + t * _rr("mc-vent-along|%s" % key, -4.0, 4.0)
		for side in [-1.0, 1.0]:
			var vent_center := along + n * float(side) * mark_half * 0.72
			_append_safe_roof_mark(vent_center - t * mark_half * 0.42,
				vent_center + t * mark_half * 0.42, key)

func _add_morph_roof(poly: PackedVector2Array, base: Color, center: Vector2,
		tangent: Vector2, normal: Vector2, mark_half: float, key: String,
		context: String) -> void:
	var cuts := _morph_roof_cuts(context)
	var roll := RoadHash.pick("mc-morph-roof|%s|%s" % [context, key], 100)
	var roof_form := "plain"
	if roll >= int(cuts.plain):
		if roll < int(cuts.pitched):
			roof_form = "pitched"
		elif roll < int(cuts.raised):
			roof_form = "raised"
		else:
			roof_form = "utility"
	var bb := _bbox(poly)
	if roof_form == "raised" and minf(bb.size.x, bb.size.y) < 9.0:
		roof_form = "plain"
	if roof_form == "utility" and minf(bb.size.x, bb.size.y) < 7.0:
		roof_form = "pitched"
	var counts: Dictionary = _metrics.morph_roofs
	counts[roof_form] = int(counts.get(roof_form, 0)) + 1
	if roof_form == "pitched":
		var ridge_center := center + normal * _rr("mc-morph-ridge-off|%s" % key, -2.0, 2.0)
		_append_safe_roof_mark(ridge_center - tangent * mark_half,
			ridge_center + tangent * mark_half, key)
	elif roof_form == "raised":
		var scale := _rr("mc-morph-cap-scale|%s" % key, 0.48, 0.64)
		var cap := _scale_poly(poly, center, scale)
		var cap_shadow := _offset(cap, Vector2(1.25, 1.55))
		if _poly_overlaps_active_plan_water(cap) > 0.001 or _poly_overlaps_active_plan_water(cap_shadow) > 0.001:
			return
		if _poly_overlaps_active_relief(cap) > 0.001 or _poly_overlaps_active_relief(cap_shadow) > 0.001:
			return
		_roof_shadow_entries.append({
			"poly": cap_shadow,
			"color": Color(MapMidcenturyStyle.SHADOW, 0.62),
		})
		_roof_top_entries.append({
			"poly": cap,
			"color": MapMidcenturyStyle.raised_roof_top(base, key, context),
		})
		_append_ring(_roof_edges, cap)
		_active_relief_roofs.append({"key": key, "poly": cap.duplicate(),
			"shadow_poly": cap_shadow.duplicate()})
		if _active_plan != null:
			_active_plan.visual_roof_elements.append({"key": key,
				"poly": cap.duplicate(), "shadow_poly": cap_shadow.duplicate()})
	elif roof_form == "utility":
		var spacing := mark_half * 0.72
		for index in [-1, 0, 1]:
			var stripe_center := center + tangent * float(index) * spacing
			_append_safe_roof_mark(stripe_center - normal * mark_half * 0.62,
				stripe_center + normal * mark_half * 0.62, key)

func _morph_roof_cuts(context: String) -> Dictionary:
	if context == MORPH_PROFILE_METRO:
		return {"plain": 64, "pitched": 83, "raised": 93}
	if context == MORPH_PROFILE_FRINGE:
		return {"plain": 65, "pitched": 83, "raised": 91}
	if context == MORPH_PROFILE_VILLAGE:
		return {"plain": 68, "pitched": 90, "raised": 98}
	return {"plain": 68, "pitched": 86, "raised": 95}

func _add_park(center: Vector2, tangent: Vector2, length: float, depth: float,
		key: String, park_entries: Array) -> void:
	var park_poly := _irregular_lot(center, tangent, maxf(18.0, length - 5.0),
		maxf(16.0, depth - 5.0), "%s|park" % key)
	park_entries.append({"poly": park_poly,
		"color": MapMidcenturyStyle.park(key), "kind": "park",
		"role": "street_park"})
	_append_ring(_block_edges, park_poly)
	var n := Vector2(-tangent.y, tangent.x)
	var u := minf(length * 0.25, 16.0)
	var v := minf(depth * 0.20, 8.0)
	var bend := center + tangent * _rr("mc-parkbend|%s" % key, -4.0, 4.0) + n * v
	_append_line(_park_marks, center - tangent * u - n * v * 0.4, bend)
	_append_line(_park_marks, bend, center + tangent * u - n * v * 0.25)
	_metrics.parks = int(_metrics.parks) + 1

func _add_open_lot(center: Vector2, tangent: Vector2, length: float, depth: float,
		key: String, parcel_entries: Array) -> void:
	var n := Vector2(-tangent.y, tangent.x)
	var lot := _irregular_lot(center, tangent, maxf(17.0, length - 5.0),
		maxf(15.0, depth - 5.0), "%s|open" % key)
	parcel_entries.append({"poly": lot, "color": Color("b8ad82"),
		"role": "open_lot"})
	_append_ring(_parcel_edges, lot)
	for i in 3:
		var d := (float(i) - 1.0) * 7.0
		var c := center + tangent * d
		_append_line(_open_lot_marks, c - n * depth * 0.26, c + n * depth * 0.26)
	_metrics.open_lots = int(_metrics.open_lots) + 1

func _stepped_row(center: Vector2, tangent: Vector2, length: float, depth: float,
		count: int, key: String) -> Dictionary:
	var t := tangent.normalized()
	var n := Vector2(-t.y, t.x)
	var front: Array[Vector2] = []
	var back: Array[Vector2] = []
	var seams: Array = []
	for i in count + 1:
		var along := -length * 0.5 + length * float(i) / float(count)
		if i > 0 and i < count:
			along += _rr("mc-boundary|%s|%d" % [key, i], -2.2, 2.2)
		var front_in := _rr("mc-front|%s|%d" % [key, i], 0.8, 4.2)
		var back_in := _rr("mc-back|%s|%d" % [key, i], 0.5, 3.2)
		front.append(center + t * along - n * (depth * 0.5 - front_in))
		back.append(center + t * along + n * (depth * 0.5 - back_in))
		if i > 0 and i < count:
			seams.append([front[i], back[i]])
	var poly := PackedVector2Array()
	for point in front:
		poly.append(point)
	for i in range(back.size() - 1, -1, -1):
		poly.append(back[i])
	return {"poly": poly, "seams": seams}

func _irregular_lot(center: Vector2, tangent: Vector2, length: float, depth: float,
		key: String) -> PackedVector2Array:
	var t := tangent.normalized()
	var n := Vector2(-t.y, t.x)
	var hu := length * 0.5
	var hv := depth * 0.5
	var cut_a := minf(hu * 0.32, _rr("mc-cut-a|%s" % key, 4.0, 10.0))
	var cut_b := minf(hu * 0.32, _rr("mc-cut-b|%s" % key, 4.0, 10.0))
	var cut_v := minf(hv * 0.45, _rr("mc-cut-v|%s" % key, 3.0, 7.0))
	return PackedVector2Array([
		center - t * hu - n * (hv - cut_v),
		center - t * (hu - cut_a) - n * hv,
		center + t * (hu - cut_b) - n * hv,
		center + t * hu - n * (hv - cut_v * 0.7),
		center + t * (hu - cut_a * 0.6) + n * hv,
		center - t * (hu - cut_b * 0.8) + n * hv,
	])

func _candidate_clear(poly: PackedVector2Array, bb: Rect2, tile_center: Vector2,
		footprints: Array, forests: Array, roads: Array, occupied: Array[PackedVector2Array]) -> bool:
	for point in poly:
		if not _inside_hex(point, tile_center, 24.0) or not _land_clear(point):
			return false
	if not _land_clear(bb.get_center()):
		return false
	for footprint_value in footprints:
		var footprint: Rect2 = footprint_value
		if bb.intersects(footprint.grow(7.0)):
			return false
	for disc_value in forests:
		var disc: Dictionary = disc_value
		var dc: Vector2 = disc.center
		var dr := float(disc.radius) + FOREST_CLEAR
		if bb.get_center().distance_to(dc) <= dr:
			return false
		for point in poly:
			if point.distance_to(dc) <= dr:
				return false
	for road_value in roads:
		var segment: Array = road_value
		for point in poly:
			if _point_segment_distance(point, segment[0], segment[1]) < ROAD_CLEAR:
				return false
	for used in occupied:
		if not Geometry2D.intersect_polygons(poly, used).is_empty():
			return false
	return true

func _land_clear(point: Vector2) -> bool:
	var nav := NavGrid.instance()
	if not nav.is_ready():
		return true
	var cell := nav.cell_of(point)
	return nav.water(cell.x, cell.y) == NavGrid.WATER_LAND and nav.water_distance(cell.x, cell.y) >= 4.0

func _poly_on_dry_land(poly: PackedVector2Array) -> bool:
	if poly.size() < 3:
		return false
	var nav := NavGrid.instance()
	if not nav.is_ready():
		return true
	# Edge samples catch a polygon bridging a curved shoreline even when every
	# corner happens to land on a dry nav cell.
	var edge_step := maxf(4.0, nav.step * 0.5)
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var samples := maxi(1, int(ceil(a.distance_to(b) / edge_step)))
		for sample in range(samples + 1):
			var point := a.lerp(b, float(sample) / float(samples))
			var cell := nav.cell_of(point)
			if nav.water(cell.x, cell.y) != NavGrid.WATER_LAND:
				return false
	# Interior nav-cell centres catch large faces that bridge a bay or lake while
	# their outline itself stays on land.
	var bb := _bbox(poly)
	var cell_min := nav.cell_of(bb.position)
	var cell_max := nav.cell_of(bb.end)
	for iy in range(cell_min.y, cell_max.y + 1):
		for ix in range(cell_min.x, cell_max.x + 1):
			var point := nav.world_of(ix, iy)
			if Geometry2D.is_point_in_polygon(point, poly) and \
					nav.water(ix, iy) != NavGrid.WATER_LAND:
				return false
	return true

func _sanitize_decorative_fills(layers: Dictionary) -> Dictionary:
	var removed_by_layer: Dictionary = {}
	var retained_by_layer: Dictionary = {}
	var total_removed := 0
	for layer_value in layers:
		var layer := str(layer_value)
		var entries: Array = layers[layer]
		var removed := 0
		for index in range(entries.size() - 1, -1, -1):
			var entry: Dictionary = entries[index]
			var poly: PackedVector2Array = entry.get("poly", PackedVector2Array())
			if _poly_on_dry_land(poly):
				continue
			entries.remove_at(index)
			removed += 1
		removed_by_layer[layer] = removed
		retained_by_layer[layer] = entries.size()
		total_removed += removed
	return {
		"water_overlap_count": 0,
		"removed_water_polygons": total_removed,
		"removed_by_layer": removed_by_layer,
		"retained_by_layer": retained_by_layer,
		"generation_rejections": _dry_land_rejections.duplicate(true),
	}

func _sanitize_gameplay_collisions(layers: Dictionary) -> Dictionary:
	var sites: Array = []
	if _buildings != null and _buildings.has_method(
			"midcentury_all_footprint_sites"):
		sites = _buildings.midcentury_all_footprint_sites()
	var exclusions: Array = []
	for site_value in sites:
		var site: Dictionary = site_value
		var poly: PackedVector2Array = site.get("poly", PackedVector2Array())
		if poly.size() < 3:
			continue
		var ccw := poly.duplicate()
		if Geometry2D.is_polygon_clockwise(ccw):
			ccw.reverse()
		var expanded: Array = Geometry2D.offset_polygon(ccw, 4.5,
			Geometry2D.JOIN_MITER)
		if expanded.is_empty():
			expanded = [ccw]
		for expanded_value in expanded:
			var expanded_poly: PackedVector2Array = expanded_value
			if expanded_poly.size() >= 3:
				exclusions.append({"poly": expanded_poly,
					"bb": _bbox(expanded_poly),
					"instance_id": str(site.get("instance_id", ""))})
	var removed_by_layer: Dictionary = {}
	var overlap_area := 0.0
	for layer_value in layers:
		var layer := str(layer_value)
		var entries: Array = layers[layer]
		var removed := 0
		for index in range(entries.size() - 1, -1, -1):
			var entry: Dictionary = entries[index]
			var poly: PackedVector2Array = entry.get("poly", PackedVector2Array())
			if poly.size() < 3:
				continue
			var collision := 0.0
			for exclusion_value in exclusions:
				var exclusion: Dictionary = exclusion_value
				if not _bbox(poly).intersects(exclusion.bb):
					continue
				collision += _polys_overlap_area(poly, exclusion.poly)
			if collision <= 0.001:
				continue
			overlap_area += collision
			entries.remove_at(index)
			removed += 1
		removed_by_layer[layer] = removed
	return {
		"footprint_version": int(_buildings.get("footprint_version")) if \
			_buildings != null else -1,
		"footprints_checked": sites.size(),
		"removed_by_layer": removed_by_layer,
		"removed_polygon_count": _sum_dictionary_ints(removed_by_layer),
		"removed_overlap_area": overlap_area,
		"opaque_overlap_count": 0,
	}

func gameplay_collision_snapshot() -> Dictionary:
	return (_metrics.get("gameplay_collision_guard", {}) as Dictionary).duplicate(true)

func force_rebuild_for_test() -> void:
	_rebuild()

func _sum_dictionary_ints(values: Dictionary) -> int:
	var total := 0
	for value in values.values():
		total += int(value)
	return total

func _density(tile_data: Dictionary) -> float:
	var density := 0.48
	if str(tile_data.get("road_density", "")) == "dense":
		density = 0.94
	var name := str(tile_data.get("nickname", "")).to_lower()
	if name.contains("old quarter") or name.contains("city"):
		density = maxf(density, 0.88)
	elif name.contains("docks") or name.contains("wharf") or name.contains("works"):
		density = maxf(density, 0.76)
	elif name != "":
		density = maxf(density, 0.62)
	if name == "":
		density = 0.38
	return density

func _district_focus(center: Vector2, tile_id: String, anchors: Array) -> Vector2:
	var focus := center + Vector2(
		_rr("mc-focus-x|%s" % tile_id, -18.0, 18.0),
		_rr("mc-focus-y|%s" % tile_id, -16.0, 16.0)
	)
	var nearest := Vector2.INF
	var nearest_d := INF
	for anchor_value in anchors:
		var point: Vector2 = (anchor_value as Dictionary).p
		var d := point.distance_squared_to(focus)
		if d < nearest_d:
			nearest_d = d
			nearest = point
	if nearest != Vector2.INF:
		# The visual centre belongs to a built street, but does not collapse onto
		# one exact sample point. This preserves an irregular district silhouette.
		focus = focus.lerp(nearest, 0.38)
	return focus

func _quad(center: Vector2, tangent: Vector2, length: float, depth: float,
		key: String, jitter: float) -> PackedVector2Array:
	var t := tangent.normalized()
	var n := Vector2(-t.y, t.x)
	var hu := length * 0.5
	var hv := depth * 0.5
	var points := PackedVector2Array([
		center - t * (hu + _rr("%s|u0" % key, -jitter, jitter)) - n * (hv + _rr("%s|v0" % key, -jitter, jitter)),
		center + t * (hu + _rr("%s|u1" % key, -jitter, jitter)) - n * (hv + _rr("%s|v1" % key, -jitter, jitter)),
		center + t * (hu + _rr("%s|u2" % key, -jitter, jitter)) + n * (hv + _rr("%s|v2" % key, -jitter, jitter)),
		center - t * (hu + _rr("%s|u3" % key, -jitter, jitter)) + n * (hv + _rr("%s|v3" % key, -jitter, jitter)),
	])
	return points

func _inside_hex(point: Vector2, center: Vector2, margin: float) -> bool:
	var inset := PackedVector2Array()
	for vertex in HEX_VERTS:
		inset.append(center + vertex.normalized() * maxf(0.0, vertex.length() - margin))
	return Geometry2D.is_point_in_polygon(point, inset)

func _near_anchor(point: Vector2, anchors: Array, distance: float) -> bool:
	for anchor_value in anchors:
		if point.distance_to((anchor_value as Dictionary).p) < distance:
			return true
	return false

func _junction_anchor(point: Vector2, tangent: Vector2, roads: Array) -> bool:
	var t := tangent.normalized()
	for road_value in roads:
		var segment: Array = road_value
		var a: Vector2 = segment[0]
		var b: Vector2 = segment[1]
		if _point_segment_distance(point, a, b) > 30.0:
			continue
		var other := (b - a).normalized()
		if other != Vector2.ZERO and absf(t.dot(other)) < 0.78:
			return true
	return false

func _point_segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	if ab.length_squared() <= 0.0001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return point.distance_to(a + ab * t)

func _bbox(poly: PackedVector2Array) -> Rect2:
	var lo := poly[0]
	var hi := poly[0]
	for point in poly:
		lo = lo.min(point)
		hi = hi.max(point)
	return Rect2(lo, hi - lo)

func _offset(poly: PackedVector2Array, amount: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in poly:
		out.append(point + amount)
	return out

func _append_line(into: PackedVector2Array, a: Vector2, b: Vector2) -> void:
	into.append(a)
	into.append(b)

## Owner rule (2026-08-16): no road-coloured line may cross sea or lake.
## Alleys and streets are laid out in PARCEL space and never consulted NavGrid,
## so a hero alley struck inward from a coastal face ran straight out over the
## bay — 1437u of it map-wide, runs up to 163u (tools/road_water_audit.tscn).
## Emits only the DRY sub-spans of [a,b], so a lane that meets the shore stops
## AT the shore instead of disappearing. Rivers are land here: roads cross them
## on bridges, and only sea/lake are the owner's rule (matching
## _morph_edge_touches_open_water).
const DRY_LINE_STEP := 6.0
const DRY_LINE_MIN := 4.0     # shorter than this is a stub, not a lane

func _append_dry_line(into: PackedVector2Array, a: Vector2, b: Vector2) -> void:
	var nav := NavGrid.instance()
	var span := a.distance_to(b)
	if span <= 0.001:
		return
	if nav == null or not nav.is_ready():
		_append_line(into, a, b)
		return
	var n := maxi(1, int(ceil(span / DRY_LINE_STEP)))
	var run_start := Vector2.INF
	var prev := Vector2.INF
	for i in range(n + 1):
		var p := a.lerp(b, float(i) / float(n))
		var cell := nav.cell_of(p)
		var kind := nav.water(cell.x, cell.y)
		if kind == NavGrid.WATER_SEA or kind == NavGrid.WATER_LAKE:
			if run_start != Vector2.INF:
				if run_start.distance_to(prev) >= DRY_LINE_MIN:
					_append_line(into, run_start, prev)
				run_start = Vector2.INF
		else:
			if run_start == Vector2.INF:
				run_start = p
			prev = p
	if run_start != Vector2.INF and run_start.distance_to(prev) >= DRY_LINE_MIN:
		_append_line(into, run_start, prev)

## Roles that ARE content without a building: a park, a yard or a deliberate open
## lot is meant to read as ground, so its outline stays.
const EMPTY_PARCEL_EXEMPT_ROLES := {
	"face_park": true, "street_park": true, "row_pocket": true,
	"accommodation_release": true, "hero_park": true, "hero_open": true,
	"face_open": true, "face_yard": true,
}
## A parcel covered by less than this fraction of drawn mass counts as unbuilt.
const EMPTY_PARCEL_COVER_MIN := 0.06
## Spatial-hash cell for the coverage test (world units).
const EMPTY_PARCEL_CELL := 128.0

## Suppress the outline of every parcel no mass was drawn in. Returns metrics.
## The fill is deliberately kept — see the call site.
func _suppress_empty_parcel_outlines(parcel_entries: Array,
		block_entries: Array) -> Dictionary:
	var out := {"checked": 0, "suppressed": 0, "suppressed_area": 0.0,
		"exempt": 0, "kept_built": 0}
	if _parcel_edges.is_empty() or parcel_entries.is_empty():
		return out
	# Bucket the masses so a parcel only tests its own neighbourhood.
	var grid: Dictionary = {}
	for i in block_entries.size():
		var bpoly: PackedVector2Array = (block_entries[i] as Dictionary).get(
			"poly", PackedVector2Array())
		if bpoly.size() < 3:
			continue
		var bb := _bbox(bpoly)
		var x0 := int(floor(bb.position.x / EMPTY_PARCEL_CELL))
		var x1 := int(floor(bb.end.x / EMPTY_PARCEL_CELL))
		var y0 := int(floor(bb.position.y / EMPTY_PARCEL_CELL))
		var y1 := int(floor(bb.end.y / EMPTY_PARCEL_CELL))
		for cx in range(x0, x1 + 1):
			for cy in range(y0, y1 + 1):
				var ck := "%d:%d" % [cx, cy]
				if not grid.has(ck):
					grid[ck] = PackedInt32Array()
				var bucket: PackedInt32Array = grid[ck]
				bucket.append(i)
				grid[ck] = bucket
	var drop: Dictionary = {}
	for entry_value in parcel_entries:
		var entry: Dictionary = entry_value
		var poly: PackedVector2Array = entry.get("poly", PackedVector2Array())
		if poly.size() < 3:
			continue
		if EMPTY_PARCEL_EXEMPT_ROLES.has(str(entry.get("role", ""))):
			out.exempt = int(out.exempt) + 1
			continue
		out.checked = int(out.checked) + 1
		var area := _poly_area(poly)
		if area <= 0.0:
			continue
		var bb := _bbox(poly)
		var seen: Dictionary = {}
		var covered := 0.0
		var x0 := int(floor(bb.position.x / EMPTY_PARCEL_CELL))
		var x1 := int(floor(bb.end.x / EMPTY_PARCEL_CELL))
		var y0 := int(floor(bb.position.y / EMPTY_PARCEL_CELL))
		var y1 := int(floor(bb.end.y / EMPTY_PARCEL_CELL))
		for cx in range(x0, x1 + 1):
			for cy in range(y0, y1 + 1):
				var bucket: PackedInt32Array = grid.get("%d:%d" % [cx, cy],
					PackedInt32Array())
				for bi in bucket:
					if seen.has(bi):
						continue
					seen[bi] = true
					var bpoly: PackedVector2Array = (block_entries[bi] as Dictionary).get(
						"poly", PackedVector2Array())
					if bpoly.size() < 3:
						continue
					for piece_value in Geometry2D.intersect_polygons(poly, bpoly):
						covered += _poly_area(piece_value as PackedVector2Array)
				if covered >= area * EMPTY_PARCEL_COVER_MIN:
					break
		if covered >= area * EMPTY_PARCEL_COVER_MIN:
			out.kept_built = int(out.kept_built) + 1
			continue
		out.suppressed = int(out.suppressed) + 1
		out.suppressed_area = float(out.suppressed_area) + area
		for i in poly.size():
			drop[_edge_key(poly[i], poly[(i + 1) % poly.size()])] = true
	if drop.is_empty():
		return out
	var kept := PackedVector2Array()
	var seg := 0
	while seg + 1 < _parcel_edges.size():
		var a := _parcel_edges[seg]
		var b := _parcel_edges[seg + 1]
		if not drop.has(_edge_key(a, b)):
			kept.append(a)
			kept.append(b)
		seg += 2
	_parcel_edges = kept
	return out

## Order-independent identity for a drawn ring segment.
func _edge_key(a: Vector2, b: Vector2) -> String:
	if a.x < b.x or (a.x == b.x and a.y <= b.y):
		return "%.3f,%.3f|%.3f,%.3f" % [a.x, a.y, b.x, b.y]
	return "%.3f,%.3f|%.3f,%.3f" % [b.x, b.y, a.x, a.y]

func _append_ring(into: PackedVector2Array, poly: PackedVector2Array) -> void:
	for i in poly.size():
		_append_line(into, poly[i], poly[(i + 1) % poly.size()])

func _rr(key: String, low: float, high: float) -> float:
	return lerpf(low, high, float(RoadHash.pick(key, 10001)) / 10000.0)

func _fill_mesh(entries: Array) -> ArrayMesh:
	var vertices := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for entry_value in entries:
		var entry: Dictionary = entry_value
		var poly: PackedVector2Array = entry.poly
		var triangles := Geometry2D.triangulate_polygon(poly)
		if triangles.is_empty():
			continue
		var base := vertices.size()
		for point in poly:
			vertices.append(point)
			colors.append(entry.color)
		for index in triangles:
			indices.append(base + index)
	if vertices.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _draw() -> void:
	if not MapStyle.is_midcentury():
		return
	if _far_plate_active:
		if _far_plate_mesh != null:
			draw_mesh(_far_plate_mesh, null)
		return
	if _parcel_mesh != null:
		draw_mesh(_parcel_mesh, null)
	if _yard_mesh != null:
		draw_mesh(_yard_mesh, null)
	if not _settlement_streets.is_empty():
		draw_multiline(_settlement_streets, Color(MapMidcenturyStyle.INK, 0.48), 4.8, true)
		draw_multiline(_settlement_streets, Color(MapMidcenturyStyle.PAPER_LIGHT, 0.96), 3.0, true)
	if not _service_lines.is_empty():
		draw_multiline(_service_lines, Color(MapMidcenturyStyle.INK, 0.38), 5.2, true)
		draw_multiline(_service_lines, MapMidcenturyStyle.PAPER, 3.4, true)
	if not _hero_alleys.is_empty():
		draw_multiline(_hero_alleys, Color(MapMidcenturyStyle.INK, 0.18), 3.6, true)
		draw_multiline(_hero_alleys, Color(MapMidcenturyStyle.PAPER_LIGHT, 0.92), 2.2, true)
	if _shadow_mesh != null:
		draw_mesh(_shadow_mesh, null)
	if _park_mesh != null:
		draw_mesh(_park_mesh, null)
	if _block_mesh != null:
		draw_mesh(_block_mesh, null)
	if _roof_shadow_mesh != null:
		draw_mesh(_roof_shadow_mesh, null)
	if _roof_top_mesh != null:
		draw_mesh(_roof_top_mesh, null)
	if not _parcel_edges.is_empty():
		draw_multiline(_parcel_edges, Color(MapMidcenturyStyle.INK, 0.26), 0.75, true)
	if not _block_edges.is_empty():
		draw_multiline(_block_edges, Color(MapMidcenturyStyle.INK, 0.82), 1.05, true)
	if not _roof_edges.is_empty():
		draw_multiline(_roof_edges, Color(MapMidcenturyStyle.INK, 0.68), 0.78, true)
	# Retired decorative bar vocabulary: terrace divisions, paired vents,
	# utility stripes and vacant-lot hatches accumulated into repeated parallel
	# marks at every scale. Ordinary fabric now reads from silhouette, roof caps,
	# courts and parcel edges; gameplay-industry machinery keeps its own detail.
	if not _park_marks.is_empty():
		draw_multiline(_park_marks, Color(MapMidcenturyStyle.PAPER, 0.54), 0.9, true)

func _clear_geometry() -> void:
	_parcel_mesh = null
	_yard_mesh = null
	_shadow_mesh = null
	_park_mesh = null
	_block_mesh = null
	_roof_shadow_mesh = null
	_roof_top_mesh = null
	_far_plate_mesh = null
	_roof_shadow_entries = []
	_roof_top_entries = []
	_parcel_edges = PackedVector2Array()
	_block_edges = PackedVector2Array()
	_roof_edges = PackedVector2Array()
	_roof_marks = PackedVector2Array()
	_park_marks = PackedVector2Array()
	_open_lot_marks = PackedVector2Array()
	_service_lines = PackedVector2Array()
	_hero_alleys = PackedVector2Array()
	_settlement_streets = PackedVector2Array()
	_active_plan = null
	_active_plan_water_exclusions = []
	queue_redraw()

func metrics() -> Dictionary:
	return _metrics.duplicate(true)

func accommodation_planning_snapshot() -> Dictionary:
	# Read-only draw-planning seam for deterministic capture/audit tools. These
	# records are deliberately retained while the optional style is off so the
	# planner result is not style state, occupancy or save state.
	return {
		"sites": _accommodation_sites.duplicate(true),
		"decorative_masses": _decorative_mass_records.duplicate(true),
	}

## Read-only seam for the per-tile density audit (docs/map-density-and-port-
## addendum.md section 6). Returns every decorative mass and green polygon that
## SURVIVED both sanitisation guards, tagged with the kind that produced it.
## Gameplay buildings are not here — they are drawn by BuildingVisuals and are
## frozen — so nothing in this snapshot is countable gameplay geometry.
func density_audit_snapshot() -> Dictionary:
	var masses: Array = []
	for entry_value in _render_mass_entries:
		var entry: Dictionary = entry_value
		var poly: PackedVector2Array = entry.get("poly", PackedVector2Array())
		if poly.size() < 3:
			continue
		masses.append({
			"kind": str(entry.get("kind", "ordinary")),
			"poly": poly.duplicate(),
			"area": _poly_area(poly),
			"center": _poly_center(poly),
		})
	var greens: Array = []
	for entry_value in _render_park_entries:
		var entry: Dictionary = entry_value
		var poly: PackedVector2Array = entry.get("poly", PackedVector2Array())
		if poly.size() < 3:
			continue
		greens.append({
			"kind": str(entry.get("kind", "green")),
			# The PLAN's own role assignment, stamped where the role was decided.
			# A green that reaches the render arrays without one has no owning
			# role record and is a HOLE, not a park (instrument 2).
			"role": str(entry.get("role", "")),
			"poly": poly.duplicate(),
			"area": _poly_area(poly),
			"center": _poly_center(poly),
		})
	var parcels: Array = []
	for entry_value in _render_parcel_entries:
		var entry: Dictionary = entry_value
		var poly: PackedVector2Array = entry.get("poly", PackedVector2Array())
		if poly.size() < 3:
			continue
		parcels.append({
			"role": str(entry.get("role", "")),
			"poly": poly.duplicate(),
			"area": _poly_area(poly),
			"center": _poly_center(poly),
		})
	# THE SHADOW LAYER. `_shadow_mesh` fills one of these under every block at
	# BLOCK_SHADOW_OFFSET, so the shape the plate draws for a mass is the mass
	# UNION its shadow - strictly larger than the mass. Withholding this layer
	# is what let the gauntlet6 articulation instrument report 1259 visible
	# pieces where the plate draws 1031. It is handed over as its own array, not
	# reconstructed by offsetting, so the audit measures the polygons that were
	# actually filled (after both sanitisers) rather than a model of them.
	var shadows: Array = []
	for entry_value in _render_shadow_entries:
		var entry: Dictionary = entry_value
		var poly: PackedVector2Array = entry.get("poly", PackedVector2Array())
		if poly.size() < 3:
			continue
		shadows.append({"poly": poly.duplicate(), "area": _poly_area(poly),
			"center": _poly_center(poly)})
	# Every inked outline the fabric draws, as flat a->b pairs. Retained as a
	# DIAGNOSTIC only: because every park site appends a green and then rings
	# THE SAME polygon into this layer, an enclosure test against it is
	# tautological (gauntlet6 break P1). Enclosure is now measured against the
	# drawn masses, not against this.
	var ink := PackedVector2Array()
	ink.append_array(_block_edges)
	ink.append_array(_parcel_edges)
	ink.append_array(_roof_edges)
	return {"masses": masses, "greens": greens, "parcels": parcels,
		"shadows": shadows,
		"ink_segments": ink,
		"large_mass_area_threshold": DensityAudit.LARGE_MASS_AREA}

## Dry BUILDABLE area per tile, using the exact exclusion vocabulary the fabric
## itself builds against: the shared water margin, forest discs, relief
## shoulders and gameplay footprints. Read-only; changes nothing.
##
## Relief MUST be resolved one tile at a time. `get_land_relief_geometry` only
## reports shoulders when the extent it is given spans three or more material
## bands, so asking it once for every hex at once activates relief on tiles that
## individually have no relief structure and over-clips them — a batched variant
## drove some tiles to zero buildable area. The per-tile call is also how the
## rural growth pass itself asks, so this matches what the fabric built against.
func tile_dry_buildable_areas(coords: Array) -> Dictionary:
	var out: Dictionary = {}
	if _terrain == null:
		return out
	for coord_value in coords:
		var coord: Vector2i = coord_value
		if not _terrain.tiles.has(coord):
			continue
		var center := _terrain.map_to_local(
			_terrain.map_coord_for_tile_coord(coord))
		var hex := PackedVector2Array()
		for vertex in HEX_VERTS:
			hex.append(center + vertex)
		var hex_area := _poly_area(hex)
		var water_exclusions := _hero_water_exclusions(_bbox(hex))
		var dry_pieces := _hero_clip_polys([hex], water_exclusions, 1.0)
		var dry_land_area := 0.0
		for piece_value in dry_pieces:
			dry_land_area += _poly_area(piece_value)
		var forest_discs: Array = []
		if _forests != null and _forests.has_method("discs_on_tile"):
			forest_discs = _forests.discs_on_tile(coord)
		var footprints: Array = []
		if _buildings != null and _buildings.has_method("footprint_rects_on_tile"):
			footprints = _buildings.footprint_rects_on_tile(coord)
		var occupancy_exclusions: Array = []
		occupancy_exclusions.append_array(_hero_forest_exclusions(forest_discs))
		occupancy_exclusions.append_array(_hero_footprint_exclusions(footprints))
		var open_pieces := _hero_clip_polys(dry_pieces, occupancy_exclusions, 1.0)
		var open_area := 0.0
		for piece_value in open_pieces:
			open_area += _poly_area(piece_value)
		# Relief shoulders are offset RINGS around contours. Clipping a whole hex
		# by them can erase the plateaus they enclose, which is why the fabric
		# itself abandons relief whenever it retains less than
		# MORPH_MIN_RELIEF_AREA_RETENTION of the pre-relief area. The probe has to
		# apply the same fallback or it reports tiles that visibly carry buildings
		# as having zero buildable land.
		var relief := _relief_geometry_for_extents([hex])
		var shoulders: Array = relief.get("shoulders", [])
		var buildable_area := open_area
		var relief_fallback := false
		if bool(relief.get("active", false)) and not shoulders.is_empty():
			var relief_pieces := _hero_clip_polys(open_pieces, shoulders, 1.0)
			var relief_area := 0.0
			for piece_value in relief_pieces:
				relief_area += _poly_area(piece_value)
			if relief_area / maxf(1.0, open_area) < MORPH_MIN_RELIEF_AREA_RETENTION:
				relief_fallback = true
			else:
				buildable_area = relief_area
		out[coord] = {
			"hex_area": hex_area,
			"dry_land_area": dry_land_area,
			"open_land_area": open_area,
			"dry_buildable_area": buildable_area,
			"water_margin_area": hex_area - dry_land_area,
			"forest_disc_count": forest_discs.size(),
			"gameplay_footprint_count": footprints.size(),
			"relief_shoulder_count": shoulders.size(),
			"relief_retention_fallback": relief_fallback,
		}
	return out

func settlement_plan(plan_key: String) -> SettlementPlan:
	return _settlement_plans.get(plan_key) as SettlementPlan
