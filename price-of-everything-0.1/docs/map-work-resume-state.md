# Resume state — map visual work

**Saved 2026-08-14 before a planned machine pause.** Everything below is committed to git
unless explicitly marked otherwise. Safe to sleep, reboot, or walk away.

## Where the work is

Owner's branch `decorative-buildings-and-city-look` — **untouched by every agent**, still
carrying your 26 uncommitted entries (`tools/market_model/`, `docs/future-market-dynamics.md`,
`tools/npc_market_dump.*`, the deleted `reports/balance/*.csv.import`, stray `*.gd.uid`).

Recent commits on it, all mine:

| Commit | What |
|---|---|
| `2f03a5b9` | Goods Graph focus-reset fix (repairs 2 tests that shipped without it) |
| `679c15c5` | Gauntlet II pass-1 results document |
| `2345b9cf` | Density/park/coast/port addendum — your visual feedback as gates |
| `2e90eec8` | Mass-form vocabulary spec — your 13 shapes |
| `bb53d1fd` | Density-neutrality lifted; your coverage ruling |

## Branch map

| Branch | State |
|---|---|
| `gauntlet3/integrated` | **Ports + coast merged and verified.** Rejected streams' postmortems preserved. Ready to merge when you choose. |
| `gauntlet3/density-audit` | The per-tile compliance instrument + frozen baseline |
| `gauntlet3/ports` | Straight arms, accepted |
| `gauntlet3/coast` | Coastal reach, accepted (blind critic 3.25 vs 2.58) |
| `gauntlet3/density`, `gauntlet3/parks` | Rejected + reverted; report postmortems only |
| `gauntlet4/form-geometry` | **13 form constructors, 165 asserts, 2,452 tests green** |
| `gauntlet4/form-adversarial` | 7,000+ hostile cases; limb thickness varies 8.7–24.0% CV; no form stamped |
| `gauntlet4/form-wiring` | Retired — built around the density-neutral rule you lifted |
| `gauntlet4/form-wiring-v2` | **ACTIVE.** Envelope-coverage + ≥10% margin instrument committed, 2,462 tests green. Rendering not yet rewired. |

## What was in flight when paused

The rewire (`gauntlet4/form-wiring-v2`) had built its measurement instrument and had **not
yet started changing rendering**. Nothing was half-written: every gauntlet4 worktree on the
main line reports a clean `git status`. The workflow was stopped deliberately, not crashed.

Uncommitted content in `/tmp/poe_g4_wt/{wirebase,probeA,probeB}` is Godot `.translation`
import churn plus two 1-line substitution-share probe tweaks whose measured results are
already recorded in commit messages. Nothing of value is lost if `/tmp` clears.

## Volatile vs durable

`/tmp` does not survive a reboot. Preserved into
`reports/map_visual_gauntlet/_durable_text/` (gitignored, but lives in the project dir):
`V0_HASHES.txt`, `gate_lists_v0.txt`, `unit_tests.log`, `density_audit_merged.{txt,json}`,
`density_audit_coastonly.txt`, `frontage.log`.

Deliberately **not** copied: ~310MB of baseline and evidence PNGs. The audit already proved
the v0 *pixels* are invalid as a baseline on this machine (captures are now 2360×1328, and
the morphology harness centre-crops rather than downsamples, so even its same-sized 960×480
PNGs crop a different world extent). Comparisons must use a **same-session control captured
from your own base commit**. The counters remain valid and are in git.

The five `/tmp/poe_g4_wt` worktrees are disposable — all their work is committed to
branches. If `/tmp` clears, run `git worktree prune` and recreate as needed.

## To resume

Rewire the vocabulary under the lifted coverage rule (spec section 5 of
`docs/map-mass-form-vocabulary.md`), branching from `gauntlet4/form-wiring-v2`:

1. Place all 13 forms into the decorative selection at rates visible at close zoom,
   **cores included** — the old wiring banished them from cores to protect a density
   budget that no longer exists.
2. Respect the coverage rule: top four components (Arin `tile_10_16`, Capital Port
   `tile_23_8`, Teganfort `tile_18_14`, Patran `tile_17_8`) uncapped; every other urban
   tile keeps ≥10% of its land outside the envelope — the instrument to measure this is
   already committed.
3. Never gain coverage by deleting parks; the ≥2 parks/urban tile floor stands.
4. Capture, stage a blind pair against a same-session control, critique blind, rule.

A fresh worktree needs `<godot> --headless --path . --import` or `class_name` symbols added
on a branch will not resolve — and without the import cache `run_tests.py` **exits 0 with no
tests run**, a silent false green. Always confirm a real `==== N passed, M failed ====` line.

## Open decision for you

The residual land between the port arms (2,352u², 95.6% of the inter-arm area is now water)
is bounded by the 12u NavGrid lattice, not the coastline. Close it either by building a
sub-lattice dry-land instrument, or by ruling that a visible foreshore is acceptable. It
must **not** be closed by loosening the existing dry-land gate — that is a goalpost move.
