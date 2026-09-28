# DS2 UI: the owner's decisions

The rulings the owner made while the top bar, the updates dock and the tile view moved to DS2 (September 2026, branch `top-bar-v3-and-updates`). Each is settled: build on it, don't re-open it. The plans hold the detail (`docs/top-bar-ds2-plan.md`, `docs/tile-view-ds2-plan.md`); the method and the kit are in `docs/ds2-theme.md` (§13 is how the top bar was done).

## Everywhere

- **Build behind a switch, one owner-sized step at a time.** Show captures after each step; commit locally once the step holds. The old surface stays exactly as it was with the switch off.
- **Text**: body 14 px (IBM Plex Sans Medium, semibold for a row's own title), metal-label captions 15 px (Barlow Condensed SemiBold), the printed £ 18 px. A compact strip such as the bar may go smaller, never under 12 px. White on anything dark; navy on anything light (stainless, concrete, white plastic), with DS2's light-surface inks for semantic figures (#1d6b3a, #7a4a00, #8f1f19) and a faint light shadow, not a dark outline.
- **Icons are sized by their drawn art, not their canvas**, to one cap height on one midline; thin icons get a tabled optical factor.
- **Icons are raised as Building Detail's are** (cream enamel relief with its swept shadow, render set per surface). The knob's icons may later be embossed in the new off-white (a refinement, not yet done).
- **The lamp, part by part** (`scripts/ds2/lamp_overlay.gd`) on every DS2 panel, Building Detail included (27 September 2026). The top bar is the exception (below).
- **Figures come from the engine's own helpers**; the lamp and the words that explain it come from one status helper, so they cannot disagree.
- **Copy**: plain and brief, no hyphens, semicolons, dashes or middle dots; the owner's wording where given (below).

## Top bar (the default; `toggle topbar ds2` switches back to v3.1)

- **60 px**, one height, no notch. Panels under it start at y 72.
- **Material**: the standard DS2 weathered navy steel. No brass. A steel **H-beam** runs along the foot (two raised flanges, the web recessed and bolted, little rust). Tried and rejected: brushed titanium, a navy lacquered sheet, a silver pipe along the foot.
- **Money in the centre** on clean **light beige-grey concrete** between two pillars. The cash on an **LED screen in white, red below zero**, the **£ printed outside the screen**, K or M printed after it. **At most five characters**: two decimals below £1,000, whole pounds to £9999, then £15.6K (one decimal to £999.9K), then £1.01M and so on. The profit line stays as text below, in the darker light-surface inks. No coin icon.
- **Pipes**: a pair of polished silver pipes rises just off each side of the concrete, symmetrical about the money, and runs along beneath the beam to meet the other side (1 px thinner and 1 px closer than first built, so the loop ends at y 69, clear of the panels).
- **Mission** sits left of the left pipes, icon first, text to its right, never crossing into another section (trimmed with an ellipsis). It moves to the dock as a work order later.
- **Icons** raised as Building Detail's; **lamps** are Building Detail's pilot lamps. Goods Graph, Encyclopedia and Menu stay raised icons (no keycaps) and show no lamp in their readout.
- **Light**: a simple light from left to right (27 September 2026): the bar is not tall enough for the corner lamp's fall to the bottom right. It keeps its one overlay, not the part by part lamp.
- **Victory**: the score on a drum counter with "/1,000" printed after it. The turn stays as text.
- **Hover readouts** under the bar, in the owner's words:
  - Power: "You generated X MW. Y MW came from the national grid."
  - Links: green "All shipments are working as expected.", amber "Some tiles are approaching capacity.", red "Transport is backlogged and we're paying overages."
  - Freight: "Nothing shipping to market." or "Lots of shipments, nothing to worry about."
  - Rankings: "How you rank compared to your competitors in revenue and goods production."
  - Council: "advisors", not "advisers".
  - Treasury: "Loan capacity", not "borrowing room".
  - Victory: "To win, score as many points as you can across the five tracks."
- **Flyouts**: Treasury and Power are **sheets in the bar's navy steel** (no trim). Treasury's figures sit in **three all-dark plates** (cash; cash in and costs; loans), no light edge, Building Detail's silver screws set in near each corner; its keys' labels centred. Power is two slide switches and a key. **Victory and Council open their full panels**; **Rankings is its own panel**. The mission's flyout goes to the dock with the mission.

## Updates dock (bottom left)

- Every toast is a row in a slide-out over a 60 px dock that collapses after 5 s; the **white countdown line** runs across all shown rows.
- A **fountain pen** for decisions (opens the briefing), then **green, amber and red bells**; each bell **filters** the slide-out to its rows. Research unlocks are green rows at the top ("Unlocked: <name>"); notices are amber rows. The briefing notch in the top bar is gone. The auto bridge loan posts once.

## Tile view (the default; `toggle tvp v3` switches back to v2)

- **The concept is the site's control cabinet** (`docs/tile-view-ds2-plan.md` §9): a **brushed stainless** backing, a **black pipe** round its edge, metal and plastic parts, **cables joining building cards of the same group**.
- **Five latching keys**: Buildings, Power, Goods, Stock and Transport (infrastructure moves out of Buildings into its own tab).
- **The photo goes**; coordinates only on hover.
- **Your buildings only** in Goods and Power, at this turn's real output (built). **Other companies fold** to one line; the "Show your buildings only" checkbox retires. The **power-plant catalogue becomes one Build power key** into Construct.
- **Warehouse, surplus and logistics controls** show only where you own land or have goods (built). **Links open their tab** (built).
- **The knob** is the existing **white plastic knob** (`scripts/rotary_selector.gd`), for any choice of three to seven options. **Its options are icons on its arc, each a button** that turns the knob to it; the knob's name is its only text. Built for the tile's surplus route. The owner is happy with it.
- **The land is a hex of squares, one per unit of land, filling from the bottom** (owner, 25 September 2026, after bars, a dial, counters and plots were weighed). It is **sized by the tile's maximum**, never showing squares past it. Other companies' land fills first, so the fill's top is the space the planning rule counts; the **planning limit** is the line after the 100th square. **Two versions**: collapsed, an LED dot-matrix screen at the top of the panel for a glance; expanded, a full **annunciator panel** where each building's squares are **one shade**, your buildings in **shades of your company's colour** broken out beside it, and **thin lines between buildings**. Squares with padding rather than small hexes. Then refined: the **mini hex is one smooth hex, no squares, only the colour splits, no shades** (one colour per kind of land); in the **split view each building's squares form one compact block, no more than twice as long as wide**. The mini hex is **laid straight onto the silver plate with a thin black rim**, and bigger than first built.
- **Terrain indicators use the owner's sprite sheet** (city, hill, mountain, rural flat, sea, deep sea): the navy keyed out, the white glyph kept as the shape. On the stainless it is inked navy like the words beside it, **standing right above the mini hex**, its hover saying how much land that terrain allows.
- **The planning limit's tape never matches the player's colour**: yellow on black, or **red on white when the player's livery is yellow**.
- **Cables and HVDC stay in Transport** with every other link. The Power tab shows their sections too, but only when they are built. A tile with no cables where your buildings make or draw power says **"Cables missing. Power production (or consumption) not possible."**, and the Power key's mark goes red.
- **The cabinet shell is built** (the stainless door and its pipe, the engraved nameplate, the five latching keys); the tab bodies still sit on navy steel sheets until each is restyled. See `docs/tile-view-ds2-plan.md` §9, Phase 2.

## Digital displays (26 September 2026, from the Construct studies; made the rule everywhere 27 September 2026)

- **The decimal point takes a cell of its own** on every LED screen in the game, as wide as a digit's (`bdp_v3_led.gd`, the default).
- **At most five cells, the point counted, and never more than two decimals.** Money on a screen: two decimals below £100 (1.15, 9.99, 99.99), one decimal from £100 (999.1), whole pounds from £1,000 (9999), then £15.6K (to 999.9K), £1.01M, £1.01B with the letter printed after the screen. A minus takes a cell, so a loss drops decimals to fit (-10.4). Other figures on screens follow the same cap; a figure is never given more decimals than it came with.
- **A materials cost is whole pounds only** (it was too busy with pence).
- Every LED fits its figure itself (`BdpV3Led.fit`, through `scripts/ds2/money_figure.gd` `screen`), so every panel (Building Detail, the top bar and its Treasury sheet, the tile view, the ledger, the upgrade panel, People) follows it; a group's screens are padded to the widest fitted figure, so they stay one width.

## Construct (26 September 2026; plan `docs/construct-ds2-plan.md`)

- **The construction lot with its crane** is the concept (over the works office). One width for every stage.
- **The tile's name** sits on a placard hung from the jib, symmetrical to the CONSTRUCT plate on the cab, when a tile is chosen.
- **The tower** is wide and cut off by the panel's edge, so only part of it shows (half the width of study round 2).
- **The search field** sits under the crane in a tab rising from the category plate.
- **Priority in the build order**: what is built, then the verdict (total, cash after, turns, the Build key, kept high: if you have the money, everything else is detail), then requirements, cost, materials, outlook; **the land use last**, good to look at but not the most important.
- **Materials**: no per good prices (the materials total speaks for them), the goods in a grid of two columns and three rows on one backing, the Materials from knob in the sixth cell. **The intermediary is the default source**, since it is faster.
- **A recipe is drawn, not named**: on a building's board the icon on the left and the recipe diagram in enamel on the right, expanded or condensed as the Construct setting says.
- **Names**: the building by what it makes, without its letter until built: "Iron Furnace", "Copper Furnace"; where several recipes make the same thing, the recipe tells them apart: "Motor Assembly Plant", "SynRM Motor Assembly Plant".
- **The Build key** (27 September) stays high in the verdict, where it is quick to decide, but as a plain cream key, not the guarded cap: building is not that big a decision. Its rim is polished brass, not the black metal bezel. Refused, it prints red, and a press makes the part that blocks glow instead of building: the money (Cash after), or the land's row when auto buy land is off (the row then offers Buy land), or the requirement that blocks.
- **Recipe diagrams** (27 September): a single row never draws goods under 48 px; three or more goods on a side go into two rows (the short row centred), a side of one or two beside them drawn larger. The recipe's name sits outside the diagram: on a catalogue tag in a tab rising between its chains, 15 px in from each.
- **The catalogue's building card** (27 September) is a blue shipping container with a plate on its left end for the icon, the name and the price, the price level with the foot of the icon. A recipe's diagram glows while hovered. The construction lot is the default construct panel. A card that can't be built there or paid for is grey; a price is white while the cash covers it twice over, red below (the build order's Total too).
- **The settings key** (27 September) is a white plastic key with a bevel and a navy gear. Since 28 September it stands on the crane's cab, left of CONSTRUCT, and the cab is four window panes wide to hold it.
- **Turns to deliver** (28 September): the verdict shows the materials' delivery beside the build on drums ("Turns to deliver + build"), so a cheaper, slower source (the global market) shows its wait next to its price. Cash after sits on a second row under Total and the Build key sits low beside it.
- **The Import/Export License** (28 September) needs £75 pre-tax profit a turn for 3 turns in a row (was £50 in one turn), so a start's free opening stock cannot unlock it on turn 1.
- **Every name in `docs/building-names.md` is approved as the table proposed it**, including the 19 rows that were marked for a second look (Limestone Mine, Sand Mine, Hairpin Stator Motor Assembly Plant and the rest). Only the unloaded farm recipes remain open.
- **Building icons**: the polished relief with its soft grey edge looked wrong; a simple emboss or flat print (a blueprint) is being compared.

## Resources (27 September 2026; plan `docs/resources-ds2-plan.md`)

- **No status lamps on goods.** Just in time play, and buying over a turn or two to sell straight away, hold little stock by design; a Low or Short lamp would call that a problem. The scenarios are too unclear for one lamp, so the table shows the figures and no verdict.

## People (27 September 2026; plan `docs/people-ds2-plan.md`)

- **The boardroom and the works are the default**; `toggle people ds2` switches back to today's panel.
- **The picker and the dossier are white on dark**, on a dark gunmetal sheet, the dossier in two columns so neither half is empty.
- **Dismiss is a guarded cap with a boot** under its clear cover.
- **A padlock means the council is full.** With a slot free, a seat not yet opened says what opens it; the council plate reads **X/Y advisors** (seated of the most you can seat now).
- **A CFO's worth is today's**: the interest her cut saves on the loans the company has now, nothing without loans.
- **No reduced salary** for Vera; the promise is gone.

