---
name: cnc-failure-archaeology
description: Load this before starting ANY investigation in price-of-everything, when a symptom feels familiar, when tempted to try an approach that might have been tried, or when writing a postmortem. The chronicle of every major investigation, dead end, rejected approach and revert - symptom, root cause, evidence, status - so nobody re-fights a settled battle.
---

# Failure archaeology — settled battles

Format: **symptom → root cause → evidence → status**. Statuses: FIXED (don't re-fix),
OPEN (known, don't re-discover), DROPPED-BY-DESIGN (don't re-build). Before any deep
investigation, scan this file AND the audit
(`price-of-everything-0.1/docs/mechanics_audit_2026-07.md`).

## Sim correctness

**Construction hangs forever awaiting materials** → `reorder_market_materials` counted
ANY inbound shipment of a missing good against its shortfall — including a co-located
production building's imports — while production's pipeline correctly EXCLUDED
construction-tagged freight; result: builds sharing an input with a neighbour never
ordered their own copy → commit `06fec41`; regression test
`_test_construction_reorder_ignores_foreign_inbound` → **FIXED**. Lesson: when two
systems share a resource stream, their mutual-exclusion accounting must be symmetric.

**Loaded save starts one phantom turn ahead / corrupted per-turn state** → loading
mid-resolution let TurnManager's suspended coroutine resume over the imported snapshot
→ `load_slot` guard + UI lockouts, commit `15f6ba7` → **FIXED**.

**DECIDE-granted timed modifiers lasted one turn longer than NARRATIVE-granted** →
`expires_turn = T + dur` regardless of grant phase, pruning in NARRATIVE →
`cb63acc`; durations now count PROCESS applications; tests updated → **FIXED**.

**Farm buildable but does nothing (class of bug)** → catalog promotion gate silently
drops recipes whose goods are missing; the building stays listed → historic farm fix +
regression tests → farm **FIXED**, but the same state is **OPEN today** for
`consumer_factory`, `old_forest`, `landfill`, `ruins`. Survival check lives in
`cnc-content-pipeline`.

**"1073741824 turns", astronomical transport costs in UI** → unreachable fluid routes
return the `INF_TURNS` (1<<30) sentinel; a display path rendered it raw → `60a9863`
(route_summary now reports `reachable`, panel prints "— no route —") → **FIXED**;
sentinel remains — any NEW route consumer must check `reachable`.

**Silent economy exploits** (special-order arbitrage; loan-principal tax shield; free
manual freight; negative money forever) → audit 2026-07, all confirmed in code →
**OPEN**, catalogued in `cnc-architecture-contract` §weak-points. Sweeps will
rediscover them — cross-reference, don't re-investigate.

## UI / input

**Clicking a panel ALSO selected the tile underneath** → tile-select was moved to
mouse-RELEASE (for drag-to-pan), but UI consumes the press and often leaks the release
→ `06fec41`: `hex_map._click_armed` requires the press to have reached the map →
**FIXED**. Lesson: press/release asymmetry is real in Godot's GUI-vs-unhandled routing.

**Panels rebuilt hundreds of times per turn** → per-emission rebuilds on
money_changed/stockpile_changed → `164b8ea`+ follow-ups: coalesced deferred refresh
everywhere (doctrine in `cnc-ui-and-theming`) → **FIXED** (doctrine; regressions likely
if pattern ignored).

**Card content clipped, CTA half-visible** → Buttons don't size to child containers →
`_ClickCard` PanelContainer pattern → **FIXED** (pattern).

**"Â£10"** → double-encoded £ in `_money_text` → `60a9863` → **FIXED**; grep guard in
`cnc-godot-discipline`.

**NPC frost bleeding onto the next building; ledger rows doubling; power RAG yellow on
own grid supply** → per-panel state not reset between renders / duplicated children /
mis-attributed source → commits `7316ec2`, `2381878`, `553afc4` → **FIXED**. Pattern:
panel caches must be cleared per `show_*` call.

## Tooling / process

**e2e harness silently rotted to 86 failing assertions** → it is not part of
run_tests.py, so nothing ran it → `674e4dc` restored it → **FIXED**, and the standing
rule is Leg 2 of `cnc-validation-and-qa`. The 4 CURRENT failures are deliberate
scoreboard, not rot — know the difference (exact list in that skill).

**Scripted screenshots: camera pans get cancelled / land at map centre** → in windowed
scripted runs the mouse idles at the window corner → edge-pan fires every frame,
killing tweens; ALSO panning before ~frame 140 is overridden by the post-load camera
configure → shot tools set `edge_pan_enabled = false` and settle first → **FIXED**
(pattern in `cnc-validation-and-qa`).

**Headless tests: "Identifier not found: <ClassName>"** → `class_name` registry isn't
built in fresh headless runs → preload pattern → **FIXED** (rule in
`cnc-godot-discipline`).

**Automated audit claimed two CRITICAL exploits that didn't exist** (L3 input-scaling
dupe; market top-up under-order) → the claims died on reading `_scaled_input_qty` call
sites → 2026-07 audit process → **SETTLED**: headline findings get verified against
code before action (`cnc-research-methodology`'s adversarial bar exists because of this).

## Performance / rendering sagas

**New-game freeze ~10s** → three separate causes (eager MarketPanel build; monolithic
hill triangulation; world_map._ready doing everything in one frame) → lazy panels +
chunked, cached triangulation + LoadPacing gate; **prewarm-on-menu was fully built and
then DROPPED** (`ff96d06→…→969fb42`) — the instantiation hitch was irreducible →
freeze → ~3.3s → **FIXED**; prewarm **DROPPED-BY-DESIGN, do not rebuild**.

**Max-zoom pan at ~1 fps** → THREE distinct culprits in one symptom (commit `09d8c6e`)
→ hill mesh caching + LOD → **FIXED**. Lesson: perf symptoms are frequently plural;
attribute each before fixing any.

**Roads v2 → v2.5 saga** (PRs #35/#36, many commits) → v1 roads replaced by baked
navgrid + hierarchical realizer; then a long visual-iteration tail: roundabout ovals
built (`e6cf38a`) then REMOVED (`b4f4284`); river tiles drew nothing (`a84d2b2` —
coarse-escalation + caps); river-hug routing; anti-parallel spacing → **SETTLED
ARCHITECTURE**: don't re-litigate road styling; extend via road_works' budgeted
pipeline. Road artifacts are currently irreversible (no removal path) — OPEN by
design; a demolish feature must add removal across network/occupancy/catalog together.

**Polygon-building footprints overflowed tiles and hid roads** (`2625d4d`) → fixed-size
no-overlap footprints planned up front (`109c785`) → **FIXED** (layout engine).

**Empire view melted GPUs/CPUs when open** → per-frame full lattice rebuild + O(n²)
card separation each frame → static-geometry cache, origin cap, reposition-on-change,
dynamic zoom floor (`164b8ea`) → **FIXED**.

## When NOT to use this skill
- Live triage of a NEW symptom → `cnc-debugging-playbook` (it links back here per row)
- The full open-issue catalogue → the audit doc + `cnc-architecture-contract`

## Provenance and maintenance
Compiled 2026-07-05 from git history (`git log --oneline --all`), the July 2026 audit,
and first-hand fixes. Every commit id above is real — verify any with
`git show --stat <id>`. When you settle a NEW battle, ADD IT HERE in the same format —
this file is append-mostly and is the project's institutional memory.
