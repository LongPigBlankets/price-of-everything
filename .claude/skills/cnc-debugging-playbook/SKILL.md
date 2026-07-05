---
name: cnc-debugging-playbook
description: Load this FIRST when something is wrong at runtime in price-of-everything and the cause is unknown - a building not producing, wrong prices, stuck construction, weird numbers, stale panels, goods not arriving, flaky test results. Symptom-to-triage table with the discriminating check for each of this project's known failure modes, plus the debug terminal and the discriminating-experiment discipline.
---

# Debugging playbook — symptom → first check → likely cause

Discipline first: **one hypothesis, one discriminating experiment, predicted
observation written down BEFORE running.** The sim is deterministic — the same seed
reproduces anything; use that. If a symptom matches a row below, run its check before
inventing theories.

## Triage table

| Symptom | First discriminating check | Likely cause(s) → where |
|---|---|---|
| Building never produces | `Production.blocked_reason_by_building[iid]` and `missing_by_building[iid]` (debug terminal or a test print); RAG dots in its panel | inputs missing (same-turn buffer lag is NORMAL for co-located chains — see the worked trace in `cnc-turn-pipeline-reference`); no cables / power cap; deposit missing or depleted (`MatchState.deposit_depleted`) |
| Construction stuck "awaiting materials" | does `construction_projects[iid].missing_materials` shrink after a turn? any shipment with `construction_instance_id == iid` inbound? | historic foreign-inbound bug is FIXED (`cnc-failure-archaeology`); remaining causes: can't afford (queue_buy clamps to cash — self-heals when funded); fluid material with no pipe route |
| Goods bought but never arrive | find the shipment in `MatchState.pending_transport_shipments` — check `destination_tile`, `turns_remaining` | destination full (overflow held + retried — check `get_overflow_shipments_for_tile`); wrong destination; fluid mis-route |
| Price looks wrong | split base vs effective: `MarketState.get_base_price_now(g)` vs `get_price(g)`; `MarketState.impact_pct.get(g)` | monotonic decay is DESIGN; nonzero impact = your own volume (thresholds in the market tab column); double-check against `data/Goods - goodsMVP.csv` decay_rate |
| Gigantic number anywhere (1073741824, ~1e9 costs) | is it `1 << 30`? | the `INF_TURNS` unreachable-route sentinel leaked — the consumer must check `reachable` (`TransportService.route_is_reachable`) |
| `Â£` in any label | `grep -rn "Â" price-of-everything-0.1/scripts/` | double-encoded literal — fix the string |
| Fluid good won't sell/move | `Catalog.requires_pipeline(gid)`; class via `get_transport_class` — hazard_liquid needs `reinf_pipes`, others `pipes` | no pipe route (the TVP toasts this; other paths may fail silently — audit D1 residue) |
| Loaded save behaves oddly for ONE turn then normalizes | expected for intermittency derates (not saved — audit D2, open) | see `cnc-save-and-migration` §open items |
| State missing after load | is it in the deliberately-NOT-saved table? | `cnc-save-and-migration` — camera/mapmode/panel state resets by design |
| Panel shows stale data until reopened | does the panel implement the coalescing pattern? was `_dirty` set but visibility catch-up missing? | `cnc-ui-and-theming` refresh doctrine — check `_on_visibility_changed` re-queues |
| Clicking a panel selects the tile under it | is the panel root `mouse_filter = STOP`? | press leaked through the panel (the release-side arm is global — `hex_map._click_armed`) |
| Tests pass, game visibly broken | is it data? run the content survival check | data integrity is a suite blind spot (`cnc-validation-and-qa` §blind spots): promotion-gate drops, dead research conditions |
| Same seed, different outcomes | `grep -rn "randi()\|randf()" price-of-everything-0.1/scripts/ | grep -v _rng` — any hit outside the visual whitelist? new dict-order dependence? frame-time dependence? | determinism break — treat as release-blocking (`cnc-architecture-contract` rule 3) |
| Turn suddenly slow | read the newest rows of `user://turn_profile.csv` — which column jumped? | `cnc-performance-playbook` Phase 2 gates |
| Research never unlocks | is the node's condition action one of the 5 handled ones, and its object an internal_name/good id? | 95/231 nodes have dead conditions (open) — `cnc-content-pipeline` §tech-gating |
| Recipe/building absent from menus | promotion-gate survival check | `cnc-content-pipeline` |
| Camera pan/tween "doesn't work" in a tool | is edge-pan disabled? did you pan before ~frame 140? | `cnc-validation-and-qa` §shot tools |

## The debug terminal

`scripts/debug_terminal.gd` — in-game console (backtick). Commands worth knowing
(verify the current set with `grep -n "match parts\[0\]\|\"help\"" scripts/debug_terminal.gd`
— it drifts): `save <slot>` / `load <slot>`; money/cheat commands; `anim` (empire-view
background modes); `toggle heightmap` / `toggle roads` (⚠️ `roads_visible` is a static
that survives scene changes — toggling then starting a new game leaves roads hidden;
known quirk); loyalty cheat via `MatchState.cheat_set_loyalty`.

## Reproducing headlessly

Fastest loop for sim bugs — drive phases directly in a scratch test or tool:
```gdscript
TurnManager.fast_mode = true
TurnManager.phase_started.emit(TurnManager.Phase.PROCESS)   # supported contract
# assert on Stockpile/MatchState/Production state
```
Seed exact scenarios with `MatchState.add_building(...)`, `Stockpile.add(...)`,
`MatchState.recruited_advisor_ids.append(...)` etc. — see existing `tools/*_shot.gd`
and `tests/e2e_stoneshore.gd` for canonical setup calls. For anything you fix, land a
regression test named after the story (`cnc-validation-and-qa` §adding a test).

## Escalation order

1. This table → the linked skill.
2. `cnc-failure-archaeology` — has this battle been fought?
3. The audit doc (`docs/mechanics_audit_2026-07.md`) — is it a known-open item?
4. Only then: novel investigation, with the discriminating-experiment discipline and a
   new archaeology entry when settled.

## When NOT to use this skill
- You already know the subsystem → its reference skill directly
- Designing a fix that changes behavior/numbers → `cnc-balance-change-control`
- Post-fix write-up → append to `cnc-failure-archaeology`

## Provenance and maintenance
Compiled 2026-07-05. The table rows each trace to a real incident or audit finding.
- Terminal commands drift: re-read `scripts/debug_terminal.gd`.
- Blocked-reason fields: `grep -n "blocked_reason_by_building\|missing_by_building" price-of-everything-0.1/scripts/production.gd`
- Sentinel: `grep -n "INF_TURNS" price-of-everything-0.1/scripts/transport_service.gd`
