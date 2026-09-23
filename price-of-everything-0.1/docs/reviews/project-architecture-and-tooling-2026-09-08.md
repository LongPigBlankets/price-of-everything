# Project architecture, data authoring and delivery review

Reviewed 8 September 2026 at `c63ec08a` on `codex/demo-updates`. This is an assessment and implementation proposal, not a migration or deployment. No runtime code, balance values or GitHub settings were changed.

## Recommendation

Keep Godot and the offline, deterministic simulation. Build a local Economy Workbench over the existing engine, establish one versioned content contract, and automate Windows validation/export. A remotely hosted content database would add little value at the present scale. JSON is a useful eventual authoring format for nested recipes and research; it is not a prerequisite for the workbench. SQLite becomes useful first for querying experiment results and telemetry, rather than for executing production turns.

The first priority is dependable answers and repeatable operations. Several substantial pieces already exist; the work is to connect and formalise them rather than replace the engine.

## Evidence and limits

- Current content: 77 goods, 37 buildings, 209 authored recipe rows, 248 research rows. The release boots with 146 promoted recipes. Authored, promoted, demo-visible and currently research-unlocked are different sets; 209 versus 146 is not by itself a defect.
- 38 autoload services; 563 tracked GDScript files. `match_state.gd` has 8,055 lines; `urban_fabric_visuals.gd` 6,922; `building_visuals.gd` 6,531; the unit runner 21,374.
- Earlier this session, release validation passed: 561 scripts parsed with 40 skips, 3,864 unit assertions and 723 end-to-end assertions through turn 100. The Windows PCK was audited and booted using macOS Godot. The native Windows executable was not run on Windows.
- Performance numbers below are extracted from that headless E2E log, not a new representative Windows GPU benchmark. Its staged scenario reaches 646 total buildings, including world/NPC buildings; this is not 646 fully active player factories.
- GitHub API confirms Actions is enabled but there are zero workflows. The repository is public. No tracked `.github` workflows exist on the reviewed branch.
- Running the root `python3 -m price_of_everything` validator during this review reported 16 issues in its separate legacy dataset. Those errors do not establish defects in the shipped Godot catalogue.

## What is already working well

1. **Explicit turn semantics.** `turn_manager.gd` owns phase order and the ordered wiring of core listeners. Production remains outside frame callbacks. Preserve this in any refactor.
2. **Real-engine analysis.** `tools/recipe_profitability_case.gd` builds through the real build handler, resolves real turns, and records accounting through `scripts/economics_snapshot.gd`. Its Python runner validates cash reconciliation and records source hashes. This is the foundation of a trustworthy balance editor.
3. **Save discipline.** SaveLoad has version 11, migrations, explicit subsystem snapshots and temporary-file/rename writes. Keep these conventions.
4. **Shared visual authoring.** The map editor uses the actual renderers, an undo/document layer and explicit export exclusion. This is a good pattern for a recipe editor.
5. **Useful performance infrastructure.** Turn profiling, frame-anatomy watchers, routing benchmarks and load-time bakes already exist. Route invalidation and graph idle guards demonstrate that performance has received real attention.

## Technical debt to address

### 1. Conflicting sources of truth and model drift — high priority

`scripts/catalog.gd` reads the live `Goods - goodsMVP.csv`, `Buildings - buildingsMVP.csv` and `recipes_all.csv`. The root Python package instead defaults to root `data/`. There are also old recipe pools and rebalanced/master variants inside the game data directory.

The root CLAUDE instructions say to regenerate recipes from the master. However, `scripts/build_recipes_all.py` explicitly refuses normal execution because doing so renumbers IDs, deletes hand-authored recipes and drops fields. That instruction conflict is an avoidable source of destructive mistakes.

`tools/balance.py` remains especially misleading: it hardcodes a maintenance multiplier of two, a self-power factor, wage/transport assumptions and simplified integration costs. The runtime catalogue explicitly says the old maintenance multiplier was removed. A mathematically correct result from that script can therefore answer the wrong economic question.

Action: document exactly which files are authoritative, mark old tools as historical/approximate, and route authoritative calculations through the real simulation. Reuse structural validation ideas from the root Python package, but make the release validator target actual shipped data. Do not silently repair or re-import the legacy pool into the game.

### 2. Implicit content contracts — high priority

The catalogue already provides an API, but returns mutable dictionaries/arrays and mixes content loading with routing state, availability and some demo transformations. The recipe loader skips short rows and unresolved references, which makes intentional dormant content indistinguishable from some authoring mistakes unless the author inspects the outcome.

Research accepts IDs, titles and aliases in different places; saves still contain title-based unlocks. Display-name edits can therefore interact with compatibility.

Action: introduce a normalized content model with stable IDs, explicit types, units and availability states. Separate immutable definitions from per-match state and indexes. Keep the current catalogue entry points as an adapter while extracting responsibilities in small steps.

### 3. Large modules and global coupling — medium/high priority

MatchState spans ownership, construction/retrofits, research, shipments, advisors, finance-related state and serialization. Large UI and drawing files similarly combine several jobs. File length alone is not a performance finding, but it makes changes and regressions difficult to isolate.

Start with research, because it has both a clear boundary and performance evidence. Then isolate construction commands/quotes and transport queries. Preserve existing signals and save migrations while moving implementations behind smaller services. Do not add another autoload for every helper.

The analysis harness currently creates a World node to reuse a UI build handler. Extracting `BuildCommand`/`BuildQuote` into a shared service would let both the UI and workbench call the same rules without this dependency. This does not require a full simulation rewrite.

### 4. Verification and repository hygiene — high priority for automation

The test suite has excellent breadth but is one very large entry point. Some performance tests have documented noisy thresholds. An older balance scenario runner allows known red scenarios, which should not become a blanket release gate.

Separate deterministic correctness, content validation, rendered UI checks and performance measurements. Preserve runtime-error detection even when assertions pass; distinguish approved engine shutdown warnings from new exceptions. Report expected economic outcomes separately from crashes and invariant violations.

Generated captures and intermediate renders are scattered under the project and repo. Some artifact files are already tracked; the Windows exclusion list contains many individual screenshot names. Use explicit source/output boundaries and shared export policy. Retain authored maps, original art source and balance-history snapshots; do not broadly ignore/delete those as if they were disposable caches. History rewriting is unnecessary for this review.

## Performance: where to look next

The existing E2E log reports mean whole-turn latency 171 ms, p95 271 ms and maximum 311 ms. Synchronous phase work averages 84 ms. These measures differ because whole turns include frame yields, completion work and harness activity. The normal game also deliberately inserts pacing delays; storage format changes will not remove those.

| Measured component | Mean | Largest observed sample | Interpretation |
|---|---:|---:|---|
| NARRATIVE phase | 45.88 ms | 66.45 ms | Best first target for narrower profiling |
| PROCESS phase | 35.06 ms | 154.61 ms | Contains production, arrivals and accounting |
| Production passes | 11.17 ms | 42.72 ms | Material but not the largest phase |
| Transport arrivals | 5.67 ms | 152.62 ms | Occasional spikes deserve investigation |
| Buying market inputs | 5.36 ms | 11.51 ms | Reuse routing indexes; measure invalidation bursts |
| Cost solver | 0.77 ms | 1.07 ms | Low priority in this scenario |

**Research is a concrete optimisation candidate.** `_check_unlock_conditions()` loops over research definitions. Tier availability calls `_tier_node_count()` and `_tier_unlocked_count()`, which loop over definitions again. At 248 authored research rows this can repeat substantial work. The once-per-turn refresh already fixed repeated per-shipment evaluation; retain that improvement. Pre-index definitions by ID/category/tier, maintain unlocked counts and compile condition references at load time. Add timings around research, event scheduling, modifier pruning and decision draws before attributing all NARRATIVE time to research. Update counters immediately on grants so same-phase unlock cascades keep their existing behaviour.

**Visual responsiveness needs separate measurement.** Historical Windows measurements in `docs/load-time-bakes.md` show approximately 100 s falling to 10.5 s after avoiding hidden rendering and baking placement. Those are historical measurements, not a promise for this build. Stale layout/texture bakes deliberately fall back to expensive live work. Add a visible bake-health report and fail release readiness when required bakes are stale, rather than silently shipping a much slower start.

Supply-chain drawing already skips its O(n²) separation pass when view state is unchanged, and goods-graph processing checks visibility. Keep those guards. Construction focus still redraws the chart every frame; moving views rebuild edge paths and hover geometry. Profile dense-chain pan/zoom and animated construction separately. If material, cache static routes/geometry and animate a lightweight overlay rather than rebuilding the full chart. This is a candidate, not a measured current GPU bottleneck.

Measure autosave, synchronous log writes, history snapshots and signal-driven UI rebuilds around `turn_resolution_completed`; these are not all included in synchronous phase brackets. Retain diagnostics but offer a bounded production logging level. Do not remove useful error reports to make timings look better.

The exported PCK contains about 145 MiB of authored-map assets, 84 MiB of icons and 65 MiB of loading assets. It is about 366 MiB total; the ZIP is 401 MB including the executable. An asset budget and unused-variant audit can improve downloads. CSV-to-JSON conversion will not materially solve this asset-size problem.

Before considering C++, C# or a new engine, benchmark controlled early/late saves on Windows at multiple zooms and dense-chain sizes. Distinguish cold load, first panel open, steady pan, upgrade completion and turn latency. Only move a measured hot routine to native code if algorithm/index/cache improvements are insufficient.

## CSV, JSON, SQLite or a server?

| Choice | Fit for this project | Recommendation |
|---|---|---|
| CSV plus explicit contracts | Flat goods/building tables; existing hand-balanced content | Keep initially; validate strictly and give it a proper editor |
| JSON plus schema | Variable-length inputs, outputs, catalysts, requirements and research conditions | Good medium-term authoring format, migrated incrementally |
| Local SQLite | Querying many experiment runs, scenarios, telemetry exports and comparisons | Useful optional analysis store; can be rebuilt from result files |
| Remote database/API | Shared multi-author content management or a growing telemetry service | Defer game-content hosting until a concrete collaboration requirement exists |

The content set is small and loaded into in-memory structures. Changing its disk format is primarily about authoring, clarity and validation, not faster turns. A schema and API do not require a database or HTTP server.

Recommended contract: `schema_version`, content revision/hash, stable IDs, typed quantities, explicit units, building/good/research foreign references, ordered outputs, availability (`active`, `dormant`, `demo_hidden`) and reasons. Validate duplicate IDs, missing references, numeric ranges and finiteness, invalid enums and requirement types. Preserve integer quantity semantics where the engine currently uses them. Treat recipe cycles as domain-aware diagnostics: recycling loops and joint outputs mean a blanket acyclic-graph rule would be wrong.

Use JSON Schema for structural validation and a shared semantic validator for cross-file references and economic constraints. Schema cannot establish that a recipe is profitable or that a route can deliver its inputs. [JSON Schema object validation](https://json-schema.org/understanding-json-schema/reference/object)

For migration, first normalize the current CSV into the new in-memory model and record a complete load report. Then migrate one content family. Compare normalized records, catalogue membership, recipe/output ordering, build quotes, multi-turn cash and save round-trips. Keep IDs stable; do not renumber recipes. Have exactly one writable authoring source after each cutover. JSON generated from CSV is a derived artifact, not a second source people edit.

Add `content_revision`/hash to save metadata and experiment reports separately from `save_version` and app version. Decide explicitly whether existing saves retain their original balance or adopt the new balance; a schema version alone cannot answer that. Preserve old-save loading while introducing this metadata.

SQLite is an embedded, cross-platform file format with useful query and transactional capabilities. It does not inherently require a hosted API. Its best first use here is an experiment index, avoiding an extra runtime dependency in each game export. [SQLite application format](https://www.sqlite.org/appfileformat.html), [appropriate uses](https://www.sqlite.org/whentouse.html)

## Economy Workbench: a tool the owner can use directly

Build a separate developer-only Godot scene, launched through the same pattern as the map editor. It should be available from a shortcut/menu without prompting an assistant. Reuse the design system, recipe diagrams, real build quotes and economic snapshots. A browser interface is possible, but should call the Godot evaluation worker; do not recreate production economics in JavaScript.

The first useful screen:

- Left: searchable goods/recipes/buildings, filters for demo availability and research, and a list of modified records.
- Centre: the selected recipe diagram with editable input/output quantities, power, catalysts, staffing and construction costs. Good base prices are visibly global edits, separate from recipe-local quantities.
- Right: baseline versus candidate revenue, itemised costs, operating surplus, retained cash, capital requirement and estimated payback. Separate cost allocation from actual money movements.
- Bottom: cash/profit/price charts and the list of upstream/downstream recipes affected by the change. Clicking an affected recipe opens it.

Controls should include L1/L2/L3, tile/deposit, transport mode/capacity/distance, buy versus self-supply, grid/self-power, turn/policy state, research and staffing settings. Initially expose a small set of named fixtures; do not require the user to configure every variable before getting a result.

Example workflow: select Bauxite Carbochlorination, change chlorine from 20 to 18 in a draft, inspect the immediate difference, then run the baseline and candidate over the same 10/30/100-turn scenario. Show whether margin improves, whether shipping or power becomes limiting, how sales affect prices and which neighbouring recipes become less attractive. This example proposes a tool interaction, not a recommended balance change.

Use three distinct evaluation modes:

1. **Immediate estimate:** current/fixed prices using shared cost helpers. Aim for interactive response, but measure it before promising a latency. Clearly label tax, future prices, inventory and financing assumptions.
2. **Verified scenario:** actual production, transport, market and accounting turns in an isolated Godot process. Reuse and extend `recipe_profitability_case.gd` and `Economics.capture`. The current harness intentionally excludes mining, bypasses research eligibility and samples only 10 turns at one site; the workbench must expose/extend those assumptions.
3. **Scenario comparison:** the same candidate across both demo starts, a representative integrated chain, different policy stages and fixed seeds. Display profitable-turn counts, running-turn counts, shortages, price impact and reconciliation failures, rather than a single green number.

Evaluate against draft content passed before autoload/catalogue initialization; never overwrite live CSVs to preview a slider movement. Keep snapshots and queues isolated from player profiles, saves and telemetry. Cache results by engine/source hash, content hash, scenario and seed. Cancel superseded previews. Start with fresh processes for correctness; only introduce a persistent worker after reset/isolation tests and startup measurements justify it.

Authoring needs undo/redo, reset-to-baseline, explicit Apply, atomic saves, automatic balance snapshots, and a readable cell/record diff. Saving must preserve unrelated fields and output order. Detect when the underlying source changed since the draft opened. A later **Create PR** button can validate and publish the selected draft on a branch, attaching its before/after report. Each saved edit should not automatically produce a new PR.

## Automated checks, PRs and builds

GitHub Actions is already enabled; the missing part is the workflow definition and reproducible local entry points. Godot supports headless command-line release exports. Pin editor and export templates together to 4.6.2 for the initial pipeline. [Godot command-line exports](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html)

| Trigger | Work | Output |
|---|---|---|
| Every PR/update | Clean import, live-content contracts, parse check, unit tests, targeted scenario checks | One pass/fail report with logs and data diff |
| Game-affecting PR | Above plus Windows release export and PCK audit | Downloadable preview ZIP tied to commit SHA |
| Main branch update | Full demo checks, both starts/tutorial coverage, Windows package startup check | Candidate build and validation manifest |
| Explicit release tag/manual dispatch | Build once, verify, optionally sign, attach release artifacts | Versioned ZIP, hashes, content manifest and changelog |
| Scheduled or manual performance run | Fixed scenarios, multiple samples, frame/load/turn metrics | Trend report; issue only for actionable regression |
| Workbench Create PR | Validate chosen draft; create/update branch and attach economic comparison | Reviewable content PR |

Prioritise Windows runners for package boot and filesystem behaviour because Windows is the primary target. Headless startup checks do not replace a rendered Windows playthrough; add a small render/UI lane or a controlled local benchmark runner for that purpose. Do not compare GPU thresholds across unrelated hosted runner hardware.

Required engineering details:

- A single local `check`/`build` command used identically by CI; configurable Godot binary and fresh output directories, no hard-coded Desktop paths.
- Import-cache keys tied to engine/OS/content inputs; source-derived bakes checked for freshness. Rendered bakes require a rendering-capable worker and cannot be generated using the dummy headless renderer.
- Machine-readable assertions/JUnit or equivalent, fail on GDScript runtime errors, timeouts and missing output; preserve useful logs and manifests.
- Build/version metadata from one source. Keep the app's identity/user-data directory stable across future version bumps; place the changing version in the window title and build metadata rather than continually changing persistent app identity.
- Check EXE+PCK pairing, CSV keep-mode, map selection, selected bakes, all runtime icon tiers and source/output exclusions. Avoid relying on a successful editor boot.
- Keep signing/upload credentials out of ordinary PR jobs; scope permissions and pin third-party actions. Publish to itch only through a deliberate release step. Butler is a suitable upload path for incremental updates; this review has not configured or authorised a scheduled publisher.
- Use a GitHub App for fully automatic PR creation/check triggering if needed. Current GitHub documentation says PR events created with `GITHUB_TOKEN` produce approval-required checks; a GitHub App token can enable automatic triggering. Explicit workflow dispatch is another supported option. [GitHub workflow triggering](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow)

Useful bot PRs are constrained: selected content edits, asset-import/manifest updates, deliberate dependency updates and release version/changelog changes. Economic optimisation should generate evidence for review; do not let a nightly bot silently retune the game to maximise a single score. Use one updateable branch per proposal to avoid PR spam.

## Other worthwhile improvements

**Replayable bug reports.** Provide a Copy diagnostics/Export bug bundle button with version/content hash, OS, selected settings, recent errors and an opt-in save. Add a versioned player-command journal so a reported turn can eventually be replayed deterministically. Seeds alone are insufficient without actions and matching content.

**Content health dashboard.** Show promoted/dormant/demo-hidden recipe counts with reasons, broken references, missing icons, asset provenance, research reachability, stale bakes and tool status in one developer screen. This resolves several recurring manual questions.

**Telemetry service boundary.** The current Apps Script receiver serialises writes with a lock and scans existing sheet IDs to deduplicate each submission. That cost grows with accumulated history. It has useful feedback validation and retry deduplication, but the embedded client token is distributed in a public repository and game; it cannot establish trusted-client authenticity. Add bounded request/schema validation and abuse controls, with idempotency keys for run envelopes as well as events/turns. If traffic grows, an indexed database behind the telemetry ingestion API is a more justified database migration than the recipe catalogue. Keep gameplay independent of service availability and retain consent/outbox handling.

**Art pipeline ownership.** Several sprite-kit implementations are copied into tools, skill bundles and source snapshots. Distinguish historical snapshots from the maintained generator; keep one maintained tool API and pin the version used by each asset. Extend the approved-icon manifest into a clear provenance/licence inventory and automatic tier-generation/import check.

**Documentation that can be trusted.** Update the recipe-source instructions and stale module headers before introducing more tooling. Add a short developer launcher/runbook with supported commands, expected outputs and recovery steps. Documentation checks should catch references to retired entry points.

## Suggested implementation order and acceptance criteria

1. **Reproducible Windows CI and release command.** A fresh checkout passes meaningful checks and produces an audited preview ZIP without this Mac's local paths. Preserve current release behaviour.
2. **Authoritative content contract and load report.** Validate the live pool, identify dormant content explicitly, eliminate ambiguous authoring instructions and quarantine approximate legacy calculators. No recipe IDs, quantities or promoted records change.
3. **Economy Workbench MVP.** Edit one recipe and one good price in a draft, view before/after estimates and real-engine scenarios, undo and save safely. A known fixture reconciles to the game; failed drafts cannot alter player saves or shipped files.
4. **Research profiling and focused extraction.** Measure individual NARRATIVE handlers; index tier/ID lookups. Identical seeds/actions produce the same research grants, timing and saved state before/after. Report performance on fixed hardware.
5. **Scenario library, owner-facing diagnostics and PR button.** Multi-turn comparisons, price/policy sweeps, reusable bug bundles and selected-draft PR creation with evidence.
6. **Selective JSON migration.** Start with recipes/research only if nested editing and validation justify it; preserve a single authoring source and compare normalized runtime behaviour. Add SQLite for experiment history only when file-based reports become inconvenient to query.

The workbench is likely the largest improvement to the owner's daily workflow. The content contract and real-engine worker make its answers dependable; CI makes its saved changes safe to distribute.
