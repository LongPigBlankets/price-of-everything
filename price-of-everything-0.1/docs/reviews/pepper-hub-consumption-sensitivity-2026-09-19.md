# Hub operating consumption and rail-level sensitivity — 19 September 2026

> Follow-up candidate: [fuel-relative differentiated input rates](pepper-hub-differentiated-inputs-2026-09-19.md), with fuel unchanged and tyres/hydraulics/batteries progressively less frequent. Savings require the explicitly proposed accumulated-use accounting.

The existing recipe is **2 hydraulic components + 4 tyres + 6 fuel per 125 used LC**. Each good is scaled by actual used LC and rounded half-up, with a minimum of one for any positive use every active turn. Idle use is zero. Installed vehicles provide 10 LC each; changing installed capacity does not reduce used-LC operating consumption.

Delivered unit costs at the central hub are £7.4725 hydraulics, £6.856802 tyres and £3.6332755 fuel. Both selected compact-district cases round to one of each per active turn: £17.9625775. No default recipe or rounding rule was changed by this sensitivity.

## Current rules: L1 versus L2 rail

| Item | Rail L1 | Rail L2 |
| --- | ---: | ---: |
| Generic-carrier profit | £169.86 | £174.47 |
| Hub profit | £172.29 | £165.09 |
| Hub advantage | +£2.44 | −£9.38 |
| Best shared handoff | tile_5_6 | tile_5_5 |
| Hub LC | 26 | 15 |
| Vehicles | 3 | 2 |
| Vehicle investment | £928.34 | £618.89 |
| Generic carrier freight | £32.22 | £20.40 |
| Hub's remaining external freight | £11.82 | £11.82 |
| Maximum hub operating bill to break even | £20.40 | £8.58 |
| Three owned rail tiles' upkeep | £9.00 | £16.20 |

The L1 handoff on the port-facing edge of coverage is within one rail leg of the port; direct factory routes are longer. The hub incurs more local distribution LC, but still consumes only one of each operating good. All seven L1 handoffs were actually quoted and compared; none has congestion in this fixture. At the central handoff instead, L1 external freight is £23.63 and the hub still trails its generic carrier by £9.38. Handoff position is therefore decisive for L1.

The current L1 hub already crosses its L1 carrier, but its vehicle-only payback is about 381 turns, excluding hub construction and overhead. It also still earns £2.18 less per turn than the generic L2 rail option. This is not yet a strong end-to-end integration incentive.

## How much reduction does L2 need?

Its hub operating bill must fall from £17.96 to **below £8.58**, a reduction greater than **52.21% in actual expense**, merely to beat its carrier before hub overhead. Cutting the recipe coefficients by 20%, 50% or even 75% does not achieve this with the existing per-turn minimum: all tested recipes still consume one of each good.

## Alternative: accumulate wear/usage across turns

This is a proposed change to the earlier minimum-one-every-turn rule, not a hidden reinterpretation. Track fractional accumulated wear or remaining service capacity; consume whole inventory units when the cumulative requirement calls for them. An active turn would no longer necessarily consume one whole tyre and one whole hydraulic component. Initial reserve purchases, exact draw timing and the behaviour when supplies run out would need implementation and testing. The figures below are long-run averages, not constant per-turn cash bills.

| Operating rule | L2 average running cost | L2 advantage | L1 average running cost | L1 advantage |
| --- | ---: | ---: | ---: | ---: |
| Existing per-turn rounding/minimum | £17.96 | −£9.38 | £17.96 | +£2.44 |
| Accumulated usage, current recipe | £7.70 | £+0.88 | £13.35 | £+7.05 |
| Accumulated usage, 20% lower recipe | £6.16 | £+2.42 | £10.68 | £+9.72 |
| Accumulated usage, 50% lower recipe | £3.85 | £+4.73 | £6.67 | £+13.73 |
| Accumulated usage, 75% lower recipe | £1.93 | £+6.66 | £3.34 | £+17.06 |

At L2's 15 LC, the original recipe averages 0.24 hydraulic components, 0.48 tyres and 0.72 fuel per turn, costing £7.70. Thus the original underlying rate is already slightly below the £8.58 crossover; the per-turn minimum creates the loss. With a 20% rate reduction, average usage is 0.192 hydraulics, 0.384 tyres and 0.576 fuel, costing £6.16. These averages still require whole goods purchases over time.

Recommended next trial: test accumulated usage at the existing recipe first, then a 20% lower-rate candidate if the operating margin is too small. Do not reduce global hydraulic or tyre prices. The resulting small positive L2 margins do not yet establish good investment returns, and the 1–3 and five-building controls must be rerun under any new consumption rule to preserve the intended scale progression. This report does not adopt either candidate as the default.

## Reproduction and evidence

```sh
python3 tools/analyse_hub_consumption_sensitivity.py
```

The tool recreates the four-tile specification from its retained report, runs the actual L1 engine route/price probe, compares all handoffs, checks absence of congestion and generates recipe sensitivities. L2 uses the retained validated quote model. Factory quantities/prices, warehouse estimate, port rates and ownership assumptions are held fixed; no production simulation or gateway inventory calibration is claimed. Infrastructure construction, hub overhead, empty repositioning and fleet amortization remain excluded.

[Full sensitivity report and L1 quotes](../../reports/balance/pepper_hub_consumption_sensitivity_2026-09-19.json).
