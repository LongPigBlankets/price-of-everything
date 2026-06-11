class_name RoadNetwork
extends RefCounted
## The persistent roads-v2 graph (spec 2.1). Nodes are the places roads care
## about (tile gateways, river crossings, orbital ports, building bunches,
## junctions); edges carry tier, state and realized geometry. The graph IS the
## shared-anchor cache: GATEWAY ids use the undirected tile-pair key so
## flanking tiles agree on one node, and the first route to touch a gateway
## records its point + arrival tangent for later continuations (tangent
## continuity across seams).
##
## Build order changes the network (designer ruling #3); the only guarantee is
## same save -> same result. export_state()/import_state() round-trip the
## whole graph as-built; SaveLoad wiring lands with the Phase-3 work orders.

const KIND_GATEWAY := "gateway"
const KIND_CROSSING := "crossing"
const KIND_ORBITAL_PORT := "orbital_port"
const KIND_BUNCH := "bunch"
const KIND_JUNCTION := "junction"

const TIER_TRUNK := "trunk"
const TIER_LOCAL := "local"

const STATE_PLANNED := "planned"
const STATE_BUILDING := "building"
const STATE_BUILT := "built"

## Reuse-discount occupancy hash cell (cost x0.6 within ~24 u of the network).
const OCCUPANCY_CELL := 24.0

static var v2_enabled := false           # 'toggle roadsv2' debug cheat
static var _inst: RoadNetwork = null

var nodes: Dictionary = {}               # id -> node dict
var edges: Dictionary = {}               # id -> edge dict
var _edges_by_tile: Dictionary = {}      # Vector2i -> Array[edge_id]
var _occupancy: Dictionary = {}          # Vector2i (24u hash cell) -> true
var _next_edge := 1
var _next_node := 1

static func instance() -> RoadNetwork:
	if _inst == null:
		_inst = RoadNetwork.new()
	return _inst

static func reset() -> void:
	_inst = null

# ------------------------------------------------------------------- nodes

func gateway_id(tile_a: Vector2i, tile_b: Vector2i) -> String:
	# undirected tile-pair key — both flanking tiles resolve to the same node
	var a := "%d_%d" % [tile_a.x, tile_a.y]
	var b := "%d_%d" % [tile_b.x, tile_b.y]
	return "gw:%s|%s" % [a, b] if a < b else "gw:%s|%s" % [b, a]

func ensure_node(id: String, kind: String, pos: Vector2, tile: Vector2i) -> Dictionary:
	if nodes.has(id):
		return nodes[id]
	var node := {
		"id": id, "kind": kind, "pos": pos, "tile": tile,
		"tangent": Vector2.ZERO,   # GATEWAY: agreed arrival direction (first writer wins)
	}
	nodes[id] = node
	return node

func add_junction(pos: Vector2, tile: Vector2i) -> Dictionary:
	var id := "jn:%d" % _next_node
	_next_node += 1
	return ensure_node(id, KIND_JUNCTION, pos, tile)

## First-writer-wins tangent contract (design 4.5): returns the agreed tangent,
## recording ours when the node has none yet.
func agree_tangent(node_id: String, tangent: Vector2) -> Vector2:
	var node: Dictionary = nodes.get(node_id, {})
	if node.is_empty():
		return tangent
	var existing: Vector2 = node.tangent
	if existing == Vector2.ZERO:
		node.tangent = tangent.normalized()
		return node.tangent
	return existing

# ------------------------------------------------------------------- edges

func add_edge(a_id: String, b_id: String, tier: String, geometry: PackedVector2Array, tiles: Array, bridges: Array, planned_turn: int) -> Dictionary:
	var id := "e:%d" % _next_edge
	_next_edge += 1
	var edge := {
		"id": id, "a": a_id, "b": b_id, "tier": tier,
		"state": STATE_BUILT, "tiles": tiles, "geometry": geometry,
		"bridges": bridges, "planned_turn": planned_turn,
	}
	edges[id] = edge
	for t in tiles:
		if not _edges_by_tile.has(t):
			_edges_by_tile[t] = []
		_edges_by_tile[t].append(id)
	_stamp_occupancy(geometry)
	return edge

func edges_on_tile(tile: Vector2i) -> Array:
	return _edges_by_tile.get(tile, [])

func edge_count() -> int:
	return edges.size()

# -------------------------------------------------- reuse-discount occupancy

func _stamp_occupancy(geometry: PackedVector2Array) -> void:
	for p in geometry:
		var c := Vector2i(int(floor(p.x / OCCUPANCY_CELL)), int(floor(p.y / OCCUPANCY_CELL)))
		_occupancy[c] = true

## True when a world point sits within ~one hash cell of existing roads.
func near_network(p: Vector2) -> bool:
	var c := Vector2i(int(floor(p.x / OCCUPANCY_CELL)), int(floor(p.y / OCCUPANCY_CELL)))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if _occupancy.has(Vector2i(c.x + dx, c.y + dy)):
				return true
	return false

func has_any_edges() -> bool:
	return not edges.is_empty()

# ---------------------------------------------------------------- save/load

func export_state() -> Dictionary:
	var nodes_out := {}
	for id in nodes:
		var n: Dictionary = nodes[id]
		nodes_out[id] = {
			"kind": n.kind, "pos": [n.pos.x, n.pos.y],
			"tile": [n.tile.x, n.tile.y], "tangent": [n.tangent.x, n.tangent.y],
		}
	var edges_out := {}
	for id2 in edges:
		var e: Dictionary = edges[id2]
		var geo: Array = []
		for p in e.geometry:
			geo.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01)])
		var tiles_out: Array = []
		for t in e.tiles:
			tiles_out.append([t.x, t.y])
		var bridges_out: Array = []
		for br in e.bridges:
			bridges_out.append({
				"point": [br.point.x, br.point.y],
				"tangent": [br.tangent.x, br.tangent.y],
			})
		edges_out[id2] = {
			"a": e.a, "b": e.b, "tier": e.tier, "state": e.state,
			"tiles": tiles_out, "geometry": geo, "bridges": bridges_out,
			"planned_turn": e.planned_turn,
		}
	return {
		"nodes": nodes_out, "edges": edges_out,
		"next_edge": _next_edge, "next_node": _next_node,
	}

func import_state(state: Dictionary) -> void:
	nodes.clear()
	edges.clear()
	_edges_by_tile.clear()
	_occupancy.clear()
	_next_edge = int(state.get("next_edge", 1))
	_next_node = int(state.get("next_node", 1))
	var nodes_in: Dictionary = state.get("nodes", {})
	for id in nodes_in:
		var n: Dictionary = nodes_in[id]
		nodes[id] = {
			"id": id, "kind": str(n.kind),
			"pos": Vector2(float(n.pos[0]), float(n.pos[1])),
			"tile": Vector2i(int(n.tile[0]), int(n.tile[1])),
			"tangent": Vector2(float(n.tangent[0]), float(n.tangent[1])),
		}
	var edges_in: Dictionary = state.get("edges", {})
	for id2 in edges_in:
		var e: Dictionary = edges_in[id2]
		var geo := PackedVector2Array()
		for p in e.geometry:
			geo.append(Vector2(float(p[0]), float(p[1])))
		var tiles: Array = []
		for t in e.tiles:
			tiles.append(Vector2i(int(t[0]), int(t[1])))
		var bridges: Array = []
		for br in e.bridges:
			bridges.append({
				"point": Vector2(float(br.point[0]), float(br.point[1])),
				"tangent": Vector2(float(br.tangent[0]), float(br.tangent[1])),
			})
		edges[id2] = {
			"id": id2, "a": str(e.a), "b": str(e.b), "tier": str(e.tier),
			"state": str(e.state), "tiles": tiles, "geometry": geo,
			"bridges": bridges, "planned_turn": int(e.planned_turn),
		}
		for t2 in tiles:
			if not _edges_by_tile.has(t2):
				_edges_by_tile[t2] = []
			_edges_by_tile[t2].append(id2)
		_stamp_occupancy(geo)
