extends RefCounted
## Tile view v3, Transport: what pressing a link's Build key will spend and do, quoted before the press so
## the key's card can say it. A refused quote still carries what the build would cost once the reason is
## dealt with: the fee, and the materials when they can be priced.
##
## The map lays a link in world_map._on_infrastructure_attempted, checking the site in _space_check_for_build
## and pricing it inline as it goes (buying land and raising toasts on the way), so there is no quote to
## call. This follows those steps in the same order without acting on any of them, and reads every figure
## from the engine:
##   refused    an overland link on the sea (the map's own OVERLAND_INFRA), no room left on the tile
##              (BuildingState.max_tile_land), land short while automatic buying is off, no land for sale,
##              materials the build's source can't bring;
##   land       the shortfall in the company's land here, in whole patches at the price
##              BuildingState.purchase_tile_land charges (AdvisorState.purchase_cost_after_advisor); none for
##              a tendered link in a logistics game;
##   fee        the catalogue's base price less MatchState.construction_material_rebate, and half as much again
##              past the planning limit (BuildingState.DENSITY_SOFT_CAPACITY), each as the map charges it;
##   materials  what the tile lacks (Construction.check_tile), brought by the build's material source as the
##              map routes it: Construction.estimate_market_cost or estimate_middleman_cost, or the move from a
##              tile with spare stock (Construction.find_source_tile, TransportState.preview_move).

## The map's charge past the planning limit (world_map._space_check_for_build's cost_multiplier).
const PLANNING_CHARGE := 1.5


## The quote for laying `building_id` on `tile_id`: {ok, refusal (a few words for the card), why (a sentence),
## base, fee, planning (past the limit), land_units, land_cost, land_short (the land a refusal lacks),
## materials ("", "order" or "ship"), missing (good id -> the units the tile lacks), materials_cost, total,
## affordable, turns (how long it takes to build, MatchState.effective_build_duration)}.
static func quote(tile_id: String, building_id: String) -> Dictionary:
	var bd: Dictionary = Catalog.get_building(building_id)
	var internal := str(bd.get("internal_name", ""))
	var base := maxf(0.0, float(bd.get("base_price", 0.0)))
	var q := {"ok": true, "refusal": "", "why": "", "base": base, "fee": base, "planning": false,
		"land_units": 0, "land_cost": 0.0, "land_short": 0, "materials": "", "missing": {}, "materials_cost": 0.0,
		"total": base, "affordable": true, "turns": MatchState.effective_build_duration(building_id)}
	# The fee, as the map charges it once the site is allowed: worked out first so a refusal's card can say
	# what the build would cost once the reason is dealt with.
	var size := maxf(0.0, float(bd.get("tile_size_used", 1.0)))
	var projected := BuildingState.get_tile_space_used(tile_id) + size
	var planning := projected > BuildingState.DENSITY_SOFT_CAPACITY
	var charge := PLANNING_CHARGE if planning else 1.0
	var rebate := MatchState.construction_material_rebate(building_id)
	q.planning = planning
	q.fee = maxf(0.0, base - rebate) * charge
	q.total = q.fee
	var overland: Dictionary = _map_constant("OVERLAND_INFRA", {})
	if overland.has(internal) and Catalog.tile_type(tile_id) in ["sea", "deep_sea"]:
		return _refuse(q, "Not on the sea", "Roads and rail can't be laid across water.")
	if projected > float(BuildingState.max_tile_land(tile_id)):
		return _refuse(q, "No room here", "There is no room left on this tile. Demolish a building to make some.")

	# Land: a tendered link crosses land the company doesn't own; any other takes the shortfall in whole
	# patches when automatic buying is on, and is refused when it is off. A refusal over land is held while
	# the materials are priced, so its card can still say what the build itself costs.
	var held: Array = []
	var tendered := ResearchState.logistics_progression_active() and ResearchState.infrastructure_tendering_available()
	var short := BuildingState.get_tile_player_space_used(tile_id) + size - float(BuildingState.get_tile_land_owned(tile_id))
	if short > 0.0 and not tendered:
		var need := ceili(short)
		q.land_short = need
		var available := BuildingState.get_tile_land_patches_available(tile_id)
		var patches := clampi(ceili(short / float(BuildingState.LAND_PATCH_SIZE)), 1, maxi(available, 1))
		var granted := mini(patches * BuildingState.LAND_PATCH_SIZE, BuildingState.get_tile_land_units_available(tile_id))
		if not (MatchState.construct_auto_buy_land or BuildMode.attempt_buy_land):
			held = ["Buy land first", "It needs %d more land here, and automatic land buying is off." % need]
		elif available <= 0 or float(granted) < short:
			held = ["No land for sale", "It needs %d more land here, and not enough is for sale." % need]
		else:
			q.land_short = 0
			q.land_units = granted
			q.land_cost = AdvisorState.purchase_cost_after_advisor(float(patches) * BuildingState.LAND_PATCH_COST, {"tile_id": tile_id})

	# Materials the tile lacks, by the route the map takes for them. On that route the map prices the fee
	# with the rebate taken after the planning charge.
	var check: Dictionary = Construction.check_tile(tile_id, building_id)
	if not bool(check.get("satisfied", true)):
		var missing: Dictionary = check.get("missing", {})
		q.missing = missing
		q.fee = maxf(0.0, base * charge - rebate)
		match material_source():
			"same_tile":
				if not held.is_empty():
					return _refuse(q, str(held[0]), str(held[1]))
				return _refuse(q, "Materials not here", "Its materials must be on this tile first.")
			"any_tile":
				var src: Dictionary = Construction.find_source_tile(tile_id, missing)
				if not held.is_empty() and src.is_empty():
					return _refuse(q, str(held[0]), str(held[1]))
				if src.is_empty():
					return _refuse(q, "Materials not here", "No tile has the spare materials to lay it here.")
				q.materials = "ship"
				q.materials_cost = float(TransportState.preview_move(str(src.get("tile_id", "")), tile_id, missing).get("cost", 0.0))
			"middleman":
				q.materials = "order"
				q.materials_cost = Construction.estimate_middleman_cost(tile_id, building_id) \
					if ResearchState.logistics_progression_active() else Construction.estimate_market_cost(tile_id, building_id)
			_:
				q.materials = "order"
				q.materials_cost = Construction.estimate_market_cost(tile_id, building_id)
	if not held.is_empty():
		return _refuse(q, str(held[0]), str(held[1]))
	q.total = float(q.fee) + float(q.land_cost) + float(q.materials_cost)
	q.affordable = MatchState.money >= float(q.total)
	return q


## Where a build's missing materials come from, as the map settles it at the press (without taking the
## one-off choice MatchState.consume_build_material_source would use up).
static func material_source() -> String:
	var src := MatchState.pending_build_material_source if MatchState.pending_build_material_source != "" else MatchState.construct_material_source
	if src == "ask" or src == "":
		src = "middleman"
	if ResearchState.logistics_progression_active():
		if src in ["same_tile", "any_tile"] and not ResearchState.open_logistics_contracts_available():
			src = "middleman"
		if src == "market" and not ResearchState.global_trade_license_available():
			src = "middleman"
	return src


## `q` refused for `refusal`: its total is what the build would cost once the reason is dealt with (the fee,
## with any land and materials already priced).
static func _refuse(q: Dictionary, refusal: String, why: String) -> Dictionary:
	q.ok = false
	q.refusal = refusal
	q.why = why
	q.total = float(q.fee) + float(q.land_cost) + float(q.materials_cost)
	q.affordable = true
	return q


## One of the world map's constants, read from its script so the rule isn't copied here.
static func _map_constant(key: String, fallback: Variant) -> Variant:
	var s := load("res://scripts/world_map.gd") as Script
	return s.get_script_constant_map().get(key, fallback) if s != null else fallback
