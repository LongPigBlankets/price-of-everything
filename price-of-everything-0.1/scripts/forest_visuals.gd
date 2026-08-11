extends Node2D
## Draws forest buildings as blobby terrain patches instead of small icon slots.

const FOREST_BUILDING_IDS := {"b_015": true, "b_016": true}
const TILE_CENTER := Vector2(270, 240)
const HEX_VERTS: Array[Vector2] = [
	Vector2(135, 0), Vector2(405, 0), Vector2(540, 240),
	Vector2(405, 480), Vector2(135, 480), Vector2(0, 240),
]
const RIVER_POINTS := {
	"C0": Vector2(270, 240),
	"S1": Vector2(390, 120),
	"S2": Vector2(390, 360),
	"S3": Vector2(150, 360),
	"S4": Vector2(150, 120),
	"HSM1": Vector2(270, 0),
	"HSM2": Vector2(472.5, 120),
	"HSM3": Vector2(472.5, 360),
	"HSM4": Vector2(270, 480),
	"HSM5": Vector2(67.5, 360),
	"HSM6": Vector2(67.5, 120),
}

## Canopy colours live in MapStyle ('toggle ink' / 'toggle plate' swap them):
## classic and ink return these exact values, so both stay byte-identical.
const FOREST_SHADOW := Color(0.02, 0.10, 0.05, 0.28)
const Trees := preload("res://scripts/tree_shapes.gd")

## A forest is a BAKED SHAPE, not a cloud of blobs. Each one gets one outline
## polygon, computed once from its seeded footprint, and that outline is what
## defines the wood at every zoom — so a forest keeps a legible silhouette when
## the map is zoomed out, where individual trees would be sub-pixel noise.
## Close in, the same outline is filled with the map's three tree glyphs.
##
## Crucially the trees belong to the FOREST, not to the tile's scatter: a forest
## is itself a tile building, so nothing a player builds nearby can subtract them
## (building_visuals' scatter keeps out of these canopies instead).
enum Mass { ROUND, LONG, RHOMBOID }
const OUTLINE_STEPS := 26
## Draw individual trees only for forests within this much of the viewport, and
## only at the terrain's detail LOD.
const TREE_VIEW_PAD := 240.0
const FOREST_MAX_EDGES := 6        # a stand is a surveyed shape, not a circle
const FOREST_MIN_EDGE := 1.0       # sub-unit edges are invisible but still cost
const FOREST_MIN_PART_AREA := 260.0
const FOREST_BUILD_CLEAR := 5.0    # canopy keeps this off a footprint
const FOREST_ROAD_SPLIT := 15.0    # corridor half-width: a road cuts the wood
const FOREST_RIVER_SPLIT := 17.0
const RIVER_SCREEN_CLEARANCE_PX := 5.0
const RIVER_HALF_WIDTH := 7.5
# Canopy fill: a coarse jittered grid of large overlapping lobes (lobe > step so
# neighbours merge into a continuous mass). Coarse on purpose — a 10%-of-tile
# forest with a fine grid was ~80 circles; this is ~30, and the pattern itself is
# cached per (shape, variant) and reused across every forest of that kind.
const FOREST_FILL_STEP := 30.0
const FOREST_FILL_JITTER := 6.0
const FOREST_LOBE := 20.0
const FOREST_PATTERN_VARIANTS := 4
const SOURCE_LAKE_DEFAULT_WIDTH := 200.0
const SOURCE_LAKE_DEFAULT_HEIGHT := 150.0

@onready var terrain_layer: HexMap = get_node_or_null("%TerrainLayer") as HexMap
@onready var river_visuals: Node = get_node_or_null("../RiverVisuals")

var _forests: Dictionary = {}
var _river_paths_by_coord: Dictionary = {}
var _river_cache_ready: bool = false
# "kind:variant" -> Array[{off:Vector2, r:float, shade:float}]: the reusable
# canopy stamps (shape-local, unrotated), generated once.
var _pattern_cache: Dictionary = {}
var _outline_fp_version := -1
var _outline_cache: Dictionary = {}   # instance_id -> {poly, bb}: the baked silhouette
# instance_id -> {circles, shadow_r, mean_half, center}: the per-forest draw
# list, computed (incl. water/hex clipping) once and replayed on redraw.
var _draw_cache: Dictionary = {}
# World centres of every forested tile, for the gravitate-toward-neighbours pull.
var _neighbour_centers: Array = []
var _neighbour_dirty: bool = true
# Every forest's canopy + shadow is drawn as ONE MultiMesh (one draw call) and
# every highlight arc as ONE batched multiline — in GL-compat each draw_circle is
# its own draw call, so ~150 forests × ~25 lobes was thousands of draws/frame.
var _disc_mesh: Mesh = null
var _canopy_mm: MultiMesh = null
var _arc_pts: PackedVector2Array = PackedVector2Array()
var _mm_dirty: bool = true
var _bulk := false   # begin_bulk()/end_bulk() window (match-start placement)
var _white_tex: Texture2D = null

func _white_texture() -> Texture2D:
	if _white_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white_tex = ImageTexture.create_from_image(img)
	return _white_tex

func _ready() -> void:
	MapStyle.style_changed.connect(_on_style_changed)

## Canopy colours are baked into _draw_cache and then into the MultiMesh instance
## colours, so a style flip has to drop both.
func _on_style_changed() -> void:
	_draw_cache.clear()
	_outline_cache.clear()
	_mm_dirty = true
	queue_redraw()

func on_building_placed(tile_id: String, building_id: String, _recipe_id: String, instance_id: String, coord: Vector2i) -> void:
	if not FOREST_BUILDING_IDS.has(building_id):
		return
	var key: String = instance_id if instance_id != "" else "%s:%s" % [tile_id, building_id]
	_forests[key] = {
		"tile_id": tile_id,
		"building_id": building_id,
		"coord": coord,
	}
	# A new forest changes its neighbours' pull, so recompute centres next draw.
	_neighbour_dirty = true
	_mm_dirty = true
	if _bulk:
		return
	_draw_cache.clear()
	_outline_cache.clear()
	queue_redraw()


## Bulk window (match-start placement): defer the cache clear + redraw to end_bulk so
## placing ~145 start forests rebuilds the draw data once instead of once per forest.
func begin_bulk() -> void:
	_bulk = true


func end_bulk() -> void:
	_bulk = false
	_neighbour_dirty = true
	_draw_cache.clear()
	_outline_cache.clear()
	_mm_dirty = true
	queue_redraw()

func clear_all() -> void:
	_forests.clear()
	_draw_cache.clear()
	_outline_cache.clear()
	_neighbour_dirty = true
	_mm_dirty = true
	_river_paths_by_coord.clear()
	_river_cache_ready = false
	queue_redraw()

## True once this forest instance is tracked (and thus drawn). Forests never get a
## building_visuals footprint, so this is their equivalent of has_placement() — the
## start-building passes use it to skip re-emitting forests that already render.
func has_forest(instance_id: String) -> bool:
	return _forests.has(instance_id)

func remove_instance(instance_id: String) -> void:
	if not _forests.has(instance_id):
		return
	_forests.erase(instance_id)
	_neighbour_dirty = true
	_draw_cache.clear()
	_outline_cache.clear()
	_mm_dirty = true
	queue_redraw()

func _draw() -> void:
	if terrain_layer == null:
		return
	_ensure_river_cache()
	# Building footprints are a clip source, so a new building reshapes the wood.
	var bv0 := get_tree().get_first_node_in_group("building_footprints")
	var fpv: int = int(bv0.get("footprint_version")) if bv0 != null and "footprint_version" in bv0 else -1
	if fpv != _outline_fp_version:
		_outline_fp_version = fpv
		_outline_cache.clear()
	_ensure_canopy()
	# The baked outline is the wood at EVERY zoom — one filled polygon per forest,
	# so a zoomed-out map still shows a defined shape rather than a smear.
	var fill := MapStyle.forest_base()
	var edge := MapStyle.tree_outline()
	var shade := MapStyle.forest_lobe_dark()
	var detail := _detail_lod()
	var view := _view_rect()
	for instance_key in _forests.keys():
		var shape_data := _mass_outline(str(instance_key))
		var parts: Array = shape_data.get("parts", [])
		if parts.is_empty():
			continue
		if view.size.x > 0.0 and not view.intersects(shape_data.bb):
			continue
		# A stand cut by a road or river arrives here as SEVERAL parts; each is a
		# wood in its own right, with its own shadow and edge.
		for part in parts:
			var poly: PackedVector2Array = part
			if poly.size() < 3:
				continue
			draw_colored_polygon(_offset_poly(poly, Vector2(2.0, 3.0)), MapStyle.tree_shadow())
			draw_colored_polygon(poly, fill)
			var ring := poly.duplicate()
			ring.append(poly[0])
			draw_polyline(ring, edge, 1.4, true)
		if not detail:
			continue
		# Close in the mass is filled with the map's three trees. Positions come
		# from the SAME cached lobe pattern the far-zoom mass uses, so the wood
		# does not change shape when the trees appear.
		var data: Dictionary = _draw_cache.get(str(instance_key), {})
		for circle in (data.get("circles", []) as Array):
			var pos: Vector2 = circle.pos
			if not view.has_point(pos):
				continue
			if not _in_any_part(pos, parts):
				continue   # fell in the road/river cut, or under a building
			var key := "%s|%.0f_%.0f" % [str(instance_key), pos.x, pos.y]
			Trees.draw_tree(self, Trees.pick_kind(key, [4, 5, 3]), pos, key,
				clampf(float(circle.r) / 18.0, 0.7, 1.35))
		# A few darker crowns give the interior depth without a second pattern.
		for circle2 in (data.get("circles", []) as Array):
			var p2: Vector2 = circle2.pos
			if view.has_point(p2) and _in_any_part(p2, parts) and RoadHash.pick("fdark|%s|%.0f" % [str(instance_key), p2.x], 5) == 0:
				draw_colored_polygon(Trees.canopy(Trees.Kind.SMALL, p2, "fd|%.0f" % p2.x, 0.8), shade)

## The forest's baked silhouette: a straight-edged stand of at most
## FOREST_MAX_EDGES sides, then CLIPPED against what it must not cover.
##
## The two clip sources behave differently on purpose. A BUILDING is an
## obstruction the wood grows around, so its footprint is simply removed. A ROAD
## or RIVER is a cut THROUGH the wood, so clipping a corridor along it naturally
## leaves timber standing on both banks — one mechanism, two readings, and no
## special case for "the forest is split" because polygon clipping already
## returns the pieces.
##
## Returns {parts: Array[PackedVector2Array], bb: Rect2}. Cached per instance and
## dropped when the tile's footprints change.
func _mass_outline(instance_id: String) -> Dictionary:
	if _outline_cache.has(instance_id):
		return _outline_cache[instance_id]
	var entry: Dictionary = _forests.get(instance_id, {})
	var coord: Vector2i = entry.get("coord", Vector2i(-1, -1))
	var out := {"parts": [], "bb": Rect2()}
	if not terrain_layer.tiles.has(coord):
		return out
	var centre := _forest_center(instance_id, str(entry.get("tile_id", "")), coord)
	var shape := ForestFootprint.shape_for(instance_id, str(entry.get("tile_id", "")), centre)
	var hw := float(shape.hw)
	var hh := float(shape.hh)
	var rot := float(shape.rot)
	var mass := RoadHash.pick("fmass|%s" % instance_id, 3)
	if mass == Mass.LONG:
		hw *= 1.35
		hh *= 0.72
	# 4-6 straight sides, seeded, with per-corner radius variation so the stand
	# reads as surveyed timber rather than a regular polygon.
	var edges := 4 + RoadHash.pick("fedge|%s" % instance_id, FOREST_MAX_EDGES - 3)
	var base := PackedVector2Array()
	for i in edges:
		var a := TAU * float(i) / float(edges) + float(RoadHash.pick("fang|%s|%d" % [instance_id, i], 40)) / 300.0
		var ca := cos(a)
		var sa := sin(a)
		var rx := hw
		var ry := hh
		if mass == Mass.RHOMBOID:
			var m := absf(ca) + absf(sa)
			rx = hw / maxf(m, 0.42)
			ry = hh / maxf(m, 0.42)
		var w := 0.86 + float(RoadHash.pick("fout|%s|%d" % [instance_id, i], 100)) / 100.0 * 0.28
		base.append(centre + Vector2(ca * rx * w, sa * ry * w).rotated(rot))
	base = _drop_short_edges(base)
	if base.size() < 3:
		return out
	var parts: Array = [base]
	# Buildings: grow past the footprint so the canopy does not touch a wall.
	var bv := get_tree().get_first_node_in_group("building_footprints")
	if bv != null and bv.has_method("footprint_rects_on_tile"):
		for r in (bv.call("footprint_rects_on_tile", coord) as Array):
			parts = _clip_all(parts, _rect_poly((r as Rect2).grow(FOREST_BUILD_CLEAR)))
	# Roads and rivers: a corridor cut, which splits the stand in two.
	for seg in _corridors(coord, centre):
		parts = _clip_all(parts, seg)
	if parts.is_empty():
		_outline_cache[instance_id] = out
		return out
	var bb := Rect2((parts[0] as PackedVector2Array)[0], Vector2.ZERO)
	for part in parts:
		for p in (part as PackedVector2Array):
			bb = bb.expand(p)
	out = {"parts": parts, "bb": bb.grow(TREE_VIEW_PAD)}
	_outline_cache[instance_id] = out
	return out

## Subtract one clipper from every part, keeping only pieces worth drawing.
func _clip_all(parts: Array, clipper: PackedVector2Array) -> Array:
	var next: Array = []
	for part in parts:
		for piece in Geometry2D.clip_polygons(part as PackedVector2Array, clipper):
			var q := _drop_short_edges(piece)
			if q.size() >= 3 and absf(_poly_area(q)) >= FOREST_MIN_PART_AREA:
				next.append(q)
	return next

## Corridor quads along every road and river crossing the tile.
func _corridors(coord: Vector2i, centre: Vector2) -> Array:
	var out: Array = []
	_ensure_river_cache()
	for pts in (_river_paths_by_coord.get(coord, []) as Array):
		var rp: PackedVector2Array = pts
		for i in range(rp.size() - 1):
			out.append(_corridor(rp[i], rp[i + 1], FOREST_RIVER_SPLIT))
	var net := RoadNetwork.instance()
	if net != null:
		for edge_id in net.edges_on_tile(coord):
			var edge: Dictionary = net.edges.get(edge_id, {})
			if str(edge.get("state", "")) != RoadNetwork.STATE_BUILT:
				continue
			var geo: PackedVector2Array = edge.get("geometry", PackedVector2Array())
			for i2 in range(geo.size() - 1):
				if geo[i2].distance_to(centre) > 620.0:
					continue
				out.append(_corridor(geo[i2], geo[i2 + 1], FOREST_ROAD_SPLIT))
	return out

func _corridor(a: Vector2, b: Vector2, half: float) -> PackedVector2Array:
	var d := b - a
	if d.length() < 0.01:
		d = Vector2(1.0, 0.0)
	d = d.normalized()
	var n := Vector2(-d.y, d.x) * half
	var e := d * half   # square the ends off so consecutive corridors meet
	return PackedVector2Array([a + n - e, b + n + e, b - n + e, a - n - e])

func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, r.position + Vector2(r.size.x, 0), r.end, r.position + Vector2(0, r.size.y)])

## Enforce the minimum edge length: clipping and radial jitter both produce
## slivers, and a sub-unit edge is invisible detail that still costs vertices.
func _drop_short_edges(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in poly.size():
		var p: Vector2 = poly[i]
		if out.is_empty() or p.distance_to(out[out.size() - 1]) >= FOREST_MIN_EDGE:
			out.append(p)
	if out.size() >= 2 and out[0].distance_to(out[out.size() - 1]) < FOREST_MIN_EDGE:
		out.remove_at(out.size() - 1)
	return out

func _poly_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p: Vector2 = poly[i]
		var q: Vector2 = poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5

func _in_any_part(p: Vector2, parts: Array) -> bool:
	for part in parts:
		if Geometry2D.is_point_in_polygon(p, part as PackedVector2Array):
			return true
	return false

func _offset_poly(poly: PackedVector2Array, off: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(p + off)
	return out

## Same LOD gate the terrain and the tree scatter use — one zoom rule on the map.
func _detail_lod() -> bool:
	var hv := get_tree().get_first_node_in_group("hill_visuals")
	if hv == null or not hv.has_method("detail_lod"):
		return false
	return bool(hv.call("detail_lod"))

func _view_rect() -> Rect2:
	var vp := get_viewport()
	if vp == null:
		return Rect2()
	var size := vp.get_visible_rect().size
	if size.x <= 0.0:
		return Rect2()
	return (vp.get_canvas_transform().affine_inverse() * Rect2(Vector2.ZERO, size)).grow(TREE_VIEW_PAD)

## Build the canopy MultiMesh and batched arc lines from every forest's clipped
## draw data. Rebuilt only when forests change (rare); the GPU then redraws the
## whole canopy every frame as a single instanced draw.
func _ensure_canopy() -> void:
	if not _mm_dirty:
		return
	_mm_dirty = false
	var shadows: Array = []   # [pos, r]
	var lobes: Array = []     # [pos, r, color]
	_arc_pts = PackedVector2Array()
	# City plate: the canopy is a low park block on the shared light model. One
	# opaque shadow disc PER LOBE, offset SE — their union IS the offset canopy
	# silhouette for any footprint shape, where the single centre disc below
	# under-covers oblong woods (its radius is the MEAN half-extent).
	var plate := MapStyle.is_plate()
	var lobe_off := MapStyle.extrude_offset(MapStyle.Extrude.MILD)
	var lobe_side := MapStyle.extrude_side(MapStyle.forest_base(), MapStyle.Extrude.MILD)
	for instance_key in _forests.keys():
		var instance_id: String = str(instance_key)
		var entry: Dictionary = _forests[instance_id] as Dictionary
		var coord: Vector2i = entry.get("coord", Vector2i(-1, -1))
		if not terrain_layer.tiles.has(coord):
			continue
		var data: Dictionary = _forest_draw_data(instance_id, str(entry.get("tile_id", "")), coord)
		var circles: Array = data.circles
		if circles.is_empty():
			continue
		if plate:
			for circle in circles:
				shadows.append([circle.pos + lobe_off, float(circle.r)])
		else:
			shadows.append([data.center + Vector2(0, 3.0), float(data.shadow_r)])
		for circle in circles:
			lobes.append([circle.pos, float(circle.r), circle.color])
		_append_arc_segments(data.center, float(data.mean_half), instance_id, coord)

	# The baked outline is the mass now, so the lobe MultiMesh is no longer drawn
	# — building it would cost instances that nothing renders. The loop above is
	# kept purely because it fills _draw_cache, which is where the close-zoom
	# tree positions come from.
	return

	if _disc_mesh == null:
		_disc_mesh = _build_disc_mesh(16)
	if _canopy_mm == null:
		_canopy_mm = MultiMesh.new()
		_canopy_mm.transform_format = MultiMesh.TRANSFORM_2D
		_canopy_mm.use_colors = true
		_canopy_mm.mesh = _disc_mesh
	# Shadows first (drawn behind), then lobes — instances render in index order.
	_canopy_mm.instance_count = shadows.size() + lobes.size()
	var idx := 0
	for s in shadows:
		_canopy_mm.set_instance_transform_2d(idx, _disc_xform(s[0], float(s[1])))
		_canopy_mm.set_instance_color(idx, lobe_side if plate else FOREST_SHADOW)
		idx += 1
	for l in lobes:
		_canopy_mm.set_instance_transform_2d(idx, _disc_xform(l[0], float(l[1])))
		_canopy_mm.set_instance_color(idx, l[2])
		idx += 1

func _disc_xform(pos: Vector2, r: float) -> Transform2D:
	return Transform2D(Vector2(r, 0.0), Vector2(0.0, r), pos)

func _build_disc_mesh(seg: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	verts.append(Vector3.ZERO)
	for i in seg + 1:
		var a := TAU * float(i) / float(seg)
		verts.append(Vector3(cos(a), sin(a), 0.0))
	var indices := PackedInt32Array()
	for i in seg:
		indices.append_array([0, 1 + i, 2 + i])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m

## Tessellate this forest's highlight arc into disjoint segments appended to the
## shared _arc_pts buffer (drawn together as one multiline).
func _append_arc_segments(center: Vector2, mean_half: float, instance_id: String, coord: Vector2i) -> void:
	if not _circle_drawable(center, 10.0, coord):
		return
	var radius: float = maxf(10.0, mean_half * 0.55)
	var start: float = float(_seed(instance_id + "|arc") % 628) / 100.0
	var origin := center + Vector2(-2.0, -mean_half * 0.18)
	var steps := 14
	var prev := origin + Vector2(cos(start), sin(start)) * radius
	for i in range(1, steps + 1):
		var a := start + 1.7 * float(i) / float(steps)
		var p := origin + Vector2(cos(a), sin(a)) * radius
		_arc_pts.append(prev)
		_arc_pts.append(p)
		prev = p

## Build (and cache) the clipped draw list for one forest: canopy circles, the
## shadow radius and centre — water/hex clipping done once, reused on rebuild.
func _forest_draw_data(instance_id: String, tile_id: String, coord: Vector2i) -> Dictionary:
	if _draw_cache.has(instance_id):
		return _draw_cache[instance_id]
	var center: Vector2 = _forest_center(instance_id, tile_id, coord)
	var shape: Dictionary = ForestFootprint.shape_for(instance_id, tile_id, center)
	var mean_half: float = (float(shape.hw) + float(shape.hh)) * 0.5
	var visible_circles: Array = []
	for circle in _forest_circles(instance_id, center, shape):
		if _circle_drawable(circle.pos, float(circle.r), coord):
			visible_circles.append(circle)
	if visible_circles.is_empty() and _circle_drawable(center, 18.0, coord):
		visible_circles.append({"pos": center, "r": 18.0, "color": MapStyle.forest_base()})
	visible_circles.sort_custom(_sort_circle_radius_desc)
	var data := {
		"circles": visible_circles,
		"shadow_r": mean_half * 0.92,
		"mean_half": mean_half,
		"center": center,
	}
	_draw_cache[instance_id] = data
	return data

## World-space avoidance discs {center, radius} for every forest on `coord`,
## matching the drawn blob exactly (same _forest_center + circumscribing radius).
## The polygon building layout keeps footprints out of these so a building never
## lands under a canopy. Cheap — only the forests actually on this tile.
func discs_on_tile(coord: Vector2i) -> Array:
	var out: Array = []
	for key in _forests:
		var e: Dictionary = _forests[key]
		if (e.get("coord", Vector2i(-1, -1)) as Vector2i) != coord:
			continue
		var tid := str(e.get("tile_id", ""))
		var center := _forest_center(str(key), tid, coord)
		var shape := ForestFootprint.shape_for(str(key), tid, center)
		out.append({"center": center, "radius": float(shape.radius)})
	return out

func _forest_center(instance_id: String, tile_id: String, coord: Vector2i) -> Vector2:
	# Delegates to ForestFootprint so the drawn blob and the road/occupancy
	# obstacle disc can never diverge (roads-v2 spec section 1).
	_ensure_river_cache()
	var paths: Array = _river_paths_by_coord.get(coord, [])
	return ForestFootprint._center(instance_id, tile_id, _tile_center(coord), paths,
		_lake_for_coord(coord), _forest_neighbour_centers())

## World centres of every forested tile (cached), for the gravitate-toward pull.
func _forest_neighbour_centers() -> Array:
	if not _neighbour_dirty:
		return _neighbour_centers
	_neighbour_centers = []
	for key in _forests:
		var coord: Vector2i = (_forests[key] as Dictionary).get("coord", Vector2i(-1, -1))
		if terrain_layer != null and terrain_layer.tiles.has(coord):
			_neighbour_centers.append(_tile_center(coord))
	_neighbour_dirty = false
	return _neighbour_centers

func _lake_for_coord(coord: Vector2i) -> Dictionary:
	if terrain_layer == null or not terrain_layer.tiles.has(coord):
		return {}
	return RiverGeometry.lake_ellipse(terrain_layer.tiles[coord], terrain_layer.river_properties, _tile_center(coord))

func _sort_circle_radius_desc(a: Dictionary, b: Dictionary) -> bool:
	return float(a.get("r", 0.0)) > float(b.get("r", 0.0))

func _forest_circles(instance_id: String, center: Vector2, shape: Dictionary) -> Array:
	# Place a cached canopy stamp (shape-local lobes) at this forest's centre and
	# rotation. The stamp is generated once per (shape kind, variant) and reused.
	var kind: String = str(shape.get("kind", "circle"))
	var rot: float = float(shape.get("rot", 0.0))
	var variant: int = abs(hash(instance_id)) % FOREST_PATTERN_VARIANTS
	var pattern: Array = _canopy_pattern(kind, variant, float(shape.hw), float(shape.hh))
	var base := MapStyle.forest_base()
	var dark := MapStyle.forest_lobe_dark()
	var circles: Array = []
	for lobe in pattern:
		circles.append({
			"pos": center + (lobe.off as Vector2).rotated(rot),
			"r": float(lobe.r),
			"color": base.lerp(dark, float(lobe.shade)),
		})
	return circles

func _canopy_pattern(kind: String, variant: int, hw: float, hh: float) -> Array:
	var key := "%s:%d" % [kind, variant]
	if _pattern_cache.has(key):
		return _pattern_cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed(key)
	var pattern: Array = []
	var y: float = -hh
	while y <= hh + 0.01:
		var x: float = -hw
		while x <= hw + 0.01:
			var lx: float = x + rng.randf_range(-FOREST_FILL_JITTER, FOREST_FILL_JITTER)
			var ly: float = y + rng.randf_range(-FOREST_FILL_JITTER, FOREST_FILL_JITTER)
			if _in_forest_shape(kind, lx, ly, hw, hh):
				pattern.append({
					"off": Vector2(lx, ly),
					"r": FOREST_LOBE * rng.randf_range(0.85, 1.18),
					"shade": rng.randf_range(0.0, 0.28),
				})
			x += FOREST_FILL_STEP
		y += FOREST_FILL_STEP
	_pattern_cache[key] = pattern
	return pattern

func _in_forest_shape(kind: String, lx: float, ly: float, hw: float, hh: float) -> bool:
	match kind:
		"square", "rectangle":
			return absf(lx) <= hw and absf(ly) <= hh
		"patch":
			# chamfered/rounded rectangle
			if absf(lx) > hw or absf(ly) > hh:
				return false
			var cut: float = minf(hw, hh) * 0.5
			var ox: float = absf(lx) - (hw - cut)
			var oy: float = absf(ly) - (hh - cut)
			if ox > 0.0 and oy > 0.0:
				return ox * ox + oy * oy <= cut * cut
			return true
		"blob":
			var ang: float = atan2(ly, lx)
			var wob: float = 0.82 + 0.18 * sin(ang * 3.0 + 1.3) + 0.08 * sin(ang * 5.0 - 0.6)
			return (lx / hw) * (lx / hw) + (ly / hh) * (ly / hh) <= wob * wob
		_:  # circle
			return (lx / hw) * (lx / hw) + (ly / hh) * (ly / hh) <= 1.0

func _circle_drawable(pos: Vector2, radius: float, coord: Vector2i) -> bool:
	if not _inside_hex(pos, _tile_center(coord), 14.0):
		return false
	var clearance: float = radius + RIVER_HALF_WIDTH + _river_clearance_world()
	if _water_clearance_score(pos, coord) < clearance:
		return false
	return _clear_of_source_lake(pos, radius, coord)

func _water_clearance_score(point: Vector2, coord: Vector2i) -> float:
	var best: float = INF
	var paths: Array = _river_paths_by_coord.get(coord, [])
	for path_data in paths:
		var pts: PackedVector2Array = path_data
		for i in range(pts.size() - 1):
			best = minf(best, _distance_to_segment(point, pts[i], pts[i + 1]))
	return best

func _clear_of_source_lake(point: Vector2, radius: float, coord: Vector2i) -> bool:
	if terrain_layer == null or not terrain_layer.tiles.has(coord):
		return true
	var tile_data: Dictionary = terrain_layer.tiles[coord]
	if not bool(tile_data.get("has_river", false)):
		return true
	var river_type: String = str(tile_data.get("river_type", ""))
	if river_type == "" or not terrain_layer.river_properties.has(river_type):
		return true
	var river_data: Dictionary = terrain_layer.river_properties[river_type]
	if str(river_data.get("kind", "")) != "source":
		return true
	var lake_point: String = str(river_data.get("lake_point", "C0"))
	if not RIVER_POINTS.has(lake_point):
		return true
	var lake_offset: Vector2 = RIVER_POINTS[lake_point]
	var lake_center: Vector2 = _tile_center(coord) + lake_offset - TILE_CENTER
	var lake_w: float = _float_or_default(str(river_data.get("lake_width", "")), SOURCE_LAKE_DEFAULT_WIDTH)
	var lake_h: float = _float_or_default(str(river_data.get("lake_height", "")), SOURCE_LAKE_DEFAULT_HEIGHT)
	var clearance: float = _river_clearance_world() + radius
	var dx: float = (point.x - lake_center.x) / (lake_w * 0.5 + clearance)
	var dy: float = (point.y - lake_center.y) / (lake_h * 0.5 + clearance)
	return Vector2(dx, dy).length() >= 1.0

func _ensure_river_cache() -> void:
	if _river_cache_ready:
		return
	if river_visuals == null:
		river_visuals = get_node_or_null("../RiverVisuals")
	_river_paths_by_coord.clear()
	if river_visuals != null and river_visuals.has_method("get_river_polylines"):
		var river_paths: Array = river_visuals.call("get_river_polylines") as Array
		for entry in river_paths:
			var path_entry: Dictionary = entry as Dictionary
			var coord: Vector2i = path_entry.get("coord", Vector2i(-1, -1))
			if not _river_paths_by_coord.has(coord):
				_river_paths_by_coord[coord] = []
			var points: PackedVector2Array = path_entry.get("points", PackedVector2Array())
			_river_paths_by_coord[coord].append(points)
	_river_cache_ready = true

func _inside_hex(point: Vector2, tile_center: Vector2, margin: float) -> bool:
	var local: Vector2 = point - tile_center + TILE_CENTER
	var inset: PackedVector2Array = PackedVector2Array()
	for vertex in HEX_VERTS:
		var from_center: Vector2 = vertex - TILE_CENTER
		inset.append(TILE_CENTER + from_center.normalized() * maxf(0.0, from_center.length() - margin))
	return Geometry2D.is_point_in_polygon(local, inset)

func _tile_center(coord: Vector2i) -> Vector2:
	if terrain_layer == null:
		return Vector2.ZERO
	return terrain_layer.map_to_local(terrain_layer.map_coord_for_tile_coord(coord))

func _river_clearance_world() -> float:
	var zoom_max: float = 1.0
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam != null:
		var value: Variant = cam.get("zoom_max")
		if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
			zoom_max = maxf(float(value), 0.01)
	return RIVER_SCREEN_CLEARANCE_PX / zoom_max

func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var denom: float = ab.length_squared()
	if denom <= 0.0001:
		return point.distance_to(a)
	var t: float = clampf((point - a).dot(ab) / denom, 0.0, 1.0)
	return point.distance_to(a + ab * t)

func _seed(text: String) -> int:
	return abs(hash(text))

func _float_or_default(value: String, fallback: float) -> float:
	if value == "":
		return fallback
	return float(value)
