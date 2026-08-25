# Balance v4 end-to-end results

Turn horizon: 150. A dash means the threshold or bankruptcy condition was not reached.

| Scenario (recipes) | Profit >100 | >200 | >500 | >1000 | Start / port distance | Buildings 30/80/150 | Units sold 30/80/150 | Expansion loans / gate waits | Integrated | Bankrupt | Red |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Motors (r_009) | 16 | — | — | — | £1,900 / 3.0 | 8/8/8 | 1000/6095/13235 | 3 / 0+16 | — | 41 | 4 |
| Motors Road 1200 (r_009) | — | — | — | — | £1,200 / 2.0 | 4/4/4 | 0/0/0 | 0 / 0+0 | — | 14 | 8 |
| Motors Metal Path 1200 (r_009) | — | — | — | — | £1,200 / 2.0 | 3/4/10 | 888/4549/7289 | 5 / 1+1 | — | — | 4 |
| Motors Metal Magnate (r_009) | 24 | — | — | — | £300 / 0.0 | 6/16/16 | 3060/10530/10139 | 0 / 0+0 | — | — | 2 |
| Electrochem (r_012, r_079, r_080) | 31 | — | — | — | £1,900 / 3.0 | 6/19/20 | 442/2843/7176 | 11 / 0+0 | — | — | 15 |
| Advanced Materials (r_020, r_044, r_076, r_082) | 31 | 136 | — | — | £1,900 / 3.0 | 6/18/22 | 442/3719/8499 | 5 / 0+2 | — | — | 2 |
| Batteries (r_099, r_102, r_136) | 31 | — | — | — | £1,900 / 3.0 | 6/17/21 | 442/1220/2403 | 3 / 0+0 | — | — | 6 |

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
- The exact Metal Magnate portfolio reaches full integration on turn -1; the blank-start portfolios do not.
- No portfolio reached profit above £100/turn by turn 150; all higher thresholds also remained unreached.
- Electrochem reaches bankruptcy on turn -1 and Advanced Materials on turn -1; their earlier green results depended on earned bonuses.
- Batteries reaches bankruptcy on turn -1 before any target battery recipe runs.
- The £1,200 road motor variant starts two tiles from port, first runs motors never, sells 0 motors, and reaches bankruptcy on turn 14. It survives much longer than the £1,500 rail benchmark (turn 41) but still cannot finance copper extraction and full integration.
- The prudent £1,200 motor path first runs motors turn 131 and sells 560 motors. It takes 5 strategy-approved expansion loan(s), waits 1 times for the 1.5× loss-making cash cushion, and reaches bankruptcy on turn -1 before full raw integration.
- Metal Magnate first runs motors turn 42, sells 1705 motors and takes no strategy-approved expansion loan. Its inherited finite coal and iron deposits eventually exhaust; owned generation then stalls, cumulative post-integration grid purchases reach 0 power, and bankruptcy follows on turn -1.
