# Hub crossover diagnosis — 19 September 2026

The three-chain L2 rail case is limited by a small replaceable local freight bill and rounded minimum operating inputs, not rail throughput. It replaces £16.44/turn of already cheap rail haulage. It does not replace external haulage, port fees, warehouse charges or the three owned rail tiles' upkeep.

Delivered input costs are £7.4725 per hydraulic component, £6.856802 per tyre and £3.6332755 per fuel. The 32-LC recipe rounds to one hydraulic, one tyre and two fuel, costing £21.595853. Before rounding it would cost £16.427996, almost exactly the replaceable freight bill. The current whole-unit rule adds about £5.17 at this utilization. This does not imply changing that user-selected rounding rule; the resulting minimum efficient scale was intentional.

Increasing installed vehicle capacity from 10 to 20 LC cuts four vehicles to two, reducing fleet capital from £1,237.79 to £618.89. It does not change the running recipe, which scales on actual used LC rather than fleet size. Increasing operating recipe capacity from 125 to 150 LC instead reduces consumption to one of each input, costing £17.96, still £1.52 above the bill replaced. Further capacity increases cannot lower the active recipe below that floor.

## More-volume sensitivity on the same routes

| Complete chains | LC | Fleet at 10 LC/vehicle | Running cost | Freight replaced | Hub advantage |
| --- | ---: | ---: | ---: | ---: | ---: |
| 3 | 32 | 4 | £21.60 | £16.44 | £-5.16 |
| 6 | 58 | 6 | £32.09 | £32.88 | £+0.79 |
| 9 | 86 | 9 | £42.58 | £49.32 | £+6.74 |
| 12 | 111 | 12 | £60.54 | £65.76 | £+5.22 |

These are marginal operating sensitivities, not additional production benchmarks. The same stream quantities are multiplied and re-consolidated at each covered directed edge using the 100-weighted-unit payload. No extra buildings were placed or production/storage feasibility checked. Peak flow would rise from 647 to 1,294 at six chains, above L2 rail's 1,200 threshold. Additional congestion is not priced in these rows; the current modelling convention charges it equally to both direct models, so it cancels in the displayed hub-versus-carrier difference. Hub overhead and capital recovery are excluded. Recipe rounding makes the savings non-monotonic.

More volume can produce a crossover, but six chains only yield about £0.79/turn before capital and hub overhead. Cheap rail alone is a poor operating-saving target for this hub recipe. Do not reduce global hydraulic/tyre goods prices solely to repair this interaction. If the design requires the hub to win at three chains, its replaceable service bill must grow or its effective running cost must fall below £16.44. Vehicle LC alone cannot do that; operating-recipe LC alone also cannot cross the whole-unit active floor. Increasing coverage or extending actual services would require a fresh workload/cost comparison, not free assumed savings.

[Calculation inputs and sensitivities](../../reports/balance/pepper_hub_crossover_diagnosis_2026-09-19.json).
