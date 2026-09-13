# Service size, performance and agent-driven development

Reviewed 8 September 2026, branch `codex/demo-updates`, commit `c63ec08abd7fb0919fbc6428cd27cad85b2504b8`. This is an assessment; no runtime refactor was made.

## Recommendation

Split MatchState by domain, starting with research, and split the shared test runner alongside it. Keep MatchState as a compatibility entry point while ordinary owned GDScript objects take over implementations. Do not turn every extracted file into another autoload. Keep the existing explicit turn ordering.

The expected benefit for agent-driven work is substantial: smaller relevant context, clearer ownership, more targeted tests and fewer shared edit locations. That is a conclusion from this repository's structure, not a measured improvement in model accuracy. Moving methods between files alone will not improve runtime performance.

## What was measured

- There are 563 tracked GDScript files, totalling 206,363 physical lines, including game code, tests and tools. This is not the size of the shipped simulation alone.
- File sizes below count blank lines and comments. Function counts are top-level `func` declarations. Static function sizes count nonblank lines other than full-line comments; these are approximate source complexity indicators, not executable instruction counts or formal cyclomatic complexity.
- Reference counts are distinct tracked scripts containing direct `Singleton.member` references, including tests/tools. They measure coupling, not runtime call frequency or direct writes.
- Change frequencies cover the last 100 commits visible from HEAD. They indicate common editing locations, not measured merge conflicts.
- A fresh Godot 4.6.2 headless 100-turn scenario wrapped seven existing phase listeners in their original order. It completed **723 checks with zero failures**, with no script errors or duplicate-connection errors. It did report resource/ObjectDB leaks at shutdown; this is not a clean resource-lifecycle test.
- Timings are inclusive synchronous listener timings on this Mac, including downstream synchronous callbacks. They exclude human pacing, frame waits and work outside the measured phase callbacks. This does not profile Windows graphics, UI frame rate, every starting business or worst-case endgame scale.

Raw evidence and the temporary profiling script are in `outputs/service-review-2026-09-08/` at repository root. The static report contains selected large services/scripts rather than the full 563-file inventory.

## Which files are oversized?

| File | Lines | Functions | Assessment |
|---|---:|---:|---|
| `tests/test_runner.gd` | 21,374 | 442 | Highest shared editing pressure. Split into domain suites with a small runner. |
| `scripts/match_state.gd` | 8,055 | 471 | Strongest service split candidate: many independent responsibilities and extensive global coupling. |
| `scripts/urban_fabric_visuals.gd` | 6,922 | 215 | Separate geometry construction, placement, drawing and audit helpers where their dependencies permit. |
| `scenes/building_visuals.gd` | 6,531 | 229 | Complex placement/subcomponent code merits boundaries; file size alone does not establish a frame-rate problem. |
| `scripts/top_bar.gd` | 3,997 | 136 | Extract individual flyouts/panels and their presentation models as those features change. |
| `scripts/tile_info_panel_v2.gd` | 3,728 | 149 | Large UI construction and update surface; split coherent sections rather than individual widgets. |
| `scripts/construct_panel_v2.gd` | 3,397 | 126 | Separate quoting/eligibility presentation from panel construction and interaction. |
| `scripts/world_map.gd` | 3,243 | 160 | Keep a scene coordinator; move distinct loading/placement/interaction jobs behind it. |
| `scripts/production.gd` | 2,802 | 96 | A real pipeline with complex calculations. Extract stages while preserving one explicit orchestrator. |
| `scripts/building_detail_panel_v2.gd` | 2,704 | 86 | Separate tabs and view calculations when touched; avoid duplicating simulation logic in them. |
| `scripts/decision_state.gd` | 1,437 | 50 | Roughly 400 initial lines precede the first function. Definitions account for substantial size; separate definitions before fragmenting behaviour. |
| `scripts/road_works.gd` | 1,258 | 51 | Relatively coherent road work/visual responsibilities and only ten referencing scripts; lower priority. |
| `scripts/catalog.gd` | 1,198 | 84 | Loaded content definitions and mutable topology/cache responsibilities need a clearer boundary. |
| `scripts/tutorial/tutorial_engine.gd` | 1,040 | 56 | Coherent controller but increasingly large; split condition adapters/presentation when needed, retain ordered progression. |
| `scripts/save_load.gd` | 810 | 41 | A versioned persistence coordinator is a reasonable responsibility. No need to fragment solely for size. |

By comparison, TurnManager is 181 lines, CostSolver 261, TransportService 360, MarketState 535 and Construction 634. These are not the first places to spend a refactoring budget. DS, EconomyConfig and MapStyle contain significant configuration/style data: splitting constants merely to reduce line counts adds little value.

Some individual functions are also difficult to change safely: Production's `_buy_market_inputs()` contains about 167 nonblank/noncomment lines and 44 branch/loop statements; building visuals' `_rebuild_subcomponents()` has about 252 such lines and 48 branch/loop statements. These are better candidates for named sub-operations and explicit intermediate results than for an arbitrary file-length rule.

## MatchState's real problem is responsibility and ownership

MatchState has direct references from **221 scripts**. Catalog has 159, TurnManager 102 and Production 65. Within MatchState, `buildings` is referenced from 92 scripts and `money` from 75. These references are not all writes, but they show why a wholesale API replacement would be disruptive.

Approximate MatchState responsibility regions demonstrate the range:

- Ownership and building lifecycle: roughly 1,200 lines.
- Surveys and deposits: roughly 280 lines.
- Research: roughly 1,100 lines.
- Freight, standing orders, warehousing and congestion: roughly 2,300 lines.
- Finance/advisors, loyalty and missions: roughly 1,440 lines.
- Further state declarations, signals, reset/save code, batteries and land operations sit around those regions.

These are review regions, not clean extraction boundaries: relevant fields and signal handlers are scattered elsewhere in the file. Extraction must move a responsibility's state and lifecycle together.

## Where time is actually going

Fresh scenario results:

| Measured operation | Mean | Maximum | Interpretation |
|---|---:|---:|---|
| Sum of synchronous resolution phases | 83.82 ms | 199.73 ms | 99 complete profiler records; not total player-visible turn duration. |
| MatchState NARRATIVE callback | 45.68 ms | 66.05 ms | Profitability streak update plus research refresh and synchronous consequences. |
| Production PROCESS callback | 34.57 ms | 155.74 ms | Production, purchases, arrivals and settlement pipeline. |
| CompanyRankings AI callback | 2.95 ms | 5.74 ms | This phase label does not establish that opponent strategy is expensive. |
| EventScheduler NARRATIVE callback | 0.037 ms | 0.083 ms | Negligible in this scenario. |
| Modifiers NARRATIVE callback | 0.024 ms | 0.053 ms | Negligible in this scenario. |

The instrumented Production listener includes 100 PROCESS invocations; most other active listeners have 99 samples. Production's existing subsection profiler has 99 complete records. Its production passes average 11.11 ms, input purchases 5.34 ms and cost solving 0.77 ms. Transport arrivals average 5.65 ms but reach **153.71 ms**: investigate the spike's route/cache/shipment work separately from ordinary steady-state cost. These nested timings overlap; do not add them to their parent timings.

### Research: first optimisation candidate

`match_state.gd:793` places profitability streaks and research refresh in the expensive callback. The measurement does not distinguish those two functions or exclusive research CPU time, so it would be inaccurate to call all 45.68 ms “the research loop”. Add inner timing brackets before assessing an optimisation's contribution.

There is nevertheless a concrete repeated-work pattern at lines 2456–2482 and 2651 onward. The unlock scan checks each definition, and tier availability repeatedly scans the full definitions list to count prior-tier nodes and unlocked nodes. There are 248 authored research rows. In the worst case these nested scans grow quadratically in definition count, before evaluating live building conditions.

Recommended changes after a behaviour-preserving extraction:

1. Index definitions by stable ID and category/tier.
2. Maintain visible-node and unlocked-node counts per tier.
3. Resolve condition tokens to their canonical meanings when loading definitions.
4. Build reusable per-turn facts for conditions that repeatedly scan the same buildings.

Preserve definition evaluation order and same-phase unlock cascades: counters must reflect newly granted unlocks immediately. Demo visibility/ruleset changes and save imports must invalidate or rebuild the relevant caches. Keep the existing once-per-turn refresh. Research currently bridges stable node IDs and title-keyed unlock state; preserve that compatibility during extraction.

### Production and graphics: more selective work

Production should retain one visible sequence of stages. Input procurement, power allocation, settlement and report construction can become owned helpers with an explicit per-turn context. Existing Stockpile, Power, TransportService and CostSolver already own parts of this domain; avoid creating competing implementations of those jobs.

`turn_report_for()` line 36 linearly searches reports. An instance-ID index is plausible if repeated consumers become expensive; the current timing does not establish it as a bottleneck.

The large visual files need a windowed capture/profile to attribute frame time. Empire view already skips some unchanged layout work and separates some overlays. Full redraws during animation and large graph layout/geometry work remain candidates, not measured defects from this headless run.

Preserve bake validity when extracting placement code. `start_layout_baked.gd` hashes map/data inputs and uses an explicit `BAKE_VERSION` for placement changes; its current content hash does **not** automatically hash every placement script. Update the version/dependency discipline and compare baked/live layouts when behaviour changes. Moving code is not proof that an existing bake remains equivalent.

## Why this helps an agent-driven workflow

The benefit comes from limiting what must be understood and what may be changed together.

- **Less unrelated context:** a research condition change can be understood from research definitions, evaluators and tests instead of the entire match state.
- **Clearer prompts:** “change this condition, preserve grant order and save keys, run this suite” is a concrete contract.
- **Fewer shared edits:** independent features can change separate implementations and tests.
- **Better review:** a moved method with a stable interface is easier to verify than a feature patch mixed with state restructuring and an algorithm rewrite.
- **Better developer tools:** a research evaluator or price calculator with explicit inputs is easier to reuse in the proposed Economy Workbench without booting unrelated UI.

There are costs: extra navigation, more interfaces to maintain, and possible dependency cycles. A helper that takes unrestricted access to every singleton reproduces the original coupling. Excessively small files can make an agent trace more code rather than less. Use coherent domain boundaries, not a hard line-count target.

Godot's own guidance favours focused responsibilities and explicit dependency relationships; ordinary objects can participate in this structure without becoming global autoloads. See [Godot scene organisation](https://docs.godotengine.org/en/stable/tutorials/best_practices/scene_organization.html).

## Proposed shape

Keep existing global entry points during migration. Add ordinary `RefCounted` objects for owned domain state/logic and stateless helpers for pure calculations. Use Nodes only where scene-tree behaviour is needed.

| Owner/entry point | Candidate owned modules | Boundary to preserve |
|---|---|---|
| MatchState | ResearchState, ResearchDefinitions, ResearchConditions | Unlock state, progress, deterministic grant order and existing save keys. |
| MatchState | FreightState, StandingOrders | Pending movement/order state; route computation stays with the established routing owner. |
| MatchState | AdvisorState and advisor definitions | Seats, loyalty, missions and their event subscriptions. |
| MatchState | BuildingLifecycle | Ownership and building mutations; cooperate with Construction rather than duplicate project queues. |
| Production | InputProcurement, PowerAllocation, TurnSettlement, TurnReports | Explicit stage order, rounding, accounting and per-turn data lifetime. |
| Catalog | ContentDefinitions/loader and a clearly separated topology index | Content identity versus mutable routing state; coordinate with TransportService. |

Do not move everything at once. Keep money and the building registry in their existing owner initially. A compatibility property can forward to a new owner later, but there must be one authoritative dictionary: silently copying it would break code relying on in-place mutation, while retaining two mutable copies creates divergence.

Avoid inheritance chains such as several successive subclasses of MatchState. Composition makes responsibility and lifetime more explicit. Also avoid one generic “manager” or service locator that gives every module unrestricted access to every other module.

## Split the tests as part of the work

The test runner changed in **48 of the last 100 commits**, versus MatchState in 21 and Production in six. Even well-separated feature implementations will collide if every test is appended to one 21,374-line file.

Introduce research, logistics, production, saves and UI-focused suites with independently reset fixtures and a small registration/discovery layer. Preserve test execution and failure accounting: accidentally dropping tests during a move must fail validation. Targeted suites should run directly, with the complete suite retained as the integration gate.

For parallel agent work later, give each task ownership of one domain and its suite. Keep shared facade changes, save contracts and turn sequencing under one integration owner. Separate worktrees help isolate edits, but cannot fix ambiguous ownership or inconsistent assumptions.

Each module needs a concise contract: purpose, state owned, inputs/results, allowed dependencies, emitted signals, save keys, ordering assumptions and the command that verifies it. Keep one short architecture map; avoid duplicating the same rules across many files.

## Suggested sequence

1. Extract the research tests and establish deterministic before/after snapshots of grants, progress and saved state. Keep the existing full runner as a gate.
2. Move research implementation behind MatchState without changing algorithms, public behaviour, save version or evaluation order. Include reset/load and signal-lifetime checks.
3. In a separate change, add inner research timings and optimise tier/ID lookup. Compare identical scenarios and confirm equivalent results.
4. Extract freight/orders and advisors one at a time, with their tests. Leave the highly shared building registry and money interface stable until their callers can migrate deliberately.
5. Extract Production stages when improving that stage or implementing workbench reuse. Profile arrival spikes before committing to an algorithm change.
6. Tackle visual placement and large UI components when measured performance or upcoming work makes them worthwhile.

Judge success by smaller relevant change surfaces, independent test commands, unchanged deterministic results and saved-game compatibility. For agent productivity, record files that must be inspected, unrelated files touched, review corrections and regressions across several comparable tasks. There is no defensible percentage improvement estimate yet.
