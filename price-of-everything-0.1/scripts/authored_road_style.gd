extends RefCounted
## The curated look of hand-authored roads — one reviewable table for the three width
## classes (`docs/map-editor-plan.md` sections 2 and 10.1).
##
## THE MIDCENTURY ROAD LOOK IS THE SOURCE (owner ruling, 2026-08-16): a paper carriageway
## bed over a solid ink casing, with a seeded wobble on the drawn line. This file does not
## invent a second idiom — it reads its colours from `MapMidcenturyStyle` so a palette
## change flows straight through, and curates only what has to differ per class.
##
## WHAT IS CURATED, AND WHY:
##   * bed width — the ruled 18 / 12.6 / 6.3 world units.
##   * casing delta — how far the ink edge stands proud of the bed. Constant deltas would
##     make a minor road look like a hairline beside a major; these scale with the class.
##   * paper tone — majors take the warmer trunk paper, mids and minors the plain paper, so
##     hierarchy reads at a glance without any change of shape.
##   * ink weight — a major's edge is the firmest line on the plate; a minor's is quietest.
##   * wobble — SMALLER ROADS WOBBLE MORE. A major road reads as surveyed and engineered, a
##     lane as walked into place. This is the one deliberate departure from the single
##     map-wide wobble the procedural roads use, and it is the main thing to judge in the
##     P1 curation pass.
##
## Deliberately has NO `class_name` (the headless global-class-cache trap; see
## `scripts/mass_form_shapes.gd`). Reference it as
##     const AuthoredRoadStyle := preload("res://scripts/authored_road_style.gd")

const AuthoredMap := preload("res://scripts/authored_map.gd")
const MidcenturyStyle := preload("res://scripts/map_midcentury_style.gd")

## How far the casing stands proud of the bed, per class (total, so half each side).
## Midcentury uses +4.0 on its trunk and +2.2 on its local; these keep that feel across a
## wider span of widths.
const CASING_DELTA := {
	"major": 4.4,
	"mid": 3.4,
	"minor": 2.2,
}

## `[step, amplitude]` for the seeded wobble, matching `road_network_visuals._wobble_polyline`.
## Midcentury's single setting is [22.0, 1.1]; a major is straighter than that and a minor
## looser.
const WOBBLE := {
	"major": [26.0, 0.85],
	"mid": [22.0, 1.10],
	"minor": [17.0, 1.35],
}

## Ink alpha of the casing per class. Midcentury: 0.92 trunk, 0.76 local.
const CASING_ALPHA := {
	"major": 0.92,
	"mid": 0.78,
	"minor": 0.66,
}

## Simplification is NOT applied to authored strokes. The procedural path RDP-simplifies at
## eps 8 because its routed polylines carry a vertex every ~12-18 u from the A* grid; an
## authored curve is already economical, and simplifying it would flatten the very curves
## the designer drew.
const SIMPLIFY_EPS := 0.0

## World units between samples when tessellating an authored curve. Fine enough that a bend
## reads as a curve rather than a chain of chords at full zoom.
const CURVE_SAMPLE := 6.0


static func bed_width(stroke_class: String) -> float:
	return AuthoredMap.road_width(stroke_class)


static func casing_width(stroke_class: String) -> float:
	return bed_width(stroke_class) + float(CASING_DELTA.get(stroke_class, 3.4))


## The carriageway fill. Majors take the trunk paper so the hierarchy reads by tone as well
## as by width.
static func bed_color(stroke_class: String) -> Color:
	return MidcenturyStyle.ROAD_TRUNK if stroke_class == "major" else MidcenturyStyle.ROAD_LOCAL


static func casing_color(stroke_class: String) -> Color:
	var ink: Color = MidcenturyStyle.INK
	return Color(ink.r, ink.g, ink.b, float(CASING_ALPHA.get(stroke_class, 0.78)))


static func wobble(stroke_class: String) -> Array:
	return WOBBLE.get(stroke_class, WOBBLE["mid"])


## Draw order for a batch of strokes: every casing first, then every bed. Per-stroke
## casing-then-bed would let a later stroke's casing cut a dark seam across an earlier
## stroke's carriageway at every junction — the same two-pass rule the river layer needs
## for its bank casings.
static func class_order() -> Array:
	# Majors last so they read as continuous where a minor meets them.
	return ["minor", "mid", "major"]
