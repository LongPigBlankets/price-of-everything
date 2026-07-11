extends RefCounted
## Shared, UI-agnostic READOUT of a building for the redesigned (v2) detail panel.
## Aggregates the existing single-source-of-truth helpers (BuildingStatus, CostSolver,
## Modifiers, Catalog, EconomyConfig, MatchState) into plain data the panel renders — so v2
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
const PORT_BUILDING_ID := "b_004"

# Fake operator names for NPC-owned buildings (cosmetic; a stable pick per owner id — no RNG).
const _COMPANIES := [
	"Ashworth Industrials", "Meridian Foundries", "Blackwater Holdings", "Calderon & Vance",
	"Ironbridge Group", "Nordvik Materials", "Halcyon Works", "Sterling Combine",
	"Thornfield Mills", "Vantage Refineries", "Crown Metalworks", "Pemberton Chemical",
	"Drexel Manufacturing", "Grayson Foundry Co.", "Aldridge Consolidated", "Whitmore Petrochem",
]

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
	if iid != "" and Production.last_turn_run.has(iid):
		return "running"
	if (recipe.get("inputs", []) as Array).is_empty():
		return "running"  # a powered no-input source (renewable) always runs
	if has_all_inputs(building, recipe):
		return "restarting"
	return "stalled"

static func has_all_inputs(building: Dictionary, recipe: Dictionary) -> bool:
	var tile := str(building.get("tile_id", ""))
	for inp in recipe.get("inputs", []):
		if Stockpile.get_at_tile(tile, str(inp.get("good_id", ""))) < int(inp.get("qty", 0)):
			return false
	return true

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

static func flow(building: Dictionary, recipe: Dictionary) -> Dictionary:
	var inputs: Array = []
	for inp in recipe.get("inputs", []):
		inputs.append({
			"good_id": str(inp.get("good_id", "")),
			"internal": str(inp.get("internal_name", "")),
			"qty": int(inp.get("qty", 0)),
		})
	var out_items := BuildingStatus.flow_output_items(recipe)
	var output: Dictionary = {}
	if not out_items.is_empty():
		var o: Dictionary = out_items[0]
		var base_qty := int(o.get("qty", 0))
		var eff := BuildingStatus.effective_output_qty(building, recipe)
		if str(recipe.get("output_name", "")) == "power":
			eff = BuildingStatus.effective_power_output(building, recipe)
		output = {
			"good_id": str(o.get("good_id", "")),
			"internal": str(o.get("internal_name", "")),
			"qty": eff,
			"base_qty": base_qty,
		}
	var mod := BuildingStatus.net_output_modifier(building, recipe)
	return {
		"inputs": inputs,
		"output": output,
		"power_in": BuildingStatus.effective_energy_req(building, recipe),
		"produces_power": str(recipe.get("output_name", "")) == "power",
		"mod_pct": int(mod.get("pct", 0)),
		"mod_text": str(mod.get("text", "")),
	}

# --- Economics (real cash flows + the cost-to-produce RAG) ---------------------------------

static func economics(building: Dictionary, recipe: Dictionary, building_data: Dictionary) -> Dictionary:
	var lvl := int(building.get("level", 1))
	var maint := BuildingStatus.maintenance_cost(building_data) * BuildingLevels.mult("maint", lvl)
	var lab := labour(building_data)
	# Power leg: the grid-price value of the energy drawn each turn (0 for generators / no-power
	# recipes). Mirrors the CostSolver's imputed power_cost (energy × GRID_BUY_PRICE).
	var power_cost := float(BuildingStatus.effective_energy_req(building, recipe)) * EconomyConfig.GRID_BUY_PRICE
	# Simplified per-turn worth: Output value − transport − inputs − maintenance − labour − power.
	# One "Output value" figure (the market worth of the run's output), tagged sold / if-sold, plus
	# the freight to its SET destination. Net always folds them in.
	var out_gid := BuildingStatus.primary_output_good_id(recipe)
	var units_out := BuildingStatus.effective_output_qty(building, recipe)
	# Live market price (incl. glut/deficit impact), falling back to the impact-free base.
	var price := 0.0
	if out_gid != "":
		price = MarketState.get_price(out_gid)
		if price <= 0.0:
			price = Catalog.get_base_price(out_gid)
	var output_value := float(units_out) * price
	# Inputs valued at their COST TO PRODUCE — the CostSolver's imputed per-good cost, resolved over
	# the whole chain (an internally-made input costs what it cost to make, not its market price).
	# Falls back to market only for external inputs no player building produces — exactly mirroring
	# the solver's own input pricing (cost_solver.gd: internal goods imputed, external leaves market).
	var input_cost := 0.0
	for inp in recipe.get("inputs", []):
		var in_gid := str(inp.get("good_id", ""))
		var imputed := CostSolver.get_good_unit_cost(in_gid)  # −1 when external / not yet solved
		var unit_price := imputed if imputed >= 0.0 else MarketState.get_price(in_gid)
		if unit_price <= 0.0:
			unit_price = Catalog.get_base_price(in_gid)
		input_cost += float(inp.get("qty", 0)) * unit_price
	# Is the output actually sold this turn (market route, or a tile that auto-sells its surplus)?
	# A generator / infrastructure has no sellable good (units_out == 0) — never treat it as selling.
	var disp := _output_disposition(building, recipe)
	var mode := str(disp.get("mode", "held"))
	var sells := (mode == "market" or mode == "tile_sales") and units_out > 0
	# Transport cost of moving the output to its SET destination (nearest port for a market route,
	# the target tile otherwise, 0 for same-tile / no destination).
	var own_tile := str(building.get("tile_id", ""))
	var route := output_route(building, recipe)
	var target := str(route.get("target", ""))
	var transport_cost := 0.0
	if units_out > 0 and target != "" and target != own_tile and bool(route.get("reachable", true)):
		transport_cost = float(BuildingStatus.route_summary(own_tile, target, out_gid, units_out).get("cost", 0.0))
	# Storage overhead: this building's attributed share of its tile's actual
	# warehousing fee last turn (CostSolver splits each tile's charge across the
	# buildings that ran there). 0 until the first solve or when nothing is stored.
	var wh_bd: Dictionary = CostSolver.last_result.get("per_building", {}).get(str(building.get("instance_id", "")), {})
	var warehousing := float(wh_bd.get("warehousing_cost", 0.0))
	# Carbon levy (live estimate at the CURRENT policy phase): the charge for this run's
	# taxed inputs (coal / processed oil / ethylene …). 0 before the levy is in force.
	var carbon_tax := 0.0
	var levy_turn := int(TurnManager.current_turn)
	for inp in recipe.get("inputs", []):
		carbon_tax += PolicyState.carbon_charge(str(inp.get("good_id", "")),
			int(round(float(inp.get("qty", 0)) * BuildingLevels.mult("input", lvl))), levy_turn)
	var running := maint + float(lab.get("cost", 0.0)) + power_cost + input_cost + transport_cost + warehousing + carbon_tax
	var pc := BuildingStatus.produce_cost_status(building)
	return {
		"value": float(building_data.get("base_price", 0.0)),   # asset value (build/buy price), not per-turn
		"output_value": output_value,
		"sells": sells,
		"units_out": units_out,
		"sale_price": price,
		"transport_cost": transport_cost,
		"input_cost": input_cost,
		"maintenance": maint,
		"labour_cost": float(lab.get("cost", 0.0)),
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
static func _output_disposition(building: Dictionary, recipe: Dictionary) -> Dictionary:
	var iid := str(building.get("instance_id", ""))
	var gid := BuildingStatus.primary_output_good_id(recipe)
	var src := str(building.get("tile_id", ""))
	if gid == "":
		return {"mode": "held", "sell_tile": src, "good_id": ""}
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
	var factor := MatchState.labour_policy_factor()
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
	var exhausted := BuildingStatus.recipe_deposit_exhausted(building, recipe)
	var ran := iid != "" and Production.last_turn_run.has(iid)
	var missing := iid != "" and Production.missing_by_building.has(iid)
	var power_c := BuildingStatus.power_status_color(building, recipe, is_infrastructure)
	var input_c := BuildingStatus.input_status_color(building, recipe, is_infrastructure)
	var produces_power := str(recipe.get("output_name", "")) == "power"
	var needs_power := BuildingStatus.effective_energy_req(building, recipe) > 0
	var has_inputs := not (recipe.get("inputs", []) as Array).is_empty()
	var rs := run_state(building, recipe, is_infrastructure)
	var tile_id := str(building.get("tile_id", ""))
	# A power PRODUCER whose "missing" entry is power = the cable export cap blocked its
	# dispatch (production._can_run_recipe's can_produce branch) — not an input problem.
	var grid_blocked := false
	if produces_power and iid != "":
		for m in (Production.missing_by_building.get(iid, []) as Array):
			if str(m.get("good_id", "")) == "power":
				grid_blocked = true

	# 1) critical fault / restarting / all-clear
	if exhausted:
		rows.append(_row("bad", "warn", "Deposit exhausted", "The deposit here is mined out — this building can no longer produce."))
	elif rs == "restarting":
		rows.append(_row("warn", "clock", "Starting", "All inputs received and powered — production begins next turn."))
	elif needs_power and power_c == BuildingStatus.STATUS_RED:
		rows.append(_row("bad", "warn", "Critical fault", "No power reaching this building — the recipe halts."))
	elif grid_blocked:
		rows.append(_row("bad", "warn", "Cannot push power", "The tile's cables are at capacity — this plant's output can't reach the network."))
	elif has_inputs and input_c == BuildingStatus.STATUS_RED:
		rows.append(_row("bad", "warn", "Cannot run", "Not enough inputs to run the recipe this turn."))
	elif missing:
		rows.append(_row("bad", "warn", "Critical fault", "Missing required inputs — the recipe could not run this turn."))
	else:
		rows.append(_row("ok", "check", "No critical faults", "Operating normally." if ran else "Ready to run."))

	# 2) power
	if produces_power:
		if grid_blocked:
			var cap := Power.tile_power_cap(tile_id)
			var on_wire := int(Power.tile_produced.get(tile_id, 0))
			rows.append(_row("bad", "bolt", "Cables overloaded",
				"%d of %d kW already on this tile's cables — the %d kW from this plant can't be pushed to the network. Upgrade the cables or reduce generation here." % [
					on_wire, cap, BuildingStatus.effective_power_output(building, recipe)]))
		else:
			rows.append(_row("ok", "bolt", "Generating power", "%d kW / turn" % BuildingStatus.effective_power_output(building, recipe)))
	elif needs_power:
		var pw := power(building, recipe)
		var st := str(pw.get("state", "none"))
		var amt := int(pw.get("amount", 0))
		if st == "none":
			rows.append(_row("bad", "bolt", "Unpowered", "No power reaching this building — the recipe halts."))
		elif st == "ready":
			rows.append(_row("warn", "bolt", "Ready to draw power", "%d kW ready to draw from the grid once it runs." % amt))
		else:
			rows.append(_row("ok" if st == "own" else "warn", "bolt", "Powered", "%d kW drawn · %s" % [amt, power_state_text(st)]))

	# 2b) green-power intermittency — only for green generators / green-power consumers; skipped
	# for buildings that only supply or draw grey (coal/gas/oil) power.
	var intermit := _intermittency_row(building, recipe, is_infrastructure)
	if not intermit.is_empty():
		rows.append(intermit)

	# 3) inputs
	if has_inputs and not exhausted:
		if rs == "restarting" or input_c == BuildingStatus.STATUS_GREEN:
			rows.append(_row("ok", "box", "Inputs in stock" if rs == "restarting" else "Receiving inputs",
				"All inputs are in stock, ready for the next run." if rs == "restarting" else "All inputs were in stock this turn."))
		elif input_c == BuildingStatus.STATUS_RED:
			rows.append(_row("bad", "box", "Starved of inputs", _missing_inputs_detail(building, recipe)))
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
				for s in MatchState.get_inbound_transport_shipments(tile_id):
					inbound += int(s.get("qty", 0))
				var detail := "The tile's warehouse is full (%d/%d) — arriving inputs can't unload." % [wh_used, wh_cap]
				if inbound > 0:
					detail += " %d unit%s in transit are waiting." % [inbound, "" if inbound == 1 else "s"]
				detail += " Expand the warehouse (Stockpile tab) or clear stock."
				rows.append(_row("bad" if input_c == BuildingStatus.STATUS_RED else "warn", "box",
					"Stockpile over-utilised", detail))
		# 3c) a fluid/gas input with no pipeline built to its source can never be delivered
		var pipe := _pipe_problem(building, recipe)
		if not pipe.is_empty():
			if bool(pipe.get("reinforced", false)):
				rows.append(_row("bad", "pipe", "No input Reinforced Pipeline", "This hazardous liquid/gas needs a reinforced pipeline from its source — none is built."))
			else:
				rows.append(_row("bad", "pipe", "No input pipeline", "This liquid input needs a pipeline from its source — none is built."))
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
				"Check infrastructure and connection to %s. Nothing ships (and no transport is charged) until the route exists — fluids need a pipe or reinforced-pipe network." % dest_name))
		else:
			var reach := "easily reached" if turns <= 1 else ("moderate to reach" if turns <= 4 else "hard to reach")
			var reach_tone := "ok" if turns <= 1 else ("warn" if turns <= 4 else "bad")
			rows.append(_row(reach_tone, "truck", "Output destination %s" % reach, "%d turn%s to %s." % [turns, "" if turns == 1 else "s", dest_name]))
			var per_unit := cost / float(qty)
			var band := "cheap" if per_unit < 0.15 else ("average" if per_unit < 0.4 else "expensive")
			var band_tone := "ok" if per_unit < 0.15 else ("warn" if per_unit < 0.4 else "bad")
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

	# 6) output modifiers — the panel renders these as an expandable "See all modifiers" accordion
	var mod := BuildingStatus.net_output_modifier(building, recipe)
	var parts: Array = mod.get("parts", [])
	var wparts: Array = mod.get("workforce_parts", [])
	if not parts.is_empty() or not wparts.is_empty():
		var net := int(mod.get("pct", 0))
		var all_parts: Array = []
		for p in parts:
			all_parts.append({"label": str(p.get("label", "")), "pct": int(round(float(p.get("pct", 0.0))))})
		for p in wparts:
			all_parts.append({"label": str(p.get("label", "")), "pct": int(round(float(p.get("pct", 0.0))))})
		var mrow := _row("ok" if net >= 0 else "warn", "trend", "Output modifiers %s" % str(mod.get("text", "")),
			"%d contributing modifier%s" % [all_parts.size(), "" if all_parts.size() == 1 else "s"])
		mrow["parts"] = all_parts
		rows.append(mrow)

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
		var cap := MatchState.tile_firming_cap(str(building.get("tile_id", "")))
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
	if unfirmed <= 0.001:
		return _row("ok", "bolt", "Safe from intermittency", "All the green power it draws is firmed (battery) or steady — no output derate.")
	if demand > 0.0 and unfirmed >= demand - 0.001:
		return _row("bad", "bolt", "Intermittent power — derated", "All its power is unfirmed renewable — output cut up to %d%% during lulls. Add battery firming or a steady/grey source." % derate)
	return _row("warn", "bolt", "Partly intermittent — derated", "Some power is unfirmed renewable — output cut up to %d%% during lulls. Firm it with a battery or add steady power." % derate)

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

# A fluid/gas input that requires a pipeline but can't be delivered (nothing in stock or inbound).
static func _pipe_problem(building: Dictionary, recipe: Dictionary) -> Dictionary:
	var tile := str(building.get("tile_id", ""))
	for inp in recipe.get("inputs", []):
		var gid := str(inp.get("good_id", ""))
		if gid != "" and Catalog.requires_pipeline(gid) and not _can_pipe_input(tile, gid):
			return {"reinforced": Catalog.get_transport_class(gid) == "hazard_liquid"}
	return {}

static func _can_pipe_input(tile: String, gid: String) -> bool:
	if Stockpile.get_at_tile(tile, gid) > 0:
		return true
	for s in MatchState.get_inbound_transport_shipments(tile, gid):
		if int(s.get("qty", 0)) > 0:
			return true
	return false

# --- helpers ------------------------------------------------------------------------------

static func _row(tone: String, ic: String, label: String, detail: String) -> Dictionary:
	return {"tone": tone, "ic": ic, "label": label, "detail": detail}

static func _missing_inputs_detail(building: Dictionary, recipe: Dictionary) -> String:
	var tile_id := str(building.get("tile_id", ""))
	var short: Array = []
	for inp in recipe.get("inputs", []):
		var need := int(inp.get("qty", 0))
		var have := Stockpile.get_at_tile(tile_id, str(inp.get("good_id", "")))
		if have < need:
			short.append("%s %d/%d" % [BuildingStatus.good_display_from_internal(str(inp.get("internal_name", ""))), have, need])
	return ("Short: " + ", ".join(short)) if not short.is_empty() else "Missing required inputs."

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
		for s in MatchState.get_inbound_transport_shipments(tile_id, gid):
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
	var dest := MatchState.get_output_stockpile_destination(iid, out_gid)
	if dest == "":
		# Unrouted output lands in this building's OWN tile stockpile (default STOCKPILE_ALL), so
		# same-tile buildings draw from it. A market route / SELL_ALL has no downstream tile.
		if not MatchState.is_output_market(iid, out_gid) and MatchState.sell_mode == MatchState.SellMode.STOCKPILE_ALL:
			dest = str(building.get("tile_id", ""))
		if dest == "":
			return []
	var rows: Array = []
	for b in MatchState.buildings.values():
		if str(b.get("instance_id", "")) == iid or str(b.get("tile_id", "")) != dest:
			continue
		if not MatchState.is_player_owned(b):
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

static func output_route(building: Dictionary, recipe: Dictionary) -> Dictionary:
	var source_tile := str(building.get("tile_id", ""))
	var gid := BuildingStatus.primary_output_good_id(recipe)
	var qty := BuildingStatus.primary_output_qty(recipe)
	var iid := str(building.get("instance_id", ""))
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
		var dest := MatchState.get_output_stockpile_destination(iid, gid)
		if dest != "" and dest != origin and not output_tiles.has(dest):
			output_tiles.append(dest)
		elif dest == "":
			has_market = true
	return {"origin": origin, "input_tiles": input_tiles, "output_tiles": output_tiles, "has_market": has_market}

static func _producers_for_input(inp: Dictionary, current_iid: String, current_tile: String) -> Array:
	var producers: Array = []
	var in_gid := str(inp.get("good_id", ""))
	var in_internal := str(inp.get("internal_name", ""))
	for b in MatchState.buildings.values():
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
	var live: Dictionary = MatchState.get_building(iid) if iid != "" else {}
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
	return _COMPANIES[acc % _COMPANIES.size()]

# Purchase price shown on the NPC Buy button (matches the Buildings-market listing).
static func buy_price(building: Dictionary) -> int:
	return int(round(MatchState.purchase_cost_after_advisor(float(BuildingPrice.sale_price(building)))))

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


## Delivery blockers for a building UNDER CONSTRUCTION: a build material that must travel by
## pipeline (a liquid/gas) can only reach the site if that tile carries a suitable pipe. If it
## doesn't, the shipment can never be created and the build stalls forever — so surface it as a
## diagnostics row (one per blocked material), mirroring the run-time "No input pipeline" rows.
## Takes the `constr` dict from construction() (it carries tile_id + the materials list).
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
			continue   # solids are trucked in — they don't need a pipe
		if Catalog.tile_can_pipe_good(tile, gid):
			continue   # the site already carries a pipe that can move this good
		var nm := str(m.get("name", Catalog.get_display_name(gid)))
		if Catalog.get_transport_class(gid) == "hazard_liquid":
			rows.append(_row("bad", "pipe", "No reinforced pipeline to deliver %s" % nm,
				"%s is a hazardous liquid — it can only reach this site by reinforced pipeline, and none is built here. Lay reinforced pipes (or build on a tile that has them) or the build can't finish." % nm))
		else:
			rows.append(_row("bad", "pipe", "No pipeline to deliver %s" % nm,
				"%s is a liquid or gas — it can only reach this site by pipeline, and none is built here. Lay pipes (or build on a tile that has them) or the build can't finish." % nm))
	return rows

# --- Battery storage ------------------------------------------------------------------------
static func battery(building: Dictionary) -> Dictionary:
	var tile_id := str(building.get("tile_id", ""))
	return {
		"loaded": MatchState.tile_battery_cells_loaded(tile_id),
		"slots": MatchState.tile_battery_slots(tile_id),
		"firming_cap": MatchState.tile_firming_cap(tile_id),
	}

static func _routes_to_tile(producer: Dictionary, output: Dictionary, tile_id: String) -> bool:
	if tile_id == "":
		return false
	var gid := str(output.get("good_id", ""))
	if gid == "":
		gid = str(Catalog.get_good_by_internal_name(str(output.get("internal_name", ""))).get("id", ""))
	if gid == "":
		return false
	var piid := str(producer.get("instance_id", ""))
	# Explicit output route to this tile.
	if MatchState.get_output_stockpile_destination(piid, gid) == tile_id:
		return true
	# Same-tile producer whose output lands in the SHARED tile stockpile (an iron-ingot furnace
	# feeding a steel furnace on the same tile): default STOCKPILE_ALL, unrouted, not sold to market.
	if str(producer.get("tile_id", "")) == tile_id \
			and MatchState.is_player_owned(producer) \
			and not MatchState.is_output_market(piid, gid) \
			and MatchState.get_output_stockpile_destination(piid, gid) == "" \
			and MatchState.sell_mode == MatchState.SellMode.STOCKPILE_ALL:
		return true
	return false
