extends Node2D
## Debug renderer for the roads-v2 network. Two layers (spec Phase 3):
## - STATIC (this node): every BUILT edge, redrawn only when an order settles
##   or the edge count changes — never per frame.
## - ACTIVE (child node): edges mid-reveal, redrawn per frame while any order
##   is revealing. The reveal grows network-outward: geometry is routed
##   tile -> attachment, so it's drawn from the attachment (goal) end back
##   toward the tile by the order's reveal fraction.
## Only active while the 'toggle roadsv2' cheat has v2 enabled.

# Road colors AND widths live in MapStyle ('toggle ink' swaps them). Ink mode
# additionally restyles the DRAWN geometry per run (RDP simplify + seeded
# wobble — spec §3c Class 2; logic geometry untouched) and replaces the solid
# casing with dash segments batched into ONE draw_multiline per tier
# (GL-compat: per-dash draw_line commands would be ~26k canvas commands).
# Junctions are kept to at most 5 roads upstream (RoadWorks degree cap) — there
# is no special junction glyph; roads simply meet and merge.

## Hand-authored tiles draw their own roads; this layer stands down on them.
const AuthoredMap := preload("res://scripts/authored_map.gd")
const ViewStream := preload("res://scripts/view_stream.gd")

## THE SAME BUG THE RIVERS HAD (see river_visuals.gd). _draw walked EVERY edge of the whole
## 728-edge network — twice, casing under bed — and the renderer replays that command buffer
## every frame whether or not _draw runs again. Measured 25 Aug with tools/pan_profile.tscn:
## 2,466 draw calls and ~43 ms of a 59 ms frame at MAXIMUM ZOOM, on a camera that was not even
## moving. The proof it was not culling: the layer cost 2,466 draw calls zoomed all the way in
## and 2,482 zoomed all the way out — the same network, for a screen showing three hexes and a
## screen showing the whole map.
##
## The margin is generous because an edge is culled on its geometry's bbox, but the things
## hung off that geometry reach past it: terminus arms (30 u), bridge decks (21 u) and the ink
## wobble. 600 matches the authored road layer's STREAM_MARGIN, so both road layers pop in at
## the same distance and a redraw of one is a redraw of the other.
const CULL_MARGIN := 600.0
var _view := Rect2()
## edge_id -> [Rect2 bbox, point count]. Geometry never changes once an edge exists, so the
## count is only a tripwire against a rebuilt network reusing an id.
var _bb_cache: Dictionary = {}
## Did the last paint keep every edge, and over what view? When everything was drawn the picture
## can never go WRONG as the camera moves — every later view is a subset of what is already on
## the canvas — so a repaint is an optimisation, not a correction, and panning while zoomed out
## (where nothing is ever culled) should not buy a full-network repaint for no saving.
##
## It IS worth repainting when the view SHRINKS, though: that is the zoom-in that finally makes
## culling pay. Without the size test, zooming in from the far view would keep all 728 edges on
## the canvas until some unrelated trigger — an order settling, a style flip — happened to fire.
var _drew_whole_network := false
var _drawn_view_size := Vector2.ZERO
## Things the current _draw left out, counted across edges, glyphs and bridges alike.
var _culled := 0

var _drawn_edges := -1
var _drawn_previews := -1
var _drawn_fp_version := -1   # terminus glyphs depend on building footprints
## Frames between building-footprint version polls (a redraw per placement
## during one-per-frame match-start seeding froze loading).
const FP_POLL_FRAMES := 30
var _fp_poll_cooldown := 0
var _active_layer: Node2D = null
## Ink-mode styled geometry cache: edge_id -> {styled: Array[PackedVector2Array],
## dashes: PackedVector2Array, n_runs: int, n_pts: int}. Simplify+wobble+dash
## per edge is too heavy to redo on every static redraw (footprint polls redraw
## repeatedly during match-start seeding — recomputing 728 edges each time
## froze the run). Entries invalidate by run-count/point-count mismatch;
## the whole cache clears on style flip.
var _ink_cache: Dictionary = {}
## Ribbon geometry: cache key -> [verts, colours, source point count, width, colour].
## See add_ribbons for why this exists rather than rebuilding on every repaint.
var _ribbon_cache: Dictionary = {}

func _ready() -> void:
	_active_layer = Node2D.new()
	_active_layer.name = "ActiveReveals"
	_active_layer.draw.connect(_draw_active)
	add_child(_active_layer)
	RoadWorks.order_settled.connect(func(_id: int) -> void:
		_drawn_edges = -1
		_term_edges = -1)
	MapStyle.style_changed.connect(_on_style_changed)

func _on_style_changed() -> void:
	_ink_cache.clear()
	_ribbon_cache.clear()   # widths and colours are baked into the vertices
	_drawn_edges = -1
	queue_redraw()
	_active_layer.queue_redraw()

func _process(_delta: float) -> void:
	# 'toggle roads' hides the whole layer; drawing is skipped while hidden.
	if visible != RoadNetwork.roads_visible:
		visible = RoadNetwork.roads_visible
		_active_layer.visible = RoadNetwork.roads_visible
		queue_redraw()
	if not RoadNetwork.roads_visible:
		return
	# See view_stream.gd: `!=` would repaint on any sub-pixel drift, which is every frame.
	var view := _visible_world_rect()
	if view.size.x > 0.0 and not ViewStream.settled(view, _view, CULL_MARGIN):
		_view = view
		if not _drew_whole_network or view.size.x < _drawn_view_size.x * 0.95:
			queue_redraw()
	var network := RoadNetwork.instance()
	var want := _built_count(network)
	var previews := RoadWorks.preview_bridges().size()
	# Terminus glyphs suppress beside buildings, so a footprint change (new
	# building landing by a dead end) also refreshes the static layer — but only
	# every FP_POLL_FRAMES: match start seeds one building PER FRAME, and a full
	# static redraw per placement froze the loading flow for ~a minute.
	_fp_poll_cooldown -= 1
	if _fp_poll_cooldown <= 0:
		_fp_poll_cooldown = FP_POLL_FRAMES
		var bv := _building_visuals()
		var fp_version: int = int(bv.footprint_version) if bv != null and "footprint_version" in bv else -1
		if fp_version != _drawn_fp_version:
			_drawn_fp_version = fp_version
			queue_redraw()
	if want != _drawn_edges or previews != _drawn_previews:
		_drawn_edges = want
		_drawn_previews = previews
		queue_redraw()
	# the active layer animates only while something is revealing
	if RoadWorks.has_active_reveals():
		_active_layer.queue_redraw()
	elif _active_layer.get_meta("had_reveals", false):
		_active_layer.queue_redraw()   # one clearing redraw after the last settle
	_active_layer.set_meta("had_reveals", RoadWorks.has_active_reveals())

func _visible_world_rect() -> Rect2:
	var vp := get_viewport()
	if vp == null:
		return Rect2()
	var size := vp.get_visible_rect().size
	if size.x <= 0.0:
		return Rect2()
	return (vp.get_canvas_transform().affine_inverse() * Rect2(Vector2.ZERO, size)).grow(CULL_MARGIN)


## Glyphs (terminus arms, bridge decks) are placed at a point and reach at most 30 u from it,
## which the cull margin swallows whole.
func _point_in_view(p: Vector2) -> bool:
	if _view.size.x <= 0.0 or _view.has_point(p):
		return true
	_culled += 1
	return false


## The bbox of an edge's geometry, cached. Empty `_view` means "no opinion" — the layer has not
## polled a viewport yet (tests never do), and then every edge draws exactly as it used to.
func _edge_visible(edge_id: Variant, geometry: PackedVector2Array) -> bool:
	if _view.size.x <= 0.0 or geometry.is_empty():
		return true
	var entry: Array = _bb_cache.get(edge_id, [])
	if entry.is_empty() or int(entry[1]) != geometry.size():
		var bb := Rect2(geometry[0], Vector2.ZERO)
		for p in geometry:
			bb = bb.expand(p)
		entry = [bb, geometry.size()]
		_bb_cache[edge_id] = entry
	if _view.intersects(entry[0]):
		return true
	_culled += 1
	return false


func _built_count(network: RoadNetwork) -> int:
	var n := 0
	for edge_id in network.edges:
		if str(network.edges[edge_id].state) == RoadNetwork.STATE_BUILT:
			n += 1
	return n

## The repo's per-layer draw timer (see authored_road_visuals.gd). Worth having HERE in
## particular: culling turned this layer from one paint a match into a paint every time the
## view drifts, which is what surfaced an 84 ms terminus pass and a 112 ms footprint scan that
## had been invisible for as long as they only ran once.
func _draw() -> void:
	var _lpd := Time.get_ticks_usec()
	_lp_draw_inner()
	var _lpms := float(Time.get_ticks_usec() - _lpd) / 1000.0
	if _lpms > 50.0 and OS.get_environment("LOAD_PROF") != "":
		print("LOADPROF-DRAW %s %.0f ms   abs=%d" % [name, _lpms, Time.get_ticks_msec()])


func _lp_draw_inner() -> void:
	var network := RoadNetwork.instance()
	var terrain := _terrain()
	var flagged := _flagged_tiles(terrain)
	# Roads show ONLY where roads are built: clip every edge to tiles whose
	# infrastructure carries "roads", dropping spans over roadless tiles. Since
	# roads-v3 the bake flags every tile its network crosses, so for baked
	# geometry this clip is a no-op safety net (geometry == gameplay).
	_culled = 0
	var runs_by_edge: Dictionary = {}
	for edge_id in network.edges:
		var edge: Dictionary = network.edges[edge_id]
		if str(edge.state) != RoadNetwork.STATE_BUILT:
			continue
		if not _edge_visible(edge_id, edge.geometry):
			continue   # off screen: no commands, and no point-wise clip either
		# Fast path: when every tile the edge crosses is flagged (true for all
		# baked geometry — the bake flags its corridor), skip the point-wise clip.
		# 728 baked edges × ~60 pts of tile lookups per redraw was a real cost.
		if _all_tiles_flagged(edge.tiles, flagged):
			runs_by_edge[edge_id] = [edge.geometry]
		else:
			runs_by_edge[edge_id] = _clip_to_built(edge.geometry, terrain, flagged)
	if MapStyle.uses_ink_linework():
		_draw_runs_ink(self, runs_by_edge, network)
	else:
		# Classic: same two-array shape as the ink path — all casings, then all beds.
		var classic_casing: Array = []
		var classic_beds: Array = []
		for edge_id4 in runs_by_edge:
			var trunk4 := str(network.edges[edge_id4].tier) == RoadNetwork.TIER_TRUNK
			for run in runs_by_edge[edge_id4]:
				if (run as PackedVector2Array).size() < 2:
					continue
				classic_casing.append(["%s|%d|cc" % [edge_id4, classic_beds.size()], run,
					MapStyle.road_casing_width(trunk4), MapStyle.road_casing()])
				classic_beds.append(["%s|%d|cb" % [edge_id4, classic_beds.size()], run,
					MapStyle.road_width(trunk4),
					MapStyle.road_trunk() if trunk4 else MapStyle.road_local()])
		add_ribbons(self, classic_casing)
		add_ribbons(self, classic_beds)
	_draw_terminus_glyphs(network, terrain, flagged)
	for edge_id2 in network.edges:
		var edge2: Dictionary = network.edges[edge_id2]
		if str(edge2.state) != RoadNetwork.STATE_BUILT:
			continue
		for bridge in edge2.bridges:
			if not _point_in_view(bridge.point):
				continue   # off screen — and the landfall probe below is not free either
			if not _point_built(terrain, flagged, bridge.point):
				continue   # the road there is hidden — so is its bridge
			_draw_bridge_glyph(self, bridge.point, bridge.tangent)
	# Preview bridges: drawn the instant a river road is built, at its
	# predetermined crossing, while the connecting road is still planning.
	for pb in RoadWorks.preview_bridges():
		if not _point_in_view(pb.point):
			continue
		if not _point_built(terrain, flagged, pb.point):
			continue
		_draw_bridge_glyph(self, pb.point, pb.tangent)
	_drew_whole_network = _culled == 0
	_drawn_view_size = _view.size

## The deck used to be a FIXED 42u bar (point +/- tangent * 21). A bridge over a
## narrow river therefore ran on well past both banks, and a crossing near a
## coast put a tan plank out in open water — the "roads on the sea" the owner
## spotted. Probe outward for the far bank instead: the deck reaches land, or it
## is not a crossing and is not drawn. Roads never appear on lakes or sea.
const BRIDGE_HALF_MAX := 21.0
const BRIDGE_HALF_MIN := 6.0
const BRIDGE_PROBE_STEP := 2.0

## Half-length the deck may run along `dir` before it reaches dry ground, or -1.0
## when there is no landfall within BRIDGE_HALF_MAX (so this end is open water).
static func _bridge_landfall(point: Vector2, dir: Vector2) -> float:
	var nav := NavGrid.instance()
	if nav == null or not nav.is_ready():
		return BRIDGE_HALF_MAX   # no world knowledge — keep the legacy deck
	var travelled := BRIDGE_PROBE_STEP
	while travelled <= BRIDGE_HALF_MAX:
		var c := nav.cell_of(point + dir * travelled)
		if nav.water(c.x, c.y) == 0:
			return maxf(travelled, BRIDGE_HALF_MIN)
		travelled += BRIDGE_PROBE_STEP
	return -1.0

## Classic: one thick brown deck stroke. Ink: a tan deck plank with two thin
## ink rails along its long sides (the mockup's little bridge symbol).
func _draw_bridge_glyph(canvas: CanvasItem, point: Vector2, tangent: Vector2) -> void:
	var fwd := _bridge_landfall(point, tangent)
	var back := _bridge_landfall(point, -tangent)
	if fwd < 0.0 or back < 0.0:
		return   # no bank on one side: this is open water, not a crossing
	_draw_bridge_deck(canvas, point, tangent, fwd, back)

func _draw_bridge_deck(canvas: CanvasItem, point: Vector2, tangent: Vector2,
		fwd: float, back: float) -> void:
	if not MapStyle.uses_ink_linework():
		canvas.draw_line(point - tangent * back, point + tangent * fwd, MapStyle.road_bridge(), 10.0, true)
		return
	var n := Vector2(-tangent.y, tangent.x)
	if MapStyle.has_cartographic_depth():
		# The deck is a low prism on the shared light model: side face offset SE
		# under the deck, rails carrying the linework (MILD masses take no outline).
		var off := MapStyle.extrude_offset(MapStyle.Extrude.MILD)
		var a := point - tangent * back
		var b := point + tangent * fwd
		canvas.draw_line(a + off, b + off, MapStyle.extrude_side(MapStyle.road_trunk(), MapStyle.Extrude.MILD), 9.0, true)
		canvas.draw_line(a, b, MapStyle.road_trunk(), 9.0, true)
		for ps in [-1.0, 1.0]:
			var rail: Vector2 = n * (5.4 * float(ps))
			canvas.draw_line(a + rail, b + rail, MapStyle.road_casing_trunk(), 1.4, true)
		return
	canvas.draw_line(point - tangent * back, point + tangent * fwd, MapStyle.road_local(), 9.0, true)
	for s in [-1.0, 1.0]:
		var off: Vector2 = n * (5.4 * float(s))
		canvas.draw_line(point - tangent * back + off, point + tangent * fwd + off, MapStyle.road_casing(), 1.6, true)

## Ink-mode run renderer: dashes for every run are accumulated per tier and
## submitted as ONE draw_multiline each; the solid near-parchment beds go on
## top (dashes stick out both sides = the vintage dashed-casing symbol).
func _draw_runs_ink(canvas: CanvasItem, runs_by_edge: Dictionary, network: RoadNetwork,
		cacheable: bool = true) -> void:
	var dash_local := PackedVector2Array()
	var dash_trunk := PackedVector2Array()
	var center_trunk := PackedVector2Array()
	var beds: Array = []   # [styled pts, is_trunk]
	for edge_id in runs_by_edge:
		var is_trunk := str(network.edges[edge_id].tier) == RoadNetwork.TIER_TRUNK
		var runs: Array = runs_by_edge[edge_id]
		var n_pts := 0
		for run in runs:
			n_pts += (run as PackedVector2Array).size()
		var entry: Dictionary = _ink_cache.get(edge_id, {})
		if entry.is_empty() or int(entry.n_runs) != runs.size() or int(entry.n_pts) != n_pts:
			var styled: Array = []
			var dashes := PackedVector2Array()
			var center := PackedVector2Array()
			for run in runs:
				var pts := _styled_run(run, str(edge_id))
				if pts.size() >= 2:
					styled.append(pts)
					if MapStyle.road_casing_dashed():
						_emit_dashes(pts, str(edge_id), dashes, MapStyle.road_dash(), "")
					if is_trunk and not MapStyle.trunk_center_dash().is_empty():
						# Arteries (trunk tier) carry a dashed centre line.
						_emit_dashes(pts, str(edge_id), center, MapStyle.trunk_center_dash(), "c")
			entry = {"styled": styled, "dashes": dashes, "center": center, "n_runs": runs.size(), "n_pts": n_pts}
			_ink_cache[edge_id] = entry
		if is_trunk:
			dash_trunk.append_array(entry.dashes)
			center_trunk.append_array(entry.center)
		else:
			dash_local.append_array(entry.dashes)
		var run_i := 0
		for pts2 in entry.styled:
			beds.append([pts2, is_trunk, ("%s|%d" % [edge_id, run_i]) if cacheable else null])
			run_i += 1
	if dash_local.size() >= 2:
		canvas.draw_multiline(dash_local, MapStyle.road_casing(), MapStyle.road_casing_width(false), true)
	if dash_trunk.size() >= 2:
		canvas.draw_multiline(dash_trunk, MapStyle.road_casing(), MapStyle.road_casing_width(true), true)
	# City plate: streets are cream CHANNELS, so the casing is a solid hairline
	# edge under the bed rather than the survey-map dash. Trunk edges take the
	# heavier alpha — in this idiom that line is the block frontage.
	# ONE array for every casing, then ONE for every bed — see add_ribbons. The two passes stay
	# separate because every casing must sit under every bed, not just under its own.
	if not MapStyle.road_casing_dashed():
		var casings: Array = []
		for b0 in beds:
			var trunk0: bool = b0[1]
			casings.append([("%s|c" % b0[2]) if b0[2] != null else null, b0[0],
				MapStyle.road_casing_width(trunk0),
				MapStyle.road_casing_trunk() if trunk0 else MapStyle.road_casing()])
		add_ribbons(canvas, casings)
	var bed_strokes: Array = []
	for b in beds:
		bed_strokes.append([("%s|b" % b[2]) if b[2] != null else null, b[0],
			MapStyle.road_width(b[1]),
			MapStyle.road_trunk() if b[1] else MapStyle.road_local()])
	add_ribbons(canvas, bed_strokes)
	if center_trunk.size() >= 2:
		canvas.draw_multiline(center_trunk, MapStyle.trunk_center_color(), MapStyle.trunk_center_width(), true)

## Simplify-then-wobble the DRAWN polyline (endpoints and simplified corners
## stay exact, so junction joints and network connectivity read unchanged).
func _styled_run(run: PackedVector2Array, seed_key: String) -> PackedVector2Array:
	return _wobble_polyline(_rdp(run, MapStyle.road_simplify_eps()), seed_key)

func _wobble_polyline(pts: PackedVector2Array, seed_key: String) -> PackedVector2Array:
	var w: Array = MapStyle.road_wobble()
	if w.is_empty() or pts.size() < 2:
		return pts
	var step: float = w[0]
	var amp: float = w[1]
	var out := PackedVector2Array()
	var k := 0
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		out.append(a)
		var seg_len := a.distance_to(b)
		var n := int(seg_len / step)
		if n > 0:
			var dir := (b - a) / seg_len
			var perp := Vector2(-dir.y, dir.x)
			for j in range(1, n + 1):
				var off := (float(RoadHash.pick("rwob|%s|%d" % [seed_key, k], 200)) / 100.0 - 1.0) * amp
				k += 1
				out.append(a + (b - a) * (float(j) / float(n + 1)) + perp * off)
	out.append(pts[pts.size() - 1])
	return out

## Ramer-Douglas-Peucker on an open polyline; endpoints always kept.
func _rdp(pts: PackedVector2Array, eps: float) -> PackedVector2Array:
	if eps <= 0.0 or pts.size() < 3:
		return pts
	var keep := PackedByteArray()
	keep.resize(pts.size())
	keep.fill(0)
	keep[0] = 1
	keep[pts.size() - 1] = 1
	var stack: Array = [[0, pts.size() - 1]]
	while not stack.is_empty():
		var span: Array = stack.pop_back()
		var i0: int = span[0]
		var i1: int = span[1]
		if i1 - i0 < 2:
			continue
		var a := pts[i0]
		var b := pts[i1]
		var ab := b - a
		var ab_len2 := ab.length_squared()
		var best := -1.0
		var best_i := -1
		for i in range(i0 + 1, i1):
			# squared point-segment distance, inline (native helper per point
			# was the hot cost across 728 edges)
			var ap := pts[i] - a
			var t := 0.0 if ab_len2 <= 0.0 else clampf(ap.dot(ab) / ab_len2, 0.0, 1.0)
			var d2 := (ap - ab * t).length_squared()
			if d2 > best:
				best = d2
				best_i = i
		if best > eps * eps:
			keep[best_i] = 1
			stack.append([i0, best_i])
			stack.append([best_i, i1])
	var out := PackedVector2Array()
	for i in pts.size():
		if keep[i] == 1:
			out.append(pts[i])
	return out

## Walk the polyline emitting [start, end] pairs for the dash-ON stretches of
## `pattern` [dash, gap], with a seeded phase per edge (+salt distinguishes
## the casing walk from the centre-line walk) so lines don't tick in sync.
func _emit_dashes(pts: PackedVector2Array, seed_key: String, into: PackedVector2Array, pattern: Array, salt: String) -> void:
	var dash: float = pattern[0]
	var period: float = dash + float(pattern[1])
	var t := -float(RoadHash.pick("rdash|%s%s" % [seed_key, salt], 100)) / 100.0 * period
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		if seg <= 0.001:
			continue
		var dir := (b - a) / seg
		var walked := 0.0
		while walked < seg - 0.001:
			var pos := fposmod(t + walked, period)
			if pos < dash:
				var run_len := minf(dash - pos, seg - walked)
				into.append(a + dir * walked)
				into.append(a + dir * (walked + run_len))
				# float landmine: pos can land a hair under `dash` (or fposmod
				# can graze `period`), making the natural advance ~0 — clamp to
				# a minimum step or this loop spins forever at 99% CPU.
				walked += maxf(run_len, 0.05)
			else:
				walked += maxf(minf(period - pos, seg - walked), 0.05)
		t += seg

func _draw_active() -> void:
	var network := RoadNetwork.instance()
	var terrain := _terrain()
	var flagged := _flagged_tiles(terrain)
	for edge_id in network.edges:
		var edge: Dictionary = network.edges[edge_id]
		if str(edge.state) != RoadNetwork.STATE_BUILDING:
			continue
		var frac := RoadWorks.reveal_fraction(str(edge_id))
		var revealed := _suffix_by_fraction(edge.geometry, frac)
		if revealed.size() < 2:
			continue
		var runs: Array = _clip_to_built(revealed, terrain, flagged)
		if MapStyle.uses_ink_linework():
			var single: Dictionary = {}
			single[edge_id] = runs
			_draw_runs_ink(_active_layer, single, network, false)
			continue
		for run in runs:
			for pass_i in 2:
				_draw_edge_polyline(_active_layer, run, str(edge.tier), pass_i)

func _terrain() -> HexMap:
	var found := get_tree().get_nodes_in_group("hex_map")
	return found[0] as HexMap if not found.is_empty() else null

## A dead end within this of a building footprint draws NO glyph — the road
## visibly ends AT the building (serving it), which is a complete terminus.
const TERMINUS_BUILDING_CLEAR := 40.0
## Dead-end treatments (designer ruling: NO circles): a short T-crossbar or a
## Y-fork, seeded per node, else a plain cut end. Arms are 20-30u; the bar/fork
## must stay at least TERMINUS_EDGE_INSET inside the tile's hex or the end
## stays plain (an arm poking over the tile seam reads as a phantom road).
const TERMINUS_ARM_MIN := 20.0
const TERMINUS_ARM_MAX := 30.0
const TERMINUS_EDGE_INSET := 30.0
const TERMINUS_Y_SPREAD_DEG := 35.0

## A tip within this of ANOTHER edge's geometry is a junction/merge, not a dead
## end — no glyph. Graph degree alone is NOT enough: baked edges meet
## geometrically (reuse-discount merges) without sharing node ids, so a pure
## degree-1 test decorated every visual junction with (often overlapping) rings.
const TERMINUS_MERGE_CLEAR := 14.0
## Two (or more) dead-end tips within this range of each other are a CONVERGENCE
## (e.g. the stitched fan at a busy bridge gate), not isolated terminuses — arms
## reach up to TERMINUS_ARM_MAX, so nearby tips would draw overlapping bars
## (owner screenshot 2026-07-09). The whole cluster stays plain cut ends.
const TERMINUS_CLUSTER_CLEAR := 60.0

## Dead-end treatment (roads-v3, replaces the deleted Y-stubs): a road tip that
## is genuinely alone — degree-1 JUNCTION node AND clear of every other edge's
## geometry — gets a small turning-loop glyph, purely draw-time (no edges, no
## saved state). The moment a later road reaches it the glyph vanishes by
## construction. Gateways/crossings are skipped, as are tips beside a building.
## WHICH TIPS ARE DEAD ENDS IS A PROPERTY OF THE NETWORK, NOT THE CAMERA: node degrees, the one
## edge touching each tip, every edge's bbox, and the tip positions. None of it moves when the
## view does, and rebuilding it per repaint cost 84 ms of a 92 ms _draw — invisible while this
## layer painted once a match, and the whole of the panning stutter once culling made it repaint
## as the camera moved. Keyed on the built-edge count, which is what `_drawn_edges` already
## invalidates on, and dropped outright when an order settles.
var _term_cache: Dictionary = {}
var _term_edges := -1


func _terminus_data(network: RoadNetwork) -> Dictionary:
	var built := _built_count(network)
	if _term_edges == built and not _term_cache.is_empty():
		return _term_cache
	_term_edges = built
	var degree: Dictionary = {}
	var tip_edge: Dictionary = {}   # node_id -> the one BUILT edge touching it
	var edge_bbox: Dictionary = {}  # edge_id -> Rect2 over its geometry
	for edge_id in network.edges:
		var edge: Dictionary = network.edges[edge_id]
		if str(edge.state) != RoadNetwork.STATE_BUILT:
			continue
		var geo0: PackedVector2Array = edge.geometry
		if geo0.size() >= 2:
			var bb := Rect2(geo0[0], Vector2.ZERO)
			for p0 in geo0:
				bb = bb.expand(p0)
			edge_bbox[edge_id] = bb.grow(TERMINUS_MERGE_CLEAR)
		var a_id := str(edge.a)
		var b_id := str(edge.b)
		degree[a_id] = int(degree.get(a_id, 0)) + 1
		degree[b_id] = int(degree.get(b_id, 0)) + 1
		tip_edge[a_id] = edge
		tip_edge[b_id] = edge
	# A tip with ANOTHER dead-end tip nearby is part of a convergence cluster and must not draw
	# a bar (they would overlap), so every tip position is collected before any of them draws.
	var tip_pos: Dictionary = {}   # node_id -> Vector2
	for nid0 in degree:
		if int(degree[nid0]) != 1:
			continue
		var node0: Dictionary = network.nodes.get(nid0, {})
		if not node0.is_empty() and str(node0.kind) == RoadNetwork.KIND_JUNCTION:
			tip_pos[nid0] = node0.pos
	_term_cache = {"tip_edge": tip_edge, "bbox": edge_bbox, "tips": tip_pos}
	return _term_cache


func _draw_terminus_glyphs(network: RoadNetwork, terrain: HexMap, flagged: Dictionary) -> void:
	var term := _terminus_data(network)
	var tip_edge: Dictionary = term.tip_edge
	var edge_bbox: Dictionary = term.bbox
	var tip_pos: Dictionary = term.tips
	# footprint_discs() rebuilds a Dictionary per building — 561 of them — on every call, and
	# this asked it once PER TIP: 223 on-screen tips x 561 buildings measured at 112 ms of a
	# 150 ms _draw, the single most expensive thing in the layer. Ask once, and keep only the
	# discs near the view: a tip off screen never reaches the loop below, so a building off
	# screen can never be the one a drawn tip ends at.
	var discs := _nearby_discs(_building_visuals())
	# Same argument for _near_other_edge, which scans every edge's bbox per tip.
	var near_bbox: Dictionary = edge_bbox
	if _view.size.x > 0.0:
		near_bbox = {}
		for eid in edge_bbox:
			if _view.intersects(edge_bbox[eid]):
				near_bbox[eid] = edge_bbox[eid]
	for nid2 in tip_pos:
		var pos: Vector2 = tip_pos[nid2]
		if not _point_in_view(pos):
			continue   # off screen. The degree/tip passes above stay whole-network: whether a
			# tip IS a dead end depends on edges that may themselves be off screen.
		if not _point_built(terrain, flagged, pos):
			continue   # the road there is hidden — so is its terminus
		if _near_disc(discs, pos):
			continue   # ends at a building frontage — that IS the terminus
		var edge2: Dictionary = tip_edge[nid2]
		if _near_other_edge(network, near_bbox, str(edge2.id), pos):
			continue   # the tip lands on/joins another road — a junction, not a dead end
		var clustered := false
		for other_nid in tip_pos:
			if str(other_nid) != str(nid2) \
					and pos.distance_squared_to(tip_pos[other_nid]) <= TERMINUS_CLUSTER_CLEAR * TERMINUS_CLUSTER_CLEAR:
				clustered = true
				break
		if clustered:
			continue   # convergence fan (bridge gates etc.) — plain ends, no bars
		var geo: PackedVector2Array = edge2.geometry
		if geo.size() < 2:
			continue
		var tip: Vector2 = geo[0] if geo[0].distance_squared_to(pos) < geo[geo.size() - 1].distance_squared_to(pos) else geo[geo.size() - 1]
		var prev: Vector2 = geo[1] if tip == geo[0] else geo[geo.size() - 2]
		var dir := (tip - prev).normalized()
		# Treatment seeded per node: 0 = T-crossbar, 1 = Y-fork, 2 = plain cut end.
		var pick := RoadHash.pick("terminus|%s" % nid2, 3)
		if pick == 2:
			continue   # plain dead end — the road just stops
		var arm := TERMINUS_ARM_MIN + float(RoadHash.pick("terminus|%s|arm" % nid2, 100)) / 100.0 * (TERMINUS_ARM_MAX - TERMINUS_ARM_MIN)
		var arms: Array = []
		if pick == 0:
			var perp := Vector2(-dir.y, dir.x)
			arms = [tip + perp * arm, tip - perp * arm]
		else:
			var spread := deg_to_rad(TERMINUS_Y_SPREAD_DEG)
			arms = [tip + dir.rotated(spread) * arm, tip + dir.rotated(-spread) * arm]
		if terrain != null and not _arms_inside_tile(terrain, tip, arms):
			continue   # too close to the tile seam — stay a plain dead end
		var tier := str(edge2.tier)
		var is_trunk := tier == RoadNetwork.TIER_TRUNK
		var core: Color = MapStyle.road_trunk() if is_trunk else MapStyle.road_local()
		for a in arms:
			draw_line(tip, a, MapStyle.road_casing(), MapStyle.road_casing_width(is_trunk), true)
		for a2 in arms:
			draw_line(tip, a2, core, MapStyle.road_width(is_trunk), true)

## Every arm endpoint must sit at least TERMINUS_EDGE_INSET inside the hex of
## the tile that owns the TIP, so a terminus bar never dangles over a tile seam.
func _arms_inside_tile(terrain: HexMap, tip: Vector2, arms: Array) -> bool:
	var center: Vector2 = terrain.map_to_local(terrain.local_to_map(tip))
	var inset := TERMINUS_EDGE_INSET
	# corner inequality inset: 240|x| + 135|y| <= 64800 shrunk by inset * |(240,135)|
	var corner_max := 64800.0 - inset * Vector2(240.0, 135.0).length()
	for a in arms:
		var rel: Vector2 = (a as Vector2) - center
		if absf(rel.x) > 270.0 - inset or absf(rel.y) > 240.0 - inset:
			return false
		if 240.0 * absf(rel.x) + 135.0 * absf(rel.y) > corner_max:
			return false
	return true

## True when `pos` sits within TERMINUS_MERGE_CLEAR of any OTHER built edge's
## geometry. Per-edge bbox prefilter first; exact segment distance only on the
## few edges whose grown bbox contains the tip.
func _near_other_edge(network: RoadNetwork, edge_bbox: Dictionary, own_id: String, pos: Vector2) -> bool:
	for edge_id in edge_bbox:
		if str(edge_id) == own_id:
			continue
		if not (edge_bbox[edge_id] as Rect2).has_point(pos):
			continue
		var geo: PackedVector2Array = network.edges[edge_id].geometry
		for i in range(geo.size() - 1):
			if pos.distance_squared_to(Geometry2D.get_closest_point_to_segment(pos, geo[i], geo[i + 1])) \
				<= TERMINUS_MERGE_CLEAR * TERMINUS_MERGE_CLEAR:
				return true
	return false

func _building_visuals() -> Node:
	var found := get_tree().get_nodes_in_group("building_footprints")
	return found[0] if not found.is_empty() else null

## Building footprints as flat centre/radius arrays, taken ONCE per draw and clipped to the
## view. Flat arrays rather than the Dictionary list `footprint_discs()` returns, because the
## test below runs for every on-screen tip and a Variant lookup per building per tip is exactly
## the cost this replaces.
func _nearby_discs(bv: Node) -> Array:
	var cx := PackedFloat32Array()
	var cy := PackedFloat32Array()
	var rr := PackedFloat32Array()
	if bv == null or not bv.has_method("footprint_discs"):
		return [cx, cy, rr]
	var clip := _view.size.x > 0.0
	var lo := _view.position
	var hi := _view.end
	for disc in bv.footprint_discs():
		var c: Vector2 = disc.center
		var r := float(disc.radius) + TERMINUS_BUILDING_CLEAR
		if clip and (c.x < lo.x - r or c.x > hi.x + r or c.y < lo.y - r or c.y > hi.y + r):
			continue
		cx.append(c.x)
		cy.append(c.y)
		rr.append(float(disc.radius))
	return [cx, cy, rr]


## Squared throughout: this is the innermost loop of the terminus pass and a square root per
## building per tip buys nothing a comparison cannot.
static func _near_disc(discs: Array, pos: Vector2) -> bool:
	var cx: PackedFloat32Array = discs[0]
	var cy: PackedFloat32Array = discs[1]
	var rr: PackedFloat32Array = discs[2]
	for i in cx.size():
		var dx := cx[i] - pos.x
		var dy := cy[i] - pos.y
		var reach := rr[i] + TERMINUS_BUILDING_CLEAR
		if dx * dx + dy * dy <= reach * reach:
			return true
	return false

## Set of tile coords whose infrastructure carries "roads" (built or seeded) AND whose
## roads this layer is responsible for drawing.
##
## HAND-AUTHORED TILES ARE EXCLUDED. This set is a pure RENDERING input — it decides which
## baked geometry gets drawn, never what the simulation reads — so dropping an authored tile
## from it removes the baked network's linework there and leaves `AuthoredRoadVisuals` to
## draw the hand-drawn roads instead. The tile keeps its infrastructure flag, its transport
## cost and its capacity; only the picture changes.
func _flagged_tiles(terrain: HexMap) -> Dictionary:
	var out: Dictionary = {}
	if terrain == null:
		return out
	var authored := AuthoredMap.is_active()
	for coord in terrain.tiles:
		var tile: Dictionary = terrain.tiles[coord]
		if not (tile.get("infrastructure_present", []) as Array).has("roads"):
			continue
		if authored and AuthoredMap.covers(str(tile.get("id", ""))):
			continue
		out[coord] = true
	return out

func _point_built(terrain: HexMap, flagged: Dictionary, p: Vector2) -> bool:
	if terrain == null:
		return true   # no terrain (headless) — don't clip
	return flagged.has(terrain.tile_coord_for_map_coord(terrain.local_to_map(p)))

func _all_tiles_flagged(tiles: Array, flagged: Dictionary) -> bool:
	for t in tiles:
		if not flagged.has(t):
			return false
	return true

## Split a polyline into the runs that lie on road-built tiles; spans over
## roadless tiles are dropped. Returns the whole polyline when there's no terrain.
func _clip_to_built(geo: PackedVector2Array, terrain: HexMap, flagged: Dictionary) -> Array:
	if terrain == null:
		return [geo]
	var runs: Array = []
	var cur := PackedVector2Array()
	for p in geo:
		if flagged.has(terrain.tile_coord_for_map_coord(terrain.local_to_map(p))):
			cur.append(p)
		elif cur.size() >= 2:
			runs.append(cur)
			cur = PackedVector2Array()
		else:
			cur = PackedVector2Array()
	if cur.size() >= 2:
		runs.append(cur)
	return runs

## The portion of the polyline revealed so far, growing from the LAST point
## (the network attachment) back toward the first (the new tile).
func _suffix_by_fraction(pts: PackedVector2Array, frac: float) -> PackedVector2Array:
	if pts.size() < 2 or frac >= 1.0:
		return pts
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	var want := total * clampf(frac, 0.0, 1.0)
	var out := PackedVector2Array()
	var walked := 0.0
	var i2 := pts.size() - 1
	out.append(pts[i2])
	while i2 > 0 and walked < want:
		var seg := pts[i2].distance_to(pts[i2 - 1])
		if walked + seg <= want:
			out.append(pts[i2 - 1])
			walked += seg
			i2 -= 1
		else:
			var t := (want - walked) / maxf(seg, 0.001)
			out.append(pts[i2].lerp(pts[i2 - 1], t))
			break
	out.reverse()
	return out

func _draw_edge_polyline(canvas: CanvasItem, pts: PackedVector2Array, tier: String, pass_i: int) -> void:
	if pts.size() < 2:
		return
	var is_trunk := tier == RoadNetwork.TIER_TRUNK
	# No cache key: the only caller is the reveal layer, whose geometry moves every frame.
	if pass_i == 0:
		add_ribbons(canvas, [[null, pts, MapStyle.road_casing_width(is_trunk), MapStyle.road_casing()]])
	else:
		add_ribbons(canvas, [[null, pts, MapStyle.road_width(is_trunk),
			MapStyle.road_trunk() if is_trunk else MapStyle.road_local()]])


# ------------------------------------------------------------------ ribbon batching

## Feather band, world units, so an edge is soft rather than stepped. Sized to about a pixel at
## the closest play zoom; further out it goes sub-pixel, which is where the roads are hairlines
## anyway. This is what replaces `draw_polyline(..., antialiased = true)`.
const RIBBON_FEATHER := 1.0
## How far a mitre may reach past the half-width before it is cut back. Roads are RDP-simplified
## and gently wobbled, so a corner sharp enough to hit this is rare; the clamp only stops a
## near-reversal from throwing a spike across the map.
const RIBBON_MITER_LIMIT := 2.5


## EVERY road bed on screen in ONE draw call.
##
## `draw_polyline(antialiased = true)` is the most expensive command in the gl_compatibility
## canvas: each call is its own dynamic vertex upload, and the antialiasing splits it further —
## measured 25 Aug at ~3 draw calls and ~30 us PER EDGE, so 728 edges cost ~2,180 draw calls and
## ~43 ms of a 59 ms frame. Culling fixed that close in and could not fix it at all zoomed out,
## where every edge genuinely is on screen.
##
## So do here what the casing dashes already do (one `draw_multiline` per tier) and what the
## canopy does (one MultiMesh): build the ribbon triangles and hand the renderer a single
## triangle array. Width and colour ride on the vertices, so beds and trunks share one array;
## only DRAW ORDER forces a second one, for the casing that goes under them.
##
## THE GEOMETRY IS CACHED, AND THAT IS NOT OPTIONAL. Building the ribbons is work draw_polyline
## used to do in C++, and GDScript is not the place to redo it 39 times in six seconds: measured
## uncached at 38-86 ms per repaint for ~100 strokes, which turned a 10 ms panning frame into a
## 46 ms one — a worse layer than the one it replaced. Cached, a repaint is `append_array` over
## a handful of PackedArrays, which is a memcpy. An edge's ribbon depends only on its geometry
## (fixed once built) and the style's width and colour, so the entry carries all three and
## rebuilds when any of them moves; `_on_style_changed` drops the lot.
##
## `strokes` is `[cache_key, PackedVector2Array points, float width, Color colour]`. A null key
## means do not cache — the reveal layer's geometry is different every frame, and caching it
## would either thrash or, worse, hand back the previous frame's shape at the same point count.
func add_ribbons(canvas: CanvasItem, strokes: Array) -> void:
	var out_p := PackedVector2Array()
	var out_c := PackedColorArray()
	for st in strokes:
		var key: Variant = st[0]
		var pts: PackedVector2Array = st[1]
		var width := float(st[2])
		var col: Color = st[3]
		var soup: Array
		if key == null:
			soup = _ribbon_soup(pts, width, col)
		else:
			var e: Array = _ribbon_cache.get(key, [])
			if e.is_empty() or int(e[2]) != pts.size() \
					or not is_equal_approx(float(e[3]), width) or Color(e[4]) != col:
				soup = _ribbon_soup(pts, width, col)
				_ribbon_cache[key] = [soup[0], soup[1], pts.size(), width, col]
			else:
				soup = e
		out_p.append_array(soup[0])
		out_c.append_array(soup[1])
	var n := out_p.size()
	if n == 0:
		return
	RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(), _sequence(n), out_p, out_c)


## 0,1,2,...,n-1. The soups are plain triangle lists, so the index array is always the identity
## and can be grown once for the whole run and sliced — a memcpy instead of n GDScript writes.
static var _seq := PackedInt32Array()

static func _sequence(n: int) -> PackedInt32Array:
	if _seq.size() < n:
		var was := _seq.size()
		_seq.resize(n)
		for i in range(was, n):
			_seq[i] = i
	return _seq.slice(0, n)


## One stroke as a flat triangle list: four offsets per point — outer, core, core, outer — woven
## into three bands per segment, so the two outer bands fade to alpha 0 and carry the
## antialiasing that draw_polyline's `antialiased` argument used to.
static func _ribbon_soup(p_in: PackedVector2Array, width: float, color: Color) -> Array:
	# A repeated point has no direction to take a normal from, and the wobble can emit one.
	var p := PackedVector2Array()
	for q in p_in:
		if p.is_empty() or not p[p.size() - 1].is_equal_approx(q):
			p.append(q)
	var n := p.size()
	if n < 2 or width <= 0.0:
		return [PackedVector2Array(), PackedColorArray()]
	var half := width * 0.5
	var feather: float = minf(RIBBON_FEATHER, half * 0.5)
	var core := half - feather
	var fade := Color(color.r, color.g, color.b, 0.0)
	var band: Array = [fade, color, color, fade]

	var seg := PackedVector2Array()
	seg.resize(n - 1)
	for i in n - 1:
		var d := (p[i + 1] - p[i]).normalized()
		seg[i] = Vector2(-d.y, d.x)

	var off := PackedVector2Array()
	off.resize(n * 4)
	for i in n:
		var nrm: Vector2
		var reach := 1.0
		if i == 0:
			nrm = seg[0]
		elif i == n - 1:
			nrm = seg[n - 2]
		else:
			var total := seg[i - 1] + seg[i]
			if total.length_squared() < 0.000001:
				nrm = seg[i]            # a near-reversal: no mitre exists, butt the ends
			else:
				nrm = total.normalized()
				# 1/cos(theta/2) — how far the mitre must reach to hold the ribbon's width.
				reach = clampf(1.0 / maxf(nrm.dot(seg[i]), 0.0001), 1.0, RIBBON_MITER_LIMIT)
		var outer := nrm * (half * reach)
		var inner := nrm * (core * reach)
		var b := i * 4
		off[b] = p[i] + outer
		off[b + 1] = p[i] + inner
		off[b + 2] = p[i] - inner
		off[b + 3] = p[i] - outer

	var segs := n - 1
	var verts := PackedVector2Array()
	var cols := PackedColorArray()
	verts.resize(segs * 18)
	cols.resize(segs * 18)
	var w := 0
	for i in segs:
		var a := i * 4
		var c := a + 4
		for k in 3:                      # fade band, core, fade band
			verts[w] = off[a + k]
			cols[w] = band[k]
			w += 1
			verts[w] = off[a + k + 1]
			cols[w] = band[k + 1]
			w += 1
			verts[w] = off[c + k]
			cols[w] = band[k]
			w += 1
			verts[w] = off[a + k + 1]
			cols[w] = band[k + 1]
			w += 1
			verts[w] = off[c + k + 1]
			cols[w] = band[k + 1]
			w += 1
			verts[w] = off[c + k]
			cols[w] = band[k]
			w += 1
	return [verts, cols]

