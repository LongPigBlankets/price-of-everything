extends Node
## BuildingState: the building instances themselves and what is derived from them — the flat
## instance dictionary, the per-tile occupancy index kept in sync with it, instance ids,
## ownership changes (buy, sell, liquidate), tile space and the player's land ledger per
## tile. Extracted from MatchState on 2026-09-12; the save keys are unchanged and still live
## under the "match" section (MatchState.export_state merges export_fields(), import_state
## calls import_fields(), reset() calls reset()).
##
## The invariant that made this one object: every add, remove and owner change updates
## `buildings` and `tile_buildings` in the same step. Never write either from outside.
## Money, the ruleset, the match RNG and the player id (MatchState.LOCAL_PLAYER) stay in
## MatchState; upgrades/retrofits/demolition live in BuildingWorks.

const BuildingPrice := preload("res://scripts/building_price.gd")
const BuildingLevels := preload("res://scripts/building_levels.gd")

# When you SELL a building it transfers to this NPC operator (keeps standing, land occupied).
const SOLD_TO_OWNER := "npc_market"
const DEFAULT_TILE_LAND_OWNED := 0
const LAND_PATCH_SIZE := 10
const LAND_PATCH_COST := 10.0
## The most land any tile can ever hold, and the default for terrain this table does not
## name. Kept as the hard ceiling: every cap below is clamped to it.
const MAX_TILE_LAND := 200
## BUILDABLE LAND BY TERRAIN. Rough ground and built-up ground hold less
## than open country. Urban sits above hill deliberately: a town is dense, and the ground
## between 100 and its cap is decorative fabric a player can demolish to make room, where
## rural's is simply empty.
##
## This replaces a table in `tile_view_data.gd` that expressed the same idea as bonuses on a
## base of 200 (rural +50, hill +25, mountain -25) and then clamped to MAX_TILE_LAND — so
## every positive one was clamped away and only mountain had any effect, in the panel only.
## Reductions survive the clamp, and this table is read by the build gate rather than by the
## display alone.
const TILE_LAND_BY_TERRAIN := {
	"rural": 200,
	"grass": 200,
	"urban": 170,
	"hill": 160,
	"mountain": 120,
}
## The owner a wood standing on the land itself carries — no company holds it.
const LAND_OWNER := "tile_data"

signal building_added(instance: Dictionary)
signal building_removed(instance_id: String)
# A building's owner changed (e.g. the player bought an NPC building from the market). UI that
# filters by ownership (the ledger, the buildings-for-sale tab) listens to refresh live.
signal building_owner_changed(instance_id: String)
signal tile_land_owned_changed(tile_id: String)

# Flat dictionary: instance_id -> building data dict
# Building data: {instance_id, building_id, recipe_id, tile_coord, owner}
var buildings: Dictionary = {}
# tile_id -> Array of instance_ids
# This is for fast "what's on this tile" queries.
var tile_buildings: Dictionary = {}
var _next_instance_counter: int = 0
var tile_land_owned: Dictionary = {}


## Match-scoped: cleared by MatchState.reset() (new game / scenario start).
func reset() -> void:
	buildings.clear()
	tile_buildings.clear()
	tile_land_owned.clear()
	_next_instance_counter = 0


## Saved under MatchState's "match" section (keys unchanged from before the extraction).
func export_fields() -> Dictionary:
	return {
		"next_instance_counter": _next_instance_counter,
		"buildings": _buildings_for_save(),
		"tile_land_owned": tile_land_owned.duplicate(true),
	}


func import_fields(d: Dictionary) -> void:
	_next_instance_counter = int(d.get("next_instance_counter", 0))
	buildings = _normalise_loaded_buildings(d.get("buildings", {}))
	tile_land_owned = (d.get("tile_land_owned", {}) as Dictionary).duplicate(true)


func is_player_owned(building: Dictionary) -> bool:
	# NPC-owned infrastructure (e.g. the shipping corporation's ports) is not the
	# player's to pay for. Buildings default to the local player when owner is unset.
	return str(building.get("owner", MatchState.LOCAL_PLAYER)) == MatchState.LOCAL_PLAYER

## A wood that belongs to the LAND rather than to a company. Every authored wood the start
## layout does not already cover is seeded as one of these, and there is no company to buy it
## from — so felling one is clearing ground, not taking someone's property, and it is allowed
## (all forests should be demolishable). A wood a COMPANY owns still has to
## be bought first, exactly like any other building of theirs.
func is_land_owned_wood(building: Dictionary) -> bool:
	return str(building.get("owner", MatchState.LOCAL_PLAYER)) == LAND_OWNER \
		and ForestFootprint.FOREST_BUILDING_IDS.has(str(building.get("building_id", "")))

func add_building(
	building_id: String,
	recipe_id: String,
	tile_id: String,
	owner: String = "player_1",
	instance_id: String = "",
	emit_added: bool = true
) -> String:
	# Pass the building_id here! An explicit instance_id lets a construction project keep one
	# stable id from placement through completion; empty means generate a fresh one.
	if instance_id == "":
		instance_id = _generate_instance_id(building_id)

	var instance := {
		"instance_id": instance_id,
		"building_id": building_id,
		"recipe_id": recipe_id,
		"tile_id": tile_id,
		"owner": owner,
		"level": 1,
	}

	buildings[instance_id] = instance
	
	if not tile_buildings.has(tile_id):
		tile_buildings[tile_id] = []
	tile_buildings[tile_id].append(instance_id)

	if emit_added:
		building_added.emit(instance)
		# Construction can complete several buildings in one PROCESS pass.  Defer
		# research evaluation to NARRATIVE so that batch costs stay constant.
		ResearchState._mark_research_progress_dirty()
	return instance_id


# Transfer ownership of an existing building (e.g. the player buys an NPC building from the
# market). Changing the owner is all that's needed for the building to become the player's: the
# production pass rebuilds its player-owned set each turn, so a bought building runs from next
# turn. Emits building_owner_changed so ownership-filtered UI refreshes immediately.
func set_building_owner(instance_id: String, owner: String) -> void:
	if not buildings.has(instance_id):
		return
	if str(buildings[instance_id].get("owner", MatchState.LOCAL_PLAYER)) == owner:
		return
	buildings[instance_id]["owner"] = owner
	# Buying bundles the land under the building: grant its footprint as owned land on the tile.
	if owner == MatchState.LOCAL_PLAYER:
		_stamp_purchase_build_value(instance_id)
		_grant_building_land(instance_id)
		# The tile size chart stacks buildings bought off an NPC at the top of the pile.
		buildings[instance_id]["acquired_from_npc"] = true
		# A purchase is a going concern, so it arrives with stock to run on. Seeded HERE rather
		# than in the market panel because three separate surfaces transfer ownership (market
		# panel, building detail, tile info) and the tutorial buys through one of them.
		MatchState.seed_purchase_inventory(instance_id)
	building_owner_changed.emit(instance_id)
	# A newly player-owned building may satisfy a count condition after the turn
	# settles; never trigger a full scan from an interaction callback.
	ResearchState._mark_research_progress_dirty()

# Sell a player-owned building to an NPC operator: credit its market value (what it would list
# at), flip ownership to the NPC — the building keeps standing and its land stays occupied, but it
# stops running for you (production rebuilds the player-owned set each turn). Instantaneous.
func sell_building(instance_id: String) -> Dictionary:
	if not buildings.has(instance_id):
		return {"ok": false, "reason": "No such building."}
	if not is_player_owned(buildings[instance_id]):
		return {"ok": false, "reason": "You don't own this building."}
	var price: int = int(round(float(BuildingPrice.sale_price(buildings[instance_id]))))
	MatchState.add_money(float(price))
	set_building_owner(instance_id, SOLD_TO_OWNER)  # emits building_owner_changed → UI refresh
	MatchState.request_toast("Sold building for £%d" % price, "success")
	return {"ok": true, "price": price}

# Sell EVERY player building at once for price_mult x sale value (the distressed-asset
# bailout: investors buy the lot at 1.5x). Returns {total, count}. Buildings keep
# standing under the NPC operator but stop running for the player.
func liquidate_all_buildings(price_mult: float) -> Dictionary:
	var total: int = 0
	var count: int = 0
	for instance_id in buildings.keys().duplicate():
		var b: Dictionary = buildings[instance_id]
		if not is_player_owned(b):
			continue
		var price: int = int(round(float(BuildingPrice.sale_price(b)) * price_mult))
		MatchState.add_money(float(price))
		set_building_owner(str(instance_id), SOLD_TO_OWNER)
		total += price
		count += 1
	if count > 0:
		MatchState.request_toast("Distressed sale: %d buildings for £%d" % [count, total], "warning")
	return {"total": total, "count": count}

# A building acquired ready-made (NPC market purchase, scripted transfer) gets the
# same cost basis a player-built copy would carry: the catalog base price as the
# money leg and the standard construction kit as the material leg. Without the
# stamp, refund_cost's fallback values it at base_price PLUS a freshly recomputed
# full kit — more than any build ever cost — which arms a buy-cheap → demolish
# money pump the day demolition ships. Player-built instances keep the exact
# stamp Construction wrote at promotion.
func _stamp_purchase_build_value(instance_id: String) -> void:
	var inst: Dictionary = buildings.get(instance_id, {})
	if inst.is_empty() or inst.has("build_cost"):
		return
	var building_id := str(inst.get("building_id", ""))
	var building: Dictionary = Catalog.get_building(building_id)
	inst["build_cost"] = float(building.get("base_price", 0.0))
	inst["build_materials"] = Construction.requirements_for(building_id)

# Grant the footprint directly under a building as owned land on its tile (once, capped at the tile
# max). get_tile_space_used already counts the building, so we add ONLY this building's footprint —
# never the whole tile or other buildings' land — which keeps the land accounting from double-counting.
func _grant_building_land(instance_id: String) -> void:
	var b: Dictionary = buildings.get(instance_id, {})
	var tile_id := str(b.get("tile_id", ""))
	if tile_id == "":
		return
	var bdata: Dictionary = Catalog.get_building(str(b.get("building_id", "")))
	var footprint := ceili(float(bdata.get("tile_size_used", 1)) * BuildingLevels.mult("size", int(b.get("level", 1))))
	if footprint <= 0:
		return
	var owned := get_tile_land_owned(tile_id)
	var granted := mini(max_tile_land(tile_id), owned + footprint)
	if granted != owned:
		tile_land_owned[tile_id] = granted
		tile_land_owned_changed.emit(tile_id)

func remove_building(instance_id: String) -> bool:
	if not buildings.has(instance_id):
		return false

	# Refund any in-progress upgrade's banked materials before the building disappears,
	# and drop any queued retrofit so it can't sit in limbo against a dead instance.
	BuildingWorks.cancel_upgrade(instance_id)
	BuildingWorks.cancel_retrofit(instance_id)

	var instance: Dictionary = buildings[instance_id]
	var tile_id: String = instance.tile_id
	
	if tile_buildings.has(tile_id):
		tile_buildings[tile_id].erase(instance_id)
		if tile_buildings[tile_id].is_empty():
			tile_buildings.erase(tile_id)
	
	buildings.erase(instance_id)
	BuildingWorks.paused_buildings.erase(instance_id)
	MatchState.output_stockpile_destinations.erase(instance_id)
	MatchState.output_special_order_destinations.erase(instance_id)
	# Removing battery housing shrinks the tile's cell slots — refund any now-excess loaded cells.
	if str(Catalog.get_building(str(instance.get("building_id", ""))).get("category", "")) == "battery":
		Power.refund_battery_cells_over_slots(tile_id)
	building_removed.emit(instance_id)
	return true

func get_buildings_on_tile(tile_id: String) -> Array:
	# Returns an Array of building instance dicts on the given tile.
	if not tile_buildings.has(tile_id):
		return []
	
	var result: Array = []
	for instance_id in tile_buildings[tile_id]:
		if buildings.has(instance_id):
			result.append(buildings[instance_id])
	return result

func get_tile_space_used(tile_id: String) -> float:
	var total := 0.0
	for instance in get_buildings_on_tile(tile_id):
		var building_id: String = instance.get("building_id", "")
		var building_data := Catalog.get_building(building_id)
		# A levelled-up building takes more room (SIZE_MULT).
		total += float(building_data.get("tile_size_used", 1.0)) * BuildingLevels.mult("size", int(instance.get("level", 1)))
	# Pending construction projects reserve their footprint up front (Phase 1: none linger).
	total += Construction.reserved_space_on_tile(tile_id)
	# In-progress upgrades reserve the extra room the building is about to grow into.
	total += BuildingWorks.reserved_upgrade_space_on_tile(tile_id)
	return total

# Footprint of buildings the player does NOT own on the tile. NPC buildings sit on
# their own (unpurchasable) land, so they never count against the player's owned
# land — buying the building converts that footprint to owned via _grant_building_land.
func get_tile_npc_footprint(tile_id: String) -> float:
	var total := 0.0
	for instance in get_buildings_on_tile(tile_id):
		if is_player_owned(instance):
			continue
		var building_data := Catalog.get_building(str(instance.get("building_id", "")))
		total += float(building_data.get("tile_size_used", 1.0)) * BuildingLevels.mult("size", int(instance.get("level", 1)))
	return total

# Space the PLAYER's estate takes on the tile: owned buildings plus construction /
# upgrade reservations (only the player builds). This — not the physical total —
# is what the owned-land gate compares against.
func get_tile_player_space_used(tile_id: String) -> float:
	return maxf(0.0, get_tile_space_used(tile_id) - get_tile_npc_footprint(tile_id))

func get_tile_land_owned(tile_id: String) -> int:
	return int(tile_land_owned.get(tile_id, DEFAULT_TILE_LAND_OWNED))

# Patches still purchasable: the tile cap minus the land under NPC buildings (not
# for sale — buy the building instead) minus what the player already owns. `cap`
# lets the UI pass a tighter cap; it never exceeds the tile's own terrain ceiling.
# The FINAL patch may be a clipped sliver (ceil): NPC footprints rarely align to the
# 10-unit patch grid, and flooring would leave the last few land units of a tile
# permanently unbuyable and unbuildable.
## The buildable ceiling for one tile, from its terrain. Every land and build rule goes
## through here rather than reading MAX_TILE_LAND, so terrain actually bites instead of only
## being displayed.
func max_tile_land(tile_id: String) -> int:
	var terrain := Catalog.tile_type(tile_id)
	return clampi(int(TILE_LAND_BY_TERRAIN.get(terrain, MAX_TILE_LAND)), 1, MAX_TILE_LAND)

func get_tile_land_patches_available(tile_id: String, cap: int = MAX_TILE_LAND) -> int:
	return maxi(0, int(ceil(float(get_tile_land_units_available(tile_id, cap)) / float(LAND_PATCH_SIZE))))

# Exact land units still purchasable on the tile (not rounded to patches).
func get_tile_land_units_available(tile_id: String, cap: int = MAX_TILE_LAND) -> int:
	var effective_cap := mini(cap, max_tile_land(tile_id))
	return maxi(0, effective_cap - int(round(get_tile_npc_footprint(tile_id))) - get_tile_land_owned(tile_id))

func purchase_tile_land(tile_id: String, patches: int = 1, cap: int = MAX_TILE_LAND) -> bool:
	if tile_id == "":
		return false
	var available := get_tile_land_patches_available(tile_id, cap)
	if available <= 0:
		return false
	var clamped_patches: int = clampi(patches, 1, available)
	# ctx carries the tile so per-tile purchase_cost modifiers (e.g. the land-deal
	# decision's "development premium" follow-up) can target it.
	var cost := AdvisorState.purchase_cost_after_advisor(float(clamped_patches) * LAND_PATCH_COST, {"tile_id": tile_id})
	if not MatchState.deduct_money(cost):
		return false
	var owned := get_tile_land_owned(tile_id)
	# The last patch can be a clipped sliver — never grant past the NPC-adjusted cap.
	var granted := mini(clamped_patches * LAND_PATCH_SIZE, get_tile_land_units_available(tile_id, cap))
	tile_land_owned[tile_id] = mini(max_tile_land(tile_id), owned + granted)
	tile_land_owned_changed.emit(tile_id)
	return true

func sellable_land_patches(tile_id: String) -> int:
	if tile_id == "":
		return 0
	for b in buildings.values():
		if str(b.get("tile_id", "")) == tile_id:
			return 0
	for p in Construction.construction_projects.values():
		if str(p.get("tile_id", "")) == tile_id:
			return 0
	var surplus := get_tile_land_owned(tile_id) - DEFAULT_TILE_LAND_OWNED
	return maxi(0, int(floor(float(surplus) / float(LAND_PATCH_SIZE))))

func sell_tile_land(tile_id: String, patches: int, price_per_patch: float) -> bool:
	var sellable := sellable_land_patches(tile_id)
	var clamped := clampi(patches, 0, sellable)
	if clamped <= 0:
		return false
	tile_land_owned[tile_id] = get_tile_land_owned(tile_id) - clamped * LAND_PATCH_SIZE
	MatchState.add_money(float(clamped) * price_per_patch)
	tile_land_owned_changed.emit(tile_id)
	return true

func get_building(instance_id: String) -> Dictionary:
	# Returns the instance dict, or empty dict if not found
	return buildings.get(instance_id, {})

func _generate_instance_id(building_id: String) -> String:
	_next_instance_counter += 1
	# %s injects the string, %06x injects the hex counter
	return "inst_%s_%06x" % [building_id, _next_instance_counter]

# Public: reserve a unique instance id before the building exists. Used by Construction so a
# project keeps the same id from placement to completion.
func reserve_instance_id(building_id: String) -> String:
	return _generate_instance_id(building_id)

func _buildings_for_save() -> Dictionary:
	var out: Dictionary = {}
	for instance_id in buildings:
		var value: Variant = buildings[instance_id]
		if not (value is Dictionary):
			continue
		var inst: Dictionary = (value as Dictionary).duplicate(true)
		inst["level"] = clampi(int(inst.get("level", 1)), 1, BuildingLevels.MAX_LEVEL)
		out[instance_id] = inst
	return out

func _normalise_loaded_buildings(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not (raw is Dictionary):
		return out
	var raw_dict: Dictionary = raw as Dictionary
	for instance_id in raw_dict:
		var value: Variant = raw_dict[instance_id]
		if not (value is Dictionary):
			continue
		var inst: Dictionary = (value as Dictionary).duplicate(true)
		inst["level"] = clampi(int(inst.get("level", 1)), 1, BuildingLevels.MAX_LEVEL)
		out[instance_id] = inst
	return out

func _rebuild_tile_index() -> void:
	tile_buildings.clear()
	for instance_id in buildings:
		var tile_id := str(buildings[instance_id].get("tile_id", ""))
		if tile_id == "":
			continue
		if not tile_buildings.has(tile_id):
			tile_buildings[tile_id] = []
		tile_buildings[tile_id].append(instance_id)

func player_building_count() -> int:
	var n := 0
	for b in buildings.values():
		if b is Dictionary and is_player_owned(b):
			n += 1
	return n
