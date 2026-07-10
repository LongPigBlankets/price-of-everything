extends Node
## Starting anchor network bake (roads-v3 rules). Run headless:
##     <godot> --headless res://tools/bake_roads.tscn
##
## Anchor tiles = the hand-authored "roads" tiles in tile_properties.csv
## ∪ every URBAN tile ∪ every tile carrying at least one non-farm, non-forest
## start building (start_buildings.json). Routes a deterministic minimum-
## spanning network between them over the baked navgrid, then adds LOOP edges
## (redundant routes) wherever the tree's detour ratio is worst — so the map
## reads as a road atlas (rings, alternatives), not a drainage tree. Every
## edge is routed by the realizer, so height rules (altitude cost, serpentine
## climbs, river gates) govern loops exactly like the spine; a loop whose
## routed path blows out vs its straight line (terrain said no) is skipped.
##
## Also emits "flagged_tiles": every tile the baked network crosses. A fresh
## match applies "roads" infrastructure to these (geometry == gameplay).
##
## Determinism: anchors sorted by tile id; Prim's MST with id tie-breaks;
## loop candidates picked by worst detour ratio with id tie-breaks; edges
## routed shortest-first (the spine accretes and the reuse discount grafts
## longer edges onto it); forest instance ids match world_map's seeding.

const OLD_GROWTH_BUILDING := "b_016"
const NORTH_MAX_ROW := 6
const OLD_GROWTH_TILE_TYPES := ["rural", "hill"]
const TRUNK_LENGTH := 1500.0
const OUT_PATH := "res://data/roads_baked.json"

## Loop-edge selection (designer ruling 2026-07-09: MST + loops + redundancy).
## A candidate pair qualifies when travelling through the network takes more
## than DETOUR_RATIO × the straight line; loops only make sense regionally,
## so candidates are capped at LOOP_MAX_SPAN straight-line distance. After
## routing, a loop whose geometry exceeds LOOP_ROUTED_GATE × straight-line is
## dropped (a mountain range or lake made the "shortcut" a lie).
const DETOUR_RATIO := 2.2
const LOOP_MAX_SPAN := 3200.0
const LOOP_ROUTED_GATE := 3.0
const LOOP_CAP_DIVISOR := 6   # max loops = anchors / this
## Give up on connecting two components after this many failed routes between
## them (an island never reaches the mainland; a hard mainland pair usually
## connects transitively through other tiles instead).
const MAX_PAIR_FAILS := 3

## Seam stitching: two adjacent road-carrying tiles whose networks nearly meet
## at the shared border but share NO edge get a short LOCAL link. Routed edges
## only merge while co-routing, so independently-routed roads can dead-end a
## few dozen units apart across a seam — reads as broken (owner report
## 2026-07-09). Only nets within STITCH_MAX_GAP stitch; a stitch whose routed
## path blows out (ridge/river detour) is dropped like a gated loop.
const STITCH_MAX_GAP := 300.0
const STITCH_SEAM_RADIUS := 330.0   # seam is 270u long; margin covers its corners
const STITCH_ROUTED_GATE := 3.0
const STITCH_BRIDGE_ALLOW := 560.0   # river stitches legitimately detour to the bridge gate
## Dead-end stitching: an edge endpoint is a STUB when no other road passes
## within STITCH_TOUCH of it (owner ruling: "it's only a stub if it's not
## meeting any other roads within 5u"). A stub with another edge inside
## DEADEND_MAX_GAP gets stitched to that edge's closest point — region-web
## jobs routinely leave seeded endpoints dangling 80-400u from the network.
const STITCH_TOUCH := 5.0
const DEADEND_MAX_GAP := 420.0

# ── Sparse-tile coverage guard (owner round 5) ──────────────────────────────
# A tile can carry the roads flag while the network barely clips a corner
# (tile_11_9, tile_15_9). Coverage = fraction of the hex interior lattice
# within SPARSE_NEAR of any road. Tiles under SPARSE_COVERAGE_MIN get an
# interior spur routed from the nearest road point into the deepest road-free
# pocket — realizer-routed, so height/water/forest rules still hold.
const SPARSE_NEAR := 90.0
const SPARSE_COVERAGE_MIN := 0.12
const SPARSE_SAMPLE_STEP := 60.0
const SPARSE_EDGE_INSET := 40.0
const SPARSE_ROUTED_GATE := 2.5
const SPARSE_MAX_SPURS := 2

# ── Merge-before-crossing via bridge anchors (owner rounds 6-7) ─────────────
# The realizer's gate whitelist lets a legal route cross the river anywhere
# within ~GATE_RADIUS of the gate segment, so edges sharing one crossing each
# cut their own line beside the deck — parallel strands, lens gaps, spike
# artifacts (owner screenshots, tiles 18_16/18_18). Fix: gates become shared
# NETWORK NODES with one canonical deck edge per crossing; crossing roads are
# SPLIT at the gates; wet spans with no reachable gate are CUT at the banks.
const FUNNEL_JOIN_MAX := 250.0   # max join distance from a wet span's ends to its gates

@onready var terrain: HexMap = %TerrainLayer

func _ready() -> void:
	await get_tree().process_frame
	var started := Time.get_ticks_msec()
	print("\n==== roads-v2 starting network bake ====")
	var nav := NavGrid.instance()
	if not nav.is_ready():
		push_error("bake_roads: navgrid missing — run tools/bake_hills.tscn first")
		get_tree().quit(1)
		return
	RoadCrossings.build(terrain)
	_seed_start_forests()
	_seed_start_buildings()

	var anchors := _anchor_tiles()
	print("bake_roads: %d anchor tiles (CSV 'roads' ∪ urban ∪ start-building tiles)" % anchors.size())
	if anchors.size() < 2:
		push_error("bake_roads: need at least 2 anchor tiles")
		get_tree().quit(1)
		return

	# Kruskal-style spanning FOREST with routing feedback: try pairs cheapest-first
	# (the spine accretes and the reuse discount grafts longer edges onto it), skip
	# already-connected pairs, blacklist a component-pair after MAX_PAIR_FAILS
	# routing failures. An island can never reach the mainland (bridges only cross
	# rivers), so its anchors settle into their own internally-connected tree.
	var n := anchors.size()
	var pairs: Array = []
	for i in n:
		for j in range(i + 1, n):
			pairs.append({"i": i, "j": j,
				"d": (anchors[i].center as Vector2).distance_to(anchors[j].center)})
	pairs.sort_custom(func(a, b): return float(a.d) < float(b.d))
	var parent := PackedInt32Array()
	parent.resize(n)
	for k in n:
		parent[k] = k
	var network := RoadNetwork.new()
	var realizer := RoadRealizer.new()
	var forest: Array = []
	var fail_pairs: Dictionary = {}
	var routed := 0
	var failed := 0
	var components := n
	for c in pairs:
		if components == 1:
			break
		var ri := _uf_find(parent, int(c.i))
		var rj := _uf_find(parent, int(c.j))
		if ri == rj:
			continue
		var key := "%d|%d" % [mini(ri, rj), maxi(ri, rj)]
		if int(fail_pairs.get(key, 0)) >= MAX_PAIR_FAILS:
			continue
		var a: Dictionary = anchors[int(c.i)]
		var b: Dictionary = anchors[int(c.j)]
		if _route_and_commit(nav, network, realizer, a, b, float(c.d), false):
			parent[ri] = rj
			components -= 1
			forest.append({"a": a, "b": b, "length": float(c.d)})
			routed += 1
		else:
			fail_pairs[key] = int(fail_pairs.get(key, 0)) + 1
			failed += 1
	print("bake_roads: forest done — %d edges, %d failed attempts, %d component(s) (islands stay separate)" % [
		routed, failed, components])

	# Loop edges (redundant routes) grafted onto the routed forest.
	var loops := _loop_edges(anchors, forest)
	loops.sort_custom(func(a, b): return float(a.length) < float(b.length))
	print("bake_roads: %d loop edges (detour ratio > %.1f)" % [loops.size(), DETOUR_RATIO])
	var gated := 0
	for edge in loops:
		if _route_and_commit(nav, network, realizer, edge.a, edge.b, float(edge.length), true):
			routed += 1
		else:
			gated += 1

	# Phase 4: each region holding an anchor tile grows its style web at bake
	# time (Stoneshore's orbital, sparse-city minihub webs, rural through-routes)
	# so cities have street fabric at turn 0 — also what the building visuals
	# will front onto.
	var styled: Array = []
	var style_regions := {}
	for a3 in anchors:
		var region_id := RoadRegions.region_of(str(a3.id))
		if region_id != RoadRegions.DEFAULT_REGION_ID:
			style_regions[region_id] = true
	var region_keys := style_regions.keys()
	region_keys.sort()
	for region_id2 in region_keys:
		var rep := RoadRegionJobs.realize_region(str(region_id2), terrain, nav, network, realizer, 0)
		styled.append(str(region_id2))
		print("bake_roads: region %-16s (%s)  jobs=%d committed=%d failed=%d overflow=%.0f%%%s" % [
			region_id2, RoadRegions.identity(str(region_id2)), int(rep.jobs), int(rep.committed),
			int(rep.failed), float(rep.overflow) * 100.0, " REWORKED" if bool(rep.reworked) else ""])

	# Dead-end stitch FIRST (dangling region-web endpoints reaching for the
	# nearest road), then the seam stitch for any remaining pair-level misses.
	var tips_stitched := _stitch_dead_ends(nav, network, realizer)
	print("bake_roads: %d dead-end stitches (dangling tips joined to the nearest road)" % tips_stitched)
	var stitched := _stitch_adjacent_seams(nav, network, realizer)
	print("bake_roads: %d seam stitches (adjacent nets nearly touching, no shared edge)" % stitched)
	# Sparse-coverage pass LAST: with the net fully stitched, any flagged tile the
	# roads barely enter gets at least one interior spur (new tips are deliberate
	# dead ends — they pick up terminus treatments at draw time).
	var spurs := _densify_sparse_tiles(nav, network, realizer)
	print("bake_roads: %d interior spurs added to road-sparse tiles" % spurs)
	# River discipline LAST, once every edge exists: crossings split onto shared
	# bridge-anchor nodes (one canonical deck each); gateless wet spans are cut
	# at the banks. No strand can cross water beside a deck by construction.
	realizer.warm_forest_cache()
	var funnel := _funnel_river_crossings(nav, network, realizer._forest_discs_cache)
	var approaches := _merge_gate_approaches(network)
	print("bake_roads: river discipline — %d crossings anchored (%d decks), %d roads cut at banks, %d grazes bank-hugged, %d approaches overlaid" % [
		int(funnel.bridged), int(funnel.decks), int(funnel.cuts), int(funnel.grazes), approaches])

	var anchor_ids: Array = []
	for a2 in anchors:
		anchor_ids.append(str(a2.id))
	# Every tile the baked network crosses gets "roads" infrastructure at match
	# start (geometry == gameplay; designer ruling 2026-07-09). Corridor tiles a
	# trunk merely passes through are included deliberately.
	var flagged := _flagged_tile_ids(network)
	var doc := {
		"version": 2,
		"hills_hash": HillBaked.source_hash(),
		"anchors": anchor_ids,
		"flagged_tiles": flagged,
		"style_regions": styled,
		"network": network.export_state(),
	}
	var file := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(doc))
	file.close()
	print("bake_roads: wrote %s — %d edges routed (%d loops gated/failed, %d forest attempts failed), %d flagged tiles (%.1fs)" % [
		OUT_PATH, routed, gated, failed, flagged.size(),
		float(Time.get_ticks_msec() - started) / 1000.0])
	# Failed attempts are expected (island ↔ mainland pairs are unroutable by
	# design); the bake only fails when it produced no network at all.
	get_tree().quit(0 if routed > 0 else 1)

## Mirrors world_map._place_northern_old_growth_forests with the SAME
## deterministic instance ids, so the realizer's forest discs match a fresh
## match exactly.
func _seed_start_forests() -> void:
	var seeded := 0
	for coord_key in terrain.tiles:
		var coord: Vector2i = coord_key
		var tile_data: Dictionary = terrain.tiles[coord]
		if coord.y + 1 > NORTH_MAX_ROW:
			continue
		if not OLD_GROWTH_TILE_TYPES.has(str(tile_data.get("type", "")).strip_edges().to_lower()):
			continue
		var tile_id := str(tile_data.get("id", ""))
		if tile_id == "":
			continue
		MatchState.add_building(OLD_GROWTH_BUILDING, "", tile_id, "tile_data",
			"forest_%s_%s" % [OLD_GROWTH_BUILDING, tile_id], false)
		seeded += 1
	print("bake_roads: seeded %d deterministic game-start forests" % seeded)

## Mirrors world_map._place_start_buildings (the pre-existing NPC pool): the
## new-growth forests in it (b_015) are road obstacles, and their footprint
## discs are seeded from the SAME deterministic instance ids a fresh match uses.
func _seed_start_buildings() -> void:
	var seeded := 0
	for entry in StartBuildings.entries():
		var tile_id := str(entry.tile)
		if terrain.id_to_coord(tile_id) == Vector2i(-1, -1):
			continue
		if MatchState.buildings.has(str(entry.instance_id)):
			continue
		MatchState.add_building(str(entry.building), str(entry.recipe), tile_id,
			str(entry.owner), str(entry.instance_id), false)
		seeded += 1
	print("bake_roads: seeded %d deterministic start buildings" % seeded)

## Roads-v3 anchor set: hand-flagged CSV tiles ∪ urban tiles ∪ tiles with at
## least one non-farm, non-forest start building. ~209 of 395 land tiles; the
## rest stay roadless until the player builds (runtime connect jobs).
func _anchor_tiles() -> Array:
	var want: Dictionary = {}   # tile_id -> true
	for entry in StartBuildings.entries():
		var b: Dictionary = Catalog.get_building(str(entry.building))
		var cat := str(b.get("category", "")).to_lower()
		if cat.contains("farm") or cat.contains("forest"):
			continue
		want[str(entry.tile)] = true
	var anchors: Array = []
	for coord in terrain.tiles:
		var tile_data: Dictionary = terrain.tiles[coord]
		var infra: Array = tile_data.get("infrastructure_present", [])
		var tile_id := str(tile_data.get("id", ""))
		var t := str(tile_data.get("type", "")).to_lower()
		if not (infra.has("roads") or t == "urban" or want.has(tile_id)):
			continue
		if t == "sea" or t == "deep_sea":
			continue
		anchors.append({
			"id": tile_id,
			"coord": coord,
			"center": terrain.map_to_local(terrain.map_coord_for_tile_coord(coord)),
		})
	anchors.sort_custom(func(a, b): return str(a.id) < str(b.id))
	return anchors

## Loop-edge selection over the routed forest: repeatedly add the non-tree pair
## with the WORST network-vs-straight detour ratio (graph distances use edge
## straight lengths — good enough to rank candidates) until no pair exceeds
## DETOUR_RATIO or the cap is hit. Cross-component pairs (mainland ↔ island)
## have infinite graph distance and are excluded — a loop never bridges the
## sea. Deterministic: ratio ties break by tile ids.
func _loop_edges(anchors: Array, forest: Array) -> Array:
	var n := anchors.size()
	var index_of: Dictionary = {}
	for i in n:
		index_of[str(anchors[i].id)] = i
	var adj: Array = []
	for i2 in n:
		adj.append([])
	var in_graph: Dictionary = {}
	for e in forest:
		var ia: int = index_of[str(e.a.id)]
		var ib: int = index_of[str(e.b.id)]
		adj[ia].append({"j": ib, "w": float(e.length)})
		adj[ib].append({"j": ia, "w": float(e.length)})
		in_graph["%d|%d" % [mini(ia, ib), maxi(ia, ib)]] = true
	# candidate pairs: regional span only, not already connected directly
	var candidates: Array = []
	for i3 in n:
		for j in range(i3 + 1, n):
			if in_graph.has("%d|%d" % [i3, j]):
				continue
			var d: float = (anchors[i3].center as Vector2).distance_to(anchors[j].center)
			if d <= LOOP_MAX_SPAN:
				candidates.append({"i": i3, "j": j, "d": d})
	# Initial ratios: one Dijkstra per unique source (not per pair). Pairs in
	# different components (unreachable) are dropped outright.
	var by_source: Dictionary = {}
	for c in candidates:
		if not by_source.has(int(c.i)):
			by_source[int(c.i)] = true
	for src in by_source:
		var dist := _dijkstra(adj, int(src))
		for c2 in candidates:
			if int(c2.i) == int(src):
				c2["ratio"] = dist[int(c2.j)] / maxf(float(c2.d), 1.0)
	candidates = candidates.filter(func(c) -> bool: return float(c.ratio) < 1.0e20)
	# Lazy greedy: adding a loop only SHRINKS graph distances, so a stale ratio
	# is a valid upper bound. Pop the best bound, re-validate with one Dijkstra;
	# accept only if it still beats the next candidate's (stale) bound.
	var sorter := func(a, b) -> bool:
		if absf(float(a.ratio) - float(b.ratio)) > 0.0001:
			return float(a.ratio) > float(b.ratio)
		return str(anchors[int(a.i)].id) + "|" + str(anchors[int(a.j)].id) \
			< str(anchors[int(b.i)].id) + "|" + str(anchors[int(b.j)].id)
	candidates.sort_custom(sorter)
	var loops: Array = []
	var cap := maxi(1, n / LOOP_CAP_DIVISOR)
	while loops.size() < cap and not candidates.is_empty():
		var head: Dictionary = candidates[0]
		var fresh: float = _dijkstra(adj, int(head.i))[int(head.j)] / maxf(float(head.d), 1.0)
		if fresh >= 1.0e20:
			candidates.remove_at(0)   # different components — never loop across the sea
			continue
		if fresh < DETOUR_RATIO:
			candidates.remove_at(0)   # bound was stale; no longer qualifies (others may still)
			continue
		var next_bound: float = float(candidates[1].ratio) if candidates.size() > 1 else 0.0
		if fresh + 0.0001 < next_bound:
			head["ratio"] = fresh   # stale — demote and retry
			candidates.sort_custom(sorter)
			continue
		var bi := int(head.i)
		var bj := int(head.j)
		loops.append({"a": anchors[bi], "b": anchors[bj], "length": float(head.d), "loop": true})
		adj[bi].append({"j": bj, "w": float(head.d)})
		adj[bj].append({"j": bi, "w": float(head.d)})
		candidates.remove_at(0)
	return loops

## Dijkstra over the anchor graph (straight-length weights) from one source.
## ~209 nodes — the O(V^2) scan is trivial at bake scale.
func _dijkstra(adj: Array, from: int) -> PackedFloat64Array:
	var n := adj.size()
	var dist := PackedFloat64Array()
	dist.resize(n)
	dist.fill(1.0e30)
	dist[from] = 0.0
	var done := PackedByteArray()
	done.resize(n)
	done.fill(0)
	for _k in n:
		var u := -1
		var ud := 1.0e30
		for v in n:
			if done[v] == 0 and dist[v] < ud:
				ud = dist[v]
				u = v
		if u < 0:
			break
		done[u] = 1
		for e in adj[u]:
			var w: float = ud + float(e.w)
			if w < dist[int(e.j)]:
				dist[int(e.j)] = w
	return dist

func _polyline_length(pts: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	return total

## Tile ids of every tile any baked edge crosses (sorted, deduped) — the
## match-start "roads" infrastructure set.
func _flagged_tile_ids(network: RoadNetwork) -> Array:
	var seen: Dictionary = {}
	for eid in network.edges:
		for t in network.edges[eid].tiles:
			var coord: Vector2i = t
			var td: Dictionary = terrain.tiles.get(coord, {})
			var tid := str(td.get("id", ""))
			if tid != "":
				seen[tid] = true
	var out: Array = seen.keys()
	out.sort()
	return out

## Route one anchor pair and commit it to the network. Loops additionally pass
## the routed-length acceptance gate (a "shortcut" the terrain turned into a
## mountain detour is dropped). Returns true when the edge was committed.
func _route_and_commit(nav, network: RoadNetwork, realizer: RoadRealizer, a: Dictionary, b: Dictionary, straight: float, is_loop: bool) -> bool:
	var identity: String = RoadRegions.identity_for_tile(str(a.id))
	var result := realizer.route(nav, network, a.center, b.center, {
		"identity": identity,
		"salt": RoadHash.pick("seed|%s|%s" % [a.id, b.id], 1 << 30),
	})
	if not result.ok:
		print("bake_roads: FAILED %s -> %s (%s)%s" % [a.id, b.id, result.reason, " LOOP" if is_loop else ""])
		return false
	if is_loop and _polyline_length(result.geometry) > LOOP_ROUTED_GATE * straight:
		print("bake_roads: loop %s -> %s GATED (routed %.0f > %.1f x %.0f straight)" % [
			a.id, b.id, _polyline_length(result.geometry), LOOP_ROUTED_GATE, straight])
		return false
	var na := network.ensure_node("anchor:" + str(a.id), RoadNetwork.KIND_JUNCTION, a.center, a.coord)
	var nb := network.ensure_node("anchor:" + str(b.id), RoadNetwork.KIND_JUNCTION, b.center, b.coord)
	var tier := RoadNetwork.TIER_TRUNK if straight > TRUNK_LENGTH else RoadNetwork.TIER_LOCAL
	realizer.commit(network, na.id, nb.id, tier, result, 0)
	print("bake_roads: %s -> %s  %s%s, %d pts, %d bridges (%s)" % [
		a.id, b.id, tier, " LOOP" if is_loop else "", result.geometry.size(),
		result.bridges.size(), identity])
	return true

## For every pair of adjacent road-carrying tiles that share no edge, find the
## closest approach between their networks (full geometry scan — near-misses
## cluster at hex corners as often as mid-seam); if the nets nearly touch,
## route a short LOCAL stitch between the two closest points. Runs to
## convergence: a stitch can itself join further pairs, and pairs skipped in
## one pass (route fail) retry against the richer network. Deterministic
## (tile iteration + id-keyed pairs). Each stitch endpoint lands ON an
## existing polyline point, so the join is visually seamless and the terminus
## glyph suppression treats it as a junction.
func _stitch_adjacent_seams(nav, network: RoadNetwork, realizer: RoadRealizer) -> int:
	var stitched := 0
	var gated := 0
	var failed := 0
	var settled: Dictionary = {}   # pairs whose join is already covered by existing roads
	for _pass in 3:
		var pass_stitched := 0
		var done_pairs: Dictionary = {}
		for coord_key in terrain.tiles:
			var coord: Vector2i = coord_key
			var a_edges := network.edges_on_tile(coord)
			if a_edges.is_empty():
				continue
			var a_id := str((terrain.tiles[coord] as Dictionary).get("id", ""))
			for ncoord in terrain.neighbor_coords(coord):
				if not terrain.tiles.has(ncoord):
					continue
				var b_edges := network.edges_on_tile(ncoord)
				if b_edges.is_empty():
					continue
				var b_id := str((terrain.tiles[ncoord] as Dictionary).get("id", ""))
				var pair_key := ("%s|%s" % [a_id, b_id]) if a_id < b_id else ("%s|%s" % [b_id, a_id])
				if done_pairs.has(pair_key) or settled.has(pair_key):
					continue
				done_pairs[pair_key] = true
				# Already joined locally: some edge crosses the shared seam.
				var shared := false
				for eid in a_edges:
					if b_edges.has(eid):
						shared = true
						break
				if shared:
					continue
				# LOCALITY: only geometry near the SHARED SEAM counts on BOTH sides.
				# edges_on_tile returns edges whose geometry spans other tiles too, so
				# an unrestricted scan finds a tiny "gap" between the same two edge
				# sets far away and stitches THERE, leaving the seam's visible break.
				var a_center: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
				var b_center: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(ncoord))
				var seam_mid := (a_center + b_center) * 0.5
				var a_pts := _points_near(network, a_edges, seam_mid, STITCH_SEAM_RADIUS)
				var b_pts := _points_near(network, b_edges, seam_mid, STITCH_SEAM_RADIUS)
				if a_pts.is_empty() or b_pts.is_empty():
					continue
				var best := 1.0e30
				var pa := Vector2.ZERO
				var pb := Vector2.ZERO
				for p1 in a_pts:
					for p2 in b_pts:
						var d := (p1 as Vector2).distance_squared_to(p2)
						if d < best:
							best = d
							pa = p1
							pb = p2
				var gap := sqrt(best)
				if gap > STITCH_MAX_GAP or gap < 6.0:
					continue   # too far to be a "near miss", or already touching
				var result := realizer.route(nav, network, pa, pb, {
					"identity": RoadRegions.identity_for_tile(a_id),
					"salt": RoadHash.pick("stitch|%s" % pair_key, 1 << 30),
				})
				if not result.ok:
					failed += 1
					continue
				var allow := STITCH_ROUTED_GATE * maxf(gap, 60.0)
				if not (result.bridges as Array).is_empty():
					# Two banks joining across a river IS the wanted stitch — the
					# route must reach the predetermined gate, so give it room
					# (a flat floor for tiny gaps, 3.5x for wider ones). Extreme
					# detours (5x+) stay unlinked — that is geography, not a break.
					allow = maxf(maxf(allow, STITCH_BRIDGE_ALLOW), 3.5 * gap)
				if _polyline_length(result.geometry) > allow:
					gated += 1
					continue   # a ridge detour, not a stitch
				# Draw only the NOVEL span (owner's 5u rule): a route that rides
				# existing roads re-draws them — the stacked-lines fan at busy
				# bridge gates. Fully-covered = already joined, count it settled.
				var trimmed := _trim_overlap(network, result.geometry)
				if trimmed.size() < 2:
					settled[pair_key] = true   # route rides existing roads — already joined
					continue
				result["geometry"] = trimmed
				# Register the stitch on BOTH pair tiles even when its geometry lies
				# in a third tile (triple-corner joins): the shared-edge check and
				# edges_on_tile consumers must see the pair as connected, or every
				# pass re-stitches the same corner forever.
				var rtiles: Array = result.tiles
				if not rtiles.has(coord):
					rtiles.append(coord)
				if not rtiles.has(ncoord):
					rtiles.append(ncoord)
				result["tiles"] = rtiles
				var na := network.ensure_node("stitch:%s:a" % pair_key, RoadNetwork.KIND_JUNCTION, trimmed[0], coord)
				var nb := network.ensure_node("stitch:%s:b" % pair_key, RoadNetwork.KIND_JUNCTION, trimmed[trimmed.size() - 1], ncoord)
				realizer.commit(network, na.id, nb.id, RoadNetwork.TIER_LOCAL, result, 0)
				pass_stitched += 1
		stitched += pass_stitched
		if pass_stitched == 0:
			break
	if gated + failed > 0:
		print("bake_roads: stitch skips — %d gated (detour), %d unroutable" % [gated, failed])
	return stitched

## Dead-end stitcher: every BUILT edge endpoint that touches no OTHER edge
## within STITCH_TOUCH is a stub; if another edge passes within DEADEND_MAX_GAP
## the stub is routed to that edge's closest point (same gates as seam
## stitches, geometry overlap-trimmed). Region-web jobs seed their endpoints
## from patterns, not attachments, so dangling 80-400u tips are systemic.
func _stitch_dead_ends(nav, network: RoadNetwork, realizer: RoadRealizer) -> int:
	var stitched := 0
	var handled: Dictionary = {}   # tip key -> true (stitched, settled or given up)
	realizer.warm_forest_cache()
	var forest_discs: Array = realizer._forest_discs_cache
	for _pass in 3:
		var pass_stitched := 0
		var edge_ids: Array = network.edges.keys()
		edge_ids.sort()
		for eid in edge_ids:
			var geo: PackedVector2Array = network.edges[eid].geometry
			if geo.size() < 2:
				continue
			for end_i in 2:
				var tip_key := "%s|%d" % [str(eid), end_i]
				if handled.has(tip_key):
					continue
				var tip: Vector2 = geo[0] if end_i == 0 else geo[geo.size() - 1]
				var near := _nearest_other_edge_point(network, str(eid), tip, DEADEND_MAX_GAP)
				if near.is_empty():
					handled[tip_key] = true
					continue   # nothing within reach — genuine terminus
				var gap := float(near.dist)
				if gap <= STITCH_TOUCH:
					handled[tip_key] = true
					continue   # already meets a road — not a stub
				# Straight connector when the line is clear: no A* (whose reuse
				# discount likes riding BACK along the stub's own corridor), the
				# ends land exactly on the tip and the target road.
				var result: Dictionary = {}
				var trimmed := PackedVector2Array()
				if _straight_clear(nav, tip, near.point, forest_discs):
					trimmed = PackedVector2Array([tip, tip.lerp(near.point, 0.5), near.point])
					result = {"geometry": trimmed, "tiles": _route_tiles(trimmed), "bridges": []}
				else:
					result = realizer.route(nav, network, tip, near.point, {
						"identity": RoadRegions.identity_for_tile(_tile_id_at(tip)),
						"salt": RoadHash.pick("tipstitch|%s|%d" % [str(eid), end_i], 1 << 30),
					})
					if not result.ok:
						continue
					var allow := STITCH_ROUTED_GATE * maxf(gap, 60.0)
					if not (result.bridges as Array).is_empty():
						allow = maxf(maxf(allow, STITCH_BRIDGE_ALLOW), 3.5 * gap)
					if _polyline_length(result.geometry) > allow:
						continue   # geography, not a break
					trimmed = _trim_overlap(network, result.geometry, str(eid))
					if trimmed.size() < 2:
						handled[tip_key] = true
						continue   # entire route rides existing roads — already joined
					result["geometry"] = trimmed
				var rtiles: Array = result.tiles
				var tip_tile: Vector2i = terrain.tile_coord_for_map_coord(terrain.local_to_map(tip))
				var tgt_tile: Vector2i = terrain.tile_coord_for_map_coord(terrain.local_to_map(near.point))
				if not rtiles.has(tip_tile):
					rtiles.append(tip_tile)
				if not rtiles.has(tgt_tile):
					rtiles.append(tgt_tile)
				result["tiles"] = rtiles
				var na := network.ensure_node("tip:%s:%d:a" % [str(eid), end_i], RoadNetwork.KIND_JUNCTION, trimmed[0], tip_tile)
				var nb := network.ensure_node("tip:%s:%d:b" % [str(eid), end_i], RoadNetwork.KIND_JUNCTION, trimmed[trimmed.size() - 1], tgt_tile)
				realizer.commit(network, na.id, nb.id, RoadNetwork.TIER_LOCAL, result, 0)
				handled[tip_key] = true
				pass_stitched += 1
		stitched += pass_stitched
		if pass_stitched == 0:
			break
	return stitched

## Closest point on any edge OTHER than `own_id` within `max_dist` of `p`:
## exact point-to-segment with a per-edge bbox prefilter. {point, dist} or {}.
## Interior spurs for road-carrying tiles the network barely enters. Coverage is
## sampled on the hex interior lattice (half-extents 270×240, corner inequality
## 240|x|+135|y| ≤ 64800 — same hex model as the terminus arm inset); a tile
## under SPARSE_COVERAGE_MIN routes a LOCAL spur from the nearest road point to
## the sample deepest inside the road-free pocket. Up to SPARSE_MAX_SPURS per
## tile, re-measuring after each. Returns the number of spurs committed.
func _densify_sparse_tiles(nav, network: RoadNetwork, realizer: RoadRealizer) -> int:
	var added := 0
	var tile_keys: Array = []
	for coord_key in terrain.tiles:
		tile_keys.append(coord_key)
	tile_keys.sort_custom(func(a, b) -> bool:
		var va: Vector2i = a
		var vb: Vector2i = b
		return va.x < vb.x if va.y == vb.y else va.y < vb.y)
	for coord_key2 in tile_keys:
		var coord: Vector2i = coord_key2
		var edges := network.edges_on_tile(coord)
		if edges.is_empty():
			continue
		var td: Dictionary = terrain.tiles[coord]
		if str(td.get("type", "")) == "water":
			continue   # a bridge crossing water is not a tile that wants streets
		var tid := str(td.get("id", ""))
		var center: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
		var segs: Array = []   # [[p0, p1], ...] of every edge touching the tile
		for eid in edges:
			var geo: PackedVector2Array = network.edges[eid].geometry
			for i in range(geo.size() - 1):
				segs.append([geo[i], geo[i + 1]])
		var before := -1.0
		var tile_added := 0
		for attempt in SPARSE_MAX_SPURS:
			var cov := _tile_road_coverage(center, segs)
			var frac := float(cov.covered) / maxf(1.0, float(cov.total))
			if before < 0.0:
				before = frac
			if frac >= SPARSE_COVERAGE_MIN:
				break
			var samples: Array = cov.samples
			samples.sort_custom(func(s1, s2) -> bool: return float(s1.d) > float(s2.d))
			var committed := false
			for ti in mini(3, samples.size()):
				var target: Vector2 = samples[ti].p
				var from := _closest_point_on_segs(target, segs)
				var straight := from.distance_to(target)
				if straight < 40.0:
					break
				var result := realizer.route(nav, network, from, target, {
					"identity": RoadRegions.identity_for_tile(tid),
					"salt": RoadHash.pick("sparse|%s|%d|%d" % [tid, attempt, ti], 1 << 30),
				})
				if not result.ok:
					continue
				if _polyline_length(result.geometry) > SPARSE_ROUTED_GATE * maxf(straight, 60.0):
					continue   # terrain says no (ridge/water detour) — try the next pocket
				var trimmed := _trim_overlap(network, result.geometry)
				if trimmed.size() < 2:
					continue
				result["geometry"] = trimmed
				var rtiles: Array = result.tiles
				if not rtiles.has(coord):
					rtiles.append(coord)
				result["tiles"] = rtiles
				var na := network.ensure_node("sparse:%s:%d:a" % [tid, attempt], RoadNetwork.KIND_JUNCTION, trimmed[0], coord)
				var nb := network.ensure_node("sparse:%s:%d:b" % [tid, attempt], RoadNetwork.KIND_JUNCTION, trimmed[trimmed.size() - 1], coord)
				realizer.commit(network, na.id, nb.id, RoadNetwork.TIER_LOCAL, result, 0)
				for i2 in range(trimmed.size() - 1):
					segs.append([trimmed[i2], trimmed[i2 + 1]])
				added += 1
				tile_added += 1
				committed = true
				break
			if not committed:
				break
		if tile_added > 0:
			var after := _tile_road_coverage(center, segs)
			print("bake_roads: sparse tile %s coverage %.0f%% -> %.0f%% (+%d spur%s)" % [
				tid, before * 100.0, float(after.covered) / maxf(1.0, float(after.total)) * 100.0,
				tile_added, "" if tile_added == 1 else "s"])
	return added

## River discipline via BRIDGE ANCHOR NODES (owner ruling, round 7): every
## crossing used by a road gets two shared gate NODES plus ONE canonical deck
## edge between them; roads that cross are SPLIT at the gates, so no polyline
## ever threads through a gate (that threading is what drew miter-spike
## arrowheads and stacked strands). A genuine wet span with no reachable gate
## is CUT at the banks — the owner's "no road within the river outside a
## bridge" rule. Gameplay is untouched: routing runs on per-tile infra flags,
## which the first split piece inherits as a superset.
func _funnel_river_crossings(nav, network: RoadNetwork, forest_discs: Array) -> Dictionary:
	var bridged := 0
	var cuts := 0
	var grazes := 0
	var bridge_edges: Dictionary = {}    # "na|nb" -> canonical edge id
	var canonical_ids: Dictionary = {}   # edge ids the pass created (never re-cut)
	var eids: Array = network.edges.keys()
	eids.sort()
	for eid in eids:
		if canonical_ids.has(str(eid)):
			continue
		var e: Dictionary = network.edges[eid]
		if str(e.state) != RoadNetwork.STATE_BUILT:
			continue
		var geo: PackedVector2Array = e.geometry
		if geo.size() < 2:
			continue
		# Slice the polyline into dry parts separated by GENUINE wet runs; bank
		# grazes (wet cells without a bank-to-bank chord) stay inline.
		var parts: Array = []     # Array[PackedVector2Array]
		var joints: Array = []    # one per boundary: {crossing, g_in, g_out} or {} = cut
		var current := PackedVector2Array()
		var i := 0
		var any := false
		while i < geo.size():
			if not _in_river(nav, geo[i]):
				current.append(geo[i])
				i += 1
				continue
			var j := i
			var mid := Vector2.ZERO
			while j < geo.size() and _in_river(nav, geo[j]):
				mid += geo[j]
				j += 1
			mid /= float(maxi(j - i, 1))
			var entry: Vector2 = current[current.size() - 1] if current.size() > 0 else geo[i]
			var exit_p: Vector2 = geo[j] if j < geo.size() else geo[geo.size() - 1]
			var at_end := (j >= geo.size()) or (current.size() == 0 and i == 0)
			if _max_wet_chord(nav, entry, exit_p) < 20.0:
				grazes += 1
				if at_end:
					# Endpoint graze: the polyline's end vertex clips a river
					# cell. Shared junction nodes sit exactly there — leave the
					# points untouched or the edge detaches from its node.
					for k0 in range(i, j):
						current.append(geo[k0])
				else:
					# Mid-run bank graze: keep the run but push its points onto
					# land so no road ever DRAWS in the water (owner round 8:
					# orange trunks riding the channel).
					var hug := _push_to_land(nav, geo.slice(i, j))
					if hug.size() > 0:
						for hp in hug:
							current.append(hp)
					else:
						for k in range(i, j):
							current.append(geo[k])
				i = j
				continue
			any = true
			var chosen: Dictionary = {}
			for cand in _crossings_by_distance(mid, 800.0, 3):
				var ga: Vector2 = cand.gate_a
				var gb: Vector2 = cand.gate_b
				# Join each end to the gate on ITS OWN bank: nearest-gate can
				# pick across the channel, and the gate-zone waiver below then
				# lets the join cross the water beside the deck (owner round 8
				# lens at 18_16). Raw wet exposure, no waiver, decides.
				var wet_ab := _max_wet_chord(nav, entry, ga) + _max_wet_chord(nav, gb, exit_p)
				var wet_ba := _max_wet_chord(nav, entry, gb) + _max_wet_chord(nav, ga, exit_p)
				var g_in := ga
				if wet_ba < wet_ab or (wet_ba == wet_ab and entry.distance_squared_to(gb) < entry.distance_squared_to(ga)):
					g_in = gb
				var g_out := gb if g_in == ga else ga
				if entry.distance_to(g_in) > FUNNEL_JOIN_MAX or exit_p.distance_to(g_out) > FUNNEL_JOIN_MAX:
					continue
				# The short joins onto the anchors must be dry outside the gate
				# zone (wet AT the bridge is the crossing itself)…
				if _wet_chord_off_gate(nav, PackedVector2Array([entry, g_in]), ga, gb) >= 20.0:
					continue
				if _wet_chord_off_gate(nav, PackedVector2Array([g_out, exit_p]), ga, gb) >= 20.0:
					continue
				# …and must not carve through a start-forest canopy (rim contact
				# near the bridge itself is the legitimate two-constraints case).
				if not _join_clear_of_forests(entry, g_in, cand.point, forest_discs):
					continue
				if not _join_clear_of_forests(g_out, exit_p, cand.point, forest_discs):
					continue
				chosen = {"crossing": cand, "g_in": g_in, "g_out": g_out}
				break
			parts.append(current)
			joints.append(chosen)
			current = PackedVector2Array()
			i = j
		parts.append(current)
		if not any:
			continue
		# Rebuild: split pieces anchored on gate nodes (bridging) or bank nodes (cuts).
		_remove_edge(network, str(eid))
		var start_node := str(e.a)
		var prepend := Vector2.INF     # gate to prepend to the next piece
		var first_piece := true
		for pi in parts.size():
			var pts: PackedVector2Array = parts[pi]
			if prepend != Vector2.INF:
				# Mirror of the tail un-bend: drop leading points that double
				# back toward the gate before prepending it.
				var rev := PackedVector2Array()
				for ri in range(pts.size() - 1, -1, -1):
					rev.append(pts[ri])
				var pj: Dictionary = joints[pi - 1]
				rev = _unbend_to_gate(nav, rev, prepend, (pj.crossing as Dictionary).gate_a, (pj.crossing as Dictionary).gate_b)
				var with_gate := PackedVector2Array([prepend])
				for ri2 in range(rev.size() - 1, -1, -1):
					with_gate.append(rev[ri2])
				pts = with_gate
				prepend = Vector2.INF
			var is_last := pi == parts.size() - 1
			var joint: Dictionary = {} if is_last else (joints[pi] as Dictionary)
			var end_node := str(e.b)
			if not is_last:
				if not joint.is_empty():
					var cr: Dictionary = joint.crossing
					end_node = _gate_node(network, cr, joint.g_in)
					pts = _unbend_to_gate(nav, pts, joint.g_in, cr.gate_a, cr.gate_b)
					pts.append(joint.g_in)
					_ensure_bridge_edge(network, cr, str(e.tier), bridge_edges, canonical_ids)
					prepend = joint.g_out
					bridged += 1
				else:
					cuts += 1
					if pts.size() > 0:
						end_node = network.ensure_node("cut:%s:%d" % [str(eid), pi],
							RoadNetwork.KIND_JUNCTION, pts[pts.size() - 1], _coord_at(pts[pts.size() - 1])).id
			if pts.size() >= 2:
				var ptiles: Array = _route_tiles(pts)
				if first_piece:
					for told in e.tiles:
						if not ptiles.has(told):
							ptiles.append(told)   # flags stay a superset — gameplay identical
					first_piece = false
				var sn := start_node
				if pi > 0 and (joints[pi - 1] as Dictionary).is_empty():
					sn = network.ensure_node("cut:%s:%d:b" % [str(eid), pi],
						RoadNetwork.KIND_JUNCTION, pts[0], _coord_at(pts[0])).id
				elif pi > 0:
					sn = _gate_node(network, (joints[pi - 1] as Dictionary).crossing, (joints[pi - 1] as Dictionary).g_out)
				network.add_edge(sn, end_node, str(e.tier), pts, ptiles, [], 0)
			start_node = end_node
	var decks := bridge_edges.size()
	return {"bridged": bridged, "cuts": cuts, "decks": decks, "grazes": grazes}

## Un-bend the V-notch a gate join creates when the approach overshoots the
## gate: drop end points while a direct line to the gate is meaningfully
## shorter and stays dry outside the gate zone (max 8 points).
func _unbend_to_gate(nav, pts: PackedVector2Array, gate: Vector2, ga: Vector2, gb: Vector2) -> PackedVector2Array:
	var out := pts.duplicate()
	var dropped := 0
	while out.size() >= 2 and dropped < 8:
		var last := out[out.size() - 1]
		var prev := out[out.size() - 2]
		if (prev.distance_to(last) + last.distance_to(gate)) - prev.distance_to(gate) < 6.0:
			break
		if _wet_chord_off_gate(nav, PackedVector2Array([prev, gate]), ga, gb) >= 20.0:
			break
		out.remove_at(out.size() - 1)
		dropped += 1
	return out

## Push every point of a wet run onto its nearest land cell (outward ring
## search) — bank grazes then hug the bank instead of riding the channel.
func _push_to_land(nav, pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		var q := _nearest_land_point(nav, p, 6)
		if q == Vector2.INF:
			return PackedVector2Array()
		if out.is_empty() or out[out.size() - 1].distance_to(q) > 2.0:
			out.append(q)
	return out

func _nearest_land_point(nav, p: Vector2, max_ring: int) -> Vector2:
	var c: Vector2i = nav.cell_of(p)
	for r in range(0, max_ring + 1):
		var best := Vector2.INF
		var best_d := 1.0e30
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var x := c.x + dx
				var y := c.y + dy
				if x < 0 or y < 0 or x >= nav.gw or y >= nav.gh:
					continue
				if nav.water(x, y) != NavGrid.WATER_LAND:
					continue
				if nav.level(x, y) >= RoadRealizer.BAN_LEVEL:
					continue
				var w: Vector2 = nav.world_of(x, y)
				var d := w.distance_squared_to(p)
				if d < best_d:
					best_d = d
					best = w
		if best != Vector2.INF:
			return best
	return Vector2.INF

## Post-funnel visual consolidation at the bridges (owner round 8):
## 1. degenerate decks (both ends the same gate node) are dropped;
## 2. loose endpoints (stitch/tip/jn connectors) whose drawn end lands within
##    SNAP_R of a gate snap exactly onto it — near-miss endpoints beside a deck
##    read as darts and lens gaps;
## 3. edges leaving the same POSITION (the gates, and the multi-id junctions
##    routing piles up beside them) ADOPT the longest edge\'s geometry while
##    they track it within MERGE_R, so overlapping approaches render as ONE
##    strand. Grouping is by quantized position, not node id — routing leaves
##    many distinct node ids on the same point.
func _merge_gate_approaches(network: RoadNetwork) -> int:
	const MERGE_R := 16.0
	const MERGE_REACH := 420.0
	const SNAP_R := 14.0
	var node_ids: Array = network.nodes.keys()
	node_ids.sort()
	var gate_pos: Array = []
	for nid in node_ids:
		if str(nid).begins_with("bgate:"):
			gate_pos.append((network.nodes[nid] as Dictionary).pos)
	var eids: Array = network.edges.keys()
	eids.sort()
	for eid0 in eids:
		var e0: Dictionary = network.edges[eid0]
		if str(e0.a) == str(e0.b) and str(e0.a).begins_with("bgate:"):
			_remove_edge(network, str(eid0))
	eids = network.edges.keys()
	eids.sort()
	for eid1 in eids:
		var e1: Dictionary = network.edges[eid1]
		if str(e1.a).begins_with("bgate:") and str(e1.b).begins_with("bgate:"):
			continue
		var geo1: PackedVector2Array = e1.geometry
		if geo1.size() < 2:
			continue
		var snapped := false
		for endi in [0, geo1.size() - 1]:
			var p1: Vector2 = geo1[endi]
			for gp in gate_pos:
				var d1: float = p1.distance_to(gp)
				if d1 > 0.01 and d1 <= SNAP_R:
					geo1[endi] = gp
					snapped = true
					break
		if snapped:
			e1["geometry"] = geo1
	# Adoption groups: every non-deck edge END near a crossing, keyed by its
	# quantized position.
	var merged := 0
	var groups: Dictionary = {}
	for eid in eids:
		var e: Dictionary = network.edges[eid]
		if str(e.a).begins_with("bgate:") and str(e.b).begins_with("bgate:"):
			continue
		var geo: PackedVector2Array = e.geometry
		if geo.size() < 2:
			continue
		for side in ["a", "b"]:
			var p: Vector2 = geo[0] if side == "a" else geo[geo.size() - 1]
			if not _pos_near_crossing(p, 160.0):
				continue
			var key := "%d|%d" % [int(roundf(p.x / 2.0)), int(roundf(p.y / 2.0))]
			var lst: Array = groups.get(key, [])
			lst.append({"eid": str(eid), "side": side})
			groups[key] = lst
	var keys: Array = groups.keys()
	keys.sort()
	for k in keys:
		var lst2: Array = groups[k]
		if lst2.size() < 2:
			continue
		# Primary = the LONGEST edge here (most likely the real trunk); the
		# others adopt its points up to their divergence arc. The walk is by
		# ARC-LENGTH SAMPLES, not vertices — long straight strands have no
		# interior vertices, and vertex tests leave leave-and-return lenses.
		lst2.sort_custom(func(x, y) -> bool:
			var lx := _polyline_arc((network.edges[x.eid] as Dictionary).geometry)
			var ly := _polyline_arc((network.edges[y.eid] as Dictionary).geometry)
			if absf(lx - ly) > 0.01:
				return lx > ly
			return str(x.eid) < str(y.eid))
		for li in range(1, lst2.size()):
			var rec: Dictionary = lst2[li]
			var e2: Dictionary = network.edges[rec.eid]
			var from_end: bool = str(rec.side) == "b"
			var seq := _oriented_from_gate(e2.geometry, from_end)
			var total := _polyline_arc(seq)
			# Try every LONGER member (not just the group primary): a short
			# connector can shadow the second-longest strand while sitting
			# nowhere near the longest one.
			for ci in range(li):
				var cand: Dictionary = lst2[ci]
				var prim_geo := _oriented_from_gate(network.edges[cand.eid].geometry, str(cand.side) == "b")
				const SAMPLE_STEP := 12.0
				var limit := minf(minf(total - 20.0, MERGE_REACH), _polyline_arc(prim_geo) - 8.0)
				var s := SAMPLE_STEP
				var shared := 0.0
				var t_prim := 0.0
				while s <= limit:
					var p2 := _point_at_arc(seq, s)
					var pr := _project_onto_polyline(prim_geo, p2)
					if pr.x > MERGE_R:
						break
					shared = s
					t_prim = pr.y
					s += SAMPLE_STEP
				if shared < minf(40.0, total * 0.5):
					continue
				var rebuilt := _polyline_prefix(prim_geo, t_prim)
				var arc2 := 0.0
				for k2 in range(seq.size()):
					if k2 > 0:
						arc2 += seq[k2 - 1].distance_to(seq[k2])
					if arc2 > shared:
						rebuilt.append(seq[k2])
				e2["geometry"] = _oriented_from_gate(rebuilt, from_end)
				merged += 1
				break
	return merged

func _pos_near_crossing(p: Vector2, radius: float) -> bool:
	for tid in RoadCrossings._by_tile:
		for cr in RoadCrossings._by_tile[tid]:
			if p.distance_to((cr as Dictionary).point) <= radius:
				return true
	return false

func _polyline_arc(poly: PackedVector2Array) -> float:
	var arc := 0.0
	for i in range(poly.size() - 1):
		arc += poly[i].distance_to(poly[i + 1])
	return arc

func _point_at_arc(poly: PackedVector2Array, t: float) -> Vector2:
	var arc := 0.0
	for i in range(poly.size() - 1):
		var seg := poly[i].distance_to(poly[i + 1])
		if seg <= 0.0:
			continue
		if arc + seg >= t:
			return poly[i].lerp(poly[i + 1], clampf((t - arc) / seg, 0.0, 1.0))
		arc += seg
	return poly[poly.size() - 1] if poly.size() > 0 else Vector2.INF

func _oriented_from_gate(geo: PackedVector2Array, from_end: bool) -> PackedVector2Array:
	if not from_end:
		return geo.duplicate()
	var out := PackedVector2Array()
	for i in range(geo.size() - 1, -1, -1):
		out.append(geo[i])
	return out

## Closest approach of p to the polyline: returns Vector2(distance, arc-length
## of the projection along the polyline from its first point).
func _project_onto_polyline(poly: PackedVector2Array, p: Vector2) -> Vector2:
	var best_d := 1.0e30
	var best_arc := 0.0
	var arc := 0.0
	for si in range(poly.size() - 1):
		var q := Geometry2D.get_closest_point_to_segment(p, poly[si], poly[si + 1])
		var d := p.distance_squared_to(q)
		if d < best_d:
			best_d = d
			best_arc = arc + poly[si].distance_to(q)
		arc += poly[si].distance_to(poly[si + 1])
	return Vector2(sqrt(best_d), best_arc)

## The polyline's points from its start up to arc-length t (end point included
## at exactly t).
func _polyline_prefix(poly: PackedVector2Array, t: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if poly.is_empty():
		return out
	out.append(poly[0])
	var arc := 0.0
	for si in range(poly.size() - 1):
		var seg := poly[si].distance_to(poly[si + 1])
		if seg <= 0.0:
			continue
		if arc + seg >= t:
			var cut := poly[si].lerp(poly[si + 1], clampf((t - arc) / seg, 0.0, 1.0))
			if out[out.size() - 1].distance_to(cut) > 0.5:
				out.append(cut)
			return out
		arc += seg
		out.append(poly[si + 1])
	return out

## A gate join may shave a canopy rim right at the bridge (two hard constraints
## meeting) but must not carve INTO a forest disc away from the crossing.
func _join_clear_of_forests(a: Vector2, b: Vector2, crossing_point: Vector2, forest_discs: Array) -> bool:
	var exempt := RoadCrossings.GATE_OFFSET + RoadRealizer.BRIDGE_BANK_STUB + 24.0
	var steps := maxi(2, int(ceil(a.distance_to(b) / 8.0)))
	for s in steps + 1:
		var p := a.lerp(b, float(s) / float(steps))
		if p.distance_to(crossing_point) <= exempt:
			continue
		for disc in forest_discs:
			if p.distance_to(disc.center) < float(disc.radius) - 6.0:
				return false
	return true

## Shared gate anchor node for one side of a crossing.
func _gate_node(network: RoadNetwork, crossing: Dictionary, gate: Vector2) -> String:
	var side := "a" if gate.distance_squared_to(crossing.gate_a) < gate.distance_squared_to(crossing.gate_b) else "b"
	var nid := "bgate:%s:%d:%s" % [str(crossing.tile_id), int(crossing.arm), side]
	return str(network.ensure_node(nid, RoadNetwork.KIND_JUNCTION, gate, _coord_at(gate)).id)

## ONE canonical deck edge per crossing — it alone carries the bridge record.
func _ensure_bridge_edge(network: RoadNetwork, crossing: Dictionary, tier: String, bridge_edges: Dictionary, canonical_ids: Dictionary) -> void:
	var na := _gate_node(network, crossing, crossing.gate_a)
	var nb := _gate_node(network, crossing, crossing.gate_b)
	var key := "%s|%s" % [na, nb]
	if bridge_edges.has(key):
		return
	var bgeo := PackedVector2Array([crossing.gate_a, crossing.gate_b])
	var bedge := network.add_edge(na, nb, tier, bgeo, _route_tiles(bgeo), [{
		"point": crossing.point, "tangent": crossing.bridge_tangent,
		"gate_a": crossing.gate_a, "gate_b": crossing.gate_b,
	}], 0)
	bridge_edges[key] = str(bedge.id)
	canonical_ids[str(bedge.id)] = true

## Remove an edge from the live network (bake-side surgery; occupancy stamps
## are inert once routing is done, so they can stay).
func _remove_edge(network: RoadNetwork, eid: String) -> void:
	var e: Dictionary = network.edges.get(eid, {})
	if e.is_empty():
		return
	for t in e.tiles:
		var lst: Array = network._edges_by_tile.get(t, [])
		lst.erase(eid)
	network.edges.erase(eid)

func _coord_at(p: Vector2) -> Vector2i:
	return terrain.tile_coord_for_map_coord(terrain.local_to_map(p))

## Longest wet chord over a polyline, IGNORING water within 36u of the bridge
## segment ga→gb (the gate zone is legal water for a road).
func _wet_chord_off_gate(nav, pts: PackedVector2Array, ga: Vector2, gb: Vector2) -> float:
	var worst := 0.0
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var steps := maxi(2, int(ceil(a.distance_to(b) / 6.0)))
		var run := 0
		var best := 0
		for s in steps + 1:
			var p := a.lerp(b, float(s) / float(steps))
			var wet := _in_river(nav, p) \
				and p.distance_to(Geometry2D.get_closest_point_to_segment(p, ga, gb)) > 36.0
			if wet:
				run += 1
				best = maxi(best, run)
			else:
				run = 0
		worst = maxf(worst, float(best) * a.distance_to(b) / float(steps))
	return worst

## Longest contiguous river chord along the straight a→b line (6u sampling) —
## distinguishes a genuine bank-to-bank crossing from a corner graze.
func _max_wet_chord(nav, a: Vector2, b: Vector2) -> float:
	var steps := maxi(2, int(ceil(a.distance_to(b) / 6.0)))
	var run := 0
	var best := 0
	for s in steps + 1:
		if _in_river(nav, a.lerp(b, float(s) / float(steps))):
			run += 1
			best = maxi(best, run)
		else:
			run = 0
	return float(best) * a.distance_to(b) / float(steps)

func _in_river(nav, p: Vector2) -> bool:
	var c: Vector2i = nav.cell_of(p)
	if c.x < 0 or c.y < 0 or c.x >= nav.gw or c.y >= nav.gh:
		return false
	return nav.water(c.x, c.y) == NavGrid.WATER_RIVER

func _crossings_by_distance(p: Vector2, radius: float, count: int) -> Array:
	var all: Array = []
	for crossing in RoadCrossings.in_rect(Rect2(p - Vector2(radius, radius), Vector2(radius, radius) * 2.0)):
		all.append(crossing)
	all.sort_custom(func(a, b) -> bool:
		return (a.point as Vector2).distance_squared_to(p) < (b.point as Vector2).distance_squared_to(p))
	return all.slice(0, count)

## Fraction of the tile's interior lattice within SPARSE_NEAR of a road segment.
func _tile_road_coverage(center: Vector2, segs: Array) -> Dictionary:
	var corner_max := 64800.0 - SPARSE_EDGE_INSET * Vector2(240.0, 135.0).length()
	var samples: Array = []
	var covered := 0
	var total := 0
	var y := -240.0 + SPARSE_EDGE_INSET
	while y <= 240.0 - SPARSE_EDGE_INSET:
		var x := -270.0 + SPARSE_EDGE_INSET
		while x <= 270.0 - SPARSE_EDGE_INSET:
			if 240.0 * absf(x) + 135.0 * absf(y) <= corner_max:
				var p := center + Vector2(x, y)
				var d := _dist_to_segs(p, segs)
				total += 1
				if d <= SPARSE_NEAR:
					covered += 1
				samples.append({"p": p, "d": d})
			x += SPARSE_SAMPLE_STEP
		y += SPARSE_SAMPLE_STEP
	return {"total": total, "covered": covered, "samples": samples}

func _dist_to_segs(p: Vector2, segs: Array) -> float:
	var best := 1.0e30
	for s in segs:
		var d := p.distance_squared_to(Geometry2D.get_closest_point_to_segment(p, s[0], s[1]))
		if d < best:
			best = d
	return sqrt(best)

func _closest_point_on_segs(p: Vector2, segs: Array) -> Vector2:
	var best := 1.0e30
	var out := p
	for s in segs:
		var q := Geometry2D.get_closest_point_to_segment(p, s[0], s[1])
		var d := p.distance_squared_to(q)
		if d < best:
			best = d
			out = q
	return out

func _nearest_other_edge_point(network: RoadNetwork, own_id: String, p: Vector2, max_dist: float) -> Dictionary:
	var best := max_dist
	var best_pt := Vector2.INF
	for eid in network.edges:
		if str(eid) == own_id:
			continue
		var geo: PackedVector2Array = network.edges[eid].geometry
		if geo.size() < 2:
			continue
		# cheap reject: bbox of the edge grown by the current best
		var bb := Rect2(geo[0], Vector2.ZERO)
		for g in geo:
			bb = bb.expand(g)
		if not bb.grow(best).has_point(p):
			continue
		for i in range(geo.size() - 1):
			var cp := Geometry2D.get_closest_point_to_segment(p, geo[i], geo[i + 1])
			var d := p.distance_to(cp)
			if d < best:
				best = d
				best_pt = cp
	if best_pt == Vector2.INF:
		return {}
	return {"point": best_pt, "dist": best}

## Owner ruling ("only a stub if not meeting any other roads within 5u"),
## applied to new stitch geometry: split it into runs whose points stay clear
## of EXISTING roads by more than STITCH_TOUCH, keep the LONGEST novel run and
## dilate it one point into the covered zone on each side (so its ends land ON
## the roads it joins). Returns empty when the whole route rides existing
## roads — stacked duplicate spans (the bridge-gate "fan") come from exactly
## that, many edges re-drawing the same corridor.
func _trim_overlap(network: RoadNetwork, geo: PackedVector2Array, exclude_id: String = "") -> PackedVector2Array:
	var n := geo.size()
	if n < 2:
		return geo
	var covered := PackedByteArray()
	covered.resize(n)
	# candidate existing segments near the route
	var bb := Rect2(geo[0], Vector2.ZERO)
	for g in geo:
		bb = bb.expand(g)
	bb = bb.grow(STITCH_TOUCH + 2.0)
	var segs: Array = []
	for eid in network.edges:
		if str(eid) == exclude_id:
			continue   # a stub stitch must not treat its OWN edge as cover
		var og: PackedVector2Array = network.edges[eid].geometry
		for i in range(og.size() - 1):
			if bb.has_point(og[i]) or bb.has_point(og[i + 1]):
				segs.append([og[i], og[i + 1]])
	for i2 in n:
		var p := geo[i2]
		for s in segs:
			if p.distance_to(Geometry2D.get_closest_point_to_segment(p, s[0], s[1])) <= STITCH_TOUCH:
				covered[i2] = 1
				break
	# FIRST uncovered run — the stitch must stay attached to the break it
	# repairs (a dangling tip is index 0 and always uncovered; a seam stitch
	# starts ON a road, so its first uncovered run is the span leaving it).
	# Keeping the LONGEST run instead can grab a mid-route segment nowhere
	# near the break, detaching the stitch and leaving junk fragments.
	var run_s := -1
	var run_e := -1
	for i3 in n + 1:
		var is_free := i3 < n and covered[i3] == 0
		if is_free and run_s < 0:
			run_s = i3
		elif not is_free and run_s >= 0:
			run_e = i3
			break
	if run_s < 0:
		return PackedVector2Array()   # fully covered — nothing novel to draw
	if run_e < 0:
		run_e = n
	var lo := maxi(0, run_s - 1)             # dilate one point each side so the
	var hi := mini(n - 1, run_e)             # ends land ON the roads being joined
	var out := geo.slice(lo, hi + 1)
	if _polyline_length(out) < 12.0:
		return PackedVector2Array()   # sub-carriageway sliver — worthless to draw
	return out

## True when the straight segment stays on land below the road ban level and
## clear of forest discs — sampled every ~6u. Anything else (river, sea, peak,
## forest) forces the routed fallback, which handles those properly.
func _straight_clear(nav, a: Vector2, b: Vector2, forest_discs: Array) -> bool:
	var steps := maxi(2, int(ceil(a.distance_to(b) / 6.0)))
	for s in steps + 1:
		var p := a.lerp(b, float(s) / float(steps))
		var c: Vector2i = nav.cell_of(p)
		if c.x < 0 or c.y < 0 or c.x >= nav.gw or c.y >= nav.gh:
			return false
		if nav.water(c.x, c.y) != NavGrid.WATER_LAND:
			return false
		if nav.level(c.x, c.y) >= RoadRealizer.BAN_LEVEL:
			return false
		for disc in forest_discs:
			if p.distance_to(disc.center) < float(disc.radius):
				return false
	return true

## Tile coords crossed by a (short) polyline, sampled every ~12u.
func _route_tiles(geo: PackedVector2Array) -> Array:
	var out: Array = []
	for i in range(geo.size() - 1):
		var seg_len := geo[i].distance_to(geo[i + 1])
		var steps := maxi(1, int(ceil(seg_len / 12.0)))
		for s in steps + 1:
			var p := geo[i].lerp(geo[i + 1], float(s) / float(steps))
			var coord: Vector2i = terrain.tile_coord_for_map_coord(terrain.local_to_map(p))
			if not out.has(coord) and terrain.tiles.has(coord):
				out.append(coord)
	return out

func _tile_id_at(p: Vector2) -> String:
	var coord: Vector2i = terrain.tile_coord_for_map_coord(terrain.local_to_map(p))
	var td: Dictionary = terrain.tiles.get(coord, {})
	return str(td.get("id", ""))

## Geometry points of the given edges within `radius` of `around` (every 2nd
## point — polylines are ~12u sampled, plenty for a closest-approach search).
func _points_near(network: RoadNetwork, edge_ids: Array, around: Vector2, radius: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var r2 := radius * radius
	for eid in edge_ids:
		var geo: PackedVector2Array = network.edges[eid].geometry
		var i := 0
		while i < geo.size():
			if geo[i].distance_squared_to(around) <= r2:
				out.append(geo[i])
			i += 2
	return out

## Union-find root with path compression.
func _uf_find(parent: PackedInt32Array, i: int) -> int:
	var root := i
	while parent[root] != root:
		root = parent[root]
	while parent[i] != root:
		var nxt := parent[i]
		parent[i] = root
		i = nxt
	return root
