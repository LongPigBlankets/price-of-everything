extends Node

const MAX_PRODUCTION_PASSES := 30

var last_turn_summary: Dictionary = {}
var missing_by_building: Dictionary = {}  # instance_id -> Array of missing inputs
var last_turn_run: Dictionary = {}  # instance_id -> true (set of buildings that ran)
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
	Power.reset_for_turn()
	
	var summary := {
	"produced": {},
	"consumed": {},
	"sold": {},
	"starved": [],
	# Money breakdown (Pass 8 additions)
	"goods_sales_revenue": 0.0,
	"power_sales_revenue": 0.0,
	"power_purchase_cost": 0.0,
	"maintenance_paid": 0.0,
	"labour_paid": 0.0,
	"taxes_paid": 0.0,
	"dividends_paid": 0.0,
	"interest_paid": 0.0,
	# Aggregates (preserved for compatibility)
	"money_in": 0.0,
	"money_out": 0.0,
	# Power-specific
	"power_supply": 0,
	"power_demand": 0,
	"grid_bought": 0,
	"grid_sold": 0,
}
	
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
			_consume_inputs(recipe, summary)
			
			# Register power demand if any
			var energy_req: int = recipe.get("energy_req", 0)
			if energy_req > 0:
				Power.add_demand(energy_req)
				summary.consumed["power"] = summary.consumed.get("power", 0) + energy_req
			
			# Route output: power goes to Power supply, everything else to Stockpile
			var output_name: String = recipe.get("output_name", "")
			if output_name == "power":
				var output_qty: int = recipe.get("output_qty", 0)
				Power.add_supply(output_qty)
				summary.produced["power"] = summary.produced.get("power", 0) + output_qty
				print("[Production] Building %s produced %d Power" % [instance_id, output_qty])
			else:
				_produce_outputs(building, recipe, summary)
			
			has_run[instance_id] = true
			last_turn_run[instance_id] = true
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

	if grid.grid_sell_revenue > 0:
		MatchState.add_money(grid.grid_sell_revenue)
		summary.power_sales_revenue = grid.grid_sell_revenue
		summary.money_in += grid.grid_sell_revenue
	# === SELL PHASE (only if SELL_ALL) ===
	if MatchState.sell_mode == MatchState.SellMode.SELL_ALL:
		var totals: Dictionary = Stockpile.get_all_totals()
		for good_id in totals.keys():
			var qty: int = totals[good_id]
			if qty <= 0:
				continue
			var price: float = MarketState.get_price(good_id)
			var revenue: float = qty * price
			Stockpile.consume(null, good_id, qty)
			MatchState.add_money(revenue)
			summary.sold[good_id] = {"qty": qty, "revenue": revenue}
			summary.goods_sales_revenue += revenue
			summary.money_in += revenue
		
	# === COSTS PHASE ===
	for building in all_buildings:
		var maint: float = EconomyConfig.MAINTENANCE_PER_BUILDING
		var labour: float = _calculate_labour_cost(building)
		var total_cost: float = maint + labour
		MatchState.add_money(-total_cost)
		summary.maintenance_paid += maint
		summary.labour_paid += labour
		summary.money_out += total_cost
		# === LOAN INTEREST PAYMENTS ==+var loan_payment: float = LoanState.process_payments()
	var loan_payment: float = LoanState.process_payments()
	if loan_payment > 0:
		summary.interest_paid = loan_payment
		summary.money_out += loan_payment
		# === TAX & DIVIDEND PHASE ===
# Compute pre-tax profit: revenue - operating costs - interest.
# Only deduct tax/dividends if profit is positive.
	var revenue: float = summary.goods_sales_revenue + summary.power_sales_revenue
	var operating_costs: float = summary.maintenance_paid + summary.labour_paid + summary.power_purchase_cost
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
	print("[Production] Cash breakdown: goods=£%.2f power_sold=£%.2f power_bought=£%.2f costs=£%.2f interest=£%.2f tax=£%.2f div=£%.2f net=£%.2f" % [
	summary.goods_sales_revenue,
	summary.power_sales_revenue,
	summary.power_purchase_cost,
	summary.maintenance_paid + summary.labour_paid,
	summary.interest_paid,
	summary.taxes_paid,
	summary.dividends_paid,
	summary.money_in - summary.money_out
])

	

# --- Helpers ---

func _get_recipe(recipe_id: String) -> Dictionary:
	if recipe_id == "":
		return {}
	# ADAPT THIS to your Recipes accessor
	return Catalog.get_recipe(recipe_id)
	
	
func _produce_outputs(building: Dictionary, recipe: Dictionary, summary: Dictionary) -> void:
	var output_name: String = recipe.get("output_name", "")
	var output_qty: int = recipe.get("output_qty", 0)
	
	if output_name == "" or output_qty <= 0:
		return

	# Recipes use internal_name; need good_id
	var good: Dictionary = Catalog.get_good_by_internal_name(output_name)
	if good.is_empty():
		push_warning("[Production] Unknown good '%s' from recipe %s" % [
			output_name, recipe.get("recipe_id", "?")
		])
		return
	
	print("[Production] Building %s produced %d %s" % [
		building.instance_id, output_qty, good.display_name
	])
	
	Stockpile.add(null, good.id, output_qty)
	summary.produced[good.id] = summary.produced.get(good.id, 0) + output_qty

func _calculate_labour_cost(_building: Dictionary) -> float:
	var unskilled := 100
	var skilled := 50
	var high_skilled := 50
	var base_cost: float = (
		unskilled * EconomyConfig.LABOUR_UNSKILLED_RATE
		+ skilled * EconomyConfig.LABOUR_SKILLED_RATE
		+ high_skilled * EconomyConfig.LABOUR_HIGH_SKILLED_RATE
	)
	return base_cost * MatchState.labour_multiplier

func _can_run_recipe(building: Dictionary, recipe: Dictionary) -> Dictionary:
	var inputs: Array = recipe.get("inputs", [])
	var missing: Array = []
	
	# Check inputs
	for input in inputs:
		var have: int = Stockpile.get_total(input.good_id)
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
		var tile_id: String = building.get("tile_id", "")
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
func _consume_inputs(recipe: Dictionary, summary: Dictionary) -> void:
	var inputs: Array = recipe.get("inputs", [])
	for input in inputs:
		Stockpile.consume(null, input.good_id, input.qty)
		summary.consumed[input.good_id] = summary.consumed.get(input.good_id, 0) + input.qty
