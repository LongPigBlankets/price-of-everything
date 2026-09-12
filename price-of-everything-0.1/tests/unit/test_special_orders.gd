extends "res://tests/test_base.gd"
## Special orders lifecycle: offer, route, settle, resolve.

const FEATURE := "special_orders"
## Tests that also belong to other features (run under any of their tags).
const TAGS := {
	"_test_two_part_freight_tariff": ["market", "special_orders"],
	"_test_special_order_settlement": ["events", "market", "special_orders", "stockpile"],
	"_test_output_special_order_route": ["events", "production", "special_orders", "stockpile"],
	"_test_special_order_overflow_resolution": ["events", "market", "production", "special_orders", "stockpile"],
	"_test_pending_special_order_shipment_resolution": ["special_orders", "stockpile"],
	"_test_special_order_resolution_dialog": ["special_orders", "stockpile", "ui"],
}

func _fake_special_order_sale_shipment(order_id: String, qty: int, revenue: float) -> Dictionary:
	return {
		"id": 9001,
		"is_sale": true,
		"source_tile": "tile_3_8",
		"destination_tile": "tile_5_10",
		"special_order_id": order_id,
		"special_order_source_mode": "tile_view",
		"sale_record": {
			"tile_id": "tile_3_8",
			"items": [{"good_id": "g_001", "qty": qty, "revenue": revenue}],
			"total_qty": qty,
			"total_revenue": revenue,
		},
		"tile_distance": 4,
		"transport_turns": 3,
		"turns_remaining": 3,
		"path": [],
		"legs": [],
		"tiles": [],
	}

func _special_order_goods(orders: Array) -> Array:
	var out: Array = []
	for order in orders:
		out.append(str((order as Dictionary).get("good_internal", "")))
	return out

func _unique_strings(values: Array) -> Array:
	var seen: Dictionary = {}
	var out: Array = []
	for value in values:
		var key := str(value)
		if seen.has(key):
			continue
		seen[key] = true
		out.append(key)
	return out

func _test_two_part_freight_tariff() -> void:
	# Freight is flat weight-class rate + ad-valorem leg (owner ruling 2026-07-27), so the
	# burden stops collapsing to ~0.1% of value at the top of the chain. Valued on the
	# decayed base price: no buy markup, no glut/deficit impact.
	for gid in ["g_006", "g_038", "g_027"]:
		var cls := Catalog.get_transport_class(gid)
		var flat: float = EconomyConfig.transport_cost_per_unit_turn(cls)
		var av: float = float(EconomyConfig.TRANSPORT_ADVALOREM_BY_WEIGHT_CLASS[cls])
		var want: float = flat + av * MarketState.get_base_price_now(gid)
		_check(absf(EconomyConfig.transport_rate_for_good(gid) - want) < 0.0001,
			"%s freight = flat %.3f + %.4f x base price" % [Catalog.get_internal_name(gid), flat, av])
	_check(EconomyConfig.transport_rate_for_good("g_061")
			> EconomyConfig.transport_cost_per_unit_turn(Catalog.get_transport_class("g_061")),
		"a high-value good (iron_battery) is dearer to haul than its flat leg alone")
	_check(absf(EconomyConfig.transport_rate_for_good("g_041")
			- EconomyConfig.transport_cost_per_unit_turn(Catalog.get_transport_class("g_041"))) < 0.0001,
		"solid_light (cpu) has a ZERO ad-valorem leg — electronics stay near-free to ship")
	_check(absf(EconomyConfig.transport_rate_for_good("") - EconomyConfig.transport_cost_per_unit_turn("standard")) < 0.0001,
		"unknown good falls back to the flat leg only")
	_check(Catalog.get_transport_class("g_038") == "solid_heavy",
		"glass reclassified solid_light -> solid_heavy (~2500 kg/m3, the densest thing in the chain)")

func _test_special_order_state_model() -> void:
	var saved_turn: int = TurnManager.current_turn
	TurnManager.current_turn = 5
	SpecialOrderState.reset()

	var templates: Array = SpecialOrderState.all_order_templates()
	_check(templates.size() == SpecialOrderState.SPECIAL_ORDER_GOOD_INTERNALS.size(),
		"special orders: every cycle good resolves to a template")
	var coal_template: Dictionary = SpecialOrderState.template_for_good("coal")
	_check(str(coal_template.get("good_id", "")) == "g_001"
		and int(coal_template.get("baseline_output_qty", 0)) == 60,
		"special orders: coal template resolves catalog good + one-producer output")
	var glass_template: Dictionary = SpecialOrderState.template_for_good("glass")
	_check(str(glass_template.get("baseline_recipe_id", "")) != ""
		and int(glass_template.get("baseline_output_qty", 0)) > 0,
		"special orders: glass template finds a baseline producer")
	var car_template: Dictionary = SpecialOrderState.template_for_good("cars")
	_check(str(car_template.get("good_internal", "")) == "ice_car",
		"special orders: cars alias resolves to ICE car good")

	var coal: Dictionary = SpecialOrderState.create_order("coal", 5, 5)
	_check(not coal.is_empty() and int(coal.get("qty_required", 0)) == 300
		and int(coal.get("expires_turn", 0)) == 20,
		"special orders: created order uses output x target turns + buffer")
	_check(SpecialOrderState.create_order("g_001", 5, 5).is_empty(),
		"special orders: a good cannot have two active orders")
	_check(str(SpecialOrderState.get_active_order_for_good("coal").get("id", "")) == str(coal.get("id", "")),
		"special orders: active order can be queried by good")

	var committed: Dictionary = SpecialOrderState.commit_units(str(coal.get("id", "")), 12, "tile_view")
	var counts: Dictionary = committed.get("source_mode_counts", {})
	_check(int(committed.get("qty_committed", 0)) == 12 and int(counts.get("tile_view", 0)) == 12,
		"special orders: commitments track qty and source mode")
	var partial: Dictionary = SpecialOrderState.deliver_units(str(coal.get("id", "")), 20)
	_check(str(partial.get("status", "")) == SpecialOrderState.STATUS_AVAILABLE
		and int(partial.get("qty_delivered", 0)) == 20,
		"special orders: partial delivery updates without closing")
	var fulfilled: Dictionary = SpecialOrderState.deliver_units(str(coal.get("id", "")), 300)
	_check(str(fulfilled.get("status", "")) == SpecialOrderState.STATUS_FULFILLED
		and SpecialOrderState.fulfilled_count == 1,
		"special orders: full delivery closes as fulfilled")
	_check(not SpecialOrderState.can_good_enter_cycle("coal"),
		"special orders: fulfilled good waits for two other fulfilments before re-entry")

	var iron: Dictionary = SpecialOrderState.create_order("iron_ore", 6, 5, 1)
	var glass: Dictionary = SpecialOrderState.create_order("glass", 6, 5, 1)
	SpecialOrderState.deliver_units(str(iron.get("id", "")), 1)
	SpecialOrderState.deliver_units(str(glass.get("id", "")), 1)
	_check(SpecialOrderState.fulfilled_count == 3 and SpecialOrderState.can_good_enter_cycle("coal"),
		"special orders: good re-enters after two other fulfilled orders")
	var coal_again: Dictionary = SpecialOrderState.create_order("coal", 7, 5, 60)
	_check(not coal_again.is_empty(), "special orders: re-entered good can create a new order")

	var snap: Dictionary = SpecialOrderState.export_state()
	SpecialOrderState.reset()
	SpecialOrderState.import_state(snap)
	_check(SpecialOrderState.get_active_orders().size() == 1
		and SpecialOrderState.fulfilled_count == 3
		and str(SpecialOrderState.get_active_orders()[0].get("good_internal", "")) == "coal",
		"special orders: state round-trips active orders and fulfilment counters")

	SpecialOrderState.reset()
	TurnManager.current_turn = saved_turn

func _test_special_order_generation() -> void:
	var saved_turn: int = TurnManager.current_turn
	SpecialOrderState.reset()
	SpecialOrderState.set_rng_seed(12345)

	_check(SpecialOrderState.spawn_orders_for_turn(4).is_empty()
		and SpecialOrderState.get_active_orders().is_empty(),
		"special orders: generation waits until turn 5")

	var turn5: Array = SpecialOrderState.spawn_orders_for_turn(5)
	_check(turn5.size() == 4, "special orders: turn 5 creates four tutorial orders")
	_check(_special_order_goods(SpecialOrderState.get_active_orders()) == ["coal", "iron_ore", "glass", "ice_car"],
		"special orders: turn 5 goods are deterministic")
	_check(SpecialOrderState.spawn_orders_for_turn(5).is_empty()
		and SpecialOrderState.get_active_orders().size() == 4,
		"special orders: a spawn turn is idempotent")

	var turn10: Array = SpecialOrderState.spawn_orders_for_turn(10)
	var active_after_10 := SpecialOrderState.get_active_orders()
	_check(turn10.size() >= 2 and turn10.size() <= 3,
		"special orders: later spawn turns add 2-3 orders")
	_check(_special_order_goods(active_after_10).size() == _unique_strings(_special_order_goods(active_after_10)).size(),
		"special orders: active goods stay unique after random spawn")
	for order in turn10:
		var turns := int((order as Dictionary).get("target_production_turns", 0))
		_check(turns >= SpecialOrderState.MIN_TARGET_TURNS and turns <= SpecialOrderState.MAX_TARGET_TURNS,
			"special orders: random order duration uses 5-10 production turns")

	var turn21: Dictionary = SpecialOrderState.advance_turn(21)
	_check((turn21.get("closed", []) as Array).size() == 4,
		"special orders: expired turn-5 orders close after their expiry turn")
	_check(SpecialOrderState.get_active_order_for_good("coal").is_empty()
		and not SpecialOrderState.can_good_enter_cycle("coal"),
		"special orders: expired goods leave active list but stay re-entry gated")
	_check(SpecialOrderState.spawn_orders_for_turn(55).is_empty(),
		"special orders: generation stops after turn 50")

	var first_run: Array = _special_order_goods(active_after_10)
	SpecialOrderState.reset()
	SpecialOrderState.set_rng_seed(12345)
	SpecialOrderState.spawn_orders_for_turn(5)
	SpecialOrderState.spawn_orders_for_turn(10)
	_check(_special_order_goods(SpecialOrderState.get_active_orders()) == first_run,
		"special orders: saved RNG seed makes random generation repeatable")

	SpecialOrderState.reset()
	TurnManager.current_turn = saved_turn

func _test_special_order_settlement() -> void:
	var saved_turn: int = TurnManager.current_turn
	var saved_money: float = MatchState.money
	EventScheduler.reset()
	SpecialOrderState.reset()
	TurnManager.current_turn = 8
	MatchState.money = 1000.0

	var coal: Dictionary = SpecialOrderState.create_order("coal", 5, 5, 10, 0.5)
	var coal_id := str(coal.get("id", ""))
	var committed: Dictionary = SpecialOrderState.commit_units(coal_id, 5, "tile_view", "g_001")
	_check(int(committed.get("qty_committed", 0)) == 5,
		"special orders: commitments can be tied to a matching good id")
	TurnManager.current_turn = 18
	var warned: Array = SpecialOrderState.warn_orders_for_turn(18)
	_check(warned.size() == 1
		and EventScheduler._active.has("special_order_warning:%s" % coal_id),
		"special orders: committed orders warn with two turns left")

	var partial: Dictionary = SpecialOrderState.settle_delivery(coal_id, "g_001", 5, 10.0)
	_check(not bool(partial.get("fulfilled", false))
		and absf(float(partial.get("premium_bonus", 0.0))) < 0.001,
		"special orders: partial settlement pays no premium")
	var money_before_bonus: float = MatchState.money
	var finished: Dictionary = SpecialOrderState.settle_delivery(coal_id, "g_001", 6, 12.0)
	_check(bool(finished.get("fulfilled", false))
		and absf(float(finished.get("premium_bonus", 0.0)) - 10.0) < 0.001,
		"special orders: fulfilment premium is based only on required units")
	_check(absf(MatchState.money - (money_before_bonus + 10.0)) < 0.001,
		"special orders: fulfilment premium is paid to cash")
	_check(SpecialOrderState.get_order(coal_id).is_empty()
		and EventScheduler._active.has("special_order_fulfilled:%s" % coal_id),
		"special orders: fulfilled order closes and raises a notification")

	EventScheduler.reset()
	SpecialOrderState.reset()
	TurnManager.current_turn = 5
	var expiring: Dictionary = SpecialOrderState.create_order("coal", 5, 5, 10, 0.5)
	var expiring_id := str(expiring.get("id", ""))
	SpecialOrderState.commit_units(expiring_id, 1, "building_detail", "g_001")
	var turn21: Dictionary = SpecialOrderState.advance_turn(21)
	_check((turn21.get("closed", []) as Array).size() == 1
		and EventScheduler._active.has("special_order_expired:%s" % expiring_id),
		"special orders: committed expired orders raise a notification")

	EventScheduler.reset()
	SpecialOrderState.reset()
	TurnManager.current_turn = 10
	MatchState.money = 500.0
	var market_order: Dictionary = SpecialOrderState.create_order("coal", 10, 5, 4, 0.25)
	var market_order_id := str(market_order.get("id", ""))
	Stockpile.consume("tile_5_10", "g_001", 1 << 30)
	Stockpile.add("tile_5_10", "g_001", 4)
	var market_money_before: float = MatchState.money
	var sale: Dictionary = MarketState.execute_sale("tile_5_10", {"g_001": 4}, {
		"special_order_id": market_order_id,
		"special_order_source_mode": "tile_view",
		"log_oneoff": false,
	})
	var expected_bonus := float(sale.get("total_revenue", 0.0)) * 0.25
	_check(not sale.is_empty()
		and not bool(sale.get("deferred", false))
		and bool(sale.get("special_order_committed", false)),
		"special orders: market sales can commit to an active order")
	_check(SpecialOrderState.get_order(market_order_id).is_empty()
		and EventScheduler._active.has("special_order_fulfilled:%s" % market_order_id),
		"special orders: immediate market sales settle and close orders")
	_check(absf(MatchState.money - (market_money_before + float(sale.get("total_revenue", 0.0)) + expected_bonus - float(sale.get("transport_cost", 0.0)))) < 0.01,
		"special orders: immediate market sale pays revenue and premium after its port charge")

	EventScheduler.reset()
	SpecialOrderState.reset()
	TurnManager.current_turn = saved_turn
	MatchState.money = saved_money

func _test_output_special_order_route() -> void:
	var saved_turn: int = TurnManager.current_turn
	var saved_money: float = MatchState.money
	MatchState.reset()
	Stockpile.clear_all()
	EventScheduler.reset()
	SpecialOrderState.reset()
	TurnManager.current_turn = 10
	MatchState.money = 500.0

	var order: Dictionary = SpecialOrderState.create_order("coal", 10, 5, 4, 0.25)
	var order_id := str(order.get("id", ""))
	MatchState.route_output_to_special_order("inst_so_prod", "g_001", order_id)
	_check(MatchState.is_output_market("inst_so_prod", "g_001")
		and MatchState.get_output_special_order_id("inst_so_prod", "g_001") == order_id,
		"special orders: output routes can target an active matching order")

	var summary := _fresh_production_summary()
	Production._dispatch_output_to_stockpile({
		"instance_id": "inst_so_prod",
		"tile_id": "tile_5_10",
	}, Catalog.get_good("g_001"), 4, summary)
	_check(SpecialOrderState.get_order(order_id).is_empty()
		and EventScheduler._active.has("special_order_fulfilled:%s" % order_id),
		"special orders: market-routed production output fulfils the order")
	var revenue: float = float(summary.get("goods_sales_revenue", 0.0))
	var transport_paid: float = float(summary.get("transport_paid", 0.0))
	var premium: float = revenue * 0.25
	_check(revenue > 0.0 and transport_paid > 0.0
		and absf(MatchState.money - (500.0 + revenue + premium - transport_paid)) < 0.01,
		"special orders: market-routed production accounts for revenue, premium, and delivery cost")

	EventScheduler.reset()
	SpecialOrderState.reset()
	TurnManager.current_turn = saved_turn
	MatchState.reset()
	Stockpile.clear_all()
	MatchState.money = saved_money

func _test_special_order_overflow_resolution() -> void:
	var saved_turn: int = TurnManager.current_turn
	var saved_money: float = MatchState.money
	MatchState.reset()
	Stockpile.clear_all()
	EventScheduler.reset()
	SpecialOrderState.reset()
	TurnManager.current_turn = 10
	MatchState.money = 500.0

	var overflow_records: Array = []
	var capture := func(record: Dictionary) -> void:
		overflow_records.append(record.duplicate(true))
	TransportState.special_order_overflow_ready.connect(capture)

	var order: Dictionary = SpecialOrderState.create_order("coal", 10, 5, 4, 0.25)
	var order_id := str(order.get("id", ""))
	var summary := _fresh_production_summary()
	Production._credit_arrived_sale({
		"id": 77,
		"is_sale": true,
		"source_tile": "tile_3_8",
		"destination_tile": "tile_5_10",
		"special_order_id": order_id,
		"special_order_source_mode": "building_detail",
		"sale_record": {
			"tile_id": "tile_3_8",
			"items": [{"good_id": "g_001", "qty": 6, "revenue": 60.0}],
			"total_qty": 6,
			"total_revenue": 60.0,
		},
	}, summary)

	_check(SpecialOrderState.get_order(order_id).is_empty()
		and overflow_records.size() == 1
		and int((overflow_records[0] as Dictionary).get("qty", 0)) == 2,
		"special orders: over-delivery fulfils order and raises overflow decision")
	_check(absf(MatchState.money - 550.0) < 0.001
		and absf(float(summary.get("goods_sales_revenue", 0.0)) - 50.0) < 0.001,
		"special orders: over-delivery pays counted units plus premium, not overflow")

	var record: Dictionary = overflow_records[0]
	var before_sell := MatchState.money
	var sold := TransportState.sell_special_order_overflow(record)
	_check(not sold.is_empty()
		and absf(MatchState.money - (before_sell + 20.0)) < 0.001,
		"special orders: overflow can be sold at normal market value")

	var stock_record := record.duplicate(true)
	stock_record["qty"] = 2
	stock_record["total_revenue"] = 20.0
	_check(TransportState.special_order_overflow_can_stockpile(stock_record)
		and TransportState.stockpile_special_order_overflow(stock_record)
		and Stockpile.get_at_tile("tile_5_10", "g_001") == 2,
		"special orders: overflow can be stockpiled at port when the whole shipment fits")

	MatchState.reset()
	Stockpile.clear_all()
	EventScheduler.reset()
	SpecialOrderState.reset()
	TurnManager.current_turn = 10
	MatchState.money = 500.0
	overflow_records.clear()
	var instant_order: Dictionary = SpecialOrderState.create_order("coal", 10, 5, 4, 0.25)
	Stockpile.add("tile_5_10", "g_001", 6)
	var instant_result := MarketState.execute_sale("tile_5_10", {"g_001": 6}, {
		"special_order_id": str(instant_order.get("id", "")),
		"special_order_source_mode": "tile_view",
		"log_oneoff": false,
	})
	_check(not bool(instant_result.get("deferred", true))
		and int(instant_result.get("total_qty", 0)) == 4
		and float(instant_result.get("total_revenue", 0.0)) > 0.0
		and overflow_records.size() == 1,
		"special orders: immediate over-delivery reports only credited sale units")

	if TransportState.special_order_overflow_ready.is_connected(capture):
		TransportState.special_order_overflow_ready.disconnect(capture)
	EventScheduler.reset()
	SpecialOrderState.reset()
	TurnManager.current_turn = saved_turn
	MatchState.reset()
	Stockpile.clear_all()
	MatchState.money = saved_money

func _test_pending_special_order_shipment_resolution() -> void:
	var saved_money: float = MatchState.money
	MatchState.reset()
	Stockpile.clear_all()

	var order_id := "so_test_pending"
	TransportState.queue_transport_shipment(_fake_special_order_sale_shipment(order_id, 4, 40.0))
	var taken := TransportState.take_pending_special_order_shipments(order_id)
	var sell_result := TransportState.resolve_special_order_shipments(taken, "sell")
	var pending := TransportState.get_pending_transport_shipments()
	_check(taken.size() == 1
		and bool(sell_result.get("ok", false))
		and pending.size() == 1
		and bool((pending[0] as Dictionary).get("is_sale", false))
		and str((pending[0] as Dictionary).get("special_order_id", "")) == "",
		"special orders: pending tagged shipments can be converted to normal market sales")

	MatchState.reset()
	Stockpile.clear_all()
	TransportState.queue_transport_shipment(_fake_special_order_sale_shipment(order_id, 4, 40.0))
	taken = TransportState.take_pending_special_order_shipments(order_id)
	var stockpile_result := TransportState.resolve_special_order_shipments(taken, "stockpile_port")
	pending = TransportState.get_pending_transport_shipments()
	_check(bool(stockpile_result.get("ok", false))
		and pending.size() == 1
		and not bool((pending[0] as Dictionary).get("is_sale", false))
		and str((pending[0] as Dictionary).get("destination_tile", "")) == "tile_5_10"
		and str((pending[0] as Dictionary).get("good_id", "")) == "g_001",
		"special orders: pending tagged shipments can be converted to port stockpile deliveries")

	MatchState.reset()
	Stockpile.clear_all()
	TransportState.queue_transport_shipment(_fake_special_order_sale_shipment(order_id, 4, 40.0))
	taken = TransportState.take_pending_special_order_shipments(order_id)
	var reroute_result := TransportState.resolve_special_order_shipments(taken, "reroute", "tile_12_4")
	pending = TransportState.get_pending_transport_shipments()
	_check(bool(reroute_result.get("ok", false))
		and pending.size() == 1
		and not bool((pending[0] as Dictionary).get("is_sale", false))
		and str((pending[0] as Dictionary).get("destination_tile", "")) == "tile_12_4",
		"special orders: pending tagged shipments can be rerouted to another tile stockpile")

	MatchState.reset()
	Stockpile.clear_all()
	MatchState.money = saved_money

func _test_special_order_resolution_dialog() -> void:
	var saved_money: float = MatchState.money
	MatchState.reset()
	Stockpile.clear_all()
	MatchState.money = 100.0

	var dialog: Control = load("res://scripts/special_order_resolution_dialog.gd").new()
	add_child(dialog)
	await get_tree().process_frame
	dialog.call("_on_overflow_ready", {
		"order_id": "so_dialog",
		"source_tile": "tile_3_8",
		"port_tile": "tile_5_10",
		"good_id": "g_001",
		"good_display": "Coal",
		"qty": 2,
		"unit_revenue": 10.0,
		"total_revenue": 20.0,
	})
	_check(dialog.visible
		and _node_tree_contains_text(dialog, "Special order overflow")
		and _node_tree_contains_text(dialog, "Stockpile at port"),
		"special orders: resolution dialog opens for overflow decisions")
	dialog.call("_on_sell_pressed")
	await get_tree().process_frame
	_check(not dialog.visible
		and absf(MatchState.money - 120.0) < 0.001,
		"special orders: resolution dialog sell action resolves and closes")
	PanelStack.remove(dialog)
	dialog.queue_free()
	MatchState.reset()
	Stockpile.clear_all()
	MatchState.money = saved_money

func _test_market_special_orders_tab() -> void:
	var saved_turn: int = TurnManager.current_turn
	SpecialOrderState.reset()
	TurnManager.current_turn = 5
	var order: Dictionary = SpecialOrderState.create_order("coal", 5, 5, 10, 0.4)
	SpecialOrderState.commit_units(str(order.get("id", "")), 3, "tile_view", "g_001")

	var panel: Control = load("res://scenes/market_panel.tscn").instantiate()
	add_child(panel)
	panel.call("_ensure_built")
	var tabs: TabContainer = panel.get("_tabs")
	_check(tabs != null
		and tabs.get_child_count() >= 3
		and tabs.get_tab_title(2) == "Special Orders",
		"market panel: Special Orders is the third tab")
	tabs.current_tab = 2
	panel.call("_ensure_current_tab_built")
	var count_label: Label = panel.get("_special_orders_count_label")
	var body: VBoxContainer = panel.get("_special_orders_body")
	_check(count_label != null
		and count_label.text == "Active special orders: 1"
		and body != null
		and body.get_child_count() == 1,
		"market panel: Special Orders tab renders active order rows")
	_check(_node_tree_contains_text(body, "Coal")
		and _node_tree_contains_text(body, "3")
		and _node_tree_contains_text(body, "+40%"),
		"market panel: active special order row exposes good, committed qty and premium")
	var row := body.get_child(0)
	var row_main := row.get_child(0) as HBoxContainer
	var product_button: Button = null
	var target_cell: Label = null
	if row_main != null and row_main.get_child_count() > 2:
		product_button = row_main.get_child(1) as Button
		target_cell = row_main.get_child(2) as Label
	_check(row_main != null
		and int(row_main.custom_minimum_size.y) == 98
		and product_button != null
		and int(product_button.custom_minimum_size.x) == 240
		and int(product_button.custom_minimum_size.y) == 98
		and target_cell != null
		and int(target_cell.custom_minimum_size.y) == 98
		and target_cell.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER,
		"market panel: Special Orders rows match goods row height and centered column cells")

	SpecialOrderState.reset()
	panel.call("_refresh_special_orders")
	_check(count_label.text == "Active special orders: 0"
		and _node_tree_contains_text(body, "No active special orders"),
		"market panel: Special Orders tab renders the empty state")

	panel.queue_free()
	SpecialOrderState.reset()
	TurnManager.current_turn = saved_turn
