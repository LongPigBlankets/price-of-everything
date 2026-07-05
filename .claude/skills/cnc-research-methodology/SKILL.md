---
name: cnc-research-methodology
description: Load this when turning a hunch about price-of-everything into an accepted result - proposing a mechanism for a bug or balance effect, deciding whether evidence is sufficient, writing up findings, or working toward the project's research frontier (agentic balance methodology). Defines the evidence bar, the adversarial-refutation step, the idea lifecycle, and the falsifiable frontier milestone.
---

# Research methodology — from hunch to accepted result

## The evidence bar

A claim is accepted here when **one mechanism explains ALL observations — including
the negatives — and survives an assigned adversarial refutation pass.**

Why the adversarial step is mandatory: in the July 2026 audit, two findings labeled
CRITICAL (an L3 input-scaling duplication exploit and a market top-up under-order)
were *plausible, internally consistent, and wrong* — both died in minutes when the
`_scaled_input_qty` call sites were actually read. Confident narratives are cheap;
this project pays only for narratives that survived an attempt to kill them.

Refutation pass, concretely: a second look (another agent, or yourself in an explicit
"refute this" frame) whose ONLY goal is to break the claim — read the disconfirming
code path, construct the counterexample seed, check the negative cases the mechanism
must also explain. Default to "refuted" under uncertainty.

## The protocol (per idea)

1. **State the mechanism** — one sentence, causal, falsifiable.
2. **Predict numbers before running** — the template in
   `cnc-sim-analysis-toolkit` §4: metric, value ± tolerance, exact command + seed,
   and the observation that would kill it.
3. **Discriminating experiment** — smallest deterministic run separating your
   mechanism from rivals. One variable. Same seed for A/B.
   (Determinism is the whole superpower: `cnc-architecture-contract` rule 3.)
4. **Run and compare** — paste real output; "roughly matched" is a miss unless the
   tolerance said so in advance.
5. **Adversarial refutation** — as above. Survives → proceed; dies → record it.
6. **Adopt or retire**:
   - Adopt: route the change through `cnc-balance-change-control` (numbers) or normal
     review (code), with the evidence attached.
   - Retire: append the dead idea to `cnc-failure-archaeology` (symptom → mechanism →
     evidence → status DEAD). Retired ideas are a deliverable — they save the next
     person a week.

## Idea lifecycle

HUNCH → MECHANISM (written, falsifiable) → PREDICTION (numbers filed) → EXPERIMENT
(seeded, minimal) → REFUTATION PASS → ADOPTED (change-control) | RETIRED (archaeology).
Exit criteria at each arrow; no stage may be skipped for "obvious" ideas — the audit
false-positives were obvious too.

Where good ideas have historically come from, in rough yield order: the audit's
systematic sweep (dozens of confirmed findings); e2e metric anomalies (slow-turn
digests, profitability curves); git archaeology (the roads and prewarm sagas produced
their own fixes); playtest friction reports (screenshots with garbage numbers found
the INF-sentinel class); wiring-what-the-UI-promises (labour output pressure came
from a UI promise the sim didn't keep).

## The research frontier (owner ruling, 2026-07-05)

**Claim under development — NOT yet achieved:** *agentic balance methodology* — that a
deterministic, headless, fully-scripted economy sim + strategy-archetype sweeps +
hypothesis-predicts-numbers discipline lets AI agents balance an economy game to a
measurable standard, cheaper and more reproducibly than manual playtesting.

Why current practice fails: studio balance is playtest-anecdote-driven,
non-reproducible, and doesn't scale to combinatorial strategy spaces. This project's
specific assets: hard determinism (seeded, save-stable), a real headless harness with
committed baselines, a turn profiler, and change-control that forces evidence.

**What must be true before claiming ANYTHING publicly:**
- Sweep configs, seeds, and results committed (`docs/sweeps/`), re-runnable by a
  stranger from a fresh clone;
- Baselines versioned; negative results reported alongside wins;
- The method demonstrated end-to-end at least once (below).

**First three concrete steps in this repo** (= `cnc-balance-campaign` Phase 1–2):
1. Commit the sweep runner (`tests/sweep_runner.gd` + driver).
2. Commit ≥6 strategy archetypes as data (`tests/strategies/*.json`).
3. Commit the first 10×10 sweep matrix + a one-page reading of it (`docs/sweeps/`).

**Falsifiable milestone — "you have a result when":** a tuning change *predicted by
the method* (mechanism + numeric prediction filed before the run) flips the 4 standing
e2e profitability failures green across ≥80% of sweep seeds **without weakening any
assertion**, and the before/after matrix shows no new dominant archetype (>60% win
rate). Until that event, the frontier is a candidate, and all write-ups say so.

## House rules for write-ups

Findings live in `docs/` (or the commit message for small results): mechanism,
prediction, command+seed, observed, refutation notes, decision. No oversell — "open",
"candidate", "confirmed (N seeds)" are the only strength labels. Anything that changes
behavior cites its change-control note.

## When NOT to use this skill
- Executing the sweeps themselves → `cnc-balance-campaign`
- The math for predictions → `cnc-sim-analysis-toolkit`
- Quick bug triage (no research question) → `cnc-debugging-playbook`

## Provenance and maintenance
Compiled 2026-07-05; frontier definition is the owner's ruling of the same date.
- The false-positive story: see `cnc-failure-archaeology` §Tooling/process.
- Milestone inputs (the 4 standing failures): `cnc-validation-and-qa` Leg 2.
- Check whether the frontier milestone has since been met: `ls price-of-everything-0.1/docs/sweeps/ 2>/dev/null` and read the latest entry before repeating any claim here.
