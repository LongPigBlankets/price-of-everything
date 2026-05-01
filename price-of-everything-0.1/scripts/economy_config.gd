extends Node
# Centralised economic constants. All tunables for balancing live here.
# When playtesting reveals "the economy is too punishing" or "buildings are too cheap",
# this is the only file you need to edit.

# --- Player starting state ---
const STARTING_MONEY: float = 50.0

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

# --- Power grid pricing ---
const GRID_BUY_PRICE: float = 0.5    # £/unit when buying from grid (shortfall)
const GRID_SELL_PRICE: float = 0.25  # £/unit when selling surplus to grid

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
