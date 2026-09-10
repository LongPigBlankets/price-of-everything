extends RefCounted
## Empire view — the OCCUPANCY REGISTRY (owner 2026-09-10: "every item, line and visual
## object gets its own space with minimal collisions").
##
## One frame, one registry: everything the supply-chain view paints registers the screen
## space it takes — a building's opaque sprite, the animated-effects envelope around it (plume,
## flame, lorry run, robot arms), its caption plate and port badge, each port hex, every
## routed line, every good-icon chip. The separation pass, the router and the chip placer
## read this ONE model instead of the three partial views they used to keep (the separation
## pass knew panels and ports, the router knew sprites, the chips knew nothing), which is how
## a plume rose into the plate above it and eight coal chips landed on one another.
##
## Pure geometry, no scene-tree or sim dependency (CLAUDE.md rule #1), so `report()` runs
## headless and the overlap audit can be a test.
##
## Kinds: sprite, fx, plate, badge, port, route, chip. Owner = the node iid (or "from|to" for a
## route, "<kind>|<from>|<good>" for a chip). A route carries `ends`, the owners it legitimately
## touches — it starts and finishes ON its endpoint plates — so those pairs never count.

const KINDS := ["sprite", "fx", "plate", "badge", "port", "route", "chip"]

var items: Array = []


func clear() -> void:
	items.clear()


func add_rect(kind: String, owner: String, rect: Rect2, ends: Array = []) -> int:
	items.append({"kind": kind, "owner": owner, "rect": rect, "path": PackedVector2Array(),
		"width": 0.0, "ends": ends})
	return items.size() - 1


## A polyline of the given stroke width; `ends` are the owners it may touch (its endpoints).
func add_path(kind: String, owner: String, pts: PackedVector2Array, width: float, ends: Array = []) -> int:
	var bb := Rect2()
	if pts.size() > 0:
		bb = Rect2(pts[0], Vector2.ZERO)
		for p in pts:
			bb = bb.expand(p)
	items.append({"kind": kind, "owner": owner, "rect": bb.grow(width * 0.5), "path": pts,
		"width": width, "ends": ends})
	return items.size() - 1


## Rects of the given kinds, minus those owned by `skip`.
func rects_of(kinds: Array, skip: Array = []) -> Array:
	var out: Array = []
	for it in items:
		if kinds.has(it["kind"]) and not skip.has(it["owner"]):
			out.append(it["rect"])
	return out


## Does `rect` collide with any registered item of `kinds` (owners in `skip` ignored)?
func rect_hits(rect: Rect2, kinds: Array, skip: Array = []) -> bool:
	for it in items:
		if not kinds.has(it["kind"]) or skip.has(it["owner"]):
			continue
		if _hit_rect_item(rect, it):
			return true
	return false


## Every colliding pair as {a, b, kinds: "x|y"} (kinds sorted). Route-vs-route is not a
## collision here — lines share gutters by design; crossings are the lane solver's metric.
func overlaps() -> Array:
	var out: Array = []
	for i in items.size():
		var a: Dictionary = items[i]
		for j in range(i + 1, items.size()):
			var b: Dictionary = items[j]
			if not _counts(a, b):
				continue
			if _hits(a, b):
				out.append({"a": i, "b": j, "kinds": _pair_key(a["kind"], b["kind"])})
	return out


## Counts per kind pair ("chip|chip", "route|sprite", ...) plus the pair list.
func report() -> Dictionary:
	var counts: Dictionary = {}
	var pairs := overlaps()
	for p in pairs:
		var k: String = p["kinds"]
		counts[k] = int(counts.get(k, 0)) + 1
	var by_kind: Dictionary = {}
	for it in items:
		by_kind[it["kind"]] = int(by_kind.get(it["kind"], 0)) + 1
	return {"counts": counts, "pairs": pairs, "items": by_kind, "total": pairs.size()}


## Line crossings: segment pairs of two different routes that intersect away from a shared
## endpoint. Not a collision (lines may cross), but the number the layout is judged by.
func crossings() -> Dictionary:
	var routes: Array = []
	for it in items:
		if it["kind"] == "route" and (it["path"] as PackedVector2Array).size() >= 2:
			routes.append(it)
	var n := 0
	var by_family: Dictionary = {}
	for i in routes.size():
		var a: Dictionary = routes[i]
		for j in range(i + 1, routes.size()):
			var b: Dictionary = routes[j]
			var pa: PackedVector2Array = a["path"]
			var pb: PackedVector2Array = b["path"]
			var shared: Array = []
			for e in a["ends"]:
				if (b["ends"] as Array).has(e):
					shared.append(e)
			var c := 0
			for x in range(pa.size() - 1):
				for y in range(pb.size() - 1):
					if _segs_cross(pa[x], pa[x + 1], pb[y], pb[y + 1]):
						c += 1
			if c > 0:
				# Lines out of the same plate touch at the stub; that is a junction, not a crossing.
				if not shared.is_empty() and pa[0].distance_to(pb[0]) < 40.0:
					c -= 1
				if not shared.is_empty() and pa[pa.size() - 1].distance_to(pb[pb.size() - 1]) < 40.0:
					c -= 1
			if c > 0:
				n += c
				var key := "%s x %s" % [a["owner"], b["owner"]]
				by_family[key] = c
	return {"total": n, "pairs": by_family}


static func _segs_cross(p1: Vector2, p2: Vector2, q1: Vector2, q2: Vector2) -> bool:
	var d1 := (p2 - p1).cross(q1 - p1)
	var d2 := (p2 - p1).cross(q2 - p1)
	var d3 := (q2 - q1).cross(p1 - q1)
	var d4 := (q2 - q1).cross(p2 - q1)
	return ((d1 > 0.0) != (d2 > 0.0)) and ((d3 > 0.0) != (d4 > 0.0)) and absf(d1) > 0.01 and absf(d2) > 0.01 and absf(d3) > 0.01 and absf(d4) > 0.01


func describe(i: int) -> String:
	var it: Dictionary = items[i]
	return "%s(%s)" % [it["kind"], it["owner"]]


static func _pair_key(ka: String, kb: String) -> String:
	return ka + "|" + kb if ka <= kb else kb + "|" + ka


func _counts(a: Dictionary, b: Dictionary) -> bool:
	if a["owner"] == b["owner"]:
		return false
	if a["kind"] == "route" and b["kind"] == "route":
		return false
	# A route may touch the plate/sprite/badge/fx of the nodes it connects; a chip may sit on
	# the route it labels (and that route's endpoints are not the chip's business).
	if (a["ends"] as Array).has(b["owner"]) or (b["ends"] as Array).has(a["owner"]):
		return false
	return true


func _hits(a: Dictionary, b: Dictionary) -> bool:
	var pa: bool = (a["path"] as PackedVector2Array).size() >= 2
	var pb: bool = (b["path"] as PackedVector2Array).size() >= 2
	if pa and pb:
		return false
	if pa:
		return _hit_rect_item(b["rect"], a)
	if pb:
		return _hit_rect_item(a["rect"], b)
	return (a["rect"] as Rect2).intersects(b["rect"])


static func _hit_rect_item(rect: Rect2, it: Dictionary) -> bool:
	var pts: PackedVector2Array = it["path"]
	if pts.size() >= 2:
		return path_hits_rect(pts, rect.grow(float(it["width"]) * 0.5))
	return rect.intersects(it["rect"])


static func path_hits_rect(pts: PackedVector2Array, r: Rect2) -> bool:
	for i in range(pts.size() - 1):
		if seg_hits_rect(pts[i], pts[i + 1], r):
			return true
	return false


## Liang-Barsky segment/rect clip: true when any part of p0-p1 lies inside r.
static func seg_hits_rect(p0: Vector2, p1: Vector2, r: Rect2) -> bool:
	if r.has_point(p0) or r.has_point(p1):
		return true
	var d := p1 - p0
	var t0 := 0.0
	var t1 := 1.0
	var p := [-d.x, d.x, -d.y, d.y]
	var q := [p0.x - r.position.x, r.end.x - p0.x, p0.y - r.position.y, r.end.y - p0.y]
	for i in 4:
		var pi: float = p[i]
		var qi: float = q[i]
		if absf(pi) < 1e-9:
			if qi < 0.0:
				return false
			continue
		var t := qi / pi
		if pi < 0.0:
			if t > t1:
				return false
			t0 = maxf(t0, t)
		else:
			if t < t0:
				return false
			t1 = minf(t1, t)
	return t0 <= t1
