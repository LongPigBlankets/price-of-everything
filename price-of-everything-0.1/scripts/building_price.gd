extends RefCounted
## Deterministic NPC-building sale price for the buildings-for-sale market.
##
##   price = round( (market value of build materials + land cost) × variation )
##
## - Build materials: the L1 build kit, plus the upgrade kit for every level the building
##   has gained above 1 (L2 building = L1 kit + L2 upgrade kit, etc.), each good valued at
##   its CURRENT market price.
## - Land cost: the building's footprint at its level, bought in land patches
##   (MatchState.LAND_PATCH_SIZE / LAND_PATCH_COST).
## - Variation: a per-building deterministic 70–100% in 5% steps, so two otherwise-identical
##   buildings (same type + recipe) can be priced differently. Buildings on, or within one hex
##   of, a port add a +10% premium → up to 110% of construction + land cost.
##
## Deterministic via RoadHash (FNV-1a over the instance id) — stable across saves and engine
## versions, identical for repeated reads, and free of any global RNG (sim determinism rule).

const BuildingLevels := preload("res://scripts/building_levels.gd")
const RoadHash := preload("res://scripts/road_hash.gd")

const VARIATION_MIN := 0.70
const VARIATION_STEP := 0.05
const VARIATION_STEPS := 7    # 0.70, 0.75, 0.80, 0.85, 0.90, 0.95, 1.00
const PORT_PREMIUM := 0.10    # +10% on, or within one hex of, a port
const PORT_PRICE := 10000     # a seaport is a fixed-value asset — its build kit is near-empty, so the
                             # materials+land valuation would otherwise misprice it (~£18).

# Final buy price for a placed building instance dict ({instance_id, building_id, tile_id, level}).
static func sale_price(building: Dictionary) -> int:
	if str(Catalog.get_building(str(building.get("building_id", ""))).get("internal_name", "")) == "port":
		return PORT_PRICE
	var base := base_cost(building)
	if base <= 0.0:
		return 0
	var mult := variation_multiplier(str(building.get("instance_id", "")))
	if is_near_port(str(building.get("tile_id", ""))):
		mult += PORT_PREMIUM
	return int(round(base * mult))

# Construction + land cost before the per-building variation.
static func base_cost(building: Dictionary) -> float:
	var bdata: Dictionary = Catalog.get_building(str(building.get("building_id", "")))
	if bdata.is_empty():
		return 0.0
	var level: int = int(building.get("level", 1))
	return _materials_value(bdata, level) + _land_cost(bdata, level)

# The deterministic 70–100% multiplier for one building (no port premium).
static func variation_multiplier(instance_id: String) -> float:
	return VARIATION_MIN + VARIATION_STEP * float(RoadHash.pick(instance_id, VARIATION_STEPS))

static func is_near_port(tile_id: String) -> bool:
	if tile_id == "":
		return false
	for p in Catalog.all_ports():
		if Catalog.tile_hex_distance(tile_id, str(p.get("tile_id", ""))) <= 1:
			return true
	return false

# ── internals ────────────────────────────────────────────────────────────────────────────
static func _materials_value(bdata: Dictionary, level: int) -> float:
	var total := 0.0
	for m in bdata.get("materials", []):  # L1 build kit: [{name: internal, qty}]
		total += float(int(m.get("qty", 0))) * _good_price(str(m.get("name", "")))
	var internal := str(bdata.get("internal_name", ""))
	for lvl in range(2, level + 1):       # upgrade kits for each level reached above 1
		var kit: Dictionary = BuildingLevels.upgrade_materials(internal, lvl)
		for good_internal in kit:
			total += float(int(kit[good_internal])) * _good_price(str(good_internal))
	return total

static func _good_price(internal_name: String) -> float:
	if internal_name == "":
		return 0.0
	var good: Dictionary = Catalog.get_good_by_internal_name(internal_name)
	var gid := str(good.get("id", ""))
	if gid == "":
		return 0.0
	var p := MarketState.get_price(gid)
	return p if p > 0.0 else float(good.get("base_price", 0.0))

static func _land_cost(bdata: Dictionary, level: int) -> float:
	var footprint := float(bdata.get("tile_size_used", 1)) * BuildingLevels.mult("size", level)
	var patches := ceilf(footprint / float(MatchState.LAND_PATCH_SIZE))
	return patches * MatchState.LAND_PATCH_COST
