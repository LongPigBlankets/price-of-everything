extends Node
# Phase 3: imputed unit-cost engine — any number of inputs, any number of outputs.
# Multi-output buildings use MARKET-VALUE (relative-sales-value) allocation: the
# total production cost is split across all outputs in proportion to each output's
# market value (price × qty). Every co-product therefore carries the same fraction
# of cost relative to its own market price.

signal costs_updated

var last_result: Dictionary = {"per_building": {}, "per_good": {}}

func get_building_unit_cost(instance_id: String) -> float:
	var bd: Dictionary = last_result.get("per_building", {}).get(instance_id, {})
	return bd.get("unit_cost", -1.0)

func get_good_unit_cost(good_id: String) -> float:
	var pg: Dictionary = last_result.get("per_good", {}).get(good_id, {})
	return pg.get("unit_cost", -1.0)

# Returns the allocated unit cost for a specific output good of a building, or -1.0.
func get_building_output_cost(instance_id: String, good_id: String) -> float:
	var bd: Dictionary = last_result.get("per_building", {}).get(instance_id, {})
	return bd.get("output_costs", {}).get(good_id, -1.0)

# solve() accepts a list of BuildingTurnReport dicts (from production.gd) and returns:
# {
#   per_building: { instance_id -> {
#       output_good_id,   # primary (first) output good ID
#       unit_cost,        # £/unit of the primary output
#       output_costs,     # { good_id -> £/unit } allocated cost for every output
#       total_cost,       # gross production cost this turn
#       input_material_cost, power_cost, labour_cost, maintenance_cost, inbound_transport,
#       output_qty,       # units of primary output produced this turn
#       output_count,     # number of distinct outputs
#   }}
#   per_good: { good_id -> { unit_cost, pct_of_market } }
# }
func solve(reports: Array) -> Dictionary:
	# ── 1. All buildings with at least one output are eligible ───────────────
	var eligible: Array = []
	for report in reports:
		var n_out: int = (report.get("outputs_produced", {}) as Dictionary).size()
		if n_out >= 1:
			eligible.append(report)

	if eligible.is_empty():
		return {"per_building": {}, "per_good": {}}

	# ── 2. Determine which goods are produced internally (any output slot) ───
	var internally_produced: Dictionary = {}  # good_id -> true
	for report in eligible:
		for gid in (report.get("outputs_produced", {}) as Dictionary):
			internally_produced[gid] = true

	# ── 3. Seed goods used as inputs but not produced internally at market price
	var priced_goods: Dictionary = {}  # good_id -> float unit cost
	for report in eligible:
		for gid in (report.get("inputs_consumed", {}) as Dictionary):
			if internally_produced.has(gid) or priced_goods.has(gid):
				continue
			var mp: float = MarketState.get_price(gid)
			priced_goods[gid] = mp
			print("[CostSolver] External leaf: %s @ £%.4f (market price)" % [
				Catalog.get_display_name(gid), mp
			])

	# ── 4. Topological sweep ─────────────────────────────────────────────────
	var per_building: Dictionary = {}
	var unresolved: Array = eligible.duplicate()

	for _sweep in range(20):
		if unresolved.is_empty():
			break
		var newly_resolved: Array = []
		var still_unresolved: Array = []

		for report in unresolved:
			# Solve only when every input good already has a price
			var inputs: Dictionary = report.get("inputs_consumed", {})
			var ready := true
			for gid in inputs:
				if not priced_goods.has(gid):
					ready = false
					break
			if not ready:
				still_unresolved.append(report)
				continue

			# Gross cost components
			var input_material_cost: float = 0.0
			for gid in inputs:
				input_material_cost += priced_goods[gid] * float(inputs[gid])

			var power_cost: float     = report.get("power_cost", 0.0)
			var labour_cost: float    = report.get("labour_cost", 0.0)
			var maint_cost: float     = report.get("maintenance_cost", 0.0)
			var transport_cost: float = report.get("inbound_transport", 0.0)
			var total_cost: float     = input_material_cost + power_cost + labour_cost + maint_cost + transport_cost

			# Market-value allocation across all outputs
			var outputs: Dictionary = report.get("outputs_produced", {})
			var output_keys: Array  = outputs.keys() as Array

			var total_output_value: float = 0.0
			for gid in output_keys:
				total_output_value += _market_value(str(gid)) * float(outputs[gid])

			var output_costs: Dictionary = {}
			for gid in output_keys:
				var qty: float = float(outputs[gid])
				var unit: float
				if total_output_value > 0.0:
					# allocated_cost = total_cost * (price*qty)/total_value;  unit = alloc/qty
					unit = total_cost * _market_value(str(gid)) / total_output_value
				elif qty > 0.0:
					# No market value to weight by → split by physical quantity
					var total_qty := 0.0
					for k in output_keys:
						total_qty += float(outputs[k])
					unit = (total_cost / total_qty) if total_qty > 0.0 else 0.0
				else:
					unit = 0.0
				output_costs[str(gid)] = unit

			var primary_gid: String = str(output_keys[0])
			var primary_qty: float  = float(outputs[output_keys[0]])

			per_building[report.get("instance_id", "")] = {
				"output_good_id":      primary_gid,
				"unit_cost":           output_costs[primary_gid],
				"output_costs":        output_costs,
				"total_cost":          total_cost,
				"input_material_cost": input_material_cost,
				"power_cost":          power_cost,
				"labour_cost":         labour_cost,
				"maintenance_cost":    maint_cost,
				"inbound_transport":   transport_cost,
				"output_qty":          primary_qty,
				"output_count":        output_keys.size(),
			}
			newly_resolved.append(report)

		# Qty-weighted average per good across ALL outputs → feeds downstream
		var accum: Dictionary = {}
		for report in newly_resolved:
			var bd: Dictionary = per_building[report.get("instance_id", "")]
			var outs: Dictionary = report.get("outputs_produced", {})
			for gid in outs:
				var g: String = str(gid)
				var q: float  = float(outs[gid])
				if not accum.has(g):
					accum[g] = {"w": 0.0, "q": 0.0}
				accum[g].w += bd.output_costs[g] * q
				accum[g].q += q
		for gid in accum:
			if accum[gid].q > 0.0:
				priced_goods[gid] = accum[gid].w / accum[gid].q

		unresolved = still_unresolved
		if newly_resolved.is_empty():
			break

	# ── 5. Starvation guard ──────────────────────────────────────────────────
	for report in unresolved:
		var outputs: Dictionary = report.get("outputs_produced", {})
		if outputs.is_empty():
			continue
		var gid: String = str((outputs.keys() as Array)[0])
		var mp: float   = MarketState.get_price(gid)
		push_warning("[CostSolver] Cycle/starvation guard: %s seeded at market £%.4f" % [
			Catalog.get_display_name(gid), mp
		])
		priced_goods[gid] = mp

	# ── 6. Build per_good — qty-weighted average across all buildings/outputs ─
	var good_accum: Dictionary = {}  # good_id -> {w, q}
	for report in eligible:
		var iid: String = report.get("instance_id", "")
		if not per_building.has(iid):
			continue
		var bd: Dictionary = per_building[iid]
		var outs: Dictionary = report.get("outputs_produced", {})
		for gid in outs:
			var g: String = str(gid)
			if not internally_produced.has(g):
				continue
			var q: float = float(outs[gid])
			if not good_accum.has(g):
				good_accum[g] = {"w": 0.0, "q": 0.0}
			good_accum[g].w += bd.output_costs[g] * q
			good_accum[g].q += q

	var per_good: Dictionary = {}
	for gid in good_accum:
		var acc: Dictionary   = good_accum[gid]
		var uc: float         = (acc.w / acc.q) if acc.q > 0.0 else 0.0
		var base_price: float = Catalog.get_base_price(gid)
		var pct: float        = (uc / base_price * 100.0) if base_price > 0.0 else 0.0
		per_good[gid] = {"unit_cost": uc, "pct_of_market": pct}

	_log_results(per_building, per_good)
	last_result = {"per_building": per_building, "per_good": per_good}
	costs_updated.emit()
	return last_result


# Market value of one unit of a good for allocation weighting:
# live market price, falling back to catalog base price.
func _market_value(good_id: String) -> float:
	var mp: float = MarketState.get_price(good_id)
	if mp > 0.0:
		return mp
	return Catalog.get_base_price(good_id)


func _log_results(per_building: Dictionary, per_good: Dictionary) -> void:
	print("[CostSolver] ── Per-building costs ────────────────────────────────")
	for iid in per_building:
		var b: Dictionary  = per_building[iid]
		var gname: String  = Catalog.get_display_name(b.output_good_id)
		print("[CostSolver]  %s → %s: £%.4f/unit (primary of %d outputs)" % [
			iid, gname, b.unit_cost, b.output_count
		])
		print("[CostSolver]    inputs £%.4f | power £%.4f | labour £%.4f | maint £%.4f | transport £%.4f  →  gross £%.4f" % [
			b.input_material_cost, b.power_cost, b.labour_cost,
			b.maintenance_cost, b.inbound_transport, b.total_cost
		])
		if b.output_count > 1:
			for gid in b.output_costs:
				print("[CostSolver]      • %s: £%.4f/unit" % [
					Catalog.get_display_name(gid), b.output_costs[gid]
				])
	print("[CostSolver] ── Per-good costs ─────────────────────────────────────")
	for gid in per_good:
		var pg: Dictionary = per_good[gid]
		print("[CostSolver]  %-20s £%.4f/unit  (%.1f%% of market)" % [
			Catalog.get_display_name(gid), pg.unit_cost, pg.pct_of_market
		])
	print("[CostSolver] ────────────────────────────────────────────────────────")
