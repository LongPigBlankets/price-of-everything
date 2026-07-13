# Balance success metrics

All profit is pre-tax cash. Standalone and one-level cases use grid power, one-turn market freight, and a one-turn working-inventory reserve. Full integration recursively costs inputs to extraction, charges only final-output friction, and uses the named owned-power scenario's long-run opportunity cost.

- Start-unlocked recipes profitable above £0: **75 / 79**
- Research recipes beating the best start-unlocked recipe for the same primary output: **44 / 47** (9 without a base comparator)
- Recipes with at least one profitable one-input integration link: **105 / 105**
- Improved one-input links: **278 / 278**

## Fully integrated profit thresholds

| Owned power | Recipes | >£50 | >£100 | >£150 | >£200 | >£300 | >£400 |
|---|---:|---:|---:|---:|---:|---:|---:|
| coal power | 136 | 58 | 28 | 17 | 13 | 5 | 3 |
| oil power | 136 | 58 | 28 | 17 | 13 | 5 | 3 |
| onshore wind + lithium battery | 136 | 53 | 23 | 16 | 11 | 4 | 3 |

## Named examples

One-level profit is the combined two-building chain; the adjacent comparison is what those same two buildings earn when operated independently.

| Example | Standalone | Integrated input | Separate buildings | One-level chain | Gain | Full coal | Full oil | Full firmed wind |
|---|---:|---|---:|---:|---:|---:|---:|---:|
| Motors | 7.5 | copper_wiring via Copper Wire Drawing | 15.0 | 22.4 | +7.4 | 108.8 | 108.8 | 93.9 |
| Chlor-alkali | 5.0 | pure_water via Water Pumping | 13.3 | 19.5 | +6.3 | 44.4 | 44.4 | 32.9 |
| ICE cars | 15.0 | engine via ICE Engine Manufacturing | 22.5 | 36.7 | +14.2 | 286.8 | 286.8 | 256.3 |
| CPUs | -10.0 | circuit_board via Basic Circuit Soldering | -2.5 | 6.8 | +9.4 | 120.5 | 120.5 | 99.9 |
| Windows — aluminium | 10.0 | glass via Industrial Glassmaking | 17.5 | 21.6 | +4.1 | 85.2 | 85.2 | 68.6 |
| Windows — PVC | 7.5 | glass via Industrial Glassmaking | 15.0 | 19.6 | +4.6 | 90.6 | 90.6 | 76.4 |
