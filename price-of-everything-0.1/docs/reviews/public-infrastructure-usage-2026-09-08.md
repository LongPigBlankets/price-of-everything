# Public infrastructure throughput

The infrastructure overview has no ownership filter: active_links enumerates
route-flow keys, and its click action can focus NPC buildings or terrain-only
infrastructure. Two other issues made public links look unused:

* The fastest-path router tried bare ground before rail/road for solids. A
  single-tile destination was claimed by bare ground even with a rail connection,
  so the route contained no capped infrastructure leg. Installed infrastructure
  now wins equal-time routes. Pipe preference for fluids and the fastest-path
  objective remain in place. Freight prices and congestion attribution follow the
  chosen mode; short solid trips can become cheaper when they correctly use rail.
* Tile infrastructure dials read the live pending-shipment list, whereas the
  overview and building breakdown read the pre-arrival snapshot. Completed
  one-turn shipments disappeared from the dial. All infrastructure readouts now
  use the settled snapshot, retained through save/load. Older saves fall back to
  reconstructed pending routes until their first settled snapshot is captured.

The overview still filters by transport type: the supplied screenshot has Roads
selected, so rail and pipe traffic belongs to the other tabs.

Validation: the new unit regression uses rail on two adjacent tiles without any
owned buildings. It verifies rail routing, 75 units after arrival, two overview
rows, save/reload persistence, and zero usage on the next idle turn. The windowed
public_infra_check scene also checks the actual tile-view data and renders both
rail rows to /tmp/public-infra-panel.png. The unit suite passed 3864 checks and
the 100-turn end-to-end simulation passed 723 checks.
