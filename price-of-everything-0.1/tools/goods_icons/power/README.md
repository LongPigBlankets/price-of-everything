# Power (g_010) Blender icon

Builder for the approved power alternate icon,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_010_power.png`: an extruded
lightning bolt in the shipped art's layout, drawn on the set's isometric grid with the fixed
orthographic goods camera, lit by the set's light, with 12/6 px navy ink and dots on the shaded
face only. The approved revision is `power_v13`. Its masters, proof sheets and review record are
in `artifacts/goods_power/`.

## Re-render

From the game directory (`price-of-everything-0.1`):

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python-exit-code 1 \
  --python tools/goods_icons/power/render.py -- <out_dir> power
python3 tools/goods_icons/power/icon_export.py <out_dir>/power_raw.png <out_dir>/power_800.png --vib 1.0
```

The Blender step writes the raw colour, mask, ID, ink and path passes, `power.blend` and
`power_metrics.json`. The export step writes the 800 px master. The 450 and 256 px tiers are
LANCZOS downsizes of the 800 px master; `pwr_proof.py <out_dir> [<previous_dir>]` writes them (and
60 px) along with the comparison, 3x crops, DS2 well sheet and `pixel_metrics.json`.

## Files

- `power_kit.py`: `build_power()`, with the bolt's outline (`BOLT_UV`), its turn on the grid
  (`PSI`), its depth, the three gold tone steps and the stipple thresholds. Its comments record
  the owner's rulings. The module docstring still describes the v8-v10 layout (face toward -Y,
  thickness on the right), as does the `topology` string it writes to `power_metrics.json`; the
  comment above `BOLT_UV` records the v11 turn that the approved icon uses.
- `pwr_proof.py`: the review sheets, adapted from pure water's `pw_proof.py` (its docstring still
  says pure water). It reads the shipped art, the approved alternates and fonts through the `POE`
  path at the top of the file.
- Frozen kit: every other file is the same copy as `tools/goods_icons/pure_water`, which came
  from `tools/goods_icons/fibreglass_lithium/source` in the Codex `blender-good-icons` worktree
  (8 Sep). The only edit is that `render.py` also loads `power_kit.py`. It still loads
  `pure_water_kit.py` too, whose helpers `build_power()` does not use.
