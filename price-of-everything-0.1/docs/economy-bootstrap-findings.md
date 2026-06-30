# Economy bootstrap findings — can you build the full chain from a cold start?

> Companion to [`goods-balancing.md`](goods-balancing.md). That doc covers *per-good /
> per-recipe* balance (flat-single, profitable-integrated). This one covers the **whole-company
> bootstrap**: starting from an empty position, can a player actually build out a complete
> production chain before going bankrupt — and what does the economy need so that they can?

The reference chain throughout is the **motor chain** (the deepest cheap-to-reach EA chain):

```
coal ─┐
iron_ore ──► pig iron ──► steel ─┐
copper_ore ─► copper ingots ─► copper wiring ─┤
pure_water ─► power                           ├──► motor
                                              ┘
```

10 buildings, ~£1,315 of construction materials when bought at market.

---

## How this was measured

A headless **build-order sweep** (`scratchpad/buildorder_sweep.py`, not shipped) models the
company turn-by-turn against the *real* economy numbers:

- Per-recipe economics are read from the `chain_profit` harness output (`tools/chain_profit.gd`)
  plus the live `Goods` / `Buildings` / `recipes_all` CSVs — same cost model as the game
  (labour + maintenance + energy + transport; own-power vs grid; the −50% deposit malus on mines).
- The company is simulated as a per-turn goods-flow: surplus sold to market, deficits bought at
  the 5% markup, power settled at grid buy/sell (£1.0 / £0.6).
- **Loans** follow the game rules: capacity = base £50 + 50%·built-building-value + the
  profit/revenue logic. The sim can only borrow against that capacity.
- **Bankruptcy** = loan capacity maxed out *and* losing money for 5 consecutive turns.
- It sweeps **6 build orders** (coal-first, all-mines-first, iron+copper-first, steel+wiring-first,
  motor-end-first, and a "mine-sell-build" trader order) and reports, for each: turn it first
  goes net-positive, buildings/spend/debt at that point, and the bankruptcy turn if it dies.

"Profitable" = the first turn with a **positive per-turn net** (after loan payments).

---

## Finding 1 — the chain is healthy *when complete*

Fully built and integrated (own power, no market markup on internal inputs), the motor chain
runs **+£59/turn** at the −20% mining-malus floor. All intermediates net to ~zero; the margin
lives in the apex (motors) plus surplus power. This is the rebalance working as designed: you
*can't* profit from one standalone factory, only from owning the chain.

## Finding 2 — but the **cold start is a wall**

The problem is getting there. Every build order has to pass through a stretch of half-built,
loss-making company before the chain closes:

- A lone mine earns **£12 at half output** (−50% malus) but carries ~£14 of fixed labour +
  ~£3 energy → **−£5/turn each**. The malus only lifts once **all three** mines exist.
- The apex-first orders (build the motor factory first, buy everything at market) bleed even
  harder — they run loss-making finished-goods buildings with no upstream to feed them.

Result, at the **£200 default start** (`EconomyConfig.STARTING_MONEY`): **no viable order.**
£200 + initial loan capacity funds ~2 buildings, which isn't enough to close *any* loop before
bleeding out. Every order bankrupts between turns 9–17.

This is the same signal as the `e2e_stoneshore` net-negative buildout: the rebalance left the
economy *correct per-recipe* but *unforgiving at the company level*.

---

## Finding 3 — what makes it viable

Three levers, stacked, turn the bootstrap from "impossible" into "forgiving":

### a) Seed capital ≈ £500–600 (not £200)
Enough to fund the first ~3 buildings — critically, all three mines — so the malus lifts and the
company flips cash-positive before the loans max out. At £600 the **mine-first** orders are
profitable by **turn 3, zero debt**. (Apex-first orders still struggle — see lever (c).)

### b) Special orders (a proposed feature, not yet in-game)
A temporary, player-only demand spike: the market asks for a quantity of one good over a short
window and pays a premium. Modelled as **coal @ turn 5 (+40%)** and **iron @ turn 10 (+30%)**,
each window sized to *one mine's* output over ~5 turns so you can service it without reshuffling
your whole industry. Worth ~**£60** of bootstrap cash injection — and it rewards the mine-and-sell
opening that the early game naturally wants. **This concept does not exist in the codebase yet**;
it's the single highest-leverage *new* mechanic for the cold start.

### c) The people-management labour track ✅ **(implemented in this PR)**
Labour cost is the bootstrap killer — it's a fixed % of build value that you pay whether or not
the building is integrated, and unlike power **it can't be internalised**. So we let the player
*earn* labour efficiency by scaling up:

| Unlock | Condition | Effect |
|---|---|---|
| **Operational Team Managers** | own **3** buildings (any type) | −5% labour, all buildings |
| **Shift Handover Documentation** | own **12** buildings (any type) | −5% labour (−10% total) |

The −5% tier fires at exactly the moment the early losses bite (right after the first couple of
buildings) and **rescues the worst build orders from bankruptcy**:

| order (start £600) | baseline | + labour track |
|---|---|---|
| coal-first | profit @3 | profit @3 |
| all-mines-first | profit @3 | profit @3 |
| iron+copper-first | profit @5 | profit @5 |
| steel+wiring-first | profit @12, £798 debt | profit @11, £771 debt |
| **motor-end-first** | **bankrupt @13** | **profit @10** ✓ |
| mine-sell-build | profit @3, end £480 | profit @3, end £549 |
| **complete chain net** | **+£59.0/turn** | **+£63.3/turn** |

Every order is now viable; the perverse "apex factory first" order survives instead of dying.
The second tier (−10% at 12 buildings) is deliberately out of reach for a *single* 10-building
chain — it's a reward for running a **larger** operation (multiple chains / a deep industry).

> The labour track **does not** rescue the £200 start on its own — at £200 every order still
> bankrupts (turns 9–17). It widens the margin; it doesn't replace the need for seed capital +
> special orders. The three levers are complementary, not substitutes.

---

## Lever comparison (why we picked the labour track)

| lever | complete-chain net | fixes cold start? | rule-preserving? | cost |
|---|---|---|---|---|
| baseline | +£59.0 | no (£200 dies) | — | — |
| flat global labour −10% | +£67.5 | yes (all orders) | bends flat-single | intermediates drift +ve standalone |
| **people-mgmt labour track** | **+£63.3** | partial (rescues weak orders @£600) | yes (earned by scale) | none — it's a research reward |
| power-shift (5% labour→power) | +£60.7 | no | yes | small (+3%), high-touch data pass |

The **people-management track** wins: it gets most of the flat-cut's bootstrap benefit, but as an
*earned* reward tied to growth rather than a free global handout, so it doesn't quietly make every
standalone intermediate profitable (which would undo the goods-balancing work).

---

## Implemented here

- **Two research unlocks** in `data/research_unlocks.csv` under the existing *People Management*
  category, gated on **total buildings owned** (3 / 12) rather than a specific building type.
- They route through the existing `ModifierState.UNLOCK_MODIFIERS` → `labour_headcount` domain
  (same path as `Safety Training`), so the −5% lands in `Production._calculate_labour_cost` with
  no new machinery, and saves/loads for free.
- A small **`"any"` wildcard** in `MatchState._count_buildings` so a `Build` condition can gate on
  *total* buildings, not one type.

Verified end-to-end headless: at 3 buildings labour 100 → **95.0**; at 12 buildings → **90.0**.
Unit suite green (860/860).

---

## Designed but **not** in this PR (the remaining viability work)

1. **Special orders** — the player-only demand-spike feature from lever (b). Highest-leverage new
   mechanic for the cold start; needs design + implementation (market hook, UI, the
   service-and-reward loop).
2. **Power-shift (5% of labour → power consumption)** — small integration sweetener (+~£2/turn on
   the complete chain), rewards owning your power because power *is* internalisable. Deferred: it's
   a per-recipe `energy_req` data pass for a +3% effect and would move power-dependent test numbers.
   A clean way to apply it later is a permanent global `building_power` +X% / `labour_headcount`
   −5% modifier pair seeded at match start (mirrors the deposit-penalty seeding), rather than
   editing every recipe row.
3. **Grid oversupply glut + per-tile wind/solar potential** — overselling power should crater the
   grid price (toward ~10% of base, mirroring the global-market glut); buying shouldn't move it.
   Until the glut exists, the **mine-and-sell trader order out-earns the full chain** (£549 vs the
   chain's slow build) — refining doesn't yet clearly beat dumping raws. (Carry-over from the
   goods-balancing pending list.)
4. **Lower the starting cash question** — either raise `STARTING_MONEY` toward ~£500–600, or keep
   £200 and rely on special orders + an early market-buy warm-up to bridge the gap. This is a
   design call, not just a number.

---

## Reproduce

```bash
# per-recipe economics (committed harness)
<godot> --headless --path . res://tools/chain_profit.tscn --quit-after 200   # writes rp.csv rows

# whole-company build-order sweep (scratchpad, not shipped)
python3 scratchpad/buildorder_sweep.py rp.csv 600    # 6 orders @ £600 start
```
