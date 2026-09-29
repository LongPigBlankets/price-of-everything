# Fertilisers (g_064) Blender icon

Builder for the approved fertilisers alternate icon,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_064_fertilisers.png` (the good's
internal name is `fertilisers`): the shipped art's layout (a wooden raised bed heaped with soil, a
tomato plant with seven tomatoes rising from it, and a plump green fertiliser bag leaning against the
bed's front-left side), drawn on the set's isometric grid with the fixed orthographic goods camera,
lit by the set's light, with 12/6 px navy ink (3 px on small detail; a 6 px outer contour on the
leaves and stems and 3 px boundaries on the leaves) and dots on the shaded sides. The bag's shape is
fitted to the shipped sack's silhouette. The installed revision is `fertiliser_v9`. Its masters,
proof sheets and the bag fit are in `artifacts/goods_fertilisers/`.

## Re-render

From the game directory (`price-of-everything-0.1`):

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python-exit-code 1 \
  --python tools/goods_icons/fertilisers/render.py -- <out_dir> fertilisers
python3 tools/goods_icons/fertilisers/icon_export.py <out_dir>/fertilisers_raw.png <out_dir>/fertilisers_800.png --vib 1.0
```

The Blender step writes the raw colour, mask, contour, ID, host ID, ink and path passes,
`fertilisers.blend` and `fertilisers_metrics.json`. The export step writes the 800 px master, its ink
layers and its line-weight record. It imports `standard_lines.py` from this folder, which is not the
frozen copy (see Files). The 450 and 256 px tiers are LANCZOS downsizes of the 800 px master;
`fz_proof.py <out_dir> [<previous_dir>]` writes them (and 60 px) along with the comparison, 3x crops,
DS2 well sheet and `pixel_metrics.json`.

The saved-scene check (camera; closed hosts; the bag clear of the bed, the soil, the tomatoes and the
leaves; the tomatoes clear of the bed and the soil; the stem in the soil; nothing below ground) reads
`fertilisers.blend` and `fertilisers_metrics.json` from `<out_dir>` and writes
`saved_scene_verification.json` there:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python-exit-code 1 \
  --python tools/goods_icons/fertilisers/fz_verify.py -- <out_dir>
```

Re-rendered from this copy at install, the 800 px master came out byte-identical to the approved
v9 one, and the saved-scene check of that render reported no failures (its record is identical to
v9's). The raw passes matched the v9 ones pixel for pixel; only Blender's embedded render date (and,
on two passes, render time) differ.

## Files

- `fertiliser_kit.py`: `build_fertilisers()`, with the bed (`BOX`, `WALL`, `SEAM_Z`), the soil
  (`SOIL_EDGE`, `SOIL_PEAK`, `SOIL_SPREAD`), the plant (`STEM_AT`, `STEM_H`, `PLANT_Z`), the tomatoes
  (`TOMATOES`), the compound leaves (`LEAVES`), the bag (`BAG`: the fitted shape, its size, the seam
  bands and the ears), the small ink weight (`SMALL_INK`), the materials, the per-part line weights
  and the stipple settings. Its comments record the shipped layout, the owner's notes and each
  revision's change. `FZ_REVISION` names the installed `fertiliser_v9`; the module docstring still
  describes the v1-v5 sack (the sand icon's pillow sack, stood up), which `BAG` and `fz_bag()`
  replaced, and `build_fertilisers()`'s docstring still says v1.
  - `fz_bed()` builds the four walls, each drawn as two boards by a seam line; `fz_soil()` the soil,
    a closed solid whose top is a heightfield (`fz_soil_z()`) mounded at the plant; `fz_leaf()` a
    compound leaf of three serrated leaflets (`fz_leaflet()`, cut as thin plates by `fz_plate()`)
    with 3 px midribs; `fz_bag()` the bag, a loft of rounded-rectangle sections (thickness
    sin(pi t^sag)^belly), leaned, turned and set against the bed's -Y side, with its seam and crease
    lines and gloss streaks. Tomatoes are spheres with silhouette ink, a glint and a calyx star
    (`fz_star()`).
  - `build_fertilisers()` sets `outline['outer_by_label']` to 6 px for the stems (label 4) and the
    leaves (label 5), and `outline['component_weight_by_label']` to 3 px for the leaves; every other
    part keeps the set's 12/6 px.
  - It uses power's `pw_toon_rgb` from `power_kit.py`, alkaline's helpers (`alk_box`,
    `alk_outward`, `E`) from `alkaline_kit.py` and pure water's (`pw_flat`, `pw_clean_water`) from
    `pure_water_kit.py`.
- `standard_lines.py`: the exporter's line module, changed from the frozen copy
  (`tools/goods_icons/fuels/standard_lines.py`) by one addition, optional per-part line weights.
  `outline['outer_by_label']` maps a part label to its outer (silhouette) weight in px at 800: each
  silhouette pixel takes the weight of the part it belongs to, and outside the body the part of the
  nearest body pixel. `outline['component_weight_by_label']` maps a part label to its
  component-boundary weight in px at 800, in place of `component_weight` (or the inner weight). The
  part-label image is now built when either `component_boundaries` or `outer_by_label` is set.
  Without the two keys every weight is the set's and exports are unchanged: at install, diesel fuel
  v9's raw passes and fertilisers v5's re-exported through this copy byte-identically.
  `*_line_weights.json` still records only the set's 12/6 px; the per-part weights are in the
  metrics' `outline`.
- `fz_verify.py`: the saved-scene check above. It fails on any contact between the bag and the
  bed's walls or the soil; any tomato and the bed, the soil or the bag; or any leaflet (its plate,
  outline or midrib) and the bag. It also fails when the stem does not touch the soil, on an open
  or degenerate structural host, and on anything below ground. The soil against the bed's walls is
  listed as intended but not required (it fills the bed). Tomatoes may touch each other; in v9
  three pairs in the trusses do.
- `fz_proof.py`: the review sheets. It reads files outside this folder through two hardcoded
  paths. `POE` is the main checkout,
  `/Users/crisu/Price of Everything/price-of-everything/price-of-everything-0.1`: the shipped art
  (`assets/icons/goods/medium/g_064_fertilisers.png`), the approved ammonia, sand, chem salts and
  industrial acids alternates (`assets/icons/goods/alternate_icons/very_small/`) for the well, and
  the IBM Plex Sans font (`assets/fonts/IBMPlexSans-Medium.ttf`). `WT` is this worktree's
  alternates folder,
  `/Users/crisu/Price of Everything/poe-goods-icons/price-of-everything-0.1/assets/icons/goods/alternate_icons`,
  for the PVC alternate, which was installed here. Edit both to run it elsewhere. Its
  `pixel_metrics.json` records the green share (leaves, stems and the bag) and a `cream_share`,
  which is 0 here. The shipped art has a baked-in blue background (see
  `artifacts/goods_fertilisers/README.md`), which shows in the comparison.
- Frozen kit: every other file is the copy in `tools/goods_icons/fuels`, byte-identical to it
  (`alkaline_kit.py`, `power_kit.py`, `pure_water_kit.py`, `base_kit.py`, `sprite_kit.py`,
  `goods_icon_kit.py`, `legacy_batch.py`, `ore_builders.py`, `typography.py` and `icon_export.py`).
  The only other edit is that `render.py` loads `fertiliser_kit.py` in place of `diesel_kit.py`, so
  its load list ends `'alkaline_kit.py','fertiliser_kit.py'`.
