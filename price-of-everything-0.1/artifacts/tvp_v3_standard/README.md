# Tile view v3: the standard

The approved look of the tile view v3 (behind `toggle tvp v3`), saved as the benchmark on 26 September 2026 and tagged `tvp-v3-standard-2026-09-26`. Every visual change to the tile view is compared with these captures before it is shown to the owner, as Building Detail's are with `artifacts/bdp_v3_standard/` (`docs/ds2-theme.md` §9). `contact_sheet.png` shows them all at a glance.

All captures are the real HUD at 1920 × 1080, two pixels per logical pixel, cropped to the panel. They are regenerated with these commands, run windowed from the project root (`GODOT` is the Godot 4.6 binary):

| Views | Command |
|---|---|
| `tvp_v3_<tab>_busy_p1`, `_p2` … and `tvp_v3_<tab>_empty` for `bl`, `power`, `prod`, `stock`, `transport`: each tab on the busy port tile (Stoneshore Docks, three of your buildings, other companies' and a port, three turns run) a screen at a time down its whole body, then on an empty unowned mountain tile | `TVP_SHOT_DIR=<dir> TVP_SHOT_TABS=bl,power,prod,stock,transport $GODOT --path . res://tools/tvp_v3_shot.tscn --quit-after 40000 -- --no-telemetry` |
| `tvp_v3_land` (the land in full on the port tile, the default livery), `tvp_v3_land_yellow` (the same with a yellow livery: red planning tape), `tvp_v3_empty` and `tvp_v3_empty_land` (the mountain tile, fixed part and land in full) | `TVP_SHOT_DIR=<dir> $GODOT --path . res://tools/tvp_v3_shot.tscn --quit-after 40000 -- --no-telemetry` |
| `tvp_v3_power_nocables_p1` (your factory on a tile with no cables: "Cables missing"), `_producergrid_p1`, `_fedgrid_p1`, `_deficit_p1` (the national grid's sentences), `_green_p1` (firmed by batteries) | `TVP_SHOT_DIR=<dir> $GODOT --path . res://tools/tvp_v3_power_shot.tscn --quit-after 40000 -- --no-telemetry` |
| `tvp_v3_deposits_tile_*` (the fixed part on tiles with several deposits, surveyed and not) | `TVP_SHOT_DIR=<dir> $GODOT --path . res://tools/tvp_v3_deposits_shot.tscn --quit-after 20000 -- --no-telemetry` |

Each tab also has its own scenario tool with more cases (`tools/tvp_v3_<tab>_shot.tscn`), and Buildings a probe that checks its contract names and overlaps (`tools/tvp_v3_buildings_probe.tscn`).

Open at the time of saving (recorded in `docs/tile-view-ds2-plan.md`, Phase 4): Power 4 small gaps, Goods 3, Transport 4, and the owner questions listed there.
