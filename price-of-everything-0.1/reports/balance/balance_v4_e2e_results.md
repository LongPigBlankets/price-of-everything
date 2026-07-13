# Balance v4 end-to-end results

Turn horizon: 150. A dash means the threshold or bankruptcy condition was not reached.

| Scenario (recipes) | Profit >100 | >200 | >500 | >1000 | Start / port distance | Buildings 30/80/150 | Units sold 30/80/150 | Expansion loans / gate waits | Integrated | Bankrupt | Red |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Motors (r_009) | — | — | — | — | £1,500 / 3.0 | 6/6/6 | 558/558/558 | 0 / 0+0 | — | 28 | 4 |
| Motors Road 1200 (r_009) | — | — | — | — | £1,200 / 2.0 | 5/7/7 | 1930/4892/4892 | 0 / 0+0 | — | 69 | 3 |
| Motors Metal Path 1200 (r_009) | — | — | — | — | £1,200 / 2.0 | 4/10/13 | 856/5384/9226 | 1 / 0+15 | — | 110 | 3 |
| Motors Metal Magnate (r_009) | — | — | — | — | £300 / 0.0 | 6/17/17 | 2696/8820/9004 | 0 / 0+0 | 68 | 143 | 2 |
| Electrochem (r_012, r_079, r_080) | — | — | — | — | £1,500 / 3.0 | 6/16/17 | 60/1302/4553 | 0 / 0+0 | — | 109 | 3 |
| Advanced Materials (r_020, r_044, r_076, r_082) | — | — | — | — | £1,500 / 3.0 | 6/18/19 | 60/3170/6036 | 0 / 0+0 | — | 134 | 3 |
| Batteries (r_099, r_102, r_136) | — | — | — | — | £1,500 / 3.0 | 6/11/11 | 60/60/60 | 0 / 0+0 | — | 63 | 9 |

## Integration scope

- **Motors:** base motors through an initially market-fed steel/copper chain, then pig iron, iron/copper/coal extraction, water and owned coal power
- **Motors Road 1200:** base motors through a downstream steel/copper hub, then nearby pig iron, iron/copper/coal extraction, water and owned coal power using road freight
- **Motors Metal Path 1200:** blank-start motors from stock-controlled water and market-fed coal power through pig iron, steel, copper, wiring and motors; coal, iron, copper and a second power block are attempted after motors
- **Motors Metal Magnate:** the exact Metal Magnate start — £300, four inherited buildings, three owned tiles, seeded inputs, authored infrastructure/routes, no opening debt and four +10% metal legacies — expanded downstream to motors and then fully integrated
- **Electrochem:** all scenario targets
- **Advanced Materials:** all scenario targets
- **Batteries:** LFP manufactured inputs to raw lithium ore, salts and graphite; sodium-ion and iron-air remain standalone comparison lines

## Findings

- All scenarios used their configured starting cash, live loan and land capacity, construction materials, physical deposits, transport maintenance, and owned power.
- Building sale and demolition were not used. The prudent motor path retains standing extraction penalties while neutralizing earned bonuses; the older portfolio fixtures neutralize all modifiers and remain legacy comparisons.
- The exact Metal Magnate portfolio reaches full integration on turn 68; the blank-start portfolios do not.
- No portfolio reached profit above £100/turn by turn 150; all higher thresholds also remained unreached.
- Electrochem reaches bankruptcy on turn 109 and Advanced Materials on turn 134; their earlier green results depended on earned bonuses.
- Batteries reaches bankruptcy on turn 63 before any target battery recipe runs.
- The £1,200 road motor variant starts two tiles from port, first runs motors on turn 6, sells 1904 motors, and reaches bankruptcy on turn 69. It survives much longer than the £1,500 rail benchmark (turn 28) but still cannot finance copper extraction and full integration.
- The prudent £1,200 motor path first runs motors on turn 67 and sells 1344 motors. It takes 1 strategy-approved expansion loan(s), waits 15 times for the 1.5× loss-making cash cushion, and reaches bankruptcy on turn 110 before full raw integration.
- Metal Magnate first runs motors on turn 42, sells 1708 motors and takes no strategy-approved expansion loan. Its inherited finite coal and iron deposits eventually exhaust; owned generation then stalls, cumulative post-integration grid purchases reach 2160 power, and bankruptcy follows on turn 143.
