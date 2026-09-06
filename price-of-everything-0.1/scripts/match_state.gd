extends Node
const BuildingLevels := preload("res://scripts/building_levels.gd")
const BuildingPrice := preload("res://scripts/building_price.gd")
# When you SELL a building it transfers to this NPC operator (keeps standing, land occupied).
const SOLD_TO_OWNER := "npc_market"
# Demolish is a queued 1-turn job (mirrors upgrades/retrofits) before the building is removed.
const DEMOLISH_TURNS := 1

# MatchState: the canonical store for everything that changes during a match.
# Other systems read and write here; never store match data elsewhere.

# --- Player resources ---
const LOCAL_PLAYER := "player_1"
var money: float = 1000.0  # was: int = 1000

# Three legacy/prototype buildings are deliberately absent from normal matches.
# `unlock hidden_buildings` is an explicit development cheat for testing them.
const HIDDEN_BUILDING_IDS := {"b_029": true, "b_030": true, "b_031": true, "b_035": true}
var hidden_buildings_unlocked: bool = false

# Recycling is off the table for the demo (owner 2026-08-23): the waste chain is a whole
# second economy — collect it, sort it, feed it back — and a 100-turn demo has no room to
# teach it. `unlock recycling` in the debug terminal puts it back for development.
const RECYCLING_BUILDING_IDS := {"b_022": true, "b_036": true}
# Waste Water, Scrap Metal, Bio Waste, Electronic Waste — the goods that only exist to be
# recycled. Hidden alongside the plants, or the encyclopedia advertises a chain with no
# building that can process it.
const RECYCLING_GOOD_IDS := {"g_063": true, "g_067": true, "g_073": true, "g_074": true}
var recycling_unlocked: bool = false

# Demo gating (owner 2026-08-19): only the three DEMO_ADVISORS and four BASE_SEATS are
# available until the `unlock advisors` cheat opens the full roster, every seat, and the
# People-Management seat-unlock research.
var advisors_unlocked: bool = false

# --- Ruleset ---
# Which rule variant this match plays under. Carried in saves and start configs so
# future rule changes (scoring, brakes, era pacing, …) can key off it; only "name"
# is defined today — add per-rule keys beside it as rules become real.
const DEFAULT_RULESET := {"name": "standard"}
var ruleset: Dictionary = DEFAULT_RULESET.duplicate(true)
## Which start config this match began from ("metal_magnate", "tutorial", …). Telemetry's
## primary segmentation field; empty for matches built without a start config (tests).
## Unlike ruleset.name this is NOT reset by state_reset mid-teardown, so it stays readable.
var scenario_name: String = ""
## Sticky once any debug command moves the sim. Telemetry reports it so cheat runs can be
## excluded from aggregates instead of silently poisoning them.
var cheats_used: bool = false

const DEFAULT_TILE_LAND_OWNED := 0
const LAND_PATCH_SIZE := 10
const LAND_PATCH_COST := 10.0
## The most land any tile can ever hold, and the default for terrain this table does not
## name. Kept as the hard ceiling: every cap below is clamped to it.
const MAX_TILE_LAND := 200

## BUILDABLE LAND BY TERRAIN (owner, 2026-08-17). Rough ground and built-up ground hold less
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

# --- Building instances ---
# Flat dictionary: instance_id -> building data dict
# Building data: {instance_id, building_id, recipe_id, tile_coord, owner}
var buildings: Dictionary = {}

# --- Tile occupancy index (derived from buildings, kept in sync) ---
# tile_id -> Array of instance_ids
# This is for fast "what's on this tile" queries.
var tile_buildings: Dictionary = {}

# --- Instance ID generation ---
var _next_instance_counter: int = 0

# --- Labour Slider ---
var labour_multiplier: float = EconomyConfig.LABOUR_MULTIPLIER_DEFAULT
# Accumulated output response (in percent) to the labour effort setting —
# negative = pressure from reduced effort, positive = overtime momentum.
# Accrued once per PROCESS by tick_labour_output_pressure(), applied by
# workforce_output_multiplier().
var labour_output_pressure_pct: float = 0.0
const WORKFORCE_POLICY_GENEROUS_PENSIONS := "generous_pensions"
const WORKFORCE_POLICY_EXTENDED_ANNUAL_LEAVE := "extended_annual_leave"
const WORKFORCE_POLICY_GENEROUS_PARENTAL_LEAVE := "generous_parental_leave"
const WORKFORCE_POLICY_STRICT_SAFETY := "strict_safety_procedures"
const WORKFORCE_POLICY_STANDARD_SAFETY := "standard_safety_procedures"
const WORKFORCE_POLICY_LAX_SAFETY := "lax_safety_procedures"
const WORKFORCE_POLICY_ANNUAL_BONUS := "annual_bonus"
const WORKFORCE_POLICY_ANNUAL_PROFIT_SHARE := "annual_profit_share"
# The former Labour-tab placeholder rungs, now wired. Ids must stay exactly these
# strings: saves from before the wiring already carry them as no-effect entries.
const WORKFORCE_POLICY_PENSIONS_MINIMUM := "pensions_minimum_legal"
const WORKFORCE_POLICY_SMALL_BONUS := "annual_bonus_small"
const WORKFORCE_POLICY_PROFIT_SHARE_10 := "profit_share_10"
const WORKFORCE_POLICY_PUSH_AUTOMATION := "push_automation"
# HR Director unlocks: Long Tenure Awards (any HR Director) and Stock Options
# (only a Leadership-3 HR Director).
const WORKFORCE_POLICY_LONG_TENURE := "long_tenure_awards"
const WORKFORCE_POLICY_STOCK_OPTIONS := "stock_options"
const WORKFORCE_POLICY_GAME_LENGTH_TURNS := 300
const WORKFORCE_SAFETY_POLICIES := [
	WORKFORCE_POLICY_STRICT_SAFETY,
	WORKFORCE_POLICY_STANDARD_SAFETY,
	WORKFORCE_POLICY_LAX_SAFETY,
]
# Mutually-exclusive spectrum groups: enabling one member disables the others
# sim-side, so a tampered or pre-wiring save can never double-dip a spectrum.
const WORKFORCE_EXCLUSIVE_GROUPS := [
	WORKFORCE_SAFETY_POLICIES,
	[WORKFORCE_POLICY_PENSIONS_MINIMUM, WORKFORCE_POLICY_GENEROUS_PENSIONS],
	[WORKFORCE_POLICY_SMALL_BONUS, WORKFORCE_POLICY_ANNUAL_BONUS],
	[WORKFORCE_POLICY_ANNUAL_PROFIT_SHARE, WORKFORCE_POLICY_PROFIT_SHARE_10],
]
var workforce_policies: Dictionary = {}
var workforce_policy_effects: Dictionary = {}
const ADVISOR_COST_PER_TURN := 2.0
var permanent_advisor_ids: Array = []
# --- Advisor seats (seat framework, docs/advisor-system-spec.md §4-6) ---
# advisor_seats is sparse: only occupied seats are keys, so .size() == seated count.
var advisor_seats: Dictionary = {}          # seat_id -> advisor_id
## Only CFO and COO exist until the player earns the rest. A new player choosing between two
## posts is a real decision; choosing between eleven is a menu.
## See docs/early-game-onboarding-spec.md §5.4.
const STARTING_SEATS: Array[String] = ["cfo", "coo"]
# The seats a match runs with by default — CFO, COO, Technical Director, Chief Markets.
# The rest wait behind `unlock advisors` (see advisors_unlocked / is_seat_available).
const BASE_SEATS: Array[String] = ["cfo", "coo", "technical_director", "chief_markets"]
const FOUNDER_ADVISOR_ID := "andrew"
const FOUNDER_TENURE_TURNS := 30
## The research title that opens the rest of the council (data/research_unlocks.csv).
const SEATS_UNLOCK_TITLE := "Executive Search"
var all_seats_unlocked: bool = false        # set by the people/labour research node
## "Worker pay while building not running": what share of a workforce's pay a building owes on a
## turn it produced NOTHING. 1.0 is the old behaviour (they are paid in full regardless).
## Deliberately keyed on zero output, never on "starving": a derated building still ran and is
## still in CostSolver, and paying it less would make its imputed cost FALL as it got sicker.
const IDLE_LABOUR_PAY_CHOICES: Array[float] = [0.5, 0.75, 1.0]
var idle_labour_pay_share: float = 1.0

func set_idle_labour_pay_share(value: float) -> void:
	# Off-menu values are REFUSED, not rounded: this is a three-position policy switch, and
	# silently snapping an unexpected value would hide a caller bug behind a plausible number.
	var matched := false
	for choice in IDLE_LABOUR_PAY_CHOICES:
		if is_equal_approx(choice, value):
			matched = true
	if not matched or is_equal_approx(value, idle_labour_pay_share):
		return
	idle_labour_pay_share = value
	labour_multiplier_changed.emit(labour_multiplier)   # the People panel repaints on this
var founder_seat: String = ""               # which post Andrew took, "" if he never joined
var founder_leaves_turn: int = 0            # tenure end; he cannot be dismissed before it
const MAX_ADVISOR_SLOTS_DEFAULT := 2
const MAX_ADVISOR_SLOTS_CAP := 5            # spec §4.1 hard ceiling
var max_advisor_slots: int = MAX_ADVISOR_SLOTS_DEFAULT
# --- Advisor acquisition (spec §4.2-4.4) ---
const DEFAULT_MATCH_RNG_SEED := 5060301
const PROFIT_MILESTONES := [50, 100, 150, 200, 300, 400, 500, 750, 1000]
# Andrew (the founder, seated via the family-friend decision), Vera (CFO) and Gerald (COO)
# are the only advisors until `unlock advisors`. The starting recruited pool is the two
# non-founder demo advisors; Andrew joins separately through seat_founder.
const DEMO_ADVISORS := ["andrew", "vera", "gerald"]
const STARTING_TRIO := ["vera", "gerald"]
var _match_rng := RandomNumberGenerator.new()
var match_rng_seed: int = DEFAULT_MATCH_RNG_SEED   # seeded match RNG (draws + tile reveal)
var crossed_milestones: Array = []                 # latched profit thresholds
var recruited_advisor_ids: Array = []              # unlocked pool (employ up to the cap)
const FIRE_COOLDOWN_TURNS := 10                     # a fired advisor sits out this many turns
var fired_advisor_cooldowns: Dictionary = {}       # advisor_id -> turns until re-hireable (greyed while > 0)

# --- Advisor loyalty / churn (agendas) --------------------------------------
# Each employed advisor holds a loyalty score in [-10, +10] that decays toward 0
# each turn. Per-turn "agenda events" they like nudge it up, ones they dislike down.
# Stay at or below WALK threshold for WALK_TURNS in a row and they walk (like fired).
const LOYALTY_MIN := -10.0
const LOYALTY_MAX := 10.0
const LOYALTY_DECAY := 0.1
const LOYALTY_STEP := 1.0
const LOYALTY_WALK_THRESHOLD := -9.0
const LOYALTY_WALK_TURNS := 11
# Agenda event tags (detected per turn from the summary + flagged hooks + streaks).
const AGENDA_TOOK_LOAN := "took_loan"
const AGENDA_PAID_OFF_LOAN := "paid_off_loan"
const AGENDA_EARLY_LOAN_PAYOFF := "early_loan_payoff"
const AGENDA_MADE_PROFIT := "made_profit"
const AGENDA_IDLE_BUILDING := "idle_building"                # >10 turns since last build
const AGENDA_BUILT_UNPROFITABLE := "built_while_unprofitable"
const AGENDA_BOUGHT_GRID_POWER := "bought_grid_power"
const AGENDA_SOLD_GRID_POWER := "sold_grid_power_streak"     # 5 turns in a row
const AGENDA_BOUGHT_MATERIALS := "bought_market_materials"
const AGENDA_USED_STOCKPILE := "used_stockpile"
const AGENDA_AUTARKIC := "autarkic_streak"                   # no market buys, 3 turns in a row
const AGENDA_FAST_SHIPMENT := "fast_shipment"               # a shipment delivered in <2 turns
const AGENDA_LABOUR_POLICIES := "labour_policies"           # >=2 workforce policies enabled
const AGENDA_TECH_UNLOCK := "tech_unlocked"
const AGENDA_CHANGED_RECIPE := "changed_recipe"
# Decision-event tags (flagged by decision choices — see decision_state.gd).
const AGENDA_BACKROOM_DEAL := "backroom_deal"
const AGENDA_CLEAN_COMMITMENT := "clean_commitment"
# 2 likes + 2 dislikes per advisor (Hal/Priya/Gerald carry an extra decision tag).
const ADVISOR_AGENDAS := {
	"vera": {"likes": [AGENDA_MADE_PROFIT, AGENDA_PAID_OFF_LOAN], "dislikes": [AGENDA_TOOK_LOAN, AGENDA_BUILT_UNPROFITABLE]},
	"tom": {"likes": [AGENDA_USED_STOCKPILE, AGENDA_CHANGED_RECIPE], "dislikes": [AGENDA_IDLE_BUILDING, AGENDA_TOOK_LOAN]},
	"rufus": {"likes": [AGENDA_MADE_PROFIT, AGENDA_BOUGHT_MATERIALS], "dislikes": [AGENDA_CHANGED_RECIPE, AGENDA_TECH_UNLOCK]},
	"gerald": {"likes": [AGENDA_USED_STOCKPILE, AGENDA_AUTARKIC], "dislikes": [AGENDA_TECH_UNLOCK, AGENDA_CHANGED_RECIPE, AGENDA_CLEAN_COMMITMENT]},
	"eleanor": {"likes": [AGENDA_LABOUR_POLICIES, AGENDA_MADE_PROFIT], "dislikes": [AGENDA_BUILT_UNPROFITABLE, AGENDA_BOUGHT_GRID_POWER]},
	"sloane": {"likes": [AGENDA_SOLD_GRID_POWER, AGENDA_MADE_PROFIT], "dislikes": [AGENDA_IDLE_BUILDING, AGENDA_AUTARKIC]},
	"priya": {"likes": [AGENDA_TECH_UNLOCK, AGENDA_CHANGED_RECIPE, AGENDA_CLEAN_COMMITMENT], "dislikes": [AGENDA_IDLE_BUILDING, AGENDA_USED_STOCKPILE, AGENDA_BACKROOM_DEAL]},
	"hitomi": {"likes": [AGENDA_FAST_SHIPMENT, AGENDA_MADE_PROFIT], "dislikes": [AGENDA_BOUGHT_GRID_POWER, AGENDA_IDLE_BUILDING]},
	"hal": {"likes": [AGENDA_MADE_PROFIT, AGENDA_TECH_UNLOCK, AGENDA_BACKROOM_DEAL], "dislikes": [AGENDA_TOOK_LOAN, AGENDA_BUILT_UNPROFITABLE]},
	"marcus": {"likes": [AGENDA_PAID_OFF_LOAN, AGENDA_EARLY_LOAN_PAYOFF], "dislikes": [AGENDA_TOOK_LOAN, AGENDA_BUILT_UNPROFITABLE]},
	"idris": {"likes": [AGENDA_TECH_UNLOCK, AGENDA_FAST_SHIPMENT], "dislikes": [AGENDA_AUTARKIC, AGENDA_USED_STOCKPILE]},
	"alexandra": {"likes": [AGENDA_MADE_PROFIT, AGENDA_TECH_UNLOCK], "dislikes": [AGENDA_IDLE_BUILDING, AGENDA_BOUGHT_GRID_POWER]},
}
# Loyalty weights. "per_turn" events can be true every single turn, so they're small:
# a per-turn LIKE gives +0.6 and a per-turn DISLIKE −0.4 (both beat the 0.1 decay but
# don't spike loyalty; gains outpace penalties). One-off actions are worth a full ±1.
const AGENDA_LIKE_PER_TURN := 0.6
const AGENDA_DISLIKE_PER_TURN := 0.4
const AGENDA_ONE_OFF := 1.0
const AGENDA_META := {
	AGENDA_MADE_PROFIT: {"text": "End the turn in profit", "per_turn": true},
	AGENDA_PAID_OFF_LOAN: {"text": "Pay off a loan", "per_turn": false},
	AGENDA_EARLY_LOAN_PAYOFF: {"text": "Repay a loan early", "per_turn": false},
	AGENDA_TOOK_LOAN: {"text": "Take out a loan", "per_turn": false},
	AGENDA_BUILT_UNPROFITABLE: {"text": "Build while unprofitable", "per_turn": false},
	AGENDA_IDLE_BUILDING: {"text": "Build nothing for 10+ turns", "per_turn": true},
	AGENDA_BOUGHT_GRID_POWER: {"text": "Buy power from the grid", "per_turn": true},
	AGENDA_SOLD_GRID_POWER: {"text": "Export power 5 turns running", "per_turn": true},
	AGENDA_BOUGHT_MATERIALS: {"text": "Buy materials from the market", "per_turn": true},
	AGENDA_USED_STOCKPILE: {"text": "Use stockpiled materials", "per_turn": true},
	AGENDA_AUTARKIC: {"text": "Buy nothing 3 turns running", "per_turn": true},
	AGENDA_FAST_SHIPMENT: {"text": "Deliver a shipment in under 2 turns", "per_turn": true},
	AGENDA_LABOUR_POLICIES: {"text": "Run 2+ labour policies", "per_turn": true},
	AGENDA_TECH_UNLOCK: {"text": "Unlock a research node", "per_turn": false},
	AGENDA_BACKROOM_DEAL: {"text": "Cut a backroom deal", "per_turn": false},
	AGENDA_CLEAN_COMMITMENT: {"text": "Make a public clean commitment", "per_turn": false},
	AGENDA_CHANGED_RECIPE: {"text": "Change a building's recipe", "per_turn": false},
}
# --- Advisor missions (loyalty-milestone chain; spec §7 C-layer specialties) ------
# Each employed advisor has a 5-mission chain that completes as their LOYALTY crosses
# thresholds. Rewards (per role): M1/M3 temporary specialty bonus (+ a 2nd temp for
# COO/Sustainability/Govt Affairs), M3 a free research unlock in their category, M2/M4
# a permanent slice of their seat effect, M5 the unique labour policy / a capstone.
const MISSION_COUNT := 5
# Missions I–IV complete the first turn loyalty reaches these values. Mission V is a
# capstone: loyalty must STAY at/above MISSION5_LOYALTY for MISSION5_STREAK_TURNS in a row.
const MISSION_LOYALTY_THRESHOLDS := [2.0, 5.0, 7.0, 9.0]
const MISSION5_LOYALTY := 9.0
const MISSION5_STREAK_TURNS := 20
const MISSION_TEMPLATES := {
	"cfo": {
		"temp": {"domain": "loan_interest", "pct": -50.0, "turns": 20, "label": "loan interest halved (20t)"},
		"perm1": {"domain": "loan_interest", "pct": -8.0, "label": "permanent -8% loan interest"},
		"research_category": "People & Management",
		"perm2": {"domain": "dividend_rate", "pct": -12.0, "label": "permanent -12% dividends"},
		"capstone": {"domain": "loan_interest", "pct": -15.0, "label": "permanent -15% loan interest"},
	},
	"coo": {
		"temp": {"domain": "building_power", "pct": -20.0, "turns": 20, "label": "-20% building power (20t)"},
		"perm1": {"domain": "building_power", "pct": -8.0, "label": "permanent -8% building power"},
		"research_category": "Manufacturing",
		"temp2": {"domain": "labour_headcount", "pct": -15.0, "turns": 20, "label": "-15% labour (20t)"},
		"perm2": {"domain": "maintenance", "pct": -8.0, "label": "permanent -8% maintenance"},
		"capstone": {"domain": "labour_headcount", "pct": -8.0, "label": "permanent -8% labour"},
	},
	"chief_markets": {
		"temp": {"domain": "market_spread", "pct": -40.0, "turns": 10, "label": "-40% buy spread (10t)"},
		"perm1": {"domain": "market_spread", "pct": -10.0, "label": "permanent -10% buy spread"},
		"research_category": "People & Management",
		"perm2": {"domain": "market_price", "pct": 2.0, "label": "permanent +2% sale price"},
		"capstone": {"domain": "market_price", "pct": 3.0, "label": "permanent +3% sale price"},
	},
	"chief_investment": {
		"temp": {"domain": "purchase_cost", "pct": -20.0, "turns": 20, "label": "-20% land/building prices (20t)"},
		"perm1": {"domain": "purchase_cost", "pct": -8.0, "label": "permanent -8% purchase cost"},
		"research_category": "People & Management",
		"perm2": {"domain": "construction_rebate", "pct": 5.0, "label": "permanent +5% build rebate"},
		"capstone": {"domain": "construction_rebate", "pct": 5.0, "label": "permanent +5% build rebate"},
	},
	"hr_director": {
		"temp": {"domain": "labour_headcount", "pct": -15.0, "turns": 20, "label": "-15% labour (20t)"},
		"perm1": {"domain": "labour_headcount", "pct": -6.0, "label": "permanent -6% labour"},
		"research_category": "People & Management",
		"perm2": {"domain": "maintenance", "pct": -6.0, "label": "permanent -6% maintenance"},
		"capstone": {"policy": "stock_options", "label": "unlocks the Stock Options policy"},
	},
	"technical_director": {
		"temp": {"domain": "recipe_output", "pct": 15.0, "turns": 20, "label": "+15% output (20t)"},
		"perm1": {"domain": "recipe_output", "pct": 5.0, "label": "permanent +5% output"},
		"research_category": "Metallurgy",
		"perm2": {"domain": "recipe_output", "pct": 5.0, "label": "permanent +5% output"},
		"capstone": {"domain": "recipe_output", "pct": 8.0, "label": "permanent +8% output"},
	},
	"vp_logistics": {
		"temp": {"domain": "transport_cost", "pct": -20.0, "turns": 20, "label": "-20% transport cost (20t)"},
		"perm1": {"domain": "transport_cost", "pct": -8.0, "label": "permanent -8% transport cost"},
		"research_category": "Logistics",
		"perm2": {"domain": "transport_throughput", "pct": 8.0, "label": "permanent +8% throughput"},
		"capstone": {"domain": "transport_throughput", "pct": 10.0, "label": "permanent +10% throughput"},
	},
	"government_affairs": {
		"temp": {"domain": "tax_rate", "pct": -30.0, "turns": 20, "label": "-30% tax (20t)"},
		"perm1": {"domain": "tax_rate", "pct": -8.0, "label": "permanent -8% tax"},
		"research_category": "People & Management",
		"temp2": {"domain": "market_spread", "pct": -30.0, "turns": 20, "label": "-30% buy spread (20t)"},
		"perm2": {"domain": "tax_rate", "pct": -8.0, "label": "permanent -8% tax"},
		"capstone": {"domain": "tax_rate", "pct": -10.0, "label": "permanent -10% tax"},
	},
	"sustainability": {
		"temp": {"domain": "recipe_output", "pct": 10.0, "turns": 20, "label": "+10% output (20t)"},
		"perm1": {"domain": "recipe_output", "pct": 5.0, "label": "permanent +5% output"},
		"research_category": "Renewable Power",
		"temp2": {"domain": "market_price", "pct": 3.0, "turns": 20, "label": "+3% sale price (20t)"},
		"perm2": {"domain": "market_price", "pct": 2.0, "label": "permanent +2% sale price"},
		"capstone": {"domain": "market_price", "pct": 3.0, "label": "permanent +3% sale price"},
	},
}
var advisor_missions_completed: Dictionary = {}    # advisor_id -> int (0..5)
var _advisor_mission5_streak: Dictionary = {}      # advisor_id -> consecutive turns at/above MISSION5_LOYALTY
var advisor_mission_policies: Array = []           # workforce policies unlocked via missions
signal advisor_mission_completed(advisor_id: String, mission_index: int, reward_label: String)
var advisor_loyalty: Dictionary = {}               # advisor_id -> float [-10, 10] (employed only)
var advisor_hired_turn: Dictionary = {}            # advisor_id -> turn hired (decision-gate tenure)
# CFO tax-loss carry-forward: while a CFO is seated, a losing turn banks a credit worth
# CFO_TAX_CREDIT_RATE of that turn's revenue, usable to reduce the tax bill over the next
# CFO_TAX_CREDIT_TURNS turns. Each entry is {amount: float, turns_left: int}.
const CFO_TAX_CREDIT_RATE := 0.05
const CFO_TAX_CREDIT_TURNS := 5
var cfo_tax_credit_pool: Array = []                # [{amount, turns_left}] oldest first
var cfo_tax_credit_intro_shown: bool = false       # the one-time CFO explainer has fired
signal cfo_tax_credit_filed(amount: float)         # fired once, when the FIRST credit is banked
var _advisor_walk_streak: Dictionary = {}          # advisor_id -> consecutive turns at/below walk threshold
var _agenda_flags: Dictionary = {}                 # event_tag -> true; set during the turn, read+cleared each turn
var _agenda_grid_sell_streak := 0
var _agenda_no_buy_streak := 0
var _agenda_last_build_turn := 0
signal advisor_walked(advisor_id: String)
# Advisor slot (employ-cap) unlocks: 3rd @15 buildings, 4th @100, 5th @ sustained profit.
const ADVISOR_SLOT_BUILDINGS_3 := 15
const ADVISOR_SLOT_BUILDINGS_4 := 100
const ADVISOR_SLOT_PROFIT_5 := 1000.0
const ADVISOR_SLOT_PROFIT_STREAK := 3
var _advisor_profit_streak: int = 0
var advisor_slot_profit_unlocked: bool = false
var fake_money_this_turn: float = 0.0              # cheat-added cash this turn ("fake money")
var peak_profit_per_turn: float = 0.0              # best profit/turn reached (advisor-track highpoint)

# --- Output routing ---
var output_stockpile_destinations: Dictionary = {}  # instance_id -> {tile_id, good_id}
# Optional split routes. Shape: instance_id -> {good_id -> [{tile_id, qty}]}. A
# qty of 0 means "automatic equal share"; otherwise it is the units per turn sent
# to that tile. Kept separate from the legacy single-route map for save compatibility.
var output_split_destinations: Dictionary = {}
var output_special_order_destinations: Dictionary = {}  # instance_id -> {good_id -> special_order_id}
const MARKET_DESTINATION := "__market__"  # sentinel tile_id: route this building's output to market
# Per-good SHIPPING CAP for an explicit tile route (the CTRL+click "send a specific
# amount every turn" flow): only min(cap, produced) ships to the destination each
# turn; the remainder stays in the origin tile's stockpile. 0 / absent = ship all.
var output_ship_quantities: Dictionary = {}  # instance_id -> {good_id -> int}
var input_tile_only: Dictionary = {}  # "instance_id|good_id" -> true (tile stockpile ONLY; default buys from market)
var pending_output_stockpile_selection: Dictionary = {}
var queued_stockpile_market_sales: Dictionary = {}  # tile_id -> true
var sell_surplus_tiles: Dictionary = {}              # tile_id -> true (master: auto-sell ALL surplus goods)
var auto_sell_goods: Dictionary = {}                 # tile_id -> { good_id -> true } (per-good auto-sell overrides)
var auto_sell_keep: Dictionary = {}                  # tile_id -> { good_id -> units always left on the tile ("sell all except X") }
const IMPACT_ANY := -1                               # auto-sell tolerance sentinel: no per-turn volume cap
var auto_sell_impact: Dictionary = {}                # tile_id -> max price-impact % tolerated per turn (or IMPACT_ANY)
var pending_transport_shipments: Array = []

# Which turns a (destination tile, good) actually RECEIVED a shipment. The empire view
# reports how reliably a supply line delivers, and nothing else in the sim remembers a
# delivery once its goods are in the stockpile — so this is recorded here rather than
# derived. Storing the turn numbers (not a per-turn bitmask shift) means a quiet line
# costs nothing per turn; the list is trimmed on write, so it stays tiny.
const ARRIVAL_HISTORY_TURNS := 10
var arrival_turns: Dictionary = {}          # "tile|good" -> PackedInt32Array of turn numbers
# In-progress building upgrades (mirrors Construction's project queue). Each entry is a
# dict — see start_upgrade() for the shape. While an upgrade is pending it reserves its
# extra footprint and the building keeps producing at its CURRENT level until promotion.
var pending_upgrades: Array = []
## Turns an upgrade may sit with NOTHING inbound before the shortfall is re-ordered.
## Generous on purpose: a genuinely slow haul must never trip it, and it resets on progress.
const UPGRADE_STALL_TURNS := 5
# In-progress retrofits (recipe changes): {instance_id, from_recipe, to_recipe,
# turns_remaining, labour_fraction}. The building produces nothing while retooling.
var pending_retrofits: Array = []
# In-progress demolitions: instance_id -> {turns_left, tile_id}. Completes in tick_demolish
# (materials refund + remove_building). Additive save state (default {} — no version bump).
var demolish_queue: Dictionary = {}
# Player-paused (mothballed) buildings: instance_id -> true. Skipped by production +
# labour; additive save state (default {} — no version bump).
var paused_buildings: Dictionary = {}
# Last turn's per-link flow ("tile|mode"->units) — drives this turn's congestion cost.
var _last_link_flow: Dictionary = {}
# Shallow snapshot of pending_transport_shipments from the same moment _last_link_flow
# is captured (before advance_transport_shipments() removes arrivals / decrements the
# rest). Shipment DICTS are shared with the live list — advance_transport_shipments()
# only ever mutates turns_remaining in place, which nothing here reads — but the ARRAY
# is this snapshot's own, so later arrivals falling out of pending_transport_shipments
# don't fall out of this too. Read by tile_good_breakdown() for the infra building
# detail panel's "Breakdown" table, so a tile still reports what transited it this turn
# even after arrivals have been paid out and removed from the live list.
var _last_transit_shipments: Array = []
# Per-link congestion HISTORY, for the transport panel's "at cap N of last 10 turns"
# column: "tile|mode" -> Array[bool], newest last, capped at LINK_HISTORY_TURNS.
# Appended once per turn from the same snapshot that prices congestion, so the two
# can never disagree about whether a link was over.
var _link_over_history: Dictionary = {}
# Cumulative congestion surcharge attributed to each link, "tile|mode" -> float.
# Diagnosis only — nothing prices off it. See note_congestion_surcharge().
var _link_congestion_paid: Dictionary = {}
# Shipments that arrived at a destination tile whose stockpile was full and so
# couldn't unload. They wait here and retry each turn until there's room.
# Record: {source_tile, destination_tile, good_id, qty, turns_waiting, construction_instance_id}
var overflow_shipments: Array = []
# Realised market sales per source tile THIS TURN: tile_id -> {units, revenue}.
# Reset at the start of each turn's processing so the figure is per-turn, not
# accumulated.
var sales_by_tile: Dictionary = {}
var _shipment_id_counter: int = 0
var recurring_moves: Array = []   # [{source, dest, goods}] re-issued every turn
var scheduled_moves: Array = []   # [{source, dest, goods}] one-shot, fired next turn (e.g. split)
var recurring_sells: Array = []   # [{source, goods}] re-sold to the nearest port every turn
var recurring_bulk_sells: Array = []  # [{params, turn_started}] re-run via sell_all_to_market every turn
var recurring_buys: Array = []  # [{dest, good, qty}] re-bought from market every turn
# View-only ledgers for the Transactions / Movements tabs (one-off entries; recurring
# rules are read from the recurring_* arrays). Rows: {good_id, qty, tile_from, tile_to,
# turn_started, turn_ended} (+ kind for transactions).
var transaction_log: Array = []
var move_log: Array = []
const LEDGER_MAX := 500  # keep the newest N entries so the logs stay bounded
const LARGE_SHIPMENT_THRESHOLD := 500
const LARGE_SHIPMENT_SURCHARGE := 2.0   # >500 units in one move costs 2x transport (tunable)
var tile_land_owned: Dictionary = {}
# Battery cells loaded into a tile's battery housing (deposit model — locked, refundable capital,
# NOT consumed). {tile_id -> {good_id -> qty}}. Firming = min(housing slots, Σ cells × density).
var tile_battery_cells: Dictionary = {}
# In-flight battery fills awaiting delivery: [{tile_id, good_id, qty, turns_left}]. Paid/reserved
# at order time; the cells install into the housing when turns_left hits 0 (the "operational"
# countdown). Ticked once per turn at PROCESS start.
var pending_battery_fills: Array = []

# Survey state: the set of tiles the player has surveyed (tile_id -> true).
# Dynamic; seeded with the port tiles at match start (see seed_surveyed_ports).
# A tile not in this set reads as "unsurveyed", except urban tiles and tiles in
# partially_surveyed_tiles, which read as "partially surveyed" until fully surveyed.
var surveyed_tiles: Dictionary = {}
var partially_surveyed_tiles: Dictionary = {}   # tile_id -> true (auto-revealed nearby)
var surveying_in_progress: Dictionary = {}      # tile_id -> turns remaining (>0)
var surveying_reveal: Dictionary = {}           # tile_id -> bool (auto-reveal a neighbour on completion)
const SURVEY_TURNS := 2                          # surveying a tile takes 2 turns
# Temporary-deposit depletion: remaining yield per tile per deposit token (e.g.
# tile_5_3 -> {"coal": 480}). Seeded from the CSV "(amount)" on each deposit;
# water never depletes so it is never tracked. Reaching 0 means the deposit is gone.
var deposit_remaining: Dictionary = {}
var _deposit_terrain = null  # HexMap, for counting a tile's deposits when surveyed
# Single deposits revealed by building a mine on an unsurveyed tile: existence is
# known but the size stays hidden and the tile remains "unsurveyed".
var revealed_deposits: Dictionary = {}  # tile_id -> {token: true}

# Research unlocks: which are unlocked (by free choice or by meeting a condition),
# and progress toward the action+object+quantity conditions (e.g. "Survey|tiles").
var unlocked_titles: Dictionary = {}
var _unlock_progress: Dictionary = {}
# Lifetime sales routed through any seaport. These deliberately do not share the
# market's general sales ledger: the logistics research chain requires that the
# goods actually crossed a port.
var _port_sale_total: int = 0
## Lifetime units EXPORTED through each port (port_tile -> units). Drives the Logistics
## shipping line's "through each port" condition — see docs/early-game-onboarding-spec.md §4.2b.
var _port_sales_by_port: Dictionary = {}
var _port_sales_by_class: Dictionary = {}
# Consecutive-turn progress for the infrastructure-utilisation research gates.
# Kept separately from the legacy action/object accumulator because its Quantity is
# the number of busy segments, while its duration lives in the Unit field.
var _infrastructure_usage_streaks: Dictionary = {}
var _infrastructure_usage_last_turn: Dictionary = {}
# Per-building consecutive turns that were both productive and profitable at the
# live market price. This backs the timed "Run … profitably" research gates.
var _profitable_run_streaks: Dictionary = {}
# Research conditions draw from several simulation services (production, market,
# construction, ports and CostSolver).  They must be resolved after those services
# have settled for the turn, not once for every individual shipment or building
# completion.  Mutations merely mark this central snapshot dirty; NARRATIVE owns
# the single authoritative refresh.
var _research_progress_dirty: bool = true
var _research_progress_last_turn: int = -1
# Per-tile CONSECUTIVE-turn streak of "stockpile fed by 3+ distinct buildings this
# turn" — the Just-in-Time Logistics unlock condition. Updated by Production at
# output flush; tiles that miss the bar in a turn drop out (streak resets). Saved.
var stockpile_feed_streaks: Dictionary = {}
var _unlock_defs: Array = []   # [{research_node_id, title, action, object, qty, prereqs, description}]
var _node_id_by_title: Dictionary = {}   # lazy title -> research_node_id (see research_node_id_for_title)
var _title_by_node_id: Dictionary = {}   # lazy research_node_id -> title (see research_title_for_node_id)
# Legacy research rows use a mix of internal names, display names and names of
# the process/research concept that represents a building group. Resolve those
# labels centrally so live conditions do not depend on CSV casing or wording.
const RESEARCH_BUILDING_ALIASES := {
	"oil_refinery": ["petro_refinery"],
	"coal_power_plant": ["power_plant"],
	"factory": ["industrial_factory"],
	"steel_mill": ["furnace"],
	"polymer_feedstocks": ["poly_plant"],
	"precision_reagent_handling": ["chem_plant"],
	"bioreactor": ["farm"],
	"cell_culture_automation": ["farm"],
	"modular_factory_cells": ["industrial_factory"],
	"grid_synchronous_generation": [
		"power_plant", "solar_farm", "onshore_wind_farm", "offshore_wind_farm",
		"hydro_power_plant",
	],
	"wind_farm": ["onshore_wind_farm", "offshore_wind_farm"],
	"renewable_dispatch_forecasting": [
		"solar_farm", "onshore_wind_farm", "offshore_wind_farm", "hydro_power_plant",
	],
	"pipe_network": ["pipes", "reinf_pipes"],
	"utility_corridor": ["roads", "rails", "pipes", "reinf_pipes", "cables"],
	"battery": ["battery"],
	"offshore_platform": ["offshore_oil_platform"],
	"forest": ["new_forest", "old_forest"],
	# Renamed from "power_plant" when the coal plant took that internal name (2026-07-28):
	# the alias key would otherwise swallow the literal building and make every
	# coal-plant-specific gate satisfiable by a solar farm.
	"any_power_plant": [
		"power_plant", "solar_farm", "onshore_wind_farm", "offshore_wind_farm",
		"hydro_power_plant",
	],
}
const RESEARCH_GOOD_ALIASES := {
	"bioplastics": "plastics",
	"motors": "motor",
}
# Survey range: how many tiles out from a surveyed tile you may survey. The red
# limit line and the click check both use it; +1 once Geoscanning is unlocked.
const SURVEY_RANGE_BASE := 2
var _surveyable_cache: Dictionary = {}
var _surveyable_dirty := true

enum SellMode { SELL_ALL, STOCKPILE_ALL, BUILDING_BY_BUILDING }
var sell_mode: int = SellMode.STOCKPILE_ALL

# How the transport router picks a path between two tiles. FASTEST by default.
enum RouteObjective { FASTEST, CHEAPEST, BLENDED }
var route_objective: int = RouteObjective.FASTEST


# Debug-only: verbose per-turn production / CostSolver logs. Off by default because
# large empires can produce hundreds of console lines per turn in editor builds.
# Toggled at runtime via the `logs` debug-terminal cheat. Session-only.
var debug_turn_logs_enabled: bool = false

# When true (the default since Phase 3), building clicks open the redesigned Building Detail v2
# panel. The classic v1 panel is kept as a fallback, reachable by toggling the `swap bdp` cheat.
# Session-only; never persisted. See docs/building-detail-v2-plan.md.

# The empire view's DEFAULT look: no background pattern, a large 2.5D building sprite above
# each node with its metal plate attached below. Buildings without a sprite keep the classic
# full-card layout, so partial sprite coverage degrades gracefully.
# `swap empire view sprite` toggles BACK to the classic card style. Session-only; never persisted.
var use_empire_sprite_view: bool = true

## Empire view: mark buildings that ship to market with a gold port hex on the sprite instead
## of drawing a line to the port row. `swap port badge` toggles back to lines.
## Session-only; never persisted.
var show_port_badge: bool = true

## Debug-only: `swap empire button` alternates the bottom-menu Empire View icon
## between the badge-centre default and the skyline alternative. Session-only.
var use_empire_button_badge: bool = true

# Debug-only: `swap construct_panel` keeps the classic construct panel available
# for comparison. The redesigned construct panel is the normal default.
# Session-only; the cheat only changes the active match.
var use_construct_panel_v2: bool = true

# Debug-only: `swap construct_panel_v3` keeps the pre-redesign confirm screen
# available for comparison (designer spec "Confirm Construction Panel v2",
# tracked as v3 here) inside the V2 panel. The redesigned confirm screen is
# the normal default. Session-only, never persisted.
var use_construct_panel_v3: bool = true

# Debug-only: `swap topbar v3.1` keeps the pre-redesign top bar (Goods Graph,
# Encyclopedia, Mission, Power, Victory, Rankings as text/vector-glyph faces)
# available for comparison inside the existing top_bar.gd — same "render branch
# behind a flag, not a second scene" shape as use_construct_panel_v3. The
# icon-faced redesign (baked standalone icons in assets/icons/ui_icons/standalone/)
# is the normal default. Session-only, never persisted.
var use_topbar_v3_1: bool = true

# Construct V2 defaults. They are match settings rather than panel-local state so
# a construction captures the current choices when it begins, including after a
# save/load. The legacy cost-display field remains load-compatible but is no
# longer exposed in the V2 settings UI.
var construct_cost_display: String = "grid"
var construct_start_half_capacity: bool = false
## When on, confirming a build on a tile the player has too little land for buys exactly
## enough land patches to cover the shortfall first (see world_map._space_check_for_build).
var construct_auto_buy_land: bool = false
## Off = the browse list's recipe cards show the compact mini diagram (icons + "+" +
## an arrow, no quantities); on = the full Building-Details-style diagram with qty
## pills. Display-only — never read by BuildForecast/Production.
var construct_expanded_recipe_mode: bool = false
# Defaults captured by constructions when they are started. "ask" preserves the
# existing delivery prompt; the other modes choose a source automatically.
var construct_material_source: String = "market"
## A one-build override picked from the confirm panel's materials accordion (which retired the old
## "construction materials missing" modal). NOT saved: it applies to the next build attempt only and
## clears once consumed. Empty = fall back to the standing construct_material_source setting.
var pending_build_material_source: String = ""
# New production defaults to market routing unless the player explicitly chooses
# the building's own tile stockpile.
var construct_output_destination: String = "market"
# Power supply priority (owner, 28 Aug): "self" (this category's generation covers
# local building demand before anything sells) or "grid" (this category's
# generation always sells; local demand for it is bought from the grid instead).
# Defaults avoid exposing buildings to intermittency: coal/gas (steady) self-
# serves, wind/solar (intermittent) sells and buys firm grid power instead. A
# match setting, read live every turn by Production/Power — applies to every
# power_plant/wind/solar building that exists AND any built after the player
# changes it, not captured per-instance at construction (contrast
# construct_material_source above, which IS captured per-construction).
var power_priority_coal_gas: String = "self"
var power_priority_wind_solar: String = "grid"

# --- Signals ---
signal money_changed(new_amount: float) 
signal building_added(instance: Dictionary)
signal building_removed(instance_id: String)
# A building's owner changed (e.g. the player bought an NPC building from the market). UI that
# filters by ownership (the ledger, the buildings-for-sale tab) listens to refresh live.
signal building_owner_changed(instance_id: String)
signal building_upgraded(instance_id: String, new_level: int)
# An upgrade was just queued (materials committed); the level changes later via building_upgraded.
signal building_upgrade_started(instance_id: String, target_level: int)
signal building_retrofit_started(instance_id: String, new_recipe_id: String)
signal building_retrofitted(instance_id: String, new_recipe_id: String)
# Demolish queued (1-turn countdown starts) / completed (materials refunded, building removed).
signal building_demolish_started(instance_id: String)
signal building_demolished(instance_id: String)
signal building_paused_changed(instance_id: String)
# An in-progress upgrade advanced (claimed materials / ticked down) — UI can refresh its countdown.
signal building_upgrade_progress(instance_id: String)
# An in-progress upgrade was cancelled / abandoned (e.g. the building was removed). Banked
# materials already on the tile are refunded; goods still in transit are not.
signal building_upgrade_cancelled(instance_id: String)
signal state_reset
## A goods movement was committed this turn (Victory-track feed). `kind` is
## "buy" | "move" | "sale"; `category` is the buy bucket ("input" | "building" |
## "upgrade" | "other"; "" for moves/sales); `transport_turns` is the delivery
## delay (0 = instant). Fires once per queue_buy / queue_move / MarketState.execute_sale,
## including 0-turn instant deliveries. Drives Logistics efficiency + Autarkic streak.
signal goods_movement_recorded(kind: String, category: String, transport_turns: int)
signal sell_mode_changed(new_mode: int)
signal route_objective_changed(new_objective: int)
signal labour_multiplier_changed(new_value: float)
signal workforce_policies_changed
signal advisors_changed
signal advisor_acquired(advisor_id: String)
signal advisor_loyalty_changed(advisor_id: String, loyalty: float)
signal advisor_mission_state_changed(advisor_id: String)
signal toast_requested(message: String, toast_type: String)
## A market sale was finalised at a port this turn (drives the £-rise effect).
signal market_sale_arrived_at_port(port_tile_id: String, revenue: float)
## A build was rejected for lack of funds (drives the error toast + money flash).
signal build_rejected_no_funds(message: String)
## Purchases tab asked the player to pick a delivery tile on the map.
signal buy_tile_pick_requested()
signal buy_tile_picked(tile_id: String)  # tile_id == "" means cancelled
## Market row "Expand" — open the construct panel filtered to producers of this good.
signal show_construct_for_good(good_id: String)
## Tile-view "Buy Buildings" — open the Market on the Buildings tab, filtered to this tile.
signal buildings_market_for_tile_requested(tile_id: String)
## Market row "Move" — start the on-map transfer flow for this good.
signal transfer_for_good_requested(good_id: String)
## Market-row "Purchase" asked to open the per-good buy flow.
signal purchase_for_good_requested(good_id: String)
## A UI element asked to open an Encyclopedia entry (e.g. a "More info" link).
signal encyclopedia_entry_requested(entry_id: String)
## A UI element (top-bar module, Resources-panel button) asked to toggle the
## full-screen Goods Graph view (scripts/goods_graph_view.gd).
signal goods_graph_requested
## A bottom-menu control asked to toggle the full-screen Empire View
## (scripts/empire_view.gd).
signal empire_view_requested
## The Goods Graph's expanded card asked for a good's Encyclopedia entry.
signal encyclopedia_good_requested(good_id: String)
## A good icon anywhere in the UI was clicked: open the Goods Graph focused on it, so a
## good the player is reading about is one click from how it is made and what it feeds.
signal goods_graph_good_requested(good_id: String)
## A UI element (e.g. the tile-view intermittency "see more" link) asked to open the
## building ledger pre-filtered to a single filter key (e.g. "green_intermittent").
signal building_ledger_filter_requested(filter_key: String)
## A research REQUIREMENT shown somewhere else in the UI was clicked — the tech gating a
## building upgrade, for instance. Opens the Research panel with its search box already
## holding that title, so the player lands on the node rather than on the whole tree.
signal research_search_requested(query: String)
signal output_stockpile_selection_started(selection: Dictionary)
signal output_stockpile_selection_cancelled
signal output_stockpile_destination_changed(instance_id: String, tile_id: String, good_id: String)
signal stockpile_market_sale_queue_changed(tile_id: String)
signal stockpile_market_sale_completed(sale_record: Dictionary)
signal sell_surplus_changed(tile_id: String)
## A standing recurring move / sell / bulk-sell was added or cancelled — the Market
## panel's Movements/Sales lists refresh on this.
signal recurring_orders_changed
signal transport_shipments_changed
signal tile_land_owned_changed(tile_id: String)
## Battery cells loaded/unloaded on a tile changed (drives the tile-view power section + firming).
signal battery_cells_changed(tile_id: String)
## The set of surveyed tiles changed (drives the Surveying mapmode + tile panel).
signal surveyed_tiles_changed
## A tile's in-progress survey changed (started / ticked down / finished).
signal surveying_in_progress_changed
## A tile's deposit remaining amount changed (depleted by mining).
signal deposits_changed(tile_id: String)
## A tile's deposit just reached 0 this turn (fires once, on the 0 transition).
signal deposit_exhausted(tile_id: String, token: String)
## A research unlock was granted. via_condition is true when earned by meeting its
## condition (shows the "Unlocked …" dialog); false for a free-chosen unlock.
signal unlock_granted(title: String, description: String, via_condition: bool)
signal hidden_buildings_enabled
## A tile finished being surveyed (drives the on-map survey animation). deposit_goods
## is an array of {good_id, internal_name} for the non-water deposits revealed.
signal tile_survey_completed(tile_id: String, deposit_goods: Array)
## A shipment arrived at a full tile and is now waiting to unload.
signal overflow_shipment_held(record: Dictionary)
## A special-order delivery reached port with units beyond the completed order's
## demand. The UI must ask whether to sell those units or stockpile them at port.
signal special_order_overflow_ready(record: Dictionary)
# The Building Detail v2 dev-toggle flipped (`swap bdp` cheat); world_map re-renders the
# active detail panel. Session-only.
signal construct_panel_v2_changed(enabled: bool)
# The confirm-screen v3 dev-toggle flipped (`swap construct_panel_v3` cheat); the V2
# panel re-renders so the gated visuals apply immediately. Session-only.
signal construct_panel_v3_changed(enabled: bool)
# The top-bar icon redesign dev-toggle flipped (`swap topbar v3.1` cheat); top_bar.gd
# re-renders the affected modules so the gated visuals apply immediately. Session-only.
signal topbar_v3_1_changed(enabled: bool)
signal empire_button_icon_changed(use_badge: bool)
signal construct_settings_changed
signal power_priority_changed
## A UI surface (notification deep-link, etc.) asks the map to focus a tile:
## centre the camera on it and open its tile panel. world_map handles it.
signal focus_tile_requested(tile_id: String)
## Like focus_tile_requested, but opens the building detail panel for a specific
## building instance (centring the camera on its tile). Used by starvation
## notifications' "Go to".
signal focus_building_requested(instance_id: String)
## The top bar's Transport module asks world_map to open the logistics panel.
signal transport_panel_requested
## A transport-panel stockpile row asks the map to open that tile's Stockpile tab.
signal tile_stockpile_requested(tile_id: String)

# --- Initialization ---
func _ready() -> void:
	money = EconomyConfig.STARTING_MONEY
	money_changed.emit(money)
	_load_unlock_defs()
	# TurnManager is registered after MatchState, so wire the per-turn survey tick
	# once every autoload exists.
	call_deferred("_connect_turn_signals")

func _connect_turn_signals() -> void:
	# _on_survey_phase_started is wired centrally by TurnManager._wire_sim_listeners
	# so the intra-phase order across sim systems is explicit, not autoload-order.
	if Production != null and not Production.turn_processed.is_connected(_on_turn_processed_advisors):
		Production.turn_processed.connect(_on_turn_processed_advisors)
	if not goods_movement_recorded.is_connected(_on_goods_movement_agenda):
		goods_movement_recorded.connect(_on_goods_movement_agenda)

# Fast-shipment agenda: a movement that lands in 1 turn (delivered in under 2).
func _on_goods_movement_agenda(_kind: String, _category: String, transport_turns: int) -> void:
	if transport_turns >= 1 and transport_turns < 2:
		flag_agenda_event(AGENDA_FAST_SHIPMENT)

func _on_survey_phase_started(phase: int) -> void:
	if phase == TurnManager.Phase.PROCESS:
		tick_labour_output_pressure()
		tick_surveys()
		tick_battery_fills()
	elif phase == TurnManager.Phase.NARRATIVE:
		# Production, costs and run-streaks have settled for the turn — one central
		# research pass reads the final production/sales/profitability state.  This
		# deliberately replaces per-shipment and per-completion scans.
		_update_profitable_run_streaks()
		_refresh_research_progress()
# --- Public API: money ---
func add_money(delta: float) -> void:
	money += delta
	money_changed.emit(money)

func deduct_money(amount: float) -> bool:  # was: int
	if money < amount:
		return false
	money -= amount
	money_changed.emit(money)
	return true

# --- Public API: buildings ---
func is_player_owned(building: Dictionary) -> bool:
	# NPC-owned infrastructure (e.g. the shipping corporation's ports) is not the
	# player's to pay for. Buildings default to the local player when owner is unset.
	return str(building.get("owner", LOCAL_PLAYER)) == LOCAL_PLAYER

## The owner a wood standing on the land itself carries — no company holds it.
const LAND_OWNER := "tile_data"

## A wood that belongs to the LAND rather than to a company. Every authored wood the start
## layout does not already cover is seeded as one of these, and there is no company to buy it
## from — so felling one is clearing ground, not taking someone's property, and it is allowed
## (owner, 2026-08-29: all forests should be demolishable). A wood a COMPANY owns still has to
## be bought first, exactly like any other building of theirs.
func is_land_owned_wood(building: Dictionary) -> bool:
	return str(building.get("owner", LOCAL_PLAYER)) == LAND_OWNER \
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
	
	# Update tile index
	if not tile_buildings.has(tile_id):
		tile_buildings[tile_id] = []
	tile_buildings[tile_id].append(instance_id)

	if emit_added:
		building_added.emit(instance)
		# Construction can complete several buildings in one PROCESS pass.  Defer
		# research evaluation to NARRATIVE so that batch costs stay constant.
		_mark_research_progress_dirty()
	return instance_id

# Transfer ownership of an existing building (e.g. the player buys an NPC building from the
# market). Changing the owner is all that's needed for the building to become the player's: the
# production pass rebuilds its player-owned set each turn, so a bought building runs from next
# turn. Emits building_owner_changed so ownership-filtered UI refreshes immediately.
func set_building_owner(instance_id: String, owner: String) -> void:
	if not buildings.has(instance_id):
		return
	if str(buildings[instance_id].get("owner", LOCAL_PLAYER)) == owner:
		return
	buildings[instance_id]["owner"] = owner
	# Buying bundles the land under the building: grant its footprint as owned land on the tile.
	if owner == LOCAL_PLAYER:
		_stamp_purchase_build_value(instance_id)
		_grant_building_land(instance_id)
		# The tile size chart stacks buildings bought off an NPC at the top of the pile.
		buildings[instance_id]["acquired_from_npc"] = true
		# A purchase is a going concern, so it arrives with stock to run on. Seeded HERE rather
		# than in the market panel because three separate surfaces transfer ownership (market
		# panel, building detail, tile info) and the tutorial buys through one of them.
		seed_purchase_inventory(instance_id)
	building_owner_changed.emit(instance_id)
	# A newly player-owned building may satisfy a count condition after the turn
	# settles; never trigger a full scan from an interaction callback.
	_mark_research_progress_dirty()

# Sell a player-owned building to an NPC operator: credit its market value (what it would list
# at), flip ownership to the NPC — the building keeps standing and its land stays occupied, but it
# stops running for you (production rebuilds the player-owned set each turn). Instantaneous.
func sell_building(instance_id: String) -> Dictionary:
	if not buildings.has(instance_id):
		return {"ok": false, "reason": "No such building."}
	if not is_player_owned(buildings[instance_id]):
		return {"ok": false, "reason": "You don't own this building."}
	var price: int = int(round(float(BuildingPrice.sale_price(buildings[instance_id]))))
	add_money(float(price))
	set_building_owner(instance_id, SOLD_TO_OWNER)  # emits building_owner_changed → UI refresh
	request_toast("Sold building for £%d" % price, "success")
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
		add_money(float(price))
		set_building_owner(str(instance_id), SOLD_TO_OWNER)
		total += price
		count += 1
	if count > 0:
		request_toast("Distressed sale: %d buildings for £%d" % [count, total], "warning")
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

# Total materials needed to take `internal` to `target`, resolved to {good_id: qty}.
func _upgrade_need_by_gid(internal: String, target: int) -> Dictionary:
	var need_by_gid: Dictionary = {}
	for gi in BuildingLevels.upgrade_materials(internal, target):
		var gid := str(Catalog.get_good_by_internal_name(str(gi)).get("id", ""))
		if gid != "":
			need_by_gid[gid] = int(BuildingLevels.upgrade_materials(internal, target)[gi])
	return need_by_gid

# Extra tile footprint a building takes when it grows from `from_level` to `target`.
## One sentence saying which gate refused the upgrade and what it would take to pass it.
## Empty when the building fits.
func _fits_reason(tile_id: String, delta: float, fits_physical: bool, fits_owned: bool) -> String:
	if fits_physical and fits_owned:
		return ""
	if not fits_physical:
		var free := float(max_tile_land(tile_id)) - get_tile_space_used(tile_id)
		return ("The larger building needs %s more space than this tile has. It grows by %s, and only %s is free of the tile's %s."
			% [_land(delta - free), _land(delta), _land(free), _land(float(max_tile_land(tile_id)))])
	var free_owned := get_tile_land_owned(tile_id) - get_tile_player_space_used(tile_id)
	return ("You do not own enough of this tile. The upgrade needs %s and only %s of your %s is free — buy land to make room."
		% [_land(delta), _land(free_owned), _land(get_tile_land_owned(tile_id))])

## Land figures read as whole units unless the fraction matters.
func _land(v: float) -> String:
	return str(int(round(v))) if absf(v - round(v)) < 0.05 else "%.1f" % v

func _upgrade_size_delta(building_id: String, from_level: int, target: int) -> float:
	var base_size := float(Catalog.get_building(building_id).get("tile_size_used", 1.0))
	return base_size * (BuildingLevels.mult("size", target) - BuildingLevels.mult("size", from_level))

func is_upgrading(instance_id: String) -> bool:
	for p in pending_upgrades:
		if str(p.get("instance_id", "")) == instance_id:
			return true
	return false

# --- Retrofit / retooling (advisor spec §7) ---------------------------------

func is_retooling(instance_id: String) -> bool:
	for p in pending_retrofits:
		if str(p.get("instance_id", "")) == instance_id:
			return true
	return false

func retrofit_turns_remaining(instance_id: String) -> int:
	for p in pending_retrofits:
		if str(p.get("instance_id", "")) == instance_id:
			return int(p.get("turns_remaining", 0))
	return 0

# Per-turn labour fraction while a building is retooling (1.0 if it isn't).
func retooling_labour_fraction(instance_id: String) -> float:
	for p in pending_retrofits:
		if str(p.get("instance_id", "")) == instance_id:
			return float(p.get("labour_fraction", 1.0))
	return 1.0

# Retrofit cost/speed tier from the seated COO's Operations stat (base if no COO).
func retrofit_cost_tier() -> Dictionary:
	var a: Dictionary = _roster_entry(str(advisor_seats.get("coo", "")))
	var key := "base"
	if not a.is_empty():
		key = "ops%d" % clampi(int(a.get("ops", 1)), 1, 3)
	return EconomyConfig.RETROFIT_TIERS.get(key, EconomyConfig.RETROFIT_TIERS["base"])

# Begin changing a built building's recipe. Charges the one-off fee up front; the
# building produces nothing (reduced labour) until the countdown completes.
func start_retrofit(instance_id: String, new_recipe_id: String) -> Dictionary:
	if not buildings.has(instance_id):
		return {"ok": false, "reason": "No such building."}
	if is_retooling(instance_id):
		return {"ok": false, "reason": "Already retooling."}
	if is_upgrading(instance_id):
		return {"ok": false, "reason": "An upgrade is in progress."}
	var inst: Dictionary = buildings[instance_id]
	var new_recipe: Dictionary = Catalog.get_recipe(new_recipe_id)
	if new_recipe.is_empty() or str(new_recipe.get("building_id", "")) != str(inst.get("building_id", "")):
		return {"ok": false, "reason": "That recipe can't run in this building."}
	if new_recipe_id == str(inst.get("recipe_id", "")):
		return {"ok": false, "reason": "Already running that recipe."}
	var tier: Dictionary = retrofit_cost_tier()
	if not deduct_money(float(tier.get("fee", 0.0))):
		return {"ok": false, "reason": "Not enough money for the retooling fee."}
	pending_retrofits.append({
		"instance_id": instance_id,
		"from_recipe": str(inst.get("recipe_id", "")),
		"to_recipe": new_recipe_id,
		"turns_remaining": int(tier.get("turns", 2)),
		"labour_fraction": float(tier.get("labour", 0.5)),
	})
	flag_agenda_event(AGENDA_CHANGED_RECIPE)
	building_retrofit_started.emit(instance_id, new_recipe_id)
	return {"ok": true, "turns": int(tier.get("turns", 2)), "fee": float(tier.get("fee", 0.0))}

# Advance every retrofit one turn; on completion swap the recipe. Returns completed ids.
func tick_retrofits() -> Array:
	var completed: Array = []
	var remaining: Array = []
	for p in pending_retrofits:
		var iid := str(p.get("instance_id", ""))
		if not buildings.has(iid):
			continue   # building vanished mid-retool
		p["turns_remaining"] = int(p.get("turns_remaining", 0)) - 1
		if int(p["turns_remaining"]) <= 0:
			buildings[iid]["recipe_id"] = str(p.get("to_recipe", ""))
			completed.append(iid)
			building_retrofitted.emit(iid, str(p.get("to_recipe", "")))
		else:
			remaining.append(p)
	pending_retrofits = remaining
	return completed

# Abandon a retrofit; the building resumes its original recipe (fee not refunded).
func cancel_retrofit(instance_id: String) -> bool:
	var kept: Array = []
	var found := false
	for p in pending_retrofits:
		if str(p.get("instance_id", "")) == instance_id:
			found = true
		else:
			kept.append(p)
	pending_retrofits = kept
	if found:
		building_retrofit_started.emit(instance_id, "")   # UI refresh
	return found

func pending_upgrade(instance_id: String) -> Dictionary:
	for p in pending_upgrades:
		if str(p.get("instance_id", "")) == instance_id:
			return p
	return {}


## Read-only progress snapshot for an upgrade button / diagnostics row. `turns_remaining`
## alone is not an ETA while a project is awaiting materials: the three-turn build countdown
## does not start until every outstanding unit has arrived and been claimed. This folds in the
## tagged shipments and overflow queue, and reports why no finite estimate can be made.
func upgrade_progress_snapshot(instance_id: String) -> Dictionary:
	var pending := pending_upgrade(instance_id)
	if pending.is_empty():
		return {}
	var countdown := maxi(0, int(pending.get("turns_remaining", 0)))
	var status := str(pending.get("status", ""))
	if status == UPGRADE_STATUS_UPGRADING:
		return {
			"status": status, "blocked": false, "estimated_turns": countdown,
			"tooltip": "Estimated completion: %d turn%s." % [countdown, "" if countdown == 1 else "s"],
		}
	if status != UPGRADE_STATUS_AWAITING:
		var unknown := "The upgrade has an unknown progress state ('%s')." % status
		return {
			"status": status, "blocked": true, "estimated_turns": -1,
			"error": unknown,
			"tooltip": "Upgrade paused — estimated completion unavailable.\n%s" % unknown,
		}

	var tile_id := str(pending.get("tile_id", ""))
	var missing: Dictionary = pending.get("missing", {})
	var blockers: Array = []
	var material_eta := 1  # even on-tile goods are claimed on the next processed turn
	var overflow_qty := 0
	for gid_value in missing:
		var gid := str(gid_value)
		var needed := maxi(0, int(missing[gid_value]))
		if needed <= 0:
			continue
		var accounted := mini(needed, Stockpile.get_at_tile(tile_id, gid))
		var latest_eta := 0
		for shipment in pending_transport_shipments:
			if str((shipment as Dictionary).get("upgrade_instance_id", "")) != instance_id \
					or str((shipment as Dictionary).get("destination_tile", "")) != tile_id \
					or str((shipment as Dictionary).get("good_id", "")) != gid:
				continue
			var enroute_take := mini(maxi(0, needed - accounted), int((shipment as Dictionary).get("qty", 0)))
			accounted += enroute_take
			if enroute_take > 0:
				latest_eta = maxi(latest_eta, int((shipment as Dictionary).get("turns_remaining", 0)))
		for overflow in overflow_shipments:
			if str((overflow as Dictionary).get("upgrade_instance_id", "")) != instance_id \
					or str((overflow as Dictionary).get("destination_tile", "")) != tile_id \
					or str((overflow as Dictionary).get("good_id", "")) != gid:
				continue
			var held := mini(maxi(0, needed - accounted), int((overflow as Dictionary).get("qty", 0)))
			accounted += held
			overflow_qty += held
			if held > 0:
				latest_eta = maxi(latest_eta, 1)
		material_eta = maxi(material_eta, latest_eta)
		if accounted >= needed:
			continue
		var short := needed - accounted
		var good_name := Catalog.get_display_name(gid)
		var quote := TransportService.quote_market_buy(tile_id, gid, short, seaport_would_cover(gid))
		if quote.is_empty():
			blockers.append("No road, rail or suitable pipe route can deliver %s to this tile." % good_name)
		else:
			blockers.append("No shipment is carrying the remaining %d %s." % [short, good_name])

	if overflow_qty > Stockpile.get_free_capacity(tile_id):
		blockers.append("The tile stockpile is too full to unload the remaining upgrade materials.")

	if not blockers.is_empty():
		var error := " ".join(blockers)
		return {
			"status": status, "blocked": true, "estimated_turns": -1,
			"error": error,
			"tooltip": "Upgrade paused — estimated completion unavailable.\n%s" % error,
		}
	var estimated := material_eta + countdown
	var waiting_text := "Materials are on their way." if material_eta > 1 else "Materials will be claimed next turn."
	return {
		"status": status, "blocked": false, "estimated_turns": estimated,
		"tooltip": "%s Estimated completion: %d turn%s." % [waiting_text, estimated, "" if estimated == 1 else "s"],
	}

# Footprint reserved on a tile by upgrades-in-progress (so a second build can't slip into
# room the growing building is about to claim). Counted by get_tile_space_used.
func reserved_upgrade_space_on_tile(tile_id: String) -> float:
	var total := 0.0
	for p in pending_upgrades:
		if str(p.get("tile_id", "")) == tile_id:
			total += float(p.get("size_delta", 0.0))
	return total

## Everything the upgrade dialog needs to render: cost (materials, sourcing, £), the
## benefit/cost deltas (cur→new per aspect), the research gate, footprint fit and the
## 3-turn duration. Read-only — commits nothing. Returns {ok:false, reason} when there's
## no building or it's already maxed.
## Infrastructure whose per-tile level can be upgraded for cash (slot key == building
## internal_name for all five). Port/airport are not levellable.
const INFRA_UPGRADABLE: Array = ["roads", "rails", "pipes", "reinf_pipes", "cables"]

## Tile-seeded infrastructure (CSV cables/rails and the baked road network) has no
## MatchState building instance. TileViewData gives those slots a stable synthetic id
## (`tile_<tile_id>_<slot>`) so the shared building-detail upgrade UI can still address
## them. Resolve that id back to the tile + canonical slot, but only while the slot is
## actually installed on the live HexMap tile.
func _tile_backed_infra_instance(upgrade_id: String) -> Dictionary:
	if not upgrade_id.begins_with("tile_"):
		return {}
	for slot_value in INFRA_UPGRADABLE:
		var slot := str(slot_value)
		var suffix := "_" + slot
		if not upgrade_id.ends_with(suffix):
			continue
		var tile_id := upgrade_id.substr(5, upgrade_id.length() - 5 - suffix.length())
		if tile_id == "" or not _tile_has_infrastructure_slot(tile_id, slot):
			continue
		var building: Dictionary = Catalog.get_building_by_internal_name(slot)
		if building.is_empty():
			return {}
		return {
			"instance_id": upgrade_id,
			"building_id": str(building.get("id", "")),
			"tile_id": tile_id,
			"owner": "tile_data",
		}
	return {}

func _tile_has_infrastructure_slot(tile_id: String, slot: String) -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	var hm = tree.get_first_node_in_group("hex_map")
	if hm == null:
		return false
	var coord = hm.id_to_coord(tile_id)
	if not hm.tiles.has(coord):
		return false
	for present_value in (hm.tiles[coord] as Dictionary).get("infrastructure_present", []):
		var present := str(present_value).strip_edges().to_lower()
		if present in ["rail", "railway", "railways"]:
			present = "rails"
		elif present in ["pipework", "pipeworks"]:
			present = "pipes"
		elif present in ["reinforced_pipes", "reinforced pipework"]:
			present = "reinf_pipes"
		if present == slot:
			return true
	return false

## The tile-level a levellable infra instance sits at (the TILE dict is the gameplay
## source of truth — power caps and transport capacity read it, not the instance).
func infra_tile_level(inst: Dictionary) -> int:
	var internal := str(Catalog.get_building(str(inst.get("building_id", ""))).get("internal_name", ""))
	return _tile_infra_level(str(inst.get("tile_id", "")), "rail" if internal == "rails" else internal)

## Write an infra slot's level on the HexMap tile (persisted via the save's structured
## infrastructure snapshot). No-ops headless (no map), like the reads.
func set_tile_infra_level(tile_id: String, slot_key: String, level: int) -> void:
	# Mirror into the router FIRST and unconditionally: a level changes how far one turn-move
	# reaches (EconomyConfig.INFRA_RANGE_BY_LEVEL), and Catalog cannot read the HexMap tile —
	# it routes headless. Doing it before the early-outs below means a headless caller still
	# gets correct routing even with no map node in the tree.
	Catalog.set_tile_infra_level(tile_id, slot_key, level)
	var tree := get_tree()
	if tree == null:
		return
	var hm = tree.get_first_node_in_group("hex_map")
	if hm == null:
		return
	var coord = hm.id_to_coord(tile_id)
	if not hm.tiles.has(coord):
		return
	var tile: Dictionary = hm.tiles[coord]
	var levels: Dictionary = tile.get("infrastructure_levels", {})
	levels[slot_key] = level
	tile["infrastructure_levels"] = levels
	hm.tiles[coord] = tile

# Cash-only infra upgrade quote (owner ruling: £150 → L2, £350 → L3; no materials, no
# research). Capacity deltas come from the live cap tables so the sheet shows the truth.
func _preview_infra_upgrade(inst: Dictionary, internal: String) -> Dictionary:
	var instance_id := str(inst.get("instance_id", ""))
	var building_name := str(Catalog.get_building(str(inst.get("building_id", ""))).get("display_name", internal))
	var level := infra_tile_level(inst)
	if level >= BuildingLevels.MAX_LEVEL:
		return {"ok": true, "at_max": true, "infra": true, "building_name": building_name, "from_level": level}
	var target := level + 1
	var cost := float(EconomyConfig.INFRA_UPGRADE_CASH_COST.get(target, 0.0))
	var pend := pending_upgrade(instance_id)
	return {
		"ok": true, "at_max": false, "infra": true,
		"building_name": building_name,
		"from_level": level, "target_level": target,
		"duration": BuildingLevels.UPGRADE_DURATION,
		"cash_cost": cost, "affordable": money >= cost,
		"capacity": _infra_capacity_delta(internal, level, target),
		"research_gate": "", "research_locked": false,
		"materials": [], "all_on_tile": true, "market_sourceable": true,
		"source_tile": "", "source_turns": 0, "market_cost": 0.0, "fits": true,
		"already_upgrading": not pend.is_empty(),
		"pending_turns_left": int(pend.get("turns_remaining", 0)),
		"pending_status": str(pend.get("status", "")),
		"stats": {}, "unit_cost": {},
	}

## Goods sitting on a tile that some OTHER pending job has already claimed.
##
## An awaiting project keeps the part of its kit it has already gathered IN THE TILE
## STOCKPILE -- the sell-surplus reserve protects it there until `claim_materials` takes it
## (construction.gd's own note says so) -- and an awaiting upgrade does the same. So a raw
## `Stockpile.get_at_tile` reading counts goods that are spoken for, and a second job started
## against them would find them gone. What is gathered is the full bill minus what is still
## missing, which is exactly what both records carry.
##
## `except_instance_id` drops one job's own claim, so previewing a job does not reserve
## against itself.
func reserved_materials_on_tile(tile_id: String, except_instance_id: String = "") -> Dictionary:
	var out: Dictionary = {}
	for instance_id in Construction.construction_projects:
		var project: Dictionary = Construction.construction_projects[instance_id]
		if str(project.get("tile_id", "")) != tile_id:
			continue
		if str(instance_id) == except_instance_id:
			continue
		if str(project.get("status", "")) != Construction.STATUS_AWAITING_MATERIALS:
			continue
		var missing: Dictionary = project.get("missing_materials", {})
		for gid in project.get("required_materials", {}):
			var gathered: int = maxi(int(project["required_materials"][gid])
				- int(missing.get(gid, 0)), 0)
			if gathered > 0:
				out[gid] = int(out.get(gid, 0)) + gathered
	for pending_value in pending_upgrades:
		var pending: Dictionary = pending_value
		if str(pending.get("tile_id", "")) != tile_id:
			continue
		if str(pending.get("instance_id", "")) == except_instance_id:
			continue
		if str(pending.get("status", "")) != UPGRADE_STATUS_AWAITING:
			continue
		var short: Dictionary = pending.get("missing", {})
		for gid in pending.get("materials", {}):
			var banked: int = maxi(int(pending["materials"][gid]) - int(short.get(gid, 0)), 0)
			if banked > 0:
				out[gid] = int(out.get(gid, 0)) + banked
	return out


func _infra_capacity_delta(internal: String, level: int, target: int) -> Dictionary:
	if internal == "cables":
		return {"label": "Power capacity", "unit": "power/turn",
			"cur": float(EconomyConfig.CABLE_POWER_CAP.get(level, 0)),
			"new": float(EconomyConfig.CABLE_POWER_CAP.get(target, 0))}
	var mode := "rail" if internal == "rails" else internal
	return {"label": "Transport capacity", "unit": "units/turn",
		"cur": tile_mode_capacity(mode, level),
		"new": tile_mode_capacity(mode, target)}

func preview_upgrade(instance_id: String) -> Dictionary:
	if not buildings.has(instance_id):
		var tile_infra := _tile_backed_infra_instance(instance_id)
		if tile_infra.is_empty():
			return {"ok": false, "reason": "No such building."}
		var tile_internal := str(Catalog.get_building(str(tile_infra.get("building_id", ""))).get("internal_name", ""))
		return _preview_infra_upgrade(tile_infra, tile_internal)
	var inst: Dictionary = buildings[instance_id]
	var level := int(inst.get("level", 1))
	var building_id := str(inst.get("building_id", ""))
	var building_name := str(Catalog.get_building(building_id).get("display_name", building_id))
	var infra_internal := str(Catalog.get_building(building_id).get("internal_name", ""))
	if INFRA_UPGRADABLE.has(infra_internal):
		return _preview_infra_upgrade(inst, infra_internal)
	if level >= BuildingLevels.MAX_LEVEL:
		return {"ok": true, "at_max": true, "building_name": building_name, "from_level": level}
	var target := level + 1
	var internal := str(Catalog.get_building(building_id).get("internal_name", ""))
	var tile_id := str(inst.get("tile_id", ""))

	# Materials — needed / on-tile / shortfall, and the £ to buy the shortfall.
	var need_by_gid := _upgrade_need_by_gid(internal, target)
	var materials: Array = []
	var shortfall: Dictionary = {}
	var market_cost := 0.0
	var market_sourceable := true  # false if any shortfall good has no port route to this tile
	# What another awaiting job on this tile has already banked is on the tile but not
	# available -- see reserved_materials_on_tile.
	var claimed := reserved_materials_on_tile(tile_id, instance_id)
	var all_free := true
	for gid in need_by_gid:
		var need := int(need_by_gid[gid])
		var have := Stockpile.get_at_tile(tile_id, gid)
		var free := maxi(have - int(claimed.get(gid, 0)), 0)
		if free < need:
			all_free = false
		var short := maxi(0, need - have)
		if short > 0:
			shortfall[gid] = short
			var quote: Dictionary = preview_buy(tile_id, gid, short)
			if quote.is_empty():
				market_sourceable = false
			else:
				market_cost += float(quote.get("cost", 0.0))
		materials.append({
			"good_id": gid, "name": Catalog.get_display_name(gid),
			"need": need, "have": have, "short": short, "free": free,
		})
	var all_on_tile := shortfall.is_empty()
	# The kit is usable off the tile only when every good is there AND unclaimed.
	var all_on_tile_free := all_on_tile and all_free

	# A single other tile that can cover the whole shortfall (powers the "use stockpile" CTA).
	var source := Construction.find_source_tile(tile_id, shortfall) if not all_on_tile else {}

	# Footprint check (the larger building must still fit, counting other pending upgrades).
	# Physical room uses everything on the tile; the owned-land gate only counts the
	# player's own estate (NPC buildings sit on their own land).
	var delta := _upgrade_size_delta(building_id, level, target)
	var projected := get_tile_space_used(tile_id) + delta
	var projected_player := get_tile_player_space_used(tile_id) + delta
	var fits_physical: bool = projected <= float(max_tile_land(tile_id))
	var fits_owned: bool = projected_player <= float(get_tile_land_owned(tile_id))
	var fits: bool = fits_physical and fits_owned

	var gate := BuildingLevels.research_gate(internal, target)
	var pend := pending_upgrade(instance_id)
	return {
		"ok": true,
		"at_max": false,
		"building_name": building_name,
		"from_level": level,
		"target_level": target,
		"duration": BuildingLevels.UPGRADE_DURATION,
		"research_gate": gate,
		"research_locked": gate != "" and not is_unlocked(gate),
		"materials": materials,
		"all_on_tile": all_on_tile,
		"all_on_tile_free": all_on_tile_free,
		"market_sourceable": market_sourceable,
		"source_tile": str(source.get("tile_id", "")),
		"source_turns": int(source.get("turns", 0)),
		"market_cost": market_cost,
		"fits": fits,
		# WHY it does not fit, and by how much. "Not enough room" over a tile panel reading
		# "122 owned" reads as a bug: the binding limit is usually the tile's PHYSICAL space,
		# which counts the NPC buildings sitting on it, not the land the player owns.
		"fits_reason": _fits_reason(tile_id, delta, fits_physical, fits_owned),
		"size_delta": delta,
		"already_upgrading": not pend.is_empty(),
		"pending_turns_left": int(pend.get("turns_remaining", 0)),
		"pending_status": str(pend.get("status", "")),
		"stats": _upgrade_stat_deltas(instance_id, level, target),
		"unit_cost": _upgrade_cost_per_unit(instance_id, level, target),
	}

# cur→new for every aspect the dialog shows, computed via the live engine at each level.
func _upgrade_stat_deltas(instance_id: String, level: int, target: int) -> Dictionary:
	var cur: Dictionary = Production.stats_at_level(instance_id, level)
	var new_s: Dictionary = Production.stats_at_level(instance_id, target)
	return {"cur": cur, "new": new_s}

## Production cost per unit of (primary) output at the current vs target level, matching the
## live CostSolver model: gross = input materials + power + labour + maintenance + inbound transport,
## per unit = allocated to the primary output. Components scale by their per-level multipliers
## (inputs/transport ×input, power ×energy, labour ×labour, maintenance ×maint) while output ×output;
## the market-value allocation fraction is level-independent so it cancels. Returns {cur,new} or {}.
func _upgrade_cost_per_unit(instance_id: String, from_level: int, target: int) -> Dictionary:
	if not buildings.has(instance_id):
		return {}
	var input_cost := 0.0
	var power_cost := 0.0
	var labour := 0.0
	var maint := 0.0
	var transport := 0.0
	var primary_qty := 0.0
	var unit_cur := -1.0
	# Prefer the live CostSolver breakdown (real input prices, transport, modifiers).
	var cs: Dictionary = (CostSolver.last_result.get("per_building", {}) as Dictionary).get(instance_id, {})
	if not cs.is_empty():
		input_cost = float(cs.get("input_material_cost", 0.0))
		power_cost = float(cs.get("power_cost", 0.0))
		labour = float(cs.get("labour_cost", 0.0))
		maint = float(cs.get("maintenance_cost", 0.0))
		transport = float(cs.get("inbound_transport", 0.0))
		primary_qty = float(cs.get("output_qty", 0.0))
		unit_cur = float(cs.get("unit_cost", -1.0))
	else:
		# Fallback (building hasn't produced yet): build it from the current-level stats.
		var cur: Dictionary = Production.stats_at_level(instance_id, from_level)
		if cur.is_empty():
			return {}
		for inp in cur.get("inputs", []):
			input_cost += MarketState.get_price(str(inp.get("good_id", ""))) * float(inp.get("qty", 0))
		power_cost = float(cur.get("energy", 0.0)) * EconomyConfig.GRID_BUY_PRICE
		labour = float(cur.get("labour", 0.0))
		maint = float(cur.get("maintenance", 0.0))
		var outs: Array = cur.get("outputs", [])
		primary_qty = float(outs[0].get("qty", 0)) if outs.size() > 0 else 0.0
	var total_cur := input_cost + power_cost + labour + maint + transport
	if primary_qty <= 0.0 or total_cur <= 0.0:
		return {}
	if unit_cur < 0.0:
		unit_cur = total_cur / primary_qty
	# Component ratios from the CURRENT level to the target level.
	var ri := BuildingLevels.mult("input", target) / BuildingLevels.mult("input", from_level)
	var re := BuildingLevels.mult("energy", target) / BuildingLevels.mult("energy", from_level)
	var rl := BuildingLevels.mult("labour", target) / BuildingLevels.mult("labour", from_level)
	var rm := BuildingLevels.mult("maint", target) / BuildingLevels.mult("maint", from_level)
	var ro := BuildingLevels.mult("output", target) / BuildingLevels.mult("output", from_level)
	var total_new := input_cost * ri + power_cost * re + labour * rl + maint * rm + transport * ri
	var unit_new := unit_cur * (total_new / total_cur) / ro
	return {"cur": unit_cur, "new": unit_new}

const UPGRADE_STATUS_AWAITING := "awaiting_materials"
const UPGRADE_STATUS_UPGRADING := "upgrading"

## Begin a 3-turn upgrade. `mode` decides where the shortfall comes from:
##   "tile"     — every material is already on the tile (consumed now, countdown starts).
##   "market"   — buy the shortfall from the nearest port (cost charged now via queue_buy).
##   "transfer" — move the shortfall in from another tile (source picked by find_source_tile).
## The on-tile portion is always consumed immediately so production can't eat it; the
## countdown only begins once every material has been claimed. Returns {ok, reason, status}.
func start_upgrade(instance_id: String, mode: String = "tile") -> Dictionary:
	if not buildings.has(instance_id):
		var tile_infra := _tile_backed_infra_instance(instance_id)
		if tile_infra.is_empty():
			return {"ok": false, "reason": "No such building."}
		if is_upgrading(instance_id):
			return {"ok": false, "reason": "An upgrade is already in progress."}
		var tile_internal := str(Catalog.get_building(str(tile_infra.get("building_id", ""))).get("internal_name", ""))
		return _start_infra_upgrade(instance_id, tile_infra, tile_internal)
	if is_upgrading(instance_id):
		return {"ok": false, "reason": "An upgrade is already in progress."}
	var inst: Dictionary = buildings[instance_id]
	# Levellable infrastructure: cash-only, no materials/research, level read from and
	# (at completion) written back to the TILE — the gameplay source of truth.
	var infra_internal := str(Catalog.get_building(str(inst.get("building_id", ""))).get("internal_name", ""))
	if INFRA_UPGRADABLE.has(infra_internal):
		return _start_infra_upgrade(instance_id, inst, infra_internal)
	var level := int(inst.get("level", 1))
	if level >= BuildingLevels.MAX_LEVEL:
		return {"ok": false, "reason": "Already at the maximum level."}
	var target := level + 1
	var building_id := str(inst.get("building_id", ""))
	var internal := str(Catalog.get_building(building_id).get("internal_name", ""))
	var tile_id := str(inst.get("tile_id", ""))

	var gate := BuildingLevels.research_gate(internal, target)
	if gate != "" and not is_unlocked(gate):
		return {"ok": false, "reason": "Requires research: %s" % gate, "research": gate}

	# Footprint: the larger building must fit (counting other in-progress upgrades).
	# Physical room counts everything; the owned-land gate only the player's estate.
	var size_delta := _upgrade_size_delta(building_id, level, target)
	var projected := get_tile_space_used(tile_id) + size_delta
	var projected_player := get_tile_player_space_used(tile_id) + size_delta
	var room_physical: bool = projected <= float(max_tile_land(tile_id))
	var room_owned: bool = projected_player <= float(get_tile_land_owned(tile_id))
	if not (room_physical and room_owned):
		return {"ok": false, "reason": _fits_reason(tile_id, size_delta, room_physical, room_owned)}

	# Split materials: what's on the tile vs the shortfall.
	var need_by_gid := _upgrade_need_by_gid(internal, target)
	var shortfall: Dictionary = {}
	for gid in need_by_gid:
		var short := int(need_by_gid[gid]) - Stockpile.get_at_tile(tile_id, gid)
		if short > 0:
			shortfall[gid] = short

	# Validate the chosen sourcing BEFORE consuming anything — start_upgrade is atomic, so a
	# broke wallet / no port / no spare tile fails cleanly with nothing taken off the tile.
	var transfer_source: Dictionary = {}
	if not shortfall.is_empty():
		match mode:
			"tile":
				return {"ok": false, "reason": "Upgrade materials missing on the tile.", "missing": shortfall, "required": need_by_gid}
			"market":
				var total := 0.0
				for gid in shortfall:
					var quote: Dictionary = preview_buy(tile_id, str(gid), int(shortfall[gid]))
					if quote.is_empty():
						return {"ok": false, "reason": "No market route to deliver %s to this tile." % Catalog.get_display_name(str(gid))}
					total += float(quote.get("cost", 0.0))
				if total > money:
					return {"ok": false, "reason": "Not enough money to order the missing materials (≈£%d)." % int(ceil(total))}
			"transfer":
				transfer_source = Construction.find_source_tile(tile_id, shortfall)
				if transfer_source.is_empty():
					return {"ok": false, "reason": "No single tile has the spare stock to transfer."}
			_:
				return {"ok": false, "reason": "Unknown sourcing mode."}

	# Cleared to commit. Reserve the in-place portion now (mirrors construction): consume what
	# we already have so co-located production can't claim it before the upgrade does.
	for gid in need_by_gid:
		var on_tile := int(need_by_gid[gid]) - int(shortfall.get(gid, 0))
		if on_tile > 0:
			Stockpile.consume(tile_id, gid, on_tile)

	# Queue the shortfall (cost / freight is charged inside queue_buy / queue_move).
	if not shortfall.is_empty():
		if mode == "market":
			for gid in shortfall:
				queue_buy(tile_id, str(gid), int(shortfall[gid]), false, {"upgrade_instance_id": instance_id})
		elif mode == "transfer":
			queue_move(str(transfer_source.get("tile_id", "")), tile_id, shortfall, false, {"upgrade_instance_id": instance_id})

	var status := UPGRADE_STATUS_UPGRADING if shortfall.is_empty() else UPGRADE_STATUS_AWAITING
	pending_upgrades.append({
		"instance_id": instance_id,
		"building_id": building_id,
		"tile_id": tile_id,
		"from_level": level,
		"target_level": target,
		"status": status,
		"materials": need_by_gid.duplicate(true),  # full kit — for refunding banked goods on cancel
		"missing": shortfall.duplicate(true),
		"turns_remaining": BuildingLevels.UPGRADE_DURATION,
		"size_delta": size_delta,
	})
	# Chief Investment rebates a fraction of the upgrade kit's market value (like a build).
	var up_rebate := _materials_rebate(need_by_gid)
	if up_rebate > 0.0:
		add_money(up_rebate)
	building_upgrade_started.emit(instance_id, target)
	return {"ok": true, "status": status, "target_level": target}

# Cash-only infra upgrade: charge up front, run the same 3-turn countdown, and let
# tick_upgrades write the new level onto the tile. No kit → no Chief-Investment rebate
# (deliberately: cash isn't a material kit, and it closes the start/cancel rebate pump
# for this path).
func _start_infra_upgrade(instance_id: String, inst: Dictionary, internal: String) -> Dictionary:
	var level := infra_tile_level(inst)
	if level >= BuildingLevels.MAX_LEVEL:
		return {"ok": false, "reason": "Already at the maximum level."}
	var target := level + 1
	var cost := float(EconomyConfig.INFRA_UPGRADE_CASH_COST.get(target, 0.0))
	if money < cost:
		return {"ok": false, "reason": "Not enough money — the upgrade costs £%d." % int(cost)}
	add_money(-cost)
	pending_upgrades.append({
		"instance_id": instance_id,
		"building_id": str(inst.get("building_id", "")),
		"tile_id": str(inst.get("tile_id", "")),
		"from_level": level,
		"target_level": target,
		"status": UPGRADE_STATUS_UPGRADING,
		"materials": {},
		"missing": {},
		"turns_remaining": BuildingLevels.UPGRADE_DURATION,
		"size_delta": 0.0,
		"infra": true,
		"infra_slot": internal,     # slot key == building internal for all five
		"cash_paid": cost,
	})
	building_upgrade_started.emit(instance_id, target)
	return {"ok": true, "status": UPGRADE_STATUS_UPGRADING, "target_level": target}

## Advance every in-progress upgrade one turn. Awaiting projects claim any newly-arrived
## materials off the tile (this runs before production consumes, so there's no race); once
## fully stocked they start counting down, and at zero the building's level is bumped.
## Returns the instance_ids that completed this turn. Called from Production each PROCESS.
func tick_upgrades() -> Array:
	var completed: Array = []
	var remaining: Array = []
	for p in pending_upgrades:
		var instance_id := str(p.get("instance_id", ""))
		var is_infra := bool(p.get("infra", false))
		# Production upgrades still require their building. Tile-backed infrastructure
		# deliberately has no building instance; its tile slot is the persistent target.
		if not buildings.has(instance_id) and not is_infra:
			continue
		if is_infra and not buildings.has(instance_id) \
				and not _tile_has_infrastructure_slot(str(p.get("tile_id", "")), str(p.get("infra_slot", ""))):
			continue
		if str(p.get("status", "")) == UPGRADE_STATUS_AWAITING:
			var tile_id := str(p.get("tile_id", ""))
			var missing: Dictionary = p.get("missing", {})
			var still: Dictionary = {}
			for gid in missing:
				var want := int(missing[gid])
				var got := Stockpile.consume(tile_id, str(gid), want)
				if got < want:
					still[gid] = want - got
			p["missing"] = still
			if still.is_empty():
				p["status"] = UPGRADE_STATUS_UPGRADING
				p["stalled_turns"] = 0
			else:
				_retry_stalled_upgrade(p, instance_id, tile_id, still)
			building_upgrade_progress.emit(instance_id)
			remaining.append(p)
			continue
		# Under upgrade — count down, promote at zero.
		p["turns_remaining"] = int(p.get("turns_remaining", 0)) - 1
		if int(p["turns_remaining"]) <= 0:
			var new_level := int(p.get("target_level", 1))
			if is_infra:
				# The TILE dict is what power caps / transport capacity read. A player-built
				# infra slot also has an instance, but seeded slots intentionally do not.
				set_tile_infra_level(str(p.get("tile_id", "")), str(p.get("infra_slot", "")), new_level)
				if buildings.has(instance_id):
					(buildings[instance_id] as Dictionary)["level"] = new_level
			else:
				var inst: Dictionary = buildings[instance_id]
				new_level = int(p.get("target_level", int(inst.get("level", 1)) + 1))
				inst["level"] = new_level
			completed.append(instance_id)
			building_upgraded.emit(instance_id, new_level)
		else:
			building_upgrade_progress.emit(instance_id)
			remaining.append(p)
	pending_upgrades = remaining
	return completed

## An upgrade waiting on materials that nothing is carrying will wait FOREVER: the buy is
## queued once, at start_upgrade, and if that shipment is never made or is lost on the way
## there is nothing that would ever order another. Two buildings sat like that for the whole
## back half of a playtest, saying "No shipment is carrying the remaining N" every turn.
##
## So: once an upgrade has stood UPGRADE_STALL_TURNS turns with nothing inbound, re-order the
## shortfall down the same path start_upgrade used. Only genuinely STRANDED goods are
## re-ordered — a slow shipment still on the road is not stalled — and the counter resets on
## any progress, so a long haul never triggers it.
func _retry_stalled_upgrade(p: Dictionary, instance_id: String, tile_id: String,
		still: Dictionary) -> void:
	var stranded: Dictionary = {}
	for gid_value in still:
		var gid := str(gid_value)
		if not _upgrade_has_inbound(instance_id, tile_id, gid):
			stranded[gid] = int(still[gid_value])
	if stranded.is_empty():
		p["stalled_turns"] = 0   # something is still on its way; waiting is correct
		return
	var stalled := int(p.get("stalled_turns", 0)) + 1
	p["stalled_turns"] = stalled
	if stalled < UPGRADE_STALL_TURNS:
		return
	p["stalled_turns"] = 0
	var ordered: Array = []
	var refused: Array = []
	for gid_value in stranded:
		var gid := str(gid_value)
		var qty := int(stranded[gid_value])
		if queue_buy(tile_id, gid, qty, false, {"upgrade_instance_id": instance_id}).is_empty():
			refused.append(Catalog.get_display_name(gid))
		else:
			ordered.append("%d %s" % [qty, Catalog.get_display_name(gid)])
	var building_id := str(get_building(instance_id).get("building_id", str(p.get("building_id", ""))))
	var what := str(Catalog.get_building(building_id).get("display_name", "An upgrade"))
	if not ordered.is_empty():
		request_toast("%s was waiting on materials nothing was carrying — re-ordered %s."
			% [what, ", ".join(ordered)], "info")
	elif not refused.is_empty():
		# The retry itself could not be placed. Say why rather than silently waiting again.
		request_toast("%s cannot be supplied with %s — no route, no headroom, or imports are banned."
			% [what, ", ".join(refused)], "warn")

## Is anything actually carrying `gid` to this upgrade right now?
func _upgrade_has_inbound(instance_id: String, tile_id: String, gid: String) -> bool:
	for list_variant: Variant in [pending_transport_shipments, overflow_shipments]:
		for shipment_variant: Variant in (list_variant as Array):
			var shipment: Dictionary = shipment_variant
			if str(shipment.get("upgrade_instance_id", "")) != instance_id:
				continue
			if str(shipment.get("destination_tile", "")) != tile_id:
				continue
			if str(shipment.get("good_id", "")) == gid and int(shipment.get("qty", 0)) > 0:
				return true
	return false

## Cancel an in-progress upgrade and hand the player back the materials it has already banked
## on the tile (full kit minus whatever's still in transit). Goods still being shipped in keep
## arriving and simply land in the tile stockpile. Returns true if an upgrade was cancelled.
func cancel_upgrade(instance_id: String) -> bool:
	var kept: Array = []
	var cancelled := false
	for p in pending_upgrades:
		if str(p.get("instance_id", "")) != instance_id:
			kept.append(p)
			continue
		cancelled = true
		var tile_id := str(p.get("tile_id", ""))
		var materials: Dictionary = p.get("materials", {})
		var missing: Dictionary = p.get("missing", {})
		# Banked = everything claimed so far (full kit minus what's still outstanding).
		for gid in materials:
			var banked := int(materials[gid]) - int(missing.get(gid, 0))
			if banked > 0:
				Stockpile.add(tile_id, str(gid), banked)
		# Infra upgrades are paid in cash up front — refund it in full (net zero, so
		# there's no start/cancel pump on this path).
		var cash_paid := float(p.get("cash_paid", 0.0))
		if cash_paid > 0.0:
			add_money(cash_paid)
	pending_upgrades = kept
	if cancelled:
		building_upgrade_cancelled.emit(instance_id)
	return cancelled

func remove_building(instance_id: String) -> bool:
	if not buildings.has(instance_id):
		return false

	# Refund any in-progress upgrade's banked materials before the building disappears,
	# and drop any queued retrofit so it can't sit in limbo against a dead instance.
	cancel_upgrade(instance_id)
	cancel_retrofit(instance_id)

	var instance: Dictionary = buildings[instance_id]
	var tile_id: String = instance.tile_id
	
	# Remove from tile index
	if tile_buildings.has(tile_id):
		tile_buildings[tile_id].erase(instance_id)
		if tile_buildings[tile_id].is_empty():
			tile_buildings.erase(tile_id)
	
	buildings.erase(instance_id)
	paused_buildings.erase(instance_id)
	output_stockpile_destinations.erase(instance_id)
	output_special_order_destinations.erase(instance_id)
	# Removing battery housing shrinks the tile's cell slots — refund any now-excess loaded cells.
	if str(Catalog.get_building(str(instance.get("building_id", ""))).get("category", "")) == "battery":
		refund_battery_cells_over_slots(tile_id)
	building_removed.emit(instance_id)
	return true

# --- Demolish refund -------------------------------------------------------------------
# What demolishing `instance_id` would return: the build money plus EVERY material kit
# consumed over the building's life — the construction kit AND each completed upgrade
# level's kit (2..level) — scaled by EconomyConfig.demolish_refund_share. Pure: no state
# change. `materials` is good_id -> qty; `materials_value` is their worth at current market
# price; `total` is the all-cash-equivalent headline (money + materials_value).
# NOTE: this only COMPUTES the refund. Applying it (crediting money/materials, then
# remove_building) is the demolish action, handled later — see refund_plan for the payout split.
func refund_cost(instance_id: String) -> Dictionary:
	var empty := {"money": 0.0, "materials": {}, "materials_value": 0.0, "total": 0.0}
	var inst: Dictionary = buildings.get(instance_id, {})
	if inst.is_empty():
		return empty

	var share: float = EconomyConfig.demolish_refund_share
	var building_id: String = str(inst.get("building_id", ""))
	var building: Dictionary = Catalog.get_building(building_id)

	# Money leg: the real paid cost if it was stamped at promotion, else build_cost_money.
	var money_paid: float = float(inst.get("build_cost", building.get("base_price", 0.0)))

	# Material leg: the construction kit (good_id -> qty), stored at promotion or recomputed.
	var mats: Dictionary = {}
	var build_kit: Dictionary = inst.get("build_materials", {})
	if build_kit.is_empty():
		build_kit = Construction.requirements_for(building_id)
	for gid in build_kit:
		mats[gid] = int(mats.get(gid, 0)) + int(build_kit[gid])

	# ...plus every completed upgrade level's kit (keyed by internal_name -> good_id).
	var internal: String = str(building.get("internal_name", ""))
	var level: int = int(inst.get("level", 1))
	for lvl in range(2, level + 1):
		var kit: Dictionary = BuildingLevels.upgrade_materials(internal, lvl)
		for iname in kit:
			var gid: String = str(Catalog.get_good_by_internal_name(str(iname)).get("id", ""))
			if gid == "":
				continue
			mats[gid] = int(mats.get(gid, 0)) + int(kit[iname])

	# Apply the refund share to money and (rounded) material quantities; value at market.
	var out_mats: Dictionary = {}
	var mats_value: float = 0.0
	for gid in mats:
		var qty: int = int(round(float(mats[gid]) * share))
		if qty <= 0:
			continue
		out_mats[gid] = qty
		mats_value += float(qty) * MarketState.get_price(gid)

	var money: float = money_paid * share
	return {
		"money": money,
		"materials": out_mats,
		"materials_value": mats_value,
		"total": money + mats_value,
	}

# How a demolish refund would actually be paid out given the building tile's storage room.
# Materials are returned to the tile stockpile up to its free capacity; any overflow that
# won't fit is offered as cash at current market price. The demolish dialog pops the
# cash-offer when `fits_fully` is false. Pure: reads capacity/prices, mutates nothing.
func refund_plan(instance_id: String) -> Dictionary:
	var refund: Dictionary = refund_cost(instance_id)
	var inst: Dictionary = buildings.get(instance_id, {})
	var tile_id: String = str(inst.get("tile_id", ""))
	var room: int = Stockpile.get_free_capacity(tile_id) if tile_id != "" else 0

	var to_stockpile: Dictionary = {}
	var cash_overflow: float = 0.0
	for gid in refund.materials:
		var qty: int = int(refund.materials[gid])
		var fit: int = clampi(qty, 0, room)
		if fit > 0:
			to_stockpile[gid] = fit
			room -= fit
		var overflow: int = qty - fit
		if overflow > 0:
			cash_overflow += float(overflow) * MarketState.get_price(gid)

	return {
		"money": refund.money,                # always paid as cash
		"to_stockpile": to_stockpile,         # good_id -> qty that fits in the tile
		"cash_overflow": cash_overflow,       # market value of what didn't fit
		"fits_fully": cash_overflow == 0.0,   # false -> pop the cash-offer dialog
		"materials": refund.materials,
		"materials_value": refund.materials_value,
		"total_if_cash": refund.total,        # money + all materials valued as cash
	}

# --- Pause (mothball) ------------------------------------------------------------------------
# A paused building produces nothing and draws no inputs/power/labour, but keeps its upkeep.
# Used by the supply-chain panel when a sold/demolished building leaves a neighbour stranded.
func is_building_paused(instance_id: String) -> bool:
	return bool(paused_buildings.get(instance_id, false))

func set_building_paused(instance_id: String, paused: bool) -> void:
	if not buildings.has(instance_id):
		return
	if paused:
		paused_buildings[instance_id] = true
	else:
		paused_buildings.erase(instance_id)
	building_paused_changed.emit(instance_id)

# --- Demolish (queued 1-turn job) ------------------------------------------------------------
func is_demolishing(instance_id: String) -> bool:
	return demolish_queue.has(instance_id)

func demolish_turns_remaining(instance_id: String) -> int:
	return int((demolish_queue.get(instance_id, {}) as Dictionary).get("turns_left", 0))

# Queue a player-owned building for demolition (completes in DEMOLISH_TURNS via tick_demolish).
func start_demolish(instance_id: String) -> Dictionary:
	if not buildings.has(instance_id):
		return {"ok": false, "reason": "No such building."}
	if not is_player_owned(buildings[instance_id]) and not is_land_owned_wood(buildings[instance_id]):
		return {"ok": false, "reason": "You don't own this building."}
	if demolish_queue.has(instance_id):
		return {"ok": false, "reason": "Already demolishing."}
	demolish_queue[instance_id] = {"turns_left": DEMOLISH_TURNS, "tile_id": str(buildings[instance_id].get("tile_id", ""))}
	building_demolish_started.emit(instance_id)
	return {"ok": true}

func cancel_demolish(instance_id: String) -> bool:
	if not demolish_queue.has(instance_id):
		return false
	demolish_queue.erase(instance_id)
	building_demolish_started.emit(instance_id)
	return true

# Advance queued demolitions one turn; complete any that reach zero — refund half the material
# kits to the tile stockpile (overflow → cash), then remove the building (frees its land). No
# money is returned (that's Sell). Returns the instance_ids removed this turn.
func tick_demolish() -> Array:
	var completed: Array = []
	for iid in demolish_queue.keys():
		var job: Dictionary = demolish_queue[iid]
		job["turns_left"] = int(job.get("turns_left", 0)) - 1
		if int(job["turns_left"]) > 0:
			continue
		if buildings.has(iid):
			var plan: Dictionary = refund_plan(iid)
			var tile_id: String = str(buildings[iid].get("tile_id", ""))
			for gid in (plan.get("to_stockpile", {}) as Dictionary):
				Stockpile.add(tile_id, str(gid), int(plan["to_stockpile"][gid]))
			var cash: float = float(plan.get("cash_overflow", 0.0))
			if cash > 0.0:
				add_money(cash)
			remove_building(iid)
		demolish_queue.erase(iid)
		completed.append(iid)
		building_demolished.emit(iid)
	return completed

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
	total += reserved_upgrade_space_on_tile(tile_id)
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

# --- Public API: survey state ---
## Seed the surveyed set with the NPC port tiles (called once at match start).
func seed_surveyed_ports() -> void:
	for port in Catalog.all_ports():
		var tile_id := str(port.get("tile_id", ""))
		if tile_id != "":
			surveyed_tiles[tile_id] = true
	_surveyable_dirty = true
	surveyed_tiles_changed.emit()

## Mark a batch of tiles surveyed in one shot (one signal emit). Used by the
## "All tiles surveyed at game start" Advanced Setting at world build.
func mark_tiles_surveyed(tile_ids: Array) -> void:
	var changed := false
	for tid in tile_ids:
		var s := str(tid)
		if s != "" and not surveyed_tiles.has(s):
			surveyed_tiles[s] = true
			changed = true
	if changed:
		_surveyable_dirty = true
		surveyed_tiles_changed.emit()

func is_tile_surveyed(tile_id: String) -> bool:
	return surveyed_tiles.has(tile_id)

## Mark a tile fully surveyed (no-op if already surveyed).
func mark_tile_surveyed(tile_id: String) -> void:
	if tile_id == "" or surveyed_tiles.has(tile_id):
		return
	surveyed_tiles[tile_id] = true
	_surveyable_dirty = true
	surveyed_tiles_changed.emit()

## Survey status for a tile: "surveyed", "partial", or "unsurveyed". Urban tiles
## (and tiles auto-revealed by a nearby survey) read as partially surveyed until
## fully surveyed; pass the tile's type so this needs no tile-data lookup.
func survey_status(tile_id: String, tile_type: String = "") -> String:
	if surveyed_tiles.has(tile_id):
		return "surveyed"
	if partially_surveyed_tiles.has(tile_id) or tile_type.strip_edges().to_lower() == "urban":
		return "partial"
	return "unsurveyed"

func is_survey_in_progress(tile_id: String) -> bool:
	return surveying_in_progress.has(tile_id)

func survey_turns_left(tile_id: String) -> int:
	return int(surveying_in_progress.get(tile_id, 0))

## Begin a 2-turn survey of a tile (cost is charged by the caller). reveal_nearby
## auto-(partially-)surveys one neighbour on completion — true for a full survey of
## an unsurveyed tile, false when just finishing a partially surveyed tile.
func begin_survey(tile_id: String, reveal_nearby: bool = true) -> void:
	if tile_id == "" or surveyed_tiles.has(tile_id) or surveying_in_progress.has(tile_id):
		return
	surveying_in_progress[tile_id] = SURVEY_TURNS
	surveying_reveal[tile_id] = reveal_nearby
	surveying_in_progress_changed.emit()

## Mark a tile partially surveyed (auto-revealed by a nearby survey).
func mark_tile_partial(tile_id: String) -> void:
	if tile_id == "" or surveyed_tiles.has(tile_id) or partially_surveyed_tiles.has(tile_id):
		return
	partially_surveyed_tiles[tile_id] = true
	surveyed_tiles_changed.emit()

## Tick every in-progress survey down by one turn; complete any that hit zero.
## Called once per turn during the PROCESS phase.
func tick_surveys() -> void:
	if surveying_in_progress.is_empty():
		return
	var done: Array = []
	for tile_id in surveying_in_progress:
		surveying_in_progress[tile_id] = int(surveying_in_progress[tile_id]) - 1
		if int(surveying_in_progress[tile_id]) <= 0:
			done.append(tile_id)
	for tile_id in done:
		var reveal: bool = bool(surveying_reveal.get(tile_id, true))
		surveying_in_progress.erase(tile_id)
		surveying_reveal.erase(tile_id)
		_complete_survey(tile_id, reveal)
	surveying_in_progress_changed.emit()

func _complete_survey(tile_id: String, reveal_nearby: bool) -> void:
	partially_surveyed_tiles.erase(tile_id)
	mark_tile_surveyed(tile_id)
	# Surveying a tile counts toward the research conditions (tiles + deposits found,
	# pure water excluded) and drives the on-map survey animation.
	var found: Array = _tile_deposit_goods(tile_id)
	record_unlock_progress("Survey", "tiles", 1)
	record_unlock_progress("Survey", "deposits", found.size())
	tile_survey_completed.emit(tile_id, found)
	request_toast(_survey_toast(tile_id, found), "info")
	if not reveal_nearby:
		return
	# A full survey auto-(partially-)surveys a neighbour; Hyperspectral Remote Sensing
	# reveals one extra ("+1 adjacent tile revealed when surveying").
	var reveals := 2 if is_unlocked("Hyperspectral Remote Sensing") else 1
	for _i in reveals:
		var fresh: Array = []
		for n in Catalog.tile_neighbours(tile_id):
			if not surveyed_tiles.has(n) and not partially_surveyed_tiles.has(n) and not surveying_in_progress.has(n):
				fresh.append(n)
		if fresh.is_empty():
			break
		mark_tile_partial(str(fresh[_match_rng_int(fresh.size())]))

# --- Public API: depletable deposits ---
## Seed each tile's depletable-deposit yields from its CSV deposits. Water is
## permanent and never seeded. Call once at match start (see world_map._ready).
func seed_deposits(terrain) -> void:
	_deposit_terrain = terrain
	deposit_remaining.clear()
	for coord in terrain.tiles:
		var td: Dictionary = terrain.tiles[coord]
		var tid := str(td.get("id", ""))
		for dep in td.get("deposits", []):
			var token := _deposit_token_of(str(dep))
			var qty := _deposit_qty_of(str(dep))
			qty = _normalized_deposit_qty(token, qty)
			if token == "" or token == "water" or qty <= 0:
				continue
			if not deposit_remaining.has(tid):
				deposit_remaining[tid] = {}
			deposit_remaining[tid][token] = qty

## True when `tile_id` carries an INEXHAUSTIBLE deposit of `token`.
##
## Not answerable from `deposit_remaining`: seed_deposits skips anything with qty <= 0, so an
## infinite deposit is absent from that map entirely and `deposit_remaining_for` returns -1
## for "inexhaustible" and for "no deposit here" alike. The distinction lives in the terrain,
## which is what this reads.
func has_infinite_deposit(tile_id: String, token: String) -> bool:
	for d in _tile_deposit_goods(tile_id):
		if str((d as Dictionary).get("internal_name", "")) == token:
			return bool((d as Dictionary).get("infinite", false))
	return false

## Remaining yield of a deposit, or -1 if the deposit isn't tracked (e.g. water,
## or a deposit given no amount in the CSV). 0 means it has been mined out.
func deposit_remaining_for(tile_id: String, token: String) -> int:
	return int((deposit_remaining.get(tile_id, {}) as Dictionary).get(token, -1))

func deposit_depleted(tile_id: String, token: String) -> bool:
	return int((deposit_remaining.get(tile_id, {}) as Dictionary).get(token, -1)) == 0

## Reduce a tile's deposit by the amount mined this turn (floored at 0 = gone).
func deplete_deposit(tile_id: String, token: String, amount: int) -> void:
	if amount <= 0 or not deposit_remaining.has(tile_id):
		return
	var t: Dictionary = deposit_remaining[tile_id]
	if not t.has(token) or int(t[token]) <= 0:
		return
	t[token] = maxi(0, int(t[token]) - amount)
	deposits_changed.emit(tile_id)
	if int(t[token]) == 0:
		deposit_exhausted.emit(tile_id, token)

## True if a deposit's existence is known to the player: fully surveyed reveals
## everything; otherwise a deposit must have been individually revealed (by
## building a mine on it).
func is_deposit_revealed(tile_id: String, token: String) -> bool:
	if surveyed_tiles.has(tile_id):
		return true
	return (revealed_deposits.get(tile_id, {}) as Dictionary).has(token)

## Reveal one deposit's existence (size stays hidden, tile stays unsurveyed).
func reveal_deposit(tile_id: String, token: String) -> void:
	if tile_id == "" or token == "":
		return
	if not revealed_deposits.has(tile_id):
		revealed_deposits[tile_id] = {}
	if revealed_deposits[tile_id].has(token):
		return
	revealed_deposits[tile_id][token] = true
	surveyed_tiles_changed.emit()  # refresh tile panel + deposits overlay

func _deposit_token_of(raw: String) -> String:
	var p := raw.find("(")
	return (raw.substr(0, p) if p >= 0 else raw).strip_edges().to_lower()

func _deposit_qty_of(raw: String) -> int:
	var o := raw.find("(")
	var c := raw.find(")")
	if o >= 0 and c > o:
		var digits := ""
		for ch in raw.substr(o + 1, c - o - 1):
			if ch >= "0" and ch <= "9":
				digits += ch
		if digits != "":
			return int(digits)
	return -1

func _normalized_deposit_qty(token: String, qty: int) -> int:
	if token != "coal" and token != "iron_ore":
		return qty
	if qty <= 0:
		return qty
	if qty <= 2000:
		return 2000
	if qty <= 4000:
		return 4000
	return -1

## The non-water deposits on a tile as [{good_id, internal_name}]. Pure water is
## excluded (it is permanent and does not count as a found deposit / for unlocks).
func _tile_deposit_goods(tile_id: String) -> Array:
	var out: Array = []
	if _deposit_terrain == null:
		return out
	var coord: Vector2i = _deposit_terrain.id_to_coord(tile_id)
	if not _deposit_terrain.tiles.has(coord):
		return out
	for dep in _deposit_terrain.tiles[coord].get("deposits", []):
		var token := _deposit_token_of(str(dep))
		if token == "" or token == "water":
			continue
		var qty := _deposit_qty_of(str(dep))  # -1 => no amount given => infinite deposit
		var good: Dictionary = Catalog.get_good_by_internal_name(token)
		out.append({
			"good_id": str(good.get("id", token)),
			"internal_name": token,
			"display_name": str(good.get("display_name", token)),
			"qty": qty,
			"infinite": qty < 0,
		})
	return out

## "Survey complete." toast describing what a finished survey revealed.
func _survey_toast(tile_id: String, found: Array) -> String:
	var label := tile_id.trim_prefix("tile_")
	if found.is_empty():
		return "Survey complete. Tile %s showed no resources." % label
	var parts: Array = []
	for d in found:
		var name := str(d.get("display_name", d.get("internal_name", ""))).capitalize()
		if bool(d.get("infinite", false)):
			parts.append("an inexhaustible deposit of %s" % name)
		else:
			var size := "large" if int(d.get("qty", 0)) >= 500 else "small"
			parts.append("a %s deposit of %s" % [size, name])
	return "Survey complete. Tile %s revealed %s." % [label, _join_and(parts)]

func _join_and(parts: Array) -> String:
	if parts.size() <= 1:
		return str(parts[0]) if parts.size() == 1 else ""
	if parts.size() == 2:
		return "%s and %s" % [str(parts[0]), str(parts[1])]
	var head: Array = parts.slice(0, parts.size() - 1)
	return "%s, and %s" % [", ".join(head), str(parts[parts.size() - 1])]

func _join_or(parts: Array) -> String:
	if parts.size() <= 1:
		return str(parts[0]) if parts.size() == 1 else ""
	if parts.size() == 2:
		return "%s or %s" % [str(parts[0]), str(parts[1])]
	var head: Array = parts.slice(0, parts.size() - 1)
	return "%s, or %s" % [", ".join(head), str(parts[parts.size() - 1])]

## Research nodes hidden for the demo (owner 2026-09-06). The CSV row is kept so the node
## can return post-demo, but it never loads: no tab card, no condition, no prereq link.
## Its recipe is hidden in step via Catalog.HIDDEN_RECIPE_IDS.
const HIDDEN_RESEARCH_IDS := {
	"research_petro_020": true,   # Methane Pyrolysis — no methane in the demo
	"research_biochem_002": true, # Enzyme Screening — bioplastics chain not in the demo
	"research_biochem_003": true, # Bioplastic Precursors — same
	"research_inorg_023": true,   # Zero-Liquid Discharge — replaced by Novel Membrane Filtration (inorg_025)
	"research_biochem_005": true, # Cell Culture Automation — bioplastics chain not in the demo
}

## Shared content gate, independent of tiers and prerequisites. Search and every
## grant path must respect these flags, including exact-title links and free picks.
func is_research_visible(definition: Dictionary) -> bool:
	var node_id := str(definition.get("research_node_id", ""))
	if HIDDEN_RESEARCH_IDS.has(node_id):
		return false
	if str(definition.get("category", "")) == "Recycling" and not recycling_unlocked:
		return false
	if node_id in ["research_people_008", "research_people_009", "research_people_010", "research_people_011"] and not advisors_unlocked:
		return false
	return true

# --- Public API: research unlocks ---
func _load_unlock_defs() -> void:
	_unlock_defs.clear()
	_node_id_by_title.clear()   # rebuilt lazily against the rows loaded below
	_title_by_node_id.clear()
	var path := "res://data/research_unlocks.csv"
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var header := f.get_csv_line()
	var idx := {}
	for i in header.size():
		idx[header[i].strip_edges()] = i
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.is_empty() or row[0].strip_edges() == "":
			continue
		if HIDDEN_RESEARCH_IDS.has(_csv_at(row, idx, "research_node_id")):
			continue   # demo-hidden node: never loads, so nothing can link to it
		var prereqs: Array = []
		for col in ["prereq_1", "prereq_2", "prereq_3"]:
			var p := _csv_at(row, idx, col)
			if p != "":
				prereqs.append(p)
		var q := _csv_at(row, idx, "Quantity")
		var rank_raw := _csv_at(row, idx, "rank").strip_edges().to_upper()
		_unlock_defs.append({
			"research_node_id": _csv_at(row, idx, "research_node_id"),
			"title": _csv_at(row, idx, "title"),
			"category": _csv_at(row, idx, "category"),
			"rank": rank_raw if rank_raw != "" else "I",
			"action": _csv_at(row, idx, "Action"),
			"object": _csv_at(row, idx, "Object"),
			"qty": int(q) if q.is_valid_int() else _leading_int(q, 0),
			"quantity_raw": q,
			"unit": _csv_at(row, idx, "Unit"),
			"prereqs": prereqs,
			"description": _csv_at(row, idx, "description"),
		})
	f.close()

func _csv_at(row: PackedStringArray, idx: Dictionary, col: String) -> String:
	if not idx.has(col):
		return ""
	var i: int = idx[col]
	return row[i].strip_edges() if i < row.size() else ""

## Stable id for a research node's display title, or "" if the title is unknown.
## `research_node_id` (research_unlocks.csv, assigned by tools/assign_research_ids.py) is
## the permanent handle: renaming a node's title must not silently deaden the effects
## keyed to it, which is what happened twice while UNLOCK_MODIFIERS was title-keyed.
## Titles remain the canonical key in SAVES for now — see docs note in that tool.
func research_node_id_for_title(title: String) -> String:
	if _node_id_by_title.is_empty():
		for d in _unlock_defs:
			var t := str(d.get("title", ""))
			var nid := str(d.get("research_node_id", ""))
			if t != "" and nid != "":
				_node_id_by_title[t] = nid
	return str(_node_id_by_title.get(title, ""))


## Display title for a research node id, or "" if unknown. The inverse of
## research_node_id_for_title — used where a stored id has to be shown to the player
## (a gated recipe's "requires research: …" line) so raw ids never reach the UI.
func research_title_for_node_id(node_id: String) -> String:
	if _title_by_node_id.is_empty():
		for d in _unlock_defs:
			var t := str(d.get("title", ""))
			var nid := str(d.get("research_node_id", ""))
			if t != "" and nid != "":
				_title_by_node_id[nid] = t
	return str(_title_by_node_id.get(node_id, ""))


## Accepts a research_node_id (what prereq columns and recipe gates now store), a display
## title (what SAVES still store), or a bare cheat token like "hydro"/"consumer" that has
## no node at all. Taking all three keeps every gate call site unchanged across the id
## migration — only what the DATA stores changed.
func is_unlocked(title_or_id: String) -> bool:
	if unlocked_titles.has(title_or_id):
		return true
	var mapped := research_title_for_node_id(title_or_id)
	return mapped != "" and unlocked_titles.has(mapped)

# Grant the first not-yet-unlocked research node in a category (an advisor-mission
# reward). Returns the granted title, or "" if the category is already fully unlocked.
func grant_first_locked_in_category(category: String) -> String:
	for d in _unlock_defs:
		if str(d.get("category", "")) == category:
			var title := str(d.get("title", ""))
			if title != "" and not is_unlocked(title) and is_research_visible(d):
				grant_unlock(title)
				return title
	return ""

# Deposit penalty + mining-yield research now live in the Modifiers system as
# recipe_output tiles (Modifiers.EXTRACTION_PENALTY_PCT + the mining UNLOCK_MODIFIERS),
# so they apply through the one production hook and surface in the recipe card's
# net-modifier indicator. The old get_deposit_yield()/PENALISED_EXTRACTION/
# RESEARCH_YIELD_BONUS triplet was removed.

## Grant an unlock. via_condition true => earned by its condition (drives the
## "Unlocked …" dialog); false => a free-chosen unlock (no dialog).
func grant_unlock(title: String, via_condition: bool = false) -> void:
	if title == "" or unlocked_titles.has(title):
		return
	var definition := get_unlock_def(title)
	if definition.is_empty() or not is_research_visible(definition):
		return
	unlocked_titles[title] = true
	# Opening the rest of the council is not a modifier, so it is applied here rather than
	# through apply_unlock_modifier. See docs/early-game-onboarding-spec.md §5.4.
	if title == SEATS_UNLOCK_TITLE:
		all_seats_unlocked = true
		advisors_changed.emit()
	_surveyable_dirty = true  # e.g. Geoscanning changes survey range
	flag_agenda_event(AGENDA_TECH_UNLOCK)
	# Apply any standing modifier this unlock grants NOW, not only via the signal
	# below: unlocks fired during game setup (e.g. a start's buildings hitting
	# "Operational Team Managers" at 3 buildings) can emit before ModifierState's
	# unlock_granted listener is connected, and grant_unlock is one-shot — so the
	# signal alone would drop the bonus. Idempotent (add() keys by id).
	Modifiers.apply_unlock_modifier(title)
	var desc := ""
	for d in _unlock_defs:
		if str(d.title) == title:
			desc = str(d.description)
			break
	unlock_granted.emit(title, desc, via_condition)

## The loaded unlock definition for a research title (empty if unknown).
func get_unlock_def(title: String) -> Dictionary:
	for d in _unlock_defs:
		if str(d.get("title", "")) == title:
			return d
	return {}

# ── Research tier gating (per category) ──────────────────────────────────────
## Nodes of the prior tier needed to open the next one. Two, not three (owner 2026-08-23):
## Petrochemistry had exactly three Tier I nodes, so "three of the prior tier" meant ALL of
## them, and Tier II was gated behind clearing a whole tier rather than committing to it.
const TIER_UNLOCK_THRESHOLD := 1
const _TIER_ORDER := ["I", "II", "III"]

## True when `category`'s roman `tier` is open. Tier I is always open; a higher
## tier opens once >= min(TIER_UNLOCK_THRESHOLD, nodes-in-prior-tier) of the
## immediately lower tier in the same category are unlocked. The clamp lets thin
## categories (fewer than 3 nodes in a tier) advance by unlocking ALL of them, so
## they can never permanently softlock.
func is_tier_available(category: String, tier: String) -> bool:
	var t := tier.strip_edges().to_upper()
	var i := _TIER_ORDER.find(t)
	if i <= 0:
		return true
	var prev: String = _TIER_ORDER[i - 1]
	var total := _tier_node_count(category, prev)
	if total <= 0:
		return true
	return _tier_unlocked_count(category, prev) >= mini(TIER_UNLOCK_THRESHOLD, total)

func _tier_node_count(category: String, tier: String) -> int:
	var n := 0
	for d in _unlock_defs:
		if is_research_visible(d) and str(d.get("category", "")) == category and str(d.get("rank", "I")) == tier:
			n += 1
	return n

func _tier_unlocked_count(category: String, tier: String) -> int:
	var n := 0
	for d in _unlock_defs:
		if is_research_visible(d) and str(d.get("category", "")) == category and str(d.get("rank", "I")) == tier \
				and unlocked_titles.has(str(d.get("title", ""))):
			n += 1
	return n

## A research node is currently available (workable toward / grantable / free-pickable)
## when its category tier is open AND every listed prereq is already unlocked.
func is_node_available(title: String) -> bool:
	var d := get_unlock_def(title)
	if d.is_empty() or not is_research_visible(d):
		return false
	if not is_tier_available(str(d.get("category", "")), str(d.get("rank", "I"))):
		return false
	for p in d.get("prereqs", []):
		# prereqs are research_node_ids; is_unlocked resolves them against the
		# title-keyed unlocked set.
		if not is_unlocked(str(p)):
			return false
	return true

## Human-readable "unlock-by-doing" condition for a research title — the same
## wording the research panel shows on a node card. Empty when the node carries
## no real condition (Placeholder / missing fields).
func unlock_condition_text(title: String) -> String:
	var d := get_unlock_def(title)
	if d.is_empty():
		return ""
	var action := str(d.get("action", "")).strip_edges()
	if action == "Placeholder":
		return ""
	var object_name := str(d.get("object", "")).strip_edges()
	var qty := int(d.get("qty", 0))
	var unit := str(d.get("unit", "")).strip_edges()
	if action.is_empty() or object_name.is_empty() or qty <= 0 or unit.is_empty():
		return ""
	if action == "Produce All":
		var goods := object_name.split("|", false)
		var quantities := str(d.get("quantity_raw", "")).split("|", false)
		if goods.size() == quantities.size() and not goods.is_empty():
			var parts: Array = []
			for index in goods.size():
				parts.append("%s %s" % [str(quantities[index]), _condition_good_label(str(goods[index]))])
			return "Produce %s" % _join_and(parts)
	if action == "Produce Any":
		# OR across goods: 500 of EITHER good unlocks it. A single Quantity applies to
		# every good; a "a|b" Quantity gives per-good thresholds like Produce All.
		var any_goods := object_name.split("|", false)
		var any_qtys := str(d.get("quantity_raw", "")).split("|", false)
		if not any_goods.is_empty():
			var parts: Array = []
			for index in any_goods.size():
				var want := qty
				if any_qtys.size() == any_goods.size() and str(any_qtys[index]).is_valid_int():
					want = int(str(any_qtys[index]))
				parts.append("%d %s" % [want, _condition_good_label(str(any_goods[index]))])
			return "Produce %s" % _join_or(parts)
	match action:
		"Produce": return "Produce %d %s" % [qty, _condition_good_label(object_name)]
		"Sell": return "Sell %d units through the market" % qty if _research_key(object_name) == "freight" else "Sell %d %s through the market" % [qty, _condition_good_label(object_name)]
		"Sell Through Ports": return "Sell %d units through ports" % qty
		"Sell Through Every Port": return "Export %d units through EVERY port" % qty
		"Own Port At Level": return "Own a port upgraded to level %d" % qty
		"Sell Through Ports Classes": return "Sell at least %d units of each weight class through ports" % qty
		"Purchase Ports": return "Purchase all %d ports" % qty
		"Build": return "Build %d %s" % [qty, _condition_building_label(object_name, qty)]
		"Own": return "Own %d land plots" % qty if _research_key(object_name) == "land" else "Own %d %s" % [qty, _condition_good_label(object_name)]
		"Run":
			var run_turns := _leading_int(unit, 0)
			return "Operate at least %d %s at full capacity for %d consecutive turns" % [qty, _condition_building_label(object_name, qty), run_turns] if run_turns > 0 else "Operate 1 %s at full capacity for %d consecutive turns" % [_condition_building_label(object_name, 1), qty]
		"Run L1": return "Operate %d Level 1 %s at full capacity for %s" % [qty, _condition_building_label(object_name, qty), unit]
		"Run Profitable":
			var profitable_turns := _leading_int(unit, 0)
			return "Operate at least %d %s profitably for %d consecutive turns" % [qty, _condition_building_label(object_name, qty), profitable_turns] if profitable_turns > 0 else "Operate %d %s profitably" % [qty, _condition_building_label(object_name, qty)]
		"Run Profitable L2": return "Operate %d Level 2 %s profitably" % [qty, _condition_building_label(object_name, qty)]
		"Run Same Tile":
			var same_turns := _leading_int(unit, 0)
			return "Operate %d %s on the same tile at full capacity for %d consecutive turns" % [qty, _condition_building_label(object_name, qty), same_turns] if same_turns > 0 else "Operate %d %s on the same tile" % [qty, _condition_building_label(object_name, qty)]
		"Own On Tiles": return "Own %s on at least %d different tiles" % [_condition_building_label(object_name, 2), qty]
		"Run Distinct Recipes": return "Operate %d %s, each on a different recipe" % [qty, _condition_building_label(object_name, qty)]
		"Own All":
			var own_parts: Array = []
			var own_names := object_name.split("|", false)
			var own_qtys := str(d.get("quantity_raw", "")).split("|", false)
			for index in own_names.size():
				var own_n := qty
				if own_qtys.size() == own_names.size() and str(own_qtys[index]).is_valid_int():
					own_n = int(str(own_qtys[index]))
				own_parts.append("%d %s" % [own_n, _condition_building_label(str(own_names[index]), own_n)])
			return "Own %s" % _join_and(own_parts)
		"Run Producing":
			var prod_turns := _leading_int(unit, 0)
			var prod_who := "a building" if qty <= 1 else "%d buildings" % qty
			return "Operate %s making %s at full capacity for %d consecutive turns" % [prod_who, _condition_good_label(object_name), prod_turns] if prod_turns > 0 else "Operate %s making %s at full capacity" % [prod_who, _condition_good_label(object_name)]
		"Run Profitable L1": return "Operate %d Level 1 %s profitably for %s" % [qty, _condition_building_label(object_name, qty), unit]
		"All Of":
			var all_parts: Array = []
			for spec in object_name.split(";", false):
				var sub := _parse_sub_condition(str(spec))
				if not sub.is_empty():
					all_parts.append(_sub_condition_text(sub))
			return _join_and(all_parts).capitalize() if all_parts.is_empty() else (_join_and(all_parts)[0].to_upper() + _join_and(all_parts).substr(1))
		"Ship Multimodal": return "Move at least %d freight in a single turn using more than one mode of transport" % qty
		"Produce Per Turn": return "Produce at least %d %s in a single turn" % [qty, _condition_good_label(object_name)]
		"Produce Per Turn Any":
			var rate_parts: Array = []
			var rate_names := object_name.split("|", false)
			var rate_raw := str(d.get("quantity_raw", "")).split("|", false)
			for index in rate_names.size():
				var rate_n := qty
				if rate_raw.size() == rate_names.size() and str(rate_raw[index]).is_valid_int():
					rate_n = int(str(rate_raw[index]))
				rate_parts.append("%d %s" % [rate_n, _condition_good_label(str(rate_names[index]))])
			return "Produce at least %s in a single turn" % _join_or(rate_parts)
		"Run Multiple": return _run_multiple_condition_text(d)
		"Fulfil Special Orders": return "Fulfil at least %d special orders" % qty
		"Run Recipe Profitable": return "Run %d buildings with %s recipes profitably" % [qty, "steelmaking" if _research_key(object_name) == "steel_production" else object_name.to_lower()]
		"Run Recipe": return "Operate %d building%s using a %s recipe" % [qty, "" if qty == 1 else "s", object_name]
		"Survey": return "Survey %d %s" % [qty, object_name]
		"Stockpile filled": return "Supply one stockpile from %s for %d consecutive turns" % [object_name, qty]
		"Sustain": return "Maintain %s for %d consecutive turns" % [object_name, qty]
		"Use Infrastructure":
			var use_turns := _leading_int(unit.get_slice("for", 1), 5) if "for" in unit else 0
			if "of l1" in unit.to_lower():
				# Absolute bar against Level-1 capacity (see _infrastructure_usage_met).
				var use_pct := _leading_int(unit, 80)
				return "Carry %d%% of Level-1 capacity on %d %s for %d consecutive turns" % [use_pct, qty, object_name.capitalize(), use_turns] if use_turns > 0 else "Carry %d%% of Level-1 capacity on %d %s" % [use_pct, qty, object_name.capitalize()]
			return "Use at least %d %s at 80%% throughput or higher" % [qty, _condition_good_label(object_name)] if use_turns <= 0 else "Use %d %s at 80%% capacity for %d consecutive turns" % [qty, object_name.capitalize(), use_turns]
		"Firm Intermittency": return "Firm at least %d power of intermittent generation" % qty
	return "%s %s %d" % [action, object_name, qty]

## Record progress toward action+object conditions (e.g. record("Survey","tiles")).
## Advance/reset the per-tile "stockpile fed by 7+ buildings" streaks from this
## turn's flush: {tile_id -> distinct producing buildings}. Tiles at the bar
## extend their streak; every other tile (including ones absent this turn) resets.
const STOCKPILE_FEED_STREAK_BUILDINGS := 7  # owner raised from 3 (2026-07-09)

func update_stockpile_feed_streaks(fed_counts: Dictionary) -> void:
	var next: Dictionary = {}
	for t in fed_counts:
		if int(fed_counts[t]) >= STOCKPILE_FEED_STREAK_BUILDINGS:
			next[t] = int(stockpile_feed_streaks.get(t, 0)) + 1
	stockpile_feed_streaks = next

func max_stockpile_feed_streak() -> int:
	var best := 0
	for t in stockpile_feed_streaks:
		best = maxi(best, int(stockpile_feed_streaks[t]))
	return best

func record_unlock_progress(action: String, object: String, amount: int = 1) -> void:
	if amount <= 0:
		return
	var key := (action + "|" + object).to_lower()
	_unlock_progress[key] = int(_unlock_progress.get(key, 0)) + amount
	_mark_research_progress_dirty()


## Mark the central research snapshot stale.  The next NARRATIVE phase performs
## exactly one complete evaluation after every upstream metric is final.
func _mark_research_progress_dirty() -> void:
	_research_progress_dirty = true


## One authoritative research-progress refresh per resolved turn.  Keeping this
## separate from `_check_unlock_conditions()` preserves the latter as a useful
## immediate diagnostic/test API while removing it from high-frequency game paths.
func _refresh_research_progress() -> void:
	var turn := int(TurnManager.current_turn)
	if _research_progress_last_turn == turn and not _research_progress_dirty:
		return
	_research_progress_last_turn = turn
	_research_progress_dirty = false
	_check_unlock_conditions()

func _check_unlock_conditions() -> void:
	for d in _unlock_defs:
		var title := str(d.title)
		if title == "" or unlocked_titles.has(title) or int(d.qty) <= 0 or not is_research_visible(d):
			continue
		var action := str(d.action)
		if action == "" or str(d.object) == "":
			continue
		# Per-category tier-lock: a higher tier's conditions can't be met until enough
		# of the prior tier is unlocked (see is_tier_available). Reuses `d` so this
		# stays a single pass over _unlock_defs.
		if not is_tier_available(str(d.get("category", "")), str(d.get("rank", "I"))):
			continue
		var prereqs_met := true
		for p in d.prereqs:
			if not is_unlocked(str(p)):   # prereqs are research_node_ids
				prereqs_met = false
				break
		if not prereqs_met:
			continue
		# Live conditions evaluated against current state (production/sales totals,
		# owned land/buildings, profitability and run-streaks). Legacy CSV Objects
		# may be IDs, internal names, display names or explicit concept aliases.
		# Level-filtered verbs ("Run L1", "Run Profitable L2") are forward-compatible:
		# every building is Level 1 until the leveling mechanic ships, so L1 gates can
		# already fire and L2 gates wait for it.
		if _live_condition_met(d):
			grant_unlock(title, true)
			continue
		# Legacy flat action|object accumulator (Survey progress, etc.).
		var key := (action + "|" + str(d.object)).to_lower()
		if int(_unlock_progress.get(key, 0)) >= int(d.qty):
			grant_unlock(title, true)

# True when a research def's live condition is satisfied right now. Survey also
# retains the legacy accumulator below, while all other shipped verbs resolve here.
func _live_condition_met(d: Dictionary) -> bool:
	var action := str(d.action)
	var obj := str(d.object)
	var need := int(d.qty)
	match action:
		"Produce":
			var produce_good := _research_good_id(obj)
			return produce_good != "" and Production.lifetime_total(produce_good) >= need
		"Produce All":
			var goods := obj.split("|", false)
			var quantities := str(d.get("quantity_raw", need)).split("|", false)
			if goods.is_empty() or goods.size() != quantities.size():
				return false
			for index in goods.size():
				var good_id := _research_good_id(str(goods[index]))
				var quantity_text := str(quantities[index])
				if good_id == "" or not quantity_text.is_valid_int() or Production.lifetime_total(good_id) < int(quantity_text):
					return false
			return true
		"Produce Any":
			# OR: producing `need` of ANY listed good satisfies it. A "a|b" Quantity
			# gives per-good thresholds; a single Quantity applies to every good.
			var any_goods := obj.split("|", false)
			var any_qtys := str(d.get("quantity_raw", need)).split("|", false)
			for index in any_goods.size():
				var gid := _research_good_id(str(any_goods[index]))
				if gid == "":
					continue
				var want := need
				if any_qtys.size() == any_goods.size() and str(any_qtys[index]).is_valid_int():
					want = int(str(any_qtys[index]))
				if Production.lifetime_total(gid) >= want:
					return true
			return false
		"Sell":
			if _research_key(obj) == "freight":
				return MarketState.lifetime_sold_total() >= need
			var sell_good := _research_good_id(obj)
			return sell_good != "" and MarketState.lifetime_sold(sell_good) >= need
		"Sell Through Ports":
			return _port_sale_total >= need
		"Sell Through Every Port":
			# Every port on the map must have carried `need` units of the player's exports.
			# Volume is the small part; the real ask is REACH.
			for port in Catalog.all_ports():
				var ptile := str(port.get("tile_id", ""))
				if ptile != "" and int(_port_sales_by_port.get(ptile, 0)) < need:
					return false
			return true
		"Own Port At Level":
			# A port building (b_004) the player owns, upgraded to at least `need`.
			for b in buildings.values():
				if not (b is Dictionary) or not is_player_owned(b):
					continue
				if str(b.get("building_id", "")) == "b_004" and int(b.get("level", 1)) >= need:
					return true
			return false
		"Sell Through Ports Classes":
			var classes := obj.split("|", false)
			if classes.is_empty():
				return false
			for transport_kind in classes:
				if int(_port_sales_by_class.get(str(transport_kind), 0)) < need:
					return false
			return true
		"Purchase Ports":
			return _owned_port_count() >= need
		"Build":
			# Own N player-built buildings of this type (any level/run state).
			return _count_buildings(obj, -1, false, 0) >= need
		"Own":
			if _research_key(obj) == "land":
				return _research_owned_land_units() >= need
			if _research_key(obj) == "offshore_oil_land":
				return _owned_offshore_oil_land() >= need
			return _count_buildings(obj, -1, false, 0) >= need
		"Run":
			# Plain Run conditions mean one matching building sustaining full output
			# for Quantity turns ("Run Mine for 15 turns"). Rows with a turn count
			# in Unit instead mean N matching buildings for that many turns.
			var run_turns := _leading_int(str(d.get("unit", "")), 0)
			return _count_buildings(obj, -1, false, run_turns) >= need if run_turns > 0 else _count_buildings(obj, -1, false, need) >= 1
		"Run Profitable":
			return _count_buildings(obj, -1, true, _leading_int(str(d.get("unit", "")), 0)) >= need
		"Run L1":
			# "Run N Level-1 buildings of this type for <Unit> turns."
			var turns := _leading_int(str(d.get("unit", "")), 20)
			return _count_buildings(obj, 1, false, turns) >= need
		"Run Profitable L2":
			return _count_buildings(obj, 2, true, 0) >= need
		"Run Same Tile":
			# N running buildings of this type on ONE tile; a leading int in Unit adds a
			# full-output streak ("4 mines on the same tile for 15 turns").
			return _max_same_tile_count(obj, _leading_int(str(d.get("unit", "")), 0)) >= need
		"Own On Tiles":
			# This building type present on at least N distinct tiles (reach, not volume).
			return _tiles_with_building(obj) >= need
		"Run Distinct Recipes":
			# N running buildings of this type each on a DIFFERENT recipe ("3 chem plants
			# with different recipes") — breadth of process, not fleet size.
			return _distinct_recipes_running(obj) >= need
		"Own All":
			# "a|b" building types with "x|y" counts: own at least each ("a chem plant AND
			# a power plant"). Mirrors Produce All.
			var own_targets := obj.split("|", false)
			var own_counts := str(d.get("quantity_raw", need)).split("|", false)
			if own_targets.is_empty():
				return false
			for index in own_targets.size():
				var want_n := need
				if own_counts.size() == own_targets.size() and str(own_counts[index]).is_valid_int():
					want_n = int(str(own_counts[index]))
				if _count_buildings(str(own_targets[index]), -1, false, 0) < want_n:
					return false
			return true
		"Run Producing":
			# N buildings whose CURRENT recipe outputs this good, at full output for the
			# streak in Unit ("run a recipe producing chlorine for 15 turns") — by output,
			# so it spans recipes in different categories.
			return _count_running_producing(_research_good_id(obj), _leading_int(str(d.get("unit", "")), 0)) >= need
		"Run Profitable L1":
			# N Level-1 buildings profitable for the streak in Unit.
			return _count_buildings(obj, 1, true, _leading_int(str(d.get("unit", "")), 0)) >= need
		"All Of":
			# Compound AND: Object is ";"-separated clauses, each "Action|Object|Qty|Unit"
			# ("operate 5 refineries AND produce alloy metals"). Every clause must hold.
			var clauses := obj.split(";", false)
			if clauses.is_empty():
				return false
			for spec in clauses:
				var sub := _parse_sub_condition(str(spec))
				if sub.is_empty() or not _live_condition_met(sub):
					return false
			return true
		"Produce Per Turn":
			# A RATE: the last resolved turn's output of this good, not lifetime volume
			# ("produce at least 300 steel per turn").
			var rate_good := _research_good_id(obj)
			return rate_good != "" and int((Production.last_turn_summary.get("produced", {}) as Dictionary).get(rate_good, 0)) >= need
		"Ship Multimodal":
			# Last turn's freight reached `need` units AND travelled by more than one transport
			# mode ("100 freight per turn using more than 1 mode").
			var mm := _multimodal_freight_last_turn()
			return int(mm.get("total", 0)) >= need and (mm.get("modes", {}) as Dictionary).size() >= 2
		"Produce Per Turn Any":
			# A rate on ANY of an "a|b" list: last turn's output of any listed good reached its
			# threshold ("30 pet coke per turn OR 30 biomass per turn"). Shared qty, or per-good "x|y".
			var rate_goods := obj.split("|", false)
			var rate_qtys := str(d.get("quantity_raw", need)).split("|", false)
			var produced_last: Dictionary = Production.last_turn_summary.get("produced", {})
			for index in rate_goods.size():
				var rg := _research_good_id(str(rate_goods[index]))
				if rg == "":
					continue
				var want_rate := need
				if rate_qtys.size() == rate_goods.size() and str(rate_qtys[index]).is_valid_int():
					want_rate = int(str(rate_qtys[index]))
				if int(produced_last.get(rg, 0)) >= want_rate:
					return true
			return false
		"Run Recipe Profitable":
			return _count_buildings_running_recipe_type(obj, 1, true) >= need
		"Run Recipe":
			# "Run N player buildings currently set to a recipe of this category"
			# (e.g. furnaces on a Glassmaking recipe). A leading int in Unit optionally
			# requires a minimum full-output run-streak.
			var recipe_streak := _leading_int(str(d.get("unit", "")), 0)
			return _count_buildings_running_recipe_type(obj, recipe_streak) >= need
		"Stockpile filled":
			# Just-in-Time Logistics: some tile's stockpile received goods from 3+
			# buildings for <qty> consecutive turns (streaks kept at output flush).
			return max_stockpile_feed_streak() >= need
		"Sustain":
			var threshold := _leading_int(obj, 0)
			return threshold == int(ADVISOR_SLOT_PROFIT_5) \
				and _advisor_profit_streak >= need
		"Use Infrastructure":
			return _infrastructure_usage_met(d)
		"Firm Intermittency":
			return Production.firmed_intermittent_power() >= need
		"Run Multiple":
			return _run_multiple_buildings_met(d)
		"Fulfil Special Orders":
			return SpecialOrderState.fulfilled_count >= need
	return false


func _run_multiple_buildings_met(d: Dictionary) -> bool:
	var targets := str(d.get("object", "")).split("|", false)
	var quantities := str(d.get("quantity_raw", "")).split("|", false)
	var turns := _leading_int(str(d.get("unit", "")), 0)
	if targets.is_empty() or targets.size() != quantities.size() or turns <= 0:
		return false
	for index in targets.size():
		var count_text := str(quantities[index])
		if not count_text.is_valid_int() or _count_buildings(str(targets[index]), -1, false, turns) < int(count_text):
			return false
	return true


func _run_multiple_condition_text(d: Dictionary) -> String:
	var targets := str(d.get("object", "")).split("|", false)
	var quantities := str(d.get("quantity_raw", "")).split("|", false)
	var turns := _leading_int(str(d.get("unit", "")), 0)
	if targets.is_empty() or targets.size() != quantities.size() or turns <= 0:
		return ""
	var parts: Array[String] = []
	for index in targets.size():
		parts.append("%s %s" % [str(quantities[index]), _condition_building_label(str(targets[index]), int(quantities[index]))])
	return "Operate at least %s at full capacity for %d consecutive turns" % [_join_and(parts), turns]


func _condition_good_label(raw: String) -> String:
	var good: Dictionary = Catalog.get_good(_research_good_id(raw))
	return str(good.get("display_name", raw.capitalize()))

func _condition_building_label(raw: String, quantity: int = 1) -> String:
	var key := _research_key(raw)
	if key == "high_tech_manufactory|assembly_plant":
		return "High Tech Manufactories and/or Assembly Plants"
	if key == "any":
		return "buildings"
	var label: String = str({
		"high_tech_manufactory": "High Tech Manufactory",
		"assembly_plant": "Assembly Plant",
		"solar_farm": "Solar Farm",
		"farm": "Farm",
		"chem_plant": "Chemical Plant",
		"petro_refinery": "Petrochemical Refinery",
		"poly_plant": "Polymerisation Refinery",
		"desal": "Desalination Plant",
		"eaf": "Electric Arc Furnace",
	}.get(key, raw.capitalize()))
	if quantity != 1:
		if label.ends_with("y"):
			return "%sies" % label.left(label.length() - 1)
		return "%ss" % label
	return label


## Count player-owned infrastructure segments carrying at least 80% of their
## current capacity. Transport flow is the same per-tile metric surfaced by the
## infrastructure overlay; cables use actual draw/generation against their power cap.
## A segment set must sustain the target utilisation for the number of turns encoded
## after "for" in the Unit cell (normally "80% for 5 turns").
func _infrastructure_usage_met(d: Dictionary) -> bool:
	var title := str(d.get("title", ""))
	var need_segments := int(d.get("qty", 0))
	if title == "" or need_segments <= 0:
		return false
	var unit := str(d.get("unit", ""))
	var duration := 1
	if "for" in unit:
		duration = _leading_int(unit.get_slice("for", 1), 5)
	# "N% of L1 for T turns": an ABSOLUTE bar — N% of the LEVEL-1 capacity — so upgrading a
	# link never makes the gate harder, and 120%+ is reachable through congestion (owner
	# 2026-09-06). Plain "80% for T turns" keeps the legacy meaning: 80% of CURRENT capacity.
	var of_l1 := "of l1" in unit.to_lower()
	var bar_fraction := float(_leading_int(unit, 80)) / 100.0
	var turn := int(TurnManager.current_turn)
	# Conditions are evaluated from several hooks. Only advance/reset the streak
	# once per resolved turn, after the actual transport and power use has settled.
	if TurnManager.current_phase == TurnManager.Phase.NARRATIVE \
			and int(_infrastructure_usage_last_turn.get(title, -1)) != turn:
		_infrastructure_usage_last_turn[title] = turn
		var active_segments := 0
		var targets := _research_building_targets(str(d.get("object", "")))
		for inst in buildings.values():
			if not is_player_owned(inst) or not targets.has(_building_internal(inst)):
				continue
			var internal := _building_internal(inst)
			var tile_id := str(inst.get("tile_id", ""))
			var capacity := 0.0
			var usage := 0.0
			if internal == "cables":
				# L1 yardstick is the RAW table cap: throughput research must not move the bar.
				capacity = float(EconomyConfig.CABLE_POWER_CAP.get(1, 0)) if of_l1 else float(Power.tile_power_cap(tile_id))
				usage = float(maxi(int(Power.tile_drawn.get(tile_id, 0)), int(Power.tile_produced.get(tile_id, 0))))
			else:
				var mode := "rail" if internal == "rails" else internal
				capacity = float(TransportService.link_capacity(mode, 1)) if of_l1 else tile_mode_capacity(mode, _tile_infra_level(tile_id, mode))
				usage = float(tile_mode_flow(tile_id, mode))
			var bar := capacity * (bar_fraction if of_l1 else 0.80)
			if capacity > 0.0 and usage >= bar:
				active_segments += 1
		if active_segments >= need_segments:
			_infrastructure_usage_streaks[title] = int(_infrastructure_usage_streaks.get(title, 0)) + 1
		else:
			_infrastructure_usage_streaks[title] = 0
	return int(_infrastructure_usage_streaks.get(title, 0)) >= duration


func _research_key(value: String) -> String:
	var key := value.strip_edges().to_lower()
	for token in [" ", "-", "/", "."]:
		key = key.replace(token, "_")
	while "__" in key:
		key = key.replace("__", "_")
	return key.trim_prefix("_").trim_suffix("_")


func _research_building_targets(raw: String) -> Array:
	if "|" in raw:
		var combined: Array = []
		for part in raw.split("|", false):
			for target in _research_building_targets(str(part)):
				if not combined.has(target):
					combined.append(target)
		return combined
	var key := _research_key(raw)
	if key == "" or key == "any":
		return []
	var targets: Array = []
	if RESEARCH_BUILDING_ALIASES.has(key):
		for internal in RESEARCH_BUILDING_ALIASES[key]:
			if not targets.has(str(internal)):
				targets.append(str(internal))
	for building in Catalog.all_buildings():
		var internal := str(building.get("internal_name", ""))
		if key in [
			_research_key(str(building.get("id", ""))),
			_research_key(internal),
			_research_key(str(building.get("display_name", ""))),
		] and not targets.has(internal):
			targets.append(internal)
	return targets


func _research_good_id(raw: String) -> String:
	var key := _research_key(raw)
	var internal_alias := str(RESEARCH_GOOD_ALIASES.get(key, key))
	for good in Catalog.all_goods():
		if internal_alias in [
			_research_key(str(good.get("id", ""))),
			_research_key(str(good.get("internal_name", ""))),
			_research_key(str(good.get("display_name", ""))),
		]:
			return str(good.get("id", ""))
	return ""


## Land the player owns on SEA tiles that carry an oil deposit — the offshore drilling gate.
##
## Deliberately land UNITS on qualifying tiles, not a tile count: the point of the condition
## is that the player has committed real money to a specific offshore field, which is the
## thing offshore drilling is actually about. Seven tiles on the shipped map qualify, each
## with 200 capacity, so the 50 units the CSV asks for fit on any one of them.
func _owned_offshore_oil_land() -> int:
	var total := 0
	for tile_id in tile_land_owned:
		var tid := str(tile_id)
		var owned := int(tile_land_owned[tile_id])
		if owned <= 0 or not tid.begins_with("tile_"):
			continue
		if not Catalog.tile_type(tid) in ["sea", "deep_sea"]:
			continue
		if not "oil" in Catalog.tile_deposits_raw(tid).to_lower():
			continue
		total += owned
	return total

func _research_owned_land_units() -> int:
	var total := 0
	for tile_id in tile_land_owned:
		if str(tile_id).begins_with("tile_") and int(tile_land_owned[tile_id]) > 0:
			total += 1
	return total


## Dataset audit used by tests and diagnostics. Placeholder nodes deliberately
## carry no live condition; every other row should resolve to a live metric.
func research_condition_issues() -> Array:
	var issues: Array = []
	for d in _unlock_defs:
		var reason := _research_condition_issue(d)
		if reason != "":
			issues.append({
				"title": str(d.get("title", "")),
				"action": str(d.get("action", "")),
				"object": str(d.get("object", "")),
				"reason": reason,
			})
	return issues


func _research_condition_issue(d: Dictionary) -> String:
	var action := str(d.get("action", ""))
	var obj := str(d.get("object", ""))
	if action == "Placeholder":
		return ""
	if action == "All Of":
		# Every ";"-separated clause must itself pass the audit.
		var all_clauses := obj.split(";", false)
		if all_clauses.is_empty():
			return "empty All Of condition"
		for spec in all_clauses:
			var sub := _parse_sub_condition(str(spec))
			if sub.is_empty():
				return "malformed All Of clause"
			var sub_issue := _research_condition_issue(sub)
			if sub_issue != "":
				return sub_issue
		return ""
	if action == "Ship Multimodal":
		return "" if _research_key(obj) == "freight" else "unsupported multimodal target"
	if action == "Produce Per Turn":
		return "" if _research_good_id(obj) != "" else "unknown good target"
	if action == "Produce Per Turn Any":
		var rate_goods := obj.split("|", false)
		if rate_goods.is_empty():
			return "invalid multi-good production condition"
		for g in rate_goods:
			if _research_good_id(str(g)) == "":
				return "unknown good target"
		return ""
	if action == "Own All":
		# "a|b" building types — every one must resolve.
		var own_all_targets := obj.split("|", false)
		if own_all_targets.is_empty():
			return "invalid multi-building ownership condition"
		for t in own_all_targets:
			if _research_building_targets(str(t)).is_empty():
				return "unknown ownership target"
		return ""
	if action == "Run Producing":
		return "" if _research_good_id(obj) != "" else "unknown good target"
	if action in ["Build", "Run", "Run Profitable", "Run L1", "Run Profitable L2", "Run Multiple", "Use Infrastructure", "Run Same Tile", "Own On Tiles", "Run Distinct Recipes", "Run Profitable L1"]:
		if _research_key(obj) != "any" and _research_building_targets(obj).is_empty():
			return "unknown building target"
		return ""
	if action == "Fulfil Special Orders":
		return "" if _research_key(obj) == "special_order" else "unsupported special-order target"
	if action == "Own":
		if _research_key(obj) == "offshore_oil_land":
			return ""
		if _research_key(obj) != "land" and _research_building_targets(obj).is_empty():
			return "unknown ownership target"
		return ""
	if action == "Purchase Ports":
		return "" if _research_key(obj) == "ports" else "unsupported port ownership target"
	if action == "Sell Through Ports":
		return "" if _research_key(obj) == "ports" else "unsupported port-sale target"
	if action == "Sell Through Every Port" or action == "Own Port At Level":
		return "" if _research_key(obj) == "ports" else "unsupported port target"
	if action == "Sell Through Ports Classes":
		var classes := obj.split("|", false)
		if classes.is_empty():
			return "missing port transport classes"
		for transport_kind in classes:
			if not ["solid_light", "solid_heavy", "ultra_heavy", "safe_liquid", "hazard_liquid", "gas"].has(str(transport_kind)):
				return "unsupported port transport class"
		return ""
	if action == "Produce All":
		var goods := obj.split("|", false)
		var quantities := str(d.get("quantity_raw", "")).split("|", false)
		if goods.is_empty() or goods.size() != quantities.size():
			return "invalid multi-good production condition"
		for index in goods.size():
			if _research_good_id(str(goods[index])) == "" or not str(quantities[index]).is_valid_int():
				return "unknown good target"
		return ""
	if action == "Produce Any":
		# OR list "a|b": every listed good must resolve. A single Quantity applies to all;
		# a per-good "a|b" Quantity must be all-integer.
		var any_goods := obj.split("|", false)
		if any_goods.is_empty():
			return "invalid multi-good production condition"
		var any_qtys := str(d.get("quantity_raw", "")).split("|", false)
		var per_good := any_qtys.size() == any_goods.size()
		for index in any_goods.size():
			if _research_good_id(str(any_goods[index])) == "":
				return "unknown good target"
			if per_good and not str(any_qtys[index]).is_valid_int():
				return "unknown good target"
		return ""
	if action in ["Produce", "Sell"]:
		if action == "Sell" and _research_key(obj) == "freight":
			return ""
		if _research_good_id(obj) == "":
			return "unknown good target"
		return ""
	if action in ["Run Recipe", "Run Recipe Profitable"]:
		var wanted := _research_key(obj)
		for recipe in Catalog.all_recipes():
			if _research_key(str(recipe.get("recipe_type", ""))) == wanted:
				return ""
		return "unknown recipe type"
	if action == "Survey":
		return "" if _research_key(obj) in ["tiles", "deposits"] else "unknown survey target"
	if action == "Stockpile filled":
		return ""
	if action == "Firm Intermittency":
		return "" if _research_key(obj) == "power" else "unsupported intermittency target"
	if action == "Sustain":
		return "" if _leading_int(obj, 0) == int(ADVISOR_SLOT_PROFIT_5) \
			else "unsupported sustain threshold"
	return "unsupported action"

# Count player-owned buildings resolved from an ID/internal/display/concept name,
# optionally filtered by level (-1 = any), profitability, and a minimum consecutive
# run-streak. `internal` == "any" (or "") matches every non-infrastructure building.
## Largest number of player buildings of `internal` sharing ONE tile, counting only those
## that (when `min_streak` > 0) have sustained full output for that many consecutive turns.
## Backs the "Run Same Tile" verb — co-location is the ask, not fleet size.
func _max_same_tile_count(internal: String, min_streak: int) -> int:
	var any_type: bool = _research_key(internal) == "any" or internal == ""
	var targets := _research_building_targets(internal)
	var per_tile: Dictionary = {}
	for inst in buildings.values():
		if not is_player_owned(inst):
			continue
		if any_type:
			if str(Catalog.get_building(str(inst.get("building_id", ""))).get("category", "")) == "infrastructure":
				continue   # "any" means production buildings, as in _count_buildings
		elif not targets.has(_building_internal(inst)):
			continue
		if min_streak > 0 and int(Production.full_output_streak_by_building.get(str(inst.get("instance_id", "")), 0)) < min_streak:
			continue
		var t := str(inst.get("tile_id", ""))
		per_tile[t] = int(per_tile.get(t, 0)) + 1
	var best := 0
	for t in per_tile:
		best = maxi(best, int(per_tile[t]))
	return best

## Last resolved turn's freight, by transport mode, from the same shipment snapshot the
## congestion model uses (_last_transit_shipments). Each shipment's units count once per
## mode it travels by — no inflation by route length. Leg-less overland moves count as
## "overland". Backs "Ship Multimodal": {"total": units, "modes": {mode: units}}.
func _multimodal_freight_last_turn() -> Dictionary:
	var by_mode: Dictionary = {}
	var total := 0
	for s in _last_transit_shipments:
		var units := _shipment_total_units(s as Dictionary)
		if units <= 0:
			continue
		var modes: Dictionary = {}
		for leg in (s as Dictionary).get("legs", []):
			var mode := str((leg as Dictionary).get("mode", ""))
			if mode != "":
				modes[mode] = true
		if modes.is_empty():
			modes["overland"] = true
		for mode in modes:
			by_mode[mode] = int(by_mode.get(mode, 0)) + units
		total += units
	return {"total": total, "modes": by_mode}

## One "Action|Object|Qty|Unit" clause of an "All Of" condition, as the condition dict the
## live check, the audit and the card text consume. Empty when malformed. (Clauses whose own
## Object needs "|" — Produce All, Own All — can't nest here; none do.)
func _parse_sub_condition(spec: String) -> Dictionary:
	# Action | Object… | Qty | Unit — the LAST two fields are qty and unit, so an Object that
	# itself carries "|" (an a|b good list for the *Any / *All verbs) survives inside a clause.
	var parts := spec.split("|", false)
	if parts.size() < 4:
		return {}
	var q := str(parts[parts.size() - 2]).strip_edges()
	var object_parts: Array = []
	for i in range(1, parts.size() - 2):
		object_parts.append(str(parts[i]).strip_edges())
	return {
		"action": str(parts[0]).strip_edges(), "object": "|".join(PackedStringArray(object_parts)),
		"qty": int(q) if q.is_valid_int() else _leading_int(q, 0), "quantity_raw": q,
		"unit": str(parts[parts.size() - 1]).strip_edges(),
	}

## Card text for one All Of clause — the verbs that actually appear in compound gates.
func _sub_condition_text(sub: Dictionary) -> String:
	var a := str(sub.get("action", "")); var o := str(sub.get("object", "")); var n := int(sub.get("qty", 0)); var u := str(sub.get("unit", ""))
	var turns := _leading_int(u, 0)
	match a:
		"Produce": return "produce %d %s" % [n, _condition_good_label(o)]
		"Produce Per Turn Any":
			var choices: Array = []
			for good in o.split("|", false):
				choices.append("%d %s" % [n, _condition_good_label(str(good))])
			return "produce %s in one turn" % _join_or(choices)
		"Own On Tiles": return "own %s on at least %d different tiles" % [_condition_building_label(o, 2), n]
		"Own": return "own %d %s" % [n, _condition_building_label(o, n)]
		"Run": return "operate %d %s at full capacity for %d turns" % [n, _condition_building_label(o, n), turns] if turns > 0 else "operate a %s at full capacity for %d turns" % [_condition_building_label(o, 1), n]
		"Run Profitable": return "operate %d %s profitably" % [n, _condition_building_label(o, n)]
		"Run Producing": return "operate %s making %s at full capacity for %d turns" % ["a building" if n <= 1 else "%d buildings" % n, _condition_good_label(o), turns]
	return "%s %s %d %s" % [a, o, n, u]

## Number of DIFFERENT recipes currently running (full-output streak >= 1) across the
## player's buildings of `internal`. Backs "Run Distinct Recipes" — breadth of process.
func _distinct_recipes_running(internal: String) -> int:
	var targets := _research_building_targets(internal)
	var recipes: Dictionary = {}
	for inst in buildings.values():
		if not is_player_owned(inst) or not targets.has(_building_internal(inst)):
			continue
		if int(Production.full_output_streak_by_building.get(str(inst.get("instance_id", "")), 0)) < 1:
			continue
		var rid := str(inst.get("recipe_id", ""))
		if rid != "":
			recipes[rid] = true
	return recipes.size()

## Player buildings whose CURRENT recipe outputs `good_id`, at full output for at least
## `min_streak` consecutive turns. Backs "Run Producing" — matched by output good, so a
## condition like "make chlorine" spans recipes that live in different categories.
func _count_running_producing(good_id: String, min_streak: int) -> int:
	if good_id == "":
		return 0
	var n := 0
	for inst in buildings.values():
		if not is_player_owned(inst):
			continue
		var recipe: Dictionary = Catalog.get_recipe(str(inst.get("recipe_id", "")))
		if recipe.is_empty() or not Catalog.recipe_produces(recipe, good_id):
			continue
		if int(Production.full_output_streak_by_building.get(str(inst.get("instance_id", "")), 0)) < maxi(min_streak, 1):
			continue
		n += 1
	return n

## Number of distinct tiles carrying at least one player building of `internal`.
## Backs the "Own On Tiles" verb — geographic reach, not building count.
func _tiles_with_building(internal: String) -> int:
	var any_type: bool = _research_key(internal) == "any" or internal == ""
	var targets := _research_building_targets(internal)
	var tiles: Dictionary = {}
	for inst in buildings.values():
		if not is_player_owned(inst):
			continue
		if any_type:
			if str(Catalog.get_building(str(inst.get("building_id", ""))).get("category", "")) == "infrastructure":
				continue   # "any" means production buildings, as in _count_buildings
		elif not targets.has(_building_internal(inst)):
			continue
		tiles[str(inst.get("tile_id", ""))] = true
	return tiles.size()

func _count_buildings(internal: String, level: int, require_profitable: bool, min_streak: int) -> int:
	var match_any: bool = _research_key(internal) == "any" or internal == ""
	var targets := _research_building_targets(internal)
	var n := 0
	for inst in buildings.values():
		if not is_player_owned(inst):
			continue
		if match_any and str(Catalog.get_building(str(inst.get("building_id", ""))).get("category", "")) == "infrastructure":
			continue   # "build N buildings" (any-type scale unlocks) ignores infrastructure
		if not match_any and not targets.has(_building_internal(inst)):
			continue
		if level >= 0 and _building_level(inst) != level:
			continue
		var streaks: Dictionary = _profitable_run_streaks if require_profitable else Production.full_output_streak_by_building
		if min_streak > 0 and int(streaks.get(str(inst.get("instance_id", "")), 0)) < min_streak:
			continue
		if require_profitable and not _is_building_profitable(inst):
			continue
		n += 1
	return n

# Count player-owned buildings whose CURRENTLY-ASSIGNED recipe has recipe_type ==
# `recipe_type` (case-insensitive), optionally requiring a minimum full-output
# run-streak. Powers recipe-specific research gates (e.g. "run furnaces on a
# Glassmaking recipe"). Because glassmaking recipes only exist in the furnace,
# matching recipe_type already means "a furnace running glassmaking".
func _count_buildings_running_recipe_type(recipe_type: String, min_streak: int, require_profitable: bool = false) -> int:
	var want := recipe_type.strip_edges().to_lower()
	if want == "":
		return 0
	var n := 0
	for inst in buildings.values():
		if not is_player_owned(inst):
			continue
		var recipe: Dictionary = Catalog.get_recipe(str(inst.get("recipe_id", "")))
		if recipe.is_empty():
			continue
		if str(recipe.get("recipe_type", "")).strip_edges().to_lower() != want:
			continue
		if min_streak > 0 and int(Production.full_output_streak_by_building.get(str(inst.get("instance_id", "")), 0)) < min_streak:
			continue
		if require_profitable and (is_building_paused(str(inst.get("instance_id", ""))) or not _is_building_profitable(inst)):
			continue
		n += 1
	return n

func _building_internal(inst: Dictionary) -> String:
	return str(Catalog.get_building(str(inst.get("building_id", ""))).get("internal_name", ""))

# Imported legacy buildings may lack a level; treat those as Level 1. Player-built
# and upgraded instances carry their actual level in the live state.
func _building_level(inst: Dictionary) -> int:
	return int(inst.get("level", 1))

# Profitable = the building's modelled cost per unit is below the market price of
# what it makes. Needs a fresh CostSolver pass; returns false if cost is unknown.
func _is_building_profitable(inst: Dictionary) -> bool:
	var iid := str(inst.get("instance_id", ""))
	if iid == "":
		return false
	var uc: float = CostSolver.get_building_unit_cost(iid)
	if uc < 0.0:
		return false
	var bd: Dictionary = CostSolver.last_result.get("per_building", {}).get(iid, {})
	var good_id: String = str(bd.get("output_good_id", ""))
	if good_id == "":
		return false
	var price: float = MarketState.get_price(good_id)
	return price > 0.0 and uc < price


func _update_profitable_run_streaks() -> void:
	var next: Dictionary = {}
	for inst in buildings.values():
		if not is_player_owned(inst):
			continue
		var iid := str(inst.get("instance_id", ""))
		if iid == "" or int(Production.full_output_streak_by_building.get(iid, 0)) <= 0:
			continue
		if _is_building_profitable(inst):
			next[iid] = int(_profitable_run_streaks.get(iid, 0)) + 1
	_profitable_run_streaks = next

# Leading integer of a string like "20 turns" -> 20; falls back to `default`.
func _leading_int(s: String, default_val: int) -> int:
	var digits := ""
	for ch in s.strip_edges():
		if ch >= "0" and ch <= "9":
			digits += ch
		elif digits != "":
			break
	return int(digits) if digits != "" else default_val

# --- Public API: survey range ---
func survey_range() -> int:
	return SURVEY_RANGE_BASE + (1 if is_unlocked("Computer Assisted Geoscanning") else 0)

## A tile is surveyable when it lies within survey_range() tiles of a surveyed
## tile. Cached; invalidated whenever the surveyed set or range changes.
func is_tile_surveyable(tile_id: String) -> bool:
	if _surveyable_dirty:
		_rebuild_surveyable()
	return _surveyable_cache.has(tile_id)

func _rebuild_surveyable() -> void:
	_surveyable_cache.clear()
	var rng := survey_range()
	var dist: Dictionary = {}
	var queue: Array = []
	for t in surveyed_tiles:
		dist[t] = 0
		_surveyable_cache[t] = true
		queue.append(t)
	var head := 0
	while head < queue.size():
		var t: String = str(queue[head])
		head += 1
		var d := int(dist[t])
		if d >= rng:
			continue
		for n in Catalog.tile_neighbours(t):
			if not dist.has(n):
				dist[n] = d + 1
				_surveyable_cache[n] = true
				queue.append(n)
	_surveyable_dirty = false

# --- Cheats (debug terminal) ---
func _all_tile_ids() -> Array:
	var out: Array = []
	if _deposit_terrain == null:
		return out
	for coord in _deposit_terrain.tiles:
		var tid := str(_deposit_terrain.tiles[coord].get("id", ""))
		if tid != "":
			out.append(tid)
	return out

## Instantly fully-survey every tile currently within the survey limit.
func cheat_survey_within_limits() -> void:
	var targets: Array = []
	for tid in _all_tile_ids():
		if is_tile_surveyable(tid):
			targets.append(tid)
	for tid in targets:
		_cheat_reveal(tid)

## Instantly fully-survey every tile on the map.
func cheat_survey_all() -> void:
	for tid in _all_tile_ids():
		_cheat_reveal(tid)

## Cheat: unlock every research node. Skips the deliberately-dangling gates like
## 'hydro'/'consumer' (no node exists, so that content stays locked). Returns count.
func cheat_unlock_all_research() -> int:
	var n := 0
	for d in _unlock_defs:
		var t := str(d.get("title", ""))
		if t != "" and not unlocked_titles.has(t):
			grant_unlock(t, false)
			n += 1
	return n

## Survey one tile and play its reveal animation (but no per-tile toast).
func _cheat_reveal(tile_id: String) -> void:
	if surveyed_tiles.has(tile_id):
		return
	tile_survey_completed.emit(tile_id, _tile_deposit_goods(tile_id))
	mark_tile_surveyed(tile_id)

## Partially survey every tile within the survey limit (already-surveyed tiles stay surveyed).
func cheat_partial_within_limits() -> void:
	var targets: Array = []
	for tid in _all_tile_ids():
		if is_tile_surveyable(tid):
			targets.append(tid)
	for tid in targets:
		mark_tile_partial(tid)

## Partially survey the whole map (already-surveyed tiles stay surveyed).
func cheat_partial_all() -> void:
	for tid in _all_tile_ids():
		mark_tile_partial(tid)

## Cheat: apply a -60% labour-cost modifier for 10 turns. A single -60% lands
## exactly on EconomyConfig.LABOUR_FACTOR_MIN (1 - 0.60 = 0.40), so it exercises
## both the labour-floor clamp and the People-panel "max reduction" flag at once.
func cheat_labour_discount() -> void:
	Modifiers.add({
		"id": "cheat_labour_discount",
		"domain": "labour_headcount",
		"pct": -60.0,
		"duration_turns": 10,
		"label": "Debug: labour -60%",
		"source": "cheat",
	})

func get_tile_land_owned(tile_id: String) -> int:
	return int(tile_land_owned.get(tile_id, DEFAULT_TILE_LAND_OWNED))

# --- Battery storage (deposit model — docs/battery-storage-spec.md) ---

func get_tile_battery_cells(tile_id: String) -> Dictionary:
	return tile_battery_cells.get(tile_id, {})

# Total cell SLOTS the tile's player-owned battery housing provides (Σ cap by level).
func tile_battery_slots(tile_id: String) -> int:
	var slots := 0
	for inst in get_buildings_on_tile(tile_id):
		if not is_player_owned(inst):
			continue
		if str(Catalog.get_building(str(inst.get("building_id", ""))).get("category", "")) != "battery":
			continue
		slots += int(EconomyConfig.BATTERY_STORAGE_CAP.get(int(inst.get("level", 1)), 0))
	return slots

# Total cells loaded on the tile (across all battery types).
func tile_battery_cells_loaded(tile_id: String) -> int:
	var n := 0
	for q in get_tile_battery_cells(tile_id).values():
		n += int(q)
	return n

# Firming ⚡ the tile's loaded cells provide right now: Σ cells × density.
func tile_loaded_firming(tile_id: String) -> float:
	var f := 0.0
	var cells := get_tile_battery_cells(tile_id)
	for gid in cells:
		var internal := str(Catalog.get_good(str(gid)).get("internal_name", ""))
		f += float(cells[gid]) * float(EconomyConfig.BATTERY_CELL_DENSITY.get(internal, 0.0))
	return f

# Firming capacity a tile provides: loaded firming, capped at the housing's ⚡ capacity.
# (round, not floor — density is fractional, so e.g. 18 lithium cells = exactly 100 ⚡.)
func tile_firming_cap(tile_id: String) -> int:
	var slots := tile_battery_slots(tile_id)
	if slots <= 0:
		return 0
	return int(round(min(float(slots), tile_loaded_firming(tile_id))))

# Cells of `good_id` still needed to FILL the tile's remaining firming headroom.
# Pass `instance_id` to scope it to ONE battery instead: the panel is opened on a single
# building, and filling from the tile total meant a tile with four batteries ordered four
# batteries' worth from whichever one you happened to click (owner 2026-08-01). Cells are pooled
# per tile, so "this battery's share" is its own capacity less what the pool already firms —
# clamped to the tile's real remaining headroom so it can never over-order either.
func battery_cells_to_fill(tile_id: String, good_id: String, instance_id: String = "") -> int:
	var density := _battery_density(good_id)
	if density <= 0.0:
		return 0
	var loaded := tile_loaded_firming(tile_id)
	var free_firming := float(tile_battery_slots(tile_id)) - loaded
	if instance_id != "":
		var inst: Dictionary = get_building(instance_id)
		if not inst.is_empty():
			var own := float(EconomyConfig.BATTERY_STORAGE_CAP.get(int(inst.get("level", 1)), 0))
			free_firming = clampf(own - loaded, 0.0, free_firming)
	return maxi(0, int(floor(free_firming / density + 0.0001)))

func _battery_density(good_id: String) -> float:
	return float(EconomyConfig.BATTERY_CELL_DENSITY.get(
		str(Catalog.get_good(good_id).get("internal_name", "")), 0.0))

# A battery good is loadable only once its tech tier is unlocked.
func battery_type_loadable(good_id: String) -> bool:
	var internal := str(Catalog.get_good(good_id).get("internal_name", ""))
	if not EconomyConfig.BATTERY_TYPE_UNLOCK.has(internal):
		return false
	return is_unlocked(str(EconomyConfig.BATTERY_TYPE_UNLOCK[internal]))

# Load up to `qty` battery cells of `good_id` from the tile's stockpile into its housing
# (locked capital). Capped by the housing's free FIRMING headroom (cells × density must fit the
# ⚡ capacity), available stock, and tech unlock. Returns loaded count.
func load_battery_cells(tile_id: String, good_id: String, qty: int) -> int:
	if qty <= 0 or not battery_type_loadable(good_id):
		return 0
	var density := _battery_density(good_id)
	if density <= 0.0:
		return 0
	var free_firming := float(tile_battery_slots(tile_id)) - tile_loaded_firming(tile_id)
	var max_by_firming := int(floor(free_firming / density + 0.0001))  # epsilon: fractional density
	var avail := Stockpile.get_at_tile(tile_id, good_id)
	var take := mini(mini(qty, max_by_firming), avail)
	if take <= 0:
		return 0
	Stockpile.consume(tile_id, good_id, take)
	var cells: Dictionary = tile_battery_cells.get(tile_id, {})
	cells[good_id] = int(cells.get(good_id, 0)) + take
	tile_battery_cells[tile_id] = cells
	battery_cells_changed.emit(tile_id)
	return take

# Unload up to `qty` cells of `good_id` back to the tile stockpile (refund). Returns count.
func unload_battery_cells(tile_id: String, good_id: String, qty: int) -> int:
	if qty <= 0:
		return 0
	var cells: Dictionary = tile_battery_cells.get(tile_id, {})
	var have := int(cells.get(good_id, 0))
	var give := mini(qty, have)
	if give <= 0:
		return 0
	cells[good_id] = have - give
	if int(cells[good_id]) <= 0:
		cells.erase(good_id)
	if cells.is_empty():
		tile_battery_cells.erase(tile_id)
	else:
		tile_battery_cells[tile_id] = cells
	Stockpile.add(tile_id, good_id, give)
	battery_cells_changed.emit(tile_id)
	return give

# When housing shrinks (battery demolished / downgraded) and loaded firming exceeds the remaining
# ⚡ capacity, refund just enough cells to fit (stable type order).
func refund_battery_cells_over_slots(tile_id: String) -> void:
	var over_firming := tile_loaded_firming(tile_id) - float(tile_battery_slots(tile_id))
	if over_firming <= 0.0:
		return
	var cells: Dictionary = tile_battery_cells.get(tile_id, {})
	var gids: Array = cells.keys()
	gids.sort()
	for gid in gids:
		if over_firming <= 0.0:
			break
		var density := _battery_density(str(gid))
		if density <= 0.0:
			continue
		var give := mini(int(cells.get(gid, 0)), int(ceil(over_firming / density)))
		if give > 0:
			unload_battery_cells(tile_id, str(gid), give)
			over_firming -= float(give) * density

# Turns until the tile's in-flight fill completes (0 if none).
func battery_fill_turns_remaining(tile_id: String) -> int:
	var t := 0
	for f in pending_battery_fills:
		if str(f.get("tile_id", "")) == tile_id:
			t = maxi(t, int(f.get("turns_left", 0)))
	return t

# Order a fill from the MARKET: pay now; the cells install after the delivery lead. Returns
# {ok, turns, cost} (ok=false if not loadable / no route / can't afford).
func order_battery_fill_market(tile_id: String, good_id: String, qty: int) -> Dictionary:
	if qty <= 0 or not battery_type_loadable(good_id):
		return {"ok": false}
	var quote := TransportService.quote_market_buy(tile_id, good_id, qty, seaport_would_cover(good_id))
	if quote.is_empty():
		return {"ok": false}
	var cost := float(quote.get("cost", 0.0))
	if not deduct_money(cost):
		return {"ok": false, "reason": "funds", "cost": cost}
	commit_sea_shipping(str(quote.get("port", "")), good_id, qty, "buy")
	var turns: int = maxi(1, int(quote.get("turns", 1)))
	pending_battery_fills.append({"tile_id": tile_id, "good_id": good_id, "qty": qty, "turns_left": turns})
	battery_cells_changed.emit(tile_id)
	return {"ok": true, "turns": turns, "cost": cost}

# Order a fill from ANOTHER TILE's stockpile: reserve the cells now; they install after the route
# time. Returns {ok, turns}.
func order_battery_fill_from_tile(tile_id: String, good_id: String, qty: int, source_tile: String) -> Dictionary:
	if qty <= 0 or not battery_type_loadable(good_id) or source_tile == "":
		return {"ok": false}
	if Stockpile.get_at_tile(source_tile, good_id) < qty:
		return {"ok": false, "reason": "stock"}
	var rt := TransportService.route(source_tile, tile_id, good_id)
	var turns: int = maxi(1, int(rt.get("turns", 1)))
	Stockpile.consume(source_tile, good_id, qty)  # reserve the cells for the journey
	pending_battery_fills.append({"tile_id": tile_id, "good_id": good_id, "qty": qty, "turns_left": turns})
	battery_cells_changed.emit(tile_id)
	return {"ok": true, "turns": turns}

# Tick all in-flight fills down a turn; install any that have arrived. (PROCESS start, so the
# new firming applies the same turn.)
func tick_battery_fills() -> void:
	if pending_battery_fills.is_empty():
		return
	var still: Array = []
	for f in pending_battery_fills:
		f["turns_left"] = int(f.get("turns_left", 0)) - 1
		if int(f["turns_left"]) > 0:
			still.append(f)
		else:
			_install_battery_cells(str(f.get("tile_id", "")), str(f.get("good_id", "")), int(f.get("qty", 0)))
	pending_battery_fills = still

# Install delivered cells straight into the housing (already paid/reserved — not from stockpile).
# Any that no longer fit (housing shrank in transit) fall back to the tile stockpile.
func _install_battery_cells(tile_id: String, good_id: String, qty: int) -> void:
	var density := _battery_density(good_id)
	if density <= 0.0 or qty <= 0:
		return
	var free_firming := float(tile_battery_slots(tile_id)) - tile_loaded_firming(tile_id)
	var take := mini(qty, maxi(0, int(floor(free_firming / density + 0.0001))))
	if take > 0:
		var cells: Dictionary = tile_battery_cells.get(tile_id, {})
		cells[good_id] = int(cells.get(good_id, 0)) + take
		tile_battery_cells[tile_id] = cells
	if qty - take > 0:
		Stockpile.add(tile_id, good_id, qty - take)
	battery_cells_changed.emit(tile_id)

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

# Cash rebate a Chief Investment advisor gives toward a build: a fraction of the
# required build materials' CURRENT market value (tier3 +10% / tier2 +5% / tier1 -5%
# surcharge). Returned as a positive amount to subtract from the money cost.
# A seated Chief Investment advisor unlocks paying for construction on credit
# (LoanState.take_construction_loan — the 4th option on the missing-materials dialog).
func construction_credit_available() -> bool:
	return not _roster_entry(str(advisor_seats.get("chief_investment", ""))).is_empty()

func construction_material_rebate(building_id: String) -> float:
	if building_id == "":
		return 0.0
	return _materials_rebate(Construction.requirements_for(building_id))

# Cash rebate = a fraction of the given materials' current market value, using the
# Chief Investment "construction_rebate" tier fraction (tier3 +10% / tier2 +5% / tier1 -5%).
# Shared by new builds and upgrades (the upgrade kit is valued the same way).
func _materials_rebate(reqs: Dictionary) -> float:
	var frac: float = float(Modifiers.resolve_pct("construction_rebate", "*", {}).get("net", 0.0)) / 100.0
	if frac == 0.0:
		return 0.0
	var mat_value := 0.0
	for good_id in reqs:
		mat_value += float(int(reqs[good_id])) * MarketState.get_price(str(good_id))
	return mat_value * frac

# Land / NPC-building purchase cost after any Chief Investment "purchase_cost" discount
# (tier3 -10% / tier2 -5% / tier1 +5% surcharge).
func purchase_cost_after_advisor(base_cost: float, ctx: Dictionary = {}) -> float:
	var mult: float = maxf(0.0, 1.0 + float(Modifiers.resolve_pct("purchase_cost", "*", ctx).get("net", 0.0)) / 100.0)
	return base_cost * mult

# Construction takes one turn longer than the raw CSV value (BUILD_DURATION_BUMP).
# The master-builder advisor (an Ops-3 veteran in the COO seat) shaves a turn off;
# real builds never drop below BUILD_DURATION_MIN. Instant (0-turn) buildings stay instant.
const BUILD_DURATION_BUMP := 1
const BUILD_DURATION_MIN := 1
const MASTER_BUILDER_ID := "gerald"   # Gerald Vance's specialty: -1 build turn while COO

func is_master_builder_active() -> bool:
	return str(advisor_seats.get("coo", "")) == MASTER_BUILDER_ID

func effective_build_duration(building_id: String) -> int:
	var base := int(Catalog.get_building(building_id).get("build_duration", 0))
	if base <= 0:
		return base   # instant buildings (infrastructure) stay instant
	var dur := base + BUILD_DURATION_BUMP
	if is_master_builder_active():
		dur -= 1
	return maxi(BUILD_DURATION_MIN, dur)

func purchase_tile_land(tile_id: String, patches: int = 1, cap: int = MAX_TILE_LAND) -> bool:
	if tile_id == "":
		return false
	var available := get_tile_land_patches_available(tile_id, cap)
	if available <= 0:
		return false
	var clamped_patches: int = clampi(patches, 1, available)
	# ctx carries the tile so per-tile purchase_cost modifiers (e.g. the land-deal
	# decision's "development premium" follow-up) can target it.
	var cost := purchase_cost_after_advisor(float(clamped_patches) * LAND_PATCH_COST, {"tile_id": tile_id})
	if not deduct_money(cost):
		return false
	var owned := get_tile_land_owned(tile_id)
	# The last patch can be a clipped sliver — never grant past the NPC-adjusted cap.
	var granted := mini(clamped_patches * LAND_PATCH_SIZE, get_tile_land_units_available(tile_id, cap))
	tile_land_owned[tile_id] = mini(max_tile_land(tile_id), owned + granted)
	tile_land_owned_changed.emit(tile_id)
	return true

# --- Land sales (decision events; decision-events-spec.md D8) -----------------
# Only surplus above the universal default holding is sellable, and only on tiles
# with no player buildings or construction projects, so a sale can never undercut
# a building footprint (land gates placement at get_tile_land_owned).

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
	add_money(float(clamped) * price_per_patch)
	tile_land_owned_changed.emit(tile_id)
	return true

func get_building(instance_id: String) -> Dictionary:
	# Returns the instance dict, or empty dict if not found
	return buildings.get(instance_id, {})

func is_building_available(building_id: String) -> bool:
	# Ports are map infrastructure that may be bought from their existing owner, never built.
	if building_id == "b_004":
		return false
	if RECYCLING_BUILDING_IDS.has(building_id) and not recycling_unlocked:
		return false
	return hidden_buildings_unlocked or not HIDDEN_BUILDING_IDS.has(building_id)

## Is this good shown to the player at all? Only the recycling chain is ever hidden today.
func is_good_available(good_id: String) -> bool:
	return recycling_unlocked or not RECYCLING_GOOD_IDS.has(good_id)

## Every good the player may see, in catalogue order. The one place the gate is applied, so
## a panel opts in by calling this instead of Catalog.all_goods() — the market and telemetry
## deliberately keep the full set (a price for a hidden good is harmless; a gap is not).
func visible_goods() -> Array:
	if recycling_unlocked:
		return Catalog.all_goods()
	var out: Array = []
	for good_variant: Variant in Catalog.all_goods():
		var good: Dictionary = good_variant
		if is_good_available(str(good.get("id", ""))):
			out.append(good)
	return out

## Cheat (`unlock recycling`): put the waste chain and its two plants back.
func cheat_unlock_recycling() -> void:
	if recycling_unlocked:
		return
	recycling_unlocked = true
	unlock_granted.emit("Recycling", "The waste chain and its plants are enabled.", false)
	hidden_buildings_enabled.emit()   # the catalogue panels already refresh on this

func cheat_unlock_hidden_buildings() -> void:
	if hidden_buildings_unlocked:
		return
	hidden_buildings_unlocked = true
	# Existing catalogue panels already refresh from this signal after research cheats.
	unlock_granted.emit("Hidden Buildings", "Legacy prototype buildings enabled.", false)
	hidden_buildings_enabled.emit()

## Cheat (`unlock advisors`): open the full advisor roster, every seat, and the
## People-Management seat-unlock research — all hidden by default in the demo, which
## ships only Andrew/Vera/Gerald and the CFO/COO/Technical Director/Chief Markets seats.
func cheat_unlock_advisors() -> void:
	if advisors_unlocked:
		return
	advisors_unlocked = true
	all_seats_unlocked = true
	for a in ADVISOR_ROSTER:
		var id := str(a.get("id", ""))
		if id != "" and not recruited_advisor_ids.has(id):
			recruited_advisor_ids.append(id)
	advisors_changed.emit()

# --- Helpers ---
func _generate_instance_id(building_id: String) -> String:
	_next_instance_counter += 1
	# %s injects the string, %06x injects the hex counter
	return "inst_%s_%06x" % [building_id, _next_instance_counter]

# Public: reserve a unique instance id before the building exists. Used by Construction so a
# project keeps the same id from placement to completion.
func reserve_instance_id(building_id: String) -> String:
	return _generate_instance_id(building_id)

# --- Reset (useful for new game / testing) ---
func reset() -> void:
	money = 1000
	hidden_buildings_unlocked = false
	recycling_unlocked = false
	advisors_unlocked = false
	construct_cost_display = "grid"
	construct_start_half_capacity = false
	construct_auto_buy_land = false
	construct_expanded_recipe_mode = false
	construct_material_source = "ask"
	construct_output_destination = "market"
	power_priority_coal_gas = "self"
	power_priority_wind_solar = "grid"
	buildings.clear()
	tile_buildings.clear()
	output_stockpile_destinations.clear()
	output_split_destinations.clear()
	output_special_order_destinations.clear()
	output_ship_quantities.clear()
	pending_output_stockpile_selection.clear()
	queued_stockpile_market_sales.clear()
	sell_surplus_tiles.clear()
	auto_sell_goods.clear()
	auto_sell_keep.clear()
	auto_sell_impact.clear()
	pending_transport_shipments.clear()
	arrival_turns.clear()
	_sea_shipping_turn = -1
	_sea_port_usage_this_turn.clear()
	_sea_port_charges_this_turn.clear()
	_last_sea_shipping_turn = -1
	_last_sea_port_usage.clear()
	_last_sea_port_charges.clear()
	_unpaid_purchase_total = 0.0
	pending_upgrades.clear()
	pending_retrofits.clear()
	demolish_queue.clear()
	paused_buildings.clear()
	_last_link_flow.clear()
	_last_transit_shipments.clear()
	_link_over_history.clear()
	_link_congestion_paid.clear()
	overflow_shipments.clear()
	sales_by_tile.clear()
	tile_land_owned.clear()
	tile_battery_cells.clear()
	pending_battery_fills.clear()
	workforce_policies.clear()
	workforce_policy_effects.clear()
	labour_multiplier = EconomyConfig.LABOUR_MULTIPLIER_DEFAULT
	labour_output_pressure_pct = 0.0
	idle_labour_pay_share = 1.0
	permanent_advisor_ids.clear()
	advisor_seats.clear()
	all_seats_unlocked = false
	founder_seat = ""
	founder_leaves_turn = 0
	freight_credit_units = 0
	ghost_holdings.clear()
	building_tabs.clear()
	construct_credit_default = "ask"
	max_advisor_slots = MAX_ADVISOR_SLOTS_DEFAULT
	crossed_milestones.clear()
	recruited_advisor_ids.clear()
	fired_advisor_cooldowns.clear()
	advisor_loyalty.clear()
	advisor_hired_turn.clear()
	_advisor_walk_streak.clear()
	advisor_missions_completed.clear()
	_advisor_mission5_streak.clear()
	advisor_mission_policies.clear()
	_agenda_flags.clear()
	_agenda_grid_sell_streak = 0
	_agenda_no_buy_streak = 0
	_agenda_last_build_turn = 0
	_advisor_profit_streak = 0
	advisor_slot_profit_unlocked = false
	fake_money_this_turn = 0.0
	peak_profit_per_turn = 0.0
	match_rng_seed = DEFAULT_MATCH_RNG_SEED
	_match_rng.seed = match_rng_seed
	reconcile_advisor_modifiers()
	recurring_moves.clear()
	scheduled_moves.clear()
	recurring_sells.clear()
	recurring_bulk_sells.clear()
	recurring_buys.clear()
	cfo_tax_credit_pool.clear()
	cfo_tax_credit_intro_shown = false
	transaction_log.clear()
	move_log.clear()
	input_tile_only.clear()
	# Research state is match-scoped: a reset (new game / scenario start) must
	# clear it, or unlocks leak from the previous match. (Load overwrites it via
	# import_state, so this only bites the reset-without-import paths.)
	unlocked_titles.clear()
	_unlock_progress.clear()
	_port_sale_total = 0
	_port_sales_by_port.clear()
	_port_sales_by_class.clear()
	_infrastructure_usage_streaks.clear()
	_infrastructure_usage_last_turn.clear()
	_profitable_run_streaks.clear()
	_research_progress_dirty = true
	_research_progress_last_turn = -1
	stockpile_feed_streaks.clear()
	# These research ledgers live in their owning simulation systems, but share
	# the match lifetime. Reset-without-import paths (tests/scenarios) must not let
	# production or sale progress leak into the next match.
	MarketState.reset_lifetime_sales()
	Production.reset_lifetime_research_metrics()
	_next_instance_counter = 0
	ruleset = DEFAULT_RULESET.duplicate(true)
	TurnManager.apply_ruleset(ruleset)   # back to the campaign length until a match sets one
	VictoryState.apply_ruleset(ruleset)   # and back to the campaign victory tracks
	scenario_name = ""
	cheats_used = false
	state_reset.emit()
	advisors_changed.emit()

# --- Debug ---
func debug_dump() -> Dictionary:
	# Returns the full state as a dict, useful for save/load and debugging
	return {
		"money": money,
		"buildings": _buildings_for_save(),
		"tile_buildings": tile_buildings.duplicate(true),
		"output_stockpile_destinations": output_stockpile_destinations.duplicate(true),
		"output_split_destinations": output_split_destinations.duplicate(true),
		"output_special_order_destinations": output_special_order_destinations.duplicate(true),
		"output_ship_quantities": output_ship_quantities.duplicate(true),
		"queued_stockpile_market_sales": queued_stockpile_market_sales.duplicate(true),
		"pending_transport_shipments": pending_transport_shipments.duplicate(true),
		"tile_land_owned": tile_land_owned.duplicate(true),
		"_next_instance_counter": _next_instance_counter,
	}

# --- Save/load (orchestrated by the SaveLoad autoload; docs/save_load_spec.md) ---

# Route geometry (tiles/path/legs) is stripped from shipments on save — it can hold
# Vector2s (not JSON-safe) and is purely visual; it is re-quoted from the live route
# graph on import so paths stay valid even if infrastructure changed.
const _SHIPMENT_ROUTE_KEYS: Array = ["tiles", "path", "legs"]

func export_state() -> Dictionary:
	return {
		"money": money,
		"ruleset": ruleset.duplicate(true),
		"scenario_name": scenario_name,
		"cheats_used": cheats_used,
		"construct_cost_display": construct_cost_display,
		"construct_start_half_capacity": construct_start_half_capacity,
		"construct_auto_buy_land": construct_auto_buy_land,
		"construct_expanded_recipe_mode": construct_expanded_recipe_mode,
		"construct_material_source": construct_material_source,
		"construct_output_destination": construct_output_destination,
		"power_priority_coal_gas": power_priority_coal_gas,
		"power_priority_wind_solar": power_priority_wind_solar,
		"next_instance_counter": _next_instance_counter,
		"shipment_id_counter": _shipment_id_counter,
		"buildings": _buildings_for_save(),
		"tile_land_owned": tile_land_owned.duplicate(true),
		"tile_battery_cells": tile_battery_cells.duplicate(true),
		"pending_battery_fills": pending_battery_fills.duplicate(true),
		"labour_multiplier": labour_multiplier,
		"labour_output_pressure_pct": labour_output_pressure_pct,
		"idle_labour_pay_share": idle_labour_pay_share,
		"workforce_policies": workforce_policies.duplicate(true),
		"workforce_policy_effects": workforce_policy_effects.duplicate(true),
		"permanent_advisor_ids": permanent_advisor_ids.duplicate(true),
		"advisor_seats": advisor_seats.duplicate(true),
		"all_seats_unlocked": all_seats_unlocked,
		"founder_seat": founder_seat,
		"founder_leaves_turn": founder_leaves_turn,
		"freight_credit_units": freight_credit_units,
		"ghost_holdings": ghost_holdings.duplicate(true),
		"building_tabs": building_tabs.duplicate(true),
		"construct_credit_default": construct_credit_default,
		"max_advisor_slots": max_advisor_slots,
		"advisor_rng_seed": match_rng_seed,
		"advisor_rng_state": _match_rng.state,
		"advisor_crossed_milestones": crossed_milestones.duplicate(true),
		"recruited_advisor_ids": recruited_advisor_ids.duplicate(true),
		"fired_advisor_cooldowns": fired_advisor_cooldowns.duplicate(true),
		"advisor_loyalty": advisor_loyalty.duplicate(true),
		"advisor_hired_turn": advisor_hired_turn.duplicate(true),
		"cfo_tax_credit_pool": cfo_tax_credit_pool.duplicate(true),
		"cfo_tax_credit_intro_shown": cfo_tax_credit_intro_shown,
		"advisor_walk_streak": _advisor_walk_streak.duplicate(true),
		"advisor_missions_completed": advisor_missions_completed.duplicate(true),
		"advisor_mission5_streak": _advisor_mission5_streak.duplicate(true),
		"advisor_mission_policies": advisor_mission_policies.duplicate(true),
		"agenda_last_build_turn": _agenda_last_build_turn,
		"advisor_profit_streak": _advisor_profit_streak,
		"advisor_slot_profit_unlocked": advisor_slot_profit_unlocked,
		"advisor_peak_profit": peak_profit_per_turn,
		"sell_mode": sell_mode,
		"route_objective": route_objective,
		"output_stockpile_destinations": output_stockpile_destinations.duplicate(true),
		"output_split_destinations": output_split_destinations.duplicate(true),
		"output_special_order_destinations": output_special_order_destinations.duplicate(true),
		"output_ship_quantities": output_ship_quantities.duplicate(true),
		"input_tile_only": input_tile_only.duplicate(true),
		"recurring_moves": recurring_moves.duplicate(true),
		"scheduled_moves": scheduled_moves.duplicate(true),
		"recurring_sells": recurring_sells.duplicate(true),
		"recurring_bulk_sells": recurring_bulk_sells.duplicate(true),
		"recurring_buys": recurring_buys.duplicate(true),
		"sell_surplus_tiles": sell_surplus_tiles.duplicate(true),
		"auto_sell_goods": auto_sell_goods.duplicate(true),
		"auto_sell_keep": auto_sell_keep.duplicate(true),
		"auto_sell_impact": auto_sell_impact.duplicate(true),
		"queued_stockpile_market_sales": queued_stockpile_market_sales.duplicate(true),
		"pending_transport_shipments": _shipments_for_save(),
		"arrival_turns": _arrival_turns_for_save(),
		# Additive (v3 transport panel): an older save has neither, and the empty
		# default reads correctly as "no history yet" until turns accrue.
		"link_over_history": _link_over_history.duplicate(true),
		"link_congestion_paid": _link_congestion_paid.duplicate(),
		"pending_upgrades": pending_upgrades.duplicate(true),
		"pending_retrofits": pending_retrofits.duplicate(true),
		"demolish_queue": demolish_queue.duplicate(true),
		"paused_buildings": paused_buildings.duplicate(true),
		"overflow_shipments": overflow_shipments.duplicate(true),
		"transaction_log": transaction_log.duplicate(true),
		"move_log": move_log.duplicate(true),
		"surveyed_tiles": surveyed_tiles.duplicate(true),
		"partially_surveyed_tiles": partially_surveyed_tiles.duplicate(true),
		"surveying_in_progress": surveying_in_progress.duplicate(true),
		"surveying_reveal": surveying_reveal.duplicate(true),
		"revealed_deposits": revealed_deposits.duplicate(true),
		"deposit_remaining": deposit_remaining.duplicate(true),
		"unlocked_titles": unlocked_titles.duplicate(true),
		"unlock_progress": _unlock_progress.duplicate(true),
		"port_sale_total": _port_sale_total,
		"port_sales_by_port": _port_sales_by_port.duplicate(true),
		"port_sales_by_class": _port_sales_by_class.duplicate(true),
		"infrastructure_usage_streaks": _infrastructure_usage_streaks.duplicate(true),
		"infrastructure_usage_last_turn": _infrastructure_usage_last_turn.duplicate(true),
		"profitable_run_streaks": _profitable_run_streaks.duplicate(true),
		"stockpile_feed_streaks": stockpile_feed_streaks.duplicate(true),
		"seaport_auto_subscribe": seaport_auto_subscribe,
		"seaport_subscribed": seaport_subscribed.duplicate(true),
		"last_sea_shipping_turn": _last_sea_shipping_turn,
		"last_sea_port_usage": _last_sea_port_usage.duplicate(true),
		"last_sea_port_charges": _last_sea_port_charges.duplicate(true),
	}

func import_state(d: Dictionary) -> void:
	# Silent full overwrite of every exported field — SaveLoad emits the refresh
	# signals once after every system has imported. Missing keys fall back to the
	# new-game default, so older/partial snapshots (and Phase 3 start configs) load.
	money = float(d.get("money", EconomyConfig.STARTING_MONEY))
	ruleset = (d.get("ruleset", DEFAULT_RULESET) as Dictionary).duplicate(true)
	# The campaign length lives in the ruleset, so this is the one moment it is known —
	# for a new game and for a load alike. TurnManager reads nothing else about the match.
	TurnManager.apply_ruleset(ruleset)
	VictoryState.apply_ruleset(ruleset)   # which set of victory tracks this match runs
	# Tolerant readers: saves from before these existed load as an unknown start, uncheated.
	scenario_name = str(d.get("scenario_name", ""))
	cheats_used = bool(d.get("cheats_used", false))
	set_construct_cost_display(str(d.get("construct_cost_display", "grid")), false)
	set_construct_start_half_capacity(bool(d.get("construct_start_half_capacity", false)), false)
	# Additive key: saves written before this setting existed simply default to off.
	set_construct_auto_buy_land(bool(d.get("construct_auto_buy_land", false)), false)
	set_construct_expanded_recipe_mode(bool(d.get("construct_expanded_recipe_mode", false)), false)
	set_construct_material_source(str(d.get("construct_material_source", "ask")), false)
	set_construct_output_destination(str(d.get("construct_output_destination", "market")), false)
	# Additive key: saves written before this setting existed default to the same
	# intermittency-avoiding defaults a fresh match starts with.
	set_power_priority("coal_gas", str(d.get("power_priority_coal_gas", "self")), false)
	set_power_priority("wind_solar", str(d.get("power_priority_wind_solar", "grid")), false)
	_next_instance_counter = int(d.get("next_instance_counter", 0))
	_shipment_id_counter = int(d.get("shipment_id_counter", 0))
	buildings = _normalise_loaded_buildings(d.get("buildings", {}))
	tile_land_owned = (d.get("tile_land_owned", {}) as Dictionary).duplicate(true)
	tile_battery_cells = (d.get("tile_battery_cells", {}) as Dictionary).duplicate(true)
	pending_battery_fills = (d.get("pending_battery_fills", []) as Array).duplicate(true)
	labour_multiplier = float(d.get("labour_multiplier", EconomyConfig.LABOUR_MULTIPLIER_DEFAULT))
	labour_output_pressure_pct = float(d.get("labour_output_pressure_pct", 0.0))
	idle_labour_pay_share = float(d.get("idle_labour_pay_share", 1.0))
	workforce_policies = (d.get("workforce_policies", {}) as Dictionary).duplicate(true)
	workforce_policy_effects = (d.get("workforce_policy_effects", {}) as Dictionary).duplicate(true)
	recruited_advisor_ids = _sanitize_advisor_ids(d.get("recruited_advisor_ids", STARTING_TRIO))
	advisor_loyalty = (d.get("advisor_loyalty", {}) as Dictionary).duplicate(true)
	cfo_tax_credit_pool = (d.get("cfo_tax_credit_pool", []) as Array).duplicate(true)
	cfo_tax_credit_intro_shown = bool(d.get("cfo_tax_credit_intro_shown", false))
	_advisor_walk_streak = (d.get("advisor_walk_streak", {}) as Dictionary).duplicate(true)
	advisor_missions_completed = (d.get("advisor_missions_completed", {}) as Dictionary).duplicate(true)
	_advisor_mission5_streak = (d.get("advisor_mission5_streak", {}) as Dictionary).duplicate(true)
	advisor_mission_policies = (d.get("advisor_mission_policies", []) as Array).duplicate(true)
	_agenda_last_build_turn = int(d.get("agenda_last_build_turn", 0))
	fired_advisor_cooldowns = {}
	for fid in (d.get("fired_advisor_cooldowns", {}) as Dictionary):
		if not _roster_entry(str(fid)).is_empty():
			var turns := int(d["fired_advisor_cooldowns"][fid])
			if turns > 0:
				fired_advisor_cooldowns[str(fid)] = mini(turns, FIRE_COOLDOWN_TURNS)
	permanent_advisor_ids = _sanitize_advisor_ids(d.get("permanent_advisor_ids", []))
	# A benched advisor can't also be employed.
	for fid in fired_advisor_cooldowns.keys():
		permanent_advisor_ids.erase(fid)
	# Employed must be a subset of recruited.
	for pid in permanent_advisor_ids:
		if not recruited_advisor_ids.has(pid):
			recruited_advisor_ids.append(pid)
	# Decision-gate tenure (tolerant reader): pre-feature saves carry no hire turns,
	# so existing councils default to "hired last turn" and count immediately.
	advisor_hired_turn = {}
	var raw_hired: Dictionary = d.get("advisor_hired_turn", {})
	for pid in permanent_advisor_ids:
		advisor_hired_turn[str(pid)] = int(raw_hired.get(str(pid), int(TurnManager.current_turn) - 1))
	advisor_seats = _sanitize_advisor_seats(d.get("advisor_seats", {}))
	# Default LOCKED: the demo ships four base seats until `unlock advisors` (owner 2026-08-19).
	# A save that had actually opened the council carries the flag; only a snapshot missing the
	# key (a fresh start config, which never sets it) reads false — which is the gated default
	# a new game wants. (Was `true` as a pre-founder tolerant-reader default; that leaked every
	# seat onto the council grid on every new game.)
	all_seats_unlocked = bool(d.get("all_seats_unlocked", false))
	founder_seat = str(d.get("founder_seat", ""))
	founder_leaves_turn = int(d.get("founder_leaves_turn", 0))
	freight_credit_units = int(d.get("freight_credit_units", 0))
	ghost_holdings = (d.get("ghost_holdings", {}) as Dictionary).duplicate(true)
	building_tabs = (d.get("building_tabs", {}) as Dictionary).duplicate(true)
	construct_credit_default = str(d.get("construct_credit_default", "ask"))
	max_advisor_slots = clampi(int(d.get("max_advisor_slots", MAX_ADVISOR_SLOTS_DEFAULT)), MAX_ADVISOR_SLOTS_DEFAULT, MAX_ADVISOR_SLOTS_CAP)
	match_rng_seed = int(d.get("advisor_rng_seed", DEFAULT_MATCH_RNG_SEED))
	_match_rng.seed = match_rng_seed
	_match_rng.state = int(d.get("advisor_rng_state", _match_rng.state))
	crossed_milestones = (d.get("advisor_crossed_milestones", []) as Array).duplicate(true)
	_advisor_profit_streak = int(d.get("advisor_profit_streak", 0))
	advisor_slot_profit_unlocked = bool(d.get("advisor_slot_profit_unlocked", false))
	peak_profit_per_turn = float(d.get("advisor_peak_profit", 0.0))
	sell_mode = int(d.get("sell_mode", SellMode.STOCKPILE_ALL))
	route_objective = int(d.get("route_objective", RouteObjective.FASTEST))
	output_stockpile_destinations = (d.get("output_stockpile_destinations", {}) as Dictionary).duplicate(true)
	output_split_destinations = (d.get("output_split_destinations", {}) as Dictionary).duplicate(true)
	output_special_order_destinations = (d.get("output_special_order_destinations", {}) as Dictionary).duplicate(true)
	output_ship_quantities = (d.get("output_ship_quantities", {}) as Dictionary).duplicate(true)
	input_tile_only = (d.get("input_tile_only", {}) as Dictionary).duplicate(true)
	recurring_moves = (d.get("recurring_moves", []) as Array).duplicate(true)
	scheduled_moves = (d.get("scheduled_moves", []) as Array).duplicate(true)
	recurring_sells = (d.get("recurring_sells", []) as Array).duplicate(true)
	recurring_bulk_sells = (d.get("recurring_bulk_sells", []) as Array).duplicate(true)
	recurring_buys = (d.get("recurring_buys", []) as Array).duplicate(true)
	sell_surplus_tiles = (d.get("sell_surplus_tiles", {}) as Dictionary).duplicate(true)
	auto_sell_goods = (d.get("auto_sell_goods", {}) as Dictionary).duplicate(true)
	auto_sell_keep = (d.get("auto_sell_keep", {}) as Dictionary).duplicate(true)
	auto_sell_impact = (d.get("auto_sell_impact", {}) as Dictionary).duplicate(true)
	queued_stockpile_market_sales = (d.get("queued_stockpile_market_sales", {}) as Dictionary).duplicate(true)
	pending_transport_shipments = (d.get("pending_transport_shipments", []) as Array).duplicate(true)
	# Pre-history saves simply start with no record — the readout says "no data yet"
	# rather than lying, and fills in as deliveries land.
	arrival_turns = _arrival_turns_from_save(d.get("arrival_turns", {}))
	_link_over_history = (d.get("link_over_history", {}) as Dictionary).duplicate(true)
	_link_congestion_paid = (d.get("link_congestion_paid", {}) as Dictionary).duplicate()
	_recompute_unpaid_purchases()  # rebuilt from the shipments so the accumulator can't drift
	pending_upgrades = (d.get("pending_upgrades", []) as Array).duplicate(true)
	pending_retrofits = (d.get("pending_retrofits", []) as Array).duplicate(true)
	demolish_queue = (d.get("demolish_queue", {}) as Dictionary).duplicate(true)
	paused_buildings = (d.get("paused_buildings", {}) as Dictionary).duplicate(true)
	overflow_shipments = (d.get("overflow_shipments", []) as Array).duplicate(true)
	transaction_log = (d.get("transaction_log", []) as Array).duplicate(true)
	move_log = (d.get("move_log", []) as Array).duplicate(true)
	surveyed_tiles = (d.get("surveyed_tiles", {}) as Dictionary).duplicate(true)
	partially_surveyed_tiles = (d.get("partially_surveyed_tiles", {}) as Dictionary).duplicate(true)
	surveying_in_progress = (d.get("surveying_in_progress", {}) as Dictionary).duplicate(true)
	surveying_reveal = (d.get("surveying_reveal", {}) as Dictionary).duplicate(true)
	revealed_deposits = (d.get("revealed_deposits", {}) as Dictionary).duplicate(true)
	# Default to the CURRENT value, not {}: a start config carries no deposit data,
	# so the CSV-seeded yields from world_map._ready must survive the import. Full
	# saves always carry the key and overwrite as usual.
	deposit_remaining = (d.get("deposit_remaining", deposit_remaining) as Dictionary).duplicate(true)
	unlocked_titles = (d.get("unlocked_titles", {}) as Dictionary).duplicate(true)
	# Research saves still store display titles. Preserve the node when its title
	# becomes more specific, so an existing Containerized Freight unlock keeps its
	# Tier-II position and receives the revised port-fee effect.
	if unlocked_titles.has("Containerized Freight"):
		unlocked_titles["Multimodal Containerized Freight"] = unlocked_titles["Containerized Freight"]
		unlocked_titles.erase("Containerized Freight")
	_unlock_progress = (d.get("unlock_progress", {}) as Dictionary).duplicate(true)
	_port_sale_total = int(d.get("port_sale_total", 0))
	_port_sales_by_port = (d.get("port_sales_by_port", {}) as Dictionary).duplicate(true)
	_port_sales_by_class = (d.get("port_sales_by_class", {}) as Dictionary).duplicate(true)
	_infrastructure_usage_streaks = (d.get("infrastructure_usage_streaks", {}) as Dictionary).duplicate(true)
	_infrastructure_usage_last_turn = (d.get("infrastructure_usage_last_turn", {}) as Dictionary).duplicate(true)
	_profitable_run_streaks = (d.get("profitable_run_streaks", {}) as Dictionary).duplicate(true)
	_research_progress_dirty = true
	_research_progress_last_turn = -1
	stockpile_feed_streaks = (d.get("stockpile_feed_streaks", {}) as Dictionary).duplicate(true)
	seaport_auto_subscribe = bool(d.get("seaport_auto_subscribe", false))
	seaport_subscribed = (d.get("seaport_subscribed", {}) as Dictionary).duplicate(true)
	_last_sea_shipping_turn = int(d.get("last_sea_shipping_turn", -1))
	_last_sea_port_usage = (d.get("last_sea_port_usage", {}) as Dictionary).duplicate(true)
	_last_sea_port_charges = (d.get("last_sea_port_charges", {}) as Dictionary).duplicate(true)
	# Derived state: the tile index is rebuilt, never saved; caches invalidate.
	_rebuild_tile_index()
	_surveyable_dirty = true
	pending_output_stockpile_selection.clear()
	sales_by_tile.clear()
	_requote_shipment_routes()

## PackedInt32Array does not survive the JSON round trip, so the history saves as plain
## arrays of ints and is rebuilt on load.
func _arrival_turns_for_save() -> Dictionary:
	var out: Dictionary = {}
	for key in arrival_turns:
		var plain: Array = []
		for t in (arrival_turns[key] as PackedInt32Array):
			plain.append(int(t))
		out[key] = plain
	return out


func _arrival_turns_from_save(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not (raw is Dictionary):
		return out
	for key in (raw as Dictionary):
		var packed := PackedInt32Array()
		for t in ((raw as Dictionary)[key] as Array):
			packed.append(int(t))
		out[str(key)] = packed
	return out


func _shipments_for_save() -> Array:
	var out: Array = []
	for shipment in pending_transport_shipments:
		var s: Dictionary = shipment.duplicate(true)
		for key in _SHIPMENT_ROUTE_KEYS:
			s.erase(key)
		out.append(s)
	return out

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

func _requote_shipment_routes() -> void:
	# Restore the visual route geometry stripped on save. Countdown fields
	# (turns_remaining / transport_turns) are the saved truth and stay untouched.
	for shipment in pending_transport_shipments:
		var src := str(shipment.get("source_tile", ""))
		var dst := str(shipment.get("destination_tile", ""))
		if src == "" or dst == "":
			continue
		var route: Dictionary = TransportService.route(src, dst, str(shipment.get("good_id", "")))
		for key in _SHIPMENT_ROUTE_KEYS:
			shipment[key] = route.get(key, [])

func set_sell_mode(mode: int) -> void:
	sell_mode = mode
	sell_mode_changed.emit(mode)

## Debug cheat: toggle verbose production / CostSolver console logs.
## Returns the new state. Session-only, never persisted.
func toggle_debug_turn_logs() -> bool:
	debug_turn_logs_enabled = not debug_turn_logs_enabled
	return debug_turn_logs_enabled

## Debug cheat: switch between the classic and redesigned (v2) building-detail panel.
## Returns the new state. Session-only, never persisted.
func toggle_show_port_badge() -> bool:
	show_port_badge = not show_port_badge
	return show_port_badge


func toggle_use_empire_sprite_view() -> bool:
	use_empire_sprite_view = not use_empire_sprite_view
	return use_empire_sprite_view

## Debug cheat: switch the bottom-menu Empire View icon to/from its badge-centre
## alternative. Session-only, so it is safe for in-match visual comparison.
func toggle_use_empire_button_badge() -> bool:
	use_empire_button_badge = not use_empire_button_badge
	empire_button_icon_changed.emit(use_empire_button_badge)
	return use_empire_button_badge

func set_use_construct_panel_v2(enabled: bool) -> bool:
	if enabled == use_construct_panel_v2:
		return use_construct_panel_v2
	use_construct_panel_v2 = enabled
	construct_panel_v2_changed.emit(use_construct_panel_v2)
	return use_construct_panel_v2

func toggle_use_construct_panel_v2() -> bool:
	return set_use_construct_panel_v2(not use_construct_panel_v2)

func set_use_construct_panel_v3(enabled: bool) -> bool:
	if enabled == use_construct_panel_v3:
		return use_construct_panel_v3
	use_construct_panel_v3 = enabled
	construct_panel_v3_changed.emit(use_construct_panel_v3)
	return use_construct_panel_v3

func toggle_use_construct_panel_v3() -> bool:
	return set_use_construct_panel_v3(not use_construct_panel_v3)

func set_use_topbar_v3_1(enabled: bool) -> bool:
	if enabled == use_topbar_v3_1:
		return use_topbar_v3_1
	use_topbar_v3_1 = enabled
	topbar_v3_1_changed.emit(use_topbar_v3_1)
	return use_topbar_v3_1

func toggle_use_topbar_v3_1() -> bool:
	return set_use_topbar_v3_1(not use_topbar_v3_1)

func set_construct_cost_display(value: String, emit_change: bool = true) -> void:
	var resolved := value.to_lower()
	if resolved not in ["grid", "compact", "list"]:
		resolved = "grid"
	if construct_cost_display == resolved:
		return
	construct_cost_display = resolved
	if emit_change:
		construct_settings_changed.emit()

func set_construct_start_half_capacity(enabled: bool, emit_change: bool = true) -> void:
	if construct_start_half_capacity == enabled:
		return
	construct_start_half_capacity = enabled
	if emit_change:
		construct_settings_changed.emit()

func set_construct_auto_buy_land(enabled: bool, emit_change: bool = true) -> void:
	if construct_auto_buy_land == enabled:
		return
	construct_auto_buy_land = enabled
	if emit_change:
		construct_settings_changed.emit()

func set_construct_expanded_recipe_mode(enabled: bool, emit_change: bool = true) -> void:
	if construct_expanded_recipe_mode == enabled:
		return
	construct_expanded_recipe_mode = enabled
	if emit_change:
		construct_settings_changed.emit()


## The material source the NEXT build attempt should use: the one-build accordion override if the
## player picked one, else the standing setting. Legacy "ask" resolves to "market" — the modal is
## retired, so a build never blocks waiting for a choice (the accordion is where the choice is made
## now). Clears the one-build override so it applies exactly once.
func consume_build_material_source() -> String:
	var src := pending_build_material_source if pending_build_material_source != "" else construct_material_source
	pending_build_material_source = ""
	if src == "ask" or src == "":
		src = "market"
	return src

func set_construct_material_source(value: String, emit_change: bool = true) -> void:
	var resolved := value.to_lower().strip_edges()
	if resolved not in ["ask", "market", "same_tile", "any_tile"]:
		resolved = "market"
	if construct_material_source == resolved:
		return
	construct_material_source = resolved
	if emit_change:
		construct_settings_changed.emit()

func set_construct_output_destination(value: String, emit_change: bool = true) -> void:
	var resolved := value.to_lower().strip_edges()
	if resolved not in ["market", "same_tile"]:
		resolved = "market"
	if construct_output_destination == resolved:
		return
	construct_output_destination = resolved
	if emit_change:
		construct_settings_changed.emit()

## `category` is "coal_gas" or "wind_solar"; `priority` is "self" or "grid" — see
## the vars' own comment. Applies live (no per-instance capture), so nothing else
## needs to touch existing buildings when this changes.
func set_power_priority(category: String, priority: String, emit_change: bool = true) -> void:
	var resolved := priority.to_lower().strip_edges()
	if resolved not in ["self", "grid"]:
		return
	if category == "coal_gas":
		if power_priority_coal_gas == resolved:
			return
		power_priority_coal_gas = resolved
	elif category == "wind_solar":
		if power_priority_wind_solar == resolved:
			return
		power_priority_wind_solar = resolved
	else:
		return
	if emit_change:
		power_priority_changed.emit()

## "self" or "grid" for the given category ("coal_gas" / "wind_solar"); "self" for
## anything else (e.g. hydro, or a non-power building) — this feature's priority
## only ever gates generation EconomyConfig.power_priority_category() actually
## names, so "no category" must never be read as "sells to the grid".
func power_priority_for(category: String) -> String:
	if category == "coal_gas":
		return power_priority_coal_gas
	if category == "wind_solar":
		return power_priority_wind_solar
	return "self"

## Multiplier applied only to a new building's first successful operating turn.
## It is stored on the instance, so changing the default later cannot alter an
## already-started project or a completed building.
func startup_capacity_multiplier(building: Dictionary) -> float:
	return 0.5 if bool(building.get("startup_half_capacity", false)) else 1.0

func consume_startup_capacity(instance_id: String) -> void:
	if instance_id == "" or not buildings.has(instance_id):
		return
	buildings[instance_id].erase("startup_half_capacity")

func set_route_objective(objective: int) -> void:
	if objective == route_objective:
		return
	route_objective = objective
	route_objective_changed.emit(objective)

func begin_output_stockpile_selection(instance_id: String, good_id: String, allow_split: bool = true) -> void:
	if instance_id == "" or good_id == "":
		return
	pending_output_stockpile_selection = {
		"instance_id": instance_id,
		"good_id": good_id,
		"allow_split": allow_split,
	}
	output_stockpile_selection_started.emit(pending_output_stockpile_selection.duplicate())

func cancel_output_stockpile_selection() -> void:
	if pending_output_stockpile_selection.is_empty():
		return
	pending_output_stockpile_selection.clear()
	output_stockpile_selection_cancelled.emit()

# Destinations are stored PER OUTPUT GOOD so a multi-output building (e.g. a
# chlor-alkali plant making chlorine + sodium hydroxide + hydrogen) can route each
# output independently. Shape: instance_id -> { good_id -> tile_id|MARKET_DESTINATION }.
func set_output_stockpile_destination(instance_id: String, tile_id: String, good_id: String) -> void:
	if instance_id == "" or tile_id == "" or good_id == "":
		return
	var per_good: Dictionary = output_stockpile_destinations.get(instance_id, {})
	per_good[good_id] = tile_id
	output_stockpile_destinations[instance_id] = per_good
	_clear_output_split_destinations(instance_id, good_id)
	_clear_output_special_order_tag(instance_id, good_id)
	set_output_ship_quantity(instance_id, good_id, 0)  # plain routing ships ALL; a cap is set explicitly after
	pending_output_stockpile_selection.clear()
	output_stockpile_destination_changed.emit(instance_id, tile_id, good_id)

# Cap how much of `good_id` ships to the explicit destination each turn (the CTRL+click
# "send a specific amount" flow). qty <= 0 clears the cap (ship everything).
func set_output_ship_quantity(instance_id: String, good_id: String, qty: int) -> void:
	if instance_id == "" or good_id == "":
		return
	var per_good: Dictionary = output_ship_quantities.get(instance_id, {})
	if qty <= 0:
		per_good.erase(good_id)
	else:
		per_good[good_id] = qty
	if per_good.is_empty():
		output_ship_quantities.erase(instance_id)
	else:
		output_ship_quantities[instance_id] = per_good

func get_output_ship_quantity(instance_id: String, good_id: String) -> int:
	return int((output_ship_quantities.get(instance_id, {}) as Dictionary).get(good_id, 0))

func clear_output_stockpile_destination(instance_id: String, good_id: String = "") -> void:
	if instance_id == "":
		return
	if good_id == "":
		output_stockpile_destinations.erase(instance_id)  # clear the whole building
		output_split_destinations.erase(instance_id)
		output_special_order_destinations.erase(instance_id)
		output_ship_quantities.erase(instance_id)
		return
	var per_good: Dictionary = output_stockpile_destinations.get(instance_id, {})
	per_good.erase(good_id)
	if per_good.is_empty():
		output_stockpile_destinations.erase(instance_id)
	else:
		output_stockpile_destinations[instance_id] = per_good
	set_output_ship_quantity(instance_id, good_id, 0)
	_clear_output_split_destinations(instance_id, good_id)
	_clear_output_special_order_tag(instance_id, good_id)

func get_output_stockpile_destination(instance_id: String, good_id: String = "") -> String:
	var split := get_output_split_destinations(instance_id, good_id)
	if not split.is_empty():
		return str((split[0] as Dictionary).get("tile_id", ""))
	var per_good: Dictionary = output_stockpile_destinations.get(instance_id, {})
	if per_good.is_empty():
		return ""
	var tile_id := ""
	if good_id != "":
		tile_id = str(per_good.get(good_id, ""))
	elif per_good.size() == 1:
		tile_id = str(per_good.values()[0])  # unambiguous single-output building
	if tile_id == "" or tile_id == MARKET_DESTINATION:
		return ""  # unset, or a market route (not a stockpile tile)
	return tile_id

# Returns the selected destinations for a split route in selection order. A single
# destination remains a legacy route, so callers only split production when this has
# two or three entries.
func get_output_split_destinations(instance_id: String, good_id: String) -> Array:
	if instance_id == "" or good_id == "":
		return []
	var per_good: Dictionary = output_split_destinations.get(instance_id, {})
	var raw: Array = per_good.get(good_id, [])
	var destinations: Array = []
	for item in raw:
		if not (item is Dictionary):
			continue
		var tile_id := str(item.get("tile_id", ""))
		if tile_id == "" or tile_id == MARKET_DESTINATION:
			continue
		destinations.append({"tile_id": tile_id, "qty": clampi(int(item.get("qty", 0)), 0, 999)})
	return destinations

func add_output_split_destination(instance_id: String, good_id: String, tile_id: String) -> int:
	if instance_id == "" or good_id == "" or tile_id == "":
		return get_output_split_destinations(instance_id, good_id).size()
	var destinations := get_output_split_destinations(instance_id, good_id)
	for item in destinations:
		if str((item as Dictionary).get("tile_id", "")) == tile_id:
			return destinations.size()
	if destinations.size() >= 3:
		return destinations.size()
	# The first Shift-click starts a new split selection, replacing the old route.
	if destinations.is_empty():
		var legacy: Dictionary = output_stockpile_destinations.get(instance_id, {})
		legacy.erase(good_id)
		if legacy.is_empty():
			output_stockpile_destinations.erase(instance_id)
		else:
			output_stockpile_destinations[instance_id] = legacy
		set_output_ship_quantity(instance_id, good_id, 0)
		_clear_output_special_order_tag(instance_id, good_id)
	destinations.append({"tile_id": tile_id, "qty": 0})
	var per_good: Dictionary = output_split_destinations.get(instance_id, {})
	per_good[good_id] = destinations
	output_split_destinations[instance_id] = per_good
	output_stockpile_destination_changed.emit(instance_id, tile_id, good_id)
	return destinations.size()

func set_output_split_quantity(instance_id: String, good_id: String, tile_id: String, qty: int) -> void:
	var destinations := get_output_split_destinations(instance_id, good_id)
	var changed := false
	for item in destinations:
		if str((item as Dictionary).get("tile_id", "")) == tile_id:
			item["qty"] = clampi(qty, 0, 999)
			changed = true
			break
	if not changed:
		return
	var per_good: Dictionary = output_split_destinations.get(instance_id, {})
	per_good[good_id] = destinations
	output_split_destinations[instance_id] = per_good
	output_stockpile_destination_changed.emit(instance_id, tile_id, good_id)

func _clear_output_split_destinations(instance_id: String, good_id: String = "") -> void:
	if good_id == "":
		output_split_destinations.erase(instance_id)
		return
	var per_good: Dictionary = output_split_destinations.get(instance_id, {})
	per_good.erase(good_id)
	if per_good.is_empty():
		output_split_destinations.erase(instance_id)
	else:
		output_split_destinations[instance_id] = per_good

## True when ANY destination is recorded for this building+good — including a market route,
## which get_output_stockpile_destination() reports as "" because it isn't a stockpile tile.
## Construction uses this so completing a build defaults the route without overwriting a
## choice the player already made while it was under construction.
func has_output_destination(instance_id: String, good_id: String) -> bool:
	if instance_id == "" or good_id == "":
		return false
	return not get_output_split_destinations(instance_id, good_id).is_empty() \
		or str((output_stockpile_destinations.get(instance_id, {}) as Dictionary).get(good_id, "")) != ""

func route_output_to_market(instance_id: String, good_id: String) -> void:
	# Per-building, per-good "send output to market" — does NOT touch global sell_mode.
	if instance_id == "" or good_id == "":
		return
	var per_good: Dictionary = output_stockpile_destinations.get(instance_id, {})
	per_good[good_id] = MARKET_DESTINATION
	output_stockpile_destinations[instance_id] = per_good
	_clear_output_split_destinations(instance_id, good_id)
	set_output_ship_quantity(instance_id, good_id, 0)
	_clear_output_special_order_tag(instance_id, good_id)
	pending_output_stockpile_selection.clear()
	output_stockpile_destination_changed.emit(instance_id, MARKET_DESTINATION, good_id)

func route_output_to_special_order(instance_id: String, good_id: String, special_order_id: String) -> void:
	if instance_id == "" or good_id == "" or special_order_id == "":
		return
	var order := SpecialOrderState.get_order(special_order_id)
	if order.is_empty() or str(order.get("good_id", "")) != good_id:
		return
	var per_good: Dictionary = output_stockpile_destinations.get(instance_id, {})
	per_good[good_id] = MARKET_DESTINATION
	output_stockpile_destinations[instance_id] = per_good
	_clear_output_split_destinations(instance_id, good_id)
	var per_order: Dictionary = output_special_order_destinations.get(instance_id, {})
	per_order[good_id] = special_order_id
	output_special_order_destinations[instance_id] = per_order
	pending_output_stockpile_selection.clear()
	output_stockpile_destination_changed.emit(instance_id, MARKET_DESTINATION, good_id)

func is_output_market(instance_id: String, good_id: String = "") -> bool:
	var per_good: Dictionary = output_stockpile_destinations.get(instance_id, {})
	if per_good.is_empty():
		return false
	if good_id != "":
		return str(per_good.get(good_id, "")) == MARKET_DESTINATION
	for v in per_good.values():
		if str(v) == MARKET_DESTINATION:
			return true
	return false

func get_output_special_order_id(instance_id: String, good_id: String = "") -> String:
	var per_good: Dictionary = output_special_order_destinations.get(instance_id, {})
	if per_good.is_empty():
		return ""
	if good_id != "":
		return str(per_good.get(good_id, ""))
	if per_good.size() == 1:
		return str(per_good.values()[0])
	return ""

func is_output_special_order(instance_id: String, good_id: String = "") -> bool:
	return get_output_special_order_id(instance_id, good_id) != ""

func _clear_output_special_order_tag(instance_id: String, good_id: String = "") -> void:
	if instance_id == "":
		return
	if good_id == "":
		output_special_order_destinations.erase(instance_id)
		return
	var per_order: Dictionary = output_special_order_destinations.get(instance_id, {})
	if per_order.is_empty():
		return
	per_order.erase(good_id)
	if per_order.is_empty():
		output_special_order_destinations.erase(instance_id)
	else:
		output_special_order_destinations[instance_id] = per_order

func queue_stockpile_market_sale(tile_id: String) -> void:
	if tile_id == "":
		return
	queued_stockpile_market_sales[tile_id] = true
	stockpile_market_sale_queue_changed.emit(tile_id)

func clear_stockpile_market_sale_queue(tile_id: String) -> void:
	if tile_id == "":
		return
	if queued_stockpile_market_sales.erase(tile_id):
		stockpile_market_sale_queue_changed.emit(tile_id)

func is_stockpile_market_sale_queued(tile_id: String) -> bool:
	return queued_stockpile_market_sales.has(tile_id)

func consume_queued_stockpile_market_sales() -> Array:
	var queued_tiles: Array = queued_stockpile_market_sales.keys()
	queued_stockpile_market_sales.clear()
	for tile_id in queued_tiles:
		stockpile_market_sale_queue_changed.emit(str(tile_id))
	return queued_tiles

func emit_stockpile_market_sale_completed(sale_record: Dictionary) -> void:
	stockpile_market_sale_completed.emit(sale_record)

## Running total of market purchases that are in transit and NOT yet paid for. Kept as an
## accumulator rather than summed over pending_transport_shipments on every order, because
## a busy turn places many orders and the shipment list is a known sim hot-spot. Rebuilt
## from the shipment list on load (_recompute_unpaid_purchases) so it can't drift.
var _unpaid_purchase_total: float = 0.0

## What a new market purchase may still commit: cash on hand, PLUS what the player could
## still borrow, MINUS purchases already in transit that haven't been paid for yet.
## Pay-on-arrival (owner ruling 2026-07-27) means an order may legitimately push the balance
## negative — the auto-bridge loan is what catches that. The line it must not cross is the
## point where the debt could no longer be financed at all. Because in-transit commitments
## are subtracted, orders placed in the same turn resolve SEQUENTIALLY: each one consumes
## the headroom the next is measured against, so a big order fails without blocking the
## small ones behind it.
func purchase_headroom() -> float:
	return money + maxf(0.0, LoanState.available_capacity()) - _unpaid_purchase_total

func unpaid_purchase_total() -> float:
	return _unpaid_purchase_total

## Cash leaves when the goods land. Called once per arriving purchase shipment.
func settle_arrived_purchase(cost: float) -> void:
	if cost <= 0.0:
		return
	add_money(-cost)
	_unpaid_purchase_total = maxf(0.0, _unpaid_purchase_total - cost)

func _recompute_unpaid_purchases() -> void:
	var total := 0.0
	for shipment in pending_transport_shipments:
		total += float((shipment as Dictionary).get("purchase_cost", 0.0))
	_unpaid_purchase_total = total

func queue_transport_shipment(shipment: Dictionary) -> void:
	var s := shipment.duplicate(true)
	if not s.has("id"):
		_shipment_id_counter += 1
		s["id"] = _shipment_id_counter  # stable id so the overlay can track it across turns
	pending_transport_shipments.append(s)
	_note_shipment_congestion(s)
	transport_shipments_changed.emit()

## Book the congestion share of a real shipment's freight against the link that caused
## it. Done HERE, at the one funnel every committed shipment passes through, rather than
## in transport_cost_for_route — that function is shared with quotes, previews and the
## build forecast, so attributing there would count charges the player never paid (the
## same trap land_cost_after_credit's `commit` flag exists to avoid).
##
## The surcharge is recovered from the multiplier the cost was priced with: only the
## units past the binding link's headroom pay it, so mult = (within + over*rate)/qty and
## the surcharge share of the final cost is (1 - 1/mult).
func _note_shipment_congestion(s: Dictionary) -> void:
	var cost := float(s.get("transport_cost", 0.0))
	if cost <= 0.0:
		return
	var qty := _shipment_total_units(s)
	if qty <= 0:
		return
	var cong := route_congestion({"tiles": s.get("tiles", []), "legs": s.get("legs", [])})
	var tier := int(cong.get("tier", 0))
	var key := str(cong.get("key", ""))
	if tier <= 0 or key == "":
		return
	var rate: float = 2.0 if tier == 1 else 3.0
	var over: int = maxi(0, qty - int(cong.get("headroom", 0)))
	var mult := (float(qty - over) + float(over) * rate) / float(qty)
	if mult <= 1.0:
		return
	note_congestion_surcharge(key, cost * (1.0 - 1.0 / mult))

func request_toast(message: String, toast_type: String = "success") -> void:
	toast_requested.emit(message, toast_type)

func queue_move(source_tile: String, dest_tile: String, goods_qtys: Dictionary, log_oneoff: bool = true, extra: Dictionary = {}) -> Dictionary:
	# Move goods from one tile to another: quote first, then consume only goods with a
	# legal route. Pipe-only goods must never vanish into an impossible fallback route.
	if source_tile == "" or dest_tile == "" or source_tile == dest_tile:
		return {}
	var manifest: Dictionary = {}
	var requested_qty := 0
	for good_id in goods_qtys.keys():
		var want := int(goods_qtys[good_id])
		if want <= 0:
			continue
		var available := mini(want, Stockpile.get_at_tile(source_tile, str(good_id)))
		if available <= 0:
			continue
		requested_qty += available
		manifest[str(good_id)] = int(manifest.get(str(good_id), 0)) + available
	if manifest.is_empty():
		return {}
	var surcharge := LARGE_SHIPMENT_SURCHARGE if requested_qty > LARGE_SHIPMENT_THRESHOLD else 1.0
	var quote := TransportService.quote_manifest(source_tile, dest_tile, manifest, {"surcharge": surcharge})
	if quote.is_empty():
		return {}
	var items: Array = []
	var total_qty := 0
	var total_cost := 0.0
	var turns := 0
	for quoted in quote.get("items", []):
		var it: Dictionary = quoted
		var good_key := str(it.get("good_id", ""))
		var quoted_qty := int(it.get("qty", 0))
		if good_key == "" or quoted_qty <= 0:
			continue
		var moved := Stockpile.consume(source_tile, good_key, quoted_qty)
		if moved <= 0:
			continue
		var item := it.duplicate(true)
		if moved != quoted_qty:
			item["qty"] = moved
			item["cost"] = float(it.get("cost", 0.0)) * (float(moved) / float(maxi(quoted_qty, 1)))
		items.append(item)
		total_qty += moved
		total_cost += float(item.get("cost", 0.0))
		turns = maxi(turns, int(item.get("turns", quote.get("turns", 0))))
	if items.is_empty():
		return {}
	if total_cost > 0.0:
		add_money(-total_cost)
	for it in items:
		var item_route: Dictionary = it.get("route", quote.get("route", {}))
		var item_turns := int(it.get("turns", turns))
		if item_turns >= 1:
			var shipment: Dictionary = {
				"source_tile": source_tile,
				"destination_tile": dest_tile,
				"good_id": it.good_id,
				"qty": it.qty,
				"turns_remaining": item_turns,
				"transport_turns": item_turns,
				"transport_cost": it.cost,
				"tiles": item_route.get("tiles", []),
				"path": item_route.get("path", []),
				"legs": item_route.get("legs", []),
			}
			shipment.merge(extra, true)  # optional tags, e.g. construction_instance_id
			queue_transport_shipment(shipment)
		else:
			Stockpile.add(dest_tile, it.good_id, it.qty)
	if log_oneoff:
		for it in items:
			log_move_shipment(source_tile, dest_tile, str(it.good_id), int(it.qty), turns)
	# Victory feed: a tile-to-tile move is one goods movement (manifest counts once).
	# Moves never break the Autarkic streak (you may relocate your own goods freely).
	goods_movement_recorded.emit("move", "", turns)
	return {"items": items, "total_qty": total_qty, "turns": turns,
		"cost": total_cost, "source": source_tile, "dest": dest_tile, "surcharged": surcharge > 1.0}

func preview_move(source_tile: String, dest_tile: String, goods_qtys: Dictionary) -> Dictionary:
	# Cost/turns for a move WITHOUT consuming — used to populate the large-shipment dialog.
	var manifest: Dictionary = {}
	var total_qty := 0
	for good_id in goods_qtys.keys():
		var qty := mini(int(goods_qtys[good_id]), Stockpile.get_at_tile(source_tile, str(good_id)))
		if qty > 0:
			manifest[str(good_id)] = qty
			total_qty += qty
	var surcharge := LARGE_SHIPMENT_SURCHARGE if total_qty > LARGE_SHIPMENT_THRESHOLD else 1.0
	var quote := TransportService.quote_manifest(source_tile, dest_tile, manifest, {"surcharge": surcharge})
	if quote.is_empty():
		return {"turns": 0, "cost": 0.0, "total_qty": 0, "per_turn": 0.0, "surcharged": surcharge > 1.0}
	var turns: int = int(quote.get("turns", 0))
	var total_cost := float(quote.get("cost", 0.0))
	return {"turns": turns, "cost": total_cost, "total_qty": int(quote.get("total_qty", 0)),
		"per_turn": total_cost / float(maxi(turns, 1)), "surcharged": surcharge > 1.0}

func add_recurring_move(source_tile: String, dest_tile: String, goods_qtys: Dictionary) -> void:
	recurring_moves.append({"source": source_tile, "dest": dest_tile, "goods": goods_qtys.duplicate(true), "turn_started": _ledger_turn()})
	recurring_orders_changed.emit()

# --- Cancel recurring orders (Market panel Movements/Sales tabs). Erase-by-value: the
# UI holds the exact entry dict, so this removes that standing order. ------------------
func remove_recurring_move(entry: Dictionary) -> bool:
	if not recurring_moves.has(entry):
		return false
	recurring_moves.erase(entry)
	recurring_orders_changed.emit()
	return true

func remove_recurring_sell(entry: Dictionary) -> bool:
	if not recurring_sells.has(entry):
		return false
	recurring_sells.erase(entry)
	recurring_orders_changed.emit()
	return true

func remove_recurring_bulk_sell(entry: Dictionary) -> bool:
	if not recurring_bulk_sells.has(entry):
		return false
	recurring_bulk_sells.erase(entry)
	recurring_orders_changed.emit()
	return true

func add_scheduled_move(source_tile: String, dest_tile: String, goods_qtys: Dictionary) -> void:
	scheduled_moves.append({"source": source_tile, "dest": dest_tile, "goods": goods_qtys.duplicate(true)})

func run_recurring_and_scheduled_moves() -> void:
	# Fire one-shot scheduled moves (e.g. the split second half) then re-issue recurring moves.
	var due: Array = scheduled_moves
	scheduled_moves = []
	for m in due:
		queue_move(str(m.source), str(m.dest), m.goods, true)  # split second-half = a one-off
	for m in recurring_moves:
		queue_move(str(m.source), str(m.dest), m.goods, false)
	for m in recurring_sells:
		_run_recurring_sell(m)
	for r in recurring_bulk_sells:
		sell_all_to_market(r.get("params", {}), false)

func _run_recurring_sell(entry: Dictionary) -> void:
	# Sell the configured qty of each good every turn, drawing from the bound source
	# tile first and then any other tile that holds the good. This keeps "sell N coal
	# every turn" working even after the source tile is drained — the produced coal
	# now sits on the mine tiles, not the tile the order was created from.
	var source := str(entry.get("source", ""))
	var goods: Dictionary = entry.get("goods", {})
	for good_id in goods.keys():
		var remaining := int(goods[good_id])
		if remaining <= 0:
			continue
		# Ordered draw list: source tile first, then other tiles holding the good.
		var draw_tiles: Array = []
		if source != "" and Stockpile.get_at_tile(source, str(good_id)) > 0:
			draw_tiles.append(source)
		for t in Stockpile.tiles_with_stock():
			var ts := str(t)
			if ts == source or not ts.begins_with("tile_"):
				continue
			if Stockpile.get_at_tile(ts, str(good_id)) > 0:
				draw_tiles.append(ts)
		for t in draw_tiles:
			if remaining <= 0:
				break
			var avail := Stockpile.get_at_tile(str(t), str(good_id))
			var take: int = mini(remaining, avail)
			if take <= 0:
				continue
			queue_sell(str(t), {good_id: take}, false)
			remaining -= take

func add_recurring_sell(source_tile: String, goods_qtys: Dictionary) -> void:
	recurring_sells.append({"source": source_tile, "goods": goods_qtys.duplicate(true), "turn_started": _ledger_turn()})
	recurring_orders_changed.emit()

func add_recurring_bulk_sell(params: Dictionary) -> void:
	recurring_bulk_sells.append({"params": params.duplicate(true), "turn_started": _ledger_turn()})
	recurring_orders_changed.emit()

func add_recurring_buy(dest_tile: String, good_id: String, qty: int) -> void:
	recurring_buys.append({"dest": dest_tile, "good": good_id, "qty": qty, "turn_started": _ledger_turn()})

# --- Ledger helpers for the Transactions / Movements tabs ---

func _ledger_turn() -> int:
	return int(TurnManager.current_turn) if TurnManager else 0

func _log_transaction(entry: Dictionary) -> void:
	transaction_log.append(entry)
	if transaction_log.size() > LEDGER_MAX:
		transaction_log = transaction_log.slice(transaction_log.size() - LEDGER_MAX)

func _log_move(entry: Dictionary) -> void:
	move_log.append(entry)
	if move_log.size() > LEDGER_MAX:
		move_log = move_log.slice(move_log.size() - LEDGER_MAX)

func log_market_sale(source_tile: String, port_tile: String, good_id: String, qty: int, turns: int) -> void:
	# Production calls this when output / stockpile sells to market, so the ledger reflects it.
	if qty <= 0:
		return
	var started := _ledger_turn()
	_log_transaction({
		"kind": "sell", "good_id": str(good_id), "qty": int(qty),
		"tile_from": source_tile, "tile_to": port_tile if port_tile != "" else "Market",
		"turn_started": started, "turn_ended": started + maxi(0, turns),
	})

func log_move_shipment(source_tile: String, dest_tile: String, good_id: String, qty: int, turns: int) -> void:
	# Production calls this when output is routed to ANOTHER tile's stockpile (a tile-to-tile move).
	if qty <= 0:
		return
	var started := _ledger_turn()
	_log_move({
		"good_id": str(good_id), "qty": int(qty),
		"tile_from": source_tile, "tile_to": dest_tile,
		"turn_started": started, "turn_ended": started + maxi(0, turns),
	})

func _ledger_tile_label(tile_id: String) -> String:
	if tile_id == "":
		return "—"
	if tile_id.begins_with("tile_"):
		return Catalog.tile_label(tile_id)
	return tile_id  # e.g. "Market", "All tiles"

func _txn_row(kind: String, good: String, qty: int, tile_from: String, tile_to: String, started: int, ended: int) -> Dictionary:
	return {
		"type": "Buy" if kind == "buy" else "Sell",
		"from": _ledger_tile_label(tile_from), "to": _ledger_tile_label(tile_to),
		"good": good, "qty": qty, "turn_started": started, "turn_ended": ended,
	}

func _move_row(good: String, qty: int, tile_from: String, tile_to: String, started: int, ended: int) -> Dictionary:
	return {
		"type": "Move", "from": _ledger_tile_label(tile_from), "to": _ledger_tile_label(tile_to),
		"good": good, "qty": qty, "turn_started": started, "turn_ended": ended,
	}

func _input_key(instance_id: String, good_id: String) -> String:
	return instance_id + "|" + good_id

func set_input_tile_only(instance_id: String, good_id: String, tile_only: bool) -> void:
	# Default (not set) = "stockpile then market" (buys the shortfall). tile_only = never buy.
	if instance_id == "" or good_id == "":
		return
	if tile_only:
		input_tile_only[_input_key(instance_id, good_id)] = true
	else:
		input_tile_only.erase(_input_key(instance_id, good_id))

func is_input_tile_only(instance_id: String, good_id: String) -> bool:
	return bool(input_tile_only.get(_input_key(instance_id, good_id), false))

# --- Seaport subscriptions and sea freight ---
# A subscribed good transfers through a seaport in one turn. Its cost is charged when it
# actually ships, rather than as the old standing subscription fee.
var seaport_auto_subscribe: bool = false
var seaport_subscribed: Dictionary = {}
var _sea_shipping_turn: int = -1
var _sea_port_usage_this_turn: Dictionary = {} # port tile -> transport class -> units
var _sea_port_charges_this_turn: Dictionary = {} # port tile -> good -> charge breakdown
# The port panel shows the latest completed traffic when a fresh turn has no
# bookings yet. Keep this separate from the live ledgers: throughput quotes must
# always start at zero on a new turn.
var _last_sea_shipping_turn: int = -1
var _last_sea_port_usage: Dictionary = {}
var _last_sea_port_charges: Dictionary = {}

func seaport_covers(good_id: String) -> bool:
	if seaport_auto_subscribe:
		seaport_subscribed[good_id] = true
		return true
	return seaport_subscribed.has(good_id)

func seaport_would_cover(good_id: String) -> bool:
	return seaport_auto_subscribe or seaport_subscribed.has(good_id)

func subscribe_seaport(good_id: String) -> void:
	seaport_subscribed[good_id] = true

func seaport_subscription_fee() -> float:
	return 0.0

func _ensure_sea_shipping_turn() -> void:
	var turn := int(TurnManager.current_turn) if TurnManager != null else 1
	if turn == _sea_shipping_turn:
		return
	if _sea_shipping_turn >= 0 and not _sea_port_charges_this_turn.is_empty():
		_last_sea_shipping_turn = _sea_shipping_turn
		_last_sea_port_usage = _sea_port_usage_this_turn.duplicate(true)
		_last_sea_port_charges = _sea_port_charges_this_turn.duplicate(true)
	_sea_shipping_turn = turn
	_sea_port_usage_this_turn.clear()
	_sea_port_charges_this_turn.clear()

func sea_shipping_growth_factor() -> float:
	var turn := int(TurnManager.current_turn) if TurnManager != null else 1
	return pow(1.0 + EconomyConfig.SEAPORT_FEE_GROWTH_PER_TURN, maxf(0.0, float(turn - 1)))

func seaport_throughput_cap(good_id: String) -> int:
	var transport_class := Catalog.get_transport_class(good_id)
	var base := EconomyConfig.SEAPORT_THROUGHPUT_RESTRICTED if EconomyConfig.SEAPORT_RESTRICTED_TRANSPORT_CLASSES.has(transport_class) else EconomyConfig.SEAPORT_THROUGHPUT_STANDARD
	return maxi(1, int(round(Modifiers.apply("port_throughput", "port", float(base), {"transport_class": transport_class}))))

func seaport_base_fee(port_tile: String) -> float:
	if is_seaport_player_owned(port_tile):
		return 0.0
	return maxf(0.0, Modifiers.apply("port_per_turn_fee", "port", EconomyConfig.SEAPORT_BASE_FEE_PER_GOOD))

func seaport_insurance_rate(port_tile: String) -> float:
	# Turn-scheduled ad valorem: cheap while the player is learning, real from t31. Owning the
	# port still halves it. Research relief rides the same port_ad_valorem_fee domain.
	var base := EconomyConfig.seaport_ad_valorem_rate(TurnManager.current_turn)
	if is_seaport_player_owned(port_tile):
		base *= EconomyConfig.OWNED_SEAPORT_AD_VALOREM_SHARE
	return maxf(0.0, Modifiers.apply("port_ad_valorem_fee", "port", base))

func is_seaport_player_owned(port_tile: String) -> bool:
	if port_tile == "":
		return false
	for building in get_buildings_on_tile(port_tile):
		if str(building.get("building_id", "")) == "b_004" and is_player_owned(building):
			return true
	return false

func _owned_port_count() -> int:
	var count := 0
	for building in buildings.values():
		if str(building.get("building_id", "")) == "b_004" and is_player_owned(building):
			count += 1
	return count

func preview_sea_shipping(port_tile: String, good_id: String, qty: int) -> Dictionary:
	if port_tile == "" or good_id == "" or qty <= 0:
		return {}
	_ensure_sea_shipping_turn()
	var transport_class := Catalog.get_transport_class(good_id)
	var cap := seaport_throughput_cap(good_id)
	var usage: Dictionary = _sea_port_usage_this_turn.get(port_tile, {})
	var used_before := int(usage.get(transport_class, 0))
	var projected := used_before + qty
	# This is a soft throughput cap: traffic can still pass, but the whole shipment costs double.
	var at_cap := projected >= cap
	var surcharge := 2.0 if at_cap else 1.0
	var owned := is_seaport_player_owned(port_tile)
	var existing_goods: Dictionary = _sea_port_charges_this_turn.get(port_tile, {})
	var first_shipment_of_good := not existing_goods.has(good_id)
	var growth := sea_shipping_growth_factor()
	var fixed_fee := seaport_base_fee(port_tile) * growth * surcharge if (not owned and first_shipment_of_good) else 0.0
	var insurance_rate := seaport_insurance_rate(port_tile)
	var insured_value := float(qty) * MarketState.get_buy_price(good_id)
	var insurance_fee := insured_value * insurance_rate * growth * surcharge
	return {
		"port": port_tile, "good_id": good_id, "qty": qty, "transport_class": transport_class,
		"capacity": cap, "used_before": used_before, "projected_usage": projected,
		"at_cap": at_cap, "surcharge": surcharge, "owned": owned, "growth": growth,
		"base_fee": fixed_fee, "insurance_fee": insurance_fee, "total": fixed_fee + insurance_fee,
	}

func commit_sea_shipping(port_tile: String, good_id: String, qty: int, direction: String) -> Dictionary:
	var charge := preview_sea_shipping(port_tile, good_id, qty)
	if charge.is_empty():
		return charge
	var transport_class := str(charge.get("transport_class", ""))
	var usage: Dictionary = _sea_port_usage_this_turn.get(port_tile, {}).duplicate()
	usage[transport_class] = int(charge.get("projected_usage", qty))
	_sea_port_usage_this_turn[port_tile] = usage
	var by_good: Dictionary = _sea_port_charges_this_turn.get(port_tile, {}).duplicate(true)
	var row: Dictionary = by_good.get(good_id, {
		"good_id": good_id, "buy_qty": 0, "sell_qty": 0, "total_qty": 0,
		"base_fee": 0.0, "insurance_fee": 0.0, "total": 0.0,
		"transport_class": transport_class, "capacity": int(charge.get("capacity", 0)), "at_cap": false,
	})
	if direction == "sell":
		row["sell_qty"] = int(row.get("sell_qty", 0)) + qty
		_port_sale_total += qty
		_port_sales_by_class[transport_class] = int(_port_sales_by_class.get(transport_class, 0)) + qty
		_port_sales_by_port[port_tile] = int(_port_sales_by_port.get(port_tile, 0)) + qty
	else:
		row["buy_qty"] = int(row.get("buy_qty", 0)) + qty
	row["total_qty"] = int(row.get("total_qty", 0)) + qty
	row["base_fee"] = float(row.get("base_fee", 0.0)) + float(charge.get("base_fee", 0.0))
	row["insurance_fee"] = float(row.get("insurance_fee", 0.0)) + float(charge.get("insurance_fee", 0.0))
	row["total"] = float(row.get("total", 0.0)) + float(charge.get("total", 0.0))
	row["at_cap"] = bool(row.get("at_cap", false)) or bool(charge.get("at_cap", false))
	by_good[good_id] = row
	_sea_port_charges_this_turn[port_tile] = by_good
	if direction == "sell":
		# One large manifest may contain many goods.  Its port-sale totals are
		# accumulated immediately, but research reads them once in NARRATIVE.
		_mark_research_progress_dirty()
	transport_shipments_changed.emit() # Refresh the open port readout after a shipment is booked.
	return charge

func seaport_shipping_summary(port_tile: String) -> Dictionary:
	_ensure_sea_shipping_turn()
	var current_rows: Dictionary = _sea_port_charges_this_turn.get(port_tile, {})
	var use_latest_completed_turn := current_rows.is_empty()
	var source_rows: Dictionary = _last_sea_port_charges.get(port_tile, {}) if use_latest_completed_turn else current_rows
	var source_usage: Dictionary = _last_sea_port_usage.get(port_tile, {}) if use_latest_completed_turn else _sea_port_usage_this_turn.get(port_tile, {})
	var rows: Array = []
	for row in source_rows.values():
		rows.append((row as Dictionary).duplicate(true))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return Catalog.get_display_name(str(a.get("good_id", ""))) < Catalog.get_display_name(str(b.get("good_id", ""))))
	var owned := is_seaport_player_owned(port_tile)
	return {
		"owned": owned, "growth": sea_shipping_growth_factor(),
		"base_fee": seaport_base_fee(port_tile),
		"insurance_rate": seaport_insurance_rate(port_tile),
		"usage": source_usage.duplicate(),
		"activity_turn": _last_sea_shipping_turn if use_latest_completed_turn else _sea_shipping_turn,
		"is_current_turn": not use_latest_completed_turn,
		"rows": rows,
	}

func queue_buy(dest_tile: String, good_id: String, qty: int, log_oneoff: bool = true, extra: Dictionary = {}) -> Dictionary:
	# Buy goods from the nearest port to dest_tile: pay now (price + transport), ship in,
	# arrive in N turns. The reusable buy primitive for market-sourced inputs (and later a Buy tab).
	if dest_tile == "" or good_id == "" or qty <= 0:
		return {}
	# An import prohibition is enforced HERE because every purchase route funnels
	# through this primitive: automated market top-up, recurring buys, construction
	# and upgrade materials, and the manual buy. One guard closes all of them.
	if PolicyState.import_banned(good_id, TurnManager.current_turn):
		return {}
	var covered := seaport_covers(good_id)
	var quote := TransportService.quote_market_buy(dest_tile, good_id, qty, covered)
	if quote.is_empty():
		return {}
	var port := str(quote.get("port", ""))
	var route: Dictionary = quote.get("route", {})
	var turns: int = int(quote.get("turns", 0))
	var unit_price := MarketState.get_buy_price(good_id)
	var transport := float(quote.get("transport_cost", 0.0))
	var total := float(quote.get("cost", 0.0))
	# Gate on the FINANCEABLE headroom, not on cash in hand — see purchase_headroom().
	var headroom := purchase_headroom()
	if total > headroom:
		# Best-effort: take as much as the headroom allows rather than nothing (avoids an
		# all-or-nothing starvation cliff when the balance dips below a full order).
		var per_unit := unit_price + transport / float(maxi(qty, 1))
		qty = mini(qty, int(floor(headroom / maxf(per_unit, 0.0001))))
		if qty <= 0:
			return {}
		quote = TransportService.quote_market_buy(dest_tile, good_id, qty, covered)
		route = quote.get("route", {})
		turns = int(quote.get("turns", 0))
		transport = float(quote.get("transport_cost", 0.0))
		total = float(quote.get("cost", 0.0))
		if total > headroom:
			return {}
	# The quote previews a mutable port-capacity charge. Commit only after the final,
	# financeable quantity is known, then reconcile in case an earlier shipment used capacity.
	var sea_quote := float(quote.get("sea_transport_cost", 0.0))
	var sea_charge := commit_sea_shipping(port, good_id, qty, "buy")
	if not sea_charge.is_empty():
		var actual_sea := float(sea_charge.get("total", 0.0))
		transport += actual_sea - sea_quote
		total += actual_sea - sea_quote
	var transport_breakdown: Dictionary = (quote.get("route_transport_breakdown", {}) as Dictionary).duplicate()
	if not sea_charge.is_empty():
		# Split by DIRECTION: this is the import leg. The ad valorem rides its own "sea" line
		# rather than being folded in, because it is the component about to carry the freight
		# redesign and needs to be watchable on its own.
		# The whole port charge, by direction. Splitting fee-from-ad-valorem left both direction
		# lines reading zero once the flat fee was retired — reported from a turn-63 save.
		transport_breakdown["port_inbound"] = float(transport_breakdown.get("port_inbound", 0.0)) \
			+ float(sea_charge.get("base_fee", 0.0)) + float(sea_charge.get("insurance_fee", 0.0))
	# Goods with a transit leg are paid for ON ARRIVAL; instant (0-turn) deliveries have no
	# transit to defer over, so they settle here.
	if turns < 1:
		add_money(-total)
	# Deficit feed: heavy player buying in one good pushes its price up (the
	# mirror of the sell-side glut) — see MarketState._tick_impact.
	MarketState.record_market_buy_volume(good_id, qty)
	if log_oneoff:
		var started := _ledger_turn()
		_log_transaction({
			"kind": "buy", "good_id": good_id, "qty": qty,
			"tile_from": port, "tile_to": dest_tile,
			"turn_started": started, "turn_ended": started + maxi(0, turns),
		})
	if turns >= 1:
		var shipment: Dictionary = {
			"source_tile": port, "destination_tile": dest_tile,
			"good_id": good_id, "qty": qty,
			"turns_remaining": turns, "transport_turns": turns,
			"transport_cost": transport, "is_purchase": true,
			# The unpaid bill rides with the goods. Production settles it on arrival and
			# books it into that turn's summary, so money_out always matches real cash.
			# Additive save field: an old save's in-flight shipments have no purchase_cost,
			# which correctly reads as "already paid for" under the old charge-on-order rule.
			"purchase_cost": total,
			"purchase_goods_cost": total - transport,
			"transport_breakdown": transport_breakdown,
			"tiles": route.get("tiles", []), "path": route.get("path", []), "legs": route.get("legs", []),
		}
		shipment.merge(extra, true)  # optional tags, e.g. construction_instance_id
		_unpaid_purchase_total += total
		queue_transport_shipment(shipment)
	else:
		Stockpile.add(dest_tile, good_id, qty)
	# Victory feed: every successful buy (including 0-turn instant deliveries) is a
	# goods movement. Category is derived from the optional tags so the Autarkic
	# track can show what broke the streak (input / building / upgrade / other).
	var buy_category := "other"
	if extra.has("construction_instance_id"):
		buy_category = "building"
	elif extra.has("upgrade_instance_id"):
		buy_category = "upgrade"
	elif str(extra.get("buy_kind", "")) != "":
		buy_category = str(extra.get("buy_kind", ""))
	goods_movement_recorded.emit("buy", buy_category, turns)
	# `deferred` tells the caller the cash has NOT left yet — Production books a deferred
	# purchase into the summary when it arrives, not here, so money_out tracks real cash.
	return {"qty": qty, "turns": turns, "cost": total, "deferred": turns >= 1,
		"goods_cost": float(qty) * unit_price, "transport_cost": transport,
		"transport_breakdown": transport_breakdown, "port": port}

func tiles_producing(good_id: String) -> Dictionary:
	var out: Dictionary = {}
	for inst in buildings.values():
		if Catalog.recipe_produces(Catalog.get_recipe(str(inst.get("recipe_id", ""))), good_id):
			out[str(inst.get("tile_id", ""))] = true
	return out

func tiles_consuming(good_id: String) -> Dictionary:
	var out: Dictionary = {}
	for inst in buildings.values():
		for input in Catalog.get_recipe(str(inst.get("recipe_id", ""))).get("inputs", []):
			if str(input.get("good_id", "")) == good_id:
				out[str(inst.get("tile_id", ""))] = true
				break
	return out

func preview_buy(dest_tile: String, good_id: String, qty: int) -> Dictionary:
	# Cost/turns for a buy WITHOUT executing — for the Purchases "Cost to buy" line.
	if dest_tile == "" or good_id == "" or qty <= 0:
		return {}
	# Mirrors the queue_buy guard so the UI never quotes a price for a purchase that
	# would be refused.
	if PolicyState.import_banned(good_id, TurnManager.current_turn):
		return {}
	var quote := TransportService.quote_market_buy(dest_tile, good_id, qty, seaport_would_cover(good_id))
	if quote.is_empty():
		return {}
	return {"cost": float(quote.get("cost", 0.0)), "goods_cost": float(quote.get("goods_cost", 0.0)),
		"transport_cost": float(quote.get("transport_cost", 0.0)), "turns": int(quote.get("turns", 0)),
		"port": str(quote.get("port", ""))}

# --- Warehouse expansion (per-tile storage upgrade paid in materials) ---

## Everything the tile panel needs to render the "Expand Warehouse" offer:
## the next level's material bill with per-good empire stock vs market cost
## (ask + freight to the tile), plus affordability flags.
func warehouse_upgrade_quote(tile_id: String) -> Dictionary:
	var level := Stockpile.get_warehouse_level(tile_id)
	var next_level := level + 1
	if tile_id == "" or not EconomyConfig.WAREHOUSE_UPGRADE_COSTS.has(next_level):
		return {"maxed": true, "level": level}
	var costs: Dictionary = EconomyConfig.WAREHOUSE_UPGRADE_COSTS[next_level]
	var materials: Array = []
	var market_total := 0.0
	var empire_ok := true
	for good_id in costs:
		var qty := int(costs[good_id])
		var have := Stockpile.get_total(str(good_id))
		var quote := TransportService.quote_market_buy(tile_id, str(good_id), qty, seaport_would_cover(str(good_id)))
		var cost := float(quote.get("cost", float(qty) * MarketState.get_buy_price(str(good_id))))
		materials.append({"good_id": str(good_id), "qty": qty, "have_empire": have, "market_cost": cost})
		market_total += cost
		if have < qty:
			empire_ok = false
	return {
		"maxed": false, "level": level, "next_level": next_level,
		"current_cap": int(EconomyConfig.WAREHOUSE_STORAGE_CAP.get(level, Stockpile.TILE_CAPACITY)),
		"next_cap": int(EconomyConfig.WAREHOUSE_STORAGE_CAP.get(next_level, Stockpile.TILE_CAPACITY)),
		"materials": materials, "market_total": market_total,
		"empire_ok": empire_ok, "money_ok": market_total <= money,
	}

## Commit the expansion. source = "market" (pay cash at ask + freight; the materials
## are consumed by the works, nothing ships) or "empire" (pull the bill from stock
## across the player's tiles). Applies immediately, like road/rail infra purchases.
func upgrade_warehouse(tile_id: String, source: String) -> Dictionary:
	var q := warehouse_upgrade_quote(tile_id)
	if bool(q.get("maxed", false)):
		return {"ok": false, "reason": "maxed"}
	var next_level := int(q.get("next_level", 0))
	var materials: Array = q.get("materials", [])
	match source:
		"market":
			var total := float(q.get("market_total", 0.0))
			if total > money:
				return {"ok": false, "reason": "money"}
			add_money(-total)
			for m in materials:
				# Deficit feed: these are real market purchases (price impact applies).
				MarketState.record_market_buy_volume(str(m.good_id), int(m.qty))
			goods_movement_recorded.emit("buy", "upgrade", 0)
		"empire":
			for m in materials:
				if Stockpile.get_total(str(m.good_id)) < int(m.qty):
					return {"ok": false, "reason": "materials"}
			for m in materials:
				Stockpile.consume_anywhere(str(m.good_id), int(m.qty))
		_:
			return {"ok": false, "reason": "unknown_source"}
	Stockpile.set_warehouse_level(tile_id, next_level)
	request_toast("Warehouse expanded to level %d — %d storage" % [next_level, int(q.get("next_cap", 0))], "success")
	return {"ok": true, "level": next_level, "capacity": int(q.get("next_cap", 0))}

func get_oneoff_transaction_rows() -> Array:
	var rows: Array = []
	for t in transaction_log:
		rows.append(_txn_row(str(t.get("kind", "sell")), Catalog.get_display_name(str(t.get("good_id", ""))),
			int(t.get("qty", 0)), str(t.get("tile_from", "")), str(t.get("tile_to", "")),
			int(t.get("turn_started", 0)), int(t.get("turn_ended", -1))))
	return rows

func get_recurring_transaction_rows() -> Array:
	var rows: Array = []
	for m in recurring_sells:
		var port := TransportService.nearest_port_tile(str(m.get("source", "")))
		for gid in m.get("goods", {}).keys():
			rows.append(_txn_row("sell", Catalog.get_display_name(str(gid)), int(m.goods[gid]),
				str(m.get("source", "")), port, int(m.get("turn_started", 0)), -1))
	for r in recurring_bulk_sells:
		var p: Dictionary = r.get("params", {})
		var good_label := "All goods" if str(p.get("good_id", "")) == "" else Catalog.get_display_name(str(p.get("good_id", "")))
		if bool(p.get("finished_only", false)):
			good_label += " (finished)"
		rows.append(_txn_row("sell", good_label, -1, "All tiles", "Market", int(r.get("turn_started", 0)), -1))
	for b in recurring_buys:
		rows.append(_txn_row("buy", Catalog.get_display_name(str(b.get("good", ""))), int(b.get("qty", 0)),
			TransportService.nearest_port_tile(str(b.get("dest", ""))), str(b.get("dest", "")), int(b.get("turn_started", 0)), -1))
	return rows

func get_oneoff_move_rows() -> Array:
	var rows: Array = []
	for m in move_log:
		rows.append(_move_row(Catalog.get_display_name(str(m.get("good_id", ""))), int(m.get("qty", 0)),
			str(m.get("tile_from", "")), str(m.get("tile_to", "")),
			int(m.get("turn_started", 0)), int(m.get("turn_ended", -1))))
	return rows

func get_recurring_move_rows() -> Array:
	var rows: Array = []
	for m in recurring_moves:
		for gid in m.get("goods", {}).keys():
			rows.append(_move_row(Catalog.get_display_name(str(gid)), int(m.goods[gid]),
				str(m.get("source", "")), str(m.get("dest", "")), int(m.get("turn_started", 0)), -1))
	return rows

func _is_finished_good(good_id: String) -> bool:
	# No explicit "finished" tier in the MVP, so "finished/manufactured" = non-raw, non-power.
	var gt := str(Catalog.get_good(good_id).get("good_type", ""))
	return gt != "" and gt != "raw" and gt != "power"

func sell_all_to_market(params: Dictionary, log_oneoff: bool = true) -> Dictionary:
	# Stories 4 & 5: sweep every tile's stockpile and sell to the nearest port, filtered by
	#   good_id     ("" = all goods, else a specific good)
	#   finished_only (only manufactured/non-raw goods)
	#   per_tile_keep (leave this many of each good per tile; sell the surplus above it)
	var good_filter := str(params.get("good_id", ""))
	var finished_only := bool(params.get("finished_only", false))
	var keep: int = maxi(0, int(params.get("per_tile_keep", 0)))
	var total_qty := 0
	var total_revenue := 0.0
	var tiles_sold := 0
	for tile_key in Stockpile.tiles_with_stock():
		var tile_id := str(tile_key)
		if not tile_id.begins_with("tile_"):
			continue
		var totals: Dictionary = Stockpile.get_tile_totals(tile_id)
		var goods_qtys: Dictionary = {}
		for gid in totals.keys():
			var g := str(gid)
			if not Catalog.is_good_sellable(g):
				continue
			if good_filter != "" and g != good_filter:
				continue
			if finished_only and not _is_finished_good(g):
				continue
			var surplus := int(totals[gid]) - keep
			if surplus > 0:
				goods_qtys[g] = surplus
		if goods_qtys.is_empty():
			continue
		var summary := queue_sell(tile_id, goods_qtys, log_oneoff)
		if not summary.is_empty():
			total_qty += int(summary.get("total_qty", 0))
			total_revenue += float(summary.get("revenue", 0.0))
			tiles_sold += 1
	return {"total_qty": total_qty, "revenue": total_revenue, "tiles": tiles_sold}

func queue_sell(source_tile: String, goods_qtys: Dictionary, log_oneoff: bool = true) -> Dictionary:
	# Sell specific goods/qtys from a tile: consume from the stockpile, ship to the
	# nearest port, pay out on arrival. All of that lives in MarketState.execute_sale
	# now; this wrapper preserves the public API (note: returns `revenue`, not
	# `total_revenue`, for back-compat with existing callers).
	var result := MarketState.execute_sale(source_tile, goods_qtys, {"log_oneoff": log_oneoff})
	if result.is_empty():
		return {}
	Production.record_external_transport_cost(float(result.get("transport_cost", 0.0)), result.get("transport_breakdown", {}))
	if not bool(result.get("deferred", false)):
		var sale_record: Dictionary = result.get("sale_record", {})
		record_tile_sale(source_tile, int(result.get("total_qty", 0)), float(result.get("total_revenue", 0.0)))
		Production.record_external_goods_sale(sale_record)
	return {
		"items": result.items,
		"total_qty": result.total_qty,
		"revenue": result.total_revenue,
		"turns": result.turns,
		"port": result.port,
		"deferred": result.deferred,
	}

## A shipment couldn't fully unload at a full tile — hold the remainder so the
## goods aren't lost; it retries each turn.
func hold_overflow_shipment(record: Dictionary) -> void:
	var rec := record.duplicate(true)
	rec["turns_waiting"] = int(rec.get("turns_waiting", 0))
	overflow_shipments.append(rec)
	overflow_shipment_held.emit(rec)
	transport_shipments_changed.emit()

func get_overflow_shipments_for_tile(tile_id: String) -> Array:
	var out: Array = []
	for r in overflow_shipments:
		if str(r.get("destination_tile", "")) == tile_id:
			out.append(r)
	return out

## Retry unloading every waiting shipment into its destination stockpile. Fully
## unloaded ones drop off the list; the rest wait another turn. Call this before
## construction claims materials so unloaded build materials are picked up.
func retry_overflow_unload() -> void:
	if overflow_shipments.is_empty():
		return
	var remaining: Array = []
	for r in overflow_shipments:
		var dest := str(r.get("destination_tile", ""))
		var gid := str(r.get("good_id", ""))
		var qty := int(r.get("qty", 0))
		var added := Stockpile.add(dest, gid, qty) if (dest != "" and gid != "" and qty > 0) else 0
		if added >= qty:
			continue  # fully unloaded — drop it
		r["qty"] = qty - added
		r["turns_waiting"] = int(r.get("turns_waiting", 0)) + 1
		remaining.append(r)
	overflow_shipments = remaining
	transport_shipments_changed.emit()

## Clear per-turn sales at the start of each turn's processing.
func reset_tile_sales_for_turn() -> void:
	sales_by_tile.clear()

## Record a realised market sale shipped from a source tile (units + £ revenue).
func record_tile_sale(tile_id: String, units: int, revenue: float) -> void:
	if tile_id == "" or (units <= 0 and revenue <= 0.0):
		return
	var rec: Dictionary = sales_by_tile.get(tile_id, {"units": 0, "revenue": 0.0})
	rec["units"] = int(rec.get("units", 0)) + units
	rec["revenue"] = float(rec.get("revenue", 0.0)) + revenue
	sales_by_tile[tile_id] = rec

func get_tile_sales(tile_id: String) -> Dictionary:
	return sales_by_tile.get(tile_id, {"units": 0, "revenue": 0.0})

func get_pending_transport_shipments() -> Array:
	return pending_transport_shipments.duplicate(true)

func offer_special_order_overflow(record: Dictionary) -> void:
	var rec := record.duplicate(true)
	if int(rec.get("qty", 0)) <= 0:
		return
	special_order_overflow_ready.emit(rec)

func special_order_overflow_can_stockpile(record: Dictionary) -> bool:
	var port_tile := str(record.get("port_tile", record.get("destination_tile", "")))
	var qty := int(record.get("qty", 0))
	if port_tile == "" or qty <= 0:
		return false
	return Stockpile.get_free_capacity(port_tile) >= qty

func sell_special_order_overflow(record: Dictionary) -> Dictionary:
	var good_id := str(record.get("good_id", ""))
	var qty := int(record.get("qty", 0))
	var revenue := float(record.get("total_revenue", 0.0))
	if good_id == "" or qty <= 0:
		return {}
	var source_tile := str(record.get("source_tile", record.get("tile_id", "")))
	var port_tile := str(record.get("port_tile", record.get("destination_tile", "")))
	var sale_record := {
		"tile_id": source_tile,
		"items": [{"good_id": good_id, "qty": qty, "revenue": revenue}],
		"total_qty": qty,
		"total_revenue": revenue,
	}
	if revenue > 0.0:
		add_money(revenue)
		record_tile_sale(source_tile, qty, revenue)
		emit_stockpile_market_sale_completed(sale_record)
		if port_tile != "":
			market_sale_arrived_at_port.emit(port_tile, revenue)
	return sale_record

func stockpile_special_order_overflow(record: Dictionary) -> bool:
	if not special_order_overflow_can_stockpile(record):
		return false
	var port_tile := str(record.get("port_tile", record.get("destination_tile", "")))
	var good_id := str(record.get("good_id", ""))
	var qty := int(record.get("qty", 0))
	return Stockpile.add(port_tile, good_id, qty) == qty

func take_pending_special_order_shipments(order_id: String) -> Array:
	if order_id == "":
		return []
	var taken: Array = []
	var remaining: Array = []
	for shipment in pending_transport_shipments:
		var s: Dictionary = shipment
		if bool(s.get("is_sale", false)) and str(s.get("special_order_id", "")) == order_id:
			taken.append(s.duplicate(true))
		else:
			remaining.append(s)
	if taken.is_empty():
		return []
	pending_transport_shipments = remaining
	transport_shipments_changed.emit()
	return taken

func special_order_shipments_manifest(shipments: Array) -> Dictionary:
	var manifest: Dictionary = {}
	for shipment in shipments:
		for item in _shipment_sale_items(shipment as Dictionary):
			var good_id := str(item.get("good_id", ""))
			var qty := int(item.get("qty", 0))
			if good_id != "" and qty > 0:
				manifest[good_id] = int(manifest.get(good_id, 0)) + qty
	return manifest

func can_store_special_order_shipments_at_ports(shipments: Array) -> bool:
	var required_by_port: Dictionary = {}
	for shipment in shipments:
		var s: Dictionary = shipment
		var port_tile := str(s.get("destination_tile", ""))
		if port_tile == "":
			return false
		var total := 0
		for item in _shipment_sale_items(s):
			total += int(item.get("qty", 0))
		required_by_port[port_tile] = int(required_by_port.get(port_tile, 0)) + total
	for port in required_by_port.keys():
		if Stockpile.get_free_capacity(str(port)) < int(required_by_port[port]):
			return false
	return true

func resolve_special_order_shipments(shipments: Array, action: String, destination_tile: String = "") -> Dictionary:
	var resolved: Array = []
	var total_qty := 0
	var total_revenue := 0.0
	match action:
		"sell":
			for shipment in shipments:
				var sell_shipment: Dictionary = (shipment as Dictionary).duplicate(true)
				sell_shipment.erase("special_order_id")
				sell_shipment.erase("special_order_source_mode")
				queue_transport_shipment(sell_shipment)
				resolved.append(sell_shipment)
				total_qty += _shipment_total_units(sell_shipment)
				total_revenue += float(sell_shipment.get("sale_record", {}).get("total_revenue", 0.0))
		"stockpile_port":
			if not can_store_special_order_shipments_at_ports(shipments):
				return {"ok": false, "reason": "port_capacity"}
			for shipment in shipments:
				var s: Dictionary = shipment
				var port_tile := str(s.get("destination_tile", ""))
				for item in _shipment_sale_items(s):
					var stock_shipment := _stockpile_shipment_from_sale_item(s, port_tile, item as Dictionary)
					_queue_or_store_resolved_shipment(stock_shipment)
					resolved.append(stock_shipment)
					total_qty += int(stock_shipment.get("qty", 0))
		"reroute":
			if destination_tile == "":
				return {"ok": false, "reason": "missing_destination"}
			for shipment in shipments:
				var s: Dictionary = shipment
				var source_tile := str(s.get("source_tile", ""))
				var manifest := _shipment_sale_manifest(s)
				if manifest.is_empty():
					continue
				var route_good_id := ""
				for good_key in manifest.keys():
					route_good_id = str(good_key)
					break
				var quote := TransportService.quote_manifest(source_tile, destination_tile, manifest, {"route_good_id": route_good_id})
				if quote.is_empty():
					continue
				for item in quote.get("items", []):
					var route: Dictionary = item.get("route", quote.get("route", {}))
					var turns := int(item.get("turns", quote.get("turns", 0)))
					var stock_shipment := {
						"source_tile": source_tile,
						"destination_tile": destination_tile,
						"good_id": str(item.get("good_id", "")),
						"qty": int(item.get("qty", 0)),
						"transport_cost": 0.0,
						"tile_distance": int(route.get("tile_distance", 0)),
						"transport_turns": turns,
						"turns_remaining": turns,
						"tiles": route.get("tiles", []),
						"path": route.get("path", []),
						"legs": route.get("legs", []),
					}
					_queue_or_store_resolved_shipment(stock_shipment)
					resolved.append(stock_shipment)
					total_qty += int(stock_shipment.get("qty", 0))
		_:
			return {"ok": false, "reason": "unknown_action"}
	return {"ok": true, "action": action, "shipments": resolved, "total_qty": total_qty, "total_revenue": total_revenue}

func get_inbound_transport_shipments(destination_tile: String, good_id: String = "") -> Array:
	var result: Array = []
	for shipment in pending_transport_shipments:
		if shipment.get("destination_tile", "") != destination_tile:
			continue
		if good_id != "" and shipment.get("good_id", "") != good_id:
			continue
		# Shallow copy: callers only read scalar fields (qty, turns_remaining). Avoids
		# deep-cloning the heavy path/tiles/legs/sale_record arrays every call (this runs
		# per building, per market input, every turn).
		result.append(shipment.duplicate())
	return result

func advance_transport_shipments() -> Array:
	var arrived: Array = []
	var remaining: Array = []
	# Decrement in place — Dictionaries are references, and the only mutation is the
	# countdown. The previous deep-copy of every shipment (with its path/tiles arrays)
	# every turn was a top sim hot-spot. Arrived shipments are read-only consumed by the
	# caller and then discarded; remaining keep their identity in the live list.
	for shipment in pending_transport_shipments:
		shipment.turns_remaining = int(shipment.get("turns_remaining", 0)) - 1
		if int(shipment.turns_remaining) <= 0:
			arrived.append(shipment)
		else:
			remaining.append(shipment)
	pending_transport_shipments = remaining
	if not arrived.is_empty():
		for shipment in arrived:
			_record_arrival(str((shipment as Dictionary).get("destination_tile", "")),
				str((shipment as Dictionary).get("good_id", "")))
		transport_shipments_changed.emit()
	return arrived


## Note that `good_id` reached `tile_id` this turn. Idempotent within a turn: several
## shipments of the same good landing together are one delivering turn, which is what
## "arrived 7 of the last 10 turns" has to mean.
func _record_arrival(tile_id: String, good_id: String) -> void:
	if tile_id == "" or good_id == "":
		return
	var key := "%s|%s" % [tile_id, good_id]
	var turn := _ledger_turn()
	var hist: PackedInt32Array = arrival_turns.get(key, PackedInt32Array())
	if hist.size() > 0 and hist[hist.size() - 1] == turn:
		return
	hist.append(turn)
	var cutoff := turn - ARRIVAL_HISTORY_TURNS
	var trimmed := PackedInt32Array()
	for t in hist:
		if t > cutoff:
			trimmed.append(t)
	arrival_turns[key] = trimmed


## How many of the last `window` turns delivered `good_id` to `tile_id` (0..window).
func arrivals_in_window(tile_id: String, good_id: String, window: int = ARRIVAL_HISTORY_TURNS) -> int:
	var hist: PackedInt32Array = arrival_turns.get("%s|%s" % [tile_id, good_id], PackedInt32Array())
	if hist.is_empty():
		return 0
	var floor_turn := _ledger_turn() - window
	var n := 0
	for t in hist:
		if t > floor_turn:
			n += 1
	return n

# ── Transport throughput congestion (soft cap) ─────────────────────────────
# A tile-link's per-turn flow on a mode = total units of in-transit shipments
# crossing that tile on that mode (same convention as the infra hover readout).
# When flow exceeds the link's capacity (base mode cap × infra level × throughput
# research), goods still move but pay a transport-cost penalty: +100% over capacity,
# +200% once over capacity plus the base L1 cap. Last turn's flow drives this turn's
# costs (route_congestion_tier), so it's stable rather than self-referential.
const _CAPPED_MODES := ["roads", "rail", "pipes", "reinf_pipes"]
## How many turns of over-capacity history the transport panel reports on.
const LINK_HISTORY_TURNS := 10

## "tile_id|mode" -> total units crossing it this turn (capped modes only).
func transport_link_flow() -> Dictionary:
	var flow: Dictionary = {}
	for s in pending_transport_shipments:
		var tiles: Array = s.get("tiles", [])
		var legs: Array = s.get("legs", [])
		if tiles.is_empty() or legs.is_empty():
			continue
		var qty := _shipment_total_units(s)
		if qty <= 0:
			continue
		# Walk legs once; each leg owns the slice of `tiles` up to its `to` tile.
		# `start := idx` reuses the previous leg's END index without advancing past
		# it, so consecutive legs sharing the SAME mode would credit that boundary
		# tile twice (once as the tail of leg N, once as the head of leg N+1) —
		# `counted` guards against exactly that, scoped to this one shipment. A mode
		# SWITCH at a boundary is not this bug: the tile legitimately draws on two
		# separate capacity pools there, so it correctly gets a key per mode — this
		# only dedupes repeat credit to the SAME (tile, mode) pair. _bfs_route()
		# (catalog.gd) produces simple shortest paths, so a real route is not
		# expected to revisit a (tile, mode) pair outside of this adjacent-leg
		# overlap; if that ever changes, this dedupe would need to change with it.
		var idx := 0
		var counted := {}
		for leg in legs:
			var start := idx
			while idx < tiles.size() - 1 and str(tiles[idx]) != str(leg.get("to", "")):
				idx += 1
			var mode := str(leg.get("mode", ""))
			if mode in _CAPPED_MODES:
				for i in range(start, idx + 1):
					var key := "%s|%s" % [str(tiles[i]), mode]
					if counted.has(key):
						continue
					counted[key] = true
					flow[key] = int(flow.get(key, 0)) + qty
	return flow

func _shipment_total_units(s: Dictionary) -> int:
	if bool(s.get("is_sale", false)):
		var total := 0
		for item in s.get("sale_record", {}).get("items", []):
			total += int(item.get("qty", 0))
		return total
	return int(s.get("qty", 0))

## Per-turn capacity of one tile-link: configured mode/level cap × the
## transport_throughput research multiplier. 0 means the mode is uncapped.
func tile_mode_capacity(mode: String, level: int) -> float:
	var cap: float = TransportService.link_capacity(mode, level)
	if cap <= 0.0:
		return 0.0
	return Modifiers.apply("transport_throughput", mode, cap, {"mode": mode})

# A tile's installed infra level for a mode (from the HexMap terrain). Defaults to
# Level 1 when there's no map (headless tests) or the tile lacks that infra. The
# level dict is keyed by infra SLOT key, so the "rail" mode maps to slot "rails".
func _tile_infra_level(tile_id: String, mode: String) -> int:
	var tree := get_tree()
	if tree == null:
		return 1
	var hm = tree.get_first_node_in_group("hex_map")
	if hm == null:
		return 1
	var coord = hm.id_to_coord(tile_id)
	if not hm.tiles.has(coord):
		return 1
	var slot_key := "rails" if mode == "rail" else mode
	return int((hm.tiles[coord] as Dictionary).get("infrastructure_levels", {}).get(slot_key, 1))

## Units of in-transit goods using one tile's infra of one mode this turn — what the
## tile-view infra readout shows. Counts both pass-through on a networked leg AND goods
## that originate/terminate on the tile (their first/last mile uses the tile's infra,
## even when the long haul is overland), matched by the good's transport class.
func tile_mode_flow(tile_id: String, mode: String) -> int:
	var total := 0
	var tolerated: Array = Catalog.infra(mode).get("good_types_tolerated", [])
	for s in pending_transport_shipments:
		var tiles: Array = s.get("tiles", [])
		var legs: Array = s.get("legs", [])
		if not tiles.is_empty() and not legs.is_empty():
			# Networked route: count where it crosses this tile on a leg of `mode`.
			var idx := 0
			var hit := false
			for leg in legs:
				var start := idx
				while idx < tiles.size() - 1 and str(tiles[idx]) != str(leg.get("to", "")):
					idx += 1
				if str(leg.get("mode", "")) == mode:
					for i in range(start, idx + 1):
						if str(tiles[i]) == tile_id:
							hit = true
							break
				if hit:
					break
			if hit:
				total += _shipment_total_units(s)
			continue
		# Overland (no leg data): goods still enter/leave via THIS tile's infra for
		# their first/last mile — count those whose class this mode carries.
		if str(s.get("source_tile", "")) == tile_id or str(s.get("destination_tile", "")) == tile_id:
			var goods := _shipment_goods_dict(s)
			for good_id in goods:
				if not tolerated.has(Catalog.get_transport_class(str(good_id))):
					continue
				# A fluid with no leg data is attributed to its PIPE network only. Since the
				# overland ruling (2026-08-09) road and rail also tolerate fluids, so without
				# this a leg-less fluid shipment would load BOTH networks and be charged
				# congestion twice for one delivery. Legged routes are attributed exactly by
				# the branch above; this only covers the first/last-mile fallback.
				if Catalog.requires_pipeline(str(good_id)) and not EconomyConfig.PIPE_MODES.has(mode):
					continue
				total += int(goods[good_id])
	return total

# {good_id: qty} a shipment carries (sale shipments may carry several goods).
func _shipment_goods_dict(s: Dictionary) -> Dictionary:
	var g: Dictionary = {}
	if bool(s.get("is_sale", false)):
		for item in s.get("sale_record", {}).get("items", []):
			g[str(item.get("good_id", ""))] = int(item.get("qty", 0))
	else:
		var gid := str(s.get("good_id", ""))
		if gid != "":
			g[gid] = int(s.get("qty", 0))
	return g

## Per-good units/cost/penalty for everything that touched one tile's infra of one
## `mode` this turn — the infrastructure building detail panel's "Breakdown" table.
## Same tile-touch rule as tile_mode_flow(): a shipment counts here if it crosses this
## tile on a `mode` leg, or — when it has no leg data (a straight overland haul) — if
## this tile is its source/destination and the good's transport class is one `mode`
## tolerates. Reads _last_transit_shipments (this turn's pre-advance snapshot, same
## moment as _last_link_flow), not the live pending_transport_shipments, so a tile
## still reports what transited it even after arrivals there have since been paid out
## and removed from the live list.
##
## cost/penalty are read-only RE-QUOTES of each touching shipment's own stored route,
## via TransportService.transport_cost_for_route()/route_congestion() — never
## land_cost_after_credit(), which CONSUMES the founder freight credit; a details panel
## must never spend anything just by being opened. They therefore reflect what moving
## these units would cost against THIS turn's congestion, not necessarily what was
## actually charged when the shipment was first queued (possibly turns ago, against a
## different flow) — the same "attribute the whole charge, don't split it per tile"
## approximation route_congestion()'s own doc comment already accepts for its binding
## link, applied here per shipment instead. Diagnostic only: nothing prices off this.
func tile_good_breakdown(tile_id: String, mode: String) -> Array:
	var by_good: Dictionary = {}   # good_id -> {qty:int, cost:float, penalty:float}
	var tolerated: Array = Catalog.infra(mode).get("good_types_tolerated", [])
	for s in _last_transit_shipments:
		var tiles: Array = s.get("tiles", [])
		var legs: Array = s.get("legs", [])
		var overland := tiles.is_empty() or legs.is_empty()
		var touches := false
		if overland:
			touches = str(s.get("source_tile", "")) == tile_id or str(s.get("destination_tile", "")) == tile_id
		else:
			var idx := 0
			for leg in legs:
				var start := idx
				while idx < tiles.size() - 1 and str(tiles[idx]) != str(leg.get("to", "")):
					idx += 1
				if str(leg.get("mode", "")) == mode:
					for i in range(start, idx + 1):
						if str(tiles[i]) == tile_id:
							touches = true
							break
				if touches:
					break
		if not touches:
			continue
		var route_data := {
			"tile_distance": int(s.get("tile_distance", 0)),
			"turns": int(s.get("transport_turns", 0)),
			"reachable": true,
			"path": s.get("path", []),
			"legs": legs,
			"tiles": tiles,
		}
		var cong := route_congestion(route_data)
		var tier := int(cong.get("tier", 0))
		var headroom := int(cong.get("headroom", 0))
		for good_id in _shipment_goods_dict(s):
			# The overland fallback has no leg to read a mode off, so — exactly like
			# tile_mode_flow's first/last-mile rule — it's credited to THIS mode only
			# when the good's transport class actually rides it; without this a
			# leg-less fluid delivery would double up on both its pipe network and
			# whatever overland mode this tile happens to be.
			if overland:
				if not tolerated.has(Catalog.get_transport_class(str(good_id))):
					continue
				if Catalog.requires_pipeline(str(good_id)) and not EconomyConfig.PIPE_MODES.has(mode):
					continue
			var qty := int(_shipment_goods_dict(s)[good_id])
			if qty <= 0:
				continue
			var cost: float = TransportService.transport_cost_for_route(str(good_id), qty, route_data)
			var penalty := 0.0
			if tier > 0:
				var over: int = maxi(0, qty - headroom)
				var within: int = qty - over
				var mult: float = 2.0 if tier == 1 else 3.0
				var denom := float(within) + float(over) * mult
				if denom > 0.0:
					penalty = cost * (1.0 - float(qty) / denom)
			var row: Dictionary = by_good.get(str(good_id), {"qty": 0, "cost": 0.0, "penalty": 0.0})
			row.qty = int(row.qty) + qty
			row.cost = float(row.cost) + cost
			row.penalty = float(row.penalty) + penalty
			by_good[str(good_id)] = row
	var out: Array = []
	for good_id in by_good:
		var row: Dictionary = by_good[good_id]
		out.append({
			"good_id": good_id,
			"qty": int(row.qty),
			"cost": float(row.cost),
			"penalty": float(row.penalty),
		})
	out.sort_custom(func(a, b): return int(a.qty) > int(b.qty))
	return out

func _shipment_sale_items(s: Dictionary) -> Array:
	if not bool(s.get("is_sale", false)):
		return []
	return (s.get("sale_record", {}).get("items", []) as Array)

func _shipment_sale_manifest(s: Dictionary) -> Dictionary:
	var manifest: Dictionary = {}
	for item in _shipment_sale_items(s):
		var good_id := str(item.get("good_id", ""))
		var qty := int(item.get("qty", 0))
		if good_id != "" and qty > 0:
			manifest[good_id] = int(manifest.get(good_id, 0)) + qty
	return manifest

func _stockpile_shipment_from_sale_item(s: Dictionary, destination_tile: String, item: Dictionary) -> Dictionary:
	return {
		"source_tile": str(s.get("source_tile", "")),
		"destination_tile": destination_tile,
		"good_id": str(item.get("good_id", "")),
		"qty": int(item.get("qty", 0)),
		"transport_cost": 0.0,
		"tile_distance": int(s.get("tile_distance", 0)),
		"transport_turns": int(s.get("transport_turns", 0)),
		"turns_remaining": int(s.get("turns_remaining", 0)),
		"tiles": s.get("tiles", []),
		"path": s.get("path", []),
		"legs": s.get("legs", []),
	}

func _queue_or_store_resolved_shipment(shipment: Dictionary) -> void:
	var dest := str(shipment.get("destination_tile", ""))
	var good_id := str(shipment.get("good_id", ""))
	var qty := int(shipment.get("qty", 0))
	if dest == "" or good_id == "" or qty <= 0:
		return
	if int(shipment.get("turns_remaining", 0)) >= 1:
		queue_transport_shipment(shipment)
	else:
		Stockpile.add(dest, good_id, qty)

## Snapshot this turn's per-link flow so next turn's transport costs can read it.
## Called each PROCESS turn. The penalty itself is a transport-cost surcharge applied
## in TransportService.transport_cost_for_route via route_congestion_tier().
func update_transport_congestion() -> void:
	_last_link_flow = transport_link_flow()
	_last_transit_shipments = pending_transport_shipments.duplicate()
	_roll_link_history()

## Record, for every link carrying freight this turn, whether it was over capacity.
## Rolled here rather than in the cost path so a link is sampled once per turn no
## matter how many shipments cross it.
func _roll_link_history() -> void:
	for key in _last_link_flow.keys():
		var parts := str(key).split("|")
		if parts.size() != 2:
			continue
		var cap := tile_mode_capacity(parts[1], _tile_infra_level(parts[0], parts[1]))
		var over: bool = cap > 0.0 and float(_last_link_flow[key]) > cap
		var hist: Array = _link_over_history.get(key, [])
		hist.append(over)
		if hist.size() > LINK_HISTORY_TURNS:
			hist = hist.slice(hist.size() - LINK_HISTORY_TURNS)
		_link_over_history[key] = hist

## Turns in the last LINK_HISTORY_TURNS this link ran over capacity.
func link_turns_over(link_key: String) -> int:
	var n := 0
	for over in (_link_over_history.get(link_key, []) as Array):
		if bool(over):
			n += 1
	return n

## Total congestion surcharge this link has been charged across the run (0 if never).
func link_congestion_paid(link_key: String) -> float:
	return float(_link_congestion_paid.get(link_key, 0.0))

## Book a route's congestion surcharge against the link that caused it. The surcharge
## is priced per ROUTE (marginally, against the tightest congested link's headroom),
## so there is no exact per-link split to recover — attributing the whole charge to
## the binding link is the honest approximation, and it is the link the player has to
## upgrade to make the charge go away. Diagnostic only: nothing prices off this.
func note_congestion_surcharge(link_key: String, amount: float) -> void:
	if link_key == "" or amount <= 0.0:
		return
	_link_congestion_paid[link_key] = float(_link_congestion_paid.get(link_key, 0.0)) + amount

## Every link currently over its capacity, worst first by utilisation. Rows are
## {key, tile_id, mode, flow, cap, level, ratio} — the transport panel's Infra column
## and the top bar's freight readout both read this.
func congested_links() -> Array:
	return active_links(true)

## Links carrying freight this turn, worst-first by utilisation. `only_over` keeps
## just the ones past capacity.
func active_links(only_over: bool = false) -> Array:
	var rows: Array = []
	for key in _last_link_flow.keys():
		var parts := str(key).split("|")
		if parts.size() != 2:
			continue
		var flow := float(_last_link_flow[key])
		if flow <= 0.0:
			continue
		var level := _tile_infra_level(parts[0], parts[1])
		var cap := tile_mode_capacity(parts[1], level)
		if cap <= 0.0:
			continue   # uncapped mode — it can never be "over"
		var ratio := flow / cap
		if only_over and ratio <= 1.0:
			continue
		rows.append({
			"key": str(key), "tile_id": parts[0], "mode": parts[1],
			"flow": flow, "cap": cap, "level": level, "ratio": ratio,
		})
	rows.sort_custom(func(a, b): return float(a.ratio) > float(b.ratio))
	return rows

## Congestion tier of a route, from last turn's flow on the links it crosses:
##   0 = clear · 1 = any link over its capacity · 2 = any link over capacity PLUS its
## base Level-1 cap (a fixed buffer, regardless of the tile's infra level). Drives the
## +100% (tier 1) / +200% (tier 2) transport-cost penalty.
func route_congestion_tier(route_data: Dictionary) -> int:
	return int(route_congestion(route_data).get("tier", 0))

## Congestion tier PLUS the headroom that governs how many units escape the penalty.
## MARGINAL pricing (owner ruling 2026-07-27): only the units ABOVE a congested link's
## remaining capacity pay the surcharge, not the whole shipment. The old whole-route
## multiplier was a cliff — 301 units on a 300-cap link doubled the cost of all 301, and
## a single congested leg penalised every other leg of the journey. Upgrading infra does
## NOT make freight cheaper per unit (owner ruling); it raises the cap, so more of the
## shipment rides at the base rate. Returns {tier, headroom}: headroom is the tightest
## remaining capacity across the route's capped links (0 when already at or over cap).
func route_congestion(route_data: Dictionary) -> Dictionary:
	var clear := {"tier": 0, "headroom": 0, "key": ""}
	if _last_link_flow.is_empty():
		return clear
	var tiles: Array = route_data.get("tiles", [])
	var legs: Array = route_data.get("legs", [])
	if tiles.is_empty() or legs.is_empty():
		return clear
	var worst := 0
	var headroom := -1.0
	var binding := ""   # the link whose headroom governs — what a surcharge is charged for
	var idx := 0
	for leg in legs:
		var start := idx
		while idx < tiles.size() - 1 and str(tiles[idx]) != str(leg.get("to", "")):
			idx += 1
		var mode := str(leg.get("mode", ""))
		if mode in _CAPPED_MODES:
			for i in range(start, idx + 1):
				var tile_id := str(tiles[i])
				var flow := float(_last_link_flow.get("%s|%s" % [tile_id, mode], 0))
				if flow <= 0.0:
					continue
				var cap := tile_mode_capacity(mode, _tile_infra_level(tile_id, mode))
				if cap <= 0.0:
					continue
				var l1_buffer := float(EconomyConfig.TRANSPORT_LINK_CAP_BY_MODE.get(mode, 0))
				if flow > cap + l1_buffer:
					worst = maxi(worst, 2)
				elif flow > cap:
					worst = maxi(worst, 1)
				var link_headroom := maxf(0.0, cap - flow)
				if headroom < 0.0 or link_headroom < headroom:
					binding = "%s|%s" % [tile_id, mode]
				headroom = link_headroom if headroom < 0.0 else minf(headroom, link_headroom)
	if worst == 0:
		return clear
	return {"tier": worst, "headroom": int(maxf(0.0, headroom)), "key": binding}

func enable_sell_surplus(tile_id: String) -> void:
	if tile_id == "" or sell_surplus_tiles.has(tile_id):
		return
	sell_surplus_tiles[tile_id] = true
	sell_surplus_changed.emit(tile_id)

func disable_sell_surplus(tile_id: String) -> void:
	if tile_id == "" or not sell_surplus_tiles.has(tile_id):
		return
	sell_surplus_tiles.erase(tile_id)
	sell_surplus_changed.emit(tile_id)

func is_sell_surplus_enabled(tile_id: String) -> bool:
	return sell_surplus_tiles.has(tile_id)

func get_sell_surplus_tiles() -> Array:
	return sell_surplus_tiles.keys()

# --- Per-good auto-sell (a standing order to sell a specific good's surplus every turn) ---

func enable_auto_sell_good(tile_id: String, good_id: String) -> void:
	if tile_id == "" or good_id == "":
		return
	if not auto_sell_goods.has(tile_id):
		auto_sell_goods[tile_id] = {}
	if auto_sell_goods[tile_id].has(good_id):
		return
	auto_sell_goods[tile_id][good_id] = true
	sell_surplus_changed.emit(tile_id)

func disable_auto_sell_good(tile_id: String, good_id: String) -> void:
	if not auto_sell_goods.has(tile_id):
		return
	if auto_sell_goods[tile_id].erase(good_id):
		if (auto_sell_goods[tile_id] as Dictionary).is_empty():
			auto_sell_goods.erase(tile_id)
		sell_surplus_changed.emit(tile_id)

func is_auto_sell_good(tile_id: String, good_id: String) -> bool:
	return auto_sell_goods.get(tile_id, {}).has(good_id)

# "Sell all except X": units of a good the auto-sell always leaves on the tile,
# on top of whatever the tile's own buildings claim as inputs.
func set_auto_sell_keep(tile_id: String, good_id: String, keep: int) -> void:
	if tile_id == "" or good_id == "":
		return
	if keep <= 0:
		if auto_sell_keep.has(tile_id):
			(auto_sell_keep[tile_id] as Dictionary).erase(good_id)
			if (auto_sell_keep[tile_id] as Dictionary).is_empty():
				auto_sell_keep.erase(tile_id)
	else:
		if not auto_sell_keep.has(tile_id):
			auto_sell_keep[tile_id] = {}
		auto_sell_keep[tile_id][good_id] = keep
	sell_surplus_changed.emit(tile_id)

func auto_sell_keep_for(tile_id: String, good_id: String) -> int:
	return int((auto_sell_keep.get(tile_id, {}) as Dictionary).get(good_id, 0))

func get_auto_sell_good_tiles() -> Array:
	return auto_sell_goods.keys()

func should_auto_sell_good(tile_id: String, good_id: String) -> bool:
	# A good auto-sells if the master "sell everything" order is on for the tile,
	# or it has an explicit per-good auto-sell override.
	return sell_surplus_tiles.has(tile_id) or auto_sell_goods.get(tile_id, {}).has(good_id)

func get_auto_sell_tiles() -> Array:
	# Union of tiles with the master order and tiles with any per-good override.
	var tiles: Dictionary = {}
	for t in sell_surplus_tiles.keys():
		tiles[t] = true
	for t in auto_sell_goods.keys():
		tiles[t] = true
	return tiles.keys()

func set_auto_sell_impact(tile_id: String, max_pct: int) -> void:
	# max_pct is the largest per-turn price impact the auto-sell may cause (or IMPACT_ANY for no cap).
	if tile_id == "":
		return
	auto_sell_impact[tile_id] = max_pct
	sell_surplus_changed.emit(tile_id)

func get_auto_sell_impact(tile_id: String) -> int:
	return int(auto_sell_impact.get(tile_id, IMPACT_ANY))

func auto_sell_unit_cap(tile_id: String) -> int:
	# Per-turn, per-good sell cap implied by the tile's price-impact tolerance.
	# Returns a very large number when ANY impact is allowed (effectively uncapped).
	var impact: int = get_auto_sell_impact(tile_id)
	if impact == IMPACT_ANY:
		return 1 << 30
	return EconomyConfig.units_cap_for_impact(impact)

func set_labour_multiplier(value: float) -> void:
	# Clamp to valid range
	value = clamp(value, EconomyConfig.LABOUR_MULTIPLIER_MIN, EconomyConfig.LABOUR_MULTIPLIER_MAX)
	if value == labour_multiplier:
		return
	labour_multiplier = value
	labour_multiplier_changed.emit(value)
	print("[MatchState] Labour multiplier set to: %.2fx" % value)

## Per-PROCESS accrual of the labour setting's output response, exactly as the
## People panel promises: 0.8× builds output pressure (−2%/turn, floor −30%),
## 1.2× builds momentum (+1%/turn, cap +10%), 1.0× recovers 1%/turn toward 0.
## Runs at the start of PROCESS (before the production cascade), so the setting
## affects output from the first worked turn.
func tick_labour_output_pressure() -> void:
	var p := labour_output_pressure_pct
	if labour_multiplier < 1.0 - 0.001:
		p += EconomyConfig.LABOUR_OUTPUT_PRESSURE_PER_TURN
	elif labour_multiplier > 1.0 + 0.001:
		p += EconomyConfig.LABOUR_OUTPUT_MOMENTUM_PER_TURN
	else:
		p = move_toward(p, 0.0, EconomyConfig.LABOUR_OUTPUT_RECOVERY_PER_TURN)
	labour_output_pressure_pct = clampf(p,
		EconomyConfig.LABOUR_OUTPUT_PRESSURE_FLOOR,
		EconomyConfig.LABOUR_OUTPUT_MOMENTUM_CAP)

# Whether a policy can currently be toggled on. Long Tenure needs any seated HR
# Director; Stock Options is the unique policy unlocked by an HR advisor's mission V.
func is_workforce_policy_available(policy_id: String) -> bool:
	match policy_id:
		WORKFORCE_POLICY_LONG_TENURE:
			return _hr_director_leadership() >= 0
		WORKFORCE_POLICY_STOCK_OPTIONS:
			return advisor_mission_policies.has(WORKFORCE_POLICY_STOCK_OPTIONS)
		_:
			return true

# Leadership stat of the seated HR Director, or -1 if the seat is empty.
func _hr_director_leadership() -> int:
	var a: Dictionary = _roster_entry(str(advisor_seats.get("hr_director", "")))
	return int(a.get("lead", 0)) if not a.is_empty() else -1

func set_workforce_policy_enabled(policy_id: String, enabled: bool) -> void:
	if policy_id == "":
		return
	if enabled and not is_workforce_policy_available(policy_id):
		return   # locked (HR Director not seated / lacks the required leadership)
	var was_enabled := bool(workforce_policies.get(policy_id, false))
	if was_enabled == enabled:
		return
	if enabled:
		for group in WORKFORCE_EXCLUSIVE_GROUPS:
			if (group as Array).has(policy_id):
				for member_id in (group as Array):
					if str(member_id) != policy_id:
						workforce_policies.erase(str(member_id))
		workforce_policies[policy_id] = true
		if not workforce_policy_effects.has(policy_id):
			workforce_policy_effects[policy_id] = {}
	else:
		workforce_policies.erase(policy_id)
	workforce_policies_changed.emit()

func is_workforce_policy_enabled(policy_id: String) -> bool:
	return bool(workforce_policies.get(policy_id, false))

func workforce_policy_game_third_turns() -> int:
	return maxi(10, int(round(float(WORKFORCE_POLICY_GAME_LENGTH_TURNS) / 30.0)) * 10)

func tick_workforce_policies() -> void:
	var ids: Array = workforce_policy_effects.keys()
	for policy_id in workforce_policies.keys():
		if not ids.has(policy_id):
			ids.append(policy_id)

	for raw_id in ids:
		var policy_id := str(raw_id)
		var active := is_workforce_policy_enabled(policy_id)
		var effect: Dictionary = workforce_policy_effects.get(policy_id, {})
		_advance_workforce_effect(policy_id, effect, active)
		if not active and absf(float(effect.get("output_pct", 0.0))) < 0.00001 and absf(float(effect.get("labour_pct", 0.0))) < 0.00001 and absf(float(effect.get("dividend_pct", 0.0))) < 0.00001 and absf(float(effect.get("maint_pct", 0.0))) < 0.00001:
			workforce_policy_effects.erase(policy_id)
		else:
			workforce_policy_effects[policy_id] = effect

# Advance one policy's accrued effect by a single turn (mutates `effect` in place).
# Shared by the live tick and the forward projection the Labour panel uses for its
# 10-turn estimate, so both stay in lockstep.
func _advance_workforce_effect(policy_id: String, effect: Dictionary, active: bool) -> void:
	effect["active_turns"] = int(effect.get("active_turns", 0)) + (1 if active else 0)
	var output_pct := float(effect.get("output_pct", 0.0))
	var labour_pct := float(effect.get("labour_pct", 0.0))

	match policy_id:
		WORKFORCE_POLICY_GENEROUS_PENSIONS:
			if active:
				output_pct = minf(0.05, output_pct + 0.0005)
				labour_pct += _pension_labour_step(int(effect.get("active_turns", 0)))
			else:
				output_pct = maxf(0.0, output_pct - 0.001)
				labour_pct = 0.0
		WORKFORCE_POLICY_EXTENDED_ANNUAL_LEAVE, WORKFORCE_POLICY_GENEROUS_PARENTAL_LEAVE:
			if active:
				labour_pct = maxf(-0.05, labour_pct - 0.001)
			else:
				labour_pct = minf(0.0, labour_pct + 0.0025)
		WORKFORCE_POLICY_STRICT_SAFETY:
			if active:
				labour_pct = maxf(-0.15, labour_pct - 0.005)
			else:
				labour_pct = minf(0.0, labour_pct + 0.0025)
		WORKFORCE_POLICY_LAX_SAFETY:
			# Cutting corners lifts output a little but lets the plant rot: maintenance
			# climbs +5% every turn the policy runs, up to +100% (2× upkeep), then eases
			# back off when strict/standard safety is restored.
			var maint_pct := float(effect.get("maint_pct", 0.0))
			if active:
				labour_pct = minf(0.15, labour_pct + 0.005)
				maint_pct = minf(1.0, maint_pct + 0.05)
			else:
				labour_pct = maxf(0.0, labour_pct - 0.0025)
				maint_pct = maxf(0.0, maint_pct - 0.05)
			effect["maint_pct"] = maint_pct
		WORKFORCE_POLICY_LONG_TENURE:
			# Long-serving staff get cheaper over time (to -10%); a periodic awards
			# payout (+10% one turn every 10th) is added in workforce_labour_cost_delta.
			if active:
				labour_pct = maxf(-0.10, labour_pct - 0.001)
			else:
				labour_pct = minf(0.0, labour_pct + 0.0025)
		WORKFORCE_POLICY_STOCK_OPTIONS:
			# Ownership stake lifts output (to +5%) and grows the dividend (to +10pp).
			var div_pct := float(effect.get("dividend_pct", 0.0))
			if active:
				output_pct = minf(0.05, output_pct + 0.001)
				div_pct = minf(0.10, div_pct + 0.0005)
			else:
				output_pct = maxf(0.0, output_pct - 0.001)
				div_pct = maxf(0.0, div_pct - 0.001)
			effect["dividend_pct"] = div_pct
		WORKFORCE_POLICY_PENSIONS_MINIMUM:
			# Cheapest legal cover: the wage bill thins while it runs, and people
			# quietly leave for better shops, dragging output down until cover improves.
			if active:
				labour_pct = maxf(-0.05, labour_pct - 0.001)
				output_pct = maxf(-0.05, output_pct - 0.0005)
			else:
				labour_pct = minf(0.0, labour_pct + 0.0025)
				output_pct = minf(0.0, output_pct + 0.001)
		WORKFORCE_POLICY_PUSH_AUTOMATION:
			# Machines replace hands: labour falls (to −15%) while the extra plant
			# pushes maintenance up (to +10%); both ease back when the push stops.
			var auto_maint := float(effect.get("maint_pct", 0.0))
			if active:
				labour_pct = maxf(-0.15, labour_pct - 0.002)
				auto_maint = minf(0.10, auto_maint + 0.02)
			else:
				labour_pct = minf(0.0, labour_pct + 0.0025)
				auto_maint = maxf(0.0, auto_maint - 0.02)
			effect["maint_pct"] = auto_maint

	effect["output_pct"] = output_pct
	effect["labour_pct"] = labour_pct

func _pension_labour_step(active_turns: int) -> float:
	var third := workforce_policy_game_third_turns()
	if active_turns <= third:
		return 0.001
	if active_turns <= third * 2:
		return 0.0025
	return 0.004

func workforce_output_multiplier(turn_number: int = -1) -> float:
	var turn := int(TurnManager.current_turn) if turn_number < 0 else turn_number
	# Labour-effort pressure/momentum accrued by tick_labour_output_pressure().
	var multiplier := 1.0 + labour_output_pressure_pct / 100.0
	if is_workforce_policy_enabled(WORKFORCE_POLICY_GENEROUS_PENSIONS):
		var pensions: Dictionary = workforce_policy_effects.get(WORKFORCE_POLICY_GENEROUS_PENSIONS, {})
		multiplier *= 1.0 + float(pensions.get("output_pct", 0.0))
	if is_workforce_policy_enabled(WORKFORCE_POLICY_PENSIONS_MINIMUM):
		var min_pensions: Dictionary = workforce_policy_effects.get(WORKFORCE_POLICY_PENSIONS_MINIMUM, {})
		multiplier *= 1.0 + float(min_pensions.get("output_pct", 0.0))
	if is_workforce_policy_enabled(WORKFORCE_POLICY_STOCK_OPTIONS):
		var stock: Dictionary = workforce_policy_effects.get(WORKFORCE_POLICY_STOCK_OPTIONS, {})
		multiplier *= 1.0 + float(stock.get("output_pct", 0.0))
	if is_workforce_policy_enabled(WORKFORCE_POLICY_EXTENDED_ANNUAL_LEAVE) and turn % 10 == 0:
		multiplier *= 0.95
	if is_workforce_policy_enabled(WORKFORCE_POLICY_GENEROUS_PARENTAL_LEAVE):
		var ten_turn_block := int(floor(float(maxi(turn, 1) - 1) / 10.0))
		if ten_turn_block % 2 == 0:
			multiplier *= 0.95
	if is_workforce_policy_enabled(WORKFORCE_POLICY_STRICT_SAFETY):
		multiplier *= 0.90
	if is_workforce_policy_enabled(WORKFORCE_POLICY_LAX_SAFETY):
		multiplier *= 1.05
	if is_workforce_policy_enabled(WORKFORCE_POLICY_ANNUAL_BONUS) and turn % 10 == 0:
		multiplier *= 1.20
	if is_workforce_policy_enabled(WORKFORCE_POLICY_SMALL_BONUS) and turn % 10 == 0:
		multiplier *= 1.10
	if is_workforce_policy_enabled(WORKFORCE_POLICY_ANNUAL_PROFIT_SHARE):
		multiplier *= 1.10
	if is_workforce_policy_enabled(WORKFORCE_POLICY_PROFIT_SHARE_10):
		multiplier *= 1.15
	return multiplier

# Empire-wide maintenance multiplier from workforce policy: every effect's accrued
# maint_pct sums (Lax Safety's neglect ramp to +100%, the automation push to +10%).
# Applied per building in the maintenance_labour phase. 1.0 = no change.
func workforce_maintenance_multiplier() -> float:
	var pct := 0.0
	for effect in workforce_policy_effects.values():
		if effect is Dictionary:
			pct += maxf(0.0, float(effect.get("maint_pct", 0.0)))
	return 1.0 + pct

# ── CFO tax-loss carry-forward ───────────────────────────────────────────────
func cfo_seated() -> bool:
	return get_advisor_in_seat("cfo") != ""

# Bank a credit worth 5% of the turn's revenue on a losing turn. Fires the one-time
# explainer signal the first time. Returns the amount banked.
func cfo_bank_tax_credit(revenue: float) -> float:
	var amount := maxf(0.0, revenue) * CFO_TAX_CREDIT_RATE
	if amount < 0.01:
		return 0.0
	cfo_tax_credit_pool.append({"amount": amount, "turns_left": CFO_TAX_CREDIT_TURNS})
	if not cfo_tax_credit_intro_shown:
		cfo_tax_credit_intro_shown = true
		cfo_tax_credit_filed.emit(amount)
	return amount

# Consume banked credits (oldest first) to offset a tax bill. Returns the amount applied.
func cfo_apply_tax_credit(tax: float) -> float:
	if tax <= 0.0 or cfo_tax_credit_pool.is_empty():
		return 0.0
	var remaining := tax
	var applied := 0.0
	for entry in cfo_tax_credit_pool:
		if remaining <= 0.0:
			break
		var take := minf(float(entry.get("amount", 0.0)), remaining)
		entry["amount"] = float(entry.get("amount", 0.0)) - take
		applied += take
		remaining -= take
	_prune_tax_credits()
	return applied

# Tick every banked credit's 5-turn window down by one; drop the exhausted/expired.
func cfo_age_tax_credits() -> void:
	for entry in cfo_tax_credit_pool:
		entry["turns_left"] = int(entry.get("turns_left", 0)) - 1
	_prune_tax_credits()

func cfo_tax_credit_available() -> float:
	var total := 0.0
	for entry in cfo_tax_credit_pool:
		total += float(entry.get("amount", 0.0))
	return total

func _prune_tax_credits() -> void:
	var kept: Array = []
	for entry in cfo_tax_credit_pool:
		if int(entry.get("turns_left", 0)) > 0 and float(entry.get("amount", 0.0)) > 0.005:
			kept.append(entry)
	cfo_tax_credit_pool = kept

# Summed workforce-policy labour delta (a fraction, e.g. -0.10 for -10%). Policies
# combine ADDITIVELY here; callers apply this to the 100% base alongside the labour
# slider and research trims rather than compounding it on top of them.
func workforce_labour_cost_delta(turn_number: int = -1) -> float:
	var turn := int(TurnManager.current_turn) if turn_number < 0 else turn_number
	var delta := 0.0
	for effect in workforce_policy_effects.values():
		if effect is Dictionary:
			delta += float(effect.get("labour_pct", 0.0))
	if is_workforce_policy_enabled(WORKFORCE_POLICY_ANNUAL_BONUS):
		delta += 0.05
	if is_workforce_policy_enabled(WORKFORCE_POLICY_SMALL_BONUS):
		delta += 0.025
	# Long Tenure Awards: a payout spike of +10% labour one turn every 10th turn.
	if is_workforce_policy_enabled(WORKFORCE_POLICY_LONG_TENURE) and turn > 0 and turn % 10 == 0:
		delta += 0.10
	return delta

# Accrued Stock Options dividend bonus (0..0.10), added on top of the base dividend
# rate at the payout site; persists (decaying) after the policy is switched off.
func workforce_dividend_bonus() -> float:
	var e = workforce_policy_effects.get(WORKFORCE_POLICY_STOCK_OPTIONS, {})
	return float(e.get("dividend_pct", 0.0)) if e is Dictionary else 0.0

func workforce_labour_cost_multiplier() -> float:
	return maxf(0.0, 1.0 + workforce_labour_cost_delta())

# Project the summed workforce-policy labour delta `turns_ahead` turns forward,
# assuming the currently-enabled policies stay enabled. Runs the same per-turn
# accrual as tick_workforce_policies on a throwaway copy (no live state touched),
# so the Labour panel's 10-turn estimate matches what the sim will actually charge.
func projected_workforce_labour_delta(turns_ahead: int) -> float:
	if turns_ahead <= 0:
		return workforce_labour_cost_delta()
	var effects: Dictionary = {}
	for k in workforce_policy_effects.keys():
		var e = workforce_policy_effects[k]
		effects[str(k)] = (e as Dictionary).duplicate(true) if e is Dictionary else {}
	var ids: Array = effects.keys()
	for policy_id in workforce_policies.keys():
		if not ids.has(str(policy_id)):
			ids.append(str(policy_id))
	for _turn in range(turns_ahead):
		for raw_id in ids:
			var policy_id := str(raw_id)
			var effect: Dictionary = effects.get(policy_id, {})
			_advance_workforce_effect(policy_id, effect, is_workforce_policy_enabled(policy_id))
			effects[policy_id] = effect
	var delta := 0.0
	for effect in effects.values():
		if effect is Dictionary:
			delta += float(effect.get("labour_pct", 0.0))
	if is_workforce_policy_enabled(WORKFORCE_POLICY_ANNUAL_BONUS):
		delta += 0.05
	if is_workforce_policy_enabled(WORKFORCE_POLICY_SMALL_BONUS):
		delta += 0.025
	return delta

# Combined labour multiplier from the slider + workforce policies, applied
# ADDITIVELY to the 100% base (no compounding). Per-building research head-count
# trims add on top of this in Production.labour_cost_factor. Display sites that lack
# a specific building (money projection, per-tier rows) use this global factor.
func labour_policy_factor() -> float:
	return maxf(0.0, 1.0 + (labour_multiplier - 1.0) + workforce_labour_cost_delta())

# ── Advisor seat framework (docs/advisor-system-spec.md §2-6) ──────────────
# Phase 0 CORE: data model + scaling + idempotent modifier reconciler. The
# effects are inert placeholders here (spec §12.1 Phase 0 = "nothing works yet");
# real domain modifiers land in Phase 1. The display roster (_advisor_definitions)
# is merged onto ADVISOR_ROSTER in a later increment.

# seat_id -> {seat_name, governs (stat key), flexible (best-of stat keys; [] = rigid), lever_kit}
const SEAT_DEFINITIONS := {
	"cfo":                {"seat_name": "CFO",                  "governs": "fin",  "flexible": [],                  "lever_kit": ["loan interest", "loan duration", "dividend holiday"]},
	"coo":                {"seat_name": "COO",                  "governs": "ops",  "flexible": [],                  "lever_kit": ["labour cost", "maintenance", "energy cost", "retrofit"]},
	"vp_logistics":       {"seat_name": "VP Logistics",         "governs": "ops",  "flexible": [],                  "lever_kit": ["transport cost", "throughput", "distance per turn"]},
	"hr_director":        {"seat_name": "HR Director",          "governs": "lead", "flexible": [],                  "lever_kit": ["labour policies", "retention", "labour cost"]},
	"technical_director": {"seat_name": "Technical Director",   "governs": "inn",  "flexible": [],                  "lever_kit": ["recipe output (chosen category)", "free tech unlock"]},
	"research_director":  {"seat_name": "Research Director",    "governs": "inn",  "flexible": [],                  "lever_kit": ["free tech unlocks"]},
	"government_affairs": {"seat_name": "Government Affairs",    "governs": "inf",  "flexible": [],                  "lever_kit": ["tax reduction", "green subsidy", "carbon relief"]},
	"chief_investment":   {"seat_name": "Chief Investment",     "governs": "fin",  "flexible": ["fin", "inn"],       "lever_kit": ["one-off cheap loan", "purchase value", "capex"]},
	"chief_markets":      {"seat_name": "Chief Markets Officer","governs": "inf",  "flexible": ["inf", "fin"],       "lever_kit": ["market spread", "sale-price boosts", "forewarning"]},
	"sustainability":     {"seat_name": "Sustainability Officer","governs": "inf", "flexible": ["inf", "ops", "lead"],"lever_kit": ["greenest push", "green premium", "clean-adoption discount"]},
}

# Canonical 12-advisor stat roster (spec §3). Stars are DERIVED (advisor_star),
# never stored. salary is static (Phase-2 payroll); advisor_payroll_per_turn stays
# flat for now. traits.specialty_domain is filled in Phase 1+ for effect routing.
const ADVISOR_ROSTER := [
	# The family friend. Joins pro bono at turn 3 in whichever post the player picks, then
	# leaves at t33. Salary 0 — he is a favour, not a hire. See spec §5.4.
	{"id": "andrew",    "name": "Andrew Keeler",   "role": "coo",                "inf": 3, "ops": 3, "lead": 3, "inn": 2, "fin": 3, "salary": 0.0, "traits": {"specialty_name": "Out of Retirement", "specialty_description": "misses the work; serves 30 turns for nothing", "specialty_domain": "", "specialty_value": 0.0, "mission_unlock_turn": 0}},
	{"id": "vera",      "name": "Vera Ashby",      "role": "cfo",                "inf": 3, "ops": 3, "lead": 3, "inn": 2, "fin": 3, "salary": 1.0, "traits": {"specialty_name": "Family Trust",         "specialty_description": "reduced salary, no malus anywhere",                 "specialty_domain": "", "specialty_value": 0.0, "mission_unlock_turn": 0}},
	{"id": "alexandra", "name": "Alexandra Reyes", "role": "coo",                "inf": 3, "ops": 3, "lead": 3, "inn": 3, "fin": 2, "salary": 4.0, "traits": {"specialty_name": "Prima Donna",          "specialty_description": "superb everywhere; high salary + walk-risk if benched", "specialty_domain": "", "specialty_value": 0.0, "mission_unlock_turn": 0}},
	{"id": "gerald",    "name": "Gerald Vance",    "role": "coo",                "inf": 2, "ops": 3, "lead": 3, "inn": 2, "fin": 2, "salary": 2.0, "traits": {"specialty_name": "Dinosaur",             "specialty_description": "top operator; brakes clean-recipe adoption (carbon, later)", "specialty_domain": "", "specialty_value": 0.0, "mission_unlock_turn": 0}},
	{"id": "eleanor",   "name": "Eleanor Shaw",    "role": "hr_director",        "inf": 3, "ops": 2, "lead": 3, "inn": 1, "fin": 3, "salary": 2.0, "traits": {"specialty_name": "Beloved",              "specialty_description": "labour cost via HR + slows advisor churn",           "specialty_domain": "", "specialty_value": 0.0, "mission_unlock_turn": 0}},
	{"id": "sloane",    "name": "Sloane Vane",     "role": "chief_markets",      "inf": 3, "ops": 3, "lead": 1, "inn": 1, "fin": 2, "salary": 2.0, "traits": {"specialty_name": "Slick",                "specialty_description": "extra temporary sale-price boost in a markets seat",  "specialty_domain": "", "specialty_value": 0.0, "mission_unlock_turn": 0}},
	{"id": "priya",     "name": "Priya Anand",     "role": "sustainability",     "inf": 3, "ops": 1, "lead": 2, "inn": 3, "fin": 1, "salary": 2.0, "traits": {"specialty_name": "Idealist",             "specialty_description": "amplifies green; raises short-term spend (green, later)", "specialty_domain": "", "specialty_value": 0.0, "mission_unlock_turn": 0}},
	{"id": "hitomi",    "name": "Hitomi Sato",     "role": "vp_logistics",       "inf": 1, "ops": 3, "lead": 1, "inn": 3, "fin": 2, "salary": 2.0, "traits": {"specialty_name": "Flow State",           "specialty_description": "logistics/mfg optimisation; extra malus in Inf/Lead seats", "specialty_domain": "", "specialty_value": 0.0, "mission_unlock_turn": 0}},
	{"id": "hal",       "name": "Hal Rooker",      "role": "government_affairs", "inf": 3, "ops": 1, "lead": 3, "inn": 1, "fin": 2, "salary": 2.0, "traits": {"specialty_name": "Backroom Deals",       "specialty_description": "regulatory relief (tax cut; carbon relief when it exists)", "specialty_domain": "", "specialty_value": 0.0, "mission_unlock_turn": 0}},
	{"id": "tom",       "name": "Tom Bracken",     "role": "coo",                "inf": 1, "ops": 3, "lead": 2, "inn": 1, "fin": 2, "salary": 2.0, "traits": {"specialty_name": "Shop-Floor Respect",   "specialty_description": "extra labour reduction in an Ops seat",              "specialty_domain": "", "specialty_value": 0.0, "mission_unlock_turn": 0}},
	{"id": "marcus",    "name": "Marcus Thorne",   "role": "chief_investment",   "inf": 2, "ops": 1, "lead": 2, "inn": 1, "fin": 3, "salary": 2.0, "traits": {"specialty_name": "Leverage",             "specialty_description": "cheap capital + discounted acquisitions; debt-risk exposure", "specialty_domain": "", "specialty_value": 0.0, "mission_unlock_turn": 0}},
	{"id": "idris",     "name": "Idris Kohl",      "role": "technical_director", "inf": 1, "ops": 2, "lead": 1, "inn": 3, "fin": 1, "salary": 2.0, "traits": {"specialty_name": "Insufferable Genius",  "specialty_description": "big recipe efficiency in TD; empire labour malus unless siloed", "specialty_domain": "", "specialty_value": 0.0, "mission_unlock_turn": 0}},
	{"id": "rufus",     "name": "Rufus Ashby",     "role": "government_affairs", "inf": 3, "ops": 1, "lead": 1, "inn": 1, "fin": 1, "salary": 2.0, "traits": {"specialty_name": "Silver Tongue, Empty Suit", "specialty_description": "strong Influencing effect; a bad block everywhere else", "specialty_domain": "", "specialty_value": 0.0, "mission_unlock_turn": 0}},
]

# Phase-1 FREE-lever effects per seat: each emits domain modifiers scaled by the
# governing tier. base_pct is the tier-3 magnitude; tier 2 = half, tier 1 = a
# half-magnitude malus (sign flips). Numbers are illustrative (spec: tune in the
# harness); labour -10% at tier 3 matches spec §5.1's COO/HR dual-source cap.
# Finance/markets/gov seats have no entry — their levers are Phase 2+.
const _SEAT_EFFECTS := {
	"coo": [
		{"domain": "labour_headcount", "base_pct": -10.0},
		{"domain": "maintenance", "base_pct": -10.0},
		{"domain": "building_power", "base_pct": -8.0},
		# Grid tariffs: cheaper imports, better-paid exports (tier3 -10% / +10%).
		{"domain": "grid_buy_price", "base_pct": -10.0},
		{"domain": "grid_sell_price", "base_pct": 10.0},
	],
	"vp_logistics": [
		{"domain": "transport_cost", "base_pct": -10.0},
		{"domain": "transport_throughput", "base_pct": 10.0},
	],
	"hr_director": [
		{"domain": "labour_headcount", "base_pct": -10.0},
	],
	# Phase 2 SMALL-lever seats (isolated domains read at the tax / buy-price / loan sites).
	"cfo": [
		{"domain": "loan_interest", "base_pct": -25.0},
		{"domain": "dividend_rate", "base_pct": -40.0},   # tier3 -40% / tier2 -20% / tier1 +20%
	],
	"chief_investment": [
		# Rebate a fraction of build/upgrade-materials value: tier3 +10% / tier2 +5% / tier1 -5%.
		{"domain": "construction_rebate", "base_pct": 10.0},
		# Land + NPC-building purchases: tier3 -10% / tier2 -5% / tier1 +5%.
		{"domain": "purchase_cost", "base_pct": -10.0},
	],
	"government_affairs": [
		{"domain": "tax_rate", "base_pct": -20.0},
	],
	"chief_markets": [
		{"domain": "market_spread", "base_pct": -25.0},
		# Sale-price uplift applies to ALL market revenue (a broad base) so it is kept
		# tiny: tier3 +2% / tier2 +1% / tier1 -1%. Stacks with research market_price, but
		# the realised sale price is clamped to the buy price (MarketState.get_sale_price).
		{"domain": "market_price", "base_pct": 2.0},
	],
}
# governing tier -> multiplier on base_pct. 3 = full, 2 = half, 1 = half malus.
const _TIER_MULT := {3: 1.0, 2: 0.5, 1: -0.5, 0: 0.0}

func _roster_entry(advisor_id: String) -> Dictionary:
	for a in ADVISOR_ROSTER:
		if str(a.get("id", "")) == advisor_id:
			return a
	return {}

# Derived star (spec §2.2 precedence): 4+ threes -> 5; else score>=12 -> 4;
# >=10 -> 3; >=8 -> 2; else 1 (floor). Accepts a full advisor dict or a bare
# {inf,ops,lead,inn,fin}. Never persisted.
func advisor_star(stats: Dictionary) -> int:
	var score := 0
	var threes := 0
	for key in ["inf", "ops", "lead", "inn", "fin"]:
		var v := int(stats.get(key, 1))
		score += v
		if v >= 3:
			threes += 1
	if threes >= 4:
		return 5
	if score >= 12:
		return 4
	if score >= 10:
		return 3
	if score >= 8:
		return 2
	return 1

func advisor_star_by_id(advisor_id: String) -> int:
	var a := _roster_entry(advisor_id)
	return advisor_star(a) if not a.is_empty() else 0

# The 3/2/1 governing tier for an advisor in a seat (spec §2.3). Rigid seats read
# the governing stat; flexible seats read the BEST of their eligible disciplines.
# Returns 0 for an unknown advisor/seat.
func advisor_seat_tier(advisor_id: String, seat_id: String) -> int:
	var a := _roster_entry(advisor_id)
	if a.is_empty() or not SEAT_DEFINITIONS.has(seat_id):
		return 0
	var seat: Dictionary = SEAT_DEFINITIONS[seat_id]
	var flex: Array = seat.get("flexible", [])
	if flex.is_empty():
		return int(a.get(str(seat.get("governs", "")), 1))
	var best := 1
	for disc in flex:
		best = maxi(best, int(a.get(str(disc), 1)))
	return best

# Which discipline governs a (possibly flexible) seat for this advisor — for the
# UI preview (spec §11). For flexible seats returns the best-of winner.
func advisor_seat_governing_discipline(advisor_id: String, seat_id: String) -> String:
	var a := _roster_entry(advisor_id)
	if not SEAT_DEFINITIONS.has(seat_id):
		return ""
	var seat: Dictionary = SEAT_DEFINITIONS[seat_id]
	var flex: Array = seat.get("flexible", [])
	if flex.is_empty() or a.is_empty():
		return str(seat.get("governs", ""))
	var best_disc := ""
	var best := -1
	for disc in flex:
		var v := int(a.get(str(disc), 1))
		if v > best:
			best = v
			best_disc = str(disc)
	return best_disc

# Assign a HIRED, rostered advisor to a seat. Enforces the slot cap and
# one-seat-per-advisor. Returns false if rejected.
## Building operational loans (spec §5.3). A newly CONSTRUCTED building has no cash flow yet,
## so its first TAB_WINDOW_TURNS of running costs are carried rather than paid: each turn they
## are charged as normal and then refunded onto the tab, which keeps every existing cost site
## and the money panel's ledger honest instead of diverting four separate charge paths.
##
## Exposure is bounded by construction — exactly five turns — which is why the earlier
## open-ended version's 1x-capex cap and forced sale are gone. Requires a seated CFO: with no
## one to arrange it, costs simply hit cash as before.
const TAB_WINDOW_TURNS := 5
const TAB_SLICES := 12
## What to do when a build's credit facility comes up: "ask" raises the dialog, the other three
## answer it silently. Stored beside the other construct-panel defaults.
const CREDIT_DEFAULT_CHOICES: Array[String] = ["ask", "slices", "loan", "none"]
var construct_credit_default: String = "ask"

func set_construct_credit_default(value: String) -> void:
	if not CREDIT_DEFAULT_CHOICES.has(value) or value == construct_credit_default:
		return
	construct_credit_default = value
	construct_settings_changed.emit()
var building_tabs: Dictionary = {}   # instance_id -> {turns_left, accrued, mode, slices_left}


func can_open_building_tab() -> bool:
	return cfo_seated()


## Start carrying a building's running costs. Called the turn BEFORE it completes, because that
## is when its inputs are ordered and the first money moves.
func open_building_tab(instance_id: String, mode: String = "slices") -> bool:
	if not can_open_building_tab() or instance_id == "" or building_tabs.has(instance_id):
		return false
	building_tabs[instance_id] = {
		"turns_left": TAB_WINDOW_TURNS, "accrued": 0.0,
		"mode": mode, "slices_left": 0,
	}
	return true


## The player's answer to the credit offer. "none" closes the tab so this building's costs hit
## cash exactly as they would have without the facility.
func set_building_tab_mode(instance_id: String, mode: String) -> void:
	if not building_tabs.has(instance_id):
		return
	if mode == "none":
		building_tabs.erase(instance_id)
		return
	var tab: Dictionary = building_tabs[instance_id]
	tab["mode"] = mode
	building_tabs[instance_id] = tab


func building_tab_debt(instance_id: String) -> float:
	return float((building_tabs.get(instance_id, {}) as Dictionary).get("accrued", 0.0))


## What a building's tab actually takes each turn, and for how many more turns — the pair the
## detail panel shows, because "you owe £900" tells a player nothing about whether they can
## afford it, while "£75 a turn for 12 turns" is the thing they budget against.
##
## Inside the interest-free window nothing is repaid yet, so the schedule quoted is the one it
## WILL run to (the accrued total over TAB_SLICES) and `starts_in` counts the turns until the
## first slice. Once repayment begins the slice is constant: each turn takes accrued/slices_left
## and decrements both, which leaves the quotient where it was.
func building_tab_repayment(instance_id: String) -> Dictionary:
	var tab: Dictionary = building_tabs.get(instance_id, {})
	var accrued := float(tab.get("accrued", 0.0))
	if tab.is_empty() or accrued <= 0.0:
		return {"accrued": 0.0, "per_turn": 0.0, "turns_left": 0, "starts_in": 0}
	var slices := int(tab.get("slices_left", 0))
	if slices > 0:
		return {"accrued": accrued, "per_turn": accrued / float(slices),
			"turns_left": slices, "starts_in": 0}
	return {"accrued": accrued, "per_turn": accrued / float(TAB_SLICES),
		"turns_left": TAB_SLICES, "starts_in": int(tab.get("turns_left", 0))}


## Everything the player still owes across every building tab — the money panel's row.
func total_building_tab_debt() -> float:
	var total := 0.0
	for iid in building_tabs:
		total += float(building_tabs[iid].get("accrued", 0.0))
	return total


## Carry one turn of a building's running costs. Returns the amount refunded onto the tab, which
## the caller credits back so the turn's cash matches what the player actually paid.
func accrue_building_tab(instance_id: String, amount: float) -> float:
	var tab: Dictionary = building_tabs.get(instance_id, {})
	if tab.is_empty() or int(tab.get("turns_left", 0)) <= 0 or amount <= 0.0:
		return 0.0
	tab["accrued"] = float(tab.get("accrued", 0.0)) + amount
	building_tabs[instance_id] = tab
	return amount


## End of turn: wind the window down and settle any tab that has run its course.
func tick_building_tabs() -> void:
	for iid in building_tabs.keys():
		var tab: Dictionary = building_tabs[iid]
		var left := int(tab.get("turns_left", 0))
		if left > 0:
			tab["turns_left"] = left - 1
			if tab["turns_left"] == 0:
				_settle_building_tab(str(iid), tab)
				# Settling may have closed the tab outright (the loan route converts and
				# erases). Writing it back unconditionally would resurrect it.
				if not building_tabs.has(iid):
					continue
			building_tabs[iid] = tab
			continue
		# Repayment: one interest-free slice a turn until it is cleared.
		if str(tab.get("mode", "slices")) == "slices" and int(tab.get("slices_left", 0)) > 0:
			var slice: float = float(tab.get("accrued", 0.0)) / float(tab.get("slices_left", 1))
			add_money(-slice)
			tab["accrued"] = maxf(0.0, float(tab.get("accrued", 0.0)) - slice)
			tab["slices_left"] = int(tab.get("slices_left", 0)) - 1
			building_tabs[iid] = tab
			if int(tab["slices_left"]) <= 0 or float(tab["accrued"]) <= 0.01:
				building_tabs.erase(iid)


func _settle_building_tab(instance_id: String, tab: Dictionary) -> void:
	var owed := float(tab.get("accrued", 0.0))
	if owed <= 0.0:
		building_tabs.erase(instance_id)
		return
	if str(tab.get("mode", "slices")) == "loan":
		# Converts to an ordinary loan — smaller payments, but it carries interest.
		LoanState.take_distress_loan(owed)
		building_tabs.erase(instance_id)
		return
	tab["slices_left"] = TAB_SLICES


## Purchased buildings arrive with PURCHASE_SEED_TURNS of their recipe's inputs — a going
## concern comes with stock, where a fresh build comes with a ramp to finance (§5.3's tab).
## Infra and input-less recipes get nothing: there is no inventory to seed.
const PURCHASE_SEED_TURNS := 2
## Goods that could not fit in the tile when a purchase was seeded. They exist, the player can
## see them on the building's detail panel, and NOTHING else can draw on them — they drain into
## the tile as real capacity frees up. instance_id -> {good_id: qty}
var ghost_holdings: Dictionary = {}


## What the stock a purchase arrives with is worth at market. The buyer pays for PURCHASE_SEED_
## TURNS of it — an advisor may hand over a THIRD turn's worth, but the two are always paid for.
func purchase_kit_cost(building: Dictionary) -> float:
	var recipe: Dictionary = Catalog.get_recipe(str(building.get("recipe_id", "")))
	var total := 0.0
	for input in recipe.get("inputs", []):
		var gid := str(input.get("good_id", ""))
		if gid != "":
			total += float(int(input.get("qty", 0)) * PURCHASE_SEED_TURNS) * MarketState.get_buy_price(gid)
	return total


## The full asking price for an NPC building: the advisor-adjusted sale value plus the stock it
## comes with. One helper so the listing, the Buy button and the charge cannot disagree.
func building_purchase_price(building: Dictionary) -> int:
	return int(round(
		purchase_cost_after_advisor(float(BuildingPrice.sale_price(building)))
		+ purchase_kit_cost(building)))


## How many turns of inputs a purchase actually receives. The player pays for PURCHASE_SEED_
## TURNS; a seated COO throws in one more (§5.4) — a gift of goods, not a discount on price.
func purchase_seed_turns() -> int:
	return PURCHASE_SEED_TURNS + (1 if get_advisor_in_seat("coo") != "" else 0)


## Seed a newly-bought building with stock. Returns the total units seeded (0 for infra, for
## input-less recipes, and for a building that already has its own stock on the tile).
func seed_purchase_inventory(instance_id: String) -> int:
	var building: Dictionary = buildings.get(instance_id, {})
	if building.is_empty():
		return 0
	var recipe: Dictionary = Catalog.get_recipe(str(building.get("recipe_id", "")))
	var inputs: Array = recipe.get("inputs", [])
	if inputs.is_empty():
		return 0
	var tile_id := str(building.get("tile_id", ""))
	if tile_id == "":
		return 0
	var seeded := 0
	for input in inputs:
		var gid := str(input.get("good_id", ""))
		var qty := int(input.get("qty", 0)) * purchase_seed_turns()
		if gid == "" or qty <= 0:
			continue
		var placed: int = Stockpile.add(tile_id, gid, qty)
		seeded += qty
		var overflow := qty - placed
		if overflow > 0:
			_add_ghost_holding(instance_id, gid, overflow)
	return seeded


func _add_ghost_holding(instance_id: String, good_id: String, qty: int) -> void:
	if qty <= 0:
		return
	var held: Dictionary = ghost_holdings.get(instance_id, {})
	held[good_id] = int(held.get(good_id, 0)) + qty
	ghost_holdings[instance_id] = held
	print("[Purchase] %s: %d %s held off-tile (no room) — will move in as space frees" % [
		instance_id, qty, good_id])


## What is waiting off-tile for this building, for its detail panel's
## "x units stored for this building" line.
func ghost_holding_for(instance_id: String) -> Dictionary:
	return (ghost_holdings.get(instance_id, {}) as Dictionary).duplicate()


func ghost_holding_units(instance_id: String) -> int:
	var total := 0
	for gid in (ghost_holdings.get(instance_id, {}) as Dictionary):
		total += int(ghost_holdings[instance_id][gid])
	return total


## Move held goods onto the tile as capacity allows. Called each turn before production, so a
## building that could not be fully stocked on purchase fills up as it consumes what it has.
func drain_ghost_holdings() -> void:
	if ghost_holdings.is_empty():
		return
	for instance_id in ghost_holdings.keys():
		var building: Dictionary = buildings.get(str(instance_id), {})
		if building.is_empty():
			ghost_holdings.erase(instance_id)   # building gone; the goods go with it
			continue
		var tile_id := str(building.get("tile_id", ""))
		var held: Dictionary = ghost_holdings[instance_id]
		for gid in held.keys():
			var want := int(held[gid])
			if want <= 0:
				held.erase(gid)
				continue
			var placed: int = Stockpile.add(tile_id, str(gid), want)
			if placed > 0:
				held[gid] = want - placed
			if int(held.get(gid, 0)) <= 0:
				held.erase(gid)
		if held.is_empty():
			ghost_holdings.erase(instance_id)
		else:
			ghost_holdings[instance_id] = held


## Domestic freight the founder pre-paid: units of overland haulage that cost the player
## nothing. Consumed by TransportService before any charge is raised, so it shows up as
## genuinely free movement rather than a rebate. The COO gift.
var freight_credit_units: int = 0

func add_freight_credit(units: int) -> void:
	if units <= 0:
		return
	freight_credit_units += units
	advisors_changed.emit()

## Spend up to `units` of credit; returns how many were covered (0 when exhausted).
func consume_freight_credit(units: int) -> int:
	if freight_credit_units <= 0 or units <= 0:
		return 0
	var used := mini(freight_credit_units, units)
	freight_credit_units -= used
	return used


## How much WOULD be covered, without spending it. Quotes, previews and the build forecast
## must use this — they call the same costing path as a real shipment, and consuming there
## would drain the gift by looking at it.
func peek_freight_credit(units: int) -> int:
	if freight_credit_units <= 0 or units <= 0:
		return 0
	return mini(freight_credit_units, units)


## Which posts the company can fill. Only CFO and COO exist until the people/labour research
## node opens the rest — see docs/early-game-onboarding-spec.md §5.4.
func is_seat_available(seat_id: String) -> bool:
	return advisors_unlocked or all_seats_unlocked or BASE_SEATS.has(seat_id)


func available_seat_ids() -> Array[String]:
	var out: Array[String] = []
	for seat_id in SEAT_DEFINITIONS:
		if is_seat_available(str(seat_id)):
			out.append(str(seat_id))
	return out


## Has the founder's pro bono tenure run out? True when he never joined at all.
func founder_tenure_expired() -> bool:
	return founder_seat == "" or TurnManager.current_turn >= founder_leaves_turn


## Andrew joins pro bono for FOUNDER_TENURE_TURNS, in whichever post the player picked.
func seat_founder(seat_id: String) -> bool:
	if not SEAT_DEFINITIONS.has(seat_id):
		return false
	if not recruited_advisor_ids.has(FOUNDER_ADVISOR_ID):
		recruited_advisor_ids.append(FOUNDER_ADVISOR_ID)
	if not permanent_advisor_ids.has(FOUNDER_ADVISOR_ID):
		permanent_advisor_ids.append(FOUNDER_ADVISOR_ID)
	founder_seat = seat_id
	founder_leaves_turn = TurnManager.current_turn + FOUNDER_TENURE_TURNS
	var ok := assign_advisor_to_seat(seat_id, FOUNDER_ADVISOR_ID)
	if not ok:
		founder_seat = ""
		founder_leaves_turn = 0
	return ok


## Tenure over: he vacates and the post opens for a normal hire.
func release_founder() -> void:
	if founder_seat == "":
		return
	if str(advisor_seats.get(founder_seat, "")) == FOUNDER_ADVISOR_ID:
		advisor_seats.erase(founder_seat)
	permanent_advisor_ids.erase(FOUNDER_ADVISOR_ID)
	recruited_advisor_ids.erase(FOUNDER_ADVISOR_ID)
	founder_seat = ""
	founder_leaves_turn = 0
	reconcile_advisor_modifiers()
	advisors_changed.emit()


func assign_advisor_to_seat(seat_id: String, advisor_id: String) -> bool:
	if not SEAT_DEFINITIONS.has(seat_id):
		return false
	if not is_seat_available(seat_id):
		return false
	if _roster_entry(advisor_id).is_empty():
		return false
	if not permanent_advisor_ids.has(advisor_id):
		return false
	# The founder's post is his for the tenure — vacating it out from under him is the one
	# reassignment the council refuses.
	if founder_seat != "" and seat_id == founder_seat and advisor_id != FOUNDER_ADVISOR_ID \
			and not founder_tenure_expired():
		return false
	# Capacity gate. An advisor who ALREADY holds a seat is moving, not arriving: the loop below
	# vacates their old seat, so the seat count does not grow and the cap must not refuse them.
	# Without this exemption, re-seating anyone silently failed once the council was full — the
	# caller saw `false`, dropped back to the roster, and the advisor stayed in their previous
	# role, which is exactly the "I hired them for one role and they went to another" report.
	var takes_new_slot := not advisor_seats.has(seat_id)
	if takes_new_slot:
		for held in advisor_seats:
			if str(advisor_seats[held]) == advisor_id:
				takes_new_slot = false
				break
	if takes_new_slot and advisor_seats.size() >= max_advisor_slots:
		return false
	# One seat per advisor: vacate any other seat this advisor currently holds.
	for existing_seat in advisor_seats.keys():
		if existing_seat != seat_id and str(advisor_seats[existing_seat]) == advisor_id:
			advisor_seats.erase(existing_seat)
	advisor_seats[seat_id] = advisor_id
	reconcile_advisor_modifiers()
	advisors_changed.emit()
	return true

func unassign_seat(seat_id: String) -> bool:
	if not advisor_seats.has(seat_id):
		return false
	advisor_seats.erase(seat_id)
	reconcile_advisor_modifiers()
	advisors_changed.emit()
	return true

func get_advisor_in_seat(seat_id: String) -> String:
	return str(advisor_seats.get(seat_id, ""))

# People-management unlock primitive: raise the seat cap toward MAX_ADVISOR_SLOTS_CAP.
# The build-count trigger that CALLS this is wired in the acquisition increment.
func unlock_advisor_slot() -> void:
	max_advisor_slots = mini(max_advisor_slots + 1, MAX_ADVISOR_SLOTS_CAP)
	advisors_changed.emit()

# Drop seats pointing at an unknown seat_id or an un-rostered advisor, and dedupe
# so an advisor never holds two seats. Keeps valid entries (no silent emptying).
func _sanitize_advisor_seats(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not (raw is Dictionary):
		return out
	var seen: Dictionary = {}
	for seat_id in (raw as Dictionary).keys():
		var sid := str(seat_id)
		var aid := str((raw as Dictionary)[seat_id])
		if not SEAT_DEFINITIONS.has(sid):
			continue
		if _roster_entry(aid).is_empty():
			continue
		if seen.has(aid):
			continue
		out[sid] = aid
		seen[aid] = true
	return out

# Idempotent bridge to ModifierState. Removes ALL prior advisor-seat modifiers
# (clearing stale/vacated seats) then re-adds one per occupied seat with a stable
# id (advisor_seat_<seat_id>) so a re-run replaces rather than duplicates. Called
# on seat change, reset, and load (the latter from save_load AFTER Modifiers import).
# Each seat's FREE-lever effects (_SEAT_EFFECTS) are emitted as domain modifiers
# scaled by the governing tier; seats whose levers are Phase 2+ emit nothing yet.
# The concrete modifier effects an advisor would provide in a given seat, each as
# {domain, pct} with pct already scaled by their governing tier (empty if the seat
# has no effects or the advisor would be inert there).
func advisor_seat_effect_list(advisor_id: String, seat_id: String) -> Array:
	var mult: float = float(_TIER_MULT.get(advisor_seat_tier(advisor_id, seat_id), 0.0))
	var out: Array = []
	if mult == 0.0:
		return out
	for eff in _SEAT_EFFECTS.get(seat_id, []):
		var pct: float = float(eff.get("base_pct", 0.0)) * mult
		if pct != 0.0:
			out.append({"domain": str(eff.get("domain", "")), "pct": pct})
	return out


## A deliberately simple, legible cash snapshot for the council UI: value only the
## POSITIVE seat effects against the last completed turn's matching ledger line. It
## is not a forecast — if the company paid no tax or freight that turn, a reduction
## to that cost is worth £0 in this snapshot. One-off/non-ledger levers (construction,
## purchases and throughput headroom) likewise stay at £0 rather than inventing value.
func advisor_bonus_preview_per_turn(advisor_id: String, seat_id: String, snapshot: Dictionary = {}) -> float:
	var summary: Dictionary = Production.last_turn_summary if snapshot.is_empty() else snapshot
	var total := 0.0
	for effect in advisor_seat_effect_list(advisor_id, seat_id):
		var eff: Dictionary = effect
		if not advisor_effect_is_beneficial(eff):
			continue
		var pct := absf(float(eff.get("pct", 0.0))) / 100.0
		var domain := str(eff.get("domain", ""))
		var basis := 0.0
		match domain:
			"labour_headcount":
				basis = float(summary.get("labour_paid", 0.0))
			"maintenance":
				basis = float(summary.get("maintenance_paid", 0.0))
			"building_power":
				basis = float(summary.get("power_purchase_cost", 0.0))
			"grid_buy_price":
				# The tariff modifier does not discount the grid's carbon component.
				basis = float(summary.get("grid_bought", 0.0)) * EconomyConfig.GRID_BUY_PRICE
			"grid_sell_price":
				basis = float(summary.get("grid_sold", 0.0)) * EconomyConfig.GRID_SELL_PRICE
			"transport_cost":
				basis = float(summary.get("transport_paid", 0.0))
			"dividend_rate":
				basis = float(summary.get("dividends_paid", 0.0))
			"tax_rate":
				basis = float(summary.get("taxes_paid", 0.0))
			"market_spread":
				# Only the buy markup is tightened, not the underlying value of the goods.
				var markup := EconomyConfig.MARKET_BUY_MARKUP
				basis = float(summary.get("goods_purchased_cost", 0.0)) * markup / (1.0 + markup)
			"market_price":
				basis = float(summary.get("goods_sales_revenue", 0.0))
		total += maxf(0.0, basis) * pct
	return total


## Sign alone does not say whether a seat effect helps: lower costs are good,
## while higher throughput, sale prices and rebates are good.
func advisor_effect_is_beneficial(effect: Dictionary) -> bool:
	var pct := float(effect.get("pct", 0.0))
	var domain := str(effect.get("domain", ""))
	var positive_is_good := domain in [
		"transport_throughput", "grid_sell_price", "construction_rebate", "market_price"]
	return pct > 0.0 if positive_is_good else pct < 0.0

# The seat this advisor best demonstrates: their assigned seat if seated, else the
# highest-tier seat that actually carries effects (falls back to their top seat).
func advisor_best_effect_seat(advisor_id: String) -> String:
	for sid in advisor_seats:
		if str(advisor_seats[sid]) == advisor_id:
			return str(sid)
	var best_seat := ""
	var best_tier := -1
	for sid in SEAT_DEFINITIONS:
		if not is_seat_available(str(sid)):
			continue  # a locked seat never becomes an advisor's shown "best" seat
		var t: int = advisor_seat_tier(advisor_id, str(sid))
		var has_fx: bool = not _SEAT_EFFECTS.get(str(sid), []).is_empty()
		# Prefer seats that carry effects; among those, the highest tier.
		var score: int = t + (100 if has_fx else 0)
		if score > best_tier:
			best_tier = score
			best_seat = str(sid)
	return best_seat

func reconcile_advisor_modifiers() -> void:
	for m in Modifiers.active():
		var mid := str(m.get("id", ""))
		if mid.begins_with("advisor_seat_"):
			Modifiers.remove(mid)
	for seat_id in advisor_seats.keys():
		var advisor_id := str(advisor_seats[seat_id])
		if _roster_entry(advisor_id).is_empty():
			continue
		var tier: int = advisor_seat_tier(advisor_id, str(seat_id))
		var tier_mult: float = float(_TIER_MULT.get(tier, 0.0))
		if tier_mult == 0.0:
			continue
		var seat_name := str(SEAT_DEFINITIONS.get(seat_id, {}).get("seat_name", seat_id))
		for eff in _SEAT_EFFECTS.get(seat_id, []):
			var pct: float = float(eff.get("base_pct", 0.0)) * tier_mult
			if pct == 0.0:
				continue
			Modifiers.add({
				"id": "advisor_seat_%s_%s" % [seat_id, str(eff.get("domain", ""))],
				"domain": str(eff.get("domain", "")),
				"pct": pct,
				"label": "%s: %s (tier %d)" % [seat_name, advisor_id, tier],
				"source": "advisor_seat",
			})
	_revoke_unavailable_workforce_policies()

# Switch off any HR-gated workforce policy whose advisor requirement is no longer met
# (e.g. the HR Director was un-seated or fired) so the benefit can't outlive the seat.
func _revoke_unavailable_workforce_policies() -> void:
	for pid in [WORKFORCE_POLICY_LONG_TENURE, WORKFORCE_POLICY_STOCK_OPTIONS]:
		if is_workforce_policy_enabled(pid) and not is_workforce_policy_available(pid):
			set_workforce_policy_enabled(pid, false)

func _match_rng_int(max_exclusive: int) -> int:
	if max_exclusive <= 0:
		return 0
	return _match_rng.randi_range(0, max_exclusive - 1)

# Canonical ids not yet recruited (draw-without-replacement, spec §4.3).
func _advisor_draw_pool() -> Array:
	var out: Array = []
	for a in ADVISOR_ROSTER:
		var id := str(a.get("id", ""))
		if not advisors_unlocked and not DEMO_ADVISORS.has(id):
			continue  # only the three demo advisors exist until `unlock advisors`
		if not recruited_advisor_ids.has(id):
			out.append(id)
	return out

# Recruit one random advisor into the available pool (seeded; deterministic).
# Recruiting UNLOCKS an advisor; you still employ up to max_advisor_slots.
func draw_advisor_from_pool() -> String:
	var pool := _advisor_draw_pool()
	if pool.is_empty():
		return ""
	var picked := str(pool[_match_rng_int(pool.size())])
	recruited_advisor_ids.append(picked)
	advisor_acquired.emit(picked)
	advisors_changed.emit()
	return picked

# Debug cheat: add cash, tracked as "fake money" for the turn summary.
func cheat_add_cash(amount: float) -> void:
	add_money(amount)
	fake_money_this_turn += amount

## Sticky taint flag for telemetry — set by the debug terminal for any command that can
## move the sim. Once set it rides the save for the rest of the match.
func note_cheat_used() -> void:
	cheats_used = true

# The next un-crossed profit milestone (advisor recruit), or 0 if all crossed.
func next_advisor_milestone() -> int:
	for m in PROFIT_MILESTONES:
		if not crossed_milestones.has(m):
			return int(m)
	return 0

# Award one advisor on the first crossing of each profit-per-turn milestone (latched).
func check_profit_milestones(profit_per_turn: float) -> void:
	for m in PROFIT_MILESTONES:
		if crossed_milestones.has(m):
			continue
		if profit_per_turn >= float(m):
			crossed_milestones.append(m)
			draw_advisor_from_pool()

func player_building_count() -> int:
	var n := 0
	for b in buildings.values():
		if b is Dictionary and is_player_owned(b):
			n += 1
	return n

# Advisor employ-slots unlock monotonically: 3rd at ADVISOR_SLOT_BUILDINGS_3 buildings,
# 4th at ADVISOR_SLOT_BUILDINGS_4, 5th after ADVISOR_SLOT_PROFIT_STREAK consecutive turns
# at >= ADVISOR_SLOT_PROFIT_5 profit/turn. Once earned a slot is kept.
func _update_advisor_slots(profit_per_turn: float) -> void:
	if profit_per_turn >= ADVISOR_SLOT_PROFIT_5:
		_advisor_profit_streak += 1
	else:
		_advisor_profit_streak = 0
	if _advisor_profit_streak >= ADVISOR_SLOT_PROFIT_STREAK:
		advisor_slot_profit_unlocked = true
	var bldgs := player_building_count()
	var target := MAX_ADVISOR_SLOTS_DEFAULT
	if bldgs >= ADVISOR_SLOT_BUILDINGS_3:
		target += 1
		grant_unlock("Third Advisor Seat")
	if bldgs >= ADVISOR_SLOT_BUILDINGS_4:
		target += 1
		grant_unlock("Fourth Advisor Seat")
	if advisor_slot_profit_unlocked:
		target += 1
		grant_unlock("Fifth Advisor Seat")
	var new_cap: int = mini(maxi(max_advisor_slots, target), MAX_ADVISOR_SLOTS_CAP)
	if new_cap != max_advisor_slots:
		max_advisor_slots = new_cap
		advisors_changed.emit()

func _on_turn_processed_advisors(summary: Dictionary) -> void:
	# Include cheat "fake money" so the cash cheat can drive advisor unlocks in testing.
	var profit := float(summary.get("money_in", 0.0)) - float(summary.get("money_out", 0.0)) + float(summary.get("fake_money", 0.0))
	peak_profit_per_turn = maxf(peak_profit_per_turn, profit)
	_tick_fire_cooldowns()
	_evaluate_agendas(summary, profit)
	_update_advisor_slots(profit)
	check_profit_milestones(profit)

# --- Advisor loyalty / churn ------------------------------------------------

func advisor_loyalty_value(advisor_id: String) -> float:
	return float(advisor_loyalty.get(advisor_id, 0.0))

# Loyalty magnitude for an event, given whether it's a like or a dislike for the
# advisor: per-turn likes +0.6 / dislikes 0.4; one-off actions a full 1.0.
func _agenda_points(tag: String, benefit: bool) -> float:
	if bool((AGENDA_META.get(tag, {}) as Dictionary).get("per_turn", false)):
		return AGENDA_LIKE_PER_TURN if benefit else AGENDA_DISLIKE_PER_TURN
	return AGENDA_ONE_OFF

# The concrete loyalty drivers for an advisor's Agenda display: one row per like /
# dislike with signed points, the plain-English action, and whether it applies each turn.
func advisor_agenda_rows(advisor_id: String) -> Array:
	var agenda: Dictionary = ADVISOR_AGENDAS.get(advisor_id, {})
	var rows: Array = []
	for tag in agenda.get("likes", []):
		var meta: Dictionary = AGENDA_META.get(str(tag), {})
		rows.append({"points": _agenda_points(str(tag), true), "text": str(meta.get("text", tag)), "per_turn": bool(meta.get("per_turn", false)), "benefit": true})
	for tag in agenda.get("dislikes", []):
		var meta2: Dictionary = AGENDA_META.get(str(tag), {})
		rows.append({"points": -_agenda_points(str(tag), false), "text": str(meta2.get("text", tag)), "per_turn": bool(meta2.get("per_turn", false)), "benefit": false})
	return rows

# Called from hook sites during a turn to record that an agenda event happened.
func flag_agenda_event(tag: String) -> void:
	_agenda_flags[tag] = true

# Record a build this turn (drives the idle-building + build-while-unprofitable agendas).
func note_building_built() -> void:
	_agenda_last_build_turn = int(TurnManager.current_turn)
	_agenda_flags["_built"] = true

## Decision-event loyalty (decision-events-spec.md §6.2): +0.5 local / +2.0 company
## for following an advocating advisor, −0.5 for ignoring one. Routed through
## _set_advisor_loyalty with mission checks ON, so a big follow can complete a
## mission milestone and serial snubs walk an advisor exactly like agenda decay.
func apply_decision_loyalty(advisor_id: String, delta: float, decision_title: String) -> void:
	if _roster_entry(advisor_id).is_empty() or not permanent_advisor_ids.has(advisor_id):
		return
	_set_advisor_loyalty(advisor_id, advisor_loyalty_value(advisor_id) + delta)
	print("[Decisions] %s loyalty %+.1f (%s)" % [advisor_id, delta, decision_title])
	advisors_changed.emit()

# Debug cheat: nudge an advisor's loyalty by delta, clamped to [-10, 10].
func cheat_set_loyalty(advisor_id: String, delta: float) -> void:
	if _roster_entry(advisor_id).is_empty():
		return
	_set_advisor_loyalty(advisor_id, advisor_loyalty_value(advisor_id) + delta)
	advisors_changed.emit()

func _set_advisor_loyalty(advisor_id: String, value: float, check_missions: bool = true) -> bool:
	var old_value := advisor_loyalty_value(advisor_id)
	var next_value := clampf(value, LOYALTY_MIN, LOYALTY_MAX)
	advisor_loyalty[advisor_id] = next_value
	var loyalty_changed := not is_equal_approx(old_value, next_value)
	var mission_changed := _check_mission_progress(advisor_id) if check_missions else false
	if loyalty_changed:
		advisor_loyalty_changed.emit(advisor_id, next_value)
	return loyalty_changed or mission_changed

# Which agenda events fired this turn (flagged hooks + summary-derived + streaks).
func _collect_agenda_events(summary: Dictionary, profit: float) -> Dictionary:
	var ev: Dictionary = {}
	for tag in _agenda_flags:
		ev[tag] = true
	if profit > 0.0:
		ev[AGENDA_MADE_PROFIT] = true
	if float(summary.get("power_purchase_cost", 0.0)) > 0.0:
		ev[AGENDA_BOUGHT_GRID_POWER] = true
	var bought_materials: bool = float(summary.get("goods_purchased_cost", 0.0)) > 0.0
	if bought_materials:
		ev[AGENDA_BOUGHT_MATERIALS] = true
	# Grid-sell streak (5 consecutive turns exporting power).
	_agenda_grid_sell_streak = _agenda_grid_sell_streak + 1 if float(summary.get("power_sales_revenue", 0.0)) > 0.0 else 0
	if _agenda_grid_sell_streak >= 5:
		ev[AGENDA_SOLD_GRID_POWER] = true
	# Autarky streak (no market input buys, 3 turns in a row).
	_agenda_no_buy_streak = 0 if bought_materials else _agenda_no_buy_streak + 1
	if _agenda_no_buy_streak >= 3:
		ev[AGENDA_AUTARKIC] = true
	if _agenda_flags.has("_built") and profit < 0.0:
		ev[AGENDA_BUILT_UNPROFITABLE] = true
	if int(TurnManager.current_turn) - _agenda_last_build_turn > 10:
		ev[AGENDA_IDLE_BUILDING] = true
	if _count_enabled_workforce_policies() >= 2:
		ev[AGENDA_LABOUR_POLICIES] = true
	return ev

func _count_enabled_workforce_policies() -> int:
	var n := 0
	for pid in workforce_policies:
		if bool(workforce_policies[pid]):
			n += 1
	return n

# Decay every employed advisor's loyalty toward 0, apply this turn's agenda events,
# then walk anyone stuck at/below the threshold for LOYALTY_WALK_TURNS running turns.
func _evaluate_agendas(summary: Dictionary, profit: float) -> void:
	var events: Dictionary = _collect_agenda_events(summary, profit)
	for aid in permanent_advisor_ids:
		var agenda: Dictionary = ADVISOR_AGENDAS.get(aid, {})
		var v: float = advisor_loyalty_value(aid)
		if v > 0.0:
			v = maxf(0.0, v - LOYALTY_DECAY)
		elif v < 0.0:
			v = minf(0.0, v + LOYALTY_DECAY)
		for tag in agenda.get("likes", []):
			if events.has(tag):
				v += _agenda_points(str(tag), true)
		for tag in agenda.get("dislikes", []):
			if events.has(tag):
				v -= _agenda_points(str(tag), false)
		_set_advisor_loyalty(aid, v)
		if advisor_loyalty_value(aid) <= LOYALTY_WALK_THRESHOLD:
			_advisor_walk_streak[aid] = int(_advisor_walk_streak.get(aid, 0)) + 1
		else:
			_advisor_walk_streak[aid] = 0
	# Walk in a second pass (walking mutates permanent_advisor_ids).
	var walkers: Array = []
	for aid in permanent_advisor_ids:
		if int(_advisor_walk_streak.get(aid, 0)) >= LOYALTY_WALK_TURNS:
			walkers.append(aid)
	for aid in walkers:
		_advisor_walk(str(aid))
	_agenda_flags.clear()

# --- Advisor missions (rewards delivered as loyalty milestones are reached) --------

func advisor_missions_done(advisor_id: String) -> int:
	return int(advisor_missions_completed.get(advisor_id, 0))

# Advance missions once per turn. I–IV complete the first turn loyalty reaches their
# threshold; V requires loyalty to hold at/above MISSION5_LOYALTY for MISSION5_STREAK_TURNS.
func _check_mission_progress(advisor_id: String) -> bool:
	if MISSION_TEMPLATES.get(str(_roster_entry(advisor_id).get("role", "")), {}).is_empty():
		return false
	var done := advisor_missions_done(advisor_id)
	var loyalty := advisor_loyalty_value(advisor_id)
	var changed := false
	var old_streak := int(_advisor_mission5_streak.get(advisor_id, 0))
	# Missions I–IV: single-hit loyalty thresholds [2, 5, 7, 9].
	while done < MISSION_LOYALTY_THRESHOLDS.size() and loyalty >= float(MISSION_LOYALTY_THRESHOLDS[done]):
		done += 1
		advisor_missions_completed[advisor_id] = done
		_grant_mission_reward(advisor_id, done)
		changed = true
	# Mission V: sustained high loyalty streak.
	if done < MISSION_COUNT:
		if loyalty >= MISSION5_LOYALTY:
			_advisor_mission5_streak[advisor_id] = int(_advisor_mission5_streak.get(advisor_id, 0)) + 1
		else:
			_advisor_mission5_streak[advisor_id] = 0
		if int(_advisor_mission5_streak.get(advisor_id, 0)) != old_streak:
			changed = true
	if done == MISSION_LOYALTY_THRESHOLDS.size() and int(_advisor_mission5_streak.get(advisor_id, 0)) >= MISSION5_STREAK_TURNS:
		advisor_missions_completed[advisor_id] = MISSION_COUNT
		_grant_mission_reward(advisor_id, MISSION_COUNT)
		changed = true
	if changed:
		advisor_mission_state_changed.emit(advisor_id)
	return changed

# Mission indices are 1-based (I..V). Mirrors the reward layout in MISSION_TEMPLATES.
func _grant_mission_reward(advisor_id: String, mission_num: int) -> void:
	var tmpl: Dictionary = MISSION_TEMPLATES.get(str(_roster_entry(advisor_id).get("role", "")), {})
	if tmpl.is_empty():
		return
	var label := ""
	match mission_num:
		1:
			label = _apply_mission_temp(advisor_id, 1, tmpl.get("temp", {}))
		2:
			label = _apply_mission_perm(advisor_id, 2, tmpl.get("perm1", {}))
		3:
			var parts: Array = []
			var research_title := grant_first_locked_in_category(str(tmpl.get("research_category", "")))
			if research_title != "":
				parts.append("free research: %s" % research_title)
			if tmpl.has("temp2"):
				parts.append(_apply_mission_temp(advisor_id, 3, tmpl.get("temp2", {})))
			label = " + ".join(parts) if not parts.is_empty() else "no new reward"
		4:
			label = _apply_mission_perm(advisor_id, 4, tmpl.get("perm2", {}))
		5:
			var cap: Dictionary = tmpl.get("capstone", {})
			if cap.has("policy"):
				label = _apply_mission_policy(str(cap.get("policy", "")), str(cap.get("label", "")))
			else:
				label = _apply_mission_perm(advisor_id, 5, cap)
	advisor_mission_completed.emit(advisor_id, mission_num, label)
	request_toast("%s reached mission %s — %s" % [str(get_advisor(advisor_id).get("name", advisor_id)), _roman(mission_num), label], "success")

func _roman(n: int) -> String:
	return ["", "I", "II", "III", "IV", "V"][clampi(n, 0, 5)]

# A temporary specialty modifier (duration_turns). Distinct ids so a re-trigger refreshes.
func _apply_mission_temp(advisor_id: String, mission_num: int, spec: Dictionary) -> String:
	if spec.is_empty():
		return ""
	Modifiers.add({
		"id": "advisor_mission_temp_%s_%d" % [advisor_id, mission_num],
		"domain": str(spec.get("domain", "")),
		"pct": float(spec.get("pct", 0.0)),
		"label": "Mission (%s): %s" % [advisor_id, str(spec.get("label", ""))],
		"source": "advisor_mission",
		"duration_turns": int(spec.get("turns", 20)),
	})
	return str(spec.get("label", ""))

# A permanent seat-effect slice that persists even when the advisor is unseated.
func _apply_mission_perm(advisor_id: String, mission_num: int, spec: Dictionary) -> String:
	if spec.is_empty():
		return ""
	Modifiers.add({
		"id": "advisor_mission_perm_%s_%d" % [advisor_id, mission_num],
		"domain": str(spec.get("domain", "")),
		"pct": float(spec.get("pct", 0.0)),
		"label": "Mission (%s): %s" % [advisor_id, str(spec.get("label", ""))],
		"source": "advisor_mission",
	})
	return str(spec.get("label", ""))

func _apply_mission_policy(policy_id: String, label: String) -> String:
	if policy_id != "" and not advisor_mission_policies.has(policy_id):
		advisor_mission_policies.append(policy_id)
		workforce_policies_changed.emit()
	return label

# Re-apply the PERMANENT mission rewards (perm slices + the capstone) after a load,
# based on how many missions each advisor has completed. Temp bonuses aren't restored.
func reapply_mission_modifiers() -> void:
	for advisor_id in advisor_missions_completed:
		var tmpl: Dictionary = MISSION_TEMPLATES.get(str(_roster_entry(str(advisor_id)).get("role", "")), {})
		if tmpl.is_empty():
			continue
		var done := int(advisor_missions_completed[advisor_id])
		if done >= 2:
			_apply_mission_perm(str(advisor_id), 2, tmpl.get("perm1", {}))
		if done >= 4:
			_apply_mission_perm(str(advisor_id), 4, tmpl.get("perm2", {}))
		if done >= 5:
			var cap: Dictionary = tmpl.get("capstone", {})
			if cap.has("policy"):
				_apply_mission_policy(str(cap.get("policy", "")), str(cap.get("label", "")))
			else:
				_apply_mission_perm(str(advisor_id), 5, cap)

func _advisor_walk(advisor_id: String) -> void:
	advisor_loyalty.erase(advisor_id)
	_advisor_walk_streak.erase(advisor_id)
	fire_advisor(advisor_id)          # unseat + bench (10-turn cooldown), like a firing
	request_toast("%s has resigned — loyalty stayed critically low." % str(get_advisor(advisor_id).get("name", advisor_id)), "warning")
	advisor_walked.emit(advisor_id)

func advisor_pool() -> Array:
	var out: Array = []
	for advisor in _advisor_definitions():
		if advisor is Dictionary:
			out.append((advisor as Dictionary).duplicate(true))
	return out

func get_advisor(advisor_id: String) -> Dictionary:
	for advisor in _advisor_definitions():
		if advisor is Dictionary and str(advisor.get("id", "")) == advisor_id:
			return (advisor as Dictionary).duplicate(true)
	return {}

func permanent_advisors() -> Array:
	var out: Array = []
	for advisor_id in permanent_advisor_ids:
		var advisor := get_advisor(str(advisor_id))
		if not advisor.is_empty():
			out.append(advisor)
	return out

func available_advisors() -> Array:
	# Recruited (unlocked) advisors you have not employed yet.
	var out: Array = []
	for advisor_id in recruited_advisor_ids:
		if permanent_advisor_ids.has(str(advisor_id)):
			continue
		var a := get_advisor(str(advisor_id))
		if not a.is_empty():
			out.append(a)
	return out

# Employ a recruited advisor. Capped at max_advisor_slots (spec §4.1).
func hire_advisor(advisor_id: String) -> bool:
	if advisor_id == "" or permanent_advisor_ids.has(advisor_id) or get_advisor(advisor_id).is_empty():
		return false
	if not recruited_advisor_ids.has(advisor_id):
		return false
	if fired_advisor_cooldowns.has(advisor_id):
		return false
	if permanent_advisor_ids.size() >= max_advisor_slots:
		return false
	permanent_advisor_ids.append(advisor_id)
	advisor_loyalty[advisor_id] = 0.0          # loyalty starts neutral on hire
	# Decision-gate tenure: a fresh hire counts only from the NEXT turn, so a live
	# dilemma can't be unlocked by panic-hiring (decision-events-spec.md §5.1).
	advisor_hired_turn[advisor_id] = int(TurnManager.current_turn)
	_advisor_walk_streak.erase(advisor_id)
	advisors_changed.emit()
	return true

## True when the advisor is employed AND was hired on an earlier turn than the
## current one — the eligibility bar for decision gates and advocacy.
func is_advisor_tenured(advisor_id: String) -> bool:
	if not permanent_advisor_ids.has(advisor_id):
		return false
	return int(TurnManager.current_turn) > int(advisor_hired_turn.get(advisor_id, -1))

func is_fired(advisor_id: String) -> bool:
	return fired_advisor_cooldowns.has(advisor_id)

# Turns until a fired advisor returns to the hireable pool (0 = not on cooldown).
func fire_cooldown_remaining(advisor_id: String) -> int:
	return int(fired_advisor_cooldowns.get(advisor_id, 0))

# Dismiss an employed advisor: unseat them, free the slot, and bench them for
# FIRE_COOLDOWN_TURNS turns (greyed + unhireable in the pool) before they return.
func fire_advisor(advisor_id: String) -> bool:
	if not permanent_advisor_ids.has(advisor_id):
		return false
	permanent_advisor_ids.erase(advisor_id)
	advisor_loyalty.erase(advisor_id)
	advisor_hired_turn.erase(advisor_id)
	_advisor_walk_streak.erase(advisor_id)
	for seat_id in advisor_seats.keys():
		if str(advisor_seats[seat_id]) == advisor_id:
			advisor_seats.erase(seat_id)
	fired_advisor_cooldowns[advisor_id] = FIRE_COOLDOWN_TURNS
	reconcile_advisor_modifiers()
	advisors_changed.emit()
	return true

# Tick each turn: count down suspensions; advisors hitting 0 rejoin the pool.
func _tick_fire_cooldowns() -> void:
	if fired_advisor_cooldowns.is_empty():
		return
	var returned := false
	for advisor_id in fired_advisor_cooldowns.keys():
		var remaining := int(fired_advisor_cooldowns[advisor_id]) - 1
		if remaining <= 0:
			fired_advisor_cooldowns.erase(advisor_id)
			returned = true
		else:
			fired_advisor_cooldowns[advisor_id] = remaining
	if returned:
		advisors_changed.emit()

## What ONE advisor costs this turn: a flat base that inflates at double the labour rate, plus
## a share of company revenue (EconomyConfig, owner spec 2026-08-01). Per-advisor rather than
## per-council, because the revenue share is charged once for each of them.
## `revenue` is the turn's goods + power sales; pass 0.0 for the base-only figure.
func advisor_cost_per_advisor(revenue: float = 0.0) -> float:
	var t: int = maxi(1, int(TurnManager.current_turn))
	var base: float = EconomyConfig.ADVISOR_BASE_COST_PER_TURN \
		* pow(1.0 + EconomyConfig.ADVISOR_COST_GROWTH, float(t - 1))
	return base + maxf(0.0, revenue) * EconomyConfig.ADVISOR_REVENUE_SHARE


## Revenue the advisor share is taken from — the same goods + power sales figure tax uses, read
## off the last resolved turn so the council panel and the ledger quote one number.
func advisor_revenue_basis() -> float:
	var s: Dictionary = Production.last_turn_summary
	return float(s.get("goods_sales_revenue", 0.0)) + float(s.get("power_sales_revenue", 0.0))


## Andrew's family-friend appointment is explicitly pro bono for its whole tenure.
## Keep the exception here, at the source of truth used by both payroll and the UI,
## rather than relying on the roster's retired static salary field.
func advisor_is_payrolled(advisor_id: String) -> bool:
	return permanent_advisor_ids.has(advisor_id) \
		and not (advisor_id == FOUNDER_ADVISOR_ID and founder_seat != "")


func payrolled_advisor_count() -> int:
	var count := 0
	for raw_id in permanent_advisor_ids:
		if advisor_is_payrolled(str(raw_id)):
			count += 1
	return count


func advisor_cost_for(advisor_id: String, revenue: float = -1.0) -> float:
	if permanent_advisor_ids.has(advisor_id) and not advisor_is_payrolled(advisor_id):
		return 0.0
	var rev: float = advisor_revenue_basis() if revenue < 0.0 else revenue
	return advisor_cost_per_advisor(rev)


func advisor_payroll_per_turn(revenue: float = -1.0) -> float:
	var rev: float = advisor_revenue_basis() if revenue < 0.0 else revenue
	return float(payrolled_advisor_count()) * advisor_cost_per_advisor(rev)

func _sanitize_advisor_ids(ids: Variant) -> Array:
	var valid := {}
	for advisor in _advisor_definitions():
		if advisor is Dictionary:
			valid[str(advisor.get("id", ""))] = true
	var out: Array = []
	if not (ids is Array):
		return out
	for raw_id in ids:
		var advisor_id := str(raw_id)
		if valid.has(advisor_id) and not out.has(advisor_id):
			out.append(advisor_id)
	return out

# Display fields for the 12 canonical advisors (ADVISOR_ROSTER holds the stats).
# accent is a hex string (const-safe; converted to Color at build time). Only 4
# portrait PNGs exist (spec §11 stub art); the rest fall back to accent+initials.
const ADVISOR_DISPLAY := {
	# The family friend. Added to ADVISOR_ROSTER without a presentation entry, which is what
	# crashed the advisors tab when he was clicked — every other reader of this table assumes
	# one exists for anyone on the roster.
	"andrew":   {"initials": "AK", "portrait_path": "res://assets/advisors/andrew.png", "accent": "#6B7F5A", "bonus": "Out of Retirement: serves 30 turns unpaid, in one of two chairs", "recommendation": "Free, capable, and temporary — take the seat you need most for the next 30 turns.", "bio": "Ran a shipping firm for thirty years and retired from it two years ago, which he has found to be one and a half years too many. He is not here for the money.", "agenda": "Get the working life out of his system, then go back to the garden.", "likes": ["Being useful", "Cheap freight"], "dislikes": ["Being kept past his welcome"], "bonuses": ["No salary for his tenure", "A signing gift in either chair"]},
	"vera":      {"initials": "VA", "portrait_path": "res://assets/advisors/natasha.png", "accent": "#7C5A80", "bonus": "Family Trust: cheap, steady, strong almost anywhere", "recommendation": "Your reliable keystone — she holds any seat well.", "bio": "Your sister and the steady hand on the board: numerate, unflappable, and very hard to surprise twice.", "agenda": "Anchor the board and keep every seat competently filled.", "likes": ["Steady growth", "A balanced board"], "dislikes": ["Reckless bets", "Idle capital"], "bonuses": ["Reduced salary", "No weak seat"]},
	"alexandra": {"initials": "AR", "portrait_path": "res://assets/advisors/alexandra.png", "accent": "#8A5A5A", "bonus": "Prima Donna: superb everywhere, high salary + walk-risk", "recommendation": "A top hire who forces a full board reshuffle when she arrives.", "bio": "A rival operator good enough at everything to make your whole board nervous — and she knows her price.", "agenda": "Be indispensable, be paid, and never be sidelined.", "likes": ["Being centrally slotted", "Ambitious plays"], "dislikes": ["Being benched", "Being under-slotted"], "bonuses": ["Strong in any seat", "Commands a high salary"]},
	"gerald":    {"initials": "GV", "portrait_path": "res://assets/advisors/dan.png", "accent": "#455C78", "bonus": "Dinosaur: superb operator, brakes the green pivot", "recommendation": "Keep him for the throughput; the carbon squeeze makes him a dilemma.", "bio": "A superb pure operator who runs a plant beautifully and fights decarbonisation on instinct.", "agenda": "Maximise output and upkeep; resist the clean transition.", "likes": ["High utilisation", "Cheap fuel"], "dislikes": ["Clean retrofits", "Carbon rules"], "bonuses": ["Excellent COO", "Drags clean adoption"]},
	"eleanor":   {"initials": "ES", "portrait_path": "res://assets/advisors/anita.png", "accent": "#51707A", "bonus": "Beloved: labour + morale, slows churn", "recommendation": "The glue that lets a flawed board function.", "bio": "The diplomat the crews trust — dampens labour spikes and keeps the board from walking.", "agenda": "Keep the workforce and the board loyal.", "likes": ["Fair policies", "A stable board"], "dislikes": ["Layoffs", "Churn"], "bonuses": ["Labour cost down", "Advisor retention"]},
	"sloane":    {"initials": "SV", "portrait_path": "", "accent": "#6E5A86", "bonus": "Slick: best sale prices, quietly toxic", "recommendation": "Your best seller — pair with a strong IR to counter the fallout.", "bio": "The closer. Best sale prices in the business, and quietly toxic to everything that isn't a deal.", "agenda": "Push prices and volume; damn the standing.", "likes": ["Fat margins", "High volume"], "dislikes": ["Slow markets", "HR duty"], "bonuses": ["Better sell prices", "Weak with people"]},
	"priya":     {"initials": "PA", "portrait_path": "res://assets/advisors/priya.png", "accent": "#4F6B58", "bonus": "Idealist: amplifies green, dents near-term profit", "recommendation": "Superb if you're racing Greenest; a cash drain if you're not.", "bio": "A true believer who reaches for the clean option every time, whatever it costs this quarter.", "agenda": "Decarbonise, capture subsidy, win Greenest.", "likes": ["Clean recipes", "Green subsidy"], "dislikes": ["Dirty routes", "Short-termism"], "bonuses": ["Green amplified", "Raises short-term spend"]},
	"hitomi":    {"initials": "HS", "portrait_path": "res://assets/advisors/hitomi.png", "accent": "#7A6A45", "bonus": "Flow State: systems savant, socially inept", "recommendation": "Brilliant on logistics and the line; keep her from people seats.", "bio": "Brilliant with systems, hopeless with people — a logistics and manufacturing savant.", "agenda": "Optimise flow and throughput everywhere.", "likes": ["Tight networks", "Clean processes"], "dislikes": ["Meetings", "People seats"], "bonuses": ["Logistics/mfg boost", "Malus in people seats"]},
	"hal":       {"initials": "HR", "portrait_path": "", "accent": "#5A6F4A", "bonus": "Backroom Deals: regulatory relief at a price", "recommendation": "A real lever if you're staying dirty into the squeeze.", "bio": "The fixer. Buys you time against the regulators, at an ethical price.", "agenda": "Soften the rules and the tax bill.", "likes": ["Loopholes", "Delay"], "dislikes": ["Scrutiny", "Clean mandates"], "bonuses": ["Tax + carbon relief", "Reputation cost"]},
	"tom":       {"initials": "TB", "portrait_path": "res://assets/advisors/lance.png", "accent": "#66513B", "bonus": "Shop-Floor Respect: dependable operations", "recommendation": "Put him near the floor; he flounders near markets or the lab.", "bio": "The old foreman. Dependable operations, no frills, and the crews trust him.", "agenda": "Keep the line running cheaply.", "likes": ["A steady floor", "Trusted crews"], "dislikes": ["Market games", "Lab work"], "bonuses": ["Extra Ops labour cut", "Poor off the floor"]},
	"marcus":    {"initials": "MT", "portrait_path": "res://assets/advisors/marcus.png", "accent": "#765742", "bonus": "Leverage: cheap capital, dangerous debt", "recommendation": "High-risk finance specialist; dangerous outside his lane.", "bio": "A financier who makes capital cheap and acquisitions cheaper — until the debt bites.", "agenda": "Borrow big, buy cheap, grow fast.", "likes": ["Cheap debt", "Acquisitions"], "dislikes": ["Thin reserves", "Operations duty"], "bonuses": ["Cheap capital", "Debt-risk exposure"]},
	"idris":     {"initials": "IK", "portrait_path": "", "accent": "#536C92", "bonus": "Insufferable Genius: brilliant, unbearable", "recommendation": "Atrocious except in the lab — silo him in a TD seat.", "bio": "A brilliant process chemist nobody can stand to work near — keep him in the lab.", "agenda": "Perfect the process; ignore the room.", "likes": ["Hard problems", "Being left alone"], "dislikes": ["Management", "Small talk"], "bonuses": ["Big recipe efficiency", "Empire labour malus unless siloed"]},
	"rufus":     {"initials": "RA", "portrait_path": "", "accent": "#6B6077", "bonus": "Silver Tongue, Empty Suit: one good seat", "recommendation": "Genuinely, and only, a lobbyist.", "bio": "Your cousin. Great in a room, useless everywhere else, riding the family name.", "agenda": "Talk his way through; do as little as possible.", "likes": ["A podium", "Family favour"], "dislikes": ["Real work", "Being found out"], "bonuses": ["Strong lobbyist", "A disaster elsewhere"]},
}

func _seat_display_name(role_id: String) -> String:
	var seat: Dictionary = SEAT_DEFINITIONS.get(role_id, {})
	return str(seat.get("seat_name", role_id.capitalize()))

func _advisor_missions(advisor_id: String, accent_hex: String) -> Array:
	var titles := ["Onboard", "Prove", "Expand", "Master", "Legacy"]
	var colours := [accent_hex, "#536C92", "#4F6B58", "#765742", "#6B6077"]
	var rewards := advisor_mission_reward_labels(advisor_id)
	var done := advisor_missions_done(advisor_id)
	var out: Array = []
	for i in 5:
		var req_text := ""
		if i < MISSION_LOYALTY_THRESHOLDS.size():
			req_text = "at loyalty %d" % int(MISSION_LOYALTY_THRESHOLDS[i])
		else:
			var streak: int = mini(int(_advisor_mission5_streak.get(advisor_id, 0)), MISSION5_STREAK_TURNS)
			req_text = "loyalty %d+ for %d turns (%d/%d)" % [int(MISSION5_LOYALTY), MISSION5_STREAK_TURNS, streak, MISSION5_STREAK_TURNS]
		out.append({
			"roman": _roman(i + 1),
			"title": titles[i],
			"state": "completed" if i < done else ("next" if i == done else "locked"),
			"color": Color(colours[i]),
			"reward": str(rewards[i]),
			"req_text": req_text,
		})
	return out

# Concise reward descriptions for an advisor's 5 missions.
func advisor_mission_reward_labels(advisor_id: String) -> Array:
	var tmpl: Dictionary = MISSION_TEMPLATES.get(str(_roster_entry(advisor_id).get("role", "")), {})
	if tmpl.is_empty():
		return ["—", "—", "—", "—", "—"]
	var m3_parts: Array[String] = ["Free research in %s." % str(tmpl.get("research_category", ""))]
	if tmpl.has("temp2"):
		m3_parts.append(_mission_reward_detail(tmpl.get("temp2", {})))
	return [
		_mission_reward_detail(tmpl.get("temp", {})),
		_mission_reward_detail(tmpl.get("perm1", {})),
		" ".join(m3_parts),
		_mission_reward_detail(tmpl.get("perm2", {})),
		_mission_reward_detail(tmpl.get("capstone", {})),
	]

func _mission_reward_detail(spec_value: Variant) -> String:
	if not (spec_value is Dictionary):
		return "No extra reward."
	var spec: Dictionary = spec_value
	if spec.is_empty():
		return "No extra reward."
	var label := str(spec.get("label", "")).strip_edges()
	if spec.has("policy"):
		return "Unlocks workforce policy: %s." % label
	var domain := _mission_domain_label(str(spec.get("domain", "")))
	var pct := float(spec.get("pct", 0.0))
	var pct_text := _signed_percent_text(pct)
	if spec.has("turns"):
		var turns := int(spec.get("turns", 0))
		return "%s. Applies %s to %s for %d turns." % [label, pct_text, domain, turns]
	return "%s. Permanent %s to %s." % [label, pct_text, domain]

func _mission_domain_label(domain: String) -> String:
	var names := {
		"building_power": "building power use",
		"construction_rebate": "build and upgrade rebates",
		"dividend_rate": "dividend payouts",
		"labour_headcount": "labour costs",
		"loan_interest": "loan interest",
		"market_price": "sale prices",
		"market_spread": "market buy spread",
		"maintenance": "maintenance costs",
		"purchase_cost": "land and building prices",
		"recipe_output": "recipe output",
		"tax_rate": "tax",
		"transport_cost": "transport cost",
		"transport_throughput": "transport throughput",
	}
	return str(names.get(domain, domain.replace("_", " ")))

func _signed_percent_text(value: float) -> String:
	var sign := "+" if value > 0.0 else ""
	return "%s%.0f%%" % [sign, value]

# Display roster derived from the canonical ADVISOR_ROSTER + ADVISOR_DISPLAY. One
# roster now backs both the People panel and seating (spec §12.1 Phase-0 rest).
func _advisor_definitions() -> Array:
	var out: Array = []
	for a in ADVISOR_ROSTER:
		var id := str(a.get("id", ""))
		var disp: Dictionary = ADVISOR_DISPLAY.get(id, {})
		var accent := str(disp.get("accent", "#5A6070"))
		out.append({
			"id": id,
			"name": str(a.get("name", id)),
			"initials": str(disp.get("initials", "")),
			"role": _seat_display_name(str(a.get("role", ""))),
			"happiness": 0,
			"portrait_path": str(disp.get("portrait_path", "")),
			"portrait_color": Color(accent),
			"bonus": str(disp.get("bonus", "")),
			"recommendation": str(disp.get("recommendation", "")),
			"bio": str(disp.get("bio", "")),
			"agenda": str(disp.get("agenda", "")),
			"likes": disp.get("likes", []),
			"dislikes": disp.get("dislikes", []),
			"bonuses": disp.get("bonuses", []),
			"missions": _advisor_missions(id, accent),
		})
	return out
