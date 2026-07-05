extends Node
const BuildingLevels := preload("res://scripts/building_levels.gd")

# MatchState: the canonical store for everything that changes during a match.
# Other systems read and write here; never store match data elsewhere.

# --- Player resources ---
const LOCAL_PLAYER := "player_1"
var money: float = 1000.0  # was: int = 1000

# --- Ruleset ---
# Which rule variant this match plays under. Carried in saves and start configs so
# future rule changes (scoring, brakes, era pacing, …) can key off it; only "name"
# is defined today — add per-rule keys beside it as rules become real.
const DEFAULT_RULESET := {"name": "standard"}
var ruleset: Dictionary = DEFAULT_RULESET.duplicate(true)

const DEFAULT_TILE_LAND_OWNED := 100
const LAND_PATCH_SIZE := 10
const LAND_PATCH_COST := 10.0
const MAX_TILE_LAND := 200

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
var workforce_policies: Dictionary = {}
var workforce_policy_effects: Dictionary = {}
const ADVISOR_COST_PER_TURN := 2.0
var permanent_advisor_ids: Array = []
# --- Advisor seats (seat framework, docs/advisor-system-spec.md §4-6) ---
# advisor_seats is sparse: only occupied seats are keys, so .size() == seated count.
var advisor_seats: Dictionary = {}          # seat_id -> advisor_id
const MAX_ADVISOR_SLOTS_DEFAULT := 2
const MAX_ADVISOR_SLOTS_CAP := 5            # spec §4.1 hard ceiling
var max_advisor_slots: int = MAX_ADVISOR_SLOTS_DEFAULT
# --- Advisor acquisition (spec §4.2-4.4) ---
const DEFAULT_MATCH_RNG_SEED := 5060301
const PROFIT_MILESTONES := [50, 100, 150, 200, 300, 400, 500, 750, 1000]
const STARTING_TRIO := ["vera", "tom", "rufus"]
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
# 2 likes + 2 dislikes per advisor.
const ADVISOR_AGENDAS := {
	"vera": {"likes": [AGENDA_MADE_PROFIT, AGENDA_PAID_OFF_LOAN], "dislikes": [AGENDA_TOOK_LOAN, AGENDA_BUILT_UNPROFITABLE]},
	"tom": {"likes": [AGENDA_USED_STOCKPILE, AGENDA_CHANGED_RECIPE], "dislikes": [AGENDA_IDLE_BUILDING, AGENDA_TOOK_LOAN]},
	"rufus": {"likes": [AGENDA_MADE_PROFIT, AGENDA_BOUGHT_MATERIALS], "dislikes": [AGENDA_CHANGED_RECIPE, AGENDA_TECH_UNLOCK]},
	"gerald": {"likes": [AGENDA_USED_STOCKPILE, AGENDA_AUTARKIC], "dislikes": [AGENDA_TECH_UNLOCK, AGENDA_CHANGED_RECIPE]},
	"eleanor": {"likes": [AGENDA_LABOUR_POLICIES, AGENDA_MADE_PROFIT], "dislikes": [AGENDA_BUILT_UNPROFITABLE, AGENDA_BOUGHT_GRID_POWER]},
	"sloane": {"likes": [AGENDA_SOLD_GRID_POWER, AGENDA_MADE_PROFIT], "dislikes": [AGENDA_IDLE_BUILDING, AGENDA_AUTARKIC]},
	"priya": {"likes": [AGENDA_TECH_UNLOCK, AGENDA_CHANGED_RECIPE], "dislikes": [AGENDA_IDLE_BUILDING, AGENDA_USED_STOCKPILE]},
	"hitomi": {"likes": [AGENDA_FAST_SHIPMENT, AGENDA_MADE_PROFIT], "dislikes": [AGENDA_BOUGHT_GRID_POWER, AGENDA_IDLE_BUILDING]},
	"hal": {"likes": [AGENDA_MADE_PROFIT, AGENDA_TECH_UNLOCK], "dislikes": [AGENDA_TOOK_LOAN, AGENDA_BUILT_UNPROFITABLE]},
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
		"research_category": "Markets and Operations",
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
		"research_category": "Markets and Operations",
		"perm2": {"domain": "market_price", "pct": 2.0, "label": "permanent +2% sale price"},
		"capstone": {"domain": "market_price", "pct": 3.0, "label": "permanent +3% sale price"},
	},
	"chief_investment": {
		"temp": {"domain": "purchase_cost", "pct": -20.0, "turns": 20, "label": "-20% land/building prices (20t)"},
		"perm1": {"domain": "purchase_cost", "pct": -8.0, "label": "permanent -8% purchase cost"},
		"research_category": "Markets and Operations",
		"perm2": {"domain": "construction_rebate", "pct": 5.0, "label": "permanent +5% build rebate"},
		"capstone": {"domain": "construction_rebate", "pct": 5.0, "label": "permanent +5% build rebate"},
	},
	"hr_director": {
		"temp": {"domain": "labour_headcount", "pct": -15.0, "turns": 20, "label": "-15% labour (20t)"},
		"perm1": {"domain": "labour_headcount", "pct": -6.0, "label": "permanent -6% labour"},
		"research_category": "People Management",
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
		"research_category": "People Management",
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
var output_special_order_destinations: Dictionary = {}  # instance_id -> {good_id -> special_order_id}
const MARKET_DESTINATION := "__market__"  # sentinel tile_id: route this building's output to market
var input_tile_only: Dictionary = {}  # "instance_id|good_id" -> true (tile stockpile ONLY; default buys from market)
var pending_output_stockpile_selection: Dictionary = {}
var queued_stockpile_market_sales: Dictionary = {}  # tile_id -> true
var sell_surplus_tiles: Dictionary = {}              # tile_id -> true (master: auto-sell ALL surplus goods)
var auto_sell_goods: Dictionary = {}                 # tile_id -> { good_id -> true } (per-good auto-sell overrides)
var auto_sell_keep: Dictionary = {}                  # tile_id -> { good_id -> units always left on the tile ("sell all except X") }
const IMPACT_ANY := -1                               # auto-sell tolerance sentinel: no per-turn volume cap
var auto_sell_impact: Dictionary = {}                # tile_id -> max price-impact % tolerated per turn (or IMPACT_ANY)
var pending_transport_shipments: Array = []
# In-progress building upgrades (mirrors Construction's project queue). Each entry is a
# dict — see start_upgrade() for the shape. While an upgrade is pending it reserves its
# extra footprint and the building keeps producing at its CURRENT level until promotion.
var pending_upgrades: Array = []
# In-progress retrofits (recipe changes): {instance_id, from_recipe, to_recipe,
# turns_remaining, labour_fraction}. The building produces nothing while retooling.
var pending_retrofits: Array = []
# Last turn's per-link flow ("tile|mode"->units) — drives this turn's congestion cost.
var _last_link_flow: Dictionary = {}
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
var _unlock_defs: Array = []   # [{title, action, object, qty, prereqs, description}]
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


# Debug-only: when true the bottom menu shows the alternate icon set instead of
# the old circular icon set. Toggled at runtime via the `swap bottom menu` cheat.
# Session-only; never persisted. Defaults to the white-rimmed alternate buttons.
var use_alt_bottom_menu: bool = true

# Debug-only: verbose per-turn production / CostSolver logs. Off by default because
# large empires can produce hundreds of console lines per turn in editor builds.
# Toggled at runtime via the `logs` debug-terminal cheat. Session-only.
var debug_turn_logs_enabled: bool = false

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
## A UI element (e.g. the tile-view intermittency "see more" link) asked to open the
## building ledger pre-filtered to a single filter key (e.g. "green_intermittent").
signal building_ledger_filter_requested(filter_key: String)
signal output_stockpile_selection_started(selection: Dictionary)
signal output_stockpile_selection_cancelled
signal output_stockpile_destination_changed(instance_id: String, tile_id: String, good_id: String)
signal stockpile_market_sale_queue_changed(tile_id: String)
signal stockpile_market_sale_completed(sale_record: Dictionary)
signal sell_surplus_changed(tile_id: String)
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
## A tile finished being surveyed (drives the on-map survey animation). deposit_goods
## is an array of {good_id, internal_name} for the non-water deposits revealed.
signal tile_survey_completed(tile_id: String, deposit_goods: Array)
## A shipment arrived at a full tile and is now waiting to unload.
signal overflow_shipment_held(record: Dictionary)
## A special-order delivery reached port with units beyond the completed order's
## demand. The UI must ask whether to sell those units or stockpile them at port.
signal special_order_overflow_ready(record: Dictionary)
## Debug cheat `swap bottom menu` flipped which bottom-menu icon set is active.
signal alt_bottom_menu_changed(enabled: bool)
## A UI surface (notification deep-link, etc.) asks the map to focus a tile:
## centre the camera on it and open its tile panel. world_map handles it.
signal focus_tile_requested(tile_id: String)
## Like focus_tile_requested, but opens the building detail panel for a specific
## building instance (centring the camera on its tile). Used by starvation
## notifications' "Go to".
signal focus_building_requested(instance_id: String)

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
		# Production, costs and run-streaks have settled for the turn — re-evaluate
		# the live research conditions (Produce N / Run profitable / Run-for-N-turns).
		_check_unlock_conditions()
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
		# Building-driven research conditions (e.g. Mining Mastery) re-evaluate here.
		_check_unlock_conditions()
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
	building_owner_changed.emit(instance_id)
	# A newly player-owned building may satisfy build-count / ownership unlock conditions.
	_check_unlock_conditions()

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
	var granted := mini(MAX_TILE_LAND, owned + footprint)
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
func preview_upgrade(instance_id: String) -> Dictionary:
	if not buildings.has(instance_id):
		return {"ok": false, "reason": "No such building."}
	var inst: Dictionary = buildings[instance_id]
	var level := int(inst.get("level", 1))
	var building_id := str(inst.get("building_id", ""))
	var building_name := str(Catalog.get_building(building_id).get("display_name", building_id))
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
	for gid in need_by_gid:
		var need := int(need_by_gid[gid])
		var have := Stockpile.get_at_tile(tile_id, gid)
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
			"need": need, "have": have, "short": short,
		})
	var all_on_tile := shortfall.is_empty()

	# A single other tile that can cover the whole shortfall (powers the "use stockpile" CTA).
	var source := Construction.find_source_tile(tile_id, shortfall) if not all_on_tile else {}

	# Footprint check (the larger building must still fit, counting other pending upgrades).
	var delta := _upgrade_size_delta(building_id, level, target)
	var projected := get_tile_space_used(tile_id) + delta
	var fits := projected <= float(MAX_TILE_LAND) and projected <= float(get_tile_land_owned(tile_id))

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
		"market_sourceable": market_sourceable,
		"source_tile": str(source.get("tile_id", "")),
		"source_turns": int(source.get("turns", 0)),
		"market_cost": market_cost,
		"fits": fits,
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
		return {"ok": false, "reason": "No such building."}
	if is_upgrading(instance_id):
		return {"ok": false, "reason": "An upgrade is already in progress."}
	var inst: Dictionary = buildings[instance_id]
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
	var size_delta := _upgrade_size_delta(building_id, level, target)
	var projected := get_tile_space_used(tile_id) + size_delta
	if projected > float(MAX_TILE_LAND) or projected > float(get_tile_land_owned(tile_id)):
		return {"ok": false, "reason": "Not enough room on the tile for the larger building."}

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

## Advance every in-progress upgrade one turn. Awaiting projects claim any newly-arrived
## materials off the tile (this runs before production consumes, so there's no race); once
## fully stocked they start counting down, and at zero the building's level is bumped.
## Returns the instance_ids that completed this turn. Called from Production each PROCESS.
func tick_upgrades() -> Array:
	var completed: Array = []
	var remaining: Array = []
	for p in pending_upgrades:
		var instance_id := str(p.get("instance_id", ""))
		# Drop upgrades whose building vanished (sold/removed mid-flight).
		if not buildings.has(instance_id):
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
			building_upgrade_progress.emit(instance_id)
			remaining.append(p)
			continue
		# Under upgrade — count down, promote at zero.
		p["turns_remaining"] = int(p.get("turns_remaining", 0)) - 1
		if int(p["turns_remaining"]) <= 0:
			var inst: Dictionary = buildings[instance_id]
			inst["level"] = int(p.get("target_level", int(inst.get("level", 1)) + 1))
			completed.append(instance_id)
			building_upgraded.emit(instance_id, int(inst["level"]))
		else:
			building_upgrade_progress.emit(instance_id)
			remaining.append(p)
	pending_upgrades = remaining
	return completed

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
	pending_upgrades = kept
	if cancelled:
		building_upgrade_cancelled.emit(instance_id)
	return cancelled

func remove_building(instance_id: String) -> bool:
	if not buildings.has(instance_id):
		return false

	# Refund any in-progress upgrade's banked materials before the building disappears.
	cancel_upgrade(instance_id)

	var instance: Dictionary = buildings[instance_id]
	var tile_id: String = instance.tile_id
	
	# Remove from tile index
	if tile_buildings.has(tile_id):
		tile_buildings[tile_id].erase(instance_id)
		if tile_buildings[tile_id].is_empty():
			tile_buildings.erase(tile_id)
	
	buildings.erase(instance_id)
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

# --- Public API: survey state ---
## Seed the surveyed set with the NPC port tiles (called once at match start).
func seed_surveyed_ports() -> void:
	for port in Catalog.all_ports():
		var tile_id := str(port.get("tile_id", ""))
		if tile_id != "":
			surveyed_tiles[tile_id] = true
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
	# A full survey auto-(partially-)surveys a neighbour; Spectral Crystallography
	# reveals one extra ("+1 adjacent tile revealed when surveying").
	var reveals := 2 if is_unlocked("Spectral Crystallography") else 1
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

# --- Public API: research unlocks ---
func _load_unlock_defs() -> void:
	_unlock_defs.clear()
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
		var prereqs: Array = []
		for col in ["prereq_1", "prereq_2", "prereq_3"]:
			var p := _csv_at(row, idx, col)
			if p != "":
				prereqs.append(p)
		var q := _csv_at(row, idx, "Quantity")
		_unlock_defs.append({
			"title": _csv_at(row, idx, "title"),
			"category": _csv_at(row, idx, "category"),
			"action": _csv_at(row, idx, "Action"),
			"object": _csv_at(row, idx, "Object"),
			"qty": int(q) if q.is_valid_int() else 0,
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

func is_unlocked(title: String) -> bool:
	return unlocked_titles.has(title)

# Grant the first not-yet-unlocked research node in a category (an advisor-mission
# reward). Returns the granted title, or "" if the category is already fully unlocked.
func grant_first_locked_in_category(category: String) -> String:
	for d in _unlock_defs:
		if str(d.get("category", "")) == category:
			var title := str(d.get("title", ""))
			if title != "" and not is_unlocked(title):
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
	unlocked_titles[title] = true
	_surveyable_dirty = true  # e.g. Geoscanning changes survey range
	flag_agenda_event(AGENDA_TECH_UNLOCK)
	var desc := ""
	for d in _unlock_defs:
		if str(d.title) == title:
			desc = str(d.description)
			break
	unlock_granted.emit(title, desc, via_condition)

## Record progress toward action+object conditions (e.g. record("Survey","tiles")).
func record_unlock_progress(action: String, object: String, amount: int = 1) -> void:
	if amount <= 0:
		return
	var key := (action + "|" + object).to_lower()
	_unlock_progress[key] = int(_unlock_progress.get(key, 0)) + amount
	_check_unlock_conditions()

func _check_unlock_conditions() -> void:
	for d in _unlock_defs:
		var title := str(d.title)
		if title == "" or unlocked_titles.has(title) or int(d.qty) <= 0:
			continue
		var action := str(d.action)
		if action == "" or str(d.object) == "":
			continue
		var prereqs_met := true
		for p in d.prereqs:
			if not unlocked_titles.has(str(p)):
				prereqs_met = false
				break
		if not prereqs_met:
			continue
		# Live conditions evaluated against current state (production totals, owned
		# buildings, profitability, run-streaks). The Object is an internal_name —
		# a good_id for "Produce", a building internal_name for the "Run …" verbs.
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

# True when a research def's live condition is satisfied right now. Returns false
# for any action this evaluator doesn't own (those fall back to the accumulator).
func _live_condition_met(d: Dictionary) -> bool:
	var action := str(d.action)
	var obj := str(d.object)
	var need := int(d.qty)
	match action:
		"Produce":
			return Production.lifetime_total(obj) >= need
		"Build":
			# "Own N player-built buildings of this internal_name" (any level/run state).
			return _count_buildings(obj, -1, false, 0) >= need
		"Run Profitable":
			return _count_buildings(obj, -1, true, 0) >= need
		"Run L1":
			# "Run N Level-1 buildings of this type for <Unit> turns."
			var turns := _leading_int(str(d.get("unit", "")), 20)
			return _count_buildings(obj, 1, false, turns) >= need
		"Run Profitable L2":
			return _count_buildings(obj, 2, true, 0) >= need
	return false

# Count player-owned buildings whose internal_name == `internal`, optionally
# filtered by level (-1 = any), profitability, and a minimum consecutive run-streak.
# `internal` == "any" (or "") matches every building type — used by scale-based
# unlocks that gate on total buildings owned rather than a specific type.
func _count_buildings(internal: String, level: int, require_profitable: bool, min_streak: int) -> int:
	var match_any: bool = internal == "any" or internal == ""
	var n := 0
	for inst in buildings.values():
		if not is_player_owned(inst):
			continue
		if not match_any and _building_internal(inst) != internal:
			continue
		if level >= 0 and _building_level(inst) != level:
			continue
		if min_streak > 0 and int(Production.full_output_streak_by_building.get(str(inst.get("instance_id", "")), 0)) < min_streak:
			continue
		if require_profitable and not _is_building_profitable(inst):
			continue
		n += 1
	return n

func _building_internal(inst: Dictionary) -> String:
	return str(Catalog.get_building(str(inst.get("building_id", ""))).get("internal_name", ""))

# Production buildings have no level field yet (leveling mechanic unbuilt), so this
# reports Level 1 for everything — the forward-compatible default.
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
	var price: float = Catalog.get_base_price(good_id)
	return price > 0.0 and uc < price

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
func battery_cells_to_fill(tile_id: String, good_id: String) -> int:
	var density := _battery_density(good_id)
	if density <= 0.0:
		return 0
	var free_firming := float(tile_battery_slots(tile_id)) - tile_loaded_firming(tile_id)
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

func get_tile_land_patches_available(tile_id: String) -> int:
	var remaining := MAX_TILE_LAND - get_tile_land_owned(tile_id)
	return maxi(0, int(floor(float(remaining) / float(LAND_PATCH_SIZE))))

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
func purchase_cost_after_advisor(base_cost: float) -> float:
	var mult: float = maxf(0.0, 1.0 + float(Modifiers.resolve_pct("purchase_cost", "*", {}).get("net", 0.0)) / 100.0)
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

func purchase_tile_land(tile_id: String, patches: int = 1) -> bool:
	if tile_id == "":
		return false
	var available := get_tile_land_patches_available(tile_id)
	if available <= 0:
		return false
	var clamped_patches: int = clampi(patches, 1, available)
	var cost := purchase_cost_after_advisor(float(clamped_patches) * LAND_PATCH_COST)
	if not deduct_money(cost):
		return false
	var owned := get_tile_land_owned(tile_id)
	tile_land_owned[tile_id] = mini(MAX_TILE_LAND, owned + clamped_patches * LAND_PATCH_SIZE)
	tile_land_owned_changed.emit(tile_id)
	return true

func get_building(instance_id: String) -> Dictionary:
	# Returns the instance dict, or empty dict if not found
	return buildings.get(instance_id, {})

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
	buildings.clear()
	tile_buildings.clear()
	output_stockpile_destinations.clear()
	output_special_order_destinations.clear()
	pending_output_stockpile_selection.clear()
	queued_stockpile_market_sales.clear()
	sell_surplus_tiles.clear()
	auto_sell_goods.clear()
	auto_sell_keep.clear()
	auto_sell_impact.clear()
	pending_transport_shipments.clear()
	pending_upgrades.clear()
	pending_retrofits.clear()
	_last_link_flow.clear()
	overflow_shipments.clear()
	sales_by_tile.clear()
	tile_land_owned.clear()
	tile_battery_cells.clear()
	pending_battery_fills.clear()
	workforce_policies.clear()
	workforce_policy_effects.clear()
	labour_multiplier = EconomyConfig.LABOUR_MULTIPLIER_DEFAULT
	labour_output_pressure_pct = 0.0
	permanent_advisor_ids.clear()
	advisor_seats.clear()
	max_advisor_slots = MAX_ADVISOR_SLOTS_DEFAULT
	crossed_milestones.clear()
	recruited_advisor_ids.clear()
	fired_advisor_cooldowns.clear()
	advisor_loyalty.clear()
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
	transaction_log.clear()
	move_log.clear()
	input_tile_only.clear()
	# Research state is match-scoped: a reset (new game / scenario start) must
	# clear it, or unlocks leak from the previous match. (Load overwrites it via
	# import_state, so this only bites the reset-without-import paths.)
	unlocked_titles.clear()
	_unlock_progress.clear()
	_next_instance_counter = 0
	ruleset = DEFAULT_RULESET.duplicate(true)
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
		"output_special_order_destinations": output_special_order_destinations.duplicate(true),
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
		"next_instance_counter": _next_instance_counter,
		"shipment_id_counter": _shipment_id_counter,
		"buildings": _buildings_for_save(),
		"tile_land_owned": tile_land_owned.duplicate(true),
		"tile_battery_cells": tile_battery_cells.duplicate(true),
		"pending_battery_fills": pending_battery_fills.duplicate(true),
		"labour_multiplier": labour_multiplier,
		"labour_output_pressure_pct": labour_output_pressure_pct,
		"workforce_policies": workforce_policies.duplicate(true),
		"workforce_policy_effects": workforce_policy_effects.duplicate(true),
		"permanent_advisor_ids": permanent_advisor_ids.duplicate(true),
		"advisor_seats": advisor_seats.duplicate(true),
		"max_advisor_slots": max_advisor_slots,
		"advisor_rng_seed": match_rng_seed,
		"advisor_rng_state": _match_rng.state,
		"advisor_crossed_milestones": crossed_milestones.duplicate(true),
		"recruited_advisor_ids": recruited_advisor_ids.duplicate(true),
		"fired_advisor_cooldowns": fired_advisor_cooldowns.duplicate(true),
		"advisor_loyalty": advisor_loyalty.duplicate(true),
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
		"output_special_order_destinations": output_special_order_destinations.duplicate(true),
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
		"pending_upgrades": pending_upgrades.duplicate(true),
		"pending_retrofits": pending_retrofits.duplicate(true),
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
		"seaport_auto_subscribe": seaport_auto_subscribe,
		"seaport_subscribed": seaport_subscribed.duplicate(true),
	}

func import_state(d: Dictionary) -> void:
	# Silent full overwrite of every exported field — SaveLoad emits the refresh
	# signals once after every system has imported. Missing keys fall back to the
	# new-game default, so older/partial snapshots (and Phase 3 start configs) load.
	money = float(d.get("money", EconomyConfig.STARTING_MONEY))
	ruleset = (d.get("ruleset", DEFAULT_RULESET) as Dictionary).duplicate(true)
	_next_instance_counter = int(d.get("next_instance_counter", 0))
	_shipment_id_counter = int(d.get("shipment_id_counter", 0))
	buildings = _normalise_loaded_buildings(d.get("buildings", {}))
	tile_land_owned = (d.get("tile_land_owned", {}) as Dictionary).duplicate(true)
	tile_battery_cells = (d.get("tile_battery_cells", {}) as Dictionary).duplicate(true)
	pending_battery_fills = (d.get("pending_battery_fills", []) as Array).duplicate(true)
	labour_multiplier = float(d.get("labour_multiplier", EconomyConfig.LABOUR_MULTIPLIER_DEFAULT))
	labour_output_pressure_pct = float(d.get("labour_output_pressure_pct", 0.0))
	workforce_policies = (d.get("workforce_policies", {}) as Dictionary).duplicate(true)
	workforce_policy_effects = (d.get("workforce_policy_effects", {}) as Dictionary).duplicate(true)
	recruited_advisor_ids = _sanitize_advisor_ids(d.get("recruited_advisor_ids", STARTING_TRIO))
	advisor_loyalty = (d.get("advisor_loyalty", {}) as Dictionary).duplicate(true)
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
	advisor_seats = _sanitize_advisor_seats(d.get("advisor_seats", {}))
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
	output_special_order_destinations = (d.get("output_special_order_destinations", {}) as Dictionary).duplicate(true)
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
	pending_upgrades = (d.get("pending_upgrades", []) as Array).duplicate(true)
	pending_retrofits = (d.get("pending_retrofits", []) as Array).duplicate(true)
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
	_unlock_progress = (d.get("unlock_progress", {}) as Dictionary).duplicate(true)
	seaport_auto_subscribe = bool(d.get("seaport_auto_subscribe", false))
	seaport_subscribed = (d.get("seaport_subscribed", {}) as Dictionary).duplicate(true)
	# Derived state: the tile index is rebuilt, never saved; caches invalidate.
	_rebuild_tile_index()
	_surveyable_dirty = true
	pending_output_stockpile_selection.clear()
	sales_by_tile.clear()
	_requote_shipment_routes()

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

## Debug cheat: switch between the current and alternate bottom-menu icon sets.
## Returns the new state. Session-only, never persisted.
func set_use_alt_bottom_menu(enabled: bool) -> bool:
	if enabled == use_alt_bottom_menu:
		return use_alt_bottom_menu
	use_alt_bottom_menu = enabled
	alt_bottom_menu_changed.emit(use_alt_bottom_menu)
	return use_alt_bottom_menu

func toggle_use_alt_bottom_menu() -> bool:
	return set_use_alt_bottom_menu(not use_alt_bottom_menu)

## Debug cheat: toggle verbose production / CostSolver console logs.
## Returns the new state. Session-only, never persisted.
func toggle_debug_turn_logs() -> bool:
	debug_turn_logs_enabled = not debug_turn_logs_enabled
	return debug_turn_logs_enabled

func set_route_objective(objective: int) -> void:
	if objective == route_objective:
		return
	route_objective = objective
	route_objective_changed.emit(objective)

func begin_output_stockpile_selection(instance_id: String, good_id: String) -> void:
	if instance_id == "" or good_id == "":
		return
	pending_output_stockpile_selection = {
		"instance_id": instance_id,
		"good_id": good_id,
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
	_clear_output_special_order_tag(instance_id, good_id)
	pending_output_stockpile_selection.clear()
	output_stockpile_destination_changed.emit(instance_id, tile_id, good_id)

func clear_output_stockpile_destination(instance_id: String, good_id: String = "") -> void:
	if instance_id == "":
		return
	if good_id == "":
		output_stockpile_destinations.erase(instance_id)  # clear the whole building
		output_special_order_destinations.erase(instance_id)
		return
	var per_good: Dictionary = output_stockpile_destinations.get(instance_id, {})
	per_good.erase(good_id)
	if per_good.is_empty():
		output_stockpile_destinations.erase(instance_id)
	else:
		output_stockpile_destinations[instance_id] = per_good
	_clear_output_special_order_tag(instance_id, good_id)

func get_output_stockpile_destination(instance_id: String, good_id: String = "") -> String:
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

func route_output_to_market(instance_id: String, good_id: String) -> void:
	# Per-building, per-good "send output to market" — does NOT touch global sell_mode.
	if instance_id == "" or good_id == "":
		return
	var per_good: Dictionary = output_stockpile_destinations.get(instance_id, {})
	per_good[good_id] = MARKET_DESTINATION
	output_stockpile_destinations[instance_id] = per_good
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

func queue_transport_shipment(shipment: Dictionary) -> void:
	var s := shipment.duplicate(true)
	if not s.has("id"):
		_shipment_id_counter += 1
		s["id"] = _shipment_id_counter  # stable id so the overlay can track it across turns
	pending_transport_shipments.append(s)
	transport_shipments_changed.emit()

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

func add_recurring_bulk_sell(params: Dictionary) -> void:
	recurring_bulk_sells.append({"params": params.duplicate(true), "turn_started": _ledger_turn()})

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

# --- Seaport subscriptions ---
# A subscribed good transfers through a seaport in 1 turn at ANY volume for a flat
# per-turn fee (see EconomyConfig.SEAPORT_SUBSCRIPTION_COST_PER_GOOD), with no per-unit
# market shipping cost. The sim sets seaport_auto_subscribe = true (every traded good
# is covered from turn 1); the game will expose per-good toggles.
var seaport_auto_subscribe: bool = false
var seaport_subscribed: Dictionary = {}

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
	return float(seaport_subscribed.size()) * EconomyConfig.SEAPORT_SUBSCRIPTION_COST_PER_GOOD

func queue_buy(dest_tile: String, good_id: String, qty: int, log_oneoff: bool = true, extra: Dictionary = {}) -> Dictionary:
	# Buy goods from the nearest port to dest_tile: pay now (price + transport), ship in,
	# arrive in N turns. The reusable buy primitive for market-sourced inputs (and later a Buy tab).
	if dest_tile == "" or good_id == "" or qty <= 0:
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
	if total > money:
		# Best-effort: buy as much as we can afford rather than nothing (avoids an
		# all-or-nothing starvation cliff when cash dips below a full order).
		var per_unit := unit_price + transport / float(maxi(qty, 1))
		qty = mini(qty, int(floor(money / maxf(per_unit, 0.0001))))
		if qty <= 0:
			return {}
		quote = TransportService.quote_market_buy(dest_tile, good_id, qty, covered)
		route = quote.get("route", {})
		turns = int(quote.get("turns", 0))
		transport = float(quote.get("transport_cost", 0.0))
		total = float(quote.get("cost", 0.0))
		if total > money:
			return {}
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
			"tiles": route.get("tiles", []), "path": route.get("path", []), "legs": route.get("legs", []),
		}
		shipment.merge(extra, true)  # optional tags, e.g. construction_instance_id
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
	return {"qty": qty, "turns": turns, "cost": total,
		"goods_cost": float(qty) * unit_price, "transport_cost": transport, "port": port}

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
	var quote := TransportService.quote_market_buy(dest_tile, good_id, qty, seaport_would_cover(good_id))
	if quote.is_empty():
		return {}
	return {"cost": float(quote.get("cost", 0.0)), "goods_cost": float(quote.get("goods_cost", 0.0)),
		"transport_cost": float(quote.get("transport_cost", 0.0)), "turns": int(quote.get("turns", 0)),
		"port": str(quote.get("port", ""))}

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
		transport_shipments_changed.emit()
	return arrived

# ── Transport throughput congestion (soft cap) ─────────────────────────────
# A tile-link's per-turn flow on a mode = total units of in-transit shipments
# crossing that tile on that mode (same convention as the infra hover readout).
# When flow exceeds the link's capacity (base mode cap × infra level × throughput
# research), goods still move but pay a transport-cost penalty: +100% over capacity,
# +200% once over capacity plus the base L1 cap. Last turn's flow drives this turn's
# costs (route_congestion_tier), so it's stable rather than self-referential.
const _CAPPED_MODES := ["roads", "rail", "pipes", "reinf_pipes"]

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
		var idx := 0
		for leg in legs:
			var start := idx
			while idx < tiles.size() - 1 and str(tiles[idx]) != str(leg.get("to", "")):
				idx += 1
			var mode := str(leg.get("mode", ""))
			if mode in _CAPPED_MODES:
				for i in range(start, idx + 1):
					var key := "%s|%s" % [str(tiles[i]), mode]
					flow[key] = int(flow.get(key, 0)) + qty
	return flow

func _shipment_total_units(s: Dictionary) -> int:
	if bool(s.get("is_sale", false)):
		var total := 0
		for item in s.get("sale_record", {}).get("items", []):
			total += int(item.get("qty", 0))
		return total
	return int(s.get("qty", 0))

## Per-turn capacity of one tile-link: base mode cap × level multiplier × the
## transport_throughput research multiplier. 0 means the mode is uncapped.
func tile_mode_capacity(mode: String, level: int) -> float:
	var base: float = float(EconomyConfig.TRANSPORT_LINK_CAP_BY_MODE.get(mode, 0))
	if base <= 0.0:
		return 0.0
	var cap := base * float(EconomyConfig.TRANSPORT_CAP_LEVEL_MULT.get(level, 1.0))
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
				if tolerated.has(Catalog.get_transport_class(str(good_id))):
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

## Congestion tier of a route, from last turn's flow on the links it crosses:
##   0 = clear · 1 = any link over its capacity · 2 = any link over capacity PLUS its
## base Level-1 cap (a fixed buffer, regardless of the tile's infra level). Drives the
## +100% (tier 1) / +200% (tier 2) transport-cost penalty.
func route_congestion_tier(route_data: Dictionary) -> int:
	if _last_link_flow.is_empty():
		return 0
	var tiles: Array = route_data.get("tiles", [])
	var legs: Array = route_data.get("legs", [])
	if tiles.is_empty() or legs.is_empty():
		return 0
	var worst := 0
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
	return worst

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
		if WORKFORCE_SAFETY_POLICIES.has(policy_id):
			for safety_id in WORKFORCE_SAFETY_POLICIES:
				if str(safety_id) != policy_id:
					workforce_policies.erase(str(safety_id))
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
		if not active and absf(float(effect.get("output_pct", 0.0))) < 0.00001 and absf(float(effect.get("labour_pct", 0.0))) < 0.00001 and absf(float(effect.get("dividend_pct", 0.0))) < 0.00001:
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
			if active:
				labour_pct = minf(0.15, labour_pct + 0.005)
			else:
				labour_pct = maxf(0.0, labour_pct - 0.0025)
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
		multiplier *= 1.10
	if is_workforce_policy_enabled(WORKFORCE_POLICY_ANNUAL_BONUS) and turn % 10 == 0:
		multiplier *= 1.20
	if is_workforce_policy_enabled(WORKFORCE_POLICY_ANNUAL_PROFIT_SHARE):
		multiplier *= 1.10
	return multiplier

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
func assign_advisor_to_seat(seat_id: String, advisor_id: String) -> bool:
	if not SEAT_DEFINITIONS.has(seat_id):
		return false
	if _roster_entry(advisor_id).is_empty():
		return false
	if not permanent_advisor_ids.has(advisor_id):
		return false
	if not advisor_seats.has(seat_id) and advisor_seats.size() >= max_advisor_slots:
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

# The seat this advisor best demonstrates: their assigned seat if seated, else the
# highest-tier seat that actually carries effects (falls back to their top seat).
func advisor_best_effect_seat(advisor_id: String) -> String:
	for sid in advisor_seats:
		if str(advisor_seats[sid]) == advisor_id:
			return str(sid)
	var best_seat := ""
	var best_tier := -1
	for sid in SEAT_DEFINITIONS:
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

func _player_building_count() -> int:
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
	var bldgs := _player_building_count()
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
	_advisor_walk_streak.erase(advisor_id)
	advisors_changed.emit()
	return true

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

func advisor_payroll_per_turn() -> float:
	var total := 0.0
	for advisor_id in permanent_advisor_ids:
		var a := _roster_entry(str(advisor_id))
		total += float(a.get("salary", ADVISOR_COST_PER_TURN)) if not a.is_empty() else ADVISOR_COST_PER_TURN
	return total

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
	"vera":      {"initials": "VA", "portrait_path": "res://assets/advisors/natasha.png", "accent": "#7C5A80", "bonus": "Family Trust: cheap, steady, strong almost anywhere", "recommendation": "Your reliable keystone — she holds any seat well.", "bio": "Your sister and the steady hand on the board: numerate, unflappable, and very hard to surprise twice.", "agenda": "Anchor the board and keep every seat competently filled.", "likes": ["Steady growth", "A balanced board"], "dislikes": ["Reckless bets", "Idle capital"], "bonuses": ["Reduced salary", "No weak seat"]},
	"alexandra": {"initials": "AR", "portrait_path": "res://assets/advisors/alexandra.png", "accent": "#8A5A5A", "bonus": "Prima Donna: superb everywhere, high salary + walk-risk", "recommendation": "A top hire who forces a full board reshuffle when she arrives.", "bio": "A rival operator good enough at everything to make your whole board nervous — and she knows her price.", "agenda": "Be indispensable, be paid, and never be sidelined.", "likes": ["Being centrally slotted", "Ambitious plays"], "dislikes": ["Being benched", "Being under-slotted"], "bonuses": ["Strong in any seat", "Commands a high salary"]},
	"gerald":    {"initials": "GV", "portrait_path": "res://assets/advisors/dan.png", "accent": "#455C78", "bonus": "Dinosaur: superb operator, brakes the green pivot", "recommendation": "Keep him for the throughput; the carbon squeeze makes him a dilemma.", "bio": "A superb pure operator who runs a plant beautifully and fights decarbonisation on instinct.", "agenda": "Maximise output and upkeep; resist the clean transition.", "likes": ["High utilisation", "Cheap fuel"], "dislikes": ["Clean retrofits", "Carbon rules"], "bonuses": ["Excellent COO", "Drags clean adoption"]},
	"eleanor":   {"initials": "ES", "portrait_path": "res://assets/advisors/anita.png", "accent": "#51707A", "bonus": "Beloved: labour + morale, slows churn", "recommendation": "The glue that lets a flawed board function.", "bio": "The diplomat the crews trust — dampens labour spikes and keeps the board from walking.", "agenda": "Keep the workforce and the board loyal.", "likes": ["Fair policies", "A stable board"], "dislikes": ["Layoffs", "Churn"], "bonuses": ["Labour cost down", "Advisor retention"]},
	"sloane":    {"initials": "SV", "portrait_path": "", "accent": "#6E5A86", "bonus": "Slick: best sale prices, quietly toxic", "recommendation": "Your best seller — pair with a strong IR to counter the fallout.", "bio": "The closer. Best sale prices in the business, and quietly toxic to everything that isn't a deal.", "agenda": "Push prices and volume; damn the standing.", "likes": ["Fat margins", "High volume"], "dislikes": ["Slow markets", "HR duty"], "bonuses": ["Better sell prices", "Weak with people"]},
	"priya":     {"initials": "PA", "portrait_path": "", "accent": "#4F6B58", "bonus": "Idealist: amplifies green, dents near-term profit", "recommendation": "Superb if you're racing Greenest; a cash drain if you're not.", "bio": "A true believer who reaches for the clean option every time, whatever it costs this quarter.", "agenda": "Decarbonise, capture subsidy, win Greenest.", "likes": ["Clean recipes", "Green subsidy"], "dislikes": ["Dirty routes", "Short-termism"], "bonuses": ["Green amplified", "Raises short-term spend"]},
	"hitomi":    {"initials": "HS", "portrait_path": "", "accent": "#7A6A45", "bonus": "Flow State: systems savant, socially inept", "recommendation": "Brilliant on logistics and the line; keep her from people seats.", "bio": "Brilliant with systems, hopeless with people — a logistics and manufacturing savant.", "agenda": "Optimise flow and throughput everywhere.", "likes": ["Tight networks", "Clean processes"], "dislikes": ["Meetings", "People seats"], "bonuses": ["Logistics/mfg boost", "Malus in people seats"]},
	"hal":       {"initials": "HR", "portrait_path": "", "accent": "#5A6F4A", "bonus": "Backroom Deals: regulatory relief at a price", "recommendation": "A real lever if you're staying dirty into the squeeze.", "bio": "The fixer. Buys you time against the regulators, at an ethical price.", "agenda": "Soften the rules and the tax bill.", "likes": ["Loopholes", "Delay"], "dislikes": ["Scrutiny", "Clean mandates"], "bonuses": ["Tax + carbon relief", "Reputation cost"]},
	"tom":       {"initials": "TB", "portrait_path": "res://assets/advisors/lance.png", "accent": "#66513B", "bonus": "Shop-Floor Respect: dependable operations", "recommendation": "Put him near the floor; he flounders near markets or the lab.", "bio": "The old foreman. Dependable operations, no frills, and the crews trust him.", "agenda": "Keep the line running cheaply.", "likes": ["A steady floor", "Trusted crews"], "dislikes": ["Market games", "Lab work"], "bonuses": ["Extra Ops labour cut", "Poor off the floor"]},
	"marcus":    {"initials": "MT", "portrait_path": "", "accent": "#765742", "bonus": "Leverage: cheap capital, dangerous debt", "recommendation": "High-risk finance specialist; dangerous outside his lane.", "bio": "A financier who makes capital cheap and acquisitions cheaper — until the debt bites.", "agenda": "Borrow big, buy cheap, grow fast.", "likes": ["Cheap debt", "Acquisitions"], "dislikes": ["Thin reserves", "Operations duty"], "bonuses": ["Cheap capital", "Debt-risk exposure"]},
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
