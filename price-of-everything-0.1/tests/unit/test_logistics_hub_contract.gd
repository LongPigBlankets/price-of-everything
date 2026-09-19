extends "res://tests/test_base.gd"
const FEATURE := "logistics_hub"
const Hub := preload("res://scripts/logistics_hub_contract.gd")

func row(qty: int = 25, cargo: String = "solid_heavy", good: String = "steel") -> Dictionary:
	return {"hub": "hub_a", "tile": "a", "next_tile": "b", "available_turn": 7,
		"good_id": good, "internal_name": good, "transport_class": cargo, "qty": qty, "connected": true}

func _test_meeting_cargo_consolidates_independent_of_original_dispatch() -> void:
	var first := row()
	first["original_departure_turn"] = 2
	first["original_source"] = "west"
	var second := row()
	second["original_departure_turn"] = 6
	second["original_source"] = "east"
	var before := JSON.stringify([first, second])
	var result := Hub.consolidate([first, second])
	_check(result.groups.size() == 1 and result.lc == 1, "meeting compatible cargo fills one load regardless of origin and departure")
	_check(result.groups[0].goods.steel == 50, "consolidation preserves all units")
	_check(JSON.stringify([first, second]) == before, "planning does not mutate shipment records")
	var split := Hub.consolidate([row(10), row(10), row(10), row(10), row(10)])
	_check(split.lc == result.lc, "splitting API orders cannot increase LC")
	var other_good := row(25, "solid_heavy", "copper_wiring")
	result = Hub.consolidate([first, other_good])
	_check(result.lc == 1 and result.groups[0].goods.size() == 2, "compatible different goods share a load without losing their identities")

func _test_direction_time_equipment_and_access_boundaries() -> void:
	var reversed := row()
	reversed.tile = "b"
	reversed.next_tile = "a"
	var later := row()
	later.available_turn = 8
	var divergent := row()
	divergent.next_tile = "c"
	var disconnected := row()
	disconnected.connected = false
	var result := Hub.consolidate([row(), reversed, later, divergent, row(25, "solid_heavy", "coal"), disconnected, row(25, "safe_liquid", "fuels")])
	_check(result.groups.size() == 5 and result.lc == 5, "opposite directions, different time/edge and bulk equipment do not share loads")
	_check(result.rejected == [5, 6], "generic fallback and fluid weights never imply owned truck eligibility")
	_check(Hub.WEIGHTS.hazard_liquid == 4 and Hub.WEIGHTS.gas == 3, "future equipment retains selected fluid weights")

func _test_weight_applied_once_and_capacity_is_installed() -> void:
	_check(Hub.consolidate([row(100, "solid_light")]).lc == 1, "100 light units use one LC")
	_check(Hub.consolidate([row(100, "solid_heavy")]).lc == 2, "100 heavy units use two LC")
	_check(Hub.consolidate([row(100, "ultra_heavy")]).lc == 5, "100 ultra-heavy units use five LC")
	_check(Hub.consolidate([row(101, "solid_light")]).lc == 2, "partial extra load rounds up only after pooling")
	_check(Hub.installed_loaded_capacity(3) == 30, "three installed vehicles provide thirty loaded LC before occupancy policy")
	_check(Hub.installed_loaded_capacity(-1) == 0, "invalid negative fleet cannot create capacity")

func _test_original_recipe_credit_carries_and_idle_consumes_nothing() -> void:
	var quote := Hub.supplies_for_work(1, 0)
	_check(quote.ok and quote.goods == {"hydraulic_components": 2, "tyres": 4, "fuels": 6}, "first dispatch secures a whole original recipe")
	_check(quote.credit_after == 124, "unused operating service credit persists")
	var idle := Hub.supplies_for_work(0, quote.credit_after)
	_check(idle.goods.is_empty() and idle.credit_after == 124, "idle turn consumes nothing and retains credit")
	var remainder := Hub.supplies_for_work(124, idle.credit_after)
	_check(remainder.goods.is_empty() and remainder.credit_after == 0, "paid credit services subsequent turns without duplicate draw")
	var large := Hub.supplies_for_work(251, 0)
	_check(large.recipes == 3 and large.credit_after == 124, "large workloads reserve enough complete recipes")
	var lithium := Hub.supplies_for_work(1, 0, "lithium_electric")
	var sodium := Hub.supplies_for_work(1, 0, "sodium_electric")
	_check(lithium.goods.get("lithium_battery") == 1 and not lithium.goods.has("fuels"), "lithium battery replaces fuel")
	_check(sodium.goods.get("sodium_battery") == 1 and not sodium.goods.has("fuels"), "sodium battery replaces fuel")
	_check(not Hub.supplies_for_work(-1, 0).ok and not Hub.supplies_for_work(1, -1).ok, "invalid usage cannot manufacture service credit")

func _test_missing_supply_rejects_complete_batch_without_mutation() -> void:
	var stock := {"hydraulic_components": 2, "tyres": 3, "fuels": 6}
	var before := stock.duplicate()
	var result := Hub.admit_stock_work(2, 1, stock)
	_check(not result.ok and result.missing == {"tyres": 1}, "missing tyre rejects unfunded work")
	_check(result.credit_after == 1 and result.goods.is_empty() and stock == before, "failed admission preserves credit and every supplied ingredient")
	stock.tyres = 4
	result = Hub.admit_stock_work(2, 1, stock)
	_check(result.ok and result.credit_after == 124 and stock.tyres == 4, "successful pure admission quotes a complete basket without consuming stock")

func _test_fleet_limit_splits_oversized_cargo_and_preserves_waiting() -> void:
	var rows := [row(800)]
	var fleets := {"hub_a": {"vehicles": 1, "credit": 125, "stock": {}}}
	var before := JSON.stringify([rows, fleets])
	var plan := Hub.schedule_stock_work(rows, fleets)
	_check(plan.allocations.size() == 1 and plan.allocations[0].qty == 500, "one truck dispatches 1000 weighted units of oversized heavy cargo")
	_check(plan.waiting == [300] and plan.hubs.hub_a.used_lc == 10, "remainder queues without exceeding installed capacity")
	_check(plan.hubs.hub_a.credit_after == 115 and plan.hubs.hub_a.goods.is_empty(), "only admitted loaded work uses prepaid service")
	_check(JSON.stringify([rows, fleets]) == before, "fleet scheduling is pure and cannot duplicate a reservation")

func _test_groups_cannot_double_reserve_supplies_or_capacity() -> void:
	var second := row(500)
	second.next_tile = "c"
	var fleets := {"hub_a": {"vehicles": 2, "credit": 1, "stock": {}}}
	var plan := Hub.schedule_stock_work([row(500), second], fleets)
	_check(plan.hubs.hub_a.used_lc == 1 and plan.hubs.hub_a.credit_after == 0, "missing recipe permits existing credit only once across groups")
	_check(plan.waiting[0] + plan.waiting[1] == 950, "queued cargo is conserved when operating supplies run out")
	fleets.hub_a.stock = {"hydraulic_components": 2, "tyres": 4, "fuels": 6}
	plan = Hub.schedule_stock_work([row(500), second], fleets)
	_check(plan.hubs.hub_a.used_lc == 20 and plan.waiting == [0, 0], "complete supplied fleet serves both directions within capacity")
	_check(plan.hubs.hub_a.goods.tyres == 4 and plan.hubs.hub_a.credit_after == 106, "two groups reserve one complete recipe together, not one each")
	var split := Hub.schedule_stock_work([row(250), row(250), second], fleets)
	_check(split.hubs == plan.hubs, "API splitting does not change admitted work or operating supply bill")
