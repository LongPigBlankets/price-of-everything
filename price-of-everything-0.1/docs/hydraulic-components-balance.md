# Hydraulic components

Added `g_077` hydraulic_components at a £7 base price, with steel for metal hardware, rubber for hoses/seals, and processed oil as the fluid/lubricant proxy. This is an abstract component bundle, not a physical bill of materials. It is market-buyable and sellable, uses solid-heavy transport, and has an original scalable cylinder/valve icon.

## Production

| Recipe | Building | Inputs | Output | Power | Unskilled / skilled / highly skilled labour |
| --- | --- | --- | ---: | ---: | --- |
| r_236 Hydraulics Manufacturing | Industrial Goods Factory | 16 steel, 3 rubber, 2 processed oil | 16 | 20 | 2500 / 1000 / 100 |
| r_237 Hydraulics Automated Assembly | Assembly Plant | Same | 18 | 20 | 1200 / 1000 / 200 |

Both recipes are available without new research gates. Automated assembly uses fewer workers with a higher highly-skilled share, produces 12.5% more output, and pays the assembly plant's existing higher maintenance.

## Consumers

Every construction-equipment/heavy-vehicle batch consumes 6 hydraulic components and 8 tyres. A supplier produces enough hydraulics for two such batches (12 units), leaving 4 units from manufacturing or 6 from automation. Transport capacity and deliveries still apply when suppliers are elsewhere.

Construction equipment's common inputs are 20 steel, 8 tyres, 6 hydraulic components and 2 electrical components. ICE adds 4 large engines and 1 motor; EV adds 10 motors and 3 batteries. Plastics are removed. Output remains 12 equipment.

All three heavy-vehicle variants use 11 car bodies, 6 hydraulic components and 8 tyres. Conventional/automated combustion adds 9 large engines, 7 batteries and 18 fuel. Electric adds 3 large engines, 9 batteries and 26 motors. These consistent reductions in existing inputs offset the added components. Output remains 5 heavy vehicles. All five consumers have exactly six input goods. Passenger-car recipes are unchanged.

## Real-engine validation

Same isolated Stoneshore Docks scenario: market inputs and grid power, market outputs, no other buildings/advisors/bonuses/loans, default labour policies. Ten consecutive operating turns starting with first production, including all operating costs, tax and dividends.

| Recipe | Sales/turn | Retained profit/turn |
| --- | ---: | ---: |
| Hydraulics Manufacturing | £112.00 | £11.16 |
| Hydraulics Automated Assembly | £126.00 | £16.96 |
| Construction Equipment ICE | £516.00 | £20.10 |
| Construction Equipment EV | £553.05 | £24.30 |
| Heavy Vehicles Assembly | £1462.42 | £7.90 |
| Heavy Vehicles Automated Manufacturing | £1462.42 | £31.32 |
| Electric Heavy Vehicles Manufacturing | £1462.42 | £39.23 |

All seven cases produced in every sampled turn and reconciled cash to their cost components. This demonstrates standalone market profitability; the two-consumer capacity comparison is per-batch arithmetic, not a multi-building transport test.

Results: `reports/recipe_profitability/sd-hydraulics-v1/`. Before-change snapshot: `data/balance_baselines/2026-09-07_pre-hydraulics.csv`. Earlier exports remain historical.

Verification completed: script parse check clean, 3,702 unit checks and 723 end-to-end checks passed. A windowed render confirmed all seven recipe rows and the hydraulic-components icon; all consumer rows fit the six-input layout. The existing save importer seeds prices from the current catalogue, including newly added goods.
