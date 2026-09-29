# Pure water (g_009) Blender icon

Builder for the approved pure water alternate icon,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_009_pure_water.png`: an outlet
pipe on a post pouring a clean stream into a splash, drawn with the set's fixed orthographic
goods camera, 12/6 px navy ink and dots on shadowed faces only (the water carries none). The
approved revision is `pure_water_v22`. Its masters, proof sheets and review record are in
`artifacts/goods_pure_water/`.

## Re-render

From the game directory (`price-of-everything-0.1`):

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python-exit-code 1 \
  --python tools/goods_icons/pure_water/render.py -- <out_dir> pure_water
python3 tools/goods_icons/pure_water/icon_export.py <out_dir>/pure_water_raw.png <out_dir>/pure_water_800.png --vib 1.0
```

The Blender step writes the raw colour, mask, ID, ink and path passes, `pure_water.blend` and
`pure_water_metrics.json`. The export step writes the 800 px master. The 450 and 256 px tiers
are LANCZOS downsizes of the 800 px master; `pw_proof.py <out_dir>` writes them (and 60 px)
along with the comparison, 3x crops and DS2 well sheets.

## Files

- `pure_water_kit.py`: `build_pure_water()`. Its docstring records the dimensions (D = pipe
  body diameter) and the owner's rulings.
- `pw_verify.py`: saved-scene checks (camera, closed hosts, which solids may touch), run in
  Blender with `-- <out_dir>`. `pw_proof.py` and `pw_owner_sheet.py` build the review sheets;
  they read the shipped art and fonts through the `POE` path at the top of each file.
- Frozen kit: every other file is a copy of `tools/goods_icons/fibreglass_lithium/source` from
  the Codex `blender-good-icons` worktree (8 Sep). The only edit is that `render.py` also loads
  `pure_water_kit.py`. `proof.py` and `verify.py` are that set's own checks, kept with the kit.
