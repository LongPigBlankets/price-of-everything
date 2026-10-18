# Biomass (g_062) Blender icon

**Approved 2026-10-18** (owner: "Approved. Install v29 as the biomass alternate and open a PR."). The internal name is
`biomass`. v29 is installed as the approved alternate,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_062_biomass.png` (800, 450 and 256 px), and listed in
`approved_manifest.json` with source `goods_biomass/v29`. The shipped main art is unchanged; the alternate takes priority
at runtime. The builder is `tools/goods_icons/biomass/`.

## v29 (installed)

- **Renders:** `biomass_800.png` is the master. The 450, 256 and 60 px files are LANCZOS downsizes of it, and the 800,
  450 and 256 px ones are the installed tiers.
- **Builder:** `biomass.blend` is the saved scene, and `bm_kit_v29.py` the builder as installed.
- **Records:**
  - `biomass_metrics.json` is the build record (camera, closed hosts, nothing below ground);
  - `old_icon_reference.png` is the shipped art whose layout was kept;
  - `owner_sheet_logs_v3.png` and `logs_ends_zoom_v3.png`: the logs;
  - `owner_sheet_chips_v19.png`, `owner_sheet_chips_v21.png` and `heap_rounds_v8_v16_v19.png`: the chip heap;
  - `owner_sheet_v24.png` to `owner_sheet_v28.png` and `basket_v24_vs_v25.png`: the basket rounds;
  - `owner_sheet.png` and `basket_zoom.png`: the approved v29.

## Record

Owner direction, in order:

1. "next let's do biomass. Start with the logs first. Wooden logs"
2. On the logs (v3): "The logs look good. Move on to the next part of the biomass icon."
3. On the chips (v19): "first move the heap of woodchips back and make it lean against the rightmost log"
4. On v21: "The heap placement is good. Move on to the basket of apples and carrots."
5. On v24: "the apples and carrots look like they sit on top of a shelf in the basket. please let the basket be deeper
   inside or find a way for the apples to look half inside the basket as if there are more apples underneath. Same for
   the carrots"
6. On v25: "now make the carrots rounded at the top"
7. On v26: "add some leaves to the left of the carrots and partly overlapped. These are just leaves, not attached to
   anything. Also mute the carrots and apples colours a bit"
8. On v28: "make it at least 6 or 7 leaves"
9. On v29: "Approved. Install v29 as the biomass alternate and open a PR."
