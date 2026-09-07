# Windows demo build audit — 7 September 2026

## Save/load fixes

Save version 11 persists the cost solver’s per-building and per-good results. Loading replaces the previous match’s costs; starting a new match clears them. Version 10 migration recovers current-turn per-good costs from price history where available. Older saves without recorded costs show unknown until production runs, rather than another match’s costs.

Autosave explicitly records the completed turn’s market observation before snapshot serialization, regardless of signal registration order. The later market listener replaces that same point rather than appending a duplicate.

Validation: 555-script parse sweep, zero failures; 3,725 unit checks; 723 end-to-end checks. Added coverage for cross-match loads, empty caches, legacy saves, migration, new-match reset and the actual autosave JSON observation.

## Windows package changes

Only the Windows Desktop preset was changed. Source assets and development files were preserved on disk.

| Resource pack | MiB |
|---|---:|
| Before | 1214.1 |
| After | 667.5 |
| Reduction | 546.7 (45.0%) |

Excluded development artifacts, local savegames, reports, logs, docs, balance baseline snapshots and 50 root screenshots with no script/scene references. Final pack manifest confirms these are absent. The original export shipped local saves and Blender/icon experiments.

Added explicit inclusions for `data/start_layout_bake.bin` and `data/map_authored/active.txt`. The binary bake was absent from the original export, forcing expensive live layout generation. The corrected pack reports `bake_available=true` and uses the baked layout.

## Keep versus further trim

- Keep authored map textures (~145 MiB): referenced by the bake manifest and used across zoom levels.
- Keep runtime banners (~320 MiB combined). Their imported lossless textures are far larger than their source JPEGs. Lossy texture compression or lower-resolution variants are the strongest next optimization, but require visual comparison. No quality-changing conversion was made.
- Keep the loading film/intro (~65 MiB), active icons, audio and advisor portraits: runtime content.
- Artifacts (~1.2 GB on disk), reports (~608 MB), logs (~21 MB), local saves (~11 MB), and screenshots can be archived outside the project to reduce repo workspace/import load. They are already excluded from the Windows build; no source deletion was performed.
- Existing duplicate translation UID warnings for legacy recipe CSV imports should be cleaned up separately. Runtime uses `recipes_all.csv`; avoid deleting legacy files without checking editor tooling.

## Export validation and limits

Created `/tmp/poe-windows-demo/CarbonAndCapital.exe` and its companion `.pck`. Both must ship together. This is a Windows x86-64 release export.

Booted the exported PCK from an isolated directory with the host Godot engine: 77 goods loaded, layout bake accepted, new-game map reached ready state, and snapshot save/load passed. The Windows executable itself has not been run on Windows; native Windows graphics/audio/input verification remains required.

An existing authored-map versus terrain hash warning appears in both source and pack tests. This is separate from the fixed missing binary bake; review terrain alignment before release sign-off. Icon work was changing concurrently in the shared workspace, so build sizes reflect the exported local files, not solely commit 420997ba.

Reproduce the manifest audit with `python3 price-of-everything-0.1/tools/audit_windows_pack.py /tmp/poe-windows-demo/CarbonAndCapital.pck /tmp/windows-demo-manifest.json`.

## Banner follow-up

Deleted all five unused building JPEGs, their `.import` files and orphaned imported cache files. A project search found no live path or UID references (only historical audit documentation). The Windows pack manifest confirms the building assets are absent, removing ~140 MiB.

The six tile banners now import with lossy compression at 90% quality and a 2048px maximum dimension, preserving the original JPEGs. Their runtime textures fell from 179.55 MiB to 9.25 MiB. A 1024px/85% trial was smaller but softened detail, so the higher-resolution setting was retained. Godot’s [image import documentation](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_images.html) describes this lossy import and size-limit workflow.

The resulting Windows resource pack is 357.1 MiB. Full regression checks remain green: 555-script parse sweep, 3,725 unit checks, 723 end-to-end checks. Native Windows verification is still required.
