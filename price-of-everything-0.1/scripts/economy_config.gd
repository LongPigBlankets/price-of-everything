extends Node
# Centralised economic constants. All tunables for balancing live here.
# When playtesting reveals "the economy is too punishing" or "buildings are too cheap",
# this is the only file you need to edit.

# --- Player starting state ---
const STARTING_MONEY: float = 200.0

# --- Per-building per-turn costs ---
const MAINTENANCE_PER_BUILDING: float = 1.0

# --- Labour rates (cost per worker per turn) ---
const LABOUR_UNSKILLED_RATE: float = 0.001
const LABOUR_SKILLED_RATE: float = 0.003
const LABOUR_HIGH_SKILLED_RATE: float = 0.005

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

# --- Power grid pricing ---
const GRID_BUY_PRICE: float = 0.5    # £/unit when buying from grid (shortfall)
const GRID_SELL_PRICE: float = 0.25  # £/unit when selling surplus to grid

# --- Transport ---
const TRANSPORT_MAX_TILES_PER_TURN: int = 2
const DEFAULT_TRANSPORT_WEIGHT_CLASS := "standard"
const TRANSPORT_COST_PER_UNIT_PER_TURN_BY_WEIGHT_CLASS := {
	"standard": 0.2,
	"solid_light": 0.2,
	"solid_heavy": 0.2,
	"ultra_heavy": 0.2,
	"safe_liquid": 0.2,
	"hazard_liquid": 0.2,
	"gas": 0.2,
	"electricity": 0.2,
}

# --- Loans ---
const LOAN_MAX_CAPACITY: float = 50.0     # Maximum outstanding initial principal
const LOAN_TERM_TURNS: int = 40            # How many turns to repay over
const LOAN_INTEREST_RATE: float = 0.10     # 10% over total term (not per turn)

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

func transport_cost_for(good_id: String, qty: int, transport_turns: int) -> float:
	var weight_class := Catalog.get_transport_class(good_id)
	return float(qty) * float(maxi(transport_turns, 0)) * transport_cost_per_unit_turn(weight_class)
