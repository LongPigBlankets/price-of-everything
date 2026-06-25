extends Node
# Centralised economic constants. All tunables for balancing live here.
# When playtesting reveals "the economy is too punishing" or "buildings are too cheap",
# this is the only file you need to edit.

# --- Player starting state ---
const STARTING_MONEY: float = 200.0

# --- Demolish / refund ---
# Share of a demolished building's construction cost returned to the player: the build
# money plus EVERY material kit consumed (the construction kit + each completed upgrade
# level's kit). 1.0 = full refund. A `var` (not const) so it can be tuned live while
# balancing demolish-and-rebuild churn. See MatchState.refund_cost / refund_plan.
var demolish_refund_share: float = 1.0

# --- Per-building per-turn costs ---
const MAINTENANCE_PER_BUILDING: float = 1.0

# --- Labour rates (cost per worker per turn) ---
# Doubled from the original 0.001/0.003/0.005 — a higher starting wage bill.
const LABOUR_UNSKILLED_RATE: float = 0.002
const LABOUR_SKILLED_RATE: float = 0.006
const LABOUR_HIGH_SKILLED_RATE: float = 0.010

# --- Labour wage growth (compounding per turn) ---
# Wages drift upward every turn: the effective rate at turn t is
#   base_rate * (1 + growth) ^ (t - 1).
# Higher-skilled labour inflates fastest, so margins compress over a long game
# and the player must keep expanding revenue to stay ahead of the wage bill.
const LABOUR_UNSKILLED_GROWTH: float = 0.0015    # +0.15%/turn
const LABOUR_SKILLED_GROWTH: float = 0.0025      # +0.25%/turn
const LABOUR_HIGH_SKILLED_GROWTH: float = 0.004  # +0.40%/turn

# --- MVP labour stub: every building has these counts ---
# Remove these once buildings catalog has real employment data.
const STUB_UNSKILLED_PER_BUILDING: int = 100
const STUB_SKILLED_PER_BUILDING: int = 50
const STUB_HIGH_SKILLED_PER_BUILDING: int = 50

# --- Bankruptcy ---
const BANKRUPTCY_FLOOR: float = -10.0

# --- Market price impact (glut model) ---
# Selling more than GLUT_UNITS of a single good in one turn starts to move its
# price. Every further GLUT_UNITS over the threshold adds another 1% of downward
# impact, capped at MAX_PRICE_IMPACT_PCT. (Placeholder model — tunable.)
const GLUT_UNITS: int = 100
const MAX_PRICE_IMPACT_PCT: int = 10

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
const GRID_BUY_PRICE: float = 1.0    # £/unit when buying from grid (shortfall)
const GRID_SELL_PRICE: float = 0.6   # £/unit when selling surplus to grid

# --- Power intermittency (green/grey quality, layered ON TOP of the single `power` good) ---
# Solar/wind are intermittent green: a recipe relying on UNFIRMED intermittent power
# produces less. output *= 1 - INTERMITTENCY_DERATE * unfirmed_intermittent_share, so a
# building running entirely on unfirmed intermittent green makes (1 - 0.4) = 60% of output.
const INTERMITTENCY_DERATE: float = 0.4
# Abstracted per-tile firming capacity (power units) by battery building level — storage on
# a tile converts up to this much intermittent green to steady (producer- or consumer-side).
# Not a charge/discharge sim; just a cap check. (Batteries give 0 storage_boost otherwise.)
# Firming CAPACITY (⚡) of one battery housing by level. Benchmark: filling a L1 building =
# 3 turns of a L1 lithium-battery factory's output (6/turn) → 18 cells × density 1.0 = 18 ⚡.
# L2 doubles, L3 triples. (Balance data — rule #7.)
const BATTERY_STORAGE_CAP := {1: 18, 2: 36, 3: 54}
# Power-quality classification by producing building internal_name (default = grey/firm).
const POWER_INTERMITTENT_BUILDINGS := ["solar_farm", "onshore_wind_farm", "offshore_wind_farm"]
const POWER_STEADY_BUILDINGS := ["hydro_power_plant"]
# Generic power_plant recipes whose fuel is biomass/waste count as steady green.
# (MVP good internal_names: biomass g_062, bio_waste g_073, carbonised_biomass g_076.)
const POWER_STEADY_FUELS := ["biomass", "bio_waste", "carbonised_biomass"]
# The ONLY buildings that may be placed on sea / deep_sea tiles. Every other building is
# land-only, and these two are conversely water-only (cannot be placed on land). By
# building internal_name. (offshore_wind_farm b_026, offshore_oil_platform b_033.)
const SEA_ONLY_BUILDINGS := ["offshore_wind_farm", "offshore_oil_platform"]
# Battery storage = deposit model (docs/battery-storage-spec.md). A battery building is housing
# with BATTERY_STORAGE_CAP[level] CELL SLOTS; the player loads battery goods (locked, refundable
# capital) into those slots and a tile's firming = min(slots, Σ loaded cells × density).
# Density is per battery-good internal_name (uniform for now; future differentiation lever).
# Firming ⚡ per loaded cell, by battery good. Calibrated so filling a building takes
# 3 / 4 / 10 turns of factory output (6/turn) for lithium / sodium / iron-air — i.e. lithium is
# the densest (fewest, priciest cells), iron-air the bulkiest (most, cheapest cells).
const BATTERY_CELL_DENSITY := {
	"lithium_battery": 1.0,
	"sodium_battery": 0.75,
	"iron_battery": 0.3,
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
	"gas": 0.03,
	"electricity": 0.02,
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
# Per-turn throughput one tile-link can carry by mode (goods/turn), at infra Level 1.
# ENFORCED via a soft cap: when a tile's in-transit flow on a mode exceeds this
# (× the tile's infra-level multiplier × throughput research), the overflow incurs a
# per-turn congestion surcharge (MatchState.charge_transport_congestion). Goods still
# move — it's a cost, not a gate. Modes not listed are uncapped (cables=power, overland).
const TRANSPORT_LINK_CAP_BY_MODE := {
	"roads": 200,
	"rail": 400,
	"pipes": 200,
	"reinf_pipes": 350,
}
# Infra level multiplies a link's capacity: L2 doubles it, L3 ×3.5.
const TRANSPORT_CAP_LEVEL_MULT := {1: 1.0, 2: 2.0, 3: 3.5}
# Cables HARD-cap a tile's power per turn by cable level — separately for production
# (export) and draw (import). A tile can both produce AND draw up to this. Power above
# the cap simply doesn't generate / isn't supplied.
const CABLE_POWER_CAP := {1: 200, 2: 400, 3: 700}

# --- Loans ---
# Capacity is no longer a flat ceiling. It STARTS at the base below and scales with
# the company's recent performance so you can borrow against a growing business and
# outgrow debt (see LoanState.capacity_total). The cap is sized so the per-turn loan
# repayment (principal + interest, amortised over LOAN_TERM_TURNS) stays within
# rolling profit plus a slice of revenue — the 40-turn payoff is the affordance that
# lets debt service sit above pure interest without being unserviceable.
const LOAN_BASE_CAPACITY: float = 50.0     # Floor on borrowing capacity (turn 1, no history)
const LOAN_TERM_TURNS: int = 36            # How many turns to repay over
const LOAN_INTEREST_RATE: float = 0.10     # 10% over total term (not per turn)
const LOAN_PROFIT_WINDOW: int = 5          # Rolling window (turns) for the profit/revenue average
const LOAN_REVENUE_BUFFER: float = 0.02    # Extra serviceable debt = this share of avg revenue

# --- Tax & Dividends ---
const TAX_RATE: float = 0.20
const DIVIDEND_RATE: float = 0.20

# --- Labour multiplier ---
const LABOUR_MULTIPLIER_MIN: float = 0.75
const LABOUR_MULTIPLIER_DEFAULT: float = 1.0
const LABOUR_MULTIPLIER_MAX: float = 1.25

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

func transport_cost_for(good_id: String, qty: int, transport_turns: int, mode_mult: float = 1.0) -> float:
	var weight_class := Catalog.get_transport_class(good_id)
	return float(qty) * float(maxi(transport_turns, 0)) * transport_cost_per_unit_turn(weight_class) * mode_mult

func transport_cost_for_route(good_id: String, qty: int, route: Dictionary) -> float:
	# Leg-aware cost. Each leg is one turn-move; pipe legs charge the flat liquid rate,
	# rail/road legs charge weight-class * mode multiplier. Falls back to a turns-based
	# overland charge when the route has no infra legs (straight-line haul).
	var legs: Array = route.get("legs", [])
	var weight_class := Catalog.get_transport_class(good_id)
	var class_rate := transport_cost_per_unit_turn(weight_class)
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
