extends RefCounted
## Read-only, one-turn planning from visible state. Never advances the sim or reads event queues.
const Allocator := preload("res://scripts/input_order_planner.gd")
const Status := preload("res://scripts/building_status.gd")
const Routes := preload("res://scripts/stockpile_guidance.gd")
static var last_comparison: Dictionary = {}
static var _before: Dictionary = {}
static var _orders: Array = []
static var _arrivals_paid := 0.0
static var _recording := false

static func reset() -> void:
	last_comparison.clear()
	_before.clear()
	_orders.clear()
	_arrivals_paid = 0.0
	_recording = false

static func payments() -> Array:
	var rows: Array = []
	for shipment: Dictionary in TransportState.pending_transport_shipments:
		var amount := float(shipment.get("purchase_cost", 0.0))
		if amount <= 0.0:
			continue # Old saves and overflow-held freight were already paid.
		var tile := str(shipment.get("destination_tile", ""))
		var good := str(shipment.get("good_id", ""))
		var kind := "Construction" if str(shipment.get("construction_instance_id", "")) != "" else "Shipment"
		if str(shipment.get("upgrade_instance_id", "")) != "":
			kind = "Upgrade"
		rows.append({"label": "%s: %d %s → %s" % [kind, int(shipment.get("qty", 0)), Catalog.get_display_name(good), Catalog.tile_label(tile)],
			"amount": amount, "due_in": maxi(1, int(shipment.get("turns_remaining", 1))), "kind": "shipment", "source_kind": kind.to_lower(),
			"extra_amount": amount * clampf(float(shipment.get("startup_input_share", 0.0)), 0.0, 1.0)})
	for loan: Dictionary in LoanState.loans:
		var grace := int(loan.get("grace_remaining", 0))
		var amount := minf(float(loan.get("payment_per_turn", 0.0)), float(loan.get("principal_remaining", 0.0)))
		if grace > 0:
			var total := float(loan.get("total_repayment", float(loan.get("principal_initial", 0.0)) * (1.0 + float(loan.get("interest_rate", EconomyConfig.LOAN_INTEREST_RATE)))))
			amount = total / float(EconomyConfig.LOAN_TERM_TURNS)
		if amount > 0.0:
			rows.append({"label": LoanState.loan_label(loan) + " instalment", "schedule": LoanState.repayment_label(loan), "amount": amount, "due_in": grace + 1, "kind": "loan"})
	for iid: String in MatchState.building_tabs:
		var tab: Dictionary = MatchState.building_tabs[iid]
		# Unfinished credit windows still accrue; show them separately as an estimate.
		if int(tab.get("turns_left", 0)) > 0:
			continue
		var slices := int(tab.get("slices_left", 0))
		if str(tab.get("mode", "slices")) == "slices" and slices > 0:
			rows.append({"label": "Building credit: " + _building_name(iid), "amount": float(tab.get("accrued", 0.0)) / float(slices), "due_in": 1, "kind": "credit"})
	return rows

static func due_total(rows: Array, horizon: int = 1) -> float:
	var total := 0.0
	for row: Dictionary in rows:
		if int(row.due_in) <= horizon:
			total += float(row.amount)
	return total

static func _building_name(iid: String) -> String:
	var b := BuildingState.get_building(iid)
	return str(b.get("name", Catalog.get_building_display_name(str(b.get("building_id", ""))))) if not b.is_empty() else iid

static func snapshot() -> Dictionary:
	var started := Time.get_ticks_usec()
	var committed := payments()
	var stock: Dictionary = {}
	var transit: Array = []
	var buildings: Array = []
	for tile: Variant in Stockpile.tiles_with_stock():
		stock[str(tile)] = Stockpile.get_tile_totals(tile).duplicate()
	for b: Dictionary in BuildingState.buildings.values():
		if BuildingState.is_player_owned(b):
			var iid := str(b.get("instance_id", ""))
			if BuildingWorks.demolish_queue.has(iid) and int(BuildingWorks.demolish_queue[iid].get("turns_left", 0)) <= 1:
				continue
			var projected := b.duplicate(true)
			for upgrade: Dictionary in BuildingWorks.pending_upgrades:
				if str(upgrade.get("instance_id", "")) == iid and str(upgrade.get("status", "")) == BuildingWorks.UPGRADE_STATUS_UPGRADING and int(upgrade.get("turns_remaining", 0)) <= 1:
					projected["level"] = int(upgrade.get("target_level", b.get("level", 1)))
			for retrofit: Dictionary in BuildingWorks.pending_retrofits:
				if str(retrofit.get("instance_id", "")) == iid and int(retrofit.get("turns_remaining", 0)) <= 1:
					projected["recipe_id"] = str(retrofit.get("to_recipe", b.get("recipe_id", "")))
					projected["forecast_retooled"] = true
			buildings.append(projected)
	# Arrival/overflow quantities can be used next turn, but cannot overfill a warehouse.
	for held: Dictionary in TransportState.overflow_shipments:
		_land(stock, transit, held, str(held.get("destination_tile", "")))
	for s: Dictionary in TransportState.pending_transport_shipments:
		if bool(s.get("is_sale", false)):
			continue
		if int(s.get("turns_remaining", 1)) <= 1:
			_land(stock, transit, s, str(s.get("destination_tile", "")))
		else:
			transit.append(s.duplicate())
	var requests: Array = []
	# Material claims precede ordinary production and buying.
	for iid: String in Construction.construction_projects:
		var project: Dictionary = Construction.construction_projects[iid]
		var tile := str(project.get("tile_id", ""))
		if str(project.get("status", "")) == Construction.STATUS_UNDER_CONSTRUCTION:
			if int(project.get("turns_remaining", 0)) <= 1:
				buildings.append({"instance_id": iid, "building_id": project.building_id, "recipe_id": project.recipe_id,
					"tile_id": tile, "level": 1, "forecast_new": true,
					"forecast_route": str(project.get("output_destination", MatchState.construct_output_destination))})
			continue
		if str(project.get("status", "")) != Construction.STATUS_AWAITING_MATERIALS:
			continue
		for gid: String in project.get("missing_materials", {}):
			var need := int(project.missing_materials[gid])
			var take := mini(need, _quantity(stock, tile, gid))
			_add(stock, tile, gid, -take)
			var incoming := 0
			for s: Dictionary in transit:
				if str(s.get("construction_instance_id", "")) == iid and str(s.get("good_id", "")) == gid:
					incoming += int(s.get("qty", 0))
			var shortfall := maxi(0, need - take - incoming)
			if shortfall > 0 and str(project.get("source", {}).get("kind", "")) == "market":
				requests.append(_request(tile, gid, shortfall, shortfall, "construction", iid))
	for upgrade: Dictionary in BuildingWorks.pending_upgrades:
		if str(upgrade.get("status", "")) == BuildingWorks.UPGRADE_STATUS_AWAITING:
			var tile := str(upgrade.get("tile_id", ""))
			for gid: String in upgrade.get("missing", {}):
				_add(stock, tile, gid, -mini(_quantity(stock, tile, gid), int(upgrade.missing[gid])))
	var completing_service: Array = buildings.filter(func(b: Dictionary) -> bool: return bool(b.get("forecast_new",false)) and preload("res://scripts/middleman_service.gd").default_for(str(b.get("recipe_id","")),str(b.get("tile_id",""))))
	var service_previews := preload("res://scripts/middleman_service.gd").company_previews(completing_service)
	var local_supply: Dictionary = {}
	var outputs: Array = []
	var ran: Dictionary = {}
	var labour := 0.0
	var maintenance := 0.0
	for b: Dictionary in buildings:
		var tile := str(b.get("tile_id", ""))
		var iid := str(b.get("instance_id", ""))
		var recipe := Catalog.get_recipe(str(b.get("recipe_id", "")))
		var private_inputs := service_previews.has(iid) and (preload("res://scripts/middleman_service.gd").uses_inputs(iid) or bool(b.get("forecast_new",false)))
		var run := not BuildingWorks.is_building_paused(iid) and (not BuildingWorks.is_retooling(iid) or bool(b.get("forecast_retooled",false)))
		run = run and _power_available(tile,recipe) and not Status.recipe_deposit_exhausted(b,recipe)
		if private_inputs:
			run = bool(service_previews[iid].get("can_run",false))
		else:
			for input: Dictionary in recipe.get("inputs",[]):
				if _quantity(stock,tile,str(input.get("good_id",""))) < Production._scaled_input_qty(input,b): run=false
		if run:
			ran[iid]=true
			if not private_inputs:
				for input: Dictionary in recipe.get("inputs",[]):
					_add(stock,tile,str(input.get("good_id","")),-Production._scaled_input_qty(input,b))
			for item: Dictionary in Status.flow_output_items(recipe):
				if preload("res://scripts/middleman_service.gd").uses_outputs(iid) or (bool(b.get("forecast_new",false)) and service_previews.has(iid)): continue
				var gid := str(item.get("good_id", ""))
				if gid == "":
					gid = str(Catalog.get_good_by_internal_name(str(item.get("internal_name", ""))).get("id", ""))
				if gid == "" or str(Catalog.get_good(gid).get("internal_name", "")) == "power":
					continue
				var single := recipe.duplicate()
				single["outputs"] = [item]
				var quantity := roundi(float(Status.effective_output_qty(b, single)) * MatchState.startup_capacity_multiplier(b))
				var allocations := Routes.output_allocations(b, gid, quantity)
				if bool(b.get("forecast_new", false)) and not MatchState.has_output_destination(iid, gid) and str(b.get("forecast_route", "")) == "same_tile":
					allocations = {tile: quantity}
				for dest: String in allocations:
					var qty := int(allocations[dest])
					if dest == tile:
						_add(local_supply, tile, gid, qty)
						outputs.append({"tile": tile, "good": gid, "qty": qty})
					elif qty > 0:
						transit.append({"destination_tile": dest, "good_id": gid, "qty": qty})
		maintenance += Production._calculate_maintenance_cost(b)
		if not BuildingWorks.is_building_paused(iid):
			labour += Production._calculate_labour_cost(b, recipe) * (1.0 if run else LabourState.idle_labour_pay_share)
	for item: Dictionary in outputs:
		_land(stock, transit, {"good_id": item.good, "qty": item.qty}, str(item.tile))
	for move: Dictionary in TransportState.recurring_moves:
		var source := str(move.get("source", ""))
		var move_goods := preload("res://scripts/middleman_service.gd").managed_move_goods(move)
		for gid: String in move_goods:
			var qty := mini(_quantity(stock, source, gid), int(move_goods[gid]))
			_add(stock, source, gid, -qty)
			transit.append({"destination_tile": str(move.get("dest", "")), "good_id": gid, "qty": qty})
	var demand: Dictionary = {}
	var names: Dictionary = {}
	var new_inputs: Dictionary = {}
	for b: Dictionary in buildings:
		var iid := str(b.get("instance_id", ""))
		if service_previews.has(iid) and (preload("res://scripts/middleman_service.gd").uses_inputs(iid) or bool(b.get("forecast_new",false))): continue
		var tile := str(b.get("tile_id", ""))
		var recipe := Catalog.get_recipe(str(b.get("recipe_id", "")))
		if not _power_available(tile, recipe):
			continue
		var entry := {"instance_id": iid, "inputs": {}}
		for item: Dictionary in recipe.get("inputs", []):
			var gid := str(item.get("good_id", ""))
			if MatchState.is_input_tile_only(iid, gid) and not Production._input_source_exhausted_for(b, item):
				continue
			entry.inputs[gid] = int(entry.inputs.get(gid, 0)) + Production._scaled_input_qty(item, b)
			if (bool(b.get("forecast_new", false)) or bool(b.get("startup_inputs_pending", false)) or bool(b.get("forecast_retooled", false))) and not ran.has(iid) and not BuildingWorks.is_building_paused(iid):
				new_inputs[iid] = true
		if not demand.has(tile):
			demand[tile] = []
		demand[tile].append(entry)
		names[iid] = _building_name(iid) if not bool(b.get("forecast_new", false)) else Catalog.get_building_display_name(str(b.building_id)) + " (completing)"
	for tile: String in demand:
		var leads: Dictionary = {}
		var pool: Dictionary = {}
		var needs: Dictionary = {}
		var first: Dictionary = {}
		for entry: Dictionary in demand[tile]:
			for gid: String in entry.inputs:
				needs[gid] = int(needs.get(gid, 0)) + int(entry.inputs[gid])
				if not first.has(gid):
					first[gid] = str(entry.instance_id)
		var inbound_all := 0
		for s: Dictionary in transit:
			if str(s.get("destination_tile", "")) != tile or Production._shipment_reserved_outside_input_pipeline(s):
				continue
			var gid := str(s.get("good_id", ""))
			pool[gid] = int(pool.get(gid, 0)) + int(s.get("qty", 0))
			inbound_all += int(s.get("qty", 0))
		var under: Dictionary = {}
		for gid: String in needs:
			var quote := TransportService.quote_market_buy(tile, gid, 1, TransportState.seaport_would_cover(gid))
			leads[gid] = {"port": str(quote.get("port", "")), "lead": maxi(1, int(quote.get("turns", 1)))}
			pool[gid] = int(pool.get(gid, 0)) + _quantity(stock, tile, gid)
			var local := _quantity(local_supply, tile, gid)
			under[gid] = local > 0 and local < int(needs[gid]) and str(leads[gid].port) != ""
		var budget := maxi(0, Stockpile.get_capacity(tile) - _used(stock, tile) - inbound_all)
		var plan := Allocator.allocate(demand[tile], leads, local_supply.get(tile, {}), pool, under, budget, Production._input_safety_margin_turns(), true)
		for gid: String in needs:
			var wanted := int(plan.wanted.get(gid, 0))
			if wanted > 0:
				var row := _request(tile, gid, int(plan.orders.get(gid, 0)), wanted, "input", str(first[gid]))
				row["building"] = str(names.get(str(first[gid]), ""))
				row["new_building_qty"] = 0
				row["allocated_qty"] = int(row.qty)
				for iid: String in plan.by_instance:
					if new_inputs.has(iid):
						row.new_building_qty += int(plan.by_instance[iid].get(gid, 0))
				requests.append(row)
	for buy: Dictionary in MatchState.recurring_buys:
		requests.append(_request(str(buy.get("dest", "")), str(buy.get("good", "")), int(buy.get("qty", 0)), int(buy.get("qty", 0)), "recurring", ""))
	var headroom := maxf(0.0, MatchState.purchase_headroom())
	for row: Dictionary in requests:
		var quote := MatchState.preview_buy(str(row.tile), str(row.good), int(row.qty)) if int(row.qty) > 0 else {}
		var amount := float(quote.get("cost", 0.0))
		if amount > headroom and int(row.qty) > 0:
			row.qty = mini(int(row.qty), floori(headroom / maxf(0.0001, amount / float(row.qty))))
			quote = MatchState.preview_buy(str(row.tile), str(row.good), int(row.qty)) if int(row.qty) > 0 else {}
		if quote.is_empty():
			row.qty = 0
		row["amount"] = float(quote.get("cost", 0.0))
		row["payment_in"] = 1 + maxi(0, int(quote.get("turns", 0)))
		row["limited"] = int(row.qty) < int(row.wanted)
		headroom = maxf(0.0, headroom - float(row.amount))
	for b: Dictionary in buildings:
		var iid := str(b.get("instance_id",""))
		if not service_previews.has(iid): continue
		var p: Dictionary = service_previews.get(iid,{})
		if not bool(p.get("can_run",false)): continue
		for item: Dictionary in p.buy.items:
			requests.append({"tile":str(b.tile_id),"good":str(item.good),"qty":int(item.quantity),"wanted":int(item.quantity),"kind":"middleman","instance_id":iid,"amount":float(item.goods_value)+float(item.fee),"payment_in":1,"limited":false})
	var order_total := 0.0
	for row: Dictionary in requests:
		order_total += float(row.amount)
	return {"turn": TurnManager.current_turn, "cash": MatchState.money, "payments": committed,
		"middleman":service_previews, "due": due_total(committed), "orders": requests, "orders_total": order_total,
		"labour": labour, "maintenance": maintenance, "ms": float(Time.get_ticks_usec() - started) / 1000.0}

static func _request(tile: String, good: String, qty: int, wanted: int, kind: String, iid: String) -> Dictionary:
	return {"tile": tile, "good": good, "qty": qty, "wanted": wanted, "kind": kind, "instance_id": iid}

static func _quantity(stock: Dictionary, tile: String, good: String) -> int:
	return int((stock.get(tile, {}) as Dictionary).get(good, 0))

static func _add(stock: Dictionary, tile: String, good: String, qty: int) -> void:
	if not stock.has(tile):
		stock[tile] = {}
	stock[tile][good] = maxi(0, _quantity(stock, tile, good) + qty)

static func _used(stock: Dictionary, tile: String) -> int:
	var result := 0
	for qty: Variant in (stock.get(tile, {}) as Dictionary).values():
		result += int(qty)
	return result

static func _land(stock: Dictionary, held: Array, shipment: Dictionary, tile: String) -> void:
	var qty := int(shipment.get("qty", 0))
	var accepted := mini(qty, maxi(0, Stockpile.get_capacity(tile) - _used(stock, tile)))
	_add(stock, tile, str(shipment.get("good_id", "")), accepted)
	if accepted < qty:
		var rest := shipment.duplicate()
		rest["qty"] = qty - accepted
		rest["destination_tile"] = tile
		held.append(rest)

static func begin_turn() -> void:
	_before = snapshot()
	_orders = []
	_arrivals_paid = 0.0
	_recording = true

static func record_order(tile: String, good: String, qty: int, amount: float, lead: int, tags: Dictionary) -> void:
	if not _recording:
		return
	var kind := "construction" if str(tags.get("construction_instance_id", "")) != "" else "input"
	if str(tags.get("upgrade_instance_id", "")) != "":
		kind = "upgrade"
	_orders.append({"tile": tile, "good": good, "qty": qty, "amount": amount, "payment_in": lead + 1, "kind": kind})

static func record_arrival(amount: float) -> void:
	if _recording:
		_arrivals_paid += amount

static func finish_turn(summary: Dictionary, tab_payments: float) -> void:
	if not _recording:
		return
	_recording = false
	var total := 0.0
	for row: Dictionary in _orders:
		total += float(row.amount)
	var paid := _arrivals_paid + float(summary.get("interest_paid", 0.0)) + tab_payments
	last_comparison = {"turn": int(_before.turn), "forecast": _before, "actual_orders": _orders.duplicate(true),
		"actual_due": paid, "actual_orders_total": total, "actual_labour": float(summary.get("labour_paid", 0.0)),
		"actual_maintenance": float(summary.get("maintenance_paid", 0.0)), "due_error": paid - float(_before.due),
		"order_error": total - float(_before.orders_total)}

static func _power_available(tile: String, recipe: Dictionary) -> bool:
	return (int(recipe.get("energy_req", 0)) <= 0 and str(recipe.get("output_name", "")) != "power") or Power.is_supplied(tile, int(recipe.get("energy_req", 0)))

## One shared exceptional-cost total for the notice, Balance link and Upcoming tab.
## Includes pending construction/upgrade bills and initial inputs; excludes routine
## purchases, labour, upkeep and debt service. Only charges on the next resolution count.
static func next_turn_costs(data: Dictionary) -> Dictionary:
	return attention_costs(data, {})

static func attention_costs(data: Dictionary, _previous: Dictionary) -> Dictionary:
	var bills := 0.0
	var later := 0.0
	var orders := 0.0
	var payment_rows: Array = []
	var order_rows: Array = []
	for row: Dictionary in data.get("payments", []):
		if int(row.get("due_in", 1)) > 1:
			continue
		var construction := str(row.get("source_kind", "")) in ["construction", "upgrade"]
		var amount := float(row.get("amount", 0.0)) if construction else float(row.get("extra_amount", 0.0))
		if amount <= 0.0:
			continue
		var extra := row.duplicate()
		extra.amount = amount
		payment_rows.append(extra)
		if int(row.get("due_in", 1)) <= 1:
			bills += amount
		else:
			later += amount
	for row: Dictionary in data.get("orders", []):
		if int(row.get("payment_in", 1)) > 1:
			continue
		var kind := str(row.get("kind", ""))
		var share := 1.0 if kind in ["construction", "upgrade"] else 0.0
		if kind == "input" and int(row.get("qty", 0)) > 0:
			# Preserve the attribution ratio when financing clips a shared order.
			share = clampf(float(row.get("new_building_qty", 0)) / maxf(1.0, float(row.get("allocated_qty", row.qty))), 0.0, 1.0)
		var amount := float(row.get("amount", 0.0)) * share
		if amount <= 0.0:
			continue
		var extra := row.duplicate()
		extra.amount = amount
		extra.qty = roundi(float(row.get("qty", 0)) * share)
		order_rows.append(extra)
		orders += amount
	return {"bills": bills, "later": later, "orders": orders, "total": bills + later + orders,
		"payments": payment_rows, "order_rows": order_rows}


## Round the cash buffer upward; the underlying bill remains exact.
static func recommended_buffer(amount: float) -> int:
	return int(ceil(maxf(0.0, amount) / 50.0)) * 50
