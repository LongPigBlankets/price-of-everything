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
		"forewarn_body": "There are rumours of a new policy that will benefit solar farms and wind farms. Nothing concrete yet, but our people are certain the government will announce something soon. It always helps to diversify into solar and wind if you haven't already, just in case.",
		"body": "Producing green power is not only clear of the carbon tax, but thanks to the green subsidy companies producing solar or wind power can benefit from government funds for each MWh produced. This is a real step towards sustainable energy production in Taralia.",
	},

	# --- CO2 Tax / Carbon Levy (the stick, escalating) ---
	{
		# Owner ruling: in force at turn 101. The advance notice is NOT a passive
		# forewarn news item — it's the blocking "Understood" story decision
		# (carbon_tax_notice) that PolicyState reserves for turn 90, so forewarn_turns
		# stays 0 here to avoid a duplicate announcement.
		"id": "co2_tax_p1", "policy": "co2_tax", "level": 1,
		"effective_turn": 101, "forewarn_turns": 0, "severity": "warning",
		"title": "Carbon Levy — Phase 1",
		# NOT SHOWN while forewarn_turns is 0 — the advance notice is the blocking
		# carbon_tax_notice decision at t90. Kept for if a rumour beat is wanted.
		"forewarn_body": "There are rumours of a new tax coming. It lines up with what we heard from the Party of Markets on the campaign trail, when they advocated for charging a tax on polluters to force them to innovate away from the old ways that threatened to leave the country's industry behind the rest of the world. It could go either way but we probably want to prepare in case our coal and oil production became affected by some sort of tax.",
		"body": "The carbon tax has hit full force. Reports across the country corroborate that our competition is hit hard. Everyone was reliant on cheap coal and oil and now their production costs skyrocketed. Nevermind relief, everyone is fearing chain bankruptcy and a mass recession. The press is reporting record layoffs across multiple industrial giants. Our company needs to tread carefully or we'll end up in the ditch too.",
	},
	{
		"id": "co2_tax_p2", "policy": "co2_tax", "level": 2,
		"effective_turn": 165, "forewarn_turns": 8, "severity": "warning",
		"title": "Carbon Levy — Phase 2",
		# BANS (balance-volatile, rule #7 — MECHANIC CHANGE, owner-approved 2026-08-13):
		# from this phase's effective_turn, recipes whose OUTPUT is in `produce` stop
		# running and cannot be selected, and goods in `import` cannot be bought by any
		# route (MatchState.queue_buy is the single purchase primitive). PolicyState
		# reports the halted-building and cancelled-order counts on the turn it lands.
		# The `ban coal` cheat exercises the identical path at any turn.
		"bans": {"produce": ["coal"], "import": ["coal"]},
		"forewarn_body": "The government is looking to appeal to its environmentally conscious voters by promising to double the carbon tax. Or possibly even ban some forms of polluting production. That would be very extreme, but with this government, you never know. We need to protect our interests but it always helps to have a backup in case we can slingshot ahead of everyone else.",
		"body": "The press called it madness, but the Party of Markets went ahead and doubled the carbon tax. They stopped short of banning coal outright, though the rumours said they would. We probably would have been fine either way, but who knows how many of our competitors would have crumbled away.",
	},
	{
		"id": "co2_tax_p3", "policy": "co2_tax", "level": 3,
		"effective_turn": 230, "forewarn_turns": 8, "severity": "warning",
		"title": "Carbon Levy — Phase 3",
		# Drafted copy — owner pass welcome. By this point coal is already banned (P2),
		# so the copy targets what still burns: oil, gas, coke.
		"forewarn_body": "The ministry is drafting what they call the final phase of the carbon programme. Our people have seen the annex: the levy goes to its ceiling, on everything that still burns — oil, gas, coke, the lot. There is no lobby left in the capital willing to argue against it. Whatever we still run on petroleum has a little time left to justify itself, and after that it had better be paying us for the privilege.",
		"body": "The final phase is in force. The carbon levy stands at its ceiling, and the government has stopped pretending it is a tax at all — it is a closing notice for the age of carbon. The last holdouts are selling plants for scrap and calling it strategy. Whatever still burns in Taralia burns at a price no ledger carries for long. If we spent the years since the first levy building the other way, this is where it pays.",
	},
]
