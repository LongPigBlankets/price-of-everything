# Differentiated hub input rates — 19 September 2026

> Latest objective: L2 handoff should earn more than L1. The [four-way and combined trial](pepper-hub-factorial-2026-09-19.md) shows that flat 300-LC rail efficiency favours L1; level-specific L1 125 / L2 300 reverses the delta if input use accumulates across turns.

Interpret the proposed 1 / 0.5 / 0.25 / 0.125 progression as a common fuel-relative quantity rate. Fuel remains 6 units per 125 LC; tyres become 3, hydraulics 1.5 and the battery alternative 0.75. This is distinct from multiplying each old recipe input by those fractions independently.

| Input | Relative rate | Units per 125 LC | LC serviced per unit |
| --- | ---: | ---: | ---: |
| Fuel | 1 | 6 | 20.83 |
| Tyres | 0.5 | 3 | 41.67 |
| Hydraulic components | 0.25 | 1.5 | 83.33 |
| Battery / specified specialist input | 0.125 | 0.75 | 166.67 |

Battery replaces fuel in the electric variants, as in earlier scenarios. It is not an extra input imposed on diesel. No unspecified specialist good was added. The diesel recipe changes from 2 hydraulics + 4 tyres + 6 fuel to 1.5 hydraulics + 3 tyres + 6 fuel: the replacement-part quantities fall by 25%, fuel remains unchanged.

## Compact ten-building district sensitivity

All figures below are long-run averages **with accumulated usage across turns**, not the existing per-turn minimum. L1 retains the port-facing handoff tile_5_6 and 26 LC; L2 retains the central handoff and 15 LC. Same prices, routes, fleet, infrastructure, port and stock-cost assumptions as the previous experiment.

| Variant | L1 running cost | Advantage over L1 carrier | L2 running cost | Advantage over L2 carrier |
| --- | ---: | ---: | ---: | ---: |
| diesel | £11.14 | £+9.26 | £6.43 | £+2.15 |
| lithium_electric | £14.95 | £+5.45 | £8.62 | £-0.04 |
| sodium_electric | £10.37 | £+10.03 | £5.98 | £+2.60 |

Diesel has vehicle-only payback of approximately 100 turns for the selected L1 handoff, versus 287 turns for L2. Sodium gives about 93 and 238 turns. These exclude hub construction, overhead and initial service inventory; they do not establish a complete investment return. Lithium's high commodity price makes it approximately break-even against L2 freight, despite its much lower unit usage rate.

## Required consumption accounting

Keeping the old positive minimum-one-per-good every active turn still produces one tyre, one hydraulic component and one fuel/battery in these cases. The diesel bill stays £17.96; lithium becomes £67.79 and sodium £38.41. Therefore changing recipe ratios alone does not realize the savings above.

The effective candidate is whole-unit supplies with accumulated service capacity: one tyre covers 41.67 LC before replacement; one hydraulic component covers 83.33 LC, and so on. Unused service persists between turns; idle hubs use none. Whole goods remain whole inventory transactions. This explicitly replaces the earlier per-turn consumption floor. No such accounting change was implemented or silently adopted here.

The input-frequency hierarchy is now explicit and the diesel/sodium candidates cross both rail carriers at the tested ten-building scale. Smaller-building controls still need rerunning under the proposed accounting before adoption: reducing the active floor can move the early crossover. The candidate does not alter global commodity prices.

```sh
python3 tools/analyse_hub_differentiated_inputs.py
```

[Full report](../../reports/balance/pepper_hub_differentiated_inputs_2026-09-19.json). [Candidate contract](../../tests/scenarios/logistics_hub_lc_weights.json).
