extends Node
## Per-tile decorative-density compliance audit.
##   <godot> --headless --path . res://tools/density_audit.tscn --quit-after 4000
##
## Implements section 6 of docs/map-density-and-port-addendum.md: for EVERY land
## tile it emits tile id, nickname, class (urban/sparse/mountain/remote), small
## and large decorative-building counts, green-space count and area, dry
## buildable area, and pass/fail against the section-2 table.
##
## It measures the geometry the mid-century style ACTUALLY RENDERS — the
## sanitised block and park layers, read through
## `UrbanFabricVisuals.density_audit_snapshot()`. Gameplay buildings are frozen
## and are never counted. The audit changes nothing; it only reads.
##
## Exit codes
##   0  every audited tile complies
##   1  the audit could not run (missing node, missing profile data)
##   2  the audit ran and the map does not comply — the intended baseline result
##
## Outputs
##   /tmp/poe_density_audit.json   full per-tile record
##   /tmp/poe_density_audit.txt    human-readable table and failure list

const PROFILE_PATH := "res://data/visual_settlement_profiles.json"
const JSON_PATH := "/tmp/poe_density_audit.json"
const TEXT_PATH := "/tmp/poe_density_audit.txt"
## Tile centres are 405u apart in x and 480u in y; anything further than this
## cannot share area with the mass being assigned.
const NEIGHBOUR_RADIUS := 640.0
## Fixed, non-lattice displacement for the enclosure negative control below.
const CONTROL_DISPLACEMENT := Vector2(37.0, 29.0)

var _terrain: TileMapLayer = null
var _fabric: Node = null


func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	for _i in 240:
		await get_tree().process_frame
	_terrain = game.get_node_or_null("%TerrainLayer") as TileMapLayer
	_fabric = game.find_child("UrbanFabricVisuals", true, false)
	if _terrain == null or _fabric == null:
		push_error("density_audit: TerrainLayer or UrbanFabricVisuals missing")
		get_tree().quit(1)
		return
	MapStyle.set_midcentury(true)
	for _i in 60:
		await get_tree().process_frame
	if not _fabric.has_method("density_audit_snapshot"):
		push_error("density_audit: fabric has no density_audit_snapshot() seam")
		get_tree().quit(1)
		return
	var report := _audit()
	MapStyle.set_midcentury(false)
	_write(JSON_PATH, JSON.stringify(report, "  "))
	_write(TEXT_PATH, _render_text(report))
	_print_summary(report)
	var summary: Dictionary = report.summary
	get_tree().quit(0 if int(summary.gate_failure_tiles) == 0 else 2)


func _audit() -> Dictionary:
	var profiles := _load_profiles()
	if profiles.is_empty():
		push_error("density_audit: no urban profiles at %s" % PROFILE_PATH)
		get_tree().quit(1)
		return {}
	var snapshot: Dictionary = _fabric.call("density_audit_snapshot")
	var fabric_metrics: Dictionary = _fabric.call("metrics")

	# --- tile table -------------------------------------------------------
	var tile_records: Array = []
	var coords: Array = _terrain.tiles.keys()
	coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x or (a.x == b.x and a.y < b.y))
	for coord_value in coords:
		var coord: Vector2i = coord_value
		var tile_data: Dictionary = _terrain.tiles[coord]
		var tile_id := str(tile_data.get("id", "%d_%d" % [coord.x, coord.y]))
		var terrain_type := str(tile_data.get("type", ""))
		var center: Vector2 = _terrain.map_to_local(
			_terrain.map_coord_for_tile_coord(coord))
		var hex := PackedVector2Array()
		for vertex in UrbanFabricVisuals.HEX_VERTS:
			hex.append(center + vertex)
		var built_edges := _built_road_edge_count(coord)
		var tile_class := DensityAudit.classify(terrain_type,
			profiles.has(tile_id), built_edges)
		tile_records.append({
			"tile_id": tile_id,
			"nickname": str(tile_data.get("nickname", "")),
			"coord": [coord.x, coord.y],
			"terrain_type": terrain_type,
			"class": tile_class,
			"urban_profile": str(profiles.get(tile_id, "")),
			"built_road_edge_count": built_edges,
			"center": center,
			"hex": hex,
			"bb": _bbox(hex),
			"small_count": 0, "large_count": 0,
			"small_area": 0.0, "large_area": 0.0,
			"courtyard_count": 0, "courtyard_area": 0.0,
			"mass_kind_counts": {},
			"green_entries": [],
			"mass_indices": PackedInt32Array(),
			"bare_parcels": [],
			"subfloor_greens": [],
		})

	# --- profile / classification consistency ----------------------------
	var profiled_not_urban: Array = []
	var urban_not_profiled: Array = []
	for record_value in tile_records:
		var record: Dictionary = record_value
		var profiled: bool = profiles.has(str(record.tile_id))
		var typed_urban: bool = str(record.terrain_type) == "urban"
		if profiled and not typed_urban:
			profiled_not_urban.append(str(record.tile_id))
		elif typed_urban and not profiled:
			urban_not_profiled.append(str(record.tile_id))

	# --- assign every rendered mass and green to one tile ----------------
	#
	# G7 REPAIR (breaks A4, P5). `shapes` is EVERYTHING THE PLATE FILLS in the
	# block layer, in three bands:
	#   [0, counted_mass_count)   the counted buildings. Index i here IS mass i,
	#                             and `mass_tile[i]` is the tile it was charged
	#                             to, so per-tile articulation can be derived
	#                             from the same assignment the mass counts use.
	#   next band                 sub-floor and non-building masses. Drawn ink,
	#                             not buildings: they may FUSE two pieces but
	#                             never count as one. Without them a chain of
	#                             119 u^2 crumbs bridges two masses the
	#                             instrument still calls two pieces.
	#   last band                 THE SHADOW FILLS, taken from the fabric's own
	#                             sanitised array. Withholding this layer is why
	#                             gauntlet6 reported 1259 pieces on a plate that
	#                             draws 1031.
	var areas: Array[float] = []
	var unassigned_masses := 0
	var unassigned_greens := 0
	var uncounted_masses := 0
	var shapes: Array = []
	var mass_tile: PackedInt32Array = PackedInt32Array()
	var bridge_shapes: Array = []
	for mass_value in snapshot.get("masses", []):
		var mass: Dictionary = mass_value
		var area := float(mass.area)
		areas.append(area)
		var kind := str(mass.kind)
		if not DensityAudit.counts_as_building(kind, area):
			uncounted_masses += 1
			bridge_shapes.append({"poly": mass.poly, "area": area,
				"kind": kind, "counts": false})
			continue
		var owner_index := _owning_tile(tile_records, mass.poly, mass.center)
		shapes.append({"poly": mass.poly, "area": area, "kind": kind,
			"counts": true})
		mass_tile.append(owner_index)
		if owner_index < 0:
			unassigned_masses += 1
			continue
		var record: Dictionary = tile_records[owner_index]
		# PackedInt32Array is a VALUE type: `(record.x as PackedInt32Array)
		# .append(...)` appends to a copy and throws it away. Read, append,
		# write back.
		var owned: PackedInt32Array = record.mass_indices
		owned.append(shapes.size() - 1)
		record.mass_indices = owned
		(record.mass_kind_counts as Dictionary)[kind] = int(
			(record.mass_kind_counts as Dictionary).get(kind, 0)) + 1
		if DensityAudit.is_large(area):
			record.large_count = int(record.large_count) + 1
			record.large_area = float(record.large_area) + area
		else:
			record.small_count = int(record.small_count) + 1
			record.small_area = float(record.small_area) + area
	var counted_mass_count := shapes.size()
	var sub_floor_bridge_count := bridge_shapes.size()
	shapes.append_array(bridge_shapes)
	var shadow_bridge_count := 0
	for shadow_value in snapshot.get("shadows", []):
		var shadow: Dictionary = shadow_value
		shapes.append({"poly": shadow.poly, "area": float(shadow.area),
			"kind": "shadow", "counts": false})
		shadow_bridge_count += 1

	# G7 REPAIR (break P2 - SELF-DECLARATION). Every drawn green is kept and
	# judged. `kind == "courtyard"` used to `continue` BEFORE any verdict, and
	# 155 of 454 rendered greens (264,873 u^2, 27% of the reported park area)
	# already took that exit: relabelling a residual pocket `courtyard` deleted
	# it from both the park and the hole count. No label is read here now; the
	# verdict is taken from the drawing in the per-tile loop below.
	for green_value in snapshot.get("greens", []):
		var green: Dictionary = green_value
		var kind := str(green.kind)
		var area := float(green.area)
		var owner_index := _owning_tile(tile_records, green.poly, green.center)
		if owner_index < 0:
			unassigned_greens += 1
			continue
		var record: Dictionary = tile_records[owner_index]
		if kind == "courtyard":
			record.courtyard_count = int(record.courtyard_count) + 1
			record.courtyard_area = float(record.courtyard_area) + area
		if area < DensityAudit.MIN_COUNTED_GREEN_AREA:
			# G7b REPAIR (break F7). gauntlet7 shattered a 1,000 u² hole into
			# six 168 u² shards and it vanished before any verdict. Sub-floor
			# greens are now kept and merged among themselves below; a shattered
			# hole reassembles into one shape and is judged.
			(record.subfloor_greens as Array).append({"poly": green.poly,
				"area": area})
			continue
		(record.green_entries as Array).append({"poly": green.poly,
			"role": str(green.get("role", "")), "kind": kind, "area": area})

	# --- INSTRUMENT 1: visible pieces, map-wide, then assigned to tiles ---
	# The clustering is done ONCE over the whole map so a silhouette that
	# straddles a hex side stays one piece.
	var pieces: Array = DensityAudit.visible_pieces(shapes)
	# THE GRADED FUSION RESPONSE (break A3). The same shapes clustered at half
	# an accepted alley, one alley and two. A plate whose articulation only
	# exists because its gaps are a hair over the limit collapses across this
	# curve; a plate separated by real streets does not move.
	var fusion: Dictionary = DensityAudit.fusion_curve(shapes)

	# G7 REPAIR - PER-TILE DENOMINATOR (the tile_20_11 shape, live).
	# gauntlet6 clustered pieces map-wide and then charged each piece WHOLE to
	# one tile while assigning masses individually. 57 of 600 tiles disagreed:
	# tile_23_9 owned 34 masses and was charged 90, and tile_22_8 owned 21
	# masses and was charged ZERO pieces, so it read as having no articulation
	# problem while its entire fabric sat inside a neighbour's amoeba.
	#
	# A tile is now charged exactly the pieces ITS OWN masses fall into, so its
	# numerator and denominator come from one assignment. A piece holding masses
	# from two tiles is counted by BOTH and reported as SHARED, and the
	# reconciliation between the per-tile sum and the map total is printed
	# rather than left to be discovered.
	var mass_piece: PackedInt32Array = PackedInt32Array()
	mass_piece.resize(counted_mass_count)
	for i in counted_mass_count:
		mass_piece[i] = -1
	var piece_tiles: Array = []
	for _i in pieces.size():
		piece_tiles.append({})
	for piece_index in pieces.size():
		var piece: Dictionary = pieces[piece_index]
		for member_value in (piece.members as PackedInt32Array):
			var member := int(member_value)
			if member >= counted_mass_count:
				continue
			mass_piece[member] = piece_index
			var owner := mass_tile[member]
			if owner >= 0:
				(piece_tiles[piece_index] as Dictionary)[owner] = true
	var unassigned_pieces := 0
	var cross_tile_pieces := 0
	for piece_index in pieces.size():
		if int(pieces[piece_index].mass_count) <= 0:
			continue
		var owners: Dictionary = piece_tiles[piece_index]
		if owners.is_empty():
			unassigned_pieces += 1
		elif owners.size() > 1:
			cross_tile_pieces += 1

	# --- INSTRUMENT 2: bare parcels --------------------------------------
	#
	# G7 REPAIR (break P4). The coverage field is now THE DRAWN MASSES ONLY.
	# gauntlet6 counted greens of every kind as cover, so stamping a
	# courtyard-kind green over an empty plot removed the bare parcel AND was
	# skipped by the green verdict - the hole left no trace in either
	# instrument. A green is not a building; an empty plot with a green on it is
	# still an empty plot.
	#
	# Three numbers are produced, deliberately overlapping:
	#   bare_parcels        role-gated, as before. Beatable by renaming
	#                       `face_built` to `face_open`; kept for continuity.
	#   empty_parcels       EVERY parcel over the floor, whatever it calls
	#                       itself, with under 10% mass cover. A rename moves a
	#                       parcel between the two buckets above and leaves this
	#                       one exactly where it was.
	#   uncovered_parcel_area   area-weighted over EVERY drawn parcel with no
	#                       floor at all. Splitting one 2,995 u^2 plot into five
	#                       599 u^2 slivers drops out of both counts above and
	#                       leaves this number unchanged.
	var cover_polys: Array = []
	for mass_value in snapshot.get("masses", []):
		cover_polys.append((mass_value as Dictionary).poly)
	var cover_grid := _build_poly_grid(cover_polys)
	var ink_grid: Dictionary = DensityAudit.build_ink_grid(
		snapshot.get("ink_segments", PackedVector2Array()))
	var unassigned_bare := 0
	var judged_parcels := 0
	var empty_parcel_count := 0
	var empty_parcel_area := 0.0
	var empty_parcel_roles: Dictionary = {}
	var uncovered_parcel_area := 0.0
	var total_parcel_area := 0.0
	for parcel_value in snapshot.get("parcels", []):
		var parcel: Dictionary = parcel_value
		var role := str(parcel.get("role", ""))
		var area := float(parcel.area)
		if area <= 0.0:
			continue
		var covered := _covered_fraction(parcel.poly, area, cover_polys,
			cover_grid)
		total_parcel_area += area
		uncovered_parcel_area += area * maxf(0.0, 1.0 - covered)
		if DensityAudit.parcel_is_empty(area, covered):
			empty_parcel_count += 1
			empty_parcel_area += area
			empty_parcel_roles[role] = int(empty_parcel_roles.get(role, 0)) + 1
		if not DensityAudit.is_built_parcel_role(role):
			continue
		if area < DensityAudit.MIN_COUNTED_PARCEL_AREA:
			continue
		judged_parcels += 1
		if not DensityAudit.parcel_is_bare(role, area, covered):
			continue
		var owner_index := _owning_tile(tile_records, parcel.poly,
			parcel.center)
		if owner_index < 0:
			unassigned_bare += 1
			continue
		((tile_records[owner_index] as Dictionary).bare_parcels as Array).append({
			"role": role, "area": area, "covered_fraction": covered})

	# THE FABRIC GRID THE ENCLOSURE TEST PROBES AGAINST.
	#
	# G7b REPAIR (break F2) — IT IS THE COUNTED BUILDINGS, AND NOTHING ELSE.
	# The first repair probed against `cover_polys`, which is EVERY mass in the
	# snapshot including the sub-floor ones. A mass under
	# `MIN_COUNTED_MASS_AREA` is not a building — it adds no mass, no visible
	# piece and no obligation — and it answered the outward probe, so an undrawn
	# hole could buy a verdict with dots: gauntlet7 measured 12 dots of 100 u²
	# turning a bare 60x60 hole into a certified PUBLIC GREEN and 24 dots
	# turning it into an inner court, at 5.0 u² of dots per unit of hole
	# perimeter — 8.06% of the map's drawn parcel area would have converted all
	# 334 holes and bought zero buildings. That is the L1 shape again: the
	# fabric drawing its own certificate.
	#
	# Probing against counted buildings only means the only ink that can certify
	# a green is ink that is itself charged on every count row of section 2. A
	# dot ring is now invisible to this test.
	var certifying_polys: Array = DensityAudit.counted_mass_polys(
		snapshot.get("masses", []))
	var fabric_grid: Dictionary = DensityAudit.build_mass_grid(
		certifying_polys)

	# --- evaluate ---------------------------------------------------------
	var shortfall_records: Dictionary = fabric_metrics.get(
		"density_shortfalls", {})
	var rural_tiles: Dictionary = (fabric_metrics.get("rural_growth", {}) as \
		Dictionary).get("tiles", {})
	var accommodation_tiles: Dictionary = (fabric_metrics.get(
		"accommodation", {}) as Dictionary).get("tiles", {})
	var land_coords: Array = []
	for record_value in tile_records:
		var record: Dictionary = record_value
		if str(record["class"]) == DensityAudit.CLASS_WATER:
			continue
		land_coords.append(Vector2i(int(record.coord[0]), int(record.coord[1])))
	var geometry_by_coord: Dictionary = _fabric.call(
		"tile_dry_buildable_areas", land_coords)
	# THE REPAIRED MEASUREMENT and its controls, all reported every run.
	var fabric_enclosure_samples: Array[float] = []
	var fabric_control_samples: Array[float] = []
	# The graded band curve, and the FAIR control at every band. Index i is
	# DensityAudit.PARK_BAND_SCALES[i].
	var band_samples: Array = []
	var band_control_samples: Array = []
	for _i in DensityAudit.PARK_BAND_SCALES.size():
		var real_bucket: Array[float] = []
		var control_bucket: Array[float] = []
		band_samples.append(real_bucket)
		band_control_samples.append(control_bucket)
	var control_placed := 0
	var control_unplaceable := 0
	# The gauntlet6 numbers, kept so the tautology stays visible in the record.
	var enclosure_samples: Array[float] = []
	var control_enclosure_samples: Array[float] = []
	var foreign_enclosure_samples: Array[float] = []
	var role_share_samples: Array[float] = []
	var green_shape_counts: Dictionary = {}
	var class_counts: Dictionary = {}
	var class_compliant: Dictionary = {}
	var class_constrained: Dictionary = {}
	var failures: Array = []
	var audited := 0
	var gate_failure_tiles := 0
	var out_tiles: Array = []
	for record_value in tile_records:
		var record: Dictionary = record_value
		var tile_class := str(record["class"])
		var tile_id := str(record.tile_id)
		# --- INSTRUMENT 2, REPAIRED ------------------------------------
		# Every green is judged ON ITS OWN OUTLINE first, from geometry only.
		# gauntlet6 judged the MERGED outline and gated on an AREA share of
		# park-role entries, so one 20,000 u^2 hero park that merely grazed
		# nineteen 1,000 u^2 pockets laundered all nineteen into itself and they
		# stopped being counted at all. A pocket now has to stand on its own
		# perimeter, whatever it is touching and whatever it is called.
		var judged_entries: Array = []
		var hole_count := 0
		var hole_area := 0.0
		var court_count := 0
		var court_area := 0.0
		var hole_reasons: Dictionary = {}
		# G7b REPAIR (break F7). The sub-floor greens this tile owns, merged
		# among themselves first: a hole shattered into shards reassembles into
		# one shape and is judged like any other green. `subfloor_green_count`
		# reports how many entries that recovered.
		var recovered: Array = DensityAudit.cluster_subfloor_greens(
			record.subfloor_greens as Array)
		var green_entries: Array = (record.green_entries as Array).duplicate()
		for recovered_value in recovered:
			var recovered_entry: Dictionary = recovered_value
			green_entries.append({"poly": recovered_entry.poly, "role": "",
				"kind": "", "area": float(recovered_entry.area)})
		for entry_value in green_entries:
			var entry: Dictionary = entry_value
			var fabric_enclosure := DensityAudit.mass_band_enclosure(
				entry.poly, fabric_grid)
			var verdict: Dictionary = DensityAudit.green_verdict(
				fabric_enclosure)
			var shape := str(verdict.shape)
			green_shape_counts[shape] = int(
				green_shape_counts.get(shape, 0)) + 1
			fabric_enclosure_samples.append(fabric_enclosure)
			# THE NEGATIVE CONTROL, and it has to be a FAIR one. Displacing a
			# green by one fixed vector often drops it ON TOP of a building,
			# and an outline inside a building is trivially surrounded by that
			# building - which says nothing about whether CLEAR GROUND reads as
			# enclosed. The control therefore walks a fixed, deterministic
			# spiral of displacements and takes the first placement that
			# overlaps no drawn mass: the same shape, on unbuilt ground
			# elsewhere. If that scores as enclosed as the real green, the
			# fabric is simply everywhere and the test is vacuous - the failure
			# that let `interarm_sea_coverage` score 100% on a paved basin.
			var control_poly := _clear_ground_control(entry.poly, fabric_grid)
			if control_poly.is_empty():
				control_unplaceable += 1
			else:
				control_placed += 1
				fabric_control_samples.append(
					DensityAudit.mass_band_enclosure(control_poly, fabric_grid))
			# THE GRADED BAND CURVE. One band is one point on a curve, and a
			# candidate could sit just outside it - the same step-function
			# failure that broke instrument 1 (break A3). Every band is
			# reported, for the real greens and for the control.
			for band_index in DensityAudit.PARK_BAND_SCALES.size():
				var band := DensityAudit.PARK_FABRIC_BAND * \
					DensityAudit.PARK_BAND_SCALES[band_index]
				(band_samples[band_index] as Array[float]).append(
					DensityAudit.mass_band_enclosure(entry.poly, fabric_grid,
						band))
				if not control_poly.is_empty():
					(band_control_samples[band_index] as Array[float]).append(
						DensityAudit.mass_band_enclosure(control_poly,
							fabric_grid, band))
			# The gauntlet6 measurements, retained as diagnostics so the
			# tautology they suffered from stays in the record: `own_ink` is the
			# shipped test (it cannot fall below 1.000 because the fabric rings
			# every green it emits), `foreign` removes exactly the green's own
			# ring, and `role_share` is the self-declared label.
			enclosure_samples.append(DensityAudit.enclosure_fraction(entry.poly,
				ink_grid))
			foreign_enclosure_samples.append(_foreign_enclosure(entry.poly,
				ink_grid))
			role_share_samples.append(1.0 if DensityAudit.is_park_role(
				str(entry.get("role", ""))) else 0.0)
			var entry_area := float(entry.area)
			# G7b REPAIR (break F3). A wrapped green is charged. In the first
			# repair it was `inner_court`: DELIBERATE, excluded from the park
			# count AND from the hole count, so deleting a building inside a
			# 3x3 block raised the park count and lowered the hole count at
			# once — the same free exit `kind == "courtyard"` used to give,
			# bought with geometry instead of a string. It is now reported in
			# `unverified_green_count` beside the holes, so no edit to the
			# drawing can move a green into a bucket that costs nothing.
			if shape == "hole":
				hole_count += 1
				hole_area += entry_area
				var reason := str(verdict.reason)
				hole_reasons[reason] = int(hole_reasons.get(reason, 0)) + 1
			elif shape == "wrapped_green":
				court_count += 1
				court_area += entry_area
				hole_reasons["wrapped_by_fabric"] = int(hole_reasons.get(
					"wrapped_by_fabric", 0)) + 1
			judged_entries.append({"poly": entry.poly, "area": entry_area,
				"public": bool(verdict.public),
				"fabric_enclosure": fabric_enclosure})
		# Touching greens are ONE green space for the >= 2 urban floor, but a
		# space only earns park credit for the area of the entries that passed
		# on their own.
		var green_spaces := _merge_green_spaces(judged_entries)
		var green_area := 0.0
		var deliberate_count := 0
		var deliberate_area := 0.0
		for space_value in green_spaces:
			var space: Dictionary = space_value
			green_area += absf(_poly_area(space.poly))
			if float(space.public_area) >= DensityAudit.MIN_COUNTED_GREEN_AREA:
				deliberate_count += 1
				deliberate_area += float(space.public_area)
		var bare_area := 0.0
		for bare_value in record.bare_parcels:
			bare_area += float((bare_value as Dictionary).area)
		var articulation: Dictionary = _tile_articulation(
			record.mass_indices, mass_piece, pieces, piece_tiles)
		var geometry: Dictionary = {}
		var evaluation: Dictionary = {}
		var out_built_ink_share := -1.0
		if tile_class != DensityAudit.CLASS_WATER:
			geometry = geometry_by_coord.get(Vector2i(int(record.coord[0]),
				int(record.coord[1])), {})
			# THE CORRECTION: only DELIBERATE parks satisfy the >= 2 urban
			# floor. An undrawn hole is bare ground, not a civic green.
			# G7 REPAIR: and the articulation numbers are now READ by the gate.
			# In gauntlet6 `evaluate()` read no articulation number at all, so
			# shattering every building into four crumbs scored a perfect
			# articulation report AND passed.
			# G7b REPAIR (break F8). The built-ink share is the one density
			# number in this report whose DENOMINATOR the decorative fabric
			# does not author: `dry_buildable_area` comes from terrain, relief
			# and water. Every parcel-derived number is a sum over records the
			# audited code emits, and gauntlet7 moved the uncovered fraction
			# from 64% to 10% by not emitting the empty parcels and to 45.7% by
			# emitting the covered ones twice, on the same drawing. This one
			# cannot be moved that way, and it is what sees paving (break A3).
			var built_ink_share := (float(record.small_area) + float(
				record.large_area)) / maxf(1.0, float(geometry.get(
					"dry_buildable_area", 0.0)))
			out_built_ink_share = built_ink_share
			evaluation = DensityAudit.evaluate(tile_class,
				int(record.small_count), int(record.large_count),
				deliberate_count,
				float(geometry.get("dry_buildable_area", 0.0)),
				shortfall_records.has(tile_id),
				float(articulation.masses_per_visible_piece),
				float(articulation.median_visible_piece_area),
				int(articulation.piece_mass_count),
				float(articulation.largest_visible_piece_area),
				built_ink_share)
			audited += 1
			class_counts[tile_class] = int(class_counts.get(tile_class, 0)) + 1
			if bool(evaluation.passes):
				class_compliant[tile_class] = int(
					class_compliant.get(tile_class, 0)) + 1
			if bool(evaluation.physically_constrained):
				class_constrained[tile_class] = int(
					class_constrained.get(tile_class, 0)) + 1
		var rejected: Dictionary = {}
		if rural_tiles.has(tile_id):
			rejected["rural_growth"] = (rural_tiles[tile_id] as Dictionary).get(
				"rejected", {})
		if accommodation_tiles.has(tile_id):
			rejected["accommodation"] = (accommodation_tiles[tile_id] as \
				Dictionary).get("rejected", {})
		var out := {
			"tile_id": tile_id,
			"nickname": str(record.nickname),
			"coord": record.coord,
			"terrain_type": str(record.terrain_type),
			"class": tile_class,
			"urban_profile": str(record.urban_profile),
			"built_road_edge_count": int(record.built_road_edge_count),
			"small_count": int(record.small_count),
			"large_count": int(record.large_count),
			"small_area": float(record.small_area),
			"large_area": float(record.large_area),
			"park_count": green_spaces.size(),
			"park_area": green_area,
			# --- INSTRUMENT 2 ---
			"deliberate_park_count": deliberate_count,
			"deliberate_park_area": deliberate_area,
			"subfloor_green_count": recovered.size(),
			# EVERY green that is not a verified public green, holes and
			# wrapped greens alike. There is no third bucket to escape into.
			"unverified_green_count": hole_count + court_count,
			"unverified_green_area": hole_area + court_area,
			"park_hole_count": hole_count,
			"park_hole_area": hole_area,
			"park_hole_reasons": hole_reasons,
			"wrapped_green_count": court_count,
			"wrapped_green_area": court_area,
			"bare_parcel_count": (record.bare_parcels as Array).size(),
			"bare_parcel_area": bare_area,
			"bare_parcels": record.bare_parcels,
			"courtyard_count": int(record.courtyard_count),
			"courtyard_area": float(record.courtyard_area),
			"mass_kind_counts": record.mass_kind_counts,
			"hex_area": float(geometry.get("hex_area", 0.0)),
			"dry_land_area": float(geometry.get("dry_land_area", 0.0)),
			"open_land_area": float(geometry.get("open_land_area", 0.0)),
			"relief_retention_fallback": bool(geometry.get(
				"relief_retention_fallback", false)),
			"dry_buildable_area": float(geometry.get("dry_buildable_area", 0.0)),
			"water_margin_area": float(geometry.get("water_margin_area", 0.0)),
			"forest_disc_count": int(geometry.get("forest_disc_count", 0)),
			"gameplay_footprint_count": int(geometry.get(
				"gameplay_footprint_count", 0)),
			"relief_shoulder_count": int(geometry.get("relief_shoulder_count", 0)),
			"rejected_candidates": rejected,
			"built_ink_share": out_built_ink_share,
		}
		# --- INSTRUMENT 1, per tile, on a CONSISTENT denominator ---------
		out.merge(articulation)
		out.merge(evaluation)
		out_tiles.append(out)
		if tile_class != DensityAudit.CLASS_WATER and not bool(out.get("passes", true)):
			failures.append(out)
		if bool(out.get("gate_failure", false)):
			gate_failure_tiles += 1

	# --- per-settlement-component roll-up ---------------------------------
	# `tile_to_settlement` is the fabric's own component key per tile, covering
	# the morphology components, the two settlement plans and the Arin hero.
	# Tiles outside any component are grouped under "(unclustered)" so nothing
	# is silently dropped.
	var tile_to_component: Dictionary = fabric_metrics.get(
		"tile_to_settlement", {})
	var component_tiles: Dictionary = {}
	for tile_value in out_tiles:
		var tile: Dictionary = tile_value
		if str(tile["class"]) == DensityAudit.CLASS_WATER:
			continue
		var component := str(tile_to_component.get(str(tile.tile_id),
			"(unclustered)"))
		if not component_tiles.has(component):
			component_tiles[component] = []
		(component_tiles[component] as Array).append(tile)
	var component_records: Array = []
	var component_keys: Array = component_tiles.keys()
	component_keys.sort()
	for key_value in component_keys:
		var key := str(key_value)
		var members: Array = component_tiles[key]
		var ids: Array = []
		var small := 0
		var large := 0
		var deliberate := 0
		var holes := 0
		var bare := 0
		var built_area := 0.0
		for tile_value in members:
			var tile: Dictionary = tile_value
			ids.append(str(tile.tile_id))
			small += int(tile.small_count)
			large += int(tile.large_count)
			deliberate += int(tile.deliberate_park_count)
			holes += int(tile.park_hole_count)
			bare += int(tile.bare_parcel_count)
			built_area += float(tile.small_area) + float(tile.large_area)
		# Component articulation uses the SAME per-tile assignment as the tile
		# rows: the masses this component owns, and the distinct pieces they
		# fall into. A piece shared with a tile outside the component is
		# counted once and flagged, never charged whole.
		var component_masses: PackedInt32Array = PackedInt32Array()
		for record_value in tile_records:
			var record: Dictionary = record_value
			if ids.has(str(record.tile_id)):
				component_masses.append_array(record.mass_indices)
		var component_articulation: Dictionary = _tile_articulation(
			component_masses, mass_piece, pieces, piece_tiles)
		var out_component := {
			"component": key,
			"tile_count": members.size(),
			"tiles": ids,
			"small_count": small,
			"large_count": large,
			"built_area": built_area,
			"deliberate_park_count": deliberate,
			"park_hole_count": holes,
			"bare_parcel_count": bare,
		}
		out_component.merge(component_articulation)
		component_records.append(out_component)

	var map_articulation: Dictionary = DensityAudit.articulation_summary(pieces)
	# The worst silhouettes, named, so the next stage has targets rather than
	# an average. `tile` is the tile the silhouette is charged to.
	# A silhouette is named by EVERY tile whose masses are inside it, not by
	# one owner, because a cross-tile amoeba is a problem for all of them.
	var piece_owner: Dictionary = {}
	for piece_index in pieces.size():
		var names: Array = []
		for tile_index_value in (piece_tiles[piece_index] as Dictionary):
			names.append(str((tile_records[int(tile_index_value)] as \
				Dictionary).tile_id))
		names.sort()
		piece_owner[piece_index] = "+".join(names) if not names.is_empty() \
			else "(none)"
	var ranked_indices: Array = []
	for piece_index in pieces.size():
		ranked_indices.append(piece_index)
	var ranked_pieces: Array = pieces.duplicate()
	ranked_pieces.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.mass_count) != int(b.mass_count):
			return int(a.mass_count) > int(b.mass_count)
		return float(a.area) > float(b.area))
	ranked_indices.sort_custom(func(a: int, b: int) -> bool:
		var pa: Dictionary = pieces[a]
		var pb: Dictionary = pieces[b]
		if int(pa.mass_count) != int(pb.mass_count):
			return int(pa.mass_count) > int(pb.mass_count)
		return float(pa.silhouette_area) > float(pb.silhouette_area))
	var largest_pieces: Array = []
	for i in mini(15, ranked_indices.size()):
		var piece_index := int(ranked_indices[i])
		var piece: Dictionary = pieces[piece_index]
		largest_pieces.append({
			"tile": str(piece_owner.get(piece_index, "(none)")),
			"mass_count": int(piece.mass_count),
			"member_count": int(piece.member_count),
			"ink_area": float(piece.area),
			"silhouette_area": float(piece.silhouette_area),
			"center": [piece.silhouette_center.x, piece.silhouette_center.y],
		})
	# Per-tile / map-wide reconciliation. The per-tile piece sum EXCEEDS the map
	# total by exactly the number of tile memberships of cross-tile pieces; that
	# is stated here rather than left as a silent disagreement, which is what
	# 57 of 600 tiles were in gauntlet6.
	var per_tile_piece_sum := 0
	var per_tile_mass_sum := 0
	for tile_value in out_tiles:
		var tile: Dictionary = tile_value
		per_tile_piece_sum += int(tile.visible_piece_count)
		per_tile_mass_sum += int(tile.piece_mass_count)

	var park_totals := {"deliberate_park_count": 0, "deliberate_park_area": 0.0,
		"park_hole_count": 0, "park_hole_area": 0.0, "bare_parcel_count": 0,
		"bare_parcel_area": 0.0, "hole_reasons": {},
		"wrapped_green_count": 0, "wrapped_green_area": 0.0,
		"unverified_green_count": 0, "unverified_green_area": 0.0,
		"subfloor_green_count": 0,
		"urban_tiles_meeting_park_floor": 0,
		"urban_tiles_meeting_park_floor_uncorrected": 0}
	for tile_value in out_tiles:
		var tile: Dictionary = tile_value
		if str(tile["class"]) == DensityAudit.CLASS_WATER:
			continue
		park_totals.deliberate_park_count = int(
			park_totals.deliberate_park_count) + int(tile.deliberate_park_count)
		park_totals.deliberate_park_area = float(
			park_totals.deliberate_park_area) + float(tile.deliberate_park_area)
		park_totals.park_hole_count = int(park_totals.park_hole_count) + 			int(tile.park_hole_count)
		park_totals.park_hole_area = float(park_totals.park_hole_area) + 			float(tile.park_hole_area)
		park_totals.bare_parcel_count = int(park_totals.bare_parcel_count) + 			int(tile.bare_parcel_count)
		park_totals.bare_parcel_area = float(park_totals.bare_parcel_area) + 			float(tile.bare_parcel_area)
		park_totals.wrapped_green_count = int(
			park_totals.wrapped_green_count) + int(tile.wrapped_green_count)
		park_totals.wrapped_green_area = float(
			park_totals.wrapped_green_area) + float(tile.wrapped_green_area)
		park_totals.unverified_green_count = int(
			park_totals.unverified_green_count) + int(
			tile.unverified_green_count)
		park_totals.unverified_green_area = float(
			park_totals.unverified_green_area) + float(
			tile.unverified_green_area)
		park_totals.subfloor_green_count = int(
			park_totals.subfloor_green_count) + int(tile.subfloor_green_count)
		for reason_value in (tile.park_hole_reasons as Dictionary):
			var reason := str(reason_value)
			(park_totals.hole_reasons as Dictionary)[reason] = int(
				(park_totals.hole_reasons as Dictionary).get(reason, 0)) + int(
				(tile.park_hole_reasons as Dictionary)[reason])
		if str(tile["class"]) != DensityAudit.CLASS_URBAN:
			continue
		if int(tile.deliberate_park_count) >= 2:
			park_totals.urban_tiles_meeting_park_floor = int(
				park_totals.urban_tiles_meeting_park_floor) + 1
		if int(tile.park_count) >= 2:
			park_totals.urban_tiles_meeting_park_floor_uncorrected = int(
				park_totals.urban_tiles_meeting_park_floor_uncorrected) + 1

	areas.sort()
	failures.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if str(a["class"]) != str(b["class"]):
			return str(a["class"]) < str(b["class"])
		return str(a.tile_id) < str(b.tile_id))
	return {
		"threshold": {
			"large_mass_area": DensityAudit.LARGE_MASS_AREA,
			"min_counted_mass_area": DensityAudit.MIN_COUNTED_MASS_AREA,
			"min_counted_green_area": DensityAudit.MIN_COUNTED_GREEN_AREA,
			"measured_distribution": {
				"rendered_mass_count": areas.size(),
				"p25": _percentile(areas, 0.25),
				"median": _percentile(areas, 0.50),
				"p75": _percentile(areas, 0.75),
				"p90": _percentile(areas, 0.90),
				"large_share_pct": 100.0 * float(_count_at_or_above(areas,
					DensityAudit.LARGE_MASS_AREA)) / maxf(1.0, float(areas.size())),
			},
		},
		"classification": {
			"profiled_urban_tiles": profiles.size(),
			"profiled_but_not_urban_terrain": profiled_not_urban,
			"urban_terrain_but_not_profiled": urban_not_profiled,
		},
		"summary": {
			"audited_tiles": audited,
			"class_counts": class_counts,
			"class_compliant": class_compliant,
			"class_physically_constrained": class_constrained,
			"failing_tiles": failures.size(),
			"gate_failure_tiles": gate_failure_tiles,
			"documented_shortfall_tiles": shortfall_records.size(),
			"unassigned_masses": unassigned_masses,
			"unassigned_greens": unassigned_greens,
			"uncounted_mass_fragments": uncounted_masses,
			"rendered_masses": int(snapshot.get("masses", []).size()),
			"rendered_greens": int(snapshot.get("greens", []).size()),
		},
		"articulation": {
			"definition": "a visible piece is a connected component of the "
				+ "DRAWN ink under 'outlines dilated by %.1fu overlap'; "
				% DensityAudit.FUSION_DILATION
				+ "the dilation is half UrbanFabricVisuals."
				+ "HERO_ALLEY_HALF_WIDTH, so any gap narrower than an accepted "
				+ "3.8u alley reads as one silhouette. The clustered ink is "
				+ "every counted mass PLUS the sub-floor masses and the block "
				+ "SHADOW fills as non-counting bridges, so the shape measured "
				+ "is the shape the plate draws.",
			"gated_numbers": "the gate reads AREAS OF DRAWN SILHOUETTES only "
				+ "- largest_visible_piece_area against the %.1f u2 ceiling " % \
					DensityAudit.drawn_piece_ceiling_area()
				+ "(two block-scale masses drawn side by side with one accepted "
				+ "alley between them), median_visible_piece_area against the "
				+ "%.1f u2 floor, and built ink over dry buildable ground " % \
					DensityAudit.drawn_piece_floor_area()
				+ "against %.3f. NONE of them reads mass_count, so re-cutting " % \
					DensityAudit.PAVED_INK_SHARE_MAX
				+ "the same ink into a different number of entries moves the "
				+ "verdict by zero (break F1). masses_per_visible_piece and "
				+ "every count built on it are REPORTED and no longer gate.",
			"drawn_piece_ceiling_area": DensityAudit.drawn_piece_ceiling_area(),
			"drawn_piece_floor_area": DensityAudit.drawn_piece_floor_area(),
			"paved_ink_share_max": DensityAudit.PAVED_INK_SHARE_MAX,
			"fusion_dilation": DensityAudit.FUSION_DILATION,
			"counted_masses": counted_mass_count,
			"sub_floor_bridges": sub_floor_bridge_count,
			"shadow_bridges": shadow_bridge_count,
			"map": map_articulation,
			# THE GRADED RESPONSE. A perfect score at 1.0x that collapses at
			# 2.0x is a plate paved to the metric's limit, not an articulated
			# one, and `fusion_fragility` is exactly that collapse.
			"fusion_curve": fusion,
			"unassigned_pieces": unassigned_pieces,
			# PER-TILE RECONCILIATION, printed rather than left to be found.
			"cross_tile_piece_count": cross_tile_pieces,
			"per_tile_visible_piece_sum": per_tile_piece_sum,
			"per_tile_mass_sum": per_tile_mass_sum,
			"largest_pieces": largest_pieces,
		},
		"parks": {
			"definition": "a green is judged FROM GEOMETRY ALONE: "
				+ "`mass_band_enclosure` is the fraction of its own perimeter "
				+ "with a drawn mass within %.1fu outside it. " % \
					DensityAudit.PARK_FABRIC_BAND
				+ ">= %.2f is a PUBLIC GREEN and satisfies the urban floor; " % \
					DensityAudit.PARK_FABRIC_ENCLOSURE_MIN
				+ ">= %.2f is a WRAPPED GREEN and anything else is an " % \
					DensityAudit.COURT_FABRIC_ENCLOSURE_MIN
				+ "UNDRAWN HOLE; both are UNVERIFIED and both cost, so no edit "
				+ "moves a green into a bucket that is free (break F3). The "
				+ "probe answers only to COUNTED BUILDINGS - sub-floor ink "
				+ "cannot certify a green (break F2). No self-declared kind or "
				+ "role reaches the verdict. This measures SURROUNDEDNESS, "
				+ "which is not deliberateness: a real courtyard reads as "
				+ "unverified and a street-facing civic green reads as a hole. "
				+ "Both errors cost the candidate.",
			"fabric_band": DensityAudit.PARK_FABRIC_BAND,
			"public_green_min": DensityAudit.PARK_FABRIC_ENCLOSURE_MIN,
			"wrapped_green_min": DensityAudit.COURT_FABRIC_ENCLOSURE_MIN,
			"bare_parcel_max_cover": DensityAudit.BARE_PARCEL_MAX_COVER,
			"totals": park_totals,
			"green_shape_counts": green_shape_counts,
			"judged_built_parcels": judged_parcels,
			"unassigned_bare_parcels": unassigned_bare,
			# LABEL-FREE parcel numbers: a role rename moves a parcel between
			# the bare buckets and leaves these untouched, and an area-weighted
			# total cannot be shattered below a counting floor.
			"empty_parcel_count": empty_parcel_count,
			"empty_parcel_area": empty_parcel_area,
			"empty_parcel_roles": empty_parcel_roles,
			"uncovered_parcel_area": uncovered_parcel_area,
			"total_parcel_area": total_parcel_area,
			# THE REPAIRED MEASUREMENT and its negative control. The separation
			# between these two distributions is this instrument's acceptance
			# criterion: real greens must stand clear of the same outlines
			# dropped on arbitrary neighbouring ground.
			"fabric_enclosure_distribution": _distribution(
				fabric_enclosure_samples),
			"fabric_enclosure_negative_control": _distribution(
				fabric_control_samples),
			"fabric_band_curve": _band_curve(band_samples, band_control_samples),
			"control_placed": control_placed,
			"control_unplaceable": control_unplaceable,
			"fabric_at_or_above_public_floor": _count_at_or_above(
				_sorted(fabric_enclosure_samples),
				DensityAudit.PARK_FABRIC_ENCLOSURE_MIN),
			"fabric_control_at_or_above_public_floor": _count_at_or_above(
				_sorted(fabric_control_samples),
				DensityAudit.PARK_FABRIC_ENCLOSURE_MIN),
			# THE gauntlet6 NUMBERS, kept so the tautology stays on the record.
			# `enclosure_own_ink` is the shipped test and cannot fall below
			# 1.000 because the fabric rings every green it emits;
			# `enclosure_foreign_ink` removes exactly that ring.
			"enclosure_own_ink": _distribution(enclosure_samples),
			"enclosure_negative_control": _distribution(
				control_enclosure_samples),
			"enclosure_foreign_ink": _distribution(foreign_enclosure_samples),
			"enclosure_foreign_at_or_above_floor": _count_at_or_above(
				_sorted(foreign_enclosure_samples),
				DensityAudit.PARK_ENCLOSURE_MIN),
			"role_share_distribution": _distribution(role_share_samples),
		},
		"components": component_records,
		"tiles": out_tiles,
		"failures": failures,
	}


func _load_profiles() -> Dictionary:
	var file := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _built_road_edge_count(coord: Vector2i) -> int:
	var network := RoadNetwork.instance()
	var count := 0
	for edge_id_value in network.edges_on_tile(coord):
		var edge: Dictionary = network.edges.get(str(edge_id_value), {})
		if str(edge.get("state", "")) == RoadNetwork.STATE_BUILT:
			count += 1
	return count


## The tile that owns a polygon is the tile it shares the MOST area with, not
## the tile its centroid lands in — settlement geometry deliberately spills
## across hex sides, and G1.02 established intersection over centroid as the
## honest assignment. Ties break on tile id, so the result is deterministic.
func _owning_tile(records: Array, poly: PackedVector2Array,
		center: Vector2) -> int:
	var best_index := -1
	var best_area := 0.0
	var best_id := ""
	var poly_bb := _bbox(poly)
	for i in records.size():
		var record: Dictionary = records[i]
		var tile_center: Vector2 = record.center
		if absf(tile_center.x - center.x) > NEIGHBOUR_RADIUS or \
				absf(tile_center.y - center.y) > NEIGHBOUR_RADIUS:
			continue
		if not (record.bb as Rect2).intersects(poly_bb):
			continue
		var overlap := 0.0
		for piece_value in Geometry2D.intersect_polygons(poly, record.hex):
			overlap += absf(_poly_area(piece_value))
		if overlap <= 0.0:
			continue
		var tile_id := str(record.tile_id)
		if overlap > best_area or (is_equal_approx(overlap, best_area) and \
				tile_id < best_id):
			best_area = overlap
			best_index = i
			best_id = tile_id
	return best_index


## A FAIR NEGATIVE-CONTROL PLACEMENT: the same outline, translated onto the
## nearest UNBUILT ground on a fixed deterministic spiral. Returns an empty
## array when no placement within reach is clear, which is itself reported.
##
## The spiral is a constant of this file, not a random draw, so two runs produce
## the same control and the number can be compared between candidates.
func _clear_ground_control(poly: PackedVector2Array,
		fabric_grid: Dictionary) -> PackedVector2Array:
	for ring in 4:
		var radius := CONTROL_DISPLACEMENT.length() * float(ring + 1)
		for step in 8:
			var angle := TAU * float(step) / 8.0
			var offset := Vector2(cos(angle), sin(angle)) * radius
			var moved := PackedVector2Array()
			for point in poly:
				moved.append(point + offset)
			if DensityAudit.poly_is_on_clear_ground(moved, fabric_grid):
				return moved
	return PackedVector2Array()


## PER-TILE ARTICULATION, on a denominator that matches the numerator.
##
## `mass_indices` are the counted masses THIS tile owns, from exactly the same
## `_owning_tile` assignment that produced its small/large counts. The tile's
## visible pieces are the distinct pieces those masses fall into - no more, no
## fewer. A piece holding masses from two tiles is counted by both and reported
## as SHARED, and `largest_shared_silhouette_mass_count` names the full size of
## the worst silhouette this tile is part of, so a tile whose whole fabric sits
## inside a neighbour's amoeba can no longer read as having no problem.
func _tile_articulation(mass_indices: PackedInt32Array,
		mass_piece: PackedInt32Array, pieces: Array,
		piece_tiles: Array) -> Dictionary:
	var local_counts: Dictionary = {}
	for index_value in mass_indices:
		var piece_index := mass_piece[int(index_value)]
		if piece_index < 0:
			continue
		local_counts[piece_index] = int(local_counts.get(piece_index, 0)) + 1
	var piece_count := local_counts.size()
	var mass_count := 0
	var fused_pieces := 0
	var fused_masses := 0
	var shared_pieces := 0
	var largest_local := 0
	var largest_shared := 0
	var outline_sum := 0.0
	var silhouette_sum := 0.0
	var ink_total := 0.0
	var silhouette_total := 0.0
	var areas: Array[float] = []
	var ink_areas: Array[float] = []
	# G7b REPAIR (break F1). The label-free family, per tile: functions of the
	# silhouettes this tile's ink falls into and of nothing else. Re-cutting the
	# same ink into a different number of entries moves none of them.
	var ceiling := DensityAudit.drawn_piece_ceiling_area()
	var largest_piece_area := 0.0
	var slab_pieces := 0
	var slab_area := 0.0
	var single_mass_slabs := 0
	var keys: Array = local_counts.keys()
	keys.sort()
	for key_value in keys:
		var piece_index := int(key_value)
		var local := int(local_counts[piece_index])
		var piece: Dictionary = pieces[piece_index]
		var drawn_area := float(piece.silhouette_area)
		largest_piece_area = maxf(largest_piece_area, drawn_area)
		if drawn_area >= ceiling:
			slab_pieces += 1
			slab_area += drawn_area
			if int(piece.mass_count) == 1:
				single_mass_slabs += 1
		mass_count += local
		if local >= 2:
			fused_pieces += 1
			fused_masses += local
		largest_local = maxi(largest_local, local)
		largest_shared = maxi(largest_shared, int(piece.mass_count))
		if (piece_tiles[piece_index] as Dictionary).size() > 1:
			shared_pieces += 1
		outline_sum += float(piece.outline_perimeter_sum)
		silhouette_sum += float(piece.silhouette_perimeter)
		ink_total += float(piece.area)
		silhouette_total += float(piece.silhouette_area)
		areas.append(float(piece.silhouette_area))
		ink_areas.append(float(piece.area))
	areas.sort()
	ink_areas.sort()
	return {
		"visible_piece_count": piece_count,
		"piece_mass_count": mass_count,
		"masses_per_visible_piece": float(mass_count) / maxf(1.0,
			float(piece_count)),
		"excess_mass_count": maxi(0, mass_count - piece_count),
		"fused_piece_count": fused_pieces,
		"fused_mass_share_pct": 100.0 * float(fused_masses) / maxf(1.0,
			float(mass_count)),
		"largest_piece_mass_count": largest_local,
		"largest_shared_silhouette_mass_count": largest_shared,
		"shared_piece_count": shared_pieces,
		"mean_visible_piece_area": DensityAudit._mean_of(areas),
		"median_visible_piece_area": DensityAudit._median_of(areas),
		"mean_piece_ink_area": DensityAudit._mean_of(ink_areas),
		"median_piece_ink_area": DensityAudit._median_of(ink_areas),
		"ink_to_silhouette_ratio": ink_total / maxf(0.001, silhouette_total),
		"silhouette_perimeter_ratio": outline_sum / maxf(0.001, silhouette_sum),
		# --- THE GATED NUMBERS (break F1) -------------------------------
		"largest_visible_piece_area": largest_piece_area,
		"slab_piece_count": slab_pieces,
		"slab_silhouette_area": slab_area,
		"slab_area_share_pct": 100.0 * slab_area / maxf(0.001,
			silhouette_total),
		"single_mass_slab_piece_count": single_mass_slabs,
		"pieces_per_10k_silhouette": 10000.0 * float(piece_count) / maxf(0.001,
			silhouette_total),
	}


## Two green polygons that merge into one outline are ONE green space.
##
## G7 REPAIR (break P3 - MERGE LAUNDERING). gauntlet6 kept the area contributed
## by PARK-ROLE entries and passed the merged space when that share reached one
## half, so a single 20,000 u^2 hero park absorbed nineteen 1,000 u^2 residual
## pockets and they stopped being counted at all - not merely reclassified,
## deleted from both the park and the hole count. Each entry is now judged on
## its own outline BEFORE it is merged, and a merged space carries only
## `public_area`: the area of the entries that passed by themselves. A pocket
## that grazes a park contributes nothing to it and is still its own hole.
func _merge_green_spaces(entries: Array) -> Array:
	var merged: Array = []
	for entry_value in entries:
		var entry: Dictionary = entry_value
		var pending: PackedVector2Array = entry.poly
		var public_area := float(entry.area) if bool(entry.get("public",
			false)) else 0.0
		var total_area := float(entry.area)
		var i := 0
		while i < merged.size():
			var candidate: Dictionary = merged[i]
			var unions := Geometry2D.merge_polygons(candidate.poly, pending)
			if unions.size() == 1:
				pending = unions[0]
				public_area += float(candidate.public_area)
				total_area += float(candidate.area)
				merged.remove_at(i)
				i = 0
			else:
				i += 1
		merged.append({"poly": pending, "public_area": public_area,
			"area": total_area})
	var out: Array = []
	for merged_value in merged:
		var space: Dictionary = merged_value
		var poly: PackedVector2Array = space.poly
		if poly.size() >= 3 and absf(_poly_area(poly)) >= \
				DensityAudit.MIN_COUNTED_GREEN_AREA:
			out.append(space)
	return out


## ADVERSARIAL: enclosure measured against FOREIGN ink only.
##
## Identical to `DensityAudit.enclosure_fraction`, except that any inked segment
## which IS one of `poly`'s own edges (either orientation, matched on quantised
## endpoints) is skipped. The fabric emits a green and its ring from the same
## polygon, so those are the segments that make the shipped measurement
## tautological. What is left is the ink that OTHER geometry drew - the ink a
## human means when they say a court is enclosed.
func _foreign_enclosure(poly: PackedVector2Array, ink: Dictionary,
		tolerance: float = DensityAudit.INK_TOLERANCE,
		step: float = DensityAudit.OUTLINE_SAMPLE_STEP) -> float:
	if poly.size() < 3:
		return 0.0
	var own: Dictionary = {}
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		own[_segment_key(a, b)] = true
		own[_segment_key(b, a)] = true
	var grid: Dictionary = ink.get("grid", {})
	var cell := float(ink.get("cell", 32.0))
	var segments: PackedVector2Array = ink.get("segments", PackedVector2Array())
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
			if _point_on_foreign_ink(point, grid, cell, segments, tolerance,
					own):
				covered += weight
	if total <= 0.0:
		return 0.0
	return covered / total


func _segment_key(a: Vector2, b: Vector2) -> String:
	return "%.2f,%.2f|%.2f,%.2f" % [a.x, a.y, b.x, b.y]


func _point_on_foreign_ink(point: Vector2, grid: Dictionary, cell: float,
		segments: PackedVector2Array, tolerance: float,
		own: Dictionary) -> bool:
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
				if own.has(_segment_key(a, b)):
					continue
				if point.distance_to(
						Geometry2D.get_closest_point_to_segment(point, a, b)) \
						<= tolerance:
					return true
	return false


## Uniform bucket grid over a polygon array, for the parcel-coverage test.
func _build_poly_grid(polys: Array, cell: float = 128.0) -> Dictionary:
	var grid: Dictionary = {}
	for i in polys.size():
		var box := _bbox(polys[i])
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
	return {"grid": grid, "cell": cell}


## Fraction of a parcel covered by anything the fabric actually inked in.
## Overlaps between two covering polygons are counted twice and the result is
## clamped to 1.0; that can only ever make a parcel look MORE covered, so it
## cannot manufacture a bare parcel that is not bare.
func _covered_fraction(poly: PackedVector2Array, area: float, polys: Array,
		grid_data: Dictionary) -> float:
	if area <= 0.0:
		return 1.0
	var grid: Dictionary = grid_data.grid
	var cell := float(grid_data.cell)
	var box := _bbox(poly)
	var seen: Dictionary = {}
	var covered := 0.0
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
				var other: PackedVector2Array = polys[index]
				if not _bbox(other).intersects(box):
					continue
				for piece_value in Geometry2D.intersect_polygons(poly, other):
					covered += absf(_poly_area(piece_value))
				if covered >= area:
					return 1.0
	return minf(1.0, covered / area)


## The graded band curve: at each band, the real distribution, the fair-control
## distribution, and how many of each clear the public floor.
func _band_curve(real_bands: Array, control_bands: Array) -> Array:
	var out: Array = []
	for i in DensityAudit.PARK_BAND_SCALES.size():
		var scale := DensityAudit.PARK_BAND_SCALES[i]
		var real_values: Array[float] = real_bands[i]
		var control_values: Array[float] = control_bands[i]
		out.append({
			"scale": scale,
			"band": DensityAudit.PARK_FABRIC_BAND * scale,
			"real": _distribution(real_values),
			"control": _distribution(control_values),
			"real_at_or_above_floor": _count_at_or_above(_sorted(real_values),
				DensityAudit.PARK_FABRIC_ENCLOSURE_MIN),
			"control_at_or_above_floor": _count_at_or_above(
				_sorted(control_values),
				DensityAudit.PARK_FABRIC_ENCLOSURE_MIN),
		})
	return out


## Percentile summary of a sample, for reporting a distribution rather than a
## single number the reader has to take on trust.
func _distribution(values: Array[float]) -> Dictionary:
	var sorted_values := values.duplicate()
	sorted_values.sort()
	var mean := 0.0
	for value in sorted_values:
		mean += value
	mean = mean / maxf(1.0, float(sorted_values.size()))
	return {
		"n": sorted_values.size(),
		"min": _percentile(sorted_values, 0.0),
		"p05": _percentile(sorted_values, 0.05),
		"median": _percentile(sorted_values, 0.5),
		"mean": mean,
		"max": _percentile(sorted_values, 1.0),
	}


func _sorted(values: Array[float]) -> Array[float]:
	var out := values.duplicate()
	out.sort()
	return out


func _percentile(sorted_values: Array[float], percentile: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var index := clampi(roundi(percentile * float(sorted_values.size() - 1)),
		0, sorted_values.size() - 1)
	return sorted_values[index]


func _count_at_or_above(sorted_values: Array[float], threshold: float) -> int:
	var count := 0
	for value in sorted_values:
		if value >= threshold:
			count += 1
	return count


func _poly_area(poly: PackedVector2Array) -> float:
	var total := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		total += a.x * b.y - b.x * a.y
	return absf(total) * 0.5


func _bbox(poly: PackedVector2Array) -> Rect2:
	if poly.is_empty():
		return Rect2()
	var mn := poly[0]
	var mx := poly[0]
	for point in poly:
		mn = mn.min(point)
		mx = mx.max(point)
	return Rect2(mn, mx - mn)


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("density_audit: cannot write '%s'" % path)
		return
	file.store_string(text)
	print("[DENSITY AUDIT] %s" % path)


func _render_text(report: Dictionary) -> String:
	var lines: Array[String] = []
	var threshold: Dictionary = report.threshold
	var distribution: Dictionary = threshold.measured_distribution
	var summary: Dictionary = report.summary
	lines.append("=== PER-TILE DECORATIVE DENSITY AUDIT ===")
	lines.append("addendum section 2 table, measured on the rendered mid-century fabric")
	lines.append("")
	lines.append("SMALL/LARGE THRESHOLD (frozen, absolute, map-wide)")
	lines.append("  large_mass_area          %.1f u^2" % float(threshold.large_mass_area))
	lines.append("  counted mass floor       %.1f u^2" % float(threshold.min_counted_mass_area))
	lines.append("  counted green floor      %.1f u^2" % float(threshold.min_counted_green_area))
	lines.append("  measured this run: n=%d  p25=%.0f  median=%.0f  p75=%.0f  p90=%.0f" % [
		int(distribution.rendered_mass_count), float(distribution.p25),
		float(distribution.median), float(distribution.p75), float(distribution.p90)])
	lines.append("  masses at or above the threshold: %.1f%%" % float(
		distribution.large_share_pct))
	lines.append("")
	lines.append("CLASSIFICATION")
	var classification: Dictionary = report.classification
	lines.append("  profiled urban tiles     %d" % int(classification.profiled_urban_tiles))
	lines.append("  profiled but not urban   %s" % str(classification.profiled_but_not_urban_terrain))
	lines.append("  urban but not profiled   %s" % str(classification.urban_terrain_but_not_profiled))
	lines.append("")
	lines.append("COMPLIANCE BY CLASS")
	lines.append("  %-10s %7s %10s %9s %12s" % ["class", "tiles", "compliant", "failing", "constrained"])
	var class_counts: Dictionary = summary.class_counts
	var class_keys: Array = class_counts.keys()
	class_keys.sort()
	for key_value in class_keys:
		var key := str(key_value)
		var total := int(class_counts[key])
		var ok := int((summary.class_compliant as Dictionary).get(key, 0))
		lines.append("  %-10s %7d %10d %9d %12d" % [key, total, ok, total - ok,
			int((summary.class_physically_constrained as Dictionary).get(key, 0))])
	lines.append("")
	lines.append("  audited tiles                %d" % int(summary.audited_tiles))
	lines.append("  failing tiles                %d" % int(summary.failing_tiles))
	lines.append("  UNDOCUMENTED misses (gate)   %d" % int(summary.gate_failure_tiles))
	lines.append("  documented shortfalls        %d" % int(summary.documented_shortfall_tiles))
	lines.append("  rendered masses / greens     %d / %d" % [
		int(summary.rendered_masses), int(summary.rendered_greens)])
	lines.append("  mass fragments below floor   %d" % int(summary.uncounted_mass_fragments))
	lines.append("  masses/greens off every tile %d / %d" % [
		int(summary.unassigned_masses), int(summary.unassigned_greens)])
	lines.append("")
	lines.append("ARTICULATION (instrument 1) - VISIBLE PIECES, NOT POLYGONS")
	var articulation: Dictionary = report.articulation
	var map_articulation: Dictionary = articulation.map
	lines.append("  %s" % str(articulation.definition))
	lines.append("")
	lines.append("  WHAT THE GATE READS (and it never reads mass_count):")
	lines.append("  %s" % str(articulation.gated_numbers))
	lines.append("    slab ceiling                %.1f u^2  (two block-scale masses + one alley)" % float(
		articulation.drawn_piece_ceiling_area))
	lines.append("    confetti floor              %.1f u^2  (one baseline small mass, drawn)" % float(
		articulation.drawn_piece_floor_area))
	lines.append("    largest drawn silhouette    %.0f u^2" % float(
		map_articulation.largest_visible_piece_area))
	lines.append("    SLAB pieces (>= ceiling)    %d   holding %.0f u^2 = %.1f%% of all drawn shape" % [
		int(map_articulation.slab_piece_count),
		float(map_articulation.slab_silhouette_area),
		float(map_articulation.slab_area_share_pct)])
	lines.append("    of those, holding ONE mass  %d   [the measured cost of not reading the partition:" % int(
		map_articulation.single_mass_slab_piece_count))
	lines.append("                                     a drawing cannot tell one big building from two")
	lines.append("                                     fused ordinary ones, so this gate charges both]")
	lines.append("    of those, bridge ink only   %d" % int(
		map_articulation.bridge_only_slab_piece_count))
	lines.append("    objects per 10,000 u^2 ink  %.3f   (slabs push it down, confetti up)" % float(
		map_articulation.pieces_per_10k_silhouette))
	lines.append("")
	lines.append("  drawn masses counted        %d" % int(map_articulation.mass_count))
	lines.append("  VISIBLE PIECES              %d" % int(map_articulation.visible_piece_count))
	lines.append("  masses per visible piece    %.3f   (1.000 = nothing fuses)" % float(
		map_articulation.masses_per_visible_piece))
	lines.append("  fused pieces (>=2 masses)   %d" % int(map_articulation.fused_piece_count))
	lines.append("  masses inside a fused piece %.1f%%" % float(map_articulation.fused_mass_share_pct))
	lines.append("  largest single silhouette   %d masses" % int(
		map_articulation.largest_piece_mass_count))
	lines.append("  mean visible piece area     %.0f u^2" % float(
		map_articulation.mean_visible_piece_area))
	lines.append("  median visible piece area   %.0f u^2" % float(
		map_articulation.median_visible_piece_area))
	lines.append("  silhouette perimeter ratio  %.3f   (1.000 = no shared boundary)" % float(
		map_articulation.silhouette_perimeter_ratio))
	lines.append("  excess masses (NOT nettable) %d  (masses that are not separately visible)" % int(
		map_articulation.excess_mass_count))
	lines.append("  pieces holding >=3 / >=5 / >=10 masses   %d / %d / %d" % [
		int(map_articulation.pieces_holding_3_or_more),
		int(map_articulation.pieces_holding_5_or_more),
		int(map_articulation.pieces_holding_10_or_more)])
	lines.append("  ink / silhouette area ratio %.3f   (>1.000 = masses drawn on top of each other)" % float(
		map_articulation.ink_to_silhouette_ratio))
	lines.append("  median piece INK area       %.0f u^2  (the gauntlet6 number: a SUM, double-counts overlap)" % float(
		map_articulation.median_piece_ink_area))
	lines.append("  bridge-only groups          %d   (shadow / sub-floor ink holding no counted mass)" % int(
		map_articulation.bridge_only_piece_count))
	lines.append("  clustered ink: %d counted masses + %d sub-floor + %d shadow fills" % [
		int(articulation.counted_masses), int(articulation.sub_floor_bridges),
		int(articulation.shadow_bridges)])
	lines.append("  pieces off every tile       %d" % int(articulation.unassigned_pieces))
	lines.append("  cross-tile silhouettes      %d   (counted by every tile inside them)" % int(
		articulation.cross_tile_piece_count))
	lines.append("  per-tile sums: masses %d (map %d)   pieces %d (map %d, + one per extra tile membership)" % [
		int(articulation.per_tile_mass_sum), int(map_articulation.mass_count),
		int(articulation.per_tile_visible_piece_sum),
		int(map_articulation.visible_piece_count)])
	var fusion: Dictionary = articulation.fusion_curve
	lines.append("  GRADED FUSION RESPONSE (the same ink asked at three dilations)")
	lines.append("    %-8s %-10s %10s %10s" % ["scale", "dilation", "pieces", "m/piece"])
	for point_value in (fusion.points as Array):
		var point: Dictionary = point_value
		lines.append("    %-8.2f %-10.2f %10d %10.3f" % [float(point.scale),
			float(point.dilation), int(point.visible_piece_count),
			float(point.masses_per_visible_piece)])
	lines.append("    fusion fragility          %.3f   (rise in m/piece from 0.5x to 2.0x;" % float(
		fusion.fusion_fragility))
	lines.append("                                       near 0 = separated by real streets,")
	lines.append("                                       large  = paved to the metric's limit)")
	lines.append("")
	lines.append("BUILT INK OVER GROUND THE FABRIC DOES NOT AUTHOR (breaks A3, F8)")
	lines.append("  Counted building ink over dry buildable area. The denominator is measured")
	lines.append("  from terrain, relief and water - not from any record the decorative fabric")
	lines.append("  emits - so suppressing or duplicating parcel records cannot move it, and a")
	lines.append("  plate paved to just outside the fusion limit shows up here as density.")
	var shares: Array[float] = []
	var paved_tiles: Array = []
	for tile_value in (report.tiles as Array):
		var tile: Dictionary = tile_value
		var share := float(tile.get("built_ink_share", -1.0))
		if share < 0.0:
			continue
		shares.append(share)
		if share >= DensityAudit.PAVED_INK_SHARE_MAX:
			paved_tiles.append("%s %.1f%%" % [str(tile.tile_id), 100.0 * share])
	var share_dist := _distribution(shares)
	lines.append("    n=%d  min=%.3f p05=%.3f median=%.3f mean=%.3f max=%.3f   cap %.3f" % [
		int(share_dist.n), float(share_dist.min), float(share_dist.p05),
		float(share_dist.median), float(share_dist.mean), float(share_dist.max),
		DensityAudit.PAVED_INK_SHARE_MAX])
	lines.append("    tiles at or over the cap  %d   %s" % [paved_tiles.size(),
		str(paved_tiles)])
	lines.append("")
	lines.append("PARKS vs HOLES (instrument 2)")
	var parks: Dictionary = report.parks
	var park_totals: Dictionary = parks.totals
	lines.append("  %s" % str(parks.definition))
	lines.append("  VERIFIED public greens      %d  (%.0f u^2)" % [
		int(park_totals.deliberate_park_count), float(park_totals.deliberate_park_area)])
	lines.append("  UNVERIFIED greens           %d  (%.0f u^2)  = holes + wrapped; there is no free bucket" % [
		int(park_totals.unverified_green_count),
		float(park_totals.unverified_green_area)])
	lines.append("    of those, UNDRAWN holes   %d  (%.0f u^2)  %s" % [
		int(park_totals.park_hole_count), float(park_totals.park_hole_area),
		str(park_totals.hole_reasons)])
	lines.append("    of those, WRAPPED greens  %d  (%.0f u^2)  closed in by fabric; NOT public ground," % [
		int(park_totals.wrapped_green_count),
		float(park_totals.wrapped_green_area)])
	lines.append("                                             and no longer exempt from the count")
	lines.append("  sub-floor greens recovered  %d  (shards merged back into judgeable shapes)" % int(
		park_totals.subfloor_green_count))
	lines.append("  greens by measured shape    %s" % str(parks.green_shape_counts))
	lines.append("  BARE built-role parcels     %d  (%.0f u^2) of %d judged   [role-gated]" % [
		int(park_totals.bare_parcel_count), float(park_totals.bare_parcel_area),
		int(parks.judged_built_parcels)])
	lines.append("  EMPTY parcels, any role     %d  (%.0f u^2)   [label-free: a rename cannot move this]" % [
		int(parks.empty_parcel_count), float(parks.empty_parcel_area)])
	lines.append("    by declared role          %s" % str(parks.empty_parcel_roles))
	lines.append("  UNCOVERED parcel area       %.0f u^2 of %.0f  [area-weighted, no counting floor]" % [
		float(parks.uncovered_parcel_area), float(parks.total_parcel_area)])
	lines.append("  urban tiles >= 2 parks      %d corrected / %d uncorrected" % [
		int(park_totals.urban_tiles_meeting_park_floor),
		int(park_totals.urban_tiles_meeting_park_floor_uncorrected)])
	lines.append("  bare parcels off every tile %d" % int(parks.unassigned_bare_parcels))
	var fabric_dist: Dictionary = parks.fabric_enclosure_distribution
	var fabric_control: Dictionary = parks.fabric_enclosure_negative_control
	lines.append("  THE MEASUREMENT: fraction of a green's own perimeter with a DRAWN MASS")
	lines.append("  within %.1fu outside it. The green contributes nothing to its own score." % float(
		parks.fabric_band))
	lines.append("    fabric enclosure  n=%d  min=%.3f p05=%.3f median=%.3f mean=%.3f max=%.3f" % [
		int(fabric_dist.n), float(fabric_dist.min), float(fabric_dist.p05),
		float(fabric_dist.median), float(fabric_dist.mean), float(fabric_dist.max)])
	lines.append("    NEGATIVE CONTROL  n=%d  min=%.3f p05=%.3f median=%.3f mean=%.3f max=%.3f" % [
		int(fabric_control.n), float(fabric_control.min), float(fabric_control.p05),
		float(fabric_control.median), float(fabric_control.mean),
		float(fabric_control.max)])
	lines.append("      (the same outlines walked out on a fixed spiral to the nearest")
	lines.append("       UNBUILT ground - an outline dropped inside a building would be")
	lines.append("       trivially surrounded by it and would prove nothing)")
	lines.append("  GRADED BAND CURVE - the same question at half, one, two and four")
	lines.append("  times the derived band, real greens against the fair control:")
	lines.append("    %-8s %-8s %9s %9s %9s %9s %14s" % ["scale", "band",
		"real_med", "real_mean", "ctl_med", "ctl_mean", "pass real/ctl"])
	for band_value in (parks.fabric_band_curve as Array):
		var band: Dictionary = band_value
		var real_d: Dictionary = band.real
		var ctl_d: Dictionary = band.control
		lines.append("    %-8.1f %-8.1f %9.3f %9.3f %9.3f %9.3f %7d /%6d" % [
			float(band.scale), float(band.band), float(real_d.median),
			float(real_d.mean), float(ctl_d.median), float(ctl_d.mean),
			int(band.real_at_or_above_floor),
			int(band.control_at_or_above_floor)])
	lines.append("    control placed on clear ground %d, unplaceable %d" % [
		int(parks.control_placed), int(parks.control_unplaceable)])
	lines.append("    at or above the %.2f public floor:  real %d of %d   control %d of %d" % [
		float(parks.public_green_min),
		int(parks.fabric_at_or_above_public_floor), int(fabric_dist.n),
		int(parks.fabric_control_at_or_above_public_floor), int(fabric_control.n)])
	var own_dist: Dictionary = parks.enclosure_own_ink
	var foreign_dist: Dictionary = parks.enclosure_foreign_ink
	var role_dist: Dictionary = parks.role_share_distribution
	lines.append("  THE gauntlet6 NUMBERS, kept so the tautology stays on the record:")
	lines.append("    own-ink enclosure n=%d  min=%.3f median=%.3f  <- cannot fall: the fabric" % [
		int(own_dist.n), float(own_dist.min), float(own_dist.median)])
	lines.append("                                                    rings every green it emits")
	lines.append("    foreign ink       n=%d  min=%.3f median=%.3f max=%.3f  (own ring removed)" % [
		int(foreign_dist.n), float(foreign_dist.min), float(foreign_dist.median),
		float(foreign_dist.max)])
	lines.append("    self-declared park role  n=%d  mean=%.3f" % [
		int(role_dist.n), float(role_dist.mean)])
	lines.append("")
	lines.append("WORST SILHOUETTES (most masses inside one visible piece)")
	lines.append("  %-12s %7s %12s %14s" % ["tile", "masses", "ink_area", "silhouette"])
	for piece_value in (report.articulation as Dictionary).largest_pieces:
		var piece: Dictionary = piece_value
		lines.append("  %-12s %7d %12.0f %14.0f" % [str(piece.tile),
			int(piece.mass_count), float(piece.ink_area),
			float(piece.silhouette_area)])
	lines.append("")
	lines.append("PER SETTLEMENT COMPONENT")
	lines.append("  %-34s %5s %6s %6s %7s %7s %9s %6s %6s" % [
		"component", "tiles", "masses", "pieces", "m/piece", "med_area",
		"perim_rat", "dpark", "hole"])
	for component_value in report.components:
		var component: Dictionary = component_value
		lines.append("  %-34s %5d %6d %6d %7.3f %7.0f %9.3f %6d %6d" % [
			str(component.component).substr(0, 34), int(component.tile_count),
			int(component.piece_mass_count), int(component.visible_piece_count),
			float(component.masses_per_visible_piece),
			float(component.median_visible_piece_area),
			float(component.silhouette_perimeter_ratio),
			int(component.deliberate_park_count), int(component.park_hole_count)])
	lines.append("")
	lines.append("FULL TILE TABLE")
	lines.append("  dpark = deliberate parks (the number the section-2 floor is judged on)")
	lines.append("  hole  = greens that are undrawn holes; bare = built-role parcels with nothing on them")
	lines.append("  %-12s %-26s %-9s %5s %5s %5s %5s %5s %6s %7s %10s  %s" % [
		"tile", "nickname", "class", "small", "large", "dpark",
		"hole", "bare", "pieces", "m/piece", "dry_area", "verdict"])
	for tile_value in report.tiles:
		var tile: Dictionary = tile_value
		if str(tile["class"]) == DensityAudit.CLASS_WATER:
			continue
		var verdict := "PASS"
		if not bool(tile.get("passes", true)):
			verdict = "FAIL %s" % str(tile.failures)
			if bool(tile.get("physically_constrained", false)):
				verdict += " [physically constrained]"
		lines.append("  %-12s %-26s %-9s %5d %5d %5d %5d %5d %6d %7.3f %10.0f  %s" % [
			str(tile.tile_id), str(tile.nickname).substr(0, 26), str(tile["class"]),
			int(tile.small_count), int(tile.large_count),
			int(tile.deliberate_park_count), int(tile.park_hole_count),
			int(tile.bare_parcel_count), int(tile.visible_piece_count),
			float(tile.masses_per_visible_piece),
			float(tile.dry_buildable_area), verdict])
	lines.append("")
	lines.append("FAILURES (%d)" % int(summary.failing_tiles))
	for tile_value in report.failures:
		var tile: Dictionary = tile_value
		var req: Dictionary = tile.requirements
		lines.append("  %-12s %-9s %-24s small=%d (min %d, max %d)  large=%d (min %d, max %d)  park=%d (min %d)  dry=%.0f/%.0f  %s%s" % [
			str(tile.tile_id), str(tile["class"]), str(tile.nickname).substr(0, 24),
			int(tile.small_count), int(req.small_min), int(req.small_max),
			int(tile.large_count), int(req.large_min), int(req.large_max),
			int(tile.deliberate_park_count), int(req.park_min),
			float(tile.dry_buildable_area), float(tile.required_dry_area),
			str(tile.failures),
			" [physically constrained]" if bool(tile.physically_constrained) else ""])
	lines.append("")
	return "\n".join(lines)


func _print_summary(report: Dictionary) -> void:
	var summary: Dictionary = report.summary
	print("\n=== DENSITY AUDIT ===")
	print("large-mass threshold: %.0f u^2 (frozen)" % DensityAudit.LARGE_MASS_AREA)
	print("audited tiles:     %d" % int(summary.audited_tiles))
	print("class counts:      %s" % str(summary.class_counts))
	print("class compliant:   %s" % str(summary.class_compliant))
	print("failing tiles:     %d" % int(summary.failing_tiles))
	print("undocumented:      %d" % int(summary.gate_failure_tiles))
	var map_articulation: Dictionary = (report.articulation as Dictionary).map
	print("visible pieces:    %d from %d masses (%.3f masses/piece)" % [
		int(map_articulation.visible_piece_count),
		int(map_articulation.mass_count),
		float(map_articulation.masses_per_visible_piece)])
	print("median piece area: %.0f u^2   perimeter ratio %.3f" % [
		float(map_articulation.median_visible_piece_area),
		float(map_articulation.silhouette_perimeter_ratio)])
	var park_totals: Dictionary = (report.parks as Dictionary).totals
	print("parks:             %d deliberate / %d holes / %d bare parcels" % [
		int(park_totals.deliberate_park_count), int(park_totals.park_hole_count),
		int(park_totals.bare_parcel_count)])
