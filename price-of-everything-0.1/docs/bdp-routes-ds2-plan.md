# Building Detail's input and output sheets in DS2

The Input sources and Output destination sheets that open from Building Detail v3's Inputs and Outputs keys, moved to DS2 (`docs/ds2-theme.md`). `UiPrefs.use_routes_ds2` is the default (owner, 26 September); `toggle routes ds2` switches back. With it off the v2 sheets are exactly as they were. Code: `scripts/bdp_v3_routes.gd`. Captures: `tools/bdp_routes_shot.tscn`. Test: `_test_bdp_routes_ds2`.

## What the v2 sheets had (inventory, 26 September)

| Element | v2 | Problem |
|---|---|---|
| Surface | flat navy cards on the sheet's steel | DS2 rule 1: no flat cards |
| Choices | bare icon tiles, the chosen one a little bluer; names only on hover | can't tell what each is or which is chosen |
| Primary / Fallback | grey "PRIMARY" captions over the tiles | grey on steel, hard to read |
| Route details | a `[-]` bracket toggle, "32 Steel/turn from Stoneshore Docks - (5, 10)" | copy rules (dash, coordinates); in a game without the intermediary the line said "from the tile" while the market was chosen |
| Destination | a second card saying where the output goes | repeats Route details |
| Money | none (freight only on the output's Destination card) | the cost of a choice is not shown beside it |
| Split output | plain text boxes with an "Auto N" placeholder | old look |
| Supplied by / Consumed by | cards with a flat "Go To" button | old look |
| Space | two thirds of the sheet empty | |

## The DS2 sheets (first pass, built)

Everything is an approved part; nothing new was rendered.

- **Readout** fixed under the title, outside the scroll (the diagnostics' readout, three lines of detail): the option under the pointer, "Steel source: Global market" and what it does; otherwise the sheet's line in the owner's words. Inputs: "Change the Input source for goods." over "The market sells only what you ship in from a port but grants more control, while logistics intermediaries deliver right away but take a bigger slice." Outputs: "Change the Output destination for goods." over "The market pays only if you ship it to a port but grants more control, while logistics intermediaries pay right away but take a bigger slice."
- **The plates**: a plate of the diagnostics' black plastic a good, screwed round its edge, straight on the sheet's steel (owner, 26 September: no case round them).
  - The good in its well, its quantity a turn on its pill (the building's level included).
  - Its name; a lamp and what the tile holds ("60 on the tile. 12 arriving in 2 turns.", the shipments bay's stock rule) for an input, or where it goes for an output ("Sold at market through Stoneshore Docks. 2 turns to the port.", red where it can't get there).
  - Where it comes from, in words ("From this tile's stockpile first. The rest is bought at market through Stoneshore Docks."), tile names only.
  - Under Per turn, Goods and Transport for an input, Value and Transport for an output, on LED screens one width down the sheet, quoted by `BuildingEconomics.per_turn`: the same figures as the Economics section.
  - Your buildings that make or use it, each with a cream Go to key.
  - At the module's right, beside the words (owner, 26 September), the knob (`rotary_selector.gd`, 80 px, the Stock tab's logistics knobs' look): **Source** for an input, and **Fallback** under it in intermediary games (the primary's own option greyed); **Destination** for an output (Intermediary, Global market, Tile stockpile, Ship to another tile). Locked options are greyed and the readout says which research they need.
- **All inputs / All outputs** (intermediary games): a first module with one knob, Each good its own, Intermediary, Global market, Tile stockpile, as the v2 sheet's All row.
- **Split output**: a line a tile, its units a turn typed onto an LED screen's glass (`stock_parts.entry`); 0 shares what is left evenly, the share printed beside it.
- **Power**: one module, the bolt and two lines. No knob, no readout.
- A knob asks for the change and stays where it was; the sheet is rebuilt with the change made, so a refused or cancelled change never leaves a knob pointing at something untrue. Every action is the v2 sheet's own call (`MiddlemanService.set_input_route`, `MatchState.route_output_to_market`, the intermediary confirmation).
- The plates keep the scroll rail's room at its right whether the rail shows or not.
- **Width**: Building Detail v3 is 525 px (`V3_PANEL_WIDTH`; its content had held it at 495, the owner widened it by 30 for these sheets), and the sheets with it. v2 keeps 460.

## Open decisions (owner)

1. **Knob or keys for two options.** An input without the intermediary has two options (tile stockpile only, or market for the rest). The owner's ruling names the knob for three to seven options; the first pass uses it for two as well, for one control throughout. Keep, or use the slide switch (Diagnostics' Visual / Text) for two?
2. **Height.** Decided: the knob stands at the module's right, beside the words; a module is about 240 px, or 280 with Source and Fallback stacked.
3. **Economics duplicated.** Goods and transport a turn repeat the Economics section's lines, per good. Keep here (the cost beside the choice), or show only transport?
4. **Titles.** "Input sources" and "Output destination" stay the plain sheet title. Raise them in Bebas as Building Detail's title, or leave all sheets alike?
5. **Default.** Decided: the default, `toggle routes ds2` switching back to v2.
