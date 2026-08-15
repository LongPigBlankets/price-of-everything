extends Node
## ADVERSARIAL PROBE against the two gauntlet6 measurement instruments.
##   <godot> --headless --path . res://tools/instrument_attack.tscn --quit-after 4000
##
## Every case below is a CONSTRUCTION: geometry that makes the instrument's
## headline numbers move in the direction the author calls "better" while the
## drawn plate gets worse, or geometry the instrument is structurally unable to
## see. Nothing here is an opinion: each case prints the numbers it produced.
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
	return ("masses %4d | pieces %4d | m/piece %.3f | fused pieces %3d | " +
		"fused mass %5.1f%% | mean area %8.1f | median area %8.1f | " +
		"perim ratio %.4f") % [
		int(summary.mass_count), int(summary.visible_piece_count),
		float(summary.masses_per_visible_piece),
		int(summary.fused_piece_count), float(summary.fused_mass_share_pct),
		float(summary.mean_visible_piece_area),
		float(summary.median_visible_piece_area),
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
	_log("  The only number that moves against the shatter is mean/median piece")
	_log("  area, and nothing in DensityAudit.evaluate() reads it. Meanwhile the")
	_log("  shatter ALSO turns 36 large masses into 144 small ones, which the")
	_log("  section-2 urban floor (small_min 10, large_min 3) rewards.")


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
	_log("  headline numbers that IMPROVED while a 10-mass amoeba was created: %d of 5" % better)
	_log("  largest silhouette mass count %d -> %d  (the ONLY number that fires)" % [
		int(control_summary.largest_piece_mass_count),
		int(candidate_summary.largest_piece_mass_count)])
	_log("  Map-wide arithmetic on the real baseline (M=2191, P=1259): fusing a")
	_log("  group of g masses is offset in m/piece by K > M(g-1)/(M-P) companions,")
	_log("  i.e. K > 21 for g = 10. 22 crumbs anywhere buy one ten-mass amoeba.")


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
	_log("  Drop every gap by 0.02u and the same picture collapses to:")
	var fused: Array = []
	for gx in 12:
		for gy in 12:
			fused.append(_mass(float(gx) * 43.79, float(gy) * 43.79, 40.0, 40.0))
	_log("  at 3.79u  " + _fmt(_summary(fused)))


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
	_log("  A candidate that shifts its street pitch from 3.7u to 4.0u converts")
	_log("  every fused pair on the map into two 'visible pieces' while leaving")
	_log("  1.2u of paper on the plate. Nothing in the instrument can tell.")


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
	_log("  The silhouette area of that piece is %.0f - the number the reader" % [
		float((DA.visible_pieces(stacked)[0] as Dictionary).silhouette_area)])
	_log("  thinks 'mean visible piece area' means is never reported map-wide.")


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
	_log("P1  ENCLOSURE IS MEASURED AGAINST THE GREEN'S OWN RING")
	# The critic's pentagon: a green with NOTHING drawn around it at all.
	var pentagon := PackedVector2Array([Vector2(0, 0), Vector2(60, 8),
		Vector2(72, 60), Vector2(30, 88), Vector2(-8, 52)])
	var own_ring := PackedVector2Array()
	for i in pentagon.size():
		own_ring.append(pentagon[i])
		own_ring.append(pentagon[(i + 1) % pentagon.size()])
	var isolated := DA.enclosure_fraction(pentagon,
		DA.build_ink_grid(own_ring))
	var verdict: Dictionary = DA.green_verdict(1.0, isolated)
	_log("  A green in the middle of blank paper, emitted the way EVERY park site")
	_log("  in the fabric emits one (park_entries.append + _append_ring on the")
	_log("  same poly), with zero other ink anywhere:")
	_log("    enclosure = %.4f   verdict deliberate = %s   reason '%s'" % [
		isolated, str(verdict.deliberate), str(verdict.reason)])
	_log("  The author's own unit test lays ink on two of five edges by hand and")
	_log("  gets 0.50. The FABRIC CANNOT PRODUCE THAT STATE: a green that reaches")
	_log("  _render_park_entries always brought its own complete ring with it.")
	_log("  park_hole_count == 0 in the baseline is therefore a STRUCTURAL")
	_log("  identity, not a measurement of the drawing.")
	# And the negative control does not detect it.
	var displaced := PackedVector2Array()
	for point in pentagon:
		displaced.append(point + Vector2(37.0, 29.0))
	_log("  negative control on the SAME isolated green: %.4f" % [
		DA.enclosure_fraction(displaced, DA.build_ink_grid(own_ring))])
	_log("  -> the control passes (low) for the same tautological reason the test")
	_log("     passes (high): it moved the polygon off its own ring. It proves the")
	_log("     ring is at the green. It says NOTHING about the surrounding fabric.")


## P2. A hole relabelled `courtyard` disappears entirely. The audit's green loop
## does `if kind == "courtyard": continue` BEFORE any verdict is taken, so a
## courtyard-kind green is never judged, never a park and never a hole - and it
## still counts as coverage for the bare-parcel test (P4).
func _attack_p2_courtyard_relabel() -> void:
	_log("")
	_log("P2  KIND AND ROLE ARE SELF-DECLARED BY THE CODE BEING AUDITED")
	_log("  green_verdict on a genuine residual pocket (no role, isolated):")
	var pocket := DA.green_verdict(0.0, 0.2)
	_log("    deliberate %s reason '%s'  -> counted as a HOLE" % [
		str(pocket.deliberate), str(pocket.reason)])
	_log("  The same pocket with one token changed at its creation site:")
	_log("    kind 'green' -> 'courtyard' : tools/density_audit.gd line ~160")
	_log("      `if kind == \"courtyard\": ... continue` fires BEFORE the verdict.")
	_log("      Result: not a park, not a hole, not counted anywhere.")
	_log("    role '' -> 'face_park'      : role_share 1.000, and P1 already")
	_log("      guarantees enclosure 1.000, so the pocket becomes a DELIBERATE")
	_log("      PARK and raises urban_tiles_meeting_park_floor.")
	_log("  Neither edit changes one pixel. is_park_role('face_park') = %s" % [
		str(DA.is_park_role("face_park"))])


## P3. MERGE LAUNDERING. role_share is an AREA share over a MERGED outline and
## the bar is 0.5. One hero park can absorb an unlimited number of holes as long
## as it is bigger than all of them put together - and the merged space counts
## as ONE deliberate park, so the holes do not merely stop being holes, they
## stop existing.
func _attack_p3_merge_laundering() -> void:
	_log("")
	_log("P3  MERGE LAUNDERING AT THE 50%% BAR")
	_log("  A 20,000 u^2 hero park touching 19 residual pockets of 1,000 u^2:")
	var role_share := 20000.0 / (20000.0 + 19.0 * 1000.0)
	var merged := DA.green_verdict(role_share, 1.0)
	_log("    role_share %.4f -> deliberate %s" % [role_share,
		str(merged.deliberate)])
	_log("    park_hole_count contribution: 0.  19 holes vanish, 1 park remains.")
	_log("  The bar is a knife edge on area, not on shape:")
	_log("    role_share 0.4999 -> deliberate %s ; 0.5000 -> deliberate %s" % [
		str(DA.green_verdict(0.4999, 1.0).deliberate),
		str(DA.green_verdict(0.5000, 1.0).deliberate)])
	_log("  'Touching' is Geometry2D.merge_polygons returning ONE polygon, so a")
	_log("  1u overlap is enough - a pocket only has to graze a park to be laundered.")


## P4. BARE-PARCEL PAVING - the N2 move, alive. `covered_fraction` counts ANY
## polygon in `masses` OR `greens`, overlaps double-counted and clamped to 1.
## Threshold is 0.10.
func _attack_p4_bare_parcel_paving() -> void:
	_log("")
	_log("P4  BARE PARCELS ARE CURED BY 11%% OF ANYTHING")
	_log("  parcel_is_bare('face_built', 2000, 0.09) = %s" % [
		str(DA.parcel_is_bare("face_built", 2000.0, 0.09))])
	_log("  parcel_is_bare('face_built', 2000, 0.11) = %s" % [
		str(DA.parcel_is_bare("face_built", 2000.0, 0.11))])
	_log("  A single 15x15 shed on a 2,000 u^2 plot is 11.3%% cover: the plot stops")
	_log("  being bare and stays an empty rectangle with a shed in it.")
	_log("  Worse, the cover field includes GREENS of every kind, courtyards")
	_log("  included. Stamping a courtyard-kind green over the empty plot removes")
	_log("  the bare_parcel AND is skipped by the green verdict (see P2), so the")
	_log("  hole leaves no trace in either instrument.")
	_log("  Cheapest of all: parcel_is_bare only judges roles in BUILT_PARCEL_ROLES.")
	_log("  Renaming the role at the creation site from 'face_built' to 'face_open'")
	_log("  (already in VACANT_PARCEL_ROLES) makes the plot 'deliberately vacant':")
	_log("    parcel_is_bare('face_open', 2000, 0.0) = %s" % [
		str(DA.parcel_is_bare("face_open", 2000.0, 0.0))])


## P5. Sub-floor holes are invisible. MIN_COUNTED_GREEN_AREA is 200 and
## MIN_COUNTED_PARCEL_AREA is 600, so a shattered defect falls out of both.
func _attack_p5_sub_floor_hole() -> void:
	_log("")
	_log("P5  SHATTER THE DEFECT BELOW THE COUNTING FLOORS")
	_log("  counts_as_green('green', 199) = %s -> a 199 u^2 hole is not measured" % [
		str(DA.counts_as_green("green", 199.0))])
	_log("  MIN_COUNTED_PARCEL_AREA = %.0f -> five 599 u^2 built-role slivers" % [
		DA.MIN_COUNTED_PARCEL_AREA])
	_log("  carry the same undrawn ground as one 2,995 u^2 plot and are never judged:")
	_log("    parcel_is_bare('core_lot', 599, 0.0) = %s" % [
		str(DA.parcel_is_bare("core_lot", 599.0, 0.0))])
	_log("  MIN_COUNTED_MASS_AREA = %.0f -> masses below it are dropped from the" % [
		DA.MIN_COUNTED_MASS_AREA])
	_log("  articulation clustering ENTIRELY, so a chain of 119 u^2 crumbs can")
	_log("  visually bridge two masses that the instrument still calls two pieces.")
	var bridged: Array = [
		{"poly": _rect(0, 0, 40, 40), "area": 1600.0},
		{"poly": _rect(60, 0, 40, 40), "area": 1600.0}]
	_log("    two masses 20u apart, bridged on the plate by sub-floor crumbs:")
	_log("    " + _fmt(_summary(bridged)))


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
