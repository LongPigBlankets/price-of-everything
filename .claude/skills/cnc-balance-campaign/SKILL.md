---
name: cnc-balance-campaign
description: Load this to work on price-of-everything's hardest live problem - detecting and killing the SOLVED ECONOMY (dominant strategies, free money, the 4 standing e2e profitability failures) - or to build/extend the strategy-sweep harness, or to decide which balance lever to move and prove it worked. An executable, decision-gated campaign with exact commands, expected observations at every gate, ranked tuning levers with blast radius, and the promotion protocol.
---

# The balance campaign — detect and kill the solved economy

The core design risk (named in CLAUDE.md): an economy that is *trivially solvable*.
The scoreboard exists today as the e2e harness's **4 standing profitability failures**
and its metrics JSON. This campaign turns that scoreboard into a tuning loop. Success
is measured, never eyeballed.

**Prime directives**: never "fix" a failing assertion by weakening it; never tune by
eye; every tuning change routes through `cnc-balance-change-control`; predict numbers
before running (`cnc-sim-analysis-toolkit` §4); everything is deterministic — record
seeds.

## Phase 0 — baseline (do this before ANY tuning work)

```bash
cd "/Users/crisu/Price of Everything/price-of-everything/price-of-everything-0.1"
"$GODOT_BIN" --headless --path . res://tests/e2e_stoneshore.tscn -- 100 2>&1 | tee /tmp/e2e_baseline.log
grep -E "FAIL|==== E2E|latest metrics" /tmp/e2e_baseline.log
```
EXPECTED (2026-07-05): `598 passed, 4 failed`; the 4 FAILs are exactly:
coal-runway recent profitability / last-10-turns profit / cumulative profit /
buildout-increases-cash. Record the metrics JSON (cash_after_*, cumulative_profit_post_tax,
turn timing). **Gate:** any OTHER failure → your tree is broken; stop and fix first
(`cnc-validation-and-qa`).

Harness anatomy (read before extending): `tests/e2e_stoneshore.gd` — drives the real
game headlessly through the UI-facing sim API; scenario config
`tests/scenarios/open_field_1.json` (build order, routes, surplus-sale tiles,
tile-only inputs); perf baseline `tests/snapshots/e2e_benchmark_baseline.json`;
prints `[E2E] latest metrics: {...}`. Related instruments: `tools/balance.py`
(OFFLINE recipe-margin model — ⚠️ known ~3× pessimistic vs the engine; use for
ranking, never absolutes), `tools/sim_mini_strategy.gd`, `tools/sim_motor_candidates.gd`
(headless scenario skeletons), `tools/buildorder_sweep.py`-style scratch sweeps have
existed — check `git log --all --oneline | grep -i sweep`.

## Phase 1 — build the sweep runner (the missing instrument)

Goal: `run_sweep(strategy, seed) → metrics row`, all headless, deterministic.

1. Clone `e2e_stoneshore.gd` into `tests/sweep_runner.gd` (+ .tscn) that reads TWO
   args: `-- <strategy_id> <seed>`. Set `MatchState.match_rng_seed = seed` before
   world build; `TurnManager.fast_mode = true`; run to turn 100 (300 later).
2. Encode strategy archetypes as build/policy rule-sets (data, not code — a JSON per
   archetype under `tests/strategies/`):
   - **dirty-rush**: coal power + heavy industry ASAP, ignore green, max loans.
   - **green-rush**: renewables + clean routes early, accept slower ramp.
   - **trader**: minimal production; buy-low/sell-high volume, seaport subscriptions,
     special orders (this one EXERCISES the known arbitrage holes — expected to look
     too good until they're fixed; that's signal).
   - **tall integrator**: one region, full vertical chain to an apex good.
   - **wide sprawler**: many tiles, shallow chains, sell intermediates.
   - **per-track specialists**: one per victory track (5 archetypes).
   Each archetype = ordered build list + standing orders (auto-sell/keep-X, market
   inputs, labour slider, loan policy) executed by the runner's simple interpreter.
3. Emit ONE JSON line per run: `{strategy, seed, profit_per_turn_curve(10-turn
   buckets), final_money, track_scores_by_turn, price_impact_incurred (sum |impact_pct|
   across traded goods), tax_paid, loans_drawn, buildings_built, turn_p95_ms}`.
4. Driver script (bash/python) loops archetypes × seeds → `docs/sweeps/<date>.jsonl`.

**Gate:** two runs with the same (strategy, seed) must be byte-identical metrics —
if not, you found a determinism break: STOP, that outranks balance
(`cnc-architecture-contract` rule 3, `cnc-debugging-playbook` last row).

## Phase 2 — the sweep matrix

Minimum credible: 10 archetypes × 10 seeds × turn-100. Record everything under
`docs/sweeps/` (committed — reproducibility is the methodology,
`cnc-research-methodology`).

## Phase 3 — decision gates (read the matrix)

| Observation | Verdict | Branch |
|---|---|---|
| One archetype wins (final_money or any track) on >60% of seeds | **Dominant strategy** | Phase 4, levers targeting its edge |
| Trader dominates | Expected — it monetizes the KNOWN holes (special-order arbitrage, clamp-exempt paths, free manual freight) | fix the holes first (they're audit items, not tuning), THEN re-sweep |
| All profit curves monotone-up, no archetype ever stressed for cash | Economy too loose | Phase 4: global levers (decay, tax, labour) |
| The 4 standing failures flip green with NO tuning change | Suspect the harness or an accidental balance edit | `git diff` economy_config + CSVs vs main; audit your change |
| Archetypes cluster within ~15% with different track winners | **Healthy tension** | tighten seeds/turns; move to turn-300 sweeps |
| Nobody profits (all 4 failures + sweeps all negative) | Economy too tight (the CURRENT state per the standing failures) | Phase 4: chain-local levers first — see below |

## Phase 4 — the tuning menu (ranked, with blast radius)

Move ONE lever per iteration. Predict the effect numerically first (toolkit §2/§3/§5),
then sweep before/after. All changes via `cnc-balance-change-control`.

| Lever | Blast radius | Notes |
|---|---|---|
| Recipe quantities / energy_req (CSV) | ONE chain | first choice for "this chain can't profit" (the current standing-failure shape: the motor chain) |
| Building base_price / materials | one building's ROI | affects buildout-cash failure directly |
| `PRICE_IMPACT_RATE_*` / cap / recovery | per-good, volume players | tightening punishes dumping; loosening helps traders |
| Per-good `decay_rate` | that good's whole timeline | market-wide mood; small changes compound over 300 turns (toolkit §2 closed form) |
| Transport class rates / congestion tiers | spatial play | interacts with make-vs-buy stance (`cnc-design-intent`) |
| `LOAN_*` | pacing/leverage | remember the open loan-tax-shield wart skews this |
| `TAX_RATE` / `DIVIDEND_RATE` | economy-wide | last resort — moves everything |
| `LABOUR_*` incl. output pressure | economy-wide | second-to-last |

Fenced wrong paths: weakening assertions; tuning `GLUT_UNITS` (legacy, not the price
model); "just" giving the player more starting cash (it moved once: `c6a7500` — do it
only as an explicit design decision); running `build_recipes_all.py` (DESTRUCTIVE —
`cnc-content-pipeline`); fixing trader dominance by nerfing trading instead of closing
the audit holes it exploits.

## Phase 5 — promotion

1. Before/after: the 4 standing failures' status + full sweep matrix deltas.
2. Unit suite green; e2e benchmark (perf) assertion still green.
3. Change-control note: intent, lever, prediction vs observed, sweep evidence path.
4. If the standing failures flip green **as predicted**: update those e2e assertions'
   context comments (they're now guarding the healthy state), land the sweep configs +
   results, and record the win in `cnc-failure-archaeology`. That event is also the
   methodology's falsifiable milestone (`cnc-research-methodology`).

## When NOT to use this skill
- One-off "is this number sane" analysis → `cnc-sim-analysis-toolkit`
- The gate/evidence rules themselves → `cnc-balance-change-control`
- Endgame turn-time problems → `cnc-performance-playbook` Part B

## Provenance and maintenance
Compiled 2026-07-05. The 4-failure baseline, harness anatomy and metrics fields were
verified that day; archetype list and gates are the owner-approved plan (not yet built
— Phase 1 is the first task).
- Re-baseline: Phase 0 commands verbatim.
- Harness fields: `grep -n "latest metrics" price-of-everything-0.1/tests/e2e_stoneshore.gd`
- balance.py pessimism caveat: header comments of `price-of-everything-0.1/tools/balance.py`.
