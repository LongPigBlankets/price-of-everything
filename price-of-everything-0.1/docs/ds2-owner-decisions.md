# DS2 UI: the owner's decisions

The rulings the owner made while the top bar, the updates dock and the tile view moved to DS2 (September 2026, branch `top-bar-v3-and-updates`). Each is settled: build on it, don't re-open it. The plans hold the detail (`docs/top-bar-ds2-plan.md`, `docs/tile-view-ds2-plan.md`); the method and the kit are in `docs/ds2-theme.md` (§13 is how the top bar was done).

## Everywhere

- **Build behind a switch, one owner-sized step at a time.** Show captures after each step; commit locally once the step holds. The old surface stays exactly as it was with the switch off.
- **Text**: body 14 px (IBM Plex Sans Medium, semibold for a row's own title), metal-label captions 15 px (Barlow Condensed SemiBold), the printed £ 18 px. A compact strip such as the bar may go smaller, never under 12 px. White on anything dark; navy on anything light (stainless, concrete, white plastic), with DS2's light-surface inks for semantic figures (#1d6b3a, #7a4a00, #8f1f19) and a faint light shadow, not a dark outline.
- **Icons are sized by their drawn art, not their canvas**, to one cap height on one midline; thin icons get a tabled optical factor.
- **Icons are raised as Building Detail's are** (cream enamel relief with its swept shadow, render set per surface). The knob's icons may later be embossed in the new off-white (a refinement, not yet done).
- **Figures come from the engine's own helpers**; the lamp and the words that explain it come from one status helper, so they cannot disagree.
- **Copy**: plain and brief, no hyphens, semicolons, dashes or middle dots; the owner's wording where given (below).

## Top bar (the default; `toggle topbar ds2` switches back to v3.1)

- **60 px**, one height, no notch. Panels under it start at y 72.
- **Material**: the standard DS2 weathered navy steel. No brass. A steel **H-beam** runs along the foot (two raised flanges, the web recessed and bolted, little rust). Tried and rejected: brushed titanium, a navy lacquered sheet, a silver pipe along the foot.
- **Money in the centre** on clean **light beige-grey concrete** between two pillars. The cash on an **LED screen in white, red below zero**, the **£ printed outside the screen**, K or M printed after it. **At most five characters**: two decimals below £1,000, whole pounds to £9999, then £15.6K (one decimal to £999.9K), then £1.01M and so on. The profit line stays as text below, in the darker light-surface inks. No coin icon.
- **Pipes**: a pair of polished silver pipes rises just off each side of the concrete, symmetrical about the money, and runs along beneath the beam to meet the other side (1 px thinner and 1 px closer than first built, so the loop ends at y 69, clear of the panels).
- **Mission** sits left of the left pipes, icon first, text to its right, never crossing into another section (trimmed with an ellipsis). It moves to the dock as a work order later.
- **Icons** raised as Building Detail's; **lamps** are Building Detail's pilot lamps. Goods Graph, Encyclopedia and Menu stay raised icons (no keycaps) and show no lamp in their readout.
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
