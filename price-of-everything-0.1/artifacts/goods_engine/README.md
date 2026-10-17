# Engine (g_046) Blender icon

**Approved 2026-10-17** (owner: "Engine v12 approved. Install it as the alternate icon."). The internal name is `engine`.
v12 is installed as the approved alternate, `assets/icons/goods/alternate_icons/{medium,small,very_small}/g_046_engine.png`
(800, 450 and 256 px), and listed in `approved_manifest.json` with source `goods_engine/v12`. The shipped main art is
unchanged; the alternate takes priority at runtime.

## v12 (installed)

- **Renders:** `engine_800.png` is the master. `engine_450.png`, `engine_256.png` and `engine_60.png` are LANCZOS downsizes
  of it, and the 800, 450 and 256 px files are the installed tiers. `engine_raw.png` and `engine_raw_mask.png` are the
  Blender colour and shading passes.
- **Scene and builder:** `engine.blend` is the saved scene, and `engine_kit_v12.py` the builder as installed. The live
  builder and render tooling are in `tools/goods_icons/engine/`.
- **Records:** `engine_metrics.json` is the build record (camera angles, dimensions), and `engine_800_line_weights.json`
  records the 12/4 px lines. `runtime_check.gd` loads the three tiers and checks sizes, mipmaps and that the lookup
  resolves to the alternate.
- **Proof sheets:** `owner_sheet.png` (shipped / v11 / v12), `owner_sheet_v11.png`, `owner_sheet_v7.png`,
  `regions_3x.png`, and `outline_vs_cpu_silicon.png` (v12 beside the CPU and high grade silicon icons).

## Record

Owner direction, verbatim, in order:

1. "Let's try engine first. the most geometric. Use the existing asset as the reference and rebuild it in blender
   according to the existing asset creation rules (isometric, no thick outer line etc.)"
2. On v7: "keep refining but needs at least one engineering pass + if possible the same angle of the cams as the old
   one"
3. On v11: "pretty good. can we make the red caps more rounded (like rounded corner rectangles similar to the older
   model) and also the outer outline should be consistent with some of the more recent icons like the CPU and high
   grade silicon"
4. On v12: "Engine v12 approved. Install it as the alternate icon."

What each round settled:

- **v1 to v7:** proportions, tones and the red-framed timing end against the shipped art, with stylised 20 degree banks.
  An adversarial review of v4 drove v5 (timing frame, round plenum, warm castings, log exhaust, crisp covers).
- **v8 to v11, the engineering pass:**
  - The block is a real 90 degree V8. Each bank's cylinder axis runs through the crank at 45 degrees, so the heads,
    decks and covers share one geometry. The shipped art's cam covers measure 46 degrees, and so does v11.
  - The lower intake fills the valley, with arched runners from the plenum and the throttle body facing forward.
  - Cast-iron primaries drop from each head into a log.
  - The crank pulley sits on the crank axis. The water pump sits above it, and the alternator has a pivot bracket and a
    slotted strap, all on one belt.
  - Also added: a thermostat neck, an engine mount, an oil filter, and a pan with a rear sump.
  - An engineering review of v10 drove v11.
- **v12:**
  - The cam covers are rounded rectangles with filleted tops on a rounded flange, and a line rings the raised panel.
  - The outer line was already the set's 12 px, measured on the CPU and silicon at 12 to 13 px. It read differently
    because the silhouette was lumpy, so v12 removes the stepped cover corners and the exhaust outlet knob, and lifts
    the iron a shade so it no longer merges with the outline.
