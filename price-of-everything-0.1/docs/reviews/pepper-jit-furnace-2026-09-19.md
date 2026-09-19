# Pepper Valley: ad valorem, JIT and local steel — 19 September 2026

No live balance changes. These experiments retain the £40 motor-factory provider reference and treat an outsourced furnace as an independent building with a £36 service fee, with the 33-motor recipe, normal 3% port base from turn one, existing price/output trial, public roads and only three player-owned rail sections (£9 maintenance). Samples cover turns 40–49 at controlled prices, with no added output or logistics research bonuses. Operating contribution excludes tax, borrowing and capital investment.

Road and rail cases run actual game code. The middleman remains arithmetic; this does not test provider inventory or settlement implementation. It buys and sells at each building only: no local shipping, shared inventory or JIT. Direct logistics may connect the buildings. JIT is granted explicitly to measure its effect, not earned: two buildings do not meet its seven-producer unlock condition.

## Halving ad valorem

Interpret the proposal primarily as halving **inland freight ad valorem**, leaving weight/distance freight and port tariffs unchanged. The following is exact arithmetic on measured zero-congestion freight components at unchanged throughput; it is not a changed-tariff game run or an evolving-market forecast.

| Motor factory only | Current profit | Half inland ad valorem | Half inland and port ad valorem |
| --- | ---: | ---: | ---: |
| Middleman reference | £15.22 | £15.22 | £15.22 |
| Roads | £-3.86 | £7.07 | £16.79 |
| Rail, three owned | £15.22 | £17.95 | £27.68 |

A universal starting discount would make rail outperform the middleman sooner, against the desired progression. A later unlock or owned-infrastructure benefit is a better fit. Halving inland ad valorem alone still leaves standalone roads behind outsourcing. Halving ports as well is a different, much broader change; do not conflate the two fees.

## Add one ordinary furnace on the same tile

Use unchanged Steelmaking (`r_003`, furnace `b_002`): 37 iron ingots + 20 coal + 140 power → 44 steel. Keep 32 steel for the motor factory and export the remaining 12 using the existing per-good surplus-selling order. External imports become 37 iron ingots, 20 coal and 32 copper wiring; exports are 33 motors and 12 steel. No steel is bought or sold for the internal transfer. Furnace construction is seeded; its upkeep, labour and power are charged normally.

The corrected provider reference charges **£76 total**: motor £40; furnace procurement £12, ordinary sales £16 and warehousing £8 (£36). The £2 local service is removed. The furnace sells all 44 steel; the motor factory independently buys 32 steel at the purchase price. Buildings never share inventory through the middleman, even on the same tile. The previous free-surplus-sales provision belonged to the rejected local-service arrangement; the furnace now sells its entire output under the ordinary sales fee.

| Company profit per turn | Middleman reference | Roads | Rail, three owned |
| --- | ---: | ---: | ---: |
| Motor factory only | £15.22 | −£3.86 | £15.22 |
| Motor factory + furnace | −£7.48 | £6.67 | £29.35 |
| Both buildings + JIT | −£7.48 | £6.67 | £29.35 |
| Both buildings, half inland ad valorem (sensitivity) | −£7.48 | £17.78 | £32.13 |

The direct chain adds £17.09 to contribution before logistics. Direct logistics rise by £6.56 for roads and £2.96 for rail, leaving improvements of £10.52 and £14.13. Independent middleman trades add £13.30 before fees: the extra steel purchase/sale spread costs £3.79 compared with sharing steel. Adding the furnace’s £36 fee therefore reduces company contribution by £22.70. A standalone outsourced furnace is not viable under these rates, even though integrating that furnace improves the direct company. Do not present this as a safe outsourced expansion path.

Current chain v7 captures independent provider trades. Historical v5 (£80 with local sharing) and v6 (£54 local service) are preserved as superseded experiments. The motor-only comparison remains v5. No transport or recipe balance changes were applied.

## Two-building logistics components

| Component per turn | Middleman | Roads | Rail, three owned |
| --- | ---: | ---: | ---: |
| Storage | Included | £3.56 | £3.56 |
| Weight/distance freight | Included | £20.04 | £5.01 |
| Inland freight ad valorem | Included | £22.22 | £5.56 |
| Infrastructure upkeep | Included | £0.00 | £9.00 |
| Port import ad valorem | Included | £6.89 | £6.91 |
| Port export ad valorem | Included | £12.93 | £12.93 |
| Port flat fee | Included | £0.00 | £0.00 |
| Congestion | Included | £0.00 | £0.00 |
| Other transport fees | Included | £0.00 | £0.00 |
| Total logistics | £76.00 | £65.65 | £42.96 |

Direct-chain goods receipts are £392.90, external goods purchases £220.92 and factory operating costs £99.67 (labour £65.77, maintenance £13.50, power £20.40). The middleman reference instead has £468.68 receipts and £300.48 purchases because it trades the 32 internal-use steel in both directions. Factory costs remain £99.67; its £76 fee leaves −£7.48. Its external goods plus £28 procurement and £16 storage require £344.48 before factory costs; £32 sales fees settle from receipts. The £9 rail upkeep is separate. Road/rail transport uses the existing carrier tariffs; these runs do not add owned fleet fuel or vehicle costs.

## What JIT actually does here

The standalone factory has no local supplier. Unlocking Just-in-Time Logistics changes neither stock nor cost: zero units use direct feed.

With the furnace, 32 steel per turn go through the real direct feed, which bypasses stockpile capacity and storage fees. However, `Production.compute_sell_reserve_for_tile` reserves one turn of consumer inputs without subtracting direct feed. The existing surplus-selling order therefore retains **another 32 steel in stock**, even with 32 in direct feed. Both JIT and non-JIT runs pay £3.5647012 storage per turn and have the same steady profit. JIT works as a feed mechanism, but the reserve policy prevents the expected cash saving in this configuration.

Removing that redundant 32-steel reserve would save `32 × (0.020 + 0.004 × 2.3679) = £0.9430912` per turn. This is an isolated storage estimate, not a simulated fix. Any correction must preserve construction reservations and avoid selling input buffers needed when local production is interrupted. It is recorded here, not patched as part of a balance experiment.

## Reproduction and verification

```sh
python3 tools/run_pepper_valley_benchmark.py --stage jit --check-baseline
python3 tools/run_pepper_valley_benchmark.py --stage furnace --check-baseline
python3 tools/run_pepper_valley_benchmark.py --stage furnace-jit --check-baseline
python3 tools/run_pepper_valley_benchmark.py --route rail-three-owned --stage jit --check-baseline
python3 tools/run_pepper_valley_benchmark.py --route rail-three-owned --stage furnace --check-baseline
python3 tools/run_pepper_valley_benchmark.py --route rail-three-owned --stage furnace-jit --check-baseline
```

Six new simulation cases passed with versioned snapshots (standalone JIT v5; furnace stages v7), exact steady quantities, goods-value and cash reconciliation, and no congestion. Maximum expected throughput is 134 units with the furnace. The original road v5 baseline was also rechecked after extending the harness. Snapshot inspection asserts JIT feeds zero units for the lone factory and 32 steel for the chain, and verifies identical measured means with/without JIT.

The harness now includes stockpile-sale `port_outbound` charges alongside factory-sale `port_insurance` in the export-port breakdown. This corrects reporting for the added surplus steel; it does not change game billing. Startup chain decomposition is not used for steady tariff assertions because surplus sales ramp up independently of production.

[Current independent-provider versus local-steel contract](../../tests/scenarios/pepper_valley_motors_local_steel.json). [Raw comparison and sensitivity results](../../reports/balance/pepper_jit_furnace_2026-09-19.json). [Previous fee/progression review](middleman-fee40-progression-2026-09-19.md).
