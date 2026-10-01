# Lithium-ion battery (g_059) Blender icon

Builder for the approved lithium-ion battery alternate icon,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_059_lithium_battery.png`: the
shipped battery pack (an open steel crate with rounded slots in its walls, coral-red cells with
raised plates and terminal pegs, a dark-red washer under each + terminal, a charcoal cover printed
"Li-ion") in the shipped art's layout, drawn on the set's isometric grid with the fixed
orthographic goods camera, lit by the set's light, with 12/6 px navy ink (3 px on the cell plates)
and dots on the shaded sides. The approved revision is `lithium_v1`. Its masters, proof sheets and
record are in `artifacts/goods_lithium_battery/`.

It is the approved sodium-ion pack (`tools/goods_icons/sodium_battery`) with other colours and
lettering: `lithium_kit.py` calls `sodium_kit.build_ion_pack` unchanged.

## Re-render

From the game directory (`price-of-everything-0.1`):

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python-exit-code 1 \
  --python tools/goods_icons/lithium_battery/render.py -- <out_dir> lithium_battery
python3 tools/goods_icons/lithium_battery/icon_export.py <out_dir>/lithium_battery_raw.png <out_dir>/lithium_battery_800.png --vib 1.0
```

The Blender step writes the raw colour, mask, ID, ink and path passes, `lithium_battery.blend`
and `lithium_battery_metrics.json`. The export step writes the 800 px master and its line-weight
record. The 450 and 256 px tiers are LANCZOS downsizes of the 800 px master;
`li_proof.py <out_dir> [<previous_dir>]` writes them (and 60 px) along with the comparison, 3x
crops, DS2 well sheet and `pixel_metrics.json`.

The saved-scene check (camera, closed hosts, which solids may touch, the + washers clear of the
plates and cover, cells on the floor and clear of the walls and lip, nothing but the terminal
posts above the rim) reads `lithium_battery.blend` and `lithium_battery_metrics.json` from
`<out_dir>` and writes `saved_scene_verification.json` there:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python-exit-code 1 \
  --python tools/goods_icons/lithium_battery/li_verify.py -- <out_dir>
```

This copy also renders the sodium-ion battery (`... render.py -- <out_dir> sodium_battery`); at
install that render was byte-identical to the installed g_060 medium tier, which shows the shared
builder is unchanged.

## Files

- `lithium_kit.py`: `build_lithium_battery()`. It calls `build_ion_pack('lithium_battery',
  LI_CELL, 'Li-ion', LI_REVISION)` with coral-red cells (`LI_CELL`, linear), then adds a dark-red
  washer (`LI_PLUS`) a hair wider and taller than the grey one under each cell's left (+) terminal,
  as the shipped art draws it; the washer shares the terminal's part label, so no line is drawn
  between washer and post.
- `sodium_kit.py`: the pack (`build_ion_pack`), byte-identical to
  `tools/goods_icons/sodium_battery/sodium_kit.py`; its README lists the dimensions and fixes.
- `li_verify.py`: the saved-scene check above, adapted from sodium's `na_verify.py`.
- `li_proof.py`: the review sheets, adapted from sodium's `na_proof.py`. It reads files outside
  this folder through two hardcoded paths at the top of the file. `POE` is the main checkout,
  `/Users/crisu/Price of Everything/price-of-everything/price-of-everything-0.1`: the shipped art
  (`assets/icons/goods/medium/g_059_lithium_battery.png`), the approved electrical components and
  computer alternates, and the IBM Plex Sans font. `WT` is this worktree's alternates folder,
  `/Users/crisu/Price of Everything/poe-goods-icons/price-of-everything-0.1/assets/icons/goods/alternate_icons`,
  for the sodium-ion, alkaline and power alternates installed here. Edit both to run it elsewhere.
- Frozen kit: every other file is the copy in `tools/goods_icons/sodium_battery`, byte-identical
  to it. The only edit is that `render.py` also loads `lithium_kit.py`. It still loads
  `power_kit.py`, whose helpers the pack does not use.
