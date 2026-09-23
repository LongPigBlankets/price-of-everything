extends "res://tests/test_base.gd"
## Power generation, grid settlement, batteries and intermittency.

const FEATURE := "power"
## Tests that also belong to other features (run under any of their tags).
const TAGS := {
	"_test_cable_power_cap": ["power", "research"],
	"_test_power_network_settlement": ["power", "research"],
	"_test_power_output_modifier": ["power", "production", "research"],
	"_test_power_quality": ["power", "production"],
	"_test_power_instance_age": ["power", "production"],
	"_test_power_intermittency_alloc": ["power", "production"],
	"_test_intermittency_tile_aggregate": ["power", "production"],
	"_test_battery_deposit": ["power", "production", "stockpile"],
	"_test_battery_fill_pending": ["power", "stockpile"],
	"_test_power_capped_alert": ["events", "power", "production"],
}

func _test_battery_fill_scope_and_units() -> void:
	# Two bugs, one root: the battery panel is opened on ONE building but every figure it used
	# was tile-wide (owner 2026-08-01).
	#  (a) "Fill from market" sized the order from the TILE's headroom, so a tile with several
	#      batteries ordered for all of them from whichever one you clicked.
	#  (b) The cream card read "36 / 2000" — a CELL COUNT over a MEGAWATT capacity.
	# NON-DESTRUCTIVE: no MatchState.reset(). reset() wipes the NPC-port / scene state that
	# later tests assert against (see the same warning on _test_warehouse_storage_levels) —
	# doing it here took out two unrelated port tests.
	var tile := "tile_batt_test_only"
	var a := BuildingState.add_building("b_028", "", tile, MatchState.LOCAL_PLAYER, "batt_a")
	var b2 := BuildingState.add_building("b_028", "", tile, MatchState.LOCAL_PLAYER, "batt_b")
	var one_cap: int = int(EconomyConfig.BATTERY_STORAGE_CAP.get(1, 0))
	_check(Power.tile_battery_slots(tile) == one_cap * 2,
		"battery: two L1 batteries give the tile twice one battery's capacity")
	var gid := ""
	for internal in EconomyConfig.BATTERY_CELL_DENSITY:
		var g := str(Catalog.get_good_by_internal_name(str(internal)).get("id", ""))
		if g != "":
			gid = g
			break
	if gid == "":
		_check(false, "battery: a cell good exists to test with")
		return
	var tile_fill: int = Power.battery_cells_to_fill(tile, gid)
	var one_fill: int = Power.battery_cells_to_fill(tile, gid, a)
	_check(tile_fill > 0 and one_fill > 0, "battery: both fills are positive")
	_check(one_fill * 2 == tile_fill,
		"battery: filling ONE battery orders half a two-battery tile's total (%d vs %d)" % [one_fill, tile_fill])
	# (b) the card's two numbers must now share a unit: MW firmed over MW capacity.
	var r: Dictionary = load("res://scripts/building_readout.gd").battery(BuildingState.get_building(a))
	_check(int(r.get("firming_cap", -1)) <= int(r.get("slots", 0)),
		"battery: power stabilised never exceeds the tile's firming capacity")
	_check(int(r.get("firming_cap", -1)) == 0,
		"battery: nothing loaded means 0 MW stabilised (not a cell count)")
	BuildingState.remove_building(a)
	BuildingState.remove_building(b2)


func _test_cable_power_cap() -> void:
	# Cables hard-cap a tile's power per turn by cable level — produce + draw separately.
	Modifiers.reset()
	Power.reset_for_turn()
	_check(int(EconomyConfig.CABLE_POWER_CAP[1]) == 2000 and int(EconomyConfig.CABLE_POWER_CAP[2]) == 4000
			and int(EconomyConfig.CABLE_POWER_CAP[3]) == 7000,
		"cable power caps are 2000 / 4000 / 7000 by level")
	# No cables → 0 cap, nothing produces or draws.
	_check(Power.tile_power_cap("tx") == 0, "a tile with no cables has a 0 power cap")
	_check(not Power.can_produce("tx", 50) and not Power.can_draw("tx", 50),
		"no cables → can neither produce nor draw power")
	_check(Power.can_produce("tx", 0) and Power.can_draw("tx", 0), "zero power is always allowed")

	# Fake an L2-cabled tile so the level threshold can be exercised headless.
	var fake := Node.new()
	var src := GDScript.new()
	src.source_code = "extends Node\nvar tiles := {}\nfunc id_to_coord(_t): return Vector2i(0, 0)\n"
	src.reload()
	fake.set_script(src)
	fake.set("tiles", {Vector2i(0, 0): {"infrastructure_present": ["cables"], "infrastructure_levels": {"cables": 2}}})
	fake.add_to_group("hex_map")
	get_tree().root.add_child(fake)

	_check(Power.tile_power_cap("t2") == 4000, "an L2-cable tile caps power at 4000 (got %d)" % Power.tile_power_cap("t2"))
	# Produce AND draw are independent caps — 4000 each on the same L2 tile.
	Power.record_produced("t2", 4000)
	Power.record_drawn("t2", 4000)
	_check(int(Power.tile_produced["t2"]) == 4000 and int(Power.tile_drawn["t2"]) == 4000,
		"a tile can produce 4000 AND draw 4000 with an L2 cable")
	_check(not Power.can_produce("t2", 1), "at the production cap, no further power generates")
	_check(not Power.can_draw("t2", 1), "at the draw cap, no further power is supplied")
	# Substation Layouts research raises the cap: +25% → 5000 (one of two +25% cable throughput unlocks).
	ResearchState.grant_unlock("Substation Layouts")
	_check(Power.tile_power_cap("t2") == 5000,
		"Substation Layouts raises the L2 cap 4000 → 5000 (got %d)" % Power.tile_power_cap("t2"))

	get_tree().root.remove_child(fake)
	fake.free()
	Modifiers.reset()
	Power.reset_for_turn()

func _test_power_network_settlement() -> void:
	# Physical cable networks: same-tile generation covers same-tile draw first, then the rest of
	# the adjacent-cabled network, then only the network's residual net settles with the grid.
	Modifiers.reset()
	Power.reset_for_turn()
	var cabled_ids := ["tile_2_2", "tile_2_3", "tile_9_9", "tile_12_12", "tile_15_15", "tile_15_16"]
	var tiles := {}
	for tid in cabled_ids:
		var p: PackedStringArray = str(tid).split("_")
		tiles[Vector2i(int(p[1]) - 1, int(p[2]) - 1)] = {"infrastructure_present": ["cables"], "infrastructure_levels": {"cables": 2}}
	var fake := Node.new()
	var src := GDScript.new()
	src.source_code = "extends Node\nvar tiles := {}\n"
	src.reload()
	fake.set_script(src)
	fake.set("tiles", tiles)
	fake.add_to_group("hex_map")
	get_tree().root.add_child(fake)

	# Network A (adjacent pair): windmill on 2_2 feeds furnace on 2_3 → surplus 520 sold.
	Power.record_produced("tile_2_2", 800)
	Power.record_drawn("tile_2_3", 280)
	# Network B (isolated, demand only): buys 500.
	Power.record_drawn("tile_9_9", 500)
	# Network C (same tile): windmill + furnace on 12_12 → self-supplied, surplus 520 sold.
	Power.record_produced("tile_12_12", 800)
	Power.record_drawn("tile_12_12", 280)
	# Network D (partial): 15_15 self-covers 280; its residual 20 partly feeds 15_16 (needs 100),
	# leaving an 80 deficit bought from the grid.
	Power.record_produced("tile_15_15", 300)
	Power.record_drawn("tile_15_15", 280)
	Power.record_drawn("tile_15_16", 100)

	var grid := Power.settle_grid_transactions()
	_check(int(grid.grid_sold) == 1040, "per-network sells the surplus of self-sufficient networks (got %d, want 1040)" % int(grid.grid_sold))
	_check(int(grid.grid_bought) == 580, "per-network buys the deficit of importing networks (got %d, want 580)" % int(grid.grid_bought))
	_check(Power.is_self_supplied("tile_2_2") and Power.is_self_supplied("tile_2_3"),
		"a cabled generator covers a same-network consumer on an adjacent tile (own supply)")
	_check(Power.is_self_supplied("tile_12_12"), "same-tile generation covers same-tile draw (own supply)")
	_check(not Power.is_self_supplied("tile_9_9"), "an isolated demand-only tile imports from the national grid")
	_check(Power.is_self_supplied("tile_15_15") and not Power.is_self_supplied("tile_15_16"),
		"same-tile draw is covered first; the network's residual shortfall falls on the far consumer")
	_check(absf(float(grid.grid_sell_revenue) - 1040.0 * EconomyConfig.GRID_SELL_PRICE) < 0.001, "sell revenue priced at GRID_SELL_PRICE")
	_check(absf(float(grid.grid_buy_cost) - 580.0 * EconomyConfig.GRID_BUY_PRICE) < 0.001, "buy cost priced at GRID_BUY_PRICE")
	_check(is_equal_approx(Power.allocated_draw_cost("tile_2_3", 280), 280.0 * EconomyConfig.GRID_SELL_PRICE),
		"cost solver: own network power uses export opportunity cost")
	_check(is_equal_approx(Power.allocated_draw_cost("tile_9_9", 100), 100.0 * EconomyConfig.GRID_BUY_PRICE),
		"cost solver: disconnected consumer pays the grid tariff")
	_check(is_equal_approx(Power.allocated_draw_cost("tile_15_16", 50), 10.0 * EconomyConfig.GRID_SELL_PRICE + 40.0 * EconomyConfig.GRID_BUY_PRICE),
		"cost solver: consumers share the tile's settled mix of own and imported power")
	Power.reset_for_turn()
	Power.record_produced("tile_12_12", 800, true)
	Power.record_drawn("tile_12_12", 280)
	Power.settle_grid_transactions()
	_check(is_equal_approx(Power.allocated_draw_cost("tile_12_12", 280), 280.0 * EconomyConfig.GRID_BUY_PRICE),
		"cost solver: grid-priority generation does not cover the tile's draw")


	get_tree().root.remove_child(fake)
	fake.free()
	Modifiers.reset()
	Power.reset_for_turn()

func _test_power_output_modifier() -> void:
	# Power generation now flows through recipe_output modifiers (it used to bypass them).
	Modifiers.reset()
	var coal_plant := {"building_id": "b_003"}  # Coal Power Plant
	var rec := {"recipe_id": "rp_power", "output_qty": 100, "recipe_type": "power", "output_name": "power"}
	_check(Production._effective_power_output(coal_plant, rec) == 100, "base power output is unmodified (100)")
	ResearchState.grant_unlock("Pulverized Coal Boilers")  # +5% Coal Power Plant output
	_check(Production._effective_power_output(coal_plant, rec) == 105,
		"Pulverized Coal Boilers boosts coal-plant power output +5%% → 105 (got %d)" % Production._effective_power_output(coal_plant, rec))
	_check(Production._effective_power_output({"building_id": "b_024"}, rec) == 100,
		"the coal-plant boost leaves other power plants (solar) untouched")
	Modifiers.reset()

# A power gate asks for a quantity a real grid reaches, and not one it passes in a turn.
# The shipped floor was 250 — one turn of the starting plant, so the node unlocked itself
# (owner, 25 Aug: "minimum of 2500 and max of 10000").
func _test_power_gates_in_band() -> void:
	const FLOOR := 2500
	const CEILING := 10000
	var checked := 0
	for row_value: Variant in _research_rows():
		var row: Dictionary = row_value
		if str(row.get("Object", "")).to_lower() != "power":
			continue
		var quantity := str(row.get("Quantity", ""))
		if not quantity.is_valid_int():
			continue
		checked += 1
		var q := int(quantity)
		_check(q >= FLOOR and q <= CEILING,
			"research: %s asks for %d power, inside %d–%d" % [
				str(row.get("research_node_id", "")), q, FLOOR, CEILING])
	_check(checked > 0, "research: at least one power gate was found to check")


# ── Power intermittency (green/grey quality flags; scripts/production.gd) ───────
func _test_power_quality() -> void:
	var p := {"output_name": "power", "inputs": []}
	_check(Production._power_quality({"building_id": "b_024"}, p) == "green_intermittent",
		"power quality: solar farm = green_intermittent")
	_check(Production._power_quality({"building_id": "b_025"}, p) == "green_intermittent",
		"power quality: onshore wind = green_intermittent")
	_check(Production._power_quality({"building_id": "b_026"}, p) == "green_intermittent",
		"power quality: offshore wind = green_intermittent")
	_check(Production._power_quality({"building_id": "b_027"}, p) == "green_steady",
		"power quality: hydro = green_steady")
	_check(Production._power_quality({"building_id": "b_003"}, {"output_name": "power", "inputs": [{"internal_name": "coal"}]}) == "grey",
		"power quality: coal-fuelled = grey")
	_check(Production._power_quality({"building_id": "b_003"}, {"output_name": "power", "inputs": [{"internal_name": "biomass"}]}) == "green_steady",
		"power quality: biomass-fuelled = green_steady")

func _test_power_instance_age() -> void:
	_check(Production._instance_age("inst_b_007_00001a") == 26, "instance age: parses trailing hex (1a = 26)")
	_check(Production._instance_age("inst_b_001_000001") < Production._instance_age("inst_b_001_000002"),
		"instance age: lower counter is older")

func _test_power_intermittency_alloc() -> void:
	# Result is keyed by iid -> {derate, green_consumed, unfirmed_intermittent, steady_consumed, demand}.
	var derate := func(dd, k): return float((dd.get(k, {}) as Dictionary).get("derate", 0.0))
	# Full unfirmed intermittent green -> 0.4 derate (produce 60%); richer fields populated.
	var d := Production._allocate_power_derates(
		{"tile_1_1": {"int": 100, "steady": 0}},
		[{"iid": "c1", "tile": "tile_1_1", "demand": 100.0, "level": 1, "profit": 0.0, "age": 1}],
		{"tile_1_1": 0})
	_check(absf(derate.call(d, "c1") - 0.4) < 0.001, "intermittency: full unfirmed intermittent green -> 0.4 derate")
	_check(int(d["c1"]["green_consumed"]) == 100 and int(d["c1"]["unfirmed_intermittent"]) == 100
		and int(d["c1"]["steady_consumed"]) == 0, "intermittency: result carries green/unfirmed/steady consumed")
	# Storage on the tile firms it -> no derate, but it still consumed (now steady) green.
	d = Production._allocate_power_derates(
		{"tile_1_1": {"int": 100, "steady": 0}},
		[{"iid": "c1", "tile": "tile_1_1", "demand": 100.0, "level": 1, "profit": 0.0, "age": 1}],
		{"tile_1_1": 100})
	_check(absf(derate.call(d, "c1")) < 0.001 and int(d["c1"]["steady_consumed"]) == 100,
		"intermittency: on-tile storage firms intermittent -> no derate (counts as steady)")
	# Steady green never derates (consumes steady green).
	d = Production._allocate_power_derates(
		{"tile_1_1": {"int": 0, "steady": 100}},
		[{"iid": "c1", "tile": "tile_1_1", "demand": 100.0, "level": 1, "profit": 0.0, "age": 1}],
		{"tile_1_1": 0})
	_check(absf(derate.call(d, "c1")) < 0.001 and int(d["c1"]["steady_consumed"]) == 100,
		"intermittency: steady green -> no derate")
	# A consumer that draws NO green is absent from the result entirely.
	d = Production._allocate_power_derates(
		{},
		[{"iid": "c1", "tile": "tile_1_1", "demand": 100.0, "level": 1, "profit": 0.0, "age": 1}],
		{"tile_1_1": 0})
	_check(not d.has("c1"), "intermittency: consumer with no green is omitted")
	# Half intermittent / half steady -> 0.2 derate (0.4 * 0.5 share).
	d = Production._allocate_power_derates(
		{"tile_1_1": {"int": 50, "steady": 50}},
		[{"iid": "c1", "tile": "tile_1_1", "demand": 100.0, "level": 1, "profit": 0.0, "age": 1}],
		{"tile_1_1": 0})
	_check(absf(derate.call(d, "c1") - 0.2) < 0.001, "intermittency: 50% intermittent share -> 0.2 derate")
	# A load-following recipe takes NO derate on fully unfirmed green and needs no battery.
	# Paired with an identical non-immune consumer so the exemption is proved to be the cause
	# rather than something else about the fixture zeroing the derate.
	var immune_id: String = str(EconomyConfig.INTERMITTENCY_IMMUNE_RECIPES[0])
	d = Production._allocate_power_derates(
		{"tile_1_1": {"int": 200, "steady": 0}},
		[{"iid": "imm", "tile": "tile_1_1", "demand": 100.0, "recipe_id": immune_id,
		  "level": 1, "profit": 0.0, "age": 1},
		 {"iid": "ctl", "tile": "tile_1_1", "demand": 100.0, "recipe_id": "r_009",
		  "level": 1, "profit": 0.0, "age": 1}],
		{"tile_1_1": 0})
	_check(absf(derate.call(d, "imm")) < 0.001 and bool(d["imm"].get("intermittency_immune", false)),
		"intermittency: a load-following recipe takes no derate on fully unfirmed green")
	_check(absf(derate.call(d, "ctl") - 0.4) < 0.001 and not bool(d["ctl"].get("intermittency_immune", true)),
		"intermittency: an identical non-immune consumer still takes the full 0.4 derate")
	_check(int(d["imm"]["unfirmed_intermittent"]) == 100 and int(d["imm"]["green_consumed"]) == 100,
		"intermittency: the immune consumer still RECORDS the unfirmed green it drew")
	# Priority: scarce green (100) goes to the higher-level consumer first.
	d = Production._allocate_power_derates(
		{"tile_5_5": {"int": 100, "steady": 0}},
		[{"iid": "hi", "tile": "tile_5_5", "demand": 100.0, "level": 3, "profit": 0.0, "age": 2},
		 {"iid": "lo", "tile": "tile_5_5", "demand": 100.0, "level": 1, "profit": 0.0, "age": 1}],
		{"tile_5_5": 0})
	_check(absf(derate.call(d, "hi") - 0.4) < 0.001 and not d.has("lo"),
		"intermittency: scarce green prioritises the higher-level consumer")
	# Tiebreak: same level/profit -> oldest (lowest age) wins the scarce green.
	d = Production._allocate_power_derates(
		{"tile_5_5": {"int": 100, "steady": 0}},
		[{"iid": "new", "tile": "tile_5_5", "demand": 100.0, "level": 1, "profit": 0.0, "age": 9},
		 {"iid": "old", "tile": "tile_5_5", "demand": 100.0, "level": 1, "profit": 0.0, "age": 1}],
		{"tile_5_5": 0})
	_check(absf(derate.call(d, "old") - 0.4) < 0.001 and not d.has("new"),
		"intermittency: tie broken by oldest instance (age) first")
	# Producer firming + proportional mix: int 50/steady 50, tile cap 30 firms 30 int ->
	# 20 int/80 steady; consumer (same tile, cap now 0) draws 20 unfirmed int of 100 ->
	# derate 0.4 * 0.2 = 0.08 (exact-float firming, no ceil over-charge).
	d = Production._allocate_power_derates(
		{"tile_1_1": {"int": 50, "steady": 50}},
		[{"iid": "c1", "tile": "tile_1_1", "demand": 100.0, "level": 1, "profit": 0.0, "age": 1}],
		{"tile_1_1": 30})
	_check(absf(derate.call(d, "c1") - 0.08) < 0.001,
		"intermittency: producer firming + proportional mix -> 0.08 derate")

func _test_intermittency_tile_aggregate() -> void:
	# Roll the per-building result + per-tile green supply up into the tile-view aggregate.
	var saved_green := Production._green_supply_by_tile
	var saved_im := Production._intermittency_by_building
	var saved_prod := Power.tile_produced
	Production._green_supply_by_tile = {"tile_2_2": {"int": 100, "steady": 0}}
	Production._intermittency_by_building = {
		"a": {"derate": 0.4, "green_consumed": 100.0, "unfirmed_intermittent": 100.0, "steady_consumed": 0.0, "demand": 100.0},
		"b": {"derate": 0.0, "green_consumed": 50.0, "unfirmed_intermittent": 0.0, "steady_consumed": 50.0, "demand": 50.0},
	}
	Power.tile_produced = {"tile_2_2": 100}
	var consumers := [
		{"iid": "a", "tile": "tile_2_2", "demand": 100.0, "building_id": "b_017"},
		{"iid": "b", "tile": "tile_2_2", "demand": 50.0, "building_id": "b_018"},
	]
	var agg := Production._aggregate_tile_intermittency(consumers)
	var t: Dictionary = agg["tile_2_2"]
	_check(int(t["green_produced"]) == 100 and int(t["green_intermittent_produced"]) == 100 and int(t["total_produced"]) == 100,
		"tile intermittency: green/total produced rolled up")
	_check(int(t["total_consumed"]) == 150 and absf(float(t["unfirmed_consumed"]) - 100.0) < 0.001
		and absf(float(t["green_consumed"]) - 150.0) < 0.001, "tile intermittency: consumed totals rolled up")
	_check((t["affected"] as Array).size() == 1 and str((t["affected"][0])["iid"]) == "a",
		"tile intermittency: only derated buildings are listed as affected")
	Production._green_supply_by_tile = saved_green
	Production._intermittency_by_building = saved_im
	Power.tile_produced = saved_prod

func _test_battery_buildable() -> void:
	# The electric battery used to be recipe-less (dropped from build panels). It now has an
	# input-only recipe (1 lithium_battery/turn) so it resolves + appears as a buildable option.
	var recs: Array = Catalog.get_recipes_for_building("b_028")  # recipes key by resolved building_id
	_check(recs.size() >= 1, "battery: has a buildable recipe (was recipe-less)")
	if recs.size() >= 1:
		var r: Dictionary = recs[0]
		# Deposit model: the housing has a no-op recipe (no per-turn consumption); firming
		# comes from loaded cells, not the recipe.
		_check(str(r.get("output_name", "")) == "" and (r.get("inputs", []) as Array).is_empty(),
			"battery: housing recipe is a no-op (no inputs/outputs)")
		var catalysts: Array = r.get("catalysts", []) as Array
		_check(catalysts.size() == 3
			and str(catalysts[0].get("internal_name", "")) == "lithium_battery"
			and str(catalysts[1].get("internal_name", "")) == "sodium_battery"
			and str(catalysts[2].get("internal_name", "")) == "iron_battery",
			"battery: allowed cell chemistries come from recipe catalysts")
	var tvd = load("res://scripts/tile_view_data.gd")
	var opt: Dictionary = tvd.power_build_option("battery", "", "tile_5_10", {})
	_check(str(opt.get("recipe_id", "")) != "", "battery: build option resolves a recipe (no longer 'not available')")

func _test_battery_deposit() -> void:
	# Deposit model: housing = 1000 ⚡ capacity at L1; firming = Σ cells × density, capped by
	# headroom; loading is tech-gated; density differs per type so 18 lithium / 24 sodium cells
	# fill 1000 ⚡; demolish refunds the cells.
	var tile := "tile_9_9"
	Power.tile_battery_cells.erase(tile)
	var lgid := str(Catalog.get_good_by_internal_name("lithium_battery").get("id", ""))
	var sgid := str(Catalog.get_good_by_internal_name("sodium_battery").get("id", ""))
	Stockpile.consume(tile, lgid, Stockpile.get_at_tile(tile, lgid))
	Stockpile.consume(tile, sgid, Stockpile.get_at_tile(tile, sgid))
	var bid: String = BuildingState.add_building("b_028", "r_225", tile, MatchState.LOCAL_PLAYER)
	_check(Power.tile_battery_slots(tile) == 1000, "battery deposit: L1 housing = 1000 firming capacity")
	_check(Production._tile_storage_cap(tile) == 0, "battery deposit: empty housing firms nothing")
	var hadL := ResearchState.is_unlocked("Lithium Battery Storage")
	var hadS := ResearchState.is_unlocked("Sodium Battery Storage")
	ResearchState.unlocked_titles.erase("Lithium Battery Storage")
	ResearchState.unlocked_titles.erase("Sodium Battery Storage")
	Stockpile.add(tile, lgid, 50)
	_check(Power.load_battery_cells(tile, lgid, 5) == 0, "battery deposit: locked type cannot be loaded")
	ResearchState.grant_unlock("Lithium Battery Storage")
	_check(Power.battery_cells_to_fill(tile, lgid) == 18, "battery deposit: 18 lithium cells fill a 1000 ⚡ L1")
	_check(Power.load_battery_cells(tile, lgid, 999) == 18, "battery deposit: loads 18 lithium cells (capped by firming)")
	_check(Power.tile_firming_cap(tile) == 1000, "battery deposit: full lithium housing firms 1000")
	_check(Power.load_battery_cells(tile, lgid, 5) == 0, "battery deposit: no headroom when full")
	_check(Power.unload_battery_cells(tile, lgid, 9) == 9, "battery deposit: unload 9")
	_check(Power.tile_firming_cap(tile) == 500 and Stockpile.get_at_tile(tile, lgid) == 41,
		"battery deposit: unload refunds to stock + halves firming")
	Power.unload_battery_cells(tile, lgid, 9)  # clear for the density check
	ResearchState.grant_unlock("Sodium Battery Storage")
	Stockpile.add(tile, sgid, 50)
	_check(Power.battery_cells_to_fill(tile, sgid) == 24, "battery deposit: sodium needs 24 cells (density 0.75×)")
	_check(Power.load_battery_cells(tile, sgid, 999) == 24, "battery deposit: loads 24 sodium cells to fill 1000 ⚡")
	_check(Power.tile_firming_cap(tile) == 1000, "battery deposit: full sodium also firms 1000")
	BuildingState.remove_building(bid)
	_check(Power.tile_firming_cap(tile) == 0 and Stockpile.get_at_tile(tile, sgid) == 50,
		"battery deposit: demolishing housing refunds all remaining cells")
	if not hadL:
		ResearchState.unlocked_titles.erase("Lithium Battery Storage")
	if not hadS:
		ResearchState.unlocked_titles.erase("Sodium Battery Storage")
	Power.tile_battery_cells.erase(tile)
	Stockpile.consume(tile, lgid, Stockpile.get_at_tile(tile, lgid))
	Stockpile.consume(tile, sgid, Stockpile.get_at_tile(tile, sgid))

func _test_battery_fill_pending() -> void:
	# An in-flight fill counts down and installs the cells (no stockpile) when it arrives.
	var tile := "tile_9_8"
	Power.tile_battery_cells.erase(tile)
	Power.pending_battery_fills.clear()
	var lgid := str(Catalog.get_good_by_internal_name("lithium_battery").get("id", ""))
	Stockpile.consume(tile, lgid, Stockpile.get_at_tile(tile, lgid))
	var bid: String = BuildingState.add_building("b_028", "r_225", tile, MatchState.LOCAL_PLAYER)
	Power.pending_battery_fills.append({"tile_id": tile, "good_id": lgid, "qty": 18, "turns_left": 2})
	_check(Power.battery_fill_turns_remaining(tile) == 2, "fill: 2 turns remaining")
	_check(Power.tile_firming_cap(tile) == 0, "fill: nothing installed yet")
	Power.tick_battery_fills()
	_check(Power.battery_fill_turns_remaining(tile) == 1, "fill: ticks down to 1")
	_check(Power.tile_firming_cap(tile) == 0, "fill: still in transit")
	Power.tick_battery_fills()
	_check(Power.battery_fill_turns_remaining(tile) == 0, "fill: countdown complete")
	_check(Power.tile_firming_cap(tile) == 1000, "fill: 18 cells installed → 1000 ⚡ (no stockpile draw)")
	BuildingState.remove_building(bid)
	Power.tile_battery_cells.erase(tile)
	Power.pending_battery_fills.clear()
	Stockpile.consume(tile, lgid, Stockpile.get_at_tile(tile, lgid))

func _test_power_capped_alert() -> void:
	# Production reports a generator blocked by the cable export cap exactly like a consumer
	# with no supply: missing "power". Read literally that says "starved of power" — the
	# opposite of the truth, and the opposite of the fix.
	var saved_missing: Dictionary = Production.missing_by_building.duplicate(true)
	TurnBriefing._alert_dismissed.erase("alert:power_capped")
	TurnBriefing._alert_dismissed.erase("alert:starved")
	# Build the generator rather than hunting the fixture for one: an early-returning test
	# that finds nothing asserts nothing, and would have hidden a regression here in silence.
	var gen: String = BuildingState.add_building("b_003", "r_004", "tile_9_9", MatchState.LOCAL_PLAYER, "cable_cap_test")
	_check(gen != "", "fixture: placed a coal power plant to stand in for a capped generator")
	Production.missing_by_building = {gen: [{"internal_name": "power", "good_id": "power"}]}
	var capped: Dictionary = TurnBriefing._cable_capped_producers()
	_check(capped.has(gen), "a power producer missing 'power' is read as cable-capped, not starved")
	var item: Dictionary = TurnBriefing._power_capped_item()
	_check(str(item.get("id", "")) == "alert:power_capped" and str(item.get("severity", "")) == "warning",
		"cable-cap alert fires as a warning (nothing is broken; output is being thrown away)")
	_check(str(item.get("title", "")).contains("capped by cables"), "cable-cap alert names the cause")
	var starved: Dictionary = TurnBriefing._starved_item()
	_check(starved.is_empty(), "the same plant is NOT also reported as starved of power")
	BuildingState.remove_building(gen)
	Production.missing_by_building = saved_missing


func _test_partial_power_dispatch() -> void:
	# PARTIAL DISPATCH (owner ruling): a generator that slightly overshoots its tile's
	# remaining cable headroom runs DERATED into the gap; a bigger overshoot doesn't run.
	# Tested through the pure decision so it needs no cabled fixture tile.
	var tol: float = Power.PARTIAL_DISPATCH_TOLERANCE
	_check(Power.dispatchable(600, 2000) == 600, "a plant well under the headroom dispatches in full")
	_check(Power.dispatchable(600, 600) == 600, "an exact fit dispatches in full")
	# 620 into 600 headroom: overshoot 20 = 3.2% of output -> derate to 600.
	_check(Power.dispatchable(620, 600) == 600,
		"a small overshoot derates to the headroom instead of idling the plant")
	# 800 into 600: overshoot 200 = 25% of output -> at the tolerance, refuse.
	_check(Power.dispatchable(800, 600) == 0,
		"an overshoot AT the %d%% tolerance does not run" % int(tol * 100.0))
	# 690 into 620 (the e2e's real case): overshoot 70 = 10.1% -> derate.
	_check(Power.dispatchable(690, 620) == 620,
		"the e2e's stranded 3rd plant now fills its tile's remaining 620 MW")
	_check(Power.dispatchable(690, 0) == 0, "a full tile dispatches nothing")
	_check(Power.dispatchable(0, 2000) == 0, "a zero-output building dispatches nothing")
	_check(Power.dispatchable(690, -50) == 0, "negative headroom dispatches nothing")
