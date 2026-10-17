# Large engine (g_052) Blender icon

**Approved 2026-10-17** (owner: "Large engine v10 approved. Install it as the alternate icon"). The internal name is
`large_engine`. v10 is installed as the approved alternate,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_052_large_engine.png` (800, 450 and 256 px), and listed in
`approved_manifest.json` with source `goods_large_engine/v10`. The shipped main art is unchanged; the alternate takes
priority at runtime.

## What it stands for

One good abstracts the big engines of the game:
- lorry engines;
- locomotive prime movers;
- later, as an input to ship components, ship engines and turbines.

It is also both combustion and electric. The icon is therefore built on the form those machines share: a heavy-duty
inline six diesel with a turbocharger, and a motor-generator on its shaft. That covers diesel-electric, hybrid and
generator use.

## v10 (installed)

- **Renders:** `large_engine_800.png` is the master. The 450, 256 and 60 px files are LANCZOS downsizes of it, and the
  800, 450 and 256 px files are the installed tiers. The `_raw` files are the Blender colour and shading passes.
- **Scene and builder:** `large_engine.blend` is the saved scene, and `le_kit_v10.py` the builder as installed.
  `build_le_d2` is the icon; the other builders are the concept studies. The live builder and render tooling are in
  `tools/goods_icons/large_engine/`.
- **Records:**
  - `large_engine_metrics.json`: the build record.
  - `large_engine_800_line_weights.json`: the line weights.
  - `runtime_check.gd`: loads the three tiers and checks sizes and mipmaps.
- **Proof sheets:**
  - `concepts_loop1_2.png`: locomotive power packs A, B and C, then A2 and C2.
  - `concepts_loop3.png`: the universal inline engine, D1, D2 and D3.
  - `owner_sheet_v4.png` to `owner_sheet.png` (v10): the D2 rounds.
  - `base_2x.png`: the base.
  - `output_end_2x.png`: the output end.

## Record

Owner direction, verbatim, in order:

1. "Let's do large engine next. First dreamloop a locomotive engine and use real world references for that. Try to
   make it somehow a combustion engine and a potential electric engine at the same time so we can abstract that"
2. On loops 1 and 2: "the trick is that this needs to represent both lorry engines and locomotive engines and in the
   future be a part that together with other inputs results in ship components (as a single good abstracting ship
   engines, turbines etc)"
3. On loop 3: "do D2 with a lip in the same layout as the old icon's - set out from the face with the holes in a
   circle. But what is the third set of blue boxes on the black rail at its base? It's not connected to any other part
   but the rail"
4. On D2 v4: "Good direction. Run your adversarial review on D2 and fold in its fixes, then show me."
5. On v5: "almost there. Where do the copper cables come from? i see they come out of the drive but what are they
   connecting to? Also the legs have lost some detail and maybe need a small raise and thinning and reshaping into
   smaller supports? Also wouldnt the cables be really small relative to such a large drive?"
6. On v6: "cables interpenetrate the ridges. I think move the box further out or reconsider the cables' position if
   that drive is meant to rotate"
7. On v7: "the cables should meet the top of the little box in black sleeves"
8. On v8: "cables should go in through the top of the sleeves (lower the box and shorten the sleeves to half their
   height). Also thicken the supports for the whole engine. Maybe a trapezoidal support that's narrower at the engine
   end/top) and wide and thick connecting the black bars"
9. On v9: "sorry i meant two to three trapezoidal supports that go from rail to rail and looks like a trapeze from the
   front"
10. On v10: "Large engine v10 approved."

What the icon is:

- **The engine:** a heavy-duty inline six. Slate heads carry six raised pale rocker covers, and brass crankcase doors
  run along the near flank, as on the shipped art.
- **Cold path (toward the camera):** air enters the brass compressor at the free end, goes down the charge-air pipe to
  the intake rail, and up a runner into each head.
- **Hot path:** a runner from each head into the dark exhaust manifold, back to the dark turbine and up the open stack.
- **Output end:** the flywheel housing, then a short slate motor-generator with axial cooling fins. Its yellow terminal
  box sits on the near flank below the fins. Three slim phase cables drop from it, through black sleeves, into a cable
  junction box on its own plate. Last comes the shipped icon's flywheel: a brass disc set out from the face, a raised
  lip, a dark recess, and a slate hub plate with a circle of ten holes and a bored boss. Only the shaft and flywheel
  turn.
- **Supports:** two base rails, with three cast cross supports spanning rail to rail. Each reads as a trapezoid from
  the front, bolted to both rails and narrowing to a saddle under the engine and motor-generator.

One independent review (of v4) drove v5:
- a shorter, finned motor-generator with the approved motor icon's yellow terminal box;
- the hot and cold paths made legible;
- the mounts attached;
- the rocker covers given the value hierarchy.
