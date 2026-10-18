# Metallurgical silicon (g_047) Blender icon

**Approved 2026-10-18** (owner: "Approved. Install v44 as the metallurgical silicon alternate and open a PR."). The
internal name is `metallurgical_silicon`. v44 is installed as the approved alternate,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_047_metallurgical_silicon.png` (800, 450 and 256 px),
and listed in `approved_manifest.json` with source `goods_metallurgical_silicon/v44`. The shipped main art is unchanged;
the alternate takes priority at runtime. The builder is `tools/goods_icons/metallurgical_silicon/`.

## v44 (installed)

- **Renders:** `metallurgical_silicon_800.png` is the master. The 450, 256 and 60 px files are LANCZOS downsizes of it,
  and the 800, 450 and 256 px ones are the installed tiers.
- **Builder:** `metallurgical_silicon.blend` is the saved scene, and `ms_kit_v44.py` the builder as installed.
- **Records:**
  - `metallurgical_silicon_metrics.json` is the build record (camera, closed hosts, nothing below ground);
  - `old_icon_reference.png` is the shipped art whose topology was targeted;
  - `iterations_v2_to_v14.png` shows the first rounds;
  - `owner_sheet_v14.png`, `_v22`, `_v27`, `_v37` and `_v43` are the rounds the owner commented on, and
    `owner_sheet.png` is the approved v44;
  - the `end_*.png` sheets compare the broken end between rounds.
- **Review:** one adversarial review ran on v9. Its six measured gaps drove v10 to v14: the fan, the proportions, the
  silhouette, the crown, the mirrors and the tone spread.

## Record

Owner direction, in order:

1. "Next tackle metallurgical silicon. Look at the topology of the current icon and target it through a few iterations"
2. On v14: "the body itself looks great. What needs more detail and a bit more relief is the round-ish face itself (the
   one to the left)"
3. On v22: "the triangular slices need more complex shapes. Look at how the old icon does it"
4. On v27: "you've slanted it slightly towards us. The original plane was better. But ultimately it's a step in the
   right direction. Try a simpler fracture layout on that plane that doesnt emanate from a single point in the middle"
5. On v37: "A few more cracks wold do it + a gentler bevel at the corner between the cylinder and the round face. Also
   add the same lighting and reflective surfaces as tehe cylinder surface"
6. On v43: "thinner lines between the cracks on the round face"
7. On v44: "Approved. Install v44 as the metallurgical silicon alternate and open a PR."
