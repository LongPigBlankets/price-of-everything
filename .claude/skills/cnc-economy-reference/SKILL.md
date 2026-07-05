---
name: cnc-economy-reference
description: Load this to understand or reason about ANY number the economy of price-of-everything produces - prices, the glut/deficit price-impact model, buy/sell spreads, the RAG imputed-cost indicator, labour cost/output math, tax, loans, power settlement, transport cost. The domain pack for someone who has never seen input-output economics, describing the LIVE model (which supersedes several older docs). Not a tuning guide.
---

# Economy reference — the live model, formula by formula

⚠️ Several older documents (and some code comments) describe a **retired** glut model
("1% per 100 units over a global threshold"). The live model is below, shipped 2026-07.
When a doc and this file disagree, verify in code — the Provenance section tells you how.

## 1. Prices

- `MarketState.prices[good]` is the **impact-free base price**, seeded from
  `base_price` (goods CSV) and drifting every turn by that good's `decay_rate`:
  `base ← base × (1 − decay_rate)`. Decay is monotonic by design (a legibility/pressure
  mechanism — see `cnc-design-intent`), typically 0.001–0.005/turn.
- The price you SEE and TRADE at: `get_price(good) = base × (1 + impact_pct/100)`.
- Forecast columns extrapolate the decay from the effective price
  (`get_estimated_price_in_n_turns`), holding impact constant.

## 2. Price impact — the live glut/deficit model

Per good, per turn, the player's **net** market volume (units sold − units bought) is
compared to thresholds derived from the good's **base output** =
`Catalog.base_output_for_good(good)` = the largest per-turn output quantity among
active recipes producing it (L1, unmodified). Example: copper wiring base output 32 →
thresholds 64 | 96 | 128.

| Net volume this turn | Accrual to `impact_pct` |
|---|---|
| ≤ 2× base output | recovery: move toward 0 by 0.1 %/turn |
| > 2× (strictly) | ±0.1 %/turn |
| > 3× | ±0.2 %/turn |
| > 4× | ±0.4 %/turn |

- Net **selling** accrues downward (glut discount); net **buying** accrues upward
  (deficit premium). Cap: ±50% (`PRICE_IMPACT_CAP_PCT`). The accrual folds in at
  `MarketState.tick_turn()` (on `turn_advanced`), stacking on top of that turn's decay.
- Volume feeds: `execute_sale` (all ordinary sales), the production auto-sell, and
  `MatchState.queue_buy`. **Special-order deliveries are exempt** (contract-priced).
- `impact_pct` persists in saves. UI: the market tab's "Impact thresholds" column and
  the bracketed base-price-under-actual display.
- Goods with no active producing recipe have base output 0 → **no impact** (deliberate).
- Owner-planned evolution (open): thresholds scale with expected output every ~10 turns.
- LEGACY trap: `GLUT_UNITS`/`price_impact_pct_for()` in economy_config are NOT this
  model — they only size the per-tile auto-sell volume cap ("impact tolerance" UI).

## 3. Spread, clamp, and the special-order exception

- Buy price = sale price × (1 + `MARKET_BUY_MARKUP` 0.05 × market_spread modifier).
- Realized sale price = min(modifier-uplifted price, buy price) — the **anti-arbitrage
  clamp**: you can never buy-then-resell at a profit on the ordinary market.
- Special orders bypass the clamp and pay a 25–40% premium on required units — which is
  why buy-from-market → deliver-to-order is a KNOWN open exploit (audit; don't build on
  it, don't "fix" it without design signoff).
- Two sell paths, one wart (open): everything converges on `MarketState.execute_sale`
  EXCEPT the PROCESS auto-sell (`_sell_stockpile_totals`), which prices at raw
  `get_price` — i.e. paid-for `market_price` modifiers (research/advisor uplifts) do
  not apply to auto-sold goods. Manual sells also currently pay no freight while
  auto-sells do (open).

## 4. Leontief imputed cost — the RAG indicator

`scripts/cost_solver.gd`, runs as the `cost_solve` sub-phase. For each producing
building: unit cost = (inputs at their own imputed costs + energy at grid price +
maintenance + labour) / units out, propagated in topological sweeps over the recipe DAG
(≤20 sweeps). **Byproducts**: a recipe's cost is allocated across its outputs weighted
by *quantity × market price* — so chlorine/hydrogen byproducts carry their fair share.
RAG: green < ~90% of market, amber ≈ market, red > ~110% (legend in `market_row.gd`).

Known limits (open, documented): production **cycles** (computer→fab→computer) exhaust
the sweeps and go uncosted (RAG blank); the energy leg prices ALL consumption at
`GRID_BUY_PRICE` even when self-powered — self-powered empires look redder than their
cash reality. Junior trap: "fixing" byproduct weighting by splitting cost equally
double-counts — the market-value weighting is the design.

## 5. Labour

- **Cost**: per building, `base_labour × labour_factor`, where
  `labour_factor = max(0.40, 1 + headcount_modifiers + (slider − 1) + policy_delta)` —
  additive deltas on a 100% base with a hard 0.40 floor (`LABOUR_FACTOR_MIN`).
  Slider ∈ {0.8, 1.0, 1.2}. Wage classes and per-turn growth: `LABOUR_*_RATE/GROWTH`.
- **Output** (live since 2026-07): the slider also drives
  `labour_output_pressure_pct` — 0.8× accrues −2%/turn (floor −30), 1.2× accrues
  +1%/turn (cap +10), 1.0× recovers 1%/turn toward 0; applied inside
  `workforce_output_multiplier()` along with workforce-policy multipliers
  (pensions/bonus/profit-share/safety cadences). Saved; ticks at PROCESS start.

## 6. Tax, dividends, loans

- Tax = `TAX_RATE` (0.20) × max(0, money_in − money_out) per turn. No loss
  carry-forward (lumpy empires pay more — open design question). KNOWN issue (open,
  audit H3): the full loan payment (principal+interest) is booked as expense, so
  borrowing shields tax.
- Dividends `DIVIDEND_RATE` 0.20 on taxable profit; profit-sharing policy on top.
- Loans: per-loan baked rate/term (`LOAN_TERM_TURNS` 36, `LOAN_INTEREST_RATE` 0.10;
  construction credit differs); borrowing capacity gated on realized profit; early
  repayment charges ALL baked interest (open wart).

## 7. Power

Same-turn generate/consume; a tile participates only with cables, and cable level
hard-caps per-tile draw AND export separately (`CABLE_POWER_CAP {1:2000, 2:4000,
3:7000}` × throughput research). Net shortfall buys from grid at `GRID_BUY_PRICE`;
surplus sells at `GRID_SELL_PRICE` (COO advisor adjusts both). Wind/solar
**intermittency** derates output by up to 40% — computed from THIS turn's mix by a
deterministic allocator but applied to NEXT turn's output (a 1-turn lag; inputs are
still consumed in full — known sharp edge).

## 8. Transport

Cost = per-class rate (`TRANSPORT_RATES`, e.g. solid_heavy vs safe_liquid) × qty ×
route legs × mode multipliers, + congestion surcharge tiers (+100/+200%) fed by LAST
turn's link flow (stable, not self-referential). Fluid classes (`safe_liquid`,
`hazard_liquid`, `liquid`, `gas`) move ONLY by pipes — `reinf_pipes` required for
`hazard_liquid` (see `data/infrastructure.csv good_types_tolerated`). Unreachable
routes return the `INF_TURNS` sentinel (1<<30) with `reachable=false` — consumers must
check it (a leak once showed players "1073741824 turns"). Seaport subscription covers
per-good freight to port for a flat fee. Deferred settlement: sale revenue is locked at
the consume-time quote and paid on arrival.

## When NOT to use this skill
- Changing any of these numbers → `cnc-balance-change-control`
- Hunting the right value / dominant strategies → `cnc-balance-campaign`
- Hand-computing costs/trajectories → `cnc-sim-analysis-toolkit`
- Why the design wants decay/legibility/routes → `cnc-design-intent`

## Provenance and maintenance
Formulas verified 2026-07-05 in market_state.gd, economy_config.gd, production.gd,
cost_solver.gd, power.gd, transport_service.gd, catalog.gd.
- Impact model: `grep -n "PRICE_IMPACT\|price_impact_rate\|_tick_impact" price-of-everything-0.1/scripts/economy_config.gd price-of-everything-0.1/scripts/market_state.gd`
- Clamp: `grep -n "get_sale_price" price-of-everything-0.1/scripts/market_state.gd`
- Labour: `grep -n "labour_cost_factor\|labour_output_pressure" price-of-everything-0.1/scripts/production.gd price-of-everything-0.1/scripts/match_state.gd`
- RAG weighting: read cost_solver.gd byproduct section.
