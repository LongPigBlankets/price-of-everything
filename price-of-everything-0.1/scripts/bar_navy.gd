extends RefCounted
## The container navy shared by the END TURN dock and the Top Bar.
##
## Both surfaces used to carry their own copy of these four corners (end_turn_dock's
## ETN_* set, the bar's flat #0c1c2e), so a tweak to one silently drifted from the
## other. Top Bar v3 makes the bar's ground the dock's gradient — stretched across
## the whole bar rather than the dock's small face — so the constants live here and
## both read them. See docs/top-bar-v3-spec.md §1.4.

const TL := Color(0.07, 0.30, 0.50)     # #124D80 — lit corner (top-left)
const TR := Color(0.0, 0.14, 0.27)      # #002445
const BL := Color(0.0, 0.11, 0.22)      # #001C38
const BR := Color(0.0, 0.045, 0.10)     # #000B1A — deepest corner (bottom-right)

## The four corners in draw_polygon winding order (TL, TR, BR, BL) for a rect.
static func corner_colors() -> PackedColorArray:
	return PackedColorArray([TL, TR, BR, BL])
