extends RefCounted
## Building/infrastructure leveling (L1→L2→L3). One place for the level multipliers,
## (Consumers `preload` this as `const BuildingLevels` rather than relying on the
## global class registry, so it works in headless test runs too.)
## the per-building upgrade material kits, and which research node gates each upgrade.
##
## Production buildings carry `level` on their MatchState instance; infrastructure
## carries it on the tile (HexMap infrastructure_levels). The MULTIPLIERS and MATERIALS
## here apply to both; the upgrade ACTION differs (see MatchState.upgrade_building).

const MAX_LEVEL := 3

# An upgrade is not instant: once started it occupies the building for this many turns
# (mirrors a construction project's countdown) before the new level takes effect.
const UPGRADE_DURATION := 3

# Per-level scaling, indexed by level (1/2/3).
const INPUT_MULT  := {1: 1.0, 2: 2.0, 3: 3.0}
const OUTPUT_MULT := {1: 1.0, 2: 2.0, 3: 3.5}
const ENERGY_MULT := {1: 1.0, 2: 1.8, 3: 2.5}
const MAINT_MULT  := {1: 1.0, 2: 1.8, 3: 2.5}
const LABOUR_MULT := {1: 1.0, 2: 1.5, 3: 2.0}
const SIZE_MULT   := {1: 1.0, 2: 1.8, 3: 2.5}

# Every production-building upgrade includes this base kit (good_internal: qty).
const _BASE_KIT := {"building_frame": 2, "construction_equipment_ice": 1, "concrete": 10}

# Per-building EXTRA materials on top of the base kit, by target level.
const _EXTRAS := {
	"electrolyser":          {2: {"electrical_components": 2}, 3: {"electrical_components": 6, "computer": 2}},
	"chem_plant":            {2: {"rubber": 20, "plastics": 20}, 3: {"rubber": 10, "plastics": 10, "computer": 2}},
	"eaf":                   {2: {"electrical_components": 3}, 3: {"electrical_components": 6}},
	"industrial_factory":    {2: {"large_engine": 1}, 3: {"large_engine": 2, "electrical_components": 1, "computer": 2}},
	"mine":                  {2: {"large_engine": 1}, 3: {"large_engine": 4, "computer": 2}},
	"petro_refinery":        {2: {"computer": 1}, 3: {"computer": 6, "chem_salts": 40}},
	"poly_plant":            {2: {"computer": 1}, 3: {"computer": 6, "alloy_ingots": 20}},
	"assembly_plant":        {2: {"large_engine": 1, "computer": 4}, 3: {"large_engine": 2, "computer": 10}},
	"high_tech_manufactory": {2: {"graphite": 4, "computer": 8}, 3: {"graphite": 10, "computer": 16}},
	"desal":                 {2: {"chem_salts": 2}, 3: {"chem_salts": 10}},
	"farm":                  {2: {}, 3: {}},  # just the base kit
}

# Forests cost only biomass — no base kit. (Quantities are a first pass.)
const _FOREST := {2: {"biomass": 20}, 3: {"biomass": 40}}

# Infrastructure upgrades — no base kit, just these.
const _INFRA := {
	"rails":       {2: {"heavy_vehicle": 2}, 3: {"heavy_vehicle": 6}},
	"roads":       {2: {"construction_equipment_ice": 2}, 3: {"construction_equipment_ice": 2, "heavy_vehicle": 2}},
	"pipes":       {2: {"steel": 6, "alloy_ingots": 3, "engine": 3}, 3: {"steel": 12, "rubber": 10, "plastics": 10, "computer": 1}},
	"reinf_pipes": {2: {"steel": 10, "engine": 3, "computer": 1}, 3: {"steel": 20, "engine": 5, "rubber": 20, "plastics": 20, "computer": 3}},
	"cables":      {2: {"rubber": 5, "electrical_components": 5}, 3: {"rubber": 10, "electrical_components": 10, "computer": 2}},
}

# Research node that must be unlocked to reach a level (building_internal -> {level: title}).
# A missing (building, level) entry means the upgrade needs no research (materials only).
const _RESEARCH_GATE := {
	"mine":                  {2: "In-Pit Crushing", 3: "Autonomous Haul Systems"},
	"furnace":               {2: "Hot Blast Stoves", 3: "Top-Pressure Recovery Turbines"},
	"eaf":                   {2: "Twin-Shell Furnaces", 3: "Consteel Continuous Charging"},
	"industrial_factory":    {2: "Conveyor Mass Assembly", 3: "Robotic Assembly Islands"},
	"assembly_plant":        {2: "Moving Assembly Lines", 3: "Mixed-Model Synchronous Lines"},
	"high_tech_manufactory": {2: "300mm Wafer Lines", 3: "EUV Lithography"},
	"chem_plant":            {2: "Larger Reactor Trains", 3: "Integrated Chemical Complexes"},
	"electrolyser":          {2: "Membrane Electrolysers", 3: "Solid-Oxide Electrolysis"},
	"petro_refinery":        {2: "Fluid Catalytic Cracking", 3: "Deep Conversion Units"},
	"desal":                 {2: "Reverse Osmosis Trains", 3: "Seawater RO Megaplants"},
	"water_recycling":       {2: "Membrane Bioreactors", 3: "Closed-Loop Reclaim"},
	"water_pump":            {3: "Extensive Drainage Systems"},
	"farm":                  {3: "Controlled-Environment Farming"},
	"power_plant":           {2: "Supercritical Boilers", 3: "Ultra-Supercritical Units"},
	"solar_farm":            {2: "Single-Axis Trackers", 3: "Self-Adjusting Panel Network"},
	"onshore_wind_farm":     {2: "Larger Rotor Diameters", 3: "Direct-Drive Megaturbines"},
	"battery":               {2: "Liquid-Cooled Packs", 3: "Flow Battery Arrays"},
	"roads":                 {2: "Multi-Lane Widening", 3: "Grade-Separated Interchanges"},
	"rails":                 {2: "Longer Freight Consists", 3: "Standardised Wagon Gantry Cranes"},
	"pipes":                 {2: "Automated Pressure Management System", 3: "Looped Distribution Grids"},
	"reinf_pipes":           {2: "High-Pressure Manifolds", 3: "Cryogenic Transfer Lines"},
	"cables":                {2: "Reconductoring", 3: "Smart Grid Control"},
}

## The per-aspect multiplier for a level. aspect ∈ input/output/energy/maint/labour/size.
static func mult(aspect: String, level: int) -> float:
	match aspect:
		"input":  return float(INPUT_MULT.get(level, 1.0))
		"output": return float(OUTPUT_MULT.get(level, 1.0))
		"energy": return float(ENERGY_MULT.get(level, 1.0))
		"maint":  return float(MAINT_MULT.get(level, 1.0))
		"labour": return float(LABOUR_MULT.get(level, 1.0))
		"size":   return float(SIZE_MULT.get(level, 1.0))
	return 1.0

## Materials {good_internal: qty} to upgrade `building_internal` to `target_level`.
## Empty if the level is out of range.
static func upgrade_materials(building_internal: String, target_level: int) -> Dictionary:
	if target_level < 2 or target_level > MAX_LEVEL:
		return {}
	if _INFRA.has(building_internal):
		return (_INFRA[building_internal].get(target_level, {}) as Dictionary).duplicate()
	if building_internal == "new_forest" or building_internal == "old_forest":
		return (_FOREST.get(target_level, {}) as Dictionary).duplicate()
	# Production building: base kit + any per-building extras (default = base kit only).
	var mats: Dictionary = _BASE_KIT.duplicate()
	var ex: Dictionary = (_EXTRAS.get(building_internal, {}) as Dictionary).get(target_level, {})
	for g in ex:
		mats[g] = int(mats.get(g, 0)) + int(ex[g])
	return mats

## Research title gating an upgrade, or "" if none required.
static func research_gate(building_internal: String, target_level: int) -> String:
	return str((_RESEARCH_GATE.get(building_internal, {}) as Dictionary).get(target_level, ""))
