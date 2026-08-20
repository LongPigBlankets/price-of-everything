# Demo Roadmap — ship Sunday 23 Aug

Goal: a 100-turn demo where victory is fairly achievable, building costs actually
constrain expansion, and the money system is legible. Nothing here is implemented
yet — this is the plan of record for the sprint. Priority marks (P1/P2/P3) are the
owner's; unmarked items carry a suggested slot.

## A. Balance & structure

1. **P1 — Triple production-building cost, not infra.**
   Lever: `build_cost_money` in the buildings CSV, parsed at `catalog.gd:1081`
   (`base_price`). Cleanest reversible implementation: a category multiplier at
   catalog load keyed off `building_type`, skipping infra rows — one place to tune,
   no CSV churn.
   **Telemetry caveat:** the playtester financed everything on the 48-turn spread —
   the 4-rails purchase at turn 79 shows *zero* visible cash impact — so a 3×
   sticker price becomes 3× buried installments unless the spread is capped or
   priced. Pair the cost change with a shorter default spread (12) and/or interest
   on the 48-turn option. This change invalidates all prior balance intuition:
   schedule a full playtest run after it lands.
2. **P2 — Tutorial ends at turn 100, same as demo.** One turn-cap value for both;
   tutorial flows into demo pacing.
3. **P3 — Shortened demo structure** (100-turn arc).
4. **Victory conditions scaled down for the 100-turn demo** (owner) + **victory
   screen** — `victory_panel.gd` exists; wire and polish.
   Pre-release check: confirm victory tracks report non-zero to telemetry — the
   v0.4 sheet showed `0|0|0|0|0` for an entire 118-turn run (bug or unwired).
5. **P2 — Glass start?** `data/starts/glass_merchant.json` already in the tree.
   Playtest evidence for it: the metal start was much easier than the tutorial's
   windows start, and windows taught intermediates well; glass sits between.

## B. Map & art

6. **P3 — Add trees & rework forests.**
7. **Decorative buildings appear over time** — half present at turn 1, the rest
   trickle in at 1 per 4 turns (half per tile).
8. **Finish Stoneshore + Arin building layout; lock map to western half** (maybe
   top-left) — mostly done in current build; verify + lock.
9. **Remaining Blender sprites (13):** electrolyser, chem plant, water pump, wind
   farm, solar farm, battery, oil well, shale oil well, oil platform, assembly
   plant, high-tech manufactory, farm, forest. (FILM_RUNBOOK pipeline.)
10. **3–4 missing goods icons.**
11. **Loading screen optimisation — cut candidate.** "Maybe not necessary if using
    texture"; the real fix is the P4 vector-fabric bake (post-demo,
    `docs/p4-bake-scope.md`).

## C. UI surfaces

12. **Top bar foldout: goods in transit / transport surface.** Also the fix for
    the playtester's #1 confusion (money jumping) and her "why did I get 2,500?"
    moment: revenue books only when sale shipments *arrive* (`production.gd:936`
    pays out "locked-in revenue" at the port), so cash swings are time-shifted
    from their causes. The £ value is already stored on each in-flight shipment —
    this is UI work only. Show "£X of sales arriving" alongside the goods count.
13. **Resource panel: produced / sold / used columns + good icon, centre the
    panel.** `resource_panel.gd`; sold and consumed quantities already exist in
    `Production.last_turn_summary`.
14. **Controls — "a handful of things."** Needs the owner's list before it can be
    scheduled.

## D. Playtest feedback → fixes (documented only; anchors from the codebase)

In Sunday scope (obvious or near-obvious fixes):

| Feedback | Fix | Where | Effort |
|---|---|---|---|
| Toasts too short-lived | Raise `TOAST_DURATION` (currently 4.0 s); consider per-type durations and hover-to-pause. Money-critical notices (auto-bridge loan) should persist, not toast. | `toast_manager.gd:10` | one-liner |
| Encyclopedia button should open with search ready to type | Focus-on-open already exists (`open_search()` → `_focus_search_input`); route the button path through it / find where it diverges. | `search_overlay.gd:71` | small |
| Wants to search game *concepts* | Concept entries already exist inline (transport, port terms). Add entries: storage, power market, upgrades, research tiers, cost spreading. Data writing, no new system. | `search_overlay.gd:185` | small |
| Research tier colours confusing ("expected all tiers to go red like tier 1") | Unify rank-stamp colour semantics across tiers. | `research_panel.gd:1252` (`_rank_stamp_color`) | small |
| Power deficit noticed but ignored until it cost money | Append the live cost to the existing top-bar surface: "importing power −£X/turn" (`power_purchase_cost` already in the turn summary), amber tint. | `top_bar.gd` | small |
| Offshore oil has weird unlock conditions | Data edit to prerequisites. | `data/research_unlocks.csv` | small |
| Upgrade-to-L2 research rabbit hole | "View blocking research" button on locked upgrades → open research panel scrolled to the node + flash it (needs a small focus-node API in `research_panel.gd`); shorten the panel. Highest-value UX item on the list. | `building_detail_panel_v2.gd`, `upgrade_dialog.gd` | medium |
| Money keeps jumping up and down / sudden +2,500 | Root cause documented: batched shipment-arrival revenue + silent auto-bridge loan (`solvency_state.gd:91`) + same-turn tax/dividend skim. Fixed by item 12's foldout + a persistent auto-bridge notice. | — | via item 12 |
| Overflowing scroll on the panels | Sweep pass over panel scroll containers (recurring complaint). | panels | medium, partial |

If time remains:

| Feedback | Fix | Where | Effort |
|---|---|---|---|
| Click a good in the encyclopedia → goods graph (maybe right-click) | Click-through from search results to the goods graph focused on that good. | `goods_graph_view.gd` | medium |
| Goods graph too busy when unfocused | Hide edges in the unfocused view. | `goods_graph_view.gd` | small-medium |

Post-demo (real findings, not Sunday work):

- **Replacement advisor after Keeler left** — she wanted to hire one; the flow
  doesn't exist. (Positive signal: the advisor hook works.)
- **Storage pain / never opened empire view** — resource-panel columns cover the
  visibility half; empire-view onboarding later.
- **"Easy until turn 120"** — addressed by the P1 cost change + victory scaling.
  Telemetry showed the real story: structurally lossmaking from ~turn 90, masked
  by shipment-batch windfalls and silent auto-bridge loans.
- **Triggered financing dialog** (spread the big bill over 12 interest-free /
  48 default / pay now and loan only the negative portion) — converts the hidden
  auto-bridge into a visible decision. Design agreed 20 Aug; build post-demo.

## E. Suggested order

- **Thu:** P1 cost change + spread cap decision; turn cap 100 for tutorial+demo;
  one-liner fixes (toast duration, power cost line, offshore CSV). Start a full
  playtest at 3× prices.
- **Fri:** Victory scaling + victory screen; glass-start decision; top-bar
  foldout; resource-panel columns; sprite batch 1.
- **Sat:** Sprite batch 2 + goods icons; trees/forests; decorative-building
  trickle; map lock; upgrade→research deep-link; scroll sweep; encyclopedia
  routing + concept entries.
- **Sun:** Full 100-turn playthrough; telemetry check (victory column non-zero,
  schema v3 rows arriving); fix; ship.

Balance lands first because everything downstream needs testing at the new
prices; art parallelises across all three days.

## Pre-release checklist

- [ ] Full 100-turn run at new prices — no bankruptcy-by-design inside 20 turns
- [ ] At least one victory track meaningfully progressed in the test run
- [ ] Victory telemetry non-zero (v0.4 regression)
- [ ] Demo build boots clean; load time acceptable without the P4 bake
