extends RefCounted
## The authored decarbonisation-squeeze timeline — const DATA only, no logic.
## One row per policy phase. PolicyState derives the live levels from this table and
## seeds the forewarn + enactment announcements into EventScheduler once per match.
## (docs/co2-tax-and-green-subsidy-announcements-spec.md)
##
## All `body`/`forewarn_body` strings are PLACEHOLDER Lorem Ipsum — the owner will
## replace them with lore. Search for LOREM.
## Turns and levels are balance-volatile (rule #7): tune on the e2e harness.

const SCHEDULE: Array = [
	# --- Green Energy Subsidy (the carrot, early) ---
	{
		"id": "green_subsidy_p1", "policy": "green_subsidy", "level": 1,
		"effective_turn": 20, "forewarn_turns": 5, "severity": "warning",
		"title": "Green Energy Subsidy",
		# LOREM — replace with lore (shown in the forewarning news item).
		"forewarn_body": "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Praesentium subsidium energiae viridis in paucis conversionibus incipiet — qui sol et ventus colunt, remunerabuntur.",
		# LOREM — replace with lore (shown when the subsidy goes live).
		"body": "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore. Vis viridis nunc per megawatt remuneratur; industria carbonis moneatur.",
	},

	# --- CO2 Tax / Carbon Levy (the stick, escalating) ---
	{
		"id": "co2_tax_p1", "policy": "co2_tax", "level": 1,
		"effective_turn": 55, "forewarn_turns": 8, "severity": "warning",
		"title": "Carbon Levy — Phase 1",
		# LOREM
		"forewarn_body": "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vectigal carbonis mox imponetur in carbonem, oleum confectum et aethylenum — parate rationes vestras.",
		# LOREM
		"body": "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor. Vectigal carbonis nunc valet: quisquis carbonem urit, solvit.",
	},
	{
		"id": "co2_tax_p2", "policy": "co2_tax", "level": 2,
		"effective_turn": 120, "forewarn_turns": 8, "severity": "warning",
		"title": "Carbon Levy — Phase 2",
		# LOREM
		"forewarn_body": "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vectigal carbonis mox duplicabitur; tempus est vias mundiores quaerere.",
		# LOREM
		"body": "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vectigal carbonis auctum est — pretium fumi crescit.",
	},
	{
		"id": "co2_tax_p3", "policy": "co2_tax", "level": 3,
		"effective_turn": 200, "forewarn_turns": 8, "severity": "warning",
		"title": "Carbon Levy — Phase 3",
		# LOREM
		"forewarn_body": "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Ultimum incrementum vectigalis appropinquat; aetas carbonis finitur.",
		# LOREM
		"body": "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vectigal carbonis maximum est — qui adhuc urit, contra ventum urit.",
	},
]
