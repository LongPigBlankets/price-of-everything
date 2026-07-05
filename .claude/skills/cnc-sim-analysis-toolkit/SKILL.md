---
name: cnc-sim-analysis-toolkit
description: Load this to reason about price-of-everything's economy WITHOUT (or before) running it - hand-computing an imputed cost, bounding a price trajectory under decay and impact, break-even analysis for a building, predicting sweep numbers before a run, or estimating when sales volume crosses price-impact bands. The prove-it-first layer that turns the harness from a slot machine into an instrument.
---

# Sim analysis toolkit — predict it, then run it

Five recipes. Each: method → worked example with this repo's real constants → what to
do with the answer. Re-verify any constant you use (`cnc-economy-reference` provenance
commands) — everything is volatile until EA ships.

## 1. Hand-compute a Leontief imputed cost (what the RAG "should" say)

Method (mirrors `cost_solver.gd`): process the recipe DAG in dependency order; a
building's turn cost = Σ(input qty × input's imputed unit cost) + energy_req ×
GRID_BUY_PRICE + maintenance + labour; allocate across outputs by **qty × market
price**; unit cost of output o = allocated cost ÷ qty_o.

Worked example (illustrative quantities — pull live ones from `recipes_all.csv`):
coal mine (no inputs, cost £6/turn, 60 coal) → coal ≈ £0.10/u imputed.
Furnace: 30 coal + 40 iron_ore(@£0.15 imputed) + energy 30×0.10 + £5 fixed
= 3.0+6.0+3.0+5.0 = £17/turn → 30 steel → steel ≈ £0.567/u. If market steel = £3.20,
RAG is deep green (0.57/3.20 ≈ 18%). Byproduct case: chlor-alkali's cost splits across
chlorine/NaOH/hydrogen by (qty×price) shares — computing "cost per chlorine" by
dividing total by chlorine qty alone is the classic double-count error.
Use: sanity-check a red/green RAG before believing it; predict how an input price
change propagates downstream (multiply through the chain).

## 2. Bound a price trajectory (closed forms)

Base decay: `P_base(N) = P₀ (1−d)^N`. Real d values are 0.001–0.005 → over 300 turns:
(0.999)³⁰⁰ ≈ 0.741, (0.995)³⁰⁰ ≈ 0.222. So a d=0.005 good loses ~78% of base by game
end — by design (`cnc-design-intent`).

Impact overlay: effective `P = P_base × (1 + A/100)`, A stepped per turn by the band
rate (−0.1/−0.2/−0.4 selling; + for buying), clamped ±50, recovering 0.1/turn under
2× threshold. Worst-case dump: A hits −50 after 125 turns of sustained >4× selling
(50/0.4); recovery from −50 to 0 takes 500 quiet turns — i.e. **within one game, deep
glut is effectively permanent**. A 20-turn >4× campaign costs A = −8 → prices ~8%
under base ≈ 13.5 quiet turns to recover. Use: price the cost of a dumping strategy
before sweeping it; set expectations for gate 3 in the campaign.

## 3. Break-even for one building

`profit/turn = out_qty×sale_price − Σ(in_qty×acquisition_cost) − energy×net_power_cost
− maintenance − labour×labour_factor − freight_on_route − tax_share`.
Acquisition cost: market buy price (×1.05 spread + freight) if bought; imputed (§1) if
made. Design-model shorthand from the turn-1 rebalance:
`running_cost ≈ K_tier × value_add − energy × own_power` — useful for ranking, but the
ENGINE diverges (grid pricing of self-power in RAG, tax timing, freight asymmetries —
audit-documented), so never promote on the shorthand alone. Use: pre-filter which
chains the campaign's per-chain levers could plausibly rescue, and by how much
(“needs sale ≥ £X or input ≤ £Y to break even”).

## 4. Hypothesis-predicts-numbers (the protocol)

Template — fill BEFORE running anything:
```
HYPOTHESIS: <one mechanism>
PREDICTS: <metric> = <number ± tolerance> under <exact command + seed>
IF INSTEAD <other observation> → hypothesis dead, because <why>
```
Worked example: "Raising motor-chain recipe output 10→12 makes the buildout profitable."
PREDICTS: e2e `cumulative_profit_post_tax` rises by ≈ (2 units × motor sale price −
marginal inputs) × selling-turns ≈ +£640 ± 20% at turn 100, and standing failure #4
flips ONLY if cash_after_buildout delta > 0. Run, compare, keep or kill. One mechanism
must explain ALL observations including the negatives — partial credit is how wrong
models survive (`cnc-research-methodology`).

## 5. Impact-band crossing estimator

Threshold base = `Catalog.base_output_for_good(g)` = the largest output qty among
active recipes producing g. Bands bite strictly above 2×/3×/4× of it. So: copper
wiring (base 32) → selling ≤64/turn is impact-free; a single L1 producer routed to
market (32/turn) NEVER moves the price; two producers on one market tile (64) still
don't; three (96) sit in the 0.1% band, at −0.1/turn ⇒ −2% after 20 turns. Rule of
thumb: **impact punishes concentration beyond ~2 same-good producers' worth of
dumping** — and buying mirrors it (a mega-buildout importing >2× base output of one
material per turn pays a rising premium). Use: predict `price_impact_incurred` per
archetype before sweeps; size "sell all except X" floors.

## When NOT to use this skill
- Actually running sweeps / choosing levers → `cnc-balance-campaign`
- What a formula IS → `cnc-economy-reference`
- Whether you may change the number → `cnc-balance-change-control`

## Provenance and maintenance
Compiled 2026-07-05. Constants quoted (decay ranges, impact rates/cap/recovery, spread)
verified that day in economy_config.gd / goods CSV — re-verify before computing:
`grep -n "PRICE_IMPACT\|MARKET_BUY_MARKUP\|TAX_RATE" price-of-everything-0.1/scripts/economy_config.gd`
and spot-check a decay: `python3 -c "import csv; print({r['internal_name']: r['decay_rate'] for r in csv.DictReader(open('price-of-everything-0.1/data/Goods - goodsMVP.csv'))}['coal'])"`.
Worked-example quantities are illustrative — always pull live recipe rows first.
