# Circuit board (g_043) Blender icon

**Approved 2026-10-01** (owner: "ok, approved.", on v6). The internal name is `circuit_board`. v6 is installed as the
approved alternate, `assets/icons/goods/alternate_icons/{medium,small,very_small}/g_043_circuit_board.png` (800, 450 and
256 px), and listed in `approved_manifest.json` with source `goods_circuit_board/v6`. The shipped main art is unchanged;
the alternate takes priority at runtime.

## v6 (installed)

- **Renders:** `circuit_board_800.png` is the master. The 450, 256 and 60 px files are LANCZOS downsizes of it, and the
  800, 450 and 256 px ones are the installed tiers.
- **Scene and builder:** `circuit_board.blend` is the saved scene, and `circuit_kit_v6.py` the builder as installed.
- **Records:** `circuit_board_metrics.json` is the build record, and `circuit_board_800_line_weights.json` records the
  12/4 px lines.
- **Checks:** `saved_scene_verification.json` shows no failures.
- **Proof sheets:** `comparison.png`, `ds2_well.png` and `regions_3x.png`.
- **Owner sheets:** `owner_sheet_v4.png` (the first build), `owner_sheet_v5.png` (thicker) and `owner_sheet.png` (v6, the
  approved one).

## Record

Owner direction, verbatim, in order:

1. "Next do circuits"
2. On v4: "give it a bit more thickness? And is there anything unrealistic about a circuit board like that?"
3. On v5: "ok fix the traces and fingers please. We dont want to add a chip in the middle but maybe a slot marking where
   the CPU and its slot will come in (since thats a different good)."
4. On v6: "ok, approved."

Kept as a stylisation, discussed with the owner: gold traces (on a real board they sit under the green mask), the board's
thickness, and the raised pads.
