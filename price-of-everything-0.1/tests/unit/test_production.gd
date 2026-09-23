extends "res://tests/test_base.gd"
## Production passes, recipes, buildings, deposits and labour.

const FEATURE := "production"
## Tests that also belong to other features (run under any of their tags).
const TAGS := {
	"_test_output_market_route": ["production", "special_orders"],
	"_test_building_operational_tab": ["finance", "production"],
	"_test_deposit_runthrough_ignores_output_modifiers": ["production", "research", "stockpile"],
	"_test_deposit_penalty_modifier": ["production", "research", "stockpile"],
	"_test_workforce_output_modifier_surfaces_in_building_status": ["production", "research"],
	"_test_additive_labour_cost_model": ["production", "research"],
	"_test_labour_factor_floor": ["production", "research"],
	"_test_building_leveling": ["production", "research", "stockpile"],
	"_test_run_failure_warnings": ["production", "research", "stockpile"],
	"_test_survey_grouping": ["events", "production"],
	"_test_building_resnap": ["map", "production"],
	"_test_deposit_running_out_warning": ["events", "production"],
	"_test_building_diagnostics": ["power", "production", "research", "stockpile"],
}

func _build_options_have_recipe(options: Array, recipe_id: String) -> bool:
	for option in options:
		if str(option.get("recipe_id", "")) == recipe_id:
			return true
	return false

## The tab row a player reads is the REPAYMENT — per turn, and how many turns of it are left
## — not the outstanding total (owner, 2026-09-03).
func _test_building_tab_repayment() -> void:
	var saved: Dictionary = MatchState.building_tabs.duplicate(true)
	MatchState.building_tabs = {}
	_check(MatchState.building_tab_repayment("nobody").get("per_turn", -1.0) == 0.0,
		"tab repayment: a building with no tab owes nothing per turn")
	# Still inside the interest-free window: quote the schedule it will run to, and the wait.
	MatchState.building_tabs["b"] = {"turns_left": 3, "accrued": 120.0, "mode": "slices", "slices_left": 0}
	var carrying: Dictionary = MatchState.building_tab_repayment("b")
	_check(is_equal_approx(float(carrying.per_turn), 120.0 / float(MatchState.TAB_SLICES)),
		"tab repayment: while carrying, the quoted slice is the total over TAB_SLICES (%.2f)" % float(carrying.per_turn))
	_check(int(carrying.turns_left) == MatchState.TAB_SLICES and int(carrying.starts_in) == 3,
		"tab repayment: while carrying, it says how many turns until the first slice")
	# Repaying: the slice is the balance over the slices still to run.
	MatchState.building_tabs["b"] = {"turns_left": 0, "accrued": 90.0, "mode": "slices", "slices_left": 9}
	var paying: Dictionary = MatchState.building_tab_repayment("b")
	_check(is_equal_approx(float(paying.per_turn), 10.0) and int(paying.turns_left) == 9,
		"tab repayment: repaying quotes balance/slices and the slices left (%.2f x %d)"
			% [float(paying.per_turn), int(paying.turns_left)])
	_check(int(paying.starts_in) == 0, "tab repayment: a tab already paying is not waiting to start")
	MatchState.building_tabs = saved


## The extraction-resources overlay marks tiles carrying a deposit that is NOT water. Water is
## on 123 tiles against 98 with anything else, and a water pump is an industrial building, not
## an extraction one (owner) — marking water would bury what the overlay exists to find.
func _test_tile_deposits_exclude_water() -> void:
	var with_any := 0
	var water_only := 0
	var non_water := 0
	for tile_id in Catalog.tile_ids_for_tests():
		var raw := Catalog.tile_deposits_raw(tile_id)
		if raw == "":
			continue
		with_any += 1
		var has_other := false
		for token in raw.split("|", false):
			if str(token).split("(", false)[0].strip_edges().to_lower() != "water":
				has_other = true
		if has_other:
			non_water += 1
		else:
			water_only += 1
	_check(with_any > 100, "deposits: the CSV column is being read (%d tiles carry one)" % with_any)
	_check(non_water > 0 and water_only > 0,
		"deposits: both kinds exist to tell apart (%d non-water, %d water-only)"
		% [non_water, water_only])
	_check(non_water < with_any,
		"deposits: excluding water actually excludes something (%d of %d)" % [non_water, with_any])


# Regression: recipe_row.tscn must instantiate + setup (catches script/root type
# mismatches — recipe rows are only built on expand, so the main-scene test misses them).
func _test_recipe_row_instantiates() -> void:
	var packed: PackedScene = load("res://scenes/recipe_row.tscn")
	var ok: bool = packed != null
	if ok:
		var row: Node = packed.instantiate()
		add_child(row)
		row.call("setup", {
			"recipe_id": "r_001", "display_name": "Test Recipe",
			"output_good_id": "g_001", "output_name": "coal", "output_qty": 10,
			"inputs": [], "energy_req": 4,
		}, "b_001")
		ok = row.get_node_or_null("Row/OutputIcon") != null
		row.queue_free()
	_check(ok, "recipe_row instantiates + setup runs")

# Logic: recipe requirements parse correctly (guards the build-mode path that
# silently broke earlier in the merge).
func _test_recipe_requirements() -> void:
	var recipe: Dictionary = Catalog.get_recipe("r_001")
	var reqs: Array = recipe.get("requirements", [])
	var ok: bool = reqs.size() == 1 \
		and reqs[0].get("type", "") == "deposit" \
		and reqs[0].get("value", "") == "coal"
	_check(ok, "r_001 (Coal Mining) requires deposit:coal")
	_check(recipe.get("recipe_type", "") == "Mineral Mining", "r_001 recipe_type is Mineral Mining")
	# Promotion gate: every active recipe's inputs + outputs resolve to real goods.
	var no_phantom := true
	for r in Catalog.all_recipes():
		for o in r.get("outputs", []):
			if o.get("good_id", "") == "":
				no_phantom = false
		for inp in r.get("inputs", []):
			if inp.get("good_id", "") == "":
				no_phantom = false
	_check(no_phantom, "promotion gate: active recipes only reference real goods")
	var mine_b: Dictionary = Catalog.get_building("b_001")
	_check("extraction" in mine_b.get("building_type", []), "Mine building_type contains extraction")

func _test_building_price() -> void:
	var BuildingPrice := preload("res://scripts/building_price.gd")
	var bid := "b_007"  # Industrial Goods Factory — has a real build-material kit
	var far := {"instance_id": "bp_far", "building_id": bid, "tile_id": "tile_12_2", "level": 1}
	var base: float = BuildingPrice.base_cost(far)
	_check(base > 0.0, "building price: base cost is positive")
	_check(BuildingPrice.sale_price(far) == BuildingPrice.sale_price(far), "building price: deterministic")

	# Variation multiplier is one of 0.70..1.00 in 5% steps.
	var m: float = BuildingPrice.variation_multiplier("bp_far")
	var step_ok := false
	for k in range(BuildingPrice.VARIATION_STEPS):
		if absf(m - (BuildingPrice.VARIATION_MIN + BuildingPrice.VARIATION_STEP * k)) < 0.0001:
			step_ok = true
	_check(step_ok, "building price: variation is a 5% step within 70-100%")

	# Different buildings of the same type can be priced differently.
	var distinct := {}
	for i in range(24):
		distinct[BuildingPrice.variation_multiplier("bp_inst_%d" % i)] = true
	_check(distinct.size() > 1, "building price: varies across buildings of the same type")

	# Off-port price stays within the 70-100% band; a port tile adds the +10% premium.
	if not BuildingPrice.is_near_port("tile_12_2"):
		var ratio: float = float(BuildingPrice.sale_price(far)) / base
		_check(ratio >= BuildingPrice.VARIATION_MIN - 0.01 and ratio <= 1.0 + 0.01,
			"building price: off-port price within 70-100%")
		var ports := Catalog.all_ports()
		if ports.size() > 0:
			var port_tile := str(ports[0].get("tile_id", ""))
			var off := {"instance_id": "bp_pp", "building_id": bid, "tile_id": "tile_12_2", "level": 1}
			var on := {"instance_id": "bp_pp", "building_id": bid, "tile_id": port_tile, "level": 1}
			_check(BuildingPrice.sale_price(on) > BuildingPrice.sale_price(off),
				"building price: port proximity adds a premium")

	# An L2 building costs more than L1 (extra upgrade kit + larger footprint).
	var l1 := {"instance_id": "bp_lvl", "building_id": bid, "tile_id": "tile_12_2", "level": 1}
	var l2 := {"instance_id": "bp_lvl", "building_id": bid, "tile_id": "tile_12_2", "level": 2}
	_check(BuildingPrice.base_cost(l2) > BuildingPrice.base_cost(l1), "building price: L2 base cost exceeds L1")

func _test_land_chart_matches_upgrade_gate() -> void:
	# The land chart drew every building at its LEVEL-1 footprint while the build/upgrade gate
	# (MatchState.get_tile_space_used) counted the level-scaled size. A tile of upgraded
	# buildings therefore looked far emptier than it was, and an upgrade was refused for want of
	# room the player could see going spare (owner 2026-08-01, Stoneshore Docks).
	# NON-DESTRUCTIVE: no MatchState.reset() — it wipes NPC-port state later tests assert on.
	var TVD := load("res://scripts/tile_view_data.gd")
	var tile := "tile_land_chart_test_only"
	var bid := "b_007"
	var base: float = maxf(0.0, float(Catalog.get_building(bid).get("tile_size_used", 1)))
	if base <= 0.0:
		_check(false, "land chart: test building has a footprint")
		return
	var iid := BuildingState.add_building(bid, "", tile, MatchState.LOCAL_PLAYER, "landchart_a")
	var at_l1: Dictionary = TVD.land_totals(tile, {})
	_check(int(at_l1.built) == int(round(base)), "land chart: level 1 built figure is the base footprint")
	# Level it up — the chart MUST grow with it.
	BuildingState.buildings[iid]["level"] = 3
	var at_l3: Dictionary = TVD.land_totals(tile, {})
	var gate_used: float = BuildingState.get_tile_space_used(tile)
	_check(int(at_l3.built) > int(at_l1.built),
		"land chart: a levelled-up building takes MORE room in the readout (%d -> %d)" % [
			int(at_l1.built), int(at_l3.built)])
	_check(int(at_l3.built) == int(round(gate_used)),
		"land chart: readout equals the figure the upgrade gate tests (%d vs %d)" % [
			int(at_l3.built), int(round(gate_used))])
	# And the chart's own segments must agree with the total it prints.
	var chart: Dictionary = TVD.land_chart_data(tile, {})
	var seg_total := 0.0
	for s in (chart.get("segments", []) as Array):
		if not bool((s as Dictionary).get("is_other", false)):
			seg_total += float((s as Dictionary).get("size", 0.0))
	_check(absf(seg_total - gate_used) < 0.51,
		"land chart: segments sum to the gate's used space (%.1f vs %.1f)" % [seg_total, gate_used])
	BuildingState.remove_building(iid)


func _test_recipe_flow_shows_co_products() -> void:
	# Chlor-alkali yields chlorine, sodium hydroxide AND hydrogen; the recipe card drew only the
	# first (owner 2026-08-01). NON-DESTRUCTIVE: no MatchState.reset().
	var recipe: Dictionary = Catalog.get_recipe("r_012")
	if recipe.is_empty():
		_check(false, "co-products: r_012 (Chlor-Alkali) exists")
		return
	var tile := "tile_coproduct_test_only"
	var iid := BuildingState.add_building("b_012", "r_012", tile, MatchState.LOCAL_PLAYER, "coprod_a")
	var f: Dictionary = load("res://scripts/building_readout.gd").flow(BuildingState.get_building(iid), recipe)
	var outs: Array = f.get("outputs", [])
	_check(outs.size() == 3, "co-products: chlor-alkali flow carries all 3 outputs (got %d)" % outs.size())
	var names: Array = []
	for o in outs:
		names.append(str((o as Dictionary).get("internal", "")))
	_check(names.has("chlorine") and names.has("sodium_hydroxide") and names.has("hydrogen"),
		"co-products: all three goods present (%s)" % str(names))
	_check(str((f.get("output", {}) as Dictionary).get("internal", "")) == str(outs[0].get("internal", "")),
		"co-products: the singular 'output' still points at the primary, for one-icon callers")
	for o in outs:
		_check(int((o as Dictionary).get("qty", 0)) > 0,
			"co-products: %s has a positive effective quantity" % str((o as Dictionary).get("internal", "")))
	var building := BuildingState.get_building(iid)
	var econ: Dictionary = BuildingReadout.economics(building, recipe, Catalog.get_building("b_012"))
	var valued_outputs: Array = econ.get("output_values", [])
	var total_value := 0.0
	for output in valued_outputs:
		total_value += float((output as Dictionary).get("value", 0.0))
	_check(valued_outputs.size() == 3,
		"co-products: economics values all three chlor-alkali outputs")
	_check(absf(float(econ.get("output_value", 0.0)) - total_value) < 0.0001,
		"co-products: economics output value equals the sum of every output")
	BuildingState.remove_building(iid)

func _test_tile_deposit_build_options_respect_research_unlocks() -> void:
	var saved_unlocks := ResearchState.unlocked_titles.duplicate(true)
	ResearchState.unlocked_titles.erase("Subsea Production Systems")
	var tvd = load("res://scripts/tile_view_data.gd")
	var locked_options: Array = tvd.deposit_build_options("crude_oil")
	_check(not _build_options_have_recipe(locked_options, "r_222"),
		"tile deposit build options hide recipe-gated research before unlock")
	ResearchState.grant_unlock("Subsea Production Systems")
	var unlocked_options: Array = tvd.deposit_build_options("crude_oil")
	_check(_build_options_have_recipe(unlocked_options, "r_222"),
		"tile deposit build options promote recipe when research unlocks")
	_replace_dict(ResearchState.unlocked_titles, saved_unlocks)

func _test_building_shapes() -> void:
	# Each shape holds its target area within tolerance and is deterministic.
	for kind in BuildingShapes.KINDS:
		for area in [400.0, 4000.0, 15000.0]:
			var s := BuildingShapes.make(str(kind), float(area), 3)
			var got := BuildingShapes.polygon_area(s.verts)
			_check(absf(got - float(area)) <= float(area) * 0.02 + 1.0,
				"building shapes: %s area %.0f within 2%% (got %.0f)" % [str(kind), float(area), got])
			var mx := 0.0
			var my := 0.0
			for v in (s.verts as PackedVector2Array):
				mx = maxf(mx, absf(v.x))
				my = maxf(my, absf(v.y))
			_check(absf(mx - float(s.half.x)) <= 0.5 and absf(my - float(s.half.y)) <= 0.5,
				"building shapes: %s half-extent matches verts" % str(kind))
	var a := BuildingShapes.make("l_base", 5000.0, 2)
	var b := BuildingShapes.make("l_base", 5000.0, 2)
	_check(a.verts == b.verts, "building shapes: deterministic for same params")

func _test_building_category_key() -> void:
	# The polygon layout clusters on category_key and edge-seeks on
	# extraction|recycling — guard those classifications against catalog drift.
	var TileViewData := preload("res://scripts/tile_view_data.gd")
	var mine := Catalog.get_building("b_001")
	if not mine.is_empty():
		_check((mine.get("building_type", []) as Array).has("extraction"),
			"layout edge rule: b_001 is extraction (mine)")
		_check(TileViewData.category_key(mine) == "extraction",
			"layout category_key: b_001 -> extraction")
	# Both recycling buildings must trip the edge rule (internal_name ~ 'recycl')
	# while keeping their own colour category.
	var wrec := Catalog.get_building("b_022")
	if not wrec.is_empty():
		_check(str(wrec.get("internal_name", "")).to_lower().contains("recycl"),
			"layout edge rule: b_022 water_recycling matches 'recycl'")
		_check(TileViewData.category_key(wrec) == "water",
			"layout category_key: b_022 -> water (colour stays water)")
	var prec := Catalog.get_building("b_036")
	if not prec.is_empty():
		_check(str(prec.get("internal_name", "")).to_lower().contains("recycl"),
			"layout edge rule: b_036 recycling_plant matches 'recycl'")
		_check(TileViewData.category_key(prec) == "manufacturing",
			"layout category_key: b_036 -> manufacturing")

func _test_output_market_route() -> void:
	var mode_before: int = MatchState.sell_mode
	SpecialOrderState.reset()
	MatchState.route_output_to_market("inst_test_market", "g_001")
	_check(MatchState.is_output_market("inst_test_market", "g_001"),
		"route_output_to_market marks the building for market")
	_check(MatchState.get_output_stockpile_destination("inst_test_market", "g_001") == "",
		"a market route reads as no stockpile tile")
	_check(MatchState.sell_mode == mode_before,
		"per-building market route leaves the global sell mode unchanged")
	var order: Dictionary = SpecialOrderState.create_order("coal", TurnManager.current_turn, 5, 4, 0.25)
	var order_id := str(order.get("id", ""))
	MatchState.route_output_to_special_order("inst_test_market", "g_001", order_id)
	_check(MatchState.get_output_special_order_id("inst_test_market", "g_001") == order_id
		and MatchState.is_output_market("inst_test_market", "g_001"),
		"route_output_to_special_order marks output as market-bound with an order tag")
	MatchState.route_output_to_market("inst_test_market", "g_001")
	_check(MatchState.get_output_special_order_id("inst_test_market", "g_001") == "",
		"route_output_to_market clears the special-order tag")
	SpecialOrderState.reset()

	# Per-good shipping cap (the CTRL+click "send a specific amount every turn" flow).
	MatchState.set_output_stockpile_destination("inst_test_market", "tile_3_9", "g_001")
	MatchState.set_output_ship_quantity("inst_test_market", "g_001", 10)
	_check(MatchState.get_output_ship_quantity("inst_test_market", "g_001") == 10,
		"ship quantity cap set and read back")
	MatchState.set_output_stockpile_destination("inst_test_market", "tile_3_8", "g_001")
	_check(MatchState.get_output_ship_quantity("inst_test_market", "g_001") == 0,
		"a plain re-route clears the cap (plain click ships everything)")
	MatchState.set_output_ship_quantity("inst_test_market", "g_001", 7)
	MatchState.route_output_to_market("inst_test_market", "g_001")
	_check(MatchState.get_output_ship_quantity("inst_test_market", "g_001") == 0,
		"routing back to market clears the cap")
	MatchState.set_output_stockpile_destination("inst_test_market", "tile_3_9", "g_001")
	MatchState.set_output_ship_quantity("inst_test_market", "g_001", 5)
	# Shift-click split routes keep up to three distinct tiles and each field is a
	# three-digit per-turn amount (0 keeps that destination on its automatic share).
	MatchState.add_output_split_destination("inst_test_market", "g_001", "tile_3_8")
	MatchState.add_output_split_destination("inst_test_market", "g_001", "tile_3_9")
	MatchState.add_output_split_destination("inst_test_market", "g_001", "tile_3_10")
	MatchState.add_output_split_destination("inst_test_market", "g_001", "tile_3_11")
	MatchState.set_output_split_quantity("inst_test_market", "g_001", "tile_3_9", 1200)
	MatchState.set_output_ship_quantity("inst_test_market", "g_001", 5)
	var split_route := MatchState.get_output_split_destinations("inst_test_market", "g_001")
	_check(split_route.size() == 3 and int((split_route[1] as Dictionary).get("qty", 0)) == 999,
		"split output routes keep three destinations and clamp entered quantities to three digits")
	var routed_state: Dictionary = MatchState.export_state()
	_check((routed_state.get("output_ship_quantities", {}) as Dictionary).has("inst_test_market"),
		"ship quantity caps ride the save export")
	_check((routed_state.get("output_split_destinations", {}) as Dictionary).has("inst_test_market"),
		"split output routes ride the save export")
	MatchState.set_output_ship_quantity("inst_test_market", "g_001", 0)
	_check(MatchState.get_output_ship_quantity("inst_test_market", "g_001") == 0
		and not MatchState.output_ship_quantities.has("inst_test_market"),
		"clearing the cap removes the empty per-building entry")
	MatchState.import_state(routed_state)
	_check(MatchState.get_output_ship_quantity("inst_test_market", "g_001") == 5,
		"ship quantity caps survive a save round-trip")
	_check(MatchState.get_output_split_destinations("inst_test_market", "g_001").size() == 3,
		"split output routes survive a save round-trip")
	MatchState.clear_output_stockpile_destination("inst_test_market", "g_001")
	_check(MatchState.get_output_ship_quantity("inst_test_market", "g_001") == 0,
		"clearing the route clears the cap too")

func _test_building_operational_tab() -> void:
	# A new build's first turns are carried, not paid (spec §5.3). Exposure is bounded by the
	# window, which is why the old 1x-capex cap and forced sale are gone.
	MatchState.reset()
	MatchState.money = 1000.0
	_check(not MatchState.can_open_building_tab(),
		"tab: without a CFO there is nobody to arrange one")
	_check(not MatchState.open_building_tab("inst_tab"),
		"tab: no CFO means no tab, and costs simply hit cash")

	AdvisorState.permanent_advisor_ids = ["vera"]
	AdvisorState.assign_advisor_to_seat("cfo", "vera")
	_check(MatchState.can_open_building_tab(), "tab: a seated CFO can arrange one")
	_check(MatchState.open_building_tab("inst_tab"), "tab: opens for a new build")
	_check(not MatchState.open_building_tab("inst_tab"), "tab: never opens twice for one building")

	# Carry five turns of costs, then it settles into interest-free slices.
	for _i in range(MatchState.TAB_WINDOW_TURNS):
		_check(is_equal_approx(MatchState.accrue_building_tab("inst_tab", 20.0), 20.0),
			"tab: a turn inside the window is carried")
		MatchState.tick_building_tabs()
	var owed: float = MatchState.building_tab_debt("inst_tab")
	_check(is_equal_approx(owed, 20.0 * MatchState.TAB_WINDOW_TURNS),
		"tab: carries exactly %d turns (£%.2f)" % [MatchState.TAB_WINDOW_TURNS, owed])
	_check(is_equal_approx(MatchState.accrue_building_tab("inst_tab", 20.0), 0.0),
		"tab: nothing is carried once the window closes")

	# Repayment: equal interest-free slices until it clears.
	var before: float = MatchState.money
	MatchState.tick_building_tabs()
	var paid: float = before - MatchState.money
	_check(is_equal_approx(paid, owed / float(MatchState.TAB_SLICES)),
		"tab: repays in %d equal slices (£%.2f each)" % [MatchState.TAB_SLICES, paid])
	for _i in range(MatchState.TAB_SLICES):
		MatchState.tick_building_tabs()
	_check(not MatchState.building_tabs.has("inst_tab") and MatchState.total_building_tab_debt() <= 0.01,
		"tab: clears once the last slice is paid")

	# The loan route converts instead, and carries interest.
	MatchState.reset()
	AdvisorState.permanent_advisor_ids = ["vera"]
	AdvisorState.assign_advisor_to_seat("cfo", "vera")
	MatchState.open_building_tab("inst_loan", "loan")
	MatchState.accrue_building_tab("inst_loan", 100.0)
	var loans_before: float = LoanState.total_outstanding()
	for _i in range(MatchState.TAB_WINDOW_TURNS):
		MatchState.tick_building_tabs()
	_check(LoanState.total_outstanding() > loans_before
		and not MatchState.building_tabs.has("inst_loan"),
		"tab: the loan route converts the balance into an ordinary loan")

## _recipe_diagram()'s input grid: 3 columns (up to 2 rows) once a recipe has more
## than 2 inputs — a 2026-08-27 fix. Was 2 columns (up to 3 rows), which overflowed
## the diagram's fixed 140px height for 5-6 input recipes. Also the "honest width"
## fix alongside it: diagram_root is a bare Control with its content row placed by
## anchors, not container management, so unlike a normal Container it never bubbled
## up that row's real content width on its own — silently reporting 0 regardless of
## how many cells it actually held. That was harmless while every caller gave it the
## whole row anyway (the confirm screen), but the same call reused compact in a
## recipe card that shares its row with a name column let the card claim less than
## it needed, and the output cell rendered clipped off the panel's own edge.
func _test_recipe_diagram_input_grid() -> void:
	var panel_script: Variant = load("res://scripts/construct_panel_v2.gd")
	var probe: Control = panel_script.new()
	add_child(probe)

	var five_inputs := {
		"inputs": [
			{"good_id": "g_001", "qty": 1}, {"good_id": "g_002", "qty": 1},
			{"good_id": "g_003", "qty": 1}, {"good_id": "g_004", "qty": 1},
			{"good_id": "g_005", "qty": 1},
		],
		"output_good_id": "g_006", "output_qty": 1, "energy_req": 0,
	}
	var five_diagram: PanelContainer = probe._recipe_diagram(five_inputs)
	add_child(five_diagram)   # min-size only resolves for a node in the tree
	var five_grid: GridContainer = five_diagram.find_child("RecipeInputsGrid", true, false)
	_check(five_grid != null and five_grid.columns == 3,
		"recipe diagram: >2 inputs lays out 3 columns, not 2 (got %s)" % (str(five_grid.columns) if five_grid != null else "no grid"))
	_check(five_diagram.get_combined_minimum_size().x > 0.0,
		"recipe diagram: reports an honest (non-zero) minimum width once it holds real cells")
	five_diagram.queue_free()

	var two_inputs := {
		"inputs": [{"good_id": "g_001", "qty": 1}, {"good_id": "g_002", "qty": 1}],
		"output_good_id": "g_006", "output_qty": 1, "energy_req": 0,
	}
	var two_diagram: PanelContainer = probe._recipe_diagram(two_inputs)
	add_child(two_diagram)
	var two_grid: GridContainer = two_diagram.find_child("RecipeInputsGrid", true, false)
	_check(two_grid != null and two_grid.columns == 1,
		"recipe diagram: <=2 inputs is unchanged — still 1 column (stacked), not part of this fix")
	two_diagram.queue_free()

	# Compact reuse (the recipe-card call site passes smaller cell/arrow sizes than
	# the confirm screen's defaults) still reports an honest width, just a smaller one.
	var compact: PanelContainer = probe._recipe_diagram(five_inputs, 36, Vector2(54, 34))
	add_child(compact)
	var default_size: PanelContainer = probe._recipe_diagram(five_inputs)
	add_child(default_size)
	_check(compact.get_combined_minimum_size().x < default_size.get_combined_minimum_size().x,
		"recipe diagram: smaller cell/arrow params report a correspondingly smaller minimum width")
	compact.queue_free()
	default_size.queue_free()
	probe.free()


## _recipe_diagram(..., size_by_count=true) — Building Details' own hero/pair/grid
## rule (2026-08-27 follow-up), inputs and outputs sized off their OWN counts
## independently, and outputs reading the recipe's FULL outputs array (co-products)
## instead of just the primary. Legacy calls (size_by_count omitted) are untouched —
## that's the confirm screen's flat cell_size, unrelated to this ask.
func _test_recipe_diagram_size_by_count() -> void:
	var panel_script: Variant = load("res://scripts/construct_panel_v2.gd")
	var probe: Control = panel_script.new()
	add_child(probe)

	_check(probe._flow_side_size(1, 62, true) == 126, "flow side size: a single item is the 126px hero")
	_check(probe._flow_side_size(2, 62, true) == 90, "flow side size: exactly 2 items are 90px each")
	_check(probe._flow_side_size(3, 62, true) == 60, "flow side size: 3+ items are 60px each")
	_check(probe._flow_side_size(5, 62, true) == 60, "flow side size: 5 items are still the same 60px tier as 3")
	_check(probe._flow_side_size(5, 62, false) == 62, "flow side size: by_count=false ignores count, returns the flat fallback")
	_check(probe._flow_side_columns(1, true) == 1 and probe._flow_side_columns(2, true) == 2
			and probe._flow_side_columns(3, true) == 3,
		"flow side columns: 1/2/3+ items lay out 1/2/3 columns under size_by_count")
	_check(probe._flow_side_columns(2, false) == 1,
		"flow side columns: by_count=false keeps its own original threshold (2 items still stack at 1 column)")

	# Independent sizing on a real diagram: 5 inputs + 1 output — inputs land in the
	# 60px/3-wide tier, the SINGLE output gets the 126px hero, on the SAME diagram.
	var five_in_one_out := {
		"inputs": [
			{"good_id": "g_001", "qty": 1}, {"good_id": "g_002", "qty": 1},
			{"good_id": "g_003", "qty": 1}, {"good_id": "g_004", "qty": 1},
			{"good_id": "g_005", "qty": 1},
		],
		"outputs": [{"good_id": "g_006", "qty": 1}],
		"output_good_id": "g_006", "output_qty": 1, "energy_req": 0,
	}
	var mixed: PanelContainer = probe._recipe_diagram(five_in_one_out, 62, Vector2(90, 55), 156.0, true)
	add_child(mixed)
	var in_grid: GridContainer = mixed.find_child("RecipeInputsGrid", true, false)
	var out_grid: GridContainer = mixed.find_child("RecipeOutputsGrid", true, false)
	_check(in_grid != null and in_grid.columns == 3, "size_by_count: 5 inputs still lay out 3 columns")
	_check(out_grid != null and out_grid.columns == 1, "size_by_count: the single output is its own 1-column hero")
	if in_grid != null:
		var an_input_cell: Control = in_grid.get_child(0)
		_check(absf(an_input_cell.custom_minimum_size.x - 60.0) < 0.5,
			"size_by_count: input cells are 60px (5-item tier)")
	if out_grid != null:
		var the_output_cell: Control = out_grid.get_child(0)
		_check(absf(the_output_cell.custom_minimum_size.x - 126.0) < 0.5,
			"size_by_count: the output cell is 126px (hero tier) — independent of the input side's own 60px")
	mixed.queue_free()

	# Multi-output (co-products): the FULL outputs array renders, not just the primary.
	var two_outputs := {
		"inputs": [{"good_id": "g_001", "qty": 1}],
		"outputs": [{"good_id": "g_006", "qty": 1}, {"good_id": "g_007", "qty": 1}],
		"output_good_id": "g_006", "output_qty": 1, "energy_req": 0,
	}
	var co_product: PanelContainer = probe._recipe_diagram(two_outputs, 62, Vector2(90, 55), 156.0, true)
	add_child(co_product)
	var co_grid: GridContainer = co_product.find_child("RecipeOutputsGrid", true, false)
	_check(co_grid != null and co_grid.get_child_count() == 2,
		"size_by_count: BOTH co-products render, not just the recipe's primary output")
	_check(co_grid != null and co_grid.columns == 2, "size_by_count: 2 outputs lay out side by side")
	co_product.queue_free()
	probe.free()


## The building detail panel's "Change recipe" sheet (2026-08-27 follow-up): rows
## now carry the SAME compressed mini diagram the Construct panel's own recipe cards
## use (UIHelpers.mini_recipe_diagram — one shared implementation so the two panels
## can't drift into two different looks) instead of a text-only summary line; and
## the sheet widens the whole panel to fit it, since a sheet is a same-rect overlay
## (PanelContainer manages every direct child to the identical rect) with no other
## way to claim more room than the panel's own normal width.
func _test_recipe_choice_row_mini_diagram() -> void:
	var detail_panel = load("res://scripts/building_detail_panel_v2.gd").new()
	var recipe: Dictionary = Catalog.get_recipe("r_033")   # 6 inputs + 1 output
	var row: Control = detail_panel.call("_recipe_choice_row", "probe_iid", recipe, false)
	var diagram: Control = row.find_child("MiniRecipeDiagramCard", true, false)
	_check(diagram != null, "recipe choice row: the mini diagram renders")
	if diagram != null:
		var icons := diagram.find_children("*", "TextureRect", true, false)
		_check(icons.size() == 7, "recipe choice row: one icon per input/output, 6+1=7 for r_033 (got %d)" % icons.size())
		_check(diagram.find_child("MiniRecipeArrow", true, false) != null,
			"recipe choice row: the filled navy arrow renders")
	row.free()
	detail_panel.free()

	var panel2 = load("res://scripts/building_detail_panel_v2.gd").new()
	add_child(panel2)
	await get_tree().process_frame
	panel2.call("_resize_body")
	var normal_width: float = panel2.size.x
	# NOT a plain "normal_width + 100" check: self is a PanelContainer, which clamps
	# size up to its OWN children's combined minimum regardless of what _resize_body()
	# assigns — normal_width can already sit above the bare PANEL_WIDTH constant for
	# reasons unrelated to this fix. What this fix actually guarantees is the ABSOLUTE
	# target once a sheet asks for it: PANEL_WIDTH + extra_width, exactly.
	panel2.call("_open_recipe_sheet", {"instance_id": "probe_iid", "building_id": "b_007", "recipe_id": "r_033"})
	await get_tree().process_frame
	_check(absf(panel2.size.x - (panel2.PANEL_WIDTH + 100.0)) < 0.5,
		"change-recipe sheet: opening it widens the panel to PANEL_WIDTH+100 to fit the mini diagram bars (got %.1f)" % panel2.size.x)
	panel2.call("_close_sheet")
	await get_tree().process_frame
	_check(absf(panel2.size.x - normal_width) < 0.5,
		"change-recipe sheet: closing it restores the panel's normal width (got %.1f, was %.1f)" % [panel2.size.x, normal_width])
	panel2.queue_free()


func _test_recipes_producing() -> void:
	_check(Catalog.recipes_producing("g_001").size() > 0, "recipes_producing finds producers of coal")
	_check(Catalog.recipes_producing("g_nope").is_empty(), "recipes_producing is empty for an unknown good")
	var aluminium: Dictionary = Catalog.get_good_by_internal_name("aluminium")
	var has_ewaste := false
	for recipe in Catalog.recipes_producing(str(aluminium.get("id", ""))):
		if str(recipe.get("recipe_id", "")) == "r_107":
			has_ewaste = true
	_check(not has_ewaste and not Catalog.all_recipes().any(func(recipe: Dictionary) -> bool: return str(recipe.get("recipe_id", "")) == "r_107"),
		"unfinished E-Waste Recycling is hidden from recipe discovery")
	_check(Catalog.recipe_produces(Catalog.get_recipe("r_001"), "g_001"),
		"recipe_produces detects a recipe's output good")

## Deposit life must not depend on output multipliers: research/advisor/level bonuses
## change how much ore you GET per turn, never how fast the seam empties. Drives the same
## coal mine twice from an identical deposit — once clean, once at +50% output — and
## asserts production rises while the deposit is charged the identical base amount.
func _test_deposit_runthrough_ignores_output_modifiers() -> void:
	Modifiers.reset()
	MatchState.reset()
	Stockpile.clear_all()
	var tile := "tile_6_8"  # has a coal deposit
	var inst: String = BuildingState.add_building("b_001", "r_001", tile)
	MatchState.reveal_deposit(tile, "coal")
	# Coal carries a standing −30% deposit penalty (re-seeded by reset); drop it so the
	# baseline is the clean 60-unit recipe output.
	Modifiers.remove("deposit_penalty_coal")

	MatchState.deposit_remaining[tile] = {"coal": 999}
	var summary := _fresh_production_summary()
	Production._produce_outputs(BuildingState.get_building(inst), Catalog.get_recipe("r_001"), summary)
	Production._flush_output_buffer()
	var plain_produced: int = int(summary.produced.get("g_001", 0))
	var plain_drawn: int = 999 - MatchState.deposit_remaining_for(tile, "coal")

	# Same mine, same deposit, but +50% output.
	Stockpile.clear_all()
	MatchState.deposit_remaining[tile] = {"coal": 999}
	Modifiers.add({"id": "test_oil_style_yield", "domain": "recipe_output",
		"target_match": {"building_id": "b_001"}, "mult": 1.5})
	summary = _fresh_production_summary()
	Production._produce_outputs(BuildingState.get_building(inst), Catalog.get_recipe("r_001"), summary)
	Production._flush_output_buffer()
	var boosted_produced: int = int(summary.produced.get("g_001", 0))
	var boosted_drawn: int = 999 - MatchState.deposit_remaining_for(tile, "coal")

	_check(boosted_produced > plain_produced,
		"deposit runthrough: +50%% modifier raises output (%d → %d)" % [plain_produced, boosted_produced])
	_check(boosted_drawn == plain_drawn,
		"deposit runthrough: deposit charged the SAME base amount either way (%d vs %d)"
			% [plain_drawn, boosted_drawn])
	_check(plain_drawn == plain_produced,
		"deposit runthrough: unmodified extraction charges exactly what it produced (%d vs %d)"
			% [plain_drawn, plain_produced])

	Modifiers.reset()
	BuildingState.remove_building(inst)


# End-to-end the demo unlock: a mine for each of the 6 staple deposits triggers
# the research tech ("Mining Mastery", research_unlocks.csv) → MatchState grants
# the unlock when its condition is met → Modifiers applies the +5% bonus.
func _test_deposit_penalty_modifier() -> void:
	# The deposit penalty + mining-yield research are recipe_output modifiers matched
	# by good_internal, so they show in the net-modifier indicator AND apply through
	# the production hook (no separate deposit-yield multiply).
	Modifiers.reset()
	MatchState.reset()          # re-seeds the standing per-good deposit penalties
	Stockpile.clear_all()
	# Coal starts at a standing −30% deposit penalty.
	var r: Dictionary = Modifiers.resolve_pct("recipe_output", "r_001", {"good_internal": "coal"})
	_check(absf(float(r.get("net", 0.0)) - (-30.0)) < 0.001,
		"coal mine starts at a −30%% deposit penalty (got %s)" % float(r.get("net", 0.0)))
	# The first recovery unlock adds +15% → net −15% (additive, no cap).
	ResearchState.grant_unlock("Improved Coal Mining")
	var r2: Dictionary = Modifiers.resolve_pct("recipe_output", "r_001", {"good_internal": "coal"})
	_check(absf(float(r2.get("net", 0.0)) - (-15.0)) < 0.001,
		"Improved Coal Mining: −30%% + 15%% = net −15%% (got %s)" % float(r2.get("net", 0.0)))
	_check((r2.get("parts", []) as Array).size() == 2,
		"breakdown shows both the penalty tile and the research tile")
	# End to end: a coal mine produces round(60 * 0.85) = 51.
	var tile := "tile_6_8"
	var inst: String = BuildingState.add_building("b_001", "r_001", tile)
	MatchState.reveal_deposit(tile, "coal")
	MatchState.deposit_remaining[tile] = {"coal": 999}
	var summary := _fresh_production_summary()
	Production._produce_outputs(BuildingState.get_building(inst), Catalog.get_recipe("r_001"), summary)
	Production._flush_output_buffer()
	_check(int(summary.produced.get("g_001", 0)) == 51,
		"coal output reflects net −15%% (60 → 51, got %d)" % int(summary.produced.get("g_001", 0)))
	# The second recovery unlock removes the remaining penalty exactly.
	ResearchState.grant_unlock("Automated Mine Dispatch")
	var r3: Dictionary = Modifiers.resolve_pct("recipe_output", "r_001", {"good_internal": "coal"})
	_check(absf(float(r3.get("net", 0.0))) < 0.001,
		"Automated Mine Dispatch: −30%% + 15%% + 15%% = full coal output")
	# Exempt goods (not in EXTRACTION_PENALTY_PCT) carry no penalty tile.
	var ro: Dictionary = Modifiers.resolve_pct("recipe_output", "rX", {"good_internal": "crude_oil"})
	_check(absf(float(ro.get("net", 0.0))) < 0.001,
		"exempt goods (crude_oil) carry no deposit penalty")
	# Loading a save (import_state) must NOT wipe the standing penalties — they are a
	# baseline rule re-seeded on import (regression: penalties vanished after load).
	Modifiers.import_state({"modifiers": {}, "history": [], "next_id": 1})
	var rload: Dictionary = Modifiers.resolve_pct("recipe_output", "r_001", {"good_internal": "coal"})
	_check(absf(float(rload.get("net", 0.0)) - (-30.0)) < 0.001,
		"a load with no saved penalties re-seeds the coal penalty (got %s)" % float(rload.get("net", 0.0)))
	BuildingState.remove_building(inst)

	# Every penalized extraction good has exactly enough +15% research steps to
	# cancel its standing penalty: two for −30% goods, one for −15% goods.
	var expected_recovery_steps := {
		"coal": 2, "iron_ore": 2, "copper_ore": 2, "limestone": 2,
		"sand": 2, "basic_salt": 2, "ree_ore": 2, "alloy_ore": 2,
		"sulphur": 1, "bauxite_ore": 1,
	}
	var recovery_unlocks := {}
	# Keys are research_node_ids, not titles — apply_unlock_modifier accepts either.
	for unlock_title in Modifiers.UNLOCK_MODIFIERS:
		var raw_spec = Modifiers.UNLOCK_MODIFIERS[unlock_title]
		var specs: Array = raw_spec if raw_spec is Array else [raw_spec]
		for raw_effect in specs:
			var effect: Dictionary = raw_effect
			if str(effect.get("source", "")) != "research:mining_yield":
				continue
			var effect_good := str((effect.get("target_match", {}) as Dictionary).get("good_internal", ""))
			if effect_good == "":
				continue
			_check(absf(float(effect.get("pct", 0.0)) - 15.0) < 0.001,
				"%s restores %s output by exactly 15%%" % [unlock_title, effect_good])
			var titles: Array = recovery_unlocks.get(effect_good, [])
			titles.append(str(unlock_title))
			recovery_unlocks[effect_good] = titles
	for recovery_good in expected_recovery_steps:
		var recovery_titles: Array = recovery_unlocks.get(recovery_good, [])
		_check(recovery_titles.size() == int(expected_recovery_steps[recovery_good]),
			"%s has exactly %d mining-yield recovery unlock%s" % [
				recovery_good, int(expected_recovery_steps[recovery_good]),
				"" if int(expected_recovery_steps[recovery_good]) == 1 else "s",
			])
		Modifiers.reset()
		MatchState.reset()
		for recovery_title in recovery_titles:
			Modifiers.apply_unlock_modifier(str(recovery_title))
		var recovered: Dictionary = Modifiers.resolve_pct("recipe_output", "test", {"good_internal": recovery_good})
		_check(absf(float(recovered.get("net", 0.0))) < 0.001,
			"%s recovery research restores full output exactly" % recovery_good)
	Modifiers.reset()
	MatchState.reset()

func _test_workforce_output_modifier_surfaces_in_building_status() -> void:
	Modifiers.reset()
	MatchState.reset()
	var old_turn: int = int(TurnManager.current_turn)
	TurnManager.current_turn = 1
	var building := {
		"instance_id": "inst_status_workforce",
		"building_id": "b_007",
		"tile_id": "tile_5_10",
		"recipe_id": "r_009",
		"level": 1,
	}
	var recipe: Dictionary = Catalog.get_recipe("r_009")
	var base_output: int = int(recipe.get("output_qty", 0))
	_check(BuildingStatus.effective_output_qty(building, recipe) == base_output,
		"building status baseline output excludes inactive workforce policies")
	LabourState.set_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_ANNUAL_PROFIT_SHARE, true)
	var mod: Dictionary = BuildingStatus.net_output_modifier(building, recipe)
	var workforce_parts: Array = mod.get("workforce_parts", [])
	_check(BuildingStatus.effective_output_qty(building, recipe) == int(round(float(base_output) * 1.10)),
		"building status output includes annual profit-share workforce multiplier")
	_check(absf(float(mod.get("pct_f", 0.0)) - 10.0) < 0.001,
		"building status net output modifier includes annual profit share")
	var first_workforce_part: Dictionary = workforce_parts[0] if not workforce_parts.is_empty() else {}
	_check(workforce_parts.size() == 1 and str(first_workforce_part.get("label", "")) == "Annual Profit Share",
		"building status modifier breakdown lists annual profit share")
	_check(BuildingStatus._modifier_tooltip(mod).find("Annual Profit Share") >= 0,
		"building status tooltip includes annual profit share")
	LabourState.set_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_ANNUAL_PROFIT_SHARE, false)
	TurnManager.current_turn = old_turn
	Modifiers.reset()
	MatchState.reset()

func _test_recipe_labour_owns_cost() -> void:
	var old_turn: int = int(TurnManager.current_turn)
	TurnManager.current_turn = 1
	var recipe: Dictionary = Catalog.get_recipe("r_039")
	var building_data: Dictionary = Catalog.get_building_by_internal_name("electrolyser")
	var building := {
		"building_id": building_data.get("id", ""),
		"recipe_id": "r_039",
		"level": 1,
	}
	var expected := (
		float(recipe.get("labour_unskilled_required", 0)) * EconomyConfig.LABOUR_UNSKILLED_RATE
		+ float(recipe.get("labour_skilled_required", 0)) * EconomyConfig.LABOUR_SKILLED_RATE
		+ float(recipe.get("labour_h_skilled_required", 0)) * EconomyConfig.LABOUR_HIGH_SKILLED_RATE
	)
	_check(int(recipe.get("labour_unskilled_required", 0)) >= 500
		and int(recipe.get("labour_skilled_required", 0)) >= 100
		and int(recipe.get("labour_h_skilled_required", 0)) >= 50,
		"recipe labour: migrated rows retain the minimum crew")
	_check(is_equal_approx(Production._base_labour_cost(building, recipe), expected),
		"recipe labour: production cost uses the selected recipe, not the building default")
	TurnManager.current_turn = old_turn

func _test_additive_labour_cost_model() -> void:
	Modifiers.reset()
	MatchState.reset()
	var old_turn: int = int(TurnManager.current_turn)
	TurnManager.current_turn = 1
	# People-management unlocks now trim 10% each (was 5%).
	# Looked up BY TITLE through the accessor: UNLOCK_MODIFIERS is keyed by research_node_id
	# now, so indexing it with a title returns nothing.
	var otm: Dictionary = Modifiers.unlock_spec_for("Operational Team Managers")
	var shd: Dictionary = Modifiers.unlock_spec_for("Shift Handover Documentation")
	_check(float(otm.get("pct", 0.0)) == -10.0 and float(shd.get("pct", 0.0)) == -10.0,
		"labour unlocks: OTM and SHD each trim head-count by 10%")

	var iid := BuildingState.add_building("b_001", "r_001", "tile_6_8", MatchState.LOCAL_PLAYER, "test_additive_labour")
	var building: Dictionary = BuildingState.buildings[iid]
	LabourState.set_labour_multiplier(1.0)
	_check(is_equal_approx(Production.labour_cost_factor(building), 1.0),
		"labour factor: 100% of base with no modifiers")

	# Slider +20% and a -30% policy delta net to -10% off the 100% base (additive,
	# not the old compounded 0.8 x 1.2 x ...).
	LabourState.set_labour_multiplier(1.2)
	LabourState.workforce_policy_effects["test_policy"] = {"labour_pct": -0.30, "output_pct": 0.0, "active_turns": 1}
	_check(is_equal_approx(Production.labour_cost_factor(building), 0.90),
		"labour factor: slider and policy deltas add to base 100% (no compounding)")
	_check(is_equal_approx(Production._calculate_labour_cost(building), Production._base_labour_cost(building) * 0.90),
		"labour cost: base x additive factor")

	var ov: Dictionary = Production.labour_overview()
	_check(ov.has("current") and ov.has("est_10_turns") and ov.has("factor_pct") and ov.has("next_turn"),
		"labour overview: exposes current, next-turn, 10-turn estimate and factor %")

	LabourState.workforce_policy_effects.clear()
	LabourState.set_labour_multiplier(1.0)
	TurnManager.current_turn = old_turn
	Modifiers.reset()
	MatchState.reset()

func _test_labour_factor_floor() -> void:
	Modifiers.reset()
	MatchState.reset()
	var old_turn: int = int(TurnManager.current_turn)
	TurnManager.current_turn = 1
	var iid := BuildingState.add_building("b_001", "r_001", "tile_6_8", MatchState.LOCAL_PLAYER, "test_labour_floor")
	var building: Dictionary = BuildingState.buildings[iid]
	LabourState.set_labour_multiplier(1.0)
	# A -80% head-count reduction would drive the factor to 0.20; the floor clamps it.
	Modifiers.add({"id": "test_labour_floor", "domain": "labour_headcount", "pct": -80.0})
	_check(is_equal_approx(Production.labour_cost_factor(building), EconomyConfig.LABOUR_FACTOR_MIN),
		"labour floor: factor clamps to LABOUR_FACTOR_MIN (0.40) when reductions exceed it")
	_check(bool(Production.labour_overview().get("at_floor", false)),
		"labour floor: overview flags at_floor once the cap is reached")
	# The -60% debug cheat lands exactly on the floor (1 - 0.60 = 0.40).
	Modifiers.remove("test_labour_floor")
	Modifiers.add({"id": "cheat_labour_discount", "domain": "labour_headcount", "pct": -60.0})
	_check(is_equal_approx(Production.labour_cost_factor(building), EconomyConfig.LABOUR_FACTOR_MIN),
		"labour floor: -60% cheat lands exactly on the 40% floor")
	LabourState.set_labour_multiplier(1.0)
	TurnManager.current_turn = old_turn
	Modifiers.reset()
	MatchState.reset()

func _test_building_leveling() -> void:
	Modifiers.reset()
	MatchState.reset()
	Stockpile.clear_all()
	# --- Multipliers ---
	_check(absf(BuildingLevels.mult("output", 2) - 2.0) < 0.001 and absf(BuildingLevels.mult("output", 3) - 3.5) < 0.001,
		"output scales ×2 (L2) / ×3.5 (L3)")
	_check(absf(BuildingLevels.mult("energy", 2) - 1.8) < 0.001 and absf(BuildingLevels.mult("input", 3) - 3.0) < 0.001
			and absf(BuildingLevels.mult("labour", 3) - 2.0) < 0.001 and absf(BuildingLevels.mult("size", 2) - 1.8) < 0.001,
		"energy/input/labour/size multipliers match spec")
	# --- Production scaling (via power output + energy) ---
	var rec := {"recipe_id": "rp", "output_qty": 100, "recipe_type": "power", "output_name": "power", "energy_req": 50}
	_check(Production._effective_power_output({"building_id": "b_003", "level": 2}, rec) == 200, "L2 power output 100 → 200")
	_check(Production._effective_power_output({"building_id": "b_003", "level": 3}, rec) == 350, "L3 power output 100 → 350")
	_check(Production._effective_energy_req({"building_id": "b_003", "level": 2}, rec) == 90, "L2 energy draw 50 → 90 (×1.8)")
	# --- Upgrade materials ---
	var cp: Dictionary = BuildingLevels.upgrade_materials("chem_plant", 2)
	_check(int(cp.get("building_frame", 0)) == 2 and int(cp.get("construction_equipment_ice", 0)) == 1
			and int(cp.get("concrete", 0)) == 10 and int(cp.get("rubber", 0)) == 20 and int(cp.get("plastics", 0)) == 20,
		"chem plant L2 = base kit + 20 rubber + 20 plastics")
	var forest: Dictionary = BuildingLevels.upgrade_materials("new_forest", 2)
	_check(forest.has("biomass") and not forest.has("building_frame"), "forest upgrade is biomass only (no base kit)")
	var roads: Dictionary = BuildingLevels.upgrade_materials("roads", 2)
	_check(int(roads.get("construction_equipment_ice", 0)) == 2 and not roads.has("concrete"),
		"roads L2 = 2 construction equipment, no base kit")
	_check(BuildingLevels.research_gate("chem_plant", 2) == "Larger Reactor Trains"
			and BuildingLevels.research_gate("poly_plant", 2) == "",
		"research gates: chem plant gated, poly plant ungated")
	# --- Upgrade action (now a 3-turn project, not instant) ---
	var tile := "tile_up"
	BuildingState.tile_land_owned[tile] = 200
	var iid := BuildingState.add_building("b_012", "", tile)  # Chemical Plant, starts L1
	_check(int(BuildingState.get_building(iid).get("level", 1)) == 1, "a new building starts at Level 1")
	var r1: Dictionary = BuildingWorks.start_upgrade(iid, "tile")
	_check(not bool(r1.get("ok", false)) and str(r1.get("research", "")) == "Larger Reactor Trains",
		"upgrade is gated on the L2 research")
	ResearchState.grant_unlock("Larger Reactor Trains")
	var r2: Dictionary = BuildingWorks.start_upgrade(iid, "tile")
	_check(not bool(r2.get("ok", false)) and r2.has("missing"), "upgrade is blocked without materials on the tile")
	var rubber_gid := str(Catalog.get_good_by_internal_name("rubber").get("id", ""))
	for gi in BuildingLevels.upgrade_materials("chem_plant", 2):
		Stockpile.add(tile, str(Catalog.get_good_by_internal_name(str(gi)).get("id", "")), int(cp[gi]))
	# Preview reflects all-on-tile + the 3-turn duration before committing.
	var pv: Dictionary = BuildingWorks.preview_upgrade(iid)
	_check(bool(pv.get("ok", false)) and bool(pv.get("all_on_tile", false)) and int(pv.get("duration", 0)) == 3,
		"preview: all materials on tile, 3-turn duration")
	var r3: Dictionary = BuildingWorks.start_upgrade(iid, "tile")
	_check(bool(r3.get("ok", false)) and str(r3.get("status", "")) == BuildingWorks.UPGRADE_STATUS_UPGRADING,
		"upgrade starts (materials consumed) and is now in progress")
	_check(BuildingWorks.is_upgrading(iid) and int(BuildingState.get_building(iid).get("level", 1)) == 1,
		"level stays 1 while the 3-turn upgrade runs")
	var progress := BuildingWorks.upgrade_progress_snapshot(iid)
	_check(not bool(progress.get("blocked", true)) and int(progress.get("estimated_turns", 0)) == 3
			and str(progress.get("tooltip", "")).contains("Estimated completion: 3 turns"),
		"upgrade progress: active countdown exposes a three-turn completion estimate")
	var detail_panel = load("res://scripts/building_detail_panel_v2.gd").new()
	var upgrade_actions: HBoxContainer = detail_panel.call("_build_primary_actions", BuildingState.get_building(iid), Catalog.get_building("b_012"))
	var upgrading_button := upgrade_actions.find_child("UpgradeButton", true, false) as Button
	_check(upgrading_button != null and upgrading_button.disabled
			and upgrading_button.tooltip_text.contains("Estimated completion: 3 turns"),
		"upgrade button: disabled Upgrading state explains its estimated finish on hover")
	upgrade_actions.free()
	detail_panel.free()
	_check(Stockpile.get_at_tile(tile, rubber_gid) == 0, "upgrade materials consumed from the tile on start")
	_check(not bool(BuildingWorks.start_upgrade(iid, "tile").get("ok", false)), "cannot queue a second upgrade while one is pending")
	_check(BuildingWorks.reserved_upgrade_space_on_tile(tile) > 0.0, "in-progress upgrade reserves the growth footprint")
	BuildingWorks.tick_upgrades()
	BuildingWorks.tick_upgrades()
	_check(int(BuildingState.get_building(iid).get("level", 1)) == 1, "still Level 1 after 2 of 3 turns")
	var done: Array = BuildingWorks.tick_upgrades()
	_check(done.has(iid) and int(BuildingState.get_building(iid).get("level", 1)) == 2 and not BuildingWorks.is_upgrading(iid),
		"upgrade completes to L2 after 3 turns")
	BuildingState.remove_building(iid)

	# --- Awaiting-materials sourcing: claim arrivals off the tile, then count down ---
	var tile2 := "tile_up2"
	BuildingState.tile_land_owned[tile2] = 200
	ResearchState.grant_unlock("Larger Reactor Trains")
	var iid2 := BuildingState.add_building("b_012", "", tile2)
	BuildingWorks.pending_upgrades.append({
		"instance_id": iid2, "building_id": "b_012", "tile_id": tile2,
		"from_level": 1, "target_level": 2, "status": BuildingWorks.UPGRADE_STATUS_AWAITING,
		"missing": {rubber_gid: 20}, "turns_remaining": 3, "size_delta": 0.0,
	})
	BuildingWorks.tick_upgrades()  # nothing on the tile yet → stays awaiting, no countdown
	_check(str(BuildingWorks.pending_upgrade(iid2).get("status", "")) == BuildingWorks.UPGRADE_STATUS_AWAITING
			and int(BuildingWorks.pending_upgrade(iid2).get("turns_remaining", 0)) == 3,
		"awaiting upgrade holds until materials arrive")
	progress = BuildingWorks.upgrade_progress_snapshot(iid2)
	_check(bool(progress.get("blocked", false)) and int(progress.get("estimated_turns", 0)) == -1,
		"upgrade progress: an awaiting kit with nothing on tile or in transit is blocked")
	var blocked_rows: Array = BuildingReadout.diagnostics(BuildingState.get_building(iid2),
		Catalog.get_recipe(str(BuildingState.get_building(iid2).get("recipe_id", ""))), Catalog.get_building("b_012"), false)
	var found_upgrade_fault := false
	for row in blocked_rows:
		found_upgrade_fault = found_upgrade_fault or (str((row as Dictionary).get("label", "")) == "Cannot deliver upgrade materials"
				and str((row as Dictionary).get("tone", "")) == "bad")
	_check(found_upgrade_fault,
		"building diagnostics: a blocked upgrade gets a red material-delivery reason")
	var upgrade_shipment := {
		"destination_tile": tile2, "good_id": rubber_gid, "qty": 20,
		"turns_remaining": 2, "upgrade_instance_id": iid2,
	}
	TransportState.pending_transport_shipments.append(upgrade_shipment)
	progress = BuildingWorks.upgrade_progress_snapshot(iid2)
	_check(not bool(progress.get("blocked", true)) and int(progress.get("estimated_turns", 0)) == 5,
		"upgrade progress: material lead time plus build countdown gives the completion estimate")
	TransportState.pending_transport_shipments.erase(upgrade_shipment)
	Stockpile.add(tile2, rubber_gid, 20)
	BuildingWorks.tick_upgrades()  # claims the rubber → becomes upgrading (countdown not yet ticked)
	_check(str(BuildingWorks.pending_upgrade(iid2).get("status", "")) == BuildingWorks.UPGRADE_STATUS_UPGRADING
			and Stockpile.get_at_tile(tile2, rubber_gid) == 0,
		"awaiting upgrade claims arrived materials and starts the countdown")
	BuildingWorks.tick_upgrades(); BuildingWorks.tick_upgrades(); BuildingWorks.tick_upgrades()
	_check(int(BuildingState.get_building(iid2).get("level", 1)) == 2, "sourced-then-built upgrade completes to L2")
	BuildingState.remove_building(iid2)

	# --- Atomic start: market sourcing with no port/funds consumes nothing ---
	var tile3 := "tile_up3"
	BuildingState.tile_land_owned[tile3] = 200
	ResearchState.grant_unlock("Larger Reactor Trains")
	var iid3 := BuildingState.add_building("b_012", "", tile3)
	# Put only HALF of one material on the tile; the rest would have to be sourced.
	Stockpile.add(tile3, rubber_gid, 5)
	MatchState.money = 0  # broke → market order must be refused
	var rm: Dictionary = BuildingWorks.start_upgrade(iid3, "market")
	_check(not bool(rm.get("ok", false)) and not BuildingWorks.is_upgrading(iid3)
			and Stockpile.get_at_tile(tile3, rubber_gid) == 5,
		"failed market start is atomic: nothing consumed, no pending upgrade")
	BuildingState.remove_building(iid3)

	# --- Cancel refunds banked materials ---
	var tile4 := "tile_up4"
	BuildingState.tile_land_owned[tile4] = 200
	ResearchState.grant_unlock("Larger Reactor Trains")
	var iid4 := BuildingState.add_building("b_012", "", tile4)
	for gi in BuildingLevels.upgrade_materials("chem_plant", 2):
		Stockpile.add(tile4, str(Catalog.get_good_by_internal_name(str(gi)).get("id", "")), int(cp[gi]))
	BuildingWorks.start_upgrade(iid4, "tile")  # consumes the whole kit off the tile
	_check(Stockpile.get_at_tile(tile4, rubber_gid) == 0, "tile-mode start consumed the kit")
	_check(BuildingWorks.cancel_upgrade(iid4) and not BuildingWorks.is_upgrading(iid4)
			and Stockpile.get_at_tile(tile4, rubber_gid) == int(cp["rubber"]),
		"cancel refunds the banked materials and clears the pending upgrade")
	BuildingState.remove_building(iid4)

	# --- Preview: non-integer energy + cost-of-production per unit ---
	var tile5 := "tile_up5"
	BuildingState.tile_land_owned[tile5] = 200
	ResearchState.grant_unlock("Larger Reactor Trains")
	var iid5 := BuildingState.add_building("b_012", "r_012", tile5)  # Chlor-Alkali chem plant
	var pv5: Dictionary = BuildingWorks.preview_upgrade(iid5)
	var en = pv5.get("stats", {}).get("cur", {}).get("energy", null)
	_check(en != null and typeof(en) == TYPE_FLOAT, "preview energy is a float (non-integer power allowed)")
	var ucp: Dictionary = pv5.get("unit_cost", {})
	_check(ucp.has("cur") and ucp.has("new"), "preview includes cost-of-production-per-unit (cur→new)")
	# The cost report (fed to CostSolver) must scale inputs/outputs by level, or the live unit
	# cost is inflated after an upgrade (levelled fixed costs ÷ un-scaled output).
	Production._building_turn_reports.clear()
	Production._capture_turn_report({"instance_id": "rt", "building_id": "b_012", "tile_id": "tT", "level": 2}, Catalog.get_recipe("r_012"))
	var rep: Dictionary = Production._building_turn_reports[-1]
	var r012: Dictionary = Catalog.get_recipe("r_012")
	var base_out := 0
	for o in r012.get("outputs", []):
		base_out += int(o.get("qty", 0))
	var rep_out := 0
	for gid in (rep.get("outputs_produced", {}) as Dictionary):
		rep_out += int(rep["outputs_produced"][gid])
	var base_in := 0
	for inp in r012.get("inputs", []):
		base_in += int(inp.get("qty", 0))
	var rep_in := 0
	for gid in (rep.get("inputs_consumed", {}) as Dictionary):
		rep_in += int(rep["inputs_consumed"][gid])
	_check(base_out > 0 and rep_out == base_out * 2, "cost report scales output by level (×2 at L2)")
	_check(base_in > 0 and rep_in == base_in * 2, "cost report scales inputs by level (×2 at L2)")
	Production._building_turn_reports.clear()
	BuildingState.remove_building(iid5)

	# The live run gate and stock reservations must scale inputs too. Otherwise an L2/L3
	# building can run with only its L1 recipe inputs on hand, and auto-sell can treat the
	# extra upgraded demand as surplus.
	var scaled_tile := "tile_scaled_inputs"
	BuildingState.tile_land_owned[scaled_tile] = 200
	var scaled_iid := BuildingState.add_building("b_012", "r_012", scaled_tile, MatchState.LOCAL_PLAYER, "inst_scaled_inputs")
	var scaled_building: Dictionary = BuildingState.buildings[scaled_iid]
	scaled_building["level"] = 2
	BuildingState.buildings[scaled_iid] = scaled_building
	var scaled_recipe: Dictionary = Catalog.get_recipe("r_012").duplicate(true)
	scaled_recipe["energy_req"] = 0
	var scaled_input: Dictionary = (scaled_recipe.get("inputs", []) as Array)[0]
	scaled_recipe["inputs"] = [scaled_input]
	var scaled_gid := str(scaled_input.get("good_id", ""))
	var base_need := int(scaled_input.get("qty", 0))
	var scaled_need := int(round(float(base_need) * BuildingLevels.mult("input", 2)))
	Stockpile.add(scaled_tile, scaled_gid, base_need)
	var scaled_check: Dictionary = Production._can_run_recipe(BuildingState.buildings[scaled_iid], scaled_recipe)
	var scaled_missing: Array = scaled_check.get("missing", [])
	_check(not bool(scaled_check.get("can_run", false))
			and not scaled_missing.is_empty()
			and int((scaled_missing[0] as Dictionary).get("need", 0)) == scaled_need,
		"L2 input gate requires scaled inputs (need %d, not L1's %d)" % [scaled_need, base_need])
	Stockpile.add(scaled_tile, scaled_gid, scaled_need - base_need)
	scaled_check = Production._can_run_recipe(BuildingState.buildings[scaled_iid], scaled_recipe)
	_check(bool(scaled_check.get("can_run", false)), "L2 input gate clears once scaled inputs are stocked")
	var committed_scaled: Dictionary = Production.compute_committed_for_tile(scaled_tile)
	_check(int(committed_scaled.get(scaled_gid, 0)) == scaled_need, "committed input reserve scales with building level")
	var scaled_summary := {"consumed": {}}
	Production._consume_inputs(BuildingState.buildings[scaled_iid], scaled_recipe, scaled_summary)
	_check(Stockpile.get_at_tile(scaled_tile, scaled_gid) == 0
			and int((scaled_summary.get("consumed", {}) as Dictionary).get(scaled_gid, 0)) == scaled_need,
		"L2 consume_inputs consumes the scaled input quantity")
	BuildingState.remove_building(scaled_iid)

	Modifiers.reset()
	MatchState.reset()
	Stockpile.clear_all()

func _test_run_failure_warnings() -> void:
	Modifiers.reset()
	MatchState.reset()
	Stockpile.clear_all()
	Production.blocked_reason_by_building.clear()
	Production._just_constructed_this_turn.clear()

	var tile := "tile_3_8"
	var iid := BuildingState.add_building("b_012", "r_012", tile, MatchState.LOCAL_PLAYER, "inst_run_warning")
	var building: Dictionary = BuildingState.buildings[iid]
	var recipe: Dictionary = Catalog.get_recipe("r_012").duplicate(true)
	recipe["energy_req"] = 0
	var input: Dictionary = (recipe.get("inputs", []) as Array)[0]
	recipe["inputs"] = [input]
	var gid := str(input.get("good_id", ""))
	var need := int(input.get("qty", 0))
	var check: Dictionary = Production._can_run_recipe(building, recipe)

	MatchState.money = 0.0
	var market_reason: Dictionary = Production._blocked_reason_for(building, recipe, check.get("missing", []))
	_check(str(market_reason.get("message", "")).begins_with("Insufficient money to order inputs. Needed £"),
		"run warning: market-sourced missing inputs report insufficient cash")

	MatchState.money = 100000.0
	TransportState.overflow_shipments.append({"destination_tile": tile, "good_id": gid, "qty": need})
	var overflow_reason: Dictionary = Production._blocked_reason_for(building, recipe, check.get("missing", []))
	_check(str(overflow_reason.get("message", "")) == "Shipments did not reach building. Tile stockpile full.",
		"run warning: overflow shipment wins over generic missing input")
	TransportState.overflow_shipments.clear()

	MatchState.set_input_tile_only(iid, gid, true)
	var tile_only_reason: Dictionary = Production._blocked_reason_for(building, recipe, check.get("missing", []))
	_check(str(tile_only_reason.get("message", "")) == "Insufficient inputs in stockpile to run recipe. Needed %d." % need,
		"run warning: tile-stockpile-only missing input reports shortfall")
	MatchState.set_input_tile_only(iid, gid, false)

	var battery_iid := BuildingState.add_building("b_028", "r_225", tile, MatchState.LOCAL_PLAYER, "inst_run_warning_battery")
	var battery_reason: Dictionary = Production.run_warning_for_building(BuildingState.buildings[battery_iid], Catalog.get_recipe("r_225"))
	_check(str(battery_reason.get("message", "")) == "Batteries missing. Fill storage to run.",
		"run warning: empty battery storage asks for cells")

	BuildingState.remove_building(iid)
	BuildingState.remove_building(battery_iid)
	Modifiers.reset()
	MatchState.reset()
	Stockpile.clear_all()
	Production.blocked_reason_by_building.clear()
	Production._just_constructed_this_turn.clear()

# Identical notifications fold into display groups by reason; dismiss_group
# clears only its own members.
# Survey-complete notifications collapse into one "N Surveys Completed" card,
# and each member carries the tile + revealed deposits.
func _test_survey_grouping() -> void:
	EventScheduler.reset()
	TurnManager.current_turn = 1
	EventScheduler._on_survey_completed("tile_6_8", [{"internal_name": "coal"}])
	EventScheduler._on_survey_completed("tile_7_10", [{"internal_name": "iron_ore"}])
	var groups := EventScheduler.grouped_active()
	var survey_group := {}
	for g in groups:
		if str(g.group_key) == "surveys_complete":
			survey_group = g
	_check(not survey_group.is_empty() and (survey_group.members as Array).size() == 2,
		"two surveys fold into one group")
	_check(str(survey_group.get("title", "")) == "Surveys Completed",
		"survey group title is 'Surveys Completed'")
	var m: Dictionary = (survey_group.members as Array)[0]
	_check(str(m.get("where", "")) == "coal" or str(m.get("where", "")) == "iron_ore",
		"survey member carries the revealed deposit in `where`")
	EventScheduler.reset()

func _test_building_resnap() -> void:
	var nav := NavGrid.instance()
	if not nav.is_ready():
		return
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	var tile_id := "tile_9_10"
	var coord: Vector2i = terrain.id_to_coord(tile_id)
	if not terrain.tiles.has(coord):
		_check(false, "resnap: test tile exists")
		terrain.queue_free()
		return
	var center: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
	# Force the tile roadless to start (a reference into terrain.tiles).
	var td: Dictionary = terrain.tiles[coord]
	td["infrastructure_present"] = []

	RoadNetwork.reset()
	var net := RoadNetwork.instance()

	var bv := preload("res://scenes/building_visuals.gd").new()
	add_child(bv)
	await get_tree().process_frame
	bv.terrain_layer = terrain   # set AFTER _ready (no %TerrainLayer to resolve in a test)

	_check(RoadWorks.order_settled.is_connected(Callable(bv, "_on_road_settled")),
		"resnap: building_visuals subscribes to RoadWorks.order_settled")

	# Place one building while the tile has no road — it lands via the fallback.
	var iid: String = BuildingState.add_building("b_test_factory", "", tile_id, "npc", "resnap_b0")
	bv.on_building_placed(tile_id, "b_test_factory", "", iid, coord)
	var idx0: int = int(bv._placement_index.get(iid, -1))
	if idx0 < 0:
		_check(false, "resnap: building placed on roadless tile")
		BuildingState.remove_building(iid)
		bv.queue_free()
		terrain.queue_free()
		RoadNetwork.reset()
		RoadNetwork.bootstrap_from_bake()
		return
	var before_rel: Vector2 = bv._placements[idx0].center_rel
	_check((bv._tile_road_segments(coord, center) as Array).is_empty(), "resnap: tile starts with no road frontage")

	# Build a road across the UPPER third of the tile (local frame y = -150).
	td["infrastructure_present"] = ["roads"]
	var ra: Dictionary = net.ensure_node("rs:a", RoadNetwork.KIND_JUNCTION, center + Vector2(-150, -150), coord)
	var rb: Dictionary = net.ensure_node("rs:b", RoadNetwork.KIND_JUNCTION, center + Vector2(150, -150), coord)
	var geo := PackedVector2Array([center + Vector2(-150, -150), center + Vector2(150, -150)])
	net.add_edge(str(ra.id), str(rb.id), RoadNetwork.TIER_LOCAL, geo, [coord], [], 1, RoadNetwork.STATE_BUILT)
	_check((bv._tile_road_segments(coord, center) as Array).size() > 0, "resnap: built road now visible to the packer")

	# Re-snap the tile (this is what order_settled triggers via _flush_resnap). The road at y=-150 is FAR
	# from the building (which landed mid-tile), so occupancy keeps it PUT — the road routes around it.
	bv.relayout_tile(tile_id)
	var idx1: int = int(bv._placement_index.get(iid, -1))
	_check(idx1 >= 0, "resnap: building survives the re-pack")
	if idx1 >= 0:
		var after_rel: Vector2 = bv._placements[idx1].center_rel
		_check(after_rel.distance_to(before_rel) < 1.0, "resnap: a building the road doesn't touch STAYS PUT (occupancy: y %.0f -> %.0f)" % [before_rel.y, after_rel.y])
	# Now build a road straight THROUGH the building — it overlaps, so it must be re-packed off the road.
	var oa: Dictionary = net.ensure_node("ro:a", RoadNetwork.KIND_JUNCTION, center + before_rel + Vector2(-150, 0), coord)
	var ob: Dictionary = net.ensure_node("ro:b", RoadNetwork.KIND_JUNCTION, center + before_rel + Vector2(150, 0), coord)
	net.add_edge(str(oa.id), str(ob.id), RoadNetwork.TIER_LOCAL, PackedVector2Array([center + before_rel + Vector2(-150, 0), center + before_rel + Vector2(150, 0)]), [coord], [], 1, RoadNetwork.STATE_BUILT)
	bv.relayout_tile(tile_id)
	var idx2: int = int(bv._placement_index.get(iid, -1))
	if idx2 >= 0:
		var after2: Vector2 = bv._placements[idx2].center_rel
		_check(after2.distance_to(before_rel) > 5.0, "resnap: a building the road OVERLAPS is re-packed off it (moved %.0fu)" % after2.distance_to(before_rel))

	BuildingState.remove_building(iid)
	bv.queue_free()
	terrain.queue_free()
	RoadNetwork.reset()
	RoadNetwork.bootstrap_from_bake()
	await get_tree().process_frame

func _test_level_storeys_and_owner_swap() -> void:
	var nav := NavGrid.instance()
	if not nav.is_ready():
		return
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	RoadNetwork.reset()
	var bv := preload("res://scenes/building_visuals.gd").new()
	add_child(bv)
	await get_tree().process_frame
	bv.terrain_layer = terrain
	var tile_id := "tile_9_10"
	var coord: Vector2i = terrain.id_to_coord(tile_id)
	if not terrain.tiles.has(coord):
		_check(false, "storeys: test tile exists")
		bv.queue_free(); terrain.queue_free(); RoadNetwork.reset(); return
	var iid := BuildingState.add_building("b_001", "", tile_id, "npc", "storey_test", false)
	bv.on_building_placed(tile_id, "b_001", "", iid, coord)
	bv._flush_subcomponents()
	var count_l1 := 0
	for sc in bv._subcomponents:
		if str(sc.kind) == "storey" and str(sc.iid) == iid:
			count_l1 += 1
	_check(count_l1 == 0, "storeys: none at level 1")
	# L3 → two stacked storey blocks, regardless of crowding or masses.
	(BuildingState.buildings[iid] as Dictionary)["level"] = 3
	bv._rebuild_subcomponents(tile_id)
	var count_l3 := 0
	var wings_l3 := 0
	for sc2 in bv._subcomponents:
		if str(sc2.iid) == iid:
			if str(sc2.kind) == "storey":
				count_l3 += 1
			elif str(sc2.kind) == "wing":
				wings_l3 += 1
	_check(count_l3 == 2, "storeys: two blocks at level 3")
	# Open ground + L3 must grow at least one wing — L/C footprints once
	# skipped wings entirely (quad-only axis math).
	_check(wings_l3 >= 1, "wings: upgraded building spreads on open ground")
	# Ownership swap flips the placement's is_npc (bought buildings recolour).
	var idx: int = bv._placement_index[iid]
	_check(bool((bv._placements[idx] as Dictionary).is_npc), "owner swap: starts NPC")
	(BuildingState.buildings[iid] as Dictionary)["owner"] = MatchState.LOCAL_PLAYER
	bv._on_building_owner_changed(iid)
	_check(not bool((bv._placements[idx] as Dictionary).is_npc), "owner swap: placement follows the sale")
	BuildingState.remove_building(iid)
	bv.queue_free()
	terrain.queue_free()
	RoadNetwork.reset()
	await get_tree().process_frame

# ── Land readout vs the build gate (owner 2026-08-23: "why did the chart show capacity?") ──
func _test_land_readout_matches_gate() -> void:
	var TileViewData := preload("res://scripts/tile_view_data.gd")
	MatchState.reset()
	var tile := "tile_5_10"
	var tile_data: Dictionary = {"id": tile, "type": Catalog.tile_type(tile)}

	# A player building and an NPC one on the same tile. The NPC footprint is the thing that
	# made the readout look wrong: it eats the tile's physical space without ever counting
	# against the land the player owns.
	BuildingState.add_building("b_009", "", tile, "player_1", "land_p1", false)
	BuildingState.add_building("b_009", "", tile, "ai_corp", "land_npc", false)
	# Land starts at 0 owned, which would leave FREE clamped at 0 and test nothing. Give the
	# player real headroom, which is also the state a tile is in when this question arises.
	BuildingState.tile_land_owned[tile] = 60
	var totals: Dictionary = TileViewData.land_totals(tile, tile_data)
	var owned: int = BuildingState.get_tile_land_owned(tile)

	# BUILT counts only the player. The chart used to be read as though it counted everything.
	_check(absf(float(totals.built) - BuildingState.get_tile_player_space_used(tile)) < 0.51,
		"land readout: BUILT is the player's footprint, matching the gate's own figure")
	_check(int(totals.max) < BuildingState.max_tile_land(tile),
		"land readout: MAX is the tile's capacity LESS the NPC buildings sitting on it")

	# FREE is the figure that decides a build, and it must agree with the gate exactly: a
	# building whose growth fits FREE is allowed, and one unit more is refused.
	var free: int = int(totals.free)
	_check(free > 0 and free == maxi(0, mini(owned, int(totals.max)) - int(totals.built)),
		"land readout: FREE is the binding gate — owned or physical, whichever is smaller")

	var used_before: float = BuildingState.get_tile_space_used(tile)
	var cap: int = BuildingState.max_tile_land(tile)
	var player_used: float = BuildingState.get_tile_player_space_used(tile)
	var fits_exactly: bool = (used_before + float(free) <= float(cap)
		and player_used + float(free) <= float(owned))
	var one_over_fails: bool = not (used_before + float(free + 1) <= float(cap)
		and player_used + float(free + 1) <= float(owned))
	_check(fits_exactly and one_over_fails,
		"land readout: exactly FREE more fits and one more does not — chart and gate agree")
	# THE BAR. Its drawn segments must add up to the same space the gate counts, or it shows
	# headroom that is not there. It used to omit the room an in-progress upgrade had already
	# reserved — the caption counted it, the bar did not, and the gap under the cap line was a
	# lie by exactly that much.
	var chart: Dictionary = TileViewData.land_chart_data(tile, tile_data)
	var drawn := 0.0
	for seg_variant: Variant in (chart.segments as Array):
		drawn += float((seg_variant as Dictionary).get("size", 0.0))
	_check(absf(drawn - BuildingState.get_tile_space_used(tile)) < 0.01,
		"land chart: the drawn bar sums to exactly the space the build gate counts")

	# ...including while an upgrade is running, which is the case that was wrong.
	BuildingWorks.pending_upgrades.append({
		"instance_id": "land_p1", "building_id": "b_009", "tile_id": tile,
		"from_level": 1, "target_level": 2, "status": "upgrading",
		"turns_remaining": 3, "size_delta": 12.0, "missing": {},
	})
	var chart_up: Dictionary = TileViewData.land_chart_data(tile, tile_data)
	var drawn_up := 0.0
	for seg_variant: Variant in (chart_up.segments as Array):
		drawn_up += float((seg_variant as Dictionary).get("size", 0.0))
	_check(absf(drawn_up - drawn - 12.0) < 0.01,
		"land chart: an upgrade in progress is drawn, not left as empty space")
	_check(absf(drawn_up - BuildingState.get_tile_space_used(tile)) < 0.01,
		"land chart: bar and gate still agree while an upgrade is running")
	var totals_up: Dictionary = TileViewData.land_totals(tile, tile_data)
	_check(int(totals_up.free) == int(totals.free) - 12,
		"land readout: FREE drops by the room the upgrade reserved")
	BuildingWorks.pending_upgrades.clear()

	MatchState.reset()

# --- Demolition/pause, liquidation, grace loans, solvency (features 1/2/3/5/6) --------
func _test_building_pause() -> void:
	BuildingState.buildings["test_pause_b"] = {"instance_id": "test_pause_b",
		"building_id": "b_001", "recipe_id": "", "tile_id": "tile_1_1", "owner": MatchState.LOCAL_PLAYER}
	_check(not BuildingWorks.is_building_paused("test_pause_b"), "pause: buildings start unpaused")
	BuildingWorks.set_building_paused("test_pause_b", true)
	_check(BuildingWorks.is_building_paused("test_pause_b"), "pause: set_building_paused pauses it")
	_check((MatchState.export_state().get("paused_buildings", {}) as Dictionary).has("test_pause_b"),
		"pause: paused set is exported in the save state")
	BuildingState.remove_building("test_pause_b")
	_check(not BuildingWorks.paused_buildings.has("test_pause_b"),
		"pause: pause flag is cleared when the building is removed")

func _test_deposit_running_out_warning() -> void:
	# A mine within Production.DEPOSIT_WARNING_TURNS of exhausting its deposit raises an
	# AMBER diagnostics row (with the ore's icon) and a DISMISSIBLE briefing warning.
	# Exhaustion used to be silent — the input bill just doubled with no notice.
	var saved: Dictionary = Production.last_turn_summary.duplicate(true)
	var coal := str(Catalog.get_good_by_internal_name("coal").get("id", ""))
	Production.last_turn_summary = {"deposits_running_out": [{
		"tile_id": "tile_6_8", "instance_id": "diag_mine", "building_id": "b_001",
		"token": "coal", "good_id": coal, "remaining": 180, "per_turn": 60, "turns_left": 3,
	}]}
	var readout = load("res://scripts/building_readout.gd")
	var mine := {"instance_id": "diag_mine", "tile_id": "tile_6_8", "building_id": "b_001",
		"recipe_id": "r_001", "level": 1, "owner": "player_1"}
	var rows: Array = readout.diagnostics(mine, Catalog.get_recipe("r_001"), Catalog.get_building("b_001"), false)
	var found: Dictionary = {}
	for r in rows:
		if str(r.get("label", "")) == "Deposit running out":
			found = r
	_check(not found.is_empty(), "diagnostics: a nearly-empty deposit raises its own row")
	_check(str(found.get("tone", "")) == "warn", "diagnostics: the deposit warning is amber, not a fault")
	_check(str(found.get("good_id", "")) == coal, "diagnostics: the row carries the ORE's good id for its icon")
	_check(str(found.get("detail", "")).contains("3 turn"), "diagnostics: the row states the turns remaining")
	# The briefing update: warning severity, dismissible, and iconned with the same good.
	var item: Dictionary = TurnBriefing._deposit_running_out_item()
	_check(str(item.get("severity", "")) == "warning", "briefing: deposit update is a warning")
	_check(bool(item.get("dismissible", false)), "briefing: deposit update can be dismissed")
	_check(str(item.get("icon_good_id", "")) == coal, "briefing: deposit update uses the ore's icon")
	_check(str(item.get("title", "")).contains("3 turn"), "briefing: title counts down the turns")
	# Dismissing silences it, but a SECOND mine running out re-raises it. Drive the gate
	# directly — dismiss() resolves the id through the live item list, which the panel
	# builds and this harness does not.
	TurnBriefing._alert_dismissed[str(item.get("id", ""))] = int(item.get("magnitude", 0))
	_check(TurnBriefing._deposit_running_out_item().is_empty(), "briefing: dismissal silences the update")
	(Production.last_turn_summary["deposits_running_out"] as Array).append({
		"tile_id": "tile_7_10", "instance_id": "diag_mine_2", "building_id": "b_001",
		"token": "iron_ore", "good_id": str(Catalog.get_good_by_internal_name("iron_ore").get("id", "")),
		"remaining": 120, "per_turn": 40, "turns_left": 3,
	})
	_check(not TurnBriefing._deposit_running_out_item().is_empty(),
		"briefing: a SECOND mine running out re-raises the dismissed update")
	Production.last_turn_summary = {"deposits_running_out": []}
	_check(TurnBriefing._deposit_running_out_item().is_empty(), "briefing: clears when no deposit is low")
	Production.last_turn_summary = saved

func _test_building_diagnostics() -> void:
	# New BDP diagnostics: cable-overload for power producers, stockpile-over-utilised
	# for non-power producers (docs/co2-tax spec follow-ups).
	var readout = load("res://scripts/building_readout.gd")

	# Power producer crowded out by the cable export cap: _can_run_recipe records a
	# "power" missing entry → "Cannot push power" fault + "Cables overloaded" row.
	var plant := {"instance_id": "diag_plant", "tile_id": "tile_9_9", "building_id": "b_003", "recipe_id": "r_004", "level": 1, "owner": "player_1"}
	Production.missing_by_building["diag_plant"] = [{"good_id": "power", "internal_name": "power", "need": 1000, "have": 2000}]
	var rows: Array = readout.diagnostics(plant, Catalog.get_recipe("r_004"), Catalog.get_building("b_003"), false)
	var titles: Array = []
	for r in rows:
		titles.append(str(r.get("label", "")))
	_check(titles.has("Power output capped"), "diagnostics: cable-capped plant shows the 'Power output capped' row")
	_check(not titles.has("Generating power"), "diagnostics: blocked plant doesn't claim to be generating")
	# AMBER, not red — the plant is throttled, not faulted.
	var capped_tone := ""
	var capped_detail := ""
	for r in rows:
		if str(r.get("label", "")) == "Power output capped":
			capped_tone = str(r.get("tone", ""))
			capped_detail = str(r.get("detail", ""))
	_check(capped_tone == "warn", "diagnostics: the cable cap reads amber, not a critical fault")
	_check(capped_detail.begins_with("Power output capped because of cabling."),
		"diagnostics: cable-cap detail leads with the cause")
	_check(capped_detail.contains("MW produced"), "diagnostics: cable-cap detail reports produced/capacity")
	# The plant's run_state is "restarting" (its power "input" is unmet), and the cap row
	# must WIN that race — otherwise a permanently throttled plant cheerfully reports
	# "Starting — production begins next turn" forever.
	_check(not titles.has("Starting"), "diagnostics: the cable cap outranks the 'Starting' row")
	# Below max cable level the advice is actionable; at max there is nothing to upgrade.
	if Power.cable_level_is_max("tile_9_9"):
		_check(capped_detail.ends_with("Max power capacity reached for this tile."),
			"diagnostics: at max cable level the row stops offering an upgrade")
	else:
		_check(capped_detail.ends_with("Upgrade cables to increase tile capacity."),
			"diagnostics: below max cable level the row tells the player to upgrade")
	Production.missing_by_building.erase("diag_plant")
	rows = readout.diagnostics(plant, Catalog.get_recipe("r_004"), Catalog.get_building("b_003"), false)
	titles = []
	for r in rows:
		titles.append(str(r.get("label", "")))
	_check(not titles.has("Power output capped"), "diagnostics: unblocked plant has no cable-cap row")

	# Non-power producer on a FULL tile warehouse → stockpile over-utilised row.
	var mill := {"instance_id": "diag_mill", "tile_id": "tile_8_8", "building_id": "b_002", "recipe_id": "r_002", "level": 1, "owner": "player_1"}
	var mill_recipe: Dictionary = Catalog.get_recipe(str(Catalog.get_recipes_for_building("b_002")[0].get("recipe_id", "")))
	var coal_id := str(Catalog.get_good_by_internal_name("coal").get("id", ""))
	var cap: int = Stockpile.get_capacity("tile_8_8")
	var before: int = Stockpile.get_used_capacity("tile_8_8")
	Stockpile.add("tile_8_8", coal_id, cap - before)   # fill to the brim
	rows = readout.diagnostics(mill, mill_recipe, Catalog.get_building("b_002"), false)
	titles = []
	for r in rows:
		titles.append(str(r.get("label", "")))
	_check(titles.has("Stockpile over-utilised"), "diagnostics: full warehouse shows the over-utilised row")
	Stockpile.consume("tile_8_8", coal_id, cap - before)
	rows = readout.diagnostics(mill, mill_recipe, Catalog.get_building("b_002"), false)
	titles = []
	for r in rows:
		titles.append(str(r.get("label", "")))
	_check(not titles.has("Stockpile over-utilised"), "diagnostics: cleared warehouse drops the row")

	# The "Output modifiers" row was removed from diagnostics (owner request 2026-07-13).
	# Even with an active recipe_output modifier — which used to produce that row plus a
	# "See all modifiers" accordion (the row carried a "parts" array) — none appears now.
	var building_status = load("res://scripts/building_status.gd")
	var mod_id: String = Modifiers.add({"domain": "recipe_output", "target": "*", "pct": 12.0, "label": "Test output boost"})
	var net_parts: Array = building_status.net_output_modifier(mill, mill_recipe).get("parts", [])
	_check(not net_parts.is_empty(), "diagnostics: precondition — a recipe_output modifier is active on the recipe")
	rows = readout.diagnostics(mill, mill_recipe, Catalog.get_building("b_002"), false)
	var has_mod_row := false
	var has_parts := false
	for r in rows:
		if str(r.get("label", "")).begins_with("Output modifiers"):
			has_mod_row = true
		if r.has("parts"):
			has_parts = true
	_check(not has_mod_row, "diagnostics: no 'Output modifiers' row even with an active modifier")
	_check(not has_parts, "diagnostics: no diagnostics row carries a modifier 'parts' accordion")
	Modifiers.remove(mod_id)
