# Price-Impact Ladder — decay removed, glut/deficit carries the market

**Status:** BUILT 2026-08-29 (branch `price-impact-ladder-spec`) — engine, UI,
tests. Evidence: unit suite **3430 passed / 0 failed**; e2e open_field_1 t100
**786 passed / 0 failed**; parse check 513 scripts, 0 failed. Economy effect at
t100: benchmark revenue 668 → 737 (**+10.3%**, in line with R7f's ≈+9%
prediction), t100 profit −121 → −55, last-profitable-turn unchanged at t47 — no
scoreboard flips.

(Earlier runs in this session reported 11 unit / 7 e2e failures on BOTH this
branch and unmodified main. Those were a cold Godot asset-import cache after the
pull — new PNGs had no `.godot/imported/` entry, so `preload()` failed to parse
`main_menu.gd` / `menu_chrome.gd`, which cascaded to `StatusLed` and every panel
test. Re-running regenerated the cache; nothing was wrong with the code.)
**Provenance:** the original write-up (2026-08-28) was lost uncommitted; this is a
reconstruction (2026-08-29) from the owner's dictated summary. Everything the owner
stated is marked plainly; details the summary did not pin down are marked
⚠ INTERPRETATION and need a ruling before build.

---

## 1. The change in one paragraph

Remove per-good price decay entirely — the `decay_rate` CSV column stops driving
prices and "prices always fall" is no longer true. In its place, the glut/deficit
price-impact model becomes the *only* thing that moves prices: a steeper, longer
**ladder** of per-turn impact rates keyed to multiples of a good's base production,
an **asymmetric cap** (floor 40% of base price, ceiling 250%), **linear** (non-
compounded) accrual, a **10-turn rolling average** that decides when the market
believes your volume has genuinely changed and walks the price to its new
equilibrium over 10 turns, and **thresholds that inflate 25% every 20 turns** so a
growing world absorbs more before noticing.

This deliberately reverses the owner ruling of 2026-07-27 ("monotonic price decay
is deliberate"). The offline evidence already exists: `future-market-dynamics.md`
§R7f re-priced full simulated runs with decay retired and measured ≈ +9% uniform
absolute uplift with relative P&L unchanged (82% → 81%) — decay can go with minimal
rebalance, and the downward squeeze then rests on the carbon levy, port fees and
input premia, which is where we want it.

## 2. What is removed

- The decay loop in `market_state.gd` `tick_turn()` (the
  `prices[good_id] *= (1.0 - decay)` step) and `DECAY_FIRST_TURN`.
- `decay_rate` as a live input. The CSV column and the `catalog.gd` parse can stay
  for save-compat, but nothing reads it for pricing.
- The decay-based forecast in `get_forecast()` (`current * pow(1.0 - decay, n)`).
  With decay gone the naive forecast is flat; forecast should instead project the
  impact model (current impact ± this-turn's accrual rate × n, clamped to the cap).
- The decay-clock probe and the calm-era `decay_live` guard from the early-game
  onboarding spec §4.1 — the t1–30 price freeze now only needs the impact guard
  (`price_impact_rate` suppressed), since there is no drift left to freeze.

Untouched: `company_rankings.gd`'s revenue "decay" (unrelated NPC cycle), the
market buy markup, port fees, carbon levy.

## 3. The ladder (replaces the 1x/2x/4x/10x bands)

Keyed, as today, to the player's **net** market volume in one good in one turn,
as a multiple of the good's **base production**
(`Catalog.base_output_for_good` — largest per-turn batch among active recipes,
L1 unmodified). Net selling pushes price down (glut); net buying pushes it up
(deficit), symmetric rates. Goods with no producing recipe take no impact.

| net volume (× base production) | impact, %-points of base price per turn |
|---|---|
| ≤ 1x | 0 (recovery regime, §5) |
| > 1x | 0.05 |
| > 3x | 0.1 |
| > 5x | 0.2 |
| > 6x | 0.3 |
| > 7x | 0.4 |
| > 8x | 0.5 |
| > 9x | 0.6 |
| > 10x | 0.7 |
| > 11x | 0.8 |
| > 12x | 1.0 |

Owner ruling 2026-08-29: the 6x–11x rungs step by exactly 0.1, then the ladder
**jumps 0.8 → 1.0 at 12x** — the discontinuity is deliberate; true flooding gets
a step change, not a smooth top-out. Note the 2x and 4x gaps are deliberate per
the dictated ladder — the market tolerates a second building's worth of volume
more gently than the old 2x band did.

## 4. Caps and linear accrual

- **Accrual is linear, not compounded** (owner ruling). Impact accrues in
  percentage points and applies to the *static* base price:
  `price = base_price × (1 + impact_pct / 100)`. The engine already works this
  way (`impact_pct += rate`; multiplicative apply) — with decay gone the base is
  genuinely static, so the model becomes purely linear. No per-turn multiplication
  of the current price.
- **Asymmetric cap** (owner ruling): price floor **40% of base** (impact −60
  points), ceiling **250% of base** (impact +150 points). Replaces today's
  ±`PRICE_IMPACT_CAP_PCT` (±40).
- Consequence worth stating: at the 1%/turn maximum, the floor takes 60 turns of
  sustained 12x flooding; the +150 ceiling takes 150 turns of equivalent buying —
  in practice the ceiling is headroom (for the Rivals and Markets NPC flows and
  scripted events) rather than something a lone player reaches.

## 5. Rolling average and the return to equilibrium

Owner ruling: the market keeps a **rolling average of the last 10 turns** of the
player's net volume per good, and uses it to decide whether to return the price
to a new equilibrium; when production drops, the price **returns over 10 turns**
to the new equilibrium implied by that rolling average.

Recommended concrete mechanic (⚠ INTERPRETATION — confirm):

1. Track `net_history[good]`: the last 10 turns of net volume (saved with the
   match).
2. Each turn compute the **sustained band**: the ladder band of the 10-turn
   rolling average (against current, inflated thresholds — §6).
3. **Accrual regime** — sustained band > 1x: accrue this turn's ladder rate
   (from this turn's actual volume) as today.
4. **Recovery regime** — sustained band ≤ 1x: the market believes the glut (or
   deficit) is over. Snapshot the gap to equilibrium and close it linearly over
   10 turns (gap/10 per turn). Equilibrium is impact 0 — base price — whenever
   sustained volume is ≤ 1x. Re-entering the accrual regime cancels the
   walk-back; the next drop re-snapshots.

This replaces the flat 0.1%/turn bleed (`PRICE_IMPACT_RECOVERY_PCT`), whose full
recovery from deep impact took 300+ turns, and — because the *rolling average*
gates the regime, not the single current turn — it kills the pulsing exploit the
current code comments worry about (sell 12x every other turn, recover on the off
turns): one quiet turn no longer flips the market into forgiveness.

## 6. Threshold inflation: +25% every 20 turns

Owner ruling: the multiplier thresholds (in units, i.e. `multiple × base
production`) increase by 25% every 20 turns — the world economy grows and absorbs
more volume before your selling registers.

- Schedule — **LINEAR (owner ruling 2026-08-29)**: +25% of the *original*
  threshold per 20-turn step. t1–20 ×1.00, t21–40 ×1.25, t41–60 ×1.50,
  t61–80 ×1.75 … reaching ×4.50 for t281–300. Not compounding.
  BUILT 2026-08-29: `EconomyConfig.impact_threshold_scale()`, indexed from t1
  (the §9 calm-era question stays open — re-indexing to t31 is a one-line change).
- The inflation applies to the unit thresholds only; the ladder rates and the cap
  do not scale.
- This supersedes the "later they scale with expected output every 10 turns" note
  in `economy_config.gd`.

Worked example — copper wire, base output 32, ladder start >32 units:
t10, selling 200/turn = 6.25x → 0.3%/turn. By t50 thresholds are ×1.5625
(1x = 50 units), so the same 200/turn = 4x → 0.1%/turn. Growth for free, without
touching the player's buildings.

## 7. Engine integration map

| site | change |
|---|---|
| `scripts/market_state.gd:169-176` | delete decay loop + `DECAY_FIRST_TURN`; `tick_turn` only ticks impact |
| `scripts/market_state.gd:185-199` `_tick_impact` | ladder rates; rolling-average regime switch; 10-turn linear walk-back; cap −60/+150 |
| `scripts/market_state.gd:107-112` `impact_thresholds` | new rungs; multiply by the turn-inflation factor; variable-length result |
| `scripts/market_state.gd:127-136` `get_forecast` | impact-model projection instead of decay powers |
| `scripts/market_state.gd` save/load | persist `net_history`; old saves: prices in the save were decayed — accept them as-is or re-anchor to catalog base (recommend re-anchor: post-load prices jump *up*, never down, and R7f says ≈ +9%) |
| `scripts/economy_config.gd:81-105` | replace band constants + `price_impact_rate()`; delete flat `price_impact_recovery()`; add ladder table, cap pair, inflation schedule |
| `scripts/market_row.gd:158+` | threshold column/tooltip is hardcoded to 4 bands — rebuild for the ladder (headline 1x figure stays); tooltip states the floor/ceiling asymmetry |
| `scripts/search_overlay.gd:1123` | drop the "Decay rate" encyclopedia row (or replace with the good's current 1x threshold) |
| `data/goods.csv` / `catalog.gd:664` | `decay_rate` column retired from pricing; keep parsed for compat |
| early-game onboarding §4.1/§8 | calm era keeps only the impact guard; decay-clock probe deleted |
| `docs/future-market-dynamics.md` §5 | update the "decay stays orthogonal" note — decay is now gone at EA, not post-EA |
| balance tooling | sweep `tools/` + `balance.py` for `decay_rate` reads; per the engine-cost-model ground truth doc the design model already ignores glut, so re-verify the 80/80 band solve against gently-rising prices |

## 8. Balance consequences to expect (from the R7f evidence)

- ≈ +9% uniform absolute price uplift across a run; relative profitability
  essentially unchanged — no per-recipe rebalance forced.
- The macro squeeze moves wholly onto the carbon levy, port fees and input
  premia. Check the raw-materials rule still holds (raw-only play must never test
  profitable — the flat £5/good/turn port fee is the lever, and it bites harder
  when raw prices no longer sag on their own).
- Stockpiling/warehousing gets stronger the moment prices can sit still or rise;
  re-check storage-fee economics.
- Victory tracks priced in £ (rising bar) are worth a sanity pass against the
  uplift.

## 9. Open questions (need owner rulings before build)

1. Calm era t1–30: should threshold inflation index from t31 instead of t1
   (the onboarding spec's index-from-unfreeze rule for the port fee suggests
   t31)? Built as t1 for now.
2. Does the *deficit* side warrant its own ladder (the asymmetric cap suggests
   the sides are not meant to feel the same)? Built symmetric for now.

Resolved 2026-08-29:
- The 7x–11x rungs — 0.1 steps from 6x, with the deliberate 0.8 → 1.0 jump at
  12x (§3).
- Threshold inflation is LINEAR (§6).
- Recovery shape: linear gap/10, snapshotted when the window goes quiet (§5) —
  BUILT.
- Old-save migration: prices re-anchor to catalog base on import (they move UP,
  never down) — BUILT, no version bump needed.
