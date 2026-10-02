extends RefCounted
## Supply chain board — the railway every tile shares.
##
## Rails have their own way beside the streets. A line runs along the outer side of each street,
## one cross track joins the two, and from the lines' ends a track runs off at 60 degrees to
## each diagonal neighbour, parallel to the road's link. The cross track runs on to the
## neighbours above and below. A train stops on the line abreast of what it serves.
##
## The two ends of a track between neighbours have to be the same point seen from each tile, so
## the plan is not a mirror image front to back: the back line is the longer, and a track
## leaving at the back crosses the road's link on its way out.
##
## Everything here is relative to the tile's centre, in map units, y down.

const Streets := preload("res://scripts/empire_board_streets.gd")

const LINE_Y := 97.0
const CROSS_X := -47.0
const FRONT_X := 164.0           # where the front line turns off toward a neighbour
const HALF := 5.5                # half the ballast's width
const SIN60 := 0.8660254
const TILE_STEP := Vector2(405.0, 240.0)


static func _front_exit(sx: float) -> Vector2:
	var a := Vector2(sx * FRONT_X, LINE_Y)
	var d := Vector2(sx * 0.5, SIN60)
	var n := Vector2(sx * SIN60, 0.5)
	return a + d * (n.dot(Vector2(sx * Streets.EDGE_X, Streets.EDGE_Y) - a) / n.dot(d))


## Where the track to the neighbour at `offset` crosses this tile's edge. Zero when that is not
## a neighbour.
static func exit_point(offset: Vector2) -> Vector2:
	if absf(offset.x) < 1.0 and absf(absf(offset.y) - Streets.TOP_Y * 2.0) < 1.0:
		return Vector2(CROSS_X, signf(offset.y) * Streets.TOP_Y)
	if absf(absf(offset.x) - TILE_STEP.x) > 1.0 or absf(absf(offset.y) - TILE_STEP.y) > 1.0:
		return Vector2.ZERO
	if offset.y > 0.0:
		return _front_exit(signf(offset.x))
	# The same point as the neighbour's front exit toward this tile.
	return _front_exit(-signf(offset.x)) + offset


static func is_exit(rel: Vector2) -> bool:
	return absf(absf(rel.y) - LINE_Y) > 1.0


## Where a train stops for the thing whose door onto the street is at `door`.
static func stop(door: Vector2) -> Vector2:
	var front := door.y > 0.0
	var reach := FRONT_X if front else _attach(exit_point(Vector2(TILE_STEP.x, -TILE_STEP.y))).x
	return Vector2(clampf(door.x, -reach, reach), LINE_Y if front else -LINE_Y)


## The point on a line that an exit's track joins; a point already on a line is itself.
static func _attach(p: Vector2) -> Vector2:
	if not is_exit(p):
		return p
	if absf(absf(p.y) - Streets.TOP_Y) < 1.0:
		return Vector2(CROSS_X, signf(p.y) * LINE_Y)
	if p.y > 0.0:
		return Vector2(signf(p.x) * FRONT_X, LINE_Y)
	var d := Vector2(-signf(p.x) * 0.5, SIN60)
	return p + d * ((-LINE_Y - p.y) / d.y)


## The track from one point to another, each a stop or an exit. Relative points, ends included.
static func path(from: Vector2, to: Vector2) -> Array:
	var a := _attach(from)
	var b := _attach(to)
	var way: Array = [from, a]
	if absf(a.y - b.y) > 1.0:
		way.append(Vector2(CROSS_X, a.y))
		way.append(Vector2(CROSS_X, b.y))
	way.append(b)
	way.append(to)
	var out: Array = []
	for p in way:
		if out.is_empty() or (out[out.size() - 1] as Vector2).distance_to(p) > 0.5:
			out.append(p)
	return out
