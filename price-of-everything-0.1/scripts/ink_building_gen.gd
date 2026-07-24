class_name InkBuildingGen
## Procedural ink-mode industrial buildings — the owner's shape language v3
## (2026-07-23), ported from the in-chat prototype. Ten building types compose
## from primitives (flat roofs, seamless flat polygons, sawtooth bays, gables,
## tanks, spheres, stacks, EAF vessels with electrode rods, capsules, apses,
## pipes, cables, pads, battery units, corridors) at three levels that read as
## build-out.
##
## LIGHTING IS WORLD-FIXED (owner requirement): recipes are authored in a
## local y-down design space, but every tone is computed from the face's
## WORLD normal against the NW light — so a rotated building keeps its lit
## faces toward the top-left of the screen. Shadows offset in world SE
## (unrotated), highlight crescents aim world NW (local angle minus rotation).
## Pure draw calls — no textures, no nodes, no sim contact.

const INK := Color("2f2b26")
const LT := Color("d8d7d2")
const MLT := Color("c4c3be")
const MID := Color("adacaa")
const DK := Color("8f8e8a")
const DKR := Color("7a7975")
const BORE := Color("3b3835")
const HI := Color("e6e5e0")
const PAD_C := Color("b6afa2")
const DECK := Color("c9bc95")
const CONTAINER_COLS: Array[Color] = [Color("a8564a"), Color("bfa04a"), Color("b8b7b2")]
const NPC_PAPER := Color("efe9db")
const SHADOW := Color(0.184, 0.169, 0.149, 0.22)
const LIGHT_DIR := Vector2(-0.7071068, -0.7071068)
const SHADOW_OFF := Vector2(1.7, 2.2)   # world units per shadow-scale k

static var _cache: Dictionary = {}   # "iname|lvl" -> {prims: Array, size: Vector2}

## Draw one building. `target` = desired world size of the long side; `ang` =
## footprint rotation. `anchor` (optional, in the recipe's design space) pins
## that local point at `ctr` instead of centering the bounding box — ports use
## it to hold the quay spine on the shoreline while the piers reach seaward.
## Returns false when the type has no recipe.
static func draw(c: CanvasItem, iname: String, lvl: int, ctr: Vector2, ang: float, target: float, npc: bool, anchor: Vector2 = Vector2.INF) -> bool:
	var entry := _entry(iname, clampi(lvl, 1, 3))
	if entry.is_empty():
		return false
	var size: Vector2 = entry.size
	var s := target / maxf(size.x, size.y)
	var pos := ctr
	if anchor.is_finite():
		var anchor_local := (anchor - (entry.center as Vector2)) * s
		pos = ctr - anchor_local.rotated(ang)
	var prims: Array = entry.prims
	# silhouette shadow passes, farthest (tallest) first, offset in WORLD space
	var groups: Dictionary = {}
	for pr in prims:
		var k := float(pr.get("k", 1.0))
		if not groups.has(k):
			groups[k] = []
		(groups[k] as Array).append(pr)
	var ks: Array = groups.keys()
	ks.sort_custom(func(a, b) -> bool: return float(a) > float(b))
	for k in ks:
		c.draw_set_transform(pos + SHADOW_OFF * float(k), ang, Vector2(s, s))
		for pr in (groups[k] as Array):
			_draw_sil(c, pr)
	# body pass
	c.draw_set_transform(pos, ang, Vector2(s, s))
	for pr in prims:
		_draw_prim(c, pr, ang, npc)
	c.draw_set_transform_matrix(Transform2D.IDENTITY)
	return true

static func _entry(iname: String, lvl: int) -> Dictionary:
	var key := "%s|%d" % [iname, lvl]
	if _cache.has(key):
		return _cache[key]
	var prims := _recipe(iname, lvl)
	if prims.is_empty():
		_cache[key] = {}
		return {}
	var bb := _bounds(prims)
	_shift(prims, -bb.get_center())
	var entry := {"prims": prims, "size": bb.size, "center": bb.get_center()}
	_cache[key] = entry
	return entry

## ── tones (world-normal lighting) ───────────────────────────────────────────

static func _fill(col: Color, npc: bool) -> Color:
	return col.lerp(NPC_PAPER, 0.30) if npc else col

## 3-step facet tone for pitched surfaces and edge strips.
static func _facet3(n_local: Vector2, rot: float) -> Color:
	var d := n_local.rotated(rot).dot(LIGHT_DIR)
	if d > 0.15:
		return LT
	if d < -0.15:
		return DK
	return MLT

## Which lateral side (local ±Y) faces the light — for capsule stripes/unit caps.
static func _lit_side(rot: float) -> float:
	var up := Vector2(0, -1).rotated(rot).dot(LIGHT_DIR)
	var down := Vector2(0, 1).rotated(rot).dot(LIGHT_DIR)
	return -1.0 if up >= down else 1.0

static func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, r.position + Vector2(r.size.x, 0), r.end, r.position + Vector2(0, r.size.y)])

## ── recipes (design space ~200x150, y-down; v3 coordinates verbatim) ────────

static func _recipe(iname: String, l: int) -> Array:
	match iname:
		"furnace":
			var p := [_flat(58, 62, 74, 36, 3), _stack(78, 55, 8), _stack(102, 55, 8)]
			if l >= 2:
				p.append(_gable(132, 66, 30, 26))
				p.append(_stack(124, 55, 7))
			if l >= 3:
				p.append(_flat(36, 52, 20, 42, 0))
				p.append(_pipes([[Vector2(46, 60), Vector2(46, 44), Vector2(84, 44)]]))
			return p
		"eaf":
			var p := [_flat(64, 52, 56, 52, 0)]
			if l >= 2:
				p.append(_flat(120, 66, 26, 38, 1))
			p.append(_vessel(92, 78, 17))
			if l >= 3:
				p.append(_vessel(134, 52, 11))
				p.append(_bar(Vector2(92, 61), Vector2(92, 52), 5, 1.0))
				p.append(_bar(Vector2(134, 63), Vector2(134, 66), 5, 1.0))
			return p
		"industrial_factory":
			var p := [_saw(50, 44, 74, 62, 4), _flat(124, 44, 16, 62, 0), _loadbay(44, 112)]
			if l >= 2:
				p.append(_multi(142, 52, 26, 34, 2))
			if l >= 3:
				p.append(_multi(142, 90, 26, 22, 2))
				p.append(_pipes([[Vector2(140, 70), Vector2(146, 70)]]))
			return p
		"consumer_factory":
			var p := [_flat(60, 56, 42, 30, 2)]
			if l >= 2:
				p.append(_gable(108, 60, 36, 22))
			if l >= 3:
				p.append(_gable(62, 92, 34, 20))
				p.append(_flat(108, 88, 30, 24, 1))
			return p
		"assembly_plant":
			var p := []
			if l == 1:
				p.append(_fpoly([PackedVector2Array([Vector2(56, 52), Vector2(144, 52), Vector2(144, 78), Vector2(56, 78)])]))
			elif l == 2:
				p.append(_fpoly([PackedVector2Array([Vector2(56, 52), Vector2(144, 52), Vector2(144, 118), Vector2(124, 118), Vector2(124, 78), Vector2(76, 78), Vector2(76, 118), Vector2(56, 118)])]))
			else:
				p.append(_pad(76, 78, 48, 26))
				p.append(_fpoly([
					PackedVector2Array([Vector2(56, 52), Vector2(144, 52), Vector2(144, 118), Vector2(56, 118)]),
					PackedVector2Array([Vector2(76, 78), Vector2(76, 104), Vector2(124, 104), Vector2(124, 78)]),
				]))
			p.append(_apse(100, 78, 16))
			p.append(_box(64, 58, 10, 7))
			p.append(_box(126, 58, 10, 7))
			return p
		"high_tech_manufactory":
			var p := []
			if l >= 2:
				p.append(_corridor(Vector2(110, 66), Vector2(122, 64)))
			if l >= 3:
				p.append(_corridor(Vector2(110, 88), Vector2(122, 94)))
				p.append(_corridor(Vector2(137, 76), Vector2(137, 86)))
			p.append(_flat(58, 56, 52, 40, 0))
			if l >= 2:
				p.append(_flat(122, 50, 30, 26, 1))
			if l >= 3:
				p.append(_flat(122, 86, 30, 26, 1))
			p.append(_box(66, 64, 10, 7))
			p.append(_box(84, 62, 12, 8))
			p.append(_box(70, 82, 9, 6))
			p.append(_pipes([[Vector2(64, 74), Vector2(100, 74)], [Vector2(88, 62), Vector2(88, 92)]]))
			if l >= 2:
				p.append(_box(130, 56, 9, 6))
			if l >= 3:
				p.append(_box(128, 92, 10, 7))
			return p
		"petro_refinery":
			var p := [_flat(52, 52, 48, 34, 2)]
			if l == 1:
				p.append(_pipes([[Vector2(100, 66), Vector2(122, 66)]]))
				p.append(_tank(122, 70, 12))
			if l >= 2:
				p.append(_stack(64, 46, 6))
				p.append(_stack(80, 46, 6))
				p.append(_pad(106, 56, 44, 44))
				p.append(_pipes([[Vector2(100, 64), Vector2(118, 64)], [Vector2(100, 76), Vector2(138, 76)]]))
				p.append(_tank(118, 68, 9.5))
				p.append(_tank(138, 68, 9.5))
			if l >= 3:
				p.append(_flat(52, 88, 32, 22, 1))
				p.append(_pipes([[Vector2(84, 96), Vector2(118, 96)], [Vector2(128, 60), Vector2(128, 96)]]))
				p.append(_tank(118, 90, 9.5))
				p.append(_tank(138, 90, 9.5))
			return p
		"poly_plant":
			var p := [_gable(52, 54, 50, 22)]
			if l == 1:
				p.append(_sphere(118, 66, 10))
				p.append(_sphere(140, 66, 10))
			if l >= 2:
				p.append(_gable(52, 80, 44, 20))
				p.append(_sphere(118, 60, 10))
				p.append(_sphere(140, 60, 10))
			if l >= 3:
				p.append(_pad(108, 76, 48, 32))
				p.append(_sphere(120, 86, 9))
				p.append(_sphere(140, 86, 9))
				p.append(_capsule(52, 106, 44, 14))
			return p
		"chem_plant":
			var p := [_flat(56, 46, 26, 66, 0), _stack(69, 60, 6.5)]
			if l >= 2:
				p.append(_flat(82, 46, 50, 16, 1))
				p.append(_stack(69, 86, 6.5))
			if l >= 3:
				p.append(_flat(82, 96, 50, 16, 1))
			p.append(_pipes([[Vector2(82, 79), Vector2(94, 79)]]))
			p.append(_tank(104, 79, 8))
			p.append(_tank(122, 79, 8))
			if l >= 2:
				p.append(_capsule(88, 26, 40, 12))
			return p
		"port":
			# Authored with +X = seaward (port_visuals passes the sea-facing
			# angle): quay spine along the shore with warehouses + container
			# stacks, plank-decked pier fingers, two jib cranes (elevated
			# shadows). Neutral infrastructure — callers pass npc=false.
			var p := [_deck(44, 28, 30, 100, true)]
			p.append(_gable_v(48, 34, 20, 28))
			p.append(_gable_v(48, 96, 20, 26))
			p.append(_deck(74, 36, 50, 10, false))
			p.append(_deck(74, 64, 58, 10, false))
			p.append(_deck(74, 92, 44, 10, false))
			p.append(_containers(48, 66, 2, 3))
			p.append(_containers(52, 84, 1, 2))
			p.append(_cbase(100, 41))
			p.append(_bar(Vector2(94, 43), Vector2(118, 36), 3, 1.6))
			p.append(_dot(118, 36, 1.3))
			p.append(_cbase(110, 69))
			p.append(_bar(Vector2(103, 71.5), Vector2(130, 64), 3, 1.6))
			p.append(_dot(130, 64, 1.3))
			return p
		"electrolyser":
			var p := [_pad(56, 54, 44, 40)]
			for r in 3:
				for cc in 3:
					p.append(_unit(62 + cc * 13, 59 + r * 13))
			p.append(_cable([[Vector2(60, 100), Vector2(96, 100)], [Vector2(66, 96), Vector2(66, 100)], [Vector2(79, 96), Vector2(79, 100)], [Vector2(92, 96), Vector2(92, 100)]]))
			p.append(_pipes([[Vector2(100, 74), Vector2(110, 74)]]))
			p.append(_tank(116, 62, 7))
			p.append(_tank(116, 80, 7))
			if l >= 2:
				p.append(_pad(56, 98, 44, 26))
				p.append(_unit(62, 103))
				p.append(_unit(75, 103))
				p.append(_unit(88, 103))
				p.append(_cable([[Vector2(60, 122), Vector2(96, 122)], [Vector2(66, 118), Vector2(66, 122)], [Vector2(79, 118), Vector2(79, 122)], [Vector2(92, 118), Vector2(92, 122)]]))
				p.append(_tank(134, 62, 7))
				p.append(_tank(134, 80, 7))
			if l >= 3:
				p.append(_pad(104, 98, 40, 26))
				p.append(_unit(110, 103))
				p.append(_unit(123, 103))
				p.append(_unit(136, 103))
				p.append(_cable([[Vector2(108, 122), Vector2(140, 122)], [Vector2(114, 118), Vector2(114, 122)], [Vector2(127, 118), Vector2(127, 122)]]))
				p.append(_flat(126, 34, 26, 18, 1))
				p.append(_tank(152, 62, 7))
				p.append(_tank(152, 80, 7))
				p.append(_cable([[Vector2(100, 66), Vector2(106, 66), Vector2(106, 90)]]))
			return p
	return []

## ── primitive constructors ──────────────────────────────────────────────────

static func _flat(x: float, y: float, w: float, h: float, vents: int) -> Dictionary:
	return {"t": "flat", "r": Rect2(x, y, w, h), "vents": vents}

static func _fpoly(rings: Array) -> Dictionary:
	return {"t": "fpoly", "rings": rings}

static func _saw(x: float, y: float, w: float, h: float, bays: int) -> Dictionary:
	return {"t": "saw", "r": Rect2(x, y, w, h), "bays": bays}

static func _multi(x: float, y: float, w: float, h: float, steps: int) -> Dictionary:
	return {"t": "multi", "r": Rect2(x, y, w, h), "steps": steps, "k": 2.4}

static func _loadbay(x: float, y: float) -> Dictionary:
	return {"t": "loadbay", "r": Rect2(x, y, 30, 16)}

static func _gable(x: float, y: float, w: float, h: float) -> Dictionary:
	return {"t": "gable", "r": Rect2(x, y, w, h)}

static func _tank(cx: float, cy: float, r: float) -> Dictionary:
	return {"t": "tank", "c": Vector2(cx, cy), "r": r}

static func _sphere(cx: float, cy: float, r: float) -> Dictionary:
	return {"t": "sphere", "c": Vector2(cx, cy), "r": r}

static func _stack(cx: float, cy: float, r: float) -> Dictionary:
	return {"t": "stack", "c": Vector2(cx, cy), "r": r}

static func _vessel(cx: float, cy: float, r: float) -> Dictionary:
	return {"t": "vessel", "c": Vector2(cx, cy), "r": r}

static func _bar(a: Vector2, b: Vector2, w: float, k: float) -> Dictionary:
	return {"t": "bar", "a": a, "b": b, "w": w, "k": k}

static func _corridor(a: Vector2, b: Vector2) -> Dictionary:
	return {"t": "bar", "a": a, "b": b, "w": 4.5, "k": 2.0}

static func _capsule(x: float, y: float, w: float, h: float) -> Dictionary:
	return {"t": "capsule", "r": Rect2(x, y, w, h)}

static func _apse(cx: float, cy: float, r: float) -> Dictionary:
	return {"t": "apse", "c": Vector2(cx, cy), "r": r}

static func _pipes(runs: Array) -> Dictionary:
	return {"t": "pipes", "runs": _to_packed(runs)}

static func _cable(runs: Array) -> Dictionary:
	return {"t": "cable", "runs": _to_packed(runs)}

static func _pad(x: float, y: float, w: float, h: float) -> Dictionary:
	return {"t": "pad", "r": Rect2(x, y, w, h)}

static func _unit(x: float, y: float) -> Dictionary:
	return {"t": "unit", "r": Rect2(x, y, 8, 11)}

static func _box(x: float, y: float, w: float, h: float) -> Dictionary:
	return {"t": "box", "r": Rect2(x, y, w, h)}

static func _gable_v(x: float, y: float, w: float, h: float) -> Dictionary:
	return {"t": "gable_v", "r": Rect2(x, y, w, h)}

static func _deck(x: float, y: float, w: float, h: float, vert: bool) -> Dictionary:
	return {"t": "deck", "r": Rect2(x, y, w, h), "vert": vert}

static func _containers(x: float, y: float, rows: int, cols: int) -> Dictionary:
	return {"t": "containers", "r": Rect2(x, y, cols * 8.3 - 1.3, rows * 5.5 - 1.3), "rows": rows, "cols": cols}

static func _cbase(cx: float, cy: float) -> Dictionary:
	return {"t": "cbase", "c": Vector2(cx, cy), "r": 4.2}

static func _dot(cx: float, cy: float, r: float) -> Dictionary:
	return {"t": "dot", "c": Vector2(cx, cy), "r": r}

static func _to_packed(runs: Array) -> Array:
	var out: Array = []
	for run in runs:
		out.append(PackedVector2Array(run))
	return out

## ── bounds + recenter ───────────────────────────────────────────────────────

static func _bounds(prims: Array) -> Rect2:
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for pr in prims:
		match str(pr.t):
			"tank", "sphere", "stack", "vessel", "apse", "cbase", "dot":
				mn = mn.min(pr.c - Vector2(pr.r, pr.r))
				mx = mx.max(pr.c + Vector2(pr.r, pr.r))
			"bar":
				mn = mn.min((pr.a as Vector2).min(pr.b))
				mx = mx.max((pr.a as Vector2).max(pr.b))
			"pipes", "cable":
				for run in (pr.runs as Array):
					for v in run:
						mn = mn.min(v)
						mx = mx.max(v)
			"fpoly":
				for v in (pr.rings as Array)[0]:
					mn = mn.min(v)
					mx = mx.max(v)
			_:
				var r: Rect2 = pr.r
				mn = mn.min(r.position)
				mx = mx.max(r.end)
	return Rect2(mn, mx - mn)

static func _shift(prims: Array, off: Vector2) -> void:
	for pr in prims:
		match str(pr.t):
			"tank", "sphere", "stack", "vessel", "apse", "cbase", "dot":
				pr.c = (pr.c as Vector2) + off
			"bar":
				pr.a = (pr.a as Vector2) + off
				pr.b = (pr.b as Vector2) + off
			"pipes", "cable":
				var shifted: Array = []
				for run in (pr.runs as Array):
					var pv: PackedVector2Array = run
					var np := PackedVector2Array()
					np.resize(pv.size())
					for i in pv.size():
						np[i] = pv[i] + off
					shifted.append(np)
				pr.runs = shifted
			"fpoly":
				var rings: Array = []
				for ring in (pr.rings as Array):
					var rv: PackedVector2Array = ring
					var nr := PackedVector2Array()
					nr.resize(rv.size())
					for i in rv.size():
						nr[i] = rv[i] + off
					rings.append(nr)
				pr.rings = rings
			_:
				pr.r = Rect2((pr.r as Rect2).position + off, (pr.r as Rect2).size)

## ── shadow silhouettes ──────────────────────────────────────────────────────

static func _draw_sil(c: CanvasItem, pr: Dictionary) -> void:
	match str(pr.t):
		"tank", "sphere", "stack", "vessel", "cbase":
			c.draw_circle(pr.c, float(pr.r), SHADOW)
		"dot":
			pass
		"apse":
			var pts := PackedVector2Array()
			for i in 13:
				var a := PI * float(i) / 12.0
				pts.append((pr.c as Vector2) + Vector2(cos(a), sin(a)) * float(pr.r))
			c.draw_colored_polygon(pts, SHADOW)
		"bar":
			var dirv := ((pr.b as Vector2) - (pr.a as Vector2)).normalized()
			var n := Vector2(-dirv.y, dirv.x) * float(pr.w) * 0.5
			c.draw_colored_polygon(PackedVector2Array([pr.a + n, pr.b + n, pr.b - n, pr.a - n]), SHADOW)
		"pipes", "cable", "box":
			pass
		"fpoly":
			c.draw_colored_polygon((pr.rings as Array)[0], SHADOW)
		"capsule":
			var r: Rect2 = pr.r
			var hr := r.size.y * 0.5
			c.draw_colored_polygon(_rect_poly(Rect2(r.position.x + hr, r.position.y, r.size.x - hr * 2.0, r.size.y)), SHADOW)
			c.draw_circle(r.position + Vector2(hr, hr), hr, SHADOW)
			c.draw_circle(Vector2(r.end.x - hr, r.position.y + hr), hr, SHADOW)
		_:
			c.draw_colored_polygon(_rect_poly(pr.r), SHADOW)

## ── primitive renderers ─────────────────────────────────────────────────────

static func _draw_prim(c: CanvasItem, pr: Dictionary, rot: float, npc: bool) -> void:
	match str(pr.t):
		"flat":
			_rd_flat(c, pr, rot, npc)
		"fpoly":
			_rd_fpoly(c, pr, rot, npc)
		"saw":
			_rd_saw(c, pr, rot, npc)
		"multi":
			_rd_multi(c, pr, rot, npc)
		"loadbay":
			_rd_loadbay(c, pr, npc)
		"gable":
			_rd_gable(c, pr, rot, npc)
		"tank":
			_rd_tank(c, pr, rot, npc)
		"sphere":
			_rd_sphere(c, pr, rot, npc)
		"stack":
			_rd_stack(c, pr, rot, npc)
		"vessel":
			_rd_vessel(c, pr, rot, npc)
		"bar":
			_rd_bar(c, pr, npc)
		"capsule":
			_rd_capsule(c, pr, rot, npc)
		"apse":
			_rd_apse(c, pr, npc)
		"pipes":
			for run in (pr.runs as Array):
				c.draw_polyline(run, INK, 4.6, true)
			for run in (pr.runs as Array):
				c.draw_polyline(run, _fill(MLT, npc), 2.6, true)
		"cable":
			for run in (pr.runs as Array):
				c.draw_polyline(run, INK, 0.9, true)
		"pad":
			c.draw_colored_polygon(_rect_poly(pr.r), _fill(PAD_C, npc))
			_outline_rect(c, pr.r, 1.1)
		"unit":
			_rd_unit(c, pr, rot, npc)
		"box":
			var r: Rect2 = pr.r
			c.draw_colored_polygon(_rect_poly(r), _fill(LT, npc))
			_outline_rect(c, r, 0.9)
		"gable_v":
			_rd_gable_v(c, pr, rot, npc)
		"deck":
			_rd_deck(c, pr, rot, npc)
		"containers":
			_rd_containers(c, pr, npc)
		"cbase":
			c.draw_circle(pr.c, float(pr.r), _fill(MLT, npc))
			c.draw_arc(pr.c, float(pr.r), 0.0, TAU, 16, INK, 1.2, true)
			c.draw_circle(pr.c, 1.2, INK)
		"dot":
			c.draw_circle(pr.c, float(pr.r), INK)

static func _outline_rect(c: CanvasItem, r: Rect2, w: float) -> void:
	var loop := _rect_poly(r)
	loop.append(loop[0])
	c.draw_polyline(loop, INK, w, true)

static func _rd_flat(c: CanvasItem, pr: Dictionary, rot: float, npc: bool) -> void:
	var r: Rect2 = pr.r
	c.draw_colored_polygon(_rect_poly(r), _fill(MID, npc))
	c.draw_rect(Rect2(r.position, Vector2(r.size.x, 2.4)), _fill(_facet3(Vector2(0, -1), rot), npc))
	c.draw_rect(Rect2(r.position, Vector2(2.4, r.size.y)), _fill(_facet3(Vector2(-1, 0), rot), npc))
	c.draw_rect(Rect2(r.position + Vector2(0, r.size.y - 2.6), Vector2(r.size.x, 2.6)), _fill(_facet3(Vector2(0, 1), rot), npc))
	c.draw_rect(Rect2(r.position + Vector2(r.size.x - 2.6, 0), Vector2(2.6, r.size.y)), _fill(_facet3(Vector2(1, 0), rot), npc))
	for i in int(pr.vents):
		var vr := Rect2(r.position + Vector2(8 + i * 12, 5), Vector2(7, 4.5))
		c.draw_colored_polygon(_rect_poly(vr), _fill(LT, npc))
		_outline_rect(c, vr, 0.9)
	_outline_rect(c, r, 1.4)

static func _rd_fpoly(c: CanvasItem, pr: Dictionary, rot: float, npc: bool) -> void:
	var rings: Array = pr.rings
	var outer: PackedVector2Array = rings[0]
	if rings.size() == 1:
		c.draw_colored_polygon(outer, _fill(MID, npc))
	else:
		# even-odd fill via triangulated delaunay is overkill — carve the hole
		# with Geometry2D (single courtyard hole in practice)
		var pieces := Geometry2D.clip_polygons(outer, rings[1])
		for piece in pieces:
			if piece.size() >= 3:
				c.draw_colored_polygon(piece, _fill(MID, npc))
	for ring in rings:
		var rv: PackedVector2Array = ring
		for i in rv.size():
			var a := rv[i]
			var b := rv[(i + 1) % rv.size()]
			var ev := b - a
			var len := ev.length()
			if len < 2.0:
				continue
			var dirv := ev / len
			var n := Vector2(dirv.y, -dirv.x)          # outward for CW outer / CCW hole
			var inset := -n * 1.5
			c.draw_line(a + inset, b + inset, _fill(_facet3(n, rot), npc), 2.6, true)
		var loop := rv.duplicate()
		loop.append(rv[0])
		c.draw_polyline(loop, INK, 1.4, true)

static func _rd_saw(c: CanvasItem, pr: Dictionary, rot: float, npc: bool) -> void:
	var r: Rect2 = pr.r
	var bh := r.size.y / float(pr.bays)
	for i in int(pr.bays):
		var by := r.position.y + i * bh
		c.draw_rect(Rect2(r.position.x, by, r.size.x, bh * 0.72), _fill(_facet3(Vector2(0, -1), rot), npc))
		c.draw_rect(Rect2(r.position.x, by + bh * 0.72, r.size.x, bh * 0.28), _fill(_facet3(Vector2(0, 1), rot).darkened(0.06), npc))
		c.draw_line(Vector2(r.position.x, by + bh * 0.72), Vector2(r.end.x, by + bh * 0.72), INK, 0.9, true)
		c.draw_line(Vector2(r.position.x, by + bh), Vector2(r.end.x, by + bh), INK, 0.7, true)
	_outline_rect(c, r, 1.4)

static func _rd_multi(c: CanvasItem, pr: Dictionary, rot: float, npc: bool) -> void:
	var r: Rect2 = pr.r
	c.draw_colored_polygon(_rect_poly(r), _fill(MLT, npc))
	for i in range(1, int(pr.steps) + 1):
		var inx := i * 3.2
		var sr := Rect2(r.position + Vector2(inx, inx), r.size - Vector2(inx * 2.0, inx * 2.0))
		c.draw_colored_polygon(_rect_poly(sr), _fill(LT if i % 2 == 1 else MLT, npc))
		_outline_rect(c, sr, 0.8)
	_outline_rect(c, r, 1.5)

static func _rd_loadbay(c: CanvasItem, pr: Dictionary, npc: bool) -> void:
	var r: Rect2 = pr.r
	c.draw_colored_polygon(_rect_poly(r), _fill(PAD_C, npc))
	_outline_rect(c, r, 1.0)
	for i in 3:
		var dr := Rect2(r.position + Vector2(3 + i * 9, 3), Vector2(6.5, 10))
		c.draw_colored_polygon(_rect_poly(dr), _fill(MLT, npc))
		_outline_rect(c, dr, 0.9)

static func _rd_gable(c: CanvasItem, pr: Dictionary, rot: float, npc: bool) -> void:
	var r: Rect2 = pr.r
	c.draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.5)), _fill(_facet3(Vector2(0, -1), rot), npc))
	c.draw_rect(Rect2(r.position + Vector2(0, r.size.y * 0.5), Vector2(r.size.x, r.size.y * 0.5)), _fill(_facet3(Vector2(0, 1), rot), npc))
	c.draw_line(r.position + Vector2(0, r.size.y * 0.5), r.position + Vector2(r.size.x, r.size.y * 0.5), INK, 0.9, true)
	_outline_rect(c, r, 1.4)

static func _rd_tank(c: CanvasItem, pr: Dictionary, rot: float, npc: bool) -> void:
	var ctr: Vector2 = pr.c
	var r := float(pr.r)
	c.draw_circle(ctr, r, _fill(MLT, npc))
	c.draw_arc(ctr, r, 0.0, TAU, 28, INK, 1.4, true)
	c.draw_arc(ctr, r * 0.62, 0.0, TAU, 22, DK, 1.0, true)
	c.draw_arc(ctr, r * 0.75, deg_to_rad(208) - rot, deg_to_rad(262) - rot, 8, HI, 2.0, true)
	c.draw_circle(ctr, 1.6, INK)

static func _rd_sphere(c: CanvasItem, pr: Dictionary, rot: float, npc: bool) -> void:
	var ctr: Vector2 = pr.c
	var r := float(pr.r)
	c.draw_circle(ctr, r, _fill(MLT, npc))
	c.draw_arc(ctr, r, 0.0, TAU, 26, INK, 1.3, true)
	var seam := PackedVector2Array()
	for i in 13:
		var a := PI * float(i) / 12.0
		seam.append(ctr + Vector2(cos(a) * r, sin(a) * r * 0.45))
	c.draw_polyline(seam, DK, 0.9, true)
	var seam2 := PackedVector2Array()
	for i in 13:
		var a := -PI * 0.5 + PI * float(i) / 12.0
		seam2.append(ctr + Vector2(cos(a) * r * 0.45, sin(a) * r))
	c.draw_polyline(seam2, DK, 0.9, true)
	var off := (LIGHT_DIR * r * 0.5).rotated(-rot)
	c.draw_circle(ctr + off, r * 0.22, HI)

static func _rd_stack(c: CanvasItem, pr: Dictionary, rot: float, npc: bool) -> void:
	var ctr: Vector2 = pr.c
	var r := float(pr.r)
	c.draw_circle(ctr, r, _fill(LT, npc))
	c.draw_arc(ctr, r, 0.0, TAU, 24, INK, 1.4, true)
	c.draw_circle(ctr, r * 0.55, BORE)
	c.draw_arc(ctr, r * 0.85, deg_to_rad(197) - rot, deg_to_rad(260) - rot, 8, HI, 1.6, true)

static func _rd_vessel(c: CanvasItem, pr: Dictionary, rot: float, npc: bool) -> void:
	var ctr: Vector2 = pr.c
	var r := float(pr.r)
	c.draw_circle(ctr, r, _fill(MLT, npc))
	c.draw_arc(ctr, r, 0.0, TAU, 30, INK, 1.5, true)
	c.draw_circle(ctr, r * 0.72, _fill(MID, npc))
	c.draw_arc(ctr, r * 0.72, 0.0, TAU, 26, DK, 0.9, true)
	c.draw_arc(ctr, r * 0.8, deg_to_rad(207) - rot, deg_to_rad(261) - rot, 8, HI, 1.8, true)
	for i in 3:
		var a := -PI * 0.5 + float(i) * TAU / 3.0
		var rc := ctr + Vector2(cos(a), sin(a)) * r * 0.34
		c.draw_circle(rc, r * 0.16, BORE)
		c.draw_arc(rc, r * 0.16, 0.0, TAU, 12, INK, 0.7, true)

static func _rd_bar(c: CanvasItem, pr: Dictionary, npc: bool) -> void:
	var dirv := ((pr.b as Vector2) - (pr.a as Vector2)).normalized()
	var n := Vector2(-dirv.y, dirv.x) * float(pr.w) * 0.5
	var quad := PackedVector2Array([pr.a + n, pr.b + n, pr.b - n, pr.a - n])
	c.draw_colored_polygon(quad, _fill(LT, npc))
	var loop := quad.duplicate()
	loop.append(quad[0])
	c.draw_polyline(loop, INK, 1.1, true)

static func _rd_capsule(c: CanvasItem, pr: Dictionary, rot: float, npc: bool) -> void:
	var r: Rect2 = pr.r
	var hr := r.size.y * 0.5
	var ca := r.position + Vector2(hr, hr)
	var cb := Vector2(r.end.x - hr, r.position.y + hr)
	c.draw_circle(ca, hr, _fill(MLT, npc))
	c.draw_circle(cb, hr, _fill(MLT, npc))
	c.draw_rect(Rect2(r.position + Vector2(hr, 0), Vector2(r.size.x - hr * 2.0, r.size.y)), _fill(MLT, npc))
	var side := _lit_side(rot)
	var sy := r.position.y + hr + side * r.size.y * 0.17 - r.size.y * 0.17
	c.draw_rect(Rect2(Vector2(r.position.x + hr * 0.6, sy), Vector2(r.size.x - hr * 1.2, r.size.y * 0.34)), _fill(LT, npc))
	c.draw_line(Vector2(ca.x, r.position.y), Vector2(ca.x, r.end.y), DK, 0.8, true)
	c.draw_line(Vector2(cb.x, r.position.y), Vector2(cb.x, r.end.y), DK, 0.8, true)
	c.draw_arc(ca, hr, PI * 0.5, PI * 1.5, 12, INK, 1.3, true)
	c.draw_arc(cb, hr, -PI * 0.5, PI * 0.5, 12, INK, 1.3, true)
	c.draw_line(Vector2(ca.x, r.position.y), Vector2(cb.x, r.position.y), INK, 1.3, true)
	c.draw_line(Vector2(ca.x, r.end.y), Vector2(cb.x, r.end.y), INK, 1.3, true)

static func _rd_apse(c: CanvasItem, pr: Dictionary, npc: bool) -> void:
	var ctr: Vector2 = pr.c
	var r := float(pr.r)
	var pts := PackedVector2Array()
	for i in 13:
		var a := PI * float(i) / 12.0
		pts.append(ctr + Vector2(cos(a), sin(a)) * r)
	c.draw_colored_polygon(pts, _fill(MLT, npc))
	for k in range(1, 4):
		var a := float(k) * PI / 4.0
		c.draw_line(ctr, ctr + Vector2(cos(a), sin(a)) * r, DK, 0.8, true)
	var loop := pts.duplicate()
	loop.append(pts[0])
	c.draw_polyline(loop, INK, 1.3, true)

static func _rd_gable_v(c: CanvasItem, pr: Dictionary, rot: float, npc: bool) -> void:
	var r: Rect2 = pr.r
	c.draw_rect(Rect2(r.position, Vector2(r.size.x * 0.5, r.size.y)), _fill(_facet3(Vector2(-1, 0), rot), npc))
	c.draw_rect(Rect2(r.position + Vector2(r.size.x * 0.5, 0), Vector2(r.size.x * 0.5, r.size.y)), _fill(_facet3(Vector2(1, 0), rot), npc))
	c.draw_line(r.position + Vector2(r.size.x * 0.5, 0), r.position + Vector2(r.size.x * 0.5, r.size.y), INK, 0.9, true)
	_outline_rect(c, r, 1.4)

static func _rd_deck(c: CanvasItem, pr: Dictionary, rot: float, npc: bool) -> void:
	var r: Rect2 = pr.r
	c.draw_colored_polygon(_rect_poly(r), _fill(DECK, npc))
	var tick := Color(INK.r, INK.g, INK.b, 0.4)
	if bool(pr.vert):
		var yy := r.position.y + 5.0
		while yy < r.end.y - 2.0:
			c.draw_line(Vector2(r.position.x + 1.5, yy), Vector2(r.end.x - 1.5, yy), tick, 0.8, true)
			yy += 6.0
	else:
		var xx := r.position.x + 5.0
		while xx < r.end.x - 2.0:
			c.draw_line(Vector2(xx, r.position.y + 1.5), Vector2(xx, r.end.y - 1.5), tick, 0.8, true)
			xx += 6.0
	c.draw_rect(Rect2(r.position, Vector2(r.size.x, 1.6)), _fill(_facet3(Vector2(0, -1), rot), npc))
	_outline_rect(c, r, 1.2)

static func _rd_containers(c: CanvasItem, pr: Dictionary, npc: bool) -> void:
	var r: Rect2 = pr.r
	for i in int(pr.rows):
		for j in int(pr.cols):
			var cr := Rect2(r.position + Vector2(j * 8.3, i * 5.5), Vector2(7, 4.2))
			c.draw_colored_polygon(_rect_poly(cr), _fill(CONTAINER_COLS[(i + j) % 3], npc))
			_outline_rect(c, cr, 0.7)

static func _rd_unit(c: CanvasItem, pr: Dictionary, rot: float, npc: bool) -> void:
	var r: Rect2 = pr.r
	c.draw_colored_polygon(_rect_poly(r), _fill(MLT, npc))
	if _lit_side(rot) < 0.0:
		c.draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), _fill(LT, npc))
	else:
		c.draw_rect(Rect2(r.position + Vector2(0, r.size.y - 3), Vector2(r.size.x, 3)), _fill(LT, npc))
	_outline_rect(c, r, 0.9)
