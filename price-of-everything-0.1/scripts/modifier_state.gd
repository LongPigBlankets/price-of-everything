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

# Research unlocks that grant a standing modifier when earned. Keyed by
# `research_node_id` from research_unlocks.csv — the node's PERMANENT handle, assigned by
# tools/assign_research_ids.py and never reused. It used to be keyed by display title,
# which meant renaming a node silently deadened its effects with no test failing; that is
# how five authored oil-extraction bonuses sat inert. The title now rides along as a
# trailing comment for readability only — it is not looked up. Callers still pass titles
# (saves store those); both entry points resolve via MatchState.research_node_id_for_title.
# Both the condition path
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
	"research_mining_006": {  # Mining Mastery
		"id": "mining_mastery_bonus", "domain": "recipe_output",
		"target_match": {"recipe_type": "mineral mining"}, "pct": 5.0,
		"duration_turns": 30,
		"label": "Mining Mastery: +5% mining output",
		"source": "research:mining_mastery",
	},
	"research_inorg_013": {  # Continuous-Flow Reactors
		"id": "cfr_chem_output", "domain": "recipe_output",
		"target_match": {"building_id": "b_012"}, "pct": 5.0,
		"label": "Continuous-Flow Reactors: +5% chemical-plant output",
		"source": "research:continuous_flow_reactors",
	},
	"research_petro_018": {  # Continuous Catalyst Regeneration
		"id": "ccr_refinery_output", "domain": "recipe_output",
		"target_match": {"building_id": "b_011"}, "pct": 5.0,
		"label": "Continuous Catalyst Regeneration: +5% refinery output",
		"source": "research:continuous_catalyst_regeneration",
	},
	"research_mfg_023": {  # Atomic Layer Deposition
		"id": "ald_hightech_output", "domain": "recipe_output",
		"target_match": {"building_id": "b_010"}, "pct": 5.0,
		"label": "Atomic Layer Deposition: +5% high-tech output",
		"source": "research:atomic_layer_deposition",
	},
	"research_mfg_025": {  # Coordinated Robot Handoff
		"id": "crh_assembly_output", "domain": "recipe_output",
		"target_match": {"building_id": "b_009"}, "pct": 5.0,
		"label": "Coordinated Robot Handoff: +5% assembly-plant output",
		"source": "research:coordinated_robot_handoff",
	},
	# ── building power consumption ───────────────────────────────────────
	"research_metal_010": {  # Pulverised Carbon Injection
		"id": "pci_furnace_power", "domain": "building_power",
		"target_match": {"building_id": "b_002"}, "pct": -20.0,
		"label": "Pulverised Carbon Injection: −20% furnace power",
		"source": "research:pulverised_carbon_injection",
	},
	"research_metal_013": {  # Scrap Preheating Towers
		"id": "preheat_eaf_power", "domain": "building_power",
		"target_match": {"building_id": "b_008"}, "pct": -20.0,
		"label": "Scrap Preheating Towers: −20% EAF power",
		"source": "research:scrap_preheating_towers",
	},
	"research_inorg_022": {  # Energy-Recovery Devices
		"id": "erd_desal_power", "domain": "building_power",
		"target_match": {"building_id": "b_021"}, "pct": -50.0,
		"label": "Energy-Recovery Devices: −50% desalination power",
		"source": "research:energy_recovery_devices",
	},
	# ── labour headcount ─────────────────────────────────────────────────
	"research_mfg_015": [  # Lights-Out Automation
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
	"research_hcpower_009": {  # Combined Heat & Power
		"id": "chp_maintenance", "domain": "maintenance",
		"target": "*", "pct": -5.0,
		"label": "Combined Heat & Power: −5% maintenance",
		"source": "research:combined_heat_power",
	},
	# ── mining-yield research: +15% recipe_output tiles on the mined good,
	# stacking ADDITIVELY with that good's standing deposit penalty. Common
	# deposits start at −30% and have two recovery steps; bauxite and sulphur
	# start at −15% and have one. Matched by the good's internal name, same as
	# the deposit penalties below.
	"research_mining_001": {  # Improved Coal Mining
		"id": "yield_coal", "domain": "recipe_output",
		"target_match": {"good_internal": "coal"}, "pct": 15.0,
		"label": "Improved Coal Mining", "source": "research:mining_yield",
	},
	"research_mining_002": {  # Beneficiated Iron Mining
		"id": "yield_iron_ore", "domain": "recipe_output",
		"target_match": {"good_internal": "iron_ore"}, "pct": 15.0,
		"label": "Beneficiated Iron Mining", "source": "research:mining_yield",
	},
	"research_mining_004": {  # Copper Froth Flotation
		"id": "yield_copper_ore", "domain": "recipe_output",
		"target_match": {"good_internal": "copper_ore"}, "pct": 15.0,
		"label": "Copper Froth Flotation", "source": "research:mining_yield",
	},
	"research_mining_003": [  # Deep Seam Surveying
		{"id": "yield_limestone", "domain": "recipe_output", "target_match": {"good_internal": "limestone"}, "pct": 15.0, "label": "Deep Seam Surveying", "source": "research:mining_yield"},
		{"id": "yield_sand", "domain": "recipe_output", "target_match": {"good_internal": "sand"}, "pct": 15.0, "label": "Deep Seam Surveying", "source": "research:mining_yield"},
		{"id": "yield_basic_salt", "domain": "recipe_output", "target_match": {"good_internal": "basic_salt"}, "pct": 15.0, "label": "Deep Seam Surveying", "source": "research:mining_yield"},
	],
	"research_mining_007": [  # Rare Vein Prospecting
		{"id": "yield_ree_ore", "domain": "recipe_output", "target_match": {"good_internal": "ree_ore"}, "pct": 15.0, "label": "Rare Vein Prospecting", "source": "research:mining_yield"},
		{"id": "yield_alloy_ore", "domain": "recipe_output", "target_match": {"good_internal": "alloy_ore"}, "pct": 15.0, "label": "Rare Vein Prospecting", "source": "research:mining_yield"},
	],
	"research_mining_010": [  # Composite Drill Bits
		{"id": "yield_ree_ore_2", "domain": "recipe_output", "target_match": {"good_internal": "ree_ore"}, "pct": 15.0, "label": "Composite Drill Bits", "source": "research:mining_yield"},
		{"id": "yield_alloy_ore_2", "domain": "recipe_output", "target_match": {"good_internal": "alloy_ore"}, "pct": 15.0, "label": "Composite Drill Bits", "source": "research:mining_yield"},
		{"id": "yield_sulphur", "domain": "recipe_output", "target_match": {"good_internal": "sulphur"}, "pct": 15.0, "label": "Composite Drill Bits", "source": "research:mining_yield"},
		{"id": "yield_bauxite_ore", "domain": "recipe_output", "target_match": {"good_internal": "bauxite_ore"}, "pct": 15.0, "label": "Composite Drill Bits", "source": "research:mining_yield"},
	],
	# ── Flavor-node benefits wired to behaviour (2026-06-19). 41 of the 47
	# design-intent nodes; 5 transport-throughput + 1 gas-plant node have no engine
	# system yet and stay description-only. market_price applies on sale revenue;
	# transport_cost applies in TransportService; the rest use existing hooks.
	"research_mining_005": [  # Automated Mine Dispatch
		{"id": "yield_coal_2", "domain": "recipe_output", "target_match": {"good_internal": "coal"}, "pct": 15.0, "label": "Automated Mine Dispatch", "source": "research:mining_yield"},
		{"id": "yield_iron_ore_2", "domain": "recipe_output", "target_match": {"good_internal": "iron_ore"}, "pct": 15.0, "label": "Automated Mine Dispatch", "source": "research:mining_yield"},
		{"id": "yield_copper_ore_2", "domain": "recipe_output", "target_match": {"good_internal": "copper_ore"}, "pct": 15.0, "label": "Automated Mine Dispatch", "source": "research:mining_yield"},
		{"id": "yield_limestone_2", "domain": "recipe_output", "target_match": {"good_internal": "limestone"}, "pct": 15.0, "label": "Automated Mine Dispatch", "source": "research:mining_yield"},
		{"id": "yield_sand_2", "domain": "recipe_output", "target_match": {"good_internal": "sand"}, "pct": 15.0, "label": "Automated Mine Dispatch", "source": "research:mining_yield"},
		{"id": "yield_basic_salt_2", "domain": "recipe_output", "target_match": {"good_internal": "basic_salt"}, "pct": 15.0, "label": "Automated Mine Dispatch", "source": "research:mining_yield"},
	],
	"research_petro_001": {"id": "rn_fractional_distillation", "domain": "recipe_output", "target_match": {"building_id": "b_011"}, "pct": 5.0, "label": "Fractional Distillation", "source": "research_node"},  # Fractional Distillation
	"research_petro_002": {"id": "rn_catalytic_cracking", "domain": "building_power", "target_match": {"building_id": "b_011"}, "pct": -5.0, "label": "Catalytic Cracking", "source": "research_node"},  # Catalytic Cracking
	# ── Oil extraction (b_032 oil_well · b_033 offshore_oil_platform · b_034 fracking_oil_well).
	# These five were authored in research_unlocks.csv with explicit numbers but never wired,
	# so the player unlocked them and nothing happened — crude oil was the only good in the
	# game with no working output research. Deposit life is unaffected by all of them:
	# Production charges the deposit its BASE rate (see production._produce_outputs).
	# "all oil extraction" is matched on the OUTPUT GOOD so it covers all three rigs at once.
	"research_petro_006": [  # Directional & Horizontal Drilling
		{"id": "rn_directional_drilling_well", "domain": "recipe_output", "target_match": {"building_id": "b_032"}, "pct": 10.0, "label": "Directional & Horizontal Drilling", "source": "research_node"},
		{"id": "rn_directional_drilling_frack", "domain": "recipe_output", "target_match": {"building_id": "b_034"}, "pct": 10.0, "label": "Directional & Horizontal Drilling", "source": "research_node"},
	],
	"research_petro_010": [  # Microseismic Monitoring
		{"id": "rn_microseismic_out_well", "domain": "recipe_output", "target_match": {"building_id": "b_032"}, "pct": 5.0, "label": "Microseismic Monitoring", "source": "research_node"},
		{"id": "rn_microseismic_out_frack", "domain": "recipe_output", "target_match": {"building_id": "b_034"}, "pct": 5.0, "label": "Microseismic Monitoring", "source": "research_node"},
		{"id": "rn_microseismic_maint_well", "domain": "maintenance", "target_match": {"building_id": "b_032"}, "pct": -10.0, "label": "Microseismic Monitoring", "source": "research_node"},
		{"id": "rn_microseismic_maint_frack", "domain": "maintenance", "target_match": {"building_id": "b_034"}, "pct": -10.0, "label": "Microseismic Monitoring", "source": "research_node"},
	],
	"research_petro_011": {"id": "rn_reservoir_stimulation", "domain": "recipe_output", "target_match": {"building_id": "b_032"}, "pct": 20.0, "duration_turns": 30, "label": "Reservoir Stimulation", "source": "research_node"},  # Reservoir Stimulation
	"research_petro_009": {"id": "rn_subsea_tieback", "domain": "recipe_output", "target_match": {"building_id": "b_033"}, "pct": 10.0, "label": "Subsea Tieback Systems", "source": "research_node"},  # Subsea Tieback Systems
	"research_petro_012": {"id": "rn_multiphase_subsea_boosting", "domain": "recipe_output", "target_match": {"building_id": "b_033"}, "pct": 10.0, "label": "Multiphase Subsea Boosting", "source": "research_node"},  # Multiphase Subsea Boosting
	"research_petro_013": {"id": "rn_enhanced_oil_recovery", "domain": "recipe_output", "target_match": {"good_internal": "crude_oil"}, "pct": 20.0, "duration_turns": 30, "label": "Enhanced Oil Recovery", "source": "research_node"},  # Enhanced Oil Recovery
	"research_petro_014": [  # Remote Platform Operations
		{"id": "rn_remote_platform_ops_well", "domain": "labour_headcount", "target_match": {"building_id": "b_032"}, "pct": -30.0, "label": "Remote Platform Operations", "source": "research_node"},
		{"id": "rn_remote_platform_ops_offshore", "domain": "labour_headcount", "target_match": {"building_id": "b_033"}, "pct": -30.0, "label": "Remote Platform Operations", "source": "research_node"},
		{"id": "rn_remote_platform_ops_frack", "domain": "labour_headcount", "target_match": {"building_id": "b_034"}, "pct": -30.0, "label": "Remote Platform Operations", "source": "research_node"},
	],
	"research_petro_003": {"id": "rn_polymer_feedstocks", "domain": "recipe_output", "target_match": {"building_id": "b_013"}, "pct": 5.0, "label": "Polymer Feedstocks", "source": "research_node"},  # Polymer Feedstocks
	"research_petro_004": {"id": "rn_solvent_recovery", "domain": "maintenance", "target_match": {"building_id": "b_011"}, "pct": -10.0, "duration_turns": 20, "label": "Solvent Recovery", "source": "research_node"},  # Solvent Recovery
	"research_petro_005": {"id": "rn_advanced_elastomers", "domain": "market_price", "target_match": {"good_internal": "rubber"}, "pct": 5.0, "duration_turns": 20, "label": "Advanced Elastomers", "source": "research_node"},  # Advanced Elastomers
	"research_metal_001": {"id": "rn_basic_blast_furnaces", "domain": "recipe_output", "target_match": {"building_id": "b_002"}, "pct": 5.0, "label": "Basic Blast Furnaces", "source": "research_node"},  # Basic Blast Furnaces
	"research_inorg_004": {"id": "rn_chlor_alkali_cells", "domain": "recipe_output", "target_match": {"building_id": "b_020"}, "pct": 5.0, "label": "Chlor Alkali Cells", "source": "research_node"},  # Chlor Alkali Cells
	"research_inorg_005": {"id": "rn_acid_gas_scrubbing", "domain": "labour_headcount", "target_match": {"building_id": "b_012"}, "pct": -5.0, "label": "Acid Gas Scrubbing", "source": "research_node"},  # Acid Gas Scrubbing
	"research_inorg_006": {"id": "rn_industrial_salt_purification", "domain": "recipe_output", "target_match": {"building_id": "b_012"}, "pct": 25.0, "duration_turns": 20, "label": "Industrial Salt Purification", "source": "research_node"},  # Industrial Salt Purification
	"research_inorg_007": {"id": "rn_ceramic_catalyst_supports", "domain": "building_power", "target_match": {"building_id": "b_012"}, "pct": -5.0, "label": "Ceramic Catalyst Supports", "source": "research_node"},  # Ceramic Catalyst Supports
	"research_inorg_008": {"id": "rn_precision_reagent_handling", "domain": "maintenance", "target_match": {"building_id": "b_012"}, "pct": -10.0, "duration_turns": 20, "label": "Precision Reagent Handling", "source": "research_node"},  # Precision Reagent Handling
	# Silica line off High Strength Glassmaking. Matched on the OUTPUT good rather than the
	# building, so both concrete routes benefit (r_029 in the furnace, r_030 in the EAF)
	# rather than only whichever building happens to be running it.
	"research_inorg_002": {"id": "rn_pozzolanic_vitrification", "domain": "recipe_output", "target_match": {"good_internal": "concrete"}, "pct": 10.0, "label": "Pozzolanic Vitrification", "source": "research_node"},  # Pozzolanic Vitrification
	"research_inorg_003": [  # Micro Silica Synthesis
		{"id": "rn_micro_silica_concrete", "domain": "recipe_output", "target_match": {"good_internal": "concrete"}, "pct": 5.0, "label": "Micro Silica Synthesis", "source": "research_node"},
		{"id": "rn_micro_silica_glass", "domain": "recipe_output", "target_match": {"good_internal": "glass"}, "pct": 15.0, "label": "Micro Silica Synthesis", "source": "research_node"},
	],
	"research_biochem_001": {"id": "rn_sterile_fermentation", "domain": "recipe_output", "target_match": {"building_id": "b_014"}, "pct": 5.0, "label": "Sterile Fermentation", "source": "research_node"},  # Sterile Fermentation
	"research_biochem_002": {"id": "rn_enzyme_screening", "domain": "market_price", "target_match": {"good_internal": "plastics"}, "pct": 5.0, "duration_turns": 20, "label": "Enzyme Screening", "source": "research_node"},  # Enzyme Screening
	"research_biochem_003": {"id": "rn_bioplastic_precursors", "domain": "maintenance", "target_match": {"building_id": "b_014"}, "pct": -10.0, "duration_turns": 20, "label": "Bioplastic Precursors", "source": "research_node"},  # Bioplastic Precursors
	"research_biochem_005": {"id": "rn_cell_culture_automation", "domain": "labour_headcount", "target_match": {"building_id": "b_014"}, "pct": -5.0, "label": "Cell Culture Automation", "source": "research_node"},  # Cell Culture Automation
	"research_mfg_001": {"id": "rn_interchangeable_tooling", "domain": "labour_headcount", "target_match": {"building_id": "b_009"}, "pct": -5.0, "label": "Interchangeable Tooling", "source": "research_node"},  # Interchangeable Tooling
	"research_hcpower_001": {"id": "rn_pulverized_coal_boilers", "domain": "recipe_output", "target_match": {"building_id": "b_003"}, "pct": 5.0, "label": "Pulverized Coal Boilers", "source": "research_node"},  # Pulverized Coal Boilers
	"research_hcpower_002": {"id": "rn_steam_turbine_upgrades", "domain": "recipe_output", "target_match": {"building_id": "b_003"}, "pct": 25.0, "duration_turns": 25, "label": "Steam Turbine Upgrades", "source": "research_node"},  # Steam Turbine Upgrades
	"research_hcpower_003": {"id": "rn_flue_heat_recovery", "domain": "building_power", "target_match": {"building_id": "b_003"}, "pct": -10.0, "label": "Flue Heat Recovery", "source": "research_node"},  # Flue Heat Recovery
	"research_hcpower_004": [{"id": "rn_grid_synchronous_generation_0", "domain": "maintenance", "target_match": {"building_id": "b_003"}, "pct": -8.0, "duration_turns": 20, "label": "Grid Synchronous Generation", "source": "research_node"}, {"id": "rn_grid_synchronous_generation_1", "domain": "maintenance", "target_match": {"building_id": "b_024"}, "pct": -8.0, "duration_turns": 20, "label": "Grid Synchronous Generation", "source": "research_node"}, {"id": "rn_grid_synchronous_generation_2", "domain": "maintenance", "target_match": {"building_id": "b_025"}, "pct": -8.0, "duration_turns": 20, "label": "Grid Synchronous Generation", "source": "research_node"}, {"id": "rn_grid_synchronous_generation_3", "domain": "maintenance", "target_match": {"building_id": "b_026"}, "pct": -8.0, "duration_turns": 20, "label": "Grid Synchronous Generation", "source": "research_node"}, {"id": "rn_grid_synchronous_generation_4", "domain": "maintenance", "target_match": {"building_id": "b_027"}, "pct": -8.0, "duration_turns": 20, "label": "Grid Synchronous Generation", "source": "research_node"}],  # Grid Synchronous Generation
	"research_renew_001": {"id": "rn_utility_solar_arrays", "domain": "recipe_output", "target_match": {"building_id": "b_024"}, "pct": 5.0, "label": "Utility Solar Arrays", "source": "research_node"},  # Utility Solar Arrays
	"research_renew_002": {"id": "rn_onshore_wind_control", "domain": "recipe_output", "target_match": {"building_id": "b_025"}, "pct": 5.0, "label": "Onshore Wind Control", "source": "research_node"},  # Onshore Wind Control
	"research_renew_003": {"id": "rn_battery_balancing", "domain": "recipe_output", "target_match": {"building_id": "b_028"}, "pct": 10.0, "label": "Battery Balancing", "source": "research_node"},  # Battery Balancing
	"research_renew_004": {"id": "rn_hydro_intake_design", "domain": "recipe_output", "target_match": {"building_id": "b_027"}, "pct": 10.0, "label": "Hydro Intake Design", "source": "research_node"},  # Hydro Intake Design
	"research_renew_005": [{"id": "rn_renewable_dispatch_forecasting_0", "domain": "recipe_output", "target_match": {"building_id": "b_024"}, "pct": 25.0, "duration_turns": 15, "label": "Renewable Dispatch Forecasting", "source": "research_node"}, {"id": "rn_renewable_dispatch_forecasting_1", "domain": "recipe_output", "target_match": {"building_id": "b_025"}, "pct": 25.0, "duration_turns": 15, "label": "Renewable Dispatch Forecasting", "source": "research_node"}, {"id": "rn_renewable_dispatch_forecasting_2", "domain": "recipe_output", "target_match": {"building_id": "b_026"}, "pct": 25.0, "duration_turns": 15, "label": "Renewable Dispatch Forecasting", "source": "research_node"}, {"id": "rn_renewable_dispatch_forecasting_3", "domain": "recipe_output", "target_match": {"building_id": "b_027"}, "pct": 25.0, "duration_turns": 15, "label": "Renewable Dispatch Forecasting", "source": "research_node"}],  # Renewable Dispatch Forecasting
	"research_infra_002": {"id": "rn_pipe_trench_standards", "domain": "maintenance", "target_match": {"building_id": "b_017"}, "pct": -10.0, "duration_turns": 20, "label": "Pipe Trench Standards", "source": "research_node"},  # Pipe Trench Standards
	"research_infra_005": {"id": "rn_integrated_utility_corridors", "domain": "maintenance", "pct": -5.0, "duration_turns": 20, "label": "Integrated Utility Corridors", "source": "research_node"},  # Integrated Utility Corridors
	"research_logi_001": {"id": "rn_depot_scheduling", "domain": "road_rail_transport_cost", "pct": -10.0, "label": "Depot Scheduling: −10% road and rail transport cost", "source": "research_node"},
	"research_logi_003": {"id": "rn_route_optimization", "domain": "transport_throughput", "target_match": {"mode": "roads"}, "pct": 25.0, "label": "Route Optimization: +25% road throughput", "source": "research_node"},
	"research_logi_004": {"id": "rn_cold_chain_handling", "domain": "transport_cost", "pct": -5.0, "duration_turns": 20, "label": "Cold Chain Handling", "source": "research_node"},  # Cold Chain Handling
	"research_markets_001": {"id": "rn_spot_price_reporting", "domain": "special_order_premium", "pct": 25.0, "label": "Spot Price Reporting: +25% special-order premium", "source": "research_node"},
	"research_markets_002": {"id": "rn_forward_contracts", "domain": "market_price", "target_match": {"good_internal": "steel"}, "pct": 5.0, "duration_turns": 20, "label": "Forward Contracts", "source": "research_node"},  # Forward Contracts
	"research_markets_003": {"id": "rn_risk_desk", "domain": "market_input_transport", "pct": -25.0, "label": "Risk Desk Procedures: −25% market-input shipping", "source": "research_node"},
	"research_markets_004": {"id": "rn_maintenance_budgeting", "domain": "maintenance", "pct": -10.0, "duration_turns": 20, "label": "Maintenance Budgeting", "source": "research_node"},  # Maintenance Budgeting
	"research_markets_005": [{"id": "rn_integrated_ops_maintenance", "domain": "maintenance", "pct": -5.0, "label": "Integrated Operations Planning: −5% maintenance", "source": "research_node"}, {"id": "rn_integrated_ops_labour", "domain": "labour_headcount", "pct": -5.0, "label": "Integrated Operations Planning: −5% labour", "source": "research_node"}],
	"research_people_001": {"id": "rn_shift_supervisors", "domain": "labour_headcount", "target_match": {"building_id": "b_001"}, "pct": -5.0, "label": "Shift Supervisors", "source": "research_node"},  # Shift Supervisors
	"research_people_002": [{"id": "rn_safety_training_maintenance", "domain": "maintenance", "pct": -5.0, "label": "Safety Training: −5% maintenance", "source": "research_node"}, {"id": "rn_safety_training_labour", "domain": "labour_headcount", "pct": -5.0, "label": "Safety Training: −5% labour", "source": "research_node"}],
	# People-management track: global head-count trims earned purely by scale (total
	# buildings owned), not by a specific building type. -10% at 3 buildings, another
	# -10% at 12 — see docs/economy-bootstrap-findings.md.
	"research_people_006": {"id": "rn_operational_team_managers", "domain": "labour_headcount", "pct": -10.0, "label": "Operational Team Managers", "source": "research_node"},  # Operational Team Managers
	"research_people_007": {"id": "rn_shift_handover_documentation", "domain": "labour_headcount", "pct": -10.0, "label": "Shift Handover Documentation", "source": "research_node"},  # Shift Handover Documentation
	"research_people_003": {"id": "rn_specialist_apprenticeships", "domain": "recipe_output", "target_match": {"building_id": "b_009"}, "pct": 5.0, "label": "Specialist Apprenticeships", "source": "research_node"},  # Specialist Apprenticeships
	"research_people_004": {"id": "rn_union_liaison_offices", "domain": "maintenance", "pct": -10.0, "duration_turns": 20, "label": "Union Liaison Offices", "source": "research_node"},  # Union Liaison Offices
	"research_people_005": [  # Continuous Improvement Teams
		{"id": "rn_continuous_improvement", "domain": "recipe_output", "pct": 5.0, "label": "Continuous Improvement Teams: +5% building output", "source": "research_node"},
	],
	# ── transport throughput (raises a mode's per-tile capacity → less congestion) ──
	"research_infra_001": {"id": "rn_reinforced_roadbeds", "domain": "transport_throughput", "target_match": {"mode": "roads"}, "pct": 25.0, "label": "Reinforced Roadbeds", "source": "research_node"},  # Reinforced Roadbeds
	"research_infra_003": {"id": "rn_high_pressure_mains", "domain": "transport_throughput", "target_match": {"mode": "pipes"}, "pct": 25.0, "label": "High Pressure Mains", "source": "research_node"},  # High Pressure Mains
	# The shipping line trims the AD VALOREM, and its cuts are RELATIVE: percentage points
	# against a 3% base would overshoot to nothing (3 − 1 − 1 = 1%, then PNA's −20% on top).
	# Modifiers.apply sums pcts within a domain, so these three total −40% off the scheduled
	# rate — 3% fully teched becomes 1.8%. See docs/early-game-onboarding-spec.md §4.2b.
	"research_logi_011": {"id": "rn_groupage_contracts", "domain": "port_ad_valorem_fee", "pct": -10.0, "label": "Groupage Contracts: −10% port ad valorem fee", "source": "research_node"},
	"research_logi_002": {"id": "rn_multimodal_containerized_freight", "domain": "port_ad_valorem_fee", "pct": -10.0, "label": "Multimodal Containerized Freight: −10% port ad valorem fee", "source": "research_node"},
	"research_logi_005": [{"id": "rn_autonomous_dispatch_roads", "domain": "labour_headcount", "target_match": {"building_id": "b_005"}, "pct": -10.0, "label": "Autonomous Dispatch Rooms", "source": "research_node"}, {"id": "rn_autonomous_dispatch_rail", "domain": "labour_headcount", "target_match": {"building_id": "b_019"}, "pct": -10.0, "label": "Autonomous Dispatch Rooms", "source": "research_node"}],  # Autonomous Dispatch Rooms
	"research_logi_009": {"id": "rn_smart_shipping_contracts", "domain": "port_throughput", "pct": 25.0, "label": "Smart Shipping Contracts: +25% port throughput", "source": "research_node"},
	"research_logi_010": [
		{"id": "rn_port_network_ad_valorem", "domain": "port_ad_valorem_fee", "pct": -20.0, "label": "Port Network Acquisition: −20% port ad valorem fee", "source": "research_node"},
		{"id": "rn_port_network_per_turn", "domain": "port_per_turn_fee", "pct": -50.0, "label": "Port Network Acquisition: −50% per-turn port fee", "source": "research_node"},
	],
	# Logistics warehouse capacity (tile storage)
	# Pallet Racking Systems / Automated Storage & Retrieval no longer grant a tile_storage
	# modifier — they now raise the tile's WAREHOUSE LEVEL directly (see Stockpile.get_capacity
	# / EconomyConfig.WAREHOUSE_STORAGE_CAP), so no standing modifier is registered here.
	"research_infra_004": {"id": "rn_substation_layouts", "domain": "transport_throughput", "target_match": {"mode": "cables"}, "pct": 25.0, "label": "Substation Layouts", "source": "research_node"},  # Substation Layouts
	"research_infra_020": {"id": "rn_smart_traffic_control", "domain": "transport_throughput", "target_match": {"mode": "roads"}, "pct": 25.0, "label": "Smart Traffic Control", "source": "research_node"},  # Smart Traffic Control
	"research_infra_023": {"id": "rn_electrified_rolling_stock", "domain": "transport_throughput", "target_match": {"mode": "rail"}, "pct": 25.0, "label": "Electrified Rolling Stock", "source": "research_node"},  # Electrified Rolling Stock
	"research_infra_032": {"id": "rn_leak_detection_networks", "domain": "transport_throughput", "target_match": {"mode": "pipes"}, "pct": 25.0, "label": "Leak-Detection Networks", "source": "research_node"},  # Leak-Detection Networks
	"research_infra_035": {"id": "rn_dynamic_line_rating", "domain": "transport_throughput", "target_match": {"mode": "cables"}, "pct": 25.0, "label": "Dynamic Line Rating", "source": "research_node"},  # Dynamic Line Rating
	# ── repurposed placeholder rewards (wired 2026-06-28) ──
	"research_mfg_020": {"id": "rn_automated_guided_assembly", "domain": "labour_headcount", "target_match": {"building_id": "b_007"}, "pct": -5.0, "label": "Automated Guided Assembly", "source": "research_node"},  # Automated Guided Assembly
	"research_mfg_024": {"id": "rn_fully_automated_fabs", "domain": "recipe_output", "target_match": {"building_id": "b_010"}, "pct": 10.0, "label": "Fully-Automated Fabs", "source": "research_node"},  # Fully-Automated Fabs
	"research_mfg_013": {"id": "rn_high_volume_press_lines", "domain": "recipe_output", "target_match": {"building_id": "b_007"}, "pct": 5.0, "label": "High-Volume Press Lines", "source": "research_node"},  # High-Volume Press Lines
	"research_mfg_017": [{"id": "rn_jit_b007", "domain": "maintenance", "target_match": {"building_id": "b_007"}, "pct": -15.0, "label": "Just-in-Time Sequencing", "source": "research_node"}, {"id": "rn_jit_b009", "domain": "maintenance", "target_match": {"building_id": "b_009"}, "pct": -15.0, "label": "Just-in-Time Sequencing", "source": "research_node"}, {"id": "rn_jit_b010", "domain": "maintenance", "target_match": {"building_id": "b_010"}, "pct": -15.0, "label": "Just-in-Time Sequencing", "source": "research_node"}],  # Just-in-Time Sequencing
	"research_mfg_018": {"id": "rn_modular_sub_assembly", "domain": "recipe_output", "target_match": {"building_id": "b_009"}, "pct": 5.0, "label": "Modular Sub-Assembly", "source": "research_node"},  # Modular Sub-Assembly
	"research_mfg_014": {"id": "rn_multi_shift_production", "domain": "recipe_output", "target_match": {"building_id": "b_007"}, "pct": 5.0, "label": "Multi-Shift Production", "source": "research_node"},  # Multi-Shift Production
	"research_mfg_019": {"id": "rn_robotic_final_assembly", "domain": "labour_headcount", "target_match": {"building_id": "b_009"}, "pct": -10.0, "duration_turns": 20, "label": "Robotic Final Assembly", "source": "research_node"},  # Robotic Final Assembly
	"research_mfg_016": [{"id": "rn_fmc_b007", "domain": "labour_headcount", "target_match": {"building_id": "b_007"}, "pct": -10.0, "label": "Flexible Manufacturing Cells", "source": "research_node"}, {"id": "rn_fmc_b009", "domain": "labour_headcount", "target_match": {"building_id": "b_009"}, "pct": -10.0, "label": "Flexible Manufacturing Cells", "source": "research_node"}, {"id": "rn_fmc_b010", "domain": "labour_headcount", "target_match": {"building_id": "b_010"}, "pct": -10.0, "label": "Flexible Manufacturing Cells", "source": "research_node"}],  # Flexible Manufacturing Cells
	"research_renew_019": {"id": "rn_dual_axis_tracking", "domain": "recipe_output", "target_match": {"building_id": "b_024"}, "pct": 10.0, "label": "Dual-Axis Tracking Farms", "source": "research_node"},  # Dual-Axis Tracking Farms
	"research_renew_018": {"id": "rn_utility_scale_inverters", "domain": "recipe_output", "target_match": {"building_id": "b_024"}, "pct": 10.0, "label": "Utility-Scale Inverters", "source": "research_node"},  # Utility-Scale Inverters
	"research_renew_015": {"id": "rn_taller_turbine_towers", "domain": "recipe_output", "target_match": {"building_id": "b_025"}, "pct": 10.0, "label": "Taller Turbine Towers", "source": "research_node"},  # Taller Turbine Towers
	"research_renew_016": {"id": "rn_variable_pitch_control", "domain": "maintenance", "target_match": {"building_id": "b_025"}, "pct": -10.0, "duration_turns": 20, "label": "Variable-Pitch Control", "source": "research_node"},  # Variable-Pitch Control
	"research_renew_021": {"id": "rn_containerised_battery_racks", "domain": "maintenance", "target_match": {"building_id": "b_028"}, "pct": -10.0, "duration_turns": 20, "label": "Containerised Battery Racks", "source": "research_node"},  # Containerised Battery Racks
	"research_metal_016": {"id": "rn_dc_arc_conversion", "domain": "building_power", "target_match": {"building_id": "b_008"}, "pct": -5.0, "label": "DC Arc Conversion", "source": "research_node"},  # DC Arc Conversion
	"research_metal_014": {"id": "rn_foamy_slag_practice", "domain": "recipe_output", "target_match": {"building_id": "b_008"}, "pct": 5.0, "label": "Foamy Slag Practice", "source": "research_node"},  # Foamy Slag Practice
	"research_metal_008": {"id": "rn_ultra_high_power_arcs", "domain": "recipe_output", "target_match": {"building_id": "b_008"}, "pct": 10.0, "label": "Ultra-High-Power Arcs", "source": "research_node"},  # Ultra-High-Power Arcs
	"research_mining_013": {"id": "rn_bench_blasting", "domain": "recipe_output", "target_match": {"building_id": "b_001"}, "pct": 20.0, "duration_turns": 20, "label": "Bench Blasting Expansion", "source": "research_node"},  # Bench Blasting Expansion
	"research_mining_016": {"id": "rn_block_caving", "domain": "maintenance", "target_match": {"building_id": "b_001"}, "pct": -20.0, "label": "Block Caving", "source": "research_node"},  # Block Caving
	"research_mining_014": {"id": "rn_bulk_haulage_fleets", "domain": "recipe_output", "target_match": {"building_id": "b_001"}, "pct": 5.0, "label": "Bulk Haulage Fleets", "source": "research_node"},  # Bulk Haulage Fleets
	"research_mining_015": {"id": "rn_continuous_surface_miners", "domain": "building_power", "target_match": {"building_id": "b_001"}, "pct": -20.0, "label": "Continuous Surface Miners", "source": "research_node"},  # Continuous Surface Miners
	"research_inorg_017": {"id": "rn_bipolar_cell_arrays", "domain": "building_power", "target_match": {"building_id": "b_020"}, "pct": -20.0, "duration_turns": 20, "label": "Bipolar Cell Arrays", "source": "research_node"},  # Bipolar Cell Arrays
	"research_inorg_016": {"id": "rn_high_current_cell_stacks", "domain": "labour_headcount", "target_match": {"building_id": "b_020"}, "pct": -5.0, "label": "High-Current Cell Stacks", "source": "research_node"},  # High-Current Cell Stacks
	"research_inorg_015": {"id": "rn_deep_catalytic_optimisation", "domain": "building_power", "target_match": {"building_id": "b_012"}, "pct": -10.0, "label": "Deep Catalytic Optimisation", "source": "research_node"},  # Deep Catalytic Optimisation
	"research_inorg_021": {"id": "rn_multi_stage_flash_desal", "domain": "recipe_output", "target_match": {"building_id": "b_021"}, "pct": 20.0, "label": "Multi-Stage Flash Desal", "source": "research_node"},  # Multi-Stage Flash Desal
	"research_petro_017": {"id": "rn_heat_integrated_trains", "domain": "building_power", "target_match": {"building_id": "b_013"}, "pct": -10.0, "label": "Heat-Integrated Trains", "source": "research_node"},  # Heat-Integrated Trains
	"research_biochem_008": [{"id": "rn_ahf_b015", "domain": "labour_headcount", "target_match": {"building_id": "b_015"}, "pct": -5.0, "label": "Automated Harvest Fleets", "source": "research_node"}, {"id": "rn_ahf_b016", "domain": "labour_headcount", "target_match": {"building_id": "b_016"}, "pct": -5.0, "label": "Automated Harvest Fleets", "source": "research_node"}],  # Automated Harvest Fleets
	"research_hcpower_008": {"id": "rn_reheat_turbine_cycles", "domain": "recipe_output", "target_match": {"building_id": "b_003"}, "pct": 10.0, "label": "Reheat Turbine Cycles", "source": "research_node"},  # Reheat Turbine Cycles
	"research_recyc_003": {"id": "rn_tertiary_filtration", "domain": "recipe_output", "target_match": {"building_id": "b_022"}, "pct": 15.0, "label": "Tertiary Filtration", "source": "research_node"},  # Tertiary Filtration
	"research_recyc_005": {"id": "rn_zero_discharge_water", "domain": "building_power", "target_match": {"building_id": "b_022"}, "pct": -10.0, "label": "Zero-Discharge Water", "source": "research_node"},  # Zero-Discharge Water
	"research_infra_024": {"id": "rn_automated_rail_yards", "domain": "maintenance", "target_match": {"building_id": "b_019"}, "pct": -10.0, "label": "Automated Rail Yards", "source": "research_node"},  # Automated Rail Yards
	"research_infra_027": {"id": "rn_booster_pumping", "domain": "maintenance", "target_match": {"building_id": "b_017"}, "pct": -10.0, "label": "Booster Pumping Stations", "source": "research_node"},  # Booster Pumping Stations
	"research_infra_031": {"id": "rn_corrosion_resistant_linings", "domain": "maintenance", "target_match": {"building_id": "b_017"}, "pct": -10.0, "label": "Corrosion-Resistant Linings", "source": "research_node"},  # Corrosion-Resistant Linings
	"research_infra_025": {"id": "rn_distributed_power_trains", "domain": "transport_cost", "pct": -5.0, "label": "Distributed-Power Trains", "source": "research_node"},  # Distributed-Power Trains
	"research_infra_021": {"id": "rn_double_track_sidings", "domain": "maintenance", "target_match": {"building_id": "b_019"}, "pct": -10.0, "label": "Double-Track Sidings", "source": "research_node"},  # Double-Track Sidings
	"research_infra_030": {"id": "rn_double_walled_pipelines", "domain": "maintenance", "target_match": {"building_id": "b_018"}, "pct": -10.0, "label": "Double-Walled Pipelines", "source": "research_node"},  # Double-Walled Pipelines
	"research_infra_019": {"id": "rn_heavy_freight_corridors", "domain": "transport_throughput", "target_match": {"mode": "rail"}, "pct": 25.0, "label": "Heavy Freight Corridors", "source": "research_node"},  # Heavy Freight Corridors
	"research_infra_026": {"id": "rn_large_diameter_mains", "domain": "maintenance", "target_match": {"building_id": "b_018"}, "pct": -10.0, "label": "Large-Diameter Mains", "source": "research_node"},  # Large-Diameter Mains
	"research_infra_028": {"id": "rn_trunk_pipeline_networks", "domain": "transport_cost", "pct": -5.0, "label": "Trunk Pipeline Networks", "source": "research_node"},  # Trunk Pipeline Networks
}

# Standing deposit penalty per extraction good — a permanent recipe_output tile on
# the mined good ("exhausted surface deposits"). Registered at match start and after
# every state reset so it's always live; mining-yield research (above) adds +15%
# tiles that stack additively against it. Keyed by good internal_name. Goods NOT
# listed (crude_oil, lithium_ore, …) are exempt and mine at full yield.
const EXTRACTION_PENALTY_PCT := {
	"coal": -30.0, "iron_ore": -30.0, "copper_ore": -30.0, "limestone": -30.0,
	"sand": -30.0, "basic_salt": -30.0, "ree_ore": -30.0, "alloy_ore": -30.0,
	"sulphur": -15.0, "bauxite_ore": -15.0,
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
	# _on_phase_started is wired centrally by TurnManager._wire_sim_listeners so
	# the intra-phase order across sim systems is explicit, not autoload-order.
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
	apply_unlock_modifier(title)

## Apply the standing modifier(s) a research title grants (idempotent — add() keys by
## id). Called both from the unlock_granted signal AND directly by
## MatchState.grant_unlock: a title can be unlocked during game SETUP (a start's
## buildings satisfy a scale condition like "Operational Team Managers" at 3 buildings)
## at a moment this listener isn't connected yet, and grant_unlock is one-shot, so the
## signal path alone would drop the bonus forever.
## Accepts EITHER a research_node_id (what the table is keyed by) or a display title, and
## returns the node id. Titles are still the handle in saves, the tutorial detectors and a
## number of tests, so both must work until those move onto ids.
func resolve_unlock_key(title_or_id: String) -> String:
	if UNLOCK_MODIFIERS.has(title_or_id):
		return title_or_id
	return MatchState.research_node_id_for_title(title_or_id)


## The modifier spec a research node grants — a Dictionary, an Array of them, or {} if the
## node grants none. Use this instead of indexing UNLOCK_MODIFIERS directly, so callers
## holding a title keep working now that the table is keyed by id.
func unlock_spec_for(title_or_id: String) -> Variant:
	return UNLOCK_MODIFIERS.get(resolve_unlock_key(title_or_id), {})


func apply_unlock_modifier(title: String) -> void:
	var node_id := resolve_unlock_key(title)
	if node_id == "" or not UNLOCK_MODIFIERS.has(node_id):
		return
	var spec = UNLOCK_MODIFIERS[node_id]
	if spec is Array:
		for m in spec:
			add(m)
	else:
		add(spec)

# Re-apply the standing modifier of every already-unlocked research title. SaveLoad
# imports buildings (which can satisfy a scale unlock like "Operational Team Managers"
# at 3 buildings and add its modifier) BEFORE Modifiers.import_state replaces the
# registry wholesale — wiping it. grant_unlock is one-shot, so the modifier would
# otherwise be lost forever (the title shows unlocked but the bonus never lands).
# Mirrors MatchState.reapply_mission_modifiers. Only PERMANENT specs (no duration_turns)
# are re-applied: a timed bonus's remaining expiry is authoritative from the saved
# registry and must not be refreshed here. add() keys by id, so this is idempotent.
func reapply_unlock_modifiers(unlocked_titles: Dictionary) -> void:
	for title in unlocked_titles.keys():
		# Saves still store titles; resolve to the node id the table is keyed by. A title
		# that no longer exists (renamed since the save) simply finds nothing — see the
		# staged-migration note: only moving saves onto ids closes that last gap.
		var key := resolve_unlock_key(str(title))
		if key == "" or not UNLOCK_MODIFIERS.has(key):
			continue
		var spec = UNLOCK_MODIFIERS[key]
		var specs: Array = spec if spec is Array else [spec]
		for m in specs:
			if (m as Dictionary).has("duration_turns"):
				continue  # timed bonus — saved expiry is authoritative
			add(m)


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
	# duration_turns convenience. A duration counts PROCESS phases the modifier
	# actually applies to: one added in/before this turn's PROCESS (DECIDE picks)
	# already applies this turn, so it expires one turn earlier than one granted
	# after PROCESS (NARRATIVE condition unlocks), whose first application is next
	# turn. Without the phase adjustment, DECIDE-granted timed modifiers lived
	# dur+1 PROCESS phases while NARRATIVE-granted ones lived exactly dur.
	if m.has("duration_turns") and not m.has("expires_turn"):
		var dur := int(m.duration_turns)
		if dur > 0:
			var applies_this_turn: bool = TurnManager.current_phase <= TurnManager.Phase.PROCESS
			m["expires_turn"] = int(TurnManager.current_turn) + dur - (1 if applies_this_turn else 0)
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
