extends Node2D
## Debug renderer for the roads-v2 network. Two layers (spec Phase 3):
## - STATIC (this node): every BUILT edge, redrawn only when an order settles
##   or the edge count changes — never per frame.
## - ACTIVE (child node): edges mid-reveal, redrawn per frame while any order
##   is revealing. The reveal grows network-outward: geometry is routed
##   tile -> attachment, so it's drawn from the attachment (goal) end back
##   toward the tile by the order's reveal fraction.
## Only active while the 'toggle roadsv2' cheat has v2 enabled.

const TRUNK_COLOR := Color("d97b29")
const LOCAL_COLOR := Color("e8c84a")
const CASING := Color(0.24, 0.16, 0.05, 0.9)
const TRUNK_WIDTH := 7.0
const LOCAL_WIDTH := 4.5
const BRIDGE_COLOR := Color(0.32, 0.2, 0.08)
# Roundabout: a node where MORE than 4 roads meet gets an OVAL RING (~7u x 4u).
# It sits where the roads actually converge (centroid of their near-node geometry,
# which is off any forest/river the bare junction node may sit on — that was the
# "oval stranded on a forest" bug). The incident roads are CLIPPED at the rim so
# they run into it and the inside stays clear — no road crosses the island. The
# minor axis flattens along the uphill so the oval doesn't climb, and the rim is
# budged inward where a river cuts close, keeping ~3-4u of river clearance.
const ROUNDABOUT_MIN_DEGREE := 5
const ROUNDABOUT_MAJOR := 35.0       # semi-major (~7u across)
const ROUNDABOUT_MINOR := 20.0       # semi-minor, unflattened (~4u across)
const ROUNDABOUT_MINOR_MIN := 12.0   # flatten floor — the loop's gap never closes below ~1u
const ROUNDABOUT_RING_SEG := 32      # rim resolution
const ROUNDABOUT_RIVER_CLEAR := 35.0 # ~3-4u: keep the rim at least this far off a river

var _drawn_edges := -1
var _drawn_previews := -1
var _active_layer: Node2D = null

func _ready() -> void:
	_active_layer = Node2D.new()
	_active_layer.name = "ActiveReveals"
	_active_layer.draw.connect(_draw_active)
	add_child(_active_layer)
	RoadWorks.order_settled.connect(func(_id: int) -> void: _drawn_edges = -1)

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
	var rabouts := _compute_roundabouts(network)   # node_id -> {center, rim}
	# Clip each BUILT edge against any roundabout it touches (once; used both passes).
	var clipped: Dictionary = {}
	for edge_id in network.edges:
		var edge: Dictionary = network.edges[edge_id]
		if str(edge.state) != RoadNetwork.STATE_BUILT:
			continue
		clipped[edge_id] = _clip_edge(edge.geometry, str(edge.a), str(edge.b), rabouts)
	for pass_i in 2:   # casing under colour
		for edge_id3 in clipped:
			_draw_edge_polyline(self, clipped[edge_id3], str(network.edges[edge_id3].tier), pass_i)
	for edge_id2 in network.edges:
		var edge2: Dictionary = network.edges[edge_id2]
		if str(edge2.state) != RoadNetwork.STATE_BUILT:
			continue
		for bridge in edge2.bridges:
			var t: Vector2 = bridge.tangent
			draw_line(bridge.point - t * 21.0, bridge.point + t * 21.0, BRIDGE_COLOR, 10.0, true)
	# Preview bridges: drawn the instant a river road is built, at its
	# predetermined crossing, while the connecting road is still planning.
	for pb in RoadWorks.preview_bridges():
		var pt: Vector2 = pb.tangent
		draw_line(pb.point - pt * 21.0, pb.point + pt * 21.0, BRIDGE_COLOR, 10.0, true)
	# Roundabout rings on top, inside left clear (roads were clipped at the rim).
	for nid in rabouts:
		var rim: PackedVector2Array = rabouts[nid].rim
		if rim.size() < 3:
			continue
		var loop := rim.duplicate()
		loop.append(rim[0])
		draw_polyline(loop, CASING, LOCAL_WIDTH + 3.0, true)
		draw_polyline(loop, LOCAL_COLOR, LOCAL_WIDTH, true)

## node_id -> {center, rim} for every node where >4 BUILT roads meet. The centre
## is the convergence of the incident roads (off the bare junction's forest/river),
## the rim a flattened, river-budged ellipse. Runs only on redraw (settle/count).
func _compute_roundabouts(network: RoadNetwork) -> Dictionary:
	var degree: Dictionary = {}
	var incident: Dictionary = {}
	for eid in network.edges:
		var e: Dictionary = network.edges[eid]
		if str(e.state) != RoadNetwork.STATE_BUILT:
			continue
		for nid in [str(e.a), str(e.b)]:
			degree[nid] = int(degree.get(nid, 0)) + 1
			if not incident.has(nid):
				incident[nid] = []
			incident[nid].append(eid)
	var out: Dictionary = {}
	var nav := NavGrid.instance()
	for nid in degree:
		if int(degree[nid]) < ROUNDABOUT_MIN_DEGREE:
			continue
		var node: Dictionary = network.nodes.get(nid, {})
		if node.is_empty():
			continue
		var center := _roundabout_center(network, incident[nid], node.pos)
		out[nid] = {"center": center, "rim": _roundabout_rim(center, nav)}
	return out

## Centre = mean of where the incident roads sit ~one semi-major out from the
## junction. That's literally on the roads (and so off any forest/river the bare
## node may occupy), which is where the oval belongs.
func _roundabout_center(network: RoadNetwork, edge_ids: Array, node_pos: Vector2) -> Vector2:
	var acc := Vector2.ZERO
	var n := 0
	for eid in edge_ids:
		var p := _road_point_near_node(network.edges[eid].geometry, node_pos, ROUNDABOUT_MAJOR)
		acc += p
		n += 1
	return acc / float(n) if n > 0 else node_pos

## The point ~`dist` along an edge from whichever end is the junction node.
func _road_point_near_node(geo: PackedVector2Array, node_pos: Vector2, dist: float) -> Vector2:
	var n := geo.size()
	if n == 0:
		return node_pos
	if geo[0].distance_squared_to(node_pos) <= geo[n - 1].distance_squared_to(node_pos):
		var walked := 0.0
		for i in range(1, n):
			walked += geo[i - 1].distance_to(geo[i])
			if walked >= dist:
				return geo[i]
		return geo[n - 1]
	var walked2 := 0.0
	for j in range(n - 2, -1, -1):
		walked2 += geo[j + 1].distance_to(geo[j])
		if walked2 >= dist:
			return geo[j]
	return geo[0]

## A flattened ellipse polygon about `center`; rim points within river clearance
## are budged inward so the oval keeps ~3-4u off a river (it cuts into the oval).
func _roundabout_rim(center: Vector2, nav: NavGrid) -> PackedVector2Array:
	var g := _elevation_gradient(nav, center)
	var minor := ROUNDABOUT_MINOR
	var rot := 0.0
	if g.length() > 0.05:
		rot = g.angle() - PI * 0.5            # minor axis points uphill (so the oval flattens up-slope)
		minor = clampf(ROUNDABOUT_MINOR - g.length() * 3.0, ROUNDABOUT_MINOR_MIN, ROUNDABOUT_MINOR)
	var rim := PackedVector2Array()
	for k in ROUNDABOUT_RING_SEG:
		var t := TAU * float(k) / float(ROUNDABOUT_RING_SEG)
		var p: Vector2 = center + Vector2(cos(t) * ROUNDABOUT_MAJOR, sin(t) * minor).rotated(rot)
		rim.append(_budge_off_river(p, center, nav))
	return rim

## Pull a rim point toward the centre until it is at least ROUNDABOUT_RIVER_CLEAR
## from the nearest river (so a river cuts a flat into the oval rather than the
## oval overlapping it), but never past the minor-axis floor.
func _budge_off_river(p: Vector2, center: Vector2, nav: NavGrid) -> Vector2:
	if _river_dist(p, nav) >= ROUNDABOUT_RIVER_CLEAR:
		return p
	var dir := (center - p)
	if dir.length() < 1.0:
		return p
	dir = dir.normalized()
	var moved := p
	for _i in 8:
		moved += dir * 6.0
		if moved.distance_to(center) <= ROUNDABOUT_MINOR_MIN:
			break
		if _river_dist(moved, nav) >= ROUNDABOUT_RIVER_CLEAR:
			break
	return moved

## Distance to the nearest RIVER cell within ROUNDABOUT_RIVER_CLEAR of `p`
## (capped — only the "is a river close" question matters here).
func _river_dist(p: Vector2, nav: NavGrid) -> float:
	if nav == null or not nav.is_ready():
		return 1e9
	var c := nav.cell_of(p)
	var reach := int(ceil(ROUNDABOUT_RIVER_CLEAR / nav.step)) + 1
	var best := ROUNDABOUT_RIVER_CLEAR
	var found := false
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var nx := c.x + dx
			var ny := c.y + dy
			if nx < 0 or ny < 0 or nx >= nav.gw or ny >= nav.gh:
				continue
			if (nav.cells[ny * nav.gw + nx] >> 4) != 3:   # 3 = NAV_WATER_RIVER
				continue
			var d := nav.world_of(nx, ny).distance_to(p)
			if d < best:
				best = d
				found = true
	return best if found else 1e9

## Clip an edge's polyline against any roundabout at its endpoints, so the road
## runs INTO the rim and stops — the oval's interior stays clear of roads.
func _clip_edge(geo: PackedVector2Array, a_id: String, b_id: String, rabouts: Dictionary) -> PackedVector2Array:
	var out := geo
	if rabouts.has(a_id):
		out = _clip_inside_end(out, rabouts[a_id].rim, false)
	if rabouts.has(b_id):
		out = _clip_inside_end(out, rabouts[b_id].rim, true)
	return out

## Trim points that fall inside `rim` from one end (from_end=false trims the
## start), replacing the last trimmed span with the exact rim crossing.
func _clip_inside_end(geo: PackedVector2Array, rim: PackedVector2Array, from_end: bool) -> PackedVector2Array:
	var pts := geo
	if from_end:
		pts = pts.duplicate()
		pts.reverse()
	var n := pts.size()
	var i := 0
	while i < n and Geometry2D.is_point_in_polygon(pts[i], rim):
		i += 1
	if i == 0:
		return geo                    # this end is already outside the oval
	if i >= n:
		return PackedVector2Array()   # whole edge is inside — drop it
	var cross := _rim_crossing(pts[i - 1], pts[i], rim)
	var trimmed := PackedVector2Array([cross])
	for j in range(i, n):
		trimmed.append(pts[j])
	if from_end:
		trimmed.reverse()
	return trimmed

## Boundary point between an inside point and an outside point (binary search).
func _rim_crossing(p_in: Vector2, p_out: Vector2, rim: PackedVector2Array) -> Vector2:
	var lo := 0.0
	var hi := 1.0
	for _i in 12:
		var mid := (lo + hi) * 0.5
		if Geometry2D.is_point_in_polygon(p_in.lerp(p_out, mid), rim):
			lo = mid
		else:
			hi = mid
	return p_in.lerp(p_out, hi)

## Level gradient (levels per ~2 cells) at a world point, from the navgrid bands.
func _elevation_gradient(nav: NavGrid, world: Vector2) -> Vector2:
	if nav == null or not nav.is_ready():
		return Vector2.ZERO
	var cell := nav.cell_of(world)
	if cell.x <= 0 or cell.y <= 0 or cell.x >= nav.gw - 1 or cell.y >= nav.gh - 1:
		return Vector2.ZERO
	var gw := nav.gw
	var i := cell.y * gw + cell.x
	var gx := float((nav.cells[i + 1] & 0x0F) - (nav.cells[i - 1] & 0x0F))
	var gy := float((nav.cells[i + gw] & 0x0F) - (nav.cells[i - gw] & 0x0F))
	return Vector2(gx, gy)

func _draw_active() -> void:
	var network := RoadNetwork.instance()
	for edge_id in network.edges:
		var edge: Dictionary = network.edges[edge_id]
		if str(edge.state) != RoadNetwork.STATE_BUILDING:
			continue
		var frac := RoadWorks.reveal_fraction(str(edge_id))
		var revealed := _suffix_by_fraction(edge.geometry, frac)
		if revealed.size() < 2:
			continue
		for pass_i in 2:
			_draw_edge_polyline(_active_layer, revealed, str(edge.tier), pass_i)

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
		canvas.draw_polyline(pts, CASING, width + 2.5, true)
	else:
		canvas.draw_polyline(pts, TRUNK_COLOR if tier == RoadNetwork.TIER_TRUNK else LOCAL_COLOR, width, true)
