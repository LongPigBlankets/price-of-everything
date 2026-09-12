extends "res://tests/test_base.gd"
## Market prices, price impact, buying and selling.

const FEATURE := "market"
## Tests that also belong to other features (run under any of their tags).
const TAGS := {
	"_test_market_price_history_and_layout": ["finance", "market"],
	"_test_queue_sell": ["market", "stockpile"],
	"_test_queue_sell_immediate_updates_turn_summary": ["market", "production", "stockpile"],
	"_test_market_execute_sale": ["market", "stockpile"],
	"_test_market_execute_sale_skip_consume": ["market", "stockpile"],
	"_test_market_execute_sale_pay_transport": ["market", "stockpile"],
	"_test_bulk_sell": ["market", "stockpile"],
	"_test_market_buy": ["finance", "market"],
	"_test_market_input_pipeline_ignores_reserved_inbound": ["market", "power", "production", "stockpile"],
	"_test_idle_labour_pay_policy": ["finance", "market", "production"],
	"_test_purchase_inventory_seed": ["market", "stockpile"],
	"_test_market_sale_credits": ["market", "production", "stockpile"],
	"_test_recurring_sell_multitile": ["market", "stockpile"],
	"_test_sell_protects_build_materials": ["construction", "market", "production", "research", "stockpile"],
	"_test_auto_sell_goods": ["market", "production"],
}

func _test_market_price_history_and_layout() -> void:
	var bar = load("res://scripts/metallic_bar.gd").new()
	bar.max_value = 1.0
	bar.value = 2.0 / 3.0
	_check(is_equal_approx(bar.frac, 2.0 / 3.0), "metallic bar: fractional skills retain their exact fill")
	bar.value = 0.0
	_check(bar.frac == 0.0, "metallic bar: zero skill has no fill")
	bar.free()
	var saved: Dictionary = MarketState.export_state()
	var saved_turn: int = int(TurnManager.current_turn)
	var saved_costs: Dictionary = CostSolver.last_result.duplicate(true)
	CostSolver.last_result = {"per_good": {"g_008": {"unit_cost": 1.25}}}
	TurnManager.current_turn = 1
	MarketState.import_state({})
	var first: Array = MarketState.history_for("g_008")
	_check(first.size() == 1 and int(first[0].turn) == 1, "market history: starts at turn one")
	_check(is_equal_approx(float(first[0].cost_basis), 1.25), "market history: captures player average unit cost")
	CostSolver.last_result = {"per_good": {"g_008": {"unit_cost": 1.75}}}
	var base: float = float(first[0].price)
	TurnManager.current_turn = 2
	MarketState.impact_pct["g_008"] = 20.0
	MarketState._record_price_history()
	var observed: Array = MarketState.history_for("g_008")
	_check(observed.size() == 2 and float(observed[1].price) > base, "market history: records actual impacted price")
	_check(is_equal_approx(float(observed[0].cost_basis), 1.25) and is_equal_approx(float(observed[1].cost_basis), 1.75), "market history: costs retain their historical values")
	CostSolver.last_result = saved_costs
	observed[0].price = -99
	_check(float(MarketState.history_for("g_008")[0].price) == base, "market history: readers cannot mutate observations")
	var snapshot: Dictionary = MarketState.export_state()
	MarketState.import_state(snapshot)
	_check(MarketState.export_state().price_history == snapshot.price_history, "market history: save/load preserves observations")
	MarketState._record_price_history()
	_check(MarketState.history_for("g_008").size() == 2, "market history: duplicate refresh does not append a turn")
	var chart = load("res://scripts/market_price_chart.gd").new()
	chart.good_id = "g_008"
	CostSolver.last_result = {"per_good": {}}
	_check(chart._cost_for_sample({"cost_basis": 1.25}) < 0.0, "market chart: hides past costs for goods not produced")
	CostSolver.last_result = {"per_good": {"g_008": {"unit_cost": 1.75}}}
	_check(is_equal_approx(chart._cost_for_sample({"cost_basis": 1.25}), 1.25), "market chart: produced goods retain hovered historical cost")
	CostSolver.last_result = saved_costs
	CostSolver.last_result = {"per_good": {"g_008": {"unit_cost": 1.75}}}
	chart.size = Vector2(600, 170)
	add_child(chart)
	_check(chart.sample_at_x(chart._plot_rect().position.x) == 0 and chart.sample_at_x(chart._plot_rect().end.x) == 1, "market chart: hover maps to first and last recorded turn")
	_check(chart._hover_lines(0) == PackedStringArray(["Turn 1", "Price £%.2f" % base, "Your cost basis £1.25"]), "market chart: hover shows historical turn price and cost")
	CostSolver.last_result = saved_costs
	MarketState.price_history["g_008"].append({"turn": 3, "price": 999.0})
	chart.refresh()
	_check(chart._samples.size() == 2, "market chart: future observations never render")
	chart.queue_free()
	var row = load("res://scenes/market_row.tscn").instantiate()
	row.setup(Catalog.get_good("g_008"))
	add_child(row)
	row.size.x = 1000
	row._toggle_expand()
	await get_tree().process_frame
	row._layout_details()
	var details: Control = row.find_child("MarketGoodDetails", true, false)
	var actions: Control = row.find_child("MarketActions", true, false)
	var graph: Control = row.find_child("PriceHistoryChart", true, false)
	_check(absf(actions.size.x + 6 - details.size.x * 0.25) < 1.0, "market details: actions occupy one quarter")
	_check(absf(graph.size.x + 6 - details.size.x * 0.75) < 1.0, "market details: chart occupies three quarters")
	row.queue_free()
	TurnManager.current_turn = 40
	MarketState.import_state({})
	_check(MarketState.history_for("g_008").size() == 1 and int(MarketState.history_for("g_008")[0].turn) == 40, "market history: old saves never invent earlier prices")
	TurnManager.current_turn = saved_turn
	MarketState.import_state(saved)

func _test_buy_grants_land() -> void:
	# Buying an NPC building grants its footprint as owned land on the tile, exactly once.
	var tile := "bp_land_tile"
	BuildingState.tile_land_owned.erase(tile)  # start from the default for this synthetic tile
	var iid: String = BuildingState.add_building("b_007", "", tile, "Test NPC Co", "", false)
	var owned_before: int = BuildingState.get_tile_land_owned(tile)  # default 100
	var footprint: int = int(Catalog.get_building("b_007").get("tile_size_used", 1))  # 10 at L1
	BuildingState.set_building_owner(iid, MatchState.LOCAL_PLAYER)
	var owned_after: int = BuildingState.get_tile_land_owned(tile)
	_check(owned_after == mini(BuildingState.MAX_TILE_LAND, owned_before + footprint),
		"buy grants the building footprint as owned land")
	BuildingState.set_building_owner(iid, MatchState.LOCAL_PLAYER)  # already owned
	_check(BuildingState.get_tile_land_owned(tile) == owned_after, "buying again does not double-grant land")
	BuildingState.remove_building(iid)
	BuildingState.tile_land_owned.erase(tile)

func _test_sell_and_demolish() -> void:
	var saved_money := MatchState.money
	var saved_buildings := BuildingState.buildings.duplicate(true)
	var saved_queue := BuildingWorks.demolish_queue.duplicate(true)
	MatchState.money = 1000.0
	BuildingState.buildings = {}
	BuildingWorks.demolish_queue = {}

	# Sell: credits the market value, flips owner to the NPC operator, building stays.
	var sid := "test_sell_1"
	BuildingState.buildings[sid] = {"instance_id": sid, "building_id": "b_001", "recipe_id": "r_001", "tile_id": "tile_0_0", "level": 1, "owner": MatchState.LOCAL_PLAYER}
	var before_money := MatchState.money
	var sres: Dictionary = BuildingState.sell_building(sid)
	_check(bool(sres.get("ok", false)) and int(sres.get("price", -1)) >= 0, "sell: returns ok + a price")
	_check(BuildingState.buildings.has(sid) and str(BuildingState.buildings[sid].get("owner", "")) == BuildingState.SOLD_TO_OWNER,
		"sell: building stays on the tile, owner → NPC operator")
	_check(MatchState.money >= before_money, "sell: value credited to the player")
	_check(not bool(BuildingState.sell_building(sid).get("ok", false)), "sell: an NPC-owned building can't be player-sold again")

	# Demolish: queued 1-turn job that removes the building on tick.
	var did := "test_demo_1"
	BuildingState.buildings[did] = {"instance_id": did, "building_id": "b_001", "recipe_id": "r_001", "tile_id": "tile_0_0", "level": 1, "owner": MatchState.LOCAL_PLAYER}
	var dres: Dictionary = BuildingWorks.start_demolish(did)
	_check(bool(dres.get("ok", false)) and BuildingWorks.is_demolishing(did) and BuildingWorks.demolish_turns_remaining(did) == 1,
		"demolish: queued with a 1-turn countdown")
	_check(not bool(BuildingWorks.start_demolish(did).get("ok", false)), "demolish: can't double-queue")
	BuildingWorks.tick_demolish()
	_check(not BuildingState.buildings.has(did) and not BuildingWorks.is_demolishing(did),
		"demolish: tick removes the building and clears the queue")

	# Demolish queue survives a save round-trip (additive field, tolerant reader — no version bump).
	var qid := "test_demo_rt"
	BuildingState.buildings[qid] = {"instance_id": qid, "building_id": "b_001", "recipe_id": "r_001", "tile_id": "tile_0_0", "level": 1, "owner": MatchState.LOCAL_PLAYER}
	BuildingWorks.start_demolish(qid)
	var snap: Dictionary = MatchState.export_state()
	BuildingWorks.demolish_queue = {}
	MatchState.import_state(snap)
	_check(BuildingWorks.is_demolishing(qid), "demolish: queue survives export/import round-trip")

	MatchState.money = saved_money
	BuildingState.buildings = saved_buildings
	BuildingWorks.demolish_queue = saved_queue

func _test_queue_sell() -> void:
	Stockpile.add("tile_3_8", "g_001", 8)
	var before: int = TransportState.get_pending_transport_shipments().size()
	var summary: Dictionary = MatchState.queue_sell("tile_3_8", {"g_001": 8})
	_check(not summary.is_empty(), "queue_sell returns a summary")
	_check(Stockpile.get_at_tile("tile_3_8", "g_001") == 0, "queue_sell consumes from source")
	_check(str(summary.get("port", "")) != "" and TransportState.get_pending_transport_shipments().size() > before,
		"queue_sell ships to a port")

func _test_queue_sell_immediate_updates_turn_summary() -> void:
	Stockpile.clear_all()
	Stockpile.add("tile_5_10", "g_001", 6)
	Production._pending_external_sales.clear()
	Production.last_turn_summary = {"goods_sales_revenue": 0.0, "money_in": 0.0, "sold": {}}
	var result: Dictionary = MatchState.queue_sell("tile_5_10", {"g_001": 6}, false)
	var sold: Dictionary = Production.last_turn_summary.get("sold", {})
	var coal: Dictionary = sold.get("g_001", {})
	_check(not result.is_empty() and not bool(result.get("deferred", true)),
		"queue_sell can settle immediately from a port tile")
	_check(int(coal.get("qty", 0)) == 6
		and float(Production.last_turn_summary.get("goods_sales_revenue", 0.0)) > 0.0,
		"immediate tile-view sales update goods sold in the turn summary")
	var next_summary := {"goods_sales_revenue": 0.0, "money_in": 0.0, "sold": {}}
	Production._merge_pending_external_sales(next_summary)
	var next_sold: Dictionary = next_summary.get("sold", {})
	var next_coal: Dictionary = next_sold.get("g_001", {})
	_check(int(next_coal.get("qty", 0)) == 6
		and float(next_summary.get("goods_sales_revenue", 0.0)) > 0.0,
		"immediate tile-view sales carry into the next turn summary")

# MarketState.execute_sale is the unified low-level sell primitive. The three tests
# below pin the three axes the option dict toggles, so any drift in queue_sell's or
# Production's wrapper is caught by something tighter than the E2E suite.
func _test_market_execute_sale() -> void:
	# Default behaviour: consume from the tile, log to ledger, defer revenue until
	# the shipment lands at the port. It keeps the historical gross inland freight,
	# but pays the required port charge when the shipment is booked.
	var tile := "tile_3_8"
	var port_charge: float = float(TransportState.preview_sea_shipping("tile_5_10", "g_001", 12).get("total", 0.0))
	Stockpile.add(tile, "g_001", 12)
	var ships_before := TransportState.get_pending_transport_shipments().size()
	var txn_before := MatchState.get_oneoff_transaction_rows().size()
	var result: Dictionary = MarketState.execute_sale(tile, {"g_001": 12})
	_check(not result.is_empty(), "execute_sale returns a result")
	_check(Stockpile.get_at_tile(tile, "g_001") == 0, "execute_sale consumes from the tile")
	_check(bool(result.get("deferred", false)) and TransportState.get_pending_transport_shipments().size() > ships_before,
		"execute_sale queues a shipment (deferred sale)")
	_check(MatchState.get_oneoff_transaction_rows().size() > txn_before,
		"execute_sale logs a transaction row by default")
	_check(absf(float(result.get("transport_cost", -1.0)) - port_charge) < 0.01,
		"execute_sale: only the mandatory port charge is paid unless inland freight is requested")

func _test_market_execute_sale_skip_consume() -> void:
	# skip_consume: the goods are already in the caller's hand (production output);
	# the stockpile is not touched.
	var tile := "tile_3_8"
	Stockpile.consume(tile, "g_001", 1 << 30)  # drain
	var before: int = Stockpile.get_at_tile(tile, "g_001")
	var result: Dictionary = MarketState.execute_sale(tile, {"g_001": 5},
		{"skip_consume": true, "log_oneoff": false})
	_check(not result.is_empty(), "execute_sale(skip_consume) sells without stockpile")
	_check(Stockpile.get_at_tile(tile, "g_001") == before,
		"execute_sale(skip_consume) does not touch the stockpile")
	_check(int(result.get("total_qty", 0)) == 5,
		"execute_sale(skip_consume) sells the full requested quantity")

func _test_market_execute_sale_pay_transport() -> void:
	# pay_transport_from_seller: the seller eats the freight cost upfront. This is
	# the difference between Production's output-routed sales and the gross manual
	# sells from queue_sell.
	var tile := "tile_3_8"
	Stockpile.add(tile, "g_001", 20)
	var money_before: float = MatchState.money
	var result: Dictionary = MarketState.execute_sale(tile, {"g_001": 20},
		{"pay_transport_from_seller": true, "log_oneoff": false})
	_check(not result.is_empty(), "execute_sale(pay_transport) returns a result")
	var paid: float = float(result.get("transport_cost", 0.0))
	_check(paid > 0.0, "execute_sale(pay_transport) charges a non-zero transport cost")
	_check(absf((money_before - paid) - MatchState.money) < 0.01,
		"execute_sale(pay_transport) deducts transport upfront (paid=%.4f, Δmoney=%.4f)"
			% [paid, money_before - MatchState.money])

func _test_bulk_sell() -> void:
	Stockpile.add("tile_3_8", "g_001", 30)
	var result: Dictionary = MatchState.sell_all_to_market({"good_id": "", "finished_only": false, "per_tile_keep": 10})
	_check(int(result.get("total_qty", 0)) >= 20, "sell_all_to_market sells the surplus above per-tile keep")
	_check(Stockpile.get_at_tile("tile_3_8", "g_001") == 10, "bulk sell leaves the kept amount on the tile")

func _test_market_buy() -> void:
	_check(not MatchState.is_input_tile_only("inst_x", "g_002"), "inputs default to stockpile-then-market")
	MatchState.set_input_tile_only("inst_x", "g_002", true)
	_check(MatchState.is_input_tile_only("inst_x", "g_002"), "input can be set to tile-stockpile-only")
	MatchState.set_input_tile_only("inst_x", "g_002", false)
	_check(not MatchState.is_input_tile_only("inst_x", "g_002"), "input resets to stockpile-then-market")
	MatchState.money = 100000.0
	var t_before: int = MatchState.get_oneoff_transaction_rows().size()
	var ship_before: int = TransportState.get_pending_transport_shipments().size()
	var money_before: float = MatchState.money
	var result: Dictionary = MatchState.queue_buy("tile_3_8", "g_002", 10)
	_check(not result.is_empty(), "queue_buy returns a summary")
	_check(absf(float(result.get("goods_cost", 0)) + float(result.get("transport_cost", 0)) - float(result.get("cost", 0))) < 0.01,
		"queue_buy splits cost into goods + transport")
	# PAY ON ARRIVAL (owner ruling 2026-07-27): a shipped order does NOT charge at order
	# time — the bill rides with the goods and settles when they land.
	_check(bool(result.get("deferred", false)), "a shipped buy is flagged deferred")
	_check(absf(MatchState.money - money_before) < 0.0001,
		"queue_buy does NOT charge at order time — the bill rides with the goods")
	_check(absf(MatchState.unpaid_purchase_total() - float(result.get("cost", 0.0))) < 0.01,
		"the unpaid bill is tracked against future purchase headroom")
	# Same clamp as purchase_headroom(): an over-borrowed wallet (negative capacity) counts as zero.
	_check(MatchState.purchase_headroom() < money_before + maxf(0.0, LoanState.available_capacity()) + 0.01,
		"in-transit commitments reduce the headroom the next order is measured against")
	_check(TransportState.get_pending_transport_shipments().size() > ship_before, "queue_buy queues an inbound shipment")
	var rows: Array = MatchState.get_oneoff_transaction_rows()
	_check(rows.size() == t_before + 1 and str(rows[rows.size() - 1].get("type", "")) == "Buy",
		"a buy is logged with type Buy")
	# Best-effort: a big order with little cash buys a partial amount, not nothing.
	MatchState.money = 50.0
	var partial: Dictionary = MatchState.queue_buy("tile_3_8", "g_002", 1000)
	_check(not partial.is_empty() and int(partial.get("qty", 0)) > 0 and int(partial.get("qty", 0)) < 1000,
		"queue_buy buys a partial amount when cash is short")

func _test_market_input_pipeline_ignores_reserved_inbound() -> void:
	MatchState.reset()
	Stockpile.clear_all()
	Power.reset_for_turn()
	TransportState.pending_transport_shipments.clear()
	var fake := Node.new()
	var src := GDScript.new()
	src.source_code = "extends Node\nvar tiles := {}\nfunc id_to_coord(t):\n\treturn Vector2i(5, 10) if t == \"tile_5_10\" else Vector2i(-1, -1)\n"
	src.reload()
	fake.set_script(src)
	fake.set("tiles", {Vector2i(5, 10): {"infrastructure_present": ["cables"], "infrastructure_levels": {"cables": 3}}})
	fake.add_to_group("hex_map")
	get_tree().root.add_child(fake)
	MatchState.money = 100000.0
	var tile := "tile_5_10"
	var coal_gid := "g_001"
	var iid := BuildingState.add_building("b_003", "r_004", tile, MatchState.LOCAL_PLAYER, "test_pipeline_coal_plant")
	TransportState.pending_transport_shipments.append({
		"source_tile": "tile_build_site",
		"destination_tile": tile,
		"good_id": coal_gid,
		"qty": 10000,
		"turns_remaining": 1,
		"construction_instance_id": "construction_reserved_coal",
	})
	TransportState.pending_transport_shipments.append({
		"source_tile": "tile_manual",
		"destination_tile": tile,
		"good_id": coal_gid,
		"qty": 3,
		"turns_remaining": 1,
	})
	_check(Production._inbound_qty(tile, coal_gid) == 3,
		"market input pipeline ignores construction-reserved inbound but counts ordinary inbound")
	var summary := {
		"purchased": {},
		"purchased_cost": {},
		"goods_purchased_cost": 0.0,
		"transport_paid": 0.0,
		"money_out": 0.0,
		"goods_purchased_by_type": {},
	}
	Production._buy_market_inputs([BuildingState.buildings[iid]], summary)
	_check(int((summary.get("purchased", {}) as Dictionary).get(coal_gid, 0)) > 0,
		"market input pipeline orders production inputs despite construction-reserved inbound")
	BuildingState.remove_building(iid)
	TransportState.pending_transport_shipments.clear()
	get_tree().root.remove_child(fake)
	fake.free()
	MatchState.reset()
	Stockpile.clear_all()
	Power.reset_for_turn()

func _test_idle_labour_pay_policy() -> void:
	# "Worker pay while not running" keys strictly on producing NOTHING. That is what keeps it
	# out of CostSolver: a building with no output never gets a turn report, so it is not in the
	# solver's eligible set and its labour — full or half — cannot reach an imputed cost.
	# Paying a DERATED building less would instead make its unit cost fall as it got sicker.
	MatchState.reset()
	_check(is_equal_approx(LabourState.idle_labour_pay_share, 1.0),
		"idle pay: workers are paid in full by default")
	LabourState.set_idle_labour_pay_share(0.5)
	_check(is_equal_approx(LabourState.idle_labour_pay_share, 0.5), "idle pay: the 50% setting takes")
	LabourState.set_idle_labour_pay_share(0.63)
	_check(is_equal_approx(LabourState.idle_labour_pay_share, 0.5),
		"idle pay: an off-menu value is refused rather than silently accepted")
	LabourState.set_idle_labour_pay_share(0.75)
	_check(is_equal_approx(LabourState.idle_labour_pay_share, 0.75), "idle pay: the 75% setting takes")

	# CostSolver's contract: only buildings with at least one output are eligible. A building
	# that produced nothing is absent from the reports entirely, so the policy cannot move any
	# imputed cost — this asserts the property the policy's safety rests on.
	MatchState.reset()
	MarketState._init_prices_from_catalog()
	Production._building_turn_reports.clear()
	Production._building_turn_reports.append({
		"instance_id": "inst_runs", "building_id": "b_002", "tile_id": "tile_5_10",
		"recipe_id": "r_005", "inputs_consumed": {"g_002": 40, "g_001": 20},
		"outputs_produced": {"g_004": 70}, "power_cost": 16.8, "labour_cost": 8.91,
		"maintenance_cost": 3.0, "inbound_transport": 0.0,
	})
	Production._building_turn_reports.append({
		"instance_id": "inst_idle", "building_id": "b_002", "tile_id": "tile_5_10",
		"recipe_id": "r_005", "inputs_consumed": {}, "outputs_produced": {},
		"power_cost": 0.0, "labour_cost": 8.91, "maintenance_cost": 3.0, "inbound_transport": 0.0,
	})
	CostSolver.solve(Production._building_turn_reports)
	var per_building: Dictionary = CostSolver.last_result.get("per_building", {})
	_check(per_building.has("inst_runs"),
		"cost solver: a producing building is costed")
	_check(not per_building.has("inst_idle"),
		"cost solver: a building that produced nothing is excluded, so its wage bill cannot move any imputed cost")
	Production._building_turn_reports.clear()

func _test_purchase_inventory_seed() -> void:
	# A bought building is a going concern: it arrives with stock to run on. A CONSTRUCTED one
	# gets the ramp financed instead (§5.3's tab) — two different problems, two solutions.
	MatchState.reset()
	Stockpile.clear_all()
	# b_002 runs r_005 (pig iron): iron_ore x40 + coal x20 per turn.
	BuildingState.buildings["inst_bought"] = {
		"instance_id": "inst_bought", "building_id": "b_002", "recipe_id": "r_005",
		"tile_id": "tile_5_10", "owner": "Someone Else", "level": 1,
	}
	BuildingState.set_building_owner("inst_bought", MatchState.LOCAL_PLAYER)
	var ore: int = Stockpile.get_at_tile("tile_5_10", "g_002")
	var coal: int = Stockpile.get_at_tile("tile_5_10", "g_001")
	_check(ore == 40 * MatchState.PURCHASE_SEED_TURNS and coal == 20 * MatchState.PURCHASE_SEED_TURNS,
		"purchase: a bought building is seeded with %d turns of its inputs (ore %d, coal %d)"
			% [MatchState.PURCHASE_SEED_TURNS, ore, coal])

	# Infra and input-less recipes have no inventory to seed.
	BuildingState.buildings["inst_mine"] = {
		"instance_id": "inst_mine", "building_id": "b_001", "recipe_id": "r_001",
		"tile_id": "tile_6_8", "owner": "Someone Else", "level": 1,
	}
	_check(MatchState.seed_purchase_inventory("inst_mine") == 0,
		"purchase: an input-less recipe seeds nothing")

	# Whatever will not fit is held off-tile: visible, drawn on by nobody, and it moves in as
	# capacity frees. It must never be silently dropped — the player paid for it.
	MatchState.reset()
	Stockpile.clear_all()
	MatchState.ghost_holdings.clear()
	MatchState._add_ghost_holding("inst_ghost", "g_001", 75)
	_check(MatchState.ghost_holding_units("inst_ghost") == 75,
		"purchase: goods that do not fit are held for that building alone")
	BuildingState.buildings["inst_ghost"] = {
		"instance_id": "inst_ghost", "building_id": "b_002", "recipe_id": "r_005",
		"tile_id": "tile_5_10", "owner": MatchState.LOCAL_PLAYER, "level": 1,
	}
	MatchState.drain_ghost_holdings()
	_check(Stockpile.get_at_tile("tile_5_10", "g_001") == 75
		and MatchState.ghost_holding_units("inst_ghost") == 0,
		"purchase: held goods move onto the tile once there is room")
	BuildingState.buildings.erase("inst_bought")
	BuildingState.buildings.erase("inst_mine")
	BuildingState.buildings.erase("inst_ghost")
	Stockpile.clear_all()

func _test_purchases() -> void:
	_check(Catalog.buyable_goods().size() > 0 and Catalog.sellable_goods().size() > 0,
		"Catalog exposes buyable + sellable good lists")
	_check(Catalog.is_good_buyable("g_001"), "coal is buyable")
	var before: int = MatchState.get_recurring_transaction_rows().size()
	MatchState.add_recurring_buy("tile_3_8", "g_001", 25)
	var rows: Array = MatchState.get_recurring_transaction_rows()
	_check(rows.size() == before + 1, "recurring buy registers in the dashboard")
	var last: Dictionary = rows[rows.size() - 1]
	_check(str(last.get("type", "")) == "Buy" and int(last.get("qty", 0)) == 25,
		"recurring buy shows as a Buy row")
	var m: float = MatchState.money
	var prev: Dictionary = MatchState.preview_buy("tile_3_8", "g_001", 10)
	_check(not prev.is_empty() and float(prev.get("cost", 0)) > 0.0 and MatchState.money == m,
		"preview_buy returns a cost without spending")

func _test_market_sale_credits() -> void:
	# Output routed to market should be sold and its revenue credited on arrival,
	# not silently lost. (Reproduces the "produced but never stockpiled/consumed/sold".)
	MatchState.reset()
	Stockpile.clear_all()
	MatchState.money = 0.0
	var summary := {"transport_paid": 0.0, "money_out": 0.0, "money_in": 0.0,
		"goods_sales_revenue": 0.0, "sold": {}}
	Production._sell_output_to_market({
		"instance_id": "inst_market_credit",
		"tile_id": "tile_3_8",
	}, Catalog.get_good("g_001"), 20, summary)
	# Drive arrivals for a few turns; a deferred sale should eventually credit.
	for _i in range(25):
		Production._process_transport_arrivals(summary)
		if MatchState.money > 0.0:
			break
	_check(MatchState.money > 0.0, "a market-routed output sale credits revenue (money=%.2f)" % MatchState.money)
	_check(summary.goods_sales_revenue > 0.0, "the sale appears in goods_sales_revenue")

func _test_recurring_sell_multitile() -> void:
	# A recurring sell bound to an empty source tile should still sell the good
	# from another tile that holds it (the fix for "sold once then stopped").
	var src := "tile_3_8"
	var other := "tile_9_5"
	var have: int = Stockpile.get_at_tile(src, "g_001")
	if have > 0:
		Stockpile.consume(src, "g_001", have)
	Stockpile.add(other, "g_001", 25)
	var before: int = Stockpile.get_at_tile(other, "g_001")
	MatchState.add_recurring_sell(src, {"g_001": 10})
	MatchState.run_recurring_and_scheduled_moves()
	var sold: int = before - Stockpile.get_at_tile(other, "g_001")
	_check(sold == 10, "recurring sell draws from another tile when source is empty (sold %d)" % sold)
	if not MatchState.recurring_sells.is_empty():
		MatchState.recurring_sells.pop_back()

func _test_sell_protects_build_materials() -> void:
	# The stuck-construction churn (owner log 2026-07-09): auto-sell sold gathered
	# build materials in the SAME process they arrived (arrivals sub-phase 2, sell
	# sub-phase 9), so direct builds could never find their bill on the tile and
	# awaiting bills gathered over multiple turns were liquidated mid-gather.
	Modifiers.reset()
	MatchState.reset()
	Stockpile.clear_all()
	var t := "tile_16_4"
	# (a) awaiting-project bills are reserved from the surplus.
	Construction.construction_projects["test_bill_proj"] = {
		"status": Construction.STATUS_AWAITING_MATERIALS, "tile_id": t,
		"missing_materials": {"g_023": 3, "g_071": 1},
		"source": {"kind": "market"},
	}
	var bills: Dictionary = Construction.missing_materials_for_tile(t)
	_check(int(bills.get("g_023", 0)) == 3 and int(bills.get("g_071", 0)) == 1,
		"awaiting bill aggregates per tile")
	var reserve: Dictionary = Production.compute_sell_reserve_for_tile(t)
	_check(int(reserve.get("g_023", 0)) >= 3 and int(reserve.get("g_071", 0)) >= 1,
		"sell reserve protects an awaiting construction's missing bill")
	Construction.construction_projects.erase("test_bill_proj")
	# (b) fresh deliveries get one turn of grace before counting as surplus.
	Production._inbound_delivery_this_turn[t] = {"g_023": {"qty": 5.0, "cost": 0.0}}
	_check(Production._arrived_this_turn(t, "g_023") == 5,
		"this-turn arrivals are tracked for the auto-sell grace")
	_check(Production._arrived_this_turn(t, "g_027") == 0,
		"goods that did not arrive this turn have no grace")
	Production._inbound_delivery_this_turn.clear()
	# (c) Existing stock is not grandfathered when a new local consumer appears:
	# Sell Surplus must immediately liquidate the accumulated amount above the
	# lead-time working reserve, while keeping that reserve safe for production.
	var iron_tile := "tile_5_10"
	var iron_id := "g_004"
	var steel_furnace := BuildingState.add_building("b_002", "r_003", iron_tile, "player_1")
	Stockpile.add(iron_tile, iron_id, 600)
	MatchState.enable_sell_surplus(iron_tile)
	# The master order must still clear accumulated stock if a previous per-good
	# order left a restrictive price-impact tolerance on this tile.
	MatchState.set_auto_sell_impact(iron_tile, 0)
	var iron_reserve: Dictionary = Production.compute_sell_reserve_for_tile(iron_tile)
	var iron_before := Stockpile.get_at_tile(iron_tile, iron_id)
	Production._process_production()
	var iron_after := Stockpile.get_at_tile(iron_tile, iron_id)
	_check(iron_before > int(iron_reserve.get(iron_id, 0)),
		"sell reserve test starts with accumulated iron above the working reserve")
	_check(iron_after <= int(iron_reserve.get(iron_id, 0)),
		"sell surplus drains accumulated iron but keeps the lead-time production reserve")
	BuildingState.remove_building(steel_furnace)
	Modifiers.reset()
	MatchState.reset()
	Stockpile.clear_all()

	# (d) The reserve exists to cover a RESUPPLY LEAD, so an input with no lead to cover needs
	# exactly one turn on hand. Two have none: one the tile makes at least as much of as it
	# burns, and one the player has taken off market top-up. Quoting a market lead for either
	# was the SELL half of the pipeline disagreeing with the BUY half — _buy_market_inputs
	# skips both — and it is why a tile that smelted its own ingots sat on two turns of them
	# for ever with Sell all Surplus on, which read as the reserve freezing (owner, 25 Aug).
	var own_tile := "tile_9_9"
	var wire_mill := BuildingState.add_building("b_007", "r_008", own_tile, "player_1")   # burns g_005
	var need := 0
	for input_value: Variant in Catalog.get_recipe("r_008").get("inputs", []):
		var input: Dictionary = input_value
		if str(input.get("good_id", "")) == "g_005":
			need = Production._scaled_input_qty(input, BuildingState.get_building(wire_mill))
	var bought_in: int = int(Production.compute_sell_reserve_for_tile(own_tile).get("g_005", 0))
	_check(need > 0 and bought_in == need,
		"sell reserve: one turn's burn, whether the input is bought or smelted (%d of %d/turn)"
		% [bought_in, need])
	# Now the tile smelts its own, at more than the mill burns.
	var copper_smelter := BuildingState.add_building("b_002", "r_020", own_tile, "player_1")
	var made_here: int = int(Production.compute_sell_reserve_for_tile(own_tile).get("g_005", 0))
	_check(made_here == need,
		"sell reserve: a good the tile makes for itself is held at one turn's use (%d of %d/turn)"
		% [made_here, need])
	BuildingState.remove_building(copper_smelter)
	# ...and the same when the player has simply opted the input out of market top-up.
	MatchState.set_input_tile_only(wire_mill, "g_005", true)
	var tile_only: int = int(Production.compute_sell_reserve_for_tile(own_tile).get("g_005", 0))
	_check(tile_only == need,
		"sell reserve: an input taken off market top-up is held at one turn too (%d of %d/turn)"
		% [tile_only, need])
	MatchState.set_input_tile_only(wire_mill, "g_005", false)
	BuildingState.remove_building(wire_mill)
	Modifiers.reset()
	MatchState.reset()
	Stockpile.clear_all()

func _test_auto_sell_goods() -> void:
	var t := "tile_4_4"
	MatchState.enable_auto_sell_good(t, "g_001")
	_check(MatchState.is_auto_sell_good(t, "g_001"), "per-good auto-sell registers")
	_check(MatchState.should_auto_sell_good(t, "g_001"), "should_auto_sell true for an armed good")
	_check(not MatchState.should_auto_sell_good(t, "g_002"), "should_auto_sell false for an unarmed good")
	_check(MatchState.get_auto_sell_tiles().has(t), "tile appears in the auto-sell tile set")
	# Master order covers every good regardless of per-good arming.
	MatchState.enable_sell_surplus(t)
	_check(MatchState.should_auto_sell_good(t, "g_009"), "master 'sell all' order auto-sells any good")
	MatchState.disable_sell_surplus(t)
	# Disarming the last per-good order removes the tile from the set.
	MatchState.disable_auto_sell_good(t, "g_001")
	_check(not MatchState.is_auto_sell_good(t, "g_001"), "per-good auto-sell clears")
	_check(not MatchState.get_auto_sell_tiles().has(t), "tile drops out once no orders remain")
	# Sell reserve = exactly ONE turn of the local consumers' burn, player-owned buildings
	# only. r_008 eats 24 copper_ingots (g_005)/turn, so the tile keeps 24 and everything
	# above it is surplus. It used to keep need × (market lead + 1); covering the lead here
	# double-booked it against _buy_market_inputs, which already sizes orders against what is
	# in transit, and left a consumer burning 40 sitting on 80 (owner, 25 Aug). NPC buildings
	# reserve nothing.
	var rt := "tile_15_5"
	var riid: String = BuildingState.add_building("b_007", "r_008", rt, "player_1", "reserve_test")
	var reserve: Dictionary = Production.compute_sell_reserve_for_tile(rt)
	var committed: Dictionary = Production.compute_committed_for_tile(rt)
	var need: int = int(committed.get("g_005", 0))
	_check(need > 0, "sell reserve test: recipe commits copper ingots per turn (%d)" % need)
	var kept: int = int(reserve.get("g_005", 0))
	_check(kept == need, "sell reserve keeps exactly one turn of inputs (%d of %d/turn)" % [kept, need])
	BuildingState.remove_building(riid)
	var npc_iid: String = BuildingState.add_building("b_007", "r_008", rt, "npc", "reserve_test_npc")
	_check(int(Production.compute_sell_reserve_for_tile(rt).get("g_005", 0)) == 0,
		"NPC buildings reserve nothing from the player's sell surplus")
	BuildingState.remove_building(npc_iid)

func _test_price_impact() -> void:
	var g: int = EconomyConfig.GLUT_UNITS
	_check(EconomyConfig.price_impact_pct_for(g) == 0, "selling up to the glut has no price impact")
	_check(EconomyConfig.price_impact_pct_for(g + 1) == 1, "just over the glut is 1% impact")
	_check(EconomyConfig.price_impact_pct_for(2 * g) == 1, "twice the glut is still 1%")
	_check(EconomyConfig.price_impact_pct_for(2 * g + 1) == 2, "past 2x glut is 2%")
	_check(EconomyConfig.price_impact_pct_for(1000 * g) == EconomyConfig.MAX_PRICE_IMPACT_PCT, "impact caps at the max")
	_check(EconomyConfig.units_cap_for_impact(0) == g, "no-impact cap is the glut")
	_check(EconomyConfig.units_cap_for_impact(1) == 2 * g, "1% cap is twice the glut")
	MatchState.set_auto_sell_impact("tile_4_5", 0)
	_check(MatchState.auto_sell_unit_cap("tile_4_5") == g, "tile NONE tolerance caps at the glut")
	MatchState.set_auto_sell_impact("tile_4_5", 1)
	_check(MatchState.auto_sell_unit_cap("tile_4_5") == 2 * g, "tile 1% tolerance caps at 2x glut")
	MatchState.set_auto_sell_impact("tile_4_5", MatchState.IMPACT_ANY)
	_check(MatchState.auto_sell_unit_cap("tile_4_5") > 1000000, "tile ANY tolerance is effectively uncapped")
	_check(MatchState.get_auto_sell_impact("tile_unset_99") == MatchState.IMPACT_ANY, "default tolerance is ANY")

# Net-volume thresholds accrue symmetric glut/deficit impact; rates doubled 2026-09-07.
func _test_price_impact_thresholds() -> void:
	_check(EconomyConfig.price_impact_rate(32, 32) == 0.0, "1x exactly is under the bite")
	_check(EconomyConfig.price_impact_rate(33, 32) == 0.1,
		"just over 1x accrues the faintest rung — a modified single building registers")
	_check(EconomyConfig.price_impact_rate(-33, 32) == 0.1, "the 1x rung applies to BUYING too")
	_check(EconomyConfig.price_impact_rate(96, 32) == 0.1, "3x exactly is still the 1x rung (strictly greater than)")
	_check(EconomyConfig.price_impact_rate(97, 32) == 0.2, "just over 3x steps up")
	_check(EconomyConfig.price_impact_rate(161, 32) == 0.4, "just over 5x steps up")
	_check(EconomyConfig.price_impact_rate(193, 32) == 0.6, "just over 6x steps up")
	_check(EconomyConfig.price_impact_rate(225, 32) == 0.8 and EconomyConfig.price_impact_rate(257, 32) == 1.0 \
			and EconomyConfig.price_impact_rate(289, 32) == 1.2 and EconomyConfig.price_impact_rate(321, 32) == 1.4 \
			and EconomyConfig.price_impact_rate(353, 32) == 1.6,
		"the 6x-11x rungs step by exactly 0.2")
	_check(EconomyConfig.price_impact_rate(384, 32) == 1.6, "12x exactly is still the 11x rung")
	_check(EconomyConfig.price_impact_rate(385, 32) == 2.0, "over 12x jumps 1.6 -> 2.0 — flooding gets a step change")
	_check(EconomyConfig.price_impact_rate(32000, 32) == 2.0, "the flooding rung is the top — it saturates by design")
	_check(EconomyConfig.price_impact_rate(1000, 0) == 0.0, "no base output -> no impact")
	# A NORMAL multi-building chain must not be punished: 3 factories of one good is 3x,
	# which sits on the faintest rung, not the flooding one.
	_check(EconomyConfig.price_impact_rate(84, 28) == 0.1, "a 3-factory chain sits on the faintest rung")
	# Asymmetric cap: gluts bottom out at 40% of base price, deficits top out at 250%.
	_check(EconomyConfig.PRICE_IMPACT_FLOOR_PCT == -60.0 and EconomyConfig.PRICE_IMPACT_CEILING_PCT == 150.0,
		"price is capped between 40% and 250% of base")
	# Threshold inflation is LINEAR (owner 2026-08-29): +25% of the ORIGINAL every 20 turns.
	_check(EconomyConfig.impact_threshold_scale(1) == 1.0 and EconomyConfig.impact_threshold_scale(20) == 1.0,
		"no threshold inflation in the first 20 turns")
	_check(EconomyConfig.impact_threshold_scale(21) == 1.25 and EconomyConfig.impact_threshold_scale(40) == 1.25,
		"turns 21-40 run at x1.25")
	_check(EconomyConfig.impact_threshold_scale(41) == 1.5 and EconomyConfig.impact_threshold_scale(300) == 4.5,
		"linear schedule: x1.50 from t41, x4.50 by t300 — NOT compounding")
	_check(EconomyConfig.price_impact_rate(40, 32, 1.25) == 0.0 and EconomyConfig.price_impact_rate(41, 32, 1.25) == 0.1,
		"an inflated threshold moves the bite point")

	# Accrual, the rolling-window hold, walk-back recovery, and the caps — driven
	# through the real per-turn pipeline on a scratch good id.
	var gid := str(Catalog.get_good_by_internal_name("coal").get("id", ""))
	var coal_base: int = Catalog.base_output_for_good(gid)
	_check(coal_base > 0, "coal has a base building output")
	var scale_now: float = EconomyConfig.impact_threshold_scale(int(TurnManager.current_turn))
	# Flush any volume an earlier test left on the books BEFORE measuring — residue would
	# push a sample into the wrong rung and shift every expected value below.
	MarketState._turn_sold.clear()
	MarketState._turn_bought.clear()
	MarketState.impact_pct.erase(gid)
	MarketState._net_history.erase(gid)
	MarketState._recovery_step.erase(gid)
	var base_before: float = MarketState.get_base_price_now(gid)
	# Sell in the flooding rung (>12x even after inflation) so the sample is unambiguous.
	var flood_units: int = int(ceilf(13.0 * float(coal_base) * scale_now))
	MarketState.record_market_sale_volume(gid, flood_units)
	MarketState.tick_turn()
	_check(absf(MarketState.get_impact_pct(gid) + 2.0) < 0.0001, "one flooding sell turn accrues -2.0%")
	_check(absf(MarketState.get_price(gid) - base_before * (1.0 - 2.0 / 100.0)) < 0.0001,
		"impact multiplies the STATIC base price — decay is retired, prices no longer drift")
	# A quiet turn inside a loud window HOLDS: the rolling average is still over 1x.
	MarketState.tick_turn()
	_check(absf(MarketState.get_impact_pct(gid) + 2.0) < 0.0001,
		"a quiet turn does not recover while the rolling average stays loud — no pulsing exploit")
	# Net buying pushes the impact UP at the same ladder rates (deficit side).
	# Fresh window first: the signed rolling average NETS sells against buys, so a
	# buy-flood straight after a sell-flood averages to quiet — by design (buying
	# back what you sold is not a deficit).
	MarketState.impact_pct.erase(gid)
	MarketState._net_history.erase(gid)
	MarketState._recovery_step.erase(gid)
	MarketState.record_market_buy_volume(gid, flood_units)
	MarketState.tick_turn()
	_check(absf(MarketState.get_impact_pct(gid) - 2.0) < 0.0001,
		"a flooding BUY turn accrues +2.0% — the same ladder, opposite sign")
	# Walk-back: give the good a deep glut, then go quiet. The window drains first
	# (holding), then the walk-back closes the whole gap in exactly 10 turns.
	MarketState.impact_pct[gid] = -30.0
	MarketState._net_history[gid] = [float(flood_units)]
	MarketState._recovery_step.erase(gid)
	var hold_turns := 0
	var recover_turns := 0
	var guard := 0
	while MarketState.get_impact_pct(gid) != 0.0 and guard < 40:
		var before: float = MarketState.get_impact_pct(gid)
		MarketState.tick_turn()
		if MarketState.get_impact_pct(gid) == before:
			hold_turns += 1
		else:
			recover_turns += 1
		guard += 1
	_check(guard < 40, "a stopped glut recovers fully in bounded time")
	_check(recover_turns == EconomyConfig.PRICE_IMPACT_RECOVERY_TURNS,
		"the walk-back closes the gap in exactly 10 turns (-3.0/turn from -30)")
	_check(hold_turns < EconomyConfig.PRICE_IMPACT_RECOVERY_TURNS,
		"the hold lasts only until the rolling window drains")
	# The glut floor: a deep impact plus a flooding turn clamps at -60 (price 40% of base).
	MarketState.impact_pct[gid] = -59.5
	MarketState._net_history.erase(gid)
	MarketState._recovery_step.erase(gid)
	MarketState.record_market_sale_volume(gid, flood_units)
	MarketState.tick_turn()
	_check(absf(MarketState.get_impact_pct(gid) + 60.0) < 0.0001, "impact floors at -60%")
	_check(absf(MarketState.get_price(gid) - base_before * 0.4) < 0.0001, "the floored price is 40% of base")
	# Save round-trip keeps the impact AND the rolling window; prices re-anchor to catalog.
	var snap: Dictionary = MarketState.export_state()
	MarketState.impact_pct.clear()
	MarketState._net_history.clear()
	MarketState.import_state(snap)
	_check(absf(MarketState.get_impact_pct(gid) + 60.0) < 0.0001, "impact survives save/load")
	_check(MarketState._net_history.has(gid), "the rolling window survives save/load")
	_check(absf(float(MarketState.prices.get(gid, 0.0)) - float(Catalog.get_good(gid).get("base_price", 0.0))) < 0.0001,
		"import re-anchors base prices to the catalog (decay retired; old decayed saves move UP)")
	# The walk-back settles exactly to zero and erases its bookkeeping.
	MarketState.impact_pct[gid] = -0.05
	MarketState._net_history.erase(gid)
	MarketState._recovery_step.erase(gid)
	for i in EconomyConfig.PRICE_IMPACT_RECOVERY_TURNS:
		MarketState.tick_turn()
	_check(MarketState.get_impact_pct(gid) == 0.0 and not MarketState.impact_pct.has(gid) \
			and not MarketState._net_history.has(gid),
		"the walk-back settles exactly to zero and erases the entry and its window")
	# UI helper: one threshold per ladder rung, at today's inflation multiplier.
	var th: PackedInt32Array = MarketState.impact_thresholds(gid)
	_check(th.size() == EconomyConfig.PRICE_IMPACT_LADDER.size(),
		"impact_thresholds returns one entry per ladder rung")
	_check(th[0] == int(floorf(float(coal_base) * scale_now)),
		"the first threshold is 1x base output at today's inflation")
	MarketState.impact_pct.erase(gid)
	MarketState._net_history.erase(gid)
	MarketState._recovery_step.erase(gid)
	MarketState.prices_updated.emit()

func _test_buy_price() -> void:
	var gid := "g_001"
	var sell := MarketState.get_price(gid)
	var buy := MarketState.get_buy_price(gid)
	_check(absf(buy - sell * (1.0 + EconomyConfig.MARKET_BUY_MARKUP)) < 0.0001,
		"buy price is the sale price plus the market markup")
	_check(buy > sell, "buying costs more than selling (spread)")
	# preview_buy should value goods at the buy price.
	var prev: Dictionary = MatchState.preview_buy("tile_3_8", gid, 10)
	if not prev.is_empty():
		_check(absf(float(prev.get("goods_cost", 0.0)) - 10.0 * buy) < 0.01,
			"preview_buy values goods at the buy price")

## The GOOD PRICES tab, which the special-orders test never builds — it jumps straight to
## tab 2, which is how a null-deref in _build_prices_tab shipped unnoticed.
##
## HONEST SCOPE: this does NOT catch that class of bug, and it was checked against the
## broken code to be sure. A GDScript runtime error prints and execution CONTINUES, so the
## bad `_detach(null)` left no observable state difference — every assertion below passed
## either way. What catches it is scanning a windowed run's output for "SCRIPT ERROR"
## (tools/market_shot.tscn reproduces it in one line); state assertions cannot.
##
## What this DOES cover, both previously untested: that the prices tab builds and rebuilds
## with the header wrapped in a zero-min-width clip (the fix that keeps the widened table
## from forcing the panel off-screen), and the column contract the owner set — the rate is
## the header, each cell carries that good's own quantity.
func _test_market_prices_tab_impact_columns() -> void:
	var panel: Control = load("res://scenes/market_panel.tscn").instantiate()
	add_child(panel)
	panel.call("_ensure_built")
	var tabs: TabContainer = panel.get("_tabs")
	tabs.current_tab = 0
	panel.call("_ensure_current_tab_built")

	# The header must live inside the clipping wrapper, and the wrapper must report NO
	# minimum width — that is what stops the widened table forcing the panel off-screen.
	var clip: Control = panel.get("_header_clip")
	var header: Control = panel.get("header_static")
	_check(clip != null and header != null and header.get_parent() == clip,
		"market prices tab: the header is wrapped in its clipping container")
	_check(clip != null and clip.custom_minimum_size.x == 0.0,
		"market prices tab: the header clip reports no minimum width")
	_check(header != null and header.get_combined_minimum_size().x > 0.0,
		"market prices tab: the header itself still sizes to its columns")

	# Toggling the ladder rebuilds the tab — the path that used to deref a null clip.
	panel.call("_set_impact_expanded", true)
	_check(panel.get("_impact_expanded"), "market prices tab: impact columns expand")
	_check(header.get_parent() == panel.get("_header_clip"),
		"market prices tab: the header survives an expand rebuild inside its clip")
	panel.call("_set_impact_expanded", false)
	_check(not panel.get("_impact_expanded"), "market prices tab: impact columns collapse again")
	_check(header.get_parent() == panel.get("_header_clip"),
		"market prices tab: the header survives a collapse rebuild inside its clip")

	# Column contract (owner 2026-08-29): the RATE is the header, and each cell carries that
	# good's own unit threshold — not the percentage.
	panel.call("_set_impact_expanded", true)
	var rows: Array = panel.get("rows")
	var checked := false
	for row in rows:
		if not is_instance_valid(row) or str(row.get("good_id")) == "":
			continue
		var thresholds: PackedInt32Array = MarketState.impact_thresholds(str(row.get("good_id")))
		if thresholds.is_empty():
			continue
		var cells: Array = row.get("_rung_cells")
		_check(cells.size() == EconomyConfig.PRICE_IMPACT_LADDER.size(),
			"market prices tab: one rung cell per ladder step")
		_check(str((cells[0] as Label).text) == row.call("_thousands", thresholds[0]),
			"market prices tab: a rung cell shows the good's quantity, not the rate")
		checked = true
		break
	_check(checked, "market prices tab: at least one produced good exercised the rung cells")
	panel.queue_free()

## Base output is the yardstick every price-impact threshold is a multiple of, so WHICH
## recipe defines it is load-bearing. It is the good's best BASE recipe — one with an empty
## tech_unlock_req — not the best recipe in the game (owner 2026-08-29): steel read 54/turn
## off Electric Arc Steelmaking, behind research_metal_004, when the player starts with
## Steelmaking at 44.
func _test_base_output_ignores_gated_recipes() -> void:
	var steel := str(Catalog.get_good_by_internal_name("steel").get("id", ""))
	_check(Catalog.base_output_for_good(steel) == 44,
		"base output: steel is 44 (Steelmaking), not 54 (Electric Arc, tech-gated)")

	# The rule, stated generally: no good may take its base output from a gated recipe while
	# an ungated one exists. This is what stops a future recipe silently moving a threshold.
	var offenders: Array = []
	for good in Catalog.all_goods():
		var gid := str(good.get("id", ""))
		var base := Catalog.base_output_for_good(gid)
		if base <= 0:
			continue
		var best_ungated := 0
		for r in Catalog.recipes_producing(gid):
			if str(r.get("tech_unlock_req", "")) == "":
				best_ungated = maxi(best_ungated, Catalog.recipe_output_qty(r, gid))
		if best_ungated > 0 and base != best_ungated:
			offenders.append("%s (base %d, ungated best %d)" % [str(good.get("internal_name", gid)), base, best_ungated])
	_check(offenders.is_empty(),
		"base output: every good with an ungated recipe uses it as its yardstick (%s)"
			% ("none" if offenders.is_empty() else ", ".join(PackedStringArray(offenders))))

	# The fallback: a good whose every producer is gated still gets a real threshold, because
	# a base output of 0 would exempt it from price impact altogether.
	var gated_only := 0
	for good in Catalog.all_goods():
		var gid2 := str(good.get("id", ""))
		var producers: Array = Catalog.recipes_producing(gid2)
		if producers.is_empty():
			continue
		var has_ungated := false
		for r in producers:
			if str(r.get("tech_unlock_req", "")) == "":
				has_ungated = true
		if not has_ungated:
			gated_only += 1
			_check(Catalog.base_output_for_good(gid2) > 0,
				"base output: %s is gated-only and still takes impact" % str(good.get("internal_name", gid2)))
	_check(gated_only > 0, "base output: the gated-only fallback is actually exercised (%d goods)" % gated_only)
