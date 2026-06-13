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
# Roundabout: a node where MORE than 4 roads meet gets an oval ring (~3u x 2u);
# the roads run into its centre and disappear under it. The oval flattens along
# the uphill so it doesn't climb, but its inner gap never closes below ~1u.
const ROUNDABOUT_MIN_DEGREE := 5
const ROUNDABOUT_MAJOR := 15.0       # semi-major (~3u across)
const ROUNDABOUT_MINOR_MAX := 10.0   # semi-minor, unflattened (~2u across)
const ROUNDABOUT_MINOR_MIN := 5.0    # never narrower than ~1u between the loop's two sides

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
	for pass_i in 2:   # casing under colour
		for edge_id in network.edges:
			var edge: Dictionary = network.edges[edge_id]
			if str(edge.state) != RoadNetwork.STATE_BUILT:
				continue
			_draw_edge_polyline(self, edge.geometry, str(edge.tier), pass_i)
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
	_draw_roundabouts(network)

## An oval ring at every node where >4 BUILT roads meet. The minor axis runs
## along the uphill and shrinks with steepness (so the oval avoids climbing),
## clamped so the loop's gap stays >= ~1u; the major axis runs along the contour.
func _draw_roundabouts(network: RoadNetwork) -> void:
	var degree: Dictionary = {}
	for eid in network.edges:
		var e: Dictionary = network.edges[eid]
		if str(e.state) != RoadNetwork.STATE_BUILT:
			continue
		degree[str(e.a)] = int(degree.get(str(e.a), 0)) + 1
		degree[str(e.b)] = int(degree.get(str(e.b), 0)) + 1
	if degree.is_empty():
		return
	var nav := NavGrid.instance()
	for nid in degree:
		if int(degree[nid]) < ROUNDABOUT_MIN_DEGREE:
			continue
		var node: Dictionary = network.nodes.get(nid, {})
		if node.is_empty():
			continue
		var c: Vector2 = node.pos
		var g := _elevation_gradient(nav, c)
		var minor := ROUNDABOUT_MINOR_MAX
		var rot := 0.0
		if g.length() > 0.05:
			rot = g.angle() - PI * 0.5            # minor axis points uphill
			minor = clampf(ROUNDABOUT_MINOR_MAX - g.length() * 2.0, ROUNDABOUT_MINOR_MIN, ROUNDABOUT_MINOR_MAX)
		var ring := PackedVector2Array()
		for k in 25:
			var t := TAU * float(k) / 24.0
			ring.append(c + Vector2(cos(t) * ROUNDABOUT_MAJOR, sin(t) * minor).rotated(rot))
		draw_polyline(ring, CASING, LOCAL_WIDTH + 3.0, true)
		draw_polyline(ring, LOCAL_COLOR, LOCAL_WIDTH, true)

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
