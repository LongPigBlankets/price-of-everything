---
name: cnc-turn-pipeline-reference
description: Load this when working on anything that happens "during a turn" in price-of-everything - production, arrivals, construction, selling, costs, events, price ticks - or when debugging apparent ordering bugs (goods arriving too late, sales missing a turn, modifiers lasting the wrong number of turns), or when writing tests that drive turns. The canonical turn-resolution order, its invariants, and a worked one-turn trace.
---

# Turn pipeline reference — the canonical order

Verified against `scripts/turn_manager.gd` and `scripts/production.gd` (2026-07-05).
Sequencing IS the spec: many "bugs" juniors see are correct ordering. **Never reorder
a phase to fix a symptom** — trace it through this document first.

## Top level (`turn_manager.gd`)

```
DECIDE (player acts) ──commit_turn()──▶ PROCESS → SEND → AI → NARRATIVE → RECEIVE
                                          └── then: current_turn += 1
                                              turn_advanced.emit()   ← market tick etc.
                                              back to DECIDE
```
- `_RESOLUTION_PHASES = [PROCESS, SEND, AI, NARRATIVE, RECEIVE]`; AI is a defined-but-
  empty placeholder. Each phase emits `phase_started`, is profiled by `TurnProfiler`,
  then pauses `phase_pause_duration` (skipped in `fast_mode`).
- `is_resolving` guards re-entry, saving (DECIDE-only) and loading (refused mid-
  resolution — a suspended resolution coroutine would otherwise resume over the loaded
  state; this was a real corruption bug, fixed 2026-07).
- **Listener order is explicit**: `TurnManager._wire_sim_listeners()` connects
  `phase_started` in this fixed order — do not add sim listeners any other way:
  1. `MatchState._on_survey_phase_started` — PROCESS: labour-pressure tick, survey
     ticks, battery fills (firming capacity must exist before production);
     NARRATIVE: `_check_unlock_conditions()` (after production settled).
  2. `Production._on_phase_started` — PROCESS: the big `_process_production()`.
  3. `EventScheduler._on_phase_started` — NARRATIVE: deterministic event tick.
  4. `Modifiers._on_phase_started` — NARRATIVE: prune expired modifiers.
- Tests/tools may drive phases by emitting `TurnManager.phase_started` directly —
  that's a supported contract (see `tests/test_runner.gd`, `tools/ledger_shot.gd`).

## PROCESS sub-phases (in `production.gd`, in this exact order)

The `TurnProfiler.section_begin(...)` names are the authoritative list:

| # | Section | What happens | Why here |
|---|---|---|---|
| 1 | `power_reset` | per-turn power tallies cleared | power is same-turn generate/consume |
| 2 | `transport_arrivals` | congestion snapshot; overflow retry; shipments with `turns_remaining==0` land in stockpiles (sales pay out via `_credit_arrived_sale`) | goods must land BEFORE anything consumes/claims |
| 3 | `construction` | `Construction.tick_turn()` (countdowns; completions promote and can produce THIS turn) → `claim_materials()` (projects consume off the tile before production can) → `reorder_market_materials()` (re-buys shortfalls, counting ONLY own-tagged freight) → `MatchState.tick_upgrades()` → retrofits | tick before claim so a just-started build isn't double-ticked; claim before production so builds own their goods |
| 4 | `production_passes` | the cascade: repeatedly run every not-yet-run building whose inputs/power/deposit checks pass (≤ `MAX_PRODUCTION_PASSES` 30). Same-turn outputs are BUFFERED and merged after all passes — co-located buildings can't consume goods made this turn | fairness: iteration order confers no advantage |
| 5 | `starvation_report` | blocked reasons recorded (`blocked_reason_by_building`) | after all passes, so "starved" is final |
| 6 | `grid_settlement` | net power vs grid at GRID_BUY/SELL_PRICE (advisor mults) | after all producers/consumers ran |
| 7 | `flush_outputs` | buffered same-turn outputs land in stockpiles | see #4 |
| 8 | `recurring_moves` | standing tile→tile transfers ship | after outputs exist |
| 9 | `buy_market_inputs` | market-routed inputs topped up to (lead+1)×demand, tile-aggregated, construction-tagged freight EXCLUDED from pipeline stock | after moves, before selling |
| 10 | `sell_phase` | queued sells + bulk sells + AUTO-SELL (surplus above `compute_committed_for_tile` minus keep-X floors, capped by the tile's impact tolerance) | LAST goods movement: only true surplus sells |
| 11 | `maintenance_labour` | per-building maintenance + labour (additive factor, 0.40 floor), advisor payroll, seaport fees | costs after operations |
| 12 | `loan_payments` | amortized payments (booked to summary; see audit H3 caveat) | before tax |
| 13 | `tax_dividends` | `TAX_RATE` on max(0, in−out); dividends; profit sharing; loan-capacity feed | after all cash flows |
| 14 | `cost_solve` | Leontief imputed costs over the recipe DAG → RAG | needs the turn's actuals |
| 15 | `emit_summary` | `turn_processed(summary)` → UI/metrics | last: the summary is final |

## What rides `turn_advanced` (AFTER all phases)

`MarketState.tick_turn()` — base-price decay THEN the price-impact fold (this turn's
recorded volumes move `impact_pct`); `SpecialOrderState.advance_turn` (spawns/expiry —
expiry uses `expires_turn < turn`, so deadline-turn arrivals count); victory tick.

## Modifier timing rule (subtle, tested)

`duration_turns` counts **PROCESS applications**: granted in/before PROCESS of turn T
(DECIDE picks) → `expires_turn = T + dur − 1`; granted in NARRATIVE (condition unlocks)
→ `T + dur`. Both live exactly `dur` applications. Pruning runs in NARRATIVE. Tests:
`_test_modifiers_expiry`.

## Worked trace — one turn, mine + furnace on one tile

Setup: tile T has a Coal Mine (deposit ok, powered) and a Furnace (needs coal+iron_ore;
iron_ore stocked; coal stock 0). Player ends turn.

1. `transport_arrivals`: nothing inbound. 2. `construction`: none.
3. `production_passes`, pass 1: Mine runs (deposit + cables checks pass), its 60 coal
   goes to the **same-turn buffer**, not the tile. Furnace check: coal on tile = 0 →
   blocked, retried next pass. Pass 2..N: Furnace still sees 0 coal (buffer is
   invisible by design) → after the passes, Furnace is starved THIS turn.
4. `starvation_report`: Furnace recorded starved(coal). 7. `flush_outputs`: 60 coal
   lands on T. 10. `sell_phase`: if T has auto-sell on, coal above the Furnace's
   committed need sells; committed demand protects next turn's inputs.
11-13. maintenance/labour for both buildings; tax on the turn's net.
Next turn, pass 1: Furnace runs (coal now on tile). **This one-turn lag is correct
behavior**, not a bug — it's the same-turn-buffer fairness rule. (In-game, the RAG
"input" dot and `Production.missing_by_building` show it.)

## When NOT to use this skill
- What the formulas inside a phase compute → `cnc-economy-reference`
- Whether reordering/behavior change is allowed → `cnc-architecture-contract` + `cnc-balance-change-control`
- A building not producing and you don't know why → `cnc-debugging-playbook`

## Provenance and maintenance
Verified 2026-07-05 against turn_manager.gd + production.gd section markers.
- Re-derive the sub-phase list: `grep -n "section_begin(" price-of-everything-0.1/scripts/production.gd`
- Re-check wiring order: `grep -n -A8 "_wire_sim_listeners" price-of-everything-0.1/scripts/turn_manager.gd`
- Modifier rule: `grep -n -B2 -A6 "duration_turns convenience" price-of-everything-0.1/scripts/modifier_state.gd`
