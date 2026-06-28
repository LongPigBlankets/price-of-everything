extends Node
##
## Central modifier registry. One pipe carries every "+X% recipe output",
## "+15% transport cost", "-£2 maintenance/turn" effect produced by advisors,
## research, carbon tax events, special market orders, and pollution.
##
## Two ways modifiers arrive:
##   1. Programmatic - Modifiers.add({...})
##   2. Event payload - any EventScheduler event with a `modifiers` array gets
##      its entries auto-added when it fires (turn-stamped on arrival).
##
## Resolution: callers ask `Modifiers.apply(domain, target, base, ctx)`. Stacking
## is (base + sum_of_adds) * product_of_mults * (1 + sum_of_pcts/100). The `pct`
## channel is the headline one — every research/advisor "+5% output", "−20% power"
## effect is a `pct`, and pcts in the same domain *add* (a −10% and a +15% net to
## +5%, then apply ×1.05) rather than chaining. `add`/`mult` stay for legacy event
## payloads. With no active modifiers `apply` is one dict-emptiness check, so it
## stays cheap on the production hot path. The recipe card's net-modifier indicator
## reads the same pcts back via `resolve_pct(domain, target, ctx)`.
##
## Each TurnManager NARRATIVE phase prunes expired modifiers (those whose
## `expires_turn` has passed).
##
## All of this is data: SaveLoad's export_state/import_state round-trip the
## registry; the future top-bar Modifiers UI reads `active()` directly; a
## carbon-tax event arriving via the EventScheduler is functionally identical
## to a unit-test calling Modifiers.add().

const HISTORY_CAP := 50

# Research unlocks that grant a standing modifier when earned. Keyed by the unlock
# title exactly as it appears in research_unlocks.csv. Both the condition path
# (grant_unlock via_condition=true) and the free-pick path (via_condition=false)
# route through MatchState.unlock_granted, so either way the bonus lands. A value
# may be a single modifier dict or an Array of them (one effect hitting two
# buildings — e.g. Lights-Out Automation at high-tech *and* assembly).
#
# `target_match.building_id` is the catalog id the production/cost ctx carries
# (b_002 furnace · b_008 EAF · b_009 assembly · b_010 high-tech · b_011 refinery
# · b_012 chem plant · b_021 desal). Domains: recipe_output (production qty),
# building_power (energy drawn), labour_headcount (staffing cost), maintenance.
const UNLOCK_MODIFIERS := {
	# ── recipe output (production quantity) ──────────────────────────────
	"Mining Mastery": {
		"id": "mining_mastery_bonus", "domain": "recipe_output",
		"target_match": {"recipe_type": "mineral mining"}, "pct": 5.0,
		"duration_turns": 30,
		"label": "Mining Mastery: +5% mining output",
		"source": "research:mining_mastery",
	},
	"Continuous-Flow Reactors": {
		"id": "cfr_chem_output", "domain": "recipe_output",
		"target_match": {"building_id": "b_012"}, "pct": 5.0,
		"label": "Continuous-Flow Reactors: +5% chemical-plant output",
		"source": "research:continuous_flow_reactors",
	},
	"Continuous Catalyst Regeneration": {
		"id": "ccr_refinery_output", "domain": "recipe_output",
		"target_match": {"building_id": "b_011"}, "pct": 5.0,
		"label": "Continuous Catalyst Regeneration: +5% refinery output",
		"source": "research:continuous_catalyst_regeneration",
	},
	"Atomic Layer Deposition": {
		"id": "ald_hightech_output", "domain": "recipe_output",
		"target_match": {"building_id": "b_010"}, "pct": 5.0,
		"label": "Atomic Layer Deposition: +5% high-tech output",
		"source": "research:atomic_layer_deposition",
	},
	"Coordinated Robot Handoff": {
		"id": "crh_assembly_output", "domain": "recipe_output",
		"target_match": {"building_id": "b_009"}, "pct": 5.0,
		"label": "Coordinated Robot Handoff: +5% assembly-plant output",
		"source": "research:coordinated_robot_handoff",
	},
	# ── building power consumption ───────────────────────────────────────
	"Pulverised Carbon Injection": {
		"id": "pci_furnace_power", "domain": "building_power",
		"target_match": {"building_id": "b_002"}, "pct": -20.0,
		"label": "Pulverised Carbon Injection: −20% furnace power",
		"source": "research:pulverised_carbon_injection",
	},
	"Scrap Preheating Towers": {
		"id": "preheat_eaf_power", "domain": "building_power",
		"target_match": {"building_id": "b_008"}, "pct": -20.0,
		"label": "Scrap Preheating Towers: −20% EAF power",
		"source": "research:scrap_preheating_towers",
	},
	"Energy-Recovery Devices": {
		"id": "erd_desal_power", "domain": "building_power",
		"target_match": {"building_id": "b_021"}, "pct": -50.0,
		"label": "Energy-Recovery Devices: −50% desalination power",
		"source": "research:energy_recovery_devices",
	},
	# ── labour headcount ─────────────────────────────────────────────────
	"Lights-Out Automation": [
		{
			"id": "lo_hightech_labour", "domain": "labour_headcount",
			"target_match": {"building_id": "b_010"}, "pct": -20.0,
			"label": "Lights-Out Automation: −20% high-tech labour",
			"source": "research:lights_out_automation",
		},
		{
			"id": "lo_assembly_labour", "domain": "labour_headcount",
			"target_match": {"building_id": "b_009"}, "pct": -20.0,
			"label": "Lights-Out Automation: −20% assembly labour",
			"source": "research:lights_out_automation",
		},
	],
	# ── maintenance (empire-wide thermal-battery retrofit) ───────────────
	"Combined Heat & Power": {
		"id": "chp_maintenance", "domain": "maintenance",
		"target": "*", "pct": -5.0,
		"label": "Combined Heat & Power: −5% maintenance",
		"source": "research:combined_heat_power",
	},
	# ── mining-yield research: a +20% recipe_output tile on the mined good,
	# stacking ADDITIVELY with that good's standing deposit penalty (so e.g. an
	# iron mine reads −50% + 20% = net −30% once the tech lands). Matched by the
	# good's internal name, same as the deposit penalties below.
	"Improved Coal Mining": {
		"id": "yield_coal", "domain": "recipe_output",
		"target_match": {"good_internal": "coal"}, "pct": 20.0,
		"label": "Improved Coal Mining", "source": "research:mining_yield",
	},
	"Beneficiated Iron Mining": {
		"id": "yield_iron_ore", "domain": "recipe_output",
		"target_match": {"good_internal": "iron_ore"}, "pct": 20.0,
		"label": "Beneficiated Iron Mining", "source": "research:mining_yield",
	},
	"Copper Froth Flotation": {
		"id": "yield_copper_ore", "domain": "recipe_output",
		"target_match": {"good_internal": "copper_ore"}, "pct": 20.0,
		"label": "Copper Froth Flotation", "source": "research:mining_yield",
	},
	"Deep Seam Surveying": [
		{"id": "yield_limestone", "domain": "recipe_output", "target_match": {"good_internal": "limestone"}, "pct": 20.0, "label": "Deep Seam Surveying", "source": "research:mining_yield"},
		{"id": "yield_sand", "domain": "recipe_output", "target_match": {"good_internal": "sand"}, "pct": 20.0, "label": "Deep Seam Surveying", "source": "research:mining_yield"},
		{"id": "yield_basic_salt", "domain": "recipe_output", "target_match": {"good_internal": "basic_salt"}, "pct": 20.0, "label": "Deep Seam Surveying", "source": "research:mining_yield"},
	],
	"Rare Vein Prospecting": [
		{"id": "yield_ree_ore", "domain": "recipe_output", "target_match": {"good_internal": "ree_ore"}, "pct": 20.0, "label": "Rare Vein Prospecting", "source": "research:mining_yield"},
		{"id": "yield_alloy_ore", "domain": "recipe_output", "target_match": {"good_internal": "alloy_ore"}, "pct": 20.0, "label": "Rare Vein Prospecting", "source": "research:mining_yield"},
	],
	"Composite Drill Bits": [
		{"id": "yield_ree_ore_2", "domain": "recipe_output", "target_match": {"good_internal": "ree_ore"}, "pct": 20.0, "label": "Composite Drill Bits", "source": "research:mining_yield"},
		{"id": "yield_alloy_ore_2", "domain": "recipe_output", "target_match": {"good_internal": "alloy_ore"}, "pct": 20.0, "label": "Composite Drill Bits", "source": "research:mining_yield"},
		{"id": "yield_sulphur", "domain": "recipe_output", "target_match": {"good_internal": "sulphur"}, "pct": 20.0, "label": "Composite Drill Bits", "source": "research:mining_yield"},
		{"id": "yield_bauxite_ore", "domain": "recipe_output", "target_match": {"good_internal": "bauxite_ore"}, "pct": 20.0, "label": "Composite Drill Bits", "source": "research:mining_yield"},
	],
	# ── Flavor-node benefits wired to behaviour (2026-06-19). 41 of the 47
	# design-intent nodes; 5 transport-throughput + 1 gas-plant node have no engine
	# system yet and stay description-only. market_price applies on sale revenue;
	# transport_cost applies in TransportService; the rest use existing hooks.
	"Automated Mine Dispatch": {"id": "rn_automated_mine_dispatch", "domain": "recipe_output", "target_match": {"building_id": "b_001"}, "pct": 10.0, "label": "Automated Mine Dispatch", "source": "research_node"},
	"Fractional Distillation": {"id": "rn_fractional_distillation", "domain": "recipe_output", "target_match": {"building_id": "b_011"}, "pct": 5.0, "label": "Fractional Distillation", "source": "research_node"},
	"Catalytic Cracking": {"id": "rn_catalytic_cracking", "domain": "building_power", "target_match": {"building_id": "b_011"}, "pct": -5.0, "label": "Catalytic Cracking", "source": "research_node"},
	"Polymer Feedstocks": {"id": "rn_polymer_feedstocks", "domain": "recipe_output", "target_match": {"building_id": "b_013"}, "pct": 5.0, "label": "Polymer Feedstocks", "source": "research_node"},
	"Solvent Recovery": {"id": "rn_solvent_recovery", "domain": "maintenance", "target_match": {"building_id": "b_011"}, "pct": -10.0, "duration_turns": 20, "label": "Solvent Recovery", "source": "research_node"},
	"Advanced Elastomers": {"id": "rn_advanced_elastomers", "domain": "market_price", "target_match": {"good_internal": "rubber"}, "pct": 5.0, "duration_turns": 20, "label": "Advanced Elastomers", "source": "research_node"},
	"Basic Blast Furnaces": {"id": "rn_basic_blast_furnaces", "domain": "recipe_output", "target_match": {"building_id": "b_002"}, "pct": 5.0, "label": "Basic Blast Furnaces", "source": "research_node"},
	"Chlor Alkali Cells": {"id": "rn_chlor_alkali_cells", "domain": "recipe_output", "target_match": {"building_id": "b_020"}, "pct": 5.0, "label": "Chlor Alkali Cells", "source": "research_node"},
	"Acid Gas Scrubbing": {"id": "rn_acid_gas_scrubbing", "domain": "labour_headcount", "target_match": {"building_id": "b_012"}, "pct": -5.0, "label": "Acid Gas Scrubbing", "source": "research_node"},
	"Industrial Salt Purification": {"id": "rn_industrial_salt_purification", "domain": "recipe_output", "target_match": {"building_id": "b_012"}, "pct": 25.0, "duration_turns": 20, "label": "Industrial Salt Purification", "source": "research_node"},
	"Ceramic Catalyst Supports": {"id": "rn_ceramic_catalyst_supports", "domain": "building_power", "target_match": {"building_id": "b_012"}, "pct": -5.0, "label": "Ceramic Catalyst Supports", "source": "research_node"},
	"Precision Reagent Handling": {"id": "rn_precision_reagent_handling", "domain": "maintenance", "target_match": {"building_id": "b_012"}, "pct": -10.0, "duration_turns": 20, "label": "Precision Reagent Handling", "source": "research_node"},
	"Sterile Fermentation": {"id": "rn_sterile_fermentation", "domain": "recipe_output", "target_match": {"building_id": "b_014"}, "pct": 5.0, "label": "Sterile Fermentation", "source": "research_node"},
	"Enzyme Screening": {"id": "rn_enzyme_screening", "domain": "market_price", "target_match": {"good_internal": "plastics"}, "pct": 5.0, "duration_turns": 20, "label": "Enzyme Screening", "source": "research_node"},
	"Bioplastic Precursors": {"id": "rn_bioplastic_precursors", "domain": "maintenance", "target_match": {"building_id": "b_014"}, "pct": -10.0, "duration_turns": 20, "label": "Bioplastic Precursors", "source": "research_node"},
	"Cell Culture Automation": {"id": "rn_cell_culture_automation", "domain": "labour_headcount", "target_match": {"building_id": "b_014"}, "pct": -5.0, "label": "Cell Culture Automation", "source": "research_node"},
	"Interchangeable Tooling": {"id": "rn_interchangeable_tooling", "domain": "labour_headcount", "target_match": {"building_id": "b_009"}, "pct": -5.0, "label": "Interchangeable Tooling", "source": "research_node"},
	"Pulverized Coal Boilers": {"id": "rn_pulverized_coal_boilers", "domain": "recipe_output", "target_match": {"building_id": "b_003"}, "pct": 5.0, "label": "Pulverized Coal Boilers", "source": "research_node"},
	"Steam Turbine Upgrades": {"id": "rn_steam_turbine_upgrades", "domain": "recipe_output", "target_match": {"building_id": "b_003"}, "pct": 25.0, "duration_turns": 25, "label": "Steam Turbine Upgrades", "source": "research_node"},
	"Flue Heat Recovery": {"id": "rn_flue_heat_recovery", "domain": "building_power", "target_match": {"building_id": "b_003"}, "pct": -10.0, "label": "Flue Heat Recovery", "source": "research_node"},
	"Grid Synchronous Generation": [{"id": "rn_grid_synchronous_generation_0", "domain": "maintenance", "target_match": {"building_id": "b_003"}, "pct": -8.0, "duration_turns": 20, "label": "Grid Synchronous Generation", "source": "research_node"}, {"id": "rn_grid_synchronous_generation_1", "domain": "maintenance", "target_match": {"building_id": "b_024"}, "pct": -8.0, "duration_turns": 20, "label": "Grid Synchronous Generation", "source": "research_node"}, {"id": "rn_grid_synchronous_generation_2", "domain": "maintenance", "target_match": {"building_id": "b_025"}, "pct": -8.0, "duration_turns": 20, "label": "Grid Synchronous Generation", "source": "research_node"}, {"id": "rn_grid_synchronous_generation_3", "domain": "maintenance", "target_match": {"building_id": "b_026"}, "pct": -8.0, "duration_turns": 20, "label": "Grid Synchronous Generation", "source": "research_node"}, {"id": "rn_grid_synchronous_generation_4", "domain": "maintenance", "target_match": {"building_id": "b_027"}, "pct": -8.0, "duration_turns": 20, "label": "Grid Synchronous Generation", "source": "research_node"}],
	"Utility Solar Arrays": {"id": "rn_utility_solar_arrays", "domain": "recipe_output", "target_match": {"building_id": "b_024"}, "pct": 5.0, "label": "Utility Solar Arrays", "source": "research_node"},
	"Onshore Wind Control": {"id": "rn_onshore_wind_control", "domain": "recipe_output", "target_match": {"building_id": "b_025"}, "pct": 5.0, "label": "Onshore Wind Control", "source": "research_node"},
	"Battery Balancing": {"id": "rn_battery_balancing", "domain": "recipe_output", "target_match": {"building_id": "b_028"}, "pct": 10.0, "label": "Battery Balancing", "source": "research_node"},
	"Hydro Intake Design": {"id": "rn_hydro_intake_design", "domain": "recipe_output", "target_match": {"building_id": "b_027"}, "pct": 10.0, "label": "Hydro Intake Design", "source": "research_node"},
	"Renewable Dispatch Forecasting": [{"id": "rn_renewable_dispatch_forecasting_0", "domain": "recipe_output", "target_match": {"building_id": "b_024"}, "pct": 25.0, "duration_turns": 15, "label": "Renewable Dispatch Forecasting", "source": "research_node"}, {"id": "rn_renewable_dispatch_forecasting_1", "domain": "recipe_output", "target_match": {"building_id": "b_025"}, "pct": 25.0, "duration_turns": 15, "label": "Renewable Dispatch Forecasting", "source": "research_node"}, {"id": "rn_renewable_dispatch_forecasting_2", "domain": "recipe_output", "target_match": {"building_id": "b_026"}, "pct": 25.0, "duration_turns": 15, "label": "Renewable Dispatch Forecasting", "source": "research_node"}, {"id": "rn_renewable_dispatch_forecasting_3", "domain": "recipe_output", "target_match": {"building_id": "b_027"}, "pct": 25.0, "duration_turns": 15, "label": "Renewable Dispatch Forecasting", "source": "research_node"}],
	"Pipe Trench Standards": {"id": "rn_pipe_trench_standards", "domain": "maintenance", "target_match": {"building_id": "b_017"}, "pct": -10.0, "duration_turns": 20, "label": "Pipe Trench Standards", "source": "research_node"},
	"Integrated Utility Corridors": {"id": "rn_integrated_utility_corridors", "domain": "maintenance", "pct": -5.0, "duration_turns": 20, "label": "Integrated Utility Corridors", "source": "research_node"},
	"Depot Scheduling": {"id": "rn_depot_scheduling", "domain": "recipe_output", "target_match": {"building_id": "b_004"}, "pct": 5.0, "label": "Depot Scheduling", "source": "research_node"},
	"Route Optimization": {"id": "rn_route_optimization", "domain": "transport_cost", "pct": -10.0, "duration_turns": 20, "label": "Route Optimization", "source": "research_node"},
	"Cold Chain Handling": {"id": "rn_cold_chain_handling", "domain": "transport_cost", "pct": -5.0, "duration_turns": 20, "label": "Cold Chain Handling", "source": "research_node"},
	"Spot Price Reporting": {"id": "rn_spot_price_reporting", "domain": "market_price", "pct": 5.0, "duration_turns": 20, "label": "Spot Price Reporting", "source": "research_node"},
	"Forward Contracts": {"id": "rn_forward_contracts", "domain": "market_price", "target_match": {"good_internal": "steel"}, "pct": 5.0, "duration_turns": 20, "label": "Forward Contracts", "source": "research_node"},
	"Risk Desk Procedures": {"id": "rn_risk_desk_procedures", "domain": "market_price", "pct": 5.0, "duration_turns": 15, "label": "Risk Desk Procedures", "source": "research_node"},
	"Maintenance Budgeting": {"id": "rn_maintenance_budgeting", "domain": "maintenance", "pct": -10.0, "duration_turns": 20, "label": "Maintenance Budgeting", "source": "research_node"},
	"Integrated Operations Planning": {"id": "rn_integrated_operations_planning", "domain": "recipe_output", "pct": 5.0, "label": "Integrated Operations Planning", "source": "research_node"},
	"Shift Supervisors": {"id": "rn_shift_supervisors", "domain": "labour_headcount", "target_match": {"building_id": "b_001"}, "pct": -5.0, "label": "Shift Supervisors", "source": "research_node"},
	"Safety Training": {"id": "rn_safety_training", "domain": "labour_headcount", "pct": -5.0, "label": "Safety Training", "source": "research_node"},
	"Specialist Apprenticeships": {"id": "rn_specialist_apprenticeships", "domain": "recipe_output", "target_match": {"building_id": "b_009"}, "pct": 5.0, "label": "Specialist Apprenticeships", "source": "research_node"},
	"Union Liaison Offices": {"id": "rn_union_liaison_offices", "domain": "maintenance", "pct": -10.0, "duration_turns": 20, "label": "Union Liaison Offices", "source": "research_node"},
	"Continuous Improvement Teams": [
		{"id": "rn_cit_high_tech", "domain": "labour_headcount", "target_match": {"building_id": "b_010"}, "pct": -10.0, "label": "Continuous Improvement Teams", "source": "research_node"},
		{"id": "rn_cit_assembly", "domain": "labour_headcount", "target_match": {"building_id": "b_009"}, "pct": -10.0, "label": "Continuous Improvement Teams", "source": "research_node"},
	],
	# ── transport throughput (raises a mode's per-tile capacity → less congestion) ──
	"Reinforced Roadbeds": {"id": "rn_reinforced_roadbeds", "domain": "transport_throughput", "target_match": {"mode": "roads"}, "pct": 5.0, "label": "Reinforced Roadbeds", "source": "research_node"},
	"High Pressure Mains": {"id": "rn_high_pressure_mains", "domain": "transport_throughput", "target_match": {"mode": "pipes"}, "pct": 5.0, "label": "High Pressure Mains", "source": "research_node"},
	"Containerized Freight": {"id": "rn_containerized_freight", "domain": "transport_throughput", "target_match": {"mode": "rail"}, "pct": 10.0, "label": "Containerized Freight", "source": "research_node"},
	"Autonomous Dispatch Rooms": {"id": "rn_autonomous_dispatch_rooms", "domain": "transport_throughput", "target_match": {"mode": "rail"}, "pct": 5.0, "label": "Autonomous Dispatch Rooms", "source": "research_node"},
	"Substation Layouts": {"id": "rn_substation_layouts", "domain": "transport_throughput", "target_match": {"mode": "cables"}, "pct": 5.0, "label": "Substation Layouts", "source": "research_node"},
}

# Standing deposit penalty per extraction good — a permanent recipe_output tile on
# the mined good ("exhausted surface deposits"). Registered at match start and after
# every state reset so it's always live; mining-yield research (above) adds +20%
# tiles that stack additively against it. Keyed by good internal_name. Goods NOT
# listed (crude_oil, lithium_ore, …) are exempt and mine at full yield.
const EXTRACTION_PENALTY_PCT := {
	"coal": -50.0, "iron_ore": -50.0, "copper_ore": -50.0, "limestone": -50.0,
	"sand": -50.0, "basic_salt": -50.0, "ree_ore": -50.0, "alloy_ore": -50.0,
	"sulphur": -30.0, "bauxite_ore": -30.0,
}

signal modifiers_changed()

# id -> modifier dict
var _modifiers: Dictionary = {}
# Pruned/expired modifiers, capped FIFO — the bell + future top-bar history.
var _history: Array = []
# Monotonic id when the caller doesn't supply one.
var _next_id: int = 1


func _ready() -> void:
	await get_tree().process_frame
	TurnManager.phase_started.connect(_on_phase_started)
	EventScheduler.event_fired.connect(_on_event_fired)
	MatchState.unlock_granted.connect(_on_unlock_granted)
	MatchState.state_reset.connect(_on_state_reset)
	_register_extraction_penalties()

# A new match clears the registry, then the standing deposit penalties are
# re-seeded (they're a baseline game rule, not earned/saved player state).
func _on_state_reset() -> void:
	reset()
	_register_extraction_penalties()

# Seed the permanent per-good deposit-penalty tiles. Idempotent — add() keys by id,
# so re-running just refreshes them to the current EXTRACTION_PENALTY_PCT values.
func _register_extraction_penalties() -> void:
	for good_internal in EXTRACTION_PENALTY_PCT:
		var disp := str(good_internal)
		var g: Dictionary = Catalog.get_good_by_internal_name(str(good_internal))
		if not g.is_empty():
			disp = str(g.get("display_name", disp))
		add({
			"id": "deposit_penalty_%s" % good_internal,
			"domain": "recipe_output",
			"target_match": {"good_internal": str(good_internal)},
			"pct": float(EXTRACTION_PENALTY_PCT[good_internal]),
			"label": "Exhausted %s deposits" % disp,
			"source": "deposit_penalty",
		})

# A research unlock that maps to a modifier grants it on earn (condition or free
# pick). One-shot: grant_unlock never re-fires for an already-unlocked title, so
# the timed bonus lands exactly once.
func _on_unlock_granted(title: String, _description: String, _via_condition: bool) -> void:
	if not UNLOCK_MODIFIERS.has(title):
		return
	var spec = UNLOCK_MODIFIERS[title]
	if spec is Array:
		for m in spec:
			add(m)
	else:
		add(spec)


# ── Public API ────────────────────────────────────────────────────────────

## Add or replace a modifier. Returns the canonical id.
## Modifier shape (every field optional except domain):
##   id, label, source            display + bookkeeping
##   domain                       e.g. "recipe_output", "transport_cost",
##                                "market_price", "construction_cost",
##                                "maintenance", "recipe_input"
##   target                       specific key, or "*" (default) for "all
##                                in this domain"
##   target_match                 Dictionary of {ctx_key: required_value}
##                                evaluated against the caller's ctx; the
##                                modifier applies only when every entry matches
##   mult                         multiplier (default 1.0)
##   add                          additive delta (default 0.0)
##   expires_turn                 absolute turn (0 = never expires)
##   duration_turns               convenience: set expires_turn from now
func add(modifier: Dictionary) -> String:
	var m := modifier.duplicate(true)
	if not m.has("id") or str(m.id) == "":
		m.id = "mod_%d" % _next_id
		_next_id += 1
	m["mult"] = float(m.get("mult", 1.0))
	m["add"] = float(m.get("add", 0.0))
	m["pct"] = float(m.get("pct", 0.0))
	m["domain"] = str(m.get("domain", ""))
	m["target"] = str(m.get("target", "*"))
	if not m.has("target_match"):
		m["target_match"] = {}
	# duration_turns convenience.
	if m.has("duration_turns") and not m.has("expires_turn"):
		var dur := int(m.duration_turns)
		if dur > 0:
			m["expires_turn"] = int(TurnManager.current_turn) + dur
	if not m.has("expires_turn"):
		m["expires_turn"] = 0
	m["added_turn"] = int(TurnManager.current_turn)
	_modifiers[str(m.id)] = m
	modifiers_changed.emit()
	return str(m.id)

## Remove a modifier early. Returns false if it wasn't active.
func remove(id: String) -> bool:
	if not _modifiers.has(id):
		return false
	_modifiers.erase(id)
	modifiers_changed.emit()
	return true

## Snapshot of active modifiers — for the future top-bar surface, the bell row
## tooltips, the recipe-card hover, the construction-cost breakdown.
func active() -> Array:
	return _modifiers.values()

func active_count() -> int:
	return _modifiers.size()

func history() -> Array:
	return _history.duplicate()

func has(id: String) -> bool:
	return _modifiers.has(id)

## Wipe every modifier (state_reset, scenario start, load fallback).
func reset() -> void:
	_modifiers.clear()
	_history.clear()
	_next_id = 1
	modifiers_changed.emit()

## Resolve all modifiers in `domain` matching `target`/`ctx` against a base value.
## Returns (base + sum_adds) * prod_mults. Hot path: empty registry short-circuits.
func apply(domain: String, target: String, base: float, ctx: Dictionary = {}) -> float:
	if _modifiers.is_empty():
		return base
	var add_sum := 0.0
	var mult := 1.0
	var pct_sum := 0.0
	for m in _modifiers.values():
		if str(m.domain) != domain:
			continue
		if not _target_matches(m, target, ctx):
			continue
		add_sum += float(m.add)
		mult *= float(m.mult)
		pct_sum += float(m.get("pct", 0.0))
	if add_sum == 0.0 and mult == 1.0 and pct_sum == 0.0:
		return base
	return (base + add_sum) * mult * (1.0 + pct_sum / 100.0)

## Net percentage effect (the additive `pct` channel) of every modifier in
## `domain` matching `target`/`ctx`, plus a per-modifier breakdown — what the
## recipe card's net-modifier indicator shows and its hover tooltip lists. Pcts
## sum: a −10% and a +15% return net 5.0. Returns {"net": float, "parts": Array}
## where each part is {"label": String, "pct": float}.
func resolve_pct(domain: String, target: String, ctx: Dictionary = {}) -> Dictionary:
	var net := 0.0
	var parts: Array = []
	for m in _modifiers.values():
		if str(m.domain) != domain:
			continue
		if not _target_matches(m, target, ctx):
			continue
		var p := float(m.get("pct", 0.0))
		if p == 0.0:
			continue
		net += p
		parts.append({"label": str(m.get("label", m.get("id", ""))), "pct": p})
	return {"net": net, "parts": parts}


# ── EventScheduler wiring (events can carry modifier payloads) ────────────

func _on_event_fired(event: Dictionary) -> void:
	if not event.has("modifiers"):
		return
	var mods = event.get("modifiers", [])
	if not (mods is Array):
		return
	for m in mods:
		if m is Dictionary:
			add(m)


# ── Per-turn pruning ──────────────────────────────────────────────────────

func _on_phase_started(phase: int) -> void:
	if phase == TurnManager.Phase.NARRATIVE:
		_prune_expired()

func _prune_expired() -> void:
	var turn := int(TurnManager.current_turn)
	var to_drop: Array = []
	for id in _modifiers.keys():
		var m: Dictionary = _modifiers[id]
		var exp := int(m.get("expires_turn", 0))
		if exp > 0 and turn >= exp:
			to_drop.append(id)
	if to_drop.is_empty():
		return
	for id in to_drop:
		var dropped: Dictionary = _modifiers[id].duplicate(true)
		dropped["dropped_turn"] = turn
		_history.append(dropped)
		while _history.size() > HISTORY_CAP:
			_history.pop_front()
		_modifiers.erase(id)
	modifiers_changed.emit()


# ── Matching ──────────────────────────────────────────────────────────────

func _target_matches(m: Dictionary, target: String, ctx: Dictionary) -> bool:
	var mod_target := str(m.get("target", "*"))
	if mod_target != "*" and mod_target != target:
		return false
	var match_dict: Dictionary = m.get("target_match", {})
	if match_dict.is_empty():
		return true
	for key in match_dict.keys():
		if str(ctx.get(key, "")) != str(match_dict[key]):
			return false
	return true


# ── Save / load (orchestrated by SaveLoad) ────────────────────────────────

func export_state() -> Dictionary:
	return {
		"modifiers": _modifiers.duplicate(true),
		"history": _history.duplicate(true),
		"next_id": _next_id,
	}

func import_state(d: Dictionary) -> void:
	_modifiers = d.get("modifiers", {}).duplicate(true)
	_history = d.get("history", []).duplicate(true)
	_next_id = int(d.get("next_id", 1))
	# The standing deposit penalties are a baseline rule, not saved player state —
	# re-seed them so loading a save (or a pre-feature one that lacks them) keeps
	# extraction penalised. Idempotent: add() keys by id.
	_register_extraction_penalties()
	modifiers_changed.emit()
