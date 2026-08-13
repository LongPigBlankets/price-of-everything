# Map visual gauntlet II — close the remaining gates

> Source document for implementation by an agent. This is a **continuation** of the
> August 11–13, 2026 gauntlet recorded in `reports/map_visual_gauntlet.md`. That report is
> the authoritative history of what has been tried, accepted, rejected and retired.
> **Read it completely before writing any code.** When this prompt and that report disagree
> about what has already been attempted, the report wins. When they disagree about what to
> do next, this prompt wins.

## 1. Executive summary

The optional draw-only **mid-century** map style is built and committed on branch
`decorative-buildings-and-city-look` (commit `e8cd62ca`). It has an accepted hero slice
(Arin Old H2.11), accepted Silkstown and Capital SettlementPlan prototypes, an organic
district field giving all 92 urban tiles a genuine dense core, water/relief-safe massing,
coastline-adaptive ports (4/4 accepted), and far-zoom silhouette plates. Every legacy
renderer (classic, ink, plate) round-trips byte-identically and every gameplay invariant is
frozen and verified.

**The whole-map gauntlet did not pass.** The final independent critic scored the map
**3.67/5** against a 4/5 floor, with four categories stuck at 3/5:

1. reference-family resemblance,
2. continuous figure/ground,
3. historically accumulated character,
4. absence of procedural repetition.

Your job is to close the enumerated hard gates in §5, in order, until the whole-map critic
scores **≥4/5 in every category** — without breaking a single frozen invariant.

**Core test of this gauntlet:**

> Does the whole map read as one continuously inhabited mid-century cartographic world —
> no visible hex seams, no repeated procedural glyphs, cities that look accumulated over
> decades rather than generated in one pass — at wide, regional and close zoom?

If a proposed mechanism does not move one of the failing gates in §5, do not build it.

## 2. Priorities and decision rules

When there is ambiguity, use this order of priority:

1. gameplay invariants (§4) — never traded for a visual gain, no exceptions;
2. determinism and legacy-identity proofs (§7);
3. closing the hard gates of §5, in the order A → B → C → D → E;
4. reference-resemblance polish (§5, gate F);
5. new visual layers — **never**, until A–E are closed.

The four verbs of this gauntlet are: **subdivide → taper → vary → verify.**

Standing rules, inherited and proven over ~60 prior iterations:

- **Two-attempt stopping rule.** A visual mechanism gets at most two materially different
  attempts. Two rejections → remove it completely from the renderer, document it in the
  report, and change abstraction. Never tune a dead mechanism a third time.
- **Never retry a retired mechanism** (§9). The graveyard exists so nobody re-fights a
  settled battle.
- **One architectural layer per iteration.** Each candidate changes exactly one named layer
  (subdivision, zoning, massing, roofs, linework, palette…) so the critic can attribute the
  change.
- **The critic is independent and harsh.** No candidate is accepted without a fresh-context
  critic scoring it against the rubric AND side-by-side against the current accepted best.
  Accept only if a primary failing score rises with no material regression elsewhere.
- **Reject neutral.** A change the critic cannot see at original resolution is rejected as
  neutral, exactly like a regression (precedents: H2.05, P4.02).

## 3. Starting state and preservation record (do this first)

1. Branch from `decorative-buildings-and-city-look` (`e8cd62ca`) into a new working branch
   (suggested: `map-gauntlet-2`). The working tree may contain the owner's unrelated
   changes (`scripts/goods_graph_world.gd` modification, `tools/market_model/`,
   `docs/future-market-dynamics.md`, `tools/npc_market_dump.*`, deleted
   `reports/balance/*.csv.import`, stray `*.gd.uid`). **Leave them untouched — never stage,
   commit, clean, revert or absorb them.**
2. Re-establish your own V0 baseline before any change, exactly as gauntlet I did. All
   commands run from the Godot project root `price-of-everything-0.1/`:
   - `python3 tools/run_tests.py` → all tests pass, exit 0. Expect **2,260 passed,
     0 failed** as of `e8cd62ca` (CLAUDE.md's "~669 asserts" figure is stale; exit 0 with
     zero failures is the criterion, the count only grows).
   - Run the all-style capture harness twice on the normal GPU renderer:
     `<godot> --path . res://tools/map_style_shot.tscn --quit-after 4200` (windowed, NOT
     headless). It captures every classic/ink/plate/mid-century framing, performs the
     legacy → midcentury → legacy round trip, the masked map-region assertion, and the
     repeated mid-century wide capture automatically. Likewise run the morphology harness
     `res://tools/settlement_morphology_shot.tscn` twice. **Before running each harness,
     read its `.gd` source for its exact output PNG and metrics-JSON paths** — outputs land
     in `/tmp/poe_*` and beside the scenes; the sources are the authority. Record the
     byte-identical hashes of every output as **your** frozen V0 baseline. Do not rely on
     hashes transcribed in the old report (at least one contains a transcription typo);
     the *invariant* is round-trip identity and run-to-run identity, re-anchored at V0.
   - **Expect the morphology harness to exit NON-ZERO at V0.** It correctly fails the
     unresolved G1.02 road-gradient gate; that is the recorded state, not a runner bug.
     Byte-identity of the PNGs and metrics JSON across two runs is the baseline criterion,
     not exit code 0. Do not "fix" the harness to make it pass.
   - Run the road-frontage audit
     (`<godot> --headless --path . res://tools/road_frontage_audit.tscn --quit-after 4000`)
     and confirm the frozen totals: 177 road tiles, 413 buildings measured, 79 failing
     tiles, 177 buildings over 15u, 137 off-road-by-design, one service-lane save,
     **165 block-mode failures**, worst 146.6u furnace on `tile_10_3`. These numbers must
     never change.
   - Regenerate the per-tile failing lists for gates A, B and C from your V0 metrics.
     If any regenerated list or number disagrees with the ones quoted in §5, **stop and
     investigate before building anything** — either the baseline is not what you think it
     is, or the report is stale; both must be resolved and documented first.
3. Locked references you inherit:
   - **Arin Old H2.11** — the hero regression slice: 25 street faces, 151 parcels,
     38.2881% built / 17.5218% green / 44.1901% negative, mass mix 44 solid / 27 U / 21 L /
     26 courtyard-ring. Byte-exact under your V0 hash unless replaced per gate A's rule.
   - The accepted evidence directories under `reports/map_visual_gauntlet/` (553 MB,
     gitignored — **never commit the PNG tree, never `git clean` it**).
   - Known pre-existing console noise: isolated `%TerrainLayer` fixture diagnostics,
     GUI-anchor warnings, shutdown RID/resource-leak reports. Not yours to fix; but any
     **new** error, warning class or parser failure is a rejection.
4. **Commit discipline (new in gauntlet II).** Gauntlet I ran for three days entirely
   uncommitted. Do not repeat that: commit source + updated report on your working branch
   at every *accepted* gate checkpoint. Evidence PNGs stay out of git.

## 4. Frozen invariants — the contract

Carried unchanged from gauntlet I. Violating any of these invalidates the run:

- The mid-century style is **draw-only and optional**; the game still starts in the
  existing style. `MapStyle.set_midcentury()` is the only switch.
- Frozen forever: road topology, river topology, bridges, subtiles, terrain classification,
  forest occupancy, gameplay building footprints (logical and visual), occupancy, placement
  legality, click testing, selection, ownership, transport connectivity, building
  counts/capacities, economy, tile classifications, save data and schema.
- Decorative fabric is deterministic, non-interactive, owns no land, has no economic
  identity, and is seeded through `RoadHash` — no wall-clock time, no global RNG.
- **No per-building or per-tree nodes.** All decorative output stays in batched
  `ArrayMesh` layers (`UrbanFabricVisuals` and siblings).
- Legacy classic, ink and plate renderers remain byte-identical compatibility targets:
  legacy → midcentury → legacy must reproduce the legacy capture pixel-for-pixel in every
  accepted run.
- The road-frontage audit totals never move.
- Balance constants, `economy_config.gd`, and the Goods CSV tuning columns are untouchable
  (CLAUDE.md rule 7). This gauntlet has no reason to ever open those files.

## 5. The hard gates (the actual work), in priority order

### Gate A — road-directed density inside face subdivision (7 failing tiles)

**Requirement:** all applicable urban tiles pass the normalized road-density gradient:
rich-sector coverage minus poor-sector coverage ≥ **+5 percentage points**.

**Instrument:** the G1.02 all-92-tile universal oracle, emitted as per-tile records in the
morphology harness's metrics JSON (rich/intermediate/poor sector construction,
normalization, and applicability flags are defined by the oracle code and documented in
the report's G1.02 section — lift them from there, do not reinvent them). The oracle
itself marks tiles inapplicable (e.g. roadless); at G1.02 that left **87 applicable of
92**. Regenerate the failing list at your V0.

Failing at G1.02: Arin Old (**−25.38**), Arin Industrial (−5.47), Arin Highgate (−2.22),
Arin Millgate (−3.93), Arin City (+2.25), Teganfort Industrial (+4.80), Capital Market Row
(+4.93).

**Mechanism constraint (proven, not negotiable):** five distinct post-generation
deletion/reordering variants were rejected in G1.02 — they break connected street walls
into paper voids and isolated cards. Also dead from the same campaign: the Tegan annex, a
second reconciliation pass, and contiguous-annex experiments — all neutral or moved the
failure into a neighbour. Road influence must enter **during face subdivision and mass
construction**, jointly shaping parcel grain and occupancy while the perimeter fabric is
being built, not pruning it afterwards. Design gates A and B together: both operate on
settlement-wide face geometry before parcel roles are fixed. **A single joint A+B
mechanism is explicitly permitted and counts as one architectural layer** for the
one-layer-per-iteration rule and critic attribution.

**The hero lock:** Arin Old is both the worst gradient failure and the locked regression
slice. Resolve the conflict explicitly: the H2.11 hash may be replaced **only** by a
candidate that (a) passes the +5pp gradient, (b) scores ≥4/5 in **all ten** hero rubric
categories in a dedicated hero critique, and (c) visibly preserves connected perimeter
street walls. Anything less → Arin stays byte-exact and the mechanism is rejected.

### Gate B — organic exterior settlement boundaries (13 failing tiles)

**Requirement:** every urban tile's local exterior boundary has < **20%** hex-edge
coincidence, measured by the corrected per-source-tile oracle (which includes settlement
geometry spilling outside the source hex). The oracle is part of the same G1.02 universal
metrics emitted by the morphology harness — the local-exterior-boundary and
hex-coincidence fields per tile. Regenerate the failing list at your V0.

Failing at G1.02, 13 tiles: seven Arin tiles, Patran Old, three Capital tiles, both
Silkstown tiles. Worst three: Silkstown Docks (**81.92%**), Arin Highgate (80.01%),
Capital Foundry (78.43%). The dynamic captures show long straight tile-aligned termination
— a real visual defect, not an audit artifact.

**Mechanism constraint:** exterior lobes must taper organically (references accumulate at
different times and bearings). Road proximity is a legal *weighting input* but not the
envelope source. The three retired continuity abstractions (§9: connector bands, density
thresholds, road catchments) may not return in disguise.

### Gate C — whole-body settlement gates (20 failing components) + Pepper Docks

**Requirement:** zero components failing the whole-body statistics recorded by the
renderer audit: mass count, p25/median/p75/p90 mass area, largest-one and largest-three
shares, repeated-size and repeated-shape dominance, road-frontage occupancy, occupied body
share outside the core, and usable-body built coverage. A "component" is a connected
settlement component as the renderer audit itself records them. **The pass/fail thresholds
embedded in the bounded-gauntlet harness (`tools/midcentury_bounded_gauntlet.tscn`) are
authoritative** — it emits per-component verdicts; the K1 section of the report records
the gate definitions. Regenerate the current failing list from its metrics at your V0 —
do not trust a stale list.

Named sub-targets:

- **Pepper Docks** (rejected in K1): six oversized masses, 60.43% largest-three dominance,
  repeated staircase river frontage. It needs its own industrial-fringe vocabulary pass —
  varied yard/shed/works grain, not a third small-town mechanism.
- **Repeated-shape dominance** at Pepper (52.38%) and Klade (59.38%): introduce deterministic
  variation in the ordinary terrace vocabulary without inventing a new repeated glyph
  (the V4.09 hook-glyph failure is the cautionary precedent).

### Gate D — road-junction linework (the oldest open defect)

**Requirement:** implement **source-level casing-path stitching**: connected road segments
share continuous casing paths so no internal endpoint caps are emitted at shared junction
endpoints; caps appear only at true dead ends. Success = **linework coherence** — the
category from the V-series 13-category rubric recorded in the report's "Rubric scores"
section, scored the same way — reaches ≥4/5 map-wide, and the blind critic finds zero
repeated junction glyphs in the Player Close, Block Close, Stoneshore and Stoneshore Docks
framings at original resolution (a critic judgment over those four named framings, not an
automated count). The framings themselves are fixed camera/zoom presets encoded in the
capture-harness scenes — invoke them by name, never re-frame by hand.

**Hard constraint:** all three overpaint approaches are retired (V3.03 bed circles, V3.04
convex envelopes — degenerate triangulation, V3.05 tangent cross-bed strokes). **No more
overpaint primitives.** This is a path-construction change in the road drawing source, made
under the same legacy-identity proofs as everything else (it must not perturb classic, ink
or plate output).

### Gate E — whole-map critic categories to ≥4/5

The final (K1) critic's first two named reference gaps, plus the long-standing wide-zoom
industrial-landmark weakness (3/5 since the P4.01 scorecard — the K1 critic's third gap,
port bilateral regularity, was already closed by L1), translate into levers:

1. **Finer, darker, more continuous urban carpet** — the references read denser and lower
   contrast between ordinary masses than the current pale/sparse fabric. Expected to fall
   out substantially from gates A–C; verify and top up with palette-value tuning only
   inside the mid-century style's own tokens (`scripts/map_midcentury_style.gd` owns the
   entire mid-century palette — never the legacy `MapStyle` values).
2. **Kill the remaining repeated glyphs** — terrace pairs, open-lot marks, stair-step
   masses recurring across unrelated blocks.
3. **Industrial landmark hierarchy at wide zoom** (stuck at 3/5 since P4.01): the
   references use rare, strong oxide/salmon/rust landmarks; the current industry accents
   are uniformly muted. Give a small deterministic subset of major industry compounds
   (single digits map-wide) a stronger accent so a handful of landmarks survive wide zoom.
   Bound: above the accepted half-chroma ordinary tier (V4.08b), strictly below the full
   category colour that failed as saturated fields (V4.08a). The halve-chroma discipline
   stays in force for the *ordinary* industry tier; the landmark tier is the one rare
   exception.
4. Re-check the far-zoom plate afterwards: some ordinary towns are currently low-contrast
   anchors at world scale.

**Passing bar:** an end-of-gauntlet whole-map critique with every category ≥4/5, and a
fixed-slice scorecard with no applicable cell below 4. The rubrics are **not yours to
invent**: the whole-map 12 categories (inhabited impression, reference-family resemblance,
continuous figure/ground, organic parcel structure, streets as negative space, green-space
integration, decorative/gameplay hierarchy, industrial color discipline, top-down
discipline, historically accumulated character, multiscale readability, absence of
procedural repetition), the ten hero categories (same list minus multiscale readability
and absence of repetition, per the H-series critiques), the V-series 13-category rubric
and the fixed-slice scorecard grid are all recorded verbatim in the report — lift them
unchanged.

### Gate F — polish (only after A–E are closed; explicitly not gate blockers)

- Port head/apron vocabulary is still diagrammatic at close zoom; Arin's right quay is
  29.53% sea-deck (land-rooted) — the weakest quay-to-water transition of the four.
- Silkstown's embankment street reads more formal than the reference family; cross-bank
  urban grain is thinner than the references.
- The pilot suburb reads as a sparse works ribbon, not a mature mixed district.
- Stoneshore's central open field (the K1 preservation caveat on figure/ground).

## 6. The iteration protocol

Every candidate follows the same loop the prior gauntlet proved:

1. **Name the gate and the single architectural layer** the candidate changes.
2. Implement deterministically (seeded via `RoadHash`; no `Date`/global RNG).
3. Capture the fixed framings for the affected gate plus the standing slices (Arin Old,
   Capital, Silkstown, Fort Silversworth, Vandel, Farpoint, Pepper/Klade, wide) with the
   UI-hidden harnesses. Two runs; byte-identical or the capture is invalid.
4. **Independent critic pass.** Mechanically: spawn a **fresh subagent** whose entire
   context is the rubric (lifted verbatim from the report), the unlabeled candidate and
   current-best images in shuffled order, and the reference panels — no iteration history,
   no description of what the change was meant to do. You (the orchestrator) record the
   label↔image mapping and unblind only after scores are returned. You may fan out
   additional per-slice critics in parallel; their outputs are *evidence* handed to the
   one deciding critic — the accept/reject verdict is always issued by a single
   fresh-context critic per candidate. For reference-resemblance categories the critique
   is a **blind A/B against the reference panels**: crop the left panels of the
   `reports/map_visual_gauntlet/hero_arinold/h*_triptych.png` triptychs (this evidence
   tree is local-only and gitignored — it exists on this machine; if it is missing, stop
   and ask the owner for the reference plates rather than substituting web images). The
   aesthetic canon is CLAUDE.md's WPA / mid-century cartography — Booth poverty maps,
   Sanborn fire-insurance sheets. The critic must say which reads better and why, at
   original resolution, before learning which image is which.
5. Accept only if a primary failing score rises with no material regression. Update the
   report (`reports/map_visual_gauntlet.md`) in the same format: iteration ID, gate/lever,
   change, status, evidence path, next bottleneck.
6. On acceptance of a **gate**, run the full §7 invariant suite and commit.
7. Two failed attempts on a mechanism → remove it completely, write the postmortem line,
   change abstraction.

## 7. Verification required for every accepted candidate

All commands from the Godot project root `price-of-everything-0.1/`:

- `python3 tools/run_tests.py` → all pass (≥2,260; add focused deterministic tests for any
  new geometry contract, as K1 did with the road-layout fixture).
- Two independent normal-GPU capture runs, byte-identical PNGs and metrics JSON.
- All-style harness (`res://tools/map_style_shot.tscn` — the round-trip, masked map-region
  assertion and repeated-wide comparison are all automatic parts of this one harness):
  classic, ink and plate wide captures unchanged from **your V0**; ink before vs after the
  legacy → midcentury → legacy round trip full-PNG identical; the masked map-region
  assertion passes; the repeated mid-century wide pair is identical.
- Road-frontage audit exactly at the frozen totals (§3.2, all eight counters including
  165 block-mode failures).
- At every **accepted gate checkpoint** (§6 step 6), additionally run the e2e balance sim
  once — `<godot> --headless --path . res://tests/e2e_stoneshore.tscn -- 100` — and
  confirm it is clean. A draw-only change must not perturb it; this keeps the gauntlet
  compliant with CLAUDE.md's full verification loop rather than silently narrowing it.
- Morphology hard gates (the F1 lesson, kept live): Capital ≥30% built, Silkstown ≥25%,
  ≥1,000 pre-rural urban blocks, at most one settlement with zero decorative built area,
  zero fills surviving the final dry-land guard, all seven water counters zero, relief
  counters zero. **Any new subtractive mechanism must ship with its own minimum-retention
  gate in the same run** — the harness must never again be able to accept visually empty
  cities.
- `git diff --check` clean; diff touches only draw-only/style/tooling files plus the
  report.

## 8. Known traps (paid for once already — do not pay again)

- The sandboxed Godot launch can crash rotating `user://logs` before startup; the standard
  permitted launch works. A sandbox crash is a runner failure, not a test failure.
- The already-open Godot editor can return control **before** a delegated capture scene
  finishes. Never trust launcher return; poll the completion timestamp of the harness's
  metrics JSON (each capture harness writes one — e.g. the hero harness writes
  `/tmp/poe_hero_arinold_metrics.json`; the exact path is declared in each harness's `.gd`
  source). This is the H2.11 stale-capture incident.
- An asynchronous relief bake could publish after a style change; a generation guard now
  prevents it — keep waiting on the matching renderer generation before capture.
- The visual harnesses need a rendering device; `--headless` produces null-image texture
  errors. Visual captures run windowed/normal GPU; only the unit suite and frontage audit
  are headless.
- Verify tile identity through `id_to_coord`, never hard-coded coordinates — the original
  Silkstown oracle pointed at the wrong tiles for days.
- If execution quota exhausts mid-iteration, do what S1.01 did: remove unverified renderer
  hooks, document the un-scored candidate in the report, and stop with the renderer at the
  last verified state. Never leave unproven code active.
- Godot draw order is sibling order — no `z_index` anywhere in the map layers.

## 9. Retired mechanisms — never retry any of these

| Mechanism | Verdict |
|---|---|
| Synthetic decorative core roads/spokes (V4.04) | Pale spokes competed with real roads |
| L-shaped frontage returns, both rates (V4.09a/b) | Repeated hook glyph |
| Single under-ellipse forest layer (V2.02) | Repeated central lozenge |
| Trunk centre stitch (V3.01) | Read as modern highway markings |
| Junction overpaint: bed circles / convex envelopes / tangent strokes (V3.03–05) | Buttons, degenerate triangulation, pale ticks — overpaint is dead as a class |
| Warped parcel lattice (H1.01–02) | Cells independent of the street graph; cannot cause road-bounded parcels |
| Staggered / T-branch alley cuts (H2.04–05) | Hook/tick glyphs or invisible |
| Promenade-fragmented greens (H2.08–09) | Read as miniature roads/rails |
| Broad industry-yard radii (P2.01) | Tan blankets; the compact P2.02 form is the accepted survivor |
| Sampled-river offset park boundaries (P3.01–02) | Offset-and-clip serration |
| Rare H/T/cross special masses (P4.02) | Effectively invisible — rejected as neutral |
| Internal-edge connector bands (C1.01–02) | Moves seams, cannot create a density field |
| Continuous density thresholds (D1.01–02) | Binary cliffs, metropolitan slabs |
| Road-catchment envelopes (C2.01–02) | Overlapping ribbons and shards |
| Cross-bank authored street pairs (S0.01) | Structural route failure |
| One-role-per-street-face zoning (S1.01) | Faces are not land-use parcels |
| Post-generation deletion/reordering for the density gradient (G1.02, five variants) | Breaks connected perimeter fabric |
| Gradient annex experiments: Tegan annex, second reconciliation pass, contiguous annexes (G1.02) | Neutral or moved the failure into a neighbour |
| Small-town subdivision-target shrink + density floor (K1 C–D attempt 1) | Passed numeric averages but still read as sparse oversized road fragments; superseded by the accepted compact frontage-row cores |
| Offset-band suburban fringe; independent road-chain branches (E1 rejects) | Abstract rings; relief-blocked |
| Broad face subtraction / face-level stroke for relief (pre-B1.01) | Erased districts |
| Fixed rectangle-and-shore-normal port primitive (K1-B) | Cannot adapt; superseded by the accepted L1 coastline search |

## 10. Out of scope

- Any gameplay change whatsoever — including the noted latent port-eligibility rule
  (`Catalog.is_building_allowed_on_tile_type()` has no coastal rule; that activates only
  if player-built ports are ever authorized, and not by this gauntlet).
- Changes to the classic, ink or plate renderers beyond byte-identity preservation.
- New mapmodes, UI panels, sim features, performance campaigns, content edits.
- Industrial-building placement transparency — deferred by F1 to a separate investigation;
  not part of this gauntlet.
- The accommodation/redevelopment map-wide 5–10-site target — status unchanged since K1;
  the existing accommodation planner stays as-is.
- Committing the evidence PNG tree.
- Tall junction-selected micro-cores and any *new* far-zoom silhouette layer — these were
  gauntlet I's "only after continuity succeeds" items and remain locked behind gates A–E.

## 11. Definition of done

The gauntlet passes when, in one final verified state:

- [ ] All 87 applicable tiles pass the +5pp road-density gradient (gate A), including Arin
      Old under the hero-replacement rule.
- [ ] All urban tiles are under 20% local exterior hex-coincidence (gate B).
- [ ] Zero settlement components fail any whole-body gate; Pepper Docks accepted by the
      critic (gate C).
- [ ] Junction casing stitching in place; no internal endpoint caps; linework coherence ≥4/5
      (gate D).
- [ ] Whole-map critique ≥4/5 in every category; fixed-slice scorecard has no applicable
      cell below 4 (gate E).
- [ ] Full suite passes; two-run byte-identical captures; legacy round-trip exact; frontage
      audit frozen; morphology and water/relief hard gates green; `git diff --check` clean.
- [ ] The report is updated through the final iteration and committed with the source.

Then stop. Do not open gate F polish or any new visual layer unless all of the above are
green and budget remains.

## 12. THIS IS THE MOST IMPORTANT PART

The prior gauntlet's discipline is the reason its failures are trustworthy. Keep it, and
keep it harsh:

- Fan out where the work is parallel (independent gate captures, per-slice critiques,
  reference A/Bs), but let **one** fresh-context critic own every accept/reject decision
  per candidate, exactly as before.
- The critic must compare **blind, side by side, at original resolution**: current best
  vs candidate, and candidate vs the reference panels. If the critic cannot honestly say
  the candidate reads more like an accumulated mid-century city plate than the current
  best does, the candidate is rejected — "metrics improved" is not acceptance.
- Loop per gate until its numeric requirement AND its critic bar are both met, or until
  two mechanisms have died honestly; then write down why and move to the next gate rather
  than grinding a third variant of a dead idea.
- Do not soften scores to make progress feel real. A 3 that stays a 3 is a 3 in the
  report. The previous gauntlet earned its credibility by recording every rejection —
  including its own accepted regression (F1). Match that standard.
