extends RefCounted
## Pure, deterministic polygon constructors for the decorative mass-form vocabulary
## (`docs/map-mass-form-vocabulary.md`, owner direction 2026-08-14).
##
## GEOMETRY ONLY. Nothing here touches the renderer, form selection, road topology or
## any gameplay state. `scripts/urban_fabric_visuals.gd` is expected to call
## [method build_form] once the wiring pass lands; until then this file is dead code
## exercised solely by the unit suite.
##
## Deliberately has NO `class_name`: a freshly declared global class is absent from the
## headless global-script-class cache until an `--import`, which fails the suite with
## "Identifier not declared". Reference it as
## `const MassFormShapes := preload("res://scripts/mass_form_shapes.gd")`.
##
## ---------------------------------------------------------------------------------
## COORDINATE FRAME (identical convention to `UrbanFabricVisuals._quad`)
## ---------------------------------------------------------------------------------
## Every constructor works in a *parcel-aligned local frame* `(u, v)`:
##
##   * `u` runs ALONG the road frontage, spanning `[-w/2, +w/2]`;
##   * `v` runs AWAY from the frontage into the parcel, spanning `[0, h]`;
##   * the frontage edge is therefore the segment `v == 0`.
##
## [method place] maps that frame onto the map with
## `p = origin + tangent * u + inward * v`, exactly the tangent/inward-normal pair
## `_hero_add_street_walls` already derives from the parcel's longest edge. Frontage
## orientation is thus taken from the parcel's real road frontage, as section 4 of the
## spec requires — it is never invented here.
##
## Local polygons are emitted with POSITIVE shoelace area in `(u, v)`, matching the
## winding `_quad` produces. [method place] re-normalises if the tangent/inward pair is
## orientation-reversing, so placed polygons keep that winding too.
##
## ---------------------------------------------------------------------------------
## SECTION 4 — PARAMETERISE, DO NOT STAMP
## ---------------------------------------------------------------------------------
## [method params] draws every per-instance proportion from `RoadHash` alone (no global
## `randi()`/`randf()`, no wall clock). Each form varies at minimum its overall aspect
## ratio, its limb/stroke/wall/notch thickness as a fraction of the mass, and — via the
## parcel frontage — which way it faces. Two instances in unrelated blocks draw
## different keys and are therefore not congruent.
##
## ---------------------------------------------------------------------------------
## SECTION 6 — GEOMETRIC SAFETY (the V3.04 lesson)
## ---------------------------------------------------------------------------------
## Safety is STRUCTURAL, not merely asserted in tests. [method build_form] validates
## every candidate polygon with [method is_simple] plus a sliver/limb/area screen, and
## descends [constant FALLBACK] on any failure — ultimately to `solid`, which returns
## the parcel unchanged and cannot fail. A constructor that cannot honour its own legal
## proportions returns an empty array rather than a sliver, a zero-area limb or a
## self-touching outline.

const RoadHashRef := preload("res://scripts/road_hash.gd")

## Frozen large/small split, `docs/map-density-audit-baseline.txt`. Mirrors
## `DensityAudit.LARGE_MASS_AREA`; duplicated as a plain constant so this module stays
## free of autoloads and global classes.
const LARGE_MASS_AREA := 1600.0

## No limb, wall, arm, stroke or pier may be thinner than this in world units.
const MIN_LIMB := 4.0
## No notch, slot or inter-bar gap may be narrower than this.
const MIN_GAP := 4.0
## No run, leg or side may be shorter than this.
const MIN_SPAN := 10.0
## An emitted polygon below this area is a fragment, not a mass.
const MIN_POLY_AREA := 40.0
## Vertices/edges closer than this are treated as coincident.
const EPS := 0.05
## Interior angles below this (degrees) are slivers and are rejected.
const MIN_INTERIOR_DEG := 14.0

const LARGE_FORMS: Array[String] = [
	"t_half", "t_full", "right_triangle", "hollow_triangle",
	"half_octagon", "h", "cross", "shallow_e",
]
const SMALL_FORMS: Array[String] = [
	"square", "rectangle", "kinked", "l", "h_small",
]
## Every form this module can construct, including the terminal `solid`.
const ALL_FORMS: Array[String] = [
	"t_half", "t_full", "right_triangle", "hollow_triangle",
	"half_octagon", "h", "cross", "shallow_e",
	"square", "rectangle", "kinked", "l", "h_small",
	"solid",
]

## The explicit, deterministic degradation ladder (spec section 6). Every chain
## terminates at `solid`, which returns the parcel unchanged and never fails.
##   t_full  -> t_half -> l -> rectangle -> solid
##   cross   -> h      -> l -> rectangle -> solid
##   hollow_triangle -> right_triangle -> rectangle -> solid
##   half_octagon / shallow_e / square / kinked -> rectangle -> solid
const FALLBACK := {
	"t_full": "t_half",
	"t_half": "l",
	"right_triangle": "rectangle",
	"hollow_triangle": "right_triangle",
	"half_octagon": "rectangle",
	"h": "l",
	"cross": "h",
	"shallow_e": "rectangle",
	"square": "rectangle",
	"rectangle": "solid",
	"kinked": "rectangle",
	"l": "rectangle",
	"h_small": "l",
	"solid": "",
}
## Guard against a malformed ladder ever looping.
const MAX_FALLBACK_STEPS := 8

# ==================================================================================
# Seeded parameter draw
# ==================================================================================

## Deterministic float in `[low, high]`, identical in form to `UrbanFabricVisuals._rr`.
static func rr(key: String, low: float, high: float) -> float:
	return lerpf(low, high, float(RoadHashRef.pick(key, 10001)) / 10000.0)

## Legal parameter ranges per form, as `{param: [low, high]}`. This IS the contract the
## adversarial test sweeps: every value in every box must produce a safe polygon or an
## honest empty result.
const PARAM_RANGES := {
	"t_half": {"span": [0.0, 1.0], "leg_frac": [0.22, 0.46]},
	"t_full": {"span": [0.0, 1.0], "leg_frac": [0.22, 0.46]},
	"right_triangle": {"span": [0.72, 1.0], "depth": [0.72, 1.0], "corner": [0.0, 1.0]},
	"hollow_triangle": {"span": [0.78, 1.0], "depth": [0.78, 1.0], "corner": [0.0, 1.0],
		"wall_frac": [0.30, 0.62]},
	"half_octagon": {"base": [0.80, 1.0], "depth": [0.78, 1.0], "chamfer": [0.18, 0.40],
		"shoulder": [0.54, 0.84]},
	"h": {"arm": [0.17, 0.30], "cross": [0.15, 0.32], "pos": [0.30, 0.62]},
	"h_small": {"arm": [0.28, 0.40], "cross": [0.28, 0.46], "pos": [0.26, 0.60]},
	"cross": {"barw": [0.22, 0.40], "bart": [0.22, 0.40], "ushift": [-0.10, 0.10],
		"vpos": [0.36, 0.64]},
	"shallow_e": {"w0": [0.30, 0.52], "w1": [0.30, 0.52], "w2": [0.30, 0.52],
		"d0": [0.16, 0.35], "d1": [0.16, 0.35], "d2": [0.16, 0.35],
		"j0": [-0.14, 0.14], "j1": [-0.14, 0.14], "j2": [-0.14, 0.14],
		"front": [0.0, 1.0]},
	"square": {"fill": [0.76, 1.0], "shift": [-1.0, 1.0]},
	"rectangle": {"wfill": [0.62, 1.0], "hfill": [0.55, 1.0], "shift": [-1.0, 1.0]},
	"kinked": {"a1": [-0.35, 0.35], "turn": [0.4538, 1.2915], "sign": [0.0, 1.0],
		"run1": [1.0, 1.55], "run2": [1.0, 1.55], "slim": [0.10, 0.24],
		"shift": [-1.0, 1.0]},
	"l": {"wfill": [0.72, 1.0], "hfill": [0.72, 1.0], "arm_v": [0.30, 0.56],
		"arm_u": [0.30, 0.56], "mirror": [0.0, 1.0]},
	"solid": {},
}

## The per-instance parameter draw. Salted by form so a fallback re-draws its own
## proportions rather than inheriting the abandoned form's.
static func params(form: String, key: String) -> Dictionary:
	var out: Dictionary = {}
	if not PARAM_RANGES.has(form):
		return out
	var ranges: Dictionary = PARAM_RANGES[form]
	for name_value in ranges.keys():
		var name := str(name_value)
		var span: Array = ranges[name]
		out[name] = rr("%s|mfs|%s|%s" % [key, form, name], float(span[0]), float(span[1]))
	return out

## Midpoint of every legal range — the canonical instance, used by tests.
static func params_mid(form: String) -> Dictionary:
	var out: Dictionary = {}
	if not PARAM_RANGES.has(form):
		return out
	var ranges: Dictionary = PARAM_RANGES[form]
	for name_value in ranges.keys():
		var span: Array = ranges[name_value]
		out[str(name_value)] = (float(span[0]) + float(span[1])) * 0.5
	return out

# ==================================================================================
# Public construction API
# ==================================================================================

## True when a mass of `area` sits at or above the frozen large threshold.
static func is_large(area: float) -> bool:
	return area >= LARGE_MASS_AREA

## Construct `form` in the local `(u, v)` frame for a `w` x `h` parcel box.
##
## Returns `{"polys": Array[PackedVector2Array], "meta": Dictionary}`. `polys` is EMPTY
## when the box cannot host the form at legal proportions — that is the honest
## infeasible answer, and [method build_form] turns it into a fallback. `meta` reports
## the derived dimensions so tests can cross-check the polygon against the intent
## rather than re-deriving it.
##
## `construct` is the single safety gate: it re-screens whatever the raw builder
## produced with [method is_safe] and returns EMPTY rather than anything unsafe. So a
## non-empty `polys` is a guarantee, not a hope.
static func construct(form: String, w: float, h: float, p: Dictionary) -> Dictionary:
	var built := _construct_raw(form, w, h, p)
	var polys: Array = built.get("polys", [])
	if polys.is_empty():
		return {"polys": [], "meta": {}}
	for poly_value in polys:
		if not is_safe(poly_value as PackedVector2Array):
			return {"polys": [], "meta": {}}
	return built

static func _construct_raw(form: String, w: float, h: float, p: Dictionary) -> Dictionary:
	match form:
		"t_half":
			return _t(w, h, p, 0.5)
		"t_full":
			return _t(w, h, p, 1.0)
		"right_triangle":
			return _right_triangle(w, h, p)
		"hollow_triangle":
			return _hollow_triangle(w, h, p)
		"half_octagon":
			return _half_octagon(w, h, p)
		"h", "h_small":
			return _h_bar(w, h, p)
		"cross":
			return _cross(w, h, p)
		"shallow_e":
			return _shallow_e(w, h, p)
		"square":
			return _square(w, h, p)
		"rectangle":
			return _rectangle(w, h, p)
		"kinked":
			return _kinked(w, h, p)
		"l":
			return _l(w, h, p)
		"solid":
			return _solid_box(w, h)
	return {"polys": [], "meta": {}}

## Full pipeline: derive the parcel frame from `frontage_index`, draw parameters, build,
## validate, and descend [constant FALLBACK] until something safe comes out.
##
## `parcel` is the (already inset) parcel polygon; `frontage_index` is the index of the
## edge that faces the road — the caller passes the same edge `_hero_longest_edge`
## already picks. `inset` shrinks the fitted box so a form built for the bounding box
## does not graze the parcel's own boundary.
##
## Returns:
##   `form`      the form actually emitted (may differ from the request);
##   `requested` the form asked for;
##   `steps`     how many rungs of the ladder were descended (0 = first choice held);
##   `polys`     Array[PackedVector2Array], always non-empty, always simple;
##   `meta`      the constructor's derived dimensions.
static func build_form(form: String, parcel: PackedVector2Array, frontage_index: int,
		key: String, inset: float = 1.5) -> Dictionary:
	var frame := frame_for(parcel, frontage_index, inset)
	var current := form
	var steps := 0
	while steps < MAX_FALLBACK_STEPS:
		if current == "solid" or not bool(frame.get("ok", false)):
			return {"form": "solid", "requested": form, "steps": steps,
				"polys": [ensure_positive(parcel)], "meta": {"fallback": true}}
		var built := construct(current, float(frame.width), float(frame.depth),
			params(current, key))
		var local: Array = built.get("polys", [])
		if not local.is_empty():
			var placed: Array = []
			var all_safe := true
			for poly_value in local:
				var placed_poly := place(poly_value as PackedVector2Array, frame)
				if not is_safe(placed_poly):
					all_safe = false
					break
				placed.append(placed_poly)
			if all_safe and not placed.is_empty():
				return {"form": current, "requested": form, "steps": steps,
					"polys": placed, "meta": built.get("meta", {})}
		current = str(FALLBACK.get(current, "solid"))
		steps += 1
	return {"form": "solid", "requested": form, "steps": steps,
		"polys": [ensure_positive(parcel)], "meta": {"fallback": true}}

# ==================================================================================
# Frame derivation and placement
# ==================================================================================

## Derive the parcel-aligned frame from the frontage edge, shrunk by `inset`.
static func frame_for(parcel: PackedVector2Array, frontage_index: int,
		inset: float = 1.5) -> Dictionary:
	var fail := {"ok": false, "width": 0.0, "depth": 0.0, "origin": Vector2.ZERO,
		"tangent": Vector2.RIGHT, "inward": Vector2.DOWN}
	var n := parcel.size()
	if n < 3:
		return fail
	var i := ((frontage_index % n) + n) % n
	var a := parcel[i]
	var b := parcel[(i + 1) % n]
	if a.distance_to(b) < EPS:
		return fail
	var tangent := (b - a).normalized()
	var inward := inward_normal(parcel, a, b)
	var u_lo := INF
	var u_hi := -INF
	var v_lo := INF
	var v_hi := -INF
	for point in parcel:
		var d := point - a
		var u := d.dot(tangent)
		var v := d.dot(inward)
		u_lo = minf(u_lo, u)
		u_hi = maxf(u_hi, u)
		v_lo = minf(v_lo, v)
		v_hi = maxf(v_hi, v)
	var width := (u_hi - u_lo) - inset * 2.0
	var depth := (v_hi - v_lo) - inset * 2.0
	if width < MIN_SPAN or depth < MIN_SPAN:
		return fail
	var origin := a + tangent * ((u_lo + u_hi) * 0.5) + inward * (v_lo + inset)
	return {"ok": true, "width": width, "depth": depth, "origin": origin,
		"tangent": tangent, "inward": inward}

## Inward normal of edge `a`->`b` of `poly`. Same test `UrbanFabricVisuals` uses.
static func inward_normal(poly: PackedVector2Array, a: Vector2, b: Vector2) -> Vector2:
	var tangent := (b - a).normalized()
	var normal := Vector2(-tangent.y, tangent.x)
	var midpoint := (a + b) * 0.5
	if Geometry2D.is_point_in_polygon(midpoint + normal * 4.0, poly):
		return normal
	return -normal

## Map a local `(u, v)` polygon onto the map through `frame`, preserving winding.
static func place(local: PackedVector2Array, frame: Dictionary) -> PackedVector2Array:
	var origin: Vector2 = frame.get("origin", Vector2.ZERO)
	var tangent: Vector2 = frame.get("tangent", Vector2.RIGHT)
	var inward: Vector2 = frame.get("inward", Vector2.DOWN)
	var out := PackedVector2Array()
	for point in local:
		out.append(origin + tangent * point.x + inward * point.y)
	# A tangent/inward pair with negative determinant reflects the frame and would
	# flip the winding the constructors guarantee. Restore it.
	if tangent.x * inward.y - tangent.y * inward.x < 0.0:
		out.reverse()
	return out

# ==================================================================================
# Safety predicates (spec section 6)
# ==================================================================================

static func bbox(poly: PackedVector2Array) -> Rect2:
	if poly.is_empty():
		return Rect2()
	var lo := poly[0]
	var hi := poly[0]
	for point in poly:
		lo = lo.min(point)
		hi = hi.max(point)
	return Rect2(lo, hi - lo)

static func signed_area(poly: PackedVector2Array) -> float:
	var twice := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		twice += a.x * b.y - b.x * a.y
	return twice * 0.5

static func area(poly: PackedVector2Array) -> float:
	return absf(signed_area(poly))

static func ensure_positive(poly: PackedVector2Array) -> PackedVector2Array:
	if signed_area(poly) < 0.0:
		var flipped := poly.duplicate()
		flipped.reverse()
		return flipped
	return poly

## Closed and non-self-intersecting: no zero-length edge, no vertex touching a
## non-incident edge, no crossing between non-adjacent edges.
static func is_simple(poly: PackedVector2Array, eps: float = EPS) -> bool:
	var n := poly.size()
	if n < 3:
		return false
	for i in n:
		if not is_finite(poly[i].x) or not is_finite(poly[i].y):
			return false
		if poly[i].distance_to(poly[(i + 1) % n]) < eps:
			return false
	for i in n:
		for j in n:
			# Skip the two edges incident on vertex i.
			if j == i or (j + 1) % n == i:
				continue
			if _point_segment_distance(poly[i], poly[j], poly[(j + 1) % n]) < eps:
				return false
	for i in n:
		for j in range(i + 1, n):
			if j == i or (j + 1) % n == i or (i + 1) % n == j:
				continue
			var hit = Geometry2D.segment_intersects_segment(
				poly[i], poly[(i + 1) % n], poly[j], poly[(j + 1) % n])
			if hit != null:
				return false
	return true

## Smallest interior angle in degrees. Slivers are the V3.04 failure mode.
static func min_interior_angle_deg(poly: PackedVector2Array) -> float:
	var n := poly.size()
	if n < 3:
		return 0.0
	var worst := 360.0
	for i in n:
		var prev := poly[(i - 1 + n) % n]
		var here := poly[i]
		var next := poly[(i + 1) % n]
		var d1 := (prev - here)
		var d2 := (next - here)
		if d1.length() < EPS or d2.length() < EPS:
			return 0.0
		var ang := rad_to_deg(absf(d1.angle_to(d2)))
		worst = minf(worst, ang)
	return worst

## The single gate every emitted polygon must clear before it is allowed out.
static func is_safe(poly: PackedVector2Array) -> bool:
	if poly.size() < 3:
		return false
	if area(poly) < MIN_POLY_AREA:
		return false
	if not is_simple(poly):
		return false
	if min_interior_angle_deg(poly) < MIN_INTERIOR_DEG:
		return false
	return true

## Reflex-vertex count — the structural limb signature the tests pin.
static func reflex_count(poly: PackedVector2Array) -> int:
	var n := poly.size()
	if n < 3:
		return 0
	var ccw := ensure_positive(poly)
	var count := 0
	for i in n:
		var prev := ccw[(i - 1 + n) % n]
		var here := ccw[i]
		var next := ccw[(i + 1) % n]
		var cross := (here - prev).cross(next - here)
		if cross < 0.0:
			count += 1
	return count

static func _point_segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	if ab.length_squared() <= 1e-9:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return point.distance_to(a + ab * t)

# ==================================================================================
# LARGE forms (spec section 2)
# ==================================================================================

## Forms 1 and 2 — T-half (`ratio` 0.5) and T-full (`ratio` 1.0).
##
## Stroke bar of length `L` on the frontage, thickness `t`; a perpendicular leg from the
## stroke's centre of length `ratio * L` and width `wl`. `L` is solved so the stroke
## keeps a legal share of the depth: `t = h - ratio * L` must land in [18%, 52%] of `h`,
## and `L` must still span 60-100% of the frontage. When those two windows do not
## overlap the box simply cannot host a T and the constructor says so.
static func _t(w: float, h: float, p: Dictionary, ratio: float) -> Dictionary:
	var empty := {"polys": [], "meta": {}}
	if w < MIN_SPAN or h < MIN_SPAN or ratio <= 0.0:
		return empty
	var lo := maxf(0.48 * h / ratio, 0.60 * w)
	var hi := minf(0.82 * h / ratio, w)
	if lo > hi:
		return empty
	var span := clampf(float(p.get("span", 0.5)), 0.0, 1.0)
	var length := lerpf(lo, hi, span)
	var leg_len := ratio * length
	var stroke_t := h - leg_len
	if stroke_t < MIN_LIMB or leg_len < MIN_SPAN or length < MIN_SPAN:
		return empty
	var leg_frac := clampf(float(p.get("leg_frac", 0.34)), 0.10, 0.55)
	var leg_w := clampf(length * leg_frac, MIN_LIMB, length * 0.55)
	if leg_w < MIN_LIMB or leg_w > length - MIN_LIMB * 2.0:
		return empty
	var hl := length * 0.5
	var hw := leg_w * 0.5
	var top := stroke_t + leg_len
	var poly := PackedVector2Array([
		Vector2(-hl, 0.0), Vector2(hl, 0.0), Vector2(hl, stroke_t),
		Vector2(hw, stroke_t), Vector2(hw, top), Vector2(-hw, top),
		Vector2(-hw, stroke_t), Vector2(-hl, stroke_t),
	])
	return {"polys": [poly], "meta": {
		"stroke_length": length, "stroke_thickness": stroke_t,
		"leg_length": leg_len, "leg_width": leg_w, "leg_ratio": ratio,
		"limbs": 2, "depth": top,
	}}

## Form 3 — right triangle. Both legs lie on the parcel axes; the hypotenuse closes it.
## `corner` picks which end of the frontage carries the right angle.
static func _right_triangle(w: float, h: float, p: Dictionary) -> Dictionary:
	var empty := {"polys": [], "meta": {}}
	var leg_u := w * clampf(float(p.get("span", 0.86)), 0.30, 1.0)
	var leg_v := h * clampf(float(p.get("depth", 0.86)), 0.30, 1.0)
	if leg_u < MIN_SPAN * 1.5 or leg_v < MIN_SPAN * 1.5:
		return empty
	var aspect := leg_u / leg_v
	if aspect < 0.34 or aspect > 2.90:
		return empty
	var hw := w * 0.5
	var right_side := float(p.get("corner", 0.0)) >= 0.5
	var poly: PackedVector2Array
	if right_side:
		poly = PackedVector2Array([
			Vector2(hw - leg_u, 0.0), Vector2(hw, 0.0), Vector2(hw, leg_v)])
	else:
		poly = PackedVector2Array([
			Vector2(-hw, 0.0), Vector2(-hw + leg_u, 0.0), Vector2(-hw, leg_v)])
	return {"polys": [poly], "meta": {
		"leg_u": leg_u, "leg_v": leg_v, "right_angle_at": 0 if not right_side else 1,
		"corner_right": right_side,
	}}

## Form 4 — hollow triangle: a larger right triangle carrying a similar triangular
## hollow of wall thickness `t`.
##
## The inner triangle is the outer scaled about its INCENTRE by `(r - t) / r`, which is
## exactly the uniform inward offset of every edge by `t` — so the wall thickness is
## constant on all three sides and the inner triangle is similar to the outer by
## construction, with no offset-and-clip serration.
##
## Emitted as the three wall bands rather than one keyhole polygon: a keyhole needs
## either a self-touching slit (banned by section 6) or hole support that
## `Geometry2D.triangulate_polygon` does not have. The three trapezoids tile the ring
## exactly, share their radial edges, and are each convex.
##
## The three split lines are the corner bisectors (the radials through the incentre), so
## a band's tip angle is exactly HALF the outer triangle's corner angle. A sharp outer
## triangle therefore yields sliver tips, which is why the outer aspect ratio is gated
## to [constant HOLLOW_ASPECT_MIN]..[constant HOLLOW_ASPECT_MAX] — tighter than the solid
## right triangle's. Outside that window the form honestly declines and the ladder drops
## it to a solid right triangle.
const HOLLOW_ASPECT_MIN := 0.55
const HOLLOW_ASPECT_MAX := 1.82

static func _hollow_triangle(w: float, h: float, p: Dictionary) -> Dictionary:
	var empty := {"polys": [], "meta": {}}
	var probe_u := w * clampf(float(p.get("span", 0.89)), 0.30, 1.0)
	var probe_v := h * clampf(float(p.get("depth", 0.89)), 0.30, 1.0)
	if probe_v < EPS:
		return empty
	var outer_aspect := probe_u / probe_v
	if outer_aspect < HOLLOW_ASPECT_MIN or outer_aspect > HOLLOW_ASPECT_MAX:
		return empty
	var outer_result := _right_triangle(w, h, p)
	var outer_polys: Array = outer_result.get("polys", [])
	if outer_polys.is_empty():
		return empty
	var outer: PackedVector2Array = outer_polys[0]
	var side_a := outer[1].distance_to(outer[2])
	var side_b := outer[2].distance_to(outer[0])
	var side_c := outer[0].distance_to(outer[1])
	var perimeter := side_a + side_b + side_c
	if perimeter < EPS:
		return empty
	var incentre := (outer[0] * side_a + outer[1] * side_b + outer[2] * side_c) / perimeter
	var inradius := 2.0 * area(outer) / perimeter
	if inradius < MIN_LIMB * 1.6:
		return empty
	var wall_frac := clampf(float(p.get("wall_frac", 0.44)), 0.20, 0.72)
	var wall := inradius * wall_frac
	if wall < MIN_LIMB:
		wall = MIN_LIMB
		wall_frac = wall / inradius
		if wall_frac > 0.72:
			return empty
	var scale := 1.0 - wall_frac
	if scale < 0.28:
		return empty
	var inner := PackedVector2Array()
	for point in outer:
		inner.append(incentre + (point - incentre) * scale)
	var bands: Array = []
	for i in 3:
		var j := (i + 1) % 3
		bands.append(ensure_positive(PackedVector2Array([
			outer[i], outer[j], inner[j], inner[i]])))
	return {"polys": bands, "meta": {
		"wall_thickness": wall, "wall_frac": wall_frac, "inner_scale": scale,
		"inradius": inradius, "incentre": incentre, "bands": 3,
		"outer": outer, "inner": inner,
	}}

## Form 5 — half-octagon: one long base on the frontage plus four shorter chamfered
## edges (the octagon bisected through its centre). Parameterised as a stretched
## canonical pentagon: `chamfer` is the horizontal inset of the shoulder vertices and
## `shoulder` the height they sit at, both as fractions. Convex for every
## `0 < chamfer < shoulder < 1`, which the clamps below guarantee.
static func _half_octagon(w: float, h: float, p: Dictionary) -> Dictionary:
	var empty := {"polys": [], "meta": {}}
	var base := w * clampf(float(p.get("base", 0.90)), 0.40, 1.0)
	var depth := h * clampf(float(p.get("depth", 0.88)), 0.40, 1.0)
	if base < MIN_SPAN * 1.5 or depth < MIN_SPAN * 1.2:
		return empty
	var chamfer := clampf(float(p.get("chamfer", 0.29)), 0.10, 0.45)
	var shoulder := clampf(float(p.get("shoulder", 0.71)), 0.20, 0.90)
	if shoulder < chamfer + 0.14:
		shoulder = chamfer + 0.14
	if shoulder >= 0.94:
		return empty
	var hb := base * 0.5
	# Chamfer and apex rise must both be visible, else it collapses to a triangle
	# or a rectangle and stops being a half-octagon.
	if chamfer * hb < 3.0 or (1.0 - shoulder) * depth < 3.0:
		return empty
	var poly := PackedVector2Array([
		Vector2(-hb, 0.0),
		Vector2(hb, 0.0),
		Vector2(hb * (1.0 - chamfer), depth * shoulder),
		Vector2(0.0, depth),
		Vector2(-hb * (1.0 - chamfer), depth * shoulder),
	])
	return {"polys": [poly], "meta": {
		"base": base, "depth": depth, "chamfer": chamfer, "shoulder": shoulder,
		"edges": 5, "chamfered_edges": 4,
	}}

## Forms 6 (large) and small-form 5 — H: two bars perpendicular to the frontage joined
## by a central crossbar. Identical constructor, different parameter bands; the small H
## is coarser-limbed (arm 28-40% vs 17-30% of the frontage), not a shrunk copy.
static func _h_bar(w: float, h: float, p: Dictionary) -> Dictionary:
	var empty := {"polys": [], "meta": {}}
	if w < MIN_SPAN * 1.5 or h < MIN_SPAN * 1.5:
		return empty
	var arm := w * clampf(float(p.get("arm", 0.24)), 0.10, 0.45)
	arm = minf(arm, (w - MIN_GAP * 1.5) * 0.5)
	if arm < MIN_LIMB:
		return empty
	var gap := w - arm * 2.0
	if gap < MIN_GAP * 1.5:
		return empty
	var cross_t := h * clampf(float(p.get("cross", 0.24)), 0.10, 0.50)
	cross_t = maxf(cross_t, MIN_LIMB)
	if h - cross_t < MIN_GAP * 2.0:
		return empty
	var pos := clampf(float(p.get("pos", 0.45)), 0.0, 1.0)
	var v0 := (h - cross_t) * pos
	v0 = clampf(v0, MIN_GAP, h - cross_t - MIN_GAP)
	if v0 < MIN_GAP or h - (v0 + cross_t) < MIN_GAP:
		return empty
	var hw := w * 0.5
	var al := -hw + arm
	var ar := hw - arm
	var vt := v0 + cross_t
	var poly := PackedVector2Array([
		Vector2(-hw, 0.0), Vector2(al, 0.0), Vector2(al, v0), Vector2(ar, v0),
		Vector2(ar, 0.0), Vector2(hw, 0.0), Vector2(hw, h), Vector2(ar, h),
		Vector2(ar, vt), Vector2(al, vt), Vector2(al, h), Vector2(-hw, h),
	])
	return {"polys": [poly], "meta": {
		"arm_width": arm, "crossbar_thickness": cross_t, "crossbar_v0": v0,
		"gap": gap, "limbs": 3, "arm_frac": arm / w, "cross_frac": cross_t / h,
	}}

## Form 7 — cross: two bars crossing at the centre, four arms. The bar down the depth
## axis reaches both the frontage and the back; the transverse bar reaches both sides.
static func _cross(w: float, h: float, p: Dictionary) -> Dictionary:
	var empty := {"polys": [], "meta": {}}
	if w < MIN_SPAN * 2.0 or h < MIN_SPAN * 2.0:
		return empty
	var bar_u := w * clampf(float(p.get("barw", 0.30)), 0.12, 0.48)
	var bar_v := h * clampf(float(p.get("bart", 0.30)), 0.12, 0.48)
	if bar_u < MIN_LIMB or bar_v < MIN_LIMB:
		return empty
	var hw := w * 0.5
	var uc := w * clampf(float(p.get("ushift", 0.0)), -0.18, 0.18)
	var vc := h * clampf(float(p.get("vpos", 0.5)), 0.25, 0.75)
	var ul := uc - bar_u * 0.5
	var ur := uc + bar_u * 0.5
	var vb := vc - bar_v * 0.5
	var vt := vc + bar_v * 0.5
	if ul + hw < MIN_LIMB or hw - ur < MIN_LIMB:
		return empty
	if vb < MIN_LIMB or h - vt < MIN_LIMB:
		return empty
	var poly := PackedVector2Array([
		Vector2(ul, 0.0), Vector2(ur, 0.0), Vector2(ur, vb), Vector2(hw, vb),
		Vector2(hw, vt), Vector2(ur, vt), Vector2(ur, h), Vector2(ul, h),
		Vector2(ul, vt), Vector2(-hw, vt), Vector2(-hw, vb), Vector2(ul, vb),
	])
	return {"polys": [poly], "meta": {
		"bar_u": bar_u, "bar_v": bar_v, "centre_u": uc, "centre_v": vc,
		"arms": 4, "arm_left": ul + hw, "arm_right": hw - ur,
		"arm_front": vb, "arm_back": h - vt,
	}}

## Form 8 — shallow E: a rectangle with THREE notches in one long edge. Notch depth is
## capped at 35% of the mass depth by [constant PARAM_RANGES] and again here, so it can
## never read as a comb. Each notch draws its own width, depth and lateral jitter, so
## the three teeth of one instance are unequal and no two instances match.
##
## Notch i is confined to its own third of the usable frontage (half-width <= 0.26 of a
## cell, jitter <= 0.14 of a cell => reach 0.40 < 0.50), which guarantees the piers
## between notches without any clipping.
static func _shallow_e(w: float, h: float, p: Dictionary) -> Dictionary:
	var empty := {"polys": [], "meta": {}}
	if w < MIN_SPAN * 4.0 or h < MIN_SPAN * 1.2:
		return empty
	var margin := maxf(0.07 * w, 5.0)
	var cell := (w - margin * 2.0) / 3.0
	if cell < MIN_GAP * 3.0:
		return empty
	var hw := w * 0.5
	var notch_u: Array[float] = []
	var notch_hw: Array[float] = []
	var notch_d: Array[float] = []
	for i in 3:
		var width_frac := clampf(float(p.get("w%d" % i, 0.41)), 0.24, 0.52)
		var depth_frac := clampf(float(p.get("d%d" % i, 0.26)), 0.10, 0.35)
		var jitter := clampf(float(p.get("j%d" % i, 0.0)), -0.14, 0.14)
		var half := cell * width_frac * 0.5
		var depth := h * depth_frac
		if half * 2.0 < MIN_GAP or depth < MIN_LIMB or h - depth < MIN_LIMB * 1.5:
			return empty
		notch_hw.append(half)
		notch_d.append(depth)
		notch_u.append(-hw + margin + cell * (float(i) + 0.5) + cell * jitter)
	# Piers: ends and both inter-notch gaps.
	if (notch_u[0] - notch_hw[0]) - (-hw) < MIN_LIMB:
		return empty
	if hw - (notch_u[2] + notch_hw[2]) < MIN_LIMB:
		return empty
	for i in 2:
		if (notch_u[i + 1] - notch_hw[i + 1]) - (notch_u[i] + notch_hw[i]) < MIN_LIMB:
			return empty
	var poly := PackedVector2Array([
		Vector2(-hw, 0.0), Vector2(hw, 0.0), Vector2(hw, h)])
	for k in 3:
		var i := 2 - k  # traverse the back edge right-to-left
		var cu: float = notch_u[i]
		var nh: float = notch_hw[i]
		var nd: float = notch_d[i]
		poly.append(Vector2(cu + nh, h))
		poly.append(Vector2(cu + nh, h - nd))
		poly.append(Vector2(cu - nh, h - nd))
		poly.append(Vector2(cu - nh, h))
	poly.append(Vector2(-hw, h))
	var notch_front := float(p.get("front", 0.0)) >= 0.80
	if notch_front:
		# Reflect across mid-depth so the notches open onto the frontage instead.
		var mirrored := PackedVector2Array()
		for point in poly:
			mirrored.append(Vector2(point.x, h - point.y))
		mirrored.reverse()  # reflection reverses winding; restore it
		poly = mirrored
	return {"polys": [poly], "meta": {
		"notches": 3, "notch_depths": notch_d, "notch_halfwidths": notch_hw,
		"notch_centres": notch_u, "max_notch_depth_frac": (
			maxf(maxf(notch_d[0], notch_d[1]), notch_d[2]) / h),
		"notch_front": notch_front, "width": w, "depth": h,
	}}

# ==================================================================================
# SMALL forms (spec section 3)
# ==================================================================================

## Small form 1 — square. Exactly equal-sided; variation comes from size, lateral
## position and the parcel's own frontage orientation.
static func _square(w: float, h: float, p: Dictionary) -> Dictionary:
	var side := minf(w, h) * clampf(float(p.get("fill", 0.88)), 0.40, 1.0)
	if side < MIN_SPAN:
		return {"polys": [], "meta": {}}
	var slack := (w - side) * 0.5
	var uo := slack * clampf(float(p.get("shift", 0.0)), -1.0, 1.0)
	var hs := side * 0.5
	var poly := PackedVector2Array([
		Vector2(uo - hs, 0.0), Vector2(uo + hs, 0.0),
		Vector2(uo + hs, side), Vector2(uo - hs, side)])
	return {"polys": [poly], "meta": {"side": side, "aspect": 1.0, "offset_u": uo}}

## Small form 2 — rectangle, frontage-aligned, varied aspect (clamped to [0.42, 2.4]
## so it never degenerates into a sliver).
static func _rectangle(w: float, h: float, p: Dictionary) -> Dictionary:
	var rw := w * clampf(float(p.get("wfill", 0.80)), 0.30, 1.0)
	var rh := h * clampf(float(p.get("hfill", 0.78)), 0.30, 1.0)
	rh = clampf(rh, rw / 2.4, rw / 0.42)
	rh = minf(rh, h)
	if rw < MIN_SPAN or rh < MIN_SPAN:
		return {"polys": [], "meta": {}}
	var slack := (w - rw) * 0.5
	var uo := slack * clampf(float(p.get("shift", 0.0)), -1.0, 1.0)
	var hrw := rw * 0.5
	var poly := PackedVector2Array([
		Vector2(uo - hrw, 0.0), Vector2(uo + hrw, 0.0),
		Vector2(uo + hrw, rh), Vector2(uo - hrw, rh)])
	return {"polys": [poly], "meta": {"width": rw, "depth": rh, "aspect": rw / rh,
		"offset_u": uo}}

## Small form 3 — kinked slim rectangle: ONE bend, a dog-leg, never a curve.
##
## Built as a three-point polyline `A -> B -> C` stroked to half-width `r` with a mitred
## joint, giving exactly six vertices and exactly one reflex corner. The turn is clamped
## to [26 deg, 74 deg]: away from collinear (where the miter length diverges — the exact
## V3.04 degeneracy) and away from a fold-back. The half-width is drawn as a fraction of
## the SHORTER run and capped at 24%, so a run is always at least ~4x the half-width and
## the inner offset can never overshoot the joint.
static func _kinked(w: float, h: float, p: Dictionary) -> Dictionary:
	var empty := {"polys": [], "meta": {}}
	if w < MIN_SPAN * 1.5 or h < MIN_SPAN:
		return empty
	var a1 := clampf(float(p.get("a1", 0.0)), -0.40, 0.40)
	var turn := clampf(float(p.get("turn", 0.80)), 0.4538, 1.2915)  # 26 deg .. 74 deg
	var sign_up := 1.0 if float(p.get("sign", 0.0)) >= 0.5 else -1.0
	var run1 := clampf(float(p.get("run1", 1.25)), 0.80, 1.80) * 100.0
	var run2 := clampf(float(p.get("run2", 1.25)), 0.80, 1.80) * 100.0
	var slim := clampf(float(p.get("slim", 0.16)), 0.06, 0.24)
	var r := slim * minf(run1, run2)
	var d1 := Vector2.from_angle(a1)
	var d2 := Vector2.from_angle(a1 + sign_up * turn)
	var n1 := Vector2(-d1.y, d1.x)
	var n2 := Vector2(-d2.y, d2.x)
	var denom := 1.0 + n1.dot(n2)
	if denom < 0.35:
		return empty  # near-collinear: the mitre would diverge
	var miter := (n1 + n2) / denom
	var b := Vector2.ZERO
	var a := b - d1 * run1
	var c := b + d2 * run2
	var raw := PackedVector2Array([
		a + n1 * r, b + miter * r, c + n2 * r,
		c - n2 * r, b - miter * r, a - n1 * r])
	# Uniform fit into the parcel box preserves every angle and every ratio.
	var lo := raw[0]
	var hi := raw[0]
	for point in raw:
		lo = lo.min(point)
		hi = hi.max(point)
	var size := hi - lo
	var margin := maxf(2.0, 0.04 * minf(w, h))
	var avail_w := w - margin * 2.0
	var avail_h := h - margin * 2.0
	if avail_w <= 0.0 or avail_h <= 0.0 or size.x <= EPS or size.y <= EPS:
		return empty
	var scale := minf(avail_w / size.x, avail_h / size.y)
	if r * scale < 2.5 or minf(run1, run2) * scale < MIN_SPAN:
		return empty
	var centre := (lo + hi) * 0.5
	var slack_u := (w - size.x * scale) * 0.5 - margin
	var uo := maxf(0.0, slack_u) * clampf(float(p.get("shift", 0.0)), -1.0, 1.0)
	var target := Vector2(uo, h * 0.5)
	var poly := PackedVector2Array()
	for point in raw:
		poly.append(target + (point - centre) * scale)
	return {"polys": [ensure_positive(poly)], "meta": {
		"bends": 1, "half_width": r * scale, "run1": run1 * scale,
		"run2": run2 * scale, "turn_rad": turn, "turn_deg": rad_to_deg(turn),
		"scale": scale,
	}}

## Small form 4 — L. Frontage arm of thickness `arm_v`, return arm of thickness
## `arm_u`, `mirror` puts the return on the other side.
static func _l(w: float, h: float, p: Dictionary) -> Dictionary:
	var empty := {"polys": [], "meta": {}}
	var lw := w * clampf(float(p.get("wfill", 0.86)), 0.40, 1.0)
	var lh := h * clampf(float(p.get("hfill", 0.86)), 0.40, 1.0)
	if lw < MIN_SPAN * 1.5 or lh < MIN_SPAN * 1.5:
		return empty
	var arm_v := lh * clampf(float(p.get("arm_v", 0.43)), 0.20, 0.65)
	var arm_u := lw * clampf(float(p.get("arm_u", 0.43)), 0.20, 0.65)
	if arm_v < MIN_LIMB or arm_u < MIN_LIMB:
		return empty
	if lh - arm_v < MIN_LIMB or lw - arm_u < MIN_LIMB:
		return empty
	var hw := lw * 0.5
	var poly := PackedVector2Array([
		Vector2(-hw, 0.0), Vector2(hw, 0.0), Vector2(hw, arm_v),
		Vector2(-hw + arm_u, arm_v), Vector2(-hw + arm_u, lh), Vector2(-hw, lh)])
	var mirrored := float(p.get("mirror", 0.0)) >= 0.5
	if mirrored:
		var flip := PackedVector2Array()
		for point in poly:
			flip.append(Vector2(-point.x, point.y))
		flip.reverse()  # reflection reverses winding; restore it
		poly = flip
	return {"polys": [poly], "meta": {
		"width": lw, "depth": lh, "arm_v": arm_v, "arm_u": arm_u,
		"limbs": 2, "mirrored": mirrored,
	}}

## The terminal rung: the whole box. Used only when `build_form` is handed a bare box;
## `build_form` itself falls back to the parcel polygon, which is what the existing
## `solid` branch draws.
static func _solid_box(w: float, h: float) -> Dictionary:
	if w < MIN_SPAN or h < MIN_SPAN:
		return {"polys": [], "meta": {}}
	var hw := w * 0.5
	return {"polys": [PackedVector2Array([
		Vector2(-hw, 0.0), Vector2(hw, 0.0), Vector2(hw, h), Vector2(-hw, h)])],
		"meta": {"width": w, "depth": h}}
