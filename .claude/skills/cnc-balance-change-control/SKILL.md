---
name: cnc-balance-change-control
description: Load this BEFORE changing any number that affects the economy of price-of-everything - anything in economy_config.gd, any CSV tuning column (base_price, decay_rate, co2_tax_multiplier, green_sales_premium, recipe quantities/energy), loan/tax/labour constants, or when unsure whether a change is a "code fix" or a "balance change". Defines the change classes, the gating each requires, and the non-negotiables with their incidents.
---

# Balance change control — nothing changes silently

## Owner ruling (2026-07-05)

**Everything is volatile until EA ships.** No constant is sacred; tuning is *expected*.
That is not permission to tune casually — it means the gate below applies to
*everything*, because with no "settled" tier, evidence is the only thing separating
tuning from vandalism.

## Classify your change first

| Class | Definition | Gate |
|---|---|---|
| **Code fix** | Behavior was objectively wrong vs. its own spec/comment; numbers unchanged | Unit suite + e2e failure-set unchanged |
| **Content addition** | New good/recipe/building/research at defaults consistent with peers | `cnc-content-pipeline` checklist + e2e unchanged |
| **Balance change** | ANY numeric change to: `scripts/economy_config.gd`; CSV columns `base_price`, `decay_rate`, `co2_tax_multiplier`, `green_sales_premium`; recipe input/output quantities or `energy_req`; building `base_price`/materials; research thresholds | Full protocol below |
| **Mechanic change** | New formula/system (even "just wiring what the UI promises") | Balance protocol + design note; flag to owner |

Gray zone rule: if a "fix" changes any number a player experiences (price, cost,
output, duration), it's a balance change. The modifier-duration off-by-one fix
(2026-07, commit `cb63acc`) was correctly treated as one: DECIDE-granted timed bonuses
got one turn shorter — behaviorally visible, so it shipped with updated tests and an
explicit changelog line.

## The balance-change protocol

1. **State the intent** — one sentence: which lever, which direction, what player-visible
   outcome you predict. Write the predicted numbers BEFORE running anything
   (`cnc-sim-analysis-toolkit` §hypothesis-predicts-numbers).
2. **Record before/after** — the exact constant(s), old → new value.
3. **Evidence** (all three):
   - Unit suite green (`python3 tools/run_tests.py`);
   - E2E run with metrics quoted; the 4 standing profitability failures may flip ONLY
     if that was the declared intent (they are the balance scoreboard — see
     `cnc-validation-and-qa`);
   - Once the sweep harness exists (`cnc-balance-campaign` Phase 1+): a before/after
     archetype sweep. Until then, say so explicitly ("sweep N/A — harness not built").
4. **Commit hygiene** — the commit message carries intent + before/after + evidence
   summary. Balance constants are never buried inside unrelated commits.

## Current tuning hot-spots (volatile even by this project's standards, 2026-07-05)

These shipped recently with *placeholder or first-guess* numbers and are the most
likely levers you'll be asked to move — all still route through the protocol:

| System | Constants | Location |
|---|---|---|
| Price impact (live glut/deficit model) | `PRICE_IMPACT_RATE_2X/3X/4X` (0.1/0.2/0.4), `PRICE_IMPACT_CAP_PCT` (50), `PRICE_IMPACT_RECOVERY_PCT` (0.1); thresholds derive from base outputs | `economy_config.gd` |
| Labour output response | `LABOUR_OUTPUT_PRESSURE_PER_TURN` (−2), `..._FLOOR` (−30), `..._MOMENTUM_PER_TURN` (+1), `..._CAP` (+10), `..._RECOVERY_PER_TURN` (1) | `economy_config.gd` |
| Loans | `LOAN_TERM_TURNS` 36, `LOAN_INTEREST_RATE` 0.10 (+ construction-loan divergence) | `economy_config.gd` |
| Tax/dividends | `TAX_RATE` 0.20, `DIVIDEND_RATE` 0.20 | `economy_config.gd` |
| Labour policy spectrums | four placeholder positions ship with NO effects yet (pensions-minimum, small bonus, 10% share, push-automation) — wiring them IS a balance change | `labour_policy_tab.gd` consts |

Legacy caveat: `GLUT_UNITS` / `MAX_PRICE_IMPACT_PCT` / `price_impact_pct_for()` are NOT
the live price model — they only feed the auto-sell volume-cap UI. Tuning them does not
tune prices.

## Non-negotiables (each with its incident)

1. **Determinism** — a balance change must not introduce unseeded randomness; sweeps
   and saves both depend on it (`cnc-architecture-contract` rule 3).
2. **Save compatibility** — if your change alters saved-state shape (new accumulators
   etc.), follow `cnc-save-and-migration`; the labour-pressure accumulator shipped with
   a tolerant-reader default for exactly this reason.
3. **Never reorder turn phases as a tuning lever** — sequencing is a correctness
   contract (`cnc-turn-pipeline-reference`).
4. **Never weaken an assertion to make evidence green** — the 4 standing e2e failures
   are the problem statement, not noise.
5. **Never route around this skill** — including "temporary" local edits for testing
   that leak into commits. If you must experiment, do it on a branch and label the
   commit `experiment:`.

## When NOT to use this skill
- HOW to find the right value → `cnc-balance-campaign` (sweeps) + `cnc-sim-analysis-toolkit` (predict first)
- WHAT a constant means mechanically → `cnc-economy-reference`
- Adding content at conventional defaults → `cnc-content-pipeline`

## Provenance and maintenance
Compiled 2026-07-05 (owner ruling same day). Re-verify:
- Constant names/values: `grep -n "PRICE_IMPACT_\|LABOUR_OUTPUT_\|TAX_RATE\|LOAN_" price-of-everything-0.1/scripts/economy_config.gd`
- Standing e2e failures: run the harness (`cnc-validation-and-qa` Leg 2).
- Legacy glut caveat: `grep -rn "price_impact_pct_for" price-of-everything-0.1/scripts/ price-of-everything-0.1/tests/`
