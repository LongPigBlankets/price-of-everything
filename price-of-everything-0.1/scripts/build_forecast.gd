extends RefCounted
## Projects what a building the player is about to construct will do to their cash, broken
## into the four phases they will actually live through.
##
## The first playtest (2026-08-08) had a player double their smelting capacity and go from
## +£27/turn to −£106/turn in a single turn, with nothing in the UI to warn them. That is the
## failure this exists to prevent — see docs/early-game-onboarding-spec.md §5.1.
##
## The phases, because the money behaves completely differently in each:
##   1 BUILDING      site under construction. Nothing produced, nothing owed.
##   2 COMPLETES     the build lands but cannot run for one turn ("just_constructed").
##                   It still pays labour and maintenance — production.gd charges those over
##                   ALL buildings, not just the running ones.
##   3 SHIPPING      producing and paying for everything, while the first output is still in
##                   transit to the port. The deepest hole, and the one players fall into.
##   4 SELLING       revenue lands and keeps landing. The steady margin.
##
## Everything charged here is charged by the engine too, through the same helpers, so the
## forecast and the real turn cannot silently diverge: recipe costs from production.gd,
## freight from TransportService quotes (live transport class, `transport_cost` modifiers and
## congestion included), port fees from MatchState, storage from EconomyConfig.
##
## Stated assumptions, held constant: output sells straight to market at today's price, inputs
## are bought from the market every producing turn, and prices do not move over the window.

const PHASE_BUILDING := "building"
const PHASE_COMPLETES := "completes"
const PHASE_SHIPPING := "shipping"
const PHASE_SELLING := "selling"


## Returns:
##   phases       Array of {kind, label, range, per_turn, turns} in order
##   cash_needed  total cash the phases before revenue will consume (the number that
##                decides whether the player can actually afford this building)
##   steady_net   per-turn net once revenue is flowing
##   breakdown    the steady turn's line items, for the tooltip/caption
##   capex        construction cost estimate
##   capex_total  the full up-front spend a confirm commits to: the money leg
##                (base_price) plus the material kit at market buy prices — the
##                same figure the confirm screen quotes as "construction". Land is
##                a separate decision and is NOT in here; add it via payback_turn().
##   build_turns  construction turns before the completion turn
##   first_selling_turn   the turn the first revenue lands, as the player counts turns
##   payback_turn the turn by whose end the build has earned back capex_total plus
##                the pre-revenue hole, at today's prices. -1 = never (steady_net <= 0).
##   sale_delay   turns between producing and the money landing
##   no_supply / input_names   inputs this tile has no route to
static func project(building_id: String, recipe_id: String, tile_id: String) -> Dictionary:
	var building_def: Dictionary = Catalog.get_building(building_id)
	var recipe: Dictionary = Catalog.get_recipe(recipe_id)
	var out := {
		"phases": [], "cash_needed": 0.0, "steady_net": 0.0, "breakdown": {},
		"capex": 0.0, "capex_total": 0.0, "build_turns": 0, "first_selling_turn": 0,
		"payback_turn": -1, "sale_delay": 1, "no_supply": false, "input_names": [],
	}
	if building_def.is_empty() or recipe.is_empty():
		return out

	# A stand-in for the finished building. The cost helpers only read these fields, so the
	# forecast prices the same building the engine will.
	var probe := {
		"instance_id": "", "building_id": building_id, "recipe_id": recipe_id,
		"tile_id": tile_id, "level": 1,
	}

	# --- Outputs: what it sells, what the freight and port cost to sell it ---------------
	var outputs := {}          # good_id -> qty
	var revenue: float = 0.0
	for item in Production._recipe_output_items(recipe):
		var gid := str(item.get("good_id", ""))
		if gid == "" and str(item.get("internal_name", "")) != "":
			gid = str(Catalog.get_good_by_internal_name(str(item.get("internal_name", ""))).get("id", ""))
		var qty := int(item.get("qty", 0))
		if gid != "" and qty > 0:
			outputs[gid] = qty
			revenue += float(qty) * MarketState.get_price(gid)

	var sale_delay: int = 1
	var outbound_freight: float = 0.0
	var port_fee: float = 0.0
	if tile_id != "" and not outputs.is_empty():
		var sell_quote: Dictionary = TransportService.quote_market_sell(tile_id, outputs)
		if not sell_quote.is_empty():
			outbound_freight = float(sell_quote.get("transport_cost", 0.0))
			sale_delay = maxi(1, int(sell_quote.get("turns", 1)))
			# Port charging is ad valorem on the value crossing the quay, so it scales with
			# what the building actually sells and steps up at SEAPORT_AD_VALOREM_STEP_TURN.
			# Owned ports charge half. (The flat per-good fee is retired — §4.2b.)
			port_fee = revenue * MatchState.seaport_insurance_rate(str(sell_quote.get("port", "")))

	# --- Inputs: delivered cost (goods + inbound freight), and whether they can arrive ---
	# An input the player already produces is NOT bought at retail. Charging the market buy
	# price for it prices a vertically integrated chain as though it shopped for its own ore,
	# which flipped metal_magnate's opening smelter from +£13/turn to −£5/turn — the exact
	# opposite of what the panel should tell someone about the game's flagship chain. Own
	# supply is charged at its opportunity cost (what selling it would have fetched) plus the
	# real freight of moving it to this tile.
	var input_cost: float = 0.0
	var inbound_freight: float = 0.0
	var unroutable: Array[String] = []
	for item in recipe.get("inputs", []):
		var gid := str(item.get("good_id", ""))
		var qty := int(item.get("qty", 0))
		if gid == "" or qty <= 0:
			continue
		var source_tile := _own_source_tile(tile_id, gid)
		if source_tile != "":
			# Own supply: charge what it actually COSTS the company to make it -- the CostSolver's
			# imputed unit cost, the very figure the realized per-turn P&L uses -- not the market price
			# it could fetch. Charging the sale price treats an internal transfer as a foregone external
			# sale, so a vertically integrated chain (chlor-alkali fed by its own desalination) forecast
			# a razor-thin/negative margin while its realized P&L was clearly positive (owner report,
			# 2026-09-05: salt+water quoted at ~£64/turn opportunity cost vs ~£31 real production cost).
			# Fall back to the market sell price when the good has no imputed cost yet (never cost-solved
			# or a cyclic recipe the solver leaves blank).
			var imputed := CostSolver.get_good_unit_cost(gid)
			input_cost += float(qty) * (imputed if imputed >= 0.0 else MarketState.get_price(gid))
			if source_tile != tile_id:
				var leg: Dictionary = TransportService.route(source_tile, tile_id, gid)
				inbound_freight += TransportService.transport_cost_for_route(gid, qty, leg)
			continue
		var buy_quote: Dictionary = {} if tile_id == "" \
				else TransportService.quote_market_buy(tile_id, gid, qty)
		if buy_quote.is_empty():
			# No own supply and no market route — the building would sit idle. Still price the
			# goods so the phase numbers stay meaningful next to the warning.
			input_cost += float(qty) * MarketState.get_buy_price(gid)
			unroutable.append(str(Catalog.get_good(gid).get("display_name", gid)))
		else:
			input_cost += float(buy_quote.get("goods_cost", 0.0))
			inbound_freight += float(buy_quote.get("transport_cost", 0.0))

	# --- Storage: only the goods that actually SIT at turn's end pay the fee ------------
	# The engine bills warehousing on the end-of-turn stockpile (production.gd: every unit in
	# Stockpile.get_tile_totals). A market-selling building's outputs are produced and sold the
	# SAME turn (production → flush → sell_phase), so they are gone by turn's end and pay nothing;
	# its inputs, bought a turn ahead, do sit and do pay. Charging storage on the outputs too
	# (as this did) invented a full turn of certified-tank fees on hazmat products that never
	# stay — ~£11/turn on chlor-alkali's chlorine/NaOH/hydrogen — which alone flipped a plant the
	# realized P&L runs clearly in profit to a "never pays back" forecast (owner report 2026-09-05).
	var warehousing: float = 0.0
	for item in recipe.get("inputs", []):
		var gid := str(item.get("good_id", ""))
		if gid != "":
			warehousing += float(item.get("qty", 0)) * EconomyConfig.warehousing_cost_per_unit(gid)

	var power_cost := float(Production._effective_energy_req(probe, recipe)) * EconomyConfig.GRID_BUY_PRICE
	var labour := Production._calculate_labour_cost(probe, recipe)
	var maintenance := Production._calculate_maintenance_cost(probe)

	# Standing costs are owed the moment the building exists, running or not.
	var standing: float = labour + maintenance
	# A producing turn adds everything it takes to make and hold the goods.
	var producing_cost: float = standing + input_cost + inbound_freight + power_cost + warehousing
	# A selling turn also pays to move them and to use the port.
	var selling_cost: float = producing_cost + outbound_freight + port_fee

	var build_turns: int = maxi(0, MatchState.effective_build_duration(building_id))
	# Turn numbers as the player counts them: turn 1 is the next turn they end.
	var completes_turn: int = build_turns + 1
	var first_producing: int = completes_turn + 1
	var first_selling: int = first_producing + sale_delay

	var phases: Array = []
	if build_turns > 0:
		phases.append({
			"kind": PHASE_BUILDING, "label": "Building",
			"range": _turn_range(1, build_turns), "per_turn": 0.0, "turns": build_turns,
		})
	phases.append({
		"kind": PHASE_COMPLETES, "label": "Completes",
		"range": _turn_range(completes_turn, completes_turn), "per_turn": -standing, "turns": 1,
	})
	phases.append({
		"kind": PHASE_SHIPPING, "label": "Making, not yet paid",
		"range": _turn_range(first_producing, first_selling - 1),
		"per_turn": -producing_cost, "turns": sale_delay,
	})
	phases.append({
		"kind": PHASE_SELLING, "label": "Selling",
		"range": "t%d onwards" % first_selling,
		"per_turn": revenue - selling_cost, "turns": -1,
	})

	var cash_needed: float = standing + producing_cost * float(sale_delay)

	out.phases = phases
	out.cash_needed = cash_needed
	out.steady_net = revenue - selling_cost
	out.capex = float(Construction.estimate_market_cost(tile_id, building_id))
	# capex_total is what a confirm actually commits to spending, matching the panel's
	# construction figure (base_price + full kit at buy prices) rather than capex's
	# missing-materials-only quote, so payback is measured against the real outlay.
	out.capex_total = maxf(0.0, float(building_def.get("base_price", 0.0))) \
		+ Construction.market_purchase_value(building_id)
	out.build_turns = build_turns
	out.first_selling_turn = first_selling
	out.payback_turn = payback_turn(float(out.capex_total), cash_needed, float(out.steady_net), first_selling)
	out.sale_delay = sale_delay
	out.no_supply = not unroutable.is_empty()
	out.input_names = unroutable
	out.breakdown = {
		"revenue": revenue, "inputs": input_cost, "inbound_freight": inbound_freight,
		"outbound_freight": outbound_freight, "port_fee": port_fee, "power": power_cost,
		"labour": labour, "maintenance": maintenance, "warehousing": warehousing,
	}
	return out


## The turn by whose end cumulative net returns to zero: the whole up-front spend
## (total_capex — pass capex_total plus any land the player is buying with the
## build) and the pre-revenue hole (cash_needed) are earned back at steady_net per
## selling turn, the first of which is first_selling_turn. -1 = never pays back at
## today's prices. Shared by the forecast, the confirm panel and the harness so
## "pays back ~turn N" is one computation everywhere.
static func payback_turn(total_capex: float, cash_needed: float, steady_net: float, first_selling_turn: int) -> int:
	if steady_net <= 0.0:
		return -1
	var hole: float = maxf(0.0, total_capex) + maxf(0.0, cash_needed)
	if hole <= 0.0:
		return first_selling_turn
	return first_selling_turn + int(ceil(hole / steady_net)) - 1


## The confirm screen's affordability chip, as data (spec: verdict strip, RAG vs
## current cash). "ok" = the build AND the pre-revenue buffer are covered;
## "buffer_short" = the build is affordable but the buffer is not, so the building
## will strain the bank before its first sale; "unaffordable" = cannot pay for the
## build at all. total_cost is everything the confirm spends (construction + land).
static func affordability_verdict(total_cost: float, cash_needed: float, money: float) -> String:
	if money + 0.0001 < total_cost:
		return "unaffordable"
	if money + 0.0001 < total_cost + maxf(0.0, cash_needed):
		return "buffer_short"
	return "ok"


static func _turn_range(from_turn: int, to_turn: int) -> String:
	if to_turn <= from_turn:
		return "t%d" % from_turn
	return "t%d–t%d" % [from_turn, to_turn]


## The player's own tile that could feed this good, or "" if they have none. This tile wins
## when it already holds stock, because a co-located feed pays no freight at all.
static func _own_source_tile(tile_id: String, good_id: String) -> String:
	if tile_id == "":
		return ""
	if Stockpile.get_at_tile(tile_id, good_id) > 0:
		return tile_id
	# PRODUCTION, not stock. `Construction.find_source_tile` answers "is there a pile of this
	# somewhere" — the right question for a build kit, the wrong one here. A player who smelts
	# iron every turn and sells or feeds it the same turn holds NONE at the instant the panel
	# opens, so the stock-only test reported no own supply and this forecast priced their own
	# ingots at retail: it quoted a vertically integrated build as though the company shopped
	# for the metal it makes (owner report, 2026-09-03; metal_magnate makes 70 iron ingots a
	# turn on the very tile the forecast called a market buy).
	var best := ""
	var best_turns := 1 << 30
	for iid in MatchState.buildings:
		var b: Dictionary = MatchState.buildings[iid]
		if not MatchState.is_player_owned(b) or not _recipe_makes(str(b.get("recipe_id", "")), good_id):
			continue
		var src := str(b.get("tile_id", ""))
		if src == tile_id:
			return tile_id   # made right here: no freight, and no better source exists
		var turns := int(TransportService.route(src, tile_id).get("turns", 1 << 30))
		if turns < best_turns:
			best_turns = turns
			best = src
	if best != "":
		return best
	# Nothing of the player's makes it, but a pile of it may still be lying about.
	var source: Dictionary = Construction.find_source_tile(tile_id, {good_id: 1})
	return str(source.get("tile_id", "")) if not source.is_empty() else ""


## Does this recipe put `good_id` out? Byproducts count — a good the player makes as a
## side-effect is still theirs and still not bought at retail.
static func _recipe_makes(recipe_id: String, good_id: String) -> bool:
	if recipe_id == "" or good_id == "":
		return false
	for item in Production._recipe_output_items(Catalog.get_recipe(recipe_id)):
		var gid := str(item.get("good_id", ""))
		if gid == "" and str(item.get("internal_name", "")) != "":
			gid = str(Catalog.get_good_by_internal_name(str(item.get("internal_name", ""))).get("id", ""))
		if gid == good_id:
			return true
	return false
