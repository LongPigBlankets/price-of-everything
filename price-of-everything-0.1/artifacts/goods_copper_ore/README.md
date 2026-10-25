# Copper ore (g_003) Blender icon

**Approved 2026-10-25** (owner: "ok approved, swap it in please"). The internal name is `copper_ore`. v15 is installed
as the approved alternate, `assets/icons/goods/alternate_icons/{medium,small,very_small}/g_003_copper_ore.png` (800,
450 and 256 px), and listed in `approved_manifest.json` with source `goods_copper_ore/v15`. It replaces the earlier
`mottle_rock` attempt in those files. The shipped main art is unchanged; the alternate takes priority at runtime. The
builder is `tools/goods_icons/copper_ore/`.

## v15 (installed)

- **Renders:** `copper_ore_800.png` is the master. The 450, 256 and 60 px files are LANCZOS downsizes of it, and the
  800, 450 and 256 px ones are the installed tiers. Re-rendered from the builder, the 800 px master is pixel-identical.
- **Builder:** `copper_ore.blend` is the saved scene, and `copper_kit_v15.py` the builder as installed.
- **Records:**
  - `copper_ore_metrics.json` is the build record (camera, closed hosts, nothing below ground);
  - `owner_sheet_v9.png`, `owner_sheet_v10.png` and `owner_sheet_v11.png` are the rounds the owner commented on, and
    `owner_sheet.png` is the approved v15 beside v11 at 600, 256 and 64 px.

## Record

Real copper ore traits used: a dark, earthy host rock stained by iron oxides, with paler and darker layers; green
malachite in streaks and stripes that run roughly parallel through a lump, plus green flecks; and brassy coppery gold
chalcopyrite grains, loose in the rock and caught in the veins. The rocks are hard broken lumps with planar breaks,
each break rim inked.

Owner direction, in order:

1. "attempt copper again as an icon now that we have many rock-like assets. Try to create a speckled and realisticaly
   striped/streaked dark brown plus green plus bits of coppery gold on the rocks"
2. On v8: "use a more reddish brown like ones in the old icon" (v9: the old art's browns, mid (150, 90, 66), lit
   (184, 124, 90), shaded (112, 64, 46), darkest (90, 52, 40); the gold made more brassy so it still separates)
3. On v9: "thicken some of the grey lines and make them less bright in the centre - a single green colour and darken it
   a bit" (v10: the streaks' pale core removed, one green, darker, and some whole stripes widened)
4. On v10: "reduce the number of gold specs by 30-40%" (v11: 55 specks to 38)
5. On v15: "ok approved, swap it in please"

An adversarial review of v8 drove v12 to v15, where it did not contradict the owner: the pattern switches off on faces
turned far from the view (specks squashed into slivers there), no 1 px veinlets or sub-5 px crumbs, a glint in the
larger gold grains and no halftone on gold, and angular chips (three cuts read as coffee beans). Rejected: alternating
pale and deep malachite layers (owner: one green), fewer stripes, no brown banding, and more gold. A crossing vein was
tried (v12, v13) and dropped: as a sheet in 3D it spread into a green blob wherever a face ran nearly parallel to it.
