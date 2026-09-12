extends Node
## AdvisorState: the advisor council — seats, the recruit pool and profit milestones, hiring
## and firing, loyalty/agendas/walkouts, and the loyalty-milestone mission chain
## (docs/advisor-system-spec.md). Extracted from MatchState on 2026-09-11; the save keys are
## unchanged and still live under the "match" section (MatchState.export_state merges
## export_fields(), import_state calls import_fields(), reset() calls reset()).
##
## The seeded match RNG stays in MatchState (one RNG threaded through the sim); draws go
## through MatchState._match_rng_int. Workforce policies, CFO tax credits and building tabs
## read the council through this autoload but stay in MatchState.
##
## Turn hooks: Production.turn_processed -> _on_turn_processed_advisors (slots, milestones,
## agendas, loyalty tick); MatchState.goods_movement_recorded -> the fast-shipment agenda.

const ADVISOR_COST_PER_TURN := 2.0
## Only CFO and COO exist until the player earns the rest. A new player choosing between two
## posts is a real decision; choosing between eleven is a menu.
## See docs/early-game-onboarding-spec.md §5.4.
const STARTING_SEATS: Array[String] = ["cfo", "coo"]
# The seats a match runs with by default — CFO, COO, Technical Director, Chief Markets.
# The rest wait behind `unlock advisors` (see advisors_unlocked / is_seat_available).
const BASE_SEATS: Array[String] = ["cfo", "coo", "technical_director", "chief_markets"]
const FOUNDER_ADVISOR_ID := "andrew"
const FOUNDER_TENURE_TURNS := 30
const MAX_ADVISOR_SLOTS_DEFAULT := 2
const MAX_ADVISOR_SLOTS_CAP := 5            # spec §4.1 hard ceiling
const PROFIT_MILESTONES := [50, 100, 150, 200, 300, 400, 500, 750, 1000]
# Andrew (the founder, seated via the family-friend decision), Vera (CFO) and Gerald (COO)
# are the only advisors until `unlock advisors`. The starting recruited pool is the two
# non-founder demo advisors; Andrew joins separately through seat_founder.
const DEMO_ADVISORS := ["andrew", "vera", "gerald"]
const STARTING_TRIO := ["vera", "gerald"]
const FIRE_COOLDOWN_TURNS := 10                     # a fired advisor sits out this many turns
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
# Advisor slot (employ-cap) unlocks: 3rd @15 buildings, 4th @100, 5th @ sustained profit.
const ADVISOR_SLOT_BUILDINGS_3 := 15
const ADVISOR_SLOT_BUILDINGS_4 := 100
const ADVISOR_SLOT_PROFIT_5 := 1000.0
const ADVISOR_SLOT_PROFIT_STREAK := 3
const MASTER_BUILDER_ID := "gerald"   # Gerald Vance's specialty: -1 build turn while COO
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

signal advisor_mission_completed(advisor_id: String, mission_index: int, reward_label: String)
signal advisor_walked(advisor_id: String)
signal advisors_changed
signal advisor_acquired(advisor_id: String)
signal advisor_loyalty_changed(advisor_id: String, loyalty: float)
signal advisor_mission_state_changed(advisor_id: String)

# Demo gating: only the three DEMO_ADVISORS and four BASE_SEATS are
# available until the `unlock advisors` cheat opens the full roster, every seat, and the
# People-Management seat-unlock research.
var advisors_unlocked: bool = false
var permanent_advisor_ids: Array = []
# advisor_seats is sparse: only occupied seats are keys, so .size() == seated count.
var advisor_seats: Dictionary = {}          # seat_id -> advisor_id
var all_seats_unlocked: bool = false        # set by the people/labour research node
var founder_seat: String = ""               # which post Andrew took, "" if he never joined
var founder_leaves_turn: int = 0            # tenure end; he cannot be dismissed before it
var max_advisor_slots: int = MAX_ADVISOR_SLOTS_DEFAULT
var crossed_milestones: Array = []                 # latched profit thresholds
var recruited_advisor_ids: Array = []              # unlocked pool (employ up to the cap)
var fired_advisor_cooldowns: Dictionary = {}       # advisor_id -> turns until re-hireable (greyed while > 0)
var advisor_missions_completed: Dictionary = {}    # advisor_id -> int (0..5)
var _advisor_mission5_streak: Dictionary = {}      # advisor_id -> consecutive turns at/above MISSION5_LOYALTY
var advisor_mission_policies: Array = []           # workforce policies unlocked via missions
var advisor_loyalty: Dictionary = {}               # advisor_id -> float [-10, 10] (employed only)
var advisor_hired_turn: Dictionary = {}            # advisor_id -> turn hired (decision-gate tenure)
var _advisor_walk_streak: Dictionary = {}          # advisor_id -> consecutive turns at/below walk threshold
var _agenda_flags: Dictionary = {}                 # event_tag -> true; set during the turn, read+cleared each turn
var _agenda_grid_sell_streak := 0
var _agenda_no_buy_streak := 0
var _agenda_last_build_turn := 0
var _advisor_profit_streak: int = 0
var advisor_slot_profit_unlocked: bool = false
var peak_profit_per_turn: float = 0.0              # best profit/turn reached (advisor-track highpoint)


func _ready() -> void:
	# Production and MatchState are registered before this autoload; connect once every
	# autoload exists.
	call_deferred("_connect_turn_signals")


func _connect_turn_signals() -> void:
	if Production != null and not Production.turn_processed.is_connected(_on_turn_processed_advisors):
		Production.turn_processed.connect(_on_turn_processed_advisors)
	if not MatchState.goods_movement_recorded.is_connected(_on_goods_movement_agenda):
		MatchState.goods_movement_recorded.connect(_on_goods_movement_agenda)


## Match-scoped: cleared by MatchState.reset() (new game / scenario start).
func reset() -> void:

	advisors_unlocked = false
	permanent_advisor_ids.clear()
	advisor_seats.clear()
	all_seats_unlocked = false
	founder_seat = ""
	founder_leaves_turn = 0
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
	peak_profit_per_turn = 0.0
	reconcile_advisor_modifiers()


## Saved under MatchState's "match" section (keys unchanged from before the extraction).
func export_fields() -> Dictionary:
	return {
		"permanent_advisor_ids": permanent_advisor_ids.duplicate(true),
		"advisor_seats": advisor_seats.duplicate(true),
		"all_seats_unlocked": all_seats_unlocked,
		"founder_seat": founder_seat,
		"founder_leaves_turn": founder_leaves_turn,
		"max_advisor_slots": max_advisor_slots,
		"advisor_crossed_milestones": crossed_milestones.duplicate(true),
		"recruited_advisor_ids": recruited_advisor_ids.duplicate(true),
		"fired_advisor_cooldowns": fired_advisor_cooldowns.duplicate(true),
		"advisor_loyalty": advisor_loyalty.duplicate(true),
		"advisor_hired_turn": advisor_hired_turn.duplicate(true),
		"advisor_walk_streak": _advisor_walk_streak.duplicate(true),
		"advisor_missions_completed": advisor_missions_completed.duplicate(true),
		"advisor_mission5_streak": _advisor_mission5_streak.duplicate(true),
		"advisor_mission_policies": advisor_mission_policies.duplicate(true),
		"agenda_last_build_turn": _agenda_last_build_turn,
		"advisor_profit_streak": _advisor_profit_streak,
		"advisor_slot_profit_unlocked": advisor_slot_profit_unlocked,
		"advisor_peak_profit": peak_profit_per_turn,
	}


func import_fields(d: Dictionary) -> void:
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
	# Decision-gate tenure (tolerant reader): pre-feature saves carry no hire turns,
	# so existing councils default to "hired last turn" and count immediately.
	advisor_hired_turn = {}
	var raw_hired: Dictionary = d.get("advisor_hired_turn", {})
	for pid in permanent_advisor_ids:
		advisor_hired_turn[str(pid)] = int(raw_hired.get(str(pid), int(TurnManager.current_turn) - 1))
	advisor_seats = _sanitize_advisor_seats(d.get("advisor_seats", {}))
	# Default LOCKED: the demo ships four base seats until `unlock advisors`.
	# A save that had actually opened the council carries the flag; only a snapshot missing the
	# key (a fresh start config, which never sets it) reads false — which is the gated default
	# a new game wants. (Was `true` as a pre-founder tolerant-reader default; that leaked every
	# seat onto the council grid on every new game.)
	all_seats_unlocked = bool(d.get("all_seats_unlocked", false))
	founder_seat = str(d.get("founder_seat", ""))
	founder_leaves_turn = int(d.get("founder_leaves_turn", 0))
	max_advisor_slots = clampi(int(d.get("max_advisor_slots", MAX_ADVISOR_SLOTS_DEFAULT)), MAX_ADVISOR_SLOTS_DEFAULT, MAX_ADVISOR_SLOTS_CAP)
	crossed_milestones = (d.get("advisor_crossed_milestones", []) as Array).duplicate(true)
	_advisor_profit_streak = int(d.get("advisor_profit_streak", 0))
	advisor_slot_profit_unlocked = bool(d.get("advisor_slot_profit_unlocked", false))
	peak_profit_per_turn = float(d.get("advisor_peak_profit", 0.0))

# Fast-shipment agenda: a movement that lands in 1 turn (delivered in under 2).
func _on_goods_movement_agenda(_kind: String, _category: String, transport_turns: int) -> void:
	if transport_turns >= 1 and transport_turns < 2:
		flag_agenda_event(AGENDA_FAST_SHIPMENT)

# Land / NPC-building purchase cost after any Chief Investment "purchase_cost" discount
# (tier3 -10% / tier2 -5% / tier1 +5% surcharge).
func purchase_cost_after_advisor(base_cost: float, ctx: Dictionary = {}) -> float:
	var mult: float = maxf(0.0, 1.0 + float(Modifiers.resolve_pct("purchase_cost", "*", ctx).get("net", 0.0)) / 100.0)
	return base_cost * mult

func is_master_builder_active() -> bool:
	return str(advisor_seats.get("coo", "")) == MASTER_BUILDER_ID

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
	var mult: float = float(MatchState._TIER_MULT.get(advisor_seat_tier(advisor_id, seat_id), 0.0))
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
		var tier_mult: float = float(MatchState._TIER_MULT.get(tier, 0.0))
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
	LabourState._revoke_unavailable_workforce_policies()

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
	var picked := str(pool[MatchState._match_rng_int(pool.size())])
	recruited_advisor_ids.append(picked)
	advisor_acquired.emit(picked)
	advisors_changed.emit()
	return picked

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
	var bldgs := BuildingState.player_building_count()
	var target := MAX_ADVISOR_SLOTS_DEFAULT
	if bldgs >= ADVISOR_SLOT_BUILDINGS_3:
		target += 1
		ResearchState.grant_unlock("Third Advisor Seat")
	if bldgs >= ADVISOR_SLOT_BUILDINGS_4:
		target += 1
		ResearchState.grant_unlock("Fourth Advisor Seat")
	if advisor_slot_profit_unlocked:
		target += 1
		ResearchState.grant_unlock("Fifth Advisor Seat")
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
	if LabourState._count_enabled_workforce_policies() >= 2:
		ev[AGENDA_LABOUR_POLICIES] = true
	return ev

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

func advisor_missions_done(advisor_id: String) -> int:
	return int(advisor_missions_completed.get(advisor_id, 0))

# Advance missions once per turn. I–IV complete the first turn loyalty reaches their
# threshold; V requires loyalty to hold at/above MISSION5_LOYALTY for MISSION5_STREAK_TURNS.
func _check_mission_progress(advisor_id: String) -> bool:
	if not preload("res://scripts/debug_terminal.gd").demo_is_unlocked():
		return false
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
			var research_title := ResearchState.grant_first_locked_in_category(str(tmpl.get("research_category", "")))
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
	MatchState.request_toast("%s reached mission %s — %s" % [str(get_advisor(advisor_id).get("name", advisor_id)), MatchState._roman(mission_num), label], "success")

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
		LabourState.workforce_policies_changed.emit()
	return label

# Re-apply the PERMANENT mission rewards (perm slices + the capstone) after a load,
# based on how many missions each advisor has completed. Temp bonuses aren't restored.
func reapply_mission_modifiers() -> void:
	if not preload("res://scripts/debug_terminal.gd").demo_is_unlocked():
		return
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
	MatchState.request_toast("%s has resigned — loyalty stayed critically low." % str(get_advisor(advisor_id).get("name", advisor_id)), "warning")
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
## a share of company revenue (EconomyConfig). Per-advisor rather than
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
			"roman": MatchState._roman(i + 1),
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
	var pct_text := MatchState._signed_percent_text(pct)
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
