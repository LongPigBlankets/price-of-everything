# Nitrogen (g_068) Blender icon

Builder for the approved nitrogen alternate icon,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_068_nitrogen.png` (the good's
internal name is `nitrogen`): one upright steel gas cylinder in a dark, slightly metallic blue-grey
with green shoulders, a rounded green-bordered white diamond with "N2" in navy on its body, and a
valve with a side outlet and a handwheel, drawn on the set's isometric grid with the fixed
orthographic goods camera, lit by the set's light, with 12/6 px navy ink and dots on the shaded
side. Unlike the earlier goods it does not keep the shipped art's layout: by owner direction it
replaces the shipped subject (a silver liquid-nitrogen dewar), and it was built from the owner's
description. The installed revision is `nitrogen_v5`. Its masters, proof sheets and the search
record are in `artifacts/goods_nitrogen/`.

## Re-render

From the game directory (`price-of-everything-0.1`):

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python-exit-code 1 \
  --python tools/goods_icons/nitrogen/render.py -- <out_dir> nitrogen
python3 tools/goods_icons/nitrogen/icon_export.py <out_dir>/nitrogen_raw.png <out_dir>/nitrogen_800.png --vib 1.0
```

The Blender step writes the raw colour, mask, contour, ID, host ID, ink and path passes,
`nitrogen.blend` and `nitrogen_metrics.json`. The lettering needs macOS's Arial Bold
(`/System/Library/Fonts/Supplemental/Arial Bold.ttf`, read by `typography.py`). The export step
writes the 800 px master, its ink layers and its line-weight record; it imports `standard_lines.py`
from this folder, the frozen copy. The 450 and 256 px tiers are LANCZOS downsizes of the 800 px
master; `n2_proof.py <out_dir> [<previous_dir>]` writes them (and 60 px) along with the
comparison, 3x crops, DS2 well sheet and `pixel_metrics.json`.

The saved-scene check (camera; closed hosts; the valve's parts joined; the diamond, its white face
and the lettering standing off the shell and clear of each other; nothing below ground) reads
`nitrogen.blend` and `nitrogen_metrics.json` from `<out_dir>` and writes
`saved_scene_verification.json` there:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python-exit-code 1 \
  --python tools/goods_icons/nitrogen/n2_verify.py -- <out_dir>
```

Re-rendered from this copy at install, the 800 px master came out byte-identical to the approved
v5 one, and the saved-scene check of that render reported no failures (its record is identical to
v5's). The raw passes matched the v5 ones pixel for pixel; only Blender's embedded render date
(and, on two passes, render time) differ.

## Files

- `nitrogen_kit.py`: `build_nitrogen()`, with the shell (`R_BODY`, `Z_FOOT`, `Z_SHOULDER`,
  `Z_NECK`, `R_NECK`), the diamond (`DIAMOND`: centre height, outer diagonal and the white face's
  diagonal; `CORNER_R`: the two corner radii), the lettering's bounds (`TEXT_WH`), the sheen streak
  (`SHEEN`: azimuth and width), the green (`GREEN_LIN`) and the white (`PAPER_LIN`), the materials
  and the stipple settings. Its comments quote the owner's rulings and record each revision's
  change; `DIAMOND` is assigned twice, v4's value and then v5's, which is the one used.
  `N2_REVISION` names the installed `nitrogen_v5`; the module docstring still describes v1 (the UN
  2.2 diamond with a white cylinder symbol and a "2", and a white N2 band), and
  `build_nitrogen()`'s docstring still says v1.
  - The shell is a lathe (`pw_lathe_z`) of one profile: a foot bevel, the straight body, an
    elliptical shoulder and the neck. Its faces above the shoulder seam take a second material,
    the green shoulder (`pw_toon_rgb`: shade (26, 98, 52), the diamond's green as its mid tone, lit
    (72, 168, 100)). Seam lines (`pw_circle_z`) ink the foot and the shoulder. The sheen is a thin
    strip just off the shell on its lit side, from the foot to the shoulder.
  - `n2_rounded_diamond()` builds the green diamond and its white face: an n x n grid over a
    square, each point pulled along its ray from the centre onto a rounded square (corner radius in
    the square's own frame), turned onto its point and wrapped round the cylinder by `n2_wrap()`
    (arc length round the side that faces the camera), fine enough that no face sags into the
    body. The green diamond sits at radius 0.505, the white face at 0.508, and the lettering
    (`formula_mesh`, wrapped the same way) at 0.511. `n2_diamond()` and `n2_grid_mesh()` (the
    earlier revisions' sharp-cornered diamond) and `n2_flat_poly()` (their cylinder symbol) are
    kept but no longer called. `fz_lin()` converts 8-bit sRGB to linear.
  - The valve: a collar on the neck, the valve body, an outlet toward -Y with a dark bore, a
    spindle, and a handwheel ring (`K.washer`) on two crossed spokes. The collar, valve body,
    outlet, spindle and ring, the prints and the sheen carry no dots (`pw_clean_water`).
  - It uses power's `pw_toon_rgb` from `power_kit.py`, pure water's helpers (`pw_toon`, `pw_flat`,
    `pw_lathe_z`, `pw_circle_z`, `pw_clean_water`) from `pure_water_kit.py`, alkaline's `E` from
    `alkaline_kit.py`, and `formula_mesh` (Arial Bold, with the chemical subscript) from
    `typography.py`.
- `n2_verify.py`: the saved-scene check above. It fails when an intended contact is missing (the
  collar on the shell's neck, the valve body on the collar, the outlet and the spindle in the valve
  body, and the handwheel ring joined to the spindle through its two spokes); on any contact
  between a print (the diamond, its white face, the lettering) and the shell or between two prints;
  on a print with a vertex on or inside the shell's radius; on an open or degenerate structural
  host; and on anything below ground. It records each print's standoff from the shell (v5: 0.005,
  0.008 and 0.011). The prints are open sheets, so they are not held to the closed-host test.
- `n2_proof.py`: the review sheets. It reads files outside this folder through two hardcoded
  paths. `POE` is the main checkout,
  `/Users/crisu/Price of Everything/price-of-everything/price-of-everything-0.1`: the shipped art
  (`assets/icons/goods/medium/g_068_nitrogen.png`), the approved oxygen, ammonia, hydrogen and
  chlorine alternates (`assets/icons/goods/alternate_icons/very_small/`) for the well, and the IBM
  Plex Sans font (`assets/fonts/IBMPlexSans-Medium.ttf`). `WT` is this worktree's alternates
  folder,
  `/Users/crisu/Price of Everything/poe-goods-icons/price-of-everything-0.1/assets/icons/goods/alternate_icons`,
  for the lithium-ion alternate (`very_small/g_059_lithium_battery.png`), which was installed
  here. Edit both to run it elsewhere. Its `pixel_metrics.json` records the green share (the
  shoulders and the diamond's border) and a `cream_share`, which here counts the white face.
- Frozen kit: every other file is the copy in `tools/goods_icons/fuels`, byte-identical to it
  (`alkaline_kit.py`, `power_kit.py`, `pure_water_kit.py`, `base_kit.py`, `sprite_kit.py`,
  `goods_icon_kit.py`, `legacy_batch.py`, `ore_builders.py`, `typography.py`, `icon_export.py` and
  `standard_lines.py`). `standard_lines.py` is that frozen copy, not the fertilisers one with
  per-part line weights; nitrogen sets none. The only edit is that `render.py` loads
  `nitrogen_kit.py` in place of `diesel_kit.py`, so its load list ends
  `'alkaline_kit.py','nitrogen_kit.py'`.
