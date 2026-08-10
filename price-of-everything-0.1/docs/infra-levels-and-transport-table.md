# Infrastructure levels change reach — and a scoped goods transport table

Owner ruling, 9 August 2026. **Mechanic + balance change** (`cnc-balance-change-control`).

## What shipped

Until now no infrastructure level changed anything but throughput; a level-3 pipe delivered at
exactly the speed of a level-1 one. Levels now set how far one turn-move reaches:

| mode | L1 | L2 | L3 |
|---|---|---|---|
| roads | 2 | 3 | 5 |
| rail | 4 | 6 | 9 |
| pipes | 2 | 3 | 5 |
| reinforced pipes | 2 | 3 | 5 |
| port | 10 | 16 | 25 |

`EconomyConfig.INFRA_RANGE_BY_LEVEL`. Level 1 equals the flat `range` column in
`infrastructure.csv`, which stays the fallback for any mode with no table — asserted, so an
un-upgraded tile cannot silently change behaviour.

**Range is not only speed.** Freight is charged per leg and a leg is one turn-move, so range also
sets cost: a 9-tile rail haul is 3 legs at L1 and 1 leg at L3 — **a third of the freight for the
same cargo**. These numbers are a deliberate long-haul discount as much as a speed-up, and the
e2e moved accordingly (below).

## The plumbing problem, and how it was solved

`Catalog` owns routing and is deliberately map-independent — it routes on tile ids, headless, in
the hottest loop in pathfinding. Levels lived only on the HexMap tile dict, reachable through
`MatchState._tile_infra_level()`, which **returns 1 whenever there is no map node** — i.e. in
every unit test and the entire e2e balance harness. Wiring the router to that would have left the
harness blind to the change and coupled pathfinding to the scene tree.

So `Catalog` now keeps its own `_tile_infra_levels` mirror, written by:

- `MatchState.set_tile_infra_level` — the single runtime writer (upgrade completion). The mirror
  is written **before** the tree/hex-map early-outs, so a headless caller still routes correctly.
- `SaveLoad._apply_infrastructure` — a loaded save seeds it, or every route would solve at L1.
- `SaveLoad._clear_scene_infrastructure` → `Catalog.clear_tile_infrastructure_levels()`.

A level change clears the route cache exactly as laying new infrastructure does.

**Reach is taken from the DEPARTURE tile's level** — it is the link you are getting on, it is one
lookup rather than a scan of the whole run, and it means upgrading the tile you ship *from*
visibly pays. A mixed-level chain therefore moves in the steps its origin allows.

## Does pipe stay cheapest? Measured, not assumed

Cost for a fluid ∝ `multiplier x ceil(distance / range)`. Swept over every level pairing and
distances 1–30:

- **Roads never beat pipe. Anywhere.** The 6× tanker premium is too steep at any level.
- **At matched levels pipe wins at every distance** — the case a player who upgrades evenly is in.
- **One exception: a level-1 pipe against level-3 rail.** Rail's 9-vs-2 range advantage (4.5×)
  finally beats the 3× premium; rail is strictly cheaper at 21 of the 30 distances.
  L1-pipe-vs-L2-rail and L2-pipe-vs-L3-rail tie at some distances but never lose.

So: **pipe stays the cheapest way to move a fluid provided the pipe network is not left two full
levels behind the rail network.** All three findings are locked in
`_test_infra_level_ranges` so nobody has to re-derive them.

⚠️ **Live consequence worth a decision.** `_route_uncached` prefers pipes *unconditionally*, so in
that one L1-pipe/L3-rail case the game routes down the **dearer** pipe. It is a known trade, not a
bug, and the honest fixes are either a cost-aware router (the empty `cost_per_unit_shipped` column
is the seam) or nudging pipe L1 to range 3, which closes the gap without touching the solver.

## Sea versus pipes for fluids

They are not competing. Ports are `market_connector: true` / `via_sea` and charge **ad valorem**
(3% of value after t30, half on owned ports), not the per-leg class rate. Sea is how you reach the
**market**; pipes are how you move between **your own tiles**. The only place they meet is getting
product to the port, and there pipe-to-port still beats rail-to-port by the ratios above. Port
range 10→25 changes how far inland a port reaches, not whether sea competes with pipe.

## Evidence

Unit **2128 passed / 0 failed** (11 new assertions). E2E **748 passed / 0 failed**, metrics moved
in the predicted direction because the scenario upgrades pipes and rail mid-run and those upgrades
now shorten routes:

| | before | after |
|---|---|---|
| money | 29793.36 | **30275.07** (+1.6%) |
| cumulative revenue | 78358.41 | 78393.25 (+0.04%) |
| profit post-tax | 8440.34 | **8618.05** (+2.1%) |

Revenue barely moved and profit moved 2%, which is the signature of a pure cost saving rather than
a production change — exactly what a freight discount should look like. Archetype sweep **N/A —
harness not built**.

---

# Scoped, not built: preferred transport per good

A read-only table in the Resources panel showing, for each good, the order the router will try.

**Derive it; do not add a CSV column.** Preference today is a pure function of `transport_class`:
fluids try pipes/reinforced pipes, then rail, then road; solids try rail, then road. A
`preferred_transport` column would be a second source of truth that can disagree with the router —
the exact drift that put five private copies of one grey into the UI. A
`Catalog.preferred_modes_for_good(good_id) -> Array` reading `_modes_for_good` plus the fluid
pipe-first rule is the whole data layer.

**Sim: already done.** The pipe-first pass and the `rail → roads` ordering are live. The table only
reports them. Nothing to wire, nothing to balance.

**UI.** Resources is 58 lines — a genuine minnow, and the right home, since goods movement belongs
with goods. Add a `TabContainer` with the existing list as "Goods" and a new "Transport" tab:

| column | source |
|---|---|
| Good | `Catalog.get_display_name` |
| Class | `get_transport_class` |
| Route order | `preferred_modes_for_good`, as chips |
| Cost vs pipe | `fluid_overland_mult` / `TRANSPORT_MODE_COST_MULT` — the number that *explains* the order |

Read-only, built once on show, coalesced refresh, DS `Card`/`Caption` variations. Risk is near
zero: it renders derived facts and mutates nothing.

**Sequence it after the export.** It is explanatory UI for mechanics that only landed today, and
the thing those mechanics most need first is a playtest, not a table describing them.
