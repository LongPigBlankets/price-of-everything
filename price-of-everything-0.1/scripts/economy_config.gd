extends Node
# Centralised economic constants. All tunables for balancing live here.
# When playtesting reveals "the economy is too punishing" or "buildings are too cheap",
# this is the only file you need to edit.

# --- Player starting state ---
const STARTING_MONEY: float = 200.0

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
# Per-turn throughput a single link can carry by mode (goods/turn). NOTE: not yet
# enforced — a per-link flow-accounting pass is needed (see infrastructure.csv's
# max_goods_carried / soft_capacity columns). Kept here as the agreed values.
const TRANSPORT_LINK_CAP_BY_MODE := {
	"roads": 200,
	"rail": 400,
}

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
