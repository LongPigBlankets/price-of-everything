# Dynamic middleman fee experiment — 19 September 2026

> Current preferred experiment: **0.4% market value + weight rate × location**, using **solid-heavy £0.05 and ultra-heavy £0.50 per unit**. Earlier rates below are retained as sensitivity history. See the final section for this candidate’s results.

The proposed tariff can support profitable outsourced expansion and an incentive to integrate, but the weight rates must distinguish low-margin bulk materials from ultra-heavy products. Reusing existing transport rates makes outsourcing too cheap; uniformly scaling those rates cannot satisfy both tested objectives at Pepper Valley.

This is a reproducible arithmetic tariff experiment using recorded game operating costs and live catalogue prices. It changes no live tariffs, recipes, geography, or provider gameplay. Middleman buildings remain independent: the furnace sells 44 steel; motors purchase 32 steel separately. Direct logistics shares 32 steel and exports 12. Road/rail results are from actual prior game runs.

## Formula and assumptions

`fee = sum(units × (0.005 × market base price + weight rate × location coefficient))`

Apply to both input purchases and output sales at each building. Use the current catalogue base price for fee valuation; goods transactions still retain their normal purchase/sale spread. Density multiplies only the weight term. This is inclusive of storage: no £8 storage charge, old £40 factory fee, or £12 furnace charge is added. Power remains in factory operating costs, outside the goods-logistics tariff. The formula has no fixed per-building penalty and scales with real throughput.

| Location | Coefficient |
| --- | ---: |
| Large city near a port | 1.05 |
| Medium city, at least four urban tiles | 1.25 |
| Small city, one to three urban tiles | 1.50 |
| Rural/hill adjacent to a city | 1.75 |
| Other rural/hill | 2.00 |
| Mountain, including beside a city | 2.50 |

Pepper Valley has two named urban tiles, so 1.5 applies. Port Lightning has four named urban tiles, so 1.25 applies. City membership must come from authored city regions, not only connected urban components: named neighbourhoods can be separated in the hex topology. The exact definition of “large” and “near a port” is not yet specified; the experiment accepts an explicit large-port-city classification rather than inventing a threshold. Unsupported terrain is not silently assigned a rate. Mountains take precedence over proximity.

The supplied formula did not specify weight values. Two explicit interpretations are tested below. Values are currency per unit before the location coefficient, not claims about physical mass.

## Literal existing rates

Current weight rates are £0.03 for solid-heavy goods (steel, iron, coal, wiring) and £0.06 for ultra-heavy goods (motors). At Pepper Valley these produce:

- Motor fee £8.81; motor operating contribution £46.42.
- Furnace fee £5.36; adding the furnace improves contribution by £7.94.
- Combined contribution £54.35, compared with direct roads £6.67 and rail £29.35.

This meets the expansion objective but leaves a large subsidy for staying outsourced. The existing tested output/research progression does not recover that gap.

A universal weight-rate scale also fails this particular chain comparison. Keeping the furnace’s incremental contribution nonnegative requires a scale no greater than **2.747×**. Making the integrated rail chain outperform the outsourced chain requires more than **3.406×**. There is no overlapping range under the fixed 0.5% price term.

## Trial with differentiated weight rates

Try **solid-heavy £0.045/unit** and **ultra-heavy £0.58/unit**, before location. Other classes retain their existing rates for this experiment and have not been balanced. This makes ultra-heavy handling 12.89 times the solid-heavy rate (existing ratio: 2). That is a substantial design choice, not a small universal tariff adjustment. Validate vehicles, construction goods, light goods and fluids before adopting the table globally.

| Per turn at Pepper Valley | Motors | Furnace addition | Combined |
| --- | ---: | ---: | ---: |
| Input service fee | £5.46 | £4.14 | £9.60 |
| Output service fee | £30.53 | £3.49 | £34.02 |
| Total inclusive service | £35.99 | £7.63 | £43.62 |
| Contribution before service | £55.22 | £13.30 | £68.52 |
| **Operating contribution** | **£19.24** | **+£5.67** | **£24.90** |

| Company | Dynamic middleman trial | Public roads | Rail, three owned sections |
| --- | ---: | ---: | ---: |
| Motors alone | £19.24 | −£3.86 | £15.22 |
| Motors + furnace | £24.90 | £6.67 | £29.35 |

The motor factory starts £4.02 ahead of rail under outsourcing; expansion with another outsourced building adds £5.67 instead of making the company worse. Integrating both buildings over rail then improves contribution by £4.45 per turn. The three rail sections’ £210 construction value would take about 47 turns to recover that advantage alone, before working capital, land, research, government construction timing or financing. The factory costs exist in both expanded cases and are not included in this incremental rail payback.

For motors alone, +10% output (36 motors after rounding) gives £49.60 under this tariff. Direct rail earns £46.75 without logistics research and £49.79 with the previously tested Depot Scheduling and Groupage rewards. The latter is only a £0.20 advantage; the local steel chain is the stronger integration incentive. Roads still require more substantial improvements.

## Density sensitivity

The following changes only the coefficient while retaining Pepper Valley prices, labour and production. These are not simulated businesses at different sites, and direct route costs cannot be assumed constant when relocating.

| Coefficient | Motor profit | Extra furnace profit | Combined profit |
| --- | ---: | ---: | ---: |
| 1.05 | £29.14 | £7.71 | £36.86 |
| 1.25 | £24.74 | £6.80 | £31.54 |
| 1.50 | £19.24 | £5.67 | £24.90 |
| 1.75 | £13.73 | £4.53 | £18.26 |
| 2.00 | £8.23 | £3.39 | £11.62 |
| 2.50 | £-2.78 | £1.12 | £-1.66 |

The furnace adds positive operating contribution across all six coefficients in this controlled comparison. That does not mean every location is viable: at mountain rates the motor factory and combined company still lose money. Nor does one furnace establish that every possible second building is profitable. Consumer demand, price impact, unlocks and construction payback need separate checks.

## Validation and next implementation gate

Run `python3 tools/analyse_middleman_dynamic_fee.py` from the project root. It reads the actual goods CSV and existing transport rates, consumes retained v5 motor and v7 independent-provider chain results, and writes [machine-readable results](../../reports/balance/middleman_dynamic_fee_2026-09-19.json). Assertions check terrain precedence, the three/four urban boundary, fee/profit objectives at Pepper Valley and positive furnace increments across the coefficient sweep.

No new game simulation was needed: direct costs and physical flows are unchanged, while the provider remains reference arithmetic. Earlier fixed-fee snapshots remain intact. Before implementing live quotes, settle the weight table and authored large-city/port eligibility; then apply one shared quote function to building purchases/sales, retain independent provider buffers, and test actual funding and settlement. This trial supports the formula’s direction, not global economy sign-off.

## Follow-up: 0.4% market value

Recommended next trial: **0.4% market value, solid-heavy £0.045/unit, ultra-heavy £0.58/unit**, with the same location coefficients and inclusive storage. Keep the weights steady first: this isolates the effect of lowering the price component. Both purchase and sale fees use the new percentage; goods prices and their spread are unchanged.

| Tariff at Pepper Valley | Motor fee | Motor profit | Furnace incremental profit | Combined profit | Integrated rail advantage over combined provider |
| --- | ---: | ---: | ---: | ---: | ---: |
| 0.5%, heavy .045, ultra .58 | £35.99 | £19.24 | £5.67 | £24.90 | £4.45 |
| **0.4%, heavy .045, ultra .58** | **£35.40** | **£19.83** | **£5.83** | **£25.66** | **£3.69** |
| 0.4%, heavy .045, ultra .56 | £34.41 | £20.82 | £5.83 | £26.65 | £2.70 |

The percentage change is a modest delay, not a 20% reduction in the whole fee. It reduces the motor fee by £0.59 and the combined fee by £0.75; weight/location remains the dominant component. At the unchanged £210 for three rail sections, simple incremental rail-only payback against the two-building provider case moves from about 47 to 57 turns. Capital, land, working capital and research costs remain excluded from the operating table; this is not a simulated investment date.

For the single motor factory with +10% output and Depot Scheduling/Groupage, 0.4% and the .58 ultra-heavy rate give £50.22 provider contribution versus £49.79 rail. The previous small research crossover disappears. The two-building local steel chain still creates a £3.69 rail advantage, so integration remains worthwhile through actual supply sharing.

If that still encourages integration too soon, reduce ultra-heavy to .56 as a second experiment: rail-only payback becomes about 78 turns. Do not lower solid-heavy merely to postpone integration: it governs the affordable upstream expansion margin. At .045, the furnace remains a positive addition across all tested coefficients, even 2.5; this does not make the mountain motor business profitable overall.

These remain middleman-specific trial rates, not changes to road/rail rates or claims about physical mass. The large difference between the weight classes still needs validation on goods other than steel and motors.

Reproduce the two new arithmetic runs:

```sh
python3 tools/analyse_middleman_dynamic_fee.py --ad-valorem .004
python3 tools/analyse_middleman_dynamic_fee.py --ad-valorem .004 --ultra-heavy .56
```

Both pass the existing density/expansion/integration assertions. Reports are separately versioned by parameter suffix, preserving the 0.5% report. No game tariff or recipe data changed.

## Preferred candidate: solid-heavy £0.05, ultra-heavy £0.50

The user-selected next candidate keeps 0.4% market value and all location coefficients. Rates apply to each traded input/output unit; storage is included and buildings remain independent under the middleman. The [candidate contract](../../tests/scenarios/middleman_dynamic_fee_candidate.json) records these choices without changing live gameplay. Other weight classes and large-port-city eligibility still need selection.

| Pepper Valley, per turn | Middleman | Public roads | Rail, three owned sections |
| --- | ---: | ---: | ---: |
| Motor factory only | £23.31 | −£3.86 | £15.22 |
| Motors plus furnace | £28.38 | £6.67 | £29.35 |

Motor service costs £31.92 (£5.71 inputs, £26.21 outputs). Furnace service adds £8.23 (£4.51 inputs, £3.72 outputs). The combined service fee is £40.14; adding the outsourced furnace increases profit by £5.07.

This makes outsourcing a viable continuing strategy. Rail still wins with the local steel chain, but by only £0.97 per turn before capital costs; simple repayment of the three rail sections (£210) takes about 217 turns at that advantage, before other acquisition costs. Consequently this is a niche or a stepping stone to further scale/research, not a compelling immediate investment solely for this two-building chain. The one-factory +10% output/research comparison remains £54.06 middleman versus £49.79 rail, so that specific research bundle alone does not justify switching.

Applying each location coefficient to the same Pepper Valley costs gives:

| Coefficient | Motors | Extra furnace contribution | Combined |
| --- | ---: | ---: | ---: |
| 1.05 | £32.17 | £7.34 | £39.52 |
| 1.25 | £28.23 | £6.33 | £34.57 |
| 1.50 | £23.31 | £5.07 | £28.38 |
| 1.75 | £18.38 | £3.81 | £22.19 |
| 2.00 | £13.46 | £2.55 | £16.00 |
| 2.50 | £3.61 | £0.02 | £3.63 |

These are coefficient sensitivities, not relocated game runs. At the mountain coefficient the added furnace is almost exactly break-even; small price or wage changes can make that expansion worse. The experiment therefore establishes a useful Pepper Valley result, not a universal guarantee that every second building helps.

Validation: `python3 tools/analyse_middleman_dynamic_fee.py --ad-valorem .004 --solid-heavy .05 --ultra-heavy .5` passed the coefficient and economic assertions. [Parameter-specific results](../../reports/balance/middleman_dynamic_fee_2026-09-19_av0.004_heavy0.05_ultra0.5.json). No new physical simulation was required because direct shipments and costs are unchanged; middleman results remain reference arithmetic.
