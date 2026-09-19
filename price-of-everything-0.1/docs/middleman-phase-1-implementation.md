# Middleman phase 1 — funded operating loop

Implemented on `codex/transport-middleman-layer`, 19 September 2026. This is the first real middleman gameplay run, replacing the phase-0 evidence gap. The historical arithmetic/direct-route benchmark files remain unchanged.

## Implemented behavior

An explicitly opted-in Pepper Valley motor factory buys a complete affordable input basket into its own private holding, runs the ordinary recipe and power calculation once, then sells its actual output. No provider goods enter tile stock, consume warehouse capacity, create a route/shipment, or incur separate port, congestion or storage charges. Two outsourced factories on the same tile still trade independently. Direct factories and existing deliveries retain their normal paths.

The inclusive fee is `quantity × (0.005 × current market reference + class rate × 1.5)` for the authored Pepper Valley fixture: heavy solids £0.05, ultra-heavy £0.50. Buy/sale goods prices use the ordinary market APIs. The Money panel has one **Middleman fee (transport and storage)** component within its transport total; it is not an additional charge on top of that total.

Funding protects outstanding unpaid commitments, due debt payments, existing factory maintenance/labour and accepted batches' predicted grid expense. Provider allocation follows creation-counter order with instance-ID tie break. Only cash and actual permitted loan draws fund acquisition; expected sales never do. Loan proceeds reconcile to cash separately from operating revenue and taxes. The existing loan minimum and payment schedule apply.

Known infeasibility or insufficient funding buys nothing. Unexpected failure after acquisition retains the paid input goods and original purchase receipts. A later turn buys only missing inputs and does not charge again for retained goods. Blocked or negative-net sales retain one cycle of actual output and prevent further production until resolved. Recipe changes, upgrades, sale/removal and service disabling cannot discard private assets. An explicit release operation transfers the whole holding to owned stock only if it fits; it is not a refund.

The outer turn phases are unchanged. Explicit provider preparation runs after arrivals/construction and before the bounded production cascade; provider sales settle after that cascade. Normal physical replenishment still dispatches later, without an extra movement step. Provider inputs and outputs are excluded from shared/JIT reserves and stockpile forecasts. Actual market purchases and the inclusive fee feed the cost solver without treating same-tile factories as suppliers.

## Code and save ownership

- `scripts/middleman_contract.gd`: pure quotes and complete-batch funding plans.
- `scripts/middleman_service.gd`: explicit enable/disable, funding, private holdings, receipts, settlement and explicit asset release.
- `scripts/production.gd`: supply, private consumption/output and settlement hooks; existing recipe modifiers, power and costs remain authoritative.
- `MatchState.middleman_service`: schema-1 saved state with persistent match identity, immutable building identities, tariff/price snapshots, bounded holdings and receipts. Duplicate preparation/settlement cannot charge or sell again.
- Save version **12**: absent service state stays absent. Old saves, including old `middleman_v1` port-rate-only saves, do not auto-enable service. Saves still use the existing DECIDE-only boundary.

## Internal playable start and regression command

`data/starts/pepper_valley_motors_middleman.json` explicitly enables the service through a per-building `logistics_mode: middleman`. It is separate from the unchanged direct-route `pepper_valley_motors.json` start. Load it through `SaveLoad.prepare_new_game()`; the benchmark does this through the normal main scene. It is intentionally not added to the public New Game selector in this phase.

From the project directory:

```sh
python3 tools/run_middleman_phase0.py --phase1 --full
```

Validation: **4,214 checks passed, zero failures**. The gate runs the full unit suite, verifies preserved baseline hashes, replays the road/three-owned-rail/five-factory controls and runs 50 real provider turns. Existing map/save tests need access to Godot's temporary test-save directory. Reports: [full gate](../reports/balance/middleman_phase1_full_gate_2026-09-19.json), [live provider trace](../reports/balance/pepper_middleman_phase1_2026-09-19.json).

A separate funded parity check runs 50 turns headlessly and 50 in a minimized Godot window, starting with £300. Both draw the £20 minimum loan and produce identical cash/operating traces, including the turn-25 reload. Run `python3 tools/run_middleman_funding_parity.py` (requires window-server access). [Parity report](../reports/balance/middleman_phase1_funding_parity_2026-09-19.json).

`test_middleman_service.gd` covers independent live batches, cash reconciliation, duplicate supply/settlement, known preflight failure, unexpected failure and actual SaveLoad recovery, funding shortage, explicit minimum-loan funding, negative-net output retention/retry, private-asset disposition, old-save defaults and coexistence with ordinary arrivals/direct production. Existing full-suite tests additionally cover construction and the unchanged legacy production/power paths.

## Measured prototype result

The live 50-turn run freezes catalogue market prices and disables unrelated research, events and government road growth, matching the retained controls. A save/reload occurs after turn 25. Every turn produces and sells 33 motors without shared stock or provider shipments.

| Per-turn item | Amount |
| --- | ---: |
| Material purchases | £238.6944 |
| Gross motor sales | £364.4883 |
| Inclusive middleman fee | £32.5090815 |
| Factory costs, mean turns 40–49 | £70.56896246 |
| Operating contribution, mean turns 40–49 | **£22.71585604** |

The live result matches the frozen phase-0 reference. Turn-one contribution is £25.0181; the later reduction comes from existing wage progression. These are operating contributions before financing, taxes, dividends and capital expenditure, not closing-cash profit. No recipe, price or transport balance adjustment was needed in phase 1.

## Remaining scope

Eligibility is deliberately limited to the motor recipe on the authored Pepper Valley site (steel, copper wiring and motors). Other goods/cities, public onboarding and mode-selection controls remain later work. Building credit tabs, special-order service, arbitrary physical-pipeline conversion, construction-service redesign and logistics hubs are not supported by this prototype. General building status/source-selection and upcoming-cash previews still need their phase-2 service presentation; the settlement ledger and fee total are authoritative.

The hub's original operating inputs and selected road/rail capacity model remain documented separately in [the logistics hub design](logistics-hub-design.md).
