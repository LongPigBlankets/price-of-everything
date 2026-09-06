extends RefCounted
## Shared building status / cost helpers, extracted from the old v1 detail panel so the
## detail panel and the Building Ledger compute RAG colours, power supply, primary output,
## lifetime production, etc. from ONE source of truth (no drift).
##
## All functions are STATIC and pure w.r.t. UI state — they read only autoload singletons
## (Catalog, Production, Power, Stockpile, MatchState). Consumers `preload` this as
## `const BuildingStatus := preload("res://scripts/building_status.gd")` (no class_name, so
## it resolves in headless test runs too — see the GDScript gotcha in the test setup notes).

const BuildingLevels := preload("res://scripts/building_levels.gd")

# RAG palette — identical values to the old v1 panel's STATUS_* consts (the contract
# the detail panel's status dots already render against). power_supply()'s return strings are
# likewise a contract: power_status_color() compares against the literal "Owned Supply".
const STATUS_GREEN := Color("#5BD180")   # DS PALETTE OK
const STATUS_RED := Color("#E66060")     # DS PALETTE DANGER
const STATUS_GREY := Color(0.45, 0.48, 0.52)
const STATUS_YELLOW := Color("#E6B85C")  # DS PALETTE WARN
const MOD_NEUTRAL := Color(0.93, 0.94, 0.96)  # net-modifier ~0% band (matches detail panel MOD_WHITE)

# --- Recipe / output introspection ---------------------------------------------------------

static func flow_output_items(recipe: Dictionary) -> Array:
	if recipe.has("outputs"):
		return recipe.get("outputs", [])
	var output_name: String = recipe.get("output_name", "")
	var output_qty: int = int(recipe.get("output_qty", 0))
	if output_name == "" or output_qty <= 0:
		return []
	return [{
		"good_id": recipe.get("output_good_id", ""),
		"internal_name": output_name,
		"qty": output_qty,
	}]

static func primary_output_good_id(recipe: Dictionary) -> String:
	for output in flow_output_items(recipe):
		var gid: String = str(output.get("good_id", ""))
		if gid != "":
			return gid
		var internal_name: String = str(output.get("internal_name", ""))
		if internal_name != "":
			return str(Catalog.get_good_by_internal_name(internal_name).get("id", ""))
	return ""

# Primary output's internal_name — the key deposit/mining-yield modifiers match on.
static func primary_output_internal(recipe: Dictionary) -> String:
	for output in flow_output_items(recipe):
		var internal_name: String = str(output.get("internal_name", ""))
		if internal_name != "":
			return internal_name
		var gid: String = str(output.get("good_id", ""))
		if gid != "":
			return str(Catalog.get_good(gid).get("internal_name", ""))
	return ""

static func primary_output_qty(recipe: Dictionary) -> int:
	for output in flow_output_items(recipe):
		return int(output.get("qty", 0))
	return 0

# Post-modifier output qty of the building's PRIMARY good this turn — mirrors
# production.gd._produce_outputs: recipe_output modifiers, level OUTPUT_MULT, then
# the workforce output multiplier.
# Returns the per-turn output capacity (0 for power/infra or unknown goods).
static func effective_output_qty(building: Dictionary, recipe: Dictionary) -> int:
	for output in flow_output_items(recipe):
		var internal_name: String = str(output.get("internal_name", ""))
		var base_qty: int = int(output.get("qty", 0))
		if internal_name == "" or base_qty <= 0:
			continue
		var good: Dictionary = Catalog.get_good_by_internal_name(internal_name)
		if good.is_empty():
			continue
		var recipe_id: String = str(recipe.get("recipe_id", ""))
		var ctx := {
			"recipe_id": recipe_id,
			"recipe_type": str(recipe.get("recipe_type", "")).to_lower(),
			"building_id": str(building.get("building_id", "")),
			"instance_id": str(building.get("instance_id", "")),   # lets on_infinite_deposit modifiers resolve in the panel too
			"good_id": str(good.id),
			"good_internal": internal_name,
		}
		var q: int = int(round(Modifiers.apply("recipe_output", recipe_id, float(base_qty), ctx)))
		q = int(round(float(q) * BuildingLevels.mult("output", int(building.get("level", 1)))))
		q = int(round(float(q) * MatchState.workforce_output_multiplier()))
		return maxi(0, q)
	return 0

# Power CONSUMPTION this turn (post building_power modifiers × level ENERGY_MULT) — mirrors
# production.gd._effective_energy_req. 0 when the recipe needs no power.
static func effective_energy_req(building: Dictionary, recipe: Dictionary) -> int:
	var energy_req: int = int(recipe.get("energy_req", 0))
	if energy_req <= 0:
		return energy_req
	var bid: String = str(building.get("building_id", ""))
	var eff := Modifiers.apply("building_power", bid, float(energy_req), {"building_id": bid})
	return int(round(eff * BuildingLevels.mult("energy", int(building.get("level", 1)))))

# Power GENERATION this turn (post recipe_output modifiers × level OUTPUT_MULT × workforce
# output multiplier) — mirrors production.gd._effective_power_output. 0 when the recipe
# produces no power.
static func effective_power_output(building: Dictionary, recipe: Dictionary) -> int:
	var output_qty: int = int(recipe.get("output_qty", 0))
	if output_qty <= 0 or str(recipe.get("output_name", "")) != "power":
		return 0
	var rid: String = str(recipe.get("recipe_id", ""))
	var ctx := {
		"recipe_id": rid,
		"recipe_type": str(recipe.get("recipe_type", "")).to_lower(),
		"building_id": str(building.get("building_id", "")),
		"good_id": "power",
		"good_internal": "power",
	}
	var eff := Modifiers.apply("recipe_output", rid, float(output_qty), ctx)
	eff *= Production.colocated_battery_power_multiplier(building)   # renew_014 same-tile battery bonus
	return int(round(eff * BuildingLevels.mult("output", int(building.get("level", 1))) * MatchState.workforce_output_multiplier()))

static func good_display_from_internal(internal_name: String) -> String:
	return str(Catalog.get_good_by_internal_name(internal_name).get("display_name", internal_name))

static func primary_output_display_name(recipe: Dictionary) -> String:
	var output_name: String = str(recipe.get("output_name", ""))
	if output_name == "":
		return ""
	return good_display_from_internal(output_name)

# --- Deposit / extraction ------------------------------------------------------------------

static func recipe_deposit_exhausted(building: Dictionary, recipe: Dictionary) -> bool:
	var tile_id := str(building.get("tile_id", ""))
	if tile_id == "":
		return false
	for req in recipe.get("requirements", []):
		if str(req.get("type", "")) != "deposit":
			continue
		var token := str(req.get("value", ""))
		if token == "" or token == "water":
			continue
		if MatchState.deposit_remaining_for(tile_id, token) == 0:
			return true
	return false

# --- Power ---------------------------------------------------------------------------------

static func tile_power_state(tile_id: String) -> Dictionary:
	var connected := Power.is_supplied(tile_id, 1)
	var supply := 0
	var demand := 0
	var has_power_plant := false
	for building in MatchState.get_buildings_on_tile(tile_id):
		var recipe: Dictionary = Catalog.get_recipe(str(building.get("recipe_id", "")))
		if str(recipe.get("output_name", "")) == "power":
			has_power_plant = true
			supply += int(recipe.get("output_qty", 0))
		demand += int(recipe.get("energy_req", 0))
	return {
		"connected": connected,
		"supply": supply,
		"demand": demand,
		"has_power_plant": has_power_plant,
	}

# Returns one of the contract strings: "Owned Supply" / "Grid" / "Not connected".
static func power_supply(building: Dictionary) -> String:
	var tile := str(building.get("tile_id", ""))
	if not Power.is_supplied(tile, 1):
		return "Not connected"
	# Own vs grid is a per-CABLE-NETWORK question: a draw is "own supply" when this tile's own
	# generation (same-tile first) plus the rest of its physically cable-connected network covered
	# it this turn; it is "Grid" when any of it was imported from the national grid. (Settled in
	# Power.settle_grid_transactions; mirrors the power map mode's self-supply test.)
	return "Owned Supply" if Power.is_self_supplied(tile) else "Grid"

static func power_status_color(building: Dictionary, recipe: Dictionary, is_infrastructure: bool) -> Color:
	if is_infrastructure:
		return STATUS_GREY
	var energy_req: int = int(recipe.get("energy_req", 0))
	var produces_power: bool = str(recipe.get("output_name", "")) == "power"
	if energy_req <= 0 and not produces_power:
		return STATUS_GREY
	if not Power.is_supplied(str(building.get("tile_id", "")), energy_req):
		return STATUS_RED
	return STATUS_GREEN if power_supply(building) == "Owned Supply" else STATUS_YELLOW

# --- Inputs / run status -------------------------------------------------------------------

static func input_status_color(building: Dictionary, recipe: Dictionary, is_infrastructure: bool) -> Color:
	if is_infrastructure:
		return STATUS_GREY
	# An extraction building whose deposit is mined out can no longer produce.
	if recipe_deposit_exhausted(building, recipe):
		return STATUS_RED
	var instance_id: String = str(building.get("instance_id", ""))
	if instance_id != "" and Production.last_turn_run.has(instance_id):
		return STATUS_GREEN
	if instance_id != "" and Production.missing_by_building.has(instance_id):
		return STATUS_RED
	var inputs: Array = recipe.get("inputs", [])
	if inputs.is_empty():
		return STATUS_GREEN
	var tile_id: String = str(building.get("tile_id", ""))
	for input in inputs:
		if Stockpile.get_at_tile(tile_id, str(input.get("good_id", ""))) < int(input.get("qty", 0)):
			return STATUS_RED
	return STATUS_YELLOW

# --- Cost RAG (the pure pct->colour band split out of _update_cost_label) -------------------
# unit_cost < 0 (unsolved / mined-out) -> grey. Bands: <90% green, 90-110% amber, >110% red.
static func cost_rag_color(unit_cost: float, base_price: float) -> Color:
	if unit_cost < 0.0:
		return STATUS_GREY
	var pct: float = (unit_cost / base_price * 100.0) if base_price > 0.0 else 0.0
	if pct < 90.0:
		return STATUS_GREEN
	elif pct <= 110.0:
		return STATUS_YELLOW
	return STATUS_RED

# --- Lifetime production / streak ----------------------------------------------------------

static func produced_good_display_name(good_key: String, recipe: Dictionary) -> String:
	if good_key == "power":
		return "Power"
	var good: Dictionary = Catalog.get_good(good_key)
	if not good.is_empty():
		return str(good.get("display_name", good_key))
	for output in flow_output_items(recipe):
		if str(output.get("internal_name", "")) == good_key:
			return good_display_from_internal(good_key)
	return good_key

static func produced_since_construction(building: Dictionary, recipe: Dictionary) -> String:
	var instance_id: String = str(building.get("instance_id", ""))
	var totals: Dictionary = Production.produced_by_building.get(instance_id, {}) as Dictionary
	if totals.is_empty():
		return "0"
	var parts: Array = []
	for good_key in totals.keys():
		parts.append("%d %s" % [int(totals[good_key]), produced_good_display_name(str(good_key), recipe)])
	return ", ".join(parts)

static func full_output_streak(building: Dictionary) -> int:
	return int(Production.full_output_streak_by_building.get(str(building.get("instance_id", "")), 0))

# --- Costs ---------------------------------------------------------------------------------

static func maintenance_cost(building_data: Dictionary) -> float:
	# catalog.gd stores null when the CSV maintenance cell is blank — guard it.
	var value = building_data.get("maintenance_cost", 0.0)
	if value == null:
		return 0.0
	return float(value)

# --- Output transport (the building's selected output route) --------------------------------

static func route_summary(source_tile: String, destination_tile: String, good_id: String, qty: int) -> Dictionary:
	var r := TransportService.route(source_tile, destination_tile, good_id)
	var reachable := TransportService.route_is_reachable(r)
	# When unreachable (e.g. a fluid with no pipe route) TransportService returns the
	# INF_TURNS sentinel; report reachable=false and a 0 cost so callers never render
	# the raw 2^30 turns / astronomical cost.
	return {
		"distance": int(r.get("tile_distance", 0)),
		"turns": int(r.get("turns", 0)),
		"cost": TransportService.transport_cost_for_route(good_id, qty, r) if reachable else 0.0,
		"reachable": reachable,
	}

static func selected_output_route(building: Dictionary, recipe: Dictionary) -> Dictionary:
	var instance_id: String = str(building.get("instance_id", ""))
	var good_id := primary_output_good_id(recipe)
	var destination_tile := MatchState.get_output_stockpile_destination(instance_id, good_id)
	if destination_tile == "":
		return {}
	return route_summary(str(building.get("tile_id", "")), destination_tile, good_id, primary_output_qty(recipe))

static func transport_duration_status_color(building: Dictionary, recipe: Dictionary, is_infrastructure: bool) -> Color:
	if is_infrastructure:
		return STATUS_GREY
	if not Production.last_turn_run.has(str(building.get("instance_id", ""))) or recipe_deposit_exhausted(building, recipe):
		return STATUS_GREY
	var route := selected_output_route(building, recipe)
	if route.is_empty():
		return STATUS_GREEN
	return STATUS_YELLOW if int(route.turns) > 1 else STATUS_GREEN

static func transport_cost_status_color(building: Dictionary, recipe: Dictionary, is_infrastructure: bool) -> Color:
	if is_infrastructure:
		return STATUS_GREY
	if not Production.last_turn_run.has(str(building.get("instance_id", ""))) or recipe_deposit_exhausted(building, recipe):
		return STATUS_GREY
	var route := selected_output_route(building, recipe)
	if route.is_empty():
		return STATUS_GREEN
	return STATUS_YELLOW if float(route.cost) > 0.0 else STATUS_GREEN

# --- Cost-to-produce RAG (CostSolver unit cost vs the LIVE market price) --------------------

## The output's live market price (decay + glut/deficit impact), falling back to the
## static base price before the market has a quote. This is what "vs market" means in
## the Building Detail economics — the comparison moves as the price moves.
static func live_output_price(good_id: String) -> float:
	if good_id == "":
		return 0.0
	var p: float = MarketState.get_price(good_id)
	return p if p > 0.0 else Catalog.get_base_price(good_id)

static func produce_cost_status(building: Dictionary) -> Dictionary:
	var iid := str(building.get("instance_id", ""))
	var recipe := Catalog.get_recipe(str(building.get("recipe_id", "")))
	var uc: float = CostSolver.get_building_unit_cost(iid)
	if recipe_deposit_exhausted(building, recipe):
		uc = -1.0
	if uc < 0.0:
		return {"color": STATUS_GREY, "unit_cost": -1.0, "base_price": 0.0}
	var bd: Dictionary = (CostSolver.last_result.get("per_building", {}) as Dictionary).get(iid, {})
	var output_good_id: String = str(bd.get("output_good_id", ""))
	var price := live_output_price(output_good_id)
	return {"color": cost_rag_color(uc, price), "unit_cost": uc, "base_price": price}

# --- Net output modifier (additive recipe_output modifiers + workforce + intermittency) ----
# Returns the signed net percent and its colour band (white -1..1%, green >1%, red <-1%), plus the
# component parts so a UI can build a breakdown tooltip without recomputing.
static func workforce_output_modifier_parts(turn_number: int = -1) -> Array:
	var turn := int(TurnManager.current_turn) if turn_number < 0 else turn_number
	var parts: Array = []
	if MatchState.is_workforce_policy_enabled(MatchState.WORKFORCE_POLICY_GENEROUS_PENSIONS):
		var pensions: Dictionary = MatchState.workforce_policy_effects.get(MatchState.WORKFORCE_POLICY_GENEROUS_PENSIONS, {})
		var pension_pct := float(pensions.get("output_pct", 0.0)) * 100.0
		if absf(pension_pct) > 0.001:
			parts.append({"pct": pension_pct, "label": "Generous Pensions"})
	if MatchState.is_workforce_policy_enabled(MatchState.WORKFORCE_POLICY_EXTENDED_ANNUAL_LEAVE) and turn % 10 == 0:
		parts.append({"pct": -5.0, "label": "Extended Annual Leave"})
	if MatchState.is_workforce_policy_enabled(MatchState.WORKFORCE_POLICY_GENEROUS_PARENTAL_LEAVE):
		var ten_turn_block := int(floor(float(maxi(turn, 1) - 1) / 10.0))
		if ten_turn_block % 2 == 0:
			parts.append({"pct": -5.0, "label": "Generous Parental Leave"})
	if MatchState.is_workforce_policy_enabled(MatchState.WORKFORCE_POLICY_STRICT_SAFETY):
		parts.append({"pct": -10.0, "label": "Strict Safety Procedures"})
	if MatchState.is_workforce_policy_enabled(MatchState.WORKFORCE_POLICY_LAX_SAFETY):
		parts.append({"pct": 5.0, "label": "Lax Safety Procedures"})
	if MatchState.is_workforce_policy_enabled(MatchState.WORKFORCE_POLICY_ANNUAL_BONUS) and turn % 10 == 0:
		parts.append({"pct": 20.0, "label": "Annual Bonus"})
	if MatchState.is_workforce_policy_enabled(MatchState.WORKFORCE_POLICY_ANNUAL_PROFIT_SHARE):
		parts.append({"pct": 10.0, "label": "Annual Profit Share"})
	return parts

static func net_output_modifier(building: Dictionary, recipe: Dictionary) -> Dictionary:
	var recipe_id: String = str(recipe.get("recipe_id", ""))
	var ctx := {
		"recipe_id": recipe_id,
		"recipe_type": str(recipe.get("recipe_type", "")).to_lower(),
		"building_id": str(building.get("building_id", "")),
		"instance_id": str(building.get("instance_id", "")),   # lets on_infinite_deposit modifiers resolve in the panel too
		"good_id": primary_output_good_id(recipe),
		"good_internal": primary_output_internal(recipe),
	}
	var res: Dictionary = Modifiers.resolve_pct("recipe_output", recipe_id, ctx)
	var net: float = float(res.get("net", 0.0))
	var workforce_mult: float = MatchState.workforce_output_multiplier()
	var workforce_parts := workforce_output_modifier_parts()
	var derate: float = float((Production.get_building_intermittency(str(building.get("instance_id", ""))) as Dictionary).get("derate", 0.0))
	var eff: float = ((1.0 + net / 100.0) * workforce_mult * (1.0 - derate) - 1.0) * 100.0
	var color: Color
	if eff > 1.0:
		color = STATUS_GREEN
	elif eff < -1.0:
		color = STATUS_RED
	else:
		color = MOD_NEUTRAL
	var eff_i: int = int(round(eff))
	return {
		"pct": eff_i,
		"pct_f": eff,
		"color": color,
		"parts": res.get("parts", []),
		"workforce_parts": workforce_parts,
		"workforce_multiplier": workforce_mult,
		"derate": derate,
		"text": "%s%d%%" % ["+" if eff_i > 0 else "", eff_i],
	}

# --- The six RAG indicators as DATA (single source for every UI that shows them) -------------
# Each entry: { key, label, color, text, tooltip }. The 4 status ones have text==""; the 5th shows
# the cost-to-produce as a £ number (up to 2dp) and the 6th the net modifier as a Δ…% number. The
# tooltips are the SAME text the detail panel hover shows, so both UIs share one source. Order matches
# the detail panel.
const _COST_RAG_LEGEND := "Green if cheaper than buying from the market, amber if even with market and red if more expensive than purchasing from the market"
const _MOD_RAG_LEGEND := "White means no net effect (−1% to +1%), green a net production boost above +1%, red a net penalty below −1%."
const _TIP_POWER := "Power status\nGreen: powered by your own supply · Amber: powered via the grid · Red: not powered · Grey: no power needed"
const _TIP_INPUT := "Input status\nGreen: ran with inputs available · Amber: inputs present but idle · Red: missing inputs · Grey: not applicable"
const _TIP_DURATION := "Output transport duration\nGreen: arrives same turn · Amber: multi-turn shipment · Grey: building didn't run this turn"
const _TIP_TRANSPORT := "Cost of transport\nGreen: no shipping cost · Amber: paying to ship output · Grey: building didn't run this turn"

static func rag_indicators(building: Dictionary, recipe: Dictionary, is_infrastructure: bool) -> Array:
	var pc := produce_cost_status(building)
	var uc: float = float(pc.unit_cost)
	# The cost per unit means little on its own — £4 is cheap for steel and ruinous for
	# coal. It now carries what it is a share OF: the good's live market price (owner
	# 2026-08-24). The colour band already read the same ratio; the number says it too.
	var price: float = float(pc.get("base_price", 0.0))
	var share := -1.0
	if uc >= 0.0 and price > 0.0:
		share = uc / price * 100.0
	var pc_text := "£–"
	if uc >= 0.0:
		pc_text = "£" + _fmt_upto2(uc) + ("" if share < 0.0 else " (%d%%)" % int(round(share)))
	var pc_tip := "Production cost per unit: --"
	if uc >= 0.0:
		pc_tip = "Production cost per unit: £" + _fmt_upto2(uc)
		if share >= 0.0:
			pc_tip += "\nThat is %d%% of the market price (£%s)." % [int(round(share)), _fmt_upto2(price)]
	pc_tip += "\n" + _COST_RAG_LEGEND
	var mod := net_output_modifier(building, recipe)
	var mpf: float = float(mod.get("pct_f", 0.0))
	var mod_text := "Δ" + ("+" if mpf > 0.0 else "") + _fmt_upto2(mpf) + "%"
	return [
		{"key": "power", "label": "Power", "color": power_status_color(building, recipe, is_infrastructure), "text": "", "tooltip": _TIP_POWER},
		{"key": "input", "label": "Inputs", "color": input_status_color(building, recipe, is_infrastructure), "text": "", "tooltip": _TIP_INPUT},
		{"key": "duration", "label": "Transport duration", "color": transport_duration_status_color(building, recipe, is_infrastructure), "text": "", "tooltip": _TIP_DURATION},
		{"key": "cost", "label": "Transport cost", "color": transport_cost_status_color(building, recipe, is_infrastructure), "text": "", "tooltip": _TIP_TRANSPORT},
		{"key": "produce_cost", "label": "Cost to produce", "color": pc.color, "text": pc_text, "tooltip": pc_tip},
		{"key": "modifier", "label": "Net output modifier", "color": mod.color, "text": mod_text, "tooltip": _modifier_tooltip(mod)},
	]


## Format a float to at most 2 decimal places, trimming trailing zeros (12.50 -> "12.5", 12.0 -> "12").
static func _fmt_upto2(v: float) -> String:
	var s := "%.2f" % v
	while s.ends_with("0"):
		s = s.substr(0, s.length() - 1)
	if s.ends_with("."):
		s = s.substr(0, s.length() - 1)
	return s


## The net-modifier hover tooltip — same breakdown the detail panel builds (parts + derate + legend).
static func _modifier_tooltip(mod: Dictionary) -> String:
	var parts: Array = mod.get("parts", [])
	var workforce_parts: Array = mod.get("workforce_parts", [])
	var derate: float = float(mod.get("derate", 0.0))
	if parts.is_empty() and workforce_parts.is_empty() and derate <= 0.0:
		return "Production modifier: none active.\n" + _MOD_RAG_LEGEND
	var lines: PackedStringArray = ["Production modifiers:"]
	if not parts.is_empty():
		lines.append("Recipe modifiers (added together):")
		for p in parts:
			var pv: float = float(p.get("pct", 0.0))
			lines.append("  %s%d%%  %s" % ["+" if pv > 0.0 else "", int(round(pv)), str(p.get("label", ""))])
	if not workforce_parts.is_empty():
		lines.append("Workforce policies (multiplicative):")
		for p in workforce_parts:
			var pv: float = float(p.get("pct", 0.0))
			lines.append("  %s%d%%  %s" % ["+" if pv > 0.0 else "", int(round(pv)), str(p.get("label", ""))])
	if derate > 0.0:
		lines.append("  -%d%%  Intermittency impact (multiplicative, applied after)" % int(round(derate * 100.0)))
	lines.append("Net: " + str(mod.get("text", "")))
	lines.append(_MOD_RAG_LEGEND)
	return "\n".join(lines)
