extends Node
## ADVERSARIAL PROBE against the two gauntlet6 measurement instruments.
##   <godot> --headless --path . res://tools/instrument_attack.tscn --quit-after 4000
##
## Every case below is a CONSTRUCTION: geometry that makes the instrument's
## headline numbers move in the direction the author calls "better" while the
## drawn plate gets worse, or geometry the instrument is structurally unable to
## see. Nothing here is an opinion: each case prints the numbers it produced.
##
## gauntlet7/repair: every construction is KEPT VERBATIM and re-run against the
## repaired instruments, so this file is now a before/after ledger rather than a
## list of open wounds. Where a break is closed the probe prints the number that
## closes it; where a limit remains it says so.
##
## Output: /tmp/poe_instrument_attack.txt (and stdout).

const DA := preload("res://scripts/density_audit.gd")
const OUT_PATH := "/tmp/poe_instrument_attack.txt"

## The offset the fabric draws every block SHADOW at. Copied, not imported, so
## this probe states the number it is attacking.
const BLOCK_SHADOW_OFFSET := Vector2(2.2, 2.8)

var _lines: Array[String] = []


func _log(text: String) -> void:
	_lines.append(text)
	print(text)


func _rect(x: float, y: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x, y), Vector2(x + w, y),
		Vector2(x + w, y + h), Vector2(x, y + h)])


func _mass(x: float, y: float, w: float, h: float) -> Dictionary:
	return {"poly": _rect(x, y, w, h), "area": w * h}


func _summary(shapes: Array) -> Dictionary:
	return DA.articulation_summary(DA.visible_pieces(shapes))


func _fmt(summary: Dictionary) -> String:
	return ("masses %4d | pieces %4d | m/piece %.3f | EXCESS %4d | " +
		"fused pieces %3d | mean sil %8.1f | median sil %8.1f | " +
		"ink/sil %.3f | perim ratio %.4f") % [
		int(summary.mass_count), int(summary.visible_piece_count),
		float(summary.masses_per_visible_piece),
		int(summary.excess_mass_count),
		int(summary.fused_piece_count),
		float(summary.mean_visible_piece_area),
		float(summary.median_visible_piece_area),
		float(summary.ink_to_silhouette_ratio),
		float(summary.silhouette_perimeter_ratio)]


func _ready() -> void:
	_log("ADVERSARIAL PROBE - gauntlet6 instruments")
	_log("=========================================")
	_attack_a1_confetti()
	_attack_a2_netting()
	_attack_a3_minimum_alley()
	_attack_a4_shadow_bridge()
	_attack_a5_piece_area_is_not_an_area()
	_attack_a6_degenerate()
	_attack_p1_enclosure_tautology()
	_attack_p2_courtyard_relabel()
	_attack_p3_merge_laundering()
	_attack_p4_bare_parcel_paving()
	_attack_p5_sub_floor_hole()
	_attack_determinism()
	var file := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(_lines) + "\n")
		file.close()
	get_tree().quit(0)


# ---------------------------------------------------------------------------
# INSTRUMENT 1
# ---------------------------------------------------------------------------

## A1. SHATTERING. Take a plate of ordinary 40x40 masses on a 80u street grid
## and cut every one of them into four crumbs separated by 4.0u - one hair over
## the 3.8u the metric calls a visible alley. Same ink, same footprint, same
## built area. The plate now reads as a hatched grey field; the instrument
## reports a PERFECT articulation score.
func _attack_a1_confetti() -> void:
	_log("")
	_log("A1  SHATTERING (confetti) - same ink, 4x the crumbs, 4.0u gaps")
	var control: Array = []
	var shattered: Array = []
	for gx in 6:
		for gy in 6:
			var x := float(gx) * 80.0
			var y := float(gy) * 80.0
			control.append(_mass(x, y, 40.0, 40.0))
			# four quarters of the same 40x40 footprint, 4.0u apart
			for qx in 2:
				for qy in 2:
					shattered.append(_mass(x + float(qx) * 22.0,
						y + float(qy) * 22.0, 18.0, 18.0))
	var control_summary := _summary(control)
	var shattered_summary := _summary(shattered)
	_log("  control   " + _fmt(control_summary))
	_log("  shattered " + _fmt(shattered_summary))
	_log("  VERDICT: piece count %d -> %d, m/piece %.3f -> %.3f, fused %d -> %d, ratio %.4f -> %.4f" % [
		int(control_summary.visible_piece_count),
		int(shattered_summary.visible_piece_count),
		float(control_summary.masses_per_visible_piece),
		float(shattered_summary.masses_per_visible_piece),
		int(control_summary.fused_piece_count),
		int(shattered_summary.fused_piece_count),
		float(control_summary.silhouette_perimeter_ratio),
		float(shattered_summary.silhouette_perimeter_ratio)])
	var plenty := 1.0e9
	var shattered_gate: Dictionary = DA.evaluate("urban", 144, 0, 2, plenty,
		false, float(shattered_summary.masses_per_visible_piece),
		float(shattered_summary.median_visible_piece_area),
		int(shattered_summary.mass_count))
	var control_gate: Dictionary = DA.evaluate("urban", 0, 36, 2, plenty,
		false, float(control_summary.masses_per_visible_piece),
		float(control_summary.median_visible_piece_area),
		int(control_summary.mass_count))
	_log("  REPAIRED: evaluate() now READS the articulation numbers (it read none")
	_log("  at all in gauntlet6), and the confetti floor is derived from the")
	_log("  frozen small-mass median drawn the way the plate draws it: %.0f u^2." % [
		DA.drawn_piece_floor_area()])
	_log("    control   median silhouette %.0f  failures %s" % [
		float(control_summary.median_visible_piece_area),
		str(control_gate.failures)])
	_log("    shattered median silhouette %.0f  failures %s" % [
		float(shattered_summary.median_visible_piece_area),
		str(shattered_gate.failures)])


## A2. NETTING. The author's central claim is that fusing three masses into one
## silhouette "CANNOT be netted back by companions placed elsewhere". It can.
## Control: 20 abutting pairs + 20 singletons. Candidate: ten of the singletons
## collapse into ONE ten-mass amoeba, and 28 ordinary buildings appear on the
## other side of the map. Every headline number moves the good way.
func _attack_a2_netting() -> void:
	_log("")
	_log("A2  NETTING - a 10-mass amoeba paid for with 28 companions elsewhere")
	var control: Array = []
	var candidate: Array = []
	# 20 abutting pairs (1.0u apart => fused), shared by both sides
	for i in 20:
		var x := float(i) * 200.0
		control.append(_mass(x, 0.0, 40.0, 40.0))
		control.append(_mass(x + 41.0, 0.0, 40.0, 40.0))
		candidate.append(_mass(x, 0.0, 40.0, 40.0))
		candidate.append(_mass(x + 41.0, 0.0, 40.0, 40.0))
	# 20 separated singletons in the control
	for i in 20:
		var x := float(i) * 200.0
		control.append(_mass(x, 300.0, 40.0, 40.0))
	# candidate: 10 of them survive, 10 collapse into one abutting amoeba
	for i in 10:
		var x := float(i) * 200.0
		candidate.append(_mass(x, 300.0, 40.0, 40.0))
	for i in 10:
		candidate.append(_mass(2000.0 + float(i) * 41.0, 300.0, 40.0, 40.0))
	# ...and 28 perfectly ordinary, perfectly separated buildings elsewhere
	for i in 28:
		candidate.append(_mass(float(i) * 200.0, 800.0, 40.0, 80.0))
	var control_summary := _summary(control)
	var candidate_summary := _summary(candidate)
	_log("  control   " + _fmt(control_summary))
	_log("  candidate " + _fmt(candidate_summary))
	var better := 0
	if int(candidate_summary.visible_piece_count) > int(control_summary.visible_piece_count):
		better += 1
	if float(candidate_summary.masses_per_visible_piece) < float(control_summary.masses_per_visible_piece):
		better += 1
	if float(candidate_summary.fused_mass_share_pct) < float(control_summary.fused_mass_share_pct):
		better += 1
	if float(candidate_summary.silhouette_perimeter_ratio) < float(control_summary.silhouette_perimeter_ratio):
		better += 1
	if float(candidate_summary.median_visible_piece_area) > float(control_summary.median_visible_piece_area):
		better += 1
	_log("  gauntlet6 headline numbers that IMPROVED while a 10-mass amoeba was")
	_log("  created: %d of 5. Map-wide the offset needed was K > M(g-1)/(M-P) =" % better)
	_log("  22 crumbs anywhere per ten-mass amoeba at the real baseline.")
	_log("  REPAIRED - the absolute, monotone numbers:")
	_log("    excess masses (not separately visible)  %d -> %d" % [
		int(control_summary.excess_mass_count),
		int(candidate_summary.excess_mass_count)])
	_log("    pieces holding >=10 masses              %d -> %d" % [
		int(control_summary.pieces_holding_10_or_more),
		int(candidate_summary.pieces_holding_10_or_more)])
	var padded: Array = control.duplicate()
	for i in 40:
		padded.append(_mass(float(i) * 200.0, 1400.0, 40.0, 40.0))
	_log("    forty well-separated companions added to the CONTROL move excess")
	_log("    from %d to %d - by construction, adding an articulated mass adds" % [
		int(control_summary.excess_mass_count),
		int(_summary(padded).excess_mass_count)])
	_log("    one mass AND one piece, so nothing can be bought back.")


## A3. MINIMUM-ALLEY PAVING. The fusion test is a step function at 3.8u. A
## fabric laid out entirely on the minimum accepted gap scores a perfect 1.000
## masses-per-piece with zero fused pieces - and is a dark field with hairlines.
## This is the N2 move: satisfy the metric by paving to just inside its limit.
func _attack_a3_minimum_alley() -> void:
	_log("")
	_log("A3  MINIMUM-ALLEY PAVING - every gap at 3.81u, i.e. the legal minimum")
	var paved: Array = []
	for gx in 12:
		for gy in 12:
			paved.append(_mass(float(gx) * 43.81, float(gy) * 43.81, 40.0, 40.0))
	var paved_summary := _summary(paved)
	_log("  paved     " + _fmt(paved_summary))
	var ink := 144.0 * 1600.0
	var extent := 12.0 * 43.81 - 3.81
	_log("  ink covers %.1f%% of its own bounding box and scores m/piece %.3f," % [
		100.0 * ink / (extent * extent),
		float(paved_summary.masses_per_visible_piece)])
	_log("  0 fused pieces and perimeter ratio %.4f - a PERFECT articulation report." % [
		float(paved_summary.silhouette_perimeter_ratio)])
	_log("  Drop every gap by 0.02u and the same picture collapsed to:")
	var fused: Array = []
	for gx in 12:
		for gy in 12:
			fused.append(_mass(float(gx) * 43.79, float(gy) * 43.79, 40.0, 40.0))
	_log("  at 3.79u  " + _fmt(_summary(fused)))
	_log("  REPAIRED - the answer is a CURVE, not a point. Same ink, three")
	_log("  dilations (half an accepted alley, one, two):")
	var paved_curve: Dictionary = DA.fusion_curve(paved)
	for point_value in (paved_curve.points as Array):
		var point: Dictionary = point_value
		_log("    x%.2f (%.2fu)  pieces %4d  m/piece %8.3f" % [
			float(point.scale), float(point.dilation),
			int(point.visible_piece_count),
			float(point.masses_per_visible_piece)])
	_log("    fusion fragility %.3f" % float(paved_curve.fusion_fragility))
	var streets: Array = []
	for gx in 12:
		for gy in 12:
			streets.append(_mass(float(gx) * 60.0, float(gy) * 60.0, 40.0, 40.0))
	_log("  the same 144 masses on real 20u streets: fragility %.3f" % [
		float((DA.fusion_curve(streets) as Dictionary).fusion_fragility)])


## A4. SHADOW BRIDGE. `masses` is `block_entries` only. The fabric ALSO draws a
## SHADOW fill for every block, offset by BLOCK_SHADOW_OFFSET (2.2, 2.8), and
## that fill is never handed to the instrument. Two masses 4.0u apart in y are
## articulated to the metric and touching to the eye, because the upper one's
## shadow eats 2.8u of the 4.0u gap.
func _attack_a4_shadow_bridge() -> void:
	_log("")
	_log("A4  SHADOW BRIDGE - the drawn silhouette is mass UNION shadow; the")
	_log("    instrument only ever sees mass")
	var a := _rect(0.0, 0.0, 40.0, 40.0)
	var b := _rect(0.0, 44.0, 40.0, 40.0)
	var audited := _summary([{"poly": a, "area": 1600.0},
		{"poly": b, "area": 1600.0}])
	_log("  as audited (mass only)      " + _fmt(audited))
	var a_shadow := PackedVector2Array()
	for point in a:
		a_shadow.append(point + BLOCK_SHADOW_OFFSET)
	var drawn_a: Array = Geometry2D.merge_polygons(a, a_shadow)
	var b_shadow := PackedVector2Array()
	for point in b:
		b_shadow.append(point + BLOCK_SHADOW_OFFSET)
	var drawn_b: Array = Geometry2D.merge_polygons(b, b_shadow)
	var drawn_shapes: Array = []
	for poly_value in drawn_a:
		drawn_shapes.append({"poly": poly_value, "area": 1600.0})
	for poly_value in drawn_b:
		drawn_shapes.append({"poly": poly_value, "area": 1600.0})
	_log("  as drawn   (mass + shadow)  " + _fmt(_summary(drawn_shapes)))
	_log("  bare paper left between the two DRAWN fills: %.2fu (metric assumed 4.00u)" % [
		44.0 - 40.0 - BLOCK_SHADOW_OFFSET.y])
	_log("  REPAIRED: the fabric now hands its own sanitised shadow array to the")
	_log("  audit, and the audit clusters it as a non-counting BRIDGE - so the")
	_log("  shape measured is the shape the plate fills, not a model of it.")
	var with_bridges: Array = [{"poly": a, "area": 1600.0},
		{"poly": b, "area": 1600.0}]
	for poly_value in [a, b]:
		var poly: PackedVector2Array = poly_value
		var shadow := PackedVector2Array()
		for point in poly:
			shadow.append(point + BLOCK_SHADOW_OFFSET)
		with_bridges.append({"poly": shadow, "area": 1600.0, "counts": false})
	_log("  as clustered now    " + _fmt(_summary(with_bridges)))


## A5. `mean/median_visible_piece_area` is the SUM of member ink areas, not the
## area of the silhouette. Overlapping masses are counted twice. The baseline
## report already shows this: tile_23_9 reports 103,003 u^2 of ink inside a
## 64,323 u^2 silhouette. So the confetti guard can be satisfied by drawing the
## SAME building twice.
func _attack_a5_piece_area_is_not_an_area() -> void:
	_log("")
	_log("A5  PIECE AREA IS NOT AN AREA - stacking duplicates inflates it")
	var single := _summary([_mass(0.0, 0.0, 40.0, 40.0)])
	var stacked: Array = []
	for i in 4:
		stacked.append(_mass(0.0, 0.0, 40.0, 40.0))
	var stacked_summary := _summary(stacked)
	_log("  one mass          " + _fmt(single))
	_log("  four coincident   " + _fmt(stacked_summary))
	_log("  Same pixels. Reported piece area %.0f -> %.0f (x%.1f)." % [
		float(single.mean_visible_piece_area),
		float(stacked_summary.mean_visible_piece_area),
		float(stacked_summary.mean_visible_piece_area) /
			float(single.mean_visible_piece_area)])
	_log("  REPAIRED: mean/median_visible_piece_area IS the silhouette area now,")
	_log("  the sum-of-ink survives under an honest name, and their ratio is")
	_log("  reported so the overlap the old field hid is named:")
	_log("    silhouette %.0f | ink sum %.0f | ink/silhouette %.3f" % [
		float(stacked_summary.mean_visible_piece_area),
		float(stacked_summary.mean_piece_ink_area),
		float(stacked_summary.ink_to_silhouette_ratio)])


## A6. DEGENERATE INPUTS. Zero masses, one mass, exactly the large threshold,
## exactly the alley boundary, a park at exactly the counting floor.
func _attack_a6_degenerate() -> void:
	_log("")
	_log("A6  DEGENERATE INPUTS")
	_log("  empty:      pieces %d, summary m/piece %.3f (no divide-by-zero)" % [
		DA.visible_pieces([]).size(),
		float(DA.articulation_summary([]).masses_per_visible_piece)])
	var degenerate: Array = [
		{"poly": PackedVector2Array([Vector2(0, 0), Vector2(10, 0)]),
			"area": 0.0},
		{"poly": PackedVector2Array(), "area": 0.0}]
	var degenerate_summary := _summary(degenerate)
	_log("  2 sub-polygons (a line and an empty array): pieces %d, mass_count %d" % [
		int(degenerate_summary.visible_piece_count),
		int(degenerate_summary.mass_count)])
	_log("  -> a mass whose outline degenerates is still counted as its OWN")
	_log("     visible piece, because dilate_outline() returns an empty array and")
	_log("     the union-find still emits a singleton group. It draws nothing.")
	_log("  is_large at exactly 1600: %s ; at 1599.999: %s" % [
		str(DA.is_large(1600.0)), str(DA.is_large(1599.999))])
	_log("  counts_as_green at exactly 200: %s ; at 199.999: %s" % [
		str(DA.counts_as_green("park", 200.0)),
		str(DA.counts_as_green("park", 199.999))])
	_log("  parcel_is_bare at exactly 0.10 cover: %s (a 10%%-covered plot is NOT bare)" % [
		str(DA.parcel_is_bare("core_lot", 2000.0, 0.10))])
	_log("  green_verdict at the two repaired boundaries: %.2f -> '%s' ; %.2f -> '%s'" % [
		DA.PARK_FABRIC_ENCLOSURE_MIN,
		str(DA.green_verdict(DA.PARK_FABRIC_ENCLOSURE_MIN).shape),
		DA.COURT_FABRIC_ENCLOSURE_MIN,
		str(DA.green_verdict(DA.COURT_FABRIC_ENCLOSURE_MIN).shape)])


# ---------------------------------------------------------------------------
# INSTRUMENT 2
# ---------------------------------------------------------------------------

## P1. THE ENCLOSURE TEST IS TAUTOLOGICAL.
## Every one of the six park-creation sites in urban_fabric_visuals.gd appends
## the park polygon to a park entry and then calls _append_ring on THE SAME
## POLYGON, into _block_edges (or _parcel_edges). `snapshot.ink_segments` is
## _block_edges + _parcel_edges + _roof_edges. So enclosure_fraction() walks a
## green's perimeter against an ink set that CONTAINS THAT GREEN'S OWN RING.
## The measurement cannot return anything but 1.000, whatever is around it -
## which is exactly what the baseline reports: n=181, min 1.000, p05 1.000.
func _attack_p1_enclosure_tautology() -> void:
	_log("")
	_log("P1  ENCLOSURE WAS MEASURED AGAINST THE GREEN'S OWN RING - CLOSED")
	var pentagon := PackedVector2Array([Vector2(0, 0), Vector2(60, 8),
		Vector2(72, 60), Vector2(30, 88), Vector2(-8, 52)])
	var own_ring := PackedVector2Array()
	for i in pentagon.size():
		own_ring.append(pentagon[i])
		own_ring.append(pentagon[(i + 1) % pentagon.size()])
	var isolated := DA.enclosure_fraction(pentagon, DA.build_ink_grid(own_ring))
	_log("  The critic's pentagon, alone on blank paper, emitted the way EVERY")
	_log("  park site in the fabric emits one (park_entries.append + _append_ring")
	_log("  on the same poly), with zero other ink anywhere:")
	_log("    gauntlet6 ink enclosure = %.4f   <- cannot fall below 1.0" % isolated)
	var repaired := DA.mass_band_enclosure(pentagon, DA.build_mass_grid([]))
	var verdict: Dictionary = DA.green_verdict(repaired)
	_log("    REPAIRED fabric enclosure = %.4f   shape '%s'  deliberate %s" % [
		repaired, str(verdict.shape), str(verdict.deliberate)])
	_log("  The repaired measurement steps OUTWARD from the perimeter and asks")
	_log("  whether a drawn mass is there. The green contributes nothing to its")
	_log("  own score, so an isolated green is a HOLE.")
	# ...and it still scores a court that really is wrapped by fabric.
	var court := _rect(0, 0, 40, 40)
	var ring: Array = [_rect(-10, -22, 60, 20), _rect(-10, 42, 60, 20),
		_rect(-22, -10, 20, 60), _rect(42, -10, 20, 60)]
	_log("  the same test on a court actually wrapped by four masses: %.4f" % [
		DA.mass_band_enclosure(court, DA.build_mass_grid(ring))])


## P2. A hole relabelled `courtyard` disappears entirely. The audit's green loop
## does `if kind == "courtyard": continue` BEFORE any verdict is taken, so a
## courtyard-kind green is never judged, never a park and never a hole - and it
## still counts as coverage for the bare-parcel test (P4).
func _attack_p2_courtyard_relabel() -> void:
	_log("")
	_log("P2  KIND AND ROLE WERE SELF-DECLARED BY THE CODE BEING AUDITED - CLOSED")
	_log("  gauntlet6: `if kind == \"courtyard\": continue` fired BEFORE any")
	_log("  verdict (155 of 454 rendered greens, 27%% of the reported park area),")
	_log("  and role '' -> 'face_park' promoted a pocket to a deliberate park.")
	_log("  green_verdict() now takes ONE argument and it is a measurement:")
	var pocket := DA.green_verdict(0.2)
	var wrapped := DA.green_verdict(0.95)
	var public_green := DA.green_verdict(0.75)
	_log("    fabric 0.20 -> '%s'  0.75 -> '%s' (public %s)  0.95 -> '%s' (public %s)" % [
		str(pocket.shape), str(public_green.shape), str(public_green.public),
		str(wrapped.shape), str(wrapped.public)])
	_log("  There is no parameter a rename could reach. A courtyard is now a")
	_log("  green the fabric WRAPS, measured; it is still excluded from the")
	_log("  public floor, and it is still counted and reported.")


## P3. MERGE LAUNDERING. role_share is an AREA share over a MERGED outline and
## the bar is 0.5. One hero park can absorb an unlimited number of holes as long
## as it is bigger than all of them put together - and the merged space counts
## as ONE deliberate park, so the holes do not merely stop being holes, they
## stop existing.
func _attack_p3_merge_laundering() -> void:
	_log("")
	_log("P3  MERGE LAUNDERING AT THE 50%% BAR - CLOSED")
	_log("  gauntlet6 judged the MERGED outline and gated on an AREA share of")
	_log("  park-role entries, so a 20,000 u^2 hero park touching nineteen")
	_log("  1,000 u^2 pockets laundered all nineteen: role_share %.4f >= 0.5," % [
		20000.0 / (20000.0 + 19.0 * 1000.0)])
	_log("  one park, zero holes, and the pockets stopped existing.")
	_log("  REPAIRED: each entry is judged on ITS OWN outline before anything is")
	_log("  merged, and a merged space carries only `public_area` - the area of")
	_log("  the entries that passed alone. A pocket that grazes a park")
	_log("  contributes nothing to it and is still its own hole. Pinned in")
	_log("  tests/test_runner.gd as 'P3 CLOSED'.")


## P4. BARE-PARCEL PAVING - the N2 move, alive. `covered_fraction` counts ANY
## polygon in `masses` OR `greens`, overlaps double-counted and clamped to 1.
## Threshold is 0.10.
func _attack_p4_bare_parcel_paving() -> void:
	_log("")
	_log("P4  BARE PARCELS WERE CURED BY 11%% OF ANYTHING - PARTLY CLOSED")
	_log("  parcel_is_bare('face_built', 2000, 0.11) = %s   (unchanged)" % [
		str(DA.parcel_is_bare("face_built", 2000.0, 0.11))])
	_log("  parcel_is_bare('face_open',  2000, 0.00) = %s   (the rename escape)" % [
		str(DA.parcel_is_bare("face_open", 2000.0, 0.0))])
	_log("  REPAIRED, label-free:")
	_log("    parcel_is_empty(2000, 0.00) = %s   <- the rename cannot move this" % [
		str(DA.parcel_is_empty(2000.0, 0.0))])
	_log("    the coverage field is now DRAWN MASSES ONLY, so stamping a green")
	_log("    of any kind over an empty plot no longer cures it")
	_log("    the audit also reports UNCOVERED PARCEL AREA over every parcel with")
	_log("    no counting floor at all, so splitting one 2,995 u^2 plot into five")
	_log("    599 u^2 slivers leaves the reported number identical")
	_log("  STILL OPEN: the 10%% cover band itself. A single 15x15 shed on a")
	_log("  2,000 u^2 plot is 11.3%% cover and clears both counts. The area-")
	_log("  weighted total absorbs 89%% of that plot, but the COUNT does not.")


## P5. Sub-floor holes are invisible. MIN_COUNTED_GREEN_AREA is 200 and
## MIN_COUNTED_PARCEL_AREA is 600, so a shattered defect falls out of both.
func _attack_p5_sub_floor_hole() -> void:
	_log("")
	_log("P5  SHATTER THE DEFECT BELOW THE COUNTING FLOORS - PARTLY CLOSED")
	_log("  counts_as_green('green', 199) = %s ; counts_as_building('ordinary', 119) = %s" % [
		str(DA.counts_as_green("green", 199.0)),
		str(DA.counts_as_building("ordinary", 119.0))])
	_log("  The floors are unchanged - a sub-floor crumb is still not a building.")
	_log("  What is closed is the BRIDGE: sub-floor masses are now handed to the")
	_log("  clustering as non-counting shapes, so they fuse what they touch.")
	var bare: Array = [
		{"poly": _rect(0, 0, 40, 40), "area": 1600.0},
		{"poly": _rect(60, 0, 40, 40), "area": 1600.0}]
	_log("    two masses 20u apart, nothing between them:")
	_log("    " + _fmt(_summary(bare)))
	var bridged: Array = bare.duplicate()
	bridged.append({"poly": _rect(41, 15, 18, 6), "area": 108.0,
		"counts": false})
	_log("    the same two, bridged on the plate by a 108 u^2 crumb:")
	_log("    " + _fmt(_summary(bridged)))
	_log("  STILL OPEN: a green under 200 u^2 is not judged at all, so a defect")
	_log("  shattered into sub-floor GREENS is still invisible to instrument 2.")
	_log("  The area-weighted uncovered-parcel total is the only number that sees")
	_log("  that ground, and only where the ground is a drawn parcel.")


func _attack_determinism() -> void:
	_log("")
	_log("D   DETERMINISM (within-process)")
	var shapes: Array = []
	for i in 40:
		shapes.append(_mass(float(i % 7) * 41.0, float(i / 7) * 41.0, 40.0, 40.0))
	var first := _summary(shapes)
	var shuffled: Array = []
	for i in shapes.size():
		shuffled.append(shapes[shapes.size() - 1 - i])
	var second := _summary(shuffled)
	_log("  input order A " + _fmt(first))
	_log("  input order B " + _fmt(second))
	_log("  identical: %s" % [str(
		int(first.visible_piece_count) == int(second.visible_piece_count)
		and is_equal_approx(float(first.silhouette_perimeter_ratio),
			float(second.silhouette_perimeter_ratio)))])
	_log("  -> the clustering itself is order-stable, but note visible_pieces()")
	_log("     seeds union-find by ARRAY INDEX and the report's largest_pieces[]")
	_log("     leaderboard is ordered by the root index, so the order in which the")
	_log("     fabric happens to append masses is part of the reported output.")
