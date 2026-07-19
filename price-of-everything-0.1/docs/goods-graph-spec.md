# Goods Graph — full-screen goods-web view

> **STATUS: Phase 1 + Phase 2 (alternates grid) BUILT** (branch `goods-graph`).

A full-screen, zoomable chart of the whole economy's goods web: every good as a card in
tier columns (raw sources left → finished goods right), connected by the input→output
flows of each good's **base recipe**. The in-game descendant of the offline
`scripts/build_goods_flow.py` chart (`docs/goods_flow_chart.html`), rebuilt live from the
Catalog so it can never go stale and can react to research state.

## The two forms (owner brief, 2026-07-18)

1. **Base web (Phase 1, built):** the whole graph drawn from each good's *simplest
   recipe available at game start*.
2. **Zoom / focus (Phase 2):** click into a good to see its alternate recipes and swap
   between them visually, re-drawing that good's incoming edges live.

## Data layer — `scripts/goods_flow_graph.gd`

Pure static builder (no scene access, no RNG — deterministic, headless-tested in
`tests/test_runner.gd::_test_goods_flow_graph`).

- **Defining recipe** per good: among producers with an empty `required_research`
  column (= available at game start), the **simplest** — fewest distinct inputs, then
  lowest `energy_req`, then smallest total input qty, then `recipe_id`. This is the
  deliberate inversion of the offline chart's least-efficient rule. A good whose every
  producer is gated falls back to the simplest gated recipe and is flagged `gated`
  (drawn dimmed).
- Primary output (`output_1`) producers are preferred; by-product-only goods fall back
  to any-output producers (same as the Python).
- **No external feedstocks:** catalog.gd's promotion gate already drops recipes that
  reference unknown goods, so every promoted recipe resolves — unlike the Python,
  which keeps dangling CSV names as dashed nodes.
- **Tiers** = longest path from a raw source; cycles (water ⇄ waste_water) break at
  their back-edge (GREY/BLACK DFS). Rows ordered per tier by 8 barycentre sweeps.
- Node records carry `alt_recipe_ids` (all other producers) — the Phase 2 candidates.

## View — `scripts/goods_graph_view.gd` + `scripts/goods_graph_world.gd`

- The view shell is a lifecycle clone of `empire_view.gd`: full-rect Control created in
  code by `world_map.gd` under `HUDContent` (node `GoodsGraphView`), driven entirely by
  `visible` (`_enter`/`_leave`: world-hide, camera `input_blocked`, `PanelStack`,
  rebuild-on-open), with the animated `empire_hex_bg.gd` backdrop behind it.
- The drawing layer differs from the empire view on purpose: **everything scales with
  zoom** (one `draw_set_transform` camera; cards, glyphs, icons, line widths all in
  world units) instead of fixed-pixel panels — the layout is static tier columns, so
  cards can't jostle and no separation pass / zoom floor is needed. The chart behaves
  like a zoomable document.
- Cards: navy plate, category accent stripe + border (`CAT_COLOR` mirrors the offline
  chart; blank categories fall back by `good_type`), good icon on a cream chip
  (`GoodIcons`), `+N` pill when the good has N alternate recipes, dimmed when `gated`.

## Layout & edge routing (owner spec 2026-07-18: orthogonal, minimal crossings)

Sugiyama-style, all computed once per `build()` (~400 ms, once per view-open):

- **Dummy vertices**: every edge spanning >1 tier gets an invisible dummy per
  intermediate tier; dummies occupy row slots (compressed to `DUMMY_ROW_H` = 40 vs
  `ROW_H` = 104 — full-height dummies made the layout ~3900 units tall and the fit
  view illegible) and form the corridor the edge runs through.
- **Ordering**: barycentre sweeps + transpose (adjacent-swap) + sifting rounds
  minimising the bilayer crossing count. Live count: **514** (unordered seed: 2093);
  the unit test asserts `< 600` as a canary — routine content growth may push it up,
  which is the signal to re-tune, not a code regression. Cycle back-edges are excluded
  from the bilayer model and routed in private corridors below the web.
- **Routing**: strictly axis-aligned waypoints per edge — right-edge exit stub →
  vertical lane in the inter-column channel → horizontal corridor across each dummy
  row → target's left-edge entry, with rounded quarter-arc corners (renderer fillets,
  r ≤ 10). Ports spread along card edges sorted by neighbour row.
- **Overlap guarantees** (unit-tested): vertical lanes in one channel with overlapping
  y-intervals sit ≥ 6 world units apart (≥ ~13 px at max zoom 2.2; the owner floor is
  5 px); x-overlapping horizontal runs of different edges ≥ 3–6 units apart via
  `_deconflict_horizontals` (corridors place first — they're rigid; port stubs walk
  around them). Known headroom: ≥ ~22 concurrent lanes in one channel would overflow
  the 136-unit gap (today's peak: 12 lanes, offset 103/112); the lane-separation test
  is the canary.
- **Rejected: radial layout.** The web has a strong global direction (raw → finished);
  radial fits ego-centric views, not flows — it is the right shape for Phase 2's
  focus mode instead.

## Banded columns (owner decision 2026-07-19: balancing-tier regions)

- **`goods_graph_tier` column added to goodsMVP** (raw/processed/intermediate/
  finished/apex; parsed by catalog.gd, validated in the suite). Sizes 20/20/20/9/7.
  Owner moves applied: lithium_carbonate + industrial_acids -> processed, concrete +
  fertilisers -> intermediate, oxygen -> processed (its base recipe is electrolysis).
- **Columns = bands** with 1-3 INVISIBLE sub-columns (no headers): sub-column = the
  good's longest same-band base chain (processed needs 3: chlorine -> acids ->
  lithium carbonate); RAW has no internal edges and splits in half for height.
  10 physical columns; ONE Bebas plate per band centred over its region. Crossings
  638 (< 900 canary). Invariant (unit-tested): no base edge flows backward across
  bands — zero by construction of the authored mapping.
- **r_231 Anthracite Graphitisation** (owner ask): eaf, 45 coal -> 2 graphite,
  160 MW, ungated, value-add +GBP0.14 (band -5..+5). Being 1-input and lower-energy
  than pet-coke calcination it becomes graphite's DEFINING base route: the web shows
  coal -> graphite; pet-coke and gated bio routes sit in the alternates grid.
  Owner flagged: energy 260 would flip pet-coke back to base. Evidence: suite green,
  e2e failure set unchanged (599/12).
- **Encyclopedia**: good entries show "Tier: <Band>" beside the title.

## Polish batch (2026-07-19, fifth): search + card hover

- **Good search (WEB mode only)**: styled LineEdit top-left (the grid's Back-button
  slot — never visible together). Min 3 letters, case-insensitive plain substring
  (`GoodsFlowGraph.search_goods`, ranked match-position → name length → name),
  dropdown of top 3 names (no icons). Click zooms to the good (>=0.75) and selects
  it; **Enter auto-picks when exactly one good matches the full list** (not top-3).
  WASD panning suspended while the box has focus; canvas click releases focus.
- **Grid output card**: 533 wide ((CARD_W+30)*1.3); the building NAME is hover-only
  (tooltip pill over the building icon), no caption on the card; good name may wrap
  to 2 lines.
- **Encyclopedia (search_overlay)**: Esc closes in ONE press — `_input` intercepts
  before the focused LineEdit can eat the first press (the old `_unhandled_input`
  path needed two); clicking the dim backdrop outside the bar/panel closes it.

## Polish batch (2026-07-19, fourth): full attachment constraints

- **Constraint generalisation**: every span attachment (port stubs AND corridor
  attachments — a corridor entering a channel from the left column has exactly an
  exit stub's geometry) now feeds the vertical-constraint digraph. Real crossings:
  988 (heuristic) → 834 (stub constraints) → **632** (full attachments);
  steel-touching 209 → 97, motor 156 → 70. Remaining crossings are chain-level
  (row-ordering floor) or broken constraint cycles.
- Grid output card +30 wider; good name wraps to 2 lines (clipped before the
  building icon), building caption anchored at the card bottom.
- **BDP status-rail power icon**: was the black `power_status_icon.png` stencil
  tinted ICON_TINT (status lives on the DOT, not the icon) — swapped to the
  tile-view panel's outlined yellow `recipe_power_icon.png`, untinted, per owner.
  The other three status pictograms stay tinted stencils.

## Polish batch (2026-07-19, third): constraint routing + grid detail

- **Vertical-constraint lane ordering** (upgrade over the nesting heuristic): per
  channel, a digraph orders spans — covering another edge's exit-stub y forces you
  right of it, covering an entry-stub y forces you left; Kahn's topo order with
  deterministic cycle-breaking, then greedy lane reuse honouring predecessor lanes.
  Measured REAL crossings (H-vs-V segment intersections between different edges):
  988 → 834 total; edges touching steel 209 → 141, motor 156 → 118. Residual
  crossings are bilayer-level (chains genuinely crossing) or broken-cycle cases.
- **Grid output cards** +30 units tall: carry the recipe's BUILDING (name caption +
  `BuildingIcon.clean_texture` art on the right edge, mirroring the goods chip's
  offsets). The arrow is a navy band that CARRIES the power draw (bolt + MW label,
  5-unit padding), gold arrowhead into the card; fuel-less recipes keep a slim arrow.
- **kW → MW relabel everywhere** (numbers unchanged): building_detail_panel_v2,
  building_readout, recipe_diagram, goods graph — consistent with the victory
  tracks, which already call the same quantities MW.
- Power goods icons: import params verified identical to the other goods icons
  (mipmaps on, same compression) — already correct.

## Polish batch (2026-07-19, second): lane nesting + grid alignment

- **Lane nesting rule** (the "disentangle" ask): per-channel lane assignment now
  processes spans SHORTEST-FIRST (VLSI channel-routing nesting / staircase rule)
  instead of by interval start — a fan leaving one card opens as a staircase, no
  longer weaving over its own siblings. Lane-reuse correctness is order-independent
  (reuse requires the lane clear before the span starts).
- Grid: row-major with uniform row heights (titles align per row); qty pills ride
  the icon chip's bottom-right corner (recipe-diagram treatment); "requires
  research" caption in white; Back button cleared below the top bar (+20 px).
- Balance CHANGE (owner-directed 2026-07-19, protocol followed): the three acid
  recipes moved into a +£5..+£15 standalone value-add band (they were −£17.3 /
  +£83.8 / +£61.3). r_114 Hydrochloric output 45→24 (+£10.9; inputs untouched —
  hydrogen cost makes output 20 a loss), r_115 Sulphuric sulphur 21→36 + output
  3→16 (+£13.3), r_116 Generic output 36→20 (+£5.8). Evidence: unit suite green,
  e2e failure set unchanged (599/12), sweep N/A (harness not built). Note:
  base_output_for_good(industrial_acids) drops 45→24, shifting its price-impact
  thresholds. r_083 ELYSIS checked and left alone: fewer units/run than
  Hall-Héroult (15 vs 20) but higher value-add (+£51.5 vs +£42.2), less energy,
  no graphite — a working researched upgrade. flow_battery/medical_components
  unpriced: owner confirms not in game yet.

## Phase 2 BUILT — alternate-recipes UX (owner decision 2026-07-19, option 4)

The colour web was retired after one day: alternates now live in a per-good
minigraph grid, and the resting web is the clean BASE chain again (all yellow,
140 edges, 514 crossings; gated-only goods dash; power keeps its fuel union).

- **Selecting a good** expands its card with an action tray (min ~34 px buttons at
  any zoom — tray world-size scales inversely below 0.77 zoom, same rects used for
  hit-testing): **"See alternate recipes"** (only when alternates exist) and
  **"Encyclopedia entry"**.
- **The grid**: one island per producing recipe (defining first, ungated before
  gated, cap 5) — Bebas recipe-name header, lock + "requires research: <title>" when
  gated, input mini-cards with qty pills, arrow with the canonical power bolt + kW,
  and a full-size copy of the good with its per-recipe output qty. No separators,
  just space; 1 column for <=3 recipes, 2 for 4-5. Same pan/zoom camera, fitted on
  entry; a real **"Back to Goods Graph"** Button (top-LEFT — top-centre belongs to
  the briefing notch) restores the saved web camera.
- **Encyclopedia deep-link**: `SearchOverlay.open_encyclopedia_good(good_id)` (new)
  via `MatchState.encyclopedia_good_requested`, opening the good's Produced-by /
  Used-in page over the graph (PanelStack LIFO).
- Data: `GoodsFlowGraph.routes_for_good(internal)` queries the Catalog live,
  simplest-first, ungated-before-gated, defining == routes[0].
- Trace unchanged from the base-cone fix: canonical chain + all routes at the
  selection itself.

## Visual pass 3b (owner tweaks 2026-07-18, fourth batch)

- **Channel doubled**: COL_W 820 (channel 440), LANE_PAD 24, LANE_GAP_MAX 26 — the
  inter-column cramping fix.
- **Trace = base chain**: the upstream cone walks `base_inputs` (route-0 edges only)
  and cone-lighting applies to route-0 edges; every route still lights where it
  touches the selection itself. Fixes selecting iron ingots lighting ammonia /
  waste water through the gated hydrogen-DRI alternate's transitive closure.
- **OPEN QUESTION (owner)**: how alternates should ultimately be shown — the
  always-on colour web reads dense. Candidates: encyclopedia deep-link on select;
  isolate-on-select (show only the selected good's chains); multi-select compare
  list; per-recipe minigraph explosion (one card copy per producing recipe).
  Direction not yet chosen; the colour web ships meanwhile.

## Visual pass 3 (owner tweaks 2026-07-18, third batch) — multi-route colours

- **Cards 380×112** (another +30% width): name text fits; the lock tag sits at the
  card's RIGHT edge (vertically centred), alt pill just left of it.
- **Route-coloured edges**: every producing route draws — route 0 (yellow) is the
  defining base recipe, alternates take blue/green/purple in simplest-first order
  (ungated before gated); **research-gated routes render dashed**. An alternate only
  consumes a colour if it contributes a new edge (power's duplicate oil plants don't
  burn the palette — its coal/oil/pet-coke spread now falls out naturally, replacing
  the old power special-case). 201 edges, capped at 4 coloured routes per good
  (`+N` pill still counts the rest). This made the gated Bio-Graphitisation
  (carbonised_biomass → graphite, r_042) visible as a dashed alternate, answering
  the owner's "isn't that a recipe already?" — it is, gated behind Biomass Cracking.
- **Tiers layer on the BASE skeleton only** (route-0 edges): tiering on all routes
  blew the chart from 7 to 15 columns. Lateral/backward alternates ride the
  below-web corridors like cycle edges. Tier-0 test now asserts "no BASE-route
  inputs" (recycling alternates may legitimately feed a raw good).
- **Overlap root cause (owner: "why does this keep happening?")**: separations are
  CENTRELINE distances; 3-unit strokes (4.8 when traced) ate nearly all of a 6-unit
  gap at max zoom, and same-radius fillets pinch parallel corners. Fixes: channel
  220 (COL_W 600), LANE_GAP_MIN 12, H_SEP 12 / sibling 9, stroke 2.5 (trace ×1.3),
  DUMMY_ROW_H 72 / CORRIDOR_LIMIT 30. Also a REAL bug: the deconfliction conflict
  prefilter had a stale hardcoded 60-unit window sized for the original ±24 port
  band — once nudges reached ±52 it placed runs blind onto unseen neighbours; the
  window now derives from PORT_LIMIT. Crossings canary: 961 < 1400.

## Visual pass 2 (owner tweaks 2026-07-18, second batch)

- **Cards 292×112** (was 224×56): icon chips are 100 world units, so exactly ~100 px
  at maximum zoom-in (`_ZOOM_MAX` = 1.0, was 2.2); chips load MEDIUM icon art.
- **Zoom-out capped at the fit zoom** (`_zoom_floor` = fit-whole-graph, recomputed on
  resize) — you cannot zoom past the graph.
- **Tier headers**: Bebas Neue 38 on octagonal brushed-silver plates (machined-silver
  family, top-left lit, streaked, bevelled), with widened clearance above the top row.
- **Hex backdrop**: per-view `line_width` override on `empire_hex_bg.gd` (goods graph
  runs 1.0 vs the empire view's 1.5 default) + modulate 0.24.
- **Gated cards**: rest dimmed ×0.6 with a gold padlock tag; while part of an active
  trace they render FULL alpha (the lock alone carries "research-gated"), so
  transparency never means two things. (The "transparent lithium battery" question:
  every lithium-battery producer is research-gated — r_032/r_099 — so its card was
  legitimately dimmed; now it lights up in traces and wears the lock.)
- **Deconfliction hardening** for the larger geometry: DUMMY_ROW_H 64 / CORRIDOR_LIMIT
  26, the conflict-prefilter window derives from PORT_LIMIT (a stale hardcoded 60
  blinded the walk once nudge ranges doubled — real bug), and exhaustion now takes the
  least-bad candidate (max worst-clearance) instead of the base y. Floors: verticals
  ≥ 9 units; horizontals target 9 (siblings 7) with a tested floor of 5.9 units =
  > 5 px at max zoom (the owner floor).
- **Canonical power icon**: the TVP bolt (`recipe_power_icon.png` colours, 512px
  `power_status_icon.png` silhouette) baked as goods icons — `g_010_power` (yellow),
  `g_077_green_power` (green), `g_078_grey_power` (silver), medium+small. The old
  g_077/g_078 art was an unkeyed 3-bolt sprite sheet. Every GoodIcons surface
  (graph, encyclopedia, market rows) now shows the bolt for power goods.

## Data addendum (2026-07-18)

- **Silicon chain**: added `r_229 CZ Monocrystal Growth` (chem_plant, 3 polysilicon →
  2 high_grade_silicon) and `r_230 Monocrystal CPU Fabbing` (assembly_plant,
  2 HG Si + 8 circuit_board + 3 refined_ree → 5 cpu), both ungated, peer-modelled,
  additive (r_122 met-Si fabbing survives as an alternate). high_grade_silicon was a
  never-produced good before this. Class: content addition; e2e failure set unchanged.
- **Power union**: power's edges are the union of every game-start power recipe's
  inputs (coal, pure_water, processed_oil, pet_coke) — the "simplest" rule alone
  picked fuel-less wind and erased the carbon-choice flows. Falls back to the chosen
  recipe if every producer is gated.
- **Solar**: base r_058 keeps metallurgical_silicon; the three research routes
  (Perovskite/Heterojunction/Tandem) all use polysilicon — visible in Phase 2's swap
  view per the owner's "unless there's multiple recipes".
- **Tracing:** hover highlights a good's direct flows; click selects and lights the
  whole upstream supply cone (gold) plus direct consumers (steel-blue), dimming the
  rest. Click empty space / the good again to clear. `select_good(internal)` is the
  programmatic hook (screenshot tool, future deep links).

## Entry points

- **G** — `toggle_goods_graph` input action, handled in `world_map._input` beside the
  empire view's Tab (same text-entry guard). **Shortcut remap that made room:**
  Resources moved G→**R**, Research moved R→**T** (`bottom_menu._MENU_SHORTCUTS`).
- **Top bar** — `GoodsGraphModule` (`top_bar.gd::_build_goods_graph`, `_WebIcon` glyph),
  immediately left of the Encyclopedia module.
- **Resources panel** — a "Goods Graph" header button (`resource_panel.gd`).
- All three route through `MatchState.goods_graph_requested` / the action; the view
  toggles. Stacking with the empire view is LIFO via PanelStack (Esc closes topmost);
  the world-hide lists are independent, so restore order is safe.

## Verify

```bash
python3 tools/run_tests.py                       # includes _test_goods_flow_graph
<godot> --path . res://tools/goods_graph_shot.tscn --quit-after 600
#   → res://goods_graph_shot.png (full web) + goods_graph_trace.png (steel traced)
```

## Phase 2 (next)

Click-zoom focus mode: side panel listing every producing recipe as
`DS.recipe_diagram_for` cards (reusing the encyclopedia's "Produced by" enumeration),
hover-preview of an alternate's input edges (dashed), click to commit the swap into a
session-local `selected_recipe_per_good` (view-only state — no sim mutation, no save
key). Research-gated alternates greyed with the `required_research` title. Phase 3
options: live-research mode, ownership badges bridging toward the empire view.
