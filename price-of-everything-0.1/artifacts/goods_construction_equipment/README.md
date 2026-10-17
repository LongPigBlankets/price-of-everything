# Construction equipment (g_071, g_072) Blender icon

**Approved 2026-10-17** (owner: "Construction equipment v7 approved. Install it as the alternate icon for both ICE and
EV"). One icon serves both goods, as the shipped art did:
- `construction_equipment_ice` (g_071);
- `construction_equipment_ev` (g_072).

v7 is installed as the approved alternate for both, in three tiers each:
- `assets/icons/goods/alternate_icons/{medium,small,very_small}/g_071_construction_equipment_ice.png`
- `assets/icons/goods/alternate_icons/{medium,small,very_small}/g_072_construction_equipment_ev.png`

The tiers are 800, 450 and 256 px. Both goods are listed in `approved_manifest.json` with source
`goods_construction_equipment/v7`. The shipped main art is unchanged; the alternate takes priority at runtime.

## v7 (installed)

- **Renders:** `construction_equipment_800.png` is the master. The 450, 256 and 60 px files are LANCZOS downsizes of
  it, and the 800, 450 and 256 px files are the installed tiers. The `_raw` files are the Blender colour and shading
  passes.
- **Scene and builder:** `construction_equipment.blend` is the saved scene, and `ce_kit_v7.py` the builder as
  installed. The live builder and render tooling are in `tools/goods_icons/construction_equipment/`.
- **Records:** `construction_equipment_metrics.json` is the build record, and
  `construction_equipment_800_line_weights.json` the line weights. `runtime_check.gd` loads all six tiers and checks
  sizes and mipmaps.
- **Proof sheets:**
  - `owner_sheet.png`: shipped / v6 / v7.
  - `owner_sheet_v3.png`, `owner_sheet_v4.png`, `owner_sheet_v6.png`: the earlier rounds.
  - `foreground_2x.png`: the toolbox and the breaker.
  - `machine_zoom.png`: the cab and the wheels.

## Record

Owner direction, verbatim, in order:

1. "Next once done, I suggest iterating through construction equipment (choose 1 jackhammer standing + 1 backhoe) as
   the only parts of the icon"
2. Asked how to handle the two goods: "One icon for both"; asked which backhoe: "Backhoe loader".
3. On v3: "Looks like the right direction. Run your adversarial review and fold in its fixes, then show me."
4. On v4: "the jackhammer needs thinner outlines and no cable. the cab of the vehicle needs to have angles like a half
   octogon towards the front (use the old icon for reference) and a better colouring on the backhoe itself. Also more
   detailed wheels (tyre indents, inner detail on the wheel hubcaps)"
5. On v6: "move the jackhammer a bit to the right and add a yellow Dewalt style toolbox (about the same size as the
   jackhammer)"
6. On v7: "Construction equipment v7 approved."

What the icon is:

- **A JCB 3CX-class backhoe loader,** on real proportions (rear tyres about 1.36 m, front 1.0 m, a 2.2 m wheelbase, the
  cab roof at about 2.95 m).
  - **Cab:** a half-octagon front in plan.
  - **Loader:** arms on towers with lift rams, and a full-width bucket.
  - **Backhoe:** a 3CX pose on a sideshift carriage. A 2.3 m boom carries a 1.9 m dipper, with pinned rams on lugs and a
    D-shaped dark steel bucket.
  - **Stabilisers:** box-section legs rooted in towers.
  - **Wheels:** tread lugs, sidewall rings, dished hubs with nuts and vents.
- **A hand-held hydraulic breaker,** standing on its chisel with a thinner outline and no hose.
- **A yellow-and-black site toolbox** of about the breaker's size, unbranded.

It shows no exhaust stack and no charge port, so it fits both goods.

One independent review (v3) drove the v4 arm, linkage and breaker fixes. This tool's copy of `standard_lines.py`
takes each outline pixel's weight from the nearest pixel that belongs to a part. The resized label map's edge holes
otherwise stood out of the thinner breaker and toolbox outlines as ticks.
