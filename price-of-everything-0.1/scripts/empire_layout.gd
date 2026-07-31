extends RefCounted
## Empire view — deterministic node packing (Milestone 2).
##
## Pure layout math, no scene-tree / sim dependencies (CLAUDE.md rule #1), so it is unit
## testable headless. Seeds each node at its building's world position, then runs collision-
## separation relaxation (AABB push-apart, NOT springy force-directed) with a weak anchor pull
## back to the seed so geography stays recognizable while every pair keeps a >=30px gap.
##
## Operates on an Array of plain Dictionaries; each node MUST provide:
##   iid  : String   — stable id, used for deterministic ordering / tie-break jitter
##   seed : Vector2  — desired position (world/layout space)
##   half : Vector2  — half-extent of the node's box, in layout pixels (level-scaled by the caller)
## After relax() each node has:
##   pos  : Vector2  — the packed position
## Determinism (rule #3): ordering is by sorted iid and the only "randomness" is RoadHash.pick().

const LEVEL_SCALE := {1: 1.0, 2: 1.5, 3: 2.25}   # node size grows with building level
const GAP := 30.0                                 # required clear gap between boxes (layout px)
const PAD := GAP * 0.5                             # folded into each box's half-extent
const MAX_ITERS := 80
const ANCHOR_PULL := 0.02                          # per-iter fraction pulling a node back to its seed

# Layered (supply-chain) layout spacing. Generous so panels read as airy columns.
const COL_SPACING := 470.0                         # horizontal distance between supply layers (columns)
const ROW_GAP := 90.0                              # vertical gap between stacked nodes in a column
const COMP_GAP := 230.0                            # gap between separate chains / isolated nodes
const FLOW_WIDTH := 3400.0                         # legacy wrap width (no-sector path only)
const BARY_SWEEPS := 4                             # crossing-reduction passes

# Port-sector layout (owner direction 2026-07-30): chains gather over the port they sell
# through, so a port's share of the row width GROWS with the empire that feeds it.
const SECTOR_GAP := 340.0                          # horizontal gap between adjacent port sectors
const SECTOR_FLOW_WIDTH := 1900.0                  # wrap a sector's chains past this width — keeps
                                                   # sectors squarish instead of one tall tower
const SECTOR_MIN_W := 220.0                        # a port with no feeders still holds a slot
const MIN_PORT_SEP := 280.0                        # port hexes never sit closer than this

const RoadHash := preload("res://scripts/road_hash.gd")


const PORT_SPACING := 380.0                        # horizontal gap between ports in the bottom row
const PORT_ROW_GAP := 260.0                         # vertical gap from the building block to the port row

## Full layout entry point for the Empire view: place each node into supply-chain columns
## (input sources left of their consumers, crossings minimized), then enforce the min gap.
## `nodes` are plain dicts with iid/seed/half/level; `edges` are {from, to} producer->consumer.
## With `sell_edges` + `ports`, connected chains are additionally grouped into a horizontal
## SECTOR per destination port (fixed port order), so each port's slice of the row is as wide
## as the empire feeding it. Omitting them keeps the old single-block behaviour (unit tests).
## Writes `pos` on every node and `sector_cx` on each port that owns a sector.
static func solve(nodes: Array, edges: Array, sell_edges: Array = [], ports: Array = []) -> void:
	_assign_layered_seeds(nodes, edges, sell_edges, ports)
	relax(nodes)


## Bounding box over a set of laid-out nodes (using each node's pos +/- half).
static func bbox_of(nodes: Array) -> Rect2:
	var bb := Rect2()
	var first := true
	for n in nodes:
		var r := Rect2((n["pos"] as Vector2) - (n["half"] as Vector2), (n["half"] as Vector2) * 2.0)
		if first:
			bb = r
			first = false
		else:
			bb = bb.merge(r)
	return bb


## Place ports in a single row below the building block, in their pre-sorted order (Stoneshore, Arin,
## Vandel, Capital). A port that owns a sector sits CENTRED UNDER ITS SECTOR (written by solve as
## `sector_cx`), so port separation grows with the chains feeding each port; ports without a sector
## fall back to fixed spacing. A left-to-right pass then enforces a minimum separation so two
## thin sectors cannot stack their hexes. Leaves a tall gap above for the gold sell-line bus lanes.
static func place_ports(ports: Array, area: Rect2) -> void:
	if ports.is_empty():
		return
	var y := area.end.y + PORT_ROW_GAP
	var xs: Array[float] = []
	var any_sector := false
	for p in ports:
		if (p as Dictionary).has("sector_cx"):
			any_sector = true
	for i in range(ports.size()):
		var p: Dictionary = ports[i]
		if p.has("sector_cx"):
			xs.append(float(p["sector_cx"]))
		elif any_sector:
			# No sector of its own: hang just right of the previous port's slot.
			xs.append((xs[i - 1] + MIN_PORT_SEP) if i > 0 else area.position.x)
		else:
			xs.append(area.get_center().x - float(ports.size() - 1) * PORT_SPACING * 0.5 				+ float(i) * PORT_SPACING)
	for i in range(1, xs.size()):
		xs[i] = maxf(xs[i], xs[i - 1] + MIN_PORT_SEP)
	for i in range(ports.size()):
		ports[i]["pos"] = Vector2(xs[i], y)


## The BUY row mirrors the sell-port row on the TOP edge: each top hex sits at the SAME x as
## its bottom twin (matched via `mirror_of`), same standoff above the block as the sell row
## keeps below it — buys enter from the top, sales leave through the bottom, and the two rows
## frame the empire as aligned columns. Run AFTER place_ports (it reads the sell positions).
static func place_buy_ports(buy_ports: Array, ports: Array, area: Rect2) -> void:
	if buy_ports.is_empty():
		return
	var x_of: Dictionary = {}
	for p in ports:
		x_of[str((p as Dictionary)["iid"])] = ((p as Dictionary).get("pos", Vector2.ZERO) as Vector2).x
	var y := area.position.y - PORT_ROW_GAP
	# Kept ALIGNED with the sell twin. Offsetting the buy row by half a port pitch was tried on
	# the theory that buy and sell lines were sharing corridors — measured, it moved buy-vs-sell
	# crossings 17 -> 18 and the total not at all. The crossings are a ROUTING property (both
	# families traverse the whole block vertically), not a port-placement one.
	for bp in buy_ports:
		var mx: float = float(x_of.get(str((bp as Dictionary).get("mirror_of", "")), area.get_center().x))
		bp["pos"] = Vector2(mx, y)


## Multiply a base half-extent by the level's size factor (L1 x1, L2 x1.5, L3 x2.25).
static func level_scale(level: int) -> float:
	return float(LEVEL_SCALE.get(clampi(level, 1, 3), 1.0))


## Pack nodes in place: writes `pos` on each. The final state guarantees no two inflated
## boxes overlap, i.e. every pair of real boxes is separated by >=GAP on at least one axis.
static func relax(nodes: Array) -> void:
	if nodes.size() <= 1:
		for n in nodes:
			n["pos"] = n["seed"]
		return

	nodes.sort_custom(func(a, b): return String(a["iid"]) < String(b["iid"]))
	for n in nodes:
		n["pos"] = n["seed"]
		n["_inflated"] = (n["half"] as Vector2) + Vector2(PAD, PAD)

	# Settle geography: anchor pull first (so separation always has the last word), then separate.
	for _it in MAX_ITERS:
		for n in nodes:
			n["pos"] = (n["pos"] as Vector2) + ((n["seed"] as Vector2) - (n["pos"] as Vector2)) * ANCHOR_PULL
		_separate_once(nodes)

	# Finalize: pure separation until a pass makes no move, so the >=GAP invariant holds.
	for _it in MAX_ITERS:
		if not _separate_once(nodes):
			break


## One O(n^2) separation pass. Returns true if any node moved. ~50 nodes => 1225 pairs, trivial.
static func _separate_once(nodes: Array) -> bool:
	var moved := false
	var count := nodes.size()
	for i in range(count):
		var n: Dictionary = nodes[i]
		for j in range(i + 1, count):
			var m: Dictionary = nodes[j]
			var d: Vector2 = (m["pos"] as Vector2) - (n["pos"] as Vector2)
			var ni: Vector2 = n["_inflated"]
			var mi: Vector2 = m["_inflated"]
			var ox: float = ni.x + mi.x - absf(d.x)
			var oy: float = ni.y + mi.y - absf(d.y)
			if ox <= 0.0 or oy <= 0.0:
				continue   # no overlap on at least one axis
			moved = true
			if ox <= oy:   # push along the least-penetration axis, split 50/50
				var s := 0.5 * ox * (1.0 if d.x >= 0.0 else -1.0)
				if absf(d.x) < 0.001:
					s = _det_jitter(str(n["iid"])).x
				n["pos"] = (n["pos"] as Vector2) - Vector2(s, 0.0)
				m["pos"] = (m["pos"] as Vector2) + Vector2(s, 0.0)
			else:
				var s2 := 0.5 * oy * (1.0 if d.y >= 0.0 else -1.0)
				if absf(d.y) < 0.001:
					s2 = _det_jitter(str(n["iid"])).y
				n["pos"] = (n["pos"] as Vector2) - Vector2(0.0, s2)
				m["pos"] = (m["pos"] as Vector2) + Vector2(0.0, s2)
	return moved


## Deterministic unit-ish nudge for coincident seeds (e.g. two buildings on the same tile),
## so they fan out reproducibly instead of never separating.
static func _det_jitter(iid: String) -> Vector2:
	var ang := deg_to_rad(float(RoadHash.pick("empire_layout|" + iid, 360)))
	return Vector2(cos(ang), sin(ang)) * 0.5


## Assign each node a `seed` position from a layered DAG layout: columns = supply depth
## (longest-path layering, cycle-safe), within-column order minimizes edge crossings (barycenter
## sweeps), and disconnected supply chains are flow-packed into separate blocks so their lines do
## not cross unrelated panels.
static func _assign_layered_seeds(nodes: Array, edges: Array, sell_edges: Array = [], ports: Array = []) -> void:
	if nodes.is_empty():
		return
	var by_iid: Dictionary = {}
	for n in nodes:
		by_iid[str(n["iid"])] = n

	# Directed adjacency (producer -> consumer) limited to nodes we actually have.
	var out_e: Dictionary = {}
	var in_e: Dictionary = {}
	for n in nodes:
		out_e[str(n["iid"])] = []
		in_e[str(n["iid"])] = []
	var real_edges: Array = []
	for e in edges:
		var f := str(e["from"])
		var t := str(e["to"])
		if f != t and by_iid.has(f) and by_iid.has(t):
			out_e[f].append(t)
			in_e[t].append(f)
			real_edges.append([f, t])

	# Longest-path layering. Iteration cap makes it safe even if the supply graph has a cycle.
	var layer: Dictionary = {}
	for n in nodes:
		layer[str(n["iid"])] = 0
	var guard := nodes.size() + 2
	var changed := true
	while changed and guard > 0:
		changed = false
		guard -= 1
		for pair in real_edges:
			if layer[pair[1]] <= layer[pair[0]]:
				layer[pair[1]] = layer[pair[0]] + 1
				changed = true

	# Connected components (union-find over undirected edges).
	var parent: Dictionary = {}
	for n in nodes:
		parent[str(n["iid"])] = str(n["iid"])
	for pair in real_edges:
		var ra := _uf_find(parent, pair[0])
		var rb := _uf_find(parent, pair[1])
		if ra != rb:
			parent[ra] = rb
	var comps: Dictionary = {}
	for n in nodes:
		var r := _uf_find(parent, str(n["iid"]))
		if not comps.has(r):
			comps[r] = []
		comps[r].append(str(n["iid"]))

	# Deterministic component order: larger chains first, ties by smallest iid.
	var comp_keys: Array = comps.keys()
	comp_keys.sort_custom(func(a, b):
		var ca: Array = comps[a]
		var cb: Array = comps[b]
		if ca.size() != cb.size():
			return ca.size() > cb.size()
		return _min_str(ca) < _min_str(cb))

	if sell_edges.is_empty() or ports.is_empty():
		# Legacy single-block path (also the unit-test path): flow-pack all components.
		_pack_components(comp_keys, comps, by_iid, in_e, out_e, layer, 0.0, FLOW_WIDTH)
		return

	# ---- Port sectors ----
	# Each component votes with its members' sell edges; majority destination owns it,
	# ties break toward the earlier (leftmost) port. Components that sell nowhere form a
	# final "internal" sector on the right, with no port beneath it.
	var comp_of: Dictionary = {}                     # iid -> component root
	for r in comps:
		for iid in comps[r]:
			comp_of[iid] = r
	var port_rank: Dictionary = {}                   # port iid -> fixed order index
	for i in range(ports.size()):
		port_rank[str((ports[i] as Dictionary)["iid"])] = i
	var votes: Dictionary = {}                       # root -> {port index: count}
	for se in sell_edges:
		var f := str((se as Dictionary)["from"])
		var t := str((se as Dictionary)["to"])
		if not (comp_of.has(f) and port_rank.has(t)):
			continue
		var root: String = comp_of[f]
		if not votes.has(root):
			votes[root] = {}
		var pi := int(port_rank[t])
		votes[root][pi] = int((votes[root] as Dictionary).get(pi, 0)) + 1
	var owner: Dictionary = {}                       # root -> sector index (ports.size() = internal)
	for r in comps:
		var best := ports.size()
		var best_n := 0
		if votes.has(r):
			var vr: Dictionary = votes[r]
			var pis: Array = vr.keys()
			pis.sort()
			for pi in pis:
				if int(vr[pi]) > best_n:
					best_n = int(vr[pi])
					best = int(pi)
		owner[r] = best

	# Lay each sector out left -> right in fixed port order; the sector's centre is written
	# onto its port (place_ports reads it), so port separation follows sector width.
	var x0 := 0.0
	for si in range(ports.size() + 1):
		var mine: Array = comp_keys.filter(func(r): return int(owner[r]) == si)
		var w := SECTOR_MIN_W
		if not mine.is_empty():
			w = _pack_components(mine, comps, by_iid, in_e, out_e, layer, x0, SECTOR_FLOW_WIDTH)
		if si < ports.size():
			ports[si]["sector_cx"] = x0 + w * 0.5
		x0 += w + SECTOR_GAP


## Flow-pack a list of components into rows starting at x offset `x0`, wrapping at `wrap_w`.
## Returns the packed block's width.
static func _pack_components(comp_keys: Array, comps: Dictionary, by_iid: Dictionary,
		in_e: Dictionary, out_e: Dictionary, layer: Dictionary, x0: float, wrap_w: float) -> float:
	var cx := 0.0
	var cy := 0.0
	var row_h := 0.0
	var width := 0.0
	for r in comp_keys:
		var ids: Array = comps[r]
		ids.sort()
		var comp := _layout_component(ids, by_iid, in_e, out_e, layer)
		var csize: Vector2 = comp["size"]
		if cx > 0.0 and cx + csize.x > wrap_w:
			cx = 0.0
			cy += row_h + COMP_GAP
			row_h = 0.0
		var local: Dictionary = comp["local"]
		for iid in local:
			by_iid[iid]["seed"] = (local[iid] as Vector2) + Vector2(x0 + cx, cy)
		cx += csize.x + COMP_GAP
		row_h = maxf(row_h, csize.y)
		width = maxf(width, cx - COMP_GAP)
	return width


## Place one connected component into local coordinates. Returns { local: {iid:Vector2}, size:Vector2 }.
static func _layout_component(ids: Array, by_iid: Dictionary, in_e: Dictionary, out_e: Dictionary, layer: Dictionary) -> Dictionary:
	var min_layer := 1 << 30
	for iid in ids:
		min_layer = mini(min_layer, int(layer[iid]))
	var cols: Dictionary = {}                       # column index -> [iid]
	for iid in ids:
		var c := int(layer[iid]) - min_layer
		if not cols.has(c):
			cols[c] = []
		cols[c].append(iid)
	var col_keys: Array = cols.keys()
	col_keys.sort()
	for c in col_keys:
		(cols[c] as Array).sort()

	var order: Dictionary = {}
	_reindex(cols, col_keys, order)
	for _sweep in BARY_SWEEPS:
		for ci in range(1, col_keys.size()):                       # forward: order by producers (left)
			_sort_by_bary(cols[col_keys[ci]], in_e, order)
		_reindex(cols, col_keys, order)
		for ci in range(col_keys.size() - 2, -1, -1):              # backward: order by consumers (right)
			_sort_by_bary(cols[col_keys[ci]], out_e, order)
		_reindex(cols, col_keys, order)

	# Tile clustering (owner direction 2026-07-30): within a column, buildings on the same
	# map tile become ADJACENT. Runs after the barycenter sweeps and preserves each tile
	# group's mean crossing-minimized rank, so it trades a few crossings for co-located
	# buildings reading as one site — not the whole ordering.
	for c in col_keys:
		_cluster_by_tile(cols[c], by_iid)
	_reindex(cols, col_keys, order)

	# Assign positions: x by column, y stacked (accounting for box heights), each column centred on 0.
	var local: Dictionary = {}
	for ci in range(col_keys.size()):
		var c = col_keys[ci]
		var col: Array = cols[c]
		var total_h := 0.0
		for iid in col:
			total_h += (by_iid[iid]["half"] as Vector2).y * 2.0 + ROW_GAP
		total_h -= ROW_GAP
		var y := -total_h * 0.5
		for iid in col:
			var h := (by_iid[iid]["half"] as Vector2).y * 2.0
			local[iid] = Vector2(float(ci) * COL_SPACING, y + h * 0.5)
			y += h + ROW_GAP

	# Normalize so the component's bounding box starts at the origin; return its size for packing.
	var bb := Rect2()
	var first := true
	for iid in local:
		var r := Rect2((local[iid] as Vector2) - (by_iid[iid]["half"] as Vector2), (by_iid[iid]["half"] as Vector2) * 2.0)
		if first:
			bb = r
			first = false
		else:
			bb = bb.merge(r)
	for iid in local:
		local[iid] = (local[iid] as Vector2) - bb.position
	return {"local": local, "size": bb.size}


## Reorder one column so tile-mates sit together: groups keyed by tile_id, each group placed
## at its members' mean rank, members keeping their relative order. Nodes without a tile_id
## (unit-test fixtures) each form their own group, i.e. the pass is a no-op for them.
static func _cluster_by_tile(col: Array, by_iid: Dictionary) -> void:
	if col.size() < 3:
		return
	var rank: Dictionary = {}
	for i in range(col.size()):
		rank[col[i]] = i
	var groups: Dictionary = {}                      # group key -> [iids]
	for iid in col:
		var t := str((by_iid[iid] as Dictionary).get("tile_id", ""))
		var key := t if t != "" else "solo|" + str(iid)
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(iid)
	if groups.size() == col.size():
		return                                       # every node alone -> nothing to do
	var gkeys: Array = groups.keys()
	gkeys.sort_custom(func(a, b):
		var ma := _mean_rank(groups[a], rank)
		var mb := _mean_rank(groups[b], rank)
		if not is_equal_approx(ma, mb):
			return ma < mb
		return str(a) < str(b))
	col.clear()
	for k in gkeys:
		var g: Array = groups[k]
		g.sort_custom(func(a, b): return int(rank[a]) < int(rank[b]))
		col.append_array(g)


static func _mean_rank(ids: Array, rank: Dictionary) -> float:
	var sum := 0.0
	for iid in ids:
		sum += float(rank.get(iid, 0))
	return sum / float(ids.size())


static func _sort_by_bary(col: Array, neighbors: Dictionary, order: Dictionary) -> void:
	var bvals: Dictionary = {}
	for iid in col:
		bvals[iid] = _bary(iid, neighbors, order)
	col.sort_custom(func(a, b): return float(bvals[a]) < float(bvals[b]))


## Average rank of a node's neighbours; falls back to the node's own rank so it stays put.
static func _bary(iid: String, neighbors: Dictionary, order: Dictionary) -> float:
	var ns: Array = neighbors.get(iid, [])
	if ns.is_empty():
		return float(order.get(iid, 0))
	var sum := 0.0
	for nb in ns:
		sum += float(order.get(nb, 0))
	return sum / float(ns.size())


static func _reindex(cols: Dictionary, col_keys: Array, order: Dictionary) -> void:
	for c in col_keys:
		var col: Array = cols[c]
		for i in range(col.size()):
			order[col[i]] = i


static func _uf_find(parent: Dictionary, x: String) -> String:
	var r := x
	while str(parent[r]) != r:
		r = str(parent[r])
	var c := x
	while str(parent[c]) != r:
		var nx := str(parent[c])
		parent[c] = r
		c = nx
	return r


static func _min_str(arr: Array) -> String:
	var m := str(arr[0])
	for v in arr:
		if str(v) < m:
			m = str(v)
	return m


## True if every pair of inflated boxes is non-overlapping — the post-relax invariant.
## Exposed for tests.
static func gap_satisfied(nodes: Array) -> bool:
	for i in range(nodes.size()):
		for j in range(i + 1, nodes.size()):
			var a: Dictionary = nodes[i]
			var b: Dictionary = nodes[j]
			var d: Vector2 = (b["pos"] as Vector2) - (a["pos"] as Vector2)
			var ah: Vector2 = (a["half"] as Vector2) + Vector2(PAD, PAD)
			var bh: Vector2 = (b["half"] as Vector2) + Vector2(PAD, PAD)
			if (ah.x + bh.x - absf(d.x)) > 0.001 and (ah.y + bh.y - absf(d.y)) > 0.001:
				return false
	return true
