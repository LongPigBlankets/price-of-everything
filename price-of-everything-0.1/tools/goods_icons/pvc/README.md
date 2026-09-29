# PVC (g_033) Blender icon

Builder for the approved PVC alternate icon,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_033_pvc.png`: the shipped art's
layout (seven hollow PVC pipes in a strapped hexagonal bundle, and a PVC window-frame corner whose
chambered profile is cut at both ends, with the double glazing shown by its two panes' cut edges),
drawn on the set's isometric grid with the fixed orthographic goods camera, lit by the set's
light, with 12/6 px navy ink (3 px on the cross-sections and glass edges) and dots on the shaded
sides. The installed revision is `pvc_v15`: the owner approved v14, and v15 fixes two drawing
defects from the review without changing the design. Its masters, proof sheets and review record
are in `artifacts/goods_pvc/`.

## Re-render

From the game directory (`price-of-everything-0.1`):

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python-exit-code 1 \
  --python tools/goods_icons/pvc/render.py -- <out_dir> pvc
python3 tools/goods_icons/pvc/icon_export.py <out_dir>/pvc_raw.png <out_dir>/pvc_800.png --vib 1.0
```

The Blender step writes the raw colour, mask, ID, ink and path passes, `pvc.blend` and
`pvc_metrics.json`. The export step writes the 800 px master and its line-weight record. The 450
and 256 px tiers are LANCZOS downsizes of the 800 px master; `pvc_proof.py <out_dir>
[<previous_dir>]` writes them (and 60 px) along with the comparison, 3x crops, DS2 well sheet and
`pixel_metrics.json`.

The saved-scene check (camera, closed hosts, the frame and panes clear of every pipe and strap,
the intended contacts, nothing below ground) reads `pvc.blend` and `pvc_metrics.json` from
`<out_dir>` and writes `saved_scene_verification.json` there:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python-exit-code 1 \
  --python tools/goods_icons/pvc/pvc_verify.py -- <out_dir>
```

Re-rendered from this copy at install, the 800 px master came out byte-identical to the approved
v15 one, and the saved-scene check of that render reported no failures. The raw passes matched the
v15 ones pixel for pixel; only Blender's embedded render date and time differ.

## Files

- `pvc_kit.py`: `build_pvc()`, with the pipe sizes (`R_O`, `R_I`, `PIPE_L`), the straps
  (`STRAPS`, `STRAP_T`) and the bundle height (`ZC`), the frame (`FX0`, `FX1`, `FY0`, `FY1`,
  `FZT`), the stepped profile (`PROFILE`, with the rib `RIB`, `RIB_H`, `RECESS`), the chambers
  (`CHAMBERS`), the glass seat (`SEAT`), the panes (`PANES`, `Z_GLASS`, `Y_GLASS`), the section
  ink weight (`SECTION_INK`), the materials and the stipple settings. Its module docstring records
  the shipped layout; its comments quote the owner's rulings and record the fixes from v2 to v15.
  `PVC_REVISION` names the installed `pvc_v15`; `build_pvc()`'s docstring still says v1. It uses
  alkaline's helpers (`alk_outward`, `E`) from `alkaline_kit.py` and pure water's
  (`pw_revolve_y`, `pw_toon`, `pw_flat`, `pw_clean_water`) from `pure_water_kit.py`.
- `pvc_verify.py`: the saved-scene check above. It fails on any contact between a frame member or
  pane and a pipe or strap, on a strap that does not touch each ring pipe, on a pane that is not
  seated in both frame members, on an open or degenerate host, and on anything below ground. The
  panes are open strips, so they are not held to the closed-host test.
- `pvc_proof.py`: the review sheets, adapted from the sodium and alkaline proof scripts
  (`na_proof.py`, `alk_proof.py`). It reads files outside this folder through two hardcoded paths
  at the top of the file. `POE` is the main checkout,
  `/Users/crisu/Price of Everything/price-of-everything/price-of-everything-0.1`: the shipped art
  (`assets/icons/goods/medium/g_033_pvc.png`), the approved copper pipe, windows, ethylene and
  glass alternates (`assets/icons/goods/alternate_icons/very_small/`) for the well, and the IBM
  Plex Sans font (`assets/fonts/IBMPlexSans-Medium.ttf`). `WT` is this worktree's alternates
  folder,
  `/Users/crisu/Price of Everything/poe-goods-icons/price-of-everything-0.1/assets/icons/goods/alternate_icons`,
  for the sodium-ion alternate, which was installed here. Edit both to run it elsewhere. Its
  `pixel_metrics.json` keeps the battery sheets' green and cream shares, which are 0 on PVC.
- Frozen kit: every other file is the copy in `tools/goods_icons/alkaline_battery`,
  byte-identical to it (`alkaline_kit.py` included). The only edit is that `render.py` also loads
  `pvc_kit.py`. It still loads `power_kit.py` too, whose helpers `build_pvc()` does not use.
