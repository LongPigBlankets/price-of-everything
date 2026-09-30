# Plastics (g_027) Blender icon

**Approved 2026-09-30** (owner: "that's pretty good. approved.", on v33). The good's internal name is
`plastics`. v33 is installed as the approved alternate,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_027_plastics.png` (800, 450 and 256 px), and
listed in `approved_manifest.json` with source `goods_plastics/v33`. The shipped main art
(`assets/icons/goods/{medium,small,very_small}/g_027_plastics.png`) is unchanged; the alternate takes
priority at runtime.

## v33 (installed)

- `plastics_800.png` is the transparent master. `plastics_450.png`, `plastics_256.png` and `plastics_60.png`
  are LANCZOS downsizes of it. The 800, 450 and 256 px files are the installed tiers.
- `plastics.blend` is the editable saved scene.
- `plastics_kit_v33.py` and `chair_geom_v33.py` are the builder as installed (the same files as
  `tools/goods_icons/plastics/`).
- `owner_sheet.png` is the sheet the owner approved: the shipped art, v28 and v33, with the bag at 2x.
- `owner_sheet_chair_v28.png` is the sheet on which the owner took the downloaded chair ("great").
- `comparison.png`, `ds2_well.png` and `regions_3x.png` are the proof sheets for v33:
  - the shipped art beside v28 and v33;
  - the 72 and 144 px wells beside neighbouring goods;
  - the master's quadrants at 3x.
- `plastics_metrics.json` is the build record. It holds the chair's placement (`CHAIR_MESH`), the bottle's
  and bag's fitted geometry (`BOTTLE`, `BAG`, the creases), the pellet count, the outline and stipple
  settings, and the camera and mesh checks.
- `saved_scene_verification.json` checks the camera, closed hosts, nothing below ground, and that the
  bottle and the bag clear the chair. No failures.
- `plastics_800_line_weights.json` records the 12 px outer and 4 px inner lines.
- `pixel_metrics.json` holds the bounding box, ink colour, grey steps and blue and cream shares.

The builder and re-render commands are in `tools/goods_icons/plastics/`. Re-rendered from that copy at
install, the 800 px master matched this one except for 3 pixels that differ by one level, and the
saved-scene check matched.

## How it was built

Each object was mapped to the shipped art rather than drawn freehand (owner: "try to map the topology of
each object, one by one"). It was then reviewed by an adversarial reviewer until it passed ("keep looping
with the reviewer until its done").

- **Chair.** First a parametric monobloc (`chair_geom.py`) was fitted to the shipped chair's inked
  silhouette, then its legs were reworked to the owner's direction.
  - The owner then supplied a downloaded model: Poly Haven's "Plastic Monobloc Chair 01" by Kuutti
    Siitonen, licensed CC0.
  - v28 uses it, welded into one closed solid and placed on the shipped chair by its silhouette, square to
    the grid.
  - Its ink comes from its own creases and contours.
  - It keeps the model's own design (four back slots and a slotted seat, where the shipped art has three
    slots and a solid seat); the owner took it as it is.
- **Bottle.** Fitted to the shipped bottle's silhouette, with its ring heights measured.
- **Bag.** Fitted to the shipped bag's silhouette; its lips, heap and creases were read off the shipped ink
  by back-projection. v29–v33 answered the owner's last two notes:
  - **The left handle.** It now runs across the mouth's left end and faces the viewer, as the shipped one
    does. Its inner leg rises out of the front lip and its outer leg out of the bag's rounded end, both
    twisting out of the film.
  - **The pellets.** The mouth is filled down past the lip, the same way as the alumina sack. The pile slopes
    down to the front lip, which cuts the lowest beads, and it ends in crowns against the walls. The beads
    are chosen so that no visible piece is a crumb.

## Record

Owner direction, verbatim, in order:

1. "approved. Please move onto plastics, iterate on that with the topology of the chair and the plastic
   bottle. The bag might be difficult but try to get close. Then rubber. Both are difficult icons but keep
   looping with the reviewer until its done"
2. "try to map the topology of each object, one by one. Do the plastic chair first"
3. "plastics is almost there. Use thinner internal linework (aside from the outer outline). Next we need to
   review the legs. The back is pretty much there. The shape of the legs needs to be identical across all
   four legs but they meet the seat and arms in slightly different ways" (which leg to copy: "Current back
   leg")
4. "the front leg should be the back leg but rotated 9 degrees. Look at the shape - it should be concave
   from the camera's POV"
5. "not quite. What you need is two very tall rectangles at 90 degrees and a quarter circle at the bottom.
   This quarter circle's radius is a bit larger than the short side of the two rectangles. Then the quarter
   circle merges into a thin connecting band on at 90 degree angle with the rightmost rectangle and follows
   it until near the seat where it curves out and further to the right"
6. "look at the latest download - a zip file. does it contain a blender friendly file you could use
   instead?"
7. On v28: "great, just the bag needs a bit more attention, the left handle looks illogical, it doesnt meet
   the front face of the bag. Also the nurdles look suspended, add more underneath, using the same
   technique used in the alumina bag"
8. On v33: "that's pretty good. approved."

Reviews of the bag:
- **v29, not ready.** The left handle's outer leg stood inside the outline. The fill left a shelf of the
  bag's inside. The right handle's leg hung in the mouth. There were crumbs.
- **v30, not ready.** A bead sat on the corner, the right lip ran into the leg, the arch ran tangent to the
  chair, and there were shards.
- **v31, not ready.** The core showed tan, and the lip's highlight crossed the feet.
- **v32, not ready.** The right outer leg's twist pinched it.
- **v33, ready for the owner.**

Left as polish:
- about seven 1–3 px pellet pieces where the pile meets a strap's edge line;
- a small window of the bag's inside at the pile's top-right;
- the chair's lines meeting the left arch.
