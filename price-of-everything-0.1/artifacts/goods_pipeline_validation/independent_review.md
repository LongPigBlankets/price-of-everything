# Complex-goods pipeline forward test

Scope: followed current build-review skill and pipeline README for a prospective EV icon, without modeling, internet access or repository edits. Initialized /tmp/ev-pipeline-forward-audit using the documented init command. Snapshot/proof control flow was exercised with clearly synthetic image fixtures, not passed off as Blender render validation; parent independently tests the actual render.

## What works

- Documented init succeeds from repository root. README paths include the price-of-everything-0.1 prefix correctly; all Markdown links tested in the skill/README resolve.
- Source includes render.py, sprite_kit.py, goods_icon_kit.py, passat.py and icon_export.py. Seed references are local copies; all copied source/reference bytes survive freezing. Actual seed has no absolute user-screenshot dependency in its source. Python/Pillow/numpy and Blender remain external runtime dependencies, appropriately documented.
- New input_hashes guard rejects an added source file in a frozen snapshot (tested). Earlier reference-path preservation gap was reproduced, reported and fixed during this audit: config now requires declared references under references/, matching copied trees.
- Proof alpha-composites originals and compares full-size/native60. Review output is pending rather than automated approval; render commands do not install assets.

## Meaningful EV setup is identifiable

Runtime catalogue row is g_057 / ev_car, Electric Car. Use its original goods art, not inherited diesel reference. Select the EV's real subtype/profile references and distinguishing graphic/accessory cue; no suitable new profile was fetched in this test. Replace inherited Passat/can-specific rulings, regions, contour calibration and metadata intentionally. Copy relevant surface-fitting, wheel and shared-boundary methods, but implement/register build_ev_car and its ICON_ev_car collection: simply renaming project.json does not create an EV builder. render.py currently executes passat.py after the shared kit and dispatches globals()['build_'+nm], so that loading/override order must be addressed. The existing copied diesel-only references do not become EV evidence through renaming. Compare EV and diesel together at60px before accepting distinction.

## Remaining concrete issue

Four regions are checked only by list length. Duplicate region names overwrite the same crop file. Synthetic test with four copies of the windscreen region passed config and produced only ONE crop, violating the advertised four-region proof contract. Reject duplicate names during config validation; ideally validate names/crop shapes before expensive rendering.

## Limits to state

Self-contained arbitrary future builders remain an authoring contract, not something this tool proves: subprocess cwd/environment is inherited, and Python can read external dependencies. The shipped seed is locally bundled, but new builders should resolve resources from their frozen __file__/workspace and bundle them before claiming portability. Runtime versions are not frozen. Reproducibility tests establish equality on the tested environment, not universal cross-Blender-version identity. These are scope limits, not blockers to using the current seed.

No further modeling/style issues assessed. Files written only under /tmp. Synthetic audit artifacts must not be mistaken for EV candidates.

Builder follow-up: duplicate region names now fail config validation before rendering. A synthetic four-identical-name configuration was rejected; the accepted seed remains valid.
