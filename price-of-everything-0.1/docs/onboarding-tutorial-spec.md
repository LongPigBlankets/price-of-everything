# Onboarding tutorial in the first game

Status: design locked by the owner on 3 Oct 2026, not built.
Research behind it: `../../reports/Strategy game tutorial onboarding.md` (outside the repo).

## Why

Telemetry: nobody left the old tutorial between steps 2 and 11, players dropped in the transport
section, and only 25–35% of tutorial finishers started a real game. Games since 2020 mostly teach
inside the first real game. So the tutorial moves into a Metal Magnate game: a short scripted
opener, then missions in the top bar mission system that the player follows at their own pace.

## Shape

1. **Opener (scripted, coach overlay).** Visual steps rescued from the old tutorial, bound to
   Metal Magnate's buildings instead of the old tutorial map: welcome, UI primer, recipes (inputs and
   outputs).
2. **Select your tile and open your buildings.** Greyroad (tile_9_9): the iron furnace and the coal
   power plant.
3. **End a turn.** Then a short explanation of the Logistics Intermediary as "local suppliers": they
   buy your inputs and sell your output for a fee.
4. **Full control.** The coach overlay ends. Victory and Rankings are hidden in the top bar. The
   missions below run in the top bar mission system.

Missions are not dismissable. The player can ignore them; nothing blocks play. Victory points and
ranking changes keep accumulating while their sections are hidden.

## Missions (Metal Magnate)

| # | Mission | Done when | Reward |
|---|---|---|---|
| a | Build a steel furnace | A player furnace running Steelmaking (r_003) completes construction | +10% coal and iron ore output, permanent |
| b | Unlock stockpiling | Open Logistics Contracts is unlocked (earned or via a free unlock) | |
| c | Supply your iron furnace yourself | The iron furnace (r_005) takes iron ore and coal from your own mines through a tile stockpile, and completes a cycle | |
| d | Supply your steel furnace yourself | The steel furnace takes iron ingots and coal from your own stockpile, and completes a cycle | −10% road and rail transport cost for 20 turns (infrastructure only, not the intermediary) |
| e1 | Unlock the global market | Government Import/Export License unlocked and its decision accepted | |
| e2 | Sell steel on the global market | Steel output routed to the global market and a sale completes | |
| f | Reach the port a turn sooner | Steel's route from Greyroad to its port takes at least one turn less than when e2 completed | Loan interest 15% → 13% for 20 turns (loans taken in that window) |
| g | Mine an infinite coal deposit | A player mine on an infinite coal deposit completes. Victory and Rankings appear in the top bar | |
| h | Ship your coal to where it is used | Coal from that mine is delivered to a tile with player buildings that consume coal | +5% output on every recipe, permanent |
| i | Build three more buildings that use your goods | Three more completed buildings whose recipes consume a good you produce | |
| j | Upgrade a building | One building level upgrade completes (not infrastructure, which is one way to solve f) | |
| k | Make 20 finished goods | 20 units of a finished or apex good (goods_graph_tier) produced | +1% sale price for 20 turns |

The tutorial ends when k completes.

### Step a: two ways to pay

The furnace costs about £430 (£20 plus about £411 of materials) and Greyroad has 14 free land of the
18 a furnace needs. Metal Magnate starts with £300 and makes about £16 a turn. Mission a offers two
routes, both shown:

- **End turns** until you have enough money (the mission shows cash against the furnace's cost).
- **Take a loan** (opens the money panel's loan dialog).

Either route also needs land: the mission says to buy 4 land on Greyroad.

### Notes per step

- **b:** the turn 1 free unlock can take Open Logistics Contracts (tier I). Earned naturally it takes
  about 5–8 turns: 300 units each of 3 goods through the intermediary.
- **c:** the mines are on other tiles (coal tile_6_8, iron tile_7_10), so this teaches shipping to a
  tile.
- **e1:** £75 pre-tax profit for 3 turns in a row, then the £150 decision. Metal Magnate makes about
  £16 a turn before the steel furnace; whether c and d lift it to £75 needs a soak (see open questions).
- **f:** intermediary sales have no transport turns, so f only means something after e2. Infrastructure
  Tendering (3 distinct goods) is unlocked from the start. Roads or rail are the expected fix.
- **g:** the start coal deposit holds 2,000 and runs out in about 33 turns. The nearest infinite coal is
  tile_10_8, a mountain next to Greyroad, within survey range.
- **k:** steel is intermediate. The nearest finished good is car bodies (Car Body Manufacturing,
  r_068: 21 steel + 7 aluminium + 3 plastics → 15 car bodies) in a factory.

## Setup and removal

- New Game: a Tutorial checkbox, on until the profile has finished the tutorial once, then off.
  The tutorial runs only on Metal Magnate.
- Remove the main menu Tutorial button, the "proceed without the Tutorial?" prompt and the separate
  tutorial start (`data/starts/tutorial.json`).
- Remove the old tutorial content: the 38-step script, its detectors and its tutorial-only panels.
  Keep the coach overlay's welcome and annotate modes for the opener.
- In a tutorial game the tutorial tree replaces the Logistics and Metal Magnate mission trees,
  which it covers. Without the tutorial those trees stay as they are.
- Pepper Valley Motors is no longer a playable start (removed on branch remove-pepper-valley-start);
  its benchmark starts stay as internal testbeds.

## Telemetry

Log each opener step, each mission completion with its turn, and when a player turns the tutorial
off at setup. Compare cohorts on real-game survival at fixed turns (tutorial on, tutorial off), not
on mission completion.

## The mission in the top bar

The missions run in the DS2 top bar's mission slot (scripts/ds2/mission_slot.gd, branch mission-slot-ds2):
a cream key holding the mission's title, and beside it a painted steel track where a brass piston head
shows the count (x/y) when the mission asks for more than one of something. On completion the piston
strokes to the end of its track with steam venting from its gland, the key changes to the next mission,
and the piston snaps back. Each tutorial mission therefore needs a title short enough for the key and,
where it counts, a `MiniQuest.progress(kind)` figure.

## Decisions (3 Oct 2026)

- f's reward is two percentage points: 15% to 13%. The `loan_interest` modifier is relative, so it is
  −13.33%. Loans bake their rate when taken, so it lowers loans taken during the 20 turns.
- Rewards without a duration (a, h) are permanent.
- Glass Merchant: no tutorial for now; to be revisited.

## Open questions

1. **e1 reachability:** soak Metal Magnate with a steel furnace and c/d in place to confirm £75 a
   turn is reachable, and how many turns a to k takes.
