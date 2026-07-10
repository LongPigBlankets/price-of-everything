extends Node2D
## Draws the baked hill contours (data/hills_baked.json) as stacked OS-relief
## bands. The map is hand-painted and never changes during a match, so at load
## we render the ~1,300 contour polygons into ONE texture (a SubViewport bake)
## and from then on draw that single texture every frame — turning ~4,100 draw
## calls + 1.8M primitives per frame into one textured quad. Sits between
## TerrainLayer and RiverLayer; rivers always draw over the hills.

## band = level + 1: [0] = lv -1 sub-sea depressions (muted deep green);
## [1] = lv 0 coastal sand; [2..6] = lv 1-5 muted grass-green -> khaki;
## [7..10] = lv 6-9 tan into warm brown; [11] = lv 10 snow-white peaks.
## Muted hypsometric relief ramp (physical-atlas look): desaturated earth
## tones, less vivid than the old lime/gold scheme; peaks stay white.
const BAND_COLORS: Array[Color] = [
	Color("28401f"),
	Color("d9cda2"),
	Color("5e7d44"),
	Color("6c874d"),
	Color("7e955c"),
	Color("9aa771"),
	Color("bebd8b"),
	Color("c9b384"),
	Color("bd9c69"),
	Color("a17e50"),
	Color("7d5c3a"),
	Color(1.0, 1.0, 1.0),
]
const OUTLINE_DARKEN := 0.22
const OUTLINE_WIDTH := 1.5
## Same blue as RiverVisuals.RIVER_COLOR — lakes and the coastal shelf read
## as river water.
const WATER_COLOR := Color(0.17647059, 0.40784314, 0.76862745, 1.0)
## Sea band fills, indexed by the baked sea band: lv -6 (DS navy BG_PANEL)
## up to the shelf, then the sandy land base the terrain bands sit on (matches
## the lv-0 coastal band so gaps/coastlines don't flash bright cream).
const SEA_COLORS: Array[Color] = [
	Color("000d94"),
	Color("000dc2"),
	Color("194ba9"),
	Color("24549e"),
	Color(0.17647059, 0.40784314, 0.76862745),
	Color("d9cda2"),
]
## Longest side of the baked terrain texture, in pixels. The map is ~12,950 ×
## 10,500 world units; 4096 keeps it crisp at the default view, for ~54 MB of
## VRAM. The texture is only ever shown ZOOMED OUT now (where its softness is
## invisible) — zoomed in, the real vector polygons are drawn (perfectly crisp).
const BAKE_LONG_SIDE := 4096.0
## Hybrid LOD: when no more than this many contour polygons are on screen, draw
## the real vectors (crisp at any zoom); above it, draw the baked texture (one
## draw call). At max zoom only a handful of tiles are visible, so the vector
## path is cheap; the crossover lands at a moderate zoom-out.
const VECTOR_CAP := 450
const CULL_MARGIN := 320.0   # world units; keep partially-visible polys

enum { MODE_TEXTURE, MODE_VECTOR }

var _polys: Array = []
var _lakes: Array = []
var _sea: Array = []
var _poly_bb: Array = []     # parallel Rect2 bbox per _polys entry
var _sea_bb: Array = []
var _lake_bb: Array = []
var _baked_tex: Texture2D = null
var _bake_rect: Rect2 = Rect2()
var _mode := MODE_TEXTURE
var _view_rect := Rect2()
# Lazily-triangulated fill meshes, keyed "p<i>"/"s<i>"/"l<i>". draw_colored_polygon
# re-triangulates a concave polygon EVERY call (marching-squares contours have
# hundreds of verts) — that was 1 fps at max zoom. A cached mesh triangulates
# once, then draw_mesh just renders the tris. null entry = triangulation failed
# (fall back to draw_colored_polygon for that poly).
var _mesh_cache: Dictionary = {}
var _white_tex: Texture2D = null

func _white_texture() -> Texture2D:
	if _white_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white_tex = ImageTexture.create_from_image(img)
	return _white_tex

var _bake_deferred := false   # the far-zoom texture bake is pending; built lazily on first need
var _meshes_warm := false     # _warm_all_meshes() done → the cached-mesh vector LOD is usable

func _enter_tree() -> void:
	# the 'toggle heightmap' debug cheat flips visibility on this group
	add_to_group("hill_visuals")

func _ready() -> void:
	_polys = HillBaked.polys()
	_lakes = HillBaked.lakes()
	_sea = HillBaked.sea()
	_poly_bb = _bboxes(_polys, true)
	_sea_bb = _bboxes(_sea, true)
	_lake_bb = _bboxes(_lakes, false)
	_bake_rect = _compute_bounds()
	await _warm_all_meshes()   # triangulate every contour ONCE (spread across frames during a bg build)
	_meshes_warm = true        # the vector LOD can now draw cached meshes (no bake needed for it)
	queue_redraw()
	# The far-zoom texture LOD's bake is a big one-frame GPU render of every hill. Build it LAZILY
	# the first time a zoomed-out view actually needs it (see _process), never during the load — so
	# it can't freeze the loading screen. Headless has no GPU; it draws polys directly.
	if DisplayServer.get_name() != "headless":
		_bake_deferred = true

func _bboxes(coll: Array, has_p_key: bool) -> Array:
	var out: Array = []
	for entry in coll:
		var pts: PackedVector2Array = entry.p if has_p_key else entry
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		for p in pts:
			mn = mn.min(p)
			mx = mx.max(p)
		out.append(Rect2(mn, mx - mn) if mn.x != INF else Rect2())
	return out

## Pick the LOD each frame: count on-screen contour polygons; below the cap draw
## crisp vectors (and redraw as the camera moves), above it the baked texture.
func _process(_delta: float) -> void:
	if not visible or not _meshes_warm:
		return
	var view := _visible_world_rect()
	var visible_polys := _count_visible(_poly_bb, view) + _count_visible(_sea_bb, view) + _count_visible(_lake_bb, view)
	var want := MODE_VECTOR if visible_polys <= VECTOR_CAP else MODE_TEXTURE
	if want == MODE_TEXTURE and _baked_tex == null:
		# First zoomed-out view: build the texture LOD now (it wasn't baked during the load). Keep
		# drawing the cached vector meshes until it lands a couple of frames later.
		if _bake_deferred:
			_bake_deferred = false
			_bake_to_texture()
		want = MODE_VECTOR
	if want != _mode:
		_mode = want
		_view_rect = view
		queue_redraw()
	elif want == MODE_VECTOR and view != _view_rect:
		_view_rect = view   # camera moved while zoomed in — recull next draw
		queue_redraw()

func _draw() -> void:
	if not _meshes_warm:
		_draw_polys_direct()   # headless, or before the cached meshes finish building (covered by the loading screen)
		return
	if _mode == MODE_TEXTURE and _baked_tex != null:
		draw_texture_rect(_baked_tex, _bake_rect, false)
	else:
		_draw_culled_meshes(_view_rect)   # cached vector meshes — works without the bake

func _visible_world_rect() -> Rect2:
	var vp := get_viewport()
	if vp == null:
		return Rect2()
	var size := vp.get_visible_rect().size
	if size.x <= 0.0:
		return Rect2()
	var world := vp.get_canvas_transform().affine_inverse() * Rect2(Vector2.ZERO, size)
	return world.grow(CULL_MARGIN)

func _count_visible(bboxes: Array, view: Rect2) -> int:
	var n := 0
	for bb in bboxes:
		if view.intersects(bb):
			n += 1
	return n

func _compute_bounds() -> Rect2:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for coll in [_sea, _polys]:
		for entry in coll:
			for p in entry.p:
				mn = mn.min(p)
				mx = mx.max(p)
	for lk in _lakes:
		for p in lk:
			mn = mn.min(p)
			mx = mx.max(p)
	if mn.x == INF:
		return Rect2()
	return Rect2(mn, mx - mn)

## Render every contour into an off-screen SubViewport once, copy it into a
## standalone ImageTexture, then free the viewport.
func _bake_to_texture() -> void:
	var size := _bake_rect.size
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var scale: float = BAKE_LONG_SIDE / maxf(size.x, size.y)
	var tex_w := int(ceil(size.x * scale))
	var tex_h := int(ceil(size.y * scale))
	var vp := SubViewport.new()
	vp.size = Vector2i(tex_w, tex_h)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	var painter := HillPainter.new()
	painter.configure(_sea, _polys, _lakes, _bake_rect.position, scale,
		SEA_COLORS, BAND_COLORS, WATER_COLOR, OUTLINE_DARKEN, OUTLINE_WIDTH,
		_mesh_cache, _white_texture())
	vp.add_child(painter)
	# Let the viewport render its single frame, then grab the pixels.
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if img != null and not img.is_empty():
		_baked_tex = ImageTexture.create_from_image(img)
	vp.queue_free()
	queue_redraw()

## Zoomed-in vector LOD: draw only polygons whose bbox is on screen, using
## cached pre-triangulated meshes (no per-frame triangulation) + non-AA
## outlines (AA polylines on huge contours were also a per-frame cost).
func _draw_culled_meshes(cull: Rect2) -> void:
	var white := _white_texture()
	for i in _sea.size():
		if not cull.intersects(_sea_bb[i]):
			continue
		var spts: PackedVector2Array = _sea[i].p
		if spts.size() < 3:
			continue
		_draw_fill("s%d" % i, spts, SEA_COLORS[clampi(_sea[i].b, 0, SEA_COLORS.size() - 1)], white)
	for i in _polys.size():
		if not cull.intersects(_poly_bb[i]):
			continue
		var pts: PackedVector2Array = _polys[i].p
		if pts.size() < 3:
			continue
		var color: Color = BAND_COLORS[clampi(_polys[i].b, 0, BAND_COLORS.size() - 1)]
		_draw_fill("p%d" % i, pts, color, white)
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, color.darkened(OUTLINE_DARKEN), OUTLINE_WIDTH, false)
	for i in _lakes.size():
		if not cull.intersects(_lake_bb[i]):
			continue
		var lake_pts: PackedVector2Array = _lakes[i]
		if lake_pts.size() < 3:
			continue
		_draw_fill("l%d" % i, lake_pts, WATER_COLOR, white)
		var shore := lake_pts.duplicate()
		shore.append(lake_pts[0])
		draw_polyline(shore, WATER_COLOR.darkened(0.25), 2.0, false)

## Triangulate every fill polygon once (load-time, ~tens of ms — the old direct
## draw triangulated all of these EVERY frame), so panning only ever draws
## already-built meshes.
func _warm_all_meshes() -> void:
	if DisplayServer.get_name() == "headless":
		return   # tests never render the vector LOD; skip the triangulation cost
	# Triangulating every contour is ~2 s of work, and a fixed contour-count batch is uneven (a few
	# huge contours dominate, giving a ~2 s frame). During a background build (loading screen up)
	# hand a frame back whenever ~35 ms have accumulated, so it spreads into smooth ~35 ms slices.
	# (Time only paces the yields; the meshes built are identical/deterministic.)
	var t_last := Time.get_ticks_msec()
	for i in _sea.size():
		if (_sea[i].p as PackedVector2Array).size() >= 3:
			_build_fill_mesh("s%d" % i, _sea[i].p)
		if Time.get_ticks_msec() - t_last > 35:
			await LoadPacing.bg_yield()
			t_last = Time.get_ticks_msec()
	for i in _polys.size():
		if (_polys[i].p as PackedVector2Array).size() >= 3:
			_build_fill_mesh("p%d" % i, _polys[i].p)
		if Time.get_ticks_msec() - t_last > 35:
			await LoadPacing.bg_yield()
			t_last = Time.get_ticks_msec()
	for i in _lakes.size():
		if (_lakes[i] as PackedVector2Array).size() >= 3:
			_build_fill_mesh("l%d" % i, _lakes[i])
		if Time.get_ticks_msec() - t_last > 35:
			await LoadPacing.bg_yield()
			t_last = Time.get_ticks_msec()

func _draw_fill(key: String, pts: PackedVector2Array, color: Color, white: Texture2D) -> void:
	var mesh: Mesh = _mesh_cache.get(key, null) if _mesh_cache.has(key) else _build_fill_mesh(key, pts)
	if mesh != null:
		draw_mesh(mesh, white, Transform2D.IDENTITY, color)
	else:
		draw_colored_polygon(pts, color)   # triangulation failed — rare

func _build_fill_mesh(key: String, pts: PackedVector2Array) -> Mesh:
	var idx := Geometry2D.triangulate_polygon(pts)
	var mesh: ArrayMesh = null
	if not idx.is_empty():
		var verts := PackedVector3Array()
		verts.resize(pts.size())
		for i in pts.size():
			verts[i] = Vector3(pts[i].x, pts[i].y, 0.0)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_INDEX] = idx
		mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh_cache[key] = mesh
	return mesh

## Draw the contour polygons directly. `cull` (when sized) keeps only polygons
## whose bbox intersects it — the zoomed-in vector LOD; an empty rect draws all
## (headless / pre-bake fallback).
func _draw_polys_direct(cull: Rect2 = Rect2()) -> void:
	var culling := cull.size.x > 0.0
	for i in _sea.size():
		if culling and not cull.intersects(_sea_bb[i]):
			continue
		var spts: PackedVector2Array = _sea[i].p
		if spts.size() < 3:
			continue
		var sband: int = clampi(_sea[i].b, 0, SEA_COLORS.size() - 1)
		draw_colored_polygon(spts, SEA_COLORS[sband])
	for i in _polys.size():
		if culling and not cull.intersects(_poly_bb[i]):
			continue
		var pts: PackedVector2Array = _polys[i].p
		if pts.size() < 3:
			continue
		var band: int = clampi(_polys[i].b, 0, BAND_COLORS.size() - 1)
		var color: Color = BAND_COLORS[band]
		draw_colored_polygon(pts, color)
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, color.darkened(OUTLINE_DARKEN), OUTLINE_WIDTH, true)
	for i in _lakes.size():
		if culling and not cull.intersects(_lake_bb[i]):
			continue
		var lake_pts: PackedVector2Array = _lakes[i]
		if lake_pts.size() < 3:
			continue
		draw_colored_polygon(lake_pts, WATER_COLOR)
		var shore: PackedVector2Array = lake_pts.duplicate()
		shore.append(lake_pts[0])
		draw_polyline(shore, WATER_COLOR.darkened(0.25), 2.0, true)

## Node2D that paints the contours into the bake SubViewport in texture space
## (world point -> (p - origin) * scale). Line widths stay in texture pixels so
## the OS-relief band outlines survive the downscale.
class HillPainter:
	extends Node2D
	var _sea: Array
	var _polys: Array
	var _lakes: Array
	var _origin: Vector2
	var _scale: float
	var _sea_colors: Array
	var _band_colors: Array
	var _water: Color
	var _outline_darken: float
	var _outline_width: float
	var _meshes: Dictionary       # pre-triangulated fill meshes (keyed s%d/p%d/l%d) so the bake
	var _white: Texture2D         # draws cached meshes instead of re-triangulating every contour

	func configure(sea: Array, polys: Array, lakes: Array, origin: Vector2, scale: float,
			sea_colors: Array, band_colors: Array, water: Color, outline_darken: float, outline_width: float,
			meshes: Dictionary, white: Texture2D) -> void:
		_sea = sea
		_polys = polys
		_lakes = lakes
		_origin = origin
		_scale = scale
		_sea_colors = sea_colors
		_band_colors = band_colors
		_water = water
		_outline_darken = outline_darken
		_outline_width = outline_width
		_meshes = meshes
		_white = white

	func _to_tex(pts: PackedVector2Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		out.resize(pts.size())
		for i in pts.size():
			out[i] = (pts[i] - _origin) * _scale
		return out

	func _draw() -> void:
		# Draw the already-triangulated cached meshes (transformed world→texture) instead of
		# draw_colored_polygon, which re-triangulates every contour (~2 s for the whole map).
		var xform := Transform2D(Vector2(_scale, 0.0), Vector2(0.0, _scale), -_origin * _scale)
		for i in _sea.size():
			var spts: PackedVector2Array = _sea[i].p
			if spts.size() < 3:
				continue
			_fill("s%d" % i, spts, _sea_colors[clampi(_sea[i].b, 0, _sea_colors.size() - 1)], xform)
		for i in _polys.size():
			var pts: PackedVector2Array = _polys[i].p
			if pts.size() < 3:
				continue
			var color: Color = _band_colors[clampi(_polys[i].b, 0, _band_colors.size() - 1)]
			_fill("p%d" % i, pts, color, xform)
			var outline := _to_tex(pts)
			outline.append(outline[0])
			draw_polyline(outline, color.darkened(_outline_darken), _outline_width, true)
		for i in _lakes.size():
			var lake_pts: PackedVector2Array = _lakes[i]
			if lake_pts.size() < 3:
				continue
			_fill("l%d" % i, lake_pts, _water, xform)
			var shore := _to_tex(lake_pts)
			shore.append(shore[0])
			draw_polyline(shore, _water.darkened(0.25), 2.0, true)

	func _fill(key: String, pts: PackedVector2Array, color: Color, xform: Transform2D) -> void:
		var mesh: Mesh = _meshes.get(key, null)
		if mesh != null:
			draw_mesh(mesh, _white, xform, color)
		else:
			draw_colored_polygon(_to_tex(pts), color)   # mesh missing (rare) — fall back
