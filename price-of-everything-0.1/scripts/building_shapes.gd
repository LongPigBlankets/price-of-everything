class_name BuildingShapes
extends RefCounted
## Footprint shapes for polygon buildings (polygon-buildings plan, phase 2).
## Each builder is parameterised to a target AREA (u²) and returns
##   {verts: PackedVector2Array (CCW, centred on the bbox centre), half: Vector2}
## so the layout can place the bbox centre at a point and (later) rotate it.
## Areas are exact for square/rectangle and held by construction for L/C.

const KINDS: Array[String] = ["square", "rectangle", "l_base", "l_length", "c"]
const MIN_AREA := 16.0
const RECT_ASPECTS: Array[float] = [1.4, 1.8, 2.4]

## Build a shape of `kind` at `area`; `seed_val` varies sub-choices (rect aspect).
static func make(kind: String, area: float, seed_val: int) -> Dictionary:
	var a := maxf(area, MIN_AREA)
	match kind:
		"rectangle":
			return _rect(a, RECT_ASPECTS[seed_val % RECT_ASPECTS.size()])
		"l_base":
			return _l(a, true)
		"l_length":
			return _l(a, false)
		"c":
			return _c(a)
		_:
			return _square(a)

static func _square(area: float) -> Dictionary:
	var h := sqrt(area) * 0.5
	return {
		"verts": PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)]),
		"half": Vector2(h, h),
	}

static func _rect(area: float, aspect: float) -> Dictionary:
	var w := sqrt(area * aspect)
	var hw := w * 0.5
	var hh := (area / w) * 0.5
	return {
		"verts": PackedVector2Array([Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh)]),
		"half": Vector2(hw, hh),
	}

## L-shape in a square LxL bbox: a full-width base bar (height bh) plus a left
## upright (width bw). thick_base → fat base bar; else → fat upright. Area held
## to `area` by solving L: area = L²·(bh_frac + bw_frac·(1−bh_frac)).
static func _l(area: float, thick_base: bool) -> Dictionary:
	var bh_frac := 0.58 if thick_base else 0.34
	var bw_frac := 0.40 if thick_base else 0.58
	var k := bh_frac + bw_frac * (1.0 - bh_frac)
	var size := sqrt(area / k)
	var bh := size * bh_frac
	var bw := size * bw_frac
	var verts := PackedVector2Array([
		Vector2(0, 0), Vector2(size, 0), Vector2(size, bh),
		Vector2(bw, bh), Vector2(bw, size), Vector2(0, size),
	])
	return _centred(verts, size, size)

## Squared-C: an LxL block with a rectangular notch (nw × nh) cut into the right
## edge. Area = L²·(1 − nw_frac·nh_frac).
static func _c(area: float) -> Dictionary:
	var nw_frac := 0.5
	var nh_frac := 0.4
	var size := sqrt(area / (1.0 - nw_frac * nh_frac))
	var nw := size * nw_frac
	var nh := size * nh_frac
	var y0 := (size - nh) * 0.5
	var y1 := y0 + nh
	var verts := PackedVector2Array([
		Vector2(0, 0), Vector2(size, 0), Vector2(size, y0), Vector2(size - nw, y0),
		Vector2(size - nw, y1), Vector2(size, y1), Vector2(size, size), Vector2(0, size),
	])
	return _centred(verts, size, size)

static func _centred(verts: PackedVector2Array, w: float, h: float) -> Dictionary:
	var c := Vector2(w * 0.5, h * 0.5)
	for i in verts.size():
		verts[i] -= c
	return {"verts": verts, "half": Vector2(w * 0.5, h * 0.5)}

## Area of a simple polygon (shoelace) — for tests/sanity.
static func polygon_area(verts: PackedVector2Array) -> float:
	var a := 0.0
	var n := verts.size()
	for i in n:
		var p := verts[i]
		var q := verts[(i + 1) % n]
		a += p.x * q.y - q.x * p.y
	return absf(a) * 0.5
