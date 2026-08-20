# Recipe Rebalance Spec — non‑MVP recipes (`r_013`+)

Status: **draft for review.** This locks the *method* on one full vertical (the
aluminium spine) before rolling it out to all ~165 non‑MVP recipes. Nothing in
live data changes until the framework below is approved.

Scope: every recipe from `r_013` onward in
[`data/recipes_all.csv`](../data/recipes_all.csv). Those rows are generated from
[`data/recipes_master_source.csv`](../data/recipes_master_source.csv) by
[`scripts/build_recipes_all.py`](../scripts/build_recipes_all.py); `r_001`–`r_012`
(the MVP recipes) are hard‑coded in that script and **are not touched**. The
source of truth to edit is therefore `recipes_master_source.csv` (recipe rows) +
`Goods - goodsMVP.csv` (good prices). Goods prices are global, so a few early
goods are shared with MVP — those are flagged.

---

## 1. Objective

Three behaviours, in the designer's words:

1. **Unintegrated is inefficient.** Buy every input at the market and pull power
   from the grid → margin is thin or negative.
2. **Integration pays.** Self‑generate power *and* self‑produce inputs → the same
   recipe becomes solidly profitable.
3. **Depth rewards.** The later in the supply chain a good sits, the higher its
   *fully‑integrated* margin — **capped at 40 % in all cases.**

Levers I'm allowed to move (recipe + price only): `energy_req`, the input/output
quantities (ratios + batch size), and output good `base_price`. Building costs,
labour, and the grid/market constants are fixed.

---

## 2. The economic model as built

Confirmed from [`economy_config.gd`](../scripts/economy_config.gd),
[`power.gd`](../scripts/power.gd), [`market_state.gd`](../scripts/market_state.gd),
[`production.gd`](../scripts/production.gd):

| Lever | Value | Consequence |
|---|---|---|
| Grid power **buy** | **£1.00 / unit** | Pulling shortfall from the grid is expensive. |
| Grid power **sell** | £0.60 / unit | Surplus self‑power dumps cheap. |
| **Self‑power cost** | **≈ £0.15 / unit** | Own coal/gas plant + fuel (derivation below). ~6–7× cheaper than grid. |
| Market **buy markup** | **+5 %** | Every purchased input costs `price × 1.05`; you sell at `price × 1.00`. |
| Fixed cost / building / turn | **£2.8 – £5.6** (turn 1) | maintenance (`×2` multiplier) + labour stub. Grows ~0.2–0.4 %/turn. |
| Tax / dividend | 20 % / 20 % | Company‑wide, post‑profit. Not modelled per‑recipe. |

**Self‑power derivation.** Coal plant `r_004`: `20 coal + 6 water → 100 power`,
plant fixed ≈ £6.78/turn. With self‑mined fuel the batch resolves to
**≈ £0.10/unit**; buying coal/water at market ≈ **£0.30/unit**. The spec uses
**£0.15** as the "fully integrated" reference and **£1.00** as the grid
(unintegrated) reference. *This single 6–7× gap is the primary integration prize
for energy‑heavy recipes.*

**Fixed cost is why tiny batches die.** Many master‑source recipes output 1–6
units. At £4.8/turn fixed, a recipe selling 3 units of a £5 good (£15 revenue)
burns 32 % of revenue on fixed cost before inputs. **Batch sizes must be
normalised** so fixed cost lands at ~5–12 % of revenue — this is half of "fixing
the I/O ratios."

Fixed cost per building (turn 1), used throughout:

| Building | maint ×2 | labour (turn 1) | **fixed/turn** |
|---|---|---|---|
| mine | 2.0 | 0.8 | **2.8** |
| furnace | 4.0 | 0.8 | **4.8** |
| eaf / electrolyser / assembly / high_tech / water_pump / poly / petro | 4.0 | 0.8 | **4.8** |
| chem_plant / industrial_factory | 4.0 | 1.6 | **5.6** |
| coal_power | 2.0 | 4.78 | **6.78** |

---

## 3. The framework

### 3a. Energy ladder (real‑world anchored)

`energy_req` is a **per‑batch** 0–20 score. Aluminium primary smelting — the most
electricity‑intensive industrial process on earth (~13–15 kWh/kg) — pins the
top at **20**. Everything else is ranked by real specific‑energy class:

| energy_req | Process class | Real‑world basis |
|---:|---|---|
| **20** | Aluminium primary smelting (Hall‑Héroult, carbothermic, ELYSIS) | ~13–15 kWh/kg — the global benchmark |
| **14–18** | Polysilicon (Siemens), metallurgical‑silicon arc, water electrolysis (H₂), REE electrolysis | electro‑intensive, 11–60 kWh/kg |
| **10–14** | EAF steel, electric calcination, methane pyrolysis, high‑strength glass | electric‑arc / very high temp |
| **8–12** | Glass melting, Bayer (alumina), Haber‑Bosch (ammonia), chlor‑alkali *(MVP=10)*, electric concrete | high heat / electrochemical |
| **4–8** | Petro refining (distillation, cracking, coking), polymerisation, fermentation, pulping | moderate process heat |
| **3–5** | Manufacturing & assembly (components, motors, windows, cars, toys, packaging, battery assembly) | low — mostly mechanical/electrical |
| **2–4** | Mining, pumping, mechanical recycling, farming, forestry | low |

The headline finding (§4) is that **most current `energy_req` values are far too
flat** — aluminium currently sits at 8 when it should be the 20 anchor. Fixing the
energy ladder is what creates the unintegrated penalty on energy‑heavy goods; with
proper batch sizes it barely moves their *price* (§4).

### 3b. Supply‑chain tiers → integrated‑margin **band** (per recipe, not per good)

Each good gets a **tier** = longest path from a raw deposit. The *fully‑integrated*
margin rises with tier and caps at 40 %. These are **approximate bands, not exact
targets** — in‑game modifiers and tech upgrades move the player well past these
base numbers early, so the job is to get the *shape* right (unintegrated thin,
integrated rising, capped ~40 %), not to hit 20.0 % on the nose.

| Tier | Examples | Integrated margin **band** |
|---:|---|---:|
| 0 — raw | ores, sand, limestone, salt, water, crude oil | **5–10 %** |
| 1 — primary | ingots, alumina, NaOH/chlorine, silica, processed oil | **10–15 %** |
| 2 — refined | steel, **aluminium**, glass, plastics, ethylene | **16–22 %** |
| 3 — components | motor, electrical components, windows, car body, engine | **24–30 %** |
| 4 — assemblies | building frame, solar panels, batteries, CPU, cars | **30–36 %** |
| 5 — top hi‑tech | computer, medical components, AI chip, EV car | **36–40 % (cap)** |

**Margin is assigned per recipe, not per good.** Many goods have several recipes
(aluminium: Hall‑Héroult / ELYSIS / carbothermic; steel: BOS / EAF / HIsarna /
DRI; batteries; engines…). The **basic / early / MVP‑adjacent recipe sits at the
bottom of its band (and may run as low as 0–5 % — deliberately thin, even for an
"advanced" good);** the advanced/unlockable recipe sits at the top. This is what
makes early game lean and rewards teching into the better process — and it's why
the MVP recipes are intentionally low‑margin.

### 3b‑i. Batch‑size rule (so percentage modifiers survive integer rounding)

Output qty is multiplied by a modifier then `int(round(…))`
([production.gd:446](../scripts/production.gd)), so a 5 % modifier on a small
batch rounds away to nothing (5 → 5.25 → **5**; 20 → 21 → lands). Batches are
therefore floored by tier:

| Tier | Output batch | Why |
|---:|---|---|
| 0–2 (raw → refined) | **20–30** | a 5 % modifier must land; these are high‑volume goods |
| 3 (components) | **10–20** | taper as goods get more valuable |
| 4–5 (assemblies / top hi‑tech) | **≥ 5 (hard floor)** | only ≥10 % modifiers land here, by design |

Inputs scale with the batch. A pleasant side‑effect: **bigger batches amortize
fixed cost + energy over more units, so the energy anchor no longer inflates
absolute prices** — it does its real job of punishing *grid* power per batch
while self‑power stays cheap.

### 3c. Bottom‑up cost recursion

For each good, **integrated cost**:

```
C(good) = ( Σ C(input)·qty  +  energy_req · £0.15  +  fixed_cost ) / output_qty
```

Raw goods have no material inputs, so `C(raw) = (energy·0.15 + fixed) / qty`
— small. Costs propagate up the tree.

**Joint products** (e.g. chlor‑alkali → chlorine + NaOH + hydrogen) split the
batch cost across outputs **by market value** (standard cost accounting):
`C(out_i) = batch_cost · value_i / Σ value`.

### 3d. Price formula

```
P(good) = C(good) / ( 1 − margin_target(tier) )
```

Because `C` already embeds the *entire* upstream chain at true cost, pricing the
final stage at `1/(1−0.40)` means the **whole‑chain integrated margin is exactly
≤ 40 %** — no runaway compounding. Deeper tiers get a higher target, so deeper
goods are more profitable when integrated. Goal 3, by construction.

### 3e. The two margin read‑outs

For any recipe, revenue `R = Σ P(out)·qty`:

- **Integrated margin** `= (R − Σ C(in)·qty − energy·0.15 − fixed) / R`
  → lands in the recipe's band by construction (basic recipe → low, advanced → high).
- **Unintegrated margin** `= (R − Σ P(in)·1.05·qty − energy·1.00 − fixed) / R`
  → falls out *much* lower, because purchased inputs carry their own margin +5 %
  markup, and grid power is 6–7× self‑power.

The gap between them is the integration prize. It comes from two physically
distinct sources, and the framework reproduces both:

- **Energy‑bound recipes** (smelting): the prize is mostly the £1.00→£0.15 power
  gap. Big `energy_req` ⇒ brutal unintegrated penalty.
- **Materials‑bound recipes** (assembly): the prize is mostly capturing the
  expensive inputs' margins instead of buying them retail.

---

## 4. Validated vertical — the aluminium spine (proper batches)

Rebalanced recipes at the §3b‑i batch sizes. Self‑power £0.15, grid £1.00, markup
5 %. Raw prices held at the existing "ore ≈ £1" convention; tier ≥1 priced by the
ladder. (`graphite` is a placeholder C = 1.2 until the carbon vertical is done.)

### Rebalanced recipes

| Good (tier) | Building | Recipe (rebalanced) | batch | energy_req |
|---|---|---|---:|---:|
| bauxite_ore (0) | mine | → bauxite | 30 | 3 |
| sand (0) | mine | → sand | 30 | 2 |
| limestone (0) | mine | → limestone | 30 | 4 |
| sodium_hydroxide (1) | chem_plant | *(MVP chlor‑alkali, joint)* | 18 | 10 |
| **alumina (1)** | chem_plant | 48 bauxite + 16 NaOH → **24 alumina** | 24 | **10** |
| **aluminium (2)** | eaf | 40 alumina + 6 graphite + 6 chem_salts → **20 aluminium** | 20 | **20** ← anchor |
| **glass (2)** | furnace | 40 sand + 8 NaOH + 8 limestone → **24 glass** | 24 | **12** |
| **windows (3)** | industrial_factory | 30 glass + 15 aluminium → **20 windows** | 20 | **5** |

### Costs, prices, margins

| Good | C (int. cost) | **P (new)** | P (current) | Unintegrated margin | Integrated margin |
|---|---:|---:|---:|---:|---:|
| alumina | 0.66 | **0.77** | 2.20 | ≈ −5 % | 14 % |
| **aluminium** | **2.11** | **2.64** | **2.80** | **−28 %** | **20 %** |
| glass | 0.56 | 0.70 | 2.50 | ≈ −3 % | 20 % |
| **windows** | 2.74 | **3.81** | 12.50 | **+2.6 %** | **28 %** |

### What this demonstrates

- **The energy anchor now corrects *behaviour*, not price.** At a 20‑unit batch,
  aluminium's honest price is **£2.64 ≈ the current £2.80** — the earlier £6.75
  was a tiny‑batch artifact. The 20 power still bites: it's a £20 grid bill on a
  ~£53 batch, which is exactly what makes **unintegrated aluminium −28 %** while
  **integrated is +20 %** (self‑power turns that £20 into £3).
- **Unintegrated is punished where physics says it should be.** Aluminium
  (energy‑bound) loses on grid power; **windows (materials‑bound) is only +2.6 %**,
  and there the penalty is the 5 % markup on expensive aluminium, not power.
- **Integrated margins climb with depth and stay capped:** alumina 14 % →
  aluminium 20 % → windows 28 % → (… solar/cars ~34 % → top hi‑tech 40 %).
- **Big batches make intermediates genuinely cheap** (alumina 0.77, glass 0.70):
  the current hand‑set prices (2.20, 2.50, windows 12.50) are simply too high to
  be internally consistent. The fix lowers mid‑chain prices — see §5.

---

## 5. The one knob left — absolute price scale

The framework fixes *relative* prices and every margin. The **absolute level is a
free constant `K`**: multiply the whole tier‑≥1 ladder by `K` and no margin or
ratio changes — only money‑flow does. So this isn't a "which philosophy" choice
anymore, just a dial:

- **K = 1 (pure formula).** Cheap, high‑volume economy: alumina 0.77, glass 0.70,
  windows 3.81. Internally perfect; lower money‑flow than today.
- **K chosen to anchor a reference good.** e.g. pick `K` so steel keeps its
  current £2.25 (≈ K 1.4–1.6), and the rest of the value‑added layer scales with
  it — keeps today's money‑flow feel while still being internally consistent.

Raw prices stay at the current convention either way (they're the buy‑anchor and
mostly bought, not made). MVP‑shared goods (steel, copper line, NaOH, chlorine,
hydrogen) keep their current sale price; their *integrated cost* `C` is still
computed low, so self‑producing them remains the integration win.

**Recommendation:** K anchored to steel (keeps money‑flow familiar). Confirm `K`
(or "K = 1") and I'll roll the framework out vertical‑by‑vertical per §6.

---

## 6. Rollout plan (after this is approved)

The full set, grouped by vertical so each is internally consistent before the
next:

1. **Metals & ores** — iron/copper/steel line *(MVP‑adjacent)*, aluminium ✅,
   alloy metals, rare earths, lithium.
2. **Chemicals & gases** — chlor‑alkali family, acids, ammonia/fertiliser, oxygen/nitrogen.
3. **Petro & polymers** — distillation → cracking → ethylene → plastics/PVC/rubber → tires.
4. **Glass & construction** — silica → glass → windows ✅ → building frame, concrete.
5. **Silicon & electronics** — silica → silicon → polysilicon → circuit board → CPU → computer.
6. **Power generation** — coal/gas/wind/solar/hydrogen/waste (energy_req = 0, priced on supply).
7. **Batteries & EV/auto** — lithium/sodium/flow/solid batteries, engines, car bodies, cars.
8. **Bio, agri, paper, consumer** — farming, forestry, fermentation, pulping, toys, packaging, medical.

Deliverable per vertical: a table like §4 (rebalanced recipe + C + P + both
margins), then the consolidated `recipes_master_source.csv` and
`Goods - goodsMVP.csv` edits.

### Resolved by the design principles

- **Margin curve:** approximate bands, not exact — modifiers/tech do the lifting.
  Early/MVP‑adjacent recipes deliberately thin (bottom of band, down to ~0–5 %).
- **Batch sizes:** fixed rule (20–30 tier 0–2; 10–20 tier 3; ≥5 tier 4–5) so 5–10 %
  modifiers land after `int(round)`.
- **The ~40 unpriced goods** (graphite, silicon, CPU, batteries, cars, …): priced
  via the ladder — in scope (required to price their outputs).
- **Pricing philosophy:** collapsed to the single scale knob `K` (§5).

---

## 7. Generated output (full rollout)

The framework is implemented in [`scripts/rebalance_recipes.py`](../scripts/rebalance_recipes.py)
— re-runnable, so every knob (energy ladder, tier, price band, batch rule,
self‑power) is one edit away. It reads `recipes_all.csv` and writes:

- **[`docs/recipe-rebalance-table.md`](recipe-rebalance-table.md)** — the full
  review table: all 165 non‑MVP recipes (+ MVP for context), grouped by tier,
  each with rebalanced inputs / energy / outputs / price and both margins.
- **[`data/recipes_rebalanced.csv`](../data/recipes_rebalanced.csv)** — drop‑in
  replacement for `recipes_all.csv` (same columns/ids; r_001–r_012 untouched).
- **[`data/good_prices_rebalanced.csv`](../data/good_prices_rebalanced.csv)** —
  every good's tier, integrated cost C, and new price.

### Final knobs used
Price bands £1–4 (tiers 0–2) · £3–10 (3) · £5–20 (4) · £7–55 (5); batches
20/20/20/10/5/5; energy ladder per §3a; self‑power £0.15; markup 5 %.

### Premium yields (§3b extension)
Premium recipes earn their edge as **extra output, same inputs** — `YIELD_BONUS`
in the generator, +10 % (a little better) to +50 % (best‑in‑class). Inputs are
sized to the *base* yield, so the bonus is a pure ratio win that lands as margin
(because the good's price is anchored by its basic recipe). Three rationales:
- **Substitution** away from scarce/expensive inputs — magnetless motors (no REE,
  +30 %, now the best motor at I 62 %), uPVC windows (no aluminium, +20 %, beats
  aluminium windows), sodium/iron batteries (no lithium, +30 %).
- **Regulation/carbon‑tax‑proof** — green steel/aluminium (EAF, ELYSIS, +20 %),
  EV car & EV equipment (+30 %), SAF biofuels (+20 %).
- **Efficiency** — membraneless electrolysis, 3D‑printed CPUs/carbon‑fibre,
  triple‑tandem solar (+50 %, the flagship at I 46 %).

### Waste as feedstock (your prices)
`waste_water £0.1 · bio/municipal £0.5 · scrap & e‑waste £2` — but the **buy price
is split from the integrated cost**: self‑generated waste is a near‑free byproduct
(`WASTE_C` ≈ £0.05–0.3), so recycling pays **only when you feed it your own
waste** (scrap → steel I 72 % integrated vs **U −49 % when bought**). Needs
`is_buyable=TRUE` on these goods in the goods CSV. Scarce **REE & lithium held at
£4** so substituting away from them — and recycling them — is actually worth it.

### Does it hit the goals?
- **Unintegrated is inefficient** — U% negative/thin on essentially every
  processed recipe; energy‑heavy ones brutal (Bayer −268 %, REE reduction −271 %).
- **Integration pays, scaling with depth** — I% climbs to 33–38 % at tiers 4–5.
- **Premium recipes clearly dominate their basic sibling** via the yield edge.

### Flags — game‑design decisions, not numbers
1. **Premium & structural recipes now exceed the 40 % cap (by design?).** The cap
   holds for deep multi‑input goods (tiers 4–5 = 33–38 %), but three groups run
   higher and it's mostly *not* the yield bonus: **(a)** raw extraction (I ≈ 84 % —
   no inputs to integrate, just the sell margin on a £1‑floored good); **(b)**
   held‑MVP goods whose prices are generous vs cost (steel I 76 %, motor recipes);
   **(c)** premium/teched recipes (magnetless 62 %, 3D‑print CPU 55 %). Decide:
   is >40 % the intended reward for teching/integrating up (you *did* ask for +50 %
   yields), or should the cap bind everywhere (which means repricing held‑MVP goods
   down and lowering raw prices)?
2. **A handful of recipes need to become DISTINCT premium goods, not just +yield.**
   When a recipe makes the *same* good from much pricier inputs, the yield bonus
   can't save it because the good's price is set by the cheap basic recipe:
   lightweight/superlight car bodies (r_069/r_070), hybrid & H₂ engines
   (r_074/r_089). These fit your "EV/electric = better goods" framing — model them
   as separate goods (like `ev_car` vs `ice_car`) that sell higher.
3. **Green fuels look thin statically but win via the carbon tax.** Biofuels/SAF
   (r_140/r_152–155) can't beat petro `fuels` (£1) on static price — but petro
   carries `co2_tax_multiplier` (already in the goods CSV) that my static margins
   don't model. The regulatory ratchet is what tips them; leave as‑is.
4. **One genuinely bad recipe:** Micro Algae Digestion (r_155, I −141 %) — lots of
   inputs for cheap ethylene. Recommend dropping or redesigning.
5. **Goods‑CSV expansion required to go live.** Only 40 of ~100 goods exist in
   `Goods - goodsMVP.csv`; the other ~60 need full rows added (transport class,
   category, decay) before their recipes leave the dormant state. Prices ready in
   `good_prices_rebalanced.csv`. Also: flip `is_buyable=TRUE` on the waste goods,
   set pure_water sell to £0.5 (already), REE/lithium to £4.

### Applying it (next step, on your OK)
1. `cp data/recipes_rebalanced.csv data/recipes_all.csv` (or backport the new
   quantities/energy into `recipes_master_source.csv` and re-run
   `build_recipes_all.py`).
2. Merge `good_prices_rebalanced.csv` into `Goods - goodsMVP.csv` (update the 40
   existing rows; add the ~60 missing goods).

### Resolved knobs
- **Price scale:** superseded by your explicit per‑tier price bands (§7 final knobs).
- **Self‑power:** £0.15/unit (own plant + cheap fuel).
