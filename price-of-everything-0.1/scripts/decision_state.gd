extends Node
## DecisionState: the decision-events sim engine (docs/decision-events-spec.md).
##
## Every few turns the player faces a dilemma with 2-3 choices, scoped to a tile,
## building, building type, or the whole company. Hired advisors advocate sides;
## following/ignoring them moves loyalty. Some choices are gated on a seat being
## filled by a TENURED advisor (hired on an earlier turn than the current one).
##
## Sim-side only — the Turn Briefing (turn_briefing.gd) presents the queue and calls
## resolve(); all state mutations run through the sim APIs (Modifiers, MatchState,
## Construction, LoanState, EventScheduler).
##
## Scheduling — a PULSE PIPELINE that leans deterministic (spec §3.2): every few turns
## a pulse PULLS one eligible event and reveals it PULSE_LEAD_TURNS (3) later, so the
## reveal is telegraphed. The gap between pulses is derived from how many events are
## eligible (fuller pool → sooner), clamped to [3,6] with one seeded turn of variation —
## the cadence is deterministic-ish; only WHICH event (the weighted draw) is random.
## The same event TYPE (category) can trigger at most once per CATEGORY_COOLDOWN_TURNS
## (20). Story beats bypass the pulse: they arrive via reserve()/force_draw() and reveal
## at the next DECIDE. All scheduler state persists on a dedicated seeded RNG stream.


# --- Pacing / balance knobs (balance-volatile: gameplay pacing, cash amounts in the
# catalog below are placeholders per architecture rule 7 — tune via the harness). ---
const FIRST_DECISION_TURN := 10
## Productive (non-infrastructure) player buildings required before ambient decisions
## start. Turn number alone was the only gate, so a player who had barely built anything
## still got union claims and substation failures — see _tick_narrative.
const MIN_PRODUCTIVE_BUILDINGS := 2
# The pulse pipeline (leans deterministic): a decision is PULLED on a pulse turn and
# PRESENTED PULSE_LEAD_TURNS later. The gap between pulses is derived from how many
# events are eligible right now — a fuller pool pulses sooner — clamped to [PULSE_MIN,
# PULSE_MAX], with a single seeded ±0/1 turn of variation so it isn't pure clockwork.
const PULSE_MIN := 3
const PULSE_MAX := 6
const PULSE_LEAD_TURNS := 3          # turns between a pull and its reveal (telegraphed)
# Hard rule: the same event TYPE (category) can trigger at most once per this window.
const CATEGORY_COOLDOWN_TURNS := 20
const RECENT_DRAWS_CAP := 16
const HISTORY_CAP := 60

# Loyalty contract (spec §6.2): follow an advocating advisor on a local decision
# +0.5, on a company-scope decision +2.0; every advocating advisor NOT followed
# takes -0.5 regardless of scope.
const LOYALTY_FOLLOW_LOCAL := 0.5
const LOYALTY_FOLLOW_COMPANY := 2.0
const LOYALTY_IGNORE := -0.5

const PRIORITY_STORY := 0
const PRIORITY_MAJOR := 1
const PRIORITY_AMBIENT := 2

signal decision_drawn(decision: Dictionary)
signal decision_resolved(decision: Dictionary, choice_id: String)
signal pending_changed()

## Off in headless runs (unit suite, e2e balance harness) so decisions never
## perturb the balance failure set; tests that exercise decisions enable this
## explicitly. Interactive play enables it at startup.
var enabled: bool = false
## Test/sweep hook: a drawn decision immediately resolves its default_choice
## (loyalty deltas included), so nothing ever blocks commit_turn.
var auto_resolve: bool = false

var _rng := RandomNumberGenerator.new()
var _rng_seed: int = 0
# The queue of decisions awaiting an answer (Turn Briefing shows all of them; each
# entry: {uid, def_id, target, turn_drawn}). Capped; the pulse only pulls into an
# empty queue, but story beats / forced draws can stack on top.
const PENDING_QUEUE_CAP := 4
var pending_queue: Array = []
## Back-compat shim over the queue's head (tests + older callers read/assign a single
## `pending`). Assigning a dict replaces the whole queue; assigning {} clears it.
var pending: Dictionary:
	get:
		return pending_queue[0] if not pending_queue.is_empty() else {}
	set(v):
		pending_queue = [] if v.is_empty() else [v.duplicate(true)]
var _cooldown_until: Dictionary = {}  # def_id -> earliest turn it may fire again
var _fired_once: Dictionary = {}      # def_id -> true (once: definitions)
var _recent_draws: Array = []         # ring buffer of {turn, id, category}
var _reservations: Dictionary = {}    # turn (int) -> def_id (story beats)
var _next_pulse_turn: int = FIRST_DECISION_TURN
var _scheduled_pull: Dictionary = {}  # a pulled decision awaiting its reveal (+lead)
var _history: Array = []              # resolved decisions (politics-panel feed)
var flags: Dictionary = {}            # e.g. "env_exempt:<instance_id>" -> true
var _next_uid: int = 1



# ---------------------------------------------------------------------------
# The catalog (spec §11). Cash amounts are balance-volatile placeholders.
# Every definition keeps >=1 ungated choice; gated choices carry requires_seat.
# ---------------------------------------------------------------------------

const DECISION_DEFINITIONS := {
	# Turn 3, every sandbox start. An old friend of the player's father offers to fill ONE of the
	# two posts that exist, pro bono, for 30 turns. The choice is cheap money versus cheap
	# movement, and both are good — a new player cannot pick wrong, only differently.
	# Verbatim line and gifts are owner-locked. See docs/early-game-onboarding-spec.md §5.4.
	"family_friend": {
		"title": "An Old Friend of the Family",
		"body": "Andrew Keeler knew your father for thirty years, and says he owes him more than he ever repaid. He is offering to sit on your board for nothing — but he will only take one chair.\n\n\"I've negotiated lots of deals with suppliers and banks in the past. But my specialty will always be transporting goods cheap.\"",
		"scope": "company", "category": "governance", "priority": PRIORITY_STORY,
		"target_selector": "company",
		"cooldown_turns": 9999, "weight": 0.0, "default_choice": "coo",
		"choices": [
			{"id": "cfo", "label": "Give him the CFO's chair",
				"effects": [
					{"kind": "seat_founder", "seat": "cfo"},
					{"kind": "founder_loan", "amount": 200.0, "rate": 0.05},
				],
				"advocate_seat": "cfo",
				"stance": "Cheap money now, and someone who reads a term sheet properly."},
			{"id": "coo", "label": "Give him the COO's chair",
				"effects": [
					{"kind": "seat_founder", "seat": "coo"},
					{"kind": "freight_credit", "units": 1000},
					{"kind": "modifier", "domain": "transport_cost", "pct": -20.0,
						"label": "Andrew Keeler: −20% transport costs"},
				],
				"advocate_seat": "coo",
				"stance": "Moving things is most of what you do. I can make it cost less."},
		],
	},
	"planning_pushback": {
		"title": "Planning Pushback",
		"body": "Residents' associations have packed the planning hearing for {target_name}. The build can absorb the consultations — or you can make the problem go away.",
		"scope": "building", "category": "infrastructure", "priority": PRIORITY_AMBIENT,
		"target_selector": "construction_project",
		"cooldown_turns": 20, "weight": 1.0, "default_choice": "consult",
		"choices": [
			{"id": "consult", "label": "Hold consultations",
				"effects": [{"kind": "construction_delta", "turns": 2}],
				"advocate_seat": "cfo",
				"stance": "Patience is free. Goodwill isn't, but it's close."},
			{"id": "accelerate", "label": "Pay for acceleration",
				"effects": [{"kind": "cash", "amount": -50.0}],
				"advocate_seat": "coo",
				"stance": "Every idle turn is a turn the line isn't learning."},
			{"id": "fast_track", "label": "Fast-track the permits",
				"requires_seat": "government_affairs",
				"effects": [{"kind": "cash", "amount": -20.0},
					{"kind": "agenda_tag", "tag": "backroom_deal"}],
				"advocate_seat": "government_affairs",
				"stance": "There's a committee chair who owes me lunch. Twenty covers lunch."},
		],
	},
	"union_demands": {
		"title": "Union Demands",
		"body": "Stewards across your {target_name} operations have tabled a coordinated pay claim, and they have the floor's support.",
		"scope": "building_type", "category": "labour", "priority": PRIORITY_AMBIENT,
		"target_selector": "highest_labour_building_type",
		"cooldown_turns": 25, "weight": 1.0, "default_choice": "hold_line",
		"choices": [
			{"id": "pay_rise", "label": "Concede the pay claim",
				"effects": [{"kind": "modifier", "domain": "labour_headcount", "pct": 20.0,
					"duration_turns": 10, "label": "Union pay deal"}],
				"advocate_seat": "coo",
				"stance": "Lines that stop don't restart cheap. Pay them and keep moving."},
			{"id": "hold_line", "label": "Hold the line on pay",
				"effects": [{"kind": "modifier", "domain": "recipe_output", "pct": -10.0,
					"duration_turns": 10, "label": "Work-to-rule slowdown"}],
				"advocate_seat": "cfo",
				"stance": "A wage rise never goes back down. Ride out the slowdown."},
			{"id": "mediate", "label": "Bring in a mediator",
				"requires_seat": "hr_director",
				"effects": [{"kind": "cash", "amount": -40.0},
					{"kind": "modifier", "domain": "labour_headcount", "pct": 8.0,
						"duration_turns": 10, "label": "Mediated pay deal"}],
				"advocate_seat": "hr_director",
				"stance": "Both sides want a story they can sell. Let me write it."},
		],
	},
	"worker_innovation": {
		"title": "A Better Way",
		"body": "A shift worker at {target_name} has worked out a genuinely better process — the kind the manuals catch up to years later.",
		"scope": "building", "category": "tech", "priority": PRIORITY_AMBIENT,
		"target_selector": "producing_building",
		"cooldown_turns": 25, "weight": 1.0, "default_choice": "adopt",
		"choices": [
			{"id": "adopt", "label": "Adopt it on the line",
				"effects": [{"kind": "modifier", "domain": "recipe_output", "pct": 10.0,
					"duration_turns": 20, "label": "Shop-floor innovation"}],
				"advocate_seat": "technical_director",
				"stance": "Give the line six months with this and it pays for a new one."},
			{"id": "license", "label": "License it out",
				"effects": [{"kind": "cash", "formula": "pct_of_building_revenue", "pct": 50.0}],
				"advocate_seat": "cfo",
				"stance": "Cash today compounds. Cleverness on one line doesn't."},
			{"id": "research", "label": "Fold it into the research programme",
				"requires_seat": "research_director",
				"effects": [{"kind": "grant_unlock", "selector": "matching_building"}],
				"advocate_seat": "research_director",
				"stance": "This isn't a tweak, it's a doorway. Let me take it through properly."},
		],
	},
	"substation_failure": {
		"title": "Substation Failure",
		"body": "The transformer feeding {target_name} died overnight in a shower of copper rain. Everything on the tile is running on goodwill.",
		"scope": "tile", "category": "infrastructure", "priority": PRIORITY_AMBIENT,
		"target_selector": "multi_building_tile",
		"cooldown_turns": 20, "weight": 1.0, "default_choice": "brownout",
		"choices": [
			{"id": "repair", "label": "Emergency repair crew",
				"effects": [{"kind": "cash", "amount": -60.0}]},
			{"id": "brownout", "label": "Ride out the brownout",
				"effects": [{"kind": "modifier", "domain": "recipe_output", "pct": -20.0,
					"duration_turns": 2, "label": "Brownout"}],
				"advocate_seat": "cfo",
				"stance": "Two dim turns cost less than a crew on triple time."},
			{"id": "cannibalise", "label": "Cannibalise spares from stores",
				"requires_seat": "coo",
				"effects": [{"kind": "modifier", "domain": "maintenance", "pct": 15.0,
					"duration_turns": 6, "label": "Cannibalised spares"}],
				"advocate_seat": "coo",
				"stance": "I can keep it lit with what's on the shelf — but we'll be patching patches for a while."},
		],
	},
	"brokers_offer": {
		"title": "The Broker's Offer",
		"body": "A commodity house wants exclusive placement of your {target_name}. Their first offer arrived with a fee attached and a smile painted on.",
		"scope": "company", "category": "market", "priority": PRIORITY_MAJOR,
		"target_selector": "top_produced_good",
		"cooldown_turns": 30, "weight": 1.0, "default_choice": "decline",
		"choices": [
			{"id": "sign", "label": "Sign the placement",
				"effects": [{"kind": "cash", "amount": -80.0},
					{"kind": "modifier", "domain": "market_price", "pct": 10.0,
						"duration_turns": 10, "label": "Broker placement"}]},
			{"id": "decline", "label": "Show them the door",
				"effects": [],
				"advocate_seat": "cfo",
				"stance": "Exclusivity is a leash with a fee attached. We sell fine without them."},
			{"id": "renegotiate", "label": "Renegotiate the terms",
				"requires_seat": "chief_markets",
				"effects": [{"kind": "modifier", "domain": "market_price", "pct": 6.0,
					"duration_turns": 15, "label": "Renegotiated placement"}],
				"advocate_seat": "chief_markets",
				"stance": "Their first offer prices our desperation. We aren't desperate — I'll re-cut it."},
		],
	},
	"environmental_inspection": {
		"title": "Environmental Inspection",
		"body": "Inspectors found runoff downstream of {target_name}, and a journalist found the inspectors.",
		"scope": "building", "category": "environment", "priority": PRIORITY_AMBIENT,
		"target_selector": "fossil_building",
		"cooldown_turns": 20, "weight": 1.0, "default_choice": "pay_fine",
		"weight_after_turn": {80: 2.0},
		"choices": [
			{"id": "pay_fine", "label": "Pay the fine, remediate",
				"effects": [{"kind": "cash", "amount": -75.0}]},
			{"id": "bury_it", "label": "Make it go away",
				"requires_seat": "government_affairs",
				"effects": [{"kind": "modifier", "domain": "recipe_output", "pct": -10.0,
					"duration_turns": 3, "label": "Under investigation"},
					{"kind": "agenda_tag", "tag": "backroom_deal"}],
				"advocate_seat": "government_affairs",
				"stance": "Findings get revised all the time. Give me three weeks and a quiet room."},
			{"id": "clean_audit", "label": "Commission a public clean audit",
				"requires_seat": "sustainability",
				"effects": [{"kind": "cash", "amount": -40.0},
					{"kind": "set_flag", "key": "env_exempt"},
					{"kind": "agenda_tag", "tag": "clean_commitment"}],
				"advocate_seat": "sustainability",
				"stance": "Own it in public once and this building stops being a target forever."},
		],
	},
	"headhunters": {
		"title": "Headhunters Circling",
		"body": "A rival operator is quietly poaching your best {target_name} crews — the ones who make the numbers look easy.",
		"scope": "building_type", "category": "labour", "priority": PRIORITY_AMBIENT,
		"target_selector": "highest_labour_building_type",
		"cooldown_turns": 25, "weight": 1.0, "default_choice": "let_go",
		"choices": [
			{"id": "match_pay", "label": "Match their offers",
				"effects": [{"kind": "modifier", "domain": "labour_headcount", "pct": 15.0,
					"duration_turns": 8, "label": "Counter-offers"}],
				"advocate_seat": "coo",
				"stance": "Replacing a trained crew costs double what keeping one does."},
			{"id": "let_go", "label": "Wish them well",
				"effects": [{"kind": "modifier", "domain": "recipe_output", "pct": -15.0,
					"duration_turns": 4, "label": "Retraining new crews"}],
				"advocate_seat": "cfo",
				"stance": "Nobody is irreplaceable, and panic raises are how payrolls rot."},
			{"id": "retention", "label": "Stand up a retention programme",
				"requires_seat": "hr_director",
				"effects": [{"kind": "cash", "amount": -50.0},
					{"kind": "modifier", "domain": "labour_headcount", "pct": 5.0,
						"duration_turns": 8, "label": "Retention programme"}],
				"advocate_seat": "hr_director",
				"stance": "People rarely leave for money alone. Give me a budget and a week."},
		],
	},
	"land_deal": {
		"title": "The Land Deal",
		"body": "A developer wants your spare frontage on {target_name} — and they're paying over the odds to get it quietly.",
		"scope": "tile", "category": "land", "priority": PRIORITY_AMBIENT,
		"target_selector": "landbank_tile",
		"cooldown_turns": 30, "weight": 1.0, "default_choice": "keep",
		"choices": [
			{"id": "sell", "label": "Sell at their price",
				"effects": [{"kind": "sell_land", "price_mult": 3.0}],
				"advocate_seat": "cfo",
				"stance": "Book the profit. Land is only worth what someone overpays for it."},
			{"id": "keep", "label": "Keep the land",
				"effects": []},
			{"id": "counter", "label": "Counter at a premium",
				"requires_seat": "chief_investment",
				"effects": [{"kind": "sell_land", "price_mult": 4.0},
					{"kind": "schedule_event", "in_turns": 5, "event": {
						"kind": "decision_followup", "severity": "warning",
						"title": "The developer breaks ground",
						"body": "Construction crews arrive on the frontage you sold — land nearby is repricing.",
						"persistent": false, "auto_dismiss_turns": 4,
						"modifiers": [{"domain": "purchase_cost", "pct": 100.0,
							"label": "Development land premium",
							"target_match": {"tile_id": "@target"}}],
					}}],
				"advocate_seat": "chief_investment",
				"stance": "They budgeted for a counter. And once they build, every acre around it reprices — sell high, then watch."},
		],
	},
	# Story one-shot: SolvencyState force-draws this the first time cash hits −£500 with
	# a CFO seated. The CFO proposes it, so accepting follows them (+2.0 company scope),
	# refusing snubs them (−0.5).
	# The carbon levy's advance notice (decarbonisation squeeze): PolicyState reserves
	# this for turn 90 — a critical, non-dismissible government notice the player must
	# read and acknowledge before the turn can end. Single choice, no effects; the levy
	# itself lands at turn 101 regardless.
	"carbon_tax_notice": {
		"title": "Government Notice: Carbon Levy",
		# Owner copy — shown big + bold above the body.
		"headline": "The new government is implementing a carbon tax of 100% of market price on anything that consumes coal, crude oil or processed oil. Many buildings will be affected. This will ramp up from turn 91 to turn 101. Our input costs will increase dramatically. We should look into some alternatives.",
		# LOREM — owner lore pending.
		"body": "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt. Nuntius gravis a ministerio venit: vectigal carbonis rei publicae imponetur.",
		"scope": "company", "category": "story", "priority": PRIORITY_STORY,
		"target_selector": "company",
		"once": true, "cooldown_turns": 9999, "weight": 1.0, "default_choice": "understood",
		"choices": [
			{"id": "understood", "label": "Understood",
				"effects": [{"kind": "none",
					"describe": "The levy ramps up between turns 91 and 101, then escalates further in later phases. Clean routes and green power are exempt."}]},
		],
	},
	# The green subsidy's announcement — same blocking pattern, reserved by PolicyState
	# to present on turn 100's DECIDE (the subsidy itself starts at turn 105).
	"green_subsidy_notice": {
		"title": "Government Notice: Green Energy Subsidy",
		# Owner copy — shown big + bold above the body.
		"headline": "The government wants to speed up the transition away from hydrocarbon power. They will subsidise green power production starting with turn 105.",
		# LOREM — owner lore pending.
		"body": "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Praesentium subsidium energiae viridis nuntiatur; qui sol, ventus et aqua colunt, remunerabuntur.",
		"scope": "company", "category": "story", "priority": PRIORITY_STORY,
		"target_selector": "company",
		"once": true, "cooldown_turns": 9999, "weight": 1.0, "default_choice": "understood",
		"choices": [
			{"id": "understood", "label": "Understood",
				"effects": [{"kind": "none",
					"describe": "From turn 105 every MW of green power you generate (solar, wind, hydro, biomass-fired) earns a government subsidy. The programme runs for roughly 80 turns before it lapses."}]},
		],
	},
	# The subsidy's wind-down warning — blocking, reserved by PolicyState to present on
	# turn 180's DECIDE (payments start shrinking at 181, gone at 191).
	"green_subsidy_end_notice": {
		"title": "Government Notice: Subsidy Winding Down",
		# Owner-directed copy — shown big + bold above the body.
		"headline": "The green power subsidy is ending. Starting next turn, payments will fall by 10% each turn until they stop completely at turn 191.",
		# LOREM — owner lore pending.
		"body": "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aerarium subsidii viridis exhauritur; merces paulatim minuentur donec cessent.",
		"scope": "company", "category": "story", "priority": PRIORITY_STORY,
		"target_selector": "company",
		"once": true, "cooldown_turns": 9999, "weight": 1.0, "default_choice": "understood",
		"choices": [
			{"id": "understood", "label": "Understood",
				"effects": [{"kind": "none",
					"describe": "Green power still earns the subsidy through the wind-down — 90% next turn, shrinking 10% per turn, ending at turn 191."}]},
		],
	},
	"distressed_asset": {
		"title": "Distressed Asset Program",
		"body": "It's not pretty and we don't have many other options — but I spoke to some outside investors. They'll buy our buildings to clear the debts and float us a rescue loan.",
		"scope": "company", "category": "story", "priority": PRIORITY_STORY,
		"target_selector": "company",
		"once": true, "cooldown_turns": 9999, "weight": 1.0, "default_choice": "refuse",
		"choices": [
			{"id": "accept", "label": "Accept the program",
				"effects": [{"kind": "distressed_program",
					"describe": "Investors buy ALL your buildings at 1.5x market value, and a £500 loan lands — interest-free for 10 turns, then normal interest for the usual term."}],
				"advocate_seat": "cfo",
				"stance": "It clears the debt today and buys us another shot. I don't love it either, but the alternative is the end."},
			{"id": "refuse", "label": "Tough it out",
				"effects": [{"kind": "none", "describe": "Keep every building and try to trade your way out — bankruptcy looms if profit doesn't turn."}]},
		],
	},
}


func _ready() -> void:
	# Headless runs (unit suite, e2e harness) keep decisions off so the balance
	# failure set never shifts under them; tests enable explicitly.
	enabled = DisplayServer.get_name() != "headless"
	_reseed(int(MatchState.match_rng_seed))
	await get_tree().process_frame
	MatchState.state_reset.connect(reset)

## Wired centrally by TurnManager._wire_sim_listeners, AFTER Modifiers' pruning.
func _on_phase_started(phase: int) -> void:
	if phase == TurnManager.Phase.NARRATIVE:
		_tick_narrative()

func has_pending() -> bool:
	return not pending.is_empty()

func history() -> Array:
	return _history.duplicate()

## The turn the family friend offers to join. Fixed rather than random: it is the first real
## decision a new player makes, and it must land before they have committed to a build order.
const FOUNDER_DECISION_TURN := 3


## Andrew's tenure ends: he vacates, the post opens, and the player is told plainly so the
## sudden loss of his modifier is legible rather than mysterious.
func _retire_founder() -> void:
	var seat := MatchState.founder_seat
	var seat_name := str(MatchState.SEAT_DEFINITIONS.get(seat, {}).get("seat_name", seat))
	MatchState.release_founder()
	EventScheduler.emit_event({
		"kind": "founder_departs",
		"severity": "info",
		"title": "Andrew Keeler stands down",
		"body": "Andrew has served his time as %s and is standing down, with his debt to your family considered paid. He wishes you luck. The chair is open — you can hire for it now." % seat_name,
		"source": "advisors",
		"persistent": false,
		"auto_dismiss_turns": 3,
	})


## Story beats (carbon arc etc.) reserve their turn ahead of time: the reserved
## definition fires unconditionally on that turn and random draws stay clear of
## it (that turn and the turn before).
func reserve(turn: int, def_id: String) -> void:
	if DECISION_DEFINITIONS.has(def_id):
		_reservations[turn] = def_id

func reset() -> void:
	pending = {}
	_cooldown_until.clear()
	_fired_once.clear()
	_recent_draws.clear()
	_reservations.clear()
	_history.clear()
	flags.clear()
	# The family friend arrives on a fixed turn in every sandbox match. Reserved here rather
	# than scheduled elsewhere so it survives a reset and cannot be crowded out by an ambient
	# draw. Suppressed for tutorials at fire time (the ruleset is not loaded yet at reset).
	_reservations[FOUNDER_DECISION_TURN] = "family_friend"
	_next_pulse_turn = FIRST_DECISION_TURN
	_scheduled_pull = {}
	_next_uid = 1
	_reseed(int(MatchState.match_rng_seed))
	pending_changed.emit()

func _reseed(match_seed: int) -> void:
	# Stable arithmetic derivation (never GDScript hash() — not version-stable).
	_rng_seed = match_seed ^ 0xDEC1DE5
	_rng.seed = _rng_seed


# ---------------------------------------------------------------------------
# Scheduling (spec §3.2)
# ---------------------------------------------------------------------------

func _tick_narrative() -> void:
	if not enabled:
		return
	var turn := int(TurnManager.current_turn)
	# Tutorial pocket: no decisions while the coach is running.
	if Tutorial.active:
		return
	# Ambient decisions need something to be ABOUT. Every one of them presumes a going
	# concern — union pay claims need crews, headhunters need someone worth poaching, a
	# substation failure needs a tile with plant on it, a broker wants a good you actually
	# ship. Below MIN_PRODUCTIVE_BUILDINGS the board stays quiet instead of inventing a
	# crisis at a company that barely exists. Infrastructure doesn't count: laying two
	# cables is not an operation with staff.
	var ambient_ok := _productive_building_count() >= MIN_PRODUCTIVE_BUILDINGS
	if not ambient_ok:
		# Hold the pulse clock as well, so the first decision arrives a turn or more AFTER
		# the threshold is met rather than the instant the second building goes up. Set to
		# turn + 1 rather than a fresh _pulse_interval() because that draws from the seeded
		# RNG, and consuming draws here would desync an otherwise identical run.
		_next_pulse_turn = maxi(_next_pulse_turn, turn + 1)
	# A) Reveal a pulled decision whose lead time is up. Promoting into the queue in
	#    NARRATIVE of turn X surfaces it at DECIDE of X+1 — so this fires when
	#    X+1 == show_turn (== pull_turn + PULSE_LEAD_TURNS). Decisions can stack (the
	#    Briefing shows a queue), so a reveal is only held back by a full queue.
	if ambient_ok and not _scheduled_pull.is_empty() and pending_queue.size() < PENDING_QUEUE_CAP \
			and turn + 1 >= int(_scheduled_pull.get("show_turn", 0)):
		_promote_scheduled()
	# B) Story reservation: fires immediately (no pulse lead) and MAY stack on an
	#    already-pending decision; holds only when the queue is full. Deliberately NOT
	#    gated by ambient_ok — these are scripted beats (the carbon-levy notice at t90 is
	#    blocking by design) and a reservation is ERASED as it fires, so skipping its turn
	#    would drop that beat from the run permanently.
	if _reservations.has(turn) and pending_queue.size() < PENDING_QUEUE_CAP:
		var def_id := str(_reservations[turn])
		_reservations.erase(turn)
		# The tutorial teaches one chain; a board appointment is noise inside it.
		if not (def_id == "family_friend" and bool(MatchState.ruleset.get("tutorial_enabled", false))):
			_draw(def_id)
	# The founder's pro bono tenure runs out — he vacates and the post opens for a real hire.
	if not MatchState.founder_tenure_expired() and turn >= MatchState.founder_leaves_turn:
		_retire_founder()
	# C) Pulse: only into a QUIET board — no pending decision, nothing in flight, and
	#    no story beat landing next turn.
	elif ambient_ok and not has_pending() and _scheduled_pull.is_empty() \
			and not _reservations.has(turn + 1) \
			and turn >= FIRST_DECISION_TURN and turn >= _next_pulse_turn:
		var picked := _pick_random_definition(turn)
		if picked == "":
			_next_pulse_turn = turn + 1          # nothing eligible; look again next turn
		else:
			_pull(picked, turn)
			_next_pulse_turn = turn + _pulse_interval(turn)
			if auto_resolve:
				# Headless/sweeps don't wait out the lead — reveal immediately.
				_promote_scheduled()
	if auto_resolve:
		auto_resolve_pending()

# The gap to the next pulse, leaning deterministic: derived from how many events are
# eligible right now (a fuller pool pulses sooner), plus one seeded turn of variation.
## Player-owned buildings that actually run something. Infrastructure (cables, roads,
## pipes, rail) is excluded: it has no crew to poach and no line to stop, so it should not
## count toward "this company is a going concern".
func _productive_building_count() -> int:
	var n := 0
	for b in MatchState.buildings.values():
		if not (b is Dictionary) or not MatchState.is_player_owned(b):
			continue
		var bd: Dictionary = Catalog.get_building(str((b as Dictionary).get("building_id", "")))
		if str(bd.get("category", "")).to_lower() == "infrastructure":
			continue
		n += 1
	return n


func _pulse_interval(turn: int) -> int:
	var eligible := _eligible_ids(turn).size()
	var base := clampi(PULSE_MAX - int(eligible / 2), PULSE_MIN, PULSE_MAX)
	return clampi(base + int(_rng.randi() % 2), PULSE_MIN, PULSE_MAX)

# Definitions that could fire this turn (cheap filters only — no target/RNG): not a
# story beat, not a spent one-shot, off its own cooldown, and its TYPE (category) hasn't
# fired within CATEGORY_COOLDOWN_TURNS (the hard 20-turn per-type spacing rule).
func _eligible_ids(turn: int) -> Array:
	var out: Array = []
	var def_ids: Array = DECISION_DEFINITIONS.keys()
	def_ids.sort()
	for def_id: String in def_ids:
		var def: Dictionary = DECISION_DEFINITIONS[def_id]
		if int(def.get("priority", PRIORITY_AMBIENT)) == PRIORITY_STORY:
			continue
		if bool(def.get("once", false)) and _fired_once.has(def_id):
			continue
		if turn < int(_cooldown_until.get(def_id, 0)):
			continue
		if _category_fired_since(str(def.get("category", "")), turn - CATEGORY_COOLDOWN_TURNS + 1):
			continue
		out.append(def_id)
	return out

func _pick_random_definition(turn: int) -> String:
	var candidates: Array = []
	for def_id in _eligible_ids(turn):
		var def: Dictionary = DECISION_DEFINITIONS[def_id]
		var target := _select_target(str(def.get("target_selector", "")), def)
		if target.is_empty():
			continue
		var weight := float(def.get("weight", 1.0))
		var after: Dictionary = def.get("weight_after_turn", {})   # arc coupling {turn: mult}
		for threshold in after.keys():
			if turn >= int(threshold):
				weight *= float(after[threshold])
		candidates.append({"id": def_id, "weight": weight,
			"priority": int(def.get("priority", PRIORITY_AMBIENT))})
	if candidates.is_empty():
		return ""
	# Priority tiering: only the most important tier present enters the weighted draw.
	var best_priority := 99
	for c in candidates:
		best_priority = mini(best_priority, int(c.priority))
	var pool: Array = candidates.filter(func(c) -> bool: return int(c.priority) == best_priority)
	var total := 0.0
	for c in pool:
		total += float(c.weight)
	if total <= 0.0:
		return ""
	var roll := _rng.randf() * total
	for c in pool:
		roll -= float(c.weight)
		if roll <= 0.0:
			return str(c.id)
	return str(pool.back().id)

func _category_fired_since(category: String, since_turn: int) -> bool:
	for entry in _recent_draws:
		if str(entry.get("category", "")) == category and int(entry.get("turn", 0)) >= since_turn:
			return true
	return false

# Build a decision (target-select + record cooldown/recency/uid). Recency is stamped
# at PULL time, so the 20-turn per-type spacing is measured pull-to-pull (and every
# pull reveals a fixed lead later, so shown events are spaced the same).
func _make_decision(def_id: String, turn: int) -> Dictionary:
	var def: Dictionary = DECISION_DEFINITIONS.get(def_id, {})
	if def.is_empty():
		return {}
	var target := _select_target(str(def.get("target_selector", "")), def)
	if target.is_empty():
		return {}
	var d := {"uid": "dec_%d" % _next_uid, "def_id": def_id, "target": target, "turn_drawn": turn}
	_next_uid += 1
	_fired_once[def_id] = true
	_cooldown_until[def_id] = turn + int(def.get("cooldown_turns", 20))
	_recent_draws.append({"turn": turn, "id": def_id, "category": str(def.get("category", ""))})
	while _recent_draws.size() > RECENT_DRAWS_CAP:
		_recent_draws.pop_front()
	return d

# Immediate draw (story reservations + force_draw/cheats): surfaces at the next DECIDE,
# no pulse lead. Appends to the queue — decisions can stack up to PENDING_QUEUE_CAP.
func _draw(def_id: String) -> bool:
	if pending_queue.size() >= PENDING_QUEUE_CAP:
		return false
	var d := _make_decision(def_id, int(TurnManager.current_turn))
	if d.is_empty():
		return false
	pending_queue.append(d)
	decision_drawn.emit(d)
	pending_changed.emit()
	return true

# Pulse draw: hold the decision as scheduled, to reveal PULSE_LEAD_TURNS later.
func _pull(def_id: String, turn: int) -> bool:
	var d := _make_decision(def_id, turn)
	if d.is_empty():
		return false
	d["show_turn"] = turn + PULSE_LEAD_TURNS
	_scheduled_pull = d
	_emit_pulse_forewarn(turn)
	print("[Decisions] pulled '%s' at turn %d → reveals turn %d" % [def_id, turn, turn + PULSE_LEAD_TURNS])
	pending_changed.emit()
	return true

func _promote_scheduled() -> void:
	if _scheduled_pull.is_empty():
		return
	# The target was captured up to PULSE_LEAD_TURNS ago; if it has gone stale (building
	# sold/demolished/gone, construction finished), re-select so the decision still makes
	# sense — and drop it entirely if nothing valid remains, rather than present a dud.
	var def_id := str(_scheduled_pull.get("def_id", ""))
	var def: Dictionary = DECISION_DEFINITIONS.get(def_id, {})
	if not _target_still_valid(def, _scheduled_pull.get("target", {})):
		var fresh := _select_target(str(def.get("target_selector", "")), def)
		if fresh.is_empty():
			print("[Decisions] dropped '%s' — target went stale before reveal" % def_id)
			_scheduled_pull = {}
			pending_changed.emit()
			return
		_scheduled_pull["target"] = fresh
	var d: Dictionary = _scheduled_pull.duplicate(true)
	d.erase("show_turn")
	_scheduled_pull = {}
	pending_queue.append(d)
	print("[Decisions] presenting '%s' (turn %d)" % [str(d.get("def_id", "")), int(TurnManager.current_turn)])
	decision_drawn.emit(d)
	pending_changed.emit()

# Is the drawn target still real? Instance/tile-scoped decisions need their entity to
# still exist and be player-owned; company/building_type decisions never go stale.
func _target_still_valid(def: Dictionary, target: Dictionary) -> bool:
	if target.is_empty():
		return false
	var iid := str(target.get("instance_id", ""))
	if iid != "":
		return MatchState.buildings.has(iid) and MatchState.is_player_owned(MatchState.get_building(iid))
	var tid := str(target.get("tile_id", ""))
	if tid != "" and str(def.get("scope", "")) == "tile":
		return MatchState.tile_buildings.has(tid) and not (MatchState.tile_buildings.get(tid, []) as Array).is_empty()
	return true

## Clear every pending/scheduled decision with no effects — the presentation layer's
## safety valve when it somehow has nothing to show, so the game can never soft-lock.
func abort_pending() -> void:
	pending_queue.clear()
	_scheduled_pull = {}
	pending_changed.emit()

# A quiet, generic heads-up so the lead time is legible without spoiling the specifics.
# DISABLED (owner 2026-07-10): the "decision is reaching your desk" update is reserved
# for a later feature — flip the const back on when that lands.
const PULSE_FOREWARN_ENABLED := false

func _emit_pulse_forewarn(_turn: int) -> void:
	if not PULSE_FOREWARN_ENABLED:
		return
	if auto_resolve:
		return
	EventScheduler.emit_event({
		"kind": "decision_incoming",
		"severity": "info",
		"title": "A decision is reaching your desk",
		"body": "Word of a matter needing your call — expect it in about %d turns." % PULSE_LEAD_TURNS,
		"source": "decisions",
		"persistent": false,
		"auto_dismiss_turns": PULSE_LEAD_TURNS + 1,
	})

## Debug/test hook: force a definition to draw now (respecting target selection).
## Stacks onto the queue; only refuses when the queue is full.
func force_draw(def_id: String) -> String:
	if not DECISION_DEFINITIONS.has(def_id):
		return "unknown decision '%s'" % def_id
	if pending_queue.size() >= PENDING_QUEUE_CAP:
		return "decision queue is full (%d pending)" % pending_queue.size()
	if not _draw(def_id):
		return "no eligible target for '%s' right now" % def_id
	if auto_resolve:
		auto_resolve_pending()
	# Interactive path: decision_drawn/pending_changed reach the Turn Briefing, which
	# auto-expands (a pending decision makes the turn critical).
	return ""


# ---------------------------------------------------------------------------
# Target selection — deterministic: candidates sorted by stable keys, then one
# seeded pick. Targets: {scope, name, instance_id?, building_id?, tile_id?, good_id?}
# ---------------------------------------------------------------------------

const BuildingNaming := preload("res://scripts/building_naming.gd")

func _select_target(selector: String, def: Dictionary) -> Dictionary:
	var scope := str(def.get("scope", "company"))
	match selector:
		"company":
			return {"scope": "company", "name": "the company"}
		"construction_project":
			var ids: Array = []
			for iid in Construction.construction_projects.keys():
				var p: Dictionary = Construction.construction_projects[iid]
				if str(p.get("status", "")) == Construction.STATUS_UNDER_CONSTRUCTION \
						and int(p.get("turns_remaining", 0)) >= 2:
					ids.append(str(iid))
			ids.sort()
			if ids.is_empty():
				return {}
			var iid := str(ids[_rng.randi() % ids.size()])
			var p: Dictionary = Construction.construction_projects[iid]
			return {"scope": scope, "instance_id": iid,
				"tile_id": str(p.get("tile_id", "")),
				"name": str(p.get("name", iid))}
		"highest_labour_building_type":
			# Building type with the largest labour bill proxy: instance count x
			# catalog labour headcount. Ties break to the lexicographically first id.
			var bills: Dictionary = {}
			for b in MatchState.buildings.values():
				if not MatchState.is_player_owned(b):
					continue
				var bid := str(b.get("building_id", ""))
				var cat: Dictionary = Catalog.get_building(bid)
				var heads := int(cat.get("labour_unskilled_required", 0)) \
					+ int(cat.get("labour_skilled_required", 0)) \
					+ int(cat.get("labour_h_skilled_required", 0))
				if heads <= 0:
					continue
				bills[bid] = float(bills.get(bid, 0.0)) + float(heads)
			var best_bid := ""
			var best_bill := 0.0
			var bids: Array = bills.keys()
			bids.sort()
			for bid: String in bids:
				if float(bills[bid]) > best_bill:
					best_bill = float(bills[bid])
					best_bid = bid
			if best_bid == "":
				return {}
			return {"scope": scope, "building_id": best_bid,
				"name": str(Catalog.get_building(best_bid).get("display_name", best_bid))}
		"producing_building":
			var reports: Array = Production.last_turn_reports()
			var ids2: Array = []
			for r in reports:
				var iid2 := str(r.get("instance_id", ""))
				if iid2 != "" and MatchState.is_player_owned(MatchState.get_building(iid2)):
					ids2.append(iid2)
			ids2.sort()
			if ids2.is_empty():
				return {}
			var picked := str(ids2[_rng.randi() % ids2.size()])
			return {"scope": scope, "instance_id": picked,
				"tile_id": str(MatchState.get_building(picked).get("tile_id", "")),
				"name": _building_label(picked)}
		"multi_building_tile":
			var per_tile: Dictionary = {}
			for b in MatchState.buildings.values():
				if MatchState.is_player_owned(b):
					var tid := str(b.get("tile_id", ""))
					per_tile[tid] = int(per_tile.get(tid, 0)) + 1
			var tiles: Array = []
			for tid: String in per_tile.keys():
				if int(per_tile[tid]) >= 2:
					tiles.append(tid)
			tiles.sort()
			if tiles.is_empty():
				return {}
			var tile := str(tiles[_rng.randi() % tiles.size()])
			return {"scope": scope, "tile_id": tile, "name": Catalog.tile_label(tile)}
		"top_produced_good":
			var value_by_good: Dictionary = {}
			for r in Production.last_turn_reports():
				for gid in (r.get("outputs_produced", {}) as Dictionary):
					var q := int(r.outputs_produced[gid])
					value_by_good[str(gid)] = float(value_by_good.get(str(gid), 0.0)) \
						+ float(q) * MarketState.get_price(str(gid))
			var best_gid := ""
			var best_value := 0.0
			var gids: Array = value_by_good.keys()
			gids.sort()
			for gid: String in gids:
				if float(value_by_good[gid]) > best_value:
					best_value = float(value_by_good[gid])
					best_gid = gid
			if best_gid == "":
				return {}
			return {"scope": scope, "good_id": best_gid,
				"name": str(Catalog.get_good(best_gid).get("display_name", best_gid))}
		"fossil_building":
			var ids3: Array = []
			for b in MatchState.buildings.values():
				if not MatchState.is_player_owned(b):
					continue
				var iid3 := str(b.get("instance_id", ""))
				if flags.has("env_exempt:%s" % iid3):
					continue
				var rtype := str(Catalog.get_recipe(str(b.get("recipe_id", ""))).get("recipe_type", "")).to_lower()
				if rtype.contains("mining") or str(b.get("building_id", "")) == "b_003":
					ids3.append(iid3)
			ids3.sort()
			if ids3.is_empty():
				return {}
			var picked3 := str(ids3[_rng.randi() % ids3.size()])
			return {"scope": scope, "instance_id": picked3,
				"tile_id": str(MatchState.get_building(picked3).get("tile_id", "")),
				"name": _building_label(picked3)}
		"landbank_tile":
			# Empty landbank tiles only: bought patches with no player buildings or
			# projects on them, so a sale can never undercut a footprint.
			var occupied: Dictionary = {}
			for b in MatchState.buildings.values():
				occupied[str(b.get("tile_id", ""))] = true
			for p2 in Construction.construction_projects.values():
				occupied[str(p2.get("tile_id", ""))] = true
			var tiles2: Array = []
			for tid: String in MatchState.tile_land_owned.keys():
				if occupied.has(tid):
					continue
				if MatchState.get_tile_land_owned(tid) >= MatchState.DEFAULT_TILE_LAND_OWNED + 2 * MatchState.LAND_PATCH_SIZE:
					tiles2.append(tid)
			tiles2.sort()
			if tiles2.is_empty():
				return {}
			var tile2 := str(tiles2[_rng.randi() % tiles2.size()])
			return {"scope": scope, "tile_id": tile2, "name": Catalog.tile_label(tile2)}
	return {}

func _building_label(instance_id: String) -> String:
	var b: Dictionary = MatchState.get_building(instance_id)
	return BuildingNaming.label_for_tile(str(b.get("tile_id", "")), instance_id,
		str(b.get("building_id", "")), str(b.get("recipe_id", "")))


# ---------------------------------------------------------------------------
# Presentation view — everything the dialog needs, computed fresh each open.
# ---------------------------------------------------------------------------

# The queued decision with this uid ("" = the queue head).
func _pending_by_uid(uid: String) -> Dictionary:
	if uid == "":
		return pending
	for d in pending_queue:
		if str(d.get("uid", "")) == uid:
			return d
	return {}

## Every queued decision expanded for display (the Turn Briefing's decision items).
func pending_views() -> Array:
	var out: Array = []
	for d in pending_queue:
		var v := pending_view(str(d.get("uid", "")))
		if not v.is_empty():
			out.append(v)
	return out

## A pending decision expanded for display: definition text with the target
## substituted, per-choice availability/lock reasons, upfront cash costs and loan
## shortfalls, consequence lines, and eligible advocates with loyalty stakes.
## uid "" = the queue head (back-compat with single-decision callers).
func pending_view(uid: String = "") -> Dictionary:
	var d := _pending_by_uid(uid)
	if d.is_empty():
		return {}
	var def: Dictionary = DECISION_DEFINITIONS[str(d.def_id)]
	var target: Dictionary = d.target
	var scope := str(def.get("scope", "company"))
	var follow_delta := LOYALTY_FOLLOW_COMPANY if scope == "company" else LOYALTY_FOLLOW_LOCAL
	var choices: Array = []
	for choice: Dictionary in def.get("choices", []):
		var seat := str(choice.get("requires_seat", ""))
		var available := seat == "" or _seat_tenured(seat)
		var lock_reason := ""
		if not available:
			lock_reason = "Requires a seated %s (hired at least one turn ago)" \
				% _seat_name(seat)
		var cost := _upfront_cost(choice)
		var shortfall := loan_needed_for(cost)
		choices.append({
			"id": str(choice.id),
			"label": str(choice.get("label", "")),
			"available": available,
			"lock_reason": lock_reason,
			"consequence": _describe_effects(choice.get("effects", []), target),
			"upfront_cost": cost,
			"loan_shortfall": shortfall,
			"advocate": _advocate_view(choice, follow_delta),
		})
	return {
		"uid": str(d.uid),
		"title": str(def.get("title", "")),
		"headline": str(def.get("headline", "")),
		"body": str(def.get("body", "")).replace("{target_name}", str(target.get("name", ""))),
		"scope": scope,
		"target": target,
		"choices": choices,
	}

func _advocate_view(choice: Dictionary, follow_delta: float) -> Dictionary:
	var seat := str(choice.get("advocate_seat", ""))
	if seat == "":
		return {}
	var aid := _tenured_advisor_in_seat(seat)
	if aid == "":
		return {}
	var advisor: Dictionary = MatchState.get_advisor(aid)
	var stance := str(choice.get("stance", ""))
	var overrides: Dictionary = choice.get("stance_overrides", {})
	stance = str(overrides.get(aid, stance))
	return {
		"advisor_id": aid,
		"seat_id": seat,
		"seat_name": _seat_name(seat),
		"name": str(advisor.get("name", aid)),
		"initials": str(advisor.get("initials", "?")),
		"portrait_path": str(advisor.get("portrait_path", "")),
		"accent": advisor.get("portrait_color", Color("#53687A")),
		"stance": stance,
		"follow_delta": follow_delta,
		"ignore_delta": LOYALTY_IGNORE,
	}

func _seat_name(seat_id: String) -> String:
	return str((MatchState.SEAT_DEFINITIONS.get(seat_id, {}) as Dictionary).get("seat_name", seat_id))

# Gate + advocacy eligibility: the seat is filled AND its occupant was hired on an
# earlier turn (the 1-turn tenure rule — you can't panic-hire through a dilemma).
func _seat_tenured(seat_id: String) -> bool:
	return _tenured_advisor_in_seat(seat_id) != ""

func _tenured_advisor_in_seat(seat_id: String) -> String:
	var aid := MatchState.get_advisor_in_seat(seat_id)
	if aid == "" or not MatchState.is_advisor_tenured(aid):
		return ""
	return aid

func _upfront_cost(choice: Dictionary) -> float:
	var cost := 0.0
	for eff: Dictionary in choice.get("effects", []):
		if str(eff.get("kind", "")) == "cash" and eff.has("amount") and float(eff.amount) < 0.0:
			cost += -float(eff.amount)
	return cost


# ---------------------------------------------------------------------------
# Resolution — the ONE mutation entry point the dialog calls.
# ---------------------------------------------------------------------------

## Resolve a queued decision by choice. uid "" = the queue head (back-compat).
func resolve(choice_id: String, uid: String = "") -> String:
	var d := _pending_by_uid(uid)
	if d.is_empty():
		return "no pending decision"
	var def: Dictionary = DECISION_DEFINITIONS[str(d.def_id)]
	var choice := _find_choice(def, choice_id)
	if choice.is_empty():
		return "unknown choice '%s'" % choice_id
	var seat := str(choice.get("requires_seat", ""))
	if seat != "" and not _seat_tenured(seat):
		return "choice '%s' requires a seated, tenured %s" % [choice_id, _seat_name(seat)]
	var target: Dictionary = d.target
	var view := pending_view(str(d.uid))   # snapshot advocates BEFORE effects mutate state
	_execute_effects(choice.get("effects", []), target)
	_apply_decision_loyalty(view, choice_id)
	var record := {
		"uid": str(d.uid),
		"def_id": str(d.def_id),
		"title": str(def.get("title", "")),
		"choice_id": choice_id,
		"choice_label": str(choice.get("label", "")),
		"target_name": str(target.get("name", "")),
		"turn": int(TurnManager.current_turn),
	}
	_history.append(record)
	while _history.size() > HISTORY_CAP:
		_history.pop_front()
	var resolved := d.duplicate(true)
	pending_queue.erase(d)
	MatchState.request_toast("%s — %s" % [str(def.get("title", "")), str(choice.get("label", ""))], "info")
	EventScheduler.emit_event({
		"kind": "decision_resolved",
		"severity": "info",
		"title": "Decision: %s" % str(def.get("title", "")),
		"body": "%s — %s" % [str(choice.get("label", "")), _describe_effects(choice.get("effects", []), target)],
		"source": "decisions",
		"persistent": false,
		"auto_dismiss_turns": 4,
	})
	decision_resolved.emit(resolved, choice_id)
	pending_changed.emit()
	return ""

## Non-interactive path (tests, sweeps, skip tooling): resolve EVERY queued decision's
## default choice — loyalty deltas apply exactly as if the player picked them.
func auto_resolve_pending() -> void:
	var guard := 0
	while not pending_queue.is_empty() and guard < PENDING_QUEUE_CAP + 1:
		guard += 1
		var d: Dictionary = pending_queue[0]
		var def: Dictionary = DECISION_DEFINITIONS[str(d.def_id)]
		var err := resolve(str(def.get("default_choice", "")), str(d.uid))
		if err != "":
			push_warning("[DecisionState] auto-resolve failed: %s" % err)
			pending_queue.erase(d)
			pending_changed.emit()

func _find_choice(def: Dictionary, choice_id: String) -> Dictionary:
	for choice: Dictionary in def.get("choices", []):
		if str(choice.id) == choice_id:
			return choice
	return {}

func _apply_decision_loyalty(view: Dictionary, choice_id: String) -> void:
	for c: Dictionary in view.get("choices", []):
		var adv: Dictionary = c.get("advocate", {})
		if adv.is_empty():
			continue
		var delta := float(adv.follow_delta) if str(c.id) == choice_id else LOYALTY_IGNORE
		MatchState.apply_decision_loyalty(str(adv.advisor_id), delta, str(view.get("title", "")))


# ---------------------------------------------------------------------------
# Effects engine — every kind maps to an existing sim API.
# ---------------------------------------------------------------------------

func _execute_effects(effects: Array, target: Dictionary) -> void:
	for eff: Dictionary in effects:
		match str(eff.get("kind", "")):
			"modifier":
				for m in _build_modifiers(eff, target):
					Modifiers.add(m)
			"cash":
				var amount := _cash_amount(eff, target)
				if amount < 0.0:
					_pay_with_loan_fallback(-amount)
				else:
					MatchState.add_money(amount)
			"construction_delta":
				Construction.adjust_remaining(str(target.get("instance_id", "")), int(eff.get("turns", 0)))
			"grant_unlock":
				var title := _pick_free_tech(target)
				if title != "":
					MatchState.grant_unlock(title)
			"agenda_tag":
				MatchState.flag_agenda_event(str(eff.get("tag", "")))
			"schedule_event":
				var event: Dictionary = (eff.get("event", {}) as Dictionary).duplicate(true)
				_substitute_target(event, target)
				EventScheduler.schedule_in(int(eff.get("in_turns", 1)), event)
			"set_flag":
				flags["%s:%s" % [str(eff.get("key", "")), str(target.get("instance_id", target.get("tile_id", "")))]] = true
			"sell_land":
				var patches := MatchState.sellable_land_patches(str(target.get("tile_id", "")))
				MatchState.sell_tile_land(str(target.get("tile_id", "")), patches,
					MatchState.LAND_PATCH_COST * float(eff.get("price_mult", 1.0)))
			"seat_founder":
				MatchState.seat_founder(str(eff.get("seat", "coo")))
			"founder_loan":
				# A one-off cheap loan on signing: the CFO's gift. Standard life, half rate.
				LoanState.take_founder_loan(float(eff.get("amount", 0.0)), float(eff.get("rate", 0.05)))
			"freight_credit":
				MatchState.add_freight_credit(int(eff.get("units", 0)))
			"distressed_program":
				SolvencyState.accept_distressed_program()
			"none":
				pass   # describe-only choice (e.g. "tough it out")

# Replace "@target" placeholder values anywhere in a (deep-duplicated) payload with
# the drawn target's ids: tile_id keys get the tile, instance_id keys the instance.
func _substitute_target(payload: Dictionary, target: Dictionary) -> void:
	for key in payload.keys():
		var value: Variant = payload[key]
		if value is Dictionary:
			_substitute_target(value, target)
		elif value is Array:
			for entry in value:
				if entry is Dictionary:
					_substitute_target(entry, target)
		elif value is String and str(value) == "@target":
			payload[key] = str(target.get(str(key), target.get("tile_id", "")))

## How much a decision cash cost must borrow. Only the COST is financed — a
## pre-existing overdraft is never refinanced (that once reset any negative
## balance to £0 through a bigger distress loan, a free bailout):
##   money >= cost          -> 0 (affordable)
##   0 <= money < cost      -> the top-up (cost - money)
##   money < 0              -> the full cost (deficit stays exactly where it was)
func loan_needed_for(cost: float) -> float:
	if cost <= 0.0:
		return 0.0
	return cost - clampf(float(MatchState.money), 0.0, cost)

## Owner ruling (spec §12.1): an unaffordable cash choice stays selectable — the
## shortfall is borrowed automatically at standard terms, bypassing the
## profit-gated capacity (a distress loan), then the cost is paid.
func _pay_with_loan_fallback(cost: float) -> void:
	var borrow := loan_needed_for(cost)
	if borrow > 0.0:
		LoanState.take_distress_loan(borrow)
	MatchState.add_money(-cost)

func _cash_amount(eff: Dictionary, target: Dictionary) -> float:
	if str(eff.get("formula", "")) == "pct_of_building_revenue":
		var report: Dictionary = Production.turn_report_for(str(target.get("instance_id", "")))
		var revenue := 0.0
		for gid in (report.get("outputs_produced", {}) as Dictionary):
			revenue += float(int(report.outputs_produced[gid])) * MarketState.get_price(str(gid))
		return revenue * float(eff.get("pct", 0.0)) / 100.0
	return float(eff.get("amount", 0.0))

# Scope -> concrete Modifiers.add() payloads. Building scope targets the single
# instance (production ctx carries instance_id); tile scope expands to one
# modifier per player building on the tile; building_type matches by building_id;
# company applies domain-wide. market_price targets the good id directly.
func _build_modifiers(eff: Dictionary, target: Dictionary) -> Array:
	var base := {
		"domain": str(eff.get("domain", "")),
		"pct": float(eff.get("pct", 0.0)),
		"label": str(eff.get("label", "Decision")),
		"source": "decision",
	}
	if eff.has("duration_turns"):
		base["duration_turns"] = int(eff.duration_turns)
	var scope := str(target.get("scope", "company"))
	var out: Array = []
	match scope:
		"building":
			var m: Dictionary = base.duplicate(true)
			m["target_match"] = {"instance_id": str(target.get("instance_id", ""))}
			out.append(m)
		"building_type":
			var m2: Dictionary = base.duplicate(true)
			m2["target_match"] = {"building_id": str(target.get("building_id", ""))}
			out.append(m2)
		"tile":
			for b in MatchState.buildings.values():
				if MatchState.is_player_owned(b) and str(b.get("tile_id", "")) == str(target.get("tile_id", "")):
					var m3: Dictionary = base.duplicate(true)
					m3["target_match"] = {"instance_id": str(b.get("instance_id", ""))}
					out.append(m3)
		"company":
			var m4: Dictionary = base.duplicate(true)
			if str(eff.get("domain", "")) == "market_price" and target.has("good_id"):
				m4["target"] = str(target.good_id)
			out.append(m4)
	return out

## Owner ruling (spec §13.3): the cheapest still-locked tech matching the building,
## else the cheapest matching its recipe family. Techs carry no price, so "cheapest"
## resolves to the deterministic first title (alphabetical) within each preference
## band: building_id match beats recipe_type match beats good match.
func _pick_free_tech(target: Dictionary) -> String:
	var b: Dictionary = MatchState.get_building(str(target.get("instance_id", "")))
	var bid := str(b.get("building_id", ""))
	var recipe: Dictionary = Catalog.get_recipe(str(b.get("recipe_id", "")))
	var rtype := str(recipe.get("recipe_type", "")).to_lower()
	var goods: Dictionary = {}
	for output in recipe.get("outputs", []):
		goods[str((output as Dictionary).get("internal_name", ""))] = true
	var bands: Array = [[], [], []]   # [building matches, recipe-family, good]
	var titles: Array = Modifiers.UNLOCK_MODIFIERS.keys()
	titles.sort()
	for title: String in titles:
		if MatchState.unlocked_titles.has(title):
			continue
		var spec: Variant = Modifiers.UNLOCK_MODIFIERS[title]
		var specs: Array = spec if spec is Array else [spec]
		for s: Dictionary in specs:
			var tm: Dictionary = s.get("target_match", {})
			if str(tm.get("building_id", "")) == bid and bid != "":
				bands[0].append(title)
			elif str(tm.get("recipe_type", "")) == rtype and rtype != "":
				bands[1].append(title)
			elif goods.has(str(tm.get("good_internal", "|"))):
				bands[2].append(title)
	for band: Array in bands:
		if not band.is_empty():
			return str(band[0])
	return ""


# ---------------------------------------------------------------------------
# Consequence text — one generator shared by the dialog, the bell entry and the
# (future) politics-panel history, so displayed text can't drift from payloads.
# ---------------------------------------------------------------------------

const _DOMAIN_LABELS := {
	"recipe_output": "output",
	"labour_headcount": "labour cost",
	"maintenance": "maintenance",
	"market_price": "sale price",
}

func _describe_effects(effects: Array, target: Dictionary) -> String:
	if effects.is_empty():
		return "No effect."
	var parts: Array = []
	for eff: Dictionary in effects:
		if eff.has("describe"):
			parts.append(str(eff.describe))
			continue
		match str(eff.get("kind", "")):
			"modifier":
				var pct := float(eff.get("pct", 0.0))
				var text := "%+.0f%% %s on %s" % [pct,
					str(_DOMAIN_LABELS.get(str(eff.get("domain", "")), str(eff.get("domain", "")))),
					str(target.get("name", "the company"))]
				if eff.has("duration_turns"):
					text += " for %d turns" % int(eff.duration_turns)
				parts.append(text)
			"cash":
				if str(eff.get("formula", "")) == "pct_of_building_revenue":
					parts.append("+£%.0f now (%.0f%% of last turn's revenue)"
						% [_cash_amount(eff, target), float(eff.get("pct", 0.0))])
				else:
					var amount := float(eff.get("amount", 0.0))
					parts.append(("+£%.0f now" if amount >= 0.0 else "−£%.0f now") % absf(amount))
			"construction_delta":
				parts.append("construction delayed %d turns" % int(eff.get("turns", 0)))
			"grant_unlock":
				var title := _pick_free_tech(target)
				parts.append("free research unlock: %s" % (title if title != "" else "none available"))
			"agenda_tag":
				pass   # advisor sentiment ripples are shown via loyalty, not here
			"schedule_event":
				parts.append("consequences follow in %d turns" % int(eff.get("in_turns", 0)))
			"set_flag":
				parts.append("%s becomes exempt from environmental events" % str(target.get("name", "it")))
			"sell_land":
				var patches := MatchState.sellable_land_patches(str(target.get("tile_id", "")))
				parts.append("+£%.0f now (sell %d land patches at %.0fx)"
					% [float(patches) * MatchState.LAND_PATCH_COST * float(eff.get("price_mult", 1.0)),
						patches, float(eff.get("price_mult", 1.0))])
	if parts.is_empty():
		return "No direct effect."
	var joined := ". ".join(PackedStringArray(parts))
	return joined.substr(0, 1).to_upper() + joined.substr(1) + "."


# ---------------------------------------------------------------------------
# Presentation: owned by the Turn Briefing (turn_briefing.gd), which listens to
# decision_drawn / pending_changed and auto-expands on critical turns. The old
# standalone modal (decision_dialog.gd) is retired as a surface but kept on disk
# for its view-robustness tests.
# ---------------------------------------------------------------------------


# ---------------------------------------------------------------------------
# Save / load (orchestrated by SaveLoad). Additive snapshot key — old saves
# without it load as fresh state (tolerant-reader doctrine, no version bump).
# ---------------------------------------------------------------------------

func export_state() -> Dictionary:
	return {
		"rng_seed": _rng_seed,
		"rng_state": _rng.state,
		"pending_queue": pending_queue.duplicate(true),
		"cooldown_until": _cooldown_until.duplicate(true),
		"fired_once": _fired_once.duplicate(true),
		"recent_draws": _recent_draws.duplicate(true),
		"reservations": _reservations.duplicate(true),
		"next_pulse_turn": _next_pulse_turn,
		"scheduled_pull": _scheduled_pull.duplicate(true),
		"history": _history.duplicate(true),
		"flags": flags.duplicate(true),
		"next_uid": _next_uid,
	}

func import_state(d: Dictionary) -> void:
	_rng_seed = int(d.get("rng_seed", int(MatchState.match_rng_seed) ^ 0xDEC1DE5))
	_rng.seed = _rng_seed
	_rng.state = int(d.get("rng_state", _rng.state))
	pending_queue = (d.get("pending_queue", []) as Array).duplicate(true)
	# Legacy saves carried a single "pending" dict — wrap it into the queue.
	var legacy_pending: Dictionary = d.get("pending", {})
	if pending_queue.is_empty() and not legacy_pending.is_empty():
		pending_queue = [legacy_pending.duplicate(true)]
	_cooldown_until = (d.get("cooldown_until", {}) as Dictionary).duplicate(true)
	_fired_once = (d.get("fired_once", {}) as Dictionary).duplicate(true)
	_recent_draws = (d.get("recent_draws", []) as Array).duplicate(true)
	# JSON round-trips integer dict keys as strings — restore reservation turns.
	_reservations = {}
	for k in (d.get("reservations", {}) as Dictionary):
		_reservations[int(k)] = str(d["reservations"][k])
	# Back-compat: pre-pulse saves carried "next_draw_turn"; fall back to it.
	_next_pulse_turn = int(d.get("next_pulse_turn", d.get("next_draw_turn", FIRST_DECISION_TURN)))
	_scheduled_pull = (d.get("scheduled_pull", {}) as Dictionary).duplicate(true)
	_history = (d.get("history", []) as Array).duplicate(true)
	flags = (d.get("flags", {}) as Dictionary).duplicate(true)
	_next_uid = int(d.get("next_uid", 1))
	pending_changed.emit()
