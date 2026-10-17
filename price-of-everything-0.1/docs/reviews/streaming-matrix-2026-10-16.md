# Visibility and read-ahead trial — 16 October 2026

Recommendation: advance the visibility policy plus bounded read-ahead to a production integration pass. Keep rear-of-view far LOD as a separate visual experiment. Keep collision-file separation and finer per-object LOD selection out of this first matrix.

This is an opt-in tool experiment. Shipped runtime scripts, regular-map behaviour, production bakes and source fingerprints are unchanged. The installed package remains 968,604,879 bytes. No rebake or export-format migration was needed.

## Policies

- **Baseline:** existing screen bounds and buffer; closest detail requests all 61 tiles in the four-ring neighbourhood, including off-screen tiles.
- **Visibility:** construct local detail only for tiles whose conservative, height-aware projected bounds intersect the view. Keep a 40-pixel safety guard inherited from the existing visibility test. Use a 20%-per-edge margin for bounded idle prefetch, with up to eight candidates and two attempts per idle pass. This margin makes the rectangle 140% of viewport width and height. Speculative resource loading does not create scene nodes. Final trial prefetch uses the current terrain tier, including near detail. Existing ten-second retention, nearby protection and memory admission rules remain in force.
- **Queue:** request native terrain resources for the current tile and at most two forthcoming tiles while scene work continues. Cap in-flight requests at nine and compressed file sizes at 16 MiB. These are scheduling caps, not a decoded RAM guarantee. The measured final peak was six requests / 3,055,006 compressed bytes. Artwork still uses the existing bounded loader. Drain every issued request on a camera change; do not construct scenes for obsolete queued requests.
- **Combined:** visibility plus queue.
- **Rear:** visibility plus the existing far continent representation for tiles wholly in the top 35% of shallow medium views, beyond the immediate focus neighbourhood. Only enabled below 0.45 radians pitch and after the far backdrop is ready. This is a conservative screen-region experiment, not perspective distance LOD or a full per-object LOD implementation.

An early queue prototype checked only ResourceLoader's cache. The game retains decoded dictionaries after their outer resource wrappers are released, so that prototype redundantly reread retained terrain. The corrected queue checks the game's terrain, chunk and retained caches first. Final return-pan validation explicitly requires zero read-ahead reads.

## Measurements

Godot 4.6.2, Forward+/Metal, Apple M5 Pro, 1920×1080 window. Ten completed fresh-process runs, sequentially; filesystem caches are warm. Four initial combinations, a reverse-order round with explicit idle prefetch, a separate rear trial, and a final corrected combined run with additional edge checks. A discarded harness setup attempt replaced the board script during active background work; the fixed harness installs the trial script before the board's `_ready` runs.

Times below are complete detail settlement, not the time until the first usable far backdrop. Baseline shows the range of its two runs; other columns use the later visibility run, corrected queue run and final combined run. They are individual observations rather than statistical confidence intervals. The two rounds differ in explicit idle prefetch; retained resource differences and machine variability affect later stages. Read raw reports before comparing small percentage differences.

| Scenario | Baseline range | Visibility | Queue | Combined |
|---|---:|---:|---:|---:|
| Closest first detail | 2,881–3,703 ms | 518 ms | 2,330 ms | **359 ms** |
| Closest adjacent pan | 432–530 ms | 288 ms | 408 ms | **248 ms** |
| Closest retained return | 502–603 ms | 94 ms | 523 ms | **82 ms** |
| First shallow medium view | 1,801–1,953 ms | 2,521 ms | 1,616 ms | **1,819 ms** |
| Medium adjacent pan | 737–745 ms | 751 ms | 845 ms | **617 ms** |
| Shallow quarter-turn | 1,611–1,758 ms | 1,270 ms | 1,492 ms | **961 ms** |
| Mountain-region jump | 2,126–2,485 ms | 2,101 ms | 1,895 ms | **1,486 ms** |

The first visibility run took 410 ms for closest first detail, 246 ms for its adjacent pan and 82 ms for return. Its matched closest-first and return images were pixel-identical to baseline, as were the final combined equivalents. Other fixed-view comparisons include changing vehicles/water effects; they are not claimed pixel-identical.

Closest first detail uses seven active tiles instead of 61. The final combined retained-tile estimate is **334 MiB versus 912 MiB** at that point, and **394 MiB versus 1,026 MiB** after the adjacent pan. This is the cache's conservative decoded-resource estimate, not total process RAM or VRAM. The ten-second/nearby protections can still exceed the soft 700 MiB target after travel.

First fully revealed continent tile: baseline **2.634–2.871 s**, final combined **2.590 s**. Full initial settlement: baseline **3.848–4.339 s**, final combined **3.804 s**. Those results do not establish a reliable first-open speedup. Owned-view opening in the final run was 320 ms. The fixed 1.5-second reveal animation remains unchanged.

The first-use rendering hitches remain: approximately 314–332 ms during initial opening and 152–173 ms on first closest detail across these runs. The final combined shallow turn had p95 16.3 ms and max 32.8 ms; baseline turns had p95 18.5–22.5 ms and max 45.9–49.1 ms. Not every frame metric improves: final combined medium adjacent pan still had a 64.2 ms frame. These policies are not a complete hitch fix or a guarantee of sub-second settlement for large views.

## Rear-of-view result

The rear trial reduced one shallow view from 74 medium tiles to 53; the other visible tiles remained represented by the far bake. It took 1.616 s to settle that view, 501 ms for an adjacent pan and 874 ms for a quarter-turn. It also visibly coarsened background trees and road rendering. Roughly 2–4% of pixels changed by more than five intensity levels in the shallow captures, including both intended LOD differences and animated content. This is not a quality-equivalent optimisation.

It needs transitions with separate upgrade/downgrade thresholds, better protection of prominent silhouettes, mixed-LOD boundary inspection and moving-camera review before becoming a default. The orthographic camera does not make distant objects smaller automatically. No extra bake was created to hide that trade-off.

## Verification and limitations

- All ten completed runs: zero bake misses and zero runtime bake writes.
- All required visible scenes and terrain tiers were present after settlement; recent resources survived the ten-second retention checks.
- Ninety centre-tile picking checks matched the expected tile. Collision geometry and the cursor-radius activation policy were unchanged.
- The final corrected queue issued zero terrain reads on the retained closest return. Issued requests drained successfully after interrupted travel; no queue load errors were recorded.
- A tall building and the highest sampled summit remained resident when placed at the bottom viewport edge, with their bases outside the visible area.
- A fresh full package validator passed all 600 tiles / 1,841 resources, including fingerprints. Package bytes: 968,604,879. Manifest SHA-256: 912c8d977b801002bd4d064604112d05afcaee6c634e43b1855b8c8b66a721a7.
- The inherited ObjectDB-at-exit warning occurs in baseline and variants; this trial does not claim a clean process-leak audit.
- Static captures and interrupted-jump checks do not prove pop-in is invisible throughout continuous high-speed rotation. A production pass should include that review, per-tile transition hysteresis and rotation-aware prefetch. This trial's 20% margin is fixed, not velocity-adaptive.

## Next matrix

Promote and remeasure visibility + corrected queue first. Then test **local object LOD alone and combined with that winner**; protect skyline buildings and keep terrain/roads/buildings coordinated. Finally test **separate prepared collision resources alone and with the winner**, including cursor jumps, immediate clicks and extra-file I/O. Collision separation requires a new package layout and cannot be evaluated by this existing-bake trial. An eight-way matrix before those features have passed their individual correctness checks would hide failure causes and spend time measuring invalid combinations.

## Reproduce

From the repository root, use a new output/cache directory for each run:

```sh
AGENT_GODOT_WINDOW=1 godot --path price-of-everything-0.1 --log-file /private/tmp/stream-trial-engine.log res://tools/supply_chain_3d/trials/profile_streaming.tscn -- --continent-review --no-telemetry --bake-cache-directory=/private/tmp/stream-trial-empty-cache --trial-output=/private/tmp/stream-trial-results --trial-idle-prefetch --trial-visibility --trial-queue --trial-extra-edges
```

Omit visibility/queue flags for baseline; enable each separately for its matrix cell. Rear trial uses `--trial-visibility --trial-rear` without queue. These scripts are under `tools/`, already excluded from release exports. The frozen trial streaming loop copies production behaviour except for its explicit hooks; it must be refreshed if the production loop changes.

Evidence at repository root: `outputs/supply-chain-3d/streaming-matrix/summary.json`, per-case `report.json`, engine logs and PNGs. The final combined case is `combined-final`; the rear visual example is `rear/medium_shallow.png`, compared with `visibility-repeat/medium_shallow.png`.
