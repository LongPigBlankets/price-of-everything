# Shared geometry and collision trial — 16 October 2026

Decision: keep this as an isolated experiment. It saves 19.25% in the sampled resources but increases loading time. Production loading code and bakes are unchanged.

## Methods

The exact candidate stores a reference to the render mesh instead of a second collision face array, reconstructing native collision with Mesh.get_faces() on load. The direct candidate expands surface indices instead; it is faster but changes existing collision positions by at most 0.0000611 world units.

The sample covers urban tile_4_9, rural tile_10_10, mountain tile_11_5, hill tile_11_6 and coastal tile_15_16 at base, medium and near tiers. The 15 original resources total 9,516,647 bytes; the exact candidate totals 7,684,500 bytes. This is a land-tile sample, not a measured continent-wide or exported-game saving. Both candidates retain the current native Zstd block optimisation.

A separate audit compared terrain surface arrays/primitive types, collision faces/settings, rims and lips across 1,824 tile resources. It found 3,841 unique payloads and no repeated nonempty payloads. The only duplicate was empty geometry, appearing 1,008 times. Nested scenery, road drawings and player-building meshes were outside this audit.

## Forward+ results

Godot 4.6.2, Forward+/Metal on Apple M5 Pro. Fresh processes with warm filesystem caches. Original/candidate order alternates; discard the first pair and take the median of seven uncached native resource loads per tile. Below are means of the five per-tile medians in the second Forward+ process.

| Tier | Original (exact comparison) | Shared mesh, exact collision | Original (direct comparison) | Shared mesh, direct expansion |
|---|---:|---:|---:|---:|
| Base | 1.55 ms | 3.50 ms | 1.50 ms | 2.80 ms |
| Medium | 2.35 ms | 7.60 ms | 2.24 ms | 4.30 ms |
| Near | 3.67 ms | 12.77 ms | 3.62 ms | 6.56 ms |

A separate Forward+ process and headless run found the same regression. These are individual resource-load measurements, not complete startup or pan timings. Collision reconstruction outweighs the reduced storage-reading/decompression work on this machine.

## Verification

- All 15 exact candidates preserve collision faces and native shape settings exactly.
- Both modes retain every noncollision payload, including mesh arrays, texture bytes and metadata.
- All 30 candidates passed native threaded ResourceLoader checks: one shared mesh reference, with collision faces matching their synchronous equivalents.
- Direct reconstruction's small position differences are explicitly reported, not treated as exact matches.
- All 1,841 installed bake sizes and SHA-256 checksums still match. Installed resource total: 968,604,879 bytes. Manifest SHA-256: 912c8d977b801002bd4d064604112d05afcaee6c634e43b1855b8c8b66a721a7.
- No production bake, semantic source, fingerprint or loader changed. No production rebake was needed or performed. No new whole-view startup or pan timings are claimed.

## Reproduction and evidence

Run tools/supply_chain_3d/trials/profile_shared_geometry.tscn through the project's Godot shim. Use headless mode for the audit; use AGENT_GODOT_WINDOW=1 for real Forward+ timings. Supply --trial-output pointing to a new directory inside /private/tmp, --no-telemetry and an explicit temporary engine log. Add --audit-geometry for the complete terrain duplicate audit. Existing output directories are rejected. The tool never installs candidates.

Evidence at repository root: outputs/supply-chain-3d/shared-geometry/headless.json, forward-plus-1.json, forward-plus-2.json and installed-checksums.json. Trial code is under tools/, already excluded from release exports.

A future attempt needs substantially cheaper native/indexed collision loading, or independently scheduled collision preparation with measured cursor-picking latency. Neither is implemented here. Deferring reconstruction alone moves its cost to later interaction. Keep the prepared collision data in production until an alternative meets both loading and picking requirements.
