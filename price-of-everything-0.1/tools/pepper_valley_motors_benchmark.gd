extends Node
## Real legacy turns plus a clearly labelled, matched-throughput middleman reference.
## Does not implement intermediary gameplay or replace the future two-ruleset test.
const Paths := preload("res://scripts/app_paths.gd")
const Harness := preload("res://tools/shot_harness.gd")
const SPEC := "res://tests/scenarios/pepper_valley_motors_benchmark.json"
const TARGETED_SPEC := "res://tests/scenarios/pepper_valley_motors_targeted_gains.json"
const FEE40_SPEC := "res://tests/scenarios/pepper_valley_motors_middleman_ports.json"
const FURNACE_SPEC := "res://tests/scenarios/pepper_valley_motors_local_steel.json"
const OUT := "/tmp/pepper-valley-motors-benchmark"
var failures: Array[String] = []
var spec: Dictionary
var spec_path := FEE40_SPEC
var stage := "base"
var rows: Array = []
var sample: Array = []
var route_mode := "roads"
var output_dir := OUT
var steel_instance := ""
var rail_instances: Array[String] = []
var rail_tiles: Array = []
var owned_rail_tiles: Array = []
var rail_owned_limit := -1
var rail_variant_path := "res://tests/scenarios/pepper_valley_motors_rail.json"

func _enter_tree() -> void:
	if OS.get_cmdline_user_args().has("--control"):
		spec_path = SPEC
	elif OS.get_cmdline_user_args().has("--targeted"):
		spec_path = TARGETED_SPEC
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--stage="):
			stage = arg.trim_prefix("--stage=")
	if stage in ["furnace", "furnace-jit"]:
		spec_path = FURNACE_SPEC
	if OS.get_cmdline_user_args().has("--rail"):
		route_mode = "rail"
		output_dir += "-rail"
		if OS.get_cmdline_user_args().has("--three-owned"):
			rail_owned_limit = 3
			output_dir += "-three-owned"
			rail_variant_path = "res://tests/scenarios/pepper_valley_motors_rail_three_owned.json"
	output_dir += "-control" if spec_path == SPEC else ("-targeted" if spec_path == TARGETED_SPEC else "-fee40")
	if stage != "base":
		output_dir += "-" + stage
	Paths._base = output_dir + "/runtime"
	RunMetrics.enabled = false

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[PepperBenchmark] " + label)

func _ready() -> void:
	Harness.prepare_window(get_window(), Vector2i(1280, 720))
	Harness.arm_watchdog(self, 240.0)
	AudioServer.set_bus_mute(0, true)
	DirAccess.make_dir_recursive_absolute(output_dir)
	spec = JSON.parse_string(FileAccess.get_file_as_string(spec_path))
	if stage == "early":
		spec.measurement.minimum_sample_turn = 10
	SaveLoad.autosave_enabled = false
	SaveLoad.prepare_new_game(str(spec.start_file), {"ruleset": spec.get("ruleset_overrides", {})})
	var world: Node = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	for frame in 160:
		await get_tree().process_frame
	TurnManager.fast_mode = true
	# Controlled benchmark only: retain the real PROCESS pipeline and turn signals,
	# but remove unrelated unlocks, events, decisions and public-road expansion.
	for system in [ResearchState, EventScheduler, DecisionState]:
		var hook := Callable(system, "_on_phase_started")
		if TurnManager.phase_started.is_connected(hook):
			TurnManager.phase_started.disconnect(hook)
	var map_hook := Callable(world, "_on_turn_advanced")
	if TurnManager.turn_advanced.is_connected(map_hook):
		TurnManager.turn_advanced.disconnect(map_hook)
	DecisionState.enabled = false
	DecisionState.auto_resolve = true
	SolvencyState.enabled = false
	var tile := str(spec.tile_id)
	check(Catalog.tile_name(tile) == str(spec.tile_name), "benchmark city identity")
	var owned: Array = []
	for building: Dictionary in BuildingState.buildings.values():
		if BuildingState.is_player_owned(building):
			owned.append(building)
	check(owned.size() == 1, "exactly one player-owned factory")
	if owned.size() != 1:
		get_tree().quit(1)
		return
	var factory: Dictionary = owned[0]
	check(str(factory.tile_id) == tile and str(factory.recipe_id) == str(spec.recipe_id), "factory site and recipe")
	var recipe := Catalog.get_recipe(str(spec.recipe_id))
	var inputs := _manifest(recipe.inputs)
	var outputs := _manifest(recipe.outputs)
	check(inputs == _named_manifest(spec.inputs), "versioned input quantities")
	check(outputs == _named_manifest(spec.outputs), "versioned output quantities")
	if stage in ["output", "research"]:
		Modifiers.add({"id": "pepper_output_trial", "domain": "recipe_output", "target": str(spec.recipe_id),
			"pct": 10.0, "label": "Benchmark: +10% output", "source": "benchmark"})
		for gid in outputs:
			outputs[gid] = int(round(float(outputs[gid]) * 1.1))
	if stage == "research":
		# Apply the actual rewards; acquisition time/cost is outside this comparison.
		Modifiers.add(Modifiers.UNLOCK_MODIFIERS["research_logi_001"].duplicate(true))
		Modifiers.add(Modifiers.UNLOCK_MODIFIERS["research_logi_011"].duplicate(true))
	var produced_outputs := outputs.duplicate()
	if stage in ["furnace", "furnace-jit"]:
		steel_instance = BuildingState.add_building("b_002", "r_003", tile, MatchState.LOCAL_PLAYER)
		var steel_recipe := Catalog.get_recipe("r_003")
		var steel_gid := str(Catalog.get_good_by_internal_name("steel").id)
		MatchState.set_output_stockpile_destination(steel_instance, tile, steel_gid)
		MatchState.enable_auto_sell_good(tile, steel_gid)
		inputs.erase(steel_gid)
		for gid in _manifest(steel_recipe.inputs):
			inputs[gid] = int(inputs.get(gid, 0)) + int(_manifest(steel_recipe.inputs)[gid])
		outputs[steel_gid] = 12
		produced_outputs[steel_gid] = 44
	if stage in ["jit", "furnace-jit"]:
		ResearchState.grant_unlock("Just-in-Time Logistics")
		check(ResearchState.is_unlocked("Just-in-Time Logistics"), "JIT reward enabled")
	var expected_flow := 0
	for quantity in inputs.values() + outputs.values():
		expected_flow += int(quantity)
	check(int(recipe.energy_req) == int(spec.energy_req), "versioned power requirement")
	check(TransportState.pending_transport_shipments.is_empty(), "no seeded shipment pipeline")
	check(Stockpile.get_all_totals().is_empty(), "no gifted input stock")
	if route_mode == "rail":
		_install_owned_rail(tile, TransportService.nearest_port_tile(tile))
	var routes: Dictionary = {}
	for gid: String in inputs:
		var quote := TransportService.quote_market_buy(tile, gid, int(inputs[gid]))
		check(not quote.is_empty(), "input route exists: " + gid)
		if not quote.is_empty():
			routes["buy:" + gid] = quote
			_check_route_mode(quote.route)
	var sale_quote := TransportService.quote_market_sell(tile, outputs)
	check(not sale_quote.is_empty(), "output route exists")
	if not sale_quote.is_empty():
		routes["sell"] = sale_quote
		_check_route_mode(TransportService.route_to_nearest_port(tile, str(outputs.keys()[0])))
	var provider_inputs := inputs.duplicate()
	var provider_outputs := outputs.duplicate()
	if steel_instance != "":
		# Outsourced buildings trade independently; only direct logistics shares steel.
		var steel_gid := str(Catalog.get_good_by_internal_name("steel").id)
		provider_inputs[steel_gid] = 32
		provider_outputs[steel_gid] = 44
	var initial_prices := MarketState.prices.duplicate(true)
	var starting_cash := MatchState.money
	var minimum_cash := starting_cash
	var first_production := 0
	var first_receipt := 0
	var previous_inventory := ""
	var first_regular := 0
	for index in int(spec.measurement.max_turns):
		MarketState.prices = initial_prices.duplicate(true)
		MarketState.impact_pct.clear()
		var turn := TurnManager.current_turn
		var arrivals: Dictionary = {}
		var freight_weight := 0.0
		var freight_value := 0.0
		for shipment: Dictionary in TransportState.pending_transport_shipments:
			if int(shipment.get("turns_remaining", 0)) <= 1 and bool(shipment.get("is_purchase", false)):
				var gid := str(shipment.get("good_id", ""))
				arrivals[gid] = int(arrivals.get(gid, 0)) + int(shipment.get("qty", 0))
				var parts := _base_freight_parts(gid, int(shipment.get("qty", 0)), shipment)
				freight_weight += float(parts.weight)
				freight_value += float(parts.value)
		var reference_goods_in := 0.0
		var reference_goods_out := 0.0
		for gid: String in inputs:
			reference_goods_in += int(inputs[gid]) * MarketState.get_buy_price(gid)
		for gid: String in outputs:
			reference_goods_out += int(outputs[gid]) * MarketState.get_sale_price(gid)
		var provider_goods_in := 0.0
		var provider_goods_out := 0.0
		for gid: String in provider_inputs:
			provider_goods_in += int(provider_inputs[gid]) * MarketState.get_buy_price(gid)
		for gid: String in provider_outputs:
			provider_goods_out += int(provider_outputs[gid]) * MarketState.get_sale_price(gid)
		var cash_before := MatchState.money
		var rail_maintenance := 0.0
		var rail_labour := 0.0
		for iid: String in rail_instances:
			var rail := BuildingState.get_building(iid)
			rail_maintenance += Production._calculate_maintenance_cost(rail)
			rail_labour += Production._calculate_labour_cost(rail)
		TurnManager.commit_turn()
		await TurnManager.turn_resolution_completed
		var summary := Production.last_turn_summary.duplicate(true)
		minimum_cash = minf(minimum_cash, MatchState.money)
		check(absf(MatchState.money - cash_before - Production.cash_change_of(summary)) < 0.01, "cash reconciliation turn %d" % turn)
		if not summary.produced.is_empty() and first_production == 0:
			first_production = turn
		if float(summary.goods_sales_revenue) > 0.0 and first_receipt == 0:
			first_receipt = turn
		var transit := _transit_totals()
		var stock := Stockpile.get_tile_totals(tile).duplicate(true)
		var inventory_signature := JSON.stringify([stock, transit])
		var regular := _same_quantities(summary.produced, produced_outputs) and _same_quantities(summary.purchased, inputs) \
			and _same_quantities(arrivals, inputs) and _same_quantities(summary.sold, outputs) \
			and inventory_signature == previous_inventory
		previous_inventory = inventory_signature
		if regular and first_regular == 0:
			first_regular = turn
		var common_costs := float(summary.labour_paid) + float(summary.maintenance_paid) + float(summary.power_purchase_cost) - rail_maintenance - rail_labour
		var direct_logistics := float(summary.transport_paid) + float(summary.warehousing_paid) + rail_maintenance + rail_labour
		var direct_contribution := float(summary.goods_sales_revenue) - float(summary.goods_purchased_cost) - common_costs - direct_logistics
		# Pure decomposition of the tariff; actual debits still come from Production.
		# Prices and routes are controlled, so arrival-time base values match dispatch.
		for gid: String in outputs:
			var parts := _base_freight_parts(gid, mini(int(outputs[gid]), int(summary.produced.get(gid, 0))), TransportService.route_to_nearest_port(tile, gid))
			freight_weight += float(parts.weight)
			freight_value += float(parts.value)
		var breakdown: Dictionary = summary.transport_breakdown
		var land_actual := float(breakdown.get(route_mode, 0.0))
		var congestion := land_actual - freight_weight - freight_value
		var port_flat := float(breakdown.get("port_fees", 0.0))
		var port_buy := float(breakdown.get("port_inbound", 0.0))
		var port_sell := float(breakdown.get("port_insurance", 0.0)) + float(breakdown.get("port_outbound", 0.0))
		check(is_zero_approx(EconomyConfig.SEAPORT_BASE_FEE_PER_GOOD), "port inbound decomposition assumes retired flat fee")
		var other_transport := float(summary.transport_paid) - land_actual - port_flat - port_buy - port_sell
		if steel_instance == "" or regular:
			check(absf(other_transport) < 0.01 and congestion >= -0.01, "transport decomposition turn %d" % turn)
		var middleman_inputs := float(spec.middleman.purchase_fee_per_factory_batch)
		var middleman_outputs := float(spec.middleman.sale_fee_per_factory_batch)
		var middleman_storage := float(spec.middleman.get("warehousing_fee_per_factory_cycle", 0.0))
		var middleman_fee := middleman_inputs + middleman_outputs + middleman_storage
		check(is_equal_approx(middleman_fee, float(spec.middleman.get("total_fee_per_full_cycle", middleman_fee))), "middleman breakdown sums to total")
		var middleman_local_service := 0.0
		if steel_instance != "":
			middleman_inputs += float(spec.furnace_extension.procurement_fee)
			middleman_outputs += float(spec.furnace_extension.sales_fee)
			middleman_storage += float(spec.furnace_extension.warehousing_fee)
			middleman_fee = middleman_inputs + middleman_outputs + middleman_storage + middleman_local_service
			check(is_equal_approx(middleman_fee, float(spec.furnace_extension.combined_middleman_fee)), "combined local-steel fee")
		if regular:
			check(absf(float(summary.goods_purchased_cost) - reference_goods_in) < 0.01, "matched input value turn %d" % turn)
			check(absf(float(summary.goods_sales_revenue) - reference_goods_out) < 0.01, "matched output value turn %d" % turn)
		var row := {"turn": turn, "regular": regular, "produced": summary.produced, "ordered": summary.purchased,
			"arrived_inputs": arrivals, "paid_sales": summary.sold, "stock": stock, "transit": transit,
			"jit_fed": Production.get_jit_fed_for_tile(tile), "direct_feed": Production._direct_feed.duplicate(true),
			"cash_change": Production.cash_change_of(summary), "goods_purchases": summary.goods_purchased_cost,
			"goods_receipts": summary.goods_sales_revenue, "factory_costs": common_costs,
			"transport": summary.transport_paid, "transport_breakdown": summary.transport_breakdown,
			"freight_weight_distance": freight_weight, "freight_ad_valorem": freight_value,
			"congestion": congestion, "port_flat_fee": port_flat, "port_import_ad_valorem": port_buy,
			"port_export_ad_valorem": port_sell, "other_transport_fees": other_transport,
			"infrastructure_maintenance": rail_maintenance, "infrastructure_labour": rail_labour,
			"factory_labour": float(summary.labour_paid) - rail_labour,
			"factory_maintenance": float(summary.maintenance_paid) - rail_maintenance,
			"factory_power": summary.power_purchase_cost,
			"warehousing": summary.warehousing_paid, "direct_logistics": direct_logistics,
			"direct_operating_contribution": direct_contribution, "middleman_fee_reference": middleman_fee,
			"middleman_input_fee_reference": middleman_inputs, "middleman_output_fee_reference": middleman_outputs,
			"middleman_warehousing_fee_reference": middleman_storage,
			"middleman_local_transfer_storage_fee_reference": middleman_local_service,
			"middleman_operating_contribution_reference": provider_goods_out - provider_goods_in - common_costs - middleman_fee if regular else null,
			"middleman_goods_purchases_reference": provider_goods_in, "middleman_goods_receipts_reference": provider_goods_out,
			"middleman_batch_funding_reference": provider_goods_in + middleman_inputs + middleman_storage + middleman_local_service}
		rows.append(row)
		if regular and turn >= int(spec.measurement.minimum_sample_turn):
			check(absf(congestion) < 0.01, "no congestion surcharge for one factory turn %d" % turn)
			for link: Dictionary in TransportState.active_links():
				check(float(link.get("flow", 0)) <= expected_flow, "steady tile throughput at most %d units" % expected_flow)
			sample.append(row)
		else:
			sample.clear()
		if sample.size() >= int(spec.measurement.consecutive_regular_turns):
			break
	check(sample.size() == int(spec.measurement.consecutive_regular_turns), "ten consecutive steady shipment turns")
	check(LoanState.loans.is_empty(), "benchmark did not borrow")
	var rail_variant: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(rail_variant_path)) if route_mode == "rail" else {}
	if not rail_variant.is_empty():
		rail_variant.base_contract = spec_path
	var report := {"benchmark_id": spec.benchmark_id, "version": spec.version, "spec": spec,
		"stage": stage, "effective_outputs": outputs, "effective_inputs": inputs, "expected_production": produced_outputs, "provider_external_inputs": provider_inputs, "provider_external_outputs": provider_outputs, "steel_instance": steel_instance, "modifiers": Modifiers.export_state(),
		"congestion_accounting_version": TransportState.FLOW_ACCOUNTING_VERSION,
		"route_mode": route_mode, "owned_rail_tiles": owned_rail_tiles, "rail_corridor_tiles": rail_tiles,
		"rail_variant": rail_variant,
		"route_quotes_at_start": routes, "starting_cash": starting_cash, "factory": factory,
		"first_production_turn": first_production, "first_receipt_turn": first_receipt,
		"first_regular_shipment_turn": first_regular, "settled_links": TransportState.active_links(),
		"observed_run_cash_drawdown": starting_cash - minimum_cash,
		"observed_startup_cash_drawdown": _startup_drawdown(first_regular),
		"middleman_status": "reference arithmetic only; no middleman simulation executed",
		"comparison_basis": "same factory production at controlled prices; direct chain shares steel, provider buildings trade independently; contribution before tax, financing and capital costs",
		"sample": sample, "means": _means(), "failures": failures, "turns": rows}
	var file := FileAccess.open(output_dir + "/result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("[PepperBenchmark] ", JSON.stringify({"means": report.means, "first_production": first_production,
		"first_receipt": first_receipt, "failures": failures, "result": output_dir + "/result.json"}))
	get_tree().quit(0 if failures.is_empty() else 1)

func _manifest(items: Array) -> Dictionary:
	var result := {}
	for item: Dictionary in items:
		result[str(item.good_id)] = int(item.qty)
	return result

func _named_manifest(named: Dictionary) -> Dictionary:
	var result := {}
	for key: String in named:
		result[str(Catalog.get_good_by_internal_name(key).id)] = int(named[key])
	return result

func _same_quantities(actual: Dictionary, expected: Dictionary) -> bool:
	for key: String in expected:
		var value: Variant = actual.get(key, 0)
		var qty := int(value.get("qty", 0)) if value is Dictionary else int(value)
		if qty != int(expected[key]):
			return false
	return true

func _check_route_mode(route: Dictionary) -> void:
	var found := false
	for leg: Dictionary in route.get("legs", []):
		var mode := str(leg.get("mode", ""))
		found = found or mode == route_mode
		check(mode == route_mode, "direct benchmark mode must be " + route_mode + ", got " + mode)
	check(found, "route has explicit " + route_mode + " legs, not distance fallback")

func _transit_totals() -> Dictionary:
	var totals := {"buy": {}, "sell": {}}
	for shipment: Dictionary in TransportState.pending_transport_shipments:
		if bool(shipment.get("is_purchase", false)):
			var gid := str(shipment.good_id)
			totals.buy[gid] = int(totals.buy.get(gid, 0)) + int(shipment.qty)
		elif bool(shipment.get("is_sale", false)):
			for item: Dictionary in shipment.get("sale_record", {}).get("items", []):
				var gid := str(item.good_id)
				totals.sell[gid] = int(totals.sell.get(gid, 0)) + int(item.qty)
	return totals

func _means() -> Dictionary:
	var result := {}
	if sample.is_empty():
		return result
	for key in ["goods_purchases", "goods_receipts", "factory_costs", "transport", "warehousing", "direct_logistics", "direct_operating_contribution", "middleman_fee_reference", "middleman_operating_contribution_reference", "middleman_batch_funding_reference", "middleman_input_fee_reference", "middleman_output_fee_reference", "middleman_warehousing_fee_reference", "middleman_local_transfer_storage_fee_reference", "middleman_goods_purchases_reference", "middleman_goods_receipts_reference", "freight_weight_distance", "freight_ad_valorem", "congestion", "port_flat_fee", "port_import_ad_valorem", "port_export_ad_valorem", "other_transport_fees", "infrastructure_maintenance", "infrastructure_labour", "factory_labour", "factory_maintenance", "factory_power"]:
		var total := 0.0
		for row: Dictionary in sample:
			total += float(row[key])
		result[key] = total / sample.size()
	result["sample_first_turn"] = sample[0].turn
	result["sample_last_turn"] = sample[-1].turn
	return result

func _startup_drawdown(first_regular: int) -> float:
	var cumulative := 0.0
	var lowest := 0.0
	for row: Dictionary in rows:
		if first_regular > 0 and int(row.turn) > first_regular:
			break
		cumulative += float(row.cash_change)
		lowest = minf(lowest, cumulative)
	return -lowest

func _base_freight_parts(gid: String, qty: int, route: Dictionary) -> Dictionary:
	var factor := 0.0
	for leg: Dictionary in route.get("legs", []):
		factor += float(EconomyConfig.TRANSPORT_MODE_COST_MULT.get(str(leg.mode), 1.0))
	var weight := qty * factor * EconomyConfig.transport_cost_per_unit_turn(Catalog.get_transport_class(gid))
	var total := EconomyConfig.transport_cost_for_route(gid, qty, route)
	var discount := Modifiers.apply("transport_cost", gid, 1.0, {"good_id": gid})
	# Every benchmark route is verified road-only or rail-only.
	discount *= 1.0 + float(Modifiers.resolve_pct("road_rail_transport_cost", "*", {}).get("net", 0.0)) / 100.0
	return {"weight": weight * discount, "value": (total - weight) * discount}

func _install_owned_rail(source: String, destination: String) -> void:
	# Seed a completed L1 corridor. Only player-owned tiles get building instances
	# and recurring maintenance; the remainder are public infrastructure. Government
	# build timing and construction/land capex are outside this steady-state trial.
	var queue: Array = [source]
	var previous := {source: ""}
	var index := 0
	while index < queue.size():
		var current := str(queue[index])
		index += 1
		if current == destination:
			break
		for neighbour in Catalog.tile_neighbours(current):
			var next := str(neighbour)
			if previous.has(next) or not bool(Catalog._tile_land.get(next, false)):
				continue
			previous[next] = current
			queue.append(next)
	check(previous.has(destination), "continuous land corridor to port")
	if not previous.has(destination):
		return
	var cursor := destination
	while cursor != "":
		rail_tiles.push_front(cursor)
		cursor = str(previous[cursor])
	var terrain = get_tree().get_first_node_in_group("hex_map")
	for tile in rail_tiles:
		Catalog.add_tile_infrastructure(str(tile), "rail")
		Catalog.set_tile_infra_level(str(tile), "rail", 1)
		var coord = terrain.id_to_coord(str(tile))
		var data: Dictionary = terrain.tiles[coord]
		var present: Array = data.get("infrastructure_present", [])
		if not present.has("rails"):
			present.append("rails")
		data["infrastructure_present"] = present
		var levels: Dictionary = data.get("infrastructure_levels", {})
		levels["rails"] = 1
		data["infrastructure_levels"] = levels
		if rail_owned_limit < 0 or rail_instances.size() < rail_owned_limit:
			owned_rail_tiles.append(tile)
			rail_instances.append(BuildingState.add_building("b_019", "", str(tile), MatchState.LOCAL_PLAYER))
	check(rail_instances.size() == (rail_tiles.size() if rail_owned_limit < 0 else rail_owned_limit), "rail ownership count")
	if rail_owned_limit == 3:
		var variant: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(rail_variant_path))
		check(owned_rail_tiles == variant.player_owned_tiles, "versioned player-owned rail tiles")
