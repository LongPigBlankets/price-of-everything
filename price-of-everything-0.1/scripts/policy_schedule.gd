extends RefCounted
## The authored decarbonisation-squeeze timeline — const DATA only, no logic.
## One row per policy phase. PolicyState derives the live levels from this table and
## seeds the forewarn + enactment announcements into EventScheduler once per match.
## (docs/co2-tax-and-green-subsidy-announcements-spec.md)
##
## Owner lore is written for phases 1 and 2; the phase-3 pair is drafted copy
## (2026-08-29, owner pass welcome). The two `forewarn_body` strings on the entries
## with `forewarn_turns: 0` are never shown; they are kept in case a rumour beat is added.
## Turns and levels are balance-volatile (rule #7): tune on the e2e harness.

const SCHEDULE: Array = [
	# --- Green Energy Subsidy (a mid-game window: live t105, runs through at least
	# t185, lapses on a seed-picked turn in 186..191 — see PolicyState). Its advance
	# notice is the blocking green_subsidy_notice decision at turn 100, so no passive
	# forewarn news here. ---
	{
		"id": "green_subsidy_p1", "policy": "green_subsidy", "level": 1,
		"effective_turn": 105, "forewarn_turns": 0, "severity": "warning",
		"title": "Green Energy Subsidy",
		# NOT SHOWN while forewarn_turns is 0 — the advance notice is the blocking
		# green_subsidy_notice decision at t100. Kept for if a rumour beat is wanted.
		"forewarn_body": "The government is considering subsidies for green power. Details have not been announced.",
		"body": "Green power now earns a subsidy for each MW generated. Solar, wind, hydro and biomass power qualify.",
	},

	# --- CO2 Tax / Carbon Levy (the stick, escalating) ---
	{
		# Owner ruling: in force at turn 101. The advance notice is NOT a passive
		# forewarn news item — it's the blocking "Understood" story decision
		# (carbon_tax_notice) that PolicyState reserves for turn 90, so forewarn_turns
		# stays 0 here to avoid a duplicate announcement.
		"id": "co2_tax_p1", "policy": "co2_tax", "level": 1,
		"effective_turn": 101, "forewarn_turns": 0, "severity": "warning",
		"title": "Carbon Levy: Phase 1",
		# NOT SHOWN while forewarn_turns is 0 — the advance notice is the blocking
		# carbon_tax_notice decision at t90. Kept for if a rumour beat is wanted.
		"forewarn_body": "The government is considering a carbon levy. Fossil fuel use and affected imports may become more expensive.",
		"body": "The first carbon levy phase is fully in force. Fossil fuel use and affected imports now cost more.",
	},
	{
		"id": "co2_tax_p2", "policy": "co2_tax", "level": 2,
		"effective_turn": 165, "forewarn_turns": 8, "severity": "warning",
		"title": "Carbon Levy: Phase 2",
		# BANS (balance-volatile, rule #7 — MECHANIC CHANGE, owner-approved 2026-08-13):
		# from this phase's effective_turn, recipes whose OUTPUT is in `produce` stop
		# running and cannot be selected, and goods in `import` cannot be bought by any
		# route (MatchState.queue_buy is the single purchase primitive). PolicyState
		# reports the halted-building and cancelled-order counts on the turn it lands.
		# The `ban coal` cheat exercises the identical path at any turn.
		"bans": {"produce": ["coal"], "import": ["coal"]},
		"forewarn_body": "The government plans to increase the carbon levy. Review production that depends on fossil fuels.",
		"body": "The carbon levy has increased to its second phase. Coal use remains permitted.",
	},
	{
		"id": "co2_tax_p3", "policy": "co2_tax", "level": 3,
		"effective_turn": 230, "forewarn_turns": 8, "severity": "warning",
		"title": "Carbon Levy: Phase 3",
		# Drafted copy — owner pass welcome. By this point coal is already banned (P2),
		# so the copy targets what still burns: oil, gas, coke.
		"forewarn_body": "The government plans a final increase in the carbon levy. Production that relies on fossil fuels will cost more.",
		"body": "The carbon levy has reached its final rate. Fossil fuel use and affected imports now face the highest charge.",
	},
]
