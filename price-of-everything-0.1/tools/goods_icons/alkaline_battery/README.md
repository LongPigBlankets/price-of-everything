# Alkaline battery (g_070) Blender icon

Builder for the approved alkaline battery alternate icon,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_070_alkaline_battery.png`: the
shipped starter battery (grey case, charcoal lid with a raised panel and two terminal wells,
green-framed label on the long face) in the shipped art's layout, drawn on the set's isometric
grid with the fixed orthographic goods camera, lit by the set's light, with 12/6 px navy ink and
dots on the shaded long side only (the printed label carries none). The approved revision is
`alkaline_v4`. Its masters, proof sheets and review record are in
`artifacts/goods_alkaline_battery/`.

## Re-render

From the game directory (`price-of-everything-0.1`):

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python-exit-code 1 \
  --python tools/goods_icons/alkaline_battery/render.py -- <out_dir> alkaline_battery
python3 tools/goods_icons/alkaline_battery/icon_export.py <out_dir>/alkaline_battery_raw.png <out_dir>/alkaline_battery_800.png --vib 1.0
```

The Blender step writes the raw colour, mask, ID, ink and path passes, `alkaline_battery.blend`
and `alkaline_battery_metrics.json`. The export step writes the 800 px master and its line-weight
record. The 450 and 256 px tiers are LANCZOS downsizes of the 800 px master;
`alk_proof.py <out_dir> [<previous_dir>]` writes them (and 60 px) along with the comparison, 3x
crops, DS2 well sheet and `pixel_metrics.json`.

The saved-scene check (camera, closed hosts, which solids may touch) reads
`alkaline_battery.blend` and `alkaline_battery_metrics.json` from `<out_dir>` and writes
`saved_scene_verification.json` there:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python-exit-code 1 \
  --python tools/goods_icons/alkaline_battery/alk_verify.py -- <out_dir>
```

## Files

- `alkaline_kit.py`: `build_alkaline_battery()`, with the case, lid, panel and well dimensions,
  the terminal sizes (`R_COL`, `H_COL`, `R_P0`, `R_P1`, `H_POST`), the label layout (`FRAME`,
  `INNER`, `BAND`), the tone steps and the stipple thresholds. Its module docstring records the
  proportions measured off the shipped art and the owner's rulings; its comments record the
  v1-v4 fixes. The function's docstring still says v1; `ALK_REVISION` names the approved
  `alkaline_v4`. It uses pure water's helpers (`pw_toon`, `pw_flat`, `pw_lathe_z`,
  `pw_circle_z`, `pw_clean_water`) from `pure_water_kit.py`.
- `alk_verify.py`: the saved-scene check above.
- `alk_proof.py`: the review sheets, adapted from power's `pwr_proof.py`. It reads the shipped
  art, the approved alternates and fonts through the `POE` path at the top of the file, and the
  power alternate through the `WT` path (the `poe-goods-icons` worktree, where power was
  installed).
- Frozen kit: every other file is the copy in `tools/goods_icons/power`, which is pure water's
  copy of `tools/goods_icons/fibreglass_lithium/source` from the Codex `blender-good-icons`
  worktree (8 Sep). The only edit is that `render.py` also loads `alkaline_kit.py`; the rest are
  byte-identical to power's. It still loads `power_kit.py` too, whose helpers
  `build_alkaline_battery()` does not use.
