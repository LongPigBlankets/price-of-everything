extends "res://tests/test_base.gd"
## Empire view, goods graph and goods flow views.

const FEATURE := "goods_views"
## Tests that also belong to other features (run under any of their tags).
const TAGS := {
	"_test_flavor_nodes_wired": ["goods_views", "research"],
}

func _node_text_contains(root: Node, needle: String) -> bool:
	if root is Label and needle in str((root as Label).text):
		return true
	if root is Button and needle in str((root as Button).text):
		return true
	for child in root.get_children():
		if _node_text_contains(child, needle):
			return true
	return false

## Goods graph reopen: closing the view while a good is FOCUSED and reopening it used
## to leave the focus animation engaged (_focus_t stuck at 1) while _mode said WEB and
## the camera was framed on the web bbox — cards drew far off-screen and nothing was
## clickable until a search re-entered focus. set_graph must clear the animated focus
## state, not just _mode.
func _test_goods_graph_reopen_clears_focus() -> void:
	var world: Node = load("res://scripts/goods_graph_world.gd").new()
	add_child(world)
	var flow_graph := preload("res://scripts/goods_flow_graph.gd")   # not in the headless global class cache
	var layout: Dictionary = flow_graph.build(false, false)
	world.call("set_graph", layout)
	_check(is_zero_approx(float(world.get("_focus_t"))), "goods graph: a fresh graph starts unfocused")

	# Enter focus the way a click does, then confirm the state really engaged.
	var focus_id := ""
	for nid in (layout.get("by_id", {}) as Dictionary):
		focus_id = str(nid)
		break
	_check(focus_id != "", "goods graph: the layout has a node to focus")
	world.call("select_good", focus_id)
	_check(float(world.get("_focus_target")) > 0.0, "goods graph: selecting a good engages focus")

	# Reopening runs set_graph again — it must land back in a clean web view.
	world.call("set_graph", layout)
	_check(is_zero_approx(float(world.get("_focus_t"))), "goods graph: reopening clears the focus animation")
	_check(is_zero_approx(float(world.get("_focus_target"))), "goods graph: reopening clears the focus target")
	_check((world.get("_fpos") as Dictionary).is_empty(), "goods graph: reopening drops the stale focus positions")
	_check(str(world.get("_selected_id")) == "", "goods graph: reopening clears the selection")
	world.queue_free()

## ============================================================================
## ADVERSARIAL PINS - gauntlet6/gameit constructions, gauntlet7/repair verdicts
## ============================================================================
## Each block below is the EXACT construction that broke a gauntlet6 instrument,
## kept verbatim, with the assertion INVERTED to the repaired verdict. The
## constructions are the permanent regression surface: a future candidate that
## reopens one of these breaks fails here before it reaches a blind critic.
## Runnable narrative form: tools/instrument_attack.gd.

func _test_encyclopedia_good_rubric() -> void:
	var overlay = load("res://scripts/search_overlay.gd").new()
	var aluminium_id := str(Catalog.get_good_by_internal_name("aluminium").get("id", ""))
	_check(aluminium_id != "", "encyclopedia rubric: aluminium exists in the goods catalog")
	var entry: Control = overlay._make_good_recipes_entry({
		"type": "good", "id": aluminium_id, "title": "Aluminium",
		"payload": Catalog.get_good(aluminium_id),
	})
	var rubric := entry.find_child("GoodRubricCard", true, false)
	var rubric_row := entry.find_child("GoodRubricRow", true, false)
	var recipe_columns := entry.find_child("GoodRecipeColumns", true, false)
	_check(rubric != null and rubric_row != null and recipe_columns != null
		and rubric_row.get_index() < recipe_columns.get_index(),
		"encyclopedia rubric: top-right details sit above both recipe columns")
	_check(_node_text_contains(rubric, "Market price")
		and _node_text_contains(rubric, "Buy price")
		and _node_text_contains(rubric, "Transport class")
		and _node_text_contains(rubric, "Carbon tax / unit"),
		"encyclopedia rubric: price, type, transport and current carbon figures are present")
	var roads := rubric.find_child("GoodTransport_roads", true, false)
	var rail := rubric.find_child("GoodTransport_rail", true, false)
	var pipes := rubric.find_child("GoodTransport_pipes", true, false)
	var reinforced := rubric.find_child("GoodTransport_reinf_pipes", true, false)
	_check(roads != null and rail != null and not _node_text_contains(roads, "Not supported")
		and not _node_text_contains(rail, "Not supported"),
		"encyclopedia rubric: aluminium supports roads and rail")
	_check(pipes != null and reinforced != null and _node_text_contains(pipes, "Not supported")
		and _node_text_contains(reinforced, "Not supported"),
		"encyclopedia rubric: aluminium rejects pipework and reinforced pipework")
	entry.free()
	overlay.free()

# Goods Graph data builder (scripts/goods_flow_graph.gd): the runtime goods web is
# complete, joins only known goods, is defined by game-start recipes (gated flag
# honest), and lays out deterministically (CLAUDE.md #3).
func _test_goods_flow_graph() -> void:
	var GoodsFlowGraph := preload("res://scripts/goods_flow_graph.gd")
	var g: Dictionary = GoodsFlowGraph.build()
	var nodes: Array = g["nodes"]
	var by_id: Dictionary = g["by_id"]
	var edges: Array = g["edges"]
	# VISIBLE goods, not the whole catalogue: the recycling chain is gated out of the demo,
	# and a graph node for a good the player can never see or make is a dead end.
	_check(nodes.size() == MatchState.visible_goods().size(),
		"goods graph: one node per visible good (%d)" % nodes.size())
	var ok_edges := not edges.is_empty()
	for e in edges:
		if not (by_id.has(str(e["from"])) and by_id.has(str(e["to"]))):
			ok_edges = false
	_check(ok_edges, "goods graph: every edge joins two known goods (%d edges)" % edges.size())
	_check(int(g["tier_count"]) >= 4, "goods graph: web layers into >=4 tiers (%d)" % int(g["tier_count"]))
	# Tiers layer on the BASE skeleton; alternates (e.g. recycling routes) may feed a
	# tier-0 raw good, so only route-0 edges must never target tier 0.
	var t0_clean := true
	for e in edges:
		if int(e.get("route", 0)) == 0 and int(by_id.get(str(e["to"]), {}).get("tier", -1)) == 0:
			t0_clean = false
	_check(t0_clean, "goods graph: tier-0 goods take no BASE-route inputs")
	_check(int(by_id.get("coal", {}).get("tier", -1)) == 0, "goods graph: coal is a tier-0 source")
	var steel: Dictionary = by_id.get("steel", {})
	_check(int(steel.get("tier", -1)) >= 1 and (steel.get("inputs", []) as Array).size() >= 1,
		"goods graph: steel sits deeper with inputs")
	var base_ok := true
	for n in nodes:
		var rid := str(n.get("recipe_id", ""))
		if rid == "":
			continue
		var r: Dictionary = Catalog.get_recipe(rid)
		if bool(n["gated"]) != (str(r.get("tech_unlock_req", "")) != ""):
			base_ok = false
	_check(base_ok, "goods graph: defining recipes are game-start unless flagged gated")
	# Owner ask 2026-07-18: the semiconductor chain is visible at game start —
	# polysilicon -> high_grade_silicon (r_229) -> cpu (r_230, 3 inputs so it wins
	# the simplest-base pick over r_122's 4) -> computer.
	var hgs: Dictionary = by_id.get("high_grade_silicon", {})
	_check(str(hgs.get("recipe_id", "")) == "r_229" and (hgs.get("inputs", []) as Array).has("polysilicon"),
		"goods graph: high_grade_silicon is made from polysilicon (r_229)")
	var cpu: Dictionary = by_id.get("cpu", {})
	_check(str(cpu.get("recipe_id", "")) == "r_230" and (cpu.get("inputs", []) as Array).has("high_grade_silicon"),
		"goods graph: cpu's defining base route consumes high_grade_silicon (r_230)")
	# Power union: fuel-less wind is the simplest producer, but the edges must still
	# carry every game-start fuel route (coal, processed_oil, pet_coke).
	var power: Dictionary = by_id.get("power", {})
	var power_inputs: Array = power.get("inputs", [])
	# Coal (r_004) and processed_oil (r_181) are start-unlocked; pet_coke's only route
	# (r_151) moved behind "Combined Cycle Turbines" on 2026-07-28, so it is no longer a
	# game-start edge.
	_check(power_inputs.has("coal") and power_inputs.has("processed_oil"),
		"goods graph: power carries the game-start fuel edges (coal, processed_oil)")
	_check(not power_inputs.has("pet_coke"),
		"goods graph: pet_coke is NOT a start edge — it is gated behind Combined Cycle Turbines")
	# The focused card alone carries a compact transport row: solids use road/rail,
	# fluids add their one preferred pipe type, and power uses only cables.
	var GoodsGraphWorld := preload("res://scripts/goods_graph_world.gd")
	var motor_gid := str(Catalog.get_good_by_internal_name("motor").get("id", ""))
	var hydrogen_gid := str(Catalog.get_good_by_internal_name("hydrogen").get("id", ""))
	var water_gid := str(Catalog.get_good_by_internal_name("pure_water").get("id", ""))
	var motor_transport: Array = GoodsGraphWorld.focused_transport_infrastructure_keys(motor_gid)
	var hydrogen_transport: Array = GoodsGraphWorld.focused_transport_infrastructure_keys(hydrogen_gid)
	var water_transport: Array = GoodsGraphWorld.focused_transport_infrastructure_keys(water_gid)
	var power_transport: Array = GoodsGraphWorld.focused_transport_infrastructure_keys(
		str(power.get("good_id", "")), str(power.get("good_type", "")))
	_check(motor_transport == ["roads", "rails"],
		"goods graph focus: a solid shows road and rail transport")
	_check(hydrogen_transport == ["roads", "rails", "reinf_pipes"],
		"goods graph focus: hydrogen adds reinforced pipework as the third icon")
	_check(water_transport == ["roads", "rails", "pipes"],
		"goods graph focus: a safe fluid adds ordinary pipework, capped at three icons")
	_check(power_transport == ["cables"],
		"goods graph focus: power shows cables only")
	var InfraIcons := preload("res://scripts/infra_icons.gd")
	var focus_infra_art_ok := true
	for infra_key in ["roads", "rails", "pipes", "reinf_pipes", "cables"]:
		var infra_building: Dictionary = Catalog.get_building_by_internal_name(infra_key)
		if InfraIcons.texture_for(str(infra_building.get("id", "")), infra_key) == null:
			focus_infra_art_ok = false
	_check(focus_infra_art_ok,
		"goods graph focus: every transport option resolves its existing infrastructure icon")
	# Owner 2026-07-19: r_231 Anthracite Graphitisation (45 coal -> 2 graphite,
	# 160 MW, ungated) is graphite's SIMPLEST base route (1 input, lower energy than
	# pet-coke calcination), so the web edge is coal; pet-coke and the gated bio
	# route live in the alternates grid.
	var graphite: Dictionary = by_id.get("graphite", {})
	_check(str(graphite.get("recipe_id", "")) == "r_231"
		and (graphite.get("inputs", []) as Array).has("coal")
		and not (graphite.get("inputs", []) as Array).has("carbonised_biomass"),
		"goods graph: graphite's base route is Anthracite Graphitisation (coal)")
	var graphite_routes: Array = GoodsFlowGraph.routes_for_good("graphite")
	var has_bio := false
	for gr in graphite_routes:
		if str((gr.get("recipe", {}) as Dictionary).get("recipe_id", "")) == "r_042":
			has_bio = bool(gr.get("gated", false))
	_check(has_bio, "goods graph: grid routes for graphite include gated Bio-Graphitisation (r_042)")
	var steel_routes: Array = GoodsFlowGraph.routes_for_good("steel")
	_check(steel_routes.size() >= 2 and str((steel_routes[0].get("recipe", {}) as Dictionary).get("recipe_id", ""))
		== str(by_id.get("steel", {}).get("recipe_id", "")),
		"goods graph: grid routes are defining-first (steel, %d routes)" % steel_routes.size())
	var all_base := true
	var has_gated_dash := false
	for e in edges:
		if int(e.get("route", 0)) != 0:
			all_base = false
		if bool(e.get("route_gated", false)):
			has_gated_dash = true
	_check(all_base and has_gated_dash,
		"goods graph: web edges are all base-route; gated-only goods still dash")
	# Owner 2026-07-19: plain-substring good search (min 3 letters), position-ranked.
	var hits: Array = GoodsFlowGraph.search_goods("ste", nodes)
	_check(not hits.is_empty() and str((hits[0] as Dictionary).get("display", "")) == "Steel",
		"goods graph: search 'ste' ranks Steel first (%d hits)" % hits.size())
	_check(GoodsFlowGraph.search_goods("st", nodes).is_empty(),
		"goods graph: search needs at least 3 letters")
	_check(GoodsFlowGraph.search_goods("polysil", nodes).size() == 1,
		"goods graph: search 'polysil' matches exactly one good (Enter auto-picks)")
	# Authored bands (goods_graph_tier): every good carries a valid band, and no
	# base-route edge flows from a later band to an earlier one (the zero-backward
	# invariant the banding was designed around).
	var band_index: Dictionary = {}
	for bi in range(GoodsFlowGraph.TIER_BANDS.size()):
		band_index[GoodsFlowGraph.TIER_BANDS[bi]] = bi
	var bands_ok := true
	var good_band: Dictionary = {}
	for good in Catalog.all_goods():
		var bv := str(good.get("goods_graph_tier", ""))
		good_band[str(good.get("internal_name", ""))] = bv
		if not band_index.has(bv):
			bands_ok = false
	_check(bands_ok, "goods graph: every good has a valid goods_graph_tier band")
	var no_backward := true
	for e in edges:
		if int(band_index.get(good_band.get(str(e["to"]), ""), 0)) 				< int(band_index.get(good_band.get(str(e["from"]), ""), 0)):
			no_backward = false
	_check(no_backward, "goods graph: no base edge flows backward across bands")
	# Owner rule 2026-07-22: a Recycling recipe can never be the base — steel's
	# base is Steelmaking (iron_ingots + coal), with Scrap Recycling an alternate.
	var steel_base_srcs: Array = []
	for e in edges:
		if str(e["to"]) == "steel" and int(e.get("route", 0)) == 0:
			steel_base_srcs.append(str(e["from"]))
	_check(steel_base_srcs.has("iron_ingots") and steel_base_srcs.has("coal")
		and not steel_base_srcs.has("scrap"),
		"goods graph: steel base = iron_ingots+coal, never scrap (recycling rule)")
	_check((g.get("bands", []) as Array).size() == 5,
		"goods graph: five labelled band regions")
	# build() caches (world_map warms it under the loading screen); force=true recomputes
	# independently, so this both keeps the determinism check meaningful AND verifies the
	# cached layout equals a fresh build.
	var g2: Dictionary = GoodsFlowGraph.build(true)
	var sig := func(gr: Dictionary) -> String:
		var parts := ""
		for n in gr["nodes"]:
			parts += "%s@%s;" % [str(n["id"]), str(n["pos"])]
		return parts + str(gr["edges"])   # edge dicts embed their waypoints
	_check(sig.call(g) == sig.call(g2), "goods graph: build is deterministic (cache == fresh)")
	# Orthogonal routing: every edge is an axis-aligned waypoint chain; vertical lane
	# runs of different edges that share y-range keep clear x separation; horizontal
	# runs of different edges that share x-range never sit collinear (>= the sibling
	# port-fan spacing H_SEP_SIBLING); and the final bilayer crossing count is
	# bounded (and visible in the PASS name).
	#
	# THE SEPARATION FLOORS ARE MEASURED ON THE LEGACY LAYOUT, because that is the only
	# presentation that still DRAWS resting web edges (the debug `legacy goods graph`
	# toggle). The default presentation stopped drawing them, and its dummy rows —
	# corridors that existed to hold those edges apart — were collapsed so the swimlane
	# bands could tighten around the cards. Asserting a pixel floor there would be
	# asserting the geometry of lines nobody renders; the invariants that DO matter for
	# it are checked separately below.
	var legacy: Dictionary = GoodsFlowGraph.build(true, true)
	var legacy_edges: Array = legacy.get("edges", [])
	var ortho := true
	var verts: Array = []   # [x, y_lo, y_hi, edge_index]
	var horiz: Array = []   # [y, x_lo, x_hi, edge_index]
	for ei: int in range(legacy_edges.size()):
		var wp: PackedVector2Array = (legacy_edges[ei] as Dictionary).get("waypoints", PackedVector2Array())
		if wp.size() < 2:
			ortho = false
			continue
		for i: int in range(wp.size() - 1):
			var a := wp[i]
			var b := wp[i + 1]
			var dx := absf(a.x - b.x)
			var dy := absf(a.y - b.y)
			if dx > 0.01 and dy > 0.01:
				ortho = false
			if dx <= 0.01 and dy > 0.01:
				verts.append([a.x, minf(a.y, b.y), maxf(a.y, b.y), ei])
			if dy <= 0.01 and dx > 0.01:
				horiz.append([a.y, minf(a.x, b.x), maxf(a.x, b.x), ei])
	_check(ortho, "goods graph: every legacy edge is an axis-aligned waypoint chain (>=2 points)")
	var sep_ok := true
	for i: int in range(verts.size()):
		for j: int in range(i + 1, verts.size()):
			var a: Array = verts[i]
			var b: Array = verts[j]
			if int(a[3]) == int(b[3]):
				continue
			var overlap: bool = maxf(float(a[1]), float(b[1])) < minf(float(a[2]), float(b[2])) - 0.01
			if overlap and absf(float(a[0]) - float(b[0])) < 11.9:
				sep_ok = false
	_check(sep_ok, "goods graph (legacy): y-overlapping vertical runs sit >=11.9 units apart")
	var hsep_ok := true
	for i: int in range(horiz.size()):
		for j: int in range(i + 1, horiz.size()):
			var a: Array = horiz[i]
			var b: Array = horiz[j]
			if int(a[3]) == int(b[3]):
				continue
			var overlap: bool = maxf(float(a[1]), float(b[1])) < minf(float(a[2]), float(b[2])) - 0.01
			if overlap and absf(float(a[0]) - float(b[0])) < 5.9:
				hsep_ok = false
	_check(hsep_ok, "goods graph (legacy): x-overlapping horizontal runs sit >=5.9 units apart (owner floor: 5 px at max zoom 1.0)")
	# The swimlane bands: sized by CARDS, with each (column, lane) cell's cards packed
	# contiguously and centred in its band. This is what replaced the pixel floors above
	# for the default presentation — the bands used to be sized to fit edge corridors,
	# which is why they were tall and why a cell's cards sat scattered inside one.
	var lanes: Array = g.get("lanes", [])
	var by_lane_col: Dictionary = {}   # "lane_top:col_x" -> [card centre ys]
	for n in g.get("nodes", []):
		var node: Dictionary = n
		var pos: Vector2 = node["pos"]
		for lane in lanes:
			var top := float((lane as Dictionary)["top"])
			var h := float((lane as Dictionary)["height"])
			if pos.y >= top - 1.0 and pos.y <= top + h + 1.0:
				var k := "%f:%f" % [top, pos.x]
				var ys: Array = by_lane_col.get(k, [])
				ys.append(pos.y)
				by_lane_col[k] = ys
				break
	var packed_ok := true
	var centred_ok := true
	var checked := 0
	for k in by_lane_col:
		var ys: Array = by_lane_col[k]
		if ys.size() < 2:
			continue
		ys.sort()
		checked += 1
		# Contiguous: consecutive cards in a cell sit exactly one ROW_H apart.
		for i: int in range(ys.size() - 1):
			if absf(float(ys[i + 1]) - float(ys[i]) - GoodsFlowGraph.ROW_H) > 0.51:
				packed_ok = false
	for lane in lanes:
		var top := float((lane as Dictionary)["top"])
		var h := float((lane as Dictionary)["height"])
		var mid := top + h * 0.5
		for k2 in by_lane_col:
			if not str(k2).begins_with("%f:" % top):
				continue
			var ys2: Array = by_lane_col[k2]
			ys2.sort()
			# Centred: the card block's own midpoint sits on the band's midpoint.
			var block_mid := (float(ys2[0]) + float(ys2[ys2.size() - 1])) * 0.5
			if absf(block_mid - mid) > 0.51:
				centred_ok = false
	_check(checked > 0, "goods graph: swimlane cells found to check (%d multi-card cells)" % checked)
	_check(packed_ok, "goods graph: a cell's cards are packed contiguously (one ROW_H apart)")
	_check(centred_ok, "goods graph: a cell's card block is centred in its swimlane band")
	# A band is exactly as tall as the most cards any one column puts in it — no corridor
	# padding. Anything taller means dummy rows have crept back into the band sizing.
	var band_sizing_ok := true
	for lane in lanes:
		var top := float((lane as Dictionary)["top"])
		var h := float((lane as Dictionary)["height"])
		var tallest := 0
		for k3 in by_lane_col:
			if str(k3).begins_with("%f:" % top):
				tallest = maxi(tallest, (by_lane_col[k3] as Array).size())
		if tallest > 0 and absf(h - float(tallest) * GoodsFlowGraph.ROW_H) > 0.51:
			band_sizing_ok = false
	_check(band_sizing_ok, "goods graph: each band is exactly its tallest cell's cards tall")
	var crossings := int(g.get("crossings", -1))
	# Canary re-baselined 2026-07-22: the 9-lane category swimlanes constrain the
	# ordering (crossing-minimisation only runs within a lane cell), measured 1032
	# vs 816 under 6 lanes / 638 unconstrained. Crossings are a regression tripwire,
	# not a visual floor — the resting web renders at ghost alpha.
	_check(crossings >= 0 and crossings < 1400,
		"goods graph: %d crossings after ordering (< 1400 canary; swimlane-constrained)" % crossings)

func _test_flavor_nodes_wired() -> void:
	# The 41 wired flavor nodes register real modifiers on unlock, one per domain.
	Modifiers.reset()
	MatchState.reset()
	# recipe_output: Fractional Distillation → +5% Petrochemical Refinery (b_011).
	ResearchState.grant_unlock("Fractional Distillation")
	_check(absf(Modifiers.apply("recipe_output", "x", 100.0, {"building_id": "b_011"}) - 105.0) < 0.001,
		"Fractional Distillation wires +5% petro-refinery output")
	# building_power: Flue Heat Recovery → −10% Coal Power Plant (b_003) power draw.
	ResearchState.grant_unlock("Flue Heat Recovery")
	_check(absf(Modifiers.apply("building_power", "b_003", 100.0, {"building_id": "b_003"}) - 90.0) < 0.001,
		"Flue Heat Recovery wires −10% coal-plant power")
	# labour: Safety Training → −5% labour on ALL buildings (empty target_match).
	ResearchState.grant_unlock("Safety Training")
	_check(absf(Modifiers.apply("labour_headcount", "b_999", 100.0, {"building_id": "b_999"}) - 95.0) < 0.001,
		"Safety Training wires −5% labour empire-wide")
	# maintenance: Grid Synchronous Generation → −8% on each power plant (array spec).
	# Safety Training also supplies a global −5% maintenance effect, so assert Grid's
	# own additive eight percentage-point contribution rather than a solo total.
	var maintenance_before_grid: float = Modifiers.apply("maintenance", "b_024", 100.0, {"building_id": "b_024"})
	ResearchState.grant_unlock("Grid Synchronous Generation")
	_check(absf(Modifiers.apply("maintenance", "b_024", 100.0, {"building_id": "b_024"}) - (maintenance_before_grid - 8.0)) < 0.001,
		"Grid Synchronous Generation adds −8% maintenance on a power plant (solar)")
	# market_price: Forward Contracts → +5% sale price on EVERY good (owner 2026-09-06;
	# was steel-only for 20 turns). An empty target_match matches all goods.
	ResearchState.grant_unlock("Forward Contracts")
	_check(absf(Modifiers.apply("market_price", "gid", 10.0, {"good_internal": "steel"}) - 10.5) < 0.001,
		"Forward Contracts wires +5% steel sale price")
	_check(absf(Modifiers.apply("market_price", "gid", 10.0, {"good_internal": "coal"}) - 10.5) < 0.001,
		"Forward Contracts is empire-wide: coal gets the same +5%")
	# transport_throughput: Route Optimization → +25% road capacity.
	ResearchState.grant_unlock("Route Optimization")
	_check(absf(Modifiers.apply("transport_throughput", "roads", 100.0, {"mode": "roads"}) - 125.0) < 0.001,
		"Route Optimization wires +25% road throughput")
	Modifiers.reset()
	MatchState.reset()

# Empire view node packing (scripts/empire_layout.gd): the >=30px gap holds, packing is
# deterministic, coincident seeds (same tile) fan out, and all nodes survive.
func _test_empire_layout() -> void:
	var EL := load("res://scripts/empire_layout.gd")
	var make := func(iid: String, seed_pos: Vector2, lvl: int) -> Dictionary:
		return {"iid": iid, "seed": seed_pos, "half": Vector2(80, 46) * EL.level_scale(lvl), "level": lvl}
	var spec := [
		["a", Vector2(0, 0), 1], ["b", Vector2(0, 0), 2],        # b coincident with a
		["c", Vector2(10, 5), 3], ["d", Vector2(400, 0), 1],
		["e", Vector2(420, 20), 1], ["f", Vector2(-300, 200), 1],
	]
	var build_nodes := func() -> Array:
		var arr: Array = []
		for s in spec:
			arr.append(make.call(s[0], s[1], s[2]))
		return arr

	var nodes: Array = build_nodes.call()
	EL.relax(nodes)
	_check(nodes.size() == 6, "empire layout: all nodes retained (%d)" % nodes.size())
	_check(EL.gap_satisfied(nodes), "empire layout: every pair keeps the >=30px gap")

	# Coincident seeds a & b must have separated.
	var pos := {}
	for n in nodes:
		pos[n["iid"]] = n["pos"]
	_check((pos["a"] as Vector2).distance_to(pos["b"]) > 30.0, "empire layout: coincident seeds fan out")

	# Determinism: a fresh run yields identical positions.
	var nodes2: Array = build_nodes.call()
	EL.relax(nodes2)
	var same := true
	for n in nodes2:
		if (pos[n["iid"]] as Vector2).distance_to(n["pos"]) > 0.0001:
			same = false
	_check(same, "empire layout: deterministic (same input -> same output)")

# Layered supply-chain layout (scripts/empire_layout.gd solve): a producer feeding a consumer is
# placed in an earlier column (input sources sit left of their consumers), and the gap still holds.
func _test_empire_layered() -> void:
	var EL := load("res://scripts/empire_layout.gd")
	var mk := func(iid: String) -> Dictionary:
		return {"iid": iid, "seed": Vector2.ZERO, "half": Vector2(80, 46), "level": 1}
	var nodes: Array = [mk.call("a"), mk.call("b"), mk.call("c"), mk.call("iso")]
	var edges: Array = [{"from": "a", "to": "b"}, {"from": "b", "to": "c"}]   # a -> b -> c chain
	EL.solve(nodes, edges)
	var px := {}
	for n in nodes:
		px[n["iid"]] = (n["pos"] as Vector2).x
	_check(px["a"] < px["b"] and px["b"] < px["c"], "empire layered: input sources sit left of their consumers")
	_check(EL.gap_satisfied(nodes), "empire layered: >=30px gap held after layered solve")
	_check(nodes.size() == 4, "empire layered: isolated node retained alongside the chain")

# The occupancy registry (scripts/empire_occupancy.gd): what counts as a collision. A route
# may touch the two nodes it connects and nothing else; chips and sprites never share space;
# two routes never count against each other; the layout's gutters grow with lane demand.
func _test_empire_occupancy() -> void:
	var EO := load("res://scripts/empire_occupancy.gd")
	var occ = EO.new()
	occ.add_rect("sprite", "a", Rect2(0, 0, 100, 100))
	occ.add_rect("plate", "a", Rect2(0, 100, 100, 40))
	occ.add_rect("sprite", "b", Rect2(300, 0, 100, 100))
	occ.add_rect("plate", "b", Rect2(300, 100, 100, 40))
	occ.add_path("route", "a|b", PackedVector2Array([Vector2(100, 120), Vector2(300, 120)]), 2.0, ["a", "b"])
	occ.add_rect("chip", "chip|input|a|g", Rect2(180, 100, 40, 40), ["a", "b", "a|b"])
	var rep: Dictionary = occ.report()
	_check(int(rep["total"]) == 0, "empire occupancy: a route between its own endpoints and a chip on it are not collisions")
	occ.add_rect("sprite", "c", Rect2(150, 80, 60, 60))
	rep = occ.report()
	_check(int((rep["counts"] as Dictionary).get("route|sprite", 0)) == 1, "empire occupancy: a line through a third node's sprite is one route|sprite collision")
	_check(int((rep["counts"] as Dictionary).get("chip|sprite", 0)) == 1, "empire occupancy: a chip on that sprite is one chip|sprite collision")
	occ.add_path("route", "b|c", PackedVector2Array([Vector2(200, 0), Vector2(200, 200)]), 2.0, ["b", "c"])
	rep = occ.report()
	_check(int((rep["counts"] as Dictionary).get("route|route", 0)) == 0, "empire occupancy: crossing lines are not counted (that is the lane solver's metric)")
	_check(EO.seg_hits_rect(Vector2(-10, 50), Vector2(110, 50), Rect2(0, 0, 100, 100)), "empire occupancy: a segment through a rect hits")
	_check(not EO.seg_hits_rect(Vector2(-10, 150), Vector2(110, 150), Rect2(0, 0, 100, 100)), "empire occupancy: a segment past a rect misses")
	var EL := load("res://scripts/empire_layout.gd")
	_check(EL.gutter_width(0) == EL.MIN_GUTTER, "empire gutters: no lines = the minimum gutter")
	_check(EL.gutter_width(6) > EL.gutter_width(1) and EL.gutter_width(1) > EL.MIN_GUTTER, "empire gutters: the gutter grows with the lines crossing it")
	_check(EL.row_gap_before({"top_extra": 300.0}) > EL.ROW_GAP, "empire gutters: a plume above a node widens the row gap under its neighbour")
	# Demand shows in the layout: two producers feeding one consumer put more gutter between
	# the columns than a lone pair does.
	var mk := func(iid: String) -> Dictionary:
		return {"iid": iid, "seed": Vector2.ZERO, "half": Vector2(80, 46), "level": 1}
	var lone: Array = [mk.call("p"), mk.call("q")]
	EL.solve(lone, [{"from": "p", "to": "q"}])
	var busy: Array = [mk.call("p"), mk.call("p2"), mk.call("p3"), mk.call("p4"), mk.call("q")]
	EL.solve(busy, [{"from": "p", "to": "q"}, {"from": "p2", "to": "q"}, {"from": "p3", "to": "q"}, {"from": "p4", "to": "q"}])
	var gap_lone: float = (lone[1]["pos"] as Vector2).x - (lone[0]["pos"] as Vector2).x
	var gap_busy: float = (busy[4]["pos"] as Vector2).x - (busy[0]["pos"] as Vector2).x
	_check(gap_busy > gap_lone, "empire gutters: four lines into one consumer open a wider column gap than one line (%.0f vs %.0f)" % [gap_busy, gap_lone])


# Ports always read left -> right as Stoneshore, Arin, Vandel, Capital (scripts/empire_graph.gd).
func _test_empire_ports() -> void:
	var EG := load("res://scripts/empire_graph.gd")
	_check(EG._port_order("Stoneshore Docks") == 0, "empire ports: Stoneshore is leftmost")
	_check(EG._port_order("Arin Estuary Docks") == 1, "empire ports: Arin is second")
	_check(EG._port_order("Vandel's Skip") == 2, "empire ports: Vandel is third")
	_check(EG._port_order("Capital Port") == 3, "empire ports: Capital is last of the four")
	_check(EG._port_order("Mystery Harbour") == 4, "empire ports: unknown ports sort after the known four")

# The 6 RAG indicators come from ONE shared function (building_status.gd), used by both the detail
# panel and the Empire view — this locks its contract (count, order, Color-typed) against drift.
func _test_empire_rag() -> void:
	var BS := load("res://scripts/building_status.gd")
	var recs: Array = Catalog.get_recipes_for_building("b_001")
	var recipe: Dictionary = recs[0] if recs.size() > 0 else {"recipe_id": "", "inputs": [], "outputs": []}
	var building := {"instance_id": "rag_probe", "building_id": "b_001", "recipe_id": str(recipe.get("recipe_id", "")), "tile_id": "tile_0_0", "level": 1}
	var rag: Array = BS.rag_indicators(building, recipe, false)
	_check(rag.size() == 6, "empire rag: six indicators returned (%d)" % rag.size())
	var keys: Array = []
	var all_colors := true
	for r in rag:
		keys.append(str(r.get("key", "")))
		if not (r.get("color") is Color):
			all_colors = false
	_check(keys == ["power", "input", "duration", "cost", "produce_cost", "modifier"], "empire rag: keys in detail-panel order")
	_check(all_colors, "empire rag: every indicator carries a Color")

## The supply chain board's model: the street plan every tile shares, and how a route becomes hops.
func _test_empire_board_model() -> void:
	var Model := preload("res://scripts/empire_board_model.gd")
	var Streets := preload("res://scripts/empire_board_streets.gd")
	var hexp := Model.hex_points(Vector2.ZERO)
	_check(Streets.SLOTS.size() == 10, "board: a tile has ten slots around its warehouse")
	var inside := true
	var apart := true
	var half := Streets.SLOT_SIDE * 0.5
	for i in range(Streets.SLOTS.size()):
		var c: Vector2 = Streets.SLOTS[i]
		for corner in [Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)]:
			inside = inside and Geometry2D.is_point_in_polygon(c + corner, hexp)
		apart = apart and (absf(c.x) >= half + Streets.HUB_SIDE * 0.5 or absf(c.y) >= half + Streets.HUB_SIDE * 0.5)
		for j in range(i + 1, Streets.SLOTS.size()):
			var d: Vector2 = (Streets.SLOTS[j] as Vector2) - c
			apart = apart and (absf(d.x) >= Streets.SLOT_SIDE or absf(d.y) >= Streets.SLOT_SIDE)
	_check(inside, "board: every slot lies wholly on its tile")
	_check(apart, "board: no slot overlaps another or the warehouse")
	_check(Streets.SLOT_SIDE * Streets.SLOT_SIDE <= 0.05 * 194400.0, "board: a slot is at most a twentieth of a tile")
	# Every slot's door reaches the warehouse's along the streets, and no street runs through a slot.
	var hub: String = Streets.nid(Streets.hub_door())
	var reached := true
	var clear := true
	for i in range(Streets.SLOTS.size()):
		var ids: Array = Streets.path(Streets.nid(Streets.slot_door(i)), hub)
		reached = reached and ids.size() >= 2 and str(ids[ids.size() - 1]) == hub
		for n in range(1, ids.size()):
			var mid: Vector2 = (Streets.node_pos(str(ids[n - 1])) + Streets.node_pos(str(ids[n]))) * 0.5
			for s in Streets.SLOTS:
				clear = clear and not (absf(mid.x - (s as Vector2).x) < half - 0.5 and absf(mid.y - (s as Vector2).y) < half - 0.5)
	_check(reached, "board: every slot's spur leads to the warehouse along the streets")
	_check(clear, "board: no street runs through a slot")
	# Two neighbouring tiles meet at one point on their shared edge, whichever side asks.
	var meets := true
	for off in [Vector2(0.0, 480.0), Vector2(0.0, -480.0), Vector2(405.0, 240.0), Vector2(-405.0, 240.0),
			Vector2(405.0, -240.0), Vector2(-405.0, -240.0)]:
		var here: Vector2 = Streets.exit_point(off)
		var there: Vector2 = Streets.exit_point(-off)
		meets = meets and here != Vector2.ZERO and here.is_equal_approx(off + there) \
			and Streets.has_node(Streets.nid(here)) and Streets.is_exit(here)
	_check(meets, "board: neighbouring tiles' roads meet at the same point on their shared edge")
	_check(Streets.exit_point(Vector2(810.0, 0.0)) == Vector2.ZERO, "board: a tile that is not a neighbour has no exit")
	# Through traffic keeps to the front street: from one front corner to the other it never
	# touches the back street, though going round the back is no longer.
	var west: String = Streets.nid(Streets.exit_point(Vector2(-405.0, 240.0)))
	var east: String = Streets.nid(Streets.exit_point(Vector2(405.0, 240.0)))
	var front := true
	for id in Streets.path(west, east):
		front = front and Streets.node_pos(str(id)).y > 0.0
	_check(front, "board: traffic along the front of a tile stays on the front street")
	# One avenue joins the two streets, right of the warehouse. The gap left of it is the
	# pipes' and the railway's, and no road runs there.
	var back_west: String = Streets.nid(Streets.exit_point(Vector2(-405.0, -240.0)))
	var by_avenue := false
	var in_gap := false
	var across: Array = Streets.path(back_west, west)
	for n in range(1, across.size()):
		var p0: Vector2 = Streets.node_pos(str(across[n - 1]))
		var p1: Vector2 = Streets.node_pos(str(across[n]))
		if absf(p0.x - p1.x) < 0.5 and absf(p0.y) <= Streets.STREET_Y + 0.5 and absf(p1.y) <= Streets.STREET_Y + 0.5 \
				and absf(p0.y - p1.y) > Streets.STREET_Y:
			by_avenue = by_avenue or absf(p0.x - Streets.AVENUE_X) < 0.5
			in_gap = in_gap or p0.x < 0.0
	_check(by_avenue and not in_gap, "board: a road crosses between the streets by the one avenue, never by the pipes' gap")
	_check(Streets.pipe_point(Vector2.ZERO).x == Streets.PIPE_TRUNK_X and Streets.pipe_point(Streets.SLOTS[1]).x == Streets.PIPE_TRUNK_X,
		"board: a building beside the trunk takes its pipes straight off it")
	_check(Streets.places(10).size() == 10 and Streets.places(11).size() == 40
		and float(Streets.places(11)[0]["side"]) < Streets.SLOT_SIDE,
		"board: an eleventh building splits the slots into quarters")
	# Two legs over four tiles: each tile pair takes the mode of the leg that covers it.
	var hops: Array = Model.route_hops({
		"tiles": ["a", "b", "c", "d"],
		"legs": [{"mode": "rail", "from": "a", "to": "c"}, {"mode": "roads", "from": "c", "to": "d"}],
	})
	_check(hops.size() == 3 and str(hops[0]["mode"]) == "rail" and str(hops[1]["mode"]) == "rail"
		and str(hops[2]["mode"]) == "roads" and str(hops[2]["a"]) == "c",
		"board: a route's hops carry the mode of their own leg")


## The board's tile heights settled: never more than the cap above a neighbour, never above the tile upstream on
## a river; a river that would climb raises the land it comes from rather than lowering the high ground.
func _test_empire_board_relief_settle() -> void:
	var Relief := preload("res://scripts/empire_board_relief.gd")
	_check(Relief.band_level(2) == 34.0 and Relief.band_level(4) == 66.0 and Relief.band_level(7) == 99.0,
		"board relief: lowland at 34, the hills' band at 66, the mountains' at 99")
	var rising := true
	for b in range(1, 12):
		rising = rising and Relief.band_level(b) >= Relief.band_level(b - 1)
	_check(rising, "board relief: every band stands at least as high as the one below it")
	_check(Relief.snap_level(37.0) == 34.0 and Relief.snap_level(45.0) == 50.0 and Relief.snap_level(74.0) == 77.0,
		"board relief: a tile's average snaps to the nearest band's level")
	_check(Relief.SEA_LEVEL < Relief.band_level(0), "board relief: open water stands below the lowland")
	# A row a - b - c - d: lowland, a river running from lowland b up into hill c, and a mountain beside it.
	var raw := {"a": 34.0, "b": 34.0, "c": 66.0, "d": 143.0}
	var near := {"a": ["b"], "b": ["a", "c"], "c": ["b", "d"], "d": ["c"]}
	var h: Dictionary = Relief.settle(raw, near, [["b", "c"]])
	_check(is_equal_approx(float(h["c"]), 66.0) and is_equal_approx(float(h["b"]), 66.0),
		"board relief: a river never climbs: the land it comes from is raised and the hill keeps its height (%.0f, %.0f)" % [float(h["b"]), float(h["c"])])
	_check(is_equal_approx(float(h["d"]), 66.0 + Relief.STEP_CAP),
		"board relief: high ground stands at most the cap above its neighbour (%.0f)" % float(h["d"]))
	_check(is_equal_approx(float(h["a"]), 34.0), "board relief: lowland away from the river keeps its level")


## The board's tile heights over the real map: each is its land's average band level, snapped; a
## river never climbs from tile to tile, followed down toward its mouth; no two neighbours differ by
## more than the cap; high ground stands higher.
func _test_empire_board_relief_map() -> void:
	var Relief := preload("res://scripts/empire_board_relief.gd")
	var Model := preload("res://scripts/empire_board_model.gd")
	var inst: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	var terrain: Node = inst.find_child("TerrainLayer", true, false)
	var rv: Node = inst.find_child("RiverVisuals", true, false)
	if terrain == null or rv == null:
		_check(false, "board relief map: the map and its rivers load")
		inst.queue_free()
		return
	var rivers: Dictionary = {}
	for rec in rv.call("get_river_polylines"):
		var cc: Vector2i = rec["coord"]
		(rivers.get_or_add("tile_%d_%d" % [cc.x + 1, cc.y + 1], []) as Array).append(rec["points"])
	var plates: Dictionary = Relief.plates(terrain, rivers)
	var centers: Dictionary = {}
	for tid in Catalog.all_tile_ids():
		if (terrain.call("id_to_coord", str(tid)) as Vector2i).x >= 0:
			centers[str(tid)] = Model.tile_center(terrain, str(tid))
	# A tile's own height, worked out here from the routing grid: the mean level of its land cells.
	var grid := NavGrid.instance()
	var checked := 0
	var wrong: Array = []
	for tid in ["tile_6_9", "tile_7_11", "tile_9_10", "tile_10_8", "tile_11_7"]:
		if not centers.has(tid):
			continue
		var c: Vector2 = centers[tid]
		var sum := 0.0
		var count := 0
		var lo := grid.cell_of(c - Relief.HEX_HALF)
		var hi := grid.cell_of(c + Relief.HEX_HALF)
		for iy in range(lo.y, hi.y + 1, Relief.SAMPLE_STRIDE):
			for ix in range(lo.x, hi.x + 1, Relief.SAMPLE_STRIDE):
				var d := grid.world_of(ix, iy) - c
				if absf(d.y) > 240.0 or absf(d.x) > 270.0 - absf(d.y) * 0.5625:
					continue
				if grid.water(ix, iy) == NavGrid.WATER_SEA or grid.water(ix, iy) == NavGrid.WATER_LAKE:
					continue
				sum += Relief.band_level(grid.band(ix, iy))
				count += 1
		var mean := sum / float(maxi(count, 1))
		checked += 1
		if not is_equal_approx(Relief.tile_level(c), Relief.snap_level(mean)):
			wrong.append("%s mean %.1f level %.0f settled %.0f" % [tid, mean, Relief.tile_level(c), float(plates[tid])])
	_check(checked == 5 and wrong.is_empty(),
		"board relief map: a tile's height is its land's average band level, snapped %s" % [wrong])
	var flows: Array = Relief.river_flows(rivers, centers)
	var climbs: Array = []
	for f in flows:
		if float(plates[str(f[1])]) > float(plates[str(f[0])]) + 0.001:
			climbs.append("%s->%s" % [f[0], f[1]])
	_check(flows.size() > 50 and climbs.is_empty(),
		"board relief map: no river climbs from tile to tile on its way to the sea (%d links, climbs %s)" % [flows.size(), climbs])
	var worst := 0.0
	var by_kind: Dictionary = {}
	for tid in plates:
		var kind := str(Catalog.tile_type(str(tid)))
		if Relief.WATER_TILES.has(kind):
			continue
		for nb in Catalog.tile_neighbours(str(tid)):
			if plates.has(str(nb)) and not Relief.WATER_TILES.has(str(Catalog.tile_type(str(nb)))):
				worst = maxf(worst, absf(float(plates[tid]) - float(plates[str(nb)])))
		var sum: Array = by_kind.get_or_add(kind, [0.0, 0])
		sum[0] = float(sum[0]) + float(plates[tid])
		sum[1] = int(sum[1]) + 1
	_check(worst <= Relief.STEP_CAP + 0.001, "board relief map: no neighbouring tiles differ by more than the cap (%.0f)" % worst)
	var mean_of := func(kind: String) -> float:
		var s: Array = by_kind.get(kind, [0.0, 1])
		return float(s[0]) / float(maxi(1, int(s[1])))
	_check(mean_of.call("mountain") > mean_of.call("hill") + 4.0 and mean_of.call("hill") > mean_of.call("rural") + 4.0
		and absf(float(mean_of.call("rural")) - 34.0) < 4.0,
		"board relief map: mountains stand well over hills, hills over lowland, lowland about 34 (%.0f, %.0f, %.0f)"
			% [mean_of.call("mountain"), mean_of.call("hill"), mean_of.call("rural")])
	inst.queue_free()
	await get_tree().process_frame


## A small board on made-up relief, to pin down its ground. Tile a (lowland, 34) with neighbours
## b (34) to the south-east, c (43) to the south, d (a warehouse tile, 34) to the north-east and e (a
## hill, 52) to the south-west. In the middle of a the map rises to 43 and in its heart to 52; c's
## higher ground reaches over the edge into a in a lobe. A river runs from c down into a, through
## the edge of a's rise.
func _relief_board() -> Control:
	var Board := preload("res://scripts/empire_board.gd")
	var Model := preload("res://scripts/empire_board_model.gd")
	var Ground := preload("res://scripts/empire_board_ground.gd")
	var Relief := preload("res://scripts/empire_board_relief.gd")
	var board: Control = Board.new()
	add_child(board)
	var spots := {"tb_a": [Vector2.ZERO, "rural", 34.0, false, 2], "tb_b": [Vector2(405, 240), "rural", 34.0, false, 2],
		"tb_c": [Vector2(0, 480), "rural", 43.0, false, 3], "tb_d": [Vector2(405, -240), "rural", 34.0, true, 2],
		"tb_e": [Vector2(-405, 240), "hill", 52.0, false, 4]}
	var disc := func(at: Vector2, r: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for k in range(40):
			pts.append(at + Vector2.from_angle(TAU * float(k) / 40.0) * r)
		return pts
	var bands: Array = []
	for tid in spots:
		bands.append({"b": int(spots[tid][4]), "p": Model.hex_points(spots[tid][0])})
	bands.append({"b": 3, "p": disc.call(Vector2(40, 240), 40.0)})
	bands.append({"b": 3, "p": disc.call(Vector2(-40, -70), 150.0)})
	bands.append({"b": 4, "p": disc.call(Vector2(-40, -70), 70.0)})
	var tiles: Dictionary = {}
	var ground: Variant = Ground.new()
	for tid in spots:
		var s: Array = spots[tid]
		var c: Vector2 = s[0]
		tiles[tid] = {"id": tid, "center": c, "type": s[1], "height": s[2], "store": s[3], "label": tid,
			"hub": c, "level": 1, "paved": true, "polluters": 0}
		ground.tiles[tid] = {"center": c, "height": s[2], "water": false}
		var land: Array = []
		for e in bands:
			for piece in Board._clip(e["p"], Model.hex_points(c)):
				land.append({"b": int(e["b"]), "p": piece})
		Board._relief_cache[tid] = {"sea": [], "land": land, "lakes": []}
	var rivers := {
		"tb_c": [{"points": PackedVector2Array([Vector2(-60, 470), Vector2(-30, 240)]), "start_width": 15.0, "end_width": 15.0}],
		"tb_a": [{"points": PackedVector2Array([Vector2(-30, 240), Vector2(-120, 80), Vector2(-262, 20)]), "start_width": 15.0, "end_width": 15.0}]}
	ground.bands = bands
	ground.rivers = rivers
	ground.flows = [["tb_c", "tb_a"]]
	ground.level_at = func(p: Vector2) -> float:
		var top := Relief.band_level(2)
		for e in bands:
			if Geometry2D.is_point_in_polygon(p, e["p"]):
				top = maxf(top, Relief.band_level(int(e["b"])))
		return top
	ground.relief = func(tile: String, center: Vector2) -> Dictionary: return Board._relief_of(tile, center)
	ground.setup()
	board.set("_ground", ground)
	board.set("_model", {"tiles": tiles, "standing": [], "lines": [], "flows": [], "lanes": [], "roads": []})
	var lines: Dictionary = {}
	for tid in rivers:
		lines[tid] = [rivers[tid][0]["points"]]
	board.set("_rivers", lines)
	board.call("_build_ground", rivers, int(board.get("_build_gen")))
	return board


## The board's ground meets itself at every shared edge; two neighbours of one height meet with no
## step; a step between two heights follows the map's contour, not the hex edge; the made-up rise
## stands at its rungs; every tile has its ground built.
func _test_empire_board_relief_seams() -> void:
	var Model := preload("res://scripts/empire_board_model.gd")
	var board := _relief_board()
	var ground: Variant = board.get("_ground")
	var tiles: Dictionary = (board.get("_model") as Dictionary)["tiles"]
	var open: Array = []
	var ids: Array = tiles.keys()
	var edges := 0
	for a in ids:
		for b in ids:
			var ca: Vector2 = tiles[a]["center"]
			var cb: Vector2 = tiles[b]["center"]
			if str(a) >= str(b) or ca.distance_to(cb) > 500.0:
				continue
			var hexp := Model.hex_points(ca)
			for i in range(6):
				var e0 := hexp[i]
				var e1 := hexp[(i + 1) % 6]
				if ((e0 + e1) * 0.5).distance_to((ca + cb) * 0.5) > 1.0:
					continue
				edges += 1
				var n := (e1 - e0).orthogonal().normalized()
				if n.dot(cb - ca) < 0.0:
					n = -n
				for k in range(1, 40):
					var p := e0.lerp(e1, float(k) / 40.0)
					var ha := float(board.call("_height_at", p - n * 0.02))
					var hb := float(board.call("_height_at", p + n * 0.02))
					if absf(ha - hb) > 0.5:
						open.append("%s|%s at %s: %.1f vs %.1f" % [a, b, p, ha, hb])
	_check(edges == 7, "board seams: the made-up board has its seven shared edges (%d)" % edges)
	_check(open.is_empty(), "board seams: the ground meets at one height either side of every shared edge %s" % [open.slice(0, 4)])
	# a and b stand at one height: no step along their edge, the ground level across it.
	var level := true
	var stepped := false
	var hexa := Model.hex_points(Vector2.ZERO)
	for i in range(6):
		var e: Dictionary = ground.call("_edge_of", "tb_a", i)
		var mid := (hexa[i] + hexa[(i + 1) % 6]) * 0.5
		if mid.distance_to(Vector2(202.5, 120.0)) < 1.0:
			stepped = not e.is_empty()
			var n := (mid - Vector2.ZERO).normalized()
			for k in range(2, 15):
				var p := hexa[i].lerp(hexa[(i + 1) % 6], float(k) / 20.0)
				for off in [-30.0, -10.0, 10.0, 30.0]:
					level = level and absf(float(board.call("_height_at", p + n * float(off))) - 34.0) < 0.01
	_check(not stepped and level, "board seams: two neighbours of one height meet with no step, level across their edge")
	# The step from a down... up to c follows c's ground where it reaches over the edge into a.
	var lobe := str(ground.call("region_at", Vector2(40, 230)))
	var plain := str(ground.call("region_at", Vector2(110, 215)))
	var region: PackedVector2Array = ground.call("region", "tb_a")
	var off_edge := 0.0
	for p in region:
		off_edge = maxf(off_edge, Geometry2D.get_closest_point_to_segment(p, Vector2(135, 240), Vector2(-135, 240)).distance_to(p)
			if absf(p.y - 240.0) < 60.0 and absf(p.x) < 135.0 else 0.0)
	_check(lobe == "tb_c" and plain == "tb_a" and off_edge > 15.0,
		"board seams: the step between two heights follows the map's contour, not the hex edge (%s, %s, %.0f off the edge)" % [lobe, plain, off_edge])
	var heart := float(board.call("_height_at", Vector2(-40, -70)))
	var shoulder := float(board.call("_height_at", Vector2(87, -70)))
	var plainland := float(board.call("_height_at", Vector2(150, -150)))
	_check(absf(heart - 66.0) < 0.05 and absf(shoulder - 50.0) < 0.05 and absf(plainland - 34.0) < 0.05,
		"board seams: a rise stands at its rungs inside the tile (%.1f, %.1f, %.1f)" % [heart, shoulder, plainland])
	var built := true
	for tid in tiles:
		built = built and ((board.get("_tile_gfx") as Dictionary).get(tid, {}) as Dictionary).get("ground") != null
	_check(built, "board seams: every tile has its ground built")
	board.queue_free()


## Rivers run in valleys and never rise downstream; a bridge's deck stands over the valley above the
## river; a way over a step climbs over the slope's width; a building on a step stands on a plinth.
func _test_empire_board_relief_one_ground() -> void:
	var Ground := preload("res://scripts/empire_board_ground.gd")
	var board := _relief_board()
	var ground: Variant = board.get("_ground")
	# Followed downstream, from c into a, the river never rises, and it meets itself at the edge.
	var runs: Array = []
	for tid in ["tb_c", "tb_a"]:
		runs.append_array(ground.call("river_runs", tid))
	var rises := false
	var prev := INF
	var gap := 0.0
	for run in runs:
		var levels: PackedFloat32Array = run["levels"]
		if prev < INF:
			gap = absf(levels[0] - prev)
		for k in range(levels.size()):
			rises = rises or (k > 0 and levels[k] > levels[k - 1] + 0.001)
		prev = levels[levels.size() - 1]
	_check(runs.size() == 2 and not rises and gap < 0.001,
		"board ground: a river never rises followed downstream, and meets itself at a tile edge (gap %.2f)" % gap)
	# Its valley: the river on the ground at its own level, no higher than the ground a bank's width
	# either side, and the land a full step above it beyond the valley's wall (as the ground's lattice
	# blends it, so within a little of the step). Its ends, where it comes down the step from c, are
	# left out.
	var wet: Array = []
	for run in runs:
		var pts: PackedVector2Array = run["pts"]
		var levels: PackedFloat32Array = run["levels"]
		for k in range(1, pts.size() - 1):
			if pts[k].distance_to(pts[0]) < 50.0 or pts[k].distance_to(pts[pts.size() - 1]) < 50.0:
				continue
			var across := (pts[k + 1] - pts[k - 1]).normalized().orthogonal()
			var bank := float(run["half"]) + Ground.BANK
			var on := float(board.call("_height_at", pts[k]))
			if absf(on - levels[k]) > 0.6:
				wet.append("%s: %.1f on %.1f" % [pts[k], levels[k], on])
			for side in [-1.0, 1.0]:
				var at_bank := float(board.call("_height_at", pts[k] + across * bank * float(side)))
				var far: Vector2 = pts[k] + across * (bank + Ground.SLOPE_W + Ground.NODE) * float(side)
				var beyond := float(board.call("_height_at", far))
				var clear := true                 # not inside the valley of another stretch, round a bend
				for other in runs:
					for q in (other["pts"] as PackedVector2Array):
						clear = clear and q.distance_to(far) >= bank + Ground.SLOPE_W + 4.0
				if on > at_bank + 0.01 or (clear and beyond < levels[k] + Ground.VALLEY_DEPTH - 1.5):
					wet.append("%s: %.1f bank %.1f beyond %.1f" % [pts[k], levels[k], at_bank, beyond])
	_check(wet.is_empty(), "board ground: a river's ground is at its level within a bank's width, the land a step above beyond %s" % [wet.slice(0, 3)])
	# A bridge: the street that crosses the river does so on a level deck above it.
	var spans: Array = board.call("_spans_of", "tb_a")
	var decks := not spans.is_empty()
	var streets: Array = []
	for span in spans:
		streets.append({"tile": "tb_a", "a": (span["at"] as Vector2) - (span["dir"] as Vector2) * 70.0,
			"b": (span["at"] as Vector2) + (span["dir"] as Vector2) * 70.0, "kind": "avenue", "level": 1, "paved": true})
	(board.get("_model") as Dictionary)["roads"] = streets
	board.call("_mark_bridges")
	for span in spans:
		var dir: Vector2 = span["dir"]
		var a: Vector2 = (span["at"] as Vector2) - dir * 70.0
		var b: Vector2 = (span["at"] as Vector2) + dir * 70.0
		decks = decks and bool(span["used"])
		var prof: Array = board.call("_profile", a, b, "tb_a")
		var on_deck := 0.0
		for i in range(1, prof.size()):
			if float(prof[i][0]) >= 0.5:
				on_deck = lerpf(float(prof[i - 1][1]), float(prof[i][1]),
					(0.5 - float(prof[i - 1][0])) / maxf(float(prof[i][0]) - float(prof[i - 1][0]), 0.0001))
				break
		var river := float(board.call("_height_at", span["at"]))
		decks = decks and float(span["deck"]) > river + 5.0 and absf(on_deck - float(span["deck"])) < 0.01
	_check(decks, "board ground: a bridge's deck stands level over the valley, above the river (%d bridges)" % spans.size())
	# A way across the step from a up to c: it climbs the step's height over the slope, never in a jump.
	var ramp: Array = board.call("_profile", Vector2(100, 120), Vector2(100, 360))
	var steepest := 0.0
	for i in range(1, ramp.size()):
		var run := (float(ramp[i][0]) - float(ramp[i - 1][0])) * 240.0
		if run > 0.001:
			steepest = maxf(steepest, absf(float(ramp[i][1]) - float(ramp[i - 1][1])) / run)
	var climb := float(ramp[ramp.size() - 1][1]) - float(ramp[0][1])
	_check(absf(climb - 9.0) < 0.01 and steepest > 0.0 and steepest <= 0.45,
		"board ground: a way over a step climbs it over the slope's width, never in one jump (climb %.1f, steepest %.2f)" % [climb, steepest])
	# A building over the step stands level on its highest ground, on a plinth.
	(board.get("_model") as Dictionary)["standing"] = [{"kind": "building", "iid": "plinth_test", "tile": "tb_a",
		"pos": Vector2(100, 238), "side": 40.0, "level": 1, "name": "Works"}]
	board.call("_build_standing")
	var stood: Dictionary = (board.get("_standing") as Array)[0]
	var high := 0.0
	for corner in [Vector2(-20, -20), Vector2(20, -20), Vector2(20, 20), Vector2(-20, 20)]:
		high = maxf(high, float(board.call("_height_at", Vector2(100, 238) + corner)))
	_check(stood.has("plinth") and is_equal_approx(float(stood["h"]), high),
		"board ground: a building over a step stands level on a plinth (%.1f)" % float(stood["h"]))
	board.queue_free()


## A one-tile terrain for building the board's model: the tile stands at the origin.
class _OneTile extends RefCounted:
	var tile := ""

	func id_to_coord(tid: String) -> Vector2i:
		return Vector2i(0, 0) if tid == tile else Vector2i(-1, -1)

	func map_coord_for_tile_coord(c: Vector2i) -> Vector2i:
		return c

	func map_to_local(_c: Vector2i) -> Vector2:
		return Vector2.ZERO


## Two neighbouring tiles for building the board's model: the first at the origin, the second
## south-east of it.
class _TwoTiles extends RefCounted:
	var tiles: Array = []
	var centres: Array = [Vector2.ZERO, Vector2(405.0, 240.0)]

	func id_to_coord(tid: String) -> Vector2i:
		var i := tiles.find(tid)
		return Vector2i(i, 0) if i >= 0 else Vector2i(-1, -1)

	func map_coord_for_tile_coord(c: Vector2i) -> Vector2i:
		return c

	func map_to_local(c: Vector2i) -> Vector2:
		return centres[c.x]


## Neighbouring tiles that both have roads are joined by them on the board though no goods move
## between them: each tile's streets run out to the point on the edge they share. A tile without
## roads is not joined.
func _test_empire_board_road_links() -> void:
	var Model := preload("res://scripts/empire_board_model.gd")
	var Streets := preload("res://scripts/empire_board_streets.gd")
	var terrain := _TwoTiles.new()
	terrain.tiles = ["tile_3_3", "tile_4_3"]
	var had: Array = []
	for t in terrain.tiles:
		had.append(Catalog.tile_has_infrastructure(str(t), "roads"))
		Catalog.add_tile_infrastructure(str(t), "roads")
	var graph := {"nodes": [
		{"tile_id": terrain.tiles[0], "iid": "links_test_a", "name": "Works", "level": 1},
		{"tile_id": terrain.tiles[1], "iid": "links_test_b", "name": "Works", "level": 1}]}
	var off: Vector2 = terrain.centres[1] - terrain.centres[0]
	var meet: Vector2 = terrain.centres[0] + Streets.exit_point(off)
	# Which tiles have a street reaching the shared edge.
	var reaching := func(model: Dictionary) -> Array:
		var found: Array = []
		for r in model["roads"]:
			if ((r["a"] as Vector2).is_equal_approx(meet) or (r["b"] as Vector2).is_equal_approx(meet)) \
					and not found.has(str(r["tile"])):
				found.append(str(r["tile"]))
		found.sort()
		return found
	Streets._paths.clear()
	var joined: Array = reaching.call(Model.build(terrain, graph))
	_check(joined == terrain.tiles, "board road links: two neighbouring tiles with roads both reach their shared edge (%s)" % [joined])
	Catalog.remove_tile_infrastructure(str(terrain.tiles[1]), "roads")
	Streets._paths.clear()
	var apart: Array = reaching.call(Model.build(terrain, graph))
	Streets._paths.clear()
	_check(apart.is_empty(), "board road links: no street runs to the edge of a neighbour without roads (%s)" % [apart])
	for i in range(terrain.tiles.size()):
		if bool(had[i]):
			Catalog.add_tile_infrastructure(str(terrain.tiles[i]), "roads")
		else:
			Catalog.remove_tile_infrastructure(str(terrain.tiles[i]), "roads")


## The supply chain board by the sea: nothing stands on open water and no street runs over it
## while dry ground is free; a home may stand on the beach, right down to the water's edge; a home
## the plan's streets reach only over the water has a street along the beach, itself kept off the
## water; and a river runs on through the beach into the sea.
func _test_empire_board_coast() -> void:
	var Model := preload("res://scripts/empire_board_model.gd")
	var Streets := preload("res://scripts/empire_board_streets.gd")
	var Board := preload("res://scripts/empire_board.gd")
	# A city tile whose west side is sea.
	var terrain := _OneTile.new()
	terrain.tile = "tile_7_11"
	var graph := {"nodes": [{"tile_id": terrain.tile, "iid": "coast_test_works", "name": "Works", "level": 1}]}
	var water := func(_tile: String, p: Vector2) -> bool: return p.x < -150.0
	# Everything standing, over its footprint, and every street, kerb to kerb, against a water test.
	var wet_in := func(model: Dictionary, test: Callable) -> Array:
		var found: Array = []
		for s in model["standing"]:
			var half := float(s["side"]) * 0.5
			for gx in range(-4, 5):
				for gy in range(-4, 5):
					if test.call("", (s["pos"] as Vector2) + Vector2(gx, gy) * half * 0.25) and not found.has(s["iid"]):
						found.append(s["iid"])
		for r in model["roads"]:
			var a: Vector2 = r["a"]
			var b: Vector2 = r["b"]
			var across := (b - a).normalized().orthogonal() * 6.0
			var steps := maxi(1, ceili(a.distance_to(b) / 2.0))
			for k in range(steps + 1):
				var q := a.lerp(b, float(k) / float(steps))
				if test.call("", q) or test.call("", q + across) or test.call("", q - across):
					found.append("%s road %s-%s" % [r["kind"], a, b])
					break
		return found
	var on_water := func(model: Dictionary) -> Array: return wet_in.call(model, water)
	Streets._paths.clear()
	var blind: Dictionary = Model.build(terrain, graph, {}, {}, true)
	Streets._paths.clear()
	var dry: Dictionary = Model.build(terrain, graph, {}, {}, true, water)
	Streets._paths.clear()
	_check(not (on_water.call(blind) as Array).is_empty(),
		"board coast: without the sea test the city's homes and streets reach the water (the test can fail)")
	var wet: Array = on_water.call(dry)
	_check(wet.is_empty(), "board coast: nothing stands on the sea and no street runs over it (%s)" % [wet])
	var works := false
	var homes := 0
	for s in dry["standing"]:
		works = works or str(s["iid"]) == "coast_test_works"
		homes += 1 if str(s["kind"]) == "house" else 0
	_check(works and homes >= 4, "board coast: the works and the city still stand, on the dry slots (%d homes)" % homes)
	# A home on the beach: the slot whose plot reaches to within a few units of the water is built on.
	var edge_home := false
	for s in dry["standing"]:
		var left := (s["pos"] as Vector2).x - float(s["side"]) * 0.5
		edge_home = edge_home or (str(s["kind"]) == "house" and left > -150.0 and left < -140.0)
	_check(edge_home and not Model._at_sea("", Vector2(-110, 0), 72.0, water) and Model._at_sea("", Vector2(-120, 0), 72.0, water),
		"board coast: a home stands on the sand right up to the water's edge, never over it")
	# A bay over the west end of the front street: the plot behind it is dry, but its way onto the street
	# runs into the water, so a street along the beach takes it round.
	var bay := func(_tile: String, p: Vector2) -> bool: return p.x < -150.0 and p.y > 60.0
	Streets._paths.clear()
	var shored: Dictionary = Model.build(terrain, graph, {}, {}, true, bay)
	Streets._paths.clear()
	var shore_streets := 0
	var shore_home := false
	for r in shored["roads"]:
		shore_streets += 1 if str(r["kind"]) == "shore" else 0
	for s in shored["standing"]:
		shore_home = shore_home or (s as Dictionary).has("shore")
	var bay_wet: Array = wet_in.call(shored, bay)
	_check(shore_streets > 0 and shore_home and bay_wet.is_empty(),
		"board coast: a home reached only over the water has a street along the beach, and nothing runs over the water (%d stretches) %s"
			% [shore_streets, bay_wet])
	# A river reaching the sea: land to the north of y = 0, open water south of it.
	var rel := {"sea": [{"b": 4, "p": PackedVector2Array([Vector2(-100, -200), Vector2(100, -200), Vector2(100, 200), Vector2(-100, 200)])}],
		"land": [{"b": 1, "lift": 0.0, "p": PackedVector2Array([Vector2(-100, -200), Vector2(100, -200), Vector2(100, 0), Vector2(-100, 0)])}],
		"lakes": []}
	var coast: Array = Board._shore_of(rel, Model.hex_points(Vector2.ZERO))
	var river := PackedVector2Array([Vector2(-60, -100), Vector2(0, -20), Vector2(30, 60)])
	var runs: Array = Board._to_mouth(rel, river, coast, 12.0)
	var mouth_ok := runs.size() == 1
	if mouth_ok:
		var pts: PackedVector2Array = runs[0]["pts"]
		var cut: Array = (runs[0]["cuts"] as Array)[0] if not (runs[0]["cuts"] as Array).is_empty() else [Vector2.INF, Vector2.ZERO]
		mouth_ok = pts[pts.size() - 1].y >= Board._MOUTH and absf((cut[0] as Vector2).y) < 0.5 \
			and (cut[1] as Vector2).is_equal_approx(Vector2(0.0, 1.0))
	_check(mouth_ok, "board coast: a river runs on over the beach to the sea's water, its end along the shore")
	var inland: Array = Board._to_mouth(rel, PackedVector2Array([Vector2(-60, -150), Vector2(40, -60)]), coast, 12.0)
	_check(inland.size() == 1 and (inland[0]["cuts"] as Array).is_empty(), "board coast: a river that never reaches the sea is left as it is")


## A tile's streets are one surface. Where two stretches turn a corner or cross, on the flat and up a
## slope, the middle of the street shows asphalt all the way through the join, and no edge or kerb of
## one stretch is laid over another's asphalt; the inked edge shows only round the outside of the
## streets as a whole. A street leaving for the tile beside runs on over the edge.
func _test_empire_board_streets_one_surface() -> void:
	var Board := preload("res://scripts/empire_board.gd")
	var board := _relief_board()
	var tiles: Dictionary = (board.get("_model") as Dictionary)["tiles"]
	# In a: a corner on the slope of its rise, a corner and a crossing on the flat, and a street out to
	# the edge with b.
	var plan := [[Vector2(-160, -150), Vector2(-40, -150)], [Vector2(-40, -150), Vector2(-40, 0)],
		[Vector2(-40, 0), Vector2(60, 0)], [Vector2(60, 0), Vector2(140, 0)], [Vector2(60, -100), Vector2(60, 0)],
		[Vector2(60, 0), Vector2(60, 100)], [Vector2(140, 0), Vector2(202.5, 120)]]
	var roads: Array = []
	for s in plan:
		roads.append({"tile": "tb_a", "a": s[0], "b": s[1], "kind": "street", "level": 2, "paved": true})
	(board.get("_model") as Dictionary)["roads"] = roads
	await board.call("_build_roads", tiles, int(board.get("_build_gen")))
	var mesh: ArrayMesh = (board.get("_road_meshes") as Dictionary).get("tb_a")
	var ways: Array = (board.get("_road_ways") as Dictionary).get("tb_a", [])
	if mesh == null or ways.size() != plan.size():
		_check(false, "board streets: a tile's streets are built as one mesh (%d stretches)" % ways.size())
		board.queue_free()
		return
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var rank := {Board._ROAD_EDGE.to_rgba32(): 0, Board._ROAD_KERB.to_rgba32(): 1, Board._ROAD_EDGE_IN.to_rgba32(): 2,
		Board._ROAD_ASPHALT.to_rgba32(): 3, Board._ROAD_MARK.to_rgba32(): 4}
	# Laid band by band: nothing is laid over a band that comes after it.
	var last := 0
	var in_order := true
	for i in range(0, idx.size(), 3):
		var r := int(rank.get(cols[idx[i]].to_rgba32(), -1))
		in_order = in_order and r >= last
		last = maxi(last, r)
	_check(in_order, "board streets: every stretch's edge, then kerb, then asphalt, then markings, so none is laid over another's asphalt")
	# The band on top at a point of the picture: 0 the edge .. 4 the markings, -1 none.
	var top := func(q: Vector2) -> int:
		var found := -1
		for i in range(0, idx.size(), 3):
			var v0 := Vector2(verts[idx[i]].x, verts[idx[i]].y)
			var v1 := Vector2(verts[idx[i + 1]].x, verts[idx[i + 1]].y)
			var v2 := Vector2(verts[idx[i + 2]].x, verts[idx[i + 2]].y)
			if Geometry2D.point_is_inside_triangle(q, v0, v1, v2):
				found = int(rank.get(cols[idx[i]].to_rgba32(), -1))
		return found
	var widths: Array = Board._road_widths(2)
	var holes: Array = []
	var edges: Array = []
	var climbs := 0.0
	for w in ways:
		var a: Vector2 = w["a"]
		var b: Vector2 = w["b"]
		var dir := (b - a).normalized()
		var across := dir.orthogonal()
		climbs = maxf(climbs, absf(float(board.call("_road_height", w, b)) - float(board.call("_road_height", w, a))))
		var length := a.distance_to(b)
		# Off the points the mesh is laid from, which lie on the edges of its triangles.
		var d := 0.41
		while d <= length:
			for off in [0.3, float(widths[3]) - 1.0, 1.0 - float(widths[3])]:
				var p: Vector2 = a + dir * d + across * float(off)
				if int(top.call(Board.iso(p, float(board.call("_road_height", w, p))))) < 3:
					holes.append("%s" % p.round())
			d += 2.0
		# The edge, at the middle of a stretch, clear of the others.
		for side in [-1.0, 1.0]:
			var p: Vector2 = a.lerp(b, 0.5) + across * float(side) * (float(widths[0]) - Board._ROAD_INK_W * 0.5)
			if int(top.call(Board.iso(p, float(board.call("_road_height", w, p))))) != 0:
				edges.append("%s" % p.round())
	_check(holes.is_empty() and climbs > 2.0,
		"board streets: asphalt all the way along and across every stretch, through every corner and crossing, up a slope (climb %.1f) %s"
			% [climbs, holes.slice(0, 4)])
	_check(edges.is_empty(), "board streets: the inked edge shows along the outside of each street %s" % [edges.slice(0, 4)])
	var out: Dictionary = ways[ways.size() - 1]
	var beyond: Vector2 = Vector2(202.5, 120) + ((out["b"] as Vector2) - (out["a"] as Vector2)).normalized() * 4.0
	var run_on := int(top.call(Board.iso(beyond, float(board.call("_road_height", out, beyond)))))
	_check(bool(out["edge"][1]) and run_on >= 3,
		"board streets: a street leaving for the tile beside runs on over the edge")
	board.queue_free()


## A car is drawn under everything that stands: on the street layer, between the bakes of the ground and
## those of the things, so a building in front of it hides it as it passes. A bridge goes with the
## streets in the ground layer, so a car crossing one is drawn over it.
func _test_empire_board_cars_behind_things() -> void:
	var Board := preload("res://scripts/empire_board.gd")
	var board: Control = Board.new()
	add_child(board)
	var order: Array = []
	for name in ["Bakes", "Street", "ThingsBakes", "Glow", "Tokens"]:
		var layer := board.get_node_or_null(name)
		order.append(layer.get_index() if layer != null else -1)
	var stacked := not order.has(-1)
	for i in range(1, order.size()):
		stacked = stacked and int(order[i]) > int(order[i - 1])
	_check(stacked and bool(board.get_node("ThingsBakes").get("things")) and not bool(board.get_node("Bakes").get("things")),
		"board cars: the ground's bakes, then the street layer, then the things' bakes, then the tokens %s" % [order])
	board.queue_free()
	# Bridges are laid with the streets, in the ground layer, and nothing of them among the things.
	var relief := _relief_board()
	var tiles: Dictionary = (relief.get("_model") as Dictionary)["tiles"]
	var spans: Array = relief.call("_spans_of", "tb_a")
	var roads: Array = []
	for span in spans:
		roads.append({"tile": "tb_a", "a": (span["at"] as Vector2) - (span["dir"] as Vector2) * 70.0,
			"b": (span["at"] as Vector2) + (span["dir"] as Vector2) * 70.0, "kind": "avenue", "level": 1, "paved": true})
	(relief.get("_model") as Dictionary)["roads"] = roads
	relief.call("_mark_bridges")
	await relief.call("_build_roads", tiles, int(relief.get("_build_gen")))
	relief.call("_sort_parts")
	var bridges: Array = ((relief.get("_tile_parts") as Dictionary)["tb_a"] as Dictionary).get("bridges", [])
	var among_things := 0
	for thing in ((relief.get("_tile_parts") as Dictionary)["tb_a"] as Dictionary)["things"]:
		among_things += 1 if str((thing["ref"] as Dictionary).get("name", "")).begins_with("r_bridge") else 0
	_check(not spans.is_empty() and bridges.size() >= 1 and among_things == 0,
		"board cars: a street's bridge is laid in the ground layer, under the cars (%d bridges)" % bridges.size())
	relief.queue_free()


## The supply chain board's pictures, kept from one build to the next. Each tile is drawn in two
## layers, every ground layer before any things layer, and a things layer takes in whole all that
## stands on its tile. A layer's make-up changes, and the layer is baked again, only when what it
## shows changes: a building's level, a building added, a tile's infrastructure; nothing else. A
## change in the sim reaches a closed view in the background.
func _test_empire_board_caches() -> void:
	var Graph := preload("res://scripts/empire_graph.gd")
	var inst: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(inst)
	for _i in range(600):
		if bool(inst.get("build_complete")):
			break
		await get_tree().process_frame
	var view: Node = inst.find_child("EmpireView", true, false)
	var terrain: Node = get_tree().get_first_node_in_group("hex_map")
	if view == null or terrain == null:
		_check(false, "board caches: the map and the supply chain view load")
		inst.queue_free()
		return
	var board: Control = view.find_child("Board", true, false)
	var chart: Node = view.find_child("GraphWorld", true, false)
	var a := "tile_9_9"
	var made: Array = [BuildingState.add_building("b_001", "r_001", a, "player_1", "cache_test_a")]
	var sigs := func() -> Dictionary:
		board.call("set_graph", Graph.populate(chart, terrain), terrain)
		return (board.get("_tile_sig") as Dictionary).duplicate()
	var changed := func(was: Dictionary, now: Dictionary) -> Array:
		var out: Array = []
		for unit in now:
			if int(was.get(unit, 0)) != int(now[unit]):
				out.append(str(unit))
		for unit in was:
			if not now.has(unit):
				out.append(str(unit))
		out.sort()
		return out
	var base: Dictionary = sigs.call()
	# Two layers a tile, every ground drawn before any things, and nothing standing cut off.
	var units: Array = board.get("_units")
	var last_ground := -1
	var first_things := units.size()
	for k in range(units.size()):
		if str(units[k]).ends_with("#ground"):
			last_ground = k
		else:
			first_things = mini(first_things, k)
	var whole := true
	for s in board.get("_standing"):
		var drawn: Rect2 = (s as Dictionary).get("tex_rect", s["rect"])
		whole = whole and (board.call("_unit_rect", str(s["tile"]) + "#things") as Rect2).encloses(drawn)
	_check(units.size() == (board.get("_tile_order") as Array).size() * 2 and last_ground < first_things and whole,
		"board caches: each tile in two layers, all ground under all things, everything standing drawn whole")
	# Nothing the board shows: no layer changes.
	MatchState.money += 1.0
	var after: Dictionary = sigs.call()
	_check((changed.call(base, after) as Array).is_empty(),
		"board caches: a change the board does not show bakes nothing again %s" % [changed.call(base, after)])
	# A building's level: its tile's things, and nothing else.
	BuildingState.buildings[made[0]]["level"] = 2
	var levelled: Array = changed.call(after, sigs.call())
	_check(levelled == [a + "#things"], "board caches: a level reached bakes its tile's things again, alone %s" % [levelled])
	after = sigs.call()
	# A building added: its tile, and only its tile.
	made.append(BuildingState.add_building("b_001", "r_001", a, "player_1", "cache_test_b"))
	var added: Array = changed.call(after, sigs.call())
	var own := true
	for unit in added:
		own = own and str(unit).begins_with(a + "#")
	_check(added.has(a + "#things") and own, "board caches: a building added bakes its own tile again, alone %s" % [added])
	after = sigs.call()
	# Its streets' level: its tile's ground, and at most a neighbour's where their roads meet.
	var was_level := Catalog.tile_infra_level(a, "roads")
	Catalog.set_tile_infra_level(a, "roads", 3 if was_level < 3 else 2)
	var paved: Array = changed.call(after, sigs.call())
	var near := true
	for unit in paved:
		near = near and (str(unit).begins_with(a + "#")
			or (str(unit).ends_with("#ground") and Catalog.tile_neighbours(a).has(str(unit).get_slice("#", 0))))
	_check(paved.has(a + "#ground") and near,
		"board caches: a tile's infrastructure bakes that tile again (its streets, and the lamps along them), and no more than a neighbour's ground where their roads meet %s" % [paved])
	Catalog.set_tile_infra_level(a, "roads", was_level)
	# Closed, the view takes a change in the sim in the background.
	after = sigs.call()
	view.call("prepare")
	for _i in range(600):
		if bool(view.get("_fresh")):
			break
		await get_tree().process_frame
	BuildingState.buildings[made[0]]["level"] = 3
	BuildingWorks.building_upgraded.emit(made[0], 3)
	var stale := not bool(view.get("_fresh"))
	for _i in range(600):
		if bool(view.get("_fresh")):
			break
		await get_tree().process_frame
	var background: Array = changed.call(after, (board.get("_tile_sig") as Dictionary))
	_check(stale and bool(view.get("_fresh")) and background == [a + "#things"],
		"board caches: a level reached while the view is closed is built in the background %s" % [background])
	# Over budget, the bakes let go are the ones off screen, even newer ones, and never a picture
	# in view: let go, it would be drawn live until baked again and the tiles in view would
	# flicker as they took turns.
	var Board := preload("res://scripts/empire_board.gd")
	made.append(BuildingState.add_building("b_001", "r_001", "tile_13_9", "player_1", "cache_test_far"))
	board.call("set_graph", Graph.populate(chart, terrain), terrain)
	units = board.get("_units")
	var kept: Dictionary = Board._bakes.duplicate()
	var was_size: Vector2 = board.size
	var was_zoom: float = board.get("_zoom")
	var was_offset: Vector2 = board.get("_offset")
	board.size = Vector2(200.0, 150.0)
	board.set("_zoom", 0.6)
	var on := a + "#ground"
	board.set("_offset", board.size * 0.5 - (board.call("_unit_rect", on) as Rect2).get_center() * 0.6)
	var off := ""
	for unit in units:
		var r: Rect2 = board.call("_unit_rect", str(unit))
		if not Rect2(Vector2.ZERO, board.size).intersects(Rect2(r.position * 0.6 + board.get("_offset"), r.size * 0.6)):
			off = str(unit)
			break
	Board._bakes.clear()
	var zoom: float = board.call("_bake_zoom")
	Board._bakes[board.call("_bake_key", on, zoom)] = {"bytes": Board._BAKE_BUDGET, "used": 1, "sig": 0}
	Board._bakes[board.call("_bake_key", off, zoom)] = {"bytes": Board._BAKE_BUDGET, "used": 2, "sig": 0}
	board.call("_trim_bakes")
	var left: Array = Board._bakes.keys()
	_check(off != "" and left == [board.call("_bake_key", on, zoom)],
		"board caches: over budget, a picture off screen (%s) goes and the one in view stays %s" % [off, left])
	Board._bakes.clear()
	Board._bakes.merge(kept)
	board.size = was_size
	board.set("_zoom", was_zoom)
	board.set("_offset", was_offset)
	for iid in made:
		BuildingState.remove_building(str(iid))
	inst.queue_free()
	await get_tree().process_frame


## The supply chain board's railway: one plan on every tile, so neighbours' tracks meet.
func _test_empire_board_rails() -> void:
	var Rails := preload("res://scripts/empire_board_rails.gd")
	var met := true
	var inside := true
	for off in [Vector2(405, 240), Vector2(-405, 240), Vector2(405, -240), Vector2(-405, -240), Vector2(0, 480), Vector2(0, -480)]:
		var out: Vector2 = Rails.exit_point(off)
		if out == Vector2.ZERO or (out - off).distance_to(Rails.exit_point(-off)) > 0.01:
			met = false
		var way: Array = Rails.path(Rails.stop(Vector2(0.0, 34.0)), out)
		if (way[0] as Vector2).distance_to(Vector2(0.0, Rails.LINE_Y)) > 0.01 or (way[way.size() - 1] as Vector2).distance_to(out) > 0.01:
			inside = false
		for i in range(way.size() - 1):
			var d: Vector2 = (way[i + 1] as Vector2) - (way[i] as Vector2)
			var deg := fposmod(rad_to_deg(d.angle()), 30.0)
			if minf(deg, 30.0 - deg) > 0.1:
				inside = false
	_check(met, "rails: a track leaves a tile at the point its neighbour's track arrives")
	_check(inside, "rails: a way from the warehouse's stop to any edge runs on the plan's directions")
	_check(Rails.exit_point(Vector2(900.0, 0.0)) == Vector2.ZERO, "rails: no track to a tile that is not a neighbour")
	_check(Rails.path(Vector2(-100.0, Rails.LINE_Y), Vector2(100.0, -Rails.LINE_Y)).size() == 4,
		"rails: between the two lines a train takes the cross track")


## The supply chain board's visibility key: a tickbox for each of the board's switches.
func _test_empire_board_visibility() -> void:
	var Board := preload("res://scripts/empire_board.gd")
	var Visibility := preload("res://scripts/empire_board_visibility.gd")
	var state: Dictionary = (Board.show as Dictionary).duplicate()
	var vis: Control = Visibility.new()
	add_child(vis)
	vis.setup(state)
	var keys: Array = []
	for row in Visibility.ROWS:
		keys.append(str(row[0]))
	var matched := keys.size() == 10 and state.size() == keys.size()
	for k in state:
		matched = matched and keys.has(str(k))
	_check(matched, "visibility: one tickbox for each of the board's ten switches")
	_check(not vis.is_open(), "visibility: the plate of tickboxes starts shut")
	vis.key.pressed.emit()
	_check(vis.is_open(), "visibility: the key opens it")
	var heard: Array = []
	vis.changed.connect(func(key: String, on: bool) -> void: heard.append([key, on]))
	(vis.panel.find_child("Show_trees", true, false) as Button).pressed.emit()
	_check(state["trees"] == false and heard == [["trees", false]], "visibility: a tickbox flips its switch and says so")
	(vis.panel.find_child("Show_trees", true, false) as Button).pressed.emit()
	_check(state["trees"] == true, "visibility: and flips it back")
	vis.queue_free()


## The supply chain board's pipework: routes snapped onto twelve directions so baked pieces fit.
func _test_empire_board_pipes() -> void:
	var Pipes := preload("res://scripts/empire_board_pipes.gd")
	var v := Vector2(140.0, -55.0)
	var parts: Array = Pipes.split(v)
	var back: Vector2 = Pipes.dir_of(parts[0]) * float(parts[1]) + Pipes.dir_of(parts[2]) * float(parts[3])
	_check(back.distance_to(v) < 0.01 and float(parts[1]) >= 0.0 and float(parts[3]) >= 0.0,
		"pipes: a vector splits into the two grid directions either side of it")
	_check(Pipes.turn(parts[0], parts[2]) == 1, "pipes: those two directions are one step, 30 degrees, apart")
	_check(Pipes.k_of(Pipes.dir_of(7)) == 7, "pipes: a direction and its index round-trip")
	_check(Pipes.bend_name(2, 5) == Pipes.bend_name(11, 8),
		"pipes: a bend walked backwards is the same baked piece")
	_check(Pipes.bend_name(2, 5) != Pipes.bend_name(5, 2), "pipes: the opposite bend is a different piece")
	# A run that has to cross a tile edge lands exactly on the edge's line, and every leg lies
	# on the grid and is long enough to carry its bends.
	var edge := Vector2(200.0, 120.0)
	var normal := Vector2(405.0, 240.0).normalized()
	var legs: Array = Pipes.plan([
		{"p": Vector2(10.0, -30.0), "base": 34.0, "edge": false},
		{"p": edge, "base": 34.0, "edge": true, "normal": normal},
		{"p": edge, "base": 66.0, "edge": true, "normal": -normal},
		{"p": Vector2(420.0, 300.0), "base": 66.0, "edge": false},
	])
	var on_grid := true
	var crossed := false
	var joined := true
	for i in range(legs.size()):
		var leg: Dictionary = legs[i]
		var d: Vector2 = ((leg["b"] as Vector2) - (leg["a"] as Vector2)).normalized()
		on_grid = on_grid and d.distance_to(Pipes.dir_of(int(leg["k"]))) < 0.001
		if i > 0:
			joined = joined and (legs[i - 1]["b"] as Vector2).distance_to(leg["a"]) < 0.001
			if not is_equal_approx(float(legs[i - 1]["base"]), float(leg["base"])):
				crossed = absf(((leg["a"] as Vector2) - edge).dot(normal)) < 0.01 \
					and int(legs[i - 1]["k"]) == int(leg["k"])
	_check(legs.size() >= 2 and on_grid, "pipes: every planned leg runs along a grid direction")
	_check(joined, "pipes: the legs join end to end")
	_check(crossed, "pipes: the step between tiles stands on the tile edge, on a straight run")
	_check((legs[legs.size() - 1]["b"] as Vector2).distance_to(Vector2(420.0, 300.0)) <= Pipes.MIN_LEG,
		"pipes: the run ends within a short leg of where it was asked to")
	var hit: Array = Pipes.road_spans(Vector2(0.0, 0.0), Vector2(100.0, 0.0),
		[{"a": Vector2(50.0, -40.0), "b": Vector2(50.0, 40.0), "half": 8.0}])
	_check(hit.size() == 1 and float(hit[0][0]) < 42.0 and float(hit[0][1]) > 58.0,
		"pipes: a road across a leg gives a span wider than the road")
