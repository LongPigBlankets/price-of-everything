extends Node

## Raised when a build is one turn out and its operational-loans tab opens — the construct
## panel listens and shows the choice. Emitted from the sim; the sim never opens a dialog.
signal building_tab_opened(instance_id: String)
# Owns construction projects — buildings that are awaiting materials or under construction
# before they become live entries in MatchState.buildings. Keeping them in a SEPARATE
# collection (not a status flag on MatchState.buildings) means every operational reader of
# MatchState.buildings (production, storage-boost, maintenance, metrics) stays correct with
# zero edits: a half-built building simply isn't in there yet.
#
# PHASE 2: the under_construction lifecycle is live. start_on_tile() consumes the materials
# and creates a project that counts down build_duration turns (ticked during PROCESS, before
# production). When the countdown reaches zero the project promotes into a real building.
# A project carries a stable instance_id from creation through promotion, so the hex visual,
# tile chart and (later) detail panel/cancellation all key off one id across the lifecycle.

signal construction_started(instance_id: String, tile_id: String)
signal construction_completed(instance_id: String, tile_id: String)
signal materials_ordered(instance_id: String, tile_id: String)
signal construction_materials_updated(instance_id: String, tile_id: String)
signal construction_cancelled(instance_id: String, tile_id: String)

const BuildingNaming := preload("res://scripts/building_naming.gd")
const STATUS_UNDER_CONSTRUCTION := "under_construction"
const STATUS_AWAITING_MATERIALS := "awaiting_materials"

var construction_projects: Dictionary = {}  # instance_id -> project dict


func _ready() -> void:
	# Clear pending projects on a new game / reset. MatchState is loaded before us.
	if MatchState.has_signal("state_reset"):
		MatchState.state_reset.connect(_on_state_reset)


func _on_state_reset() -> void:
	construction_projects.clear()


# --- Save/load (orchestrated by the SaveLoad autoload; docs/save_load_spec.md) ---

func export_state() -> Dictionary:
	return {"projects": construction_projects.duplicate(true)}

func import_state(d: Dictionary) -> void:
	construction_projects = (d.get("projects", {}) as Dictionary).duplicate(true)


# --- Requirements ---

# Construction materials for a building as {good_id: qty}. The Catalog stores build
# materials by internal name (build_material_N in the CSV); the Stockpile is keyed by
# good_id, so we resolve name -> good_id here once.
func requirements_for(building_id: String) -> Dictionary:
	var reqs: Dictionary = {}
	var building: Dictionary = Catalog.get_building(building_id)
	for mat in building.get("materials", []):
		var internal: String = str(mat.get("name", ""))
		var qty: int = int(mat.get("qty", 0))
		if internal == "" or qty <= 0:
			continue
		var good_id: String = str(Catalog.get_good_by_internal_name(internal).get("id", ""))
		if good_id == "":
			push_warning("[Construction] build material '%s' for %s has no matching good" % [internal, building_id])
			continue
		reqs[good_id] = int(reqs.get(good_id, 0)) + qty
	return reqs


## Cash-equivalent value of a building's material kit at this turn's market
## prices. It is deliberately not a tile-specific purchase quote: until the
## player picks a site, freight and density costs are unknown.
func market_value(building_id: String) -> float:
	var total := 0.0
	var requirements := requirements_for(building_id)
	for good_id in requirements:
		var unit_price := MarketState.get_price(str(good_id))
		if unit_price <= 0.0:
			unit_price = Catalog.get_base_price(str(good_id))
		total += float(int(requirements.get(good_id, 0))) * unit_price
	return total


## Cash value of buying the complete construction kit from the market this turn.
## Unlike market_value(), this uses the actual buy-side price (including the
## market spread). Freight/warehousing remains site-dependent until a tile is
## selected and is therefore called out separately by the confirm panel.
func market_purchase_value(building_id: String) -> float:
	var total := 0.0
	var requirements := requirements_for(building_id)
	for good_id in requirements:
		var unit_price := MarketState.get_buy_price(str(good_id))
		if unit_price <= 0.0:
			unit_price = Catalog.get_base_price(str(good_id))
		total += float(int(requirements.get(good_id, 0))) * unit_price
	return total


## Bill-of-materials ledger for the confirm screen (v3 spec §5): one row per
## required good stating what the site holds, what will be bought, and what stays
## short, plus a subtotal. The verdict strip's construction figure is base_price +
## this subtotal, so the two reconcile structurally — both read this one dict.
##
## Row fields:
##   good_id/name  the material
##   need          the kit requirement
##   have          stock on `tile_id` right now (0 when no tile is chosen yet)
##   from_stock    the part of `need` that stock covers — already owned, costs nothing
##   market_qty /  the part bought in, priced by the live buy preview when the tile
##   market_cost   is known (freight included) or the market buy price when it isn't
##   short         covered by nobody. Only under the "same_tile" material source,
##                 where a missing good blocks the build instead of being bought.
##   line_cost     what this line adds to the confirm total (= market_cost)
##   elsewhere     uncommitted surplus of this good on every OTHER tile — informational:
##                 what an "any_tile" switch could actually draw on, shown regardless
##                 of the active setting (v3.1 spec: On tile / Elsewhere / Market price).
##   market_price  reference estimate for buying the FULL need at today's buy price —
##                 always populated, unlike market_cost which is freight-inclusive
##                 and only covers the actual gap. Display-only; never summed.
##
## The "any_tile" source is deliberately priced as market here: which surplus tile
## would feed the build (and its freight) is only resolved by the delivery flow, so
## the market quote is the honest ceiling rather than a guess at a cheaper route.
func materials_ledger(building_id: String, tile_id: String) -> Dictionary:
	var rows: Array = []
	var subtotal := 0.0
	var same_tile_only := MatchState.construct_material_source == "same_tile"
	var requirements := requirements_for(building_id)
	for good_id in requirements:
		var need: int = int(requirements[good_id])
		var have: int = Stockpile.get_at_tile(tile_id, str(good_id)) if tile_id != "" else 0
		var from_stock: int = mini(have, need)
		var gap: int = need - from_stock
		var market_qty := 0
		var market_cost := 0.0
		var short := 0
		if gap > 0:
			if same_tile_only:
				short = gap
			else:
				market_qty = gap
				market_cost = _market_gap_cost(tile_id, str(good_id), gap)
		rows.append({
			"good_id": str(good_id),
			"name": Catalog.get_display_name(str(good_id)),
			"need": need, "have": have, "from_stock": from_stock,
			"market_qty": market_qty, "market_cost": market_cost,
			"short": short, "line_cost": market_cost,
			"elsewhere": network_surplus_for_good(str(good_id), tile_id),
			"market_price": _reference_market_price(str(good_id), need),
		})
		subtotal += market_cost
	return {"rows": rows, "subtotal": subtotal}


## Reference estimate for buying `need` units of one good at today's buy price —
## no freight, no tile awareness. A flat "what the market would charge" figure for
## the materials table, independent of what is actually being bought (market_cost).
func _reference_market_price(good_id: String, need: int) -> float:
	var unit_price := MarketState.get_buy_price(good_id)
	if unit_price <= 0.0:
		unit_price = Catalog.get_base_price(good_id)
	return float(need) * unit_price


## Uncommitted surplus of one good across every OTHER tile with stock — mirrors
## find_source_tile's per-tile spare formula (stock minus this turn's committed
## input use) but SUMS across every tile instead of stopping at the first one that
## alone covers the whole shortfall. Purely informational for the confirm screen;
## nothing here reserves or moves the goods.
func network_surplus_for_good(good_id: String, exclude_tile_id: String) -> int:
	var total := 0
	for tile_key in Stockpile.tiles_with_stock():
		var src := str(tile_key)
		if src == exclude_tile_id or not src.begins_with("tile_"):
			continue
		var committed: Dictionary = Production.compute_committed_for_tile(src)
		var spare: int = Stockpile.get_at_tile(src, good_id) - int(committed.get(good_id, 0))
		if spare > 0:
			total += spare
	return total


## Market cost of buying `qty` of one good for a build: the tile-aware buy preview
## (goods + freight) when a site is chosen, the plain buy price before one is.
func _market_gap_cost(tile_id: String, good_id: String, qty: int) -> float:
	if tile_id != "":
		var preview: Dictionary = MatchState.preview_buy(tile_id, good_id, qty)
		if not preview.is_empty():
			return float(preview.get("cost", 0.0))
	var unit_price := MarketState.get_buy_price(good_id)
	if unit_price <= 0.0:
		unit_price = Catalog.get_base_price(good_id)
	return float(qty) * unit_price


# Whether the target tile holds every required material, and what's short.
# Returns {satisfied: bool, missing: {good_id: qty_short}, required: {good_id: qty}}.
func check_tile(tile_id: String, building_id: String) -> Dictionary:
	var reqs: Dictionary = requirements_for(building_id)
	var missing: Dictionary = {}
	for good_id in reqs:
		var need: int = int(reqs[good_id])
		var have: int = Stockpile.get_at_tile(tile_id, good_id)
		if have < need:
			missing[good_id] = need - have
	return {"satisfied": missing.is_empty(), "missing": missing, "required": reqs}


# --- Build lifecycle ---

# Consume the construction materials from the tile and begin the build. The caller has
# already validated tile/recipe/space and deducted the money cost; check_tile() must have
# returned satisfied == true beforehand. Returns the project's (and future building's)
# stable instance_id. The building does NOT exist yet — it promotes after build_duration
# turns (or immediately if a building has no positive duration).
func start_on_tile(building_id: String, recipe_id: String, tile_id: String, build_cost: float = 0.0) -> String:
	var reqs: Dictionary = requirements_for(building_id)
	var output_destination := MatchState.construct_output_destination
	for good_id in reqs:
		Stockpile.consume(tile_id, good_id, int(reqs[good_id]))

	var building: Dictionary = Catalog.get_building(building_id)
	var duration: int = MatchState.effective_build_duration(building_id)
	var instance_id: String = MatchState.reserve_instance_id(building_id)

	if duration <= 0:
		# Degenerate (no construction time): complete at once, but still fire the lifecycle
		# signals so visuals/toasts follow the same path as a timed build.
		construction_started.emit(instance_id, tile_id)
		_complete_build(building_id, recipe_id, tile_id, instance_id,
			MatchState.construct_start_half_capacity and recipe_id != "", output_destination)
		construction_completed.emit(instance_id, tile_id)
		return instance_id

	construction_projects[instance_id] = {
		"instance_id": instance_id,
		"building_id": building_id,
		"recipe_id": recipe_id,
		"tile_id": tile_id,
		"status": STATUS_UNDER_CONSTRUCTION,
		"required_materials": reqs,
		"missing_materials": {},
		"turns_remaining": duration,
		"construction_duration": duration,
		"reserved_space": float(building.get("tile_size_used", 1)),
		"build_cost": build_cost,
		"startup_half_capacity": MatchState.construct_start_half_capacity and recipe_id != "",
		"output_destination": output_destination,
	}
	construction_projects[instance_id]["name"] = BuildingNaming.label_for_tile(tile_id, instance_id, building_id, recipe_id)
	construction_started.emit(instance_id, tile_id)
	return instance_id


# Total market cost (goods + transport) to buy the materials still missing on the tile.
# Used by the build flow to check affordability before committing to an awaiting project.
func estimate_market_cost(tile_id: String, building_id: String) -> float:
	var missing: Dictionary = check_tile(tile_id, building_id).get("missing", {})
	var total: float = 0.0
	for good_id in missing:
		var preview: Dictionary = MatchState.preview_buy(tile_id, good_id, int(missing[good_id]))
		total += float(preview.get("cost", 0.0))
	return total


# Begin a project whose materials aren't all on the tile: order the shortfall from the market
# (tagged to this project) and reserve the site. The caller has already deducted the build
# cost and confirmed affordability. The project sits in awaiting_materials until claim_materials
# secures every required good, then begins the build countdown. Returns the stable instance_id.
func start_awaiting_market(building_id: String, recipe_id: String, tile_id: String, build_cost: float = 0.0) -> String:
	var reqs: Dictionary = requirements_for(building_id)
	var missing: Dictionary = check_tile(tile_id, building_id).get("missing", {})
	var building: Dictionary = Catalog.get_building(building_id)
	var duration: int = MatchState.effective_build_duration(building_id)
	var instance_id: String = MatchState.reserve_instance_id(building_id)
	var output_destination := MatchState.construct_output_destination

	# Reserve the in-place portion of every material RIGHT NOW, so co-located production
	# buildings can't consume it before claim_materials runs. Only the shortfall is then
	# bought and remains to be claimed on arrival. (Previously the in-place goods were
	# left on the tile to be claimed "next PROCESS", which let production eat them first
	# and stalled the build.)
	for good_id in reqs:
		var on_tile_part: int = int(reqs[good_id]) - int(missing.get(good_id, 0))
		if on_tile_part > 0:
			Stockpile.consume(tile_id, good_id, on_tile_part)
	for good_id in missing:
		MatchState.queue_buy(tile_id, good_id, int(missing[good_id]), false, {"construction_instance_id": instance_id})

	construction_projects[instance_id] = {
		"instance_id": instance_id,
		"building_id": building_id,
		"recipe_id": recipe_id,
		"tile_id": tile_id,
		"status": STATUS_AWAITING_MATERIALS,
		"required_materials": reqs,
		"missing_materials": missing.duplicate(),  # only the ordered shortfall remains
		"turns_remaining": duration,
		"construction_duration": duration,
		"reserved_space": float(building.get("tile_size_used", 1)),
		"source": {"kind": "market"},  # re-ordered from market each turn until secured
		"build_cost": build_cost,
		"startup_half_capacity": MatchState.construct_start_half_capacity and recipe_id != "",
		"output_destination": output_destination,
	}
	construction_projects[instance_id]["name"] = BuildingNaming.label_for_tile(tile_id, instance_id, building_id, recipe_id)
	materials_ordered.emit(instance_id, tile_id)
	return instance_id


# Find the nearest single tile whose UNCOMMITTED surplus covers every missing material, so the
# player can source a build from their own spare stock instead of the market. Surplus on a tile
# is its stock minus what that tile's own buildings need for production. Returns {tile_id, turns}
# or {} if no single tile can cover the whole shortfall. (v1: single source tile only.)
func find_source_tile(dest_tile: String, missing: Dictionary) -> Dictionary:
	if missing.is_empty():
		return {}
	var best: Dictionary = {}
	var best_turns: int = 1 << 30
	for tile_key in Stockpile.tiles_with_stock():
		var src: String = str(tile_key)
		if src == dest_tile or not src.begins_with("tile_"):
			continue
		var committed: Dictionary = Production.compute_committed_for_tile(src)
		var covers: bool = true
		for good_id in missing:
			var spare: int = Stockpile.get_at_tile(src, str(good_id)) - int(committed.get(good_id, 0))
			if spare < int(missing[good_id]):
				covers = false
				break
		if not covers:
			continue
		var turns: int = int(TransportService.route(src, dest_tile).get("turns", 0))
		if turns < best_turns:
			best_turns = turns
			best = {"tile_id": src, "turns": turns}
	return best


# Begin an awaiting project sourced from another tile's spare stock: pull the shortfall from the
# source tile into tagged shipments to the build site (charging only transport). The caller has
# deducted the build cost and confirmed the source via find_source_tile. Returns the instance_id.
func start_awaiting_from_tile(building_id: String, recipe_id: String, dest_tile: String, source_tile: String, build_cost: float = 0.0) -> String:
	var reqs: Dictionary = requirements_for(building_id)
	var missing: Dictionary = check_tile(dest_tile, building_id).get("missing", {})
	var building: Dictionary = Catalog.get_building(building_id)
	var duration: int = MatchState.effective_build_duration(building_id)
	var instance_id: String = MatchState.reserve_instance_id(building_id)
	var output_destination := MatchState.construct_output_destination

	# Reserve the in-place portion now (see start_awaiting_market); only the shortfall is
	# moved in from the source tile and remains to be claimed.
	for good_id in reqs:
		var on_tile_part: int = int(reqs[good_id]) - int(missing.get(good_id, 0))
		if on_tile_part > 0:
			Stockpile.consume(dest_tile, good_id, on_tile_part)
	MatchState.queue_move(source_tile, dest_tile, missing, false, {"construction_instance_id": instance_id})

	construction_projects[instance_id] = {
		"instance_id": instance_id,
		"building_id": building_id,
		"recipe_id": recipe_id,
		"tile_id": dest_tile,
		"status": STATUS_AWAITING_MATERIALS,
		"required_materials": reqs,
		"missing_materials": missing.duplicate(),
		"turns_remaining": duration,
		"construction_duration": duration,
		"reserved_space": float(building.get("tile_size_used", 1)),
		"source": {"kind": "tile", "from_tile_id": source_tile},
		"build_cost": build_cost,
		"startup_half_capacity": MatchState.construct_start_half_capacity and recipe_id != "",
		"output_destination": output_destination,
	}
	construction_projects[instance_id]["name"] = BuildingNaming.label_for_tile(dest_tile, instance_id, building_id, recipe_id)
	materials_ordered.emit(instance_id, dest_tile)
	return instance_id


# Priority claim: before production/selling, each awaiting project consumes whatever of its
# required goods are sitting on its tile (arrived purchases or pre-existing stock), so the
# construction owns them ahead of every other system. A project whose materials are all
# secured transitions to under_construction and starts its countdown (next turn).
# Market-sourced awaiting projects re-order any still-missing materials every turn, so a
# build whose order failed at creation (e.g. the player was momentarily broke after paying
# the build cost) self-heals once cash is available — instead of stalling forever. Only the
# shortfall not already on the tile or inbound is ordered, to avoid double-buying.
func reorder_market_materials() -> void:
	for instance_id in construction_projects.keys():
		var project: Dictionary = construction_projects[instance_id]
		if str(project.get("status", "")) != STATUS_AWAITING_MATERIALS:
			continue
		if str(project.get("source", {}).get("kind", "")) != "market":
			continue
		var tile_id: String = str(project.get("tile_id", ""))
		for good_id in (project.get("missing_materials", {}) as Dictionary).keys():
			var need: int = int(project["missing_materials"][good_id])
			# Count ONLY this project's own in-transit freight against the
			# shortfall — NOT arbitrary inbound of the same good. A co-located
			# production building's imports (or another project's) are earmarked
			# for their own consumer: production already excludes our freight from
			# its pipeline (production._shipment_reserved_outside_input_pipeline),
			# so counting theirs here left builds permanently short whenever a
			# neighbour imported the same good — they'd never order (nor receive)
			# their own copy, and the countdown never started. On-tile stock is
			# NOT pre-counted because claim_materials (which runs just before this)
			# has already consumed everything available off the tile.
			var inbound: int = 0
			for shipment in MatchState.get_inbound_transport_shipments(tile_id, str(good_id)):
				if str(shipment.get("construction_instance_id", "")) == instance_id:
					inbound += int(shipment.get("qty", 0))
			# Our freight that arrived at a full tile waits in overflow-hold — it is
			# still ours and still coming; without counting it, a jammed tile makes
			# this loop re-buy the same materials every lead-cycle.
			for held in MatchState.get_overflow_shipments_for_tile(tile_id):
				if str(held.get("construction_instance_id", "")) == instance_id \
						and str(held.get("good_id", "")) == str(good_id):
					inbound += int(held.get("qty", 0))
			var shortfall: int = need - inbound
			if shortfall > 0:
				MatchState.queue_buy(tile_id, str(good_id), shortfall, false, {"construction_instance_id": instance_id})

## Union of the still-missing material bills of every AWAITING project on a tile.
## The sell-surplus reserve protects these, so a bill gathered over several turns
## survives on the tile until claim_materials takes it.
func missing_materials_for_tile(tile_id: String) -> Dictionary:
	var out: Dictionary = {}
	for instance_id in construction_projects:
		var project: Dictionary = construction_projects[instance_id]
		if str(project.get("status", "")) != STATUS_AWAITING_MATERIALS \
				or str(project.get("tile_id", "")) != tile_id:
			continue
		for good_id in project.get("missing_materials", {}):
			out[good_id] = int(out.get(good_id, 0)) + int(project["missing_materials"][good_id])
	return out

func claim_materials() -> void:
	for instance_id in construction_projects.keys():
		var project: Dictionary = construction_projects[instance_id]
		if str(project.get("status", "")) != STATUS_AWAITING_MATERIALS:
			continue
		var tile_id: String = str(project.get("tile_id", ""))
		var missing: Dictionary = project["missing_materials"]
		var changed: bool = false
		for good_id in missing.keys():
			var need: int = int(missing[good_id])
			var take: int = Stockpile.consume(tile_id, good_id, need)  # consume returns amount taken
			if take > 0:
				changed = true
				if take >= need:
					missing.erase(good_id)
				else:
					missing[good_id] = need - take
		if missing.is_empty():
			project["status"] = STATUS_UNDER_CONSTRUCTION
			project["turns_remaining"] = int(project.get("construction_duration", 0))
			construction_started.emit(instance_id, tile_id)
		elif changed:
			construction_materials_updated.emit(instance_id, tile_id)


# Cancel a project in either state. Refunds the full build cost, returns every material the
# project has already secured to its tile, and frees the reserved space. Materials still in
# transit are left to arrive as ordinary stockpile goods (with the project gone, claim_materials
# ignores them) — no transport surgery, no goods refund. Returns true if a project was cancelled.
func cancel(instance_id: String) -> bool:
	if not construction_projects.has(instance_id):
		return false
	var project: Dictionary = construction_projects[instance_id]
	var tile_id: String = str(project.get("tile_id", ""))

	var refund: float = float(project.get("build_cost", 0.0))
	if refund > 0.0:
		MatchState.add_money(refund)

	# Secured materials = required − still-missing; return them to the build tile.
	var required: Dictionary = project.get("required_materials", {})
	var missing: Dictionary = project.get("missing_materials", {})
	for good_id in required:
		var secured: int = int(required[good_id]) - int(missing.get(good_id, 0))
		if secured > 0:
			Stockpile.add(tile_id, str(good_id), secured)

	construction_projects.erase(instance_id)
	construction_cancelled.emit(instance_id, tile_id)
	return true


# --- ETA helpers (computed live from inbound shipments) ---

# Turns until a still-missing material reaches the tile (min over its inbound shipments).
# 0 means it's already there / arriving this turn. -1 means nothing inbound (unknown / on-tile).
func material_arrival_eta(tile_id: String, good_id: String) -> int:
	var best: int = -1
	for shipment in MatchState.get_inbound_transport_shipments(tile_id, good_id):
		var turns: int = int(shipment.get("turns_remaining", 0))
		if best < 0 or turns < best:
			best = turns
	return best


# Max arrival ETA across a project's still-missing materials (-1 if none are inbound).
func materials_eta(project: Dictionary) -> int:
	var tile_id: String = str(project.get("tile_id", ""))
	var worst: int = -1
	for good_id in project.get("missing_materials", {}):
		var eta: int = material_arrival_eta(tile_id, good_id)
		if eta > worst:
			worst = eta
	return worst


# Advance every under-construction project by one turn; promote those that reach zero.
# Called during PROCESS, after transport arrivals and BEFORE the production cascade, so a
# building that completes this turn is active in time to produce this turn (spec turn order).
# Returns the instance_ids completed this turn so Production can annotate failures without
# changing the turn order.
func tick_turn() -> Array:
	var completed: Array = []
	for instance_id in construction_projects.keys():
		var project: Dictionary = construction_projects[instance_id]
		if str(project.get("status", "")) != STATUS_UNDER_CONSTRUCTION:
			continue
		project["turns_remaining"] = int(project["turns_remaining"]) - 1
		# One turn out: its inputs are being ordered and the first money is about to move, so
		# this is where the operational-loans tab opens (spec §5.3). Needs a seated CFO —
		# without one there is nobody to arrange it and costs simply hit cash.
		# Infrastructure has no recipe to run, so there are no start-up running costs to carry —
		# offering the facility for a stretch of rail was simply wrong. Purchases never reach
		# here at all (they are not construction projects); they get seeded stock instead.
		if int(project["turns_remaining"]) == 1 and MatchState.can_open_building_tab() \
				and not Catalog.get_recipe(str(project.get("recipe_id", ""))).get("inputs", []).is_empty():
			if MatchState.open_building_tab(str(instance_id)):
				building_tab_opened.emit(str(instance_id))
		if int(project["turns_remaining"]) <= 0:
			completed.append(instance_id)
	for instance_id in completed:
		_promote(instance_id)
	return completed


# Decision-event hook: delay (+N) or accelerate (-N) an under-construction project.
# Clamped to at least 1 remaining turn — completion still happens via tick_turn so
# the promote-before-produce ordering is never bypassed.
func adjust_remaining(instance_id: String, delta_turns: int) -> bool:
	var project: Dictionary = construction_projects.get(instance_id, {})
	if project.is_empty() or str(project.get("status", "")) != STATUS_UNDER_CONSTRUCTION:
		return false
	project["turns_remaining"] = maxi(1, int(project["turns_remaining"]) + delta_turns)
	# Reuses the project-row refresh signal — panels re-read turns_remaining on it.
	construction_materials_updated.emit(instance_id, str(project.get("tile_id", "")))
	return true


func _promote(instance_id: String) -> void:
	var project: Dictionary = construction_projects[instance_id]
	construction_projects.erase(instance_id)
	_complete_build(
		str(project.get("building_id", "")),
		str(project.get("recipe_id", "")),
		str(project.get("tile_id", "")),
		instance_id,
		bool(project.get("startup_half_capacity", false)),
		str(project.get("output_destination", MatchState.construct_output_destination)),
	)
	# Carry the real paid build cost (money, density-aware) + the consumed material kit
	# onto the live instance, so MatchState.refund_cost can give an exact demolish refund.
	# These ride in MatchState.buildings, so save/load persists them for free.
	var inst: Dictionary = MatchState.buildings.get(instance_id, {})
	if not inst.is_empty():
		inst["build_cost"] = float(project.get("build_cost", 0.0))
		inst["build_materials"] = (project.get("required_materials", {}) as Dictionary).duplicate()
	construction_completed.emit(instance_id, str(project.get("tile_id", "")))


# Promotion seam: turn a (pending) construction into a live building, reusing the stable id.
func _complete_build(building_id: String, recipe_id: String, tile_id: String, instance_id: String, startup_half_capacity: bool = false, output_destination: String = "") -> String:
	var completed_id := MatchState.add_building(building_id, recipe_id, tile_id, MatchState.LOCAL_PLAYER, instance_id)
	if startup_half_capacity and MatchState.buildings.has(completed_id):
		MatchState.buildings[completed_id]["startup_half_capacity"] = true
	var destination := output_destination if output_destination in ["market", "same_tile"] else MatchState.construct_output_destination
	var recipe := Catalog.get_recipe(recipe_id)
	for output in recipe.get("outputs", []):
		var good_id := str(output.get("good_id", ""))
		if good_id == "":
			continue
		# Only DEFAULT the route — never overwrite one the player already chose. The instance
		# id is stable across the project -> building promotion, so a destination set while the
		# building was still under construction lives in output_stockpile_destinations already,
		# and this loop used to stomp it on completion. Wiring a furnace's output the moment you
		# queue it is the natural play, and the setting silently vanished turns later (it is
		# what made the e2e motor chain never route steel to its assembly tile).
		if MatchState.has_output_destination(completed_id, good_id):
			continue
		if destination == "same_tile":
			MatchState.set_output_stockpile_destination(completed_id, tile_id, good_id)
		else:
			MatchState.route_output_to_market(completed_id, good_id)
	return completed_id


# --- Queries ---

# Projects currently sitting on a tile (awaiting/under construction). Returns the live dicts.
func projects_on_tile(tile_id: String) -> Array:
	var result: Array = []
	for project in construction_projects.values():
		if str(project.get("tile_id", "")) == tile_id:
			result.append(project)
	return result


# Space held by not-yet-active projects on a tile. MatchState.get_tile_space_used() adds
# this so reservations count against tile capacity alongside live buildings.
func reserved_space_on_tile(tile_id: String) -> float:
	var total: float = 0.0
	for project in construction_projects.values():
		if str(project.get("tile_id", "")) == tile_id:
			total += float(project.get("reserved_space", 0.0))
	return total
