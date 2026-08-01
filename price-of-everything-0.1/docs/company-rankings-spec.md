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

## 2. The one decision needed before building

The brief reads: *"production growth/decay 5 turns grow, 2 decrease, 2 fixed at 5%/2%/1%"*.
That parses two ways and they produce visibly different tables.

**(A) Temporal cycle — recommended.** Each company runs a repeating 9-turn cycle: **5 turns
growing, 2 shrinking, 2 flat**, with its growth magnitude fixed per company at one of 5%/2%/1%.
Each company gets a phase offset so they do not all peak together. Standings churn continuously
and every company drifts upward over a long game — matching an industry that is broadly expanding
with cyclical setbacks.

**(B) Population split.** Nine companies: 5 permanently growing, 2 permanently shrinking, 2 flat,
at 5%/2%/1%. Standings are near-static after ~30 turns: the growers run away, the shrinkers sink,
and the table stops being interesting.

**Recommendation: (A).** It is the reading the word "turns" supports, and (B) converges to a fixed
order early, which defeats the point of a league table. **Everything below assumes (A)**; switching
to (B) touches only §4.

---

## 3. Architecture constraints

Non-negotiable, from `CLAUDE.md`:

| Rule | What it means here |
|---|---|
| #1 sim outside the tree | `CompanyRankings` is an autoload service. No node per company. |
| #2 turn logic in advance functions | Recompute on the **AI phase** only — never in `_process`. |
| #3 determinism | Seeded RNG only. **Never** global `randi()`/`randf()`. |
| #4 versioned saves | See §5 — the design deliberately needs *no* new save state. |
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
name           String   from the shuffled roster
revenue        float    starts at 100.0/turn
growth_rate    float    fixed per company: 0.05 | 0.02 | 0.01
phase_offset   int      0..8, fixed per company
```

Distribute the nine companies across the three growth rates 3/3/3 so the table has a clear top,
middle and tail.

### 4.3 Per-turn update

For company `i` at turn `t`, the cycle position is `(t + phase_offset_i) % 9`:

| position | behaviour |
|---|---|
| 0–4 | grow: `revenue *= (1 + growth_rate)` |
| 5–6 | shrink: `revenue *= (1 - growth_rate * 0.5)` |
| 7–8 | flat: unchanged |

Shrink is **half** the growth magnitude, so the long-run drift is upward — a company that grew 5%
for five turns and fell 5% for two would still net +11%, which is fine, but halving it keeps the
5%-tier companies from lapping the 1% tier inside 50 turns. Tune if the spread looks wrong; this
is a display number, not a balance constant, so it does **not** fall under rule #7.

The brief also specifies **revenue changing −2%..+5% per turn**. Apply a seeded per-turn jitter in
that range on top of the cycle so the table is not perfectly mechanical. This is the only RNG draw
in the feature.

### 4.4 The player's row

The player's revenue is the **real** figure the top bar already shows (`money_in` from the last
turn summary), inserted into the same sorted list. Never smooth or scale it — the point is that
the player's actual trajectory is what is being ranked.

Two consequences to handle explicitly:
- **Turn 1** the player has no revenue and sits last. Correct, and worth showing.
- **Late game** the player will likely be an order of magnitude above every rival, because rivals
  compound from 100 and the player compounds from a real industrial base. Expect rank 1 by ~t150.
  If that reads as anticlimactic, the fix is to raise the rivals' starting revenue, **not** to
  scale the player's — flagged as an open question in §7.

---

## 5. Persistence — none required

This is the load-bearing design decision. Because every company's revenue at turn `t` is a pure
function of `(match_seed, company_index, t)`, the whole table can be **recomputed from scratch on
load** rather than saved. Nothing goes in the save file, no `schema_version` bump, and no migration
(rule #4 is satisfied by having no new state rather than by serializing it).

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

---

## 7. Open questions

1. **§2 — cycle or population split.** Blocking. Recommendation: cycle (A).
2. **Rival starting revenue.** 100/turn as briefed means the player laps the field by roughly t150.
   Options: raise rivals' start, give the top rival a higher growth tier, or accept it as an
   intended power fantasy. Recommend deciding after seeing a real 300-turn run.
3. **Does the player's company have a name?** The rankings need one for the player's row. If none
   exists, a New Game field is the natural home, defaulting to something neutral.
4. **Do rivals react to the carbon clock?** Cheap and thematic — rivals on the 1% tier could stall
   after t60 as the squeeze bites. Deferred; not in v1.

---

## 8. Test plan

Unit (`tests/test_runner.gd`), all non-destructive — **no `MatchState.reset()`**, which wipes the
NPC-port state later tests assert against:

- **Determinism.** Same seed + same turn ⇒ identical table. Compute t50 twice, assert equality.
- **Reconstruction.** Advance to t50, rebuild from seed alone, assert the table matches — this is
  what makes §5's no-save design safe.
- **RNG isolation.** Draw the full table for 50 turns, assert `_match_rng`'s state is unchanged.
  This is the test that catches the determinism break described in §5.
- **Cycle shape.** Over 9 turns a single company grows on 5, shrinks on 2, holds on 2.
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
