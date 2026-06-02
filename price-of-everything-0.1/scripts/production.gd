extends Node

const MAX_PRODUCTION_PASSES := 30

var last_turn_summary: Dictionary = {}
var missing_by_building: Dictionary = {}  # instance_id -> Array of missing inputs
var last_turn_run: Dictionary = {}  # instance_id -> true (set of buildings that ran)
var produced_by_building: Dictionary = {}  # instance_id -> good_id/internal_name -> lifetime qty
var full_output_streak_by_building: Dictionary = {}  # instance_id -> consecutive turns at full output
var _building_turn_reports: Array = []  # BuildingTurnReport dicts for CostSolver
# Per-turn record of goods delivered to each tile and the transport paid to get them there.
# { tile_id -> { good_id -> {"cost": float, "qty": float} } }. Used to impute inbound
# transport into the unit cost of buildings that consume those goods.
var _inbound_delivery_this_turn: Dictionary = {}
# This turn's same-tile (0-turn) outputs, merged into stockpiles AFTER production
# so a good produced this turn can't be consumed by another building the same turn.
var _output_buffer: Array = []
var summary := {
	# ... existing fields ...
	"interest_paid": 0.0,
	"taxes_paid": 0.0,
	"dividends_paid": 0.0,
	# ... existing fields ...
}

signal turn_processed(summary: Dictionary)
signal building_starved(starvation_record: Dictionary)

func _ready() -> void:
	await get_tree().process_frame
	if not TurnManager.phase_started.is_connected(_on_phase_started):
		TurnManager.phase_started.connect(_on_phase_started)
	print("[Production] ready and connected to TurnManager")

func _on_phase_started(phase: int) -> void:
	print("[Production] _on_phase_started fired, phase=", phase)
	if phase == TurnManager.Phase.PROCESS:
		_process_production()

func _process_production() -> void:
	last_turn_run.clear()
	missing_by_building.clear()
	_building_turn_reports.clear()
	_inbound_delivery_this_turn.clear()
	_output_buffer.clear()
	Power.reset_for_turn()
	
	var summary := {
	"produced": {},
	"consumed": {},
	"sold": {},
	"purchased": {},
	"starved": [],
	# Money breakdown (Pass 8 additions)
	"goods_sales_revenue": 0.0,
	"power_sales_revenue": 0.0,
	"power_purchase_cost": 0.0,
	"transport_paid": 0.0,
	"goods_purchased_cost": 0.0,
	"maintenance_paid": 0.0,
	"labour_paid": 0.0,
	"taxes_paid": 0.0,
	"dividends_paid": 0.0,
	"interest_paid": 0.0,
	# Per-building-type cost breakdowns for money-panel tooltips.
	# Each maps building_id -> {"count": int, "amount": float}.
	"maintenance_by_type": {},
	"labour_by_type": {},
	"goods_purchased_by_type": {},
	"power_purchase_by_type": {},
	"power_demand_by_type": {},
	# Aggregates (preserved for compatibility)
	"money_in": 0.0,
	"money_out": 0.0,
	# Power-specific
	"power_supply": 0,
	"power_demand": 0,
	"grid_bought": 0,
	"grid_sold": 0,
}

	_process_transport_arrivals(summary)
	
	var all_buildings: Array = MatchState.buildings.values()
	var has_run: Dictionary = {}
	
	# === CASCADING PRODUCTION PHASE ===
	var pass_count := 0
	while pass_count < MAX_PRODUCTION_PASSES:
		var progress_made := false
		
		for building in all_buildings:
			var instance_id: String = building.instance_id
			if has_run.get(instance_id, false):
				continue
			
			var recipe: Dictionary = Catalog.get_recipe(building.recipe_id)
			if recipe.is_empty():
				has_run[instance_id] = true
				continue
			
			var check: Dictionary = _can_run_recipe(building, recipe)
			if not check.can_run:
				missing_by_building[instance_id] = check.missing
				continue
			
			# Building can run — execute it
			_consume_inputs(building, recipe, summary)
			
			# Register power demand if any
			var energy_req: int = recipe.get("energy_req", 0)
			if energy_req > 0:
				Power.add_demand(energy_req)
				summary.consumed["power"] = summary.consumed.get("power", 0) + energy_req
				if MatchState.is_player_owned(building):
					_accumulate_by_type(summary.power_demand_by_type, str(building.get("building_id", "")), float(energy_req))
			
			# Route output: power goes to Power supply, everything else to Stockpile
			var output_name: String = recipe.get("output_name", "")
			if output_name == "power":
				var output_qty: int = recipe.get("output_qty", 0)
				Power.add_supply(output_qty)
				summary.produced["power"] = summary.produced.get("power", 0) + output_qty
				_record_building_output(instance_id, "power", output_qty)
				print("[Production] Building %s produced %d Power" % [instance_id, output_qty])
			else:
				_produce_outputs(building, recipe, summary)
				_capture_turn_report(building, recipe)

			has_run[instance_id] = true
			last_turn_run[instance_id] = true
			full_output_streak_by_building[instance_id] = full_output_streak_by_building.get(instance_id, 0) + 1
			progress_made = true
			missing_by_building.erase(instance_id)
		
		if not progress_made:
			break
		pass_count += 1
	
	if pass_count >= MAX_PRODUCTION_PASSES:
		push_warning("[Production] Hit MAX_PRODUCTION_PASSES (%d). Possible cycle in recipes." % MAX_PRODUCTION_PASSES)
	
	# === STARVATION REPORTING ===
	for building in all_buildings:
		if not has_run.get(building.instance_id, false):
			var missing: Array = missing_by_building.get(building.instance_id, [])
			var record := {
				"instance_id": building.instance_id,
				"building_id": building.building_id,
				"tile_id": building.tile_id,
				"missing": missing,
			}
			summary.starved.append(record)
			full_output_streak_by_building[building.instance_id] = 0
			building_starved.emit(record)
			
			var missing_strs: Array = []
			for m in missing:
				missing_strs.append("%s (need %d, have %d)" % [
					m.internal_name, m.need, m.have
				])
			var missing_msg: String = ", ".join(missing_strs) if not missing_strs.is_empty() else "no recipe inputs"
			print("[Production] Building %s STARVED — missing: %s" % [
				building.instance_id, missing_msg
			])
	
	# === GRID SETTLEMENT ===
	var grid: Dictionary = Power.settle_grid_transactions()
	summary.power_supply = grid.supply
	summary.power_demand = grid.demand
	summary.grid_bought = grid.grid_bought
	summary.grid_sold = grid.grid_sold
	if grid.grid_buy_cost > 0:
		MatchState.add_money(-grid.grid_buy_cost)
		summary.power_purchase_cost = grid.grid_buy_cost
		summary.money_out += grid.grid_buy_cost
		# Attribute the grid purchase across consumer building types by demand share.
		var total_demand := 0.0
		for k in summary.power_demand_by_type:
			total_demand += float(summary.power_demand_by_type[k].get("amount", 0.0))
		if total_demand > 0.0:
			for k in summary.power_demand_by_type:
				var d: Dictionary = summary.power_demand_by_type[k]
				var share: float = float(d.get("amount", 0.0)) / total_demand
				_accumulate_by_type(summary.power_purchase_by_type, str(k), grid.grid_buy_cost * share, int(d.get("count", 0)))

	if grid.grid_sell_revenue > 0:
		MatchState.add_money(grid.grid_sell_revenue)
		summary.power_sales_revenue = grid.grid_sell_revenue
		summary.money_in += grid.grid_sell_revenue
	# Merge this turn's same-tile outputs into stockpiles now — after all production
	# (so they can't be consumed this turn) but before selling (so they're sellable).
	_flush_output_buffer()

	# Recurring + scheduled (split) tile-to-tile moves fire here, on the merged stock.
	MatchState.run_recurring_and_scheduled_moves()

	# Top up market-sourced building inputs (bought from the nearest port, arrive in N turns).
	_buy_market_inputs(all_buildings, summary)

	# === SELL PHASE (when production defaults to market) ===
	if MatchState.sell_mode != MatchState.SellMode.STOCKPILE_ALL:
		var totals: Dictionary = Stockpile.get_tile_totals(null)
		_sell_stockpile_totals(null, totals, summary, false)

	for tile_id in MatchState.consume_queued_stockpile_market_sales():
		var tile_totals: Dictionary = Stockpile.get_tile_totals(str(tile_id))
		_sell_stockpile_totals(str(tile_id), tile_totals, summary, true)

	for tile_id in MatchState.get_sell_surplus_tiles():
		var committed: Dictionary = compute_committed_for_tile(str(tile_id))
		var tile_totals: Dictionary = Stockpile.get_tile_totals(str(tile_id))
		var surplus: Dictionary = {}
		for good_id in tile_totals:
			var surplus_qty: int = max(0, int(tile_totals[good_id]) - int(committed.get(good_id, 0)))
			if surplus_qty > 0:
				surplus[good_id] = surplus_qty
		if not surplus.is_empty():
			_sell_stockpile_totals(str(tile_id), surplus, summary, true)

	# === COSTS PHASE ===
	# Only the player pays maintenance/labour on the buildings they own — NPC-owned
	# infrastructure (e.g. the shipping corporation's ports) is not the player's expense.
	for building in all_buildings:
		if not MatchState.is_player_owned(building):
			continue
		var btype: String = str(building.get("building_id", ""))
		var maint: float = _calculate_maintenance_cost(building)
		var labour: float = _calculate_labour_cost(building)
		var total_cost: float = maint + labour
		MatchState.add_money(-total_cost)
		summary.maintenance_paid += maint
		summary.labour_paid += labour
		summary.money_out += total_cost
		_accumulate_by_type(summary.maintenance_by_type, btype, maint)
		_accumulate_by_type(summary.labour_by_type, btype, labour)
		# === LOAN INTEREST PAYMENTS ==+var loan_payment: float = LoanState.process_payments()
	var loan_payment: float = LoanState.process_payments()
	if loan_payment > 0:
		summary.interest_paid = loan_payment
		summary.money_out += loan_payment
		# === TAX & DIVIDEND PHASE ===
# Compute pre-tax profit: revenue - operating costs - interest.
# Only deduct tax/dividends if profit is positive.
	var revenue: float = summary.goods_sales_revenue + summary.power_sales_revenue
	var operating_costs: float = (
		summary.maintenance_paid
		+ summary.labour_paid
		+ summary.power_purchase_cost
		+ summary.transport_paid
	)
	var operating_profit: float = revenue - operating_costs
	var pre_tax_profit: float = operating_profit - summary.interest_paid

	if pre_tax_profit > 0:
		var tax: float = pre_tax_profit * EconomyConfig.TAX_RATE
		MatchState.add_money(-tax)
		summary.taxes_paid = tax
		summary.money_out += tax
	
		var post_tax_profit: float = pre_tax_profit - tax
		if post_tax_profit > 0:
			var dividends: float = post_tax_profit * EconomyConfig.DIVIDEND_RATE
			MatchState.add_money(-dividends)
			summary.dividends_paid = dividends
			summary.money_out += dividends
	
	CostSolver.solve(_building_turn_reports)

	last_turn_summary = summary
	turn_processed.emit(summary)
	
	print("[Production] Stockpile after turn: ", Stockpile.get_all_totals())
	print("[Production] Power: supply=%d demand=%d net=%d (bought=%d sold=%d)" % [
		summary.power_supply, summary.power_demand,
		summary.power_supply - summary.power_demand,
		summary.grid_bought, summary.grid_sold
	])
	print("[Production] Turn summary: produced=%s consumed=%s sold=%s starved=%d net=£%.2f passes=%d" % [
		summary.produced, summary.consumed, summary.sold, summary.starved.size(),
		summary.money_in - summary.money_out, pass_count
	])
	print("[Production] Cash breakdown: goods=£%.2f power_sold=£%.2f power_bought=£%.2f costs=£%.2f goods_bought=£%.2f interest=£%.2f tax=£%.2f div=£%.2f net=£%.2f" % [
	summary.goods_sales_revenue,
	summary.power_sales_revenue,
	summary.power_purchase_cost,
	summary.maintenance_paid + summary.labour_paid + summary.transport_paid,
	summary.goods_purchased_cost,
	summary.interest_paid,
	summary.taxes_paid,
	summary.dividends_paid,
	summary.money_in - summary.money_out
])
	# Diagnostic: goods sitting in pending shipments (sales + moves). If a produced good
	# is neither stockpiled nor sold, it should show here as in-transit; if not, it's lost.
	var _in_transit_dbg: Dictionary = {}
	for s in MatchState.get_pending_transport_shipments():
		if bool(s.get("is_sale", false)):
			for it in s.get("sale_record", {}).get("items", []):
				var sg := str(it.get("good_id", ""))
				_in_transit_dbg[sg] = int(_in_transit_dbg.get(sg, 0)) + int(it.get("qty", 0))
		else:
			var mg := str(s.get("good_id", ""))
			if mg != "":
				_in_transit_dbg[mg] = int(_in_transit_dbg.get(mg, 0)) + int(s.get("qty", 0))
	print("[Production] In transit (pending shipments): ", _in_transit_dbg)

	

# --- Helpers ---

func _get_recipe(recipe_id: String) -> Dictionary:
	if recipe_id == "":
		return {}
	# ADAPT THIS to your Recipes accessor
	return Catalog.get_recipe(recipe_id)
	
	
func _produce_outputs(building: Dictionary, recipe: Dictionary, summary: Dictionary) -> void:
	for output in _recipe_output_items(recipe):
		var output_name: String = output.get("internal_name", "")
		var output_qty: int = output.get("qty", 0)
		
		if output_name == "" or output_qty <= 0:
			continue

		# Recipes use internal_name; need good_id
		var good: Dictionary = Catalog.get_good_by_internal_name(output_name)
		if good.is_empty():
			push_warning("[Production] Unknown good '%s' from recipe %s" % [
				output_name, recipe.get("recipe_id", "?")
			])
			continue
		
		print("[Production] Building %s produced %d %s" % [
			building.instance_id, output_qty, good.display_name
		])
		
		_dispatch_output_to_stockpile(building, good, output_qty, summary)
		summary.produced[good.id] = summary.produced.get(good.id, 0) + output_qty
		_record_building_output(building.instance_id, good.id, output_qty)

func _process_transport_arrivals(summary: Dictionary) -> void:
	for shipment in MatchState.advance_transport_shipments():
		if shipment.get("is_sale", false):
			_credit_arrived_sale(shipment, summary)
			continue
		var destination_tile: String = shipment.get("destination_tile", "")
		var good_id: String = shipment.get("good_id", "")
		var qty: int = int(shipment.get("qty", 0))
		if destination_tile == "" or good_id == "" or qty <= 0:
			continue
		var added := Stockpile.add(destination_tile, good_id, qty)
		var per_unit_transport: float = float(shipment.get("transport_cost", 0.0)) / float(qty)
		_record_inbound_delivery(destination_tile, good_id, added, per_unit_transport)
		if added < qty:
			push_warning("[Production] Transport arrival for %s only stored %d/%d %s" % [
				destination_tile,
				added,
				qty,
				Catalog.get_display_name(good_id),
			])

func _credit_arrived_sale(shipment: Dictionary, summary: Dictionary) -> void:
	# A sale shipment reached its port this turn — pay out the locked-in revenue.
	var sale_record: Dictionary = shipment.get("sale_record", {})
	for item in sale_record.get("items", []):
		var gid := str(item.get("good_id", ""))
		var qty := int(item.get("qty", 0))
		var rev := float(item.get("revenue", 0.0))
		if rev > 0.0:
			MatchState.add_money(rev)
			_add_summary_sale(summary, gid, qty, rev)
	if float(sale_record.get("total_revenue", 0.0)) > 0.0:
		MatchState.emit_stockpile_market_sale_completed(sale_record)
		var port_tile := str(shipment.get("destination_tile", ""))
		if port_tile != "":
			MatchState.market_sale_arrived_at_port.emit(port_tile, float(sale_record.get("total_revenue", 0.0)))

func _sell_output_to_market(source_tile: String, good: Dictionary, qty: int, summary: Dictionary) -> void:
	# Output destined for the market ships to the nearest port; revenue lands on arrival.
	var good_id: String = good.id
	var revenue: float = float(qty) * MarketState.get_price(good_id)
	var port_tile := Catalog.nearest_port_tile(source_tile) if source_tile != "" else ""
	var route := _transport_route(source_tile, port_tile, good_id)
	# Pay to ship the output to its market (the port) — surfaced as transport cost.
	var transport_cost: float = EconomyConfig.transport_cost_for(good_id, qty, int(route.turns))
	if transport_cost > 0.0:
		MatchState.add_money(-transport_cost)
		summary.transport_paid += transport_cost
		summary.money_out += transport_cost
	var sale_record := {
		"tile_id": source_tile,
		"items": [{"good_id": good_id, "qty": qty, "revenue": revenue}],
		"total_qty": qty,
		"total_revenue": revenue,
	}
	MatchState.log_market_sale(source_tile, port_tile, good_id, qty, int(route.turns))
	if port_tile != "" and int(route.turns) >= 1:
		# Goods are in transit; cash arrives when the port receives them (x turns later).
		MatchState.queue_transport_shipment({
			"is_sale": true,
			"source_tile": source_tile,
			"destination_tile": port_tile,
			"sale_record": sale_record,
			"tile_distance": route.tile_distance,
			"transport_turns": route.turns,
			"turns_remaining": int(route.turns),
			"path": route.get("path", []),
			"legs": route.get("legs", []),
			"tiles": route.get("tiles", []),
		})
	else:
		MatchState.add_money(revenue)
		_add_summary_sale(summary, good_id, qty, revenue)
		MatchState.emit_stockpile_market_sale_completed(sale_record)
		if port_tile != "":
			MatchState.market_sale_arrived_at_port.emit(port_tile, revenue)

func _dispatch_output_to_stockpile(building: Dictionary, good: Dictionary, qty: int, summary: Dictionary) -> void:
	var stockpile_coord = _output_stockpile_coord(building, good.id)
	if stockpile_coord == null:
		# Market-bound output (no stockpile destination): sell it via the nearest port.
		_sell_output_to_market(str(building.get("tile_id", "")), good, qty, summary)
		return
	var route := _transport_route(building.get("tile_id", ""), stockpile_coord, good.id)
	var transport_cost: float = EconomyConfig.transport_cost_for(good.id, qty, int(route.turns))
	if transport_cost > 0.0:
		MatchState.add_money(-transport_cost)
		summary.transport_paid += transport_cost
		summary.money_out += transport_cost

	if int(route.turns) >= 1:
		# Inter-tile: in transit, arrives route.turns turns later (a tile-to-tile move).
		MatchState.log_move_shipment(str(building.get("tile_id", "")), str(stockpile_coord), good.id, qty, int(route.turns))
		MatchState.queue_transport_shipment({
			"source_tile": building.get("tile_id", ""),
			"destination_tile": str(stockpile_coord),
			"good_id": good.id,
			"qty": qty,
			"tile_distance": route.tile_distance,
			"transport_turns": route.turns,
			"turns_remaining": int(route.turns),
			"transport_cost": transport_cost,
			"path": route.get("path", []),
			"legs": route.get("legs", []),
			"tiles": route.get("tiles", []),
		})
		return

	# Same-tile (0-turn) output: buffer it, merged after all production this turn.
	_output_buffer.append({
		"coord": stockpile_coord,
		"good_id": good.id,
		"qty": qty,
		"transport_cost": transport_cost,
	})

func _flush_output_buffer() -> void:
	for o in _output_buffer:
		var added: int = Stockpile.add(o.coord, str(o.good_id), int(o.qty))
		if o.coord != null and str(o.coord) != "":
			var per_unit: float = (float(o.transport_cost) / float(o.qty)) if int(o.qty) > 0 else 0.0
			_record_inbound_delivery(str(o.coord), str(o.good_id), added, per_unit)
		if added < int(o.qty):
			push_warning("[Production] Stockpile full for %s; stored %d/%d %s" % [
				str(o.coord), added, int(o.qty), Catalog.get_display_name(str(o.good_id)),
			])
	_output_buffer.clear()

func _output_stockpile_coord(building: Dictionary, good_id: String):
	var instance_id: String = building.get("instance_id", "")
	if MatchState.is_output_market(instance_id, good_id):
		return null  # explicit per-building market route — sell to nearest port
	var destination_tile := MatchState.get_output_stockpile_destination(instance_id, good_id)
	if destination_tile != "":
		return destination_tile
	if MatchState.sell_mode == MatchState.SellMode.STOCKPILE_ALL:
		return building.get("tile_id", null)
	return null

func _transport_route(source_tile: String, destination_tile, good_id: String = "") -> Dictionary:
	if destination_tile == null or str(destination_tile) == "":
		return {"tile_distance": 0, "turns": 0, "delayed": false, "path": [], "legs": []}
	var dest := str(destination_tile)
	var r := Catalog.route(source_tile, dest, good_id)
	var turns: int = int(r.get("turns", 0))
	if turns >= (1 << 30):
		# Unreachable via road/rail/overland networks — fall back to straight-line overland.
		turns = EconomyConfig.transport_turns_for_tile_distance(_tile_distance(source_tile, dest))
	return {
		"tile_distance": _tile_distance(source_tile, dest),
		"turns": turns,
		"delayed": turns > 1,
		"path": r.get("path", []),
		"legs": r.get("legs", []),
		"tiles": r.get("tiles", []),
	}

func _tile_distance(source_tile: String, destination_tile: String) -> int:
	var source := _tile_id_to_coord(source_tile)
	var destination := _tile_id_to_coord(destination_tile)
	if source == Vector2i(-1, -1) or destination == Vector2i(-1, -1):
		return 0
	var source_axial := _oddq_to_axial(source)
	var destination_axial := _oddq_to_axial(destination)
	var dq := source_axial.x - destination_axial.x
	var dr := source_axial.y - destination_axial.y
	return int((abs(dq) + abs(dr) + abs(dq + dr)) / 2)

func _tile_id_to_coord(tile_id: String) -> Vector2i:
	var parts := tile_id.split("_")
	if parts.size() != 3 or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return Vector2i(-1, -1)
	return Vector2i(int(parts[1]) - 1, int(parts[2]) - 1)

func _oddq_to_axial(coord: Vector2i) -> Vector2i:
	return Vector2i(coord.x, coord.y - int((coord.x - (coord.x & 1)) / 2))

func _sell_stockpile_totals(coord, totals: Dictionary, summary: Dictionary, emit_toast: bool) -> Dictionary:
	var source_tile := "" if coord == null else str(coord)
	var sale_record := {
		"tile_id": source_tile,
		"items": [],
		"total_qty": 0,
		"total_revenue": 0.0,
	}
	# Sold goods ship by sea: route to the nearest port; cash lands once it arrives
	# (x turns later, x = transport duration at 2 tiles/turn). Shipping costs apply.
	var port_tile := Catalog.nearest_port_tile(source_tile) if source_tile != "" else ""
	var route := _transport_route(source_tile, port_tile)
	var deferred: bool = port_tile != "" and int(route.turns) >= 1
	var transport_cost := 0.0
	for good_id in totals.keys():
		var qty: int = int(totals[good_id])
		if qty <= 0:
			continue
		var good_key := str(good_id)
		var price: float = MarketState.get_price(good_key)
		var sold_qty: int = Stockpile.consume(coord, good_key, qty)
		if sold_qty <= 0:
			continue
		var sold_revenue: float = float(sold_qty) * price
		transport_cost += EconomyConfig.transport_cost_for(good_key, sold_qty, int(route.turns))
		sale_record.items.append({
			"good_id": good_key,
			"qty": sold_qty,
			"revenue": sold_revenue,
		})
		sale_record.total_qty += sold_qty
		sale_record.total_revenue += sold_revenue
		MatchState.log_market_sale(source_tile, port_tile, good_key, sold_qty, int(route.turns))
		if not deferred:
			# No port (or distance 0) — pay out immediately.
			MatchState.add_money(sold_revenue)
			_add_summary_sale(summary, good_key, sold_qty, sold_revenue)
	if transport_cost > 0.0:
		MatchState.add_money(-transport_cost)
		summary.transport_paid += transport_cost
		summary.money_out += transport_cost
	if deferred and int(sale_record.total_qty) > 0:
		# Goods are already consumed (in transit); cash lands when the port receives them.
		MatchState.queue_transport_shipment({
			"is_sale": true,
			"source_tile": source_tile,
			"destination_tile": port_tile,
			"sale_record": sale_record.duplicate(true),
			"tile_distance": route.tile_distance,
			"transport_turns": route.turns,
			"turns_remaining": int(route.turns),
			"path": route.get("path", []),
			"legs": route.get("legs", []),
			"tiles": route.get("tiles", []),
		})
	elif emit_toast and float(sale_record.total_revenue) > 0.0:
		MatchState.emit_stockpile_market_sale_completed(sale_record)
	return sale_record

func _add_summary_sale(summary: Dictionary, good_id: String, qty: int, revenue: float) -> void:
	var existing: Dictionary = summary.sold.get(good_id, {"qty": 0, "revenue": 0.0})
	existing.qty = int(existing.get("qty", 0)) + qty
	existing.revenue = float(existing.get("revenue", 0.0)) + revenue
	summary.sold[good_id] = existing
	summary.goods_sales_revenue += revenue
	summary.money_in += revenue

func _recipe_output_items(recipe: Dictionary) -> Array:
	if recipe.has("outputs"):
		return recipe.get("outputs", [])
	var output_name: String = recipe.get("output_name", "")
	var output_qty: int = recipe.get("output_qty", 0)
	if output_name == "" or output_qty <= 0:
		return []
	return [{"internal_name": output_name, "qty": output_qty}]

func _record_building_output(instance_id: String, good_key: String, qty: int) -> void:
	if instance_id == "" or good_key == "" or qty <= 0:
		return
	if not produced_by_building.has(instance_id):
		produced_by_building[instance_id] = {}
	var totals: Dictionary = produced_by_building[instance_id] as Dictionary
	totals[good_key] = totals.get(good_key, 0) + qty
	produced_by_building[instance_id] = totals

func _capture_turn_report(building: Dictionary, recipe: Dictionary) -> void:
	# Build inputs_consumed {good_id: qty} from recipe inputs
	var inputs_consumed: Dictionary = {}
	for input in recipe.get("inputs", []):
		var gid: String = input.get("good_id", "")
		if gid != "":
			inputs_consumed[gid] = input.get("qty", 0)

	# Build outputs_produced {good_id: qty} from recipe outputs (good_id already resolved)
	var outputs_produced: Dictionary = {}
	for output in _recipe_output_items(recipe):
		var gid: String = output.get("good_id", "")
		var qty: int    = output.get("qty", 0)
		if gid != "" and qty > 0:
			outputs_produced[gid] = qty

	if outputs_produced.is_empty():
		return  # nothing to track (e.g. power recipe fell through)

	var energy_req: int    = recipe.get("energy_req", 0)
	var power_cost: float  = float(energy_req) * EconomyConfig.GRID_BUY_PRICE

	# Inbound transport: per-unit transport paid to land each input on this tile
	# this turn, times the quantity consumed.
	var tile_id: String = building.get("tile_id", "")
	var inbound_transport: float = 0.0
	for gid in inputs_consumed:
		inbound_transport += _inbound_transport_per_unit(tile_id, gid) * float(inputs_consumed[gid])

	_building_turn_reports.append({
		"instance_id":      building.get("instance_id", ""),
		"building_id":      building.get("building_id", ""),
		"tile_id":          tile_id,
		"recipe_id":        recipe.get("recipe_id", ""),
		"inputs_consumed":  inputs_consumed,
		"outputs_produced": outputs_produced,
		"power_cost":       power_cost,
		"labour_cost":      _calculate_labour_cost(building),
		"maintenance_cost": _calculate_maintenance_cost(building),
		"inbound_transport": inbound_transport,
	})

func _record_inbound_delivery(tile_id: String, good_id: String, qty_added: int, per_unit_transport: float) -> void:
	if tile_id == "" or good_id == "" or qty_added <= 0:
		return
	if not _inbound_delivery_this_turn.has(tile_id):
		_inbound_delivery_this_turn[tile_id] = {}
	var by_good: Dictionary = _inbound_delivery_this_turn[tile_id]
	var rec: Dictionary = by_good.get(good_id, {"cost": 0.0, "qty": 0.0})
	rec.cost += per_unit_transport * float(qty_added)
	rec.qty += float(qty_added)
	by_good[good_id] = rec
	_inbound_delivery_this_turn[tile_id] = by_good

func _inbound_transport_per_unit(tile_id: String, good_id: String) -> float:
	var by_good: Dictionary = _inbound_delivery_this_turn.get(tile_id, {})
	var rec: Dictionary = by_good.get(good_id, {})
	var qty: float = rec.get("qty", 0.0)
	if qty <= 0.0:
		return 0.0
	return float(rec.get("cost", 0.0)) / qty

func _calculate_labour_cost(building: Dictionary) -> float:
	var bdata: Dictionary = Catalog.get_building(building.get("building_id", ""))
	var unskilled: int   = bdata.get("labour_unskilled_required", EconomyConfig.STUB_UNSKILLED_PER_BUILDING)
	var skilled: int     = bdata.get("labour_skilled_required",   EconomyConfig.STUB_SKILLED_PER_BUILDING)
	var high_skilled: int = bdata.get("labour_h_skilled_required", EconomyConfig.STUB_HIGH_SKILLED_PER_BUILDING)
	var base_cost: float = (
		unskilled    * EconomyConfig.LABOUR_UNSKILLED_RATE
		+ skilled    * EconomyConfig.LABOUR_SKILLED_RATE
		+ high_skilled * EconomyConfig.LABOUR_HIGH_SKILLED_RATE
	)
	return base_cost * MatchState.labour_multiplier

func _calculate_maintenance_cost(building: Dictionary) -> float:
	var bdata: Dictionary = Catalog.get_building(building.get("building_id", ""))
	var maint = bdata.get("maintenance_cost", null)
	return EconomyConfig.MAINTENANCE_PER_BUILDING if maint == null else float(maint)

func _accumulate_by_type(target: Dictionary, building_id: String, amount: float, count: int = 1) -> void:
	# target maps building_id -> {"count": int, "amount": float} for money-panel tooltips.
	var entry: Dictionary = target.get(building_id, {"count": 0, "amount": 0.0})
	entry["count"] = int(entry.get("count", 0)) + count
	entry["amount"] = float(entry.get("amount", 0.0)) + amount
	target[building_id] = entry

func _can_run_recipe(building: Dictionary, recipe: Dictionary) -> Dictionary:
	var inputs: Array = recipe.get("inputs", [])
	var missing: Array = []
	var tile_id: String = building.get("tile_id", "")
	
	# Check inputs
	for input in inputs:
		var have: int = Stockpile.get_at_tile(tile_id, input.good_id)
		if have < input.qty:
			missing.append({
				"good_id": input.good_id,
				"internal_name": input.internal_name,
				"need": input.qty,
				"have": have,
			})
	
	# Cable check: required for power consumers AND power producers
	var energy_req: int = recipe.get("energy_req", 0)
	var produces_power: bool = recipe.get("output_name", "") == "power"
	if energy_req > 0 or produces_power:
		if not Power.is_supplied(tile_id, energy_req):
			missing.append({
				"good_id": "power",
				"internal_name": "power",
				"need": energy_req if energy_req > 0 else 1,
				"have": 0,
			})
	
	return {
		"can_run": missing.is_empty(),
		"missing": missing,
	}

func compute_committed_for_tile(tile_id: String) -> Dictionary:
	var committed: Dictionary = {}
	for building in MatchState.get_buildings_on_tile(tile_id):
		var recipe: Dictionary = Catalog.get_recipe(building.get("recipe_id", ""))
		for input in recipe.get("inputs", []):
			var good_id: String = input.get("good_id", "")
			var qty: int = int(input.get("qty", 0))
			if good_id != "" and qty > 0:
				committed[good_id] = committed.get(good_id, 0) + qty
	return committed

func _inbound_qty(tile_id: String, good_id: String) -> int:
	var total := 0
	for s in MatchState.get_inbound_transport_shipments(tile_id, good_id):
		total += int(s.get("qty", 0))
	return total

func _buy_market_inputs(all_buildings: Array, summary: Dictionary) -> void:
	# For every input a player has set to "Market", keep the pipeline topped up to
	# (lead+1) turns of demand: order = target - on_tile - in_transit, shipped from the port.
	for building in all_buildings:
		var recipe: Dictionary = Catalog.get_recipe(building.recipe_id)
		if recipe.is_empty():
			continue
		var inputs: Array = recipe.get("inputs", [])
		if inputs.is_empty():
			continue
		var instance_id: String = building.instance_id
		var tile_id: String = str(building.get("tile_id", ""))
		# Don't buy inputs for a building that can't run for power reasons (avoids waste).
		var energy_req: int = recipe.get("energy_req", 0)
		var needs_power: bool = energy_req > 0 or recipe.get("output_name", "") == "power"
		if needs_power and not Power.is_supplied(tile_id, energy_req):
			continue
		var port := Catalog.nearest_port_tile(tile_id)
		if port == "":
			continue
		var lead := int(Catalog.route(port, tile_id).get("turns", 1))
		if lead >= (1 << 30):
			lead = EconomyConfig.transport_turns_for_tile_distance(Catalog.tile_hex_distance(port, tile_id))
		lead = maxi(1, lead)
		for input in inputs:
			var good_id := str(input.good_id)
			if MatchState.is_input_tile_only(instance_id, good_id):
				continue  # player opted this input out of market top-up
			var need_per_turn := int(input.qty)
			if need_per_turn <= 0:
				continue
			var target := need_per_turn * (lead + 1)
			var order := target - Stockpile.get_at_tile(tile_id, good_id) - _inbound_qty(tile_id, good_id)
			if order > 0:
				var bought: Dictionary = MatchState.queue_buy(tile_id, good_id, order)
				if not bought.is_empty():
					summary.goods_purchased_cost += float(bought.get("goods_cost", 0.0))
					summary.transport_paid += float(bought.get("transport_cost", 0.0))
					summary.money_out += float(bought.get("cost", 0.0))
					summary.purchased[good_id] = int(summary.purchased.get(good_id, 0)) + int(bought.get("qty", 0))
					_accumulate_by_type(summary.goods_purchased_by_type, str(building.get("building_id", "")), float(bought.get("goods_cost", 0.0)), 0)
	# Player-set recurring market purchases (Purchases tab), delivered to the chosen tile.
	for rb in MatchState.recurring_buys:
		var rgood := str(rb.get("good", ""))
		var rbought: Dictionary = MatchState.queue_buy(str(rb.get("dest", "")), rgood, int(rb.get("qty", 0)), false)
		if not rbought.is_empty():
			summary.goods_purchased_cost += float(rbought.get("goods_cost", 0.0))
			summary.transport_paid += float(rbought.get("transport_cost", 0.0))
			summary.money_out += float(rbought.get("cost", 0.0))
			summary.purchased[rgood] = int(summary.purchased.get(rgood, 0)) + int(rbought.get("qty", 0))
			_accumulate_by_type(summary.goods_purchased_by_type, "", float(rbought.get("goods_cost", 0.0)), 0)

func _consume_inputs(building: Dictionary, recipe: Dictionary, summary: Dictionary) -> void:
	var inputs: Array = recipe.get("inputs", [])
	var tile_id: String = building.get("tile_id", "")
	for input in inputs:
		Stockpile.consume(tile_id, input.good_id, input.qty)
		summary.consumed[input.good_id] = summary.consumed.get(input.good_id, 0) + input.qty
