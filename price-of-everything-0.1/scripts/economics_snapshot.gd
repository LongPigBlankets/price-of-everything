extends RefCounted
## Read-only accounting interface. Call after turn_resolution_completed, with cash
## captured before commit_turn. Production reports are cost attribution, not cash P&L.

static func capture(cash_before: float, instance_id: String = "") -> Dictionary:
	var summary: Dictionary = Production.last_turn_summary.duplicate(true)
	var income := float(summary.get("money_in", 0.0))
	var expenses := float(summary.get("money_out", 0.0))
	var delta := MatchState.money - cash_before
	var output_costs: Dictionary = {}
	var building: Dictionary = MatchState.get_building(instance_id)
	var recipe: Dictionary = Catalog.get_recipe(str(building.get("recipe_id", "")))
	for output: Dictionary in recipe.get("outputs", []):
		var gid := str(output.get("good_id", ""))
		output_costs[gid] = CostSolver.get_building_output_cost(instance_id, gid)
	return {
		"empire": summary,
		"cash_before": cash_before,
		"cash_after": MatchState.money,
		"cash_delta": delta,
		"sales": float(summary.get("goods_sales_revenue", 0.0)) + float(summary.get("power_sales_revenue", 0.0)),
		"reported_net": income - expenses,
		"cash_reconciliation_residual": delta - (income - expenses),
		"building": Production.turn_report_for(instance_id).duplicate(true),
		"building_output_unit_costs": output_costs,
		"building_carbon_tax": float(Production.carbon_tax_by_building.get(instance_id, 0.0)),
		"stockpile": Stockpile.export_state(),
		"shipments": MatchState.get_pending_transport_shipments(),
	}
