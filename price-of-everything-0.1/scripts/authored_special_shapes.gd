extends RefCounted
## The three PARAMETRIC primitives — U, ring and L — built from their side lengths.
##
## These are not part of `MassFormShapes`. That module fits a form into a parcel and owns a
## fallback ladder for when it cannot; these are laid down directly at sizes the designer
## types, and must come out exactly as asked or not at all. Mixing the two would mean a
## primitive silently degrading into a different shape mid-edit.
##
## EVERY PRIMITIVE PRODUCES AN EXPLICIT OUTLINE, which is then the truth for drawing, hit
## testing and corner editing. The parameters stay on the record so the shape can be rebuilt
## from them, but once a corner has been dragged the outline is what counts — a shape you can
## reshape by hand cannot also be defined by three numbers.
##
## Deliberately has NO `class_name` (the headless global-class-cache trap; see
## `scripts/mass_form_shapes.gd`).

## Parameter names per kind, in the order they are shown and stored. The counts are the
## owner's: three on the U, four on the ring, two on the L.
const PARAMETERS := {
	"u": ["left arm", "back", "right arm"],
	"ring": ["top", "right", "bottom", "left"],
	"l": ["long arm", "short arm"],
}

## Sensible starting lengths, world units.
const DEFAULTS := {
	"u": [70.0, 90.0, 70.0],
	"ring": [110.0, 90.0, 110.0, 90.0],
	"l": [100.0, 70.0],
}

## Wall thickness. One number rather than a parameter per limb: the owner asked for side
## LENGTHS, and a thickness per limb would double the controls for a distinction nobody
## draws by eye.
const THICKNESS := 24.0

## Nothing below this is a building; parameters clamp rather than refuse, so a slider cannot
## drive a shape into degeneracy.
const MIN_SIDE := 30.0
const MAX_SIDE := 400.0


static func kinds() -> Array:
	return ["u", "ring", "l"]


static func parameters_for(kind: String) -> Array:
	return PARAMETERS.get(kind, []) as Array


static func defaults_for(kind: String) -> Array:
	return (DEFAULTS.get(kind, []) as Array).duplicate()


static func clamp_side(value: float) -> float:
	return clampf(value, MIN_SIDE, MAX_SIDE)


## The outline for a kind at these side lengths, centred on the origin and unrotated. The
## caller places it; keeping construction origin-centred means a parameter change grows the
## shape about its middle rather than dragging one corner across the map.
static func build(kind: String, sides: Array) -> PackedVector2Array:
	var values: Array = []
	for value in sides:
		values.append(clamp_side(float(value)))
	match kind:
		"u":
			return _build_u(values)
		"ring":
			return _build_ring(values)
		"l":
			return _build_l(values)
	return PackedVector2Array()


## A U: two arms rising from a back bar. Parameters are the two arm lengths and the back's
## span, so the opening between the arms is whatever the back leaves.
static func _build_u(sides: Array) -> PackedVector2Array:
	var left: float = sides[0] if sides.size() > 0 else DEFAULTS["u"][0]
	var back: float = sides[1] if sides.size() > 1 else DEFAULTS["u"][1]
	var right: float = sides[2] if sides.size() > 2 else DEFAULTS["u"][2]
	var t := minf(THICKNESS, back * 0.4)
	var half := back * 0.5
	var tall := maxf(left, right)
	# Origin-centred: the back bar sits below, arms rise.
	var base := -tall * 0.5
	return PackedVector2Array([
		Vector2(-half, base),
		Vector2(half, base),
		Vector2(half, base + right),
		Vector2(half - t, base + right),
		Vector2(half - t, base + t),
		Vector2(-half + t, base + t),
		Vector2(-half + t, base + left),
		Vector2(-half, base + left),
	])


## A ring: an irregular quadrilateral with a courtyard inside it. The four parameters are the
## four side lengths, which is what makes it irregular — a regular ring would need only two.
##
## THIS RETURNS THE FOUR OUTER CORNERS, not the drawn band. The band needs a seam — out along
## the outside, in, back along the inside — and a seam means two pairs of coincident points.
## Those duplicates made corner dragging pick the wrong vertex: a grab landed on the seam copy
## rather than the corner, so the corner appeared not to move while its twin did. The quad is
## what the designer shapes; the band is derived at draw time by [method render_polygon].
static func _build_ring(sides: Array) -> PackedVector2Array:
	var top: float = sides[0] if sides.size() > 0 else DEFAULTS["ring"][0]
	var right: float = sides[1] if sides.size() > 1 else DEFAULTS["ring"][1]
	var bottom: float = sides[2] if sides.size() > 2 else DEFAULTS["ring"][2]
	var left: float = sides[3] if sides.size() > 3 else DEFAULTS["ring"][3]
	# The four sides describe a quad by their lengths: top and bottom set the two horizontal
	# spans, left and right the two vertical ones, and the corners fall where they meet.
	var half_top := top * 0.5
	var half_bottom := bottom * 0.5
	var half_left := left * 0.5
	var half_right := right * 0.5
	var outer := PackedVector2Array([
		Vector2(-half_top, -half_left),
		Vector2(half_top, -half_right),
		Vector2(half_bottom, half_right),
		Vector2(-half_bottom, half_left),
	])
	return outer


## An L: a long arm with a short one at its foot. Two parameters, two arms.
static func _build_l(sides: Array) -> PackedVector2Array:
	var long_arm: float = sides[0] if sides.size() > 0 else DEFAULTS["l"][0]
	var short_arm: float = sides[1] if sides.size() > 1 else DEFAULTS["l"][1]
	var t := minf(THICKNESS, minf(long_arm, short_arm) * 0.45)
	var x := -long_arm * 0.5
	var y := -short_arm * 0.5
	return PackedVector2Array([
		Vector2(x, y),
		Vector2(x + long_arm, y),
		Vector2(x + long_arm, y + t),
		Vector2(x + t, y + t),
		Vector2(x + t, y + short_arm),
		Vector2(x, y + short_arm),
	])


## Uniform inward offset. Returns empty when the shape would collapse.
static func _shrink(outline: PackedVector2Array, by: float) -> PackedVector2Array:
	var shrunk := Geometry2D.offset_polygon(outline, -by)
	if shrunk.is_empty():
		return PackedVector2Array()
	var best: PackedVector2Array = shrunk[0]
	for candidate in shrunk:
		if (candidate as PackedVector2Array).size() > best.size():
			best = candidate
	return best


## What to DRAW for a primitive. Everything except the ring draws its own outline; a ring
## becomes a band around its quad, so the courtyard reads as a hole. Kept out of the stored
## record so that what the designer edits stays four corners rather than ten.
static func render_polygon(special: Dictionary) -> PackedVector2Array:
	var outline := _outline_of(special)
	if str(special.get("kind", "")) != "ring" or outline.size() < 3:
		return outline
	var span := _longest_edge(outline)
	var inner := _shrink(outline, minf(THICKNESS, span * 0.3))
	if inner.size() < 3:
		return outline
	var band := PackedVector2Array()
	band.append_array(outline)
	band.append(outline[0])
	# Reversed so the inner loop winds against the outer one and reads as a hole.
	for i in range(inner.size() - 1, -1, -1):
		band.append(inner[i])
	band.append(inner[inner.size() - 1])
	return band


static func _longest_edge(outline: PackedVector2Array) -> float:
	var longest := 0.0
	for i in outline.size():
		longest = maxf(longest, outline[i].distance_to(outline[(i + 1) % outline.size()]))
	return longest


## Place an origin-centred outline on the map.
static func place(outline: PackedVector2Array, origin: Vector2, rotation: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in outline:
		out.append(origin + point.rotated(rotation))
	return out


## The record for a freshly laid primitive. `outline` is stored in WORLD units and is the
## drawing truth from here on; `sides` stays so the parameter controls can rebuild it.
static func record(id: String, kind: String, origin: Vector2, sides: Array = []) -> Dictionary:
	var lengths: Array = sides if not sides.is_empty() else defaults_for(kind)
	var outline := place(build(kind, lengths), origin, 0.0)
	if outline.size() < 3:
		return {}
	var points: Array = []
	for point in outline:
		points.append([point.x, point.y])
	return {"id": id, "kind": kind, "sides": lengths, "outline": points}


## Rebuild a record's outline from its parameters, about its own centre. Any corner edits are
## lost — which is the honest behaviour, and the status line says so: a shape defined by
## numbers and a shape reshaped by hand cannot both be true at once.
static func rebuild(special: Dictionary) -> void:
	var outline := _outline_of(special)
	if outline.is_empty():
		return
	var centre := Vector2.ZERO
	for point in outline:
		centre += point
	centre /= float(outline.size())
	var rebuilt := place(build(str(special.get("kind", "u")),
		special.get("sides", []) as Array), centre, 0.0)
	var points: Array = []
	for point in rebuilt:
		points.append([point.x, point.y])
	special["outline"] = points


static func _outline_of(special: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	for entry in (special.get("outline", []) as Array):
		var values: Array = entry as Array
		if values != null and values.size() >= 2:
			out.append(Vector2(float(values[0]), float(values[1])))
	return out
