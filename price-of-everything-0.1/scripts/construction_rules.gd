extends RefCounted
## ConstructionRules: the questions the construct flow asks, answered in one place and without
## side effects. What may be built (the catalogue), whether a site allows it (the site rules),
## what it costs and when (the quote), and why it cannot go ahead (the blocks).
##
## Each rule is the one the build applies. world_map's build and infrastructure attempts call
## the site, land, source and fee rules below, so a panel that reads them shows the refusal and
## the figure the engine acts on. The construct panel, the map's build overlay and the build
## hover card still carry their own copies; moving them onto these helpers is the next step.
##
## Preload by path (no class_name until the editor has scanned the file):
##   const ConstructionRules := preload("res://scripts/construction_rules.gd")
##
## The flows and the helpers they read:
##   Browse          catalogue(tile_data), recipe_offer(), building_offer()
##   Map pick        site_check(): the cheap per tile verdict, no prices
##   Confirm         quote(): fee, materials, land, total, turns, blocks, warnings; site_needs()
##   Materials       material_source(), materials_quote()
##   Land            land_plan()
##   Infrastructure  quote() with an empty recipe (the tile view's add keys, the catalogue)

## Roads and rail may not cross water; a pipeline or a cable may. Keyed by internal name, as
## world_map's space check always was.
const OVERLAND_INFRA := {"roads": true, "rail": true}
const InfraIcons := preload("res://scripts/infra_icons.gd")
const MONEY_EPSILON := 0.0001


# --- Browse: what may be built -------------------------------------------------------------

## Whether a building is offered at all: the port is never built, recycling and hidden
## prototypes wait for their unlocks, and a building's own research gate applies.
static func building_offer(building_id: String) -> Dictionary:
	if not MatchState.is_building_available(building_id):
		return {"offered": false, "reason": "unavailable"}
	var research := str(Catalog.get_building(building_id).get("required_research", ""))
	if research != "" and not ResearchState.is_unlocked(research):
		return {"offered": false, "reason": "research", "research": research}
	return {"offered": true, "reason": ""}


## Whether a recipe is offered: its research first, then, when a site is given, the terrain
## and the recipe's requirements as the build checks them (an unsurveyed deposit is offered,
## since the build lets the player build blind).
static func recipe_offer(recipe: Dictionary, tile_data: Dictionary = {}) -> Dictionary:
	var research := str(recipe.get("tech_unlock_req", ""))
	if research != "" and not ResearchState.is_unlocked(research):
		return {"offered": false, "reason": "research", "research": research}
	if tile_data.is_empty():
		return {"offered": true, "reason": ""}
	var building_id := str(recipe.get("building_id", ""))
	if not Catalog.is_building_allowed_on_tile_type(building_id, str(tile_data.get("type", ""))):
		return {"offered": false, "reason": "terrain"}
	var block := requirement_block(tile_data, recipe, str(tile_data.get("id", "")))
	if block != "":
		return {"offered": false, "reason": block}
	return {"offered": true, "reason": ""}


## The catalogue: every building the player may see, sorted by name, each with its recipes and
## whether each is offered (on `tile_data` when given). Buildings and recipes behind research
## are left out, as the construct panel leaves them out. A tile's infrastructure is listed with
## `infrastructure = true` and no recipes; it is offered when Infrastructure Tendering allows.
##   [{building_id, building, infrastructure, offered, reason,
##     recipes: [{recipe_id, recipe, offered, reason}]}]
static func catalogue(tile_data: Dictionary = {}) -> Array:
	var recipes_by_building: Dictionary = {}
	for recipe_variant: Variant in Catalog.all_recipes():
		var recipe: Dictionary = recipe_variant
		var building_id := str(recipe.get("building_id", ""))
		if building_id == "":
			continue
		var offer := recipe_offer(recipe, tile_data)
		if str(offer.reason) == "research":
			continue
		if not recipes_by_building.has(building_id):
			recipes_by_building[building_id] = []
		(recipes_by_building[building_id] as Array).append({"recipe_id": str(recipe.get("recipe_id", "")),
			"recipe": recipe, "offered": bool(offer.offered), "reason": str(offer.reason)})
	var entries: Array = []
	for building_variant: Variant in Catalog.all_buildings():
		var building: Dictionary = building_variant
		var building_id := str(building.get("id", ""))
		if not bool(building_offer(building_id).offered):
			continue
		var infrastructure := is_tile_infrastructure(str(building.get("internal_name", "")))
		var recipes: Array = recipes_by_building.get(building_id, [])
		var offered := false
		var reason := ""
		if infrastructure:
			offered = ResearchState.infrastructure_tendering_available()
			reason = "" if offered else "tendering"
		else:
			for entry: Variant in recipes:
				offered = offered or bool((entry as Dictionary).offered)
			if recipes.is_empty():
				reason = "no_recipes"
			elif not offered:
				reason = "site"
		entries.append({"building_id": building_id, "building": building, "infrastructure": infrastructure,
			"offered": offered, "reason": reason, "recipes": recipes})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.building.get("display_name", "")).naturalnocasecmp_to(str(b.building.get("display_name", ""))) < 0)
	return entries


## The infrastructure a tile carries as a slot (cables, roads, pipes, HVDC, rail, reinforced
## pipes). The port and the airport are "infrastructure" in the catalogue but ordinary buildings.
static func is_tile_infrastructure(internal_name: String) -> bool:
	if internal_name == "":
		return false
	for slot: Variant in InfraIcons.SLOTS:
		if str((slot as Dictionary).key) == internal_name:
			return true
	return false


# --- Site rules ------------------------------------------------------------------------------

## The build's requirement gate for a recipe on a tile: "" when met, "deposit" when a known
## deposit is missing, "other" for any other unmet requirement. An unsurveyed tile skips its
## deposit checks (a blind build, revealed when it finishes); water is always visible.
static func requirement_block(tile_data: Dictionary, recipe: Dictionary, tile_id: String) -> String:
	var status := MatchState.survey_status(tile_id, str(tile_data.get("type", "")))
	for req_variant: Variant in recipe.get("requirements", []):
		var req: Dictionary = req_variant
		if str(req.get("type", "")) == "deposit":
			if str(req.get("value", "")) != "water" and status == "unsurveyed":
				continue
			if not tile_meets_requirement(tile_data, req):
				return "deposit"
		elif not tile_meets_requirement(tile_data, req):
			return "other"
	return ""


## The deposit a blind build is betting on: the recipe's non-water deposit when the tile is
## unsurveyed, else "". The build goes ahead and the deposit is revealed when it finishes.
static func blind_deposit(tile_data: Dictionary, recipe: Dictionary, tile_id: String) -> String:
	if MatchState.survey_status(tile_id, str(tile_data.get("type", ""))) != "unsurveyed":
		return ""
	for req_variant: Variant in recipe.get("requirements", []):
		var req: Dictionary = req_variant
		var token := str(req.get("value", ""))
		if str(req.get("type", "")) == "deposit" and token != "" and token != "water":
			return token
	return ""


static func tile_meets_requirement(tile_data: Dictionary, req: Dictionary) -> bool:
	match str(req.get("type", "")):
		"deposit":
			return deposits_include(tile_data.get("deposits", []), str(req.get("value", "")))
		"produces":
			return tile_produces_good(tile_data, str(req.get("value", "")))
		"potential":
			var value := str(req.get("value", ""))
			if value == "wind":
				return tile_data.get("wind_potential", 0) > 0
			if value == "solar":
				return tile_data.get("solar_potential", 0) > 0
			return false
	return false


static func deposits_include(deposits: Array, internal_name: String) -> bool:
	if internal_name == "":
		return false
	for deposit: Variant in deposits:
		if deposit_base_name(str(deposit)) == internal_name:
			return true
	return false


## "coal(1000)" → "coal".
static func deposit_base_name(deposit: String) -> String:
	var value := deposit.strip_edges()
	var quantity_marker := value.find("(")
	if quantity_marker > 0 and value.ends_with(")"):
		return value.substr(0, quantity_marker)
	return value


static func tile_produces_good(tile_data: Dictionary, internal_name: String) -> bool:
	var tile_id := str(tile_data.get("id", ""))
	if tile_id == "":
		return false
	for instance_id: Variant in BuildingState.tile_buildings.get(tile_id, []):
		var building: Dictionary = BuildingState.buildings.get(instance_id, {})
		if building.is_empty():
			continue
		var recipe: Dictionary = Catalog.get_recipe(str(building.get("recipe_id", "")))
		if str(recipe.get("output_name", "")) == internal_name:
			return true
		for output: Variant in recipe.get("outputs", []):
			if str((output as Dictionary).get("internal_name", "")) == internal_name:
				return true
	return false


## Is there physical room for the building, counting everyone's buildings, live projects and
## reserved upgrades? The one absolute limit: owned land can be bought, this cannot.
static func has_physical_room(tile_id: String, building_id: String) -> bool:
	var needed := maxf(0.0, float(Catalog.get_building(building_id).get("tile_size_used", 1.0)))
	return BuildingState.get_tile_space_used(tile_id) + needed <= float(BuildingState.max_tile_land(tile_id))


## The map pick's cheap verdict for one tile, no prices: the first rule that refuses the build
## there, in the build's own order, or "" when none does. Owned land is left to quote(): a
## shortfall may be bought.
static func site_check(building_id: String, recipe_id: String, tile_data: Dictionary) -> String:
	var tile_id := str(tile_data.get("id", ""))
	if recipe_id != "":
		if not Catalog.is_building_allowed_on_tile_type(building_id, str(tile_data.get("type", ""))):
			return "terrain"
		var block := requirement_block(tile_data, Catalog.get_recipe(recipe_id), tile_id)
		if block != "":
			return block
	var internal := str(Catalog.get_building(building_id).get("internal_name", ""))
	if OVERLAND_INFRA.has(internal) and _is_sea(Catalog.tile_type(tile_id)):
		return "sea"
	if not has_physical_room(tile_id, building_id):
		return "full"
	return ""


# --- Land ------------------------------------------------------------------------------------

## The land a build needs on a tile and what the build will do about it, in the order the
## build's space check decides:
##   outcome        "ok", "sea" (roads or rail on water), "full" (the tile's physical cap),
##                  "cannot_buy" (a purchase was wanted but nothing is for sale or the cash
##                  is short), "short" (not enough owned land and no purchase)
##   will_buy       the build buys `patches` of land for `cost` on the way
##   density_multiplier  1.5 past the planning limit (everyone's land over 100), else 1
## `buy_land` is the confirm's one off intent; the standing Auto-buy land setting also buys.
## Tendered infrastructure (Logistics Intermediary games with Infrastructure Tendering) may
## cross land the player does not own.
static func land_plan(tile_id: String, building_id: String, buy_land: bool = false) -> Dictionary:
	var building := Catalog.get_building(building_id)
	var internal := str(building.get("internal_name", ""))
	var needed := maxf(0.0, float(building.get("tile_size_used", 1.0)))
	var projected := BuildingState.get_tile_space_used(tile_id) + needed
	var max_land := BuildingState.max_tile_land(tile_id)
	var player_projected := BuildingState.get_tile_player_space_used(tile_id) + needed
	var owned := BuildingState.get_tile_land_owned(tile_id)
	var tendered := ResearchState.logistics_progression_active() \
		and ResearchState.infrastructure_tendering_available() and is_tile_infrastructure(internal)
	var shortfall := maxf(0.0, player_projected - float(owned)) if not tendered else 0.0
	var wants_buy := shortfall > 0.0 and (MatchState.construct_auto_buy_land or buy_land)
	var patches_for_sale := BuildingState.get_tile_land_patches_available(tile_id)
	var patches := 0
	var cost := 0.0
	var owned_after := owned
	if shortfall > 0.0 and patches_for_sale > 0:
		# purchase_tile_land's own clamp and price, and the sliver it may grant.
		patches = clampi(int(ceil(shortfall / float(BuildingState.LAND_PATCH_SIZE))), 1, patches_for_sale)
		cost = AdvisorState.purchase_cost_after_advisor(float(patches) * BuildingState.LAND_PATCH_COST, {"tile_id": tile_id})
		var granted := mini(patches * BuildingState.LAND_PATCH_SIZE, BuildingState.get_tile_land_units_available(tile_id))
		owned_after = mini(max_land, owned + granted)
	var outcome := "ok"
	var will_buy := false
	if OVERLAND_INFRA.has(internal) and _is_sea(Catalog.tile_type(tile_id)):
		outcome = "sea"
	elif projected > float(max_land):
		outcome = "full"
	elif shortfall > 0.0:
		if wants_buy:
			if patches_for_sale <= 0 or MatchState.money < cost:
				outcome = "cannot_buy"
			elif player_projected > float(owned_after):
				outcome = "short"
				will_buy = true   # the build buys the sliver, then refuses for the rest
			else:
				will_buy = true
		else:
			outcome = "short"
	var free := maxi(0, owned - roundi(BuildingState.get_tile_player_space_used(tile_id)))
	return {
		"outcome": outcome, "allowed": outcome == "ok",
		"needed": needed, "free": free, "owned": owned, "owned_after": owned_after if will_buy else owned,
		"shortfall": shortfall, "tendered": tendered,
		"patches_for_sale": patches_for_sale, "patches": patches, "units": patches * BuildingState.LAND_PATCH_SIZE,
		"cost": cost, "wants_buy": wants_buy, "will_buy": will_buy,
		"covered_by_purchase": patches_for_sale > 0 and player_projected <= float(owned_after),
		"max_land": max_land, "projected": projected, "player_projected": player_projected,
		"density_multiplier": 1.5 if projected > BuildingState.DENSITY_SOFT_CAPACITY else 1.0,
	}


# --- Materials -------------------------------------------------------------------------------

## Where a build's missing materials will come from. `requested` overrides the one build pick
## and the standing setting; "" reads them as the build does (without consuming the pick).
##   source   "middleman", "market", "same_tile" or "any_tile" after the research gates
##   buys_via the path that actually buys: "middleman" outside a Logistics Intermediary game
##            buys from the market
##   notes    [{key, text}] for each gate that changed the source (the build toasts them)
static func material_source(requested: String = "") -> Dictionary:
	var source := requested
	if source == "":
		source = MatchState.pending_build_material_source if MatchState.pending_build_material_source != "" \
			else MatchState.construct_material_source
	if source == "ask" or source == "":
		source = "middleman"
	var asked := source
	var notes: Array = []
	var intermediary := ResearchState.logistics_progression_active()
	if intermediary and source in ["same_tile", "any_tile"] and not ResearchState.open_logistics_contracts_available():
		notes.append({"key": "contracts",
			"text": "Open Logistics Contracts is required to use tile stockpiles for construction."})
		source = "middleman"
	if intermediary and source == "market" and not ResearchState.global_trade_license_available():
		notes.append({"key": "license",
			"text": "Government Import/Export License is required for direct global-market construction purchases."})
		source = "middleman"
	var buys_via := source
	if source == "middleman" and not intermediary:
		buys_via = "market"
	return {"asked": asked, "source": source, "buys_via": buys_via, "notes": notes}


## What bringing the missing materials to `tile_id` costs, by the source's own path, the figure
## the build checks the player can afford:
##   satisfied  the tile already holds the kit (the build consumes it, nothing is bought)
##   cost       goods plus delivery; turns the lead time; source_tile for "any_tile"
##   block      "materials_short" (same tile source, kit missing) or "no_surplus" (no tile
##              holds the spare), else ""
static func materials_quote(building_id: String, tile_id: String, source: Dictionary) -> Dictionary:
	var check: Dictionary = Construction.check_tile(tile_id, building_id)
	var missing: Dictionary = check.get("missing", {})
	var out := {"satisfied": bool(check.get("satisfied", false)), "missing": missing, "cost": 0.0,
		"turns": 0, "source_tile": "", "block": ""}
	if bool(out.satisfied):
		return out
	match str(source.buys_via):
		"middleman":
			out.cost = Construction.estimate_middleman_cost(tile_id, building_id)
			out.turns = 1
		"same_tile":
			out.block = "materials_short"
		"any_tile":
			var from: Dictionary = Construction.find_source_tile(tile_id, missing)
			if from.is_empty():
				out.block = "no_surplus"
			else:
				out.source_tile = str(from.get("tile_id", ""))
				out.turns = int(from.get("turns", 0))
				out.cost = float(TransportState.preview_move(str(out.source_tile), tile_id, missing).get("cost", 0.0))
		_:
			out.cost = Construction.estimate_market_cost(tile_id, building_id)
			var turns := 0
			for row: Variant in Construction.materials_ledger(building_id, tile_id).get("rows", []):
				turns = maxi(turns, int((row as Dictionary).get("market_turns", 0)))
			out.turns = turns
	return out


# --- Money -----------------------------------------------------------------------------------

## The cash fee a building's build charges: its base price, raised past the planning limit,
## less the Chief Investment materials rebate.
static func build_fee(building_id: String, density_multiplier: float = 1.0) -> float:
	var base := float(Catalog.get_building(building_id).get("base_price", 0.0))
	return maxf(0.0, base * density_multiplier - MatchState.construction_material_rebate(building_id))


## The fee for infrastructure whose kit is already on the tile: the rebate comes off before the
## planning limit's rise, the other way round from build_fee. (A kit that has to be bought goes
## through the building paths and pays build_fee.)
static func infrastructure_fee(building_id: String, density_multiplier: float = 1.0) -> float:
	var base := float(Catalog.get_building(building_id).get("base_price", 0.0))
	return maxf(0.0, base - MatchState.construction_material_rebate(building_id)) * density_multiplier


# --- Site infrastructure ---------------------------------------------------------------------

## The infrastructure one good needs to reach or leave a tile, or "" when it travels overland.
static func infra_key_for_good(good_id: String) -> String:
	if good_id == "":
		return ""
	match Catalog.get_transport_class(good_id):
		"hazard_liquid":
			return "reinf_pipes"
		"safe_liquid", "liquid", "gas":
			return "pipes"
		"electricity":
			return "cables"
	return ""


## The connections a recipe needs on its site: one entry per infrastructure, in the order
## cables, pipes, reinforced pipes, inputs before outputs.
##   [{infra_key, good_ids, is_output, satisfied}]
## Power drawn by the recipe needs cables. Outputs are only judged on a known tile, and
## `satisfied` only means something there. Advisory: nothing here refuses the build.
static func site_needs(recipe: Dictionary, tile_id: String = "") -> Array:
	var needs: Array = []
	if recipe.is_empty():
		return needs
	var inputs := _needs_for(recipe.get("inputs", []))
	if int(recipe.get("energy_req", 0)) > 0:
		_add_need(inputs, "cables", str(Catalog.get_good_by_internal_name("power").get("id", "")))
	for key: String in ["cables", "pipes", "reinf_pipes"]:
		if inputs.has(key):
			needs.append({"infra_key": key, "good_ids": inputs[key], "is_output": false,
				"satisfied": tile_id != "" and Catalog.tile_has_infrastructure(tile_id, key)})
	if tile_id != "":
		var outputs := _needs_for(recipe.get("outputs", []))
		for key: String in ["cables", "pipes", "reinf_pipes"]:
			if outputs.has(key):
				needs.append({"infra_key": key, "good_ids": outputs[key], "is_output": true,
					"satisfied": Catalog.tile_has_infrastructure(tile_id, key)})
	return needs


static func is_intermittent(building_id: String) -> bool:
	return str(Catalog.get_building(building_id).get("internal_name", "")) in EconomyConfig.POWER_INTERMITTENT_BUILDINGS


# --- The quote -------------------------------------------------------------------------------

## Everything the confirm step says about building `building_id` with `recipe_id` on
## `tile_id`, and everything the build will do, computed without doing it. An empty recipe
## quotes infrastructure (roads, cables, pipes and so on).
##
## opts:
##   source    a material source for this build ("" reads the pick and the setting)
##   buy_land  the confirm's buy land intent (the standing Auto-buy land setting also buys)
##
## Returns:
##   site_known        false with no tile: the figures are estimates at market prices,
##                     without freight, land or the planning limit
##   fee, materials, land, total   what the build spends (land only when it buys some)
##   cash_after        cash once it has
##   build_turns, materials_turns
##   source            material_source(); land (land_plan()); materials (materials_quote())
##   blocks            [{key, text}] every reason the build would be refused, in the order the
##                     build checks them; `ok` when there are none
##   warnings          [{key, text}] what goes ahead but deserves a word
##
## Block keys: tutorial_area, tendering, terrain, deposit, requirement, already_built,
## in_progress, sea, full, cannot_buy_land, land_short, materials_short, no_surplus, funds.
## Warning keys: site_unknown, blind_deposit, density, buys_land, source_changed, needs_cables,
## needs_pipes, needs_reinf_pipes, intermittent.
static func quote(building_id: String, recipe_id: String = "", tile_id: String = "",
		tile_data: Dictionary = {}, opts: Dictionary = {}) -> Dictionary:
	var building := Catalog.get_building(building_id)
	var internal := str(building.get("internal_name", ""))
	var infrastructure := recipe_id == "" and is_tile_infrastructure(internal)
	var recipe: Dictionary = Catalog.get_recipe(recipe_id) if recipe_id != "" else {}
	var source := material_source(str(opts.get("source", "")))
	var blocks: Array = []
	var warnings: Array = []
	var q := {
		"building_id": building_id, "recipe_id": recipe_id, "tile_id": tile_id,
		"infrastructure": infrastructure, "site_known": tile_id != "",
		"build_turns": MatchState.effective_build_duration(building_id), "materials_turns": 0,
		"source": source, "blocks": blocks, "warnings": warnings,
	}
	for note: Variant in source.notes:
		warnings.append({"key": "source_changed", "text": str((note as Dictionary).text)})
	if is_intermittent(building_id):
		warnings.append({"key": "intermittent", "text": "Output rises and falls with the weather."})

	if tile_id == "":
		# No site yet: the kit at today's prices by the chosen source, the fee without the
		# planning limit. Land, freight and the site's own rules wait for the tile.
		var ledger: Dictionary = Construction.materials_ledger(building_id, "")
		q.fee = build_fee(building_id)
		q.materials = float(ledger.get("subtotal", 0.0))
		q.land = 0.0
		q.total = float(q.fee) + float(q.materials)
		q.cash_after = MatchState.money - float(q.total)
		q.land_plan = {}
		q.materials_quote = {}
		warnings.push_front({"key": "site_unknown",
			"text": "Freight, land and local rules are known once a site is chosen."})
		if MatchState.money + MONEY_EPSILON < float(q.total):
			blocks.append(_funds_block(float(q.total)))
		q.ok = blocks.is_empty()
		return q

	if tile_data.is_empty():
		tile_data = {"id": tile_id, "type": Catalog.tile_type(tile_id)}

	# The build's order: the tutorial board, the terrain and the recipe's requirements for a
	# building; Infrastructure Tendering, an existing slot and a running project for
	# infrastructure.
	if infrastructure:
		if not ResearchState.infrastructure_tendering_available():
			blocks.append({"key": "tendering", "text": "Infrastructure Tendering is needed to build infrastructure."})
		if _tile_has_infrastructure(tile_data, tile_id, internal):
			blocks.append({"key": "already_built", "text": "This tile already has %s." % str(building.get("display_name", internal))})
		for project: Variant in Construction.projects_on_tile(tile_id):
			if str((project as Dictionary).get("building_id", "")) == building_id:
				blocks.append({"key": "in_progress", "text": "%s is already being built here." % str(building.get("display_name", internal))})
				break
	else:
		if Tutorial.active and not Tutorial.tile_allowed(tile_id):
			blocks.append({"key": "tutorial_area", "text": "Stay on the tutorial area for now."})
		var tile_type := str(tile_data.get("type", ""))
		if not Catalog.is_building_allowed_on_tile_type(building_id, tile_type):
			blocks.append({"key": "terrain", "text": "Only offshore wind farms and oil platforms can be built at sea."
				if _is_sea(tile_type) else "Offshore buildings need a sea tile."})
		elif not recipe.is_empty():
			match requirement_block(tile_data, recipe, tile_id):
				"deposit":
					blocks.append({"key": "deposit", "text": "This tile has no deposit for this recipe."})
				"other":
					blocks.append({"key": "requirement", "text": "This tile does not meet the recipe's requirements."})
			var blind := blind_deposit(tile_data, recipe, tile_id)
			if blind != "":
				warnings.append({"key": "blind_deposit",
					"text": "Unsurveyed. The %s deposit is confirmed when the building is finished." % _deposit_name(blind)})

	var land := land_plan(tile_id, building_id, bool(opts.get("buy_land", false)))
	q.land_plan = land
	match str(land.outcome):
		"sea":
			blocks.append({"key": "sea", "text": "Roads and railways cannot be built on sea."})
		"full":
			blocks.append({"key": "full", "text": "No room on this tile. It holds %d land." % int(land.max_land)})
		"cannot_buy":
			blocks.append({"key": "cannot_buy_land", "text": "Not enough land for sale here." if int(land.patches_for_sale) <= 0
				else "Not enough cash to buy the land."})
		"short":
			blocks.append({"key": "land_short", "text": "Needs %d more land." % ceili(float(land.shortfall))})
	if bool(land.will_buy) and str(land.outcome) == "ok":
		warnings.append({"key": "buys_land", "text": "Buys %d land for %s." % [int(land.units), _money(float(land.cost))]})
	var multiplier := float(land.density_multiplier)
	if multiplier > 1.0:
		warnings.append({"key": "density", "text": "Past the planning limit. The build fee is 50% higher."})

	var mats := materials_quote(building_id, tile_id, source)
	q.materials_quote = mats
	q.materials_turns = int(mats.turns)
	match str(mats.block):
		"materials_short":
			blocks.append({"key": "materials_short", "text": "This tile must hold every material before building."})
		"no_surplus":
			blocks.append({"key": "no_surplus", "text": "No tile has the spare materials for this build."})

	# A kit already on the tile builds straight away; infrastructure then takes the rebate first.
	if infrastructure and bool(mats.satisfied):
		q.fee = infrastructure_fee(building_id, multiplier)
	else:
		q.fee = build_fee(building_id, multiplier)
	q.materials = float(mats.cost)
	q.land = float(land.cost) if bool(land.will_buy) else 0.0
	q.total = float(q.fee) + float(q.materials) + float(q.land)
	q.cash_after = MatchState.money - float(q.total)
	if MatchState.money + MONEY_EPSILON < float(q.total) and str(land.outcome) != "cannot_buy":
		blocks.append(_funds_block(float(q.total)))

	for need: Variant in site_needs(recipe, tile_id):
		var n: Dictionary = need
		if not bool(n.satisfied):
			warnings.append({"key": "needs_" + str(n.infra_key), "text": "%s missing. %s" % [
				_infra_label(str(n.infra_key)), "Outputs cannot leave the tile." if bool(n.is_output) else "Inputs cannot reach it."]})
	q.ok = blocks.is_empty()
	return q


# --- Internals -------------------------------------------------------------------------------

static func _is_sea(tile_type: String) -> bool:
	return tile_type == "sea" or tile_type == "deep_sea"


## The map's own list when the caller passes the map's tile (the build reads that one), else
## the catalogue's copy.
static func _tile_has_infrastructure(tile_data: Dictionary, tile_id: String, internal: String) -> bool:
	if tile_data.has("infrastructure_present"):
		return (tile_data.get("infrastructure_present", []) as Array).has(internal)
	return Catalog.tile_has_infrastructure(tile_id, internal)


static func _needs_for(entries: Array) -> Dictionary:
	var needs: Dictionary = {}
	for entry: Variant in entries:
		var good_id := str((entry as Dictionary).get("good_id", ""))
		var key := infra_key_for_good(good_id)
		if key != "":
			_add_need(needs, key, good_id)
	return needs


static func _add_need(needs: Dictionary, key: String, good_id: String) -> void:
	if good_id == "":
		return
	var goods: Array = needs.get(key, [])
	if not goods.has(good_id):
		goods.append(good_id)
	needs[key] = goods


static func _funds_block(total: float) -> Dictionary:
	return {"key": "funds", "text": "Needs %s. You have %s." % [_money(total), _money(MatchState.money)]}


static func _deposit_name(token: String) -> String:
	var good: Dictionary = Catalog.get_good_by_internal_name("pure_water" if token == "water" else token)
	return str(good.get("display_name", token.capitalize())).to_lower()


static func _infra_label(key: String) -> String:
	for slot: Variant in InfraIcons.SLOTS:
		if str((slot as Dictionary).key) == key:
			return str((slot as Dictionary).label)
	return key.capitalize()


## £1,234.56, the separators the owner asks for in counts and money.
static func _money(amount: float) -> String:
	var whole := int(floor(absf(amount)))
	var pence := roundi((absf(amount) - float(whole)) * 100.0)
	if pence >= 100:
		whole += 1
		pence -= 100
	var digits := str(whole)
	var grouped := ""
	while digits.length() > 3:
		grouped = "," + digits.substr(digits.length() - 3) + grouped
		digits = digits.substr(0, digits.length() - 3)
	return "%s£%s%s.%02d" % ["-" if amount < 0.0 else "", digits, grouped, pence]
