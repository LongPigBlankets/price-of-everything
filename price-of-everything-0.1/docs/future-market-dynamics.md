# Future Market Dynamics — NPC flows, price discovery, and the settings they unlock

## → Shipping candidate: the **"Rivals and Markets"** free update (post-EA)

**Owner ruling, 2026-08-12:** this whole body of work is earmarked as a **free
post-EA content update titled *Rivals and Markets***, not an EA-launch change.
The reasoning: it turns an existing cosmetic panel into the game's second major
system, it is a genuine "the world came alive" beat to bring lapsed players back,
and it is large enough to carry its own announcement — while EA ships on the
current, known-stable pricing model.

What the update contains, in the order it would be built (each stage is playable
and shippable on its own, and each is already simulated — see the plate reference
in §7):

1. **Living market** — Model P bands + the R4 rival supply response: the
   competitors' panel becomes real supply and demand, prices carry structural
   premia and gluts, specialising in what rivals over-consume becomes a strategy.
2. **Industry churn** — capacity depreciation, bankruptcies, acquisitions
   (50% write-down), price-triggered entrants at era-scaled sizes, plus the
   market-disruption window that makes a big arrival actually crash a price.
   This is the news layer: 100+ panel-visible corporate events per run.
3. **World demand** — the tiered fraction-drawn demand cycle (raw calm → apex
   volatile), which is also the seam where a real final-demand curve replaces
   the band table later.
4. **Apex competition from era 2** — the endgame tiers stop being the player's
   private garden; supplying the boom becomes as strong a play as joining it.
5. **New-game settings** — Boom & Bust Cycles (persona mix), Competitor
   Responsiveness (decision lag), Market Depth (β 0.40/0.50/0.60), optional
   price-band width; plus the scripted market-event calendar (State-Owned
   Champion and friends) as the boom-bust generator.

**Status:** design exploration, fully simulated offline against engine ground truth
(2026-08-12). **Nothing here is built in-engine yet**, and nothing here is proposed
for EA. Companion charts (Plates I–XXX): the "If the Rivals Traded" artifact. Sim
suite: `tools/market_model/` (self-contained Python + `tools/npc_market_dump.gd`
to regenerate the engine dump).

**The pitch in one line:** make the competitors' panel real — count rival output as
sold and rival input needs as bought — through a *banded-equilibrium* price model
plus a rival *supply response*, and the same machinery becomes three new-game
settings and a scriptable market-event system.

---

## 1. The model this is built on (Model P + R-series response)

Simulated end-state, chosen after eliminating alternatives (see §6):

```
net(g)   = (player sold − player bought) + (1−β) × (rival sold − rival buys)
             β = share of NPC flow absorbed by world trade (default 0.75)
T(g,t)   = max(base_output, 0.6 · base_output · γ(t))       γ(t) = 1 + 0.425·⌊t/5⌋
band     = |EMA₅(net/T)|:  ≤1× → 0   >1× → ±10%   >2× → ±20%   >4× → ±30%   >10× → ±40%
impact   → walks toward its band target at 0.5%/turn (recovery constant retired)
price    = decayed base × (1 + impact/100)
```

Rival supply response (R4 configuration):

```
Growth multiplier per good, applied to each rival's 5-turn expansion increment:
  OUTPUT ladder:  ≥+10% → ×2.0   +5…10 → ×1.5   −5…−10 → ×0.75   ≤−10% → ×0.5
  INPUT  ladder (value-weighted, w ∝ market price × qty):
                  ≤−25% → ×2.0   −12…−25 → ×1.5   +12…+25 → ×0.75   ≥+25% → ×0.5
  G = clamp(G_in · G_out, 0.25, 2.5)
LAG:   a ladder engages only after its trigger direction persists N turns (setting §3.2)
EXIT:  impact ≤ −20% held ≥5 turns → responding rivals RETIRE capacity by the drawn
       increment × personality (floor: the base plant). Cautious rivals never exit.
PERSONALITIES: each rival is cautious (never responds), half-cautious (half the
       deviation, half-size exits) or aggressive (full response) — the mix is §3.1.
```

Why this shape (all measured, mean of 3 seeds):

- **The current live model cannot host NPC flows.** Counting them raw saturates the
  market: 58/73 goods pinned at ±40% by t200; threshold-growth variants only delay
  it. The current model also caps *the player alone*: a standard build-out
  (B1@t10 → L3@t60 → new building/upgrade every 5 turns) rides to −40% by t160, and
  a hard specialist who market-buys inputs ends **negative from t190** (lifetime 1%
  of the impact-free baseline). That failure exists in the live game today.
- **Band targets, not runaway accrual**, give prices stable levels that only move
  when someone's scale crosses a band edge — the "stretches, then moves" texture.
- **β-netting** starts the world in equilibrium (trade absorbs the expected
  surplus/shortfall) so structure presses prices without pinning them.
- The supply response makes premia self-correct (rivals chase scarcity), creates
  boom-bust arcs, and prices predatory dumping honestly (you can force rival exits,
  but you pay glut prices while doing it).
- Steel specialist outcome under the default R4: lifetime P&L ≈ 67–69% of the
  impact-free baseline, every expansion step still profitable, premium windows of
  27–51 turns depending on settings — vs 1% under the current model.

**Not in scope at EA (reserved for free updates):** an explicit world-demand curve.
The band-target table is a step approximation of `(D/S)^k`; when real demand ships,
it replaces the table on identical plumbing (ν, γ, flows, EMA) and β's absorbed
share becomes the exogenous final-demand term.

---

## 2. Engine integration sketch

- Inputs: per-good base recipe coefficients (catalog load), γ(t) (one line from
  `company_rankings.gd` constants), realized rival volumes (the seeded draws the
  panel already computes).
- State that must persist in saves: per-rival-per-good **capacity** (or one
  capacity multiplier per good + the persona array), the impact map (already
  saved), persistence counters. Everything else derives deterministically.
- Cost: O(goods × 9) per turn for flows + O(goods × inputs) for the weighted input
  deviation. Trivial next to `cost_solve`.
- UI hooks for free: the competitors' panel becomes a market map (ambient bands),
  and every exit/expansion is a news item ("Fentiman idles two solar lines").
- Determinism: G and exits are pure functions of (seeded draws, impact state) —
  rule #3 safe.

---

## 3. Game-setup settings — DEFINITIVE (measured on R7m)

> Everything from §3.1 down is the *historical exploration* on earlier configs.
> This block is the shipping spec: every option re-measured on the final R7m
> ruleset (`r7p_settings.py`, `r7q_settings2.py`, `r7r_apex.py`), ambient +
> integrated-player, 3 seeds, 300 turns. P&L is the integrated player's lifetime
> profit vs an impact-free baseline; "loss turns" are turns in the red.

**Five settings, three options each. Defaults in bold.**

### S1 · World Demand — *does the world's appetite grow?*
The largest dial in the system; doubles as the economic-difficulty axis.

| option | what it does | ambient character | player |
|---|---|---|---|
| Flat | no demand cycle | apex σ 0.0pp, mid-range 11pp, 5% of turns above base / 73% below, 31 entrants | **77%**, 0 loss turns |
| **Cyclical** | tiered fraction-drawn waves (raw calm → apex volatile) | apex σ 11.8pp, range 26.6pp, 28%↑/47%↓, 179 entrants | 35%, 32 loss |
| Boom | busts return only ~70% of their boom → net-up drift | apex σ 12.4pp, range 37.2pp, **72%↑/8%↓**, 282 entrants, steel +27 | **100%**, 0 loss |

Flat is a stagnant, glut-heavy world that is *easy* (nothing competes prices
down but nothing grows). Boom is a rising tide — the friendliest and busiest.

### S2 · Price Volatility — *how far can a price swing?*
The band-ladder amplitude. Pure risk dial: same market, different stakes.

| option | ladder targets | ambient | player |
|---|---|---|---|
| Steady | ±3…±24 | apex σ 7.2pp, mid-range 17.2pp, 45 extrema | **65%**, 0 loss turns |
| **Standard** | ±5…±40 | apex σ 11.8pp, range 26.6pp, 386 extrema | 35%, 32 loss |
| Turbulent | ±7…±60 | apex σ 18.3pp, range 40.2pp, 617 extrema | **−2%, 99 loss turns** |

⚠️ Turbulent is unplayable for a passive build-and-sell player (net-negative
lifetime). Ship it only with a warning label, or as the top difficulty.

### S3 · Apex Competition — *when do rivals enter the endgame tiers?*
Clean monotonic endgame-difficulty dial.

| option | | ambient | player |
|---|---|---|---|
| Off | apex stays player-only | 105 entrants, steel +12.2 | **67%**, 0 loss turns |
| Era 3 (t200+) | late arrival | 165 entrants, steel +14.8 | 49%, 18 loss |
| **Era 2 (t100+)** | mid-game arrival | 179 entrants, steel +16.5 | 35%, 32 loss |

The player's own EV price is the tell: a protected garden all game, versus 81%
of late turns below base once contested (Plate XXIX).

### S4 · New Entrants — *how much new capital enters the economy?*
The live discipline mechanism under R7m (see the cut settings below).

**Units, because this confuses people:** entry is decided **per good** — a good's
own price must hold above the trigger, its 10-turn cooldown must be clear, and it
caps at 12 producers. The numbers below are **totals per 300-turn run across all
~76 goods** (≈0.6 entrants/turn nationally), *not* per turn and not per good.

Three ways to expose the dial. **Ship (a): the per-good cap** — it is the only
one with no settings interference, and it reads plainly as *"how many new rivals
can ever pile into one market"*.

**(a) PER-GOOD entrant cap — RECOMMENDED** (`r7u_pergood.py`, `r7v_apexshare.py`):

| cap / good | entrants | player P&L | loss turns | acquisitions |
|---|---|---|---|---|
| 1 | 47 | **62%** | 0 | 80 |
| 2 | 91 | 58% | 0 | 79 |
| **3** | 130 | 52% | 0 | 78 |
| 5 | 146 | 47% | 8 | 75 |
| 10 | 171 | 37% | 29 | 74 |
| (uncapped) | 179 | 35% | 32 | 73 |

A clean monotone ladder, and — the reason to prefer it — **it guarantees tier
coverage**. Measured entry by tier (goods per tier: raw 17, processed 20,
intermediate 20, finished 9, apex 7):

| setting | total | apex entry | tier coverage |
|---|---|---|---|
| per-good 1 | 47 | **6.7 → 7/7 apex goods** (14% of entry) | raw 9/17, proc 13/20, int 13/20, fin 4/9, **apex 7/7** |
| national 50 | 50 | **0.7 → 1/7 apex goods** (1% of entry) | raw 17/17, proc 15/20, int 18/20, **fin 0/9, apex 1/7** |
| national 100 | 100 | 21.3 (21%) | apex finally served |

At the *same* entrant volume, the per-good cap contests **every apex market**
while the national budget contests **one** — and starves the finished tier
entirely (0/9). That is the §S4 interference trap solved structurally rather
than by tuning: raw goods can no longer eat apex's allocation, so S3 (Apex
Competition) and S4 become independent, as a settings screen requires.

**(b) National entrant budget** (`r7s_entrants.py`) — wider raw spread, but
winner-take-all by *timing*, which is what creates the trap:

| budget / run | entrants | budget gone by | player P&L | loss turns | where it gets spent |
|---|---|---|---|---|---|

| budget / run | entrants | budget gone by | player P&L | loss turns | where it gets spent |
|---|---|---|---|---|---|
| 10 | 10 | t30 | **66%** | 0 | raw 5, processed 4 |
| 20 | 20 | t45 | 66% | 0 | processed 8, raw 7, intermediate 5 |
| 50 | 50 | t97 | 65% | 0 | intermediate 18, raw 17, processed 15 |
| 100 | 100 | t167 | 54% | 0 | intermediate 26, processed 25, **apex 21** |
| 150 | 150 | t237 | 45% | 13 | **apex 46**, intermediate 35, processed 31 |
| **200** | 178 | t292 | 35% | 32 | apex 58, intermediate 38, processed 37 |
| uncapped | 179 | — | 35% | 32 | (natural demand is ~179, so 200 ≈ uncapped) |

**(c) Trigger sensitivity** (`r7q_settings2.py`) — same mechanism, weakest spread:
Patient (+15%×8t / +25%×3t, cooldown 15) 127 entrants, **44%** · Standard
(+10%×5t / +20%×2t, cooldown 10) 179, 35% · Eager (+8%×3t / +15%×2t, cooldown 6)
201, 32%.

⚠️ **Settings-interference trap — the reason (b) is NOT recommended.** The national budget is spent
chronologically, first-come-first-served, and apex goods cannot enter until
t101 — so **a small budget is entirely consumed by raw/processed goods in the
first ~50 turns and silently cancels the S3 Apex Competition setting.** At
budget ≤50 apex entry never happens regardless of what S3 says; apex only gets
real entry from ~100 up. Tested fix — a **per-era budget** that refills at t101
and t201 — does *not* solve it (10/era → 66% P&L, apex still absent; 50/era
→ 43%, apex 44; i.e. per-era ≈ run-budget of the same total: the binding
constraint is total volume, not timing, because ~60 non-apex goods out-compete
7 apex goods for any small pool). **The fix is option (a), the per-good cap** — measured above: it contests 7/7 apex
markets at 47 entrants where the national budget contests 1/7 at 50. Ship (a);
if (b) is ever used instead, ring-fence a per-tier share (~30% for apex) and treat
S3 and S4 as coupled.

Market *character* barely moves across the whole budget range (apex σ 11.8–12.2,
mid-tier range 23.4–26.6pp, 21–28% of turns above base) — this is a
player-pressure dial, not a volatility dial. Acquisitions move inversely
(81 at budget 10 → 73 uncapped): fewer entrants, more distressed consolidation.

### S5 · Market Depth — *how much does world trade absorb?* (β)
Now a **character** dial, not a difficulty one — P&L is flat across it (38/35/39%).
What moves is the glut/premium balance and the event mix.

| option | β | ambient | player |
|---|---|---|---|
| Deep | 0.60 | 39% of mid-tier turns below base, 52 acquisitions, 193 entrants | 39%, 24 loss |
| **Standard** | 0.50 | 47% below, 73 acquisitions, 179 entrants | 35%, 32 loss |
| Shallow | 0.40 | **52% below, 92 acquisitions**, 171 entrants | 38%, 29 loss |

Shallow = a consolidating, glut-prone world; deep = a crowded, entrant-heavy one.

### ✂️ Two designed settings that measured INERT — cut them

- **Competitor Responsiveness (decision lag 3 / 5 / 10 turns):** identical
  outputs on every metric (apex σ 11.8 in all three, P&L 35% in all three,
  extrema 380/386/386).
- **Rival Temperament (persona mix 4/3/2 · 3/3/3 · 2/3/4):** P&L 35% in all
  three; only acquisitions move (81 → 62). It was a real dial on R7k (Plate XV).

**Why both died:** R7j softened the *incumbent* growth response to ×1.3 and made
price-triggered **entrants** the market's disciplinarian. Both cut settings act
only on incumbent response, which no longer moves the needle. They can be revived
by restoring incumbent growth to ×2.0 (R7i-era) — but that is a design choice
about who disciplines the market, not a free addition. Until then, **do not ship
a setting that does nothing**; S4 is their functional replacement.

**Recommended default preset:** Cyclical · Standard · Era 2 · Standard · Standard
(= plain R7m: 35% P&L, 32 loss turns for a *passive* player — an active one
adapts, see Plate XXX). For a friendlier launch preset: Cyclical · Steady ·
Era 3 · Patient · Standard.

---

## 3-historical. The three new-game settings (the bedrock claim)

All three are one-constant dials on the same machinery. Measured effects below;
each row is a full 300-turn, 3-seed simulation with the standard player build-out.
**Superseded by the definitive block above — kept for the reasoning trail.**

### 3.1 Market Boom & Bust Cycles — the persona mix

Split of the 9 rivals (cautious / half-cautious / aggressive). **Player lifetime
P&L is mix-invariant (67–69%)** — aggression eats the early premium but repays it
as a shallower late glut. The setting purely changes texture:

| setting | mix | premium window ≥+10% | ambient solar heal (t300) | dumping counter-play | price smoothness |
|---|---|---|---|---|---|
| Dramatic (default?) | 4/3/2 | 42 turns | −16.7% | weak (rival cap ×0.82) | 4.0 rev/good |
| Balanced | 3/3/3 | 34 | −15.2% | medium | 4.5 |
| Disciplined | 2/3/4 | 27 | −13.0% | strong (rival cap ×0.54) | 4.3 |

(2/4/3 measured too: near-Disciplined healing with the smoothest prices, 3.9 —
a good hidden compromise.) Boom-and-bust reading: cautious markets give long booms
and deep hangovers; aggressive markets correct fast in both directions.

### 3.2 Competitor Responsiveness — the decision lag

Turns a price signal must persist before rivals' growth ladders engage.
Measured: lag 10 (at 4/3/2) → 42-turn windows, deep overshoot (−15…−17%), P&L 67%;
lag 5 (at 3/3/3) → 29-turn window, overshoot ≈ −10…−14%, P&L 68%. The lag is
**symmetric** — it protects the player's premium and prolongs the rivals'
overshoot ("converts profit into drama"). Proposed values: **3 / 5 / 10 turns**
(3 not yet simulated; expect windows ≈ 20 turns and minimal overshoot — verify
before shipping).

### 3.3 Market Depth — β, the world-trade absorption share

"How much of the national imbalance the world market soaks up." Sweep at 3/3/3,
lag 5 — **this dial matters the most of the three**:

| β (setting) | ambient mean |impact| | steel ambient premium t50 | solar heal t300 | specialist window | specialist P&L |
|---|---|---|---|---|---|
| 0.60 (shallow) | 13.6% | +19.8% | −20.0% | 51 turns | 59% |
| 0.75 (standard) | 9.5% | +17.5% | −14.3% | 29 | 68% |
| 0.90 (deep) | 4.4% | +8.5% | −10.0% | **0** | 61% |

⚠️ Two findings to respect before shipping this as a setting:

1. **β=0.90 deletes the overconsumption play** (window 0 — structural premia never
   reach +10%) and is *worse* for the specialist than 0.75 despite a calmer world.
   Cause: β nets **NPC flows only**; the player's own volume stays fully live, so a
   deep world removes their premium shelter while leaving their self-glut intact.
2. If "deep markets" should damp the player too, pair β with the threshold
   constant (e.g. raise `c` from 0.6 with β) so depth scales everyone. As
   implemented, the honest labels are: 0.60 = "volatile frontier economy",
   0.75 = "standard", 0.90 = "becalmed" (calm world, but specialisation strategies
   largely off — arguably a legitimate difficulty/flavor choice if labeled so).

> **Superseded for the R7 family:** with the demand wobble at full weight and
> era-scaled entrants (R7g+), the depth setting re-centres at **β = 0.50
> default, options 0.40 / 0.60** (`r7l.py`, Plate XXVIII). Measured on the R7k
> config: 0.40 "volatile & consolidating" (steel 10 extrema at 30-turn period,
> 115 acquisitions, player 69%), 0.50 "standard" (88 acq, 105 entrants, 67%),
> 0.60 "calm & crowded" (121 entrants, 64%). Two structural notes: **apex
> goods are β-invariant** (no rival supply to absorb — depth shapes the
> producible economy only), and the player-benefit sign flips vs the old
> Model-P sweep — louder structure pays the integrated player on both sides
> (deeper sell premia, deeper input gluts), so lowering the default 0.75 →
> 0.50 is itself a player buff (59% → 67%). The 60/75/90 numbers below stand
> for the plain Model-P config only.

### 3.4 Price-band width — a possible fourth setting (±40% vs ±60%)

Widening "max price change" to ±60% only does something if the whole ladder
stretches — moving just the top band (10/20/30/**60**) is a no-op (ambient 9.8%
vs 9.5%, specialist P&L identical) because almost no good ever reaches the 10×
band. With the proportional ladder **±15/30/45/60** (triggers and the −20% exit
rule unchanged), crossed with market depth (3/3/3, lag 5):

| config | ambient mean \|impact\| | goods ≥±30 / ≥±45 | solar t300 | spec window | spec P&L |
|---|---|---|---|---|---|
| ±40 · β 0.60 | 13.6% | 2 / 0 | −20.0% | 51t | 59% |
| **±60 · β 0.60** | **18.3%** | **18 / 3** | **−30.0%** | 61t | **50%** |
| ±40 · β 0.75 | 9.5% | 2 / 0 | −14.3% | 29t | 68% |
| **±60 · β 0.75** | 12.4% | 4 / 2 | −15.3% | 40t | **54%** |
| ±40 · β 0.90 | 4.4% | 1 / 0 | −10.0% | 0t | 61% |
| **±60 · β 0.90** | 6.4% | 2 / 1 | −15.0% | 0t | **43%** |

Findings: the wide band is a **drama multiplier and a scale-player tax** — premium
windows widen (+10–11 turns) but the player lives in the glut bands, so deeper
band-1/2 targets (−15/−30) cut lifetime P&L by 9–18 points at every depth. The
specialist never goes per-turn negative in any cell (Model P holds that line).
β 0.60 + ±60 is a legitimate "wild-west" combo (18 goods ambiently beyond ±30);
β 0.90 + ±60 is the worst of both worlds (no premium plays, −30 self-glut, 43%).
If the goal is "prices breathe wider" without taxing scale, stretch only the upper
rungs (**±10/30/45/60**) so band 1 — where normal-scale play lives — stays at ±10.
Pacing note: at 0.5%/turn approach, a ±60 target is a 120-turn journey.
Sim: `tools/market_model/cap60_sweep.py`.

---

## 4. Scripted market events: the State-Owned Champion

Prototype of a 10th competitor as a **market-event device** (diegetic: subsidised
national champion). Spec as simulated (β 0.75, 3/3/3, lag 5):

- Produces **every** rival good; never responds to prices; expands by the **maximum**
  increment (+1 base batch per good every 5 turns) — by t85 it runs ~18× base per
  good, ~2.2× the average rival ("leads in every domain").
- Freezes at t85; production steps down 75% → 50% → 25% → 0% at t95/100/105/110
  (gone before t115).

Measured impact (ambient / with the steel-specialist player):

| effect | without champion | with champion |
|---|---|---|
| steel premium at t50 (specialist) | +9.2% | **+18.7%** |
| specialist premium window | 29 turns | **50 turns** |
| post-collapse steel glut (t150) | −10% | **−17.2%** (demand cliff) |
| specialist lifetime P&L | 68% | 69% (boom pays for the cliff) |
| hydrogen (champion squeeze) | +30% | **+40% (capped) t85–100**, then back |
| solar glut after collapse | −18…−20% | **relief to −10.5% by t150** |

The arc works as narrative: goods the champion net-buys (steel, hydrogen) boom
while it grows and cliff when it dies; goods it net-sells (solar) suffer then
recover. Player money is roughly neutral — the event reshapes *when* profit comes
and rewards reading the collapse in the panel/news.

**Muting caveat & the "loud" variant:** at β=0.75 the trade closure absorbs 75% of
the champion's flows, which is why ambient steel barely moves without the player.
For a louder event, count the champion's flows at 100% (subsidised dumping is not
absorbed by world trade) — one line, not yet simulated.

---

## 4.5 Boom-bust cycles: written into the flows, not the bands

Investigated whether the band framework can generate self-sustaining cycles
endogenously (R5 = R4 + capacity depreciation 0.75%/turn + bankruptcy at the
floor in ≤−15% markets + entrants into sustained premia; R5b = the high-gain
corner: lag 12, ×2/×0.5 output response, entrants adding up to 12 slots/good).
**Result: zero cycles detected in any configuration** — the band layer (EMA +
quantised targets + 0.5%/turn approach) low-passes every oscillation the
capacity dynamics produce. R5 is instead the *calmest* economy tested (ambient
mean |impact| 2.9%) and incidentally the best glut-healer (solar −20 → −7).

Conclusion: **cycles must be written into the flows; the machinery then
performs them.** The champion (§4) is the existence proof — its rise and fall
produced a textbook boom-cliff arc. The event system this implies:

- Shock = a timed per-good flow modifier riding the same plumbing:
  demand surge/collapse (±10–30% of the good's world flow for 20–40 turns),
  foreign supply cut (β dip for one good), bankruptcy wave, embargo.
- Rivals respond through the normal ladders, so every shock buys ~two swings
  (the arc plus the overshoot correction) — one event ≈ one 40–80-turn story.
- The narrative/decision-event scheduler already exists in-engine; shocks are
  deterministic, seeded, and panel-visible.
- Diegetic copy writes itself: "international copper market shuts down —
  +20% global demand for your copper", "foreign boom lifts EV demand 10%".

Keep from R5 regardless: **depreciation** (one constant, fixes glut stickiness
better than anything else tested) and **bankruptcy/entrant events as news
structure** (~30–50 panel stories per run).

**R6 follow-ups (owner proposals, all tested — `r6_demand.py` / `r6d.py` /
`r6ef.py`):**

- **Acquisitions with a 50% write-down** (distressed rival sells to the largest
  player, half the capacity scrapped): works exactly as hoped as a mechanism —
  25–46 per run, the strongest glut-cleaner tested (solar heals fully to 0%) —
  but it is a *stabiliser*, not a shock source: it fires in response to
  distress. Ship it for news + market structure. Nine configurations now
  confirm the §4.5 theorem: zero endogenous cycles anywhere; even ±30% zero-net
  demand waves are absorbed by the event layer (46 acquisitions quietly track
  them).
- **Strict entrant triggers** (≥+30% for 5 turns, or ≥+40% for 2): ~6 per run,
  rare and dramatic, fire into structural premia and post-shock booms. Good
  calibration as specced.
- **Demand growth**: previously implicit (trade closure grows in lockstep with
  rival supply — that is why the baseline world is balanced). The owner's
  net-positive 5-2-3 grow/decay/plateau cycle (+2% per 10 turns above trend)
  is not a cycle generator — it is the **demand-led-growth dial**: steel holds
  a standing +20% premium all game, structural gluts are absorbed (solar → 0%
  by t100), 30 entrants fire, and the steel specialist posts **86% lifetime
  P&L, the best of the series**. A third settings axis (with depth and
  personas), or an era backdrop. At zero-net wobble scale (±10–30%) the same
  cadence is EMA-filtered into nothing.
- **Depreciation and the player**: sims are rival-only ("industry churn" —
  retooling, aging plant, product rotation). The player-side version is the
  planned post-EA maintenance feature (decay slowed by unlocks/advisors/spend;
  skimping cuts output) — same constant, gaining a literal meaning later.
- ⚠️ **Never anchor thresholds to the realized market** (tested R6e/f):
  procyclical depth → consolidation death spiral (84 bankruptcies + 254
  acquisitions per run, specialist P&L 18%). T stays on the expected γ curve.

**R7 — the sawtooth test and the final cycles verdict (13 configurations,
`r7_sawtooth.py` / `r7b.py`):**

- The owner's sawtooth (+10–80% demand over 20 turns at random 0.5–4%/turn,
  −10–50% over 10, plateau 10) compounds net-upward (≈×2.9 demand by t300) and
  produces a **roaring era**, not cycles: everything +25/+35%, 166 entrants,
  steel producer at **132% lifetime P&L** with a 282-turn premium window.
- A balanced variant (each bust unwinds its boom) produces only ±5–10pp
  undulations: a 20-turn ramp gives the ladders/entrants/acquisitions time to
  track it. **Ramps get tracked; steps make cycles.** The champion's staged
  collapse (a step) remains the only ±30pp-class arc producer. Boom-bust
  design: a calendar of **step changes with holds** ("embargo: +30% steel
  demand, effective now, 25 turns") — each step opens a 10–15-turn adjustment
  window of real price movement, and the removal step busts against the
  boom-built capacity.
- **R7c/R7d — the whipsaw trap (`r7cd.py`)**: percentage-label ranges hide
  multiplicative asymmetry. +20–100% booms vs −30–90% busts = E[log] −0.58 per
  cycle → world demand collapses to ×0.03 by t300: a great depression (91
  bankruptcies + 380 acquisitions per run), steel volatility up only 3.0→5.2pp,
  and still zero cycles. Tiered ranges (R7d: raw 20-40/25-35 … apex 20-100/30-90)
  produce a clean tier gradient — but of *depression depth* (apex −39%), the
  inverse of "apex most dynamic". The integrated steel→motor→EV player lands at
  8–11% of baseline with EVs pinned −40%. **Fix**: draw each bust as a fraction
  of the boom it follows (60–110% ≈ balanced; tier by fraction-width — apex
  40–120% wide, raw 70–100% narrow) so tiers become swing amplitude, not
  depression. Apex demand anchoring to a notional 9×base×γ market works.
- **R7e — fraction-drawn tiered sawtooth (`r7e.py`) — the working demand-era
  recipe.** Busts drawn as a fraction of the preceding boom, tiered by width
  (raw 70–100%, processed 60–105%, intermediate 50–110%, finished 45–115%,
  apex 40–120%). The gradient finally points the intended way in both level
  and motion: raw +17% / std 4.9pp → apex +36% / std 10.4pp at t300; demand
  ends ×1.72 above trend; 51 entrants, zero bankruptcies. Tiering the net
  drift upward toward apex also repeals the downstream squeeze: apex demand
  grows fastest, so the integrated steel→motor→EV player's EV climbs to +25%
  (vs pinned −40% under R7d) and they post **82% P&L with zero loss turns**
  — the healthiest player economy of the series. Still no rhythmic cycles
  (16th configuration): motion is tier-scaled undulation around rising
  trends; steps remain the boom-bust tool.
- **R7f — retiring `decay_rate` (same runs re-priced; decay is a pricing
  overlay, impacts run on flows):** ≈ +9% uniform absolute uplift (baseline
  ×1.09, player ×1.08), relative P&L unchanged (82% → 81%). With the market
  model live, decay can retire with minimal rebalance — but note "prices
  always fall" is a recorded deliberate design ruling (pre-market-model);
  R7e+R7f inverts the macro trend to gently rising prices, and the squeeze
  then rests wholly on the carbon levy, port fees and input premia. Make it
  as an explicit era choice.
- **R7g/R7h — the volatility dial (`r7g.py` / `r7h.py`).** Four levers govern
  swing size, ranked: (1) **approach speed** (0.5 → 1.5%/turn — the biggest
  unlock; at 0.5 prices never reach deep targets before the demand phase
  flips); (2) **ladder depth/closeness** (edges 1/1.5/2.5/5×, targets
  ±15/25/35/50); (3) **fraction centering** (E[fraction] ≈ 1 → prices cross
  base both ways instead of trending premium); (4) **demand weight** (β off
  the wobble term). Supply response strength/lag is the brake on all four.
  Measured trade surface (ambient apex std/range · integrated player P&L ·
  loss turns): R7e gentle 10.4pp/~30pp · 82% · 0; R7g lively 13.7pp/51pp ·
  47% · 0; R7h wild **18.9pp/63pp** (±25–40% swings, mid tiers genuinely
  above AND below base) · **18% · 41**. The price of drama is player margin —
  the shipping blend is R7h's ladder+speed with fractions shifted net-up
  (E[frac]≈0.9, raw 80–105% … apex 45–135%), expected ±25–35 swings at
  ~35–50% P&L. Big volatility also promotes stockpiling/warehousing to a
  first-class strategy — check storage-fee economics against it.
- **R7i — the first rhythmic market (`r7i.py`).** R7g + approach 2.5%/turn +
  thresholds re-anchored to *initial* production (static 9×base, edges
  1/4/10/30×). After 18 damped configurations, **the cycle detector fires:
  1,322 extrema, 15–21 per good, median period ≈20 turns** — a relaxation
  oscillator (wave crosses the fixed edge → price snaps onto the ±10 rung in
  ~4 turns → response pulls the ratio back → snaps home → next demand phase
  re-triggers). The quantization + speed that suppressed smooth cycles CREATE
  the rhythm once the anchor stops growing. Character: ±10–20 typical swings
  (apex range 42pp), square-ish steps (hold-jump-hold — very legible),
  free early-calm window (flows grow into the static dead zone), integrated
  player 61% P&L with zero loss turns; event layer goes quiet (deep bands
  need 10×/30× initial — retune exit/entrant triggers if news wanted).
  **The dials are separable: rhythm = static anchor + speed + quantization;
  amplitude = ladder edges/targets.** R7i with edges 1/3/6/15 and targets
  ±15/25/35/50 is the candidate for R7h-scale drama on an R7i pulse.
- **R7j — the settling fix (`r7j.py`).** R7i parks at the first rung in the
  second half (flows grow past the static 1× edge and stay). R7j: 8 log-stepped
  bands (edges 1→30× geometric, targets ±5…±40), exits ≤−15% held 10, entrants
  at **+10%×5t / +20%×2t**, growth response ×1.3 (slowdowns keep ×0.5/×0.75).
  Result: settling fixed emphatically — 2nd-half extrema (263) run 2.5× the
  1st half (103); **140 entrants/run become the market's disciplinarian**
  (every parked premium is an invitation); player 59%, zero loss turns. The
  trade: fine 5pp rungs smooth R7i's snap into 37–77-turn undulations (369
  extrema vs 1,322) — same energy (apex std 12.1pp/range 44pp), rounder
  curves. **Band count is a texture dial** (coarse = legible square-wave snap,
  fine = commodity-chart glide); the anti-parking agent is entrant
  sensitivity, independent of ladder granularity. R7k candidate for snap
  without parking: R7i's 4 coarse bands + R7j's entrant triggers + ×1.3
  growth. Watch the 12-slot cap once entrants fire at this rate — industry
  concentration vs fragmentation becomes a live design surface.
- **R7k — era-scaled entrants, and the absorption asymmetry (`r7k.py`).**
  Entrants sized 1/2/3× base (era 1), 5/8/12× (era 2), 15/25/40× (era 3) —
  intended as price-triggered champion-class supply steps. Measured: **almost
  no effect** (extrema 410 vs R7j's 369, apex stats and player P&L identical).
  Cause: the trade closure — only (1−β)=25% of NPC supply presses prices, so
  a 25×base entrant lands as 6.25×base against a 9×base band edge: 0.7 rungs.
  Demand shocks run at full weight (since R7g); supply shocks whisper. **Fix
  if entrants should be boom-killers: a market-disruption window** — count a
  new entrant's output at full weight for its first ~10–15 turns (world trade
  takes time to re-route around a sudden domestic supplier), then fold into
  normal netting. An era-3 titan then lands ~2.8 edges — premium collapses
  through 2–3 rungs in a few turns. Generalises to any supply event
  (bankruptcy waves, the champion, embargo lifts). Candidate R7l.
- **R7m — apex competition (era 2+) and below-base busts (`r7m.py`).** Apex
  goods join the traded economy via entrants only, from t>100, era-sized, with
  synthetic growth, consuming their recipe inputs; plus the
  **market-disruption window** — entrant output counts at full weight for its
  first 12 turns before trade absorbs it. Measured (β 0.50): first apex entry
  lands t101 every seed (the standing premium is that inviting; 58 apex
  entrants/run); EV flips from premium island to contested market — below
  base 81% of late turns, troughs −30%. Below-base busts arrive
  tier-appropriately everywhere: finished 66% of turns below (p10 −12.8,
  troughs −15.6), intermediate 38% (troughs −10.2), raw gentle (−4.4).
  Emergent era story: the apex industry's input hunger cascades down-chain —
  steel climbs to +22/+23 late ("the nation starts building cars; steel
  booms"); 179 entrants + 73 acquisitions/run. Player: era-1 apex monopoly,
  then a real mid-game shock — P&L 35% with 32 loss turns for the
  *non-adapting* build rotation, but their motor line runs +17% late (the new
  EV industry buys motors): the model rewards pivoting from selling apex to
  supplying it. Gentle knobs if 35% is too harsh: apex entry cooldown 15–20
  or era-2 apex sizes capped at 5/8× — not the disruption window, which does
  the below-base work everywhere.
- **R7n — price-residence census + the Metal Magnate sweep (`r7n_census.py`).**
  Under R7m the ambient market settles into **three persistent regimes**:
  permanent-premium goods (100% of turns above base — steel +16.5, wiring
  +16.5, hydrogen +27, salt +33: the structural-deficit intermediates),
  permanent-glut goods (90–97% below — wind turbines −10.3, alkaline
  batteries, nitrogen, concrete, building frames), and a **two-sided middle**
  that genuinely crosses base (car bodies 37↑/42↓, glass, tyres, EVs) — the
  trading goods. Tier averages: raw 40↑/21↓ · processed 40↑/22↓ ·
  intermediate 42↑/38↓ · finished 24↑/61↓ · apex 67↑/15↓. The census is the
  player's strategy map: sell what lives above, buy what lives below, trade
  what crosses.
  Integration sweep (ore → ingots → steel → motors → EVs, fixed attention
  rotated): P&L £105k → £161k → £306k → **£379k** → £314k — **optimal
  stopping at motors**; the EV step destroys £65k and brings the only loss
  turns (17), because the era-2 contested EV market (−4.1 mean) can't cover
  its premium input basket. Two laws: **integration heals your own gluts**
  (iron ore −11.4 mean as a pure extractor → −1.7 fully integrated — own ore
  stops hitting the market), and **selling into structural premiums barely
  dents them** (full player steel output shaves 3pp off +16.5) while dumping
  into thin raws craters them (ore 6↑/0↓ → 0↑/87↓ at S1).
  **The battery route (`r7o.py`) rewrites the leaderboard**: motors → lithium
  batteries instead of EVs = **£667k, zero loss turns** (batteries are
  permanent-premium, +11.7 held at +10.2 under full player selling);
  batteries-then-EVs = £620k, zero loss turns (internalising batteries removes
  the costliest premium input — the EV step falls from −£65k-with-losses to a
  mild −£47k). Twice confirmed: **supply the EV boom (batteries, motors)
  rather than compete with it**; EVs are for the era-1 monopoly window or
  victory tracks, not margin.
- **The distributional law of demand-led growth**: it blesses goods where
  *rivals* are the marginal supplier and is invisible on the player's own
  good (their expansion absorbs its demand growth — no premium), while inputs
  carry standing premiums. Measured (motor maker, 32 steel + 32 wiring per
  28): **29%** P&L under steady growth, 67% under the sawtooth (18 loss
  turns), **−6%** under the balanced saw (114 loss turns) — vs 86–132% for
  the upstream steel producer in the same eras. Demand eras are
  upstream-seller buffs and downstream-converter taxes; vertical integration
  is the in-fiction answer, but any demand-era setting needs a downstream
  compensation (e.g. final-goods export demand) before shipping.

## 5. Open knobs / follow-ups

- **Band-edge hysteresis (±3–5%)** — calms the exit thermostat and the 4-ish
  price-direction reversals/good that lag+exit introduce.
- **Lag 3** and the champion **loud variant**: specced, not yet simulated.
- Extraction goods are insulated (a demand shock dies crossing a glutted
  processing band — bauxite never moves). If ore booms are wanted: give no-input
  goods a **downstream channel** (watch value-weighted consumer prices), mirror of
  the input channel.
- Apex goods have no NPC market: player-only volume vs γ-thresholds today; they
  get real final-demand curves when world demand ships.
- Power: market impact applies, but grid settlement prices are fixed constants —
  decide whether grid buy/sell should track the market price before wiring NPC
  flows into power.
- The 2026-07 price decay (`decay_rate` CSV column) stays orthogonal for now;
  under a full demand model it becomes emergent and the column can retire.

## 6. Rejected alternatives (why Model P)

- **CUT SETTING — "Competitor Responsiveness" (rival decision lag).** Proposed as
  a 3/5/10-turn game-setup option and simulated as such; on the final R7m ruleset
  it is **provably inert**: apex σ 11.8pp, player P&L 35%, mid-tier range 26.5/26.6/27.0pp
  and extrema 380/386/386 across lag 3, 5 and 10 — i.e. no measurable difference on
  any metric. **Do not ship it.** (`r7p_settings.py`.)
- **CUT SETTING — "Rival Temperament" (persona mix 4/3/2 · 3/3/3 · 2/3/4).** Same
  fate, one notch less severe: P&L 35% in all three, extrema 386/392, and only
  acquisitions move (81 → 62). It *was* a genuine dial on R7k (Plate XV).
- **Root cause for both, worth remembering before re-proposing them:** R7j softened
  the *incumbent* growth response to ×1.3 and handed market discipline to
  price-triggered **entrants**. Both cut settings act only on incumbent behaviour,
  which no longer moves prices. Reviving either means restoring incumbent growth to
  ×2.0 (R7i-era) — a decision about *who disciplines the market*, not a free setting.
  The lesson generalises: **re-measure every setting on the final ruleset**; dials
  calibrated mid-design can be silently zeroed by later changes.

- **Raw NPC flows into the live accumulator** (any threshold variant): saturates —
  every structurally imbalanced good pins at ±40%; integer-rounded threshold
  growth silently freezes all thresholds under 50 units.
- **Full netting (N)**: safe but deletes the overconsumption play (principle:
  players should profit from selling what rivals over-buy).
- **Full ratio (D/S)^k now**: needs a demand model — explicitly deferred to
  post-EA; Model P is its step-function approximation on the same plumbing.
- **Model Q — bandless free-running prices** (drift 0.5%/turn while |net/T| > 1,
  cap ±60%, a ±5%/turn "global demand" state E engaging at −40%/+60% that also
  scales rival responsiveness): produces one beautiful ambient arc (steel:
  +25% boom → corrected → par) and fails everything else. Measured (3/3/3, lag 5,
  β 0.75): ambient mean |impact| 19.5% (P: 9.5), 23 goods beyond ±30, median
  swing 36pp; hydrogen pinned at +60% for 183 straight turns (the stabiliser
  saturates at 2×T of demand vs a ~13×T structural deficit); solar saws −25↔−45;
  the steel specialist ends at **14% P&L with 70 loss-making turns** (P: 68%,
  zero). Root causes: flat drift speed (a 1.1× imbalance travels as fast as a
  10× flood) and a hard-trigger, budget-capped stabiliser. Fixing both — drift
  proportional to pressure, stabiliser graduated with distance from base — *is*
  the continuous demand curve: bandless-with-stabilisers converges to the ratio
  model. The bands are the EA-simple stand-in for that curve, not decoration.
  Q's E-mechanism is a good seed for the post-EA final-demand term, engaged
  gradually rather than in extremis. Sim: `tools/market_model/model_q.py`.

## 7. Reproduction, and the evidence behind each shipping stage

```bash
# regenerate the engine dump (goods, base recipes, band constants, seeded rival draws)
<godot> --headless --path . res://tools/npc_market_dump.tscn --quit-after 600
# then any analysis, e.g. the current candidate ruleset:
python3 tools/market_model/r7m.py
```

**Stage → evidence map** (stages as listed in the header; plates are in the
"If the Rivals Traded" artifact):

| Update stage | Plates | Scripts |
|---|---|---|
| 0 · why not the current model | I–V | `npc_price_model.py`, `headtohead.py`, `netting_and_ratio.py`, `tier1_model.py` |
| 1 · Living market (Model P + R4) | IX–XV | `model_p.py`, `model_p_response.py`, `response_variants.py`, `r4_model.py`, `r4_mixes.py` |
| 2 · Industry churn (depreciation, bankruptcy, acquisitions, entrants, disruption window) | XIX, XX, XXVII, XXIX | `r5_cycles.py`, `r5b_cycles.py`, `r6_demand.py`, `r7k.py`, `r7m.py` |
| 3 · World demand (tiered fraction-drawn cycle) | XXI–XXIII | `r7_sawtooth.py`, `r7b.py`, `r7cd.py`, `r7e.py` |
| 4 · Apex competition from era 2 | XXIX–XXX | `r7m.py`, `r7n_census.py`, `r7o.py` |
| 5 · Settings + market events | XVI, XXIV–XXVIII | `settings_and_champion.py`, `cap60_sweep.py`, `r7g.py`, `r7h.py`, `r7i.py`, `r7j.py`, `r7l.py` |
| — · P&L and player-experience checks | XII, XXX | `profit_steel.py`, `r7n_census.py`, `r7o.py` |
| — · rejected: bandless free-running prices | XVIII | `model_q.py` |
| — · edge cases (player-only goods, ore chains) | XI | `edgecases.py` |

**The current candidate ruleset is R7m** (`r7m.py`): static thresholds anchored to
initial production, 8 log-stepped bands, 2.5%/turn approach, tiered fraction-drawn
demand, era-scaled entrants with a 12-turn market-disruption window, apex
competition from era 2, β 0.50, depreciation + acquisitions + bankruptcies.
`r7n_census.py` / `r7o.py` produce the price-residence census and the Metal
Magnate integration atlas on top of it.
