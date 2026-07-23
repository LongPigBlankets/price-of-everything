extends Node2D
## Debug renderer for the roads-v2 network. Two layers (spec Phase 3):
## - STATIC (this node): every BUILT edge, redrawn only when an order settles
##   or the edge count changes — never per frame.
## - ACTIVE (child node): edges mid-reveal, redrawn per frame while any order
##   is revealing. The reveal grows network-outward: geometry is routed
##   tile -> attachment, so it's drawn from the attachment (goal) end back
##   toward the tile by the order's reveal fraction.
## Only active while the 'toggle roadsv2' cheat has v2 enabled.

# Road colors live in MapStyle ('toggle ink' swaps them); widths are P2 work.
const TRUNK_WIDTH := 7.0
const LOCAL_WIDTH := 4.5
# Junctions are kept to at most 5 roads upstream (RoadWorks degree cap) — there
# is no special junction glyph; roads simply meet and merge.

var _drawn_edges := -1
var _drawn_previews := -1
var _drawn_fp_version := -1   # terminus glyphs depend on building footprints
## Frames between building-footprint version polls (a redraw per placement
## during one-per-frame match-start seeding froze loading).
const FP_POLL_FRAMES := 30
var _fp_poll_cooldown := 0
var _active_layer: Node2D = null

func _ready() -> void:
	_active_layer = Node2D.new()
	_active_layer.name = "ActiveReveals"
	_active_layer.draw.connect(_draw_active)
	add_child(_active_layer)
	RoadWorks.order_settled.connect(func(_id: int) -> void: _drawn_edges = -1)
	MapStyle.style_changed.connect(_on_style_changed)

func _on_style_changed() -> void:
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

func _built_count(network: RoadNetwork) -> int:
	var n := 0
	for edge_id in network.edges:
		if str(network.edges[edge_id].state) == RoadNetwork.STATE_BUILT:
			n += 1
	return n

func _draw() -> void:
	var network := RoadNetwork.instance()
	var terrain := _terrain()
	var flagged := _flagged_tiles(terrain)
	# Roads show ONLY where roads are built: clip every edge to tiles whose
	# infrastructure carries "roads", dropping spans over roadless tiles. Since
	# roads-v3 the bake flags every tile its network crosses, so for baked
	# geometry this clip is a no-op safety net (geometry == gameplay).
	var runs_by_edge: Dictionary = {}
	for edge_id in network.edges:
		var edge: Dictionary = network.edges[edge_id]
		if str(edge.state) != RoadNetwork.STATE_BUILT:
			continue
		# Fast path: when every tile the edge crosses is flagged (true for all
		# baked geometry — the bake flags its corridor), skip the point-wise clip.
		# 728 baked edges × ~60 pts of tile lookups per redraw was a real cost.
		if _all_tiles_flagged(edge.tiles, flagged):
			runs_by_edge[edge_id] = [edge.geometry]
		else:
			runs_by_edge[edge_id] = _clip_to_built(edge.geometry, terrain, flagged)
	for pass_i in 2:   # casing under colour
		for edge_id4 in runs_by_edge:
			for run in runs_by_edge[edge_id4]:
				_draw_edge_polyline(self, run, str(network.edges[edge_id4].tier), pass_i)
	_draw_terminus_glyphs(network, terrain, flagged)
	for edge_id2 in network.edges:
		var edge2: Dictionary = network.edges[edge_id2]
		if str(edge2.state) != RoadNetwork.STATE_BUILT:
			continue
		for bridge in edge2.bridges:
			if not _point_built(terrain, flagged, bridge.point):
				continue   # the road there is hidden — so is its bridge
			var t: Vector2 = bridge.tangent
			draw_line(bridge.point - t * 21.0, bridge.point + t * 21.0, MapStyle.road_bridge(), 10.0, true)
	# Preview bridges: drawn the instant a river road is built, at its
	# predetermined crossing, while the connecting road is still planning.
	for pb in RoadWorks.preview_bridges():
		if not _point_built(terrain, flagged, pb.point):
			continue
		var pt: Vector2 = pb.tangent
		draw_line(pb.point - pt * 21.0, pb.point + pt * 21.0, MapStyle.road_bridge(), 10.0, true)

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
		for run in _clip_to_built(revealed, terrain, flagged):
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
func _draw_terminus_glyphs(network: RoadNetwork, terrain: HexMap, flagged: Dictionary) -> void:
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
		for nid in [str(edge.a), str(edge.b)]:
			degree[nid] = int(degree.get(nid, 0)) + 1
			tip_edge[nid] = edge
	var bv := _building_visuals()
	# All dead-end tip positions first: a tip with ANOTHER dead-end tip nearby is
	# part of a convergence cluster and must not draw a bar (they'd overlap).
	var tip_pos: Dictionary = {}   # node_id -> Vector2
	for nid0 in degree:
		if int(degree[nid0]) != 1:
			continue
		var node0: Dictionary = network.nodes.get(nid0, {})
		if not node0.is_empty() and str(node0.kind) == RoadNetwork.KIND_JUNCTION:
			tip_pos[nid0] = node0.pos
	for nid2 in tip_pos:
		var pos: Vector2 = tip_pos[nid2]
		if not _point_built(terrain, flagged, pos):
			continue   # the road there is hidden — so is its terminus
		if bv != null and _near_building(bv, pos):
			continue   # ends at a building frontage — that IS the terminus
		var edge2: Dictionary = tip_edge[nid2]
		if _near_other_edge(network, edge_bbox, str(edge2.id), pos):
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
		var core: Color = MapStyle.road_trunk() if tier == RoadNetwork.TIER_TRUNK else MapStyle.road_local()
		var w: float = TRUNK_WIDTH if tier == RoadNetwork.TIER_TRUNK else LOCAL_WIDTH
		for a in arms:
			draw_line(tip, a, MapStyle.road_casing(), w + 2.5, true)
		for a2 in arms:
			draw_line(tip, a2, core, w, true)

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

func _near_building(bv: Node, pos: Vector2) -> bool:
	if not bv.has_method("footprint_discs"):
		return false
	for disc in bv.footprint_discs():
		if pos.distance_to(disc.center) <= float(disc.radius) + TERMINUS_BUILDING_CLEAR:
			return true
	return false

## Set of tile coords whose infrastructure carries "roads" (built or seeded).
func _flagged_tiles(terrain: HexMap) -> Dictionary:
	var out: Dictionary = {}
	if terrain == null:
		return out
	for coord in terrain.tiles:
		if (terrain.tiles[coord].get("infrastructure_present", []) as Array).has("roads"):
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
	var width: float = TRUNK_WIDTH if tier == RoadNetwork.TIER_TRUNK else LOCAL_WIDTH
	if pass_i == 0:
		canvas.draw_polyline(pts, MapStyle.road_casing(), width + 2.5, true)
	else:
		canvas.draw_polyline(pts, MapStyle.road_trunk() if tier == RoadNetwork.TIER_TRUNK else MapStyle.road_local(), width, true)
