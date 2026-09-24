extends RefCounted
const Middleman := preload("res://scripts/middleman_service.gd")
## Shared, UI-agnostic READOUT of a building for the building detail panel.
## Aggregates the existing single-source-of-truth helpers (BuildingStatus, CostSolver,
## Modifiers, Catalog, EconomyConfig, MatchState) into plain data the panel renders — so the panel
## never re-derives balance-sensitive numbers. All functions are STATIC and read-only against
## the sim (architecture rule 5). Preloaded (no class_name) so it resolves in headless runs.
##
## The one deliberate presentation choice: there is no engine per-building per-turn PROFIT, and
## mixing the building's asset value (base_price) with per-turn flows would be meaningless — so
## the economics block reports real cash flows (maintenance, labour, running cost) plus the
## engine's actual profitability signal, the cost-to-produce-vs-market RAG. See
## docs/building-detail-v2-plan.md §Economics.

const BuildingStatus := preload("res://scripts/building_status.gd")
const BuildingLevels := preload("res://scripts/building_levels.gd")
const BuildingPrice := preload("res://scripts/building_price.gd")
const CompanyNames := preload("res://scripts/company_names.gd")
const PORT_BUILDING_ID := "b_004"

# Tone keys used by the diagnostics rows → resolved to DS palette by the panel.
# "ok" | "warn" | "bad" | "info"

# --- Classification -----------------------------------------------------------------------

static func classify(building_data: Dictionary, recipe: Dictionary, building_id: String = "") -> String:
	if building_id == PORT_BUILDING_ID:
		return "port"
	var cat := str(building_data.get("category", "")).to_lower()
	if cat == "battery":
		return "battery"
	if cat == "infrastructure":
		return "infrastructure"
	if str(recipe.get("output_name", "")) == "power":
		return "renewable_power" if (recipe.get("inputs", []) as Array).is_empty() else "thermal_power"
	return "production"

static func is_recipe_kind(kind: String) -> bool:
	return kind in ["production", "thermal_power", "renewable_power", "liquid"]

# --- Status (running / idle / stalled) ----------------------------------------------------

# Shared run-state (badge + diagnostics both derive from this so they never disagree):
#   operational — infrastructure (no recipe)
#   running     — produced last turn (or a no-input source that's powered)
#   restarting  — didn't run, but inputs are now in stock AND it's powered → resumes next turn (AMBER)
#   stalled     — deposit exhausted, unpowered, or short of inputs (RED)
static func run_state(building: Dictionary, recipe: Dictionary, is_infrastructure: bool) -> String:
	if BuildingStatus.recipe_deposit_exhausted(building, recipe):
		return "stalled"
	if is_infrastructure:
		return "operational"
	if BuildingStatus.power_status_color(building, recipe, is_infrastructure) == BuildingStatus.STATUS_RED:
		return "stalled"
	var iid := str(building.get("instance_id", ""))
	if Middleman.uses_inputs(iid):
		var p := Middleman.preview(iid)
		if not bool(p.get("can_run",false)): return "stalled"
		return "running" if Production.last_turn_run.has(iid) else "restarting"
	if iid != "" and Production.last_turn_run.has(iid):
		return "running"
	if (recipe.get("inputs", []) as Array).is_empty():
		return "running"  # a powered no-input source (renewable) always runs
	if has_all_inputs(building, recipe):
		return "restarting"
	# Short on-tile RIGHT NOW, but in-transit units will cover every shortfall next turn — a timing
	# gap (a linked producer on another tile, or a market delivery in flight), not a real shortage.
	# Read it as amber "Starting", not red "Stalled". Same-tile 0-turn production is out of scope
	# here (the input safety margin in production.gd handles that); this is the multi-tile case.
	if inbound_covers_shortfall(building, recipe):
		return "restarting"
	return "stalled"

static func has_all_inputs(building: Dictionary, recipe: Dictionary) -> bool:
	var tile := str(building.get("tile_id", ""))
	for inp in recipe.get("inputs", []):
		if Stockpile.get_at_tile(tile, str(inp.get("good_id", ""))) < int(inp.get("qty", 0)):
			return false
	return true

## True when the building is short of at least one input on-tile now, AND every such shortfall is
## covered once its in-transit units land. Only reached after has_all_inputs() is already false, so
## the shipments() scan runs on the rare short path, not every healthy building.
static func inbound_covers_shortfall(building: Dictionary, recipe: Dictionary) -> bool:
	var any_short := false
	for s in shipments(building, recipe):
		if int(s.get("stored", 0)) < int(s.get("need", 0)):
			any_short = true
			if int(s.get("stored", 0)) + int(s.get("inbound", 0)) < int(s.get("need", 0)):
				return false
	return any_short

static func status(building: Dictionary, recipe: Dictionary, is_infrastructure: bool) -> Dictionary:
	var producing := str(recipe.get("output_name", "")) == "power"
	match run_state(building, recipe, is_infrastructure):
		"operational":
			return {"state": "running", "label": "Operational", "tone": "ok"}
		"running":
			return {"state": "running", "label": "Generating" if producing else "Running", "tone": "ok"}
		"restarting":
			return {"state": "restarting", "label": "Starting", "tone": "warn"}
		_:
			return {"state": "stalled", "label": "Stalled", "tone": "bad"}

# --- Recipe flow (inputs → power → output, with modifier) ----------------------------------

## `this_turn` quantities include the startup ramp and intermittency derate (BuildingStatus.effective_output_qty).
static func flow(building: Dictionary, recipe: Dictionary, this_turn := false) -> Dictionary:
	var inputs: Array = []
	for inp in recipe.get("inputs", []):
		inputs.append({
			"good_id": str(inp.get("good_id", "")),
			"internal": str(inp.get("internal_name", "")),
			"qty": int(inp.get("qty", 0)),
		})
	# ALL outputs, not just the first: chlor-alkali makes chlorine, sodium hydroxide AND hydrogen.
	# The engine's effective-qty
	# helper is defined for the recipe's PRIMARY output, so the co-products are scaled by the same
	# ratio the primary was — one modifier applies to the whole batch, not per good.
	var out_items := BuildingStatus.flow_output_items(recipe)
	var outputs: Array = []
	var output: Dictionary = {}
	if not out_items.is_empty():
		var primary: Dictionary = out_items[0]
		var primary_base := int(primary.get("qty", 0))
		var eff := BuildingStatus.effective_output_qty(building, recipe, this_turn)
		if str(recipe.get("output_name", "")) == "power":
			eff = BuildingStatus.effective_power_output(building, recipe)
		var ratio := (float(eff) / float(primary_base)) if primary_base > 0 else 1.0
		for i in range(out_items.size()):
			var o: Dictionary = out_items[i]
			var base_qty := int(o.get("qty", 0))
			outputs.append({
				"good_id": str(o.get("good_id", "")),
				"internal": str(o.get("internal_name", "")),
				"qty": eff if i == 0 else int(round(float(base_qty) * ratio)),
				"base_qty": base_qty,
			})
		output = outputs[0]
	var mod := BuildingStatus.net_output_modifier(building, recipe)
	return {
		"inputs": inputs,
		"output": output,      # the primary output — kept for callers that show one hero icon
		"outputs": outputs,    # every output, in recipe order (co-products included)
		"power_in": BuildingStatus.effective_energy_req(building, recipe),
		"produces_power": str(recipe.get("output_name", "")) == "power",
		"mod_pct": int(mod.get("pct", 0)),
		"mod_text": str(mod.get("text", "")),
	}

# --- Economics (real cash flows + the cost-to-produce RAG) ---------------------------------

static func economics(building: Dictionary, recipe: Dictionary, building_data: Dictionary) -> Dictionary:
	if Middleman.fully_managed(str(building.get("instance_id",""))):
		var p := Middleman.preview(str(building.instance_id))
		if bool(p.ok):
			var output_units := 0
			for item: Dictionary in p.sale.items: output_units += int(item.quantity)
			return {"middleman":true,"value":float(building_data.get("base_price",0.0)),"output_value":float(p.sale.goods_value),
				"output_values":[],"sells":true,"selling_output_count":1,"units_out":output_units,"sale_price":0.0,
				"transport_cost":0.0,"middleman_fee":float(p.fee),"logistics_intermediary_fee":float(p.fee),"input_cost":float(p.buy.goods_value),"maintenance":float(p.maintenance),
				"labour_cost":float(p.labour),"power_cost":float(p.power),"warehousing_cost":0.0,"carbon_tax":float(p.carbon_tax),
				"running_cost":float(p.buy.goods_value)+float(p.fee)+float(p.maintenance)+float(p.labour)+float(p.power)+float(p.carbon_tax),"net":float(p.net)}
	# Maintenance, labour and power are priced through production.gd's OWN per-turn helpers — the
	# exact functions that move the cash each turn — so the panel reflects real building
	# performance: grown wages (not base rates), level multipliers, and every active modifier
	# (research building_power/maintenance/labour_headcount, workforce policies, Lax Safety upkeep).
	# The forecast prices through these same helpers, so the BDP agrees with it and with
	# the engine.
	var maint := Production._calculate_maintenance_cost(building)
	var lab_cost := Production._calculate_labour_cost(building, recipe)
	# Power leg: the grid-price value of the energy actually drawn this turn (post power modifiers,
	# level, and startup ramp; 0 for generators / no-power recipes). Priced at GRID_BUY_PRICE like
	# the CostSolver — this is the imputed energy cost, which for a self-powered tile is dearer than
	# the marginal cash (a known cost-model choice, not specific to this panel).
	var power_cost := float(Production._effective_energy_req(building, recipe)) * EconomyConfig.GRID_BUY_PRICE
	# Simplified per-turn worth: Output value − transport − inputs − maintenance − labour − power.
	# Output value includes every product of the run. A co-product is genuine value
	# added by the same building, so leaving it out made multi-output recipes (such
	# as Chlor-Alkali) appear materially less valuable than they are.
	var out_gid := BuildingStatus.primary_output_good_id(recipe)
	var units_out := BuildingStatus.effective_output_qty(building, recipe)
	var output_value := 0.0
	var price := 0.0
	var output_values: Array = []
	var selling_outputs := 0
	for output: Dictionary in (flow(building, recipe).get("outputs", []) as Array):
		var output_gid := str(output.get("good_id", ""))
		var output_qty := int(output.get("qty", 0))
		if output_gid == "" or output_qty <= 0:
			continue
		# Live market price (incl. glut/deficit impact), falling back to the impact-free base.
		var output_price := MarketState.get_price(output_gid)
		if output_price <= 0.0:
			output_price = Catalog.get_base_price(output_gid)
		if output_gid == out_gid:
			price = output_price
		var value := float(output_qty) * output_price
		output_value += value
		output_values.append({"good_id": output_gid, "qty": output_qty, "price": output_price, "value": value})
		var output_mode := str(_output_disposition(building, recipe, output_gid).get("mode", "held"))
		if output_mode == "market" or output_mode == "tile_sales":
			selling_outputs += 1
	# Inputs valued the way the cash actually leaves the company: an internally-made input costs
	# what it cost to PRODUCE (the CostSolver's imputed per-good cost, resolved over the chain), but
	# an input the building has no own source for is BOUGHT on the market — so it costs the retail
	# BUY price (sale price + the ~5% bid-ask markup), not the sell price. Valuing bought inputs at
	# the sell price would understate running cost by that markup. get_good_unit_cost returns −1
	# for a good no player building makes, which is exactly the "bought from market" case.
	var input_cost := 0.0
	for inp in recipe.get("inputs", []):
		var in_gid := str(inp.get("good_id", ""))
		var imputed := CostSolver.get_good_unit_cost(in_gid)  # −1 when external / not yet solved
		var unit_price := imputed if imputed >= 0.0 else MarketState.get_buy_price(in_gid)
		if unit_price <= 0.0:
			unit_price = Catalog.get_base_price(in_gid)
		# Quantity actually consumed this turn: the recipe base scaled by level (a level-2 building
		# eats 2x) and the startup-capacity ramp — the same _scaled_input_qty the engine draws.
		input_cost += float(Production._scaled_input_qty(inp, building)) * unit_price
	# Is the output actually sold this turn (market route, or a tile that auto-sells its surplus)?
	# A generator / infrastructure has no sellable good (units_out == 0) — never treat it as selling.
	var sells := selling_outputs > 0

	# Inputs, labour, power, maintenance, warehousing and carbon are now priced through the engine's
	# own per-turn helpers (see above / below), so they are actuals, not estimates. Transport
	# remains primary-output-only and excludes sea charges — the one line still to reconcile.
	# Transport cost of moving the output to its SET destination (nearest port for a market route,
	# the target tile otherwise, 0 for same-tile / no destination).
	var own_tile := str(building.get("tile_id", ""))
	var route := output_route(building, recipe)
	var target := str(route.get("target", ""))
	var transport_cost := 0.0
	if units_out > 0 and target != "" and target != own_tile and bool(route.get("reachable", true)):
		transport_cost = float(BuildingStatus.route_summary(own_tile, target, out_gid, units_out).get("cost", 0.0))
	# Storage overhead: this building's attributed share of its tile's actual warehousing fee last turn.
	var warehousing := CostSolver.warehousing_share(str(building.get("instance_id", "")))
	# Carbon levy (live estimate at the CURRENT policy phase) on this run's taxed inputs.
	var carbon_tax := PolicyState.run_carbon_levy(building, recipe)
	var service_fee := 0.0
	var iid := str(building.get("instance_id",""))
	if Middleman.enabled(iid):
		var quote := Middleman.preview(iid)
		service_fee = float(quote.fee)
		if Middleman.uses_inputs(iid): input_cost = float(quote.buy.goods_value)
		if str(recipe.get("output_name", "")) == "power":
			output_value = float(quote.grid_value)
			sells = true
			transport_cost = 0.0
		if Middleman.uses_outputs(iid):
			output_value = float(quote.sale.goods_value)
			sells = true
			selling_outputs = output_values.size()
			transport_cost = 0.0
	var running := service_fee + maint + lab_cost + power_cost + input_cost + transport_cost + warehousing + carbon_tax
	var pc := BuildingStatus.produce_cost_status(building)
	return {
		"value": float(building_data.get("base_price", 0.0)),   # asset value (build/buy price), not per-turn
		"output_value": output_value,
		"output_values": output_values,
		"sells": sells,
		"selling_output_count": selling_outputs,
		"units_out": units_out,
		"sale_price": price,
		"middleman_fee": service_fee,
		"logistics_intermediary_fee": service_fee,
		"transport_cost": transport_cost,
		"input_cost": input_cost,
		"maintenance": maint,
		"labour_cost": lab_cost,
		"power_cost": power_cost,
		"warehousing_cost": warehousing,
		"carbon_tax": carbon_tax,
		"running_cost": running,
		"net": output_value - running,
		"unit_cost": float(pc.get("unit_cost", -1.0)),
		"unit_cost_color": pc.get("color", BuildingStatus.STATUS_GREY),
		"base_price_out": float(pc.get("base_price", 0.0)),     # market price of the primary output
	}

# Where this building's primary output goes this turn: "market" (direct market route, whole run
# sells), "tile_sales" (lands on a tile whose surplus auto-sells — a partial sale is possible), or
# "held" (feeds a downstream building or just sits in a stockpile — earns nothing directly).
static func _output_disposition(building: Dictionary, recipe: Dictionary, output_good_id: String = "") -> Dictionary:
	var iid := str(building.get("instance_id", ""))
	var gid := output_good_id if output_good_id != "" else BuildingStatus.primary_output_good_id(recipe)
	var src := str(building.get("tile_id", ""))
	if gid == "":
		return {"mode": "held", "sell_tile": src, "good_id": ""}
	# The per-good intermediary owns this output privately. Do not let the
	# global sell mode reinterpret it as a same-tile stockpile or market sale.
	if Middleman.buys_output(iid, gid):
		return {"mode": "held", "sell_tile": "", "good_id": gid}
	if MatchState.is_output_market(iid, gid):
		return {"mode": "market", "sell_tile": src, "good_id": gid}
	var dest := MatchState.get_output_stockpile_destination(iid, gid)
	if MatchState.sell_mode == MatchState.SellMode.SELL_ALL:
		# global sell-all: routed output sells from its landing tile; unrouted dispatches to market
		if dest != "":
			return {"mode": "tile_sales", "sell_tile": dest, "good_id": gid}
		return {"mode": "market", "sell_tile": src, "good_id": gid}
	# STOCKPILE_ALL (the default): only auto-sell-flagged tiles clear their surplus
	var land := dest if dest != "" else src
	if MatchState.should_auto_sell_good(land, gid):
		return {"mode": "tile_sales", "sell_tile": land, "good_id": gid}
	return {"mode": "held", "sell_tile": land, "good_id": gid}

# --- Labour split -------------------------------------------------------------------------

static func labour(building_data: Dictionary, recipe: Dictionary = {}) -> Dictionary:
	var source: Dictionary = recipe if int(recipe.get("labour_unskilled_required", -1)) >= 0 else building_data
	var unskilled := int(source.get("labour_unskilled_required", 0))
	var skilled := int(source.get("labour_skilled_required", 0))
	var highly := int(source.get("labour_h_skilled_required", 0))
	var factor := LabourState.labour_policy_factor()
	var cost := (float(unskilled) * EconomyConfig.LABOUR_UNSKILLED_RATE
		+ float(skilled) * EconomyConfig.LABOUR_SKILLED_RATE
		+ float(highly) * EconomyConfig.LABOUR_HIGH_SKILLED_RATE) * factor
	return {
		"unskilled": unskilled, "skilled": skilled, "highly": highly,
		"total": unskilled + skilled + highly, "cost": cost,
	}

# --- Power line ---------------------------------------------------------------------------

# Power draw + who supplies it. The supply attribution is only meaningful AFTER the building has
# run (own vs grid is settled during the turn); before that it reads "ready" (grid-connected) or
# "none". state: own | grid | ready | none.
static func power(building: Dictionary, recipe: Dictionary) -> Dictionary:
	var amount := BuildingStatus.effective_energy_req(building, recipe)
	if amount <= 0:
		return {"needs": false}
	var iid := str(building.get("instance_id", ""))
	var ran := iid != "" and Production.last_turn_run.has(iid)
	var connected := Power.is_supplied(str(building.get("tile_id", "")), amount)
	var state := "none"
	if ran:
		state = "own" if BuildingStatus.power_supply(building) == "Owned Supply" else "grid"
	elif connected:
		state = "ready"
	return {"needs": true, "amount": amount, "ran": ran, "connected": connected, "state": state}

static func power_state_text(state: String) -> String:
	match state:
		"own": return "your own supply"
		"grid": return "grey from the national grid"
		"ready": return "ready to draw from the grid"
		_: return "no power connection"

# --- Diagnostics checklist (the always-open triage list) ----------------------------------
# Each row: { tone, ic, label, detail }. Built entirely from the shared status helpers so it
# never disagrees with the RAG rail, the ledger, or the Empire view.

static func diagnostics(building: Dictionary, recipe: Dictionary, building_data: Dictionary, is_infrastructure: bool) -> Array:
	var rows: Array = []
	var iid := str(building.get("instance_id", ""))
	if Middleman.uses_inputs(iid):
		var p := Middleman.preview(iid)
		return [_row("ok" if bool(p.get("can_run",false)) else "warn","truck","Middleman service",str(p.get("reason","Unavailable")))]
	var exhausted := BuildingStatus.recipe_deposit_exhausted(building, recipe)
	var ran := iid != "" and Production.last_turn_run.has(iid)
	var missing := iid != "" and Production.missing_by_building.has(iid)
	var stockpile_gap_detail := _stockpile_input_gap_detail(building, recipe)
	var power_c := BuildingStatus.power_status_color(building, recipe, is_infrastructure)
	var input_c := BuildingStatus.input_status_color(building, recipe, is_infrastructure)
	var produces_power := str(recipe.get("output_name", "")) == "power"
	var needs_power := BuildingStatus.effective_energy_req(building, recipe) > 0
	var has_inputs := not (recipe.get("inputs", []) as Array).is_empty()
	var rs := run_state(building, recipe, is_infrastructure)
	# Two "not running yet" cases share run_state "restarting": inputs are all in stock (true
	# restart next turn), or they are short on-tile but arriving (a timing gap). The messages differ.
	var has_all := has_inputs and has_all_inputs(building, recipe)
	var inbound_case := rs == "restarting" and has_inputs and not has_all
	var tile_id := str(building.get("tile_id", ""))
	var upgrade_progress := BuildingWorks.upgrade_progress_snapshot(iid)
	var upgrade_blocked := bool(upgrade_progress.get("blocked", false))
	var upgrade_fault_label := "Cannot deliver upgrade materials"
	# A power PRODUCER whose "missing" entry is power = the cable export cap blocked its
	# dispatch (production._can_run_recipe's can_produce branch) — not an input problem.
	var grid_blocked := produces_power and _power_output_capped(iid)

	# 1) critical fault / restarting / all-clear
	if exhausted:
		rows.append(_row("bad", "warn", "Deposit exhausted", "The deposit is exhausted. This building cannot produce with its current recipe."))
	elif not _deposit_runway(iid).is_empty():
		# AMBER: the deposit is nearly gone. Warned rather than faulted — the mine is still
		# producing normally today. Without it exhaustion arrives with no notice at all: the
		# input bill simply doubles as the chain begins buying what it had been mining.
		var dr: Dictionary = _deposit_runway(iid)
		rows.append(_row_good("warn", "warn", str(dr.get("good_id", "")),
			"Deposit running out",
			"About %d turn%s of %s left here (%d units at %d/turn). Build a replacement mine on another deposit before this one stops — construction takes turns you won't have afterwards." % [
				int(dr.get("turns_left", 0)), "" if int(dr.get("turns_left", 0)) == 1 else "s",
				str(dr.get("token", "")).replace("_", " "),
				int(dr.get("remaining", 0)), int(dr.get("per_turn", 0))]))
	elif grid_blocked:
		# AMBER, and checked BEFORE "restarting": a capped plant reports run_state
		# "restarting" (its power "input" is unmet), so checked the other way round it shows
		# a cheerful "Starting — production begins next turn" forever while actually
		# throttled by the tile's cable capacity, never starting.
		rows.append(_row("warn", "bolt", "Power output capped", _cable_cap_detail(building, recipe, tile_id)))
	elif rs == "restarting":
		if inbound_case:
			rows.append(_row("warn", "clock", "Starting",
				"Insufficient inputs, but more are on the way — production begins once they land.  " + _missing_inputs_detail(building, recipe)))
		else:
			rows.append(_row("warn", "clock", "Starting", "All inputs received and powered — production begins next turn."))
	elif needs_power and power_c == BuildingStatus.STATUS_RED:
		rows.append(_row("bad", "warn", "Critical fault", "This building doesn't have power. It can't run."))
	elif has_inputs and input_c == BuildingStatus.STATUS_RED:
		rows.append(_row("bad", "warn", "Cannot run", stockpile_gap_detail if stockpile_gap_detail != "" else "Not enough inputs to run the recipe this turn."))
	elif missing:
		rows.append(_row("bad", "warn", "Critical fault", stockpile_gap_detail if stockpile_gap_detail != "" else "Missing required inputs — the recipe could not run this turn."))
	elif upgrade_blocked:
		rows.append(_row("bad", "box", upgrade_fault_label, str(upgrade_progress.get("error", "The upgrade is unable to continue."))))
	else:
		rows.append(_row("ok", "check", "No critical faults", "Operating normally." if ran else "Ready to run."))
	# Keep the upgrade fault visible alongside a production fault instead of letting the first
	# red row hide a separate stalled project.
	if upgrade_blocked and (rows.is_empty() or str((rows[0] as Dictionary).get("label", "")) != upgrade_fault_label):
		rows.append(_row("bad", "box", upgrade_fault_label, str(upgrade_progress.get("error", "The upgrade is unable to continue."))))

	# 2) power
	if produces_power:
		if grid_blocked:
			rows.append(_row("warn", "bolt", "Power output capped", _cable_cap_detail(building, recipe, tile_id)))
		else:
			rows.append(_row("ok", "bolt", "Generating power", "%d MW / turn" % BuildingStatus.effective_power_output(building, recipe)))
	elif needs_power:
		var pw := power(building, recipe)
		var st := str(pw.get("state", "none"))
		var amt := int(pw.get("amount", 0))
		if st == "none":
			rows.append(_row("bad", "bolt", "Unpowered", "This building doesn't have power. It can't run."))
		elif st == "ready":
			rows.append(_row("warn", "bolt", "Ready to draw power", "%d MW ready to draw from the grid once it runs." % amt))
		else:
			rows.append(_row("ok" if st == "own" else "warn", "bolt", "Powered", "%d MW drawn · %s" % [amt, power_state_text(st)]))

	# 2b) green-power intermittency — only for green generators / green-power consumers; skipped
	# for buildings that only supply or draw grey (coal/gas/oil) power.
	var intermit := _intermittency_row(building, recipe, is_infrastructure)
	if not intermit.is_empty():
		rows.append(intermit)

	# 3) inputs
	if has_inputs and not exhausted:
		if inbound_case:
			rows.append(_row("warn", "box", "Inputs on the way", _missing_inputs_detail(building, recipe)))
		elif rs == "restarting" or input_c == BuildingStatus.STATUS_GREEN:
			rows.append(_row("ok", "box", "Inputs in stock" if rs == "restarting" else "Receiving inputs",
				"All inputs are in stock, ready for the next run." if rs == "restarting" else "All inputs were in stock this turn."))
		elif input_c == BuildingStatus.STATUS_RED:
			rows.append(_row("bad", "box", "Starved of inputs", stockpile_gap_detail if stockpile_gap_detail != "" else _missing_inputs_detail(building, recipe)))
		else:
			rows.append(_row("warn", "box", "Inputs idle", "Inputs are present but the building did not run this turn."))

		# 3b) where inputs come from (grey until sourced, then own=green / market=amber / missing=red)
		var src_row := _input_sourcing_row(building, recipe, ran, input_c, rs)
		if str(src_row.get("detail", "")) != "":
			rows.append(_row(str(src_row.get("tone", "info")), "src", "Input sourcing", str(src_row.get("detail", ""))))

		# 3c) stockpile over-utilised (non-power producers): the tile warehouse is full,
		# so arriving inputs bounce and the recipe can't restock. Critical when the
		# building is actually starved; a warning while it still has stock to burn.
		if not produces_power:
			var wh_cap := Stockpile.get_capacity(tile_id)
			var wh_used := Stockpile.get_used_capacity(tile_id)
			if wh_cap > 0 and wh_used >= wh_cap:
				var inbound := 0
				for s in TransportState.get_inbound_transport_shipments(tile_id):
					inbound += int(s.get("qty", 0))
				var detail := "The tile's warehouse is full (%d/%d) — arriving inputs can't unload." % [wh_used, wh_cap]
				if inbound > 0:
					detail += " %d unit%s in transit are waiting." % [inbound, "" if inbound == 1 else "s"]
				detail += " Expand the warehouse (Stockpile tab) or clear stock."
				rows.append(_row("bad" if input_c == BuildingStatus.STATUS_RED else "warn", "box",
					"Stockpile over-utilised", detail))
		# 3c) Fluid/gas transport. Road tankers and rail tank wagons are valid, so missing
		# pipework is only RED when there is no supported route at all. A working overland
		# route gets an AMBER cost recommendation because pipework is still much cheaper.
		for fluid_problem in _fluid_input_transport_problems(building, recipe):
			var gid := str((fluid_problem as Dictionary).get("good_id", ""))
			var good_name := Catalog.get_display_name(gid)
			var reinforced := bool((fluid_problem as Dictionary).get("reinforced", false))
			var pipe_name := "Reinforced Pipeline" if reinforced else "Pipeline"
			var pipe_phrase := "a reinforced pipeline" if reinforced else "a pipeline"
			if bool((fluid_problem as Dictionary).get("blocked", false)):
				rows.append(_row_good("bad", "pipe", gid, "No transport route for %s" % good_name,
					"%s cannot reach this building. Connect it to its source or the market port by road, rail or %s." % [good_name, pipe_phrase]))
			else:
				rows.append(_row_good("warn", "pipe", gid, "Transport could be cheaper using %s" % pipe_name,
					"%s can reach this building by road or rail, but %s would carry it more cheaply." % [good_name, pipe_phrase]))
		# 3d) how far the inputs travel
		var far := _input_distance_text(building, recipe)
		if not far.is_empty():
			rows.append(_row(str(far.get("tone", "ok")), "clock", str(far.get("label", "")), str(far.get("detail", ""))))

	# 4) output destination — reachability band + transport-cost band. Uses the market-aware
	# output_route so the bands also render for market-routed output (route to the nearest port).
	# Skipped for buildings with no shippable output good (batteries, infra, power generators).
	if not is_infrastructure and not produces_power and BuildingStatus.primary_output_good_id(recipe) != "":
		var route := output_route(building, recipe)
		var turns := int(route.get("turns", 0))
		var cost := float(route.get("cost", 0.0))
		var qty := maxi(1, BuildingStatus.primary_output_qty(recipe))
		var dest_name := str(route.get("destination", "the destination"))
		if not bool(route.get("reachable", true)):
			rows.append(_row("bad", "truck", "Outputs cannot reach destination",
				"Check infrastructure and connection to %s. Nothing ships (and no transport is charged) until a road, rail or suitable pipe route exists." % dest_name))
		else:
			var reach := "easily reached" if turns <= 1 else ("moderate to reach" if turns <= 4 else "hard to reach")
			var reach_tone := "ok" if turns <= 1 else ("warn" if turns <= 4 else "bad")
			rows.append(_row(reach_tone, "truck", "Output destination %s" % reach, "%d turn%s to %s." % [turns, "" if turns == 1 else "s", dest_name]))
			var per_unit := cost / float(qty)
			var band := "cheap" if per_unit < 0.15 else ("average" if per_unit < 0.4 else "expensive")
			# Expensive freight needs attention, but it is still a viable route. Reserve
			# red for a route that cannot reach the destination at all.
			var band_tone := "ok" if per_unit < 0.15 else "warn"
			rows.append(_row(band_tone, "truck", "Transport to destination is %s" % band, "£%s / unit shipped · £%.2f / turn." % [_num(per_unit), cost]))

	# 5) cost to produce vs market (the engine's profitability signal)
	if not is_infrastructure:
		var pc := BuildingStatus.produce_cost_status(building)
		var uc := float(pc.get("unit_cost", -1.0))
		var bp := float(pc.get("base_price", 0.0))
		if uc >= 0.0 and bp > 0.0:
			var pct := int(round((uc / bp - 1.0) * 100.0))
			var c: Color = pc.get("color", BuildingStatus.STATUS_GREY)
			if c == BuildingStatus.STATUS_GREEN:
				rows.append(_row("ok", "scale", "Cheaper than market", "Producing at £%s / unit — %d%% below the £%s market price." % [_num(uc), absi(pct), _num(bp)]))
			elif c == BuildingStatus.STATUS_YELLOW:
				rows.append(_row("warn", "scale", "Even with market", "Producing at £%s / unit — about the £%s market price." % [_num(uc), _num(bp)]))
			else:
				rows.append(_row("bad", "scale", "Dearer than market", "Producing at £%s / unit — %d%% above the £%s market price." % [_num(uc), absi(pct), _num(bp)]))

	return rows

# Green-power intermittency status row (or {} for no row). Shown for a GREEN power generator or a
# building that CONSUMES green power. Green = fully safe (firmed by a battery, or steady renewable),
# yellow = partially affected (some power firmed/steady/grey, some unfirmed), red = fully affected
# (all its power is unfirmed intermittent renewable). Grey-only supply/draw shows no row at all.
static func _intermittency_row(building: Dictionary, recipe: Dictionary, is_infrastructure: bool) -> Dictionary:
	if is_infrastructure:
		return {}
	# --- SOURCE: a power generator ---
	if str(recipe.get("output_name", "")) == "power":
		var q := _power_quality_of(building, recipe)
		if q == "grey":
			return {}  # coal / gas / oil generation — no intermittency
		if q == "green_steady":
			return _row("ok", "bolt", "Steady green power", "Firm renewable output (hydro / biomass) — never intermittent.")
		var out := BuildingStatus.effective_power_output(building, recipe)  # green_intermittent
		if out <= 0:
			return {}
		var cap := Power.tile_firming_cap(str(building.get("tile_id", "")))
		if cap >= out:
			return _row("ok", "bolt", "Firmed green generation", "A battery on this tile firms this renewable output — steady supply, safe from intermittency.")
		if cap <= 0:
			return _row("bad", "bolt", "Intermittent generation", "This renewable output isn't firmed — buildings drawing it are derated when the wind/sun drops. Load battery cells to firm it.")
		return _row("warn", "bolt", "Partly firmed generation", "Only part of this renewable output is firmed by a battery — the rest is intermittent.")
	# --- CONSUMER: draws power; classify by the green it actually drew ---
	if BuildingStatus.effective_energy_req(building, recipe) <= 0:
		return {}
	var im := Production.get_building_intermittency(str(building.get("instance_id", "")))
	var green := float(im.get("green_consumed", 0.0))
	if green <= 0.0:
		return {}  # draws only grey power — no intermittency row
	var unfirmed := float(im.get("unfirmed_intermittent", 0.0))
	var demand := float(im.get("demand", green))
	var derate := maxi(1, int(round(float(im.get("derate", 0.0)) * 100.0)))
	# A load-following process takes no derate at all, so it reads as a STANDING benefit rather
	# than the "you got away with it" phrasing of a building that merely happens to be firmed.
	if bool(im.get("intermittency_immune", false)):
		return _row("ok", "bolt", "Follows intermittent power",
			"This process runs straight off unfirmed wind and solar — no derate, and no battery needed to avoid one.")
	if unfirmed <= 0.001:
		return _row("ok", "bolt", "Safe from intermittency", "All the green power it draws is firmed (battery) or steady — no output derate.")
	if demand > 0.0 and unfirmed >= demand - 0.001:
		return _row("bad", "bolt", "Intermittent power — derated", "All its power is unfirmed renewable — output cut up to %d%% during lulls. Add battery firming or a steady/grey source." % derate)
	return _row("warn", "bolt", "Partly intermittent — derated", "Some power is unfirmed renewable — output cut up to %d%% during lulls. Firm it with a battery or add steady power." % derate)

## True when a power plant's output was held back by its tile's cable export cap last turn: its
## "missing" entry is power (production._can_run_recipe's can_produce branch).
static func _power_output_capped(iid: String) -> bool:
	if iid == "":
		return false
	for m in (Production.missing_by_building.get(iid, []) as Array):
		if str(m.get("good_id", "")) == "power":
			return true
	return false

## True when a building's draw didn't fit under its tile's cable import cap last turn: its "missing"
## power entry has the cap as what it had (no cables at all leave it at 0).
static func _power_draw_capped(iid: String) -> bool:
	if iid == "":
		return false
	for m in (Production.missing_by_building.get(iid, []) as Array):
		if str(m.get("good_id", "")) == "power" and int(m.get("have", 0)) > 0:
			return true
	return false

# --- Visual diagnostics: what every stage shares ---------------------------------------------
# The diagnostics' visual view asks for each stage's checks, each {key, label, tone, detail}, and for a
# check over several goods also `tones` (a lamp each, worst first) and sometimes `icon`. Tones come from
# the same helpers as the checklist's rows, so the two views agree. Details are short plain sentences,
# for the readout's two lines.

const _TONE_ORDER := ["bad", "warn", "ok"]
const _TONE_WORDS := {"bad": "red", "warn": "amber", "ok": "green", "off": "unlit"}
## How a route's modes are named.
const MODE_NAMES := {"roads": "road", "rail": "rail", "pipes": "pipeline", "reinf_pipes": "reinforced pipeline"}

static func _check(key: String, label: String, tone: String, detail: String) -> Dictionary:
	return {"key": key, "label": label, "tone": tone, "detail": detail}

## A check about one good: `_check` and the good's name.
static func _good_check(g: Dictionary, key: String, label: String, tone: String, detail: String) -> Dictionary:
	var c := _check(key, label, tone, detail)
	c["name"] = str(g.get("name", ""))
	return c

## One check over several goods: its lamps the distinct tones among them, worst first (at most red,
## amber and green; unlit only when every one is), its tone and icon the worst good's, and its detail
## the worst good's. With several goods it names them all when they share the detail, else it names
## the worst and counts the rest by colour.
static func _combine_goods(key: String, label: String, per_good: Array) -> Dictionary:
	if per_good.is_empty():
		return _check(key, label, "off", "Nothing to check.")
	var tones: Array = []
	for t in _TONE_ORDER:
		for c: Dictionary in per_good:
			if str(c.get("tone", "")) == t and not tones.has(t):
				tones.append(t)
	if tones.is_empty():
		tones = ["off"]
	var rank := func(c: Dictionary) -> int:
		var i := _TONE_ORDER.find(str(c.get("tone", "")))
		return i if i >= 0 else _TONE_ORDER.size()
	var worst: Dictionary = per_good[0]
	for c: Dictionary in per_good:
		if int(rank.call(c)) < int(rank.call(worst)):
			worst = c
	var detail := str(worst.get("detail", ""))
	if per_good.size() > 1 and per_good.all(func(c: Dictionary) -> bool: return str(c.get("detail", "")) == detail):
		detail = "%s: %s" % [_sentence_start(_and_list(per_good.map(func(c: Dictionary) -> String: return str(c.get("name", ""))))), detail]
	elif per_good.size() > 1:
		var rest := {}
		for c: Dictionary in per_good:
			if c != worst:
				var w := str(_TONE_WORDS.get(str(c.get("tone", "")), "unlit"))
				rest[w] = int(rest.get(w, 0)) + 1
		var parts: Array = []
		for w in ["red", "amber", "green", "unlit"]:
			if rest.has(w):
				parts.append("%d %s" % [int(rest[w]), w])
		detail = "%s: %s The rest: %s." % [_sentence_start(str(worst.get("name", ""))), detail, ", ".join(parts)]
	var out := _check(key, label, tones[0], detail)
	out["tones"] = tones
	if worst.has("icon"):
		out["icon"] = worst["icon"]
	return out

## A phrase with its first letter capitalised, to start a sentence.
static func _sentence_start(text: String) -> String:
	return text.substr(0, 1).to_upper() + text.substr(1) if text != "" else text

## "a", "a and b", "a, b and c".
static func _and_list(items: Array) -> String:
	if items.size() <= 1:
		return "".join(items)
	return ", ".join(items.slice(0, items.size() - 1)) + " and " + str(items[-1])

## A place as the readout names it: the tile's name, or its coordinates when it has none.
static func _place(tile_id: String) -> String:
	var n := Catalog.tile_name(tile_id)
	return n if n != "" else Catalog.tile_label(tile_id)

## The modes a route's legs use, in the order they come.
static func _route_modes(route: Dictionary) -> Array:
	var modes: Array = []
	for leg: Dictionary in route.get("legs", []):
		var m := str(leg.get("mode", ""))
		if MODE_NAMES.has(m) and not modes.has(m):
			modes.append(m)
	return modes

## The cheapest kind of infrastructure that suits a good (rail for a solid; pipeline for a fluid, the
## reinforced one where only that will carry it), when its route in `modes` isn't all on it: "" when it
## is, or when nothing cheaper suits it. No cost is worked out: the kinds are ranked by how they charge.
static func _cheaper_mode(gid: String, modes: Array) -> String:
	var allowed: Array = Catalog._modes_for_good(gid)
	var cheapest: Array = []
	if Catalog.requires_pipeline(gid):
		cheapest = ["pipes", "reinf_pipes"].filter(func(m: String) -> bool: return allowed.has(m))
	elif allowed.has("rail"):
		cheapest = ["rail"]
	if cheapest.is_empty():
		return ""
	if modes.is_empty() or modes.any(func(m: String) -> bool: return not cheapest.has(m)):
		return str(cheapest[0])
	return ""

## How a good travels, as a per-good check: amber when a cheaper kind of infrastructure suits it, green
## when it already goes on the cheapest. `verb` and `where` make the sentence ("Comes", " from the market").
static func _mode_check(g: Dictionary, key: String, label: String, modes: Array, verb: String, where: String) -> Dictionary:
	var by := ("by " + _and_list(modes.map(func(m: String) -> String: return str(MODE_NAMES[m])))) if not modes.is_empty() else "across open country"
	var cheaper := _cheaper_mode(str(g.get("gid", "")), modes)
	if cheaper != "":
		return _good_check(g, key, label, "warn", "%s %s%s. %s would be cheaper." % [verb, by, where, str(MODE_NAMES[cheaper]).capitalize()])
	return _good_check(g, key, label, "ok", "%s %s%s, the cheapest way that suits it." % [verb, by, where])

## The kind of route to build for a good that has none: the cheapest that suits it.
static func _route_to_build(gid: String) -> String:
	return str(MODE_NAMES.get(_cheaper_mode(gid, []), "road, rail or pipe"))

# --- Power checks (the diagnostics' visual view) ---------------------------------------------
# Three checks: where the building's power comes from, whether it is exposed to intermittent green power,
# and whether its tile's cables carry what it draws or makes. A building that neither uses nor makes
# power has all three unlit.

## Cable load at or above this share of the tile's cap reads amber: little room left.
const CABLE_NEAR_FULL := 0.9

static func power_checks(building: Dictionary, recipe: Dictionary, is_infrastructure: bool) -> Array:
	var produces_power := str(recipe.get("output_name", "")) == "power"
	var draw := BuildingStatus.effective_energy_req(building, recipe)
	if is_infrastructure or (not produces_power and draw <= 0):
		var none := "Uses no power and makes none."
		return [_check("power_supply", "Power supply", "off", none), _check("intermittency", "Intermittency", "off", none),
			_check("cable", "Cable capacity", "off", none)]
	return [_supply_check(building, recipe, produces_power), _intermittency_check(building, recipe, produces_power),
		_cable_check(building, recipe, produces_power, draw)]

static func _supply_check(building: Dictionary, recipe: Dictionary, produces_power: bool) -> Dictionary:
	if produces_power:
		var out := BuildingStatus.effective_power_output(building, recipe)
		if _power_output_capped(str(building.get("instance_id", ""))):
			return _check("power_supply", "Power supply", "warn", "Makes up to %d MW a turn, but its cables cannot carry it all." % out)
		return _check("power_supply", "Power supply", "ok", "Makes %d MW a turn." % out)
	var pw := power(building, recipe)
	var amt := int(pw.get("amount", 0))
	match str(pw.get("state", "none")):
		"own":
			return _check("power_supply", "Power supply", "ok", "%d MW from your own generation." % amt)
		"grid":
			return _check("power_supply", "Power supply", "warn", "%d MW bought from the national grid." % amt)
		"ready":
			return _check("power_supply", "Power supply", "warn", "Needs %d MW. It will draw from the national grid once it runs." % amt)
		_:
			return _check("power_supply", "Power supply", "bad", "Needs %d MW and has no power connection. Build cables on this tile." % amt)

## The checklist's intermittency row (its tone), said briefly.
const _INTERMITTENCY_SHORT := {
	"Steady green power": "Hydro or biomass. Never intermittent.",
	"Firmed green generation": "Renewable output, fully firmed by batteries on this tile.",
	"Intermittent generation": "Renewable output with no firming. Buildings using it lose output when wind or sun drops. Load battery cells.",
	"Partly firmed generation": "Renewable output, only partly firmed by batteries.",
	"Follows intermittent power": "Runs on unfirmed wind and solar with no loss of output.",
	"Safe from intermittency": "Its green power is firmed or steady. No loss of output.",
	"Intermittent power — derated": "Runs on unfirmed renewable power. Output falls by up to %d%% in lulls. Add batteries or steady power.",
	"Partly intermittent — derated": "Partly runs on unfirmed renewable power. Output falls by up to %d%% in lulls. Add batteries.",
}

static func _intermittency_check(building: Dictionary, recipe: Dictionary, produces_power: bool) -> Dictionary:
	var row := _intermittency_row(building, recipe, false)
	if row.is_empty():
		if produces_power:
			if _power_quality_of(building, recipe) == "grey":
				return _check("intermittency", "Intermittency", "ok", "Coal, gas or oil generation. Never intermittent.")
			return _check("intermittency", "Intermittency", "off", "Not generating this turn.")
		if Production.last_turn_run.has(str(building.get("instance_id", ""))):
			return _check("intermittency", "Intermittency", "ok", "Draws only coal, gas or oil power. Never intermittent.")
		return _check("intermittency", "Intermittency", "off", "Has not drawn power yet.")
	var detail := str(_INTERMITTENCY_SHORT.get(str(row.get("label", "")), row.get("detail", "")))
	if detail.contains("%d"):
		var im := Production.get_building_intermittency(str(building.get("instance_id", "")))
		detail = detail % maxi(1, int(round(float(im.get("derate", 0.0)) * 100.0)))
	return _check("intermittency", "Intermittency", str(row.get("tone", "info")), detail)

static func _cable_check(building: Dictionary, recipe: Dictionary, produces_power: bool, draw: int) -> Dictionary:
	var tile_id := str(building.get("tile_id", ""))
	var iid := str(building.get("instance_id", ""))
	var cap := Power.tile_power_cap(tile_id)
	if cap <= 0:
		return _check("cable", "Cable capacity", "bad", "No cables on this tile. Power cannot reach it or leave it.")
	var more := " The cables are at their top level." if Power.cable_level_is_max(tile_id) else " Upgrade the cables for more."
	if produces_power:
		var made := int(Power.tile_produced.get(tile_id, 0))
		if _power_output_capped(iid):
			return _check("cable", "Cable capacity", "warn", "Cables full. %s of %s MW leave this tile and this plant's %s MW cannot.%s" % [
				_fmt_count(made), _fmt_count(cap), _fmt_count(BuildingStatus.effective_power_output(building, recipe)), more])
		var near := float(made) >= CABLE_NEAR_FULL * float(cap)
		return _check("cable", "Cable capacity", "warn" if near else "ok", "This tile sends out %s of the %s MW its cables carry.%s" % [
			_fmt_count(made), _fmt_count(cap), more if near else ""])
	if draw > cap:
		return _check("cable", "Cable capacity", "bad", "Needs %s MW. The cables here carry at most %s MW.%s" % [_fmt_count(draw), _fmt_count(cap), more])
	if _power_draw_capped(iid):
		return _check("cable", "Cable capacity", "bad", "Cables full. The tile can draw %s MW, not enough for this building's %s MW as well.%s" % [_fmt_count(cap), _fmt_count(draw), more])
	var drawn := int(Power.tile_drawn.get(tile_id, 0))
	var near_in := float(drawn) >= CABLE_NEAR_FULL * float(cap)
	return _check("cable", "Cable capacity", "warn" if near_in else "ok", "Needs %s MW. The tile draws %s of the %s MW its cables carry.%s" % [
		_fmt_count(draw), _fmt_count(drawn), _fmt_count(cap), more if near_in else ""])

# --- Input checks (the diagnostics' visual view) ---------------------------------------------
# Four checks: where each input comes from (a lamp for each), how long the stock on the tile lasts,
# whether the company's own supplying buildings are running, and, for a mine, how much of its deposit
# is left. A building that takes no inputs has the first three unlit; one that mines nothing, the last.

static func input_checks(building: Dictionary, recipe: Dictionary, is_infrastructure: bool) -> Array:
	var deposit := _deposit_check(building, recipe)
	if is_infrastructure or (recipe.get("inputs", []) as Array).is_empty():
		var none := "Takes no inputs."
		return [_check("source", "Source", "off", none), _check("stock", "Stock cover", "off", none),
			_check("upstream", "Upstream health", "off", none), deposit]
	return [_source_check(building, recipe, is_infrastructure), _stock_check(building, recipe, is_infrastructure),
		_upstream_check(building, recipe), deposit]

## Each input's source, a lamp for each: green from the company's own buildings or the intermediary,
## amber bought at the market, red when not enough reaches it to run (the checklist's starved signal).
static func _source_check(building: Dictionary, recipe: Dictionary, is_infrastructure: bool) -> Dictionary:
	var iid := str(building.get("instance_id", ""))
	var ran := iid != "" and Production.last_turn_run.has(iid)
	var row := _input_sourcing_row(building, recipe, ran, BuildingStatus.input_status_color(building, recipe, is_infrastructure),
		run_state(building, recipe, is_infrastructure))
	var tone := str(row.get("tone", "info"))
	if tone == "info":
		return _check("source", "Source", "off", "Nothing sourced yet.")
	var linked := {}
	for src: Dictionary in input_sources(building, recipe):
		linked[str(src.get("good_id", ""))] = true
	var short := {}
	if tone == "bad":
		for sh: Dictionary in shipments(building, recipe):
			if int(sh.get("stored", 0)) < int(sh.get("need", 0)):
				short[str(sh.get("good_id", ""))] = true
	var per: Array = []
	for inp: Dictionary in recipe.get("inputs", []):
		var gid := str(inp.get("good_id", ""))
		var g := {"gid": gid, "name": Catalog.get_display_name(gid).to_lower()}
		if short.has(gid):
			per.append(_good_check(g, "source", "Source", "bad", "Not enough reaches it to run."))
		elif Middleman.supplies_good(iid, gid):
			per.append(_good_check(g, "source", "Source", "ok", "Brought by the logistics intermediary."))
		elif linked.has(gid):
			per.append(_good_check(g, "source", "Source", "ok", "From your own buildings."))
		else:
			per.append(_good_check(g, "source", "Source", "warn", "Bought at the market."))
	return _combine_goods("source", "Source", per)

static func _stock_check(building: Dictionary, recipe: Dictionary, is_infrastructure: bool) -> Dictionary:
	var short_none: Array = []
	var short_arriving: Array = []
	var cover := -1
	var scarcest: Dictionary = {}
	var counted := 0
	for sh: Dictionary in shipments(building, recipe):
		var need := int(sh.get("need", 0))
		if need <= 0:
			continue
		counted += 1
		var stored := int(sh.get("stored", 0))
		var inbound := int(sh.get("inbound", 0))
		if stored < need:
			if inbound > 0 and stored + inbound >= need:
				short_arriving.append(sh)
			else:
				short_none.append(sh)
			continue
		var runs := stored / need
		if cover < 0 or runs < cover:
			cover = runs
			scarcest = sh
	if counted == 0:
		return _check("stock", "Stock cover", "off", "Uses up none of its inputs.")
	if not short_none.is_empty():
		var s0: Dictionary = short_none[0]
		var starved := BuildingStatus.input_status_color(building, recipe, is_infrastructure) == BuildingStatus.STATUS_RED \
			and run_state(building, recipe, is_infrastructure) != "restarting"
		var coming := int(s0.get("inbound", 0))
		return _check("stock", "Stock cover", "bad" if starved else "warn", "Short of %s for the next run. %d of %d on the tile, %s." % [
			str(s0.get("name", "")).to_lower(), int(s0.get("stored", 0)), int(s0.get("need", 0)),
			"%d more on the way" % coming if coming > 0 else "none on the way"])
	if not short_arriving.is_empty():
		var a: Dictionary = short_arriving[0]
		var eta := int(a.get("eta_turns", -1))
		return _check("stock", "Stock cover", "warn", "Short of %s on the tile. %d arrive %s." % [
			str(a.get("name", "")).to_lower(), int(a.get("inbound", 0)), "next turn" if eta <= 1 else "in %d turns" % eta])
	var name := str(scarcest.get("name", ""))
	var runs_txt := "%d run%s" % [cover, "" if cover == 1 else "s"]
	var eta_s := int(scarcest.get("eta_turns", -1))
	if int(scarcest.get("inbound", 0)) > 0 and eta_s > cover:
		return _check("stock", "Stock cover", "warn", "Its %s covers %s. The next delivery lands in %d turns." % [name.to_lower(), runs_txt, eta_s])
	if counted == 1:
		return _check("stock", "Stock cover", "ok", "Stock covers %s." % runs_txt)
	return _check("stock", "Stock cover", "ok", "Stock covers %s. %s runs short first." % [runs_txt, _sentence_start(name.to_lower())])

static func _upstream_check(building: Dictionary, recipe: Dictionary) -> Dictionary:
	var iid := str(building.get("instance_id", ""))
	var tile := str(building.get("tile_id", ""))
	var rank := {"ok": 0, "good": 0, "warn": 1, "bad": 2}
	var found := 0
	var worst_rank := -1
	var worst := ""
	for inp: Dictionary in recipe.get("inputs", []):
		if Middleman.supplies_good(iid, str(inp.get("good_id", ""))):
			continue
		for producer: Dictionary in _producers_for_input(inp, iid, tile):
			if not BuildingState.is_player_owned(producer):
				continue
			found += 1
			var pdata := Catalog.get_building(str(producer.get("building_id", "")))
			var st := status(producer, Catalog.get_recipe(str(producer.get("recipe_id", ""))), str(pdata.get("category", "")).to_lower() == "infrastructure")
			var r := int(rank.get(str(st.get("tone", "ok")), 0))
			if r > worst_rank:
				worst_rank = r
				worst = "Your %s at %s, making %s, is %s." % [str(pdata.get("display_name", "supplier")).to_lower(),
					_place(str(producer.get("tile_id", ""))), Catalog.get_display_name(str(inp.get("good_id", ""))).to_lower(),
					str(st.get("label", "")).to_lower()]
	if found == 0:
		return _check("upstream", "Upstream health", "off", "Every input is bought. No supplier of yours to watch.")
	if worst_rank <= 0:
		return _check("upstream", "Upstream health", "ok", "Your %d supplier%s %s running." % [found, "" if found == 1 else "s", "is" if found == 1 else "are"])
	return _check("upstream", "Upstream health", "warn" if worst_rank == 1 else "bad", worst)

static func _deposit_check(building: Dictionary, recipe: Dictionary) -> Dictionary:
	var token := Production._recipe_deposit_token(recipe)
	if token == "":
		return _check("deposit", "Deposit left", "off", "Not a mine.")
	var tile := str(building.get("tile_id", ""))
	var name := token.replace("_", " ")
	if BuildingStatus.recipe_deposit_exhausted(building, recipe) or MatchState.deposit_depleted(tile, token):
		return _check("deposit", "Deposit left", "bad", "The %s deposit is exhausted. This recipe cannot produce here any more." % name)
	var runway := _deposit_runway(str(building.get("instance_id", "")))
	if not runway.is_empty():
		var t := int(runway.get("turns_left", 0))
		return _check("deposit", "Deposit left", "warn", "About %d turn%s of %s left, %d at %d a turn. Build a replacement mine elsewhere." % [
			t, "" if t == 1 else "s", name, int(runway.get("remaining", 0)), int(runway.get("per_turn", 0))])
	var remaining := MatchState.deposit_remaining_for(tile, token)
	if remaining < 0:
		return _check("deposit", "Deposit left", "ok", "The %s deposit never runs out." % name)
	var per_turn := maxi(1, BuildingStatus.primary_output_qty(recipe))
	return _check("deposit", "Deposit left", "ok", "About %d turns of %s left, %d in the ground." % [remaining / per_turn, name, remaining])

# --- Inbound checks (the diagnostics' visual view) -------------------------------------------
# Four checks: how each input travels in (a lamp for each: red with no route, amber when a cheaper kind
# of infrastructure suits it), whether the tile's warehouse has room to unload, how long inputs take to
# arrive, and what bringing them in costs. `econ` is BuildingEconomics.per_turn(building): freight's tone
# is its input transport lamp. A building that takes no inputs has all four unlit.

## Warehouse use at or above this share of its capacity reads amber: little room left to unload.
const WAREHOUSE_NEAR_FULL := 0.9

static func inbound_checks(building: Dictionary, recipe: Dictionary, is_infrastructure: bool, econ: Dictionary = {}) -> Array:
	if is_infrastructure or (recipe.get("inputs", []) as Array).is_empty():
		var none := "Takes no inputs."
		return [_check("route", "Route and mode", "off", none), _check("warehouse", "Warehouse room", "off", none),
			_check("transit", "Transit time", "off", none), _check("freight", "Freight cost", "off", none)]
	var routes := _input_routes(building, recipe)
	return [_route_check(building, recipe, routes), _warehouse_check(building, recipe), _transit_check(routes), _freight_check(econ)]

## How each input reaches the building: [{good_id, name, turns (-1 when unknown), reachable, from,
## route}]. An input from the company's own buildings takes its nearest producer's route; one bought
## takes the market's quote; one the logistics intermediary brings has no route of its own.
static func _input_routes(building: Dictionary, recipe: Dictionary) -> Array:
	var tile := str(building.get("tile_id", ""))
	var iid := str(building.get("instance_id", ""))
	var out: Array = []
	for inp: Dictionary in recipe.get("inputs", []):
		var gid := str(inp.get("good_id", ""))
		if gid == "":
			continue
		var row := {"good_id": gid, "name": Catalog.get_display_name(gid).to_lower(), "turns": -1, "reachable": true, "from": "", "route": {}}
		if Middleman.supplies_good(iid, gid):
			row["from"] = "the logistics intermediary"
		elif MatchState.is_input_tile_only(iid, gid):
			row["from"] = "your own buildings"
			for producer: Dictionary in _producers_for_input(inp, iid, tile):
				var src := str(producer.get("tile_id", ""))
				var t := 0
				var r := {}
				if src != tile:
					r = TransportService.route(src, tile, gid)
					t = int(r.get("turns", 0)) if TransportService.route_is_reachable(r) else -1
				if t >= 0 and (int(row["turns"]) < 0 or t < int(row["turns"])):
					row["turns"] = t
					row["route"] = r
					row["from"] = "this tile" if t == 0 else _place(src)
		else:
			row["from"] = "the market"
			var q := TransportService.quote_market_buy(tile, gid, maxi(1, int(inp.get("qty", 1))), TransportState.seaport_would_cover(gid))
			if q.is_empty():
				row["reachable"] = false
			else:
				row["turns"] = int(q.get("turns", 0))
				row["route"] = q.get("route", {})
		out.append(row)
	return out

## How each input travels in, a lamp for each: red with no route in, amber when a cheaper kind of
## infrastructure suits it, green when it already comes the cheapest way or needs no travel.
static func _route_check(building: Dictionary, recipe: Dictionary, routes: Array, _econ: Dictionary = {}) -> Dictionary:
	var blocked := {}
	for f: Dictionary in _fluid_input_transport_problems(building, recipe):
		if bool(f.get("blocked", false)):
			blocked[str(f.get("good_id", ""))] = true
	var per: Array = []
	for r: Dictionary in routes:
		var gid := str(r.get("good_id", ""))
		var g := {"gid": gid, "name": Catalog.get_display_name(gid).to_lower() if gid != "" else str(r.get("name", ""))}
		var from := str(r.get("from", ""))
		var modes := _route_modes(r.get("route", {}))
		if from == "the logistics intermediary":
			per.append(_good_check(g, "route", "Route and mode", "ok", "Brought by the logistics intermediary."))
		elif not bool(r.get("reachable", true)) or blocked.has(gid):
			per.append(_good_check(g, "route", "Route and mode", "bad", "No route in. Connect the tile by %s." % _route_to_build(gid)))
		elif from == "this tile":
			per.append(_good_check(g, "route", "Route and mode", "ok", "Made on this tile."))
		elif int(r.get("turns", -1)) < 0:
			per.append(_good_check(g, "route", "Route and mode", "ok", "Drawn from this tile's stockpile."))
		elif modes.is_empty() and int(r.get("turns", 0)) == 0:
			per.append(_good_check(g, "route", "Route and mode", "ok", "Lands at the port on this tile."))
		else:
			per.append(_mode_check(g, "route", "Route and mode", modes, "Comes", " from %s" % from))
	return _combine_goods("route", "Route and mode", per)

static func _warehouse_check(building: Dictionary, recipe: Dictionary) -> Dictionary:
	var tile := str(building.get("tile_id", ""))
	var cap := Stockpile.get_capacity(tile)
	var used := Stockpile.get_used_capacity(tile)
	if cap <= 0:
		return _check("warehouse", "Warehouse room", "off", "No warehouse on this tile.")
	if used >= cap:
		var inbound := 0
		for sh: Dictionary in TransportState.get_inbound_transport_shipments(tile):
			inbound += int(sh.get("qty", 0))
		var starved := BuildingStatus.input_status_color(building, recipe, false) == BuildingStatus.STATUS_RED
		var waiting := " %d unit%s wait in transit." % [inbound, "" if inbound == 1 else "s"] if inbound > 0 else ""
		return _check("warehouse", "Warehouse room", "bad" if starved else "warn",
			"Warehouse full, %s of %s. Arriving inputs cannot unload.%s" % [_fmt_count(used), _fmt_count(cap), waiting])
	if float(used) >= WAREHOUSE_NEAR_FULL * float(cap):
		return _check("warehouse", "Warehouse room", "warn", "Warehouse nearly full, %s of %s used." % [_fmt_count(used), _fmt_count(cap)])
	return _check("warehouse", "Warehouse room", "ok", "Warehouse holds %s of %s. Room for deliveries." % [_fmt_count(used), _fmt_count(cap)])

static func _transit_check(routes: Array) -> Dictionary:
	var worst: Dictionary = {}
	var via_intermediary := false
	for r: Dictionary in routes:
		if str(r.get("from", "")) == "the logistics intermediary":
			via_intermediary = true
		if int(r.get("turns", -1)) >= 0 and (worst.is_empty() or int(r.turns) > int(worst.turns)):
			worst = r
	if worst.is_empty():
		if via_intermediary:
			return _check("transit", "Transit time", "ok", "The logistics intermediary delivers its inputs.")
		return _check("transit", "Transit time", "off", "No route in yet.")
	var t := int(worst.turns)
	if t == 0 and routes.all(func(r: Dictionary) -> bool: return str(r.get("from", "")) == "this tile"):
		return _check("transit", "Transit time", "ok", "Every input is made on this tile.")
	if t == 0:
		return _check("transit", "Transit time", "ok", "Inputs arrive the turn they are bought.")
	if t <= 1:
		return _check("transit", "Transit time", "ok", "Inputs arrive within a turn.")
	return _check("transit", "Transit time", "warn" if t <= 4 else "bad", "Slowest is %s, %d turns from %s." % [str(worst.name), t, str(worst.from)])

static func _freight_check(econ: Dictionary) -> Dictionary:
	if not bool(econ.get("shown", false)):
		return _check("freight", "Freight cost", "off", "No figures yet.")
	var cost := float(econ.get("transport_in", 0.0))
	var value := float(econ.get("input_value", 0.0))
	if bool(econ.get("inputs_free", false)) or cost <= 0.0:
		return _check("freight", "Freight cost", "ok", "Bringing its inputs in costs nothing.")
	var share := cost / value * 100.0 if value > 0.0 else 100.0
	return _check("freight", "Freight cost", str(econ.get("lamp_in", "ok")), "£%.2f a turn to bring inputs in, %d%% of their value." % [cost, roundi(share)])

# --- Output checks (the diagnostics' visual view) --------------------------------------------
# Five checks, each over every good the recipe makes, a lamp for each tone among them: how each travels
# (amber when a cheaper kind of infrastructure suits it, never red), how long it takes (red when it cannot
# reach its destination), what shipping it costs a unit, how close the port it sells through is to its
# throughput cap, and how it sells (stock piling up unsold, or else its price against the glut the
# company's own selling makes). Transit and freight use the checklist's output rows' bands. A building
# that makes no goods to ship (a power plant, a battery, infrastructure) has all five unlit.

## Output stock of at least this many turns' output reads amber: it is piling up. Red from the second.
const UNSOLD_TURNS_AMBER := 3
const UNSOLD_TURNS_RED := 6
## Port traffic from this share of the port's cap for the good's transport class reads amber: the next
## shipments may take it to the cap, where a shipment pays double.
const PORT_NEAR_CAP := 0.9
## How the readout names each transport class.
const TRANSPORT_CLASS_NAMES := {"solid_light": "light solids", "solid_heavy": "heavy solids", "ultra_heavy": "ultra heavy solids",
	"safe_liquid": "safe liquids", "hazard_liquid": "hazardous liquids", "gas": "gases"}
## A sale price this many points or more under its impact free base reads red.
const GLUT_RED_PCT := -10.0
## And amber from this far under it, or whenever the company's selling is pushing it down.
const GLUT_AMBER_PCT := -5.0

static func output_checks(building: Dictionary, recipe: Dictionary, is_infrastructure: bool) -> Array:
	var produces_power := str(recipe.get("output_name", "")) == "power"
	var goods: Array = []
	if not produces_power:
		for o: Dictionary in BuildingStatus.flow_output_items(recipe):
			var gid := str(o.get("good_id", ""))
			if gid == "":
				gid = str(Catalog.get_good_by_internal_name(str(o.get("internal_name", ""))).get("id", ""))
			if gid != "":
				goods.append({"gid": gid, "qty": maxi(1, int(o.get("qty", 1))), "name": Catalog.get_display_name(gid).to_lower()})
	var keys := [["reach", "Reach"], ["transit_out", "Transit time"], ["freight_out", "Freight cost"], ["port", "Port charge"], ["sales", "Sales"]]
	if is_infrastructure or goods.is_empty():
		var none := "Its power leaves by cable. See Power." if produces_power else "Makes no goods to ship."
		return keys.map(func(k: Array) -> Dictionary: return _check(str(k[0]), str(k[1]), "off", none))
	var per: Array = [[], [], [], [], []]
	for g: Dictionary in goods:
		var route := output_route(building, recipe, str(g.gid))
		per[0].append(_reach_check(route, building, g))
		per[1].append(_transit_out_check(route, building, g))
		per[2].append(_freight_out_check(route, building, g))
		per[3].append(_port_check(building, route, g))
		per[4].append(_sales_check(building, route, g))
	var out: Array = []
	for i in keys.size():
		out.append(_combine_goods(str(keys[i][0]), str(keys[i][1]), per[i]))
	return out

## How an output route stands: "intermediary", "unreachable", "local" (it stays on this tile, or has
## no port to go to), or "shipped".
static func _output_leg(route: Dictionary, building: Dictionary) -> String:
	if str(route.get("destination", "")) == "Middleman":
		return "intermediary"
	if not bool(route.get("reachable", true)):
		return "unreachable"
	var target := str(route.get("target", ""))
	if target == "" or target == str(building.get("tile_id", "")):
		return "local"
	return "shipped"

## Where an output route goes, as the readout says it: "the market through Stoneshore Docks".
static func _destination(route: Dictionary) -> String:
	var target := str(route.get("target", ""))
	if str(route.get("destination", "")).begins_with("Special Order"):
		return "a special order"
	if bool(route.get("has_market", false)):
		return "the market through %s" % _place(target) if target != "" else "the market"
	return _place(target) if target != "" else "its destination"

static func _reach_check(route: Dictionary, building: Dictionary, g: Dictionary) -> Dictionary:
	var gid := str(g.get("gid", ""))
	match _output_leg(route, building):
		"intermediary":
			return _good_check(g, "reach", "Reach", "ok", "The logistics intermediary collects it.")
		"unreachable":
			return _good_check(g, "reach", "Reach", "warn", "Cannot reach %s. Build a %s route out." % [_destination(route), _route_to_build(gid)])
		"local":
			return _good_check(g, "reach", "Reach", "ok", "Goes to this tile's stockpile. Nothing to ship." if str(route.get("target", "")) != "" else "Goes to the market.")
	var r := TransportService.route(str(building.get("tile_id", "")), str(route.get("target", "")), gid)
	return _mode_check(g, "reach", "Reach", _route_modes(r), "Goes", " to %s" % _destination(route))

static func _transit_out_check(route: Dictionary, building: Dictionary, g: Dictionary) -> Dictionary:
	match _output_leg(route, building):
		"intermediary":
			return _good_check(g, "transit_out", "Transit time", "ok", "The logistics intermediary collects it.")
		"unreachable":
			return _good_check(g, "transit_out", "Transit time", "bad", "No route to %s. Never arrives." % _destination(route))
		"local":
			return _good_check(g, "transit_out", "Transit time", "ok", "No travel. Goes to this tile's stockpile.")
	var t := int(route.get("turns", 0))
	return _good_check(g, "transit_out", "Transit time", "ok" if t <= 1 else ("warn" if t <= 4 else "bad"),
		"%d turn%s to %s." % [t, "" if t == 1 else "s", _destination(route)])

static func _freight_out_check(route: Dictionary, building: Dictionary, g: Dictionary) -> Dictionary:
	match _output_leg(route, building):
		"intermediary":
			return _good_check(g, "freight_out", "Freight cost", "ok", "The logistics intermediary's fee covers it. See Economics.")
		"unreachable":
			return _good_check(g, "freight_out", "Freight cost", "off", "No route out, so no freight.")
		"local":
			return _good_check(g, "freight_out", "Freight cost", "ok", "No freight. Goes to this tile's stockpile.")
	var cost := float(route.get("cost", 0.0))
	var per_unit := cost / float(maxi(1, int(g.get("qty", 1))))
	var band := "Cheap" if per_unit < 0.15 else ("Average" if per_unit < 0.4 else "Expensive")
	return _good_check(g, "freight_out", "Freight cost", "ok" if per_unit < 0.15 else "warn", "£%s a unit to ship, £%.2f a turn. %s." % [_num(per_unit), cost, band])

## The port its outputs are sold through: the port a market route goes to, or the one nearest the
## stockpile they go to, which sells its surplus. "" when they pass no port.
static func _output_port(building: Dictionary, route: Dictionary) -> String:
	if _output_leg(route, building) == "intermediary":
		return ""
	if bool(route.get("has_market", false)):
		return str(route.get("target", ""))
	var lands := str(route.get("target", ""))
	return TransportService.nearest_port_tile(lands if lands != "" else str(building.get("tile_id", "")))

static func _port_check(building: Dictionary, route: Dictionary, g: Dictionary) -> Dictionary:
	var port := _output_port(building, route)
	if port == "":
		var why := "The logistics intermediary ships it. No port charge." if _output_leg(route, building) == "intermediary" else "Passes no port."
		return _good_check(g, "port", "Port charge", "ok", why)
	var gid := str(g.get("gid", ""))
	var kind := Catalog.get_transport_class(gid)
	var kind_name := str(TRANSPORT_CLASS_NAMES.get(kind, kind.replace("_", " ")))
	var cap := TransportState.seaport_throughput_cap(gid)
	var summary := TransportState.seaport_shipping_summary(port)
	var used := int((summary.get("usage", {}) as Dictionary).get(kind, 0))
	var hit := used >= cap
	for row: Dictionary in summary.get("rows", []):
		if str(row.get("transport_class", "")) == kind and bool(row.get("at_cap", false)):
			hit = true
	var where := _place(port)
	if hit:
		return _good_check(g, "port", "Port charge", "bad", "%s handled %s of %s %s this turn. At the cap a shipment pays double." % [where, _fmt_count(used), _fmt_count(cap), kind_name])
	if float(used) >= PORT_NEAR_CAP * float(cap):
		return _good_check(g, "port", "Port charge", "warn", "%s handled %s of %s %s this turn, close to the cap. At the cap a shipment pays double." % [where, _fmt_count(used), _fmt_count(cap), kind_name])
	var owned := bool(summary.get("owned", false))
	return _good_check(g, "port", "Port charge", "ok", "%s handled %s of %s %s this turn. Charge %.1f%%.%s" % [
		where, _fmt_count(used), _fmt_count(cap), kind_name, float(summary.get("insurance_rate", 0.0)) * float(summary.get("growth", 1.0)) * 100.0,
		" The port is yours." if owned else " Owning the port halves it."])

## A count with thousands separated: 1500 becomes "1,500".
static func _fmt_count(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out

## How a good sells: stock piling up unsold when it is (the pallet icon), else its price against the glut
## the company's own selling makes (the coin icon). Only one of the two applies at a time.
static func _sales_check(building: Dictionary, route: Dictionary, g: Dictionary) -> Dictionary:
	var unsold := _unsold_check(building, route, g)
	if str(unsold.get("tone", "")) in ["warn", "bad"]:
		unsold["icon"] = "unsold"
		return unsold
	var glut := _glut_check(building, g)
	glut["icon"] = "glut"
	return glut

static func _glut_check(building: Dictionary, g: Dictionary) -> Dictionary:
	var gid := str(g.get("gid", ""))
	if Middleman.buys_output(str(building.get("instance_id", "")), gid):
		return _good_check(g, "sales", "Sales", "ok", "The logistics intermediary buys it at a contract price.")
	var impact := MarketState.get_impact_pct(gid)
	var th := MarketState.impact_thresholds(gid)
	var net := MarketState.rolling_net_volume(gid)
	var falling := 0.0
	for i in th.size():
		if net > float(th[i]) and i < EconomyConfig.PRICE_IMPACT_LADDER.size():
			falling = float(EconomyConfig.PRICE_IMPACT_LADDER[i][1])
	var where := "at its base price"
	if impact < -0.5:
		where = "%d%% under its base price" % roundi(-impact)
	elif impact > 0.5:
		where = "%d%% over its base price" % roundi(impact)
	var detail := "Sells at £%.2f, %s." % [MarketState.get_price(gid), where]
	if falling > 0.0:
		detail += " Your own selling pushes it down %.1f points a turn." % falling
	var tone := "ok"
	if impact <= GLUT_RED_PCT:
		tone = "bad"
	elif falling > 0.0 or impact <= GLUT_AMBER_PCT:
		tone = "warn"
	return _good_check(g, "sales", "Sales", tone, detail)

static func _unsold_check(building: Dictionary, route: Dictionary, g: Dictionary) -> Dictionary:
	var gid := str(g.get("gid", ""))
	var tile := str(building.get("tile_id", ""))
	var where := tile
	if not bool(route.get("has_market", false)) and str(route.get("target", "")) != "":
		where = str(route.get("target", ""))
	var stock := Stockpile.get_at_tile(where, gid)
	if stock <= 0:
		return _good_check(g, "sales", "Sales", "ok", "Nothing waiting. Moves on as it is made.")
	var place := "on this tile" if where == tile else "at %s" % _place(where)
	var turns := stock / maxi(1, int(g.get("qty", 1)))
	if turns >= UNSOLD_TURNS_RED:
		return _good_check(g, "sales", "Sales", "bad", "%d waiting unsold %s, %d turns of output." % [stock, place, turns])
	if turns >= UNSOLD_TURNS_AMBER:
		return _good_check(g, "sales", "Sales", "warn", "%d waiting unsold %s, %d turns of output." % [stock, place, turns])
	return _good_check(g, "sales", "Sales", "ok", "%d waiting %s." % [stock, place])

# --- Plant checks (the diagnostics' visual view) ---------------------------------------------
# Two checks: the carbon levy the building pays, and works under way on it (an upgrade, a retool or its
# demolition). `econ` is BuildingEconomics.per_turn(building), when the caller has it: it tells a levy
# that tips the building into a loss from one it can carry.

static func plant_checks(building: Dictionary, recipe: Dictionary, is_infrastructure: bool, econ: Dictionary = {}) -> Array:
	return [_carbon_check(building, recipe, is_infrastructure, econ), _works_check(building)]

static func _carbon_check(building: Dictionary, recipe: Dictionary, is_infrastructure: bool, econ: Dictionary) -> Dictionary:
	if is_infrastructure:
		return _check("carbon", "Carbon levy", "off", "Infrastructure pays no carbon levy.")
	if PolicyState.co2_tax_scale(TurnManager.current_turn) <= 0.0:
		return _check("carbon", "Carbon levy", "ok", "No carbon levy in force.")
	var levy := PolicyState.run_carbon_levy(building, recipe)
	if levy <= 0.0:
		return _check("carbon", "Carbon levy", "ok", "Burns nothing the carbon levy taxes.")
	var taxed: Array = []
	for inp: Dictionary in recipe.get("inputs", []):
		var gid := str(inp.get("good_id", ""))
		if float(Catalog.get_good(gid).get("co2_tax_multiplier", 0.0)) > 0.0:
			taxed.append(Catalog.get_display_name(gid).to_lower())
	var on := " on its %s" % _and_list(taxed) if not taxed.is_empty() else ""
	var net := float(econ.get("net_value_added", NAN))
	if not is_nan(net) and net < 0.0 and net + levy >= 0.0:
		return _check("carbon", "Carbon levy", "bad", "Pays £%.2f a turn in carbon levy%s. That turns a profit into a loss of £%.2f." % [levy, on, -net])
	return _check("carbon", "Carbon levy", "warn", "Pays £%.2f a turn in carbon levy%s." % [levy, on])

static func _works_check(building: Dictionary) -> Dictionary:
	var iid := str(building.get("instance_id", ""))
	if BuildingWorks.is_demolishing(iid):
		var d := BuildingWorks.demolish_turns_remaining(iid)
		return _check("works", "Upgrade and retool works", "warn", "Being demolished. %d turn%s left." % [d, "" if d == 1 else "s"])
	if BuildingWorks.is_retooling(iid):
		var r := BuildingWorks.retrofit_turns_remaining(iid)
		return _check("works", "Upgrade and retool works", "warn", "Retooling. %d turn%s left, and it makes nothing until then." % [r, "" if r == 1 else "s"])
	var snap := BuildingWorks.upgrade_progress_snapshot(iid)
	if not snap.is_empty():
		var target := int(BuildingWorks.pending_upgrade(iid).get("target_level", int(building.get("level", 1)) + 1))
		if bool(snap.get("blocked", false)):
			return _check("works", "Upgrade and retool works", "bad", "Upgrade to Lv %d has stalled. %s" % [target, str(snap.get("error", ""))])
		var eta := int(snap.get("estimated_turns", -1))
		var when := "About %d turn%s to go." % [eta, "" if eta == 1 else "s"] if eta >= 0 else "Under way."
		return _check("works", "Upgrade and retool works", "warn", "Upgrading to Lv %d. %s" % [target, when])
	return _check("works", "Upgrade and retool works", "off", "No works under way.")

# green_intermittent (solar/wind) / green_steady (hydro/biomass fuel) / grey — mirrors Production._power_quality.
static func _power_quality_of(building: Dictionary, recipe: Dictionary) -> String:
	var internal := str(Catalog.get_building(str(building.get("building_id", ""))).get("internal_name", ""))
	if internal in EconomyConfig.POWER_INTERMITTENT_BUILDINGS:
		return "green_intermittent"
	if internal in EconomyConfig.POWER_STEADY_BUILDINGS:
		return "green_steady"
	for inp in recipe.get("inputs", []):
		if str(inp.get("internal_name", "")) in EconomyConfig.POWER_STEADY_FUELS:
			return "green_steady"
	return "grey"

# Input-sourcing row: grey until anything is sourced; then green (all from your buildings),
# amber (some bought from market), or red (missing).
static func _input_sourcing_row(building: Dictionary, recipe: Dictionary, ran: bool, input_c: Color, rs: String) -> Dictionary:
	var tile := str(building.get("tile_id", ""))
	var any_sourced := ran
	if not any_sourced:
		for inp in recipe.get("inputs", []):
			if Stockpile.get_at_tile(tile, str(inp.get("good_id", ""))) > 0:
				any_sourced = true
				break
	if not any_sourced:
		for s in shipments(building, recipe):
			if int(s.get("inbound", 0)) > 0:
				any_sourced = true
				break
	var linked: Dictionary = {}
	for s in input_sources(building, recipe):
		linked[str(s.get("input_name", ""))] = true
	var total := (recipe.get("inputs", []) as Array).size()
	var tone := "info"  # grey — just built/bought, nothing sourced yet
	if any_sourced:
		if input_c == BuildingStatus.STATUS_RED and rs != "restarting":
			tone = "bad"
		elif linked.size() >= total and total > 0:
			tone = "ok"    # every input comes from your own buildings
		else:
			tone = "warn"  # (some) bought from the market
	return {"tone": tone, "detail": _input_sourcing_text(building, recipe)}

# Fluid/gas input route diagnostics. The ordinary input shortage rows say whether the recipe
# can run THIS turn; this helper answers the different question of whether the next batch has a
# route. Default inputs come from the market. "Tile stockpile only" inputs instead use any
# player producer explicitly routing that good here.
static func _fluid_input_transport_problems(building: Dictionary, recipe: Dictionary) -> Array:
	var problems: Array = []
	var tile := str(building.get("tile_id", ""))
	var iid := str(building.get("instance_id", ""))
	if tile == "":
		return problems
	for inp in recipe.get("inputs", []):
		var gid := str((inp as Dictionary).get("good_id", ""))
		if gid == "" or not Catalog.requires_pipeline(gid):
			continue
		var routes: Array = []
		var supplied_on_tile := false
		if MatchState.is_input_tile_only(iid, gid):
			for producer in _producers_for_input(inp, iid, tile):
				var source_tile := str((producer as Dictionary).get("tile_id", ""))
				if source_tile == tile:
					supplied_on_tile = true
					break
				var producer_route := TransportService.route(source_tile, tile, gid)
				if TransportService.route_is_reachable(producer_route):
					routes.append(producer_route)
			if supplied_on_tile:
				continue
			# With no selected external source, the generic starvation diagnostic already
			# explains the problem. Do not invent a missing-pipe fault for stockpile-only mode.
			if routes.is_empty():
				continue
		else:
			var quote := TransportService.quote_market_buy(tile, gid, 1, TransportState.seaport_would_cover(gid))
			if not quote.is_empty():
				routes.append(quote.get("route", {}))

		var reinforced := Catalog.get_transport_class(gid) == "hazard_liquid"
		if routes.is_empty():
			problems.append({"good_id": gid, "reinforced": reinforced, "blocked": true})
			continue
		var has_suitable_pipe := false
		for route in routes:
			if _route_uses_suitable_pipe(route as Dictionary, tile, gid):
				has_suitable_pipe = true
				break
		if not has_suitable_pipe:
			problems.append({"good_id": gid, "reinforced": reinforced, "blocked": false})
	return problems


static func _route_uses_suitable_pipe(route: Dictionary, endpoint_tile: String, good_id: String) -> bool:
	var legs: Array = route.get("legs", [])
	for leg in legs:
		var mode := str((leg as Dictionary).get("mode", ""))
		if mode != "reinf_pipes" and not (mode == "pipes" and Catalog.get_transport_class(good_id) != "hazard_liquid"):
			return false
	if not legs.is_empty():
		return true
	# Same-tile market delivery has no legs. In that case the terminal's actual mode
	# distinguishes a piped delivery from a road/rail loading bay.
	if Catalog.tile_has_infrastructure(endpoint_tile, "reinf_pipes"):
		return true
	if Catalog.get_transport_class(good_id) != "hazard_liquid" \
			and Catalog.tile_has_infrastructure(endpoint_tile, "pipes"):
		return true
	return false

# --- helpers ------------------------------------------------------------------------------

static func _row(tone: String, ic: String, label: String, detail: String) -> Dictionary:
	return {"tone": tone, "ic": ic, "label": label, "detail": detail}

## A diagnostics row that shows a GOOD's icon in place of the tone dot — used where the row
## is about a specific commodity (the deposit warning names the ore that is running out).
static func _row_good(tone: String, ic: String, good_id: String, label: String, detail: String) -> Dictionary:
	var r := _row(tone, ic, label, detail)
	r["good_id"] = good_id
	return r

## This turn's exhaustion warning for one building, or {} — Production records it while
## depleting, so the runway already reflects upgrades and output modifiers.
static func _deposit_runway(instance_id: String) -> Dictionary:
	if instance_id == "":
		return {}
	for d in (Production.last_turn_summary.get("deposits_running_out", []) as Array):
		if str((d as Dictionary).get("instance_id", "")) == instance_id:
			return d
	return {}

## Detail line for a generator throttled by its tile's cable export cap. Reports what the
## tile actually got onto the wire against what it can carry, then tells the player the one
## thing they can do about it — except at max cable level, where there is nothing to do and
## saying "upgrade" would be a dead end.
static func _cable_cap_detail(building: Dictionary, recipe: Dictionary, tile_id: String) -> String:
	var cap := Power.tile_power_cap(tile_id)
	var on_wire := int(Power.tile_produced.get(tile_id, 0))
	var blocked := BuildingStatus.effective_power_output(building, recipe)
	var advice := "Max power capacity reached for this tile." if Power.cable_level_is_max(tile_id) \
		else "Upgrade cables to increase tile capacity."
	return "Power output capped because of cabling. %d/%d MW produced — this plant's %d MW can't reach the network. %s" % [
		on_wire, cap, blocked, advice]

static func _missing_inputs_detail(building: Dictionary, recipe: Dictionary) -> String:
	# "have" counts what is ON THE TILE plus what is IN TRANSIT and will be pulled in next turn --
	# so a timing gap reads as "18 on tile +88 arriving", not a bare shortage. Kept even when the
	# inbound overshoots the requirement.
	var short: Array = []
	for s in shipments(building, recipe):
		var stored := int(s.get("stored", 0))
		var need := int(s.get("need", 0))
		if stored >= need:
			continue
		var inbound := int(s.get("inbound", 0))
		if inbound > 0:
			var eta := int(s.get("eta_turns", -1))
			var eta_txt := "next turn" if eta <= 1 else "%d turns" % eta
			short.append("%s %d on tile +%d arriving %s (need %d)" % [str(s.get("name", "")), stored, inbound, eta_txt, need])
		else:
			short.append("%s %d/%d" % [str(s.get("name", "")), stored, need])
	return ("Short: " + ", ".join(short)) if not short.is_empty() else "Missing required inputs."

static func _stockpile_input_gap_detail(building: Dictionary, recipe: Dictionary) -> String:
	var iid := str(building.get("instance_id", ""))
	var tile_id := str(building.get("tile_id", ""))
	if iid == "" or tile_id == "":
		return ""
	for input: Dictionary in recipe.get("inputs", []):
		var gid := str(input.get("good_id", ""))
		if gid == "" or not MatchState.is_input_tile_only(iid, gid):
			continue
		if Production.stockpile_input_gap_streak(iid, gid) < 2:
			continue
		if Stockpile.get_at_tile(tile_id, gid) > 0:
			continue
		return "This building draws from the tile stockpile but no %s has been produced or delivered here in a while." % Catalog.get_display_name(gid)
	return ""

# "Steel from Furnace · Coal from market" — where each input is sourced (linked supplier vs market).
static func _input_sourcing_text(building: Dictionary, recipe: Dictionary) -> String:
	var linked: Dictionary = {}  # input display name -> supplier building name
	for s in input_sources(building, recipe):
		linked[str(s.get("input_name", ""))] = str(s.get("building_name", ""))
	var parts: Array = []
	for inp in recipe.get("inputs", []):
		var nm := BuildingStatus.good_display_from_internal(str(inp.get("internal_name", "")))
		parts.append("%s from %s" % [nm, str(linked[nm])] if linked.has(nm) else "%s from market" % nm)
	return "  ·  ".join(parts)

# "Some inputs travel far" vs "Inputs are nearby", from the inbound shipments' ETA + source tile.
static func _input_distance_text(building: Dictionary, recipe: Dictionary) -> Dictionary:
	var far: Array = []
	var near := false
	for s in shipments(building, recipe):
		if int(s.get("inbound", 0)) <= 0:
			continue
		var eta := int(s.get("eta_turns", -1))
		if eta > 1:
			far.append("%s %d turns from %s" % [str(s.get("name", "")), eta, str(s.get("from", "source"))])
		else:
			near = true
	if not far.is_empty():
		return {"tone": "warn", "label": "Some inputs travel far", "detail": "  ·  ".join(far)}
	if near:
		return {"tone": "ok", "label": "Inputs are nearby", "detail": "Arriving this turn or next."}
	return {}

static func _mod_detail(parts: Array, wparts: Array) -> String:
	var out: Array = []
	for p in parts:
		var pv := int(round(float(p.get("pct", 0.0))))
		out.append("%s%d%% %s" % ["+" if pv > 0 else "", pv, str(p.get("label", ""))])
	for p in wparts:
		var pv := int(round(float(p.get("pct", 0.0))))
		out.append("%s%d%% %s" % ["+" if pv > 0 else "", pv, str(p.get("label", ""))])
	return "  ·  ".join(out)

static func _num(v: float) -> String:
	var s := "%.2f" % v
	while s.ends_with("0"):
		s = s.substr(0, s.length() - 1)
	if s.ends_with("."):
		s = s.substr(0, s.length() - 1)
	return s

# --- Cost to produce, per output good (vs that good's market price) -------------------------
# One row per output the CostSolver priced this turn: { good_id, name, unit_cost, market_price,
# pct (unit_cost/market − 1, ×100), color }. Empty until cost_solve has run (turn 1 pre-solve).
static func cost_to_produce(building: Dictionary) -> Array:
	var iid := str(building.get("instance_id", ""))
	var recipe := Catalog.get_recipe(str(building.get("recipe_id", "")))
	if BuildingStatus.recipe_deposit_exhausted(building, recipe):
		return []
	var bd: Dictionary = (CostSolver.last_result.get("per_building", {}) as Dictionary).get(iid, {})
	var output_costs: Dictionary = bd.get("output_costs", {})
	var rows: Array = []
	for gid in output_costs:
		var uc := float(output_costs[gid])
		# LIVE market price (decay + glut impact), not the static base — the RAG and
		# the % move as the output's price moves.
		var mp := BuildingStatus.live_output_price(str(gid))
		if uc < 0.0 or mp <= 0.0:
			continue  # unsolved, or a good with no market price (e.g. power)
		rows.append({
			"good_id": str(gid),
			"name": Catalog.get_display_name(str(gid)),
			"unit_cost": uc,
			"market_price": mp,
			"pct": int(round((uc / mp - 1.0) * 100.0)),
			"color": BuildingStatus.cost_rag_color(uc, mp),
		})
	return rows

# --- Inbound input shipments ---------------------------------------------------------------
static func shipments(building: Dictionary, recipe: Dictionary) -> Array:
	var tile_id := str(building.get("tile_id", ""))
	var rows: Array = []
	for inp in recipe.get("inputs", []):
		var gid := str(inp.get("good_id", ""))
		var need := int(inp.get("qty", 0))
		var stored := Stockpile.get_at_tile(tile_id, gid)
		var inbound := 0
		var next_turns := -1
		var from_tiles: Array = []
		for s in TransportState.get_inbound_transport_shipments(tile_id, gid):
			inbound += int(s.get("qty", 0))
			var t := int(s.get("turns_remaining", 0))
			if next_turns < 0 or t < next_turns:
				next_turns = t
			var src := str(s.get("source_tile", ""))
			if src != "" and not from_tiles.has(src):
				from_tiles.append(src)
		var from_labels: Array = []
		for src in from_tiles:
			from_labels.append(Catalog.tile_label(src))
		rows.append({
			"good_id": gid,
			"internal": str(inp.get("internal_name", "")),
			"name": BuildingStatus.good_display_from_internal(str(inp.get("internal_name", ""))),
			"stored": stored, "need": need, "inbound": inbound,
			"from": ", ".join(from_labels),
			"eta_turns": next_turns,
		})
	return rows

# --- Routing: where inputs come from, where the output goes, and the tiles to highlight ------

static func input_sources(building: Dictionary, recipe: Dictionary) -> Array:
	var rows: Array = []
	var iid := str(building.get("instance_id", ""))
	var tile_id := str(building.get("tile_id", ""))
	for inp in recipe.get("inputs", []):
		if Middleman.supplies_good(iid, str(inp.get("good_id", ""))): continue
		for producer in _producers_for_input(inp, iid, tile_id):
			var prod_data := Catalog.get_building(str(producer.get("building_id", "")))
			rows.append({
				"good_id": str(inp.get("good_id", "")),
				"internal": str(inp.get("internal_name", "")),
				"input_name": BuildingStatus.good_display_from_internal(str(inp.get("internal_name", ""))),
				"building_name": str(prod_data.get("display_name", producer.get("building_id", ""))),
				"tile_id": str(producer.get("tile_id", "")),
				"instance_id": str(producer.get("instance_id", "")),
			})
	return rows

# Player buildings that consume this building's primary output, fed from its routed destination tile.
static func output_consumers(building: Dictionary, recipe: Dictionary) -> Array:
	var out_gid := BuildingStatus.primary_output_good_id(recipe)
	var iid := str(building.get("instance_id", ""))
	if out_gid == "":
		return []
	# The per-good mode is authoritative. A mixed service contract can sell one
	# output privately while another output remains a physical stockpile route.
	# The old side-wide check hid all consumers in that case.
	if Middleman.buys_output(iid, out_gid): return []
	var destinations := MatchState.get_output_split_destinations(iid, out_gid)
	if destinations.is_empty():
		var single := MatchState.get_output_stockpile_destination(iid, out_gid)
		if single != "":
			destinations.append({"tile_id": single})
	if destinations.is_empty():
		# Unrouted output lands in this building's OWN tile stockpile (default STOCKPILE_ALL), so
		# same-tile buildings draw from it. A market route / SELL_ALL has no downstream tile.
		if not MatchState.is_output_market(iid, out_gid) and MatchState.sell_mode == MatchState.SellMode.STOCKPILE_ALL:
			destinations.append({"tile_id": str(building.get("tile_id", ""))})
		if destinations.is_empty():
			return []
	var rows: Array = []
	var destination_tiles: Array = []
	for destination in destinations:
		var tile := str((destination as Dictionary).get("tile_id", ""))
		if tile != "" and not destination_tiles.has(tile):
			destination_tiles.append(tile)
	for b in BuildingState.buildings.values():
		if str(b.get("instance_id", "")) == iid or not destination_tiles.has(str(b.get("tile_id", ""))):
			continue
		if Middleman.uses_inputs(str(b.get("instance_id",""))): continue
		if not BuildingState.is_player_owned(b):
			continue
		var r := Catalog.get_recipe(str(b.get("recipe_id", "")))
		for inp in r.get("inputs", []):
			if str(inp.get("good_id", "")) == out_gid:
				var bd := Catalog.get_building(str(b.get("building_id", "")))
				rows.append({
					"name": str(bd.get("display_name", b.get("building_id", ""))),
					"instance_id": str(b.get("instance_id", "")),
					"tile_id": str(b.get("tile_id", "")),
				})
				break
	return rows

## Where one of the building's outputs goes (the primary output when `good_id` is ""): {destination,
## cost and turns for its quantity a run, reachable, has_market, target}.
static func output_route(building: Dictionary, recipe: Dictionary, good_id: String = "") -> Dictionary:
	var iid := str(building.get("instance_id", ""))
	var gid := good_id if good_id != "" else BuildingStatus.primary_output_good_id(recipe)
	# Do this before consulting the legacy/default sell mode. An active
	# intermediary has no shared-tile destination, even when STOCKPILE_ALL is the
	# global fallback for buildings that have no explicit route.
	if Middleman.buys_output(iid, gid):
		return {"destination":"Middleman","target":"","has_market":true,"cost":0.0,"turns":0}
	var source_tile := str(building.get("tile_id", ""))
	var qty := BuildingStatus.primary_output_qty(recipe)
	for o: Dictionary in BuildingStatus.flow_output_items(recipe):
		if str(o.get("good_id", "")) == gid:
			qty = maxi(1, int(o.get("qty", qty)))
	var dest_tile := MatchState.get_output_stockpile_destination(iid, gid)
	var target := ""
	var destination := ""
	var has_market := false
	if MatchState.is_output_market(iid, gid):
		target = TransportService.nearest_port_tile(source_tile)
		var soid := MatchState.get_output_special_order_id(iid, gid)
		if soid != "" and not SpecialOrderState.get_order(soid).is_empty():
			destination = ("Special Order (via %s)" % Catalog.tile_label(target)) if target != "" else "Special Order"
		else:
			destination = ("Market (via %s)" % Catalog.tile_label(target)) if target != "" else "Market"
		has_market = true
	elif dest_tile != "":
		target = dest_tile
		destination = Catalog.tile_label(dest_tile)
	elif MatchState.sell_mode == MatchState.SellMode.STOCKPILE_ALL:
		target = source_tile
		destination = "Tile stockpile (same tile)"
	else:
		target = TransportService.nearest_port_tile(source_tile)
		destination = ("Market (via %s)" % Catalog.tile_label(target)) if target != "" else "Market"
		has_market = true
	var cost := 0.0
	var turns := 0
	var reachable := true
	if target != "" and target != source_tile:
		var route := BuildingStatus.route_summary(source_tile, target, gid, qty)
		cost = float(route.get("cost", 0.0))
		turns = int(route.get("turns", 0))
		reachable = bool(route.get("reachable", true))
	return {"destination": destination, "cost": cost, "turns": turns, "reachable": reachable, "has_market": has_market, "target": target}

static func connections(building: Dictionary, recipe: Dictionary) -> Dictionary:
	if Middleman.fully_managed(str(building.get("instance_id",""))):
		return {"origin":str(building.get("tile_id","")),"input_tiles":[],"output_tiles":[],"has_market":false}
	var origin := str(building.get("tile_id", ""))
	var iid := str(building.get("instance_id", ""))
	var input_tiles: Array = []
	for row in input_sources(building, recipe):
		var t := str(row.get("tile_id", ""))
		if t != "" and t != origin and not input_tiles.has(t):
			input_tiles.append(t)
	var output_tiles: Array = []
	var has_market := false
	for o in BuildingStatus.flow_output_items(recipe):
		var gid := str(o.get("good_id", ""))
		if gid == "":
			gid = str(Catalog.get_good_by_internal_name(str(o.get("internal_name", ""))).get("id", ""))
		if gid == "":
			continue
		if Middleman.buys_output(iid, gid):
			continue
		var split := MatchState.get_output_split_destinations(iid, gid)
		if not split.is_empty():
			for destination in split:
				var split_dest := str((destination as Dictionary).get("tile_id", ""))
				if split_dest != "" and split_dest != origin and not output_tiles.has(split_dest):
					output_tiles.append(split_dest)
		else:
			var dest := MatchState.get_output_stockpile_destination(iid, gid)
			if dest != "" and dest != origin and not output_tiles.has(dest):
				output_tiles.append(dest)
			elif dest == "":
				has_market = true
	return {"origin": origin, "input_tiles": input_tiles, "output_tiles": output_tiles, "has_market": has_market}

## Tiles that are real stockpile endpoints for this input good.
##
## This intentionally does not enumerate every owned tile or every tile in a
## shipment's route geometry. A tile is offered only when the good is already
## stored there, is scheduled to arrive there, or a player producer is actually
## configured to leave it there. Transit/path tiles therefore never appear as
## selectable sources.
static func stockpile_source_tiles(building: Dictionary, good_id: String) -> Array:
	var current_tile := str(building.get("tile_id", ""))
	var candidates: Dictionary = {}
	for tile_value in Stockpile.tiles_with_stock():
		var tile := str(tile_value)
		if tile == "" or tile == current_tile or not tile.begins_with("tile_"):
			continue
		if Stockpile.get_at_tile(tile, good_id) > 0:
			candidates[tile] = true
	# An inbound shipment's destination is a genuine future stockpile endpoint;
	# its path and intermediate tiles are deliberately ignored.
	for shipment: Dictionary in TransportState.pending_transport_shipments:
		if str(shipment.get("good_id", "")) != good_id:
			continue
		var destination := str(shipment.get("destination_tile", ""))
		if destination != "" and destination != current_tile and destination.begins_with("tile_"):
			candidates[destination] = true
	# Include a remote producer only when its output endpoint resolves to that
	# tile. Middleman output is private and is not a shared stockpile source.
	for producer: Dictionary in BuildingState.buildings.values():
		if not BuildingState.is_player_owned(producer):
			continue
		var producer_tile := str(producer.get("tile_id", ""))
		if producer_tile == "" or producer_tile == current_tile:
			continue
		var recipe := Catalog.get_recipe(str(producer.get("recipe_id", "")))
		for output in BuildingStatus.flow_output_items(recipe):
			if not _good_matches_input(output, good_id, str(Catalog.get_good(good_id).get("internal_name", ""))):
				continue
			var producer_iid := str(producer.get("instance_id", ""))
			if Middleman.buys_output(producer_iid, good_id):
				continue
			if _routes_to_tile(producer, output, producer_tile):
				candidates[producer_tile] = true
			for destination in MatchState.get_output_split_destinations(producer_iid, good_id):
				var destination_tile := str((destination as Dictionary).get("tile_id", ""))
				if destination_tile != "" and destination_tile != current_tile and destination_tile.begins_with("tile_"):
					candidates[destination_tile] = true
			var single_destination := MatchState.get_output_stockpile_destination(producer_iid, good_id)
			if single_destination != "" and single_destination != current_tile and single_destination.begins_with("tile_"):
				candidates[single_destination] = true
			break
	var result: Array = candidates.keys()
	result.sort()
	return result

static func _producers_for_input(inp: Dictionary, current_iid: String, current_tile: String) -> Array:
	var producers: Array = []
	var in_gid := str(inp.get("good_id", ""))
	var in_internal := str(inp.get("internal_name", ""))
	for b in BuildingState.buildings.values():
		if str(b.get("instance_id", "")) == current_iid:
			continue
		var r := Catalog.get_recipe(str(b.get("recipe_id", "")))
		for o in BuildingStatus.flow_output_items(r):
			if _good_matches_input(o, in_gid, in_internal) and _routes_to_tile(b, o, current_tile):
				producers.append(b)
				break
	return producers

static func _good_matches_input(output: Dictionary, in_gid: String, in_internal: String) -> bool:
	var out_gid := str(output.get("good_id", ""))
	if in_gid != "" and out_gid != "":
		return in_gid == out_gid
	return str(output.get("internal_name", "")) == in_internal

# --- Ownership / NPC ------------------------------------------------------------------------
# Authoritative live owner (never trust a possibly-stale passed-in dict).
static func owner_info(building: Dictionary) -> Dictionary:
	var iid := str(building.get("instance_id", ""))
	var live: Dictionary = BuildingState.get_building(iid) if iid != "" else {}
	var owner := str(live.get("owner", building.get("owner", MatchState.LOCAL_PLAYER)))
	var is_npc := owner != MatchState.LOCAL_PLAYER and owner != "tile_data"
	return {
		"is_npc": is_npc,
		"owner_id": owner,
		"is_ruins": str(building.get("building_id", "")) == "b_031",
		"company": company_name(owner),
	}

# Stable, deterministic fake company name for an owner id (char-fold, not hash() — engine-stable).
static func company_name(owner_id: String) -> String:
	if owner_id == "" or owner_id == MatchState.LOCAL_PLAYER:
		return owner_id
	var acc := 0
	for i in owner_id.length():
		acc = (acc * 31 + owner_id.unicode_at(i)) % 1000000
	return CompanyNames.NAMES[acc % CompanyNames.NAMES.size()]

# Purchase price shown on the NPC Buy button (matches the Buildings-market listing).
static func buy_price(building: Dictionary) -> int:
	return MatchState.building_purchase_price(building)

# What you recover on Sell — the building's market list value.
static func sell_value(building: Dictionary) -> int:
	return int(round(float(BuildingPrice.sale_price(building))))

# --- Construction ---------------------------------------------------------------------------
static func construction(building: Dictionary) -> Dictionary:
	var iid := str(building.get("instance_id", ""))
	var proj: Dictionary = Construction.construction_projects.get(iid, {})
	if proj.is_empty():
		return {"active": false}
	var status := str(proj.get("status", Construction.STATUS_UNDER_CONSTRUCTION))
	var tile_id := str(proj.get("tile_id", ""))
	var required: Dictionary = proj.get("required_materials", {})
	var missing: Dictionary = proj.get("missing_materials", {})
	var mats: Array = []
	for gid in required:
		var secured := not missing.has(gid)
		var eta := -1
		if not secured:
			eta = Construction.material_arrival_eta(tile_id, str(gid))
		mats.append({
			"good_id": str(gid), "internal": str(Catalog.get_good(str(gid)).get("internal_name", "")),
			"name": Catalog.get_display_name(str(gid)),
			"qty": int(required[gid]), "secured": secured, "eta": eta,
		})
	return {
		"active": true,
		"tile_id": tile_id,
		"building_phase": status == Construction.STATUS_UNDER_CONSTRUCTION,
		"turns_left": int(proj.get("turns_remaining", 0)),
		"turns_after": int(proj.get("construction_duration", 0)),
		"materials": mats,
	}


## Transport advice for fluid/gas construction materials. Road and rail can deliver them, so
## missing pipework is an amber cost warning when an overland route exists and a red blocker only
## when the market cannot quote any route to the site.
static func construction_diagnostics(constr: Dictionary) -> Array:
	var rows: Array = []
	var tile := str(constr.get("tile_id", ""))
	if tile == "":
		return rows
	for m in constr.get("materials", []):
		if bool(m.get("secured", false)):
			continue
		var gid := str(m.get("good_id", ""))
		if gid == "" or not Catalog.requires_pipeline(gid):
			continue
		var nm := str(m.get("name", Catalog.get_display_name(gid)))
		var reinforced := Catalog.get_transport_class(gid) == "hazard_liquid"
		var pipe_name := "Reinforced Pipeline" if reinforced else "Pipeline"
		var pipe_phrase := "a reinforced pipeline" if reinforced else "a pipeline"
		var quote := TransportService.quote_market_buy(tile, gid, 1, TransportState.seaport_would_cover(gid))
		if quote.is_empty():
			rows.append(_row_good("bad", "pipe", gid, "No transport route to deliver %s" % nm,
				"%s cannot reach this site. Connect it to the market port by road, rail or %s, or the build cannot finish." % [nm, pipe_phrase]))
		elif not _route_uses_suitable_pipe(quote.get("route", {}) as Dictionary, tile, gid):
			rows.append(_row_good("warn", "pipe", gid, "Transport could be cheaper using %s" % pipe_name,
				"%s can reach this site by road or rail, but %s would carry it more cheaply." % [nm, pipe_phrase]))
	return rows

# --- Battery storage ------------------------------------------------------------------------
static func battery(building: Dictionary) -> Dictionary:
	var tile_id := str(building.get("tile_id", ""))
	return {
		"loaded": Power.tile_battery_cells_loaded(tile_id),
		"slots": Power.tile_battery_slots(tile_id),
		"firming_cap": Power.tile_firming_cap(tile_id),
	}

static func _routes_to_tile(producer: Dictionary, output: Dictionary, tile_id: String) -> bool:
	if Middleman.buys_output(str(producer.get("instance_id","")), str(output.get("good_id", ""))): return false
	if tile_id == "":
		return false
	var gid := str(output.get("good_id", ""))
	if gid == "":
		gid = str(Catalog.get_good_by_internal_name(str(output.get("internal_name", ""))).get("id", ""))
	if gid == "":
		return false
	var piid := str(producer.get("instance_id", ""))
	# Explicit output route to this tile.
	for destination in MatchState.get_output_split_destinations(piid, gid):
		if str((destination as Dictionary).get("tile_id", "")) == tile_id:
			return true
	if MatchState.get_output_stockpile_destination(piid, gid) == tile_id:
		return true
	# Same-tile producer whose output lands in the SHARED tile stockpile (an iron-ingot furnace
	# feeding a steel furnace on the same tile): default STOCKPILE_ALL, unrouted, not sold to market.
	if str(producer.get("tile_id", "")) == tile_id \
			and BuildingState.is_player_owned(producer) \
			and not MatchState.is_output_market(piid, gid) \
			and MatchState.get_output_stockpile_destination(piid, gid) == "" \
			and MatchState.sell_mode == MatchState.SellMode.STOCKPILE_ALL:
		return true
	return false

## Roll up the same diagnostic rows the BDP displays into a tile-card lamp.
static func diagnostic_led_tone(rows: Array) -> String:
	var amber := 0
	var green := 0
	for row: Dictionary in rows:
		match str(row.get("tone", "info")):
			"bad": return "bad"
			"warn": amber += 1
			"ok": green += 1
	if amber > 1 or (amber > 0 and green == 0):
		return "warn"
	return "ok"
