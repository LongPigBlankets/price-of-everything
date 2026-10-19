# Save validation

`scripts/save_validation.gd` is the boundary before saved data reaches subsystem
imports. `SaveLoad.load_slot()` validates the raw JSON before normalization or
migration, then validates the migrated snapshot against the current demo policy.
`import_snapshot()` validates again before resetting the live match. Rejected input
returns a readable error and leaves the live simulation unchanged.

The limits are 64 MiB per file, 32 nesting levels, one million values, 100,000 entries
per collection and 64 KiB per string. Values must have supported types and finite
numbers. Nested subsystem containers, records, histories, road geometry and endpoints,
building levels/recipes, inventory quantities and catalog references are checked.
The slot browser also skips malformed metadata and oversized files.

Demo loads accept the two shipped starts and legacy default/tutorial saves, Normal
difficulty and 100-turn rules. Gated buildings/goods and unavailable advisors are
rejected. Compatible legacy demo saves receive the current turn/difficulty defaults,
full tile visibility and the current advisor-capacity limit. These checks protect the
load contract; they do not authenticate a save or prevent a modified client.

Missing additive fields remain valid. The simulation format remains version 17;
existing stepwise migrations still run. Trusted in-memory start snapshots may omit
subsystems and use the existing native coordinate values.

When changing a saved field:

1. Update its owner's export/import/reset contract.
2. Update the explicit `FIELDS` table or nested record check in the validator.
3. Test a current round trip, a missing-field/legacy load, and a malformed record.
4. Assert rejected input leaves `SaveLoad.export_snapshot()` unchanged.

Coverage lives in `tests/unit/test_save_validation.gd` alongside the existing
save/load migration and round-trip tests. Run the focused checks with
`python3 tools/run_tests.py --test _test_save_validation_`, then run the full suite
for import-contract changes.
No rendering or production bake inputs are changed by this validator.
