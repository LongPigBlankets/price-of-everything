# Diesel fuel (g_031) Blender icon

Builder for the approved diesel fuel alternate icon,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_031_fuels.png` (the good's
internal name is `fuels`; the catalogue calls it Diesel Fuel): the shipped art's layout (a red
fuel pump on a plinth with a display panel, a holster hole on its side with the hose coming out
of it, and a second hose to a pistol nozzle filling a jerrycan), drawn on the set's isometric grid
with the fixed orthographic goods camera, lit by the set's light, with 12/6 px navy ink (3 px on
small detail) and dots on the shaded sides. The jerrycan is the ICE car's (g_056), built by that
icon's own jerrycan builder and painted in the pump's red. The installed revision is `diesel_v9`.
Its masters and proof sheets are in `artifacts/goods_fuels/`.

## Re-render

From the game directory (`price-of-everything-0.1`):

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python-exit-code 1 \
  --python tools/goods_icons/fuels/render.py -- <out_dir> fuels
python3 tools/goods_icons/fuels/icon_export.py <out_dir>/fuels_raw.png <out_dir>/fuels_800.png --vib 1.0
```

The Blender step writes the raw colour, mask, contour, ID, ink and path passes, `fuels.blend` and
`fuels_metrics.json`. The export step writes the 800 px master and its line-weight record. The 450
and 256 px tiers are LANCZOS downsizes of the 800 px master; `ds_proof.py <out_dir>
[<previous_dir>]` writes them (and 60 px) along with the comparison, 3x crops, DS2 well sheet and
`pixel_metrics.json`.

The saved-scene check (camera, closed hosts, the hoses clear of the can, the plinth and each
other, the nozzle and the open cap clear of the can and its handle, the intended contacts, nothing
below ground) reads `fuels.blend` and `fuels_metrics.json` from `<out_dir>` and writes
`saved_scene_verification.json` there:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python-exit-code 1 \
  --python tools/goods_icons/fuels/ds_verify.py -- <out_dir>
```

Re-rendered from this copy at install, the 800 px master came out byte-identical to the approved
v9 one, and the saved-scene check of that render reported no failures (its record is identical to
v9's). The raw passes matched the v9 ones pixel for pixel; only Blender's embedded render date and
time differ.

## Files

- `diesel_kit.py`: `build_fuels()`, with the pump (`PUMP`, `R_EDGE`, `RIM_IN`), the plinth
  (`PLINTH`), the display (`DISPLAY`), the holster's bezel and hole (`BEZEL`, `HOLE`), the can's
  size and place (`CAN_D`, `CAN_AT`) and its cap's swing (`CAP_SWING`), the pistol nozzle
  (`NOZ_TILT`, `SPOUT_DIR`, `SPOUT_LEN`, `NOZ_BODY`, `NOZ_GUARD`, `NOZ_LEVER`, `NOZ_W`, `SPOUT_AT`,
  `COLLAR_V`), the hose and spout radii (`R_HOSE`, `R_SPOUT`), the pump red's three tones
  (`PUMP_RED`), the can's dark set and toon thresholds (`CAN_DARK`, `CAN_STEPS`), the small ink
  weight (`SMALL_INK`), the materials and the stipple settings. Its module docstring records the
  shipped layout and the owner's rulings. `DS_REVISION` names the installed `diesel_v9`;
  `build_fuels()`'s docstring still says v6.
  - `ds_ice_can()` builds the can with `build_reference_jerrycan` from `base_kit.py` (yaw 90,
    D 1.25). That function is byte-identical to the one in the ICE car's own kit
    (`tools/goods_icons/complex_goods/diesel_car/source/goods_icon_kit.py`). It then adds the
    adapter the standard exporter needs: part labels; ink paths read off the can's own geometry
    (its loft profile's perimeter and sharp depth corners, the pressed X's rims found on the
    finished Boolean mesh, the neck and cap rims); its own cap swung open on the neck; a dark open
    mouth; and the can's two materials (`tn_diesel_red`, `tn_diesel_red_dark`) rebuilt in place
    with the pump red's tones, keeping the can's toon thresholds.
  - It uses power's `pw_toon_rgb` from `power_kit.py`, alkaline's helpers (`alk_box`, `alk_rect`,
    `alk_outward`, `E`) from `alkaline_kit.py` and pure water's (`pw_toon`, `pw_flat`,
    `pw_clean_water`) from `pure_water_kit.py`.
- `ds_verify.py`: the saved-scene check above. It fails on any contact between the hoses and the
  can, the plinth or each other; the nozzle's parts and the can or its handle; the open cap and
  the can, the spout or the nozzle; or the can and the pump or plinth. It also fails when an
  intended contact is missing (the pump on its plinth, both hoses entering the pump, the spout in
  the neck and in the nozzle's head, the nozzle's parts, the neck on the can), on an open or
  degenerate host, and on anything below ground. The open cap may touch its neck at the hinge.
- `ds_proof.py`: the review sheets, adapted from the PVC proof script (`pvc_proof.py`). It reads
  files outside this folder through two hardcoded paths. `POE` is the main checkout,
  `/Users/crisu/Price of Everything/price-of-everything/price-of-everything-0.1`: the shipped art
  (`assets/icons/goods/medium/g_031_fuels.png`), the approved processed oil, crude oil, ICE car
  and chlorine alternates (`assets/icons/goods/alternate_icons/very_small/`) for the well, and the
  IBM Plex Sans font (`assets/fonts/IBMPlexSans-Medium.ttf`). `WT` is this worktree's alternates
  folder,
  `/Users/crisu/Price of Everything/poe-goods-icons/price-of-everything-0.1/assets/icons/goods/alternate_icons`,
  for the alkaline battery alternate, which was installed here. Edit both to run it elsewhere. The
  well's ICE car comes from the main checkout, so it shows that icon as installed there. Its
  `pixel_metrics.json` records the red paint's share as `red_share` (the mask is still named
  `green` in the script) and a `cream_share`, which is 0 here.
- Frozen kit: every other file is the copy in `tools/goods_icons/pvc`, byte-identical to it
  (`alkaline_kit.py`, `power_kit.py`, `pure_water_kit.py` and `base_kit.py` included). The only
  edit is that `render.py` loads `diesel_kit.py` in place of `pvc_kit.py`, so its load list ends
  `'alkaline_kit.py','diesel_kit.py'`.
