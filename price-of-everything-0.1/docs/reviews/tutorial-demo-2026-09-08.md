# Demo tutorial and panel follow-up — 8 September 2026

The HUD tour now labels Shipments and Stockpiles, Power and Ranking, uses Supply chain view, and separates neighbouring annotation labels. Three lessons immediately follow it: selecting a tile, reading its Land Chart, and understanding its buildings, power, goods and stockpile sections. Later lessons keep their stable IDs; their displayed numbers shift with the added lessons.

Tutorial copy now introduces the motor recipe at the top of the building panel, explicitly asks for the factory tile before construction, explains recipe selection and tile-level power, and highlights the construction materials ledger. Tutorial cards have additional vertical padding and use the diagnostics body's 14px Caption typeface. The tile overview blocks panel actions until Next so closing the highlighted panel cannot interrupt the lesson.

Player building cards use the shared top-bar LED instead of the Running and power pills. The colour comes from the same diagnostic rows displayed in the building detail panel: any red makes the light red; multiple amber rows or amber without green make it amber; otherwise it is green. NPC ownership labels are retained. Critical fault and Unpowered descriptions use “This building doesn't have power. It can't run.”

Port metric columns both wrap within their allocated width, avoiding the long value squeezing its label into single characters. Both current terms and the rate card list all six sea-freight classes separately, using the configured throughput and applicable live modifiers. Percentages omit trailing zeroes. Recent sea freight labels its right-aligned fee values with “Fee paid”.

Validation:
- Parse sweep: 556 scripts, zero failures.
- Unit suite: 3,750 passed, zero failed, including the LED aggregation rules and lesson ordering.
- Expanded live tutorial regression: 120 checks, zero failures, including the new tile lessons, spotlights, six freight classes in both tables, both construction branches, research and advisor flow.
- Standard end-to-end scenario through turn 100: 723 assertions passed, zero failed.
- Visual review: HUD annotations, Land Chart, tile overview, motor recipe, port terms and construction-materials highlight.

The existing authored-map staleness and shutdown resource-leak warnings still appear in the live harness; this follow-up does not alter map bakes or rendering resource lifetimes.

Cable-step follow-up: `lay_cable_factory` previously waited for `SourcingBuyButton` to appear, but infrastructure now sources materials directly from the construction setting. It now checks for a cable construction project or completed cables on the factory tile and routes directly to `run_until_running`. The live regression clicks the real cable button, verifies rejection with insufficient funds does not advance, verifies a successful order advances, and verifies re-entering the step with an existing order recovers automatically.

Routing follow-up: output-destination cards consume mouse-down before calling actions that can hide the panel. This prevents the opening click from selecting the map tile underneath. The destination lesson ends on routing to the named coastal tile, followed by a separate End Turn spotlight that waits for windows in that destination stockpile. Step 25 splits its dash-separated sentence with a full stop. The live regression uses press/release input for both the destination option and the map tile, then runs actual production and transport through arrival. Test telemetry is disabled in the harness.

Integration and encyclopedia follow-up: the diagram names Polymerisation Refinery, and the margin, cost, supply-chain and encyclopedia lessons use the requested shorter copy without dash-separated sentences. Encyclopedia prose and captions use the shared 14px body size and off-white text on dark surfaces. The margin lesson no longer changes the output route silently. After browsing the encyclopedia, the player must select Global market before the separate shipment-sale lesson begins. Its completion filters for windows from the factory tile while allowing any travel duration, so another factory or good cannot complete it. The live regression verifies the unchanged coastal route, actual Market selection, unrelated-sale rejection, actual window sale, and encyclopedia body style. Unit suite: 3,748 passed; parse sweep: 556 scripts with zero failures.

Finance and glass-selection follow-up: the books lesson uses the requested operating-cost and power copy, with the gross-profit and net-profit equations on separate rows. Expansion loans now require any principal strictly above £200, with unit checks at £200 and £200.50; a real £250 loan advances the live tutorial. Loan terms and integration/glass lessons use the requested concise copy. The glass recipe spotlight waits for expanded-card layout and centres its row in the scroll viewport. The live regression verifies that the entire row is visible before clicking and captures the revised books panel.

Final finance follow-up validation: 3,750 unit checks passed; 104 live tutorial checks passed; 556 scripts passed the parse sweep.

Surplus, settling and advisor follow-up: the land lesson uses a full stop, and the surplus, furnace construction, recipe-change and advisor-seat lessons use the requested copy. Glass integration waits three turns rather than two before displaying the profit result. The live regression checks that the result remains hidden after turns one and two and appears after turn three. The recipe-change lesson closes Research and returns to the factory tile so the Furnace can be selected. Live tutorial regression: 120 checks, zero failures.

Advisor comparison follow-up: comparison and hiring have no spotlight or dimming and close stale money/building panels on entry. Viewing profiles and changing seats leave comparison active; the new Choose this advisor action explicitly advances to hiring. Both stages allow returning to other candidates. Financial previews show bonuses minus salary as a net-benefit line. Negative values warn but do not block choice: the completed-glass test fixture offered no candidate whose current benefits covered salary, so a hard positive-value requirement would soft-lock the lesson. The live regression compares multiple candidates and confirms explicit choice and hiring.
