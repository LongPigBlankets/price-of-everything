extends Node2D
## Look-dev contact sheet: the same authored wood drawn under each canopy-edge candidate,
## side by side and labelled. Windowed, but it boots NOTHING — no map, no fabric, no bake:
## it reads a few real outlines out of the authored document and draws trees straight onto
## this canvas. (The first attempt at this drove the whole game with the fabric bake bypassed
## and made the machine unresponsive; there is no reason to boot a map to look at a wood.)
##
##   <godot> --path . res://tools/forest_preview.tscn --quit-after 400
##
## The candidates live HERE rather than in authored_fabric_painter, so nothing that ships
## changes until a variant is chosen.

const TreeShapesRef := preload("res://scripts/tree_shapes.gd")
const RoadHash := preload("res://scripts/road_hash.gd")
const AuthoredMap := preload("res://scripts/authored_map.gd")
const Painter := preload("res://scripts/authored_fabric_painter.gd")

# Mirrors authored_fabric_painter's own constants, so "current" here is what the map draws.
const TREE_SPACING := 19.0
const MAX_DENSITY := 4.0
const TREE_EDGE_INSET := 1.0

const GRASS := Color(0.639, 0.702, 0.435)
const INK := Color(0.10, 0.13, 0.10, 0.85)
const LABEL_COL := Color(0.08, 0.10, 0.08)

const COLS := 4
const CELL := Vector2(430, 470)
const MARGIN := Vector2(20, 16)

## [name, spacing multiplier, edge wobble, feather depth, glade strength, gradient, blurb]
##   wobble    world units the tree line may wander OUTSIDE (or inside) the authored polygon
##   feather   how far in from the rim trees start being dropped (0 = today's hard edge)
##   glades    0..1 low-frequency thinning across the interior
##   gradient  0..1 dense-to-sparse fall-off ACROSS the wood, along a per-wood axis
const VARIANTS := [
	["current", 1.0, 0.0, 0.0, 0.0, 0.0, "ships today — the authored octagon, hard edge"],
	["wiggle", 1.0, 15.0, 0.0, 0.0, 0.0, "edge wanders +/-15u, still closed canopy"],
	["feather", 1.0, 7.0, 26.0, 0.0, 0.0, "soft rim: thins out over the last 26u"],
	["glades", 0.92, 9.0, 12.0, 0.55, 0.0, "denser, with clearings inside"],
	["soft", 1.0, 14.0, 22.0, 0.25, 0.0, "wander + soft rim + a few glades"],
	# Dense dropped (owner 2026-08-29): too close to the others to be worth a slot. Its
	# replacement is the one thing none of the others do — a wood that is NOT uniform: thick
	# at one end and thinning to an open scatter at the other, the way a real wood thins
	# toward an exposed edge. Spacing is the dense one; the gradient does the thinning.
	["graded", 0.74, 14.0, 18.0, 0.10, 0.88, "dense one end, sparse the other"],
	["sparse", 1.45, 16.0, 30.0, 0.35, 0.0, "open copse, dissolves at the edges"],
]

var _outlines: Array = []      # a few real authored woods, recentred on the origin
var _font: Font = null


func _ready() -> void:
	var w := int(MARGIN.x * 2 + CELL.x * COLS)
	var rows := int(ceil(float(VARIANTS.size()) / float(COLS)))
	var h := int(MARGIN.y * 2 + CELL.y * rows)
	DisplayServer.window_set_size(Vector2i(w, h))
	_font = ThemeDB.fallback_font
	_outlines = _load_outlines()
	print("[PREVIEW] outlines=%d  sheet=%dx%d" % [_outlines.size(), w, h])
	# Tree counts per variant, and for "graded" the split between the two halves along its
	# own axis — squinting at a contact sheet is not measurement.
	for spec: Array in VARIANTS:
		var total := 0
		var near := 0
		var far := 0
		for area: Dictionary in _outlines:
			var pts := _points(area, spec)
			total += pts.size()
			var ol: PackedVector2Array = area["outline"]
			var salt2 := RoadHash.fnv1a(str(area["id"])) & 0xFFFF
			var ws := float(salt2 % 977) * 0.031
			var ax := Vector2(cos(ws * 2.1), sin(ws * 2.1))
			var lo2 := INF
			var hi2 := -INF
			for q in ol:
				lo2 = minf(lo2, q.dot(ax))
				hi2 = maxf(hi2, q.dot(ax))
			for q2 in pts:
				if (q2.dot(ax) - lo2) / maxf(0.001, hi2 - lo2) < 0.5:
					near += 1
				else:
					far += 1
		print("[COUNT] %-9s trees=%4d  thick-half=%4d  thin-half=%4d  ratio=%.2f"
			% [str(spec[0]), total, near, far, float(far) / maxf(1.0, float(near))])
	queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/poe_forest_sheet.png")
	print("[PREVIEW] saved /tmp/poe_forest_sheet.png")
	get_tree().quit(0)


## Three real woods from the active document, recentred and scaled to fill a cell. Real
## outlines matter: the polygonal look IS the authored octagon, so a hand-drawn test shape
## would be answering a different question.
func _load_outlines() -> Array:
	var doc: Dictionary = AuthoredMap.data()
	var found: Array = []
	# `settlements` is keyed by name (a Dictionary), not a list — the editor saves each
	# settlement under its own key.
	var settlements: Dictionary = doc.get("settlements", {}) as Dictionary
	for key in settlements:
		var settlement: Dictionary = settlements[key] as Dictionary
		for area in (settlement.get("forests", []) as Array):
			found.append(area)
			if found.size() >= 3:
				break
		if found.size() >= 3:
			break
	var out: Array = []
	for area: Dictionary in found:
		var pts := PackedVector2Array()
		for entry in (area.get("outline", []) as Array):
			var v: Array = entry as Array
			if v != null and v.size() >= 2:
				pts.append(Vector2(float(v[0]), float(v[1])))
		if pts.size() < 3:
			continue
		var mid := Vector2.ZERO
		for p in pts:
			mid += p
		mid /= float(pts.size())
		var centred := PackedVector2Array()
		for p in pts:
			centred.append(p - mid)
		out.append({"id": str(area.get("id", "")), "outline": centred,
			"density": float(area.get("density", 1.0))})
	return out


func _draw() -> void:
	var rows := int(ceil(float(VARIANTS.size()) / float(COLS)))
	draw_rect(Rect2(Vector2.ZERO, MARGIN * 2 + Vector2(CELL.x * COLS, CELL.y * rows)), GRASS)
	for i in VARIANTS.size():
		var spec: Array = VARIANTS[i]
		var origin := MARGIN + Vector2(CELL.x * float(i % COLS), CELL.y * float(i / COLS))
		_draw_cell(origin, spec)


func _draw_cell(origin: Vector2, spec: Array) -> void:
	var title := str(spec[0])
	# Cell frame + caption.
	draw_rect(Rect2(origin, CELL - Vector2(10, 10)), Color(1, 1, 1, 0.05))
	draw_string(_font, origin + Vector2(12, 26), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, LABEL_COL)
	draw_string(_font, origin + Vector2(12, 46), str(spec[6]), HORIZONTAL_ALIGNMENT_LEFT,
		CELL.x - 24, 12, Color(LABEL_COL, 0.75))

	# Three woods stacked down the cell, at a scale where individual crowns read.
	var scale := 1.45
	var slots := [Vector2(CELL.x * 0.5, 150.0), Vector2(CELL.x * 0.30, 300.0),
		Vector2(CELL.x * 0.72, 390.0)]
	for k in mini(_outlines.size(), slots.size()):
		var area: Dictionary = _outlines[k]
		var at: Vector2 = origin + (slots[k] as Vector2)
		_draw_wood(area, at, scale, spec)


func _draw_wood(area: Dictionary, at: Vector2, scale: float, spec: Array) -> void:
	var outline: PackedVector2Array = area["outline"]
	# The authored polygon itself, faint — so the difference between the shape the designer
	# drew and the tree line that results is visible at a glance.
	var poly := PackedVector2Array()
	for p in outline:
		poly.append(at + p * scale)
	poly.append(poly[0])
	draw_polyline(poly, Color(0.35, 0.30, 0.20, 0.35), 1.0, true)

	for point in _points(area, spec):
		var key := "%s|tree|%.0f|%.0f" % [str(area["id"]), point.x, point.y]
		TreeShapesRef.draw_tree(self, TreeShapesRef.pick_kind(key, [55, 25, 20]),
			at + point * scale, key, scale)


## Straight through the shipping painter now that the variants live there — a second copy of
## the knobs in a look-dev tool is exactly how a preview starts lying about the game.
func _points(area: Dictionary, spec: Array) -> PackedVector2Array:
	var probe := area.duplicate(true)
	probe["variant"] = str(spec[0])
	probe["outline"] = _as_outline(area["outline"])
	return Painter.woodland_points(probe)


## The painter reads `outline` as an array of [x, y] pairs (document shape), while this tool
## keeps them as Vector2 for drawing.
func _as_outline(pts: PackedVector2Array) -> Array:
	var out: Array = []
	for p in pts:
		out.append([p.x, p.y])
	return out


## Smooth, continuous along an edge — that is what makes the tree line meander rather than
## dither tree by tree. Three incommensurate sines, roughly -1.6..1.6.
func _wobble(p: Vector2, salt: float) -> float:
	return sin(p.x * 0.055 + salt) * 0.6 \
		+ sin(p.y * 0.048 - salt * 1.7) * 0.6 \
		+ sin((p.x + p.y) * 0.031 + salt * 0.5) * 0.4


func _signed_depth(outline: PackedVector2Array, point: Vector2) -> float:
	var best := INF
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		best = minf(best, point.distance_to(Geometry2D.get_closest_point_to_segment(point, a, b)))
	return best if Geometry2D.is_point_in_polygon(point, outline) else -best


func _inside_by(outline: PackedVector2Array, point: Vector2, reach: float) -> bool:
	if not Geometry2D.is_point_in_polygon(point, outline):
		return false
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point, a, b)) < reach:
			return false
	return true


func _bounds(outline: PackedVector2Array) -> Rect2:
	var r := Rect2(outline[0], Vector2.ZERO)
	for p in outline:
		r = r.expand(p)
	return r
