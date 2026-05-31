# Transport routing plan — multi-modal shortest path

Status: PLAN (awaiting approval). Data layer landed in commit a098c6e
(`Catalog.infra_range/all_infrastructure`, infrastructure.csv ranges).

## Goal
Move goods from tile A to tile B choosing the path + modes that minimise
**turns**. Modes: `nothing` (overland), `roads`, `rail`, `sea` (via ports).

## The cost model (the key rule)
- Cost is measured in **turns**.
- Each turn you travel on **one** mode, along that mode's connected network, up
  to that mode's `range` tiles.
- **You cannot switch modes within a turn.** Switching ends the current turn,
  and any unused range is wasted. (Board rail (range 4), go 2 tiles, switch to
  road → the rail leg still cost 1 whole turn.)
- Therefore: total turns = number of "turn-moves", where each turn-move is one
  contiguous single-mode hop of `1..range` tiles.

## Speeds (tiles/turn, from infrastructure.csv `range`)
| mode | range | network |
|------|-------|---------|
| nothing | **TBD (propose 1)** | any land tile ↔ its 6 hex neighbours |
| roads | 2 | tiles with `roads`, connected by shared road edges |
| rail | 4 | tiles with rail, connected by shared rail edges |
| sea | special | ports as entry/exit; port→port = 2 turns; port→coastal tile = 1 turn if ≤10 sea-route tiles |

## Algorithm — Dijkstra over turn-moves
1. **Build mode networks** from tile data (once per map / on infra change):
   adjacency lists for roads, rail, sea; `nothing` is the full hex grid.
2. **Turn-move expansion**: from tile X, for each mode M usable at X, BFS up to
   `range[M]` hops on M's network → every reachable tile is a **1-turn-away**
   neighbour of X. Sea contributes special edges (port→port cost 2, port→coastal
   ≤10 cost 1).
3. **Dijkstra** from A minimising summed turn-cost to B (uniform 1 per land
   turn-move, 2 for port→port — so Dijkstra, not plain BFS).
4. Return `{turns, path: [tile...], legs: [{mode, tiles}...]}` for the transport
   queue (turns) and the marching ants (path + per-leg mode).

State can stay as plain `tile` (not `(tile, mode)`) because the no-switch rule is
captured by "each turn-move is one mode" — leftover range is never carried across
a switch, which is exactly the per-turn-move expansion in step 2.

## Eligibility by good
A mode is only usable for a good if the good's `transport_class` is in that
infra's `good_types_tolerated` (e.g. solids on road/rail, `hazard_liquid` only
on reinf_pipes/port). `nothing` carries anything. Pipes/reinf_pipes (gas/liquid)
are a parallel network — same algorithm, gated by `good_types_tolerated`.

## Integration points
- Replace `production.gd::_transport_route` (currently `hex_dist / 2` flat) with
  the router; it returns turns + path.
- Sales (`_sell_output_to_market`, `_sell_stockpile_totals`) and inter-tile
  dispatch use the router's turns.
- `building_connection_visuals` marching ants follow the returned `path`
  (optionally colour each leg by mode) instead of a straight line.
- `building_detail` "Duration to destination" uses router turns.

## Phasing
- **P1** Land router (nothing/roads/rail), Dijkstra over turn-moves. Single-path test.
- **P2** Sea integration (ports, port→port 2 turns, coastal ≤10 = 1 turn).
- **P3** Marching ants follow the actual path + per-leg mode colour.
- **P4** Capacity/cost layer (`soft_capacity`, `cost_per_unit_shipped`,
  `double_cost_types`) — affects money, optionally tie-breaks equal-turn paths.

## Decisions (confirmed)
- **Objective**: variable FASTEST / CHEAPEST / BLENDED (50% fast, 50% cheap),
  default FASTEST. Lives in `MatchState.route_objective`, set via the building
  ledger's first-section dropdown. ✅ DONE (commit 4a875eb).
- **`nothing` speed**: 1 tile/turn.
- **Rail**: connectivity = the rail icon being present on the tile (presence +
  adjacency). HSM-edge rail later.
- **Pipes/reinf_pipes**: out of scope for now.
- **0-turn shipment**: only same-tile (source == dest → 0 turns).
- **No same-turn chaining**: the instant same-tile shipment must NOT let a good
  produced this turn be consumed by another building the same turn (can't
  produce A → ship A → produce B-from-A in one turn). Production consumes only
  start-of-turn stock; this turn's outputs become consumable next turn. It's
  instant *shipment*, not instant *multi-step production*.

- **In-transit shipments keep their route.** A shipment commits its path + delivery
  time when first dispatched; building new infra only affects *future* shipments
  (the router reads live infra via `Catalog.add_tile_infrastructure`). This is fine
  in practice — but EDGE CASE: if infra a shipment is mid-journey on gets demolished,
  the shipment still "rides" the now-deleted route. Acceptable for now; revisit if
  demolition-mid-transit becomes common (would need in-flight re-routing).

## Remaining build (next)
1. Catalog: load per-tile `infrastructure_present` (roads/rail) — static CSV for
   the single-path test; live/player-built infra wiring later.
2. `Catalog.route(source, dest, good_id) -> {turns, cost, path}` — Dijkstra over
   turn-moves; modes nothing(1)/roads(2)/rail(4); 0-turn same-tile; objective-aware
   (`MatchState.route_objective`).
3. Integrate into `production._transport_route` + building-detail route summary.
4. No-chaining: buffer this-turn outputs; merge into the stockpile after the
   production passes, before the sell phase.
5. Follow-ups: sea (ports, port→port = 2 turns, coastal ≤10 = 1 turn);
   cheapest/blended cost tuning (needs `cost_per_unit_shipped`); ants follow the path.
