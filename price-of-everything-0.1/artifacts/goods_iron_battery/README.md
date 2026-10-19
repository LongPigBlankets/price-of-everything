# Iron-air battery (g_061) Blender icon

**Approved 2026-10-19** (owner: "Approved. Install iron-air v11 as the alternate and open a PR."). The internal name is
`iron_battery`. v11 is installed as the approved alternate,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_061_iron_battery.png` (800, 450 and 256 px), and listed
in `approved_manifest.json` with source `goods_iron_battery/v11`. The shipped main art is unchanged; the alternate takes
priority at runtime. The builder is `tools/goods_icons/iron_battery/`.

## v11 (installed)

- **Renders:** `iron_battery_800.png` is the master. The 450, 256 and 60 px files are LANCZOS downsizes of it, and the
  800, 450 and 256 px ones are the installed tiers.
- **Builder:** `iron_battery.blend` is the saved scene, and `fe_kit_v11.py` the builder as installed.
- **Records:**
  - `iron_battery_metrics.json` is the build record (camera, hosts, nothing below ground);
  - `old_icon_reference.png` is the shipped art;
  - `owner_sheet_v3.png` to `owner_sheet_v10.png` are the rounds the owner commented on, with
    `owner_sheet_v5_x_and_v.png` showing the X and V bracing side by side;
  - `owner_sheet.png` and `front_zoom.png` are the approved v11.

## Record

Owner direction, in order:

1. On v3: "do another pass for iron air but with thinner linework and the crossbars at the front"
2. On v4: "Note that iron air batteries are deeper. And the crossbars are meeting at the bottom. Also make the bars more
   pronounced and strop back part of the roof so they;re more visible. Also make the casters a bit more visible"
3. On v5, choosing between X and V bracing: "Use the V bracing, with the bars meeting at the bottom like the old icon."
4. On v6: "the bottom bars should be symmetrical not like a tick. The whole front should be all blades and the 2 cross
   bars like in the old one"
5. On v8: "almost - the wraparound housing should meet the bars"
6. On v9: "bars should hook/connect to the housing."
7. On v10: "just hook it onto the housing rather than using bolts and plates. Thiiner bars too"
8. On v11: "Approved. Install iron-air v11 as the alternate and open a PR."
