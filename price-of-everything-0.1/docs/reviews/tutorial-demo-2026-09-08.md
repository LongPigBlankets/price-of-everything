# Demo tutorial and panel follow-up — 8 September 2026

The HUD tour now labels Shipments and Stockpiles, Power and Ranking, uses Supply chain view, and separates neighbouring annotation labels. Three lessons immediately follow it: selecting a tile, reading its Land Chart, and understanding its buildings, power, goods and stockpile sections. Later lessons keep their stable IDs; their displayed numbers shift with the added lessons.

Tutorial copy now introduces the motor recipe at the top of the building panel, explicitly asks for the factory tile before construction, explains recipe selection and tile-level power, and highlights the construction materials ledger. Tutorial cards have additional vertical padding and use the diagnostics body's 14px Caption typeface. The tile overview blocks panel actions until Next so closing the highlighted panel cannot interrupt the lesson.

Player building cards use the shared top-bar LED instead of the Running and power pills. The colour comes from the same diagnostic rows displayed in the building detail panel: any red makes the light red; multiple amber rows or amber without green make it amber; otherwise it is green. NPC ownership labels are retained. Critical fault and Unpowered descriptions use “This building doesn't have power. It can't run.”

Port metric columns both wrap within their allocated width, avoiding the long value squeezing its label into single characters. Both current terms and the rate card list all six sea-freight classes separately, using the configured throughput and applicable live modifiers. Percentages omit trailing zeroes. Recent sea freight labels its right-aligned fee values with “Fee paid”.

Validation:
- Parse sweep: 556 scripts, zero failures.
- Unit suite: 3,748 passed, zero failed, including the LED aggregation rules and lesson ordering.
- Expanded live tutorial regression: 80 checks, zero failures, including the new tile lessons, spotlights, six freight classes in both tables, both construction branches, research and advisor flow.
- Standard end-to-end scenario through turn 100: 723 assertions passed, zero failed.
- Visual review: HUD annotations, Land Chart, tile overview, motor recipe, port terms and construction-materials highlight.

The existing authored-map staleness and shutdown resource-leak warnings still appear in the live harness; this follow-up does not alter map bakes or rendering resource lifetimes.

Cable-step follow-up: `lay_cable_factory` previously waited for `SourcingBuyButton` to appear, but infrastructure now sources materials directly from the construction setting. It now checks for a cable construction project or completed cables on the factory tile and routes directly to `run_until_running`. The live regression clicks the real cable button, verifies rejection with insufficient funds does not advance, verifies a successful order advances, and verifies re-entering the step with an existing order recovers automatically.
