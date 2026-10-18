# Pet coke (g_075) Blender icon

**Approved 2026-10-18** (owner: "Approved. Install v29 as the pet coke alternate and open a PR."). The internal name is
`pet_coke`. v29 is installed as the approved alternate,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_075_pet_coke.png` (800, 450 and 256 px), and listed in
`approved_manifest.json` with source `goods_pet_coke/v29`. The shipped main art is unchanged; the alternate takes priority
at runtime. The builder is `tools/goods_icons/pet_coke/`.

## v29 (installed)

- **Renders:** `pet_coke_800.png` is the master. The 450, 256 and 60 px files are LANCZOS downsizes of it, and the 800,
  450 and 256 px ones are the installed tiers. `pet_coke_hero_800.png` is the hero alone.
- **Builder:** `pet_coke.blend` is the saved scene, and `pc_kit_v29.py` the builder as installed.
- **Records:**
  - `pet_coke_metrics.json` is the build record (camera, closed hosts, nothing below ground);
  - `old_icon_reference.png` is the shipped art, and `earlier_failed_attempts.png` the four earlier Blender attempts;
  - `rounds_v1_v5_v9_v12.png`, then `owner_sheet_v12.png` to `owner_sheet_v27.png` are the rounds the owner commented on,
    with `hero_ends_zoom_v15.png` and `hero_old_vs_v20.png`;
  - `owner_sheet.png` and `chunks_zoom.png` are the approved v29.

## Record

Owner direction, in order:

1. "Ok now iterate on petcoke. This one has been the hardest so far with many failed attempts. The ridges and relief and
   hero nugget shape should be the priority"
2. On v12: "The hero nededs to be longer, uneven at the end and should have a wider and more jagged/ multifaced bottom"
3. On v15: "Yes, that's the bottom I meant. Keep refining the hero."
4. On v20: "the left side is a regression. we want the ridges still on that side"
5. On v21: "watch out for the interpenetration of the two nuggets and the hero + make the hero sit leaning properly as it
   would if gravity were a real thing on the other two nuggets"
6. On v25: "make the hero 15% shorter but not narrower. And make the sides of the hero a bit more jagged"
7. On v27: "The hero is good. Now refine the two supporting chunks to match."
8. On v29: "Approved. Install v29 as the pet coke alternate and open a PR."
