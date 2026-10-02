extends RefCounted
## Supply chain board — the street plan every tile shares.
##
## A tile on the board is laid out like a small industrial estate. The warehouse stands at the
## centre. Ten slots stand around it in three rows: three behind, four across the middle (two
## either side of the warehouse), three in front. Two streets run between the rows along the
## map's x axis, two avenues cross them, each slot and the warehouse has a short spur onto a
## street, and from each street end a link runs off at 60 degrees to the tile's diagonal
## neighbour. The avenues run out to the neighbours above and below.
##
## Because the plan is the same on every tile, the junctions that can occur are a known set,
## which is what lets the roads be drawn from baked pieces (road_pieces.py), and two
## neighbouring tiles always meet at the same point on their shared edge.
##
## Everything here is relative to the tile's centre, in map units, y down. Pure data and
## graph search: nothing here reads the sim.

const SLOT_SIDE := 80.0
const HUB_SIDE := 68.0
const STREET_Y := 70.0
const AVENUE_X := 53.0
const LINK_X := 173.6            # where a link leaves its street
const END_X := 215.0             # a street's end, and the spur of the outermost middle slot
const EDGE_X := 202.5            # the middle of a diagonal edge
const EDGE_Y := 120.0
const TOP_Y := 240.0
## Pipes run beside the streets: one line inside each street, nearer the warehouse, one outside.
const PIPE_INNER := 48.0
const PIPE_OUTER := 92.0

## Slot centres. Front row first, so a tile with few buildings shows them toward the camera.
const SLOTS: Array[Vector2] = [
	Vector2(-110.0, 140.0), Vector2(0.0, 140.0), Vector2(110.0, 140.0),
	Vector2(-200.0, 0.0), Vector2(-110.0, 0.0), Vector2(110.0, 0.0), Vector2(200.0, 0.0),
	Vector2(-110.0, -140.0), Vector2(0.0, -140.0), Vector2(110.0, -140.0),
]

static var _nodes: Dictionary = {}       # id -> Vector2
static var _adj: Dictionary = {}         # id -> [[id, length, kind]]
static var _paths: Dictionary = {}       # "a|b" -> Array of ids


static func nid(p: Vector2) -> String:
	return "%d,%d" % [int(round(p.x)), int(round(p.y))]


## Where a slot's spur meets it, and where that spur meets its street.
static func slot_door(i: int) -> Vector2:
	var c: Vector2 = SLOTS[i]
	if absf(c.y) > 1.0:
		return Vector2(c.x, c.y - signf(c.y) * SLOT_SIDE * 0.5)
	if absf(c.x) > 150.0:
		return Vector2(signf(c.x) * END_X, SLOT_SIDE * 0.5)
	return Vector2(c.x, SLOT_SIDE * 0.5)


static func slot_foot(i: int) -> Vector2:
	var door := slot_door(i)
	return Vector2(door.x, STREET_Y * (1.0 if door.y > 0.0 else -1.0))


static func hub_door() -> Vector2:
	return Vector2(0.0, HUB_SIDE * 0.5)


## The point on this tile's edge where its roads meet the neighbour at `offset` (the
## neighbour's centre minus this tile's). Zero when that is not a neighbour.
static func exit_point(offset: Vector2) -> Vector2:
	if absf(offset.x) < 1.0 and absf(absf(offset.y) - TOP_Y * 2.0) < 1.0:
		return Vector2(AVENUE_X, signf(offset.y) * TOP_Y)
	if absf(absf(offset.x) - EDGE_X * 2.0) < 1.0 and absf(absf(offset.y) - EDGE_Y * 2.0) < 1.0:
		return Vector2(signf(offset.x) * EDGE_X, signf(offset.y) * EDGE_Y)
	return Vector2.ZERO


## Is this point (relative to the tile's centre) one where the roads leave the tile?
static func is_exit(rel: Vector2) -> bool:
	return absf(absf(rel.y) - TOP_Y) < 1.0 \
		or (absf(absf(rel.x) - EDGE_X) < 1.0 and absf(absf(rel.y) - EDGE_Y) < 1.0)


static func _build() -> void:
	if not _nodes.is_empty():
		return
	var xs: Array = [-END_X, -LINK_X, -110.0, -AVENUE_X, 0.0, AVENUE_X, 110.0, LINK_X, END_X]
	for sy in [-1.0, 1.0]:
		for i in range(xs.size() - 1):
			_edge(Vector2(float(xs[i]), STREET_Y * sy), Vector2(float(xs[i + 1]), STREET_Y * sy), "street")
		for sx in [-1.0, 1.0]:
			_edge(Vector2(LINK_X * sx, STREET_Y * sy), Vector2(EDGE_X * sx, EDGE_Y * sy), "link")
			_edge(Vector2(AVENUE_X * sx, STREET_Y * sy), Vector2(AVENUE_X * sx, TOP_Y * sy), "avenue")
	for sx in [-1.0, 1.0]:
		_edge(Vector2(AVENUE_X * sx, -STREET_Y), Vector2(AVENUE_X * sx, STREET_Y), "avenue")
	for i in range(SLOTS.size()):
		_edge(slot_door(i), slot_foot(i), "spur")
	_edge(hub_door(), Vector2(0.0, STREET_Y), "spur")


static func _edge(a: Vector2, b: Vector2, kind: String) -> void:
	var ia := nid(a)
	var ib := nid(b)
	_nodes[ia] = a
	_nodes[ib] = b
	(_adj.get_or_add(ia, []) as Array).append([ib, a.distance_to(b), kind])
	(_adj.get_or_add(ib, []) as Array).append([ia, a.distance_to(b), kind])


static func node_pos(id: String) -> Vector2:
	_build()
	return _nodes.get(id, Vector2.ZERO)


static func has_node(id: String) -> bool:
	_build()
	return _nodes.has(id)


## The kind of the street between two neighbouring nodes: street, avenue, link or spur.
static func kind_of(a: String, b: String) -> String:
	_build()
	for e in _adj.get(a, []):
		if str(e[0]) == b:
			return str(e[2])
	return ""


## The shortest way along the streets from one node to another, as node ids.
static func path(from: String, to: String) -> Array:
	_build()
	var key := from + "|" + to
	if _paths.has(key):
		return _paths[key]
	var dist: Dictionary = {from: 0.0}
	var prev: Dictionary = {}
	var open: Array = [from]
	var done: Dictionary = {}
	while not open.is_empty():
		var best := 0
		for i in range(1, open.size()):
			if float(dist[open[i]]) < float(dist[open[best]]):
				best = i
		var cur: String = open[best]
		open.remove_at(best)
		if done.has(cur):
			continue
		done[cur] = true
		if cur == to:
			break
		for e in _adj.get(cur, []):
			var nd := float(dist[cur]) + float(e[1])
			if not dist.has(e[0]) or nd < float(dist[e[0]]) - 0.001:
				dist[e[0]] = nd
				prev[e[0]] = cur
				open.append(e[0])
	var out: Array = []
	if dist.has(to):
		var at := to
		while at != from:
			out.push_front(at)
			at = str(prev[at])
		out.push_front(from)
	_paths[key] = out
	return out


## Positions for `count` things on a tile's slots: one per slot while they last, then each
## slot split into four, then nine. `skip` is a slot the warehouse has taken. Returns
## [{pos, side, slot}], at least `count` of them.
static func places(count: int, skip: int = -1) -> Array:
	var usable := SLOTS.size() - (1 if skip >= 0 else 0)
	var per := 1
	while usable * per * per < count:
		per += 1
	var out: Array = []
	var side := SLOT_SIDE / float(per)
	for i in range(SLOTS.size()):
		if i == skip:
			continue
		for r in range(per):
			for c in range(per):
				out.append({"slot": i, "side": side,
					"pos": SLOTS[i] + Vector2((float(c) + 0.5) * side - SLOT_SIDE * 0.5,
						(float(r) + 0.5) * side - SLOT_SIDE * 0.5)})
	return out


## Where pipes meet the ground beside the thing whose spur ends at `door`.
static func pipe_point(door: Vector2) -> Vector2:
	var sy := 1.0 if door.y > 0.0 else -1.0
	if absf(door.y) > STREET_Y:
		return Vector2(door.x - 26.0, PIPE_OUTER * sy)
	if absf(door.x) < 1.0:
		return Vector2(-20.0, PIPE_INNER)
	return Vector2(door.x - signf(door.x) * 26.0, PIPE_INNER)
