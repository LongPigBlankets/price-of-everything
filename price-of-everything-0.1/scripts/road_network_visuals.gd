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
# Junctions are kept to at most 5 roads upstream (RoadWorks degree cap) — there
# is no special junction glyph; roads simply meet and merge.

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
	var terrain := _terrain()
	var flagged := _flagged_tiles(terrain)
	# Roads show ONLY where roads are built: clip every edge to tiles whose
	# infrastructure carries "roads", dropping spans over roadless tiles (the
	# baked region-web spill, a long connect across empty terrain, etc.).
	var runs_by_edge: Dictionary = {}
	for edge_id in network.edges:
		var edge: Dictionary = network.edges[edge_id]
		if str(edge.state) != RoadNetwork.STATE_BUILT:
			continue
		runs_by_edge[edge_id] = _clip_to_built(edge.geometry, terrain, flagged)
	for pass_i in 2:   # casing under colour
		for edge_id4 in runs_by_edge:
			for run in runs_by_edge[edge_id4]:
				_draw_edge_polyline(self, run, str(network.edges[edge_id4].tier), pass_i)
	for edge_id2 in network.edges:
		var edge2: Dictionary = network.edges[edge_id2]
		if str(edge2.state) != RoadNetwork.STATE_BUILT:
			continue
		for bridge in edge2.bridges:
			if not _point_built(terrain, flagged, bridge.point):
				continue   # the road there is hidden — so is its bridge
			var t: Vector2 = bridge.tangent
			draw_line(bridge.point - t * 21.0, bridge.point + t * 21.0, BRIDGE_COLOR, 10.0, true)
	# Preview bridges: drawn the instant a river road is built, at its
	# predetermined crossing, while the connecting road is still planning.
	for pb in RoadWorks.preview_bridges():
		if not _point_built(terrain, flagged, pb.point):
			continue
		var pt: Vector2 = pb.tangent
		draw_line(pb.point - pt * 21.0, pb.point + pt * 21.0, BRIDGE_COLOR, 10.0, true)

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
		canvas.draw_polyline(pts, CASING, width + 2.5, true)
	else:
		canvas.draw_polyline(pts, TRUNK_COLOR if tier == RoadNetwork.TIER_TRUNK else LOCAL_COLOR, width, true)
