# Middleman £40 fee and progression review — 19 September 2026

The middleman replaces introductory port relief in the new logistics ruleset. `EconomyConfig.seaport_ad_valorem_rate` now returns the normal 3% base from turn one when the saved ruleset has `logistics_model: middleman_v1`. Existing port growth, ownership and research modifiers still apply. Legacy games and tutorials keep their previous schedule until migrated. This is implemented port policy; middleman service remains a benchmark reference pending phase 1.

## Tariff contract

One visible £40 logistics total has three breakdown items: £16 input procurement, £16 output sale and £8 warehousing. Inputs and sales are charged once per complete basket/batch, not per good. Storage is charged once per factory turn using provider storage, including its operating buffer; no duplicate legacy storage charge. A missing purchase or sale direction has no corresponding direction fee. Output modifiers do not multiply this fixed fee.

Reserve input goods (£238.6944) plus input and storage fees (£24), or **£262.6944**, before production. Deduct the £16 sale fee from receipts. This is a funding requirement for the proposed provider contract, not a simulated minimum starting cash result.

## Measured operating contribution

All figures are per turn before tax, finance and capital investment. Road/rail use real game turns; middleman replaces direct logistics with £40 in reference arithmetic. Prices are controlled; labour and port growth remain active. Roads have no maintenance. Rail owns three sections (£9 per turn); four government sections are assumed already complete.

| Stage | Middleman reference | Roads | Rail, three owned |
| --- | ---: | ---: | ---: |
| 33 motors, turns 10–19 | £16.83 | £-1.68 | £17.39 |
| 33 motors, turns 40–49 | £15.22 | £-3.86 | £15.22 |
| 36 motors, output modifier only | £48.36 | £26.14 | £46.75 |
| 36 motors, output modifier + logistics rewards | £48.36 | £32.14 | £49.79 |

The output stage adds a +10% modifier through the game modifier system, rounding 33 to 36 motors. The research stage also applies the actual Depot Scheduling reward (−10% road/rail transport cost) and Groupage reward (−10% port ad valorem). Research acquisition cost and timing are not simulated. These are controlled reward comparisons, not a claim that both unlocks are available at game start.

## Base logistics breakdown, turns 40–49

| Cost per turn | Roads | Rail, three owned | Middleman |
| --- | ---: | ---: | --- |
| Warehousing | £2.19 | £2.19 | Included |
| Weight/distance freight | £15.60 | £3.90 | Included |
| Inland freight ad valorem | £21.85 | £5.46 | Included |
| Infrastructure maintenance | £0.00 | £9.00 | Included |
| Port import ad valorem | £7.45 | £7.46 | Included |
| Port export ad valorem | £11.99 | £11.99 | Included |
| Port flat fee | £0.00 | £0.00 | Included |
| Congestion | £0.00 | £0.00 | Included |
| Other transport fees | £0.00 | £0.00 | Included |
| Total logistics | £59.08 | £40.01 | £40.00 |

There is no additional warehouse-building maintenance or owned vehicle/fuel/crew bill in these existing systems. Infrastructure labour is zero. Seven player-owned rail sections instead cost £21 maintenance and leave £3.22 operating contribution in the base comparison. Quantities, inputs, prices and construction costs were not changed for this fee/port update; the previous targeted output/price trial remains applied.

## Progression assessment

Removing introductory port relief eliminates a large artificial advantage for early direct transport. However, the complete requested progression target is **not yet met**:

- Roads lose money at base output and are less profitable than outsourcing in all tested stages.
- Three-section rail is £0.566 ahead of outsourcing in turns 10–19, then £0.0086 behind in turns 40–49. This is effectively a tie, not a robust initial outsourcing advantage. Capital and government construction timing still favour starting with outsourcing, but they do not satisfy the stricter operating-profit target.
- Output growth alone improves factory profitability but makes direct logistics more expensive relative to a fixed £40 fee. It does not itself create an integration crossover.
- The two existing logistics rewards produce a rail advantage of £1.432 per turn at 36 motors. At £210 for the three seeded rail sections, simple infrastructure-only payback is about 147 turns, before land, working capital or research costs. This is evidence of a crossover, not yet a compelling investment return.

Keep £40 and the current production trial while implementing the provider and owned-logistics progression. The next balance gate needs a clear initial margin for outsourcing and a meaningful later advantage through actual infrastructure/research savings, with acquisition costs and an evolving-market survival run included. Avoid changing recipe quantities again merely to correct the remaining logistics gap.

## Reproduction and validation

The current contract is [scenario version 4](../../tests/scenarios/pepper_valley_motors_middleman_ports.json); current snapshots are v5. V4 snapshots preserve the £40 experiment with the old introductory port rate and are superseded for this decision. V1–v3 retain earlier congestion/output/tariff controls.

From the Godot project directory:

```sh
python3 tools/run_pepper_valley_benchmark.py --check-baseline
python3 tools/run_pepper_valley_benchmark.py --route rail-three-owned --check-baseline
python3 tools/run_pepper_valley_benchmark.py --route rail-three-owned --stage early --check-baseline
python3 tools/run_pepper_valley_benchmark.py --route rail-three-owned --stage output --check-baseline
python3 tools/run_pepper_valley_benchmark.py --route rail-three-owned --stage research --check-baseline
```

Nine real simulation cases passed: roads and three-owned rail across all four stages, plus all-owned rail at base. Full unit suite: **4,120 checks passed, zero failed**, including turn-one port billing/quotes, legacy policy and ruleset persistence. The runner validates fee components, funded basket, full regular shipments, cash reconciliation and zero congestion. These checks do not substitute for future actual-provider tests.

[Machine-readable component results](../../reports/balance/middleman_fee40_progression_2026-09-19.json). [Benchmark specification](../pepper-valley-motors-benchmark.md). [Implementation phases](../transport-middleman-phasing-plan.md).
