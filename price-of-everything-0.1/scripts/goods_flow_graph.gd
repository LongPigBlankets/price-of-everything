extends RefCounted
## Goods Graph — derives the "which good feeds which good" web from the live Catalog.
##
## In-game port of the offline chart generator (scripts/build_goods_flow.py), with one
## deliberate inversion: the offline chart defines each good by its LEAST-efficient
## recipe (a documentation choice), while this picks the SIMPLEST recipe available at
## GAME START — among producers with an empty `tech_unlock_req` column: fewest
## distinct inputs, then lowest energy_req, then smallest total input quantity, with
## recipe_id as the final (deterministic) tie-break. A good whose every producer is
## research-gated falls back to the simplest gated recipe and is marked `gated`.
##
## Unlike the Python, there are no "external feedstock" nodes: catalog.gd's promotion
## gate drops any recipe referencing a good that is not in the goods table, so every
## input of every promoted recipe resolves. Pure data (no scene access, no RNG):
## deterministic and headless-testable (CLAUDE.md #3).
##
## Layout is Sugiyama-style: multi-tier edges get an invisible dummy vertex per
## intermediate tier (occupying a row slot — the corridor the edge runs through),
## row order is barycentre sweeps + a transpose pass minimising the bilayer crossing
## count, and every edge carries axis-aligned "waypoints" (90-degree turns only,
## parallel edges separated into vertical lanes per channel).

# World-space layout geometry (the view scales everything with zoom, so these are
# document units, not screen pixels). Card size per owner 2026-07-18: doubled height /
# +30% width so the icon chip reads ~100 px at maximum zoom-in (view _ZOOM_MAX = 1.0),
# with a wider channel (COL_W - CARD_W = 180) to relax the edge routing.
const COL_W := 820.0
# Column x-spacing is NOT uniform: within a tier the step is tightened, and each
# tier boundary adds an extra gap (owner 2026-07-21). All column->x mapping goes
# through col_x(); COL_W remains the base for card/channel geometry.
# Column spacing. The 200u floor below was measured against a web that drew EVERY edge at
# rest: ~180u was the point where y-overlapping risers crowded past the 11.9u readability
# floor. Resting edges are no longer drawn (goods_graph_world._REST_GHOST_ALPHA), so the
# constraint that set that floor is gone — only a selected good's own chain is ever drawn
# over these columns, which is a fraction of the density the 200u was protecting.
# Tightened accordingly, then halved again at the owner's request. The tier boundary is
# now only a little wider than an ordinary column gap (140 vs 110), so the tiers are read
# from the header plates above them rather than from the spacing — worth knowing before
# anyone tightens INTRA_COL_GAP further and closes the difference completely.
const INTRA_COL_GAP := 110.0
const INTER_TIER_GAP := 140.0

# Swimlanes (owner 2026-07-21): the resting view groups goods into CATEGORY
# lanes that run horizontally across every tier — the vertical axis reads as
# taxonomy. Crossing-minimisation still runs, but only WITHIN a (column, lane)
# cell; a lane's band height is its tallest cell and cells centre in the band.
const LANE_ORDER: Array[String] = ["energy", "petrochem", "metals", "construction",
	"vehicles", "electronics", "chems", "agribio", "waste"]
# Display names where the CSV slug isn't the full lane title (owner 2026-07-22).
# " & " splits into stacked label lines in the renderer.
const LANE_LABELS := {
	"petrochem": "HYDROCARBONS & PETROCHEM",
	"vehicles": "VEHICLES & PARTS",
	"electronics": "ELECTRICALS & ELECTRONICS",
}
const LANE_GAP_Y := 45.0    # vertical air between lane bands (tightened with the columns)


static func _lane_rank_of(cat: String) -> int:
	var i := LANE_ORDER.find(cat)
	return i if i >= 0 else LANE_ORDER.size()   # unknown categories sink to a trailing OTHER lane
static var _col_x: PackedFloat32Array = PackedFloat32Array()
# Row heights. ROW_H has to clear CARD_H (112) with air around it; the rest was slack.
#
# DUMMY rows are edge-routing corridors — they hold no card, they exist so a line has
# somewhere to run. At rest no line is drawn any more, so every one of them was spending
# 72u of the player's screen on nothing. They still have to EXIST, because a selected
# good's chain is routed through them, but they can be a good deal thinner than a card.
const ROW_H := 132.0
const DUMMY_ROW_H := 34.0
const CARD_W := 380.0
const CARD_H := 112.0
const BARY_SWEEPS := 2     # barycentre sweeps per ordering round
const ORDER_ROUNDS := 16   # sweeps+transpose rounds; stops early when crossings stall

# Edge-routing geometry. Between adjacent columns each edge rides a vertical LANE in
# the channel (the CHANNEL_W gap between card edges); spans whose y-intervals overlap
# are forced onto different lanes (greedy interval colouring), so parallel edges keep
# clear separation instead of overdrawing.
const CHANNEL_W := COL_W - CARD_W   # 440.0 (owner: double the inter-column space)
const LANE_PAD := 24.0              # channel inset before the first lane
const LANE_GAP_MIN := 12.0
const LANE_GAP_MAX := 26.0
const LANE_CLEAR := 4.0             # y clearance required for two spans to share a lane
const PORT_MARGIN := 10.0           # ports stay within +/-(CARD_H/2 - margin) of centre
const PORT_STEP_MAX := 14.0         # preferred spacing between ports on one card edge
const BACK_MARGIN := 56.0           # first below-web corridor sits this far under it
const BACK_GAP := 28.0              # spacing between below-web corridors

# Horizontal runs (port stubs and dummy-row corridors) get the same treatment as
# vertical lanes: runs of different edges that would overlap collinearly are nudged
# onto distinct y offsets, so a dim edge is never overdrawn by another edge's run.
const H_SEP := 12.0                 # min y between x-overlapping runs of different cards
const H_SEP_SIBLING := 9.0          # min y between stubs fanning from the SAME card side
const H_CLEAR := 4.0                # x clearance when testing two runs for overlap
const H_GRID := 4.0                 # candidate nudges walk out in this quantum
const PORT_LIMIT := CARD_H * 0.5 - 4.0    # nudged ports stay on the card edge (+/-52)
const CORRIDOR_LIMIT := 30.0        # corridor nudges stay inside the DUMMY_ROW_H slot (+/-36)

# Category -> accent colour, mirroring docs/goods_flow_chart.html. Goods with a blank
# category fall back by good_type (raw grey-blue, finished violet, power gold).
const CAT_COLOR := {
	"metals": Color("#d98a4b"), "chems": Color("#7bb0e0"),
	"construction": Color("#9ac26a"), "energy": Color("#e0635e"),
	"water": Color("#4fc7d4"), "agribio": Color("#7ed0a0"),
	"consumer": Color("#c98ad9"), "hightech": Color("#e0c44f"),
	"component": Color("#b0b0c0"), "power": Color("#f2c14e"),
	"waste": Color("#8a8a8a"),
	# Owner re-taxonomy 2026-07-22: the three lanes carved out of construction.
	"petrochem": Color("#c2703e"), "vehicles": Color("#c98ad9"),
	"electronics": Color("#4fc7d4"),
}
const TYPE_COLOR := {
	"raw": Color("#9aa0a8"), "intermediate": Color("#8ea3ba"),
	"finished": Color("#c98ad9"), "power": Color("#f2c14e"),
	"waste": Color("#8a8a8a"),
}
const DEFAULT_COLOR := Color("#8ea3ba")

# The authored balancing bands, left to right — the goods_graph_tier CSV column
# must hold one of these (validated in the unit suite).
const TIER_BANDS: Array[String] = ["raw", "processed", "intermediate", "finished", "apex"]


## Build the full graph. Returns:
##   nodes: Array[Dictionary]  — one per good (see _node_record), sorted (tier, row)
##   by_id: Dictionary         — internal_name -> its node dict (same objects)
##   edges: Array[Dictionary]  — {from, to, waypoints} input_good -> output_good;
##                               waypoints is a strictly axis-aligned PackedVector2Array
##                               from the source card's right edge to the target's left
##   tier_count: int
##   crossings: int            — bilayer crossing count of the final row ordering
## World-space x for a column index, honouring the tightened intra-tier step and
## the per-boundary TIER_GAP (see build()). Falls back to uniform COL_W spacing
## for out-of-range indices (only before the first build()).
static func col_x(c: int) -> float:
	if c >= 0 and c < _col_x.size():
		return _col_x[c]
	if _col_x.is_empty():
		return float(c) * COL_W
	if c < 0:
		return float(c) * (CARD_W + INTRA_COL_GAP)
	return _col_x[_col_x.size() - 1] + float(c - _col_x.size() + 1) * (CARD_W + INTRA_COL_GAP)


## The whole goods-graph layout (nodes with positions, routed edges, bands, lanes).
## It is a PURE function of the Catalog — no MatchState, no research-unlock state, no
## RNG (the "gated" flag is the static `tech_unlock_req` CSV column) — so the result
## is identical for every open and every match. The Catalog is fixed for the app run,
## so we compute it ONCE and cache it: the first call (warmed under the loading screen
## via world_map) pays the ~120 ms Sugiyama layout; every later open returns instantly.
## Pass force=true (or clear_cache()) to recompute, e.g. after a catalog reload in tests.
static var _cache: Dictionary = {}
static var _legacy_cache: Dictionary = {}

## Drop the cached layout so the next build() recomputes (catalog reloads in tools/tests).
static func clear_cache() -> void:
	_cache = {}
	_legacy_cache = {}

## `legacy_layout` restores the pre-swimlane row placement while leaving the
## current layout as the default. The two layouts have separate caches.
static func build(force := false, legacy_layout := false) -> Dictionary:
	var cache: Dictionary = _legacy_cache if legacy_layout else _cache
	if not force and not cache.is_empty():
		return cache
	# 1 · Goods universe, keyed by internal name.
	var goods: Dictionary = {}
	for g in MatchState.visible_goods():
		var internal := str(g.get("internal_name", ""))
		if internal != "":
			goods[internal] = g

	# 2 · Producer index: primary (output_1) preferred, any-output fallback.
	var primary: Dictionary = {}
	var anyout: Dictionary = {}
	for r in Catalog.all_recipes():
		var outs: Array = r.get("outputs", [])
		if outs.is_empty():
			continue
		_index_append(primary, str(outs[0].get("internal_name", "")), r)
		for o in outs:
			_index_append(anyout, str(o.get("internal_name", "")), r)

	# 3 · Defining recipe per good (simplest game-start, gated fallback). Owner
	# rule 2026-07-22: a Recycling (waste-to-good) recipe can NEVER be the base —
	# scrap->steel may be the simplest route, but coal+iron IS steel. Recycling
	# routes stay as alternates; a recycling base is allowed only when no other
	# producer exists at all (even a gated non-recycling route outranks it).
	var chosen: Dictionary = {}   # internal -> {recipe, gated}
	for internal in goods:
		var producers: Array = primary.get(internal, anyout.get(internal, []))
		if producers.is_empty():
			continue
		var making: Array = producers.filter(
			func(r: Dictionary) -> bool: return str(r.get("recipe_type", "")).to_lower() != "recycling")
		var pool: Array = making if not making.is_empty() else producers
		var base: Array = pool.filter(
			func(r: Dictionary) -> bool: return str(r.get("tech_unlock_req", "")) == "")
		if base.is_empty():
			chosen[internal] = {"recipe": _simplest(pool), "gated": true}
		else:
			chosen[internal] = {"recipe": _simplest(base), "gated": false}

	# 4 · Edges: the BASE web only (owner 2026-07-19: "base chain, all yellow, no
	# alternative recipes" — alternates moved to the per-good minigraph focus view).
	# Each good draws its defining recipe's inputs; a gated-only good's edges render
	# dashed (route_gated). POWER is the one deliberate exception: its "simplest"
	# recipe is fuel-less wind, which would erase the coal/oil/pet-coke flows that
	# are the game's central carbon choice — power draws the UNION of every
	# game-start power recipe's inputs.
	var edge_seen: Dictionary = {}
	var edges: Array = []
	var adj: Dictionary = {}        # internal -> Array of goods it feeds
	var radj: Dictionary = {}       # internal -> Array of goods feeding it
	var radj_base: Dictionary = radj  # base == full set now; kept for the node contract
	for internal: String in _sorted_keys(chosen):
		var gated_def := bool((chosen[internal] as Dictionary).get("gated", false))
		var edge_recipes: Array = [chosen[internal]["recipe"]]
		if str((goods[internal] as Dictionary).get("good_type", "")) == "power":
			var ungated: Array = (primary.get(internal, anyout.get(internal, [])) as Array).filter(
				func(r: Dictionary) -> bool: return str(r.get("tech_unlock_req", "")) == "")
			if not ungated.is_empty():
				edge_recipes = ungated
		for er in edge_recipes:
			for inp in (er as Dictionary).get("inputs", []):
				var src := str(inp.get("internal_name", ""))
				if not goods.has(src):
					continue
				var key := src + ">" + internal
				if edge_seen.has(key):
					continue
				edge_seen[key] = true
				edges.append({"from": src, "to": internal, "route": 0,
					"route_gated": gated_def})
				_index_append(adj, src, internal)
				_index_append(radj, internal, src)

	# 5 · Columns come from the authored goods_graph_tier bands (owner 2026-07-19:
	# RAW / PROCESSED / INTERMEDIATE / FINISHED / APEX regions), not computed depth —
	# stable positions, headers in game vocabulary. Within a band, 1-3 INVISIBLE
	# sub-columns (no headers) resolve the band's internal flow: sub-column = the
	# good's longest same-band chain depth, so every within-band edge still runs
	# left -> right. RAW has no internal edges and splits in half purely for height.
	var nodes_sorted := _sorted_keys(goods)
	var band_of: Dictionary = {}
	for n: String in nodes_sorted:
		var b := str((goods[n] as Dictionary).get("goods_graph_tier", ""))
		if not TIER_BANDS.has(b):
			push_warning("GoodsFlowGraph: '%s' has no goods_graph_tier — defaulting to intermediate" % n)
			b = "intermediate"
		band_of[n] = b
	# Same-band base-edge adjacency -> local depth (GREY/BLACK guard as before).
	var radj_band: Dictionary = {}
	for e in edges:
		if int(e.get("route", 0)) == 0 and str(band_of[str(e["from"])]) == str(band_of[str(e["to"])]):
			_index_append(radj_band, str(e["to"]), str(e["from"]))
	var local: Dictionary = {}
	var state: Dictionary = {}
	for n: String in nodes_sorted:
		if not local.has(n):
			_visit_depth(n, radj_band, local, state)
	# Sub-column counts per band; RAW forced to 2 for height.
	var sub_count: Dictionary = {}
	for b: String in TIER_BANDS:
		sub_count[b] = 1
	for n: String in nodes_sorted:
		var b2: String = band_of[n]
		sub_count[b2] = maxi(int(sub_count[b2]), int(local[n]) + 1)
	sub_count["raw"] = maxi(int(sub_count["raw"]), 2)
	# RAW halves: first half of the display-name order takes sub 0.
	var raw_names: Array = []
	for n: String in nodes_sorted:
		if str(band_of[n]) == "raw":
			raw_names.append(n)
	raw_names.sort_custom(func(a: String, b: String) -> bool:
		return _display_of(a, goods) < _display_of(b, goods))
	var raw_sub: Dictionary = {}
	for i: int in range(raw_names.size()):
		raw_sub[raw_names[i]] = 0 if i < (raw_names.size() + 1) / 2 else 1
	# Global column index per good + band metadata for the header plates.
	var bands_meta: Array = []
	var band_base: Dictionary = {}
	var col_cursor := 0
	for b3: String in TIER_BANDS:
		band_base[b3] = col_cursor
		bands_meta.append({"label": b3.to_upper(), "first": col_cursor, "count": int(sub_count[b3])})
		col_cursor += int(sub_count[b3])
	var depth: Dictionary = {}
	for n: String in nodes_sorted:
		var sub: int = raw_sub[n] if str(band_of[n]) == "raw" else int(local[n])
		depth[n] = int(band_base[band_of[n]]) + mini(sub, int(sub_count[band_of[n]]) - 1)
	var maxd := col_cursor - 1

	# Per-column x: tighten within a tier, add TIER_GAP at each tier boundary. One
	# source of truth for every column->x conversion (nodes, edges, headers).
	var _boundary_cols: Dictionary = {}
	for bm: Dictionary in bands_meta:
		var f := int(bm.get("first", 0))
		if f > 0:
			_boundary_cols[f] = true
	_col_x = PackedFloat32Array()
	var running_x := 0.0
	for c: int in range(maxd + 1):
		if c > 0:
			# pitch = card width + the gap AFTER this column's kind of boundary
			running_x += CARD_W + (INTER_TIER_GAP if _boundary_cols.has(c) else INTRA_COL_GAP)
		_col_x.append(running_x)

	# 6 · Sugiyama layout graph: real goods plus one invisible dummy vertex per
	# intermediate tier of every multi-tier edge. Dummies occupy row slots exactly
	# like real nodes (their slot stays empty visually — the corridor the edge runs
	# through), but at the compressed DUMMY_ROW_H, and are NOT returned. Back-edges
	# inside cycles (depth[to] <=
	# depth[from], e.g. waste_water -> water) get no dummies; _route_edges sends them
	# below the web instead.
	var ldepth: Dictionary = {}   # layout vertex (good or dummy) -> column
	var lane_rank: Dictionary = {}
	for n: String in nodes_sorted:
		ldepth[n] = int(depth[n])
		if not legacy_layout:
			# Swimlane rank per layout vertex: goods by category; a dummy inherits
			# its edge's TARGET lane.
			lane_rank[n] = _lane_rank_of(str((goods[n] as Dictionary).get("category", "")))
	var ladj: Dictionary = {}     # layout vertex -> chain successors (next column)
	var lradj: Dictionary = {}    # layout vertex -> chain predecessors
	var chains: Dictionary = {}   # edge index -> Array[String] chain, from .. to
	var backs: Array = []         # edge indices with span <= 0 (cycle back-edges)
	for ei: int in range(edges.size()):
		var e: Dictionary = edges[ei]
		var u := str(e["from"])
		var v := str(e["to"])
		if int(depth[v]) <= int(depth[u]):
			backs.append(ei)
			continue
		var chain: Array = [u]
		for d: int in range(int(depth[u]) + 1, int(depth[v])):
			var dummy := "~%s>%s@%d" % [u, v, d]
			ldepth[dummy] = d
			if not legacy_layout:
				lane_rank[dummy] = int(lane_rank[v])
			chain.append(dummy)
		chain.append(v)
		chains[ei] = chain
		for i: int in range(chain.size() - 1):
			_index_append(ladj, chain[i], chain[i + 1])
			_index_append(lradj, chain[i + 1], chain[i])

	# 7 · Order rows (barycentre + transpose over goods AND dummies), then place the
	# real nodes. Row heights are non-uniform — good rows ROW_H, dummy rows the
	# compressed DUMMY_ROW_H — so each row's centre y is the cumulative sum of the
	# heights above it, and every column is vertically centred by its TOTAL height
	# (not its row count) against the tallest column.
	var cols := _order_columns(ldepth, ladj, lradj, goods, maxd, lane_rank)
	var crossings := count_crossings(cols, ladj, maxd)

	var ypos: Dictionary = {}     # layout vertex -> row-centre y
	var route_bottom := 0.0
	var lanes_meta: Array = []
	if legacy_layout:
		# Pre-swimlane layout: every column is vertically centred against the
		# tallest column, with no category bands or lane-specific ordering.
		var col_height: Dictionary = {}
		var max_height := 0.0
		for d: int in range(maxd + 1):
			var total := 0.0
			for v: String in cols.get(d, []) as Array:
				total += ROW_H if goods.has(v) else DUMMY_ROW_H
			col_height[d] = total
			max_height = maxf(max_height, total)
		for d: int in range(maxd + 1):
			var col: Array = cols.get(d, [])
			var y := (max_height - float(col_height[d])) * 0.5
			for v: String in col:
				var h := ROW_H if goods.has(v) else DUMMY_ROW_H
				ypos[v] = y + h * 0.5
				y += h
		route_bottom = max_height
	else:
		# Swimlane vertical placement. A lane band is sized by the CARDS in its tallest
		# (column, lane) cell, and each cell's cards are packed contiguously and centred in
		# the band. Bands stack with LANE_GAP_Y of air; empty lanes take no space.
		#
		# DUMMY ROWS ARE NOT SIZED IN. A dummy is an edge corridor, not a card, and counting
		# them did two visible things: it inflated every band to fit corridors nobody can see,
		# and it pushed a cell's cards apart so they no longer read as a group sitting in the
		# middle of their lane. They still get a y — the routing code expects one for every
		# layout vertex — taken from the cards they sit between, so a corridor stays where its
		# edge would want it without spending a row on it.
		#
		# Safe because this branch is the MODERN presentation only (legacy_layout takes the
		# arm above): there, resting edges are not drawn at all and a selection swaps to the
		# focus layout, which does its own routing. Nothing visible routes through these
		# corridors any more.
		var lane_count := LANE_ORDER.size() + 1
		var cell_h: Dictionary = {}     # "lane:column" -> summed CARD heights
		var lane_h: Dictionary = {}     # lane rank -> band height
		for d: int in range(maxd + 1):
			for v: String in cols.get(d, []) as Array:
				if not goods.has(v):
					continue   # corridor: costs the band nothing
				var lr := int(lane_rank.get(v, lane_count - 1))
				var key := "%d:%d" % [lr, d]
				cell_h[key] = float(cell_h.get(key, 0.0)) + ROW_H
				lane_h[lr] = maxf(float(lane_h.get(lr, 0.0)), float(cell_h[key]))
		var lane_top: Dictionary = {}
		var ly := 0.0
		for lr: int in range(lane_count):
			if not lane_h.has(lr):
				continue
			lane_top[lr] = ly
			var slug := LANE_ORDER[lr] if lr < LANE_ORDER.size() else ""
			var label: String = LANE_LABELS.get(slug, slug.to_upper()) if slug != "" else "OTHER"
			lanes_meta.append({"label": label, "top": ly, "height": float(lane_h[lr]),
				"color": CAT_COLOR.get(slug, DEFAULT_COLOR)})
			ly += float(lane_h[lr]) + LANE_GAP_Y
		for d: int in range(maxd + 1):
			var cursor: Dictionary = {}    # lane rank -> next free y for a CARD in this column
			var pending: Array = []        # corridors waiting for the next card's y
			for v: String in cols.get(d, []) as Array:
				var lr := int(lane_rank.get(v, lane_count - 1))
				if not goods.has(v):
					pending.append(v)
					continue
				if not cursor.has(lr):
					var cell := float(cell_h.get("%d:%d" % [lr, d], 0.0))
					cursor[lr] = float(lane_top[lr]) + (float(lane_h[lr]) - cell) * 0.5
				var y := float(cursor[lr]) + ROW_H * 0.5
				ypos[v] = y
				cursor[lr] = float(cursor[lr]) + ROW_H
				for pv in pending:
					ypos[pv] = y   # the corridor rides with the card it precedes
				pending.clear()
			# Trailing corridors in a column have no card after them: park them on the last
			# card placed, or on the top of the chart if the column is corridors all the way.
			for pv in pending:
				ypos[pv] = float(ypos.get(cols.get(d, [])[0], 0.0)) if not ypos.is_empty() else 0.0
		route_bottom = ly - LANE_GAP_Y

	var by_id: Dictionary = {}
	var nodes: Array = []
	for d: int in range(maxd + 1):
		var col: Array = cols.get(d, [])
		for i: int in range(col.size()):
			var internal: String = col[i]
			if not goods.has(internal):
				continue   # dummy slot: left empty, forms an edge corridor
			var rec := _node_record(internal, goods[internal], chosen.get(internal, {}),
				primary.get(internal, anyout.get(internal, [])), d, i,
				Vector2(col_x(d), float(ypos[internal])), adj, radj, radj_base)
			by_id[internal] = rec
			nodes.append(rec)

	# 8 · Orthogonal edge geometry (adds "waypoints" to every edge dict).
	# Back-edge corridors dive below the whole chart.
	_route_edges(edges, chains, backs, ldepth, ypos, route_bottom)

	cache = {"nodes": nodes, "by_id": by_id, "edges": edges, "tier_count": maxd + 1,
		"bands": bands_meta,
		"lanes": lanes_meta,
		"crossings": crossings, "legacy_layout": legacy_layout}
	if legacy_layout:
		_legacy_cache = cache
	else:
		_cache = cache
	return cache


## Every producing recipe of a good, simplest-first with ungated before gated —
## the focus grid's island list. Queried live from the Catalog so it always matches
## what the game would let the player build. Element shape: {recipe, gated}.
static func routes_for_good(internal: String) -> Array:
	var primary: Array = []
	var anyout: Array = []
	for r in Catalog.all_recipes():
		var outs: Array = r.get("outputs", [])
		if outs.is_empty():
			continue
		if str(outs[0].get("internal_name", "")) == internal:
			primary.append(r)
		else:
			for o in outs:
				if str(o.get("internal_name", "")) == internal:
					anyout.append(r)
					break
	return _ranked_producers(primary if not primary.is_empty() else anyout)


## Case-insensitive substring search over the goods' display names (owner 2026-07-19:
## plain string match, any part of the string, no fuzzy matching; caller enforces the
## 3-letter minimum shown to the player). Returns ALL matching node dicts ranked by
## match position, then name length, then name — the caller caps the display at 3
## and auto-picks on Enter only when exactly one match exists.
static func search_goods(query: String, nodes: Array) -> Array:
	var q := query.strip_edges().to_lower()
	if q.length() < 3:
		return []
	var hits: Array = []
	for n in nodes:
		var name := str((n as Dictionary).get("display", "")).to_lower()
		var pos := name.find(q)
		if pos >= 0:
			hits.append([pos, name.length(), name, n])
	hits.sort_custom(func(a: Array, b: Array) -> bool:
		return _key_less([a[0], a[1], a[2]], [b[0], b[1], b[2]]))
	var out: Array = []
	for h: Array in hits:
		out.append(h[3])
	return out


static func accent_for(node: Dictionary) -> Color:
	var cat := str(node.get("category", ""))
	if CAT_COLOR.has(cat):
		return CAT_COLOR[cat]
	return TYPE_COLOR.get(str(node.get("good_type", "")), DEFAULT_COLOR)


## Total crossing count over all adjacent-tier channels: the standard bilayer
## inversion count over chain segments (dummy vertices included), i.e. pairs of
## segments in one channel whose endpoint orders invert.
static func count_crossings(cols: Dictionary, ladj: Dictionary, maxd: int) -> int:
	var pos := _positions(cols, maxd)
	var total := 0
	for d: int in range(maxd):
		total += _channel_crossings(cols.get(d, []), ladj, pos)
	return total


# --- internals ---------------------------------------------------------------------

static func _index_append(dict: Dictionary, key: String, value: Variant) -> void:
	if key == "":
		return
	if not dict.has(key):
		dict[key] = []
	(dict[key] as Array).append(value)


static func _sorted_keys(d: Dictionary) -> Array:
	var keys := d.keys()
	keys.sort()
	return keys


static func _total_input_qty(r: Dictionary) -> int:
	var total := 0
	for inp in r.get("inputs", []):
		total += int(inp.get("qty", 0))
	return total


## Simplest = fewest distinct inputs, then lowest power, then smallest total input
## qty, then recipe_id (so ties never depend on CSV row order).
static func _simplest_key(r: Dictionary) -> Array:
	return [
		(r.get("inputs", []) as Array).size(),
		int(r.get("energy_req", 0)),
		_total_input_qty(r),
		str(r.get("recipe_id", "")),
	]


static func _simplest(recipes: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_key: Array = []
	for r in recipes:
		var key := _simplest_key(r)
		if best.is_empty() or _key_less(key, best_key):
			best = r
			best_key = key
	return best


## Every producing route of a good, simplest-first, ungated before research-gated —
## the colour ranking for the web (yellow base, then blue/green/purple alternates).
## Element shape: {recipe: Dictionary, gated: bool}. routes[0] always equals the
## good's defining recipe (same ordering as _simplest / the chosen fallback).
static func _ranked_producers(producers: Array) -> Array:
	# Mirrors the base-recipe chooser exactly (owner 2026-07-22: Recycling can
	# never be the base), so the grid always leads with the defining recipe:
	# non-recycling ungated > non-recycling gated > recycling ungated > gated.
	var by_key := func(a: Dictionary, b: Dictionary) -> bool:
		return _key_less(_simplest_key(a), _simplest_key(b))
	var tiers: Array = [[], [], [], []]
	for r in producers:
		var rec := str(r.get("recipe_type", "")).to_lower() == "recycling"
		var gat := str(r.get("tech_unlock_req", "")) != ""
		(tiers[(2 if rec else 0) + (1 if gat else 0)] as Array).append(r)
	var out: Array = []
	for ti: int in range(4):
		var arr: Array = tiers[ti]
		arr.sort_custom(by_key)
		for r in arr:
			out.append({"recipe": r, "gated": ti % 2 == 1})
	return out


## Lexicographic compare of mixed int/float/String sort keys (Arrays have no `<`).
static func _key_less(a: Array, b: Array) -> bool:
	for i in range(mini(a.size(), b.size())):
		if a[i] != b[i]:
			return a[i] < b[i]
	return a.size() < b.size()


## Longest-path DFS depth with GREY/BLACK colouring: a parent still on the stack
## (GREY) is a back-edge inside a cycle (e.g. water <-> waste_water) and is skipped,
## so the layering stays acyclic. Recursion depth is bounded by the longest chain.
static func _visit_depth(u: String, radj: Dictionary, depth: Dictionary, state: Dictionary) -> void:
	state[u] = 1   # GREY
	var best := 0
	for p in radj.get(u, []):
		if int(state.get(p, 0)) == 1:
			continue
		if not depth.has(p):
			_visit_depth(p, radj, depth, state)
		best = maxi(best, int(depth[p]) + 1)
	depth[u] = best
	state[u] = 2   # BLACK


# --- row ordering (crossing minimisation) ------------------------------------------

## Order each column's rows over the LAYOUT graph (goods + dummies): seed
## alphabetically, then up to ORDER_ROUNDS rounds of barycentre sweeps followed by a
## transpose pass, keeping the best ordering seen (by global crossing count) and
## stopping as soon as a round fails to improve it. Fully deterministic: every sort
## key ends in a unique id or row index.
static func _order_columns(ldepth: Dictionary, ladj: Dictionary, lradj: Dictionary,
		goods: Dictionary, maxd: int, lane_rank: Dictionary) -> Dictionary:
	var cols: Dictionary = {}
	for v: String in _sorted_keys(ldepth):
		var d: int = ldepth[v]
		if not cols.has(d):
			cols[d] = []
		(cols[d] as Array).append(v)
	for d: int in range(maxd + 1):
		var arr: Array = cols.get(d, [])
		var keyed: Array = []
		for id: String in arr:
			keyed.append([int(lane_rank.get(id, 0)), _seed_key(id, goods), id])
		keyed.sort_custom(func(a: Array, b: Array) -> bool: return _key_less(a, b))
		for i: int in range(arr.size()):
			arr[i] = (keyed[i] as Array)[2]

	var best := count_crossings(cols, ladj, maxd)
	var best_cols := _copy_cols(cols)
	var stale := 0
	for round_i: int in range(ORDER_ROUNDS):
		var use_median := round_i % 2 == 1   # alternate mean / median heuristics
		for _sweep: int in range(BARY_SWEEPS):
			var pos := _positions(cols, maxd)
			for d: int in range(1, maxd + 1):
				_bary_sort(cols, d, lradj, pos, lane_rank, use_median)
			pos = _positions(cols, maxd)
			for d: int in range(maxd - 1, -1, -1):
				_bary_sort(cols, d, ladj, pos, lane_rank, use_median)
		# Transpose and sift only ever apply strictly-improving moves, so this inner
		# polish loop is monotone decreasing — run it to its local fixpoint.
		var c := count_crossings(cols, ladj, maxd)
		for _polish: int in range(8):
			_transpose(cols, ladj, lradj, maxd, lane_rank)
			_sift(cols, ladj, lradj, maxd, lane_rank)
			var c2 := count_crossings(cols, ladj, maxd)
			if c2 == c:
				break
			c = c2
		if c < best:
			best = c
			best_cols = _copy_cols(cols)
			stale = 0
		else:
			stale += 1
			if stale >= 2:   # both heuristics failed to improve — converged
				break
	return best_cols


## Seed order: real goods first (alphabetical by display name), dummies after (by id).
static func _seed_key(id: String, goods: Dictionary) -> String:
	if goods.has(id):
		return "0" + _display_of(id, goods) + "|" + id
	return "1" + id


static func _copy_cols(cols: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for d: int in cols:
		out[d] = (cols[d] as Array).duplicate()
	return out


static func _positions(cols: Dictionary, maxd: int) -> Dictionary:
	var pos: Dictionary = {}
	for d in range(maxd + 1):
		var arr: Array = cols.get(d, [])
		for i in range(arr.size()):
			pos[arr[i]] = i
	return pos


## Barycentre sort of one column: mean (or median) neighbour row, tie-broken by
## current row (so ties keep their relative order and the unstable sort stays
## deterministic).
static func _bary_sort(cols: Dictionary, d: int, neighbours: Dictionary, pos: Dictionary,
		lane_rank: Dictionary, use_median: bool = false) -> void:
	var arr: Array = cols.get(d, [])
	var keyed: Array = []
	for id: String in arr:
		var key := _median(id, neighbours, pos) if use_median \
			else _barycentre(id, neighbours, pos)
		# Lane rank leads the key: barycentre only reorders WITHIN a lane cell.
		keyed.append([int(lane_rank.get(id, 0)), key, int(pos.get(id, 0)), id])
	keyed.sort_custom(func(a: Array, b: Array) -> bool: return _key_less(a, b))
	for i: int in range(arr.size()):
		arr[i] = (keyed[i] as Array)[3]


static func _barycentre(n: String, neighbours: Dictionary, pos: Dictionary) -> float:
	var ns: Array = neighbours.get(n, [])
	if ns.is_empty():
		return float(pos.get(n, 0))
	var total := 0.0
	for p in ns:
		total += float(pos.get(p, 0))
	return total / float(ns.size())


## Median neighbour row (Sugiyama's median heuristic; even counts average the two
## middles). Nodes without neighbours keep their current row.
static func _median(n: String, neighbours: Dictionary, pos: Dictionary) -> float:
	var ns: Array = neighbours.get(n, [])
	if ns.is_empty():
		return float(pos.get(n, 0))
	var rows: Array = []
	for p in ns:
		rows.append(int(pos.get(p, 0)))
	rows.sort()
	var m := rows.size() / 2
	if rows.size() % 2 == 1:
		return float(rows[m])
	return (float(rows[m - 1]) + float(rows[m])) * 0.5


## TRANSPOSE pass (Sugiyama): repeatedly swap adjacent rows within a column when that
## strictly reduces the crossing count of the column's two adjacent channels. A swap
## of neighbours u/w only changes crossings between u's and w's own segments, so the
## gain is counted over those pairs alone. Mutates cols in place; guarded loop.
static func _transpose(cols: Dictionary, ladj: Dictionary, lradj: Dictionary, maxd: int,
		lane_rank: Dictionary) -> void:
	var pos := _positions(cols, maxd)
	var improved := true
	var guard := 0
	while improved and guard < 24:
		guard += 1
		improved = false
		for d: int in range(maxd + 1):
			var arr: Array = cols.get(d, [])
			for i: int in range(arr.size() - 1):
				var u: String = arr[i]
				var w: String = arr[i + 1]
				if int(lane_rank.get(u, 0)) != int(lane_rank.get(w, 0)):
					continue   # never swap across a lane boundary
				if _swap_gain(u, w, ladj, pos) + _swap_gain(u, w, lradj, pos) > 0:
					arr[i] = w
					arr[i + 1] = u
					pos[w] = i
					pos[u] = i + 1
					improved = true


## SIFTING pass: move each vertex to the row in its column that minimises crossings
## with both adjacent channels. The delta of bubbling v past a neighbour only depends
## on adjacent-column rows (never on rows inside v's own column), so the cumulative
## swap gains give the exact crossing delta for every landing row in one scan.
## Deterministic: columns in order, vertices by degree (desc) then id.
static func _sift(cols: Dictionary, ladj: Dictionary, lradj: Dictionary, maxd: int,
		lane_rank: Dictionary) -> void:
	var pos := _positions(cols, maxd)
	for d: int in range(maxd + 1):
		var arr: Array = cols.get(d, [])
		var order: Array = []
		for id: String in arr:
			var deg := (ladj.get(id, []) as Array).size() + (lradj.get(id, []) as Array).size()
			order.append([-deg, id])
		order.sort_custom(func(a: Array, b: Array) -> bool: return _key_less(a, b))
		for entry: Array in order:
			var v: String = entry[1]
			var i: int = pos[v]
			var vlane := int(lane_rank.get(v, 0))
			var best_delta := 0
			var best_pos := i
			var delta := 0
			for k: int in range(i - 1, -1, -1):   # bubble v upward, within its lane
				if int(lane_rank.get(arr[k], 0)) != vlane:
					break
				delta -= _swap_gain(arr[k], v, ladj, pos) + _swap_gain(arr[k], v, lradj, pos)
				if delta < best_delta:
					best_delta = delta
					best_pos = k
			delta = 0
			for k: int in range(i + 1, arr.size()):   # bubble v downward, within its lane
				if int(lane_rank.get(arr[k], 0)) != vlane:
					break
				delta -= _swap_gain(v, arr[k], ladj, pos) + _swap_gain(v, arr[k], lradj, pos)
				if delta < best_delta:
					best_delta = delta
					best_pos = k
			if best_pos != i:
				arr.remove_at(i)
				arr.insert(best_pos, v)
				for idx: int in range(arr.size()):
					pos[arr[idx]] = idx


## Crossings between u's and w's neighbour segments with u above w, minus the same
## with w above u — positive means swapping u/w removes crossings.
static func _swap_gain(u: String, w: String, neighbours: Dictionary, pos: Dictionary) -> int:
	var above := 0
	var below := 0
	for a: String in neighbours.get(u, []):
		var ra: int = pos.get(a, 0)
		for b: String in neighbours.get(w, []):
			var rb: int = pos.get(b, 0)
			if ra > rb:
				above += 1
			elif ra < rb:
				below += 1
	return above - below


## Bilayer inversion count for one channel: segments run from each vertex of the left
## column to its chain successors; two segments cross iff their endpoint orders invert.
static func _channel_crossings(left: Array, ladj: Dictionary, pos: Dictionary) -> int:
	var segs: Array = []   # [left_row, right_row]
	for u: String in left:
		var pu: int = pos.get(u, 0)
		for v: String in ladj.get(u, []):
			segs.append([pu, int(pos.get(v, 0))])
	var count := 0
	for i: int in range(segs.size()):
		for j: int in range(i + 1, segs.size()):
			var a: Array = segs[i]
			var b: Array = segs[j]
			if (int(a[0]) - int(b[0])) * (int(a[1]) - int(b[1])) < 0:
				count += 1
	return count


# --- orthogonal edge geometry ------------------------------------------------------

## Adds "waypoints" (strictly axis-aligned PackedVector2Array) to every edge dict:
##   [exit on source right edge] -> vertical lane in each channel -> horizontal run
##   along the dummy's empty row through each intermediate column -> [entry on target
##   left edge]. Exit ports spread vertically sorted by first-hop row; entry ports by
##   last-hop row. Per channel, spans whose y-intervals overlap get different lanes
##   (greedy interval colouring over deterministically sorted spans), and horizontal
##   runs that would overlap collinearly are nudged apart (_deconflict_horizontals)
##   before the vertical colouring sees them. Back-edges (span <= 0) dive below the
##   web, run along a private corridor, and climb back up.
static func _route_edges(edges: Array, chains: Dictionary, backs: Array,
		ldepth: Dictionary, ypos: Dictionary, web_bottom: float) -> void:
	# Below-web corridors for back-edges, deterministically stacked. `web_bottom`
	# is the tallest column's slot bottom (columns span y 0 .. web_bottom).
	var bottom := web_bottom + BACK_MARGIN
	var corridor: Dictionary = {}   # edge index -> corridor y
	var backs_sorted: Array = backs.duplicate()
	backs_sorted.sort_custom(func(a: int, b: int) -> bool:
		return _edge_key(edges[a]) < _edge_key(edges[b]))
	for i: int in range(backs_sorted.size()):
		corridor[backs_sorted[i]] = bottom + float(i) * BACK_GAP

	# Exit/entry ports: out-edges sorted by first-hop row, in-edges by last-hop row
	# (back-edges key on their corridor, sorting them to the card's bottom).
	var out_ports: Dictionary = {}   # source id -> Array of [sort_y, other_id, ei]
	var in_ports: Dictionary = {}    # target id -> Array of [sort_y, other_id, ei]
	for ei: int in range(edges.size()):
		var e: Dictionary = edges[ei]
		var u := str(e["from"])
		var v := str(e["to"])
		if chains.has(ei):
			var chain: Array = chains[ei]
			_index_append(out_ports, u, [float(ypos[chain[1]]), v, ei])
			_index_append(in_ports, v, [float(ypos[chain[chain.size() - 2]]), u, ei])
		else:
			_index_append(out_ports, u, [float(corridor[ei]), v, ei])
			_index_append(in_ports, v, [float(corridor[ei]), u, ei])
	var exit_y: Dictionary = {}      # edge index -> exit-port y
	var entry_y: Dictionary = {}     # edge index -> entry-port y
	for id: String in out_ports:
		_assign_ports(out_ports[id], float(ypos[id]), exit_y)
	for id: String in in_ports:
		_assign_ports(in_ports[id], float(ypos[id]), entry_y)

	# Separate horizontal runs BEFORE lane colouring, so vertical spans (and the lane
	# guarantees) are computed against the final, nudged y of every horizontal.
	var hy := _deconflict_horizontals(edges, chains, ldepth, ypos, exit_y, entry_y)

	# Collect every channel span (one per edge per channel crossed) with its y-interval.
	var chan_spans: Dictionary = {}  # channel -> Array of [lo, hi, from, to, hop, ei]
	for ei: int in range(edges.size()):
		var e: Dictionary = edges[ei]
		if chains.has(ei):
			var chain: Array = chains[ei]
			for j: int in range(chain.size() - 1):
				var yl: float = exit_y[ei] if j == 0 else float(hy["%d:%d" % [ei, j]])
				var yr: float = entry_y[ei] if j == chain.size() - 2 \
					else float(hy["%d:%d" % [ei, j + 1]])
				# Every attachment y constrains — a corridor entering the channel
				# from the left column has exactly an exit stub's geometry, and one
				# leaving right an entry stub's, so all four kinds order lanes.
				_add_span(chan_spans, int(ldepth[chain[j]]), yl, yr, e, j, ei, yl, yr)
		else:
			_add_span(chan_spans, int(ldepth[str(e["from"])]),
				float(exit_y[ei]), float(corridor[ei]), e, 0, ei,
				float(exit_y[ei]), float(corridor[ei]))
			_add_span(chan_spans, int(ldepth[str(e["to"])]) - 1,
				float(corridor[ei]), float(entry_y[ei]), e, 1, ei,
				float(corridor[ei]), float(entry_y[ei]))

	# Lane ordering per channel via a VERTICAL-CONSTRAINT digraph (VLSI channel
	# routing): a span whose y-interval covers another edge's EXIT-stub y must sit
	# RIGHT of that edge's span (the stub then reaches its lane without crossing us);
	# covering an ENTRY-stub y forces the opposite. Kahn's topological order with
	# deterministic tie-breaks honours every satisfiable constraint; cycles (where a
	# crossing is genuinely unavoidable) break at the lowest-indegree span. Greedy
	# lane reuse then assigns the lowest clear lane at or beyond every predecessor's,
	# so y-overlapping spans still always differ in lane.
	var lane_of: Dictionary = {}     # "ei:hop" -> lane index
	var lane_gap: Dictionary = {}    # channel -> x gap between lanes
	var chan_keys: Array = chan_spans.keys()
	chan_keys.sort()
	for c: int in chan_keys:
		var spans: Array = chan_spans[c]
		spans.sort_custom(func(a: Array, b: Array) -> bool: return _key_less(a, b))
		var n := spans.size()
		var succ: Array = []            # succ[i]: spans that must sit RIGHT of i
		var indeg := PackedInt32Array()
		indeg.resize(n)
		for i: int in range(n):
			succ.append([])
		for i: int in range(n):
			var lo_i := float((spans[i] as Array)[0])
			var hi_i := float((spans[i] as Array)[1])
			for j: int in range(n):
				if i == j or int((spans[i] as Array)[5]) == int((spans[j] as Array)[5]):
					continue
				var ex_j := float((spans[j] as Array)[6])
				if ex_j > lo_i + 0.5 and ex_j < hi_i - 0.5:
					# i covers j's exit stub: i right of j (arc j -> i).
					(succ[j] as Array).append(i)
					indeg[i] += 1
				var en_j := float((spans[j] as Array)[7])
				if en_j > lo_i + 0.5 and en_j < hi_i - 0.5:
					# i covers j's entry stub: i left of j (arc i -> j).
					(succ[i] as Array).append(j)
					indeg[j] += 1
		var order: Array = []
		var used := PackedByteArray()
		used.resize(n)
		for _k: int in range(n):
			var best := -1
			for i: int in range(n):
				if used[i] == 0 and indeg[i] == 0 \
						and (best == -1 or _key_less(spans[i], spans[best])):
					best = i
			if best == -1:
				# Cycle: forced pick — fewest outstanding constraints, then key.
				for i: int in range(n):
					if used[i] == 0 and (best == -1 or indeg[i] < indeg[best]
							or (indeg[i] == indeg[best] and _key_less(spans[i], spans[best]))):
						best = i
			used[best] = 1
			order.append(best)
			for j: int in (succ[best] as Array):
				if used[j] == 0:
					indeg[j] -= 1
		var lane_end: Array = []        # per-lane max y so far (-1e18 = never used)
		var min_lane := PackedInt32Array()
		min_lane.resize(n)
		for idx: int in order:
			var s: Array = spans[idx]
			var lane := -1
			for j2: int in range(int(min_lane[idx]), lane_end.size()):
				if float(lane_end[j2]) + LANE_CLEAR <= float(s[0]):
					lane = j2
					break
			if lane == -1:
				lane = maxi(int(min_lane[idx]), lane_end.size())
				while lane_end.size() <= lane:
					lane_end.append(-1.0e18)
			lane_end[lane] = float(s[1])
			lane_of["%d:%d" % [int(s[5]), int(s[4])]] = lane
			for j3: int in (succ[idx] as Array):
				min_lane[j3] = maxi(int(min_lane[j3]), lane + 1)
		# Distribute lanes across the ACTUAL channel width (varies now: ~60u within a
		# tier, ~200u between tiers), not a fixed CHANNEL_W, so risers pack correctly.
		# Pad is proportional so a tight intra-tier channel isn't eaten by fixed pad.
		var chan_w := col_x(c + 1) - col_x(c) - CARD_W
		lane_gap[c] = clampf((chan_w - 2.0 * _lane_pad(chan_w)) / maxf(1.0, float(lane_end.size())),
			LANE_GAP_MIN, LANE_GAP_MAX)

	# Assemble each edge's axis-aligned waypoint chain.
	for ei: int in range(edges.size()):
		var e: Dictionary = edges[ei]
		var u := str(e["from"])
		var v := str(e["to"])
		var ey: float = exit_y[ei]
		var ty: float = entry_y[ei]
		var pts: Array = []
		pts.append(Vector2(col_x(int(ldepth[u])) + CARD_W * 0.5, ey))
		if chains.has(ei):
			var chain: Array = chains[ei]
			var lx := _lane_x(int(ldepth[u]), int(lane_of["%d:0" % ei]), lane_gap)
			pts.append(Vector2(lx, ey))
			for j: int in range(1, chain.size() - 1):
				var yd: float = hy["%d:%d" % [ei, j]]
				pts.append(Vector2(lx, yd))
				lx = _lane_x(int(ldepth[chain[j]]), int(lane_of["%d:%d" % [ei, j]]), lane_gap)
				pts.append(Vector2(lx, yd))
			pts.append(Vector2(lx, ty))
		else:
			var yb: float = corridor[ei]
			var lx_out := _lane_x(int(ldepth[u]), int(lane_of["%d:0" % ei]), lane_gap)
			var lx_in := _lane_x(int(ldepth[v]) - 1, int(lane_of["%d:1" % ei]), lane_gap)
			pts.append(Vector2(lx_out, ey))
			pts.append(Vector2(lx_out, yb))
			pts.append(Vector2(lx_in, yb))
			pts.append(Vector2(lx_in, ty))
		pts.append(Vector2(col_x(int(ldepth[v])) - CARD_W * 0.5, ty))
		e["waypoints"] = _collapse(pts)


static func _edge_key(e: Dictionary) -> String:
	return str(e["from"]) + ">" + str(e["to"])


## Nudge horizontal runs apart so no two edges overdraw collinearly. Every port stub
## (card edge -> lane, at the port's y) and every dummy-row corridor (lane -> lane,
## at the empty slot's y) is placed greedily — corridors first (they are the rigid
## segments: CORRIDOR_LIMIT keeps them inside their compressed DUMMY_ROW_H slot),
## then the stubs, whose wider PORT_LIMIT band walks around them — trying H_GRID
## clear of every x-overlapping run of another edge (>= H_SEP_SIBLING against stubs
## fanning from the same card side, whose _assign_ports spacing can be < H_SEP by
## design). X-extents are conservative (a run claims its whole channel), which only
## ever nudges a little more than strictly needed. Back-edge bottom corridors sit on
## private below-web rows (BACK_GAP apart) and are skipped. Mutates exit_y /
## entry_y in place; returns "ei:hop" -> corridor y for every dummy hop.
static func _deconflict_horizontals(edges: Array, chains: Dictionary, ldepth: Dictionary,
		ypos: Dictionary, exit_y: Dictionary, entry_y: Dictionary) -> Dictionary:
	# [rank, base_y, x0, x1, from, to, tag, ei, hop, centre_y, side_id]
	# tag: 0 = exit stub, 1 = entry stub, 2 = dummy corridor. Sort keys (first seven
	# elements) are unique per segment, so ordering is deterministic.
	var segs: Array = []
	for ei: int in range(edges.size()):
		var e: Dictionary = edges[ei]
		var u := str(e["from"])
		var v := str(e["to"])
		var du := float(int(ldepth[u]))
		var dv := float(int(ldepth[v]))
		segs.append([1, float(exit_y[ei]), col_x(int(du)) + CARD_W * 0.5,
			col_x(int(du) + 1) - CARD_W * 0.5, u, v, 0, ei, -1, float(ypos[u]), u])
		segs.append([1, float(entry_y[ei]), col_x(int(dv) - 1) + CARD_W * 0.5,
			col_x(int(dv)) - CARD_W * 0.5, u, v, 1, ei, -2, float(ypos[v]), v])
		if chains.has(ei):
			var chain: Array = chains[ei]
			for j: int in range(1, chain.size() - 1):
				var d := int(ldepth[chain[j]])
				segs.append([0, float(ypos[chain[j]]), col_x(d - 1) + CARD_W * 0.5,
					col_x(d + 1) - CARD_W * 0.5, u, v, 2, ei, j, 0.0, ""])
	segs.sort_custom(func(a: Array, b: Array) -> bool: return _key_less(a, b))

	# Conflict prefilter: for each segment, the segments of OTHER edges whose
	# conservative x-extents come within H_CLEAR and whose base y is near enough that
	# any candidate offset could collide. The window derives from the constants —
	# both runs can nudge up to PORT_LIMIT toward each other and still need H_SEP
	# clearance (a stale hardcoded 60 here silently blinded the walk when the card
	# size doubled, landing stubs on unseen corridors).
	var near_window := 2.0 * PORT_LIMIT + H_SEP + H_GRID
	var conflicts: Array = []
	for i: int in range(segs.size()):
		var a: Array = segs[i]
		var near: Array = []
		for j: int in range(segs.size()):
			var b: Array = segs[j]
			if j == i or int(b[7]) == int(a[7]):
				continue
			if float(b[2]) >= float(a[3]) + H_CLEAR or float(a[2]) >= float(b[3]) + H_CLEAR:
				continue
			if absf(float(b[1]) - float(a[1])) < near_window:
				near.append(j)
		conflicts.append(near)

	# Greedy placement: walk candidate offsets outward (0, +-4, +-8, ...) until the
	# run clears every conflicting segment's CURRENT y — final y for already placed
	# segments, base y for pending ones (so a nudge never lands on a spot a later
	# segment starts from). Fallback on exhaustion (never hit on the live catalog) is
	# the base y. Stubs may use the full port band (+-PORT_LIMIT of the card centre);
	# corridors stay within +-CORRIDOR_LIMIT of their empty row slot's centre.
	var final_y: Array = []
	for s: Array in segs:
		final_y.append(float(s[1]))
	var hy: Dictionary = {}
	for i: int in range(segs.size()):
		var s: Array = segs[i]
		var tag := int(s[6])
		var base_y := float(s[1])
		var limit: float = CORRIDOR_LIMIT if tag == 2 else PORT_LIMIT
		var steps := int(limit / H_GRID)
		# Walk candidates outward; accept the first fully clear one. If the band is
		# genuinely too crowded, take the LEAST-BAD candidate (the one maximising the
		# worst clearance deficit) rather than the base y — a near-miss beats a
		# collinear overdraw. Deterministic: ties keep the earlier candidate.
		var placed := false
		var best_cand := base_y
		var best_worst := -INF
		for k: int in range(2 * steps + 1):
			var off := float((k + 1) >> 1) * H_GRID * (1.0 if k % 2 == 1 else -1.0)
			var cand := base_y + off
			if tag != 2 and absf(cand - float(s[9])) > PORT_LIMIT:
				continue
			var worst := INF
			for j: int in conflicts[i]:
				var b: Array = segs[j]
				var sibling: bool = tag != 2 and int(b[6]) == tag and str(b[10]) == str(s[10])
				var need: float = H_SEP_SIBLING if sibling else H_SEP
				worst = minf(worst, absf(float(final_y[j]) - cand) - need)
			if worst >= 0.0:
				final_y[i] = cand
				placed = true
				break
			if worst > best_worst:
				best_worst = worst
				best_cand = cand
		if not placed:
			final_y[i] = best_cand
		if tag == 0:
			exit_y[int(s[7])] = final_y[i]
		elif tag == 1:
			entry_y[int(s[7])] = final_y[i]
		else:
			hy["%d:%d" % [int(s[7]), int(s[8])]] = final_y[i]
	return hy


## Spread one card edge's ports vertically: sorted by adjacent-hop row (then the other
## endpoint's id), evenly stepped, clamped within +/-(CARD_H/2 - PORT_MARGIN).
static func _assign_ports(ports: Array, centre_y: float, out: Dictionary) -> void:
	ports.sort_custom(func(a: Array, b: Array) -> bool: return _key_less(a, b))
	var n := ports.size()
	var step := 0.0
	if n > 1:
		step = minf(PORT_STEP_MAX, (CARD_H - 2.0 * PORT_MARGIN) / float(n - 1))
	for i: int in range(n):
		var port: Array = ports[i]
		out[int(port[2])] = centre_y + (float(i) - float(n - 1) * 0.5) * step


## exit_stub_y / entry_stub_y: the y of this edge's port stub attached to this
## span's left / right end, or _NO_STUB when the end attaches to a corridor —
## the vertical-constraint ordering needs to know which ys are stub crossings.
const _NO_STUB := 1.0e18

static func _add_span(chan_spans: Dictionary, c: int, y0: float, y1: float,
		e: Dictionary, hop: int, ei: int,
		exit_stub_y: float = _NO_STUB, entry_stub_y: float = _NO_STUB) -> void:
	if not chan_spans.has(c):
		chan_spans[c] = []
	(chan_spans[c] as Array).append(
		[minf(y0, y1), maxf(y0, y1), str(e["from"]), str(e["to"]), hop, ei,
			exit_stub_y, entry_stub_y])


## Lane index -> world x inside channel c (the gap right of column c's cards).
static func _lane_x(c: int, lane: int, lane_gap: Dictionary) -> float:
	return col_x(c) + CARD_W * 0.5 + _lane_pad(col_x(c + 1) - col_x(c) - CARD_W) \
		+ float(lane) * float(lane_gap.get(c, LANE_GAP_MAX))


## Lane inset from a card edge, proportional to the channel so a tight intra-tier
## channel keeps room for its risers instead of losing it all to a fixed pad.
static func _lane_pad(chan_w: float) -> float:
	return clampf(chan_w * 0.15, 4.0, LANE_PAD)


## Drop zero-length segments and merge collinear runs; the result is a strict
## axis-aligned polyline (every consecutive pair differs in exactly one axis).
static func _collapse(raw: Array) -> PackedVector2Array:
	var kept: Array = []
	for p: Vector2 in raw:
		if not kept.is_empty() and (kept[kept.size() - 1] as Vector2).is_equal_approx(p):
			continue
		while kept.size() >= 2:
			var a: Vector2 = kept[kept.size() - 2]
			var b: Vector2 = kept[kept.size() - 1]
			if (absf(a.x - b.x) < 0.001 and absf(b.x - p.x) < 0.001) \
					or (absf(a.y - b.y) < 0.001 and absf(b.y - p.y) < 0.001):
				kept.pop_back()
			else:
				break
		kept.append(p)
	var packed := PackedVector2Array()
	packed.resize(kept.size())
	for i: int in range(kept.size()):
		packed[i] = kept[i]
	return packed


static func _display_of(internal: String, goods: Dictionary) -> String:
	return str((goods[internal] as Dictionary).get("display_name", internal))


static func _node_record(internal: String, good: Dictionary, choice: Dictionary,
		producers: Array, tier: int, row: int, pos: Vector2,
		adj: Dictionary, radj: Dictionary, radj_base: Dictionary) -> Dictionary:
	var recipe: Dictionary = choice.get("recipe", {})
	var alt_ids: Array = []
	for r in producers:
		var rid := str(r.get("recipe_id", ""))
		if rid != str(recipe.get("recipe_id", "")):
			alt_ids.append(rid)
	alt_ids.sort()
	return {
		"id": internal,
		"good_id": str(good.get("id", "")),
		"display": str(good.get("display_name", internal)),
		"category": str(good.get("category", "")),
		"good_type": str(good.get("good_type", "")),
		"tier": tier,
		"row": row,
		"pos": pos,
		"half": Vector2(CARD_W, CARD_H) * 0.5,
		"gated": bool(choice.get("gated", false)),
		"recipe_id": str(recipe.get("recipe_id", "")),
		"recipe_name": str(recipe.get("display_name", "")),
		"building_id": str(recipe.get("building_id", "")),
		"alt_recipe_ids": alt_ids,          # phase 2: the zoom/swap candidates
		"inputs": (radj.get(internal, []) as Array).duplicate(),
		# Base-recipe inputs only — the trace's upstream cone walks THESE, so
		# selecting a good lights its canonical chain, not the transitive closure of
		# every alternate route (which pulled in "unrelated" goods, owner 2026-07-18).
		"base_inputs": (radj_base.get(internal, []) as Array).duplicate(),
		"feeds": (adj.get(internal, []) as Array).duplicate(),
	}
