extends Node
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
	for good_id in reqs:
		Stockpile.consume(tile_id, good_id, int(reqs[good_id]))

	var building: Dictionary = Catalog.get_building(building_id)
	var duration: int = int(building.get("build_duration", 0))
	var instance_id: String = MatchState.reserve_instance_id(building_id)

	if duration <= 0:
		# Degenerate (no construction time): complete at once, but still fire the lifecycle
		# signals so visuals/toasts follow the same path as a timed build.
		construction_started.emit(instance_id, tile_id)
		_complete_build(building_id, recipe_id, tile_id, instance_id)
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
	var duration: int = int(building.get("build_duration", 0))
	var instance_id: String = MatchState.reserve_instance_id(building_id)

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
	var duration: int = int(building.get("build_duration", 0))
	var instance_id: String = MatchState.reserve_instance_id(building_id)

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
			var on_tile: int = Stockpile.get_at_tile(tile_id, str(good_id))
			var inbound: int = 0
			for shipment in MatchState.get_inbound_transport_shipments(tile_id, str(good_id)):
				inbound += int(shipment.get("qty", 0))
			var shortfall: int = need - on_tile - inbound
			if shortfall > 0:
				MatchState.queue_buy(tile_id, str(good_id), shortfall, false, {"construction_instance_id": instance_id})

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
func tick_turn() -> void:
	var completed: Array = []
	for instance_id in construction_projects.keys():
		var project: Dictionary = construction_projects[instance_id]
		if str(project.get("status", "")) != STATUS_UNDER_CONSTRUCTION:
			continue
		project["turns_remaining"] = int(project["turns_remaining"]) - 1
		if int(project["turns_remaining"]) <= 0:
			completed.append(instance_id)
	for instance_id in completed:
		_promote(instance_id)


func _promote(instance_id: String) -> void:
	var project: Dictionary = construction_projects[instance_id]
	construction_projects.erase(instance_id)
	_complete_build(
		str(project.get("building_id", "")),
		str(project.get("recipe_id", "")),
		str(project.get("tile_id", "")),
		instance_id,
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
func _complete_build(building_id: String, recipe_id: String, tile_id: String, instance_id: String) -> String:
	return MatchState.add_building(building_id, recipe_id, tile_id, MatchState.LOCAL_PLAYER, instance_id)


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
