# New Game settings in DS2: three metaphors

The New Game panel (`scripts/new_game_panel.gd`) is the last menu surface still in the pre DS2 look: a navy plate with rivets, seven rounded start cards, an Advanced Settings accordion of stacked buttons and tickboxes, a telemetry row and a Start key. Every in game panel now has a place it is set in: Research is a patent office and drawing office archive, Construct a lot with its crane, Politics a courtroom, People a boardroom over the works, Market an exchange, the Briefing a foreman's clipboard. This document proposes three places for the New Game screen, in the format the other plans used, so the owner can choose one for a study render.

The rules it is written to: `docs/ds2-theme.md` §1 (everything is an object, one lamp, white on dark and navy on light, raised headings, numbers on displays, status is a lamp, goods keep their icon tiles) and `docs/ds2-owner-decisions.md` (Everywhere). Nothing is decided here.

## 1. What the screen holds

| Element | Today | What it means |
|---|---|---|
| Start | one row of 7 cards: good on a tier coloured hex, title, badge (Beginner friendly, Intermediate, Challenging) | which company you take over: Metal Magnate, Glass Merchant, Open Field, Troubled Carmaker, Semiconductor Turnaround, Too Many Acquisitions, Ambitious Start |
| Start detail | description line, then Buildings owned, Financials, Company colour, three centred columns | what the company owns, what it is worth and owes, its livery |
| Difficulty | 5 stacked buttons, Very Hard and God of Industry locked until one game is finished; a caption with the chosen one's words | which deposits exist and are finite, how much of the map is surveyed |
| Speed | 4 stacked buttons: 200, 300, 400 turns, Demo; "This also changes the Era pacing." | the match length, its policy timeline and victory set |
| Options | 3 tickboxes, only "All tiles surveyed at game start" wired, two placeholders | rule switches |
| Telemetry | a consent tickbox outside the accordion | send metrics or not |
| Demo lock | every unavailable control greyed, hover "Locked in the Demo" | the demo plays two starts, Normal, 100 turns |
| Start, Back | the Start New Game key, Back | begin, or return to the menu |

The panel sits over the main menu's goods board, to the right of the polished steel menu column, at most 1396 logical px wide and the screen's height less 90 px. Whatever the place is, it must hold seven starts in one row, the detail of one, the three setting groups and the Start key without scrolling at 1080p.

## 2. Concept A: the company registry

The office where a company is born. The player stands at the registrar's counter, picks a company file from the index behind it, reads the file on the blotter, fills in the form of incorporation and stamps it with the company seal.

| Part | Metaphor | What it is on screen |
|---|---|---|
| Frame | the registrar's counter | a walnut counter top with a brass rail along its front edge (the courtroom's turned balusters, shorter) on the house navy steel; the title REGISTRY raised white Bebas on black enamel, the Back key beside it |
| Starts | the card index | seven manila files standing in a brass fronted pigeonhole rack across the top, each with a tab in its tier's colour (green, amber, red) and the good's cream icon tile set in a cut window in the cover; the company name typed on a label; the chosen file pulled forward and lit |
| Start detail | the file open on the blotter | a green leather blotter; the file's two leaves: left the description typed on cream paper, then the asset schedule (Buildings owned as a ruled list, each building's blueprint icon flat on navy as Construct prints them); right the balance sheet, Cash, Loan and Net on LEDs set into a dark strip at the foot of the leaf (money stays on displays, rule 5) |
| Company colour | the paint chip card | a fan of livery chips clipped to the file's corner, the chosen one on top; hover names the colour |
| Difficulty | the registrar's grade stamps | five rubber stamps in a rack, each a wooden handle on a cream key face reading its grade; the chosen stamp's impression on the form in red ink; the words of the grade typed under the impression. Very Hard and God of Industry chained to the rack with a small brass padlock, hover "This difficulty is unlocked once you finish one game" |
| Speed | the term of the charter | a line on the form, "Charter of" then a drum counter of turns (200, 300, 400, 100), stepped by a cream key each side; a strip of era marks under the drum that spreads or tightens with the term, the hover "This also changes the Era pacing." |
| Options | the form's tick boxes | printed boxes on the cream form, a navy tick where set; an option not yet wired prints greyed |
| Telemetry | a line on the form | "Send anonymous metrics" with its printed box |
| Demo lock | a rubber stamp across the control | a red NOT IN THE DEMO impression at an angle on each file, stamp or line the demo does not allow; hover "Locked in the Demo" |
| Start | the company seal | a cast iron embossing press at the counter's right; its lever is the Start key, printed Start New Game on a cream face; pressing it drops the die on the form and the game begins |

Also considered for this place: wax and ribbon for the seal (slow to read as a control), a bell on the counter for Start (the exchange already has a bell).

**What it needs new.** Renders: the counter and rail, the pigeonhole rack and a manila file in three states, the blotter and its two leaves, a stamp and its impression, the paint chips, the embossing press with its lever down and up. The form's print, tick boxes and era strip are drawn live. Drum counter, LED, small key, padlock and lamp come from the kit. The courtroom's leather and brass stud 9 slice can carry the blotter.

**Where it is strong.** Every setting is a line on one document, so the player reads the whole game they are about to start in one place, and the Start key is a physical act on that document. The locked and demo states have a natural form (chain, stamp). Money, buildings and livery each get their own object.

**Where it is weak.** Difficulty's meaning (deposits, survey) is only told in words under the stamp. A warm wood and paper place beside the polished steel menu column is a tonal jump; the brass rail and the black enamel nameplate tie it back.

## 3. Concept B: the survey office

Where you decide what ground you will play on. The player stands at a map table under the lamp, chooses a start by its pin on the continent, reads the company's papers at the table's edge and sets the match on the surveyor's instruments. Difficulty is shown on the map itself.

| Part | Metaphor | What it is on screen |
|---|---|---|
| Frame | the map table | a dark timber table edge with a brass rule screwed along it, on the house navy steel; SURVEY OFFICE raised white Bebas on black enamel, the Back key |
| Map | the continent sheet pinned to the table | the continent as printed relief (the existing relief shot, `tools/relief_shot.tscn`, as one texture), its corners under brass map weights; it fills the table's left two thirds |
| Starts | the survey pins | a brass headed pin at each start's town (Greyroad for Metal Magnate, Ashmouth for Glass Merchant, and so on), a tag on a string with the good's cream icon tile and the company name; the tag's edge in its tier colour. Open Field is a pin lying loose on the table's margin with its tag, since it has no ground yet. The chosen pin's tag lies flat and lit, the others hang |
| Start detail | the company's papers at the table's edge | a clipboard at the right: description, Buildings owned as a ruled list with blueprint icons, Cash, Loan and Net on LEDs in a dark strip, the livery as a flag swatch on the pin's string and a chip row on the clipboard |
| Difficulty | how much of the sheet is surveyed | a five position rotary selector (the People panel's white knob) on the instrument plate, Easy to God of Industry. The map answers it: Easy prints the whole sheet with every deposit's mineral mark; Normal prints the whole sheet with some marks hollow (finite); Hard greys the unsurveyed tiles to blank paper and removes the rare earth marks but one; Very Hard and God of Industry leave only the start's tiles printed and strike the deposits they remove. The chosen difficulty's words print under the knob. The two locked positions have a brass blanking plate screwed over them with the padlock, hover "This difficulty is unlocked once you finish one game" |
| Speed | the almanac | a drum counter of turns on the instrument plate, stepped by two cream keys, and a brass era rule beside it whose era marks slide with the term; "This also changes the Era pacing." on hover |
| Options | the instrument case switches | slide switches in a slot each on the plastic instrument case, a pilot lamp by each; unwired options greyed |
| Telemetry | one more switch | "Send anonymous metrics", a slide switch |
| Demo lock | a paper band | a red printed band "NOT IN THE DEMO" round each pin's tag, over the knob's positions and the drum's steps the demo does not allow; hover "Locked in the Demo" |
| Start | break ground | a wide cream key on the instrument plate under a clear guard cover, printed Start New Game: the first click lifts the cover, the second starts (the kit's guarded button). Starting a match is the one choice on this screen you cannot take back, so it earns the guard, where Build did not |

Also considered for this place: the starts as flags rather than pins (flags hide the tile), a theodolite as the Start control (a lovely object, but a telescope is not a key).

**What it needs new.** Renders: the table edge and brass rule, the map weights, a pin and its tag in three states, the clipboard (the briefing's hardboard and clip can carry it), the instrument plate and case, the blanking plate. The map is the existing relief as a texture with a live mask for the unsurveyed area and live deposit marks (the mineral glyphs already exist in `assets/icons/ui_icons/terrain/`). Knob, slide switch, drum, LED, guarded key and lamp come from the kit.

**Where it is strong.** This is the only concept where difficulty shows what it does: the player turns the knob and watches the map go blank and the deposits vanish. Starts are placed where they are on the continent, which the start cards never said. Era pacing is a rule with marks that move, not a sentence.

**Where it is weak.** Open Field, Too Many Acquisitions and any start with holdings in several towns need a convention (a loose pin, a pin per site, or the pin at the first site). The map eats most of the width, so the start detail is a column, not three. A difficulty that only changes the map on a loaded game needs the survey and deposit rules to be readable from the panel without a match (the deposit set per difficulty is in the sim's config, not yet in the panel). Most expensive of the three.

## 4. Concept C: the commissioning desk

The control desk a plant is started from. The player sits at the desk, chooses a plant on the mimic board, sets the selectors and turns the key. No paper, all kit: the machine answer, the way the top bar and tile view are.

| Part | Metaphor | What it is on screen |
|---|---|---|
| Frame | a control desk | a grey painted steel desk with a sloped instrument face and a flat shelf, the house navy steel behind; NEW GAME raised white Bebas on the desk's black enamel nameplate, the Back key |
| Starts | the plant selector | seven illuminated push buttons in a row across the top of the face, each a cream lens with the good's icon printed on it and the company name engraved on a plate under it; a pilot lamp by each in its tier colour (green, amber, red); the chosen button lit and latched down |
| Start detail | the mimic board | a dark gunmetal board above the buttons: the company's buildings as raised relief icons joined by engraved lines (Buildings owned), with a lamp each; Cash, Loan and Net as three LED screens in one group with their printed £, Net green or red; the livery as a coloured lens over a lamp at the board's corner, the colour chosen on a small rotary of lenses |
| Description | the readout | the kit's dark glass readout under the mimic, the start's description in two white lines |
| Difficulty | a five position rotary selector | the knob on the face, Easy to God of Industry engraved round it; the chosen position's words on a second readout; positions 4 and 5 under a steel blanking plate with the padlock, hover "This difficulty is unlocked once you finish one game" |
| Speed | the run length selector | a four position selector, 200, 300, 400, Demo, and a drum counter of turns beside it; an era strip of LED cells under the drum, the era boundaries lit, that spread with the term; hover "This also changes the Era pacing." |
| Options | toggles with lamps | a toggle switch per option on the face, a pilot lamp above each, lit when on; unwired options' switches blanked |
| Telemetry | one toggle | "Send anonymous metrics" |
| Demo lock | blanking plates | a screwed steel plate over each push button, selector position and switch the demo does not allow, hover "Locked in the Demo" |
| Start | the key switch | a brass key in a switch at the desk's right, printed START; the first click turns the key to the lit position (the cover's lift), the second presses the green mushroom head beside it and the game begins. The kit's guarded button carries both steps if the key switch is too much to render |

Also considered for this place: a locomotive's regulator for Start (too big for a key), a telephone to the works (no).

**What it needs new.** Renders: the desk face and shelf, the push button in three states, the mimic board's engraved lines, the lens rotary, the blanking plate, the key switch. Knob, toggle, drum, LED, readout, lamp, raised relief icon and guarded button come from the kit as they are. Least new work of the three.

**Where it is strong.** The most DS2 of the three: it is the tile view's cabinet and the top bar's steel at a desk, so the menu and the game read as one machine. Every control has a kit part. The mimic board shows what you own as the game will show it. Locked and demo states are plates screwed on, the same object everywhere.

**Where it is weak.** No paper, so the start's story (a troubled carmaker, a grab bag bought on debt) is two lines on a readout, the thinnest telling of the three. A mimic board of two or three buildings looks thin for Metal Magnate and Glass Merchant; Open Field has none and shows the bare board.

## 5. Across the three

- **Copy.** Every proposed string is plain and brief, no hyphens, semicolons, dashes or middle dots. The tier badge "Beginner-friendly" becomes "Beginner friendly" in all three. "Demo - Itch.io" becomes "Demo" on the control and "100 turns, the Itch.io demo" in its hover.
- **Ink.** White with a dark shadow on steel, gunmetal, walnut, leather and plastic; navy on cream paper, manila, keycaps and lenses. Nothing under 12 logical px.
- **Figures.** Cash, Loan and Net come from the start config through the same helper the loading pipeline applies (`save_load.gd expand_start_config`), quoted, not retyped in the manifest.
- **The lamp.** One lamp overlay from the top left on the whole panel, part by part, as every DS2 panel.
- **Width.** 1396 logical px holds seven starts in one row in all three (A at 160 each with the rack's walls, B as pins, C at 150 with their plates). Below 1100 px, A and C drop the detail to two columns; B drops the clipboard under the map.
- **Behind a switch.** `UiPrefs.use_new_game_ds2` and `toggle newgame ds2`, the current panel unchanged with it off, the first step a shell only, as every migration.

## 6. Recommendation

Concept A, the company registry, for a study first. It tells the start's story best, which is what a new player reads this screen for, and it gives the Start key a physical act on the document the player has just filled in. Concept B's survey map is the one idea worth carrying across whatever is chosen: if A is taken, the difficulty stamp's impression could sit beside a small survey sheet that goes blank as the grade rises. Concept C is the fallback if render budget is short.

## 7. The study: the company registry

Study: `artifacts/new_game_ds2/registry_study_v1.png`, rendered by the `registrystudy` set in `tools/button_mockup/cluster.html` (seed 488, a study only, no game layer). One sheet at the panel's width (1396 logical px, 2617 layout) with the Troubled Carmaker chosen, every figure the start config's (£200 cash, £500 debt, four buildings on their tiles) and every string one the panel would print.

What it shows, part by part: the REGISTRY nameplate and Back key on the navy steel header; the card index as an oak rack of seven felt lined pigeonholes, a manila file in each with its tier tab, the good's tile in a cut window and the typed label, the chosen file lifted and pulled over the lip; the walnut counter with a brass rail along its front; the file open on a green leather blotter, the story and the asset schedule (building icons printed navy) on the left leaf, the figures on a gunmetal strip of three LEDs and the livery as a fan of paint chips on a brass stud on the right; the form of incorporation on cream plastic with the grade's red stamp impression, the charter's term on a drum between two small keys over a printed era rule, the tick boxes and the dashed circle where the seal lands; the five grade stamps as cream keys in a dark steel rack (Normal latched, Very Hard and God of Industry padlocked) over the red ink pad; and the company seal, a cast iron press with a brass die, its chrome lever ending in the Start New Game key.

Choices made in the study that the owner may want to change:

- The file's second line is the tier in words (Beginner friendly, Intermediate, Challenging), not a badge.
- One assembly plant sits on an unnamed tile; the study prints "Near Capital Port". The panel will need a name for every start tile or a rule for unnamed ones.
- Net is cash less debt, red below zero. The old panel printed an estimated profit per turn instead; the start configs do not all carry one.
- The era rule marks three eras at 0, 100 and 200 turns for the study only; the real boundaries come from the policy timeline.
- Start New Game is a plain cream key on the lever, not a guarded one.

**Round two** (`artifacts/new_game_ds2/registry_study_v2.png`), the owner's corrections on the first study, each applied:

- *The whole thing a desk, dark wood with a leather section.* The navy steel backing, the walnut counter and its brass rail are gone: one dark walnut desk top edge to edge, the green leather blotter its one soft section, the oak rack, the form, the stamp rack and the press standing on the wood.
- *The title section a metal panel on wood.* A navy steel panel screwed to the desk across the top, the REGISTRY nameplate and the Back key on it.
- *Buildings larger, names and places on hover only, a strip of the building and the good it produces.* Buildings owned is a strip of four cells: the building printed navy at 104 layout px, a short link line, the good it makes on its cream tile under it, no words. The pointed at cell has a dashed outline and a white plastic slip under the strip with the name and the place. The good is the recipe's first output (ice car, engine, tyres).

**Round three** (`artifacts/new_game_ds2/registry_study_v3.png`, three states on one sheet), the owner's corrections on round two:

- *The colour swatch without precise hovering or selecting.* The fan is gone. The livery is a paint card printed on the right leaf: eight squares of 96 layout px (51 logical) in two rows of four, the chosen one framed in navy with a tick in its corner, its name printed under the card. A square is a target the size of a key.
- *The money as text on the page, like a ledger.* The gunmetal strip and its LEDs are gone. Financials are ruled ledger lines in ink: the label at the left, the figure at the right in whole pounds as the panel prints them, a double rule under the last line. A figure below zero is in the light surface red ink, a profit in the green. Troubled Carmaker reads Cash £200, Debt £500, Net £300 owing; Metal Magnate reads Cash £300, Debt none, Profit each turn £16. This is the one place a DS2 surface shows money off a display, on the owner's word.
- *A demo state.* Two variants, both with Metal Magnate open (a demo start) and Start New Game in place:
  - **Lockboxes** (state 2): a dark steel lid with hinges, a brass hasp, a padlock and a brass plate reading FULL GAME over the five pigeonholes the demo keeps shut, and a second lid over the grade stamps and the ink pad. The form is emptier: the company, the grade stamped NORMAL and the charter printed "100 turns, the Itch.io demo." with a DEMO stamp, nothing to set, the seal circle kept.
  - **The wider book** (state 3): no form and no stamps. The blotter and the book take the desk up to the press column, the leaves half as wide again, and the charter is printed in the file under the paint card with the DEMO stamp. The lid over the five starts stays.
  - *Decided: the lockboxes, 19 October 2026.*
  - Not studied: a lid over the whole form (it would hide the company's name and the charter, which the demo player still needs to read).

Export: `python3 tools/button_mockup/export.py 8790`, then headless Chrome at `cluster.html?export&only=registrystudy` (a fresh `--user-data-dir` each time, since Chrome caches the page); move `assets/ui/bdp_v3/registry_study.png` into `artifacts/new_game_ds2/` and revert `layout.json`, which the export only re-escapes.

## 8. Open decisions

1. Which metaphor goes to a study render. *Decided: the company registry, studied (§7), 19 October 2026.*
2. Whether Start earns the guarded cover (B and C guard it, A does not).
3. Whether difficulty should show its effect on a map (B, or a small sheet in A).
4. Where a start with no ground or several sites sits (B only).
5. Which demo variant goes forward. *Decided: the lockboxes (state 2 of round three), 19 October 2026. The wider book is set aside.*

## 9. What was built (20 October 2026) and what is left

Built on the branch `new-game-ds2`, behind `UiPrefs.use_new_game_ds2` (off by default) and the cheat `toggle newgame ds2`. With the flag off the old panel is built and stands exactly as before (`tests/unit/test_new_game_ds2.gd` checks it, and that the flag swaps the panel live in the main menu both ways).

**The game layers** (`tools/button_mockup/cluster.html`, seeds 489 to 498, inside the `registrystudy` block so they share the study's materials; the study itself is unchanged): the walnut desk (a 9-slice at the panel's size), the navy header (a 9-slice), the felt and the oak pigeonhole frame (the frame drawn over the files, with the shadow it throws in), a blank manila file per tier in its hole and pulled out, the lockbox lid with its hinge, hasp, padlock and blank brass plate as separate parts, the blotter, the open cover and a cream leaf (9-slices the game prints on), the stamp rack and the ink pad, the press without its key, the hover slip, and a small key with a chevron right (`key_forward`). The kit supplied the rest: the silver screws, the tile view's nameplate, the Back key, the cream keys, the drum counter and `sheet_white` for the form. Export: `python3 tools/button_mockup/export.py <private port>`, then headless Chrome at `cluster.html?export&only=registrydesk,registryhead,registryrack,registryfile,registrylid,registryblotter,registrystamps,registrypress,registryslip,registrykeys` with a fresh `--user-data-dir`; then `godot --headless --path . --import`. The layout entries are listed in `docs/ds2-theme.md` §3.2.

**The shell** (`scripts/new_game_ds2/new_game_ds2.gd`, extending `scripts/new_game_panel.gd`): everything the old panel decides is inherited, the signals, the starts and their configs, the demo lock (`DEMO_LOCK`, `DEMO_START_IDS`, `DEMO_DIFFICULTY_ID`, `DEMO_SPEED_ID`), the difficulty lock on `PlayerProfile.has_completed_game`, the livery table and the telemetry consent. The script lays the desk in regions and prints on them:

- the header with the REGISTRY nameplate, the silver screws and the Back key;
- the rack of seven files, each a toggle in a group as the old cards were, the chosen one pulled out over the lip with a warm rim; in a demo build the lockbox over the pigeonholes the demo keeps shut;
- the file on the blotter: the story, the buildings as a strip (the building printed navy, the good it makes on its cream tile under it; pointing at one shows the white slip with its name and place), the ledger (Cash, Debt, then Net while there is debt, else Profit each turn; whole pounds; red ink below zero, green for a profit) and the paint card of the eight liveries, the chosen one framed and ticked, its name under the card;
- the form on `sheet_white`: the company, the grade's red impression and its words, the charter on a drum between two small keys (`key_back`, `key_forward`, stepping through the old panel's lengths, the demo length included, with its timeline), the era rule, the survey tick (and the metrics tick only while `TelemetryState.SHOW_CONSENT_CHECKBOX` is on), the seal circle; in a demo build the fixed charter line and the DEMO stamp;
- the stamp rack of five cream keys, the chosen grade latched, a padlock on each locked grade; in a demo build the lockbox over the rack and the pad;
- the press with the Start New Game key on its lever.

The lamp overlay (`scripts/ds2/lamp_overlay.gd`) is on the whole panel, part by part.

**The era rule** (the owner, 20 October 2026, replacing the policy beats the first build printed): a bar cut into the three eras with their names and nothing else on it. A 300 turn charter is 90 turns of Era 1, 90 of Era 2 and 110 of Era 3; a 200 or 400 turn charter keeps those shares (`era_spans`). In the demo the bar spans the campaign's 300 turns, the demo's hundred printed Demo Era and the rest greyed out, under the demo's charter line.

**Unnamed start tiles** print the nearest named tile with Near in front, as the study did (`place_for`): the Troubled Carmaker's plant on `tile_23_6` prints "Near Long Valley Fields" (the study guessed "Near Capital Port"; the nearest named tile by the grid is the fields one step north). The rule is grid distance over the tile ids, not road distance; a start tile with its own name prints it.

**Captures**: `tools/new_game_ds2_shot.tscn` (windowed, `-- --no-telemetry`, a SubViewport at two pixels a logical pixel) wrote `artifacts/new_game_ds2/ds2_v1/` (the first build; `ds2_v2/` after the corrections below): `01_full_default` (the full game, the recommended start), `02_full_carmaker` (the Troubled Carmaker open, a building pointed at, Hard stamped, a 200 turn charter), `03_demo_lockboxes` (the demo).

**Tests**: `tests/unit/test_new_game_ds2.gd` (tag `new_game`): the flag off keeps the old panel and swaps live; seven files, the recommended one open, the ledger's lines and inks, the building rows, the hover slip, the paint card; the grade stamps and their locks, the charter's keys; `start_requested` with the same overrides as the old panel, `back_requested`; the demo's locks, lid, fixed charter and standing Start key; the era marks; the Near rule.

**The owner's corrections on the first captures** (20 October 2026), each built:

- *Remove the line under the company colour.* The sentence "Every building this company owns is painted in it." is gone; the heading, the paint card, the chosen name and "Press a square to repaint." stay.
- *Hide the sentence about what is surveyed.* The grade's words print only their deposits part (`grade_words`): the sentence about the survey ("Some tiles are surveyed." and its siblings) is left out while the All tiles surveyed option is on, which it always is today and in the demo every tile is surveyed. The old panel's strings are untouched.
- *An animation when Start New Game is pressed.* The die is now its own layer (`registry_die`, the press rendered without it, seed 496 re-exported). On the press the key latches with its lamp, inputs are held off and Esc is ignored, and over 2.5 s the die lifts off the press (a little larger, nearer the lamp), slides to the seal circle, comes down on it, holds, rises, slides back and settles on the press; from the moment it comes down the circle carries the seal's impression, embossed into the cream (two rings, THE REGISTRY OF COMPANIES and CARBON AND CAPITAL round it, SEALED across). Then `start_requested` goes out as before and the main menu, on its DS2 path only, fades the screen to black over 2.0 s before the loading screen and the existing `prepare_new_game` pipeline run (`main_menu.gd` `_on_start_requested`, `NEW_GAME_FADE_SECONDS`). Headless runs and tests skip the sequence (the signal goes at once), and `animate` can be switched off. The sequence is a pure function of time (`die_centre_at`, `DIE_SCALE_AT`, `_set_stamp_time`), which is how the shot tool captures its moments and the tests check it. Captures: `artifacts/new_game_ds2/ds2_v2/` (the three states, then `04_stamp_over`, `05_stamp_down`, `06_stamp_after`).

**Left for later** (none of it blocks the review):

1. The study's choices the owner may still change (§7): the tier in words on the file, Net as cash less debt, Start New Game unguarded.
2. The old panel's two placeholder options (Setting 2, Setting 3) are not printed on the form; they said nothing. The survey tick prints ticked and is not a control, as the old panel's was disabled.
3. The grade words are the old panel's strings and carry its hyphens ("rare-earth"); changing them changes the old panel too, so they are left for the copy pass.
4. The chosen stamp key latches as the cabinet's keys do (sunk, a shade darker); the study sank it further. A sunk cream key render would need a kit change.
5. The pigeonhole frames are drawn one per opening, overlapping on the shared bars, so a faint seam shows down each bar; a rack rendered as one frame would need a render per start count.
6. Below 1080p the panel keeps the study's layout and the blotter shrinks to a floor of 420 px; the two column fall back of §5 is not built.
7. A standard capture set once the owner approves (`docs/ds2-theme.md` §9).
8. Open Field's story says £1,500 while its config starts it with £1,900, so the ledger (which quotes the config) and the story disagree; the old panel showed the same. A data or copy fix, not the panel's.
