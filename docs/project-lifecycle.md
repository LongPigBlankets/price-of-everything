# Project lifecycle and archive index

19 October 2026. This is the current cleanup index. Dated reviews retain their original
findings; use current source and this index to distinguish resolved findings from work
still outstanding. An old filename or a design-only status is not proof of abandonment.

| Lifecycle | Paths / ownership |
|---|---|
| **Active** | Godot project; Catalog's six CSV inputs; `research_unlocks.csv` and presentation; starts/NPCs; authored map documents; runtime assets and production bakes; tests and their scenarios; current asset builders, manifests and approval standards |
| **Active guidance** | [Content authoring](../price-of-everything-0.1/docs/content-authoring.md), [demo build](../price-of-everything-0.1/docs/demo-build.md), [bakes](../price-of-everything-0.1/docs/load-time-bakes.md), [DS2 theme](../price-of-everything-0.1/docs/ds2-theme.md), test README and current owner decisions |
| **Future retained** | Recycling definitions/art/tests in full source; [pollution design](../price-of-everything-0.1/docs/pollution-spec.md), carbon schema/tax logic; [future market dynamics](../price-of-everything-0.1/docs/future-market-dynamics.md), `market_state.gd`, `market_rules.gd` and pricing/history tests |
| **Superseded rollout notes** | Market, Resources and People DS2 plans: retained design/approval history. Their advertised switchbacks are retired; the active panel scripts directly host DS2. Construction still has an active base class; Dock, Legend and Research variants are retained. |
| **Generated, retained** | `data/goods_flow.json` / `docs/goods_flow_chart.html`, built by `scripts/build_goods_flow.py`; current reports, captured standards and bake fingerprints. Generated does not mean disposable. |
| **Historical evidence, retained** | Dated reviews; `data/balance_baselines/`; test benchmarks; approved asset renders and Blender sources; release/build logs; EULA/privacy/loading approvals; current October artwork, trailer and supply-chain captures |
| **Legacy retained** | Root Python package/data/tests: [prototype guide](legacy-python-prototype.md). Kept separate from current game authoring. |
| **Archived, tracked** | [Legacy recipe material](../archive/legacy-recipes/README.md) and the [May scene recovery file](../archive/scene-recovery/README.md), with [hash/provenance manifest](../archive/manifest.json). Old recipe doc paths redirect to the archive and current guide. |
| **Archived, local** | In the original working folder: `archive/local/2026-10-19/`. Whole historical v0.2/Experimental bundles and September release workspaces are preserved with per-file hashes, saves/logs and restore instructions. These machine-local files are not part of a PR/download. |

## Retention and future cleanup

- Keep canonical art sources, approved/golden renders, balance baselines and production
  bake resources with their fingerprints. Never sweep `artifacts/`, `reports/`,
  `outputs/` or caches by age, extension or tracked status.
- For a retired tool/table, identify runtime, test, generator and documentation consumers
  first. Preserve its original source/commit and hashes, fix current links/instructions,
  and make accidental execution or reimport fail safely.
- For local releases/captures, archive by whole run. Preserve distributables, manifests,
  validation logs, screenshots and saved games together. Verify file hashes after moving.
  Local moves organize the checkout; they do not claim disk-space savings.
- New generated reports/captures go in a named run directory. Document the regeneration
  command and approved result; only archive intermediates once their replacement/evidence
  has been identified. Ambiguous drafts stay until their status is established.
- Restore archived local material using its manifest/restore script. A restore must refuse
  to overwrite a new file at the original path.
