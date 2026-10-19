# Heavy vehicle (g_055) Blender icon

**Approved 2026-10-18** (owner: "ok now create a PR for this"). The internal name is `heavy_vehicle`. v38 is installed as
the approved alternate, `assets/icons/goods/alternate_icons/{medium,small,very_small}/g_055_heavy_vehicle.png` (800, 450
and 256 px), and listed in `approved_manifest.json` with source `goods_heavy_vehicle/v38`. The shipped main art is
unchanged; the alternate takes priority at runtime. The builder is `tools/goods_icons/heavy_vehicle/`.

## v38 (installed)

- **Renders:** `heavy_vehicle_800.png` is the master. The 450, 256 and 60 px files are LANCZOS downsizes of it, and the
  800, 450 and 256 px ones are the installed tiers.
- **Builder:** `heavy_vehicle.blend` is the saved scene, and `hv_kit_v38.py` the builder as installed.
- **Records:**
  - `heavy_vehicle_metrics.json` is the build record (camera, hosts, nothing below ground);
  - `old_icon_reference.png` is the shipped art;
  - `owner_sheet_v4.png` to `owner_sheet_v37.png` are the rounds the owner commented on, with `lorry_old_vs_v8.png` and
    `door_zoom_v21.png`;
  - `owner_sheet.png` and `under_zoom.png` are the approved v38.

## Record

Owner direction, in order:

1. "heavy vehicle first - use the existing cab and shape the rest of the lorry from there. Add windows, tyres and the
   trailer"
2. On v6: "add more detail to the trailer + the wheel guards + back bar and also add the whindshield + headlamps and
   emulate some more of the details from the old icon"
3. On v8: "i think make the lorry trailer 25% longer. Then begin working on the locomotive"
4. On v14: "i like the lorry, that's good, maybe tune the vibrancy of the blue down a bit. And then analyse the train vs
   the old one (the existing icon)"
5. On the analysis: "rework the loco in that order: taupe cab hood, then the nose shape, then the buffer beam and
   coupler, then the pantographs, shoulder and underframe"
6. On v19: "make the buffers more prominent and tweak the skirt to the angled shape on the other oner. Also make the
   radiator section narrower and merged to follow the shape of the nose. Also tweak the windshields so they mould to the
   shape of our trail's nose. And fix the door + detail near the door too"
7. On v21: "thinner linework on the front + larger headlamps (25% larger housing, slant it inwards towards the radiator
   and 20% larger lamps) Also add vents all along the side of the loco and a plate with 4 screws and a three hex logo in
   1 top, 2 bottom layout, pointy top hexes) Also add more detail to the bogeys, move the lorry a little bit away from
   the loco so the bogeys are visible and also more detail to the top + the pantographs"
8. On v26: "thinner linework on the bogeys. And centre the equipment on the top and make sure it doesnt overflow past the
   edge of the train. Also the vents should be taller and less split into many units. Long continuous vents. And the
   headlamps should be slanted the other way"
9. On v28: "widen the top of the train. right now it narrows into a thin strip and forces the pantograph and other vents
   to be too thin."
10. On v29: "then check the proportions compared to an actual locomotive from the 2010s. Should it be longer?" Against
    the Siemens Vectron (18.98 m over buffers, 3.01 m wide, 4.25 m over the lowered pantograph, 3.0 m bogie wheelbase)
    it was about 25% short for its width and 40% too tall. Owner: "lengthen the body to 6.0, lower the roof to 1.60, and
    lengthen the bogies and their spacing to match."
11. On v33: "adjust all bogies and maybe add any new wheels/bogies as required". Kept Bo'Bo', as the Vectron and TRAXX
    both are; the wheels went to the real 1.25 m.
12. On v35: "now move the lorry closer (so the lorry overlaps the bogies a bit at the front where its taller)"
13. On v37: "a little closer still"
14. On v38: "ok now create a PR for this"
