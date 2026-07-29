extends Node
# Centralised economic constants. All tunables for balancing live here.
# When playtesting reveals "the economy is too punishing" or "buildings are too cheap",
# this is the only file you need to edit.

# --- Player starting state ---
const STARTING_MONEY: float = 600.0

# --- Demolish / refund ---
# Share of a demolished building's MATERIAL kits returned to the player on demolish (the
# construction kit + each completed upgrade level's kit), rounded down; overflow that won't
# fit the tile stockpile is paid as cash. NO build money is returned on demolish (that's what
# Sell is for). 0.5 = half the materials back (owner spec 2026-07-05). This base is the lever a
# future advisor modifies — read it through MatchState so an advisor bonus can stack on top.
# A `var` (not const) so it can be tuned live. See MatchState.refund_cost / refund_plan / tick_demolish.
var demolish_refund_share: float = 0.5

# --- Per-building per-turn costs ---
const MAINTENANCE_PER_BUILDING: float = 1.0

# --- Labour rates (cost per worker per turn) ---
# Rebalance: unskilled:skilled:h_skilled = 1:3:10 (a highly-skilled worker costs 10x an unskilled
# one). Rates raised so per-building head-counts read in the ~1000-10000 range at the back-solved
# wage bills; head-counts were rescaled in lock-step so each building's total wage bill is unchanged.
const LABOUR_UNSKILLED_RATE: float = 0.00304
const LABOUR_SKILLED_RATE: float = 0.00912
const LABOUR_HIGH_SKILLED_RATE: float = 0.0304

# --- Labour wage growth (compounding per turn) ---
# Wages drift upward every turn: the effective rate at turn t is
#   base_rate * (1 + growth) ^ (t - 1).
# Higher-skilled labour inflates fastest, so margins compress over a long game
# and the player must keep expanding revenue to stay ahead of the wage bill.
const LABOUR_UNSKILLED_GROWTH: float = 0.0005    # +0.05%/turn
const LABOUR_SKILLED_GROWTH: float = 0.001       # +0.10%/turn
const LABOUR_HIGH_SKILLED_GROWTH: float = 0.002  # +0.20%/turn

# --- MVP labour stub: every building has these counts ---
# Remove these once buildings catalog has real employment data.
const STUB_UNSKILLED_PER_BUILDING: int = 100
const STUB_SKILLED_PER_BUILDING: int = 50
const STUB_HIGH_SKILLED_PER_BUILDING: int = 50

# --- Bankruptcy ---
const BANKRUPTCY_FLOOR: float = -10.0

# --- Market price impact (glut model) ---
# LEGACY volume-cap knobs: only the auto-sell "impact tolerance" cap
# (units_cap_for_impact) still reads these. The LIVE price-impact model is the
# per-good threshold system below (price_impact_rate + MarketState.impact_pct).
const GLUT_UNITS: int = 100
const MAX_PRICE_IMPACT_PCT: int = 10

# --- Price impact (glut / deficit) — the live model ---
# A player's NET market volume in one good in one turn moves that good's price
# once it crosses multiples of the good's BASE OUTPUT (the largest per-turn
# output among active recipes producing it, L1 unmodified —
# Catalog.base_output_for_good). E.g. copper wiring, base output 32:
#   65 units  (>2x)  → 0.1 %/turn
#   129 units (>4x)  → 0.2 %/turn
#   321 units (>10x) → 0.5 %/turn
# Net selling pushes the price DOWN (glut), net buying UP (deficit). The
# accumulated impact is capped at ±PRICE_IMPACT_CAP_PCT and, while volume stays
# at or under 2x, recovers toward 0 by price_impact_recovery() per turn. The
# impact multiplies the good's decayed base price, so it stacks on top of the
# normal per-turn drift. Thresholds are STATIC for now; later they scale with
# expected output every 10 turns. Goods with no active producing recipe have no
# base output and take no impact.
const PRICE_IMPACT_CAP_PCT: float = 40.0
const PRICE_IMPACT_RECOVERY_PCT: float = 0.1
# BANDED response, thresholds spaced out (owner ruling 2026-07-27). The bands are back —
# the continuous curve bit far too early in practice: a normal 3-factory chain sells 3x one
# building's batch, which crushed motors to the -48% floor over 75 turns purely for being
# a normal size. Volume must be genuinely excessive before the market notices:
#     > 2x  base output -> 0.1 %/turn   (a nudge — you are now moving this market)
#     > 4x               -> 0.2 %/turn
#     >10x               -> 0.5 %/turn  (flooding; hits the -40% cap in 80 turns)
# base_output is the largest per-turn batch among active recipes producing the good
# (Catalog.base_output_for_good), so the thresholds rescale with any recipe rebalance.
const PRICE_IMPACT_RATE_2X: float = 0.1
const PRICE_IMPACT_RATE_4X: float = 0.2
const PRICE_IMPACT_RATE_10X: float = 0.5

## %/turn accrual for one turn's net player market volume in one good.
func price_impact_rate(net_volume: int, base_output: int) -> float:
	if base_output <= 0:
		return 0.0
	var v := float(absi(net_volume))
	if v > 10.0 * float(base_output):
		return PRICE_IMPACT_RATE_10X
	if v > 4.0 * float(base_output):
		return PRICE_IMPACT_RATE_4X
	if v > 2.0 * float(base_output):
		return PRICE_IMPACT_RATE_2X
	return 0.0

## %/turn a good's accumulated impact bleeds back toward 0 while its volume is under the
## bite. FLAT: the depth-scaled recovery that guarded against a ratchet is unnecessary now
## accrual tops out at 0.5%/turn, and at these rates scaling it would invert the incentive —
## recovery would outrun accrual and reward pulsing production on and off.
func price_impact_recovery(_current_pct: float) -> float:
	return PRICE_IMPACT_RECOVERY_PCT

# Market spread: buying a unit costs the sale price plus this markup.
const MARKET_BUY_MARKUP: float = 0.05

func price_impact_pct_for(units: int) -> int:
	# % downward price impact from selling `units` of one good in a single turn.
	if units <= GLUT_UNITS:
		return 0
	var steps: int = int(ceil(float(units - GLUT_UNITS) / float(GLUT_UNITS)))
	return mini(MAX_PRICE_IMPACT_PCT, steps)

func units_cap_for_impact(max_pct: int) -> int:
	# Largest single-turn sell volume of one good that stays within max_pct impact.
	# max_pct 0 -> GLUT_UNITS (no impact); 1 -> 2*GLUT_UNITS; etc.
	return GLUT_UNITS * (max_pct + 1)

# --- Seaport subscription shipping ---
# A seaport can transfer ANY volume of a subscribed good in 1 turn for a flat per-turn
# fee per good (NOT per unit). When a good is covered, market buy/sell shipping pays no
# per-unit transport — just this standing subscription. (Sim auto-subscribes from turn 1;
# the game will expose this as a per-good toggle.)
const SEAPORT_SUBSCRIPTION_COST_PER_GOOD: float = 1.0
# A seaport can only service tiles within this many tiles of it (per turn).
const SEAPORT_RANGE_TILES: int = 10

# --- Power grid pricing ---
const GRID_BUY_PRICE: float = 0.12    # £/unit when buying from grid (shortfall)
const GRID_SELL_PRICE: float = 0.08  # £/unit when selling surplus to grid

# --- Decarbonisation squeeze: CO2 tax + green subsidy (PolicyState schedules the phases) ---
# Carbon levy per unit of a taxed good CONSUMED by a player building:
#   charge = qty × good.co2_tax_multiplier × CO2_TAX_RATE × CO2_TAX_PHASE_SCALE[level]
# The per-good co2_tax_multiplier column (Goods CSV) carries the carbon intensity in £ at
# scale 1; this rate is the global knob. (Balance data — rule #7.)
const CO2_TAX_RATE: float = 1.0
# Phase escalation, indexed by PolicyState.co2_tax_level (0 = not yet in force).
const CO2_TAX_PHASE_SCALE: Array = [0.0, 1.0, 2.0, 3.5]
# Green-energy subsidy: £ per green MW GENERATED (intermittent + steady, matching the
# Greenest victory track), paid at grid settlement once the subsidy is announced.
const GREEN_SUBSIDY_RATE: float = 0.03
const GREEN_SUBSIDY_PHASE_SCALE: Array = [0.0, 1.0]

# --- National grid carbon intensity -----------------------------------------------------
# The grid the player imports from decarbonises on its own, whatever they do: fully carbon
# intensive until turn 70, then falling to 30% of that by the last turn. It scales the carbon
# priced into imported power, so buying grid power gets steadily cleaner — and the whole point
# of the curve is that a coal plant does NOT, because a coal plant still burns coal.
#
# The curve starts before the levy does (turn 91), so the early part is invisible in £ and
# only begins to matter as the tax ramps. That is deliberate: the world is already moving
# when the policy arrives. (Balance data — rule #7.)
const GRID_CARBON_FULL_TURN: int = 70
const GRID_CARBON_FLOOR: float = 0.30

# --- Power intermittency (green/grey quality, layered ON TOP of the single `power` good) ---
# Solar/wind are intermittent green: a recipe relying on UNFIRMED intermittent power
# produces less. output *= 1 - INTERMITTENCY_DERATE * unfirmed_intermittent_share, so a
# building running entirely on unfirmed intermittent green makes (1 - 0.4) = 60% of output.
const INTERMITTENCY_DERATE: float = 0.4
# Abstracted per-tile firming capacity (power units) by battery building level — storage on
# a tile converts up to this much intermittent green to steady (producer- or consumer-side).
# Not a charge/discharge sim; just a cap check. (Batteries give 0 storage_boost otherwise.)
# Firming CAPACITY (⚡) of one battery housing by level — L1 100, L2 doubles, L3 triples.
# (Balance data — rule #7.)
const BATTERY_STORAGE_CAP := {1: 1000, 2: 2000, 3: 3000}
# Power-quality classification by producing building internal_name (default = grey/firm).
const POWER_INTERMITTENT_BUILDINGS := ["solar_farm", "onshore_wind_farm", "offshore_wind_farm"]
const POWER_STEADY_BUILDINGS := ["hydro_power_plant"]
# Generic power_plant recipes whose fuel is biomass/waste count as steady green.
# (MVP good internal_names: biomass g_062, bio_waste g_073, carbonised_biomass g_076.)
const POWER_STEADY_FUELS := ["biomass", "bio_waste", "carbonised_biomass"]
# Recipes that take NO intermittency derate however unfirmed their supply is. A membraneless
# electrolyser has no membrane to dry out or differentially pressurise, so it can follow a
# ragged renewable input up and down instead of needing a steady load — which is the whole
# point of the research, and a benefit that survives a balance pass in a way that an output
# bump does not. Listed by recipe_id because it is a property of the process, not the building.
const INTERMITTENCY_IMMUNE_RECIPES := ["r_080"]
# The ONLY buildings that may be placed on sea / deep_sea tiles. Every other building is
# land-only, and these two are conversely water-only (cannot be placed on land). By
# building internal_name. (offshore_wind_farm b_026, offshore_oil_platform b_033.)
const SEA_ONLY_BUILDINGS := ["offshore_wind_farm", "offshore_oil_platform"]
# Battery storage = deposit model (docs/battery-storage-spec.md). A battery building is housing
# with BATTERY_STORAGE_CAP[level] CELL SLOTS; the player loads battery goods (locked, refundable
# capital) into those slots and a tile's firming = min(slots, Σ loaded cells × density).
# Density is per battery-good internal_name (uniform for now; future differentiation lever).
# Firming ⚡ per loaded cell, by battery good. Calibrated against the L1 cap (1000 ⚡) so filling a
# building takes 3 / 4 / 10 turns of factory output (6/turn) — i.e. 18 / 24 / 60 cells fill 1000 ⚡.
# Scaled x10 alongside BATTERY_STORAGE_CAP in the power rescale, so cell COUNTS are unchanged.
# Lithium is densest (fewest, priciest cells), iron-air bulkiest (most, cheapest cells).
const BATTERY_CELL_DENSITY := {
	"lithium_battery": 1000.0 / 18.0,   # 18 cells fill 1000 ⚡ (3 factory-turns)
	"sodium_battery": 1000.0 / 24.0,    # 24 cells (4 turns)
	"iron_battery": 1000.0 / 60.0,      # 60 cells (10 turns)
}
# Tech gate: battery good internal_name -> the research title that unlocks loading it.
const BATTERY_TYPE_UNLOCK := {
	"lithium_battery": "Lithium Battery Storage",
	"sodium_battery": "Sodium Battery Storage",
	"iron_battery": "Iron Air Long Duration Storage",
}

# --- Transport ---
const TRANSPORT_MAX_TILES_PER_TURN: int = 2
# Liquids & gases move by pipe ONLY (1 tile/turn — see infrastructure.csv pipe range)
# at a flat per-unit-per-tile rate, regardless of weight class.
const PIPE_MODES := ["pipes", "reinf_pipes"]
const DEFAULT_TRANSPORT_WEIGHT_CLASS := "standard"
# Per-unit-per-turn transport rates by weight class (a leg is one turn-move).
const TRANSPORT_COST_PER_UNIT_PER_TURN_BY_WEIGHT_CLASS := {
	"standard": 0.02,
	"solid_light": 0.02,
	"solid_heavy": 0.03,
	"ultra_heavy": 0.06,
	"safe_liquid": 0.03,
	"hazard_liquid": 0.03,
	"liquid": 0.03,
	"gas": 0.30,        # ~10x safe_liquid — compression/cryogenics (owner ruling 2026-07-27)
	"electricity": 0.02,
}
# AD-VALOREM component of the freight tariff: £/unit/turn per £1 of the good's value.
# Real freight is a two-part tariff — a weight/volume charge plus insurance and handling
# that scale with what the cargo is worth. With the flat rate alone, freight burden collapses
# to ~0.1% of value at the top of the chain (heavy_vehicle) where reality is 2-5%, because
# the class rates only span 3x while prices span 2280x. solid_light is deliberately 0.0 so
# electronics stay near-free to ship, as they are in reality (CPUs go by air).
# Valued at MarketState.get_base_price_now() — this turn's DECAYED base price, with no
# buy-side markup and no glut/deficit impact (owner ruling 2026-07-27). Impact is excluded
# on purpose: market-linking freight would make a flooded good cheaper to haul, partly
# cancelling the price-impact penalty, and would make the quote unpredictable to plan against.
const TRANSPORT_ADVALOREM_BY_WEIGHT_CLASS := {
	"standard": 0.004,
	"solid_light": 0.0,
	"solid_heavy": 0.008,
	"ultra_heavy": 0.010,
	"safe_liquid": 0.004,
	"hazard_liquid": 0.006,
	"liquid": 0.005,
	"gas": 0.04,    # ~10x safe_liquid (owner ruling 2026-07-27). Gases ride NORMAL pipework
	                # — they do not need the reinforced line — but compression and cryogenic
	                # handling make them an order of magnitude dearer to move and hold. This
	                # is why real air-separation units sit ON the customer's site rather than
	                # shipping product: it pushes gas production local, which is correct.
	"electricity": 0.0,
}

# Per-mode multiplier on the weight-class rate. Rail is half the per-unit cost of
# roads/overland (and also faster — see infrastructure.csv range 4 vs 2).
const TRANSPORT_MODE_COST_MULT := {
	"rail": 0.5,
	"roads": 1.0,
	"pipes": 1.0,        # pipe cost is flat (PIPE_COST_PER_UNIT_PER_TURN), not class-scaled
	"reinf_pipes": 1.0,
	"nothing": 1.0,
}
# Per-turn throughput one tile-link can carry by mode and infrastructure level.
# ENFORCED via a soft cap: when a tile's in-transit flow on a mode exceeds this
# (after throughput research), the overflow incurs a
# per-turn congestion surcharge (MatchState.charge_transport_congestion). Goods still
# move — it's a cost, not a gate. Modes not listed are uncapped (cables=power, overland).
const TRANSPORT_LINK_CAP_BY_MODE := {
	"roads": 300,
	"rail": 600,
	"pipes": 250,
	"reinf_pipes": 250,
}
const TRANSPORT_LINK_CAP_BY_MODE_LEVEL := {
	"roads": {1: 300, 2: 500, 3: 750},
	"rail": {1: 600, 2: 1200, 3: 2000},
	"pipes": {1: 250, 2: 600, 3: 1200},
	"reinf_pipes": {1: 250, 2: 600, 3: 1200},
}
# Cables HARD-cap a tile's power per turn by cable level — separately for production
# (export) and draw (import). A tile can both produce AND draw up to this. Power above
# the cap simply doesn't generate / isn't supplied.
const CABLE_POWER_CAP := {1: 2000, 2: 4000, 3: 7000}
# Infrastructure upgrades (roads/rails/pipes/reinf_pipes/cables) are CASH-ONLY for now
# (owner ruling 2026-07-10): a flat £ price per target level, no material kit, no
# research gate. Capacity still scales by the mode tier table / CABLE_POWER_CAP.
# (Balance data — rule #7.)
const INFRA_UPGRADE_CASH_COST := {2: 150.0, 3: 350.0}

# --- Warehouse (per-tile storage) ---
# A tile's storage capacity by "warehouse level". Level = 1 + the number of storage
# research upgrades unlocked (WAREHOUSE_UPGRADE_RESEARCH): no research = 800, one = 1600,
# both = 2500. A building's storage_boost (a Port adds +600) is added on top. Rule #7.
const WAREHOUSE_STORAGE_CAP := {1: 800, 2: 1600, 3: 2500}
const WAREHOUSE_UPGRADE_RESEARCH := ["Pallet Racking Systems", "Automated Storage & Retrieval"]
# Per-tile warehouse expansion, paid in MATERIALS (owner spec 2026-07-09): the target
# level keys the bill. Materials come either from the market (charged at ask + freight
# to the tile) or pulled from stock across the player's tiles.
# g_023 building_frame · g_071 construction_equipment_ice · g_027 plastics ·
# g_042 computer · g_036 electrical_components
const WAREHOUSE_UPGRADE_COSTS := {
	2: {"g_023": 5, "g_071": 2, "g_027": 10},
	3: {"g_023": 5, "g_071": 2, "g_042": 2, "g_036": 5},
}
# Warehousing fee: per-turn storage cost per STOCKPILED unit, by transport class
# (owner spec 2026-07-09, part of the recipes-vs-overheads rebalance). Solids rack
# cheaply; liquids need tankage; hazardous liquids and gases need certified
# pressure storage. Goods in transit, overflow-hold or JIT feed pay nothing.
#
# TWO-PART TARIFF (owner ruling 2026-07-27): flat + ad-valorem, the same shape as freight.
# A flat-only rate can only be correct at ONE price point — at 0.03 flat, coal pays for its
# own value in 13 turns while an ice_car takes 3410, so a hoarder sitting on £56k of CPUs
# paid the same as one sitting on £320 of coal. Real inventory carrying cost is 15-25%/yr
# OF VALUE across commodities, because cost of capital dominates physical storage. The
# ad-valorem term compresses that 262x spread to ~12x while costing the tutorial cluster
# the same as flat-0.03 did (measured: £2.41/turn on its 80-unit buffer, 14%/yr of the
# inventory's value, 1.1% of revenue — real-world warehousing is 1-2% of revenue).
# `flat` is the floor-space/handling leg, `av` the capital/insurance leg.
const WAREHOUSING_BY_CLASS := {
	"solid_light":   {"flat": 0.010, "av": 0.004},  # small footprint, but secure + insured
	"solid_heavy":   {"flat": 0.020, "av": 0.004},  # racking + floor loading — the workhorse
	"ultra_heavy":   {"flat": 0.060, "av": 0.004},  # a parked car or turbine eats floor area
	"safe_liquid":   {"flat": 0.015, "av": 0.002},  # tankage: capital-heavy, cheap per unit
	"liquid":        {"flat": 0.025, "av": 0.003},
	"hazard_liquid": {"flat": 0.100, "av": 0.006},  # bunded, ventilated, licensed storage
	"gas":           {"flat": 0.150, "av": 0.020},  # ~10x safe_liquid: pressure vessels + boil-off
}

func warehousing_cost_per_unit(good_id: String) -> float:
	var band: Dictionary = WAREHOUSING_BY_CLASS.get(
		Catalog.get_transport_class(good_id), WAREHOUSING_BY_CLASS["solid_light"])
	return float(band["flat"]) + float(band["av"]) * good_value_basis(good_id)

## The value a two-part tariff (freight or storage) charges against: this turn's DECAYED
## base price — no buy-side markup, no glut/deficit impact. Returns 0.0 for an unknown or
## empty good so both tariffs fall back to their flat leg rather than an invented value.
func good_value_basis(good_id: String) -> float:
	if good_id == "" or Catalog.get_good(good_id).is_empty():
		return 0.0
	return MarketState.get_base_price_now(good_id)

# --- Loans ---
# Capacity is no longer a flat ceiling. It STARTS at the base below and scales with
# the company's recent performance so you can borrow against a growing business and
# outgrow debt (see LoanState.capacity_total). The cap is sized so the per-turn loan
# repayment (principal + interest, amortised over LOAN_TERM_TURNS) stays within
# rolling profit plus a slice of revenue — the 40-turn payoff is the affordance that
# lets debt service sit above pure interest without being unserviceable.
const LOAN_BASE_CAPACITY: float = 50.0     # Floor on borrowing capacity (turn 1, no history)
const LOAN_TERM_TURNS: int = 36            # How many turns of REPAYMENT (after the grace)
const LOAN_INTEREST_RATE: float = 0.10     # 10% over total term (not per turn)
# Smallest loan the bank will write. The auto-bridge used to borrow the exact shortfall, so a
# £1.36 gap became a £1.36 loan on a 36-turn book — 18 of them by turn 57 in a player log,
# each carrying its own interest forever. A floor turns that into one loan with headroom.
const LOAN_MINIMUM: float = 20.0
# Turns before the first payment falls due. Interest still ACCRUES across them, so the grace
# buys breathing room rather than free money: a loan now runs 12 + 36 = 48 turns and the
# larger balance is amortised over the same 36 paying turns. (Balance data — rule #7.)
const LOAN_GRACE_TURNS: int = 12
const LOAN_PROFIT_WINDOW: int = 5          # Rolling window (turns) for the profit/revenue average
const LOAN_REVENUE_BUFFER: float = 0.02    # Extra serviceable debt = this share of avg revenue
# Asset-backed leg (2026-07-08): plant is collateral, so a loss-making trough never
# zeroes the credit line — capacity = max(base, profit-scaled) + LTV x plant SALE value.
# The basis is what the buildings would SELL for (BuildingPrice.sale_price — level-aware
# via upgrade kits), so a levelled empire borrows against its real market worth.
# Base LTV is 0.75; a seated CFO or Chief Investment (expansion/capex) advisor lifts it
# to 1.0 (LOAN_COLLATERAL_LTV_MAX) — the two do NOT stack past the max.
const LOAN_COLLATERAL_LTV_BASE: float = 0.75  # Borrowable share of player buildings' sale value
const LOAN_COLLATERAL_LTV_MAX: float = 1.0    # With a seated CFO or Chief Investment advisor

# --- Tax & Dividends ---
const TAX_RATE: float = 0.20
const DIVIDEND_RATE: float = 0.20

# --- Retrofit / retooling (advisor spec §7) ---
# Changing a built building's recipe. Labour is a per-turn fraction of base while
# retooling (building produces nothing); the fee is a one-off. Tier keyed off the
# seated COO's Operations stat (base = no COO). Balance-volatile (rule #7).
const RETROFIT_TIERS := {
	"base": {"labour": 0.50, "fee": 25.0, "turns": 2},   # no relevant advisor seated
	"ops3": {"labour": 0.30, "fee": 15.0, "turns": 1},   # Ops 3 — cheap AND fast
	"ops2": {"labour": 0.30, "fee": 15.0, "turns": 2},   # Ops 2 — cheap, normal speed
	"ops1": {"labour": 0.75, "fee": 40.0, "turns": 2},   # Ops 1 malus — worse than base
}

# --- Labour multiplier ---
const LABOUR_MULTIPLIER_MIN: float = 0.8
const LABOUR_MULTIPLIER_DEFAULT: float = 1.0
const LABOUR_MULTIPLIER_MAX: float = 1.2
# Hard floor on the final labour factor: no matter how many additive reductions
# stack (advisors, people-management unlocks, workforce policies, the slider),
# labour cost can never fall below this fraction of base. Prevents free labour.
const LABOUR_FACTOR_MIN: float = 0.40

# Workforce effort ↔ output response (the People panel labour setting). Reduced
# effort (0.8×) compounds output pressure each worked turn; overtime (1.2×)
# builds a smaller momentum bonus; at 1.0× the accumulator recovers toward 0.
# Percent per PROCESS phase; values match the People panel copy — keep in sync.
const LABOUR_OUTPUT_PRESSURE_PER_TURN: float = -2.0  # accrual at 0.8×
const LABOUR_OUTPUT_PRESSURE_FLOOR: float = -30.0
const LABOUR_OUTPUT_MOMENTUM_PER_TURN: float = 1.0   # accrual at 1.2×
const LABOUR_OUTPUT_MOMENTUM_CAP: float = 10.0
const LABOUR_OUTPUT_RECOVERY_PER_TURN: float = 1.0   # toward 0 at 1.0×

func transport_turns_for_tile_distance(tile_distance: int) -> int:
	if tile_distance <= 0:
		return 0
	return maxi(1, ceili(float(maxi(tile_distance, 0)) / float(TRANSPORT_MAX_TILES_PER_TURN)))

func transport_cost_per_unit_turn(weight_class: String) -> float:
	var resolved_class := weight_class.strip_edges()
	if resolved_class == "":
		resolved_class = DEFAULT_TRANSPORT_WEIGHT_CLASS
	return float(TRANSPORT_COST_PER_UNIT_PER_TURN_BY_WEIGHT_CLASS.get(
		resolved_class,
		TRANSPORT_COST_PER_UNIT_PER_TURN_BY_WEIGHT_CLASS[DEFAULT_TRANSPORT_WEIGHT_CLASS]
	))

## The full two-part freight rate for one unit of `good_id` for one turn-move:
## the weight-class flat leg plus the ad-valorem leg charged against this turn's
## decayed base price. See TRANSPORT_ADVALOREM_BY_WEIGHT_CLASS for why both exist.
func transport_rate_for_good(good_id: String) -> float:
	var weight_class := Catalog.get_transport_class(good_id)
	var av: float = float(TRANSPORT_ADVALOREM_BY_WEIGHT_CLASS.get(
		weight_class, TRANSPORT_ADVALOREM_BY_WEIGHT_CLASS[DEFAULT_TRANSPORT_WEIGHT_CLASS]))
	return transport_cost_per_unit_turn(weight_class) + av * good_value_basis(good_id)

func transport_cost_for(good_id: String, qty: int, transport_turns: int, mode_mult: float = 1.0) -> float:
	return float(qty) * float(maxi(transport_turns, 0)) * transport_rate_for_good(good_id) * mode_mult

func transport_cost_for_route(good_id: String, qty: int, route: Dictionary) -> float:
	# Leg-aware cost. Each leg is one turn-move; pipe legs charge the flat liquid rate,
	# rail/road legs charge weight-class * mode multiplier. Falls back to a turns-based
	# overland charge when the route has no infra legs (straight-line haul).
	var legs: Array = route.get("legs", [])
	var class_rate := transport_rate_for_good(good_id)
	if legs.is_empty():
		var turns: int = int(route.get("turns", 0))
		return float(qty) * float(maxi(turns, 0)) * class_rate
	var total := 0.0
	for leg in legs:
		# Every leg is one turn-move: charge the per-unit-per-turn class rate times the
		# mode multiplier (rail 0.5x; roads/pipes 1x).
		var mode := str(leg.get("mode", ""))
		total += float(qty) * class_rate * float(TRANSPORT_MODE_COST_MULT.get(mode, 1.0))
	return total

func transport_link_capacity(mode: String, level: int) -> float:
	var tiers: Dictionary = TRANSPORT_LINK_CAP_BY_MODE_LEVEL.get(mode, {})
	if tiers.is_empty():
		return 0.0
	return float(tiers.get(clampi(level, 1, 3), 0.0))
