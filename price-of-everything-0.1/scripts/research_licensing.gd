extends RefCounted
## Research licensing (docs/pacing-labour-mining-licensing-spec.md §10).
##
## A licence group is three competing processes for one problem (research_unlocks.csv `licence_group`). A member
## whose condition is met is ready to license (ResearchState routes it there instead of granting it). The first
## licence in a group costs the era price once; the second and third a share of company revenue each turn for
## LICENCE_ROYALTY_TURNS, then they are paid up. A free pick develops a member in-house at no cost. Rank II and III
## processes developed in-house can be licensed out within the patent window: paid once, and each sale lowers the
## sale price of the goods the process touches.
##
## The state lives in ResearchState (licences, licensed_out, licence_ready_titles, unlock_turns, licence_sales_due,
## free_picks); this seam prices and acts on it. Royalties and licence sales settle in Production's costs phase
## (settle_turn), before tax.

const GROUP_ORDER := ["coal_power", "iron_steel", "refining", "extraction", "solar", "wind", "factory", "eaf"]
const GROUP_NAMES := {
	"coal_power": "Coal power", "iron_steel": "Iron and steel", "refining": "Refining", "extraction": "Extraction",
	"solar": "Solar", "wind": "Wind", "factory": "Factory", "eaf": "Electric arc furnace",
}
## Modifier domains of a production process: a node with an effect in one of these touches goods.
const PROCESS_DOMAINS := ["recipe_output", "throughput", "recipe_input", "building_power", "labour_headcount",
	"maintenance", "extraction_cap_cost"]
const MINE_BUILDING := "b_001"
const OUT_SOURCE := "licence_out"
## Sold to the grid, not the market: no sale price for a licence sold to lower.
const NOT_MARKET_GOODS := ["power"]

## title -> {process: bool, goods: Array}, see _scope.
static var _scope_cache: Dictionary = {}


# --- Groups --------------------------------------------------------------------------------------------------

static func group_name(group: String) -> String:
	return str(GROUP_NAMES.get(group, group.capitalize()))


## The visible members of `group`, by rank and then in table order.
static func members(group: String) -> Array:
	var out: Array = []
	if group == "":
		return out
	for rank: String in ["I", "II", "III"]:
		for d: Dictionary in ResearchState.unlock_defs():
			if str(d.get("licence_group", "")) == group and str(d.get("rank", "I")) == rank and ResearchState.is_research_visible(d):
				out.append(str(d.get("title", "")))
	return out


## The groups with a visible member, in GROUP_ORDER.
static func groups() -> Array:
	return GROUP_ORDER.filter(func(g: String) -> bool: return not members(g).is_empty())


## How many of `group`'s processes the company holds, licensed or in-house.
static func held_count(group: String) -> int:
	var n := 0
	for t: String in members(group):
		if ResearchState.is_unlocked(t):
			n += 1
	return n


static func licence_of(title: String) -> Dictionary:
	return ResearchState.licences.get(title, {})


## The company's own: unlocked, and not licensed in (every unlocked node outside a group is in-house).
static func is_in_house(title: String) -> bool:
	if not ResearchState.is_unlocked(title):
		return false
	return ResearchState.licence_group_of(title) == "" or str(licence_of(title).get("kind", "inhouse")) == "inhouse"


static func is_licensed_in(title: String) -> bool:
	return ResearchState.is_unlocked(title) and str(licence_of(title).get("kind", "")) in ["flat", "royalty"]


# --- Licensing in --------------------------------------------------------------------------------------------

## The first licence's price in the era of `turn`.
static func first_price(turn: int) -> float:
	var prices: Array = EconomyConfig.LICENCE_FIRST_PRICE
	return float(prices[clampi(MatchState.era_for_turn(turn) - 1, 0, prices.size() - 1)])


## What licensing `title` would cost now: {kind: "flat", price} or {kind: "royalty", rate, turns}. Set by the
## processes already held in its group, whichever they are.
static func terms_for(title: String) -> Dictionary:
	var held := held_count(ResearchState.licence_group_of(title))
	if held <= 0:
		return {"kind": "flat", "price": first_price(TurnManager.current_turn)}
	var rates: Array = EconomyConfig.LICENCE_ROYALTY_RATES
	return {"kind": "royalty", "rate": float(rates[mini(held - 1, rates.size() - 1)]),
		"turns": EconomyConfig.LICENCE_ROYALTY_TURNS}


## Why `title` cannot be licensed now, or "" when it can.
static func license_refusal(title: String) -> String:
	if ResearchState.licence_group_of(title) == "":
		return "Not in a licence group"
	if ResearchState.is_unlocked(title):
		return "Already held"
	if not ResearchState.is_licence_ready(title):
		return "Its condition is not met yet"
	var terms := terms_for(title)
	if str(terms.kind) == "flat" and MatchState.money < float(terms.price):
		return "Needs %s in hand" % _money(float(terms.price))
	return ""


## Licenses a ready member: records the licence, books a flat price as a one-off charge in this turn's costs and
## grants the node, whose effects apply from this turn. False when license_refusal says no.
static func license(title: String) -> bool:
	if license_refusal(title) != "":
		return false
	var terms := terms_for(title)
	var turn := int(TurnManager.current_turn)
	var entry := {"kind": str(terms.kind), "start_turn": turn}
	if str(terms.kind) == "flat":
		entry["price"] = float(terms.price)
		MatchState.one_off_charges.append({"turn": turn, "amount": float(terms.price), "label": "Licence: %s" % title})
	else:
		entry["rate"] = float(terms.rate)
	ResearchState.licences[title] = entry
	ResearchState.grant_unlock(title, false)
	ResearchState.licences_changed.emit()
	return true


## True while a royalty licence is in its term at `turn`.
static func royalty_active(licence: Dictionary, turn: int) -> bool:
	if str(licence.get("kind", "")) != "royalty":
		return false
	var start := int(licence.get("start_turn", 0))
	return turn >= start and turn < start + EconomyConfig.LICENCE_ROYALTY_TURNS


## Royalty charges left for `title`, counting this turn's (0 when paid up or not a royalty licence).
static func royalty_turns_left(title: String) -> int:
	var l := licence_of(title)
	if str(l.get("kind", "")) != "royalty":
		return 0
	return maxi(0, int(l.get("start_turn", 0)) + EconomyConfig.LICENCE_ROYALTY_TURNS - int(TurnManager.current_turn))


## The share of revenue every royalty licence in its term charges at `turn`.
static func royalty_rate_total(turn: int) -> float:
	var total := 0.0
	for t: String in ResearchState.licences:
		var l: Dictionary = ResearchState.licences[t]
		if royalty_active(l, turn):
			total += float(l.get("rate", 0.0))
	return total


# --- The turn's settlement -----------------------------------------------------------------------------------

## Production's costs phase: every royalty licence in its term charges its rate on this turn's goods and power
## sales, used or not, and the licences sold this turn are paid. Both before tax, with their lines on the summary.
static func settle_turn(summary: Dictionary) -> void:
	var revenue := maxf(0.0, float(summary.get("goods_sales_revenue", 0.0)) + float(summary.get("power_sales_revenue", 0.0)))
	var turn := int(TurnManager.current_turn)
	var royalties := 0.0
	var royalty_lines: Array = []
	var titles := ResearchState.licences.keys()
	titles.sort()
	for t: String in titles:
		var l: Dictionary = ResearchState.licences[t]
		if not royalty_active(l, turn):
			continue
		var amount := snappedf(revenue * float(l.get("rate", 0.0)), 0.01)
		if amount <= 0.0:
			continue
		royalties += amount
		royalty_lines.append({"title": t, "rate": float(l.get("rate", 0.0)), "amount": amount})
	if royalties > 0.0:
		MatchState.add_money(-royalties)
		summary["money_out"] = float(summary.get("money_out", 0.0)) + royalties
	summary["royalties_paid"] = royalties
	summary["royalty_lines"] = royalty_lines
	var income := 0.0
	var sale_lines: Array = []
	for due: Dictionary in ResearchState.licence_sales_due:
		income += float(due.get("amount", 0.0))
		sale_lines.append(due.duplicate())
	ResearchState.licence_sales_due.clear()
	if income > 0.0:
		MatchState.add_money(income)
		summary["money_in"] = float(summary.get("money_in", 0.0)) + income
	summary["licence_income"] = income
	summary["licence_sale_lines"] = sale_lines


# --- Licensing out -------------------------------------------------------------------------------------------

## The market goods `title` touches, as good ids, sorted: those made by the buildings and recipes its production
## effects target, the goods those effects name, and those made by the recipes it unlocks. Power is sold to the
## grid, so a power plant process touches no market good.
static func goods_touched(title: String) -> Array:
	return _scope(title).goods


## A process: a node with a production effect scoped to buildings, recipes or goods, or one that unlocks a recipe.
## Company-wide practices (an effect on every building: management, staffing) and logistics, finance or council
## nodes are not processes, so they are not licensed out.
static func is_process(title: String) -> bool:
	return bool(_scope(title).process)


static func _scope(title: String) -> Dictionary:
	if _scope_cache.has(title):
		return _scope_cache[title]
	var node_id := ResearchState.research_node_id_for_title(title)
	var process := false
	var out := {}
	for m: Dictionary in _modifiers_of(title):
		var domain := str(m.get("domain", ""))
		if not PROCESS_DOMAINS.has(domain) or ((m.get("target_match", {}) as Dictionary).is_empty() and domain != "extraction_cap_cost"):
			continue
		process = true
		for r: Dictionary in Catalog.all_recipes():
			for gid: String in _goods_hit(m, r, str(r.get("building_id", ""))):
				out[gid] = true
	for r: Dictionary in Catalog.all_recipes():
		var req := str(r.get("tech_unlock_req", ""))
		if req != "" and (req == node_id or req == title):
			process = true
			for o: Dictionary in r.get("outputs", []):
				out[str(o.get("good_id", ""))] = true
	out.erase("")
	var goods: Array = out.keys().filter(func(gid: String) -> bool:
		return not NOT_MARKET_GOODS.has(Catalog.get_internal_name(gid)))
	goods.sort()
	_scope_cache[title] = {"process": process, "goods": goods}
	return _scope_cache[title]


## The turns of the patent window left for `title` (the turn it was developed, unknown counting as 0).
static func patent_turns_left(title: String) -> int:
	var developed := int(ResearchState.unlock_turns.get(title, 0))
	return developed + EconomyConfig.LICENCE_OUT_WINDOW_TURNS - int(TurnManager.current_turn)


static func _rank(title: String) -> String:
	return str(ResearchState.get_unlock_def(title).get("rank", "I"))


## Why `title` cannot be licensed out now, or "" when it can.
static func license_out_refusal(title: String) -> String:
	if not ResearchState.is_unlocked(title):
		return "Not developed yet"
	if ResearchState.licensed_out.has(title):
		return "Already licensed out"
	if not is_in_house(title):
		return "Licensed in, so it cannot be sublicensed"
	if _rank(title) not in ["II", "III"]:
		return "Rank I processes are not licensed out"
	if not is_process(title):
		return "Not a process: a practice or service, not a production line"
	if patent_turns_left(title) <= 0:
		return "The patent window has closed"
	return ""


## Unsold in-house rank II and III processes other than `title`, as [rank II count, rank III count].
static func _unsold_processes(title: String) -> Vector2i:
	var counts := Vector2i.ZERO
	for t: String in ResearchState.unlocked_titles:
		if t == title or ResearchState.licensed_out.has(t) or not is_in_house(t) or not is_process(t):
			continue
		match _rank(t):
			"II":
				counts.x += 1
			"III":
				counts.y += 1
	return counts


## The licence-out rate for `title`: the base, a step for each other unsold in-house rank II and III process, capped.
static func license_out_rate(title: String) -> float:
	var others := _unsold_processes(title)
	var rate := EconomyConfig.LICENCE_OUT_BASE_RATE + EconomyConfig.LICENCE_OUT_RATE_RANK_II * others.x \
		+ EconomyConfig.LICENCE_OUT_RATE_RANK_III * others.y
	return minf(rate, EconomyConfig.LICENCE_OUT_RATE_CAP)


static func license_out_price(title: String) -> float:
	var revenue := LoanState.recent_revenue(EconomyConfig.LICENCE_OUT_REVENUE_TURNS)
	return snappedf(maxf(EconomyConfig.LICENCE_OUT_FLOOR, license_out_rate(title) * revenue), 0.01)


## Licenses `title` out: paid in this turn's costs phase, and every good it touches sells LICENCE_OUT_PRICE_PCT
## lower for LICENCE_OUT_PRICE_TURNS (one market_price modifier per good, so sales stack). False when refused.
static func license_out(title: String) -> bool:
	if license_out_refusal(title) != "":
		return false
	var price := license_out_price(title)
	ResearchState.licensed_out[title] = int(TurnManager.current_turn)
	ResearchState.licence_sales_due.append({"title": title, "amount": price})
	var node_id := ResearchState.research_node_id_for_title(title)
	for gid: String in goods_touched(title):
		Modifiers.add({"id": "%s:%s:%s" % [OUT_SOURCE, node_id, gid], "domain": "market_price", "target": gid,
			"pct": EconomyConfig.LICENCE_OUT_PRICE_PCT, "duration_turns": EconomyConfig.LICENCE_OUT_PRICE_TURNS,
			"label": "%s licensed out: %d%% sale price" % [title, int(EconomyConfig.LICENCE_OUT_PRICE_PCT)],
			"source": OUT_SOURCE})
	ResearchState.licences_changed.emit()
	return true


# --- Payback at the company's buildings ----------------------------------------------------------------------

## About what `title`'s effects return a turn at the company's current buildings, from each building's running
## P&L (output value, inputs, power, labour and upkeep a turn): throughput scales the margin, output the value, each
## cut its own cost, and an over-cap cost cut the part of a mine's labour and upkeep its seam's M adds. 0 when no
## building it touches has run.
static func estimate_return(title: String) -> float:
	var mods := _modifiers_of(title)
	if mods.is_empty():
		return 0.0
	var total := 0.0
	for iid: String in Production.lifetime_pl_by_building:
		var b: Dictionary = BuildingState.buildings.get(iid, {})
		if b.is_empty() or not BuildingState.is_player_owned(b):
			continue
		var pl: Dictionary = Production.lifetime_pl_by_building[iid]
		var turns := float(maxi(1, int(pl.get("turns", 0))))
		if int(pl.get("turns", 0)) <= 0:
			continue
		var recipe := Catalog.get_recipe(str(b.get("recipe_id", "")))
		if recipe.is_empty():
			continue
		var value := float(pl.get("value", 0.0)) / turns
		var inputs := float(pl.get("inputs", 0.0)) / turns
		var power := float(pl.get("power", 0.0)) / turns
		for m: Dictionary in mods:
			if _goods_hit(m, recipe, str(b.get("building_id", ""))).is_empty():
				continue
			var share := float(m.get("pct", 0.0)) / 100.0
			match str(m.get("domain", "")):
				"throughput":
					total += share * (value - inputs - power)
				"recipe_output":
					total += share * value
				"recipe_input":
					total -= share * inputs * _input_share(recipe, str((m.get("target_match", {}) as Dictionary).get("good_internal", "")))
				"building_power":
					total -= share * power
				"labour_headcount":
					total -= share * float(pl.get("labour", 0.0)) / turns
				"maintenance":
					total -= share * float(pl.get("maint", 0.0)) / turns
				"extraction_cap_cost":
					# Labour and upkeep carry the site's M (1 + cost × workings over the free cap): the cut takes its
					# share of the part over 1.
					var site_m := preload("res://scripts/mining_sites.gd").m_for(b)
					if site_m > 1.0:
						total -= share * (site_m - 1.0) / site_m * (float(pl.get("labour", 0.0)) + float(pl.get("maint", 0.0))) / turns
	return total


## The share of `recipe`'s input value (at buy prices) that `good_internal` makes up; 1 for "" (every input).
static func _input_share(recipe: Dictionary, good_internal: String) -> float:
	if good_internal == "":
		return 1.0
	var all := 0.0
	var part := 0.0
	for inp: Dictionary in recipe.get("inputs", []):
		var v := float(inp.get("qty", 0)) * MarketState.get_buy_price(str(inp.get("good_id", "")))
		all += v
		if str(inp.get("internal_name", "")) == good_internal:
			part += v
	return part / all if all > 0.0 else 0.0


# --- Words ---------------------------------------------------------------------------------------------------

## The terms of licensing `title`, as the drawing and the dialog print them.
static func terms_text(terms: Dictionary) -> String:
	if str(terms.get("kind", "")) == "flat":
		return _money(float(terms.get("price", 0.0)))
	return "%s of revenue, %d turns" % [_pct(float(terms.get("rate", 0.0))), int(terms.get("turns", EconomyConfig.LICENCE_ROYALTY_TURNS))]


## One line for a group member's drawing: what it costs to license, or how it is held.
static func price_line(title: String) -> String:
	if ResearchState.licence_group_of(title) == "":
		return ""
	if not ResearchState.is_unlocked(title):
		return "License for %s" % terms_text(terms_for(title))
	var l := licence_of(title)
	match str(l.get("kind", "inhouse")):
		"flat":
			return "Licensed for %s" % _money(float(l.get("price", 0.0)))
		"royalty":
			var left := royalty_turns_left(title)
			return "Licensed, %s of revenue, %d turns left" % [_pct(float(l.get("rate", 0.0))), left] if left > 0 \
				else "Licensed, paid up"
	return "Developed in house" if ResearchState.free_picks.has(title) else "In house"


## The licence-out line for an in-house process: its price and window, or why not.
static func out_line(title: String) -> String:
	var why := license_out_refusal(title)
	if why == "":
		return "License out for %s, %d turns left" % [_money(license_out_price(title)), patent_turns_left(title)]
	if ResearchState.licensed_out.has(title):
		return "Licensed out"
	return ""


## The goods `title` touches, by name, for the licence-out consequence.
static func goods_text(title: String) -> String:
	var names: Array = []
	for gid: String in goods_touched(title):
		names.append(Catalog.get_display_name(gid))
	if names.size() > 4:
		return "%s and %d more" % [", ".join(names.slice(0, 3)), names.size() - 3]
	if names.size() > 1:
		return "%s and %s" % [", ".join(names.slice(0, names.size() - 1)), names[-1]]
	return "".join(names)


static func _money(v: float) -> String:
	return "£%s" % String.num(v, 0 if is_equal_approx(v, roundf(v)) else 2)


static func _pct(rate: float) -> String:
	var p := rate * 100.0
	return ("%d%%" % int(roundf(p))) if is_equal_approx(p, roundf(p)) else ("%.1f%%" % p)


# --- Matching a node's effects to recipes --------------------------------------------------------------------

static func _modifiers_of(title: String) -> Array:
	var spec: Variant = Modifiers.unlock_spec_for(title)
	if spec is Array:
		return spec
	if spec is Dictionary and not (spec as Dictionary).is_empty():
		return [spec]
	return []


## The good ids of `recipe` (run by `building_id`) that modifier `m` touches: its outputs when the effect reaches the
## recipe, only the named output for an output effect scoped to one good, none when it does not reach it.
static func _goods_hit(m: Dictionary, recipe: Dictionary, building_id: String) -> Array:
	var domain := str(m.get("domain", ""))
	var tm: Dictionary = m.get("target_match", {})
	if domain == "extraction_cap_cost" and tm.is_empty():
		tm = {"building_id": MINE_BUILDING}
	var only := ""
	for key: String in tm:
		var want := str(tm[key])
		match key:
			"building_id":
				if building_id != want:
					return []
			"makes":
				if not Catalog.goods_made(str(recipe.get("recipe_id", ""))).has(want):
					return []
			"good_internal":
				if domain == "recipe_input":
					if not recipe.get("inputs", []).any(func(i: Dictionary) -> bool: return str(i.get("internal_name", "")) == want):
						return []
				elif not Catalog.goods_made(str(recipe.get("recipe_id", ""))).has(want):
					return []
				else:
					only = want
			"on_infinite_deposit":
				pass
			_:
				return []
	var out: Array = []
	for o: Dictionary in recipe.get("outputs", []):
		if only == "" or str(o.get("internal_name", "")) == only:
			out.append(str(o.get("good_id", "")))
	return out
