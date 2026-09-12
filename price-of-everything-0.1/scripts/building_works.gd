extends Node
## BuildingWorks: the jobs a standing building can be put through — level upgrades (and the
## cash-only infrastructure upgrades that share their pending machinery), recipe retrofits,
## pause/mothball, queued demolition, and the refund rules those use. Extracted from
## MatchState on 2026-09-11; the save keys are unchanged and still live under the "match"
## section (MatchState.export_state merges export_fields(), import_state calls
## import_fields(), reset() calls reset()).
##
## Turn hooks: Production calls tick_upgrades() / tick_retrofits() / tick_demolish() at its
## fixed point in the PROCESS sub-phase order (see cnc-turn-pipeline-reference).
## Building instances themselves (add/remove, tile index, tile space) stay in MatchState;
## this autoload mutates them only through MatchState's dictionaries and API.

const BuildingLevels := preload("res://scripts/building_levels.gd")

# Demolish is a queued 1-turn job (mirrors upgrades/retrofits) before the building is removed.
const DEMOLISH_TURNS := 1
## Turns an upgrade may sit with NOTHING inbound before the shortfall is re-ordered.
## Generous on purpose: a genuinely slow haul must never trip it, and it resets on progress.
const UPGRADE_STALL_TURNS := 5
## Everything the upgrade dialog needs to render: cost (materials, sourcing, £), the
## benefit/cost deltas (cur→new per aspect), the research gate, footprint fit and the
## 3-turn duration. Read-only — commits nothing. Returns {ok:false, reason} when there's
## no building or it's already maxed.
## Infrastructure whose per-tile level can be upgraded for cash (slot key == building
## internal_name for all five). Port/airport are not levellable.
const INFRA_UPGRADABLE: Array = ["roads", "rails", "pipes", "reinf_pipes", "cables"]
const UPGRADE_STATUS_AWAITING := "awaiting_materials"
const UPGRADE_STATUS_UPGRADING := "upgrading"

signal building_upgraded(instance_id: String, new_level: int)
# An upgrade was just queued (materials committed); the level changes later via building_upgraded.
signal building_upgrade_started(instance_id: String, target_level: int)
signal building_retrofit_started(instance_id: String, new_recipe_id: String)
signal building_retrofitted(instance_id: String, new_recipe_id: String)
# Demolish queued (1-turn countdown starts) / completed (materials refunded, building removed).
signal building_demolish_started(instance_id: String)
signal building_demolished(instance_id: String)
signal building_paused_changed(instance_id: String)
# An in-progress upgrade advanced (claimed materials / ticked down) — UI can refresh its countdown.
signal building_upgrade_progress(instance_id: String)
# An in-progress upgrade was cancelled / abandoned (e.g. the building was removed). Banked
# materials already on the tile are refunded; goods still in transit are not.
signal building_upgrade_cancelled(instance_id: String)

# In-progress building upgrades (mirrors Construction's project queue). Each entry is a
# dict — see start_upgrade() for the shape. While an upgrade is pending it reserves its
# extra footprint and the building keeps producing at its CURRENT level until promotion.
var pending_upgrades: Array = []
# In-progress retrofits (recipe changes): {instance_id, from_recipe, to_recipe,
# turns_remaining, labour_fraction}. The building produces nothing while retooling.
var pending_retrofits: Array = []
# In-progress demolitions: instance_id -> {turns_left, tile_id}. Completes in tick_demolish
# (materials refund + remove_building). Additive save state (default {} — no version bump).
var demolish_queue: Dictionary = {}
# Player-paused (mothballed) buildings: instance_id -> true. Skipped by production +
# labour; additive save state (default {} — no version bump).
var paused_buildings: Dictionary = {}


## Match-scoped: cleared by MatchState.reset() (new game / scenario start).
func reset() -> void:

	pending_upgrades.clear()
	pending_retrofits.clear()
	demolish_queue.clear()
	paused_buildings.clear()


## Saved under MatchState's "match" section (keys unchanged from before the extraction).
func export_fields() -> Dictionary:
	return {
		"pending_upgrades": pending_upgrades.duplicate(true),
		"pending_retrofits": pending_retrofits.duplicate(true),
		"demolish_queue": demolish_queue.duplicate(true),
		"paused_buildings": paused_buildings.duplicate(true),
	}


func import_fields(d: Dictionary) -> void:
	pending_upgrades = (d.get("pending_upgrades", []) as Array).duplicate(true)
	pending_retrofits = (d.get("pending_retrofits", []) as Array).duplicate(true)
	demolish_queue = (d.get("demolish_queue", {}) as Dictionary).duplicate(true)
	paused_buildings = (d.get("paused_buildings", {}) as Dictionary).duplicate(true)

# Total materials needed to take `internal` to `target`, resolved to {good_id: qty}.
func _upgrade_need_by_gid(internal: String, target: int) -> Dictionary:
	var need_by_gid: Dictionary = {}
	for gi in BuildingLevels.upgrade_materials(internal, target):
		var gid := str(Catalog.get_good_by_internal_name(str(gi)).get("id", ""))
		if gid != "":
			need_by_gid[gid] = int(BuildingLevels.upgrade_materials(internal, target)[gi])
	return need_by_gid

# Extra tile footprint a building takes when it grows from `from_level` to `target`.
## One sentence saying which gate refused the upgrade and what it would take to pass it.
## Empty when the building fits.
func _fits_reason(tile_id: String, delta: float, fits_physical: bool, fits_owned: bool) -> String:
	if fits_physical and fits_owned:
		return ""
	if not fits_physical:
		var free := float(BuildingState.max_tile_land(tile_id)) - BuildingState.get_tile_space_used(tile_id)
		return ("The larger building needs %s more space than this tile has. It grows by %s, and only %s is free of the tile's %s."
			% [_land(delta - free), _land(delta), _land(free), _land(float(BuildingState.max_tile_land(tile_id)))])
	var free_owned := BuildingState.get_tile_land_owned(tile_id) - BuildingState.get_tile_player_space_used(tile_id)
	return ("You do not own enough of this tile. The upgrade needs %s and only %s of your %s is free — buy land to make room."
		% [_land(delta), _land(free_owned), _land(BuildingState.get_tile_land_owned(tile_id))])

## Land figures read as whole units unless the fraction matters.
func _land(v: float) -> String:
	return str(int(round(v))) if absf(v - round(v)) < 0.05 else "%.1f" % v

func _upgrade_size_delta(building_id: String, from_level: int, target: int) -> float:
	var base_size := float(Catalog.get_building(building_id).get("tile_size_used", 1.0))
	return base_size * (BuildingLevels.mult("size", target) - BuildingLevels.mult("size", from_level))

func is_upgrading(instance_id: String) -> bool:
	for p in pending_upgrades:
		if str(p.get("instance_id", "")) == instance_id:
			return true
	return false

func is_retooling(instance_id: String) -> bool:
	for p in pending_retrofits:
		if str(p.get("instance_id", "")) == instance_id:
			return true
	return false

func retrofit_turns_remaining(instance_id: String) -> int:
	for p in pending_retrofits:
		if str(p.get("instance_id", "")) == instance_id:
			return int(p.get("turns_remaining", 0))
	return 0

# Per-turn labour fraction while a building is retooling (1.0 if it isn't).
func retooling_labour_fraction(instance_id: String) -> float:
	for p in pending_retrofits:
		if str(p.get("instance_id", "")) == instance_id:
			return float(p.get("labour_fraction", 1.0))
	return 1.0

# Retrofit cost/speed tier from the seated COO's Operations stat (base if no COO).
func retrofit_cost_tier() -> Dictionary:
	var a: Dictionary = AdvisorState._roster_entry(str(AdvisorState.advisor_seats.get("coo", "")))
	var key := "base"
	if not a.is_empty():
		key = "ops%d" % clampi(int(a.get("ops", 1)), 1, 3)
	return EconomyConfig.RETROFIT_TIERS.get(key, EconomyConfig.RETROFIT_TIERS["base"])

# Begin changing a built building's recipe. Charges the one-off fee up front; the
# building produces nothing (reduced labour) until the countdown completes.
func start_retrofit(instance_id: String, new_recipe_id: String) -> Dictionary:
	if not BuildingState.buildings.has(instance_id):
		return {"ok": false, "reason": "No such building."}
	if is_retooling(instance_id):
		return {"ok": false, "reason": "Already retooling."}
	if is_upgrading(instance_id):
		return {"ok": false, "reason": "An upgrade is in progress."}
	var inst: Dictionary = BuildingState.buildings[instance_id]
	var new_recipe: Dictionary = Catalog.get_recipe(new_recipe_id)
	if new_recipe.is_empty() or str(new_recipe.get("building_id", "")) != str(inst.get("building_id", "")):
		return {"ok": false, "reason": "That recipe can't run in this building."}
	if not Catalog.is_recipe_demo_available(new_recipe):
		return {"ok": false, "reason": "Recycling is not available in the demo."}
	if new_recipe_id == str(inst.get("recipe_id", "")):
		return {"ok": false, "reason": "Already running that recipe."}
	var tier: Dictionary = retrofit_cost_tier()
	if not MatchState.deduct_money(float(tier.get("fee", 0.0))):
		return {"ok": false, "reason": "Not enough money for the retooling fee."}
	pending_retrofits.append({
		"instance_id": instance_id,
		"from_recipe": str(inst.get("recipe_id", "")),
		"to_recipe": new_recipe_id,
		"turns_remaining": int(tier.get("turns", 2)),
		"labour_fraction": float(tier.get("labour", 0.5)),
	})
	AdvisorState.flag_agenda_event(AdvisorState.AGENDA_CHANGED_RECIPE)
	building_retrofit_started.emit(instance_id, new_recipe_id)
	return {"ok": true, "turns": int(tier.get("turns", 2)), "fee": float(tier.get("fee", 0.0))}

# Advance every retrofit one turn; on completion swap the recipe. Returns completed ids.
func tick_retrofits() -> Array:
	var completed: Array = []
	var remaining: Array = []
	for p in pending_retrofits:
		var iid := str(p.get("instance_id", ""))
		if not BuildingState.buildings.has(iid):
			continue   # building vanished mid-retool
		p["turns_remaining"] = int(p.get("turns_remaining", 0)) - 1
		if int(p["turns_remaining"]) <= 0:
			BuildingState.buildings[iid]["recipe_id"] = str(p.get("to_recipe", ""))
			completed.append(iid)
			building_retrofitted.emit(iid, str(p.get("to_recipe", "")))
		else:
			remaining.append(p)
	pending_retrofits = remaining
	return completed

# Abandon a retrofit; the building resumes its original recipe (fee not refunded).
func cancel_retrofit(instance_id: String) -> bool:
	var kept: Array = []
	var found := false
	for p in pending_retrofits:
		if str(p.get("instance_id", "")) == instance_id:
			found = true
		else:
			kept.append(p)
	pending_retrofits = kept
	if found:
		building_retrofit_started.emit(instance_id, "")   # UI refresh
	return found

func pending_upgrade(instance_id: String) -> Dictionary:
	for p in pending_upgrades:
		if str(p.get("instance_id", "")) == instance_id:
			return p
	return {}

## Read-only progress snapshot for an upgrade button / diagnostics row. `turns_remaining`
## alone is not an ETA while a project is awaiting materials: the three-turn build countdown
## does not start until every outstanding unit has arrived and been claimed. This folds in the
## tagged shipments and overflow queue, and reports why no finite estimate can be made.
func upgrade_progress_snapshot(instance_id: String) -> Dictionary:
	var pending := pending_upgrade(instance_id)
	if pending.is_empty():
		return {}
	var countdown := maxi(0, int(pending.get("turns_remaining", 0)))
	var status := str(pending.get("status", ""))
	if status == UPGRADE_STATUS_UPGRADING:
		return {
			"status": status, "blocked": false, "estimated_turns": countdown,
			"tooltip": "Estimated completion: %d turn%s." % [countdown, "" if countdown == 1 else "s"],
		}
	if status != UPGRADE_STATUS_AWAITING:
		var unknown := "The upgrade has an unknown progress state ('%s')." % status
		return {
			"status": status, "blocked": true, "estimated_turns": -1,
			"error": unknown,
			"tooltip": "Upgrade paused — estimated completion unavailable.\n%s" % unknown,
		}

	var tile_id := str(pending.get("tile_id", ""))
	var missing: Dictionary = pending.get("missing", {})
	var blockers: Array = []
	var material_eta := 1  # even on-tile goods are claimed on the next processed turn
	var overflow_qty := 0
	for gid_value in missing:
		var gid := str(gid_value)
		var needed := maxi(0, int(missing[gid_value]))
		if needed <= 0:
			continue
		var accounted := mini(needed, Stockpile.get_at_tile(tile_id, gid))
		var latest_eta := 0
		for shipment in TransportState.pending_transport_shipments:
			if str((shipment as Dictionary).get("upgrade_instance_id", "")) != instance_id \
					or str((shipment as Dictionary).get("destination_tile", "")) != tile_id \
					or str((shipment as Dictionary).get("good_id", "")) != gid:
				continue
			var enroute_take := mini(maxi(0, needed - accounted), int((shipment as Dictionary).get("qty", 0)))
			accounted += enroute_take
			if enroute_take > 0:
				latest_eta = maxi(latest_eta, int((shipment as Dictionary).get("turns_remaining", 0)))
		for overflow in TransportState.overflow_shipments:
			if str((overflow as Dictionary).get("upgrade_instance_id", "")) != instance_id \
					or str((overflow as Dictionary).get("destination_tile", "")) != tile_id \
					or str((overflow as Dictionary).get("good_id", "")) != gid:
				continue
			var held := mini(maxi(0, needed - accounted), int((overflow as Dictionary).get("qty", 0)))
			accounted += held
			overflow_qty += held
			if held > 0:
				latest_eta = maxi(latest_eta, 1)
		material_eta = maxi(material_eta, latest_eta)
		if accounted >= needed:
			continue
		var short := needed - accounted
		var good_name := Catalog.get_display_name(gid)
		var quote := TransportService.quote_market_buy(tile_id, gid, short, TransportState.seaport_would_cover(gid))
		if quote.is_empty():
			blockers.append("No road, rail or suitable pipe route can deliver %s to this tile." % good_name)
		else:
			blockers.append("No shipment is carrying the remaining %d %s." % [short, good_name])

	if overflow_qty > Stockpile.get_free_capacity(tile_id):
		blockers.append("The tile stockpile is too full to unload the remaining upgrade materials.")

	if not blockers.is_empty():
		var error := " ".join(blockers)
		return {
			"status": status, "blocked": true, "estimated_turns": -1,
			"error": error,
			"tooltip": "Upgrade paused — estimated completion unavailable.\n%s" % error,
		}
	var estimated := material_eta + countdown
	var waiting_text := "Materials are on their way." if material_eta > 1 else "Materials will be claimed next turn."
	return {
		"status": status, "blocked": false, "estimated_turns": estimated,
		"tooltip": "%s Estimated completion: %d turn%s." % [waiting_text, estimated, "" if estimated == 1 else "s"],
	}

# Footprint reserved on a tile by upgrades-in-progress (so a second build can't slip into
# room the growing building is about to claim). Counted by get_tile_space_used.
func reserved_upgrade_space_on_tile(tile_id: String) -> float:
	var total := 0.0
	for p in pending_upgrades:
		if str(p.get("tile_id", "")) == tile_id:
			total += float(p.get("size_delta", 0.0))
	return total

## Tile-seeded infrastructure (CSV cables/rails and the baked road network) has no
## MatchState building instance. TileViewData gives those slots a stable synthetic id
## (`tile_<tile_id>_<slot>`) so the shared building-detail upgrade UI can still address
## them. Resolve that id back to the tile + canonical slot, but only while the slot is
## actually installed on the live HexMap tile.
func _tile_backed_infra_instance(upgrade_id: String) -> Dictionary:
	if not upgrade_id.begins_with("tile_"):
		return {}
	for slot_value in INFRA_UPGRADABLE:
		var slot := str(slot_value)
		var suffix := "_" + slot
		if not upgrade_id.ends_with(suffix):
			continue
		var tile_id := upgrade_id.substr(5, upgrade_id.length() - 5 - suffix.length())
		if tile_id == "" or not _tile_has_infrastructure_slot(tile_id, slot):
			continue
		var building: Dictionary = Catalog.get_building_by_internal_name(slot)
		if building.is_empty():
			return {}
		return {
			"instance_id": upgrade_id,
			"building_id": str(building.get("id", "")),
			"tile_id": tile_id,
			"owner": "tile_data",
		}
	return {}

func _tile_has_infrastructure_slot(tile_id: String, slot: String) -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	var hm = tree.get_first_node_in_group("hex_map")
	if hm == null:
		return false
	var coord = hm.id_to_coord(tile_id)
	if not hm.tiles.has(coord):
		return false
	for present_value in (hm.tiles[coord] as Dictionary).get("infrastructure_present", []):
		var present := str(present_value).strip_edges().to_lower()
		if present in ["rail", "railway", "railways"]:
			present = "rails"
		elif present in ["pipework", "pipeworks"]:
			present = "pipes"
		elif present in ["reinforced_pipes", "reinforced pipework"]:
			present = "reinf_pipes"
		if present == slot:
			return true
	return false

## The tile-level a levellable infra instance sits at (the TILE dict is the gameplay
## source of truth — power caps and transport capacity read it, not the instance).
func infra_tile_level(inst: Dictionary) -> int:
	var internal := str(Catalog.get_building(str(inst.get("building_id", ""))).get("internal_name", ""))
	return TransportState._tile_infra_level(str(inst.get("tile_id", "")), "rail" if internal == "rails" else internal)

## Write an infra slot's level on the HexMap tile (persisted via the save's structured
## infrastructure snapshot). No-ops headless (no map), like the reads.
func set_tile_infra_level(tile_id: String, slot_key: String, level: int) -> void:
	# Mirror into the router FIRST and unconditionally: a level changes how far one turn-move
	# reaches (EconomyConfig.INFRA_RANGE_BY_LEVEL), and Catalog cannot read the HexMap tile —
	# it routes headless. Doing it before the early-outs below means a headless caller still
	# gets correct routing even with no map node in the tree.
	Catalog.set_tile_infra_level(tile_id, slot_key, level)
	var tree := get_tree()
	if tree == null:
		return
	var hm = tree.get_first_node_in_group("hex_map")
	if hm == null:
		return
	var coord = hm.id_to_coord(tile_id)
	if not hm.tiles.has(coord):
		return
	var tile: Dictionary = hm.tiles[coord]
	var levels: Dictionary = tile.get("infrastructure_levels", {})
	levels[slot_key] = level
	tile["infrastructure_levels"] = levels
	hm.tiles[coord] = tile

# Cash-only infra upgrade quote (£150 → L2, £350 → L3; no materials, no
# research). Capacity deltas come from the live cap tables so the sheet shows the truth.
func _preview_infra_upgrade(inst: Dictionary, internal: String) -> Dictionary:
	var instance_id := str(inst.get("instance_id", ""))
	var building_name := str(Catalog.get_building(str(inst.get("building_id", ""))).get("display_name", internal))
	var level := infra_tile_level(inst)
	if level >= BuildingLevels.MAX_LEVEL:
		return {"ok": true, "at_max": true, "infra": true, "building_name": building_name, "from_level": level}
	var target := level + 1
	var cost := float(EconomyConfig.INFRA_UPGRADE_CASH_COST.get(target, 0.0))
	var pend := pending_upgrade(instance_id)
	return {
		"ok": true, "at_max": false, "infra": true,
		"building_name": building_name,
		"from_level": level, "target_level": target,
		"duration": BuildingLevels.UPGRADE_DURATION,
		"cash_cost": cost, "affordable": MatchState.money >= cost,
		"capacity": _infra_capacity_delta(internal, level, target),
		"research_gate": "", "research_locked": false,
		"materials": [], "all_on_tile": true, "market_sourceable": true,
		"source_tile": "", "source_turns": 0, "market_cost": 0.0, "fits": true,
		"already_upgrading": not pend.is_empty(),
		"pending_turns_left": int(pend.get("turns_remaining", 0)),
		"pending_status": str(pend.get("status", "")),
		"stats": {}, "unit_cost": {},
	}

## Goods sitting on a tile that some OTHER pending job has already claimed.
##
## An awaiting project keeps the part of its kit it has already gathered IN THE TILE
## STOCKPILE -- the sell-surplus reserve protects it there until `claim_materials` takes it
## (construction.gd's own note says so) -- and an awaiting upgrade does the same. So a raw
## `Stockpile.get_at_tile` reading counts goods that are spoken for, and a second job started
## against them would find them gone. What is gathered is the full bill minus what is still
## missing, which is exactly what both records carry.
##
## `except_instance_id` drops one job's own claim, so previewing a job does not reserve
## against itself.
func reserved_materials_on_tile(tile_id: String, except_instance_id: String = "") -> Dictionary:
	var out: Dictionary = {}
	for instance_id in Construction.construction_projects:
		var project: Dictionary = Construction.construction_projects[instance_id]
		if str(project.get("tile_id", "")) != tile_id:
			continue
		if str(instance_id) == except_instance_id:
			continue
		if str(project.get("status", "")) != Construction.STATUS_AWAITING_MATERIALS:
			continue
		var missing: Dictionary = project.get("missing_materials", {})
		for gid in project.get("required_materials", {}):
			var gathered: int = maxi(int(project["required_materials"][gid])
				- int(missing.get(gid, 0)), 0)
			if gathered > 0:
				out[gid] = int(out.get(gid, 0)) + gathered
	for pending_value in pending_upgrades:
		var pending: Dictionary = pending_value
		if str(pending.get("tile_id", "")) != tile_id:
			continue
		if str(pending.get("instance_id", "")) == except_instance_id:
			continue
		if str(pending.get("status", "")) != UPGRADE_STATUS_AWAITING:
			continue
		var short: Dictionary = pending.get("missing", {})
		for gid in pending.get("materials", {}):
			var banked: int = maxi(int(pending["materials"][gid]) - int(short.get(gid, 0)), 0)
			if banked > 0:
				out[gid] = int(out.get(gid, 0)) + banked
	return out

func _infra_capacity_delta(internal: String, level: int, target: int) -> Dictionary:
	if internal == "cables":
		return {"label": "Power capacity", "unit": "power/turn",
			"cur": float(EconomyConfig.CABLE_POWER_CAP.get(level, 0)),
			"new": float(EconomyConfig.CABLE_POWER_CAP.get(target, 0))}
	var mode := "rail" if internal == "rails" else internal
	return {"label": "Transport capacity", "unit": "units/turn",
		"cur": TransportState.tile_mode_capacity(mode, level),
		"new": TransportState.tile_mode_capacity(mode, target)}

func preview_upgrade(instance_id: String) -> Dictionary:
	if not BuildingState.buildings.has(instance_id):
		var tile_infra := _tile_backed_infra_instance(instance_id)
		if tile_infra.is_empty():
			return {"ok": false, "reason": "No such building."}
		var tile_internal := str(Catalog.get_building(str(tile_infra.get("building_id", ""))).get("internal_name", ""))
		return _preview_infra_upgrade(tile_infra, tile_internal)
	var inst: Dictionary = BuildingState.buildings[instance_id]
	var level := int(inst.get("level", 1))
	var building_id := str(inst.get("building_id", ""))
	var building_name := str(Catalog.get_building(building_id).get("display_name", building_id))
	var infra_internal := str(Catalog.get_building(building_id).get("internal_name", ""))
	if INFRA_UPGRADABLE.has(infra_internal):
		return _preview_infra_upgrade(inst, infra_internal)
	if level >= BuildingLevels.MAX_LEVEL:
		return {"ok": true, "at_max": true, "building_name": building_name, "from_level": level}
	var target := level + 1
	var internal := str(Catalog.get_building(building_id).get("internal_name", ""))
	var tile_id := str(inst.get("tile_id", ""))

	# Materials — needed / on-tile / shortfall, and the £ to buy the shortfall.
	var need_by_gid := _upgrade_need_by_gid(internal, target)
	var materials: Array = []
	var shortfall: Dictionary = {}
	var market_cost := 0.0
	var market_sourceable := true  # false if any shortfall good has no port route to this tile
	# What another awaiting job on this tile has already banked is on the tile but not
	# available -- see reserved_materials_on_tile.
	var claimed := reserved_materials_on_tile(tile_id, instance_id)
	var all_free := true
	for gid in need_by_gid:
		var need := int(need_by_gid[gid])
		var have := Stockpile.get_at_tile(tile_id, gid)
		var free := maxi(have - int(claimed.get(gid, 0)), 0)
		if free < need:
			all_free = false
		var short := maxi(0, need - have)
		if short > 0:
			shortfall[gid] = short
			var quote: Dictionary = MatchState.preview_buy(tile_id, gid, short)
			if quote.is_empty():
				market_sourceable = false
			else:
				market_cost += float(quote.get("cost", 0.0))
		materials.append({
			"good_id": gid, "name": Catalog.get_display_name(gid),
			"need": need, "have": have, "short": short, "free": free,
		})
	var all_on_tile := shortfall.is_empty()
	# The kit is usable off the tile only when every good is there AND unclaimed.
	var all_on_tile_free := all_on_tile and all_free

	# A single other tile that can cover the whole shortfall (powers the "use stockpile" CTA).
	var source := Construction.find_source_tile(tile_id, shortfall) if not all_on_tile else {}

	# Footprint check (the larger building must still fit, counting other pending upgrades).
	# Physical room uses everything on the tile; the owned-land gate only counts the
	# player's own estate (NPC buildings sit on their own land).
	var delta := _upgrade_size_delta(building_id, level, target)
	var projected := BuildingState.get_tile_space_used(tile_id) + delta
	var projected_player := BuildingState.get_tile_player_space_used(tile_id) + delta
	var fits_physical: bool = projected <= float(BuildingState.max_tile_land(tile_id))
	var fits_owned: bool = projected_player <= float(BuildingState.get_tile_land_owned(tile_id))
	var fits: bool = fits_physical and fits_owned

	var gate := BuildingLevels.research_gate(internal, target)
	var pend := pending_upgrade(instance_id)
	return {
		"ok": true,
		"at_max": false,
		"building_name": building_name,
		"from_level": level,
		"target_level": target,
		"duration": BuildingLevels.UPGRADE_DURATION,
		"research_gate": gate,
		"research_locked": gate != "" and not ResearchState.is_unlocked(gate),
		"materials": materials,
		"all_on_tile": all_on_tile,
		"all_on_tile_free": all_on_tile_free,
		"market_sourceable": market_sourceable,
		"source_tile": str(source.get("tile_id", "")),
		"source_turns": int(source.get("turns", 0)),
		"market_cost": market_cost,
		"fits": fits,
		# WHY it does not fit, and by how much. "Not enough room" over a tile panel reading
		# "122 owned" reads as a bug: the binding limit is usually the tile's PHYSICAL space,
		# which counts the NPC buildings sitting on it, not the land the player owns.
		"fits_reason": _fits_reason(tile_id, delta, fits_physical, fits_owned),
		"size_delta": delta,
		"already_upgrading": not pend.is_empty(),
		"pending_turns_left": int(pend.get("turns_remaining", 0)),
		"pending_status": str(pend.get("status", "")),
		"stats": _upgrade_stat_deltas(instance_id, level, target),
		"unit_cost": _upgrade_cost_per_unit(instance_id, level, target),
	}

# cur→new for every aspect the dialog shows, computed via the live engine at each level.
func _upgrade_stat_deltas(instance_id: String, level: int, target: int) -> Dictionary:
	var cur: Dictionary = Production.stats_at_level(instance_id, level)
	var new_s: Dictionary = Production.stats_at_level(instance_id, target)
	return {"cur": cur, "new": new_s}

## Production cost per unit of (primary) output at the current vs target level, matching the
## live CostSolver model: gross = input materials + power + labour + maintenance + inbound transport,
## per unit = allocated to the primary output. Components scale by their per-level multipliers
## (inputs/transport ×input, power ×energy, labour ×labour, maintenance ×maint) while output ×output;
## the market-value allocation fraction is level-independent so it cancels. Returns {cur,new} or {}.
func _upgrade_cost_per_unit(instance_id: String, from_level: int, target: int) -> Dictionary:
	if not BuildingState.buildings.has(instance_id):
		return {}
	var input_cost := 0.0
	var power_cost := 0.0
	var labour := 0.0
	var maint := 0.0
	var transport := 0.0
	var primary_qty := 0.0
	var unit_cur := -1.0
	# Prefer the live CostSolver breakdown (real input prices, transport, modifiers).
	var cs: Dictionary = (CostSolver.last_result.get("per_building", {}) as Dictionary).get(instance_id, {})
	if not cs.is_empty():
		input_cost = float(cs.get("input_material_cost", 0.0))
		power_cost = float(cs.get("power_cost", 0.0))
		labour = float(cs.get("labour_cost", 0.0))
		maint = float(cs.get("maintenance_cost", 0.0))
		transport = float(cs.get("inbound_transport", 0.0))
		primary_qty = float(cs.get("output_qty", 0.0))
		unit_cur = float(cs.get("unit_cost", -1.0))
	else:
		# Fallback (building hasn't produced yet): build it from the current-level stats.
		var cur: Dictionary = Production.stats_at_level(instance_id, from_level)
		if cur.is_empty():
			return {}
		for inp in cur.get("inputs", []):
			input_cost += MarketState.get_price(str(inp.get("good_id", ""))) * float(inp.get("qty", 0))
		power_cost = float(cur.get("energy", 0.0)) * EconomyConfig.GRID_BUY_PRICE
		labour = float(cur.get("labour", 0.0))
		maint = float(cur.get("maintenance", 0.0))
		var outs: Array = cur.get("outputs", [])
		primary_qty = float(outs[0].get("qty", 0)) if outs.size() > 0 else 0.0
	var total_cur := input_cost + power_cost + labour + maint + transport
	if primary_qty <= 0.0 or total_cur <= 0.0:
		return {}
	if unit_cur < 0.0:
		unit_cur = total_cur / primary_qty
	# Component ratios from the CURRENT level to the target level.
	var ri := BuildingLevels.mult("input", target) / BuildingLevels.mult("input", from_level)
	var re := BuildingLevels.mult("energy", target) / BuildingLevels.mult("energy", from_level)
	var rl := BuildingLevels.mult("labour", target) / BuildingLevels.mult("labour", from_level)
	var rm := BuildingLevels.mult("maint", target) / BuildingLevels.mult("maint", from_level)
	var ro := BuildingLevels.mult("output", target) / BuildingLevels.mult("output", from_level)
	var total_new := input_cost * ri + power_cost * re + labour * rl + maint * rm + transport * ri
	var unit_new := unit_cur * (total_new / total_cur) / ro
	return {"cur": unit_cur, "new": unit_new}

## Begin a 3-turn upgrade. `mode` decides where the shortfall comes from:
##   "tile"     — every material is already on the tile (consumed now, countdown starts).
##   "market"   — buy the shortfall from the nearest port (cost charged now via queue_buy).
##   "transfer" — move the shortfall in from another tile (source picked by find_source_tile).
## The on-tile portion is always consumed immediately so production can't eat it; the
## countdown only begins once every material has been claimed. Returns {ok, reason, status}.
func start_upgrade(instance_id: String, mode: String = "tile") -> Dictionary:
	if not BuildingState.buildings.has(instance_id):
		var tile_infra := _tile_backed_infra_instance(instance_id)
		if tile_infra.is_empty():
			return {"ok": false, "reason": "No such building."}
		if is_upgrading(instance_id):
			return {"ok": false, "reason": "An upgrade is already in progress."}
		var tile_internal := str(Catalog.get_building(str(tile_infra.get("building_id", ""))).get("internal_name", ""))
		return _start_infra_upgrade(instance_id, tile_infra, tile_internal)
	if is_upgrading(instance_id):
		return {"ok": false, "reason": "An upgrade is already in progress."}
	var inst: Dictionary = BuildingState.buildings[instance_id]
	# Levellable infrastructure: cash-only, no materials/research, level read from and
	# (at completion) written back to the TILE — the gameplay source of truth.
	var infra_internal := str(Catalog.get_building(str(inst.get("building_id", ""))).get("internal_name", ""))
	if INFRA_UPGRADABLE.has(infra_internal):
		return _start_infra_upgrade(instance_id, inst, infra_internal)
	var level := int(inst.get("level", 1))
	if level >= BuildingLevels.MAX_LEVEL:
		return {"ok": false, "reason": "Already at the maximum level."}
	var target := level + 1
	var building_id := str(inst.get("building_id", ""))
	var internal := str(Catalog.get_building(building_id).get("internal_name", ""))
	var tile_id := str(inst.get("tile_id", ""))

	var gate := BuildingLevels.research_gate(internal, target)
	if gate != "" and not ResearchState.is_unlocked(gate):
		return {"ok": false, "reason": "Requires research: %s" % gate, "research": gate}

	# Footprint: the larger building must fit (counting other in-progress upgrades).
	# Physical room counts everything; the owned-land gate only the player's estate.
	var size_delta := _upgrade_size_delta(building_id, level, target)
	var projected := BuildingState.get_tile_space_used(tile_id) + size_delta
	var projected_player := BuildingState.get_tile_player_space_used(tile_id) + size_delta
	var room_physical: bool = projected <= float(BuildingState.max_tile_land(tile_id))
	var room_owned: bool = projected_player <= float(BuildingState.get_tile_land_owned(tile_id))
	if not (room_physical and room_owned):
		return {"ok": false, "reason": _fits_reason(tile_id, size_delta, room_physical, room_owned)}

	# Split materials: what's on the tile vs the shortfall.
	var need_by_gid := _upgrade_need_by_gid(internal, target)
	var shortfall: Dictionary = {}
	for gid in need_by_gid:
		var short := int(need_by_gid[gid]) - Stockpile.get_at_tile(tile_id, gid)
		if short > 0:
			shortfall[gid] = short

	# Validate the chosen sourcing BEFORE consuming anything — start_upgrade is atomic, so a
	# broke wallet / no port / no spare tile fails cleanly with nothing taken off the tile.
	var transfer_source: Dictionary = {}
	if not shortfall.is_empty():
		match mode:
			"tile":
				return {"ok": false, "reason": "Upgrade materials missing on the tile.", "missing": shortfall, "required": need_by_gid}
			"market":
				var total := 0.0
				for gid in shortfall:
					var quote: Dictionary = MatchState.preview_buy(tile_id, str(gid), int(shortfall[gid]))
					if quote.is_empty():
						return {"ok": false, "reason": "No market route to deliver %s to this tile." % Catalog.get_display_name(str(gid))}
					total += float(quote.get("cost", 0.0))
				if total > MatchState.money:
					return {"ok": false, "reason": "Not enough money to order the missing materials (≈£%d)." % int(ceil(total))}
			"transfer":
				transfer_source = Construction.find_source_tile(tile_id, shortfall)
				if transfer_source.is_empty():
					return {"ok": false, "reason": "No single tile has the spare stock to transfer."}
			_:
				return {"ok": false, "reason": "Unknown sourcing mode."}

	# Cleared to commit. Reserve the in-place portion now (mirrors construction): consume what
	# we already have so co-located production can't claim it before the upgrade does.
	for gid in need_by_gid:
		var on_tile := int(need_by_gid[gid]) - int(shortfall.get(gid, 0))
		if on_tile > 0:
			Stockpile.consume(tile_id, gid, on_tile)

	# Queue the shortfall (cost / freight is charged inside queue_buy / queue_move).
	if not shortfall.is_empty():
		if mode == "market":
			for gid in shortfall:
				MatchState.queue_buy(tile_id, str(gid), int(shortfall[gid]), false, {"upgrade_instance_id": instance_id})
		elif mode == "transfer":
			TransportState.queue_move(str(transfer_source.get("tile_id", "")), tile_id, shortfall, false, {"upgrade_instance_id": instance_id})

	var status := UPGRADE_STATUS_UPGRADING if shortfall.is_empty() else UPGRADE_STATUS_AWAITING
	pending_upgrades.append({
		"instance_id": instance_id,
		"building_id": building_id,
		"tile_id": tile_id,
		"from_level": level,
		"target_level": target,
		"status": status,
		"materials": need_by_gid.duplicate(true),  # full kit — for refunding banked goods on cancel
		"missing": shortfall.duplicate(true),
		"turns_remaining": BuildingLevels.UPGRADE_DURATION,
		"size_delta": size_delta,
	})
	# Chief Investment rebates a fraction of the upgrade kit's market value (like a build).
	var up_rebate := MatchState._materials_rebate(need_by_gid)
	if up_rebate > 0.0:
		MatchState.add_money(up_rebate)
	building_upgrade_started.emit(instance_id, target)
	return {"ok": true, "status": status, "target_level": target}

# Cash-only infra upgrade: charge up front, run the same 3-turn countdown, and let
# tick_upgrades write the new level onto the tile. No kit → no Chief-Investment rebate
# (deliberately: cash isn't a material kit, and it closes the start/cancel rebate pump
# for this path).
func _start_infra_upgrade(instance_id: String, inst: Dictionary, internal: String) -> Dictionary:
	var level := infra_tile_level(inst)
	if level >= BuildingLevels.MAX_LEVEL:
		return {"ok": false, "reason": "Already at the maximum level."}
	var target := level + 1
	var cost := float(EconomyConfig.INFRA_UPGRADE_CASH_COST.get(target, 0.0))
	if MatchState.money < cost:
		return {"ok": false, "reason": "Not enough money — the upgrade costs £%d." % int(cost)}
	MatchState.add_money(-cost)
	pending_upgrades.append({
		"instance_id": instance_id,
		"building_id": str(inst.get("building_id", "")),
		"tile_id": str(inst.get("tile_id", "")),
		"from_level": level,
		"target_level": target,
		"status": UPGRADE_STATUS_UPGRADING,
		"materials": {},
		"missing": {},
		"turns_remaining": BuildingLevels.UPGRADE_DURATION,
		"size_delta": 0.0,
		"infra": true,
		"infra_slot": internal,     # slot key == building internal for all five
		"cash_paid": cost,
	})
	building_upgrade_started.emit(instance_id, target)
	return {"ok": true, "status": UPGRADE_STATUS_UPGRADING, "target_level": target}

## Advance every in-progress upgrade one turn. Awaiting projects claim any newly-arrived
## materials off the tile (this runs before production consumes, so there's no race); once
## fully stocked they start counting down, and at zero the building's level is bumped.
## Returns the instance_ids that completed this turn. Called from Production each PROCESS.
func tick_upgrades() -> Array:
	var completed: Array = []
	var remaining: Array = []
	for p in pending_upgrades:
		var instance_id := str(p.get("instance_id", ""))
		var is_infra := bool(p.get("infra", false))
		# Production upgrades still require their building. Tile-backed infrastructure
		# deliberately has no building instance; its tile slot is the persistent target.
		if not BuildingState.buildings.has(instance_id) and not is_infra:
			continue
		if is_infra and not BuildingState.buildings.has(instance_id) \
				and not _tile_has_infrastructure_slot(str(p.get("tile_id", "")), str(p.get("infra_slot", ""))):
			continue
		if str(p.get("status", "")) == UPGRADE_STATUS_AWAITING:
			var tile_id := str(p.get("tile_id", ""))
			var missing: Dictionary = p.get("missing", {})
			var still: Dictionary = {}
			for gid in missing:
				var want := int(missing[gid])
				var got := Stockpile.consume(tile_id, str(gid), want)
				if got < want:
					still[gid] = want - got
			p["missing"] = still
			if still.is_empty():
				p["status"] = UPGRADE_STATUS_UPGRADING
				p["stalled_turns"] = 0
			else:
				_retry_stalled_upgrade(p, instance_id, tile_id, still)
			building_upgrade_progress.emit(instance_id)
			remaining.append(p)
			continue
		# Under upgrade — count down, promote at zero.
		p["turns_remaining"] = int(p.get("turns_remaining", 0)) - 1
		if int(p["turns_remaining"]) <= 0:
			var new_level := int(p.get("target_level", 1))
			if is_infra:
				# The TILE dict is what power caps / transport capacity read. A player-built
				# infra slot also has an instance, but seeded slots intentionally do not.
				set_tile_infra_level(str(p.get("tile_id", "")), str(p.get("infra_slot", "")), new_level)
				if BuildingState.buildings.has(instance_id):
					(BuildingState.buildings[instance_id] as Dictionary)["level"] = new_level
			else:
				var inst: Dictionary = BuildingState.buildings[instance_id]
				new_level = int(p.get("target_level", int(inst.get("level", 1)) + 1))
				inst["level"] = new_level
			completed.append(instance_id)
			building_upgraded.emit(instance_id, new_level)
		else:
			building_upgrade_progress.emit(instance_id)
			remaining.append(p)
	pending_upgrades = remaining
	return completed

## An upgrade waiting on materials that nothing is carrying will wait FOREVER: the buy is
## queued once, at start_upgrade, and if that shipment is never made or is lost on the way
## there is nothing that would ever order another. Two buildings sat like that for the whole
## back half of a playtest, saying "No shipment is carrying the remaining N" every turn.
##
## So: once an upgrade has stood UPGRADE_STALL_TURNS turns with nothing inbound, re-order the
## shortfall down the same path start_upgrade used. Only genuinely STRANDED goods are
## re-ordered — a slow shipment still on the road is not stalled — and the counter resets on
## any progress, so a long haul never triggers it.
func _retry_stalled_upgrade(p: Dictionary, instance_id: String, tile_id: String,
		still: Dictionary) -> void:
	var stranded: Dictionary = {}
	for gid_value in still:
		var gid := str(gid_value)
		if not _upgrade_has_inbound(instance_id, tile_id, gid):
			stranded[gid] = int(still[gid_value])
	if stranded.is_empty():
		p["stalled_turns"] = 0   # something is still on its way; waiting is correct
		return
	var stalled := int(p.get("stalled_turns", 0)) + 1
	p["stalled_turns"] = stalled
	if stalled < UPGRADE_STALL_TURNS:
		return
	p["stalled_turns"] = 0
	var ordered: Array = []
	var refused: Array = []
	for gid_value in stranded:
		var gid := str(gid_value)
		var qty := int(stranded[gid_value])
		if MatchState.queue_buy(tile_id, gid, qty, false, {"upgrade_instance_id": instance_id}).is_empty():
			refused.append(Catalog.get_display_name(gid))
		else:
			ordered.append("%d %s" % [qty, Catalog.get_display_name(gid)])
	var building_id := str(BuildingState.get_building(instance_id).get("building_id", str(p.get("building_id", ""))))
	var what := str(Catalog.get_building(building_id).get("display_name", "An upgrade"))
	if not ordered.is_empty():
		MatchState.request_toast("%s was waiting on materials nothing was carrying — re-ordered %s."
			% [what, ", ".join(ordered)], "info")
	elif not refused.is_empty():
		# The retry itself could not be placed. Say why rather than silently waiting again.
		MatchState.request_toast("%s cannot be supplied with %s — no route, no headroom, or imports are banned."
			% [what, ", ".join(refused)], "warn")

## Is anything actually carrying `gid` to this upgrade right now?
func _upgrade_has_inbound(instance_id: String, tile_id: String, gid: String) -> bool:
	for list_variant: Variant in [TransportState.pending_transport_shipments, TransportState.overflow_shipments]:
		for shipment_variant: Variant in (list_variant as Array):
			var shipment: Dictionary = shipment_variant
			if str(shipment.get("upgrade_instance_id", "")) != instance_id:
				continue
			if str(shipment.get("destination_tile", "")) != tile_id:
				continue
			if str(shipment.get("good_id", "")) == gid and int(shipment.get("qty", 0)) > 0:
				return true
	return false

## Cancel an in-progress upgrade and hand the player back the materials it has already banked
## on the tile (full kit minus whatever's still in transit). Goods still being shipped in keep
## arriving and simply land in the tile stockpile. Returns true if an upgrade was cancelled.
func cancel_upgrade(instance_id: String) -> bool:
	var kept: Array = []
	var cancelled := false
	for p in pending_upgrades:
		if str(p.get("instance_id", "")) != instance_id:
			kept.append(p)
			continue
		cancelled = true
		var tile_id := str(p.get("tile_id", ""))
		var materials: Dictionary = p.get("materials", {})
		var missing: Dictionary = p.get("missing", {})
		# Banked = everything claimed so far (full kit minus what's still outstanding).
		for gid in materials:
			var banked := int(materials[gid]) - int(missing.get(gid, 0))
			if banked > 0:
				Stockpile.add(tile_id, str(gid), banked)
		# Infra upgrades are paid in cash up front — refund it in full (net zero, so
		# there's no start/cancel pump on this path).
		var cash_paid := float(p.get("cash_paid", 0.0))
		if cash_paid > 0.0:
			MatchState.add_money(cash_paid)
	pending_upgrades = kept
	if cancelled:
		building_upgrade_cancelled.emit(instance_id)
	return cancelled

# What demolishing `instance_id` would return: the build money plus EVERY material kit
# consumed over the building's life — the construction kit AND each completed upgrade
# level's kit (2..level) — scaled by EconomyConfig.demolish_refund_share. Pure: no state
# change. `materials` is good_id -> qty; `materials_value` is their worth at current market
# price; `total` is the all-cash-equivalent headline (money + materials_value).
# NOTE: this only COMPUTES the refund. Applying it (crediting money/materials, then
# remove_building) is the demolish action, handled later — see refund_plan for the payout split.
func refund_cost(instance_id: String) -> Dictionary:
	var empty := {"money": 0.0, "materials": {}, "materials_value": 0.0, "total": 0.0}
	var inst: Dictionary = BuildingState.buildings.get(instance_id, {})
	if inst.is_empty():
		return empty

	var share: float = EconomyConfig.demolish_refund_share
	var building_id: String = str(inst.get("building_id", ""))
	var building: Dictionary = Catalog.get_building(building_id)

	# Money leg: the real paid cost if it was stamped at promotion, else build_cost_money.
	var money_paid: float = float(inst.get("build_cost", building.get("base_price", 0.0)))

	# Material leg: the construction kit (good_id -> qty), stored at promotion or recomputed.
	var mats: Dictionary = {}
	var build_kit: Dictionary = inst.get("build_materials", {})
	if build_kit.is_empty():
		build_kit = Construction.requirements_for(building_id)
	for gid in build_kit:
		mats[gid] = int(mats.get(gid, 0)) + int(build_kit[gid])

	# ...plus every completed upgrade level's kit (keyed by internal_name -> good_id).
	var internal: String = str(building.get("internal_name", ""))
	var level: int = int(inst.get("level", 1))
	for lvl in range(2, level + 1):
		var kit: Dictionary = BuildingLevels.upgrade_materials(internal, lvl)
		for iname in kit:
			var gid: String = str(Catalog.get_good_by_internal_name(str(iname)).get("id", ""))
			if gid == "":
				continue
			mats[gid] = int(mats.get(gid, 0)) + int(kit[iname])

	# Apply the refund share to money and (rounded) material quantities; value at market.
	var out_mats: Dictionary = {}
	var mats_value: float = 0.0
	for gid in mats:
		var qty: int = int(round(float(mats[gid]) * share))
		if qty <= 0:
			continue
		out_mats[gid] = qty
		mats_value += float(qty) * MarketState.get_price(gid)

	var cash_part: float = money_paid * share
	return {
		"money": cash_part,
		"materials": out_mats,
		"materials_value": mats_value,
		"total": cash_part + mats_value,
	}

# How a demolish refund would actually be paid out given the building tile's storage room.
# Materials are returned to the tile stockpile up to its free capacity; any overflow that
# won't fit is offered as cash at current market price. The demolish dialog pops the
# cash-offer when `fits_fully` is false. Pure: reads capacity/prices, mutates nothing.
func refund_plan(instance_id: String) -> Dictionary:
	var refund: Dictionary = refund_cost(instance_id)
	var inst: Dictionary = BuildingState.buildings.get(instance_id, {})
	var tile_id: String = str(inst.get("tile_id", ""))
	var room: int = Stockpile.get_free_capacity(tile_id) if tile_id != "" else 0

	var to_stockpile: Dictionary = {}
	var cash_overflow: float = 0.0
	for gid in refund.materials:
		var qty: int = int(refund.materials[gid])
		var fit: int = clampi(qty, 0, room)
		if fit > 0:
			to_stockpile[gid] = fit
			room -= fit
		var overflow: int = qty - fit
		if overflow > 0:
			cash_overflow += float(overflow) * MarketState.get_price(gid)

	return {
		"money": refund.money,                # always paid as cash
		"to_stockpile": to_stockpile,         # good_id -> qty that fits in the tile
		"cash_overflow": cash_overflow,       # market value of what didn't fit
		"fits_fully": cash_overflow == 0.0,   # false -> pop the cash-offer dialog
		"materials": refund.materials,
		"materials_value": refund.materials_value,
		"total_if_cash": refund.total,        # money + all materials valued as cash
	}

# A paused building produces nothing and draws no inputs/power/labour, but keeps its upkeep.
# Used by the supply-chain panel when a sold/demolished building leaves a neighbour stranded.
func is_building_paused(instance_id: String) -> bool:
	return bool(paused_buildings.get(instance_id, false))

func set_building_paused(instance_id: String, paused: bool) -> void:
	if not BuildingState.buildings.has(instance_id):
		return
	if paused:
		paused_buildings[instance_id] = true
	else:
		paused_buildings.erase(instance_id)
	building_paused_changed.emit(instance_id)

func is_demolishing(instance_id: String) -> bool:
	return demolish_queue.has(instance_id)

func demolish_turns_remaining(instance_id: String) -> int:
	return int((demolish_queue.get(instance_id, {}) as Dictionary).get("turns_left", 0))

# Queue a player-owned building for demolition (completes in DEMOLISH_TURNS via tick_demolish).
func start_demolish(instance_id: String) -> Dictionary:
	if not BuildingState.buildings.has(instance_id):
		return {"ok": false, "reason": "No such building."}
	if not BuildingState.is_player_owned(BuildingState.buildings[instance_id]) and not BuildingState.is_land_owned_wood(BuildingState.buildings[instance_id]):
		return {"ok": false, "reason": "You don't own this building."}
	if demolish_queue.has(instance_id):
		return {"ok": false, "reason": "Already demolishing."}
	demolish_queue[instance_id] = {"turns_left": DEMOLISH_TURNS, "tile_id": str(BuildingState.buildings[instance_id].get("tile_id", ""))}
	building_demolish_started.emit(instance_id)
	return {"ok": true}

func cancel_demolish(instance_id: String) -> bool:
	if not demolish_queue.has(instance_id):
		return false
	demolish_queue.erase(instance_id)
	building_demolish_started.emit(instance_id)
	return true

# Advance queued demolitions one turn; complete any that reach zero — refund half the material
# kits to the tile stockpile (overflow → cash), then remove the building (frees its land). No
# money is returned (that's Sell). Returns the instance_ids removed this turn.
func tick_demolish() -> Array:
	var completed: Array = []
	for iid in demolish_queue.keys():
		var job: Dictionary = demolish_queue[iid]
		job["turns_left"] = int(job.get("turns_left", 0)) - 1
		if int(job["turns_left"]) > 0:
			continue
		if BuildingState.buildings.has(iid):
			var plan: Dictionary = refund_plan(iid)
			var tile_id: String = str(BuildingState.buildings[iid].get("tile_id", ""))
			for gid in (plan.get("to_stockpile", {}) as Dictionary):
				Stockpile.add(tile_id, str(gid), int(plan["to_stockpile"][gid]))
			var cash: float = float(plan.get("cash_overflow", 0.0))
			if cash > 0.0:
				MatchState.add_money(cash)
			BuildingState.remove_building(iid)
		demolish_queue.erase(iid)
		completed.append(iid)
		building_demolished.emit(iid)
	return completed
