# Fluids by road and rail

Owner ruling, 9 August 2026. Closes the P5 item "Fluids by road and rail" from
`notes-for-9th-aug.md`. **Mechanic change** — see `.claude/skills/cnc-balance-change-control`.

## Intent

Liquids and gases could only ever move through pipework. A fluid with no pipe to its destination
was simply stuck, which made a whole class of build order impossible rather than expensive. They
can now go overland, priced so that laying the pipe is still obviously the right answer.

## The numbers

Multipliers are against the **pipe cost for the same good** (pipes are 1.0 in
`TRANSPORT_MODE_COST_MULT`), so they scale the full two-part freight rate — the flat
weight-class leg *and* the ad-valorem leg. That is deliberate: a tanker's insurance scales with
what is in it, exactly as the pipe's does not.

| | ordinary fluid | hazardous fluid |
|---|---|---|
| **Rail** | 3× | 5× |
| **Road** | 6× | 10× |

`EconomyConfig.FLUID_OVERLAND_COST_MULT`. Road is twice rail, matching the 0.5 rail multiplier
solids already get. The hazard split is the same one the pipes make: `hazard_liquid` is the one
class ordinary pipework refuses, and it is the class that pays the higher overland rate.

## Routing: pipes first, explicitly

The router is **fastest-first** (`catalog._route_uncached`, unit-weight BFS) and rail out-ranges
pipe 4 tiles to 2. Left alone, every fluid shipment would have deserted a perfectly good pipe
network for the nearest railhead and quietly cost 3–5× more — the opposite of the intent, and a
silent bill for every player who had already built pipes.

So `_route_uncached` now runs a **pipe-only pass first** for fluids and only falls back to the
full mode set when no pipe path exists. `_bfs_route` was split out of it to make that possible.
Consequence worth knowing: this makes the change **strictly additive**. A route that worked before
routes and costs exactly as it did; the new multipliers only ever apply where the good previously
could not move at all. The e2e's headline metrics are byte-identical before and after
(money 29793.36, revenue 78358.41, profit 8440.34, same infra upgrades) for precisely that reason.

Fluids still do **not** get the `ROUTE_MODE_NONE` off-network straight-line haul that solids have.
No link at all still means stranded, so `INF_TURNS` and the "unreachable routes cost nothing"
guard both stay live — they are just hit far less often.

## What else moved

- `data/infrastructure.csv` — `roads` and `rail` now tolerate `safe_liquid|hazard_liquid|liquid|gas`.
  This is the actual gate; everything downstream (`_modes_for_good`, `tile_can_pipe_good`, the
  "needs pipework" UI warnings, market-buy blocking) follows from it automatically.
- `MatchState.tile_mode_flow` — a leg-less fluid shipment is attributed to its **pipe** network
  only. Roads and rail tolerating fluids would otherwise have loaded both networks from one
  delivery and charged tile congestion twice.

## Blast radius — read before shipping

Eleven existing assertions encoded "fluids move by pipe only" as an invariant, across market
buys, tile moves, market sales, construction diagnostics and routing. They were rewritten to the
new contract, not deleted:

- Where "no pipeline" was tested using tiles that happen to carry a road in the CSV baseline, the
  test now strips the tile back to bare ground first — so it tests the rule it claims (no link at
  all → still stranded) rather than the map's furniture.
- New assertions cover the other half: rail-only tiles carry both fluid kinds, and a railed port
  tile with no pipework can land them.

**The part that most wants a playtest** is port logistics. A fluid can now be market-bought onto
any railed or roaded port tile, where before it needed the pipe. That is what the ruling says, and
the cost multipliers are what keep it honest, but it is a real change to how a coastal start
plays, and no amount of green tests substitutes for playing it.
