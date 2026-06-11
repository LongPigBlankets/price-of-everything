extends Node2D
## Debug renderer for the roads-v2 network (Phase 2). Draws committed edges
## with the tiered atlas placeholder language — trunk orange over yellow-local,
## both with darker casing — plus bridge glyphs. Only active while the
## 'toggle roadsv2' cheat has v2 enabled; the static layer redraws when the
## edge count changes (no per-frame replanning, unlike v1).

const TRUNK_COLOR := Color("d97b29")
const LOCAL_COLOR := Color("e8c84a")
const CASING := Color(0.24, 0.16, 0.05, 0.9)
const TRUNK_WIDTH := 7.0
const LOCAL_WIDTH := 4.5
const BRIDGE_COLOR := Color(0.32, 0.2, 0.08)

var _drawn_edges := -1

func _process(_delta: float) -> void:
	var network := RoadNetwork.instance()
	var want := network.edge_count() if RoadNetwork.v2_enabled else 0
	if want != _drawn_edges:
		_drawn_edges = want
		queue_redraw()

func _draw() -> void:
	if not RoadNetwork.v2_enabled:
		return
	var network := RoadNetwork.instance()
	for pass_i in 2:   # casing under colour
		for edge_id in network.edges:
			var edge: Dictionary = network.edges[edge_id]
			var pts: PackedVector2Array = edge.geometry
			if pts.size() < 2:
				continue
			var width: float = TRUNK_WIDTH if edge.tier == RoadNetwork.TIER_TRUNK else LOCAL_WIDTH
			if pass_i == 0:
				draw_polyline(pts, CASING, width + 2.5, true)
			else:
				draw_polyline(pts, TRUNK_COLOR if edge.tier == RoadNetwork.TIER_TRUNK else LOCAL_COLOR, width, true)
	for edge_id2 in network.edges:
		for bridge in network.edges[edge_id2].bridges:
			var t: Vector2 = bridge.tangent
			draw_line(bridge.point - t * 21.0, bridge.point + t * 21.0, BRIDGE_COLOR, 10.0, true)
