# Building frame (g_023) Blender icon

**Approved 2026-10-01** (owner: "cool, approved.", on v5). The internal name is `building_frame`. v5 is installed as the
approved alternate, `assets/icons/goods/alternate_icons/{medium,small,very_small}/g_023_building_frame.png` (800, 450
and 256 px), and listed in `approved_manifest.json` with source `goods_building_frame/v5`. The shipped main art is
unchanged; the alternate takes priority at runtime.

## v5 (installed)

- **Master and tiers:** `building_frame_800.png` is the master. The 450, 256 and 60 px files are LANCZOS downsizes of it,
  and the 800, 450 and 256 px ones are the installed tiers.
- **Scene and builder:** `building_frame.blend` is the saved scene, and `frame_kit_v5.py` is the builder as installed.
- **Build records:** `building_frame_metrics.json` is the build record, and `building_frame_800_line_weights.json`
  records the 12/4 px line weights.
- **Saved-scene check:** `saved_scene_verification.json` shows no failures.
- **Proof sheets:** `comparison.png`, `ds2_well.png` and `regions_3x.png`.
- **Owner sheets:** `owner_sheet_v2.png` to `owner_sheet_v4.png` are the rounds; `owner_sheet.png` is v5, the approved
  one.

## Record

Owner direction, verbatim, in order:

1. "let's do building frame next"
2. On v2: "make the cables from the left feed into the middle cables. And make the pipe poke through to the top so its
   hole is visible. And make the cables black with yellow stripes."
3. On v3: "something doesnt physically make sense about the pipe and the beam next to it. Like the horizontal beam is
   too far in. Just put the pipe through a cutout in the beam?" and "the cables that go horizontal dont follow 3d logic
   from this perspectivve. They should go to the right not become hidden behind the rightmost one."
4. On v4: "now add a 2nd pipe between the existing one and the corner. Same layout"
5. On v5: "cool, approved."

Still open (not raised again by the owner):
- The steel uses the approved steel icon's blue-grey rather than the shipped flat grey.
- The shipped art's doubled corner-post strips are not drawn.
