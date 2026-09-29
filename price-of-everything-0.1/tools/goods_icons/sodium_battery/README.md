# Sodium-ion battery (g_060) Blender icon

Builder for the approved sodium-ion battery alternate icon,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_060_sodium_battery.png`: the
shipped battery pack (an open steel crate with rounded slots in its walls, white cells with
raised plates and terminal pegs, a charcoal cover printed "Na-ion") in the shipped art's layout,
drawn on the set's isometric grid with the fixed orthographic goods camera, lit by the set's
light, with 12/6 px navy ink (3 px on the cell plates) and dots on the shaded sides. The approved
revision is `sodium_v12`. Its masters, proof sheets and review record are in
`artifacts/goods_sodium_battery/`.

## Re-render

From the game directory (`price-of-everything-0.1`):

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python-exit-code 1 \
  --python tools/goods_icons/sodium_battery/render.py -- <out_dir> sodium_battery
python3 tools/goods_icons/sodium_battery/icon_export.py <out_dir>/sodium_battery_raw.png <out_dir>/sodium_battery_800.png --vib 1.0
```

The Blender step writes the raw colour, mask, ID, ink and path passes, `sodium_battery.blend`
and `sodium_battery_metrics.json`. The export step writes the 800 px master and its line-weight
record. The 450 and 256 px tiers are LANCZOS downsizes of the 800 px master;
`na_proof.py <out_dir> [<previous_dir>]` writes them (and 60 px) along with the comparison, 3x
crops, DS2 well sheet and `pixel_metrics.json`.

The saved-scene check (camera, closed hosts, which solids may touch, cells on the floor and clear
of the walls and lip, nothing but the terminal posts above the rim) reads `sodium_battery.blend`
and `sodium_battery_metrics.json` from `<out_dir>` and writes `saved_scene_verification.json`
there:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python-exit-code 1 \
  --python tools/goods_icons/sodium_battery/na_verify.py -- <out_dir>
```

Re-rendered from this copy at install, the 800 px master came out byte-identical to the approved
one, and the saved-scene check of that render reported no failures. The raw passes matched the
approved ones pixel for pixel; only Blender's embedded render date differs.

## Files

- `sodium_kit.py`: `build_ion_pack(name, cell_rgb, text, revision)`, the pack, and
  `build_sodium_battery()`, which builds it with white cells and "Na-ion". The lithium battery
  (g_059) is the same pack with red cells and "Li-ion", so it will reuse `build_ion_pack`. It holds
  the crate, wall, lip and slot dimensions (`CR`, `T_WALL`, `T_FLOOR`, `LIP_W`, `LIP_H`, `SLOT_W`,
  `SLOT_R`, `ROWS`, `SMALL`, `COLS`), the cell grid (`GRID`, `GRID_X`, `GRID_Y`, `CELL_GAP`,
  `CELL_R`, `CELL_TOP`), the terminal and plate sizes (`TERM_X`, `TERM_Y`, `R_WASH`, `H_WASH`,
  `R_POST`, `H_POST`, `PLATE_IN`, `PLATE_GAP`, `PLATE_H`, `PLATE_R`), the plate ink weight
  (`PLATE_INK`), the cover (`COVER_Y0`, `COVER_T`), the tone steps and the stipple thresholds. Its
  module docstring records the proportions measured off the shipped art and the owner's rulings;
  its comments record the fixes from v1 to v12 and quote the owner's two fixes. `NA_REVISION` names
  the approved `sodium_v12`; `build_sodium_battery()`'s docstring still says v1. It uses
  alkaline's helpers (`alk_box`, `alk_rect`, `alk_outward`, `E`) from `alkaline_kit.py`, pure
  water's (`pw_toon`, `pw_flat`, `pw_lathe_z`, `pw_clean_water`) from `pure_water_kit.py`, and
  `typography.formula_mesh` for the "Na-ion" lettering, set in Arial Bold from
  `/System/Library/Fonts/Supplemental/Arial Bold.ttf` (a macOS system font).
- `na_verify.py`: the saved-scene check above.
- `na_proof.py`: the review sheets, adapted from alkaline's `alk_proof.py`. It reads files outside
  this folder through two hardcoded paths at the top of the file. `POE` is the main checkout,
  `/Users/crisu/Price of Everything/price-of-everything/price-of-everything-0.1`: the shipped art
  (`assets/icons/goods/medium/g_060_sodium_battery.png`, and `g_059_lithium_battery.png` for the
  well), the approved electrical components and computer alternates, and the IBM Plex Sans font.
  `WT` is this worktree's alternates folder,
  `/Users/crisu/Price of Everything/poe-goods-icons/price-of-everything-0.1/assets/icons/goods/alternate_icons`,
  for the alkaline and power alternates, which were installed here. Edit both to run it elsewhere.
- Frozen kit: every other file is the copy in `tools/goods_icons/alkaline_battery`, byte-identical
  to it (`alkaline_kit.py` included). The only edit is that `render.py` also loads
  `sodium_kit.py`. It still loads `power_kit.py` too, whose helpers `build_sodium_battery()` does
  not use.
