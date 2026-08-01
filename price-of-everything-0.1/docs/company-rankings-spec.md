# Company Rankings — spec

**Status:** proposed, not built. **Owner brief:** 2026-08-01.
**One line:** a league table of invented rival companies in the top bar, so the player can see
where they place — cosmetic only, with **no effect on the simulation**.

---

## 1. Intent

The game has NPC-owned buildings but no sense of *rivals*. A player 300 turns in knows their own
revenue and nothing about whether it is good. The rankings give that number a context: a standings
table the player climbs, without adding an opponent AI or any new economic pressure.

**The companies are scenery.** They own nothing, buy nothing, and never touch a price. If removing
this feature would change a single number in a turn resolution, the implementation is wrong.

---

## 2. The cycle (owner ruling, 2026-08-01)

Each company runs a repeating cycle of **growth → stagnation → decay**, always **5 growth turns,
2 decay turns and 2 flat turns** in a 9-turn period. The ORDER of those turns within the period is
randomised per company, so the field does not move in lockstep, but the counts never vary.

Magnitudes are randomised per turn, not fixed per company:

| phase | per-turn change |
|---|---|
| growth (5 turns) | normal draw centred on `+15%`, σ `5%`, clamped to `+1%` .. `+25%` |
| decay (2 turns) | `-1%` .. `-5%`, drawn uniformly per turn |
| flat (2 turns) | 0 |

Expected drift per 9-turn period is roughly **+90%** (five ~15% growth draws against two ~3%
decay draws), so the whole field expands rapidly while individual standings churn — which is the
intent.

This supersedes the earlier open question about whether the split was temporal or a population
split. It is temporal, and it applies to every company.

---

## 3. Architecture constraints

Non-negotiable, from `CLAUDE.md`:

| Rule | What it means here |
|---|---|
| #1 sim outside the tree | `CompanyRankings` is an autoload service. No node per company. |
| #2 turn logic in advance functions | Recompute on the **AI phase** only — never in `_process`. |
| #3 determinism | Seeded RNG only. **Never** global `randi()`/`randf()`. |
| #4 versioned saves | See §5 — presentation state is versioned and migrated. |
| #5 UI read-only | The top bar reads `CompanyRankings`; it never writes. |
| #6 typed GDScript | Typed throughout. |

The AI phase is currently a defined-but-empty placeholder in the `_RESOLUTION_PHASES` loop
(`turn_manager.gd:18`). Phases do their work through `phase_started` listeners, so
`CompanyRankings` connects to that signal and acts when `phase == Phase.AI`. This is the first
real occupant of that phase — do not reorder the phases to accommodate it.

---

## 4. The model

### 4.1 Roster

Nine companies. Names come from the existing `_COMPANIES` list in `building_readout.gd:20`
(16 cosmetic operator names, already stable-per-owner and RNG-free). Pick the first nine by a
seeded shuffle at match start so different matches get different line-ups.

> **Move the list.** It currently lives in `building_readout.gd`, which is about *reading out a
> building*. Two consumers now need it. Lift it to its own small const script and have both
> reference it — do not duplicate the array.

### 4.2 State per company

```
name           String       from the shuffled roster
revenue        float        starts at 100.0/turn
cycle          Array[int]   9 entries, a shuffled permutation of 5 x GROW, 2 x DECAY, 2 x FLAT
```

`cycle` is generated once per company at match start by shuffling the fixed multiset, so every
company has the same *counts* and a different *order*. There is no per-company growth rate any
more — magnitude is drawn per turn (§4.3).

### 4.3 Per-turn update

For company `i` at turn `t`, the phase is `cycle_i[t % 9]`:

| phase | applied |
|---|---|
| GROW | `revenue *= 1 + clamp(randfn(0.15, 0.05), 0.01, 0.25)` |
| DECAY | `revenue *= 1 - rand(0.01, 0.05)` |
| FLAT | unchanged |

Both draws come from the isolated stream in §5 — never `_match_rng`.

Because the magnitude is redrawn every turn, the earlier "shrink at half the growth rate" fudge is
gone: the asymmetry now comes from the 5:2 turn split and the fact that the decay range is
narrower than the growth range.

### 4.4 The player's row

The player's revenue is the **real** figure the top bar already shows (`money_in` from the last
turn summary), inserted into the same sorted list. Never smooth or scale it — the point is that
the player's actual trajectory is what is being ranked.

Two consequences to handle explicitly:
- **Turn 1** the player has no revenue and sits last. Correct, and worth showing.
- **Late game** the rivals now compound very quickly from 100. Whether the player can keep pace
  needs a fresh 300-turn run; tune rival starting revenue, not the player's real revenue.

---

## 5. Persistence — presentation-only state

Rival revenue and output are pure functions of their seeds, so they are recomputed from scratch on
load. The save does serialize the player's five-turn revenue history and last resolved good
quantities, solely to preserve the trend, rank movement, and player rows in the panel. This data is
never read by turn resolution. The save schema is versioned and migrated accordingly.

That holds **only if** the per-turn jitter draws from a stream seeded by `(match_seed, i, t)` and
not from the shared `_match_rng`. Drawing from the shared stream would make the rankings consume
RNG that the rest of the sim depends on, and the sequence would then differ between a fresh run
and a loaded one — breaking determinism (rule #3) and, worse, breaking it *elsewhere* in the sim.

**Therefore:** use a dedicated `RandomNumberGenerator` re-seeded per draw, never `_match_rng`.

---

## 6. UI

### 6.1 Top-bar module

A compact module in the modular bar, matching the existing module treatment (`_module_box`,
`MOD_H`) — see `top_bar.gd`. Shows the player's current position: `▲ 4th of 10`, with the arrow
indicating movement since last turn (▲ risen / ▼ fallen / — held). Click opens the panel.

Follow the top-bar flicker rule established in PR #99: refresh by `remove_child()`-then-free, never
bare `queue_free()`, which is deferred and lays out both sets of children for a frame.

### 6.2 Expanded panel

Standard `DS` theme, `Card` variation — do not invent panel styling. Ten rows, sorted by revenue
descending, the player's row emphasised:

| col | content |
|---|---|
| rank | 1–10, with the movement arrow |
| company | name (player's own company name for their row) |
| revenue | £/turn, `Numeric` variation |
| trend | last-5-turn direction |

Keep a 5-turn revenue history per company purely for the trend column — in memory only, rebuilt on
load like everything else.

### 6.3 Goods tab

A second **Goods** tab shows every catalogued good with its framed good icon and a compact producer
table. Ordinary goods list the top three rival producers plus **Your Company**, sorted by quantity;
each quantity is displayed in brackets. Apex goods list **Your Company** only — rivals never produce
them in this cosmetic view.

For a rival and good, start output at `Catalog.base_output_for_good(good_id)`. Every five completed
turns, add one seeded integer increment chosen from `0`, `base × 0.2`, `base × 0.5`, or `base`. The
player row uses the real quantity from the most recently resolved production summary. Rival quantities
are derived from the match seed, good, competitor, and five-turn batch; player last-turn quantities
are presentation-only save data so loading preserves the view.

---

## 7. Open questions

1. **Rival starting revenue.** With the 15% growth mean, 100/turn compounds aggressively.
   Decide after a real 300-turn run whether the start needs lowering or the current power curve is
   intended.
2. **Does the player's company have a name?** The rankings need one for the player's row. If none
   exists, a New Game field is the natural home, defaulting to something neutral.
3. **Do rivals react to the carbon clock?** Cheap and thematic — a rival's decay turns could bite
   harder after t60 as the squeeze lands. Deferred; not in v1.

---

## 8. Test plan

Unit (`tests/test_runner.gd`), all non-destructive — **no `MatchState.reset()`**, which wipes the
NPC-port state later tests assert against:

- **Determinism.** Same seed + same turn ⇒ identical table. Compute t50 twice, assert equality.
- **Reconstruction.** Advance to t50, rebuild rival rows from seed alone, and assert the table
  matches — this is what keeps rival presentation deterministic.
- **RNG isolation.** Draw the full table for 50 turns, assert `_match_rng`'s state is unchanged.
  This is the test that catches the determinism break described in §5.
- **Cycle shape.** Over any 9 consecutive turns a company grows on exactly 5, decays on exactly 2
  and holds on exactly 2 — the counts are invariant even though the order is shuffled.
- **Magnitude bounds.** Over 500 sampled growth turns every draw lands in [1%, 25%] and the sample
  mean remains near 15%; over 500 decay turns every draw lands in [1%, 5%].
- **No sim effect.** Run 20 turns with rankings enabled and disabled; assert the player's money,
  every market price, and every stockpile are bit-identical. **The most important test here.**
- **Player placement.** Zero revenue ⇒ last; revenue above every rival ⇒ first.

UI: render the top bar and expanded panel windowed via a `*_shot.tscn` tool and inspect the PNG —
the project's standard for UI verification.

---

## 9. Estimate

Roughly a day: half for the model plus tests, half for the two UI pieces. The riskiest part is not
the maths — it is §5, keeping the RNG isolated from the shared match stream. Get that wrong and it
manifests as a save/load determinism bug somewhere else entirely, which is expensive to trace back
to a cosmetic league table.
