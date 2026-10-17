# Bauxite ore (g_022) Blender icon

**Approved 2026-10-17** (owner: "Approved. Install v19 as the bauxite ore alternate and open a PR."). The internal name
is `bauxite_ore`. v19 is installed as the approved alternate,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_022_bauxite_ore.png` (800, 450 and 256 px), and listed
in `approved_manifest.json` with source `goods_bauxite_ore/v19`. The shipped main art is unchanged; the alternate takes
priority at runtime. The builder is `tools/goods_icons/bauxite_ore/`.

## v19 (installed)

- **Renders:** `bauxite_ore_800.png` is the master. The 450, 256 and 60 px files are LANCZOS downsizes of it, and the
  800, 450 and 256 px ones are the installed tiers.
- **Builder:** `bauxite_ore.blend` is the saved scene, and `bauxite_kit_v19.py` the builder as installed.
- **Records:**
  - `bauxite_ore_metrics.json` is the build record (camera, closed hosts, nothing below ground);
  - `owner_sheet_v15.png` and `owner_sheet_v18.png` are the rounds the owner commented on, and `owner_sheet.png` is the
    approved v19;
  - `comparison.png` is v18 without the back lump beside v19.

## Record

Real bauxite traits used: an earthy rust red crust mottled with cream (gibbsite and clay), pisoids that show as rings
where the rock is cut, stand out of the crust as knobs and lie loose as pea gravel, and a rounded, crumbly fracture.

Owner direction, in order:

1. "look at the remaining good icons tht havent been migrated to blender. try bauxite ore. Look up bauxite ore in real
   life, identify a few distinguishing elements. Scrap the older attempt. It was too rudimentary and too many outlines
   poked through"
2. On v15: "i want a cleaner slice down the middle of the right hero and darker pea spots. The slice should be at the
   widest point of the rock. The other slice should be lying with the flat sliced side up"
3. On v18: "Go with the version without the back lump (two halves and the loose peas)."
4. On v19: "Approved. Install v19 as the bauxite ore alternate and open a PR."
