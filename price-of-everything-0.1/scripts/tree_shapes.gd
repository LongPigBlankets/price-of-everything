class_name TreeShapes
extends RefCounted
## The map's three trees, in one place so the forest canopy, the roadside and
## riverside scatter, and the courtyards of the decorative courts all draw the
## SAME vocabulary.
##
##   SMALL  a hedgerow/garden tree — a lumpy disc, a short shadow
##   FIR    medium and spiky — a rosette of points, a middling shadow
##   LARGE  the specimen tree — a broad lumpy cloud roughly half the width of a
##          decorative court's courtyard, and a correspondingly long shadow
##
## Shadows follow the map's one light (NW), so every canopy offsets toward the
## SE exactly like a building prism does — the offset scales with the tree, which
## is what actually communicates size on a flat top-down plate.
##
## Geometry only: no colour decisions live here (callers read MapStyle), and no
## randf() — every wobble is seeded through RoadHash so a tree is identical on
## every load.

enum Kind { SMALL, FIR, LARGE }

const SMALL_R := 2.6
const FIR_R := 4.2
const LARGE_R := 6.0

## Shadow offsets, world units, SE. Deliberately more than proportional to the
## radius: a big tree should read as TALL, not merely wide.
const _SHADOW_OFF := {
	Kind.SMALL: Vector2(1.2, 1.5),
	Kind.FIR: Vector2(2.2, 2.8),
	Kind.LARGE: Vector2(3.6, 4.6),
}

static func radius(kind: int) -> float:
	match kind:
		Kind.SMALL:
			return SMALL_R
		Kind.FIR:
			return FIR_R
		_:
			return LARGE_R

static func shadow_offset(kind: int) -> Vector2:
	return _SHADOW_OFF.get(kind, _SHADOW_OFF[Kind.LARGE])

## Canopy outline centred on `centre`. `scale` lets a caller vary one tree
## without inventing a fourth kind (forests jitter their trees this way).
static func canopy(kind: int, centre: Vector2, seed_key: String, scale: float = 1.0) -> PackedVector2Array:
	var r := radius(kind) * scale
	match kind:
		Kind.FIR:
			return _spiky(centre, r, seed_key)
		Kind.SMALL:
			return _lumpy(centre, r, seed_key, 7, 0.16)
		_:
			return _lumpy(centre, r, seed_key, 11, 0.22)

## A broadleaf crown: a ring with seeded radial wobble, so no two read alike.
static func _lumpy(centre: Vector2, r: float, seed_key: String, points: int, jitter: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var phase := float(RoadHash.pick("tree|%s|ph" % seed_key, 628)) / 100.0
	for i in points:
		var a := phase + TAU * float(i) / float(points)
		var j := 1.0 - jitter + float(RoadHash.pick("tree|%s|r%d" % [seed_key, i], 100)) / 100.0 * (jitter * 2.0)
		out.append(centre + Vector2(cos(a), sin(a)) * (r * j))
	return out

## A conifer from above: alternating long and short radii make a rosette of
## points. Spikier than the broadleaves by design — it is the silhouette, not
## the colour, that tells the two apart at map zoom.
static func _spiky(centre: Vector2, r: float, seed_key: String) -> PackedVector2Array:
	var spikes := 7 + RoadHash.pick("tree|%s|sp" % seed_key, 3)
	var out := PackedVector2Array()
	var phase := float(RoadHash.pick("tree|%s|ph" % seed_key, 628)) / 100.0
	for i in spikes * 2:
		var a := phase + TAU * float(i) / float(spikes * 2)
		var tip := i % 2 == 0
		var j := 1.0 - 0.08 + float(RoadHash.pick("tree|%s|s%d" % [seed_key, i], 100)) / 100.0 * 0.16
		# 0.78 rather than a deep 0.52 notch: still clearly a conifer, but the
		# points read as a soft rosette instead of a caltrop (owner 2026-08-11).
		var rr := (r if tip else r * 0.78) * j
		out.append(centre + Vector2(cos(a), sin(a)) * rr)
	return out

## Draw one tree — shadow, crown, outline — onto `c`. The one place a tree is
## painted, so the forest, the scatter and the courtyards cannot drift apart.
static func draw_tree(c: CanvasItem, kind: int, centre: Vector2, seed_key: String, scale: float = 1.0) -> void:
	var crown := canopy(kind, centre, seed_key, scale)
	if crown.size() < 3:
		return
	var off := shadow_offset(kind) * scale
	var shadow := PackedVector2Array()
	for p in crown:
		shadow.append(p + off)
	c.draw_colored_polygon(shadow, MapStyle.tree_shadow())
	c.draw_colored_polygon(crown, MapStyle.tree_fill(kind == Kind.FIR))
	var ring := crown.duplicate()
	ring.append(crown[0])
	c.draw_polyline(ring, MapStyle.tree_outline(), 1.0, true)

## Pick a kind from a seeded roll, with the mix a caller wants. `weights` is
## [small, fir, large] and need not sum to anything in particular.
static func pick_kind(seed_key: String, weights: Array) -> int:
	var total := 0
	for w in weights:
		total += int(w)
	if total <= 0:
		return Kind.SMALL
	var roll := RoadHash.pick("tree|%s|kind" % seed_key, total)
	var acc := 0
	for i in weights.size():
		acc += int(weights[i])
		if roll < acc:
			return i
	return Kind.SMALL
