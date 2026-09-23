# Alternative: 125 LC on roads, 300 LC on rail

> Latest objective: L2 handoff should earn more than L1. The [four-way and combined trial](pepper-hub-factorial-2026-09-19.md) shows that flat 300-LC rail efficiency favours L1; level-specific L1 125 / L2 300 reverses the delta if input use accumulates across turns.

Keep the original operating recipe (2 hydraulic components, 4 tyres, 6 fuel), supplying 125 road LC or 300 rail LC. Rail then uses 41.67% of road inputs per used LC, a 58.33% reduction. This is an alternative sensitivity, not stacked with the differentiated-input candidate or adopted gameplay.

Apply mode efficiency to the actual owned movement. The current compact-district model explicitly has owned local road delivery and generic external rail service. It therefore still qualifies for 125 LC, even with a rail carrier. A hub-owned rail variant needs its local routes, travel timing and appropriate fleet/infrastructure assumptions modelled before claiming the rail saving.

For mixed operation, scale each recipe input by `used_road_LC / 125 + used_rail_LC / 300`, then apply inventory accounting once per hub. This does not change installed vehicle capacity (10 LC/vehicle).

| Hypothetical all-owned-rail workload, unchanged LC and carrier quote | Average running cost at 300 LC | Advantage over corresponding generic carrier |
| --- | ---: | ---: |
| L1-handoff fixture, 26 LC | £5.56 | +£14.84 |
| L2-handoff fixture, 15 LC | £3.21 | +£5.38 |

These are isolated consumption sensitivities with accumulated usage across turns, not re-routed owned-rail simulation results. Other costs and fleet assumptions are held fixed purely for comparison. Under the current per-turn minimum, both still consume one hydraulic component, one tyre and one fuel, costing £17.96; increasing recipe capacity alone does not change running expense at these volumes.

The modal distinction could support a useful specialization, but it does not solve the active consumption floor or prove the desired 9+-building crossover. Keep the two proposed levers separate during calibration: differentiated input rates versus mode-specific recipe capacity. Neither has been silently applied to gameplay.

[Machine-readable sensitivity](../../reports/balance/pepper_hub_modal_efficiency_2026-09-19.json).
