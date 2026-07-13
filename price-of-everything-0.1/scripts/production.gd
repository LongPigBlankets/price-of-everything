extends Node
const BuildingLevels := preload("res://scripts/building_levels.gd")

const MAX_PRODUCTION_PASSES := 30

var last_turn_summary: Dictionary = {}
var missing_by_building: Dictionary = {}  # instance_id -> Array of missing inputs
var blocked_reason_by_building: Dictionary = {}  # instance_id -> {code, message}
var last_turn_run: Dictionary = {}  # instance_id -> true (set of buildings that ran)
var produced_by_building: Dictionary = {}  # instance_id -> good_id/internal_name -> lifetime qty
var full_output_streak_by_building: Dictionary = {}  # instance_id -> consecutive turns at full output
var _building_turn_reports: Array = []  # BuildingTurnReport dicts for CostSolver
# Decarbonisation squeeze: taxed-good consumption accumulated during the production pass
# (player buildings only), charged in the carbon_tax step after tax_dividends. The charge
# breakdown persists until next turn so the Building Detail panel can show actuals.
var _carbon_consumed_by_building: Dictionary = {}  # instance_id -> {good_id: qty}
var carbon_tax_by_building: Dictionary = {}        # instance_id -> £ charged last turn

# Read-only views for DecisionState (targets + revenue formulas). Reports are
# cleared at the start of each PROCESS, so during DECIDE these are last turn's.
func last_turn_reports() -> Array:
	return _building_turn_reports

func turn_report_for(instance_id: String) -> Dictionary:
	for r in _building_turn_reports:
		if str(r.get("instance_id", "")) == instance_id:
			return r
	return {}
var _just_constructed_this_turn: Dictionary = {}  # instance_id -> true
var _warning_buy_preview_cache: Dictionary = {}  # "tile|good|qty" -> preview_buy result
# Per-turn record of goods delivered to each tile and the transport paid to get them there.
# { tile_id -> { good_id -> {"cost": float, "qty": float} } }. Used to impute inbound
# transport into the unit cost of buildings that consume those goods.
var _inbound_delivery_this_turn: Dictionary = {}
# This turn's same-tile (0-turn) outputs, merged into stockpiles AFTER production
# so a good produced this turn can't be consumed by another building the same turn.
var _output_buffer: Array = []
# Per-turn same-tile production landing in each tile's stockpile this turn: {tile_id -> {good_id -> qty}}.
# Recorded during _flush_output_buffer, read by _buy_market_inputs so the market pipeline only tops up
# the SHORTFALL after recurring local production (don't buy steel you smelt on the same tile).
var _same_tile_supply: Dictionary = {}
# This turn's warehousing fee per tile ({tile_id -> £}), kept so CostSolver can
# attribute storage overheads to the tile's buildings. Rebuilt every COSTS phase.
var _warehousing_by_tile: Dictionary = {}
# Just-in-Time Logistics (research unlock): once unlocked, goods produced on a tile
# that its player buildings will consume bypass the warehouse via this feed buffer —
# {tile_id -> {good_id -> qty}}. Consumers draw it BEFORE the stockpile; anything
# beyond one turn of committed demand spills back into the warehouse at flush.
# SAVED (real goods live here); pays no warehousing fee and uses no capacity.
const JIT_UNLOCK_TITLE := "Just-in-Time Logistics"
var _direct_feed: Dictionary = {}
# Units routed into the feed this turn ({tile_id -> qty}) — stockpile-tab readout.
var _jit_fed_this_turn: Dictionary = {}
# Per-building intermittency result, instance_id -> {derate (0..1), green_consumed,
# unfirmed_intermittent, steady_consumed, demand}. Computed AFTER the cascade from this
# turn's actuals (which buildings ran + green actually generated); the derate is applied
# NEXT turn in _produce_outputs — a 1-turn lag that keeps it exact (no phantom/starved
# consumers, no over-cap green estimate). Persists across turns; read by the UI via
# get_building_intermittency() (ledger green-power filters) + get_tile_intermittency().
var _intermittency_by_building: Dictionary = {}
# Per-tile intermittency aggregate, tile_id -> {green_produced, green_intermittent_produced,
# total_produced, green_consumed, total_consumed, unfirmed_consumed, battery_cap, affected:
# [{iid, building_id, power}]}. Derived alongside _intermittency_by_building for the tile view.
var _intermittency_by_tile: Dictionary = {}
# Green power actually generated this turn per tile, by quality {tile -> {int, steady}}.
# Accumulated in the cascade power branch (already cable-capped); consumed by the
# post-cascade intermittency allocation. Reset each turn.
var _green_supply_by_tile: Dictionary = {}
# Every power producer this turn per tile: {tile -> [{iid, building_id, qty, quality}]}.
# Used by get_power_sources() to attribute a consumer's draw to specific source buildings
# (on demand, when the building detail panel opens — not in the per-turn hot path). Reset each turn.
var _power_sources_by_tile: Dictionary = {}
var _active_turn_summary: Dictionary = {}
var _pending_external_sales: Array = []
var summary := {
	# ... existing fields ...
	"interest_paid": 0.0,
	"taxes_paid": 0.0,
	"dividends_paid": 0.0,
	"profit_sharing_paid": 0.0,
	# ... existing fields ...
}

signal turn_processed(summary: Dictionary)
signal building_starved(starvation_record: Dictionary)

# --- Save/load (orchestrated by the SaveLoad autoload; docs/save_load_spec.md) ---
# Only lifetime stats persist; everything else here is rebuilt each PROCESS phase.

func export_state() -> Dictionary:
	return {
		"produced_by_building": produced_by_building.duplicate(true),
		"full_output_streak_by_building": full_output_streak_by_building.duplicate(true),
		"direct_feed": _direct_feed.duplicate(true),
	}

func import_state(d: Dictionary) -> void:
	produced_by_building = (d.get("produced_by_building", {}) as Dictionary).duplicate(true)
	full_output_streak_by_building = (d.get("full_output_streak_by_building", {}) as Dictionary).duplicate(true)
	_direct_feed = (d.get("direct_feed", {}) as Dictionary).duplicate(true)
	_jit_fed_this_turn.clear()
	last_turn_summary.clear()
	_pending_external_sales.clear()
	missing_by_building.clear()
	blocked_reason_by_building.clear()
	last_turn_run.clear()
	_just_constructed_this_turn.clear()
	_warning_buy_preview_cache.clear()

func _debug_logs_enabled() -> bool:
	return bool(MatchState.debug_turn_logs_enabled)

func _ready() -> void:
	# _on_phase_started is wired centrally by TurnManager._wire_sim_listeners so
	# the intra-phase order across sim systems is explicit, not autoload-order.
	if _debug_logs_enabled():
		print("[Production] ready (phase hook wired by TurnManager)")

func _on_phase_started(phase: int) -> void:
	if _debug_logs_enabled():
		print("[Production] _on_phase_started fired, phase=", phase)
	if phase == TurnManager.Phase.PROCESS:
		_process_production()

func _process_production() -> void:
	last_turn_run.clear()
	missing_by_building.clear()
	blocked_reason_by_building.clear()
	_just_constructed_this_turn.clear()
	_warning_buy_preview_cache.clear()
	_building_turn_reports.clear()
	_carbon_consumed_by_building.clear()
	_inbound_delivery_this_turn.clear()
	_output_buffer.clear()
	_green_supply_by_tile.clear()  # _intermittency_by_* persist (they are last turn's)
	_power_sources_by_tile.clear()
	MatchState.reset_tile_sales_for_turn()  # per-turn sales figure, not accumulated
	TurnProfiler.section_begin("power_reset")
	Power.reset_for_turn()
	TurnProfiler.section_end("power_reset")
	MatchState.tick_workforce_policies()

	var summary := {
	"produced": {},
	"consumed": {},
	"sold": {},
	"purchased": {},
	"starved": [],
	# Input-pipeline diagnostics (turn briefing): orders the market pipeline could
	# not fully place for CASH ({tile_id, good_id, requested, bought, short_cost}),
	# and inputs SPLICED between same-tile production and market top-up
	# ({tile_id, good_id, need, local, market}) — a local dip there starves the
	# building for the transport lead before bigger orders arrive.
	"input_orders_short": [],
	"input_splices": [],
	# Orders clipped by the destination tile's STORAGE capacity (not cash):
	# {tile_id, good_id, wanted, placed}. Feeds the tile-full briefing alert.
	"input_orders_capped": [],
	# Tiles whose warehouse is STRUCTURALLY smaller than their buildings' steady-state
	# working set (import buffers + local intermediates + outputs): {tile_id, required,
	# capacity}. Fires the critical briefing update before the tile actually jams.
	"storage_overcommitted": [],
	# Money breakdown (Pass 8 additions)
	"goods_sales_revenue": 0.0,
	"power_sales_revenue": 0.0,
	"power_purchase_cost": 0.0,
	"transport_paid": 0.0,
	"goods_purchased_cost": 0.0,
	# Per-good purchased goods cost (goods value only, excludes transport), used by
	# the money panel's Charts tab to split purchases by good tier.
	"purchased_cost": {},
	"maintenance_paid": 0.0,
	"labour_paid": 0.0,
	"advisor_paid": 0.0,
	# Per-turn storage fee on stockpiled goods (per unit, by transport class —
	# EconomyConfig.WAREHOUSING_COST_PER_UNIT_BY_CLASS).
	"warehousing_paid": 0.0,
	"taxes_paid": 0.0,
	"dividends_paid": 0.0,
	"profit_sharing_paid": 0.0,
	"interest_paid": 0.0,
	# Decarbonisation squeeze (PolicyState phases): the carbon levy charged on taxed
	# goods consumed by player buildings, and the per-green-MW subsidy received.
	"carbon_tax_paid": 0.0,
	"green_subsidy_received": 0.0,
	# Per-building-type cost breakdowns for money-panel tooltips.
	# Each maps building_id -> {"count": int, "amount": float}.
	"maintenance_by_type": {},
	"labour_by_type": {},
	"goods_purchased_by_type": {},
	"power_purchase_by_type": {},
	"power_demand_by_type": {},
	# Power generated this turn split by QUALITY (the green/grey + intermittent/steady
	# flags layered on top of `power`). Drives Greenest + the intermittency UI.
	"power_supply_by_quality": {"green_intermittent": 0, "green_steady": 0, "grey": 0},
	# Power produced this turn, split by generating building type (building_id ->
	# {count, amount}). Drives the Greenest victory track (green share of the grid).
	# Accumulated in the player-only cascade loop, the same scope as the `power_supply`
	# aggregate below (green / total must share a denominator).
	"power_supply_by_type": {},
	# Aggregates (preserved for compatibility)
	"money_in": 0.0,
	"money_out": 0.0,
	"fake_money": 0.0,   # cheat-added cash, reported as its own category
	# Power-specific
	"power_supply": 0,
	"power_demand": 0,
	"grid_bought": 0,
	"grid_sold": 0,
}
	_active_turn_summary = summary
	_merge_pending_external_sales(summary)

	TurnProfiler.section_begin("transport_arrivals")
	_process_transport_arrivals(summary)
	TurnProfiler.section_end("transport_arrivals")

	# Advance construction AFTER deliveries, BEFORE production and selling. tick_turn() promotes
	# any build whose countdown reached zero (it's then in the snapshot below and produces this
	# turn). claim_materials() lets awaiting projects consume their goods off the tile first, so
	# construction owns them ahead of production/sell/surplus. Order matters: tick before claim,
	# so a project that becomes under_construction this turn isn't also ticked the same turn.
	TurnProfiler.section_begin("construction")
	var completed_construction: Array = Construction.tick_turn()
	for completed_instance_id in completed_construction:
		_just_constructed_this_turn[str(completed_instance_id)] = true
	Construction.claim_materials()
	Construction.reorder_market_materials()  # re-buy any still-missing build materials
	# In-progress upgrades advance here too: awaiting projects claim freshly-arrived materials
	# off the tile (before production can consume them) and ticked-down ones promote to the
	# new level, so an upgrade that completes this turn produces at its new level immediately.
	MatchState.tick_upgrades()
	MatchState.tick_retrofits()   # recipe changes complete + swap in the new recipe
	MatchState.tick_demolish()    # queued demolitions complete: refund materials + remove
	TurnProfiler.section_end("construction")

	# Only the player's buildings are simulated each turn. The pre-existing NPC
	# pool (data/start_buildings.json) is inert scenery until bought — pre-filtering
	# here keeps turn cost proportional to the player's empire, not the ~500 NPC
	# buildings on the map. (Build the list once; every per-turn loop reuses it.)
	var all_buildings: Array = []
	for b in MatchState.buildings.values():
		if MatchState.is_player_owned(b):
			all_buildings.append(b)
	var has_run: Dictionary = {}

	# === CASCADING PRODUCTION PHASE ===
	TurnProfiler.section_begin("production_passes")
	var pass_count := 0
	while pass_count < MAX_PRODUCTION_PASSES:
		var progress_made := false

		for building in all_buildings:
			var instance_id: String = building.instance_id
			if has_run.get(instance_id, false):
				continue

			# A building being retooled produces nothing until the recipe change lands.
			if MatchState.is_retooling(instance_id):
				has_run[instance_id] = true
				continue

			# A paused building (player-stopped, e.g. via the supply-chain panel) is idle:
			# no inputs consumed, no outputs, no labour/power draw this turn.
			if MatchState.is_building_paused(instance_id):
				has_run[instance_id] = true
				continue

			var recipe: Dictionary = Catalog.get_recipe(building.recipe_id)
			if recipe.is_empty():
				has_run[instance_id] = true
				continue
			
			var check: Dictionary = _can_run_recipe(building, recipe)
			if not check.can_run:
				missing_by_building[instance_id] = check.missing
				var reason := _blocked_reason_for(building, recipe, check.missing)
				if reason.is_empty():
					blocked_reason_by_building.erase(instance_id)
				else:
					blocked_reason_by_building[instance_id] = reason
				continue
			
			# Building can run — execute it
			_consume_inputs(building, recipe, summary)
			
			# Register power demand if any (power-consumption modifiers shrink it). The
			# tile's cable level already cleared this draw in _can_run_recipe; record it
			# per-tile so it counts toward the cap + grid.
			var energy_req: int = _effective_energy_req(building, recipe)
			if energy_req > 0:
				Power.record_drawn(str(building.get("tile_id", "")), energy_req)
				summary.consumed["power"] = summary.consumed.get("power", 0) + energy_req
				if MatchState.is_player_owned(building):
					_accumulate_by_type(summary.power_demand_by_type, str(building.get("building_id", "")), float(energy_req))

			# Route output: power goes to Power supply (per-tile, capped), else Stockpile
			var output_name: String = recipe.get("output_name", "")
			if output_name == "power":
				var output_qty: int = _effective_power_output(building, recipe)
				Power.record_produced(str(building.get("tile_id", "")), output_qty)
				summary.produced["power"] = summary.produced.get("power", 0) + output_qty
				# Greenest victory track: attribute generation to its building type. The
				# enclosing cascade loop is already player-only, so this shares the
				# player-only scope of summary.power_supply (the green/total denominator).
				if output_qty > 0:
					_accumulate_by_type(summary.power_supply_by_type, str(building.get("building_id", "")), float(output_qty))
					# Tag the actual (already cable-capped) generation by quality.
					var pq: String = _power_quality(building, recipe)
					summary.power_supply_by_quality[pq] = int(summary.power_supply_by_quality.get(pq, 0)) + output_qty
					# Per-tile producer list (with building ids) for the on-demand "Power
					# Source(s)" attribution shown in the building detail panel.
					var st_src: String = str(building.get("tile_id", ""))
					var srcs: Array = _power_sources_by_tile.get(st_src, [])
					srcs.append({"iid": instance_id, "building_id": str(building.get("building_id", "")), "qty": output_qty, "quality": pq})
					_power_sources_by_tile[st_src] = srcs
					if pq != "grey":
						var gt: String = str(building.get("tile_id", ""))
						var ge: Dictionary = _green_supply_by_tile.get(gt, {"int": 0, "steady": 0})
						if pq == "green_intermittent":
							ge["int"] = int(ge["int"]) + output_qty
						else:
							ge["steady"] = int(ge["steady"]) + output_qty
						_green_supply_by_tile[gt] = ge
				_record_building_output(instance_id, "power", output_qty)
				if _debug_logs_enabled():
					print("[Production] Building %s produced %d Power" % [instance_id, output_qty])
			else:
				_produce_outputs(building, recipe, summary)
				_capture_turn_report(building, recipe)

			has_run[instance_id] = true
			last_turn_run[instance_id] = true
			# A new building stays in its selected half-capacity start until it has
			# actually completed one operating turn; starvation does not consume it.
			MatchState.consume_startup_capacity(instance_id)
			full_output_streak_by_building[instance_id] = full_output_streak_by_building.get(instance_id, 0) + 1
			progress_made = true
			missing_by_building.erase(instance_id)
			blocked_reason_by_building.erase(instance_id)
		
		if not progress_made:
			break
		pass_count += 1
	
	if pass_count >= MAX_PRODUCTION_PASSES:
		push_warning("[Production] Hit MAX_PRODUCTION_PASSES (%d). Possible cycle in recipes." % MAX_PRODUCTION_PASSES)
	TurnProfiler.section_end("production_passes")
	TurnProfiler.note_scale("production_passes", pass_count)

	# === STARVATION REPORTING ===
	TurnProfiler.section_begin("starvation_report")
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
			
			if _debug_logs_enabled():
				var missing_strs: Array = []
				for m in missing:
					missing_strs.append("%s (need %d, have %d)" % [
						m.internal_name, m.need, m.have
					])
				var missing_msg: String = ", ".join(missing_strs) if not missing_strs.is_empty() else "no recipe inputs"
				print("[Production] Building %s STARVED — missing: %s" % [
					building.instance_id, missing_msg
				])
	TurnProfiler.section_end("starvation_report")

	# === POWER INTERMITTENCY (recompute the derate for NEXT turn from this turn's actuals) ===
	TurnProfiler.section_begin("power_alloc")
	_compute_power_intermittency()
	TurnProfiler.section_end("power_alloc")

	# === GRID SETTLEMENT ===
	TurnProfiler.section_begin("grid_settlement")
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
	# Grid exports bypass MarketState.execute_sale(), but still satisfy research
	# conditions that ask the player to sell power. Keep them out of spot-price
	# impact while adding them to the saved lifetime sales ledger.
	if grid.grid_sold > 0:
		var power_good := Catalog.get_good_by_internal_name("power")
		MarketState.record_lifetime_sale_volume(
			str(power_good.get("id", "")), int(grid.grid_sold)
		)
	# Green-energy subsidy (PolicyState schedule): £ per green MW GENERATED this turn
	# (intermittent + steady — the same "green" the Greenest victory track counts).
	var subsidy_rate: float = PolicyState.green_subsidy_rate(int(TurnManager.current_turn))
	if subsidy_rate > 0.0:
		var q: Dictionary = summary.power_supply_by_quality
		var green_mw: float = float(q.get("green_intermittent", 0)) + float(q.get("green_steady", 0))
		var subsidy: float = green_mw * subsidy_rate
		if subsidy > 0.0:
			MatchState.add_money(subsidy)
			summary.green_subsidy_received = subsidy
			summary.money_in += subsidy
	TurnProfiler.section_end("grid_settlement")

	# Merge this turn's same-tile outputs into stockpiles now — after all production
	# (so they can't be consumed this turn) but before selling (so they're sellable).
	TurnProfiler.section_begin("flush_outputs")
	_flush_output_buffer()
	TurnProfiler.section_end("flush_outputs")

	# Recurring + scheduled (split) tile-to-tile moves fire here, on the merged stock.
	TurnProfiler.section_begin("recurring_moves")
	MatchState.run_recurring_and_scheduled_moves()
	TurnProfiler.section_end("recurring_moves")

	# Top up market-sourced building inputs (bought from the nearest port, arrive in N turns).
	TurnProfiler.section_begin("buy_market_inputs")
	_buy_market_inputs(all_buildings, summary)
	TurnProfiler.section_end("buy_market_inputs")

	# === SELL PHASE (when production defaults to market) ===
	TurnProfiler.section_begin("sell_phase")
	if MatchState.sell_mode != MatchState.SellMode.STOCKPILE_ALL:
		var totals: Dictionary = Stockpile.get_tile_totals(null)
		_sell_stockpile_totals(null, totals, summary, false)

	for tile_id in MatchState.consume_queued_stockpile_market_sales():
		var tile_totals: Dictionary = Stockpile.get_tile_totals(str(tile_id))
		_sell_stockpile_totals(str(tile_id), tile_totals, summary, true)

	# Auto-sell standing orders: the master "sell everything" toggle (sell_surplus_tiles)
	# and per-good overrides (auto_sell_goods). Runs AFTER production consumes inputs and
	# AFTER outbound moves ship, so anything still on the tile is genuine surplus — this
	# can never starve a local consumer or a downstream tile fed by recurring moves.
	for tile_id in MatchState.get_auto_sell_tiles():
		# Reserve the WORKING STOCK of the player's local consumers, not just one
		# turn of inputs: (lead+1) turns per good, mirroring the input pipeline.
		var reserved: Dictionary = compute_sell_reserve_for_tile(str(tile_id))
		var tile_totals: Dictionary = Stockpile.get_tile_totals(str(tile_id))
		# The master Sell all Surplus order means exactly that: it clears every unit
		# above the protected production/construction reserve, including old stock
		# accumulated before a consumer was built. Only the optional per-good order
		# honours a price-impact cap.
		var master_order := MatchState.is_sell_surplus_enabled(str(tile_id))
		var unit_cap: int = MatchState.auto_sell_unit_cap(str(tile_id))
		var surplus: Dictionary = {}
		for good_id in tile_totals:
			if not MatchState.should_auto_sell_good(str(tile_id), str(good_id)):
				continue
			# Surplus = on-tile stock minus the local consumers' working stock,
			# minus the player's "sell all except X" floor for this good. Construction
			# materials and the full lead-time production reserve are already included
			# above, so no unrelated old stock is grandfathered.
			var surplus_qty: int = max(0, int(tile_totals[good_id]) - int(reserved.get(good_id, 0))
				- MatchState.auto_sell_keep_for(str(tile_id), str(good_id)))
			if not master_order:
				surplus_qty = mini(surplus_qty, unit_cap)
			if surplus_qty > 0:
				surplus[good_id] = surplus_qty
		if not surplus.is_empty():
			_sell_stockpile_totals(str(tile_id), surplus, summary, true)
	TurnProfiler.section_end("sell_phase")

	# === COSTS PHASE ===
	# all_buildings is already player-only, so every building here is the player's
	# expense (NPC-owned scenery never reaches this loop).
	TurnProfiler.section_begin("maintenance_labour")
	for building in all_buildings:
		var btype: String = str(building.get("building_id", ""))
		var maint: float = _calculate_maintenance_cost(building)
		var active_recipe: Dictionary = Catalog.get_recipe(str(building.get("recipe_id", "")))
		# A paused (mothballed) building keeps its upkeep but carries no workforce.
		var labour: float = 0.0 if MatchState.is_building_paused(str(building.get("instance_id", ""))) else _calculate_labour_cost(building, active_recipe)
		var total_cost: float = maint + labour
		MatchState.add_money(-total_cost)
		summary.maintenance_paid += maint
		summary.labour_paid += labour
		summary.money_out += total_cost
		_accumulate_by_type(summary.maintenance_by_type, btype, maint)
		_accumulate_by_type(summary.labour_by_type, btype, labour)
		# === LOAN INTEREST PAYMENTS ==+var loan_payment: float = LoanState.process_payments()
	# Seaport subscription fees: flat per-turn charge per subscribed good.
	var seaport_fee: float = MatchState.seaport_subscription_fee()
	if seaport_fee > 0.0:
		MatchState.add_money(-seaport_fee)
		summary.money_out += seaport_fee
	_apply_advisor_costs(summary)
	# Warehousing: every stockpiled unit pays a per-turn storage fee by transport
	# class (solids rack cheaply; hazardous liquids/gases need certified tanks).
	# Per-tile fees are kept for CostSolver attribution to the tile's buildings.
	_warehousing_by_tile.clear()
	var warehousing := 0.0
	for wtile in Stockpile.tiles_with_stock():
		if not str(wtile).begins_with("tile_"):
			continue
		var wtotals: Dictionary = Stockpile.get_tile_totals(wtile)
		var tile_fee := 0.0
		for wgood in wtotals:
			tile_fee += float(wtotals[wgood]) * EconomyConfig.warehousing_cost_per_unit(str(wgood))
		if tile_fee > 0.0:
			warehousing += tile_fee
			_warehousing_by_tile[str(wtile)] = tile_fee
	if warehousing > 0.0:
		MatchState.add_money(-warehousing)
		summary.money_out += warehousing
	summary.warehousing_paid = warehousing
	TurnProfiler.section_end("maintenance_labour")

	TurnProfiler.section_begin("loan_payments")
	var loan_payment: float = LoanState.process_payments()
	if loan_payment > 0:
		summary.interest_paid = loan_payment
		summary.money_out += loan_payment
		# === TAX & DIVIDEND PHASE ===
	TurnProfiler.section_end("loan_payments")
	TurnProfiler.section_begin("tax_dividends")
	var revenue: float = summary.goods_sales_revenue + summary.power_sales_revenue
	var pre_tax_profit: float = _apply_tax_and_dividends(summary)
	var profit_sharing: float = _apply_profit_sharing(summary, pre_tax_profit)
	TurnProfiler.section_end("tax_dividends")

	# Carbon levy (PolicyState phases): charge taxed-good consumption accrued during the
	# production pass. NOT profit-gated — burning carbon costs money even on a loss turn;
	# that is the squeeze. Added after tax_dividends as its own government charge.
	TurnProfiler.section_begin("carbon_tax")
	_apply_carbon_tax(summary)
	TurnProfiler.section_end("carbon_tax")

	# Feed this turn's retained net profit + gross revenue to the loan facility so
	# borrowing capacity scales with the business. taxes_paid/dividends_paid are 0
	# when the turn was a loss, so retained then equals the (negative) pre-tax profit.
	var retained_profit: float = pre_tax_profit - summary.taxes_paid - summary.dividends_paid - profit_sharing
	LoanState.record_turn_economics(retained_profit, revenue)

	TurnProfiler.section_begin("cost_solve")
	# Attribute each tile's warehousing fee across the buildings that ran there, so
	# imputed unit costs carry storage overheads (owner rebalance 2026-07-09).
	if not _warehousing_by_tile.is_empty():
		var reports_per_tile: Dictionary = {}
		for r in _building_turn_reports:
			var rt := str(r.get("tile_id", ""))
			reports_per_tile[rt] = int(reports_per_tile.get(rt, 0)) + 1
		for r2 in _building_turn_reports:
			var rt2 := str(r2.get("tile_id", ""))
			var fee: float = float(_warehousing_by_tile.get(rt2, 0.0))
			r2["warehousing_cost"] = (fee / float(reports_per_tile[rt2])) if fee > 0.0 else 0.0
	CostSolver.solve(_building_turn_reports)
	TurnProfiler.section_end("cost_solve")

	TurnProfiler.section_begin("emit_summary")
	# Cheat-added cash this turn, surfaced as its own "fake money" category. Kept out
	# of money_in so it doesn't count toward advisor profit unlocks (it's a cheat).
	summary["fake_money"] = MatchState.fake_money_this_turn
	MatchState.fake_money_this_turn = 0.0
	last_turn_summary = summary
	_active_turn_summary = {}
	turn_processed.emit(summary)
	TurnProfiler.section_end("emit_summary")

	if _debug_logs_enabled():
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
		print("[Production] Cash breakdown: goods=£%.2f power_sold=£%.2f power_bought=£%.2f costs=£%.2f goods_bought=£%.2f interest=£%.2f tax=£%.2f div=£%.2f profit_share=£%.2f net=£%.2f" % [
			summary.goods_sales_revenue,
			summary.power_sales_revenue,
			summary.power_purchase_cost,
			summary.maintenance_paid + summary.labour_paid + summary.advisor_paid + summary.transport_paid + summary.warehousing_paid,
			summary.goods_purchased_cost,
			summary.interest_paid,
			summary.taxes_paid,
			summary.dividends_paid,
			summary.profit_sharing_paid,
			summary.money_in - summary.money_out
		])
		# Diagnostic: goods sitting in pending shipments (sales + moves). If a produced good
		# is neither stockpiled nor sold, it should show here as in-transit; if not, it's lost.
		var _in_transit_dbg: Dictionary = {}
		# Read-only summation — iterate the live list directly rather than paying for a
		# deep copy of every shipment (with its path/tiles arrays) just to tally quantities.
		for s in MatchState.pending_transport_shipments:
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

func _apply_advisor_costs(summary: Dictionary) -> float:
	var payroll := MatchState.advisor_payroll_per_turn()
	if payroll <= 0.0:
		summary.advisor_paid = 0.0
		return 0.0
	MatchState.add_money(-payroll)
	summary.advisor_paid = payroll
	summary.money_out += payroll
	return payroll

# Decarbonisation squeeze: charge the carbon levy on this turn's accrued taxed-good
# consumption (player buildings only, accumulated in _consume_inputs). Fills the
# per-building breakdown the Building Detail panel shows as last-turn actuals.
func _apply_carbon_tax(summary: Dictionary) -> void:
	carbon_tax_by_building.clear()
	var turn: int = int(TurnManager.current_turn)
	# Scale, not level: the levy ramps in across turns 91..100 before phase 1 lands.
	if PolicyState.co2_tax_scale(turn) <= 0.0:
		return
	var total: float = 0.0
	for iid in _carbon_consumed_by_building:
		var charge: float = 0.0
		var per: Dictionary = _carbon_consumed_by_building[iid]
		for gid in per:
			charge += PolicyState.carbon_charge(str(gid), int(per[gid]), turn)
		if charge > 0.0:
			carbon_tax_by_building[iid] = charge
			total += charge
	if total > 0.0:
		MatchState.add_money(-total)
		summary.carbon_tax_paid = total
		summary.money_out += total

func _apply_tax_and_dividends(summary: Dictionary) -> float:
	# Use actual pre-tax cashflow, not just sales minus a narrow operating-cost
	# subset. Market input buys are real expenses and must prevent loss-making turns
	# from paying tax or dividends.
	var pre_tax_profit := float(summary.get("money_in", 0.0)) - float(summary.get("money_out", 0.0))
	var taxable_profit := maxf(0.0, pre_tax_profit)
	var revenue := float(summary.get("goods_sales_revenue", 0.0)) + float(summary.get("power_sales_revenue", 0.0))
	var cfo := MatchState.cfo_seated()
	if taxable_profit <= 0.0:
		summary.taxes_paid = 0.0
		summary.dividends_paid = 0.0
		# CFO tax-loss carry-forward: age the existing credit windows, then bank a fresh
		# credit off this losing turn's revenue (banked after aging so it keeps 5 turns).
		MatchState.cfo_age_tax_credits()
		if cfo:
			summary["tax_credit_banked"] = MatchState.cfo_bank_tax_credit(revenue)
		return pre_tax_profit

	# A Government Affairs advisor can cut the tax rate via the "tax_rate" domain.
	var tax_mult: float = maxf(0.0, 1.0 + float(Modifiers.resolve_pct("tax_rate", "*", {}).get("net", 0.0)) / 100.0)
	var tax: float = minf(taxable_profit, taxable_profit * EconomyConfig.TAX_RATE * tax_mult)
	# CFO tax-loss carry-forward: spend banked credits to shave the bill, then tick the
	# windows down. The player sees this as a simply lower tax amount.
	if cfo:
		var credit_applied := MatchState.cfo_apply_tax_credit(tax)
		if credit_applied > 0.0:
			tax = maxf(0.0, tax - credit_applied)
			summary["tax_credit_applied"] = credit_applied
	MatchState.cfo_age_tax_credits()
	if tax > 0.0:
		MatchState.add_money(-tax)
		summary.taxes_paid = tax
		summary.money_out += tax

	var post_tax_profit := maxf(0.0, taxable_profit - tax)
	# A CFO advisor can grant a partial dividend holiday via the "dividend_rate" domain;
	# the Stock Options workforce policy adds to the base rate (both capped at 30% total).
	var div_mult: float = maxf(0.0, 1.0 + float(Modifiers.resolve_pct("dividend_rate", "*", {}).get("net", 0.0)) / 100.0)
	var div_rate: float = minf(0.30, EconomyConfig.DIVIDEND_RATE * div_mult + MatchState.workforce_dividend_bonus())
	var dividends: float = minf(post_tax_profit, post_tax_profit * div_rate)
	if dividends > 0.0:
		MatchState.add_money(-dividends)
		summary.dividends_paid = dividends
		summary.money_out += dividends
	return pre_tax_profit

func _apply_profit_sharing(summary: Dictionary, pre_tax_profit: float) -> float:
	summary.profit_sharing_paid = 0.0
	if not MatchState.is_workforce_policy_enabled(MatchState.WORKFORCE_POLICY_ANNUAL_PROFIT_SHARE):
		return 0.0
	var post_dividend_profit := maxf(
		0.0,
		pre_tax_profit - float(summary.get("taxes_paid", 0.0)) - float(summary.get("dividends_paid", 0.0))
	)
	if post_dividend_profit <= 0.0:
		return 0.0
	var profit_sharing := post_dividend_profit * 0.05
	MatchState.add_money(-profit_sharing)
	summary.profit_sharing_paid = profit_sharing
	summary.money_out += profit_sharing
	return profit_sharing

func _get_recipe(recipe_id: String) -> Dictionary:
	if recipe_id == "":
		return {}
	# ADAPT THIS to your Recipes accessor
	return Catalog.get_recipe(recipe_id)
	
	
func _produce_outputs(building: Dictionary, recipe: Dictionary, summary: Dictionary) -> void:
	# A recipe that mines a depletable deposit stops once that deposit is gone, and
	# what it mines this turn is subtracted from the deposit.
	var dep_token: String = _recipe_deposit_token(recipe)
	var tile_id: String = building.get("tile_id", "")
	if dep_token != "" and MatchState.deposit_depleted(tile_id, dep_token):
		return
	var mined := 0
	var recipe_id: String = str(recipe.get("recipe_id", ""))
	var recipe_type: String = str(recipe.get("recipe_type", "")).to_lower()
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

		# Modifier hook: advisor bonuses, "Mining Mastery" research, carbon-tax
		# productivity hits etc. all land here. With no active modifiers this is
		# one dict-emptiness check.
		# The deposit penalty + mining-yield research are recipe_output modifiers
		# matched by good_internal, so they land here too (no separate multiply).
		var mod_ctx := {
			"recipe_id": recipe_id,
			"recipe_type": recipe_type,
			"building_id": str(building.get("building_id", "")),
			"instance_id": str(building.get("instance_id", "")),
			"good_id": str(good.id),
			"good_internal": output_name,
		}
		output_qty = int(round(Modifiers.apply("recipe_output", recipe_id, float(output_qty), mod_ctx)))
		output_qty = int(round(float(output_qty) * BuildingLevels.mult("output", int(building.get("level", 1)))))
		output_qty = int(round(float(output_qty) * MatchState.workforce_output_multiplier()))
		output_qty = int(round(float(output_qty) * MatchState.startup_capacity_multiplier(building)))
		# Intermittency: derate output that relies on unfirmed intermittent green power
		# (0 for grey/steady/no-power buildings; set by _compute_power_intermittency).
		var power_derate: float = float((_intermittency_by_building.get(building.instance_id, {}) as Dictionary).get("derate", 0.0))
		if power_derate > 0.0:
			output_qty = int(round(float(output_qty) * (1.0 - power_derate)))
		if output_qty <= 0:
			continue

		if _debug_logs_enabled():
			print("[Production] Building %s produced %d %s" % [
				building.instance_id, output_qty, good.display_name
			])

		_dispatch_output_to_stockpile(building, good, output_qty, summary)
		summary.produced[good.id] = summary.produced.get(good.id, 0) + output_qty
		_record_building_output(building.instance_id, good.id, output_qty)
		mined += output_qty
	if dep_token != "" and mined > 0:
		MatchState.deplete_deposit(tile_id, dep_token, mined)

func _recipe_deposit_token(recipe: Dictionary) -> String:
	for req in recipe.get("requirements", []):
		if str(req.get("type", "")) == "deposit":
			return str(req.get("value", ""))
	return ""

func _process_transport_arrivals(summary: Dictionary) -> void:
	# Snapshot this turn's in-transit per-link flow (before shipments advance) so the
	# next turn's transport costs carry the right congestion penalty.
	MatchState.update_transport_congestion()
	# First, retry any shipments that arrived earlier at a then-full tile.
	MatchState.retry_overflow_unload()
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
			# Tile is full: hold the remainder instead of losing it. It waits on the
			# tile and retries each turn until there's room (see retry_overflow_unload).
			MatchState.hold_overflow_shipment({
				"source_tile": str(shipment.get("source_tile", "")),
				"destination_tile": destination_tile,
				"good_id": good_id,
				"qty": qty - added,
				"construction_instance_id": str(shipment.get("construction_instance_id", "")),
				"upgrade_instance_id": str(shipment.get("upgrade_instance_id", "")),
			})

func _credit_arrived_sale(shipment: Dictionary, summary: Dictionary) -> void:
	# A sale shipment reached its port this turn — pay out the locked-in revenue.
	var sale_record: Dictionary = shipment.get("sale_record", {})
	var special_order_id := str(shipment.get("special_order_id", ""))
	var paid_sale_record := {
		"tile_id": str(sale_record.get("tile_id", "")),
		"items": [],
		"total_qty": 0,
		"total_revenue": 0.0,
	}
	for item in sale_record.get("items", []):
		var gid := str(item.get("good_id", ""))
		var qty := int(item.get("qty", 0))
		var rev := float(item.get("revenue", 0.0))
		if special_order_id == "":
			if rev > 0.0:
				MatchState.add_money(rev)
				_add_summary_sale(summary, gid, qty, rev)
				_add_paid_sale_item(paid_sale_record, gid, qty, rev)
			continue

		var order_before := SpecialOrderState.get_order(special_order_id)
		var unit_revenue := rev / float(maxi(qty, 1))
		if order_before.is_empty():
			_offer_special_order_overflow(shipment, sale_record, gid, qty, unit_revenue)
			continue
		if str(order_before.get("good_id", "")) != gid:
			if rev > 0.0:
				MatchState.add_money(rev)
				_add_summary_sale(summary, gid, qty, rev)
				_add_paid_sale_item(paid_sale_record, gid, qty, rev)
			continue

		var remaining := maxi(0, int(order_before.get("qty_required", 0)) - int(order_before.get("qty_delivered", 0)))
		var paid_qty := mini(qty, remaining)
		var overflow_qty := maxi(0, qty - paid_qty)
		var paid_revenue := unit_revenue * float(paid_qty)
		if paid_revenue > 0.0:
			MatchState.add_money(paid_revenue)
			_add_summary_sale(summary, gid, paid_qty, paid_revenue)
			_add_paid_sale_item(paid_sale_record, gid, paid_qty, paid_revenue)
		var settlement := SpecialOrderState.settle_delivery(special_order_id, gid, qty, rev)
		var premium_bonus := float(settlement.get("premium_bonus", 0.0))
		if premium_bonus > 0.0:
			_add_summary_sale(summary, gid, 0, premium_bonus)
		if overflow_qty > 0:
			_offer_special_order_overflow(shipment, sale_record, gid, overflow_qty, unit_revenue)
	if float(paid_sale_record.get("total_revenue", 0.0)) > 0.0:
		MatchState.record_tile_sale(str(paid_sale_record.get("tile_id", "")), int(paid_sale_record.get("total_qty", 0)), float(paid_sale_record.get("total_revenue", 0.0)))
		MatchState.emit_stockpile_market_sale_completed(paid_sale_record)
		var port_tile := str(shipment.get("destination_tile", ""))
		if port_tile != "":
			MatchState.market_sale_arrived_at_port.emit(port_tile, float(paid_sale_record.get("total_revenue", 0.0)))

func _add_paid_sale_item(sale_record: Dictionary, good_id: String, qty: int, revenue: float) -> void:
	if good_id == "" or qty <= 0 or revenue <= 0.0:
		return
	sale_record.items.append({"good_id": good_id, "qty": qty, "revenue": revenue})
	sale_record.total_qty = int(sale_record.get("total_qty", 0)) + qty
	sale_record.total_revenue = float(sale_record.get("total_revenue", 0.0)) + revenue

func _offer_special_order_overflow(shipment: Dictionary, sale_record: Dictionary, good_id: String, qty: int, unit_revenue: float) -> void:
	if good_id == "" or qty <= 0:
		return
	MatchState.offer_special_order_overflow({
		"order_id": str(shipment.get("special_order_id", "")),
		"source_mode": str(shipment.get("special_order_source_mode", "")),
		"source_tile": str(sale_record.get("tile_id", shipment.get("source_tile", ""))),
		"port_tile": str(shipment.get("destination_tile", "")),
		"good_id": good_id,
		"good_display": Catalog.get_display_name(good_id),
		"qty": qty,
		"unit_revenue": unit_revenue,
		"total_revenue": unit_revenue * float(qty),
		"shipment_id": int(shipment.get("id", 0)),
	})

func _sell_output_to_market(building: Dictionary, good: Dictionary, qty: int, summary: Dictionary) -> void:
	# Output destined for the market goes through MarketState.execute_sale:
	#   - skip_consume: the goods never landed in the stockpile — they're being
	#     dispatched straight from production output,
	#   - pay_transport_from_seller: production absorbs the freight cost upfront
	#     (manual sells get a gross price; output-routed sales pay to deliver),
	#   - good_id_hint: enables type-aware port selection.
	# This function still owns Production's per-turn summary bookkeeping — that's
	# the part that's genuinely Production's concern, not the market's.
	var source_tile := str(building.get("tile_id", ""))
	var good_id := str(good.get("id", ""))
	var opts := {
		"skip_consume": true,
		"pay_transport_from_seller": true,
		"good_id_hint": good_id,
	}
	var special_order_id := MatchState.get_output_special_order_id(str(building.get("instance_id", "")), good_id)
	if special_order_id != "" and not SpecialOrderState.get_order(special_order_id).is_empty():
		opts["special_order_id"] = special_order_id
		opts["special_order_source_mode"] = "building_detail"
	var result := MarketState.execute_sale(source_tile, {good_id: qty}, opts)
	if result.is_empty():
		var stored := Stockpile.add(source_tile, good_id, qty)
		if stored < qty:
			push_warning("[Production] Could not route %s to market and stockpile stored %d/%d" % [
				Catalog.get_display_name(good_id), stored, qty,
			])
		return
	var transport_cost: float = float(result.get("transport_cost", 0.0))
	if transport_cost > 0.0:
		summary.transport_paid += transport_cost
		summary.money_out += transport_cost
	# Deferred sales credit the summary on arrival via _process_transport_arrivals;
	# immediate sales (no route, 0-turn) add to the summary here.
	if not bool(result.get("deferred", false)):
		for it in result.items:
			_add_summary_sale(summary, str(it.good_id), int(it.qty), float(it.revenue))

func _dispatch_output_to_stockpile(building: Dictionary, good: Dictionary, qty: int, summary: Dictionary) -> void:
	var stockpile_coord = _output_stockpile_coord(building, good.id)
	if stockpile_coord == null:
		# Market-bound output (no stockpile destination): sell it via the nearest port.
		_sell_output_to_market(building, good, qty, summary)
		return
	# Per-good shipping cap on an explicit OTHER-tile route (the CTRL+click "send a
	# specific amount every turn" flow): min(cap, produced) travels; the remainder
	# stays in the origin tile's stockpile and keeps accumulating there.
	var origin_tile := str(building.get("tile_id", ""))
	if str(stockpile_coord) != origin_tile:
		var cap := MatchState.get_output_ship_quantity(str(building.get("instance_id", "")), good.id)
		if cap > 0 and qty > cap:
			Stockpile.add(origin_tile, good.id, qty - cap)
			qty = cap
	var route := _transport_route(building.get("tile_id", ""), stockpile_coord, good.id)
	# Unreachable destination (e.g. a fluid with no pipe / reinforced-pipe network to
	# the target): do NOT attempt delivery and charge NOTHING — the output stays in
	# the source tile's stockpile until the player fixes the connection. The BDP
	# diagnostics call this out ("Outputs cannot reach destination…").
	if not TransportService.route_is_reachable(route):
		var kept := Stockpile.add(str(building.get("tile_id", "")), good.id, qty)
		if kept < qty:
			push_warning("[Production] %s output unroutable to %s and source stockpile kept %d/%d" % [
				Catalog.get_display_name(good.id), str(stockpile_coord), kept, qty,
			])
		return
	var transport_cost: float = TransportService.transport_cost_for_route(good.id, qty, route)
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
	# instance_id feeds the JIT-unlock streak (distinct producers filling one tile).
	_output_buffer.append({
		"coord": stockpile_coord,
		"good_id": good.id,
		"qty": qty,
		"transport_cost": transport_cost,
		"instance_id": str(building.get("instance_id", "")),
	})

func _flush_output_buffer() -> void:
	_same_tile_supply.clear()
	_jit_fed_this_turn.clear()
	var committed_cache: Dictionary = {}   # tile_id -> {good_id -> per-turn player need}
	# JIT spill-back: feed held for a consumer that no longer wants it (demolished,
	# paused, retooled) — or beyond one turn of committed demand — returns to the
	# warehouse before this turn's outputs are routed. Runs even without the unlock
	# so a loaded buffer can always drain.
	if not _direct_feed.is_empty():
		for ft in _direct_feed.keys().duplicate():
			var f_committed: Dictionary = _player_committed_for_tile(str(ft))
			committed_cache[str(ft)] = f_committed
			var feed_tile: Dictionary = _direct_feed[ft]
			for fg in feed_tile.keys().duplicate():
				var keep: int = int(f_committed.get(fg, 0))
				var excess: int = int(feed_tile[fg]) - keep
				if excess <= 0:
					continue
				var spilled: int = Stockpile.add(str(ft), str(fg), excess)
				if spilled < excess:
					# Warehouse full too — hold the remainder like any bounced arrival.
					MatchState.hold_overflow_shipment({
						"source_tile": str(ft), "destination_tile": str(ft),
						"good_id": str(fg), "qty": excess - spilled,
					})
				if keep > 0:
					feed_tile[fg] = keep
				else:
					feed_tile.erase(fg)
			if feed_tile.is_empty():
				_direct_feed.erase(ft)
	var jit_active := MatchState.is_unlocked(JIT_UNLOCK_TITLE)
	var producers_by_tile: Dictionary = {}   # tile_id -> {instance_id: true}
	for o in _output_buffer:
		var qty: int = int(o.qty)
		var to_store: int = qty
		var t := str(o.coord) if o.coord != null else ""
		if jit_active and t != "":
			# Route what co-located player buildings will consume next turn straight
			# into the feed; only the surplus takes up warehouse space.
			if not committed_cache.has(t):
				committed_cache[t] = _player_committed_for_tile(t)
			var g := str(o.good_id)
			var room: int = maxi(0, int((committed_cache[t] as Dictionary).get(g, 0)) - _feed_available(t, g))
			var fed: int = mini(qty, room)
			if fed > 0:
				var feed_per_tile: Dictionary = _direct_feed.get(t, {})
				feed_per_tile[g] = int(feed_per_tile.get(g, 0)) + fed
				_direct_feed[t] = feed_per_tile
				_jit_fed_this_turn[t] = int(_jit_fed_this_turn.get(t, 0)) + fed
				to_store = qty - fed
		var added: int = Stockpile.add(o.coord, str(o.good_id), to_store) if to_store > 0 else 0
		if t != "":
			var per_unit: float = (float(o.transport_cost) / float(o.qty)) if int(o.qty) > 0 else 0.0
			_record_inbound_delivery(t, str(o.good_id), added + (qty - to_store), per_unit)
			# tally this turn's recurring same-tile supply (fed direct or stockpiled —
			# both cover local demand) so the market pipeline doesn't re-buy it
			var per_tile: Dictionary = _same_tile_supply.get(t, {})
			per_tile[str(o.good_id)] = int(per_tile.get(str(o.good_id), 0)) + qty
			_same_tile_supply[t] = per_tile
			# JIT-unlock streak input: which buildings filled this tile's stores.
			var prods: Dictionary = producers_by_tile.get(t, {})
			prods[str(o.get("instance_id", ""))] = true
			producers_by_tile[t] = prods
		if added < to_store:
			push_warning("[Production] Stockpile full for %s; stored %d/%d %s" % [
				str(o.coord), added, to_store, Catalog.get_display_name(str(o.good_id)),
			])
	_output_buffer.clear()
	# "Stockpile filled by 7+ buildings for 5 turns" — advance/reset per-tile streaks.
	var fed_counts: Dictionary = {}
	for pt in producers_by_tile:
		fed_counts[pt] = (producers_by_tile[pt] as Dictionary).size()
	MatchState.update_stockpile_feed_streaks(fed_counts)

## One turn of the PLAYER's buildings' recipe inputs on a tile — the JIT feed target.
## (compute_committed_for_tile counts NPC buildings too; the feed must not.)
func _player_committed_for_tile(tile_id: String) -> Dictionary:
	var committed: Dictionary = {}
	for building in MatchState.get_buildings_on_tile(tile_id):
		if not MatchState.is_player_owned(building) or MatchState.is_building_paused(str(building.get("instance_id", ""))):
			continue
		var recipe: Dictionary = Catalog.get_recipe(building.get("recipe_id", ""))
		for input in recipe.get("inputs", []):
			var good_id: String = input.get("good_id", "")
			var qty: int = _scaled_input_qty(input, building)
			if good_id != "" and qty > 0:
				committed[good_id] = int(committed.get(good_id, 0)) + qty
	return committed

func _feed_available(tile_id: String, good_id: String) -> int:
	return int((_direct_feed.get(tile_id, {}) as Dictionary).get(good_id, 0))

## Draw from the JIT feed; returns what it covered (callers take the rest from Stockpile).
func _feed_consume(tile_id: String, good_id: String, qty: int) -> int:
	var feed_tile: Dictionary = _direct_feed.get(tile_id, {})
	var have: int = int(feed_tile.get(good_id, 0))
	var taken: int = mini(have, qty)
	if taken > 0:
		if have - taken > 0:
			feed_tile[good_id] = have - taken
		else:
			feed_tile.erase(good_id)
		if feed_tile.is_empty():
			_direct_feed.erase(tile_id)
		else:
			_direct_feed[tile_id] = feed_tile
	return taken

## Stockpile-tab readout: units routed building-to-building this turn (0 = no JIT).
func get_jit_fed_for_tile(tile_id: String) -> int:
	return int(_jit_fed_this_turn.get(tile_id, 0))

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
	return TransportService.route(source_tile, destination_tile, good_id)

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
	var covered_goods: Dictionary = {}
	for gid in totals.keys():
		if int(totals[gid]) > 0:
			covered_goods[str(gid)] = MatchState.seaport_covers(str(gid))
	var quote := TransportService.quote_market_sell(source_tile, totals, covered_goods)
	if quote.is_empty():
		return sale_record
	var port_tile := str(quote.get("port", ""))
	var route: Dictionary = quote.get("route", {})
	# Seaport subscription: a port only services tiles within SEAPORT_RANGE_TILES. If in
	# range AND every good sold here is covered, the port ships any volume in 1 turn for
	# the flat per-turn fee (charged once per turn), with no per-unit cost.
	var in_port_range: bool = port_tile != "" and TransportService.tile_distance(source_tile, port_tile) <= EconomyConfig.SEAPORT_RANGE_TILES
	var ship_turns: int = int(quote.get("turns", 0))
	var deferred: bool = port_tile != "" and ship_turns >= 1
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
		MarketState.record_market_sale_volume(good_key, sold_qty)
		var sold_revenue: float = float(sold_qty) * price
		if not (in_port_range and bool(covered_goods.get(good_key, false))):
			transport_cost += TransportService.transport_cost_for_route(good_key, sold_qty, route)
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
			"transport_turns": ship_turns,
			"turns_remaining": ship_turns,
			"path": route.get("path", []),
			"legs": route.get("legs", []),
			"tiles": route.get("tiles", []),
		})
	elif emit_toast and float(sale_record.total_revenue) > 0.0:
		MatchState.emit_stockpile_market_sale_completed(sale_record)
	# Victory feed: this bulk / auto-sell / queued-stockpile market sale is one goods
	# movement for the Logistics track. The production-OUTPUT sell path emits
	# separately (via MarketState.execute_sale), so the two never double-count.
	if int(sale_record.total_qty) > 0:
		MatchState.goods_movement_recorded.emit("sale", "", ship_turns)
	return sale_record

func _add_summary_sale(summary: Dictionary, good_id: String, qty: int, revenue: float) -> void:
	if not summary.has("sold"):
		summary["sold"] = {}
	var sold: Dictionary = summary.get("sold", {})
	var existing: Dictionary = sold.get(good_id, {"qty": 0, "revenue": 0.0})
	existing.qty = int(existing.get("qty", 0)) + qty
	existing.revenue = float(existing.get("revenue", 0.0)) + revenue
	sold[good_id] = existing
	summary["sold"] = sold
	summary["goods_sales_revenue"] = float(summary.get("goods_sales_revenue", 0.0)) + revenue
	summary["money_in"] = float(summary.get("money_in", 0.0)) + revenue

func record_external_goods_sale(sale_record: Dictionary) -> void:
	if sale_record.is_empty():
		return
	if not _active_turn_summary.is_empty():
		_apply_sale_record_to_summary(_active_turn_summary, sale_record)
		return
	_pending_external_sales.append(sale_record.duplicate(true))
	if not last_turn_summary.is_empty() and _apply_sale_record_to_summary(last_turn_summary, sale_record):
		turn_processed.emit(last_turn_summary)

func _merge_pending_external_sales(summary: Dictionary) -> void:
	if _pending_external_sales.is_empty():
		return
	for sale_record in _pending_external_sales:
		_apply_sale_record_to_summary(summary, sale_record)
	_pending_external_sales.clear()

func _apply_sale_record_to_summary(summary: Dictionary, sale_record: Dictionary) -> bool:
	if summary.is_empty() or sale_record.is_empty():
		return false
	var changed := false
	for item in sale_record.get("items", []):
		var gid := str(item.get("good_id", ""))
		var qty := int(item.get("qty", 0))
		var revenue := float(item.get("revenue", 0.0))
		if gid == "" or (qty <= 0 and revenue <= 0.0):
			continue
		_add_summary_sale(summary, gid, qty, revenue)
		changed = true
	return changed

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

## Lifetime units of a good produced across all buildings — feeds the "Produce N
## units of X" research conditions. Material outputs record under the good_id;
## generated power records under its internal name. Accept either catalog form
## and total both possible ledger keys without double-counting identical keys.
func lifetime_total(good: String) -> int:
	var g: Dictionary = Catalog.get_good(good)
	if g.is_empty():
		g = Catalog.get_good_by_internal_name(good)
	var gid := str(g.get("id", good))
	var internal := str(g.get("internal_name", good))
	var total: int = 0
	for inst_id in produced_by_building:
		var ledger: Dictionary = produced_by_building[inst_id] as Dictionary
		total += int(ledger.get(gid, 0))
		if internal != gid:
			total += int(ledger.get(internal, 0))
	return total

func reset_lifetime_research_metrics() -> void:
	produced_by_building.clear()
	full_output_streak_by_building.clear()

func _capture_turn_report(building: Dictionary, recipe: Dictionary) -> void:
	# A levelled building consumes/produces scaled quantities (see _consume_inputs /
	# _produce_outputs). The cost report MUST scale them the same way, or CostSolver divides
	# the levelled power/labour/maintenance by the un-scaled output and reports an inflated
	# unit cost after an upgrade.
	var lvl := int(building.get("level", 1))
	var imul := BuildingLevels.mult("input", lvl)
	var omul := BuildingLevels.mult("output", lvl)
	var startup_mult := MatchState.startup_capacity_multiplier(building)

	# Build inputs_consumed {good_id: qty} from recipe inputs
	var inputs_consumed: Dictionary = {}
	for input in recipe.get("inputs", []):
		var gid: String = input.get("good_id", "")
		if gid != "":
			var scaled_input := float(input.get("qty", 0)) * imul * startup_mult
			inputs_consumed[gid] = int(ceil(scaled_input)) if startup_mult < 1.0 and scaled_input > 0.0 else int(round(scaled_input))

	# Build outputs_produced {good_id: qty}. Scale each output the SAME way _produce_outputs
	# does — recipe_output modifiers (the "Δ +%" shown on the recipe) × level output mult ×
	# workforce multiplier — so CostSolver divides the run's fixed costs by what the building
	# actually makes, not the un-modified recipe base. (Intermittency derate is excluded, as
	# before: the cost basis reflects structural efficiency, not per-turn power weather.)
	var recipe_id: String = str(recipe.get("recipe_id", ""))
	var recipe_type: String = str(recipe.get("recipe_type", "")).to_lower()
	var out_bid: String = str(building.get("building_id", ""))
	var workforce_out_mult: float = MatchState.workforce_output_multiplier()
	var outputs_produced: Dictionary = {}
	for output in _recipe_output_items(recipe):
		var gid: String = output.get("good_id", "")
		if gid == "":
			continue
		var mod_ctx := {
			"recipe_id": recipe_id,
			"recipe_type": recipe_type,
			"building_id": out_bid,
			"instance_id": str(building.get("instance_id", "")),
			"good_id": gid,
			"good_internal": str(output.get("internal_name", "")),
		}
		var qty: int = int(round(Modifiers.apply("recipe_output", recipe_id, float(output.get("qty", 0)), mod_ctx)))
		qty = int(round(float(qty) * omul))
		qty = int(round(float(qty) * workforce_out_mult * startup_mult))
		if qty > 0:
			outputs_produced[gid] = qty

	if outputs_produced.is_empty():
		return  # nothing to track (e.g. power recipe fell through)

	var energy_req: int    = _effective_energy_req(building, recipe)
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
		"labour_cost":      _calculate_labour_cost(building, recipe),
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

func _calculate_labour_cost(building: Dictionary, recipe: Dictionary = {}) -> float:
	# While retooling, a building pays only a reduced fraction of its base labour and
	# skips the usual modifier factor (spec §7.3).
	var instance_id: String = str(building.get("instance_id", ""))
	if MatchState.is_retooling(instance_id):
		return _base_labour_cost(building, recipe) * MatchState.retooling_labour_fraction(instance_id)
	return _base_labour_cost(building, recipe) * labour_cost_factor(building)

# Raw per-turn staffing cost for a building BEFORE any percentage labour modifiers:
# grown wage rates x headcount x the level labour multiplier. This is the "100% base"
# that every discount/surcharge is measured against.
func _base_labour_cost(building: Dictionary, recipe: Dictionary = {}) -> float:
	var bdata: Dictionary = Catalog.get_building(building.get("building_id", ""))
	var rdata: Dictionary = recipe if not recipe.is_empty() else Catalog.get_recipe(str(building.get("recipe_id", "")))
	var recipe_unskilled: int = int(rdata.get("labour_unskilled_required", -1))
	var recipe_skilled: int = int(rdata.get("labour_skilled_required", -1))
	var recipe_high_skilled: int = int(rdata.get("labour_h_skilled_required", -1))
	var unskilled: int = recipe_unskilled if recipe_unskilled >= 0 else int(bdata.get("labour_unskilled_required", EconomyConfig.STUB_UNSKILLED_PER_BUILDING))
	var skilled: int = recipe_skilled if recipe_skilled >= 0 else int(bdata.get("labour_skilled_required", EconomyConfig.STUB_SKILLED_PER_BUILDING))
	var high_skilled: int = recipe_high_skilled if recipe_high_skilled >= 0 else int(bdata.get("labour_h_skilled_required", EconomyConfig.STUB_HIGH_SKILLED_PER_BUILDING))
	# Wage rates compound every turn (EconomyConfig.LABOUR_*_GROWTH), so the same
	# building costs more to staff as the game goes on.
	var base_cost: float = (
		unskilled    * _grown_labour_rate(EconomyConfig.LABOUR_UNSKILLED_RATE, EconomyConfig.LABOUR_UNSKILLED_GROWTH)
		+ skilled    * _grown_labour_rate(EconomyConfig.LABOUR_SKILLED_RATE, EconomyConfig.LABOUR_SKILLED_GROWTH)
		+ high_skilled * _grown_labour_rate(EconomyConfig.LABOUR_HIGH_SKILLED_RATE, EconomyConfig.LABOUR_HIGH_SKILLED_GROWTH)
	)
	return base_cost * BuildingLevels.mult("labour", int(building.get("level", 1)))

# Every percentage labour modifier applies ADDITIVELY to the 100% base — they no
# longer compound. Research head-count trims (e.g. Lights-Out Automation, the
# people-management unlocks), the labour slider, and workforce policies all sum as
# deltas off 1.0, clamped so labour never goes negative. `policy_delta_override`
# lets the Labour panel reuse this with a projected workforce delta.
func labour_cost_factor(building: Dictionary, policy_delta_override: float = INF) -> float:
	var bid: String = str(building.get("building_id", ""))
	var headcount_delta: float = float(Modifiers.resolve_pct("labour_headcount", bid, {"building_id": bid, "instance_id": str(building.get("instance_id", ""))}).get("net", 0.0)) / 100.0
	var slider_delta: float = MatchState.labour_multiplier - 1.0
	var policy_delta: float = MatchState.workforce_labour_cost_delta() if is_inf(policy_delta_override) else policy_delta_override
	return maxf(EconomyConfig.LABOUR_FACTOR_MIN, 1.0 + headcount_delta + slider_delta + policy_delta)

# Aggregate labour snapshot for the People panel's Labour indicator: current £/turn,
# the effective % of base, the next-turn direction (from workforce-policy accrual),
# and the 10-turn estimate. Buildings are held constant; only the workforce-policy
# labour delta is projected forward.
func labour_overview() -> Dictionary:
	var base_total := 0.0
	var current := 0.0
	var next_turn := 0.0
	var est_ten := 0.0
	var at_floor := false
	var slider_delta: float = MatchState.labour_multiplier - 1.0
	var policy_now: float = MatchState.workforce_labour_cost_delta()
	var policy_next: float = MatchState.projected_workforce_labour_delta(1)
	var policy_ten: float = MatchState.projected_workforce_labour_delta(10)
	for building in MatchState.buildings.values():
		if not MatchState.is_player_owned(building):
			continue
		var active_recipe: Dictionary = Catalog.get_recipe(str(building.get("recipe_id", "")))
		var b_base: float = _base_labour_cost(building, active_recipe)
		if b_base <= 0.0:
			continue
		var bid: String = str(building.get("building_id", ""))
		var hc: float = float(Modifiers.resolve_pct("labour_headcount", bid, {"building_id": bid}).get("net", 0.0)) / 100.0
		var floor_min: float = EconomyConfig.LABOUR_FACTOR_MIN
		var raw_now: float = 1.0 + hc + slider_delta + policy_now
		if raw_now <= floor_min + 0.000001:
			at_floor = true
		base_total += b_base
		current   += b_base * maxf(floor_min, raw_now)
		next_turn += b_base * maxf(floor_min, 1.0 + hc + slider_delta + policy_next)
		est_ten   += b_base * maxf(floor_min, 1.0 + hc + slider_delta + policy_ten)
	var factor_pct: float = (current / base_total * 100.0) if base_total > 0.0 else 100.0
	return {
		"base": base_total,
		"current": current,
		"next_turn": next_turn,
		"est_10_turns": est_ten,
		"factor_pct": factor_pct,
		"has_buildings": base_total > 0.0,
		"at_floor": at_floor,
	}

func _grown_labour_rate(base_rate: float, growth: float) -> float:
	# Compounded wage at the current turn: base * (1 + growth) ^ (turn - 1).
	# Turn 1 pays the base rate; growth accrues from turn 2 onward.
	var t: int = maxi(0, int(TurnManager.current_turn) - 1)
	return base_rate * pow(1.0 + growth, float(t))

func _calculate_maintenance_cost(building: Dictionary) -> float:
	var bdata: Dictionary = Catalog.get_building(building.get("building_id", ""))
	var maint = bdata.get("maintenance_cost", null)
	var maint_val: float = EconomyConfig.MAINTENANCE_PER_BUILDING if maint == null else float(maint)
	# Maintenance modifiers (e.g. Combined Heat & Power thermal-battery retrofit).
	var bid: String = str(building.get("building_id", ""))
	var maint_cost := Modifiers.apply("maintenance", bid, maint_val, {"building_id": bid, "instance_id": str(building.get("instance_id", ""))})
	# Empire-wide workforce penalty (Lax Safety neglect ramps upkeep up to +100%).
	maint_cost *= MatchState.workforce_maintenance_multiplier()
	return maint_cost * BuildingLevels.mult("maint", int(building.get("level", 1)))

# Power-consumption modifiers (Pulverised Carbon Injection, Scrap Preheating,
# Energy-Recovery Devices) shrink the energy a building actually draws — applied
# once here so grid demand and the £ power cost stay in lock-step.
func _effective_energy_req(building: Dictionary, recipe: Dictionary) -> int:
	var energy_req: int = recipe.get("energy_req", 0)
	if energy_req <= 0:
		return energy_req
	var bid: String = str(building.get("building_id", ""))
	var eff := Modifiers.apply("building_power", bid, float(energy_req), {"building_id": bid})
	var capacity_mult := MatchState.startup_capacity_multiplier(building)
	var scaled := eff * BuildingLevels.mult("energy", int(building.get("level", 1))) * capacity_mult
	return int(ceil(scaled)) if capacity_mult < 1.0 and scaled > 0.0 else int(round(scaled))

# Power generation after recipe_output modifiers (e.g. Pulverised Coal Boilers +5%,
# Hydro Intake Design +10%). Power takes its own production branch that bypasses
# _produce_outputs, so the modifier is applied here — used for BOTH the cable-cap
# gate and the recorded supply so they always agree.
func _effective_power_output(building: Dictionary, recipe: Dictionary) -> int:
	var output_qty: int = recipe.get("output_qty", 0)
	if output_qty <= 0:
		return output_qty
	var rid := str(recipe.get("recipe_id", ""))
	var mod_ctx := {
		"recipe_id": rid,
		"recipe_type": str(recipe.get("recipe_type", "")).to_lower(),
		"building_id": str(building.get("building_id", "")),
		"good_id": "power",
		"good_internal": "power",
	}
	var eff := Modifiers.apply("recipe_output", rid, float(output_qty), mod_ctx)
	return int(round(eff * BuildingLevels.mult("output", int(building.get("level", 1))) * MatchState.workforce_output_multiplier() * MatchState.startup_capacity_multiplier(building)))

## Per-turn stat snapshot for a building instance evaluated AS IF it were `level`. Used by the
## upgrade dialog to show cur→new (energy / labour / maintenance / size / inputs / outputs) using
## the very same formulas the engine runs, so the preview numbers match live production exactly.
## Energy / labour / maintenance are kept as FLOATS (the panel allows non-integer costs); inputs,
## outputs and tile size remain whole units. Returns
## {energy:float, labour:float, maintenance:float, size:float, inputs:[{name,good_id,qty}], outputs:[{name,good_id,qty}]}.
func stats_at_level(instance_id: String, level: int) -> Dictionary:
	var inst: Dictionary = MatchState.buildings.get(instance_id, {})
	if inst.is_empty():
		return {}
	# A throwaway copy at the hypothetical level — the private cost/output helpers read building.level.
	var b: Dictionary = inst.duplicate(true)
	b["level"] = level
	var recipe: Dictionary = Catalog.get_recipe(str(b.get("recipe_id", "")))
	var bdata: Dictionary = Catalog.get_building(str(b.get("building_id", "")))
	var out: Dictionary = {
		"energy": _effective_energy_req_f(b, recipe),  # FLOAT (the grid still draws the int version)
		"labour": _calculate_labour_cost(b, recipe),
		"maintenance": _calculate_maintenance_cost(b),
		"size": float(bdata.get("tile_size_used", 1.0)) * BuildingLevels.mult("size", level),
		"inputs": [],
		"outputs": [],
	}
	var imul := BuildingLevels.mult("input", level) * MatchState.startup_capacity_multiplier(b)
	for input in recipe.get("inputs", []):
		out.inputs.append({
			"good_id": str(input.get("good_id", "")),
			"name": Catalog.get_display_name(str(input.get("good_id", ""))),
			"qty": int(round(float(input.get("qty", 0)) * imul)),
		})
	# Outputs: power takes its own branch; everything else mirrors _produce_outputs (modifier + level).
	if str(recipe.get("output_name", "")) == "power":
		out.outputs.append({"name": "Power", "good_id": "power", "qty": _effective_power_output(b, recipe)})
	else:
		var omul := BuildingLevels.mult("output", level) * MatchState.startup_capacity_multiplier(b)
		var rid := str(recipe.get("recipe_id", ""))
		for output in _recipe_output_items(recipe):
			var oname := str(output.get("internal_name", ""))
			var good: Dictionary = Catalog.get_good_by_internal_name(oname)
			if good.is_empty():
				continue
			var ctx := {
				"recipe_id": rid, "recipe_type": str(recipe.get("recipe_type", "")).to_lower(),
				"building_id": str(b.get("building_id", "")), "instance_id": str(b.get("instance_id", "")),
				"good_id": str(good.id), "good_internal": oname,
			}
			var q := int(round(Modifiers.apply("recipe_output", rid, float(output.get("qty", 0)), ctx)))
			out.outputs.append({"name": str(good.get("display_name", oname)), "good_id": str(good.id), "qty": int(round(float(q) * omul * MatchState.workforce_output_multiplier()))})
	return out

# Float energy draw (no whole-unit rounding) — for the upgrade panel's cost rows. The live grid
# still uses the integer _effective_energy_req; this just lets the panel show the true value.
func _effective_energy_req_f(building: Dictionary, recipe: Dictionary) -> float:
	var energy_req: int = recipe.get("energy_req", 0)
	if energy_req <= 0:
		return float(energy_req)
	var bid: String = str(building.get("building_id", ""))
	var eff := Modifiers.apply("building_power", bid, float(energy_req), {"building_id": bid})
	return eff * BuildingLevels.mult("energy", int(building.get("level", 1))) * MatchState.startup_capacity_multiplier(building)

# ── Power intermittency (green/grey quality flags layered on top of `power`) ────

# Classify a power-producing building's output quality: "green_intermittent" (solar/wind),
# "green_steady" (hydro, or a generic power_plant burning biomass/waste), else "grey" (firm).
func _power_quality(building: Dictionary, recipe: Dictionary) -> String:
	var internal := str(Catalog.get_building(str(building.get("building_id", ""))).get("internal_name", ""))
	if internal in EconomyConfig.POWER_INTERMITTENT_BUILDINGS:
		return "green_intermittent"
	if internal in EconomyConfig.POWER_STEADY_BUILDINGS:
		return "green_steady"
	for inp in recipe.get("inputs", []):
		if str(inp.get("internal_name", "")) in EconomyConfig.POWER_STEADY_FUELS:
			return "green_steady"
	return "grey"

# A tile's abstracted firming capacity = sum of its player battery buildings' caps by level.
func _tile_storage_cap(tile_id: String) -> int:
	# Deposit model: firming comes from the battery CELLS loaded into the tile's housing, not
	# the housing alone (docs/battery-storage-spec.md). MatchState owns the slot + cell math.
	return MatchState.tile_firming_cap(tile_id)

# Last turn's profit margin for a consumer, snapped to 2dp (deterministic tiebreak):
# (price - unit_cost) * output_qty from the previous CostSolver solve. 0.0 when unsolved
# (turn 1 / post-load) — those fall through to the instance-age tiebreak.
func _consumer_profit_key(iid: String) -> float:
	var bd: Dictionary = CostSolver.last_result.get("per_building", {}).get(iid, {})
	if bd.is_empty():
		return 0.0
	var gid := str(bd.get("output_good_id", ""))
	if gid == "":
		return 0.0
	var price := float(MarketState.get_price(gid))
	if price <= 0.0:
		price = float(Catalog.get_base_price(gid))
	return snappedf((price - float(bd.get("unit_cost", 0.0))) * float(bd.get("output_qty", 0)), 0.01)

# Instance creation order from "inst_<building_id>_<hex>" — lower = older (highest priority).
func _instance_age(iid: String) -> int:
	var parts := iid.split("_")
	if parts.is_empty():
		return 0
	return parts[parts.size() - 1].hex_to_int()

# Post-cascade: recompute the per-building intermittency derate from THIS turn's actuals —
# the buildings that actually RAN (last_turn_run) and the green actually generated per tile
# (_green_supply_by_tile, already cable-capped). Stored for NEXT turn (read in _produce_outputs).
# Using actuals (not a pre-cascade estimate) avoids phantom/starved consumers soaking up green
# and avoids over-counting green on tiles whose plants exceed the cable export cap.
func _compute_power_intermittency() -> void:
	var green_sources := {}  # tile -> {"int": units, "steady": units}
	for tile in _green_supply_by_tile.keys():
		green_sources[tile] = (_green_supply_by_tile[tile] as Dictionary).duplicate()
	var consumers := []
	for iid in last_turn_run.keys():
		var b: Dictionary = MatchState.buildings.get(iid, {})
		if b.is_empty():
			continue
		var recipe: Dictionary = Catalog.get_recipe(str(b.get("recipe_id", "")))
		if str(recipe.get("output_name", "")) == "power":
			continue
		var demand := _effective_energy_req(b, recipe)
		if demand <= 0:
			continue
		consumers.append({
			"iid": str(iid), "tile": str(b.get("tile_id", "")), "demand": float(demand),
			"building_id": str(b.get("building_id", "")),
			"level": int(b.get("level", 1)), "profit": _consumer_profit_key(str(iid)),
			"age": _instance_age(str(iid)),
		})
	var tile_caps := {}
	for tile in green_sources.keys():
		tile_caps[tile] = _tile_storage_cap(tile)
	for cons in consumers:
		var ct := str(cons["tile"])
		if not tile_caps.has(ct):
			tile_caps[ct] = _tile_storage_cap(ct)
	_intermittency_by_building = _allocate_power_derates(green_sources, consumers, tile_caps)
	_intermittency_by_tile = _aggregate_tile_intermittency(consumers)

# Pure allocator (deep-copies its inputs; hex distance is string arithmetic — no scene deps).
# Firms intermittent green per tile, pushes each source's green to consumers nearest-first by
# priority (proportional int/steady mix), firms the received intermittent per consuming tile
# (highest-priority consumer first), and returns, for each consumer that drew any green,
# {iid -> {derate, green_consumed, unfirmed_intermittent, steady_consumed, demand}}.
# green_sources: tile -> {int, steady}. consumers: {iid, tile, demand, level, profit, age}.
# tile_caps: tile -> firming capacity.
func _allocate_power_derates(green_sources: Dictionary, consumers: Array, tile_caps: Dictionary) -> Dictionary:
	if consumers.is_empty():
		return {}
	var sources: Dictionary = green_sources.duplicate(true)  # don't mutate the caller's dicts
	var cap_left := {}  # tile -> remaining firming cap (float, for fractional consumer firming)
	for t in tile_caps.keys():
		cap_left[t] = float(tile_caps[t])
	# Producer-side firming: intermittent -> steady, up to the tile's cap (green is integer).
	for tile in sources.keys():
		var e: Dictionary = sources[tile]
		var firm: int = mini(int(cap_left.get(tile, 0.0)), int(e["int"]))
		if firm > 0:
			e["int"] = int(e["int"]) - firm
			e["steady"] = int(e["steady"]) + firm
			cap_left[tile] = float(cap_left[tile]) - float(firm)
	# Per-consumer running totals of green / intermittent received.
	var recv := {}
	for cons in consumers:
		recv[str(cons["iid"])] = {"green": 0.0, "int": 0.0}
	# Push each source's green to consumers nearest-first, then L3>L2>L1, then most
	# profitable (2dp), then oldest. Sources in stable tile order for determinism.
	var src_tiles: Array = sources.keys()
	src_tiles.sort()
	for src in src_tiles:
		var e: Dictionary = sources[src]
		var i_pool := float(e["int"])
		var s_pool := float(e["steady"])
		if i_pool + s_pool <= 0.0:
			continue
		var order: Array = consumers.duplicate()
		order.sort_custom(func(a, c): return _consumer_less(src, a, c))
		for cons in order:
			var g_left := i_pool + s_pool
			if g_left <= 0.0:
				break
			var r: Dictionary = recv[str(cons["iid"])]
			var room := float(cons["demand"]) - float(r["green"])
			if room <= 0.0:
				continue
			var give: float = minf(room, g_left)
			var int_give: float = give * (i_pool / g_left)
			r["green"] = float(r["green"]) + give
			r["int"] = float(r["int"]) + int_give
			i_pool -= int_give
			s_pool -= (give - int_give)
	# Consumer-side firming + final derate, in priority order so the highest-priority
	# same-tile consumer escapes the derate first when storage is scarce.
	var firm_order: Array = consumers.duplicate()
	firm_order.sort_custom(_firming_less)
	var result := {}
	for cons in firm_order:
		var iid := str(cons["iid"])
		var green: float = float(recv[iid]["green"])
		if green <= 0.0:
			continue  # drew no green at all — not relevant to intermittency or the filters
		var unfirmed: float = float(recv[iid]["int"])
		var tile := str(cons["tile"])
		var cap := float(cap_left.get(tile, 0.0))
		if cap > 0.0 and unfirmed > 0.0:
			var firm := minf(cap, unfirmed)
			unfirmed -= firm
			cap_left[tile] = cap - firm  # exact decrement (no ceil over-charge)
		var demand: float = float(cons["demand"])
		var derate: float = 0.0
		if demand > 0.0:
			derate = EconomyConfig.INTERMITTENCY_DERATE * clampf(unfirmed / demand, 0.0, 1.0)
		result[iid] = {
			"derate": derate,
			"green_consumed": green,
			"unfirmed_intermittent": unfirmed,
			"steady_consumed": green - unfirmed,
			"demand": demand,
		}
	return result

# Consumer ordering for a source tile: nearest, then the tile-agnostic priority below.
func _consumer_less(src: String, a: Dictionary, c: Dictionary) -> bool:
	var da := Catalog.tile_hex_distance(src, str(a["tile"]))
	var dc := Catalog.tile_hex_distance(src, str(c["tile"]))
	if da != dc:
		return da < dc
	return _firming_less(a, c)

# Tile-agnostic priority: highest level, then most profitable (exact compare on the
# 2dp-snapped value), then oldest instance — a total order (age is unique per building).
func _firming_less(a: Dictionary, c: Dictionary) -> bool:
	if int(a["level"]) != int(c["level"]):
		return int(a["level"]) > int(c["level"])
	if float(a["profit"]) != float(c["profit"]):
		return float(a["profit"]) > float(c["profit"])
	return int(a["age"]) < int(c["age"])

# Roll the per-building result up per tile for the tile-view Power section: green produced
# (and the intermittent share), total produced (from the cascade), green/total consumed,
# unfirmed-intermittent consumed, battery cap, and the list of affected buildings.
func _aggregate_tile_intermittency(consumers: Array) -> Dictionary:
	var by_tile := {}
	# Seed every producing tile with its green generation + total produced this turn.
	for tile in _green_supply_by_tile.keys():
		var e: Dictionary = _green_supply_by_tile[tile]
		var t: Dictionary = _new_tile_intermittency(str(tile))
		t["green_intermittent_produced"] = int(e.get("int", 0))
		t["green_produced"] = int(e.get("int", 0)) + int(e.get("steady", 0))
		t["total_produced"] = int(Power.tile_produced.get(tile, 0))
		by_tile[tile] = t
	# Fold each consumer's green draw / unfirmed share into its tile.
	for cons in consumers:
		var tile := str(cons["tile"])
		if not by_tile.has(tile):
			var nt: Dictionary = _new_tile_intermittency(tile)
			nt["total_produced"] = int(Power.tile_produced.get(tile, 0))
			by_tile[tile] = nt
		var agg: Dictionary = by_tile[tile]
		agg["total_consumed"] = int(agg["total_consumed"]) + int(round(float(cons["demand"])))
		var r: Dictionary = _intermittency_by_building.get(str(cons["iid"]), {})
		if r.is_empty():
			continue
		agg["green_consumed"] = float(agg["green_consumed"]) + float(r.get("green_consumed", 0.0))
		agg["unfirmed_consumed"] = float(agg["unfirmed_consumed"]) + float(r.get("unfirmed_intermittent", 0.0))
		if float(r.get("derate", 0.0)) > 0.0:
			(agg["affected"] as Array).append({
				"iid": str(cons["iid"]), "building_id": str(cons["building_id"]),
				"power": int(round(float(cons["demand"]))),
			})
	# Affected buildings sorted by power consumed, highest first.
	for tile in by_tile.keys():
		(by_tile[tile]["affected"] as Array).sort_custom(func(a, b): return int(a["power"]) > int(b["power"]))
	return by_tile

func _new_tile_intermittency(tile_id: String) -> Dictionary:
	return {
		"green_produced": 0, "green_intermittent_produced": 0, "total_produced": 0,
		"green_consumed": 0.0, "total_consumed": 0, "unfirmed_consumed": 0.0,
		"battery_cap": _tile_storage_cap(tile_id), "affected": [],
	}

# Read-only accessors for the UI (tile view + building ledger filters). Reflect the most
# recently resolved turn (the intermittency is computed post-cascade, applied next turn).
func get_building_intermittency(instance_id: String) -> Dictionary:
	return _intermittency_by_building.get(instance_id, {})

func get_tile_intermittency(tile_id: String) -> Dictionary:
	return _intermittency_by_tile.get(tile_id, {})

# On-demand power-source attribution for ONE consumer (called when the building detail panel
# opens — NOT in the per-turn hot path). Attributes the building's draw to the NEAREST source
# buildings: its green draw (from the intermittency result) to green plants, the remainder to
# grey plants, then the leftover to the national grid. Returns
# {green_from:{iid->qty}, grey_from:{iid->qty}, grid:float}, or {} for non-consumers. This is
# a per-building illustrative attribution (the grid is a single settled pool), not metered flow.
func get_power_sources(instance_id: String) -> Dictionary:
	var b: Dictionary = MatchState.buildings.get(instance_id, {})
	if b.is_empty():
		return {}
	var recipe: Dictionary = Catalog.get_recipe(str(b.get("recipe_id", "")))
	if str(recipe.get("output_name", "")) == "power":
		return {}
	var demand := _effective_energy_req(b, recipe)
	if demand <= 0:
		return {}
	var tile := str(b.get("tile_id", ""))
	var green_need: float = minf(float(demand),
		float((_intermittency_by_building.get(instance_id, {}) as Dictionary).get("green_consumed", 0.0)))
	var green_srcs := []
	var grey_srcs := []
	for t in _power_sources_by_tile.keys():
		for s in _power_sources_by_tile[t]:
			var e := {"iid": str(s["iid"]), "tile": str(t), "qty": float(s["qty"])}
			if str(s["quality"]) == "grey":
				grey_srcs.append(e)
			else:
				green_srcs.append(e)
	var green_from := _pull_nearest(green_srcs, tile, green_need)
	var non_green: float = maxf(0.0, float(demand) - green_need)
	var grey_from := _pull_nearest(grey_srcs, tile, non_green)
	var grey_total := 0.0
	for k in grey_from.keys():
		grey_total += float(grey_from[k])
	return {"green_from": green_from, "grey_from": grey_from, "grid": maxf(0.0, non_green - grey_total)}

# Pull `amount` from the source buildings nearest `tile` (hex distance, then stable tile/iid
# order), capped by each source's recorded output. Returns {iid -> qty}. Pure read.
func _pull_nearest(srcs: Array, tile: String, amount: float) -> Dictionary:
	var out := {}
	if amount <= 0.0 or srcs.is_empty():
		return out
	srcs.sort_custom(func(a, c):
		var da := Catalog.tile_hex_distance(tile, str(a["tile"]))
		var dc := Catalog.tile_hex_distance(tile, str(c["tile"]))
		if da != dc:
			return da < dc
		if str(a["tile"]) != str(c["tile"]):
			return str(a["tile"]) < str(c["tile"])
		return str(a["iid"]) < str(c["iid"]))
	var need := amount
	for s in srcs:
		if need <= 0.0:
			break
		var take: float = minf(float(s["qty"]), need)
		if take <= 0.0:
			continue
		out[str(s["iid"])] = float(out.get(s["iid"], 0.0)) + take
		need -= take
	return out


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
	
	# Check inputs (the JIT direct feed counts — it's real goods staged for this tile)
	for input in inputs:
		var have: int = Stockpile.get_at_tile(tile_id, input.good_id) + _feed_available(tile_id, str(input.good_id))
		var need := _scaled_input_qty(input, building)
		if have < need:
			missing.append({
				"good_id": input.good_id,
				"internal_name": input.internal_name,
				"need": need,
				"have": have,
			})

	# A mined-out deposit stops the building entirely — no inputs consumed, no power
	# drawn, no output. (Maintenance + labour are charged separately, regardless.)
	var dep_token: String = _recipe_deposit_token(recipe)
	if dep_token != "" and MatchState.deposit_depleted(tile_id, dep_token):
		missing.append({
			"good_id": dep_token,
			"internal_name": dep_token,
			"need": 1,
			"have": 0,
		})

	# Power: cables are required to draw OR produce, and the tile's cable level hard-
	# caps how much it can draw (import) and produce (export) per turn — separately.
	var produces_power: bool = recipe.get("output_name", "") == "power"
	var draw: int = _effective_energy_req(building, recipe)
	var power_out: int = _effective_power_output(building, recipe) if produces_power else 0
	if draw > 0 or produces_power:
		if not Power.is_supplied(tile_id, draw):
			missing.append({"good_id": "power", "internal_name": "power",
				"need": draw if draw > 0 else 1, "have": 0})
		elif draw > 0 and not Power.can_draw(tile_id, draw):
			missing.append({"good_id": "power", "internal_name": "power",
				"need": draw, "have": Power.tile_power_cap(tile_id)})
		elif produces_power and not Power.can_produce(tile_id, power_out):
			missing.append({"good_id": "power", "internal_name": "power",
				"need": power_out, "have": Power.tile_power_cap(tile_id)})

	return {
		"can_run": missing.is_empty(),
		"missing": missing,
	}

func blocked_reason_for_building(instance_id: String) -> Dictionary:
	return blocked_reason_by_building.get(instance_id, {})

func run_warning_for_building(building: Dictionary, recipe: Dictionary) -> Dictionary:
	var instance_id := str(building.get("instance_id", ""))
	var reason: Dictionary = blocked_reason_for_building(instance_id)
	if not reason.is_empty():
		return reason
	var storage_reason := _battery_storage_missing_reason(building, recipe)
	if not storage_reason.is_empty():
		return storage_reason
	return {}

func _blocked_reason_for(building: Dictionary, recipe: Dictionary, missing: Array) -> Dictionary:
	var instance_id := str(building.get("instance_id", ""))
	var tile_id := str(building.get("tile_id", ""))
	if _has_waiting_overflow_input(tile_id, missing):
		return _run_warning("shipment_overflow", "Shipments did not reach building. Tile stockpile full.")
	var market_needed := _market_input_cash_needed(building, missing)
	if market_needed > 0.0 and MatchState.money + 0.0001 < market_needed:
		return _run_warning("market_input_cash", "Insufficient money to order inputs. Needed £%d." % int(ceil(market_needed)))
	var grid_needed := _grid_power_cash_needed(building, recipe, missing)
	if grid_needed > 0.0 and MatchState.money + 0.0001 < grid_needed:
		return _run_warning("grid_power_cash", "Insufficient money to buy power from grid. Needed £%d." % int(ceil(grid_needed)))
	if bool(_just_constructed_this_turn.get(instance_id, false)):
		return _run_warning("just_constructed", "Building just constructed. Wait one turn.")
	var storage_reason := _battery_storage_missing_reason(building, recipe)
	if not storage_reason.is_empty():
		return storage_reason
	var tile_only_needed := _tile_only_input_needed(building, missing)
	if tile_only_needed > 0:
		return _run_warning("tile_stockpile_only", "Insufficient inputs in stockpile to run recipe. Needed %d." % tile_only_needed)
	return {}

func _run_warning(code: String, message: String) -> Dictionary:
	return {"code": code, "message": message}

func _has_waiting_overflow_input(tile_id: String, missing: Array) -> bool:
	if tile_id == "" or missing.is_empty():
		return false
	var missing_goods := {}
	for entry in missing:
		var gid := str((entry as Dictionary).get("good_id", ""))
		if gid != "" and gid != "power":
			missing_goods[gid] = true
	if missing_goods.is_empty():
		return false
	for shipment in MatchState.get_overflow_shipments_for_tile(tile_id):
		var gid := str((shipment as Dictionary).get("good_id", ""))
		if int((shipment as Dictionary).get("qty", 0)) > 0 and missing_goods.has(gid):
			return true
	return false

func _market_input_cash_needed(building: Dictionary, missing: Array) -> float:
	if missing.is_empty():
		return 0.0
	var instance_id := str(building.get("instance_id", ""))
	var tile_id := str(building.get("tile_id", ""))
	if tile_id == "":
		return 0.0
	var total := 0.0
	for entry in missing:
		var m: Dictionary = entry
		var gid := str(m.get("good_id", ""))
		if gid == "" or gid == "power" or MatchState.is_input_tile_only(instance_id, gid):
			continue
		if Catalog.get_good(gid).is_empty():
			continue
		var qty := maxi(0, int(m.get("need", 0)) - int(m.get("have", 0)))
		if qty <= 0:
			continue
		var cache_key := "%s|%s|%d" % [tile_id, gid, qty]
		var preview: Dictionary = _warning_buy_preview_cache.get(cache_key, {})
		if not _warning_buy_preview_cache.has(cache_key):
			preview = MatchState.preview_buy(tile_id, gid, qty)
			_warning_buy_preview_cache[cache_key] = preview
		if preview.is_empty():
			continue
		total += float(preview.get("cost", 0.0))
	return total

func _grid_power_cash_needed(building: Dictionary, recipe: Dictionary, missing: Array) -> float:
	var has_power_missing := false
	for entry in missing:
		if str((entry as Dictionary).get("good_id", "")) == "power":
			has_power_missing = true
			break
	if not has_power_missing:
		return 0.0
	var draw := _effective_energy_req(building, recipe)
	if draw <= 0:
		return 0.0
	var tile_id := str(building.get("tile_id", ""))
	if not Power.is_supplied(tile_id, draw):
		return 0.0
	if Power.tile_power_cap(tile_id) < draw:
		return 0.0
	return float(draw) * EconomyConfig.GRID_BUY_PRICE

func _battery_storage_missing_reason(building: Dictionary, recipe: Dictionary = {}) -> Dictionary:
	var building_data := Catalog.get_building(str(building.get("building_id", "")))
	if str(building_data.get("category", "")) != "battery":
		return {}
	var tile_id := str(building.get("tile_id", ""))
	if tile_id == "" or MatchState.tile_battery_slots(tile_id) <= 0:
		return {}
	var catalysts: Array = recipe.get("catalysts", []) as Array
	if catalysts.is_empty():
		# Legacy battery recipes accepted any loaded battery cell.
		if MatchState.tile_battery_cells_loaded(tile_id) > 0:
			return {}
	else:
		var cells: Dictionary = MatchState.get_tile_battery_cells(tile_id)
		for catalyst in catalysts:
			if int(cells.get(str(catalyst.get("good_id", "")), 0)) > 0:
				return {}
	return _run_warning("battery_storage_empty", "Batteries missing. Fill storage to run.")

func _tile_only_input_needed(building: Dictionary, missing: Array) -> int:
	var instance_id := str(building.get("instance_id", ""))
	var needed := 0
	for entry in missing:
		var m: Dictionary = entry
		var gid := str(m.get("good_id", ""))
		if gid == "" or gid == "power":
			continue
		if MatchState.is_input_tile_only(instance_id, gid):
			needed += maxi(0, int(m.get("need", 0)) - int(m.get("have", 0)))
	return needed

func compute_committed_for_tile(tile_id: String) -> Dictionary:
	var committed: Dictionary = {}
	for building in MatchState.get_buildings_on_tile(tile_id):
		var recipe: Dictionary = Catalog.get_recipe(building.get("recipe_id", ""))
		for input in recipe.get("inputs", []):
			var good_id: String = input.get("good_id", "")
			var qty: int = _scaled_input_qty(input, building)
			if good_id != "" and qty > 0:
				committed[good_id] = committed.get(good_id, 0) + qty
	return committed

## Working-stock reserve per good for "Sell all Surplus": the per-turn input
## requirement of the PLAYER's buildings on the tile × the same (market lead + 1)
## factor the input pipeline stocks toward (_buy_market_inputs). One turn of
## committed inputs is NOT enough to protect: the pipeline deliberately keeps
## (lead+1) turns on remote tiles, and selling that buffer just makes the next
## buy phase re-purchase it at the ask + freight — a sell/re-buy churn loop that
## starves the tile for a full transport lead (diagnosed 2026-07-09 on Arinnal).
## NPC buildings never consume player stock, so only player buildings reserve.
## A good with no market route quotes lead 1 (2 turns kept) — the floor, since
## an unreachable tile can't refill what it sells.
func compute_sell_reserve_for_tile(tile_id: String) -> Dictionary:
	var reserve: Dictionary = {}
	var lead_cache: Dictionary = {}
	for building in MatchState.get_buildings_on_tile(tile_id):
		if not MatchState.is_player_owned(building):
			continue
		var recipe: Dictionary = Catalog.get_recipe(building.get("recipe_id", ""))
		for input in recipe.get("inputs", []):
			var good_id: String = input.get("good_id", "")
			var qty: int = _scaled_input_qty(input, building)
			if good_id == "" or qty <= 0:
				continue
			if not lead_cache.has(good_id):
				var quote: Dictionary = TransportService.quote_market_buy(
					tile_id, good_id, 1, MatchState.seaport_would_cover(good_id))
				lead_cache[good_id] = maxi(1, int(quote.get("turns", 1))) if not quote.is_empty() else 1
			reserve[good_id] = int(reserve.get(good_id, 0)) + qty * (int(lead_cache[good_id]) + 1)
	# Materials an AWAITING construction on this tile still needs are not surplus
	# either — the bill may gather over several turns, and selling the first half
	# while the second is in transit re-buys the same goods forever.
	var bills: Dictionary = Construction.missing_materials_for_tile(tile_id)
	for bill_good in bills:
		reserve[bill_good] = int(reserve.get(bill_good, 0)) + int(bills[bill_good])
	return reserve

## Units of a good delivered to this tile THIS turn (market buys, moves). Fresh
## deliveries get one turn of grace from the auto-sell — they are not surplus yet.
func _arrived_this_turn(tile_id: String, good_id: String) -> int:
	var by_good: Dictionary = _inbound_delivery_this_turn.get(tile_id, {})
	return int(float((by_good.get(good_id, {}) as Dictionary).get("qty", 0.0)))

func _inbound_qty(tile_id: String, good_id: String) -> int:
	var total := 0
	for s in MatchState.get_inbound_transport_shipments(tile_id, good_id):
		if _shipment_reserved_outside_input_pipeline(s):
			continue
		total += int(s.get("qty", 0))
	# Overflow-held goods have already arrived but couldn't unload (tile full); they
	# sit at the tile and retry every turn. They MUST count as inbound — before
	# 2026-07-09 they were invisible here, so the pipeline re-bought every bounced
	# batch each lead-cycle, forever (the warehouse-cap money incinerator).
	for r in MatchState.get_overflow_shipments_for_tile(tile_id):
		if str(r.get("good_id", "")) != good_id:
			continue
		if _shipment_reserved_outside_input_pipeline(r):
			continue
		total += int(r.get("qty", 0))
	return total

func _shipment_reserved_outside_input_pipeline(shipment: Dictionary) -> bool:
	return str(shipment.get("construction_instance_id", "")) != "" \
		or str(shipment.get("upgrade_instance_id", "")) != ""

func _buy_market_inputs(all_buildings: Array, summary: Dictionary) -> void:
	# For every input a player has set to "Market", keep the pipeline topped up to
	# (lead+1) turns of demand: order = target - on_tile - in_transit, shipped from the port.
	# Construction/upgrade-tagged shipments are reserved freight and do not count as
	# production pipeline stock; ordinary/manual/producer inbound goods still do.
	# Memoise (port, lead) per tile+good for this turn. Lead can be good-specific
	# because seaport coverage and infra eligibility affect the actual buy quote.
	var market_lead_cache: Dictionary = {}
	# Collect per-BUILDING demand per tile, in deterministic encounter order. Orders
	# are still netted per (tile, good) against the shared stock + inbound (computing
	# an order per building would let the first one's order zero out the rest), but
	# they are ALLOCATED building by building: when the tile's storage can't hold
	# every building's full (lead+1) buffer, the first buildings get their complete
	# buffers and the tail gets nothing this turn — one fully-fed building beats ten
	# at 10% (owner ruling 2026-07-09).
	# {tile_id -> Array[{instance_id, building_id, inputs: {good_id -> need/turn}}]}
	var demand_by_tile: Dictionary = {}
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
		var entry := {"instance_id": instance_id, "building_id": str(building.get("building_id", "")), "inputs": {}}
		for input in inputs:
			var good_id := str(input.good_id)
			if MatchState.is_input_tile_only(instance_id, good_id):
				if _input_source_exhausted_for(building, input):
					MatchState.set_input_tile_only(instance_id, good_id, false)
				else:
					continue  # player opted this input out of market top-up
			var need_per_turn := _scaled_input_qty(input, building)
			if need_per_turn <= 0:
				continue
			entry.inputs[good_id] = int(entry.inputs.get(good_id, 0)) + need_per_turn
		if not (entry.inputs as Dictionary).is_empty():
			var tile_entries: Array = demand_by_tile.get(tile_id, [])
			tile_entries.append(entry)
			demand_by_tile[tile_id] = tile_entries

	for tile_id in demand_by_tile:
		var entries: Array = demand_by_tile[tile_id]
		# Union of goods (encounter order) + aggregate per-turn need, plus the first
		# consuming building per good (cost-attribution + splice rows, as before).
		var goods_order: Array = []
		var total_need: Dictionary = {}
		var rep_building: Dictionary = {}
		for e in entries:
			for good_id in (e.inputs as Dictionary):
				if not total_need.has(good_id):
					goods_order.append(good_id)
					rep_building[good_id] = str(e.building_id)
				total_need[good_id] = int(total_need.get(good_id, 0)) + int(e.inputs[good_id])
		# Market lead + port per good (memoised); goods with no route order nothing.
		var leads: Dictionary = {}
		for good_id in goods_order:
			var cache_key := "%s|%s" % [str(tile_id), str(good_id)]
			var pl: Dictionary = market_lead_cache.get(cache_key, {})
			if pl.is_empty():
				var lead_quote := TransportService.quote_market_buy(str(tile_id), str(good_id), 1, MatchState.seaport_would_cover(str(good_id)))
				pl = {
					"port": str(lead_quote.get("port", "")),
					"lead": maxi(1, int(lead_quote.get("turns", 1))),
				} if not lead_quote.is_empty() else {"port": "", "lead": 0}
				market_lead_cache[cache_key] = pl
			leads[good_id] = pl
		# Only top up the SHORTFALL after recurring same-tile production. A good smelted on this
		# tile is replenished every turn, so the market pipeline should cover need − local_rate,
		# not the full need (which double-buys what you already make locally). The local pool is
		# handed to buildings in the same first-come order the allocator uses below.
		# ROADMAP (docs/long-term-roadmap.md): extend this to cross-tile (1-turn+) linked producers
		# too — needs a market-only inbound split + a ramp-up safety margin to avoid starvation.
		var local_pool: Dictionary = {}
		for good_id in goods_order:
			var local_rate: int = int((_same_tile_supply.get(tile_id, {}) as Dictionary).get(good_id, 0))
			local_pool[good_id] = local_rate
			var net_need: int = maxi(0, int(total_need[good_id]) - local_rate)
			if local_rate > 0 and net_need > 0 and str((leads[good_id] as Dictionary).get("port", "")) != "":
				# Spliced input: same-tile production covers part of the demand, the
				# market pipeline tops up the rest. Worth surfacing — if the local
				# producer dips, the top-up lags by the transport lead.
				summary.input_splices.append({
					"tile_id": str(tile_id), "good_id": str(good_id),
					"need": int(total_need[good_id]), "local": local_rate, "market": net_need,
					"building_id": str(rep_building[good_id]),
				})
		# Shared per-good pool the buffers draw down before ordering anything new:
		# on-tile stock + pipeline-visible inbound (in-flight AND overflow-held).
		var pool: Dictionary = {}
		for good_id in goods_order:
			pool[good_id] = Stockpile.get_at_tile(tile_id, good_id) + _inbound_qty(tile_id, str(good_id))
		# Storage budget: never order more than the tile can physically accept once
		# everything already heading there (or bounced and waiting) has unloaded.
		# Without this the pipeline happily orders 1000+ units of buffers against an
		# 800-unit warehouse and the tile deadlocks (owner's turn-13..68 jam).
		# Construction/upgrade-reserved freight is excluded: projects claim it off the
		# tile the moment it lands, so it passes through rather than occupying storage.
		var inbound_all := 0
		for s in MatchState.get_inbound_transport_shipments(str(tile_id)):
			if bool(s.get("is_sale", false)) or _shipment_reserved_outside_input_pipeline(s):
				continue
			inbound_all += int(s.get("qty", 0))
		var held_all := 0
		for r in MatchState.get_overflow_shipments_for_tile(str(tile_id)):
			if not _shipment_reserved_outside_input_pipeline(r):
				held_all += int(r.get("qty", 0))
		var budget: int = maxi(0, Stockpile.get_capacity(tile_id) - Stockpile.get_used_capacity(tile_id) - inbound_all - held_all)
		# Building-first allocation: walk buildings in order; each claims local supply,
		# then the shared pool, then orders the remainder while budget lasts.
		var orders: Dictionary = {}   # good_id -> units to order this turn
		var wanted: Dictionary = {}   # good_id -> units we WOULD order uncapped
		for e2 in entries:
			for good_id in (e2.inputs as Dictionary):
				if str((leads[good_id] as Dictionary).get("port", "")) == "":
					continue
				var need: int = int(e2.inputs[good_id])
				var covered_local: int = mini(need, int(local_pool.get(good_id, 0)))
				local_pool[good_id] = int(local_pool.get(good_id, 0)) - covered_local
				var want: int = (need - covered_local) * (int((leads[good_id] as Dictionary).get("lead", 1)) + 1)
				var from_pool: int = mini(want, int(pool.get(good_id, 0)))
				pool[good_id] = int(pool.get(good_id, 0)) - from_pool
				var to_order: int = want - from_pool
				if to_order <= 0:
					continue
				wanted[good_id] = int(wanted.get(good_id, 0)) + to_order
				var placed: int = mini(to_order, budget)
				budget -= placed
				if placed > 0:
					orders[good_id] = int(orders.get(good_id, 0)) + placed
		# Structural check: can this tile's warehouse hold the buildings' working set
		# at all? Import buffers are (lead+1) turns of net need; locally-made
		# intermediates and outputs each need ~2 turns of room between flush and
		# consumption/sale. If the total beats capacity, the tile WILL jam sooner or
		# later no matter how orders are throttled — surface it as a critical update.
		var required := 0
		var jit := MatchState.is_unlocked(JIT_UNLOCK_TITLE)
		for good_id in goods_order:
			var lr: int = int((_same_tile_supply.get(tile_id, {}) as Dictionary).get(good_id, 0))
			var gross: int = int(total_need[good_id])
			if str((leads[good_id] as Dictionary).get("port", "")) != "":
				required += maxi(0, gross - lr) * (int((leads[good_id] as Dictionary).get("lead", 1)) + 1)
			if not jit:
				# Locally-made intermediates transit the warehouse (~2 turns of room)
				# — unless Just-in-Time Logistics feeds them building-to-building.
				required += mini(lr, gross) * 2
		for e5 in entries:
			var out_building: Dictionary = MatchState.get_building(str(e5.instance_id))
			var out_recipe: Dictionary = Catalog.get_recipe(str(out_building.get("recipe_id", "")))
			for output in out_recipe.get("outputs", []):
				if str(output.get("internal_name", "")) == "power":
					continue
				required += int(round(float(output.get("qty", 0)) * BuildingLevels.mult("output", int(out_building.get("level", 1))))) * 2
		var tile_cap := Stockpile.get_capacity(tile_id)
		if required > tile_cap:
			summary.storage_overcommitted.append({
				"tile_id": str(tile_id), "required": required, "capacity": tile_cap,
			})
		for good_id in goods_order:
			var clipped: int = int(wanted.get(good_id, 0)) - int(orders.get(good_id, 0))
			if clipped > 0:
				# Storage-capped, not cash-capped: the tile can't hold this slice of
				# the buffer. Recorded separately so the briefing can say "expand
				# storage", not "find cash".
				summary.input_orders_capped.append({
					"tile_id": str(tile_id), "good_id": str(good_id),
					"wanted": int(wanted.get(good_id, 0)), "placed": int(orders.get(good_id, 0)),
				})
			var order: int = int(orders.get(good_id, 0))
			if order > 0:
				var bought: Dictionary = MatchState.queue_buy(tile_id, good_id, order, true, {
					"buy_kind": "input",
					"auto_input_pipeline": true,
				})
				var got: int = int(bought.get("qty", 0))
				if got < order:
					# Cash-clipped (partial) or cash-skipped (empty) order — the silent
					# starvation path diagnosed 2026-07-09. Record it for the briefing.
					summary.input_orders_short.append({
						"tile_id": str(tile_id), "good_id": str(good_id),
						"requested": order, "bought": got,
						"short_cost": float(order - got) * MarketState.get_buy_price(good_id),
					})
				if not bought.is_empty():
					summary.goods_purchased_cost += float(bought.get("goods_cost", 0.0))
					summary.transport_paid += float(bought.get("transport_cost", 0.0))
					summary.money_out += float(bought.get("cost", 0.0))
					summary.purchased[good_id] = int(summary.purchased.get(good_id, 0)) + int(bought.get("qty", 0))
					summary.purchased_cost[good_id] = float(summary.purchased_cost.get(good_id, 0.0)) + float(bought.get("goods_cost", 0.0))
					_accumulate_by_type(summary.goods_purchased_by_type, str(rep_building[good_id]), float(bought.get("goods_cost", 0.0)), 0)
	# Player-set recurring market purchases (Purchases tab), delivered to the chosen tile.
	for rb in MatchState.recurring_buys:
		var rgood := str(rb.get("good", ""))
		var rbought: Dictionary = MatchState.queue_buy(str(rb.get("dest", "")), rgood, int(rb.get("qty", 0)), false, {"buy_kind": "input"})
		if not rbought.is_empty():
			summary.goods_purchased_cost += float(rbought.get("goods_cost", 0.0))
			summary.transport_paid += float(rbought.get("transport_cost", 0.0))
			summary.money_out += float(rbought.get("cost", 0.0))
			summary.purchased[rgood] = int(summary.purchased.get(rgood, 0)) + int(rbought.get("qty", 0))
			summary.purchased_cost[rgood] = float(summary.purchased_cost.get(rgood, 0.0)) + float(rbought.get("goods_cost", 0.0))
			_accumulate_by_type(summary.goods_purchased_by_type, "", float(rbought.get("goods_cost", 0.0)), 0)

func _input_source_exhausted_for(building: Dictionary, input: Dictionary) -> bool:
	var target_tile := str(building.get("tile_id", ""))
	var current_instance_id := str(building.get("instance_id", ""))
	var input_good_id := str(input.get("good_id", ""))
	var input_internal := str(input.get("internal_name", ""))
	if target_tile == "" or (input_good_id == "" and input_internal == ""):
		return false
	var saw_exhausted_source := false
	var saw_live_source := false
	for producer in MatchState.buildings.values():
		if str(producer.get("instance_id", "")) == current_instance_id:
			continue
		if not MatchState.is_player_owned(producer):
			continue
		var producer_recipe: Dictionary = Catalog.get_recipe(str(producer.get("recipe_id", "")))
		if producer_recipe.is_empty():
			continue
		var output_good_id := _recipe_output_good_matching_input(producer_recipe, input_good_id, input_internal)
		if output_good_id == "":
			continue
		var destination = _output_stockpile_coord(producer, output_good_id)
		if destination == null or str(destination) != target_tile:
			continue
		var dep_token := _recipe_deposit_token(producer_recipe)
		if dep_token != "" and MatchState.deposit_depleted(str(producer.get("tile_id", "")), dep_token):
			saw_exhausted_source = true
		else:
			saw_live_source = true
	return saw_exhausted_source and not saw_live_source

func _recipe_output_good_matching_input(recipe: Dictionary, input_good_id: String, input_internal: String) -> String:
	for output in _recipe_output_items(recipe):
		var output_internal := str(output.get("internal_name", ""))
		var output_good_id := ""
		if output_internal != "":
			output_good_id = str(Catalog.get_good_by_internal_name(output_internal).get("id", ""))
		if input_good_id != "" and output_good_id == input_good_id:
			return output_good_id
		if input_internal != "" and output_internal == input_internal:
			return output_good_id
	return ""

func _consume_inputs(building: Dictionary, recipe: Dictionary, summary: Dictionary) -> void:
	var inputs: Array = recipe.get("inputs", [])
	var tile_id: String = building.get("tile_id", "")
	var player_owned := MatchState.is_player_owned(building)
	var iid: String = str(building.get("instance_id", ""))
	for input in inputs:
		var qty := _scaled_input_qty(input, building)
		# JIT feed first (goods staged building-to-building), warehouse for the rest.
		var from_feed := _feed_consume(tile_id, str(input.good_id), qty)
		if qty - from_feed > 0:
			Stockpile.consume(tile_id, input.good_id, qty - from_feed)
		if qty > 0:
			MatchState.flag_agenda_event(MatchState.AGENDA_USED_STOCKPILE)
		summary.consumed[input.good_id] = summary.consumed.get(input.good_id, 0) + qty
		# Carbon levy accrual: taxed goods burned by PLAYER buildings this turn.
		# Charged in one lump in the carbon_tax step (after tax_dividends).
		if player_owned and qty > 0 and float(Catalog.get_good(str(input.good_id)).get("co2_tax_multiplier", 0.0)) > 0.0:
			var per: Dictionary = _carbon_consumed_by_building.get(iid, {})
			per[str(input.good_id)] = int(per.get(str(input.good_id), 0)) + qty
			_carbon_consumed_by_building[iid] = per

func _scaled_input_qty(input: Dictionary, building: Dictionary) -> int:
	var capacity_mult := MatchState.startup_capacity_multiplier(building)
	var scaled := float(input.get("qty", 0)) * BuildingLevels.mult("input", int(building.get("level", 1))) * capacity_mult
	return int(ceil(scaled)) if capacity_mult < 1.0 and scaled > 0.0 else int(round(scaled))
