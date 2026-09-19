# Middleman balance review after the congestion fix

> Follow-up: the current £40 tariff and replacement of introductory port relief are covered in the [fee/progression review](middleman-fee40-progression-2026-09-19.md). The £20 results below remain historical evidence.

Status: review and sensitivity calculations only. No prices, recipe quantities, staffing, energy requirements, upkeep or tariffs changed. Preserve the £10 input-basket / £10 output-batch middleman benchmark. User direction: protect the existing production-chain balance; consider broad price scaling, modest targeted output increases and selective prices for goods with few/no consumers before changing input quantities or redesigning chains.

Follow-up: the [targeted output/terminal-price trial](targeted-output-gains-2026-09-19.md) has now been applied and measured separately. Figures below remain the pre-trial review and analytical hypotheses.

## What the corrected game actually measures

The [Pepper Valley benchmark](../pepper-valley-motors-benchmark.md) now counts at most 94 units per tile per turn, with no congestion surcharge. At turns 40–49, one motor factory contributes **−£33.86 via public roads**, **−£16.32 via rail with three owned sections**, and **+£2.09 in the £20 middleman reference**. Road and rail are actual simulation; the middleman remains arithmetic pending implementation. The other four rail sections are completed public infrastructure, not a simulated government construction schedule.

This is **logistics integration**, not ownership of steel/wiring production. The older balance documents' integrated-chain gains include making inputs internally, avoiding input purchase markups and market/port legs. Their gains should not be expected from switching an otherwise identical factory onto rail alone.

## Relevant August sources, newest first

Dates below come from Git history, not file modification times. A newer committed document is not automatically a description of deployed balance.

| Date / commit | Source | Finding and present applicability |
| --- | --- | --- |
| 29 August, `5ff26b76` specification and `e216b0aa` implementation | [Price-impact ladder](../price-impact-ladder-spec.md) | Retires automatic goods-price decay. Volume relative to a good's base production drives glut/deficit, with a rolling history and growing thresholds. Changing outputs also changes the market's reference volume where that recipe sets the maximum batch. September 7 doubled impact rates; use current code for trials. |
| 20 August, `93582013` | [Recipe rebalance specification](../recipe-rebalance-spec.md), [review table](../recipe-rebalance-table.md), [building-cost analysis](../building-cost-balance.md) | Supports extra output at unchanged inputs/prices as a reward. However, these are draft/generated review artifacts with stale economic assumptions: £1 grid power, £0.15 self-power, tiny building costs, and a proposed replacement recipe file. Their values are not the shipped September economy. Do not apply their generator/replacement instructions to live data. |
| 10 August, `f830e0e5` | Live routing/freight changes | Infrastructure level determines reach; road/rail can carry appropriate fluids. Distance and network access are intentional cost differences. Preserve route-based comparisons rather than making every location equally cheap. |
| 9 August, `fd5d3227`, `8ce560d5` | [Early-game onboarding / freight economics](../early-game-onboarding-spec.md), especially §4.2b | Replaces the flat port fee with 0.5% early / 3% later ad valorem. Shows a glass chain improving through rail and integration without recipe changes. Its earlier decay and flat-fee sections are explicitly superseded. The principle is a viable opening with legible costs, not additional startup cash covering permanent losses. |
| 5 August, `fbd3b410` | [Goods balancing](../goods-balancing.md) | Preserve modestly profitable processing, reward upstream ownership through avoided costs, protect build-material prices and research ordering. Its labour percentage / live build-cost feedback description is stale: runtime now uses recipe headcounts and stored maintenance values. Its build-material dependency warning still matters for construction affordability and offline regeneration. |

The [July latest-pass summary](../../balancing-lastest-pass-july-2026.md) and [balance success scorecard](../../reports/balance/balance_success_summary.md) explain the established supply-ratio constraints and approximate cash targets. Their baseline is **one-turn freight plus a working-inventory reserve**, not four-turn inland roads. They aim for a positive starter cushion and profitable one-input integration, preserving energy requirements, whole-building supplier ratios, coproduct proportions and research rewards. Pepper Valley's longer journey and later port-rate window are stricter conditions.

## More recent evidence that supersedes the old figures

The [September 7 motor/heavy-vehicle review](../motor-heavy-vehicle-balance-2026-09-07.md) is especially relevant:

- Motor Manufacture was already increased from 28 to 30 output, with related motor recipes tuned together. Inputs, power, staffing and prices were initially held.
- Motor price was then deliberately reduced by 2.5%, from £11.3283 to £11.0451, and producers plus downstream consumers were rerun. Raising motor price now would partly undo that work.
- Construction equipment was rebalanced with separate ICE/EV powertrains and consumer checks. Those decisions should not be regenerated from the August draft.
- The measured motor profit of £16.51 was a ten-turn, coastal Stoneshore retained-cash result. It is not directly comparable with Pepper Valley's later inland, pre-tax operating contribution. See the [profitability harness methodology](../../tools/RECIPE_PROFITABILITY.md).

The [September 8 shipped-start/glass audit](glass-and-start-economics-2026-09-08.md) confirms healthy openings and improving integrated glass chains under their specific rules. It also distinguishes the tutorial's permanent early port rate from standard games. Preserve these as regressions; do not assume an inland benchmark proves the whole economy is broken.

## What each permitted lever actually changes

### A common goods-price multiplier

Scaling goods prices together preserves their relative prices and all physical recipe ratios. Current runtime labour is headcount × growing wage rates; maintenance reads stored building data. Neither automatically scales with market goods prices. This corrects the older goods-balancing document's claim about an immediate operating-cost feedback loop.

However, purchased inputs, construction materials, value-based land freight, port charges, storage insurance/capital costs and working-capital funding all rise. Fixed cash construction charges, wages, maintenance, physical freight and the £20 middleman fee do not rise unless separately changed. This is an economic rebalance, not merely changing the currency denomination. Offline balancing tools may regenerate staffing/upkeep, so they must not be run as an incidental part of a price experiment.

A broad 10% increase is a useful conservative comparison, but it cannot be assumed to yield 10% more profit. In this benchmark it adds £9.27 to outsourced contribution, £6.83 to three-owned-rail contribution and £5.29 to road contribution. Because the direct case bears value-based logistics while the middleman fee is fixed, this also widens the absolute outsourcing advantage.

### Tactical output increases around 10%

At held input quantities, staffing, power and goods prices, extra output creates a much larger contribution increase than repricing all inputs and outputs together. A motor change from 30 to 33 is exactly +10%. It preserves consumers' purchase prices and the factory's input demand. This is a candidate to test, not an approved/live recipe change.

It still changes supplier-consumer coverage, freight/port volumes, surplus stock, market-impact reference quantities and research-production thresholds. A base recipe must not overtake its researched alternatives accidentally. Multi-output recipes must preserve deliberately selected coproduct ratios; small integer batches may not support exactly 10%. Check each affected recipe family, not just the target row. Do not automatically scale inputs with outputs: that is a different experiment with different costs.

### Selective apex-price increases

Audit actual dependencies rather than trusting the label “apex”. In current CSVs, motors have **8 recipe consumers**, CPUs have **3**, and computers have **0 recipe consumers but enter 2 building kits**. Building frames have no recipe consumers but enter 13 kits; ICE construction equipment enters 25. These are not isolated price levers.

ICE cars, EV cars and heavy vehicles have no recipe-input consumers or direct building-kit entries in the inspected CSVs, making them better initial price candidates. This is not a complete dependency clearance: check catalysts, battery loading, special orders, research costs, unlock conditions and scripted construction/upgrade requirements as well. Batteries, turbines and panels illustrate why zero recipe consumers alone is insufficient. A terminal-good price increase also helps all its producer variants, so retain their ordering.

## Pepper Valley sensitivity, before changing data

These are **analytical estimates**, not simulations of changed data. Baseline road/rail values are actual v2 results. The hypothetical columns hold routes, utilisation, staffing, power rates, maintenance and inventory quantities fixed and adjust value-based charges. Output growth additionally adjusts outbound per-unit freight and port charges. They exclude construction, tax/dividends, price impact, research, consumer reactions and wider portfolio effects. “All prices” here means goods base prices, not wages or regulated grid rates.

| Operating contribution / turn | Current | All goods prices +10% | Motor output 30 → 33, prices held |
| --- | ---: | ---: | ---: |
| Middleman reference | +£2.09 | +£11.36 | +£35.22 |
| Public roads | −£33.86 | −£28.57 | −£3.86 |
| Rail, three player sections | −£16.32 | −£9.49 | +£15.22 |

The [calculation artifact](../../reports/balance/pepper_valley_sensitivity_2026-09-19.json) records assumptions, formulas and full precision. For the broad-price experiment, road contribution changes with the goods trading margin **minus** inland/port/storage ad valorem; it does not change with gross sales alone. With those fixed assumptions, broad repricing would need approximately +24% for rail break-even and +64% for road break-even, making it an expensive way to solve this particular inland case globally.

Neither lever alone makes logistics ownership beat a fixed £20 provider at this scale. Current three-owned-rail logistics cost £29.41 variable plus £9 maintenance, and port charges plus storage already exceed £20. Raising revenue can fund growth, but a later owned-operation design still needs a viable cost/scale advantage. Treat actual carrier tariffs and future owned fleet operating costs separately; do not charge both for the same service. Preserve upstream production integration as a distinct source of savings.

## Recommended next balance trial

1. Keep current quantities/prices as the control, and retain both pre-fix v1 and corrected v2 logistics snapshots. No input quantities or energy changes.
2. Run separate, reversible scenarios for +10% goods prices and targeted motor-family output around +10%. Compare against the same starts, sample turns and obligations. Do not combine levers before measuring each.
3. For price-only exceptions, begin with dependency-audited terminal goods. Hold intermediate and construction-good prices in the selective trial, especially motors, computers, frames and equipment used to build factories.
4. Re-run the four motor producers, eight current motor consumers, base/researched vehicle ordering, existing glass and metal starts, and at least one co-located upstream chain. Measure both the introductory era and turns 40–49, and allow price impact in a separate longer playthrough.
5. Set the minimum outsourced retained-cash surplus from a desired number of turns to fund expansion plus operating reserves. Separately require an owned-logistics path with positive incremental savings and credible capex/working-capital payback at its intended scale. Borrowing may bridge a delivery delay; it is not a remedy for recurring losses.

Recommendation: **test modest output gains at held prices first for the starter, use selective price changes for genuinely terminal goods, and retain common-price scaling as a measured alternative**. This follows the latest live tuning more closely than rerunning the August draft or altering input ratios across the economy.
