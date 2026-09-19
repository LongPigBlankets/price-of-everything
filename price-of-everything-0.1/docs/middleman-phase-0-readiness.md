# Middleman phase 0: readiness and completion record

Historical phase-0 record. [Phase 1 is now implemented and separately validated](middleman-phase-1-implementation.md).

Phase-0 contract and baseline work is implemented. See the [implementation contract](middleman-phase-0-contract.md) for the confirmed rules, ownership and turn sequence, preserved evidence, limitations and phase-1 integration acceptance matrix.

The user confirmed ordinary market goods prices, cash plus explicitly drawn permitted credit (never anticipated sales), complete-batch acquisition and reuse of paid private inputs after unexpected production failure. The executable helpers freeze these decisions without changing live production.

The first live fixture remains Pepper Valley Motors on tile_5_4: 32 steel + 32 copper wiring + 30 grid power → 33 motors, using the dynamic 0.5% tariff with location coefficient 1.5. The inclusive fee covers provider transport and storage. Buildings trade independently.

Phase 0 supplies pure quote/budget tests, reference cash/goods traces, baseline hashes and replay tooling. Actual middleman settlement, SaveLoad integration and a playable start are phase 1. Existing legacy save migration and round-trip tests remain part of the full gate; the proposed private holding fixture is not a complete game save.

Validation passed: **4,168 checks, zero failures**, plus unchanged road, three-owned-rail and five-factory gameplay baseline replays. The initial restricted run could not write two existing map fixtures; rerunning with access to Godot’s test-save directory passed. Validation is recorded in [the full gate report](../reports/balance/middleman_phase0_full_gate_2026-09-19.json). No logistics hub implementation or further recipe/price balancing is required before beginning phase 1.
