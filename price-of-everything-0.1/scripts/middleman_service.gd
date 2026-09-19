extends RefCounted
## Phase-1 building-private operating service. Authoritative state lives in MatchState.
const Contract := preload("res://scripts/middleman_contract.gd")

static func enabled(iid: String) -> bool:
	return int(MatchState.middleman_service.get("schema", 0)) == 1 and MatchState.middleman_service.get("buildings", {}).has(iid)

static func material_tradeable(gid: String, side: String) -> bool:
	var good := Catalog.get_good(gid)
	return Contract.CLASS_RATES.has(str(good.get("transport_class", ""))) and bool(good.get("is_buyable" if side == "input" else "is_sellable", false))

# Historical benchmark recipe set; not an eligibility restriction.
const CHAIN_RECIPES := ["r_003", "r_005", "r_007", "r_008", "r_009"]

static func goods() -> Array:
	return Catalog.all_goods().filter(func(g: Dictionary) -> bool: return Contract.CLASS_RATES.has(str(g.get("transport_class", "")))).map(func(g: Dictionary) -> String: return str(g.id))

static func recipe_side(recipe: Dictionary, side: String) -> bool:
	return (recipe.get("inputs" if side == "input" else "outputs", []) as Array).any(func(item: Dictionary) -> bool: return material_tradeable(str(item.get("good_id", "")), side))

static func supplies_good(iid: String, gid: String) -> bool:
	return uses_inputs(iid) and material_tradeable(gid, "input")

static func buys_output(iid: String, gid: String) -> bool:
	return uses_outputs(iid) and material_tradeable(gid, "output")

static func uses_inputs(iid: String) -> bool:
	return enabled(iid) and recipe_side(Catalog.get_recipe(str(BuildingState.get_building(iid).get("recipe_id", ""))), "input") and str(entry(iid).get("input_mode","middleman")) == "middleman"

static func uses_outputs(iid: String) -> bool:
	return enabled(iid) and recipe_side(Catalog.get_recipe(str(BuildingState.get_building(iid).get("recipe_id", ""))), "output") and str(entry(iid).get("output_mode","middleman")) == "middleman"

static func fully_managed(iid: String) -> bool:
	var recipe := Catalog.get_recipe(str(BuildingState.get_building(iid).get("recipe_id", "")))
	return enabled(iid) and (uses_inputs(iid) or (recipe.get("inputs", []) as Array).is_empty()) and uses_outputs(iid) and (recipe.get("inputs", []) as Array).all(func(i: Dictionary) -> bool: return material_tradeable(str(i.good_id), "input")) and (recipe.get("outputs", []) as Array).all(func(o: Dictionary) -> bool: return material_tradeable(str(o.good_id), "output"))

static func eligible(b: Dictionary) -> bool:
	return BuildingState.is_player_owned(b) and (recipe_side(Catalog.get_recipe(str(b.get("recipe_id", ""))), "input") or recipe_side(Catalog.get_recipe(str(b.get("recipe_id", ""))), "output")) and str(MatchState.ruleset.get("logistics_model","")) == "middleman_v1"

static func coefficient(b: Dictionary) -> float:
	return preload("res://scripts/middleman_locations.gd").coefficient(str(b.get("tile_id", "")))

## Change one side atomically; release only that side's paid goods. Existing
## shipments keep their owner/destination and are never cancelled or rewritten.
static func set_mode(iid: String, side: String, mode: String, validate_only: bool = false) -> Dictionary:
	if TurnManager.current_phase != TurnManager.Phase.DECIDE or TurnManager.is_resolving:
		return {"ok":false,"reason":"Wait until the turn finishes."}
	if side not in ["input","output"] or mode not in ["middleman","managed"]:
		return {"ok":false,"reason":"Unknown logistics option."}
	var b := BuildingState.get_building(iid)
	if not eligible(b): return {"ok":false,"reason":"No tradeable material inputs or outputs on this building."}
	if BuildingWorks.is_retooling(iid) or BuildingWorks.is_upgrading(iid) or BuildingWorks.is_demolishing(iid):
		return {"ok":false,"reason":"Finish building works first."}
	if mode == "middleman" and not recipe_side(Catalog.get_recipe(str(b.recipe_id)), side):
		return {"ok":false,"reason":"This side uses the grid or has no tradeable materials."}
	if mode == "middleman" and MatchState.building_tabs.has(iid):
		return {"ok":false,"reason":"Resolve this building's credit tab first."}
	var e := entry(iid)
	var current := str(e.get(side+"_mode","middleman")) if enabled(iid) else "managed"
	if current == mode: return {"ok":true}
	var key := "inputs" if side == "input" else "outputs"
	var held: Dictionary = e.get(key,{})
	var total := 0
	for qty in held.values(): total += int(qty)
	if mode == "managed" and Stockpile.get_free_capacity(str(b.tile_id)) < total:
		return {"ok":false,"reason":"Not enough tile storage for the paid goods. Free capacity first."}
	if validate_only: return {"ok":true}
	if e.is_empty():
		if MatchState.middleman_service.is_empty():
			MatchState.middleman_service={"schema":1,"match_id":str(Time.get_unix_time_from_system())+":"+str(Time.get_ticks_usec()),"buildings":{}}
		e={"coefficient":coefficient(b),"recipe_id":str(b.recipe_id),"inputs":{},"outputs":{},"turn":-1,"state":"idle","receipts":{},"input_mode":"managed","output_mode":"managed"}
		MatchState.middleman_service.buildings[iid]=e
	if mode == "managed":
		for gid in held: Stockpile.add(str(b.tile_id),str(gid),int(held[gid]))
		held.clear()
		if side == "input": e["holding_receipts"]=[]
		# Start retaining output when taking control: never silently sell it.
		if side == "output":
			for output: Dictionary in Catalog.get_recipe(str(b.recipe_id)).get("outputs",[]):
				MatchState.set_output_stockpile_destination(iid,str(b.tile_id),str(output.good_id))
	e[side+"_mode"]=mode
	e.turn=-1
	e.state="idle"
	if not uses_inputs(iid) and not uses_outputs(iid):
		MatchState.middleman_service.buildings.erase(iid)
	TransportState.transport_shipments_changed.emit()
	return {"ok":true}

static func entry(iid: String) -> Dictionary:
	return MatchState.middleman_service.get("buildings", {}).get(iid, {})

static func has_assets(iid: String) -> bool:
	var e := entry(iid)
	for key in ["inputs", "outputs"]:
		for qty in e.get(key, {}).values():
			if int(qty) > 0: return true
	return false

static func enable(iid: String) -> Dictionary:
	if TurnManager.current_phase != TurnManager.Phase.DECIDE: return {"ok":false,"reason":"Enable service in DECIDE."}
	var b: Dictionary = BuildingState.get_building(iid)
	if not eligible(b):
		return {"ok":false,"reason":"No tradeable material service for this building."}
	if str(MatchState.ruleset.get("logistics_model", "")) != "middleman_v1":
		return {"ok":false,"reason":"Requires middleman_v1 ruleset."}
	if MatchState.building_tabs.has(iid) or BuildingWorks.is_retooling(iid) or BuildingWorks.is_upgrading(iid) or BuildingWorks.is_demolishing(iid):
		return {"ok":false,"reason":"Finish credit/building works before enabling service."}
	if enabled(iid): return {"ok":true}
	# Switching an existing physical pipeline is intentionally outside this slice.
	for s: Dictionary in TransportState.pending_transport_shipments:
		if str(s.get("destination_tile", "")) == str(b.tile_id) or str(s.get("source_tile", "")) == str(b.tile_id):
			return {"ok":false,"reason":"Finish outstanding physical shipments first."}
	if MatchState.middleman_service.is_empty():
		MatchState.middleman_service = {"schema":1,"match_id":str(Time.get_unix_time_from_system())+":"+str(Time.get_ticks_usec()),"buildings":{}}
	MatchState.middleman_service.buildings[iid] = {"coefficient":coefficient(b),"recipe_id":str(b.recipe_id),"inputs":{},"outputs":{},"turn":-1,"state":"idle","receipts":{}}
	return {"ok":true}

static func prices() -> Dictionary:
	var result := {}
	for gid in goods():
		var good: Dictionary = Catalog.get_good(gid)
		result[gid] = {"reference":MarketState.get_price(gid),"buy":MarketState.get_buy_price(gid),
			"sale":MarketState.get_sale_price(gid,{"good_id":gid,"good_internal":str(good.get("internal_name", ""))}),
			"transport_class":str(good.get("transport_class", "")), "is_buyable":bool(good.get("is_buyable", false)), "is_sellable":bool(good.get("is_sellable", false))}
	return result

static func prepare(buildings: Array, summary: Dictionary) -> void:
	if MatchState.middleman_service.is_empty(): return
	var snapshot := prices()
	var protected := MatchState.unpaid_purchase_total()
	for row: Dictionary in preload("res://scripts/cash_commitments.gd").payments():
		if str(row.kind) != "shipment" and int(row.due_in) <= 1: protected += float(row.amount)
	# Fixed upkeep is due even for rejected batches. Protect all existing buildings once.
	for b: Dictionary in buildings:
		protected += Production._calculate_maintenance_cost(b)
		if not BuildingWorks.is_building_paused(str(b.instance_id)):
			protected += Production._calculate_labour_cost(b, Catalog.get_recipe(str(b.recipe_id)))
	var reserved_power := 0.0
	var reserved_draw := {}
	var ordered := buildings.duplicate()
	ordered.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		var ai := str(a.instance_id).get_slice("_",3).hex_to_int()
		var bi := str(b.instance_id).get_slice("_",3).hex_to_int()
		return str(a.instance_id)<str(b.instance_id) if ai==bi else ai<bi)
	for b: Dictionary in ordered:
		var iid := str(b.instance_id)
		if not enabled(iid): continue
		var e := entry(iid)
		if int(e.turn) == TurnManager.current_turn: continue
		e.coefficient = coefficient(b)
		e.turn = TurnManager.current_turn
		e.operation_id = Contract.operation_id(str(MatchState.middleman_service.match_id), TurnManager.current_turn, iid)
		e.receipts = {}
		e.prices = snapshot.duplicate(true)
		e.state = "rejected_before_supply"
		e.reason = ""
		if not (e.outputs as Dictionary).is_empty():
			e.state = "blocked_with_private_output"
			continue
		if str(b.recipe_id) != str(e.recipe_id) or BuildingWorks.is_retooling(iid) or BuildingWorks.is_demolishing(iid) or BuildingWorks.is_building_paused(iid):
			e.reason = "Building paused or recipe changed."
			continue
		var recipe: Dictionary = Catalog.get_recipe(str(b.recipe_id))
		if not uses_inputs(iid):
			e.state = "supplied"
			continue
		var check: Dictionary = Production._can_run_recipe(b, recipe, true)
		if not bool(check.can_run):
			e.reason = "Production unavailable: " + str(check.missing)
			continue
		var required := {}
		for input: Dictionary in recipe.get("inputs", []):
			if material_tradeable(str(input.good_id), "input"): required[str(input.good_id)] = Production._scaled_input_qty(input,b)
		var banned := false
		for gid in required:
			if int(required[gid]) > int(e.inputs.get(gid,0)) and PolicyState.import_banned(str(gid),TurnManager.current_turn): banned = true
		if banned:
			e.reason = "Input imports prohibited."
			continue
		var draw: int = Production._effective_energy_req(b,recipe)
		var tile := str(b.tile_id)
		if int(reserved_draw.get(tile,0))+draw > Power.tile_power_cap(tile):
			e.reason = "Insufficient cable capacity for another batch."
			continue
		var power_rate := EconomyConfig.GRID_BUY_PRICE * maxf(0.0,1.0+float(Modifiers.resolve_pct("grid_buy_price","*",{}).get("net",0.0))/100.0) + MarketState.carbon_component(str(Catalog.get_good_by_internal_name("power").get("id","")))
		var running := draw * power_rate
		for input: Dictionary in recipe.get("inputs", []):
			running += PolicyState.carbon_charge(str(input.good_id), Production._scaled_input_qty(input,b), TurnManager.current_turn)
		var plan := Contract.plan_batch(required,e.inputs,snapshot,float(e.coefficient),{
			"cash":MatchState.money,"credit_available":maxf(0.0,LoanState.available_capacity()),
			"commitments":protected+reserved_power,"running_reserve":running,"minimum_loan":EconomyConfig.LOAN_MINIMUM,
			"building_credit_tab":MatchState.building_tabs.has(iid)},true,goods())
		if not bool(plan.ok):
			e.reason = str(plan.reason)
			continue
		if float(plan.funding_draw) > 0.0:
			if not LoanState.take_loan(float(plan.funding_draw)):
				e.reason = "Funding unavailable."
				continue
			summary["middleman_financing"] = float(summary.get("middleman_financing",0.0))+float(plan.funding_draw)
		reserved_power += running
		reserved_draw[tile] = int(reserved_draw.get(tile,0))+draw
		var q: Dictionary = plan.purchase
		MatchState.add_money(-float(q.cash_out))
		summary.goods_purchased_cost += float(q.goods_value)
		summary.money_out += float(q.cash_out)
		fee(summary,float(q.fee))
		for item: Dictionary in q.items:
			var gid := str(item.good)
			e.inputs[gid] = int(e.inputs.get(gid,0))+int(item.quantity)
			MarketState.record_market_buy_volume(gid,int(item.quantity))
			summary.purchased[gid] = int(summary.purchased.get(gid,0))+int(item.quantity)
			summary.purchased_cost[gid] = float(summary.purchased_cost.get(gid,0.0))+float(item.goods_value)
			MatchState.goods_movement_recorded.emit("buy",gid,0)
		Production._accumulate_by_type(summary.goods_purchased_by_type,str(b.building_id),float(q.goods_value))
		if not e.has("holding_receipts"): e.holding_receipts = []
		if not q.items.is_empty(): e.holding_receipts.append({"operation_id":str(e.operation_id),"purchase":q.duplicate(true)})
		e.required = required
		e.receipts.purchase = q.duplicate(true)
		e.receipts.input_fee = float(q.fee)
		e.state = "supplied"

static func ready(iid: String) -> bool:
	var e := entry(iid)
	return int(e.get("turn",-1)) == TurnManager.current_turn and str(e.get("state","")) == "supplied"

static func consume(iid: String, gid: String, qty: int) -> void:
	var e := entry(iid)
	if not ready(iid) or qty <= 0: return
	if not e.receipts.has("consumed"): e.receipts.consumed = {}
	if e.receipts.consumed.has(gid): return
	if int(e.inputs.get(gid,0)) < qty or int(e.required.get(gid,0)) != qty: return
	e.receipts.consumed[gid] = qty
	e.inputs[gid] = int(e.inputs.get(gid,0))-qty
	if int(e.inputs[gid]) == 0: e.inputs.erase(gid)
	if (e.inputs as Dictionary).is_empty():
		e.receipts["input_origins"] = e.get("holding_receipts",[]).duplicate(true)
		e["holding_receipts"] = []

static func produce(iid: String, gid: String, qty: int) -> void:
	var e := entry(iid)
	if int(e.get("turn", -1)) != TurnManager.current_turn or str(e.get("state", "")) not in ["supplied", "produced"] or qty <= 0 or not (e.inputs as Dictionary).is_empty(): return
	if e.receipts.get("produced", {}).has(gid): return
	if uses_inputs(iid) and not (e.get("required", {}) as Dictionary).is_empty() and not e.receipts.has("consumed"): return
	e.outputs[gid] = int(e.outputs.get(gid,0))+qty
	e.state = "produced"
	e.receipts.produced = (e.outputs as Dictionary).duplicate(true)

static func fee(summary: Dictionary, amount: float) -> void:
	# Included within transport total for existing cash/UI readers, never charged twice.
	summary["middleman_fee"] = float(summary.get("middleman_fee",0.0))+amount
	summary.transport_paid += amount
	summary.transport_breakdown["middleman"] = float(summary.transport_breakdown.get("middleman",0.0))+amount

static func settle(buildings: Array, summary: Dictionary) -> void:
	for b: Dictionary in buildings:
		var iid := str(b.instance_id)
		if not enabled(iid): continue
		var e := entry(iid)
		if int(e.turn) != TurnManager.current_turn or e.receipts.has("sale"): continue
		if (e.outputs as Dictionary).is_empty():
			if str(e.state) == "supplied": e.state = "blocked_with_private_inputs" if not (e.inputs as Dictionary).is_empty() else "completed"
			continue
		var lines := []
		for gid in e.outputs: lines.append({"good":gid,"quantity":int(e.outputs[gid])})
		var q := Contract.quote("sell",lines,e.prices,float(e.coefficient),goods())
		if not bool(q.ok) or float(q.net_receipt) < 0.0:
			e.state = "blocked_with_private_output"
			e.reason = "Sale unavailable or negative net proceeds."
			continue
		# Record before synchronous notifications; duplicate settlement cannot pay twice.
		e.receipts.sale = q.duplicate(true)
		e.receipts.output_fee = float(q.fee)
		e.outputs.clear()
		e.state = "settled"
		MatchState.add_money(float(q.net_receipt))
		summary.money_out += float(q.fee)
		fee(summary,float(q.fee))
		var sale := {"tile_id":str(b.tile_id),"items":[],"total_qty":0,"total_revenue":float(q.goods_value),"middleman":true}
		for item: Dictionary in q.items:
			var gid := str(item.good)
			MarketState.record_market_sale_volume(gid,int(item.quantity))
			Production._add_summary_sale(summary,gid,int(item.quantity),float(item.goods_value))
			sale.items.append({"good_id":gid,"qty":int(item.quantity),"revenue":float(item.goods_value)})
			sale.total_qty += int(item.quantity)
		MatchState.record_tile_sale(str(b.tile_id),int(sale.total_qty),float(q.goods_value))
		MatchState.goods_movement_recorded.emit("sale","",0)
		MatchState.emit_stockpile_market_sale_completed(sale)

## Explicit asset disposition: transfer to ordinary player stock only if all units fit.
static func release_to_stock(iid: String) -> Dictionary:
	if TurnManager.current_phase != TurnManager.Phase.DECIDE: return {"ok":false,"reason":"Wait until DECIDE."}
	var e := entry(iid)
	var b: Dictionary = BuildingState.get_building(iid)
	if e.is_empty() or b.is_empty(): return {"ok":false,"reason":"No service building."}
	var goods := {}
	var total := 0
	for key in ["inputs","outputs"]:
		for gid in e[key]:
			goods[gid] = int(goods.get(gid,0))+int(e[key][gid])
			total += int(e[key][gid])
	if Stockpile.get_free_capacity(str(b.tile_id)) < total: return {"ok":false,"reason":"Insufficient owned storage."}
	for gid in goods: Stockpile.add(str(b.tile_id),str(gid),int(goods[gid]))
	e.inputs.clear()
	e.outputs.clear()
	e["holding_receipts"] = []
	return {"ok":true}

static func disable(iid: String) -> Dictionary:
	if TurnManager.current_phase != TurnManager.Phase.DECIDE or has_assets(iid):
		return {"ok":false,"reason":"Resolve private holdings in DECIDE first."}
	if enabled(iid): MatchState.middleman_service.buildings.erase(iid)
	return {"ok":true}

## Read-only next-cycle preview. Prices share the settlement quote contract.
static func preview(iid: String) -> Dictionary:
	return company_previews().get(iid,preview_building(BuildingState.get_building(iid)))

static func preview_building(b: Dictionary) -> Dictionary:
	var iid := str(b.get("instance_id",""))
	if b.is_empty(): return {"ok":false,"reason":"No building."}
	var recipe: Dictionary = Catalog.get_recipe(str(b.get("recipe_id","")))
	if not recipe_side(recipe, "input") and not recipe_side(recipe, "output"):
		return {"ok":false,"reason":"No tradeable material service for this recipe."}
	var e := entry(iid)
	var input_service := recipe_side(recipe, "input") and (not enabled(iid) or uses_inputs(iid))
	var output_service := recipe_side(recipe, "output") and (not enabled(iid) or uses_outputs(iid))
	var factor := coefficient(b)
	var held: Dictionary = e.get("inputs",{})
	var required := {}
	for input: Dictionary in recipe.get("inputs",[]):
		if input_service and material_tradeable(str(input.good_id), "input"): required[str(input.good_id)] = Production._scaled_input_qty(input,b)
	var snapshot := prices()
	var lines := []
	for gid in required: lines.append({"good":gid,"quantity":maxi(0,int(required[gid])-int(held.get(gid,0)))})
	var buy := Contract.quote("buy",lines,snapshot,factor,goods())
	var output_lines := []
	for output: Dictionary in recipe.get("outputs",[]):
		if not material_tradeable(str(output.good_id), "output"): continue
		var single := recipe.duplicate(true)
		single.outputs = [output]
		var qty: int = preload("res://scripts/building_status.gd").effective_output_qty(b,single)
		qty = int(round(float(qty)*MatchState.startup_capacity_multiplier(b)))
		var derate := float(Production._intermittency_by_building.get(iid,{}).get("derate",0.0))
		qty = int(round(float(qty)*(1.0-derate)))
		output_lines.append({"good":str(output.good_id),"quantity":qty})
	var selling_held := not (e.get("outputs",{}) as Dictionary).is_empty()
	if selling_held:
		output_lines.clear()
		for gid in e.outputs: output_lines.append({"good":gid,"quantity":int(e.outputs[gid])})
		buy = Contract.quote("buy",[],snapshot,factor,goods())
	var sale := Contract.quote("sell",output_lines if output_service else [],snapshot,factor,goods())
	if not bool(buy.ok) or not bool(sale.ok): return {"ok":false,"reason":"Unsupported service quote."}
	var power := 0.0 if selling_held else Production._effective_energy_req(b,recipe)*(EconomyConfig.GRID_BUY_PRICE*maxf(0.0,1.0+float(Modifiers.resolve_pct("grid_buy_price","*",{}).get("net",0.0))/100.0)+MarketState.carbon_component(str(Catalog.get_good_by_internal_name("power").get("id",""))))
	var grid_value := 0.0
	if str(recipe.get("output_name", "")) == "power":
		grid_value = Production._effective_power_output(b, recipe) * EconomyConfig.GRID_SELL_PRICE * maxf(0.0, 1.0 + float(Modifiers.resolve_pct("grid_sell_price", "*", {}).get("net", 0.0))/100.0)
	var carbon := 0.0
	if not selling_held:
		for input: Dictionary in recipe.get("inputs", []): carbon += PolicyState.carbon_charge(str(input.good_id), Production._scaled_input_qty(input,b), TurnManager.current_turn)
	var labour := 0.0 if BuildingWorks.is_building_paused(iid) else Production._calculate_labour_cost(b,recipe)
	var maintenance: float = Production._calculate_maintenance_cost(b)
	var reserve := MatchState.unpaid_purchase_total()
	for row: Dictionary in preload("res://scripts/cash_commitments.gd").payments():
		if str(row.kind) != "shipment" and int(row.due_in)<=1: reserve += float(row.amount)
	for other: Dictionary in BuildingState.buildings.values():
		if not BuildingState.is_player_owned(other) or str(other.instance_id)==iid: continue
		reserve += Production._calculate_maintenance_cost(other)
		if not BuildingWorks.is_building_paused(str(other.instance_id)):
			reserve += Production._calculate_labour_cost(other,Catalog.get_recipe(str(other.recipe_id)))
	var feasible := bool(Production._can_run_recipe(b, recipe, input_service).can_run) and not BuildingWorks.is_building_paused(iid) and not BuildingWorks.is_retooling(iid) and not BuildingWorks.is_demolishing(iid)
	if not input_service:
		feasible = feasible and bool(Production._can_run_recipe(b,recipe).can_run)
	for gid in required:
		if int(required[gid])>int(held.get(gid,0)) and PolicyState.import_banned(str(gid),TurnManager.current_turn): feasible=false
	var budget := Contract.plan_batch(required,held,snapshot,factor,{"cash":MatchState.money,"credit_available":maxf(0.0,LoanState.available_capacity()),"commitments":reserve,"running_reserve":labour+maintenance+power+carbon,"minimum_loan":EconomyConfig.LOAN_MINIMUM,"building_credit_tab":MatchState.building_tabs.has(iid)},feasible,goods())
	var reason := ready_message(iid) if bool(budget.ok) else str(budget.get("reason","Unavailable")).replace("_"," ").capitalize()
	if selling_held: reason = "Sell retained output before starting another batch."
	return {"ok":true,"can_run":bool(budget.ok) and not selling_held,"reason":reason,"feasible":feasible,"required":required,"selling_held":selling_held,
		"buy":buy,"sale":sale,"fee":float(buy.fee)+float(sale.fee),"labour":labour,"maintenance":maintenance,"power":power,"carbon_tax":carbon,"grid_value":grid_value,
		"upfront":float(buy.cash_out)+labour+maintenance+power+carbon,"protected_commitments":reserve,
		"funding_draw":float(budget.get("funding_draw",0.0)),"inputs":held.duplicate(true),"outputs":e.get("outputs",{}).duplicate(true),
		"net":grid_value+float(sale.net_receipt)-float(buy.cash_out)-labour-maintenance-power-carbon}

static func default_for(recipe_id: String, tile: String) -> bool:
	return bool(MatchState.ruleset.get("middleman_new_buildings",false)) and str(MatchState.ruleset.get("logistics_model",""))=="middleman_v1" and tile != "" and (recipe_side(Catalog.get_recipe(recipe_id), "input") or recipe_side(Catalog.get_recipe(recipe_id), "output"))

## Only new completed construction, before any operating orders exist.
static func enroll_completed(iid: String) -> void:
	var b: Dictionary = BuildingState.get_building(iid)
	if b.is_empty() or not default_for(str(b.recipe_id),str(b.tile_id)) or MatchState.building_tabs.has(iid): return
	if MatchState.middleman_service.is_empty():
		MatchState.middleman_service={"schema":1,"match_id":str(Time.get_unix_time_from_system())+":"+str(Time.get_ticks_usec()),"buildings":{}}
	MatchState.middleman_service.buildings[iid]={"coefficient":coefficient(b),"recipe_id":str(b.recipe_id),"inputs":{},"outputs":{},"turn":-1,"state":"idle","receipts":{}}

## Allocate previews in the same stable order as resolution; no sale proceeds enter cash.
static func company_previews(completing: Array = []) -> Dictionary:
	var result := {}
	var ordered: Array = BuildingState.buildings.values().filter(func(b: Dictionary) -> bool: return enabled(str(b.instance_id)) and BuildingState.is_player_owned(b))
	ordered.append_array(completing)
	ordered.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		var ai := str(a.instance_id).get_slice("_",3).hex_to_int()
		var bi := str(b.instance_id).get_slice("_",3).hex_to_int()
		return str(a.instance_id)<str(b.instance_id) if ai==bi else ai<bi)
	var cash := MatchState.money
	var credit := maxf(0.0,LoanState.available_capacity())
	var power_reserved := 0.0
	var draw_by_tile := {}
	var snapshot := prices()
	for b: Dictionary in ordered:
		var iid := str(b.instance_id)
		var p := preview_building(b)
		for upcoming: Dictionary in completing:
			if str(upcoming.instance_id)!=iid:
				p.protected_commitments += Production._calculate_maintenance_cost(upcoming)+Production._calculate_labour_cost(upcoming,Catalog.get_recipe(str(upcoming.recipe_id)))
		result[iid] = p
		if not bool(p.ok) or bool(p.selling_held): continue
		var tile := str(b.tile_id)
		var draw: int = Production._effective_energy_req(b,Catalog.get_recipe(str(b.recipe_id)))
		var feasible := bool(p.feasible) and int(draw_by_tile.get(tile,0))+draw <= Power.tile_power_cap(tile)
		var plan := Contract.plan_batch(p.required,p.inputs,snapshot,coefficient(b),{"cash":cash,"credit_available":credit,"commitments":float(p.protected_commitments)+power_reserved,"running_reserve":float(p.labour)+float(p.maintenance)+float(p.power)+float(p.carbon_tax),"minimum_loan":EconomyConfig.LOAN_MINIMUM,"building_credit_tab":MatchState.building_tabs.has(iid)},feasible,goods())
		p.can_run = bool(plan.ok)
		p.reason = ready_message(iid) if bool(plan.ok) else str(plan.get("reason","Unavailable")).replace("_"," ").capitalize()
		p.funding_draw = float(plan.get("funding_draw",0.0))
		if bool(plan.ok):
			cash += float(plan.funding_draw)-float(plan.purchase.cash_out)
			credit -= float(plan.funding_draw)
			power_reserved += float(p.power)+float(p.carbon_tax)
			draw_by_tile[tile] = int(draw_by_tile.get(tile,0))+draw
	return result

## A managed remote input is a standing physical delivery into the destination
## tile's shared stock, never a private warehouse or instant transfer.
static func set_input_source(iid: String, gid: String, source: String) -> Dictionary:
	if TurnManager.current_phase != TurnManager.Phase.DECIDE or TurnManager.is_resolving or uses_inputs(iid):
		return {"ok":false,"reason":"Choose Manage logistics for inputs between turns first."}
	var b := BuildingState.get_building(iid)
	if not BuildingState.is_player_owned(b): return {"ok":false,"reason":"Not your building."}
	var recipe := Catalog.get_recipe(str(b.get("recipe_id","")))
	if not (recipe.get("inputs",[]) as Array).any(func(item: Dictionary) -> bool: return str(item.good_id)==gid):
		return {"ok":false,"reason":"Not an input of this building."}
	if source != "auto" and source != str(b.tile_id):
		if BuildingState.get_tile_land_owned(source)<=0 and not (BuildingState.get_buildings_on_tile(source) as Array).any(func(other: Dictionary) -> bool: return BuildingState.is_player_owned(other)):
			return {"ok":false,"reason":"Choose an owned tile stockpile."}
	for move: Dictionary in TransportState.recurring_moves.duplicate():
		if str(move.get("logistics_input_instance",""))==iid and str(move.get("logistics_input_good",""))==gid:
			TransportState.remove_recurring_move(move)
	MatchState.set_input_tile_only(iid,gid,source!="auto")
	if not b.has("logistics_input_sources"): b.logistics_input_sources={}
	b.logistics_input_sources[gid]=source
	if source!="auto" and source!=str(b.tile_id):
		TransportState.recurring_moves.append({"source":source,"dest":str(b.tile_id),"goods":{gid:1},"turn_started":MatchState._ledger_turn(),"logistics_input_instance":iid,"logistics_input_good":gid})
	MatchState.recurring_orders_changed.emit()
	return {"ok":true}

static func managed_move_goods(move: Dictionary) -> Dictionary:
	var iid := str(move.get("logistics_input_instance",""))
	if iid=="": return move.get("goods",{})
	var b := BuildingState.get_building(iid)
	if b.is_empty() or not BuildingState.is_player_owned(b) or uses_inputs(iid) or BuildingWorks.is_building_paused(iid) or BuildingWorks.is_retooling(iid): return {}
	var gid := str(move.get("logistics_input_good",""))
	for item: Dictionary in Catalog.get_recipe(str(b.recipe_id)).get("inputs",[]):
		if str(item.good_id)==gid: return {gid:Production._scaled_input_qty(item,b)}
	return {}

static func ready_message(iid: String) -> String:
	if not enabled(iid) or fully_managed(iid): return "Ready to buy, produce and sell this turn."
	if uses_inputs(iid): return "Ready to buy inputs. Output follows your managed destination."
	return "Ready to produce from shared stock and sell through the intermediary."

## Only material sides participate: grid power and buildings without recipes stay unchanged.
static func tile_sides(tile_id: String) -> Dictionary:
	var result := {"input":[], "output":[], "all_input":true, "all_output":true, "physical":false}
	for b: Dictionary in BuildingState.get_buildings_on_tile(tile_id):
		if not BuildingState.is_player_owned(b): continue
		var recipe := Catalog.get_recipe(str(b.get("recipe_id", "")))
		for side in ["input", "output"]:
			var active := uses_inputs(str(b.instance_id)) if side == "input" else uses_outputs(str(b.instance_id))
			if recipe_side(recipe, side):
				result[side].append(str(b.instance_id))
				result["all_"+side] = result["all_"+side] and active
			for good: Dictionary in recipe.get("inputs" if side == "input" else "outputs", []):
				if str(Catalog.get_good(str(good.good_id)).get("internal_name", "")) == "power": continue
				if not active or not material_tradeable(str(good.good_id), side): result.physical = true
	return result

static func set_tile_mode(tile_id: String, side: String, mode: String) -> Dictionary:
	if side not in ["input", "output"]: return {"ok":false, "reason":"Unknown logistics option."}
	return set_modes(tile_sides(tile_id)[side], side, mode)

static func global_side(side: String) -> Dictionary:
	var ids: Array = []
	var intermediary := 0
	for b: Dictionary in BuildingState.buildings.values():
		if not eligible(b) or not recipe_side(Catalog.get_recipe(str(b.get("recipe_id", ""))), side): continue
		var iid := str(b.instance_id)
		ids.append(iid)
		if uses_inputs(iid) if side == "input" else uses_outputs(iid): intermediary += 1
	return {"ids":ids, "intermediary":intermediary, "managed":ids.size()-intermediary}

static func changed_ids(ids: Array, side: String, mode: String) -> Array:
	return ids.filter(func(iid: String) -> bool:
		var active := uses_inputs(iid) if side == "input" else uses_outputs(iid)
		return active != (mode == "middleman"))

## Validate the whole selection, including combined releases per tile, before mutating.
static func set_modes(ids: Array, side: String, mode: String) -> Dictionary:
	if side not in ["input", "output"] or mode not in ["middleman", "managed"]:
		return {"ok":false, "reason":"Unknown logistics option."}
	var changes := changed_ids(ids, side, mode)
	var releases := {}
	for iid: String in changes:
		var check := set_mode(iid, side, mode, true)
		if not check.ok: return check
		if mode == "managed":
			var tile_id := str(BuildingState.get_building(iid).tile_id)
			for qty in entry(iid).get("inputs" if side == "input" else "outputs", {}).values():
				releases[tile_id] = int(releases.get(tile_id, 0)) + int(qty)
	for tile_id: String in releases:
		if int(releases[tile_id]) > Stockpile.get_free_capacity(tile_id):
			return {"ok":false, "reason":"Not enough tile storage for all buildings' paid goods. Free capacity first."}
	for iid: String in changes: set_mode(iid, side, mode)
	return {"ok":true, "changed":changes.size()}
