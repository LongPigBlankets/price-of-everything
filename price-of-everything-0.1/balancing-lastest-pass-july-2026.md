# Balancing — latest pass, July 2026

## Purpose

This pass moves recipe economics to a reproducible model rather than a collection of one-off price edits. It is intended to make early production viable after freight and warehousing, reward sensible integration, retain the cost of real energy use, and leave room for later costs and player mistakes.

The source of truth is the committed data, not this prose summary:

- `data/recipes_all.csv` contains every recipe's inputs, outputs, energy, research gate, per-recipe labour and catalysts.
- `data/Goods - goodsMVP.csv` contains every deployed market price.
- `reports/balance/systemic_formula_prices.csv` is the complete canonical-price schedule.
- `reports/balance/systemic_formula_recipe_plan.csv` is the complete formula-derived schedule of output quantities, labour and target margin for active recipes.
- `reports/balance/deployed_recipe_economics.csv` is the complete deployed standalone cashflow view.
- `reports/balance/integer_one_layer_chains.csv` and `reports/balance/forced_one_layer_chains.csv` contain the whole-building integration checks.

These files deliberately keep the full value list in CSV form so it is reviewable, diffable and usable by tools without duplicating hundreds of values into a stale prose table.

## Economic targets

The common comparison is **pre-tax cash after one-turn market freight and a one-turn working-inventory warehouse reserve**. The reserve is a deliberate inclusion: recipes that only work if goods never occupy storage are not robust enough for normal play.

| Recipe class | Standalone target | Notes |
|---|---:|---|
| Start-unlocked base recipe | +£5 to +£10 | After freight and warehousing; excludes tax and dividends. |
| Mine at game start | Negative modifier retained | Mines remain the intentional early exception. |
| Rank I / normal unlock | +£5 to +£30 | May solve a supply-chain or rarity problem rather than maximise cash. |
| Rank II unlock | +£20 to +£60 | More room for specialised capital and skilled labour. |
| Rank III / advanced unlock | +£30 to +£100 | Advanced outputs may be materially better, but still need downstream review. |
| Integrated two-building cluster | +£10 to +£25 net cash | Assumes surplus is sold rather than accumulated. |
| Any integration level | At most +£400 | The remaining high-integration review cases are explicitly reported. |

The target is a cash cushion, not a guarantee that every player layout is profitable. Taxes, dividends, debt service, policy choices, price impact, transport beyond the one-turn assumption, and stockpiled surplus can all make the live result lower.

## What was changed

### Formula-led prices, quantities and labour

1. Pick one non-recycling base recipe as the canonical producer for each good.
2. Solve market prices from that canonical production chain, preserving raw/intermediate/processed/finished/apex relationships where possible.
3. Keep power demand unchanged. It represents physical energy consumption and is not used as a balancing lever.
4. Set maintenance at the building level, then use recipe-owned labour, inputs, output quantities and good prices to reach the target bands.
5. Require every migrated recipe to retain at least 500 unskilled, 100 skilled and 50 highly skilled workers.
6. Bias advanced chemical, polymer, assembly, high-tech manufacturing, electrolyser and electric-arc recipes toward skilled and highly skilled labour.
7. Check that a base consumer generally needs no more than one base supplier building for each canonical input. The formula report records zero canonical links that require more than one supplier building.
8. Round outputs above 36 to nearby multiples of 5 or 12 where that does not break the one-building supply floor. This avoids arbitrary-looking values such as 44 or 69.

The formula converged in 33 iterations. It places 117 of 124 single-output recipes within their target bands before the deliberately reviewed exceptions and deployment overrides.

### Deliberate recipe decisions

- Desalination now yields 40 Pure Water, 10 Basic Salt and 5 Chemical Salts.
- Industrial and high-strength glass, aluminium, windows, steel, rubber and plastics/ethylene were checked as whole supplier-consumer clusters rather than only as standalone recipes.
- ICE cars and heavy vehicle routes were kept modestly profitable; automated and electric heavy-vehicle routes receive higher specialist-labour targets while retaining the base recipe's output quantity.
- CPU price was reduced, lithium-ion batteries and lithium carbonate were allowed to be weak or unprofitable where intended, and research-gated solar panels retain controlled positive margins.
- Fabless semiconductors, semiconductor 3D printing, lithium electrolysis, specialist motors and heavy vehicle routes have explicit deployment overrides in `reports/balance/systemic_deployment_overrides.csv`.
- Sulphuric acid was made slightly profitable; generic acid remains as-is. Acid-producing recipes belong in the chemical-plant family.

### Recipe-owned staffing

Labour is now read from the selected recipe rather than the building default wherever the recipe supplies it. This makes it possible for, for example, a basic furnace recipe and an advanced furnace recipe to use different skill mixes without duplicating buildings.

The production cost path, cost solver, building details, next-turn money projection and tests all use the same recipe staffing data. Legacy rows can still fall back to building labour through the `-1` compatibility sentinel, although migrated rows use explicit recipe values.

### Catalysts

Recipes have a `catalysts` field. Catalysts are goods that must be present in the building's tile stockpile for the recipe to run, but are not consumed by the recipe.

The Battery Storage recipe requires lithium, sodium and iron battery goods as catalysts. The building-details panel surfaces the existing battery requirement UI only when a recipe has catalysts; recipes without catalysts keep their existing presentation.

### Research placement

- Bio-Graphitisation is gated behind the Biochemistry node **Biomass Cracking**, which itself follows Sustainable Forestry.
- Every Level 2 building-upgrade node is Tier II in its own research category, including the warehouse Level 2 node, Pallet Racking Systems.

## How to read live results

There is no intra-tile transport charge. A same-tile producer-to-consumer route is zero turns and £0 freight. It can still incur warehousing if goods sit in the tile stockpile; the Just-in-Time unlock can feed committed local demand directly and avoids that storage for the fed quantity.

The Construct panel shows the base recipe quantity. A running building may report a different effective output because recipe research, building level and workforce-output policies are applied after the base recipe. For example, a base output of 32 becomes 34 under a +5% effective output modifier after rounding.

The money panel reports the whole company, not a single recipe's margin. It includes upstream building costs, raw market inputs, power, warehousing, outbound freight, tax, dividends and loan interest. Use `BuildingReadout`/the building panel for the per-building diagnostic, and use the integration reports for a whole-chain comparison.

Surplus must actually be sold for a chain's surplus value to become cash. The reports include a `settled auto-sell` scenario and a `hold surplus for one turn` scenario specifically to expose this difference. For example, the model's base motor + steel + copper-wiring cluster has operating profit +£39.06 and post-tax/dividend cash +£25.00 when surplus is sold; holding the production instead consumes inputs and labour without recording sales revenue.

## Validation and reproducibility

Run the tools in this order from `price-of-everything-0.1`:

```sh
python3 -B tools/systemic_recipe_formula.py
python3 -B tools/apply_systemic_recipe_plan.py
python3 -B tools/recipe_rebalance.py
```

The tools regenerate the balance reports listed above. They are committed as review artifacts; generated Godot `.translation` and `.import` files are intentionally not treated as balancing source data.

The Godot regression suite covers recipe labour ownership, catalyst requirements, the Bio-Graphitisation gate, and the Tier II Level 2 upgrade rule. At the time of this pass the suite records 1,522 passing tests and one pre-existing stale-hills-bake failure; re-run `tools/bake_hills.tscn` after map or generator edits to clear that unrelated failure.

## Follow-up review points

- Revisit the three explicit +400 integration-cap review cases in `recipe_rebalance_summary.md` after live playtesting.
- Recheck market price impact once production volumes, port placement and policy choices are exercised in longer saves.
- Keep the one-turn freight assumption explicit when evaluating a player layout: a remote, congested or unsold chain is intentionally worse than the report baseline.
- Prefer changes to the formula, canonical price selection, supply ratio, labour mix or explicit override table over ad-hoc edits to individual CSV rows.
