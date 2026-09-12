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

func _test_group_card_content_fits() -> void:
	# A TVP group card stacks name (BuildingName 22) + "Cost Basis" (13) + value (14) inside
	# GROUP_CARD_H. With a 20px inset top and bottom the content was ~7px taller than the space
	# left, so the expanding pusher collapsed and the value row sat on the card's bottom edge.
	# Measure with the real theme rather than trusting the arithmetic.
	var TVP := preload("res://scripts/tile_info_panel_v2.gd")
	var v_inset := 8   # must match tile_info_panel_v2._add_group_card
	var name_lbl := Label.new()
	name_lbl.theme_type_variation = &"BuildingName"
	name_lbl.text = "Onshore wind generation"
	var head_lbl := Label.new()
	head_lbl.theme_type_variation = &"Body"
	head_lbl.add_theme_font_size_override("font_size", 13)
	head_lbl.text = "Cost Basis"
	var val_lbl := Label.new()
	val_lbl.theme_type_variation = &"Numeric"
	val_lbl.add_theme_font_size_override("font_size", 14)
	val_lbl.text = "0.4213"
	var holder := Control.new()
	add_child(holder)
	for l in [name_lbl, head_lbl, val_lbl]:
		holder.add_child(l)
	var content: float = name_lbl.get_minimum_size().y + head_lbl.get_minimum_size().y \
		+ val_lbl.get_minimum_size().y + 2.0 * 2.0   # VBox separation = 2, two gaps
	var available: float = float(TVP.GROUP_CARD_H) - 2.0 * float(v_inset)
	_check(content <= available,
		"TVP group card: %.0fpx of rows fits the %.0fpx left by a %dpx inset" % [content, available, v_inset])
	_check(float(TVP.GROUP_CARD_H) - 2.0 * 20.0 < content,
		"...and the old 20px inset genuinely did NOT fit (that was the misalignment)")
	holder.queue_free()
