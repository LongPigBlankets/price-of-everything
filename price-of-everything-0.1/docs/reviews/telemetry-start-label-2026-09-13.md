# Telemetry start labels

Capture the start as soon as a start/save imports, with match_loaded as a further lifecycle hook. Persist it in the optional telemetry.start save field and restore it before any interaction or completed turn is needed. Older saves recover from the already-loaded MatchState.scenario_name. The value remains latched through teardown, and an actually unknown legacy scenario remains unknown rather than being classified as Glass Merchant.

The external envelope still uses run.start. Code.gs already stores that field; neither the external schema nor receiver code changed. No Apps Script deployment is required. The fix requires a rebuilt client; existing historical blank entries are not automatically changed.

Validation: parse sweep passes; full unit suite and 100-turn E2E pass. New tests cover all three starts exiting without turns/events, teardown before finalization, save/resume/immediate exit, legacy fallback and avoiding cross-run label leakage. The existing receiver mock accepts all three labels with no turn rows. All checks ran locally without uploading telemetry.

Evidence: outputs/telemetry-start-label-2026-09-13/. No game exports rebuilt.
