# Alternate goods icons

User-requested alternate representations, September 2026.

| File stem | Representation |
| --- | --- |
| `g_002_iron_ore` | Approved hematite streaks, wider left edge seams, restored crown patch and fine foreground ink; installed as default in all tiers. |
| `g_001_coal` | Approved bottom-heavy fractured coal; also installed as the default game icon in all three tiers. |
| `g_016_limestone` | Seven warm limestone chunks with contrasting sedimentary strata. |
| `g_036_electrical_components` | Yellow breaker with distinct top/front tones, recessed constant-width folded switch matching the reference, copper strands, thin inset frames and cable-base seams, bulb and lowered voltmeter. |
| `g_024_ethylene` | Glass flask, continuous liquid volume with coloured top surface, curved formula label. |

Each file is a transparent RGBA PNG. Tiers mirror the existing goods folder:
`medium` = 800 px, `small` = 450 px, `very_small` = 256 px.
Coal and iron ore are also installed in the default game tiers, as requested. Other alternates retain the existing default selection.

Godot import sidecars are committed for every alternate. Their complete `[params]`
blocks match established goods icons in the corresponding tier, including
`mipmaps/generate=true`, `mipmaps/limit=-1` and alpha-border correction.

Editable `.blend` sources, raw colour/mask renders, 128/64 px previews, comparison images
and review evidence are in
[palette_refinement](../../../../artifacts/goods_material_studies/palette_refinement/).
The latest electrical model, PNGs and original-switch close-up comparison are in
[switch_reference_refinement](../../../../artifacts/goods_material_studies/switch_reference_refinement/).
The build workflow is documented in
[material_studies](../../../../tools/goods_icons/material_studies/README.md).
